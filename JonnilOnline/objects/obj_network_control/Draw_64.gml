/// @description Draw network menus, session controls, and GUI overlays in priority order

#region /* Diagnostic Shortcuts */
draw_set_colour(c_white);

/* Record whether the folder-confirmation modal owns input. Its draw-layer shortcut
checks use the same blocker so diagnostics cannot consume keys underneath that modal */
var open_folder_modal_blocks_draw_input = scr_get_open_folder_modal().blocks_input();

/* F3 toggles the visible log overlay only outside modal input capture.
Invert show_logs so the next render reflects the requested diagnostic visibility */
if (!open_folder_modal_blocks_draw_input
&& keyboard_check_pressed(vk_f3))
{
	show_logs = !show_logs;
}

/* F2 may change network verbosity only when the folder modal leaves input free */
if (!open_folder_modal_blocks_draw_input
&& keyboard_check_pressed(vk_f2))
{
	/* Borrow the shared network service whose verbose flag controls detailed packet logs */
	var net = scr_get_network();

	/* Toggle verbosity only for an available network service with that flag.
	Report ON/OFF from the resulting state and skip missing support */
	if (is_struct(net)
	&& variable_struct_exists(net, "verbose"))
	{
		net.verbose = !net.verbose;
		debug_log("Network verbose logs: " + (net.verbose ? "ON" : "OFF"));
	}
}

/* F4 requests client network diagnostics only outside folder-modal input capture */
if (!open_folder_modal_blocks_draw_input
&& keyboard_check_pressed(vk_f4))
{
	/* Borrow the client session that owns its network-diagnostics visibility */
	var diagnostics_client = scr_get_client();

	/* An available diagnostics-toggle method can process F4. Missing client support
	leaves its diagnostic display unchanged */
	if (is_struct(diagnostics_client)
	&& variable_struct_exists(diagnostics_client, "toggle_network_diagnostics"))
	{
		diagnostics_client.toggle_network_diagnostics();
	}
}

/* F9 toggles the UI timing overlay only when the folder modal does not own input */
if (!open_folder_modal_blocks_draw_input
&& keyboard_check_pressed(vk_f9))
{
	/* perf_enabled is the resulting timing-overlay state returned by the toggle.
	Use it to report ON or OFF without assuming the previous value */
	var perf_enabled = scr_ui_perf_toggle();
	debug_log("UI perf overlay: " + (perf_enabled ? "ON" : "OFF"));
}
#endregion /* Diagnostic Shortcuts END */

#region /* Options Screen */
/* The open Options screen draws its active page, optional guidance and top folder
modal, then returns. Lower-priority network screens must not cover it */
if (options_screen_open)
{
	options_update_layout();

	/* Capture current GUI width/height in pixels for the Options background and modal veil */
	var options_gui_width = display_get_gui_width();
	var options_gui_height = display_get_gui_height();

	draw_set_colour(make_color_rgb(8, 9, 12));
	draw_rectangle(0, 0, options_gui_width, options_gui_height, false);
	draw_set_colour(make_color_rgb(22, 24, 29));
	draw_rectangle(options_panel_x, options_panel_y, options_panel_x + options_panel_width, options_panel_y + options_panel_height, false);
	draw_set_colour(make_color_rgb(78, 82, 92));
	draw_rectangle(options_panel_x, options_panel_y, options_panel_x + options_panel_width, options_panel_y + options_panel_height, true);

	draw_set_halign(fa_center);
	draw_set_colour(c_white);
	scr_render_text(options_panel_x + options_panel_width * 0.5, options_panel_y + 14, "Options", 30, options_panel_width - 40);
	draw_set_colour(make_color_rgb(190, 194, 203));

	/* Each tab shows its own guidance. Performance can replace its normal subtitle with current
	clipboard feedback */
	var options_subtitle = options_tab == "appearance"
		? "Appearance changes preview immediately and are saved when you Apply."
		: (options_tab == "diagnostics" ? "Show the collision body while testing movement and interactions." : html5_performance.clipboard_status_text());

	/* An empty Performance feedback string receives the normal measured-performance
	subtitle. Appearance keeps its own instructional subtitle */
	if (options_tab == "performance" && options_subtitle == "")
	{
		options_subtitle = "Measured browser performance and safe rendering controls.";
	}
	scr_render_text(options_panel_x + options_panel_width * 0.5, options_panel_y + 44, options_subtitle, 15, options_panel_width - 40);

	/* Tab button hover follows options_hover, while focus highlight requires the Tabs
	focus owner and matching active page. Subdued styling identifies the inactive tab */
	scr_draw_menu_button(options_appearance_tab_x, options_tab_y, options_tab_width, options_tab_height, "Appearance", options_hover == "appearance_tab", options_focus == "tabs" && options_tab == "appearance", true, options_tab != "appearance", false, 17);
	scr_draw_menu_button(options_performance_tab_x, options_tab_y, options_tab_width, options_tab_height, "Performance", options_hover == "performance_tab", options_focus == "tabs" && options_tab == "performance", true, options_tab != "performance", false, 17);
	scr_draw_menu_button(options_diagnostics_tab_x, options_tab_y, options_tab_width, options_tab_height, "Diagnostics", options_hover == "diagnostics_tab", options_focus == "tabs" && options_tab == "diagnostics", true, options_tab != "diagnostics", false, 17);

	/// @description Draw an Options choice row using the controller's current layout, hover and focus state
	/// @param {Real} row_y Top of the row in GUI pixels
	/// @param {String} row_key Field-focus identity for its outline
	/// @param {String} label Visible setting name
	/// @param {String} value Current displayed choice
	/// @param {String} left_key Left-arrow action identity
	/// @param {String} right_key Right-arrow action identity
	var draw_options_choice = function(row_y, row_key, label, value, left_key, right_key)
	{
		scr_draw_menu_button(options_row_left_x, row_y, options_arrow_width, options_row_height, "<", options_hover == left_key, false, true, false, false, 20);
		scr_draw_menu_button(options_row_right_x, row_y, options_arrow_width, options_row_height, ">", options_hover == right_key, false, true, false, false, 20);
		draw_set_colour(make_color_rgb(13, 15, 18));
		draw_rectangle(options_row_value_x, row_y, options_row_value_x + options_row_value_width, row_y + options_row_height, false);

		/* Use the focus accent only for this selected choice row. Other rows retain the
		normal border, showing which row keyboard/gamepad changes currently target */
		draw_set_colour(options_focus == row_key ? make_color_rgb(255, 220, 95) : make_color_rgb(86, 90, 98));
		draw_rectangle(options_row_value_x, row_y, options_row_value_x + options_row_value_width, row_y + options_row_height, true);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(options_row_value_x + options_row_value_width * 0.5, row_y + 10, label + ": " + value, 18, options_row_value_width - 16);
	}

	/* Appearance draws the live draft color, palette controls and shape/transparency choices */
	if (options_tab == "appearance")
	{
		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(218, 220, 226));

		/* options_rgb_text reports the current draft RGB channels. Append Default only
		when that color exactly matches the menu theme's authored default */
		var options_rgb_text = "Color: RGB "
			+ string(colour_get_red(options_draft_colour)) + ", "
			+ string(colour_get_green(options_draft_colour)) + ", "
			+ string(colour_get_blue(options_draft_colour))
			+ (options_draft_colour == scr_menu_button_default_theme().default_colour ? " (Default)" : "");
		scr_render_text(options_hue_x, options_hue_y - 22, options_rgb_text, 16, options_hue_width);

		/* hue_steps divides the hue bar into 64 display slices spanning the HSV hue range.
		The loop uses these samples to draw the palette rather than altering the draft color */
		var hue_steps = 64;

		/* Draw every zero-based hue slice through the last sample. Endpoint scaling covers
		HSV hue values zero through 255 while layout width determines each slice's pixels */
		for (var hue_index = 0; hue_index < hue_steps; hue_index++)
		{
			/* hue_left/right are this slice's GUI-pixel bounds. Extend the right edge by one
			pixel so adjacent sampled rectangles cover the bar without visible gaps */
			var hue_left = options_hue_x + options_hue_width * hue_index / hue_steps;
			var hue_right = options_hue_x + options_hue_width * (hue_index + 1) / hue_steps + 1;
			draw_set_colour(make_color_hsv(hue_index * 255 / (hue_steps - 1), 255, 255));
			draw_rectangle(hue_left, options_hue_y, hue_right, options_hue_y + options_hue_height, false);
		}

		/* hue_marker_x maps the selected zero-to-255 hue into the bar's GUI width.
		The black/white marker makes its position visible across the changing palette */
		var hue_marker_x = options_hue_x + options_hue_width * options_hue / 255;
		draw_set_colour(c_black);
		draw_rectangle(hue_marker_x - 3, options_hue_y - 2, hue_marker_x + 3, options_hue_y + options_hue_height + 2, false);
		draw_set_colour(c_white);
		draw_rectangle(hue_marker_x - 1, options_hue_y - 2, hue_marker_x + 1, options_hue_y + options_hue_height + 2, false);

		/* Sample the saturation/value palette with 32 columns and 12 rows.
		Columns progress from no saturation to full saturation, while rows progress
		from full value at the top to zero value at the bottom */
		var sv_columns = 32;
		var sv_rows = 12;

		/* Visit all zero-based value rows to draw the selected hue's palette.
		Each row contains every saturation-column sample before advancing downward */
		for (var sv_row = 0; sv_row < sv_rows; sv_row++)
		{
			/* sv_top/bottom are this row's GUI bounds, extending the bottom edge one pixel.
			sv_value maps the row to brightness from 255 at the top to zero at the last row */
			var sv_top = options_sv_y + options_sv_height * sv_row / sv_rows;
			var sv_bottom = options_sv_y + options_sv_height * (sv_row + 1) / sv_rows + 1;
			var sv_value = 255 * (1 - sv_row / max(1, sv_rows - 1));

			/* Draw each zero-based saturation column until the row is filled.
			Column position maps to HSV saturation from zero through 255 */
			for (var sv_column = 0; sv_column < sv_columns; sv_column++)
			{
				/* sv_left/right bound this sample in GUI pixels, with one-pixel overlap at the
				right edge. sv_saturation supplies its zero-to-255 horizontal palette channel */
				var sv_left = options_sv_x + options_sv_width * sv_column / sv_columns;
				var sv_right = options_sv_x + options_sv_width * (sv_column + 1) / sv_columns + 1;
				var sv_saturation = 255 * sv_column / max(1, sv_columns - 1);
				draw_set_colour(make_color_hsv(options_hue, sv_saturation, sv_value));
				draw_rectangle(sv_left, sv_top, sv_right, sv_bottom, false);
			}
		}

		/* Accent the palette border only while color editing owns focus.
		Otherwise keep a neutral border around the selectable color area */
		draw_set_colour(options_focus == "colour" ? make_color_rgb(255, 220, 95) : make_color_rgb(150, 154, 164));
		draw_rectangle(options_sv_x, options_sv_y, options_sv_x + options_sv_width, options_sv_y + options_sv_height, true);

		/* sv_marker_x maps current saturation horizontally. sv_marker_y maps current value
		vertically with brighter values toward the top. Both remain GUI-pixel marker positions */
		var sv_marker_x = options_sv_x + options_sv_width * options_saturation / 255;
		var sv_marker_y = options_sv_y + options_sv_height * (1 - options_value / 255);
		draw_set_colour(c_black);
		draw_circle(sv_marker_x, sv_marker_y, 6, true);
		draw_set_colour(c_white);
		draw_circle(sv_marker_x, sv_marker_y, 4, true);

		draw_options_choice(options_shape_y, "shape", "Shape", options_shape_label(), "shape_left", "shape_right");
		draw_options_choice(options_transparency_y, "transparency", "Transparency", options_transparency_label(), "transparency_left", "transparency_right");
		scr_draw_menu_button(options_reset_x, options_reset_y, options_reset_width, options_reset_height, "Reset Appearance to Default", options_hover == "reset", options_focus == "reset", true, true, false, 18);
	}

	/* Diagnostics draws the local collision toggle on every runtime */
	else if (options_tab == "diagnostics")
	{
		/* Off is the authored default. The live value previews immediately, Apply saves it, and
		Cancel restores the value captured when Options opened */
		var collision_mask_label = "Show Collision Mask: " + (global.show_collision_mask ? "On" : "Off (Default)");
		scr_draw_menu_button(options_hue_x, options_collision_mask_y, options_hue_width, options_row_height, collision_mask_label, options_hover == "collision_mask", options_focus == "collision_mask", true, false, false, 18);
		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(218, 220, 226));

		/* Advance by the wrapped height so the instructions stay separate on narrow windows */
		var diagnostics_text_y = options_collision_mask_y + options_row_height + 18;
		diagnostics_text_y += scr_render_text_wrapped(options_hue_x, diagnostics_text_y,
			"Shows the player collision circle, its origin, and sprite offsets. Character artwork becomes transparent so the body is easier to compare.", 18, options_hue_width, 4);
		draw_set_colour(make_color_rgb(188, 192, 201));
		scr_render_text_wrapped(options_hue_x, diagnostics_text_y + 16,
			"Apply saves this setting. Cancel restores the previous setting. The overlay changes only what you see.", 16, options_hue_width, 4);
	}

	/* The Performance page draws browser measurements only on an HTML5 runtime.
	Native builds use the explanatory unavailable-controls alternative */
	else if (html5_performance.is_html5)
	{
		/* performance_left/width align the browser section with the existing palette area,
		and performance_top starts it below the title. performance_compact marks panels
		under 560 GUI pixels tall, selecting a smaller banner, typography and spacing */
		var performance_left = options_hue_x;
		var performance_width = options_hue_width;
		var performance_top = options_panel_y + 116;
		var performance_compact = options_panel_height < 560;

		/* The compact banner is 44 pixels high instead of 52. Begin with an amber color
		and the renderer summary while the renderer checks decide whether to show a
		clearer warning or hardware-classified state */
		var performance_banner_height = performance_compact ? 44 : 52;
		var performance_banner_colour = make_color_rgb(181, 145, 54);
		var performance_banner_text = html5_performance.renderer_summary();

		/* Missing WebGL overrides renderer classification with a red warning and explicit
		unavailable message. Do not present renderer clues as available accelerated rendering */
		if (!webgl_enabled)
		{
			performance_banner_colour = make_color_rgb(170, 67, 70);
			performance_banner_text = "WebGL is unavailable - browser graphics may be limited";
		}

		/* With WebGL present, a hardware-classified renderer receives green status styling.
		That classification comes from service evidence and is not a new acceleration test here */
		else if (html5_performance.renderer_class == "hardware")
		{
			performance_banner_colour = make_color_rgb(62, 128, 82);
		}

		/* A software-classified renderer receives red warning styling.
		Unknown classification keeps the initial amber banner */
		else if (html5_performance.renderer_class == "software")
		{
			performance_banner_colour = make_color_rgb(170, 67, 70);
		}
		draw_set_colour(performance_banner_colour);
		draw_rectangle(performance_left, performance_top, performance_left + performance_width, performance_top + performance_banner_height, false);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);

		/* Compact layout uses the smaller banner text height and inset.
		Normal layout uses the larger values so the summary stays inside either banner */
		scr_render_text(performance_left + performance_width * 0.5, performance_top + (performance_compact ? 12 : 15), performance_banner_text, performance_compact ? 16 : 18, performance_width - 24);

		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(218, 220, 226));

		/* browser_label combines browser name, optional nonempty version and platform.
		performance_info_font_height/gap use compact sizing, while performance_info_y
		starts immediately below the banner for stacked wrapped diagnostic rows */
		var browser_label = html5_performance.browser_name + (html5_performance.browser_version == "" ? "" : " " + html5_performance.browser_version)
			+ " on " + html5_performance.platform_name;
		var performance_info_font_height = performance_compact ? 15 : 16;
		var performance_info_gap = performance_compact ? 5 : 7;
		var performance_info_y = performance_top + performance_banner_height + 10;

		/* Append browser information with WebGL shown as On or Off from its current flag.
		Advance performance_info_y by the rendered wrapped height and the chosen row gap */
		performance_info_y += scr_render_text_wrapped(performance_left, performance_info_y,
			"Browser: " + browser_label + "  |  WebGL: " + (webgl_enabled ? "On" : "Off"),
			performance_info_font_height, performance_width, 3) + performance_info_gap;

		/* Expanded panels draw detailed renderer, sampling and frame-time information.
		Compact panels omit this extra text so the controls remain usable on short windows */
		if (!performance_compact)
		{
			/* renderer_display starts as the full service-reported renderer name before its
			length is bounded for the available detailed row */
			var renderer_display = html5_performance.renderer_name;

			/* Renderer names longer than 112 characters are shortened to 109 plus an ellipsis,
			keeping a long driver/browser string from dominating the details area */
			if (string_length(renderer_display) > 112) renderer_display = string_copy(renderer_display, 1, 109) + "...";
			performance_info_y += scr_render_text_wrapped(performance_left, performance_info_y,
				"Renderer (" + html5_performance.renderer_class + "): " + renderer_display,
				performance_info_font_height, performance_width, 3) + performance_info_gap;
			draw_set_colour(make_color_rgb(202, 207, 216));
			performance_info_y += scr_render_text_wrapped(performance_left, performance_info_y,
				html5_performance.performance_summary(), performance_info_font_height, performance_width, 3) + performance_info_gap;
			performance_info_y += scr_render_text_wrapped(performance_left, performance_info_y,
				"Frame time p50 / p95 / p99 / worst: "
				+ html5_performance.format_ms(html5_performance.frame_p50_ms) + " / "
				+ html5_performance.format_ms(html5_performance.frame_p95_ms) + " / "
				+ html5_performance.format_ms(html5_performance.frame_p99_ms) + " / "
				+ html5_performance.format_ms(html5_performance.frame_worst_ms),
				performance_info_font_height, performance_width, 3) + performance_info_gap;
			performance_info_y += scr_render_text_wrapped(performance_left, performance_info_y,
				"Long frames >20 / >33.3 / >50 ms: " + string(html5_performance.frames_over_20_ms) + " / "
				+ string(html5_performance.frames_over_33_ms) + " / " + string(html5_performance.frames_over_50_ms)
				+ "  (" + string(html5_performance.sample_count) + "/" + string(html5_performance.sample_capacity) + " samples)",
				performance_info_font_height, performance_width, 3) + performance_info_gap;

			/* Draw the reduced-mode explanation only when at least 19 pixels remain before
			the mode control's eight-pixel top margin. Otherwise skip it to avoid overlap */
			if (performance_info_y + 19 <= options_performance_mode_y - 8)
			{
				scr_render_text(performance_left, options_performance_mode_y - 23, "Reduced mode hides the decorative room grid; canvas pixels and saved layers are unchanged.", 15, performance_width);
			}
		}

		/* mode_value begins with the selected draft graphics-mode label. This displays the
		candidate setting before Apply commits it */
		var mode_value = html5_performance.mode_name(html5_performance.draft_mode);

		/* Auto mode also names the currently effective rendering mode, distinguishing its
		policy choice from the mode presently selected by performance management */
		if (html5_performance.draft_mode == JONNIL_HTML5_PERFORMANCE_AUTO)
		{
			mode_value += " (currently " + html5_performance.effective_mode_label() + ")";
		}
		draw_options_choice(options_performance_mode_y, "performance_graphics", "Graphics Mode", mode_value, "performance_left", "performance_right");
		scr_draw_menu_button(options_performance_copy_x, options_performance_copy_y, options_performance_copy_width, options_performance_copy_height, "Copy Diagnostic Report", options_hover == "performance_copy", options_focus == "performance_copy", true, false, false, 17);
		scr_draw_menu_button(options_performance_instructions_x, options_performance_instructions_y, options_performance_instructions_width, options_performance_instructions_height, "Show Browser Instructions", options_hover == "performance_instructions", options_focus == "performance_instructions", true, true, false, 17);
		scr_draw_menu_button(options_performance_reset_x, options_performance_reset_y, options_performance_reset_width, options_performance_reset_height, "Reset Measurements", options_hover == "performance_reset", options_focus == "performance_reset", true, true, false, 17);
	}

	/* Native builds display why browser performance controls are unavailable and draw
	their actions disabled. Appearance and the Options Apply/Cancel controls remain usable */
	else
	{
		draw_set_halign(fa_center);
		draw_set_colour(make_color_rgb(218, 220, 226));
		scr_render_text(options_panel_x + options_panel_width * 0.5, options_panel_y + 175, "HTML5 Performance", 24, options_panel_width - 70);
		draw_set_colour(make_color_rgb(155, 159, 168));
		scr_render_text(options_panel_x + options_panel_width * 0.5, options_panel_y + 225, "Browser diagnostics and graphics modes affect only the HTML5 browser version of Jonnil Online.", 16, options_panel_width - 90);
		scr_draw_menu_button(options_performance_copy_x, options_performance_copy_y, options_performance_copy_width, options_performance_copy_height, "Copy Diagnostic Report (HTML5 only)", false, false, false, true, false, 17);
		scr_draw_menu_button(options_performance_instructions_x, options_performance_instructions_y, options_performance_instructions_width, options_performance_instructions_height, "Browser Instructions (HTML5 only)", false, false, false, true, false, 17);
		scr_draw_menu_button(options_performance_reset_x, options_performance_reset_y, options_performance_reset_width, options_performance_reset_height, "Reset Measurements (HTML5 only)", false, false, false, true, false, 17);
	}

	scr_draw_menu_button(options_apply_x, options_apply_y, options_apply_width, options_apply_height, "Apply", options_hover == "apply", options_focus == "apply", true, false, false, 19);
	scr_draw_menu_button(options_cancel_x, options_cancel_y, options_cancel_width, options_cancel_height, "Cancel", options_hover == "cancel", options_focus == "cancel", true, true, false, 19);

	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(188, 192, 201));

	/* options_help switches to hue/saturation/value instructions while color editing is
	active. Other focus states receive normal choice/tab/navigation guidance */
	var options_help = options_colour_editing
		? "Color edit: arrows/D-pad change saturation and brightness | Q/E or LB/RB changes hue | Enter/A finishes"
		: "Up/Down selects | Left/Right changes choices | Page Up/Down or LB/RB switches tabs | Enter/A activates | Esc/B cancels";
	scr_render_text(options_panel_x + options_panel_width * 0.5, options_panel_y + options_panel_height - 18, options_help, 15, options_panel_width - 34);

	/* An open guidance panel draws above Options with its own veil, text and actions.
	Keep the underlying page visible as context while the panel owns interaction */
	if (options_guidance_open)
	{
		draw_set_alpha(0.78);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, options_gui_width, options_gui_height, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(25, 28, 34));
		draw_rectangle(options_guidance_panel_x, options_guidance_panel_y, options_guidance_panel_x + options_guidance_panel_width, options_guidance_panel_y + options_guidance_panel_height, false);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(options_guidance_panel_x, options_guidance_panel_y, options_guidance_panel_x + options_guidance_panel_width, options_guidance_panel_y + options_guidance_panel_height, true);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(options_guidance_panel_x + options_guidance_panel_width * 0.5, options_guidance_panel_y + 17, "HTML5 Performance Guidance", 28, options_guidance_panel_width - 36);
		draw_set_halign(fa_left);

		/* guidance_lines borrows ordered guidance text. guidance_y starts the body below
		the title and guidance_text_width reserves side margins. guidance_content_height
		bounds the space above Review. Compact panels choose smaller initial text/gaps,
		with item spacing four pixels and total measured height initially zero */
		var guidance_lines = html5_performance.get_guidance_lines();
		var guidance_y = options_guidance_panel_y + 64;
		var guidance_text_width = options_guidance_panel_width - 64;
		var guidance_content_height = max(1, options_guidance_review_y - 14 - guidance_y);
		var guidance_font_height = options_guidance_panel_height < 520 ? 16 : 18;
		var guidance_line_gap = options_guidance_panel_height < 520 ? 3 : 4;
		var guidance_item_gap = 4;
		var guidance_total_height = 0;

		/* Try at most six measurements to fit guidance. Reset the total each pass, then
		reduce text and spacing only when the measured body still exceeds available height */
		repeat (6)
		{
			guidance_total_height = 0;

			/* Measure body entries from index one through the last line, skipping index zero
			because the panel already draws the guidance title */
			for (var guidance_measure_index = 1; guidance_measure_index < array_length(guidance_lines); guidance_measure_index++)
			{
				/* guidance_measure_line is this ordered body entry. Empty entries add a small
				paragraph gap, while text entries add wrapped height plus item spacing */
				var guidance_measure_line = guidance_lines[guidance_measure_index];
				guidance_total_height += guidance_measure_line == ""
					? max(4, floor(guidance_font_height * 0.55))
					: scr_text_wrapped_height(guidance_measure_line, guidance_font_height, guidance_text_width, guidance_line_gap) + guidance_item_gap;
			}

			/* Stop fitting when the body fits or text reaches the 15-pixel minimum.
			Otherwise make the next measurement slightly smaller instead of shrinking indefinitely */
			if (guidance_total_height <= guidance_content_height || guidance_font_height <= 15)
			{
				break;
			}
			guidance_font_height--;
			guidance_line_gap = min(guidance_line_gap, 3);
			guidance_item_gap = max(2, guidance_item_gap - 1);
		}

		/* Draw the measured body entries in their original order, again skipping the title.
		Advance the shared vertical cursor after every paragraph or empty separator */
		for (var guidance_index = 1; guidance_index < array_length(guidance_lines); guidance_index++)
		{
			/* guidance_line is the current body paragraph or empty spacing marker */
			var guidance_line = guidance_lines[guidance_index];

			/* An empty guidance entry advances vertical paragraph spacing and skips text draw.
			It is deliberate separation rather than a missing sentence */
			if (guidance_line == "")
			{
				guidance_y += max(4, floor(guidance_font_height * 0.55));
				continue;
			}

			/* guidance_line_lower provides case-insensitive phrase matching. guidance_warning
			marks software-renderer or missing-WebGL guidance, choosing amber text for those
			warnings and pale text for ordinary instructions */
			var guidance_line_lower = string_lower(guidance_line);
			var guidance_warning = string_pos("software renderer", guidance_line_lower) > 0
				|| string_pos("webgl did not start", guidance_line_lower) > 0;
			draw_set_colour(guidance_warning ? make_color_rgb(255, 198, 126) : make_color_rgb(232, 235, 241));
			guidance_y += scr_render_text_wrapped(options_guidance_panel_x + 32, guidance_y, guidance_line, guidance_font_height, guidance_text_width, guidance_line_gap)
				+ guidance_item_gap;
		}

		/* guidance_review_label says Review Settings for startup guidance, otherwise Back
		to Performance, matching the destination of this panel's primary action */
		var guidance_review_label = options_guidance_startup ? "Review Settings" : "Back to Performance";
		scr_draw_menu_button(options_guidance_review_x, options_guidance_review_y, options_guidance_review_width, options_guidance_review_height, guidance_review_label, options_guidance_hover == "review", options_guidance_focus == "review", true, false, false, 20);

		/* Startup guidance additionally shows Continue so the player can leave the initial
		advice. Guidance opened from Options keeps only its normal return path */
		if (options_guidance_startup)
		{
			scr_draw_menu_button(options_guidance_continue_x, options_guidance_continue_y, options_guidance_continue_width, options_guidance_continue_height, "Continue", options_guidance_hover == "continue", options_guidance_focus == "continue", true, true, false, 20);
		}
	}

	/* Restore common GUI alignment, color and opacity before drawing the top folder
	modal and returning from the Options screen */
	draw_set_halign(fa_left);
	draw_set_colour(c_white);
	draw_set_alpha(1);
	scr_get_open_folder_modal().draw();
	return;
}
#endregion /* Options Screen END */

#region /* Update Notes Screen */
/* An open What's New screen renders its scrollable update notes and then returns.
Other network/gameplay screens must not draw over this full-screen view */
if (whats_new_screen_open)
{
	whats_new_update_layout();

	/* Capture current GUI width/height in pixels for the update-notes background,
	centered title, labels and scroll-track placement */
	var whats_gui_width = display_get_gui_width();
	var whats_gui_height = display_get_gui_height();

	draw_set_colour(make_color_rgb(8, 9, 12));
	draw_rectangle(0, 0, whats_gui_width, whats_gui_height, false);
	draw_set_colour(make_color_rgb(17, 19, 24));
	draw_rectangle(0, 0, whats_gui_width, 112, false);
	draw_set_colour(make_color_rgb(62, 66, 76));
	draw_rectangle(whats_new_text_x, 111, whats_new_text_x + whats_new_text_width, 112, false);

	/* Draw only complete wrapped lines inside the moving content area */
	draw_set_halign(fa_left);
	draw_set_valign(fa_top);
	draw_set_colour(make_color_rgb(232, 234, 239));

	/* whats_line_step combines text height and line spacing in GUI pixels.
	It advances each stored wrapped line through the scrolling body */
	var whats_line_step = whats_new_text_height + whats_new_line_gap;

	/* Visit every zero-based wrapped update line. Only complete lines inside the
	visible content area are drawn, keeping partial rows outside the viewport */
	for (var whats_line_index = 0; whats_line_index < array_length(whats_new_lines); whats_line_index++)
	{
		/* whats_line_y combines the body's top, pixel scroll offset and indexed line step.
		This positions the current stored line without changing its text */
		var whats_line_y = whats_new_text_start_y - whats_new_scroll_offset + whats_line_index * whats_line_step;

		/* Skip lines above the body or whose full text height would cross its bottom.
		Draw no partial line into the fixed title/button areas */
		if (whats_line_y < whats_new_text_start_y
		|| whats_line_y + whats_new_text_height > whats_new_text_end_y)
		{
			continue;
		}
		scr_render_text(whats_new_text_x, whats_line_y, whats_new_lines[whats_line_index], whats_new_text_height, whats_new_text_width);
	}

	/* The update title text, height and centered x/y position define the fixed header,
	independent of the body scroll offset */
	var whats_title = "What's New";
	var whats_title_height = 30;
	var whats_title_x = whats_gui_width * 0.5;
	var whats_title_y = 20;
	draw_set_halign(fa_center);
	draw_set_colour(c_white);
	scr_render_text(whats_title_x, whats_title_y, whats_title, whats_title_height, max(1, whats_gui_width - 48));

	/* Version/date text come from current build metadata. Their 16-pixel labels share
	side margins derived from content inset, with version on the left and date on
	the right. Both initially use the same 75-pixel header baseline */
	var whats_version_text = "Build version: " + game_version_label;
	var whats_date_text = "Build date: " + scr_whats_new_build_datetime();
	var whats_label_height = 16;
	var whats_label_margin = max(12, whats_new_text_x);
	var whats_version_x = whats_label_margin;
	var whats_date_x = whats_gui_width - whats_label_margin;
	var whats_version_y = 75;
	var whats_date_y = 75;

	/* Windows narrower than 620 GUI pixels stack version/date labels on separate
	baselines so their opposing text columns do not compete for the same space */
	if (whats_gui_width < 620)
	{
		whats_version_y = 62;
		whats_date_y = 88;
	}

	draw_set_halign(fa_left);
	draw_set_colour(make_color_rgb(177, 181, 190));
	scr_render_text(whats_version_x, whats_version_y, whats_version_text, whats_label_height, max(1, whats_gui_width * 0.48 - whats_label_margin));
	draw_set_halign(fa_right);
	scr_render_text(whats_date_x, whats_date_y, whats_date_text, whats_label_height, max(1, whats_gui_width * 0.48 - whats_label_margin));

	/* Draw a scrollbar only when the body has overflow that can scroll.
	Short update notes need no track or position indicator */
	if (whats_new_can_scroll)
	{
		/* scroll_track_x places the track beside the body and scroll_track_height matches
		its visible span. scroll_thumb_height scales that span against total content with
		a 22-pixel minimum. scroll_thumb_y maps the current offset onto remaining travel */
		var scroll_track_x = whats_gui_width - max(9, whats_new_text_x * 0.35);
		var scroll_track_height = max(1, whats_new_text_end_y - whats_new_text_start_y);
		var scroll_thumb_height = max(22, scroll_track_height * scroll_track_height / (scroll_track_height + whats_new_scroll_max));
		var scroll_thumb_y = whats_new_text_start_y
			+ (scroll_track_height - scroll_thumb_height) * (whats_new_scroll_offset / max(1, whats_new_scroll_max));
		draw_set_colour(make_color_rgb(42, 45, 52));
		draw_rectangle(scroll_track_x, whats_new_text_start_y, scroll_track_x + 2, whats_new_text_end_y, false);
		draw_set_colour(make_color_rgb(132, 138, 150));
		draw_rectangle(scroll_track_x - 1, scroll_thumb_y, scroll_track_x + 3, scroll_thumb_y + scroll_thumb_height, false);
	}

	/// @description Draw an update-notes action with the controller's current button layout and input focus
	/// @param {Real} button_x Left edge in GUI pixels
	/// @param {String} label Visible action text
	/// @param {String} key Hover and focus action identity
	/// @param {Bool} enabled Whether this action currently permits activation
	var draw_whats_new_button = function(button_x, label, key, enabled)
	{
		scr_draw_menu_button(
			button_x,
			whats_new_button_y,
			whats_new_button_width,
			whats_new_button_height,
			label,
			whats_new_hover == key,
			whats_new_focus == key,
			enabled,
			false,
			false,
			19
		);
	}

	/* Scrollable notes show Up/Down enabled only when more content exists in that
	direction. Nonscrollable notes omit these controls rather than displaying inactive navigation */
	if (whats_new_can_scroll)
	{
		draw_whats_new_button(whats_new_up_button_x, "Up", "up", whats_new_scroll_offset > 0);
		draw_whats_new_button(whats_new_down_button_x, "Down", "down", whats_new_scroll_offset < whats_new_scroll_max);

		/* Show To Top only after scrolling away from the first row.
		At the top, that action would have no effect */
		if (whats_new_scroll_offset > 0)
		{
			draw_whats_new_button(whats_new_top_button_x, "To Top", "top", true);
		}
	}

	/* Back remains available regardless of note length so the current update view can
	always return through its input handler */
	draw_whats_new_button(whats_new_back_button_x, "Back", "back", true);

	draw_set_colour(make_color_rgb(54, 58, 67));
	draw_rectangle(whats_new_text_x, whats_new_text_end_y + 8, whats_new_text_x + whats_new_text_width, whats_new_text_end_y + 9, false);
	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(151, 155, 164));
	scr_render_text(whats_gui_width * 0.5, whats_new_button_y - 20, "Mouse wheel | Left/Right selects | Enter/A activates | Esc/B returns", 13, max(1, whats_gui_width - 48));
	draw_set_alpha(1);
	draw_set_colour(c_white);
	scr_get_open_folder_modal().draw();
	return;
}
#endregion /* Update Notes Screen END */

#region /* Information Screen */
/* The Information screen draws its panel and folder modal, then returns before
network-mode or gameplay UI can cover this view */
if (information_screen_open)
{
	information_update_layout();

	/* Capture current GUI width/height in pixels for Information's veil and centered layout */
	var information_gui_width = display_get_gui_width();
	var information_gui_height = display_get_gui_height();

	draw_set_alpha(0.96);
	draw_set_colour(make_color_rgb(8, 9, 10));
	draw_rectangle(0, 0, information_gui_width, information_gui_height, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(24, 26, 30));
	draw_rectangle(
		information_panel_x,
		information_panel_y,
		information_panel_x + information_panel_width,
		information_panel_y + information_panel_height,
		false
	);
	draw_set_colour(make_color_rgb(76, 78, 84));
	draw_rectangle(
		information_panel_x,
		information_panel_y,
		information_panel_x + information_panel_width,
		information_panel_y + information_panel_height,
		true
	);

	draw_set_halign(fa_center);
	draw_set_valign(fa_top);
	draw_set_colour(c_white);
	scr_render_text(information_gui_width * 0.5, information_panel_y + 27, "Information", 30, information_panel_width - 48);
	draw_set_colour(make_color_rgb(178, 181, 190));
	scr_render_text(information_gui_width * 0.5, information_panel_y + 69, "About Jonnil Online", 20, information_panel_width - 64);

	draw_set_halign(fa_left);
	draw_set_colour(make_color_rgb(224, 227, 233));

	/* about_text is the project's visible description, wrapped inside the information
	panel's content width */
	var about_text = "A relaxed online space for walking around, chatting with friends, and drawing together on one shared canvas.";
	scr_render_text_wrapped(information_panel_x + 38, information_panel_y + 119, about_text, 19, information_panel_width - 76, 7);
	draw_set_colour(make_color_rgb(159, 164, 174));

	/* information_metadata_y positions build/version hints relative to the What's New
	button so they stay above the lower action area */
	var information_metadata_y = information_whats_new_button_y - 72;
	scr_render_text(information_panel_x + 38, information_metadata_y, "Build version: " + game_version_label, 16, information_panel_width - 76);
	scr_render_text(information_panel_x + 38, information_metadata_y + 28, "Press F11 at any time to switch fullscreen.", 16, information_panel_width - 76);

	scr_draw_menu_button(
		information_whats_new_button_x,
		information_whats_new_button_y,
		information_whats_new_button_width,
		information_whats_new_button_height,
		"What's New",
		information_hover_button == "whats_new",
		information_focus == "whats_new",
		true,
		false,
		false,
		19
	);
	scr_draw_menu_button(
		information_back_button_x,
		information_back_button_y,
		information_back_button_width,
		information_back_button_height,
		"Back",
		information_hover_button == "back",
		information_focus == "back",
		true,
		true,
		false,
		19
	);

	/* Unread update notes add a small accent badge to What's New.
	Read notes leave that button without the notification marker */
	if (whats_new_unread)
	{
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_circle(
			information_whats_new_button_x + information_whats_new_button_width - 15,
			information_whats_new_button_y + 12,
			5,
			false
		);
	}

	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(151, 155, 164));
	scr_render_text(information_gui_width * 0.5, information_panel_y + information_panel_height - 24, "Left/Right selects | Enter/A activates | Esc/B returns", 13, information_panel_width - 40);
	draw_set_halign(fa_left);
	draw_set_colour(c_white);
	draw_set_alpha(1);
	scr_get_open_folder_modal().draw();
	return;
}
#endregion /* Information Screen END */

#region /* Network Mode Screen */
/* The network-mode chooser renders its current main/host page and then returns.
Lower network/session controls stay hidden while choosing a mode */
if (network_mode_screen)
{
	network_mode_update_layout();

	/* Capture current GUI dimensions in pixels and borrow network branding/port
	configuration for the chooser's labels and hosting guidance */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var net = scr_get_network();

	draw_set_alpha(0.94);
	draw_set_colour(make_color_rgb(8, 9, 10));
	draw_rectangle(0, 0, gui_width, gui_height, false);
	draw_set_alpha(1);

	draw_set_colour(make_color_rgb(24, 26, 30));
	draw_rectangle(network_mode_panel_x, network_mode_panel_y, network_mode_panel_x + network_mode_panel_width, network_mode_panel_y + network_mode_panel_height, false);
	draw_set_colour(make_color_rgb(76, 78, 84));
	draw_rectangle(network_mode_panel_x, network_mode_panel_y, network_mode_panel_x + network_mode_panel_width, network_mode_panel_y + network_mode_panel_height, true);

	draw_set_halign(fa_center);
	draw_set_colour(c_white);

	/* The host page uses Choose How to Host, while the main chooser uses its configured
	title. This makes the submenu's mode-specific purpose visible */
	var mode_title = network_mode_page == "host" ? "Choose How to Host" : network_mode_title;
	scr_render_text(gui_width * 0.5, network_mode_panel_y + 28, mode_title, 30, network_mode_panel_width - 48);
	draw_set_colour(make_color_rgb(178, 178, 184));

	/* Host-page status uses its current guidance directly. The main page additionally
	prefixes game branding and build version so the chooser identifies this application */
	var mode_status = network_mode_page == "host"
		? network_mode_status
		: net.game_name + " " + game_version_label + " - " + network_mode_status;
	scr_render_text(gui_width * 0.5, network_mode_panel_y + 68, mode_status, 18, network_mode_panel_width - 64);

	/// @description Draw a chooser name field with placeholder and current_time caret animation
	/// @param {Real} x Left edge in GUI pixels
	/// @param {Real} y Top edge in GUI pixels
	/// @param {Real} w Field width in GUI pixels
	/// @param {Real} h Field height in GUI pixels
	/// @param {String} label Visible field name above the rectangle
	/// @param {String} value Current name candidate, kept unchanged
	/// @param {Bool} focused Whether this field owns text input
	var draw_mode_input = function(x, y, w, h, label, value, focused)
	{
		draw_set_halign(fa_left);
		draw_set_colour(c_ltgray);
		scr_render_text(x, y - 24, label, 18, w);

		draw_set_colour(make_color_rgb(8, 8, 8));
		draw_rectangle(x, y, x + w, y + h, false);

		/* Brighten the input border only while this field owns text focus.
		Unfocused input keeps the neutral border */
		draw_set_colour(focused ? make_color_rgb(220, 220, 224) : make_color_rgb(112, 112, 116));
		draw_rectangle(x, y, x + w, y + h, true);

		/* cursor starts empty because an unfocused text field has no caret */
		var cursor = "";

		/* A focused field displays a blinking caret. Unfocused fields retain the empty cursor */
		if (focused)
		{
			cursor = "|";

			/* Alternate caret visibility every 500 current_time milliseconds.
			Hide it during the odd half of the one-second cycle */
			if ((current_time div 500) mod 2 == 1)
			{
				cursor = "";
			}
		}

		/* display_value converts the current name candidate to text. Empty names use a
		dim placeholder color, while actual text uses white */
		var display_value = string(value);
		draw_set_colour(display_value == "" ? make_color_rgb(112, 112, 116) : c_white);

		/* An empty name displays Type your name as a visual hint without changing the
		underlying value used for validation */
		if (display_value == "")
		{
			display_value = "Type your name";
		}
		scr_render_text(x + 12, y + 9, display_value + cursor, 23, w - 24);
	}

	/// @description Draw a mode action using current pointer and eligible gamepad focus from controller state
	/// @param {Real} x Left edge in GUI pixels
	/// @param {Real} y Top edge in GUI pixels
	/// @param {Real} w Button width in GUI pixels
	/// @param {Real} h Button height in GUI pixels
	/// @param {String} label Visible action text
	/// @param {String} key Mode-action identity for hover and gamepad focus
	/// @param {Bool} subdued Whether to use secondary styling and smaller text
	/// @param {Bool} enabled Whether the action currently permits activation
	/// @param {Any} icon Optional shared-menu icon identifier, defaulting to undefined for no icon
	var draw_mode_button = function(x, y, w, h, label, key, subdued, enabled, icon = undefined)
	{
		/* hovered matches this button's key against pointer selection. gamepad_focused
		requires a connected first controller, no active username typing and matching
		gamepad focus, so text editing does not also highlight an action */
		var hovered = network_mode_hover_button == key;
		var gamepad_focused = gamepad_is_connected(0)
			&& network_mode_focus != "username"
			&& network_mode_gamepad_focus == key;

		/* Subdued buttons use 19-pixel labels and primary actions use 22 pixels.
		Forward enabled/hover/focus styling to the shared menu renderer */
		scr_draw_menu_button(x, y, w, h, label, hovered, gamepad_focused, enabled, subdued, false, subdued ? 19 : 22, undefined, icon);
	}

	/* username_ready records whether the current local-play name passes validation.
	It controls Join/Host & Play appearance while console hosting remains available */
	var username_ready = client_username_is_ready();

	/* The host page offers console-only hosting and Host & Play, plus Back.
	Host & Play is enabled only for a valid playable name */
	if (network_mode_page == "host")
	{
		draw_mode_button(network_mode_server_button_x, network_mode_server_button_y, network_mode_server_button_width, network_mode_server_button_height, "Host Server Only", "server", false, true);
		draw_mode_button(network_mode_host_play_button_x, network_mode_host_play_button_y, network_mode_host_play_button_width, network_mode_host_play_button_height, "Host & Play", "host_play", false, username_ready);
		draw_mode_button(network_mode_back_button_x, network_mode_back_button_y, network_mode_back_button_width, network_mode_back_button_height, "Back", "back", true, true);

		/* host_port is the native listen port parsed from the configured default address,
		using the configured TCP port as its fallback for visible hosting guidance */
		var host_port = net.parse_server_address(net.native_default_address, net.port, TRANSPORT_TCP).port;
		draw_set_halign(fa_center);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text_wrapped(gui_width * 0.5, network_mode_back_button_y + network_mode_back_button_height + 14,
			"Hosting ports: TCP " + string(host_port) + " (game), TCP " + string(net.websocket_port)
			+ " (WebSocket), UDP " + string(net.discovery_port) + " (LAN discovery).", 13, network_mode_panel_width - 64, 3);
		scr_render_text(gui_width * 0.5, network_mode_panel_y + network_mode_panel_height - 24,
			"Host & Play on this computer needs no port forwarding.", 12, network_mode_panel_width - 64);
	}

	/* The main chooser shows the username and its mode/settings/help buttons.
	Join uses name readiness while nonjoining actions retain their own eligibility */
	else
	{
		draw_mode_input(network_mode_username_input_x, network_mode_username_input_y, network_mode_username_input_width, network_mode_username_input_height, "Username", client_username, network_mode_focus == "username");
		draw_mode_button(network_mode_host_button_x, network_mode_host_button_y, network_mode_host_button_width, network_mode_host_button_height, "Host", "host", false, true);
		draw_mode_button(network_mode_client_button_x, network_mode_client_button_y, network_mode_client_button_width, network_mode_client_button_height, "Join Server", "client", false, username_ready);
		draw_mode_button(network_mode_singleplayer_button_x, network_mode_singleplayer_button_y, network_mode_singleplayer_button_width, network_mode_singleplayer_button_height, "Singleplayer", "singleplayer", true, true);
		draw_mode_button(network_mode_options_button_x, network_mode_options_button_y, network_mode_options_button_width, network_mode_options_button_height, "Options", "options", false, true, spr_icon_cogwheel);

		/* Draw Quit and its held-Escape progress only when the chooser permits application
		exit through that control. Hidden Quit leaves that corner without exit feedback */
		if (network_mode_show_quit)
		{
			draw_mode_button(network_mode_quit_button_x, network_mode_quit_button_y, network_mode_quit_button_width, network_mode_quit_button_height, "Quit", "quit", false, true, JONNIL_MENU_ICON_QUIT);
			escape_exit_hold_draw_progress(network_mode_quit_button_x, network_mode_quit_button_y, network_mode_quit_button_width, network_mode_quit_button_height, "mode_quit");
		}

		/* A visible browser-performance warning adds its guidance link to the chooser.
		Without that warning, skip its extra action */
		if (network_mode_performance_warning_visible)
		{
			/* performance_warning_gamepad_focused requires a connected gamepad, no username
			text focus and the guidance action selected. It mirrors input routing eligibility */
			var performance_warning_gamepad_focused = gamepad_is_connected(0)
				&& network_mode_focus != "username"
				&& network_mode_gamepad_focus == "performance_guidance";
			scr_draw_menu_button(
				network_mode_performance_warning_x,
				network_mode_performance_warning_y,
				network_mode_performance_warning_width,
				network_mode_performance_warning_height,
				html5_performance.acceleration_warning_label(),
				network_mode_hover_button == "performance_guidance",
				performance_warning_gamepad_focused,
				true,
				false,
				true,
				18
			);
		}

		/* information_gamepad_focused uses the same connected-controller and no-text-focus
		rules before matching the icon-only Information action */
		var information_gamepad_focused = gamepad_is_connected(0)
			&& network_mode_focus != "username"
			&& network_mode_gamepad_focus == "information";
		scr_draw_menu_button(
			network_mode_information_button_x,
			network_mode_information_button_y,
			network_mode_information_button_width,
			network_mode_information_button_height,
			"",
			network_mode_hover_button == "information",
			information_gamepad_focused,
			true,
			false,
			false,
			1,
			undefined,
			JONNIL_MENU_ICON_INFORMATION
		);

		/* Unread updates mark the Information icon so the main chooser advertises What's New.
		Once read, omit the badge */
		if (whats_new_unread)
		{
			draw_set_colour(make_color_rgb(255, 220, 95));
			draw_circle(network_mode_information_button_x + network_mode_information_button_width - 7, network_mode_information_button_y + 7, 5, false);
		}

		/* Show the Information tooltip only when pointer hover or eligible gamepad focus
		identifies that otherwise icon-only control */
		if (network_mode_hover_button == "information"
		|| information_gamepad_focused)
		{
			draw_set_halign(fa_right);
			draw_set_colour(c_white);
			scr_render_text(gui_width - 16, network_mode_information_button_y - 22, "Information", 16, 180);
		}
	}

	draw_set_halign(fa_left);
	draw_set_colour(make_color_rgb(150, 150, 154));

	/* fullscreen_hint names the F11 action that would switch away from the current
	fullscreen state, rather than simply repeating the state already active */
	var fullscreen_hint = window_get_fullscreen() ? "F11: Windowed" : "F11: Fullscreen";
	scr_render_text(16, gui_height - 48, fullscreen_hint, 16, min(220, gui_width - 32));
	scr_render_text(16, gui_height - 24, game_version_label, 16, min(220, gui_width - 32));
	draw_set_alpha(1);

	/* Draw the text diagnostic overlay only when its shared visibility flag is enabled.
	The chooser still restores its normal rendering when diagnostics are hidden */
	if (global.text_debug_overlay)
	{
		scr_render_text_debug_overlay();
	}

	/* Draw the tool cursor without world-tool availability, then place the folder modal
	above the chooser before returning */
	scr_get_drawing().draw_tool_cursor(false);
	scr_get_open_folder_modal().draw();
	return;
}
#endregion /* Network Mode Screen END */

#region /* Server Console and Debug Logs */
/* Server view renders its authoritative status message. The client view skips this
console text because its world/session UI communicates connection status separately */
if (!is_client)
{
	/* Borrow server state and begin server_msg empty. Copy an available status message
	without confusing the service struct with its listener handle */
	var server = scr_get_server();
	var server_msg = "";

	/* Only an available server msg member supplies console text.
	Missing service support leaves the displayed message empty */
	if (is_struct(server) && variable_struct_exists(server, "msg"))
	{
		server_msg = server.msg;
	}

	scr_render_text(50, 100, server_msg, 32);
}

/* Draw and optionally scroll diagnostics only while show_logs is enabled.
Hidden diagnostics consume no wheel or navigation input in this region */
if (show_logs)
{
	/* The folder modal blocks diagnostic scrolling while it owns input.
	Keep drawing the log behind it, but do not react to its keyboard/mouse actions */
	if (!open_folder_modal_blocks_draw_input)
	{
		/* Wheel-up moves the diagnostic history by three rows toward older messages */
		if (mouse_wheel_up())
		{
			debug_scroll(3);
		}

		/* Wheel-down advances three rows toward newer diagnostic messages */
		if (mouse_wheel_down())
		{
			debug_scroll(-3);
		}

		/* Page Up moves fifteen log rows for faster history browsing */
		if (keyboard_check_pressed(vk_pageup))
		{
			debug_scroll(15);
		}

		/* Page Down moves fifteen rows toward the latest log messages */
		if (keyboard_check_pressed(vk_pagedown))
		{
			debug_scroll(-15);
		}

		/* Home resets diagnostic scrolling through the log's home-position helper */
		if (keyboard_check_pressed(vk_home))
		{
			debug_scroll_home();
		}
	}

	/* Client diagnostics occupy the upper half of the GUI so the world remains visible.
	Use a small normalized side margin rather than full-screen coverage */
	if (is_client)
	{
		/* margin is one thirty-second of normalized GUI width on each side.
		The diagnostic helper converts these fractions into its client overlay rectangle */
		var margin = 1/32;
		debug_draw_log(margin, 0, 1 - margin, 1/2, 1/11);
	}

	/* Dedicated server diagnostics use the full GUI area because there is no playable
	world underneath this console log view */
	else
	{
		debug_draw_log(0, 0, 1, 1, 1/10);
	}
}

/* Server view also renders owner controls for local joining, lifecycle and settings.
Client view uses its separate session/admin overlays */
if (!is_client)
{
	server_mode_update_layout();

	/* panel_x1/x2 surround the username field with 12-pixel side margins.
	panel_y1 begins ten GUI pixels from the top and panel_y2 extends below the wall
	control, keeping all console actions inside one backing panel */
	var panel_x1 = server_username_input_x - 12;
	var panel_y1 = 10;
	var panel_x2 = server_username_input_x + server_username_input_width + 12;
	var panel_y2 = server_wall_toggle_button_y + server_wall_toggle_button_height + 34;
	draw_set_alpha(0.94);
	draw_set_colour(make_color_rgb(18, 20, 24));
	draw_rectangle(panel_x1, panel_y1, panel_x2, panel_y2, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(86, 90, 98));
	draw_rectangle(panel_x1, panel_y1, panel_x2, panel_y2, true);

	draw_set_halign(fa_left);
	draw_set_colour(c_ltgray);
	scr_render_text(server_username_input_x, 16, "Username to play", 16, server_username_input_width);
	draw_set_colour(make_color_rgb(8, 8, 8));
	draw_rectangle(server_username_input_x, server_username_input_y, server_username_input_x + server_username_input_width, server_username_input_y + server_username_input_height, false);

	/* Highlight the console username border while its field owns text focus.
	Other focus states keep its normal border */
	draw_set_colour(server_mode_focus == "username" ? make_color_rgb(220, 220, 224) : make_color_rgb(112, 112, 116));
	draw_rectangle(server_username_input_x, server_username_input_y, server_username_input_x + server_username_input_width, server_username_input_y + server_username_input_height, true);

	/* server_username_text starts with the actual local-play name and is modified only
	for placeholder/caret display, leaving the validated name unchanged */
	var server_username_text = client_username;

	/* An empty name uses the placeholder Type your name. It is a visual prompt and
	does not become the stored username */
	if (server_username_text == "")
	{
		server_username_text = "Type your name";
	}

	/* A nonempty focused name appends its caret during the even 500 ms half-cycle.
	Unfocused names and the other half-cycle remain without a caret */
	else if (server_mode_focus == "username" && (current_time div 500) mod 2 == 0)
	{
		server_username_text += "|";
	}

	/* Empty-name placeholder text is dimmed, while actual username text stays white */
	draw_set_colour(client_username == "" ? make_color_rgb(112, 112, 116) : c_white);
	scr_render_text(server_username_input_x + 10, server_username_input_y + 9, server_username_text, 20, server_username_input_width - 20);

	/// @description Draw a console action through shared menu styling without keyboard-focus highlighting
	/// @param {Real} button_x Left edge in GUI pixels
	/// @param {Real} button_y Top edge in GUI pixels
	/// @param {Real} button_w Button width in GUI pixels
	/// @param {Real} button_h Button height in GUI pixels
	/// @param {String} label Visible action text
	/// @param {Bool} hovered Whether the pointer is over this action
	/// @param {Bool} enabled Whether this action currently permits activation
	/// @param {Bool} danger Whether this destructive action needs danger styling
	var draw_server_action_button = function(button_x, button_y, button_w, button_h, label, hovered, enabled, danger)
	{
		scr_draw_menu_button(button_x, button_y, button_w, button_h, label, hovered, false, enabled, false, danger, 18);
	}

	/* Local joining is drawn enabled only for a valid username. Shutdown remains
	available and uses danger styling, with held-Escape progress drawn over its action */
	draw_server_action_button(server_join_button_x, server_join_button_y, server_join_button_width, server_join_button_height, "Join Your Own Server", server_join_button_hover, client_username_is_ready(), false);
	draw_server_action_button(server_shutdown_button_x, server_shutdown_button_y, server_shutdown_button_width, server_shutdown_button_height, "Shut Down Server", server_shutdown_button_hover, true, true);
	escape_exit_hold_draw_progress(server_shutdown_button_x, server_shutdown_button_y, server_shutdown_button_width, server_shutdown_button_height, "server_mode");

	/* console_restart_pending requires available server state reporting either a queued
	or active restart. It disables restart appearance while another restart is underway */
	var console_restart_pending = is_struct(scr_get_server())
		&& ((variable_struct_exists(scr_get_server(), "force_restart_pending") && scr_get_server().force_restart_pending)
			|| (variable_struct_exists(scr_get_server(), "force_restart_in_progress") && scr_get_server().force_restart_in_progress));

	/* console_restart_label asks for confirmation only while the current_time deadline
	is still in the future. Otherwise it presents the ordinary restart action */
	var console_restart_label = server_restart_confirm_until > current_time
		? "Confirm: Archive, Wipe & Restart"
		: "Archive, Wipe & Restart";
	draw_server_action_button(server_restart_button_x, server_restart_button_y, server_restart_button_width, server_restart_button_height, console_restart_label, server_restart_button_hover, !console_restart_pending, true);

	/* server_status_lower supports case-insensitive error phrases. server_status_is_error
	combines invalid username and known save/unavailable/integer-input errors, choosing
	red feedback for those cases and a muted success color otherwise */
	var server_status_lower = string_lower(server_mode_status);
	var server_status_is_error = !client_username_is_ready()
		|| string_pos("could not", server_status_lower) > 0
		|| string_pos("unavailable", server_status_lower) > 0
		|| string_pos("enter a whole number", server_status_lower) > 0;
	draw_set_halign(fa_left);
	draw_set_colour(server_status_is_error ? make_color_rgb(235, 150, 150) : make_color_rgb(170, 190, 176));
	scr_render_text_wrapped(
		server_username_input_x,
		server_restart_button_y + server_restart_button_height + 9,
		server_mode_status,
		15,
		server_username_input_width,
		3
	);

	/* Borrow lifecycle state. reset_enabled needs its available true scheduling flag.
	reset_interval_minutes uses its current interval or the existing 180-minute display
	fallback. reset_countdown uses available countdown support or an unavailable message */
	var lifecycle_server = scr_get_server();
	var reset_enabled = is_struct(lifecycle_server)
		&& variable_struct_exists(lifecycle_server, "automatic_reset_enabled")
		&& lifecycle_server.automatic_reset_enabled;
	var reset_interval_minutes = is_struct(lifecycle_server)
		&& variable_struct_exists(lifecycle_server, "automatic_reset_interval_minutes")
		? lifecycle_server.automatic_reset_interval_minutes
		: 180;
	var reset_countdown = is_struct(lifecycle_server)
		&& variable_struct_exists(lifecycle_server, "reset_countdown_text")
		? lifecycle_server.reset_countdown_text()
		: "Drawing reset timer unavailable";
	draw_set_colour(c_ltgray);
	scr_render_text(server_reset_toggle_button_x, server_reset_toggle_button_y - 42, "Drawing reset timer", 16, server_reset_toggle_button_width);

	/* Use the scheduling accent for enabled reset countdowns and neutral text for
	unlimited scheduling */
	draw_set_colour(reset_enabled ? make_color_rgb(255, 220, 95) : make_color_rgb(150, 150, 156));
	scr_render_text(server_reset_toggle_button_x, server_reset_toggle_button_y - 22, reset_countdown, 14, server_reset_toggle_button_width);

	/* The reset-toggle label reports its current enabled interval in seconds converted
	for display, or Unlimited when scheduling is off */
	draw_server_action_button(
		server_reset_toggle_button_x,
		server_reset_toggle_button_y,
		server_reset_toggle_button_width,
		server_reset_toggle_button_height,
		reset_enabled ? "Enabled: every " + server_reset_duration_text(reset_interval_minutes * 60) : "Unlimited",
		server_reset_toggle_button_hover,
		true,
		false
	);

	/* Draw Minus enabled only above the server's configured minimum reset interval.
	The input handler and setter separately enforce the change */
	draw_server_action_button(server_reset_minus_button_x, server_reset_minus_button_y, server_reset_minus_button_width, server_reset_minus_button_height, "- 30 minutes", server_reset_minus_button_hover, reset_interval_minutes > lifecycle_server.automatic_reset_min_minutes, false);

	/* Plus remains visually enabled only below the server's configured maximum interval */
	draw_server_action_button(server_reset_plus_button_x, server_reset_plus_button_y, server_reset_plus_button_width, server_reset_plus_button_height, "+ 30 minutes", server_reset_plus_button_hover, reset_interval_minutes < lifecycle_server.automatic_reset_max_minutes, false);

	/* Borrow network policy for player-count bounds. server_max_players_valid checks
	the field candidate and server_current_max_players uses available committed state
	or the network's default capacity as a display fallback */
	var server_draw_net = scr_get_network();
	var server_max_players_valid = max_players_input_is_valid(server_max_players_text);
	var server_current_max_players = is_struct(lifecycle_server)
		&& variable_struct_exists(lifecycle_server, "max_players")
		? lifecycle_server.max_players
		: server_draw_net.default_max_players;
	draw_set_halign(fa_left);
	draw_set_colour(c_ltgray);
	scr_render_text(
		server_max_players_input_x,
		server_max_players_input_y - 22,
		"Maximum players (" + string(server_draw_net.min_player_limit) + "-" + string(server_draw_net.max_player_limit) + ")",
		16,
		server_username_input_width
	);
	draw_set_colour(make_color_rgb(8, 8, 8));
	draw_rectangle(
		server_max_players_input_x,
		server_max_players_input_y,
		server_max_players_input_x + server_max_players_input_width,
		server_max_players_input_y + server_max_players_input_height,
		false
	);

	/* Capacity input uses the focus accent while editing, a lighter hover border when
	unfocused but pointed at, and its normal border otherwise */
	draw_set_colour(server_mode_focus == "max_players"
		? make_color_rgb(255, 220, 95)
		: (server_max_players_input_hover ? make_color_rgb(200, 202, 208) : make_color_rgb(112, 116, 124)));
	draw_rectangle(
		server_max_players_input_x,
		server_max_players_input_y,
		server_max_players_input_x + server_max_players_input_width,
		server_max_players_input_y + server_max_players_input_height,
		true
	);

	/* server_max_players_label starts with the typed capacity candidate.
	Caret decoration below affects only this displayed copy */
	var server_max_players_label = server_max_players_text;

	/* Append the capacity caret only while editing and during the even 500 ms half-cycle.
	Other focus/timing states leave the candidate text undecorated */
	if (server_mode_focus == "max_players" && (current_time div 500) mod 2 == 0)
	{
		server_max_players_label += "|";
	}
	draw_set_halign(fa_center);

	/* Use white text for a valid capacity or while it is being edited.
	A finished invalid candidate turns red so incomplete typing is not continually warned */
	draw_set_colour(server_max_players_valid || server_mode_focus == "max_players" ? c_white : make_color_rgb(235, 150, 150));
	scr_render_text(
		server_max_players_input_x + server_max_players_input_width * 0.5,
		server_max_players_input_y + 8,
		server_max_players_label,
		18,
		server_max_players_input_width - 16
	);

	/* Draw Apply enabled only for a valid numeric limit differing from committed
	capacity. Unchanged or invalid text cannot request a meaningful capacity update */
	draw_server_action_button(
		server_max_players_apply_button_x,
		server_max_players_apply_button_y,
		server_max_players_apply_button_width,
		server_max_players_apply_button_height,
		"Apply",
		server_max_players_apply_button_hover,
		server_max_players_valid && max_players_input_value(server_max_players_text) != server_current_max_players,
		false
	);
	draw_set_halign(fa_left);

	/* Borrow drawing UI for server-specific controls and diagnostics beneath the console */
	var server_drawing_gui = scr_get_drawing();

	/* The wall-policy button names the current authoritative ON/OFF state.
	Its input handler performs the mutation, while this draw only reports the setting */
	draw_server_action_button(server_wall_toggle_button_x, server_wall_toggle_button_y, server_wall_toggle_button_width, server_wall_toggle_button_height,
		lifecycle_server.wall_drawing_enabled ? "Wall Drawing: ON" : "Wall Drawing: OFF", server_wall_toggle_button_hover, true, false);
	draw_set_halign(fa_left);
	draw_set_colour(c_ltgray);
	scr_render_text(server_wall_toggle_button_x, server_wall_toggle_button_y + server_wall_toggle_button_height + 7, "Off makes existing walls passable.", 13, server_wall_toggle_button_width);
	server_drawing_gui.draw_server_gui();
	server_drawing_gui.draw_debug_overlay(true);
}
#endregion /* Server Console and Debug Logs END */

#region /* Server Selection Screen */
/* Draw server selection only for the client view with its join screen visible.
Other views leave these rows and dialogs out of the GUI */
if (is_client && client_join_screen)
{
	client_join_update_layout();

	/* Capture current GUI dimensions and borrow client/network services for server-list
	content and branding. entries begins empty until an available list builder supplies rows */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var client = scr_get_client();
	var net = scr_get_network();
	var entries = [];

	/* Only an available client list builder replaces the empty row array.
	Missing support leaves the scanning view rather than calling absent functionality */
	if (is_struct(client)
	&& variable_struct_exists(client, "build_server_list_entries"))
	{
		entries = client.build_server_list_entries();
	}

	/* row_count is the current snapshot's number of list entries, including informational rows */
	var row_count = array_length(entries);

	draw_set_alpha(0.92);
	draw_set_colour(make_color_rgb(8, 9, 10));
	draw_rectangle(0, 0, gui_width, gui_height, false);
	draw_set_alpha(1);

	draw_set_colour(make_color_rgb(35, 35, 38));
	draw_line(0, 62, gui_width, 62);
	draw_line(0, client_join_button_y - 16, gui_width, client_join_button_y - 16);

	draw_set_halign(fa_center);
	draw_set_colour(c_white);
	scr_render_text(gui_width * 0.5, 22, net.game_name + " " + game_version_label, 26, client_join_panel_width - 48);

	draw_set_halign(fa_left);
	draw_set_colour(make_color_rgb(150, 150, 154));
	scr_render_text(16, 18, client_device_label, 16, min(320, gui_width * 0.32));
	draw_set_halign(fa_right);
	scr_render_text(gui_width - 16, 18, "Username: " + client_username, 16, min(320, gui_width * 0.32));
	draw_set_halign(fa_left);

	draw_set_colour(make_color_rgb(6, 6, 8));
	draw_rectangle(client_join_list_x, client_join_list_y, client_join_list_x + client_join_list_width, client_join_list_y + client_join_list_height, false);
	draw_set_colour(make_color_rgb(64, 64, 68));
	draw_rectangle(client_join_list_x, client_join_list_y, client_join_list_x + client_join_list_width, client_join_list_y + client_join_list_height, true);

	/* visible_rows converts GUI list height to at least one whole row. first_row uses
	the scroll index and last_row bounds that page by the snapshot count, preventing
	drawing past the final available entry */
	var visible_rows = max(1, floor(client_join_list_height / client_join_row_height));
	var first_row = client_join_scroll;
	var last_row = min(row_count, first_row + visible_rows);

	/* An empty list shows animated scanning feedback instead of indexing nonexistent
	server entries. Informational/header entries take the nonempty-list path */
	if (row_count <= 0)
	{
		/* dots begins empty and dot_count cycles zero through three every 350 current_time
		milliseconds, animating scanning without storing separate timer state */
		var dots = "";
		var dot_count = (current_time div 350) mod 4;

		/* Append exactly dot_count periods from counter zero, then stop.
		Zero dots renders the blank phase of the scanning animation */
		for (var dot = 0; dot < dot_count; dot++)
		{
			dots += ".";
		}

		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(client_join_list_x + client_join_list_width * 0.5, client_join_list_y + client_join_list_height * 0.5 - 28, "Scanning for games on your local network", 22, client_join_list_width - 32);
		draw_set_colour(c_ltgray);
		scr_render_text(client_join_list_x + client_join_list_width * 0.5, client_join_list_y + client_join_list_height * 0.5 + 4, dots, 22, client_join_list_width - 32);
		draw_set_halign(fa_left);
	}

	/* A nonempty snapshot draws only its current visible page of rows */
	else
	{
		/* Visit zero-based entries from first_row up to the bounded last_row.
		This limits drawing to the visible page rather than rendering the entire server list */
		for (var row = first_row; row < last_row; row++)
		{
			/* local_row is the row's position within the page. row_x/y/w/h inset its GUI
			rectangle by two pixels. selected/hovered compare its snapshot index with current
			selection/pointer state, and entry borrows the current server/information descriptor */
			var local_row = row - first_row;
			var row_x = client_join_list_x + 2;
			var row_y = client_join_list_y + 2 + local_row * client_join_row_height;
			var row_w = client_join_list_width - 4;
			var row_h = client_join_row_height - 4;
			var selected = row == client_join_selected;
			var hovered = row == client_join_hover_row;
			var entry = entries[row];

			/* Separator entries draw only a group heading and dividing line.
			Continue to the next row so headers never receive server availability graphics */
			if (entry.kind == "separator")
			{
				draw_set_colour(make_color_rgb(13, 13, 16));
				draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_h, false);
				draw_set_colour(make_color_rgb(92, 92, 98));
				draw_line(row_x + 8, row_y + 34, row_x + row_w - 8, row_y + 34);
				draw_set_colour(make_color_rgb(210, 210, 214));
				scr_render_text(row_x + 16, row_y + 22, entry.label, 16, row_w - 32);
				continue;
			}

			/* Empty-group information draws its label centered, then skips normal server details.
			It has no selectable endpoint, capacity or latency icon */
			if (entry.kind == "empty")
			{
				draw_set_colour(make_color_rgb(16, 17, 20));
				draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_h, false);
				draw_set_halign(fa_center);
				draw_set_colour(make_color_rgb(166, 166, 170));
				scr_render_text(row_x + row_w * 0.5, row_y + 22, entry.label, 18, row_w - 32);
				draw_set_halign(fa_left);
				continue;
			}

			/* row_color starts with the selected-row background or normal server-row background.
			The next hover check may accent only an unselected row */
			var row_color = selected ? make_color_rgb(72, 78, 88) : make_color_rgb(20, 22, 26);

			/* Hovering an unselected row brightens its background. Selection retains the
			stronger selected color instead of being overwritten by pointer hover */
			if (hovered && !selected)
			{
				row_color = make_color_rgb(38, 42, 48);
			}

			draw_set_colour(row_color);
			draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_h, false);

			/* Only the selected row receives an outline, keeping keyboard selection visible
			even when the pointer highlights a different server */
			if (selected)
			{
				draw_set_colour(make_color_rgb(160, 160, 166));
				draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_h, true);
			}

			/* icon_x/y locate the decorative server avatar thumbnail inside this row in GUI pixels */
			var icon_x = row_x + 10;
			var icon_y = row_y + 10;
			draw_set_colour(make_color_rgb(34, 54, 38));
			draw_rectangle(icon_x, icon_y, icon_x + 48, icon_y + 48, false);
			draw_set_colour(make_color_rgb(72, 106, 66));
			draw_rectangle(icon_x, icon_y, icon_x + 48, icon_y + 17, false);
			draw_set_colour(make_color_rgb(82, 70, 54));
			draw_rectangle(icon_x, icon_y + 31, icon_x + 48, icon_y + 48, false);
			player_character_draw(PLAYER_DIRECTION_DOWN, false, icon_x + 24, icon_y + 28, 1.15, c_white, 1);

			/* text_x/w reserve the space beside the avatar and before right-side status.
			ping_ms uses the reported millisecond RTT or -1 when absent. online uses current
			list availability, while full/checking/status_failed default false unless their
			optional flags exist. These are list snapshot fields, not new live socket tests */
			var text_x = icon_x + 60;
			var text_w = row_w - 220;
			var ping_ms = variable_struct_exists(entry, "ping_ms") ? entry.ping_ms : -1;
			var online = entry.online;
			var full = variable_struct_exists(entry, "full") && entry.full;
			var checking = variable_struct_exists(entry, "checking") && entry.checking;
			var status_failed = variable_struct_exists(entry, "status_failed") && entry.status_failed;

			/* Online row names use white and other availability states use dimmed text */
			draw_set_colour(online ? c_white : make_color_rgb(150, 150, 150));
			scr_render_text(text_x, row_y + 9, entry.name, 23, text_w);
			draw_set_colour(make_color_rgb(166, 166, 166));
			scr_render_text(text_x, row_y + 34, entry.address, 18, text_w);

			/* status_numbers_known requires a nonnegative player count and positive capacity.
			Unknown sentinels leave the capacity text out instead of displaying misleading counts */
			var status_numbers_known = entry.players >= 0 && entry.max_players > 0;

			/* Only known player/capacity numbers produce their count label.
			Other rows retain their status text without invented occupancy */
			if (status_numbers_known)
			{
				/* players_text formats the reported players and capacity as current/maximum.
				Full capacity uses red, other online counts white and offline counts muted gray */
				var players_text = string(entry.players) + "/" + string(entry.max_players);
				draw_set_halign(fa_right);
				draw_set_colour(full ? make_color_rgb(224, 92, 92) : (online ? c_white : make_color_rgb(130, 130, 130)));
				scr_render_text(row_x + row_w - 54, row_y + 11, players_text, 20, 80);
				draw_set_halign(fa_left);
			}

			/* green_bar_count starts zero for missing latency. Known RTT bands fill progressively
			fewer of the five bars as round-trip milliseconds increase */
			var green_bar_count = 0;

			/* A known RTT up to 150 ms uses all five latency bars */
			if (ping_ms >= 0 && ping_ms <= 150)
			{
				green_bar_count = 5;
			}

			/* The next known band through 300 ms uses four bars after the faster band failed */
			else if (ping_ms >= 0 && ping_ms <= 300)
			{
				green_bar_count = 4;
			}

			/* RTT through 600 ms uses three bars, indicating the middle latency band */
			else if (ping_ms >= 0 && ping_ms <= 600)
			{
				green_bar_count = 3;
			}

			/* RTT through 1,000 ms uses two bars after the preceding lower bands failed */
			else if (ping_ms >= 0 && ping_ms <= 1000)
			{
				green_bar_count = 2;
			}

			/* Any remaining known RTT uses one bar. Negative unknown RTT retains zero bars */
			else if (ping_ms >= 0)
			{
				green_bar_count = 1;
			}

			/* bars_x/y position the small latency glyph at the row's right edge in GUI pixels */
			var bars_x = row_x + row_w - 44;
			var bars_y = row_y + 18;
			/// @description Draw five latency bars and an unavailable cross using the caller's current row snapshot
			/// @param {Real} icon_x Left edge of the glyph in GUI pixels
			/// @param {Real} icon_y Top edge of the glyph in GUI pixels
			/// @param {Bool} is_reachable Whether the list currently reports this server online
			/// @param {Real} filled_bars Number of low-index bars to color green when reachable
			var draw_ping_icon = function(icon_x, icon_y, is_reachable, filled_bars)
			{
				/* Draw all five bars in ascending-height order using zero-based bar index.
				Every bar is drawn, with fill controlled by reachability and requested count */
				for (var bar = 0; bar < 5; bar++)
				{
					/* bar_h increases four GUI pixels per bar from six pixels. bar_x advances six
					pixels horizontally. filled requires a reachable server and an index below the
					requested bar count, choosing green for active bars and gray for the rest */
					var bar_h = 6 + bar * 4;
					var bar_x = icon_x + bar * 6;
					var filled = is_reachable && bar < filled_bars;
					draw_set_colour(filled ? make_color_rgb(0, 235, 55) : make_color_rgb(78, 82, 86));
					draw_rectangle(bar_x, icon_y + 22 - bar_h, bar_x + 5, icon_y + 22, false);
				}

				/* An unreachable server adds a red cross over its gray bars.
				Reachable icons keep the plain latency-bar appearance */
				if (!is_reachable)
				{
					draw_set_colour(c_red);
					draw_line_width(icon_x - 2, icon_y + 3, icon_x + 30, icon_y + 25, 4);
					draw_line_width(icon_x + 30, icon_y + 3, icon_x - 2, icon_y + 25, 4);
				}
			}

			/* ping_known requires both usable capacity metadata and a nonnegative RTT.
			This existing UI therefore omits latency icons when occupancy metadata is unknown */
			var ping_known = status_numbers_known && ping_ms >= 0;

			/* Online entries may show a measured latency icon and exceptional status text.
			Offline entries take the separate unavailable-status styling */
			if (online)
			{
				/* Draw reachable latency bars only for known measurements outside active checking.
				During a probe, retain checking status instead of presenting that icon */
				if (ping_known && !checking)
				{
					draw_ping_icon(bars_x, bars_y, true, green_bar_count);
				}

				/* Checking, full or failed-status rows display their explicit status message.
				Ordinary online rows omit it. Full messages are red and other exceptional messages gray */
				if (checking || full || status_failed)
				{
					draw_set_halign(fa_right);
					draw_set_colour(full ? make_color_rgb(224, 92, 92) : make_color_rgb(178, 178, 178));
					scr_render_text(row_x + row_w - 12, row_y + 38, entry.status, 16, 180);
					draw_set_halign(fa_left);
				}
			}

			/* Offline rows keep their explicit unavailable/checking feedback instead of the
			ordinary online appearance */
			else
			{
				/* A previously known latency allows an offline crossed-out icon.
				Without known counts/RTT, omit that glyph instead of suggesting a measurement */
				if (ping_known)
				{
					draw_ping_icon(bars_x, bars_y, false, 0);
				}

				draw_set_halign(fa_right);

				/* Pending-check status is muted while other offline feedback is red.
				The row's text still reports the actual snapshot status */
				draw_set_colour(entry.checking ? make_color_rgb(180, 180, 184) : make_color_rgb(224, 92, 92));
				scr_render_text(row_x + row_w - 12, row_y + 38, entry.status, 16, 180);
				draw_set_halign(fa_left);
			}
		}
	}

	/// @description Draw a join-dialog text field with current_time caret animation without changing its stored value
	/// @param {Real} x Left edge in GUI pixels
	/// @param {Real} y Top edge in GUI pixels
	/// @param {Real} w Field width in GUI pixels
	/// @param {Real} h Field height in GUI pixels
	/// @param {String} label Visible field name above the rectangle
	/// @param {String} value Candidate text for display
	/// @param {Bool} focused Whether this field owns dialog input
	var draw_join_input = function(x, y, w, h, label, value, focused)
	{
		draw_set_colour(c_ltgray);
		scr_render_text(x, y - 24, label, 18, w);

		draw_set_colour(make_color_rgb(8, 8, 8));
		draw_rectangle(x, y, x + w, y + h, false);

		/* A focused dialog text field receives a brighter outline.
		Unfocused fields use the ordinary border */
		draw_set_colour(focused ? make_color_rgb(190, 190, 194) : make_color_rgb(112, 112, 116));
		draw_rectangle(x, y, x + w, y + h, true);

		/* cursor starts empty so unfocused dialog fields do not display a caret */
		var cursor = "";

		/* A focused dialog field shows its blinking caret without altering stored input text */
		if (focused)
		{
			cursor = "|";

			/* Hide that caret during the odd 500 ms phase on current_time.
			The other half of the one-second cycle leaves it visible */
			if ((current_time div 500) mod 2 == 1)
			{
				cursor = "";
			}
		}

		draw_set_colour(c_white);
		scr_render_text(x + 12, y + 9, string(value) + cursor, 23, w - 24);
	}

	/* status_y begins just below the visible list. status_text gives explicit join
	errors priority over ordinary status, with red error color and neutral status color */
	var status_y = client_join_list_y + client_join_list_height + 10;
	var status_text = client_join_error != "" ? client_join_error : client_join_status;
	draw_set_colour(client_join_error != "" ? c_red : c_ltgray);
	scr_render_text(client_join_list_x, status_y, status_text, 18, client_join_list_width);

	/// @description Draw a server-list action while suppressing background hover/focus under an open join dialog
	/// @param {Real} x Left edge in GUI pixels
	/// @param {Real} y Top edge in GUI pixels
	/// @param {Real} w Button width in GUI pixels
	/// @param {Real} h Button height in GUI pixels
	/// @param {String} label Visible action text
	/// @param {String} key Server-list action identity
	/// @param {Bool} enabled Whether current join/list state permits activation
	var draw_join_button = function(x, y, w, h, label, key, enabled)
	{
		/* hovered matches this action's key to pointer state. Suppress pointer and keyboard
		focus accents while any join dialog owns input, leaving background buttons visually inactive */
		var hovered = client_join_hover_button == key;
		scr_draw_menu_button(x, y, w, h, label, hovered && client_join_dialog == "", client_join_action_focus == key && client_join_dialog == "", enabled, false, false, 20);
	}

	/* join_busy combines DNS and connection startup. Direct/Add/Refresh are disabled
	while busy, Join uses its readiness flag, Edit/Delete use saved-row eligibility,
	and Back remains available for cancellation */
	var join_busy = client_dns_pending || client.connect_pending;
	draw_join_button(client_join_button_x, client_join_button_y, client_join_button_width, client_join_button_height, "Join Server", "join", client_join_join_enabled);
	draw_join_button(client_join_direct_button_x, client_join_direct_button_y, client_join_direct_button_width, client_join_direct_button_height, "Direct Connection", "direct", !join_busy);
	draw_join_button(client_join_add_button_x, client_join_add_button_y, client_join_add_button_width, client_join_button_height, "Add Server", "add", !join_busy);
	draw_join_button(client_join_edit_button_x, client_join_edit_button_y, client_join_edit_button_width, client_join_button_height, "Edit", "edit", client_join_edit_enabled);
	draw_join_button(client_join_delete_button_x, client_join_delete_button_y, client_join_delete_button_width, client_join_button_height, "Delete", "delete", client_join_edit_enabled);
	draw_join_button(client_join_refresh_button_x, client_join_refresh_button_y, client_join_refresh_button_width, client_join_refresh_button_height, "Refresh", "refresh", !join_busy);
	draw_join_button(client_join_back_button_x, client_join_back_button_y, client_join_back_button_width, client_join_back_button_height, "Back", "back", true);
	escape_exit_hold_draw_progress(client_join_back_button_x, client_join_back_button_y, client_join_back_button_width, client_join_back_button_height, "join_back");

	/* An open join dialog draws a modal layer over list controls.
	Its kind selects name/address editing, direct connection or delete confirmation */
	if (client_join_dialog != "")
	{
		/* dialog_editing marks Add/Edit and dialog_deleting marks Delete. dialog_title
		follows Add, Edit, Delete or Direct kind. field_x/width reserve 28-pixel side
		margins, and dialog_button_width splits remaining space across two actions */
		var dialog_editing = client_join_dialog == "add" || client_join_dialog == "edit";
		var dialog_deleting = client_join_dialog == "delete";
		var dialog_title = client_join_dialog == "add" ? "Add Server" : (client_join_dialog == "edit" ? "Edit Server" : (dialog_deleting ? "Delete Server?" : "Direct Connection"));
		var field_x = client_join_dialog_x + 28;
		var field_width = client_join_dialog_width - 56;
		var dialog_button_width = (field_width - 12) * 0.5;
		draw_set_alpha(0.8);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, gui_width, gui_height, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(22, 24, 29));
		draw_rectangle(client_join_dialog_x, client_join_dialog_y, client_join_dialog_x + client_join_dialog_width, client_join_dialog_y + client_join_dialog_height, false);
		draw_set_colour(make_color_rgb(100, 106, 118));
		draw_rectangle(client_join_dialog_x, client_join_dialog_y, client_join_dialog_x + client_join_dialog_width, client_join_dialog_y + client_join_dialog_height, true);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(gui_width * 0.5, client_join_dialog_y + 18, dialog_title, 26, field_width);
		draw_set_halign(fa_left);

		/* Add/Edit dialogs include a name field because their entry is saved.
		Direct/Delete use an explanation rather than editable name input */
		if (dialog_editing)
		{
			draw_join_input(field_x, client_join_dialog_name_y, field_width, 42, "Server Name", client_join_dialog_name, client_join_dialog_focus == "name");
		}

		/* Other dialog kinds explain their operation. Delete asks about removing the
		saved list entry and Direct describes its one-time connection */
		else
		{
			draw_set_colour(c_ltgray);

			/* dialog_explanation chooses saved-entry removal guidance for Delete and one-time
			connection guidance for Direct */
			var dialog_explanation = dialog_deleting ? "Remove this saved server from your list?" : "Connect once without adding a saved server.";
			scr_render_text(field_x, client_join_dialog_y + 64, dialog_explanation, 18, field_width);
		}

		/* Delete displays the existing name/address as confirmation context without
		making either value editable */
		if (dialog_deleting)
		{
			draw_set_colour(c_white);
			scr_render_text(field_x, client_join_dialog_y + 100, client_join_dialog_name, 22, field_width);
			draw_set_colour(c_ltgray);
			scr_render_text(field_x, client_join_dialog_y + 130, client_join_dialog_address, 17, field_width);
		}

		/* Other dialog kinds draw address input, focused only for the address field key */
		else
		{
			draw_join_input(field_x, client_join_dialog_address_y, field_width, 42, "Server Address", client_join_dialog_address, client_join_dialog_focus == "address");
		}

		/* dialog_message starts with the current join error so it stays visible above
		ordinary progress or input guidance */
		var dialog_message = client_join_error;

		/* Without an error, busy startup displays its progress. Idle Delete explains that
		only the saved entry is removed and other idle dialogs show input/cancel guidance */
		if (dialog_message == "") dialog_message = join_busy ? client_join_status : (dialog_deleting ? "This does not shut down or delete the server." : "Ctrl+V pastes. Tab changes fields. Esc cancels.");

		/* Display dialog errors in red and normal guidance/progress in neutral text */
		draw_set_colour(client_join_error == "" ? c_ltgray : make_color_rgb(240, 105, 105));
		scr_render_text_wrapped(field_x, client_join_dialog_button_y - 48, dialog_message, 16, field_width, 3);

		/* dialog_valid begins true for Delete because it edits no connection fields.
		Other kinds must establish valid address/name state below */
		var dialog_valid = dialog_deleting;

		/* Nondelete dialogs validate their current target rather than enabling completion
		from dialog visibility alone */
		if (!dialog_deleting)
		{
			/* dialog_parsed is the normalized candidate target. Completion needs a usable
			nonplaceholder address and, for Add/Edit, a nonempty trimmed saved-server name */
			var dialog_parsed = client_parse_join_address(client_join_dialog_address);
			dialog_valid = dialog_parsed.ok && !dialog_parsed.placeholder && (!dialog_editing || string_trim(client_join_dialog_name) != "");
		}

		/* done_label chooses Delete, Done for saved-entry editing, or Join Server for a
		direct target. The primary action requires valid fields and idle startup, while
		Cancel remains available and Delete receives danger styling */
		var done_label = dialog_deleting ? "Delete" : (dialog_editing ? "Done" : "Join Server");
		scr_draw_menu_button(field_x, client_join_dialog_button_y, dialog_button_width, 40, done_label, client_join_dialog_hover == "done", client_join_dialog_focus == "done", dialog_valid && !join_busy, false, dialog_deleting, 20);
		scr_draw_menu_button(field_x + dialog_button_width + 12, client_join_dialog_button_y, dialog_button_width, 40, "Cancel", client_join_dialog_hover == "cancel", client_join_dialog_focus == "cancel", true, true, false, 20);
	}

	draw_set_halign(fa_left);
	draw_set_alpha(1);
}
#endregion /* Server Selection Screen END */

#region /* Gameplay GUI Layers */
/* Outside server selection, show the build footer, including the console view.
The join screen already draws its own version header */
if (!client_join_screen)
{
	/* Capture current GUI width/height in pixels to place the build label above the
	bottom edge and bound its available text width */
	var build_gui_width = display_get_gui_width();
	var build_gui_height = display_get_gui_height();
	draw_set_halign(fa_left);
	draw_set_colour(make_color_rgb(150, 150, 154));
	scr_render_text(16, build_gui_height - 24, game_version_label, 16, min(180, build_gui_width - 32));
}

/* Client session controls draw only outside server selection.
Server view has its separate owner-console controls */
if (is_client && !client_join_screen)
{
	/* Borrow the client session. has_active_socket tests its available numeric handle
	and has_assigned_id tests its available logical player identity. These represent
	different stages of connection establishment */
	var active_client = scr_get_client();
	var has_active_socket = is_struct(active_client)
		&& variable_struct_exists(active_client, "socket")
		&& is_real(active_client.socket)
		&& active_client.socket >= 0;
	var has_assigned_id = is_struct(active_client)
		&& variable_struct_exists(active_client, "ID")
		&& active_client.ID != noone;

	/* Either a live socket or an assigned ID permits session controls.
	With neither, omit a leave/admin button for a session that has not started */
	if (has_active_socket || has_assigned_id)
	{
		client_leave_update_layout();

		/* remote_admin_available requires authenticated remote ownership and excludes
		Host & Play and Singleplayer, which have different local session controls */
		var remote_admin_available = !host_play_active
			&& !is_singleplayer
			&& variable_struct_exists(active_client, "admin_authenticated")
			&& active_client.admin_authenticated;

		/* leave_label names the action for this session: Host Menu for owned play, Mode
		Select for Singleplayer, Official Server Controls for remote admins, otherwise
		Server List. Rendering reports the destination chosen by input routing */
		var leave_label = host_play_active ? "Host Menu" : (is_singleplayer ? "Mode Select" : (remote_admin_available ? "Official Server Controls" : "Server List"));
		scr_draw_menu_button(client_leave_button_x, client_leave_button_y, client_leave_button_width, client_leave_button_height, leave_label, client_leave_button_hover, false, true, false, false, 18);

		/* Only nonhost sessions show held-Escape leave progress.
		Host & Play uses a menu-opening Escape action instead of timed departure */
		if (!host_play_active)
		{
			escape_exit_hold_draw_progress(client_leave_button_x, client_leave_button_y, client_leave_button_width, client_leave_button_height, "client_leave");
		}
		draw_set_halign(fa_left);
	}
}

/* Draw normal client world overlays only outside join/mode selection.
Those full-screen menus already own their layouts and input priority */
if (is_client && !client_join_screen && !network_mode_screen)
{
	/* Borrow the character-maker GUI and record whether it blocks game input.
	character_blocks_gui controls whether normal drawing/chat/world overlays should
	be visible beneath that editor */
	var character_maker_gui = scr_get_character_maker();
	var character_blocks_gui = character_maker_gui.blocks_game_input();

	/* When the character editor does not block gameplay, draw normal client overlays
	in their explicit layer order. Blocking editor state hides these panels so its
	controls are not covered by world UI */
	if (!character_blocks_gui)
	{
		player_controller_draw_edge_indicators(network_camera);

		/* Borrow drawing GUI for its panels, diagnostics and final toast/tooltip passes.
		This service owns their contents while this event establishes layer order */
		var drawing_gui = scr_get_drawing();
		drawing_gui.draw_gui();

		/* The fixed zoom panel owns this top-right space, so keep it visibly
		above draggable drawing panels just as it is in input priority */
		network_camera_draw_zoom_gui();
		scr_get_chat().draw_overlay();
		scr_get_chat().draw_player_list_overlay();
		drawing_gui.draw_debug_overlay(false);

		/* Drawing toasts and tooltips are a final pass so they cannot be covered by panels */
		drawing_gui.draw_top_overlays();
		scr_get_social().draw_card();

		/* If this server supports walls but the client snapshot is not ready, display the
		wall-loading notice. Other states omit the notice rather than suggesting movement
		is blocked by an unsupported or already-ready wall transfer */
		if (scr_get_client().wall_drawing_supported && !scr_get_walls().client_ready)
		{
			draw_set_halign(fa_center);
			draw_set_colour(c_black);
			draw_rectangle(display_get_gui_width() * 0.5 - 180, display_get_gui_height() - 68,
				display_get_gui_width() * 0.5 + 180, display_get_gui_height() - 24, false);
			draw_set_colour(c_white);
			scr_render_text(display_get_gui_width() * 0.5, display_get_gui_height() - 58,
				"Loading walls... movement resumes when ready.", 14, 344);
			draw_set_halign(fa_left);
		}
	}

	/* Draw character-maker GUI after normal world overlays so the editor remains on top
	when its own state chooses to display controls */
	character_maker_gui.draw_gui();
}
#endregion /* Gameplay GUI Layers END */

#region /* Host Session Menu */
/* Draw the host-session menu only during Host & Play with the menu open and mode
selection absent. It overlays gameplay while server maintenance continues in Step */
if (host_play_active && host_session_menu_open && !network_mode_screen)
{
	host_session_menu_update_layout();

	/* Capture current GUI dimensions in pixels for the full-screen host-menu veil */
	var host_gui_width = display_get_gui_width();
	var host_gui_height = display_get_gui_height();
	draw_set_alpha(0.72);
	draw_set_colour(c_black);
	draw_rectangle(0, 0, host_gui_width, host_gui_height, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(24, 26, 30));
	draw_rectangle(host_menu_panel_x, host_menu_panel_y, host_menu_panel_x + host_menu_panel_width, host_menu_panel_y + host_menu_panel_height, false);
	draw_set_colour(make_color_rgb(90, 92, 100));
	draw_rectangle(host_menu_panel_x, host_menu_panel_y, host_menu_panel_x + host_menu_panel_width, host_menu_panel_y + host_menu_panel_height, true);
	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(255, 220, 95));
	scr_render_text(host_menu_panel_x + host_menu_panel_width * 0.5, host_menu_panel_y + 24, "Host Session", 28, host_menu_panel_width - 32);
	draw_set_colour(make_color_rgb(178, 178, 184));
	scr_render_text(host_menu_panel_x + host_menu_panel_width * 0.5, host_menu_panel_y + 55, "The server keeps running while this menu is open.", 15, host_menu_panel_width - 40);

	/* Borrow the hosting service. host_reset_text uses available countdown support
	or the explicit unavailable fallback, keeping local lifecycle feedback visible */
	var host_server = scr_get_server();
	var host_reset_text = is_struct(host_server) && variable_struct_exists(host_server, "reset_countdown_text")
		? host_server.reset_countdown_text()
		: "Drawing reset timer unavailable";
	draw_set_colour(make_color_rgb(255, 220, 95));
	scr_render_text(host_menu_panel_x + host_menu_panel_width * 0.5, host_menu_panel_y + 79, host_reset_text, 16, host_menu_panel_width - 40);

	/// @description Draw an available host-session menu action using controller pointer-hover state
	/// @param {Real} button_x Left edge in GUI pixels
	/// @param {Real} button_y Top edge in GUI pixels
	/// @param {Real} button_w Button width in GUI pixels
	/// @param {Real} button_h Button height in GUI pixels
	/// @param {String} label Visible action text
	/// @param {String} key Host-menu action identity
	/// @param {Bool} danger Whether this destructive action needs danger styling
	var draw_host_menu_button = function(button_x, button_y, button_w, button_h, label, key, danger)
	{
		/* hovered matches this host-menu action key to the pointer-selected control.
		The shared menu renderer handles its ordinary or danger styling */
		var hovered = host_menu_hover_button == key;
		scr_draw_menu_button(button_x, button_y, button_w, button_h, label, hovered, false, true, false, danger, 18);
	}

	draw_host_menu_button(host_menu_resume_button_x, host_menu_resume_button_y, host_menu_resume_button_width, host_menu_resume_button_height, "Resume", "resume", false);

	/* The host wall button displays authoritative ON/OFF policy, matching the setting
	its separate input path toggles */
	draw_host_menu_button(host_menu_wall_button_x, host_menu_wall_button_y, host_menu_wall_button_width, host_menu_wall_button_height,
		host_server.wall_drawing_enabled ? "Wall Drawing: ON" : "Wall Drawing: OFF", "walls", false);
	draw_host_menu_button(host_menu_return_button_x, host_menu_return_button_y, host_menu_return_button_width, host_menu_return_button_height, "Return to Server Console", "return", false);
	draw_host_menu_button(host_menu_shutdown_button_x, host_menu_shutdown_button_y, host_menu_shutdown_button_width, host_menu_shutdown_button_height, "Shut Down Server", "shutdown", true);
	draw_set_halign(fa_center);
	draw_set_colour(c_ltgray);

	/* Show recent wall-setting feedback when nonempty. Otherwise explain that disabling
	wall drawing makes existing walls passable */
	scr_render_text(host_menu_panel_x + host_menu_panel_width * 0.5, host_menu_shutdown_button_y + host_menu_shutdown_button_height + 12,
		host_menu_wall_feedback == "" ? "Off makes existing walls passable." : host_menu_wall_feedback, 14, host_menu_panel_width - 40);
	draw_set_halign(fa_left);
}
#endregion /* Host Session Menu END */

#region /* Remote Server Controls */
/* The remote lifecycle panel renders only while its controls page is open in an
active client view outside join/mode menus. The logs subpage has its own later layer */
if (official_admin_controls_open && !official_admin_logs_open && is_client && !client_join_screen && !network_mode_screen)
{
	official_admin_controls_update_layout();

	/* Borrow admin client state and current GUI width/height in pixels for the panel's
	server status, actions and full-screen veil */
	var admin_draw_client = scr_get_client();
	var admin_gui_width = display_get_gui_width();
	var admin_gui_height = display_get_gui_height();
	draw_set_alpha(0.76);
	draw_set_colour(c_black);
	draw_rectangle(0, 0, admin_gui_width, admin_gui_height, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(24, 26, 30));
	draw_rectangle(official_admin_panel_x, official_admin_panel_y, official_admin_panel_x + official_admin_panel_width, official_admin_panel_y + official_admin_panel_height, false);
	draw_set_colour(make_color_rgb(90, 92, 100));
	draw_rectangle(official_admin_panel_x, official_admin_panel_y, official_admin_panel_x + official_admin_panel_width, official_admin_panel_y + official_admin_panel_height, true);
	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(255, 220, 95));
	scr_render_text(official_admin_panel_x + official_admin_panel_width * 0.5, official_admin_panel_y + 20, "Official Server Controls", 28, official_admin_panel_width - 40);

	/* admin_players_text formats reported occupancy and capacity without performing
	another server query during drawing */
	var admin_players_text = "Players: " + string(admin_draw_client.admin_connected_players) + " / " + string(admin_draw_client.admin_max_players);
	draw_set_colour(make_color_rgb(190, 192, 198));
	scr_render_text(official_admin_panel_x + official_admin_panel_width * 0.5, official_admin_panel_y + 53, admin_players_text, 16, official_admin_panel_width - 48);

	/* Accent the remote countdown while automatic reset is enabled.
	Unlimited scheduling uses neutral text */
	draw_set_colour(admin_draw_client.admin_reset_enabled ? make_color_rgb(255, 220, 95) : make_color_rgb(166, 166, 172));
	scr_render_text(official_admin_panel_x + official_admin_panel_width * 0.5, official_admin_panel_y + 76, admin_draw_client.server_reset_countdown_text(), 16, official_admin_panel_width - 48);

	/* admin_feedback gives an active restart's progress priority over the last command
	result. Otherwise begin with the client-recorded result message */
	var admin_feedback = admin_draw_client.admin_restart_in_progress
		? "The server restart is in progress..."
		: admin_draw_client.admin_last_result_message;

	/* An empty command result falls back to the server's admin-status message.
	Keep any existing result/progress feedback instead of overwriting it */
	if (admin_feedback == "")
	{
		admin_feedback = admin_draw_client.admin_server_message;
	}

	/* Successful admin results use green feedback. Other result states remain neutral
	here rather than claiming success from message text alone */
	draw_set_colour(admin_draw_client.admin_last_result_code == ADMIN_RESULT_OK ? make_color_rgb(170, 220, 178) : make_color_rgb(205, 205, 210));
	scr_render_text_wrapped(
		official_admin_panel_x + official_admin_panel_width * 0.5,
		official_admin_panel_y + 101,
		admin_feedback,
		14,
		official_admin_panel_width - 48,
		3
	);

	/* admin_controls_busy combines pending command/status replies, restart state and
	active log download. Draw command controls disabled while these operations own
	the admin request/transfer flow */
	var admin_controls_busy = admin_draw_client.admin_command_pending
		|| admin_draw_client.admin_status_refresh_pending
		|| admin_draw_client.admin_restart_in_progress
		|| admin_draw_client.admin_logs.active;
	/// @description Draw a remote lifecycle action using controller hover state and caller-computed eligibility
	/// @param {Real} button_x Left edge in GUI pixels
	/// @param {Real} button_y Top edge in GUI pixels
	/// @param {Real} button_w Button width in GUI pixels
	/// @param {Real} button_h Button height in GUI pixels
	/// @param {String} label Visible action text
	/// @param {String} key Remote-admin action identity
	/// @param {Bool} enabled Whether this action currently permits activation
	/// @param {Bool} danger Whether this destructive action needs danger styling
	var draw_admin_button = function(button_x, button_y, button_w, button_h, label, key, enabled, danger)
	{
		scr_draw_menu_button(button_x, button_y, button_w, button_h, label, official_admin_hover_button == key, false, enabled, false, danger, 17);
	}

	/* The scheduling-toggle label reports enabled resets or unlimited time.
	Its action is drawn available only while admin controls are idle */
	draw_admin_button(
		official_admin_toggle_button_x,
		official_admin_toggle_button_y,
		official_admin_toggle_button_width,
		official_admin_toggle_button_height,
		admin_draw_client.admin_reset_enabled ? "Automatic Reset: Enabled" : "Automatic Reset: Unlimited",
		"toggle",
		!admin_controls_busy,
		false
	);

	/* Minus is available only while idle and above the 15-minute scheduling minimum */
	draw_admin_button(official_admin_minus_button_x, official_admin_minus_button_y, official_admin_minus_button_width, official_admin_minus_button_height, "- 30 minutes", "minus", !admin_controls_busy && admin_draw_client.admin_reset_interval_minutes > 15, false);

	/* Plus is available only while idle and below the 1,440-minute scheduling maximum */
	draw_admin_button(official_admin_plus_button_x, official_admin_plus_button_y, official_admin_plus_button_width, official_admin_plus_button_height, "+ 30 minutes", "plus", !admin_controls_busy && admin_draw_client.admin_reset_interval_minutes < 1440, false);

	/* Borrow network policy for displayed capacity bounds. admin_max_players_valid
	checks the whole-number candidate and admin_max_players_changed additionally
	compares it with reported committed capacity, preventing meaningless Apply requests */
	var admin_draw_net = scr_get_network();
	var admin_max_players_valid = max_players_input_is_valid(official_admin_max_players_text);
	var admin_max_players_changed = admin_max_players_valid
		&& max_players_input_value(official_admin_max_players_text) != floor(real(admin_draw_client.admin_max_players));
	draw_set_halign(fa_left);
	draw_set_colour(make_color_rgb(190, 192, 198));
	scr_render_text(
		official_admin_max_players_input_x,
		official_admin_max_players_input_y - 21,
		"Maximum players (" + string(admin_draw_net.min_player_limit) + "-" + string(admin_draw_net.max_player_limit) + ")",
		16,
		official_admin_toggle_button_width
	);

	/* admin_max_players_input_active records whether the capacity field owns text focus.
	It controls its outline, caret and editing feedback below */
	var admin_max_players_input_active = official_admin_focus == "max_players";
	draw_set_colour(make_color_rgb(8, 8, 8));
	draw_rectangle(
		official_admin_max_players_input_x,
		official_admin_max_players_input_y,
		official_admin_max_players_input_x + official_admin_max_players_input_width,
		official_admin_max_players_input_y + official_admin_max_players_input_height,
		false
	);

	/* An active capacity field uses the focus accent. Otherwise pointer hover chooses
	a lighter border and the remaining field uses its normal border */
	draw_set_colour(admin_max_players_input_active
		? make_color_rgb(255, 220, 95)
		: (official_admin_hover_button == "max_players_input" ? make_color_rgb(200, 202, 208) : make_color_rgb(112, 116, 124)));
	draw_rectangle(
		official_admin_max_players_input_x,
		official_admin_max_players_input_y,
		official_admin_max_players_input_x + official_admin_max_players_input_width,
		official_admin_max_players_input_y + official_admin_max_players_input_height,
		true
	);

	/* admin_max_players_label is a display copy of the current capacity candidate.
	Adding a caret must not alter text used by validation or command serialization */
	var admin_max_players_label = official_admin_max_players_text;

	/* Append the caret only for active editing during the even 500 ms current_time
	half-cycle. Other states render the plain candidate */
	if (admin_max_players_input_active && (current_time div 500) mod 2 == 0)
	{
		admin_max_players_label += "|";
	}
	draw_set_halign(fa_center);

	/* Capacity text stays white while valid or being edited. A finished invalid candidate
	turns red, avoiding premature warnings for intermediate typing */
	draw_set_colour(admin_max_players_valid || admin_max_players_input_active ? c_white : make_color_rgb(235, 150, 150));
	scr_render_text(
		official_admin_max_players_input_x + official_admin_max_players_input_width * 0.5,
		official_admin_max_players_input_y + 8,
		admin_max_players_label,
		18,
		official_admin_max_players_input_width - 16
	);

	/* Remote Apply requires idle admin controls plus valid changed capacity.
	Invalid, unchanged or busy state produces a disabled action */
	draw_admin_button(
		official_admin_max_players_apply_button_x,
		official_admin_max_players_apply_button_y,
		official_admin_max_players_apply_button_width,
		official_admin_max_players_apply_button_height,
		"Apply",
		"max_players_apply",
		!admin_controls_busy && admin_max_players_valid && admin_max_players_changed,
		false
	);

	/* The wall button reports remote ON/OFF policy and is available only when idle
	and the server advertises wall support */
	draw_admin_button(official_admin_wall_button_x, official_admin_wall_button_y, official_admin_wall_button_width, official_admin_wall_button_height,
		admin_draw_client.wall_drawing_enabled ? "Wall Drawing: ON" : "Wall Drawing: OFF (passable)", "walls", !admin_controls_busy && admin_draw_client.wall_drawing_supported, false);

	/* admin_reset_label requests confirmation only while its current_time deadline
	remains in the future. Expired or inactive confirmation shows the normal reset action */
	var admin_reset_label = official_admin_reset_confirm_until > current_time
		? "Confirm: Archive & Clear Canvas"
		: "Archive & Clear Canvas Now";

	/* Immediate reset uses danger styling and remains disabled during other admin work.
	Refresh shares the idle requirement, while Logs stays available as a navigation action */
	draw_admin_button(official_admin_reset_button_x, official_admin_reset_button_y, official_admin_reset_button_width, official_admin_reset_button_height, admin_reset_label, "reset", !admin_controls_busy, true);
	draw_admin_button(official_admin_refresh_button_x, official_admin_refresh_button_y, official_admin_refresh_button_width, official_admin_refresh_button_height, "Refresh Server Status", "refresh", !admin_controls_busy, false);
	draw_admin_button(official_admin_logs_button_x, official_admin_logs_button_y, official_admin_logs_button_width, official_admin_refresh_button_height, "Server Logs", "logs", true, false);

	/* admin_restart_label shows the confirming action only inside its live millisecond
	window. Outside that window it names the ordinary archive/wipe/restart request */
	var admin_restart_label = official_admin_restart_confirm_until > current_time
		? "Confirm: Save Everything, Wipe & Restart"
		: "Save Everything, Wipe & Restart Server";
	draw_admin_button(official_admin_restart_button_x, official_admin_restart_button_y, official_admin_restart_button_width, official_admin_restart_button_height, admin_restart_label, "restart", !admin_controls_busy, true);
	draw_admin_button(official_admin_back_button_x, official_admin_back_button_y, official_admin_back_button_width, official_admin_back_button_height, "Back to Game", "back", true, false);
	draw_admin_button(official_admin_leave_button_x, official_admin_leave_button_y, official_admin_leave_button_width, official_admin_leave_button_height, "Server List", "leave", true, false);

	/* Hovering Refresh shows its explanatory tooltip. Other controls do not produce
	this status-refresh explanation */
	if (official_admin_hover_button == "refresh")
	{
		/* admin_tooltip_width is bounded by 380 pixels and GUI width with margins, while
		height is 64 pixels. Pointer x/y are GUI coordinates. Tooltip x stays within side
		margins and y initially places the panel below the pointer */
		var admin_tooltip_width = min(380, max(1, admin_gui_width - 8));
		var admin_tooltip_height = 64;
		var admin_tooltip_mouse_x = device_mouse_x_to_gui(0);
		var admin_tooltip_mouse_y = device_mouse_y_to_gui(0);
		var admin_tooltip_x = clamp(admin_tooltip_mouse_x + 14, 4, max(4, admin_gui_width - admin_tooltip_width - 4));
		var admin_tooltip_y = admin_tooltip_mouse_y + 18;

		/* If the tooltip would cross the GUI bottom margin, move it above the pointer
		and keep at least the existing four-pixel top inset */
		if (admin_tooltip_y + admin_tooltip_height > admin_gui_height - 4)
		{
			admin_tooltip_y = max(4, admin_tooltip_mouse_y - admin_tooltip_height - 12);
		}

		draw_set_alpha(0.94);
		draw_set_colour(make_color_rgb(18, 19, 22));
		draw_rectangle(admin_tooltip_x, admin_tooltip_y, admin_tooltip_x + admin_tooltip_width, admin_tooltip_y + admin_tooltip_height, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(255, 220, 95));
		draw_rectangle(admin_tooltip_x, admin_tooltip_y, admin_tooltip_x + admin_tooltip_width, admin_tooltip_y + admin_tooltip_height, true);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);
		scr_render_text(admin_tooltip_x + 9, admin_tooltip_y + 7, "Refresh Server Status", 13, admin_tooltip_width - 18);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(admin_tooltip_x + 9, admin_tooltip_y + 28, "Fetches the latest player count, reset schedule, and restart state.", 11, admin_tooltip_width - 18);
		scr_render_text(admin_tooltip_x + 9, admin_tooltip_y + 44, "This panel also refreshes automatically.", 11, admin_tooltip_width - 18);
	}
	draw_set_halign(fa_left);
	draw_set_alpha(1);
}
#endregion /* Remote Server Controls END */

#region /* Remote Server Log Downloads */
/* The logs subpage renders only while remote admin controls and Logs are both open
in client view outside join/mode menus. It replaces the lifecycle-controls layer */
if (official_admin_controls_open && official_admin_logs_open && is_client && !client_join_screen && !network_mode_screen)
{
	official_admin_controls_update_layout();

	/* Borrow the client and its log transfer. logs_center_x centers text in the panel,
	and logs_button_x/width reuse its action column. logs_browser identifies browser
	restrictions, while logs_controls_busy combines pending replies and restart state */
	var logs_client = scr_get_client();
	var logs_download = logs_client.admin_logs;
	var logs_center_x = official_admin_panel_x + official_admin_panel_width * 0.5;
	var logs_button_x = official_admin_toggle_button_x;
	var logs_button_width = official_admin_toggle_button_width;
	var logs_browser = scr_get_network().is_browser_runtime();
	var logs_controls_busy = logs_client.admin_command_pending || logs_client.admin_status_refresh_pending || logs_client.admin_restart_in_progress;
	draw_set_alpha(0.76);
	draw_set_colour(c_black);
	draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(24, 26, 30));
	draw_rectangle(official_admin_panel_x, official_admin_panel_y, official_admin_panel_x + official_admin_panel_width, official_admin_panel_y + official_admin_panel_height, false);
	draw_set_colour(make_color_rgb(90, 92, 100));
	draw_rectangle(official_admin_panel_x, official_admin_panel_y, official_admin_panel_x + official_admin_panel_width, official_admin_panel_y + official_admin_panel_height, true);
	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(255, 220, 95));
	scr_render_text(logs_center_x, official_admin_panel_y + 24, "Official Server Logs", 28, official_admin_panel_width - 40);
	draw_set_colour(make_color_rgb(205, 205, 210));
	scr_render_text_wrapped(logs_center_x, official_admin_panel_y + 76, "Download saved chat and technical game logs from every available server session.", 16, logs_button_width, 4);
	draw_set_colour(make_color_rgb(166, 166, 172));
	scr_render_text_wrapped(logs_center_x, official_admin_panel_y + 136, "Includes only saved game messages. VM service and operating-system logs are retrieved separately over SSH.", 14, logs_button_width, 3);

	/* logs_status starts with the transfer's current message for progress/result feedback */
	var logs_status = logs_download.message;

	/* Browser mode replaces transfer feedback with desktop-download guidance because
	this log-download workflow is unavailable in the browser */
	if (logs_browser)
	{
		logs_status = "Use the desktop game to download server logs to this computer.";
	}

	/* An idle native transfer with no message gets the normal ready-to-request text.
	Nonempty transfer feedback remains visible */
	else if (logs_status == "")
	{
		logs_status = "Ready to request saved logs from the official server.";
	}

	/* A completed transfer uses green result text. Other transfer states use the
	attention accent while showing their current feedback */
	draw_set_colour(logs_download.complete ? make_color_rgb(170, 220, 178) : make_color_rgb(255, 220, 95));

	/* logs_status_lines splits wrapped status text into display rows using the panel's
	width and 14-pixel text height */
	var logs_status_lines = string_split(scr_text_wrap(logs_status, 14, logs_button_width), "\n");

	/* Draw at most four zero-based wrapped status lines so feedback stays inside its
	reserved panel area */
	for (var logs_line = 0; logs_line < min(4, array_length(logs_status_lines)); logs_line++)
	{
		/* logs_line_text is this wrapped row, allowing only its displayed copy to gain an
		ellipsis without modifying the transfer's status message */
		var logs_line_text = logs_status_lines[logs_line];

		/* The fourth visible row receives an ellipsis when additional wrapped lines remain.
		Shorter messages keep their last row unchanged */
		if (logs_line == 3 && array_length(logs_status_lines) > 4)
		{
			logs_line_text += "...";
		}
		scr_render_text(logs_center_x, official_admin_panel_y + 204 + logs_line * 17, logs_line_text, 14, logs_button_width);
	}

	/* An active transfer turns Download into Cancel and keeps cancellation available.
	Starting a new download requires native runtime and no pending admin/restart work */
	scr_draw_menu_button(logs_button_x, official_admin_logs_download_button_y, logs_button_width, 40, logs_download.active ? "Cancel Download" : "Download Saved Server Logs", official_admin_hover_button == "download_logs", false, logs_download.active || (!logs_browser && !logs_controls_busy), false, false, 17);

	/* Open Downloaded Logs is enabled only on a native runtime with a known output
	folder. Browser mode and missing folder paths disable that action */
	scr_draw_menu_button(logs_button_x, official_admin_logs_folder_button_y, logs_button_width, 40, "Open Downloaded Logs", official_admin_hover_button == "logs_folder", false, !logs_browser && logs_download.folder != "", false, false, 17);
	draw_set_halign(fa_center);
	draw_set_colour(make_color_rgb(166, 166, 172));
	scr_render_text_wrapped(logs_center_x, official_admin_panel_y + 386, "Saved in debug_logs/official_server. Downloads continue when you return to the game.", 14, logs_button_width, 3);
	scr_draw_menu_button(logs_button_x, official_admin_logs_back_button_y, logs_button_width, 40, "Back to Server Controls", official_admin_hover_button == "logs_back", false, true, false, false, 17);
	draw_set_halign(fa_left);
	draw_set_alpha(1);
}
#endregion /* Remote Server Log Downloads END */

#region /* Final Diagnostics and Modal Overlays */
/* Draw shared text diagnostics only while their visibility flag is enabled.
This final pass places them above ordinary session/menu layers */
if (global.text_debug_overlay)
{
	scr_render_text_debug_overlay();
}

/* Borrow the client session for the final network-diagnostics overlay */
var diagnostics_draw_client = scr_get_client();

/* An available client diagnostics method can render its own optional panel.
Missing service support skips that layer without changing other GUI output */
if (is_struct(diagnostics_draw_client)
&& variable_struct_exists(diagnostics_draw_client, "draw_network_diagnostics"))
{
	diagnostics_draw_client.draw_network_diagnostics();
}

/* draw_tool_cursor_available requires playable client view without join/mode,
host-menu, remote-admin or folder-modal input ownership. Pass false for these
blocking screens so the cursor cannot suggest an available world tool */
var draw_tool_cursor_available = is_client
	&& !client_join_screen
	&& !network_mode_screen
	&& !host_session_menu_open
	&& !official_admin_controls_open
	&& !scr_get_social().blocks_game_input()
	&& !scr_get_open_folder_modal().blocks_input();

/* Draw the world-tool cursor with the computed availability, then UI timing and
finally the folder modal. This order keeps the input-blocking modal on top */
scr_get_drawing().draw_tool_cursor(draw_tool_cursor_available);
scr_ui_perf_draw_overlay();
scr_get_open_folder_modal().draw();
#endregion /* Final Diagnostics and Modal Overlays END */
