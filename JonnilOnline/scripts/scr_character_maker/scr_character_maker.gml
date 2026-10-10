#macro CharacterMaker scr_get_character_maker()

/// @description Create the twelve-frame character editor, modal UI, and rendering caches
function scr_character_maker() constructor
{

	#region /* Editor State */
	/* Rows face Down, Left, Right, Up.
	Columns contain Walk 1, Idle, Walk 2.
	Each cell is 16 by 19 pixels */
	/* frame_w/h define each 16 by 19 source-pixel animation cell and column_count/row_count define its
	three-pose, four-direction grid */
	frame_w = 16;
	frame_h = 19;
	column_count = 3;
	row_count = 4;

	/* sheet_w/h are the complete 48 by 76 pixel PNG dimensions used when encoding all animation frames */
	sheet_w = 48;
	sheet_h = 76;

	/* Imported alpha bytes at or below this threshold become transparent black in RgbaPng */
	alpha_cutoff = 2;

	/* Shared client INI path and transparency-only section name retain this editor's display settings
	without overwriting other client settings */
	settings_file = "client_settings.ini";
	transparency_settings_section = "sprite_editor_transparency_background";

	/* open starts false before a main editing session and modal starts empty before any entry, save,
	loading or discard dialog owns input */
	open = false;
	modal = "";

	/* The same editor serves player and pet artwork. Keep its destination separate from registry
	selection so editing a companion never equips it as the player */
	editing_target = "player";
	requested_source_key = ""; /* Artwork captured when the entry dialog opens */

	/* hover_key starts empty before GUI hit testing. hover_col/row start at source cell zero and
	follow the currently pointed grid pixel */
	hover_key = "";
	hover_col = 0;
	hover_row = 0;

	/* active_frame starts at row-major slot zero. editor_view_col/row start at the top-left source
	cell and are reclamped when zoom or panning changes visible extent */
	active_frame = 0;
	editor_view_col = 0;
	editor_view_row = 0;

	/* editor_zoom_percent starts at the unzoomed 100-percent view. min/max bound it to 8..800 percent
	and editor_zoom_levels lists the authored keyboard/button steps */
	editor_zoom_percent = 100;
	editor_zoom_min = 8;
	editor_zoom_max = 800;
	editor_zoom_levels = [8, 16, 32, 64, 100, 200, 300, 400, 800];

	/* Frame slots store row-major RRGGBBAA snapshots.
	The editor owns mutable pixels and undo for active_frame */
	/* frames starts empty until reset or character extraction supplies twelve snapshots. Its row-major
	slots each contain frame_w times frame_h RRGGBBAA pixels */
	frames = [];

	/* loading_source starts undefined with no pending character source, loading_frames empty and
	loading_frame zero. Queued imports fill one frame per Step before replacing current edits */
	loading_source = undefined;
	loading_frames = [];
	loading_frame = 0;

	/* editor starts noone before mutable pixels are created. editor_surface starts unallocated and
	dirty so ensure_editor_surface must build its first GPU representation */
	editor = noone;
	editor_surface = noone;
	editor_surface_dirty = true;

	/* frame_surfaces owns one initially unallocated surface per frame slot and frame_surface_dirty
	starts true for each. Cache reset and session close free live surfaces, and preview getters
	rebuild only needed content */
	frame_surfaces = array_create(column_count * row_count, noone);
	frame_surface_dirty = array_create(column_count * row_count, true);

	/* Pen is the initial painting tool. editor_dragging starts false before a stroke and editor_dirty
	false until pixels change and require saving */
	editor_tool = PIXEL_EDITOR_TOOL_PEN;
	editor_dragging = false;
	editor_dirty = false;

	/* source_key/label start empty before a source is chosen and source_can_overwrite starts false.
	The registry enables replacement only for an installed local custom character */
	source_key = "";
	source_label = "";
	source_can_overwrite = false;

	/* save_name starts empty before naming a sheet. keyboard_focus starts empty before a modal text
	field takes keyboard_string */
	save_name = "";
	keyboard_focus = "";

	/* copied_frame_hex starts empty before a whole-frame copy. Selection copies instead use the pixel
	editor's separate region clipboard */
	copied_frame_hex = "";

	/* Feedback starts with empty status_text, white status_colour and a zero current_time millisecond
	expiry. set_status replaces all three for a three-second message */
	status_text = "";
	status_colour = c_white;
	status_until = 0;

	/* active_slider starts empty before an HSV drag owns mouse input */
	active_slider = "";

	/* hsv_surface_hue/saturation/value start unallocated and hsv_key_hue/saturation/value empty.
	hsv_surface_for creates these owned channel caches and free_hsv_surfaces releases them */
	hsv_surface_hue = noone;
	hsv_surface_saturation = noone;
	hsv_surface_value = noone;
	hsv_key_hue = "";
	hsv_key_saturation = "";
	hsv_key_value = "";

	/* transparency_focus starts empty. transparency_draft_mode defaults to checker blocks and the
	three draft RGB structs use r/g/b byte channels for its two gray shades and matching
	single-color shade */
	transparency_focus = "";
	transparency_draft_mode = "block";
	transparency_draft_color_1 = { r: 214, g: 214, b: 218 };
	transparency_draft_color_2 = { r: 164, g: 166, b: 172 };
	transparency_draft_single_color = { r: 164, g: 166, b: 172 };

	/* Draft checker size is editable text starting at two source cells per block, separate from the
	parsed numeric setting */
	transparency_draft_block_size_text = "2";

	/* RGB and HSV UI channels both use 0..255.
	Hue wraps over a full color wheel */
	/* Current RGB bytes begin with the gold swatch and current_hue/saturation/value initialize its HSV
	controls. These channel sets stay synchronized when painting color changes */
	current_red = 255;
	current_green = 220;
	current_blue = 95;
	current_hue = 36;
	current_saturation = 160;
	current_value = 255;

	/* Authored swatches are reusable preset colors. Every entry's r/g/b fields are red, green and blue
	bytes from zero to 255, shown and copied by the palette UI */
	swatches =
	[
		{ r: 255, g: 255, b: 255 },
		{ r: 255, g: 220, b: 95 },
		{ r: 244, g: 84, b: 84 },
		{ r: 94, g: 215, b: 122 },
		{ r: 84, g: 164, b: 244 },
		{ r: 190, g: 112, b: 244 },
		{ r: 35, g: 37, b: 42 }
	];
	#endregion /* Editor State END */

	#region /* Color and Transparency Settings */
	/// @description Convert a numeric value to an integer RGB or HSV byte
	/// @param {Real} raw_value Numeric channel value
	/// @returns {Real} Floored value clamped to zero through 255
	clamp_byte = function(raw_value)
	{
		return clamp(floor(real(raw_value)), 0, 255);
	}

	/// @description Replace editor feedback for three current_time seconds
	/// @param {String} text Feedback message
	/// @param {Real} colour Draw color, default c_white
	set_status = function(text, colour = c_white)
	{
		status_text = string(text);
		status_colour = colour;
		status_until = current_time + 3000;
	}

	/// @description Keep decimal digits in their original order for numeric text fields
	/// @param {String} raw_text Text to filter
	/// @returns {String} Digits zero through nine, or empty text
	digits_only = function(raw_text)
	{
		/* source_text is the string to filter and result starts empty before valid digits are appended
		in order */
		var source_text = string(raw_text);
		var result = "";

		/* char_pos starts at one because GML strings are one-based and continues through the final
		source character */
		for (var char_pos = 1; char_pos <= string_length(source_text); char_pos++)
		{
			/* Current character's codepoint distinguishes decimal digits from punctuation or letters
			in numeric UI input */
			var codepoint = string_ord_at(source_text, char_pos);

			/* Only codepoints for digits zero through nine are kept. Other characters are skipped so
			draft sizes can be parsed numerically */
			if (codepoint >= 48 && codepoint <= 57)
			{
				result += string_char_at(source_text, char_pos);
			}
		}

		return result;
	}

	/// @description Create independently clamped red, green and blue byte channels
	/// @param {Real} raw_red Red byte value
	/// @param {Real} raw_green Green byte value
	/// @param {Real} raw_blue Blue byte value
	/// @returns {Struct} Fresh r/g/b byte record
	rgb_struct = function(raw_red, raw_green, raw_blue)
	{
		/* Return a new RGB record whose r, g and b are independently clamped byte channels, avoiding
		shared mutable color objects */
		return
		{
			r: clamp_byte(raw_red),
			g: clamp_byte(raw_green),
			b: clamp_byte(raw_blue)
		};
	}

	/// @description Copy clamped RGB channels or use the default gray for nonstruct input
	/// @param {Struct} source_colour Record with r/g/b channels
	/// @returns {Struct} Fresh RGB byte record
	copy_rgb_struct = function(source_colour)
	{
		/* Malformed nonstruct colors fall back to the default gray. Valid RGB structs are copied and
		clamped below */
		if (!is_struct(source_colour))
		{
			return rgb_struct(164, 166, 172);
		}

		return rgb_struct(source_colour.r, source_colour.g, source_colour.b);
	}

	/// @description Create the authored checker colors, single color and two-cell block size
	/// @returns {Struct} Fresh transparency display settings
	transparency_default_settings = function()
	{
		/* Default settings use block mode with light color_1, darker color_2 and matching
		single_color. block_size starts at two source cells and saved INI values can replace these
		defaults */
		return
		{
			mode: "block",
			color_1: rgb_struct(214, 214, 218),
			color_2: rgb_struct(164, 166, 172),
			single_color: rgb_struct(164, 166, 172),
			block_size: 2
		};
	}

	/// @description Bound a checker block size to the supported two through 999 source cells
	/// @param {Real} raw_value Requested block size
	/// @returns {Real} Floored clamped source-cell size
	clamp_transparency_block_size = function(raw_value)
	{
		return clamp(floor(real(raw_value)), 2, 999);
	}

	/// @description Parse digits from checker-size input and retain a fallback when empty
	/// @param {String} raw_text Draft numeric field text
	/// @param {Real} fallback_value Existing or default source-cell size
	/// @returns {Real} Clamped two through 999 cell size
	transparency_block_size_from_text = function(raw_text, fallback_value)
	{
		/* Digit-only copy of the user's block-size text removes nonnumeric input before conversion */
		var clean_text = digits_only(raw_text);

		/* Empty filtered text keeps the supplied prior/default size, clamped to the supported range.
		Entered digits replace that fallback */
		if (clean_text == "")
		{
			return clamp_transparency_block_size(fallback_value);
		}

		return clamp_transparency_block_size(real(clean_text));
	}

	/// @description Reuse shared transparency settings or restore authored defaults and saved INI fields
	/// @returns {Struct} Shared mutable transparency background settings
	ensure_transparency_settings = function()
	{
		/* Reuse an existing shared settings struct so display reads do not repeatedly reload defaults
		or disk state */
		if (variable_global_exists("sprite_editor_transparency_background")
		&& is_struct(global.sprite_editor_transparency_background))
		{
			return global.sprite_editor_transparency_background;
		}

		/* Fresh default settings are the starting point for absent INI fields and are later retained
		globally */
		var settings = transparency_default_settings();

		/* Only an existing client settings file is opened for restoration. Missing files preserve the
		authored defaults */
		if (file_exists(settings_file))
		{
			ini_open(settings_file);

			/* Only saved single mode selects one color. Every other saved string falls back to checker
			blocks, including malformed or legacy values */
			settings.mode = string_lower(string(ini_read_string(transparency_settings_section, "mode", settings.mode))) == "single" ? "single" : "block";
			settings.color_1 = rgb_struct(
				ini_read_real(transparency_settings_section, "color_1_r", settings.color_1.r),
				ini_read_real(transparency_settings_section, "color_1_g", settings.color_1.g),
				ini_read_real(transparency_settings_section, "color_1_b", settings.color_1.b)
			);
			settings.color_2 = rgb_struct(
				ini_read_real(transparency_settings_section, "color_2_r", settings.color_2.r),
				ini_read_real(transparency_settings_section, "color_2_g", settings.color_2.g),
				ini_read_real(transparency_settings_section, "color_2_b", settings.color_2.b)
			);
			settings.single_color = rgb_struct(
				ini_read_real(transparency_settings_section, "single_r", settings.single_color.r),
				ini_read_real(transparency_settings_section, "single_g", settings.single_color.g),
				ini_read_real(transparency_settings_section, "single_b", settings.single_color.b)
			);
			settings.block_size = clamp_transparency_block_size(ini_read_real(transparency_settings_section, "block_size", settings.block_size));
			ini_close();
		}

		/* The shared transparency settings global first receives this verified default/restored record
		and subsequent accesses reuse it */
		global.sprite_editor_transparency_background = settings;
		return global.sprite_editor_transparency_background;
	}

	/// @description Access the shared lazily restored transparency display settings
	/// @returns {Struct} Shared mutable settings record
	transparency_settings = function()
	{
		return ensure_transparency_settings();
	}

	/// @description Write shared transparency colors, mode and block size to the client INI section
	/// @returns {Bool} True after the INI writes complete
	save_transparency_settings = function()
	{
		/* Shared settings record supplies the mode, RGB byte channels and checker size written into
		their own INI section */
		var settings = transparency_settings();
		ini_open(settings_file);
		ini_write_string(transparency_settings_section, "mode", settings.mode);
		ini_write_real(transparency_settings_section, "color_1_r", settings.color_1.r);
		ini_write_real(transparency_settings_section, "color_1_g", settings.color_1.g);
		ini_write_real(transparency_settings_section, "color_1_b", settings.color_1.b);
		ini_write_real(transparency_settings_section, "color_2_r", settings.color_2.r);
		ini_write_real(transparency_settings_section, "color_2_g", settings.color_2.g);
		ini_write_real(transparency_settings_section, "color_2_b", settings.color_2.b);
		ini_write_real(transparency_settings_section, "single_r", settings.single_color.r);
		ini_write_real(transparency_settings_section, "single_g", settings.single_color.g);
		ini_write_real(transparency_settings_section, "single_b", settings.single_color.b);
		ini_write_real(transparency_settings_section, "block_size", settings.block_size);
		ini_close();
		return true;
	}

	/// @description Keep the retired transparency-settings dialog closed
	/// @returns {Bool} Always false because the editor uses the authored scrolling background sprite
	begin_transparency_modal = function()
	{
		/* Jonna replaced the configurable rectangle checkerboards with spr_transparent_background to reduce editor lag
		Only the editable canvas shows that scrolling sprite, while thumbnails and previews omit the pattern
		The old settings controls and shortcut were deliberately removed, so reopening this dialog would revive an abandoned UI */
		return false;
	}

	/// @description Dismiss transparency drafts and release both draft and keyboard focus
	/// @returns {Bool} True after modal dismissal
	cancel_transparency_modal = function()
	{
		modal = "";
		transparency_focus = "";
		keyboard_focus = "";
		keyboard_string = "";
		return true;
	}

	/// @description Apply clamped draft transparency settings, persist them and dismiss the modal
	/// @returns {Bool} True after settings and feedback are updated
	apply_transparency_modal = function()
	{
		/* Existing shared settings record is updated from the modal drafts before persistence and
		modal dismissal */
		var settings = transparency_settings();

		/* A draft of single selects single mode. Other draft values select block mode so saved display
		behavior remains one of the supported formats */
		settings.mode = transparency_draft_mode == "single" ? "single" : "block";
		settings.color_1 = copy_rgb_struct(transparency_draft_color_1);
		settings.color_2 = copy_rgb_struct(transparency_draft_color_2);
		settings.single_color = copy_rgb_struct(transparency_draft_single_color);
		settings.block_size = transparency_block_size_from_text(transparency_draft_block_size_text, settings.block_size);
		global.sprite_editor_transparency_background = settings;
		save_transparency_settings();
		cancel_transparency_modal();
		set_status("Transparency background updated.", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Convert clamped RGB bytes into the editor's 0..255 hue, saturation and value channels
	/// @param {Real} raw_red Red byte value
	/// @param {Real} raw_green Green byte value
	/// @param {Real} raw_blue Blue byte value
	set_hsv_from_rgb = function(raw_red, raw_green, raw_blue)
	{
		/* rgb_red/green/blue normalize clamped bytes to 0..1 for HSV conversion.
		max_channel/min_channel find brightness and channel_delta measures chroma */
		var rgb_red = clamp_byte(raw_red) / 255;
		var rgb_green = clamp_byte(raw_green) / 255;
		var rgb_blue = clamp_byte(raw_blue) / 255;
		var max_channel = max(rgb_red, max(rgb_green, rgb_blue));
		var min_channel = min(rgb_red, min(rgb_green, rgb_blue));
		var channel_delta = max_channel - min_channel;

		/* hue_degrees starts zero for gray or black, where no channel difference can define a hue */
		var hue_degrees = 0;

		/* Only nonzero chroma needs hue calculation and division by channel_delta. Gray colors retain
		the zero hue fallback */
		if (channel_delta > 0)
		{
			/* Red as the maximum selects the red-centered hue sector */
			if (max_channel == rgb_red)
			{
				hue_degrees = 60 * ((rgb_green - rgb_blue) / channel_delta);
			}

			/* When red is not the maximum, a green maximum selects the sector offset by two sixths of
			the color wheel */
			else if (max_channel == rgb_green)
			{
				hue_degrees = 60 * (((rgb_blue - rgb_red) / channel_delta) + 2);
			}

			/* The remaining blue maximum selects the sector offset by four sixths of the wheel */
			else
			{
				hue_degrees = 60 * (((rgb_red - rgb_green) / channel_delta) + 4);
			}
		}

		/* Negative sector angles wrap forward by one full turn so stored hue remains in the
		nonnegative color-wheel range */
		if (hue_degrees < 0)
		{
			hue_degrees += 360;
		}

		/* An angle reaching a full turn wraps back to its start, keeping zero and 360 degrees
		equivalent */
		if (hue_degrees >= 360)
		{
			hue_degrees -= 360;
		}

		current_hue = clamp(round(hue_degrees / 360 * 255), 0, 255);

		/* Black has zero saturation because its maximum channel is zero. Other colors use chroma
		divided by brightness, then map back to a byte */
		current_saturation = max_channel <= 0 ? 0 : clamp(round(channel_delta / max_channel * 255), 0, 255);
		current_value = clamp(round(max_channel * 255), 0, 255);
	}

	/// @description Convert byte-scaled HSV into a fresh clamped RGB record, wrapping the full-turn hue endpoint
	/// @param {Real} raw_hue Hue from zero to 255
	/// @param {Real} raw_saturation Saturation from zero to 255
	/// @param {Real} raw_value Brightness from zero to 255
	/// @returns {Struct} r/g/b byte channels
	hsv_to_rgb_struct = function(raw_hue, raw_saturation, raw_value)
	{
		/* Hue byte becomes a degree angle across a full turn for RGB sector selection */
		var hue_degrees = clamp(real(raw_hue), 0, 255) / 255 * 360;

		/* The 255 endpoint wraps to zero degrees so both ends of the hue slider represent the same
		wheel position */
		if (hue_degrees >= 360)
		{
			hue_degrees = 0;
		}

		/* saturation_amount/value_amount normalize their bytes, chroma is the saturated brightness,
		section is a 60-degree sector and section_mod2/hsv_mix interpolate its changing channel */
		var saturation_amount = clamp(real(raw_saturation), 0, 255) / 255;
		var value_amount = clamp(real(raw_value), 0, 255) / 255;
		var chroma = value_amount * saturation_amount;
		var section = hue_degrees / 60;
		var section_mod2 = section - floor(section / 2) * 2;
		var hsv_mix = chroma * (1 - abs(section_mod2 - 1));

		/* channel_red/green/blue begin at zero before the hue sector assigns chroma and its
		intermediate mix */
		var channel_red = 0;
		var channel_green = 0;
		var channel_blue = 0;

		/* The first sector blends red toward yellow by increasing green while blue remains zero */
		if (section < 1)
		{
			channel_red = chroma;
			channel_green = hsv_mix;
		}

		/* The second sector blends yellow toward green, retaining green chroma and reducing red */
		else if (section < 2)
		{
			channel_red = hsv_mix;
			channel_green = chroma;
		}

		/* The third sector blends green toward cyan by increasing blue */
		else if (section < 3)
		{
			channel_green = chroma;
			channel_blue = hsv_mix;
		}

		/* The fourth sector blends cyan toward blue by reducing green */
		else if (section < 4)
		{
			channel_green = hsv_mix;
			channel_blue = chroma;
		}

		/* The fifth sector blends blue toward magenta by increasing red */
		else if (section < 5)
		{
			channel_red = hsv_mix;
			channel_blue = chroma;
		}

		/* The final sector blends magenta toward red by reducing blue, completing the hue wheel */
		else
		{
			channel_red = chroma;
			channel_blue = hsv_mix;
		}

		/* match_value adds the unsaturated brightness shared by all channels. Returned r/g/b scale and
		clamp the resulting colors back to byte values */
		var match_value = value_amount - chroma;
		return
		{
			r: clamp(round((channel_red + match_value) * 255), 0, 255),
			g: clamp(round((channel_green + match_value) * 255), 0, 255),
			b: clamp(round((channel_blue + match_value) * 255), 0, 255)
		};
	}

	/// @description Convert byte-scaled HSV into a GameMaker draw color
	/// @param {Real} raw_hue Hue byte
	/// @param {Real} raw_saturation Saturation byte
	/// @param {Real} raw_value Brightness byte
	/// @returns {Real} GameMaker RGB color
	hsv_to_colour = function(raw_hue, raw_saturation, raw_value)
	{
		/* New RGB byte record converted from the supplied HSV values before making a GameMaker draw
		color */
		var rgb = hsv_to_rgb_struct(raw_hue, raw_saturation, raw_value);
		return make_color_rgb(rgb.r, rgb.g, rgb.b);
	}

	/// @description Synchronize painting RGB bytes from the current HSV slider channels
	set_current_colour_from_hsv = function()
	{
		/* RGB bytes converted from the editor's current HSV channels to synchronize pen color with
		slider changes */
		var rgb = hsv_to_rgb_struct(current_hue, current_saturation, current_value);
		current_red = rgb.r;
		current_green = rgb.g;
		current_blue = rgb.b;
	}

	/// @description Store clamped painting RGB and synchronize HSV slider channels
	/// @param {Real} raw_red Red byte value
	/// @param {Real} raw_green Green byte value
	/// @param {Real} raw_blue Blue byte value
	set_current_colour_rgb = function(raw_red, raw_green, raw_blue)
	{
		current_red = clamp_byte(raw_red);
		current_green = clamp_byte(raw_green);
		current_blue = clamp_byte(raw_blue);
		set_hsv_from_rgb(current_red, current_green, current_blue);
	}
	#endregion /* Color and Transparency Settings END */

	#region /* RGBA Data and Surface Caches */
	/// @description Decode one hexadecimal digit, using zero for absent or unrecognized characters
	/// @param {String} raw_char Hexadecimal digit
	/// @returns {Real} Numeric nibble from zero to 15
	hex_value = function(raw_char)
	{
		/* One-based position in the hex alphabet becomes the numeric nibble value, with
		missing/invalid characters falling back to zero */
		var digit_index = string_pos(string_upper(string(raw_char)), "0123456789ABCDEF");
		return max(0, digit_index - 1);
	}

	/// @description Decode a byte from two adjacent hexadecimal characters
	/// @param {String} hex_text Source hex string
	/// @param {Real} offset One-based index of the first character
	/// @returns {Real} Byte from zero to 255
	hex_pair_to_byte = function(hex_text, offset)
	{
		return hex_value(string_char_at(hex_text, offset)) * 16 + hex_value(string_char_at(hex_text, offset + 1));
	}

	/// @description Serialize a temporary transparent frame without replacing active editing pixels
	/// @returns {String} Row-major RRGGBBAA frame snapshot
	blank_frame_hex = function()
	{
		/* Temporary blank pixel-editor struct creates a transparent frame snapshot without replacing
		the active mutable editor */
		var blank_editor = new scr_pixel_editor(frame_w, frame_h);
		return blank_editor.to_hex_string();
	}

	/// @description Free the owned live-frame GPU cache and mark it unallocated and dirty
	/// @returns {Bool} True after cache reset
	free_editor_surface_cache = function()
	{
		/* Free the active GPU surface only when it still exists. Lost or unallocated handles need no
		release */
		if (surface_exists(editor_surface))
		{
			surface_free(editor_surface);
		}
		editor_surface = noone;
		editor_surface_dirty = true;
		return true;
	}

	/// @description Free owned thumbnail surfaces and reset all twelve handles and dirty flags
	/// @returns {Bool} True after cache arrays are rebuilt
	reset_frame_surface_cache = function()
	{
		/* frame_index starts at slot zero and releases every owned frame-preview cache that still
		exists */
		for (var frame_index = 0; frame_index < array_length(frame_surfaces); frame_index++)
		{
			/* Only live surfaces are freed, avoiding invalid release calls for lost or unallocated
			preview handles */
			if (surface_exists(frame_surfaces[frame_index]))
			{
				surface_free(frame_surfaces[frame_index]);
			}
		}
		frame_surfaces = array_create(column_count * row_count, noone);
		frame_surface_dirty = array_create(column_count * row_count, true);
		return true;
	}

	/// @description Invalidate one valid frame thumbnail without changing its pixels
	/// @param {Real} frame_index Row-major frame slot, floored before bounds checking
	/// @returns {Bool} Whether a valid slot was marked dirty
	mark_frame_surface_dirty = function(frame_index)
	{
		/* Floored frame slot identifies which preview dirty flag should change */
		var safe_index = floor(real(frame_index));

		/* Only slots inside frame_surface_dirty can be invalidated. Out-of-range requests return false
		without changing the cache array */
		if (safe_index >= 0 && safe_index < array_length(frame_surface_dirty))
		{
			frame_surface_dirty[safe_index] = true;
			return true;
		}
		return false;
	}

	/// @description Invalidate live-frame drawing and its active thumbnail after mutable pixel operations
	/// @returns {Bool} True after dirty flags are set
	mark_editor_surface_dirty = function()
	{
		editor_surface_dirty = true;
		mark_frame_surface_dirty(active_frame);
		return true;
	}

	/// @description Free all owned HSV gradient surfaces and clear their content keys
	/// @returns {Bool} True after gradient cache disposal
	free_hsv_surfaces = function()
	{
		/* Release the hue gradient only when its surface exists */
		if (surface_exists(hsv_surface_hue))
		{
			surface_free(hsv_surface_hue);
		}

		/* Release the saturation gradient only when its surface exists */
		if (surface_exists(hsv_surface_saturation))
		{
			surface_free(hsv_surface_saturation);
		}

		/* Release the value gradient only when its surface exists, then reset all cache handles and
		keys together */
		if (surface_exists(hsv_surface_value))
		{
			surface_free(hsv_surface_value);
		}
		hsv_surface_hue = noone;
		hsv_surface_saturation = noone;
		hsv_surface_value = noone;
		hsv_key_hue = "";
		hsv_key_saturation = "";
		hsv_key_value = "";
		return true;
	}

	/// @description Paint one RRGGBBAA frame into a supplied surface and restore the draw target
	/// @param {Id.Surface} target_surface Caller-owned frame-sized surface
	/// @param {String} hex_text Row-major frame snapshot with eight hex characters per pixel
	/// @returns {Bool} Whether the target existed and was painted
	draw_hex_to_surface = function(target_surface, hex_text)
	{
		/* An absent target surface cannot receive pixels, so return false before setting any render
		target */
		if (!surface_exists(target_surface))
		{
			return false;
		}

		/* String snapshot supplies row-major RRGGBBAA bytes used to redraw this frame cache */
		var source_hex = string(hex_text);
		surface_set_target(target_surface);
		draw_clear_alpha(c_black, 0);

		/* pixel_row visits source rows zero through frame_h minus one, matching snapshot row-major
		order */
		for (var pixel_row = 0; pixel_row < frame_h; pixel_row++)
		{
			/* pixel_col visits every source column in the current row */
			for (var pixel_col = 0; pixel_col < frame_w; pixel_col++)
			{
				/* hex_offset is this pixel's one-based eight-character start and pixel_alpha decodes
				its final alpha byte */
				var hex_offset = (pixel_row * frame_w + pixel_col) * 8 + 1;
				var pixel_alpha = hex_pair_to_byte(source_hex, hex_offset + 6);

				/* Nonzero alpha pixels draw their color and opacity. Transparent pixels retain the
				cleared surface background */
				if (pixel_alpha > 0)
				{
					draw_set_alpha(pixel_alpha / 255);
					draw_set_colour(make_color_rgb(hex_pair_to_byte(source_hex, hex_offset), hex_pair_to_byte(source_hex, hex_offset + 2), hex_pair_to_byte(source_hex, hex_offset + 4)));
					draw_rectangle(pixel_col, pixel_row, pixel_col + 1, pixel_row + 1, false);
				}
			}
		}
		draw_set_alpha(1);
		surface_reset_target();
		return true;
	}

	/// @description Recreate a lost or resized active-frame surface and redraw only when dirty
	/// @returns {Id.Surface|Real} Cached active-frame surface, or noone when no editor is open
	ensure_editor_surface = function()
	{
		/* The active surface is available only for an open editor with mutable pixel state. Other
		states return noone */
		if (!open || !is_struct(editor))
		{
			return noone;
		}

		/* A surviving surface of the wrong frame size is freed and marked dirty before recreation,
		preventing reuse with incompatible dimensions */
		if (surface_exists(editor_surface)
		&& (surface_get_width(editor_surface) != frame_w || surface_get_height(editor_surface) != frame_h))
		{
			surface_free(editor_surface);
			editor_surface = noone;
			editor_surface_dirty = true;
		}

		/* Missing or lost active surfaces are recreated and marked dirty. Live matching-size surfaces
		retain their allocation */
		if (!surface_exists(editor_surface))
		{
			editor_surface = surface_create(frame_w, frame_h);
			editor_surface_dirty = true;
		}

		/* Redraw only a live surface whose pixels are dirty. A clean cache is reused and failed
		allocation leaves it dirty for a later attempt */
		if (surface_exists(editor_surface) && editor_surface_dirty)
		{
			editor.draw_to_surface(editor_surface);
			editor_surface_dirty = false;
		}

		return editor_surface;
	}

	/// @description Use the live editor surface for the active frame and cached RGBA snapshots for other frames
	/// @param {Real} frame_index Zero-based row-major frame index
	/// @returns {Id.Surface|Real} Frame preview surface, or noone for an invalid index
	ensure_frame_surface = function(frame_index)
	{
		/* Floored row-major frame slot used for all cache and snapshot accesses */
		var safe_index = floor(real(frame_index));

		/* Reject negative slots and slots beyond available snapshots before indexing either cache or
		frames */
		if (safe_index < 0 || safe_index >= array_length(frames))
		{
			return noone;
		}

		/* The active slot in an open editor uses live mutable pixels so preview thumbnails reflect
		unsaved edits rather than the last committed snapshot */
		if (safe_index == active_frame && open && is_struct(editor))
		{
			return ensure_editor_surface();
		}

		/* Different snapshot and cache counts reset all preview caches so slot arrays align before
		lookup */
		if (array_length(frame_surfaces) != array_length(frames))
		{
			reset_frame_surface_cache();
		}

		/* A live preview with mismatched frame dimensions is released and marked dirty, ready for a
		correctly sized replacement */
		if (surface_exists(frame_surfaces[safe_index])
		&& (surface_get_width(frame_surfaces[safe_index]) != frame_w || surface_get_height(frame_surfaces[safe_index]) != frame_h))
		{
			surface_free(frame_surfaces[safe_index]);
			frame_surfaces[safe_index] = noone;
			frame_surface_dirty[safe_index] = true;
		}

		/* Missing preview surfaces are allocated lazily for the requested slot and marked dirty for
		their first draw */
		if (!surface_exists(frame_surfaces[safe_index]))
		{
			frame_surfaces[safe_index] = surface_create(frame_w, frame_h);
			frame_surface_dirty[safe_index] = true;
		}

		/* Only a live dirty preview is repainted from its snapshot. Clean surfaces retain content
		without repeating hex decoding */
		if (surface_exists(frame_surfaces[safe_index]) && frame_surface_dirty[safe_index])
		{
			draw_hex_to_surface(frame_surfaces[safe_index], frames[safe_index]);
			frame_surface_dirty[safe_index] = false;
		}

		return frame_surfaces[safe_index];
	}
	#endregion /* RGBA Data and Surface Caches END */

	#region /* Animation Frame State */
	/// @description Replace the sheet with twelve transparent frames and a fresh active-frame editor
	reset_frames = function()
	{
		reset_frame_surface_cache();
		free_editor_surface_cache();
		frames = array_create(column_count * row_count);

		/* One transparent-frame RRGGBBAA snapshot is reused to initialize every animation slot */
		var blank_hex = blank_frame_hex();

		/* frame_index fills frames from slot zero through the full grid count, giving every direction
		and pose a transparent starting image */
		for (var frame_index = 0; frame_index < array_length(frames); frame_index++)
		{
			frames[frame_index] = blank_hex;
		}

		active_frame = 0;
		editor_view_col = 0;
		editor_view_row = 0;
		editor = new scr_pixel_editor(frame_w, frame_h);
		editor.load_hex_string(frames[active_frame]);
		mark_editor_surface_dirty();
	}

	/// @description Serialize the active editor into its frame slot before switching frames or saving
	commit_active_frame = function()
	{
		/* Commit only when the mutable editor exists and active_frame is a valid snapshot slot.
		Otherwise leave frame storage unchanged */
		if (is_struct(editor)
		&& active_frame >= 0
		&& active_frame < array_length(frames))
		{
			/* Fresh RRGGBBAA snapshot of the active mutable pixels used to detect whether its
			committed representation changed */
			var next_hex = editor.to_hex_string();

			/* A changed snapshot replaces its frame slot and invalidates that preview. Identical
			pixels retain the existing cached snapshot */
			if (frames[active_frame] != next_hex)
			{
				frames[active_frame] = next_hex;
				mark_frame_surface_dirty(active_frame);
			}
		}
	}

	/// @description Commit the old frame, then create a new pixel editor and undo history for the selected frame
	/// @param {Real} next_frame Zero-based row-major frame index, clamped to the sheet
	load_active_frame = function(next_frame)
	{
		commit_active_frame();
		active_frame = clamp(floor(real(next_frame)), 0, array_length(frames) - 1);
		editor_view_col = 0;
		editor_view_row = 0;
		editor = new scr_pixel_editor(frame_w, frame_h);
		editor.load_hex_string(frames[active_frame]);
		mark_editor_surface_dirty();
	}

	/// @description Name a facing row for thumbnails and tooltips
	/// @param {Real} frame_row Facing row from PLAYER_DIRECTION constants
	/// @returns {String} Direction label, defaulting to Down for unknown rows
	frame_direction_label = function(frame_row)
	{
		/* Facing-row constants choose their readable direction label. Unknown row values fall back to
		Down after the switch */
		switch (floor(real(frame_row)))
		{
			/* Down uses the first facing-row label */
			case PLAYER_DIRECTION_DOWN: return "Down";

			/* Left uses the second facing-row label */
			case PLAYER_DIRECTION_LEFT: return "Left";

			/* Right uses the third facing-row label */
			case PLAYER_DIRECTION_RIGHT: return "Right";

			/* Up uses the final facing-row label */
			case PLAYER_DIRECTION_UP: return "Up";
		}

		return "Down";
	}

	/// @description Name one of the three animation poses
	/// @param {Real} frame_col Zero-based animation column
	/// @returns {String} Walk 1, Idle, Walk 2 or the generic Frame label
	frame_column_label = function(frame_col)
	{
		/* Animation columns map to first walk, idle and second walk pose names. Unknown columns use
		the general Frame label */
		switch (floor(real(frame_col)))
		{
			/* Column zero names the first walking pose */
			case 0: return "Walk 1";

			/* Column one names the standing idle pose */
			case 1: return "Idle";

			/* Column two names the second walking pose */
			case 2: return "Walk 2";
		}

		return "Frame";
	}

	/// @description Explain a pose's role in the timed walk or idle animation
	/// @param {Real} frame_col Zero-based animation column
	/// @returns {String} Pose tooltip detail or a general frame description
	frame_column_detail = function(frame_col)
	{
		/* Each animation column gets matching tooltip guidance for its role in the walk cycle, with
		general text for unknown columns */
		switch (floor(real(frame_col)))
		{
			/* The first walking column explains the first pose of the timed cycle */
			case 0: return "First walking pose in the step animation.";

			/* The middle column explains the standing pose used at rest */
			case 1: return "Standing pose used when this direction is idle.";

			/* The final column explains the second walking pose */
			case 2: return "Second walking pose in the step animation.";
		}

		return "Animation frame.";
	}
	#endregion /* Animation Frame State END */

	#region /* Editor Session and Character Saving */
	/// @description Call the shared client's movement-release hook before editor input ownership
	/// @returns {Bool} Hook result, or false when that client capability is unavailable
	release_local_movement = function()
	{
		/* Shared client can release currently held movement before editor UI takes ownership */
		var client = scr_get_client();

		/* When the client provides its release hook, return that operation's result. Without it,
		return false rather than assuming input was released */
		if (is_struct(client)
		&& variable_struct_exists(client, "release_local_movement"))
		{
			return client.release_local_movement();
		}
		return false;
	}

	/// @description Keep gameplay input captured throughout the editor and all its modal dialogs
	/// @returns {Bool} Whether the editor or any modal is open
	blocks_game_input = function()
	{
		/* Either an open main editor or a nonempty modal captures gameplay input, including entry and
		loading dialogs before editable pixels are visible */
		return open || modal != "";
	}

	/// @description Close chat and release local movement before opening the character-maker entry dialog
	/// @returns {Bool} True after opening the start modal
	/// @param {String} target Save destination, player or pet
	/// @param {String} source_key_value Pet artwork key, default empty for a blank companion
	open_start = function(target = "player", source_key_value = "")
	{
		scr_get_chat().close();
		release_local_movement();
		editing_target = target == "pet" ? "pet" : "player";
		requested_source_key = string(source_key_value);
		modal = "start";
		open = false;
		hover_key = "";
		keyboard_focus = "";
		return true;
	}

	/// @description Create a transparent character sheet that will save as a new custom character
	/// @returns {Bool} True after opening the blank editor
	begin_new_blank = function()
	{
		reset_frames();
		source_key = "";
		source_label = editing_target == "pet" ? "New Pet" : "New Character";
		source_can_overwrite = false;
		save_name = editing_target == "pet" ? "Custom Pet" : "Custom Character";
		editor_tool = PIXEL_EDITOR_TOOL_PEN;
		editor_dirty = false;
		open = true;
		modal = "";
		set_status(editing_target == "pet" ? "Started a blank pet." : "Started a blank character.", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Queue the selected character for one-frame-per-Step loading without replacing existing edits yet
	/// @returns {Bool} Whether the registry supplied a loaded source sheet
	begin_edit_current = function()
	{
		/* A removed companion has no source to edit. New Blank remains available in the same dialog */
		if (editing_target == "pet" && requested_source_key == "")
		{
			return false;
		}

		/* registry owns selected character sources and source is its loaded sheet plus key, label and
		overwrite permission for this editing request */
		var registry = scr_get_player_characters();
		var source = editing_target == "pet" ? registry.editor_source_for_key(requested_source_key) : registry.selected_editor_source();

		/* A source marked not ok cannot supply editable frames. Keep current edits intact, show its
		registry error and return false */
		if (!source.ok)
		{
			registry.set_status(source.message, make_color_rgb(244, 84, 84));
			set_status(source.message, make_color_rgb(244, 84, 84));
			return false;
		}

		loading_source = source;
		loading_frames = array_create(column_count * row_count);
		loading_frame = 0;
		modal = "loading";
		open = false;
		hover_key = "";
		return true;
	}

	/// @description Read one source animation cell and adopt the new editor only after all twelve frames succeed
	/// @returns {Bool} Whether loading advanced or completed. Returns false when inactive or extraction fails
	update_character_load = function()
	{
		/* Advance extraction only in the loading modal with a source struct. Other session states
		return false without consuming queued frames */
		if (modal != "loading" || !is_struct(loading_source)) return false;

		/* Read one animation frame per Step so input and network maintenance can run */
		/* Local source reference retains metadata through the final adoption after loading_source is
		cleared */
		var source = loading_source;
		try
		{
			/* frame_row/col decode the pending row-major slot, source_x/y account for its sheet
			cell/gutter and frame_result contains the extracted source-sized RRGGBBAA snapshot or
			error */
			var frame_row = loading_frame div column_count;
			var frame_col = loading_frame mod column_count;
			var source_x = frame_col * source.sheet_cell_w + source.sheet_gutter;
			var source_y = frame_row * source.sheet_cell_h + source.sheet_gutter;
			var frame_result = RgbaPng.sprite_region_to_rgba_hex(source.sprite, source_x, source_y, frame_w, frame_h, alpha_cutoff);

			/* Failed extraction throws its message into the common failure path, leaving the old
			editor intact and returning to the entry dialog */
			if (!frame_result.ok)
			{
				throw frame_result.message;
			}
			loading_frames[loading_frame++] = frame_result.hex;
		}
		catch(e)
		{
			loading_source = undefined;
			loading_frames = [];
			modal = "start";
			set_status((editing_target == "pet" ? "Could not open pet: " : "Could not open character: ") + scr_debug_export_exception_text(e), make_color_rgb(244, 84, 84));
			return false;
		}

		/* More pending frame slots keep the loading modal active after this successful extraction. The
		final frame continues to full-sheet adoption below */
		if (loading_frame < array_length(loading_frames)) return true;

		/* Keep the existing editor intact until every source frame was read successfully */
		reset_frame_surface_cache();
		free_editor_surface_cache();
		frames = loading_frames;
		loading_frames = [];
		loading_source = undefined;
		active_frame = 0;
		editor_view_col = 0;
		editor_view_row = 0;
		editor = new scr_pixel_editor(frame_w, frame_h);
		editor.load_hex_string(frames[active_frame]);
		mark_editor_surface_dirty();
		source_key = source.key;
		source_label = source.label;
		source_can_overwrite = source.can_overwrite;

		/* Installed editable custom sources retain their name for replacement. Other sources append
		Copy because saving must create a new custom character */
		save_name = source.can_overwrite ? source.label : source.label + " Copy";
		editor_tool = PIXEL_EDITOR_TOOL_PEN;
		editor_dirty = false;
		open = true;
		modal = "";

		/* Feedback describes the same overwrite permission that save_character later enforces */
		set_status(source.can_overwrite ? (editing_target == "pet" ? "Editing installed pet artwork." : "Editing installed custom character.") : "Editing will save a custom copy.", make_color_rgb(255, 220, 95));
		return true;
	}

	/// @description Close all editor UI and release editor, frame-preview, and HSV surface caches
	/// @returns {Bool} True after clearing session UI and temporary surfaces
	close_all = function()
	{
		loading_source = undefined;
		loading_frames = [];
		loading_frame = 0;
		open = false;
		modal = "";
		hover_key = "";
		keyboard_focus = "";
		keyboard_string = "";
		editor_dragging = false;
		active_slider = "";
		free_editor_surface_cache();
		reset_frame_surface_cache();
		free_hsv_surfaces();
		return true;
	}

	/// @description Ask before discarding a dirty editor. Close immediately when no pixel changes need saving
	/// @returns {Bool} True after opening discard confirmation or closing the editor
	request_close = function()
	{
		/* Dirty pixels require discard confirmation before closure. A clean session can close
		immediately without an extra dialog */
		if (editor_dirty)
		{
			modal = "discard";
			keyboard_focus = "";
			keyboard_string = "";
			return true;
		}

		return close_all();
	}

	/// @description Commit the active frame and give the name field ownership of keyboard_string
	/// @returns {Bool} True after opening the save modal
	open_save_modal = function()
	{
		commit_active_frame();
		modal = "save";
		keyboard_focus = "save_name";
		keyboard_string = save_name;
		return true;
	}

	/// @description Replace line breaks, trim whitespace and cap an editor character name at 32 characters
	/// @param {String} raw_text Name-field text
	/// @returns {String} Sanitized possibly empty display name
	clean_name_text = function(raw_text)
	{
		/* Name text begins with carriage returns replaced by spaces, then removes line feeds and trims
		whitespace before its length check */
		var text = string_replace_all(string(raw_text), "\r", " ");
		text = string_replace_all(text, "\n", " ");
		text = string_trim(text);

		/* Names above 32 characters are truncated to the editor's limit. Shorter names retain their
		complete sanitized text */
		if (string_length(text) > 32)
		{
			text = string_copy(text, 1, 32);
		}

		return text;
	}

	/// @description Interleave frame pixel rows into a contiguous 48 by 76 sheet in row-major RRGGBBAA order
	/// @returns {String} Eight hex characters per sheet pixel, with no render-time gutters
	build_sheet_hex = function()
	{
		commit_active_frame();

		/* sheet_hex starts empty and accumulates row-major RRGGBBAA pixels for the complete PNG sheet */
		var sheet_hex = "";

		/* frame_row walks facing directions from zero to row_count minus one */
		for (var frame_row = 0; frame_row < row_count; frame_row++)
		{
			/* pixel_row walks every source row inside that facing block so frames are interleaved
			horizontally, not concatenated as whole images */
			for (var pixel_row = 0; pixel_row < frame_h; pixel_row++)
			{
				/* frame_col visits each animation pose in order for the current source pixel row */
				for (var frame_col = 0; frame_col < column_count; frame_col++)
				{
					/* frame_hex supplies this row-major frame snapshot and row_offset is the one-based
					hex start of its current source pixel row */
					var frame_hex = frames[frame_row * column_count + frame_col];
					var row_offset = pixel_row * frame_w * 8 + 1;
					sheet_hex += string_copy(frame_hex, row_offset, frame_w * 8);
				}
			}
		}

		return sheet_hex;
	}

	/// @description Encode the committed sheet as PNG and save/select it through the character registry
	/// @returns {Bool} Whether saving succeeded. Failed saves keep the editor open with its error status
	save_character = function()
	{
		save_name = clean_name_text(keyboard_string);

		/* Blank sanitized save text becomes Custom Character so installation always has a usable
		display label */
		if (save_name == "")
		{
			save_name = editing_target == "pet" ? "Custom Pet" : "Custom Character";
		}

		/* sheet_hex is the committed full-grid snapshot and encode_result holds PNG base64 or a
		conversion failure */
		var sheet_hex = build_sheet_hex();
		var encode_result = RgbaPng.rgba_hex_to_png_base64(sheet_w, sheet_h, sheet_hex);

		/* A failed PNG encode shows its reason and returns false without closing the editor or losing
		unsaved pixels */
		if (!encode_result.ok)
		{
			set_status(encode_result.message, make_color_rgb(244, 84, 84));
			return false;
		}

		/* Shared registry performs actual custom installation, metadata update and selection after PNG
		encoding succeeds */
		var registry = scr_get_player_characters();

		/* Only installed local custom characters can be overwritten.
		Official/remote sources save a copy */
		/* existing_key identifies an installed overwritable custom source. Protected sources use empty
		text so the registry creates a new package instead */
		var existing_key = source_can_overwrite ? source_key : "";

		/* Failed registry saving keeps this editor open and copies its status into the editor. Success
		clears dirty state and closes the session below */
		if (!registry.save_editor_character_base64(encode_result.base64, save_name, existing_key, editing_target != "pet"))
		{
			set_status(registry.status_text, registry.status_colour);
			return false;
		}

		/* The registry stores pet artwork in the same library but only the companion selection changes */
		if (editing_target == "pet")
		{
			/* Artwork already saved successfully. Retain its key so retrying equipment persistence
			updates that package rather than creating another copy */
			source_key = registry.last_saved_key;
			source_label = save_name;
			source_can_overwrite = true;
			if (!scr_get_pets().equip_local(source_key))
			{
				set_status(registry.status_text, registry.status_colour);
				return false;
			}
		}

		editor_dirty = false;
		close_all();
		return true;
	}
	#endregion /* Editor Session and Character Saving END */

	#region /* GUI Geometry and Hit Testing */
	/// @description Center a requested GUI panel with fourteen-pixel outer margins
	/// @param {Real} raw_width Requested width in GUI pixels
	/// @param {Real} raw_height Requested height in GUI pixels
	/// @returns {Struct} GUI left/top/right/bottom and capped w/h
	modal_rect = function(raw_width, raw_height)
	{
		/* gui_w/h are current GUI canvas pixels. modal_w/h cap requested dimensions to leave 14-pixel
		margins, and modal_left/top center the resulting panel */
		var gui_w = display_get_gui_width();
		var gui_h = display_get_gui_height();
		var modal_w = min(raw_width, gui_w - 28);
		var modal_h = min(raw_height, gui_h - 28);
		var modal_left = (gui_w - modal_w) * 0.5;
		var modal_top = (gui_h - modal_h) * 0.5;

		/* Returned left/top/right/bottom are GUI edges and w/h are its capped size, giving drawing and
		hit testing the same modal rectangle */
		return
		{
			left: modal_left,
			top: modal_top,
			right: modal_left + modal_w,
			bottom: modal_top + modal_h,
			w: modal_w,
			h: modal_h
		};
	}

	/// @description Resolve the main editor's centered nominal 1040 by 680 GUI panel
	/// @returns {Struct} Main GUI edges and size capped by the canvas
	main_rect = function()
	{
		return modal_rect(1040, 680);
	}

	/// @description Derive visible cells from editor zoom while keeping the GUI viewport at its base size
	/// @returns {Struct} GUI rectangle with cell size, visible rows/columns, and full viewport bounds
	grid_rect = function()
	{
		/* rect is the main panel. base_cell_size fits unzoomed source pixels in its height and
		cell_size applies the current zoom percentage with a one-pixel minimum */
		var rect = main_rect();
		var base_cell_size = max(12, min(20, floor((rect.h - 250) / frame_h)));
		var cell_size = max(1, floor(base_cell_size * clamp(editor_zoom_percent, editor_zoom_min, editor_zoom_max) / 100));

		/* viewport_w/h retain the full base-grid GUI size when zoom changes. visible_cols/rows count
		whole source cells that fit at the zoomed cell size */
		var viewport_w = frame_w * base_cell_size;
		var viewport_h = frame_h * base_cell_size;
		cell_size = min(cell_size, max(1, min(viewport_w, viewport_h)));
		var visible_cols = min(frame_w, max(1, floor(viewport_w / cell_size)));
		var visible_rows = min(frame_h, max(1, floor(viewport_h / cell_size)));

		/* grid_left/top offset the drawing grid from the main panel to leave room for frame thumbnails
		and title text */
		var grid_left = rect.left + 278;
		var grid_top = rect.top + 74;

		/* Returned left/top/right/bottom enclose visible whole cells. cell/base_cell store zoomed/base
		GUI pixels, visible_cols/rows count source cells and viewport_right/bottom retain the fixed
		full viewport edges */
		return
		{
			left: grid_left,
			top: grid_top,
			right: grid_left + visible_cols * cell_size,
			bottom: grid_top + visible_rows * cell_size,
			cell: cell_size,
			base_cell: base_cell_size,
			visible_cols: visible_cols,
			visible_rows: visible_rows,
			viewport_right: grid_left + viewport_w,
			viewport_bottom: grid_top + viewport_h
		};
	}

	/// @description Place sidebar controls 28 GUI pixels after the grid viewport
	/// @returns {Real} Sidebar horizontal GUI coordinate
	side_left = function()
	{
		return grid_rect().viewport_right + 28;
	}

	/// @description Reserve sidebar space from its start to the main panel's right padding
	/// @returns {Real} Sidebar width in GUI pixels, with a 200-pixel minimum
	side_width = function()
	{
		/* Main panel rectangle supplies the right edge used to size the tools and color sidebar */
		var rect = main_rect();
		return max(200, rect.right - side_left() - 24);
	}

	/// @description Make a GUI edge record from position and dimensions
	/// @param {Real} rect_left Left GUI coordinate
	/// @param {Real} rect_top Top GUI coordinate
	/// @param {Real} rect_w GUI width
	/// @param {Real} rect_h GUI height
	/// @returns {Struct} left/top/right/bottom GUI edges
	make_rect = function(rect_left, rect_top, rect_w, rect_h)
	{
		/* Rectangle fields store GUI left/top and right/bottom calculated from the supplied width and
		height, sharing one edge format across editor controls */
		return { left: rect_left, top: rect_top, right: rect_left + rect_w, bottom: rect_top + rect_h };
	}

	/// @description Resolve a sidebar or grid-transform action's shared draw and hit rectangle
	/// @param {String} button_key Stable editor action key
	/// @returns {Struct} GUI rectangle, empty for an unknown action
	button_rect = function(button_key)
	{
		/* rect anchors the main panel and side_x/w locate its sidebar. button_h is the GUI row height,
		button_gap separates controls and group_gap separates tool and history groups */
		var rect = main_rect();
		var side_x = side_left();
		var side_w = side_width();
		var button_h = 30;
		var button_gap = 8;
		var group_gap = 14;

		/* half_w splits paired sidebar actions evenly. top_base, tool_row_1/2, history_row and
		clear_row identify their GUI y anchors, while save_top anchors the bottom row */
		var half_w = floor((side_w - button_gap) * 0.5);
		var top_base = rect.top + 74;
		var tool_row_1 = top_base + button_h + button_gap;
		var tool_row_2 = tool_row_1 + button_h + button_gap;
		var history_row = tool_row_2 + button_h + group_gap;
		var clear_row = history_row + button_h + button_gap;
		var save_top = rect.bottom - button_h - 10;

		/* Sidebar action keys choose their fixed tool, history or session row so drawing and hit
		testing use identical rectangles */
		switch (button_key)
		{
			/* Pen occupies the left half of the first tool row */
			case "pen": return make_rect(side_x, top_base, half_w, button_h);

			/* Eraser occupies the right half of the first tool row */
			case "eraser": return make_rect(side_x + half_w + button_gap, top_base, half_w, button_h);

			/* Fill occupies the left half of the second tool row */
			case "fill": return make_rect(side_x, tool_row_1, half_w, button_h);

			/* Picker occupies its right half */
			case "picker": return make_rect(side_x + half_w + button_gap, tool_row_1, half_w, button_h);

			/* Selection spans the full third tool row */
			case "select": return make_rect(side_x, tool_row_2, side_w, button_h);

			/* Undo occupies the left history control */
			case "undo": return make_rect(side_x, history_row, half_w, button_h);

			/* Redo occupies the right history control */
			case "redo": return make_rect(side_x + half_w + button_gap, history_row, half_w, button_h);

			/* Clear spans the full row beneath history */
			case "clear": return make_rect(side_x, clear_row, side_w, button_h);

			/* Save occupies the left half of the bottom session row */
			case "save": return make_rect(side_x, save_top, half_w, button_h);

			/* Cancel occupies the right half of that row */
			case "cancel": return make_rect(side_x + half_w + button_gap, save_top, half_w, button_h);
		}

		/* grid supplies the fixed viewport width for transform controls. transform_gap separates four
		equally sized transform_w buttons and transform_top initially starts below zoom controls */
		var grid = grid_rect();
		var transform_gap = 8;
		var transform_w = floor((grid.viewport_right - grid.left - transform_gap * 3) / 4);
		var transform_top = zoom_button_rect("zoom_out").bottom + 8;

		/* If cropped pixels require pan controls, place transforms below that additional row.
		Otherwise leave them directly below zoom controls */
		if (view_controls_visible())
		{
			transform_top = view_button_rect("view_left").bottom + 8;
		}

		/* Clipboard and transform keys occupy four-column rows below the grid, keeping their
		rectangles outside sidebar tool controls */
		switch (button_key)
		{
			/* Copy is the first control in the upper transform row */
			case "copy": return make_rect(grid.left, transform_top, transform_w, button_h);

			/* Paste occupies the second position in that row */
			case "paste": return make_rect(grid.left + (transform_w + transform_gap), transform_top, transform_w, button_h);

			/* Horizontal flip occupies the third position */
			case "flip_h": return make_rect(grid.left + (transform_w + transform_gap) * 2, transform_top, transform_w, button_h);

			/* Vertical flip occupies the final position */
			case "flip_v": return make_rect(grid.left + (transform_w + transform_gap) * 3, transform_top, transform_w, button_h);

			/* Left shift starts the lower transform row */
			case "shift_left": return make_rect(grid.left, transform_top + 40, transform_w, button_h);

			/* Right shift occupies its second position */
			case "shift_right": return make_rect(grid.left + (transform_w + transform_gap), transform_top + 40, transform_w, button_h);

			/* Up shift occupies its third position */
			case "shift_up": return make_rect(grid.left + (transform_w + transform_gap) * 2, transform_top + 40, transform_w, button_h);

			/* Down shift occupies its final position */
			case "shift_down": return make_rect(grid.left + (transform_w + transform_gap) * 3, transform_top + 40, transform_w, button_h);
		}

		/* Unknown action keys get an empty rectangle, avoiding an invented layout for unsupported
		controls */
		return make_rect(0, 0, 0, 0);
	}

	/// @description Resolve the fixed zoom-action row below the grid viewport
	/// @param {String} button_key zoom_out, zoom_reset or zoom_in
	/// @returns {Struct} GUI button rectangle, empty for an unknown key
	zoom_button_rect = function(button_key)
	{
		/* grid anchors zoom controls below its fixed viewport. button_h/gap size and separate them in
		GUI pixels, button_top/left start the first button */
		var grid = grid_rect();
		var button_h = 30;
		var button_gap = 8;
		var button_top = grid.viewport_bottom + 14;
		var button_left = grid.left;

		/* Known zoom keys select the left decrement, middle 100-percent reset or right increment
		rectangle */
		switch (button_key)
		{
			/* Zoom Out uses the first 76-pixel-wide button */
			case "zoom_out":
				return make_rect(button_left, button_top, 76, button_h);

			/* Reset advances past Zoom Out and its gap into a 70-pixel button */
			case "zoom_reset":
				button_left += 76 + button_gap;
				return make_rect(button_left, button_top, 70, button_h);

			/* Zoom In advances past both earlier buttons and gaps into the final 76-pixel button */
			case "zoom_in":
				button_left += 76 + button_gap + 70 + button_gap;
				return make_rect(button_left, button_top, 76, button_h);
		}

		/* An unknown zoom action has no visible hit rectangle */
		return make_rect(0, 0, 0, 0);
	}

	/// @description Resolve left, up, down or right panning control geometry
	/// @param {String} button_key Stable view action key
	/// @returns {Struct} GUI arrow rectangle, empty for an unknown key
	view_button_rect = function(button_key)
	{
		/* grid anchors the pan row below zoom. button_size is a 30-pixel square, button_gap separates
		arrows and button_top/left start the left arrow after the View label */
		var grid = grid_rect();
		var button_size = 30;
		var button_gap = 8;
		var button_top = zoom_button_rect("zoom_out").bottom + 8;
		var button_left = grid.left + 48;

		/* Pan routing keys select arrows in left, up, down, right order along the GUI row */
		switch (button_key)
		{
			/* Left uses the initial pan square */
			case "view_left":
				return make_rect(button_left, button_top, button_size, button_size);

			/* Up advances one arrow width and gap */
			case "view_up":
				button_left += button_size + button_gap;
				return make_rect(button_left, button_top, button_size, button_size);

			/* Down advances two arrow widths and gaps */
			case "view_down":
				button_left += (button_size + button_gap) * 2;
				return make_rect(button_left, button_top, button_size, button_size);

			/* Right advances three arrow widths and gaps */
			case "view_right":
				button_left += (button_size + button_gap) * 3;
				return make_rect(button_left, button_top, button_size, button_size);
		}

		/* Unknown pan keys return an empty hit rectangle rather than selecting an existing arrow */
		return make_rect(0, 0, 0, 0);
	}

	/// @description Test whether hidden source cells remain in a requested pan direction
	/// @param {String} button_key Stable view action key
	/// @returns {Bool} Whether the viewport can move in that direction
	view_button_enabled = function(button_key)
	{
		/* Current grid visible-cell counts establish how much hidden source content remains for
		panning */
		var grid = grid_rect();

		/* Each directional action is enabled only while hidden source cells remain in that direction,
		keeping panned offsets within the frame */
		switch (button_key)
		{
			/* Left can move only when editor_view_col is above source column zero */
			case "view_left":
				return editor_view_col > 0;

			/* Right can move only before the final start column that still fits visible_cols */
			case "view_right":
				return editor_view_col < max(0, frame_w - grid.visible_cols);

			/* Up can move only when editor_view_row is above row zero */
			case "view_up":
				return editor_view_row > 0;

			/* Down can move only before the final start row that still fits visible_rows */
			case "view_down":
				return editor_view_row < max(0, frame_h - grid.visible_rows);
		}

		/* Unsupported pan keys are disabled instead of allowing a meaningless view change */
		return false;
	}

	/// @description Show horizontal or vertical pan controls only when their source axis is cropped
	/// @param {String} button_key Stable view action key
	/// @returns {Bool} Whether this directional control belongs in the current layout
	view_button_should_show = function(button_key)
	{
		/* Current grid visible counts determine whether each source axis is cropped */
		var grid = grid_rect();

		/* Horizontal arrows appear only when not all frame columns fit and vertical arrows only when
		not all rows fit, avoiding controls with no panning purpose */
		switch (button_key)
		{
			/* Left and right share the cropped-column visibility check */
			case "view_left":
			case "view_right":
				return grid.visible_cols < frame_w;

			/* Up and down share the cropped-row visibility check */
			case "view_up":
			case "view_down":
				return grid.visible_rows < frame_h;
		}

		/* Unknown pan actions are hidden */
		return false;
	}

	/// @description Test whether either source axis is cropped enough to require the pan row
	/// @returns {Bool} Whether any pan controls are needed
	view_controls_visible = function()
	{
		/* Show the pan row when either horizontal or vertical source content is cropped. A full-frame
		viewport needs no directional controls */
		return view_button_should_show("view_left")
			|| view_button_should_show("view_up");
	}

	/// @description Constrain source-cell view offsets to the currently visible row and column counts
	/// @returns {Bool} True after both offsets are clamped
	clamp_editor_view = function()
	{
		/* Current grid counts limit zero-based source start offsets so the visible region never passes
		the frame's final column or row */
		var grid = grid_rect();
		editor_view_col = clamp(floor(real(editor_view_col)), 0, max(0, frame_w - grid.visible_cols));
		editor_view_row = clamp(floor(real(editor_view_row)), 0, max(0, frame_h - grid.visible_rows));
		return true;
	}

	/// @description Move the viewport in source-pixel cells and clamp it to the current visible extent
	/// @param {Real} delta_col Horizontal source-cell displacement
	/// @param {Real} delta_row Vertical source-cell displacement
	/// @returns {Bool} True after applying the clamped view offset
	pan_editor_view = function(delta_col, delta_row)
	{
		editor_view_col += floor(real(delta_col));
		editor_view_row += floor(real(delta_row));
		return clamp_editor_view();
	}

	/// @description Format the clamped current zoom percentage for editor feedback
	/// @returns {String} Percentage label including its percent sign
	editor_zoom_text = function()
	{
		return string(clamp(floor(real(editor_zoom_percent)), editor_zoom_min, editor_zoom_max)) + "%";
	}

	/// @description Apply a bounded integer zoom percentage, reclamp pan and report actual percentage changes
	/// @param {Real} raw_zoom_percent Requested view percentage
	/// @returns {Bool} Whether the stored percentage changed
	set_editor_zoom = function(raw_zoom_percent)
	{
		/* Previous zoom percentage distinguishes a real view change from a clamped request that leaves
		the percentage unchanged */
		var old_zoom = editor_zoom_percent;
		editor_zoom_percent = clamp(floor(real(raw_zoom_percent)), editor_zoom_min, editor_zoom_max);

		/* A changed percentage reclamps the visible source offset and shows zoom feedback. An
		unchanged request returns false without status changes */
		if (editor_zoom_percent != old_zoom)
		{
			clamp_editor_view();
			set_status("Editor zoom " + editor_zoom_text() + ".", make_color_rgb(178, 178, 184));
			return true;
		}

		return false;
	}

	/// @description Choose the nearest authored larger or smaller zoom level
	/// @param {Real} direction Positive requests zoom in, nonpositive requests zoom out
	/// @returns {Bool} Whether applying the chosen or boundary zoom changes its percentage
	adjust_editor_zoom = function(direction)
	{
		/* Current zoom is normalized to the allowed percent range before selecting the next authored
		level */
		var current_zoom = clamp(floor(real(editor_zoom_percent)), editor_zoom_min, editor_zoom_max);

		/* Positive direction searches larger levels from the beginning. Nonpositive direction searches
		smaller levels in reverse */
		if (direction > 0)
		{
			/* zoom_index_in starts at the smallest authored level and stops at the first strictly
			larger percentage or the end */
			for (var zoom_index_in = 0; zoom_index_in < array_length(editor_zoom_levels); zoom_index_in++)
			{
				/* Current authored zoom-in candidate is compared with the normalized current
				percentage */
				var zoom_in_level = editor_zoom_levels[zoom_index_in];

				/* The first larger level is the nearest allowed upward step. Apply it and stop the
				search */
				if (zoom_in_level > current_zoom)
				{
					return set_editor_zoom(zoom_in_level);
				}
			}
		}

		/* The remaining direction values take the zoom-out path, including zero, matching the current
		implementation */
		else
		{
			/* zoom_index_out starts at the largest authored level and counts down through zero until
			it finds a smaller percentage */
			for (var zoom_index_out = array_length(editor_zoom_levels) - 1; zoom_index_out >= 0; zoom_index_out--)
			{
				/* Current authored zoom-out candidate is checked against the current view percentage */
				var zoom_out_level = editor_zoom_levels[zoom_index_out];

				/* The first smaller level in reverse order is the nearest allowed downward step */
				if (zoom_out_level < current_zoom)
				{
					return set_editor_zoom(zoom_out_level);
				}
			}
		}

		/* If no further authored step exists, reapply the clamped current percentage and return
		whether that normalization changed anything */
		return set_editor_zoom(current_zoom);
	}

	/// @description Restore the 100-percent source view and reclamp its panning offsets
	/// @returns {Bool} Whether the zoom percentage changed
	reset_editor_zoom = function()
	{
		return set_editor_zoom(100);
	}

	/// @description Convert a GUI x coordinate to the scrolled source-frame pixel column
	/// @param {Real} gui_x Mouse x in GUI pixels
	/// @param {Struct} grid Current grid_rect geometry
	/// @returns {Real} Zero-based source column, clamped to the frame
	grid_col_from_gui = function(gui_x, grid)
	{
		return clamp(editor_view_col + floor((gui_x - grid.left) / max(1, grid.cell)), 0, frame_w - 1);
	}

	/// @description Convert a GUI y coordinate to the scrolled source-frame pixel row
	/// @param {Real} gui_y Mouse y in GUI pixels
	/// @param {Struct} grid Current grid_rect geometry
	/// @returns {Real} Zero-based source row, clamped to the frame
	grid_row_from_gui = function(gui_y, grid)
	{
		return clamp(editor_view_row + floor((gui_y - grid.top) / max(1, grid.cell)), 0, frame_h - 1);
	}

	/// @description Choose selection left, pointed grid column or viewport origin as paste's horizontal target
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @param {Struct} grid Current grid_rect geometry
	/// @returns {Real} Zero-based source column
	paste_target_col = function(gui_x, gui_y, grid)
	{
		/* An active selection fixes paste's horizontal destination to its left edge. Otherwise prefer
		a grid pointer or the view's starting column */
		if (is_struct(editor) && editor.selection_active)
		{
			return editor.selection_left;
		}

		/* A pointer within the visible grid supplies the source-column paste target. Outside-grid
		clicks use editor_view_col as the fallback */
		if (point_in_gui_rect(gui_x, gui_y, grid))
		{
			return grid_col_from_gui(gui_x, grid);
		}

		return editor_view_col;
	}

	/// @description Choose selection top, pointed grid row or viewport origin as paste's vertical target
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @param {Struct} grid Current grid_rect geometry
	/// @returns {Real} Zero-based source row
	paste_target_row = function(gui_x, gui_y, grid)
	{
		/* An active selection fixes paste's vertical destination to its top edge, keeping both paste
		axes aligned with that selection */
		if (is_struct(editor) && editor.selection_active)
		{
			return editor.selection_top;
		}

		/* A pointer inside the grid supplies the source-row target. Otherwise use the viewport's
		starting row */
		if (point_in_gui_rect(gui_x, gui_y, grid))
		{
			return grid_row_from_gui(gui_y, grid);
		}

		return editor_view_row;
	}

	/// @description Resolve a row-major animation slot's thumbnail button
	/// @param {Real} frame_index Zero-based row-major frame slot
	/// @returns {Struct} GUI rectangle for its 68-pixel thumbnail
	frame_button_rect = function(frame_index)
	{
		/* rect anchors thumbnails, frame_col/row decode the row-major frame slot, cell_w/h are the
		76-pixel layout stride and left_value/top_value position its 68-pixel button */
		var rect = main_rect();
		var frame_col = frame_index mod column_count;
		var frame_row = floor(frame_index / column_count);
		var cell_w = 76;
		var cell_h = 76;
		var left_value = rect.left + 24 + frame_col * cell_w;
		var top_value = rect.top + 108 + frame_row * cell_h;
		return make_rect(left_value, top_value, 68, 68);
	}

	/// @description Position the current-color section below Clear
	/// @returns {Real} Vertical GUI coordinate
	colour_controls_top = function()
	{
		return button_rect("clear").bottom + 16;
	}

	/// @description Position preset swatches below the current-color section
	/// @returns {Real} Vertical GUI coordinate
	colour_swatch_top = function()
	{
		return colour_controls_top() + 94;
	}

	/// @description Position HSV channels below the palette section
	/// @returns {Real} Vertical GUI coordinate
	colour_slider_top = function()
	{
		return colour_controls_top() + 140;
	}

	/// @description Resolve one preset's square in the palette row
	/// @param {Real} swatch_index Zero-based authored palette index
	/// @returns {Struct} GUI swatch rectangle
	swatch_rect = function(swatch_index)
	{
		/* side_x and top_value anchor the palette row. swatch_size_value makes each preset a
		22-GUI-pixel square with a 28-pixel stride */
		var side_x = side_left();
		var top_value = colour_swatch_top();
		var swatch_size_value = 22;
		return make_rect(side_x + swatch_index * 28, top_value, swatch_size_value, swatch_size_value);
	}

	/// @description Resolve a channel's GUI track and its usable byte-mapping width
	/// @param {String} slider_key hue, saturation or value
	/// @returns {Struct} GUI edges and positive slider_w
	hsv_slider_rect = function(slider_key)
	{
		/* side_x/top_value anchor the HSV controls and slider_index starts at hue row zero before
		selecting the requested channel row */
		var side_x = side_left();
		var top_value = colour_slider_top();
		var slider_index = 0;

		/* Hue, saturation and brightness map to consecutive slider rows, giving each channel a stable
		GUI position */
		switch (slider_key)
		{
			/* Hue uses the first slider row */
			case "hue": slider_index = 0; break;

			/* Saturation uses the second row */
			case "saturation": slider_index = 1; break;

			/* Brightness uses the third row */
			case "value": slider_index = 2; break;
		}

		/* Returned left/top/right/bottom are GUI slider bounds and slider_w is its positive usable
		track width for byte-channel mapping */
		return
		{
			left: side_x + 24,
			top: top_value + slider_index * 24,
			right: side_x + min(230, side_width()),
			bottom: top_value + slider_index * 24 + 14,
			slider_w: max(1, min(230, side_width()) - 24)
		};
	}

	/// @description Test an inclusive GUI rectangle against a pointer position
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @param {Struct} rect GUI edge record
	/// @returns {Bool} Whether the pointer lies inside or on its edges
	point_in_gui_rect = function(gui_x, gui_y, rect)
	{
		/* Pointer hit testing includes all four GUI rectangle edges so drawing bounds and interactive
		bounds agree */
		return gui_x >= rect.left
			&& gui_x <= rect.right
			&& gui_y >= rect.top
			&& gui_y <= rect.bottom;
	}

	/// @description Hit-test visible editor actions using their matching rectangle families
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @returns {String} First hit action key or empty text
	button_key_at = function(gui_x, gui_y)
	{
		/* Stable action keys enumerate tool, history, view, clipboard, transform and session buttons
		in hit-test order */
		var keys = ["pen", "eraser", "fill", "picker", "select", "undo", "redo", "clear", "zoom_out", "zoom_reset", "zoom_in", "view_left", "view_up", "view_down", "view_right", "copy", "paste", "flip_h", "flip_v", "shift_left", "shift_right", "shift_up", "shift_down", "save", "cancel"];

		/* key_index starts at zero and tests each action until a visible rectangle hits or all keys
		are exhausted */
		for (var key_index = 0; key_index < array_length(keys); key_index++)
		{
			/* Current action key identifies which rectangle family and visibility rule applies */
			var check_key = keys[key_index];

			/* Hidden pan arrows are excluded from hit testing, avoiding interactions with controls
			that are not drawn */
			if (string_copy(check_key, 1, 5) == "view_"
			&& !view_button_should_show(check_key))
			{
				continue;
			}

			/* Pan keys use view_button_rect, zoom keys use zoom_button_rect and remaining actions use
			button_rect. check_rect is the selected GUI hit area */
			var check_rect = string_copy(check_key, 1, 5) == "view_" ? view_button_rect(check_key) : (string_copy(check_key, 1, 5) == "zoom_" ? zoom_button_rect(check_key) : button_rect(check_key));

			/* The first containing visible control returns its routing key. Misses continue through
			the action list */
			if (point_in_gui_rect(gui_x, gui_y, check_rect))
			{
				return check_key;
			}
		}

		return "";
	}

	/// @description Hit-test all twelve animation thumbnails
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @returns {Real} Row-major slot, or noone for a miss
	frame_key_at = function(gui_x, gui_y)
	{
		/* frame_index visits all twelve row-major thumbnail slots starting at zero */
		for (var frame_index = 0; frame_index < column_count * row_count; frame_index++)
		{
			/* Return the first thumbnail slot containing the pointer. A complete miss returns noone
			after the loop */
			if (point_in_gui_rect(gui_x, gui_y, frame_button_rect(frame_index)))
			{
				return frame_index;
			}
		}

		return noone;
	}

	/// @description Hit-test authored color preset squares
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @returns {Real} Palette index, or noone for a miss
	swatch_index_at = function(gui_x, gui_y)
	{
		/* swatch_index walks palette presets from zero to the final entry, matching their drawing
		order */
		for (var swatch_index = 0; swatch_index < array_length(swatches); swatch_index++)
		{
			/* A pointer inside a swatch square identifies that preset. Misses continue and ultimately
			return noone */
			if (point_in_gui_rect(gui_x, gui_y, swatch_rect(swatch_index)))
			{
				return swatch_index;
			}
		}

		return noone;
	}

	/// @description Hit-test the hue, saturation and brightness tracks
	/// @param {Real} gui_x Pointer x in GUI pixels
	/// @param {Real} gui_y Pointer y in GUI pixels
	/// @returns {String} Channel key, or empty text for a miss
	slider_key_at = function(gui_x, gui_y)
	{
		/* HSV routing keys are ordered hue, saturation and value */
		var keys = ["hue", "saturation", "value"];

		/* key_index visits the three channel rectangles until a slider contains the pointer */
		for (var key_index = 0; key_index < array_length(keys); key_index++)
		{
			/* Current channel key selects its GUI track rectangle */
			var slider_key = keys[key_index];

			/* A hit returns this channel's key for starting or displaying slider interaction. A miss
			continues to the next track */
			if (point_in_gui_rect(gui_x, gui_y, hsv_slider_rect(slider_key)))
			{
				return slider_key;
			}
		}

		return "";
	}

	/// @description Map GUI horizontal pointer position to one byte HSV channel and synchronize painting RGB
	/// @param {String} slider_key hue, saturation or value
	/// @param {Real} gui_x Pointer x in GUI pixels
	update_hsv_slider_from_mouse = function(slider_key, gui_x)
	{
		/* slider_rect_value provides GUI track geometry and slider_value maps horizontal pointer
		position into a clamped rounded 0..255 HSV channel */
		var slider_rect_value = hsv_slider_rect(slider_key);
		var slider_value = clamp(round((gui_x - slider_rect_value.left) / max(1, slider_rect_value.slider_w) * 255), 0, 255);

		/* The routed channel alone receives the sampled byte value, then RGB is recalculated from all
		three HSV channels */
		switch (slider_key)
		{
			/* Hue updates current_hue while saturation and brightness remain unchanged */
			case "hue":
				current_hue = slider_value;
				break;

			/* Saturation updates current_saturation while hue and brightness stay fixed */
			case "saturation":
				current_saturation = slider_value;
				break;

			/* Brightness updates current_value while hue and saturation stay fixed */
			case "value":
				current_value = slider_value;
				break;
		}

		set_current_colour_from_hsv();
	}

	/// @description Resolve controls for loading, save, discard or entry modal layouts
	/// @param {String} button_key Modal action key
	/// @returns {Struct} GUI button edges, empty for unsupported keys
	modal_button_rect = function(button_key)
	{
		/* Default centered GUI dialog rectangle before choosing the active modal's button layout */
		var rect = modal_rect(430, 210);

		/* Loading has only Cancel, centered near the bottom so an unfinished import can be aborted */
		if (modal == "loading" && button_key == "cancel")
		{
			return make_rect(rect.left + (rect.w - 120) * 0.5, rect.top + 150, 120, 34);
		}

		/* Save uses two bottom actions under name entry. Other modal types continue to their own
		layouts */
		if (modal == "save")
		{
			rect = modal_rect(430, 210);

			/* Save's confirm and cancel keys select their separate 120-pixel buttons */
			switch (button_key)
			{
				/* Confirm occupies the left save-action position */
				case "confirm": return make_rect(rect.left + 82, rect.top + 150, 120, 34);

				/* Cancel occupies the right save-action position */
				case "cancel": return make_rect(rect.left + 228, rect.top + 150, 120, 34);
			}
		}

		/* Discard uses the shorter dialog and wider confirmation choices to emphasize keeping or
		losing edits */
		if (modal == "discard")
		{
			rect = modal_rect(430, 180);

			/* Discard confirm and cancel use separate 136-pixel buttons */
			switch (button_key)
			{
				/* Discard confirmation occupies the left destructive-action position */
				case "confirm": return make_rect(rect.left + 70, rect.top + 120, 136, 34);

				/* Cancel occupies the right position to return to editing */
				case "cancel": return make_rect(rect.left + 224, rect.top + 120, 136, 34);
			}
		}

		rect = modal_rect(430, 210);

		/* Remaining modal controls use the entry layout's New, Edit and Cancel buttons */
		switch (button_key)
		{
			/* New Blank occupies the first entry action */
			case "new": return make_rect(rect.left + 32, rect.top + 78, 112, 34);

			/* Edit Current occupies the middle entry action */
			case "edit": return make_rect(rect.left + 158, rect.top + 78, 112, 34);

			/* Cancel occupies the final entry action */
			case "cancel": return make_rect(rect.left + 284, rect.top + 78, 112, 34);
		}

		/* Unsupported modal actions receive no usable button rectangle */
		return make_rect(0, 0, 0, 0);
	}

	/// @description Resolve the centered nominal 520 by 300 transparency dialog
	/// @returns {Struct} GUI edges and size capped by canvas margins
	transparency_modal_rect = function()
	{
		return modal_rect(520, 300);
	}

	/// @description Resolve a transparency mode, color-copy or confirmation control
	/// @param {String} button_key Transparency action key
	/// @returns {Struct} GUI control rectangle, empty for an unknown key
	transparency_modal_button_rect = function(button_key)
	{
		/* Centered transparency dialog rectangle anchors all mode, current-color and completion
		controls */
		var rect = transparency_modal_rect();

		/* Known transparency keys select fixed GUI rectangles shared by input and drawing */
		switch (button_key)
		{
			/* Checker mode has its radio rectangle above the two checker color rows */
			case "mode_block":
				return make_rect(rect.left + 18, rect.top + 52, 132, 24);

			/* Single mode sits above its one color row */
			case "mode_single":
				return make_rect(rect.left + 18, rect.top + 186, 132, 24);

			/* The first checker color's Use Current button aligns with its sample row */
			case "color_1_current":
				return make_rect(rect.right - 120, rect.top + 82, 102, 24);

			/* The second checker color's copy button aligns with the next row */
			case "color_2_current":
				return make_rect(rect.right - 120, rect.top + 118, 102, 24);

			/* Single-color copy uses its own row below the single-mode choice */
			case "single_current":
				return make_rect(rect.right - 120, rect.top + 216, 102, 24);

			/* OK uses the left confirmation button near the bottom */
			case "ok":
				return make_rect(rect.right - 204, rect.bottom - 40, 92, 26);

			/* Cancel uses the right confirmation button */
			case "cancel":
				return make_rect(rect.right - 102, rect.bottom - 40, 84, 26);
		}

		/* Unknown transparency keys have no interactive rectangle */
		return make_rect(0, 0, 0, 0);
	}

	/// @description Resolve the checker-size draft text field
	/// @returns {Struct} GUI text-field rectangle
	transparency_block_size_input_rect = function()
	{
		/* Transparency panel anchors the GUI text field for the checker block-size draft */
		var rect = transparency_modal_rect();
		return make_rect(rect.left + 138, rect.top + 154, 80, 26);
	}
	#endregion /* GUI Geometry and Hit Testing END */

	#region /* Editor Input and Actions */
	/// @description Capture modal text, hover and actions before any pixel editing or gameplay input
	/// @returns {Bool} True after handling modal input, including idle frames
	update_modal_input = function()
	{
		/* gui_x and gui_y are current GUI mouse coordinates used by every modal control's hit
		rectangle */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		hover_key = "";

		/* Loading owns input while the selected character is extracted. Handle cancel first, otherwise
		advance one frame this Step */
		if (modal == "loading")
		{
			/* cancel_hover records whether the pointer lies in the loading dialog's cancel rectangle */
			var cancel_hover = point_in_gui_rect(gui_x, gui_y, modal_button_rect("cancel"));

			/* Only a hovered Cancel becomes the current modal hover key for drawing feedback */
			if (cancel_hover) hover_key = "modal_cancel";

			/* Escape or a left press on Cancel aborts queued loading and closes the editor UI. Other
			input leaves extraction running */
			if (keyboard_check_pressed(vk_escape) || (cancel_hover && mouse_check_button_pressed(mb_left)))
			{
				close_all();
				return true;
			}
			update_character_load();
			return true;
		}

		/* Transparency mode routes its draft settings input separately from save, start and discard
		dialogs */
		if (modal == "transparency")
		{
			/* While the block-size field owns focus, accept digits from text input and keep its draft
			and keyboard_string synchronized */
			if (transparency_focus == "block_size")
			{
				scr_text_input_update("character_transparency_block_size", transparency_draft_block_size_text);
				transparency_draft_block_size_text = digits_only(keyboard_string);
				keyboard_string = transparency_draft_block_size_text;
			}

			/* Escape discards only the transparency draft dialog, returning to the underlying editor */
			if (keyboard_check_pressed(vk_escape))
			{
				cancel_transparency_modal();
				return true;
			}

			/* Enter applies and saves the transparency draft before dismissing its dialog */
			if (keyboard_check_pressed(vk_enter))
			{
				apply_transparency_modal();
				return true;
			}

			/* Current GUI rectangle for the block-size draft text field */
			var block_size_rect = transparency_block_size_input_rect();

			/* A pointer inside the size field receives its own hover key so a click can grant keyboard
			focus */
			if (point_in_gui_rect(gui_x, gui_y, block_size_rect))
			{
				hover_key = "transparency_block_size";
			}

			/* transparency_keys lists mode, color-copy and confirmation routing keys in hit-test order */
			var transparency_keys = ["mode_block", "mode_single", "color_1_current", "color_2_current", "single_current", "ok", "cancel"];

			/* transparency_key_index visits all transparency controls from zero to the array end */
			for (var transparency_key_index = 0; transparency_key_index < array_length(transparency_keys); transparency_key_index++)
			{
				/* Current transparency action key determines which modal rectangle is tested */
				var transparency_key = transparency_keys[transparency_key_index];

				/* A matching button rectangle updates the hover key used by this dialog's drawing and
				left-click dispatch */
				if (point_in_gui_rect(gui_x, gui_y, transparency_modal_button_rect(transparency_key)))
				{
					hover_key = "transparency_" + transparency_key;
				}
			}

			/* Only a new left press activates draft actions. Without one, the modal still retains
			input and hover ownership */
			if (mouse_check_button_pressed(mb_left))
			{
				/* Clicks outside the size field release text focus and clear keyboard_string so button
				actions cannot keep editing hidden draft text */
				if (hover_key != "transparency_block_size")
				{
					transparency_focus = "";
					keyboard_string = "";
				}

				/* Route the hovered transparency control to its matching draft change, focus change,
				confirmation or cancellation */
				switch (hover_key)
				{
					/* Block mode makes the draft use alternating checker colors */
					case "transparency_mode_block":
						transparency_draft_mode = "block";
						return true;

					/* Single mode makes the draft use one background color */
					case "transparency_mode_single":
						transparency_draft_mode = "single";
						return true;

					/* Copy the current painting RGB bytes into the first checker color without
					changing the other draft color */
					case "transparency_color_1_current":
						transparency_draft_color_1 = rgb_struct(current_red, current_green, current_blue);
						return true;

					/* Copy the current painting RGB bytes into the second checker color */
					case "transparency_color_2_current":
						transparency_draft_color_2 = rgb_struct(current_red, current_green, current_blue);
						return true;

					/* Copy the current painting RGB bytes into the single-color draft */
					case "transparency_single_current":
						transparency_draft_single_color = rgb_struct(current_red, current_green, current_blue);
						return true;

					/* The size field captures keyboard text with its current draft value */
					case "transparency_block_size":
						transparency_focus = "block_size";
						keyboard_string = transparency_draft_block_size_text;
						return true;

					/* OK applies the draft to shared settings and persists it */
					case "transparency_ok":
						apply_transparency_modal();
						return true;

					/* Cancel dismisses the draft without applying it */
					case "transparency_cancel":
						cancel_transparency_modal();
						return true;
				}
			}

			return true;
		}

		/* The save dialog owns name entry, sanitizing keyboard text to its 32-character limit before
		processing dismissal or saving */
		if (modal == "save")
		{
			scr_text_input_update("character_save_name", save_name, 32);
			save_name = clean_name_text(keyboard_string);
			keyboard_string = save_name;

			/* Escape dismisses save and releases the keyboard field while retaining the editor's
			unsaved pixels */
			if (keyboard_check_pressed(vk_escape))
			{
				modal = "";
				keyboard_focus = "";
				keyboard_string = "";
				return true;
			}

			/* Enter attempts the PNG save. Failed saves keep editor state and feedback available
			rather than discarding changes */
			if (keyboard_check_pressed(vk_enter))
			{
				save_character();
				return true;
			}
		}

		/* Other modal types handle Escape without save-field cleanup. Discard confirmation returns to
		editing while the entry modal closes all UI */
		else if (keyboard_check_pressed(vk_escape))
		{
			/* Canceling discard removes only its confirmation, keeping the dirty editor open */
			if (modal == "discard")
			{
				modal = "";
			}

			/* Remaining Escape dismissal closes the complete editor session instead of returning to an
			existing editing modal */
			else
			{
				close_all();
			}
			return true;
		}

		/* The entry modal offers New, Edit and Cancel. Save and discard dialogs use Confirm and
		Cancel, giving this loop the relevant routing keys */
		var modal_keys = modal == "start" ? ["new", "edit", "cancel"] : ["confirm", "cancel"];

		/* key_index starts at zero and checks each current modal action until a rectangle contains the
		pointer */
		for (var key_index = 0; key_index < array_length(modal_keys); key_index++)
		{
			/* Current modal action key selects its hit rectangle and becomes the hover routing suffix
			when matched */
			var modal_key = modal_keys[key_index];

			/* The first matching modal button establishes hover and ends the search, keeping one click
			target */
			if (point_in_gui_rect(gui_x, gui_y, modal_button_rect(modal_key)))
			{
				hover_key = "modal_" + modal_key;
				break;
			}
		}

		/* A fresh left press dispatches the hovered modal action. Without a click, only hover and
		keyboard handling run */
		if (mouse_check_button_pressed(mb_left))
		{
			/* Each entry, confirmation and cancel hover key maps to the operation for its current
			modal */
			switch (hover_key)
			{
				/* New opens a fresh transparent sheet and consumes the entry-dialog click */
				case "modal_new":
					begin_new_blank();
					return true;

				/* Edit attempts to obtain and queue the selected source rather than altering current
				pixels immediately */
				case "modal_edit":

					/* Successful source preparation begins loading and returns immediately. Failure
					retains the dialog with its error status */
					if (begin_edit_current())
					{
						return true;
					}
					break;

				/* Confirm is interpreted according to the active save or discard dialog */
				case "modal_confirm":

					/* Save confirmation attempts PNG installation and selection through the registry */
					if (modal == "save")
					{
						save_character();
					}

					/* After ruling out save, discard confirmation closes and releases the entire
					unsaved editing session */
					else if (modal == "discard")
					{
						close_all();
					}
					return true;

				/* Cancel either closes the entry dialog or removes a save/discard modal while
				retaining editing state */
				case "modal_cancel":

					/* The start dialog has no active editing view to return to, so its cancel closes
					the full UI */
					if (modal == "start")
					{
						close_all();
					}

					/* Save and discard cancellation release their modal and text focus but retain the
					main editor and pixels */
					else
					{
						modal = "";
						keyboard_focus = "";
						keyboard_string = "";
					}
					return true;
			}
		}

		return true;
	}

	/// @description Route tools, undo, selection/frame clipboard, transforms, view controls, and save/close actions
	/// @param {String} action_key Key used by the editor action buttons or keyboard shortcuts
	/// @returns {Bool} Whether a supported action was handled. It can be true without changing pixels
	apply_editor_action = function(action_key)
	{
		/* Actions require a pixel-editor struct for tools and history. Return false when there is no
		editable frame */
		if (!is_struct(editor))
		{
			return false;
		}

		/* Dispatch supported tool, history, viewport, clipboard, transform and session actions through
		their stable button keys */
		switch (action_key)
		{
			/* Pen changes the active tool to opaque pixel painting */
			case "pen":
				editor_tool = PIXEL_EDITOR_TOOL_PEN;
				return true;

			/* Eraser changes the active tool to clearing pixel alpha */
			case "eraser":
				editor_tool = PIXEL_EDITOR_TOOL_ERASER;
				return true;

			/* Fill selects flood fill instead of a continuous mouse stroke */
			case "fill":
				editor_tool = PIXEL_EDITOR_TOOL_FILL;
				return true;

			/* Picker selects color sampling without changing frame pixels */
			case "picker":
				editor_tool = PIXEL_EDITOR_TOOL_COLOR_PICKER;
				return true;

			/* Select switches the grid to selection creation and movement */
			case "select":
				editor_tool = PIXEL_EDITOR_TOOL_SELECT;
				return true;

			/* Undo asks the editor for a previous snapshot without changing the chosen tool */
			case "undo":

				/* Only a successful undo marks the session unsaved and invalidates its draw caches.
				Empty history retains existing pixels */
				if (editor.undo())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Redo reapplies the next saved snapshot when one remains */
			case "redo":

				/* Successful redo invalidates previews and marks edits dirty. No remaining redo state
				leaves the frame unchanged */
				if (editor.redo())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Zoom Out requests the next smaller authored zoom level */
			case "zoom_out":
				adjust_editor_zoom(-1);
				return true;

			/* No Zoom returns the view to 100 percent without changing source pixels */
			case "zoom_reset":
				reset_editor_zoom();
				return true;

			/* Zoom In requests the next larger authored zoom level */
			case "zoom_in":
				adjust_editor_zoom(1);
				return true;

			/* The left pan action moves toward earlier source columns */
			case "view_left":

				/* Only remaining leftward space permits a pan. At the left boundary the supported
				action is consumed without changing the view */
				if (view_button_enabled("view_left"))
				{
					/* Current viewport geometry sets leftward pan to a quarter of visible columns,
					with at least one source cell */
					var grid_left = grid_rect();
					pan_editor_view(-max(1, floor(grid_left.visible_cols / 4)), 0);
				}
				return true;

			/* The right pan action moves toward later source columns */
			case "view_right":

				/* Only remaining rightward space permits this pan, retaining the view at its boundary
				otherwise */
				if (view_button_enabled("view_right"))
				{
					/* Current visible-column count sets the quarter-view rightward source-cell
					displacement */
					var grid_right = grid_rect();
					pan_editor_view(max(1, floor(grid_right.visible_cols / 4)), 0);
				}
				return true;

			/* Up pans toward earlier source rows */
			case "view_up":

				/* Do not move above row zero. Enabled upward travel uses a quarter of the current
				visible rows */
				if (view_button_enabled("view_up"))
				{
					/* Current grid geometry determines the upward source-cell amount */
					var grid_up = grid_rect();
					pan_editor_view(0, -max(1, floor(grid_up.visible_rows / 4)));
				}
				return true;

			/* Down pans toward later source rows */
			case "view_down":

				/* Pan downward only while hidden rows remain below the view. At the bottom edge retain
				the current offset */
				if (view_button_enabled("view_down"))
				{
					/* Current visible-row count supplies the quarter-view downward displacement */
					var grid_down = grid_rect();
					pan_editor_view(0, max(1, floor(grid_down.visible_rows / 4)));
				}
				return true;

			/* Clear records one undo snapshot before clearing the entire frame, then invalidates its
			preview and marks unsaved edits */
			case "clear":
				editor.push_undo_snapshot();
				editor.clear();
				editor_dirty = true;
				mark_editor_surface_dirty();
				return true;

			/* Copy prefers an active selection and otherwise records the whole frame */
			case "copy":

				/* An active selection uses the region clipboard. Without a selection, copy the
				complete frame and clear the region clipboard to identify the intended paste source */
				if (editor.selection_active)
				{
					/* Report a copied selection only if the editor successfully populated its region
					clipboard. Failure leaves feedback unchanged */
					if (editor.copy_selection_to_clipboard())
					{
						set_status("Copied selection.", make_color_rgb(126, 245, 150));
					}
				}

				/* Whole-frame copy stores the editor's RRGGBBAA snapshot for later frame replacement
				instead of a positional region paste */
				else
				{
					copied_frame_hex = editor.to_hex_string();
					editor.clear_region_clipboard();
					set_status("Copied frame.", make_color_rgb(126, 245, 150));
				}
				return true;

			/* Paste gives a stored region precedence over the whole-frame clipboard */
			case "paste":

				/* An available region is pasted at the selection, grid pointer or viewport origin
				supplied by the target helpers */
				if (editor.region_clipboard_available())
				{
					/* paste_grid describes current GUI geometry, paste_gui_x/y are the pointer and
					paste_col/row resolve the source-cell destination for this region */
					var paste_grid = grid_rect();
					var paste_gui_x = device_mouse_x_to_gui(0);
					var paste_gui_y = device_mouse_y_to_gui(0);
					var paste_col = paste_target_col(paste_gui_x, paste_gui_y, paste_grid);
					var paste_row = paste_target_row(paste_gui_x, paste_gui_y, paste_grid);

					/* Only an actual region-paste pixel change marks the session dirty and invalidates
					surfaces. A no-op paste still reports the supported action */
					if (editor.paste_clipboard_at(paste_col, paste_row))
					{
						editor_dirty = true;
						mark_editor_surface_dirty();
					}
					set_status("Pasted selection.", make_color_rgb(126, 245, 150));
				}

				/* Without a region, a nonempty whole-frame copy replaces pixels after recording undo
				and clears any stale selection. With neither clipboard, pixels stay unchanged */
				else if (copied_frame_hex != "")
				{
					editor.push_undo_snapshot();
					editor.load_hex_string(copied_frame_hex);
					editor.clear_selection();
					editor_dirty = true;
					mark_editor_surface_dirty();
					set_status("Pasted frame.", make_color_rgb(126, 245, 150));
				}
				return true;

			/* Flip H mirrors pixels horizontally through the editor's transform operation */
			case "flip_h":

				/* A supported horizontal flip marks the session dirty and redraws previews. The editor
				returns true for a canvas wider than one cell even when mirrored pixels look
				identical */
				if (editor.flip_horizontal())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Flip V mirrors pixels vertically */
			case "flip_v":

				/* A supported vertical flip marks unsaved edits and redraws previews. Its success
				means the canvas has more than one row, without comparing the before and after
				pixels */
				if (editor.flip_vertical())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Shift Left translates pixels one source column toward the left */
			case "shift_left":

				/* The nonzero left shift reports success and marks unsaved work, including an empty
				frame. A rejected zero-displacement request would leave dirty state unchanged */
				if (editor.shift_pixels(-1, 0))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Shift Right translates pixels one source column toward the right */
			case "shift_right":

				/* Accepted nonzero rightward travel marks the frame dirty and redraws its preview. The
				editor does not compare pixel content before returning success */
				if (editor.shift_pixels(1, 0))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Shift Up translates pixels one source row upward */
			case "shift_up":

				/* An accepted nonzero upward shift invalidates previews and marks unsaved work, even
				if the blank or shifted image appears unchanged */
				if (editor.shift_pixels(0, -1))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Shift Down translates pixels one source row downward */
			case "shift_down":

				/* Accepted nonzero downward travel marks the session dirty and invalidates draw
				surfaces. A false operation result would retain them */
				if (editor.shift_pixels(0, 1))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;

			/* Save commits the active frame before opening the keyboard-owned naming dialog */
			case "save":
				open_save_modal();
				return true;

			/* Cancel routes through request_close so dirty pixels require discard confirmation */
			case "cancel":
				request_close();
				return true;
		}

		return false;
	}

	/// @description Handle selection dragging, panning, picking, fill, and pen/eraser strokes on the active frame
	/// @param {Real} gui_x Mouse x in GUI pixels
	/// @param {Real} gui_y Mouse y in GUI pixels
	/// @param {Struct} grid Current grid_rect geometry
	/// @returns {Bool} Whether the pointer or active selection drag belongs to the grid
	update_grid_input = function(gui_x, gui_y, grid)
	{
		/* An in-progress selection drag keeps ownership even if the pointer leaves the grid, using
		clamped source cells to finish a consistent selection move */
		if (editor_tool == PIXEL_EDITOR_TOOL_SELECT && editor.selection_drag_active())
		{
			/* drag_col and drag_row are the pointer's source-cell coordinates including pan, clamped
			to the frame while dragging */
			var drag_col = grid_col_from_gui(gui_x, grid);
			var drag_row = grid_row_from_gui(gui_y, grid);
			editor.update_selection_drag(drag_col, drag_row);

			/* A released or no-longer-held left button ends the drag. While held, keep updating the
			preview without committing it */
			if (!mouse_check_button(mb_left) || mouse_check_button_released(mb_left))
			{
				/* Only a finished drag that changes pixels marks the editor dirty and redraws cached
				artwork */
				if (editor.finish_selection_drag())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
			}
			return true;
		}

		/* Outside-grid input ends ordinary painting strokes and reports false. Active selection drags
		have already been handled above */
		if (!point_in_gui_rect(gui_x, gui_y, grid))
		{
			editor_dragging = false;
			return false;
		}

		hover_key = "grid";

		/* Wheel Up pans the source view rather than changing artwork, with Shift selecting horizontal
		movement */
		if (mouse_wheel_up())
		{
			/* Holding Shift pans left by a quarter-view. Otherwise the same wheel event pans upward */
			if (keyboard_check(vk_shift))
			{
				/* Leftward wheel displacement is at least one source cell or a quarter of visible
				columns */
				var wheel_step_left = max(1, floor(grid.visible_cols / 4));
				pan_editor_view(-wheel_step_left, 0);
			}

			/* Without Shift, Wheel Up moves toward earlier source rows */
			else
			{
				/* Upward wheel displacement is at least one source cell or a quarter of visible rows */
				var wheel_step_up = max(1, floor(grid.visible_rows / 4));
				pan_editor_view(0, -wheel_step_up);
			}
			return true;
		}

		/* Wheel Down pans in the opposite direction and consumes the grid input for this update */
		if (mouse_wheel_down())
		{
			/* Shift makes Wheel Down move right, keeping horizontal and vertical gestures distinct */
			if (keyboard_check(vk_shift))
			{
				/* Rightward wheel displacement is a positive quarter-view source-column amount with a
				one-cell minimum */
				var wheel_step_right = max(1, floor(grid.visible_cols / 4));
				pan_editor_view(wheel_step_right, 0);
			}

			/* Without Shift, Wheel Down moves toward later source rows */
			else
			{
				/* Downward wheel displacement uses a quarter of visible source rows with a one-cell
				minimum */
				var wheel_step_down = max(1, floor(grid.visible_rows / 4));
				pan_editor_view(0, wheel_step_down);
			}
			return true;
		}

		/* pixel_col and pixel_row convert this pointer to frame source-cell coordinates and become the
		stored grid hover location */
		var pixel_col = grid_col_from_gui(gui_x, grid);
		var pixel_row = grid_row_from_gui(gui_y, grid);
		hover_col = pixel_col;
		hover_row = pixel_row;

		/* Selection mode handles selection creation, preview dragging and release instead of painting
		or sampling */
		if (editor_tool == PIXEL_EDITOR_TOOL_SELECT)
		{
			/* A fresh left press begins selection dragging at this source cell and consumes the input */
			if (mouse_check_button_pressed(mb_left))
			{
				editor.begin_selection_drag(pixel_col, pixel_row);
				return true;
			}

			/* Held left input updates a selection only when a drag is active, avoiding selection
			changes from an unrelated held click */
			if (mouse_check_button(mb_left) && editor.selection_drag_active())
			{
				editor.update_selection_drag(pixel_col, pixel_row);
				return true;
			}

			/* Releasing left completes the selection gesture and consumes this grid update */
			if (mouse_check_button_released(mb_left))
			{
				/* A completed gesture marks edits dirty only when it moved or otherwise changed
				selected pixels */
				if (editor.finish_selection_drag())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;
			}
		}

		/* A new left press in picker mode samples one pixel rather than starting a stroke */
		if (mouse_check_button_pressed(mb_left) && editor_tool == PIXEL_EDITOR_TOOL_COLOR_PICKER)
		{
			/* Packed pixel at the clicked source cell supplies its RGB channels when visible */
			var picked_pixel = editor.get_pixel(pixel_col, pixel_row);

			/* Only pixels with nonzero alpha become the current painting color. Transparent cells
			leave the chosen RGB unchanged */
			if (editor.pixel_alpha(picked_pixel) > 0)
			{
				set_current_colour_rgb(editor.pixel_red(picked_pixel), editor.pixel_green(picked_pixel), editor.pixel_blue(picked_pixel));
			}
			return true;
		}

		/* A new left press starts a fill or records the single undo snapshot shared by a subsequent
		pen/eraser stroke */
		if (mouse_check_button_pressed(mb_left))
		{
			/* Fill mode performs one flood-fill operation on press and returns before continuous
			painting begins */
			if (editor_tool == PIXEL_EDITOR_TOOL_FILL)
			{
				editor.push_undo_snapshot();

				/* A fill that changes pixels marks edits dirty and invalidates previews. Identical
				fill content retains existing render state */
				if (editor.fill_pixels(pixel_col, pixel_row, current_red, current_green, current_blue))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				return true;
			}

			/* Capture one undo state at stroke start.
			Held pen/eraser updates share that snapshot */
			editor.push_undo_snapshot();
			editor_dragging = true;
		}

		/* Continuous painting requires held left input and a stroke started in this grid. Fill, picker
		and select are excluded because they handle their own gestures */
		if (mouse_check_button(mb_left)
		&& editor_dragging
		&& editor_tool != PIXEL_EDITOR_TOOL_FILL
		&& editor_tool != PIXEL_EDITOR_TOOL_COLOR_PICKER
		&& editor_tool != PIXEL_EDITOR_TOOL_SELECT)
		{
			/* Eraser strokes clear the clicked pixel rather than applying the current RGB */
			if (editor_tool == PIXEL_EDITOR_TOOL_ERASER)
			{
				/* A valid source-cell erase reports success and marks the frame dirty, even if that
				pixel was already transparent. Invalid cells would leave dirty state unchanged */
				if (editor.erase_pixel(pixel_col, pixel_row))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
			}

			/* The remaining continuous tool paints the current RGB into this source cell */
			else
			{
				/* A valid source-cell paint reports success and invalidates the frame cache, even when
				the written RGB matches existing pixels. Invalid cells would skip those updates */
				if (editor.paint_pixel(pixel_col, pixel_row, current_red, current_green, current_blue))
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
			}
			return true;
		}

		/* Release ends the ordinary stroke so a later press captures a fresh undo snapshot */
		if (mouse_check_button_released(mb_left))
		{
			editor_dragging = false;
		}

		return true;
	}

	/// @description Capture editor keyboard shortcuts, tools, grid gestures, frame selection and color controls
	/// @returns {Bool} Whether an open pixel editor owns this update
	update_main_input = function()
	{
		/* The main input path requires an open editor with editable pixels. Closed UI or missing pixel
		state returns false */
		if (!open || !is_struct(editor))
		{
			return false;
		}

		/* gui_x/y locate the GUI pointer, rect bounds the main panel and grid maps pixel-tool input
		into source cells */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var rect = main_rect();
		var grid = grid_rect();
		hover_key = "";

		/* Escape clears an active selection first, then later presses request closing with
		unsaved-edit protection */
		if (keyboard_check_pressed(vk_escape))
		{
			/* A current selection is dismissed without closing the editor. With no selection, proceed
			to request_close */
			if (editor.selection_active)
			{
				editor.clear_selection();
				return true;
			}

			request_close();
			return true;
		}

		/* Left-arrow presses pan one source column toward the start without painting */
		if (keyboard_check_pressed(vk_left))
		{
			pan_editor_view(-1, 0);
			return true;
		}

		/* Right-arrow presses pan one source column toward the end */
		if (keyboard_check_pressed(vk_right))
		{
			pan_editor_view(1, 0);
			return true;
		}

		/* Up-arrow presses pan one source row upward */
		if (keyboard_check_pressed(vk_up))
		{
			pan_editor_view(0, -1);
			return true;
		}

		/* Down-arrow presses pan one source row downward */
		if (keyboard_check_pressed(vk_down))
		{
			pan_editor_view(0, 1);
			return true;
		}

		/* Control plus a new Z press routes undo once for that key press, retaining the active tool */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Z")))
		{
			apply_editor_action("undo");
			return true;
		}

		/* Control plus a new Y press routes redo through the same action path as its button */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Y")))
		{
			apply_editor_action("redo");
			return true;
		}

		/* Control plus C copies the active selection or whole frame through the common clipboard
		action */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("C")))
		{
			apply_editor_action("copy");
			return true;
		}

		/* Control plus X cuts only a current selection, keeping whole-frame copy separate from cutting */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("X")))
		{
			/* An active selection can be cut into the region clipboard. With no selection, show
			guidance and retain pixels */
			if (editor.selection_active)
			{
				/* A successful cut removes selected pixels, marks unsaved state and invalidates cached
				artwork */
				if (editor.cut_selection_to_clipboard())
				{
					editor_dirty = true;
					mark_editor_surface_dirty();
				}
				set_status("Cut selection.", make_color_rgb(126, 245, 150));
			}

			/* Without an active selection there is nothing to cut, so report that state without
			modifying the frame */
			else
			{
				set_status("No selection to cut.", make_color_rgb(255, 220, 95));
			}
			return true;
		}

		/* Control plus V uses the common paste action, preserving its region-before-frame clipboard
		priority */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("V")))
		{
			apply_editor_action("paste");
			return true;
		}

		/* Control plus zero restores the authored 100-percent view */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("0")))
		{
			reset_editor_zoom();
			return true;
		}

		/* Control with a fresh add, plus or equals key press advances to the next larger zoom level,
		supporting keyboard variants */
		if (keyboard_check(vk_control)
		&& (keyboard_check_pressed(vk_add) || keyboard_check_pressed(ord("+")) || keyboard_check_pressed(ord("="))))
		{
			adjust_editor_zoom(1);
			return true;
		}

		/* Control with subtract or minus requests the next smaller zoom level */
		if (keyboard_check(vk_control)
		&& (keyboard_check_pressed(vk_subtract) || keyboard_check_pressed(ord("-"))))
		{
			adjust_editor_zoom(-1);
			return true;
		}

		/* Control plus S opens save-name entry after committing the current mutable frame */
		if (keyboard_check(vk_control) && keyboard_check_pressed(ord("S")))
		{
			open_save_modal();
			return true;
		}

		/* Delete or Backspace clears pixels only when a selection is active. Without a selection these
		keys leave the entire frame intact */
		if ((keyboard_check_pressed(vk_delete) || keyboard_check_pressed(vk_backspace))
		&& editor.selection_active)
		{
			/* Only changed selected pixels mark the editor dirty and invalidate preview surfaces */
			if (editor.clear_selected_pixels(true))
			{
				editor_dirty = true;
				mark_editor_surface_dirty();
			}
			set_status("Deleted selection pixels.", make_color_rgb(126, 245, 150));
			return true;
		}

		/* An active HSV slider owns input until left is released, so dragging can continue outside its
		original rectangle */
		if (active_slider != "")
		{
			hover_key = active_slider + "_slider";

			/* While left stays held, update the chosen HSV channel from the pointer's horizontal GUI
			position */
			if (mouse_check_button(mb_left))
			{
				update_hsv_slider_from_mouse(active_slider, gui_x);
			}

			/* Release clears active_slider, allowing later frames to hit-test other editor controls */
			else
			{
				active_slider = "";
			}
			return true;
		}

		/* frame_hit is a row-major frame slot under the pointer, or noone when no frame button is hit */
		var frame_hit = frame_key_at(gui_x, gui_y);

		/* Only a valid frame hit contributes a frame hover key for thumbnail feedback and tooltips */
		if (frame_hit != noone)
		{
			hover_key = "frame_" + string(frame_hit);
		}

		/* action_key identifies a tool or action button under the pointer, returning empty text for a
		miss */
		var action_key = button_key_at(gui_x, gui_y);

		/* An action-button hit supplies the current hover key. No action leaves earlier frame hover
		unchanged */
		if (action_key != "")
		{
			hover_key = action_key;
		}

		/* swatch_hit is the palette index under the pointer or noone */
		var swatch_hit = swatch_index_at(gui_x, gui_y);

		/* A valid swatch updates hover styling to that preset's indexed routing key */
		if (swatch_hit != noone)
		{
			hover_key = "swatch_" + string(swatch_hit);
		}

		/* slider_hit names the hovered HSV channel or returns empty text */
		var slider_hit = slider_key_at(gui_x, gui_y);

		/* Only a hit HSV slider updates its hover state, leaving other target feedback intact
		otherwise */
		if (slider_hit != "")
		{
			hover_key = slider_hit + "_slider";
		}

		update_grid_input(gui_x, gui_y, grid);

		/* A new left press activates the cached frame/action/swatch/slider hit, giving these controls
		one operation per click */
		if (mouse_check_button_pressed(mb_left))
		{
			/* A frame-button hit commits the old frame and loads the selected slot with fresh mutable
			editor/undo state */
			if (frame_hit != noone)
			{
				load_active_frame(frame_hit);
				return true;
			}

			/* A nonempty action hit routes its stable button key and consumes the click */
			if (action_key != "")
			{
				apply_editor_action(action_key);
				return true;
			}

			/* A hit color preset replaces current painting RGB and synchronizes HSV controls */
			if (swatch_hit != noone)
			{
				/* Chosen preset's r/g/b byte channels supply the new painting color */
				var swatch = swatches[swatch_hit];
				set_current_colour_rgb(swatch.r, swatch.g, swatch.b);
				return true;
			}

			/* A hit HSV slider becomes the active drag owner and samples its channel immediately */
			if (slider_hit != "")
			{
				active_slider = slider_hit;
				update_hsv_slider_from_mouse(slider_hit, gui_x);
				return true;
			}
		}

		/* Clicks and hover outside the panel remain consumed while the editor is open so input cannot
		reach gameplay behind it */
		if (!point_in_gui_rect(gui_x, gui_y, rect))
		{
			return true;
		}

		return true;
	}

	/// @description Route modal input before the main editor so the owning Step event can stop gameplay input
	/// @returns {Bool} Whether an open editor or modal captured this update
	update_client_input = function()
	{
		/* Any active modal receives input before the main editor, ensuring its naming, confirmation or
		loading state owns this update */
		if (modal != "")
		{
			return update_modal_input();
		}

		/* With no modal, an open editor handles tools and pixels. When both are closed, return false
		so gameplay can resume */
		if (open)
		{
			return update_main_input();
		}

		return false;
	}
	#endregion /* Editor Input and Actions END */

	#region /* Buttons and Pixel Grid Rendering */
	/// @description Draw a GUI editor action with selected, disabled, hover and optional icon presentation
	/// @param {Struct} rect GUI edge record
	/// @param {String} label Displayed action text
	/// @param {Bool} active Selected-tool styling, default false
	/// @param {Bool} enabled Availability styling, default true
	/// @param {Bool} hovered Mouse-target styling, default false
	/// @param {Id.Sprite|Real} icon_spr Optional icon, default noone
	character_maker_draw_button = function(rect, label, active = false, enabled = true, hovered = false, icon_spr = noone)
	{
		/* fill_colour darkens disabled controls, brightens enabled hovered controls and otherwise uses
		the ordinary button fill */
		var fill_colour = enabled ? (hovered ? make_color_rgb(76, 80, 88) : make_color_rgb(54, 57, 62)) : make_color_rgb(32, 34, 38);

		/* An active tool overrides hover fill so the selected editing mode remains identifiable */
		if (active)
		{
			fill_colour = make_color_rgb(78, 88, 104);
		}

		/* Enabled buttons draw at full opacity and disabled ones at 45 percent, indicating
		availability without changing hit handling */
		draw_set_alpha(enabled ? 1 : 0.45);
		draw_set_colour(fill_colour);
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, false);

		/* Active tools receive a gold outline. Other buttons keep the neutral border */
		draw_set_colour(active ? make_color_rgb(255, 220, 95) : make_color_rgb(132, 136, 144));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, true);

		/* Enabled text is white and disabled text muted gray, matching the opacity cue */
		draw_set_colour(enabled ? c_white : make_color_rgb(132, 134, 138));

		/* A valid icon uses the icon-plus-label layout. Missing icons fall through to centered text */
		if (sprite_exists(icon_spr))
		{
			/* icon_w/h are source sprite dimensions with a one-pixel floor. icon_scale fits them to an
			18-pixel target before limiting enlargement */
			var icon_w = max(1, sprite_get_width(icon_spr));
			var icon_h = max(1, sprite_get_height(icon_spr));
			var icon_scale = min(18 / icon_w, 18 / icon_h);
			icon_scale = clamp(icon_scale, 1, 2);

			/* icon_left/top place the scaled icon with left padding and vertical centering in GUI
			pixels */
			var icon_left = rect.left + 10;
			var icon_top = rect.top + (rect.bottom - rect.top) * 0.5 - icon_h * icon_scale * 0.5;

			/* Icon tint and opacity follow enabled state, using white/full opacity for usable actions
			and muted gray/45 percent otherwise */
			draw_sprite_ext(icon_spr, 0, icon_left + sprite_get_xoffset(icon_spr) * icon_scale, icon_top + sprite_get_yoffset(icon_spr) * icon_scale, icon_scale, icon_scale, 0, enabled ? c_white : make_color_rgb(132, 134, 138), enabled ? 1 : 0.45);
			draw_set_halign(fa_left);
			scr_render_text(rect.left + 34, rect.top + 6, label, 14, rect.right - rect.left - 40);
		}

		/* Without an icon, center the label in the full rectangle rather than reserving unused icon
		space */
		else
		{
			draw_set_halign(fa_center);
			scr_render_text((rect.left + rect.right) * 0.5, rect.top + 6, label, 14, rect.right - rect.left - 8);
		}

		draw_set_halign(fa_left);
		draw_set_alpha(1);
	}

	/// @description Tile and clip the scrolling transparency sprite with a plain-color missing-sprite fallback
	/// @param {Real} draw_left Left GUI coordinate
	/// @param {Real} draw_top Top GUI coordinate
	/// @param {Real} draw_w Requested GUI width
	/// @param {Real} draw_h Requested GUI height
	/// @param {Real} draw_alpha Opacity, default 1
	/// @returns {Bool} True after background drawing
	draw_transparency_background = function(draw_left, draw_top, draw_w, draw_h, draw_alpha = 1)
	{
		/* safe_w/h are positive GUI-pixel bounds for clipping the transparency background, flooring
		empty dimensions to a one-pixel area */
		var safe_w = max(1, real(draw_w));
		var safe_h = max(1, real(draw_h));

		/* When the background sprite is unavailable, use a plain dark fill instead of accessing its
		texture */
		if (!sprite_exists(spr_transparent_background))
		{
			draw_set_alpha(draw_alpha);
			draw_set_colour(make_color_rgb(30, 32, 36));
			draw_rectangle(draw_left, draw_top, draw_left + safe_w, draw_top + safe_h, false);
			draw_set_alpha(1);
			return true;
		}

		/* tile_w/h are positive sprite tile dimensions. scroll_x/y wrap current_time millisecond
		motion at 36 and 48 ms per pixel, while restore_filter retains the caller's texture
		filtering */
		var tile_w = max(1, sprite_get_width(spr_transparent_background));
		var tile_h = max(1, sprite_get_height(spr_transparent_background));
		var scroll_x = floor(current_time / 36) mod tile_w;
		var scroll_y = floor(current_time / 48) mod tile_h;
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);

		/* tile_y starts above the area by the vertical scroll offset and advances one tile height
		until the requested bottom edge is covered */
		for (var tile_y = draw_top - scroll_y; tile_y < draw_top + safe_h; tile_y += tile_h)
		{
			/* tile_x similarly starts before the left edge and advances one tile width until this row
			covers the right edge */
			for (var tile_x = draw_left - scroll_x; tile_x < draw_left + safe_w; tile_x += tile_w)
			{
				/* crop_left/top/right/bottom intersect this tile with the requested GUI area. crop_w/h
				are the resulting dimensions used to draw only its visible part */
				var crop_left = max(draw_left, tile_x);
				var crop_top = max(draw_top, tile_y);
				var crop_right = min(draw_left + safe_w, tile_x + tile_w);
				var crop_bottom = min(draw_top + safe_h, tile_y + tile_h);
				var crop_w = crop_right - crop_left;
				var crop_h = crop_bottom - crop_top;

				/* Draw a clipped tile only when both dimensions are positive. Empty intersections
				contribute no background pixels */
				if (crop_w > 0 && crop_h > 0)
				{
					draw_sprite_part_ext(spr_transparent_background, 0, crop_left - tile_x, crop_top - tile_y, crop_w, crop_h, crop_left, crop_top, 1, 1, c_white, draw_alpha);
				}
			}
		}

		gpu_set_texfilter(restore_filter);
		draw_set_alpha(1);
		return true;
	}

	/// @description Choose single-color or alternating checker RGB for a source pixel cell
	/// @param {Real} pixel_col Source pixel column
	/// @param {Real} pixel_row Source pixel row
	/// @returns {Struct} Shared settings RGB color record
	transparency_pixel_cell_colour = function(pixel_col, pixel_row)
	{
		/* Shared saved transparency settings decide whether a source cell uses one color or a checker
		pattern */
		var settings = transparency_settings();

		/* Single-color mode uses the same stored RGB value for every source cell. Other modes continue
		to checker parity */
		if (settings.mode == "single")
		{
			return settings.single_color;
		}

		/* block_cells is the positive source-cell size of each checker square. checker_even identifies
		alternating squares from column/row block parity */
		var block_cells = clamp_transparency_block_size(settings.block_size);
		var checker_even = ((floor(real(pixel_col) / block_cells) + floor(real(pixel_row) / block_cells)) mod 2) == 0;

		/* Even checker squares use color_1 and odd squares color_2, keeping adjacent blocks visually
		distinct */
		return checker_even ? settings.color_1 : settings.color_2;
	}

	/// @description Draw one source cell's saved transparency-display color in a supplied rectangle
	/// @param {Real} draw_left Left GUI edge
	/// @param {Real} draw_top Top GUI edge
	/// @param {Real} draw_right Right GUI edge
	/// @param {Real} draw_bottom Bottom GUI edge
	/// @param {Real} pixel_col Source pixel column
	/// @param {Real} pixel_row Source pixel row
	/// @param {Real} draw_alpha Opacity, default 1
	/// @returns {Bool} True after drawing, leaving draw alpha at draw_alpha
	draw_transparency_pixel_cell = function(draw_left, draw_top, draw_right, draw_bottom, pixel_col, pixel_row, draw_alpha = 1)
	{
		/* RGB background color for this source cell, independent of the zoomed GUI rectangle used to
		draw it */
		var cell_colour = transparency_pixel_cell_colour(pixel_col, pixel_row);
		draw_set_alpha(draw_alpha);
		draw_set_colour(make_color_rgb(cell_colour.r, cell_colour.g, cell_colour.b));
		draw_rectangle(draw_left, draw_top, draw_right, draw_bottom, false);
		return true;
	}

	/// @description Draw a row-major frame snapshot as scaled rectangles, optionally over checker cells
	/// @param {String} hex_text RRGGBBAA frame snapshot
	/// @param {Real} draw_left GUI horizontal start
	/// @param {Real} draw_top GUI vertical start
	/// @param {Real} cell_size GUI pixels per source pixel
	/// @param {Bool} draw_checker Whether to draw cell backgrounds, default false
	draw_frame_hex = function(hex_text, draw_left, draw_top, cell_size, draw_checker = false)
	{
		/* safe_cell is the GUI-pixel size of a source pixel with a one-pixel minimum */
		var safe_cell = max(1, real(cell_size));

		/* pixel_row starts at source row zero and draws all frame_h rows once */
		for (var pixel_row = 0; pixel_row < frame_h; pixel_row++)
		{
			/* pixel_col visits each source column from zero through frame_w minus one in this row */
			for (var pixel_col = 0; pixel_col < frame_w; pixel_col++)
			{
				/* cell_left/top locate the current source pixel's scaled GUI rectangle */
				var cell_left = draw_left + pixel_col * safe_cell;
				var cell_top = draw_top + pixel_row * safe_cell;

				/* draw_checker enables a transparency cell background before the artwork. Without it,
				transparent pixels leave the existing draw target visible */
				if (draw_checker)
				{
					draw_transparency_pixel_cell(cell_left, cell_top, cell_left + safe_cell, cell_top + safe_cell, pixel_col, pixel_row, 1);
				}

				/* hex_offset is the one-based start of this row-major eight-character RRGGBBAA pixel.
				pixel_alpha decodes the final byte */
				var hex_offset = (pixel_row * frame_w + pixel_col) * 8 + 1;
				var pixel_alpha = hex_pair_to_byte(hex_text, hex_offset + 6);

				/* Only nontransparent pixels draw artwork over the background. Alpha zero leaves the
				background unchanged */
				if (pixel_alpha > 0)
				{
					draw_set_alpha(pixel_alpha / 255);
					draw_set_colour(make_color_rgb(hex_pair_to_byte(hex_text, hex_offset), hex_pair_to_byte(hex_text, hex_offset + 2), hex_pair_to_byte(hex_text, hex_offset + 4)));
					draw_rectangle(cell_left, cell_top, cell_left + safe_cell, cell_top + safe_cell, false);
				}
			}
		}

		draw_set_alpha(1);
	}

	/// @description Draw active pixels from their cache, the panned zoom grid, selection and current-cell hover
	draw_editor_grid = function()
	{
		/* Without an editor struct, there are no mutable pixels to render. Skip the grid and its
		overlays */
		if (!is_struct(editor))
		{
			return;
		}

		/* perf_token times this grid draw pass and grid supplies current zoomed cell and viewport
		geometry */
		var perf_token = scr_ui_perf_begin("character.grid");
		var grid = grid_rect();
		clamp_editor_view();
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(grid.left, grid.top, grid.viewport_right, grid.viewport_bottom, false);
		draw_transparency_background(grid.left, grid.top, grid.viewport_right - grid.left, grid.viewport_bottom - grid.top, 1);

		/* Cached active-frame surface provides current pixels and may be missing if allocation failed */
		var pixel_surface = ensure_editor_surface();

		/* Draw artwork only when the surface exists. The transparency background and grid can still
		render without it */
		if (surface_exists(pixel_surface))
		{
			/* Previous texture filter is restored after nearest-neighbor surface drawing so pixel art
			stays sharp without changing later GUI rendering */
			var restore_filter = gpu_get_texfilter();
			gpu_set_texfilter(false);
			draw_surface_part_ext(pixel_surface, editor_view_col, editor_view_row, grid.visible_cols, grid.visible_rows, grid.left, grid.top, grid.cell, grid.cell, c_white, 1);
			gpu_set_texfilter(restore_filter);
		}

		draw_set_alpha(0.24);
		draw_set_colour(c_black);

		/* grid_col includes both outer edges from zero through visible_cols, drawing one vertical
		boundary per source-cell edge */
		for (var grid_col = 0; grid_col <= grid.visible_cols; grid_col++)
		{
			draw_line(grid.left + grid_col * grid.cell, grid.top, grid.left + grid_col * grid.cell, grid.bottom);
		}

		/* grid_row includes zero through visible_rows so horizontal grid lines enclose the final row
		too */
		for (var grid_row = 0; grid_row <= grid.visible_rows; grid_row++)
		{
			draw_line(grid.left, grid.top + grid_row * grid.cell, grid.right, grid.top + grid_row * grid.cell);
		}

		draw_selection_overlay();

		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(82, 86, 94));
		draw_rectangle(grid.left, grid.top, grid.viewport_right, grid.viewport_bottom, true);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(grid.left, grid.top, grid.right, grid.bottom, true);

		/* Grid hover draws a pulsing cell highlight. Mouse positions over other editor controls leave
		the grid unhighlighted */
		if (hover_key == "grid")
		{
			/* gui_x/y are current GUI mouse coordinates. Local hover_col/row identify visible cells,
			and hover_alpha pulses between zero and half opacity using current_time milliseconds */
			var gui_x = device_mouse_x_to_gui(0);
			var gui_y = device_mouse_y_to_gui(0);
			var hover_col = clamp(floor((gui_x - grid.left) / grid.cell), 0, grid.visible_cols - 1);
			var hover_row = clamp(floor((gui_y - grid.top) / grid.cell), 0, grid.visible_rows - 1);
			var hover_alpha = (sin(current_time / 140) + 1) * 0.25;
			draw_set_alpha(hover_alpha);
			draw_set_colour(make_color_rgb(current_red, current_green, current_blue));
			draw_rectangle(grid.left + hover_col * grid.cell, grid.top + hover_row * grid.cell, grid.left + (hover_col + 1) * grid.cell, grid.top + (hover_row + 1) * grid.cell, false);
			draw_set_alpha(min(1, hover_alpha + 0.25));
			draw_rectangle(grid.left + hover_col * grid.cell, grid.top + hover_row * grid.cell, grid.left + (hover_col + 1) * grid.cell, grid.top + (hover_row + 1) * grid.cell, true);
			draw_set_alpha(1);
		}

		scr_ui_perf_end("character.grid", perf_token);
	}
	#endregion /* Buttons and Pixel Grid Rendering END */

	#region /* Selection and Cursor Overlays */
	/// @description Clip inclusive selection cells to the current viewport and draw their GUI overlay
	/// @param {Real} raw_left Left source-cell bound
	/// @param {Real} raw_top Top source-cell bound
	/// @param {Real} raw_right Inclusive right source-cell bound
	/// @param {Real} raw_bottom Inclusive bottom source-cell bound
	/// @param {Real} outline_colour Selection draw color
	/// @param {Real} fill_alpha Fill opacity, default 0.12
	/// @param {Real} outline_alpha Border opacity, default 1
	/// @returns {Bool} Whether a visible open-editor rectangle was drawn
	draw_selection_rect = function(raw_left, raw_top, raw_right, raw_bottom, outline_colour, fill_alpha = 0.12, outline_alpha = 1)
	{
		/* Selection rectangles need an open editor and pixel data. Closed or unavailable editors
		return false without drawing */
		if (!open || !is_struct(editor))
		{
			return false;
		}

		/* grid supplies zoom geometry. visible_left/top/right/bottom are inclusive source-cell bounds
		for the currently panned viewport */
		var grid = grid_rect();
		var visible_left = editor_view_col;
		var visible_top = editor_view_row;
		var visible_right = editor_view_col + grid.visible_cols - 1;
		var visible_bottom = editor_view_row + grid.visible_rows - 1;

		/* draw_left/top/right/bottom_cell intersect the requested inclusive source selection with
		those visible bounds */
		var draw_left_cell = max(raw_left, visible_left);
		var draw_top_cell = max(raw_top, visible_top);
		var draw_right_cell = min(raw_right, visible_right);
		var draw_bottom_cell = min(raw_bottom, visible_bottom);

		/* A selection wholly outside the viewport has inverted clipped bounds and produces no overlay */
		if (draw_right_cell < draw_left_cell || draw_bottom_cell < draw_top_cell)
		{
			return false;
		}

		/* rect_left/top/right/bottom convert the clipped source rectangle to GUI pixels, adding one
		cell at the far edges because source bounds are inclusive */
		var rect_left = grid.left + (draw_left_cell - editor_view_col) * grid.cell;
		var rect_top = grid.top + (draw_top_cell - editor_view_row) * grid.cell;
		var rect_right = grid.left + (draw_right_cell - editor_view_col + 1) * grid.cell;
		var rect_bottom = grid.top + (draw_bottom_cell - editor_view_row + 1) * grid.cell;
		draw_set_alpha(fill_alpha);
		draw_set_colour(outline_colour);
		draw_rectangle(rect_left, rect_top, rect_right, rect_bottom, false);
		draw_set_alpha(outline_alpha);
		draw_set_colour(c_black);
		draw_rectangle(rect_left + 1, rect_top + 1, rect_right + 1, rect_bottom + 1, true);
		draw_set_colour(outline_colour);
		draw_rectangle(rect_left, rect_top, rect_right, rect_bottom, true);
		draw_set_alpha(1);
		return true;
	}

	/// @description Draw selected source pixels at a proposed destination while clipping to the viewport
	/// @param {Real} target_left_cell Destination source column
	/// @param {Real} target_top_cell Destination source row
	/// @param {Real} draw_alpha Preview opacity multiplier, default 0.82
	/// @returns {Bool} Whether an active open-editor selection was processed
	draw_selection_pixel_preview = function(target_left_cell, target_top_cell, draw_alpha = 0.82)
	{
		/* Only an open editor with an active selection can draw selected pixel content. Other states
		return false */
		if (!open || !is_struct(editor) || !editor.selection_active)
		{
			return false;
		}

		/* grid supplies GUI conversion and visible_left/top/right/bottom define inclusive source-cell
		clipping bounds */
		var grid = grid_rect();
		var visible_left = editor_view_col;
		var visible_top = editor_view_row;
		var visible_right = editor_view_col + grid.visible_cols - 1;
		var visible_bottom = editor_view_row + grid.visible_rows - 1;

		/* source_row begins at selection_top and visits every selected source row through
		selection_bottom */
		for (var source_row = editor.selection_top; source_row <= editor.selection_bottom; source_row++)
		{
			/* target_row translates the current selected row to its proposed destination, preserving
			its offset within the selection */
			var target_row = target_top_cell + source_row - editor.selection_top;

			/* Destination rows outside the visible viewport are skipped before looking at their pixels */
			if (target_row < visible_top || target_row > visible_bottom)
			{
				continue;
			}

			/* source_col visits selection_left through selection_right inclusively for each visible
			destination row */
			for (var source_col = editor.selection_left; source_col <= editor.selection_right; source_col++)
			{
				/* target_col translates the selected column relative to the proposed destination left
				edge */
				var target_col = target_left_cell + source_col - editor.selection_left;

				/* Offscreen destination columns are excluded so a dragged selection preview stays
				clipped to the grid */
				if (target_col < visible_left || target_col > visible_right)
				{
					continue;
				}

				/* pixel_value is the packed source pixel and pixel_alpha its byte opacity used to
				combine preview fading with original transparency */
				var pixel_value = editor.get_pixel(source_col, source_row);
				var pixel_alpha = editor.pixel_alpha(pixel_value);

				/* Fully transparent selected pixels contribute no preview artwork and are skipped */
				if (pixel_alpha <= 0)
				{
					continue;
				}

				/* cell_left/top place this visible destination cell in GUI pixels using the current
				pan and zoom */
				var cell_left = grid.left + (target_col - editor_view_col) * grid.cell;
				var cell_top = grid.top + (target_row - editor_view_row) * grid.cell;
				draw_set_alpha(draw_alpha * pixel_alpha / 255);
				draw_set_colour(make_color_rgb(editor.pixel_red(pixel_value), editor.pixel_green(pixel_value), editor.pixel_blue(pixel_value)));
				draw_rectangle(cell_left, cell_top, cell_left + grid.cell, cell_top + grid.cell, false);
			}
		}

		draw_set_alpha(1);
		return true;
	}

	/// @description Draw stationary selection bounds or dim source and highlighted destination during dragging
	/// @returns {Bool} Whether an open-editor selection overlay was processed
	draw_selection_overlay = function()
	{
		/* Without an open editor and active selection there is no selection overlay to draw */
		if (!open || !is_struct(editor) || !editor.selection_active)
		{
			return false;
		}

		/* An active drag preview shows the original bounds dimly, the selected pixels at their
		proposed position and a highlighted destination outline */
		if (editor.selection_preview_active)
		{
			draw_selection_rect(editor.selection_left, editor.selection_top, editor.selection_right, editor.selection_bottom, make_color_rgb(178, 178, 184), 0.04, 0.48);
			draw_selection_pixel_preview(editor.selection_preview_left, editor.selection_preview_top, 0.86);

			/* preview_right/bottom complete the destination's inclusive source bounds from its
			top-left and selection size */
			var preview_right = editor.selection_preview_left + editor.selection_width() - 1;
			var preview_bottom = editor.selection_preview_top + editor.selection_height() - 1;
			draw_selection_rect(editor.selection_preview_left, editor.selection_preview_top, preview_right, preview_bottom, make_color_rgb(255, 220, 95), 0.16, 1);
			return true;
		}

		/* Outside preview dragging, draw only the current selection's highlighted source bounds */
		return draw_selection_rect(editor.selection_left, editor.selection_top, editor.selection_right, editor.selection_bottom, make_color_rgb(255, 220, 95), 0.1, 1);
	}

	/// @description Choose active tool cursor artwork with pen as the fallback
	/// @returns {Id.Sprite} Tool cursor sprite asset
	editor_tool_cursor_sprite = function()
	{
		/* The selected tool chooses its cursor artwork so the mouse communicates the next grid
		operation */
		switch (editor_tool)
		{
			/* Eraser mode shows the erase icon */
			case PIXEL_EDITOR_TOOL_ERASER:
				return spr_icon_erase;

			/* Fill mode shows the flood-fill icon */
			case PIXEL_EDITOR_TOOL_FILL:
				return spr_icon_fill;

			/* Color-picker mode shows the sample-color icon */
			case PIXEL_EDITOR_TOOL_COLOR_PICKER:
				return spr_icon_pick;

			/* Selection mode shows the selection cursor */
			case PIXEL_EDITOR_TOOL_SELECT:
				return spr_cursor_select;
		}

		/* The ordinary pen is the fallback cursor for remaining tool values */
		return spr_icon_pen;
	}

	/// @description Draw the active tool icon beside the GUI pointer only while hovering an open editor grid
	/// @returns {Bool} Whether a valid cursor was drawn
	draw_editor_grid_cursor = function()
	{
		/* Tool cursors draw only while the editor is open and the pointer belongs to its grid. Other
		GUI areas retain their own cursor presentation */
		if (!open || hover_key != "grid")
		{
			return false;
		}

		/* Cursor sprite is chosen from the active editing tool */
		var cursor_spr = editor_tool_cursor_sprite();

		/* Missing cursor artwork skips this overlay rather than attempting an invalid sprite draw */
		if (!sprite_exists(cursor_spr))
		{
			return false;
		}

		/* gui_x/y are the GUI mouse position and cursor_scale doubles source icon pixels for a
		readable tool indicator */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var cursor_scale = 2;
		draw_sprite_ext(cursor_spr, 0, gui_x + 3, gui_y + 3, cursor_scale, cursor_scale, 0, c_black, 0.35);
		draw_sprite_ext(cursor_spr, 0, gui_x + 1, gui_y + 1, cursor_scale, cursor_scale, 0, c_white, 1);
		draw_set_alpha(1);
		return true;
	}
	#endregion /* Selection and Cursor Overlays END */

	#region /* Frame and Color Previews */
	/// @description Draw all animation thumbnail caches with active and hover emphasis plus pose labels
	draw_frame_selector = function()
	{
		/* perf_token times all frame thumbnails and rect anchors the frame selector inside the main
		editor */
		var perf_token = scr_ui_perf_begin("character.frames");
		var rect = main_rect();
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(rect.left + 24, rect.top + 74, "Frames", 15, 220);

		/* frame_index starts at row-major slot zero and draws all column_count times row_count
		animation cells */
		for (var frame_index = 0; frame_index < column_count * row_count; frame_index++)
		{
			/* frame_rect supplies this slot's GUI button bounds. frame_active marks the mutable editor
			slot and frame_hovered marks the mouse's frame target */
			var frame_rect = frame_button_rect(frame_index);
			var frame_active = frame_index == active_frame;
			var frame_hovered = hover_key == "frame_" + string(frame_index);
			draw_set_alpha(1);

			/* The active frame uses the strongest fill, other hovered frames a lighter fill and
			ordinary frames the resting fill so selection takes visual priority */
			draw_set_colour(frame_active ? make_color_rgb(82, 125, 154) : (frame_hovered ? make_color_rgb(50, 54, 62) : make_color_rgb(30, 32, 36)));
			draw_rectangle(frame_rect.left, frame_rect.top, frame_rect.right, frame_rect.bottom, false);

			/* Only the active frame receives the gold border. Other thumbnails keep the neutral
			outline */
			draw_set_colour(frame_active ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
			draw_rectangle(frame_rect.left, frame_rect.top, frame_rect.right, frame_rect.bottom, true);

			/* preview_left/top place doubled source pixels inside the thumbnail and preview_surface
			retrieves live active pixels or another frame's cached snapshot */
			var preview_left = frame_rect.left + 15;
			var preview_top = frame_rect.top + 5;
			var preview_surface = ensure_frame_surface(frame_index);

			/* Draw a thumbnail only when its surface exists. Labels and button bounds remain available
			after allocation loss */
			if (surface_exists(preview_surface))
			{
				/* Retain texture filtering before disabling it for crisp doubled thumbnail pixels,
				then restore it immediately */
				var restore_filter = gpu_get_texfilter();
				gpu_set_texfilter(false);
				draw_surface_ext(preview_surface, preview_left, preview_top, 2, 2, 0, c_white, 1);
				gpu_set_texfilter(restore_filter);
			}
			draw_set_colour(make_color_rgb(255, 220, 95));
			draw_set_halign(fa_center);

			/* frame_row and frame_col decode this row-major slot into its facing direction and
			animation-pose labels */
			var frame_row = floor(frame_index / column_count);
			var frame_col = frame_index mod column_count;
			scr_render_text((frame_rect.left + frame_rect.right) * 0.5, frame_rect.bottom - 24, frame_direction_label(frame_row), 10, frame_rect.right - frame_rect.left - 6);
			draw_set_colour(c_white);
			scr_render_text((frame_rect.left + frame_rect.right) * 0.5, frame_rect.bottom - 12, frame_column_label(frame_col), 10, frame_rect.right - frame_rect.left - 6);
			draw_set_halign(fa_left);
		}
		scr_ui_perf_end("character.frames", perf_token);
	}

	/// @description Cache a slider gradient by its dimensions and the two HSV channels held constant
	/// @param {String} slider_key hue, saturation, or value
	/// @param {Real} slider_w Slider width in GUI pixels
	/// @param {Real} slider_h Slider height in GUI pixels
	/// @returns {Id.Surface|Real} Cached gradient surface, which callers check with surface_exists
	hsv_surface_for = function(slider_key, slider_w, slider_h)
	{
		/* safe_w/h are positive integer GUI-pixel dimensions. cache_key starts with those dimensions
		before adding the channels that control this gradient */
		var safe_w = max(1, floor(real(slider_w)));
		var safe_h = max(1, floor(real(slider_h)));
		var cache_key = string(safe_w) + "x" + string(safe_h);

		/* Each slider varies one HSV channel, so its cache key includes only the other two fixed
		channels along with dimensions */
		switch (slider_key)
		{
			/* Hue gradients vary hue while retaining current saturation and brightness in their cache
			identity */
			case "hue":
				cache_key += ":h:" + string(current_saturation) + ":" + string(current_value);
				break;

			/* Saturation gradients retain current hue and brightness */
			case "saturation":
				cache_key += ":s:" + string(current_hue) + ":" + string(current_value);
				break;

			/* Brightness gradients retain current hue and saturation */
			case "value":
				cache_key += ":v:" + string(current_hue) + ":" + string(current_saturation);
				break;
		}

		/* slider_surface starts unallocated and slider_cache_key empty until the selected channel's
		owned cache is retrieved */
		var slider_surface = noone;
		var slider_cache_key = "";

		/* Retrieve the hue, saturation or value cache pair for this channel. Unknown keys retain an
		unallocated surface and empty identity */
		switch (slider_key)
		{
			/* Hue uses hsv_surface_hue with hsv_key_hue */
			case "hue":
				slider_surface = hsv_surface_hue;
				slider_cache_key = hsv_key_hue;
				break;

			/* Saturation uses hsv_surface_saturation with hsv_key_saturation */
			case "saturation":
				slider_surface = hsv_surface_saturation;
				slider_cache_key = hsv_key_saturation;
				break;

			/* Brightness uses hsv_surface_value with hsv_key_value */
			case "value":
				slider_surface = hsv_surface_value;
				slider_cache_key = hsv_key_value;
				break;
		}

		/* An existing surface of the wrong width or height is freed before recreation. Matching
		dimensions retain it for the content-key check */
		if (surface_exists(slider_surface)
		&& (surface_get_width(slider_surface) != safe_w || surface_get_height(slider_surface) != safe_h))
		{
			surface_free(slider_surface);
			slider_surface = noone;
			slider_cache_key = "";
		}

		/* A lost surface or changed dimensions/fixed channels needs a fresh gradient. Matching live
		cache identity skips all rebuilding */
		if (!surface_exists(slider_surface) || slider_cache_key != cache_key)
		{
			/* Free the previous live surface before replacing it so changed gradients do not leak GPU
			resources */
			if (surface_exists(slider_surface))
			{
				surface_free(slider_surface);
			}

			slider_surface = surface_create(safe_w, safe_h);

			/* Only successful allocation can become a render target and receive gradient pixels.
			Failure leaves the cache unavailable for this draw */
			if (surface_exists(slider_surface))
			{
				surface_set_target(slider_surface);
				draw_clear_alpha(c_black, 0);

				/* segments splits the channel range into 36 painted strips, reducing gradient work
				compared with per-pixel drawing */
				var segments = 36;

				/* segment_index starts at zero and fills every strip through segments minus one */
				for (var segment_index = 0; segment_index < segments; segment_index++)
				{
					/* t0/t1 are this strip's normalized left/right endpoints and segment_colour starts
					white before the selected channel is resolved */
					var t0 = segment_index / segments;
					var t1 = (segment_index + 1) / segments;
					var segment_colour = c_white;

					/* Vary the chosen channel across the strip while holding the other two current HSV
					channels fixed */
					switch (slider_key)
					{
						/* Hue strips sample hue from zero to 255 using current saturation and
						brightness */
						case "hue":
							segment_colour = hsv_to_colour(round(t0 * 255), current_saturation, current_value);
							break;

						/* Saturation strips use current hue and brightness while sampling saturation */
						case "saturation":
							segment_colour = hsv_to_colour(current_hue, round(t0 * 255), current_value);
							break;

						/* Brightness strips use current hue and saturation while sampling value */
						case "value":
							segment_colour = hsv_to_colour(current_hue, current_saturation, round(t0 * 255));
							break;
					}

					draw_set_alpha(1);
					draw_set_colour(segment_colour);
					draw_rectangle(t0 * safe_w, 0, t1 * safe_w + 1, safe_h, false);
				}
				surface_reset_target();
				slider_cache_key = cache_key;
			}
		}

		/* Write the resulting surface and content key back to the selected channel's owned cache,
		ready for reuse or later disposal by free_hsv_surfaces */
		switch (slider_key)
		{
			/* Store the hue cache pair */
			case "hue":
				hsv_surface_hue = slider_surface;
				hsv_key_hue = slider_cache_key;
				break;

			/* Store the saturation cache pair */
			case "saturation":
				hsv_surface_saturation = slider_surface;
				hsv_key_saturation = slider_cache_key;
				break;

			/* Store the brightness cache pair */
			case "value":
				hsv_surface_value = slider_surface;
				hsv_key_value = slider_cache_key;
				break;
		}

		return slider_surface;
	}

	/// @description Draw one cached HSV gradient, channel label and current-value knob
	/// @param {String} label_text Short channel label
	/// @param {String} slider_key hue, saturation or value
	draw_hsv_slider = function(label_text, slider_key)
	{
		/* slider is this channel's GUI rectangle and slider_value starts zero until the appropriate
		current HSV channel is selected */
		var slider = hsv_slider_rect(slider_key);
		var slider_value = 0;

		/* Hue, saturation and value keys use their matching 0..255 channel for knob placement. Unknown
		keys retain the zero-position fallback */
		switch (slider_key)
		{
			/* The hue knob tracks current_hue */
			case "hue": slider_value = current_hue; break;

			/* The saturation knob tracks current_saturation */
			case "saturation": slider_value = current_saturation; break;

			/* The brightness knob tracks current_value */
			case "value": slider_value = current_value; break;
		}

		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(slider.left - 24, slider.top - 1, label_text, 13, 20);

		/* Channel-owned gradient surface is obtained for this slider's current GUI width and height */
		var slider_surface = hsv_surface_for(slider_key, slider.slider_w, slider.bottom - slider.top);

		/* A surviving gradient surface draws behind its knob. A missing surface still leaves the
		border and knob visible */
		if (surface_exists(slider_surface))
		{
			draw_surface(slider_surface, slider.left, slider.top);
		}

		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(slider.left, slider.top, slider.right, slider.bottom, true);

		/* Knob x coordinate maps the chosen byte channel across the slider's GUI-pixel width */
		var knob_x = slider.left + slider_value / 255 * slider.slider_w;
		draw_set_colour(c_black);
		draw_rectangle(knob_x - 3, slider.top - 3, knob_x + 3, slider.bottom + 3, false);
		draw_set_colour(c_white);
		draw_rectangle(knob_x - 2, slider.top - 2, knob_x + 2, slider.bottom + 2, false);
	}

	/// @description Draw zoom decrement, 100-percent reset and increment with boundary-aware availability
	draw_zoom_controls = function()
	{
		/* Zoom Out is enabled above the minimum, No Zoom when the view differs from 100 percent and
		Zoom In below the maximum. Each hover comparison identifies its own button for visual
		feedback */
		character_maker_draw_button(zoom_button_rect("zoom_out"), "Zoom Out", false, editor_zoom_percent > editor_zoom_min, hover_key == "zoom_out");
		character_maker_draw_button(zoom_button_rect("zoom_reset"), "No Zoom", false, editor_zoom_percent != 100, hover_key == "zoom_reset");
		character_maker_draw_button(zoom_button_rect("zoom_in"), "Zoom In", false, editor_zoom_percent < editor_zoom_max, hover_key == "zoom_in");
	}

	/// @description Draw needed panning arrows and one-based source-view coordinates
	/// @returns {Bool} Whether cropped source content required the pan controls
	draw_view_controls = function()
	{
		/* A viewport showing the entire source frame needs no pan controls. Return false without
		drawing arrows or coordinates */
		if (!view_controls_visible())
		{
			return false;
		}

		/* grid supplies visible source-cell counts and view_top anchors the pan row in GUI pixels */
		var grid = grid_rect();
		var view_top = view_button_rect("view_left").top;
		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(grid.left, view_top + 7, "View", 13, 42);

		/* Show the left arrow only when horizontal cropping exists. Its enabled state separately
		decides whether further leftward travel is possible */
		if (view_button_should_show("view_left"))
		{
			/* can_pan_left records remaining leftward source-cell travel. Disabled arrows also
			suppress hover styling */
			var can_pan_left = view_button_enabled("view_left");
			character_maker_draw_button(view_button_rect("view_left"), "<", false, can_pan_left, hover_key == "view_left" && can_pan_left);
		}

		/* Vertical cropping exposes the up arrow even at the top limit, where its enabled check
		explains unavailable travel */
		if (view_button_should_show("view_up"))
		{
			/* can_pan_up records whether the viewport can move above its current source row */
			var can_pan_up = view_button_enabled("view_up");
			character_maker_draw_button(view_button_rect("view_up"), "^", false, can_pan_up, hover_key == "view_up" && can_pan_up);
		}

		/* The down arrow appears only for vertically cropped views, with availability checked
		separately at the lower edge */
		if (view_button_should_show("view_down"))
		{
			/* can_pan_down records remaining downward source-cell travel */
			var can_pan_down = view_button_enabled("view_down");
			character_maker_draw_button(view_button_rect("view_down"), "v", false, can_pan_down, hover_key == "view_down" && can_pan_down);
		}

		/* Horizontal cropping exposes the right arrow, with the right boundary deciding availability */
		if (view_button_should_show("view_right"))
		{
			/* can_pan_right records remaining rightward source-cell travel */
			var can_pan_right = view_button_enabled("view_right");
			character_maker_draw_button(view_button_rect("view_right"), ">", false, can_pan_right, hover_key == "view_right" && can_pan_right);
		}

		/* view_label converts zero-based source offsets to one-based column,row text for the editor UI */
		var view_label = string(editor_view_col + 1) + "," + string(editor_view_row + 1);

		/* When either axis is cropped, append the full source frame dimensions so the user can relate
		the current viewport to its total size */
		if (grid.visible_cols < frame_w || grid.visible_rows < frame_h)
		{
			view_label += " / " + string(frame_w) + "," + string(frame_h);
		}
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(view_button_rect("view_right").right + 8, view_top + 7, view_label, 11, max(1, grid.viewport_right - view_button_rect("view_right").right - 8));
		return true;
	}

	/// @description Draw current RGB, authored swatches and HSV channels
	draw_colour_controls = function()
	{
		/* side_x and colour_top anchor the color section in GUI pixels. current_size is the 52-pixel
		current-color square */
		var side_x = side_left();
		var colour_top = colour_controls_top();
		var current_size = 52;
		draw_set_colour(make_color_rgb(current_red, current_green, current_blue));
		draw_rectangle(side_x, colour_top, side_x + current_size, colour_top + current_size, false);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(side_x, colour_top, side_x + current_size, colour_top + current_size, true);
		draw_set_colour(c_white);
		scr_render_text(side_x + 64, colour_top + 7, "Current Color", 13, side_width() - 64);
		scr_render_text(side_x + 64, colour_top + 28, "RGB " + string(current_red) + ", " + string(current_green) + ", " + string(current_blue), 11, side_width() - 64);
		draw_set_colour(c_white);
		scr_render_text(side_x, colour_swatch_top() - 22, "Swatches", 13, side_width());

		/* swatch_index starts at zero and draws every authored RGB swatch in order */
		for (var swatch_index = 0; swatch_index < array_length(swatches); swatch_index++)
		{
			/* swatch supplies the preset r/g/b byte channels and swatch_box gives its GUI bounds */
			var swatch = swatches[swatch_index];
			var swatch_box = swatch_rect(swatch_index);
			draw_set_colour(make_color_rgb(swatch.r, swatch.g, swatch.b));
			draw_rectangle(swatch_box.left, swatch_box.top, swatch_box.right, swatch_box.bottom, false);

			/* The hovered swatch gets a gold border. Other presets keep the neutral outline */
			draw_set_colour(hover_key == "swatch_" + string(swatch_index) ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
			draw_rectangle(swatch_box.left, swatch_box.top, swatch_box.right, swatch_box.bottom, true);
		}

		draw_hsv_slider("H", "hue");
		draw_hsv_slider("S", "saturation");
		draw_hsv_slider("V", "value");
	}

	/// @description Animate the selected facing row from frame caches beside the current editing grid
	draw_live_preview = function()
	{
		/* side_x and preview_top anchor the live animation under the sliders. save_rect limits
		available height and preview_cell fits source pixels at a two-to-four-pixel GUI scale */
		var side_x = side_left();
		var preview_top = hsv_slider_rect("value").bottom + 34;
		var save_rect = button_rect("save");
		var preview_cell = clamp(floor((save_rect.top - preview_top - 12) / frame_h), 2, 4);

		/* active_row is the selected facing row, preview_col follows the timed walking cycle and
		preview_index combines them into a row-major frame slot */
		var active_row = floor(active_frame / column_count);
		var preview_col = player_character_walk_column(true);
		var preview_index = active_row * column_count + preview_col;
		draw_set_colour(c_white);
		scr_render_text(side_x, preview_top - 18, "Preview " + frame_direction_label(active_row), 13, side_width());

		/* Cached surface for the currently animated frame, using the live editor when that slot is
		active */
		var preview_surface = ensure_frame_surface(preview_index);

		/* Draw the animation only if its frame surface exists. Missing allocation leaves the preview
		label without artwork */
		if (surface_exists(preview_surface))
		{
			/* Previous filtering is restored after sharp integer-scale drawing so later UI keeps its
			requested filter */
			var restore_filter = gpu_get_texfilter();
			gpu_set_texfilter(false);
			draw_surface_ext(preview_surface, side_x + 30, preview_top, preview_cell, preview_cell, 0, c_white, 1);
			gpu_set_texfilter(restore_filter);
		}
	}
	#endregion /* Frame and Color Previews END */

	#region /* Transparency Settings Rendering */
	/// @description Draw a transparency mode choice using draft selection and modal hover state
	/// @param {String} button_key Transparency mode routing key
	/// @param {String} label_text Displayed mode label
	/// @param {Bool} active Whether this draft mode is selected
	draw_transparency_radio = function(button_key, label_text, active)
	{
		/* rect positions this radio control and mark_left/top locate its 12-GUI-pixel selection box */
		var rect = transparency_modal_button_rect(button_key);
		var mark_left = rect.left + 2;
		var mark_top = rect.top + 5;
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(mark_left, mark_top, mark_left + 12, mark_top + 12, false);

		/* Hovered radio choices use a gold border, while ordinary choices use the neutral border */
		draw_set_colour(hover_key == "transparency_" + button_key ? make_color_rgb(255, 220, 95) : make_color_rgb(132, 136, 144));
		draw_rectangle(mark_left, mark_top, mark_left + 12, mark_top + 12, true);

		/* Only the active mode fills its selection box blue. Inactive choices retain an empty box */
		if (active)
		{
			draw_set_colour(make_color_rgb(84, 164, 244));
			draw_rectangle(mark_left + 3, mark_top + 3, mark_left + 9, mark_top + 9, false);
		}

		draw_set_colour(c_white);
		scr_render_text(rect.left + 20, rect.top + 4, label_text, 13, rect.right - rect.left - 22);
	}

	/// @description Draw one draft RGB sample and its Use Current action
	/// @param {String} label_text Displayed color role
	/// @param {Struct} colour_value Draft r/g/b byte record
	/// @param {Real} row_top Row y in GUI pixels
	/// @param {String} button_key Color-copy action key
	draw_transparency_colour_row = function(label_text, colour_value, row_top, button_key)
	{
		/* rect anchors the transparency dialog. box_left and box_top position this row's RGB color
		sample in GUI pixels */
		var rect = transparency_modal_rect();
		var box_left = rect.left + 138;
		var box_top = row_top;
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(rect.left + 42, row_top + 5, label_text, 13, 88);
		draw_set_colour(make_color_rgb(colour_value.r, colour_value.g, colour_value.b));
		draw_rectangle(box_left, box_top, box_left + 54, box_top + 24, false);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(box_left, box_top, box_left + 54, box_top + 24, true);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(box_left + 64, row_top + 6, "RGB " + string(colour_value.r) + ", " + string(colour_value.g) + ", " + string(colour_value.b), 11, max(1, rect.right - box_left - 196));

		/* Use Current highlights only when this row's routing key is the hovered transparency action */
		character_maker_draw_button(transparency_modal_button_rect(button_key), "Use Current", false, true, hover_key == "transparency_" + button_key);
	}

	/// @description Draw draft background modes, RGB choices and block-size input over the main editor
	draw_transparency_modal = function()
	{
		/* Current GUI rectangle for the transparency settings dialog */
		var rect = transparency_modal_rect();

		/* An open main editor uses lighter dimming behind its settings dialog. Without it, stronger
		dimming separates the modal from gameplay */
		draw_set_alpha(open ? 0.32 : 0.58);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
		draw_set_alpha(0.98);
		draw_set_colour(make_color_rgb(28, 30, 34));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, true);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);
		scr_render_text(rect.left + 18, rect.top + 16, "Transparency Background Settings", 18, rect.w - 36);

		/* The checker radio is active only for block mode and the single-color radio below only for
		single mode, displaying the draft choice before it is saved */
		draw_transparency_radio("mode_block", "Block Pattern", transparency_draft_mode == "block");
		draw_transparency_colour_row("Color 1", transparency_draft_color_1, rect.top + 82, "color_1_current");
		draw_transparency_colour_row("Color 2", transparency_draft_color_2, rect.top + 118, "color_2_current");

		/* GUI-pixel text field rectangle for the draft checker block size */
		var size_rect = transparency_block_size_input_rect();
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(rect.left + 42, size_rect.top + 6, "Block Size", 13, 88);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(size_rect.left, size_rect.top, size_rect.right, size_rect.bottom, false);

		/* Hover or keyboard focus gives the size field a gold border. Otherwise use its neutral
		outline */
		draw_set_colour(hover_key == "transparency_block_size" || transparency_focus == "block_size" ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
		draw_rectangle(size_rect.left, size_rect.top, size_rect.right, size_rect.bottom, true);
		draw_set_colour(c_white);

		/* Show a blinking caret only while the block-size field owns focus, alternating every 420
		current_time milliseconds */
		scr_render_text(size_rect.left + 6, size_rect.top + 6, transparency_draft_block_size_text + (transparency_focus == "block_size" && floor(current_time / 420) mod 2 == 0 ? "|" : ""), 13, size_rect.right - size_rect.left - 12);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(size_rect.right + 10, size_rect.top + 7, "2-999", 11, 80);

		draw_transparency_radio("mode_single", "Single Color", transparency_draft_mode == "single");
		draw_transparency_colour_row("Color", transparency_draft_single_color, rect.top + 216, "single_current");

		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(rect.left + 18, rect.bottom - 34, "Current", 11, 54);
		draw_set_colour(make_color_rgb(current_red, current_green, current_blue));
		draw_rectangle(rect.left + 74, rect.bottom - 36, rect.left + 102, rect.bottom - 14, false);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(rect.left + 74, rect.bottom - 36, rect.left + 102, rect.bottom - 14, true);

		/* OK and Cancel highlight against their own hovered routing keys, matching transparency-modal
		click dispatch */
		character_maker_draw_button(transparency_modal_button_rect("ok"), "OK", false, true, hover_key == "transparency_ok");
		character_maker_draw_button(transparency_modal_button_rect("cancel"), "Cancel", false, true, hover_key == "transparency_cancel");
		draw_set_alpha(1);
	}
	#endregion /* Transparency Settings Rendering END */

	#region /* Editor Tooltips and Modal Composition */
	/// @description Draw a pointer-adjacent GUI title and optional detail with canvas-edge positioning
	/// @param {String} title_text Tooltip title
	/// @param {String} detail_text Optional detail, empty text uses a shorter box
	/// @returns {Bool} True after tooltip drawing
	draw_tooltip_box = function(title_text, detail_text)
	{
		/* gui_x/y locate the pointer, while positive gui_w/h provide clipping limits. tooltip_w is 286
		GUI pixels */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var tooltip_w = 286;

		/* Title-only tooltips use 30 pixels of height and detailed ones 58. tooltip_left keeps a
		four-pixel horizontal margin and tooltip_top initially positions the box below the pointer */
		var tooltip_h = detail_text == "" ? 30 : 58;
		var tooltip_left = clamp(gui_x + 14, 4, max(4, gui_w - tooltip_w - 4));
		var tooltip_top = gui_y + 18;

		/* If the tooltip would pass the bottom GUI margin, move it above the pointer instead.
		Otherwise keep the below-pointer position */
		if (tooltip_top + tooltip_h > gui_h - 4)
		{
			tooltip_top = max(4, gui_y - tooltip_h - 12);
		}

		draw_set_alpha(0.94);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(tooltip_left, tooltip_top, tooltip_left + tooltip_w, tooltip_top + tooltip_h, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(tooltip_left, tooltip_top, tooltip_left + tooltip_w, tooltip_top + tooltip_h, true);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);
		scr_render_text(tooltip_left + 8, tooltip_top + 7, title_text, 13, tooltip_w - 16);

		/* Nonempty detail text gets a second muted line. Title-only tips skip that row */
		if (detail_text != "")
		{
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(tooltip_left + 8, tooltip_top + 29, detail_text, 11, tooltip_w - 16);
		}

		draw_set_alpha(1);
		return true;
	}

	/// @description Explain the hovered animation frame's direction and pose
	/// @returns {Bool} Whether a valid frame hover produced a tooltip
	draw_hover_tooltip = function()
	{
		/* Only frame hover keys provide frame-specific tooltips. Other controls return false without
		parsing their keys */
		if (string_copy(hover_key, 1, 6) != "frame_")
		{
			return false;
		}

		/* Zero-based frame slot parsed from the frame_ routing suffix, before bounds validation */
		var frame_index = floor(real(string_copy(hover_key, 7, string_length(hover_key) - 6)));

		/* Reject slots outside the fixed twelve-frame grid so malformed hover text cannot address
		frame labels */
		if (frame_index < 0 || frame_index >= column_count * row_count)
		{
			return false;
		}

		/* frame_row/col split the row-major slot into direction and pose. title_text combines their
		short labels and detail_text explains that pose and facing */
		var frame_row = floor(frame_index / column_count);
		var frame_col = frame_index mod column_count;
		var title_text = frame_direction_label(frame_row) + " - " + frame_column_label(frame_col);
		var detail_text = "Faces " + string_lower(frame_direction_label(frame_row)) + ". " + frame_column_detail(frame_col);
		return draw_tooltip_box(title_text, detail_text);
	}

	/// @description Draw the open editing panel, frame previews, pixel grid, controls and unexpired feedback
	draw_main = function()
	{
		/* A closed main editor draws no grid, tools or caches. Entry and other modals are composed
		separately */
		if (!open)
		{
			return;
		}

		/* perf_token times the complete main editor draw pass and rect defines its GUI panel */
		var perf_token = scr_ui_perf_begin("character.draw_main");
		var rect = main_rect();
		draw_set_alpha(0.58);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
		draw_set_alpha(0.97);
		draw_set_colour(make_color_rgb(28, 30, 34));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, true);

		draw_set_colour(c_white);
		scr_render_text(rect.left + 24, rect.top + 22, editing_target == "pet" ? "Pet Maker" : "Character Maker", 22, 250);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(rect.left + 278, rect.top + 26, "48x76 sheet, 3x4 frames, 16x19 each", 13, 360);

		/* Explain whether saving replaces the installed custom source or creates a copy, matching
		source_can_overwrite used by save_character */
		scr_render_text(rect.left + 650, rect.top + 26, source_can_overwrite ? (editing_target == "pet" ? "Updates this pet's artwork" : "Saves over custom character") : "Saves as custom copy", 13, 280);

		/* Display nonempty feedback only while its current_time millisecond expiry has not passed.
		Empty and expired messages are skipped */
		if (status_text != "" && current_time <= status_until)
		{
			draw_set_colour(status_colour);
			scr_render_text(rect.left + 24, rect.bottom - 26, status_text, 13, 540);
		}

		draw_frame_selector();
		draw_editor_grid();
		draw_zoom_controls();
		draw_view_controls();
		draw_colour_controls();
		draw_live_preview();

		/* Each tool button compares editor_tool with its own tool constant for active styling and
		hover_key with its routing key for hover feedback. These flags affect appearance while
		apply_editor_action owns tool changes */
		character_maker_draw_button(button_rect("pen"), "Pen", editor_tool == PIXEL_EDITOR_TOOL_PEN, true, hover_key == "pen", spr_icon_pen);
		character_maker_draw_button(button_rect("eraser"), "Eraser", editor_tool == PIXEL_EDITOR_TOOL_ERASER, true, hover_key == "eraser", spr_icon_erase);
		character_maker_draw_button(button_rect("fill"), "Fill", editor_tool == PIXEL_EDITOR_TOOL_FILL, true, hover_key == "fill", spr_icon_fill);
		character_maker_draw_button(button_rect("picker"), "Color Picker", editor_tool == PIXEL_EDITOR_TOOL_COLOR_PICKER, true, hover_key == "picker", spr_icon_pick);
		character_maker_draw_button(button_rect("select"), "Select", editor_tool == PIXEL_EDITOR_TOOL_SELECT, true, hover_key == "select", spr_icon_select);

		/* Undo and Redo availability follow their corresponding editor history checks. Other basic
		actions are shown enabled and rely on their operation's return value to report actual pixel
		changes */
		character_maker_draw_button(button_rect("undo"), "Undo", false, editor.can_undo(), hover_key == "undo");
		character_maker_draw_button(button_rect("redo"), "Redo", false, editor.can_redo(), hover_key == "redo");
		character_maker_draw_button(button_rect("clear"), "Clear", false, true, hover_key == "clear");
		character_maker_draw_button(button_rect("copy"), "Copy", false, true, hover_key == "copy");

		/* Paste is enabled when either a region clipboard or a copied whole frame exists. Its routing
		key still determines hover styling */
		character_maker_draw_button(button_rect("paste"), "Paste", false, editor.region_clipboard_available() || copied_frame_hex != "", hover_key == "paste");
		character_maker_draw_button(button_rect("flip_h"), "Flip H", false, true, hover_key == "flip_h");
		character_maker_draw_button(button_rect("flip_v"), "Flip V", false, true, hover_key == "flip_v");
		character_maker_draw_button(button_rect("shift_left"), "Left", false, true, hover_key == "shift_left");
		character_maker_draw_button(button_rect("shift_right"), "Right", false, true, hover_key == "shift_right");
		character_maker_draw_button(button_rect("shift_up"), "Up", false, true, hover_key == "shift_up");
		character_maker_draw_button(button_rect("shift_down"), "Down", false, true, hover_key == "shift_down");
		character_maker_draw_button(button_rect("save"), "Save", false, true, hover_key == "save");
		character_maker_draw_button(button_rect("cancel"), "Cancel", false, true, hover_key == "cancel");
		draw_hover_tooltip();
		scr_ui_perf_end("character.draw_main", perf_token);
	}

	/// @description Draw the active entry, load, save, discard or transparency dialog above editor content
	draw_modal = function()
	{
		/* An empty modal key means there is no dialog to draw over the main editor */
		if (modal == "")
		{
			return;
		}

		/* Transparency settings have their own larger layout and renderer, so draw that dialog and
		stop generic modal composition */
		if (modal == "transparency")
		{
			draw_transparency_modal();
			return;
		}

		/* Discard uses a shorter 180-pixel dialog while other generic modals use 210 pixels. rect
		remains clipped and centered by modal_rect */
		var rect = modal == "discard" ? modal_rect(430, 180) : modal_rect(430, 210);

		/* An existing editor behind the modal uses lighter dimming than a modal opened directly over
		gameplay */
		draw_set_alpha(open ? 0.32 : 0.58);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
		draw_set_alpha(0.98);
		draw_set_colour(make_color_rgb(28, 30, 34));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, true);

		/* The entry modal offers a blank sheet, the current character or cancellation, then returns
		before drawing another modal type */
		if (modal == "start")
		{
			draw_set_colour(c_white);
			scr_render_text(rect.left + 22, rect.top + 22, editing_target == "pet" ? "Pet Maker" : "Character Maker", 20, rect.w - 44);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(rect.left + 22, rect.top + 50, editing_target == "pet" ? "Create a 48x76 sheet for your companion." : "Create a 48x76 custom character sheet.", 13, rect.w - 44);

			/* Each entry action highlights only when its matching modal hover key is selected by
			update_modal_input */
			character_maker_draw_button(modal_button_rect("new"), "New Blank", false, true, hover_key == "modal_new");
			character_maker_draw_button(modal_button_rect("edit"), "Edit Current", false, editing_target != "pet" || requested_source_key != "", hover_key == "modal_edit");
			character_maker_draw_button(modal_button_rect("cancel"), "Cancel", false, true, hover_key == "modal_cancel");

			/* Show entry feedback before its current_time deadline, keeping old load errors from
			remaining visible indefinitely */
			if (current_time < status_until)
			{
				draw_set_colour(status_colour);
				scr_render_text_wrapped(rect.left + 22, rect.top + 126, status_text, 13, rect.w - 44, 3);
			}
			return;
		}

		/* Loading displays the next one-based frame number and a cancel action while frame extraction
		proceeds one per Step */
		if (modal == "loading")
		{
			draw_set_colour(c_white);
			scr_render_text(rect.left + 22, rect.top + 22, editing_target == "pet" ? "Opening Pet" : "Opening Character", 20, rect.w - 44);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(rect.left + 22, rect.top + 66, "Loading animation frame " + string(loading_frame + 1)
				+ " of " + string(column_count * row_count) + "...", 16, rect.w - 44);

			/* The loading cancel action follows modal_cancel hover so its feedback matches
			cancellation input */
			character_maker_draw_button(modal_button_rect("cancel"), "Cancel", false, true, hover_key == "modal_cancel");
			return;
		}

		/* The save dialog presents the current name and save/cancel actions, leaving pixel edits
		available if saving later fails */
		if (modal == "save")
		{
			draw_set_colour(c_white);
			scr_render_text(rect.left + 22, rect.top + 22, editing_target == "pet" ? "Save Pet" : "Save Character", 20, rect.w - 44);
			draw_set_colour(make_color_rgb(178, 178, 184));

			/* Use replacement wording for an overwritable installed custom source and new-character
			wording for protected or copied sources */
			scr_render_text(rect.left + 22, rect.top + 52, source_can_overwrite ? (editing_target == "pet" ? "This will update this pet's artwork." : "This will update the selected custom character.") : (editing_target == "pet" ? "This will save new pet artwork." : "This will save a new custom character."), 13, rect.w - 44);

			/* GUI rectangle for the name text field inside the save dialog */
			var input_rect = make_rect(rect.left + 22, rect.top + 88, rect.w - 44, 34);
			draw_set_colour(make_color_rgb(12, 13, 16));
			draw_rectangle(input_rect.left, input_rect.top, input_rect.right, input_rect.bottom, false);
			draw_set_colour(make_color_rgb(132, 136, 144));
			draw_rectangle(input_rect.left, input_rect.top, input_rect.right, input_rect.bottom, true);
			draw_set_colour(c_white);

			/* The name caret alternates every 420 current_time milliseconds to show the keyboard-owned
			save field */
			scr_render_text(input_rect.left + 8, input_rect.top + 8, save_name + (floor(current_time / 420) mod 2 == 0 ? "|" : ""), 16, input_rect.right - input_rect.left - 16);

			/* Save and Cancel use their own modal_confirm/modal_cancel hover states, matching the
			save-input dispatch */
			character_maker_draw_button(modal_button_rect("confirm"), "Save", false, true, hover_key == "modal_confirm");
			character_maker_draw_button(modal_button_rect("cancel"), "Cancel", false, true, hover_key == "modal_cancel");
			return;
		}

		/* Discard confirmation warns that edits will be lost and offers destructive confirmation or a
		return to editing */
		if (modal == "discard")
		{
			draw_set_colour(c_white);
			scr_render_text(rect.left + 22, rect.top + 22, "Discard Edits?", 20, rect.w - 44);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(rect.left + 22, rect.top + 56, editing_target == "pet" ? "Unsaved pet changes will be lost." : "Unsaved character changes will be lost.", 13, rect.w - 44);

			/* Discard and Cancel follow their separate hover keys so the confirmation action remains
			distinguishable from keeping edits */
			character_maker_draw_button(modal_button_rect("confirm"), "Discard", false, true, hover_key == "modal_confirm");
			character_maker_draw_button(modal_button_rect("cancel"), "Cancel", false, true, hover_key == "modal_cancel");
		}
	}

	/// @description Draw the editor first and its active modal above it
	draw_gui = function()
	{
		draw_main();
		draw_modal();
	}
	#endregion /* Editor Tooltips and Modal Composition END */

}

/// @description Get the shared character editor. Creates its state on first use
/// @returns {Struct} Shared scr_character_maker instance
function scr_get_character_maker()
{
	/* Create one shared editor on first use and retain its session, frame data and owned surface
	caches across callers */
	static maker = new scr_character_maker();
	return maker;
}
