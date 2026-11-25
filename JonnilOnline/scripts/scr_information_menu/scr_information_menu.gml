/// @description Initialize the Information hub on its owning network controller
function scr_information_menu_initialize()
{
	information_screen_open = false;
	information_page = "main";
	information_focus = "tab_main";
	information_hover_button = "";
	information_gamepad_navigation_due = 0;
	information_history = [];
	information_tabs = [];
	information_controls = [];
	information_actions = [];
	information_primary_action = undefined;
	information_content_data = undefined;
	information_document = {title: "", body: "", actions: [], available: true};
	information_lines = [];
	information_wrap_key = "";
	information_scroll_offset = 0;
	information_scroll_max = 0;
	information_credits_playing = false;
	information_credits_start_due = 0;
	information_gui_owned = false;
	information_previous_gui_width = 0;
	information_previous_gui_height = 0;

	/* Keep destinations and native logos together. Optional links come from the
	Included File configuration when Information opens */
	information_links = [
		{name: "Discord", url: "https://discord.jonnil.games", icon: spr_logo_discord},
		{name: "Instagram", url: "https://www.instagram.com/jonnilll", icon: spr_logo_instagram},
		{name: "Reddit", url: "https://www.reddit.com/r/Jonnil", icon: spr_logo_reddit},
		{name: "Bluesky", url: "https://bsky.app/profile/jonnil.games", icon: spr_logo_bluesky},
		{name: "YouTube", url: "https://www.youtube.com/Jonnilescom", icon: spr_logo_youtube},
		{name: "GitHub", url: "https://github.com/Jonnil-Games", icon: spr_logo_github},
		{name: "Website", url: "https://www.jonnil.games/", icon: noone}
	];

	information_url_is_enabled = function(destination)
	{
		var link_url = string_trim(string(destination));
		return string_copy(link_url, 1, 8) == "https://" && string_length(link_url) > 8
			&& string_pos(" ", link_url) == 0 && string_pos(chr(9), link_url) == 0
			&& string_pos(chr(10), link_url) == 0 && string_pos(chr(13), link_url) == 0;
	}

	/// @description Prepare one page without rebuilding its content every Draw
	information_load_page = function(page_name)
	{
		information_page = page_name;
		information_document = scr_information_content(page_name, information_content_data);
		information_actions = information_document.actions;
		information_primary_action = undefined;
		if (page_name == "support" && array_length(information_actions) > 0)
		{
			/* The support destination stays fixed while longer approved text scrolls */
			information_primary_action = information_actions[0];
			information_actions = [];
		}
		if (page_name == "links")
		{
			information_document.title = "Links";
			information_document.body = "Community and studio destinations open in your browser.";
			information_actions = [];
			for (var link_index = 0; link_index < array_length(information_links); link_index++)
			{
				var link = information_links[link_index];
				if (!information_url_is_enabled(link.url)) continue;
				array_push(information_actions, {id: "link_" + string(link_index), label: link.name,
					kind: "url", target: link.url, enabled: true, icon: link.icon});
			}
		}
		information_wrap_key = "";
		information_scroll_offset = 0;
		information_hover_button = "";
		information_credits_playing = page_name == "credits";
		information_credits_start_due = current_time + 1500;
	}

	/// @description Construct shared drawing and hit-test rectangles in GUI units
	information_update_layout = function()
	{
		var physical_width = max(1, display_get_gui_width());
		var physical_height = max(1, display_get_gui_height());
		/* Small windows scale one shared coordinate space so tabs and the footer
		cannot consume the entire document or make a full action row unreachable */
		information_gui_scale = min(1, physical_width / 480, physical_height / 360);
		var gui_width = physical_width / information_gui_scale;
		var gui_height = physical_height / information_gui_scale;
		information_gui_width = gui_width;
		information_gui_height = gui_height;
		var compact = gui_height < 520;
		var margin = gui_width < 640 || compact ? 8 : 24;
		information_panel_width = min(1120, max(1, gui_width - margin * 2));
		information_panel_height = min(820, max(1, gui_height - margin * 2));
		information_panel_x = (gui_width - information_panel_width) * 0.5;
		information_panel_y = (gui_height - information_panel_height) * 0.5;
		var padding = information_panel_width < 640 ? 14 : 28;
		var inner_width = max(1, information_panel_width - padding * 2);
		var gap = 8;
		var tab_count = max(1, array_length(information_tabs));
		var columns = inner_width >= 840 ? tab_count : min(tab_count, max(1, min(4, floor((inner_width + gap) / 108))));
		var rows = ceil(tab_count / columns);
		var tab_width = max(1, (inner_width - gap * (columns - 1)) / columns);
		var tab_height = compact ? 32 : 38;
		var tab_top = information_panel_y + (compact ? 47 : 75);
		information_body_x = information_panel_x + padding;
		information_body_width = max(1, inner_width - 12);
		information_title_y = tab_top + rows * (tab_height + gap) + 5;
		information_body_top = information_title_y + (compact ? 30 : 38);
		information_footer_y = information_panel_y + information_panel_height - (compact ? 57 : 66);
		information_body_bottom = max(information_body_top + 1, information_footer_y - 14);
		information_text_height = compact ? 16 : 19;
		information_line_step = information_text_height + 6;

		/* Font, width and body identify wrapped text. Resizing reclamps the same
		offset without reparsing content or opening files during drawing */
		var wrap_key = string(scr_render_text_primary_font()) + ":"
			+ string(scr_render_text_font_for_text(information_document.body)) + ":"
			+ string(information_body_width) + ":" + string(information_text_height)
			+ ":" + information_document.body;
		if (information_wrap_key != wrap_key)
		{
			information_lines = information_document.body == "" ? []
				: string_split(scr_text_wrap(information_document.body, information_text_height, information_body_width), "\n");
			information_wrap_key = wrap_key;
		}
		information_text_content_height = max(0, array_length(information_lines) * information_line_step - 6);
		information_action_height = information_page == "links" ? 54 : 40;
		information_action_pitch = information_action_height + 8;
		information_actions_top = information_text_content_height + (array_length(information_actions) > 0 ? 22 : 0);
		var content_height = array_length(information_actions) > 0
			? information_actions_top + array_length(information_actions) * information_action_pitch - 8
			: information_text_content_height;
		information_scroll_max = max(0, ceil(content_height - (information_body_bottom - information_body_top)));
		information_scroll_offset = clamp(information_scroll_offset, 0, information_scroll_max);
		if (information_scroll_max <= 0) information_credits_playing = false;

		information_controls = [];
		for (var tab_index = 0; tab_index < array_length(information_tabs); tab_index++)
		{
			var tab = information_tabs[tab_index];
			array_push(information_controls, {id: "tab_" + tab.id, label: tab.label, kind: "tab", target: tab.id,
				left: information_body_x + (tab_index mod columns) * (tab_width + gap),
				top: tab_top + floor(tab_index / columns) * (tab_height + gap),
				width: tab_width, height: tab_height, enabled: true, visible: true});
		}
		for (var action_index = 0; action_index < array_length(information_actions); action_index++)
		{
			var action = information_actions[action_index];
			var action_top = information_body_top + information_actions_top
				+ action_index * information_action_pitch - information_scroll_offset;
			array_push(information_controls, {id: "action_" + string(action_index), label: action.label,
				kind: "action", target: action_index, left: information_body_x, top: action_top,
				width: information_body_width, height: information_action_height,
				enabled: action.enabled, visible: action_top >= information_body_top
					&& action_top + information_action_height <= information_body_bottom});
		}

		/* Fixed slots prevent To Top appearing or disappearing from moving Back */
		var footer_width = max(1, (inner_width - gap * 4) / 5);
		var footer_height = compact ? 32 : 38;
		var has_primary = is_struct(information_primary_action);
		var footer_ids = ["up", "down", "top", has_primary ? "primary" : "credits_play", "back"];
		var footer_labels = ["Up", "Down", "To Top", has_primary ? information_primary_action.label
			: (information_credits_playing ? "Pause" : "Play"), "Back"];
		for (var footer_index = 0; footer_index < 5; footer_index++)
		{
			var footer_id = footer_ids[footer_index];
			var shown = footer_id == "back" || footer_id == "primary" || (information_scroll_max > 0
				&& (footer_id != "top" || information_scroll_offset > 0)
				&& (footer_id != "credits_play" || information_page == "credits"));
			var enabled = shown && (footer_id != "up" || information_scroll_offset > 0)
				&& (footer_id != "down" || information_scroll_offset < information_scroll_max);
			array_push(information_controls, {id: footer_id, label: footer_labels[footer_index], kind: footer_id == "primary" ? "primary" : "footer", target: footer_id,
				left: information_body_x + footer_index * (footer_width + gap), top: information_footer_y,
				width: footer_width, height: footer_height, enabled: enabled, visible: shown});
		}
	}

	/// @description Select a page and retain nested callers for Back
	information_select_page = function(page_name, nested = false)
	{
		if (page_name == "whats_new")
		{
			information_credits_playing = false;
			information_focus = "tab_whats_new";
			whats_new_open();
			return true;
		}
		var document = scr_information_content(page_name, information_content_data);
		if (!document.available) return false;
		if (nested)
		{
			array_push(information_history, {page: information_page, focus: information_focus, scroll: information_scroll_offset});
		}
		else information_history = [];
		information_load_page(page_name);
		information_focus = nested ? "back" : "tab_" + page_name;
		information_gamepad_navigation_due = current_time + 180;
		information_update_layout();
		return true;
	}

	/// @description Retain the shared display mapping when closing this overlay
	information_release_gui = function()
	{
		information_gui_owned = false;
	}

	information_open = function()
	{
		escape_exit_hold_reset();
		/* All menus use the shared GUI scale, including drawing and pointer coordinates. */
		network_mode_focus = "";
		keyboard_string = "";
		information_content_data = scr_information_content_load();
		information_tabs = [
			{id: "main", label: "About"}, {id: "whats_new", label: "What's New"},
			{id: "backups", label: "Backups"}, {id: "community", label: "Community"},
			{id: "credits", label: "Credits"}, {id: "links", label: "Links"}
		];
		if (information_content_data.support_available)
		{
			array_push(information_tabs, {id: "support", label: "Support"});
		}
		information_screen_open = true;
		return information_select_page("main");
	}

	information_close = function()
	{
		escape_exit_hold_reset();
		information_release_gui();
		information_screen_open = false;
		information_history = [];
		information_hover_button = "";
		information_credits_playing = false;
		network_mode_gamepad_focus = "information";
		return true;
	}

	information_back = function()
	{
		escape_exit_hold_reset();
		if (array_length(information_history) > 0)
		{
			var caller = array_pop(information_history);
			information_load_page(caller.page);
			information_focus = caller.focus;
			information_scroll_offset = caller.scroll;
			information_credits_playing = false;
			information_gamepad_navigation_due = current_time + 180;
			information_update_layout();
			return true;
		}
		return information_close();
	}

	/// @description Keep focused content actions visible without making hidden rows clickable
	information_reveal_focus = function()
	{
		for (var control_index = 0; control_index < array_length(information_controls); control_index++)
		{
			var control = information_controls[control_index];
			if (control.id != information_focus || control.kind != "action") continue;
			if (control.top < information_body_top) information_scroll_offset -= information_body_top - control.top;
			else if (control.top + control.height > information_body_bottom)
			{
				information_scroll_offset += control.top + control.height - information_body_bottom;
			}
			information_scroll_offset = clamp(information_scroll_offset, 0, information_scroll_max);
			information_update_layout();
			break;
		}
	}

	information_activate = function(control)
	{
		if (!control.enabled || !control.visible) return;
		information_focus = control.id;
		if (control.kind == "tab")
		{
			information_select_page(control.target);
			return;
		}
		if (control.kind == "action" || control.kind == "primary")
		{
			var action = control.kind == "primary" ? information_primary_action : information_actions[control.target];
			information_credits_playing = false;
			if (action.kind == "page") information_select_page(action.target, true);
			else if (action.kind == "folder" && scr_desktop_folder_opening_is_enabled())
			{
				var folder_label = string_copy(action.label, 1, 5) == "Open " ? string_delete(action.label, 1, 5) : action.label;
				scr_open_folder(action.target, folder_label);
			}
			else if (action.kind == "url" && information_url_is_enabled(action.target))
			{
				var destination = string_trim(string(action.target));
				if (scr_get_network().is_browser_runtime()) url_open_ext(destination, "_blank");
				else url_open(destination);
			}
			return;
		}
		if (control.id == "back") information_back();
		else if (control.id == "top")
		{
			information_scroll_offset = 0;
			information_credits_playing = false;
			information_focus = "down";
		}
		else if (control.id == "credits_play")
		{
			if (information_scroll_offset >= information_scroll_max) information_scroll_offset = 0;
			information_credits_playing = !information_credits_playing;
			information_credits_start_due = current_time + 1000;
		}
		else if (control.id == "up" || control.id == "down")
		{
			information_credits_playing = false;
			information_scroll_offset = clamp(information_scroll_offset + (control.id == "down" ? 40 : -40), 0, information_scroll_max);
		}
	}

	/// @description Route one input owner while networking continues in the existing Step
	information_update_input = function()
	{
		information_update_layout();
		information_reveal_focus();
		var controller = gamepad_is_connected(0);
		if (keyboard_check_pressed(vk_escape) || (controller && gamepad_button_check_pressed(0, gp_face2)))
		{
			information_back();
			return true;
		}
		var pointer_x = scr_gui_mouse_x(0) / information_gui_scale;
		var pointer_y = scr_gui_mouse_y(0) / information_gui_scale;
		var mouse_pressed = mouse_check_button_pressed(mb_left);
		var accept_pressed = keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space)
			|| (controller && gamepad_button_check_pressed(0, gp_face1));
		var accept_held = keyboard_check(vk_enter) || keyboard_check(vk_space)
			|| (controller && gamepad_button_check(0, gp_face1));
		information_hover_button = "";
		for (var hover_index = 0; hover_index < array_length(information_controls); hover_index++)
		{
			var hovered = information_controls[hover_index];
			if (hovered.visible && hovered.enabled && point_in_rectangle(pointer_x, pointer_y,
				hovered.left, hovered.top, hovered.left + hovered.width, hovered.top + hovered.height))
			{
				information_hover_button = hovered.id;
				break;
			}
		}

		var move_direction = 0;
		if (keyboard_check_pressed(vk_tab)) move_direction = keyboard_check(vk_shift) ? -1 : 1;
		else if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(ord("A"))
			|| keyboard_check_pressed(vk_up) || keyboard_check_pressed(ord("W"))) move_direction = -1;
		else if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(ord("D"))
			|| keyboard_check_pressed(vk_down) || keyboard_check_pressed(ord("S"))) move_direction = 1;
		if (controller && current_time >= information_gamepad_navigation_due)
		{
			var previous = gamepad_button_check(0, gp_padl) || gamepad_button_check(0, gp_padu)
				|| gamepad_axis_value(0, gp_axislh) < -0.65 || gamepad_axis_value(0, gp_axislv) < -0.65;
			var next = gamepad_button_check(0, gp_padr) || gamepad_button_check(0, gp_padd)
				|| gamepad_axis_value(0, gp_axislh) > 0.65 || gamepad_axis_value(0, gp_axislv) > 0.65;
			if (previous != next)
			{
				move_direction = previous ? -1 : 1;
				information_gamepad_navigation_due = current_time + 180;
			}
		}

		/* All available content actions participate in navigation, including rows
		outside the viewport. Selection reveals a row before it can be accepted */
		var focus_options = [];
		var focus_index = -1;
		for (var option_index = 0; option_index < array_length(information_controls); option_index++)
		{
			var option = information_controls[option_index];
			if (!option.enabled || (!option.visible && option.kind != "action")) continue;
			if (option.id == information_focus) focus_index = array_length(focus_options);
			array_push(focus_options, option.id);
		}
		if (focus_index < 0)
		{
			information_focus = "back";
			focus_index = array_length(focus_options) - 1;
		}
		if (move_direction != 0)
		{
			focus_index = (focus_index + move_direction + array_length(focus_options)) mod array_length(focus_options);
			information_focus = focus_options[focus_index];
			information_credits_playing = false;
			information_reveal_focus();
		}

		var scroll_change = 0;
		if (pointer_x >= information_body_x && pointer_x <= information_body_x + information_body_width
		&& pointer_y >= information_body_top && pointer_y <= information_body_bottom)
		{
			scroll_change += (mouse_wheel_down() - mouse_wheel_up()) * 40;
		}
		var page_distance = max(1, (information_body_bottom - information_body_top) * 0.8);
		if (keyboard_check_pressed(vk_pageup) || keyboard_check_pressed(vk_pagedown)
		|| keyboard_check_pressed(vk_home) || keyboard_check_pressed(vk_end)) information_credits_playing = false;
		if (keyboard_check_pressed(vk_pageup)) scroll_change -= page_distance;
		if (keyboard_check_pressed(vk_pagedown)) scroll_change += page_distance;
		if (keyboard_check_pressed(vk_home)) scroll_change = -information_scroll_offset;
		if (keyboard_check_pressed(vk_end)) scroll_change = information_scroll_max - information_scroll_offset;
		var held_up = (information_hover_button == "up" && mouse_check_button(mb_left))
			|| (information_focus == "up" && accept_held);
		var held_down = (information_hover_button == "down" && mouse_check_button(mb_left))
			|| (information_focus == "down" && accept_held);
		var elapsed_seconds = min(0.05, max(0, delta_time * 0.000001));
		if (held_up != held_down) scroll_change += (held_down ? 1 : -1) * 420 * elapsed_seconds;
		if (scroll_change != 0)
		{
			information_credits_playing = false;
			information_scroll_offset = clamp(information_scroll_offset + scroll_change, 0, information_scroll_max);
			information_update_layout();
			for (var hidden_index = 0; hidden_index < array_length(information_controls); hidden_index++)
			{
				var hidden_control = information_controls[hidden_index];
				if (hidden_control.id == information_focus && hidden_control.kind == "action" && !hidden_control.visible)
				{
					information_focus = "back";
				}
			}
		}
		else if (information_credits_playing && current_time >= information_credits_start_due)
		{
			information_scroll_offset = min(information_scroll_max, information_scroll_offset + 28 * elapsed_seconds);
			if (information_scroll_offset >= information_scroll_max) information_credits_playing = false;
			information_update_layout();
		}

		var activation = mouse_pressed ? information_hover_button : (accept_pressed ? information_focus : "");
		for (var activation_index = 0; activation_index < array_length(information_controls); activation_index++)
		{
			var control = information_controls[activation_index];
			if (control.id == activation)
			{
				if (mouse_pressed && !point_in_rectangle(pointer_x, pointer_y, control.left,
					control.top, control.left + control.width, control.top + control.height)) break;
				information_activate(control);
				break;
			}
		}
		return true;
	}

	/// @description Draw complete document lines and action rows within a fixed reading area
	information_draw = function()
	{
		information_update_layout();
		var previous_world = matrix_get(matrix_world);
		matrix_set(matrix_world, matrix_build(0, 0, 0, 0, 0, 0, information_gui_scale, information_gui_scale, 1));
		draw_set_alpha(0.97);
		draw_set_colour(make_color_rgb(8, 9, 12));
		draw_rectangle(0, 0, information_gui_width, information_gui_height, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(24, 26, 30));
		draw_rectangle(information_panel_x, information_panel_y,
			information_panel_x + information_panel_width, information_panel_y + information_panel_height, false);
		draw_set_colour(make_color_rgb(76, 78, 84));
		draw_rectangle(information_panel_x, information_panel_y,
			information_panel_x + information_panel_width, information_panel_y + information_panel_height, true);
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		draw_set_colour(c_white);
		scr_render_text(information_body_x, information_panel_y + 14, "Information", 26, information_body_width * 0.55);
		draw_set_halign(fa_right);
		draw_set_colour(make_color_rgb(178, 183, 194));
		scr_render_text(information_body_x + information_body_width, information_panel_y + 21,
			game_version_label, 14, information_body_width * 0.42);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);
		scr_render_text(information_body_x, information_title_y, information_document.title, 22, information_body_width);
		draw_set_colour(make_color_rgb(225, 229, 237));
		for (var line_index = 0; line_index < array_length(information_lines); line_index++)
		{
			var line_top = information_body_top + line_index * information_line_step - information_scroll_offset;
			if (line_top < information_body_top || line_top + information_text_height > information_body_bottom) continue;
			scr_render_text(information_body_x, line_top, information_lines[line_index], information_text_height, information_body_width);
		}
		for (var draw_index = 0; draw_index < array_length(information_controls); draw_index++)
		{
			var control = information_controls[draw_index];
			if (!control.visible) continue;
			var active_tab = control.kind == "tab" && control.target == information_page;
			var focused = information_focus == control.id;
			var hovered = information_hover_button == control.id;
			var link_row = information_page == "links" && control.kind == "action";
			scr_draw_menu_button(control.left, control.top, control.width, control.height,
				link_row ? "" : control.label, hovered, focused || active_tab, control.enabled,
				control.kind == "footer", false, information_panel_width < 640 ? 14 : 17);
			if (link_row)
			{
				var action = information_actions[control.target];
				if (sprite_exists(action.icon))
				{
					draw_set_colour(c_white);
					draw_roundrect(control.left + 8, control.top + 8, control.left + 46, control.top + 46, false);
					scr_draw_menu_icon(action.icon, control.left + 27, control.top + 27, 30);
				}
				var theme = scr_menu_button_get_theme();
				draw_set_halign(fa_left);
				draw_set_valign(fa_top);
				draw_set_colour((focused || hovered) && theme.transparency == JONNIL_MENU_BUTTON_INVISIBLE ? theme.focus_colour : theme.text_colour);
				scr_render_text(control.left + 58, control.top + 6, action.label, 17, max(1, control.width - 70));
				scr_render_text(control.left + 58, control.top + 31, action.target, 13, max(1, control.width - 70));
			}
			if (control.id == "tab_whats_new" && whats_new_unread)
			{
				draw_set_colour(make_color_rgb(255, 220, 95));
				draw_circle(control.left + control.width - 10, control.top + 8, 4, false);
			}
		}
		if (information_scroll_max > 0)
		{
			var track_left = information_body_x + information_body_width + 7;
			var track_height = information_body_bottom - information_body_top;
			var thumb_height = min(track_height, max(18, track_height * track_height / (track_height + information_scroll_max)));
			var thumb_top = information_body_top + (track_height - thumb_height) * information_scroll_offset / information_scroll_max;
			draw_set_colour(make_color_rgb(58, 63, 74));
			draw_rectangle(track_left, information_body_top, track_left + 4, information_body_bottom, false);
			draw_set_colour(make_color_rgb(154, 169, 190));
			draw_rectangle(track_left, thumb_top, track_left + 4, thumb_top + thumb_height, false);
		}
		draw_set_halign(fa_center);
		draw_set_valign(fa_top);
		draw_set_colour(make_color_rgb(156, 164, 177));
		scr_render_text(information_panel_x + information_panel_width * 0.5,
			information_panel_y + information_panel_height - 20,
			information_panel_width < 640 ? "Tab: select | Enter/A: open | Esc/B: back"
				: "Arrows/Tab: select | Enter/A: open | Wheel/Page Up/Down: scroll | Esc/B: back", 12, information_body_width);
		draw_set_halign(fa_left);
		draw_set_colour(c_white);
		draw_set_alpha(1);
		matrix_set(matrix_world, previous_world);
		scr_get_open_folder_modal().draw();
	}
}
