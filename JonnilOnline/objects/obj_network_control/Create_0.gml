/// @description Initialize network modes, connection menus, camera controls, and startup selection

#region /* Network Controller State */
/* Keep this controller across room transitions so connection, menu, and camera state survive the
active room */
persistent = true;

/* net borrows the shared network configuration for initial player limits and runtime capabilities */
var net = scr_get_network();

/* game_version records the formatted build date and game_version_label prefixes it for captions.
network_window_role and network_last_caption start empty before the first caption is assembled */
game_version = scr_get_build_date(true, true);
game_version_label = "v" + game_version;
network_window_role = "";
network_last_caption = "";
/// @description Update the OS caption only when role, client identity, or build label changes
/// @param {String} role Window role normalized to uppercase, defaulting to empty when omitted
/// @returns {Any} No explicit return value
network_update_window_caption = function(role = "")
{
	network_window_role = string_upper(string_trim(string(role)));

	/* caption starts with the shared game name and accumulates the current role, player identity, and
	build label */
	var caption = string(scr_get_network().game_name);

	/* A nonempty role is appended so the OS caption identifies this window's active network purpose */
	if (network_window_role != "")
	{
		caption += " " + network_window_role;
	}

	/* Client-facing roles include the player's username and slot, while a dedicated server caption
	does not need player identity */
	if (network_window_role == "CLIENT"
	|| network_window_role == "HOST & PLAY"
	|| network_window_role == "SINGLEPLAYER")
	{
		/* client borrows the connection manager. caption_username starts empty and caption_slot starts
		noone until available identity fields supply values */
		var client = scr_get_client();
		var caption_username = "";
		var caption_slot = noone;

		/* Read identity fields only from a valid client struct */
		if (is_struct(client))
		{
			/* Prefer the server-assigned nonempty username so the caption uses the identity actually
			accepted by the session */
			if (variable_struct_exists(client, "assigned_username")
			&& string_trim(string(client.assigned_username)) != "")
			{
				caption_username = string(client.assigned_username);
			}

			/* Without an assigned name, use a nonempty requested username while connection assignment
			is pending */
			else if (variable_struct_exists(client, "requested_username")
			&& string_trim(string(client.requested_username)) != "")
			{
				caption_username = string(client.requested_username);
			}

			/* An available ID provides the current player slot for the debug identity label */
			if (variable_struct_exists(client, "ID"))
			{
				caption_slot = client.ID;
			}
		}

		/* Append a resolved username only when one was available, avoiding an empty identity segment */
		if (caption_username != "")
		{
			caption += " " + caption_username;
		}

		caption += " " + scr_network_debug_id_text(caption_slot);
	}
	caption += " " + game_version_label;

	/* Only a changed complete caption reaches the OS setter, keeping per-frame caption checks from
	repeating the same update */
	if (caption != network_last_caption)
	{
		network_last_caption = caption;
		window_set_caption(caption); /* Keep the current network role and identity visible in the OS window caption */
	}
}
network_update_window_caption();

/* running_in_browser and running_on_gxgames independently detect the browser and GX.games runtime
paths used by later startup selection */
var running_in_browser = os_browser != browser_not_a_browser;
var running_on_gxgames = os_type == os_gxgames;

/* is_client starts in client presentation and is_singleplayer starts false. is_hosting_server records
server ownership, host_play_active records an owned local player, and host_claim_pending tracks its
pending slot claim, all initially inactive */
is_client = true;
is_singleplayer = false;
is_hosting_server = false;
host_play_active = false;
host_claim_pending = false;

/* host_session_menu_open and network_mode_screen start closed until startup or session input chooses a
menu */
host_session_menu_open = false;
network_mode_screen = false;

/* network_startup_mode, network_startup_connect_address, and network_startup_username start empty
before environment and argument parsing. network_pending_direct_connect_address holds a deferred
direct join and also starts empty */
network_startup_mode = "";
network_startup_connect_address = "";
network_startup_username = "";
network_pending_direct_connect_address = "";

/* client_username_persistence_suppressed starts false so ordinary profile edits persist.
managed_dedicated_server starts false until startup identifies an externally managed server */
client_username_persistence_suppressed = false;
managed_dedicated_server = false;

/* network_mode_page starts main, network_mode_hover_button starts empty, and network_mode_title/status
supply the initial chooser heading and guidance */
network_mode_page = "main";
network_mode_hover_button = "";
network_mode_title = "Choose Network Mode";
network_mode_status = "Host a server or join as a client.";

/* Offer Quit only when the network runtime reports a native application that can close its window */
network_mode_show_quit = !net.is_browser_runtime();

/* network_mode_panel_x/y/width/height start zero until layout computes the chooser's GUI bounds */
network_mode_panel_x = 0;
network_mode_panel_y = 0;
network_mode_panel_width = 0;
network_mode_panel_height = 0;

/* network_mode_focus starts on the username field for keyboard input */
network_mode_focus = "username";

/* network_mode_username_input_x/y/width start unplaced and height starts 42 GUI pixels for the chooser
profile field */
network_mode_username_input_x = 0;
network_mode_username_input_y = 0;
network_mode_username_input_width = 0;
network_mode_username_input_height = 42;

/* network_mode_host_button_x/y/width start unplaced and height starts 52 GUI pixels for the main Host
action */
network_mode_host_button_x = 0;
network_mode_host_button_y = 0;
network_mode_host_button_width = 0;
network_mode_host_button_height = 52;

/* network_mode_server_button_x/y/width start unplaced and height starts 52 GUI pixels for dedicated
hosting on the host page */
network_mode_server_button_x = 0;
network_mode_server_button_y = 0;
network_mode_server_button_width = 0;
network_mode_server_button_height = 52;

/* network_mode_host_play_button_x/y/width start unplaced and height starts 52 GUI pixels for hosting
with a local player */
network_mode_host_play_button_x = 0;
network_mode_host_play_button_y = 0;
network_mode_host_play_button_width = 0;
network_mode_host_play_button_height = 52;

/* network_mode_client_button_x/y/width start unplaced and height starts 52 GUI pixels for the
join-server action */
network_mode_client_button_x = 0;
network_mode_client_button_y = 0;
network_mode_client_button_width = 0;
network_mode_client_button_height = 52;

/* network_mode_singleplayer_button_x/y/width start unplaced and height starts 42 GUI pixels for local
play */
network_mode_singleplayer_button_x = 0;
network_mode_singleplayer_button_y = 0;
network_mode_singleplayer_button_width = 0;
network_mode_singleplayer_button_height = 42;

/* network_mode_options_button_x/y/width start unplaced and height starts 42 GUI pixels for appearance
and performance settings */
network_mode_options_button_x = 0;
network_mode_options_button_y = 0;
network_mode_options_button_width = 0;
network_mode_options_button_height = 42;

/* network_mode_quit_button_x/y/width start unplaced and height starts 42 GUI pixels for the native
Quit action */
network_mode_quit_button_x = 0;
network_mode_quit_button_y = 0;
network_mode_quit_button_width = 0;
network_mode_quit_button_height = 42;

/* network_mode_back_button_x/y/width start unplaced and height starts 42 GUI pixels for returning from
the host page */
network_mode_back_button_x = 0;
network_mode_back_button_y = 0;
network_mode_back_button_width = 0;
network_mode_back_button_height = 42;

/* network_mode_information_button_x/y start unplaced with a 42-by-42 GUI-pixel control for the
information menu */
network_mode_information_button_x = 0;
network_mode_information_button_y = 0;
network_mode_information_button_width = 42;
network_mode_information_button_height = 42;

/* network_mode_performance_warning_visible starts false, x/y/width await layout, and height reserves
46 GUI pixels for browser acceleration guidance */
network_mode_performance_warning_visible = false;
network_mode_performance_warning_x = 0;
network_mode_performance_warning_y = 0;
network_mode_performance_warning_width = 0;
network_mode_performance_warning_height = 46;

/* network_mode_gamepad_focus starts at Host and network_mode_gamepad_navigation_due starts zero so the
first directional input is immediately eligible */
network_mode_gamepad_focus = "host";
network_mode_gamepad_navigation_due = 0;

/* information_screen_open starts closed, information_hover_button empty, information_focus at What's
New, and information_gamepad_navigation_due zero for immediate initial navigation */
information_screen_open = false;
information_hover_button = "";
information_focus = "whats_new";
information_gamepad_navigation_due = 0;

/* information_panel_x/y/width/height start zero until the information layout centers its GUI panel */
information_panel_x = 0;
information_panel_y = 0;
information_panel_width = 0;
information_panel_height = 0;

/* information_whats_new_button_x/y/width start unplaced and height starts 42 GUI pixels for opening
update notes */
information_whats_new_button_x = 0;
information_whats_new_button_y = 0;
information_whats_new_button_width = 0;
information_whats_new_button_height = 42;

/* information_back_button_x/y/width start unplaced and height starts 42 GUI pixels for closing the
information menu */
information_back_button_x = 0;
information_back_button_y = 0;
information_back_button_width = 0;
information_back_button_height = 42;

/* Global text diagnostics start with overlay and forced-white text disabled, while
text_canvas_safe_palette starts enabled for drawing-safe text colours */
global.text_debug_overlay = false;
global.text_debug_force_white = false;
global.text_canvas_safe_palette = true;
scr_get_player_characters().load_selected_key();
scr_get_pets().load_selected_key();

/* client_device_name first uses COMPUTERNAME to label this runtime's device without affecting its
multiplayer username */
client_device_name = string_trim(environment_get_variable("COMPUTERNAME"));

/* An empty Windows computer name falls back to HOSTNAME for other native environments */
if (client_device_name == "")
{
	client_device_name = string_trim(environment_get_variable("HOSTNAME"));
}

/* If neither environment field provides a name, a readable Unknown device fallback keeps the device
label nonempty */
if (client_device_name == "")
{
	client_device_name = "Unknown device";
}

/* Names beyond 28 characters are shortened with an ellipsis so the device label stays within menu
space */
if (string_length(client_device_name) > 28)
{
	client_device_name = string_copy(client_device_name, 1, 28) + "...";
}

/* client_device_label stores the readable device caption. client_join_screen starts closed,
client_join_address and client_username start empty, and client_join_focus/error/status start
without active input or feedback */
client_device_label = "Device: " + client_device_name;
client_join_screen = false;
client_join_address = "";
client_username = "";
client_join_focus = "";
client_join_error = "";
client_join_status = "";

/* client_join_button_hover starts false, client_join_hover_button empty, client_join_hover_row and
client_join_selected noone, and client_join_scroll zero before any server rows are selected or
displayed */
client_join_button_hover = false;
client_join_hover_button = "";
client_join_hover_row = noone;
client_join_selected = noone;
client_join_scroll = 0;

/* client_join_direct_mode starts false. client_join_dialog, name, and address start empty,
dialog_index starts noone, dialog_focus starts Name, and dialog_hover starts empty for saved-server
editing */
client_join_direct_mode = false;
client_join_dialog = "";
client_join_dialog_index = noone;
client_join_dialog_name = "";
client_join_dialog_address = "";
client_join_dialog_focus = "name";
client_join_dialog_hover = "";

/* client_join_action_focus starts Join, while client_join_edit_enabled starts false until a saved
server is selected */
client_join_action_focus = "join";
client_join_edit_enabled = false;

/* client_join_dialog_x/y/width and its name/address/button row y positions start unplaced, with a
340-GUI-pixel initial dialog height */
client_join_dialog_x = 0;
client_join_dialog_y = 0;
client_join_dialog_width = 0;
client_join_dialog_height = 340;
client_join_dialog_name_y = 0;
client_join_dialog_address_y = 0;
client_join_dialog_button_y = 0;

/* client_join_add_button_x/y/width start unplaced for creating a saved server */
client_join_add_button_x = 0;
client_join_add_button_y = 0;
client_join_add_button_width = 0;

/* client_join_edit_button_x/y/width start unplaced for editing a selected saved server */
client_join_edit_button_x = 0;
client_join_edit_button_y = 0;
client_join_edit_button_width = 0;

/* client_join_delete_button_x/y/width start unplaced for removing a selected saved server */
client_join_delete_button_x = 0;
client_join_delete_button_y = 0;
client_join_delete_button_width = 0;

/* client_join_last_click_row starts noone and last_click_time zero before double-click tracking.
client_join_join_enabled starts false until a usable server is selected */
client_join_last_click_row = noone;
client_join_last_click_time = 0;
client_join_join_enabled = false;

/* client_join_panel_x/y/width/height start zero until layout fits the server list to the GUI */
client_join_panel_x = 0;
client_join_panel_y = 0;
client_join_panel_width = 0;
client_join_panel_height = 0;

/* client_join_list_x/y/width/height start unplaced and row_height fixes each visible server row at 68
GUI pixels */
client_join_list_x = 0;
client_join_list_y = 0;
client_join_list_width = 0;
client_join_list_height = 0;
client_join_row_height = 68;

/* client_join_input_x/y/width start unplaced and height reserves 42 GUI pixels for the address field */
client_join_input_x = 0;
client_join_input_y = 0;
client_join_input_width = 0;
client_join_input_height = 42;

/* client_username_input_x/y/width start unplaced and height reserves 42 GUI pixels for the legacy
join-screen username region */
client_username_input_x = 0;
client_username_input_y = 0;
client_username_input_width = 0;
client_username_input_height = 42;

/* client_join_button_x/y/width start unplaced and height starts 38 GUI pixels for joining the selected
server */
client_join_button_x = 0;
client_join_button_y = 0;
client_join_button_width = 0;
client_join_button_height = 38;

/* client_join_direct_button_x/y/width start unplaced and height starts 38 GUI pixels for the
direct-address dialog */
client_join_direct_button_x = 0;
client_join_direct_button_y = 0;
client_join_direct_button_width = 0;
client_join_direct_button_height = 38;

/* client_join_refresh_button_x/y/width start unplaced and height starts 38 GUI pixels for refreshing
discovered servers */
client_join_refresh_button_x = 0;
client_join_refresh_button_y = 0;
client_join_refresh_button_width = 0;
client_join_refresh_button_height = 38;

/* client_join_back_button_x/y/width start unplaced and height starts 38 GUI pixels for returning to
mode selection */
client_join_back_button_x = 0;
client_join_back_button_y = 0;
client_join_back_button_width = 0;
client_join_back_button_height = 38;

/* client_leave_button_x/y start unplaced, width/height reserve 150 by 34 GUI pixels, and hover starts
false for the active client session's leave control */
client_leave_button_x = 0;
client_leave_button_y = 0;
client_leave_button_width = 150;
client_leave_button_height = 34;
client_leave_button_hover = false;

/* server_mode_button_x starts zero and y starts 16, width/height reserve 150 by 34 GUI pixels, and
hover starts false for the legacy console exit rectangle */
server_mode_button_x = 0;
server_mode_button_y = 16;
server_mode_button_width = 150;
server_mode_button_height = 34;
server_mode_button_hover = false;

/* server_join_button_x/y start unplaced, width/height reserve 260 by 40 GUI pixels, and hover starts
false for joining this owned server as a local player */
server_join_button_x = 0;
server_join_button_y = 0;
server_join_button_width = 260;
server_join_button_height = 40;
server_join_button_hover = false;

/* server_shutdown_button_x/y start unplaced, width/height reserve 260 by 40 GUI pixels, and hover
starts false for stopping the owned server */
server_shutdown_button_x = 0;
server_shutdown_button_y = 0;
server_shutdown_button_width = 260;
server_shutdown_button_height = 40;
server_shutdown_button_hover = false;

/* server_restart_button_x/y start unplaced, width/height reserve 260 by 40 GUI pixels, and hover
starts false. server_restart_confirm_until starts zero before any millisecond confirmation window */
server_restart_button_x = 0;
server_restart_button_y = 0;
server_restart_button_width = 260;
server_restart_button_height = 40;
server_restart_button_hover = false;
server_restart_confirm_until = 0;

/* server_reset_toggle_button_x/y start unplaced, width/height reserve 260 by 34 GUI pixels, and hover
starts false for toggling scheduled resets */
server_reset_toggle_button_x = 0;
server_reset_toggle_button_y = 0;
server_reset_toggle_button_width = 260;
server_reset_toggle_button_height = 34;
server_reset_toggle_button_hover = false;

/* server_reset_minus_button_x/y start unplaced, width/height reserve 125 by 34 GUI pixels, and hover
starts false for reducing the reset interval */
server_reset_minus_button_x = 0;
server_reset_minus_button_y = 0;
server_reset_minus_button_width = 125;
server_reset_minus_button_height = 34;
server_reset_minus_button_hover = false;

/* server_reset_plus_button_x/y start unplaced, width/height reserve 125 by 34 GUI pixels, and hover
starts false for increasing the reset interval */
server_reset_plus_button_x = 0;
server_reset_plus_button_y = 0;
server_reset_plus_button_width = 125;
server_reset_plus_button_height = 34;
server_reset_plus_button_hover = false;

/* server_max_players_input_x/y start unplaced, width/height reserve 150 by 38 GUI pixels, and hover
starts false for editing the player-capacity draft */
server_max_players_input_x = 0;
server_max_players_input_y = 0;
server_max_players_input_width = 150;
server_max_players_input_height = 38;
server_max_players_input_hover = false;

/* server_max_players_apply_button_x/y start unplaced, width/height reserve 100 by 38 GUI pixels, and
hover starts false for applying the capacity draft */
server_max_players_apply_button_x = 0;
server_max_players_apply_button_y = 0;
server_max_players_apply_button_width = 100;
server_max_players_apply_button_height = 38;
server_max_players_apply_button_hover = false;

/* server_max_players_text begins with the network's default player capacity rendered as editable
decimal text */
server_max_players_text = string(net.default_max_players);

/* server_wall_toggle_button_x/y start unplaced, width/height reserve 260 by 34 GUI pixels, and hover
starts false for toggling room walls */
server_wall_toggle_button_x = 0;
server_wall_toggle_button_y = 0;
server_wall_toggle_button_width = 260;
server_wall_toggle_button_height = 34;
server_wall_toggle_button_hover = false;

/* server_username_input_x/y start unplaced, width/height reserve 260 by 42 GUI pixels, and hover
starts false. server_mode_focus/status start empty before console input or feedback */
server_username_input_x = 0;
server_username_input_y = 0;
server_username_input_width = 260;
server_username_input_height = 42;
server_username_input_hover = false;
server_mode_focus = "";
server_mode_status = "";

/* host_menu_panel_x/y start unplaced with a 420-by-292 GUI-pixel initial panel for the owned-session
pause menu */
host_menu_panel_x = 0;
host_menu_panel_y = 0;
host_menu_panel_width = 420;
host_menu_panel_height = 292;

/* host_menu_resume_button_x/y/width start unplaced and height starts 42 GUI pixels for resuming local
host play */
host_menu_resume_button_x = 0;
host_menu_resume_button_y = 0;
host_menu_resume_button_width = 0;
host_menu_resume_button_height = 42;

/* host_menu_wall_button_x/y/width start unplaced and height starts 42 GUI pixels, while wall_feedback
starts empty before changing owned-session walls */
host_menu_wall_button_x = 0;
host_menu_wall_button_y = 0;
host_menu_wall_button_width = 0;
host_menu_wall_button_height = 42;
host_menu_wall_feedback = "";

/* host_menu_return_button_x/y/width start unplaced and height starts 42 GUI pixels for returning the
local player to the server console */
host_menu_return_button_x = 0;
host_menu_return_button_y = 0;
host_menu_return_button_width = 0;
host_menu_return_button_height = 42;

/* host_menu_shutdown_button_x/y/width start unplaced and height starts 42 GUI pixels for ending the
owned server. host_menu_hover_button starts empty */
host_menu_shutdown_button_x = 0;
host_menu_shutdown_button_y = 0;
host_menu_shutdown_button_width = 0;
host_menu_shutdown_button_height = 42;
host_menu_hover_button = "";

/* official_admin_controls_open and logs_open start closed, hover_button and focus start empty,
restart/reset confirmation deadlines start zero, next_refresh_at starts zero for immediate refresh,
and max_players_text starts at the default capacity */
official_admin_controls_open = false;
official_admin_logs_open = false;
official_admin_hover_button = "";
official_admin_restart_confirm_until = 0;
official_admin_reset_confirm_until = 0;
official_admin_next_refresh_at = 0;
official_admin_focus = "";
official_admin_max_players_text = string(net.default_max_players);

/* official_admin_panel_x/y start unplaced with a 520-by-536 GUI-pixel initial administration panel */
official_admin_panel_x = 0;
official_admin_panel_y = 0;
official_admin_panel_width = 520;
official_admin_panel_height = 536;

/* official_admin_toggle_button_x/y/width start unplaced and height starts 40 GUI pixels for
scheduled-reset enablement */
official_admin_toggle_button_x = 0;
official_admin_toggle_button_y = 0;
official_admin_toggle_button_width = 0;
official_admin_toggle_button_height = 40;

/* official_admin_minus_button_x/y/width start unplaced and height starts 36 GUI pixels for reducing
the official server reset interval */
official_admin_minus_button_x = 0;
official_admin_minus_button_y = 0;
official_admin_minus_button_width = 0;
official_admin_minus_button_height = 36;

/* official_admin_plus_button_x/y/width start unplaced and height starts 36 GUI pixels for increasing
the official server reset interval */
official_admin_plus_button_x = 0;
official_admin_plus_button_y = 0;
official_admin_plus_button_width = 0;
official_admin_plus_button_height = 36;

/* official_admin_max_players_input_x/y/width start unplaced and height starts 38 GUI pixels for the
official capacity draft */
official_admin_max_players_input_x = 0;
official_admin_max_players_input_y = 0;
official_admin_max_players_input_width = 0;
official_admin_max_players_input_height = 38;

/* official_admin_max_players_apply_button_x/y/width start unplaced and height starts 38 GUI pixels for
applying official player capacity */
official_admin_max_players_apply_button_x = 0;
official_admin_max_players_apply_button_y = 0;
official_admin_max_players_apply_button_width = 0;
official_admin_max_players_apply_button_height = 38;

/* official_admin_wall_button_x/y/width start unplaced and height starts 36 GUI pixels for toggling
official room walls */
official_admin_wall_button_x = 0;
official_admin_wall_button_y = 0;
official_admin_wall_button_width = 0;
official_admin_wall_button_height = 36;

/* official_admin_reset_button_x/y/width start unplaced and height starts 40 GUI pixels for an
immediate official reset */
official_admin_reset_button_x = 0;
official_admin_reset_button_y = 0;
official_admin_reset_button_width = 0;
official_admin_reset_button_height = 40;

/* official_admin_refresh_button_x/y/width start unplaced and height starts 36 GUI pixels for
refreshing official server status */
official_admin_refresh_button_x = 0;
official_admin_refresh_button_y = 0;
official_admin_refresh_button_width = 0;
official_admin_refresh_button_height = 36;

/* official_admin_logs_button_x/y/width start unplaced for opening logs. logs_download_button_y,
logs_folder_button_y, and logs_back_button_y start zero until the log view lays out its rows */
official_admin_logs_button_x = 0;
official_admin_logs_button_y = 0;
official_admin_logs_button_width = 0;
official_admin_logs_download_button_y = 0;
official_admin_logs_folder_button_y = 0;
official_admin_logs_back_button_y = 0;

/* official_admin_restart_button_x/y/width start unplaced and height starts 44 GUI pixels for
restarting the official server */
official_admin_restart_button_x = 0;
official_admin_restart_button_y = 0;
official_admin_restart_button_width = 0;
official_admin_restart_button_height = 44;

/* official_admin_back_button_x/y/width start unplaced and height starts 40 GUI pixels for closing
administration controls */
official_admin_back_button_x = 0;
official_admin_back_button_y = 0;
official_admin_back_button_width = 0;
official_admin_back_button_height = 40;

/* official_admin_leave_button_x/y/width start unplaced and height starts 40 GUI pixels for leaving the
administered session */
official_admin_leave_button_x = 0;
official_admin_leave_button_y = 0;
official_admin_leave_button_width = 0;
official_admin_leave_button_height = 40;

/* Deadlines based on current_time and hold durations are measured in milliseconds */
/* escape_exit_hold_duration_ms requires an 850-millisecond hold. started_at starts -1 for no active
hold, context starts empty, and progress starts zero before any confirmation fills */
escape_exit_hold_duration_ms = 850;
escape_exit_hold_started_at = -1;
escape_exit_hold_context = "";
escape_exit_hold_progress = 0;

/* client_dns_request_id starts noone, pending false, deadline zero, URL/display address/username
empty, port zero, transport TCP, direct-mode false, and admin-intent false before a hostname join
captures its request state */
client_dns_request_id = noone;
client_dns_pending = false;
client_dns_deadline = 0;
client_dns_pending_url = "";
client_dns_pending_port = 0;
client_dns_pending_transport = TRANSPORT_TCP;
client_dns_pending_display_address = "";
client_dns_pending_join_direct_mode = false;
client_dns_pending_username = "";
client_dns_pending_admin_intent = false;

/* client_settings_file names client_settings.ini, client_settings_section selects profile, and
client_username_key selects username for profile persistence */
client_settings_file = "client_settings.ini";
client_settings_section = "profile";
client_username_key = "username";

/* loaded_menu_button_theme starts with independent authored defaults before saved customization is
considered */
var loaded_menu_button_theme = scr_menu_button_default_theme();

/* Collision diagnostics start off. Saved local settings can enable the overlay without changing
movement, character assets, or the server's wall policy */
global.show_collision_mask = false;
try
{
	/* Only an existing settings file is opened so a first launch retains authored button defaults */
	if (file_exists(client_settings_file))
	{
		ini_open(client_settings_file);

		/* Missing diagnostic settings retain the authored Off default */
		global.show_collision_mask = ini_read_real("diagnostics", "show_collision_mask", 0) >= 1;

		/* menu_theme_customized records whether the INI explicitly enables stored appearance values
		instead of inheriting authored defaults */
		var menu_theme_customized = ini_read_real("ui_button_design", "customized", 0) >= 1;

		/* Read stored colour, shape, and transparency only for a customized theme, bounding enum
		values to their supported ranges */
		if (menu_theme_customized)
		{
			loaded_menu_button_theme.colour = ini_read_real("ui_button_design", "colour", loaded_menu_button_theme.default_colour);
			loaded_menu_button_theme.shape = clamp(round(ini_read_real("ui_button_design", "shape", loaded_menu_button_theme.shape)), JONNIL_MENU_BUTTON_RECTANGLE, JONNIL_MENU_BUTTON_ROUND);
			loaded_menu_button_theme.transparency = clamp(round(ini_read_real("ui_button_design", "transparency", loaded_menu_button_theme.transparency)), JONNIL_MENU_BUTTON_OPAQUE, JONNIL_MENU_BUTTON_INVISIBLE);
		}
		ini_close();
	}
}
catch(e)
{
	try { ini_close(); } catch(close_error) {}
	debug_error("Could not load options settings: " + string(e.message));
}

/* global.menu_button_theme owns the loaded shared appearance struct. html5_performance borrows the
shared browser-performance manager for options and warning state */
global.menu_button_theme = loaded_menu_button_theme;
html5_performance = scr_get_html5_performance();

/* options_screen_open starts closed, tab starts Appearance, focus starts Colour, hover empty,
colour_editing false, picker_drag empty, and navigation_due zero before this options session
receives input */
options_screen_open = false;
options_tab = "appearance";
options_focus = "colour";
options_hover = "";
options_colour_editing = false;
options_picker_drag = "";
options_navigation_due = 0;

/* options_draft_colour/shape/transparency copy the live theme for previews.
options_original_colour/shape/transparency keep the matching initial values for cancellation */
options_draft_colour = global.menu_button_theme.colour;
options_draft_shape = global.menu_button_theme.shape;
options_draft_transparency = global.menu_button_theme.transparency;
options_original_colour = global.menu_button_theme.colour;
options_original_shape = global.menu_button_theme.shape;
options_original_transparency = global.menu_button_theme.transparency;

/* Keep the entry overlay setting so Cancel can restore its live preview */
options_original_show_collision_mask = global.show_collision_mask;

/* options_hue, saturation, and value initialize the colour picker's byte-scaled components from its
RGB draft */
options_hue = colour_get_hue(options_draft_colour);
options_saturation = colour_get_saturation(options_draft_colour);
options_value = colour_get_value(options_draft_colour);

/* options_panel_x/y/width/height start zero before layout centers the options GUI */
options_panel_x = 0;
options_panel_y = 0;
options_panel_width = 0;
options_panel_height = 0;

/* options_hue_x/y/width start unplaced with a 24-GUI-pixel slider height. options_sv_x/y/width/height
start unplaced for the saturation/value region */
options_hue_x = 0;
options_hue_y = 0;
options_hue_width = 0;
options_hue_height = 24;
options_sv_x = 0;
options_sv_y = 0;
options_sv_width = 0;
options_sv_height = 0;

/* options_shape_y and transparency_y start unplaced. row_height sets forty GUI pixels, arrow_width
forty-eight, and row_left_x/right_x/value_x/value_width await shared cycling-row layout */
options_shape_y = 0;
options_transparency_y = 0;
options_row_height = 40;
options_arrow_width = 48;
options_row_left_x = 0;
options_row_right_x = 0;
options_row_value_x = 0;
options_row_value_width = 0;

/* options_reset_x/y/width start unplaced and height starts forty GUI pixels for appearance reset */
options_reset_x = 0;
options_reset_y = 0;
options_reset_width = 0;
options_reset_height = 40;

/* options_apply_x/y/width start unplaced and height starts forty-two GUI pixels for saving the options
session */
options_apply_x = 0;
options_apply_y = 0;
options_apply_width = 0;
options_apply_height = 42;

/* options_cancel_x/y/width start unplaced and height starts forty-two GUI pixels for restoring the
original appearance */
options_cancel_x = 0;
options_cancel_y = 0;
options_cancel_width = 0;
options_cancel_height = 42;

/* options_tab_y starts unplaced with a thirty-eight-GUI-pixel height. The three tab positions and
tab_width await layout */
options_tab_y = 0;
options_tab_height = 38;
options_appearance_tab_x = 0;
options_performance_tab_x = 0;
options_diagnostics_tab_x = 0;
options_tab_width = 0;

/* Diagnostic toggle starts unplaced and shares the options row height */
options_collision_mask_y = 0;

/* options_performance_mode_y starts unplaced for browser graphics cycling. performance_copy_x/y/width
start unplaced with a thirty-eight-GUI-pixel height for copying diagnostics */
options_performance_mode_y = 0;
options_performance_copy_x = 0;
options_performance_copy_y = 0;
options_performance_copy_width = 0;
options_performance_copy_height = 38;

/* options_performance_instructions_x/y/width start unplaced with a thirty-eight-GUI-pixel height for
browser guidance */
options_performance_instructions_x = 0;
options_performance_instructions_y = 0;
options_performance_instructions_width = 0;
options_performance_instructions_height = 38;

/* options_performance_reset_x/y/width start unplaced with a thirty-eight-GUI-pixel height for
resetting measured performance */
options_performance_reset_x = 0;
options_performance_reset_y = 0;
options_performance_reset_width = 0;
options_performance_reset_height = 38;

/* options_guidance_open and startup start false, focus starts Review, and hover starts empty before
browser acceleration guidance opens */
options_guidance_open = false;
options_guidance_startup = false;
options_guidance_focus = "review";
options_guidance_hover = "";

/* options_guidance_panel_x/y/width/height start zero before guidance layout centers the modal */
options_guidance_panel_x = 0;
options_guidance_panel_y = 0;
options_guidance_panel_width = 0;
options_guidance_panel_height = 0;

/* options_guidance_review_x/y/width start unplaced and height starts forty-six GUI pixels for
reviewing browser settings */
options_guidance_review_x = 0;
options_guidance_review_y = 0;
options_guidance_review_width = 0;
options_guidance_review_height = 46;

/* options_guidance_continue_x/y/width start unplaced and height starts forty-six GUI pixels for
continuing past startup guidance */
options_guidance_continue_x = 0;
options_guidance_continue_y = 0;
options_guidance_continue_width = 0;
options_guidance_continue_height = 46;

/* whats_new_screen_open starts closed and whats_new_loaded records whether bundled update notes were
read successfully */
whats_new_screen_open = false;
whats_new_loaded = scr_load_whats_new();

/* A missing notes file installs readable fallback text and logs the failed bundled-file load */
if (!whats_new_loaded)
{
	global.whats_new = "Update notes are not available in this build.";
	debug_error("Could not load a What's New Included File.");
}

/* whats_new_unread requires successfully loaded notes whose content has not been marked read in this
profile */
whats_new_unread = whats_new_loaded
	&& !scr_whats_new_was_read(client_settings_file, global.whats_new);

/* whats_new_scroll_offset and scroll_max start zero, can_scroll false, focus Down, hover empty, and
navigation_due zero before the notes layout determines available movement */
whats_new_scroll_offset = 0;
whats_new_scroll_max = 0;
whats_new_can_scroll = false;
whats_new_focus = "down";
whats_new_hover = "";
whats_new_navigation_due = 0;

/* whats_new_text_x/start_y/end_y/width start unplaced, text_height reserves nineteen GUI pixels, and
line_gap six for readable notes. wrapped_text starts empty and lines starts an empty row array */
whats_new_text_x = 0;
whats_new_text_start_y = 0;
whats_new_text_end_y = 0;
whats_new_text_width = 0;
whats_new_text_height = 19;
whats_new_line_gap = 6;
whats_new_wrapped_text = "";
whats_new_lines = [];

/* whats_new_button_y/width start unplaced, height reserves forty-two GUI pixels, gap ten, and
up/down/top/back_button_x start zero until the four-button row is positioned */
whats_new_button_y = 0;
whats_new_button_width = 0;
whats_new_button_height = 42;
whats_new_button_gap = 10;
whats_new_up_button_x = 0;
whats_new_down_button_x = 0;
whats_new_top_button_x = 0;
whats_new_back_button_x = 0;
#endregion /* Network Controller State END */

#region /* Profile and Player Limit Input */
/// @description Filter a username and explain empty or shorter-than-three-character input
/// @param {String} raw_username Username draft to validate
/// @returns {String} Validation explanation, or empty for an accepted filtered username
client_username_validation_message = function(raw_username)
{
	/* filtered is the username after the shared input filter has removed disallowed characters */
	var filtered = chat_filter_username_input(raw_username);

	/* An empty filtered username needs an explicit prompt before any network join can proceed */
	if (string_trim(filtered) == "")
	{
		return "Enter a username before joining.";
	}

	/* A filtered name shorter than three characters receives the minimum-length explanation */
	if (string_length(filtered) < 3)
	{
		return "Username must be at least 3 characters.";
	}

	return "";
}

/// @description Check whether the current client username passes profile validation
/// @returns {Bool} Whether the filtered name is nonempty and at least three characters long
client_username_is_ready = function()
{
	/* The current profile is ready only when username validation returns no explanatory error */
	return client_username_validation_message(client_username) == "";
}

/// @description Keep decimal digits up to the configured maximum player's digit count
/// @param {String} raw_text Capacity input draft
/// @returns {String} Bounded digit-only text
max_players_filter_input = function(raw_text)
{
	/* raw copies the input text, filtered starts empty for accepted digits, and maximum_length limits
	digit count to the configured player-limit width */
	var raw = string(raw_text);
	var filtered = "";
	var maximum_length = string_length(string(scr_get_network().max_player_limit));

	/* char_index visits each one-based input character while building the bounded numeric draft */
	for (var char_index = 1; char_index <= string_length(raw); char_index++)
	{
		/* ch is the current input character under validation */
		var ch = string_char_at(raw, char_index);

		/* Append only decimal digits while the configured digit-count limit still has space */
		if (string_pos(ch, "0123456789") > 0
		&& string_length(filtered) < maximum_length)
		{
			filtered += ch;
		}
	}
	return filtered;
}

/// @description Validate the filtered capacity draft against the network's inclusive player limits
/// @param {String} raw_text Capacity input draft
/// @returns {Bool} Whether a nonempty filtered value falls within the allowed range
max_players_input_is_valid = function(raw_text)
{
	/* filtered is the numeric-only player-capacity draft after its configured length bound */
	var filtered = max_players_filter_input(raw_text);

	/* An empty numeric draft cannot represent an acceptable player capacity */
	if (filtered == "")
	{
		return false;
	}

	/* value truncates the parsed numeric draft and input_net borrows the authoritative minimum and
	maximum player limits */
	var value = floor(real(filtered));
	var input_net = scr_get_network();

	/* Accept capacity only within the network's inclusive player-limit range */
	return value >= input_net.min_player_limit && value <= input_net.max_player_limit;
}

/// @description Parse bounded digit-only capacity text without applying the allowed numeric range
/// @param {String} raw_text Capacity input draft
/// @returns {Real} Truncated numeric value, or one below the minimum limit for empty input
max_players_input_value = function(raw_text)
{
	/* filtered is the bounded digit-only capacity draft used for numeric conversion */
	var filtered = max_players_filter_input(raw_text);

	/* An empty draft returns one below the minimum as an invalid sentinel, while a nonempty draft
	parses to an integer */
	return filtered == "" ? scr_get_network().min_player_limit - 1 : floor(real(filtered));
}

/// @description Read and filter the profile username from client_settings.ini without changing the current draft
/// @returns {String} Filtered saved name, or empty when missing or unreadable
client_load_saved_username = function()
{
	/* saved_username starts empty so missing storage and failed reads both retain an unconfigured
	profile */
	var saved_username = "";

	try
	{
		/* Read profile persistence only when client_settings.ini already exists */
		if (file_exists(client_settings_file))
		{
			ini_open(client_settings_file);
			saved_username = ini_read_string(client_settings_section, client_username_key, "");
			ini_close();
		}
	}
	catch(e)
	{
		debug_error("Could not load saved username: " + string(e.message));
	}

	return chat_filter_username_input(saved_username);
}

/// @description Filter and validate the current username, then persist it unless this startup profile suppresses persistence
/// @returns {Bool} Whether validation passed and persistence succeeded or was intentionally suppressed
client_save_username = function()
{
	client_username = chat_filter_username_input(client_username);

	/* A filtered username that still fails validation is rejected before any persistence attempt */
	if (!client_username_is_ready())
	{
		return false;
	}

	/* Startup-supplied profiles can intentionally suppress disk persistence while still reporting an
	accepted username */
	if (client_username_persistence_suppressed)
	{
		return true;
	}

	try
	{
		ini_open(client_settings_file);
		ini_write_string(client_settings_section, client_username_key, client_username);
		ini_close();
		return true;
	}
	catch(e)
	{
		debug_error("Could not save username: " + string(e.message));
		return false;
	}
}

/// @description Validate the profile before a session transition, reopening the username chooser on failure and attempting persistence on success
/// @param {String} status_text Context prompt to show when the username is empty
/// @returns {Bool} Whether the username passed validation, regardless of persistence success
client_require_username = function(status_text)
{
	client_username = chat_filter_username_input(client_username);

	/* validation_message records the filtered username's explanation so invalid input can return the
	user to the profile chooser */
	var validation_message = client_username_validation_message(client_username);

	/* A nonempty validation message opens the username chooser and stops the requested session
	transition */
	if (validation_message != "")
	{
		/* An empty name displays the caller's context prompt, while a nonempty invalid name displays
		the specific validation error */
		network_mode_status = string_trim(client_username) == "" ? string(status_text) : validation_message;
		network_mode_page = "main";
		network_mode_focus = "username";
		network_mode_screen = true;
		information_screen_open = false;
		client_join_screen = false;
		is_singleplayer = false;
		network_update_window_caption();
		keyboard_string = client_username;
		return false;
	}

	client_save_username();
	return true;
}
#endregion /* Profile and Player Limit Input END */

#region /* Network Mode Layout */
/// @description Recompute chooser bounds in GUI pixels for the host or main page, accounting for native Quit and browser acceleration guidance
/// @returns {Any} No explicit result value
network_mode_update_layout = function()
{
	/* gui_width and gui_height measure the current GUI, while gap sets fourteen-pixel vertical spacing
	between network actions */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var gap = 14;

	/* The acceleration warning appears only on the main page while the browser-performance manager
	reports an active warning */
	network_mode_performance_warning_visible = network_mode_page == "main"
		&& html5_performance.acceleration_warning_active();

	network_mode_panel_width = min(560, max(320, gui_width - 48));

	/* The host subpage uses its smaller fixed panel, while the main page grows when acceleration
	guidance needs an extra row */
	network_mode_panel_height = network_mode_page == "host"
		? 392
		: (network_mode_performance_warning_visible ? 528 : 470);
	network_mode_panel_x = (gui_width - network_mode_panel_width) * 0.5;
	network_mode_panel_y = (gui_height - network_mode_panel_height) * 0.5;

	/* button_width is the centered chooser's usable width after its thirty-two-pixel side margins */
	var button_width = network_mode_panel_width - 64;
	network_mode_username_input_width = button_width;
	network_mode_host_button_width = button_width;
	network_mode_server_button_width = button_width;
	network_mode_host_play_button_width = button_width;
	network_mode_client_button_width = button_width;
	network_mode_singleplayer_button_width = button_width;
	network_mode_back_button_width = button_width;

	network_mode_host_button_height = 52;
	network_mode_server_button_height = 52;
	network_mode_host_play_button_height = 52;
	network_mode_client_button_height = 52;
	network_mode_singleplayer_button_height = 42;
	network_mode_options_button_height = 42;
	network_mode_quit_button_height = 42;
	network_mode_back_button_height = 42;
	network_mode_username_input_height = 42;
	network_mode_information_button_width = 42;
	network_mode_information_button_height = 42;
	network_mode_information_button_x = gui_width - network_mode_information_button_width - 16;
	network_mode_information_button_y = gui_height - network_mode_information_button_height - 16;

	network_mode_username_input_x = network_mode_panel_x + 32;
	network_mode_username_input_y = network_mode_panel_y + 112;

	/* The host page lays out dedicated-server, host-play, and Back actions and returns before
	main-page controls */
	if (network_mode_page == "host")
	{
		network_mode_server_button_x = network_mode_panel_x + 32;
		network_mode_server_button_y = network_mode_panel_y + 112;
		network_mode_host_play_button_x = network_mode_server_button_x;
		network_mode_host_play_button_y = network_mode_server_button_y + network_mode_server_button_height + gap;
		network_mode_back_button_x = network_mode_server_button_x;
		network_mode_back_button_y = network_mode_host_play_button_y + network_mode_host_play_button_height + gap;
		return;
	}

	network_mode_host_button_x = network_mode_username_input_x;
	network_mode_host_button_y = network_mode_username_input_y + network_mode_username_input_height + 24;
	network_mode_client_button_x = network_mode_host_button_x;
	network_mode_client_button_y = network_mode_host_button_y + network_mode_host_button_height + gap;
	network_mode_singleplayer_button_x = network_mode_host_button_x;
	network_mode_singleplayer_button_y = network_mode_client_button_y + network_mode_client_button_height + gap;
	network_mode_options_button_y = network_mode_singleplayer_button_y + network_mode_singleplayer_button_height + gap;
	network_mode_options_button_x = network_mode_host_button_x;

	/* Native windows divide the last main-page row between Options and Quit */
	if (network_mode_show_quit)
	{
		/* split_button_width divides the available action width equally after reserving the
		fourteen-pixel gap */
		var split_button_width = (button_width - gap) * 0.5;
		network_mode_options_button_width = split_button_width;
		network_mode_quit_button_width = split_button_width;
		network_mode_quit_button_x = network_mode_options_button_x + split_button_width + gap;
		network_mode_quit_button_y = network_mode_options_button_y;
	}

	/* Browser runtimes give Options the full row and leave the unavailable Quit control with zero
	width */
	else
	{
		network_mode_options_button_width = button_width;
		network_mode_quit_button_width = 0;
		network_mode_quit_button_x = network_mode_options_button_x + button_width;
		network_mode_quit_button_y = network_mode_options_button_y;
	}
	network_mode_performance_warning_x = network_mode_host_button_x;
	network_mode_performance_warning_y = network_mode_options_button_y + network_mode_options_button_height + 12;
	network_mode_performance_warning_width = button_width;
}
#endregion /* Network Mode Layout END */

#region /* Information Menu */
/// @description Center the information panel and position its update-notes and Back controls in GUI pixels
/// @returns {Any} No explicit return value
information_update_layout = function()
{
	/* gui_width and gui_height measure available GUI pixels, and gap separates the information menu's
	two actions */
	var gui_width = max(1, display_get_gui_width());
	var gui_height = max(1, display_get_gui_height());
	var gap = 14;

	information_panel_width = min(620, max(320, gui_width - 48));
	information_panel_height = min(390, max(330, gui_height - 48));
	information_panel_x = (gui_width - information_panel_width) * 0.5;
	information_panel_y = (gui_height - information_panel_height) * 0.5;

	/* button_width spans the information panel's inner area, while split_button_width divides it
	around the shared gap */
	var button_width = information_panel_width - 64;
	var split_button_width = (button_width - gap) * 0.5;
	information_whats_new_button_width = split_button_width;
	information_back_button_width = split_button_width;
	information_whats_new_button_x = information_panel_x + 32;
	information_back_button_x = information_whats_new_button_x + split_button_width + gap;
	information_whats_new_button_y = information_panel_y + information_panel_height - 70;
	information_back_button_y = information_whats_new_button_y;
}

/// @description Open the information menu, release username text focus, reset hold confirmation, and position its controls
/// @returns {Bool} Always true after opening the information menu
information_open = function()
{
	escape_exit_hold_reset();
	network_mode_focus = "";
	keyboard_string = "";
	information_screen_open = true;
	information_hover_button = "";
	information_focus = "whats_new";
	information_update_layout();
	return true;
}

/// @description Close information, reset hold confirmation, and return gamepad focus to the main information action
/// @returns {Bool} Always true after resetting the menu state
information_close = function()
{
	escape_exit_hold_reset();
	information_screen_open = false;
	information_hover_button = "";
	information_focus = "whats_new";
	network_mode_gamepad_focus = "information";
	return true;
}

/// @description Route information-menu pointer, keyboard, and first-gamepad actions to update notes or Back
/// @returns {Bool} Always true because this menu retains input ownership for the update
information_update_input = function()
{
	information_update_layout();

	/* mouse_x_gui and mouse_y_gui capture GUI pointer position, and mouse_pressed detects a new left
	click */
	var mouse_x_gui = device_mouse_x_to_gui(0);
	var mouse_y_gui = device_mouse_y_to_gui(0);
	var mouse_pressed = mouse_check_button_pressed(mb_left);

	/* whats_new_hover requires the pointer inside the inclusive update-notes button bounds */
	var whats_new_hover = mouse_x_gui >= information_whats_new_button_x
		&& mouse_x_gui <= information_whats_new_button_x + information_whats_new_button_width
		&& mouse_y_gui >= information_whats_new_button_y
		&& mouse_y_gui <= information_whats_new_button_y + information_whats_new_button_height;

	/* back_hover tests the information menu's Back rectangle independently */
	var back_hover = mouse_x_gui >= information_back_button_x
		&& mouse_x_gui <= information_back_button_x + information_back_button_width
		&& mouse_y_gui >= information_back_button_y
		&& mouse_y_gui <= information_back_button_y + information_back_button_height;

	/* What's New receives hover priority, followed by Back, with empty hover state outside both
	controls */
	information_hover_button = whats_new_hover ? "whats_new" : (back_hover ? "back" : "");

	/* move_direction starts neutral before keyboard or gamepad navigation selects a focus step */
	var move_direction = 0;

	/* Left or A requests the previous information action */
	if (keyboard_check_pressed(vk_left)
	|| keyboard_check_pressed(ord("A")))
	{
		move_direction = -1;
	}

	/* Otherwise Right or D requests the next information action */
	else if (keyboard_check_pressed(vk_right)
	|| keyboard_check_pressed(ord("D")))
	{
		move_direction = 1;
	}

	/* A connected first gamepad can repeat information focus movement only after its millisecond
	navigation deadline */
	if (gamepad_is_connected(0)
	&& current_time >= information_gamepad_navigation_due)
	{
		/* gamepad_left and gamepad_right combine D-pad directions with horizontal-stick thresholds of
		0.65 so opposing held requests can be detected */
		var gamepad_left = gamepad_button_check(0, gp_padl)
			|| gamepad_axis_value(0, gp_axislh) <= -0.65;
		var gamepad_right = gamepad_button_check(0, gp_padr)
			|| gamepad_axis_value(0, gp_axislh) >= 0.65;

		/* Exactly one gamepad direction chooses a signed step and schedules the next repeat 180
		milliseconds later */
		if (gamepad_left != gamepad_right)
		{
			/* Left selects a backward step and Right selects a forward step */
			move_direction = gamepad_left ? -1 : 1;
			information_gamepad_navigation_due = current_time + 180;
		}
	}

	/* Any movement alternates focus because the information menu has exactly two actions */
	if (move_direction != 0)
	{
		/* What's New focus moves to Back, while Back moves to What's New */
		information_focus = information_focus == "whats_new" ? "back" : "whats_new";
	}

	/* accept_pressed combines Enter, Space, and first-gamepad confirm presses for the focused
	information action */
	var accept_pressed = keyboard_check_pressed(vk_enter)
		|| keyboard_check_pressed(vk_space)
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face1));

	/* A new click on What's New or confirmation while it is focused opens update notes */
	if ((whats_new_hover && mouse_pressed)
	|| (information_focus == "whats_new" && accept_pressed))
	{
		whats_new_open();
		return true;
	}

	/* A Back click, focused confirmation, Escape, or first-gamepad cancel closes the information menu */
	if ((back_hover && mouse_pressed)
	|| (information_focus == "back" && accept_pressed)
	|| keyboard_check_pressed(vk_escape)
	|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face2)))
	{
		information_close();
		return true;
	}

	return true;
}
#endregion /* Information Menu END */

#region /* Appearance Performance and Diagnostics Options */
/// @description Recompute appearance, performance, diagnostics, and browser-guidance bounds in GUI pixels
/// @returns {Any} No explicit return value
options_update_layout = function()
{
	/* gui_width and gui_height measure available GUI pixels before centering the appearance and
	performance panel */
	var gui_width = max(1, display_get_gui_width());
	var gui_height = max(1, display_get_gui_height());
	options_panel_width = min(900, max(340, gui_width - 30));
	options_panel_height = min(650, max(470, gui_height - 30));
	options_panel_x = (gui_width - options_panel_width) * 0.5;
	options_panel_y = (gui_height - options_panel_height) * 0.5;

	/* inner_margin scales the panel padding, inner_width measures usable control width, and tab_gap
	separates the three equal-width options tabs */
	var inner_margin = clamp(options_panel_width * 0.055, 20, 38);
	var inner_width = options_panel_width - inner_margin * 2;
	var tab_gap = 8;
	options_tab_y = options_panel_y + 65;
	options_tab_height = 38;
	options_tab_width = (inner_width - tab_gap * 2) / 3;
	options_appearance_tab_x = options_panel_x + inner_margin;
	options_performance_tab_x = options_appearance_tab_x + options_tab_width + tab_gap;
	options_diagnostics_tab_x = options_performance_tab_x + options_tab_width + tab_gap;
	options_collision_mask_y = options_panel_y + 132;
	options_hue_x = options_panel_x + inner_margin;
	options_hue_y = options_panel_y + 132;
	options_hue_width = inner_width;
	options_hue_height = 24;
	options_sv_x = options_hue_x;
	options_sv_y = options_hue_y + options_hue_height + 9;
	options_sv_width = options_hue_width;
	options_sv_height = clamp(options_panel_height - 410, 60, 180);

	options_row_left_x = options_hue_x;
	options_row_right_x = options_hue_x + options_hue_width - options_arrow_width;
	options_row_value_x = options_row_left_x + options_arrow_width + 8;
	options_row_value_width = max(1, options_hue_width - options_arrow_width * 2 - 16);
	options_shape_y = options_sv_y + options_sv_height + 14;
	options_transparency_y = options_shape_y + options_row_height + 9;

	options_reset_x = options_hue_x;
	options_reset_y = options_transparency_y + options_row_height + 9;
	options_reset_width = options_hue_width;
	options_reset_height = 40;

	/* bottom_gap separates Apply and Cancel within the shared colour-control width */
	var bottom_gap = 10;
	options_apply_width = (options_hue_width - bottom_gap) * 0.5;
	options_apply_height = 42;
	options_apply_x = options_hue_x;
	options_apply_y = options_panel_y + options_panel_height - options_apply_height - 29;
	options_cancel_width = options_apply_width;
	options_cancel_height = options_apply_height;
	options_cancel_x = options_apply_x + options_apply_width + bottom_gap;
	options_cancel_y = options_apply_y;
	options_performance_reset_x = options_hue_x;
	options_performance_reset_y = options_apply_y - options_performance_reset_height - 9;
	options_performance_reset_width = inner_width;
	options_performance_instructions_x = options_hue_x;
	options_performance_instructions_y = options_performance_reset_y - options_performance_instructions_height - 8;
	options_performance_instructions_width = inner_width;
	options_performance_copy_x = options_hue_x;
	options_performance_copy_y = options_performance_instructions_y - options_performance_copy_height - 8;
	options_performance_copy_width = inner_width;
	options_performance_mode_y = options_performance_copy_y - options_row_height - 12;

	options_guidance_panel_width = min(960, max(310, gui_width - 32));
	options_guidance_panel_height = min(620, max(410, gui_height - 32));
	options_guidance_panel_x = (gui_width - options_guidance_panel_width) * 0.5;
	options_guidance_panel_y = (gui_height - options_guidance_panel_height) * 0.5;

	/* guidance_margin scales the warning panel's side padding, while guidance_gap separates Review and
	Continue controls */
	var guidance_margin = clamp(options_guidance_panel_width * 0.055, 18, 34);
	var guidance_gap = 10;
	options_guidance_review_x = options_guidance_panel_x + guidance_margin;
	options_guidance_review_y = options_guidance_panel_y + options_guidance_panel_height - options_guidance_review_height - 20;

	/* Startup guidance divides the bottom row between Review and Continue, while ordinary guidance
	gives Review the full inner width */
	options_guidance_review_width = options_guidance_startup
		? (options_guidance_panel_width - guidance_margin * 2 - guidance_gap) * 0.5
		: options_guidance_panel_width - guidance_margin * 2;
	options_guidance_continue_x = options_guidance_review_x + options_guidance_review_width + guidance_gap;
	options_guidance_continue_y = options_guidance_review_y;
	options_guidance_continue_width = options_guidance_review_width;
}

/// @description Test inclusive GUI bounds expressed as four edge coordinates
/// @param {Real} point_x Horizontal pointer coordinate in GUI pixels
/// @param {Real} point_y Vertical pointer coordinate in GUI pixels
/// @param {Real} left Rectangle left coordinate in GUI pixels
/// @param {Real} top Rectangle top coordinate in GUI pixels
/// @param {Real} right Rectangle right coordinate in GUI pixels
/// @param {Real} bottom Rectangle bottom coordinate in GUI pixels
/// @returns {Bool} Whether the point lies inside or on the rectangle
point_in_rect = function(point_x, point_y, left, top, right, bottom)
{
	/* Controller menus use edge bounds, while options_point_in_rect below uses dimensions */
	return point_x >= left && point_x <= right && point_y >= top && point_y <= bottom;
}

/// @description Test inclusive GUI bounds expressed as an origin and dimensions
/// @param {Real} mouse_x Horizontal pointer coordinate in GUI pixels
/// @param {Real} mouse_y Vertical pointer coordinate in GUI pixels
/// @param {Real} left Rectangle left coordinate in GUI pixels
/// @param {Real} top Rectangle top coordinate in GUI pixels
/// @param {Real} width Rectangle width in GUI pixels
/// @param {Real} height Rectangle height in GUI pixels
/// @returns {Bool} Whether the point lies inside or on the rectangle
options_point_in_rect = function(mouse_x, mouse_y, left, top, width, height)
{
	/* The pointer must lie within the inclusive horizontal and vertical bounds of this GUI control */
	return mouse_x >= left
		&& mouse_x <= left + width
		&& mouse_y >= top
		&& mouse_y <= top + height;
}

/// @description Select a recognized options tab and clear content focus, colour editing, hover, and picker dragging
/// @param {String} tab_name appearance, performance, or diagnostics
/// @returns {Bool} Whether a recognized tab was selected
options_switch_tab = function(tab_name)
{
	/* Only the three options identities are accepted so later input routing can rely on
	the active tab */
	if (tab_name != "appearance" && tab_name != "performance" && tab_name != "diagnostics")
	{
		return false;
	}
	options_tab = tab_name;
	options_focus = "tabs";
	options_hover = "";
	options_colour_editing = false;
	options_picker_drag = "";
	return true;
}

/// @description Move through the options tabs in the requested direction and wrap at either end
/// @param {Real} direction Negative selects the previous tab and positive selects the next
options_cycle_tab = function(direction)
{
	/* Ordered identities and the current zero-based index make keyboard and gamepad tab movement
	match the visible left-to-right order */
	var tabs = ["appearance", "performance", "diagnostics"];
	var tab_index = options_tab == "appearance" ? 0 : (options_tab == "performance" ? 1 : 2);
	options_switch_tab(tabs[(tab_index + sign(direction) + array_length(tabs)) mod array_length(tabs)]);
}

/// @description Preview collision diagnostics locally without changing any collision rules
options_toggle_collision_mask = function()
{
	global.show_collision_mask = !global.show_collision_mask;
}

/// @description Refresh HTML5 diagnostics and open browser performance guidance
/// @param {Bool} startup Whether Continue should close startup options, defaulting to false when omitted
/// @returns {Bool} Whether HTML5 guidance was available and opened
options_show_guidance = function(startup = false)
{
	/* Performance guidance is available only in HTML5, where the browser diagnostics and acceleration
	settings apply */
	if (!html5_performance.is_html5)
	{
		return false;
	}
	html5_performance.refresh_diagnostics();
	options_guidance_startup = startup;
	options_guidance_open = true;
	options_guidance_focus = "review";
	options_guidance_hover = "";
	options_update_layout();
	return true;
}

/// @description Mark guidance seen and close it, opening performance review or closing startup options as requested
/// @param {Bool} review_settings Whether to leave options open on the performance tab
/// @returns {Bool} Always true after handling dismissal
options_dismiss_guidance = function(review_settings)
{
	/* was_startup preserves whether dismissal should also close the startup options screen after its
	modal flags are cleared */
	var was_startup = options_guidance_startup;
	html5_performance.mark_guidance_seen();
	options_guidance_open = false;
	options_guidance_startup = false;
	options_guidance_hover = "";

	/* Choosing review keeps options open and switches focus to the performance settings */
	if (review_settings)
	{
		options_switch_tab("performance");
		return true;
	}

	/* Continuing past startup guidance closes options without applying draft changes */
	if (was_startup)
	{
		options_close(false);
	}
	return true;
}

/// @description Apply draft colour, shape, and transparency to the shared live menu-button theme
/// @returns {Any} No explicit return value
options_apply_draft_live = function()
{
	scr_menu_button_set_theme(options_draft_colour, options_draft_shape, options_draft_transparency);
}

/// @description Clamp byte-scaled HSV, recompute the RGB appearance draft, and update the live menu-button preview
/// @returns {Any} No explicit return value
options_refresh_colour = function()
{
	options_hue = clamp(options_hue, 0, 255);
	options_saturation = clamp(options_saturation, 0, 255);
	options_value = clamp(options_value, 0, 255);
	options_draft_colour = make_color_hsv(options_hue, options_saturation, options_value);
	options_apply_draft_live();
}

/// @description Derive byte-scaled HSV picker state from the current RGB appearance draft
/// @returns {Any} No explicit return value
options_sync_picker_from_colour = function()
{
	options_hue = colour_get_hue(options_draft_colour);
	options_saturation = colour_get_saturation(options_draft_colour);
	options_value = colour_get_value(options_draft_colour);
}

/// @description Compare colour, shape, and transparency with the complete authored default theme
/// @param {Colour} colour Packed RGB button colour
/// @param {Real} shape Button shape enum
/// @param {Real} transparency Button transparency enum
/// @returns {Bool} Whether all three properties match the default appearance
options_theme_is_default = function(colour, shape, transparency)
{
	/* default_theme is a fresh authored reference used to compare all three appearance properties */
	var default_theme = scr_menu_button_default_theme();

	/* The theme is default only when colour, shape, and transparency all match their authored values */
	return colour == default_theme.default_colour
		&& shape == default_theme.shape
		&& transparency == default_theme.transparency;
}

/// @description Persist live menu appearance and collision diagnostics to client_settings.ini
/// @returns {Bool} Whether the settings writes completed without an exception
options_save_theme = function()
{
	try
	{
		ini_open(client_settings_file);

		/* Store the customized marker as zero only for the complete default theme, allowing startup to
		keep future authored defaults */
		ini_write_real("ui_button_design", "customized", options_theme_is_default(global.menu_button_theme.colour, global.menu_button_theme.shape, global.menu_button_theme.transparency) ? 0 : 1);
		ini_write_real("ui_button_design", "colour", global.menu_button_theme.colour);
		ini_write_real("ui_button_design", "shape", global.menu_button_theme.shape);
		ini_write_real("ui_button_design", "transparency", global.menu_button_theme.transparency);
		ini_write_real("diagnostics", "show_collision_mask", global.show_collision_mask ? 1 : 0);
		ini_close();
		return true;
	}
	catch(e)
	{
		try { ini_close(); } catch(close_error) {}
		debug_error("Could not save options settings: " + string(e.message));
		return false;
	}
}

/// @description Capture live appearance and diagnostics for cancellation and open the requested options tab
/// @param {String} initial_tab appearance, performance, or diagnostics, defaulting to appearance
/// @param {Bool} show_guidance Whether to attempt startup browser guidance, defaulting to false when omitted
/// @returns {Bool} Always true after opening options, even when a requested tab or browser guidance is unavailable
options_open = function(initial_tab = "appearance", show_guidance = false)
{
	/* active_theme borrows the current menu theme so the original appearance can be restored if this
	options session is cancelled */
	var active_theme = scr_menu_button_get_theme();
	options_original_colour = active_theme.colour;
	options_original_shape = active_theme.shape;
	options_original_transparency = active_theme.transparency;
	options_original_show_collision_mask = global.show_collision_mask;
	options_draft_colour = active_theme.colour;
	options_draft_shape = active_theme.shape;
	options_draft_transparency = active_theme.transparency;
	options_sync_picker_from_colour();
	options_focus = "colour";
	options_hover = "";
	options_colour_editing = false;
	options_picker_drag = "";
	html5_performance.cancel_draft_mode();
	html5_performance.clear_copy_feedback();

	/* Refresh browser diagnostics on opening HTML5 options so the performance tab reflects the current
	runtime */
	if (html5_performance.is_html5)
	{
		html5_performance.refresh_diagnostics();
	}
	options_screen_open = true;
	options_switch_tab(initial_tab);
	options_update_layout();

	/* Requested startup guidance opens the review modal over the newly initialized options screen */
	if (show_guidance)
	{
		options_show_guidance(true);
	}
	return true;
}

/// @description Apply and save options, or restore the captured appearance and collision diagnostics
/// @param {Bool} apply_changes Whether to commit instead of cancel the options session
/// @returns {Bool} Always true after closing, without propagating theme-persistence failure
options_close = function(apply_changes)
{
	/* Applying options commits the live appearance and issues its settings write before applying a
	browser performance draft */
	if (apply_changes)
	{
		options_apply_draft_live();
		options_save_theme();

		/* Only HTML5 supports committing the performance manager's browser graphics mode */
		if (html5_performance.is_html5)
		{
			html5_performance.apply_draft_mode();
		}
	}

	/* Cancelling restores appearance and collision diagnostics captured at opening and discards the
	pending performance-mode change */
	else
	{
		scr_menu_button_set_theme(options_original_colour, options_original_shape, options_original_transparency);
		global.show_collision_mask = options_original_show_collision_mask;
		html5_performance.cancel_draft_mode();
	}
	options_screen_open = false;
	options_guidance_open = false;
	options_guidance_startup = false;
	options_hover = "";
	options_colour_editing = false;
	options_picker_drag = "";
	return true;
}

/// @description Replace the appearance draft with authored defaults, synchronize HSV, and preview the result live
/// @returns {Bool} Always true after resetting the draft
options_reset_draft = function()
{
	/* default_theme supplies the authored colour, shape, and transparency values for a live preview
	reset */
	var default_theme = scr_menu_button_default_theme();
	options_draft_colour = default_theme.default_colour;
	options_draft_shape = default_theme.shape;
	options_draft_transparency = default_theme.transparency;
	options_sync_picker_from_colour();
	options_apply_draft_live();
	return true;
}

/// @description Format the current appearance draft's shape for its cycling row
/// @returns {String} Round default or rectangular shape label
options_shape_label = function()
{
	/* The round shape uses the default label, while the other stored shape identifies rectangular
	buttons */
	return options_draft_shape == JONNIL_MENU_BUTTON_ROUND ? "Round (Default)" : "Rectangle";
}

/// @description Format the current appearance draft's transparency mode with an opaque fallback
/// @returns {String} Readable transparency-mode label
options_transparency_label = function()
{
	/* The stored transparency mode selects its readable label, with unlisted or opaque values using
	the default fallback */
	switch (options_draft_transparency)
	{
		/* See-through mode keeps a translucent filled button */
		case JONNIL_MENU_BUTTON_SEE_THROUGH: return "See Through";

		/* Outlines-only mode identifies buttons drawn using their borders */
		case JONNIL_MENU_BUTTON_OUTLINES_ONLY: return "Outlines Only";

		/* Invisible mode identifies the appearance without a visible button body */
		case JONNIL_MENU_BUTTON_INVISIBLE: return "Invisible";
	}
	return "Opaque (Default)";
}

/// @description Wrap through the two authored button shapes and apply the draft to the live preview
/// @param {Real} direction Positive for forward, negative for backward, or zero to retain the shape
/// @returns {Bool} Always true after previewing the resulting draft
options_cycle_shape = function(direction)
{
	options_draft_shape = (options_draft_shape + sign(direction) + 2) mod 2;
	options_apply_draft_live();
	return true;
}

/// @description Wrap through the four authored transparency modes and apply the draft to the live preview
/// @param {Real} direction Positive for forward, negative for backward, or zero to retain the mode
/// @returns {Bool} Always true after previewing the resulting draft
options_cycle_transparency = function(direction)
{
	options_draft_transparency = (options_draft_transparency + sign(direction) + 4) mod 4;
	options_apply_draft_live();
	return true;
}

/// @description Map GUI pointer position to hue or saturation/value and update the live appearance preview
/// @param {Real} mouse_x Horizontal pointer coordinate in GUI pixels
/// @param {Real} mouse_y Vertical pointer coordinate in GUI pixels
/// @param {String} picker_part hue or sv
/// @returns {Any} No explicit return value
options_update_picker_mouse = function(mouse_x, mouse_y, picker_part)
{
	/* Hue dragging maps horizontal pointer position to the full byte-scaled hue range */
	if (picker_part == "hue")
	{
		options_hue = clamp((mouse_x - options_hue_x) / max(1, options_hue_width), 0, 1) * 255;
	}

	/* Saturation/value dragging maps x to saturation and inverted y to brightness so the top of the
	picker is brightest */
	else if (picker_part == "sv")
	{
		options_saturation = clamp((mouse_x - options_sv_x) / max(1, options_sv_width), 0, 1) * 255;
		options_value = (1 - clamp((mouse_y - options_sv_y) / max(1, options_sv_height), 0, 1)) * 255;
	}
	options_refresh_colour();
}

/// @description Give browser guidance input priority, then route pointer, keyboard, and first-gamepad actions through the active options tab
/// @returns {Bool} Always true because options retains input ownership for the update
options_update_input = function()
{
	options_update_layout();

	/* mouse_x_gui and mouse_y_gui are current GUI pointer coordinates. mouse_pressed detects a new
	left click and mouse_down supports an active colour-picker drag */
	var mouse_x_gui = device_mouse_x_to_gui(0);
	var mouse_y_gui = device_mouse_y_to_gui(0);
	var mouse_pressed = mouse_check_button_pressed(mb_left);
	var mouse_down = mouse_check_button(mb_left);

	/* cancel_pressed combines Escape with the first gamepad's cancel button */
	var cancel_pressed = keyboard_check_pressed(vk_escape)
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face2));

	/* accept_pressed combines new Enter, Space, or first-gamepad confirmation for focused options
	actions */
	var accept_pressed = keyboard_check_pressed(vk_enter)
		|| keyboard_check_pressed(vk_space)
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face1));

	/* An open browser guidance modal receives input before all ordinary options controls */
	if (options_guidance_open)
	{
		/* guidance_review_hover checks the Review button's inclusive bounds. guidance_continue_hover
		additionally requires startup guidance because Continue is hidden during ordinary review */
		var guidance_review_hover = options_point_in_rect(mouse_x_gui, mouse_y_gui, options_guidance_review_x, options_guidance_review_y, options_guidance_review_width, options_guidance_review_height);
		var guidance_continue_hover = options_guidance_startup
			&& options_point_in_rect(mouse_x_gui, mouse_y_gui, options_guidance_continue_x, options_guidance_continue_y, options_guidance_continue_width, options_guidance_continue_height);

		/* Review wins hover priority over Continue, with an empty key when the pointer is over neither
		control */
		options_guidance_hover = guidance_review_hover ? "review" : (guidance_continue_hover ? "continue" : "");

		/* Clicking Review dismisses guidance and leaves performance settings available for inspection */
		if (mouse_pressed && guidance_review_hover)
		{
			options_dismiss_guidance(true);
			return true;
		}

		/* Clicking the startup Continue button dismisses guidance and closes the startup options
		session */
		if (mouse_pressed && guidance_continue_hover)
		{
			options_dismiss_guidance(false);
			return true;
		}

		/* A cancel action dismisses guidance through the same continue path, closing options only for
		startup guidance */
		if (cancel_pressed)
		{
			options_dismiss_guidance(false);
			return true;
		}

		/* Startup guidance permits left/right keyboard or gamepad presses to switch between its two
		visible choices */
		if (options_guidance_startup
		&& (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right)
			|| (gamepad_is_connected(0) && (gamepad_button_check_pressed(0, gp_padl) || gamepad_button_check_pressed(0, gp_padr)))))
		{
			/* Focus alternates between Review and Continue because startup guidance has exactly two
			actions */
			options_guidance_focus = options_guidance_focus == "review" ? "continue" : "review";
		}

		/* Confirmation activates the focused guidance choice, passing whether Review was selected */
		if (accept_pressed)
		{
			options_dismiss_guidance(options_guidance_focus == "review");
		}
		return true;
	}

	/* Tab hover values check each GUI button. Active identities route its controls, while
	performance_available restricts browser operations to HTML5 */
	var appearance_tab_hover = options_point_in_rect(mouse_x_gui, mouse_y_gui, options_appearance_tab_x, options_tab_y, options_tab_width, options_tab_height);
	var performance_tab_hover = options_point_in_rect(mouse_x_gui, mouse_y_gui, options_performance_tab_x, options_tab_y, options_tab_width, options_tab_height);
	var diagnostics_tab_hover = options_point_in_rect(mouse_x_gui, mouse_y_gui, options_diagnostics_tab_x, options_tab_y, options_tab_width, options_tab_height);
	var appearance_active = options_tab == "appearance";
	var performance_active = options_tab == "performance";
	var diagnostics_active = options_tab == "diagnostics";
	var performance_available = html5_performance.is_html5;

	/* The collision toggle is available on every runtime while Diagnostics is selected */
	var collision_mask_hover = diagnostics_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_hue_x, options_collision_mask_y, options_hue_width, options_row_height);

	/* hue_hover and sv_hover require the appearance tab and pointer containment in their respective
	colour-picker regions */
	var hue_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_hue_x, options_hue_y, options_hue_width, options_hue_height);
	var sv_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_sv_x, options_sv_y, options_sv_width, options_sv_height);

	/* shape_left_hover and shape_right_hover identify the two appearance-only shape cycling arrows */
	var shape_left_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_row_left_x, options_shape_y, options_arrow_width, options_row_height);
	var shape_right_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_row_right_x, options_shape_y, options_arrow_width, options_row_height);

	/* transparency_left_hover and transparency_right_hover identify the two appearance-only
	transparency cycling arrows */
	var transparency_left_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_row_left_x, options_transparency_y, options_arrow_width, options_row_height);
	var transparency_right_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_row_right_x, options_transparency_y, options_arrow_width, options_row_height);

	/* reset_hover is available only over the appearance tab's reset control */
	var reset_hover = appearance_active && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_reset_x, options_reset_y, options_reset_width, options_reset_height);

	/* performance_left_hover and performance_right_hover require the performance tab, HTML5 support,
	and the matching graphics-mode arrow */
	var performance_left_hover = performance_active && performance_available && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_row_left_x, options_performance_mode_y, options_arrow_width, options_row_height);
	var performance_right_hover = performance_active && performance_available && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_row_right_x, options_performance_mode_y, options_arrow_width, options_row_height);

	/* performance_copy_hover identifies the diagnostics-copy control only when the HTML5 performance
	tab is active */
	var performance_copy_hover = performance_active && performance_available && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_performance_copy_x, options_performance_copy_y, options_performance_copy_width, options_performance_copy_height);

	/* performance_instructions_hover identifies the browser instructions control under the same
	active-tab and runtime requirements */
	var performance_instructions_hover = performance_active && performance_available && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_performance_instructions_x, options_performance_instructions_y, options_performance_instructions_width, options_performance_instructions_height);

	/* performance_reset_hover identifies the HTML5 measurement reset control on the active performance
	tab */
	var performance_reset_hover = performance_active && performance_available && options_point_in_rect(mouse_x_gui, mouse_y_gui, options_performance_reset_x, options_performance_reset_y, options_performance_reset_width, options_performance_reset_height);

	/* Apply and Cancel remain available on every tab */
	var apply_hover = options_point_in_rect(mouse_x_gui, mouse_y_gui, options_apply_x, options_apply_y, options_apply_width, options_apply_height);
	var cancel_hover = options_point_in_rect(mouse_x_gui, mouse_y_gui, options_cancel_x, options_cancel_y, options_cancel_width, options_cancel_height);

	options_hover = "";

	/* A pointer over Appearance assigns the first eligible hover identity */
	if (appearance_tab_hover) options_hover = "appearance_tab";

	/* Otherwise Performance receives hover priority before its content controls */
	else if (performance_tab_hover) options_hover = "performance_tab";

	/* Diagnostics has its own tab and local overlay toggle */
	else if (diagnostics_tab_hover) options_hover = "diagnostics_tab";
	else if (collision_mask_hover) options_hover = "collision_mask";

	/* Either colour-picker region highlights the shared colour control */
	else if (hue_hover || sv_hover) options_hover = "colour";

	/* The left shape arrow receives its own hover identity for reverse cycling */
	else if (shape_left_hover) options_hover = "shape_left";

	/* The right shape arrow highlights forward shape cycling */
	else if (shape_right_hover) options_hover = "shape_right";

	/* The left transparency arrow highlights reverse cycling of the appearance modes */
	else if (transparency_left_hover) options_hover = "transparency_left";

	/* The right transparency arrow highlights forward cycling of the appearance modes */
	else if (transparency_right_hover) options_hover = "transparency_right";

	/* The appearance reset button highlights its authored-default action */
	else if (reset_hover) options_hover = "reset";

	/* The left browser graphics arrow highlights reverse performance-mode cycling */
	else if (performance_left_hover) options_hover = "performance_left";

	/* The right browser graphics arrow highlights forward performance-mode cycling */
	else if (performance_right_hover) options_hover = "performance_right";

	/* Diagnostics copy receives its own hover identity for feedback */
	else if (performance_copy_hover) options_hover = "performance_copy";

	/* The browser instructions control highlights the guidance action */
	else if (performance_instructions_hover) options_hover = "performance_instructions";

	/* The measurement reset control highlights the performance-counter reset */
	else if (performance_reset_hover) options_hover = "performance_reset";

	/* The common Apply button highlights saving the current options */
	else if (apply_hover) options_hover = "apply";

	/* The common Cancel button highlights restoring the captured appearance */
	else if (cancel_hover) options_hover = "cancel";

	/* A new click on Appearance switches tabs and consumes this update before content actions */
	if (mouse_pressed && appearance_tab_hover)
	{
		options_switch_tab("appearance");
		return true;
	}

	/* A new click on Performance switches tabs through the same focus-reset path */
	if (mouse_pressed && performance_tab_hover)
	{
		options_switch_tab("performance");
		return true;
	}

	/* Diagnostics switches through the same focus-reset path as the other tabs */
	if (mouse_pressed && diagnostics_tab_hover)
	{
		options_switch_tab("diagnostics");
		return true;
	}

	/* A new hue click starts a hue drag and immediately updates the live colour preview */
	if (mouse_pressed && hue_hover)
	{
		options_focus = "colour";
		options_picker_drag = "hue";
		options_update_picker_mouse(mouse_x_gui, mouse_y_gui, options_picker_drag);
	}

	/* Otherwise a new saturation/value click starts a two-channel picker drag */
	else if (mouse_pressed && sv_hover)
	{
		options_focus = "colour";
		options_picker_drag = "sv";
		options_update_picker_mouse(mouse_x_gui, mouse_y_gui, options_picker_drag);
	}

	/* While the left button remains held, an existing picker drag follows the pointer even outside the
	original control */
	if (mouse_down && options_picker_drag != "")
	{
		options_update_picker_mouse(mouse_x_gui, mouse_y_gui, options_picker_drag);
	}

	/* Releasing the left button ends the picker drag so later pointer motion no longer changes colour */
	if (mouse_check_button_released(mb_left))
	{
		options_picker_drag = "";
	}

	/* Discrete options buttons react only to the new click, while held input is reserved for colour
	dragging */
	if (mouse_pressed)
	{
		/* The diagnostic button previews the overlay and keeps focus for keyboard navigation */
		if (collision_mask_hover) { options_focus = "collision_mask"; options_toggle_collision_mask(); }

		/* The left shape click focuses shape and cycles backward */
		else if (shape_left_hover) { options_focus = "shape"; options_cycle_shape(-1); }

		/* The right shape click focuses shape and cycles forward */
		else if (shape_right_hover) { options_focus = "shape"; options_cycle_shape(1); }

		/* The left transparency click focuses transparency and cycles backward */
		else if (transparency_left_hover) { options_focus = "transparency"; options_cycle_transparency(-1); }

		/* The right transparency click focuses transparency and cycles forward */
		else if (transparency_right_hover) { options_focus = "transparency"; options_cycle_transparency(1); }

		/* Reset focuses the authored-default action and updates its live appearance preview */
		else if (reset_hover) { options_focus = "reset"; options_reset_draft(); }

		/* The left graphics-mode click focuses browser performance and cycles its draft backward */
		else if (performance_left_hover) { options_focus = "performance_graphics"; html5_performance.cycle_draft_mode(-1); }

		/* The right graphics-mode click focuses browser performance and cycles its draft forward */
		else if (performance_right_hover) { options_focus = "performance_graphics"; html5_performance.cycle_draft_mode(1); }

		/* Copy focuses diagnostics and asks the browser manager to copy its report */
		else if (performance_copy_hover) { options_focus = "performance_copy"; html5_performance.copy_diagnostics_report(); }

		/* Instructions opens ordinary browser guidance and consumes this input update */
		else if (performance_instructions_hover) { options_focus = "performance_instructions"; options_show_guidance(false); return true; }

		/* Measurement reset focuses its action and clears recorded browser performance measurements */
		else if (performance_reset_hover) { options_focus = "performance_reset"; html5_performance.reset_measurements(); }

		/* Apply commits options and consumes this update after closing the screen */
		else if (apply_hover) { options_close(true); return true; }

		/* Cancel restores the captured settings and consumes this update after closing the screen */
		else if (cancel_hover) { options_close(false); return true; }
	}

	/* Cancellation first exits fine colour editing or otherwise closes the options session */
	if (cancel_pressed)
	{
		/* When colour adjustment has focus ownership, the first cancel only returns to ordinary
		control navigation */
		if (options_colour_editing)
		{
			options_colour_editing = false;
		}

		/* Without active colour adjustment, cancellation discards the session's draft changes */
		else
		{
			options_close(false);
		}
		return true;
	}

	/* move_x and move_y combine opposing new arrow presses as signed control-navigation steps.
	hue_move combines E/Q presses, and tab_move combines Page Down/Page Up presses */
	var move_x = keyboard_check_pressed(vk_right) - keyboard_check_pressed(vk_left);
	var move_y = keyboard_check_pressed(vk_down) - keyboard_check_pressed(vk_up);
	var hue_move = keyboard_check_pressed(ord("E")) - keyboard_check_pressed(ord("Q"));
	var tab_move = keyboard_check_pressed(vk_pagedown) - keyboard_check_pressed(vk_pageup);

	/* The first connected gamepad adds stick, D-pad, and shoulder navigation to the keyboard requests */
	if (gamepad_is_connected(0))
	{
		/* Held gamepad directions are sampled only after the navigation repeat deadline */
		if (current_time >= options_navigation_due)
		{
			/* pad_x and pad_y combine opposing D-pad or stick directions into signed steps, treating
			stick magnitudes of at least 0.65 as directional input */
			var pad_x = (gamepad_button_check(0, gp_padr) || gamepad_axis_value(0, gp_axislh) >= 0.65)
				- (gamepad_button_check(0, gp_padl) || gamepad_axis_value(0, gp_axislh) <= -0.65);
			var pad_y = (gamepad_button_check(0, gp_padd) || gamepad_axis_value(0, gp_axislv) >= 0.65)
				- (gamepad_button_check(0, gp_padu) || gamepad_axis_value(0, gp_axislv) <= -0.65);

			/* Any nonzero gamepad direction replaces the corresponding navigation steps and delays
			further repeats by 125 milliseconds */
			if (pad_x != 0 || pad_y != 0)
			{
				move_x = pad_x;
				move_y = pad_y;
				options_navigation_due = current_time + 125;
			}
		}

		/* shoulder_move is the signed difference of new right and left shoulder presses */
		var shoulder_move = gamepad_button_check_pressed(0, gp_shoulderr) - gamepad_button_check_pressed(0, gp_shoulderl);

		/* During colour editing, shoulder presses adjust hue instead of changing tabs */
		if (options_colour_editing)
		{
			hue_move += shoulder_move;
		}

		/* During ordinary navigation, shoulders add a tab-switch request */
		else
		{
			tab_move += shoulder_move;
		}
	}

	/* Colour-editing mode interprets directional input as component adjustments and keeps ownership of
	this update */
	if (options_colour_editing)
	{
		/* A horizontal request adjusts saturation by six byte units per step */
		if (move_x != 0) options_saturation += move_x * 6;

		/* A vertical request subtracts six brightness units so upward input makes the colour brighter */
		if (move_y != 0) options_value -= move_y * 6;

		/* A hue request advances six byte units per step and wraps through the 256-value hue cycle */
		if (hue_move != 0) options_hue = (options_hue + hue_move * 6 + 256) mod 256;

		/* Any component movement recomputes and previews the resulting RGB colour */
		if (move_x != 0 || move_y != 0 || hue_move != 0) options_refresh_colour();

		/* Confirmation exits colour editing while keeping the chosen live preview */
		if (accept_pressed) options_colour_editing = false;
		return true;
	}

	/* Page or shoulder movement follows the visible tab order and consumes this update */
	if (tab_move != 0)
	{
		options_cycle_tab(tab_move);
		return true;
	}

	/* Each tab exposes its own controls. Diagnostics works on all runtimes, while unsupported browser
	performance leaves only tabs and confirmation controls */
	var focus_options = appearance_active
		? ["tabs", "colour", "shape", "transparency", "reset", "apply", "cancel"]
		: (diagnostics_active ? ["tabs", "collision_mask", "apply", "cancel"] : (performance_available
			? ["tabs", "performance_graphics", "performance_copy", "performance_instructions", "performance_reset", "apply", "cancel"]
			: ["tabs", "apply", "cancel"]));

	/* Tab produces a focus-row step, with Shift reversing its direction */
	if (keyboard_check_pressed(vk_tab))
	{
		/* Shift selects the previous control and ordinary Tab selects the next */
		move_y = keyboard_check(vk_shift) ? -1 : 1;
	}

	/* Vertical navigation locates the current focus and wraps through the active tab's available
	controls */
	if (move_y != 0)
	{
		/* focus_index starts at the first available control, while index searches the zero-based focus
		order */
		var focus_index = 0;

		/* Visit available focus identities until the currently focused control is found */
		for (var index = 0; index < array_length(focus_options); index++)
		{
			/* A matching identity records its position and ends the focus search */
			if (focus_options[index] == options_focus) { focus_index = index; break; }
		}
		options_focus = focus_options[(focus_index + sign(move_y) + array_length(focus_options)) mod array_length(focus_options)];
	}

	/* Without vertical movement, horizontal input changes the value or choice belonging to the focused
	control */
	else if (move_x != 0)
	{
		/* Focused tabs cycle in the horizontal input direction */
		if (options_focus == "tabs") options_cycle_tab(move_x);

		/* Either horizontal direction toggles the focused diagnostic choice */
		else if (options_focus == "collision_mask") options_toggle_collision_mask();

		/* Focused shape cycles in the requested horizontal direction */
		else if (options_focus == "shape") options_cycle_shape(move_x);

		/* Focused transparency cycles its appearance mode in the requested direction */
		else if (options_focus == "transparency") options_cycle_transparency(move_x);

		/* Focused browser graphics cycles only when HTML5 performance controls are available */
		else if (options_focus == "performance_graphics" && performance_available) html5_performance.cycle_draft_mode(move_x);

		/* Focused Apply or Cancel switches to the other bottom confirmation control */
		else if (options_focus == "apply" || options_focus == "cancel") options_focus = options_focus == "apply" ? "cancel" : "apply";
	}

	/* Confirmation activates the action belonging to the current focus */
	if (accept_pressed)
	{
		/* The focus identity routes confirmation to tab switching, colour editing, value cycling,
		browser diagnostics, or closing options */
		switch (options_focus)
		{
			/* Tab confirmation advances to the next visible tab */
			case "tabs": options_cycle_tab(1); break;

			/* Collision confirmation previews the diagnostic overlay */
			case "collision_mask": options_toggle_collision_mask(); break;

			/* Colour confirmation enters fine HSV editing */
			case "colour": options_colour_editing = true; break;

			/* Shape confirmation cycles to the next authored button shape */
			case "shape": options_cycle_shape(1); break;

			/* Transparency confirmation cycles to the next authored appearance mode */
			case "transparency": options_cycle_transparency(1); break;

			/* Reset confirmation restores the authored appearance defaults in the live draft */
			case "reset": options_reset_draft(); break;

			/* Browser graphics confirmation cycles its draft only on HTML5 */
			case "performance_graphics": if (performance_available) html5_performance.cycle_draft_mode(1); break;

			/* Diagnostics confirmation copies the report only on HTML5 */
			case "performance_copy": if (performance_available) html5_performance.copy_diagnostics_report(); break;

			/* Instructions confirmation opens browser guidance only on HTML5 */
			case "performance_instructions": if (performance_available) options_show_guidance(false); break;

			/* Measurement confirmation clears performance counters only on HTML5 */
			case "performance_reset": if (performance_available) html5_performance.reset_measurements(); break;

			/* Apply confirmation commits the session and closes options */
			case "apply": options_close(true); break;

			/* Cancel confirmation restores the original appearance and closes options */
			case "cancel": options_close(false); break;
		}
	}
	return true;
}
#endregion /* Appearance Performance and Diagnostics Options END */

#region /* Server List and Saved Server Dialogs */
/// @description Position server rows, join actions, and saved-server dialogs in GUI pixels, hiding the legacy username input
/// @returns {Any} No explicit return value
client_join_update_layout = function()
{
	/* gui_width and gui_height measure available GUI pixels. margin reserves panel side padding and
	gap separates neighboring server-list controls */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var margin = 40;
	var gap = 10;

	client_join_panel_width = min(860, max(360, gui_width - 48));
	client_join_panel_height = gui_height;
	client_join_panel_x = (gui_width - client_join_panel_width) * 0.5;
	client_join_panel_y = 0;

	client_join_button_height = 38;
	client_join_direct_button_height = client_join_button_height;
	client_join_refresh_button_height = client_join_button_height;
	client_join_back_button_height = client_join_button_height;

	/* button_total_width spans the inner panel. button_width divides the main row into three controls,
	small_button_width divides the second row into four, and button_y places both rows above the GUI
	bottom */
	var button_total_width = client_join_panel_width - margin * 2;
	var button_width = (button_total_width - gap * 2) / 3;
	var small_button_width = (button_total_width - gap * 3) * 0.25;
	var button_y = gui_height - client_join_button_height * 2 - gap - 24;

	client_join_button_width = button_width;
	client_join_direct_button_width = button_width;
	client_join_add_button_width = button_width;
	client_join_edit_button_width = small_button_width;
	client_join_delete_button_width = small_button_width;
	client_join_refresh_button_width = small_button_width;
	client_join_back_button_width = small_button_width;

	client_join_button_x = client_join_panel_x + margin;
	client_join_direct_button_x = client_join_button_x + button_width + gap;
	client_join_add_button_x = client_join_direct_button_x + button_width + gap;
	client_join_edit_button_x = client_join_button_x;
	client_join_delete_button_x = client_join_edit_button_x + small_button_width + gap;
	client_join_refresh_button_x = client_join_delete_button_x + small_button_width + gap;
	client_join_back_button_x = client_join_refresh_button_x + small_button_width + gap;

	client_join_button_y = button_y;
	client_join_direct_button_y = button_y;
	client_join_add_button_y = button_y;
	client_join_edit_button_y = button_y + client_join_button_height + gap;
	client_join_delete_button_y = client_join_edit_button_y;
	client_join_refresh_button_y = client_join_edit_button_y;
	client_join_back_button_y = client_join_edit_button_y;

	client_join_input_x = client_join_panel_x + margin;
	client_join_input_width = button_total_width;
	client_join_input_height = 42;
	client_username_input_x = 0;
	client_username_input_width = 0;
	client_username_input_height = 0;
	client_username_input_y = 0;
	client_join_input_y = button_y - client_join_input_height - 38;

	client_join_list_x = client_join_panel_x + margin;
	client_join_list_y = 72;
	client_join_list_width = button_total_width;

	/* list_bottom stops the server rows above the actions, leaving at least 120 GUI pixels for list
	content */
	var list_bottom = button_y - 58;
	client_join_list_height = max(120, list_bottom - client_join_list_y);
	client_join_dialog_width = min(560, gui_width - 40);
	client_join_dialog_x = (gui_width - client_join_dialog_width) * 0.5;

	/* Deletion uses a shorter confirmation panel because name and address editing fields are absent */
	client_join_dialog_height = client_join_dialog == "delete" ? 260 : 340;
	client_join_dialog_y = max(12, (gui_height - client_join_dialog_height) * 0.5);
	client_join_dialog_name_y = client_join_dialog_y + 86;
	client_join_dialog_address_y = client_join_dialog_y + 168;
	client_join_dialog_button_y = client_join_dialog_y + client_join_dialog_height - 64;
}

/// @description Resolve the selected visible row to saved-server storage only when its source is saved
/// @returns {Real} Zero-based saved_servers index, or noone for an invalid or unsaved row
client_join_selected_saved_index = function()
{
	/* entries borrows the client's current server-list rows before resolving the selected row to saved
	storage */
	var entries = scr_get_client().server_list_entries;

	/* An out-of-range list selection has no saved-server index */
	if (client_join_selected < 0 || client_join_selected >= array_length(entries)) return noone;

	/* entry borrows the selected visible server row, whose source determines whether saved metadata
	exists */
	var entry = entries[client_join_selected];

	/* Only a saved-source row supplies saved_index, while discovered or other rows return noone */
	return variable_struct_exists(entry, "source") && entry.source == "saved" ? entry.saved_index : noone;
}

/// @description Close saved-server or direct-join dialogs and clear direct mode, input focus, errors, double-click row, and keyboard text
/// @returns {Any} No explicit return value
client_join_close_dialog = function()
{
	client_join_dialog = "";
	client_join_direct_mode = false;
	client_join_focus = "";
	client_join_error = "";
	client_join_last_click_row = noone;
	keyboard_string = "";
}

/// @description Open a saved-server or direct-address dialog, copying an existing record only for eligible edit and delete selections
/// @param {String} dialog add, edit, delete, or direct
/// @returns {Any} No explicit result value, with edit and delete returning early when no saved row is selected
client_join_open_dialog = function(dialog)
{
	client_join_dialog_index = client_join_selected_saved_index();

	/* Editing and deletion require a selected saved server, preventing discovered rows from mutating
	saved entries */
	if ((dialog == "edit" || dialog == "delete") && client_join_dialog_index == noone) return;
	client_join_dialog = dialog;

	/* Only the direct dialog activates direct connection mode, while saved-entry dialogs keep it
	disabled */
	client_join_direct_mode = dialog == "direct";
	client_join_dialog_name = "";
	client_join_dialog_address = "";
	client_join_error = "";
	client_join_dialog_hover = "";

	/* Edit and delete dialogs copy their selected saved entry's label and address into the dialog
	draft */
	if (dialog == "edit" || dialog == "delete")
	{
		/* saved borrows the selected saved-server record so its values can seed the dialog without
		changing storage */
		var saved = scr_get_client().saved_servers[client_join_dialog_index];
		client_join_dialog_name = saved.name;
		client_join_dialog_address = saved.address;
	}

	/* A direct connection dialog reuses the most recent address instead of a saved-server record */
	else if (dialog == "direct") client_join_dialog_address = client_join_address;

	/* Direct connection focuses Address, deletion focuses Cancel for deliberate confirmation, and
	add/edit focuses Name */
	client_join_dialog_focus = dialog == "direct" ? "address" : (dialog == "delete" ? "cancel" : "name");

	/* Address focus seeds keyboard_string with the address draft, while other initial focus uses the
	name draft */
	keyboard_string = client_join_dialog_focus == "address" ? client_join_dialog_address : client_join_dialog_name;
	escape_exit_hold_reset();
}

/// @description Edit dialog drafts, route focus and confirmation, cancel pending connections, and submit direct joins or saved-server changes
/// @returns {Any} No explicit result value
client_join_update_dialog = function()
{
	/* client borrows the connection manager. busy combines DNS and socket connection work, editing
	identifies add/edit, and deleting identifies the confirmation-only dialog */
	var client = scr_get_client();
	var busy = client_dns_pending || client.connect_pending;
	var editing = client_join_dialog == "add" || client_join_dialog == "edit";
	var deleting = client_join_dialog == "delete";

	/* Name input is accepted only when its field is focused in an add or edit dialog */
	if (client_join_dialog_focus == "name" && editing)
	{
		scr_text_input_update("server_name", client_join_dialog_name, 64);
		client_join_dialog_name = string_copy(string_replace_all(string_replace_all(keyboard_string, "\r", ""), "\n", ""), 1, 64);
		keyboard_string = client_join_dialog_name;
	}

	/* Otherwise a focused Address field accepts text in every dialog except deletion confirmation */
	else if (client_join_dialog_focus == "address" && !deleting)
	{
		scr_text_input_update("server_address", client_join_dialog_address, 160);
		client_join_dialog_address = string_copy(string_replace_all(string_replace_all(keyboard_string, "\r", ""), "\n", ""), 1, 160);
		keyboard_string = client_join_dialog_address;
	}

	/* field_x and field_width define the shared dialog field region, button_width divides its bottom
	actions, and mouse_x_gui/mouse_y_gui capture the GUI pointer */
	var field_x = client_join_dialog_x + 28;
	var field_width = client_join_dialog_width - 56;
	var button_width = (field_width - 12) * 0.5;
	var mouse_x_gui = device_mouse_x_to_gui(0);
	var mouse_y_gui = device_mouse_y_to_gui(0);

	/* in_field records pointer containment across the common horizontal span before testing individual
	rows */
	var in_field = mouse_x_gui >= field_x && mouse_x_gui <= field_x + field_width;
	client_join_dialog_hover = "";

	/* Only pointer positions within the shared horizontal span can highlight a dialog field or button */
	if (in_field)
	{
		/* Add/edit highlights the name row when the pointer lies within its 42-pixel vertical bounds */
		if (editing && mouse_y_gui >= client_join_dialog_name_y && mouse_y_gui <= client_join_dialog_name_y + 42) client_join_dialog_hover = "name";

		/* Every non-delete dialog highlights the address row within its matching vertical bounds */
		if (!deleting && mouse_y_gui >= client_join_dialog_address_y && mouse_y_gui <= client_join_dialog_address_y + 42) client_join_dialog_hover = "address";

		/* The bottom action row splits pointer hits between Done and Cancel with a twelve-pixel gap */
		if (mouse_y_gui >= client_join_dialog_button_y && mouse_y_gui <= client_join_dialog_button_y + 40)
		{
			/* The row's left button highlights Done */
			if (mouse_x_gui <= field_x + button_width) client_join_dialog_hover = "done";

			/* The row's right button highlights Cancel after the separating gap */
			else if (mouse_x_gui >= field_x + button_width + 12) client_join_dialog_hover = "cancel";
		}
	}

	/* focus_before remembers the input owner so a focus change can reseed keyboard_string instead of
	mixing field text */
	var focus_before = client_join_dialog_focus;

	/* Tab cycles the controls allowed by the current dialog type */
	if (keyboard_check_pressed(vk_tab))
	{
		/* fields includes name/address for add/edit, confirmation choices for deletion, or address and
		actions for direct connection */
		var fields = editing ? ["name", "address", "done", "cancel"] : (deleting ? ["cancel", "done"] : ["address", "done", "cancel"]);

		/* field_index starts at the first allowed control before finding the current focus in fields */
		var field_index = 0;

		/* i visits every zero-based focus position and records the matching identity for wrapped Tab
		movement */
		for (var i = 0; i < array_length(fields); i++) if (fields[i] == client_join_dialog_focus) field_index = i;

		/* Shift reverses focus traversal, while ordinary Tab advances, both wrapping within this
		dialog's available controls */
		field_index = (field_index + (keyboard_check(vk_shift) ? -1 : 1) + array_length(fields)) mod array_length(fields);
		client_join_dialog_focus = fields[field_index];
	}

	/* A new click over a named control assigns its hover identity as focus */
	if (mouse_check_button_pressed(mb_left) && client_join_dialog_hover != "") client_join_dialog_focus = client_join_dialog_hover;

	/* After focus changes, keyboard_string must switch to the corresponding draft or clear for action
	controls */
	if (client_join_dialog_focus != focus_before)
	{
		/* Name and Address focus receive their respective text drafts, while Done or Cancel focus
		receives empty keyboard text */
		keyboard_string = client_join_dialog_focus == "name" ? client_join_dialog_name : (client_join_dialog_focus == "address" ? client_join_dialog_address : "");
	}

	/* activate combines a new Enter press with a new click over any identified dialog control */
	var activate = keyboard_check_pressed(vk_enter) || (mouse_check_button_pressed(mb_left) && client_join_dialog_hover != "");

	/* Escape or activated Cancel closes the dialog, cancelling outstanding connection work first */
	if (keyboard_check_pressed(vk_escape) || (activate && client_join_dialog_focus == "cancel"))
	{
		/* A busy dialog disconnects the pending socket and clears DNS request bookkeeping before it
		closes */
		if (busy)
		{
			client.disconnect("Connection cancelled.");
			client_dns_pending = false;
			client_dns_request_id = noone;
			client_dns_pending_admin_intent = false;
		}
		client_join_close_dialog();
		return;
	}

	/* No activation or an unfinished connection blocks all new save, delete, and direct-connect
	actions */
	if (!activate || busy) return;

	/* A mouse activation must target Done, while Enter can submit an ordinary text-editing dialog */
	if (!keyboard_check_pressed(vk_enter) && client_join_dialog_focus != "done") return;

	/* Deletion additionally requires Done focus so Enter on Cancel or another control cannot remove a
	saved entry */
	if (deleting && client_join_dialog_focus != "done") return;

	/* The direct dialog copies its draft address into connection state and starts a join attempt */
	if (client_join_dialog == "direct")
	{
		client_join_address = client_join_dialog_address;
		client_join_attempt();
		return;
	}

	/* saved_index uses noone to append a new Add entry and otherwise retains the selected saved index */
	var saved_index = client_join_dialog == "add" ? noone : client_join_dialog_index;

	/* saved_ok records deletion for a Delete dialog or the store result for Add/Edit, keeping
	persistence failure explicit */
	var saved_ok = deleting ? client.delete_saved_server(saved_index)
		: client.store_saved_server(saved_index, client_join_dialog_name, client_join_dialog_address);

	/* A failed saved-server operation displays the client's storage error and keeps the dialog open */
	if (!saved_ok)
	{
		client_join_error = client.saved_servers_error;
		return;
	}

	/* target_index points to the newly appended saved entry or the existing edited index before
	rebuilding visible rows */
	var target_index = saved_index == noone ? array_length(client.saved_servers) - 1 : saved_index;
	client_join_close_dialog();
	client_join_refresh();

	/* entries is the rebuilt visible server list used to restore selection to the affected saved index */
	var entries = client.build_server_list_entries();

	/* row visits zero-based visible list positions until it finds the affected saved-server identity */
	for (var row = 0; row < array_length(entries); row++)
	{
		/* A row with the target saved_index restores selection and scrolls it into the visible
		server-list area */
		if (variable_struct_exists(entries[row], "saved_index") && entries[row].saved_index == target_index)
		{
			client_join_selected = row;
			client_join_scroll = max(0, row - max(1, floor(client_join_list_height / client_join_row_height)) + 1);
			break;
		}
	}
}
#endregion /* Server List and Saved Server Dialogs END */

#region /* Session Control Layouts */
/// @description Position the client leave control at the GUI's top-right, widening it for authenticated remote administration
/// @returns {Any} No explicit return value
client_leave_update_layout = function()
{
	/* gui_width measures the available GUI width, layout_client borrows client state, and
	remote_admin_available starts from authenticated remote administration while excluding owned
	host-play and singleplayer sessions */
	var gui_width = display_get_gui_width();
	var layout_client = scr_get_client();
	var remote_admin_available = is_struct(layout_client)
		&& variable_struct_exists(layout_client, "admin_authenticated")
		&& layout_client.admin_authenticated
		&& !host_play_active
		&& !is_singleplayer;

	/* Remote administration needs a wider leave control for its additional label, while ordinary play
	keeps the compact width */
	client_leave_button_width = remote_admin_available ? 220 : 150;
	client_leave_button_height = 34;
	client_leave_button_x = gui_width - client_leave_button_width - 16;
	client_leave_button_y = 16;
}

/// @description Position owned-server profile, lifecycle, reset, capacity, and wall controls at the right GUI edge
/// @returns {Any} No explicit return value
server_mode_update_layout = function()
{
	/* gui_width anchors the native server-console controls to the right GUI edge */
	var gui_width = display_get_gui_width();

	server_username_input_width = 260;
	server_username_input_height = 42;
	server_username_input_x = gui_width - server_username_input_width - 16;
	server_username_input_y = 40;

	server_join_button_width = server_username_input_width;
	server_join_button_height = 40;
	server_join_button_x = server_username_input_x;
	server_join_button_y = server_username_input_y + server_username_input_height + 12;

	server_shutdown_button_width = server_username_input_width;
	server_shutdown_button_height = 40;
	server_shutdown_button_x = server_username_input_x;
	server_shutdown_button_y = server_join_button_y + server_join_button_height + 10;

	server_restart_button_width = server_username_input_width;
	server_restart_button_height = 40;
	server_restart_button_x = server_username_input_x;
	server_restart_button_y = server_shutdown_button_y + server_shutdown_button_height + 10;

	server_reset_toggle_button_width = server_username_input_width;
	server_reset_toggle_button_height = 34;
	server_reset_toggle_button_x = server_username_input_x;

	/* Leave two readable status lines between the restart and reset controls */
	server_reset_toggle_button_y = server_restart_button_y + server_restart_button_height + 84;

	server_reset_minus_button_width = (server_username_input_width - 10) * 0.5;
	server_reset_minus_button_height = 34;
	server_reset_minus_button_x = server_username_input_x;
	server_reset_minus_button_y = server_reset_toggle_button_y + server_reset_toggle_button_height + 10;
	server_reset_plus_button_width = server_reset_minus_button_width;
	server_reset_plus_button_height = server_reset_minus_button_height;
	server_reset_plus_button_x = server_reset_minus_button_x + server_reset_minus_button_width + 10;
	server_reset_plus_button_y = server_reset_minus_button_y;

	server_max_players_input_width = 150;
	server_max_players_input_height = 38;
	server_max_players_input_x = server_username_input_x;
	server_max_players_input_y = server_reset_minus_button_y + server_reset_minus_button_height + 34;
	server_max_players_apply_button_width = server_username_input_width - server_max_players_input_width - 10;
	server_max_players_apply_button_height = server_max_players_input_height;
	server_max_players_apply_button_x = server_max_players_input_x + server_max_players_input_width + 10;
	server_max_players_apply_button_y = server_max_players_input_y;
	server_wall_toggle_button_x = server_username_input_x;
	server_wall_toggle_button_y = server_max_players_input_y + server_max_players_input_height + 12;
	server_wall_toggle_button_width = server_username_input_width;

	/* Keep the legacy rectangle in sync for the Escape hold progress helper */
	server_mode_button_x = server_shutdown_button_x;
	server_mode_button_y = server_shutdown_button_y;
	server_mode_button_width = server_shutdown_button_width;
	server_mode_button_height = server_shutdown_button_height;
}

/// @description Center official administration controls and their log-view actions in GUI pixels
/// @returns {Any} No explicit return value
official_admin_controls_update_layout = function()
{
	/* gui_width and gui_height center the administration panel. margin reserves its inner padding and
	gap separates neighboring controls, all in GUI pixels */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var margin = 28;
	var gap = 10;

	official_admin_panel_width = min(520, max(340, gui_width - 32));
	official_admin_panel_height = 582;
	official_admin_panel_x = (gui_width - official_admin_panel_width) * 0.5;
	official_admin_panel_y = (gui_height - official_admin_panel_height) * 0.5;

	/* full_width is the panel's usable control width and half_width divides paired controls around the
	shared gap */
	var full_width = official_admin_panel_width - margin * 2;
	var half_width = (full_width - gap) * 0.5;
	official_admin_toggle_button_x = official_admin_panel_x + margin;
	official_admin_toggle_button_y = official_admin_panel_y + 140;
	official_admin_toggle_button_width = full_width;
	official_admin_minus_button_x = official_admin_toggle_button_x;
	official_admin_minus_button_y = official_admin_toggle_button_y + official_admin_toggle_button_height + gap;
	official_admin_minus_button_width = half_width;
	official_admin_plus_button_x = official_admin_minus_button_x + half_width + gap;
	official_admin_plus_button_y = official_admin_minus_button_y;
	official_admin_plus_button_width = half_width;
	official_admin_max_players_input_x = official_admin_toggle_button_x;
	official_admin_max_players_input_y = official_admin_minus_button_y + official_admin_minus_button_height + 32;
	official_admin_max_players_input_width = floor((full_width - gap) * 0.62);
	official_admin_max_players_apply_button_x = official_admin_max_players_input_x + official_admin_max_players_input_width + gap;
	official_admin_max_players_apply_button_y = official_admin_max_players_input_y;
	official_admin_max_players_apply_button_width = full_width - official_admin_max_players_input_width - gap;
	official_admin_wall_button_x = official_admin_toggle_button_x;
	official_admin_wall_button_y = official_admin_max_players_input_y + official_admin_max_players_input_height + gap;
	official_admin_wall_button_width = full_width;
	official_admin_reset_button_x = official_admin_toggle_button_x;
	official_admin_reset_button_y = official_admin_wall_button_y + official_admin_wall_button_height + gap;
	official_admin_reset_button_width = full_width;
	official_admin_refresh_button_x = official_admin_toggle_button_x;
	official_admin_refresh_button_y = official_admin_reset_button_y + official_admin_reset_button_height + gap;
	official_admin_refresh_button_width = half_width;
	official_admin_logs_button_x = official_admin_plus_button_x;
	official_admin_logs_button_y = official_admin_refresh_button_y;
	official_admin_logs_button_width = half_width;
	official_admin_logs_download_button_y = official_admin_panel_y + 276;
	official_admin_logs_folder_button_y = official_admin_logs_download_button_y + 52;
	official_admin_logs_back_button_y = official_admin_panel_y + official_admin_panel_height - 64;
	official_admin_restart_button_x = official_admin_toggle_button_x;
	official_admin_restart_button_y = official_admin_refresh_button_y + official_admin_refresh_button_height + gap;
	official_admin_restart_button_width = full_width;
	official_admin_back_button_x = official_admin_toggle_button_x;
	official_admin_back_button_y = official_admin_restart_button_y + official_admin_restart_button_height + 12;
	official_admin_back_button_width = half_width;
	official_admin_leave_button_x = official_admin_plus_button_x;
	official_admin_leave_button_y = official_admin_back_button_y;
	official_admin_leave_button_width = half_width;
}

/// @description Center the owned-session menu and vertically position resume, wall, console-return, and shutdown controls in GUI pixels
/// @returns {Any} No explicit return value
host_session_menu_update_layout = function()
{
	/* gui_width and gui_height center the owned-session menu. gap spaces its vertically stacked
	controls in GUI pixels */
	var gui_width = display_get_gui_width();
	var gui_height = display_get_gui_height();
	var gap = 12;

	host_menu_panel_width = min(420, max(320, gui_width - 48));
	host_menu_panel_height = 374;
	host_menu_panel_x = (gui_width - host_menu_panel_width) * 0.5;
	host_menu_panel_y = (gui_height - host_menu_panel_height) * 0.5;

	/* button_width spans the session panel between its 32-pixel side margins */
	var button_width = host_menu_panel_width - 64;
	host_menu_resume_button_width = button_width;
	host_menu_wall_button_width = button_width;
	host_menu_return_button_width = button_width;
	host_menu_shutdown_button_width = button_width;
	host_menu_resume_button_x = host_menu_panel_x + 32;
	host_menu_wall_button_x = host_menu_resume_button_x;
	host_menu_return_button_x = host_menu_resume_button_x;
	host_menu_shutdown_button_x = host_menu_resume_button_x;
	host_menu_resume_button_y = host_menu_panel_y + 110;
	host_menu_wall_button_y = host_menu_resume_button_y + host_menu_resume_button_height + gap;
	host_menu_return_button_y = host_menu_wall_button_y + host_menu_wall_button_height + gap;
	host_menu_shutdown_button_y = host_menu_return_button_y + host_menu_return_button_height + gap;
}
#endregion /* Session Control Layouts END */

#region /* Update Notes Menu */
/// @description Wrap update notes, calculate GUI scroll bounds, position actions, and move focus away from unavailable scrolling choices
/// @returns {Any} No explicit return value
whats_new_update_layout = function()
{
	/* gui_width and gui_height measure the current GUI, while horizontal_margin scales the notes' side
	padding within readable bounds */
	var gui_width = max(1, display_get_gui_width());
	var gui_height = max(1, display_get_gui_height());
	var horizontal_margin = clamp(gui_width * 0.04, 24, 56);

	whats_new_text_x = horizontal_margin;
	whats_new_text_start_y = 126;
	whats_new_text_end_y = max(whats_new_text_start_y + 1, gui_height - 86);
	whats_new_text_width = max(1, gui_width - horizontal_margin * 2);
	whats_new_text_height = 19;
	whats_new_line_gap = 6;
	whats_new_wrapped_text = scr_text_wrap(global.whats_new, whats_new_text_height, whats_new_text_width);
	whats_new_lines = string_split(whats_new_wrapped_text, "\n");

	/* line_count includes at least one row, content_height measures wrapped text plus line gaps, and
	view_height measures the visible notes area in GUI pixels */
	var line_count = max(1, array_length(whats_new_lines));
	var content_height = line_count * (whats_new_text_height + whats_new_line_gap) - whats_new_line_gap;
	var view_height = max(1, whats_new_text_end_y - whats_new_text_start_y);
	whats_new_scroll_max = max(0, ceil(content_height - view_height));
	whats_new_scroll_offset = clamp(whats_new_scroll_offset, 0, whats_new_scroll_max);

	/* Positive overflow enables scrolling, while notes that fit leave every scroll action disabled */
	whats_new_can_scroll = whats_new_scroll_max > 0;

	whats_new_button_gap = clamp(gui_width * 0.009, 6, 12);
	whats_new_button_width = min(180, max(54, (gui_width - horizontal_margin * 2 - whats_new_button_gap * 3) * 0.25));
	whats_new_button_height = 42;
	whats_new_button_y = gui_height - whats_new_button_height - 18;
	whats_new_up_button_x = horizontal_margin;
	whats_new_down_button_x = whats_new_up_button_x + whats_new_button_width + whats_new_button_gap;
	whats_new_top_button_x = whats_new_down_button_x + whats_new_button_width + whats_new_button_gap;
	whats_new_back_button_x = whats_new_top_button_x + whats_new_button_width + whats_new_button_gap;

	/* When all notes fit, focus moves to Back so accepting cannot trigger a disabled scroll control */
	if (!whats_new_can_scroll
	&& whats_new_focus != "back")
	{
		whats_new_focus = "back";
	}

	/* At the beginning of scrollable notes, Top is unavailable and focus returns to Down */
	else if (whats_new_focus == "top"
	&& whats_new_scroll_offset <= 0)
	{
		whats_new_focus = "down";
	}
}

/// @description Open notes at the beginning, release username input, and attempt to persist the current content's read marker
/// @returns {Bool} Always true after opening notes, without propagating read-marker persistence failure
whats_new_open = function()
{
	network_mode_focus = "";
	keyboard_string = "";
	whats_new_screen_open = true;
	whats_new_scroll_offset = 0;
	whats_new_focus = "down";
	whats_new_hover = "";
	whats_new_update_layout();

	/* Notes that fit entirely start with Back focused because no scrolling action is needed */
	if (!whats_new_can_scroll)
	{
		whats_new_focus = "back";
	}

	/* Unread notes attempt persistence when opened so the menu can stop displaying its unread
	indicator */
	if (whats_new_unread)
	{
		/* Clear the unread flag only after the stored read marker succeeds, allowing a failed write to
		be retried later */
		if (scr_whats_new_mark_read(client_settings_file, global.whats_new))
		{
			whats_new_unread = false;
		}
	}
	return true;
}

/// @description Close update notes and reset their scroll, hover, and focus state
/// @returns {Bool} Always true after resetting notes state
whats_new_close = function()
{
	whats_new_screen_open = false;
	whats_new_scroll_offset = 0;
	whats_new_hover = "";
	whats_new_focus = "down";
	return true;
}

/// @description Hit-test a notes action using the shared button row and dimensions
/// @param {Real} mouse_x Horizontal pointer coordinate in GUI pixels
/// @param {Real} mouse_y Vertical pointer coordinate in GUI pixels
/// @param {Real} button_x Action's left coordinate in GUI pixels
/// @returns {Bool} Whether the pointer lies within the inclusive button bounds
whats_new_point_in_button = function(mouse_x, mouse_y, button_x)
{
	/* The pointer must fall within this button's inclusive horizontal edges and the shared
	update-notes button row */
	return mouse_x >= button_x
		&& mouse_x <= button_x + whats_new_button_width
		&& mouse_y >= whats_new_button_y
		&& mouse_y <= whats_new_button_y + whats_new_button_height;
}

/// @description Route notes navigation, repeated scrolling, page movement, jump-to-start, and Back through pointer, keyboard, and first-gamepad input
/// @returns {Bool} Always true because the notes screen retains input ownership for the update
whats_new_update_input = function()
{
	whats_new_update_layout();

	/* mouse_x_gui and mouse_y_gui capture pointer position in GUI pixels. mouse_pressed records the
	new left click, while mouse_held supports repeated scrolling during a held click */
	var mouse_x_gui = device_mouse_x_to_gui(0);
	var mouse_y_gui = device_mouse_y_to_gui(0);
	var mouse_pressed = mouse_check_button_pressed(mb_left);
	var mouse_held = mouse_check_button(mb_left);
	whats_new_hover = "";

	/* Highlight Up only when notes overflow and the pointer lies within its button */
	if (whats_new_can_scroll
	&& whats_new_point_in_button(mouse_x_gui, mouse_y_gui, whats_new_up_button_x))
	{
		whats_new_hover = "up";
	}

	/* Otherwise a pointer over enabled Down highlights the downward scroll action */
	else if (whats_new_can_scroll
	&& whats_new_point_in_button(mouse_x_gui, mouse_y_gui, whats_new_down_button_x))
	{
		whats_new_hover = "down";
	}

	/* Top is highlighted only after scrolling away from the start, preventing an unavailable jump
	action from appearing interactive */
	else if (whats_new_can_scroll
	&& whats_new_scroll_offset > 0
	&& whats_new_point_in_button(mouse_x_gui, mouse_y_gui, whats_new_top_button_x))
	{
		whats_new_hover = "top";
	}

	/* The Back button remains available regardless of whether the notes need scrolling */
	else if (whats_new_point_in_button(mouse_x_gui, mouse_y_gui, whats_new_back_button_x))
	{
		whats_new_hover = "back";
	}

	/* An upward wheel step moves the notes twenty GUI pixels toward their beginning */
	if (mouse_wheel_up())
	{
		whats_new_scroll_offset -= 20;
	}

	/* Otherwise a downward wheel step advances the notes twenty GUI pixels */
	else if (mouse_wheel_down())
	{
		whats_new_scroll_offset += 20;
	}

	/* move_direction starts neutral before keyboard or gamepad input chooses a horizontal focus
	movement */
	var move_direction = 0;

	/* Left or A selects the previous available notes action */
	if (keyboard_check_pressed(vk_left)
	|| keyboard_check_pressed(ord("A")))
	{
		move_direction = -1;
	}

	/* Right or D selects the next action when left movement was not pressed */
	else if (keyboard_check_pressed(vk_right)
	|| keyboard_check_pressed(ord("D")))
	{
		move_direction = 1;
	}

	/* The first connected gamepad can repeat focus movement only after its millisecond navigation
	deadline */
	if (gamepad_is_connected(0)
	&& current_time >= whats_new_navigation_due)
	{
		/* gamepad_left and gamepad_right combine their respective D-pad input with a horizontal-stick
		threshold of 0.65, so opposing held directions can be detected */
		var gamepad_left = gamepad_button_check(0, gp_padl)
			|| gamepad_axis_value(0, gp_axislh) <= -0.65;
		var gamepad_right = gamepad_button_check(0, gp_padr)
			|| gamepad_axis_value(0, gp_axislh) >= 0.65;

		/* A single held gamepad direction chooses focus movement and delays its next repeat by 180
		milliseconds */
		if (gamepad_left != gamepad_right)
		{
			/* The held right direction advances focus and the held left direction moves backward */
			move_direction = gamepad_left ? -1 : 1;
			whats_new_navigation_due = current_time + 180;
		}
	}

	/* Only a requested movement rebuilds the available action order and advances the focused button */
	if (move_direction != 0)
	{
		/* focus_options contains scroll actions when notes overflow, includes Top only away from the
		start, and otherwise contains Back alone */
		var focus_options = whats_new_can_scroll
			? (whats_new_scroll_offset > 0 ? ["up", "down", "top", "back"] : ["up", "down", "back"])
			: ["back"];

		/* focus_index starts at the first available action while option_index searches this zero-based
		focus order for the existing focus */
		var focus_index = 0;

		/* Visit the available actions in order until the current focus is found */
		for (var option_index = 0; option_index < array_length(focus_options); option_index++)
		{
			/* A matching action records its index and ends the search so movement starts from the
			current focus */
			if (focus_options[option_index] == whats_new_focus)
			{
				focus_index = option_index;
				break;
			}
		}
		focus_index = (focus_index + move_direction + array_length(focus_options)) mod array_length(focus_options);
		whats_new_focus = focus_options[focus_index];
	}

	/* accept_pressed combines new Enter, Space, or first-gamepad confirm input for one-shot actions */
	var accept_pressed = keyboard_check_pressed(vk_enter)
		|| keyboard_check_pressed(vk_space)
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face1));

	/* accept_held combines held Enter, Space, or first-gamepad confirm input for repeated scrolling */
	var accept_held = keyboard_check(vk_enter)
		|| keyboard_check(vk_space)
		|| (gamepad_is_connected(0) && gamepad_button_check(0, gp_face1));

	/* up_held requires scrollable notes and either a held click over Up or held confirmation while Up
	is focused */
	var up_held = whats_new_can_scroll
		&& ((whats_new_hover == "up" && mouse_held)
			|| (whats_new_focus == "up" && accept_held));

	/* down_held applies the same held-action rule to Down, independently detecting opposing scroll
	requests */
	var down_held = whats_new_can_scroll
		&& ((whats_new_hover == "down" && mouse_held)
			|| (whats_new_focus == "down" && accept_held));

	/* Exactly one held scroll direction changes the offset, while simultaneous Up and Down cancel each
	other */
	if (up_held != down_held)
	{
		/* Down advances the notes ten GUI pixels per input update and Up moves them ten pixels toward
		the start */
		whats_new_scroll_offset += down_held ? 10 : -10;
	}

	/* top_pressed requires scrollable notes away from their beginning and a new Top click, focused
	confirmation, or Home key press */
	var top_pressed = whats_new_can_scroll
		&& whats_new_scroll_offset > 0
		&& ((whats_new_hover == "top" && mouse_pressed)
			|| (whats_new_focus == "top" && accept_pressed)
			|| keyboard_check_pressed(vk_home));

	/* A jump-to-start action clears the offset and focuses Down because Top is no longer available */
	if (top_pressed)
	{
		whats_new_scroll_offset = 0;
		whats_new_focus = "down";
	}

	/* Page Up moves backward by eighty percent of the visible notes height, with a minimum
	twenty-pixel step */
	if (keyboard_check_pressed(vk_pageup))
	{
		whats_new_scroll_offset -= max(20, (whats_new_text_end_y - whats_new_text_start_y) * 0.8);
	}

	/* Page Down applies the same page-sized movement toward the end of the notes */
	if (keyboard_check_pressed(vk_pagedown))
	{
		whats_new_scroll_offset += max(20, (whats_new_text_end_y - whats_new_text_start_y) * 0.8);
	}

	whats_new_scroll_offset = clamp(whats_new_scroll_offset, 0, whats_new_scroll_max);

	/* back_pressed combines a new Back click, focused confirmation, Escape, or the first gamepad's
	cancel button */
	var back_pressed = (whats_new_hover == "back" && mouse_pressed)
		|| (whats_new_focus == "back" && accept_pressed)
		|| keyboard_check_pressed(vk_escape)
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face2));

	/* Any back action closes the notes screen after this update has bounded its scroll position */
	if (back_pressed)
	{
		whats_new_close();
	}
	return true;
}
#endregion /* Update Notes Menu END */

#region /* Hosted Server Update */
/// @description Query the shared server's running-state method when available, falling back to a numeric nonnegative server socket
/// @returns {Bool} Whether authoritative server state reports an active session
network_server_is_running = function()
{
	/* server borrows the shared authoritative server manager for running-state inspection */
	var server = scr_get_server();

	/* An unavailable server struct cannot own a running session */
	if (!is_struct(server))
	{
		return false;
	}

	/* Prefer the server's explicit running-state handler when the field exists */
	if (variable_struct_exists(server, "is_running"))
	{
		/* running_handler borrows the optional running-state field before verifying it is callable */
		var running_handler = server.is_running;

		/* A method can evaluate the server's current lifecycle state directly instead of inferring it
		from a socket */
		if (is_method(running_handler))
		{
			return running_handler();
		}
	}

	/* Older server state counts as running only when a numeric nonnegative server socket is present */
	return variable_struct_exists(server, "server")
		&& is_real(server.server)
		&& server.server >= 0;
}

/* Server ownership and the visible client/console view are intentionally separate.
This authoritative tick keeps remote players alive while the host is playing locally */
/// @description Advance authoritative server state independently of the visible client/console view
/// @returns {Bool} Whether an owned running server was updated
network_update_hosted_server = function()
{
	/* Authoritative updates run only for a server owned by this controller that still reports a
	running session */
	if (!is_hosting_server || !network_server_is_running())
	{
		return false;
	}

	/* server_drawing borrows drawing authority for this tick while walls update their server-side
	state first */
	var server_drawing = scr_get_drawing();
	scr_get_walls().server_update();

	/* A drawing manager that provides server-network maintenance receives its authoritative update */
	if (is_struct(server_drawing)
	&& variable_struct_exists(server_drawing, "update_server_network"))
	{
		server_drawing.update_server_network();
	}

	/* server borrows the owned server manager, and movement_tick_started_at records get_timer
	microseconds before network and player maintenance */
	var server = scr_get_server();
	var movement_tick_started_at = get_timer();

	/* Update discovery when the server implements it so advertised server information stays current */
	if (variable_struct_exists(server, "update_discovery"))
	{
		server.update_discovery();
	}

	/* Available heartbeat maintenance keeps connected client liveness checks progressing during local
	host play */
	if (variable_struct_exists(server, "update_client_heartbeats"))
	{
		server.update_client_heartbeats();
	}

	/* Available character-send maintenance advances queued multiplayer character transfers */
	if (variable_struct_exists(server, "update_character_sends"))
	{
		server.update_character_sends();
	}

	/* Available typing-state maintenance expires or distributes remote chat indicators */
	if (variable_struct_exists(server, "update_typing_states"))
	{
		server.update_typing_states();
	}

	/* Available lifecycle maintenance handles scheduled session or reset work before player movement */
	if (variable_struct_exists(server, "update_lifecycle"))
	{
		server.update_lifecycle();
	}

	/* player_controller borrows the shared player registry for authoritative movement updates */
	var player_controller = scr_get_player_controller();

	/* Only a player controller exposing an array of slots can be traversed safely */
	if (is_struct(player_controller)
	&& variable_struct_exists(player_controller, "players")
	&& is_array(player_controller.players))
	{
		/* players borrows the controller's slot array, and i will visit its zero-based positions
		without compacting empty slots */
		var players = player_controller.players;

		/* Walk every player slot so all occupied connections receive the same authoritative movement
		tick */
		for (var i = 0; i < array_length(players); i++)
		{
			/* Occupied slots advance their server movement, while noone slots remain unused */
			if (players[i] != noone)
			{
				players[i].update_server();
			}
		}
	}

	/* Available collision-object maintenance synchronizes authoritative player collision state after
	movement */
	if (variable_struct_exists(server, "update_collision_objects"))
	{
		server.update_collision_objects();
	}

	/* Available AFK maintenance updates inactivity state after this tick's players have advanced */
	if (variable_struct_exists(server, "update_afk_states"))
	{
		server.update_afk_states();
	}

	/* Available position broadcasting distributes the completed authoritative movement state */
	if (variable_struct_exists(server, "update_position_broadcast"))
	{
		server.update_position_broadcast();
	}

	/* A server timing recorder receives this tick's elapsed microseconds converted to milliseconds */
	if (variable_struct_exists(server, "record_movement_tick"))
	{
		server.record_movement_tick((get_timer() - movement_tick_started_at) / 1000);
	}

	return true;
}
#endregion /* Hosted Server Update END */

#region /* Escape Hold Confirmation */
/* Escape exits require a hold so stray key taps do not leave active sessions */
/// @description Clear the Escape hold context, progress and inactive -1 start-time sentinel
escape_exit_hold_reset = function()
{
	escape_exit_hold_started_at = -1;
	escape_exit_hold_context = "";
	escape_exit_hold_progress = 0;
}

/// @description Track a held Escape key separately for each menu/session context
/// @param {String} _context Menu/session key. Changing it restarts the Escape hold
/// @param {Bool} _enabled Whether this UI permits Escape to leave
/// @returns {Bool} Whether escape_exit_hold_duration_ms elapsed and the hold was consumed
escape_exit_hold_update = function(_context, _enabled)
{
	/* A disabled exit action or released Escape key cannot complete a hold */
	if (!_enabled || !keyboard_check(vk_escape))
	{
		/* Reset the matching disabled context, or any context after the key is released, so stale progress cannot trigger a later exit */
		if (escape_exit_hold_context == _context || !keyboard_check(vk_escape))
		{
			escape_exit_hold_reset();
		}

		return false;
	}

	/* Entering another menu or session context starts a fresh current_time millisecond hold */
	if (escape_exit_hold_context != _context)
	{
		escape_exit_hold_context = _context;
		escape_exit_hold_started_at = current_time;
		escape_exit_hold_progress = 0;
		return false;
	}

	escape_exit_hold_progress = clamp((current_time - escape_exit_hold_started_at) / max(1, escape_exit_hold_duration_ms), 0, 1);

	/* Consume a completed hold once, resetting its state before reporting that the caller may exit */
	if (escape_exit_hold_progress >= 1)
	{
		escape_exit_hold_reset();
		return true;
	}

	return false;
}

/// @description Draw the matching Escape hold fraction inside supplied GUI bounds and reset alpha to one
/// @param {Real} _x Button left in GUI pixels
/// @param {Real} _y Button top in GUI pixels
/// @param {Real} _w Button width in GUI pixels
/// @param {Real} _h Button height in GUI pixels
/// @param {String} _context Menu or session hold context
escape_exit_hold_draw_progress = function(_x, _y, _w, _h, _context)
{
	/* Draw progress only for the current context and only after its hold has advanced */
	if (escape_exit_hold_context != _context || escape_exit_hold_progress <= 0)
	{
		return;
	}

	/* Inset the progress strip by five GUI pixels and use a five-pixel height
	The four bounds locate the strip inside the supplied button, bar_width cannot be negative, and progress is clamped to a fraction */
	var inset = 5;
	var bar_height = 5;
	var bar_x1 = _x + inset;
	var bar_y1 = _y + _h - inset - bar_height;
	var bar_x2 = _x + _w - inset;
	var bar_y2 = bar_y1 + bar_height;
	var bar_width = max(0, bar_x2 - bar_x1);
	var progress = clamp(escape_exit_hold_progress, 0, 1);

	draw_set_alpha(0.95);
	draw_set_colour(make_color_rgb(18, 18, 20));
	draw_rectangle(bar_x1, bar_y1, bar_x2, bar_y2, false);
	draw_set_colour(make_color_rgb(245, 196, 74));
	draw_rectangle(bar_x1, bar_y1, bar_x1 + bar_width * progress, bar_y2, false);
	draw_set_alpha(1);
}
#endregion /* Escape Hold Confirmation END */

#region /* World Camera and Zoom Controls */
/* Enable the render camera on view index zero without changing player or packet coordinates
network_camera starts unallocated at noone and is created by network_camera_configure
The controller retains and reuses this handle across mode and room transitions */
network_camera_enabled = true;
network_camera_view_index = 0;
network_camera = noone;

/* The base camera view is 1366 by 768 room pixels before zoom scaling
Its origin starts at zero, follow interpolation uses 0.16 per update, and has_target starts false so the first valid player snaps into view */
network_camera_view_width = 1366;
network_camera_view_height = 768;
network_camera_x = 0;
network_camera_y = 0;
network_camera_lerp = 0.16;
network_camera_has_target = false;

/* Target and current view-size multipliers start at one, equivalent to 100 percent zoom
initialized starts false for an initial snap, and locked starts false so the player can adjust zoom */
network_camera_zoom_target = 1;
network_camera_zoom_current = 1;
network_camera_zoom_initialized = false;
network_camera_zoom_locked = false;

/* Bound the preferred view-size multiplier so the camera can show detail or a wider drawing area
A multiplier of 0.35 displays about 286 percent zoom, and 3 displays about 33 percent
Room dimensions can reduce the effective zoom-out limit without replacing the saved preference
The 0.015 held-input step controls adjustment speed, while the 0.16 interpolation fraction softens each update
These are authored camera-tuning values, rather than network intervals or pixel-editor zoom levels */
network_camera_zoom_min = 0.35;
network_camera_zoom_max = 3;
network_camera_zoom_step = 0.015;
network_camera_zoom_lerp = 0.16;

/* The limit-flash opacity starts at zero and decays after a zoom limit is reached
Panel origin starts at zero until layout, with GUI-pixel width 214, height 64, row height 32, adjustment width 34 and reset width 64 */
network_camera_zoom_border_lerp = 0;
network_camera_zoom_panel_x = 0;
network_camera_zoom_panel_y = 0;
network_camera_zoom_panel_width = 214;
network_camera_zoom_panel_height = 64;
network_camera_zoom_row_height = 32;
network_camera_zoom_button_width = 34;
network_camera_zoom_reset_width = 64;

/* Virtual key codes 187 and 189 cover the main keyboard plus/equal and minus keys alongside the other checked aliases */
network_camera_zoom_key_in_main = 187;
network_camera_zoom_key_out_main = 189;

/* No zoom control is hovered initially, no status highlight deadline is active and percentage input starts unfocused and empty
mouse_captured starts false so its first captured gesture can release held player movement */
network_camera_zoom_hover = "";
network_camera_zoom_status_until = 0;
network_camera_zoom_input_active = false;
network_camera_zoom_input_text = "";
network_camera_zoom_mouse_captured = false;

/* Store zoom preferences in the camera INI section under percent, precise target and lock keys
Dirty starts false and save_due starts zero until an edit schedules a current_time millisecond save */
network_camera_zoom_settings_section = "camera";
network_camera_zoom_percent_key = "zoom_percent";
network_camera_zoom_target_key = "zoom_target";
network_camera_zoom_locked_key = "zoom_locked";
network_camera_zoom_settings_dirty = false;
network_camera_zoom_save_due = 0;

/* The controller-owned cached grid surface starts unallocated at -1 and is released by controller cleanup
surface_reduced starts false and records which detail mode an allocated grid contains */
network_world_grid_surface = -1;
network_world_grid_surface_reduced = false;

/// @description Derive the largest view-size scale permitted by configured limits and the current room dimensions
/// @returns {Real} Effective upper multiplier, bounded below by network_camera_zoom_min
network_camera_zoom_maximum = function()
{
	/* Compare room width and height with the base view to find the largest scale that fits both room axes */
	var room_scale_w = room_width / max(1, network_camera_view_width);
	var room_scale_h = room_height / max(1, network_camera_view_height);
	return max(network_camera_zoom_min, min(network_camera_zoom_max, min(room_scale_w, room_scale_h)));
}

/// @description Derive the effective lower view-size scale from the configured minimum and current maximum
/// @returns {Real} Minimum multiplier
network_camera_zoom_minimum = function()
{
	return min(network_camera_zoom_min, network_camera_zoom_maximum());
}

/// @description Clamp the effective view scale to room bounds while retaining the saved preference
/// @returns {Real} View-size multiplier. Lower values zoom in
network_camera_zoom_clamp_target = function()
{
	/* Keep the player's preferred target intact when a smaller room cannot
	currently display it. The effective target will expand back to the
	preference automatically in a room with enough space */
	return clamp(network_camera_zoom_target, network_camera_zoom_minimum(), network_camera_zoom_maximum());
}

/// @description Convert the saved view-size multiplier to a rounded display percentage without current-room clamping
/// @returns {Real} Preferred percentage of at least one
network_camera_zoom_preferred_percent = function()
{
	return max(1, round(100 / max(0.01, network_camera_zoom_target)));
}

/// @description Convert the current room-clamped target to its rounded display percentage
/// @returns {Real} Effective percentage of at least one
network_camera_zoom_percent = function()
{
	return max(1, round(100 / max(0.01, network_camera_zoom_clamp_target())));
}

/// @description Format the effective target percentage for the zoom label
/// @returns {String} Percentage text ending in percent
network_camera_zoom_text = function()
{
	return string(network_camera_zoom_percent()) + "%";
}

/// @description Accept at most four decimal digits without filtering or joining invalid input
/// @param {String} raw_text Candidate percentage
/// @returns {Bool} Whether all characters are digits and the length fits. Empty text also passes this character check
network_camera_zoom_input_is_valid = function(raw_text)
{
	/* Read the proposed percentage as text before validating its character count */
	var raw = string(raw_text);

	/* Reject more than four characters before scanning digits */
	if (string_length(raw) > 4)
	{
		return false;
	}

	/* Inspect one-based characters so only uninterrupted decimal digits are accepted */
	for (var char_index = 1; char_index <= string_length(raw); char_index++)
	{
		/* Read the current percentage character for digit validation */
		var ch = string_char_at(raw, char_index);

		/* Any nondigit rejects the entire input instead of silently joining separate digit groups */
		if (string_pos(ch, "0123456789") <= 0)
		{
			return false;
		}
	}

	return true;
}

/// @description Write preferred percentage, precise target and lock state, clearing dirty on success or scheduling a five-second retry on failure
/// @returns {Bool} Whether settings were written without an exception
network_camera_save_zoom_settings = function()
{
	try
	{
		ini_open(client_settings_file);
		ini_write_real(network_camera_zoom_settings_section, network_camera_zoom_percent_key, network_camera_zoom_preferred_percent());
		ini_write_real(network_camera_zoom_settings_section, network_camera_zoom_target_key, network_camera_zoom_target);

		/* Persist the Boolean zoom lock as numeric one or zero for INI storage */
		ini_write_real(network_camera_zoom_settings_section, network_camera_zoom_locked_key, network_camera_zoom_locked ? 1 : 0);
		ini_close();
		network_camera_zoom_settings_dirty = false;
		return true;
	}

	/* If writing fails, attempt to close INI state and postpone the next retry by 5000 local milliseconds
	The inline close_error handler ignores a secondary close failure so it cannot replace the original error */
	catch(e)
	{
		try { ini_close(); } catch(close_error) {}
		network_camera_zoom_save_due = current_time + 5000;
		debug_error("Could not save camera zoom settings: " + string(e.message));
		return false;
	}
}

/// @description Mark edited zoom settings and schedule a save 400 current_time milliseconds from now
network_camera_mark_zoom_settings_dirty = function()
{
	network_camera_zoom_settings_dirty = true;
	network_camera_zoom_save_due = current_time + 400;
}

/// @description Write dirty zoom settings only when their debounce or retry deadline has arrived
network_camera_save_zoom_settings_if_due = function()
{
	/* Save only edited preferences whose local millisecond debounce or retry deadline has arrived */
	if (network_camera_zoom_settings_dirty
	&& current_time >= network_camera_zoom_save_due)
	{
		network_camera_save_zoom_settings();
	}
}

/// @description Load saved zoom and lock preferences, preferring a positive precise target and otherwise converting the stored percentage
network_camera_load_zoom_settings = function()
{
	/* Start at 100 percent, no stored precise target (-1) and an unlocked camera when settings are missing */
	var saved_percent = 100;
	var saved_target = -1;
	var saved_locked = false;

	try
	{
		/* Read persisted values only when the shared client settings file exists */
		if (file_exists(client_settings_file))
		{
			ini_open(client_settings_file);
			saved_percent = ini_read_real(network_camera_zoom_settings_section, network_camera_zoom_percent_key, 100);
			saved_target = ini_read_real(network_camera_zoom_settings_section, network_camera_zoom_target_key, -1);

			/* A nonzero persisted lock value enables locking, while the missing-value default zero keeps zoom adjustable */
			saved_locked = ini_read_real(network_camera_zoom_settings_section, network_camera_zoom_locked_key, 0) != 0;
			ini_close();
		}
	}

	/* Keep available defaults after a load failure and attempt to close INI state
	The inline close_error handler ignores a secondary close exception */
	catch(e)
	{
		try { ini_close(); } catch(close_error) {}
		debug_error("Could not load camera zoom settings: " + string(e.message));
	}

	saved_percent = max(1, round(real(saved_percent)));

	/* Prefer a positive stored view-size multiplier for accurate round trips instead of reconstructing it from a rounded percentage */
	if (saved_target > 0)
	{
		network_camera_zoom_target = clamp(saved_target, network_camera_zoom_min, network_camera_zoom_max);
	}

	/* Older or missing precise targets reconstruct scale from the saved percentage and clamp it to configured limits */
	else
	{
		network_camera_zoom_target = clamp(100 / saved_percent, network_camera_zoom_min, network_camera_zoom_max);
	}
	network_camera_zoom_locked = saved_locked;
}

/// @description Set the zoom-limit border fully visible and retain the status highlight for 900 current_time milliseconds
network_camera_zoom_flash_limit = function()
{
	network_camera_zoom_border_lerp = 1;
	network_camera_zoom_status_until = current_time + 900;
}

/// @description Translate display percentage to inverse view scale, clamp it, and save or debounce settings
/// @param {Any} raw_percent Requested display zoom percentage. 100 is the base view size
/// @param {Bool} save_immediately Whether to write settings immediately. Defaults to true
/// @returns {Bool} Whether the percentage converted successfully
network_camera_set_zoom_percent = function(raw_percent, save_immediately = true)
{
	/* Start conversion at the base 100-percent value before attempting the supplied number */
	var requested_percent = 100;
	try
	{
		requested_percent = max(1, round(real(raw_percent)));
	}

	/* Reject a percentage that cannot convert to a real number without changing camera settings */
	catch(e)
	{
		return false;
	}

	/* Invert percentage into view-size scale, then distinguish configured-limit clamping from room-size clamping */
	var requested_target = 100 / requested_percent;
	var next_target = clamp(requested_target, network_camera_zoom_min, network_camera_zoom_max);
	var effective_target = clamp(next_target, network_camera_zoom_minimum(), network_camera_zoom_maximum());

	/* Flash the limit border when either configured limits or current room dimensions prevent the requested zoom */
	if (abs(next_target - requested_target) > 0.001
	|| abs(effective_target - next_target) > 0.001)
	{
		network_camera_zoom_flash_limit();
	}

	network_camera_zoom_target = next_target;
	network_camera_zoom_status_until = current_time + 1200;
	network_camera_zoom_settings_dirty = true;

	/* Explicit percentage commits write their preference immediately */
	if (save_immediately)
	{
		network_camera_save_zoom_settings();
	}

	/* Deferred edits mark preferences dirty and move their local millisecond debounce deadline */
	else
	{
		network_camera_mark_zoom_settings_dirty();
	}
	return true;
}

/// @description Request and immediately save 100-percent zoom when unlocked
/// @returns {Bool} Whether the request was accepted. False while locked
network_camera_reset_zoom = function()
{
	/* Respect the zoom lock by rejecting reset before altering the saved preference */
	if (network_camera_zoom_locked)
	{
		return false;
	}

	return network_camera_set_zoom_percent(100, true);
}

/// @description Focus an empty percentage field and refresh its status highlight when zoom is unlocked
/// @returns {Bool} Whether editing opened
network_camera_begin_zoom_input = function()
{
	/* Locked zoom cannot open percentage text entry */
	if (network_camera_zoom_locked)
	{
		return false;
	}

	network_camera_zoom_input_active = true;
	network_camera_zoom_input_text = "";
	keyboard_string = network_camera_zoom_input_text;
	network_camera_zoom_status_until = current_time + 1200;
	return true;
}

/// @description Close active zoom entry without applying its value
/// @param {Bool} clear_keyboard Clear shared keyboard text. Defaults to true
/// @returns {Bool} Whether an active edit was cancelled
network_camera_cancel_zoom_input = function(clear_keyboard = true)
{
	/* An inactive percentage field has nothing to cancel */
	if (!network_camera_zoom_input_active)
	{
		return false;
	}

	network_camera_zoom_input_active = false;
	network_camera_zoom_input_text = "";

	/* Clear shared keyboard text only when the caller permits it */
	if (clear_keyboard)
	{
		keyboard_string = "";
	}
	return true;
}

/// @description Close active zoom entry and immediately save a nonempty valid percentage
/// @param {Bool} clear_keyboard Clear shared keyboard text. Defaults to true
/// @returns {Bool} Whether a percentage was accepted. This does not confirm a successful settings write
network_camera_commit_zoom_input = function(clear_keyboard = true)
{
	/* Only an active percentage field can commit a value */
	if (!network_camera_zoom_input_active)
	{
		return false;
	}

	/* Keep the entered percentage locally before closing and clearing its field state */
	var entered_text = network_camera_zoom_input_text;
	network_camera_zoom_input_active = false;
	network_camera_zoom_input_text = "";

	/* Clear shared keyboard text when requested after ending percentage entry */
	if (clear_keyboard)
	{
		keyboard_string = "";
	}

	/* Empty or invalid text closes the field without changing the zoom preference */
	if (entered_text == ""
	|| !network_camera_zoom_input_is_valid(entered_text))
	{
		return false;
	}

	return network_camera_set_zoom_percent(entered_text, true);
}

/// @description Commit any active percentage edit, toggle locking and request an immediate settings save
/// @returns {Bool} Resulting zoom lock flag
network_camera_toggle_zoom_lock = function()
{
	/* Commit any active percentage edit before changing the lock state */
	if (network_camera_zoom_input_active)
	{
		network_camera_commit_zoom_input();
	}

	network_camera_zoom_locked = !network_camera_zoom_locked;
	network_camera_zoom_status_until = current_time + 1200;
	network_camera_zoom_settings_dirty = true;
	network_camera_save_zoom_settings();
	return network_camera_zoom_locked;
}

/// @description Adjust the effective view scale when unlocked, flashing limits or scheduling a debounced preference save
/// @param {Real} direction Signed adjustment direction. Negative zooms in and positive zooms out
/// @param {Real} amount Scale increment. Defaults to network_camera_zoom_step
/// @returns {Bool} Whether target scale changed beyond the 0.001 tolerance
network_camera_adjust_zoom = function(direction, amount = network_camera_zoom_step)
{
	/* Held zoom input has no effect while the camera is locked */
	if (network_camera_zoom_locked)
	{
		return false;
	}

	/* Adjust from the room-clamped current target, with signed direction times the requested scale increment */
	var old_zoom = network_camera_zoom_clamp_target();
	var next_zoom = clamp(old_zoom + direction * amount, network_camera_zoom_minimum(), network_camera_zoom_maximum());

	/* An adjustment that cannot change scale beyond the tolerance flashes the limit and reports no change */
	if (abs(next_zoom - old_zoom) <= 0.001)
	{
		network_camera_zoom_flash_limit();
		return false;
	}

	network_camera_zoom_target = next_zoom;
	network_camera_zoom_status_until = current_time + 1200;
	network_camera_mark_zoom_settings_dirty();
	return true;
}

/// @description Read the configured plus/equal and keypad zoom-in aliases
/// @returns {Bool} Whether any zoom-in alias is held
network_camera_zoom_in_held = function()
{
	/* Accept the main plus/equal key, keypad Add and plus/equal character aliases as held zoom-in input */
	return keyboard_check(network_camera_zoom_key_in_main)
		|| keyboard_check(vk_add)
		|| keyboard_check(ord("+"))
		|| keyboard_check(ord("="));
}

/// @description Read the configured minus and keypad zoom-out aliases
/// @returns {Bool} Whether any zoom-out alias is held
network_camera_zoom_out_held = function()
{
	/* Accept the main minus key, keypad Subtract and minus character alias as held zoom-out input */
	return keyboard_check(network_camera_zoom_key_out_main)
		|| keyboard_check(vk_subtract)
		|| keyboard_check(ord("-"));
}

/// @description Anchor the zoom panel at the GUI right edge with a 16-pixel margin and top 58
network_camera_zoom_update_layout = function()
{
	/* Anchor the panel 16 GUI pixels from the right edge using a nonzero viewport width */
	var gui_width = max(1, display_get_gui_width());
	network_camera_zoom_panel_x = gui_width - network_camera_zoom_panel_width - 16;
	network_camera_zoom_panel_y = 58;
}

/// @description Check gameplay and higher-priority player-list, text, social and character-editor input ownership
/// @returns {Bool} Whether camera controls must yield input
network_camera_zoom_input_blocked = function()
{
	/* Only active client gameplay permits camera controls, excluding the mode and join menus */
	if (!is_client || network_mode_screen || client_join_screen)
	{
		return true;
	}

	/* The held-Tab player list is drawn above this panel and keeps input priority */
	if (keyboard_check(vk_tab))
	{
		return true;
	}

	/* Check whether the shared chat input currently owns keyboard focus */
	var chat = scr_get_chat();

	/* Open chat takes input priority, with struct and field checks preceding its optional state */
	if (is_struct(chat)
	&& variable_struct_exists(chat, "is_open")
	&& chat.is_open)
	{
		return true;
	}

	/* Check whether drawing text entry currently owns keyboard input */
	var drawing = scr_get_drawing();

	/* A present text-entry capture helper blocks camera input while the drawing field is active */
	if (is_struct(drawing)
	&& variable_struct_exists(drawing, "text_entry_captures_keyboard")
	&& drawing.text_entry_captures_keyboard())
	{
		return true;
	}

	/* Read the social card focus used to suppress gameplay input */
	var social = scr_get_social();

	/* An open social card takes input priority over camera adjustment */
	if (is_struct(social)
	&& variable_struct_exists(social, "card_open")
	&& (social.card_open || social.pet_card_open))
	{
		return true;
	}

	/* Read character-editor modal input ownership */
	var character_maker = scr_get_character_maker();

	/* Block camera controls while the available character-editor helper captures game input */
	if (is_struct(character_maker)
	&& variable_struct_exists(character_maker, "blocks_game_input")
	&& character_maker.blocks_game_input())
	{
		return true;
	}

	return false;
}

/// @description Check a GUI point against inclusive rectangle bounds
/// @param {Real} mx Mouse X in GUI pixels
/// @param {Real} my Mouse Y in GUI pixels
/// @param {Real} x1 Left bound
/// @param {Real} y1 Top bound
/// @param {Real} x2 Right bound
/// @param {Real} y2 Bottom bound
/// @returns {Bool} Whether the point is inside or on an edge
network_camera_zoom_point_in_rect = function(mx, my, x1, y1, x2, y2)
{
	/* Include all four edges in the shared GUI rectangle hit test */
	return mx >= x1 && mx <= x2 && my >= y1 && my <= y2;
}

/// @description Apply zoom controls after higher-priority text, player-list, and character UI release input
/// @returns {Bool} Whether zoom text entry or mouse interaction captured input
network_camera_update_zoom_input = function()
{
	network_camera_zoom_update_layout();
	network_camera_zoom_hover = "";
	network_camera_save_zoom_settings_if_due();

	/* Releasing the left button clears remembered camera mouse capture */
	if (!mouse_check_button(mb_left))
	{
		network_camera_zoom_mouse_captured = false;
	}

	/* Higher-priority UI cancels zoom text entry and releases camera mouse capture for this update */
	if (network_camera_zoom_input_blocked())
	{
		network_camera_cancel_zoom_input();
		network_camera_zoom_mouse_captured = false;
		return false;
	}

	/* Read the mouse in GUI pixels and copy panel origin, width and button sizes for consistent hit testing
	The first row orders zoom-out, value, zoom-in and reset, and lock_y begins the second row */
	var mx = device_mouse_x_to_gui(0);
	var my = device_mouse_y_to_gui(0);
	var panel_x = network_camera_zoom_panel_x;
	var panel_y = network_camera_zoom_panel_y;
	var panel_w = network_camera_zoom_panel_width;
	var row_h = network_camera_zoom_row_height;
	var button_w = network_camera_zoom_button_width;
	var reset_w = network_camera_zoom_reset_width;
	var zoom_out_x = panel_x;
	var input_x = zoom_out_x + button_w;
	var input_w = panel_w - button_w * 2 - reset_w;
	var zoom_in_x = input_x + input_w;
	var reset_x = zoom_in_x + button_w;
	var lock_y = panel_y + row_h;

	/* The first-row minus rectangle selects the zoom-out control */
	if (network_camera_zoom_point_in_rect(mx, my, zoom_out_x, panel_y, zoom_out_x + button_w, panel_y + row_h))
	{
		network_camera_zoom_hover = "zoom_out";
	}

	/* The central percentage rectangle selects value entry */
	else if (network_camera_zoom_point_in_rect(mx, my, input_x, panel_y, input_x + input_w, panel_y + row_h))
	{
		network_camera_zoom_hover = "zoom_value";
	}

	/* The plus rectangle selects zoom-in */
	else if (network_camera_zoom_point_in_rect(mx, my, zoom_in_x, panel_y, zoom_in_x + button_w, panel_y + row_h))
	{
		network_camera_zoom_hover = "zoom_in";
	}

	/* The reset rectangle selects the base-zoom action */
	else if (network_camera_zoom_point_in_rect(mx, my, reset_x, panel_y, reset_x + reset_w, panel_y + row_h))
	{
		network_camera_zoom_hover = "zoom_reset";
	}

	/* The second row selects zoom locking */
	else if (network_camera_zoom_point_in_rect(mx, my, panel_x, lock_y, panel_x + panel_w, lock_y + row_h))
	{
		network_camera_zoom_hover = "zoom_lock";
	}

	/* Other pixels inside the panel still capture mouse input without selecting an action */
	else if (network_camera_zoom_point_in_rect(mx, my, panel_x, panel_y, panel_x + panel_w, panel_y + network_camera_zoom_panel_height))
	{
		network_camera_zoom_hover = "zoom_panel";
	}

	/* Track the initial left press separately from held adjustment input */
	var mouse_pressed = mouse_check_button_pressed(mb_left);

	/* Active percentage editing consumes keyboard text and its submit or cancel shortcuts before button actions */
	if (network_camera_zoom_input_active)
	{
		scr_text_input_update("camera_zoom", network_camera_zoom_input_text, 12);

		/* Read the synchronized keyboard text as the complete candidate percentage */
		var candidate_text = string(keyboard_string);

		/* Accept a candidate only when it satisfies the four-digit percentage policy */
		if (network_camera_zoom_input_is_valid(candidate_text))
		{
			network_camera_zoom_input_text = candidate_text;
		}

		/* Ignore an invalid character or paste instead of joining separated
		digit groups into a surprising percentage */
		else
		{
			keyboard_string = network_camera_zoom_input_text;
		}

		/* Escape cancels the percentage field and consumes this input update */
		if (keyboard_check_pressed(vk_escape))
		{
			network_camera_cancel_zoom_input();
			return true;
		}

		/* Enter commits the percentage field and consumes this update */
		if (keyboard_check_pressed(vk_enter))
		{
			network_camera_commit_zoom_input();
			return true;
		}

		/* Continue capturing input while editing unless a fresh mouse press requests another action */
		if (!mouse_pressed)
		{
			return true;
		}

		/* A press inside the active percentage field keeps editing without committing */
		if (network_camera_zoom_hover == "zoom_value")
		{
			return true;
		}

		network_camera_commit_zoom_input();

		/* A press outside the panel commits the field and remains consumed by this update */
		if (network_camera_zoom_hover == "")
		{
			return true;
		}
	}

	/* Start without mouse capture until a panel press or held gesture claims it */
	var captured_mouse = false;

	/* Initial presses handle text entry, reset and locking once per click */
	if (mouse_pressed)
	{
		/* A value-field press requests percentage entry and captures the pointer even if the lock rejects editing */
		if (network_camera_zoom_hover == "zoom_value")
		{
			network_camera_begin_zoom_input();
			captured_mouse = true;
		}

		/* A reset press requests 100-percent zoom and captures the pointer */
		else if (network_camera_zoom_hover == "zoom_reset")
		{
			network_camera_reset_zoom();
			captured_mouse = true;
		}

		/* A lock-row press toggles zoom locking and captures the pointer */
		else if (network_camera_zoom_hover == "zoom_lock")
		{
			network_camera_toggle_zoom_lock();
			captured_mouse = true;
		}

		/* Other initial panel presses are consumed so they cannot reach world drawing or movement */
		else if (network_camera_zoom_hover != "")
		{
			captured_mouse = true;
		}
	}

	/* Held panel input continuously adjusts plus or minus while retaining mouse capture */
	if (mouse_check_button(mb_left))
	{
		/* Plus decreases the view-size multiplier, making the world appear larger */
		if (network_camera_zoom_hover == "zoom_in")
		{
			network_camera_adjust_zoom(-1);
			captured_mouse = true;
		}

		/* Minus increases the view-size multiplier, revealing more of the world */
		else if (network_camera_zoom_hover == "zoom_out")
		{
			network_camera_adjust_zoom(1);
			captured_mouse = true;
		}

		/* A held button over the remaining panel area stays captured without changing zoom */
		else if (network_camera_zoom_hover != "")
		{
			captured_mouse = true;
		}
	}

	/* Only unlocked zoom processes held keyboard adjustment aliases */
	if (!network_camera_zoom_locked)
	{
		/* Read both held directions so simultaneous opposite inputs cancel each other */
		var zoom_in_held = network_camera_zoom_in_held();
		var zoom_out_held = network_camera_zoom_out_held();

		/* Zoom in only when its input is held without the opposite direction */
		if (zoom_in_held && !zoom_out_held)
		{
			network_camera_adjust_zoom(-1);
		}

		/* Zoom out only when its input is held without zoom-in */
		else if (zoom_out_held && !zoom_in_held)
		{
			network_camera_adjust_zoom(1);
		}
	}

	/* The first captured camera gesture releases held player movement once */
	if (captured_mouse && !network_camera_zoom_mouse_captured)
	{
		/* Use the client movement-release helper for that initial capture */
		var movement_client = scr_get_client();

		/* Release movement only when the client exposes the helper */
		if (is_struct(movement_client)
		&& variable_struct_exists(movement_client, "release_local_movement"))
		{
			movement_client.release_local_movement();
		}
	}
	network_camera_zoom_mouse_captured = captured_mouse;

	return captured_mouse;
}

/// @description Create or resize the controller camera, interpolate zoom and attach the view without moving world entities
/// @returns {Bool} Whether camera configuration is enabled and completed
network_camera_configure = function()
{
	/* A disabled render camera does not configure views or allocate a camera */
	if (!network_camera_enabled)
	{
		return false;
	}

	view_enabled = true;
	view_set_visible(network_camera_view_index, true);

	/* Use the effective room-clamped target to size the camera */
	var target_zoom = network_camera_zoom_clamp_target();

	/* Snap to the loaded zoom preference on first configuration instead of animating from an unrelated initial scale */
	if (!network_camera_zoom_initialized)
	{
		network_camera_zoom_current = target_zoom;
		network_camera_zoom_initialized = true;
	}

	/* Later configurations interpolate toward the effective target */
	else
	{
		network_camera_zoom_current = lerp(network_camera_zoom_current, target_zoom, network_camera_zoom_lerp);

		/* Snap the remaining tiny scale difference to its target to stop asymptotic interpolation */
		if (abs(network_camera_zoom_current - target_zoom) <= 0.001)
		{
			network_camera_zoom_current = target_zoom;
		}
	}

	/* Scale the base view into positive integer room-pixel dimensions that fit the room
	needs_camera records whether the retained handle is missing or invalid */
	var view_w = max(1, min(round(network_camera_view_width * network_camera_zoom_current), room_width));
	var view_h = max(1, min(round(network_camera_view_height * network_camera_zoom_current), room_height));
	var needs_camera = !is_real(network_camera) || network_camera < 0;

	/* Allocate a controller-owned camera only when no usable handle exists and attach it to the selected view */
	if (needs_camera)
	{
		network_camera = camera_create_view(0, 0, view_w, view_h);
		view_set_camera(network_camera_view_index, network_camera);
	}

	view_set_camera(network_camera_view_index, network_camera);
	camera_set_view_size(network_camera, view_w, view_h);
	camera_set_view_speed(network_camera, -1, -1);
	camera_set_view_border(network_camera, view_w, view_h);
	return true;
}

/// @description Clamp a proposed room-pixel camera origin using the current view size
/// @param {Real} origin_x Proposed world X
/// @param {Real} origin_y Proposed world Y
/// @returns {Struct} Clamped room-pixel x and y
network_camera_clamp_origin = function(origin_x, origin_y)
{
	/* Read the current camera dimensions in room pixels to keep its origin inside the room */
	var view_w = camera_get_view_width(network_camera);
	var view_h = camera_get_view_height(network_camera);

	/* Return room-pixel x/y coordinates limited so the complete view stays within the room */
	return
	{
		x: clamp(origin_x, 0, max(0, room_width - view_w)),
		y: clamp(origin_y, 0, max(0, room_height - view_h))
	};
}

/// @description Follow the local player smoothed visual position when available
/// @returns {Struct|Real} World-pixel x/y position, or noone without an assigned local player
network_camera_get_follow_position = function()
{
	/* Resolve the local assigned player slot before choosing a camera follow point */
	var client = scr_get_client();

	/* No client with an assigned player slot means there is no local character to follow */
	if (!is_struct(client)
	|| !variable_struct_exists(client, "ID")
	|| client.ID == noone)
	{
		return noone;
	}

	/* Look up the existing local player without allocating a missing roster record */
	var player = player_controller_get_player(client.ID, false);

	/* A vacant local slot has no follow position */
	if (player == noone)
	{
		return noone;
	}

	/* Start at the authoritative player room position before checking interpolation */
	var follow_x = player.pos.x;
	var follow_y = player.pos.y;

	/* Prefer the smoothed visual position so the camera follows the character currently drawn */
	if (variable_struct_exists(player, "visual_pos"))
	{
		follow_x = player.visual_pos.x;
		follow_y = player.visual_pos.y;
	}

	/* Return the selected world-pixel x/y follow point without modifying player coordinates */
	return { x: follow_x, y: follow_y };
}

/// @description Forget the existing follow target so the next local player position snaps into view
network_camera_reset_follow = function()
{
	network_camera_has_target = false;
}

/// @description Configure zoom and smoothly follow a local gameplay character, snapping after a missing target
network_camera_update = function()
{
	/* Skip follow updates when camera configuration is disabled or unavailable */
	if (!network_camera_configure())
	{
		return;
	}

	/* Menus and the server console do not follow a gameplay character */
	if (!is_client || network_mode_screen || client_join_screen)
	{
		return;
	}

	/* Read the local character follow point for this update */
	var follow_pos = network_camera_get_follow_position();

	/* Clear the remembered target when no local character exists so its next appearance can snap into view */
	if (follow_pos == noone)
	{
		network_camera_has_target = false;
		return;
	}

	/* Center the view on the follow point and clamp the resulting room-pixel origin */
	var view_w = camera_get_view_width(network_camera);
	var view_h = camera_get_view_height(network_camera);
	var target_origin = network_camera_clamp_origin(follow_pos.x - view_w * 0.5, follow_pos.y - view_h * 0.5);

	/* Snap the first valid target rather than sliding across the room from the old or default origin */
	if (!network_camera_has_target)
	{
		network_camera_x = target_origin.x;
		network_camera_y = target_origin.y;
		network_camera_has_target = true;
	}

	/* Smooth later follow movement and clamp again after interpolation near room edges */
	else
	{
		network_camera_x = lerp(network_camera_x, target_origin.x, network_camera_lerp);
		network_camera_y = lerp(network_camera_y, target_origin.y, network_camera_lerp);

		/* Keep the interpolated camera origin inside the room using the current view dimensions */
		var clamped_origin = network_camera_clamp_origin(network_camera_x, network_camera_y);
		network_camera_x = clamped_origin.x;
		network_camera_y = clamped_origin.y;
	}

	camera_set_view_pos(network_camera, network_camera_x, network_camera_y);
}

/// @description Reuse or recreate the controller-owned 256-pixel world-grid tile for the requested detail mode
/// @param {Bool} reduced Omit minor grid lines
/// @returns {Bool} Whether a valid grid surface is available
network_world_grid_ensure = function(reduced)
{
	/* Reuse a valid grid surface only when its recorded detail mode matches the requested mode */
	if (surface_exists(network_world_grid_surface)
	&& network_world_grid_surface_reduced == reduced)
	{
		return true;
	}

	/* Release an old surface before replacing it for a different grid detail mode */
	if (surface_exists(network_world_grid_surface))
	{
		surface_free(network_world_grid_surface);
	}
	network_world_grid_surface = surface_create(256, 256);

	/* A failed surface allocation leaves the caller to draw the world background directly */
	if (!surface_exists(network_world_grid_surface))
	{
		return false;
	}

	network_world_grid_surface_reduced = reduced;
	surface_set_target(network_world_grid_surface);
	draw_clear(make_color_rgb(18, 21, 24));
	draw_set_alpha(1);

	/* Detailed grid tiles include minor lines every 64 room pixels, while reduced tiles omit them */
	if (!reduced)
	{
		draw_set_colour(make_color_rgb(30, 34, 38));

		/* Draw zero-based minor line coordinates within the 256-pixel cached tile at 64-pixel intervals */
		for (var minor = 0; minor < 256; minor += 64)
		{
			draw_line(minor, 0, minor, 255);
			draw_line(0, minor, 255, minor);
		}
	}
	draw_set_colour(make_color_rgb(52, 58, 64));
	draw_line(0, 0, 0, 255);
	draw_line(0, 0, 255, 0);
	surface_reset_target();
	draw_set_alpha(1);
	return true;
}

/// @description Draw the world background and fixed scenery, using reduced mode, a cached grid or direct grid fallback
network_camera_draw_world = function()
{
	draw_set_alpha(1);

	/* Use reduced background rendering only when the optional global browser performance setting is present and enabled */
	var reduced_grid = variable_global_exists("html5_reduced_performance_mode")
		&& global.html5_reduced_performance_mode;

	/* Reduced mode paints a flat world background to avoid tiled grid drawing */
	if (reduced_grid)
	{
		draw_set_colour(make_color_rgb(18, 21, 24));
		draw_rectangle(0, 0, room_width, room_height, false);
	}

	/* Normal mode reuses or creates the detailed tile before drawing it across the world */
	else if (network_world_grid_ensure(false))
	{
		/* Retain the previous GPU texture filtering flag while rendering the grid without smoothing */
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);
		draw_surface_tiled(network_world_grid_surface, 0, 0);
		gpu_set_texfilter(restore_filter);
	}

	/* If tile allocation fails, draw the world background and grid lines directly */
	else
	{
		draw_set_colour(make_color_rgb(18, 21, 24));
		draw_rectangle(0, 0, room_width, room_height, false);
		draw_set_colour(make_color_rgb(30, 34, 38));

		/* Start at room coordinate zero and draw vertical minor grid lines every 64 world pixels through the room edge */
		for (var mx = 0; mx <= room_width; mx += 64) draw_line(mx, 0, mx, room_height);

		/* Start at room coordinate zero and draw horizontal minor grid lines every 64 world pixels through the room edge */
		for (var my = 0; my <= room_height; my += 64) draw_line(0, my, room_width, my);
		draw_set_colour(make_color_rgb(52, 58, 64));

		/* Start at room coordinate zero and draw vertical major grid lines every 256 world pixels through the room edge */
		for (var gx = 0; gx <= room_width; gx += 256) draw_line(gx, 0, gx, room_height);

		/* Start at room coordinate zero and draw horizontal major grid lines every 256 world pixels through the room edge */
		for (var gy = 0; gy <= room_height; gy += 256) draw_line(0, gy, room_width, gy);
	}

	/* Paint the four fixed world background rectangles before the final room boundary outline */
	draw_set_colour(make_color_rgb(70, 118, 92));
	draw_rectangle(120, 120, 420, 360, false);
	draw_set_colour(make_color_rgb(112, 78, 126));
	draw_rectangle(room_width - 520, 180, room_width - 160, 440, false);
	draw_set_colour(make_color_rgb(126, 104, 58));
	draw_rectangle(260, room_height - 430, 620, room_height - 160, false);
	draw_set_colour(make_color_rgb(70, 98, 132));
	draw_rectangle(room_width - 680, room_height - 520, room_width - 220, room_height - 180, false);

	draw_set_colour(make_color_rgb(190, 196, 202));
	draw_rectangle(0, 0, room_width - 1, room_height - 1, true);
}

/// @description Draw the client gameplay zoom panel and fading limit border, leaving left alignment and alpha one
/// @returns {Bool} Whether the gameplay panel was drawn
network_camera_draw_zoom_gui = function()
{
	/* Show the zoom panel only in active client gameplay, excluding mode and join menus */
	if (!is_client || network_mode_screen || client_join_screen)
	{
		return false;
	}

	/* Draw the limit warning while its opacity exceeds the small visibility threshold */
	if (network_camera_zoom_border_lerp > 0.01)
	{
		/* Measure the GUI viewport and reserve an eight-pixel warning border on all four edges */
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var border_w = 8;
		network_camera_zoom_border_lerp = lerp(network_camera_zoom_border_lerp, 0, 0.1);

		draw_set_alpha(network_camera_zoom_border_lerp);
		draw_set_colour(make_color_rgb(244, 84, 84));
		draw_rectangle(0, 0, gui_w, border_w, false);
		draw_rectangle(0, gui_h - border_w, gui_w, gui_h, false);
		draw_rectangle(0, border_w, border_w, gui_h - border_w, false);
		draw_rectangle(gui_w - border_w, border_w, gui_w, gui_h - border_w, false);
		draw_set_alpha(1);
	}

	network_camera_zoom_update_layout();

	/* Copy panel origin, dimensions and button widths in GUI pixels for rendering
	The first row positions zoom-out, value, zoom-in and reset, with the lock row directly below */
	var panel_x = network_camera_zoom_panel_x;
	var panel_y = network_camera_zoom_panel_y;
	var panel_w = network_camera_zoom_panel_width;
	var panel_h = network_camera_zoom_panel_height;
	var row_h = network_camera_zoom_row_height;
	var button_w = network_camera_zoom_button_width;
	var reset_w = network_camera_zoom_reset_width;
	var zoom_out_x = panel_x;
	var input_x = zoom_out_x + button_w;
	var input_w = panel_w - button_w * 2 - reset_w;
	var zoom_in_x = input_x + input_w;
	var reset_x = zoom_in_x + button_w;
	var lock_y = panel_y + row_h;

	/* Use the room-clamped target to determine available actions
	Zoom-in and zoom-out require an unlocked camera and remaining scale range, while reset compares the saved target with one */
	var effective_target = network_camera_zoom_clamp_target();
	var can_zoom_in = !network_camera_zoom_locked
		&& effective_target > network_camera_zoom_minimum() + 0.001;
	var can_zoom_out = !network_camera_zoom_locked
		&& effective_target < network_camera_zoom_maximum() - 0.001;
	var can_reset = !network_camera_zoom_locked
		&& abs(network_camera_zoom_target - 1) > 0.001;

	draw_set_alpha(0.82);
	draw_set_colour(make_color_rgb(18, 20, 24));
	draw_rectangle(panel_x, panel_y, panel_x + panel_w, panel_y + panel_h, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(86, 90, 98));
	draw_rectangle(panel_x, panel_y, panel_x + panel_w, panel_y + panel_h, true);

	/// @description Draw a measured GUI zoom action with enabled and hover styling
	/// @param {Real} button_x Button left in GUI pixels
	/// @param {Real} button_y Button top in GUI pixels
	/// @param {Real} button_w_arg Button width in GUI pixels
	/// @param {Real} button_h_arg Button height in GUI pixels
	/// @param {String} label Button text
	/// @param {String} hover_key Key matched against current zoom hover
	/// @param {Bool} enabled Whether active action styling applies
	/// @param {Real} label_size Text height in GUI pixels. Defaults to 18
	var draw_zoom_button = function(button_x, button_y, button_w_arg, button_h_arg, label, hover_key, enabled, label_size = 18)
	{
		/* Match this button hover key and select active or disabled fill, border and label colors */
		var hovered = network_camera_zoom_hover == hover_key;
		var fill = enabled ? make_color_rgb(54, 57, 62) : make_color_rgb(34, 36, 40);
		var border = enabled ? make_color_rgb(112, 116, 124) : make_color_rgb(70, 72, 76);
		var text_colour = enabled ? c_white : make_color_rgb(132, 134, 138);

		/* Highlight only an enabled hovered action so disabled controls retain their muted appearance */
		if (hovered && enabled)
		{
			fill = make_color_rgb(78, 82, 88);
			border = make_color_rgb(255, 220, 95);
		}

		draw_set_colour(fill);
		draw_rectangle(button_x, button_y, button_x + button_w_arg, button_y + button_h_arg, false);
		draw_set_colour(border);
		draw_rectangle(button_x, button_y, button_x + button_w_arg, button_y + button_h_arg, true);
		draw_set_halign(fa_center);
		draw_set_colour(text_colour);
		scr_render_text(button_x + button_w_arg * 0.5, button_y + 6, label, label_size, button_w_arg - 8);
	}

	draw_zoom_button(zoom_out_x, panel_y, button_w, row_h, "-", "zoom_out", can_zoom_out, 21);
	draw_zoom_button(zoom_in_x, panel_y, button_w, row_h, "+", "zoom_in", can_zoom_in, 21);
	draw_zoom_button(reset_x, panel_y, reset_w, row_h, "Reset", "zoom_reset", can_reset, 15);

	/* Percentage entry is enabled only while zoom is unlocked
	Track its hover state and choose readable active or disabled input colors */
	var input_enabled = !network_camera_zoom_locked;
	var input_hovered = network_camera_zoom_hover == "zoom_value";
	var input_fill = input_enabled ? make_color_rgb(26, 28, 32) : make_color_rgb(34, 36, 40);
	var input_border = input_enabled ? make_color_rgb(112, 116, 124) : make_color_rgb(70, 72, 76);
	var input_text_colour = input_enabled ? c_white : make_color_rgb(132, 134, 138);

	/* Highlight active editing, or an enabled value field that is hovered or within its local millisecond status interval */
	if (network_camera_zoom_input_active
	|| (input_enabled
		&& (input_hovered || current_time <= network_camera_zoom_status_until)))
	{
		input_border = make_color_rgb(255, 220, 95);
	}

	/* Start with the effective displayed percentage before replacing it with editable text */
	var input_label = network_camera_zoom_text();

	/* During editing, draw the current input, a blinking cursor and the percent suffix */
	if (network_camera_zoom_input_active)
	{
		input_label = network_camera_zoom_input_text;

		/* Show the cursor on alternating 420-millisecond intervals */
		if ((floor(current_time / 420) mod 2) == 0)
		{
			input_label += "|";
		}
		input_label += "%";
	}

	draw_set_colour(input_fill);
	draw_rectangle(input_x, panel_y, input_x + input_w, panel_y + row_h, false);
	draw_set_colour(input_border);
	draw_rectangle(input_x, panel_y, input_x + input_w, panel_y + row_h, true);
	draw_set_halign(fa_center);
	draw_set_colour(input_text_colour);
	scr_render_text(input_x + input_w * 0.5, panel_y + 7, input_label, 17, input_w - 8);

	/* Match the lock row hover state and choose locked-green or regular colors from the saved lock flag */
	var lock_hovered = network_camera_zoom_hover == "zoom_lock";
	var lock_fill = network_camera_zoom_locked ? make_color_rgb(42, 72, 52) : make_color_rgb(54, 57, 62);
	var lock_border = network_camera_zoom_locked ? make_color_rgb(126, 245, 150) : make_color_rgb(112, 116, 124);

	/* Highlight the hovered lock row while retaining its locked or unlocked color family */
	if (lock_hovered)
	{
		lock_fill = network_camera_zoom_locked ? make_color_rgb(52, 92, 64) : make_color_rgb(78, 82, 88);
		lock_border = make_color_rgb(255, 220, 95);
	}

	draw_set_colour(lock_fill);
	draw_rectangle(panel_x, lock_y, panel_x + panel_w, lock_y + row_h, false);
	draw_set_colour(lock_border);
	draw_rectangle(panel_x, lock_y, panel_x + panel_w, lock_y + row_h, true);

	/* Place a 16-GUI-pixel checkbox ten pixels from the panel left and vertically center it in the lock row */
	var box_size = 16;
	var box_x = panel_x + 10;
	var box_y = lock_y + (row_h - box_size) * 0.5;
	draw_set_colour(make_color_rgb(18, 20, 24));
	draw_rectangle(box_x, box_y, box_x + box_size, box_y + box_size, false);

	/* Use green for a checked lock outline and gray for its unchecked outline */
	draw_set_colour(network_camera_zoom_locked ? make_color_rgb(126, 245, 150) : make_color_rgb(190, 190, 194));
	draw_rectangle(box_x, box_y, box_x + box_size, box_y + box_size, true);

	/* Draw the checkmark only when zoom is locked */
	if (network_camera_zoom_locked)
	{
		draw_line_width(box_x + 3, box_y + 9, box_x + 7, box_y + 13, 2);
		draw_line_width(box_x + 7, box_y + 13, box_x + 14, box_y + 3, 2);
	}

	draw_set_halign(fa_left);
	draw_set_colour(c_white);
	scr_render_text(panel_x + 36, lock_y + 7, "Lock camera zoom", 16, panel_w - 46);
	draw_set_halign(fa_left);
	draw_set_alpha(1);
	return true;
}
#endregion /* World Camera and Zoom Controls END */

#region /* Startup Environment and Arguments */
network_camera_load_zoom_settings();
network_camera_configure();

/* Managed Linux services can choose a startup mode through the environment.
Some GameMaker Linux runners consume dash-prefixed process arguments before
parameter_count() exposes them to GML, while environment variables remain available.
Read and normalize the optional JONNIL_STARTUP_MODE setting for managed-service startup */
var environment_startup_mode = string_lower(string_trim(environment_get_variable("JONNIL_STARTUP_MODE")));

/* Accept only the four implemented network modes from the environment */
if (environment_startup_mode == "client"
|| environment_startup_mode == "server"
|| environment_startup_mode == "host_play"
|| environment_startup_mode == "singleplayer")
{
	network_startup_mode = environment_startup_mode;
}

/* Read one-based launch arguments in order so later recognized arguments can replace earlier choices */
for (var i = 1; i <= parameter_count(); i++)
{
	/* Keep the trimmed original argument for case-sensitive address content and a lowercase copy for option-name matching */
	var raw_param = string_trim(parameter_string(i));
	var param = string_lower(raw_param);

	/* The explicit client flag selects the remote-server menu */
	if (param == "-client")
	{
		network_startup_mode = "client";
	}

	/* The server flag selects the local dedicated console */
	else
	if (param == "-server")
	{
		network_startup_mode = "server";
	}

	/* Either host-and-play alias selects local hosting with a loopback player */
	else
	if (param == "-hostplay" || param == "-host-and-play")
	{
		network_startup_mode = "host_play";
	}

	/* The singleplayer flag selects the offline local session */
	else
	if (param == "-singleplayer")
	{
		network_startup_mode = "singleplayer";
	}

	/* A separate connect argument consumes its following value only when another launch argument exists */
	else
	if (param == "-connect" && i < parameter_count())
	{
		i++;
		network_startup_connect_address = string_trim(parameter_string(i));
	}

	/* The equals form extracts the original-spelling address after the nine-character option prefix */
	else
	if (string_pos("-connect=", param) == 1)
	{
		network_startup_connect_address = string_trim(string_copy(raw_param, 10, string_length(raw_param) - 9));
	}

	/* A separate username argument consumes its following value when available */
	else
	if (param == "-username" && i < parameter_count())
	{
		i++;
		network_startup_username = string_trim(parameter_string(i));
	}

	/* The equals form extracts the original-spelling username after the ten-character option prefix */
	else
	if (string_pos("-username=", param) == 1)
	{
		network_startup_username = string_trim(string_copy(raw_param, 11, string_length(raw_param) - 10));
	}
}

/* A nonempty direct target overrides the selected startup mode with client mode */
if (network_startup_connect_address != "")
{
	network_startup_mode = "client";
}

/* The cloud service selects server mode through the environment. Keep manual
-server launches visible, but avoid rendering the managed server console into
Xvfb/Mesa on every frame */
managed_dedicated_server = environment_startup_mode == "server"
	&& network_startup_mode == "server";

/* Start retained server logs early for managed dedicated startup diagnostics */
if (managed_dedicated_server)
{
	scr_server_logs_start();
}

/* Hide the visible server-log console until the chosen startup mode explicitly opens it */
show_logs = false;
#endregion /* Startup Environment and Arguments END */

#region /* Remote Connection and Server Selection */
/// @description Normalize a target using client transport parsing and provide fallback address guidance
/// @param {String} address Requested target
/// @returns {Struct} Parse result with ok, url, port, address, transport, placeholder and message
client_parse_join_address = function(address)
{
	/* Start with a failed parse, empty host/display address, port zero, default TCP transport and no placeholder
	message carries validation feedback, while successful parsing replaces all connection fields */
	var result =
	{
		ok: false,
		url: "",
		port: 0,
		address: "",
		transport: TRANSPORT_TCP,
		placeholder: false,
		message: ""
	};

	/* Fetch shared network state before delegating address parsing to the client transport policy */
	var net = scr_get_network();

	/* Retain the client parser result with normalized address, transport and validation feedback */
	var parsed = scr_get_client().parse_server_address(address);

	/* Return failure with the parser message when available, otherwise the authored address-format guidance */
	if (!parsed.ok)
	{
		result.message = parsed.message != "" ? parsed.message : "Use address format: 192.168.0.34:8080";
		return result;
	}

	result.ok = true;
	result.url = parsed.url;
	result.port = parsed.port;
	result.address = parsed.address;
	result.transport = parsed.transport;
	result.placeholder = parsed.placeholder;
	return result;
}

/// @description Validate target and username. Defer TCP hostname connections until Async HTTP resolves them
/// @returns {Bool} Whether the socket connection started. False also covers a pending DNS lookup
client_join_attempt = function()
{
	client_username = chat_filter_username_input(client_username);

	/* Validate the filtered profile name before discovery selection, DNS or socket setup */
	var username_validation = client_username_validation_message(client_username);

	/* An incomplete username stops the join and directs the user back to profile entry */
	if (username_validation != "")
	{
		client_join_error = "Go back and enter a username.";
		client_join_status = "Join failed.";
		debug_error(username_validation);
		return false;
	}

	client_save_username();

	/* Start from the manual address, runtime transport default and current profile name
	Admin intent starts false until an official discovery row explicitly requests it */
	var target_address = client_join_address;
	var target_transport = scr_get_network().default_client_transport();
	var requested_username = client_username;
	var target_admin_intent = false;

	/* List-based joining resolves the selected discovery row, while direct mode keeps its manual target */
	if (!client_join_direct_mode)
	{
		/* Read the discovered server rows from client state */
		var selected_client = scr_get_client();

		/* Require an initialized list and an in-range nonnegative selection before indexing its row */
		if (!is_struct(selected_client)
		|| !variable_struct_exists(selected_client, "server_list_entries")
		|| !is_array(selected_client.server_list_entries)
		|| client_join_selected == noone
		|| client_join_selected < 0
		|| client_join_selected >= array_length(selected_client.server_list_entries))
		{
			client_join_error = "Select a server first.";
			client_join_status = "Join failed.";
			return false;
		}

		/* Read the selected server row and mark admin intent only when its source identifies the official listing */
		var selected_entry = selected_client.server_list_entries[client_join_selected];
		target_admin_intent = variable_struct_exists(selected_entry, "source")
			&& selected_entry.source == "official";

		/* Placeholder or disabled rows cannot start a join */
		if (!variable_struct_exists(selected_entry, "selectable")
		|| !selected_entry.selectable)
		{
			client_join_error = "Select a server first.";
			client_join_status = "Join failed.";
			return false;
		}

		/* An offline or unknown-online row stops joining with its available status text or a connection fallback */
		if (!variable_struct_exists(selected_entry, "online")
		|| !selected_entry.online)
		{
			client_join_error = variable_struct_exists(selected_entry, "status") ? selected_entry.status : "Can't connect to server.";
			client_join_status = "Join failed.";
			return false;
		}

		/* Reject known full or explicitly nonjoinable servers, preferring their published status message */
		if ((variable_struct_exists(selected_entry, "full") && selected_entry.full)
		|| (variable_struct_exists(selected_entry, "joinable") && !selected_entry.joinable))
		{
			client_join_error = variable_struct_exists(selected_entry, "status") ? selected_entry.status : "Server is full.";
			client_join_status = "Join failed.";
			return false;
		}

		target_address = selected_entry.address;

		/* Use a discovery row transport when present before the normalized address parser resolves the final transport */
		if (variable_struct_exists(selected_entry, "transport"))
		{
			target_transport = selected_entry.transport;
		}
	}

	/* Validate and normalize the chosen address using the same client parsing policy as manual entry */
	var parsed = client_parse_join_address(target_address);

	/* Invalid addresses show parser feedback and stop before DNS or connection setup */
	if (!parsed.ok)
	{
		client_join_error = parsed.message;
		client_join_status = "Join failed.";
		debug_error("Join failed: " + parsed.message);
		return false;
	}

	/* Reject the unpublished HTML5 address placeholder rather than attempting a connection to it */
	if (parsed.placeholder)
	{
		client_join_error = "Set PUBLIC_WSS_ADDRESS before publishing the HTML5 build.";
		client_join_status = "Join failed.";
		debug_error(client_join_error);
		return false;
	}

	target_transport = parsed.transport;

	#region /* Async DNS Resolution for TCP Domain Names */
	/* TCP hostnames require an asynchronous DNS lookup, while IPv4 and non-TCP targets can proceed directly */
	if (target_transport == TRANSPORT_TCP && !is_ipv4_address(parsed.url))
	{
		/* Keep one pending DNS request and reject a second join attempt until it completes or times out */
		if (client_dns_pending && client_dns_request_id != noone)
		{
			client_join_error = "Already resolving " + parsed.url + "...";
			return false;
		}

		client_dns_pending = true;
		client_dns_pending_url = parsed.url;
		client_dns_pending_port = parsed.port;
		client_dns_pending_transport = target_transport;
		client_dns_pending_display_address = parsed.address;
		client_dns_pending_join_direct_mode = client_join_direct_mode;
		client_dns_pending_username = requested_username;
		client_dns_pending_admin_intent = target_admin_intent;
		client_join_status = "Resolving " + parsed.url + "...";
		client_join_error = "";

		client_dns_request_id = dns_resolve_domain(parsed.url);

		/* Bound the pending lookup with the shared connect timeout in local current_time milliseconds */
		client_dns_deadline = current_time + scr_get_network().connect_timeout_ms;

		/* An immediate DNS request failure clears its pending state and reports join failure */
		if (client_dns_request_id < 0)
		{
			client_dns_pending = false;
			client_dns_deadline = 0;
			client_dns_request_id = noone;
			client_dns_pending_admin_intent = false;
			client_join_error = "Could not start hostname lookup. Check the address and your connection.";
			client_join_status = "Join failed.";
			return false;
		}
		debug_log("DNS resolution started for: " + parsed.url + " (request id: " + string(client_dns_request_id) + ")");
		return false;
	}
	#endregion /* Async DNS Resolution for TCP Domain Names END */

	client_join_address = parsed.address;

	/* Restore text for the direct-address dialog, otherwise the active address field or profile username */
	keyboard_string = client_join_dialog == "direct" ? client_join_dialog_address : (client_join_focus == "address" ? client_join_address : client_username);

	/* Get the client transport and preserve the connection-start result
	Joining still completes asynchronously after a nonnegative start result */
	var client = scr_get_client();
	var connect_result = client.init(parsed.url, parsed.port, target_transport, parsed.address, requested_username, false, target_admin_intent);
	client_join_status = client.connect_status;

	/* A failed socket creation or connection start reports the target address as a join error */
	if (connect_result < 0)
	{
		client_join_error = "Could not connect to " + client_join_address;
		return false;
	}

	client_join_error = "";
	client_join_status = client.connect_status;
	return true;
}

/// @description Resume the pending TCP join while retaining the display address and username
/// @param {String} resolved_ip Resolved IPv4 address, or empty on lookup failure
/// @returns {Bool} Whether the resumed socket connection started
client_join_with_resolved_ip = function(resolved_ip)
{
	/* Ignore a resolved address when there is no longer a pending join request */
	if (!client_dns_pending)
	{
		return false;
	}
	client_dns_deadline = 0;

	/* Empty or non-IPv4 resolution results clear the request and report DNS failure */
	if (resolved_ip == "" || !is_ipv4_address(resolved_ip))
	{
		client_dns_pending = false;
		client_dns_request_id = noone;
		client_dns_pending_admin_intent = false;
		client_join_error = "DNS resolution failed for " + client_dns_pending_url;
		client_join_status = "Join failed.";
		debug_error(client_join_error);
		return false;
	}

	/* Retain the resolved IPv4 endpoint with the pending port, transport, username, admin intent and display label
	The public display label stays distinct from the numeric connection endpoint */
	var actual_url = resolved_ip;
	var actual_port = client_dns_pending_port;
	var actual_transport = client_dns_pending_transport;
	var requested_username = client_dns_pending_username;
	var admin_intent = client_dns_pending_admin_intent;
	var display_address = client_dns_pending_display_address;

	/* Reconstruct a hostname-and-port label when the pending request did not retain one */
	if (display_address == "")
	{
		display_address = client_dns_pending_url + ":" + string(actual_port);
	}

	client_dns_pending = false;
	client_dns_request_id = noone;
	client_join_address = display_address;

	/* Restore the currently active dialog address or menu field text after DNS completion */
	keyboard_string = client_join_dialog == "direct" ? client_join_dialog_address : (client_join_focus == "address" ? client_join_address : client_username);

	/* Resume the client connection with the saved request fields and retain its immediate transport result */
	var client = scr_get_client();
	var connect_result = client.init(actual_url, actual_port, actual_transport, display_address, requested_username, false, admin_intent);
	client_join_status = client.connect_status;

	/* A failed resumed connection reports the preserved display address rather than its internal resolved IP */
	if (connect_result < 0)
	{
		client_join_error = "Could not connect to " + display_address;
		return false;
	}

	client_join_error = "";
	client_join_status = client.connect_status;

	return true;
}

/// @description Cancel pending join lookup and dialog state, refresh discovery and reset selection and text focus
client_join_refresh = function()
{
	client_join_dialog = "";
	client_join_last_click_row = noone;
	client_dns_pending = false;
	client_dns_deadline = 0;
	client_dns_request_id = noone;
	client_dns_pending_admin_intent = false;

	/* Use the shared client discovery service after clearing old DNS and dialog state */
	var client = scr_get_client();

	/* Request a fresh discovery pass only when the client exposes its refresh helper */
	if (is_struct(client)
	&& variable_struct_exists(client, "refresh_discovery"))
	{
		client.refresh_discovery();
	}

	client_join_error = "";
	client_join_status = client.discovery_status;
	client_join_selected = noone;
	client_join_scroll = 0;
	client_join_direct_mode = false;
	client_join_focus = "";
	keyboard_string = "";
}

/// @description Open refreshed server selection after resetting gameplay UI, optionally disconnecting the outgoing client
/// @param {String} status_text Menu feedback. Defaults to Select a server.
/// @param {Bool} close_socket Request client disconnect. Defaults to false
client_open_server_list = function(status_text = "Select a server.", close_socket = false)
{
	client_dns_pending = false;
	client_dns_deadline = 0;
	client_dns_request_id = noone;
	client_dns_pending_admin_intent = false;
	escape_exit_hold_reset();
	official_admin_controls_open = false;
	official_admin_hover_button = "";
	official_admin_focus = "";
	official_admin_restart_confirm_until = 0;
	official_admin_reset_confirm_until = 0;
	network_camera_cancel_zoom_input();

	/* Save edited zoom preferences before leaving gameplay for server selection */
	if (network_camera_zoom_settings_dirty)
	{
		network_camera_save_zoom_settings();
	}

	/* Read the client transport for optional disconnect and discovery refresh */
	var client = scr_get_client();

	/* Disconnect only when requested and the available client exposes the cleanup helper */
	if (close_socket
	&& is_struct(client)
	&& variable_struct_exists(client, "disconnect"))
	{
		client.disconnect(status_text);
	}

	/* When disconnect is not requested or its helper is unavailable, explicitly clear player, AFK and client collision state for the menu transition */
	else
	{
		player_controller_clear_players();
		scr_get_chat().clear_afk_states();
		scr_get_collision_objects().reset_client();
	}

	network_camera_reset_follow();
	client_join_screen = true;
	client_join_dialog = "";
	client_join_action_focus = "join";
	client_join_direct_mode = false;
	client_join_error = "";
	client_join_status = string(status_text);
	client_join_address = scr_get_network().default_manual_address();
	client_username = chat_filter_username_input(client_username);
	client_join_selected = noone;
	client_join_scroll = 0;
	client_join_hover_button = "";
	client_join_hover_row = noone;
	client_join_button_hover = false;
	client_leave_button_hover = false;
	client_join_focus = "";
	keyboard_string = "";
	show_logs = false;

	/* Refresh discovery when the helper exists and clear the deferred server-list request flag */
	if (is_struct(client)
	&& variable_struct_exists(client, "refresh_discovery"))
	{
		client.refresh_discovery();
		client.needs_server_list = false;
	}
}
#endregion /* Remote Connection and Server Selection END */

#region /* Network Mode Transitions */
/// @description Stop any owned server and open remote server selection after profile validation
/// @param {String} status_text Status displayed after the transition. Defaults to Select a server.
/// @returns {Bool} Whether client mode opened after username validation
network_start_client_mode = function(status_text = "Select a server.")
{
	escape_exit_hold_reset();

	/* Require a usable profile before shutting down hosting and opening remote-server selection */
	if (!client_require_username("Enter a username before joining."))
	{
		return false;
	}

	/* Read the owned authoritative server before switching the controller to a remote-client session */
	var server = scr_get_server();

	/* Shut down hosting only when the shared server exposes its lifecycle helper */
	if (is_struct(server)
	&& variable_struct_exists(server, "shutdown"))
	{
		server.shutdown();
	}
	scr_server_logs_stop("Switched to client mode.");

	/* Read the client state whose local-host marker must be cleared for remote play */
	var client = scr_get_client();

	/* Clear the local-host marker when it exists so future disconnects use remote-client cleanup rules */
	if (is_struct(client)
	&& variable_struct_exists(client, "local_host_mode"))
	{
		client.local_host_mode = false;
	}

	is_hosting_server = false;
	host_play_active = false;
	host_claim_pending = false;
	host_session_menu_open = false;
	is_client = true;
	is_singleplayer = false;
	network_mode_screen = false;
	network_update_window_caption("CLIENT");
	show_logs = false;
	client_join_screen = false;
	client_join_address = scr_get_network().default_manual_address();
	client_username = chat_filter_username_input(client_username);
	client_join_error = "";
	client_join_status = "";
	client_dns_pending = false;
	client_dns_request_id = noone;
	client_join_focus = "";
	keyboard_string = "";
	network_camera_reset_follow();
	client_open_server_list(status_text, true);
	debug_log("Client mode active. Join screen is open.");
	return true;
}

/// @description Validate the profile, switch to remote-client mode and attempt the supplied direct target
/// @param {String} address Direct server address
/// @returns {Bool} Whether the connection started. False also covers a pending DNS lookup
network_start_direct_client_mode = function(address)
{
	network_pending_direct_connect_address = string_trim(string(address));

	/* Profile rejection prevents the pending direct address from starting a socket connection */
	if (!network_start_client_mode("Connecting directly..."))
	{
		return false;
	}

	client_join_direct_mode = true;
	client_join_address = network_pending_direct_connect_address;
	network_pending_direct_connect_address = "";
	client_join_selected = noone;
	client_join_scroll = 0;
	client_join_focus = "";
	keyboard_string = "";
	return client_join_attempt();
}

/// @description Open local listeners using the native listen configuration and switch to the console
/// @returns {Bool} Whether the hosted server is running
network_start_server_mode = function()
{
	escape_exit_hold_reset();

	/* Read the outgoing client before replacing client gameplay with local hosting */
	var client = scr_get_client();

	/* Clean up available client transport and discovery state before starting local listeners */
	if (is_struct(client))
	{
		/* Disconnect an outgoing client when the helper exists */
		if (variable_struct_exists(client, "disconnect"))
		{
			client.disconnect("Switched to server mode.");
		}

		/* Remove the loopback marker so the new hosting lifecycle starts from console mode */
		if (variable_struct_exists(client, "local_host_mode"))
		{
			client.local_host_mode = false;
		}

		/* Stop discovery polling while operating the dedicated console */
		if (variable_struct_exists(client, "stop_discovery"))
		{
			client.stop_discovery();
		}
	}

	is_client = false;
	is_singleplayer = false;
	is_hosting_server = false;
	host_play_active = false;
	host_claim_pending = false;
	host_session_menu_open = false;
	network_mode_screen = false;
	network_update_window_caption("SERVER");
	client_join_screen = false;
	client_join_error = "";
	client_join_status = "";
	client_dns_pending = false;
	client_dns_request_id = noone;
	client_join_focus = "username";
	keyboard_string = "";
	network_camera_reset_follow();
	server_mode_focus = "";
	server_mode_status = "";

	/* Enter the server room when the controller was in another room */
	if (room != room_server)
	{
		room_goto(room_server);
	}

	/* Read the authoritative server instance that will own local listeners */
	var server = scr_get_server();

	/* Require an initialized server with an init member before attempting startup */
	if (!is_struct(server) || !variable_struct_exists(server, "init"))
	{
		show_debug_message("Network server missing init method.");
		return false;
	}

	/* Retain the server initialization member so its callability can be checked before invoking it */
	var init_handler = server.init;

	/* A noncallable initialization member cannot start hosting */
	if (!is_method(init_handler))
	{
		show_debug_message("Network server init is not callable.");
		return false;
	}


	/* Restore the configured native listen address because prior outgoing connections may have changed shared URL and port
	local_address retains its TCP parse result before assigning the listener endpoint */
	var net = scr_get_network();
	var local_address = net.parse_server_address(net.native_default_address, net.port, TRANSPORT_TCP);

	/* Replace the shared listener URL and port only when native configuration parsed successfully */
	if (local_address.ok)
	{
		net.url = local_address.url;
		net.port = local_address.port;
	}

	scr_server_logs_start();
	init_handler(managed_dedicated_server);
	is_hosting_server = network_server_is_running();

	/* A server without active required listeners returns the controller to mode selection and displays its status or a fallback error */
	if (!is_hosting_server)
	{
		is_client = true;
		network_mode_screen = true;
		network_mode_status = variable_struct_exists(server, "msg") && server.msg != ""
			? server.msg
			: "Server failed to start.";
		network_update_window_caption();
		show_logs = false;

		/* A failed managed-service startup exits the game so the external service manager can retry */
		if (managed_dedicated_server)
		{
			debug_error("Managed dedicated server startup failed. Exiting so the service manager can retry.");
			scr_server_logs_stop("Server startup failed.");
			game_end();
		}

		/* A manual startup failure closes server logs and leaves the mode menu available */
		else
		{
			scr_server_logs_stop("Server startup failed.");
		}
		return false;
	}

	/* Managed hosting disables automatic Draw events to avoid rendering its console every frame */
	if (managed_dedicated_server)
	{
		show_logs = false;
		draw_enable_drawevent(false);
		debug_log("Managed dedicated server: automatic Draw events disabled.");
	}

	/* Manual hosting keeps the visible server log console enabled */
	else
	{
		show_logs = true;
	}
	server_mode_status = "Server is running. Join when you are ready.";

	/* Display the running server actual player capacity when available */
	if (variable_struct_exists(server, "max_players"))
	{
		server_max_players_text = string(server.max_players);
	}
	debug_log("Server mode active.");
	return true;
}

/// @description Join the running local server over loopback while its authoritative updates continue
/// @returns {Bool} Whether the loopback connection started
network_join_owned_server = function()
{
	escape_exit_hold_reset();
	client_username = chat_filter_username_input(client_username);

	/* Validate the filtered profile before connecting its local host player */
	var validation_message = client_username_validation_message(client_username);

	/* Invalid profiles stay in the server console with username entry focused */
	if (validation_message != "")
	{
		server_mode_status = validation_message;
		server_mode_focus = "username";
		keyboard_string = client_username;
		return false;
	}

	/* Join only a server that this controller owns and that still has active required listeners */
	if (!is_hosting_server || !network_server_is_running())
	{
		server_mode_status = "The hosted server is not running.";
		return false;
	}

	client_save_username();

	/* Use the client transport for the loopback player while the authoritative server continues running */
	var client = scr_get_client();

	/* Stop discovery before the local client connects to its owned server */
	if (is_struct(client)
	&& variable_struct_exists(client, "stop_discovery"))
	{
		client.stop_discovery();
	}

	is_client = true;
	is_singleplayer = false;
	host_play_active = true;
	host_claim_pending = true;
	host_session_menu_open = false;
	network_mode_screen = false;
	client_join_screen = false;
	client_join_error = "";
	client_join_status = "Connecting to your hosted server...";
	client_dns_pending = false;
	client_dns_request_id = noone;
	client_dns_pending_admin_intent = false;
	client_dns_pending_admin_intent = false;
	client_join_focus = "";
	server_mode_focus = "";
	keyboard_string = "";
	show_logs = false;
	network_camera_reset_follow();
	network_update_window_caption("HOST & PLAY");

	/* Use the server shared listen port and a loopback display label for the local TCP connection
	connect_result records only whether its asynchronous connection could start */
	var net = scr_get_network();
	var local_port = net.port;
	var local_display = "127.0.0.1:" + string(local_port);
	var connect_result = client.init("127.0.0.1", local_port, TRANSPORT_TCP, local_display, client_username, true);
	client_join_status = client.connect_status;

	/* A failed loopback start returns to the console without shutting down remote players or the authoritative server */
	if (connect_result < 0)
	{

		/* Client.init already reset the client-only drawing and chat view
		Clear the failed loopback marker so later transitions cannot inherit host-only cleanup rules */
		if (variable_struct_exists(client, "local_host_mode"))
		{
			client.local_host_mode = false;
		}
		host_play_active = false;
		host_claim_pending = false;
		is_client = false;
		show_logs = true;
		server_mode_status = "Could not join your hosted server. It is still running.";
		network_update_window_caption("SERVER");
		return false;
	}

	debug_log("Host & Play connecting through " + local_display + ".");
	return true;
}

/// @description Require a profile, start local hosting and begin a loopback player connection
/// @returns {Bool} Whether the loopback connection started
network_start_host_play_mode = function()
{
	/* Validate the profile before starting a server that the player intends to join locally */
	if (!client_require_username("Enter a username before using Host & Play."))
	{
		return false;
	}

	/* Do not attempt loopback play when local listener startup failed */
	if (!network_start_server_mode())
	{
		return false;
	}

	return network_join_owned_server();
}

/// @description Disconnect the local host player while the owned server and remote players keep running
/// @param {String} status_text Status displayed after the transition. Defaults to Your player left. The server is still running.
/// @returns {Bool} True after switching views
network_return_to_server_console = function(status_text = "Your player left. The server is still running.")
{
	escape_exit_hold_reset();
	host_session_menu_open = false;
	official_admin_controls_open = false;
	official_admin_focus = "";
	host_claim_pending = false;

	/* Read the authoritative server so the departing local player can relinquish its host claim */
	var server = scr_get_server();

	/* Clear host-slot ownership when the server helper is available, while leaving server listeners running */
	if (is_struct(server)
	&& variable_struct_exists(server, "clear_host_player_slot"))
	{
		server.clear_host_player_slot();
	}

	/* Read the local client transport to disconnect only the host player */
	var client = scr_get_client();

	/* Disconnect the local player when its client exposes cleanup */
	if (is_struct(client)
	&& variable_struct_exists(client, "disconnect"))
	{
		client.disconnect(status_text);
	}

	/* Clear the local-host marker after the local socket has been disconnected */
	if (is_struct(client)
	&& variable_struct_exists(client, "local_host_mode"))
	{
		client.local_host_mode = false;
	}

	host_play_active = false;
	is_client = false;
	is_singleplayer = false;
	network_mode_screen = false;
	client_join_screen = false;
	client_join_error = "";
	client_join_status = "";
	server_mode_status = string(status_text);
	server_mode_focus = "";
	keyboard_string = "";

	/* Refresh the console capacity field from the still-running server */
	if (is_struct(server)
	&& variable_struct_exists(server, "max_players"))
	{
		server_max_players_text = string(server.max_players);
	}
	show_logs = true;
	network_camera_reset_follow();
	network_update_window_caption("SERVER");
	debug_log(status_text);
	return true;
}

/// @description Request manual hosted-server shutdown with drawing archiving and return to mode selection
network_shutdown_hosted_server = function()
{
	host_session_menu_open = false;

	/* Read the authoritative server selected for an explicit manual shutdown */
	var server = scr_get_server();

	/* Use available server cleanup with a manual-shutdown reason and drawing archive enabled */
	if (is_struct(server)
	&& variable_struct_exists(server, "shutdown"))
	{
		server.shutdown("manual_shutdown", true);
	}
	network_open_mode_screen("Server shut down. Choose a network mode.");
}

/// @description Stop networking and create one local player with slot 0 and drawing author 1
/// @returns {Bool} Whether the local player was created
network_start_singleplayer_mode = function()
{
	escape_exit_hold_reset();

	client_username = chat_filter_username_input(client_username);

	/* Offline play substitutes Player for an incomplete profile because no remote identity is being assigned */
	if (client_username_validation_message(client_username) != "")
	{
		client_username = "Player";
	}

	/* Persist a usable profile before entering the offline session */
	else
	{
		client_save_username();
	}

	/* Read the authoritative server to stop any owned online session before offline play */
	var server = scr_get_server();

	/* Shut down an available hosted server before assigning offline player state */
	if (is_struct(server)
	&& variable_struct_exists(server, "shutdown"))
	{
		server.shutdown();
	}
	scr_server_logs_stop("Switched to singleplayer mode.");
	is_hosting_server = false;
	host_play_active = false;
	host_claim_pending = false;
	host_session_menu_open = false;

	/* Read the client state that will become the offline local session */
	var client = scr_get_client();

	/* Clean up online client and discovery resources before configuring the offline session */
	if (is_struct(client))
	{
		/* Disconnect without server notifications during the offline transition */
		if (variable_struct_exists(client, "disconnect"))
		{
			client.disconnect("Switched to singleplayer.", false);
		}

		/* Remove the local-host marker so offline cleanup has no hosted-server relationship */
		if (variable_struct_exists(client, "local_host_mode"))
		{
			client.local_host_mode = false;
		}

		/* Stop discovery polling because offline play has no remote server selection */
		if (variable_struct_exists(client, "stop_discovery"))
		{
			client.stop_discovery();
		}
	}

	is_client = true;
	is_singleplayer = true;
	network_mode_screen = false;
	network_update_window_caption("SINGLEPLAYER");
	show_logs = false;
	client_join_screen = false;
	client_join_error = "";
	client_join_status = "";
	client_dns_pending = false;
	client_dns_request_id = noone;
	client_join_focus = "";
	keyboard_string = "";
	player_controller_clear_players();
	scr_get_collision_objects().reset_client();
	network_camera_reset_follow();

	client_username = chat_filter_username_input(client_username);

	/* Represent offline play with slot zero, no socket and no pending handshake or reset countdown
	Set the local activity time in current_time milliseconds while keeping automatic drawing reset disabled */
	if (is_struct(client))
	{
		client.singleplayer_mode = true;
		client.socket = noone;
		client.ID = 0;
		client.requested_username = client_username;
		client.assigned_username = client_username;
		client.join_request_sent = false;
		client.connect_pending = false;
		client.connect_deadline = 0;
		client.connect_failed_message = "";
		client.needs_server_list = false;
		client.connect_status = "Singleplayer playtest active.";
		client.connect_address = "Singleplayer";
		client.last_server_heard = current_time;
		client.server_reset_status_known = true;
		client.server_reset_enabled = false;
		client.server_reset_interval_minutes = 0;
		client.server_reset_deadline_local = 0;
	}

	/* Use the shared drawing state to attribute offline actions to player slot zero and undo author one */
	var drawing_identity = scr_get_drawing();

	/* Assign offline drawing identity only when the attribution helper exists */
	if (is_struct(drawing_identity)
	&& variable_struct_exists(drawing_identity, "set_local_identity"))
	{
		drawing_identity.set_local_identity(0, client_username, 1);
	}

	/* Reset the shared offline chat history and presence, assign the profile name and add the local join message */
	var chat = scr_get_chat();
	chat.assigned_username = client_username;
	chat.clear_messages();
	chat.clear_typing_states(false);
	chat.clear_afk_states();
	chat.add_message(CHAT_TYPE_SYSTEM, noone, "", client_username + " joined the game.");

	/* Use collision-aware world bounds to choose a centered room-pixel spawn
	p is the created zero-slot local player using the selected character key */
	var spawn_bounds = player_world_bounds();
	var spawn_x = (spawn_bounds.left + spawn_bounds.right) * 0.5;
	var spawn_y = (spawn_bounds.top + spawn_bounds.bottom) * 0.5;
	var p = player_controller_make_player(0, spawn_x, spawn_y, client_username, scr_get_player_characters().load_selected_key());

	/* Report failure when the local player factory could not create the offline player */
	if (p == noone)
	{
		debug_error("Singleplayer failed to create local player.");
		return false;
	}

	debug_log("Singleplayer playtest active.");
	return true;
}

/// @description Close owned client and server sessions, save pending zoom preferences and restore profile-sensitive mode selection
/// @param {String} status_text Mode-menu feedback. Defaults to Host a server or join as a client.
network_open_mode_screen = function(status_text = "Host a server or join as a client.")
{
	escape_exit_hold_reset();
	official_admin_controls_open = false;
	official_admin_logs_open = false;
	official_admin_hover_button = "";
	official_admin_focus = "";
	official_admin_restart_confirm_until = 0;
	official_admin_reset_confirm_until = 0;
	network_camera_cancel_zoom_input();

	/* Save pending zoom preferences before clearing session state for the mode menu */
	if (network_camera_zoom_settings_dirty)
	{
		network_camera_save_zoom_settings();
	}

	/* Read the client transport before returning to the initial network-mode menu */
	var client = scr_get_client();

	/* Clean up available outgoing-client and discovery state before presenting mode choices */
	if (is_struct(client))
	{
		/* Disconnect the current local or remote player when cleanup is available */
		if (variable_struct_exists(client, "disconnect"))
		{
			client.disconnect("Back to mode selection.");
		}

		/* Clear the loopback marker for later sessions */
		if (variable_struct_exists(client, "local_host_mode"))
		{
			client.local_host_mode = false;
		}

		/* Stop active discovery polling when returning to the mode menu */
		if (variable_struct_exists(client, "stop_discovery"))
		{
			client.stop_discovery();
		}
	}

	/* Read the authoritative server whose owned session also ends at the mode screen */
	var server = scr_get_server();

	/* Shut down local hosting when its lifecycle helper exists */
	if (is_struct(server)
	&& variable_struct_exists(server, "shutdown"))
	{
		server.shutdown();
	}
	scr_server_logs_stop("Returned to network mode selection.");

	is_hosting_server = false;
	host_play_active = false;
	host_claim_pending = false;
	host_session_menu_open = false;
	network_mode_page = "main";
	network_mode_screen = true;
	information_screen_open = false;
	is_client = true;
	is_singleplayer = false;
	network_update_window_caption();
	network_mode_status = string(status_text);
	client_join_screen = false;
	client_join_error = "";
	client_join_status = "";
	client_dns_pending = false;
	client_dns_request_id = noone;
	client_join_focus = "";

	/* Focus username entry only when the current profile is incomplete
	Shared keyboard text mirrors that field while ready profiles begin without text focus */
	network_mode_focus = client_username_is_ready() ? "" : "username";
	network_mode_gamepad_focus = "host";
	keyboard_string = network_mode_focus == "username" ? client_username : "";
	show_logs = false;
	player_controller_clear_players();
	scr_get_collision_objects().reset_client();
	network_camera_reset_follow();
}
#endregion /* Network Mode Transitions END */

#region /* Initial Profile and Network Mode */
client_username = client_load_saved_username();

/* An explicit launch username overrides saved profile text and suppresses writing that temporary name back to preferences */
if (network_startup_username != "")
{
	client_username = chat_filter_username_input(network_startup_username);
	client_username_persistence_suppressed = true;
}

/* Incomplete loaded profiles begin with username focus, while valid names begin with no text field selected */
network_mode_focus = client_username_is_ready() ? "" : "username";

/* Copy the loaded profile into shared keyboard text only when username entry is focused */
if (network_mode_focus == "username")
{
	keyboard_string = client_username;
}

/* Refresh browser diagnostics only on the browser runtime */
if (html5_performance.is_html5)
{
	html5_performance.refresh_diagnostics();
}

/* An explicit direct address has startup priority and begins its client join */
if (network_startup_connect_address != "")
{
	network_start_direct_client_mode(network_startup_connect_address);
}

/* The server startup mode opens local listeners and their console */
else if (network_startup_mode == "server")
{
	network_start_server_mode();
}

/* Host-and-play startup opens a local server and joins it through loopback */
else if (network_startup_mode == "host_play")
{
	network_start_host_play_mode();
}

/* Client startup opens server selection after profile validation */
else if (network_startup_mode == "client")
{
	network_start_client_mode();
}

/* Singleplayer startup creates an offline local player */
else if (network_startup_mode == "singleplayer")
{
	network_start_singleplayer_mode();
}

/* Without an explicit recognized startup choice, present the network-mode menu */
else
{
	network_open_mode_screen();
}

/* Log one-based launch arguments while redacting explicit username values */
for (var i = 1; i <= parameter_count(); i++)
{
	/* Keep the original argument for logging and a trimmed lowercase copy for redaction matching */
	var debug_param = string(parameter_string(i));
	var debug_param_lower = string_lower(string_trim(debug_param));

	/* Redact a separate username option and skip logging its following value */
	if (debug_param_lower == "-username" && i < parameter_count())
	{
		debug_log("-username <redacted>");
		i++;
	}

	/* Redact the inline username value without changing other argument logging */
	else if (string_pos("-username=", debug_param_lower) == 1)
	{
		debug_log("-username=<redacted>");
	}

	/* Log other launch arguments in their supplied spelling */
	else
	{
		debug_log(debug_param);
	}
}

debug_log("Build version: " + game_version_label);
#endregion /* Initial Profile and Network Mode END */
