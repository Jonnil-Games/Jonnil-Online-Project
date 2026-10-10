#macro Server scr_get_server()

/// @description Format a non-negative reset duration as hours, minutes, and seconds
/// @param {Real} raw_seconds Duration in seconds, rounded upward
/// @returns {String} Duration label with zero-valued components omitted
function server_reset_duration_text(raw_seconds)
{
	/* Normalize the requested duration to nonnegative whole seconds. hours/minutes/
	seconds divide it into display components, and text starts empty so only nonzero
	parts are appended */
	var total_seconds = max(0, ceil(real(raw_seconds)));
	var hours = total_seconds div 3600;
	var minutes = (total_seconds mod 3600) div 60;
	var seconds = total_seconds mod 60;
	var text = "";

	/* Append hours only when present, keeping short countdown announcements concise */
	if (hours > 0)
	{
		text = string(hours) + "h";
	}

	/* Append nonzero minutes with a separator only after another component exists.
	Zero minutes are omitted rather than adding unnecessary text */
	if (minutes > 0)
	{
		text += (text == "" ? "" : " ") + string(minutes) + "m";
	}

	/* Append seconds when nonzero, or zero seconds when all components were empty.
	The conditional separator avoids leading spaces while guaranteeing a visible duration */
	if (seconds > 0 || text == "")
	{
		text += (text == "" ? "" : " ") + string(seconds) + "s";
	}

	return text;
}

/// @description Format a non-negative reset countdown as hours:minutes:seconds
/// @param {Real} raw_seconds Duration in seconds, rounded upward
/// @returns {String} Clock label with two-digit minutes and seconds
function server_reset_clock_text(raw_seconds)
{
	/* Normalize seconds before deriving hours, remaining minutes and remaining
	seconds. Unlike the duration prose, clock formatting keeps every component and pads
	minutes/seconds to two digits */
	var total_seconds = max(0, ceil(real(raw_seconds)));
	var hours = total_seconds div 3600;
	var minutes = (total_seconds mod 3600) div 60;
	var seconds = total_seconds mod 60;
	return string(hours)
		+ ":" + scr_debug_export_pad_number(minutes, 2)
		+ ":" + scr_debug_export_pad_number(seconds, 2);
}

/// @description Create authoritative server listeners, player-slot state, and lifecycle services
function scr_server() constructor
{

	#region /* Server State */
	/* server and websocket_server hold the TCP and WebSocket listener handles,
	initially noone. Startup creates them and shutdown destroys/restores them.
	These handles differ from the enclosing server struct and accepted player sockets */
	server = noone;
	websocket_server = noone;

	/* msg is hosting feedback, initially empty until startup records an outcome.
	net borrows shared transport configuration and packet helpers */
	msg = "";
	net = scr_get_network();

	/* The server-owned UDP discovery socket and writer start unallocated.
	Startup creates them, shutdown releases them, and discovery_status begins OFF
	before those resources can advertise hosting */
	discovery_socket = noone;
	discovery_buffer = noone;
	discovery_status = "LAN discovery: OFF";

	/* The next current_time millisecond announcement deadline starts zero for an
	immediate first broadcast. chat_buffer/position_buffer also start unallocated,
	are created lazily by their getters and are deleted by shutdown */
	next_discovery_broadcast = 0;
	chat_buffer = noone;
	position_buffer = noone;

	/* Zero on the current_time clock permits the first movement-broadcast attempt.
	The 67 ms interval retains the documented target of roughly 15 batched position
	updates per second, keeping relay traffic below the per-Step movement rate.
	Eligible Steps advance the deadline even without dirty positions, so this is an
	attempt interval rather than a guaranteed packet rate. Remote visuals smooth
	the received positions while negotiated client movement stays responsive locally */
	next_position_broadcast = 0;
	position_broadcast_interval_ms = 67;

	/* Tick diagnostics start without samples. last/average/recent_peak measure
	update work in milliseconds, sample_count begins zero, and peak_window_started
	is an inactive current_time timestamp until record_movement_tick seeds it */
	movement_tick_last_ms = 0;
	movement_tick_average_ms = 0;
	movement_tick_recent_peak_ms = 0;
	movement_tick_sample_count = 0;
	movement_tick_peak_window_started = 0;

	/* The previous-tick and rate-window timestamps start inactive on current_time.
	Window count and rate Hz start zero before measurement. max_gap is milliseconds,
	and gap_window_started marks the five-second gap window once sampling begins */
	movement_tick_previous_at = 0;
	movement_tick_rate_window_started = 0;
	movement_tick_rate_window_count = 0;
	movement_tick_rate_hz = 0;
	movement_tick_max_gap_ms = 0;
	movement_tick_gap_window_started = 0;

	/* Probe replies are limited to one per slot per 500 milliseconds.
	latency_reply_next_at is indexed by zero-based logical player slot, with zero
	meaning no initial cooldown. A reply attempt advances it even if sending fails */
	latency_reply_min_interval_ms = 500;
	latency_reply_next_at = array_create(net.max_clients, 0);

	/* Collision broadcasts start immediately eligible on current_time milliseconds.
	The 67 ms period gives changed ball snapshots the same approximate attempt
	cadence as position batches. Ball physics still advances every server update,
	and clients interpolate its visuals between snapshots. The original reason for
	choosing this exact collision period was not recorded in the development notes */
	next_collision_broadcast = 0;
	collision_broadcast_interval_ms = 67;

	/* Typing indicators expire after ten seconds without renewal. Gameplay idle
	shows AFK after two minutes and kicks after 15 minutes, using current_time
	millisecond activity timestamps rather than heartbeat liveness */
	typing_timeout_ms = 10000;
	afk_indicator_delay_ms = 120000;
	afk_kick_delay_ms = 900000;

	/* The sandbox INI stores reset policy under lifecycle and capacity/wall policy
	under server. Constructor defaults below may be replaced by this saved configuration */
	lifecycle_settings_file = "server_settings.ini";
	lifecycle_settings_section = "lifecycle";
	server_settings_section = "server";

	/* Gameplay capacity starts at the network default, independently of socket
	storage length. Wall editing starts enabled. Saved server settings replace both
	when valid configuration exists */
	max_players = net.default_max_players;
	wall_drawing_enabled = true;

	/* Automatic drawing reset starts disabled with a three-hour default period.
	Saved lifecycle settings can enable it or replace its minutes. Bounds allow 15
	to 1,440 minutes, and UI adjustment uses 30-minute steps */
	automatic_reset_enabled = false;
	automatic_reset_interval_minutes = 180;
	automatic_reset_min_minutes = 15;
	automatic_reset_max_minutes = 1440;
	automatic_reset_step_minutes = 30;

	/* Zero means no active reset on the current_time millisecond clock.
	Warning thresholds are remaining seconds, and matching sent flags start false
	so each selected threshold is announced at most once per schedule */
	automatic_reset_deadline = 0;
	automatic_reset_warning_thresholds = [3600, 1800, 600, 300, 60, 30, 10];
	automatic_reset_warnings_sent = array_create(array_length(automatic_reset_warning_thresholds), false);

	/* Reset numbering starts zero before the first reset. shutdown_in_progress
	starts false and guards against recursive/repeated shutdown work */
	drawing_reset_sequence = 0;
	shutdown_in_progress = false;

	/* This sandbox INI/admin section is a fallback for server owner credentials.
	Environment values take precedence, and comments must not contain actual secrets */
	admin_credentials_file = "server_admin_credentials.ini";
	admin_credentials_section = "admin";

	/* Expected key/token and credential-source text start empty, with configured
	false. load_admin_credentials fills them only after complete valid configuration */
	admin_expected_key_id = "";
	admin_expected_token = "";
	admin_credentials_configured = false;
	admin_credentials_source = "";

	/* Auth failures begin with a one-second per-slot retry delay and double it up
	to 60 seconds. Failure counts decay after two minutes, all using current_time
	milliseconds rather than elapsed Steps */
	admin_auth_base_delay_ms = 1000;
	admin_auth_max_delay_ms = 60000;
	admin_auth_failure_decay_ms = 120000;

	/* Global failures start zero and the retry/last-failure timestamps start inactive.
	This shared cooldown applies across slots, while per-slot arrays below track each
	connection separate failure history */
	admin_auth_global_failures = 0;
	admin_auth_global_retry_at = 0;
	admin_auth_global_last_failure_at = 0;

	/* No server log transfer exists initially. next_start_at zero allows its first
	eligible start on current_time. The admin-log service replaces/clears transfer state */
	admin_log_transfer = undefined;
	admin_log_next_start_at = 0;

	/* No restart is queued initially. Pending time zero, empty reason, noone slot
	and request ID zero represent absent request metadata. in_progress starts false,
	and verification_error is empty until archive validation reports a failure */
	force_restart_pending = false;
	force_restart_pending_at = 0;
	force_restart_pending_reason = "";
	force_restart_pending_slot = noone;
	force_restart_pending_request_id = 0;
	force_restart_in_progress = false;

	/* Wait 750 milliseconds after accepting a restart request so its response can
	be sent before shutdown. The pending timestamp uses current_time */
	force_restart_delay_ms = 750;
	force_restart_archive_verification_error = "";

	/* Every per-client array below uses the same zero-based logical player slot.
	sockets contains actual accepted handles, with noone marking unused slots.
	close_in_progress starts false and guards recursive cleanup. Transports default
	to TCP for empty slots until an accepted connection supplies its route */
	sockets = array_create(net.max_clients, noone);
	client_close_in_progress = array_create(net.max_clients, false);
	slot_transports = array_create(net.max_clients, TRANSPORT_TCP);

	/* Unused slots have empty usernames, built-in player1 character keys, noone
	character manifests and drawing-author ID zero. Join acceptance fills each role,
	and slot cleanup restores these unused defaults */
	slot_usernames = array_create(net.max_clients, "");
	slot_character_keys = array_create(net.max_clients, "player1");
	slot_character_manifests = array_create(net.max_clients, noone);

	/* Pet arrays use the same logical player slots. Empty keys and noone manifests
	mean no pet. Selection cooldowns and shared upload windows start inactive */
	slot_pet_keys = array_create(net.max_clients, "");
	slot_pet_manifests = array_create(net.max_clients, noone);
	pet_change_next_at = array_create(net.max_clients, 0);
	asset_upload_window_started = array_create(net.max_clients, 0);
	asset_upload_window_bytes = array_create(net.max_clients, 0);

	/* One uncached approved pet can reserve encoded bytes in its owner's upload
	budget until acknowledgement releases the client chunks. Empty keys reserve none */
	asset_upload_reserved_keys = array_create(net.max_clients, "");
	asset_upload_reserved_bytes = array_create(net.max_clients, 0);

	/* Pet changes are spaced by 250 ms. Upload accounting uses five-second
	current_time windows shared by character and pet sheets */
	pet_change_min_interval_ms = 250;
	asset_upload_window_ms = 5000;
	slot_drawing_author_ids = array_create(net.max_clients, 0);

	/* Character key/manifest arrays start empty and align at the same cache index.
	character_send_jobs is an empty outgoing chunk queue, bounded to two packets per
	Step to avoid a large appearance-transfer burst during join synchronization */
	character_cache_keys = [];
	character_cache_manifests = [];
	character_send_jobs = [];
	character_send_packets_per_step = 2;

	/* Drawing authors use a server-assigned connection sequence, separate from
	reusable player slots and socket handles, so reconnecting cannot inherit an
	earlier connection's undo ownership. Zero means unassigned and local play uses
	author one. The online sequence begins at 1,000,001 as the established project
	base, although its exact historical choice is undocumented. Ownership checks
	depend on the assigned ID matching the sender's slot, not on this large base */
	next_drawing_author_id = 1000001;

	/* No slot initially needs a movement broadcast or has negotiated client movement
	authority. Accepted movement marks dirty and authority handshake sets ownership,
	while slot cleanup clears both flags */
	position_dirty = array_create(net.max_clients, false);
	client_movement_authority = array_create(net.max_clients, false);

	/* Typing/AFK flags start false. Typing deadlines and AFK last-activity timestamps
	start zero on current_time, filled by join/input/typing updates and reset on cleanup */
	typing_active = array_create(net.max_clients, false);
	typing_deadlines = array_create(net.max_clients, 0);
	afk_active = array_create(net.max_clients, false);
	afk_last_activity = array_create(net.max_clients, 0);

	/* Each slot starts with no scheduled ping, zero missed replies and sequence zero.
	last_heard zero means no liveness timestamp yet. Accepted traffic updates it,
	heartbeat sends advance scheduling/counts, and slot cleanup resets all four */
	heartbeat_next_ping = array_create(net.max_clients, 0);
	heartbeat_missed = array_create(net.max_clients, 0);
	heartbeat_sequence = array_create(net.max_clients, 0);
	heartbeat_last_heard = array_create(net.max_clients, 0);

	/* Every slot starts unauthenticated, with no authenticated socket or key ID.
	Failure counters, retry/last-failure clocks and last request IDs begin zero.
	Authentication binds access to the exact current socket/key, and slot/session
	cleanup removes the binding so reused slots cannot inherit owner access */
	admin_authenticated = array_create(net.max_clients, false);
	admin_authenticated_sockets = array_create(net.max_clients, noone);
	admin_authenticated_key_ids = array_create(net.max_clients, "");
	admin_auth_failures = array_create(net.max_clients, 0);
	admin_auth_retry_at = array_create(net.max_clients, 0);
	admin_auth_last_failure_at = array_create(net.max_clients, 0);
	admin_last_request_ids = array_create(net.max_clients, 0);

	/* Status-only sockets and their current_time deadlines begin as aligned empty
	lists. Pending WebSocket sockets, transports and deadlines form separate aligned
	lists until the first join/status packet identifies their role */
	status_sockets = [];
	status_socket_deadlines = [];
	pending_ws_sockets = [];
	pending_ws_transports = [];
	pending_ws_deadlines = [];

	/* No gameplay players are connected initially. host_player_slot begins noone
	until the local Host & Play connection claims a valid occupied player slot */
	connected_players = 0;
	host_player_slot = noone;
	#endregion /* Server State END */

	#region /* Socket and Slot Ownership */
	/// @description Read the valid TCP-listener running marker
	/// @returns {Bool} Whether the stored TCP listener is numeric and nonnegative
	is_running = function()
	{
		/* A numeric nonnegative TCP listener is this implementation running marker.
		This does not separately guarantee the WebSocket/discovery listeners are valid */
		return is_real(server) && server >= 0;
	}

	/// @description Match event/listener handles to authoritative listener, player or temporary ownership
	/// @param {Real} network_id Async id handle
	/// @param {Real} network_socket Async socket handle
	/// @param {Real} network_server Optional listener handle, defaulting to noone for handle-based fallback
	/// @returns {Bool} Whether this server owns the event
	owns_socket_event = function(network_id, network_socket, network_server = noone)
	{
		/* A valid async listener ID can directly establish server ownership when it
		matches TCP, WebSocket or discovery. Missing listener metadata uses handle matching */
		if (is_real(network_server) && network_server >= 0)
		{
			/* Accept events naming one of this server valid listeners. Check each stored
			handle before equality so absent/failed listener values cannot claim ownership */
			if ((is_real(server) && server >= 0 && network_server == server)
			|| (is_real(websocket_server) && websocket_server >= 0 && network_server == websocket_server)
			|| (is_real(discovery_socket) && discovery_socket >= 0 && network_server == discovery_socket))
			{
				return true;
			}
		}

		/* id_is_valid/socket_is_valid establish which async fields contain usable actual
		handles before matching listeners, occupied gameplay slots or temporary sockets */
		var id_is_valid = is_real(network_id) && network_id >= 0;
		var socket_is_valid = is_real(network_socket) && network_socket >= 0;

		/* Without either valid event handle and no earlier listener match, this server
		cannot own the event. Return false before searching socket collections */
		if (!id_is_valid && !socket_is_valid)
		{
			return false;
		}

		/* Match valid id/socket fields against the server listeners when explicit
		listener metadata was absent or unmatched. Each listener must itself be allocated */
		if ((is_real(server) && server >= 0
			&& ((id_is_valid && network_id == server) || (socket_is_valid && network_socket == server)))
		|| (is_real(websocket_server) && websocket_server >= 0
			&& ((id_is_valid && network_id == websocket_server) || (socket_is_valid && network_socket == websocket_server)))
		|| (is_real(discovery_socket) && discovery_socket >= 0
			&& ((id_is_valid && network_id == discovery_socket) || (socket_is_valid && network_socket == discovery_socket))))
		{
			return true;
		}

		/* Otherwise ownership requires an occupied gameplay socket, status-only socket
		or pending WebSocket handle in either valid event field. Logical player slot IDs
		are resolved from those handles instead of compared as socket identities */
		return (id_is_valid
			&& (find_slot_by_socket(network_id) != noone
				|| is_status_client_socket(network_id)
				|| is_pending_ws_socket(network_id)))
			|| (socket_is_valid
			&& (find_slot_by_socket(network_socket) != noone
				|| is_status_client_socket(network_socket)
				|| is_pending_ws_socket(network_socket)));
	}

	/// @description Validate an exact whole logical index against socket storage
	/// @param {Any} slot Proposed zero-based player slot
	/// @returns {Bool} Whether the numeric slot is in range
	slot_is_valid = function(slot)
	{
		/* Only numeric values can be logical array slots. Reject other values before
		rounding/index checks */
		if (!is_real(slot))
		{
			return false;
		}

		/* slot_index is the whole-number candidate, permitting comparison with the
		original input before using it as a zero-based socket-array index */
		var slot_index = floor(slot);

		/* A valid slot must be an exact whole number within socket storage bounds.
		Fractional, negative or out-of-capacity values cannot safely index per-client arrays */
		return (slot == slot_index
			&& slot_index >= 0
			&& slot_index < array_length(sockets));
	}

	/// @description Normalize a logical player slot without accepting fractional or out-of-range IDs
	/// @param {Any} raw_slot Logical player-slot value, validated against the sockets array
	/// @returns {Real} Valid sockets-array index, or noone
	slot_from_value = function(raw_slot)
	{
		/* An absent/noone slot has no assigned logical index. Return noone before
		numeric conversion or array access */
		if (is_undefined(raw_slot)
		|| raw_slot == noone)
		{
			return noone;
		}

		/* The numeric candidate starts unresolved and is filled by conversion in try.
		Conversion failure returns noone instead of interrupting packet handling */
		var numeric_slot = noone;
		try
		{
			numeric_slot = real(raw_slot);
		}
		catch (e)
		{
			return noone;
		}

		/* Compare this whole-number candidate with the converted value to reject
		fractional logical IDs before storage bounds are checked */
		var slot_index = floor(numeric_slot);

		/* Reject fractional, negative and beyond-capacity slot values. noone is the
		failure marker used by callers before they index per-slot state */
		if (numeric_slot != slot_index
		|| slot_index < 0
		|| slot_index >= array_length(sockets))
		{
			return noone;
		}

		return slot_index;
	}
	#endregion /* Socket and Slot Ownership END */

	#region /* Remote Administration */
	/// @description Clear one slot authentication, cooldowns, request history and owned log transfer
	/// @param {Any} raw_slot Logical player-slot candidate
	/// @returns {Bool} Whether the slot was valid and cleared
	clear_admin_slot = function(raw_slot)
	{
		/* Normalize the logical player slot before clearing its per-slot admin state.
		An invalid input cannot index authentication/cooldown arrays */
		var slot = slot_from_value(raw_slot);

		/* Reject invalid logical slots before altering admin arrays or transfer state */
		if (slot == noone)
		{
			return false;
		}

		admin_authenticated[slot] = false;

		/* Clear an active transfer only when it belongs to the slot being reset.
		Other administrators retain their own pending transfer */
		if (is_struct(admin_log_transfer) && admin_log_transfer.slot == slot)
		{
			admin_log_transfer = undefined;
		}
		admin_authenticated_sockets[slot] = noone;
		admin_authenticated_key_ids[slot] = "";
		admin_auth_failures[slot] = 0;
		admin_auth_retry_at[slot] = 0;
		admin_auth_last_failure_at[slot] = 0;
		admin_last_request_ids[slot] = 0;
		return true;
	}

	/// @description Clear every authentication binding, failure timer and active log transfer
	clear_all_admin_sessions = function()
	{
		admin_log_transfer = undefined;
		admin_authenticated = array_create(net.max_clients, false);
		admin_authenticated_sockets = array_create(net.max_clients, noone);
		admin_authenticated_key_ids = array_create(net.max_clients, "");
		admin_auth_failures = array_create(net.max_clients, 0);
		admin_auth_retry_at = array_create(net.max_clients, 0);
		admin_auth_last_failure_at = array_create(net.max_clients, 0);
		admin_last_request_ids = array_create(net.max_clients, 0);
		admin_auth_global_failures = 0;
		admin_auth_global_retry_at = 0;
		admin_auth_global_last_failure_at = 0;
	}

	/// @description Check a nonempty credential field against its permitted alphabet
	/// @param {Any} value Candidate text
	/// @param {String} allowed_characters Complete accepted character set
	/// @returns {Bool} Whether every character is permitted
	admin_string_uses_only = function(value, allowed_characters)
	{
		/* Convert the candidate credential to text before checking its permitted
		alphabet. Empty input is not a usable credential field */
		var text = string(value);

		/* Reject an empty field before its character loop, which would otherwise have
		no characters to reject */
		if (text == "")
		{
			return false;
		}

		/* Inspect each one-based credential character until all are accepted or a
		forbidden character ends validation */
		for (var character_index = 1; character_index <= string_length(text); character_index++)
		{
			/* A character outside the configured alphabet rejects the complete field.
			Do not accept only the valid prefix of a credential */
			if (string_pos(string_char_at(text, character_index), allowed_characters) <= 0)
			{
				return false;
			}
		}
		return true;
	}

	/// @description Prefer environment credentials. Use the sandbox INI only when neither environment value is supplied
	/// @returns {Bool} Whether a valid key/token pair was configured and protected in logs
	load_admin_credentials = function()
	{
		admin_expected_key_id = "";
		admin_expected_token = "";
		admin_credentials_configured = false;
		admin_credentials_source = "";

		/* Read trimmed environment key/token text. environment_credentials_present
		means either field is supplied, so partial environment config also blocks INI fallback */
		var environment_key_id = string_trim(string(environment_get_variable("JONNIL_ADMIN_KEY_ID")));
		var environment_token = string_trim(string(environment_get_variable("JONNIL_ADMIN_TOKEN")));
		var environment_credentials_present = environment_key_id != "" || environment_token != "";

		/* Any supplied environment field selects environment configuration.
		It must be complete rather than silently mixing one field with sandbox values */
		if (environment_credentials_present)
		{
			/* Both environment fields must be nonempty before assigning the expected pair.
			A partial pair stays disabled and uses the failure diagnostic alternative */
			if (environment_key_id != "" && environment_token != "")
			{
				admin_expected_key_id = environment_key_id;
				admin_expected_token = environment_token;
				admin_credentials_source = "environment";
			}

			/* Incomplete environment credentials are reported without trying the sandbox
			fallback, keeping deployment configuration precedence explicit */
			else
			{
				debug_error("Remote admin environment credentials are incomplete; sandbox fallback was not used.");
			}
		}

		/* Only with neither environment field and an existing sandbox INI, read the
		fallback pair. Missing configuration retains empty credential state */
		else if (file_exists(admin_credentials_file))
		{
			try
			{
				ini_open(admin_credentials_file);
				admin_expected_key_id = string_trim(ini_read_string(admin_credentials_section, "key_id", ""));
				admin_expected_token = string_trim(ini_read_string(admin_credentials_section, "token", ""));
				ini_close();

				/* Record the INI source only after both fallback values were supplied.
				An incomplete pair cannot claim to be configured */
				if (admin_expected_key_id != "" && admin_expected_token != "")
				{
					admin_credentials_source = "sandbox INI";
				}
			}
			catch(e)
			{
				try { ini_close(); } catch(close_error) { }
				admin_expected_key_id = "";
				admin_expected_token = "";
				admin_credentials_source = "";
				debug_error("Could not load remote admin credentials from the sandbox INI.");
			}
		}

		/* key_id_length/token_length count text characters before validation.
		Configured requires bounded nonempty key, a 32-to-512-character token and accepted
		alphabets for both, rejecting malformed or incomplete configuration */
		var key_id_length = string_length(admin_expected_key_id);
		var token_length = string_length(admin_expected_token);
		admin_credentials_configured = key_id_length >= 1
			&& key_id_length <= 128
			&& token_length >= 32
			&& token_length <= 512
			&& admin_string_uses_only(admin_expected_key_id, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
			&& admin_string_uses_only(admin_expected_token, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.=");

		/* Clear every credential field when the complete pair fails validation.
		Disable owner access rather than keeping partially accepted secret state */
		if (!admin_credentials_configured)
		{
			admin_expected_key_id = "";
			admin_expected_token = "";
			admin_credentials_source = "";
			debug_log("Remote admin access is disabled: no valid server credential is configured.");
			return false;
		}

		scr_server_logs_protect_secret(admin_expected_token);
		scr_server_logs_protect_secret(admin_expected_key_id);
		debug_success("Remote admin credentials loaded from " + admin_credentials_source + ".");
		return true;
	}

	/// @description Require an occupied WebSocket slot for administrator traffic
	/// @param {Any} raw_slot Logical player-slot candidate
	/// @returns {Bool} Whether the current occupied route is WebSocket
	admin_transport_allowed = function(raw_slot)
	{
		/* Validate the logical slot before checking its accepted socket/transport.
		An invalid slot makes the result false before any array access */
		var slot = slot_from_value(raw_slot);

		/* Admin traffic requires a valid occupied logical slot using WebSocket.
		This transport check identifies the route and does not itself authenticate a user */
		return slot != noone
			&& sockets[slot] != noone
			&& slot_transports[slot] == TRANSPORT_WS;
	}

	/// @description Require authentication to match the current WebSocket and configured key
	/// @param {Any} raw_slot Logical player-slot value, validated against the sockets array
	/// @returns {Bool} Whether credentials remain valid for this exact socket session
	admin_slot_is_authenticated = function(raw_slot)
	{
		/* Normalize the player slot before examining its exact authenticated session
		binding and current configured credential */
		var slot = slot_from_value(raw_slot);

		/* Authentication remains valid only for an occupied WebSocket slot with the
		stored authenticated flag, exact current socket and expected key. Credential
		configuration must still be valid, preventing reused slots inheriting owner access */
		return slot != noone
			&& admin_transport_allowed(slot)
			&& admin_authenticated[slot]
			&& admin_authenticated_sockets[slot] == sockets[slot]
			&& admin_authenticated_key_ids[slot] == admin_expected_key_id
			&& admin_credentials_configured;
	}

	/// @description Name a supported admin action for audit logs
	/// @param {Real} action ADMIN_ACTION value
	/// @returns {String} Action label or numeric unknown label
	admin_action_name = function(action)
	{
		/* Known admin actions get readable audit-log names. Unsupported actions fall
		through to a numeric unknown label rather than being named as a valid operation */
		switch(action)
		{
			case ADMIN_ACTION_AUTH: return "authenticate";
			case ADMIN_ACTION_STATUS: return "status";
			case ADMIN_ACTION_SET_RESET_ENABLED: return "set reset enabled";
			case ADMIN_ACTION_SET_RESET_INTERVAL: return "set reset interval";
			case ADMIN_ACTION_RESET_NOW: return "reset drawing now";
			case ADMIN_ACTION_FORCE_RESTART: return "force restart";
			case ADMIN_ACTION_SET_MAX_PLAYERS: return "set maximum players";
			case ADMIN_ACTION_SET_WALL_DRAWING: return "set wall drawing";
		}
		return "unknown action " + string(action);
	}

	/// @description Compare complete text lengths/characters without returning at the first mismatch
	/// @param {Any} supplied_value Candidate credential text
	/// @param {Any} expected_value Configured expected text
	/// @returns {Bool} Whether lengths and all characters match
	admin_secret_matches = function(supplied_value, expected_value)
	{
		/* supplied/expected normalize both candidate secrets to text. Their lengths
		seed mismatch if different, and compare_length takes the longer size so the loop
		examines every position without an early return on the first difference */
		var supplied = string(supplied_value);
		var expected = string(expected_value);
		var supplied_length = string_length(supplied);
		var expected_length = string_length(expected);
		var mismatch = supplied_length != expected_length;
		var compare_length = max(supplied_length, expected_length);

		/* Compare every one-based character through the longer string. A position
		beyond one string uses empty text, so unequal lengths still contribute mismatches */
		for (var character_index = 1; character_index <= compare_length; character_index++)
		{
			/* supplied_character/expected_character select an actual in-range character
			or empty text past that string end. This avoids invalid string access while keeping
			the full comparison loop */
			var supplied_character = character_index <= supplied_length
				? string_char_at(supplied, character_index)
				: "";
			var expected_character = character_index <= expected_length
				? string_char_at(expected, character_index)
				: "";

			/* Remember any differing character but continue scanning. Equal later
			characters cannot clear an earlier mismatch */
			if (supplied_character != expected_character)
			{
				mismatch = true;
			}
		}

		/* Return true only when lengths and every examined character matched.
		The loop completion does not grant access if any prior difference was recorded */
		return !mismatch;
	}

	/// @description Send correlated owner-action feedback to an occupied player socket
	/// @param {Any} raw_target_slot Logical recipient candidate
	/// @param {Real} request_id Echoed command correlation ID
	/// @param {Real} action ADMIN_ACTION value
	/// @param {Real} result_code ADMIN_RESULT outcome
	/// @param {String} message Visible feedback
	/// @returns {Real} Send result or -1 for an invalid/unoccupied target
	send_admin_result = function(raw_target_slot, request_id, action, result_code, message)
	{
		/* Normalize the reply recipient logical slot before looking up its actual
		socket and aligned transport */
		var target_slot = slot_from_value(raw_target_slot);

		/* An invalid or unoccupied target cannot receive a request outcome.
		Return -1 without constructing/sending a result packet */
		if (target_slot == noone || sockets[target_slot] == noone)
		{
			return -1;
		}

		net.start(N_ADMIN_RESULT, noone);
		net.write(buffer_u8, ADMIN_PROTOCOL_VERSION);
		net.write(buffer_u32, request_id);
		net.write(buffer_u8, action);
		net.write(buffer_u8, result_code);
		net.write(buffer_string, string(message));
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Send control/status fields only to a currently authenticated socket binding
	/// @param {Any} raw_target_slot Logical recipient candidate
	/// @param {Real} request_id Echoed status correlation ID
	/// @returns {Real} Send result or -1 for an invalid/unauthenticated target
	send_admin_status = function(raw_target_slot, request_id)
	{
		/* Normalize the status recipient before checking its authenticated connection.
		Admin status may expose server controls and is not sent to unauthenticated slots */
		var target_slot = slot_from_value(raw_target_slot);

		/* Reject invalid or no-longer-authenticated status recipients before encoding
		server control data */
		if (target_slot == noone || !admin_slot_is_authenticated(target_slot))
		{
			return -1;
		}

		net.start(N_ADMIN_STATUS, noone);
		net.write(buffer_u8, ADMIN_PROTOCOL_VERSION);
		net.write(buffer_u32, request_id);
		net.write(buffer_u8, 1);

		/* Encode automatic reset as one/zero, then send configured minutes, remaining
		seconds and gameplay counts. Restart is true for either queued or active restart,
		and the countdown text gives matching human-readable feedback */
		net.write(buffer_u8, automatic_reset_enabled ? 1 : 0);
		net.write(buffer_u16, automatic_reset_interval_minutes);
		net.write(buffer_u32, reset_remaining_seconds());
		net.write(buffer_u16, connected_players);
		net.write(buffer_u16, max_players);
		net.write(buffer_u8, (force_restart_pending || force_restart_in_progress) ? 1 : 0);
		net.write(buffer_string, reset_countdown_text());
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Decay old auth failures and check slot/global retry deadlines
	/// @param {Any} raw_slot Logical sender candidate
	/// @returns {Bool} Whether either cooldown is active, also true for invalid slots
	admin_auth_is_rate_limited = function(raw_slot)
	{
		/* Normalize the slot before inspecting its retry history. Invalid input is
		considered blocked so it cannot bypass the authentication delay */
		var slot = slot_from_value(raw_slot);

		/* Return rate-limited for invalid slots rather than indexing retry state or
		allowing an unassigned connection to attempt authentication */
		if (slot == noone)
		{
			return true;
		}

		/* A recorded global failure old enough for the decay interval clears shared
		failure/cooldown state. No recorded failure leaves its zero state unchanged */
		if (admin_auth_global_last_failure_at > 0
		&& current_time - admin_auth_global_last_failure_at >= admin_auth_failure_decay_ms)
		{
			admin_auth_global_failures = 0;
			admin_auth_global_retry_at = 0;
			admin_auth_global_last_failure_at = 0;
		}

		/* Decay this slot only after a recorded failure reaches the same quiet period.
		Other slots retain their own failure history */
		if (admin_auth_last_failure_at[slot] > 0
		&& current_time - admin_auth_last_failure_at[slot] >= admin_auth_failure_decay_ms)
		{
			admin_auth_failures[slot] = 0;
			admin_auth_retry_at[slot] = 0;
			admin_auth_last_failure_at[slot] = 0;
		}

		/* Either an active per-slot deadline or global deadline blocks a new failed-
		credential attempt. Both must have expired for this check to return false */
		return current_time < admin_auth_retry_at[slot]
			|| current_time < admin_auth_global_retry_at;
	}

	/// @description Increase slot/global failure history and schedule bounded exponential retry delay
	/// @param {Any} raw_slot Logical sender candidate
	record_admin_auth_failure = function(raw_slot)
	{
		/* Normalize the failed-auth sender before updating its slot and shared counters */
		var slot = slot_from_value(raw_slot);

		/* Invalid slots cannot receive failure-history updates. Return before indexing
		arrays or starting cooldowns */
		if (slot == noone)
		{
			return;
		}

		admin_auth_failures[slot]++;
		admin_auth_last_failure_at[slot] = current_time;
		admin_auth_global_failures++;
		admin_auth_global_last_failure_at = current_time;

		/* failure_count includes this newly recorded failure. delay begins at the
		one-second base and grows by doubling for each permitted escalation step */
		var failure_count = admin_auth_failures[slot];
		var delay = admin_auth_base_delay_ms;

		/* Start at the first escalation beyond the base failure. Stop at the bounded
		failure count and cap each doubled millisecond delay at the configured maximum */
		for (var delay_step = 1; delay_step < min(failure_count, 7); delay_step++)
		{
			delay = min(admin_auth_max_delay_ms, delay * 2);
		}
		admin_auth_retry_at[slot] = current_time + delay;
		admin_auth_global_retry_at = current_time + admin_auth_base_delay_ms;
		debug_error("Remote admin authentication failed for " + scr_network_debug_server_slot_label(slot) + "; retry delayed.");
	}

	/// @description Validate protocol and credentials, then bind admin access to the current sender socket
	/// @param {Any} raw_slot Logical player-slot value, validated against the sockets array
	/// @param {Real} protocol_version Client protocol version
	/// @param {Real} request_id Nonzero request ID echoed in responses
	/// @param {String} supplied_key_id Supplied owner key ID
	/// @param {String} supplied_token Supplied owner token
	/// @returns {Bool} Whether this session was authenticated
	handle_admin_auth = function(raw_slot, protocol_version, request_id, supplied_key_id, supplied_token)
	{
		/* Normalize the actual sender logical slot before accepting a new auth request.
		Success later binds access to this exact accepted socket */
		var slot = slot_from_value(raw_slot);

		/* Authentication needs an occupied validated player slot. Invalid or empty
		slots return false before their session arrays are accessed */
		if (slot == noone || sockets[slot] == noone)
		{
			return false;
		}

		admin_authenticated[slot] = false;
		admin_authenticated_sockets[slot] = noone;
		admin_authenticated_key_ids[slot] = "";
		admin_last_request_ids[slot] = 0;

		/* Require the supported admin layout and positive correlation ID.
		Reject incompatible/untrackable requests before comparing credentials */
		if (protocol_version != ADMIN_PROTOCOL_VERSION || request_id <= 0)
		{
			send_admin_result(slot, request_id, ADMIN_ACTION_AUTH, ADMIN_RESULT_INVALID, "Unsupported remote admin request.");
			return false;
		}

		/* Only the WebSocket route can authenticate owner controls. Other transports
		receive denial rather than validating secrets on the native gameplay route */
		if (!admin_transport_allowed(slot))
		{
			send_admin_result(slot, request_id, ADMIN_ACTION_AUTH, ADMIN_RESULT_DENIED, "Remote admin access requires the secure WebSocket route.");
			debug_error("Rejected remote admin authentication from a non-WebSocket client slot.");
			return false;
		}

		/* Without valid expected server credentials, owner access is unavailable.
		Report that configuration state instead of accepting any supplied pair */
		if (!admin_credentials_configured)
		{
			send_admin_result(slot, request_id, ADMIN_ACTION_AUTH, ADMIN_RESULT_UNAVAILABLE, "Remote admin access is not configured on this server.");
			return false;
		}

		/* Measure supplied key/token character lengths. key_matches needs bounded exact
		key equality, and token_matches needs its bounded length plus full secret comparison.
		Neither Boolean alone is enough to authenticate */
		var supplied_key_length = string_length(string(supplied_key_id));
		var supplied_token_length = string_length(string(supplied_token));
		var key_matches = supplied_key_length >= 1
			&& supplied_key_length <= 128
			&& string(supplied_key_id) == admin_expected_key_id;
		var token_matches = supplied_token_length >= 32
			&& supplied_token_length <= 512
			&& admin_secret_matches(supplied_token, admin_expected_token);

		/* Either mismatched field fails authentication. Existing cooldowns may reject
		it without another failure increment, otherwise record a new delayed attempt */
		if (!key_matches || !token_matches)
		{
			/* A wrong pair during slot/global cooldown gets the rate-limited outcome.
			Do not escalate counters for every repeated packet during the active wait */
			if (admin_auth_is_rate_limited(slot))
			{
				send_admin_result(slot, request_id, ADMIN_ACTION_AUTH, ADMIN_RESULT_RATE_LIMITED, "Authentication is temporarily rate limited. Try again later.");
				return false;
			}
			record_admin_auth_failure(slot);
			send_admin_result(slot, request_id, ADMIN_ACTION_AUTH, ADMIN_RESULT_DENIED, "Remote admin authentication failed.");
			return false;
		}

		admin_authenticated[slot] = true;
		admin_authenticated_sockets[slot] = sockets[slot];
		admin_authenticated_key_ids[slot] = admin_expected_key_id;
		admin_auth_failures[slot] = 0;
		admin_auth_retry_at[slot] = 0;
		admin_auth_last_failure_at[slot] = 0;
		admin_auth_global_failures = 0;
		admin_auth_global_retry_at = 0;
		admin_auth_global_last_failure_at = 0;
		debug_success("Remote admin authenticated for " + scr_network_debug_server_slot_label(slot) + ".");
		send_admin_result(slot, request_id, ADMIN_ACTION_AUTH, ADMIN_RESULT_OK, "Remote server controls unlocked.");
		send_admin_status(slot, request_id);
		return true;
	}

	/// @description Validate eligible owner status requests before replying
	/// @param {Any} raw_slot Logical sender candidate
	/// @param {Real} protocol_version Received admin protocol version
	/// @param {Real} request_id Positive echoed correlation ID
	/// @returns {Bool} Whether compatible authenticated status was sent
	handle_admin_status_request = function(raw_slot, protocol_version, request_id)
	{
		/* Normalize the status requester and require its current exact socket/key
		binding before exposing authenticated server metadata */
		var slot = slot_from_value(raw_slot);

		/* Invalid or unauthenticated requests return false. A valid denied slot can
		receive feedback, while an invalid slot has no safe reply target */
		if (slot == noone || !admin_slot_is_authenticated(slot))
		{
			/* Send authentication-required feedback only to a validated logical slot.
			Invalid sender input cannot select a socket array entry */
			if (slot != noone)
			{
				send_admin_result(slot, request_id, ADMIN_ACTION_STATUS, ADMIN_RESULT_DENIED, "Remote admin authentication is required.");
			}
			return false;
		}

		/* Reject unsupported protocol or nonpositive request IDs before sending status,
		keeping response layouts and correlation compatible */
		if (protocol_version != ADMIN_PROTOCOL_VERSION || request_id <= 0)
		{
			send_admin_result(slot, request_id, ADMIN_ACTION_STATUS, ADMIN_RESULT_INVALID, "Invalid status request.");
			return false;
		}

		/* Report success only for a nonnegative complete status send result.
		The authentication guard does not guarantee transport delivery */
		return send_admin_status(slot, request_id) >= 0;
	}
	#endregion /* Remote Administration END */

	#region /* Persistence and Server Lifecycle */
	/// @description Record the server authoritative chat export line when supported
	/// @param {Real} chat_type CHAT_TYPE value
	/// @param {Real} sender_id Logical sender or noone for system messages
	/// @param {String} sender_name Approved display name
	/// @param {String} content Approved visible text
	record_chat_log = function(chat_type, sender_id, sender_name, content)
	{
		/* Borrow the shared chat export service to record the authoritative line before
		network delivery, so a local host client need not export the same message twice */
		var chat = scr_get_chat();

		/* Record only when export capability exists. Missing chat/export support
		skips recording without blocking the server packet operation */
		if (is_struct(chat)
		&& variable_struct_exists(chat, "record_export_message"))
		{
			chat.record_export_message(chat_type, sender_id, sender_name, content);
		}
	}

	/// @description Restore bounded sandbox capacity, wall policy and reset configuration
	/// @returns {Bool} Whether an existing INI was read without exception
	load_lifecycle_settings = function()
	{
		max_players = net.default_max_players;
		wall_drawing_enabled = true;
		try
		{
			/* No saved INI means constructor/current reset defaults remain in use.
			Return false without manufacturing a new configuration during loading */
			if (!file_exists(lifecycle_settings_file))
			{
				return false;
			}

			ini_open(lifecycle_settings_file);

			/* Missing Boolean INI keys use the current one/zero policy as fallback.
			Read nonzero as enabled, and clamp saved player/minute values to their valid ranges */
			wall_drawing_enabled = ini_read_real(server_settings_section, "wall_drawing_enabled", wall_drawing_enabled ? 1 : 0) != 0;
			max_players = clamp(
				floor(ini_read_real(server_settings_section, "max_players", max_players)),
				net.min_player_limit,
				net.max_player_limit
			);
			automatic_reset_enabled = ini_read_real(lifecycle_settings_section, "automatic_reset_enabled", automatic_reset_enabled ? 1 : 0) != 0;
			automatic_reset_interval_minutes = clamp(
				floor(ini_read_real(lifecycle_settings_section, "automatic_reset_interval_minutes", automatic_reset_interval_minutes)),
				automatic_reset_min_minutes,
				automatic_reset_max_minutes
			);
			ini_close();
			return true;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) { }
			debug_error("Could not load server lifecycle settings: " + string(e.message));
			return false;
		}
	}

	/// @description Persist current capacity, wall policy and reset configuration to the sandbox INI
	/// @returns {Bool} Whether the write completed without exception
	save_lifecycle_settings = function()
	{
		try
		{
			ini_open(lifecycle_settings_file);
			ini_write_real(server_settings_section, "max_players", max_players);

			/* Persist enabled policy flags as numeric one and disabled as zero, alongside
			player capacity and reset minutes. Runtime deadlines are not saved */
			ini_write_real(server_settings_section, "wall_drawing_enabled", wall_drawing_enabled ? 1 : 0);
			ini_write_real(lifecycle_settings_section, "automatic_reset_enabled", automatic_reset_enabled ? 1 : 0);
			ini_write_real(lifecycle_settings_section, "automatic_reset_interval_minutes", automatic_reset_interval_minutes);
			ini_close();
			return true;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) { }
			debug_error("Could not save server lifecycle settings: " + string(e.message));
			return false;
		}
	}

	/// @description Mark each countdown threshold unsent for the next reset schedule
	reset_warning_state = function()
	{
		automatic_reset_warnings_sent = array_create(array_length(automatic_reset_warning_thresholds), false);
	}

	/// @description Reset warnings and create a current_time countdown only for enabled running hosting
	/// @returns {Bool} Whether a reset deadline was started
	start_reset_schedule = function()
	{
		reset_warning_state();

		/* Disabled resets or a stopped server have no active schedule. Clear the
		millisecond deadline after resetting warning flags instead of starting a countdown */
		if (!automatic_reset_enabled || !is_running())
		{
			automatic_reset_deadline = 0;
			return false;
		}

		automatic_reset_deadline = current_time + automatic_reset_interval_minutes * 60000;
		return true;
	}

	/// @description Read the nonnegative reset countdown in whole seconds
	/// @returns {Real} Rounded-up remaining seconds or zero for inactive reset
	reset_remaining_seconds = function()
	{
		/* A disabled policy or inactive deadline has no remaining countdown.
		Return zero rather than deriving time from an unset clock */
		if (!automatic_reset_enabled || automatic_reset_deadline <= 0)
		{
			return 0;
		}

		return max(0, ceil((automatic_reset_deadline - current_time) / 1000));
	}

	/// @description Format unlimited or active reset status for UI and admin packets
	/// @returns {String} Reset countdown label
	reset_countdown_text = function()
	{
		/* Disabled resets show unlimited drawing time. Enabled policy formats the
		remaining deadline as a clock */
		if (!automatic_reset_enabled)
		{
			return "Drawing reset timer: Unlimited";
		}

		return "Drawing reset in " + server_reset_clock_text(reset_remaining_seconds());
	}

	/// @description Send reset flag, configured minutes and remaining seconds to one occupied slot
	/// @param {Any} raw_target_slot Logical recipient candidate
	/// @returns {Real} Send result or -1 without a recipient
	send_lifecycle_status_to_slot = function(raw_target_slot)
	{
		/* Normalize the logical recipient before choosing its actual accepted socket
		and transport for lifecycle status */
		var target_slot = slot_from_value(raw_target_slot);

		/* No valid occupied slot means no lifecycle recipient. Return -1 before
		encoding status for an absent connection */
		if (target_slot == noone || sockets[target_slot] == noone)
		{
			return -1;
		}

		net.start(N_SERVER_LIFECYCLE, noone);
		net.write(buffer_u8, SERVER_LIFECYCLE_STATUS);

		/* The status body encodes enabled as one/zero, period as unsigned minutes and
		remaining time as unsigned seconds. The header uses noone for a server sender */
		net.write(buffer_u8, automatic_reset_enabled ? 1 : 0);
		net.write(buffer_u16, automatic_reset_interval_minutes);
		net.write(buffer_u32, reset_remaining_seconds());
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Publish reset/countdown status and close failed recipients
	/// @returns {Real} Recipient count or -1 for any eligible delivery failure
	broadcast_lifecycle_status = function()
	{
		net.start(N_SERVER_LIFECYCLE, noone);
		net.write(buffer_u8, SERVER_LIFECYCLE_STATUS);

		/* Broadcast the same one/zero policy, minutes and remaining seconds to every
		occupied gameplay slot so clients can build their own local countdown deadline */
		net.write(buffer_u8, automatic_reset_enabled ? 1 : 0);
		net.write(buffer_u16, automatic_reset_interval_minutes);
		net.write(buffer_u32, reset_remaining_seconds());

		/* result is the recipient count or -1 when an eligible send failed.
		The shared failure lists identify which occupied slots require cleanup */
		var result = net.send_all(sockets);

		/* Close failed recipients after the lifecycle broadcast. Successful delivery
		leaves connections intact */
		if (result < 0)
		{
			close_failed_send_slots("broadcasting server lifecycle status");
		}
		return result;
	}

	/// @description Send saved gameplay capacity to one occupied slot
	/// @param {Any} raw_target_slot Logical recipient candidate
	/// @returns {Real} Send result or -1 without a recipient
	send_player_limit_to_slot = function(raw_target_slot)
	{
		/* Resolve the logical player before sending authoritative gameplay capacity,
		which differs from the fixed socket-array storage size */
		var target_slot = slot_from_value(raw_target_slot);

		/* Capacity updates need a valid occupied recipient. Invalid/empty slots
		return failure without a send */
		if (target_slot == noone || sockets[target_slot] == noone)
		{
			return -1;
		}

		net.start(N_SERVER_PLAYER_LIMIT, noone);
		net.write(buffer_u16, max_players);
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Broadcast current gameplay capacity and close failed recipients
	/// @returns {Real} Recipient count or -1 for an eligible failure
	broadcast_player_limit = function()
	{
		net.start(N_SERVER_PLAYER_LIMIT, noone);
		net.write(buffer_u16, max_players);

		/* result reports delivery of the updated player limit across occupied slots,
		with shared failed-send lists retained for cleanup */
		var result = net.send_all(sockets);

		/* Clean failed recipient slots after broadcasting capacity. The new server
		limit remains applied rather than being rolled back for transport failures */
		if (result < 0)
		{
			close_failed_send_slots("broadcasting the server player limit");
		}
		return result;
	}

	/// @description Save and broadcast a validated join limit. Existing players remain connected
	/// @param {Real} raw_max_players Requested player count within network limits
	/// @returns {Bool} Whether saved. A write failure restores the previous limit
	set_max_players = function(raw_max_players)
	{
		/* The proposed whole player count is assigned inside guarded conversion.
		Conversion failure returns false before changing the current capacity */
		var requested_max_players;
		try
		{
			requested_max_players = floor(real(raw_max_players));
		}
		catch(e)
		{
			return false;
		}

		/* Reject player counts outside network gameplay bounds rather than expanding
		socket storage or silently clamping an administrator request */
		if (requested_max_players < net.min_player_limit
		|| requested_max_players > net.max_player_limit)
		{
			return false;
		}

		/* Retain the current capacity so a persistence failure can restore it.
		The new value is broadcast only after settings are successfully saved */
		var previous_max_players = max_players;
		max_players = requested_max_players;

		/* If persistence fails, restore the previous limit and report false.
		Do not publish a capacity change that was not saved */
		if (!save_lifecycle_settings())
		{
			max_players = previous_max_players;
			return false;
		}

		broadcast_player_limit();
		return true;
	}

	/// @description Send the strict Boolean wall policy to one occupied slot
	/// @param {Any} raw_target_slot Logical recipient candidate
	/// @returns {Real} Send result or -1 without a recipient
	send_wall_settings_to_slot = function(raw_target_slot)
	{
		/* Validate the recipient logical slot before selecting its socket for the
		server wall-edit policy byte */
		var target_slot = slot_from_value(raw_target_slot);

		/* Invalid or unoccupied targets cannot receive wall policy. Return failure
		before building the settings packet */
		if (target_slot == noone || sockets[target_slot] == noone) return -1;
		net.start(N_WALL_SETTINGS, noone);

		/* Encode enabled as one and disabled as zero, matching the strict client wall-
		settings decoder */
		net.write(buffer_u8, wall_drawing_enabled ? 1 : 0);
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Persist wall policy with rollback on write failure, then broadcast and clean failed recipients
	/// @param {Bool} enabled Desired policy, accepting true or numeric one
	/// @returns {Bool} Whether the policy was saved
	set_wall_drawing_enabled = function(enabled)
	{
		/* Keep the current wall policy for rollback. Only true or numeric one selects
		enabled in the proposed policy, while other values select disabled */
		var previous_enabled = wall_drawing_enabled;
		wall_drawing_enabled = enabled == true || enabled == 1;

		/* A failed settings write restores the previous policy and prevents broadcast,
		so clients are not told to adopt an unsaved change */
		if (!save_lifecycle_settings())
		{
			wall_drawing_enabled = previous_enabled;
			return false;
		}
		net.start(N_WALL_SETTINGS, noone);

		/* Publish the persisted wall policy as a strict Boolean wire byte */
		net.write(buffer_u8, wall_drawing_enabled ? 1 : 0);

		/* Failed recipients are closed after publishing the saved policy.
		The setting remains applied for successfully connected players */
		if (net.send_all(sockets) < 0) close_failed_send_slots("broadcasting wall drawing settings");
		return true;
	}

	/// @description Change reset policy, attempt persistence, rebuild its countdown and publish status
	/// @param {Bool} enabled Desired policy, accepting explicit true
	/// @returns {Bool} Resulting enabled state, independent of save success
	set_automatic_reset_enabled = function(enabled)
	{
		/* Only true enables the policy. Save it, rebuild its current_time schedule and
		publish status. This setter returns the resulting state, not persistence success */
		automatic_reset_enabled = enabled == true;
		save_lifecycle_settings();
		start_reset_schedule();
		broadcast_lifecycle_status();
		return automatic_reset_enabled;
	}

	/// @description Adjust bounded reset minutes, attempt persistence and restart the countdown
	/// @param {Real} delta_minutes Whole-minute adjustment before clamping
	/// @returns {Real} Resulting configured minutes
	adjust_automatic_reset_minutes = function(delta_minutes)
	{
		automatic_reset_interval_minutes = clamp(
			automatic_reset_interval_minutes + floor(real(delta_minutes)),
			automatic_reset_min_minutes,
			automatic_reset_max_minutes
		);
		save_lifecycle_settings();
		start_reset_schedule();
		broadcast_lifecycle_status();
		return automatic_reset_interval_minutes;
	}

	/// @description Replace bounded reset minutes, attempt persistence and restart the countdown
	/// @param {Real} raw_minutes Requested whole-minute period before clamping
	/// @returns {Real} Resulting configured minutes
	set_automatic_reset_minutes = function(raw_minutes)
	{
		automatic_reset_interval_minutes = clamp(
			floor(real(raw_minutes)),
			automatic_reset_min_minutes,
			automatic_reset_max_minutes
		);
		save_lifecycle_settings();
		start_reset_schedule();
		broadcast_lifecycle_status();
		return automatic_reset_interval_minutes;
	}

	/// @description Announce the ordered reset sequence/reason and close failed recipients
	/// @param {Real} reset_id Reset correlation sequence
	/// @param {String} reason Reset cause for clients
	/// @returns {Real} Recipient count or -1 for an eligible failure
	broadcast_lifecycle_reset = function(reset_id, reason)
	{
		net.start(N_SERVER_LIFECYCLE, noone);
		net.write(buffer_u8, SERVER_LIFECYCLE_RESET_NOW);
		net.write(buffer_u32, reset_id);
		net.write(buffer_string, string(reason));

		/* result reports reset-notification recipients or negative delivery failure.
		The same reset sequence/reason is sent to all occupied slots */
		var result = net.send_all(sockets);

		/* Close failed recipients after broadcasting the ordered reset notice.
		Successfully connected players continue with the reset sequence */
		if (result < 0)
		{
			close_failed_send_slots("broadcasting drawing reset");
		}
		return result;
	}

	/// @description Publish the shutdown/restart reason to occupied players
	/// @param {String} reason Lifecycle cause
	/// @returns {Real} Broadcast count or -1 for an eligible failure
	broadcast_lifecycle_shutdown = function(reason)
	{
		net.start(N_SERVER_LIFECYCLE, noone);
		net.write(buffer_u8, SERVER_LIFECYCLE_SHUTDOWN);
		net.write(buffer_string, string(reason));
		return net.send_all(sockets);
	}

	/// @description Verify the archive and clear persistence and walls before broadcasting the reset
	/// @param {String} reason Logged lifecycle cause, defaulting to scheduled_reset
	/// @returns {Bool} Whether reset completed. Failed verification postpones the schedule
	perform_drawing_reset = function(reason = "scheduled_reset")
	{
		/* Only a running server can coordinate reset archives and lifecycle packets.
		Stopped state returns false before changing authoritative canvas persistence */
		if (!is_running())
		{
			return false;
		}

		/* Borrow authoritative drawing state. archived is true only when its forced
		archive save succeeds and archive verification passes, with verification skipped
		if the save already failed */
		var drawing = scr_get_drawing();
		var archived = drawing.save_automatic_archive("server_reset", "server", true)
			&& verify_force_restart_archive(drawing, "automatic_server_reset");

		/* An unverified archive postpones reset and restarts the schedule.
		Keep authoritative drawing intact and explain the postponed operation */
		if (!archived)
		{
			start_reset_schedule();
			broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "The drawing reset was postponed because its archive could not be verified.");
			broadcast_lifecycle_status();
			return false;
		}

		/* If saved history cannot be safely removed, preserve it and postpone reset.
		Restart countdown/status instead of clearing a canvas that may restore on restart */
		if (!drawing.delete_server_history_persistence())
		{
			drawing.save_server_history_persistence(true);
			start_reset_schedule();
			broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "The drawing reset was postponed because its saved history could not be cleared safely.");
			broadcast_lifecycle_status();
			return false;
		}

		/* Wall reset persistence must succeed before clearing authoritative drawing.
		Failure re-saves drawing history and postpones the reset */
		if (!scr_get_walls().reset_server())
		{
			drawing.save_server_history_persistence(true);
			start_reset_schedule();
			broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "The drawing reset was postponed because the walls could not be saved safely.");
			broadcast_lifecycle_status();
			return false;
		}

		drawing_reset_sequence++;

		/* Wrap the reset correlation sequence to one before exceeding its chosen range.
		Zero remains the initial not-yet-reset state */
		if (drawing_reset_sequence > 4000000000)
		{
			drawing_reset_sequence = 1;
		}

		broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "The drawing was archived and is being reset now.");
		broadcast_lifecycle_reset(drawing_reset_sequence, reason);

		/* Borrow the in-process client only to synchronize Host & Play reset handling.
		Remote clients receive the ordered lifecycle packet instead */
		var local_client = scr_get_client();

		/* Apply directly only to a present local-host client with reset capability.
		Other clients rely on network delivery, avoiding duplicate shared-state assumptions */
		if (is_struct(local_client)
		&& variable_struct_exists(local_client, "local_host_mode")
		&& local_client.local_host_mode
		&& variable_struct_exists(local_client, "handle_server_drawing_reset"))
		{
			local_client.handle_server_drawing_reset(drawing_reset_sequence, reason);
		}

		drawing.reset_server(false);
		drawing.clear_client_drawing_state();
		start_reset_schedule();
		broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "The drawing was archived and reset.");
		broadcast_lifecycle_status();
		return true;
	}

	/// @description Queue a restart after the reply delay. Archive verification runs before shutdown
	/// @param {String} reason Logged lifecycle cause, defaulting to manual_force_restart
	/// @param {Real} requester_slot Requesting admin slot, defaulting to noone for a local request
	/// @param {Real} request_id Correlation ID, defaulting to zero when no remote reply is needed
	/// @returns {Bool} Whether a running server accepted a new restart request
	request_force_restart = function(reason = "manual_force_restart", requester_slot = noone, request_id = 0)
	{
		/* A restart needs a running server with no shutdown or previous restart underway.
		Reject duplicate requests before overwriting archive/request metadata */
		if (!is_running() || shutdown_in_progress || force_restart_pending || force_restart_in_progress)
		{
			return false;
		}

		/* Bound the restart reason to 96 characters for lifecycle/log metadata.
		Empty text receives the existing manual-restart fallback */
		var clean_reason = string_copy(string(reason), 1, 96);

		/* Give an empty request the known manual restart cause, keeping archive and
		client reconnect feedback meaningful */
		if (clean_reason == "")
		{
			clean_reason = "manual_force_restart";
		}

		force_restart_pending = true;
		force_restart_pending_at = current_time + force_restart_delay_ms;
		force_restart_pending_reason = clean_reason;
		force_restart_pending_slot = slot_from_value(requester_slot);
		force_restart_pending_request_id = max(0, floor(real(request_id)));
		debug_log("Safe server restart requested; drawing persistence and archives will be verified before restart.");
		return true;
	}

	/// @description Clear restart state and send failure to its still-authenticated original requester
	/// @param {String} message Archive/lifecycle failure reason
	/// @returns {Bool} False to propagate restart failure
	abort_force_restart = function(message)
	{
		/* Capture failure text and the original requester slot/request ID before
		clearing pending restart state. These values permit correlated failure feedback */
		var failure_message = string(message);
		var requester_slot = force_restart_pending_slot;
		var request_id = force_restart_pending_request_id;
		force_restart_pending = false;
		force_restart_pending_at = 0;
		force_restart_pending_reason = "";
		force_restart_pending_slot = noone;
		force_restart_pending_request_id = 0;
		force_restart_in_progress = false;
		debug_error("Safe server restart aborted: " + failure_message);

		/* Send restart-abort feedback only to an original requester whose exact socket
		session remains authenticated. Disconnected/reused slots must not receive it */
		if (requester_slot != noone && admin_slot_is_authenticated(requester_slot))
		{
			send_admin_result(requester_slot, request_id, ADMIN_ACTION_FORCE_RESTART, ADMIN_RESULT_FAILED, "Restart aborted: " + failure_message);
			send_admin_status(requester_slot, request_id);
		}
		return false;
	}

	/// @description Load and release a PNG buffer while checking signature, trailer and room dimensions
	/// @param {String} path Expected archive file
	/// @param {Struct} drawing Dimension parser service
	/// @returns {Bool} Whether this file passes structural and size checks
	force_restart_archive_file_is_valid = function(path, drawing)
	{
		/* archive_path is the expected PNG file to inspect, not a resource to create.
		An empty/missing path cannot prove that the archive exists */
		var archive_path = string(path);

		/* Reject absent archive files before loading, so restart cannot rely on a
		missing output path */
		if (archive_path == "" || !file_exists(archive_path))
		{
			return false;
		}

		/* This function owns a temporary loaded-file buffer, initially absent.
		archive_valid starts false and becomes true only after byte/dimension checks,
		then the buffer is released on either normal or exception paths */
		var archive_buffer = noone;
		var archive_valid = false;
		try
		{
			archive_buffer = buffer_load(archive_path);

			/* Use loaded buffer bytes only when its handle exists, otherwise zero.
			Validity requires minimum PNG length, its eight signature bytes and exact IEND
			trailer bytes. These structural checks precede room-dimension validation */
			var archive_size = (!is_undefined(archive_buffer) && buffer_exists(archive_buffer))
				? buffer_get_size(archive_buffer)
				: 0;
			archive_valid = archive_size >= 41
				&& buffer_exists(archive_buffer)
				&& buffer_peek(archive_buffer, 0, buffer_u8) == 137
				&& buffer_peek(archive_buffer, 1, buffer_u8) == 80
				&& buffer_peek(archive_buffer, 2, buffer_u8) == 78
				&& buffer_peek(archive_buffer, 3, buffer_u8) == 71
				&& buffer_peek(archive_buffer, 4, buffer_u8) == 13
				&& buffer_peek(archive_buffer, 5, buffer_u8) == 10
				&& buffer_peek(archive_buffer, 6, buffer_u8) == 26
				&& buffer_peek(archive_buffer, 7, buffer_u8) == 10
				&& buffer_peek(archive_buffer, archive_size - 12, buffer_u32) == 0
				&& buffer_peek(archive_buffer, archive_size - 8, buffer_u8) == 73
				&& buffer_peek(archive_buffer, archive_size - 7, buffer_u8) == 69
				&& buffer_peek(archive_buffer, archive_size - 6, buffer_u8) == 78
				&& buffer_peek(archive_buffer, archive_size - 5, buffer_u8) == 68
				&& buffer_peek(archive_buffer, archive_size - 4, buffer_u8) == 174
				&& buffer_peek(archive_buffer, archive_size - 3, buffer_u8) == 66
				&& buffer_peek(archive_buffer, archive_size - 2, buffer_u8) == 96
				&& buffer_peek(archive_buffer, archive_size - 1, buffer_u8) == 130;

			/* Only a structurally valid PNG and available drawing dimension parser can
			proceed to room-size verification. Missing support takes the invalid alternative */
			if (archive_valid
			&& is_struct(drawing)
			&& variable_struct_exists(drawing, "png_dimensions_from_buffer"))
			{
				/* png_info reports decoded width/height and parse status. An accepted archive
				must parse and equal the bounded current room dimensions in pixels */
				var png_info = drawing.png_dimensions_from_buffer(archive_buffer);
				archive_valid = png_info.ok
					&& png_info.w == max(1, room_width)
					&& png_info.h == max(1, room_height);
			}

			/* Without valid structure or dimension support, keep archive_valid false.
			Do not treat merely readable file bytes as a verified archive */
			else
			{
				archive_valid = false;
			}
		}
		catch(e)
		{
			archive_valid = false;
		}

		/* Release the temporary file buffer only when loading created a live handle.
		The caller receives the Boolean result without owning this resource */
		if (!is_undefined(archive_buffer) && buffer_exists(archive_buffer))
		{
			buffer_delete(archive_buffer);
		}
		return archive_valid;
	}

	/// @description Verify the flattened PNG and every drawn layer PNG for the last archive
	/// @param {Struct} drawing Drawing state supplying archive paths, layers, and PNG dimensions
	/// @param {String} archive_category Layer archive directory category, defaulting to automatic_server_restart
	/// @returns {Bool} Whether all expected room-sized PNG files pass the archive checks
	verify_force_restart_archive = function(drawing, archive_category = "automatic_server_restart")
	{
		force_restart_archive_verification_error = "";

		/* Verification requires drawing state and its last flattened filename/path.
		Missing metadata records a specific reason and blocks the restart/reset */
		if (!is_struct(drawing)
		|| !variable_struct_exists(drawing, "last_screenshot_filename")
		|| !variable_struct_exists(drawing, "last_screenshot_path"))
		{
			force_restart_archive_verification_error = "archive file details are unavailable";
			return false;
		}

		/* Capture the flattened name/path and expected _flattened.png suffix length.
		They establish both archive naming and the prefix used for per-layer files */
		var flattened_filename = string(drawing.last_screenshot_filename);
		var flattened_path = string(drawing.last_screenshot_path);
		var flattened_suffix = "_flattened.png";
		var flattened_suffix_length = string_length(flattened_suffix);

		/* Reject empty names, names without a prefix plus expected suffix, and missing/
		invalid flattened PNGs. The suffix check guards against verifying an unrelated file */
		if (flattened_filename == ""
		|| string_length(flattened_filename) <= flattened_suffix_length
		|| string_copy(flattened_filename, string_length(flattened_filename) - flattened_suffix_length + 1, flattened_suffix_length) != flattened_suffix
		|| !force_restart_archive_file_is_valid(flattened_path, drawing))
		{
			force_restart_archive_verification_error = "the flattened drawing archive is missing";
			return false;
		}

		/* Without reported drawn layers, this implementation accepts the flattened file
		alone. A positive drawn-layer count requires the detailed layer checks below */
		if (!variable_struct_exists(drawing, "drawn_layer_count")
		|| drawing.drawn_layer_count() <= 0)
		{
			return true;
		}

		/* Drawn-layer verification requires the layer array and all naming/history/path
		helpers. Missing support blocks restart rather than guessing archive filenames */
		if (!variable_struct_exists(drawing, "layers")
		|| !is_array(drawing.layers)
		|| !variable_struct_exists(drawing, "layer_has_drawn_history")
		|| !variable_struct_exists(drawing, "screenshot_pad_number")
		|| !variable_struct_exists(drawing, "screenshot_safe_name_fragment")
		|| !variable_struct_exists(drawing, "screenshot_save_path"))
		{
			force_restart_archive_verification_error = "layer archive verification support is unavailable";
			return false;
		}

		/* export_prefix removes the verified flattened suffix so each expected layer
		file uses the same archive identity. expected_layer_count begins zero before
		counting only layers with actual drawn history */
		var export_prefix = string_delete(
			flattened_filename,
			string_length(flattened_filename) - flattened_suffix_length + 1,
			flattened_suffix_length
		);
		var expected_layer_count = 0;

		/* Visit every zero-based layer entry. Only valid identified layers with drawn
		history require PNG verification, and all required files must pass */
		for (var layer_index = 0; layer_index < array_length(drawing.layers); layer_index++)
		{
			/* paint_layer is the layer metadata at this array position. Its ID identifies
			history, while its display name/visibility contribute to archive filename rules */
			var paint_layer = drawing.layers[layer_index];

			/* Skip malformed, unidentified or undrawn layers rather than requiring an
			archive PNG for a layer that contributed no recorded drawing */
			if (!is_struct(paint_layer)
			|| !variable_struct_exists(paint_layer, "id")
			|| !drawing.layer_has_drawn_history(paint_layer.id))
			{
				continue;
			}

			expected_layer_count++;

			/* Use the layer name or Layer fallback, and treat missing visibility as visible.
			layer_filename uses the shared prefix, one-based padded display number and safe
			name, adding _hidden only for hidden layers. layer_path resolves its category */
			var layer_name = variable_struct_exists(paint_layer, "name") ? string(paint_layer.name) : "Layer";
			var layer_visible = !variable_struct_exists(paint_layer, "visible") || paint_layer.visible;
			var layer_filename = export_prefix
				+ "_layer_"
				+ drawing.screenshot_pad_number(layer_index + 1, 2)
				+ "_"
				+ drawing.screenshot_safe_name_fragment(layer_name)
				+ (layer_visible ? "" : "_hidden")
				+ ".png";
			var layer_path = drawing.screenshot_save_path(layer_filename, archive_category);

			/* Any missing or invalid expected drawn-layer PNG blocks completion.
			Record that specific failure instead of accepting a partial set of archives */
			if (!force_restart_archive_file_is_valid(layer_path, drawing))
			{
				force_restart_archive_verification_error = "a drawn layer PNG is missing";
				return false;
			}
		}

		/* The counted verifiable layers must match the drawing service reported count.
		A mismatch means coverage could not be established, so do not clear drawing state */
		if (expected_layer_count != drawing.drawn_layer_count())
		{
			force_restart_archive_verification_error = "the drawn layer archive count could not be verified";
			return false;
		}
		return true;
	}

	/// @description After reply delay, verify/persist archives before clearing drawing and relaunching hosting
	/// @returns {Bool} Whether eligible restart completed or requested managed process exit
	perform_pending_force_restart = function()
	{
		/* Run the queued restart only after its response-delay deadline. No request or
		a deadline still ahead leaves authoritative drawing untouched */
		if (!force_restart_pending || current_time < force_restart_pending_at)
		{
			return false;
		}

		force_restart_pending = false;
		force_restart_in_progress = true;

		/* Retain the queued cause while pending becomes in-progress. drawing borrows
		the authoritative service that must persist/archive before listener shutdown */
		var restart_reason = force_restart_pending_reason;
		var drawing = scr_get_drawing();

		/* All persistence, archive, deletion and reset capabilities must exist before
		the restart sequence proceeds. Missing support aborts with correlated feedback */
		if (!is_struct(drawing)
		|| !variable_struct_exists(drawing, "save_server_history_persistence")
		|| !variable_struct_exists(drawing, "save_automatic_archive")
		|| !variable_struct_exists(drawing, "delete_server_history_persistence")
		|| !variable_struct_exists(drawing, "reset_server"))
		{
			return abort_force_restart("drawing persistence or archive support is unavailable");
		}

		/* A forced authoritative history checkpoint must succeed first. Failure aborts
		without clearing the live drawing or shutting down listeners */
		if (!drawing.save_server_history_persistence(true))
		{
			return abort_force_restart("the authoritative drawing history could not be persisted");
		}

		/* Every required archive save must succeed before verification. Failure aborts
		rather than proceeding with a partial archive set */
		if (!drawing.save_automatic_archive("server_restart", "server", true))
		{
			return abort_force_restart("one or more drawing-layer archives could not be saved");
		}

		/* Verify actual flattened/layer PNG outputs before deleting persistence.
		Any structural, dimension or coverage failure aborts with the recorded reason */
		if (!verify_force_restart_archive(drawing))
		{
			return abort_force_restart(force_restart_archive_verification_error);
		}

		/* Deletion failure re-saves authoritative history and aborts. A restart must
		not clear drawing while stale persistence might restore it */
		if (!drawing.delete_server_history_persistence())
		{
			drawing.save_server_history_persistence(true);
			return abort_force_restart("the persisted drawing history could not be cleared safely");
		}

		/* Walls must also persist their cleared state. Failure restores drawing
		persistence and aborts the restart before shutdown */
		if (!scr_get_walls().reset_server())
		{
			drawing.save_server_history_persistence(true);
			return abort_force_restart("the walls could not be cleared safely");
		}

		broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "All drawing layers were archived. The server is restarting with a blank canvas.");
		broadcast_lifecycle_shutdown(restart_reason);
		drawing.reset_server(true);

		/* Clear in-process client canvas state when the method exists after server reset.
		Missing optional client support does not invalidate the verified archive */
		if (variable_struct_exists(drawing, "clear_client_drawing_state"))
		{
			drawing.clear_client_drawing_state();
		}

		debug_success("Safe server restart archive completed; authoritative drawing state was cleared.");

		/* Managed server startup mode uses its external service supervisor for relaunch.
		Other modes reopen listeners in-process. This Boolean is captured before shutdown */
		var use_process_supervisor = string_lower(string_trim(environment_get_variable("JONNIL_STARTUP_MODE"))) == "server";
		shutdown(restart_reason, false, true);

		/* A managed process ends only after verified archives and shutdown, allowing
		its supervisor to relaunch. Other modes continue to in-process init */
		if (use_process_supervisor)
		{
			debug_log("Ending the managed server process so its service supervisor can relaunch it.");
			game_end();
			return true;
		}

		init();

		/* After in-process init, both TCP running state and a valid WebSocket listener
		are required. Report false if either failed instead of claiming restart succeeded */
		if (!is_running()
		|| !is_real(websocket_server)
		|| websocket_server < 0)
		{
			debug_error("The in-process server restart did not reopen both required listeners.");
			return false;
		}
		debug_success("The server restarted in-process with a blank authoritative canvas.");
		return true;
	}

	/// @description Validate the authenticated request and execute a supported server lifecycle action
	/// @param {Any} raw_slot Logical player-slot value, validated against the sockets array
	/// @param {Real} protocol_version Client protocol version
	/// @param {Real} request_id Nonzero request ID echoed in responses
	/// @param {Real} action ADMIN_ACTION value
	/// @param {Any} value Action value, defaulting to undefined for actions without one. Intervals are minutes and limits are player counts
	/// @returns {Bool} Whether the resulting ADMIN_RESULT code is OK
	handle_admin_command = function(raw_slot, protocol_version, request_id, action, value = undefined)
	{
		/* Normalize the command sender before checking its exact authenticated socket
		binding. Admin actions operate on server state only after this guard */
		var slot = slot_from_value(raw_slot);

		/* Invalid or unauthenticated senders cannot run server commands.
		Only a valid slot can receive the authentication-required response */
		if (slot == noone || !admin_slot_is_authenticated(slot))
		{
			/* Reply with denial only when the logical slot is valid. Invalid sender input
			cannot select a socket to receive command feedback */
			if (slot != noone)
			{
				send_admin_result(slot, request_id, action, ADMIN_RESULT_DENIED, "Remote admin authentication is required.");
			}
			return false;
		}

		/* Require a compatible layout and positive correlation ID before changing
		server lifecycle or recording a request as handled */
		if (protocol_version != ADMIN_PROTOCOL_VERSION || request_id <= 0)
		{
			send_admin_result(slot, request_id, action, ADMIN_RESULT_INVALID, "Invalid remote admin command.");
			return false;
		}

		/* Reject the same last request ID so an immediately repeated packet cannot
		apply the same reset/restart command twice */
		if (admin_last_request_ids[slot] == request_id)
		{
			send_admin_result(slot, request_id, action, ADMIN_RESULT_INVALID, "Duplicate remote admin request.");
			return false;
		}
		admin_last_request_ids[slot] = request_id;

		/* Begin with successful command feedback and status follow-up enabled.
		Each action may replace result_code/message, while unknown actions suppress status
		because no recognized operation was requested */
		var result_code = ADMIN_RESULT_OK;
		var result_message = "Command completed.";
		var send_status_after = true;

		/* Select the authenticated operation by its admin action ID. Each setting
		validates its own units/allowed values before mutation, while reset/restart paths
		use their archive and duplicate guards */
		switch(action)
		{
			/* Status-only commands retain success and cause the status follow-up below.
			No setting or drawing state changes in this branch */
			case ADMIN_ACTION_STATUS:
				result_message = "Server status refreshed.";
				break;

			/* Only true or numeric one enables automatic reset. Choose enabled/disabled
			feedback from the resulting policy after the setter rebuilds its schedule */
			case ADMIN_ACTION_SET_RESET_ENABLED:
				set_automatic_reset_enabled(value == true || value == 1);
				result_message = automatic_reset_enabled
					? "Automatic drawing resets enabled."
					: "Automatic drawing resets disabled.";
				break;

			/* Wall editing accepts only strict zero/one input and needs persistence to
			succeed before reporting the new policy */
			case ADMIN_ACTION_SET_WALL_DRAWING:

				/* Reject non-Boolean wall policy values before invoking the setter.
				Malformed input cannot silently become disable permission */
				if (value != 0 && value != 1)
				{
					result_code = ADMIN_RESULT_INVALID;
					result_message = "Wall drawing must be enabled or disabled.";
					break;
				}

				/* A failed settings write retains the previous wall policy.
				Report failure rather than claiming the requested state was installed */
				if (!set_wall_drawing_enabled(value == 1))
				{
					result_code = ADMIN_RESULT_FAILED;
					result_message = "The wall drawing setting could not be saved. The previous setting was kept.";
					break;
				}

				/* Feedback follows the persisted policy. Enabled permits editing, while
				disabled feedback explains the existing passable-wall behavior */
				result_message = wall_drawing_enabled ? "Wall drawing enabled." : "Wall drawing disabled. Existing walls are passable.";
				break;

			/* The reset-period action supplies whole minutes and is rejected outside the
			server configured minimum/maximum rather than silently clamped */
			case ADMIN_ACTION_SET_RESET_INTERVAL:

				/* requested_minutes is the converted whole-minute period proposed by this
				command, validated before changing countdown state */
				var requested_minutes = floor(real(value));

				/* Out-of-range reset minutes produce invalid feedback and leave the current
				schedule unchanged */
				if (requested_minutes < automatic_reset_min_minutes
				|| requested_minutes > automatic_reset_max_minutes)
				{
					result_code = ADMIN_RESULT_INVALID;
					result_message = "Reset interval must be between " + string(automatic_reset_min_minutes) + " and " + string(automatic_reset_max_minutes) + " minutes.";
					break;
				}
				set_automatic_reset_minutes(requested_minutes);
				result_message = "Automatic reset interval set to " + string(automatic_reset_interval_minutes) + " minutes.";
				break;

			/* Gameplay-capacity actions validate the count and persist before broadcasting.
			Lowering below the current count does not disconnect already joined players */
			case ADMIN_ACTION_SET_MAX_PLAYERS:

				/* requested_max_players is the converted whole count proposed by the command.
				It is bounded independently of maximum socket-array capacity */
				var requested_max_players = floor(real(value));

				/* Reject counts outside network gameplay bounds before persistence or broadcasts */
				if (requested_max_players < net.min_player_limit
				|| requested_max_players > net.max_player_limit)
				{
					result_code = ADMIN_RESULT_INVALID;
					result_message = "Maximum players must be between " + string(net.min_player_limit) + " and " + string(net.max_player_limit) + ".";
					break;
				}

				/* A failed capacity save reports failure and preserves the previous limit.
				Do not publish success merely because the requested count was valid */
				if (!set_max_players(requested_max_players))
				{
					result_code = ADMIN_RESULT_FAILED;
					result_message = "The maximum player setting could not be saved. The previous limit was kept.";
					break;
				}
				result_message = "Maximum players set to " + string(max_players) + ".";

				/* When lowering capacity below existing occupancy, explain that current players
				remain and new joins wait for a vacancy. Otherwise ordinary capacity feedback suffices */
				if (connected_players > max_players)
				{
					result_message += " Existing players will stay connected; new joins are paused until the player count is below the limit.";
				}
				break;

			/* An immediate reset still depends on complete archive/persistence verification.
			archive_saved captures the reset result rather than only an attempted save */
			case ADMIN_ACTION_RESET_NOW:

				/* archive_saved reports whether the complete requested reset succeeded.
				Its false path preserves postponed/aborted feedback */
				var archive_saved = perform_drawing_reset("remote_admin_reset");

				/* A completed verified reset gets success feedback. The alternative reports
				failure instead of claiming an archive attempt was enough */
				if (archive_saved)
				{
					result_message = "The drawing was archived and reset.";
				}

			/* Reset failure returns the failed result with archive-verification feedback,
			leaving the reset method own rollback/postponement behavior intact */
			else
			{
				result_code = ADMIN_RESULT_FAILED;
				result_message = "The reset was aborted because its archive could not be verified.";
				}
				break;

			/* Restart commands queue the guarded delayed operation. Immediate acceptance
			means scheduled, while actual archive verification can still abort it later */
			case ADMIN_ACTION_FORCE_RESTART:

				/* A stopped/shutting-down/already-restarting server cannot accept another
				request. Return unavailable instead of replacing an existing restart */
				if (!request_force_restart("remote_admin_restart", slot, request_id))
				{
					result_code = ADMIN_RESULT_UNAVAILABLE;
					result_message = "A shutdown or restart is already in progress.";
				}

				/* The delayed restart was accepted. Feedback states it is scheduled and may
				abort on archive verification, rather than promising a completed relaunch */
				else
				{
					result_message = "Safe restart scheduled. It will abort if the drawing archive cannot be verified.";
				}
				break;

			/* Unknown authenticated actions get invalid feedback and no status follow-up.
			They cannot select an arbitrary server method */
			default:
				result_code = ADMIN_RESULT_INVALID;
				result_message = "Unknown remote admin command.";
				send_status_after = false;
				break;
		}

		debug_log("Remote admin action for " + scr_network_debug_server_slot_label(slot)
			+ ": " + admin_action_name(action) + " request=" + string(request_id)
			+ " result=" + string(result_code));
		send_admin_result(slot, request_id, action, result_code, result_message);

		/* Send follow-up controls only for recognized actions while the sender binding
		is still authenticated. Cleanup during the action may have removed that session */
		if (send_status_after && admin_slot_is_authenticated(slot))
		{
			send_admin_status(slot, request_id);
		}

		/* Return true only for the resulting OK outcome. A valid request may still
		return false when validation, persistence or lifecycle guards rejected its action */
		return result_code == ADMIN_RESULT_OK;
	}

	/// @description Prioritize pending restart, then enforce reset deadlines and one-shot warnings
	/// @returns {Bool} Restart/reset result, true while restarting, otherwise false
	update_lifecycle = function()
	{
		/* An eligible queued restart takes priority over scheduled resets.
		Return its completion result rather than starting another lifecycle operation */
		if (force_restart_pending && current_time >= force_restart_pending_at)
		{
			return perform_pending_force_restart();
		}

		/* An in-progress restart is already handling lifecycle state. Report handled
		without starting reset countdown work concurrently */
		if (force_restart_in_progress)
		{
			return true;
		}

		/* Stopped servers and disabled reset policy have no scheduled canvas work.
		Return false while leaving their current drawing untouched */
		if (!is_running() || !automatic_reset_enabled)
		{
			return false;
		}

		/* An enabled running server with no active deadline seeds a fresh schedule.
		Existing positive deadlines remain intact */
		if (automatic_reset_deadline <= 0)
		{
			start_reset_schedule();
		}

		/* remaining_seconds is the nonnegative rounded countdown from the millisecond
		deadline. Reaching zero triggers the scheduled archive/reset path */
		var remaining_seconds = reset_remaining_seconds();

		/* At or past the deadline, perform the guarded reset and return its result.
		Before expiry, only warning announcements may occur */
		if (remaining_seconds <= 0)
		{
			return perform_drawing_reset("scheduled_reset");
		}

		/* Convert the configured minutes to seconds so warning thresholds use the
		same unit and can exclude warnings longer than the reset period */
		var interval_seconds = automatic_reset_interval_minutes * 60;

		/* Visit each zero-based warning threshold, with the same index in its sent
		flag array. A warning is emitted at most once during this schedule */
		for (var warning_index = 0; warning_index < array_length(automatic_reset_warning_thresholds); warning_index++)
		{
			/* warning_seconds is the remaining-time threshold for this announcement,
			compared with both the configured period and current countdown */
			var warning_seconds = automatic_reset_warning_thresholds[warning_index];

			/* Announce only an unsent threshold shorter than the full period once remaining
			time reaches it. Mark sent before broadcasting so later updates do not repeat it */
			if (!automatic_reset_warnings_sent[warning_index]
			&& warning_seconds < interval_seconds
			&& remaining_seconds <= warning_seconds)
			{
				automatic_reset_warnings_sent[warning_index] = true;
				broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "Automatic drawing reset in " + server_reset_duration_text(warning_seconds) + ". A PNG archive will be saved first.");
			}
		}

		return false;
	}
	#endregion /* Persistence and Server Lifecycle END */

	#region /* Player Slots and Connection Liveness */
	/// @description Resolve an actual accepted socket handle to its logical player slot
	/// @param {Real} socket_value Actual socket handle
	/// @returns {Real} Zero-based player slot or noone
	find_slot_by_socket = function(socket_value)
	{
		/* Reject invalid actual socket handles before scanning occupied player slots.
		A negative creation/error value is not a logical player identity */
		if (!is_real(socket_value)
		|| socket_value < 0)
		{
			return noone;
		}

		/* Scan every zero-based logical slot for the actual accepted handle.
		No match returns noone rather than interpreting the handle as an array index */
		for (var i = 0; i < array_length(sockets); i++)
		{
			/* Return the slot containing this handle, linking async socket events to all
			aligned per-player state arrays */
			if (sockets[i] == socket_value)
			{
				return i;
			}
		}

		return noone;
	}

	/// @description Send the authoritative host-player marker to an occupied recipient
	/// @param {Any} raw_target_slot Logical recipient candidate
	/// @returns {Real} Send result or -1 without a recipient
	send_host_status_to_slot = function(raw_target_slot)
	{
		/* Validate the logical recipient before sending the separate host-player marker */
		var target_slot = slot_from_value(raw_target_slot);

		/* Invalid or unoccupied target slots cannot receive host status.
		Return -1 before choosing a socket */
		if (target_slot == noone
		|| sockets[target_slot] == noone)
		{
			return -1;
		}

		net.start(N_HOST_STATUS, noone);
		net.write(TYPE_ID, host_player_slot);
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Publish host-player ownership to occupied recipients with optional exclusion
	/// @param {Real} exception Logical slot to skip, defaulting to noone for no exclusion
	/// @returns {Real} Successful count or -1 for an eligible failure
	broadcast_host_status = function(exception = noone)
	{
		net.start(N_HOST_STATUS, noone);
		net.write(TYPE_ID, host_player_slot);

		/* send_count is the successful recipient count or failure marker.
		The optional excluded value is a logical slot, independent of socket handles */
		var send_count = net.send_all(sockets, exception);

		/* A failed eligible recipient produces failure diagnostics rather than a
		success count. The method returns that same failure to its caller */
		if (send_count < 0)
		{
			debug_error("Failed to broadcast host player status for slot " + string(host_player_slot));
		}

		/* A nonnegative result reports the number of successful recipients, including
		zero when no other players were eligible */
		else
		{
			debug_log("Broadcast host player status: " + string(host_player_slot) + " to " + string(send_count) + " client(s)");
		}

		return send_count;
	}

	/// @description Claim occupied authoritative player ownership without replacing another active host
	/// @param {Any} raw_slot Proposed logical host slot
	/// @returns {Bool} Whether the host marker was assigned/broadcast
	claim_host_player_slot = function(raw_slot)
	{
		/* Normalize the proposed host player. Ownership can be claimed only by an
		occupied slot with an authoritative player, not merely an accepted listener */
		var slot = slot_from_value(raw_slot);

		/* Host ownership requires a running server, valid occupied slot and existing
		player state. Reject incomplete or invalid claims before changing the host marker */
		if (!is_running()
		|| slot == noone
		|| sockets[slot] == noone
		|| player_controller_get_player(slot, false) == noone)
		{
			debug_error("Refusing to claim invalid host player slot: " + string(raw_slot));
			return false;
		}

		/* A different previously claimed host must be checked before replacement.
		An absent or identical claim does not need this conflict path */
		if (host_player_slot != noone
		&& host_player_slot != slot)
		{
			/* Validate the existing host marker before deciding whether it still names
			an occupied connection that must keep ownership */
			var current_host_slot = slot_from_value(host_player_slot);

			/* Do not replace another valid occupied host slot. An obsolete invalid/empty
			claim can be replaced by the new validated player */
			if (current_host_slot != noone
			&& sockets[current_host_slot] != noone)
			{
				debug_error("Refusing to replace active host player slot " + string(host_player_slot) + " with " + string(slot));
				return false;
			}
		}

		host_player_slot = slot;
		debug_success("Claimed authoritative host player slot " + string(slot));
		broadcast_host_status();
		return true;
	}

	/// @description Clear host ownership only when the optional expected owner still matches
	/// @param {Any} expected_slot Optional owner guard. undefined defaults to unconditional clearing
	/// @param {Bool} broadcast_change Whether to publish removal, defaulting to true
	/// @returns {Bool} Whether an existing matching claim was cleared
	clear_host_player_slot = function(expected_slot = undefined, broadcast_change = true)
	{
		/* No current host claim means there is nothing to clear. Return false without
		broadcasting an unchanged noone marker */
		if (host_player_slot == noone)
		{
			return false;
		}

		/* A supplied expected slot restricts clearing to that host owner. Omitted
		expectation allows unconditional removal of the existing host claim */
		if (!is_undefined(expected_slot))
		{
			/* expected_index is the normalized expected logical owner used to protect a
			newer host claim from an unrelated disconnect cleanup */
			var expected_index = slot_from_value(expected_slot);

			/* Invalid expectations or another owner cannot clear the current host marker.
			Leave it unchanged so unrelated slot cleanup does not remove host ownership */
			if (expected_index == noone
			|| expected_index != host_player_slot)
			{
				return false;
			}
		}

		/* Capture the old owner for diagnostics before restoring noone */
		var previous_host_slot = host_player_slot;
		host_player_slot = noone;
		debug_log("Cleared authoritative host player slot " + string(previous_host_slot));

		/* Notify connected clients only when the caller requested an ownership update.
		Silent resets clear server state without an extra packet */
		if (broadcast_change)
		{
			broadcast_host_status();
		}

		return true;
	}

	/// @description Clear an existing host marker with optional notification
	/// @param {Bool} broadcast_change Whether to publish removal, defaulting to false
	/// @returns {Bool} Whether a host claim was cleared
	reset_host_player_slot = function(broadcast_change = false)
	{
		/* A host marker already clear needs no reset. Return false without invoking
		the conditional clearing method */
		if (host_player_slot == noone)
		{
			return false;
		}

		return clear_host_player_slot(undefined, broadcast_change);
	}

	/// @description Assign the next drawing-author sequence to a valid logical slot
	/// @param {Real} slot Zero-based player slot
	/// @returns {Real} Author identity or zero for an invalid slot
	assign_drawing_author_id = function(slot)
	{
		/* Drawing-author assignment requires a valid logical slot.
		Invalid input returns zero, the unassigned-author marker */
		if (!slot_is_valid(slot))
		{
			return 0;
		}

		/* Capture the next author identity before incrementing its sequence.
		This ID is stored separately from player slot/socket so drawing ownership can persist */
		var author_id = next_drawing_author_id;
		next_drawing_author_id++;

		/* Wrap author numbering to the configured project base before exceeding its
		chosen range. The current assigned ID remains the captured pre-increment value */
		if (next_drawing_author_id > 4000000000)
		{
			next_drawing_author_id = 1000001;
		}

		slot_drawing_author_ids[slot] = author_id;
		return author_id;
	}

	/// @description Unregister and destroy a valid accepted child handle while refusing listener destruction
	/// @param {Real} socket_value Actual accepted socket handle
	/// @returns {Bool} Whether the handle was destroyed
	destroy_client_socket = function(socket_value)
	{
		/* Invalid/negative handles need no socket destruction. Return false before
		unregistering or passing them to network_destroy */
		if (!is_real(socket_value) || socket_value < 0)
		{
			return false;
		}

		/* Refuse to destroy any TCP, WebSocket or discovery listener through accepted-
		client cleanup. These resources belong to whole-server shutdown */
		if (socket_value == server
		|| socket_value == websocket_server
		|| socket_value == discovery_socket)
		{
			debug_error("Refusing to destroy listener socket " + string(socket_value));
			return false;
		}

		net.unregister_socket_transport(socket_value);
		network_destroy(socket_value);
		return true;
	}

	/// @description Clear one valid slot heartbeat schedule/count/sequence/clock
	/// @param {Real} slot Zero-based player slot
	/// @returns {Bool} Whether the slot was valid and reset
	reset_client_heartbeat = function(slot)
	{
		/* Heartbeat reset needs a valid aligned player-array slot.
		Reject another value instead of altering liveness metadata */
		if (!slot_is_valid(slot))
		{
			return false;
		}

		heartbeat_next_ping[slot] = 0;
		heartbeat_missed[slot] = 0;
		heartbeat_sequence[slot] = 0;
		heartbeat_last_heard[slot] = 0;
		return true;
	}

	/// @description Refresh occupied-slot connection liveness and clear missed replies
	/// @param {Real} slot Zero-based player slot
	/// @returns {Bool} Whether an occupied valid slot was refreshed
	note_client_activity = function(slot)
	{
		/* Only valid occupied slots can report connection activity.
		Empty or invalid slots cannot refresh the heartbeat watchdog */
		if (!slot_is_valid(slot)
		|| sockets[slot] == noone)
		{
			return false;
		}

		heartbeat_last_heard[slot] = current_time;
		heartbeat_missed[slot] = 0;
		return true;
	}

	/// @description Refresh occupied-slot gameplay-idle timing and clear/broadcast AFK return
	/// @param {Any} raw_slot Logical sender candidate
	/// @returns {Bool} Whether an occupied valid slot was refreshed
	note_client_gameplay_activity = function(raw_slot)
	{
		/* Normalize the logical sender before refreshing its gameplay idle timestamp.
		This tracks AFK input separately from heartbeat connection liveness */
		var slot = slot_from_value(raw_slot);

		/* Ignore activity for invalid/unoccupied slots, preserving the unused entry
		state rather than treating it as a player returning from AFK */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return false;
		}

		afk_last_activity[slot] = current_time;

		/* Gameplay activity clears an existing AFK indicator and broadcasts return.
		Already-active players only refresh their timestamp without a repeated state packet */
		if (afk_active[slot])
		{
			afk_active[slot] = false;
			broadcast_afk_state(slot, false);
		}

		return true;
	}

	/// @description Guard recursive disconnect broadcasts while removing one authoritative player slot
	/// @param {Real} slot Validated logical sockets-array index
	/// @param {String} reason Disconnect cause, defaulting to empty for the connection closed fallback
	/// @param {Bool} broadcast_remove Whether removal and departure are broadcast, defaulting to true
	/// @param {Bool} destroy_socket Whether to destroy the accepted socket rather than only unregister it, defaulting to true
	/// @returns {Bool} Whether an occupied socket/player slot was closed
	close_client_slot = function(slot, reason = "", broadcast_remove = true, destroy_socket = true)
	{
		/* Slot cleanup requires a valid logical index for every aligned array.
		Reject invalid input before entering the recursive-close guard */
		if (!slot_is_valid(slot))
		{
			debug_error("close_client_slot received invalid slot: " + string(slot));
			return false;
		}

		/* Departure broadcasts can recursively reveal send failures for this same slot.
		Skip a reentrant close until the original cleanup finishes */
		if (client_close_in_progress[slot])
		{
			return false;
		}

		/* Cleanup broadcasts can fail on another client and re-enter this slot */
		client_close_in_progress[slot] = true;
		try
		{
			return close_client_slot_contents(slot, reason, broadcast_remove, destroy_socket);
		}
		finally
		{
			client_close_in_progress[slot] = false;
		}
	}

	/// @description Remove guarded slot state, release accepted ownership and notify remaining players
	/// @param {Real} slot Validated logical slot already guarded by close_client_slot
	/// @param {String} reason Departure cause
	/// @param {Bool} broadcast_remove Whether to notify roster/chat departure
	/// @param {Bool} destroy_socket Whether this cleanup owns handle destruction
	/// @returns {Bool} Whether occupied player/socket state was removed
	close_client_slot_contents = function(slot, reason, broadcast_remove, destroy_socket)
	{
		clear_admin_slot(slot);

		/* Capture the accepted handle and whether it/player exist before resetting state.
		closing_username/author preserve departure metadata, closing_was_host remembers
		ownership, and reason_text normalizes the cause for logs/jobs */
		var socket_to_close = sockets[slot];
		var had_socket = is_real(socket_to_close) && socket_to_close >= 0;
		var had_player = player_controller_get_player(slot, false) != noone;
		var closing_username = slot_usernames[slot];
		var closing_author_id = slot_drawing_author_ids[slot];
		var closing_was_host = host_player_slot == slot;
		var reason_text = string(reason);

		/* An empty cleanup reason receives the connection-closed fallback so logs and
		cancelled sync jobs always have an understandable cause */
		if (reason_text == "")
		{
			reason_text = "connection closed";
		}

		/* An already empty slot needs no full departure cleanup. Its stale host claim
		is still cleared when necessary before returning false */
		if (!had_socket && !had_player)
		{
			/* Even an empty leftover slot must release its old host marker.
			Other empty slots leave ownership unchanged */
			if (closing_was_host)
			{
				clear_host_player_slot(slot, true);
			}
			return false;
		}

		/* Borrow drawing state to clear sender-owned undo/uploads/sync jobs and update
		layer voting before resetting this logical slot */
		var drawing = scr_get_drawing();

		/* Clear slot/socket undo-author state when that drawing capability exists.
		Missing support skips this optional cleanup without an invalid method call */
		if (is_struct(drawing)
		&& variable_struct_exists(drawing, "server_clear_undo_authors_for_slot"))
		{
			drawing.server_clear_undo_authors_for_slot(slot, socket_to_close);
		}

		/* Cancel this slot pending image uploads when the image cleanup method exists.
		Other sender uploads remain owned by their slots */
		if (is_struct(drawing)
		&& variable_struct_exists(drawing, "server_clear_pending_images_for_slot"))
		{
			drawing.server_clear_pending_images_for_slot(slot);
		}

		/* Cancel this departing slot history-sync jobs when supported, attaching the
		captured cleanup reason rather than leaving queued work for a reused slot */
		if (is_struct(drawing)
		&& variable_struct_exists(drawing, "cancel_history_sync_jobs_for_slot"))
		{
			drawing.cancel_history_sync_jobs_for_slot(slot, reason_text);
		}

		/* Let the active layer vote remove this departing voter when supported.
		Without a vote hook, skip it without interrupting socket cleanup */
		if (is_struct(drawing)
		&& variable_struct_exists(drawing, "server_layer_vote_slot_disconnected"))
		{
			drawing.server_layer_vote_slot_disconnected(slot);
		}

		/* Broadcast typing removal only for an active indicator, excluding the departing
		slot from delivery. Inactive slots need no redundant typing packet */
		if (typing_active[slot])
		{
			clear_client_typing(slot, slot);
		}

		/* Clear/broadcast an active AFK indicator before its name/slot metadata resets.
		Inactive slots skip the redundant indicator operation */
		if (afk_active[slot])
		{
			clear_client_afk(slot, slot);
		}

		sockets[slot] = noone;
		slot_transports[slot] = TRANSPORT_TCP;
		slot_usernames[slot] = "";
		slot_character_keys[slot] = "player1";
		slot_character_manifests[slot] = noone;
		slot_pet_keys[slot] = "";
		slot_pet_manifests[slot] = noone;
		pet_change_next_at[slot] = 0;
		asset_upload_window_started[slot] = 0;
		asset_upload_window_bytes[slot] = 0;
		asset_upload_reserved_keys[slot] = "";
		asset_upload_reserved_bytes[slot] = 0;
		slot_drawing_author_ids[slot] = 0;
		clear_character_jobs_for_slot(slot);
		clear_pending_character_uploads(slot);
		prune_character_cache();
		position_dirty[slot] = false;
		client_movement_authority[slot] = false;
		latency_reply_next_at[slot] = 0;
		typing_active[slot] = false;
		typing_deadlines[slot] = 0;
		afk_active[slot] = false;
		afk_last_activity[slot] = 0;
		reset_client_heartbeat(slot);
		connected_players = max(0, connected_players - 1);

		/* When the last player leaves and checkpoint capability exists, request history
		persistence. Remaining occupancy or missing support skips this checkpoint request */
		if (connected_players <= 0
		&& is_struct(drawing)
		&& variable_struct_exists(drawing, "server_request_history_checkpoint"))
		{
			drawing.server_request_history_checkpoint("last player left");
		}

		/* Remove authoritative player state only when it existed before cleanup.
		Status/empty connections do not manufacture a player-removal operation */
		if (had_player)
		{
			player_controller_remove_player(slot);
		}

		/* Destroy an existing accepted socket when requested.
		Otherwise a valid handle can be unregistered without being destroyed */
		if (destroy_socket && had_socket)
		{
			destroy_client_socket(socket_to_close);
		}

		/* If the handle existed but caller owns destruction, remove transport registration
		only. An absent handle skips both resource operations */
		else if (had_socket)
		{
			net.unregister_socket_transport(socket_to_close);
		}

		debug_error("Closed " + scr_network_debug_id_label(slot, closing_username) + " socket=" + string(socket_to_close) + " author=" + string(closing_author_id) + ": " + reason_text);

		/* Publish roster removal only for a real departed player when notifications
		were requested. Other cleanup remains silent to avoid fictitious roster changes */
		if (broadcast_remove && had_player)
		{
			net.start(N_REMOVE_PLAYER, slot);
			net.write(TYPE_ID, slot);

			/* remove_result reports delivery to remaining occupied slots, excluding the
			departing logical slot. It is a count or negative failure result */
			var remove_result = net.send_all(sockets, slot);

			/* Report failed departure delivery rather than logging a successful count.
			Cleanup remains complete even if another recipient cannot receive it */
			if (remove_result < 0)
			{
				debug_error("Failed to broadcast N_REMOVE_PLAYER for slot " + string(slot));
			}

			/* Log successful departure delivery only when someone received it.
			Zero recipients need no delivery-count message */
			else if (remove_result > 0)
			{
				debug_log("Broadcast N_REMOVE_PLAYER for slot " + string(slot) + " to " + string(remove_result) + " client(s)");
			}
		}

		/* A requested real-player departure with a visible name gets a chat notice.
		Unnamed or silent cleanup avoids an empty/fictitious announcement */
		if (broadcast_remove && had_player && closing_username != "")
		{
			broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", closing_username + " left the game.");
		}

		/* Clear the captured host ownership after its slot is removed, broadcasting
		noone so remaining clients do not retain a departed host marker */
		if (closing_was_host)
		{
			clear_host_player_slot(slot, true);
		}

		return true;
	}

	/// @description Drain send failures in bounded passes. Departure broadcasts can expose further failures
	/// @param {String} reason Disconnect cause, defaulting to send failed
	/// @returns {Real} Number of occupied player slots closed
	close_failed_send_slots = function(reason = "send failed")
	{
		/* Failure cleanup requires an available failed-slot array from the shared
		network service. Older/incomplete services return zero rather than indexing it */
		if (!variable_struct_exists(net, "failed_send_slots")
		|| !is_array(net.failed_send_slots))
		{
			return 0;
		}

		/* closed_count begins with no removed players. seen_slots is false for each
		logical slot so a failed slot is processed once, and remaining_passes caps cascading
		broadcast cleanup at socket-array capacity */
		var closed_count = 0;
		var seen_slots = array_create(array_length(sockets), false);
		var remaining_passes = array_length(sockets);

		/* Continue only while failed slots remain and the capacity-sized pass budget
		has not expired. Departure broadcasts may create another failure batch, but the
		bound prevents endless recursive cleanup */
		while (array_length(net.failed_send_slots) > 0
		&& remaining_passes > 0)
		{
			remaining_passes--;

			/* Capture this failure batch before clearing shared lists. Cleanup broadcasts
			can populate the shared lists for the next bounded pass */
			var failed_slots = net.failed_send_slots;
			net.clear_failed_sends();

			/* Visit each zero-based entry in the captured failure batch.
			Invalid or already-seen logical slots are skipped without blocking later entries */
			for (var i = 0; i < array_length(failed_slots); i++)
			{
				/* failed_slot is a logical player index recorded by broadcast, not an actual
				socket handle. Validate it before using seen_slots or closing player state */
				var failed_slot = failed_slots[i];

				/* Ignore malformed failure indexes instead of accessing arrays out of bounds */
				if (!slot_is_valid(failed_slot))
				{
					continue;
				}

				/* A slot already processed in this cleanup pass chain must not close again,
				including failures exposed by later departure broadcasts */
				if (seen_slots[failed_slot])
				{
					continue;
				}

				seen_slots[failed_slot] = true;

				/* Count only a close that actually removed occupied socket/player state.
				Already-empty/reentrant slots return false and do not inflate the total */
				if (close_client_slot(failed_slot, reason, true, true))
				{
					closed_count++;
				}
			}
		}

		return closed_count;
	}

	/// @description Send scheduled pings and close slots after the final allowed reply interval
	/// @returns {Real} Number of player slots closed during this update
	update_client_heartbeats = function()
	{
		/* Count player slots actually closed during this heartbeat update, starting zero */
		var closed_count = 0;

		/* Inspect each zero-based logical slot for occupied heartbeat scheduling.
		Empty slots skip work and one failed client does not prevent checking others */
		for (var slot = 0; slot < array_length(sockets); slot++)
		{
			/* target_socket is the actual handle in this logical player slot.
			The slot indexes all heartbeat timing/counter arrays */
			var target_socket = sockets[slot];

			/* An unused slot has no connection to ping. Continue without changing its
			unused heartbeat defaults */
			if (target_socket == noone)
			{
				continue;
			}

			/* An occupied but invalid handle cannot answer a heartbeat. Close its slot and
			continue so valid peers still receive their scheduled checks */
			if (!is_real(target_socket)
			|| target_socket < 0)
			{
				/* Increase the closed count only if invalid-handle cleanup removed actual
				slot/player occupancy */
				if (close_client_slot(slot, "invalid heartbeat socket", true, true))
				{
					closed_count++;
				}
				continue;
			}

			/* Seed an unscheduled slot deadline one heartbeat interval from now,
			giving a new connection a full interval before its first ping */
			if (heartbeat_next_ping[slot] <= 0)
			{
				heartbeat_next_ping[slot] = current_time + net.client_heartbeat_interval_ms;
			}

			/* Before the current_time deadline, leave this connection alone.
			Only due slots advance missed counts or send a new ping */
			if (current_time < heartbeat_next_ping[slot])
			{
				continue;
			}

			/* After the previous final permitted ping had its full reply interval, reaching
			the missed limit closes the silent client rather than sending indefinitely */
			if (heartbeat_missed[slot] >= net.client_heartbeat_missed_limit)
			{
				/* silent_seconds converts the elapsed last-heard clock to whole seconds.
				timeout_reason includes that liveness duration for the departure diagnostic */
				var silent_seconds = max(0, floor((current_time - heartbeat_last_heard[slot]) / 1000));
				var timeout_reason = "missed " + string(net.client_heartbeat_missed_limit) + " heartbeat response(s) over " + string(silent_seconds) + "s";
				send_server_kick_to_slot(slot, "Disconnected: missed heartbeat responses for " + string(silent_seconds) + "s.");

				/* Count only an actual occupied-slot close after heartbeat timeout notification */
				if (close_client_slot(slot, timeout_reason, true, true))
				{
					closed_count++;
				}
				continue;
			}

			heartbeat_sequence[slot]++;
			net.start(N_HEARTBEAT_PING, slot);
			net.write(buffer_u32, heartbeat_sequence[slot]);

			/* The ping send result uses this slot aligned transport. Failure closes the
			connection. Success increments missed replies and schedules the next full interval */
			var send_result = net.send(target_socket, false, slot_transports[slot]);

			/* A failed ping route cannot maintain this connection. Send removal feedback
			when possible, close its slot and continue with other peers */
			if (send_result < 0)
			{
				send_server_kick_to_slot(slot, "Disconnected: the server could not send a heartbeat ping.");

				/* Count the failed-ping departure only if it actually removed occupied state */
				if (close_client_slot(slot, "heartbeat send failed", true, true))
				{
					closed_count++;
				}
				continue;
			}

			heartbeat_missed[slot]++;
			heartbeat_next_ping[slot] = current_time + net.client_heartbeat_interval_ms;

			/* Give the last permitted ping its full response interval too */
		}

		return closed_count;
	}
	#endregion /* Player Slots and Connection Liveness END */

	#region /* Movement and Collision Synchronization */
	/// @description Flag one valid logical slot for the next movement batch
	/// @param {Real} slot Zero-based player slot
	/// @returns {Bool} Whether the slot was valid and marked
	mark_position_dirty = function(slot)
	{
		/* Only a valid logical player slot can be marked dirty. Invalid values leave
		broadcast flags unchanged */
		if (!slot_is_valid(slot))
		{
			return false;
		}

		position_dirty[slot] = true;
		return true;
	}

	/// @description Check negotiated movement ownership on an occupied slot
	/// @param {Any} raw_slot Logical player candidate
	/// @returns {Bool} Whether client-owned movement is active
	slot_uses_client_movement_authority = function(raw_slot)
	{
		/* Normalize the player slot before checking negotiated movement ownership.
		Occupied socket state is required alongside the authority flag */
		var slot = slot_from_value(raw_slot);

		/* Client movement ownership is true only for a valid occupied slot whose
		handshake completed. Invalid/empty or compatibility-mode slots return false */
		return slot != noone
			&& sockets[slot] != noone
			&& client_movement_authority[slot];
	}

	/// @description Send accepted movement protocol and broadcast interval before enabling authority
	/// @param {Any} raw_slot Logical player candidate
	/// @returns {Real} Send result or -1 without a valid occupied handle
	send_client_movement_authority_ack = function(raw_slot)
	{
		/* Validate the logical recipient before sending the movement version/interval
		acknowledgment on its actual accepted socket */
		var slot = slot_from_value(raw_slot);

		/* An ack needs an occupied numeric nonnegative socket in a valid slot.
		Invalid connection state returns -1 instead of enabling client authority */
		if (slot == noone
		|| sockets[slot] == noone
		|| !is_real(sockets[slot])
		|| sockets[slot] < 0)
		{
			return -1;
		}

		net.start(N_CLIENT_PLAYER_STATE_ACK, noone);
		net.write(buffer_u8, CLIENT_MOVEMENT_PROTOCOL_VERSION);
		net.write(buffer_u16, position_broadcast_interval_ms);
		return net.send(sockets[slot], false, slot_transports[slot]);
	}

	/// @description Negotiate movement authority before forwarding the supported state to its player
	/// @param {Any} raw_slot Logical player-slot value, validated against the sockets array
	/// @param {Real} protocol_version Client protocol version
	/// @param {Real} x Room/world x coordinate in pixels
	/// @param {Real} y Room/world y coordinate in pixels
	/// @param {Real} client_direction Encoded facing direction
	/// @param {Real} client_is_moving Encoded movement flag
	/// @returns {Bool} Whether the supported protocol reached a connected player
	apply_client_player_state = function(raw_slot, protocol_version, x, y, client_direction, client_is_moving)
	{
		/* Normalize the sender logical slot before negotiating client-owned movement.
		The protocol check protects the following state-body interpretation */
		var slot = slot_from_value(raw_slot);

		/* Only an occupied slot using the supported movement protocol can proceed.
		Other packets return false before finding or changing its player */
		if (slot == noone
		|| protocol_version != CLIENT_MOVEMENT_PROTOCOL_VERSION
		|| sockets[slot] == noone)
		{
			return false;
		}

		/* Resolve the existing authoritative player without creating one from movement
		data. Its receive method owns how the provided pixel/visual state is applied */
		var player = player_controller_get_player(slot, false);

		/* Missing players or unsupported state receivers cannot apply this protocol.
		Return false rather than manufacturing roster state from movement */
		if (player == noone
		|| !variable_struct_exists(player, "receive_client_player_state"))
		{
			return false;
		}

		/* A first compatible state negotiates authority by sending an ack before
		setting ownership. Already-negotiated slots do not repeat that handshake */
		if (!client_movement_authority[slot])
		{
			/* ack_result must confirm a successful complete ack send before server-side
			client-authority state is enabled */
			var ack_result = send_client_movement_authority_ack(slot);

			/* A failed handshake reply leaves authority disabled and skips this state.
			The client cannot safely act on an agreement it did not receive */
			if (ack_result < 0)
			{
				return false;
			}
			client_movement_authority[slot] = true;
			debug_log("Client-owned movement enabled for " + scr_network_debug_server_slot_label(slot));
		}

		note_client_activity(slot);
		player.receive_client_player_state(x, y, client_direction, client_is_moving);
		return true;
	}

	/// @description Clear server tick samples/windows and every slot latency-reply cooldown
	/// @returns {Bool} True after reset
	reset_network_diagnostics = function()
	{
		movement_tick_last_ms = 0;
		movement_tick_average_ms = 0;
		movement_tick_recent_peak_ms = 0;
		movement_tick_sample_count = 0;
		movement_tick_peak_window_started = 0;
		movement_tick_previous_at = 0;
		movement_tick_rate_window_started = 0;
		movement_tick_rate_window_count = 0;
		movement_tick_rate_hz = 0;
		movement_tick_max_gap_ms = 0;
		movement_tick_gap_window_started = 0;
		latency_reply_next_at = array_create(net.max_clients, 0);
		return true;
	}

	/// @description Measure update work, five-second work/gap peaks and one-second loop frequency
	/// @param {Real} elapsed_ms Update-work duration in milliseconds
	/// @returns {Real} Nonnegative normalized work sample
	record_movement_tick = function(elapsed_ms)
	{
		/* sample is nonnegative server update-work milliseconds, and now captures the
		current_time clock for loop timing. The first sample seeds average directly,
		later samples blend 12 percent into the previous value */
		var sample = max(0, real(elapsed_ms));
		var now = current_time;
		movement_tick_last_ms = sample;
		movement_tick_sample_count++;
		movement_tick_average_ms = movement_tick_sample_count <= 1
			? sample
			: lerp(movement_tick_average_ms, sample, 0.12);

		/* Start a peak window when uninitialized or five seconds old. Otherwise retain
		the largest update-work sample inside the current window */
		if (movement_tick_peak_window_started <= 0
		|| current_time - movement_tick_peak_window_started >= 5000)
		{
			movement_tick_peak_window_started = current_time;
			movement_tick_recent_peak_ms = sample;
		}

		/* Within the active five-second peak window, keep the larger of the previous
		peak and current work duration */
		else
		{
			movement_tick_recent_peak_ms = max(movement_tick_recent_peak_ms, sample);
		}

		/* A previous loop timestamp is needed to measure its gap. The first sample
		establishes timing without comparing against inactive zero */
		if (movement_tick_previous_at > 0)
		{
			/* tick_gap is elapsed milliseconds between server loop samples.
			Its independent five-second window tracks scheduling gaps rather than work duration */
			var tick_gap = max(0, now - movement_tick_previous_at);

			/* An unset/expired gap window seeds its maximum from this gap.
			The alternative retains the largest gap within the active five-second window */
			if (movement_tick_gap_window_started <= 0
			|| now - movement_tick_gap_window_started >= 5000)
			{
				movement_tick_gap_window_started = now;
				movement_tick_max_gap_ms = tick_gap;
			}

			/* Keep the current gap-window maximum instead of replacing it with a smaller
			inter-sample delay */
			else
			{
				movement_tick_max_gap_ms = max(movement_tick_max_gap_ms, tick_gap);
			}
		}
		movement_tick_previous_at = now;

		/* The first rate sample starts its one-second observation window with count one.
		Later samples advance the existing count before calculating measured Hz */
		if (movement_tick_rate_window_started <= 0)
		{
			movement_tick_rate_window_started = now;
			movement_tick_rate_window_count = 1;
		}

		/* A rate window already exists, so count this loop and test whether at least
		one second elapsed before publishing the measured frequency */
		else
		{
			movement_tick_rate_window_count++;

			/* rate_elapsed is current_time milliseconds across the rate observation window.
			It converts the sample count to Hz and controls when the window restarts */
			var rate_elapsed = now - movement_tick_rate_window_started;

			/* Publish rate only after at least a full second. Earlier calls retain the
			previous Hz estimate while accumulating enough samples */
			if (rate_elapsed >= 1000)
			{
				movement_tick_rate_hz = movement_tick_rate_window_count * 1000 / max(1, rate_elapsed);
				movement_tick_rate_window_started = now;
				movement_tick_rate_window_count = 0;
			}
		}

		return sample;
	}

	/// @description Echo a probe with server diagnostics subject to per-slot cooldown
	/// @param {Any} raw_slot Logical probe sender
	/// @param {Real} sequence Client correlation ID to echo
	/// @returns {Real} Send result, zero during cooldown or -1 without a recipient
	send_latency_reply = function(raw_slot, sequence)
	{
		/* Normalize the probe sender before its per-slot response cooldown or socket
		can be accessed */
		var slot = slot_from_value(raw_slot);

		/* Only an occupied valid numeric socket can receive latency diagnostics.
		Invalid sender/session state returns -1 without advancing a cooldown */
		if (slot == noone
		|| sockets[slot] == noone
		|| !is_real(sockets[slot])
		|| sockets[slot] < 0)
		{
			return -1;
		}

		/* An active millisecond cooldown skips this reply with zero. Eligible attempts
		advance the deadline before sending, so transport failures also consume cooldown */
		if (current_time < latency_reply_next_at[slot])
		{
			return 0;
		}
		latency_reply_next_at[slot] = current_time + latency_reply_min_interval_ms;

		net.start(N_LATENCY_REPLY, noone);
		net.write(buffer_u32, sequence);
		net.write(buffer_f32, movement_tick_last_ms);
		net.write(buffer_f32, movement_tick_average_ms);
		net.write(buffer_f32, movement_tick_recent_peak_ms);
		net.write(buffer_f32, movement_tick_rate_hz);
		net.write(buffer_f32, movement_tick_max_gap_ms);
		net.write(buffer_f32, fps_real);
		net.write(buffer_u16, position_broadcast_interval_ms);
		net.write(buffer_string, scr_get_build_date(true, true));
		return net.send(sockets[slot], false, slot_transports[slot]);
	}

	/// @description Lazily allocate and rewind the server-owned movement-batch writer
	/// @returns {Id.Buffer} Borrowed reusable writer, released by shutdown
	get_position_buffer = function()
	{
		/* Create the server-owned movement writer only when absent/deleted.
		Existing buffers are rewound and reused rather than allocated per update */
		if (is_undefined(position_buffer)
		|| !buffer_exists(position_buffer))
		{
			position_buffer = buffer_create(512, buffer_grow, 1);
		}

		buffer_seek(position_buffer, buffer_seek_start, 0);
		return position_buffer;
	}

	/// @description Send dirty world positions and visual states in a slot-terminated batch
	/// @param {String} reason Failed-recipient cleanup cause, defaulting to sending movement batch
	/// @returns {Real} Recipient count, 0 for no dirty players, or -1 when a send fails
	broadcast_dirty_positions = function(reason = "sending movement batch")
	{
		/* Borrow the authoritative player roster for dirty-position batching.
		Its indexes must align with logical socket/dirty slots */
		var player_controller = scr_get_player_controller();

		/* No available roster array means no player positions to encode.
		Return zero before iterating dirty metadata */
		if (!is_struct(player_controller)
		|| !variable_struct_exists(player_controller, "players")
		|| !is_array(player_controller.players))
		{
			return 0;
		}

		/* players is the aligned authoritative roster. has_dirty starts false and
		becomes true only after an occupied, existing player is marked dirty */
		var players = player_controller.players;
		var has_dirty = false;

		/* Scan zero-based dirty slots until one live player needs delivery.
		No eligible match leaves the batch unnecessary */
		for (var i = 0; i < array_length(position_dirty); i++)
		{
			/* A pending flag must also have an in-range player and occupied socket.
			Only that complete combination justifies constructing a movement batch */
			if (position_dirty[i]
			&& i < array_length(players)
			&& players[i] != noone
			&& sockets[i] != noone)
			{
				has_dirty = true;
				break;
			}
		}

		/* No eligible dirty player means no state packet needs sending.
		Return zero without allocating/rewinding the batch buffer */
		if (!has_dirty)
		{
			return 0;
		}

		/* Borrow the reusable server-owned batch writer. Encode a server-sender header,
		then slot, signed pixel x/y, direction and strict moving byte for each dirty player.
		A noone slot terminates the body list */
		var packet_buffer = get_position_buffer();
		buffer_write(packet_buffer, buffer_u8, N_PLAYER_STATE_BATCH);
		buffer_write(packet_buffer, buffer_s16, noone);

		/* Visit zero-based dirty slots to append each eligible live player once.
		The following skip guard keeps stale/empty entries out of the batch */
		for (var slot = 0; slot < array_length(position_dirty); slot++)
		{
			/* Skip clean slots, missing/out-of-range players and empty connections.
			Every included entry therefore has aligned player position and visuals */
			if (!position_dirty[slot]
			|| slot >= array_length(players)
			|| players[slot] == noone
			|| sockets[slot] == noone)
			{
				continue;
			}

			buffer_write(packet_buffer, TYPE_ID, slot);
			buffer_write(packet_buffer, TYPE_POSITION, players[slot].pos.x);
			buffer_write(packet_buffer, TYPE_POSITION, players[slot].pos.y);
			buffer_write(packet_buffer, buffer_u8, players[slot].facing_direction);

			/* Encode moving as one and stationary as zero, matching the client visual flag
			wire format */
			buffer_write(packet_buffer, buffer_u8, players[slot].is_moving ? 1 : 0);
		}

		buffer_write(packet_buffer, TYPE_ID, noone);

		/* packet_size is completed batch body bytes. send_count starts zero and
		failed_slots starts empty, collecting failed logical recipients independently
		of player positions included in this batch */
		var packet_size = buffer_tell(packet_buffer);
		var send_count = 0;
		var failed_slots = [];

		/* Send the assembled batch to each occupied zero-based recipient slot.
		Every recipient observes all encoded dirty players, including its own relay */
		for (var target = 0; target < array_length(sockets); target++)
		{
			/* target_socket is the actual handle at this recipient logical slot.
			Its aligned transport determines raw WebSocket versus GameMaker framing */
			var target_socket = sockets[target];

			/* Unused slots are not recipients and do not count as failed sends */
			if (target_socket == noone)
			{
				continue;
			}

			/* An occupied invalid handle is a failed recipient. Record its logical slot
			and continue delivery to valid peers */
			if (!is_real(target_socket) || target_socket < 0)
			{
				failed_slots[array_length(failed_slots)] = target;
				continue;
			}

			/* send_result is assigned by the selected transport send operation.
			This direct batching path currently checks negative errors, not partial byte counts */
			var send_result;

			/* WebSocket receives binary body bytes directly. Native sockets use the framed
			GameMaker packet API in the alternative branch */
			if (slot_transports[target] == TRANSPORT_WS)
			{
				send_result = network_send_raw(target_socket, packet_buffer, packet_size, network_send_binary);
			}

			/* Native recipients need GameMaker packet framing rather than raw WebSocket
			body sends */
			else
			{
				send_result = network_send_packet(target_socket, packet_buffer, packet_size);
			}

			/* Record this failed recipient for cleanup after all sends. Continue so one
			broken route does not prevent delivery to remaining peers */
			if (send_result < 0)
			{
				failed_slots[array_length(failed_slots)] = target;
				continue;
			}

			send_count++;
		}

		/* Clear every dirty flag after the eligible batch attempt, even if recipients
		failed. Later position changes can mark slots dirty again */
		for (var dirty_index = 0; dirty_index < array_length(position_dirty); dirty_index++)
		{
			position_dirty[dirty_index] = false;
		}

		/* Close each recorded failed logical recipient after packet delivery finishes,
		so cleanup broadcasts do not overwrite the batch mid-send */
		for (var failed_index = 0; failed_index < array_length(failed_slots); failed_index++)
		{
			close_client_slot(failed_slots[failed_index], reason, true, true);
		}

		/* Any failed recipient returns -1 even when peers received the packet.
		A clean attempt returns its successful recipient count */
		return array_length(failed_slots) > 0 ? -1 : send_count;
	}

	/// @description Advance the millisecond movement schedule and attempt dirty-state delivery
	/// @returns {Real} Recipient count, zero when waiting/clean or -1 for eligible failures
	update_position_broadcast = function()
	{
		/* Wait for the movement deadline before another batch attempt. Due updates
		advance the deadline even when no dirty players currently need sending */
		if (current_time < next_position_broadcast)
		{
			return 0;
		}

		next_position_broadcast = current_time + position_broadcast_interval_ms;
		return broadcast_dirty_positions();
	}

	/// @description Serialize collision state for one occupied recipient
	/// @param {Any} raw_slot Logical recipient candidate
	/// @returns {Real} Send result or -1 without recipient/serializer
	send_collision_state_to_slot = function(raw_slot)
	{
		/* Normalize the collision-state recipient before looking up its actual socket */
		var slot = slot_from_value(raw_slot);

		/* Reject invalid/unoccupied collision recipients before packet construction */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return -1;
		}

		/* Borrow authoritative collision state and its wire serializer for this reply */
		var collision_objects = scr_get_collision_objects();

		/* Collision delivery requires its service and body writer. Missing support
		returns -1 without sending an incomplete state packet */
		if (!is_struct(collision_objects)
		|| !variable_struct_exists(collision_objects, "write_state_packet_body"))
		{
			return -1;
		}

		net.start(N_COLLISION_OBJECT_STATE, noone);
		collision_objects.write_state_packet_body();
		return net.send(sockets[slot], false, slot_transports[slot]);
	}

	/// @description Publish dirty/forced collision state, retaining dirty on failure
	/// @param {Bool} force Bypass dirty-state suppression, defaulting to false
	/// @returns {Real} Recipient count, zero when skipped or -1 for eligible failure
	broadcast_collision_state = function(force = false)
	{
		/* Borrow collision state for a scheduled or explicitly forced broadcast */
		var collision_objects = scr_get_collision_objects();

		/* Missing collision service/serializer means no supported state to broadcast.
		Return zero without building a partial packet */
		if (!is_struct(collision_objects)
		|| !variable_struct_exists(collision_objects, "write_state_packet_body"))
		{
			return 0;
		}

		/* Ordinary broadcasts require a present true dirty flag. Forced delivery
		bypasses the dirty requirement so startup/synchronization can send current state */
		if (!force
		&& (!variable_struct_exists(collision_objects, "server_state_dirty")
		|| !collision_objects.server_state_dirty))
		{
			return 0;
		}

		net.start(N_COLLISION_OBJECT_STATE, noone);
		collision_objects.write_state_packet_body();

		/* send_count records collision packet delivery and shared failed recipients.
		The dirty flag is cleared only after a clean broadcast with clear_dirty support */
		var send_count = net.send_all(sockets);

		/* Failure leaves collision dirty for a later attempt and cleans broken slots.
		Do not clear state merely because some recipients succeeded */
		if (send_count < 0)
		{
			debug_error("Failed to broadcast collision object state.");
			close_failed_send_slots("broadcasting collision object state");
		}

		/* After nonfailed delivery, clear dirty state when the service supports it.
		Without that optional method the existing flag remains as provided */
		else if (variable_struct_exists(collision_objects, "clear_dirty"))
		{
			collision_objects.clear_dirty();
		}

		return send_count;
	}

	/// @description Advance authoritative collision simulation and attempt a due dirty broadcast
	/// @returns {Real} Broadcast result or zero when services/schedule skip delivery
	update_collision_objects = function()
	{
		/* Borrow the roster passed into authoritative collision simulation */
		var player_controller = scr_get_player_controller();

		/* Collision simulation requires a present player array. Missing roster state
		skips simulation/broadcast instead of indexing invalid data */
		if (!is_struct(player_controller)
		|| !variable_struct_exists(player_controller, "players")
		|| !is_array(player_controller.players))
		{
			return 0;
		}

		/* Borrow the collision service whose update_server applies current player
		interaction before deciding whether a network broadcast is due */
		var collision_objects = scr_get_collision_objects();

		/* Without the collision simulation method, skip this subsystem safely.
		No incomplete collision state is broadcast */
		if (!is_struct(collision_objects)
		|| !variable_struct_exists(collision_objects, "update_server"))
		{
			return 0;
		}

		collision_objects.update_server(player_controller.players);

		/* Simulation has already advanced, but network delivery waits for its
		millisecond deadline. Due attempts advance scheduling even if no dirty state exists */
		if (current_time < next_collision_broadcast)
		{
			return 0;
		}

		next_collision_broadcast = current_time + collision_broadcast_interval_ms;
		return broadcast_collision_state();
	}
	#endregion /* Movement and Collision Synchronization END */

	#region /* Chat and Player Presence */
	/// @description Lazily allocate and rewind the server-owned chat writer
	/// @returns {Id.Buffer} Borrowed reusable writer released by shutdown
	get_chat_buffer = function()
	{
		/* Allocate the server-owned chat writer only when absent/deleted.
		Existing storage is rewound for each message and released at server shutdown */
		if (is_undefined(chat_buffer)
		|| !buffer_exists(chat_buffer))
		{
			chat_buffer = buffer_create(512, buffer_grow, 1);
		}

		buffer_seek(chat_buffer, buffer_seek_start, 0);
		return chat_buffer;
	}

	/// @description Write message identity/content/timestamp and send through the specified socket transport
	/// @param {Real} socket_to_reply Actual accepted destination handle
	/// @param {Real} socket_transport TRANSPORT value
	/// @param {Real} chat_type CHAT_TYPE value
	/// @param {Real} sender_id Logical speaker slot or noone
	/// @param {String} sender_name Approved display name
	/// @param {String} content Approved visible text
	/// @param {String} sent_at Display timestamp, defaulting to empty for local generation
	/// @returns {Real} Transport result or -1 for invalid handle
	send_chat_to_socket = function(socket_to_reply, socket_transport, chat_type, sender_id, sender_name, content, sent_at = "")
	{
		/* A nonnumeric/negative actual socket cannot receive chat. Return -1 before
		creating message bytes */
		if (!is_real(socket_to_reply) || socket_to_reply < 0)
		{
			return -1;
		}

		/* display_timestamp uses the caller calendar/display text after trimming.
		It is unrelated to current_time network scheduling, and empty input gets a local
		chat display timestamp */
		var display_timestamp = string_trim(string(sent_at));

		/* Generate visible timestamp text only when none was supplied, allowing a
		broadcast to reuse one common timestamp for every recipient */
		if (display_timestamp == "")
		{
			display_timestamp = chat_display_timestamp();
		}

		/* Borrow the reusable chat writer. Wire order is type and signed sender header,
		chat kind, repeated logical sender ID, visible sender name/content and timestamp */
		var packet_buffer = get_chat_buffer();
		buffer_write(packet_buffer, buffer_u8, N_MESSAGE);
		buffer_write(packet_buffer, buffer_s16, sender_id);
		buffer_write(packet_buffer, buffer_u8, chat_type);
		buffer_write(packet_buffer, TYPE_ID, sender_id);
		buffer_write(packet_buffer, buffer_string, string(sender_name));
		buffer_write(packet_buffer, buffer_string, string(content));
		buffer_write(packet_buffer, buffer_string, display_timestamp);

		/* packet_size measures the written chat bytes, and send_result is assigned by
		the selected raw/framed transport operation */
		var packet_size = buffer_tell(packet_buffer);
		var send_result;

		/* WebSocket chat sends binary body bytes directly. Other sockets require
		GameMaker packet framing */
		if (socket_transport == TRANSPORT_WS)
		{
			send_result = network_send_raw(socket_to_reply, packet_buffer, packet_size, network_send_binary);
		}

		/* Send framed chat to native transports, preserving their GameMaker protocol
		header requirements */
		else
		{
			send_result = network_send_packet(socket_to_reply, packet_buffer, packet_size);
		}

		/* Log a negative chat-send failure and return it. This direct send currently
		does not compare nonnegative results with expected full byte length */
		if (send_result < 0)
		{
			debug_error("Failed to send chat packet to socket " + string(socket_to_reply) + " over " + net.transport_to_string(socket_transport));
		}

		return send_result;
	}

	/// @description Resolve slot socket/transport and deliver one timestamped message
	/// @param {Real} slot Logical recipient
	/// @param {Real} chat_type CHAT_TYPE value
	/// @param {Real} sender_id Logical speaker slot or noone
	/// @param {String} sender_name Approved display name
	/// @param {String} content Approved visible text
	/// @param {String} sent_at Display timestamp, defaulting to empty for local generation
	/// @returns {Real} Send result or -1 without a recipient
	send_chat_to_slot = function(slot, chat_type, sender_id, sender_name, content, sent_at = "")
	{
		/* Chat delivery requires a valid occupied logical recipient. Resolve its
		actual socket and transport only after the slot check */
		if (!slot_is_valid(slot)
		|| sockets[slot] == noone)
		{
			return -1;
		}

		return send_chat_to_socket(sockets[slot], slot_transports[slot], chat_type, sender_id, sender_name, content, sent_at);
	}

	/// @description Record one authoritative export line, send one shared timestamp and close failed recipients
	/// @param {Real} chat_type CHAT_TYPE value
	/// @param {Real} sender_id Logical speaker slot or noone
	/// @param {String} sender_name Approved display name
	/// @param {String} content Approved visible text
	/// @param {Real} exception Logical recipient exclusion, defaulting to noone
	/// @returns {Real} Recipient count or -1 for an eligible failure
	broadcast_chat = function(chat_type, sender_id, sender_name, content, exception = noone)
	{
		record_chat_log(chat_type, sender_id, sender_name, content);

		/* Choose one display timestamp for this broadcast after recording its
		authoritative export line. Every recipient receives identical message timing */
		var sent_at = chat_display_timestamp();

		/* Count successful recipients from zero and collect failed logical slots in an
		empty list. Cleanup runs after delivery to avoid overwriting message buffers mid-send */
		var send_count = 0;
		var failed_slots = [];

		/* Visit every zero-based recipient slot, skipping excluded/empty entries.
		A failed peer does not prevent delivery to the remaining players */
		for (var i = 0; i < array_length(sockets); i++)
		{
			/* The excluded logical slot and unused sockets are not intended recipients.
			Skip them without counting a send failure */
			if (i == exception || sockets[i] == noone)
			{
				continue;
			}

			/* send_result belongs to this recipient, using the same broadcast timestamp.
			A negative result records its logical slot for later removal */
			var send_result = send_chat_to_slot(i, chat_type, sender_id, sender_name, content, sent_at);

			/* Record this failed recipient and continue other deliveries before cleanup */
			if (send_result < 0)
			{
				failed_slots[array_length(failed_slots)] = i;
				continue;
			}

			send_count++;
		}

		/* Close recorded failed slots after all message sends, preventing cleanup chat
		from replacing the writer during the original broadcast */
		for (var failed_index = 0; failed_index < array_length(failed_slots); failed_index++)
		{
			close_client_slot(failed_slots[failed_index], "sending chat message", true, true);
		}

		/* Report -1 if any eligible recipient failed, otherwise the successful count.
		A message with no eligible recipients returns zero */
		return array_length(failed_slots) > 0 ? -1 : send_count;
	}

	/// @description Send the removal explanation before player/socket cleanup
	/// @param {Any} raw_slot Logical recipient candidate
	/// @param {String} message Visible removal reason
	/// @returns {Real} Send result or -1 without recipient
	send_server_kick_to_slot = function(raw_slot, message)
	{
		/* Normalize the target logical player before sending a server removal reason */
		var slot = slot_from_value(raw_slot);

		/* An invalid or unoccupied slot has no kick recipient. Return -1 before a send */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return -1;
		}

		net.start(N_SERVER_KICK, slot);
		net.write(buffer_string, string(message));
		return net.send(sockets[slot], false, slot_transports[slot]);
	}

	/// @description Notify a valid occupied player and close its authoritative slot
	/// @param {Any} raw_slot Logical target candidate
	/// @param {String} server_reason Diagnostic cause, defaulting to empty for cleanup fallback
	/// @param {String} client_message Visible reason, defaulting to empty for generic kick feedback
	/// @param {Bool} broadcast_remove Whether to announce departure, defaulting to true
	/// @returns {Bool} Whether occupied slot state was removed
	kick_client_slot = function(raw_slot, server_reason = "", client_message = "", broadcast_remove = true)
	{
		/* Validate the logical kick target before notifying and closing its socket */
		var slot = slot_from_value(raw_slot);

		/* Reject invalid/empty kick targets instead of performing fictitious departure
		cleanup */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return false;
		}

		/* message is visible client removal feedback, distinct from server_reason used
		in departure diagnostics. Empty client text gets the generic kick message */
		var message = string(client_message);

		/* Use generic removal feedback when the caller supplied no client reason,
		keeping return-to-list behavior understandable */
		if (message == "")
		{
			message = "You were kicked from the server.";
		}

		send_server_kick_to_slot(slot, message);
		return close_client_slot(slot, server_reason, broadcast_remove, true);
	}

	/// @description Publish a logical subject typing flag/name and close failed recipients
	/// @param {Any} raw_slot Logical subject candidate
	/// @param {Bool} is_typing Desired indicator state
	/// @param {Real} exception Logical recipient exclusion, defaulting to noone
	/// @returns {Real} Recipient count or -1 for invalid subject/delivery failure
	broadcast_typing_state = function(raw_slot, is_typing, exception = noone)
	{
		/* Validate the logical typing subject before publishing its slot/name indicator */
		var slot = slot_from_value(raw_slot);

		/* An invalid subject cannot index typing/name state. Return failure without
		sending an indicator for another slot */
		if (slot == noone)
		{
			return -1;
		}

		/* The visible typing name starts from authoritative assigned username.
		An empty name uses the Player fallback */
		var username = slot_usernames[slot];

		/* Keep indicator text readable with Player when no visible username is present */
		if (username == "")
		{
			username = "Player";
		}

		net.start(N_TYPING_STATE, slot);

		/* Encode active typing as one and inactive as zero, with the logical subject in
		the packet header rather than its actual socket handle */
		net.write(buffer_u8, is_typing ? 1 : 0);
		net.write(buffer_string, username);

		/* send_count reports indicator recipients, excluding an optional logical slot.
		Negative delivery results retain shared failure metadata for connection cleanup */
		var send_count = net.send_all(sockets, exception);

		/* Close broken indicator recipients after failure diagnostics so stale
		connections do not remain in the authoritative roster */
		if (send_count < 0)
		{
			debug_error("Failed to broadcast typing state for slot " + string(slot));
			close_failed_send_slots("broadcasting typing state for slot " + string(slot));
		}

		/* Successful delivery logs ON/OFF text only through verbose logging.
		The conditional label follows the same is_typing state encoded in the packet */
		else
		{
			net.log_verbose("Broadcast typing " + (is_typing ? "ON" : "OFF") + " for slot " + string(slot) + " to " + string(send_count) + " client(s)");
		}

		return send_count;
	}

	/// @description Refresh active typing unless AFK, or clear an existing indicator
	/// @param {Any} raw_slot Logical sender candidate
	/// @param {Bool} is_typing Active report flag
	/// @returns {Bool} Whether the occupied indicator changed/refreshed
	set_client_typing = function(raw_slot, is_typing)
	{
		/* Normalize the typing sender before updating its occupied-slot indicator and
		current_time expiration deadline */
		var slot = slot_from_value(raw_slot);

		/* Only an occupied valid sender can change typing state. Ignore absent slots
		before reading AFK or indicator arrays */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return false;
		}

		/* An active report refreshes the typing deadline and broadcasts ON unless the
		player is AFK. A false report instead attempts to clear existing typing */
		if (is_typing)
		{
			/* AFK players cannot begin a typing indicator in this handler.
			Return false without changing their idle state or typing timeout */
			if (afk_active[slot])
			{
				return false;
			}

			typing_active[slot] = true;
			typing_deadlines[slot] = current_time + typing_timeout_ms;
			broadcast_typing_state(slot, true);
			return true;
		}

		/* An OFF report for an already inactive indicator has nothing to clear.
		Skip duplicate OFF broadcasts */
		if (!typing_active[slot])
		{
			return false;
		}

		typing_active[slot] = false;
		typing_deadlines[slot] = 0;
		broadcast_typing_state(slot, false);
		return true;
	}

	/// @description Clear an existing typing indicator with optional recipient exclusion
	/// @param {Any} raw_slot Logical subject candidate
	/// @param {Real} exception Logical recipient exclusion, defaulting to noone
	/// @returns {Bool} Whether an active indicator was cleared
	clear_client_typing = function(raw_slot, exception = noone)
	{
		/* Resolve the logical subject whose typing indicator should be removed */
		var slot = slot_from_value(raw_slot);

		/* Clear only a valid active indicator. Invalid or already inactive subjects
		return false without broadcasting redundant removal */
		if (slot == noone
		|| !typing_active[slot])
		{
			return false;
		}

		typing_active[slot] = false;
		typing_deadlines[slot] = 0;
		broadcast_typing_state(slot, false, exception);
		return true;
	}

	/// @description Clear typing indicators whose current_time timeout elapsed
	/// @returns {Real} Expired indicator count
	update_typing_states = function()
	{
		/* Count expired typing indicators cleared during this update, beginning zero */
		var cleared_count = 0;

		/* Inspect every zero-based typing slot. Only active indicators whose current_time
		deadline elapsed are cleared and counted */
		for (var slot = 0; slot < array_length(typing_active); slot++)
		{
			/* Inactive slots have no typing deadline to enforce, so skip their unused state */
			if (!typing_active[slot])
			{
				continue;
			}

			/* An active indicator still within its timeout remains visible.
			Only due deadlines reach the OFF broadcast below */
			if (current_time < typing_deadlines[slot])
			{
				continue;
			}

			typing_active[slot] = false;
			typing_deadlines[slot] = 0;
			broadcast_typing_state(slot, false);
			cleared_count++;
		}

		return cleared_count;
	}

	/// @description Send one logical subject AFK flag/name to a distinct recipient
	/// @param {Any} target_slot_raw Logical recipient candidate
	/// @param {Any} raw_slot Logical subject candidate
	/// @param {Bool} is_afk Desired idle indicator
	/// @returns {Real} Send result or -1 for invalid indexes/recipient
	send_afk_state_to_slot = function(target_slot_raw, raw_slot, is_afk)
	{
		/* Normalize target_slot as recipient and slot as the AFK subject. They may be
		different logical players and have separate roles in this synchronization packet */
		var target_slot = slot_from_value(target_slot_raw);
		var slot = slot_from_value(raw_slot);

		/* Both subject/recipient indexes must be valid and the recipient occupied.
		Otherwise no safe AFK update can be sent */
		if (target_slot == noone
		|| slot == noone
		|| sockets[target_slot] == noone)
		{
			return -1;
		}

		/* Use the AFK subject assigned name, with Player as fallback for missing text */
		var username = slot_usernames[slot];

		/* An empty subject name gets the readable Player fallback */
		if (username == "")
		{
			username = "Player";
		}

		net.start(N_AFK_STATE, slot);

		/* Encode idle as one and active as zero. The subject slot stays in the header,
		while the actual recipient socket comes from target_slot */
		net.write(buffer_u8, is_afk ? 1 : 0);
		net.write(buffer_string, username);
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Publish the subject idle flag/name and close failed recipients
	/// @param {Any} raw_slot Logical subject candidate
	/// @param {Bool} is_afk Desired idle indicator
	/// @param {Real} exception Logical recipient exclusion, defaulting to noone
	/// @returns {Real} Recipient count or -1 for invalid subject/delivery failure
	broadcast_afk_state = function(raw_slot, is_afk, exception = noone)
	{
		/* Normalize the AFK subject before broadcasting its aligned username/indicator */
		var slot = slot_from_value(raw_slot);

		/* An invalid logical subject cannot publish AFK state. Return failure before
		indexing metadata */
		if (slot == noone)
		{
			return -1;
		}

		/* Use the authoritative subject name, falling back to Player when empty */
		var username = slot_usernames[slot];

		/* Unnamed subjects still need readable AFK indicator text */
		if (username == "")
		{
			username = "Player";
		}

		net.start(N_AFK_STATE, slot);

		/* Idle state uses one and active state zero, matching the client indicator decoder */
		net.write(buffer_u8, is_afk ? 1 : 0);
		net.write(buffer_string, username);

		/* Capture AFK delivery count/failure after excluding the optional logical slot */
		var send_count = net.send_all(sockets, exception);

		/* Clean failed AFK recipients after logging, preventing broken connections from
		remaining in future broadcasts */
		if (send_count < 0)
		{
			debug_error("Failed to broadcast AFK state for slot " + string(slot));
			close_failed_send_slots("broadcasting AFK state for slot " + string(slot));
		}

		/* Successful delivery uses verbose ON/OFF feedback from is_afk, leaving normal
		logs quiet for routine indicator changes */
		else
		{
			net.log_verbose("Broadcast AFK " + (is_afk ? "ON" : "OFF") + " for slot " + string(slot) + " to " + string(send_count) + " client(s)");
		}

		return send_count;
	}

	/// @description Clear an active AFK indicator with optional recipient exclusion
	/// @param {Any} raw_slot Logical subject candidate
	/// @param {Real} exception Logical recipient exclusion, defaulting to noone
	/// @returns {Bool} Whether an active indicator was cleared
	clear_client_afk = function(raw_slot, exception = noone)
	{
		/* Normalize the logical player whose existing AFK indicator should clear */
		var slot = slot_from_value(raw_slot);

		/* Only a valid active AFK indicator needs removal. Others return false without
		a redundant active-state broadcast */
		if (slot == noone
		|| !afk_active[slot])
		{
			return false;
		}

		afk_active[slot] = false;
		broadcast_afk_state(slot, false, exception);
		return true;
	}

	/// @description Mark gameplay-idle players AFK, clear resumed indicators and kick long inactivity
	/// @returns {Real} Indicator-transition or actual kick count
	update_afk_states = function()
	{
		/* Count actual AFK transitions or occupied-slot kicks during this pass, starting zero */
		var changed_count = 0;

		/* Visit each zero-based occupied player slot. Gameplay idle timing is separate
		from heartbeat liveness, so a responsive client can still become AFK */
		for (var slot = 0; slot < array_length(sockets); slot++)
		{
			/* Unused slots have no gameplay inactivity to enforce */
			if (sockets[slot] == noone)
			{
				continue;
			}

			/* Seed an unset gameplay timestamp with current_time so a newly occupied slot
			gets the full idle interval rather than timing out from zero */
			if (afk_last_activity[slot] <= 0)
			{
				afk_last_activity[slot] = current_time;
			}

			/* idle_ms is elapsed gameplay inactivity on the current_time clock.
			Its longer kick threshold is checked before the shorter indicator threshold */
			var idle_ms = current_time - afk_last_activity[slot];

			/* A player idle for the full kick delay is notified/closed, then skipped so it
			cannot also receive a new AFK indicator in this update */
			if (idle_ms >= afk_kick_delay_ms)
			{
				/* Convert idle milliseconds to whole seconds for server diagnostics.
				kick_message carries the existing visible inactivity explanation */
				var idle_seconds = floor(idle_ms / 1000);
				var kick_message = "You were kicked for inactivity.";

				/* Count inactivity removal only if the occupied slot was actually closed */
				if (kick_client_slot(slot, "AFK timeout after " + string(idle_seconds) + "s", kick_message))
				{
					changed_count++;
				}
				continue;
			}

			/* Once the shorter idle delay passes, an inactive AFK indicator transitions ON.
			An already idle-marked player does not repeat the announcement */
			if (idle_ms >= afk_indicator_delay_ms)
			{
				/* Only the first transition to AFK clears typing, publishes idle and increments
				changed_count, avoiding repeated indicator traffic */
				if (!afk_active[slot])
				{
					/* Clear any active typing indicator before marking the same player AFK, keeping
					chat status from displaying both states at once */
					if (typing_active[slot])
					{
						clear_client_typing(slot);
					}

					afk_active[slot] = true;
					broadcast_afk_state(slot, true);
					changed_count++;
				}
			}

			/* Activity within the indicator delay clears a previously active AFK flag and
			broadcasts return. Already-active players need no transition packet */
			else if (afk_active[slot])
			{
				afk_active[slot] = false;
				broadcast_afk_state(slot, false);
				changed_count++;
			}
		}

		return changed_count;
	}

	/// @description Sanitize occupied-player chat, apply gameplay activity and interpret supported slash speech
	/// @param {Real} sender_slot Socket-derived logical speaker slot
	/// @param {String} raw_input Submitted chat text
	/// @returns {Bool} Whether nonempty normal chat or supported speech was broadcast
	handle_chat_input = function(sender_slot, raw_input)
	{
		/* Chat needs a valid occupied logical sender so assigned identity is server-
		owned. Reject malformed/empty sender state before sanitizing its text */
		if (!slot_is_valid(sender_slot)
		|| sockets[sender_slot] == noone)
		{
			debug_error("Ignoring chat from invalid slot " + string(sender_slot));
			return false;
		}

		/* text is sanitized submitted content, not trusted packet text. Empty results
		carry no message or command and do not refresh gameplay activity */
		var text = chat_sanitize_message(raw_input);

		/* Ignore an empty sanitized submission rather than broadcasting a blank line */
		if (text == "")
		{
			return false;
		}

		note_client_gameplay_activity(sender_slot);
		clear_client_typing(sender_slot);

		/* Use the assigned authoritative name for visible speech, falling back to
		Player instead of trusting a name supplied with the chat content */
		var sender_name = slot_usernames[sender_slot];

		/* Give an unnamed accepted sender the readable Player label */
		if (sender_name == "")
		{
			sender_name = "Player";
		}

		/* Leading slash selects command interpretation. Only a supported nonempty /say
		body broadcasts speech, while unknown or empty commands receive private error text */
		if (chat_text_starts_with(text, "/"))
		{
			/* Normalize command detection only. The original sanitized text remains the
			source of /say content, preserving player text case */
			var lower_text = string_lower(text);

			/* Recognize /say plus a space, extracting only its body for another sanitization.
			Other slash commands fall through to Unknown command feedback */
			if (chat_text_starts_with(lower_text, "/say "))
			{
				/* say_content is the sanitized text after /say, excluding its prefix.
				It must retain content before command speech is broadcast */
				var say_content = chat_sanitize_message(string_copy(text, 6, string_length(text) - 5));

				/* Only a nonempty speech body broadcasts CHAT_TYPE_SAY and succeeds.
				An empty body falls through to the existing unknown-command feedback */
				if (say_content != "")
				{
					broadcast_chat(CHAT_TYPE_SAY, sender_slot, sender_name, say_content);
					return true;
				}
			}

			send_chat_to_slot(sender_slot, CHAT_TYPE_ERROR, noone, "", "Unknown command.");
			record_chat_log(CHAT_TYPE_ERROR, noone, "", "Unknown command.");
			return false;
		}

		broadcast_chat(CHAT_TYPE_PLAYER, sender_slot, sender_name, text);
		return true;
	}
	#endregion /* Chat and Player Presence END */

	#region /* Unjoined Connections and Status Probes */
	/// @description Send join denial then destroy the valid accepted child regardless of notification result
	/// @param {Real} socket_to_reject Actual child handle
	/// @param {Real} socket_transport Transport, defaulting to TCP
	/// @param {String} rejection_message Feedback, defaulting to Server is full.
	/// @returns {Bool} Whether a valid handle was processed
	reject_full_connection = function(socket_to_reject, socket_transport = TRANSPORT_TCP, rejection_message = "Server is full.")
	{
		/* Rejecting a full server still needs a valid accepted handle. Invalid values
		return false before writing or destroying sockets */
		if (!is_real(socket_to_reject)
		|| socket_to_reject < 0)
		{
			debug_error("Tried to reject full-server connection with invalid socket: " + string(socket_to_reject));
			return false;
		}

		/* clean_message is visible join-denial feedback after trimming, with the
		full-server fallback used when caller text is empty */
		var clean_message = string_trim(string(rejection_message));

		/* A missing rejection reason uses the existing full-server message so the
		client is not removed without visible feedback */
		if (clean_message == "")
		{
			clean_message = "Server is full.";
		}

		net.start(N_SERVER_FULL, noone);
		net.write(buffer_string, clean_message);

		/* Attempt to deliver denial using the accepted connection transport.
		The socket is closed afterwards even when notification delivery fails */
		var send_result = net.send(socket_to_reject, true, socket_transport);

		/* Log failed denial delivery, then still release this rejected connection.
		Failure to notify cannot admit a player beyond capacity */
		if (send_result < 0)
		{
			debug_error("Failed to send N_SERVER_FULL to socket " + string(socket_to_reject));
		}

		destroy_client_socket(socket_to_reject);
		debug_error("Rejected " + net.transport_to_string(socket_transport) + " connection on socket " + string(socket_to_reject) + ": " + clean_message);
		return true;
	}

	/// @description Remove aligned status tracking and optionally destroy the accepted handle
	/// @param {Real} socket_value Actual status handle
	/// @param {Bool} destroy_socket Whether to release the handle, defaulting to false
	remove_status_socket = function(socket_value, destroy_socket = false)
	{
		/* Scan status handles backward to remove matching entries and aligned deadlines
		without skipping shifted indexes */
		for (var i = array_length(status_sockets) - 1; i >= 0; i--)
		{
			/* Remove this handle/deadline pair only when it matches the target socket.
			Other status connections retain their timeout metadata */
			if (status_sockets[i] == socket_value)
			{
				array_delete(status_sockets, i, 1);
				array_delete(status_socket_deadlines, i, 1);
			}
		}

		/* Destroy the accepted socket only when requested and numerically valid.
		Otherwise this function removes tracking without claiming resource destruction */
		if (destroy_socket && is_real(socket_value) && socket_value >= 0)
		{
			destroy_client_socket(socket_value);
		}
	}

	/// @description Release status-only handles whose current_time grace deadline elapsed
	cleanup_status_sockets = function()
	{
		/* Walk status-only handles backward so expiry removal keeps aligned array
		indexes safe for unvisited entries */
		for (var i = array_length(status_sockets) - 1; i >= 0; i--)
		{
			/* Close a status-only connection once its current_time deadline expires.
			Connections still within their wait remain tracked */
			if (current_time >= status_socket_deadlines[i])
			{
				remove_status_socket(status_sockets[i], true);
			}
		}
	}

	/// @description Send signed gameplay counts and branded server name to a listing connection
	/// @param {Real} socket_to_reply Actual listing handle
	/// @param {Real} socket_transport Transport, defaulting to WebSocket
	/// @returns {Real} Send result or -1 for invalid handle
	send_status_response = function(socket_to_reply, socket_transport = TRANSPORT_WS)
	{
		/* A failed/missing actual socket cannot receive listing status.
		Return -1 before writing server count/name fields */
		if (!is_real(socket_to_reply) || socket_to_reply < 0)
		{
			return -1;
		}

		net.start(N_SERVER_STATUS, noone);
		net.write(buffer_s16, connected_players);
		net.write(buffer_s16, max_players);
		net.write(buffer_string, net.official_server_name);

		/* send_result reports the complete status send through the selected transport.
		This response uses current gameplay count/capacity and branded official name */
		var send_result = net.send(socket_to_reply, true, socket_transport);

		/* Report status send failure while returning it to the caller for connection
		cleanup. Successful sends skip the error log */
		if (send_result < 0)
		{
			debug_error("Failed to send server status to socket " + string(socket_to_reply));
		}

		return send_result;
	}

	/// @description Check actual-handle ownership in the status-only collection
	/// @param {Real} socket_value Actual handle
	/// @returns {Bool} Whether a status record matches
	is_status_client_socket = function(socket_value)
	{
		/* Search zero-based status-only actual handles. A match establishes temporary
		connection ownership, while exhausting the list returns false */
		for (var i = 0; i < array_length(status_sockets); i++)
		{
			/* Return true only for a recorded status handle rather than a player slot ID */
			if (status_sockets[i] == socket_value)
			{
				return true;
			}
		}

		return false;
	}

	/// @description Remove aligned first-packet tracking and optionally destroy its accepted handle
	/// @param {Real} socket_value Actual pending handle
	/// @param {Bool} destroy_socket Whether to release the handle, defaulting to false
	remove_pending_ws_socket = function(socket_value, destroy_socket = false)
	{
		/* Remove pending handle/transport/deadline triples backward so deletion cannot
		misalign remaining first-packet waits */
		for (var i = array_length(pending_ws_sockets) - 1; i >= 0; i--)
		{
			/* Delete all matching pending entries with their aligned metadata.
			Other WebSocket connections keep their transport and deadline */
			if (pending_ws_sockets[i] == socket_value)
			{
				array_delete(pending_ws_sockets, i, 1);
				array_delete(pending_ws_transports, i, 1);
				array_delete(pending_ws_deadlines, i, 1);
			}
		}

		/* Release the accepted handle only when the caller requests destruction and
		it is valid. Promotion to gameplay/status can remove tracking without destruction */
		if (destroy_socket && is_real(socket_value) && socket_value >= 0)
		{
			destroy_client_socket(socket_value);
		}
	}

	/// @description Check actual-handle ownership awaiting an identifying first packet
	/// @param {Real} socket_value Actual accepted handle
	/// @returns {Bool} Whether pending tracking matches
	is_pending_ws_socket = function(socket_value)
	{
		/* Search zero-based pending actual socket handles until a match or list end.
		This collection has not yet assigned gameplay player slots */
		for (var i = 0; i < array_length(pending_ws_sockets); i++)
		{
			/* A recorded pending handle belongs to the server first-packet wait.
			Return true before testing other temporary connections */
			if (pending_ws_sockets[i] == socket_value)
			{
				return true;
			}
		}

		return false;
	}

	/// @description Resolve the recorded transport before a gameplay slot exists
	/// @param {Real} socket_value Actual pending handle
	/// @param {Real} fallback Unmatched transport, defaulting to TCP
	/// @returns {Real} Recorded transport or fallback
	get_pending_ws_transport = function(socket_value, fallback = TRANSPORT_TCP)
	{
		/* Resolve the actual pending handle through its zero-based tracking entry.
		A missing handle returns the caller transport fallback */
		for (var i = 0; i < array_length(pending_ws_sockets); i++)
		{
			/* The matching pending index selects its aligned transport, preserving its
			accepted listener route before any gameplay slot is assigned */
			if (pending_ws_sockets[i] == socket_value)
			{
				return pending_ws_transports[i];
			}
		}

		return fallback;
	}

	/// @description Register a valid child handle and its first-packet deadline without duplicate tracking
	/// @param {Real} socket_value Actual accepted child
	/// @param {Real} socket_transport Transport, defaulting to WebSocket
	/// @returns {Bool} Whether pending registration accepted the handle
	add_pending_ws_socket = function(socket_value, socket_transport = TRANSPORT_WS)
	{
		/* Only valid accepted handles enter first-packet tracking.
		Invalid values return false without allocating an aligned pending record */
		if (!is_real(socket_value) || socket_value < 0)
		{
			return false;
		}

		/* Never track a server listener as a pending client. Whole-server resources
		must not later be destroyed by first-packet timeout cleanup */
		if (socket_value == server
		|| socket_value == websocket_server
		|| socket_value == discovery_socket)
		{
			debug_error("Refusing to track listener socket " + string(socket_value) + " as a pending client.");
			return false;
		}

		/* An existing pending handle only refreshes transport registration.
		Do not append another triple or restart its original first-packet deadline */
		if (is_pending_ws_socket(socket_value))
		{
			net.register_socket_transport(socket_value, socket_transport);
			return true;
		}

		net.register_socket_transport(socket_value, socket_transport);

		/* Append one aligned handle/transport/current_time deadline record.
		The timeout uses connect_timeout_ms and awaits a first join or status packet */
		pending_ws_sockets[array_length(pending_ws_sockets)] = socket_value;
		pending_ws_transports[array_length(pending_ws_transports)] = socket_transport;
		pending_ws_deadlines[array_length(pending_ws_deadlines)] = current_time + net.connect_timeout_ms;
		return true;
	}

	/// @description Close first-packet waits whose current_time deadline elapsed
	cleanup_pending_ws_sockets = function()
	{
		/* Check pending first-packet waits backward so timed-out triple removal cannot
		skip another unvisited socket */
		for (var i = array_length(pending_ws_sockets) - 1; i >= 0; i--)
		{
			/* No identifying packet arrived before this handle deadline. Remove/destroy
			the pending connection instead of reserving resources indefinitely */
			if (current_time >= pending_ws_deadlines[i])
			{
				remove_pending_ws_socket(pending_ws_sockets[i], true);
			}
		}
	}
	#endregion /* Unjoined Connections and Status Probes END */

	#region /* Character Manifests and Chunk Transfers */
	/// @description Publish the occupied owner manifest and close failed recipients
	/// @param {Any} raw_slot Logical character owner
	/// @returns {Real} Recipient count or -1 for invalid owner/delivery failure
	broadcast_player_character = function(raw_slot)
	{
		/* Normalize the character subject before reading its occupied player metadata */
		var slot = slot_from_value(raw_slot);

		/* An invalid or empty character-owner slot cannot publish a roster appearance.
		Return -1 without indexing its manifest/name arrays */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return -1;
		}

		net.start(N_PLAYER_CHARACTER, slot);
		net.write(TYPE_ID, slot);
		scr_get_player_characters().write_manifest(net, character_manifest_for_slot(slot));

		/* send_count captures delivery of this logical owner manifest across occupied
		players, with shared failed recipients available for cleanup */
		var send_count = net.send_all(sockets);

		/* Close failed recipients after publishing the character update so broken
		routes do not remain registered */
		if (send_count < 0)
		{
			debug_error("Failed to broadcast character for slot " + string(slot));
			close_failed_send_slots("broadcasting character for slot " + string(slot));
		}

		/* A successful broadcast records the character identity through verbose logs,
		without duplicating normal high-frequency packet messages */
		else
		{
			net.log_verbose("Broadcast character " + slot_character_keys[slot] + " for " + scr_network_debug_server_slot_label(slot));
		}

		return send_count;
	}

	/// @description Check whether an occupied owner still uses a shared image as its character or pet
	/// @param {Real} slot Logical owner slot
	/// @param {String} key Shared image identity
	/// @returns {Bool} Whether either appearance still needs this image
	slot_uses_asset_key = function(slot, key)
	{
		/* Only occupied owners retain assets. Empty pet keys cannot own a payload */
		return slot_is_valid(slot) && sockets[slot] != noone && key != ""
			&& (slot_character_keys[slot] == key || slot_pet_keys[slot] == key);
	}

	/// @description Send one independent pet state to a connected recipient
	/// @param {Real} owner_slot Logical pet owner
	/// @param {Real} target_slot Logical recipient
	/// @returns {Real} Transport result or -1 for an unavailable slot
	send_player_pet_to_slot = function(owner_slot, target_slot)
	{
		/* Both slots must belong to live connections before accessing aligned pet
		arrays or sending a removal/equip update */
		if (!slot_is_valid(owner_slot) || !slot_is_valid(target_slot)
		|| sockets[owner_slot] == noone || sockets[target_slot] == noone) return -1;

		/* A nonempty key identifies one equipped pet. Removal has only its zero flag */
		var equipped = slot_pet_keys[owner_slot] != "";
		net.start(N_PLAYER_PET, owner_slot);
		net.write(buffer_u8, equipped ? 1 : 0);
		if (equipped) scr_get_player_characters().write_manifest(net, slot_pet_manifests[owner_slot]);
		return net.send(sockets[target_slot], false, slot_transports[target_slot]);
	}

	/// @description Publish one authoritative pet selection to all occupied recipients
	/// @param {Real} slot Logical pet owner
	/// @returns {Real} Recipient count or -1 on delivery failure
	broadcast_player_pet = function(slot)
	{
		/* Pet metadata uses its own packet so character and roster layouts stay
		unchanged. Missing owners cannot publish a pet state */
		if (!slot_is_valid(slot) || sockets[slot] == noone) return -1;
		var equipped = slot_pet_keys[slot] != "";
		net.start(N_PLAYER_PET, slot);
		net.write(buffer_u8, equipped ? 1 : 0);
		if (equipped) scr_get_player_characters().write_manifest(net, slot_pet_manifests[slot]);
		var send_count = net.send_all(sockets);

		/* Failed routes use the established slot cleanup after the broadcast finishes */
		if (send_count < 0) close_failed_send_slots("broadcasting pet for slot " + string(slot));
		return send_count;
	}

	/// @description Drop outgoing shared-image jobs that this owner no longer uses in either role
	/// @param {Real} slot Logical image owner
	clear_unused_asset_jobs = function(slot)
	{
		/* Work backward so deleting an obsolete appearance cannot skip another job.
		Character and pet transfers that still match either role keep their progress */
		for (var i = array_length(character_send_jobs) - 1; i >= 0; i--)
		{
			var job = character_send_jobs[i];
			if (job.owner_slot == slot && !slot_uses_asset_key(slot, job.manifest.network_key))
			{
				array_delete(character_send_jobs, i, 1);
			}
		}
	}

	/// @description Start a fresh five-second upload window when due while retaining approved pet reservations
	/// @param {Real} slot Occupied logical uploader
	refresh_asset_upload_window = function(slot)
	{
		/* A delayed acknowledgement can outlast one window. Its pet reservation
		remains protected while received-byte accounting starts fresh */
		if (asset_upload_window_started[slot] <= 0
		|| current_time - asset_upload_window_started[slot] >= asset_upload_window_ms)
		{
			asset_upload_window_started[slot] = current_time;
			asset_upload_window_bytes[slot] = 0;
		}
	}

	/// @description Validate and publish a cosmetic pet independently from its owner's character
	/// @param {Real} raw_slot Socket-derived logical owner
	/// @param {Struct|Real} manifest Shared image metadata, or noone for no pet
	/// @returns {Bool} Whether the server accepted this pet selection
	set_client_pet = function(raw_slot, manifest)
	{
		/* Resolve sender ownership from the accepted socket. A packet header cannot
		change another player's pet or manufacture an unconnected owner */
		var slot = slot_from_value(raw_slot);
		if (slot == noone || sockets[slot] == noone) return false;
		var registry = scr_get_player_characters();

		/* Changing pets has a short per-owner cooldown. Rejected requests receive
		the retained state so an optimistic local card returns to the approved pet */
		if (current_time < pet_change_next_at[slot])
		{
			send_player_pet_to_slot(slot, slot);
			return false;
		}
		pet_change_next_at[slot] = current_time + pet_change_min_interval_ms;

		/* Shared custom sheets retain the existing byte/chunk caps and exact count.
		Bundled sheets must resolve to a real official identity without uploaded bytes */
		if (manifest != noone)
		{
			var valid = registry.manifest_is_valid_shape(manifest);
			if (valid && manifest.custom)
			{
				valid = manifest.byte_size > 0 && manifest.byte_size <= registry.character_max_bytes
					&& manifest.chunk_count > 0 && manifest.chunk_count <= registry.character_max_chunks
					&& manifest.chunk_count == ceil(ceil(manifest.byte_size / 3) * 4 / registry.character_chunk_size)
					&& registry.is_network_custom_key(manifest.network_key);
			}
			else if (valid)
			{
				valid = registry.official_manifest(manifest.network_key).network_key == manifest.network_key
					&& manifest.byte_size == 0 && manifest.chunk_count == 0;
			}

			/* Invalid metadata leaves both pet and character state unchanged and replies
			with the current pet before any image assembly can begin */
			if (!valid)
			{
				send_player_pet_to_slot(slot, slot);
				return false;
			}
		}

		/* Known bytes can be equipped immediately and permission-only edits keep
		the active upload. A new uncached sheet must fit before publishing its metadata,
		so a rejected selection can retry after the existing upload window expires */
		var reserved_key = "";
		var reserved_bytes = 0;
		if (is_struct(manifest) && manifest.custom)
		{
			var cached_payload = cached_character_manifest(manifest.network_key);
			var payload_cached = is_struct(cached_payload)
				&& cached_payload.byte_size == manifest.byte_size
				&& cached_payload.chunk_count == manifest.chunk_count;
			if (!payload_cached)
			{
				reserved_key = manifest.network_key;
				reserved_bytes = asset_upload_reserved_keys[slot] == reserved_key
					? asset_upload_reserved_bytes[slot]
					: ceil(manifest.byte_size / 3) * 4;
				refresh_asset_upload_window(slot);

				/* Replacing an obsolete pet reservation frees its future bytes. Existing
				received bytes still count, and the retained pet is acknowledged on refusal */
				var upload_limit = 4 * ceil(registry.character_max_bytes / 3) * 4;
				if (asset_upload_window_bytes[slot] + reserved_bytes > upload_limit)
				{
					send_player_pet_to_slot(slot, slot);
					return false;
				}
			}
		}
		asset_upload_reserved_keys[slot] = reserved_key;
		asset_upload_reserved_bytes[slot] = reserved_bytes;

		/* Empty keys represent no pet. Retain metadata only for an equipped image,
		then release jobs, pending assemblies and cached bytes unused by either role */
		slot_pet_keys[slot] = manifest == noone ? "" : manifest.network_key;
		slot_pet_manifests[slot] = manifest;
		if (manifest != noone) registry.remember_manifest(manifest);
		clear_unused_asset_jobs(slot);
		clear_pending_character_uploads(slot, slot_character_keys[slot]);
		prune_character_cache();
		scr_get_pets().receive_player_pet(slot, manifest);
		broadcast_player_pet(slot);
		if (manifest != noone && manifest.custom) broadcast_cached_character(slot, true);
		return true;
	}

	/// @description Return stored appearance metadata or resolve its key without embedded PNG bytes
	/// @param {Any} raw_slot Logical owner candidate
	/// @returns {Struct} Character manifest, with player1 fallback for invalid slot
	character_manifest_for_slot = function(raw_slot)
	{
		/* Validate the requested logical appearance owner. Its stored manifest takes
		priority over reconstructing a manifest from the saved key */
		var slot = slot_from_value(raw_slot);

		/* Invalid slots use the built-in player1 manifest rather than indexing another
		player character entry */
		if (slot == noone)
		{
			return scr_get_player_characters().official_manifest("player1");
		}

		/* Return the stored appearance metadata when present. Otherwise resolve the
		slot character key without embedding Base64 PNG payload */
		if (is_struct(slot_character_manifests[slot]))
		{
			return slot_character_manifests[slot];
		}

		return scr_get_player_characters().manifest_for_key(slot_character_keys[slot], false);
	}

	/// @description Locate a sanitized appearance key in the parallel payload cache
	/// @param {String} raw_key Appearance identity
	/// @returns {Real} Cache index or noone
	character_cache_index = function(raw_key)
	{
		/* Normalize the requested appearance identity before looking up cached payloads */
		var key_text = scr_get_player_characters().sanitize_key(raw_key);

		/* Scan zero-based cache keys until one matches. The same index identifies its
		manifest in the parallel payload array, and no match returns noone */
		for (var cache_index = 0; cache_index < array_length(character_cache_keys); cache_index++)
		{
			/* Return the cache index for this exact normalized character identity */
			if (character_cache_keys[cache_index] == key_text)
			{
				return cache_index;
			}
		}

		return noone;
	}

	/// @description Store valid completed custom Base64 bytes, replacing an existing key pair
	/// @param {Struct} manifest Completed custom manifest including payload
	/// @returns {Bool} Whether the manifest was cacheable
	cache_character_payload = function(manifest)
	{
		/* Cache only valid custom manifests containing nonempty encoded payload text.
		Built-in or incomplete appearances need no custom transfer cache entry */
		if (!scr_get_player_characters().manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| string_trim(manifest.base64) == "")
		{
			return false;
		}

		/* Find the existing payload entry so a completed upload can replace it in place.
		A missing key instead uses the next append index */
		var cache_index = character_cache_index(manifest.network_key);

		/* Append a new key/manifest pair only when this identity is not already cached.
		Existing identities replace their aligned payload rather than duplicating it */
		if (cache_index == noone)
		{
			cache_index = array_length(character_cache_keys);
		}

		character_cache_keys[cache_index] = manifest.network_key;
		character_cache_manifests[cache_index] = manifest;
		return true;
	}

	/// @description Retrieve a completed payload by sanitized appearance identity
	/// @param {String} raw_key Appearance identity
	/// @returns {Struct} Cached manifest or noone
	cached_character_manifest = function(raw_key)
	{
		/* Resolve the sanitized key to a shared key/manifest index before retrieving payload */
		var cache_index = character_cache_index(raw_key);

		/* An uncached character has no completed custom payload to send.
		Return noone without indexed manifest access */
		if (cache_index == noone)
		{
			return noone;
		}

		return character_cache_manifests[cache_index];
	}

	/// @description Remove old character assemblies for one owner while optionally retaining its current key
	/// @param {Real} slot Logical owner
	/// @param {String} keep_key Retained key, defaulting to empty for ordinary removal
	clear_pending_character_uploads = function(slot, keep_key = "")
	{
		/* Borrow receive state to discard old uploads for this logical owner. A
		retained character key also preserves its pet upload during appearance changes */
		var registry = scr_get_player_characters();
		var keep_pet_key = keep_key != "" && slot_is_valid(slot) ? slot_pet_keys[slot] : "";

		/* Inspect pending receive entries backward so removing old owner uploads cannot
		skip later shifted records */
		for (var i = array_length(registry.pending_character_receives) - 1; i >= 0; i--)
		{
			/* pending is one character assembly identified by owner slot and network key */
			var pending = registry.pending_character_receives[i];

			/* Remove only this owner uploads whose key is not explicitly retained.
			Other owners and the retained current key continue receiving */
			if (pending.owner_id == slot && pending.network_key != keep_key
			&& pending.network_key != keep_pet_key)
			{
				array_delete(registry.pending_character_receives, i, 1);
			}
		}
	}

	/// @description Release completed payload copies unused by any occupied owner in server and registry caches
	prune_character_cache = function()
	{
		/* Prune completed cache entries backward, retaining identities still used by
		an occupied player slot and keeping key/manifest arrays aligned */
		for (var cache_index = array_length(character_cache_keys) - 1; cache_index >= 0; cache_index--)
		{
			/* Assume this cached key is unused until an occupied slot proves otherwise */
			var active = false;

			/* Check every zero-based occupied slot for this cached appearance key.
			Stop after one active owner is enough to retain the payload */
			for (var slot = 0; slot < array_length(sockets); slot++)
			{
				/* An occupied player using this key keeps its custom payload cached.
				Empty slots cannot retain an appearance merely through their default key */
				if (slot_uses_asset_key(slot, character_cache_keys[cache_index]))
				{
					active = true;
					break;
				}
			}

			/* Delete both cache arrays at this unused index. Active payloads remain available
			for joining players and repeat appearance delivery */
			if (!active)
			{
				array_delete(character_cache_keys, cache_index, 1);
				array_delete(character_cache_manifests, cache_index, 1);
			}
		}

		/* Borrow the registry completed remote-manifest cache as well, since clearing
		only the server parallel cache would leave inactive encoded payload copies */
		var registry = scr_get_player_characters();

		/* Scan registry manifests backward to release payloads unused by any occupied
		slot, preserving safe indexes during deletion */
		for (var i = array_length(registry.remote_manifests) - 1; i >= 0; i--)
		{
			/* key identifies this registry payload. active begins false for its own
			occupied-slot scan rather than inheriting the previous cache entry result */
			var key = registry.remote_manifests[i].network_key;
			var active = false;

			/* Find any occupied slot using this registry key. One match retains it and
			ends the ownership scan */
			for (var slot = 0; slot < array_length(sockets); slot++)
			{
				/* A current occupied owner still needs this registry payload.
				Mark active and stop inspecting unrelated player slots */
				if (slot_uses_asset_key(slot, key))
				{
					active = true;
					break;
				}
			}

			/* Release the unused registry manifest and its recorded remote failure state.
			Active owners retain both their payload identity and current status */
			if (!active)
			{
				array_delete(registry.remote_manifests, i, 1);
				registry.clear_remote_failure(key);
			}
		}
	}

	/// @description Remove queued transfers owned by or targeting a logical slot
	/// @param {Real} slot Logical owner/recipient
	/// @param {Bool} owner_only Preserve incoming jobs when true, defaulting to false
	clear_character_jobs_for_slot = function(slot, owner_only = false)
	{
		/* Remove character jobs backward for this logical slot. owner_only limits
		cleanup to outgoing ownership, otherwise recipient-side jobs are removed too */
		for (var i = array_length(character_send_jobs) - 1; i >= 0; i--)
		{
			/* job identifies both logical owner and recipient plus their bound sockets */
			var job = character_send_jobs[i];

			/* Always remove this owner old transfers. Remove jobs targeting the slot only
			when owner_only is false, preserving incoming appearances during owner-only changes */
			if (job.owner_slot == slot || (!owner_only && job.target_slot == slot))
			{
				array_delete(character_send_jobs, i, 1);
			}
		}
	}

	/// @description Replace an owner/recipient/image job and bind it to both current sockets
	/// @param {Real} owner_slot Connected character owner slot
	/// @param {Real} target_slot Connected recipient slot
	/// @param {Struct} manifest Validated custom character manifest including its base64 payload
	/// @returns {Real} 1 when queued, or 0 for an invalid payload
	queue_character_send = function(owner_slot, target_slot, manifest)
	{
		/* Borrow the character registry to validate encoded custom payload bounds
		before queuing a sender/recipient transfer */
		var registry = scr_get_player_characters();

		/* A job needs a valid custom nonempty payload with positive bounded byte/chunk
		counts. Invalid manifests return zero before binding current socket identities */
		if (!registry.manifest_is_valid_shape(manifest)
		|| !manifest.custom || manifest.base64 == ""
		|| manifest.byte_size <= 0 || manifest.byte_size > registry.character_max_bytes
		|| manifest.chunk_count <= 0 || manifest.chunk_count > registry.character_max_chunks)
		{
			return 0;
		}

		/* Remove old jobs for this exact owner/recipient/image combination backward.
		A separate character or pet sheet for the same pair keeps its own progress */
		for (var i = array_length(character_send_jobs) - 1; i >= 0; i--)
		{
			/* previous is a queued owner/recipient job considered for replacement */
			var previous = character_send_jobs[i];

			/* Only this owner, recipient and image key are replaced. Other active sheets
			and transfers involving different players retain their jobs */
			if (previous.owner_slot == owner_slot && previous.target_slot == target_slot
			&& previous.manifest.network_key == manifest.network_key)
			{
				array_delete(character_send_jobs, i, 1);
			}
		}

		/* The job stores logical owner/target, both current accepted socket handles and
		the validated manifest. chunk_index zero begins at its first encoded chunk.
		Socket bindings let later processing reject stale jobs after slot reuse */
		array_push(character_send_jobs,
		{
			owner_slot: owner_slot,
			owner_socket: sockets[owner_slot],
			target_slot: target_slot,
			target_socket: sockets[target_slot],
			manifest: manifest,
			chunk_index: 0
		});
		return 1;
	}

	/// @description Round-robin character chunks with a packet-per-step limit and a three-millisecond budget checked after successful sends
	/// @returns {Real} Number of chunks sent
	update_character_sends = function()
	{
		/* Count successful chunks from zero. registry supplies chunk sizing/serialization,
		and started_at captures get_timer microseconds for the three-millisecond work budget */
		var sent_count = 0;
		var registry = scr_get_player_characters();
		var started_at = get_timer();

		/* Start attempt zero and process while jobs remain and the per-Step packet cap
		allows another attempt. Stale/failed jobs still consume an attempt, and successful
		sends additionally test the three-millisecond budget */
		for (var attempt = 0; attempt < character_send_packets_per_step && array_length(character_send_jobs) > 0; attempt++)
		{
			/* Take the first queued job and remove it before processing. Unfinished valid
			jobs reappend at the tail for round-robin transfer rather than monopolizing Step */
			var job = character_send_jobs[0];
			array_delete(character_send_jobs, 0, 1);

			/* Drop jobs whose owner/recipient socket changed, owner appearance changed or
			bound handle is noone. Slot reuse cannot inherit an old character transfer */
			if (sockets[job.owner_slot] != job.owner_socket
			|| sockets[job.target_slot] != job.target_socket
			|| !slot_uses_asset_key(job.owner_slot, job.manifest.network_key)
			|| job.owner_socket == noone || job.target_socket == noone)
			{
				continue;
			}

			/* chunk_start converts the zero-based chunk number to one-based string position.
			chunk_text selects at most one registry-sized section of encoded payload */
			var chunk_start = job.chunk_index * registry.character_chunk_size + 1;
			var chunk_text = string_copy(job.manifest.base64, chunk_start, registry.character_chunk_size);
			net.start(N_PLAYER_CHARACTER_CHUNK, job.owner_slot);
			registry.write_character_chunk_packet(net, job.owner_slot, job.manifest, job.chunk_index, chunk_text);

			/* A failed chunk send closes that recipient and discards this job attempt.
			Other queued transfers can continue on remaining attempts */
			if (net.send(job.target_socket, false, slot_transports[job.target_slot]) < 0)
			{
				close_client_slot(job.target_slot, "custom character send failed", true, true);
				continue;
			}
			sent_count++;
			job.chunk_index++;

			/* Requeue only while another chunk remains after increment. Completed jobs
			stay removed rather than resending their final chunk */
			if (job.chunk_index < job.manifest.chunk_count)
			{
				array_push(character_send_jobs, job);
			}

			/* After a successful chunk, stop when elapsed get_timer reaches 3,000
			microseconds. This bounds successful-send work within roughly three milliseconds */
			if (get_timer() - started_at >= 3000) break;
		}
		return sent_count;
	}

	/// @description Merge active metadata and queue one completed payload for an occupied recipient
	/// @param {Any} raw_owner_slot Logical appearance owner
	/// @param {Any} raw_target_slot Logical recipient
	/// @param {Bool} pet_role Use the pet manifest when true, defaulting to the character
	/// @returns {Real} One when queued, otherwise zero
	send_cached_character_to_slot = function(raw_owner_slot, raw_target_slot, pet_role = false)
	{
		/* Normalize logical owner and recipient separately before resolving the
		appearance payload and accepted destination */
		var owner_slot = slot_from_value(raw_owner_slot);
		var target_slot = slot_from_value(raw_target_slot);

		/* Both indexes must be valid and the target occupied. Otherwise no custom
		transfer can be queued safely */
		if (owner_slot == noone
		|| target_slot == noone
		|| sockets[target_slot] == noone)
		{
			return 0;
		}

		/* Find completed custom bytes for the owner current appearance key.
		The active slot metadata is merged later so cached payload retains current identity */
		var active_manifest = pet_role ? slot_pet_manifests[owner_slot] : character_manifest_for_slot(owner_slot);
		if (!is_struct(active_manifest)) return 0;
		var cached_manifest = cached_character_manifest(active_manifest.network_key);

		/* A cache miss has no completed custom bytes to queue. Return zero rather than
		creating an empty character job */
		if (cached_manifest == noone)
		{
			return 0;
		}

		/* Use registry metadata merging before queueing payload to the chosen recipient */
		var registry = scr_get_player_characters();
		cached_manifest = registry.manifest_with_metadata(cached_manifest, active_manifest);
		return queue_character_send(owner_slot, target_slot, cached_manifest);
	}

	/// @description Merge active metadata and queue the owner completed payload to occupied recipients
	/// @param {Any} raw_owner_slot Logical appearance owner
	/// @param {Bool} pet_role Use the pet manifest when true, defaulting to the character
	/// @returns {Real} Queued job count
	broadcast_cached_character = function(raw_owner_slot, pet_role = false)
	{
		/* Validate the appearance owner before queueing its cached payload to all players */
		var owner_slot = slot_from_value(raw_owner_slot);

		/* An invalid owner cannot identify cached slot appearance. Return zero jobs */
		if (owner_slot == noone)
		{
			return 0;
		}

		/* Look up the completed payload for this owner current appearance identity */
		var active_manifest = pet_role ? slot_pet_manifests[owner_slot] : character_manifest_for_slot(owner_slot);
		if (!is_struct(active_manifest)) return 0;
		var cached_manifest = cached_character_manifest(active_manifest.network_key);

		/* Without completed custom bytes, no broadcast jobs can be constructed */
		if (cached_manifest == noone)
		{
			return 0;
		}

		/* Borrow metadata merging so the payload uses current owner appearance fields.
		queued_count begins zero before visiting eligible recipients */
		var registry = scr_get_player_characters();
		cached_manifest = registry.manifest_with_metadata(cached_manifest, active_manifest);
		var queued_count = 0;

		/* Visit each zero-based destination slot, including the owner.
		Only occupied recipients contribute character transfer jobs */
		for (var target_slot = 0; target_slot < array_length(sockets); target_slot++)
		{
			/* Queue the merged payload only for an occupied recipient. Empty array slots
			are not transfer destinations */
			if (sockets[target_slot] != noone)
			{
				queued_count += queue_character_send(owner_slot, target_slot, cached_manifest);
			}
		}
		return queued_count;
	}

	/// @description Replace occupied owner metadata, cancel obsolete transfers and publish appearance/payload
	/// @param {Any} raw_slot Logical sender
	/// @param {Any} raw_character_manifest Valid manifest or compatible appearance key
	/// @returns {Bool} Whether the occupied owner state was updated
	set_client_character = function(raw_slot, raw_character_manifest)
	{
		/* Normalize the requesting owner before replacing its authoritative appearance */
		var slot = slot_from_value(raw_slot);

		/* Character changes require a valid occupied slot, rejecting absent owners
		before altering arrays or cancelling transfer jobs */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			return false;
		}

		/* registry supplies appearance validation and fallback lookup. A valid struct
		uses the submitted manifest directly, while other inputs resolve as a compatible
		key. character_key identifies the selected network appearance */
		var registry = scr_get_player_characters();
		var character_manifest = registry.manifest_is_valid_shape(raw_character_manifest)
			? raw_character_manifest
			: registry.manifest_for_key(raw_character_manifest, false);
		var character_key = character_manifest.network_key;
		slot_character_keys[slot] = character_key;
		slot_character_manifests[slot] = character_manifest;
		clear_unused_asset_jobs(slot);
		clear_pending_character_uploads(slot, character_key);
		registry.remember_manifest(character_manifest);
		prune_character_cache();

		/* Resolve the existing player after updating slot manifest metadata.
		Its optional appearance setter mirrors that authoritative identity */
		var player = player_controller_get_player(slot, false);

		/* Update appearance only on an existing player with a character setter.
		The slot metadata broadcast still proceeds for unsupported player shapes */
		if (player != noone
		&& variable_struct_exists(player, "set_character_key"))
		{
			player.set_character_key(character_key);
		}

		debug_log("Set character for " + scr_network_debug_server_slot_label(slot) + " key=" + character_key);
		broadcast_player_character(slot);

		/* Custom appearances may have completed encoded bytes to broadcast through
		the cache. Built-in characters need only their manifest identity update */
		if (character_manifest.custom)
		{
			broadcast_cached_character(slot);
		}
		return true;
	}

	/// @description Validate actual ownership/current appearance/encoded size before caching a completed upload
	/// @param {Any} raw_slot Socket-derived logical sender
	/// @returns {Bool} Whether the chunk was accepted, including valid incomplete assembly
	handle_client_character_chunk = function(raw_slot)
	{
		/* Normalize actual sender ownership, borrow registry and decode chunk body
		without remembering received metadata yet. The body owner is validated below */
		var slot = slot_from_value(raw_slot);
		var registry = scr_get_player_characters();
		var chunk = registry.read_character_chunk_packet(net, false);

		/* Only an occupied actual sender can upload character bytes. Reject other
		senders before matching claimed ownership or active appearance */
		if (slot == noone
		|| sockets[slot] == noone)
		{
			debug_error("Rejected custom character chunk from invalid slot.");
			return false;
		}

		/* The decoded owner must equal the socket-derived sender slot. Reject another
		player claim rather than allowing one client to upload assets for someone else */
		if (chunk.owner_id != slot)
		{
			debug_error("Rejected custom character chunk owner mismatch. actual=" + scr_network_debug_server_slot_label(slot) + " headerOwner=" + scr_network_debug_id_text(chunk.owner_id));
			return false;
		}

		/* Match the shared image to either current role. A pet-only upload must not
		change the player character, while one shared sheet can satisfy both roles */
		var character_match = slot_character_keys[slot] == chunk.manifest.network_key;
		var pet_match = slot_pet_keys[slot] == chunk.manifest.network_key;
		var active_manifest = character_match
			? character_manifest_for_slot(slot)
			: slot_pet_manifests[slot];

		/* A valid active manifest with the same network key is required.
		Reject stale or mismatched appearance uploads before accepting their bytes */
		if ((!character_match && !pet_match)
		|| !registry.manifest_is_valid_shape(active_manifest)
		|| !active_manifest.custom || !chunk.manifest.custom
		|| active_manifest.network_key != chunk.manifest.network_key
		|| active_manifest.byte_size != chunk.manifest.byte_size
		|| active_manifest.chunk_count != chunk.manifest.chunk_count)
		{
			debug_error("Rejected custom character chunk for inactive character key from " + scr_network_debug_server_slot_label(slot));
			return false;
		}

		chunk.manifest = registry.manifest_with_metadata(chunk.manifest, active_manifest);

		/* encoded_length is padded Base64 character length for declared bytes.
		expected_chunks divides it by registry chunk size, and expected_length bounds this
		chunk final remainder so declared size/count and actual text agree */
		var encoded_length = ceil(chunk.manifest.byte_size / 3) * 4;
		var expected_chunks = ceil(encoded_length / registry.character_chunk_size);
		var expected_length = min(registry.character_chunk_size, encoded_length - chunk.chunk_index * registry.character_chunk_size);

		/* Require positive bounded byte size, matching computed chunk count, an index
		below that count and exact text length. Any inconsistency rejects this upload chunk */
		if (chunk.manifest.byte_size <= 0 || chunk.manifest.byte_size > registry.character_max_bytes
		|| chunk.manifest.chunk_count != expected_chunks
		|| chunk.chunk_index >= expected_chunks
		|| string_length(chunk.chunk_text) != expected_length)
		{
			debug_error("Rejected custom character chunk with inconsistent payload length from " + scr_network_debug_server_slot_label(slot));
			return false;
		}

		/* Completed bytes with the same content identity need no second assembly.
		Cached chunks don't consume upload capacity, and release any reservation that
		another role completed first */
		var cached_payload = cached_character_manifest(chunk.manifest.network_key);
		if (is_struct(cached_payload)
		&& cached_payload.byte_size == chunk.manifest.byte_size
		&& cached_payload.chunk_count == chunk.manifest.chunk_count)
		{
			if (asset_upload_reserved_keys[slot] == chunk.manifest.network_key)
			{
				asset_upload_reserved_keys[slot] = "";
				asset_upload_reserved_bytes[slot] = 0;
			}
			return true;
		}

		/* Reserve capacity for an approved pet while counting other character bytes.
		Each pet fragment converts its reserved bytes into received bytes, keeping the
		four-sheet cap without losing an accepted pet to a concurrent upload */
		refresh_asset_upload_window(slot);
		var upload_bytes = string_length(chunk.chunk_text);
		var reserved_credit = asset_upload_reserved_keys[slot] == chunk.manifest.network_key
			? min(upload_bytes, asset_upload_reserved_bytes[slot]) : 0;
		var upload_limit = 4 * ceil(registry.character_max_bytes / 3) * 4;
		if (asset_upload_window_bytes[slot] + asset_upload_reserved_bytes[slot]
		+ upload_bytes - reserved_credit > upload_limit)
		{
			return false;
		}
		asset_upload_window_bytes[slot] += upload_bytes;
		asset_upload_reserved_bytes[slot] -= reserved_credit;

		/* result reports validation/assembly progress for this owner. The false argument
		suppresses writing a temporary installed character package on the server */
		var result = registry.accept_character_chunk(slot, chunk.manifest, chunk.chunk_index, chunk.chunk_text, false);

		/* Failed assembly returns false. A nonempty registry reason is logged below,
		while empty reasons still reject the chunk */
		if (!result.ok)
		{
			/* Log available assembly feedback only when it carries text, avoiding an empty
			rejection detail */
			if (result.message != "")
			{
				debug_error("Rejected custom character chunk from " + scr_network_debug_server_slot_label(slot) + ": " + result.message);
			}
			return false;
		}

		/* A valid incomplete upload succeeds for this chunk but does not publish a
		finished payload yet. Later chunks continue the same assembly */
		if (!result.complete)
		{
			return true;
		}

		cache_character_payload(result.manifest);
		if (asset_upload_reserved_keys[slot] == result.manifest.network_key)
		{
			asset_upload_reserved_keys[slot] = "";
			asset_upload_reserved_bytes[slot] = 0;
		}

		/* Publish a character result only when that role still uses this key. Pet
		uploads stay independent and leave the owner's player sprite untouched */
		if (character_match)
		{
			slot_character_manifests[slot] = registry.manifest_with_metadata(result.manifest, active_manifest);
			var player = player_controller_get_player(slot, false);
			if (player != noone && variable_struct_exists(player, "set_character_key"))
			{
				player.set_character_key(result.manifest.network_key);
			}
			broadcast_player_character(slot);
			broadcast_cached_character(slot);
		}

		/* The same validated payload can complete an equipped pet too. Merge the
		pet's own permissions before synchronizing its card and follower */
		if (pet_match && sockets[slot] != noone)
		{
			slot_pet_manifests[slot] = registry.manifest_with_metadata(result.manifest, slot_pet_manifests[slot]);
			scr_get_pets().receive_player_pet(slot, slot_pet_manifests[slot]);
			broadcast_player_pet(slot);
			broadcast_cached_character(slot, true);
		}

		debug_log("Accepted custom image " + result.manifest.network_key + " from " + scr_network_debug_server_slot_label(slot));
		return true;
	}
	#endregion /* Character Manifests and Chunk Transfers END */

	#region /* Player Join Synchronization */
	/// @description Assign identity and synchronize joining state before announcing the new player
	/// @param {Real} event_socket Accepted child socket, never a listener
	/// @param {Real} event_transport TRANSPORT value for the accepted child
	/// @param {String} requested_username Requested display name, defaulting to empty for generated fallback naming. The server makes it unique
	/// @param {Struct} requested_character_manifest Character metadata, defaulting to undefined. Missing or invalid shape uses player1
	/// @returns {Bool} Whether the client was accepted and initial state sent or queued
	accept_client_connection = function(event_socket, event_transport, requested_username = "", requested_character_manifest = undefined)
	{
		/* Accepted players must use child connection handles, never TCP/WebSocket/
		discovery listeners. Refuse listener values so per-player cleanup cannot own them */
		if (event_socket == server
		|| event_socket == websocket_server
		|| event_socket == discovery_socket)
		{
			debug_error("Refusing to accept listener socket " + string(event_socket) + " as a client.");
			return false;
		}

		/* Gameplay occupancy at the saved player limit rejects this new connection.
		Socket storage capacity is a separate later guard */
		if (connected_players >= max_players)
		{
			reject_full_connection(
				event_socket,
				event_transport,
				"Server is full (" + string(connected_players) + "/" + string(max_players) + ")."
			);
			return false;
		}

		/* Borrow the shared canvas to check whether its authoritative history checkpoint
		currently blocks a consistent new join */
		var joining_drawing = scr_get_drawing();

		/* When checkpoint-blocking capability exists and reports busy, reject with
		retry guidance. Other states continue without claiming canvas readiness beyond
		this service check */
		if (is_struct(joining_drawing)
		&& variable_struct_exists(joining_drawing, "server_history_checkpoint_blocks_join")
		&& joining_drawing.server_history_checkpoint_blocks_join())
		{
			reject_full_connection(
				event_socket,
				event_transport,
				"The shared canvas is being optimized. Please try joining again in a moment."
			);
			return false;
		}

		/* No logical player slot is assigned yet. The free-slot search fills _id from
		socket-array position rather than deriving it from the accepted socket handle */
		var _id = noone;

		/* Search zero-based socket storage from the first slot to capacity.
		Stop at the first noone entry, leaving noone if every storage slot is occupied */
		for (var i = 0; i < net.max_clients; i++)
		{
			/* The first unused slot becomes this connection logical identity.
			Do not reuse an occupied player slot even when gameplay capacity would allow joining */
			if (sockets[i] == noone)
			{
				_id = i;
				break;
			}
		}

		/* No storage slot remains, so reject rather than accepting a client without
		aligned per-player state arrays */
		if (_id == noone)
		{
			reject_full_connection(event_socket, event_transport);
			return false;
		}

		/* assigned_username is the server-approved unique display name. character_registry
		supplies validation, with the submitted manifest used only for a valid shape or
		player1 otherwise. Its network key identifies appearance, while drawing_author_id
		is a distinct assigned drawing ownership identity */
		var assigned_username = chat_make_unique_username(requested_username, slot_usernames);
		var character_registry = scr_get_player_characters();
		var assigned_character_manifest = character_registry.manifest_is_valid_shape(requested_character_manifest)
			? requested_character_manifest
			: character_registry.official_manifest("player1");
		var assigned_character_key = assigned_character_manifest.network_key;
		var drawing_author_id = assign_drawing_author_id(_id);
		clear_admin_slot(_id);
		sockets[_id] = event_socket;
		client_movement_authority[_id] = false;
		slot_transports[_id] = event_transport;
		slot_usernames[_id] = assigned_username;
		slot_character_keys[_id] = assigned_character_key;
		slot_character_manifests[_id] = assigned_character_manifest;
		slot_pet_keys[_id] = "";
		slot_pet_manifests[_id] = noone;
		pet_change_next_at[_id] = 0;
		asset_upload_window_started[_id] = 0;
		asset_upload_window_bytes[_id] = 0;
		asset_upload_reserved_keys[_id] = "";
		asset_upload_reserved_bytes[_id] = 0;
		character_registry.remember_manifest(assigned_character_manifest);
		clear_pending_character_uploads(_id, assigned_character_key);
		prune_character_cache();
		typing_active[_id] = false;
		typing_deadlines[_id] = 0;
		afk_active[_id] = false;
		afk_last_activity[_id] = current_time;
		heartbeat_next_ping[_id] = current_time + net.client_heartbeat_interval_ms;
		heartbeat_missed[_id] = 0;
		heartbeat_sequence[_id] = 0;
		heartbeat_last_heard[_id] = current_time;
		net.register_socket_transport(event_socket, event_transport);
		connected_players++;
		debug_success("Connected " + scr_network_debug_server_slot_label(_id));

		/* spawn_bounds supplies permitted world-pixel limits. Random spawn x/y are
		chosen within those bounds before authoritative player creation */
		var spawn_bounds = player_world_bounds();
		var spawn_player_on_x = random_range(spawn_bounds.left, spawn_bounds.right);
		var spawn_player_on_y = random_range(spawn_bounds.top, spawn_bounds.bottom);

		/* p is the newly created authoritative player for the accepted logical slot.
		Creation failure must undo the occupied socket/slot state already registered */
		var p = player_controller_make_player(_id, spawn_player_on_x, spawn_player_on_y, assigned_username, assigned_character_key);

		/* If player creation fails, notify and close the accepted connection without
		announcing a player that never reached initial synchronization */
		if (p == noone)
		{
			debug_error("Failed to create server player for slot " + string(_id));
			kick_client_slot(_id, "server player creation failed", "Disconnected: the server could not create your player.", false);
			return false;
		}

		/* Assign the client identity before sending host, lifecycle, wall, collision, and existing-player state */
		net.start(N_ID, _id);
		net.write(buffer_s16, _id);
		net.write(buffer_s32, p.pos.x);
		net.write(buffer_s32, p.pos.y);
		net.write(buffer_string, assigned_username);
		net.write(buffer_u8, p.facing_direction);

		/* Write the initial moving flag as one or zero, matching the client assignment
		visual-state format */
		net.write(buffer_u8, p.is_moving ? 1 : 0);
		character_registry.write_manifest(net, assigned_character_manifest);
		net.write(buffer_u32, drawing_author_id);

		/* Optional join capability: this server terminates canvas history with a zero-count packet */
		net.write(buffer_u8, 1);

		/* Capture delivery of the identity assignment. All later host/lifecycle/world
		packets depend on the client receiving its logical slot first */
		var send_result = net.send(sockets[_id]);

		/* A failed identity reply aborts join and closes the new player slot quietly.
		Do not continue world synchronization for a client without its assigned identity */
		if (send_result < 0)
		{
			debug_error("Failed to send N_ID packet to socket " + string(sockets[_id]));
			kick_client_slot(_id, "initial N_ID send failed", "Disconnected: the server could not send your join data.", false);
			return false;
		}

		/* Successful identity delivery allows the remaining ordered join packets.
		This log confirms send completion rather than a client-rendered world */
		else
		{
			debug_success("Sent N_ID packet to " + scr_network_debug_server_slot_label(_id));
		}

		/* host_status_result reports initial host ownership marker delivery.
		Join must fail if the client cannot receive this required status */
		var host_status_result = send_host_status_to_slot(_id);

		/* Abort the new connection when required host status could not synchronize,
		avoiding a partially established join */
		if (host_status_result < 0)
		{
			debug_error("Failed to sync host status to new client slot " + string(_id));
			kick_client_slot(_id, "host status sync failed", "Disconnected: the server could not sync host status.", false);
			return false;
		}

		/* Capture reset/countdown synchronization before the client receives drawing
		history, so its lifecycle display describes the same server session */
		var lifecycle_status_result = send_lifecycle_status_to_slot(_id);

		/* Close this incomplete join if the required reset status cannot be delivered */
		if (lifecycle_status_result < 0)
		{
			debug_error("Failed to sync server lifecycle status to new client slot " + string(_id));
			kick_client_slot(_id, "lifecycle status sync failed", "Disconnected: the server could not sync its reset timer.", false);
			return false;
		}

		/* player_limit_result reports delivery of current gameplay capacity,
		independent of constructor socket storage limits */
		var player_limit_result = send_player_limit_to_slot(_id);

		/* Fail the join rather than keeping a client with an unsynchronized required
		server capacity setting */
		if (player_limit_result < 0)
		{
			debug_error("Failed to sync the player limit to new client slot " + string(_id));
			kick_client_slot(_id, "player limit sync failed", "Disconnected: the server could not sync its player limit.", false);
			return false;
		}

		/* Wall policy must arrive before its snapshot is queued. A failed settings
		send closes the partial join instead of exposing wall edits without server policy */
		if (send_wall_settings_to_slot(_id) < 0)
		{
			kick_client_slot(_id, "wall settings sync failed", "Disconnected: the server could not sync wall settings.", false);
			return false;
		}
		scr_get_walls().server_queue_snapshot(_id);

		/* Capture initial authoritative collision-state delivery after queuing walls,
		before roster and shared-canvas history synchronization */
		var collision_sync_result = send_collision_state_to_slot(_id);

		/* A failed initial collision packet aborts join rather than allowing a world
		representation without required collision state */
		if (collision_sync_result < 0)
		{
			debug_error("Failed to sync collision object state to new client slot " + string(_id));
			kick_client_slot(_id, "collision object sync failed", "Disconnected: the server could not sync collision objects.", false);
			return false;
		}

		/* Borrow the existing authoritative roster for initial player-list/history
		synchronization. Each entry uses its logical player-slot identity */
		var player_controller = scr_get_player_controller();

		/* Only available roster state enters the initial roster/history block.
		The existing implementation skips that block when controller/players metadata is absent */
		if (is_struct(player_controller)
		&& variable_struct_exists(player_controller, "players"))
		{
			/* players is the authoritative roster candidate. It must be an array before
			counting or encoding slot entries */
			var players = player_controller.players;

			/* An array roster supplies existing player entries and subsequent AFK/history
			sync. A nonarray shape skips this current synchronization block */
			if (is_array(players))
			{
				/* Count existing eligible players from zero for join-failure diagnostics.
				The joining player itself is excluded from its initial roster list */
				var existing_player_count = 0;

				/* Visit zero-based roster slots to count existing occupied players other than
				the newcomer, ending after the final array entry */
				for (var i = 0; i < array_length(players); i++)
				{
					/* Skip the newcomer, unoccupied sockets and absent player entries before counting
					existing roster recipients */
					if ((i == _id)
					|| (sockets[i] == noone)
					|| (players[i] == noone))
					{
						continue;
					}

					existing_player_count++;
				}

				net.start(N_PLAYER_LIST, _id);

				/* Encode each existing player in zero-based roster order, then write noone as
				the list terminator so the client can stop without guessing entry count */
				for (var i = 0; i < array_length(players); i++)
				{
					/* Exclude the newcomer and empty sockets from its own existing-player list.
					A later player lookup also skips a missing roster struct */
					if ((i == _id)
					|| (sockets[i] == noone))
					{
						continue;
					}

					/* existing_player is this roster entry. Its logical ID, signed pixel position,
					name, direction/moving bytes and manifest form one initial player-list record */
					var existing_player = players[i];

					/* No player struct means no entry can be encoded at this occupied socket slot.
					Continue rather than dereferencing unavailable player fields */
					if (existing_player == noone)
					{
						continue;
					}

					net.write(buffer_s16, existing_player.ID);
					net.write(buffer_s32, existing_player.pos.x);
					net.write(buffer_s32, existing_player.pos.y);
					net.write(buffer_string, existing_player.username);
					net.write(buffer_u8, existing_player.facing_direction);

					/* Encode moving as a strict one/zero byte for this existing-player visual state */
					net.write(buffer_u8, existing_player.is_moving ? 1 : 0);
					character_registry.write_manifest(net, character_manifest_for_slot(i));
				}

				net.write(buffer_s16, noone);

				/* The roster send result confirms delivery of the complete slot-terminated
				list to the newcomer before indicator/history synchronization */
				var existing_player_result = net.send(sockets[_id]);

				/* An undeliverable initial roster aborts the partial join, preserving
				synchronization order rather than announcing this player to peers */
				if (existing_player_result < 0)
				{
					debug_error("Failed to send existing player list to new client slot " + string(_id) + " on socket " + string(sockets[_id]) + " with " + string(existing_player_count) + " player(s)");
					kick_client_slot(_id, "existing player list send failed", "Disconnected: the server could not sync the player list.", false);
					return false;
				}

				/* Pet metadata follows the complete roster, so each owner already exists
				on the client. Late joins receive independent equipped/removal state */
				for (var pet_owner = 0; pet_owner < array_length(sockets); pet_owner++)
				{
					if (pet_owner == _id || sockets[pet_owner] == noone) continue;
					if (send_player_pet_to_slot(pet_owner, _id) < 0)
					{
						kick_client_slot(_id, "pet roster sync failed", "Disconnected: the server could not sync pets.", false);
						return false;
					}
				}

				/* Inspect all zero-based idle-indicator slots, sending only existing AFK
				subjects other than the newcomer to its initial state */
				for (var i = 0; i < array_length(afk_active); i++)
				{
					/* Skip the newcomer, inactive AFK indicators and unused sockets.
					Only actual existing idle players need a state packet */
					if (i == _id
					|| !afk_active[i]
					|| sockets[i] == noone)
					{
						continue;
					}

					/* afk_sync_result reports this existing subject indicator delivery to the
					newcomer, keeping target and subject logical slots distinct */
					var afk_sync_result = send_afk_state_to_slot(_id, i, true);

					/* A failed required player-status sync aborts this incomplete join */
					if (afk_sync_result < 0)
					{
						debug_error("Failed to sync AFK state for slot " + string(i) + " to new client slot " + string(_id));
						kick_client_slot(_id, "AFK state sync failed", "Disconnected: the server could not sync player status.", false);
						return false;
					}
				}

				/* Borrow the canvas history sender. drawing_sync_result reports sent/queued
				ordered history and its completion marker, which must follow the chunks */
				var drawing_state = scr_get_drawing();

				/* Ordered history completion must follow its chunks before the client publishes the shared canvas */
				var drawing_sync_result = drawing_state.server_send_history_to_slot(_id);

				/* Failed history setup aborts join rather than displaying a partially synchronized
				canvas. Optional detail below adds the service-specific cause to diagnostics */
				if (drawing_sync_result < 0)
				{
					debug_error("Failed to sync drawing history to new client slot " + string(_id));

					/* Read detailed history failure only when its diagnostic field exists.
					Empty fallback adds no suffix to the cleanup reason, while available text explains it */
					var drawing_sync_detail = variable_struct_exists(drawing_state, "debug_server_history_sync_detail") ? string(drawing_state.debug_server_history_sync_detail) : "";
					kick_client_slot(_id, "drawing history sync failed" + (drawing_sync_detail == "" ? "" : ": " + drawing_sync_detail), "Disconnected: the server could not sync drawing history.", false);
					return false;
				}

				/* Send active vote immediately only when supported and no history job reports
				it still owns ordered join sync. Queued history completion can publish the vote later */
				if (variable_struct_exists(drawing_state, "server_send_active_layer_vote_to_slot")
				&& (!variable_struct_exists(drawing_state, "history_join_sync_active_for_slot")
					|| !drawing_state.history_join_sync_active_for_slot(_id)))
				{
					drawing_state.server_send_active_layer_vote_to_slot(_id);
				}

				/* Visit existing zero-based owners once more to queue their completed custom
				characters for the newcomer after roster/history setup */
				for (var i = 0; i < array_length(players); i++)
				{
					/* Skip the newcomer and empty owners when queuing existing appearance payloads.
					Cache misses return zero from the transfer helper */
					if (i == _id
					|| sockets[i] == noone)
					{
						continue;
					}

					send_cached_character_to_slot(i, _id);
					send_cached_character_to_slot(i, _id, true);
				}
			}
		}

		net.start(N_NEW_PLAYER, _id);
		net.write(buffer_s16, _id);
		net.write(buffer_s32, p.pos.x);
		net.write(buffer_s32, p.pos.y);
		net.write(buffer_string, assigned_username);
		net.write(buffer_u8, p.facing_direction);

		/* The peer announcement uses the same strict movement byte as identity/list
		entries, alongside the newcomer appearance manifest */
		net.write(buffer_u8, p.is_moving ? 1 : 0);
		character_registry.write_manifest(net, assigned_character_manifest);

		/* broadcast_count reports announcement delivery to existing players,
		excluding the newcomer logical slot already assigned its identity */
		var broadcast_count = net.send_all(sockets, _id);

		/* Clean failed existing recipients after the announcement. The accepted new
		player remains joined unless that cleanup exposes its own connection failure */
		if (broadcast_count < 0)
		{
			debug_error("Failed to broadcast N_NEW_PLAYER for client slot " + string(_id));
			close_failed_send_slots("broadcasting new player slot " + string(_id));
		}

		/* Log positive announcement delivery. Zero peers means no delivery-count
		message is needed for this accepted join */
		else if (broadcast_count > 0)
		{
			debug_success("Broadcast N_NEW_PLAYER for client slot " + string(_id) + " to " + string(broadcast_count) + " existing client(s)");
		}

		broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", assigned_username + " joined the game.", _id);
		return true;
	}
	#endregion /* Player Join Synchronization END */

	#region /* Server Startup and Shutdown */
	/// @description Release partially started hosting without duplicate archive work and report bind failure
	/// @param {String} failure_message Hosting feedback
	/// @returns {Bool} False to propagate startup failure
	fail_startup = function(failure_message)
	{
		/* A failed start must not leave a listener accepting an incomplete session */
		shutdown("startup_failed", false, true);
		msg = failure_message;
		debug_error(msg);
		return false;
	}

	/// @description Replace the server session and load persistence after creating its listeners
	/// @param {Bool} require_all_listeners Whether WebSocket/discovery failures also abort startup, defaulting to false. TCP is always required
	/// @returns {Bool} Whether required listeners started successfully
	init = function(require_all_listeners = false)
	{
		shutdown();
		reset_network_diagnostics();
		load_lifecycle_settings();
		load_admin_credentials();

		/* Borrow chat to clear the previous hosted-session messages before reopening
		listeners and loading this server authoritative world */
		var server_chat = scr_get_chat();

		/* Clear chat only when its service/method exists. Missing support does not
		prevent listener startup */
		if (is_struct(server_chat)
		&& variable_struct_exists(server_chat, "clear_messages"))
		{
			server_chat.clear_messages();
		}

		scr_get_collision_objects().reset_server();

		server = net.create_server(TRANSPORT_TCP, net.port, net.max_clients);

		/* TCP listener failure always aborts startup, because it is the running-state
		marker and required native gameplay route */
		if (server < 0)
		{
			return fail_startup("Server failed to bind TCP port " + string(net.port) + ". Check whether another server is already using it.");
		}

		websocket_server = net.create_server(TRANSPORT_WS, net.websocket_port, net.max_clients);

		/* Strict startup also aborts for WebSocket bind failure. Non-strict startup
		may continue native hosting and reports browser transport unavailable below */
		if (websocket_server < 0 && require_all_listeners)
		{
			return fail_startup("Server failed to bind WebSocket TCP port " + string(net.websocket_port) + ". Check whether another server is already using it.");
		}

		/* websocket_status begins with failed-bind feedback and is replaced only when
		the listener handle indicates successful creation */
		var websocket_status = "WebSocket server: OFF - could not create WS socket on port " + string(net.websocket_port);

		/* A nonnegative WebSocket listener enables browser route feedback.
		Failure takes the diagnostic alternative while non-strict TCP hosting may continue */
		if (websocket_server >= 0)
		{
			websocket_status = "WebSocket server: ON - browser clients use local WS port " + string(net.websocket_port);
		}

		/* Report failed optional WebSocket creation rather than claiming browser
		availability on a TCP-only non-strict server */
		else
		{
			debug_error(websocket_status);
		}

		discovery_socket = network_create_server(network_socket_udp, net.discovery_port, net.max_clients);

		/* A failed UDP discovery bind cannot advertise the game. Strict mode aborts.
		non-strict mode retains gameplay listeners and reports discovery disabled */
		if (discovery_socket < 0)
		{
			/* Strict startup requires discovery too, so release all partially started
			listeners through fail_startup instead of keeping an incomplete required set */
			if (require_all_listeners)
			{
				return fail_startup("Server failed to bind discovery UDP port " + string(net.discovery_port) + ". Check whether another server is already using it.");
			}
			discovery_status = "LAN discovery: OFF - could not create UDP socket";
			debug_error(discovery_status);
		}

		/* A created UDP discovery listener gets its owned growable writer and an
		immediately eligible first announcement deadline */
		else
		{
			discovery_status = "LAN discovery: ON - clients can scan your local network";
			discovery_buffer = buffer_create(256, buffer_grow, 1);
			next_discovery_broadcast = 0;
		}

		/* Borrow authoritative canvas persistence to restore the last hosted history
		after listeners are available, then request a startup checkpoint when supported */
		var persistent_drawing = scr_get_drawing();

		/* Load saved history only through an available persistence method.
		Missing support leaves current drawing state as established by server reset */
		if (is_struct(persistent_drawing)
		&& variable_struct_exists(persistent_drawing, "load_server_history_persistence"))
		{
			persistent_drawing.load_server_history_persistence();

			/* A supported checkpoint request consolidates restored history on startup.
			Without the optional hook, loading still completes normally */
			if (variable_struct_exists(persistent_drawing, "server_request_history_checkpoint"))
			{
				persistent_drawing.server_request_history_checkpoint("server startup");
			}
		}

		/* ip_command is instructional Windows command text shown in hosting feedback,
		not executed here. It helps users identify the LAN adapter address */
		var ip_command = "ipconfig | findstr /i \"adapter IPv4 Gateway\"";
		scr_get_walls().start_server();
		msg =
			"Server running on port " + string(net.port) + "\n\n" +
			websocket_status + "\n" +
			discovery_status + "\n\n" +
			"Same computer: 127.0.0.1:" + string(net.port) + "\n\n" +
			"Other computers on your Wi-Fi/LAN:\n" +
			"1. Open CMD on this server computer.\n" +
			"2. Type exactly:\n" + ip_command + "\n\n" +
			"3. Find the real Wi-Fi/Ethernet adapter.\n" +
			"4. Use its IPv4 Address, not Default Gateway.\n\n" +
			"Example:\n" +
			"IPv4 Address: 192.168.0.34  -> players use 192.168.0.34:" + string(net.port) + "\n" +
			"Default Gateway: 192.168.0.1 -> router, do not use\n\n" +
			"Avoid hotspot/sharing, virtual adapter, or VPN addresses unless clients use that exact network.\n\n" +
			"Browser players need WSS through a reverse proxy:\n" +
			"Public WSS 443 -> local ws://127.0.0.1:" + string(net.websocket_port);

		debug_success("Server running on port " + string(net.port));
		debug_log(websocket_status);
		debug_log(discovery_status);
		debug_log("Same computer: 127.0.0.1:" + string(net.port));
		debug_log("CMD: " + ip_command);
		debug_log("Use IPv4 Address, not Default Gateway.");
		debug_log("Example: IPv4 Address 192.168.0.34 -> players use 192.168.0.34:" + string(net.port));
		debug_log("Example: Default Gateway 192.168.0.1 -> router, do not use.");
		debug_log("Avoid hotspot/sharing, virtual adapter, or VPN addresses unless clients use that exact network.");
		debug_log("Browser WSS proxy target: ws://127.0.0.1:" + string(net.websocket_port));
		start_reset_schedule();

		/* Append the configured duration only when automatic reset is enabled.
		Disabled feedback remains the unlimited label without an inactive interval suffix */
		debug_log(reset_countdown_text() + (automatic_reset_enabled
			? " (interval " + server_reset_duration_text(automatic_reset_interval_minutes * 60) + ")"
			: ""));
		return true;
	}

	/// @description Persist the authoritative drawing, archive when requested, and release owned sockets and buffers
	/// @param {String} reason Logged lifecycle cause, defaulting to server_shutdown
	/// @param {Bool} archive_drawing Whether to save the server shutdown archive, defaulting to true
	/// @param {Bool} drawing_already_prepared Whether a verified restart already prepared the drawing, defaulting to false
	shutdown = function(reason = "server_shutdown", archive_drawing = true, drawing_already_prepared = false)
	{
		/* Capture the TCP running marker before releasing resources so shutdown
		notifications/archives occur only for an active server session */
		var was_running = is_running();

		/* A running session enters archive/notification work once. Recursive/repeated
		shutdown calls skip that guarded work but still proceed through resource cleanup */
		if (was_running && !shutdown_in_progress)
		{
			shutdown_in_progress = true;

			/* Ordinary shutdown persists/notifies and optionally archives. A verified
			restart already prepared drawing, so skip duplicate archive/reset work */
			if (!drawing_already_prepared)
			{
				broadcast_chat(CHAT_TYPE_SYSTEM, noone, "", "The server is shutting down. The drawing is being archived.");
				broadcast_lifecycle_shutdown(reason);

				/* Borrow the authoritative canvas for forced persistence and server/local-
				client shutdown archives before clearing client drawing state */
				var drawing_archive = scr_get_drawing();

				/* Save history when persistence support exists before listener destruction.
				This shutdown path currently does not abort resource cleanup on a save failure */
				if (variable_struct_exists(drawing_archive, "save_server_history_persistence"))
				{
					drawing_archive.save_server_history_persistence(true);
				}

				/* Borrow the shared client to detect Host & Play, whose client canvas also
				needs its own shutdown archive before shared state clears */
				var local_client = scr_get_client();

				/* A present local-host client gets a client-side archive. Remote/unavailable
				client state does not trigger that in-process archive */
				if (is_struct(local_client)
				&& variable_struct_exists(local_client, "local_host_mode")
				&& local_client.local_host_mode)
				{
					drawing_archive.save_automatic_archive("client_shutdown", "client");
				}

				/* Save the server PNG archive only when caller requested it.
				Verified restart/startup-failure paths can suppress this duplicate archive */
				if (archive_drawing)
				{
					drawing_archive.save_automatic_archive("server_shutdown", "server");
				}
				drawing_archive.clear_client_drawing_state();
			}
		}

		reset_host_player_slot(false);
		scr_get_walls().stop_server();

		/* Track whether any accepted valid client had character upload state released.
		Only that case needs the cache-pruning pass before whole-server cache reset */
		var released_character_state = false;

		/* Visit every zero-based accepted slot, destroy valid child handles and restore
		unused slot metadata regardless of whether a handle was valid */
		for (var i = 0; i < array_length(sockets); i++)
		{
			/* A valid accepted handle owns upload state and needs destruction.
			Absent/negative entries skip those resource calls while their arrays still reset */
			if (is_real(sockets[i]) && sockets[i] >= 0)
			{
				clear_pending_character_uploads(i);
				released_character_state = true;
				destroy_client_socket(sockets[i]);
			}

			sockets[i] = noone;
			slot_transports[i] = TRANSPORT_TCP;
			slot_usernames[i] = "";
			slot_character_keys[i] = "player1";
			slot_character_manifests[i] = noone;
			slot_pet_keys[i] = "";
			slot_pet_manifests[i] = noone;
			pet_change_next_at[i] = 0;
			asset_upload_window_started[i] = 0;
			asset_upload_window_bytes[i] = 0;
			asset_upload_reserved_keys[i] = "";
			asset_upload_reserved_bytes[i] = 0;
			client_movement_authority[i] = false;
			typing_active[i] = false;
			typing_deadlines[i] = 0;
			afk_active[i] = false;
			afk_last_activity[i] = 0;
		}

		/* Prune owner-dependent registry copies after actual accepted clients were
		released. An already-empty server needs no such ownership scan */
		if (released_character_state) prune_character_cache();

		/* Unregister/destroy the valid TCP listener through whole-server cleanup.
		Missing or failed listener handles need no release */
		if (is_real(server) && server >= 0)
		{
			net.unregister_socket_transport(server);
			network_destroy(server);
		}

		/* Release the separate WebSocket listener only when allocated successfully */
		if (is_real(websocket_server) && websocket_server >= 0)
		{
			net.unregister_socket_transport(websocket_server);
			network_destroy(websocket_server);
		}

		/* Visit every zero-based status-only handle and release valid accepted sockets
		before clearing the parallel status tracking arrays */
		for (var i = 0; i < array_length(status_sockets); i++)
		{
			/* Only valid tracked status handles are passed to accepted-client destruction */
			if (is_real(status_sockets[i]) && status_sockets[i] >= 0)
			{
				destroy_client_socket(status_sockets[i]);
			}
		}

		/* Release pending first-packet handles before clearing their aligned transport/
		deadline lists, preventing waiting connections surviving server shutdown */
		for (var i = 0; i < array_length(pending_ws_sockets); i++)
		{
			/* Destroy only valid pending accepted handles, skipping failed/absent values */
			if (is_real(pending_ws_sockets[i]) && pending_ws_sockets[i] >= 0)
			{
				destroy_client_socket(pending_ws_sockets[i]);
			}
		}

		/* Whole-server cleanup owns the UDP discovery listener and releases it only
		when valid */
		if (is_real(discovery_socket) && discovery_socket >= 0)
		{
			network_destroy(discovery_socket);
		}

		/* Delete the allocated discovery writer before restoring its absent handle */
		if (!is_undefined(discovery_buffer) && buffer_exists(discovery_buffer))
		{
			buffer_delete(discovery_buffer);
		}

		/* Delete the lazily allocated chat writer when it exists. A never-used chat
		buffer remains absent and requires no release */
		if (!is_undefined(chat_buffer) && buffer_exists(chat_buffer))
		{
			buffer_delete(chat_buffer);
		}

		/* Delete the lazily allocated movement writer when present, leaving no owned
		packet buffers behind after server shutdown */
		if (!is_undefined(position_buffer) && buffer_exists(position_buffer))
		{
			buffer_delete(position_buffer);
		}

		server = noone;
		websocket_server = noone;
		discovery_socket = noone;
		discovery_buffer = noone;
		chat_buffer = noone;
		position_buffer = noone;
		discovery_status = "LAN discovery: OFF";
		next_discovery_broadcast = 0;
		next_position_broadcast = 0;
		next_collision_broadcast = 0;
		automatic_reset_deadline = 0;
		reset_warning_state();
		status_sockets = [];
		status_socket_deadlines = [];
		pending_ws_sockets = [];
		pending_ws_transports = [];
		pending_ws_deadlines = [];
		client_close_in_progress = array_create(net.max_clients, false);
		slot_usernames = array_create(net.max_clients, "");
		slot_character_keys = array_create(net.max_clients, "player1");
		slot_character_manifests = array_create(net.max_clients, noone);
		slot_pet_keys = array_create(net.max_clients, "");
		slot_pet_manifests = array_create(net.max_clients, noone);
		pet_change_next_at = array_create(net.max_clients, 0);
		asset_upload_window_started = array_create(net.max_clients, 0);
		asset_upload_window_bytes = array_create(net.max_clients, 0);
		asset_upload_reserved_keys = array_create(net.max_clients, "");
		asset_upload_reserved_bytes = array_create(net.max_clients, 0);
		character_cache_keys = [];
		character_cache_manifests = [];
		character_send_jobs = [];
		slot_drawing_author_ids = array_create(net.max_clients, 0);
		next_drawing_author_id = 1000001;
		position_dirty = array_create(net.max_clients, false);
		client_movement_authority = array_create(net.max_clients, false);
		typing_active = array_create(net.max_clients, false);
		typing_deadlines = array_create(net.max_clients, 0);
		afk_active = array_create(net.max_clients, false);
		afk_last_activity = array_create(net.max_clients, 0);
		heartbeat_next_ping = array_create(net.max_clients, 0);
		heartbeat_missed = array_create(net.max_clients, 0);
		heartbeat_sequence = array_create(net.max_clients, 0);
		heartbeat_last_heard = array_create(net.max_clients, 0);
		clear_all_admin_sessions();
		admin_expected_key_id = "";
		admin_expected_token = "";
		admin_credentials_configured = false;
		admin_credentials_source = "";
		force_restart_pending = false;
		force_restart_pending_at = 0;
		force_restart_pending_reason = "";
		force_restart_pending_slot = noone;
		force_restart_pending_request_id = 0;
		force_restart_in_progress = false;
		force_restart_archive_verification_error = "";
		reset_network_diagnostics();
		connected_players = 0;
		host_player_slot = noone;
		msg = "";
		player_controller_clear_players();
		net.clear_failed_sends();
		scr_get_drawing().reset_server();
		scr_get_collision_objects().reset_server();
		shutdown_in_progress = false;
	}
	#endregion /* Server Startup and Shutdown END */

	#region /* LAN Discovery */
	/// @description Encode current hosting/counts and reply to a UDP target or announce on LAN
	/// @param {String} target_ip Destination, defaulting to empty for broadcast
	/// @param {Real} target_port Destination UDP port, defaulting to -1 for broadcast
	/// @param {String} request_id Echo correlation text, defaulting to empty for unsolicited/legacy announcements
	/// @returns {Real} Transport result or -1 without discovery resources
	send_discovery_response = function(target_ip = "", target_port = -1, request_id = "")
	{
		/* A reply requires the allocated UDP listener and live server-owned discovery
		writer. Missing/failed resources return -1 before text packet construction */
		if (!is_real(discovery_socket)
		|| discovery_socket < 0
		|| is_undefined(discovery_buffer)
		|| !buffer_exists(discovery_buffer))
		{
			return -1;
		}

		buffer_seek(discovery_buffer, buffer_seek_start, 0);
		buffer_write(
			discovery_buffer,
			buffer_string,
			net.discovery_magic
				+ "|RESPONSE|"
				+ string(net.port)
				+ "|" + net.lan_server_name + "|"
				+ string(connected_players)
				+ "|"
				+ string(max_players)
				+ "|"
				+ string(request_id)
		);

		/* packet_size is written discovery bytes and send_result is assigned by unicast
		or broadcast. The text body carries magic, RESPONSE, game port, LAN name,
		player count/capacity and optional echo ID in pipe-delimited order */
		var packet_size = buffer_tell(discovery_buffer);
		var send_result;

		/* An explicit nonempty host and nonnegative port reply to that queried UDP
		endpoint. Otherwise announce availability on the shared LAN broadcast port */
		if (string(target_ip) != ""
		&& target_port >= 0)
		{
			send_result = network_send_udp(discovery_socket, target_ip, target_port, discovery_buffer, packet_size);
		}

		/* Without a complete explicit destination, broadcast discovery to the LAN so
		clients scanning the shared port can see this server */
		else
		{
			send_result = network_send_broadcast(discovery_socket, net.discovery_port, discovery_buffer, packet_size);
		}

		/* Report a failed discovery send through rate-limited network diagnostics.
		The returned transport result lets callers see failure without claiming delivery */
		if (send_result < 0)
		{
			net.log_send_error("LAN discovery response failed. result=" + string(send_result));
		}

		return send_result;
	}

	/// @description Expire temporary connections and broadcast hosting at its millisecond schedule
	update_discovery = function()
	{
		cleanup_status_sockets();
		cleanup_pending_ws_sockets();

		/* Temporary status/pending cleanup already ran. Without a valid discovery
		listener, skip only the periodic UDP announcement */
		if (!is_real(discovery_socket)
		|| discovery_socket < 0)
		{
			return;
		}

		/* Wait until the current_time millisecond announcement deadline.
		Due updates advance it by discovery_interval_ms before sending */
		if (current_time < next_discovery_broadcast)
		{
			return;
		}

		next_discovery_broadcast = current_time + net.discovery_interval_ms;
		send_discovery_response();
	}

	/// @description Reply only to requests belonging to this server discovery listener
	/// @param {Real} network_id Async id field
	/// @param {Id.Buffer} network_data Borrowed packet buffer
	/// @param {String} network_ip UDP source IP
	/// @param {Real} network_port UDP source port
	/// @param {Real} network_server Async listener ID, defaulting to noone for matching by other event handles
	/// @returns {Bool} Whether the event belongs to discovery, including ignored requests
	handle_discovery_async = function(network_id, network_data, network_ip, network_port, network_server = noone)
	{
		/* An absent discovery listener cannot own this async event.
		Return false so other socket routing can inspect it */
		if (!is_real(discovery_socket) || discovery_socket < 0)
		{
			return false;
		}

		/* Match a valid numeric id or explicit listener field to the discovery handle.
		These Booleans distinguish UDP ownership before reading text rather than binary packets */
		var discovery_id_matches = is_real(network_id)
			&& network_id >= 0
			&& network_id == discovery_socket;
		var discovery_server_matches = is_real(network_server)
			&& network_server >= 0
			&& network_server == discovery_socket;

		/* Neither event field names this discovery listener, so return false.
		Do not consume another subsystem network traffic */
		if (!discovery_id_matches && !discovery_server_matches)
		{
			return false;
		}

		/* A discovery-owned event with no live buffer is consumed and ignored.
		It must not fall through into gameplay binary decoding */
		if (is_undefined(network_data) || !buffer_exists(network_data))
		{
			return true;
		}

		buffer_seek(network_data, buffer_seek_start, 0);

		/* message is the incoming discovery text and parts splits its pipe-delimited
		fields. This existing server path reads the string directly without the client-side
		size/exception guards */
		var message = buffer_read(network_data, buffer_string);
		var parts = string_split(message, "|");

		/* Require project/protocol magic plus REQUEST before responding.
		Foreign-game announcements and malformed kinds are consumed without a reply */
		if (array_length(parts) < 2 || parts[0] != net.discovery_magic || parts[1] != "REQUEST")
		{
			return true;
		}

		/* The echoed correlation ID starts empty for older requests. A fourth field
		supplies it when present, allowing client round-trip measurement */
		var request_id = "";

		/* Echo the optional request ID only when its field exists.
		Otherwise use the older empty-ID response format */
		if (array_length(parts) >= 4)
		{
			request_id = string(parts[3]);
		}

		/* An absent source host or invalid port cannot receive a unicast reply.
		Consume the request without accidentally broadcasting in response */
		if (string(network_ip) == "" || network_port < 0)
		{
			return true;
		}

		send_discovery_response(network_ip, network_port, request_id);
		return true;
	}
	#endregion /* LAN Discovery END */

	#region /* Async Router */
	/// @description Validate packets and resolve the sender slot from its accepted socket before gameplay dispatch
	/// @param {Real} network_id Async id field
	/// @param {Real} network_type GameMaker network event type
	/// @param {Real} network_socket Async socket field
	/// @param {Id.Buffer} network_data Borrowed packet buffer
	/// @param {Real} network_server Async listener ID, defaulting to noone for matching by other event handles
	on_async = function(network_id, network_type, network_socket, network_data, network_server = noone)
	{
		/* Start from async id and prefer a valid explicit socket field below.
		The resulting actual handle is resolved to a logical player slot only when needed */
		var event_socket = network_id;

		/* A valid explicit accepted socket takes precedence over id, which can name
		its listener. Missing socket metadata retains the id fallback */
		if (is_real(network_socket) && network_socket >= 0)
		{
			event_socket = network_socket;
		}

		/* Transport starts TCP until listener metadata or recorded temporary ownership
		establishes WebSocket/another pending transport */
		var event_transport = TRANSPORT_TCP;

		/* An event whose id or explicit listener names the WebSocket listener uses
		WebSocket framing. Other events retain TCP until temporary tracking overrides it */
		if (network_id == websocket_server
		|| network_server == websocket_server)
		{
			event_transport = TRANSPORT_WS;
		}

		/* Identify the actual handle in status-only and pending first-packet collections.
		These flags guide routing without assigning a player identity prematurely */
		var event_is_status_socket = is_status_client_socket(event_socket);
		var event_is_pending_socket = is_pending_ws_socket(event_socket);

		/* A tracked browser status handle always uses WebSocket.
		Otherwise pending ownership may supply its accepted transport */
		if (event_is_status_socket)
		{
			event_transport = TRANSPORT_WS;
		}

		/* Use the recorded pending transport when present, retaining the inferred
		listener transport as fallback if its pending mapping is missing */
		else if (event_is_pending_socket)
		{
			event_transport = get_pending_ws_transport(event_socket, event_transport);
		}

		/* Convert the async event constant to readable verbose routing text */
		var async_name = net.event_type_to_string(network_type);
		net.log_verbose("Server async event: " + async_name + " (" + string(network_type) + "), socket=" + string(event_socket) + ", transport=" + net.transport_to_string(event_transport));

		/* Connection events maintain first-packet/player ownership, while data validates
		wire structure before join/status or gameplay dispatch. Other event types perform
		no operation in this server router */
		switch(network_type)
		{

			#region /* Connection Events */
			/* A new accepted handle waits for its first identifying packet rather than
			immediately consuming a gameplay player slot */
			case network_type_connect:

				/* An already accepted player handle does not need another pending record.
				Consume duplicate connect notification without restarting join ownership */
				if (find_slot_by_socket(event_socket) != noone)
				{
					net.log_verbose("Connect event for already accepted socket " + string(event_socket));
					break;
				}

				add_pending_ws_socket(event_socket, event_transport);
				debug_log("Accepted pending " + net.transport_to_string(event_transport) + " connection on socket " + string(event_socket));
				break;

			/* Remove temporary ownership first. Only an accepted gameplay handle maps to
			a logical slot that needs player departure broadcasts */
			case network_type_disconnect:

				/* A status-only disconnect removes its temporary tracking without gameplay
				player cleanup or destroying an already-disconnected handle */
				if (event_is_status_socket)
				{
					remove_status_socket(event_socket, false);
					break;
				}

				/* A first-packet wait disconnect removes only its pending triple.
				It never became a roster player */
				if (event_is_pending_socket)
				{
					remove_pending_ws_socket(event_socket, false);
					break;
				}

				/* Resolve the departed actual handle to its zero-based gameplay slot.
				noone means an earlier cleanup already removed or never accepted it */
				var disconnected_slot = find_slot_by_socket(event_socket);

				/* An unknown/already-closed handle has no player state to remove again.
				Log and stop rather than indexing a guessed slot */
				if (disconnected_slot == noone)
				{
					debug_log("Disconnected socket " + string(event_socket) + " was already closed.");
					break;
				}

				close_client_slot(disconnected_slot, "socket disconnected", true, false);
				close_failed_send_slots("broadcasting removal for disconnected slot " + string(disconnected_slot));
				break;
			#endregion /* Connection Events END */

			#region /* Data Packets */
			/* Resolve sender identity from accepted handle, then structural-preflight the
			shared packet before reading any action-specific body */
			case network_type_data:

				/* sender_slot is the accepted logical identity, or noone for a first/unknown
				connection. A packet header cannot select that identity */
				var sender_slot = find_slot_by_socket(event_socket);

				/* Malformed/oversized data closes accepted player state or a nonlistener
				unjoined handle. Stop this packet before any gameplay handler consumes it */
				if (!scr_server_packet_is_valid(net))
				{
					/* A known sender failure uses full authoritative slot cleanup.
					Unknown handles use the protected nonlistener cleanup alternative */
					if (sender_slot != noone)
					{
						close_client_slot(sender_slot, "malformed or oversized packet", true, true);
					}

					/* Only child connections may be destroyed for malformed unjoined data.
					Exclude all listeners so invalid packets cannot close whole-server resources */
					else if (event_socket != server && event_socket != websocket_server && event_socket != discovery_socket)
					{
						remove_pending_ws_socket(event_socket, false);
						destroy_client_socket(event_socket);
					}
					break;
				}

				/* An unjoined handle may request listing status or send a supported join.
				It cannot reach gameplay dispatch until accepted into a logical player slot */
				if (sender_slot == noone)
				{
					/* A recorded first-packet child uses its pending join/status route.
					The WebSocket listener itself must never be promoted as a player */
					if (event_is_pending_socket
					&& event_socket != websocket_server)
					{
						/* WebSocket listing requests become status-only connections. Reply with counts,
						remove pending tracking and keep the handle for one second before cleanup */
						if (event_transport == TRANSPORT_WS
						&& net.header.type == N_SERVER_STATUS_REQUEST)
						{
							send_status_response(event_socket, TRANSPORT_WS);
							remove_pending_ws_socket(event_socket, false);

							/* Append the actual status handle and aligned current_time deadline.
							The one-second grace permits reply delivery without reserving gameplay capacity */
							status_sockets[array_length(status_sockets)] = event_socket;
							status_socket_deadlines[array_length(status_socket_deadlines)] = current_time + 1000;
							debug_log("Sent server list status to browser probe on socket " + string(event_socket));
							break;
						}

						/* A versioned join carries gameplay compatibility before requested name/manifest.
						Only the supported version can proceed to player acceptance */
						if (net.header.type == N_JOIN_GAME_VERSIONED)
						{
							/* Read the pending client advertised gameplay version before its identity fields */
							var gameplay_protocol_version = net.read(buffer_u16);

							/* An incompatible pending client is removed/rejected with update guidance.
							Do not consume its name/character as current protocol gameplay state */
							if (gameplay_protocol_version != GAMEPLAY_PROTOCOL_VERSION)
							{
								remove_pending_ws_socket(event_socket, false);
								reject_full_connection(event_socket, event_transport, "This server requires the latest version of Jonnil Online. Please update the game and try again.");
								break;
							}

							/* Capture requested name and manifest without remembering unapproved metadata
							in the registry. Remove pending ownership before the guarded acceptance method */
							var requested_username = net.read(buffer_string);
							var requested_character_manifest = scr_get_player_characters().read_manifest(net, false);
							remove_pending_ws_socket(event_socket, false);
							accept_client_connection(event_socket, event_transport, requested_username, requested_character_manifest);
							break;
						}

						/* Legacy unversioned joins are explicitly rejected by this server.
						Compatibility preflight acceptance does not imply the old gameplay format is admitted */
						if (net.header.type == N_JOIN_GAME)
						{
							remove_pending_ws_socket(event_socket, false);
							reject_full_connection(event_socket, event_transport, "This server requires the latest version of Jonnil Online. Please update the game and try again.");
							break;
						}

						debug_error("Pending connection sent unexpected packet: " + net.message_type_to_string(net.header.type));
						remove_pending_ws_socket(event_socket, true);
						break;
					}

					/* Untracked nonlistener child handles may still supply first join/status data.
					Listeners are excluded from fallback acceptance and remain server resources */
					if (event_socket != server
					&& event_socket != websocket_server
					&& event_socket != discovery_socket)
					{
						/* An untracked WebSocket listing request gets the same count response and
						one-second status-only ownership as a tracked probe */
						if (event_transport == TRANSPORT_WS
						&& net.header.type == N_SERVER_STATUS_REQUEST)
						{
							send_status_response(event_socket, TRANSPORT_WS);

							/* Record the untracked status handle and aligned one-second current_time expiry,
							keeping this probe separate from player arrays */
							status_sockets[array_length(status_sockets)] = event_socket;
							status_socket_deadlines[array_length(status_socket_deadlines)] = current_time + 1000;
							debug_log("Sent server list status to untracked browser probe on socket " + string(event_socket));
							break;
						}

						/* Fallback joins still require the versioned gameplay layout before reading
						requested player identity */
						if (net.header.type == N_JOIN_GAME_VERSIONED)
						{
							/* Read the untracked child gameplay version before any requested-name metadata */
							var untracked_gameplay_protocol_version = net.read(buffer_u16);

							/* Reject the incompatible untracked child rather than accepting a stale
							body layout into current gameplay */
							if (untracked_gameplay_protocol_version != GAMEPLAY_PROTOCOL_VERSION)
							{
								reject_full_connection(event_socket, event_transport, "This server requires the latest version of Jonnil Online. Please update the game and try again.");
								break;
							}

							/* Capture the fallback requested name and unremembered manifest. The shared
							acceptance method still applies capacity, identity and synchronization guards */
							var untracked_requested_username = net.read(buffer_string);
							var untracked_requested_character_manifest = scr_get_player_characters().read_manifest(net, false);
							accept_client_connection(event_socket, event_transport, untracked_requested_username, untracked_requested_character_manifest);
							break;
						}

						/* Reject fallback unversioned joins with the same update guidance.
						Unknown remaining first packets are ignored instead of reaching gameplay */
						if (net.header.type == N_JOIN_GAME)
						{
							reject_full_connection(event_socket, event_transport, "This server requires the latest version of Jonnil Online. Please update the game and try again.");
							break;
						}
					}

					net.log_verbose("Ignoring data from unknown socket " + string(event_socket));
					break;
				}

				note_client_activity(sender_slot);
				scr_on_data_server(sockets, sender_slot);

				/* packet_name labels this dispatched accepted-player packet for diagnostics,
				without changing reader state or its socket-derived sender identity */
				var packet_name = net.message_type_to_string(net.header.type);

				/* Log packet summaries according to routine-traffic suppression. Data still
				refreshes liveness and dispatches when its diagnostic text is skipped */
				if (net.should_log_packet(net.header.type))
				{
					debug_log("Server data packet: " + packet_name + " (" + string(net.header.type) + "), actual=" + scr_network_debug_server_slot_label(sender_slot) + ", header=" + scr_network_debug_server_slot_label(net.header.socketID));
				}
				break;
			#endregion /* Data Packets END */

		}
	}
	#endregion /* Async Router END */

}

/// @description Get the process-wide server session. Creates it on first use
/// @returns {Struct} Shared scr_server instance
function scr_get_server()
{
	/* Create one process-wide authoritative server on first access, sharing its
	listeners, per-slot arrays and lifecycle across callers */
	static n = new scr_server();
	return n;
}
