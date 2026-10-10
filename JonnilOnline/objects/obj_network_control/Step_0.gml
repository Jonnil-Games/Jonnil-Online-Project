/// @description Advance hosted networking and route menu, modal, and gameplay input

/* Reset shared text-input bookkeeping for this Step before any screen consumes
keyboard input. Update the role caption and performance state before modal returns */
scr_text_input_begin_step();
network_update_window_caption(network_window_role);
html5_performance.update();

/* Keep hosted server maintenance running in both console and Host & Play modes.
Menus must not pause authoritative networking, timeouts or synchronization */
if (is_hosting_server)
{
	network_update_hosted_server();
}

/* Only the client view advances pending outbound connections here.
Dedicated server mode has no visible client connection to finish */
if (is_client)
{
	/* Borrow the client session that owns asynchronous connection startup */
	var pending_client = scr_get_client();

	/* An available pending-connect method advances its status/deadline checks.
	Missing client support skips this maintenance without accessing absent state */
	if (is_struct(pending_client) && variable_struct_exists(pending_client, "update_pending_connect"))
	{
		pending_client.update_pending_connect();
	}
}

/* A pending join DNS request expires on the current_time millisecond clock.
Clear its identity, deadline and saved admin intent before showing failure so
late HTTP completion cannot resume this timed-out join */
if (client_dns_pending && current_time >= client_dns_deadline)
{
	client_dns_pending = false;
	client_dns_deadline = 0;
	client_dns_request_id = noone;
	client_dns_pending_admin_intent = false;
	client_join_status = "Join failed.";
	client_join_error = "Hostname lookup timed out. Check the address and try again.";
}

/* Start with history maintenance not yet performed. Run incoming transfer/decode
maintenance before UI can capture input and return early. Set the flag only when
that maintenance runs so later drawing updates do not repeat the same work */
var drawing_sync_maintenance_done = false;

/* Perform client canvas transfer/decode maintenance before any UI returns early.
Server-only view skips this client history work */
if (is_client)
{
	/* Borrow the drawing service responsible for incoming client history synchronization */
	var drawing_sync_maintenance = scr_get_drawing();

	/* Run history maintenance only when its drawing service and method exist.
	Absent support keeps the completion flag false for later drawing processing */
	if (is_struct(drawing_sync_maintenance)
	&& variable_struct_exists(drawing_sync_maintenance, "update_client_history_sync_maintenance"))
	{
		drawing_sync_maintenance.update_client_history_sync_maintenance();
		drawing_sync_maintenance_done = true;
	}
}

/* Borrow the folder-confirmation modal. open_folder_modal_blocks_input records
whether its input update claims this Step, giving that dialog priority over menus
and gameplay without stopping network maintenance */
var open_folder_modal = scr_get_open_folder_modal();
var open_folder_modal_blocks_input = open_folder_modal.update_input();

/* A newly consumed modal release request cancels active zoom entry and movement.
This prevents held input from continuing in the world while the folder prompt
captures keyboard/mouse interaction */
if (open_folder_modal.consume_input_release())
{
	network_camera_cancel_zoom_input();

	/* Only the client view owns local player movement that needs releasing.
	The dedicated server skips this client cleanup */
	if (is_client)
	{
		/* Borrow the client session whose movement-release method clears held actions */
		var folder_modal_client = scr_get_client();

		/* Release movement through the available client capability. Missing client or
		method support skips the call rather than reading absent state */
		if (is_struct(folder_modal_client)
		&& variable_struct_exists(folder_modal_client, "release_local_movement"))
		{
			folder_modal_client.release_local_movement();
		}
	}
}

/* F7 toggles the text diagnostics only when the folder modal has not claimed input.
Invert the current flag and log ON for enabled or OFF for disabled */
if (!open_folder_modal_blocks_input
&& keyboard_check_pressed(vk_f7))
{
	global.text_debug_overlay = !global.text_debug_overlay;
	debug_log("Text debug overlay: " + (global.text_debug_overlay ? "ON" : "OFF"));
}

/* F6 toggles canvas diagnostics only outside folder-modal input capture.
Leave the drawing overlay unchanged when that modal owns the key */
if (!open_folder_modal_blocks_input
&& keyboard_check_pressed(vk_f6))
{
	/* Borrow drawing state to access its diagnostic overlay flag */
	var drawing_debug_toggle = scr_get_drawing();

	/* Only an available drawing overlay flag can be toggled. Invert its current value
	and report ON/OFF, otherwise leave diagnostic state unchanged */
	if (is_struct(drawing_debug_toggle)
	&& variable_struct_exists(drawing_debug_toggle, "debug_overlay_enabled"))
	{
		drawing_debug_toggle.debug_overlay_enabled = !drawing_debug_toggle.debug_overlay_enabled;
		debug_log("Drawing debug overlay: " + (drawing_debug_toggle.debug_overlay_enabled ? "ON" : "OFF"));
	}
}

/* F8 toggles the forced-white text diagnostic outside folder-modal input capture.
The inverted flag selects ON/OFF in the diagnostic message */
if (!open_folder_modal_blocks_input
&& keyboard_check_pressed(vk_f8))
{
	global.text_debug_force_white = !global.text_debug_force_white;
	debug_log("Text force white: " + (global.text_debug_force_white ? "ON" : "OFF"));
}

/* F11 requests the opposite fullscreen state only outside managed dedicated-server
mode. Catch unsupported window changes so a failed toggle is logged without
stopping Step processing */
if (!managed_dedicated_server
&& keyboard_check_pressed(vk_f11))
{
	try
	{
		window_set_fullscreen(!window_get_fullscreen());
	}
	catch(e)
	{
		debug_error("Could not toggle fullscreen: " + string(e.message));
	}
}

/* While the folder modal claims input, reset held-Escape exit progress and bypass
other screens/gameplay. Client watchdog/camera maintenance still runs before returning */
if (open_folder_modal_blocks_input)
{
	escape_exit_hold_reset();

	/* The client view keeps its camera and connection health advancing under the modal.
	The dedicated server has no client camera to update */
	if (is_client)
	{
		/* Borrow the active client for connection-health maintenance beneath the folder modal */
		var folder_modal_active_client = scr_get_client();

		/* An online client with watchdog support checks connection health while input is
		blocked. Singleplayer has no remote connection watchdog to advance */
		if (!is_singleplayer
		&& is_struct(folder_modal_active_client)
		&& variable_struct_exists(folder_modal_active_client, "update_connection_watchdog"))
		{
			folder_modal_active_client.update_connection_watchdog();
		}
		network_camera_update();
	}
	return;
}

/* An open Options screen receives this Step and returns before the mode menu or
world can also consume its keys */
if (options_screen_open)
{
	options_update_input();
	return;
}

/* The open What's New screen owns input for this Step. Update it and stop routing
before another screen interprets the same actions */
if (whats_new_screen_open)
{
	whats_new_update_input();
	return;
}

/* An open Information screen receives input exclusively, preserving the maintenance
already performed at the start of this Step */
if (information_screen_open)
{
	information_update_input();
	return;
}

#region /* Network Mode Selection */
/* The network mode chooser owns input while visible. Handle its active page and
return before server selection or gameplay can react to the same actions */
if (network_mode_screen)
{
	network_mode_update_layout();

	/* Sample pointer x/y in GUI pixels and a fresh left-click for menu hit testing.
	gamepad_action starts empty and gamepad_move starts zero, meaning no activation
	or navigation has been requested in this Step */
	var mouse_x_gui = device_mouse_x_to_gui(0);
	var mouse_y_gui = device_mouse_y_to_gui(0);
	var mouse_pressed = mouse_check_button_pressed(mb_left);
	var gamepad_action = "";
	var gamepad_move = 0;

	/* A connected first gamepad may navigate after the current_time repeat deadline.
	Before that deadline, retain the selected option to throttle held directions */
	if (gamepad_is_connected(0)
	&& current_time >= network_mode_gamepad_navigation_due)
	{
		/* gamepad_up/down combine D-pad presses with vertical-stick deflection beyond
		65 percent. Each Boolean identifies a requested menu direction, including held input */
		var gamepad_up = gamepad_button_check(0, gp_padu)
			|| gamepad_axis_value(0, gp_axislv) <= -0.65;
		var gamepad_down = gamepad_button_check(0, gp_padd)
			|| gamepad_axis_value(0, gp_axislv) >= 0.65;

		/* Navigate only when exactly one vertical direction is requested. Opposing inputs
		cancel. Up chooses the previous option and down the next, then wait 180 ms before
		another held-direction move */
		if (gamepad_up != gamepad_down)
		{
			gamepad_move = gamepad_up ? -1 : 1;
			network_mode_gamepad_navigation_due = current_time + 180;
		}
	}

	/* The host submenu exposes console hosting, Host & Play and Back.
	Finish this page before interpreting the main chooser controls below */
	if (network_mode_page == "host")
	{
		/* server_hover, host_play_hover and back_hover each test their own GUI button
		rectangle. They control pointer activation and the hover highlight on this host page */
		var server_hover = mouse_x_gui >= network_mode_server_button_x
			&& mouse_x_gui <= network_mode_server_button_x + network_mode_server_button_width
			&& mouse_y_gui >= network_mode_server_button_y
			&& mouse_y_gui <= network_mode_server_button_y + network_mode_server_button_height;
		var host_play_hover = mouse_x_gui >= network_mode_host_play_button_x
			&& mouse_x_gui <= network_mode_host_play_button_x + network_mode_host_play_button_width
			&& mouse_y_gui >= network_mode_host_play_button_y
			&& mouse_y_gui <= network_mode_host_play_button_y + network_mode_host_play_button_height;
		var back_hover = mouse_x_gui >= network_mode_back_button_x
			&& mouse_x_gui <= network_mode_back_button_x + network_mode_back_button_width
			&& mouse_y_gui >= network_mode_back_button_y
			&& mouse_y_gui <= network_mode_back_button_y + network_mode_back_button_height;

		/* Choose the hovered host-page label in button priority order: Server, Host & Play,
		then Back. Empty text clears the highlight when no rectangle contains the pointer */
		network_mode_hover_button = server_hover ? "server" : (host_play_hover ? "host_play" : (back_hover ? "back" : ""));

		/* The host-page gamepad order is Server, Host & Play, then Back.
		This local array defines the wraparound navigation order */
		var host_gamepad_options = ["server", "host_play", "back"];

		/* A requested gamepad move updates host-page focus. Zero movement leaves the
		existing selection unchanged */
		if (gamepad_move != 0)
		{
			/* Begin the focus lookup at option zero as a fallback if the saved focus no longer
			matches this host page */
			var host_gamepad_index = 0;

			/* Search the three zero-based host options until the current focus is found.
			Stop at its first match, then wrap the requested move within this option count */
			for (var host_option_index = 0; host_option_index < array_length(host_gamepad_options); host_option_index++)
			{
				/* A matching option supplies the current gamepad index. Stop searching so the
				subsequent move advances relative to this selection */
				if (host_gamepad_options[host_option_index] == network_mode_gamepad_focus)
				{
					host_gamepad_index = host_option_index;
					break;
				}
			}
			host_gamepad_index = (host_gamepad_index + gamepad_move + array_length(host_gamepad_options)) mod array_length(host_gamepad_options);
			network_mode_gamepad_focus = host_gamepad_options[host_gamepad_index];
		}

		/* The first gamepad confirm button activates its current host-page focus only when
		a controller is connected. Otherwise no gamepad activation is recorded */
		if (gamepad_is_connected(0)
		&& gamepad_button_check_pressed(0, gp_face1))
		{
			gamepad_action = network_mode_gamepad_focus;
		}

		/* accept_pressed records Enter or Space as keyboard confirmation for the currently
		focused host-page button */
		var accept_pressed = keyboard_check_pressed(vk_enter)
			|| keyboard_check_pressed(vk_space);

		/* Start console hosting from its pointer click, S shortcut, focused keyboard
		confirmation or matching gamepad action. Return after the mode transition so
		this input is not reused by another screen */
		if ((server_hover && mouse_pressed)
		|| keyboard_check_pressed(ord("S"))
		|| (accept_pressed && network_mode_gamepad_focus == "server")
		|| gamepad_action == "server")
		{
			/* Persist a valid current username before hosting. Invalid names are left unsaved
			because console-only hosting does not require a playable local identity */
			if (client_username_is_ready())
			{
				client_save_username();
			}
			network_start_server_mode();
			return;
		}

		/* A Host & Play click, H shortcut or focused keyboard/gamepad confirmation starts
		local hosting with a playable client and then ends this menu Step */
		if ((host_play_hover && mouse_pressed)
		|| keyboard_check_pressed(ord("H"))
		|| (accept_pressed && network_mode_gamepad_focus == "host_play")
		|| gamepad_action == "host_play")
		{
			network_start_host_play_mode();
			return;
		}

		/* Back activation or a supported Escape/B/cancel input returns to the main chooser.
		Clear hover state, select Host for gamepad focus and reset held-Escape progress
		so this back action does not also exit the application */
		if ((back_hover && mouse_pressed)
		|| (accept_pressed && network_mode_gamepad_focus == "back")
		|| gamepad_action == "back"
		|| keyboard_check_pressed(vk_escape)
		|| keyboard_check_pressed(ord("B"))
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face2)))
		{
			escape_exit_hold_reset();
			network_mode_page = "main";
			network_mode_status = "Host a server or join as a client.";
			network_mode_hover_button = "";
			network_mode_gamepad_focus = "host";
			return;
		}

		/* No host-page action fired. End this Step on the host submenu so its remaining
		input is not interpreted as main-page or gameplay actions */
		return;
	}

	/* username_hover tests the name field. host_hover/client_hover/singleplayer_hover
	identify mode buttons, while options_hover/information_hover identify help screens.
	quit_hover additionally requires Quit to be available and performance_warning_hover
	requires its warning link to be visible. All bounds use the current GUI-pixel layout */
	var username_hover = mouse_x_gui >= network_mode_username_input_x
		&& mouse_x_gui <= network_mode_username_input_x + network_mode_username_input_width
		&& mouse_y_gui >= network_mode_username_input_y
		&& mouse_y_gui <= network_mode_username_input_y + network_mode_username_input_height;
	var host_hover = mouse_x_gui >= network_mode_host_button_x
		&& mouse_x_gui <= network_mode_host_button_x + network_mode_host_button_width
		&& mouse_y_gui >= network_mode_host_button_y
		&& mouse_y_gui <= network_mode_host_button_y + network_mode_host_button_height;
	var client_hover = mouse_x_gui >= network_mode_client_button_x
		&& mouse_x_gui <= network_mode_client_button_x + network_mode_client_button_width
		&& mouse_y_gui >= network_mode_client_button_y
		&& mouse_y_gui <= network_mode_client_button_y + network_mode_client_button_height;
	var singleplayer_hover = mouse_x_gui >= network_mode_singleplayer_button_x
		&& mouse_x_gui <= network_mode_singleplayer_button_x + network_mode_singleplayer_button_width
		&& mouse_y_gui >= network_mode_singleplayer_button_y
		&& mouse_y_gui <= network_mode_singleplayer_button_y + network_mode_singleplayer_button_height;
	var options_hover = mouse_x_gui >= network_mode_options_button_x
		&& mouse_x_gui <= network_mode_options_button_x + network_mode_options_button_width
		&& mouse_y_gui >= network_mode_options_button_y
		&& mouse_y_gui <= network_mode_options_button_y + network_mode_options_button_height;
	var quit_hover = network_mode_show_quit
		&& mouse_x_gui >= network_mode_quit_button_x
		&& mouse_x_gui <= network_mode_quit_button_x + network_mode_quit_button_width
		&& mouse_y_gui >= network_mode_quit_button_y
		&& mouse_y_gui <= network_mode_quit_button_y + network_mode_quit_button_height;
	var information_hover = mouse_x_gui >= network_mode_information_button_x
		&& mouse_x_gui <= network_mode_information_button_x + network_mode_information_button_width
		&& mouse_y_gui >= network_mode_information_button_y
		&& mouse_y_gui <= network_mode_information_button_y + network_mode_information_button_height;
	var performance_warning_hover = network_mode_performance_warning_visible
		&& mouse_x_gui >= network_mode_performance_warning_x
		&& mouse_x_gui <= network_mode_performance_warning_x + network_mode_performance_warning_width
		&& mouse_y_gui >= network_mode_performance_warning_y
		&& mouse_y_gui <= network_mode_performance_warning_y + network_mode_performance_warning_height;

	/* A fresh pointer click chooses name-entry focus or clears it.
	Moving the pointer alone does not change which field owns keyboard text */
	if (mouse_pressed)
	{
		/* Clicking inside the username field focuses it and loads its current text into
		the shared keyboard buffer for editing */
		if (username_hover)
		{
			network_mode_focus = "username";
			keyboard_string = client_username;
		}

		/* A click elsewhere leaves name entry. Clear its focus and keyboard buffer so
		menu shortcuts do not become stale username edits */
		else
		{
			network_mode_focus = "";
			keyboard_string = "";
		}
	}

	/* Only the focused username field consumes text. Update through the shared input
	service with its 24-character limit before filtering line breaks and unsupported characters */
	if (network_mode_focus == "username")
	{
		scr_text_input_update("network_username", client_username, 24);

		/* typed_username begins as the current keyboard buffer. Filtering produces the
		candidate name before it replaces the saved in-memory menu text */
		var typed_username = keyboard_string;
		typed_username = string_replace_all(typed_username, "\r", "");
		typed_username = string_replace_all(typed_username, "\n", "");
		typed_username = chat_filter_username_input(typed_username);

		/* Apply only a changed filtered username, avoiding unnecessary field updates.
		Keep the shared buffer aligned with the accepted candidate */
		if (typed_username != client_username)
		{
			client_username = typed_username;
			keyboard_string = client_username;

			/* A name with no validation message restores the normal chooser guidance.
			Invalid input keeps the current status until its validation path supplies feedback */
			if (client_username_validation_message(client_username) == "")
			{
				network_mode_status = "Host a server or join as a client.";
			}
		}
	}

	/* Clear the main-page pointer highlight before choosing the first matching button.
	No matching button leaves the hover key empty */
	network_mode_hover_button = "";

	/* A pointer inside Host highlights the host submenu action */
	if (host_hover)
	{
		network_mode_hover_button = "host";
	}

	/* If Host was not hovered, a pointer inside Client highlights server joining */
	else if (client_hover)
	{
		network_mode_hover_button = "client";
	}

	/* The next pointer alternative selects offline Singleplayer */
	else if (singleplayer_hover)
	{
		network_mode_hover_button = "singleplayer";
	}

	/* A pointer over Options highlights the settings action */
	else if (options_hover)
	{
		network_mode_hover_button = "options";
	}

	/* The visible performance-warning link highlights its guidance action */
	else if (performance_warning_hover)
	{
		network_mode_hover_button = "performance_guidance";
	}

	/* An available Quit button highlights application exit */
	else if (quit_hover)
	{
		network_mode_hover_button = "quit";
	}

	/* The remaining Information button highlights the project information screen */
	else if (information_hover)
	{
		network_mode_hover_button = "information";
	}

	/* Only a connected gamepad needs a main-page focus list and activation check.
	Pointer/keyboard menu handling remains available without it */
	if (gamepad_is_connected(0))
	{
		/* gamepad_options is assigned by warning visibility before navigation uses it.
		Both alternatives include only controls available on this main page */
		var gamepad_options;

		/* A visible performance warning adds its guidance action to gamepad navigation.
		Include Quit only when network_mode_show_quit permits that control */
		if (network_mode_performance_warning_visible)
		{
			gamepad_options = network_mode_show_quit
				? ["host", "client", "singleplayer", "options", "quit", "performance_guidance", "information"]
				: ["host", "client", "singleplayer", "options", "performance_guidance", "information"];
		}

		/* Without a visible warning, omit its guidance action. The Quit setting still
		chooses whether application exit participates in gamepad focus order */
		else
		{
			gamepad_options = network_mode_show_quit
				? ["host", "client", "singleplayer", "options", "quit", "information"]
				: ["host", "client", "singleplayer", "options", "information"];
		}

		/* A nonzero navigation request searches and moves the current main-page focus.
		Zero preserves the existing selection */
		if (gamepad_move != 0)
		{
			/* The focus lookup starts at option zero if the saved focus is absent from the
			current available-controls list */
			var gamepad_focus_index = 0;

			/* Search available main-page options from index zero through the last entry.
			Stop at the current focus before wrapping one move within this list */
			for (var gamepad_option_index = 0; gamepad_option_index < array_length(gamepad_options); gamepad_option_index++)
			{
				/* The matching option identifies the gamepad's current selection and ends lookup.
				The move then starts from that actual position */
				if (gamepad_options[gamepad_option_index] == network_mode_gamepad_focus)
				{
					gamepad_focus_index = gamepad_option_index;
					break;
				}
			}
			gamepad_focus_index = (gamepad_focus_index + gamepad_move + array_length(gamepad_options)) mod array_length(gamepad_options);
			network_mode_gamepad_focus = gamepad_options[gamepad_focus_index];
			network_mode_focus = "";
			keyboard_string = "";
		}

		/* A fresh gamepad confirm press activates the selected main-page option.
		Without that press, keep gamepad_action empty */
		if (gamepad_button_check_pressed(0, gp_face1))
		{
			gamepad_action = network_mode_gamepad_focus;
		}
	}

	/* username_focused records whether typing owns the name field, suppressing letter
	shortcuts that would otherwise trigger modes while the player enters a name */
	var username_focused = network_mode_focus == "username";

	/* Open the host submenu from its pointer/gamepad action or H outside name editing.
	Clear text focus and return so this activation cannot start another mode immediately */
	if ((host_hover && mouse_pressed)
	|| (!username_focused && keyboard_check_pressed(ord("H")))
	|| gamepad_action == "host")
	{
		escape_exit_hold_reset();
		network_mode_page = "host";
		network_mode_status = "Run a server console, or join your own server and play.";
		network_mode_focus = "";
		network_mode_hover_button = "";
		network_mode_gamepad_focus = "server";
		keyboard_string = "";
		return;
	}

	/* Open client joining from its pointer/gamepad action, C outside name editing, or
	Enter. The Enter branch also allows committing the name and proceeding to joining */
	if ((client_hover && mouse_pressed)
	|| (!username_focused && keyboard_check_pressed(ord("C")))
	|| keyboard_check_pressed(vk_enter)
	|| gamepad_action == "client")
	{
		/* A queued direct-connect address bypasses server-list selection and starts that
		specific target. Keep it intact for the direct-mode initializer */
		if (network_pending_direct_connect_address != "")
		{
			network_start_direct_client_mode(network_pending_direct_connect_address);
		}

		/* With no queued target, open normal client server selection instead */
		else
		{
			network_start_client_mode();
		}
		return;
	}

	/* Singleplayer activates from its pointer button or gamepad focus.
	Start its offline session and end this chooser Step */
	if ((singleplayer_hover && mouse_pressed)
	|| gamepad_action == "singleplayer")
	{
		network_start_singleplayer_mode();
		return;
	}

	/* Exit only when Quit is available and explicitly clicked or gamepad-activated.
	Hidden Quit controls cannot end the application through this branch */
	if (network_mode_show_quit
	&& ((quit_hover && mouse_pressed)
		|| gamepad_action == "quit"))
	{
		game_end();
		return;
	}

	/* Open Information from a pointer/gamepad action or I outside username typing.
	Return before other menu actions can consume the same input */
	if ((information_hover && mouse_pressed)
	|| (!username_focused && keyboard_check_pressed(ord("I")))
	|| gamepad_action == "information")
	{
		information_open();
		return;
	}

	/* The performance-guidance link works only while its warning is visible.
	Open the performance Options page and its guidance view, then stop menu routing */
	if (network_mode_performance_warning_visible
	&& ((performance_warning_hover && mouse_pressed)
		|| gamepad_action == "performance_guidance"))
	{
		options_open("performance");
		options_show_guidance(false);
		return;
	}

	/* W opens What's New only outside username editing, preserving typed W characters
	while the name field owns keyboard input */
	if (!username_focused && keyboard_check_pressed(ord("W")))
	{
		whats_new_open();
		return;
	}

	/* Options opens from its pointer/gamepad action or O outside username typing.
	Return after opening so lower-priority modes do not also react */
	if ((options_hover && mouse_pressed)
	|| (!username_focused && keyboard_check_pressed(ord("O")))
	|| gamepad_action == "options")
	{
		options_open();
		return;
	}

	/* The chooser's held-Escape exit helper may end the application only when its
	Quit permission allows it and the hold has completed */
	if (escape_exit_hold_update("mode_quit", network_mode_show_quit))
	{
		game_end();
		return;
	}

	/* The mode chooser has handled this Step even when no action fired.
	Return before server-selection or world input can run behind it */
	return;
}
#endregion /* Network Mode Selection END */

#region /* Server Selection */
/* Client server selection runs only while its join screen is visible.
Other client states and dedicated server view skip this menu region */
if (is_client && client_join_screen)
{
	/* Borrow the client session that owns the join attempt, server discovery and list data */
	var client = scr_get_client();

	/* An assigned logical player ID means joining has completed. Close the selection
	screen/dialog, stop discovery and hide logs before returning to gameplay on a later Step */
	if (client.ID != noone)
	{
		client_join_screen = false;
		client_join_close_dialog();
		client.stop_discovery();
		show_logs = false; /* The debug screen is off by default for the client */
		return;
	}

	/* A new connection failure message becomes visible join feedback once.
	Clear the source message after copying it so later Steps do not repeatedly overwrite status */
	if (client.connect_failed_message != "")
	{
		client_join_error = client.connect_failed_message;
		client_join_status = "Join failed.";
		client.connect_failed_message = "";
	}
	client.send_discovery_request();
	client_join_update_layout();

	/* entries is the current normalized server-list snapshot and row_count its count.
	busy combines pending DNS and connection startup, blocking concurrent list actions */
	var entries = client.build_server_list_entries();
	var row_count = array_length(entries);
	var busy = client_dns_pending || client.connect_pending;

	/* An open direct/add/edit/delete dialog receives input before list navigation.
	Return after its update to keep the background server rows inactive */
	if (client_join_dialog != "")
	{
		client_join_update_dialog();
		return;
	}
	client_join_direct_mode = false;
	client_join_focus = "";
	keyboard_string = "";

	/* first_selectable begins noone because the list may have no server row.
	selectable_count starts zero and counts rows eligible for keyboard/pointer selection */
	var first_selectable = noone;
	var selectable_count = 0;

	/* Visit every zero-based list entry to count selectable servers and remember the
	first eligible row. Headers and other nonselectable rows do not contribute */
	for (var entry_index = 0; entry_index < row_count; entry_index++)
	{
		/* Only selectable entries count as candidate servers. Leave separators and
		noninteractive informational rows outside selection */
		if (entries[entry_index].selectable)
		{
			selectable_count++;

			/* Record the first selectable row only while none has been found, preserving the
			earlier candidate as the fallback for an invalid current selection */
			if (first_selectable == noone) first_selectable = entry_index;
		}
	}

	/* A missing, out-of-bounds or nonselectable current selection falls back to the
	first eligible row. Bounds checks precede the indexed access to avoid reading
	outside a changed server list */
	if (client_join_selected < 0 || client_join_selected >= row_count || !entries[client_join_selected].selectable)
	{
		client_join_selected = first_selectable;
	}

	/* visible_rows converts list height and row height in GUI pixels to whole rows,
	with at least one visible slot. Clamp scrolling so it cannot pass the remaining list */
	var visible_rows = max(1, floor(client_join_list_height / client_join_row_height));
	client_join_scroll = clamp(client_join_scroll, 0, max(0, row_count - visible_rows));

	/* Refresh normal join status only when no explicit join error owns the message.
	A saved-list load failure takes priority, followed by DNS progress, connection
	progress and the selectable-server count */
	if (client_join_error == "")
	{
		client_join_status = client.saved_servers_load_failed ? client.saved_servers_error : (client_dns_pending ? "Resolving " + client_dns_pending_url + "..."
			: (client.connect_pending ? client.connect_status : string(selectable_count) + " server(s) listed. Up/Down selects; Enter joins."));
	}

	/* Sample the current GUI pointer and fresh left-click for server rows/buttons.
	Reset previous hover keys before this Step's hit tests */
	var mouse_x_gui = device_mouse_x_to_gui(0);
	var mouse_y_gui = device_mouse_y_to_gui(0);
	var mouse_pressed = mouse_check_button_pressed(mb_left);
	client_join_hover_button = "";
	client_join_hover_row = noone;
	client_join_button_hover = false;

	/* in_server_list records whether the pointer lies inside the visible list rectangle.
	double_click_join starts false because only a second accepted click within the
	same-row 400 ms window should request joining */
	var in_server_list = mouse_x_gui >= client_join_list_x
		&& mouse_x_gui <= client_join_list_x + client_join_list_width
		&& mouse_y_gui >= client_join_list_y
		&& mouse_y_gui <= client_join_list_y + client_join_list_height;
	var double_click_join = false;

	/* Only a pointer inside the list controls its wheel scrolling and row hit test.
	Wheel input elsewhere must not move server rows */
	if (in_server_list)
	{
		/* Wheel-up moves one row toward the top, clamped at zero */
		if (mouse_wheel_up()) client_join_scroll = max(0, client_join_scroll - 1);

		/* Wheel-down advances one row while keeping the last visible page inside the list */
		if (mouse_wheel_down()) client_join_scroll = min(max(0, row_count - visible_rows), client_join_scroll + 1);

		/* row_under_mouse combines zero-based scroll offset with the pointer's whole-row
		position inside the GUI list */
		var row_under_mouse = client_join_scroll + floor((mouse_y_gui - client_join_list_y) / client_join_row_height);

		/* Only a row within the actual list and current visible page receives hover state.
		Ignore padding below the final row instead of indexing an absent entry */
		if (row_under_mouse >= 0 && row_under_mouse < min(row_count, client_join_scroll + visible_rows))
		{
			client_join_hover_row = row_under_mouse;

			/* Select a clicked row only when it is selectable and no join operation is busy.
			Return action focus to Join, clear prior feedback and record click timing */
			if (entries[row_under_mouse].selectable && mouse_pressed && !busy)
			{
				client_join_selected = row_under_mouse;
				client_join_direct_mode = false;
				client_join_action_focus = "join";
				client_join_error = "";

				/* A repeated click on the same accepted row within 400 current_time milliseconds
				requests joining. Different rows or slower clicks only change selection */
				double_click_join = client_join_last_click_row == row_under_mouse && current_time - client_join_last_click_time < 400;
				client_join_last_click_row = row_under_mouse;
				client_join_last_click_time = current_time;
			}
		}
	}

	/* row_direction is +1 for Down, -1 for Up and zero when neither or both are pressed.
	It controls one wrapped search for the next selectable list entry */
	var row_direction = keyboard_check_pressed(vk_down) - keyboard_check_pressed(vk_up);

	/* Move selection only for a directional press while idle and with at least one
	selectable row. Busy startup or an empty list keeps its current selection */
	if (row_direction != 0 && !busy && first_selectable != noone)
	{
		/* next_row starts at the current selection so the search first considers the
		next row in the requested direction */
		var next_row = client_join_selected;

		/* Search at most one full list cycle, wrapping each candidate index.
		Stop at the first selectable row so headers are skipped without an endless loop */
		repeat (row_count)
		{
			next_row = (next_row + row_direction + row_count) mod row_count;

			/* The first selectable candidate becomes the highlighted server and ends the
			search. Nonselectable entries continue to the next candidate */
			if (entries[next_row].selectable)
			{
				client_join_selected = next_row;
				client_join_action_focus = "join";
				client_join_error = "";
				break;
			}
		}
		client_join_scroll = clamp(client_join_scroll, max(0, client_join_selected - visible_rows + 1), max(0, client_join_selected));
	}

	/* selected_joinable requires a bounded selectable row whose current availability
	permits joining. Join also requires a valid username and idle startup. Edit/Delete
	require a saved-server row and idle startup, leaving official rows protected */
	var selected_joinable = client_join_selected >= 0 && client_join_selected < row_count
		&& entries[client_join_selected].selectable && entries[client_join_selected].joinable;
	client_join_join_enabled = client_username_is_ready() && selected_joinable && !busy;
	client_join_edit_enabled = client_join_selected_saved_index() != noone && !busy;

	/* buttons defines action keys and GUI rectangles for Join, Direct, Add, Edit,
	Delete, Refresh and Back. Their enabled flags enforce the current join/edit/busy
	rules. Back stays available so a pending attempt can still be cancelled */
	var buttons = [
		{ key: "join", x: client_join_button_x, y: client_join_button_y, w: client_join_button_width, enabled: client_join_join_enabled },
		{ key: "direct", x: client_join_direct_button_x, y: client_join_direct_button_y, w: client_join_direct_button_width, enabled: !busy },
		{ key: "add", x: client_join_add_button_x, y: client_join_add_button_y, w: client_join_add_button_width, enabled: !busy },
		{ key: "edit", x: client_join_edit_button_x, y: client_join_edit_button_y, w: client_join_edit_button_width, enabled: client_join_edit_enabled },
		{ key: "delete", x: client_join_delete_button_x, y: client_join_delete_button_y, w: client_join_delete_button_width, enabled: client_join_edit_enabled },
		{ key: "refresh", x: client_join_refresh_button_x, y: client_join_refresh_button_y, w: client_join_refresh_button_width, enabled: !busy },
		{ key: "back", x: client_join_back_button_x, y: client_join_back_button_y, w: client_join_back_button_width, enabled: true }
	];

	/* focus_index starts at the first button if the saved action focus no longer
	matches the current action list */
	var focus_index = 0;

	/* Visit each zero-based button entry to resolve keyboard focus and pointer hover.
	Later Tab handling uses this same order for enabled-button navigation */
	for (var button_index = 0; button_index < array_length(buttons); button_index++)
	{
		/* button is the current action descriptor containing its key, position, width
		and eligibility flag */
		var button = buttons[button_index];

		/* A matching saved focus supplies its index for subsequent Tab navigation */
		if (button.key == client_join_action_focus) focus_index = button_index;

		/* A pointer inside this button's GUI rectangle sets its hover key.
		Enabled state is checked separately before a click changes action focus */
		if (mouse_x_gui >= button.x && mouse_x_gui <= button.x + button.w
		&& mouse_y_gui >= button.y && mouse_y_gui <= button.y + client_join_button_height)
		{
			client_join_hover_button = button.key;

			/* Only a fresh click on an enabled action updates keyboard action focus.
			A disabled hover can display feedback but must not become a clicked selection */
			if (mouse_pressed && button.enabled) client_join_action_focus = button.key;
		}
	}

	/* Tab cycles action focus rather than joining immediately.
	Use Shift to reverse its direction */
	if (keyboard_check_pressed(vk_tab))
	{
		/* tab_direction is -1 with Shift and +1 otherwise, selecting backward or forward
		navigation within the action array */
		var tab_direction = keyboard_check(vk_shift) ? -1 : 1;

		/* Inspect at most one cycle of buttons, wrapping focus and skipping disabled actions.
		The always-enabled Back entry ensures the search has an eligible destination */
		repeat (array_length(buttons))
		{
			focus_index = (focus_index + tab_direction + array_length(buttons)) mod array_length(buttons);

			/* Stop at the first enabled button so keyboard focus cannot land on a blocked action */
			if (buttons[focus_index].enabled) break;
		}
		client_join_action_focus = buttons[focus_index].key;
	}

	/* action starts empty until keyboard, pointer or double-click input supplies an
	activation. The following checks define their precedence for this Step */
	var action = "";

	/* Enter activates the currently focused list action */
	if (keyboard_check_pressed(vk_enter)) action = client_join_action_focus;

	/* A pointer click on a hovered button replaces the keyboard action with that
	button's key. Eligibility is enforced by the action handlers */
	if (mouse_pressed && client_join_hover_button != "") action = client_join_hover_button;

	/* F5 requests list refresh independently of the current action focus */
	if (keyboard_check_pressed(vk_f5)) action = "refresh";

	/* A qualifying repeated row click takes final precedence and requests Join */
	if (double_click_join) action = "join";

	/* Back or a completed held-Escape action returns to mode selection.
	Cancel any busy connection before leaving so its later completion cannot join
	behind the mode chooser */
	if (escape_exit_hold_update("join_back", true) || action == "back")
	{
		/* A busy pending attempt must be disconnected before opening the mode screen.
		An idle client needs no cancellation */
		if (busy) client.disconnect("Connection cancelled.");
		network_open_mode_screen("Choose another network mode.");
		return;
	}

	/* Only idle connection/DNS state may run list actions. Back cancellation has
	already been handled above, while busy startup skips Join/Edit/Refresh work */
	if (!busy)
	{
		/* Dispatch the chosen action to join validation, a direct/saved-server dialog or
		list refresh. Empty/unknown actions leave the list unchanged */
		switch (action)
		{
			/* Join routes through the existing readiness flag rather than blindly opening
			the selected server connection */
			case "join":

				/* Attempt joining only while the current row, username and startup state permit it.
				A disabled Join action leaves the selection screen unchanged */
				if (client_join_join_enabled) client_join_attempt();
				break;

			/* Direct opens an address-entry dialog for a one-time target */
			case "direct": client_join_open_dialog("direct"); break;

			/* Add opens a dialog that can persist a new custom server entry */
			case "add": client_join_open_dialog("add"); break;

			/* Edit opens only for an eligible saved row, preserving read-only official entries */
			case "edit": if (client_join_edit_enabled) client_join_open_dialog("edit"); break;

			/* Delete confirmation also requires an eligible saved row */
			case "delete": if (client_join_edit_enabled) client_join_open_dialog("delete"); break;

			/* Refresh rebuilds discovery/configuration list state through its existing handler */
			case "refresh": client_join_refresh(); break;
		}
	}
}
#endregion /* Server Selection END */

/* The client view handles its session recovery, overlays and player input below.
The server-view alternative at the end handles console controls instead */
if (is_client)
{
	/* Borrow the active client for host identity, admin controls and connection health */
	var active_client = scr_get_client();

	/* A Host & Play session awaiting host ownership can claim it only after the client
	has an assigned logical ID. Earlier connection state leaves the claim pending */
	if (host_play_active
	&& host_claim_pending
	&& is_struct(active_client)
	&& variable_struct_exists(active_client, "ID")
	&& active_client.ID != noone)
	{
		/* Borrow authoritative hosting state to register which joined slot belongs to
		the local host player */
		var hosted_server = scr_get_server();

		/* Claim ownership only through an available server capability that accepts this
		slot. A failed claim keeps host_claim_pending true for a later Step */
		if (is_struct(hosted_server)
		&& variable_struct_exists(hosted_server, "claim_host_player_slot")
		&& hosted_server.claim_host_player_slot(active_client.ID))
		{
			host_claim_pending = false;
			debug_success("Local host identity claimed for " + scr_network_debug_id_text(active_client.ID));
		}
	}

	/* An online client requesting the server list must leave gameplay when that list
	is not already visible. Singleplayer ignores remote reconnect/list recovery */
	if (!client_join_screen
	&& !is_singleplayer
	&& is_struct(active_client)
	&& variable_struct_exists(active_client, "needs_server_list")
	&& active_client.needs_server_list)
	{
		/* A lost Host & Play player returns to the server console, preserving the hosting
		session while its local client is disconnected */
		if (host_play_active)
		{
			/* host_failure_status starts with the client connection feedback so the console
			can explain the local player's failure */
			var host_failure_status = active_client.connect_status;

			/* When the client supplied no feedback, use the explicit local-disconnect message.
			This leaves the user aware that authoritative hosting is still running */
			if (host_failure_status == "")
			{
				host_failure_status = "Your local player disconnected. The server is still running.";
			}
			network_return_to_server_console(host_failure_status);
		}

		/* An ordinary remote client returns to server selection with its connection feedback.
		It has no local host console to preserve */
		else
		{
			client_open_server_list(active_client.connect_status, false);
		}
		return;
	}

	/* Borrow drawing state and record whether its text-entry handler currently captures
	keyboard input. drawing_text_entry_active controls whether movement may run later */
	var drawing_debug = scr_get_drawing();
	var drawing_text_entry_active = is_struct(drawing_debug)
		&& variable_struct_exists(drawing_debug, "text_entry_captures_keyboard")
		&& drawing_debug.text_entry_captures_keyboard();

	/* Borrow social UI state. social_card_open is true only for an available service
	with an open card, preventing leave/menu shortcuts from interrupting that card */
	var social_ui = scr_get_social();
	var social_card_open = is_struct(social_ui)
		&& variable_struct_exists(social_ui, "card_open")
		&& (social_ui.card_open || social_ui.pet_card_open);

	/* Borrow the character-maker UI. character_maker_active records its available
	blocks_game_input result, so editor interactions take priority over world actions */
	var character_maker_ui = scr_get_character_maker();
	var character_maker_active = is_struct(character_maker_ui)
		&& variable_struct_exists(character_maker_ui, "blocks_game_input")
		&& character_maker_ui.blocks_game_input();

	/* Session leave/admin controls run outside the join screen.
	Server selection already owns input when client_join_screen remains visible */
	if (!client_join_screen)
	{
		/* has_active_socket requires a numeric live connection handle. has_assigned_id
		requires a logical player identity. Check service/member availability before both
		accesses so either established-session signal can enable its leave controls */
		var has_active_socket = is_struct(active_client)
			&& variable_struct_exists(active_client, "socket")
			&& is_real(active_client.socket)
			&& active_client.socket >= 0;
		var has_assigned_id = is_struct(active_client)
			&& variable_struct_exists(active_client, "ID")
			&& active_client.ID != noone;

	/* A live connection or assigned logical ID allows session controls, including an
	in-progress connected session before both states have settled. With neither,
	skip overlays that require an active session */
	if (has_active_socket || has_assigned_id)
	{
			/* Borrow chat state for input ownership and movement release before updating the
			session leave-button layout */
			var chat = scr_get_chat();
			client_leave_update_layout();

			/* Sample pointer coordinates in GUI pixels for the session leave/admin button.
			Its hover flag is true only within the current button rectangle */
			var mouse_x_gui = device_mouse_x_to_gui(0);
			var mouse_y_gui = device_mouse_y_to_gui(0);
			client_leave_button_hover = mouse_x_gui >= client_leave_button_x
				&& mouse_x_gui <= client_leave_button_x + client_leave_button_width
				&& mouse_y_gui >= client_leave_button_y
				&& mouse_y_gui <= client_leave_button_y + client_leave_button_height;

			/* remote_admin_available requires authenticated remote admin state and excludes
			local Host & Play and Singleplayer. Local hosting has separate owner controls */
			var remote_admin_available = !host_play_active
				&& !is_singleplayer
				&& variable_struct_exists(active_client, "admin_authenticated")
				&& active_client.admin_authenticated;

			/* If admin authentication or remote-session eligibility disappears, close its
			controls/logs and clear focus and confirmation deadlines. Stale admin UI must not
			continue accepting privileged input */
			if (official_admin_controls_open && !remote_admin_available)
			{
				escape_exit_hold_reset();
				official_admin_controls_open = false;
				official_admin_logs_open = false;
				official_admin_hover_button = "";
				official_admin_focus = "";
				keyboard_string = "";
				official_admin_restart_confirm_until = 0;
				official_admin_reset_confirm_until = 0;
			}

			/* Begin with the admin panel unopened in this Step. Opening sets the flag so the
			same pointer press cannot immediately activate a newly exposed admin control */
			var admin_controls_just_opened = false;

			/* Open remote admin controls only for an eligible owner clicking the session button,
			with chat, canvas text, zoom entry, social card and character maker all inactive.
			Those input owners must finish before their click can be treated as admin input */
			if (remote_admin_available
			&& !official_admin_controls_open
			&& !chat.is_open
			&& !drawing_text_entry_active
			&& !network_camera_zoom_input_active
			&& !social_card_open
			&& !character_maker_active
			&& client_leave_button_hover
			&& mouse_check_button_pressed(mb_left))
			{
				escape_exit_hold_reset();
				official_admin_controls_open = true;
				official_admin_logs_open = false;
				admin_controls_just_opened = true;
				official_admin_hover_button = "";
				official_admin_focus = "";
				official_admin_max_players_text = string(active_client.admin_max_players);
				keyboard_string = "";
				official_admin_restart_confirm_until = 0;
				official_admin_reset_confirm_until = 0;
				official_admin_next_refresh_at = current_time;

				/* Release local movement when the session exposes that capability, preventing
				held actions from continuing while admin controls capture input */
				if (variable_struct_exists(active_client, "release_local_movement"))
				{
					active_client.release_local_movement();
				}
			}

			/* The open admin panel owns this Step after maintenance. Update its controls and
			connection health before returning instead of running player movement beneath it */
			if (official_admin_controls_open)
			{
				official_admin_controls_update_layout();

				/* Borrow network policy for bounded player-count input and browser capability checks */
				var admin_net = scr_get_network();

				/* Refresh displayed player capacity from server status only outside active editing.
				Keep the user's typed candidate while the max-player field owns focus */
				if (official_admin_focus != "max_players")
				{
					/* synced_admin_max_players is the whole-number server-reported limit clamped to
					network policy bounds before it becomes the displayed field text */
					var synced_admin_max_players = clamp(
						floor(real(active_client.admin_max_players)),
						admin_net.min_player_limit,
						admin_net.max_player_limit
					);
					official_admin_max_players_text = string(synced_admin_max_players);
				}

				/* Capture current GUI pointer x/y and a fresh left-click for admin buttons */
				var admin_mouse_x = device_mouse_x_to_gui(0);
				var admin_mouse_y = device_mouse_y_to_gui(0);
				var admin_mouse_pressed = mouse_check_button_pressed(mb_left);

				/* An open logs subpage routes input to download/cancel, open-folder and Back.
				It returns after connection maintenance, keeping lifecycle controls underneath inactive */
				if (official_admin_logs_open)
				{
					/* Borrow the client-owned log transfer. log_button_x/width reuse the panel's button
					column. log_download_hover, log_folder_hover and log_back_hover each test that
					column's corresponding 40-pixel-high GUI action rectangle */
					var log_download = active_client.admin_logs;
					var log_button_x = official_admin_toggle_button_x;
					var log_button_width = official_admin_toggle_button_width;
					var log_download_hover = point_in_rect(admin_mouse_x, admin_mouse_y, log_button_x, official_admin_logs_download_button_y, log_button_x + log_button_width, official_admin_logs_download_button_y + 40);
					var log_folder_hover = point_in_rect(admin_mouse_x, admin_mouse_y, log_button_x, official_admin_logs_folder_button_y, log_button_x + log_button_width, official_admin_logs_folder_button_y + 40);
					var log_back_hover = point_in_rect(admin_mouse_x, admin_mouse_y, log_button_x, official_admin_logs_back_button_y, log_button_x + log_button_width, official_admin_logs_back_button_y + 40);

					/* Choose the first hovered logs action in download, folder, then Back order.
					Empty text clears the highlight when the pointer is outside these rectangles */
					official_admin_hover_button = log_download_hover ? "download_logs" : (log_folder_hover ? "logs_folder" : (log_back_hover ? "logs_back" : ""));

					/* Escape or a clicked Back closes only the logs subpage, leaving the admin panel open */
					if (keyboard_check_pressed(vk_escape) || (admin_mouse_pressed && log_back_hover))
					{
						official_admin_logs_open = false;
						official_admin_hover_button = "";
					}

					/* A clicked download button either cancels its active transfer or considers a new
					request. Other pointer positions leave the transfer state unchanged */
					else if (admin_mouse_pressed && log_download_hover)
					{
						/* An active log transfer makes this button Cancel. Stop it instead of starting
						a second download over the same client-owned transfer state */
						if (log_download.active)
						{
							log_download.cancel();
						}

						/* An idle native client may start log downloading only with no command, status
						refresh or restart underway. Browser mode and busy lifecycle work skip this request */
						else if (!admin_net.is_browser_runtime()
						&& !active_client.admin_command_pending
						&& !active_client.admin_status_refresh_pending
						&& !active_client.admin_restart_in_progress)
						{
							log_download.start();
						}
					}

					/* Open the downloaded log folder only on a native runtime and after a nonempty
					folder path exists. Browser or absent output paths leave it unopened */
					else if (admin_mouse_pressed && log_folder_hover && !admin_net.is_browser_runtime() && log_download.folder != "")
					{
						log_download.open_folder();
					}
					active_client.update_connection_watchdog();
					return;
				}

				/* Keep these hit tests in the event scope because anonymous methods do not capture
				Step locals on every GameMaker runner. admin_toggle_hover/minus_hover/plus_hover
				identify scheduling controls. max_players_input/apply identify edit/commit areas,
				while reset/wall/restart/refresh/logs/back/leave identify their named actions.
				Each uses the current GUI-pixel layout for highlighting and click routing */
				var admin_toggle_hover = admin_mouse_x >= official_admin_toggle_button_x
					&& admin_mouse_x <= official_admin_toggle_button_x + official_admin_toggle_button_width
					&& admin_mouse_y >= official_admin_toggle_button_y
					&& admin_mouse_y <= official_admin_toggle_button_y + official_admin_toggle_button_height;
				var admin_minus_hover = admin_mouse_x >= official_admin_minus_button_x
					&& admin_mouse_x <= official_admin_minus_button_x + official_admin_minus_button_width
					&& admin_mouse_y >= official_admin_minus_button_y
					&& admin_mouse_y <= official_admin_minus_button_y + official_admin_minus_button_height;
				var admin_plus_hover = admin_mouse_x >= official_admin_plus_button_x
					&& admin_mouse_x <= official_admin_plus_button_x + official_admin_plus_button_width
					&& admin_mouse_y >= official_admin_plus_button_y
					&& admin_mouse_y <= official_admin_plus_button_y + official_admin_plus_button_height;
				var admin_max_players_input_hover = admin_mouse_x >= official_admin_max_players_input_x
					&& admin_mouse_x <= official_admin_max_players_input_x + official_admin_max_players_input_width
					&& admin_mouse_y >= official_admin_max_players_input_y
					&& admin_mouse_y <= official_admin_max_players_input_y + official_admin_max_players_input_height;
				var admin_max_players_apply_hover = admin_mouse_x >= official_admin_max_players_apply_button_x
					&& admin_mouse_x <= official_admin_max_players_apply_button_x + official_admin_max_players_apply_button_width
					&& admin_mouse_y >= official_admin_max_players_apply_button_y
					&& admin_mouse_y <= official_admin_max_players_apply_button_y + official_admin_max_players_apply_button_height;
				var admin_reset_hover = admin_mouse_x >= official_admin_reset_button_x
					&& admin_mouse_x <= official_admin_reset_button_x + official_admin_reset_button_width
					&& admin_mouse_y >= official_admin_reset_button_y
					&& admin_mouse_y <= official_admin_reset_button_y + official_admin_reset_button_height;
				var admin_wall_hover = admin_mouse_x >= official_admin_wall_button_x
					&& admin_mouse_x <= official_admin_wall_button_x + official_admin_wall_button_width
					&& admin_mouse_y >= official_admin_wall_button_y
					&& admin_mouse_y <= official_admin_wall_button_y + official_admin_wall_button_height;
				var admin_refresh_hover = admin_mouse_x >= official_admin_refresh_button_x
					&& admin_mouse_x <= official_admin_refresh_button_x + official_admin_refresh_button_width
					&& admin_mouse_y >= official_admin_refresh_button_y
					&& admin_mouse_y <= official_admin_refresh_button_y + official_admin_refresh_button_height;
				var admin_restart_hover = admin_mouse_x >= official_admin_restart_button_x
					&& admin_mouse_x <= official_admin_restart_button_x + official_admin_restart_button_width
					&& admin_mouse_y >= official_admin_restart_button_y
					&& admin_mouse_y <= official_admin_restart_button_y + official_admin_restart_button_height;
				var admin_logs_hover = point_in_rect(admin_mouse_x, admin_mouse_y, official_admin_logs_button_x, official_admin_logs_button_y, official_admin_logs_button_x + official_admin_logs_button_width, official_admin_logs_button_y + official_admin_refresh_button_height);
				var admin_back_hover = admin_mouse_x >= official_admin_back_button_x
					&& admin_mouse_x <= official_admin_back_button_x + official_admin_back_button_width
					&& admin_mouse_y >= official_admin_back_button_y
					&& admin_mouse_y <= official_admin_back_button_y + official_admin_back_button_height;
				var admin_leave_hover = admin_mouse_x >= official_admin_leave_button_x
					&& admin_mouse_x <= official_admin_leave_button_x + official_admin_leave_button_width
					&& admin_mouse_y >= official_admin_leave_button_y
					&& admin_mouse_y <= official_admin_leave_button_y + official_admin_leave_button_height;

				/* Clear the admin hover key before choosing the first matching control.
				Overlapping rectangles follow the explicit priority of the branches below */
				official_admin_hover_button = "";

				/* Hovering reset enablement highlights the scheduling toggle */
				if (admin_toggle_hover) official_admin_hover_button = "toggle";

				/* The next hover alternative highlights shortening the reset interval */
				else if (admin_minus_hover) official_admin_hover_button = "minus";

				/* A pointer over Plus highlights lengthening the reset interval */
				else if (admin_plus_hover) official_admin_hover_button = "plus";

				/* The player-count input rectangle highlights the editable capacity field */
				else if (admin_max_players_input_hover) official_admin_hover_button = "max_players_input";

				/* The capacity Apply rectangle highlights its commit action */
				else if (admin_max_players_apply_hover) official_admin_hover_button = "max_players_apply";

				/* Wall-control hover identifies the shared wall-policy action */
				else if (admin_wall_hover) official_admin_hover_button = "walls";

				/* Reset hover identifies the immediate canvas-reset action */
				else if (admin_reset_hover) official_admin_hover_button = "reset";

				/* Refresh hover identifies the manual server-status request */
				else if (admin_refresh_hover) official_admin_hover_button = "refresh";

				/* Logs hover identifies the download subpage */
				else if (admin_logs_hover) official_admin_hover_button = "logs";

				/* Restart hover identifies the managed server-restart request */
				else if (admin_restart_hover) official_admin_hover_button = "restart";

				/* Back hover identifies closing admin controls while staying connected */
				else if (admin_back_hover) official_admin_hover_button = "back";

				/* The remaining Leave rectangle highlights returning to server selection */
				else if (admin_leave_hover) official_admin_hover_button = "leave";

				/* Expire restart confirmation after its current_time millisecond deadline.
				Zero means the next click must begin a fresh confirmation window */
				if (current_time > official_admin_restart_confirm_until)
				{
					official_admin_restart_confirm_until = 0;
				}

				/* Expire canvas-reset confirmation on the same millisecond clock.
				Clear its pending confirmation so a later click cannot reuse stale consent */
				if (current_time > official_admin_reset_confirm_until)
				{
					official_admin_reset_confirm_until = 0;
				}

				/* Only the focused capacity field consumes shared keyboard text.
				Filter its candidate before considering any admin command */
				if (official_admin_focus == "max_players")
				{
					scr_text_input_update("admin_max_players", official_admin_max_players_text);

					/* admin_filtered_max_players is the allowed player-limit text after filtering
					unsupported characters from the keyboard buffer */
					var admin_filtered_max_players = max_players_filter_input(keyboard_string);
					official_admin_max_players_text = admin_filtered_max_players;

					/* When filtering changes the keyboard text, replace that buffer with the accepted
					candidate so later input cannot reintroduce rejected characters */
					if (string(keyboard_string) != admin_filtered_max_players)
					{
						keyboard_string = admin_filtered_max_players;
					}
				}

				/* An admin pointer press may change focus only after the panel's opening Step.
				The opening click must not also activate a field beneath it */
				if (!admin_controls_just_opened && admin_mouse_pressed)
				{
					/* Clicking the capacity field focuses it and loads the current candidate text */
					if (admin_max_players_input_hover)
					{
						official_admin_focus = "max_players";
						keyboard_string = official_admin_max_players_text;
					}

					/* A click outside Apply while capacity editing cancels the edit and restores
					bounded server-reported text. Clicking Apply retains the candidate for validation */
					else if (official_admin_focus == "max_players"
					&& !admin_max_players_apply_hover)
					{
						official_admin_focus = "";
						official_admin_max_players_text = string(clamp(
							floor(real(active_client.admin_max_players)),
							admin_net.min_player_limit,
							admin_net.max_player_limit
						));
						keyboard_string = "";
					}
				}

				/* Escape while editing cancels the capacity candidate only after the opening Step.
				Restore reported server state and return without also closing the admin panel */
				if (!admin_controls_just_opened
				&& official_admin_focus == "max_players"
				&& keyboard_check_pressed(vk_escape))
				{
					official_admin_focus = "";
					official_admin_max_players_text = string(clamp(
						floor(real(active_client.admin_max_players)),
						admin_net.min_player_limit,
						admin_net.max_player_limit
					));
					keyboard_string = "";
					return;
				}

				/* Outside the just-opened Step, Escape or clicked Back closes admin controls.
				Clear text focus and destructive-action confirmation state before returning */
				if (!admin_controls_just_opened
				&& (keyboard_check_pressed(vk_escape) || (admin_back_hover && admin_mouse_pressed)))
				{
					escape_exit_hold_reset();
					official_admin_controls_open = false;
					official_admin_hover_button = "";
					official_admin_focus = "";
					keyboard_string = "";
					official_admin_restart_confirm_until = 0;
					official_admin_reset_confirm_until = 0;
					return;
				}

				/* A clicked Leave outside the opening Step disconnects to server selection.
				Return immediately so no admin command can also run during departure */
				if (!admin_controls_just_opened && admin_leave_hover && admin_mouse_pressed)
				{
					client_open_server_list("Disconnected. Select a server to reconnect.", true);
					return;
				}

				/* A clicked Logs outside the opening Step switches to its download subpage.
				Clear field focus/confirmations, advance connection health and end this panel Step */
				if (!admin_controls_just_opened && admin_logs_hover && admin_mouse_pressed)
				{
					official_admin_logs_open = true;
					official_admin_focus = "";
					official_admin_hover_button = "";
					official_admin_restart_confirm_until = 0;
					official_admin_reset_confirm_until = 0;
					keyboard_string = "";
					active_client.update_connection_watchdog();
					return;
				}

				/* admin_command_busy covers pending command or status replies. admin_restart_busy
				covers restart state and admin_logs_busy covers the active log transfer.
				admin_controls_busy combines them so lifecycle/capacity commands wait until idle */
				var admin_command_busy = (variable_struct_exists(active_client, "admin_command_pending")
					&& active_client.admin_command_pending)
					|| (variable_struct_exists(active_client, "admin_status_refresh_pending")
					&& active_client.admin_status_refresh_pending);
				var admin_restart_busy = variable_struct_exists(active_client, "admin_restart_in_progress")
					&& active_client.admin_restart_in_progress;
				var admin_logs_busy = active_client.admin_logs.active;
				var admin_controls_busy = admin_command_busy || admin_restart_busy || admin_logs_busy;

				/* admin_max_players_valid checks the complete allowed integer input range.
				admin_max_players_changed additionally compares its numeric value with reported
				server capacity, so unchanged values need no network command */
				var admin_max_players_valid = max_players_input_is_valid(official_admin_max_players_text);
				var admin_max_players_changed = admin_max_players_valid
					&& max_players_input_value(official_admin_max_players_text) != floor(real(active_client.admin_max_players));

				/* admin_max_players_apply_requested combines a fresh Apply click or Enter while
				editing, excluding the panel-opening Step. It does not yet establish value validity */
				var admin_max_players_apply_requested = !admin_controls_just_opened
					&& ((admin_max_players_apply_hover && admin_mouse_pressed)
						|| (official_admin_focus == "max_players" && keyboard_check_pressed(vk_enter)));

				/* Process a requested capacity commit only while all admin operations are idle.
				Busy transfers, replies or restart state leave the candidate unsubmitted */
				if (admin_max_players_apply_requested && !admin_controls_busy)
				{
					/* Invalid capacity text produces bounded-range feedback instead of sending a
					server command. Record the result time for its visible feedback */
					if (!admin_max_players_valid)
					{
						active_client.admin_last_result_code = ADMIN_RESULT_FAILED;
						active_client.admin_last_result_message = "Enter a whole number from "
							+ string(admin_net.min_player_limit) + " to " + string(admin_net.max_player_limit) + ".";
						active_client.admin_last_result_at = current_time;
					}

					/* An unchanged valid capacity reports that no update is needed, then clears input
					focus without consuming a network request */
					else if (!admin_max_players_changed)
					{
						active_client.admin_last_result_code = ADMIN_RESULT_OK;
						active_client.admin_last_result_message = "Maximum players is already set to "
							+ string(max_players_input_value(official_admin_max_players_text)) + ".";
						active_client.admin_last_result_at = current_time;
						official_admin_focus = "";
						keyboard_string = "";
					}

					/* A changed valid limit uses the available admin setter. Clear field focus only
					when that method accepts the request, preserving the candidate on rejection */
					else if (admin_max_players_changed
					&& variable_struct_exists(active_client, "set_admin_max_players")
					&& active_client.set_admin_max_players(max_players_input_value(official_admin_max_players_text)))
					{
						official_admin_focus = "";
						keyboard_string = "";
					}
					return;
				}

				/* Lifecycle buttons require a fresh pointer press after opening and no pending
				command/status, restart or log transfer. This prevents overlapping admin operations */
				if (!admin_controls_just_opened
				&& !admin_command_busy
				&& !admin_restart_busy
				&& !admin_logs_busy
				&& admin_mouse_pressed)
				{
					/* A reset-toggle click calls available client support with the opposite reported
					scheduling state. The command handler still validates authenticated eligibility */
					if (admin_toggle_hover && variable_struct_exists(active_client, "set_admin_reset_enabled"))
					{
						active_client.set_admin_reset_enabled(!active_client.admin_reset_enabled);
					}

					/* A supported wall-control click asks the client to change the opposite reported
					wall policy. Its request method determines whether the command can be accepted */
					else if (admin_wall_hover && active_client.wall_drawing_supported)
					{
						active_client.set_admin_wall_drawing(!active_client.wall_drawing_enabled);
					}

					/* A Minus click uses available interval support to shorten scheduling by 30 minutes,
					clamped to the server's 15-minute minimum */
					else if (admin_minus_hover && variable_struct_exists(active_client, "set_admin_reset_interval"))
					{
						active_client.set_admin_reset_interval(max(15, active_client.admin_reset_interval_minutes - 30));
					}

					/* A Plus click extends the requested reset interval by 30 minutes without exceeding
					1,440 minutes, matching the one-day server limit */
					else if (admin_plus_hover && variable_struct_exists(active_client, "set_admin_reset_interval"))
					{
						active_client.set_admin_reset_interval(min(1440, active_client.admin_reset_interval_minutes + 30));
					}

					/* A manual Refresh click uses available client status-request support */
					else if (admin_refresh_hover && variable_struct_exists(active_client, "request_admin_status"))
					{
						/* Only an accepted manual refresh advances the next polling deadline by 2 seconds.
						A rejected request leaves scheduling unchanged so later eligible polling can retry */
						if (active_client.request_admin_status(true))
						{
							official_admin_next_refresh_at = current_time + 2000;
						}
					}

					/* The reset button requires its client capability before beginning or completing
					a two-click canvas-reset confirmation */
					else if (admin_reset_hover && variable_struct_exists(active_client, "request_admin_reset_now"))
					{
						/* A still-active confirmation allows the second click to request immediate reset.
						Clear the confirmation afterward so it cannot be reused */
						if (official_admin_reset_confirm_until > 0)
						{
							active_client.request_admin_reset_now();
							official_admin_reset_confirm_until = 0;
						}

						/* The first reset click opens a 5,000 ms current_time confirmation window.
						No reset command is sent until another click arrives before expiry */
						else
						{
							official_admin_reset_confirm_until = current_time + 5000;
						}
					}

					/* Restart uses available client support and a separate two-click confirmation,
					keeping its deadline independent of canvas reset */
					else if (admin_restart_hover && variable_struct_exists(active_client, "request_admin_force_restart"))
					{
						/* The second restart click inside its active window requests managed restart.
						Clear its confirmation whether the request method later accepts or rejects it */
						if (official_admin_restart_confirm_until > 0)
						{
							active_client.request_admin_force_restart();
							official_admin_restart_confirm_until = 0;
						}

						/* A first restart click grants a 5-second current_time confirmation window.
						It leaves the running server unchanged until a confirming click */
						else
						{
							official_admin_restart_confirm_until = current_time + 5000;
						}
					}
				}

				/* admin_poll_busy combines pending command/status replies and restart state.
				Periodic status requests wait for these operations rather than competing with them */
				var admin_poll_busy = (variable_struct_exists(active_client, "admin_command_pending")
					&& active_client.admin_command_pending)
					|| (variable_struct_exists(active_client, "admin_status_refresh_pending")
					&& active_client.admin_status_refresh_pending)
					|| (variable_struct_exists(active_client, "admin_restart_in_progress")
					&& active_client.admin_restart_in_progress);

				/* When idle, past the current_time polling deadline and with status support,
				request a quiet refresh and schedule the next attempt 2 seconds later.
				Advance this deadline even if the request method rejects this attempt */
				if (!admin_poll_busy
				&& current_time >= official_admin_next_refresh_at
				&& variable_struct_exists(active_client, "request_admin_status"))
				{
					active_client.request_admin_status(false);
					official_admin_next_refresh_at = current_time + 2000;
				}

				/* An available watchdog keeps remote connection health advancing while admin
				controls own input. Missing support skips this final maintenance */
				if (variable_struct_exists(active_client, "update_connection_watchdog"))
				{
					active_client.update_connection_watchdog();
				}

				/* Admin controls have consumed this Step. Return before leave shortcuts, other
				client overlays or gameplay can interpret their input */
				return;
			}

			/* can_escape_leave permits leave input only when chat, canvas text, zoom entry,
			social card and character maker do not own interaction. Host & Play suppresses
			held-Escape departure and uses its non-pausing host menu instead */
			var can_escape_leave = !chat.is_open
				&& !drawing_text_entry_active
				&& !network_camera_zoom_input_active
				&& !social_card_open
				&& !character_maker_active;
			var should_leave_with_escape = host_play_active
				? false
				: escape_exit_hold_update("client_leave", can_escape_leave);

			/* should_leave_with_mouse requires a fresh leave-button click outside zoom entry
			and character editing. Other overlay restrictions for admin/menu opening are
			checked by their own paths */
			var should_leave_with_mouse = !network_camera_zoom_input_active
				&& !character_maker_active
				&& client_leave_button_hover
				&& mouse_check_button_pressed(mb_left);

			/* Host & Play handles leave input through its owner menu rather than directly
			disconnecting or shutting down hosting. Reset the ordinary held-Escape exit state */
			if (host_play_active)
			{
				escape_exit_hold_reset();

				/* host_menu_just_opened starts false each Step. A new menu activation sets it so
				the opening key/click cannot immediately Resume, Return or Shutdown */
				var host_menu_just_opened = false;

				/* Open the host menu only while closed and after an accepted pointer leave action
				or Escape outside competing input owners. The hosted server keeps updating
				because maintenance already ran before this menu handling */
				if (!host_session_menu_open
				&& (should_leave_with_mouse
					|| (can_escape_leave && keyboard_check_pressed(vk_escape))))
				{
					host_session_menu_open = true;
					host_menu_just_opened = true;

					/* An available chat movement-release capability clears held actions once when the
					menu opens, preventing the authoritative host player from continuing to walk
					under this non-pausing menu. Missing chat support skips the release call */
					if (is_struct(chat)
					&& variable_struct_exists(chat, "release_local_movement"))
					{
						chat.release_local_movement();
					}
				}

				/* While the host menu is open, route input to its controls and return after
				connection health maintenance. Gameplay must not consume menu input */
				if (host_session_menu_open)
				{
					host_session_menu_update_layout();

					/* Capture host-menu pointer coordinates in GUI pixels and a fresh left-click.
					resume_hover/return_hover/shutdown_hover identify their named button rectangles,
					and host_wall_hover identifies its wall-policy rectangle */
					var host_mouse_x = device_mouse_x_to_gui(0);
					var host_mouse_y = device_mouse_y_to_gui(0);
					var host_mouse_pressed = mouse_check_button_pressed(mb_left);
					var resume_hover = host_mouse_x >= host_menu_resume_button_x
						&& host_mouse_x <= host_menu_resume_button_x + host_menu_resume_button_width
						&& host_mouse_y >= host_menu_resume_button_y
						&& host_mouse_y <= host_menu_resume_button_y + host_menu_resume_button_height;
					var return_hover = host_mouse_x >= host_menu_return_button_x
						&& host_mouse_x <= host_menu_return_button_x + host_menu_return_button_width
						&& host_mouse_y >= host_menu_return_button_y
						&& host_mouse_y <= host_menu_return_button_y + host_menu_return_button_height;
					var shutdown_hover = host_mouse_x >= host_menu_shutdown_button_x
						&& host_mouse_x <= host_menu_shutdown_button_x + host_menu_shutdown_button_width
						&& host_mouse_y >= host_menu_shutdown_button_y
						&& host_mouse_y <= host_menu_shutdown_button_y + host_menu_shutdown_button_height;
					var host_wall_hover = point_in_rect(host_mouse_x, host_mouse_y, host_menu_wall_button_x, host_menu_wall_button_y, host_menu_wall_button_x + host_menu_wall_button_width, host_menu_wall_button_y + host_menu_wall_button_height);

					/* Choose the first host-menu highlight in Resume, Walls, Return, Shutdown order.
					An empty key clears hover when no control contains the pointer */
					host_menu_hover_button = resume_hover ? "resume" : (host_wall_hover ? "walls" : (return_hover ? "return" : (shutdown_hover ? "shutdown" : "")));

					/* Escape or clicked Resume closes the menu only after its opening Step.
					This avoids immediately dismissing the menu with the input that opened it */
					if ((!host_menu_just_opened && keyboard_check_pressed(vk_escape))
					|| (!host_menu_just_opened && resume_hover && host_mouse_pressed))
					{
						host_session_menu_open = false;
						host_menu_hover_button = "";
						return;
					}

					/* A clicked Return after opening leaves local play for the server console.
					Hosting continues under that transition rather than stopping the shared server */
					if (!host_menu_just_opened && return_hover && host_mouse_pressed)
					{
						network_return_to_server_console();
						return;
					}

					/* A clicked Walls control after opening toggles the local host's authoritative
					wall policy. Return after updating so the same click cannot activate another control */
					if (!host_menu_just_opened && host_wall_hover && host_mouse_pressed)
					{
						/* Borrow hosting state for its wall-policy setter. Its success selects feedback
						from the resulting enabled state, while failure reports that the setting could
						not be saved */
						var walls_host_server = scr_get_server();
						host_menu_wall_feedback = walls_host_server.set_wall_drawing_enabled(!walls_host_server.wall_drawing_enabled)
							? (walls_host_server.wall_drawing_enabled ? "Wall drawing enabled." : "Walls are now passable.")
							: "Could not save the wall setting.";
						return;
					}

					/* A clicked Shutdown after opening requests hosted-server cleanup and then
					ends this menu Step, unlike Return which preserves hosting */
					if (!host_menu_just_opened && shutdown_hover && host_mouse_pressed)
					{
						network_shutdown_hosted_server();
						return;
					}

					/* An available client watchdog keeps loopback connection health advancing while
					the host menu blocks player input */
					if (is_struct(active_client)
					&& variable_struct_exists(active_client, "update_connection_watchdog"))
					{
						active_client.update_connection_watchdog();
					}

					/* The open host menu owns this Step even when no button fired.
					Return before drawing or movement can reuse its input */
					return;
				}
			}

			/* Outside Host & Play, an accepted held-Escape or pointer leave action ends the
			current client session through its mode-appropriate destination */
			else if (should_leave_with_escape || should_leave_with_mouse)
			{
				/* Leaving Singleplayer returns to network-mode selection because there is no
				remote server list connection to restore */
				if (is_singleplayer)
				{
					network_open_mode_screen("Singleplayer stopped. Choose a network mode.");
				}

				/* A remote client leaves through server selection and requests disconnection,
				allowing the player to choose a new or previous target */
				else
				{
					client_open_server_list("Disconnected. Select a server to reconnect.", true);
				}
				return;
			}
		}
	}

	/* Without an assigned logical Client ID, no local player is ready for world input.
	End this client Step before looking up player state */
	if (Client.ID == noone)
	{
		return;
	}

	/* An online client with watchdog support advances connection-health deadlines
	before gameplay. Singleplayer skips these remote liveness checks */
	if (!is_singleplayer
	&& is_struct(active_client)
	&& variable_struct_exists(active_client, "update_connection_watchdog"))
	{
		active_client.update_connection_watchdog();
	}

	/* _id is the assigned logical player slot, not its socket handle.
	local_player resolves that slot in the shared player controller before world input */
	var _id = Client.ID;
	var local_player = player_controller_get_player(_id);

	/* An absent local player cannot consume movement or collision input.
	Return until its roster state becomes available */
	if (local_player == noone)
	{
		return;
	}

	/* Active canvas text entry owns keyboard input. Update drawing with the earlier
	history-maintenance flag, advance the camera and return before movement */
	if (drawing_text_entry_active)
	{
		drawing_debug.update_client(network_camera, drawing_sync_maintenance_done);
		network_camera_update();
		return;
	}

	/* When zoom-field input reports that it consumed this Step, update the camera
	and stop routing. Otherwise allow the next overlay to inspect input */
	if (network_camera_update_zoom_input())
	{
		network_camera_update();
		return;
	}

	/* A social UI input update that claims this Step prevents character/chat/world
	input from running behind its interaction. Keep camera maintenance before returning */
	if (social_ui.update_client_input(network_camera))
	{
		network_camera_update();
		return;
	}

	/* An available character-maker input handler may claim the Step.
	When it does, update the camera and bypass chat, drawing and player movement */
	if (is_struct(character_maker_ui)
	&& variable_struct_exists(character_maker_ui, "update_client_input")
	&& character_maker_ui.update_client_input())
	{
		network_camera_update();
		return;
	}

	/* Chat's input handler has priority over drawing and movement when it consumes
	the Step. Keep camera updates running while text/chat interaction captures keys */
	if (scr_get_chat().update_client_input())
	{
		/* An available drawing diagnostic hook records why normal client drawing input
		was skipped. Missing diagnostics must not affect chat's input ownership */
		if (is_struct(drawing_debug)
		&& variable_struct_exists(drawing_debug, "debug_note"))
		{
			drawing_debug.debug_note("client update skipped", "chat captured input");
		}
		network_camera_update();
		return;
	}

	/* Update drawing with the flag indicating whether history maintenance already ran.
	Drawing may begin text entry in this same call before movement is considered */
	drawing_debug.update_client(network_camera, drawing_sync_maintenance_done);

	/* Recheck available drawing text-entry capture after its input update.
	If it became active in this Step, update the camera and return so held keys do
	not immediately restore movement that text entry just released */
	if (is_struct(drawing_debug)
	&& variable_struct_exists(drawing_debug, "text_entry_captures_keyboard")
	&& drawing_debug.text_entry_captures_keyboard())
	{
		network_camera_update();
		return;
	}

	/* Singleplayer with its local update capability advances player motion and local
	collision objects without remote networking */
	if (is_singleplayer
	&& variable_struct_exists(local_player, "update_singleplayer"))
	{
		local_player.update_singleplayer();
		scr_get_collision_objects().update_singleplayer(local_player);
	}

	/* Other cases use the normal client player update, including the existing fallback
	when Singleplayer lacks its dedicated update method */
	else
	{
		local_player.update_client();
	}
	network_camera_update();
}

/* In server view, route this Step to console controls instead of world/player input.
Hosted networking already advanced at the start of the event */
else
{
	server_mode_update_layout();

	/* Sample console pointer coordinates in GUI pixels and a fresh left-click.
	lifecycle_server borrows the authoritative hosting service for settings and
	restart/shutdown commands */
	var server_mouse_x_gui = device_mouse_x_to_gui(0);
	var server_mouse_y_gui = device_mouse_y_to_gui(0);
	var server_mouse_pressed = mouse_check_button_pressed(mb_left);
	var lifecycle_server = scr_get_server();

	/* Refresh displayed capacity from available server state only outside active
	player-limit editing. Preserve the typed candidate while its field has focus */
	if (server_mode_focus != "max_players"
	&& is_struct(lifecycle_server)
	&& variable_struct_exists(lifecycle_server, "max_players"))
	{
		server_max_players_text = string(lifecycle_server.max_players);
	}

	/* Console hover flags test each current GUI rectangle: username_input for local
	name editing, join for entering owned play, shutdown/restart for lifecycle actions,
	reset_toggle/minus/plus for scheduling, max_players_input/apply for capacity,
	and wall_toggle for wall policy. server_mode_button_hover mirrors Shutdown */
	server_username_input_hover = server_mouse_x_gui >= server_username_input_x
		&& server_mouse_x_gui <= server_username_input_x + server_username_input_width
		&& server_mouse_y_gui >= server_username_input_y
		&& server_mouse_y_gui <= server_username_input_y + server_username_input_height;
	server_join_button_hover = server_mouse_x_gui >= server_join_button_x
		&& server_mouse_x_gui <= server_join_button_x + server_join_button_width
		&& server_mouse_y_gui >= server_join_button_y
		&& server_mouse_y_gui <= server_join_button_y + server_join_button_height;
	server_shutdown_button_hover = server_mouse_x_gui >= server_shutdown_button_x
		&& server_mouse_x_gui <= server_shutdown_button_x + server_shutdown_button_width
		&& server_mouse_y_gui >= server_shutdown_button_y
		&& server_mouse_y_gui <= server_shutdown_button_y + server_shutdown_button_height;
	server_restart_button_hover = server_mouse_x_gui >= server_restart_button_x
		&& server_mouse_x_gui <= server_restart_button_x + server_restart_button_width
		&& server_mouse_y_gui >= server_restart_button_y
		&& server_mouse_y_gui <= server_restart_button_y + server_restart_button_height;
	server_reset_toggle_button_hover = server_mouse_x_gui >= server_reset_toggle_button_x
		&& server_mouse_x_gui <= server_reset_toggle_button_x + server_reset_toggle_button_width
		&& server_mouse_y_gui >= server_reset_toggle_button_y
		&& server_mouse_y_gui <= server_reset_toggle_button_y + server_reset_toggle_button_height;
	server_reset_minus_button_hover = server_mouse_x_gui >= server_reset_minus_button_x
		&& server_mouse_x_gui <= server_reset_minus_button_x + server_reset_minus_button_width
		&& server_mouse_y_gui >= server_reset_minus_button_y
		&& server_mouse_y_gui <= server_reset_minus_button_y + server_reset_minus_button_height;
	server_reset_plus_button_hover = server_mouse_x_gui >= server_reset_plus_button_x
		&& server_mouse_x_gui <= server_reset_plus_button_x + server_reset_plus_button_width
		&& server_mouse_y_gui >= server_reset_plus_button_y
		&& server_mouse_y_gui <= server_reset_plus_button_y + server_reset_plus_button_height;
	server_max_players_input_hover = server_mouse_x_gui >= server_max_players_input_x
		&& server_mouse_x_gui <= server_max_players_input_x + server_max_players_input_width
		&& server_mouse_y_gui >= server_max_players_input_y
		&& server_mouse_y_gui <= server_max_players_input_y + server_max_players_input_height;
	server_max_players_apply_button_hover = server_mouse_x_gui >= server_max_players_apply_button_x
		&& server_mouse_x_gui <= server_max_players_apply_button_x + server_max_players_apply_button_width
		&& server_mouse_y_gui >= server_max_players_apply_button_y
		&& server_mouse_y_gui <= server_max_players_apply_button_y + server_max_players_apply_button_height;
	server_wall_toggle_button_hover = point_in_rect(server_mouse_x_gui, server_mouse_y_gui, server_wall_toggle_button_x, server_wall_toggle_button_y, server_wall_toggle_button_x + server_wall_toggle_button_width, server_wall_toggle_button_y + server_wall_toggle_button_height);
	server_mode_button_hover = server_shutdown_button_hover;

	/* A fresh console pointer click changes text focus or discards an edit.
	Pointer motion alone leaves the keyboard's current owner unchanged */
	if (server_mouse_pressed)
	{
		/* Clicking capacity input focuses its current candidate and loads the keyboard buffer */
		if (server_max_players_input_hover)
		{
			server_mode_focus = "max_players";
			keyboard_string = server_max_players_text;
		}

		/* A username-field click instead focuses the local-play name and loads that text */
		else if (server_username_input_hover)
		{
			server_mode_focus = "username";
			keyboard_string = client_username;
		}

		/* Clicks outside Apply clear editing focus. A clicked Apply preserves its capacity
		candidate until the commit path validates it */
		else if (!server_max_players_apply_button_hover)
		{
			/* When leaving capacity editing with available server state, restore the committed
			limit before clearing focus. Missing state leaves the existing display text */
			if (server_mode_focus == "max_players"
			&& is_struct(lifecycle_server)
			&& variable_struct_exists(lifecycle_server, "max_players"))
			{
				server_max_players_text = string(lifecycle_server.max_players);
			}
			server_mode_focus = "";
			keyboard_string = "";
		}
	}

	/* Only the focused username consumes shared text with the 24-character limit.
	Remove line breaks and unsupported name characters before applying its candidate */
	if (server_mode_focus == "username")
	{
		scr_text_input_update("server_username", client_username, 24);

		/* server_typed_username begins with the current keyboard text before filtering
		produces the console's candidate local-play name */
		var server_typed_username = keyboard_string;
		server_typed_username = string_replace_all(server_typed_username, "\r", "");
		server_typed_username = string_replace_all(server_typed_username, "\n", "");
		server_typed_username = chat_filter_username_input(server_typed_username);

		/* Apply only a changed filtered name and align the keyboard buffer.
		Its validation result selects ready-to-join feedback or the specific naming error */
		if (server_typed_username != client_username)
		{
			client_username = server_typed_username;
			keyboard_string = client_username;
			server_mode_status = client_username_is_ready()
				? "Ready to join without stopping the server."
				: client_username_validation_message(client_username);
		}
	}

	/* The alternative focused capacity field consumes and filters numeric limit text.
	An unfocused console keeps both text fields unchanged */
	else if (server_mode_focus == "max_players")
	{
		scr_text_input_update("server_max_players", server_max_players_text);

		/* server_filtered_max_players is the candidate after the existing whole-number
		input filter removes unsupported keyboard characters */
		var server_filtered_max_players = max_players_filter_input(keyboard_string);
		server_max_players_text = server_filtered_max_players;

		/* Replace the keyboard buffer only when filtering changed it, keeping later input
		aligned with the displayed capacity candidate */
		if (string(keyboard_string) != server_filtered_max_players)
		{
			keyboard_string = server_filtered_max_players;
		}
	}

	/* Expire console restart confirmation after its current_time millisecond deadline.
	Zero means another click must begin a new confirmation rather than restarting */
	if (current_time > server_restart_confirm_until)
	{
		server_restart_confirm_until = 0;
	}

	/* A fresh console click may operate lifecycle settings only with available hosting
	state. Missing server state leaves these click actions unprocessed */
	if (server_mouse_pressed
	&& is_struct(lifecycle_server))
	{
		/* The wall button toggles authoritative policy through its persistence-aware setter.
		Success feedback reflects the resulting enabled state and failure explains that
		saving failed. Return so no second console action uses this click */
		if (server_wall_toggle_button_hover)
		{
			server_mode_status = lifecycle_server.set_wall_drawing_enabled(!lifecycle_server.wall_drawing_enabled)
				? (lifecycle_server.wall_drawing_enabled ? "Wall drawing enabled." : "Wall drawing disabled. Walls are passable.")
				: "Could not save the wall drawing setting.";
			return;
		}

		/* Restart needs the corresponding server capability before using its independent
		two-click confirmation window */
		if (server_restart_button_hover
		&& variable_struct_exists(lifecycle_server, "request_force_restart"))
		{
			/* A click while confirmation is still active submits the console restart request.
			Clear the window afterward so it cannot authorize another restart */
			if (server_restart_confirm_until > 0)
			{
				/* restart_queued records whether hosting accepted this restart request.
				Accepted requests show archive/restart progress, while rejection reports an
				already active shutdown or restart */
				var restart_queued = lifecycle_server.request_force_restart("server_console_restart");
				server_restart_confirm_until = 0;
				server_mode_status = restart_queued
					? "Saving every drawing layer, then restarting with a blank canvas..."
					: "A shutdown or restart is already in progress.";
			}

			/* The first restart click starts a 5,000 ms current_time confirmation deadline.
			Show confirmation guidance and leave the server running until another click */
			else
			{
				server_restart_confirm_until = current_time + 5000;
				server_mode_status = "Click restart again within 5 seconds to confirm.";
			}
			return;
		}

		/* The reset-toggle button uses available scheduling support with the opposite
		current enabled state. The returned enabled state controls its feedback */
		if (server_reset_toggle_button_hover
		&& variable_struct_exists(lifecycle_server, "set_automatic_reset_enabled"))
		{
			/* reset_enabled_now is the resulting scheduling flag, rather than a persistence
			success indicator. True reports scheduled resets and false reports unlimited time */
			var reset_enabled_now = lifecycle_server.set_automatic_reset_enabled(!lifecycle_server.automatic_reset_enabled);
			server_mode_status = reset_enabled_now
				? "Automatic drawing reset enabled."
				: "Drawing reset timer set to unlimited.";
			return;
		}

		/* Minus uses available scheduling support to shorten the interval by the server's
		configured minute step. Its setter bounds/persists the value before feedback */
		if (server_reset_minus_button_hover
		&& variable_struct_exists(lifecycle_server, "adjust_automatic_reset_minutes"))
		{
			lifecycle_server.adjust_automatic_reset_minutes(-lifecycle_server.automatic_reset_step_minutes);
			server_mode_status = "Reset interval: " + server_reset_duration_text(lifecycle_server.automatic_reset_interval_minutes * 60) + ".";
			return;
		}

		/* Plus uses the same configured minute step to extend reset scheduling.
		Report the resulting interval as a human-readable duration after the setter */
		if (server_reset_plus_button_hover
		&& variable_struct_exists(lifecycle_server, "adjust_automatic_reset_minutes"))
		{
			lifecycle_server.adjust_automatic_reset_minutes(lifecycle_server.automatic_reset_step_minutes);
			server_mode_status = "Reset interval: " + server_reset_duration_text(lifecycle_server.automatic_reset_interval_minutes * 60) + ".";
			return;
		}
	}

	/* Escape while capacity editing cancels that candidate and consumes the Step.
	Reset held-exit state so cancelling text does not also stop hosting */
	if (server_mode_focus == "max_players" && keyboard_check_pressed(vk_escape))
	{
		/* Available server capacity restores the committed text on edit cancellation.
		Missing server metadata leaves the current field text before focus is cleared */
		if (is_struct(lifecycle_server)
		&& variable_struct_exists(lifecycle_server, "max_players"))
		{
			server_max_players_text = string(lifecycle_server.max_players);
		}
		server_mode_focus = "";
		keyboard_string = "";
		escape_exit_hold_reset();
		return;
	}

	/* server_max_players_apply_requested combines a clicked Apply button with Enter
	while capacity editing. It only requests validation and does not imply success */
	var server_max_players_apply_requested = (server_max_players_apply_button_hover && server_mouse_pressed)
		|| (server_mode_focus == "max_players" && keyboard_check_pressed(vk_enter));

	/* A requested capacity commit enters validation and ends this console Step.
	Without a commit request, later name/join/shutdown controls remain available */
	if (server_max_players_apply_requested)
	{
		/* Borrow network policy for the permitted whole-number player-limit range */
		var server_net = scr_get_network();

		/* Invalid capacity text shows the network's allowed range without changing server
		capacity or clearing the candidate needed for correction */
		if (!max_players_input_is_valid(server_max_players_text))
		{
			server_mode_status = "Enter a whole number from " + string(server_net.min_player_limit)
				+ " to " + string(server_net.max_player_limit) + ".";
		}

		/* A valid candidate still needs available server state and its capacity setter.
		Missing support produces feedback instead of attempting a mutation */
		else if (!is_struct(lifecycle_server)
		|| !variable_struct_exists(lifecycle_server, "set_max_players"))
		{
			server_mode_status = "Maximum player controls are unavailable.";
		}

		/* With valid text and available setter support, compare the candidate to committed
		capacity before deciding whether a persistence update is needed */
		else
		{
			/* requested_max_players is the validated candidate converted to its player-count value */
			var requested_max_players = max_players_input_value(server_max_players_text);

			/* An unchanged limit needs no save or broadcast. Report its existing value and
			clear text focus so keyboard input returns to console actions */
			if (requested_max_players == lifecycle_server.max_players)
			{
				server_mode_status = "Maximum players is already set to " + string(requested_max_players) + ".";
				server_mode_focus = "";
				keyboard_string = "";
			}

			/* Only a successful capacity setter updates the displayed committed value and
			clears editing focus. The setter retains the old limit when persistence fails */
			else if (lifecycle_server.set_max_players(requested_max_players))
			{
				server_max_players_text = string(lifecycle_server.max_players);
				server_mode_status = "Maximum players set to " + string(lifecycle_server.max_players) + ".";

				/* When current occupancy exceeds the new capacity, explain that existing players
				remain and new joins pause. Lowering the limit does not evict current slots */
				if (lifecycle_server.connected_players > lifecycle_server.max_players)
				{
					server_mode_status = "Limit set to " + string(lifecycle_server.max_players)
						+ ". Existing players stay; new joins are paused.";
				}
				server_mode_focus = "";
				keyboard_string = "";
			}

			/* A failed capacity save reports that the previous limit remains, preserving the
			candidate field so the user can correct or retry it */
			else
			{
				server_mode_status = "Could not save the player limit. Previous limit kept.";
			}
		}
		return;
	}

	/* server_username_ready records local-play name validity. server_join_requested
	combines a clicked Join, J outside text editing, or Enter in the name field,
	allowing explicit play entry without consuming letters typed into another field */
	var server_username_ready = client_username_is_ready();
	var server_join_requested = (server_join_button_hover && server_mouse_pressed)
		|| (server_mode_focus == "" && keyboard_check_pressed(ord("J")))
		|| (server_mode_focus == "username" && keyboard_check_pressed(vk_enter));

	/* A requested owned-server join validates the name before changing mode.
	Return after handling it so the same input cannot also shut down hosting */
	if (server_join_requested)
	{
		/* An invalid name shows its validation error and focuses username entry.
		Do not create the local player connection until the name is ready */
		if (!server_username_ready)
		{
			server_mode_status = client_username_validation_message(client_username);
			server_mode_focus = "username";
			keyboard_string = client_username;
		}

		/* A valid local-play name allows joining the owned server while hosting remains active */
		else
		{
			network_join_owned_server();
		}
		return;
	}

	/* Escape in username editing clears text focus and held-exit progress.
	Consume this Step so leaving the field cannot also stop the server */
	if (server_mode_focus == "username" && keyboard_check_pressed(vk_escape))
	{
		server_mode_focus = "";
		keyboard_string = "";
		escape_exit_hold_reset();
		return;
	}

	/* A completed held-Escape shutdown outside text focus, or a clicked Shutdown,
	ends hosted-server mode through its cleanup path before returning */
	if (escape_exit_hold_update("server_mode", server_mode_focus == "")
	|| (server_shutdown_button_hover && server_mouse_pressed))
	{
		network_shutdown_hosted_server();
		return;
	}

	/* Borrow drawing state for console-specific archive/input controls */
	var server_drawing_ui = scr_get_drawing();

	/* Only an unfocused console with available drawing input support handles its
	server drawing commands. Text editing retains keyboard ownership instead */
	if (server_mode_focus == ""
	&& is_struct(server_drawing_ui)
	&& variable_struct_exists(server_drawing_ui, "update_server_input"))
	{
		server_drawing_ui.update_server_input();
	}
}
