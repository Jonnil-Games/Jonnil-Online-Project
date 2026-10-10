#macro Stamps scr_get_stamps()

/// @description Own the stamp library, PNG and pixel caches, custom-package storage, and the stamp editor. Placement resizing uses separate copies
function scr_stamps() constructor
{
	/* stamp_w and stamp_h are the default new-canvas dimensions in source pixels, both 32 */
	stamp_w = 32;
	stamp_h = 32;

	/* stamp_min_size requires at least one pixel per side. stamp_max_editable_size caps editor sides
	at 512 and stamp_max_import_size caps imported PNG sides at 4096 */
	stamp_min_size = 1;
	stamp_max_editable_size = 512;
	stamp_max_import_size = 4096;

	/* stamp_max_import_bytes caps PNG input at 2097152 bytes, or 2 MiB, and stamp_max_import_pixels
	caps its total canvas at 4194304 source pixels */
	stamp_max_import_bytes = 2097152;
	stamp_max_import_pixels = 4194304;

	/* stamp_max_editable_pixels limits PNG-to-editor decoding to 65536 source pixels, while
	stamp_max_size aliases the editable per-side limit for canvas controls */
	stamp_max_editable_pixels = 65536;
	stamp_max_size = stamp_max_editable_size;

	/* settings_file is the shared client INI. browser_index_section/count_key locate browser stamp
	installations and their numeric count */
	settings_file = "client_settings.ini";
	browser_index_section = "browser_stamps";
	browser_index_count_key = "count";

	/* browser_storage_prefix marks manager-created PNG filenames in browser storage */
	browser_storage_prefix = "browser_stamp_";

	/* stamp_folder_name identifies permanent native installations and stamp_temp_folder_name
	identifies intermediate PNG output */
	stamp_folder_name = "stamps";
	stamp_temp_folder_name = "stamp_temp";

	/* stamp_config_file_name and stamp_png_file_name are the fixed metadata and image filenames inside
	each native package */
	stamp_config_file_name = "stamp_config.ini";
	stamp_png_file_name = "stamp.png";

	/* builtin_folder_name identifies bundled stamps, builtin_manifest_file_name names their INI, and
	builtin_manifest_section/order_section locate readable names and preferred order */
	builtin_folder_name = "Stamps";
	builtin_manifest_file_name = "stamp_manifest.ini";
	builtin_manifest_section = "names";
	builtin_order_section = "order";

	/* custom_prefix and builtin_prefix distinguish installation identity from bundled image identity */
	custom_prefix = "custom:";
	builtin_prefix = "builtin:";

	/* transparency_settings_section identifies persisted sprite-editor checker and single-background
	preferences */
	transparency_settings_section = "sprite_editor_transparency_background";

	/* Low-alpha PNG noise should stay invisible when a stamp is decoded into editable pixels.
	Placement still uses the original PNG payload when one exists */
	/* stamp_png_alpha_cutoff treats alpha-byte values up to 2 as transparent in decoded editable data
	while preserving original PNG placement bytes */
	stamp_png_alpha_cutoff = 2;

	/* entries starts empty until discovery. selected_key starts empty, scanned tracks first discovery,
	library_tab starts all and library_tab_keys fixes category order */
	entries = [];
	selected_key = "";
	scanned = false;
	library_tab = "all";
	library_tab_keys = ["all", "builtin", "custom"];

	/* library_scroll starts at row zero. library_modal and its key/label start empty until a size,
	rename or delete dialog opens */
	library_scroll = 0;
	library_modal = "";
	library_modal_key = "";
	library_modal_label = "";

	/* library_size_w_text/h_text start at the 32-pixel canvas defaults and library_size_focus starts
	without a text owner */
	library_size_w_text = "32";
	library_size_h_text = "32";
	library_size_focus = "";

	/* browser_import_pending starts false until asynchronous PNG selection begins */
	browser_import_pending = false;

	/* The placement cache starts empty with no selected/source identity, zero output dimensions,
	smooth filtering disabled and no encoded copy. It retains only the latest prepared size variant */
	placement_cache_key = "";
	placement_cache_source = "";
	placement_cache_w = 0;
	placement_cache_h = 0;
	placement_cache_smooth = false;
	placement_cache_base64 = "";

	/* panel_anchor_left/top/w/h are GUI toolbar bounds used to position the library below its owner,
	initially 16/16/520/180 */
	panel_anchor_left = 16;
	panel_anchor_top = 16;
	panel_anchor_w = 520;
	panel_anchor_h = 180;

	/* panel_hover starts empty and panel_close_requested starts false until a close interaction is
	handed to the toolbar owner */
	panel_hover = "";
	panel_close_requested = false;

	/* editor_hover starts empty and editor_hover_col/row start at source cell zero until pointer input
	resolves a canvas position */
	editor_hover = "";
	editor_hover_col = 0;
	editor_hover_row = 0;

	/* editor_open starts false and editor starts noone until a pixel canvas is created. editor_surface
	starts unallocated and editor_surface_dirty starts true so its first image must be rendered */
	editor_open = false;
	editor = noone;
	editor_surface = noone;
	editor_surface_dirty = true;

	/* editor_source_key/label start empty and editor_existing_custom false until editing records a
	source whose custom installation can be overwritten */
	editor_source_key = "";
	editor_source_label = "";
	editor_existing_custom = false;

	/* editor_tool starts Pen. editor_size_w/h_text start at 32 and editor_size_focus starts without
	numeric text ownership */
	editor_tool = PIXEL_EDITOR_TOOL_PEN;
	editor_size_w_text = "32";
	editor_size_h_text = "32";
	editor_size_focus = "";

	/* editor_view_col/row start at the first source cell and editor_zoom_percent starts 100 */
	editor_view_col = 0;
	editor_view_row = 0;
	editor_zoom_percent = 100;

	/* editor_zoom_min/max bound enlargement to 8 through 800 percent and editor_zoom_levels lists the
	intentional steps used by zoom controls and initial fitting */
	editor_zoom_min = 8;
	editor_zoom_max = 800;
	editor_zoom_levels = [8, 16, 32, 64, 100, 200, 300, 400, 800];

	/* transparency_modal_open starts false and transparency_focus empty. transparency_draft_mode
	starts block until draft background settings are resolved */
	transparency_modal_open = false;
	transparency_focus = "";
	transparency_draft_mode = "block";

	/* transparency_draft_color_1 and color_2 start with light/darker checker RGB bytes, single_color
	starts darker grey, and transparency_draft_block_size_text starts two source cells per checker
	block */
	transparency_draft_color_1 = { r: 214, g: 214, b: 218 };
	transparency_draft_color_2 = { r: 164, g: 166, b: 172 };
	transparency_draft_single_color = { r: 164, g: 166, b: 172 };
	transparency_draft_block_size_text = "2";

	/* current_red/green/blue start with the yellow tool colour in 0 to 255 byte channels */
	current_red = 255;
	current_green = 220;
	current_blue = 95;

	/* current_hue/saturation/value start with its HSV component bytes, using 0 to 255 for each
	component */
	current_hue = 36;
	current_saturation = 160;
	current_value = 255;

	/* colour_sync_pending starts false until editor colour should reach the toolbar and
	editor_colour_slider_active starts without drag ownership */
	colour_sync_pending = false;
	editor_colour_slider_active = "";

	/* editor_hsv_surface_hue/saturation/value start noone and their keys empty until manager-owned
	gradient caches are allocated and rendered */
	editor_hsv_surface_hue = noone;
	editor_hsv_surface_saturation = noone;
	editor_hsv_surface_value = noone;
	editor_hsv_key_hue = "";
	editor_hsv_key_saturation = "";
	editor_hsv_key_value = "";

	/* editor_colour_swatches stores seven authored RGB byte presets in r/g/b structs for palette
	drawing and colour selection */
	editor_colour_swatches =
	[
		{ r: 255, g: 255, b: 255 },
		{ r: 255, g: 220, b: 95 },
		{ r: 244, g: 84, b: 84 },
		{ r: 94, g: 215, b: 122 },
		{ r: 82, g: 162, b: 255 },
		{ r: 196, g: 116, b: 255 },
		{ r: 34, g: 34, b: 38 }
	];

	/* status_text starts empty, status_color white and status_until zero until a transient message
	expires on the millisecond clock */
	status_text = "";
	status_color = c_white;
	status_until = 0;

	/* lazy_stamp_load_frame starts -1 before any clock key is visited. lazy_stamp_loads_this_frame
	starts zero, while lazy_stamp_loads_per_frame_browser and lazy_stamp_loads_per_frame_desktop
	allow one and three ordinary preview loads respectively under each shared millisecond key */
	lazy_stamp_load_frame = -1;
	lazy_stamp_loads_this_frame = 0;
	lazy_stamp_loads_per_frame_browser = 1;
	lazy_stamp_loads_per_frame_desktop = 3;

	#region /* Stamp Colour State */
	/// @description Convert a numeric channel to an integer byte, truncating before clamping
	/// @param {Real} raw_value Channel value to convert
	/// @returns {Real} Integer in the inclusive range 0 to 255
	clamp_byte = function(raw_value)
	{
		return clamp(floor(real(raw_value)), 0, 255);
	}

	/// @description Set the active RGB channels and recompute HSV without requesting toolbar synchronization
	/// @param {Real} raw_red Red channel, truncated and clamped to a byte
	/// @param {Real} raw_green Green channel, truncated and clamped to a byte
	/// @param {Real} raw_blue Blue channel, truncated and clamped to a byte
	/// @returns {Bool} Always true after updating colour state
	set_current_colour = function(raw_red, raw_green, raw_blue)
	{
		current_red = clamp_byte(raw_red);
		current_green = clamp_byte(raw_green);
		current_blue = clamp_byte(raw_blue);
		set_hsv_from_rgb(current_red, current_green, current_blue);
		return true;
	}

	/// @description Convert RGB into the editor's byte-scaled hue, saturation, and value channels
	/// @param {Real} raw_red Red channel, clamped to 0 to 255
	/// @param {Real} raw_green Green channel, clamped to 0 to 255
	/// @param {Real} raw_blue Blue channel, clamped to 0 to 255
	/// @returns {Bool} Always true after updating HSV state
	set_hsv_from_rgb = function(raw_red, raw_green, raw_blue)
	{
		/* rgb_red/green/blue normalize clamped byte inputs to zero through one.
		max_channel/min_channel locate extrema, channel_delta measures chroma and hue_degrees starts
		zero for achromatic colours */
		var rgb_red = clamp(real(raw_red), 0, 255) / 255;
		var rgb_green = clamp(real(raw_green), 0, 255) / 255;
		var rgb_blue = clamp(real(raw_blue), 0, 255) / 255;
		var max_channel = max(rgb_red, max(rgb_green, rgb_blue));
		var min_channel = min(rgb_red, min(rgb_green, rgb_blue));
		var channel_delta = max_channel - min_channel;
		var hue_degrees = 0;

		/* Nonzero chroma permits calculating hue from the channel with greatest intensity, while
		grey/black keeps the zero hue fallback */
		if (channel_delta > 0)
		{
			/* A red maximum derives hue from the green/blue difference */
			if (max_channel == rgb_red)
			{
				hue_degrees = 60 * ((rgb_green - rgb_blue) / channel_delta);
			}

			/* A green maximum derives hue from the blue/red difference plus its sector offset */
			else if (max_channel == rgb_green)
			{
				hue_degrees = 60 * (((rgb_blue - rgb_red) / channel_delta) + 2);
			}

			/* A blue maximum uses the remaining red/green difference and sector offset */
			else
			{
				hue_degrees = 60 * (((rgb_red - rgb_green) / channel_delta) + 4);
			}
		}

		/* A negative hue wraps forward by one 360-degree turn */
		if (hue_degrees < 0)
		{
			hue_degrees += 360;
		}

		/* A full-turn hue wraps back into the zero-through-less-than-360 degree range */
		if (hue_degrees >= 360)
		{
			hue_degrees -= 360;
		}

		current_hue = clamp(round(hue_degrees / 360 * 255), 0, 255);

		/* Black has no saturation denominator and uses zero. Other colours scale chroma relative to
		their brightest channel into a byte */
		current_saturation = max_channel <= 0 ? 0 : clamp(round(channel_delta / max_channel * 255), 0, 255);
		current_value = clamp(round(max_channel * 255), 0, 255);
		return true;
	}

	/// @description Convert byte-scaled HSV to a new RGB struct without changing the active colour
	/// @param {Real} raw_hue Hue in the range 0 to 255, with the upper endpoint wrapping to red
	/// @param {Real} raw_saturation Saturation in the range 0 to 255
	/// @param {Real} raw_value Brightness in the range 0 to 255
	/// @returns {Struct} Newly allocated r, g, and b integer byte values
	hsv_to_rgb_struct = function(raw_hue, raw_saturation, raw_value)
	{
		/* hue_degrees converts the byte hue component to a full 360-degree colour wheel */
		var hue_degrees = clamp(real(raw_hue), 0, 255) / 255 * 360;

		/* The endpoint at 360 degrees wraps to zero so red remains in the first sector */
		if (hue_degrees >= 360)
		{
			hue_degrees = 0;
		}

		/* saturation_amount/value_amount normalize their byte components, chroma measures colour
		intensity, section/sector locate its 60-degree hue region and section_mod2/mixed_channel
		interpolate its secondary channel */
		var saturation_amount = clamp(real(raw_saturation), 0, 255) / 255;
		var value_amount = clamp(real(raw_value), 0, 255) / 255;
		var chroma = value_amount * saturation_amount;
		var section = hue_degrees / 60;
		var sector = floor(section);
		var section_mod2 = section - floor(section / 2) * 2;
		var mixed_channel = chroma * (1 - abs(section_mod2 - 1));

		/* channel_red/green/blue start zero before the hue sector distributes chroma and its mixed
		secondary intensity */
		var channel_red = 0;
		var channel_green = 0;
		var channel_blue = 0;

		/* The six hue sectors choose which RGB channels receive primary chroma and secondary
		interpolation */
		switch (sector)
		{
			/* Red-to-yellow hues use full red, mixed green and no blue */
			case 0:
				channel_red = chroma; channel_green = mixed_channel; channel_blue = 0;
				break;

			/* Yellow-to-green hues use mixed red, full green and no blue */
			case 1:
				channel_red = mixed_channel; channel_green = chroma; channel_blue = 0;
				break;

			/* Green-to-cyan hues use no red, full green and mixed blue */
			case 2:
				channel_red = 0; channel_green = chroma; channel_blue = mixed_channel;
				break;

			/* Cyan-to-blue hues use no red, mixed green and full blue */
			case 3:
				channel_red = 0; channel_green = mixed_channel; channel_blue = chroma;
				break;

			/* Blue-to-magenta hues use mixed red, no green and full blue */
			case 4:
				channel_red = mixed_channel; channel_green = 0; channel_blue = chroma;
				break;

			/* The final magenta-to-red sector uses full red, no green and mixed blue */
			default:
				channel_red = chroma; channel_green = 0; channel_blue = mixed_channel;
				break;
		}

		/* match_value adds the common achromatic brightness offset before returning rounded r/g/b byte
		channels */
		var match_value = value_amount - chroma;
		return
		{
			r: clamp(round((channel_red + match_value) * 255), 0, 255),
			g: clamp(round((channel_green + match_value) * 255), 0, 255),
			b: clamp(round((channel_blue + match_value) * 255), 0, 255)
		};
	}

	/// @description Convert byte-scaled HSV into a GameMaker colour value
	/// @param {Real} raw_hue Hue in the range 0 to 255
	/// @param {Real} raw_saturation Saturation in the range 0 to 255
	/// @param {Real} raw_value Brightness in the range 0 to 255
	/// @returns {Colour} Packed RGB colour
	hsv_to_colour = function(raw_hue, raw_saturation, raw_value)
	{
		/* New RGB byte record converted from the supplied HSV values before making a GameMaker draw
		color */
		var rgb = hsv_to_rgb_struct(raw_hue, raw_saturation, raw_value);
		return make_color_rgb(rgb.r, rgb.g, rgb.b);
	}

	/// @description Recompute active RGB from the current HSV channels and request one toolbar colour synchronization
	/// @returns {Bool} Always true after updating RGB and the pending flag
	set_current_colour_from_hsv = function()
	{
		/* rgb contains the converted r/g/b byte values for the current HSV components before toolbar
		synchronization is requested */
		var rgb = hsv_to_rgb_struct(current_hue, current_saturation, current_value);
		current_red = rgb.r;
		current_green = rgb.g;
		current_blue = rgb.b;
		colour_sync_pending = true;
		return true;
	}

	/// @description Set editor RGB and HSV together and mark the colour for synchronization with the drawing toolbar
	/// @param {Real} raw_red Red channel, truncated and clamped to a byte
	/// @param {Real} raw_green Green channel, truncated and clamped to a byte
	/// @param {Real} raw_blue Blue channel, truncated and clamped to a byte
	/// @returns {Bool} Always true after updating colour state
	set_editor_colour_rgb = function(raw_red, raw_green, raw_blue)
	{
		set_current_colour(raw_red, raw_green, raw_blue);
		colour_sync_pending = true;
		return true;
	}

	/// @description Consume the editor's pending colour change once for the drawing toolbar
	/// @returns {Struct} r, g, and b byte values, or noone when no colour change is pending
	consume_colour_sync = function()
	{
		/* Without a pending colour change, there is no new editor RGB update for the drawing toolbar
		to consume */
		if (!colour_sync_pending)
		{
			return noone;
		}

		colour_sync_pending = false;

		/* The returned r/g/b struct copies current byte channels and consumes the pending flag once */
		return
		{
			r: current_red,
			g: current_green,
			b: current_blue
		};
	}

	/// @description Consume and clear a pending library-close request exactly once
	/// @returns {Bool} Whether a close request was pending
	consume_library_close_request = function()
	{
		/* Without a pending library-close request, the toolbar owner has no close action to consume */
		if (!panel_close_requested)
		{
			return false;
		}

		panel_close_requested = false;
		return true;
	}
	#endregion /* Stamp Colour State END */

	#region /* Editor Surfaces and Input Ownership */
	/// @description Release the manager-owned editor preview surface and mark it for reconstruction
	/// @returns {Bool} Always true after resetting the cache
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

	/// @description Mark the editor's cached preview for rebuilding after pixel changes
	/// @returns {Bool} Always true after setting the dirty flag
	mark_editor_surface_dirty = function()
	{
		editor_surface_dirty = true;
		return true;
	}

	/// @description Rebuild the manager-owned editor pixel surface when its size or content changes
	/// @returns {Id.Surface} Borrowed cached surface, or noone when the editor is closed or no surface could be created
	ensure_editor_surface = function()
	{
		/* Only an open editor with a valid pixel model can own a cached editor image */
		if (!editor_open || !is_struct(editor))
		{
			return noone;
		}

		/* surface_w/h are positive whole source-grid dimensions used by the manager-owned editor
		surface */
		var surface_w = max(1, floor(real(editor.grid_w)));
		var surface_h = max(1, floor(real(editor.grid_h)));

		/* A live surface with outdated dimensions is freed and marked dirty so the current canvas can
		get a correctly sized image */
		if (surface_exists(editor_surface)
		&& (surface_get_width(editor_surface) != surface_w || surface_get_height(editor_surface) != surface_h))
		{
			surface_free(editor_surface);
			editor_surface = noone;
			editor_surface_dirty = true;
		}

		/* A missing cached editor surface is allocated to the current source dimensions and starts
		dirty */
		if (!surface_exists(editor_surface))
		{
			editor_surface = surface_create(surface_w, surface_h);
			editor_surface_dirty = true;
		}

		/* Draw the pixel model into a live dirty surface once, then clear its dirty flag for later
		preview reuse */
		if (surface_exists(editor_surface) && editor_surface_dirty)
		{
			editor.draw_to_surface(editor_surface);
			editor_surface_dirty = false;
		}

		return editor_surface;
	}

	/// @description Release all manager-owned HSV gradient surfaces and clear their cache keys
	/// @returns {Bool} Always true after clearing the three caches
	free_editor_hsv_surfaces = function()
	{
		/* Free the manager-owned hue gradient only when its surface remains live */
		if (surface_exists(editor_hsv_surface_hue))
		{
			surface_free(editor_hsv_surface_hue);
		}

		/* Free the manager-owned saturation gradient only when its surface remains live */
		if (surface_exists(editor_hsv_surface_saturation))
		{
			surface_free(editor_hsv_surface_saturation);
		}

		/* Free the manager-owned value gradient only when its surface remains live */
		if (surface_exists(editor_hsv_surface_value))
		{
			surface_free(editor_hsv_surface_value);
		}
		editor_hsv_surface_hue = noone;
		editor_hsv_surface_saturation = noone;
		editor_hsv_surface_value = noone;
		editor_hsv_key_hue = "";
		editor_hsv_key_saturation = "";
		editor_hsv_key_value = "";
		return true;
	}

	/// @description Report whether the stamp editor or a library modal owns input before player-card hit testing
	/// @returns {Bool} Whether player-card interaction must be deferred
	blocks_player_cards = function()
	{
		/* An open editor or library dialog owns modal interaction and blocks player-card hit testing */
		return editor_open || library_modal != "";
	}

	/// @description Reserve keyboard input while the pixel editor or a library modal is open
	/// @returns {Bool} Whether the stamp interface owns keyboard input
	captures_keyboard = function()
	{
		/* An open editor or library dialog captures keyboard input before ordinary game shortcuts */
		return editor_open || library_modal != "";
	}

	/// @description Select browser-compatible storage for browser runtimes and GX.games
	/// @returns {Bool} Whether native filesystem paths must be avoided
	uses_browser_storage = function()
	{
		/* Browser and GX.games builds require browser storage for custom stamp persistence */
		return os_browser != browser_not_a_browser || os_type == os_gxgames;
	}

	/// @description Set the library panel's position and dimensions in GUI pixels
	/// @param {Real} anchor_left Left edge in GUI pixels
	/// @param {Real} anchor_top Top edge in GUI pixels
	/// @param {Real} anchor_w Panel width in GUI pixels
	/// @param {Real} anchor_h Panel height in GUI pixels
	/// @returns {Bool} Always true after storing the anchor
	set_anchor = function(anchor_left, anchor_top, anchor_w, anchor_h)
	{
		panel_anchor_left = real(anchor_left);
		panel_anchor_top = real(anchor_top);
		panel_anchor_w = real(anchor_w);
		panel_anchor_h = real(anchor_h);
		return true;
	}

	/// @description Test an inclusive GUI rectangle so its edges count as part of the control
	/// @param {Real} gui_x Horizontal pointer coordinate in GUI pixels
	/// @param {Real} gui_y Vertical pointer coordinate in GUI pixels
	/// @param {Real} rect_left Left boundary in GUI pixels
	/// @param {Real} rect_top Top boundary in GUI pixels
	/// @param {Real} rect_right Right boundary in GUI pixels
	/// @param {Real} rect_bottom Bottom boundary in GUI pixels
	/// @returns {Bool} Whether the point lies inside or on the rectangle
	point_in_rect = function(gui_x, gui_y, rect_left, rect_top, rect_right, rect_bottom)
	{
		/* A point inside all inclusive GUI rectangle edges is a hit shared by control drawing and
		input */
		return gui_x >= rect_left && gui_x <= rect_right && gui_y >= rect_top && gui_y <= rect_bottom;
	}
	#endregion /* Editor Surfaces and Input Ownership END */

	#region /* Stamp Paths and Limits */
	/// @description Choose the path separator accepted by the current storage platform
	/// @returns {String} Backslash for native Windows, otherwise slash
	path_separator = function()
	{
		/* Browser paths always use forward slashes. Native Windows paths use backslashes and other
		native platforms use forward slashes */
		return uses_browser_storage() ? "/" : (os_type == os_windows ? "\\" : "/");
	}

	/// @description Normalize path separators for browser storage or the current native platform
	/// @param {String} raw_path Path to normalize
	/// @returns {String} Path with platform-appropriate separators
	normalize_path = function(raw_path)
	{
		/* path_text converts input to a string before platform separator normalization */
		var path_text = string(raw_path);

		/* Browser builds and non-Windows native platforms normalize backslashes to forward slashes */
		if (uses_browser_storage() || os_type != os_windows)
		{
			return string_replace_all(path_text, "\\", "/");
		}

		/* Native Windows normalizes forward slashes to backslashes */
		if (os_type == os_windows)
		{
			return string_replace_all(path_text, "/", "\\");
		}

		return path_text;
	}

	/// @description Join two path components without duplicating their boundary separator
	/// @param {String} base_path Parent path, which may be empty
	/// @param {String} leaf_path Child path, which may be empty
	/// @returns {String} Combined normalized path
	path_join = function(base_path, leaf_path)
	{
		/* left_text and right_text normalize the parent and child paths before joining them */
		var left_text = normalize_path(base_path);
		var right_text = normalize_path(leaf_path);

		/* An empty parent returns the child path directly */
		if (left_text == "")
		{
			return right_text;
		}

		/* An empty child returns the parent without a trailing separator */
		if (right_text == "")
		{
			return left_text;
		}

		/* final_char is the parent's last character used to detect an existing path separator */
		var final_char = string_char_at(left_text, string_length(left_text));

		/* A parent already ending in a slash or backslash joins directly without adding another
		separator */
		if (final_char == "/" || final_char == "\\")
		{
			return left_text + right_text;
		}

		return left_text + path_separator() + right_text;
	}

	/// @description Extract the final component after normalizing both separator styles
	/// @param {String} raw_path Path or filename
	/// @returns {String} Final path component
	path_leaf = function(raw_path)
	{
		/* path_text is the source path and separator_pos starts zero until a directory boundary is
		found */
		var path_text = string(raw_path);
		var separator_pos = 0;

		/* char_pos visits all one-based path characters to retain the final separator position */
		for (var char_pos = 1; char_pos <= string_length(path_text); char_pos++)
		{
			/* current_char is the path character tested for either supported separator form */
			var current_char = string_char_at(path_text, char_pos);

			/* A slash or backslash records the latest directory boundary */
			if (current_char == "/" || current_char == "\\")
			{
				separator_pos = char_pos;
			}
		}

		/* With no directory separator, the input is already a leaf. Otherwise return text after the
		last separator */
		return separator_pos <= 0 ? path_text : string_copy(path_text, separator_pos + 1, string_length(path_text) - separator_pos);
	}

	/// @description Build a lowercase storage key from letters, digits, underscores, and hyphens
	/// @param {String} raw_name Display name to sanitize
	/// @returns {String} Safe key, using stamp when no allowed characters remain
	safe_folder_key = function(raw_name)
	{
		/* raw_text is the lowercase trimmed requested basename, result starts empty and last_separator
		tracks a newly added replacement underscore */
		var raw_text = string_lower(string_trim(string(raw_name)));
		var result = "";
		var last_separator = false;

		/* char_pos visits all one-based source characters to build one safe installation name */
		for (var char_pos = 1; char_pos <= string_length(raw_text); char_pos++)
		{
			/* current_char is the current candidate name character */
			var current_char = string_char_at(raw_text, char_pos);

			/* Letters, digits, underscores and hyphens are copied directly to the safe basename */
			if (scr_player_character_is_key_char_allowed(current_char))
			{
				result += current_char;
				last_separator = false;
			}

			/* Unsupported characters add one separating underscore only after existing text and
			without consecutive replacement separators */
			else if (!last_separator && result != "")
			{
				result += "_";
				last_separator = true;
			}
		}

		/* Trim trailing underscores while they remain so the final basename does not end with
		replacement punctuation */
		while (string_length(result) > 0 && string_char_at(result, string_length(result)) == "_")
		{
			result = string_delete(result, string_length(result), 1);
		}

		/* An input yielding no usable basename falls back to stamp */
		return result == "" ? "stamp" : result;
	}

	/// @description Format a truncated integer with leading zeroes until it reaches the requested width
	/// @param {Real} raw_value Number to format
	/// @param {Real} digits Minimum character count
	/// @returns {String} Padded numeric text
	pad_number = function(raw_value, digits)
	{
		/* result is the requested whole number converted to decimal text before zero padding */
		var result = string(floor(real(raw_value)));

		/* Prepend zeros while its text is shorter than the requested digit count */
		while (string_length(result) < digits)
		{
			result = "0" + result;
		}

		return result;
	}

	/// @description Build a local timestamp suitable for package names and metadata
	/// @returns {String} Timestamp in YYYY-MM-DD_HH-MM-SS format
	stamp_timestamp = function()
	{
		/* now_value captures one calendar timestamp so its year through seconds belong to the same
		formatted instant */
		var now_value = date_current_datetime();
		return pad_number(date_get_year(now_value), 4)
			+ "-" + pad_number(date_get_month(now_value), 2)
			+ "-" + pad_number(date_get_day(now_value), 2)
			+ "_" + pad_number(date_get_hour(now_value), 2)
			+ "-" + pad_number(date_get_minute(now_value), 2)
			+ "-" + pad_number(date_get_second(now_value), 2);
	}

	/// @description Attempt to create a missing native directory and confirm it exists
	/// @param {String} folder_path Directory path to create
	/// @returns {Bool} Whether the directory exists after the attempt
	ensure_folder = function(folder_path)
	{
		try
		{
			/* Create the requested folder only when it does not already exist */
			if (!directory_exists(folder_path))
			{
				directory_create(folder_path);
			}

			/* Report success only when the folder is visible after preparation */
			return directory_exists(folder_path);
		}
		catch(e)
		{
			debug_error("Could not create stamp folder " + string(folder_path) + ": " + string(e.message));
			return false;
		}
	}

	/// @description Resolve the custom-stamp directory beneath game_save_id
	/// @returns {String} Normalized custom-stamp root path
	stamp_root_path = function()
	{
		return normalize_path(path_join(game_save_id, stamp_folder_name));
	}

	/// @description Resolve stamp_temp under game_save_id, falling back to temp_directory when the save root is empty
	/// @returns {String} Normalized temporary-stamp directory path
	temp_root_path = function()
	{
		/* root_text uses game_save_id when available, otherwise temp_directory for intermediate stamp
		PNGs */
		var root_text = string(game_save_id) == "" ? string(temp_directory) : string(game_save_id);
		return normalize_path(path_join(root_text, stamp_temp_folder_name));
	}

	/// @description Prefix PNG base64 with the data URL header expected by browser image APIs
	/// @param {String} base64_text Complete PNG encoded as base64
	/// @returns {String} PNG data URL
	stamp_data_url = function(base64_text)
	{
		return "data:image/png;base64," + string(base64_text);
	}

	/// @description Display a library status message for 4,200 milliseconds
	/// @param {String} message Text to display
	/// @param {Colour} colour Message colour, defaulting to c_white when omitted
	/// @returns {Bool} Always true after updating the status fields
	set_status = function(message, colour = c_white)
	{
		/* Set the message and colour and expire it 4200 milliseconds after the current runtime clock */
		status_text = string(message);
		status_color = colour;
		status_until = current_time + 4200;
		return true;
	}

	/// @description Resolve the connected client's assigned username, then its requested username
	/// @returns {String} Author name, or an empty string when neither is available
	local_author_name = function()
	{
		/* client borrows current connection state for local stamp-author attribution */
		var client = scr_get_client();

		/* Structured client state can provide an assigned or requested display identity */
		if (is_struct(client))
		{
			/* Prefer a nonempty server-assigned username as the saved author name */
			if (variable_struct_exists(client, "assigned_username")
			&& string_trim(string(client.assigned_username)) != "")
			{
				return string(client.assigned_username);
			}

			/* Before assignment, a nonempty requested username supplies the saved author name */
			if (variable_struct_exists(client, "requested_username")
			&& string_trim(string(client.requested_username)) != "")
			{
				return string(client.requested_username);
			}
		}

		return "";
	}

	/// @description Check the integer canvas dimensions against the editable per-side limits
	/// @param {Real} candidate_w Proposed width in pixels
	/// @param {Real} candidate_h Proposed height in pixels
	/// @returns {Bool} Whether both truncated sides are within the editable range
	stamp_size_is_supported = function(candidate_w, candidate_h)
	{
		/* check_w and check_h convert requested source dimensions to whole pixels before editor-side
		validation */
		var check_w = floor(real(candidate_w));
		var check_h = floor(real(candidate_h));

		/* Both dimensions must lie inside the one-through-512 editable per-side limits. This test
		alone does not apply the separate total decode-pixel limit */
		return check_w >= stamp_min_size
			&& check_w <= stamp_max_size
			&& check_h >= stamp_min_size
			&& check_h <= stamp_max_size;
	}

	/// @description Format the editable per-side limits for status messages
	/// @returns {String} Editable pixel range with a px suffix
	stamp_size_range_text = function()
	{
		return string(stamp_min_size) + "-" + string(stamp_max_size) + " px";
	}

	/// @description Check imported dimensions against per-side and total-pixel limits
	/// @param {Real} candidate_w Proposed image width in pixels
	/// @param {Real} candidate_h Proposed image height in pixels
	/// @returns {Bool} Whether the truncated dimensions satisfy all import dimension limits
	stamp_import_size_is_supported = function(candidate_w, candidate_h)
	{
		/* check_w/h convert import source dimensions to whole pixels */
		var check_w = floor(real(candidate_w));
		var check_h = floor(real(candidate_h));

		/* Import requires one-through-4096 pixels per side and no more than 4194304 pixels across the
		whole canvas */
		return check_w >= stamp_min_size
			&& check_w <= stamp_max_import_size
			&& check_h >= stamp_min_size
			&& check_h <= stamp_max_import_size
			&& check_w * check_h <= stamp_max_import_pixels;
	}

	/// @description Describe the authored PNG file-size, per-side, and total-pixel limits
	/// @returns {String} User-facing import-limit explanation
	stamp_import_limits_text = function()
	{
		return "Stamp PNG limit: 2 MiB, 4096 px per side and 4,194,304 pixels total.";
	}

	/// @description Format the import per-side limits for status messages
	/// @returns {String} Import pixel range with a px suffix
	stamp_import_size_range_text = function()
	{
		return string(stamp_min_size) + "-" + string(stamp_max_import_size) + " px";
	}

	/// @description Truncate and clamp a canvas dimension to the editable per-side range
	/// @param {Real} raw_value Requested dimension in pixels
	/// @returns {Real} Supported integer canvas dimension
	clamp_stamp_dimension = function(raw_value)
	{
		return clamp(floor(real(raw_value)), stamp_min_size, stamp_max_size);
	}

	/// @description Truncate and clamp an image dimension to the import per-side range
	/// @param {Real} raw_value Requested dimension in pixels
	/// @returns {Real} Supported integer image dimension
	clamp_stamp_import_dimension = function(raw_value)
	{
		return clamp(floor(real(raw_value)), stamp_min_size, stamp_max_import_size);
	}

	/// @description Count pixels using truncated, nonnegative dimensions
	/// @param {Real} candidate_w Width in pixels
	/// @param {Real} candidate_h Height in pixels
	/// @returns {Real} Product of the nonnegative integer dimensions
	stamp_pixel_count = function(candidate_w, candidate_h)
	{
		return max(0, floor(real(candidate_w))) * max(0, floor(real(candidate_h)));
	}

	/// @description Check whether dimensions fit both editable per-side limits and the editable total-pixel budget
	/// @param {Real} candidate_w Image width in pixels
	/// @param {Real} candidate_h Image height in pixels
	/// @returns {Bool} Whether automatic editable RGBA decoding is permitted
	stamp_can_decode_to_editable_pixels = function(candidate_w, candidate_h)
	{
		/* PNG-to-editor decoding requires editable per-side dimensions and at most 65536 total source
		pixels */
		return stamp_size_is_supported(candidate_w, candidate_h)
			&& stamp_pixel_count(candidate_w, candidate_h) <= stamp_max_editable_pixels;
	}

	/// @description Retain ASCII decimal digits from an input-field string
	/// @param {String} raw_text Text to filter
	/// @returns {String} Digits in their original order
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

	/// @description Parse digit-only canvas-size text and clamp it to editable limits
	/// @param {String} raw_text Input-field text
	/// @param {Real} fallback_value Dimension to use when no digits remain
	/// @returns {Real} Supported integer dimension
	stamp_dimension_from_text = function(raw_text, fallback_value)
	{
		/* clean_text retains only digits from the dimension draft */
		var clean_text = digits_only(raw_text);

		/* An empty numeric draft uses the current/default fallback dimension rather than parsing empty
		text */
		if (clean_text == "")
		{
			return clamp_stamp_dimension(fallback_value);
		}

		return clamp_stamp_dimension(real(clean_text));
	}
	#endregion /* Stamp Paths and Limits END */

	#region /* Transparency Background Settings */
	/// @description Allocate independent RGB byte fields for colour settings
	/// @param {Real} raw_red Red channel, truncated and clamped to a byte
	/// @param {Real} raw_green Green channel, truncated and clamped to a byte
	/// @param {Real} raw_blue Blue channel, truncated and clamped to a byte
	/// @returns {Struct} New r, g, and b colour fields
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

	/// @description Copy RGB settings without sharing the source struct
	/// @param {Struct} source_colour Source colour, or a non-struct value to use the default grey
	/// @returns {Struct} Independent clamped RGB copy, defaulting to 164, 166, 172
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

	/// @description Create fresh checkerboard settings with two grey colours and a two-pixel block size
	/// @returns {Struct} Independent transparency background settings
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

	/// @description Truncate and clamp transparency checkerboard blocks to 2 to 999 pixels
	/// @param {Real} raw_value Requested checkerboard block size in pixels
	/// @returns {Real} Supported integer block size
	clamp_transparency_block_size = function(raw_value)
	{
		return clamp(floor(real(raw_value)), 2, 999);
	}

	/// @description Parse digit-only checkerboard-size text with a fallback for an empty field
	/// @param {String} raw_text Input-field text
	/// @param {Real} fallback_value Size to use when no digits remain
	/// @returns {Real} Block size clamped to 2 to 999 pixels
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

	/// @description Restore the shared sprite-editor transparency settings once. Missing INI fields retain authored defaults
	/// @returns {Struct} Shared global transparency background settings
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

	/// @description Obtain the shared transparency settings, restoring them from storage on first access
	/// @returns {Struct} Borrowed shared background-settings struct
	transparency_settings = function()
	{
		return ensure_transparency_settings();
	}

	/// @description Write the shared transparency mode, RGB channels, and block size to client_settings.ini
	/// @returns {Bool} Always true after issuing the INI writes
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

	/// @description Report that the transparency-settings opener is currently disabled
	/// @returns {Bool} Always false without opening the modal
	begin_transparency_modal = function()
	{
		return false;
	}

	/// @description Close the transparency settings modal and clear its input focus
	/// @returns {Bool} Always true after resetting modal state
	cancel_transparency_modal = function()
	{
		transparency_modal_open = false;
		transparency_focus = "";
		keyboard_string = "";
		return true;
	}

	/// @description Copy the draft transparency settings into shared state, persist them, close the modal, and display confirmation
	/// @returns {Bool} Always true after applying the draft and issuing persistence
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
	#endregion /* Transparency Background Settings END */

	#region /* Stamp Entries and Cached Images */
	/// @description Format dimensions as width x height with each integer side at least one pixel
	/// @param {Real} candidate_w Width in pixels
	/// @param {Real} candidate_h Height in pixels
	/// @returns {String} Compact dimension label
	stamp_size_label = function(candidate_w, candidate_h)
	{
		return string(max(1, floor(real(candidate_w)))) + "x" + string(max(1, floor(real(candidate_h))));
	}

	/// @description Read an entry's clamped image width or use the manager's default canvas width
	/// @param {Struct} entry Stamp library entry
	/// @returns {Real} Integer source width in pixels
	entry_stamp_w = function(entry)
	{
		/* Use a stored width clamped to import limits when present, otherwise the 32-pixel default
		width */
		return variable_struct_exists(entry, "stamp_w") ? clamp_stamp_import_dimension(entry.stamp_w) : stamp_w;
	}

	/// @description Read an entry's clamped image height or use the manager's default canvas height
	/// @param {Struct} entry Stamp library entry
	/// @returns {Real} Integer source height in pixels
	entry_stamp_h = function(entry)
	{
		/* Use a stored height clamped to import limits when present, otherwise the 32-pixel default
		height */
		return variable_struct_exists(entry, "stamp_h") ? clamp_stamp_import_dimension(entry.stamp_h) : stamp_h;
	}

	/// @description Keep nonempty status text visible until its millisecond deadline passes
	/// @returns {Bool} Whether the current status should be drawn
	status_is_visible = function()
	{
		/* A nonempty status remains visible through its millisecond expiration time */
		return status_text != "" && current_time <= status_until;
	}

	/// @description Convert a clamped nibble to one uppercase hexadecimal character
	/// @param {Real} value Nibble value, truncated and clamped to 0 to 15
	/// @returns {String} One character from 0123456789ABCDEF
	hex_digit = function(value)
	{
		return string_char_at("0123456789ABCDEF", clamp(floor(real(value)), 0, 15) + 1);
	}

	/// @description Encode a clamped byte as two uppercase hexadecimal characters
	/// @param {Real} raw_value Byte value, truncated and clamped to 0 to 255
	/// @returns {String} Two-character hexadecimal byte
	byte_to_hex = function(raw_value)
	{
		/* byte_value is the clamped whole 0 to 255 channel encoded as two hexadecimal digits */
		var byte_value = clamp_byte(raw_value);
		return hex_digit(floor(byte_value / 16)) + hex_digit(byte_value mod 16);
	}

	/// @description Decode one hexadecimal character, treating an unrecognized character as zero
	/// @param {String} raw_char Character to decode
	/// @returns {Real} Nibble value from 0 to 15
	hex_value = function(raw_char)
	{
		/* One-based position in the hex alphabet becomes the numeric nibble value, with
		missing/invalid characters falling back to zero */
		var digit_index = string_pos(string_upper(string(raw_char)), "0123456789ABCDEF");
		return max(0, digit_index - 1);
	}

	/// @description Decode an ASCII hexadecimal character at a one-based string offset, returning zero for other characters
	/// @param {String} hex_text Hexadecimal source string
	/// @param {Real} offset One-based character position
	/// @returns {Real} Nibble value from 0 to 15
	hex_nibble_at = function(hex_text, offset)
	{
		/* codepoint is the character at the requested one-based hex offset */
		var codepoint = string_ord_at(hex_text, offset);

		/* ASCII digits 0 through 9 convert by subtracting their zero codepoint */
		if (codepoint >= 48 && codepoint <= 57)
		{
			return codepoint - 48;
		}

		/* Uppercase A through F convert to hexadecimal values 10 through 15 */
		if (codepoint >= 65 && codepoint <= 70)
		{
			return codepoint - 55;
		}

		/* Lowercase a through f convert to the same hexadecimal values */
		if (codepoint >= 97 && codepoint <= 102)
		{
			return codepoint - 87;
		}

		return 0;
	}

	/// @description Decode two adjacent hexadecimal characters into a byte
	/// @param {String} hex_text Hexadecimal source string
	/// @param {Real} offset One-based position of the high nibble
	/// @returns {Real} Byte value from 0 to 255
	hex_pair_to_byte = function(hex_text, offset)
	{
		return hex_nibble_at(hex_text, offset) * 16 + hex_nibble_at(hex_text, offset + 1);
	}

	/// @description Decode one pixel from row-major RRGGBBAA text using a zero-based pixel index
	/// @param {String} hex_text Eight hexadecimal characters per source pixel
	/// @param {Real} pixel_index Zero-based row-major pixel index
	/// @returns {Struct} r, g, b, and a byte channels
	hex_pixel_at = function(hex_text, pixel_index)
	{
		/* hex_offset converts this zero-based row-major pixel index to the one-based start of its
		eight RGBA hex characters */
		var hex_offset = pixel_index * 8 + 1;

		/* Return the source pixel's r/g/b/a byte values from consecutive two-character hexadecimal
		pairs */
		return
		{
			r: hex_pair_to_byte(hex_text, hex_offset),
			g: hex_pair_to_byte(hex_text, hex_offset + 2),
			b: hex_pair_to_byte(hex_text, hex_offset + 4),
			a: hex_pair_to_byte(hex_text, hex_offset + 6)
		};
	}

	/// @description Allocate library metadata with independent empty preview caches, preserving the supplied pixel and PNG strings
	/// @param {String} key_text Stable prefixed library key
	/// @param {String} label_text Display label, falling back to Stamp when blank
	/// @param {String} source_text Entry origin, normally builtin or custom
	/// @param {Bool} editable_value Initial editable metadata flag
	/// @param {String} hex_text Row-major RRGGBBAA pixel text, or empty for PNG-only entries
	/// @param {String} base64_text Complete PNG base64, defaulting to empty when omitted
	/// @param {String} package_path_text Native custom-package path, defaulting to empty when omitted
	/// @param {String} storage_file_text PNG storage filename or path, defaulting to empty when omitted
	/// @param {String} created_text Creation timestamp, defaulting to empty when omitted
	/// @param {String} updated_text Last-update timestamp, defaulting to empty when omitted
	/// @param {Real} entry_w Source width in pixels, defaulting to stamp_w when omitted and clamped to import limits
	/// @param {Real} entry_h Source height in pixels, defaulting to stamp_h when omitted and clamped to import limits
	/// @returns {Struct} New stamp metadata with no allocated preview surface or bounds
	make_entry = function(key_text, label_text, source_text, editable_value, hex_text, base64_text = "", package_path_text = "", storage_file_text = "", created_text = "", updated_text = "", entry_w = stamp_w, entry_h = stamp_h)
	{
		/* safe_entry_w and safe_entry_h clamp the source dimensions to import per-side limits */
		var safe_entry_w = clamp_stamp_import_dimension(entry_w);
		var safe_entry_h = clamp_stamp_import_dimension(entry_h);

		/* The record retains key, display label, source category, editable state and dimensions, RGBA
		hex and original PNG data, native/browser destinations and created/updated timestamps.
		preview_surface and preview_bounds start unresolved until their manager-owned caches are
		created */
		return
		{
			key: string(key_text),

			/* A blank display label falls back to Stamp while a nonblank supplied label is retained */
			label: string_trim(string(label_text)) == "" ? "Stamp" : string(label_text),
			source: string(source_text),
			editable: editable_value,
			stamp_w: safe_entry_w,
			stamp_h: safe_entry_h,
			hex: string(hex_text),
			base64: string(base64_text),
			package_path: string(package_path_text),
			storage_file: string(storage_file_text),
			created_at: string(created_text),
			updated_at: string(updated_text),
			preview_surface: noone,
			preview_bounds: noone
		};
	}

	/// @description Register bundled PNG identity without loading its bytes or pixels
	/// @param {String} file_name Bundled PNG filename used to form a stable builtin key
	/// @param {String} display_name User-facing library label
	/// @param {String} root_path Preferred bundled root, defaulting to empty when omitted
	/// @param {String} file_path Known native PNG path, defaulting to empty when omitted
	/// @returns {Struct} Unloaded builtin entry with lazy-load bookkeeping
	make_builtin_placeholder_entry = function(file_name, display_name, root_path = "", file_path = "")
	{
		/* clean_file_name keeps the source leaf, entry_key builds its stable bundled identity and
		entry creates a metadata-only placeholder before loading any PNG */
		var clean_file_name = path_leaf(file_name);
		var entry_key = builtin_prefix + safe_folder_key(strip_png_extension(clean_file_name));
		var entry = make_entry(entry_key, display_name, "builtin", false, "", "", "", "", "", "", stamp_w, stamp_h);

		/* builtin_file_name/root/file_path retain the source filename and search destinations.
		builtin_png_loaded/failed start false until a lazy read resolves them */
		entry.builtin_file_name = clean_file_name;
		entry.builtin_root = string(root_path);
		entry.builtin_file_path = string(file_path);
		entry.builtin_png_loaded = false;
		entry.builtin_png_failed = false;
		return entry;
	}

	/// @description Register a browser custom PNG without loading its stored bytes
	/// @param {String} local_key_text Stable custom-prefixed library key
	/// @param {String} label_text User-facing library label
	/// @param {String} storage_file_text Browser PNG storage filename
	/// @param {String} created_text Creation timestamp, defaulting to empty when omitted
	/// @param {String} updated_text Update timestamp, defaulting to empty when omitted
	/// @param {Real} entry_w Source width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} entry_h Source height in pixels, defaulting to stamp_h when omitted
	/// @returns {Struct} Unloaded custom entry with lazy-load bookkeeping
	make_custom_placeholder_entry = function(local_key_text, label_text, storage_file_text, created_text = "", updated_text = "", entry_w = stamp_w, entry_h = stamp_h)
	{
		/* entry creates a custom browser placeholder with saved identity, file path, timestamps and
		provisional dimensions */
		var entry = make_entry(local_key_text, label_text, "custom", false, "", "", "", storage_file_text, created_text, updated_text, entry_w, entry_h);

		/* custom_png_loaded and custom_png_failed start false until a lazy stored-image read resolves
		them */
		entry.custom_png_loaded = false;
		entry.custom_png_failed = false;
		return entry;
	}

	/// @description Release every manager-owned entry preview surface and sprite before rebuilding the library
	/// @returns {Bool} Always true after clearing entry preview caches
	delete_cached_surfaces = function()
	{
		/* entry_index visits all library records to release manager-owned preview surfaces and sprites
		before their entries are rebuilt */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			/* stamp_entry is the record currently relinquishing its cached image resources */
			var stamp_entry = entries[entry_index];

			/* Free a live preview_surface only when that optional handle exists, then clear it in the
			record */
			if (variable_struct_exists(stamp_entry, "preview_surface")
			&& surface_exists(stamp_entry.preview_surface))
			{
				surface_free(stamp_entry.preview_surface);
				stamp_entry.preview_surface = noone;
				entries[entry_index] = stamp_entry;
			}

			/* Delete a live preview_sprite only when its optional handle exists, then clear it in the
			record */
			if (variable_struct_exists(stamp_entry, "preview_sprite")
			&& sprite_exists(stamp_entry.preview_sprite))
			{
				sprite_delete(stamp_entry.preview_sprite);
				stamp_entry.preview_sprite = noone;
				entries[entry_index] = stamp_entry;
			}
		}

		return true;
	}

	/// @description Decode supported RGBA hex text into a newly allocated surface
	/// @param {String} hex_text Row-major RRGGBBAA pixel text
	/// @param {Real} surface_w Width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} surface_h Height in pixels, defaulting to stamp_h when omitted
	/// @returns {Id.Surface} New surface owned by the caller, or noone for insufficient RGBA text or decoding failure
	hex_to_surface = function(hex_text, surface_w = stamp_w, surface_h = stamp_h)
	{
		/* safe_surface_w/h are positive whole RGBA-grid dimensions for surface creation */
		var safe_surface_w = max(1, floor(real(surface_w)));
		var safe_surface_h = max(1, floor(real(surface_h)));

		/* Insufficient hex for that source grid cannot produce a complete preview surface */
		if (!hex_is_valid_size(hex_text, safe_surface_w, safe_surface_h))
		{
			return noone;
		}

		return RgbaPng.rgba_hex_to_surface(safe_surface_w, safe_surface_h, hex_text);
	}

	/// @description Obtain or build the manager-owned preview surface for an entry's editable pixels
	/// @param {Real} entry_index Zero-based index in entries
	/// @returns {Id.Surface} Borrowed cached surface, or noone when the entry or decoding is unavailable
	ensure_entry_surface = function(entry_index)
	{
		/* An index outside the zero-based library array has no preview surface owner */
		if (entry_index < 0 || entry_index >= array_length(entries))
		{
			return noone;
		}

		/* stamp_entry is the record whose manager-owned RGBA surface is requested */
		var stamp_entry = entries[entry_index];

		/* Return an already live cached surface instead of allocating another preview resource */
		if (variable_struct_exists(stamp_entry, "preview_surface")
		&& surface_exists(stamp_entry.preview_surface))
		{
			return stamp_entry.preview_surface;
		}

		/* stamp_surface is a new RGBA preview allocation, retained in its entry and borrowed by
		callers */
		var stamp_surface = hex_to_surface(stamp_entry.hex, entry_stamp_w(stamp_entry), entry_stamp_h(stamp_entry));
		stamp_entry.preview_surface = stamp_surface;
		entries[entry_index] = stamp_entry;
		return stamp_surface;
	}

	/// @description Cache inclusive nontransparent pixel bounds, using the full image extent when no editable hex is available
	/// @param {Real} entry_index Zero-based index in entries
	/// @returns {Struct} Borrowed cached ok, min_col, min_row, max_col, and max_row, or invalid bounds for an invalid entry
	entry_visible_bounds = function(entry_index)
	{
		/* An invalid entry index returns empty inclusive bounds with ok false and maximum coordinates
		at -1 */
		if (entry_index < 0 || entry_index >= array_length(entries))
		{
			return { ok: false, min_col: 0, min_row: 0, max_col: -1, max_row: -1 };
		}

		/* entry is the record whose visible-pixel crop is requested */
		var entry = entries[entry_index];

		/* Reuse cached bounds when they were already computed for this image */
		if (variable_struct_exists(entry, "preview_bounds")
		&& is_struct(entry.preview_bounds))
		{
			return entry.preview_bounds;
		}

		/* source_w and source_h are the entry's whole source-pixel dimensions */
		var source_w = entry_stamp_w(entry);
		var source_h = entry_stamp_h(entry);

		/* Without complete decoded pixels, use the full PNG rectangle rather than hiding an image-only
		stamp */
		if (!hex_is_valid_size(entry.hex, source_w, source_h))
		{
			/* image_bounds covers columns/rows from zero through dimension minus one, with ok enabled
			when both source dimensions are positive */
			var image_bounds =
			{
				ok: source_w > 0 && source_h > 0,
				min_col: 0,
				min_row: 0,
				max_col: source_w - 1,
				max_row: source_h - 1
			};
			entry.preview_bounds = image_bounds;
			entries[entry_index] = entry;
			return image_bounds;
		}

		/* min_col and min_row start beyond the grid and max_col/max_row start -1 so a fully
		transparent image retains empty bounds */
		var min_col = source_w;
		var min_row = source_h;
		var max_col = -1;
		var max_row = -1;

		/* pixel_row visits all zero-based source rows when locating nontransparent pixels */
		for (var pixel_row = 0; pixel_row < source_h; pixel_row++)
		{
			/* pixel_col visits every source column of this row to expand the visible crop */
			for (var pixel_col = 0; pixel_col < source_w; pixel_col++)
			{
				/* pixel_data is this row-major source pixel's RGBA byte struct */
				var pixel_data = hex_pixel_at(entry.hex, pixel_row * source_w + pixel_col);

				/* Any pixel with nonzero alpha expands the inclusive visible bounds */
				if (pixel_data.a > 0)
				{
					min_col = min(min_col, pixel_col);
					min_row = min(min_row, pixel_row);
					max_col = max(max_col, pixel_col);
					max_row = max(max_row, pixel_row);
				}
			}
		}

		/* bounds stores inclusive source-cell edges and marks ok only when at least one visible pixel
		produced a nonempty crop */
		var bounds =
		{
			ok: max_col >= min_col && max_row >= min_row,
			min_col: min_col,
			min_row: min_row,
			max_col: max_col,
			max_row: max_row
		};
		entry.preview_bounds = bounds;
		entries[entry_index] = entry;
		return bounds;
	}

	/// @description Obtain or allocate a manager-owned PNG preview sprite without transferring ownership to the caller
	/// @param {Real} entry_index Zero-based index in entries
	/// @returns {Id.Sprite} Borrowed sprite, which may still be loading in a browser, or noone when unavailable
	ensure_entry_sprite = function(entry_index)
	{
		/* An invalid library index cannot own a preview sprite */
		if (entry_index < 0 || entry_index >= array_length(entries))
		{
			return noone;
		}

		/* stamp_entry is the selected record providing original PNG data and its cached sprite */
		var stamp_entry = entries[entry_index];

		/* Reuse a live cached original-PNG sprite rather than creating a second resource owner */
		if (variable_struct_exists(stamp_entry, "preview_sprite")
		&& sprite_exists(stamp_entry.preview_sprite))
		{
			return stamp_entry.preview_sprite;
		}

		/* base64_text starts from the optional retained PNG or empty when that payload has not yet
		loaded or been encoded */
		var base64_text = variable_struct_exists(stamp_entry, "base64") ? string(stamp_entry.base64) : "";

		/* A missing original PNG requires lazy loading or encoding from complete editable pixels */
		if (string_trim(base64_text) == "")
		{
			/* A successful lazy PNG load refreshes the record and provides its original bytes */
			if (ensure_entry_png_payload(entry_index, false, false))
			{
				stamp_entry = entries[entry_index];
				base64_text = string(stamp_entry.base64);
			}

			/* If the original PNG cannot load, complete editable RGBA data may still produce the
			preview */
			else
			{
				/* Without complete editable pixels there is no fallback image to encode */
				if (!entry_has_editable_pixels(stamp_entry))
				{
					return noone;
				}

				/* encode_result converts the available RGBA canvas to PNG base64 for preview loading */
				var encode_result = hex_to_png_base64(stamp_entry.hex, entry_stamp_w(stamp_entry), entry_stamp_h(stamp_entry));

				/* Failed fallback encoding leaves no preview image to create */
				if (!encode_result.ok)
				{
					return noone;
				}

				base64_text = encode_result.base64;
				stamp_entry.base64 = base64_text;
			}
		}

		/* sprite_source starts as a PNG data URL, which is retained for browser sprite loading */
		var sprite_source = stamp_data_url(base64_text);

		/* Native builds prefer existing image files to avoid the asynchronous data-URL loading
		placeholder */
		if (!uses_browser_storage())
		{
			/* Data URLs load asynchronously. Desktop stamps already have a local
			file, so use it instead of drawing a temporary 1x1 loading sprite */
			/* local_file_path starts empty until the entry's source type resolves a readable native
			image */
			var local_file_path = "";

			/* Bundled records use their discovered file path or fall back to their bundled root and
			filename */
			if (stamp_entry.source == "builtin")
			{
				/* Use a remembered builtin_file_path when available, otherwise leave the path empty
				for fallback lookup */
				local_file_path = variable_struct_exists(stamp_entry, "builtin_file_path")
					? string(stamp_entry.builtin_file_path)
					: "";

				/* An absent or missing direct path requires reconstructing a bundled candidate path */
				if (local_file_path == "" || !file_exists(local_file_path))
				{
					/* local_root uses the record's discovered bundled root when present, otherwise the
					normal bundled stamp folder */
					var local_root = variable_struct_exists(stamp_entry, "builtin_root")
						? string(stamp_entry.builtin_root)
						: builtin_stamp_folder_path();
					local_file_path = path_join(local_root, string(stamp_entry.builtin_file_name));
				}
			}

			/* Custom native records can use a recorded storage_file path when that field exists */
			else if (stamp_entry.source == "custom"
			&& variable_struct_exists(stamp_entry, "storage_file"))
			{
				local_file_path = string(stamp_entry.storage_file);
			}

			/* A nonempty existing local file replaces the data URL as the synchronous native sprite
			source */
			if (local_file_path != "" && file_exists(local_file_path))
			{
				sprite_source = local_file_path;
			}
		}

		/* stamp_sprite starts without an owned sprite. A successful sprite_add allocation is retained
		by this record and later released during library cache deletion */
		var stamp_sprite = noone;
		try
		{
			stamp_sprite = sprite_add(sprite_source, 1, false, false, 0, 0);
		}
		catch(e)
		{
			debug_error("Could not create stamp preview sprite: " + string(e.message));
			return noone;
		}

		/* A failed sprite allocation returns no preview handle rather than caching an invalid resource */
		if (!sprite_exists(stamp_sprite))
		{
			return noone;
		}

		stamp_entry.preview_sprite = stamp_sprite;
		entries[entry_index] = stamp_entry;
		return stamp_sprite;
	}

	/// @description Find the first exact library key match
	/// @param {String} key_text Stable entry key to locate
	/// @returns {Real} Zero-based entries index, or noone when absent
	entry_index_by_key = function(key_text)
	{
		/* entry_index visits all zero-based library records for an exact stable-key match */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			/* The first matching entry key returns its underlying library index */
			if (entries[entry_index].key == key_text)
			{
				return entry_index;
			}
		}

		return noone;
	}

	/// @description Resolve the selected key, choosing and storing the first entry when the key is no longer present
	/// @returns {Real} Zero-based selected entries index, or noone for an empty library
	selected_entry_index = function()
	{
		/* found_index locates the current selected identity */
		var found_index = entry_index_by_key(selected_key);

		/* A still-valid selection preserves its existing library index */
		if (found_index != noone)
		{
			return found_index;
		}

		/* An empty library has no fallback entry to select */
		if (array_length(entries) <= 0)
		{
			return noone;
		}

		selected_key = entries[0].key;
		return 0;
	}

	/// @description Resolve the selected library entry, repairing missing selection through the first entry
	/// @returns {Struct} Borrowed selected entry, or noone for an empty library
	selected_entry = function()
	{
		/* found_index resolves selection and may choose the library's first record as fallback */
		var found_index = selected_entry_index();

		/* Return noone when the library is empty, otherwise borrow the selected entry */
		return found_index == noone ? noone : entries[found_index];
	}

	/// @description Determine whether selection can resolve to a library entry, repairing the selected key when needed
	/// @returns {Bool} Whether the library has a selected stamp
	has_selected_stamp = function()
	{
		refresh();

		/* A nonempty refreshed selection means the library has a stamp available */
		return selected_entry_index() != noone;
	}

	/// @description Return selected source dimensions and editing flags. Loading dimensions can be deferred by the lazy-load budget
	/// @returns {Struct} stamp_w, stamp_h, image_only, editable_pixels, label, and source, or noone when empty
	selected_size = function()
	{
		refresh();

		/* entry_index resolves the selected image whose source dimensions are requested */
		var entry_index = selected_entry_index();

		/* An empty library has no selected dimensions to report */
		if (entry_index == noone)
		{
			return noone;
		}

		/* A deferred PNG may load its true dimensions within the ordinary lazy-load budget, without
		decoding editable pixels */
		if (entry_can_lazy_load_png(entries[entry_index]))
		{
			/* Selection only needs the PNG dimensions. Pixel decoding is reserved
			for Edit instead of changing the preview as a selection side effect */
			ensure_entry_png_payload(entry_index, false, false);
		}

		/* entry retains the record after any dimension-loading attempt */
		var entry = entries[entry_index];

		/* Return source width/height, whether its dimensions exceed editable decoding limits, whether
		complete editable data exists, and its label/source category */
		return
		{
			stamp_w: entry_stamp_w(entry),
			stamp_h: entry_stamp_h(entry),
			image_only: !stamp_can_decode_to_editable_pixels(entry_stamp_w(entry), entry_stamp_h(entry)),
			editable_pixels: entry_has_editable_pixels(entry),
			label: entry.label,
			source: entry.source
		};
	}

	/// @description Check that RGBA text is long enough for the clamped dimensions without validating individual hex characters
	/// @param {String} hex_text Pixel text to measure
	/// @param {Real} expected_w Width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} expected_h Height in pixels, defaulting to stamp_h when omitted
	/// @returns {Bool} Whether at least eight characters exist per expected pixel
	hex_is_valid_size = function(hex_text, expected_w = stamp_w, expected_h = stamp_h)
	{
		/* safe_expected_w/h are positive whole source-grid dimensions used to calculate required RGBA
		characters */
		var safe_expected_w = max(1, floor(real(expected_w)));
		var safe_expected_h = max(1, floor(real(expected_h)));

		/* Enough hex means at least eight characters per source pixel. This length test does not
		validate that every character is hexadecimal */
		return string_length(string(hex_text)) >= safe_expected_w * safe_expected_h * 8;
	}

	/// @description Check an entry's dimensions and RGBA text against editable per-side requirements
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether supported dimensions and sufficient hex text exist, independent of the automatic-decoding total-pixel budget
	entry_has_editable_pixels = function(entry)
	{
		/* Only a structured entry can expose editable pixels and dimensions */
		if (!is_struct(entry))
		{
			return false;
		}

		/* check_w/h resolve source dimensions using entry fields or default canvas size */
		var check_w = entry_stamp_w(entry);
		var check_h = entry_stamp_h(entry);

		/* Editable data requires supported per-side dimensions and enough RGBA hex for the complete
		grid */
		return stamp_size_is_supported(check_w, check_h)
			&& hex_is_valid_size(entry.hex, check_w, check_h);
	}

	/// @description Check for a nonempty PNG base64 field on an entry
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether PNG base64 text is already available
	entry_has_png_payload = function(entry)
	{
		/* A PNG payload is present only in a structured entry with a nonempty base64 field */
		return is_struct(entry)
			&& variable_struct_exists(entry, "base64")
			&& string_trim(string(entry.base64)) != "";
	}

	/// @description Identify unloaded builtin or custom entries with a filename and no recorded load failure
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether lazy storage loading remains possible
	entry_can_lazy_load_png = function(entry)
	{
		/* Lazy loading applies only to structured entries with a source category and no existing PNG
		payload */
		if (!is_struct(entry)
		|| !variable_struct_exists(entry, "source")
		|| entry_has_png_payload(entry))
		{
			return false;
		}

		/* Bundled sources resolve from their filename metadata */
		if (entry.source == "builtin")
		{
			/* A nonempty bundled filename with no recorded failure remains eligible for a lazy PNG
			load */
			return variable_struct_exists(entry, "builtin_file_name")
				&& string_trim(string(entry.builtin_file_name)) != ""
				&& (!variable_struct_exists(entry, "builtin_png_failed") || !entry.builtin_png_failed);
		}

		/* Custom sources resolve from their saved storage filename */
		if (entry.source == "custom")
		{
			/* A nonempty custom storage path with no recorded failure remains eligible for lazy
			loading */
			return variable_struct_exists(entry, "storage_file")
				&& string_trim(string(entry.storage_file)) != ""
				&& (!variable_struct_exists(entry, "custom_png_failed") || !entry.custom_png_failed);
		}

		return false;
	}

	/// @description Accept either existing PNG bytes or an entry that can still load them from storage
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether a PNG payload is available or potentially loadable
	entry_can_provide_png_payload = function(entry)
	{
		/* A retained PNG or eligible deferred image can provide placement/export PNG data */
		return entry_has_png_payload(entry) || entry_can_lazy_load_png(entry);
	}

	/// @description Identify loaded PNG entries lacking editable pixels whose dimensions fit the automatic-decoding budget
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether editable-pixel decoding can be attempted
	entry_can_decode_loaded_pixels = function(entry)
	{
		/* Pixel decoding is pending only for structured entries with PNG data, no complete editable
		pixels and dimensions within decode limits */
		return is_struct(entry)
			&& entry_has_png_payload(entry)
			&& !entry_has_editable_pixels(entry)
			&& stamp_can_decode_to_editable_pixels(entry_stamp_w(entry), entry_stamp_h(entry));
	}

	/// @description Decide whether an entry still needs storage loading or eligible editable-pixel decoding
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether either lazy operation remains available
	entry_should_load_or_decode_pixels = function(entry)
	{
		/* An image needs loading or decoding when either its deferred source or undecoded eligible PNG
		remains available */
		return entry_can_lazy_load_png(entry) || entry_can_decode_loaded_pixels(entry);
	}

	/// @description Reserve a lazy-load slot for the current millisecond clock key, or bypass accounting for explicit actions
	/// @param {Bool} force_load Whether to bypass the budget, defaulting to false when omitted
	/// @returns {Bool} Whether loading is permitted, with ordinary successful reservations incrementing the counter
	take_lazy_stamp_load_budget = function(force_load = false)
	{
		/* Explicit force_load actions bypass preview throttling without incrementing the ordinary
		lazy-load counter */
		if (force_load)
		{
			return true;
		}

		/* frame_key is the floored current_time millisecond value used to group this manager's
		preview-load requests */
		var frame_key = floor(real(current_time));

		/* A changed clock key resets the preview-load count before applying this interval's platform
		limit */
		if (lazy_stamp_load_frame != frame_key)
		{
			lazy_stamp_load_frame = frame_key;
			lazy_stamp_loads_this_frame = 0;
		}

		/* max_loads chooses one ordinary preview load in browser storage and three on native builds */
		var max_loads = uses_browser_storage() ? lazy_stamp_loads_per_frame_browser : lazy_stamp_loads_per_frame_desktop;

		/* Once the interval's load count reaches its limit, defer another preview load until a later
		clock key */
		if (lazy_stamp_loads_this_frame >= max_loads)
		{
			return false;
		}

		lazy_stamp_loads_this_frame++;
		return true;
	}

	/// @description Create an independent pixel-editor model and load row-major RGBA text into it
	/// @param {String} hex_text Row-major RRGGBBAA pixel text
	/// @param {Real} editor_w Canvas width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} editor_h Canvas height in pixels, defaulting to stamp_h when omitted
	/// @returns {Struct} New pixel-editor model
	editor_from_hex = function(hex_text, editor_w = stamp_w, editor_h = stamp_h)
	{
		/* pixel_editor is a newly owned pixel-model struct populated from the requested hex canvas and
		returned to its caller */
		var pixel_editor = new scr_pixel_editor(editor_w, editor_h);
		pixel_editor.load_hex_string(hex_text);
		return pixel_editor;
	}

	/// @description Encode a newly created transparent canvas as RGBA hex text
	/// @param {Real} blank_w Canvas width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} blank_h Canvas height in pixels, defaulting to stamp_h when omitted
	/// @returns {String} Row-major RRGGBBAA text for transparent pixels
	blank_hex = function(blank_w = stamp_w, blank_h = stamp_h)
	{
		/* pixel_editor is a temporary blank model used only to encode a transparent RGBA canvas as hex */
		var pixel_editor = new scr_pixel_editor(blank_w, blank_h);
		return pixel_editor.to_hex_string();
	}
	#endregion /* Stamp Entries and Cached Images END */

	#region /* Built-in Stamp Discovery */
	/// @description Resolve the bundled Stamps root, preferring a native datafiles folder when present
	/// @returns {String} Bundled stamp root path
	builtin_stamp_folder_path = function()
	{
		/* Browser builds refer directly to the bundled Stamps path without native directory inspection */
		if (uses_browser_storage())
		{
			return builtin_folder_name;
		}

		/* source_folder_path is the native datafiles/Stamps candidate */
		var source_folder_path = path_join("datafiles", builtin_folder_name);

		/* An existing native directory or its bundled manifest selects the datafiles path */
		if (directory_exists(source_folder_path)
		|| file_exists(path_join(source_folder_path, builtin_manifest_file_name)))
		{
			return source_folder_path;
		}

		return builtin_folder_name;
	}

	/// @description Resolve stamp_manifest.ini beneath the bundled stamp root
	/// @returns {String} Bundled manifest path
	builtin_stamp_manifest_path = function()
	{
		return path_join(builtin_stamp_folder_path(), builtin_manifest_file_name);
	}

	/// @description Derive a readable label from a PNG filename when the manifest supplies no label
	/// @param {String} file_name Bundled PNG filename
	/// @returns {String} Derived label, falling back to Stamp when empty
	builtin_fallback_label = function(file_name)
	{
		/* label_text starts from the PNG filename stem before separators are converted to readable
		spaces */
		var label_text = strip_png_extension(file_name);
		label_text = string_replace_all(label_text, "_", " ");
		label_text = string_replace_all(label_text, "-", " ");
		label_text = string_trim(label_text);

		/* A cleaned empty filename stem uses Stamp as the readable fallback */
		return label_text == "" ? "Stamp" : label_text;
	}

	/// @description Shorten a library label to fit a thumbnail while retaining an ellipsis for truncated text
	/// @param {String} label_text Full display label
	/// @returns {String} Thumbnail label
	library_short_label = function(label_text)
	{
		/* short_label is the full source label and max_chars limits the compact thumbnail caption to
		ten characters */
		var short_label = string(label_text);
		var max_chars = 10;

		/* Labels already within the caption limit are returned unchanged */
		if (string_length(short_label) <= max_chars)
		{
			return short_label;
		}

		return string_copy(short_label, 1, max_chars - 3) + "...";
	}

	/// @description Read a native bundled PNG and append its bytes with editable pixels when eligible decoding succeeds
	/// @param {String} file_path Native PNG path
	/// @param {String} file_name Filename used for the builtin key
	/// @param {String} display_name User-facing label
	/// @returns {Bool} Whether the PNG passed read validation and an entry was appended
	add_builtin_png_entry = function(file_path, file_name, display_name)
	{
		/* png_result validates and encodes this bundled source image without retaining a buffer */
		var png_result = read_png_base64(file_path);

		/* A failed source image is skipped instead of adding an unusable loaded record */
		if (!png_result.ok)
		{
			debug_error("Skipping built-in stamp " + string(file_name) + ": " + png_result.message);
			return false;
		}

		/* hex_text starts empty until eligible source dimensions permit editable decoding */
		var hex_text = "";

		/* Only PNGs within editable decoding limits attempt conversion to hex pixels */
		if (stamp_can_decode_to_editable_pixels(png_result.png_w, png_result.png_h))
		{
			hex_text = base64_to_hex(png_result.base64, png_result.png_w, png_result.png_h);

			/* Incomplete decoded pixels leave this valid original PNG registered as image-only */
			if (!hex_is_valid_size(hex_text, png_result.png_w, png_result.png_h))
			{
				debug_error("Loading built-in stamp " + string(file_name) + " as image-only: could not decode pixels.");
				hex_text = "";
			}
		}

		/* entry_key builds the stable builtin identity from the filename stem */
		var entry_key = builtin_prefix + safe_folder_key(strip_png_extension(file_name));
		entries[array_length(entries)] = make_entry(entry_key, display_name, "builtin", false, hex_text, png_result.base64, "", "", "", "", png_result.png_w, png_result.png_h);
		return true;
	}

	/// @description Check whether a normalized bundled-file candidate was already collected
	/// @param {Array} candidates Candidate path strings
	/// @param {String} candidate_path Normalized path to compare
	/// @returns {Bool} Whether a matching path exists, respecting case-sensitive native platforms
	path_candidate_exists = function(candidates, candidate_path)
	{
		/* candidate_text normalizes the requested path and case_sensitive_paths is true on Linux/macOS
		to preserve distinct filesystem names */
		var candidate_text = normalize_path(candidate_path);
		var case_sensitive_paths = os_type == os_linux || os_type == os_macosx;

		/* Other platforms compare lowercase candidates to avoid duplicate paths differing only in case */
		if (!case_sensitive_paths)
		{
			candidate_text = string_lower(candidate_text);
		}

		/* candidate_index visits all prior search paths for a normalized duplicate */
		for (var candidate_index = 0; candidate_index < array_length(candidates); candidate_index++)
		{
			/* existing_text normalizes the candidate currently being compared */
			var existing_text = normalize_path(candidates[candidate_index]);

			/* Case-insensitive platforms also lowercase existing paths before comparison */
			if (!case_sensitive_paths)
			{
				existing_text = string_lower(existing_text);
			}

			/* An equal normalized path is already in the candidate list and needs no repeat load
			attempt */
			if (existing_text == candidate_text)
			{
				return true;
			}
		}

		return false;
	}

	/// @description Try distinct preferred and bundled paths until one yields valid PNG data
	/// @param {String} file_name Bundled PNG filename
	/// @param {String} preferred_root Preferred root directory, defaulting to empty when omitted
	/// @returns {Struct} ok, base64, png_w, png_h, byte_size, and message with attempted-path diagnostics on failure
	read_builtin_png_by_name = function(file_name, preferred_root = "")
	{
		/* result starts failed with no encoded PNG, zero dimensions/bytes and a provisional
		bundled-image diagnostic */
		var result =
		{
			ok: false,
			base64: "",
			png_w: 0,
			png_h: 0,
			byte_size: 0,
			message: "Could not read bundled stamp PNG."
		};

		/* candidates starts as an empty ordered search list, attempted_paths accumulates diagnostics,
		and clean_file_name strips directory components from the requested image name */
		var candidates = [];
		var attempted_paths = "";
		var clean_file_name = path_leaf(file_name);

		/* A supplied preferred root gets the first load candidate */
		if (string_trim(string(preferred_root)) != "")
		{
			candidates[array_length(candidates)] = path_join(preferred_root, clean_file_name);
		}

		/* Native builds also consider datafiles/Stamps as a packaged source root */
		if (!uses_browser_storage())
		{
			/* source_folder_path is that packaged root and source_candidate joins it with the
			requested leaf filename */
			var source_folder_path = path_join("datafiles", builtin_folder_name);
			var source_candidate = path_join(source_folder_path, clean_file_name);

			/* Append this packaged path only when it is not already among the candidates */
			if (!path_candidate_exists(candidates, source_candidate))
			{
				candidates[array_length(candidates)] = source_candidate;
			}
		}

		/* bundle_candidate is the direct Stamps/filename packaged location */
		var bundle_candidate = path_join(builtin_folder_name, clean_file_name);

		/* Append the direct bundled candidate only when it is distinct from previous paths */
		if (!path_candidate_exists(candidates, bundle_candidate))
		{
			candidates[array_length(candidates)] = bundle_candidate;
		}

		/* Native builds also try the bare filename when it has not already been listed */
		if (!uses_browser_storage()
		&& !path_candidate_exists(candidates, clean_file_name))
		{
			candidates[array_length(candidates)] = clean_file_name;
		}

		/* candidate_index attempts search paths in order until one valid PNG succeeds */
		for (var candidate_index = 0; candidate_index < array_length(candidates); candidate_index++)
		{
			/* attempted_paths separates later paths with commas while leaving the first path
			unprefixed */
			attempted_paths += (attempted_paths == "" ? "" : ", ") + string(candidates[candidate_index]);

			/* candidate_result retains this path's image read and validation outcome */
			var candidate_result = read_png_base64(candidates[candidate_index]);

			/* Return the first successfully inspected original PNG */
			if (candidate_result.ok)
			{
				return candidate_result;
			}

			/* A nonempty path-specific diagnostic replaces the provisional error for the final
			failed-search report */
			if (string_trim(candidate_result.message) != "")
			{
				result.message = candidate_result.message;
			}
		}

		result.message = result.message + " Tried: " + attempted_paths + ".";
		return result;
	}

	/// @description Load a library PNG within the lazy-load budget and optionally attempt editable-pixel decoding
	/// @param {Real} entry_index Index in entries
	/// @param {Bool} decode_pixels Whether to attempt RGBA decoding within editable limits, defaulting to false when omitted
	/// @param {Bool} force_load Whether to bypass the lazy-load budget, defaulting to false when omitted
	/// @returns {Bool} Whether PNG data is available. This does not guarantee editable pixels were decoded
	ensure_entry_png_payload = function(entry_index, decode_pixels = false, force_load = false)
	{
		/* An index outside the zero-based library has no image payload to load */
		if (entry_index < 0 || entry_index >= array_length(entries))
		{
			return false;
		}

		/* entry borrows this record and has_payload detects whether its original PNG is already
		retained */
		var entry = entries[entry_index];
		var has_payload = entry_has_png_payload(entry);

		/* Without retained PNG data, resolve its deferred source and consume load budget before file
		inspection */
		if (!has_payload)
		{
			/* A source ineligible for lazy loading or a depleted ordinary load budget defers this
			request without altering the record */
			if (!entry_can_lazy_load_png(entry)
			|| !take_lazy_stamp_load_budget(force_load))
			{
				return false;
			}

			/* source_label identifies the entry in diagnostics. png_result starts failed with empty
			payload, zero dimensions and a provisional source-read message */
			var source_label = string(entry.label);
			var png_result =
			{
				ok: false,
				base64: "",
				png_w: 0,
				png_h: 0,
				message: "Could not read bundled stamp PNG."
			};

			/* Bundled entries choose a recorded direct path or the ordered bundled path search */
			if (entry.source == "builtin")
			{
				/* file_name is the bundled source leaf and replaces the diagnostic label for the read
				attempt */
				var file_name = string(entry.builtin_file_name);
				source_label = file_name;

				/* direct_path uses the optional remembered bundled file location or empty when not
				recorded */
				var direct_path = variable_struct_exists(entry, "builtin_file_path") ? string(entry.builtin_file_path) : "";

				/* A native existing direct path can be inspected immediately instead of searching
				alternate bundled roots */
				if (!uses_browser_storage()
				&& direct_path != ""
				&& file_exists(direct_path))
				{
					png_result = read_png_base64(direct_path);
				}

				/* Browser sources and unavailable direct paths use the bundled candidate search */
				else
				{
					/* preferred_root uses the record's remembered bundled root when present or empty
					to use ordinary fallback roots */
					var preferred_root = variable_struct_exists(entry, "builtin_root") ? string(entry.builtin_root) : "";
					png_result = read_builtin_png_by_name(file_name, preferred_root);
				}
			}

			/* Custom entries read from their saved storage path */
			else
			{
				/* storage_path uses the optional saved PNG filename or an empty fallback */
				var storage_path = variable_struct_exists(entry, "storage_file") ? string(entry.storage_file) : "";
				source_label = storage_path;
				png_result = read_png_base64(storage_path);
			}

			/* A failed source read records a source-specific failure flag so ordinary previews do not
			repeatedly retry the same unavailable image */
			if (!png_result.ok)
			{
				/* Bundled failures set builtin_png_failed */
				if (entry.source == "builtin")
				{
					entry.builtin_png_failed = true;
				}

				/* Custom failures set custom_png_failed */
				else
				{
					entry.custom_png_failed = true;
				}
				entries[entry_index] = entry;
				debug_error("Skipping stamp " + source_label + ": " + png_result.message);
				return false;
			}

			entry.base64 = png_result.base64;
			entry.stamp_w = png_result.png_w;
			entry.stamp_h = png_result.png_h;

			/* Successful bundled loading marks the PNG available and clears its bundled failure flag */
			if (entry.source == "builtin")
			{
				entry.builtin_png_loaded = true;
				entry.builtin_png_failed = false;
			}

			/* Successful custom loading marks the PNG available and clears its custom failure flag */
			else
			{
				entry.custom_png_loaded = true;
				entry.custom_png_failed = false;
			}
			entry.preview_bounds = noone;
			has_payload = true;
		}

		/* Decode pixels only when requested, missing complete editable data, and source dimensions fit
		decode limits */
		if (decode_pixels
		&& !entry_has_editable_pixels(entry)
		&& stamp_can_decode_to_editable_pixels(entry_stamp_w(entry), entry_stamp_h(entry)))
		{
			/* hex_text retains the decoded RGBA attempt for the entry's actual PNG dimensions */
			var hex_text = base64_to_hex(entry.base64, entry_stamp_w(entry), entry_stamp_h(entry));

			/* Only a complete decoded canvas is stored and marked editable, leaving the original PNG
			untouched on a decode failure */
			if (hex_is_valid_size(hex_text, entry_stamp_w(entry), entry_stamp_h(entry)))
			{
				entry.hex = hex_text;
				entry.editable = true;
				entry.preview_bounds = noone;
			}
		}

		entries[entry_index] = entry;
		return has_payload;
	}

	/// @description Read a bundled PNG through candidate paths and append its bytes with editable pixels when eligible decoding succeeds
	/// @param {String} file_name Bundled PNG filename
	/// @param {String} display_name User-facing label
	/// @param {String} preferred_root Preferred bundled directory, defaulting to empty when omitted
	/// @returns {Bool} Whether a candidate PNG passed read validation and an entry was appended
	add_builtin_png_entry_by_name = function(file_name, display_name, preferred_root = "")
	{
		/* png_result inspects the requested bundled filename through its preferred and fallback paths */
		var png_result = read_builtin_png_by_name(file_name, preferred_root);

		/* An invalid or unavailable source is skipped with its filename diagnostic */
		if (!png_result.ok)
		{
			debug_error("Skipping built-in stamp " + string(file_name) + ": " + png_result.message);
			return false;
		}

		/* hex_text starts empty until a sufficiently small PNG permits editable decoding */
		var hex_text = "";

		/* Only source grids within decoding limits attempt RGBA conversion */
		if (stamp_can_decode_to_editable_pixels(png_result.png_w, png_result.png_h))
		{
			hex_text = base64_to_hex(png_result.base64, png_result.png_w, png_result.png_h);

			/* If decoding yields insufficient pixels, preserve the original PNG as image-only and
			clear partial hex */
			if (!hex_is_valid_size(hex_text, png_result.png_w, png_result.png_h))
			{
				debug_error("Loading built-in stamp " + string(file_name) + " as image-only: could not decode pixels.");
				hex_text = "";
			}
		}

		/* entry_key builds the stable bundled identity from its filename stem */
		var entry_key = builtin_prefix + safe_folder_key(strip_png_extension(file_name));
		entries[array_length(entries)] = make_entry(entry_key, display_name, "builtin", false, hex_text, png_result.base64, "", "", "", "", png_result.png_w, png_result.png_h);
		return true;
	}

	/// @description Discover bundled entries through manifest order and names, then native PNG enumeration when available
	/// @returns {Bool} Whether at least one builtin entry was appended
	add_builtin_entries = function()
	{
		/* root_path and manifest_path locate bundled sources, manifest_exists tests metadata
		availability, root_exists applies native-only directory lookup, and manifest_open starts
		false until the INI opens */
		var root_path = builtin_stamp_folder_path();
		var manifest_path = builtin_stamp_manifest_path();
		var manifest_exists = file_exists(manifest_path);
		var root_exists = uses_browser_storage() ? false : directory_exists(root_path);
		var manifest_open = false;

		/* Open the bundled manifest only when it exists, preserving fallback enumeration if reading
		fails */
		if (manifest_exists)
		{
			try
			{
				ini_open(manifest_path);
				manifest_open = true;
			}
			catch(e)
			{
				debug_error("Could not read built-in stamp manifest " + manifest_path + ": " + string(e.message));
				try { ini_close(); } catch(close_error) {}
			}
		}

		/* builtin_files starts empty and retains discovered file_name/file_path pairs for ordered
		registration */
		var builtin_files = [];

		/* Native bundled directories can enumerate image filenames, while browsers rely on the
		manifest's ordered names */
		if (!uses_browser_storage()
		&& root_exists)
		{
			/* search_mask targets bundled PNG files and found_path is the first current search result */
			var search_mask = path_join(root_path, "*.png");
			var found_path = file_find_first(search_mask, 0);

			/* Continue gathering PNG candidates while filesystem search results remain nonempty */
			while (found_path != "")
			{
				/* file_name is the current result's leaf and file_path initially joins it to the
				bundled root */
				var file_name = path_leaf(found_path);
				var file_path = path_join(root_path, file_name);

				/* A returned existing file path replaces a missing joined path so discovery keeps the
				actual packaged location */
				if (!file_exists(file_path) && file_exists(found_path))
				{
					file_path = found_path;
				}

				/* Each candidate pair retains its leaf filename for identity/label lookup and actual
				path for later loading */
				builtin_files[array_length(builtin_files)] = {
					file_name: file_name,
					file_path: file_path
				};

				found_path = file_find_next();
			}

			file_find_close();
		}

		/* added_count starts zero for registered bundled records and loaded_names starts empty to
		prevent duplicate filename registration */
		var added_count = 0;
		var loaded_names = [];

		/* A successfully opened manifest provides the preferred registration order */
		if (manifest_open)
		{
			/* order_index starts at one because manifest order keys are one-based, and
			empty_order_count starts zero for consecutive missing keys */
			var order_index = 1;
			var empty_order_count = 0;

			/* Inspect at most 512 order slots and stop after 32 consecutive empty keys, bounding
			sparse manifest traversal */
			while (order_index <= 512 && empty_order_count < 32)
			{
				/* order_file_name is the trimmed filename requested at this manifest slot */
				var order_file_name = string_trim(ini_read_string(builtin_order_section, string(order_index), ""));

				/* An empty slot increases the missing-key streak and advances to the next order key */
				if (order_file_name == "")
				{
					empty_order_count++;
					order_index++;
					continue;
				}

				empty_order_count = 0;

				/* ordered_file_index starts unresolved and ordered_lower_name normalizes the manifest
				leaf for matching discovered filenames */
				var ordered_file_index = noone;
				var ordered_lower_name = string_lower(path_leaf(order_file_name));

				/* order_file_index visits all native file candidates to resolve this ordered filename */
				for (var order_file_index = 0; order_file_index < array_length(builtin_files); order_file_index++)
				{
					/* A case-normalized filename match selects the candidate's actual native path */
					if (string_lower(builtin_files[order_file_index].file_name) == ordered_lower_name)
					{
						ordered_file_index = order_file_index;
						break;
					}
				}

				/* A manifest filename absent from native enumeration still receives a lazy placeholder
				so browser and alternate-path loading can resolve it later */
				if (ordered_file_index == noone)
				{
					/* ordered_label_text starts from the readable filename fallback and
					ordered_loaded_lower_name records its duplicate-detection identity */
					var ordered_label_text = builtin_fallback_label(order_file_name);
					ordered_label_text = ini_read_string(builtin_manifest_section, path_leaf(order_file_name), ordered_label_text);
					var ordered_loaded_lower_name = string_lower(path_leaf(order_file_name));
					loaded_names[array_length(loaded_names)] = ordered_loaded_lower_name;
					entries[array_length(entries)] = make_builtin_placeholder_entry(order_file_name, ordered_label_text, root_path, "");
					added_count++;
				}

				/* A matching native candidate supplies its actual path while the manifest preserves
				preferred ordering */
				else
				{
					/* ordered_file retains that candidate, loaded_lower_name normalizes its leaf, and
					already_loaded starts false until prior registrations are checked */
					var ordered_file = builtin_files[ordered_file_index];
					var loaded_lower_name = string_lower(ordered_file.file_name);
					var already_loaded = false;

					/* loaded_index visits previously registered lowercase names to prevent adding the
					same bundled PNG twice */
					for (var loaded_index = 0; loaded_index < array_length(loaded_names); loaded_index++)
					{
						/* A prior name match marks this ordered candidate already registered and stops
						the duplicate search */
						if (loaded_names[loaded_index] == loaded_lower_name)
						{
							already_loaded = true;
							break;
						}
					}

					/* Register only ordered native candidates that have not already been added */
					if (!already_loaded)
					{
						/* Packaged Included Files are enumerated in lowercase. Keep that
						actual path for loading, but use the manifest's canonical leaf for
						its name lookup and the stable built-in stamp key */
						/* canonical_file_name preserves the manifest's leaf spelling and
						ordered_label_text starts from its readable fallback before manifest name
						override */
						var canonical_file_name = path_leaf(order_file_name);
						var ordered_label_text = builtin_fallback_label(canonical_file_name);
						ordered_label_text = ini_read_string(builtin_manifest_section, canonical_file_name, ordered_label_text);
						loaded_names[array_length(loaded_names)] = loaded_lower_name;
						entries[array_length(entries)] = make_builtin_placeholder_entry(canonical_file_name, ordered_label_text, root_path, ordered_file.file_path);
						added_count++;
					}
				}

				order_index++;
			}
		}

		/* fallback_file_index visits native PNG candidates not already added by manifest ordering */
		for (var fallback_file_index = 0; fallback_file_index < array_length(builtin_files); fallback_file_index++)
		{
			/* fallback_file retains the current native path pair, fallback_lower_name normalizes its
			duplicate identity and fallback_already_loaded starts false */
			var fallback_file = builtin_files[fallback_file_index];
			var fallback_lower_name = string_lower(fallback_file.file_name);
			var fallback_already_loaded = false;

			/* fallback_loaded_index checks all names already registered from preferred order */
			for (var fallback_loaded_index = 0; fallback_loaded_index < array_length(loaded_names); fallback_loaded_index++)
			{
				/* A matching prior lowercase name marks this native fallback as already represented */
				if (loaded_names[fallback_loaded_index] == fallback_lower_name)
				{
					fallback_already_loaded = true;
					break;
				}
			}

			/* Skip an already registered native file to avoid duplicate library entries */
			if (fallback_already_loaded)
			{
				continue;
			}

			/* fallback_label_text starts with the filename-derived display label */
			var fallback_label_text = builtin_fallback_label(fallback_file.file_name);

			/* An open manifest can override the fallback display label even for files absent from its
			order section */
			if (manifest_open)
			{
				fallback_label_text = ini_read_string(builtin_manifest_section, fallback_file.file_name, fallback_label_text);
			}

			loaded_names[array_length(loaded_names)] = fallback_lower_name;
			entries[array_length(entries)] = make_builtin_placeholder_entry(fallback_file.file_name, fallback_label_text, root_path, fallback_file.file_path);
			added_count++;
		}

		/* Close the manifest after both ordered and fallback registration complete */
		if (manifest_open)
		{
			ini_close();
		}

		/* If no bundled image placeholder was registered, log the paths and discovery state explaining
		the empty bundled library */
		if (added_count <= 0)
		{
			debug_error("No built-in stamp PNGs were registered. root=" + root_path
				+ " root_exists=" + string(root_exists)
				+ " manifest=" + manifest_path
				+ " manifest_exists=" + string(manifest_exists)
				+ " manifest_open=" + string(manifest_open)
				+ " enumerated_pngs=" + string(array_length(builtin_files))
				+ " browser=" + string(uses_browser_storage()) + ".");
		}

		/* Bundled registration succeeds when at least one image placeholder was appended */
		return added_count > 0;
	}
	#endregion /* Built-in Stamp Discovery END */

	#region /* PNG Loading and Library Scans */
	/// @description Read four bytes at the buffer cursor as an unsigned big-endian integer
	/// @param {Id.Buffer} source_buffer Borrowed PNG buffer whose cursor advances four bytes
	/// @returns {Real} Unsigned 32-bit integer
	png_read_u32_be = function(source_buffer)
	{
		/* byte_a/b/c/d read the next four unsigned bytes from most to least significant for the PNG's
		big-endian integer format */
		var byte_a = buffer_read(source_buffer, buffer_u8);
		var byte_b = buffer_read(source_buffer, buffer_u8);
		var byte_c = buffer_read(source_buffer, buffer_u8);
		var byte_d = buffer_read(source_buffer, buffer_u8);
		return byte_a * 16777216 + byte_b * 65536 + byte_c * 256 + byte_d;
	}

	/// @description Inspect the PNG signature and first IHDR dimensions without decoding image pixels
	/// @param {Id.Buffer} source_buffer Borrowed PNG buffer, rewound on success but potentially advanced on failure
	/// @returns {Struct} ok, png_w, png_h, and message describing header inspection
	png_dimensions_from_buffer = function(source_buffer)
	{
		/* result starts with invalid PNG state, zero pixel dimensions and a signature-failure
		diagnostic */
		var result =
		{
			ok: false,
			png_w: 0,
			png_h: 0,
			message: "Not a PNG file."
		};

		/* A live buffer containing at least 24 bytes is needed for the PNG signature, first chunk
		header and two dimensions */
		if (is_undefined(source_buffer)
		|| !buffer_exists(source_buffer)
		|| buffer_get_size(source_buffer) < 24)
		{
			result.message = "File is too small to be a PNG.";
			return result;
		}

		buffer_seek(source_buffer, buffer_seek_start, 0);

		/* signature holds the exact eight bytes identifying a PNG file */
		var signature = [137, 80, 78, 71, 13, 10, 26, 10];

		/* sig_index checks the signature's zero-based byte positions until all eight match */
		for (var sig_index = 0; sig_index < array_length(signature); sig_index++)
		{
			/* A signature mismatch returns the provisional Not a PNG result before dimensions are
			interpreted */
			if (buffer_read(source_buffer, buffer_u8) != signature[sig_index])
			{
				return result;
			}
		}

		/* chunk_length is the first chunk's big-endian byte count and chunk_type starts empty until
		its four ASCII type bytes are read */
		var chunk_length = png_read_u32_be(source_buffer);
		var chunk_type = "";

		/* type_index reads exactly four bytes to assemble the first chunk's type */
		for (var type_index = 0; type_index < 4; type_index++)
		{
			chunk_type += chr(buffer_read(source_buffer, buffer_u8));
		}

		/* Only an IHDR chunk with at least eight payload bytes can provide the PNG's width and height */
		if (chunk_type != "IHDR" || chunk_length < 8)
		{
			result.message = "PNG header is missing IHDR.";
			return result;
		}

		result.png_w = png_read_u32_be(source_buffer);
		result.png_h = png_read_u32_be(source_buffer);
		result.ok = true;
		result.message = "";
		buffer_seek(source_buffer, buffer_seek_start, 0);
		return result;
	}

	/// @description Decode eligible PNG data into editable RGBA text, applying the low-alpha cutoff
	/// @param {String} base64_text Complete PNG encoded as base64
	/// @param {Real} source_w Expected source width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} source_h Expected source height in pixels, defaulting to stamp_h when omitted
	/// @returns {String} Row-major RRGGBBAA text, or empty when dimensions or decoding fail
	base64_to_hex = function(base64_text, source_w = stamp_w, source_h = stamp_h)
	{
		/* decode_result delegates PNG decoding with requested source dimensions and the authored
		low-alpha cutoff */
		var decode_result = RgbaPng.png_base64_to_rgba_hex(base64_text, source_w, source_h, stamp_png_alpha_cutoff);

		/* A failed PNG decode logs its diagnostic and returns no editable hex data */
		if (!decode_result.ok)
		{
			debug_error("Could not decode stamp PNG: " + decode_result.message);
			return "";
		}

		return decode_result.hex;
	}

	/// @description Read a PNG within byte and dimension limits, releasing its temporary buffer before returning
	/// @param {String} file_path PNG path or browser storage filename
	/// @returns {Struct} ok, base64, png_w, png_h, byte_size, and message
	read_png_base64 = function(file_path)
	{
		/* result starts unsuccessful with no PNG text or byte count, zero dimensions and a provisional
		unreadable-image message */
		var result =
		{
			ok: false,
			base64: "",
			png_w: 0,
			png_h: 0,
			byte_size: 0,
			message: "Could not read stamp PNG."
		};

		/* source_buffer starts unowned and is released after file inspection and encoding */
		var source_buffer = noone;
		try
		{
			/* Native file size can be checked before loading its entire PNG allocation */
			if (!uses_browser_storage())
			{
				/* size_handle borrows a binary file handle only to measure the source and is closed
				immediately after that measurement */
				var size_handle = file_bin_open(file_path, 0);

				/* A failed native file open returns the provisional unreadable-image result */
				if (size_handle < 0)
				{
					return result;
				}

				/* file_bytes is the native image file's byte count before buffer allocation */
				var file_bytes = file_bin_size(size_handle);
				file_bin_close(size_handle);

				/* Reject empty native files and files larger than the 2097152-byte import limit before
				loading them */
				if (file_bytes <= 0 || file_bytes > stamp_max_import_bytes)
				{
					result.message = stamp_import_limits_text();
					return result;
				}
			}
			source_buffer = buffer_load(file_path);

			/* An undefined or missing loaded buffer cannot supply PNG content and returns the failed
			result */
			if (is_undefined(source_buffer) || !buffer_exists(source_buffer))
			{
				return result;
			}

			/* byte_size is the loaded image allocation in bytes and png_info reports its PNG header
			and source dimensions */
			var byte_size = buffer_get_size(source_buffer);
			result.byte_size = byte_size;
			var png_info = png_dimensions_from_buffer(source_buffer);

			/* Reject loaded content exceeding the 2-MiB import limit, including browser storage reads */
			if (byte_size > stamp_max_import_bytes)
			{
				result.message = stamp_import_limits_text();
			}

			/* A malformed PNG header propagates its diagnostic rather than encoding invalid file
			content */
			else if (!png_info.ok)
			{
				result.message = png_info.message;
			}

			/* Reject dimensions outside the per-side and total-pixel import limits */
			else if (!stamp_import_size_is_supported(png_info.png_w, png_info.png_h))
			{
				result.message = stamp_import_limits_text();
			}

			/* A recognized PNG within all import limits supplies its original base64 and clears the
			provisional error */
			else
			{
				result.base64 = buffer_base64_encode(source_buffer, 0, byte_size);
				result.png_w = png_info.png_w;
				result.png_h = png_info.png_h;
				result.ok = true;
				result.message = "";
			}
		}
		catch(e)
		{
			result.message = "Could not read stamp PNG: " + string(e.message);
		}

		/* Release the locally owned source buffer after inspection or an exception, leaving only
		encoded text and scalar metadata in result */
		if (!is_undefined(source_buffer) && buffer_exists(source_buffer))
		{
			buffer_delete(source_buffer);
		}

		return result;
	}

	/// @description Append custom PNG metadata and attempt editable decoding only when dimensions fit the decoding budget
	/// @param {String} local_key_text Stable custom-prefixed entry key
	/// @param {String} label_text User-facing display label
	/// @param {String} base64_text Complete PNG encoded as base64
	/// @param {String} package_path_text Native package path, defaulting to empty when omitted
	/// @param {String} storage_file_text Browser PNG filename, defaulting to empty when omitted
	/// @param {String} created_text Creation timestamp, defaulting to empty when omitted
	/// @param {String} updated_text Update timestamp, defaulting to empty when omitted
	/// @param {Real} entry_w Source width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} entry_h Source height in pixels, defaulting to stamp_h when omitted
	/// @returns {Bool} Always true after appending an entry, even when editable decoding was unavailable
	add_custom_entry_from_base64 = function(local_key_text, label_text, base64_text, package_path_text = "", storage_file_text = "", created_text = "", updated_text = "", entry_w = stamp_w, entry_h = stamp_h)
	{
		/* safe_entry_w/h clamp source dimensions to import limits. hex_text starts empty and
		editable_value false until eligible PNG data is decoded */
		var safe_entry_w = clamp_stamp_import_dimension(entry_w);
		var safe_entry_h = clamp_stamp_import_dimension(entry_h);
		var hex_text = "";
		var editable_value = false;

		/* Only source dimensions inside editable decoding limits attempt conversion into a pixel
		canvas */
		if (stamp_can_decode_to_editable_pixels(safe_entry_w, safe_entry_h))
		{
			hex_text = base64_to_hex(base64_text, safe_entry_w, safe_entry_h);

			/* editable_value records whether decoded hex has enough RGBA data for the complete source
			grid */
			editable_value = hex_is_valid_size(hex_text, safe_entry_w, safe_entry_h);

			/* A failed pixel decode clears the partial hex text while keeping the original PNG payload
			available */
			if (!editable_value)
			{
				hex_text = "";
			}
		}

		entries[array_length(entries)] = make_entry(local_key_text, label_text, "custom", editable_value, hex_text, base64_text, package_path_text, storage_file_text, created_text, updated_text, safe_entry_w, safe_entry_h);
		return true;
	}

	/// @description Read one custom-package info field without retaining an open INI file
	/// @param {String} folder_path Native custom-package directory
	/// @param {String} key_name Key in the info section
	/// @param {String} default_value Missing-file or missing-key fallback, defaulting to empty when omitted
	/// @returns {String} Stored value or the supplied fallback
	read_custom_config_string = function(folder_path, key_name, default_value = "")
	{
		/* config_path locates the custom package's metadata under data/stamp_config.ini */
		var config_path = path_join(path_join(folder_path, "data"), stamp_config_file_name);

		/* Missing metadata returns the caller's default without opening an INI */
		if (!file_exists(config_path))
		{
			return default_value;
		}

		/* value_text starts with the default and retains it when an INI read throws */
		var value_text = default_value;
		try
		{
			ini_open(config_path);
			value_text = ini_read_string("info", key_name, default_value);
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not read stamp config " + config_path + ": " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		return value_text;
	}

	/// @description Read a native custom package's PNG and metadata, appending it only when the PNG passes import limits
	/// @param {String} folder_path Native package directory
	/// @param {String} folder_key Directory basename used for the custom key
	/// @returns {Bool} Whether a custom entry was appended
	add_desktop_custom_entry = function(folder_path, folder_key)
	{
		/* sprite_path identifies the package's fixed sprites/stamp.png source image */
		var sprite_path = path_join(path_join(folder_path, "sprites"), stamp_png_file_name);

		/* A package without that PNG is omitted from native library discovery */
		if (!file_exists(sprite_path))
		{
			return false;
		}

		/* png_result validates import limits and retains the package's original encoded PNG */
		var png_result = read_png_base64(sprite_path);

		/* An invalid or unreadable installed PNG is skipped with its diagnostic */
		if (!png_result.ok)
		{
			debug_error("Skipping custom stamp " + string(folder_key) + ": " + png_result.message);
			return false;
		}

		/* label_text reads the saved display name, while created_text and updated_text retain optional
		package timestamps */
		var label_text = read_custom_config_string(folder_path, "display_name", string_replace_all(folder_key, "_", " "));
		var created_text = read_custom_config_string(folder_path, "created_at", "");
		var updated_text = read_custom_config_string(folder_path, "updated_at", "");
		return add_custom_entry_from_base64(custom_prefix + safe_folder_key(folder_key), label_text, png_result.base64, folder_path, "", created_text, updated_text, png_result.png_w, png_result.png_h);
	}

	/// @description Enumerate native custom-package directories and append readable stamp PNGs
	/// @returns {Bool} Whether the custom root existed and directory scanning was attempted
	scan_desktop_custom_folder = function()
	{
		/* root_path is the native permanent custom-stamp directory */
		var root_path = stamp_root_path();

		/* A missing installation root has no custom packages to discover */
		if (!directory_exists(root_path))
		{
			return false;
		}

		/* search_mask targets all immediate package candidates under the installed-stamp root */
		var search_mask = path_join(root_path, "*");

		/* File attributes are only supported by GameMaker on Windows */
		/* find_attributes requests directory entries on Windows and normal search elsewhere.
		found_path retains the current result until enumeration ends */
		var find_attributes = os_type == os_windows ? fa_directory : fa_none;
		var found_path = file_find_first(search_mask, find_attributes);

		/* Continue inspecting package candidates while filesystem search results remain nonempty */
		while (found_path != "")
		{
			/* folder_key is the current result's leaf name */
			var folder_key = path_leaf(found_path);

			/* Dot directory entries are skipped because they are navigation entries rather than
			installations */
			if (folder_key != "." && folder_key != "..")
			{
				/* folder_path joins the root and current package leaf */
				var folder_path = path_join(root_path, folder_key);

				/* Use the returned search path directly when it already names an existing directory
				and the joined path is missing */
				if (!directory_exists(folder_path) && directory_exists(found_path))
				{
					folder_path = found_path;
				}

				/* Only existing directories are passed to native custom-package registration */
				if (directory_exists(folder_path))
				{
					add_desktop_custom_entry(folder_path, folder_key);
				}
			}

			found_path = file_find_next();
		}

		file_find_close();
		return true;
	}

	/// @description Restore browser custom metadata from client_settings.ini as unloaded PNG placeholders
	/// @returns {Bool} Whether the browser index was processed without an exception
	scan_browser_custom_entries = function()
	{
		/* Without client settings there is no saved browser stamp index to scan */
		if (!file_exists(settings_file))
		{
			return false;
		}

		try
		{
			ini_open(settings_file);

			/* entry_count is the persisted browser index length, clamped to a nonnegative whole count */
			var entry_count = max(0, floor(real(ini_read_real(browser_index_section, browser_index_count_key, 0))));

			/* entry_index visits every saved zero-based browser index slot */
			for (var entry_index = 0; entry_index < entry_count; entry_index++)
			{
				/* local_key_text is the saved installation identity and storage_file_text is its
				browser PNG filename */
				var local_key_text = string(ini_read_string(browser_index_section, "local_key_" + string(entry_index), ""));
				var storage_file_text = string(ini_read_string(browser_index_section, "storage_file_" + string(entry_index), ""));

				/* Entries lacking either identity or storage path are skipped because they cannot
				supply a deferred image */
				if (local_key_text == "" || storage_file_text == "")
				{
					continue;
				}

				/* Register saved browser images as lazy placeholders with display name, timestamps and
				source dimensions, deferring PNG bytes and editable decoding until needed */
				entries[array_length(entries)] = make_custom_placeholder_entry(
					local_key_text,
					ini_read_string(browser_index_section, "display_name_" + string(entry_index), "Stamp"),
					storage_file_text,
					ini_read_string(browser_index_section, "created_at_" + string(entry_index), ""),
					ini_read_string(browser_index_section, "updated_at_" + string(entry_index), ""),
					max(1, floor(real(ini_read_real(browser_index_section, "width_" + string(entry_index), stamp_w)))),
					max(1, floor(real(ini_read_real(browser_index_section, "height_" + string(entry_index), stamp_h))))
				);
			}
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not scan browser stamps: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Rebuild the library when forced, release its preview resources, and retain the selected key when still available
	/// @param {Bool} force Whether to rescan instead of reusing entries, defaulting to false when omitted
	/// @returns {Array} Library entries owned by this manager
	scan = function(force = false)
	{
		/* Reuse existing library discovery after its first scan unless force requests a new
		resource-releasing rescan */
		if (scanned && !force)
		{
			return entries;
		}

		/* previous_key retains the selection across rebuilding entries and releasing their owned
		preview resources */
		var previous_key = selected_key;
		delete_cached_surfaces();
		entries = [];
		add_builtin_entries();

		/* Browser builds rebuild custom records from their saved storage index */
		if (uses_browser_storage())
		{
			scan_browser_custom_entries();
		}

		/* Native builds rebuild custom records from installed package directories */
		else
		{
			scan_desktop_custom_folder();
		}

		scanned = true;

		/* If the prior selected identity survives rediscovery, retain it */
		if (entry_index_by_key(previous_key) != noone)
		{
			selected_key = previous_key;
		}

		/* Otherwise a nonempty rebuilt library selects its first entry */
		else if (array_length(entries) > 0)
		{
			selected_key = entries[0].key;
		}

		/* An empty rebuilt library clears selection identity */
		else
		{
			selected_key = "";
		}

		return entries;
	}

	/// @description Obtain the library, rebuilding it only when forced or not yet scanned
	/// @param {Bool} force Whether to discard caches and rescan storage, defaulting to false when omitted
	/// @returns {Array} Borrowed manager-owned library entries
	refresh = function(force = false)
	{
		return scan(force);
	}
	#endregion /* PNG Loading and Library Scans END */

	#region /* Custom Stamp Storage */
	/// @description Write supported RGBA text directly as a native PNG through the shared codec
	/// @param {String} hex_text Row-major RRGGBBAA text
	/// @param {String} destination_path Native PNG output path
	/// @param {Real} write_w Canvas width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} write_h Canvas height in pixels, defaulting to stamp_h when omitted
	/// @returns {Bool} Whether the codec reported a successful PNG write
	write_hex_to_png = function(hex_text, destination_path, write_w = stamp_w, write_h = stamp_h)
	{
		/* safe_write_w/h are positive whole output dimensions for the RGBA PNG writer */
		var safe_write_w = max(1, floor(real(write_w)));
		var safe_write_h = max(1, floor(real(write_h)));

		/* Reject hex text lacking enough RGBA characters for the full output canvas before writing a
		file */
		if (!hex_is_valid_size(hex_text, safe_write_w, safe_write_h))
		{
			return false;
		}

		return RgbaPng.rgba_hex_to_png_file(destination_path, safe_write_w, safe_write_h, hex_text);
	}

	/// @description Encode RGBA through a temporary native PNG, then read base64 and remove the file after the read
	/// @param {String} hex_text Row-major RRGGBBAA text
	/// @param {Real} encode_w Width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} encode_h Height in pixels, defaulting to stamp_h when omitted
	/// @returns {Struct} ok, base64, and message describing encoding
	hex_to_png_base64_desktop = function(hex_text, encode_w = stamp_w, encode_h = stamp_h)
	{
		/* result starts failed with no encoded PNG and a provisional encoder diagnostic */
		var result =
		{
			ok: false,
			base64: "",
			message: "Could not encode stamp PNG."
		};

		/* folder_path is the writable stamp temporary directory used for a one-call encode/read round
		trip */
		var folder_path = temp_root_path();

		/* Without a prepared temporary directory, desktop encoding cannot write its intermediate PNG */
		if (!ensure_folder(folder_path))
		{
			result.message = "Could not create stamp temp folder.";
			return result;
		}

		/* temp_path combines a timestamp and random suffix to distinguish this encoder's intermediate
		image file */
		var temp_path = path_join(folder_path, "JonnilOnline_Stamp_" + stamp_timestamp() + "_" + string(irandom(999999)) + ".png");

		/* A failed RGBA-to-PNG write returns the provisional encoding failure */
		if (!write_hex_to_png(hex_text, temp_path, encode_w, encode_h))
		{
			return result;
		}

		/* png_result reloads and validates the temporary PNG as original base64 data */
		var png_result = read_png_base64(temp_path);

		/* Delete the intermediate PNG when it exists after the read attempt, retaining only encoded
		content in result */
		if (file_exists(temp_path))
		{
			try { file_delete(temp_path); } catch(delete_error) {}
		}

		result.ok = png_result.ok;
		result.base64 = png_result.base64;
		result.message = png_result.message;
		return result;
	}

	/// @description Encode RGBA hex through the browser PNG extension without a native temporary file
	/// @param {String} hex_text Row-major RRGGBBAA text
	/// @param {Real} encode_w Width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} encode_h Height in pixels, defaulting to stamp_h when omitted
	/// @returns {Struct} ok, base64, and message describing encoding
	hex_to_png_base64_browser = function(hex_text, encode_w = stamp_w, encode_h = stamp_h)
	{
		/* result starts failed with empty browser PNG data and a provisional encoder diagnostic */
		var result =
		{
			ok: false,
			base64: "",
			message: "Could not encode browser stamp PNG."
		};

		try
		{
			/* base64_text receives the browser extension's PNG encoding of the requested RGBA canvas */
			var base64_text = html5_stamp_rgba_hex_to_png_base64(encode_w, encode_h, hex_text);

			/* An empty browser result has no PNG content and needs a specific or fallback diagnostic */
			if (string_trim(string(base64_text)) == "")
			{
				/* error_text starts empty and is replaced when the browser extension exposes its last
				encoding error */
				var error_text = "";
				try { error_text = html5_stamp_last_error(); } catch(error_read) {}

				/* A nonempty extension error replaces the provisional message, otherwise retain the
				general encode failure */
				result.message = string_trim(error_text) == "" ? result.message : error_text;
				return result;
			}

			result.ok = true;
			result.base64 = base64_text;
			result.message = "";
		}
		catch(e)
		{
			result.message = "Could not encode browser stamp PNG: " + string(e.message);
		}

		return result;
	}

	/// @description Encode RGBA through the shared PNG codec, falling back to the platform-specific encoder on failure
	/// @param {String} hex_text Row-major RRGGBBAA text
	/// @param {Real} encode_w Width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} encode_h Height in pixels, defaulting to stamp_h when omitted
	/// @returns {Struct} ok, base64, and message describing encoding
	hex_to_png_base64 = function(hex_text, encode_w = stamp_w, encode_h = stamp_h)
	{
		/* result first tries the shared RGBA PNG codec before platform-specific fallback encoding */
		var result = RgbaPng.rgba_hex_to_png_base64(encode_w, encode_h, hex_text);

		/* A shared encoder failure selects a browser extension fallback or desktop temporary-file
		fallback */
		if (!result.ok)
		{
			/* Browser builds use the extension encoder, while native builds use the temporary PNG
			round trip */
			return uses_browser_storage() ? hex_to_png_base64_browser(hex_text, encode_w, encode_h) : hex_to_png_base64_desktop(hex_text, encode_w, encode_h);
		}

		return result;
	}

	/// @description Generate a browser PNG filename using the sanitized name, timestamp, and random suffix
	/// @param {String} safe_name_text Name to sanitize for storage
	/// @returns {String} PNG storage filename
	browser_storage_file_for_stamp = function(safe_name_text)
	{
		return browser_storage_prefix + safe_folder_key(safe_name_text) + "_" + stamp_timestamp() + "_" + string(irandom(999999)) + ".png";
	}

	/// @description Persist all custom entries and their metadata under the browser_stamps INI section
	/// @returns {Bool} Whether index writing completed without an exception
	write_browser_index = function()
	{
		try
		{
			ini_open(settings_file);

			/* custom_count starts zero and numbers only persisted custom entries rather than all
			library records */
			var custom_count = 0;

			/* entry_index visits the complete discovered library while constructing a compact saved
			custom index */
			for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
			{
				/* Only custom records with a storage filename are persisted in the browser
				installation index */
				if (entries[entry_index].source == "custom" && entries[entry_index].storage_file != "")
				{
					/* entry is the eligible custom record whose identity, dimensions, timestamps and
					current local author are saved */
					var entry = entries[entry_index];
					ini_write_string(browser_index_section, "local_key_" + string(custom_count), entry.key);
					ini_write_string(browser_index_section, "display_name_" + string(custom_count), entry.label);
					ini_write_string(browser_index_section, "safe_name_" + string(custom_count), safe_folder_key(entry.label));
					ini_write_string(browser_index_section, "storage_file_" + string(custom_count), entry.storage_file);
					ini_write_real(browser_index_section, "width_" + string(custom_count), entry_stamp_w(entry));
					ini_write_real(browser_index_section, "height_" + string(custom_count), entry_stamp_h(entry));
					ini_write_string(browser_index_section, "created_at_" + string(custom_count), entry.created_at);
					ini_write_string(browser_index_section, "updated_at_" + string(custom_count), entry.updated_at);
					ini_write_string(browser_index_section, "author_name_" + string(custom_count), local_author_name());
					custom_count++;
				}
			}

			ini_write_real(browser_index_section, browser_index_count_key, custom_count);
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not write browser stamp index: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Ensure a native package directory and persist its identity, dimensions, timestamps, and local author
	/// @param {String} package_path Native package directory
	/// @param {String} folder_key Safe storage identity
	/// @param {String} label_text User-facing label
	/// @param {String} created_text Creation timestamp
	/// @param {String} updated_text Update timestamp
	/// @param {Real} config_w Source width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} config_h Source height in pixels, defaulting to stamp_h when omitted
	/// @returns {Bool} Whether directory creation and metadata writing completed
	write_desktop_config = function(package_path, folder_key, label_text, created_text, updated_text, config_w = stamp_w, config_h = stamp_h)
	{
		/* data_path is the native package metadata directory */
		var data_path = path_join(package_path, "data");

		/* A metadata directory must be prepared before saving package configuration */
		if (!ensure_folder(data_path))
		{
			return false;
		}

		/* config_path is the fixed stamp_config.ini destination inside that data directory */
		var config_path = path_join(data_path, stamp_config_file_name);
		try
		{
			ini_open(config_path);
			ini_write_real("info", "version", 1);
			ini_write_string("info", "display_name", label_text);
			ini_write_string("info", "safe_name", safe_folder_key(folder_key));
			ini_write_string("info", "source", "custom");
			ini_write_string("info", "created_at", created_text);
			ini_write_string("info", "updated_at", updated_text);
			ini_write_string("info", "author_name", local_author_name());
			ini_write_string("stamp", "file", stamp_png_file_name);
			ini_write_real("stamp", "width", config_w);
			ini_write_real("stamp", "height", config_h);
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not write stamp package config: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Decode base64 into a temporary buffer, save its bytes, and release the buffer without validating PNG content
	/// @param {String} base64_text Bytes encoded as base64
	/// @param {String} destination_path PNG output path or browser storage filename
	/// @returns {Struct} ok and message, with ok indicating that the destination exists after the attempted save
	save_base64_png_file = function(base64_text, destination_path)
	{
		/* result starts failed with a provisional PNG-save message */
		var result =
		{
			ok: false,
			message: "Could not save stamp PNG."
		};

		/* decoded_buffer starts without an owned allocation and is released after the decoded bytes
		are written or saving fails */
		var decoded_buffer = noone;
		try
		{
			decoded_buffer = buffer_base64_decode(string(base64_text));

			/* An undefined or missing decode result cannot be written as a PNG */
			if (is_undefined(decoded_buffer) || !buffer_exists(decoded_buffer))
			{
				result.message = "Could not decode stamp PNG.";
			}

			/* A live decoded buffer can be saved to the requested path */
			else
			{
				buffer_save(decoded_buffer, destination_path);

				/* A visible destination file marks this save successful and clears its diagnostic */
				if (file_exists(destination_path))
				{
					result.ok = true;
					result.message = "";
				}

				/* If the destination file did not appear, report the unsuccessful write */
				else
				{
					result.message = "Stamp PNG was not saved.";
				}
			}
		}
		catch(e)
		{
			result.message = "Could not save stamp PNG: " + string(e.message);
		}

		/* Release the locally owned decoded allocation after its save attempt or an exception */
		if (!is_undefined(decoded_buffer) && buffer_exists(decoded_buffer))
		{
			buffer_delete(decoded_buffer);
		}

		return result;
	}

	/// @description Look up the custom-prefixed form of a sanitized local storage name
	/// @param {String} local_key_text Unprefixed local name to sanitize
	/// @returns {Bool} Whether the current library contains that custom key
	custom_key_exists = function(local_key_text)
	{
		/* A sanitized custom identity already present in discovery reserves this installation name */
		return entry_index_by_key(custom_prefix + safe_folder_key(local_key_text)) != noone;
	}

	/// @description Add numeric suffixes until a sanitized name avoids library and native-directory collisions
	/// @param {String} label_text Desired display name
	/// @returns {String} Available unprefixed package key
	unique_custom_folder_key = function(label_text)
	{
		/* base_key sanitizes the requested name, candidate_key initially uses it unchanged, and suffix
		starts at 2 for collisions */
		var base_key = safe_folder_key(label_text);
		var candidate_key = base_key;
		var suffix = 2;

		/* Keep adding numeric suffixes while a matching discovered key or native installation
		directory already exists */
		while (custom_key_exists(candidate_key)
		|| (!uses_browser_storage() && directory_exists(path_join(stamp_root_path(), candidate_key))))
		{
			candidate_key = base_key + "_" + string(suffix);
			suffix++;
		}

		return candidate_key;
	}

	/// @description Store a nonempty PNG payload with import-supported dimensions, refresh the library, and select the installed custom entry
	/// @param {String} base64_text Complete PNG base64, expected to have been validated by the caller
	/// @param {String} label_text Desired display label
	/// @param {Real} entry_w Source width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} entry_h Source height in pixels, defaulting to stamp_h when omitted
	/// @param {String} existing_key_text Custom key to overwrite, defaulting to empty for a new entry when omitted
	/// @returns {Bool} Whether installation reached its successful refresh and selection
	install_custom_base64 = function(base64_text, label_text, entry_w = stamp_w, entry_h = stamp_h, existing_key_text = "")
	{
		/* safe_entry_w/h are positive whole source dimensions used for saved metadata and import-size
		checks */
		var safe_entry_w = max(1, floor(real(entry_w)));
		var safe_entry_h = max(1, floor(real(entry_h)));

		/* Reject dimensions outside the per-side and total-pixel import limits before saving PNG data */
		if (!stamp_import_size_is_supported(safe_entry_w, safe_entry_h))
		{
			set_status(stamp_import_limits_text(), make_color_rgb(244, 84, 84));
			return false;
		}

		/* Empty encoded text cannot provide a custom stamp PNG */
		if (string_trim(string(base64_text)) == "")
		{
			set_status("Stamp PNG data is invalid.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* now_text is the current package timestamp and clean_label uses the requested label or a
		timestamped Stamp fallback */
		var now_text = stamp_timestamp();
		var clean_label = string_trim(string(label_text)) == "" ? "Stamp " + now_text : string(label_text);

		/* existing_index resolves a requested overwrite or stays noone for a new installation.
		created_text keeps the original creation time on overwrite and uses now for new entries */
		var existing_index = existing_key_text == "" ? noone : entry_index_by_key(existing_key_text);
		var created_text = existing_index == noone ? now_text : entries[existing_index].created_at;

		/* folder_key preserves an overwrite basename or chooses an unused new name. local_key_text
		adds the custom category prefix */
		var folder_key = existing_index == noone ? unique_custom_folder_key(clean_label) : safe_folder_key(string_replace_all(existing_key_text, custom_prefix, ""));
		var local_key_text = custom_prefix + folder_key;

		/* Browser installation saves the PNG file, updates the in-memory record and persists the
		custom index */
		if (uses_browser_storage())
		{
			/* storage_file_text reuses an existing nonempty browser filename on overwrite, otherwise
			generates a new owned filename */
			var storage_file_text = existing_index == noone || entries[existing_index].storage_file == "" ? browser_storage_file_for_stamp(folder_key) : entries[existing_index].storage_file;

			/* browser_save_result records whether the encoded PNG bytes were decoded and saved */
			var browser_save_result = save_base64_png_file(base64_text, storage_file_text);

			/* A failed PNG save prevents changing the browser library record */
			if (!browser_save_result.ok)
			{
				set_status(browser_save_result.message, make_color_rgb(244, 84, 84));
				return false;
			}

			/* A new installation appends a custom entry retaining the original PNG and source
			dimensions */
			if (existing_index == noone)
			{
				entries[array_length(entries)] = make_entry(local_key_text, clean_label, "custom", false, "", base64_text, "", storage_file_text, created_text, now_text, safe_entry_w, safe_entry_h);
			}

			/* An overwrite replaces the existing custom record with the new PNG and updated metadata */
			else
			{
				entries[existing_index] = make_entry(local_key_text, clean_label, "custom", false, "", base64_text, "", storage_file_text, created_text, now_text, safe_entry_w, safe_entry_h);
			}

			/* The browser installation requires its saved index as well as its PNG file */
			if (!write_browser_index())
			{
				set_status("Could not write stamp browser index.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		/* Native installation prepares a package directory and writes its PNG and configuration */
		else
		{
			/* root_path locates custom stamps, package_path locates this installation and sprite_path
			locates its PNG subdirectory */
			var root_path = stamp_root_path();
			var package_path = path_join(root_path, folder_key);
			var sprite_path = path_join(package_path, "sprites");

			/* Prepare parent, package and sprite directories in that order before attempting a PNG
			save */
			if (!ensure_folder(root_path) || !ensure_folder(package_path) || !ensure_folder(sprite_path))
			{
				set_status("Could not create stamp package.", make_color_rgb(244, 84, 84));
				return false;
			}

			/* png_path is the package's fixed stamp.png destination and desktop_save_result records
			its byte-save outcome */
			var png_path = path_join(sprite_path, stamp_png_file_name);
			var desktop_save_result = save_base64_png_file(base64_text, png_path);

			/* A failed native image write stops before publishing package metadata */
			if (!desktop_save_result.ok)
			{
				set_status(desktop_save_result.message, make_color_rgb(244, 84, 84));
				return false;
			}

			/* A failed configuration write leaves no complete native installation to announce */
			if (!write_desktop_config(package_path, folder_key, clean_label, created_text, now_text, safe_entry_w, safe_entry_h))
			{
				set_status("Could not write stamp config.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		scanned = false;
		refresh(true);
		selected_key = local_key_text;
		set_status("Saved " + clean_label + ".", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Encode and store editable RGBA text as a custom PNG, then refresh and select the installed entry
	/// @param {String} hex_text Row-major RRGGBBAA text, checked for length and editable per-side limits
	/// @param {String} label_text Desired display label
	/// @param {Real} entry_w Canvas width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} entry_h Canvas height in pixels, defaulting to stamp_h when omitted
	/// @param {String} existing_key_text Custom key to overwrite, defaulting to empty for a new entry when omitted
	/// @returns {Bool} Whether installation reached its successful refresh and selection
	install_custom_hex = function(hex_text, label_text, entry_w = stamp_w, entry_h = stamp_h, existing_key_text = "")
	{
		/* safe_entry_w/h are positive whole editable-canvas dimensions */
		var safe_entry_w = max(1, floor(real(entry_w)));
		var safe_entry_h = max(1, floor(real(entry_h)));

		/* Only dimensions within editable per-side limits can be saved from RGBA hex */
		if (!stamp_size_is_supported(safe_entry_w, safe_entry_h))
		{
			set_status("Stamp size must be between " + stamp_size_range_text() + " wide and high.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* The requested grid requires a complete RGBA hex payload before pixel encoding or file writes */
		if (!hex_is_valid_size(hex_text, safe_entry_w, safe_entry_h))
		{
			set_status("Stamp data is invalid.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* now_text is the update timestamp and clean_label uses the supplied display name or a
		timestamped fallback */
		var now_text = stamp_timestamp();
		var clean_label = string_trim(string(label_text)) == "" ? "Stamp " + now_text : string(label_text);

		/* existing_index resolves an overwrite or stays noone for a new record. created_text preserves
		original creation time when overwriting */
		var existing_index = existing_key_text == "" ? noone : entry_index_by_key(existing_key_text);
		var created_text = existing_index == noone ? now_text : entries[existing_index].created_at;

		/* folder_key preserves the existing installation basename or chooses a unique new one, and
		local_key_text adds the custom prefix */
		var folder_key = existing_index == noone ? unique_custom_folder_key(clean_label) : safe_folder_key(string_replace_all(existing_key_text, custom_prefix, ""));
		var local_key_text = custom_prefix + folder_key;

		/* Browser pixel saves encode the RGBA canvas and persist its PNG plus custom index */
		if (uses_browser_storage())
		{
			/* base64_result is the browser encoder's PNG data and success diagnostic */
			var base64_result = hex_to_png_base64_browser(hex_text, safe_entry_w, safe_entry_h);

			/* A failed encode stops before browser file allocation */
			if (!base64_result.ok)
			{
				set_status(base64_result.message, make_color_rgb(244, 84, 84));
				return false;
			}

			/* storage_file_text reuses an existing saved filename or creates a new owned one.
			decoded_buffer starts unowned and browser_write_ok starts false */
			var storage_file_text = existing_index == noone || entries[existing_index].storage_file == "" ? browser_storage_file_for_stamp(folder_key) : entries[existing_index].storage_file;
			var decoded_buffer = noone;
			var browser_write_ok = false;
			try
			{
				decoded_buffer = buffer_base64_decode(base64_result.base64);

				/* An undefined or missing decoded PNG cannot be written to browser storage */
				if (is_undefined(decoded_buffer) || !buffer_exists(decoded_buffer))
				{
					set_status("Could not decode stamp PNG.", make_color_rgb(244, 84, 84));
					return false;
				}

				buffer_save(decoded_buffer, storage_file_text);

				/* Record whether the browser destination exists after saving before publishing the new
				record */
				browser_write_ok = file_exists(storage_file_text);
			}
			catch(e)
			{
				set_status("Could not save browser stamp: " + string(e.message), make_color_rgb(244, 84, 84));

				/* Release a still-live locally owned buffer when browser saving throws */
				if (!is_undefined(decoded_buffer) && buffer_exists(decoded_buffer))
				{
					buffer_delete(decoded_buffer);
				}
				return false;
			}

			/* Release the decoded PNG allocation after successful browser writing, retaining encoded
			text and hex in the entry */
			if (!is_undefined(decoded_buffer) && buffer_exists(decoded_buffer))
			{
				buffer_delete(decoded_buffer);
			}

			/* A missing stored file prevents publishing a browser entry whose PNG cannot load */
			if (!browser_write_ok)
			{
				set_status("Browser storage did not save the custom stamp.", make_color_rgb(244, 84, 84));
				return false;
			}

			/* New pixel installations append a custom record retaining hex and encoded PNG data */
			if (existing_index == noone)
			{
				entries[array_length(entries)] = make_entry(local_key_text, clean_label, "custom", true, hex_text, base64_result.base64, "", storage_file_text, created_text, now_text, safe_entry_w, safe_entry_h);
			}

			/* Overwrites replace the existing record with updated pixels and timestamps */
			else
			{
				entries[existing_index] = make_entry(local_key_text, clean_label, "custom", true, hex_text, base64_result.base64, "", storage_file_text, created_text, now_text, safe_entry_w, safe_entry_h);
			}

			/* Browser persistence needs its index after storing the encoded image */
			if (!write_browser_index())
			{
				set_status("Could not write stamp browser index.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		/* Native pixel saves write a package PNG directly from hex and then configuration metadata */
		else
		{
			/* root_path is the installation parent, package_path identifies this custom package, and
			sprite_path is its image directory */
			var root_path = stamp_root_path();
			var package_path = path_join(root_path, folder_key);
			var sprite_path = path_join(package_path, "sprites");

			/* Parent, package and image folders must all exist before writing the canvas PNG */
			if (!ensure_folder(root_path) || !ensure_folder(package_path) || !ensure_folder(sprite_path))
			{
				set_status("Could not create stamp package.", make_color_rgb(244, 84, 84));
				return false;
			}

			/* png_path is the fixed native stamp.png output */
			var png_path = path_join(sprite_path, stamp_png_file_name);

			/* A failed RGBA PNG write prevents configuration and success reporting */
			if (!write_hex_to_png(hex_text, png_path, safe_entry_w, safe_entry_h))
			{
				set_status("Could not save stamp PNG.", make_color_rgb(244, 84, 84));
				return false;
			}

			/* A failed native configuration write prevents treating the saved PNG as a complete custom
			installation */
			if (!write_desktop_config(package_path, folder_key, clean_label, created_text, now_text, safe_entry_w, safe_entry_h))
			{
				set_status("Could not write stamp config.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		scanned = false;
		refresh(true);
		selected_key = local_key_text;
		set_status("Saved " + clean_label + ".", make_color_rgb(126, 245, 150));
		return true;
	}
	#endregion /* Custom Stamp Storage END */

	#region /* Stamp Editor Lifecycle */
	/// @description Open a blank pixel editor with clamped canvas dimensions
	/// @param {Real} new_stamp_w Canvas width in source pixels, defaulting to stamp_w when omitted
	/// @param {Real} new_stamp_h Canvas height in source pixels, defaulting to stamp_h when omitted
	/// @returns {Bool} Whether the editor opened
	begin_new_stamp = function(new_stamp_w = stamp_w, new_stamp_h = stamp_h)
	{
		/* safe_stamp_w and safe_stamp_h clamp the requested whole source-pixel canvas dimensions to
		the editable per-side limits */
		var safe_stamp_w = clamp_stamp_dimension(new_stamp_w);
		var safe_stamp_h = clamp_stamp_dimension(new_stamp_h);

		/* Reject an unsupported canvas size before allocating its editor */
		if (!stamp_size_is_supported(safe_stamp_w, safe_stamp_h))
		{
			set_status("Stamp size must be between " + stamp_size_range_text() + " wide and high.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* The new editor owns a blank RGBA canvas. Source identity stays empty, the label starts New
		Stamp, overwrite mode is disabled, Pen is selected and the viewport starts at its first cell */
		editor = new scr_pixel_editor(safe_stamp_w, safe_stamp_h);
		editor_source_key = "";
		editor_source_label = "New Stamp";
		editor_existing_custom = false;
		editor_tool = PIXEL_EDITOR_TOOL_PEN;
		editor_view_col = 0;
		editor_view_row = 0;
		editor_open = true;
		mark_editor_surface_dirty();
		sync_editor_size_text(true);
		set_initial_editor_zoom();
		return true;
	}

	/// @description Load editable pixels and open the selected stamp. Built-in entries save to a custom copy
	/// @returns {Bool} Whether editable pixels were available and the editor opened
	begin_edit_selected = function()
	{
		refresh();

		/* entry_index resolves the selected stamp after library discovery */
		var entry_index = selected_entry_index();

		/* Without a selected entry there is no image to load into the editor */
		if (entry_index == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* Deferred PNG loading or missing decoded pixels requires an explicit forced load/decode
		before editing */
		if (entry_should_load_or_decode_pixels(entries[entry_index]))
		{
			/* A failed PNG load prevents opening an editor for unavailable source data */
			if (!ensure_entry_png_payload(entry_index, true, true))
			{
				set_status("Could not load built-in stamp PNG.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		/* entry is the selected record after any load/decode updated its cached state */
		var entry = entries[entry_index];

		/* A record without a complete editable pixel payload cannot enter the pixel editor */
		if (!entry_has_editable_pixels(entry))
		{
			set_status("This image stamp is too large for pixel editing.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* The editor receives its own pixel canvas from the selected hex data, retaining source
		identity and label for saving while resetting tool and viewport */
		editor = editor_from_hex(entry.hex, entry_stamp_w(entry), entry_stamp_h(entry));
		editor_source_key = entry.key;
		editor_source_label = entry.label;

		/* editor_existing_custom is true only for a custom installation, choosing overwrite rather
		than a new copy on save */
		editor_existing_custom = entry.source == "custom";
		editor_tool = PIXEL_EDITOR_TOOL_PEN;
		editor_view_col = 0;
		editor_view_row = 0;
		editor_open = true;
		mark_editor_surface_dirty();
		sync_editor_size_text(true);
		set_initial_editor_zoom();

		/* Editing a bundled image warns that saving creates a custom copy and preserves the bundled
		source */
		if (!editor_existing_custom)
		{
			set_status("Editing a built-in stamp will save a custom copy.", make_color_rgb(255, 220, 95));
		}
		return true;
	}

	/// @description Install an independent custom copy of the selected builtin stamp, preferring its original PNG payload
	/// @returns {Bool} Whether a builtin selection was successfully copied
	copy_selected_builtin = function()
	{
		refresh();

		/* entry_index resolves the current selection for the bundled-copy action */
		var entry_index = selected_entry_index();

		/* No selected record means there is no bundled image to copy */
		if (entry_index == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* entry borrows the selected record for source-type and payload checks */
		var entry = entries[entry_index];

		/* This action only copies bundled stamps, since custom installations already belong to the
		editable library */
		if (entry.source != "builtin")
		{
			set_status("Only built-in stamps need copying.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* A deferred bundled image must load its original PNG before it can be copied */
		if (entry_can_lazy_load_png(entry))
		{
			/* A failed explicit source load stops the copy */
			if (!ensure_entry_png_payload(entry_index, false, true))
			{
				set_status("Could not load built-in stamp PNG.", make_color_rgb(244, 84, 84));
				return false;
			}
			entry = entries[entry_index];
		}

		/* Prefer copying the original PNG payload, preserving its resolution and alpha without an
		editor round trip */
		if (entry_has_png_payload(entry))
		{
			return install_custom_base64(entry.base64, entry.label + " Copy", entry_stamp_w(entry), entry_stamp_h(entry), "");
		}

		/* If no original PNG is available, complete editable RGBA data can still be installed as a
		custom copy */
		if (entry_has_editable_pixels(entry))
		{
			return install_custom_hex(entry.hex, entry.label + " Copy", entry_stamp_w(entry), entry_stamp_h(entry), "");
		}

		set_status("Stamp data is invalid.", make_color_rgb(244, 84, 84));
		return false;
	}

	/// @description Attempt to remove the selected custom PNG and metadata, then rebuild selection and report deletion
	/// @returns {Bool} Whether an eligible custom deletion was attempted, without confirming every underlying removal
	delete_selected_custom = function()
	{
		refresh();

		/* entry_index resolves the selected installation for the custom deletion action */
		var entry_index = selected_entry_index();

		/* Without a selected record there is no installation to remove */
		if (entry_index == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* entry retains the selected record's storage paths and label throughout deletion and refresh */
		var entry = entries[entry_index];

		/* Bundled sources are preserved and cannot be deleted through the custom installation action */
		if (entry.source != "custom")
		{
			set_status("Built-in stamps cannot be deleted.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* Browser deletion removes the owned PNG and rewrites the surviving custom index */
		if (uses_browser_storage())
		{
			/* Attempt file deletion only for a nonempty browser storage path that exists */
			if (entry.storage_file != "" && file_exists(entry.storage_file))
			{
				try { file_delete(entry.storage_file); } catch(delete_error) {}
			}

			array_delete(entries, entry_index, 1);
			write_browser_index();
			scanned = false;
			refresh(true);
		}

		/* Native deletion attempts the package's known image/config files and their containing
		directories */
		else
		{
			/* data_path and sprite_path locate package subfolders, while config_path and png_path
			identify their fixed metadata and image files */
			var data_path = path_join(entry.package_path, "data");
			var sprite_path = path_join(entry.package_path, "sprites");
			var config_path = path_join(data_path, stamp_config_file_name);
			var png_path = path_join(sprite_path, stamp_png_file_name);

			/* Delete the package configuration only if its file exists */
			if (file_exists(config_path))
			{
				try { file_delete(config_path); } catch(config_error) {}
			}

			/* Delete the package PNG only if it exists */
			if (file_exists(png_path))
			{
				try { file_delete(png_path); } catch(png_error) {}
			}

			/* Attempt to remove the metadata directory only when it still exists */
			if (directory_exists(data_path))
			{
				try { directory_delete(data_path); } catch(data_delete_error) {}
			}

			/* Attempt to remove the sprite directory only when it still exists */
			if (directory_exists(sprite_path))
			{
				try { directory_delete(sprite_path); } catch(sprite_delete_error) {}
			}

			/* Attempt to remove the package root only for a nonempty existing path */
			if (entry.package_path != "" && directory_exists(entry.package_path))
			{
				try { directory_delete(entry.package_path); } catch(package_delete_error) {}
			}

			scanned = false;
			refresh(true);
		}

		set_status("Deleted " + entry.label + ".", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Save the current pixel canvas, overwrite an existing custom entry when editing it, and close the editor after success
	/// @returns {Bool} Whether the custom stamp was saved
	save_editor = function()
	{
		/* Saving needs a valid current pixel editor model */
		if (!is_struct(editor))
		{
			return false;
		}

		/* label_text starts from the opened source label and existing_key_text targets an overwrite
		only for an existing custom installation */
		var label_text = editor_source_label;
		var existing_key_text = editor_existing_custom ? editor_source_key : "";

		/* New and bundled-source editors need a saved custom-copy label */
		if (!editor_existing_custom)
		{
			/* A blank New Stamp canvas gets a timestamp name, while an edited bundled source receives
			a Copy suffix */
			label_text = editor_source_label == "New Stamp" ? "Stamp " + stamp_timestamp() : editor_source_label + " Copy";
		}

		/* result records whether exporting editor hex and installing its custom package succeeded */
		var result = install_custom_hex(editor.to_hex_string(), label_text, editor.grid_w, editor.grid_h, existing_key_text);

		/* Only a complete save closes the editor and releases its cached pixel and HSV surfaces */
		if (result)
		{
			editor_open = false;
			editor = noone;
			free_editor_surface_cache();
			free_editor_hsv_surfaces();
		}

		return result;
	}

	/// @description Close the editor, clear input focus, and release manager-owned pixel and HSV preview surfaces
	/// @returns {Bool} Always true after resetting editor state
	cancel_editor = function()
	{
		editor_open = false;
		editor = noone;
		editor_size_focus = "";
		keyboard_string = "";
		free_editor_surface_cache();
		free_editor_hsv_surfaces();
		set_status("Stamp edit cancelled.", make_color_rgb(178, 178, 184));
		return true;
	}

	/// @description Synchronize canvas-size text while preserving a field currently being edited unless forced
	/// @param {Bool} force Whether to overwrite focused field text too, defaulting to false when omitted
	/// @returns {Bool} Whether a valid editor model was available for synchronization
	sync_editor_size_text = function(force = false)
	{
		/* Without a valid editor there are no canvas dimensions to synchronize */
		if (!is_struct(editor))
		{
			return false;
		}

		/* Refresh width text when forced or when that field does not currently own typing focus */
		if (force || editor_size_focus != "w")
		{
			editor_size_w_text = string(editor.grid_w);
		}

		/* Refresh height text when forced or when that field does not own typing focus */
		if (force || editor_size_focus != "h")
		{
			editor_size_h_text = string(editor.grid_h);
		}

		return true;
	}

	/// @description Parse the width and height fields and resize a changed canvas, invalidating previews and clamping its viewport
	/// @returns {Bool} Whether an open editor received different supported dimensions
	apply_editor_resize_from_text = function()
	{
		/* Resize input applies only while a valid editor is open */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* resize_w and resize_h parse digits-only draft dimensions with current canvas sizes as
		fallbacks */
		var resize_w = stamp_dimension_from_text(editor_size_w_text, editor.grid_w);
		var resize_h = stamp_dimension_from_text(editor_size_h_text, editor.grid_h);
		editor_size_w_text = string(resize_w);
		editor_size_h_text = string(resize_h);

		/* A request matching both current dimensions leaves the canvas unchanged and reports no resize */
		if (resize_w == editor.grid_w && resize_h == editor.grid_h)
		{
			set_status("Stamp size unchanged.", make_color_rgb(178, 178, 184));
			return false;
		}

		editor.resize_canvas(resize_w, resize_h);
		mark_editor_surface_dirty();
		editor_size_focus = "";
		keyboard_string = "";
		sync_editor_size_text(true);
		clamp_editor_view();
		set_status("Resized stamp to " + stamp_size_label(resize_w, resize_h) + ".", make_color_rgb(126, 245, 150));
		return true;
	}
	#endregion /* Stamp Editor Lifecycle END */

	#region /* Library Actions and PNG Transfer */
	/// @description Extract a path's filename and remove a case-insensitive trailing .png extension
	/// @param {String} raw_name Path or filename
	/// @returns {String} Filename without its PNG extension
	strip_png_extension = function(raw_name)
	{
		/* name_text extracts the filename's leaf and lower_text provides a case-insensitive
		PNG-extension check */
		var name_text = path_leaf(raw_name);
		var lower_text = string_lower(name_text);

		/* Only a trailing .png extension after a nonempty stem is removed */
		if (string_length(lower_text) > 4
		&& string_copy(lower_text, string_length(lower_text) - 3, 4) == ".png")
		{
			return string_copy(name_text, 1, string_length(name_text) - 4);
		}

		return name_text;
	}

	/// @description Apply the active builtin or custom source filter, accepting all sources on other tabs
	/// @param {Struct} entry Library entry to inspect
	/// @returns {Bool} Whether the entry belongs to the active library tab
	entry_matches_tab = function(entry)
	{
		/* The active library category chooses which source types are visible */
		switch (library_tab)
		{
			/* Built-in filtering keeps only records with builtin source */
			case "builtin":
				return entry.source == "builtin";

			/* Custom filtering keeps only records with custom source */
			case "custom":
				return entry.source == "custom";
		}

		return true;
	}

	/// @description Collect original library indices matching the active source tab
	/// @returns {Array} New array of zero-based entries indices in library order
	library_filtered_indices = function()
	{
		/* filtered starts empty and accumulates original library indices rather than copying entry
		resources */
		var filtered = [];

		/* entry_index visits every discovered stamp record for category filtering */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			/* Append indices matching the current category, preserving their original library order */
			if (entry_matches_tab(entries[entry_index]))
			{
				filtered[array_length(filtered)] = entry_index;
			}
		}

		return filtered;
	}

	/// @description Calculate the largest row offset for the filtered six-column, two-row thumbnail grid
	/// @returns {Real} Nonnegative maximum library scroll row
	library_max_scroll = function()
	{
		/* filtered is the current category's indices, grid_cols is six thumbnails per row and
		visible_rows is the two-row page capacity */
		var filtered = library_filtered_indices();
		var grid_cols = 6;
		var visible_rows = 2;
		return max(0, ceil(array_length(filtered) / grid_cols) - visible_rows);
	}

	/// @description Select a source tab and clamp the existing scroll offset to its filtered entries
	/// @param {String} tab_key Source tab identity
	/// @returns {Bool} Always true after storing the tab
	set_library_tab = function(tab_key)
	{
		library_tab = string(tab_key);
		library_scroll = clamp(library_scroll, 0, library_max_scroll());
		return true;
	}

	/// @description Close the library modal and clear its identity, label, input focus, and keyboard text
	/// @returns {Bool} Always true after resetting modal state
	cancel_library_modal = function()
	{
		library_modal = "";
		library_modal_key = "";
		library_modal_label = "";
		library_size_focus = "";
		keyboard_string = "";
		return true;
	}

	/// @description Open the new-canvas size modal with the manager's default dimensions and cleared input text
	/// @returns {Bool} Always true after initializing the size modal
	begin_size_picker = function()
	{
		library_modal = "size";
		library_modal_key = "";
		library_modal_label = "";
		library_size_w_text = string(stamp_w);
		library_size_h_text = string(stamp_h);
		library_size_focus = "";
		keyboard_string = "";
		return true;
	}

	/// @description Open the rename modal for the selected custom entry and preload its label
	/// @returns {Bool} Whether a custom selection was available and the modal opened
	begin_rename_selected = function()
	{
		refresh();

		/* entry borrows the currently selected record for rename eligibility and initial text */
		var entry = selected_entry();

		/* An empty selection cannot start a rename dialog */
		if (entry == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* Only custom installations can be renamed, preserving bundled manifest names */
		if (entry.source != "custom")
		{
			set_status("Built-in stamps cannot be renamed.", make_color_rgb(255, 220, 95));
			return false;
		}

		library_modal = "rename";
		library_modal_key = entry.key;
		library_modal_label = entry.label;
		keyboard_string = entry.label;
		return true;
	}

	/// @description Open a deletion confirmation modal for the selected custom entry
	/// @returns {Bool} Whether a custom selection was available and the modal opened
	begin_delete_confirm = function()
	{
		refresh();

		/* entry is the selected record used to label the deletion confirmation */
		var entry = selected_entry();

		/* An empty selection cannot open a meaningful deletion confirmation */
		if (entry == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* Only custom installations can be removed, preserving bundled stamp assets */
		if (entry.source != "custom")
		{
			set_status("Built-in stamps cannot be deleted.", make_color_rgb(255, 220, 95));
			return false;
		}

		library_modal = "delete";
		library_modal_key = entry.key;
		library_modal_label = entry.label;
		keyboard_string = "";
		return true;
	}

	/// @description Update a selected custom label in memory and attempt to persist it, refreshing after successful persistence
	/// @param {String} new_label Nonempty desired display label
	/// @returns {Bool} Whether persistence succeeded, with the in-memory label already changed when persistence fails
	rename_selected_custom = function(new_label)
	{
		refresh();

		/* entry_index locates the selected record before changing its saved display name */
		var entry_index = selected_entry_index();

		/* Without a selected entry there is no display metadata to rename */
		if (entry_index == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* entry retains the selected record while its label and update timestamp change */
		var entry = entries[entry_index];

		/* A bundled source cannot receive custom installation name changes */
		if (entry.source != "custom")
		{
			set_status("Built-in stamps cannot be renamed.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* clean_label trims the requested display name before persistence */
		var clean_label = string_trim(string(new_label));

		/* Reject a blank display name so the installed stamp remains identifiable */
		if (clean_label == "")
		{
			set_status("Stamp name cannot be blank.", make_color_rgb(244, 84, 84));
			return false;
		}

		entry.label = clean_label;
		entry.updated_at = stamp_timestamp();
		entries[entry_index] = entry;

		/* Browser renaming persists the changed label and timestamp in the shared custom index */
		if (uses_browser_storage())
		{
			/* A failed browser index write reports unsuccessful rename persistence */
			if (!write_browser_index())
			{
				set_status("Could not write stamp browser index.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		/* Native renaming writes the package's configuration without replacing its PNG */
		else
		{
			/* folder_key removes the custom prefix and sanitizes the installation basename used by the
			metadata writer */
			var folder_key = safe_folder_key(string_replace_all(entry.key, custom_prefix, ""));

			/* A failed package configuration write reports unsuccessful rename persistence */
			if (!write_desktop_config(entry.package_path, folder_key, entry.label, entry.created_at, entry.updated_at, entry_stamp_w(entry), entry_stamp_h(entry)))
			{
				set_status("Could not write stamp config.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		set_status("Renamed stamp to " + clean_label + ".", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Install an independent custom copy of the selected stamp, preferring its original PNG payload
	/// @returns {Bool} Whether the selected stamp was successfully duplicated
	duplicate_selected_stamp = function()
	{
		refresh();

		/* entry_index locates the selected record for a new custom duplicate */
		var entry_index = selected_entry_index();

		/* An empty library cannot provide a source image to duplicate */
		if (entry_index == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* entry retains the selected image's payload and dimensions */
		var entry = entries[entry_index];

		/* A deferred PNG needs an explicit load before its original image can be duplicated */
		if (entry_can_lazy_load_png(entry))
		{
			/* A failed source load stops duplication before creating a custom installation */
			if (!ensure_entry_png_payload(entry_index, false, true))
			{
				set_status("Could not load built-in stamp PNG.", make_color_rgb(244, 84, 84));
				return false;
			}
			entry = entries[entry_index];
		}

		/* Prefer the original PNG payload for duplication, preserving its exact source image data */
		if (entry_has_png_payload(entry))
		{
			return install_custom_base64(entry.base64, entry.label + " Copy", entry_stamp_w(entry), entry_stamp_h(entry), "");
		}

		/* Without original PNG data, complete editable hex pixels can still produce the duplicate */
		if (entry_has_editable_pixels(entry))
		{
			return install_custom_hex(entry.hex, entry.label + " Copy", entry_stamp_w(entry), entry_stamp_h(entry), "");
		}

		set_status("Stamp data is invalid.", make_color_rgb(244, 84, 84));
		return false;
	}

	/// @description Check PNG size and import limits, then store large images as PNG payloads or smaller images as editable pixels
	/// @param {String} base64_text Complete PNG encoded as base64
	/// @param {String} label_text Display name used for the new custom entry
	/// @returns {Bool} Whether a custom stamp was installed
	import_png_base64 = function(base64_text, label_text)
	{
		/* Reject encoded text longer than the base64 envelope of the 2-MiB import limit before
		decoding it */
		if (string_length(string(base64_text)) > ceil(stamp_max_import_bytes / 3) * 4)
		{
			set_status(stamp_import_limits_text(), make_color_rgb(244, 84, 84));
			return false;
		}

		/* decoded_buffer starts without an owned handle, png_w/h start zero, info_ok starts false, and
		info_message starts empty until decode/header checks resolve them */
		var decoded_buffer = noone;
		var png_w = 0;
		var png_h = 0;
		var info_ok = false;
		var info_message = "";
		try
		{
			decoded_buffer = buffer_base64_decode(string(base64_text));

			/* An undefined or missing decoded buffer reports unavailable PNG bytes instead of
			inspecting its header */
			if (is_undefined(decoded_buffer) || !buffer_exists(decoded_buffer))
			{
				info_message = "Could not decode stamp PNG.";
			}

			/* A live decoded allocation can provide byte size and PNG header dimensions */
			else
			{
				/* png_info reports decoded PNG dimensions and header validity without taking buffer
				ownership */
				var png_info = png_dimensions_from_buffer(decoded_buffer);

				/* An actual decoded allocation above the 2-MiB limit is rejected even if its encoded
				length passed the initial check */
				if (buffer_get_size(decoded_buffer) > stamp_max_import_bytes)
				{
					info_message = stamp_import_limits_text();
				}

				/* A malformed PNG header propagates its inspection diagnostic */
				else if (!png_info.ok)
				{
					info_message = png_info.message;
				}

				/* A valid header within the byte limit supplies source dimensions and marks inspection
				successful */
				else
				{
					png_w = png_info.png_w;
					png_h = png_info.png_h;
					info_ok = true;
				}

			}
		}
		catch(e)
		{
			info_message = "Could not read stamp PNG: " + string(e.message);
		}

		/* Release this import's locally owned decoded buffer after header inspection or an exception */
		if (!is_undefined(decoded_buffer) && buffer_exists(decoded_buffer))
		{
			buffer_delete(decoded_buffer);
		}

		/* A failed inspection returns a diagnostic and creates no custom stamp */
		if (!info_ok)
		{
			/* Use the specific inspection message when nonempty, otherwise a general PNG-read failure */
			set_status(info_message == "" ? "Could not read stamp PNG." : info_message, make_color_rgb(244, 84, 84));
			return false;
		}

		/* Imported source dimensions must fit both the 4096-pixel per-side limit and total
		4194304-pixel limit */
		if (!stamp_import_size_is_supported(png_w, png_h))
		{
			set_status(stamp_import_limits_text(), make_color_rgb(244, 84, 84));
			return false;
		}

		/* Images beyond editable decoding limits retain their original PNG as image-only custom stamps */
		if (!stamp_can_decode_to_editable_pixels(png_w, png_h))
		{
			return install_custom_base64(base64_text, label_text, png_w, png_h, "");
		}

		/* hex_text is the decoded row-major RGBA data for an image small enough to enter pixel editing */
		var hex_text = base64_to_hex(base64_text, png_w, png_h);

		/* Reject insufficient decoded pixel data instead of installing an invalid editable canvas */
		if (!hex_is_valid_size(hex_text, png_w, png_h))
		{
			set_status("Imported stamp pixels are invalid.", make_color_rgb(244, 84, 84));
			return false;
		}

		return install_custom_hex(hex_text, label_text, png_w, png_h, "");
	}

	/// @description Start a browser PNG picker or synchronously read and install a native PNG selection
	/// @returns {Bool} Whether a browser import started or a native PNG was installed
	import_png_from_dialog = function()
	{
		/* Browser builds open the asynchronous PNG picker rather than the desktop file dialog */
		if (uses_browser_storage())
		{
			/* A pending browser request prevents opening a second import picker */
			if (browser_import_pending)
			{
				set_status("Stamp PNG import is already open.", make_color_rgb(255, 220, 95));
				return false;
			}

			try
			{
				/* start_result is the browser extension's picker-start outcome */
				var start_result = html5_stamp_import_start();

				/* Status 1 marks an active import request and asks the user to choose a PNG */
				if (start_result == 1)
				{
					browser_import_pending = true;
					set_status("Choose a stamp PNG to import.", make_color_rgb(255, 220, 95));
					return true;
				}
			}
			catch(e)
			{
				set_status("Browser stamp import is unavailable.", make_color_rgb(244, 84, 84));
				return false;
			}

			set_status("Could not open browser stamp import.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* linux_cache_path is the readable save-area copy for desktop picking, picked_file captures
		its outcome, and import_path is the selected path this reader can access */
		var linux_cache_path = path_join(string(game_save_id), "linux_stamp_import.png");
		var picked_file = scr_desktop_pick_png(linux_cache_path);
		var import_path = picked_file.readable_path;

		/* An empty readable path means selection was cancelled or yielded no accessible file */
		if (string(import_path) == "")
		{
			set_status("Stamp import cancelled.", make_color_rgb(178, 178, 184));
			return false;
		}

		/* png_result inspects source limits and captures the selected PNG's original encoded data */
		var png_result = read_png_base64(import_path);

		/* An invalid or unreadable picked image reports its diagnostic before installing anything */
		if (!png_result.ok)
		{
			set_status(png_result.message, make_color_rgb(244, 84, 84));
			return false;
		}

		return import_png_base64(png_result.base64, strip_png_extension(picked_file.selected_path));
	}

	/// @description Poll a pending browser picker, install completed PNG data, and clear completed or failed import state
	/// @returns {Bool} Whether the picker remains pending or a completed import installed successfully
	update_browser_import = function()
	{
		/* Without a pending browser picker, this poll has no import to process */
		if (!browser_import_pending)
		{
			return false;
		}

		/* import_status starts zero and is replaced by the extension's asynchronous picker state */
		var import_status = 0;
		try
		{
			import_status = html5_stamp_import_status();
		}
		catch(e)
		{
			browser_import_pending = false;
			set_status("Browser stamp import is unavailable.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* Status 1 leaves the picker pending and reports that its request remains active */
		if (import_status == 1)
		{
			return true;
		}

		browser_import_pending = false;

		/* Status 2 provides a chosen PNG for import and clears the extension state after capturing its
		data */
		if (import_status == 2)
		{
			/* import_name is the chosen filename and import_base64 retains its encoded PNG before
			clearing the picker result */
			var import_name = html5_stamp_import_name();
			var import_base64 = html5_stamp_import_base64();
			html5_stamp_import_clear();
			return import_png_base64(import_base64, strip_png_extension(import_name));
		}

		/* error_text starts with cancellation wording until a negative picker status supplies another
		diagnostic */
		var error_text = "Stamp import cancelled.";

		/* Negative completion statuses may provide an extension-specific import error */
		if (import_status < 0)
		{
			try { error_text = html5_stamp_import_error(); } catch(error_read) {}

			/* An empty extension diagnostic falls back to Stamp import failed */
			if (string_trim(error_text) == "")
			{
				error_text = "Stamp import failed.";
			}
		}

		try { html5_stamp_import_clear(); } catch(clear_error) {}

		/* Cancellation status -2 uses muted feedback, while other failed outcomes use the error colour */
		set_status(error_text, import_status == -2 ? make_color_rgb(178, 178, 184) : make_color_rgb(244, 84, 84));
		return false;
	}

	/// @description Resolve stamp_exports under game_save_id, falling back to temp_directory for an empty save root
	/// @returns {String} Normalized native export directory
	stamp_export_root_path = function()
	{
		/* root_text uses game_save_id when available or temp_directory otherwise, keeping desktop PNG
		exports in a writable stamp_exports folder */
		var root_text = string(game_save_id) == "" ? string(temp_directory) : string(game_save_id);
		return normalize_path(path_join(root_text, "stamp_exports"));
	}

	/// @description Export the selected stamp using a browser download or native PNG file, preferring original PNG bytes
	/// @returns {Bool} Whether the browser download was accepted or the native export succeeded
	export_selected_png = function()
	{
		refresh();

		/* entry_index resolves the current stamp for export */
		var entry_index = selected_entry_index();

		/* An empty selection cannot provide PNG data to export */
		if (entry_index == noone)
		{
			set_status("No stamp selected.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* Deferred images need an explicit original PNG load before export */
		if (entry_can_lazy_load_png(entries[entry_index]))
		{
			/* A failed source load stops export with an unavailable-image diagnostic */
			if (!ensure_entry_png_payload(entry_index, false, true))
			{
				set_status("Could not load built-in stamp PNG.", make_color_rgb(244, 84, 84));
				return false;
			}
		}

		/* entry supplies selected metadata, export_name includes label/size/timestamp, and
		export_base64 uses retained PNG data or starts empty for pixel encoding */
		var entry = entries[entry_index];
		var export_name = "JonnilOnline_Stamp_" + safe_folder_key(entry.label) + "_" + stamp_size_label(entry_stamp_w(entry), entry_stamp_h(entry)) + "_" + stamp_timestamp() + ".png";
		var export_base64 = entry_has_png_payload(entry) ? string(entry.base64) : "";

		/* Browser export uses a PNG download instead of a native output directory */
		if (uses_browser_storage())
		{
			/* Without original PNG bytes, encode the selected RGBA data for browser download */
			if (string_trim(export_base64) == "")
			{
				/* base64_result is the browser encoder's success state, encoded PNG and diagnostic */
				var base64_result = hex_to_png_base64_browser(entry.hex, entry_stamp_w(entry), entry_stamp_h(entry));

				/* A failed encode prevents downloading an empty or invalid image */
				if (!base64_result.ok)
				{
					set_status(base64_result.message, make_color_rgb(244, 84, 84));
					return false;
				}

				export_base64 = base64_result.base64;
			}

			try
			{
				/* The browser extension's return value 1 confirms the download action was initiated
				successfully */
				if (html5_download_base64_png(export_name, export_base64) == 1)
				{
					set_status("Exported " + entry.label + ".", make_color_rgb(126, 245, 150));
					return true;
				}
			}
			catch(e)
			{
				set_status("Browser stamp export is unavailable.", make_color_rgb(244, 84, 84));
				return false;
			}

			set_status("Could not download stamp PNG.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* export_root is the desktop stamp_exports directory */
		var export_root = stamp_export_root_path();

		/* The export directory must exist before writing a selected image file */
		if (!ensure_folder(export_root))
		{
			set_status("Could not create stamp export folder.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* export_path combines that writable directory and the timestamped PNG filename */
		var export_path = path_join(export_root, export_name);

		/* When original PNG base64 exists, save those bytes directly to preserve the source image */
		if (string_trim(export_base64) != "")
		{
			/* save_result records whether decoding and writing those original bytes succeeded */
			var save_result = save_base64_png_file(export_base64, export_path);

			/* A failed original-byte save propagates its diagnostic and reports no successful export */
			if (!save_result.ok)
			{
				set_status(save_result.message, make_color_rgb(244, 84, 84));
				return false;
			}
		}

		/* Without original PNG data, editable hex must successfully encode to the destination file */
		else if (!write_hex_to_png(entry.hex, export_path, entry_stamp_w(entry), entry_stamp_h(entry)))
		{
			set_status("Could not export stamp PNG.", make_color_rgb(244, 84, 84));
			return false;
		}

		set_status("Exported stamp PNG to stamp_exports.", make_color_rgb(126, 245, 150));
		return true;
	}
	#endregion /* Library Actions and PNG Transfer END */

	#region /* Library and Editor Geometry */
	/// @description Derive the anchored library panel bounds while keeping the panel within GUI margins
	/// @returns {Struct} left, top, right, bottom, panel_w, and panel_h in GUI pixels
	library_rect = function()
	{
		/* gui_w/h measure the available GUI space. panel_w/h fix the library at 456 by 320 units and
		panel_left/top place it below the toolbar anchor within GUI margins */
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var panel_w = 456;
		var panel_h = 320;
		var panel_left = clamp(panel_anchor_left, 4, max(4, gui_w - panel_w - 4));
		var panel_top = clamp(panel_anchor_top + panel_anchor_h + 12, 4, max(4, gui_h - panel_h - 4));

		/* The returned library bounds contain left/top/right/bottom edges and panel_w/panel_h
		dimensions in GUI coordinates */
		return { left: panel_left, top: panel_top, right: panel_left + panel_w, bottom: panel_top + panel_h, panel_w: panel_w, panel_h: panel_h };
	}

	/// @description Position the close control in the library panel's top-right corner
	/// @returns {Struct} left, top, right, and bottom in GUI pixels
	library_close_button_rect = function()
	{
		/* panel_rect anchors the close button, button_size is 22 GUI units and button_margin is its
		five-unit inset from the header edge */
		var panel_rect = library_rect();
		var button_size = 22;
		var button_margin = 5;

		/* The close-control rectangle uses GUI edge coordinates for shared hit testing and rendering */
		return
		{
			left: panel_rect.right - button_margin - button_size,
			top: panel_rect.top + button_margin,
			right: panel_rect.right - button_margin,
			bottom: panel_rect.top + button_margin + button_size
		};
	}

	/// @description Position a library source tab using its ordered tab index
	/// @param {String} tab_key Tab identity from library_tab_keys
	/// @returns {Struct} left, top, right, and bottom in GUI pixels
	library_tab_rect = function(tab_key)
	{
		/* panel_rect anchors category tabs. tab_w/h size each control, tab_gap spaces them, and
		tab_index starts at the first tab until its key is found */
		var panel_rect = library_rect();
		var tab_w = 70;
		var tab_h = 22;
		var tab_gap = 6;
		var tab_index = 0;

		/* key_index visits category keys to locate this tab's zero-based position */
		for (var key_index = 0; key_index < array_length(library_tab_keys); key_index++)
		{
			/* The requested category key selects its tab index and ends lookup */
			if (library_tab_keys[key_index] == tab_key)
			{
				tab_index = key_index;
				break;
			}
		}

		/* tab_left offsets this indexed tab from the panel's left edge and tab_top aligns the tab row
		below the header */
		var tab_left = panel_rect.left + 10 + tab_index * (tab_w + tab_gap);
		var tab_top = panel_rect.top + 38;

		/* The tab rectangle returns its GUI left/top/right/bottom edges */
		return { left: tab_left, top: tab_top, right: tab_left + tab_w, bottom: tab_top + tab_h };
	}

	/// @description Position an upward or downward library-row scroll control
	/// @param {String} button_key Scroll control identity
	/// @returns {Struct} left, top, right, and bottom in GUI pixels
	library_scroll_button_rect = function(button_key)
	{
		/* panel_rect anchors scrolling controls. button_w/h measure their GUI dimensions and
		button_left/top start at the upper-right row */
		var panel_rect = library_rect();
		var button_w = 54;
		var button_h = 22;
		var button_left = panel_rect.right - button_w - 14;
		var button_top = panel_rect.top + 70;

		/* The downward scroll key shifts its control below the upper arrow with a six-unit gap */
		if (button_key == "scroll_down")
		{
			button_top += button_h + 6;
		}

		/* Return this scroll control's GUI edge rectangle */
		return { left: button_left, top: button_top, right: button_left + button_w, bottom: button_top + button_h };
	}

	/// @description Position a named library action in its authored button row
	/// @param {String} button_key Action identity used by library input and drawing
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown action
	library_button_rect = function(button_key)
	{
		/* panel_rect anchors library action controls. button_top starts above the panel bottom,
		button_w/h size controls, gap spaces columns, and button_index/row start at the first
		control */
		var panel_rect = library_rect();
		var button_top = panel_rect.bottom - 62;
		var button_h = 24;
		var button_w = 76;
		var gap = 6;
		var button_index = 0;
		var button_row = 0;

		/* The action key selects a column in the first or second action row */
		switch (button_key)
		{
			/* New occupies first-row column zero */
			case "new":
				button_index = 0;
				break;

			/* Edit occupies first-row column one */
			case "edit":
				button_index = 1;
				break;

			/* Rename occupies first-row column two */
			case "rename":
				button_index = 2;
				break;

			/* Duplicate occupies first-row column three */
			case "duplicate":
				button_index = 3;
				break;

			/* Delete occupies second-row column zero */
			case "delete":
				button_index = 0;
				button_row = 1;
				break;

			/* Import occupies second-row column one */
			case "import":
				button_index = 1;
				button_row = 1;
				break;

			/* Export occupies second-row column two */
			case "export":
				button_index = 2;
				button_row = 1;
				break;

			/* An unsupported library action has an empty zero-edge rectangle */
			default:
				return { left: 0, top: 0, right: 0, bottom: 0 };
		}

		/* button_left converts the selected column to GUI x and row_top offsets the selected action
		row vertically */
		var button_left = panel_rect.left + 10 + button_index * (button_w + gap);
		var row_top = button_top + button_row * (button_h + 6);

		/* Return the final action control's GUI edge rectangle */
		return { left: button_left, top: row_top, right: button_left + button_w, bottom: row_top + button_h };
	}

	/// @description Hit-test visible filtered thumbnails against a GUI pointer position
	/// @param {Real} gui_x Horizontal pointer position in GUI pixels
	/// @param {Real} gui_y Vertical pointer position in GUI pixels
	/// @returns {Real} Zero-based original entries index, or noone outside visible thumbnails
	library_entry_index_at = function(gui_x, gui_y)
	{
		/* panel_rect anchors thumbnail hit testing. thumb_size is a 42-unit square, gap spaces
		columns, grid_left/top anchor six columns and two visible rows, and filtered maps category
		positions to library indices */
		var panel_rect = library_rect();
		var thumb_size = 42;
		var gap = 8;
		var grid_left = panel_rect.left + 12;
		var grid_top = panel_rect.top + 72;
		var grid_cols = 6;
		var visible_rows = 2;
		var filtered = library_filtered_indices();
		library_scroll = clamp(library_scroll, 0, library_max_scroll());

		/* visible_index visits at most twelve visible thumbnail positions after applying the current
		row scroll */
		for (var visible_index = 0; visible_index < min(array_length(filtered), grid_cols * visible_rows); visible_index++)
		{
			/* absolute_index maps this visible slot into the category-filtered array */
			var absolute_index = visible_index + library_scroll * grid_cols;

			/* Stop when the scrolled slot exceeds the filtered list rather than reading a nonexistent
			thumbnail */
			if (absolute_index >= array_length(filtered))
			{
				break;
			}

			/* entry_index is the underlying library index. entry_col/row are page-relative positions
			and thumb_left/top are the image square's GUI location */
			var entry_index = filtered[absolute_index];
			var entry_col = visible_index mod grid_cols;
			var entry_row = floor(visible_index / grid_cols);
			var thumb_left = grid_left + entry_col * (thumb_size + gap);
			var thumb_top = grid_top + entry_row * (thumb_size + 28);

			/* A pointer inside this thumbnail square returns its underlying library index */
			if (point_in_rect(gui_x, gui_y, thumb_left, thumb_top, thumb_left + thumb_size, thumb_top + thumb_size))
			{
				return entry_index;
			}
		}

		return noone;
	}

	/// @description Center the library modal within the GUI and apply its minimum margins
	/// @returns {Struct} left, top, right, bottom, modal_w, and modal_h in GUI pixels
	library_modal_rect = function()
	{
		/* panel_rect anchors the modal. Size selection reserves a larger 414 by 186 dialog, while
		rename/deletion use 298 by 132, and modal_left/top center it over the panel */
		var panel_rect = library_rect();
		var modal_w = library_modal == "size" ? 414 : 298;
		var modal_h = library_modal == "size" ? 186 : 132;
		var modal_left = panel_rect.left + panel_rect.panel_w * 0.5 - modal_w * 0.5;
		var modal_top = panel_rect.top + panel_rect.panel_h * 0.5 - modal_h * 0.5;

		/* Return modal GUI edges plus modal_w/h for both rendering and hit testing */
		return { left: modal_left, top: modal_top, right: modal_left + modal_w, bottom: modal_top + modal_h, modal_w: modal_w, modal_h: modal_h };
	}

	/// @description Position a named size-preset or confirmation button within the library modal
	/// @param {String} button_key Modal action identity
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown action
	library_modal_button_rect = function(button_key)
	{
		/* modal_rect anchors library dialog buttons and button_w/h size the preset controls */
		var modal_rect = library_modal_rect();
		var button_w = 78;
		var button_h = 24;

		/* The dialog control key chooses its GUI rectangle */
		switch (button_key)
		{
			/* The 16-pixel preset uses the first preset column */
			case "size_16":
				return { left: modal_rect.left + 16, top: modal_rect.top + 58, right: modal_rect.left + 16 + button_w, bottom: modal_rect.top + 58 + button_h };

			/* The 32-pixel preset uses the second preset column */
			case "size_32":
				return { left: modal_rect.left + 110, top: modal_rect.top + 58, right: modal_rect.left + 110 + button_w, bottom: modal_rect.top + 58 + button_h };

			/* The 48-pixel preset uses the third preset column */
			case "size_48":
				return { left: modal_rect.left + 204, top: modal_rect.top + 58, right: modal_rect.left + 204 + button_w, bottom: modal_rect.top + 58 + button_h };

			/* Custom Create uses the lower-right confirmation position */
			case "custom_create":
				return { left: modal_rect.right - 184, top: modal_rect.bottom - 34, right: modal_rect.right - 104, bottom: modal_rect.bottom - 10 };

			/* Rename/Delete confirmation uses the same lower-right action position */
			case "confirm":
				return { left: modal_rect.right - 184, top: modal_rect.bottom - 34, right: modal_rect.right - 104, bottom: modal_rect.bottom - 10 };

			/* Cancel uses the dialog's final right-side control */
			case "cancel":
				return { left: modal_rect.right - 94, top: modal_rect.bottom - 34, right: modal_rect.right - 14, bottom: modal_rect.bottom - 10 };
		}

		/* An unknown modal control returns an empty rectangle */
		return { left: 0, top: 0, right: 0, bottom: 0 };
	}

	/// @description Position the new-canvas width or height input field
	/// @param {String} input_key Width or height field identity
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown field
	library_size_input_rect = function(input_key)
	{
		/* modal_rect anchors numeric size fields. input_w/h measure their GUI dimensions and input_top
		aligns the custom size row */
		var modal_rect = library_modal_rect();
		var input_w = 72;
		var input_h = 24;
		var input_top = modal_rect.top + 112;

		/* The input key chooses the width or height field's GUI rectangle */
		switch (input_key)
		{
			/* Width occupies the first numeric field */
			case "w":
				return { left: modal_rect.left + 84, top: input_top, right: modal_rect.left + 84 + input_w, bottom: input_top + input_h };

			/* Height occupies the second numeric field */
			case "h":
				return { left: modal_rect.left + 214, top: input_top, right: modal_rect.left + 214 + input_w, bottom: input_top + input_h };
		}

		/* An unknown input key has no visible numeric rectangle */
		return { left: 0, top: 0, right: 0, bottom: 0 };
	}

	/// @description Size and position the stamp editor around its viewport and side controls
	/// @returns {Struct} left, top, right, bottom, modal_w, and modal_h in GUI pixels
	editor_rect = function()
	{
		/* gui_w/h give available GUI dimensions and grid_metrics describes the current visible canvas */
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var grid_metrics = editor_grid_metrics();

		/* left_column_w reserves at least 360 units for the canvas-side controls. modal_w/h include
		the viewport and tool column, and modal_left/top center the editor with a four-unit margin */
		var left_column_w = max(grid_metrics.viewport_w, 360);
		var modal_w = max(586, 18 + left_column_w + 38 + 168 + 18);
		var modal_h = min(max(360, gui_h - 8), max(650, 58 + grid_metrics.viewport_h + 208));
		var modal_left = max(4, gui_w * 0.5 - modal_w * 0.5);
		var modal_top = max(4, gui_h * 0.5 - modal_h * 0.5);

		/* The editor rectangle reports GUI edges and modal dimensions used by its controls */
		return { left: modal_left, top: modal_top, right: modal_left + modal_w, bottom: modal_top + modal_h, modal_w: modal_w, modal_h: modal_h };
	}

	/// @description Calculate zoomed cell size and the canvas portion that fits the current GUI viewport
	/// @returns {Struct} cell_size, visible_cols, visible_rows, pixel_w, pixel_h, viewport_w, and viewport_h
	editor_grid_metrics = function()
	{
		/* gui_w/h bound editor layout. open_editor_w/h use the active canvas dimensions or the default
		32-pixel canvas while closed */
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var open_editor_w = editor_open && is_struct(editor) ? max(1, floor(real(editor.grid_w))) : stamp_w;
		var open_editor_h = editor_open && is_struct(editor) ? max(1, floor(real(editor.grid_h))) : stamp_h;

		/* base_cell_size chooses a 6 to 10 unit base source-cell enlargement. max_view_w/h reserve GUI
		space for the tool column and lower controls */
		var base_cell_size = max(6, min(10, floor(min(420 / open_editor_w, 420 / open_editor_h))));
		var max_view_w = min(720, max(160, gui_w - 8 - 18 - 38 - 168 - 18));
		var max_view_h = min(520, max(128, gui_h - 8 - 58 - 208));

		/* cell_size applies the bounded zoom percentage to that base enlargement and is limited to the
		available viewport */
		var cell_size = max(1, floor(base_cell_size * clamp(editor_zoom_percent, editor_zoom_min, editor_zoom_max) / 100));
		cell_size = min(cell_size, max(1, min(max_view_w, max_view_h)));

		/* visible_cols and visible_rows count whole source cells fitting within the viewport, capped
		at canvas dimensions */
		var visible_cols = min(open_editor_w, max(1, floor(max_view_w / cell_size)));
		var visible_rows = min(open_editor_h, max(1, floor(max_view_h / cell_size)));

		/* Grid metrics return cell enlargement, visible source counts, visible pixel_w/h in GUI units,
		and the full viewport_w/h allocation */
		return
		{
			cell_size: cell_size,
			visible_cols: visible_cols,
			visible_rows: visible_rows,
			pixel_w: visible_cols * cell_size,
			pixel_h: visible_rows * cell_size,
			viewport_w: max_view_w,
			viewport_h: max_view_h
		};
	}

	/// @description Reserve enough GUI width for the viewport and the editor's lower canvas controls
	/// @returns {Real} Left-column width in GUI pixels
	editor_left_column_w = function()
	{
		/* grid_rect provides the allocated viewport width used to size the editor's left column */
		var grid_rect = editor_grid_rect();
		return max(grid_rect.viewport_right - grid_rect.left, 360);
	}

	/// @description Position the side controls after the viewport column and its separating gap
	/// @returns {Real} Side-column left coordinate in GUI pixels
	editor_side_left = function()
	{
		/* modal_rect anchors the tool side column after the canvas column and its spacing */
		var modal_rect = editor_rect();
		return modal_rect.left + 18 + editor_left_column_w() + 38;
	}

	/// @description Place the colour controls below the editor's clear button
	/// @returns {Real} Colour-controls top coordinate in GUI pixels
	editor_colour_top = function()
	{
		return editor_button_rect("clear").bottom + 10;
	}

	/// @description Position visible canvas cells and expose the full viewport bounds used for panning controls
	/// @returns {Struct} GUI cell bounds, viewport_right, viewport_bottom, cell_size, visible_cols, and visible_rows
	editor_grid_rect = function()
	{
		/* modal_rect anchors the grid and grid_metrics gives visible counts, enlargement and allocated
		viewport size */
		var modal_rect = editor_rect();
		var grid_metrics = editor_grid_metrics();

		/* grid_left and grid_top position the visible canvas inside the editor header margins */
		var grid_left = modal_rect.left + 18;
		var grid_top = modal_rect.top + 58;

		/* The grid rectangle separates visible canvas edges from full viewport_right/bottom, and
		retains cell_size and visible source counts for input conversion */
		return
		{
			left: grid_left,
			top: grid_top,
			right: grid_left + grid_metrics.pixel_w,
			bottom: grid_top + grid_metrics.pixel_h,
			viewport_right: grid_left + grid_metrics.viewport_w,
			viewport_bottom: grid_top + grid_metrics.viewport_h,
			cell_size: grid_metrics.cell_size,
			visible_cols: grid_metrics.visible_cols,
			visible_rows: grid_metrics.visible_rows
		};
	}

	/// @description Keep the viewport's source-cell origin within the current canvas and visible-cell range
	/// @returns {Bool} Whether an open valid editor was available for clamping
	clamp_editor_view = function()
	{
		/* A closed or invalid editor resets panning to the first source cell and reports that no
		active view was clamped */
		if (!editor_open || !is_struct(editor))
		{
			editor_view_col = 0;
			editor_view_row = 0;
			return false;
		}

		/* grid_rect provides visible cell counts used to keep viewport offsets inside the source
		canvas */
		var grid_rect = editor_grid_rect();
		editor_view_col = clamp(floor(real(editor_view_col)), 0, max(0, editor.grid_w - grid_rect.visible_cols));
		editor_view_row = clamp(floor(real(editor_view_row)), 0, max(0, editor.grid_h - grid_rect.visible_rows));
		return true;
	}

	/// @description Add source-cell offsets to the viewport origin and clamp it to available canvas cells
	/// @param {Real} delta_col Horizontal movement in source columns
	/// @param {Real} delta_row Vertical movement in source rows
	/// @returns {Bool} Always true after applying the requested pan and attempting clamping
	pan_editor_view = function(delta_col, delta_row)
	{
		editor_view_col += floor(real(delta_col));
		editor_view_row += floor(real(delta_row));
		clamp_editor_view();
		return true;
	}

	/// @description Convert a GUI x coordinate into a source canvas column, clamped to the current editor
	/// @param {Real} gui_x Horizontal pointer coordinate in GUI pixels
	/// @param {Struct} grid_rect Current editor_grid_rect result
	/// @returns {Real} Zero-based source column
	editor_grid_col_from_gui = function(gui_x, grid_rect)
	{
		return clamp(editor_view_col + floor((gui_x - grid_rect.left) / max(1, grid_rect.cell_size)), 0, editor.grid_w - 1);
	}

	/// @description Convert a GUI y coordinate into a source canvas row, clamped to the current editor
	/// @param {Real} gui_y Vertical pointer coordinate in GUI pixels
	/// @param {Struct} grid_rect Current editor_grid_rect result
	/// @returns {Real} Zero-based source row
	editor_grid_row_from_gui = function(gui_y, grid_rect)
	{
		return clamp(editor_view_row + floor((gui_y - grid_rect.top) / max(1, grid_rect.cell_size)), 0, editor.grid_h - 1);
	}

	/// @description Choose the selection's left column, the pointer's canvas column, or the viewport origin for pasting
	/// @param {Real} gui_x Horizontal pointer coordinate in GUI pixels
	/// @param {Real} gui_y Vertical pointer coordinate in GUI pixels
	/// @param {Struct} grid_rect Current editor_grid_rect result
	/// @returns {Real} Zero-based source paste column
	editor_paste_target_col = function(gui_x, gui_y, grid_rect)
	{
		/* An active selection makes its left source boundary the paste destination column */
		if (is_struct(editor) && editor.selection_active)
		{
			return editor.selection_left;
		}

		/* Without a selection, a pointer over the visible grid supplies the destination source column */
		if (point_in_rect(gui_x, gui_y, grid_rect.left, grid_rect.top, grid_rect.right, grid_rect.bottom))
		{
			return editor_grid_col_from_gui(gui_x, grid_rect);
		}

		return editor_view_col;
	}

	/// @description Choose the selection's top row, the pointer's canvas row, or the viewport origin for pasting
	/// @param {Real} gui_x Horizontal pointer coordinate in GUI pixels
	/// @param {Real} gui_y Vertical pointer coordinate in GUI pixels
	/// @param {Struct} grid_rect Current editor_grid_rect result
	/// @returns {Real} Zero-based source paste row
	editor_paste_target_row = function(gui_x, gui_y, grid_rect)
	{
		/* An active selection makes its top source boundary the paste destination row */
		if (is_struct(editor) && editor.selection_active)
		{
			return editor.selection_top;
		}

		/* Without a selection, a pointer over the visible grid supplies the destination source row */
		if (point_in_rect(gui_x, gui_y, grid_rect.left, grid_rect.top, grid_rect.right, grid_rect.bottom))
		{
			return editor_grid_row_from_gui(gui_y, grid_rect);
		}

		return editor_view_row;
	}

	/// @description Format the clamped integer editor zoom with a percent suffix
	/// @returns {String} Current zoom label
	editor_zoom_text = function()
	{
		return string(clamp(floor(real(editor_zoom_percent)), editor_zoom_min, editor_zoom_max)) + "%";
	}

	/// @description Store a supported integer zoom and clamp the viewport after an actual zoom change
	/// @param {Real} raw_zoom_percent Requested percentage, clamped to the editor's zoom limits
	/// @returns {Bool} Whether the stored zoom changed
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

	/// @description Move to the next authored zoom level in the requested direction
	/// @param {Real} direction Positive to zoom in, negative to zoom out, or zero to retain the current level
	/// @returns {Bool} Whether a different zoom was stored
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

	/// @description Restore the editor's 100 percent zoom through the normal clamping path
	/// @returns {Bool} Whether zoom changed
	reset_editor_zoom = function()
	{
		return set_editor_zoom(100);
	}

	/// @description Test whether the entire current canvas fits the GUI viewport at a proposed zoom
	/// @param {Real} raw_zoom_percent Proposed percentage, truncated and clamped to zoom limits
	/// @returns {Bool} Whether both source dimensions fit, also true when no editor is open
	editor_canvas_fits_at_zoom = function(raw_zoom_percent)
	{
		/* With no active pixel canvas, this fit test has nothing to clip and returns true */
		if (!editor_open || !is_struct(editor))
		{
			return true;
		}

		/* gui_w/h bound the viewport and open_editor_w/h are the canvas's source-pixel dimensions */
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var open_editor_w = max(1, floor(real(editor.grid_w)));
		var open_editor_h = max(1, floor(real(editor.grid_h)));

		/* base_cell_size selects normal cell enlargement and max_view_w/h reserve GUI space for
		surrounding editor controls */
		var base_cell_size = max(6, min(10, floor(min(420 / open_editor_w, 420 / open_editor_h))));
		var max_view_w = min(720, max(160, gui_w - 8 - 18 - 38 - 168 - 18));
		var max_view_h = min(520, max(128, gui_h - 8 - 58 - 208));

		/* zoom_percent clamps the proposed percentage and cell_size computes its whole GUI source-cell
		enlargement */
		var zoom_percent = clamp(floor(real(raw_zoom_percent)), editor_zoom_min, editor_zoom_max);
		var cell_size = max(1, floor(base_cell_size * zoom_percent / 100));
		cell_size = min(cell_size, max(1, min(max_view_w, max_view_h)));

		/* visible_cols/rows count complete source cells fitting at this candidate zoom */
		var visible_cols = min(open_editor_w, max(1, floor(max_view_w / cell_size)));
		var visible_rows = min(open_editor_h, max(1, floor(max_view_h / cell_size)));

		/* A candidate zoom fits only when both visible source counts cover the entire canvas */
		return visible_cols >= open_editor_w
			&& visible_rows >= open_editor_h;
	}

	/// @description Find the largest authored zoom level that displays the entire canvas within the current viewport
	/// @returns {Real} Supported zoom percentage, falling back to the minimum zoom
	editor_best_fit_zoom = function()
	{
		/* best_zoom starts at the minimum allowed percentage in case no larger authored zoom fits */
		var best_zoom = editor_zoom_min;

		/* zoom_index visits authored levels in ascending order so the last fitting candidate becomes
		the largest full-canvas zoom */
		for (var zoom_index = 0; zoom_index < array_length(editor_zoom_levels); zoom_index++)
		{
			/* candidate_zoom is the current authored percentage tested against available viewport
			space */
			var candidate_zoom = editor_zoom_levels[zoom_index];

			/* Retain candidates covering the entire canvas without panning in either axis */
			if (editor_canvas_fits_at_zoom(candidate_zoom))
			{
				best_zoom = candidate_zoom;
			}
		}

		return clamp(best_zoom, editor_zoom_min, editor_zoom_max);
	}

	/// @description Choose the best fitting zoom for a newly opened editor and reset its viewport origin
	/// @returns {Bool} Always true after assigning zoom and clamping the viewport
	set_initial_editor_zoom = function()
	{
		editor_zoom_percent = editor_best_fit_zoom();
		editor_view_col = 0;
		editor_view_row = 0;
		clamp_editor_view();
		return true;
	}

	/// @description Position a named zoom-out, reset, or zoom-in control
	/// @param {String} button_key Zoom control identity
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown control
	editor_zoom_button_rect = function(button_key)
	{
		/* grid_rect anchors zoom buttons, button_h sizes their GUI height, button_gap separates them,
		and button_top/left start below the viewport */
		var grid_rect = editor_grid_rect();
		var button_h = 24;
		var button_gap = 6;
		var button_top = grid_rect.viewport_bottom + 10;
		var button_left = grid_rect.left;

		/* The zoom action key selects one control in the horizontal zoom row */
		switch (button_key)
		{
			/* Zoom Out occupies the leftmost 78-unit control */
			case "zoom_out":
				return { left: button_left, top: button_top, right: button_left + 78, bottom: button_top + button_h };

			/* No Zoom occupies the middle 72-unit control */
			case "zoom_reset":
				button_left += 78 + button_gap;
				return { left: button_left, top: button_top, right: button_left + 72, bottom: button_top + button_h };

			/* Zoom In occupies the final 78-unit control */
			case "zoom_in":
				button_left += 78 + button_gap + 72 + button_gap;
				return { left: button_left, top: button_top, right: button_left + 78, bottom: button_top + button_h };
		}

		/* An unknown zoom action has no visible control rectangle */
		return { left: 0, top: 0, right: 0, bottom: 0 };
	}

	/// @description Position a directional viewport control around the canvas viewport
	/// @param {String} button_key view_left, view_right, view_up, or view_down
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown direction
	editor_view_button_rect = function(button_key)
	{
		/* grid_rect anchors view arrows, button_size is 24 GUI units, button_gap spaces arrows, and
		button_top/left place them below zoom controls after the View label */
		var grid_rect = editor_grid_rect();
		var button_size = 24;
		var button_gap = 6;
		var button_top = editor_zoom_button_rect("zoom_out").bottom + 8;
		var button_left = grid_rect.left + 42;

		/* The view action chooses a left, up, down or right arrow position */
		switch (button_key)
		{
			/* Left uses the first arrow position */
			case "view_left":
				return { left: button_left, top: button_top, right: button_left + button_size, bottom: button_top + button_size };

			/* Up uses the second arrow position */
			case "view_up":
				button_left += button_size + button_gap;
				return { left: button_left, top: button_top, right: button_left + button_size, bottom: button_top + button_size };

			/* Down uses the third arrow position */
			case "view_down":
				button_left += (button_size + button_gap) * 2;
				return { left: button_left, top: button_top, right: button_left + button_size, bottom: button_top + button_size };

			/* Right uses the fourth arrow position */
			case "view_right":
				button_left += (button_size + button_gap) * 3;
				return { left: button_left, top: button_top, right: button_left + button_size, bottom: button_top + button_size };
		}

		/* An unknown view key returns an empty rectangle */
		return { left: 0, top: 0, right: 0, bottom: 0 };
	}

	/// @description Enable a directional pan control only when the viewport can move further along that axis
	/// @param {String} button_key view_left, view_right, view_up, or view_down
	/// @returns {Bool} Whether the direction has remaining offscreen source cells
	editor_view_button_enabled = function(button_key)
	{
		/* View movement is disabled without an open valid editor */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* grid_rect gives the currently visible source-cell counts used by pan boundary checks */
		var grid_rect = editor_grid_rect();

		/* The requested direction is enabled only when source cells remain beyond that viewport edge */
		switch (button_key)
		{
			/* Left panning requires a nonzero first visible source column */
			case "view_left":
				return editor_view_col > 0;

			/* Right panning requires columns beyond the visible right edge */
			case "view_right":
				return editor_view_col < max(0, editor.grid_w - grid_rect.visible_cols);

			/* Up panning requires a nonzero first visible source row */
			case "view_up":
				return editor_view_row > 0;

			/* Down panning requires rows beyond the visible bottom edge */
			case "view_down":
				return editor_view_row < max(0, editor.grid_h - grid_rect.visible_rows);
		}

		return false;
	}

	/// @description Show directional pan controls only when the canvas exceeds the viewport along their axis
	/// @param {String} button_key view_left, view_right, view_up, or view_down
	/// @returns {Bool} Whether that axis needs panning controls
	editor_view_button_should_show = function(button_key)
	{
		/* A closed or invalid editor needs no view controls */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* grid_rect supplies visible source counts for deciding whether each axis overflows */
		var grid_rect = editor_grid_rect();

		/* Direction groups show controls only for their corresponding overflowing source axis */
		switch (button_key)
		{
			/* Both horizontal arrows are relevant when visible columns do not cover the canvas width */
			case "view_left":
			case "view_right":
				return grid_rect.visible_cols < editor.grid_w;

			/* Both vertical arrows are relevant when visible rows do not cover the canvas height */
			case "view_up":
			case "view_down":
				return grid_rect.visible_rows < editor.grid_h;
		}

		return false;
	}

	/// @description Determine whether either canvas axis extends beyond the current viewport
	/// @returns {Bool} Whether any viewport controls should be displayed
	editor_view_controls_visible = function()
	{
		/* Any horizontal or vertical overflow makes the panning-control row necessary */
		return editor_view_button_should_show("view_left")
			|| editor_view_button_should_show("view_up");
	}

	/// @description Position a named editor tool or action in the side-column button layout
	/// @param {String} button_key Editor action identity
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown action
	editor_button_rect = function(button_key)
	{
		/* modal_rect anchors editor actions, button_w/h set ordinary control dimensions, button_left
		locates the tool column, top_value/tool_top start its first row, and tool_step spaces tools */
		var modal_rect = editor_rect();
		var button_w = 168;
		var button_h = 24;
		var button_left = editor_side_left();
		var top_value = modal_rect.top + 58;
		var tool_top = modal_rect.top + 58;
		var tool_step = 28;

		/* The action key chooses a tool/history row, a transform-grid position or a lower save/cancel
		control */
		switch (button_key)
		{
			/* Pen uses the first tool row */
			case "pen":
				top_value = tool_top;
				break;

			/* Eraser uses the second tool row */
			case "eraser":
				top_value = tool_top + tool_step;
				break;

			/* Fill uses the third tool row */
			case "fill":
				top_value = tool_top + tool_step * 2;
				break;

			/* Picker uses the fourth tool row */
			case "picker":
				top_value = tool_top + tool_step * 3;
				break;

			/* Select uses the fifth tool row */
			case "select":
				top_value = tool_top + tool_step * 4;
				break;

			/* Undo uses the sixth tool row */
			case "undo":
				top_value = tool_top + tool_step * 5;
				break;

			/* Redo uses the seventh tool row */
			case "redo":
				top_value = tool_top + tool_step * 6;
				break;

			/* Clear uses the eighth tool row */
			case "clear":
				top_value = tool_top + tool_step * 7;
				break;

			/* Flip, rotate and shift actions share the two-row transform grid below zoom and any
			panning controls */
			case "flip_h":
			case "flip_v":
			case "rotate_cw":
			case "rotate_ccw":
			case "shift_left":
			case "shift_right":
			case "shift_up":
			case "shift_down":
			{
				/* grid_rect anchors transforms. transform_keys fixes their order and transform_index
				starts at the first slot until this action is found */
				var grid_rect = editor_grid_rect();
				var transform_keys = ["flip_h", "flip_v", "rotate_ccw", "rotate_cw", "shift_left", "shift_right", "shift_up", "shift_down"];
				var transform_index = 0;

				/* key_index visits transform action keys to locate the requested control's zero-based
				slot */
				for (var key_index = 0; key_index < array_length(transform_keys); key_index++)
				{
					/* A matching transform key selects its slot and stops lookup */
					if (transform_keys[key_index] == button_key)
					{
						transform_index = key_index;
						break;
					}
				}

				/* transform_cols divides controls into four columns, transform_gap spaces them,
				transform_col/row locate this slot, and transform_w fits their width to the editor's
				left column */
				var transform_cols = 4;
				var transform_gap = 6;
				var transform_col = transform_index mod transform_cols;
				var transform_row = floor(transform_index / transform_cols);
				var transform_w = floor((editor_left_column_w() - transform_gap * (transform_cols - 1)) / transform_cols);
				button_w = transform_w;
				button_left = grid_rect.left + transform_col * (transform_w + transform_gap);

				/* transform_top starts below zoom controls before accounting for any visible panning
				row */
				var transform_top = editor_zoom_button_rect("zoom_out").bottom + 8;

				/* When view controls are shown, move transforms below them so their rectangles do not
				overlap */
				if (editor_view_controls_visible())
				{
					transform_top = editor_view_button_rect("view_left").bottom + 8;
				}
				top_value = transform_top + transform_row * (button_h + 6);
				break;
			}

			/* Save occupies the lower tool-column action above Cancel */
			case "save":
				top_value = modal_rect.bottom - 70;
				break;

			/* Cancel occupies the final lower tool-column action */
			case "cancel":
				top_value = modal_rect.bottom - 38;
				break;

			/* An unsupported editor action returns an empty rectangle */
			default:
				return { left: 0, top: 0, right: 0, bottom: 0 };
		}

		/* Return the selected editor action's GUI edge rectangle */
		return { left: button_left, top: top_value, right: button_left + button_w, bottom: top_value + button_h };
	}

	/// @description Position one RGB palette swatch beneath the colour sliders
	/// @param {Real} swatch_index Zero-based editor_colour_swatches index
	/// @returns {Struct} left, top, right, and bottom in GUI pixels
	editor_swatch_rect = function(swatch_index)
	{
		/* modal_rect borrows editor bounds, swatch_size_value and swatch_gap size the palette squares,
		swatch_col is its zero-based column, and swatch_left/top position it below the
		current-colour preview */
		var modal_rect = editor_rect();
		var swatch_size_value = 18;
		var swatch_gap = 5;
		var swatch_col = swatch_index mod 7;
		var swatch_left = editor_side_left() + swatch_col * (swatch_size_value + swatch_gap);
		var swatch_top = editor_colour_top() + 68;

		/* The swatch rectangle reports its GUI edges for shared drawing and hit testing */
		return { left: swatch_left, top: swatch_top, right: swatch_left + swatch_size_value, bottom: swatch_top + swatch_size_value };
	}

	/// @description Position a hue, saturation, or value slider in the colour-controls column
	/// @param {String} slider_key hue, saturation, or value
	/// @returns {Struct} GUI bounds and slider_w and slider_h, or zero bounds for an unknown component
	editor_hsv_slider_rect = function(slider_key)
	{
		/* modal_rect borrows editor bounds and slider_index starts at hue until the requested
		component is selected */
		var modal_rect = editor_rect();
		var slider_index = 0;

		/* The HSV key selects one of three slider rows */
		switch (slider_key)
		{
			/* Hue uses slider row zero */
			case "hue":
				slider_index = 0;
				break;

			/* Saturation uses slider row one */
			case "saturation":
				slider_index = 1;
				break;

			/* Value uses slider row two */
			case "value":
				slider_index = 2;
				break;

			/* An unknown HSV key has no slider rectangle */
			default:
				return { left: 0, top: 0, right: 0, bottom: 0 };
		}

		/* slider_left/top locate this component beneath the palette and slider_w/h measure its GUI
		gradient area */
		var slider_left = editor_side_left() + 24;
		var slider_top = editor_colour_top() + 108 + slider_index * 23;
		var slider_w = 144;
		var slider_h = 13;

		/* Return slider GUI edges plus gradient width/height used for mouse conversion and cache
		allocation */
		return { left: slider_left, top: slider_top, right: slider_left + slider_w, bottom: slider_top + slider_h, slider_w: slider_w, slider_h: slider_h };
	}

	/// @description Position the canvas width or height input beneath the viewport
	/// @param {String} input_key Width or height field identity
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown field
	editor_resize_input_rect = function(input_key)
	{
		/* grid_rect anchors resize inputs, input_w/h size each field and input_top places the row
		below the transform controls */
		var grid_rect = editor_grid_rect();
		var input_w = 58;
		var input_h = 24;
		var input_top = editor_button_rect("shift_down").bottom + 28;

		/* The dimension key selects its width or height field */
		switch (input_key)
		{
			/* Width uses the first resize field */
			case "w":
				return { left: grid_rect.left + 28, top: input_top, right: grid_rect.left + 28 + input_w, bottom: input_top + input_h };

			/* Height uses the second resize field */
			case "h":
				return { left: grid_rect.left + 132, top: input_top, right: grid_rect.left + 132 + input_w, bottom: input_top + input_h };
		}

		/* An unknown dimension key returns an empty resize rectangle */
		return { left: 0, top: 0, right: 0, bottom: 0 };
	}

	/// @description Position the apply-resize button beside the canvas dimension fields
	/// @returns {Struct} left, top, right, and bottom in GUI pixels
	editor_resize_apply_rect = function()
	{
		/* grid_rect anchors the resize Apply button and input_top aligns it with the numeric fields */
		var grid_rect = editor_grid_rect();
		var input_top = editor_button_rect("shift_down").bottom + 28;
		return { left: grid_rect.left + 220, top: input_top, right: grid_rect.left + 292, bottom: input_top + 24 };
	}

	/// @description Center the transparency settings modal using fixed dimensions and GUI margins
	/// @returns {Struct} left, top, right, bottom, modal_w, and modal_h in GUI pixels
	transparency_modal_rect = function()
	{
		/* editor_modal is the parent editor bounds, gui_w/h are available GUI dimensions, modal_w/h
		cap the transparency dialog, and modal_left/top center it within GUI margins */
		var editor_modal = editor_rect();
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var modal_w = min(520, gui_w - 24);
		var modal_h = min(300, gui_h - 24);
		var modal_left = clamp(editor_modal.left + editor_modal.modal_w * 0.5 - modal_w * 0.5, 12, max(12, gui_w - modal_w - 12));
		var modal_top = clamp(editor_modal.top + editor_modal.modal_h * 0.5 - modal_h * 0.5, 12, max(12, gui_h - modal_h - 12));

		/* Return transparency modal GUI edges and dimensions for its controls */
		return { left: modal_left, top: modal_top, right: modal_left + modal_w, bottom: modal_top + modal_h, modal_w: modal_w, modal_h: modal_h };
	}

	/// @description Position a transparency mode, colour, apply, or cancel control
	/// @param {String} button_key Transparency modal control identity
	/// @returns {Struct} GUI bounds, or zero bounds for an unknown control
	transparency_modal_button_rect = function(button_key)
	{
		/* rect is the transparency dialog rectangle used to place its controls */
		var rect = transparency_modal_rect();

		/* Each transparency action chooses a fixed GUI rectangle within this modal */
		switch (button_key)
		{
			/* Block mode occupies the upper mode selector */
			case "mode_block":
				return { left: rect.left + 18, top: rect.top + 52, right: rect.left + 150, bottom: rect.top + 76 };

			/* Single mode occupies the lower mode selector */
			case "mode_single":
				return { left: rect.left + 18, top: rect.top + 186, right: rect.left + 150, bottom: rect.top + 210 };

			/* The first checker colour uses the upper Use Current control */
			case "color_1_current":
				return { left: rect.right - 120, top: rect.top + 82, right: rect.right - 18, bottom: rect.top + 106 };

			/* The second checker colour uses the following Use Current control */
			case "color_2_current":
				return { left: rect.right - 120, top: rect.top + 118, right: rect.right - 18, bottom: rect.top + 142 };

			/* The single background colour uses its lower Use Current control */
			case "single_current":
				return { left: rect.right - 120, top: rect.top + 216, right: rect.right - 18, bottom: rect.top + 240 };

			/* OK occupies the lower confirmation position */
			case "ok":
				return { left: rect.right - 204, top: rect.bottom - 40, right: rect.right - 112, bottom: rect.bottom - 14 };

			/* Cancel occupies the final right-side action */
			case "cancel":
				return { left: rect.right - 102, top: rect.bottom - 40, right: rect.right - 18, bottom: rect.bottom - 14 };
		}

		/* An unknown transparency action returns an empty rectangle */
		return { left: 0, top: 0, right: 0, bottom: 0 };
	}

	/// @description Position the checkerboard block-size field in the transparency modal
	/// @returns {Struct} left, top, right, and bottom in GUI pixels
	transparency_block_size_input_rect = function()
	{
		/* rect anchors the checker block-size numeric field inside the transparency dialog */
		var rect = transparency_modal_rect();
		return { left: rect.left + 138, top: rect.top + 154, right: rect.left + 218, bottom: rect.top + 180 };
	}

	/// @description Hit-test the three editor HSV sliders
	/// @param {Real} gui_x Horizontal pointer position in GUI pixels
	/// @param {Real} gui_y Vertical pointer position in GUI pixels
	/// @returns {String} Component key, or empty outside all sliders
	editor_hsv_slider_key_at = function(gui_x, gui_y)
	{
		/* slider_keys fixes the hit-test order for hue, saturation and value */
		var slider_keys = ["hue", "saturation", "value"];

		/* slider_index visits all three HSV rectangles until a pointer hit is found */
		for (var slider_index = 0; slider_index < array_length(slider_keys); slider_index++)
		{
			/* slider_rect is this component's GUI area with four extra units above and below for
			easier pointer targeting */
			var slider_rect = editor_hsv_slider_rect(slider_keys[slider_index]);

			/* A pointer inside that expanded area returns the component key for its drag handler */
			if (point_in_rect(gui_x, gui_y, slider_rect.left, slider_rect.top - 4, slider_rect.right, slider_rect.bottom + 4))
			{
				return slider_keys[slider_index];
			}
		}

		return "";
	}

	/// @description Hit-test the editor's authored RGB palette swatches
	/// @param {Real} gui_x Horizontal pointer position in GUI pixels
	/// @param {Real} gui_y Vertical pointer position in GUI pixels
	/// @returns {Real} Zero-based swatch index, or noone outside the palette
	editor_swatch_index_at = function(gui_x, gui_y)
	{
		/* swatch_index visits every authored palette square for pointer hit testing */
		for (var swatch_index = 0; swatch_index < array_length(editor_colour_swatches); swatch_index++)
		{
			/* swatch_rect provides this preset's GUI bounds */
			var swatch_rect = editor_swatch_rect(swatch_index);

			/* A pointer inside the square returns its zero-based palette index */
			if (point_in_rect(gui_x, gui_y, swatch_rect.left, swatch_rect.top, swatch_rect.right, swatch_rect.bottom))
			{
				return swatch_index;
			}
		}

		return noone;
	}

	/// @description Map pointer x to a byte-scaled HSV component, recompute RGB, and request toolbar synchronization
	/// @param {String} slider_key hue, saturation, or value
	/// @param {Real} gui_x Horizontal pointer coordinate in GUI pixels
	/// @returns {Bool} Whether a recognized slider component was updated
	update_editor_hsv_slider_from_mouse = function(slider_key, gui_x)
	{
		/* slider_rect bounds the component and slider_value maps pointer x to a clamped 0 to 255 HSV
		value */
		var slider_rect = editor_hsv_slider_rect(slider_key);
		var slider_value = clamp(round((gui_x - slider_rect.left) / max(1, slider_rect.slider_w) * 255), 0, 255);

		/* The component key chooses which HSV field receives the pointer-derived value */
		switch (slider_key)
		{
			/* Hue input updates current_hue */
			case "hue":
				current_hue = slider_value;
				break;

			/* Saturation input updates current_saturation */
			case "saturation":
				current_saturation = slider_value;
				break;

			/* Value input updates current_value */
			case "value":
				current_value = slider_value;
				break;

			/* An unrecognized component rejects the update without changing RGB colour */
			default:
				return false;
		}

		return set_current_colour_from_hsv();
	}
	#endregion /* Library and Editor Geometry END */

	#region /* Stamp GUI Input */
	/// @description Route keyboard and pointer actions through library modals, tabs, thumbnails, and package operations
	/// @param {Bool} panel_active Whether ordinary library-panel input is enabled
	/// @returns {Bool} Whether a handled action or relevant panel or modal pointer region owns this input
	update_library_input = function(panel_active)
	{
		panel_hover = "";

		/* An inactive library panel relinquishes input before any hit testing */
		if (!panel_active)
		{
			return false;
		}

		refresh();

		/* gui_x and gui_y locate the pointer in GUI coordinates, panel_rect bounds the library and
		close_rect bounds its close control */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var panel_rect = library_rect();
		var close_rect = library_close_button_rect();

		/* Hovering the close rectangle highlights that control before any library modal consumes the
		pointer */
		if (point_in_rect(gui_x, gui_y, close_rect.left, close_rect.top, close_rect.right, close_rect.bottom))
		{
			panel_hover = "close";

			/* A fresh left click on Close cancels the current dialog and records a close request for
			the toolbar owner */
			if (mouse_check_button_pressed(mb_left))
			{
				cancel_library_modal();
				panel_close_requested = true;
				return true;
			}
		}

		/* An active library modal processes its text, confirmation and pointer controls before
		ordinary library selection */
		if (library_modal != "")
		{
			/* modal_rect supplies the dialog's GUI bounds for final input ownership testing */
			var modal_rect = library_modal_rect();

			/* The size dialog edits keyboard text only while one numeric dimension field owns focus */
			if (library_modal == "size" && library_size_focus != "")
			{
				/* Use width or height text according to library_size_focus so the shared keyboard
				buffer belongs to the active numeric field */
				scr_text_input_update("stamp_library_size_" + library_size_focus, library_size_focus == "w" ? library_size_w_text : library_size_h_text);

				/* clean_size_text removes nondigits from the active size input before updating its
				draft value */
				var clean_size_text = digits_only(keyboard_string);
				keyboard_string = clean_size_text;

				/* Width focus stores the cleaned draft in library_size_w_text */
				if (library_size_focus == "w")
				{
					library_size_w_text = clean_size_text;
				}

				/* Height focus stores the cleaned draft in library_size_h_text */
				else if (library_size_focus == "h")
				{
					library_size_h_text = clean_size_text;
				}
			}

			/* Escape dismisses the active library dialog and consumes the shortcut */
			if (keyboard_check_pressed(vk_escape))
			{
				cancel_library_modal();
				return true;
			}

			/* Enter in the size dialog commits clamped dimensions and opens a new pixel canvas */
			if (library_modal == "size" && keyboard_check_pressed(vk_enter))
			{
				/* enter_stamp_w and enter_stamp_h parse the two draft dimensions with the default
				canvas dimensions as fallbacks */
				var enter_stamp_w = stamp_dimension_from_text(library_size_w_text, stamp_w);
				var enter_stamp_h = stamp_dimension_from_text(library_size_h_text, stamp_h);
				cancel_library_modal();
				return begin_new_stamp(enter_stamp_w, enter_stamp_h);
			}

			/* The rename dialog owns the shared text input and copies its current keyboard text to the
			draft label */
			if (library_modal == "rename")
			{
				scr_text_input_update("stamp_library_rename", library_modal_label);
				library_modal_label = keyboard_string;
			}

			/* Enter in the rename dialog attempts to persist the typed display name */
			if (library_modal == "rename" && keyboard_check_pressed(vk_enter))
			{
				/* rename_result records whether the selected custom stamp's display name was saved */
				var rename_result = rename_selected_custom(keyboard_string);

				/* Dismiss the rename dialog only after a successful update so failed names can still
				be corrected */
				if (rename_result)
				{
					cancel_library_modal();
				}
				return true;
			}

			/* Enter in the deletion dialog performs the selected custom deletion and closes the
			confirmation */
			if (library_modal == "delete" && keyboard_check_pressed(vk_enter))
			{
				delete_selected_custom();
				cancel_library_modal();
				return true;
			}

			/* modal_keys selects size presets/Create/Cancel for a size dialog and Confirm/Cancel for
			rename or deletion */
			var modal_keys = library_modal == "size" ? ["size_16", "size_32", "size_48", "custom_create", "cancel"] : ["confirm", "cancel"];

			/* modal_key_index visits all controls available to the active library dialog */
			for (var modal_key_index = 0; modal_key_index < array_length(modal_keys); modal_key_index++)
			{
				/* modal_button_key identifies this control and modal_button_rect supplies its GUI hit
				bounds */
				var modal_button_key = modal_keys[modal_key_index];
				var modal_button_rect = library_modal_button_rect(modal_button_key);

				/* A pointer inside these bounds records the matching modal_ hover key for rendering
				and click dispatch */
				if (point_in_rect(gui_x, gui_y, modal_button_rect.left, modal_button_rect.top, modal_button_rect.right, modal_button_rect.bottom))
				{
					panel_hover = "modal_" + modal_button_key;
				}
			}

			/* Only the size dialog exposes width and height input hit areas */
			if (library_modal == "size")
			{
				/* size_w_rect and size_h_rect bound the two numeric draft fields */
				var size_w_rect = library_size_input_rect("w");
				var size_h_rect = library_size_input_rect("h");

				/* Hovering the width field records modal_size_w */
				if (point_in_rect(gui_x, gui_y, size_w_rect.left, size_w_rect.top, size_w_rect.right, size_w_rect.bottom))
				{
					panel_hover = "modal_size_w";
				}

				/* Otherwise hovering the height field records modal_size_h */
				else if (point_in_rect(gui_x, gui_y, size_h_rect.left, size_h_rect.top, size_h_rect.right, size_h_rect.bottom))
				{
					panel_hover = "modal_size_h";
				}
			}

			/* A fresh left press dispatches the highlighted dialog action once */
			if (mouse_check_button_pressed(mb_left))
			{
				/* The dialog hover key selects a preset, numeric focus, confirmation or cancellation
				action */
				switch (panel_hover)
				{
					/* The 16-pixel preset closes the picker and opens a 16 by 16 canvas */
					case "modal_size_16":
						cancel_library_modal();
						return begin_new_stamp(16, 16);

					/* The 32-pixel preset opens the default 32 by 32 canvas */
					case "modal_size_32":
						cancel_library_modal();
						return begin_new_stamp(32, 32);

					/* The 48-pixel preset opens a 48 by 48 canvas */
					case "modal_size_48":
						cancel_library_modal();
						return begin_new_stamp(48, 48);

					/* Clicking the width field transfers text focus and the current width draft to the
					shared keyboard buffer */
					case "modal_size_w":
						library_size_focus = "w";
						keyboard_string = library_size_w_text;
						return true;

					/* Clicking the height field transfers text focus and the current height draft to
					the shared keyboard buffer */
					case "modal_size_h":
						library_size_focus = "h";
						keyboard_string = library_size_h_text;
						return true;

					/* Custom Create parses both draft dimensions, closes the picker and opens their
					canvas */
					case "modal_custom_create":

						/* custom_stamp_w and custom_stamp_h are the clamped typed dimensions used by
						this new canvas */
						var custom_stamp_w = stamp_dimension_from_text(library_size_w_text, stamp_w);
						var custom_stamp_h = stamp_dimension_from_text(library_size_h_text, stamp_h);
						cancel_library_modal();
						return begin_new_stamp(custom_stamp_w, custom_stamp_h);

					/* Confirm applies the action belonging to the current rename or deletion dialog */
					case "modal_confirm":

						/* Rename confirmation attempts to persist the shared keyboard text as the
						custom stamp label */
						if (library_modal == "rename")
						{
							/* confirm_rename retains the permission-independent rename persistence
							result */
							var confirm_rename = rename_selected_custom(keyboard_string);

							/* Close the rename dialog only when its display-name update succeeded */
							if (confirm_rename)
							{
								cancel_library_modal();
							}
							return true;
						}

						/* Deletion confirmation invokes the selected custom deletion and dismisses the
						dialog */
						if (library_modal == "delete")
						{
							delete_selected_custom();
							cancel_library_modal();
							return true;
						}
						break;

					/* Cancel closes the dialog and clears its focus without applying its action */
					case "modal_cancel":
						cancel_library_modal();
						return true;
				}
			}

			/* A dialog consumes pointer input within either its own rectangle or the underlying
			library panel */
			return point_in_rect(gui_x, gui_y, modal_rect.left, modal_rect.top, modal_rect.right, modal_rect.bottom) || point_in_rect(gui_x, gui_y, panel_rect.left, panel_rect.top, panel_rect.right, panel_rect.bottom);
		}

		/* Outside the library rectangle, normal panel input is relinquished so other GUI/world
		controls can handle it */
		if (!point_in_rect(gui_x, gui_y, panel_rect.left, panel_rect.top, panel_rect.right, panel_rect.bottom))
		{
			return false;
		}

		/* Wheel-up moves one library row toward the start without passing row zero */
		if (mouse_wheel_up())
		{
			library_scroll = max(0, library_scroll - 1);
			return true;
		}

		/* Wheel-down moves one row toward the final scroll position without passing it */
		if (mouse_wheel_down())
		{
			library_scroll = min(library_max_scroll(), library_scroll + 1);
			return true;
		}

		/* max_scroll_value is the last row offset available for the filtered library */
		var max_scroll_value = library_max_scroll();

		/* An overflowing library exposes upward and downward scroll hit areas */
		if (max_scroll_value > 0)
		{
			/* scroll_up_rect and scroll_down_rect are the GUI bounds of the two row-navigation
			controls */
			var scroll_up_rect = library_scroll_button_rect("scroll_up");
			var scroll_down_rect = library_scroll_button_rect("scroll_down");

			/* Hovering the upper navigation control records scroll_up */
			if (point_in_rect(gui_x, gui_y, scroll_up_rect.left, scroll_up_rect.top, scroll_up_rect.right, scroll_up_rect.bottom))
			{
				panel_hover = "scroll_up";
			}

			/* Otherwise hovering the lower navigation control records scroll_down */
			else if (point_in_rect(gui_x, gui_y, scroll_down_rect.left, scroll_down_rect.top, scroll_down_rect.right, scroll_down_rect.bottom))
			{
				panel_hover = "scroll_down";
			}
		}

		/* tab_index visits all category tabs to determine the pointer's active tab hover key */
		for (var tab_index = 0; tab_index < array_length(library_tab_keys); tab_index++)
		{
			/* tab_key is this category and tab_rect supplies its GUI hit rectangle */
			var tab_key = library_tab_keys[tab_index];
			var tab_rect = library_tab_rect(tab_key);

			/* Hovering a category tab records its tab_ key for highlighting and click selection */
			if (point_in_rect(gui_x, gui_y, tab_rect.left, tab_rect.top, tab_rect.right, tab_rect.bottom))
			{
				panel_hover = "tab_" + tab_key;
			}
		}

		/* button_keys defines the seven ordinary library actions checked beneath the thumbnail grid */
		var button_keys = ["new", "edit", "rename", "duplicate", "delete", "import", "export"];

		/* button_index visits all action controls to find their hover state */
		for (var button_index = 0; button_index < array_length(button_keys); button_index++)
		{
			/* rect is the current library action's GUI bounds */
			var rect = library_button_rect(button_keys[button_index]);

			/* A pointer within this action rectangle records its action key as panel_hover */
			if (point_in_rect(gui_x, gui_y, rect.left, rect.top, rect.right, rect.bottom))
			{
				panel_hover = button_keys[button_index];
			}
		}

		/* entry_index identifies the visible thumbnail beneath the pointer or remains noone outside
		the image squares */
		var entry_index = library_entry_index_at(gui_x, gui_y);

		/* A valid thumbnail hit records its entry_ hover key for selection and tooltip rendering */
		if (entry_index != noone)
		{
			panel_hover = "entry_" + string(entry_index);
		}

		/* Fresh left clicks dispatch the hovered scroll, tab, thumbnail or library action */
		if (mouse_check_button_pressed(mb_left))
		{
			/* The upward scroll button moves one row toward the first library entries */
			if (panel_hover == "scroll_up")
			{
				library_scroll = max(0, library_scroll - 1);
				return true;
			}

			/* The downward scroll button moves one row toward the last filtered entries */
			if (panel_hover == "scroll_down")
			{
				library_scroll = min(library_max_scroll(), library_scroll + 1);
				return true;
			}

			/* click_tab_index visits category keys until the clicked tab hover identity is found */
			for (var click_tab_index = 0; click_tab_index < array_length(library_tab_keys); click_tab_index++)
			{
				/* click_tab_key is the category currently checked for this click */
				var click_tab_key = library_tab_keys[click_tab_index];

				/* A clicked tab selects its filter and consumes this input before other actions */
				if (panel_hover == "tab_" + click_tab_key)
				{
					set_library_tab(click_tab_key);
					return true;
				}
			}

			/* A clicked thumbnail stores its stable key as the selected stamp */
			if (entry_index != noone)
			{
				selected_key = entries[entry_index].key;
				return true;
			}

			/* Other hover keys dispatch one library action for this left click */
			switch (panel_hover)
			{
				/* New opens the canvas-size picker */
				case "new":
					begin_size_picker();
					return true;

				/* Edit attempts to load editable pixels and open the selected canvas */
				case "edit":
					begin_edit_selected();
					return true;

				/* Rename opens the selected custom display-name dialog */
				case "rename":
					begin_rename_selected();
					return true;

				/* Duplicate installs a new custom copy of the selected image */
				case "duplicate":
					duplicate_selected_stamp();
					return true;

				/* Delete opens a confirmation for the selected custom installation */
				case "delete":
					begin_delete_confirm();
					return true;

				/* Import begins platform PNG selection */
				case "import":
					import_png_from_dialog();
					return true;

				/* Export attempts to save or download the selected PNG */
				case "export":
					export_selected_png();
					return true;
			}
		}

		return true;
	}

	/// @description Handle transparency mode, colour, block-size, apply, and cancel input while the settings modal is open
	/// @returns {Bool} Whether the transparency modal is open and owns input
	update_transparency_modal_input = function()
	{
		/* A closed transparency dialog does not consume editor input */
		if (!transparency_modal_open)
		{
			return false;
		}

		/* gui_x and gui_y locate the pointer in the same GUI space as the transparency dialog */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		editor_hover = "";

		/* Block-size focus routes keyboard input into its digits-only draft */
		if (transparency_focus == "block_size")
		{
			scr_text_input_update("stamp_transparency_block_size", transparency_draft_block_size_text);
			transparency_draft_block_size_text = digits_only(keyboard_string);
			keyboard_string = transparency_draft_block_size_text;
		}

		/* Escape dismisses transparency drafts without applying them */
		if (keyboard_check_pressed(vk_escape))
		{
			cancel_transparency_modal();
			return true;
		}

		/* Enter applies the transparency drafts, persists settings and closes the dialog */
		if (keyboard_check_pressed(vk_enter))
		{
			apply_transparency_modal();
			return true;
		}

		/* block_size_rect bounds the transparency numeric input */
		var block_size_rect = transparency_block_size_input_rect();

		/* Hovering the block-size field records its dedicated transparency hover key */
		if (point_in_rect(gui_x, gui_y, block_size_rect.left, block_size_rect.top, block_size_rect.right, block_size_rect.bottom))
		{
			editor_hover = "transparency_block_size";
		}

		/* modal_keys lists mode choices, colour-copy controls and OK/Cancel actions */
		var modal_keys = ["mode_block", "mode_single", "color_1_current", "color_2_current", "single_current", "ok", "cancel"];

		/* key_index visits all transparency dialog controls for hit testing */
		for (var key_index = 0; key_index < array_length(modal_keys); key_index++)
		{
			/* modal_key identifies this control and button_rect bounds it in GUI coordinates */
			var modal_key = modal_keys[key_index];
			var button_rect = transparency_modal_button_rect(modal_key);

			/* A hit records the matching transparency_ key for rendering and action dispatch */
			if (point_in_rect(gui_x, gui_y, button_rect.left, button_rect.top, button_rect.right, button_rect.bottom))
			{
				editor_hover = "transparency_" + modal_key;
			}
		}

		/* A fresh left press applies the highlighted transparency control */
		if (mouse_check_button_pressed(mb_left))
		{
			/* Clicks away from the block-size field release text focus and its keyboard buffer */
			if (editor_hover != "transparency_block_size")
			{
				transparency_focus = "";
				keyboard_string = "";
			}

			/* The transparency hover key chooses a mode, RGB draft copy, numeric focus or
			commit/cancel action */
			switch (editor_hover)
			{
				/* Block mode selects alternating checker cells */
				case "transparency_mode_block":
					transparency_draft_mode = "block";
					return true;

				/* Single mode selects a uniform transparency background */
				case "transparency_mode_single":
					transparency_draft_mode = "single";
					return true;

				/* Use Current copies the current RGB bytes into the first checker colour */
				case "transparency_color_1_current":
					transparency_draft_color_1 = rgb_struct(current_red, current_green, current_blue);
					return true;

				/* Use Current copies the current RGB bytes into the second checker colour */
				case "transparency_color_2_current":
					transparency_draft_color_2 = rgb_struct(current_red, current_green, current_blue);
					return true;

				/* Use Current copies the current RGB bytes into the single background colour */
				case "transparency_single_current":
					transparency_draft_single_color = rgb_struct(current_red, current_green, current_blue);
					return true;

				/* Block-size clicks transfer numeric draft focus to the keyboard buffer */
				case "transparency_block_size":
					transparency_focus = "block_size";
					keyboard_string = transparency_draft_block_size_text;
					return true;

				/* OK applies and saves the dialog drafts */
				case "transparency_ok":
					apply_transparency_modal();
					return true;

				/* Cancel discards the dialog interaction and clears focus */
				case "transparency_cancel":
					cancel_transparency_modal();
					return true;
			}
		}

		return true;
	}

	/// @description Handle editor shortcuts, tools, selections, strokes, colour controls, resize, and view navigation
	/// @returns {Bool} Whether the editor is open and owns input, including input outside its visible rectangle
	update_editor_input = function()
	{
		/* A closed stamp editor has no modal input ownership */
		if (!editor_open)
		{
			return false;
		}

		/* An active transparency dialog consumes input before canvas tools and editor controls */
		if (update_transparency_modal_input())
		{
			return true;
		}

		editor_hover = "";

		/* gui_x and gui_y are the current GUI pointer, modal_rect bounds the editor and grid_rect
		describes the visible canvas cells */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var modal_rect = editor_rect();
		var grid_rect = editor_grid_rect();
		clamp_editor_view();

		/* Focused resize text is processed before keyboard shortcuts so digits and editing keys belong
		to the active field */
		if (editor_size_focus != "")
		{
			/* Route text input to the width or height draft selected by editor_size_focus */
			scr_text_input_update("stamp_editor_size_" + editor_size_focus, editor_size_focus == "w" ? editor_size_w_text : editor_size_h_text);

			/* clean_editor_size_text retains only digits for the active resize draft */
			var clean_editor_size_text = digits_only(keyboard_string);
			keyboard_string = clean_editor_size_text;

			/* Width focus updates the width draft */
			if (editor_size_focus == "w")
			{
				editor_size_w_text = clean_editor_size_text;
			}

			/* Height focus updates the height draft */
			else if (editor_size_focus == "h")
			{
				editor_size_h_text = clean_editor_size_text;
			}

			/* Escape releases numeric focus and restores text from the actual canvas dimensions */
			if (keyboard_check_pressed(vk_escape))
			{
				editor_size_focus = "";
				keyboard_string = "";
				sync_editor_size_text(true);
				return true;
			}

			/* Enter commits the drafted canvas resize and consumes the input */
			if (keyboard_check_pressed(vk_enter))
			{
				apply_editor_resize_from_text();
				return true;
			}
		}

		/* Without numeric focus, keep both dimension drafts synchronized to current canvas state */
		else
		{
			sync_editor_size_text(false);
		}

		/* Control shortcuts run only when no numeric field owns keyboard input */
		if (editor_size_focus == "" && keyboard_check(vk_control))
		{
			/* Control-Z requests one undo snapshot */
			if (keyboard_check_pressed(ord("Z")))
			{
				/* A successful snapshot restore dirties the cached surface and resynchronizes
				dimensions and viewport */
				if (editor.undo())
				{
					mark_editor_surface_dirty();
					sync_editor_size_text(true);
					clamp_editor_view();
				}
				return true;
			}

			/* Control-Y requests one redo snapshot */
			if (keyboard_check_pressed(ord("Y")))
			{
				/* A successful redo restore dirties the image cache and updates size text and viewport
				bounds */
				if (editor.redo())
				{
					mark_editor_surface_dirty();
					sync_editor_size_text(true);
					clamp_editor_view();
				}
				return true;
			}

			/* Control-C attempts to copy the active selected region */
			if (keyboard_check_pressed(ord("C")))
			{
				/* An active selection copied to the shared region clipboard receives a success status */
				if (editor.selection_active && editor.copy_selection_to_clipboard())
				{
					set_status("Copied selection.", make_color_rgb(126, 245, 150));
				}

				/* Without an available copied selection, show the no-selection warning */
				else
				{
					set_status("No selection to copy.", make_color_rgb(255, 220, 95));
				}
				return true;
			}

			/* Control-X attempts to copy and clear the selected region */
			if (keyboard_check_pressed(ord("X")))
			{
				/* Only an active selection can be cut to the shared clipboard */
				if (editor.selection_active)
				{
					/* A cut reporting changed pixels invalidates the cached editor surface */
					if (editor.cut_selection_to_clipboard())
					{
						mark_editor_surface_dirty();
					}
					set_status("Cut selection.", make_color_rgb(126, 245, 150));
				}

				/* Without a selection, cutting shows a warning and preserves the canvas */
				else
				{
					set_status("No selection to cut.", make_color_rgb(255, 220, 95));
				}
				return true;
			}

			/* Control-V attempts to paste the shared region clipboard */
			if (keyboard_check_pressed(ord("V")))
			{
				/* Available copied region data can be placed at the selection, pointer cell or
				viewport fallback target */
				if (editor.region_clipboard_available())
				{
					/* paste_col and paste_row are the chosen zero-based destination cells for the
					copied region */
					var paste_col = editor_paste_target_col(gui_x, gui_y, grid_rect);
					var paste_row = editor_paste_target_row(gui_x, gui_y, grid_rect);

					/* A paste reporting changed pixels invalidates the cached editor surface */
					if (editor.paste_clipboard_at(paste_col, paste_row))
					{
						mark_editor_surface_dirty();
					}
					set_status("Pasted selection.", make_color_rgb(126, 245, 150));
				}

				/* Without copied region data, report that nothing is available to paste */
				else
				{
					set_status("No copied selection.", make_color_rgb(255, 220, 95));
				}
				return true;
			}

			/* Control-0 restores the editor's 100-percent zoom */
			if (keyboard_check_pressed(ord("0")))
			{
				reset_editor_zoom();
				return true;
			}

			/* Control with plus, equals or keypad-add advances to the next larger authored zoom level */
			if (keyboard_check_pressed(vk_add) || keyboard_check_pressed(ord("+")) || keyboard_check_pressed(ord("=")))
			{
				adjust_editor_zoom(1);
				return true;
			}

			/* Control with minus or keypad-subtract advances to the next smaller authored zoom level */
			if (keyboard_check_pressed(vk_subtract) || keyboard_check_pressed(ord("-")))
			{
				adjust_editor_zoom(-1);
				return true;
			}
		}

		/* Delete or Backspace clears selected pixels only when the canvas owns keyboard input and a
		selection is active */
		if (editor_size_focus == ""
		&& (keyboard_check_pressed(vk_delete) || keyboard_check_pressed(vk_backspace))
		&& editor.selection_active)
		{
			/* Changed selected pixels require a new cached editor image */
			if (editor.clear_selected_pixels(true))
			{
				mark_editor_surface_dirty();
			}
			set_status("Deleted selection pixels.", make_color_rgb(126, 245, 150));
			return true;
		}

		/* An active HSV slider drag keeps ownership ahead of other canvas and control hits */
		if (editor_colour_slider_active != "")
		{
			editor_hover = editor_colour_slider_active + "_slider";

			/* Holding the left button updates that HSV component from the pointer and consumes the
			drag */
			if (mouse_check_button(mb_left))
			{
				update_editor_hsv_slider_from_mouse(editor_colour_slider_active, gui_x);
				return true;
			}

			editor_colour_slider_active = "";
		}

		/* button_keys lists tools, history, zoom, view, transforms and editor save/cancel controls for
		hit testing */
		var button_keys = ["pen", "eraser", "fill", "picker", "select", "undo", "redo", "clear", "zoom_out", "zoom_reset", "zoom_in", "view_left", "view_up", "view_down", "view_right", "flip_h", "flip_v", "rotate_cw", "rotate_ccw", "shift_left", "shift_right", "shift_up", "shift_down", "save", "cancel"];

		/* button_index visits all listed editor controls for their current hover bounds */
		for (var button_index = 0; button_index < array_length(button_keys); button_index++)
		{
			/* button_key is the editor action currently being tested */
			var button_key = button_keys[button_index];

			/* Skip view arrows hidden because their source axis already fits in the viewport */
			if (string_copy(button_key, 1, 5) == "view_"
			&& !editor_view_button_should_show(button_key))
			{
				continue;
			}

			/* is_zoom_button distinguishes zoom geometry. rect uses view, zoom or ordinary editor
			bounds according to the button prefix */
			var is_zoom_button = string_copy(button_key, 1, 5) == "zoom_";
			var rect = string_copy(button_key, 1, 5) == "view_" ? editor_view_button_rect(button_key) : (is_zoom_button ? editor_zoom_button_rect(button_key) : editor_button_rect(button_key));

			/* A pointer hit stores this editor action as editor_hover */
			if (point_in_rect(gui_x, gui_y, rect.left, rect.top, rect.right, rect.bottom))
			{
				editor_hover = button_key;
			}
		}

		/* swatch_index identifies the palette square beneath the pointer or noone */
		var swatch_index = editor_swatch_index_at(gui_x, gui_y);

		/* A valid swatch hit stores its swatch_ hover identity */
		if (swatch_index != noone)
		{
			editor_hover = "swatch_" + string(swatch_index);
		}

		/* slider_key identifies the hovered hue, saturation or value slider, or empty when none is hit */
		var slider_key = editor_hsv_slider_key_at(gui_x, gui_y);

		/* A slider hit stores its component-specific hover key */
		if (slider_key != "")
		{
			editor_hover = slider_key + "_slider";
		}

		/* resize_w_rect, resize_h_rect and resize_apply_rect bound numeric resize input and its commit
		control */
		var resize_w_rect = editor_resize_input_rect("w");
		var resize_h_rect = editor_resize_input_rect("h");
		var resize_apply_rect = editor_resize_apply_rect();

		/* The width field receives resize_w hover */
		if (point_in_rect(gui_x, gui_y, resize_w_rect.left, resize_w_rect.top, resize_w_rect.right, resize_w_rect.bottom))
		{
			editor_hover = "resize_w";
		}

		/* Otherwise the height field receives resize_h hover */
		else if (point_in_rect(gui_x, gui_y, resize_h_rect.left, resize_h_rect.top, resize_h_rect.right, resize_h_rect.bottom))
		{
			editor_hover = "resize_h";
		}

		/* Otherwise the resize commit control receives resize_apply hover */
		else if (point_in_rect(gui_x, gui_y, resize_apply_rect.left, resize_apply_rect.top, resize_apply_rect.right, resize_apply_rect.bottom))
		{
			editor_hover = "resize_apply";
		}

		/* An active selection drag keeps moving its preview even after the pointer leaves the grid */
		if (editor_tool == PIXEL_EDITOR_TOOL_SELECT && editor.selection_drag_active())
		{
			/* drag_col and drag_row convert the current GUI pointer to clamped zero-based canvas cells */
			var drag_col = editor_grid_col_from_gui(gui_x, grid_rect);
			var drag_row = editor_grid_row_from_gui(gui_y, grid_rect);
			editor.update_selection_drag(drag_col, drag_row);

			/* A released or no-longer-held left button finishes the active selection gesture */
			if (!mouse_check_button(mb_left) || mouse_check_button_released(mb_left))
			{
				/* Only a completed drag reporting changed pixels invalidates the cached surface */
				if (editor.finish_selection_drag())
				{
					mark_editor_surface_dirty();
				}
			}
			return true;
		}

		/* Within the visible grid, pointer input can pan, select, pick colour or paint source cells */
		if (point_in_rect(gui_x, gui_y, grid_rect.left, grid_rect.top, grid_rect.right, grid_rect.bottom))
		{
			editor_hover = "grid";

			/* Wheel-up pans toward earlier canvas rows by roughly a quarter viewport */
			if (mouse_wheel_up())
			{
				/* wheel_step_up is at least one source row and otherwise one quarter of the visible
				row count */
				var wheel_step_up = max(1, floor(grid_rect.visible_rows / 4));
				pan_editor_view(0, -wheel_step_up);
				return true;
			}

			/* Wheel-down pans toward later canvas rows by the same viewport-relative amount */
			if (mouse_wheel_down())
			{
				/* wheel_step_down is at least one source row and otherwise one quarter of the visible
				row count */
				var wheel_step_down = max(1, floor(grid_rect.visible_rows / 4));
				pan_editor_view(0, wheel_step_down);
				return true;
			}

			/* pixel_col and pixel_row are clamped zero-based canvas coordinates used by hover state
			and pixel tools */
			var pixel_col = editor_grid_col_from_gui(gui_x, grid_rect);
			var pixel_row = editor_grid_row_from_gui(gui_y, grid_rect);
			editor_hover_col = pixel_col;
			editor_hover_row = pixel_row;

			/* Selection-tool input starts, updates or finishes a region gesture before painting is
			considered */
			if (editor_tool == PIXEL_EDITOR_TOOL_SELECT)
			{
				/* A fresh left press starts a selection gesture at this source cell */
				if (mouse_check_button_pressed(mb_left))
				{
					editor.begin_selection_drag(pixel_col, pixel_row);
					return true;
				}

				/* Holding left while the selection gesture is active updates its bounds or movement
				preview */
				if (mouse_check_button(mb_left) && editor.selection_drag_active())
				{
					editor.update_selection_drag(pixel_col, pixel_row);
					return true;
				}

				/* Releasing left completes the selection gesture */
				if (mouse_check_button_released(mb_left))
				{
					/* Changed pixels reported by a completed move require a refreshed editor surface */
					if (editor.finish_selection_drag())
					{
						mark_editor_surface_dirty();
					}
					return true;
				}
			}

			/* A fresh left press with the colour picker samples this source pixel rather than painting
			it */
			if (mouse_check_button_pressed(mb_left) && editor_tool == PIXEL_EDITOR_TOOL_COLOR_PICKER)
			{
				/* picked_pixel is the source RGBA value and picked_alpha measures its byte opacity */
				var picked_pixel = editor.get_pixel(pixel_col, pixel_row);
				var picked_alpha = editor.pixel_alpha(picked_pixel);

				/* Visible pixels supply RGB values for the current editor colour and toolbar
				synchronization */
				if (picked_alpha > 0)
				{
					set_editor_colour_rgb(editor.pixel_red(picked_pixel), editor.pixel_green(picked_pixel), editor.pixel_blue(picked_pixel));
					set_status("Picked RGB " + string(current_red) + ", " + string(current_green) + ", " + string(current_blue) + ".", make_color_rgb(126, 245, 150));
				}

				/* A fully transparent pixel has no visible colour to pick, so retain the current
				colour and show a warning */
				else
				{
					set_status("Transparent pixel has no color.", make_color_rgb(255, 220, 95));
				}

				return true;
			}

			/* A fresh press starts pixel-tool handling. Held presses repeat pen/eraser strokes, while
			fill, picker and selection are excluded from repeated drawing */
			if (mouse_check_button_pressed(mb_left) || (mouse_check_button(mb_left) && editor_tool != PIXEL_EDITOR_TOOL_FILL && editor_tool != PIXEL_EDITOR_TOOL_COLOR_PICKER && editor_tool != PIXEL_EDITOR_TOOL_SELECT))
			{
				/* Capture one undo snapshot at the start of a press so a continuous stroke can be
				reverted as one operation */
				if (mouse_check_button_pressed(mb_left))
				{
					editor.push_undo_snapshot();
				}

				/* The active tool chooses erasing, flood fill or default pen painting */
				switch (editor_tool)
				{
					/* Eraser clears alpha at the hovered source cell */
					case PIXEL_EDITOR_TOOL_ERASER:

						/* An accepted in-bounds erase dirties the cached surface even when the cell
						was already transparent */
						if (editor.erase_pixel(pixel_col, pixel_row))
						{
							mark_editor_surface_dirty();
						}
						break;

					/* Fill operates on the connected matching-colour region */
					case PIXEL_EDITOR_TOOL_FILL:

						/* Flood fill runs only on a fresh press so holding the button does not repeat
						it */
						if (mouse_check_button_pressed(mb_left))
						{
							/* A fill reporting changed pixels invalidates the cached surface */
							if (editor.fill_pixels(pixel_col, pixel_row, current_red, current_green, current_blue))
							{
								mark_editor_surface_dirty();
							}
						}
						break;

					/* Other painting tool values use the pen's current RGB colour */
					default:

						/* An accepted in-bounds paint dirties the surface even when the previous pixel
						already had the same colour */
						if (editor.paint_pixel(pixel_col, pixel_row, current_red, current_green, current_blue))
						{
							mark_editor_surface_dirty();
						}
						break;
				}
			}
		}

		/* Fresh left clicks outside an ongoing gesture can choose swatches, begin slider drags, focus
		numeric fields or invoke editor actions */
		if (mouse_check_button_pressed(mb_left))
		{
			/* A clicked palette swatch replaces the current RGB colour and requests toolbar
			synchronization */
			if (swatch_index != noone)
			{
				/* swatch supplies the clicked preset's r/g/b byte channels */
				var swatch = editor_colour_swatches[swatch_index];
				set_editor_colour_rgb(swatch.r, swatch.g, swatch.b);
				return true;
			}

			/* Clicking an HSV slider begins component drag ownership and immediately updates its value */
			if (slider_key != "")
			{
				editor_colour_slider_active = slider_key;
				update_editor_hsv_slider_from_mouse(slider_key, gui_x);
				return true;
			}

			/* Clicking the width field transfers resize focus and current text to the keyboard buffer */
			if (editor_hover == "resize_w")
			{
				editor_size_focus = "w";
				keyboard_string = editor_size_w_text;
				return true;
			}

			/* Clicking the height field transfers resize focus and current text to the keyboard buffer */
			if (editor_hover == "resize_h")
			{
				editor_size_focus = "h";
				keyboard_string = editor_size_h_text;
				return true;
			}

			/* Clicking Apply commits the current resize drafts */
			if (editor_hover == "resize_apply")
			{
				apply_editor_resize_from_text();
				return true;
			}

			/* The clicked editor hover key dispatches tool choice, history, panning, transforms or
			save/cancel */
			switch (editor_hover)
			{
				/* Pen selects direct pixel painting */
				case "pen":
					editor_tool = PIXEL_EDITOR_TOOL_PEN;
					break;

				/* Eraser selects alpha clearing */
				case "eraser":
					editor_tool = PIXEL_EDITOR_TOOL_ERASER;
					break;

				/* Fill selects connected-region colouring */
				case "fill":
					editor_tool = PIXEL_EDITOR_TOOL_FILL;
					break;

				/* Picker selects source RGB sampling */
				case "picker":
					editor_tool = PIXEL_EDITOR_TOOL_COLOR_PICKER;
					break;

				/* Select chooses region selection and dragging */
				case "select":
					editor_tool = PIXEL_EDITOR_TOOL_SELECT;
					break;

				/* Undo requests the previous history snapshot */
				case "undo":

					/* A restored undo snapshot requires refreshed image, size text and viewport limits */
					if (editor.undo())
					{
						mark_editor_surface_dirty();
						sync_editor_size_text(true);
						clamp_editor_view();
					}
					break;

				/* Redo requests the next history snapshot */
				case "redo":

					/* A restored redo snapshot requires refreshed image, dimensions and viewport
					limits */
					if (editor.redo())
					{
						mark_editor_surface_dirty();
						sync_editor_size_text(true);
						clamp_editor_view();
					}
					break;

				/* Zoom Out moves to a smaller authored zoom step */
				case "zoom_out":
					adjust_editor_zoom(-1);
					break;

				/* No Zoom restores 100 percent */
				case "zoom_reset":
					reset_editor_zoom();
					break;

				/* Zoom In moves to a larger authored zoom step */
				case "zoom_in":
					adjust_editor_zoom(1);
					break;

				/* View Left pans toward earlier columns */
				case "view_left":

					/* Only pan left when columns remain beyond the viewport's left edge */
					if (editor_view_button_enabled("view_left"))
					{
						pan_editor_view(-max(1, floor(grid_rect.visible_cols / 4)), 0);
					}
					break;

				/* View Right pans toward later columns */
				case "view_right":

					/* Only pan right when columns remain beyond the viewport's right edge */
					if (editor_view_button_enabled("view_right"))
					{
						pan_editor_view(max(1, floor(grid_rect.visible_cols / 4)), 0);
					}
					break;

				/* View Up pans toward earlier rows */
				case "view_up":

					/* Only pan upward while rows remain above the viewport */
					if (editor_view_button_enabled("view_up"))
					{
						pan_editor_view(0, -max(1, floor(grid_rect.visible_rows / 4)));
					}
					break;

				/* View Down pans toward later rows */
				case "view_down":

					/* Only pan downward while rows remain below the viewport */
					if (editor_view_button_enabled("view_down"))
					{
						pan_editor_view(0, max(1, floor(grid_rect.visible_rows / 4)));
					}
					break;

				/* Clear captures an undo snapshot before emptying the full pixel canvas and refreshing
				its surface */
				case "clear":
					editor.push_undo_snapshot();
					editor.clear();
					mark_editor_surface_dirty();
					break;

				/* Flip H mirrors the canvas's columns */
				case "flip_h":

					/* An accepted horizontal flip dirties the cache when the canvas is wider than one
					pixel, without testing whether mirrored pixels differ */
					if (editor.flip_horizontal())
					{
						mark_editor_surface_dirty();
					}
					break;

				/* Flip V mirrors the canvas's rows */
				case "flip_v":

					/* An accepted vertical flip dirties the cache when the canvas is taller than one
					pixel, without testing whether mirrored pixels differ */
					if (editor.flip_vertical())
					{
						mark_editor_surface_dirty();
					}
					break;

				/* Rot R rotates pixels clockwise and can exchange canvas width and height */
				case "rotate_cw":

					/* An accepted clockwise rotation updates the cached image, numeric dimensions and
					viewport limits */
					if (editor.rotate_clockwise())
					{
						mark_editor_surface_dirty();
						sync_editor_size_text(true);
						clamp_editor_view();
					}
					break;

				/* Rot L rotates pixels counterclockwise and can exchange canvas dimensions */
				case "rotate_ccw":

					/* An accepted counterclockwise rotation updates the cached image, size fields and
					viewport limits */
					if (editor.rotate_counterclockwise())
					{
						mark_editor_surface_dirty();
						sync_editor_size_text(true);
						clamp_editor_view();
					}
					break;

				/* Left shifts the canvas by one source column */
				case "shift_left":

					/* An accepted nonzero left shift dirties the cache even for an empty canvas */
					if (editor.shift_pixels(-1, 0)) mark_editor_surface_dirty();
					break;

				/* Right shifts the canvas by one source column */
				case "shift_right":

					/* An accepted nonzero right shift dirties the cache even when no visible pixels
					move */
					if (editor.shift_pixels(1, 0)) mark_editor_surface_dirty();
					break;

				/* Up shifts the canvas by one source row */
				case "shift_up":

					/* An accepted nonzero upward shift dirties the cache without a pixel-difference
					test */
					if (editor.shift_pixels(0, -1)) mark_editor_surface_dirty();
					break;

				/* Down shifts the canvas by one source row */
				case "shift_down":

					/* An accepted nonzero downward shift dirties the cache without checking whether
					the image changed */
					if (editor.shift_pixels(0, 1)) mark_editor_surface_dirty();
					break;

				/* Save persists the current editor image and closes it after a complete custom-package
				save */
				case "save":
					save_editor();
					break;

				/* Cancel closes the editor and releases its image/gradient caches */
				case "cancel":
					cancel_editor();
					break;
			}
		}

		/* Escape first clears an active selection, otherwise cancels the whole editor */
		if (keyboard_check_pressed(vk_escape))
		{
			/* An active selection consumes Escape by clearing its bounds without closing the canvas */
			if (editor.selection_active)
			{
				editor.clear_selection();
				return true;
			}

			cancel_editor();
		}

		return true;
	}

	/// @description Poll imports and route GUI input to the editor before the library, synchronizing toolbar RGB into editor colour state
	/// @param {Bool} panel_active Whether the library panel is active
	/// @param {Real} raw_red Toolbar red channel, clamped to a byte
	/// @param {Real} raw_green Toolbar green channel, clamped to a byte
	/// @param {Real} raw_blue Toolbar blue channel, clamped to a byte
	/// @returns {Bool} Whether stamp GUI interaction consumed input
	update_gui = function(panel_active, raw_red, raw_green, raw_blue)
	{
		set_current_colour(raw_red, raw_green, raw_blue);

		/* The first GUI update discovers the library before input actions depend on its entries */
		if (!scanned)
		{
			refresh(true);
		}

		update_browser_import();

		/* Editor or transparency interaction consumes input before the ordinary library panel */
		if (update_editor_input())
		{
			return true;
		}

		return update_library_input(panel_active);
	}
	#endregion /* Stamp GUI Input END */

	#region /* Stamp GUI Rendering */
	/// @description Fill a destination rectangle with the scrolling transparency sprite, using a dark solid fallback when the sprite is unavailable
	/// @param {Real} draw_left Destination left coordinate
	/// @param {Real} draw_top Destination top coordinate
	/// @param {Real} draw_w Destination width in drawing pixels
	/// @param {Real} draw_h Destination height in drawing pixels
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 1 when omitted
	/// @returns {Bool} Always true after drawing and resetting draw alpha to 1
	draw_transparency_background = function(draw_left, draw_top, draw_w, draw_h, draw_alpha = 1)
	{
		/* safe_w and safe_h keep the transparency-background rectangle at least one draw-coordinate
		unit in each dimension */
		var safe_w = max(1, real(draw_w));
		var safe_h = max(1, real(draw_h));

		/* Without the authored transparency sprite, fill the requested rectangle with a dark fallback
		colour */
		if (!sprite_exists(spr_transparent_background))
		{
			draw_set_alpha(draw_alpha);
			draw_set_colour(make_color_rgb(30, 32, 36));
			draw_rectangle(draw_left, draw_top, draw_left + safe_w, draw_top + safe_h, false);
			draw_set_alpha(1);
			return true;
		}

		/* tile_w and tile_h are the transparency sprite's source-pixel dimensions. scroll_x and
		scroll_y advance one pixel per 72 and 96 milliseconds and wrap at their tile dimensions */
		var tile_w = max(1, sprite_get_width(spr_transparent_background));
		var tile_h = max(1, sprite_get_height(spr_transparent_background));
		var scroll_x = floor(current_time / 72) mod tile_w;
		var scroll_y = floor(current_time / 96) mod tile_h;

		/* restore_filter preserves the caller's texture filtering while this pixel background draws
		without interpolation */
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);

		/* tile_y visits every tile row intersecting the requested rectangle, starting before its top
		to account for animated scrolling */
		for (var tile_y = draw_top - scroll_y; tile_y < draw_top + safe_h; tile_y += tile_h)
		{
			/* tile_x visits every intersecting tile column so the scrolling texture covers the full
			rectangle */
			for (var tile_x = draw_left - scroll_x; tile_x < draw_left + safe_w; tile_x += tile_w)
			{
				/* crop_left/top/right/bottom clip this tile to the destination rectangle. crop_w and
				crop_h measure its visible portion in draw coordinates */
				var crop_left = max(draw_left, tile_x);
				var crop_top = max(draw_top, tile_y);
				var crop_right = min(draw_left + safe_w, tile_x + tile_w);
				var crop_bottom = min(draw_top + safe_h, tile_y + tile_h);
				var crop_w = crop_right - crop_left;
				var crop_h = crop_bottom - crop_top;

				/* Only a positive visible crop is drawn, keeping partial edge tiles inside the
				background rectangle */
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

	/// @description Resolve the shared solid background or checkerboard colour for a source pixel cell
	/// @param {Real} pixel_col Zero-based source column
	/// @param {Real} pixel_row Zero-based source row
	/// @returns {Struct} Borrowed RGB colour from shared transparency settings
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

	/// @description Draw one source cell's transparency background colour and reset draw alpha to 1
	/// @param {Real} draw_left Destination left edge
	/// @param {Real} draw_top Destination top edge
	/// @param {Real} draw_right Destination right edge
	/// @param {Real} draw_bottom Destination bottom edge
	/// @param {Real} pixel_col Zero-based source column used for checkerboard parity
	/// @param {Real} pixel_row Zero-based source row used for checkerboard parity
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 1 when omitted
	/// @returns {Bool} Always true after drawing the cell
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

	/// @description Draw an entry using its dimension-ready original PNG sprite or editable surface fallback, temporarily disabling texture filtering
	/// @param {Real} entry_index Zero-based index in entries
	/// @param {Real} draw_left Destination left coordinate
	/// @param {Real} draw_top Destination top coordinate
	/// @param {Real} draw_w Destination width in drawing pixels
	/// @param {Real} draw_h Destination height in drawing pixels
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 1 when omitted
	/// @param {Bool} checker Whether to draw a transparency background first, defaulting to false when omitted
	/// @param {Bool} outline Whether to draw an outer white border, defaulting to false when omitted
	/// @param {Bool} fit_aspect Whether to center the image with its aspect ratio preserved, defaulting to false when omitted
	/// @returns {Bool} Whether a ready sprite or surface was available and drawn
	draw_entry_surface = function(entry_index, draw_left, draw_top, draw_w, draw_h, draw_alpha = 1, checker = false, outline = false, fit_aspect = false)
	{
		/* An index outside the zero-based library array has no preview image to draw */
		if (entry_index < 0 || entry_index >= array_length(entries))
		{
			return false;
		}

		/* Draw the optional transparency background before the stamp image */
		if (checker)
		{
			draw_transparency_background(draw_left, draw_top, draw_w, draw_h, draw_alpha);
		}

		/* Preserve the original PNG for thumbnails and cursor previews. Decoded
		pixel surfaces are an editing/fallback representation and must not hide
		a valid PNG if a platform-specific decode fails */
		/* stamp_sprite borrows the entry's cached original PNG preview. entry supplies its stored
		dimensions, with entry_w and entry_h measured in source pixels */
		var stamp_sprite = ensure_entry_sprite(entry_index);
		var entry = entries[entry_index];
		var entry_w = entry_stamp_w(entry);
		var entry_h = entry_stamp_h(entry);

		/* sprite_ready requires a live sprite matching the entry's full dimensions, excluding an
		asynchronous loading placeholder */
		var sprite_ready = sprite_exists(stamp_sprite)
			&& sprite_get_width(stamp_sprite) == entry_w
			&& sprite_get_height(stamp_sprite) == entry_h;

		/* A ready original PNG needs no pixel surface. Otherwise stamp_surface borrows the
		editable-pixel fallback cache */
		var stamp_surface = sprite_ready ? noone : ensure_entry_surface(entry_index);

		/* If neither the full PNG nor a live pixel surface is available, report that no stamp image
		was drawn */
		if (!sprite_ready && !surface_exists(stamp_surface))
		{
			return false;
		}

		/* surface_left/top/w/h initially use the requested destination rectangle in the current
		drawing coordinates */
		var surface_left = draw_left;
		var surface_top = draw_top;
		var surface_w = draw_w;
		var surface_h = draw_h;

		/* Aspect fitting preserves image proportions and centers the fitted stamp inside the requested
		rectangle */
		if (fit_aspect)
		{
			/* surface_scale is the smaller width/height fit so neither source dimension exceeds the
			destination box */
			var surface_scale = min(draw_w / entry_w, draw_h / entry_h);
			surface_w = max(1, entry_w * surface_scale);
			surface_h = max(1, entry_h * surface_scale);
			surface_left = round(draw_left + draw_w * 0.5 - surface_w * 0.5);
			surface_top = round(draw_top + draw_h * 0.5 - surface_h * 0.5);
		}

		/* restore_filter preserves the caller's texture filtering before drawing the stamp with sharp
		pixels */
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);

		/* A fully loaded original PNG is drawn before considering its editable-pixel representation */
		if (sprite_ready)
		{
			draw_sprite_ext(stamp_sprite, 0, surface_left, surface_top, surface_w / entry_w, surface_h / entry_h, 0, c_white, draw_alpha);
		}

		/* When the original sprite is not ready, draw the borrowed pixel-surface fallback instead */
		else
		{
			draw_surface_ext(stamp_surface, surface_left, surface_top, surface_w / entry_w, surface_h / entry_h, 0, c_white, draw_alpha);
		}
		gpu_set_texfilter(restore_filter);

		/* Draw the requested border around the full destination rectangle after rendering the image */
		if (outline)
		{
			draw_set_alpha(draw_alpha);
			draw_set_colour(c_white);
			draw_rectangle(draw_left - 1, draw_top - 1, draw_left + draw_w + 1, draw_top + draw_h + 1, true);
			draw_set_alpha(1);
		}

		return true;
	}

	/// @description Draw RGBA text cell by cell, optionally drawing transparency backgrounds and cell outlines, then reset draw alpha to 1
	/// @param {String} hex_text Row-major RRGGBBAA pixel text
	/// @param {Real} draw_left Destination left coordinate
	/// @param {Real} draw_top Destination top coordinate
	/// @param {Real} cell_size Destination cell size in drawing pixels
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 1 when omitted
	/// @param {Bool} checker Whether to draw backgrounds for cells, defaulting to false when omitted
	/// @param {Bool} outline Whether to outline cells, defaulting to false when omitted
	/// @param {Real} draw_w Source width in pixels, defaulting to stamp_w when omitted
	/// @param {Real} draw_h Source height in pixels, defaulting to stamp_h when omitted
	/// @returns {Any} No explicit return value
	draw_hex_pixels = function(hex_text, draw_left, draw_top, cell_size, draw_alpha = 1, checker = false, outline = false, draw_w = stamp_w, draw_h = stamp_h)
	{
		/* safe_cell_size measures one source pixel in draw coordinates. safe_draw_w and safe_draw_h
		are positive whole source-grid dimensions */
		var safe_cell_size = max(1, real(cell_size));
		var safe_draw_w = max(1, floor(real(draw_w)));
		var safe_draw_h = max(1, floor(real(draw_h)));

		/* A requested checker background covers the whole enlarged pixel grid before visible pixels
		are drawn */
		if (checker)
		{
			draw_transparency_background(draw_left, draw_top, safe_draw_w * safe_cell_size, safe_draw_h * safe_cell_size, draw_alpha);
		}

		/* pixel_row visits all zero-based source rows in this grid */
		for (var pixel_row = 0; pixel_row < safe_draw_h; pixel_row++)
		{
			/* pixel_col visits all zero-based source columns in the current row */
			for (var pixel_col = 0; pixel_col < safe_draw_w; pixel_col++)
			{
				/* pixel_index addresses row-major RGBA hex data and pixel_data exposes this pixel's
				r/g/b/a bytes */
				var pixel_index = pixel_row * safe_draw_w + pixel_col;
				var pixel_data = hex_pixel_at(hex_text, pixel_index);

				/* Transparent pixels leave the underlying background visible and need no coloured
				primitive */
				if (pixel_data.a > 0)
				{
					draw_set_alpha(draw_alpha * pixel_data.a / 255);
					draw_set_colour(make_color_rgb(pixel_data.r, pixel_data.g, pixel_data.b));

					/* At one draw unit per source pixel, draw a point rather than a larger cell
					rectangle */
					if (safe_cell_size <= 1)
					{
						draw_point(draw_left + pixel_col, draw_top + pixel_row);
					}

					/* Larger cells fill an enlarged rectangle corresponding to the source pixel */
					else
					{
						draw_rectangle(draw_left + pixel_col * safe_cell_size, draw_top + pixel_row * safe_cell_size, draw_left + (pixel_col + 1) * safe_cell_size, draw_top + (pixel_row + 1) * safe_cell_size, false);
					}
				}
			}
		}

		/* Draw the optional outline around the completed pixel grid */
		if (outline)
		{
			draw_set_alpha(draw_alpha);
			draw_set_colour(c_white);
			draw_rectangle(draw_left, draw_top, draw_left + safe_draw_w * safe_cell_size, draw_top + safe_draw_h * safe_cell_size, true);
		}

		draw_set_alpha(1);
	}

	/// @description Draw the cached full-canvas pixel preview with filtering temporarily disabled
	/// @param {Real} draw_left Destination left coordinate
	/// @param {Real} draw_top Destination top coordinate
	/// @param {Real} cell_size Destination size per source pixel
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 1 when omitted
	/// @returns {Bool} Whether an open valid editor was available, even when a preview surface could not be created
	draw_editor_preview_pixels = function(draw_left, draw_top, cell_size, draw_alpha = 1)
	{
		/* An open editor with a valid pixel model is required for the canvas preview */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* perf_token measures this preview draw, safe_cell_size is its enlargement factor, and
		pixel_surface borrows the manager-owned editor cache */
		var perf_token = scr_ui_perf_begin("stamp.preview");
		var safe_cell_size = max(1, real(cell_size));
		var pixel_surface = ensure_editor_surface();

		/* Draw the preview only when its cached surface exists, allowing surface allocation failures
		to leave the GUI running */
		if (surface_exists(pixel_surface))
		{
			/* restore_filter preserves texture interpolation while the pixel preview draws with sharp
			edges */
			var restore_filter = gpu_get_texfilter();
			gpu_set_texfilter(false);
			draw_surface_ext(pixel_surface, draw_left, draw_top, safe_cell_size, safe_cell_size, 0, c_white, draw_alpha);
			gpu_set_texfilter(restore_filter);
		}

		draw_set_alpha(1);
		scr_ui_perf_end("stamp.preview", perf_token);
		return true;
	}

	/// @description Draw a GUI action button with active, disabled, hover, label, and optional icon states
	/// @param {Struct} rect GUI bounds containing left, top, right, and bottom
	/// @param {String} label Button label
	/// @param {Bool} active Whether the action is selected, defaulting to false when omitted
	/// @param {Bool} enabled Whether interaction is available, defaulting to true when omitted
	/// @param {Bool} hovered Whether the pointer highlights the button, defaulting to false when omitted
	/// @param {Id.Sprite} icon_spr Optional icon sprite, defaulting to noone when omitted
	/// @returns {Any} No explicit return value
	draw_stamp_button = function(rect, label, active = false, enabled = true, hovered = false, icon_spr = noone)
	{
		/* fill_colour distinguishes enabled and disabled controls. border_colour highlights active
		controls with the selected yellow accent */
		var fill_colour = enabled ? make_color_rgb(54, 57, 62) : make_color_rgb(34, 36, 40);
		var border_colour = active ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124);

		/* Enabled hovered controls receive brighter fill and border colours, while disabled controls
		keep their inactive appearance */
		if (hovered && enabled)
		{
			fill_colour = make_color_rgb(78, 82, 88);
			border_colour = make_color_rgb(255, 220, 95);
		}

		draw_set_alpha(1);
		draw_set_colour(fill_colour);
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, false);
		draw_set_colour(border_colour);
		draw_rectangle(rect.left, rect.top, rect.right, rect.bottom, true);

		/* Enabled text is white and disabled text uses muted grey */
		draw_set_colour(enabled ? c_white : make_color_rgb(132, 134, 138));

		/* A live icon sprite reserves a left-side image area and aligns the label after it */
		if (sprite_exists(icon_spr))
		{
			/* icon_w and icon_h measure source pixels. icon_scale fits an 18-unit icon area and is
			then restricted to 1 through 2 */
			var icon_w = max(1, sprite_get_width(icon_spr));
			var icon_h = max(1, sprite_get_height(icon_spr));
			var icon_scale = min(18 / icon_w, 18 / icon_h);
			icon_scale = clamp(icon_scale, 1, 2);

			/* icon_left places the icon inside the button and icon_top centers its scaled height
			vertically */
			var icon_left = rect.left + 10;
			var icon_top = rect.top + (rect.bottom - rect.top) * 0.5 - icon_h * icon_scale * 0.5;

			/* Tint the borrowed icon white when enabled and muted grey when disabled, applying its
			origin offsets to the button placement */
			draw_sprite_ext(icon_spr, 0, icon_left + sprite_get_xoffset(icon_spr) * icon_scale, icon_top + sprite_get_yoffset(icon_spr) * icon_scale, icon_scale, icon_scale, 0, enabled ? c_white : make_color_rgb(132, 134, 138), 1);
			draw_set_halign(fa_left);
			scr_render_text(rect.left + 34, rect.top + 5, label, 14, rect.right - rect.left - 40);
		}

		/* Buttons without an icon center their label across the full rectangle */
		else
		{
			draw_set_halign(fa_center);
			scr_render_text((rect.left + rect.right) * 0.5, rect.top + 5, label, 14, rect.right - rect.left - 8);
		}
		draw_set_halign(fa_left);
	}

	/// @description Resolve the cursor icon for the active editor tool, falling back to the pen icon
	/// @returns {Id.Sprite} Authored tool icon sprite
	editor_tool_icon_sprite = function()
	{
		/* Choose the cursor icon for the active pixel tool, with pen as the fallback for unrecognized
		or pen tool values */
		switch (editor_tool)
		{
			/* The eraser tool uses the erase icon */
			case PIXEL_EDITOR_TOOL_ERASER:
				return spr_icon_erase;

			/* The fill tool uses the fill icon */
			case PIXEL_EDITOR_TOOL_FILL:
				return spr_icon_fill;

			/* The colour picker uses the pick icon */
			case PIXEL_EDITOR_TOOL_COLOR_PICKER:
				return spr_icon_pick;

			/* Selection uses the dedicated selection cursor sprite */
			case PIXEL_EDITOR_TOOL_SELECT:
				return spr_cursor_select;
		}

		return spr_icon_pen;
	}

	/// @description Read the active byte-scaled hue, saturation, or value channel
	/// @param {String} slider_key hue, saturation, or value
	/// @returns {Real} Component value, or zero for an unknown key
	editor_hsv_value = function(slider_key)
	{
		/* Select the current 0 to 255 HSV component requested by this slider key */
		switch (slider_key)
		{
			/* Hue sliders read current_hue */
			case "hue":
				return current_hue;

			/* Saturation sliders read current_saturation */
			case "saturation":
				return current_saturation;

			/* Value sliders read current_value */
			case "value":
				return current_value;
		}

		return 0;
	}

	/// @description Build or reuse a manager-owned HSV gradient surface keyed by component, size, and relevant colour channels
	/// @param {String} slider_key hue, saturation, or value
	/// @param {Real} slider_w Gradient width in pixels
	/// @param {Real} slider_h Gradient height in pixels
	/// @returns {Id.Surface} Borrowed cached gradient surface, or noone if allocation fails
	editor_hsv_surface_for = function(slider_key, slider_w, slider_h)
	{
		/* safe_w and safe_h are positive whole slider-surface dimensions. cache_key starts with those
		dimensions before adding the fixed HSV components */
		var safe_w = max(1, floor(real(slider_w)));
		var safe_h = max(1, floor(real(slider_h)));
		var cache_key = string(safe_w) + "x" + string(safe_h);

		/* Each gradient key includes the two colour components that stay fixed while its own slider
		component varies */
		switch (slider_key)
		{
			/* Hue gradients depend on current saturation and value */
			case "hue":
				cache_key += ":h:" + string(current_saturation) + ":" + string(current_value);
				break;

			/* Saturation gradients depend on current hue and value */
			case "saturation":
				cache_key += ":s:" + string(current_hue) + ":" + string(current_value);
				break;

			/* Value gradients depend on current hue and saturation */
			case "value":
				cache_key += ":v:" + string(current_hue) + ":" + string(current_saturation);
				break;
		}

		/* slider_surface starts with no borrowed cache handle and slider_cache_key starts empty until
		the requested component cache is selected */
		var slider_surface = noone;
		var slider_cache_key = "";

		/* Select the corresponding manager-owned gradient surface and its last-rendered content key */
		switch (slider_key)
		{
			/* Hue requests use the hue surface/key pair */
			case "hue":
				slider_surface = editor_hsv_surface_hue;
				slider_cache_key = editor_hsv_key_hue;
				break;

			/* Saturation requests use the saturation surface/key pair */
			case "saturation":
				slider_surface = editor_hsv_surface_saturation;
				slider_cache_key = editor_hsv_key_saturation;
				break;

			/* Value requests use the value surface/key pair */
			case "value":
				slider_surface = editor_hsv_surface_value;
				slider_cache_key = editor_hsv_key_value;
				break;
		}

		/* A cached surface with the wrong dimensions is freed so a replacement can match the requested
		slider rectangle */
		if (surface_exists(slider_surface)
		&& (surface_get_width(slider_surface) != safe_w || surface_get_height(slider_surface) != safe_h))
		{
			surface_free(slider_surface);
			slider_surface = noone;
			slider_cache_key = "";
		}

		/* A missing surface or changed fixed components requires rebuilding the gradient instead of
		reusing stale colour content */
		if (!surface_exists(slider_surface) || slider_cache_key != cache_key)
		{
			/* Free any previous live gradient surface before allocating its replacement */
			if (surface_exists(slider_surface))
			{
				surface_free(slider_surface);
			}

			slider_surface = surface_create(safe_w, safe_h);

			/* Render gradient pixels only after the replacement surface was created successfully */
			if (surface_exists(slider_surface))
			{
				surface_set_target(slider_surface);
				draw_clear_alpha(c_black, 0);

				/* segment_count divides the gradient into 32 horizontal colour samples */
				var segment_count = 32;

				/* segment_index visits the zero-based samples from left to right until the whole
				slider width is filled */
				for (var segment_index = 0; segment_index < segment_count; segment_index++)
				{
					/* t0 and t1 are this segment's normalized left/right positions. segment_colour
					starts white until its HSV component supplies the actual colour */
					var t0 = segment_index / segment_count;
					var t1 = (segment_index + 1) / segment_count;
					var segment_colour = c_white;

					/* Vary the requested HSV component across the segment while holding the other two
					components fixed */
					switch (slider_key)
					{
						/* Hue samples vary hue over the 0 to 255 component scale */
						case "hue":
							segment_colour = hsv_to_colour(round(t0 * 255), current_saturation, current_value);
							break;

						/* Saturation samples vary saturation while preserving hue and value */
						case "saturation":
							segment_colour = hsv_to_colour(current_hue, round(t0 * 255), current_value);
							break;

						/* Value samples vary brightness while preserving hue and saturation */
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

		/* Retain the resulting surface handle and content key in the requested manager-owned component
		cache */
		switch (slider_key)
		{
			/* Store the hue gradient and its completed render key */
			case "hue":
				editor_hsv_surface_hue = slider_surface;
				editor_hsv_key_hue = slider_cache_key;
				break;

			/* Store the saturation gradient and its completed render key */
			case "saturation":
				editor_hsv_surface_saturation = slider_surface;
				editor_hsv_key_saturation = slider_cache_key;
				break;

			/* Store the value gradient and its completed render key */
			case "value":
				editor_hsv_surface_value = slider_surface;
				editor_hsv_key_value = slider_cache_key;
				break;
		}

		return slider_surface;
	}

	/// @description Draw a named HSV gradient, its current value, border, and handle, restoring texture filtering afterward
	/// @param {String} label_text Human-readable component label
	/// @param {String} slider_key hue, saturation, or value
	/// @returns {Any} No explicit return value
	draw_editor_hsv_slider = function(label_text, slider_key)
	{
		/* slider_rect is the GUI slider bounds and slider_value is its current 0 to 255 HSV component */
		var slider_rect = editor_hsv_slider_rect(slider_key);
		var slider_value = editor_hsv_value(slider_key);
		draw_set_halign(fa_left);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(slider_rect.left - 24, slider_rect.top - 1, label_text, 13, 18);

		/* slider_surface borrows the cached gradient generated for this slider's dimensions and fixed
		colour components */
		var slider_surface = editor_hsv_surface_for(slider_key, slider_rect.slider_w, slider_rect.bottom - slider_rect.top);

		/* Draw the gradient only when its cached surface is live */
		if (surface_exists(slider_surface))
		{
			draw_surface(slider_surface, slider_rect.left, slider_rect.top);
		}

		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(slider_rect.left, slider_rect.top, slider_rect.right, slider_rect.bottom, true);

		/* knob_left converts the current byte-scaled component to its horizontal position along the
		GUI slider */
		var knob_left = slider_rect.left + slider_value / 255 * slider_rect.slider_w;
		draw_set_colour(c_black);
		draw_rectangle(knob_left - 3, slider_rect.top - 3, knob_left + 3, slider_rect.bottom + 3, false);
		draw_set_colour(c_white);
		draw_rectangle(knob_left - 2, slider_rect.top - 2, knob_left + 2, slider_rect.bottom + 2, false);
	}

	/// @description Draw the active-colour preview, RGB channel text, palette swatches, and HSV sliders
	/// @returns {Any} No explicit return value
	draw_editor_colour_controls = function()
	{
		/* perf_token measures colour-control drawing. side_left and current_top anchor the panel, and
		current_size is the 42-unit current-colour swatch */
		var perf_token = scr_ui_perf_begin("stamp.colour_controls");
		var side_left = editor_side_left();
		var current_top = editor_colour_top();
		var current_size = 42;

		draw_set_alpha(1);
		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(current_red, current_green, current_blue));
		draw_rectangle(side_left, current_top, side_left + current_size, current_top + current_size, false);
		draw_set_colour(make_color_rgb(190, 190, 194));
		draw_rectangle(side_left, current_top, side_left + current_size, current_top + current_size, true);
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(side_left + current_size + 10, current_top + 4, "Current Color", 13, 112);
		scr_render_text(side_left + current_size + 10, current_top + 22, "RGB " + string(current_red) + ", " + string(current_green) + ", " + string(current_blue), 11, 112);

		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(side_left, current_top + 48, "Swatches", 13, 160);

		/* swatch_index visits every authored RGB swatch for rendering and selection highlighting */
		for (var swatch_index = 0; swatch_index < array_length(editor_colour_swatches); swatch_index++)
		{
			/* swatch supplies its r/g/b byte colour and swatch_rect locates its GUI square */
			var swatch = editor_colour_swatches[swatch_index];
			var swatch_rect = editor_swatch_rect(swatch_index);

			/* swatch_selected requires all three current RGB channels to match. swatch_hovered detects
			this square's hover key */
			var swatch_selected = current_red == swatch.r && current_green == swatch.g && current_blue == swatch.b;
			var swatch_hovered = editor_hover == "swatch_" + string(swatch_index);
			draw_set_colour(make_color_rgb(swatch.r, swatch.g, swatch.b));
			draw_rectangle(swatch_rect.left, swatch_rect.top, swatch_rect.right, swatch_rect.bottom, false);

			/* Selected or hovered swatches receive the yellow accent border, otherwise a neutral grey
			border */
			draw_set_colour(swatch_selected || swatch_hovered ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
			draw_rectangle(swatch_rect.left, swatch_rect.top, swatch_rect.right, swatch_rect.bottom, true);
		}

		draw_editor_hsv_slider("H", "hue");
		draw_editor_hsv_slider("S", "saturation");
		draw_editor_hsv_slider("V", "value");
		scr_ui_perf_end("stamp.colour_controls", perf_token);
	}

	/// @description Draw canvas dimension fields, focus indicators, and the apply-resize button
	/// @returns {Bool} Whether an open valid editor was available
	draw_editor_resize_controls = function()
	{
		/* Resize controls need an open editor and valid pixel model */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* grid_rect anchors the resize row, size_w_rect and size_h_rect are its numeric fields, and
		apply_rect is the commit button */
		var grid_rect = editor_grid_rect();
		var size_w_rect = editor_resize_input_rect("w");
		var size_h_rect = editor_resize_input_rect("h");
		var apply_rect = editor_resize_apply_rect();
		draw_set_halign(fa_left);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(grid_rect.left, size_w_rect.top - 18, "Canvas Size", 13, 100);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(grid_rect.left + 98, size_w_rect.top - 17, stamp_size_range_text(), 11, max(1, editor_left_column_w() - 98));
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(size_w_rect.left - 18, size_w_rect.top + 5, "W", 12, 14);
		scr_render_text(size_h_rect.left - 18, size_h_rect.top + 5, "H", 12, 14);

		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(size_w_rect.left, size_w_rect.top, size_w_rect.right, size_w_rect.bottom, false);
		draw_rectangle(size_h_rect.left, size_h_rect.top, size_h_rect.right, size_h_rect.bottom, false);

		/* Highlight the width border while its field owns text input or the pointer hovers it */
		draw_set_colour(editor_size_focus == "w" || editor_hover == "resize_w" ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
		draw_rectangle(size_w_rect.left, size_w_rect.top, size_w_rect.right, size_w_rect.bottom, true);

		/* Highlight the height border while its field owns text input or the pointer hovers it */
		draw_set_colour(editor_size_focus == "h" || editor_hover == "resize_h" ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
		draw_rectangle(size_h_rect.left, size_h_rect.top, size_h_rect.right, size_h_rect.bottom, true);
		draw_set_colour(c_white);

		/* Focused width text gets a caret on alternating 420-millisecond clock phases */
		scr_render_text(size_w_rect.left + 6, size_w_rect.top + 5, editor_size_w_text + (editor_size_focus == "w" && floor(current_time / 420) mod 2 == 0 ? "|" : ""), 13, size_w_rect.right - size_w_rect.left - 12);

		/* Focused height text uses the same caret phase so numeric editing remains visually consistent */
		scr_render_text(size_h_rect.left + 6, size_h_rect.top + 5, editor_size_h_text + (editor_size_focus == "h" && floor(current_time / 420) mod 2 == 0 ? "|" : ""), 13, size_h_rect.right - size_h_rect.left - 12);

		/* The Apply button highlights only when its resize_apply hover key is active */
		draw_stamp_button(apply_rect, "Apply", false, true, editor_hover == "resize_apply");
		return true;
	}

	/// @description Draw zoom-out, percentage reset, and zoom-in controls with limit-aware enablement
	/// @returns {Bool} Whether an open valid editor was available
	draw_editor_zoom_controls = function()
	{
		/* Zoom controls are drawn only for an open editor with a valid model */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* Enable zoom-out above the minimum, reset away from 100 percent, and zoom-in below the
		maximum. Their individual hover keys select the highlighted control */
		draw_stamp_button(editor_zoom_button_rect("zoom_out"), "Zoom Out", false, editor_zoom_percent > editor_zoom_min, editor_hover == "zoom_out");
		draw_stamp_button(editor_zoom_button_rect("zoom_reset"), "No Zoom", false, editor_zoom_percent != 100, editor_hover == "zoom_reset");
		draw_stamp_button(editor_zoom_button_rect("zoom_in"), "Zoom In", false, editor_zoom_percent < editor_zoom_max, editor_hover == "zoom_in");
		return true;
	}

	/// @description Draw directional viewport controls when source cells extend beyond the viewport
	/// @returns {Bool} Whether an open valid editor required panning controls
	draw_editor_view_controls = function()
	{
		/* Panning controls require an open editor with valid canvas dimensions */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* When the entire canvas is visible in both axes, omit panning controls rather than displaying
		unnecessary arrows */
		if (!editor_view_controls_visible())
		{
			return false;
		}

		/* grid_rect anchors the view row and view_top aligns it below the zoom controls */
		var grid_rect = editor_grid_rect();
		var view_top = editor_view_button_rect("view_left").top;
		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(grid_rect.left, view_top + 5, "View", 13, 40);

		/* Horizontal overflow makes the left panning control visible */
		if (editor_view_button_should_show("view_left"))
		{
			/* can_pan_left is true when the viewport has source columns to its left, enabling and
			highlighting the left button only then */
			var can_pan_left = editor_view_button_enabled("view_left");
			draw_stamp_button(editor_view_button_rect("view_left"), "<", false, can_pan_left, editor_hover == "view_left" && can_pan_left);
		}

		/* Vertical overflow makes the upward panning control visible */
		if (editor_view_button_should_show("view_up"))
		{
			/* can_pan_up is true when there are rows above the viewport, enabling and highlighting the
			up button only then */
			var can_pan_up = editor_view_button_enabled("view_up");
			draw_stamp_button(editor_view_button_rect("view_up"), "^", false, can_pan_up, editor_hover == "view_up" && can_pan_up);
		}

		/* Vertical overflow also makes the downward panning control visible */
		if (editor_view_button_should_show("view_down"))
		{
			/* can_pan_down is true when more rows remain below the viewport */
			var can_pan_down = editor_view_button_enabled("view_down");
			draw_stamp_button(editor_view_button_rect("view_down"), "v", false, can_pan_down, editor_hover == "view_down" && can_pan_down);
		}

		/* Horizontal overflow also makes the right panning control visible */
		if (editor_view_button_should_show("view_right"))
		{
			/* can_pan_right is true when more columns remain to the right of the viewport */
			var can_pan_right = editor_view_button_enabled("view_right");
			draw_stamp_button(editor_view_button_rect("view_right"), ">", false, can_pan_right, editor_hover == "view_right" && can_pan_right);
		}

		/* view_label starts with the viewport's one-based source column and row */
		var view_label = string(editor_view_col + 1) + "," + string(editor_view_row + 1);

		/* If either axis overflows, append the total canvas dimensions to explain the panning position */
		if (grid_rect.visible_cols < editor.grid_w || grid_rect.visible_rows < editor.grid_h)
		{
			view_label += " / " + string(editor.grid_w) + "," + string(editor.grid_h);
		}
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(editor_view_button_rect("view_right").right + 8, view_top + 5, view_label, 11, max(1, grid_rect.viewport_right - editor_view_button_rect("view_right").right - 8));
		return true;
	}

	/// @description Draw visible canvas cells, checkerboard backgrounds, grid outlines, and viewport borders
	/// @returns {Bool} Whether an open valid editor was available
	draw_editor_grid_viewport = function()
	{
		/* The viewport needs an open editor with a valid pixel model */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* perf_token measures grid drawing, grid_rect describes viewport and visible-grid bounds, and
		safe_cell_size measures one enlarged source cell */
		var perf_token = scr_ui_perf_begin("stamp.grid");
		clamp_editor_view();
		var grid_rect = editor_grid_rect();
		var safe_cell_size = max(1, real(grid_rect.cell_size));
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(grid_rect.left, grid_rect.top, grid_rect.viewport_right, grid_rect.viewport_bottom, false);
		draw_transparency_background(grid_rect.left, grid_rect.top, grid_rect.right - grid_rect.left, grid_rect.bottom - grid_rect.top, 1);

		/* pixel_surface borrows the editor's cached RGBA surface for the currently visible source
		region */
		var pixel_surface = ensure_editor_surface();

		/* Only a live cache surface is sampled, leaving the background visible after a failed
		allocation */
		if (surface_exists(pixel_surface))
		{
			/* restore_filter preserves caller texture filtering while the grid is sampled without
			interpolation */
			var restore_filter = gpu_get_texfilter();
			gpu_set_texfilter(false);
			draw_surface_part_ext(pixel_surface, editor_view_col, editor_view_row, grid_rect.visible_cols, grid_rect.visible_rows, grid_rect.left, grid_rect.top, safe_cell_size, safe_cell_size, c_white, 1);
			gpu_set_texfilter(restore_filter);
		}

		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(82, 86, 94));
		draw_rectangle(grid_rect.left, grid_rect.top, grid_rect.viewport_right, grid_rect.viewport_bottom, true);
		draw_set_alpha(0.35);
		draw_set_colour(c_black);

		/* grid_col visits every visible column boundary, including the final edge, to draw vertical
		grid lines */
		for (var grid_col = 0; grid_col <= grid_rect.visible_cols; grid_col++)
		{
			draw_line_width(grid_rect.left + grid_col * safe_cell_size, grid_rect.top, grid_rect.left + grid_col * safe_cell_size, grid_rect.bottom, 2);
		}

		/* grid_row visits every visible row boundary, including the final edge, to draw horizontal
		grid lines */
		for (var grid_row = 0; grid_row <= grid_rect.visible_rows; grid_row++)
		{
			draw_line_width(grid_rect.left, grid_rect.top + grid_row * safe_cell_size, grid_rect.right, grid_rect.top + grid_row * safe_cell_size, 2);
		}

		draw_editor_selection_overlay();

		/* Only the grid hover state adds a pulsing source-cell highlight */
		if (editor_hover == "grid")
		{
			/* gui_x and gui_y are the current pointer coordinates in the same GUI space as the
			viewport */
			var gui_x = device_mouse_x_to_gui(0);
			var gui_y = device_mouse_y_to_gui(0);

			/* The pointer must still lie within the visible grid before its cell highlight is drawn */
			if (point_in_rect(gui_x, gui_y, grid_rect.left, grid_rect.top, grid_rect.right, grid_rect.bottom))
			{
				/* hover_col and hover_row are zero-based viewport-relative cell indices, clamped to
				visible cells */
				var hover_col = clamp(floor((gui_x - grid_rect.left) / safe_cell_size), 0, grid_rect.visible_cols - 1);
				var hover_row = clamp(floor((gui_y - grid_rect.top) / safe_cell_size), 0, grid_rect.visible_rows - 1);

				/* hover_left and hover_top convert that cell to GUI coordinates. pulse_alpha smoothly
				varies the selected-colour fill between zero and one half */
				var hover_left = grid_rect.left + hover_col * safe_cell_size;
				var hover_top = grid_rect.top + hover_row * safe_cell_size;
				var pulse_alpha = (sin(current_time / 160) * 0.5 + 0.5) * 0.5;
				draw_set_alpha(pulse_alpha);
				draw_set_colour(make_color_rgb(current_red, current_green, current_blue));
				draw_rectangle(hover_left, hover_top, hover_left + safe_cell_size, hover_top + safe_cell_size, false); /* Make the entire pixel pulse the selected color */
				draw_set_alpha(pulse_alpha * 2); /* Keep the outline brighter than the pixel fill */
				draw_rectangle(hover_left, hover_top, hover_left + safe_cell_size, hover_top + safe_cell_size, true);
			}
		}

		draw_set_alpha(1);
		scr_ui_perf_end("stamp.grid", perf_token);
		return true;
	}

	/// @description Clip an inclusive source-cell rectangle to the viewport and draw its fill and two-tone outline
	/// @param {Real} raw_left Inclusive zero-based source left column
	/// @param {Real} raw_top Inclusive zero-based source top row
	/// @param {Real} raw_right Inclusive zero-based source right column
	/// @param {Real} raw_bottom Inclusive zero-based source bottom row
	/// @param {Colour} outline_colour Selection fill and outline colour
	/// @param {Real} fill_alpha Fill opacity, defaulting to 0.12 when omitted
	/// @param {Real} outline_alpha Outline opacity, defaulting to 1 when omitted
	/// @returns {Bool} Whether an open valid editor had a visible rectangle to draw
	draw_editor_selection_rect = function(raw_left, raw_top, raw_right, raw_bottom, outline_colour, fill_alpha = 0.12, outline_alpha = 1)
	{
		/* Selection outlines require an open editor with valid canvas state */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* grid_rect anchors the viewport and safe_cell_size is the GUI enlargement of one source pixel */
		var grid_rect = editor_grid_rect();
		var safe_cell_size = max(1, real(grid_rect.cell_size));

		/* visible_left/top/right/bottom are inclusive zero-based source bounds currently visible in
		the editor */
		var visible_left = editor_view_col;
		var visible_top = editor_view_row;
		var visible_right = editor_view_col + grid_rect.visible_cols - 1;
		var visible_bottom = editor_view_row + grid_rect.visible_rows - 1;

		/* draw_left/top/right/bottom_cell clip the requested inclusive selection bounds to those
		visible source cells */
		var draw_left_cell = max(raw_left, visible_left);
		var draw_top_cell = max(raw_top, visible_top);
		var draw_right_cell = min(raw_right, visible_right);
		var draw_bottom_cell = min(raw_bottom, visible_bottom);

		/* A selection completely outside the viewport has no visible rectangle to draw */
		if (draw_right_cell < draw_left_cell || draw_bottom_cell < draw_top_cell)
		{
			return false;
		}

		/* rect_left/top/right/bottom convert the clipped cell bounds to GUI edges, adding one cell at
		the inclusive bottom/right */
		var rect_left = grid_rect.left + (draw_left_cell - editor_view_col) * safe_cell_size;
		var rect_top = grid_rect.top + (draw_top_cell - editor_view_row) * safe_cell_size;
		var rect_right = grid_rect.left + (draw_right_cell - editor_view_col + 1) * safe_cell_size;
		var rect_bottom = grid_rect.top + (draw_bottom_cell - editor_view_row + 1) * safe_cell_size;
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

	/// @description Preview selected nontransparent pixels at a proposed source-cell origin, clipping them to the viewport
	/// @param {Real} target_left_cell Zero-based destination left column
	/// @param {Real} target_top_cell Zero-based destination top row
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 0.82 when omitted
	/// @returns {Bool} Whether an open valid editor had an active selection to preview
	draw_editor_selection_pixel_preview = function(target_left_cell, target_top_cell, draw_alpha = 0.82)
	{
		/* A moved-selection preview requires an open pixel model and active selection */
		if (!editor_open || !is_struct(editor) || !editor.selection_active)
		{
			return false;
		}

		/* grid_rect and safe_cell_size convert selected source pixels to viewport drawing coordinates */
		var grid_rect = editor_grid_rect();
		var safe_cell_size = max(1, real(grid_rect.cell_size));

		/* visible_left/top/right/bottom are inclusive source-cell bounds of the current viewport */
		var visible_left = editor_view_col;
		var visible_top = editor_view_row;
		var visible_right = editor_view_col + grid_rect.visible_cols - 1;
		var visible_bottom = editor_view_row + grid_rect.visible_rows - 1;

		/* source_row visits all inclusive rows of the original selected region */
		for (var source_row = editor.selection_top; source_row <= editor.selection_bottom; source_row++)
		{
			/* target_row offsets this original row from the selection's proposed destination top */
			var target_row = target_top_cell + source_row - editor.selection_top;

			/* Skip moved rows outside the current viewport so the preview cannot draw beyond its
			visible grid */
			if (target_row < visible_top || target_row > visible_bottom)
			{
				continue;
			}

			/* source_col visits every inclusive column of this selected source row */
			for (var source_col = editor.selection_left; source_col <= editor.selection_right; source_col++)
			{
				/* target_col offsets this original column from the proposed destination left */
				var target_col = target_left_cell + source_col - editor.selection_left;

				/* Skip moved columns outside the viewport before reading or drawing their source
				pixels */
				if (target_col < visible_left || target_col > visible_right)
				{
					continue;
				}

				/* pixel_value is the original selected pixel and pixel_alpha is its 0 to 255 opacity */
				var pixel_value = editor.get_pixel(source_col, source_row);
				var pixel_alpha = editor.pixel_alpha(pixel_value);

				/* Transparent selected pixels need no coloured preview primitive */
				if (pixel_alpha <= 0)
				{
					continue;
				}

				/* cell_left and cell_top place this visible moved pixel in GUI coordinates */
				var cell_left = grid_rect.left + (target_col - editor_view_col) * safe_cell_size;
				var cell_top = grid_rect.top + (target_row - editor_view_row) * safe_cell_size;
				draw_set_alpha(draw_alpha * pixel_alpha / 255);
				draw_set_colour(make_color_rgb(editor.pixel_red(pixel_value), editor.pixel_green(pixel_value), editor.pixel_blue(pixel_value)));
				draw_rectangle(cell_left, cell_top, cell_left + safe_cell_size, cell_top + safe_cell_size, false);
			}
		}

		draw_set_alpha(1);
		return true;
	}

	/// @description Draw the active selection or its moving preview using viewport-clipped source bounds
	/// @returns {Bool} Whether a visible selection overlay or active move preview was handled
	draw_editor_selection_overlay = function()
	{
		/* Without an open editor and active selection there is no selection overlay to draw */
		if (!editor_open || !is_struct(editor) || !editor.selection_active)
		{
			return false;
		}

		/* An active move preview draws the original selection faintly, its proposed pixel positions,
		and a brighter destination outline */
		if (editor.selection_preview_active)
		{
			draw_editor_selection_rect(editor.selection_left, editor.selection_top, editor.selection_right, editor.selection_bottom, make_color_rgb(178, 178, 184), 0.04, 0.48);
			draw_editor_selection_pixel_preview(editor.selection_preview_left, editor.selection_preview_top, 0.86);

			/* preview_right and preview_bottom extend the proposed destination by the selection's
			inclusive width and height */
			var preview_right = editor.selection_preview_left + editor.selection_width() - 1;
			var preview_bottom = editor.selection_preview_top + editor.selection_height() - 1;
			draw_editor_selection_rect(editor.selection_preview_left, editor.selection_preview_top, preview_right, preview_bottom, make_color_rgb(255, 220, 95), 0.16, 1);
			return true;
		}

		return draw_editor_selection_rect(editor.selection_left, editor.selection_top, editor.selection_right, editor.selection_bottom, make_color_rgb(255, 220, 95), 0.1, 1);
	}

	/// @description Draw the active tool icon beside the GUI pointer while it hovers over the editor grid
	/// @returns {Bool} Whether the editor grid was hovered and a valid icon was drawn
	draw_editor_grid_cursor = function()
	{
		/* Draw the tool cursor only while the open editor reports the pointer over its grid */
		if (!editor_open || editor_hover != "grid")
		{
			return false;
		}

		/* cursor_spr borrows the authored cursor icon selected for the active editor tool */
		var cursor_spr = editor_tool_icon_sprite();

		/* A missing cursor sprite leaves this overlay undrawn */
		if (!sprite_exists(cursor_spr))
		{
			return false;
		}

		/* gui_x and gui_y locate the pointer in GUI space and cursor_scale doubles the icon for its
		shadow and foreground draws */
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var cursor_scale = 2;
		draw_sprite_ext(cursor_spr, 0, gui_x + 3, gui_y + 3, cursor_scale, cursor_scale, 0, c_black, 0.35);
		draw_sprite_ext(cursor_spr, 0, gui_x + 1, gui_y + 1, cursor_scale, cursor_scale, 0, c_white, 1);
		draw_set_alpha(1);
		return true;
	}

	/// @description Draw a selectable transparency-mode button
	/// @param {String} button_key Modal control identity used for hover state
	/// @param {String} label_text Human-readable mode label
	/// @param {Bool} active Whether this mode is currently selected
	/// @returns {Any} No explicit return value
	draw_transparency_radio = function(button_key, label_text, active)
	{
		/* rect locates this mode control, while mark_left and mark_top anchor its twelve-unit radio
		square */
		var rect = transparency_modal_button_rect(button_key);
		var mark_left = rect.left + 2;
		var mark_top = rect.top + 5;
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(mark_left, mark_top, mark_left + 12, mark_top + 12, false);

		/* The radio border highlights when the matching transparency hover key is active */
		draw_set_colour(editor_hover == "transparency_" + button_key ? make_color_rgb(255, 220, 95) : make_color_rgb(132, 136, 144));
		draw_rectangle(mark_left, mark_top, mark_left + 12, mark_top + 12, true);

		/* The currently selected mode receives a filled radio marker */
		if (active)
		{
			draw_set_colour(make_color_rgb(84, 164, 244));
			draw_rectangle(mark_left + 3, mark_top + 3, mark_left + 9, mark_top + 9, false);
		}

		draw_set_colour(c_white);
		scr_render_text(rect.left + 20, rect.top + 4, label_text, 13, rect.right - rect.left - 22);
	}

	/// @description Draw an RGB colour label, preview swatch, and Use Current colour-copy button in the transparency modal
	/// @param {String} label_text Human-readable colour role
	/// @param {Struct} colour_value RGB byte fields for the preview
	/// @param {Real} row_top Row top coordinate in GUI pixels
	/// @param {String} button_key Modal Use Current colour-copy control identity
	/// @returns {Any} No explicit return value
	draw_transparency_colour_row = function(label_text, colour_value, row_top, button_key)
	{
		/* rect supplies the transparency modal bounds and box_left/box_top locate this row's RGB
		colour preview */
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

		/* Highlight Use Current when the corresponding transparency colour-copy button is hovered */
		draw_stamp_button(transparency_modal_button_rect(button_key), "Use Current", false, true, editor_hover == "transparency_" + button_key);
	}

	/// @description Draw the open transparency settings draft, colour controls, block-size input, and confirmation buttons
	/// @returns {Bool} Whether the transparency modal was open and drawn
	draw_transparency_modal = function()
	{
		/* A closed transparency modal has no overlay to draw */
		if (!transparency_modal_open)
		{
			return false;
		}

		/* rect is the GUI modal rectangle used by all transparency settings controls */
		var rect = transparency_modal_rect();
		draw_set_alpha(0.48);
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
		scr_render_text(rect.left + 18, rect.top + 16, "Transparency Background Settings", 18, rect.modal_w - 36);

		/* Block Pattern is marked active only when the draft mode is block */
		draw_transparency_radio("mode_block", "Block Pattern", transparency_draft_mode == "block");
		draw_transparency_colour_row("Color 1", transparency_draft_color_1, rect.top + 82, "color_1_current");
		draw_transparency_colour_row("Color 2", transparency_draft_color_2, rect.top + 118, "color_2_current");

		/* size_rect locates the checker block-size input field */
		var size_rect = transparency_block_size_input_rect();
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(rect.left + 42, size_rect.top + 6, "Block Size", 13, 88);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(size_rect.left, size_rect.top, size_rect.right, size_rect.bottom, false);

		/* Highlight its border when the field owns text focus or its hover key is active */
		draw_set_colour(editor_hover == "transparency_block_size" || transparency_focus == "block_size" ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
		draw_rectangle(size_rect.left, size_rect.top, size_rect.right, size_rect.bottom, true);
		draw_set_colour(c_white);

		/* Focused block-size text gets a caret on alternating 420-millisecond clock phases */
		scr_render_text(size_rect.left + 6, size_rect.top + 6, transparency_draft_block_size_text + (transparency_focus == "block_size" && floor(current_time / 420) mod 2 == 0 ? "|" : ""), 13, size_rect.right - size_rect.left - 12);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(size_rect.right + 10, size_rect.top + 7, "2-999", 11, 80);

		/* Single Color is marked active only when the draft mode is single */
		draw_transparency_radio("mode_single", "Single Color", transparency_draft_mode == "single");
		draw_transparency_colour_row("Color", transparency_draft_single_color, rect.top + 216, "single_current");

		/* current_colour_box groups the current r/g/b byte channels for the modal's current-colour
		preview */
		var current_colour_box = { r: current_red, g: current_green, b: current_blue };
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(rect.left + 18, rect.bottom - 34, "Current", 11, 54);
		draw_set_colour(make_color_rgb(current_colour_box.r, current_colour_box.g, current_colour_box.b));
		draw_rectangle(rect.left + 74, rect.bottom - 36, rect.left + 102, rect.bottom - 14, false);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(rect.left + 74, rect.bottom - 36, rect.left + 102, rect.bottom - 14, true);

		/* The modal OK and Cancel buttons use their individual hover keys for highlighting */
		draw_stamp_button(transparency_modal_button_rect("ok"), "OK", false, true, editor_hover == "transparency_ok");
		draw_stamp_button(transparency_modal_button_rect("cancel"), "Cancel", false, true, editor_hover == "transparency_cancel");
		draw_set_alpha(1);
		return true;
	}

	/// @description Draw the active size, rename, or delete-confirmation library modal
	/// @returns {Bool} Whether a recognized library modal was drawn
	draw_library_modal = function()
	{
		/* A library with no active modal has no additional dialog to draw */
		if (library_modal == "")
		{
			return false;
		}

		/* modal_rect supplies the active library dialog's GUI bounds */
		var modal_rect = library_modal_rect();
		draw_set_alpha(0.82);
		draw_set_colour(c_black);
		draw_rectangle(modal_rect.left - 4, modal_rect.top - 4, modal_rect.right + 4, modal_rect.bottom + 4, false);
		draw_set_alpha(0.98);
		draw_set_colour(make_color_rgb(32, 34, 36));
		draw_rectangle(modal_rect.left, modal_rect.top, modal_rect.right, modal_rect.bottom, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(modal_rect.left, modal_rect.top, modal_rect.right, modal_rect.bottom, true);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);

		/* The size dialog shows three presets, width/height fields and Create/Cancel controls */
		if (library_modal == "size")
		{
			scr_render_text(modal_rect.left + 14, modal_rect.top + 12, "New Stamp Size", 17, modal_rect.modal_w - 28);
			draw_set_colour(make_color_rgb(210, 210, 214));
			scr_render_text(modal_rect.left + 14, modal_rect.top + 34, "Choose a preset or enter a custom canvas size.", 12, modal_rect.modal_w - 28);

			/* Each preset highlights only when its matching modal_size hover key is active */
			draw_stamp_button(library_modal_button_rect("size_16"), "16x16", false, true, panel_hover == "modal_size_16");
			draw_stamp_button(library_modal_button_rect("size_32"), "32x32", false, true, panel_hover == "modal_size_32");
			draw_stamp_button(library_modal_button_rect("size_48"), "48x48", false, true, panel_hover == "modal_size_48");
			draw_set_colour(make_color_rgb(210, 210, 214));
			scr_render_text(modal_rect.left + 14, modal_rect.top + 94, "Custom", 13, 60);
			scr_render_text(modal_rect.left + 66, modal_rect.top + 118, "W", 12, 14);
			scr_render_text(modal_rect.left + 196, modal_rect.top + 118, "H", 12, 14);

			/* size_w_rect and size_h_rect locate the size dialog's numeric width and height fields */
			var size_w_rect = library_size_input_rect("w");
			var size_h_rect = library_size_input_rect("h");
			draw_set_colour(make_color_rgb(18, 19, 22));
			draw_rectangle(size_w_rect.left, size_w_rect.top, size_w_rect.right, size_w_rect.bottom, false);
			draw_rectangle(size_h_rect.left, size_h_rect.top, size_h_rect.right, size_h_rect.bottom, false);

			/* The width border highlights while focused or hovered */
			draw_set_colour(library_size_focus == "w" || panel_hover == "modal_size_w" ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
			draw_rectangle(size_w_rect.left, size_w_rect.top, size_w_rect.right, size_w_rect.bottom, true);

			/* The height border highlights while focused or hovered */
			draw_set_colour(library_size_focus == "h" || panel_hover == "modal_size_h" ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
			draw_rectangle(size_h_rect.left, size_h_rect.top, size_h_rect.right, size_h_rect.bottom, true);
			draw_set_colour(c_white);

			/* Focused width and height fields each show a caret on alternating 420-millisecond phases */
			scr_render_text(size_w_rect.left + 6, size_w_rect.top + 5, library_size_w_text + (library_size_focus == "w" && floor(current_time / 420) mod 2 == 0 ? "|" : ""), 13, size_w_rect.right - size_w_rect.left - 12);
			scr_render_text(size_h_rect.left + 6, size_h_rect.top + 5, library_size_h_text + (library_size_focus == "h" && floor(current_time / 420) mod 2 == 0 ? "|" : ""), 13, size_h_rect.right - size_h_rect.left - 12);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(modal_rect.left + 296, modal_rect.top + 118, stamp_size_range_text(), 11, 96);

			/* Create and Cancel controls highlight from their respective modal hover keys */
			draw_stamp_button(library_modal_button_rect("custom_create"), "Create", false, true, panel_hover == "modal_custom_create");
			draw_stamp_button(library_modal_button_rect("cancel"), "Cancel", false, true, panel_hover == "modal_cancel");
			return true;
		}

		/* The rename dialog renders the shared keyboard text and Rename/Cancel actions */
		if (library_modal == "rename")
		{
			scr_render_text(modal_rect.left + 14, modal_rect.top + 12, "Rename Stamp", 17, modal_rect.modal_w - 28);
			draw_set_colour(make_color_rgb(210, 210, 214));
			scr_render_text(modal_rect.left + 14, modal_rect.top + 36, "Enter a new display name.", 12, modal_rect.modal_w - 28);
			draw_set_colour(make_color_rgb(18, 19, 22));
			draw_rectangle(modal_rect.left + 14, modal_rect.top + 58, modal_rect.right - 14, modal_rect.top + 84, false);
			draw_set_colour(make_color_rgb(112, 116, 124));
			draw_rectangle(modal_rect.left + 14, modal_rect.top + 58, modal_rect.right - 14, modal_rect.top + 84, true);
			draw_set_colour(c_white);

			/* Rename text shows a caret on alternating 420-millisecond clock phases */
			scr_render_text(modal_rect.left + 20, modal_rect.top + 64, keyboard_string + (floor(current_time / 420) mod 2 == 0 ? "|" : ""), 14, modal_rect.modal_w - 40);

			/* Rename confirmation and cancellation highlight only from their respective modal hover
			keys */
			draw_stamp_button(library_modal_button_rect("confirm"), "Rename", false, true, panel_hover == "modal_confirm");
			draw_stamp_button(library_modal_button_rect("cancel"), "Cancel", false, true, panel_hover == "modal_cancel");
			return true;
		}

		/* The deletion dialog names the local custom stamp and shows Delete/Cancel actions */
		if (library_modal == "delete")
		{
			scr_render_text(modal_rect.left + 14, modal_rect.top + 12, "Delete Stamp", 17, modal_rect.modal_w - 28);
			draw_set_colour(make_color_rgb(244, 84, 84));
			scr_render_text(modal_rect.left + 14, modal_rect.top + 38, library_modal_label, 14, modal_rect.modal_w - 28);
			draw_set_colour(make_color_rgb(210, 210, 214));
			scr_render_text(modal_rect.left + 14, modal_rect.top + 60, "This removes the local custom stamp.", 12, modal_rect.modal_w - 28);

			/* Deletion confirmation and cancellation highlight from their individual modal hover keys */
			draw_stamp_button(library_modal_button_rect("confirm"), "Delete", false, true, panel_hover == "modal_confirm");
			draw_stamp_button(library_modal_button_rect("cancel"), "Cancel", false, true, panel_hover == "modal_cancel");
			return true;
		}

		return false;
	}

	/// @description Draw selected hover metadata near the pointer, keeping the tooltip within GUI bounds
	/// @param {Real} entry_index Zero-based index in entries
	/// @returns {Bool} Whether a valid library entry's tooltip was drawn
	draw_library_entry_tooltip = function(entry_index)
	{
		/* A missing or out-of-range library index cannot provide a hover tooltip */
		if (entry_index == noone
		|| entry_index < 0
		|| entry_index >= array_length(entries))
		{
			return false;
		}

		/* entry is the hovered library record and label_text is its full display name */
		var entry = entries[entry_index];
		var label_text = string(entry.label);

		/* editable_pixels detects existing RGBA data and loadable_stamp detects a deferred PNG that
		may still be loaded */
		var editable_pixels = entry_has_editable_pixels(entry);
		var loadable_stamp = entry_can_lazy_load_png(entry);

		/* type_text prioritizes on-demand PNG loading, then decoded editable pixels, otherwise
		image-only state, distinguishing bundled and custom sources */
		var type_text = loadable_stamp ? (entry.source == "builtin" ? "Built-in stamp - loads on demand" : "Custom stamp - loads on demand") : (editable_pixels ? (entry.source == "builtin" ? "Built-in pixel stamp" : "Editable pixel stamp") : "Image stamp - not editable");

		/* size_text reports source-pixel dimensions. gui_x/y locate the pointer and gui_w/h give the
		available GUI space */
		var size_text = "Source: " + string(entry_stamp_w(entry)) + "x" + string(entry_stamp_h(entry));
		var gui_x = device_mouse_x_to_gui(0);
		var gui_y = device_mouse_y_to_gui(0);
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());

		/* tooltip_w adapts to label/type text within 190 to 340 units and tooltip_h reserves three
		lines. tooltip_left/top stay within the GUI margin near the pointer */
		var tooltip_w = clamp(max(190, max(string_length(label_text), string_length(type_text)) * 7 + 24), 190, 340);
		var tooltip_h = 62;
		var tooltip_left = clamp(gui_x + 14, 4, max(4, gui_w - tooltip_w - 4));
		var tooltip_top = clamp(gui_y + 18, 4, max(4, gui_h - tooltip_h - 4));

		draw_set_alpha(0.95);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(tooltip_left, tooltip_top, tooltip_left + tooltip_w, tooltip_top + tooltip_h, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(tooltip_left, tooltip_top, tooltip_left + tooltip_w, tooltip_top + tooltip_h, true);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);
		scr_render_text(tooltip_left + 8, tooltip_top + 7, label_text, 13, tooltip_w - 16);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(tooltip_left + 8, tooltip_top + 27, type_text, 11, tooltip_w - 16);
		scr_render_text(tooltip_left + 8, tooltip_top + 43, size_text, 11, tooltip_w - 16);
		draw_set_alpha(1);
		return true;
	}

	/// @description Refresh and draw the active library panel, filtered thumbnails, action controls, and hover details
	/// @param {Bool} panel_active Whether the library panel should be drawn
	/// @param {String} active_layer_text Current drawing-layer label, defaulting to empty when omitted
	/// @returns {Bool} Whether the library panel was active and drawn
	draw_library = function(panel_active, active_layer_text = "")
	{
		/* An inactive library panel has no visible library GUI to render */
		if (!panel_active)
		{
			return false;
		}

		/* perf_token measures library drawing and panel_rect supplies its GUI bounds after refreshing
		discovery */
		var perf_token = scr_ui_perf_begin("stamp.draw_library");
		refresh();
		var panel_rect = library_rect();
		draw_set_alpha(0.9);
		draw_set_colour(make_color_rgb(32, 34, 36));
		draw_rectangle(panel_rect.left, panel_rect.top, panel_rect.right, panel_rect.bottom, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(panel_rect.left, panel_rect.top, panel_rect.right, panel_rect.bottom, true);
		draw_set_colour(make_color_rgb(54, 57, 62));
		draw_rectangle(panel_rect.left, panel_rect.top, panel_rect.right, panel_rect.top + 32, false);
		draw_set_colour(c_white);
		scr_render_text(panel_rect.left + 10, panel_rect.top + 8, "Stamp Library", 16, 138);

		/* close_rect locates the header close control */
		var close_rect = library_close_button_rect();
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(panel_rect.left + 142, panel_rect.top + 8, active_layer_text, 14, max(1, close_rect.left - panel_rect.left - 150));

		/* Highlight the header close button from the close hover key */
		draw_stamp_button(close_rect, "X", false, true, panel_hover == "close");

		/* tab_index visits every library category tab to draw its label and active state */
		for (var tab_index = 0; tab_index < array_length(library_tab_keys); tab_index++)
		{
			/* tab_key is this category and tab_label maps all, builtin or custom to a readable label */
			var tab_key = library_tab_keys[tab_index];
			var tab_label = tab_key == "all" ? "All" : (tab_key == "builtin" ? "Built-in" : "Custom");

			/* The selected library_tab gives the active border and its tab_ hover key gives the
			hovered fill */
			draw_stamp_button(library_tab_rect(tab_key), tab_label, library_tab == tab_key, true, panel_hover == "tab_" + tab_key);
		}

		/* thumb_size is a 42-unit image square and gap spaces columns by eight units. grid_left/top
		anchor six columns and two visible rows */
		var thumb_size = 42;
		var gap = 8;
		var grid_left = panel_rect.left + 12;
		var grid_top = panel_rect.top + 72;
		var grid_cols = 6;
		var visible_rows = 2;

		/* filtered maps category-visible positions back to library indices and hovered_entry_index
		starts unresolved for the tooltip below */
		var filtered = library_filtered_indices();
		var hovered_entry_index = noone;
		library_scroll = clamp(library_scroll, 0, library_max_scroll());

		/* visible_index visits at most twelve filtered positions in the current two-row library page */
		for (var visible_index = 0; visible_index < min(array_length(filtered), grid_cols * visible_rows); visible_index++)
		{
			/* absolute_index offsets the visible position by the current whole-row scroll */
			var absolute_index = visible_index + library_scroll * grid_cols;

			/* Stop when scrolling leaves no corresponding filtered entry instead of indexing beyond
			the category list */
			if (absolute_index >= array_length(filtered))
			{
				break;
			}

			/* entry_index maps the filtered position to its source record and entry borrows that
			record */
			var entry_index = filtered[absolute_index];
			var entry = entries[entry_index];

			/* entry_col and entry_row are zero-based page coordinates. thumb_left and thumb_top place
			the thumbnail and its label in GUI space */
			var entry_col = visible_index mod grid_cols;
			var entry_row = floor(visible_index / grid_cols);
			var thumb_left = grid_left + entry_col * (thumb_size + gap);
			var thumb_top = grid_top + entry_row * (thumb_size + 28);

			/* entry_selected compares stable selection identity and hovered compares this record's
			entry_ hover key */
			var entry_selected = entry.key == selected_key;
			var hovered = panel_hover == "entry_" + string(entry_index);

			/* A hovered thumbnail retains its library index for the full-name tooltip after drawing
			the grid */
			if (hovered)
			{
				hovered_entry_index = entry_index;
			}

			/* Selected thumbnails use the selection fill, otherwise hovered thumbnails brighten and
			idle thumbnails keep their neutral fill */
			draw_set_colour(entry_selected ? make_color_rgb(82, 122, 154) : (hovered ? make_color_rgb(58, 62, 68) : make_color_rgb(42, 44, 46)));
			draw_rectangle(thumb_left - 3, thumb_top - 3, thumb_left + thumb_size + 3, thumb_top + thumb_size + 19, false);
			draw_entry_surface(entry_index, thumb_left, thumb_top, thumb_size, thumb_size, 1, false, false, true);

			/* A stamp with no decoded pixels and no available deferred loading/decoding path receives
			the IMG badge */
			if (!entry_has_editable_pixels(entry)
			&& !entry_can_lazy_load_png(entry)
			&& !entry_can_decode_loaded_pixels(entry))
			{
				draw_set_alpha(0.92);
				draw_set_colour(make_color_rgb(18, 19, 22));
				draw_rectangle(thumb_left + 2, thumb_top + 2, thumb_left + 24, thumb_top + 13, false);
				draw_set_alpha(1);
				draw_set_colour(make_color_rgb(255, 220, 95));
				draw_rectangle(thumb_left + 2, thumb_top + 2, thumb_left + 24, thumb_top + 13, true);
				draw_set_halign(fa_center);
				scr_render_text(thumb_left + 13, thumb_top + 3, "IMG", 8, 22);
				draw_set_halign(fa_left);
			}

			/* Selected thumbnails use the yellow outline and other entries use a grey outline */
			draw_set_colour(entry_selected ? make_color_rgb(255, 220, 95) : make_color_rgb(112, 116, 124));
			draw_rectangle(thumb_left - 1, thumb_top - 1, thumb_left + thumb_size + 1, thumb_top + thumb_size + 1, true);

			/* Bundled entry labels use yellow to distinguish their source from white custom labels */
			draw_set_colour(entry.source == "builtin" ? make_color_rgb(255, 220, 95) : c_white);
			draw_set_halign(fa_center);
			scr_render_text(thumb_left + thumb_size * 0.5, thumb_top + thumb_size + 4, library_short_label(entry.label), 11, thumb_size + 8);
			draw_set_halign(fa_left);
		}

		/* max_scroll_value is the last whole-row scroll position available for the current category */
		var max_scroll_value = library_max_scroll();

		/* Only overflowing category lists need row-position text and scroll buttons */
		if (max_scroll_value > 0)
		{
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(panel_rect.right - 88, panel_rect.top + 42, "Rows " + string(library_scroll + 1) + "/" + string(max_scroll_value + 1), 11, 78);

			/* Upward scrolling is enabled above row zero and downward scrolling below the last row.
			Hover highlighting also requires that direction to be enabled */
			draw_stamp_button(library_scroll_button_rect("scroll_up"), "^", false, library_scroll > 0, panel_hover == "scroll_up" && library_scroll > 0);
			draw_stamp_button(library_scroll_button_rect("scroll_down"), "v", false, library_scroll < max_scroll_value, panel_hover == "scroll_down" && library_scroll < max_scroll_value);
		}

		/* selected_stamp is the selected library record or noone for an empty library */
		var selected_stamp = selected_entry();

		/* New and Import remain enabled and highlight on their matching hover keys */
		draw_stamp_button(library_button_rect("new"), "New", false, true, panel_hover == "new");

		/* Edit requires a selected stamp with decoded pixels or an available load/decode path */
		draw_stamp_button(library_button_rect("edit"), "Edit", false, selected_stamp != noone && (entry_has_editable_pixels(selected_stamp) || entry_should_load_or_decode_pixels(selected_stamp)), panel_hover == "edit");

		/* Rename and Delete require a selected custom stamp, preserving bundled entries */
		draw_stamp_button(library_button_rect("rename"), "Rename", false, selected_stamp != noone && selected_stamp.source == "custom", panel_hover == "rename");

		/* Duplicate requires a selected image with editable pixels or available PNG data */
		draw_stamp_button(library_button_rect("duplicate"), "Duplicate", false, selected_stamp != noone && (entry_has_editable_pixels(selected_stamp) || entry_can_provide_png_payload(selected_stamp)), panel_hover == "duplicate");

		/* Delete highlights on its own hover key and remains enabled only for custom selection */
		draw_stamp_button(library_button_rect("delete"), "Delete", false, selected_stamp != noone && selected_stamp.source == "custom", panel_hover == "delete");

		/* Import highlights only from the import hover key */
		draw_stamp_button(library_button_rect("import"), "Import", false, true, panel_hover == "import");

		/* Export requires selected editable pixels or available PNG data */
		draw_stamp_button(library_button_rect("export"), "Export", false, selected_stamp != noone && (entry_has_editable_pixels(selected_stamp) || entry_can_provide_png_payload(selected_stamp)), panel_hover == "export");

		/* Show entry tooltips only when no library dialog covers the panel */
		if (library_modal == "")
		{
			draw_library_entry_tooltip(hovered_entry_index);
		}
		draw_library_modal();
		draw_set_alpha(1);
		scr_ui_perf_end("stamp.draw_library", perf_token);
		return true;
	}

	/// @description Draw the open pixel editor, viewport, tools, colour controls, preview, and any transparency modal
	/// @returns {Bool} Whether the editor was open and drawn
	draw_editor = function()
	{
		/* Draw the stamp editor only while its modal is open and its pixel model exists */
		if (!editor_open || !is_struct(editor))
		{
			return false;
		}

		/* perf_token measures editor drawing. gui_w/h cover its dimmed backdrop and
		modal_rect/grid_rect locate the editor and viewport */
		var perf_token = scr_ui_perf_begin("stamp.draw_editor");
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var modal_rect = editor_rect();
		var grid_rect = editor_grid_rect();
		draw_set_alpha(0.54);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, gui_w, gui_h, false);
		draw_set_alpha(0.96);
		draw_set_colour(make_color_rgb(32, 34, 36));
		draw_rectangle(modal_rect.left, modal_rect.top, modal_rect.right, modal_rect.bottom, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(modal_rect.left, modal_rect.top, modal_rect.right, modal_rect.bottom, true);
		draw_set_colour(c_white);
		scr_render_text(modal_rect.left + 18, modal_rect.top + 16, "Stamp Maker", 20, 180);
		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(modal_rect.left + 170, modal_rect.top + 20, string(editor.grid_w) + "x" + string(editor.grid_h), 14, 70);

		/* The header distinguishes editing an existing custom installation from saving a new custom
		stamp */
		scr_render_text(modal_rect.left + 248, modal_rect.top + 20, editor_existing_custom ? "Editing custom stamp" : "Saves as custom stamp", 14, 240);

		draw_editor_grid_viewport();
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(grid_rect.left, grid_rect.top, grid_rect.right, grid_rect.bottom, true);

		draw_editor_colour_controls();

		draw_set_colour(make_color_rgb(210, 210, 214));
		scr_render_text(editor_side_left(), modal_rect.top + 454, "Preview", 13, 168);

		/* preview_cell_size uses one draw unit per pixel for canvases larger than 32 in either axis,
		otherwise doubles pixels for the small preview */
		var preview_cell_size = editor.grid_w > 32 || editor.grid_h > 32 ? 1 : 2;
		draw_editor_preview_pixels(editor_side_left(), modal_rect.top + 472, preview_cell_size, 1);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_rectangle(editor_side_left(), modal_rect.top + 472, editor_side_left() + editor.grid_w * preview_cell_size, modal_rect.top + 472 + editor.grid_h * preview_cell_size, true);

		/* Tool buttons mark the matching editor_tool active and highlight the pointer's matching hover
		key */
		draw_stamp_button(editor_button_rect("pen"), "Pen", editor_tool == PIXEL_EDITOR_TOOL_PEN, true, editor_hover == "pen", spr_icon_pen);
		draw_stamp_button(editor_button_rect("eraser"), "Eraser", editor_tool == PIXEL_EDITOR_TOOL_ERASER, true, editor_hover == "eraser", spr_icon_erase);
		draw_stamp_button(editor_button_rect("fill"), "Fill", editor_tool == PIXEL_EDITOR_TOOL_FILL, true, editor_hover == "fill", spr_icon_fill);
		draw_stamp_button(editor_button_rect("picker"), "Color Picker", editor_tool == PIXEL_EDITOR_TOOL_COLOR_PICKER, true, editor_hover == "picker", spr_icon_pick);
		draw_stamp_button(editor_button_rect("select"), "Select", editor_tool == PIXEL_EDITOR_TOOL_SELECT, true, editor_hover == "select", spr_icon_select);

		/* Undo and Redo enable only when their respective history stacks can restore a snapshot */
		draw_stamp_button(editor_button_rect("undo"), "Undo", false, editor.can_undo(), editor_hover == "undo");
		draw_stamp_button(editor_button_rect("redo"), "Redo", false, editor.can_redo(), editor_hover == "redo");

		/* Clear and transform controls remain enabled, with each button using its own hover key */
		draw_stamp_button(editor_button_rect("clear"), "Clear", false, true, editor_hover == "clear");
		draw_editor_zoom_controls();
		draw_editor_view_controls();
		draw_stamp_button(editor_button_rect("flip_h"), "Flip H", false, true, editor_hover == "flip_h");
		draw_stamp_button(editor_button_rect("flip_v"), "Flip V", false, true, editor_hover == "flip_v");
		draw_stamp_button(editor_button_rect("rotate_ccw"), "Rot L", false, true, editor_hover == "rotate_ccw");
		draw_stamp_button(editor_button_rect("rotate_cw"), "Rot R", false, true, editor_hover == "rotate_cw");
		draw_stamp_button(editor_button_rect("shift_left"), "Left", false, true, editor_hover == "shift_left");
		draw_stamp_button(editor_button_rect("shift_right"), "Right", false, true, editor_hover == "shift_right");
		draw_stamp_button(editor_button_rect("shift_up"), "Up", false, true, editor_hover == "shift_up");
		draw_stamp_button(editor_button_rect("shift_down"), "Down", false, true, editor_hover == "shift_down");
		draw_editor_resize_controls();

		/* Save and Cancel use their separate hover keys for pointer highlighting */
		draw_stamp_button(editor_button_rect("save"), "Save", false, true, editor_hover == "save");
		draw_stamp_button(editor_button_rect("cancel"), "Cancel", false, true, editor_hover == "cancel");
		draw_transparency_modal();
		draw_set_alpha(1);
		draw_set_halign(fa_left);
		scr_ui_perf_end("stamp.draw_editor", perf_token);
		return true;
	}

	/// @description Draw the library, editor, and library modal in GUI coordinates
	/// @param {Bool} panel_active Whether to draw the ordinary library panel
	/// @param {String} active_layer_text Current drawing-layer label, defaulting to empty when omitted
	/// @returns {Bool} Always true after routing GUI drawing
	draw_gui = function(panel_active, active_layer_text = "")
	{
		/* The library draws beneath the GUI only when the editor is closed, while draw_editor handles
		its own open-state guard */
		if (!editor_open)
		{
			draw_library(panel_active, active_layer_text);
		}
		draw_editor();
		return true;
	}

	/// @description Draw the current unexpired status toast above other GUI content and reset alpha and horizontal alignment
	/// @returns {Bool} Whether a visible status toast was drawn
	draw_top_overlays = function()
	{
		/* No visible unexpired status message means there is no top toast to draw */
		if (!status_is_visible())
		{
			return false;
		}

		/* gui_w bounds the toast. toast_w adapts within 180 to 420 units, toast_h reserves 28 units,
		toast_left centers it and toast_top places it eight units below the GUI top */
		var gui_w = max(1, display_get_gui_width());
		var toast_w = min(420, max(180, gui_w - 24));
		var toast_h = 28;
		var toast_left = max(6, gui_w * 0.5 - toast_w * 0.5);
		var toast_top = 8;
		draw_set_alpha(0.88);
		draw_set_colour(c_black);
		draw_rectangle(toast_left, toast_top, toast_left + toast_w, toast_top + toast_h, false);
		draw_set_alpha(1);
		draw_set_colour(status_color);
		draw_rectangle(toast_left, toast_top, toast_left + toast_w, toast_top + toast_h, true);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(toast_left + toast_w * 0.5, toast_top + 6, status_text, 15, toast_w - 16);
		draw_set_halign(fa_left);
		draw_set_alpha(1);
		return true;
	}
	#endregion /* Stamp GUI Rendering END */

	#region /* Stamp Preview and Placement Payloads */
	/// @description Draw the selected stamp as a translucent outlined placement preview in world coordinates
	/// @param {Real} world_left Destination left world coordinate
	/// @param {Real} world_top Destination top world coordinate
	/// @param {Real} preview_w Destination width, defaulting to stamp_w when omitted and bounded to at least one
	/// @param {Real} preview_h Destination height, defaulting to stamp_h when omitted and bounded to at least one
	/// @returns {Bool} Whether a selected preview image was available and drawn
	draw_selected_world_preview = function(world_left, world_top, preview_w = stamp_w, preview_h = stamp_h)
	{
		refresh();

		/* entry_index resolves the selected stamp for a world-space placement preview */
		var entry_index = selected_entry_index();

		/* Without a selected library record, there is no placement preview to draw */
		if (entry_index == noone)
		{
			return false;
		}

		return draw_entry_surface(entry_index, world_left, world_top, max(1, real(preview_w)), max(1, real(preview_h)), 0.64, false, true);
	}

	/// @description Draw the selected stamp's visible bounds fitted into a toolbar rectangle, preferring its ready PNG sprite
	/// @param {Real} draw_left Toolbar destination left coordinate in GUI pixels
	/// @param {Real} draw_top Toolbar destination top coordinate in GUI pixels
	/// @param {Real} draw_w Toolbar destination width in GUI pixels
	/// @param {Real} draw_h Toolbar destination height in GUI pixels
	/// @param {Real} draw_alpha Opacity multiplier, defaulting to 1 when omitted
	/// @returns {Bool} Whether a selected nonempty image had a ready sprite or surface to draw
	draw_selected_toolbar_icon = function(draw_left, draw_top, draw_w, draw_h, draw_alpha = 1)
	{
		refresh();

		/* entry_index resolves the selected image for the toolbar icon */
		var entry_index = selected_entry_index();

		/* An empty selection has no toolbar icon to render */
		if (entry_index == noone)
		{
			return false;
		}

		/* stamp_sprite borrows the original PNG cache and entry supplies its source-pixel width and
		height */
		var stamp_sprite = ensure_entry_sprite(entry_index);
		var entry = entries[entry_index];
		var entry_w = entry_stamp_w(entry);
		var entry_h = entry_stamp_h(entry);

		/* sprite_ready requires a live sprite matching those dimensions so an asynchronous placeholder
		is not drawn as the stamp */
		var sprite_ready = sprite_exists(stamp_sprite)
			&& sprite_get_width(stamp_sprite) == entry_w
			&& sprite_get_height(stamp_sprite) == entry_h;

		/* Use a pixel-surface fallback only when the original sprite is not ready. bounds is the
		cached inclusive visible-pixel crop */
		var stamp_surface = sprite_ready ? noone : ensure_entry_surface(entry_index);
		var bounds = entry_visible_bounds(entry_index);

		/* When decoded pixels give no visible bounds but the PNG is ready, use the full original image
		so failed decoding cannot hide it */
		if (!bounds.ok && sprite_ready)
		{
			/* A failed editable-pixel decode must not suppress the original PNG */
			/* The fallback bounds cover all source columns and rows and are explicitly marked
			available */
			bounds = { ok: true, min_col: 0, min_row: 0, max_col: entry_w - 1, max_row: entry_h - 1 };
		}

		/* With no usable visible bounds, the selected stamp cannot produce a toolbar icon */
		if (!bounds.ok)
		{
			return false;
		}

		/* crop_w and crop_h measure the inclusive source crop in pixels. icon_w and icon_h are
		positive destination dimensions */
		var crop_w = bounds.max_col - bounds.min_col + 1;
		var crop_h = bounds.max_row - bounds.min_row + 1;
		var icon_w = max(1, real(draw_w));
		var icon_h = max(1, real(draw_h));

		/* icon_scale is the smaller width/height fit. scaled_w/h measure the fitted crop and
		icon_left/top center it in the toolbar rectangle */
		var icon_scale = min(icon_w / crop_w, icon_h / crop_h);
		var scaled_w = crop_w * icon_scale;
		var scaled_h = crop_h * icon_scale;
		var icon_left = draw_left + icon_w * 0.5 - scaled_w * 0.5;
		var icon_top = draw_top + icon_h * 0.5 - scaled_h * 0.5;

		/* restore_filter preserves texture interpolation while the toolbar crop is drawn with sharp
		pixels */
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);

		/* A ready original PNG supplies the toolbar icon before the editable fallback is considered */
		if (sprite_ready)
		{
			draw_sprite_part_ext(stamp_sprite, 0, bounds.min_col, bounds.min_row, crop_w, crop_h, icon_left, icon_top, icon_scale, icon_scale, c_white, draw_alpha);
		}

		/* A live fallback surface supplies the same cropped icon when the original PNG is not ready */
		else if (surface_exists(stamp_surface))
		{
			draw_surface_part_ext(stamp_surface, bounds.min_col, bounds.min_row, crop_w, crop_h, icon_left, icon_top, icon_scale, icon_scale, c_white, draw_alpha);
		}

		/* Without either drawable image, restore the caller's filtering and report failure */
		else
		{
			gpu_set_texfilter(restore_filter);
			return false;
		}
		gpu_set_texfilter(restore_filter);
		draw_set_alpha(1);
		return true;
	}

	/* Only a placement copy is resized. The library PNG remains available at its
	original resolution for editing, export and a later, larger placement */
	/// @description Prepare a PNG copy no larger than the source for one placement. A pending result requires another explicit placement attempt
	/// @param {Real} target_w Requested placement PNG width in pixels, capped at the source width
	/// @param {Real} target_h Requested placement PNG height in pixels, capped at the source height
	/// @returns {Struct} Selected payload plus pending and source_w and source_h for the output PNG. stamp_w and stamp_h retain library dimensions. Check ok before using base64
	placement_payload = function(target_w, target_h)
	{
		/* result begins with selected_payload's validated library image. pending starts false until a
		platform reports preparation still in progress */
		var result = selected_payload();
		result.pending = false;

		/* A failed selected payload cannot be resized and returns its existing diagnostic */
		if (!result.ok)
		{
			return result;
		}

		/* source_w and source_h are the library PNG dimensions. output_w and output_h are positive
		whole requested dimensions capped at the source */
		var source_w = result.stamp_w;
		var source_h = result.stamp_h;
		var output_w = min(source_w, max(1, floor(real(target_w))));
		var output_h = min(source_h, max(1, floor(real(target_h))));

		/* source_w and source_h are added to the result to describe the bytes returned for this
		placement attempt */
		result.source_w = source_w;
		result.source_h = source_h;

		/* A request matching the source dimensions reuses the library PNG without creating a resized
		copy */
		if (output_w == source_w && output_h == source_h)
		{
			return result;
		}

		/* source_base64 retains the original PNG, while smooth_filter enables interpolation for
		image-only stamps and keeps decoded pixel stamps sharp */
		var source_base64 = result.base64;
		var smooth_filter = result.image_only;

		/* Reuse the last resized copy only when selection identity, original bytes, output dimensions,
		filter mode and nonempty cached data all match */
		if (placement_cache_key == selected_key
		&& placement_cache_source == source_base64
		&& placement_cache_w == output_w
		&& placement_cache_h == output_h
		&& placement_cache_smooth == smooth_filter
		&& placement_cache_base64 != "")
		{
			result.base64 = placement_cache_base64;
			result.source_w = output_w;
			result.source_h = output_h;
			return result;
		}

		result.ok = false;
		result.message = "Could not prepare stamp at its placed size.";

		/* resized_base64 starts empty until browser preparation or native surface export produces a
		placement PNG */
		var resized_base64 = "";

		/* Browser preparation may complete asynchronously, requiring another explicit placement
		attempt after a pending result */
		if (uses_browser_storage())
		{
			/* The browser decoder is asynchronous. Preparing a stamp must never
			schedule a delayed placement at a cursor position the player has left */
			try
			{
				resized_base64 = html5_stamp_placement_png(source_base64, source_w, source_h, output_w, output_h, smooth_filter);

				/* An empty browser preparation result needs either a pending status or a reported
				extension error */
				if (resized_base64 == "")
				{
					/* browser_message is the extension's preparation diagnostic. An empty message
					means preparation is pending, while a nonempty one is shown as failure */
					var browser_message = html5_stamp_placement_error();
					result.pending = browser_message == "";
					result.message = browser_message != "" ? browser_message : "Preparing stamp. Click again when ready.";
					return result;
				}
			}
			catch(browser_error)
			{
				result.message = "Could not prepare browser stamp.";
				return result;
			}
		}

		/* Native builds render a separate reduced PNG from the original cached sprite */
		else
		{
			/* stamp_sprite borrows the selected entry's manager-owned PNG sprite */
			var stamp_sprite = ensure_entry_sprite(selected_entry_index());

			/* A missing sprite cannot provide the native placement image */
			if (!sprite_exists(stamp_sprite))
			{
				result.message = "Could not load stamp image.";
				return result;
			}

			/* A sprite whose dimensions still differ from its source PNG is treated as asynchronously
			loading and requires a later explicit placement attempt */
			if (sprite_get_width(stamp_sprite) != source_w
			|| sprite_get_height(stamp_sprite) != source_h)
			{
				result.pending = true;
				result.message = "Stamp image is still loading. Try placing it again.";
				return result;
			}

			/* resize_surface starts with no locally owned allocation, target_active tracks whether it
			needs target cleanup, restore_filter preserves interpolation, and temp_path gives this
			attempt's temporary PNG destination */
			var resize_surface = noone;
			var target_active = false;
			var restore_filter = gpu_get_texfilter();
			var temp_path = path_join(temp_directory,
				"JonnilOnline_StampPlacement_" + string(current_time) + "_" + string(irandom(999999999)) + ".png");
			try
			{
				resize_surface = surface_create(output_w, output_h);

				/* A failed resize-surface allocation throws into the shared cleanup path */
				if (!surface_exists(resize_surface))
				{
					throw "Could not create stamp resize surface.";
				}
				surface_set_target(resize_surface);
				target_active = true;
				gpu_set_texfilter(smooth_filter);
				gpu_set_blendmode_ext(bm_one, bm_zero);
				draw_clear_alpha(c_black, 0);
				draw_sprite_ext(stamp_sprite, 0, 0, 0, output_w / source_w, output_h / source_h, 0, c_white, 1);
				surface_reset_target();
				target_active = false;
				surface_save(resize_surface, temp_path);

				/* png_result inspects and encodes the temporary reduced PNG after it has been saved */
				var png_result = read_png_base64(temp_path);

				/* A failed temporary PNG read leaves no valid placement bytes and enters cleanup with
				its diagnostic */
				if (!png_result.ok)
				{
					throw png_result.message;
				}

				/* The saved PNG must have the requested reduced dimensions before its bytes can be
				returned for placement */
				if (png_result.png_w != output_w || png_result.png_h != output_h)
				{
					throw "Prepared stamp dimensions did not match its placed size.";
				}
				resized_base64 = png_result.base64;
			}
			catch(resize_error)
			{
				/* Exceptions with a message field expose it directly, otherwise convert the thrown
				value to diagnostic text */
				result.message = is_struct(resize_error) && variable_struct_exists(resize_error, "message")
					? string(resize_error.message) : string(resize_error);
			}

			/* If rendering threw while its surface was still the target, reset that target before
			restoring draw state */
			if (target_active)
			{
				try { surface_reset_target(); } catch(target_error) { }
			}
			gpu_set_texfilter(restore_filter);
			gpu_set_blendmode(bm_normal);
			draw_set_alpha(1);

			/* Free this attempt's locally owned resize surface when it remains live after rendering or
			failure */
			if (surface_exists(resize_surface))
			{
				surface_free(resize_surface);
			}

			/* Delete this attempt's temporary PNG when it exists, leaving only the encoded placement
			copy in memory */
			if (file_exists(temp_path))
			{
				try { file_delete(temp_path); } catch(delete_error) { }
			}
		}

		/* Without prepared base64, return the failed result after platform resources have been
		released */
		if (resized_base64 == "")
		{
			return result;
		}

		/* Reject encoded output exceeding the base64 length corresponding to the 2-MiB PNG limit */
		if (string_length(resized_base64) > ceil(stamp_max_import_bytes / 3) * 4)
		{
			result.message = "Prepared stamp exceeds 2 MiB. Choose a smaller stamp size.";
			return result;
		}

		/* Keep only the latest variant, so resizing many stamps cannot grow an
		unbounded second library of encoded images in memory */
		placement_cache_key = selected_key;
		placement_cache_source = source_base64;
		placement_cache_w = output_w;
		placement_cache_h = output_h;
		placement_cache_smooth = smooth_filter;
		placement_cache_base64 = resized_base64;
		result.ok = true;
		result.base64 = resized_base64;
		result.source_w = output_w;
		result.source_h = output_h;
		result.message = "";
		return result;
	}

	/// @description Resolve selected PNG data for placement, loading or encoding it when needed without changing its library dimensions
	/// @returns {Struct} ok, name, stamp_w, stamp_h, image_only, base64, and message. Consumers must check ok
	selected_payload = function()
	{
		refresh();

		/* result starts failed with no selected name or base64, default dimensions, image_only false
		and a no-selection diagnostic */
		var result =
		{
			ok: false,
			name: "",
			stamp_w: stamp_w,
			stamp_h: stamp_h,
			image_only: false,
			base64: "",
			message: "No stamp selected."
		};

		/* entry_index resolves the current library selection */
		var entry_index = selected_entry_index();

		/* An empty selection returns the provisional failed payload */
		if (entry_index == noone)
		{
			return result;
		}

		/* A deferred PNG must load successfully for this explicit action, bypassing the ordinary
		preview load budget */
		if (entry_can_lazy_load_png(entries[entry_index])
		&& !ensure_entry_png_payload(entry_index, false, true))
		{
			result.message = "Could not load built-in stamp PNG.";
			return result;
		}

		/* entry is the resolved library record and base64_text begins with its retained original PNG
		bytes */
		var entry = entries[entry_index];
		var base64_text = entry.base64;

		/* An entry lacking encoded PNG data needs editable pixels to generate a payload */
		if (string_trim(base64_text) == "")
		{
			/* Without either PNG data or editable pixels, reject the selected payload as unavailable */
			if (!entry_has_editable_pixels(entry))
			{
				result.message = "Stamp data is invalid.";
				return result;
			}

			/* encode_result converts the entry's RGBA data to PNG base64 without changing its library
			dimensions */
			var encode_result = hex_to_png_base64(entry.hex, entry_stamp_w(entry), entry_stamp_h(entry));

			/* Encoding failure propagates its diagnostic instead of returning an empty placement image */
			if (!encode_result.ok)
			{
				result.message = encode_result.message;
				return result;
			}

			base64_text = encode_result.base64;
			entry.base64 = base64_text;
			entries[entry_index] = entry;
		}

		/* Reject source dimensions outside import limits or encoded data larger than the allowed 2-MiB
		base64 envelope */
		if (!stamp_import_size_is_supported(entry_stamp_w(entry), entry_stamp_h(entry))
		|| string_length(string(base64_text)) > ceil(stamp_max_import_bytes / 3) * 4)
		{
			result.message = stamp_import_limits_text();
			return result;
		}
		result.ok = true;
		result.name = entry.label;
		result.stamp_w = entry_stamp_w(entry);
		result.stamp_h = entry_stamp_h(entry);

		/* image_only marks canvases exceeding editable-pixel decoding limits, guiding the placement
		resize filter */
		result.image_only = !stamp_can_decode_to_editable_pixels(entry_stamp_w(entry), entry_stamp_h(entry));
		result.base64 = base64_text;
		result.message = "";
		return result;
	}
	#endregion /* Stamp Preview and Placement Payloads END */

}

/// @description Return the shared stamp library and editor manager
/// @returns {Struct} Lazily constructed stamp manager
function scr_get_stamps()
{
	/* stamps is constructed once on the first accessor call and retains the shared library, editor and
	cache ownership for later calls */
	static stamps = new scr_stamps();
	return stamps;
}
