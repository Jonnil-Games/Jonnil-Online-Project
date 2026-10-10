#region /* Display Fonts and Input Filtering */
/// @description Get the authored primary UI font
/// @returns {Asset.GMFont} fnt_ui
function scr_render_text_primary_font()
{
	return fnt_ui;
}

/// @description Try the bundled CJK font, then installed alternatives and cache the first result for this runtime
/// @returns {Real} Fallback font handle, or -1 when no candidate loads
function scr_render_text_fallback_font()
{
	/* Reuse the cached result after the first font search, including -1 when every candidate failed */
	if (variable_global_exists("text_fallback_font_checked"))
	{
		return global.text_fallback_font;
	}

	/* Mark the search as attempted before loading
	text_fallback_font starts at -1 for no usable font, and text_fallback_font_name stays empty until a candidate succeeds */
	global.text_fallback_font_checked = true;
	global.text_fallback_font = -1;
	global.text_fallback_font_name = "";

	/* Try bundled CJK file paths first, then installed Windows font names, preserving this fallback priority */
	var candidates = [
		"Fonts/NotoSansCJKjp-Regular.otf",
		"NotoSansCJKjp-Regular.otf",
		"Yu Gothic UI",
		"Meiryo"
	];

	/* Visit each zero-based candidate in order until one font_add call succeeds */
	for (var i = 0; i < array_length(candidates); i++)
	{
		/* candidate is the current file path or installed font name, and handle starts at -1 for a failed load */
		var candidate = candidates[i];
		var handle = -1;

		try
		{
			handle = font_add(candidate, 100, false, false, 32, 128);
		}

		/* A thrown font load leaves handle at -1 so the next candidate can be attempted */
		catch(e)
		{
			handle = -1;
		}

		/* Cache the first usable runtime font and its name, then stop searching */
		if (handle != -1)
		{
			global.text_fallback_font = handle;
			global.text_fallback_font_name = candidate;
			break;
		}
	}

	return global.text_fallback_font;
}

/// @description Get the shared per-font and per-code-point glyph cache
/// @returns {Struct} Mutable Boolean glyph results
function scr_text_font_glyph_cache()
{
	/* Create the shared glyph-result struct only once, starting empty until fonts and characters are inspected */
	if (!variable_global_exists("text_font_glyph_cache"))
	{
		global.text_font_glyph_cache = {};
	}

	return global.text_font_glyph_cache;
}

/// @description Check the code-point range permitted for Latin-1 fallback
/// @param {Real} code Character code point
/// @returns {Bool} Whether the code point belongs to those ranges
function scr_text_code_is_latin1(code)
{
	/* Allow the printable/control-adjacent Latin-1 range used by fallback eligibility, from code 32 through 255 */
	return code >= 32 && code <= 255;
}

/// @description Check the selected Japanese and CJK fallback ranges
/// @param {Real} code Character code point
/// @returns {Bool} Whether the code point belongs to those ranges
function scr_text_code_is_japanese(code)
{
	/* These code-point ranges include CJK punctuation, hiragana, katakana, bopomofo, CJK ideographs,
	halfwidth katakana and fullwidth forms for the fallback font */
	return (code >= 12288 && code <= 12351)
		|| (code >= 12352 && code <= 12447)
		|| (code >= 12448 && code <= 12543)
		|| (code >= 12544 && code <= 12591)
		|| (code >= 13312 && code <= 19903)
		|| (code >= 19968 && code <= 40959)
		|| (code >= 65377 && code <= 65439)
		|| (code >= 65280 && code <= 65519);
}

/// @description Check punctuation, arrows and geometric-symbol fallback ranges
/// @param {Real} code Character code point
/// @returns {Bool} Whether the code point belongs to those ranges
function scr_text_code_is_common_symbol(code)
{
	/* Permit the selected punctuation, arrows and geometric-symbol ranges for fallback rendering */
	return (code >= 8208 && code <= 8231)
		|| (code >= 8240 && code <= 8254)
		|| (code >= 8592 && code <= 8703)
		|| (code >= 9632 && code <= 9727);
}

/// @description Check whether a code point belongs to an allowed fallback range
/// @param {Real} code Character code point
/// @returns {Bool} Whether the code point belongs to those ranges
function scr_text_code_can_try_fallback(code)
{
	/* Fallback eligibility accepts any of the Latin-1, Japanese/CJK or selected-symbol ranges */
	return scr_text_code_is_latin1(code)
		|| scr_text_code_is_japanese(code)
		|| scr_text_code_is_common_symbol(code);
}

/// @description Inspect and cache a font's glyph metadata
/// @param {Real} font_asset Font asset or runtime handle
/// @param {String} ch Character text
/// @param {Real} code Character code point
/// @returns {Bool} Whether either metadata key confirms the glyph
function scr_text_font_has_glyph(font_asset, ch, code)
{
	/* Reject nonnumeric and negative font handles before querying font metadata */
	if (!is_real(font_asset)
	|| font_asset < 0)
	{
		return false;
	}

	/* cache is the shared result struct, and cache_key pairs this font handle with its character code */
	var cache = scr_text_font_glyph_cache();
	var cache_key = "f" + string(font_asset) + "_" + string(code);

	/* Reuse a previously inspected result, including false, instead of repeatedly requesting font metadata */
	if (variable_struct_exists(cache, cache_key))
	{
		return cache[$ cache_key];
	}

	/* Start with no confirmed glyph and update only when usable metadata exposes the character */
	var has_glyph = false;
	try
	{
		/* Keep the runtime font metadata for guarded access to its glyph table */
		var info = font_get_info(font_asset);

		/* Check the metadata and glyph-table types before accessing glyph entries */
		if (is_struct(info)
		&& variable_struct_exists(info, "glyphs")
		&& is_struct(info.glyphs))
		{
			/* Accept either a character-keyed or numeric-code-keyed glyph entry to support both metadata representations */
			has_glyph = variable_struct_exists(info.glyphs, ch)
				|| variable_struct_exists(info.glyphs, string(code));
		}
	}

	/* A metadata exception is cached as no confirmed glyph */
	catch(e)
	{
		has_glyph = false;
	}

	cache[$ cache_key] = has_glyph;
	return has_glyph;
}

/// @description Check primary and fallback glyphs, then allowed ranges for sparse fallback metadata
/// @param {Real} code Character code point
/// @param {String} ch Character text
/// @returns {Bool} Whether the character can be displayed by the project's font policy
function scr_text_code_supported_by_display_font(code, ch)
{
	/* Reject control codes and the placeholder box U+25AF before checking fonts */
	if (code < 32
	|| code == 9647)
	{
		return false;
	}

	/* Try the authored UI font before requesting any fallback */
	var primary_font = scr_render_text_primary_font();

	/* A confirmed primary-font glyph needs no fallback load or range guess */
	if (scr_text_font_has_glyph(primary_font, ch, code))
	{
		return true;
	}

	/* Get the cached fallback font result for characters missing from the primary font */
	var fallback_font = scr_render_text_fallback_font();

	/* Without a usable fallback font, the character remains unsupported */
	if (fallback_font == -1)
	{
		return false;
	}

	/* A confirmed fallback glyph makes the character usable even outside the guessed range lists */
	if (scr_text_font_has_glyph(fallback_font, ch, code))
	{
		return true;
	}

	/* File fonts can have sparse runtime glyph info, especially before a glyph is drawn */
	return scr_text_code_can_try_fallback(code);
}

/// @description Check display support using the first character's code point
/// @param {String} ch Character text
/// @returns {Bool} Whether nonempty text passes the display-font policy
function scr_text_character_supported_by_display_font(ch)
{
	/* Convert the candidate to text before reading its first one-based code point */
	var text = string(ch);

	/* Empty text has no character to test */
	if (text == "")
	{
		return false;
	}

	return scr_text_code_supported_by_display_font(string_ord_at(text, 1), text);
}

/// @description Replace delimiters and remove characters unsupported by the display fonts
/// @param {String} raw_text Input text
/// @param {Real} max_length Maximum resulting character count, defaulting to -1. Negative values disable the limit
/// @param {Bool} trim_result Trim the filtered result, defaulting to false
/// @param {String} pipe_replacement Replacement for each pipe delimiter, defaulting to the unchanged pipe character
/// @param {String} line_break_replacement Replacement for each CR/LF character, defaulting to one space
/// @returns {String} Filtered text
function scr_text_filter_for_display(raw_text, max_length = -1, trim_result = false, pipe_replacement = "|", line_break_replacement = " ")
{
	/* source is the input text, result starts as the empty filtered output,
	and limit is a floored numeric bound or -1 for unlimited length */
	var source = string(raw_text);
	var result = "";
	var limit = is_real(max_length) ? floor(max_length) : -1;

	/* Process each one-based source character so replacements and font filtering retain the input order */
	for (var i = 1; i <= string_length(source); i++)
	{
		/* ch is the current character or its later replacement, and code is its first code point for font eligibility */
		var ch = string_char_at(source, i);
		var code = string_ord_at(source, i);

		/* Replace each CR or LF individually with the requested line-break text
		An empty replacement gets code -1 rather than reading a nonexistent character */
		if (ch == "\r" || ch == "\n")
		{
			ch = string(line_break_replacement);
			code = ch == "" ? -1 : string_ord_at(ch, 1);
		}

		/* Replace pipe delimiters separately, again using -1 when the replacement is empty */
		else if (ch == "|")
		{
			ch = string(pipe_replacement);
			code = ch == "" ? -1 : string_ord_at(ch, 1);
		}

		/* Append only nonempty replacement text accepted by the display-font check */
		if (ch != ""
		&& scr_text_code_supported_by_display_font(code, ch))
		{
			result += ch;
		}

		/* A nonnegative output limit stops processing once reached, trimming any replacement that crossed it */
		if (limit >= 0
		&& string_length(result) >= limit)
		{
			result = string_copy(result, 1, limit);
			break;
		}
	}

	/* Trim surrounding whitespace only when requested, after filtering and length limiting */
	if (trim_result)
	{
		result = string_trim(result);
	}

	return result;
}

/// @description Scan text for a printable primary-font miss in an allowed fallback range
/// @param {String} text Text to inspect
/// @returns {Bool} Whether the first eligible miss has usable fallback support
function scr_text_uses_fallback_font(text)
{
	/* Convert the full candidate string once before checking whether any character needs the fallback font */
	var source = string(text);

	/* Empty text requires no fallback */
	if (source == "")
	{
		return false;
	}

	/* primary_font is the authored UI font, and source_length bounds the one-based character scan */
	var primary_font = scr_render_text_primary_font();
	var source_length = string_length(source);

	/* Inspect characters in order until a fallback-eligible primary-font miss is found */
	for (var i = 1; i <= source_length; i++)
	{
		/* Read the current code point for the fast Latin-1 path and later fallback eligibility checks */
		var code = string_ord_at(source, i);

		/* fnt_ui includes printable ASCII and Latin-1, covering most UI labels.
		Skip cached glyph lookups for characters already covered by that font */
		if ((code >= 32 && code <= 126)
		|| (code >= 160 && code <= 255))
		{
			continue;
		}

		/* Retain the current character text for glyph metadata lookup */
		var ch = string_char_at(source, i);

		/* Only printable characters missing from the primary font and within allowed fallback ranges reach the fallback check */
		if (code >= 32
		&& !scr_text_font_has_glyph(primary_font, ch, code)
		&& scr_text_code_can_try_fallback(code))
		{
			/* The first eligible miss decides the result using the cached fallback handle and display-support check
			A -1 fallback short-circuits the support call */
			var fallback_font = scr_render_text_fallback_font();
			return fallback_font != -1
				&& scr_text_code_supported_by_display_font(code, ch);
		}
	}

	return false;
}

/// @description Select one display font for the entire string
/// @param {String} text Text to draw
/// @returns {Real} Primary font or loaded fallback handle
function scr_render_text_font_for_text(text)
{
	/* A string needing fallback uses that font for the entire draw, otherwise use the authored primary font */
	if (scr_text_uses_fallback_font(text))
	{
		return scr_render_text_fallback_font();
	}

	return scr_render_text_primary_font();
}
#endregion /* Display Fonts and Input Filtering END */

#region /* Text Scaling and Canvas Palette */
/// @description Select a font and measure the scale for the requested height
/// @param {Real} height Target height in pixels
/// @param {Real} text_font Font override. Defaults to noone for the primary font
/// @returns {Real} Uniform scale, or 1 if the base height cannot be measured. Changes draw font
function scr_render_text_scale(height, text_font = noone)
{
	/* An undefined or noone override selects the primary font, otherwise use the supplied font for measurement */
	var base_font = is_undefined(text_font) || text_font == noone ? scr_render_text_primary_font() : text_font;
	draw_set_font(base_font);

	/* Measure 'Mg' as the base pixel height so both ascender and descender contribute to the requested scale */
	var base_height = string_height("Mg");

	/* If 'Mg' has no measurable height, try 'M' before giving up */
	if (base_height <= 0)
	{
		base_height = string_height("M");
	}

	/* If both measurements are nonpositive, use scale one rather than dividing by zero */
	if (base_height <= 0)
	{
		return 1;
	}

	return height / base_height;
}

/// @description Round a drawing coordinate to the nearest pixel
/// @param {Real} value Coordinate to round
/// @returns {Real} floor(value + 0.5)
function scr_render_text_snap(value)
{
	return floor(value + 0.5);
}

/// @description Check whether the Canvas-specific precoloured font palette is enabled
/// @returns {Bool} Whether the global flag is enabled in a browser without WebGL
function scr_render_text_canvas_safe_active()
{
	/* The special palette applies only when its global flag exists and is enabled in a browser using Canvas without WebGL */
	var active = variable_global_exists("text_canvas_safe_palette")
		&& global.text_canvas_safe_palette
		&& os_browser != browser_not_a_browser
		&& webgl_enabled == 0;
	return active;
}

/// @description Initialize paired precoloured font and colour arrays once
function scr_render_text_safe_palette_ensure()
{
	/* Reuse previously initialized palette arrays instead of rebuilding them for each draw */
	if (variable_global_exists("text_safe_palette_fonts"))
	{
		return;
	}

	/* These colour entries and the following precoloured font assets share the same zero-based indices
	They let Canvas draw from a suitable authored font texture without runtime tinting */
	global.text_safe_palette_colours = [
		c_white,
		c_black,
		make_color_rgb(122, 122, 126),
		make_color_rgb(166, 166, 166),
		make_color_rgb(210, 210, 214),
		make_color_rgb(255, 85, 85),
		make_color_rgb(255, 220, 95),
		make_color_rgb(0, 235, 55),
		make_color_rgb(185, 195, 210)
	];

	/* Each font matches the colour at its corresponding text_safe_palette_colours index */
	global.text_safe_palette_fonts = [
		fnt_ui,
		fnt_ui_black,
		fnt_ui_darkgray,
		fnt_ui_gray,
		fnt_ui_lightgray,
		fnt_ui_red,
		fnt_ui_yellow,
		fnt_ui_green,
		fnt_ui_blue
	];
}

/// @description Measure squared RGB channel distance
/// @param {Real} a First GameMaker colour
/// @param {Real} b Second GameMaker colour
/// @returns {Real} Sum of squared red, green and blue differences
function scr_render_text_colour_distance(a, b)
{
	/* Measure red, green and blue channel differences, then sum their squares for palette comparison */
	var red_delta = colour_get_red(a) - colour_get_red(b);
	var green_delta = colour_get_green(a) - colour_get_green(b);
	var blue_delta = colour_get_blue(a) - colour_get_blue(b);
	return red_delta * red_delta + green_delta * green_delta + blue_delta * blue_delta;
}

/// @description Select the closest precoloured UI font from the paired palette
/// @param {Real} colour Requested drawing colour
/// @returns {Asset.GMFont} Closest font, retaining the earlier entry on ties
function scr_render_text_safe_font_for_colour(colour)
{
	scr_render_text_safe_palette_ensure();

	/* Start with palette index zero and its squared RGB distance as the best match */
	var best_index = 0;
	var best_distance = scr_render_text_colour_distance(colour, global.text_safe_palette_colours[0]);

	/* Compare the remaining zero-based palette entries, keeping earlier entries when distances tie */
	for (var i = 1; i < array_length(global.text_safe_palette_colours); i++)
	{
		/* Measure this candidate's squared channel distance from the requested colour */
		var distance = scr_render_text_colour_distance(colour, global.text_safe_palette_colours[i]);

		/* Replace the best match only when this candidate is strictly closer */
		if (distance < best_distance)
		{
			best_distance = distance;
			best_index = i;
		}
	}

	return global.text_safe_palette_fonts[best_index];
}

/// @description Draw snapped text without texture filtering, then restore colour, alpha and filtering
/// @param {Real} x Horizontal position using the current draw alignment
/// @param {Real} y Vertical position using the current draw alignment
/// @param {String} text Text to draw
/// @param {Real} scale Uniform font scale
/// @param {Real} text_font Font override, defaulting to noone for automatic selection
/// Resets the font to fnt_ui rather than the caller's previous font.
function scr_render_text_draw_scaled(x, y, text, scale, text_font = noone)
{
	/* Browser filtering can smear neighbouring font-atlas pixels on small transformed
	text. Save the caller's filtering, color and alpha so temporary draw changes can
	be restored afterward */
	var restore_filter = gpu_get_texfilter();
	var restore_colour = draw_get_colour();
	var restore_alpha = draw_get_alpha();

	/* force_white reads its optional global only after an existence check
	preferred_font uses automatic selection for an absent override, otherwise keeps the supplied font */
	var force_white = variable_global_exists("text_debug_force_white") && global.text_debug_force_white;
	var preferred_font = is_undefined(text_font) || text_font == noone ? scr_render_text_font_for_text(text) : text_font;

	/* Use the authored Canvas palette only for the primary font when forced-white diagnostics are off
	draw_font selects that nearest precoloured asset or the preferred font
	draw_colour stays white for precoloured/forced-white rendering, otherwise preserves the caller's colour */
	var safe_palette = preferred_font == fnt_ui && !force_white && scr_render_text_canvas_safe_active();
	var draw_font = safe_palette ? scr_render_text_safe_font_for_colour(restore_colour) : preferred_font;
	var draw_colour = (force_white || safe_palette) ? c_white : restore_colour;

	/* Forced-white diagnostics also select the primary font, giving a stable baseline for tint comparisons */
	if (force_white)
	{
		draw_font = scr_render_text_primary_font();
	}

	/* Disable interpolation only when it was enabled, keeping transformed text pixels crisp */
	if (restore_filter)
	{
		gpu_set_texfilter(false);
	}

	draw_set_font(draw_font);
	draw_set_colour(draw_colour);
	draw_text_transformed(scr_render_text_snap(x), scr_render_text_snap(y), string(text), scale, scale, 0);
	draw_set_font(scr_render_text_primary_font());

	/* Restore enabled filtering after drawing, while callers that started unfiltered need no change */
	if (restore_filter)
	{
		gpu_set_texfilter(true);
	}

	draw_set_colour(restore_colour);
	draw_set_alpha(restore_alpha);
}
#endregion /* Text Scaling and Canvas Palette END */

#region /* Font Diagnostics Overlay */
/// @description Draw font, tint and renderer diagnostics when the GUI has enough space
function scr_render_text_debug_overlay()
{
	/* gui_width/gui_height bound the diagnostics panel in GUI pixels
	panel_x/panel_y anchor it, and panel_w/panel_h cap its size while respecting the available viewport */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var panel_x = 16;
	var panel_y = 76;
	var panel_w = min(620, gui_width - 32);
	var panel_h = min(320, gui_height - panel_y - 24);

	/* Skip the overlay when available dimensions are too small for readable diagnostics */
	if (panel_w <= 240 || panel_h <= 160)
	{
		return;
	}

	draw_set_alpha(0.92);
	draw_set_colour(make_color_rgb(6, 7, 9));
	draw_rectangle(panel_x, panel_y, panel_x + panel_w, panel_y + panel_h, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(120, 124, 132));
	draw_rectangle(panel_x, panel_y, panel_x + panel_w, panel_y + panel_h, true);

	/* text_x/text_y begin inside the panel padding, and row_gap advances successive samples by 27 GUI pixels */
	var text_x = panel_x + 14;
	var text_y = panel_y + 12;
	var row_gap = 27;
	draw_set_halign(fa_left);

	draw_set_colour(c_white);

	/* The diagnostic label displays the force-white flag as ON or OFF */
	scr_render_text(text_x, text_y, "F7 text diagnostics | F8 force-white " + (global.text_debug_force_white ? "ON" : "OFF"), 18, panel_w - 28);
	text_y += row_gap + 6;

	draw_set_colour(c_white);
	scr_render_text(text_x, text_y, "white draw colour: The quick brown fox 0123456789", 18, panel_w - 28);
	text_y += row_gap;

	draw_set_colour(c_white);
	scr_render_text(text_x, text_y, "Japanese fallback: こんにちは カタカナ 日本語", 18, panel_w - 28);
	text_y += row_gap;

	draw_set_colour(make_color_rgb(166, 166, 166));
	scr_render_text(text_x, text_y, "gray draw colour: The quick brown fox 0123456789", 18, panel_w - 28);
	text_y += row_gap;

	/* Save the sample area's alpha before the translucent-text comparison, then restore it afterward */
	var restore_alpha = draw_get_alpha();
	draw_set_colour(c_white);
	draw_set_alpha(0.65);
	scr_render_text(text_x, text_y, "white with alpha 0.65: The quick brown fox 0123456789", 18, panel_w - 28);
	draw_set_alpha(restore_alpha);
	text_y += row_gap;

	draw_set_colour(make_color_rgb(255, 220, 95));
	scr_render_text(text_x, text_y, "yellow chat colour: The quick brown fox 0123456789", 18, panel_w - 28);
	text_y += row_gap;

	draw_set_colour(make_color_rgb(255, 85, 85));
	scr_render_text(text_x, text_y, "red error colour: The quick brown fox 0123456789", 18, panel_w - 28);
	text_y += row_gap;

	draw_set_colour(c_white);
	draw_rectangle(text_x - 4, text_y - 2, text_x + panel_w - 36, text_y + 23, false);
	draw_set_colour(c_black);
	scr_render_text(text_x, text_y, "black on white bubble text: The quick brown fox 0123456789", 18, panel_w - 42);
	text_y += row_gap;

	draw_set_colour(make_color_rgb(178, 178, 184));

	/* Report the Canvas palette branch as 1 when active and 0 otherwise beside runtime renderer information */
	scr_render_text(text_x, text_y, "HTML5 webgl_enabled=" + string(webgl_enabled) + " palette_text=" + (scr_render_text_canvas_safe_active() ? "1" : "0") + " os_browser=" + string(os_browser), 16, panel_w - 28);

	draw_set_halign(fa_left);
	draw_set_alpha(1);
	draw_set_colour(c_white);
}
#endregion /* Font Diagnostics Overlay END */

/// @description Check scaled width using the currently selected font
/// @param {String} text Text to measure
/// @param {Real} scale Uniform text scale
/// @param {Real} max_width Pixel bound. Nonpositive values disable the check
/// @returns {Bool} Whether the text fits or checking is disabled
function scr_text_fits_width(text, scale, max_width)
{
	/* A nonpositive maximum disables width checking, otherwise compare the current font's scaled pixel width */
	return max_width <= 0 || string_width(string(text)) * scale <= max_width;
}

/// @description Measure text in its display font and reset the draw font to fnt_ui
/// @param {String} text Text to measure
/// @returns {Real} Unscaled pixel width
function scr_render_text_measure_width(text)
{
	/* Convert the string and choose its display font before measuring */
	var source = string(text);
	draw_set_font(scr_render_text_font_for_text(source));

	/* Keep the measured unscaled pixel width before resetting the selected font to the primary UI font */
	var width = string_width(source);
	draw_set_font(scr_render_text_primary_font());
	return width;
}

/// @description Wrap one line at spaces and split oversized words by character
/// @param {String} raw_line Line text
/// @param {Real} height Target pixel height. Defaults to 18
/// @param {Real} max_width Pixel width. Defaults to -1 for no wrapping
/// @returns {String} LF-separated text. Changes draw font and accepts an oversized single glyph per chunk
function scr_text_wrap_line(raw_line, height = 18, max_width = -1)
{
	/* source is the line to wrap and wrap_font is the display font used consistently for its width checks */
	var source = string(raw_line);
	var wrap_font = scr_render_text_font_for_text(source);
	draw_set_font(wrap_font);

	/* Scale the chosen font to the requested pixel height before testing line widths */
	var scale = scr_render_text_scale(height, wrap_font);

	/* Disabled wrapping or an already-fitting line returns the original text without splitting it */
	if (max_width <= 0 || scr_text_fits_width(source, scale, max_width))
	{
		return source;
	}

	/* lines collects finished lines, line_count starts at zero for the next output index,
	and line begins empty as the current unfinished line */
	var lines = [];
	var line_count = 0;
	var line = "";

	/* Split on spaces for word-based wrapping before falling back to character-sized chunks */
	var words = string_split(source, " ");

	/* Visit every zero-based split word in order, preserving spaces between accumulated words */
	for (var word_index = 0; word_index < array_length(words); word_index++)
	{
		/* word is the current split token, which may be empty when the source contains repeated spaces */
		var word = words[word_index];

		/* Skip empty tokens at a new line so it does not start with separator padding */
		if (word == "" && line == "")
		{
			continue;
		}

		/* A new line starts with the word alone, while an existing line tests one joining space plus the word */
		var candidate = line == "" ? word : line + " " + word;

		/* A fitting candidate extends the current line and needs no word splitting */
		if (scr_text_fits_width(candidate, scale, max_width))
		{
			line = candidate;
			continue;
		}

		/* Commit a nonempty previous line before placing a word that did not fit beside it */
		if (line != "")
		{
			lines[line_count++] = line;
			line = "";
		}

		/* A word fitting by itself begins the next line */
		if (scr_text_fits_width(word, scale, max_width))
		{
			line = word;
		}

		/* An oversized word is split by character so wrapping can proceed without a space boundary */
		else
		{
			/* chunk accumulates the next unfinished piece of the oversized word from empty */
			var chunk = "";

			/* Walk one-based word characters while filling chunks to the available width */
			for (var i = 1; i <= string_length(word); i++)
			{
				/* ch is the current character and chunk_candidate tests it appended to the unfinished chunk */
				var ch = string_char_at(word, i);
				var chunk_candidate = chunk + ch;

				/* Accept at least one character per chunk even when a single glyph is wider than the limit, ensuring forward progress */
				if (chunk == "" || scr_text_fits_width(chunk_candidate, scale, max_width))
				{
					chunk = chunk_candidate;
				}

				/* Commit a full chunk and begin the next one with the character that crossed its width */
				else
				{
					lines[line_count++] = chunk;
					chunk = ch;
				}
			}

			line = chunk;
		}
	}

	/* Commit the final unfinished line only when it contains text */
	if (line != "")
	{
		lines[line_count++] = line;
	}

	/* Start the joined wrapped output empty */
	var result = "";

	/* Join each zero-based finished line in order */
	for (var line_index = 0; line_index < line_count; line_index++)
	{
		/* Insert LF before later nonempty output so the result does not start with a newline */
		if (result != "")
		{
			result += "\n";
		}
		result += lines[line_index];
	}

	return result;
}

/// @description Wrap each input line to a pixel width, splitting oversized words by character
/// @param {String} text Input text. CR characters are removed
/// @param {Real} height Requested line height in pixels, defaulting to 18
/// @param {Real} max_width Pixel width, defaulting to -1. Nonpositive values disable wrapping
/// @returns {String} Wrapped text separated by LF characters. Changes the selected draw font
function scr_text_wrap(text, height = 18, max_width = -1)
{
	/* Remove CR characters before splitting on LF
	raw_lines contains the resulting source lines, and result starts empty for their wrapped output */
	var source = string_replace_all(string(text), "\r", "");
	var raw_lines = string_split(source, "\n");
	var result = "";

	/* Wrap each zero-based source line independently, retaining its order */
	for (var i = 0; i < array_length(raw_lines); i++)
	{
		/* Store this line's wrapped text before appending it to the output */
		var wrapped = scr_text_wrap_line(raw_lines[i], height, max_width);

		/* Add LF only after output text already exists, which can collapse leading empty source lines */
		if (result != "")
		{
			result += "\n";
		}
		result += wrapped;
	}

	return result;
}

/// @description Count LF-separated logical lines
/// @param {String} text Text to inspect
/// @returns {Real} Line count, with one for empty text
function scr_text_line_count(text)
{
	/* Convert the supplied value to text before counting LF-separated lines */
	var source = string(text);

	/* Empty text still occupies one logical line */
	if (source == "")
	{
		return 1;
	}

	/* Start at one for the initial line, adding one for every LF */
	var count = 1;

	/* Scan every one-based character position for explicit line breaks */
	for (var i = 1; i <= string_length(source); i++)
	{
		/* Each LF adds another logical line to the count */
		if (string_char_at(source, i) == "\n")
		{
			count++;
		}
	}

	return count;
}

/// @description Measure wrapped line heights without a trailing gap
/// @param {String} text Text to wrap
/// @param {Real} height Line height in pixels, defaulting to 18
/// @param {Real} max_width Pixel width. Defaults to -1 for no wrapping
/// @param {Real} line_gap Pixels between lines. Defaults to 4
/// @returns {Real} Total pixel height. Changes draw font
function scr_text_wrapped_height(text, height = 18, max_width = -1, line_gap = 4)
{
	/* Wrap the text first so the measured height reflects actual line breaks at the requested width */
	var wrapped = scr_text_wrap(text, height, max_width);
	return scr_text_line_count(wrapped) * (height + line_gap) - line_gap;
}

/// @description Draw wrapped lines using the current horizontal and vertical alignment
/// @param {Real} x Horizontal position in the caller's drawing coordinates
/// @param {Real} y First line position in the caller's drawing coordinates
/// @param {String} text Input text
/// @param {Real} height Line height in pixels, defaulting to 18
/// @param {Real} max_width Pixel width, defaulting to -1. Nonpositive values disable wrapping
/// @param {Real} line_gap Additional pixels between lines, defaulting to 4
/// @returns {Real} Total drawn height in pixels, excluding a trailing gap
function scr_render_text_wrapped(x, y, text, height = 18, max_width = -1, line_gap = 4)
{
	/* Use one chosen display font for every line in this draw */
	var draw_font = scr_render_text_font_for_text(text);
	draw_set_font(draw_font);

	/* scale fits the requested line height, wrapped holds the width-limited text,
	lines splits it into LF-separated entries, and line_height includes the requested interline pixel gap */
	var scale = scr_render_text_scale(height, draw_font);
	var wrapped = scr_text_wrap(text, height, max_width);
	var lines = string_split(wrapped, "\n");
	var line_height = height + line_gap;

	/* Draw each zero-based line at its vertically advanced position using the same scale and font */
	for (var i = 0; i < array_length(lines); i++)
	{
		scr_render_text_draw_scaled(x, y + i * line_height, lines[i], scale, draw_font);
	}

	return array_length(lines) * line_height - line_gap;
}

/// @description Draw one text string, shrinking it uniformly when it exceeds max_width
/// @param {Real} x Horizontal position using the current draw alignment
/// @param {Real} y Vertical position using the current draw alignment
/// @param {String} text Text to draw
/// @param {Real} height Requested text height in pixels, defaulting to 32
/// @param {Real} max_width Pixel width, defaulting to -1. Nonpositive values disable shrinking
function scr_render_text(x, y, text, height = 32, max_width = -1)
{
	/* -1 means no UI timing measurement was started for this call */
	var perf_token = -1;

	/* Read the optional overlay flag only when initialized, then begin a render_text timing sample when enabled */
	if (variable_global_exists("ui_perf_overlay") && global.ui_perf_overlay)
	{
		perf_token = scr_ui_perf_begin("render_text");
	}

	/* _text is the converted string and draw_font selects its whole-string display font */
	var _text = string(text);
	var draw_font = scr_render_text_font_for_text(_text);
	draw_set_font(draw_font);

	/* Start with the uniform scale needed for the requested pixel height */
	var scale = scr_render_text_scale(height, draw_font);
	
	/* Only a positive width enables shrinking, preserving the requested height for unconstrained text */
	if (max_width > 0)
	{
		/* Measure the unscaled string in the selected font before deciding whether to shrink it */
		var base_width = string_width(_text);

		/* A positive measured width is required before calculating a shrink ratio */
		if (base_width > 0)
		{
			/* Convert the base width to the pixel width at the current uniform scale */
			var scaled_width = base_width * scale;

			/* Reduce both axes proportionally only when the text exceeds the allowed width */
			if (scaled_width > max_width)
			{
				scale *= max_width / scaled_width;
			}
		}
	}
	
	scr_render_text_draw_scaled(x, y, _text, scale, draw_font);

	/* End timing only when this call actually began a UI performance sample */
	if (perf_token >= 0)
	{
		scr_ui_perf_end("render_text", perf_token);
	}
}
