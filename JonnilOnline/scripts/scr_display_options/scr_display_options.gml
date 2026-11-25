/// @description Find the visible game rectangle inside a letterboxed native window
function scr_display_rendered_rect(available_width, available_height, surface_width, surface_height)
{
	var fit = min(max(1, available_width) / max(1, surface_width), max(1, available_height) / max(1, surface_height));
	return {width: max(1, surface_width) * fit, height: max(1, surface_height) * fit};
}

/// @description Fit one GUI coordinate space to the rendered game without changing the world camera
function scr_display_gui_metrics(rendered_width, rendered_height, requested_percent)
{
	var width = max(1, rendered_width);
	var height = max(1, rendered_height);
	var requested = requested_percent == 0
		? clamp(floor(min(width / 960, height / 600) * 4) / 4, 1, 2)
		: clamp(requested_percent / 100, 1, 2);
	var effective = max(0.01, min(requested, width / 640, height / 540));
	return {width: width / effective, height: height / effective,
		requested_scale: requested, effective_scale: effective, limited: effective + 0.001 < requested};
}

/// @description Shared display preferences, observed fullscreen state and immediate local GUI saving
function scr_display_options(controller_id) constructor
{
	controller = controller_id;
	is_browser = os_browser != browser_not_a_browser;
	scale_percent = 0;
	scale_choices = [0, 100, 125, 150, 175, 200];
	metrics = scr_display_gui_metrics(1366, 768, 0);
	last_width = -1;
	last_height = -1;
	last_percent = -1;
	fullscreen = false;
	fullscreen_supported = true;
	fullscreen_shortcut = "F11";
	fullscreen_preference = false;
	native_initialized = false;
	native_requested = -1;
	native_request_due = 0;
	browser_gamepad_hint = false;
	save_feedback = "";
	fullscreen_feedback = "";
	controls = [];
	focus = "fullscreen";
	hover = "";
	try
	{
		if (file_exists("client_settings.ini"))
		{
			ini_open("client_settings.ini");
			var saved_scale = ini_read_real("display", "gui_scale_percent", 0);
			for (var index = 0; index < array_length(scale_choices); index++)
				if (saved_scale == scale_choices[index]) scale_percent = saved_scale;
			fullscreen_preference = ini_read_real("display", "fullscreen", 0) == 1;
			ini_close();
		}
	}
	catch(load_error)
	{
		try { ini_close(); } catch(close_error) {}
		save_feedback = "Display preferences could not be read. Defaults are available.";
	}

	save = function()
	{
		try
		{
			ini_open("client_settings.ini");
			ini_write_real("display", "gui_scale_percent", scale_percent);
			ini_write_real("display", "fullscreen", fullscreen_preference ? 1 : 0);
			ini_close();
			save_feedback = "";
			return true;
		}
		catch(save_error)
		{
			try { ini_close(); } catch(close_error) {}
			save_feedback = "Could not save display preferences on this device.";
			return false;
		}
	}

	set_scale = function(percent)
	{
		var accepted = false;
		for (var index = 0; index < array_length(scale_choices); index++)
			if (percent == scale_choices[index]) accepted = true;
		if (!accepted) return false;
		scale_percent = percent;
		last_percent = -1;
		update_gui();
		save();
		return true;
	}

	cycle_scale = function(direction)
	{
		var current_index = 0;
		for (var index = 0; index < array_length(scale_choices); index++)
			if (scale_choices[index] == scale_percent) current_index = index;
		return set_scale(scale_choices[(current_index + sign(direction) + array_length(scale_choices)) mod array_length(scale_choices)]);
	}

	scale_label = function()
	{
		return scale_percent == 0 ? "Auto (Default)" : string(scale_percent) + "%";
	}

	update_gui = function()
	{
		var rendered_width = max(1, window_get_width());
		var rendered_height = max(1, window_get_height());
		if (is_browser)
		{
			try
			{
				rendered_width = max(1, html5_display_canvas_width());
				rendered_height = max(1, html5_display_canvas_height());
			}
			catch(size_error) {}
		}
		else
		{
			/* GUI drawing follows the application surface, including its native letterbox. */
			var surface_width = max(1, view_get_wport(0));
			var surface_height = max(1, view_get_hport(0));
			if (surface_exists(application_surface))
			{
				surface_width = surface_get_width(application_surface);
				surface_height = surface_get_height(application_surface);
			}
			var rendered = scr_display_rendered_rect(rendered_width, rendered_height, surface_width, surface_height);
			rendered_width = rendered.width;
			rendered_height = rendered.height;
		}
		if (rendered_width == last_width && rendered_height == last_height && scale_percent == last_percent) return;
		metrics = scr_display_gui_metrics(rendered_width, rendered_height, scale_percent);
		display_set_gui_size(round(metrics.width), round(metrics.height));
		last_width = rendered_width;
		last_height = rendered_height;
		last_percent = scale_percent;
	}

	toggle_fullscreen = function()
	{
		if (!fullscreen_supported || controller.managed_dedicated_server) return false;
		if (is_browser)
		{
			/* The browser bridge handles the actual pointer or key gesture directly. */
			return false;
		}
		try
		{
			native_requested = window_get_fullscreen() ? 0 : 1;
			native_request_due = current_time + 2000;
			window_set_fullscreen(native_requested == 1);
			fullscreen_feedback = "";
			return true;
		}
		catch(fullscreen_error) { native_requested = -1; fullscreen_feedback = "Fullscreen could not be changed."; return false; }
	}

	update = function()
	{
		if (controller.managed_dedicated_server) return;
		if (is_browser)
		{
			try
			{
				fullscreen = html5_display_fullscreen_state() == 1;
				fullscreen_supported = html5_display_fullscreen_available() == 1;
				fullscreen_shortcut = html5_display_shortcut_label();
				fullscreen_feedback = html5_display_fullscreen_status();
			}
			catch(fullscreen_error)
			{
				fullscreen_supported = false;
				fullscreen_feedback = "Fullscreen is unavailable on this browser page.";
			}
		}
		else
		{
			if (!native_initialized)
			{
				native_initialized = true;
				if (fullscreen_preference != window_get_fullscreen())
				{
					native_requested = fullscreen_preference ? 1 : 0;
					native_request_due = current_time + 2000;
					try { window_set_fullscreen(fullscreen_preference); } catch(fullscreen_error) { native_requested = -1; }
				}
			}
			fullscreen = window_get_fullscreen();
			if (native_requested != -1)
			{
				if (fullscreen == (native_requested == 1))
				{
					native_requested = -1;
					fullscreen_preference = fullscreen;
					save();
				}
				else if (current_time >= native_request_due)
				{
					native_requested = -1;
					fullscreen_feedback = "Fullscreen could not be changed.";
				}
			}
			else if (fullscreen_preference != fullscreen)
			{
				fullscreen_preference = fullscreen;
				save();
			}
		}
		update_gui();
		controller.options_update_layout();
		update_layout();
		if (is_browser)
		{
			var enabled = controller.options_screen_open && controller.options_tab == "display"
				&& !controller.options_guidance_open && fullscreen_supported
				&& !scr_get_open_folder_modal().blocks_input();
			var button = controls[0];
			var application_bounds = application_get_position();
			html5_display_fullscreen_control(button.x, button.y, button.width, button.height,
				display_get_gui_width(), display_get_gui_height(), focus == "fullscreen" ? 1 : 0, enabled ? 1 : 0,
				application_bounds[0], application_bounds[1], application_bounds[2] - application_bounds[0], application_bounds[3] - application_bounds[1]);
		}
	}

	update_layout = function()
	{
		var ctrl = controller;
		var top = ctrl.options_panel_y + 124;
		controls = [
			{key: "fullscreen", x: ctrl.options_hue_x, y: top, width: ctrl.options_hue_width, height: 44},
			{key: "scale_left", x: ctrl.options_row_left_x, y: top + 94, width: ctrl.options_arrow_width, height: 44},
			{key: "scale_right", x: ctrl.options_row_right_x, y: top + 94, width: ctrl.options_arrow_width, height: 44},
			{key: "reset", x: ctrl.options_hue_x, y: top + 210, width: ctrl.options_hue_width, height: 40}
		];
	}

	activate = function(key)
	{
		switch (key)
		{
			case "fullscreen": return toggle_fullscreen();
			case "scale_left": return cycle_scale(-1);
			case "scale_right": case "scale": return cycle_scale(1);
			case "reset": return set_scale(0);
		}
		return false;
	}

	update_input = function()
	{
		var ctrl = controller;
		if (ctrl.options_guidance_open) return false;
		var mx = scr_gui_mouse_x(0);
		var my = scr_gui_mouse_y(0);
		var pressed = mouse_check_button_pressed(mb_left);
		var over_tab = ctrl.options_point_in_rect(mx, my, ctrl.options_display_tab_x, ctrl.options_tab_y, ctrl.options_tab_width, ctrl.options_tab_height);
		if (ctrl.options_tab != "display")
		{
			if (over_tab) ctrl.options_hover = "display_tab";
			if (pressed && over_tab) { ctrl.options_switch_tab("display"); focus = "fullscreen"; return true; }
			return false;
		}
		update_layout();
		hover = "";
		ctrl.options_hover = over_tab ? "display_tab" : "";
		var tabs_x = [ctrl.options_display_tab_x, ctrl.options_appearance_tab_x, ctrl.options_performance_tab_x, ctrl.options_diagnostics_tab_x, ctrl.options_presence_tab_x];
		var tabs = ["display", "appearance", "performance", "diagnostics", "presence"];
		for (var index = 0; index < array_length(tabs); index++)
			if (pressed && ctrl.options_point_in_rect(mx, my, tabs_x[index], ctrl.options_tab_y, ctrl.options_tab_width, ctrl.options_tab_height))
			{ ctrl.options_switch_tab(tabs[index]); return true; }
		for (var index = 0; index < array_length(controls); index++)
		{
			var button = controls[index];
			if (ctrl.options_point_in_rect(mx, my, button.x, button.y, button.width, button.height))
			{
				hover = button.key;
				if (pressed) { focus = button.key == "scale_left" || button.key == "scale_right" ? "scale" : button.key; activate(button.key); return true; }
			}
		}
		var done = ctrl.options_point_in_rect(mx, my, ctrl.options_apply_x, ctrl.options_apply_y, ctrl.options_hue_width, ctrl.options_apply_height);
		if (done) hover = "done";
		if (pressed && done) { ctrl.options_close(true); return true; }
		var pad = gamepad_is_connected(0);
		if (keyboard_check_pressed(vk_escape) || (pad && gamepad_button_check_pressed(0, gp_face2))) { ctrl.options_close(true); return true; }
		var tab_move = keyboard_check_pressed(vk_pagedown) - keyboard_check_pressed(vk_pageup);
		if (pad) tab_move += gamepad_button_check_pressed(0, gp_shoulderr) - gamepad_button_check_pressed(0, gp_shoulderl);
		if (tab_move != 0) { ctrl.options_cycle_tab(tab_move); return true; }
		var move_y = keyboard_check_pressed(vk_down) - keyboard_check_pressed(vk_up);
		if (keyboard_check_pressed(vk_tab)) move_y = keyboard_check(vk_shift) ? -1 : 1;
		if (pad) move_y += gamepad_button_check_pressed(0, gp_padd) - gamepad_button_check_pressed(0, gp_padu);
		var order = fullscreen_supported ? ["tabs", "fullscreen", "scale", "reset", "done"] : ["tabs", "scale", "reset", "done"];
		if (move_y != 0)
		{
			var current_index = 0;
			for (var index = 0; index < array_length(order); index++) if (focus == order[index]) current_index = index;
			focus = order[(current_index + sign(move_y) + array_length(order)) mod array_length(order)];
		}
		var move_x = keyboard_check_pressed(vk_right) - keyboard_check_pressed(vk_left);
		if (pad) move_x += gamepad_button_check_pressed(0, gp_padr) - gamepad_button_check_pressed(0, gp_padl);
		if (move_x != 0)
		{
			if (focus == "tabs") ctrl.options_cycle_tab(move_x);
			else if (focus == "scale") cycle_scale(move_x);
		}
		var accept = keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space) || (pad && gamepad_button_check_pressed(0, gp_face1));
		if (accept)
		{
			if (focus == "tabs") ctrl.options_cycle_tab(1);
			else if (focus == "done") ctrl.options_close(true);
			else if (focus == "fullscreen" && is_browser && pad && gamepad_button_check_pressed(0, gp_face1)) browser_gamepad_hint = true;
			else activate(focus);
		}
		if (focus != "fullscreen") browser_gamepad_hint = false;
		ctrl.options_focus = focus == "tabs" ? "tabs" : "display_" + focus;
		return true;
	}

	draw = function()
	{
		update_layout();
		var ctrl = controller;
		var button = controls[0];
		scr_draw_menu_button(button.x, button.y, button.width, button.height, "", hover == "fullscreen", focus == "fullscreen", fullscreen_supported, false, false, 1);
		var box_x = button.x + 12;
		var box_y = button.y + 12;
		draw_set_colour(make_color_rgb(220, 220, 224));
		draw_rectangle(box_x, box_y, box_x + 18, box_y + 18, true);
		if (fullscreen)
		{
			draw_set_colour(make_color_rgb(126, 245, 150));
			draw_line_width(box_x + 3, box_y + 9, box_x + 7, box_y + 14, 2);
			draw_line_width(box_x + 7, box_y + 14, box_x + 15, box_y + 3, 2);
		}
		draw_set_halign(fa_left);
		draw_set_colour(fullscreen_supported ? c_white : c_gray);
		scr_render_text(button.x + 42, button.y + 12, "Fullscreen", 18, button.width - 54);
		var fullscreen_help = fullscreen_feedback;
		if (!fullscreen_supported && fullscreen_help == "") fullscreen_help = "Fullscreen is unavailable on this browser page.";
		if (browser_gamepad_hint && fullscreen_help == "") fullscreen_help = "Use " + fullscreen_shortcut + " or click Fullscreen. A gamepad cannot change browser fullscreen.";
		if (fullscreen_help == "") fullscreen_help = is_browser
			? fullscreen_shortcut + " toggles the game. Escape leaves fullscreen."
			: fullscreen_shortcut + " toggles fullscreen.";
		draw_set_colour(c_ltgray);
		scr_render_text_wrapped(button.x, button.y + 54, fullscreen_help, 16, button.width, 3);
		for (var index = 1; index <= 2; index++)
		{
			var arrow = controls[index];
			scr_draw_menu_button(arrow.x, arrow.y, arrow.width, arrow.height, index == 1 ? "<" : ">", hover == arrow.key, false, true, false, false, 20);
		}
		var scale_y = controls[1].y;
		draw_set_colour(make_color_rgb(13, 15, 18));
		draw_rectangle(ctrl.options_row_value_x, scale_y, ctrl.options_row_value_x + ctrl.options_row_value_width, scale_y + 44, false);
		draw_set_colour(focus == "scale" ? make_color_rgb(255, 220, 95) : make_color_rgb(86, 90, 98));
		draw_rectangle(ctrl.options_row_value_x, scale_y, ctrl.options_row_value_x + ctrl.options_row_value_width, scale_y + 44, true);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(ctrl.options_row_value_x + ctrl.options_row_value_width * 0.5, scale_y + 12, "GUI Scale: " + scale_label(), 18, ctrl.options_row_value_width - 16);
		draw_set_halign(fa_left);
		draw_set_colour(c_ltgray);
		var scale_help = "Changes menus and text. Camera zoom stays the same.";
		if (metrics.limited) scale_help += " Fitted to " + string(round(metrics.effective_scale * 100)) + "% so controls stay visible.";
		scr_render_text_wrapped(button.x, scale_y + 56, scale_help, 16, button.width, 3);
		var reset = controls[3];
		scr_draw_menu_button(reset.x, reset.y, reset.width, reset.height, "Reset GUI Scale to Auto", hover == "reset", focus == "reset", true, true, false, 18);
		if (save_feedback != "")
		{
			draw_set_colour(make_color_rgb(255, 190, 150));
			scr_render_text_wrapped(button.x, reset.y + reset.height + 12, save_feedback, 16, button.width, 3);
		}
		scr_draw_menu_button(ctrl.options_apply_x, ctrl.options_apply_y, ctrl.options_hue_width, ctrl.options_apply_height, "Done", hover == "done", focus == "done", true, false, false, 19);
	}
}

/// @description Convert the browser pointer through its rendered canvas and GUI viewport
function scr_gui_mouse_x(device = 0)
{
	if (os_browser == browser_not_a_browser || device != 0) return device_mouse_x_to_gui(device);
	var application_bounds = application_get_position();
	return html5_display_gui_x(window_mouse_get_x(), display_get_gui_width(),
		application_bounds[0], application_bounds[2] - application_bounds[0]);
}

/// @description Use the same browser coordinate transform for drawing and GUI hit testing
function scr_gui_mouse_y(device = 0)
{
	if (os_browser == browser_not_a_browser || device != 0) return device_mouse_y_to_gui(device);
	var application_bounds = application_get_position();
	return html5_display_gui_y(window_mouse_get_y(), display_get_gui_height(),
		application_bounds[1], application_bounds[3] - application_bounds[1]);
}
