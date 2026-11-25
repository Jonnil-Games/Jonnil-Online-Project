#region /* Display Fonts and Input Filtering */
/// @description Load the bundled font once and keep a readable font available during browser loading
function scr_render_text_font_init()
{
	if (variable_global_exists("text_font_initialized")) return;
	global.text_font_initialized = true;
	global.text_font_handle = fnt_ui;
	global.text_font_owned = [];
	global.text_file_font_ready = false;
	global.text_font_loading = false;
	global.text_font_poll_at = 0;
	global.text_font_error = "";
	global.text_font_description = "Bundled font atlas";
	global.text_font_generic = -1;
	global.text_canvas_fonts = [];
	global.text_canvas_font_clock = 0;
	global.text_canvas_font_failed = false;
	global.text_canvas_line_ratio = 1;

	/* WebGL uses one licensed white atlas. Dynamic HTML5 fonts are supported only by Canvas */
	if (os_browser != browser_not_a_browser)
	{
		if (webgl_enabled != 0) return;
		try
		{
			/* Canvas reports its CSS pixel size as line height. Match the licensed atlas's line spacing */
			var restore_font = draw_get_font();
			draw_set_font(fnt_ui);
			var atlas_height = string_height("Mg");
			var atlas_info = font_get_info(fnt_ui);
			if (is_struct(atlas_info) && variable_struct_exists(atlas_info, "size") && atlas_info.size > 0)
			{
				global.text_canvas_line_ratio = atlas_height / (atlas_info.size * 4 / 3);
			}
			draw_set_font(restore_font);
			/* A generic web family draws with fillText, so loading and failure states need no pixel tinting */
			var generic = font_add("sans-serif", 100, false, false, 32, 255);
			if (generic != -1)
			{
				global.text_font_generic = generic;
				global.text_font_handle = generic;
				array_push(global.text_font_owned, generic);
			}
			global.text_font_loading = true;
			global.text_font_description = "Browser font, loading bundled font";
			html5_ui_font_load_start();
		}
		catch(e)
		{
			global.text_font_loading = false;
			global.text_font_error = "The bundled font could not load. Using the fallback font.";
		}
		return;
	}

	/* Included file layout differs between native packages and local runs. Each path is tried once */
	var paths = ["Fonts/NotoSansCJKjp-Regular.otf", "datafiles/Fonts/NotoSansCJKjp-Regular.otf"];
	for (var font_path_index = 0; font_path_index < array_length(paths); font_path_index++)
	{
		if (!file_exists(paths[font_path_index])) continue;
		var handle = -1;
		try { handle = font_add(paths[font_path_index], 100, false, false, 32, 255); }
		catch(e) { handle = -1; }
		if (handle != -1)
		{
			global.text_font_handle = handle;
			global.text_file_font_ready = true;
			global.text_font_description = "Bundled Noto font file";
			array_push(global.text_font_owned, handle);
			return;
		}
	}
	global.text_font_error = "The bundled font could not load. Using the fallback font.";
}

/// @description Adopt the browser font after asynchronous FontFace loading, without retrying from Draw
function scr_render_text_font_update()
{
	scr_render_text_font_init();
	if (!global.text_font_loading || current_time < global.text_font_poll_at) return;
	global.text_font_poll_at = current_time + 100;
	var status = html5_ui_font_load_status();
	if (status == 0) return;
	global.text_font_loading = false;
	if (status == 1)
	{
		var handle = -1;
		/* The family alias avoids GameMaker's file-font loader, which reads Canvas pixels for metrics */
		try { handle = font_add("JonnilUI", 100, false, false, 32, 255); }
		catch(e) { handle = -1; }
		if (handle != -1)
		{
			scr_render_text_canvas_cache_clear();
			global.text_font_handle = handle;
			global.text_file_font_ready = true;
			global.text_font_description = "Bundled Noto web font";
			global.text_font_error = "";
			global.text_font_glyph_cache = {};
			array_push(global.text_font_owned, handle);
			return;
		}
	}
	global.text_font_description = "Browser fallback font";
	global.text_font_error = "The bundled font could not load. Using the browser font.";
	debug_error("Could not load UI font: " + html5_ui_font_load_error());
}

/// @description Get the same ready font used by text drawing and measurement
/// @returns {Real} Owned runtime font or the licensed compiled fallback
function scr_render_text_primary_font()
{
	scr_render_text_font_update();
	return global.text_font_handle;
}

/// @description Return loading or failure guidance for the appearance page
/// @returns {String} Empty after successful loading, otherwise a readable fallback explanation
function scr_render_text_font_notice()
{
	scr_render_text_font_update();
	if (global.text_font_error != "") return global.text_font_error;
	return global.text_font_loading ? "Loading the bundled font. Text remains available." : "";
}

/// @description Release only font handles allocated by this text service at application exit
function scr_render_text_font_cleanup()
{
	if (!variable_global_exists("text_font_initialized")) return;
	scr_render_text_canvas_cache_clear();
	for (var font_index = 0; font_index < array_length(global.text_font_owned); font_index++)
	{
		try { font_delete(global.text_font_owned[font_index]); } catch(e) {}
	}
	global.text_font_owned = [];
	global.text_font_handle = fnt_ui;
}

/// @description Release the Canvas-only size cache after a family change or at application exit
function scr_render_text_canvas_cache_clear()
{
	/* Canvas fillText is immediate. Never delete fonts from queued native or WebGL drawing */
	if (os_browser == browser_not_a_browser || webgl_enabled != 0) return;
	for (var font_index = 0; font_index < array_length(global.text_canvas_fonts); font_index++)
	{
		try { font_delete(global.text_canvas_fonts[font_index].font); } catch(e) {}
	}
	global.text_canvas_fonts = [];
	global.text_canvas_font_clock = 0;
	global.text_canvas_font_failed = false;
}

/// @description Cache actual Canvas font sizes because this runner ignores transformed web-font scale
/// @param {Real} pixel_size Requested CSS pixel size before flooring to avoid width overflow
/// @returns {Real} Canvas web font at the bounded size
function scr_render_text_canvas_font(pixel_size)
{
	var size = clamp(floor(pixel_size + 0.000001), 1, 1024);
	var family = global.text_file_font_ready ? "JonnilUI" : "sans-serif";
	global.text_canvas_font_clock++;
	var oldest_index = 0;
	for (var font_index = 0; font_index < array_length(global.text_canvas_fonts); font_index++)
	{
		var cached = global.text_canvas_fonts[font_index];
		if (cached.size == size && cached.family == family)
		{
			cached.used = global.text_canvas_font_clock;
			return cached.font;
		}
		if (cached.used < global.text_canvas_fonts[oldest_index].used) oldest_index = font_index;
	}

	/* A failed allocation stops further attempts until the font family changes */
	if (global.text_canvas_font_failed) return global.text_font_handle;
	/* Canvas draws immediately, so the least recent size can be released before adding its replacement */
	if (array_length(global.text_canvas_fonts) >= 64)
	{
		var recycled = global.text_canvas_fonts[oldest_index];
		font_delete(recycled.font);
		array_delete(global.text_canvas_fonts, oldest_index, 1);
	}
	var handle = -1;
	try { handle = font_add(family, size, false, false, 32, 255); } catch(e) {}
	if (handle == -1)
	{
		global.text_canvas_font_failed = true;
		global.text_font_error = "The browser could not create a text size. Using the fallback font.";
		return global.text_font_handle;
	}
	array_push(global.text_canvas_fonts, { font: handle, size: size, family: family, used: global.text_canvas_font_clock });
	return handle;
}

/// @description Measure the font size actually drawn, including Canvas pixel-size quantization
/// @param {String} text Text to measure
/// @param {Real} scale Requested scale of the base font
/// @param {Real} text_font Shared measurement font
/// @returns {Real} Final width in drawing coordinates
function scr_render_text_scaled_width(text, scale, text_font)
{
	var restore_font = draw_get_font();
	var measured_font = text_font;
	var measured_scale = scale;
	if (os_browser != browser_not_a_browser && webgl_enabled == 0 && text_font != fnt_ui)
	{
		measured_font = scr_render_text_canvas_font(100 * scale);
		measured_scale = 1;
	}
	draw_set_font(measured_font);
	var width = string_width(string(text)) * measured_scale;
	draw_set_font(restore_font);
	return width;
}

/// @description Check verified bundled-file coverage within this game's permitted text ranges
/// @param {Real} code Unicode code point
/// @returns {Bool} Whether the bundled Noto font contains the permitted glyph
function scr_text_file_font_has_glyph(code)
{
	/* These ranges were checked against the bundled font's cmap, not inferred from Unicode blocks */
	static ranges = [[32,126],[160,255],[8208,8214],[8216,8218],[8220,8222],[8224,8226],
		[8229,8231],[8240,8240],[8242,8243],[8245,8245],[8249,8252],[8592,8601],
		[8632,8633],[8644,8646],[8651,8652],[8656,8656],[8658,8658],[8660,8660],
		[8678,8681],[8693,8693],[9632,9643],[9649,9651],[9654,9655],[9660,9661],
		[9664,9665],[9670,9671],[9673,9676],[9678,9683],[9698,9702],[9711,9711],
		[12288,12351],[12353,12438],[12441,12543],[12549,12591],[13312,19893],
		[19968,40943],[65281,65470],[65474,65479],[65482,65487],[65490,65495],
		[65498,65500],[65504,65510],[65512,65518]];
	var first = 0;
	var last = array_length(ranges) - 1;
	while (first <= last)
	{
		var middle = (first + last) div 2;
		if (code < ranges[middle][0]) last = middle - 1;
		else if (code > ranges[middle][1]) first = middle + 1;
		else return true;
	}
	return false;
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
	/* File fonts expose glyph metadata lazily. Use the verified bundled-file coverage while active */
	if (variable_global_exists("text_font_initialized"))
	{
		if (global.text_file_font_ready && font_asset == global.text_font_handle)
		{
			return scr_text_file_font_has_glyph(code);
		}
		/* Browser generic families keep ordinary labels usable while the bundled file is loading */
		if (font_asset == global.text_font_generic)
		{
			return (code >= 32 && code <= 126) || (code >= 160 && code <= 255);
		}
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

/// @description Check the active file font's verified coverage or the compiled font's actual glyphs
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

	/* Native and Canvas file fonts use verified cmap coverage. WebGL uses only its real atlas glyphs */
	var primary_font = scr_render_text_primary_font();
	return scr_text_font_has_glyph(primary_font, ch, code);
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

/// @description Select one display font for the entire string
/// @param {String} text Text to draw
/// @returns {Real} Shared ready font
function scr_render_text_font_for_text(text)
{
	/* One ready font owns both measurement and drawing for this string */
	return scr_render_text_primary_font();
}
#endregion /* Display Fonts and Input Filtering END */

#region /* Text Scaling and Drawing */
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
	if (os_browser != browser_not_a_browser && webgl_enabled == 0 && base_font != fnt_ui)
	{
		base_height *= global.text_canvas_line_ratio;
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

/// @description Draw snapped text without texture filtering, then restore colour, alpha and filtering
/// @param {Real} x Horizontal position using the current draw alignment
/// @param {Real} y Vertical position using the current draw alignment
/// @param {String} text Text to draw
/// @param {Real} scale Uniform font scale
/// @param {Real} text_font Font override, defaulting to noone for automatic selection
/// Resets the font to the shared primary font rather than the caller's previous font.
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

	/* Canvas web fonts use fillText with this exact colour. Native and WebGL tint one white font */
	var draw_font = preferred_font;
	var draw_colour = force_white ? c_white : restore_colour;

	/* Forced-white diagnostics also select the primary font, giving a stable baseline for tint comparisons */
	if (force_white)
	{
		draw_font = scr_render_text_primary_font();
	}
	/* Dynamic Canvas fonts ignore transformed scale. Draw at the cached final size instead */
	if (os_browser != browser_not_a_browser && webgl_enabled == 0 && draw_font != fnt_ui)
	{
		draw_font = scr_render_text_canvas_font(100 * scale);
		scale = 1;
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
#endregion /* Text Scaling and Drawing END */

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
	scr_render_text(text_x, text_y, "Japanese sample: こんにちは カタカナ 日本語", 18, panel_w - 28);
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

	/* Show the actual font path so a loading or fallback result can be distinguished from the atlas */
	scr_render_text(text_x, text_y, global.text_font_description + " | WebGL=" + string(webgl_enabled), 16, panel_w - 28);

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
	return max_width <= 0 || scr_render_text_scaled_width(text, scale, draw_get_font()) <= max_width;
}

/// @description Measure text in its display font and reset the shared primary font
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
			var scaled_width = scr_render_text_scaled_width(_text, scale, draw_font);

			/* Reduce both axes proportionally only when the text exceeds the allowed width */
			if (scaled_width > max_width)
			{
				scale = min(scale, max_width / base_width);
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
