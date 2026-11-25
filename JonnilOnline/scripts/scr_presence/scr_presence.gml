/// @description Return Unix seconds without changing the game's chosen date timezone
function jonnil_presence_unix_time()
{
	var previous_zone = date_get_timezone();
	date_set_timezone(timezone_utc);
	var result = floor(date_second_span(date_create_datetime(1970, 1, 1, 0, 0, 0), date_current_datetime()));
	date_set_timezone(previous_zone);
	return int64(result);
}

/// @description Release only a Discord client successfully initialized by this controller
function jonnil_discord_extension_finalize()
{
	if (!variable_global_exists("jonnil_presence")) return;
	var service = global.jonnil_presence;
	if (!is_struct(service) || !service.initialized) return;
	/* Clear the guard before calling native code so repeated end events cannot free it twice */
	service.initialized = false;
	try { discord_social_client_clear_rich_presence(); } catch(clear_error) {}
	try { discord_social_shutdown(); } catch(shutdown_error) {}
}

/// @description Read only supported protocol numbers from this game's public invitation formats
function jonnil_presence_public_join_protocol(raw_target)
{
	if (!is_string(raw_target) || string_length(raw_target) > 180) return 0;
	var target = string_trim(raw_target);
	for (var protocol = GAMEPLAY_PROTOCOL_MIN_SUPPORTED; protocol <= GAMEPLAY_PROTOCOL_VERSION; protocol++)
	{
		if (target == "jo1:public:" + string(protocol)
		|| target == "jonnilonline://join/public?protocol=" + string(protocol)) return protocol;
	}
	return 0;
}

/// @description Own optional profile activity, public-name consent and validated public session invitations
function scr_presence(owner) constructor
{
	controller = owner;
	settings_file = "client_settings.ini";
	enabled = true;
	public_name = false;
	allow_join = true;
	draft_enabled = enabled;
	draft_public_name = public_name;
	draft_allow_join = allow_join;
	initialized = false;
	initialization_checked = false;
	published = false;
	application_id = "";
	status_text = "Discord activity is unavailable in this build.";
	last_snapshot = "";
	last_session = "";
	desired_context = "";
	update_generation = 0;
	session_started = jonnil_presence_unix_time();
	next_update = 0;
	pending_update = false;
	update_deadline = 0;
	visibility_socket = noone;
	visibility_id = noone;
	visibility_value = -1;
	visibility_retry = 0;
	pending_join = "";
	join_feedback = "";
	join_focus = 0;
	options_index = 0;
	options_due = 0;
	link_feedback = "";
	clipboard_pending = false;
	handoff = new jonnil_presence_handoff();
	handoff_client_mode = controller.is_client;

	try
	{
		if (file_exists(settings_file))
		{
			ini_open(settings_file);
			enabled = ini_read_real("presence", "discord_activity", 1) == 1;
			public_name = ini_read_real("presence", "public_name", 0) == 1;
			allow_join = ini_read_real("presence", "allow_join", 1) == 1;
			ini_close();
		}
	}
	catch(settings_error) { try { ini_close(); } catch(close_error) {} }
	draft_enabled = enabled;
	draft_public_name = public_name;
	draft_allow_join = allow_join;

	begin_draft = function()
	{
		draft_enabled = enabled;
		draft_public_name = public_name;
		draft_allow_join = allow_join;
		options_index = 0;
		link_feedback = "";
	}

	/* A permission or session transition revokes join data before ordinary update throttling */
	clear_activity = function()
	{
		update_generation++;
		pending_update = false;
		published = false;
		last_snapshot = "";
		desired_context = "";
		next_update = 0;
		if (initialized) discord_social_client_clear_rich_presence();
	}

	finish_draft = function(apply_changes)
	{
		if (!apply_changes) { begin_draft(); return; }
		if (enabled != draft_enabled || allow_join != draft_allow_join) clear_activity();
		enabled = draft_enabled;
		public_name = draft_public_name;
		allow_join = draft_allow_join;
		try
		{
			ini_open(settings_file);
			ini_write_real("presence", "discord_activity", enabled ? 1 : 0);
			ini_write_real("presence", "public_name", public_name ? 1 : 0);
			ini_write_real("presence", "allow_join", allow_join ? 1 : 0);
			ini_close();
		}
		catch(settings_error)
		{
			try { ini_close(); } catch(close_error) {}
			debug_error("Could not save activity sharing settings.");
		}
		last_snapshot = "";
		next_update = 0;
		visibility_value = -1;
	}

	/// @description Accept only this game's public destination and supported gameplay protocols
	queue_join = function(raw_target)
	{
		if (jonnil_presence_public_join_protocol(raw_target) == 0)
		{
			pending_join = "";
			join_feedback = "This invitation is invalid or needs a different game version.";
			return false;
		}
		/* The secret is a public locator. Existing server admission still checks capacity and compatibility */
		pending_join = "public";
		join_focus = 0;
		join_feedback = "";
		return true;
	}

	/// @description Resolve the public key to the authored native or browser route
	join_public_server = function()
	{
		var target = os_browser == browser_not_a_browser
			? "online.jonnil.games:28080" : PUBLIC_WSS_ADDRESS;
		pending_join = "";
		if (!instance_exists(controller)) return false;
		controller.options_screen_open = false;
		controller.information_screen_open = false;
		return controller.network_start_direct_client_mode(target);
	}

	/// @description Send name consent only after the server assigns this connection a player slot
	sync_visibility = function()
	{
		var client = scr_get_client();
		if (!controller.is_client || client.singleplayer_mode || client.ID == noone
		|| client.gameplay_protocol_version < 4)
		{
			visibility_socket = noone;
			visibility_id = noone;
			visibility_value = -1;
			return;
		}
		var value = public_name ? 1 : 0;
		if (visibility_socket == client.socket && visibility_id == client.ID && visibility_value == value) return;
		if (current_time < visibility_retry) return;
		visibility_retry = current_time + 1000;
		var net = scr_get_network();
		net.start(N_PRESENCE_VISIBILITY, client.ID);
		net.write(buffer_u8, PUBLIC_PRESENCE_PROTOCOL_VERSION);
		net.write(buffer_u8, value);
		if (net.send_server() > 0)
		{
			visibility_socket = client.socket;
			visibility_id = client.ID;
			visibility_value = value;
		}
	}

	initialize_discord = function()
	{
		if (initialization_checked || !enabled || !controller.is_client) return;
		initialization_checked = true;
		if (os_browser != browser_not_a_browser) return;
		try
		{
			if (!__GMDiscordSocial_is_available()) return;
			application_id = string_trim(string(extension_get_option_value("GMDiscordSocial", "application_id")));
			if (string_length(application_id) < 17 || string_length(application_id) > 20) return;
			for (var index = 1; index <= string_length(application_id); index++)
				if (string_pos(string_char_at(application_id, index), "0123456789") == 0) return;
			if (int64(application_id) <= 0) return;
			discord_social_init();
			initialized = true;
			discord_social_client_set_application_id(int64(application_id));
			discord_social_client_set_activity_join_callback(method(self, function(join_secret)
			{
				queue_join(join_secret);
			}));
			/* The IDE Runner is a build tool. Register only the installed game's executable */
			if (os_type == os_windows)
			{
				var executable = ExecutableFromSelf();
				if (jonnil_presence_join_executable_is_installed(executable) && file_exists(executable))
					discord_social_client_register_launch_command(int64(application_id), chr(34) + executable + chr(34));
			}
			status_text = "Waiting for Discord.";
		}
		catch(init_error)
		{
			status_text = "Discord activity is unavailable. You can keep playing.";
			debug_error("Discord initialization failed: " + scr_debug_export_exception_text(init_error));
			jonnil_discord_extension_finalize();
		}
	}

	activity_snapshot = function()
	{
		var client = scr_get_client();
		var active = controller.is_client && client.ID != noone && !client.singleplayer_mode;
		var state = "In the menus";
		var details = "Choosing what to play";
		var count = 0;
		var capacity = max(1, client.server_max_players);
		var public_session = false;
		var session = "menus";
		if (controller.is_singleplayer || client.singleplayer_mode)
		{
			details = "Playing offline";
			state = "Singleplayer";
			session = "offline";
		}
		else if (client.connect_pending || controller.client_dns_pending)
		{
			details = "Connecting to a server";
			state = "Joining";
			session = "connecting";
		}
		else if (active)
		{
			var roster = scr_get_player_controller().players;
			for (var index = 0; index < array_length(roster); index++)
				if (is_struct(roster[index])) count++;
			var address = string_lower(string_trim(client.connect_address));
			public_session = address == "online.jonnil.games:28080" || address == string_lower(PUBLIC_WSS_ADDRESS);
			session = "server:" + address;
			var drawing = scr_get_drawing();
			var ready = variable_struct_exists(drawing, "client_history_sync_complete") && drawing.client_history_sync_complete;
			details = ready ? "Playing online" : "Receiving the shared canvas";
			state = public_session ? "Public server" : "Online session";
			var chat = scr_get_chat();
			if (ready && client.ID < array_length(chat.afk_active) && chat.afk_active[client.ID]) details = "Away from keyboard";
			public_session = public_session && ready && allow_join && count < capacity && !client.server_shutdown_received;
		}
		if (session != last_session)
		{
			last_session = session;
			session_started = jonnil_presence_unix_time();
		}
		return {details: details, state: state, count: count, capacity: capacity, joinable: public_session, active: active,
			protocol: client.gameplay_protocol_version};
	}

	update = function()
	{
		if (!instance_exists(controller)) return;
		/* A dedicated server must not claim invitations intended for a playing client */
		if (handoff_client_mode != controller.is_client)
		{
			handoff.close();
			handoff_client_mode = controller.is_client;
			if (handoff_client_mode) handoff = new jonnil_presence_handoff();
		}
		if (handoff_client_mode)
		{
			var handoff_result = handoff.update(pending_join);
			if (handoff_result.received_target != "" && queue_join(handoff_result.received_target)) handoff.acknowledge_received();
			if (handoff_result.forwarded)
			{
				pending_join = "";
				game_end();
				return;
			}
		}
		if (clipboard_pending && os_browser != browser_not_a_browser)
		{
			var copy_status = html5_diag_copy_status();
			if (copy_status == 2 || copy_status < 0)
			{
				clipboard_pending = false;
				link_feedback = copy_status == 2 ? "Public join link copied." : "Your browser couldn't copy the link. Open the online page to copy it.";
			}
		}
		sync_visibility();
		initialize_discord();
		if (!initialized) return;
		try
		{
			discord_social_run_callbacks();
			if (!enabled || !controller.is_client)
			{
				if (published || pending_update || last_snapshot != "") clear_activity();
				status_text = enabled ? "Discord activity is paused while hosting." : "Discord activity is off.";
				return;
			}
			var snapshot = activity_snapshot();
			var context = last_session + "|" + string(snapshot.joinable);
			if (context != desired_context)
			{
				clear_activity();
				desired_context = context;
			}
			if (pending_update)
			{
				if (current_time < update_deadline) return;
				update_generation++;
				pending_update = false;
				last_snapshot = "";
				status_text = "Discord isn't responding. You can keep playing.";
			}
			var key = json_stringify(snapshot);
			if (current_time < next_update) return;
			if (key == last_snapshot && current_time < next_update + 45000) return;
			var activity = new DiscordActivity();
			activity.type = DiscordActivityTypes.Playing;
			activity.details = snapshot.details;
			activity.state = snapshot.state;
			activity.timestamps = new DiscordActivityTimestamps();
			activity.timestamps.start = session_started;
			activity.supported_platforms = DiscordActivityGamePlatforms.Desktop;
			if (snapshot.active)
			{
				activity.party = new DiscordActivityParty();
				activity.party.activity_party_id = snapshot.joinable ? "jonnil-public" : "jonnil-session-" + string(session_started);
				activity.party.privacy = snapshot.joinable ? DiscordActivityPartyPrivacy.Public : DiscordActivityPartyPrivacy.Private;
				activity.party.current_size = max(1, snapshot.count);
				activity.party.max_size = max(activity.party.current_size, snapshot.capacity);
			}
			if (snapshot.joinable)
			{
				activity.secrets = new DiscordActivitySecrets();
				activity.secrets.join = "jo1:public:" + string(snapshot.protocol);
			}
			/* Discord RPC rejects custom buttons together with join secrets.
			Joinable sessions use Discord's join action instead of the website button */
			if (!snapshot.joinable)
			{
				var button = new DiscordActivityButton();
				button.label = "Visit Jonnil Games";
				button.url = "https://jonnil.games/";
				activity.buttons = [button];
			}
			last_snapshot = key;
			next_update = current_time + 15000;
			pending_update = true;
			update_deadline = current_time + 10000;
			update_generation++;
			/* Bind immutable request context rather than borrowing mutable state or uncaptured locals */
			var callback_service = self;
			var completion = { service: callback_service, generation: update_generation, context_key: desired_context,
				activity_details: snapshot.details, activity_joinable: snapshot.joinable };
			discord_social_client_update_rich_presence(activity, method(completion, function(result)
			{
				var state = service;
				if (generation != state.update_generation)
				{
					/* A late update from an old session must not restore its join secret */
					if (state.initialized && (context_key != state.desired_context || !state.enabled))
					{
						discord_social_client_clear_rich_presence();
						state.last_snapshot = "";
						state.next_update = 0;
					}
					return;
				}
				state.pending_update = false;
				if (is_struct(result) && result.successful)
				{
					if (!state.published) debug_log("Discord activity connected.");
					state.published = true;
					state.status_text = "Discord activity is connected.";
				}
				else
				{
					state.last_snapshot = "";
					state.status_text = "Discord isn't available. You can keep playing.";
					if (is_struct(result)) debug_error("Discord activity update failed (" + activity_details
						+ ", joinable=" + string(activity_joinable) + "): type=" + string(result.type)
						+ ", code=" + string(result.error_code) + ", status=" + string(result.status) + ", error=" + string(result.error));
				}
			}));
		}
		catch(update_error)
		{
			pending_update = false;
			next_update = current_time + 30000;
			status_text = "Discord activity is unavailable. You can keep playing.";
			debug_error("Discord activity update failed: " + scr_debug_export_exception_text(update_error));
		}
	}

	join_rect = function()
	{
		var width = min(600, display_get_gui_width() - 24);
		var height = min(290, display_get_gui_height() - 24);
		return {x: (display_get_gui_width() - width) * 0.5, y: (display_get_gui_height() - height) * 0.5, w: width, h: height};
	}

	update_join_input = function()
	{
		if (pending_join == "" || handoff.waiting) return false;
		var rect = join_rect();
		var mx = scr_gui_mouse_x(0);
		var my = scr_gui_mouse_y(0);
		var pressed = mouse_check_button_pressed(mb_left);
		var join_hover = controller.point_in_rect(mx, my, rect.x + 20, rect.y + rect.h - 68, rect.x + rect.w * 0.5 - 5, rect.y + rect.h - 24);
		var cancel_hover = controller.point_in_rect(mx, my, rect.x + rect.w * 0.5 + 5, rect.y + rect.h - 68, rect.x + rect.w - 20, rect.y + rect.h - 24);
		var gamepad = gamepad_is_connected(0);
		if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right)
		|| (gamepad && (gamepad_button_check_pressed(0, gp_padl) || gamepad_button_check_pressed(0, gp_padr)))) join_focus = 1 - join_focus;
		if (keyboard_check_pressed(vk_escape) || (pressed && cancel_hover) || (gamepad && gamepad_button_check_pressed(0, gp_face2))) pending_join = "";
		else if (pressed && join_hover) join_public_server();
		else if (keyboard_check_pressed(vk_enter) || (gamepad && gamepad_button_check_pressed(0, gp_face1)))
		{
			if (join_focus == 0) join_public_server(); else pending_join = "";
		}
		return true;
	}

	draw_join_prompt = function()
	{
		if (pending_join == "" || handoff.waiting) return false;
		var rect = join_rect();
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(8, 9, 12));
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
		draw_set_colour(make_color_rgb(24, 27, 33));
		draw_rectangle(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, false);
		draw_set_halign(fa_center);
		draw_set_valign(fa_top);
		draw_set_colour(c_white);
		scr_render_text(rect.x + rect.w * 0.5, rect.y + 20, "Join Jonnil Online?", 25, rect.w - 40);
		draw_set_halign(fa_left);
		scr_render_text_wrapped(rect.x + 20, rect.y + 72,
			"Join the public server using your saved player name. This leaves your current session. If you're hosting, your local server will close.", 17, rect.w - 40, 4);
		scr_draw_menu_button(rect.x + 20, rect.y + rect.h - 68, rect.w * 0.5 - 25, 44, "Join", false, join_focus == 0, true, false, false, 18);
		scr_draw_menu_button(rect.x + rect.w * 0.5 + 5, rect.y + rect.h - 68, rect.w * 0.5 - 25, 44, "Cancel", false, join_focus == 1, true, true, false, 18);
		draw_set_halign(fa_left);
		return true;
	}

	options_rows = function()
	{
		return [
			"Discord activity: " + (draft_enabled ? "On" : "Off"),
			"Show my name outside the game: " + (draft_public_name ? "On" : "Off"),
			"Let Discord friends join: " + (draft_allow_join ? "On" : "Off"),
			"See who's online",
			"Copy public server join link",
			"Enable installed game join links"
		];
	}

	activate_option = function(index)
	{
		switch (index)
		{
			case 0: draft_enabled = !draft_enabled; break;
			case 1: draft_public_name = !draft_public_name; break;
			case 2: draft_allow_join = !draft_allow_join; break;
			case 3: url_open("https://online.jonnil.games/online"); break;
			case 4:
				var link = "https://online.jonnil.games/join?server=public&protocol=" + string(scr_get_client().gameplay_protocol_version);
				if (os_browser == browser_not_a_browser) { clipboard_set_text(link); link_feedback = "Public join link copied."; }
				else { html5_diag_copy_text(link); clipboard_pending = true; link_feedback = "Copying public join link..."; }
				break;
			case 5:
				link_feedback = jonnil_presence_register_join_links()
					? "Installed game join links are enabled."
					: "Join link registration needs an installed desktop build.";
				break;
		}
	}

	/// @description Handle Sharing without changing the other Options pages' input flow
	options_update_input = function()
	{
		var ctrl = controller;
		if (ctrl.options_guidance_open) return false;
		var mx = scr_gui_mouse_x(0);
		var my = scr_gui_mouse_y(0);
		var pressed = mouse_check_button_pressed(mb_left);
		var social_x = ctrl.options_presence_tab_x;
		var over_tab = ctrl.options_point_in_rect(mx, my, social_x, ctrl.options_tab_y, ctrl.options_tab_width, ctrl.options_tab_height);
		if (ctrl.options_tab != "presence")
		{
			if (!over_tab) return false;
			ctrl.options_hover = "presence_tab";
			if (pressed) { ctrl.options_switch_tab("presence"); return true; }
			return false;
		}
		var tabs_x = [ctrl.options_display_tab_x, ctrl.options_appearance_tab_x, ctrl.options_performance_tab_x, ctrl.options_diagnostics_tab_x, social_x];
		var tabs = ["display", "appearance", "performance", "diagnostics", "presence"];
		for (var tab_index = 0; tab_index < array_length(tabs); tab_index++)
			if (pressed && ctrl.options_point_in_rect(mx, my, tabs_x[tab_index], ctrl.options_tab_y, ctrl.options_tab_width, ctrl.options_tab_height))
			{ ctrl.options_switch_tab(tabs[tab_index]); return true; }
		var rows = options_rows();
		var top = ctrl.options_panel_y + 116;
		var row_step = min(49, (ctrl.options_apply_y - top - 74) / array_length(rows));
		ctrl.options_hover = over_tab ? "presence_tab" : "";
		for (var index = 0; index < array_length(rows); index++)
		{
			if (ctrl.options_point_in_rect(mx, my, ctrl.options_hue_x, top + index * row_step, ctrl.options_hue_width, row_step - 5))
			{
				ctrl.options_hover = "presence_" + string(index);
				if (pressed) { options_index = index; activate_option(index); return true; }
			}
		}
		if (pressed && ctrl.options_point_in_rect(mx, my, ctrl.options_apply_x, ctrl.options_apply_y, ctrl.options_apply_width, ctrl.options_apply_height)) { ctrl.options_close(true); return true; }
		if (pressed && ctrl.options_point_in_rect(mx, my, ctrl.options_cancel_x, ctrl.options_cancel_y, ctrl.options_cancel_width, ctrl.options_cancel_height)) { ctrl.options_close(false); return true; }
		var pad = gamepad_is_connected(0);
		if (keyboard_check_pressed(vk_escape) || (pad && gamepad_button_check_pressed(0, gp_face2))) { ctrl.options_close(false); return true; }
		var tab_move = keyboard_check_pressed(vk_pagedown) - keyboard_check_pressed(vk_pageup);
		if (pad) tab_move += gamepad_button_check_pressed(0, gp_shoulderr) - gamepad_button_check_pressed(0, gp_shoulderl);
		if (tab_move != 0) { ctrl.options_cycle_tab(tab_move); return true; }
		var move = keyboard_check_pressed(vk_down) - keyboard_check_pressed(vk_up);
		if (keyboard_check_pressed(vk_tab)) move = keyboard_check(vk_shift) ? -1 : 1;
		if (pad) move += gamepad_button_check_pressed(0, gp_padd) - gamepad_button_check_pressed(0, gp_padu);
		if (move != 0) options_index = (options_index + sign(move) + 9) mod 9;
		ctrl.options_focus = options_index == 6 ? "apply" : (options_index == 7 ? "cancel" : (options_index == 8 ? "tabs" : "presence_" + string(options_index)));
		if (options_index == 8 && (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right)))
		{ ctrl.options_cycle_tab(keyboard_check_pressed(vk_right) ? 1 : -1); return true; }
		var accept = keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space) || (pad && gamepad_button_check_pressed(0, gp_face1));
		if (accept)
		{
			if (options_index < 6) activate_option(options_index);
			else if (options_index == 6) ctrl.options_close(true);
			else if (options_index == 7) ctrl.options_close(false);
			else ctrl.options_cycle_tab(1);
		}
		return true;
	}

	draw_options = function()
	{
		var ctrl = controller;
		var rows = options_rows();
		var top = ctrl.options_panel_y + 116;
		var row_step = min(49, (ctrl.options_apply_y - top - 74) / array_length(rows));
		for (var index = 0; index < array_length(rows); index++)
			scr_draw_menu_button(ctrl.options_hue_x, top + index * row_step, ctrl.options_hue_width, row_step - 5, rows[index], ctrl.options_hover == "presence_" + string(index), options_index == index, true, index >= 3, false, 16);
		draw_set_halign(fa_left);
		draw_set_colour(c_ltgray);
		var text_y = top + array_length(rows) * row_step + 2;
		scr_render_text_wrapped(ctrl.options_hue_x, text_y, "Names are hidden outside the game by default. Apply saves sharing choices. Discord also follows your activity privacy settings.", 14, ctrl.options_hue_width, 3);
		draw_set_colour(make_color_rgb(170, 210, 225));
		scr_render_text(ctrl.options_hue_x, ctrl.options_apply_y - 24, link_feedback != "" ? link_feedback : (join_feedback != "" ? join_feedback : (enabled ? status_text : "Discord activity is off.")), 14, ctrl.options_hue_width);
	}
}
