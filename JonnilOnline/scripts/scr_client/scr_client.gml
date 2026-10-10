#macro Client scr_get_client()

/// @description Create client connection, discovery, diagnostics, and remote-admin state
function scr_client() constructor
{

	#region /* Client State */
	/* The client owns its outgoing gameplay socket. undefined means it has never
	been created, and disconnect later restores noone. ID is the logical player
	slot assigned by the server, initially noone until the join reply */
	socket = undefined;
	ID = noone;

	/* singleplayer_mode starts off until offline play selects it. local_host_mode
	also starts off and becomes true when this client shares its process with a hosted
	server. host_player_slot remains noone until the server announces its host identity */
	singleplayer_mode = false;
	local_host_mode = false;
	host_player_slot = noone;

	/* requested_username starts empty before connection setup filters player input.
	assigned_username stays empty until the server accepts a name. join_request_sent
	starts false and prevents duplicate join packets after socket completion */
	requested_username = "";
	assigned_username = "";
	join_request_sent = false;

	/* Pet changes keep only the latest requested local key while waiting for a
	300 ms send interval. Zero allows the initial join selection immediately */
	pet_requested_key = "";
	pet_send_pending = false;
	pet_send_next_at = 0;
	pet_send_interval_ms = 300;

	/* Custom pet bytes wait for their accepted manifest. The approved/sent keys
	avoid repeating the same active sheet when only its sharing permissions change */
	pet_pending_upload_manifest = noone;
	pet_approved_key = "";
	pet_upload_sent_key = "";

	/* net borrows the process-wide transport and packet service. connect_status
	starts with the disconnected UI message, and needs_server_list starts false until
	failure/disconnection asks the controller to return to selection */
	net = scr_get_network();
	connect_status = "Not connected";
	needs_server_list = false;

	/* discovery_socket and discovery_buffer begin unallocated. LAN startup creates
	the client-owned UDP scan socket and writer, and stop_discovery releases both.
	discovery_listen_port starts noone until a fixed-port bind succeeds */
	discovery_socket = noone;
	discovery_buffer = noone;
	discovery_listen_port = noone;

	/* official_servers starts without normalized official/saved configurations.
	saved_servers starts without loaded user entries. saved_servers_loaded prevents
	repeat loads, and saved_servers_load_failed initially allows persistence attempts */
	official_servers = [];
	saved_servers = [];
	saved_servers_loaded = false;
	saved_servers_load_failed = false;

	/* Saved server names and addresses are persisted in this sandbox INI.
	saved_servers_error starts empty and carries validation/read/write feedback */
	saved_servers_file = "saved_servers.ini";
	saved_servers_error = "";

	/* The combined UI row list begins empty. discovery_found starts false,
	discovery_address starts empty, and discovery_servers collects LAN replies from
	an empty list. discovery_status initially tells the user scanning is pending */
	server_list_entries = [];
	discovery_found = false;
	discovery_address = "";
	discovery_servers = [];
	discovery_status = "Scanning for servers on your local network...";

	/* The current_time millisecond deadline begins zero, allowing an immediate
	first scan. transport begins at the runtime default and connect_address stays
	empty until a connection target is chosen */
	next_discovery_request = 0;
	transport = net.default_client_transport();
	connect_address = "";

	/* No connection is waiting initially, so its millisecond deadline is zero.
	connect_failed_message starts empty, and last_server_heard stays zero until
	connection setup or received traffic seeds the watchdog clock */
	connect_pending = false;
	connect_deadline = 0;
	connect_failed_message = "";
	last_server_heard = 0;

	/* Capacity starts at the network default until server status replaces it.
	Wall support and wall editing both start false until the server sends its policy */
	server_max_players = net.default_max_players;
	wall_drawing_supported = false;
	wall_drawing_enabled = false;

	/* Reset countdown information is unknown and disabled initially. The minute
	interval and current_time millisecond deadline start zero. last_server_reset_id
	starts noone for duplicate detection, and shutdown has not yet been received */
	server_reset_status_known = false;
	server_reset_enabled = false;
	server_reset_interval_minutes = 0;
	server_reset_deadline_local = 0;
	last_server_reset_id = noone;
	server_shutdown_received = false;

	/* DNS requests and UDP ping-correlation records begin empty. The ping sequence
	starts at zero and increments with each request so replies can identify its send time */
	discovery_dns_requests = [];
	discovery_ping_requests = [];
	discovery_ping_sequence = 0;

	/* The client-owned browser status socket starts absent, with no official-list
	index assigned. next_index starts zero for round-robin probing. started/deadline
	are inactive current_time millisecond timestamps until a probe connects */
	status_probe_socket = noone;
	status_probe_official_index = noone;
	status_probe_next_index = 0;
	status_probe_started = 0;
	status_probe_deadline = 0;

	/* Optional diagnostics start off. Probes are spaced by one second and wait
	three seconds for a reply, using current_time milliseconds. next_at zero permits
	an immediate first eligible probe */
	network_diagnostics_enabled = false;
	latency_probe_interval_ms = 1000;
	latency_probe_timeout_ms = 3000;
	latency_probe_next_at = 0;

	/* Probe numbering starts at zero, with no pending sequence and no recorded send
	time. The sequence identifies replies and sent_at uses current_time milliseconds */
	latency_probe_sequence = 0;
	latency_probe_pending_sequence = noone;
	latency_probe_sent_at = 0;

	/* Sent, reply and timeout counters start with no samples. Consecutive timeouts
	also begin zero and exhausted starts false, allowing probes until the optional
	protocol stops after three unanswered requests */
	latency_probe_sent_count = 0;
	latency_probe_reply_count = 0;
	latency_probe_timeout_count = 0;
	latency_probe_consecutive_timeouts = 0;
	latency_probe_exhausted = false;

	/* Round-trip measurements start at -1 to display as unavailable. The current,
	smoothed average, previous sample, jitter and minimum/maximum all use milliseconds.
	Matching replies populate them, and diagnostics reset restores the sentinel */
	latency_rtt_ms = -1;
	latency_rtt_average_ms = -1;
	latency_rtt_previous_ms = -1;
	latency_rtt_jitter_ms = -1;
	latency_rtt_min_ms = -1;
	latency_rtt_max_ms = -1;

	/* Reported server diagnostics start unavailable at -1. Last/average/peak tick
	work and maximum loop gap use milliseconds, tick_rate uses Hz, server_fps is frames
	per second and snapshot_interval is milliseconds. The build label starts empty */
	latency_server_tick_ms = -1;
	latency_server_tick_average_ms = -1;
	latency_server_tick_peak_ms = -1;
	latency_server_tick_rate_hz = -1;
	latency_server_tick_max_gap_ms = -1;
	latency_server_fps = -1;
	latency_server_snapshot_interval_ms = -1;
	latency_server_build = "";

	/* No movement relays have been sampled. last_at starts zero on current_time.
	Last/average/peak/previous intervals and jitter start -1 because no timing samples
	exist, while active_interval_count starts zero for smoothing initialization */
	movement_snapshot_count = 0;
	movement_snapshot_last_at = 0;
	movement_snapshot_interval_ms = -1;
	movement_snapshot_average_ms = -1;
	movement_snapshot_peak_interval_ms = -1;
	movement_snapshot_previous_interval_ms = -1;
	movement_snapshot_jitter_ms = -1;
	movement_snapshot_active_interval_count = 0;

	/* Latest and peak prediction distances start unavailable at -1 pixels.
	The signed authoritative-minus-predicted dx/dy offsets start zero. Safety-snap
	count starts zero and increments only when a correction reports a hard snap */
	movement_snapshot_last_error = -1;
	movement_snapshot_peak_error = -1;
	movement_snapshot_last_dx = 0;
	movement_snapshot_last_dy = 0;
	movement_snapshot_safety_snaps = 0;

	/* Client/relay moving flags begin false before samples arrive.
	has_server_position distinguishes missing relay coordinates from valid origin
	coordinates, while server_x/y start zero pixels */
	movement_snapshot_client_moving = false;
	movement_snapshot_server_moving = false;
	movement_snapshot_has_server_position = false;
	movement_snapshot_server_x = 0;
	movement_snapshot_server_y = 0;

	/* The desktop owner credential is read from this sandbox INI and credential
	section. It is not embedded in gameplay packets or copied into comments */
	admin_credentials_file = "official_server_admin.ini";
	admin_credentials_section = "credential";

	/* Credential version zero and empty server/key/token fields mean no credential
	is loaded. valid starts false and the error text explains that owner access is
	uninstalled until load_admin_credentials verifies the file */
	admin_credential_version = 0;
	admin_credential_server = "";
	admin_credential_key_id = "";
	admin_credential_token = "";
	admin_credential_valid = false;
	admin_credential_error = "Owner credential not installed.";

	/* Admin access begins unrequested, ineligible and unauthenticated. Intent comes
	from an official-list selection, eligibility verifies the trusted endpoint, and
	authenticated becomes true only after a server reply */
	admin_connection_intent = false;
	admin_eligible = false;
	admin_authenticated = false;

	/* Authentication and command requests begin idle, with inactive zero deadlines
	on current_time milliseconds. Status refresh begins idle with request ID zero and
	no deadline, so no response is yet being awaited */
	admin_auth_pending = false;
	admin_auth_deadline = 0;
	admin_command_pending = false;
	admin_command_deadline = 0;
	admin_status_refresh_pending = false;
	admin_status_refresh_request_id = 0;
	admin_status_refresh_deadline = 0;

	/* Admin correlation numbering starts zero before the first generated request.
	No last request/action/result exists, represented by zero or noone. Message text
	starts empty and last_result_at zero means no timed result has been recorded */
	admin_request_sequence = 0;
	admin_last_request_id = 0;
	admin_last_action = noone;
	admin_last_result_code = noone;
	admin_last_result_message = "";
	admin_last_result_at = 0;

	/* Admin status has not arrived. Reset policy starts disabled with zero minutes
	and seconds, connected/capacity counts start zero, restart starts false and the
	server message empty. Accepted status replies replace these placeholders */
	admin_status_known = false;
	admin_reset_enabled = false;
	admin_reset_interval_minutes = 0;
	admin_reset_remaining_seconds = 0;
	admin_connected_players = 0;
	admin_max_players = 0;
	admin_restart_in_progress = false;
	admin_server_message = "";

	/* This client-owned transfer state receives its owner so log downloads can use
	the authenticated session and report progress. Session reset cancels active transfers */
	admin_logs = new scr_admin_log_download(self);
	#endregion /* Client State END */

	#region /* Remote Admin Credentials and Requests */
	/// @description Validate a nonempty credential field against its permitted alphabet
	/// @param {Any} value Credential field to convert to text
	/// @param {String} allowed_characters Complete accepted character set
	/// @returns {Bool} Whether every character is allowed
	admin_string_uses_only = function(value, allowed_characters)
	{
		/* Convert the candidate credential field to text before checking its permitted
		character alphabet */
		var text = string(value);

		/* Empty credential text cannot identify a key or token. Reject it before the
		character scan, which would otherwise accept an empty loop */
		if (text == "")
		{
			return false;
		}

		/* Read every one-based credential character until the text ends. A disallowed
		character rejects the field immediately, while complete traversal accepts it */
		for (var i = 1; i <= string_length(text); i++)
		{
			/* A character outside the permitted alphabet makes this credential invalid.
			Return false before allowing that value into an authentication request */
			if (string_pos(string_char_at(text, i), allowed_characters) <= 0)
			{
				return false;
			}
		}

		return true;
	}

	/// @description Load and validate the desktop owner credential from the sandbox INI
	/// @returns {Bool} Whether the credential matches the supported protocol and official hostname
	load_admin_credentials = function()
	{
		admin_credential_version = 0;
		admin_credential_server = "";
		admin_credential_key_id = "";
		admin_credential_token = "";
		admin_credential_valid = false;
		admin_credential_error = "Owner credential not installed.";

		/* Browser builds do not load the desktop credential file. A missing native
		file also leaves access disabled, avoiding an attempted read without credentials */
		if (net.is_browser_runtime() || !file_exists(admin_credentials_file))
		{
			return false;
		}

		/* Track whether this function has opened the INI so exception cleanup closes
		only a file whose open succeeded */
		var credential_file_open = false;
		try
		{
			ini_open(admin_credentials_file);
			credential_file_open = true;
			admin_credential_version = floor(ini_read_real(admin_credentials_section, "version", 0));
			admin_credential_server = string_lower(string_trim(ini_read_string(admin_credentials_section, "server", "")));
			admin_credential_key_id = string_trim(ini_read_string(admin_credentials_section, "key_id", ""));
			admin_credential_token = string_trim(ini_read_string(admin_credentials_section, "token", ""));
			ini_close();
			credential_file_open = false;
		}
		catch(e)
		{
			/* If a read failed after opening, attempt to close the INI before clearing
			credential fields. Failures before opening need no close */
			if (credential_file_open)
			{
				try { ini_close(); } catch(close_error) { }
			}
			admin_credential_version = 0;
			admin_credential_server = "";
			admin_credential_key_id = "";
			admin_credential_token = "";
			admin_credential_error = "Owner credential could not be read.";
			return false;
		}

		/* key_length and token_length measure credential characters before checking
		supported protocol, exact official hostname, size bounds and allowed alphabets */
		var key_length = string_length(admin_credential_key_id);
		var token_length = string_length(admin_credential_token);

		/* Reject any unsupported version, different official hostname, out-of-bounds
		key/token length or disallowed character. Clear all credential values so malformed
		files cannot leave partially usable owner access */
		if (admin_credential_version != ADMIN_PROTOCOL_VERSION
		|| admin_credential_server != "online.jonnil.games"
		|| key_length < 1
		|| key_length > 128
		|| token_length < 32
		|| token_length > 512
		|| !admin_string_uses_only(admin_credential_key_id, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
		|| !admin_string_uses_only(admin_credential_token, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.="))
		{
			admin_credential_version = 0;
			admin_credential_server = "";
			admin_credential_key_id = "";
			admin_credential_token = "";
			admin_credential_error = "Owner credential is invalid.";
			return false;
		}

		admin_credential_valid = true;
		admin_credential_error = "";
		return true;
	}

	/// @description Cancel active log transfer and clear authentication, request waits and cached admin status
	reset_admin_session = function()
	{
		/* A disconnect must interrupt an active log export before authentication state
		is cleared. Inactive transfers need no interruption message */
		if (admin_logs.active)
		{
			admin_logs.fail("Server log download interrupted by disconnect.", false);
		}
		admin_eligible = false;
		admin_authenticated = false;
		admin_auth_pending = false;
		admin_auth_deadline = 0;
		admin_command_pending = false;
		admin_command_deadline = 0;
		admin_status_refresh_pending = false;
		admin_status_refresh_request_id = 0;
		admin_status_refresh_deadline = 0;
		admin_request_sequence = 0;
		admin_last_request_id = 0;
		admin_last_action = noone;
		admin_last_result_code = noone;
		admin_last_result_message = "";
		admin_last_result_at = 0;
		admin_status_known = false;
		admin_reset_enabled = false;
		admin_reset_interval_minutes = 0;
		admin_reset_remaining_seconds = 0;
		admin_connected_players = 0;
		admin_max_players = 0;
		admin_restart_in_progress = false;
		admin_server_message = "";
	}

	/// @description Allow credentials only on the exact configured secure official WebSocket endpoint
	/// @param {String} target_url Connection URL to check
	/// @param {Real} target_port Remote port
	/// @param {Real} target_transport Selected TRANSPORT value
	/// @returns {Bool} Whether the valid owner credential may be sent to this target
	is_trusted_admin_target = function(target_url, target_port, target_transport)
	{
		/* Credentials may be sent only when a validated official-host credential and
		WebSocket transport are both present. Other targets keep owner access disabled */
		if (!admin_credential_valid
		|| admin_credential_server != "online.jonnil.games"
		|| target_transport != TRANSPORT_WS)
		{
			return false;
		}

		/* trusted parses the configured official gameplay endpoint. It supplies the
		exact URL/port that must match before any credential can be sent */
		var trusted = net.parse_server_address(net.public_websocket_address, net.websocket_public_port, TRANSPORT_WS);

		/* The configured trusted endpoint must parse successfully and use wss.
		An invalid or unencrypted configured route cannot receive owner credentials */
		if (!trusted.ok
		|| !net.text_starts_with(string_lower(trusted.address), "wss://"))
		{
			return false;
		}

		/* Require the same case-normalized endpoint URL and numeric port. Matching
		only a hostname would permit a different route to receive the credential */
		return string_lower(string(target_url)) == string_lower(string(trusted.url))
			&& floor(real(target_port)) == trusted.port;
	}

	/// @description Advance positive admin request numbering, wrapping above its chosen limit
	/// @returns {Real} Nonzero correlation ID
	next_admin_request_id = function()
	{
		admin_request_sequence++;

		/* Keep request IDs positive within the chosen sequence range, wrapping to one
		rather than allowing zero to mean a valid pending request */
		if (admin_request_sequence <= 0 || admin_request_sequence > 4000000000)
		{
			admin_request_sequence = 1;
		}
		return admin_request_sequence;
	}

	/// @description Authenticate an eligible joined session and start its ten-second reply deadline
	/// @returns {Bool} Whether the authentication request was sent
	send_admin_auth = function()
	{
		/* Authenticate only an eligible, joined client with a valid socket and neither
		an authenticated nor pending auth session. Otherwise skip duplicate/unsafe requests */
		if (!admin_eligible
		|| admin_authenticated
		|| admin_auth_pending
		|| ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return false;
		}

		/* Generate the nonzero correlation ID echoed by the auth reply. The ten-second
		current_time deadline starts only after a successful send */
		var request_id = next_admin_request_id();
		net.start(N_ADMIN_AUTH, ID);
		net.write(buffer_u8, ADMIN_PROTOCOL_VERSION);
		net.write(buffer_u32, request_id);
		net.write(buffer_string, admin_credential_key_id);
		net.write(buffer_string, admin_credential_token);

		/* The auth send result indicates whether a reply can be awaited. A negative
		result records immediate failure instead of starting a pending auth deadline */
		var send_result = net.send_server();

		/* Failed or partial sends cannot authenticate this session. Store visible
		failure feedback and return false without marking the request pending */
		if (send_result < 0)
		{
			admin_last_result_code = ADMIN_RESULT_FAILED;
			admin_last_result_message = "Could not authenticate remote server controls.";
			admin_last_result_at = current_time;
			return false;
		}

		admin_auth_pending = true;
		admin_auth_deadline = current_time + 10000;
		admin_last_request_id = request_id;
		admin_last_action = ADMIN_ACTION_AUTH;
		return true;
	}

	/// @description Send a serialized remote-admin action after authentication and track its reply
	/// @param {Real} action ADMIN_ACTION value
	/// @param {Any} value Action value, defaulting to undefined for valueless actions. Intervals are minutes and limits are player counts
	/// @returns {Bool} Whether the command passed the client guards and was sent
	send_admin_command = function(action, value = undefined)
	{
		/* Commands require eligible authenticated gameplay and a valid socket.
		A pending command or visible status refresh serializes operations, preventing
		new requests from overwriting the correlation state */
		if (!admin_eligible
		|| !admin_authenticated
		|| admin_command_pending
		|| admin_status_refresh_pending
		|| ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return false;
		}

		/* Admit the supported status-through-wall-policy actions so the wall toggle
		can reach its existing serializer and authenticated server handler. Authentication
		has its own request path, and values outside the command range are rejected */
		if (action < ADMIN_ACTION_STATUS || action > ADMIN_ACTION_SET_WALL_DRAWING)
		{
			return false;
		}

		/* Use a new correlation ID for the command so its result can be matched to
		this pending operation */
		var request_id = next_admin_request_id();
		net.start(N_ADMIN_COMMAND, ID);
		net.write(buffer_u8, ADMIN_PROTOCOL_VERSION);
		net.write(buffer_u32, request_id);
		net.write(buffer_u8, action);

		/* Boolean policy actions encode one only for true or numeric one, otherwise
		zero. Other actions select their own value format or carry no value */
		if (action == ADMIN_ACTION_SET_RESET_ENABLED || action == ADMIN_ACTION_SET_WALL_DRAWING)
		{
			net.write(buffer_u8, value == true || value == 1 ? 1 : 0);
		}

		/* Reset periods carry whole minutes clamped to 15 through 1,440 before writing
		a two-byte setting value */
		else if (action == ADMIN_ACTION_SET_RESET_INTERVAL)
		{
			net.write(buffer_u16, clamp(floor(real(value)), 15, 1440));
		}

		/* Player limits carry a whole count clamped to the network player-limit range.
		Actions with no matching value branch keep only their command header */
		else if (action == ADMIN_ACTION_SET_MAX_PLAYERS)
		{
			net.write(buffer_u16, clamp(floor(real(value)), net.min_player_limit, net.max_player_limit));
		}

		/* The command result controls whether to start its ten-second response wait.
		A failed send produces immediate feedback and leaves command_pending false */
		var send_result = net.send_server();

		/* A transport failure cannot produce a reliably correlated reply. Record the
		failure now instead of starting a command deadline */
		if (send_result < 0)
		{
			admin_last_result_code = ADMIN_RESULT_FAILED;
			admin_last_result_message = "Could not send the remote server command.";
			admin_last_result_at = current_time;
			return false;
		}

		admin_last_request_id = request_id;
		admin_last_action = action;
		admin_last_result_message = "Waiting for the server...";
		admin_command_pending = true;
		admin_command_deadline = current_time + 10000;
		return true;
	}

	/// @description Request authenticated status with optional tracked refresh feedback
	/// @param {Bool} show_feedback Whether to track visible refresh progress, defaulting to false
	/// @returns {Bool} Whether the query was sent
	request_admin_status = function(show_feedback = false)
	{
		/* Status reads require eligible authenticated gameplay and a valid socket.
		Pending commands block reads. Visible refreshes additionally block a second
		visible refresh, while background refreshes may proceed without feedback state */
		if (!admin_eligible
		|| !admin_authenticated
		|| admin_command_pending
		|| (show_feedback && admin_status_refresh_pending)
		|| ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return false;
		}

		/* The status correlation ID identifies a visible refresh response when
		show_feedback is true. Background requests do not replace feedback tracking */
		var request_id = next_admin_request_id();
		net.start(N_ADMIN_STATUS, ID);
		net.write(buffer_u8, ADMIN_PROTOCOL_VERSION);
		net.write(buffer_u32, request_id);

		/* The status send result determines whether a refresh was initiated at all.
		Failure returns false regardless of whether UI feedback was requested */
		var send_result = net.send_server();

		/* A failed status send cannot refresh server data. Optional feedback records
		its failure, while background calls leave the existing result message alone */
		if (send_result < 0)
		{
			/* Visible refresh calls publish the failed-send result. Background polling
			returns failure without overwriting user-facing command feedback */
			if (show_feedback)
			{
				admin_last_result_code = ADMIN_RESULT_FAILED;
				admin_last_result_message = "Could not refresh the server status.";
				admin_last_result_at = current_time;
			}
			return false;
		}

		/* Only a visible successful refresh gets a pending request ID, ten-second
		current_time deadline and refreshing message. Background reads just await normal
		status application */
		if (show_feedback)
		{
			admin_status_refresh_pending = true;
			admin_status_refresh_request_id = request_id;
			admin_status_refresh_deadline = current_time + 10000;
			admin_last_result_code = noone;
			admin_last_result_message = "Refreshing server status...";
			admin_last_result_at = current_time;
		}
		return true;
	}

	/// @description Request the server automatic-reset policy
	/// @param {Bool} enabled Desired reset state
	/// @returns {Bool} Whether the command was sent
	set_admin_reset_enabled = function(enabled)
	{
		return send_admin_command(ADMIN_ACTION_SET_RESET_ENABLED, enabled);
	}

	/// @description Request a bounded server reset period
	/// @param {Real} minutes Desired period in minutes
	/// @returns {Bool} Whether the command was sent
	set_admin_reset_interval = function(minutes)
	{
		return send_admin_command(ADMIN_ACTION_SET_RESET_INTERVAL, minutes);
	}

	/// @description Request the bounded server gameplay capacity
	/// @param {Real} players Desired player count
	/// @returns {Bool} Whether the command was sent
	set_admin_max_players = function(players)
	{
		return send_admin_command(ADMIN_ACTION_SET_MAX_PLAYERS, players);
	}

	/// @description Request the authenticated server wall-drawing policy
	/// @param {Bool} enabled Desired wall-drawing state
	/// @returns {Bool} Whether the command was sent
	set_admin_wall_drawing = function(enabled)
	{
		return send_admin_command(ADMIN_ACTION_SET_WALL_DRAWING, enabled);
	}

	/// @description Request an immediate authenticated drawing reset
	/// @returns {Bool} Whether the command was sent
	request_admin_reset_now = function()
	{
		return send_admin_command(ADMIN_ACTION_RESET_NOW);
	}

	/// @description Request an authenticated server restart
	/// @returns {Bool} Whether the command was sent
	request_admin_force_restart = function()
	{
		return send_admin_command(ADMIN_ACTION_FORCE_RESTART);
	}

	/// @description Apply a protocol-compatible correlated admin outcome and clear its wait
	/// @param {Real} protocol_version Received ADMIN_PROTOCOL_VERSION
	/// @param {Real} request_id Correlation ID echoed by the server
	/// @param {Real} action Completed ADMIN_ACTION value
	/// @param {Real} result_code ADMIN_RESULT outcome
	/// @param {String} message Visible server feedback
	/// @returns {Bool} Whether the outcome matched eligible request state
	receive_admin_result = function(protocol_version, request_id, action, result_code, message)
	{
		/* Ignore results for an ineligible session or unsupported admin layout.
		They cannot establish valid authentication or complete a current request */
		if (!admin_eligible || protocol_version != ADMIN_PROTOCOL_VERSION)
		{
			return false;
		}

		/* Authentication results must match an outstanding auth request ID.
		Ignore unsolicited or stale auth replies before changing session access */
		if (action == ADMIN_ACTION_AUTH
		&& (!admin_auth_pending || request_id != admin_last_request_id))
		{
			return false;
		}

		/* Identify a visible status refresh only when action, pending flag and request
		ID all match. Other results continue through the authenticated-command checks */
		var is_status_refresh_result = action == ADMIN_ACTION_STATUS
			&& admin_status_refresh_pending
			&& request_id == admin_status_refresh_request_id;

		/* Non-auth results need either the matched visible refresh or an authenticated
		session whose last request ID matches. Ignore other results so stale replies cannot
		clear a newer operation */
		if (action != ADMIN_ACTION_AUTH
		&& !is_status_refresh_result
		&& (!admin_authenticated || request_id != admin_last_request_id))
		{
			return false;
		}

		admin_last_request_id = request_id;
		admin_last_action = action;
		admin_last_result_code = result_code;
		admin_last_result_message = string(message);
		admin_last_result_at = current_time;

		/* An auth outcome ends its deadline and grants access only for ADMIN_RESULT_OK.
		Failed authentication also invalidates cached authenticated server status */
		if (action == ADMIN_ACTION_AUTH)
		{
			admin_auth_pending = false;
			admin_auth_deadline = 0;
			admin_authenticated = result_code == ADMIN_RESULT_OK;

			/* Failed authentication means the previous admin status is no longer usable.
			Successful authentication leaves its known-status flag as it stood */
			if (!admin_authenticated)
			{
				admin_status_known = false;
			}
		}

		/* A matched status refresh result clears only refresh tracking, preserving any
		separate command state */
		else if (is_status_refresh_result)
		{
			admin_status_refresh_pending = false;
			admin_status_refresh_request_id = 0;
			admin_status_refresh_deadline = 0;
		}

		/* Remaining matched command outcomes end the command wait. They do not change
		auth or refresh tracking because those actions used their earlier branches */
		else
		{
			admin_command_pending = false;
			admin_command_deadline = 0;
		}
		return true;
	}

	/// @description Apply compatible admin status and synchronize client lifecycle display
	/// @param {Real} protocol_version Received admin protocol version
	/// @param {Real} request_id Status correlation ID
	/// @param {Bool} authenticated Server authentication flag, also accepting numeric one
	/// @param {Bool} reset_enabled Automatic-reset flag, also accepting numeric one
	/// @param {Real} reset_interval_minutes Configured reset period in minutes
	/// @param {Real} reset_remaining_seconds Reset countdown in seconds
	/// @param {Real} connected_players Current gameplay count
	/// @param {Real} max_players Reported gameplay capacity, bounded by the client setter
	/// @param {Bool} restart_in_progress Restart flag, also accepting numeric one
	/// @param {String} server_message Server status feedback
	/// @returns {Bool} Whether compatible eligible status was applied
	receive_admin_status = function(protocol_version, request_id, authenticated, reset_enabled, reset_interval_minutes, reset_remaining_seconds, connected_players, max_players, restart_in_progress, server_message)
	{
		/* Unsupported or ineligible status replies are ignored before mutating admin
		or lifecycle UI state */
		if (protocol_version != ADMIN_PROTOCOL_VERSION || !admin_eligible)
		{
			return false;
		}

		/* Wire flags accept true or numeric one for authenticated, reset enabled and
		restart state. Other values become false. Status counts/times are normalized
		nonnegative, with gameplay capacity passed through its bounded setter */
		admin_authenticated = authenticated == true || authenticated == 1;
		admin_auth_pending = false;
		admin_auth_deadline = 0;
		admin_status_known = admin_authenticated;
		admin_reset_enabled = reset_enabled == true || reset_enabled == 1;
		admin_reset_interval_minutes = max(0, floor(real(reset_interval_minutes)));
		admin_reset_remaining_seconds = max(0, floor(real(reset_remaining_seconds)));
		admin_connected_players = max(0, floor(real(connected_players)));
		apply_server_player_limit(max_players);
		admin_max_players = server_max_players;
		admin_restart_in_progress = restart_in_progress == true || restart_in_progress == 1;
		admin_server_message = string(server_message);

		/* Complete visible refresh feedback only when its pending ID matches.
		Other valid status updates still refresh data without claiming that request completed */
		if (admin_status_refresh_pending && request_id == admin_status_refresh_request_id)
		{
			admin_status_refresh_pending = false;
			admin_status_refresh_request_id = 0;
			admin_status_refresh_deadline = 0;
			admin_last_result_code = ADMIN_RESULT_OK;
			admin_last_result_message = "Server status refreshed.";
			admin_last_result_at = current_time;
		}
		apply_server_lifecycle_status(admin_reset_enabled, admin_reset_interval_minutes, admin_reset_remaining_seconds);
		return true;
	}

	load_admin_credentials();
	#endregion /* Remote Admin Credentials and Requests END */

	#region /* Client Connection Lifecycle */
	/// @description Replace the outgoing connection. Host & Play retains authoritative players and collision state
	/// @param {String} _url Host or WebSocket URL, defaulting to undefined to retain net.url
	/// @param {Real} _port Remote port, defaulting to undefined to retain net.port
	/// @param {Real} _transport TRANSPORT value. undefined chooses the runtime default
	/// @param {String} _display_address UI label, defaulting to host:port when undefined
	/// @param {String} _requested_username Username filtered before joining. undefined defaults to empty
	/// @param {Bool} _local_host_mode Whether this client shares its hosted server, defaulting to false
	/// @param {Bool} _admin_intent Whether official selection requested remote-admin access, defaulting to false
	/// @returns {Real} Socket creation or connection result. Joining completes asynchronously
	init = function(_url = undefined, _port = undefined, _transport = undefined, _display_address = undefined, _requested_username = undefined, _local_host_mode = false, _admin_intent = false)
	{
		singleplayer_mode = false;

		/* Only an explicit true enables local-host sharing. Admin connection intent
		also requires true, keeping ordinary joins from requesting owner access */
		local_host_mode = _local_host_mode == true;
		admin_connection_intent = _admin_intent == true;
		reset_admin_session();
		needs_server_list = false;
		connect_failed_message = "";
		ID = noone;
		host_player_slot = noone;
		assigned_username = "";
		join_request_sent = false;

		/* An omitted username uses empty text so the server may assign its fallback.
		Supplied text is filtered before the join request */
		requested_username = is_undefined(_requested_username) ? "" : chat_filter_username_input(_requested_username);

		/* Borrow chat to clear the previous connection identity and session display.
		Local-host cleanup preserves the server export history */
		var chat = scr_get_chat();
		chat.assigned_username = "";

		/* Remote connections clear prior messages, indicators and collision state.
		A shared local server uses the separate visible-chat path to retain its world */
		if (!local_host_mode)
		{
			chat.clear_messages();
			chat.clear_typing_states(false);
			chat.clear_afk_states();
			scr_get_collision_objects().reset_client();
		}

		/* Hosting in this process keeps the authoritative export history. Clear the
		visible chat when supported, then reset client typing/AFK presentation */
		else
		{
			/* Use visible-only clearing when available so the local host does not erase
			the server chat export. Missing support leaves visible history unchanged */
			if (variable_struct_exists(chat, "clear_visible_messages"))
			{
				chat.clear_visible_messages();
			}
			chat.clear_typing_states(false);
			chat.clear_afk_states();
		}
		scr_get_drawing().reset_client();

		/* A supplied URL replaces the network connection host. Omitting it preserves
		the previously configured target */
		if (!is_undefined(_url))
		{
			net.url = _url;
		}

		/* A supplied port replaces the connection port. Otherwise retain the current
		network port rather than erasing it with undefined */
		if (!is_undefined(_port))
		{
			net.port = _port;
		}

		/* Select the runtime transport only when the caller omitted it. The display
		address similarly defaults to host:port unless supplied. Admin eligibility needs
		both explicit admin intent and an exact trusted secure target */
		transport = is_undefined(_transport) ? net.default_client_transport() : _transport;
		connect_address = is_undefined(_display_address) ? net.url + ":" + string(net.port) : string(_display_address);
		admin_eligible = admin_connection_intent && is_trusted_admin_target(net.url, net.port, transport);
		connect_pending = false;
		connect_deadline = 0;
		last_server_heard = current_time;
		server_max_players = net.default_max_players;
		wall_drawing_supported = false;
		wall_drawing_enabled = false;
		scr_get_walls().reset_client();
		server_reset_status_known = false;
		server_reset_enabled = false;
		server_reset_interval_minutes = 0;
		server_reset_deadline_local = 0;
		last_server_reset_id = noone;
		server_shutdown_received = false;
		reset_network_diagnostics();

		/* Release a previous valid gameplay socket before creating its replacement,
		including its transport registration. Absent or failed handles need no destroy */
		if (is_real(socket) && socket >= 0)
		{
			net.unregister_socket_transport(socket);
			network_destroy(socket);
		}

		socket = network_create_socket(net.socket_type_for_transport(transport, net.url));

		/* A negative socket creation result cannot begin a connection. Preserve that
		result locally before failure cleanup replaces the stored handle */
		if (socket < 0)
		{
			/* Save the original negative creation result for the caller while
			fail_pending_connect cleans the client-owned socket state */
			var create_result = socket;
			fail_pending_connect("Failed to create " + net.transport_to_string(transport) + " client socket.");
			return create_result;
		}

		net.register_socket_transport(socket, transport);

		/* connect_result reports whether transport connection startup succeeded.
		Async transports still need their completion event and later join response */
		var connect_result = net.connect(socket, net.url, net.port, transport);
		connect_status = "Connecting to " + connect_address;
		debug_log("Client init: connecting to " + connect_address + " using " + net.transport_to_string(transport) + " socket " + string(socket));
		debug_log("Client connect result: " + string(connect_result));

		/* Connection startup failure ends the pending session immediately. Return the
		transport error instead of starting a deadline for an event that cannot succeed */
		if (connect_result < 0)
		{
			fail_pending_connect("Failed to connect to " + connect_address);
			return connect_result;
		}

		connect_pending = true;
		connect_deadline = current_time + net.connect_timeout_ms;

		/* UDP connection completes through its synchronous path, so send the join now.
		TCP and WebSocket wait for their async connection event */
		if (transport == TRANSPORT_UDP)
		{
			complete_socket_connect();
		}

		/* Async transports defer join submission until a successful connection event.
		Keeping it pending allows the connection watchdog to enforce the deadline */
		else
		{
			debug_log("Waiting for " + net.transport_to_string(transport) + " async connect result from " + connect_address);
		}

		return connect_result;
	}

	/// @description Send the join request once after a successful socket connection event
	/// @returns {Bool} Whether this event advanced a pending, unjoined session
	complete_socket_connect = function()
	{
		/* Only a pending unjoined connection advances to join submission. Duplicate
		completion events cannot restart the deadline or replace an assigned player ID */
		if (!connect_pending || join_request_sent || ID != noone)
		{
			return false;
		}

		connect_deadline = current_time + net.connect_timeout_ms;
		connect_status = "Connected. Waiting for server response...";
		debug_success("Client connected on socket " + string(socket));
		send_join_request();
		return true;
	}

	/// @description Send gameplay version:u16, requested username:string, then the character manifest
	/// @returns {Real} Send result, 0 when already sent, or -1 without a valid socket
	send_join_request = function()
	{
		/* A join request already submitted returns zero without sending again.
		This keeps duplicate connection events from producing duplicate joins */
		if (join_request_sent)
		{
			return 0;
		}

		/* A missing or failed gameplay socket cannot carry a join. Return -1 before
		building a packet or consuming its one-shot flag */
		if (!is_real(socket) || socket < 0)
		{
			debug_error("Cannot send join request without a valid client socket.");
			return -1;
		}

		join_request_sent = true;

		/* Borrow the character registry and capture selected metadata without embedding
		the Base64 PNG payload. Custom bytes are transferred separately after joining */
		var character_registry = scr_get_player_characters();
		var character_manifest = character_registry.selected_manifest(false);
		net.start(N_JOIN_GAME_VERSIONED, noone);
		net.write(buffer_u16, GAMEPLAY_PROTOCOL_VERSION);
		net.write(buffer_string, requested_username);
		character_registry.write_manifest(net, character_manifest);

		/* The join send result determines whether the pending connection remains
		viable. A failure invokes cleanup, while a sent request waits for N_ID */
		var send_result = net.send_server();

		/* A failed/partial join send cannot yield a reliable accepted session.
		Fail the pending connection rather than waiting for its response */
		if (send_result < 0)
		{
			fail_pending_connect("Could not request join from " + connect_address);
		}

		return send_result;
	}

	/// @description Announce an independent pet selection and reuse custom-character image chunks
	/// @param {String} key Installed appearance key, or empty for no pet
	/// @returns {Real} Send result, zero without an assigned multiplayer connection, or -1 on failure
	send_player_pet = function(key)
	{
		/* Pet announcements need the assigned connection. Singleplayer keeps its pet
		selection locally without creating network packets */
		if (ID == noone || singleplayer_mode || !is_real(socket) || socket < 0)
		{
			return 0;
		}

		/* Rapid card changes replace the pending choice instead of uploading every
		intermediate sheet. The watchdog sends the latest choice when its turn arrives */
		pet_requested_key = string_trim(string(key));
		pet_send_pending = true;
		if (current_time < pet_send_next_at) return 0;
		pet_send_pending = false;
		pet_send_next_at = current_time + pet_send_interval_ms;

		/* registry supplies the shared image identity and payload. Empty keys remove
		the pet, so no character fallback manifest is serialized for removal */
		var registry = scr_get_player_characters();
		var equipped = string_trim(string(key)) != "";
		var manifest = equipped ? registry.manifest_for_key(key, true) : noone;
		net.start(N_PLAYER_PET, ID);
		net.write(buffer_u8, equipped ? 1 : 0);
		if (equipped) registry.write_manifest(net, manifest);

		/* Only metadata travels before approval. A retained older pet means the server
		is still waiting for upload capacity, so rejected retries carry no image bytes */
		var send_result = net.send_server();
		var local_player = player_controller_get_player(ID, false);
		var shared_character_sheet = equipped && local_player != noone
			&& variable_struct_exists(local_player, "character_key")
			&& local_player.character_key == manifest.network_key;

		/* The live player key identifies artwork already announced as its character.
		A changed package on disk can have a newer hash and still need its pet upload */
		if (send_result >= 0 && equipped && manifest.custom
		&& !shared_character_sheet
		&& (pet_approved_key != manifest.network_key || pet_upload_sent_key != manifest.network_key))
		{
			pet_pending_upload_manifest = manifest;
		}
		else
		{
			pet_pending_upload_manifest = noone;
		}

		/* A failed announcement ends the unreliable session through
		the same transport-loss path used by player character changes */
		if (send_result < 0) mark_connection_lost("Lost connection to server.");
		return send_result;
	}

	/// @description Retry the latest pet choice when the server retains an older selection
	/// @param {Real} owner_id Logical owner acknowledged by the server
	/// @param {Struct|Real} manifest Approved image metadata, or noone for removal
	acknowledge_player_pet = function(owner_id, manifest)
	{
		/* Other owners' pets don't acknowledge this client's request. Local replies
		compare network identities because saved keys may use a local package basename */
		if (owner_id != ID) return;
		var registry = scr_get_player_characters();
		var requested_manifest = pet_requested_key == ""
			? noone : registry.manifest_for_key(pet_requested_key, false);
		var requested_network_key = is_struct(requested_manifest) ? requested_manifest.network_key : "";
		var approved_key = is_struct(manifest) ? manifest.network_key : "";
		pet_approved_key = approved_key;
		if (approved_key == "") pet_upload_sent_key = "";

		/* A retained older state can result from the server cooldown or an earlier
		request still in flight. Keep the latest choice queued until it is acknowledged */
		pet_send_pending = requested_network_key != approved_key;

		/* Metadata edits can keep the same sheet identity. Compare the display name,
		sharing policy and credits as serialized so an older cooldown reply cannot
		discard a newer name or permission change */
		if (!pet_send_pending && is_struct(requested_manifest) && is_struct(manifest))
		{
			/* Creator text and copy hashes use the same bounds and normalization as
			write_manifest. Missing optional values serialize as empty text */
			var requested_creator_name = requested_manifest.custom && variable_struct_exists(requested_manifest, "original_creator_name")
				? registry.metadata_text(requested_manifest.original_creator_name, 64) : "";
			var requested_creator_id = requested_manifest.custom && variable_struct_exists(requested_manifest, "original_creator_id")
				? registry.metadata_text(requested_manifest.original_creator_id, 64) : "";
			var requested_copy_hash = requested_manifest.custom && variable_struct_exists(requested_manifest, "copied_from_hash")
				? registry.optional_hash_key(requested_manifest.copied_from_hash) : "";
			var requested_temp_cache = !requested_manifest.custom
				|| (variable_struct_exists(requested_manifest, "allow_multiplayer_temp_cache")
					&& registry.metadata_bool(requested_manifest.allow_multiplayer_temp_cache, true));
			pet_send_pending = registry.manifest_allows_clone(requested_manifest) != registry.manifest_allows_clone(manifest)
				|| requested_temp_cache != manifest.allow_multiplayer_temp_cache
				|| string(requested_manifest.display_label) != manifest.display_label
				|| requested_creator_name != manifest.original_creator_name
				|| requested_creator_id != manifest.original_creator_id
				|| requested_copy_hash != manifest.copied_from_hash;
		}
		if (pet_send_pending) pet_send_next_at = max(pet_send_next_at, current_time + pet_send_interval_ms);

		/* An accepted latest manifest releases its queued sheet exactly once. Older
		acknowledgements leave the latest bytes waiting and cannot start a denied upload */
		if (!pet_send_pending && is_struct(pet_pending_upload_manifest)
		&& pet_pending_upload_manifest.network_key == approved_key)
		{
			var upload_manifest = pet_pending_upload_manifest;
			pet_pending_upload_manifest = noone;
			if (registry.send_character_chunks_to_server(upload_manifest) < 0)
			{
				mark_connection_lost("Lost connection to server.");
			}
			else
			{
				pet_upload_sent_key = approved_key;
			}
		}
	}

	/// @description Clear client-only state while preserving the in-process server world in Host & Play
	/// @returns {Bool} True when remote player/collision state was cleared. Returns false for the shared local server
	reset_disconnected_client_state = function()
	{
		pet_requested_key = "";
		pet_send_pending = false;
		pet_send_next_at = 0;
		pet_pending_upload_manifest = noone;
		pet_approved_key = "";
		pet_upload_sent_key = "";
		server_max_players = net.default_max_players;
		wall_drawing_supported = false;
		wall_drawing_enabled = false;
		scr_get_walls().reset_client();
		reset_network_diagnostics();

		/* A shared local server keeps its authoritative players/collision state.
		Reset client-facing chat and drawing state, then return false to report preservation */
		if (local_host_mode)
		{
			/* Borrow chat for visible-only host cleanup, retaining the server export history */
			var local_host_chat = scr_get_chat();

			/* Clear only the visible messages when supported. Missing capability keeps
			history rather than calling a nonexistent method */
			if (variable_struct_exists(local_host_chat, "clear_visible_messages"))
			{
				local_host_chat.clear_visible_messages();
			}
			local_host_chat.clear_typing_states(false);
			local_host_chat.clear_afk_states();
			scr_get_drawing().reset_client();
			return false;
		}

		player_controller_clear_players();
		scr_get_chat().clear_typing_states(false);
		scr_get_chat().clear_afk_states();
		scr_get_drawing().reset_client();
		scr_get_collision_objects().reset_client();
		return true;
	}

	/// @description Add chat without duplicating a local host server export line
	/// @param {Real} chat_type CHAT_TYPE presentation value
	/// @param {Real} sender_id Logical player slot or noone for system text
	/// @param {String} sender_name Display name
	/// @param {String} content Approved message text
	/// @param {String} sent_at Display timestamp, defaulting to empty for chat fallback handling
	add_received_chat_message = function(chat_type, sender_id, sender_name, content, sent_at = "")
	{
		/* Use the shared chat receiver. Remote clients record received export lines,
		while local hosts pass false because their server already recorded the same line */
		var chat = scr_get_chat();

		/* The in-process server records the authoritative export line before it sends
		this packet. Do not record that line a second time on the local client */
		chat.add_message(chat_type, sender_id, sender_name, content, sent_at, !local_host_mode);
	}

	/// @description Check the ordered identity, position, visual state, and character-manifest fields
	/// @param {Bool} with_drawing_author Require assignment author:u32 when true, defaulting to false for roster entries
	/// @returns {Bool} Whether the complete player entry fits the current packet
	can_read_player_entry = function(with_drawing_author = false)
	{
		/* fields lists the exact player-entry wire types: logical ID, signed pixel x/y,
		username, visual bytes and character manifest fields. The assignment-only author
		field is appended when requested before shared structural preflight */
		var fields = [TYPE_ID, TYPE_POSITION, TYPE_POSITION, buffer_string, buffer_u8, buffer_u8,
			buffer_string, buffer_string, buffer_string, buffer_string,
			buffer_u8, buffer_u32, buffer_u16, buffer_u8, buffer_u8,
			buffer_string, buffer_string, buffer_string];

		/* N_ID includes a drawing-author identity after the ordinary player fields.
		Other roster entries omit that field and validate only the base manifest */
		if (with_drawing_author) array_push(fields, buffer_u32);
		return net.can_read_fields(fields);
	}

	/// @description Notify the server that a joined client is leaving gameplay
	/// @returns {Real} Send result, or zero when there is no usable joined session
	send_leave_request = function()
	{
		/* Leaving needs an assigned player and a valid gameplay socket. Without either,
		return zero because there is no joined session to notify */
		if (ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return 0;
		}

		net.start(N_LEAVE_GAME, ID);
		return net.send_server();
	}

	/// @description Echo server heartbeat correlation and detect a failed reply send
	/// @param {Real} sequence Server heartbeat sequence
	/// @returns {Real} Send result, or zero without a joined valid socket
	send_heartbeat_pong = function(sequence)
	{
		/* Heartbeat replies require an assigned slot and a valid socket. An unjoined
		or disconnected client returns zero without building a reply */
		if (ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return 0;
		}

		net.start(N_HEARTBEAT_PONG, ID);
		net.write(buffer_u32, sequence);

		/* The heartbeat send result detects a broken gameplay connection.
		Successful replies keep the server liveness check satisfied */
		var send_result = net.send_server();

		/* A failed heartbeat send marks this client connection lost instead of keeping
		an apparently joined session with no working route to the server */
		if (send_result < 0)
		{
			mark_connection_lost("Lost connection to server.");
		}

		return send_result;
	}

	/// @description Clear local held movement and release every server action before interrupted input
	/// @returns {Bool} Whether local state was cleared or releases were attempted for a joined socket
	release_local_movement = function()
	{
		/* Without a joined logical ID there is no local movement state to release.
		Return false rather than looking up an unassigned player */
		if (ID == noone)
		{
			return false;
		}

		/* Find the existing local player without creating one. Its directional holds
		are cleared locally before any release packets are attempted */
		var player = player_controller_get_player(ID, false);

		/* An existing local player can stop immediately. Missing player state skips
		local changes while still allowing releases over a valid socket */
		if (player != noone)
		{
			player.left = 0;
			player.right = 0;
			player.up = 0;
			player.down = 0;

			/* Stop velocity-derived visual motion when the player supplies that setter.
			The directional hold flags were already cleared for older player shapes */
			if (variable_struct_exists(player, "set_motion_from_vector"))
			{
				player.set_motion_from_vector(0, 0);
			}
		}

		/* An unavailable socket cannot send release packets. Return whether local
		movement was cleared, preserving useful cleanup even after connection failure */
		if (!is_real(socket) || socket < 0)
		{
			return player != noone;
		}

		/* Visit movement actions from zero through the action-count limit and release
		each one, ensuring no server-side direction remains held after input is interrupted */
		for (var action_index = 0; action_index < PLAYER_INPUT_COUNT; action_index++)
		{
			net.start(N_KEY_RELEASE, ID);
			net.write(buffer_u8, scr_player_input_action_code(action_index));
			net.send_server();
		}

		/* An existing player with client-state sending also publishes a forced stopped
		snapshot. Other shapes rely on the legacy release packets already sent */
		if (player != noone
		&& variable_struct_exists(player, "send_client_player_state"))
		{
			player.send_client_player_state(true);
		}
		return true;
	}

	/// @description Close the outgoing socket and return client state to server selection
	/// @param {String} status_text Feedback after transition, defaulting to Disconnected from server.
	/// @param {Bool} notify_server Whether to send typing/leave notifications before cleanup, defaulting to true
	disconnect = function(status_text = "Disconnected from server.", notify_server = true)
	{
		singleplayer_mode = false;
		admin_connection_intent = false;
		reset_admin_session();

		/* Borrow chat to stop the local typing indicator before the session is closed.
		The optional notification is skipped for connection-loss cleanup */
		var chat = scr_get_chat();

		/* Notify the server that local typing stopped only while an intentional
		disconnect still has a usable route. Lost connections skip this traffic */
		if (notify_server)
		{
			chat.stop_local_typing(true);
		}

		/* Send the leave request only for an intentional notifying disconnect.
		Connection-loss and kick paths avoid sending to a broken/removed session */
		if (notify_server)
		{
			send_leave_request();
		}

		/* Release a valid owned gameplay socket and unregister its transport.
		Missing handles need no destruction, but all session identity is still cleared */
		if (is_real(socket) && socket >= 0)
		{
			net.unregister_socket_transport(socket);
			network_destroy(socket);
		}

		socket = noone;
		ID = noone;
		host_player_slot = noone;
		assigned_username = "";
		join_request_sent = false;
		connect_pending = false;
		connect_deadline = 0;
		connect_status = string(status_text);
		needs_server_list = true;
		reset_disconnected_client_state();
	}

	/// @description Disconnect without sending leave traffic and retain a visible failure reason
	/// @param {String} status_text Feedback, defaulting to Lost connection to server.
	mark_connection_lost = function(status_text = "Lost connection to server.")
	{
		disconnect(status_text, false);
		connect_failed_message = string(status_text);
	}

	/// @description Apply server removal without sending another leave request
	/// @param {String} status_text Removal feedback, defaulting to the generic kick message
	handle_server_kick = function(status_text = "You were kicked from the server.")
	{
		disconnect(status_text, false);
		connect_failed_message = string(status_text);
	}

	/// @description Release failed connection state and return to server selection
	/// @param {String} status_text Failure reason shown and logged
	fail_pending_connect = function(status_text)
	{
		singleplayer_mode = false;
		admin_connection_intent = false;
		reset_admin_session();
		connect_pending = false;
		connect_deadline = 0;
		connect_status = string(status_text);
		connect_failed_message = connect_status;
		needs_server_list = true;

		/* Failure cleanup unregisters and destroys an allocated gameplay socket.
		Absent handles are skipped before restoring unjoined state */
		if (is_real(socket) && socket >= 0)
		{
			net.unregister_socket_transport(socket);
			network_destroy(socket);
		}

		socket = noone;
		ID = noone;
		host_player_slot = noone;
		assigned_username = "";
		join_request_sent = false;
		reset_disconnected_client_state();
		debug_error(connect_status);
	}

	/// @description Fail a pending connection or join once its current_time deadline expires
	update_pending_connect = function()
	{
		/* Without a connection or join awaiting completion, there is no deadline to
		enforce. Leave established or idle sessions unchanged */
		if (!connect_pending)
		{
			return;
		}

		/* When the pending connection deadline expires on current_time milliseconds,
		fail the attempt and return to selection. Earlier calls keep waiting */
		if (current_time >= connect_deadline)
		{
			fail_pending_connect("Connection timed out: " + connect_address);
		}
	}

	/// @description Advance log-download and admin deadlines, then detect a silent joined server
	update_connection_watchdog = function()
	{
		admin_logs.tick();

		/* The server watchdog requires a joined slot and valid gameplay socket.
		Log-transfer ticking has already occurred, but disconnected sessions skip liveness
		and admin deadline checks */
		if (ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return;
		}

		/* Seed an unset last-heard timestamp with current_time so the watchdog does
		not report immediate silence from an uninitialized clock */
		if (last_server_heard <= 0)
		{
			last_server_heard = current_time;
		}

		/* Only a pending auth request with an active elapsed deadline times out.
		Clear its wait/access state and publish failure while leaving the gameplay session */
		if (admin_auth_pending
		&& admin_auth_deadline > 0
		&& current_time >= admin_auth_deadline)
		{
			admin_auth_pending = false;
			admin_auth_deadline = 0;
			admin_authenticated = false;
			admin_last_result_code = ADMIN_RESULT_FAILED;
			admin_last_result_message = "Remote server control authentication timed out.";
			admin_last_result_at = current_time;
		}

		/* Expire a pending command only after its active current_time deadline.
		Clear the wait and show the timeout without claiming the server action succeeded */
		if (admin_command_pending
		&& admin_command_deadline > 0
		&& current_time >= admin_command_deadline)
		{
			admin_command_pending = false;
			admin_command_deadline = 0;
			admin_last_result_code = ADMIN_RESULT_FAILED;
			admin_last_result_message = "The remote server command timed out.";
			admin_last_result_at = current_time;
		}

		/* A visible refresh with an elapsed active deadline clears its correlation
		state and reports timeout. Background status polling has no such feedback wait */
		if (admin_status_refresh_pending
		&& admin_status_refresh_deadline > 0
		&& current_time >= admin_status_refresh_deadline)
		{
			admin_status_refresh_pending = false;
			admin_status_refresh_request_id = 0;
			admin_status_refresh_deadline = 0;
			admin_last_result_code = ADMIN_RESULT_FAILED;
			admin_last_result_message = "The server status refresh timed out.";
			admin_last_result_at = current_time;
		}

		/* server_timeout_ms allows one interval beyond the missed-heartbeat limit
		before declaring silence, using elapsed current_time milliseconds */
		var server_timeout_ms = net.client_heartbeat_interval_ms * (net.client_heartbeat_missed_limit + 1);

		/* A joined server silent for the full watchdog interval is treated as lost.
		Disconnect and stop diagnostics work instead of displaying a stale live session */
		if (current_time - last_server_heard >= server_timeout_ms)
		{
			mark_connection_lost("Lost connection to server.");
			return;
		}

		/* Coalesce rapid Pet Card selections after connection work. Removal also
		uses the empty queued key, so it doesn't need a separate packet path */
		if (pet_send_pending && current_time >= pet_send_next_at)
		{
			send_player_pet(pet_requested_key);
		}
		update_network_diagnostics();
	}

	/// @description Convert the server countdown into a local current_time deadline
	/// @param {Bool} enabled Whether automatic reset is enabled
	/// @param {Real} interval_minutes Reset interval in minutes
	/// @param {Real} remaining_seconds Server countdown in seconds
	/// @returns {Bool} True after updating the local countdown
	apply_server_lifecycle_status = function(enabled, interval_minutes, remaining_seconds)
	{
		server_reset_status_known = true;

		/* Only true enables the local countdown. Convert the received remaining
		seconds to a current_time millisecond deadline when enabled, or use zero for
		an inactive deadline */
		server_reset_enabled = enabled == true;
		server_reset_interval_minutes = max(0, floor(real(interval_minutes)));
		server_reset_deadline_local = server_reset_enabled
			? current_time + max(0, real(remaining_seconds)) * 1000
			: 0;
		return true;
	}

	/// @description Normalize reported gameplay capacity within the network bounds
	/// @param {Real} max_players Reported player count limit
	/// @returns {Bool} True after assigning the bounded capacity
	apply_server_player_limit = function(max_players)
	{
		server_max_players = clamp(
			floor(real(max_players)),
			net.min_player_limit,
			net.max_player_limit
		);
		return true;
	}

	/// @description Read nonnegative local reset countdown from its millisecond deadline
	/// @returns {Real} Remaining whole seconds, or zero for unknown/disabled reset
	server_reset_remaining_seconds = function()
	{
		/* Unknown or disabled automatic reset has no active countdown. Return zero
		rather than deriving a misleading time from its inactive deadline */
		if (!server_reset_status_known || !server_reset_enabled)
		{
			return 0;
		}

		return max(0, ceil((server_reset_deadline_local - current_time) / 1000));
	}

	/// @description Format waiting, unlimited or active drawing-reset countdown
	/// @returns {String} Client lifecycle label
	server_reset_countdown_text = function()
	{
		/* Before the first server status, display waiting rather than implying reset
		is disabled or already due */
		if (!server_reset_status_known)
		{
			return "Drawing reset timer: Waiting for server";
		}

		/* Known disabled reset displays unlimited drawing time. Enabled status falls
		through to the live remaining-time clock */
		if (!server_reset_enabled)
		{
			return "Drawing reset timer: Unlimited";
		}

		return "Drawing reset in " + server_reset_clock_text(server_reset_remaining_seconds());
	}

	/// @description Archive once per reset ID before clearing local drawing and wall state
	/// @param {Real} reset_id Server reset sequence used to reject duplicate resets
	/// @param {String} reason Logged operation reason, defaulting to scheduled_reset
	/// @returns {Bool} Whether the local archive succeeded. False also marks a duplicate reset
	handle_server_drawing_reset = function(reset_id, reason = "scheduled_reset")
	{
		/* A duplicate reset ID has already been handled. Skip another archive/clear
		so repeated delivery cannot overwrite or empty a new client session canvas */
		if (last_server_reset_id == reset_id)
		{
			return false;
		}

		last_server_reset_id = reset_id;
		scr_get_walls().reset_client();
		scr_get_walls().set_client_enabled(wall_drawing_enabled);

		/* Borrow the drawing service and archive its current canvas before clearing.
		archived records whether the archive succeeded, but clearing still proceeds */
		var drawing = scr_get_drawing();
		var archived = drawing.save_automatic_archive("client_reset", "client");
		drawing.clear_client_drawing_state();

		/* A reset arriving during initial history replaces that server queue.
		Mark ordered completion so Step can finish synchronization after pending work clears */
		if (!drawing.client_history_sync_is_ready())
		{
			/* The ordered reset replaces join history, whose server-side queue is discarded.
			Let Step publish the authoritative empty canvas after pending work is clear */
			drawing.client_history_sync_completion_received = true;
		}
		debug_log("Handled server drawing reset " + string(reset_id) + " reason=" + string(reason) + " archive=" + string(archived));
		return archived;
	}

	/// @description Archive once, choose restart/shutdown feedback and disconnect the session
	/// @param {String} reason Lifecycle reason, defaulting to server_shutdown
	/// @returns {Bool} Archive success, or false for a duplicate notification
	handle_server_shutdown_archive = function(reason = "server_shutdown")
	{
		/* Handle only the first shutdown notification per session. Duplicates return
		false without archiving the same final drawing again */
		if (server_shutdown_received)
		{
			return false;
		}

		server_shutdown_received = true;

		/* Normalize the shutdown reason for the three recognized restart causes.
		restarting selects restart-specific archive naming and reconnect guidance, while
		other reasons use the ordinary shutdown archive/message */
		var shutdown_reason = string_lower(string(reason));
		var restarting = shutdown_reason == "remote_admin_restart"
			|| shutdown_reason == "server_console_restart"
			|| shutdown_reason == "manual_force_restart";

		/* Archive before disconnect cleanup. archived is the success flag returned to
		the caller, with restart versus shutdown chosen from the normalized reason */
		var archived = scr_get_drawing().save_automatic_archive(restarting ? "client_restart" : "client_shutdown", "client");

		/* Show temporary restart guidance for the recognized restart reasons, otherwise
		explain final shutdown. Both alternatives clean the lost client session */
		mark_connection_lost(restarting
			? "The official server is restarting. Reconnect in a moment."
			: "The server shut down. The final drawing was archived.");
		debug_log("Handled server shutdown reason=" + string(reason) + " archive=" + string(archived));
		return archived;
	}
	#endregion /* Client Connection Lifecycle END */

	#region /* Network / Movement Diagnostics */
	/// @description Clear latency/movement samples and permit an immediate next probe
	/// @returns {Bool} True after diagnostics reset
	reset_network_diagnostics = function()
	{
		latency_probe_next_at = current_time;
		latency_probe_sequence = 0;
		latency_probe_pending_sequence = noone;
		latency_probe_sent_at = 0;
		latency_probe_sent_count = 0;
		latency_probe_reply_count = 0;
		latency_probe_timeout_count = 0;
		latency_probe_consecutive_timeouts = 0;
		latency_probe_exhausted = false;
		latency_rtt_ms = -1;
		latency_rtt_average_ms = -1;
		latency_rtt_previous_ms = -1;
		latency_rtt_jitter_ms = -1;
		latency_rtt_min_ms = -1;
		latency_rtt_max_ms = -1;
		latency_server_tick_ms = -1;
		latency_server_tick_average_ms = -1;
		latency_server_tick_peak_ms = -1;
		latency_server_tick_rate_hz = -1;
		latency_server_tick_max_gap_ms = -1;
		latency_server_fps = -1;
		latency_server_snapshot_interval_ms = -1;
		latency_server_build = "";
		movement_snapshot_count = 0;
		movement_snapshot_last_at = 0;
		movement_snapshot_interval_ms = -1;
		movement_snapshot_average_ms = -1;
		movement_snapshot_peak_interval_ms = -1;
		movement_snapshot_previous_interval_ms = -1;
		movement_snapshot_jitter_ms = -1;
		movement_snapshot_active_interval_count = 0;
		movement_snapshot_last_error = -1;
		movement_snapshot_peak_error = -1;
		movement_snapshot_last_dx = 0;
		movement_snapshot_last_dy = 0;
		movement_snapshot_safety_snaps = 0;
		movement_snapshot_client_moving = false;
		movement_snapshot_server_moving = false;
		movement_snapshot_has_server_position = false;
		movement_snapshot_server_x = 0;
		movement_snapshot_server_y = 0;
		return true;
	}

	/// @description Toggle the panel/probing state with fresh samples
	/// @returns {Bool} New diagnostics-enabled state
	toggle_network_diagnostics = function()
	{
		/* Remember the opposite of the current diagnostics state before resetting its
		samples, so the same toggle can enable fresh sampling or disable the panel */
		var should_enable = !network_diagnostics_enabled;
		reset_network_diagnostics();
		network_diagnostics_enabled = should_enable;

		/* The diagnostic label reports ON for the new enabled state and OFF otherwise.
		This log records the toggle without changing transport behavior */
		debug_log("Network movement diagnostics: " + (network_diagnostics_enabled ? "ON" : "OFF"));
		return network_diagnostics_enabled;
	}

	/// @description Resolve probe timeouts and send one scheduled optional latency request
	/// @returns {Bool} Whether a new probe was sent
	update_network_diagnostics = function()
	{
		/* Probe only while diagnostics are enabled, not exhausted and attached to a
		joined valid socket. Other states return false without extra background traffic */
		if (!network_diagnostics_enabled
		|| latency_probe_exhausted
		|| ID == noone
		|| !is_real(socket)
		|| socket < 0)
		{
			return false;
		}

		/* A pending sequence means one probe is awaiting a reply. Resolve its wait or
		timeout before starting another, keeping round-trip correlation unambiguous */
		if (latency_probe_pending_sequence != noone)
		{
			/* Keep waiting while the pending probe has not reached its millisecond timeout.
			Returning false prevents a second outstanding sequence */
			if (current_time - latency_probe_sent_at < latency_probe_timeout_ms)
			{
				return false;
			}

			latency_probe_pending_sequence = noone;
			latency_probe_timeout_count++;
			latency_probe_consecutive_timeouts++;
			latency_probe_next_at = current_time + latency_probe_interval_ms;

			/* Three unanswered optional probes stop further sampling for this diagnostics
			session. Older deployed servers may not implement the reply packet */
			if (latency_probe_consecutive_timeouts >= 3)
			{
				/* Older deployed servers do not know this optional packet. Stop probing
				after three unanswered requests instead of producing background traffic */
				latency_probe_exhausted = true;
			}
			return false;
		}

		/* Before the current_time deadline, skip a new probe so diagnostics use the
		configured interval instead of sending every watchdog update */
		if (current_time < latency_probe_next_at)
		{
			return false;
		}

		latency_probe_sequence = (latency_probe_sequence mod 2147483646) + 1;
		net.start(N_LATENCY_PROBE, ID);
		net.write(buffer_u32, latency_probe_sequence);

		/* Record whether this probe was actually sent. The next deadline advances on
		all attempts, but only a successful send starts pending sequence/time tracking */
		var send_result = net.send_server();
		latency_probe_next_at = current_time + latency_probe_interval_ms;

		/* A failed send did not create a measurable round trip. Return false without
		incrementing sent samples or awaiting this sequence */
		if (send_result < 0)
		{
			return false;
		}

		latency_probe_pending_sequence = latency_probe_sequence;
		latency_probe_sent_at = current_time;
		latency_probe_sent_count++;
		return true;
	}

	/// @description Match the outstanding probe and update latency/server diagnostics
	/// @param {Real} sequence Echoed pending probe ID
	/// @param {Real} tick_last_ms Server update-work duration in milliseconds
	/// @param {Real} tick_average_ms Smoothed update-work duration in milliseconds
	/// @param {Real} tick_peak_ms Recent peak update-work duration in milliseconds
	/// @param {Real} tick_rate_hz Measured server loop frequency
	/// @param {Real} tick_max_gap_ms Recent maximum loop gap in milliseconds
	/// @param {Real} server_fps Reported Runner frames per second
	/// @param {Real} snapshot_interval_ms Server movement-broadcast target period
	/// @param {String} server_build Server build label
	/// @returns {Bool} Whether the reply matched and updated samples
	receive_latency_reply = function(sequence, tick_last_ms, tick_average_ms, tick_peak_ms, tick_rate_hz, tick_max_gap_ms, server_fps, snapshot_interval_ms, server_build)
	{
		/* Accept a reply only for the one currently pending sequence. Ignore stale or
		unsolicited replies so their arrival time cannot contaminate round-trip samples */
		if (latency_probe_pending_sequence == noone
		|| sequence != latency_probe_pending_sequence)
		{
			return false;
		}

		/* round_trip_ms measures elapsed time on the same client current_time clock.
		The first reply seeds its average directly, while later replies blend 20 percent
		of the new sample into the previous average */
		var round_trip_ms = max(0, current_time - latency_probe_sent_at);
		latency_rtt_ms = round_trip_ms;
		latency_rtt_average_ms = latency_probe_reply_count <= 0
			? round_trip_ms
			: lerp(latency_rtt_average_ms, round_trip_ms, 0.20);

		/* Jitter needs an earlier valid round-trip sample. Skip it for the first reply
		rather than comparing against the unavailable -1 sentinel */
		if (latency_rtt_previous_ms >= 0)
		{
			/* rtt_delta is the absolute change between consecutive round trips in
			milliseconds. The first available difference seeds jitter, later differences
			blend at 12.5 percent */
			var rtt_delta = abs(round_trip_ms - latency_rtt_previous_ms);
			latency_rtt_jitter_ms = latency_probe_reply_count <= 1
				? rtt_delta
				: lerp(latency_rtt_jitter_ms, rtt_delta, 0.125);
		}
		latency_rtt_previous_ms = round_trip_ms;

		/* Unset min/max measurements take this sample directly. Later replies retain
		the smallest/largest measured round trip so -1 never acts as a real minimum */
		latency_rtt_min_ms = latency_rtt_min_ms < 0 ? round_trip_ms : min(latency_rtt_min_ms, round_trip_ms);
		latency_rtt_max_ms = latency_rtt_max_ms < 0 ? round_trip_ms : max(latency_rtt_max_ms, round_trip_ms);
		latency_server_tick_ms = max(0, real(tick_last_ms));
		latency_server_tick_average_ms = max(0, real(tick_average_ms));
		latency_server_tick_peak_ms = max(0, real(tick_peak_ms));
		latency_server_tick_rate_hz = max(0, real(tick_rate_hz));
		latency_server_tick_max_gap_ms = max(0, real(tick_max_gap_ms));
		latency_server_fps = max(0, real(server_fps));
		latency_server_snapshot_interval_ms = max(0, real(snapshot_interval_ms));
		latency_server_build = string(server_build);
		latency_probe_pending_sequence = noone;
		latency_probe_reply_count++;
		latency_probe_consecutive_timeouts = 0;
		latency_probe_exhausted = false;
		return true;
	}

	/// @description Measure relay timing and local prediction discrepancy without counting idle gaps as lag
	/// @param {Real} predicted_x Predicted world x in pixels
	/// @param {Real} predicted_y Predicted world y in pixels
	/// @param {Real} authoritative_x Relayed world x in pixels
	/// @param {Real} authoritative_y Relayed world y in pixels
	/// @param {Bool} client_moving Local movement state at receipt
	/// @param {Bool} server_moving Relayed movement state
	/// @param {Bool} safety_snap Whether this update applied a hard correction
	/// @returns {Real} Current prediction discrepancy in pixels
	record_local_movement_snapshot = function(predicted_x, predicted_y, authoritative_x, authoritative_y, client_moving, server_moving, safety_snap)
	{
		/* now captures one millisecond timestamp for all calculations in this relay
		sample, preventing different reads from assigning different ages to its fields */
		var now = current_time;

		/* A positive previous timestamp permits interval measurement. The first relay
		only establishes the clock and prediction-distance sample */
		if (movement_snapshot_last_at > 0)
		{
			/* interval_ms is elapsed relay time. active_stream_gap_ms uses three known
			server snapshot intervals, with a 500 ms floor/fallback, to distinguish idle gaps.
			previous_snapshot_was_moving combines prior client and server moving flags */
			var interval_ms = max(0, now - movement_snapshot_last_at);
			var active_stream_gap_ms = max(500, latency_server_snapshot_interval_ms > 0 ? latency_server_snapshot_interval_ms * 3 : 500);
			var previous_snapshot_was_moving = movement_snapshot_client_moving || movement_snapshot_server_moving;

			/* A long gap after both sides were idle starts a fresh active interval stream.
			Do not count intentionally absent idle relays as lag or include them in jitter */
			if (interval_ms > active_stream_gap_ms && !previous_snapshot_was_moving)
			{
				/* Dirty positions are not sent while the player is idle. Start a new
				active-stream sample instead of counting that idle gap as network lag */
				movement_snapshot_interval_ms = -1;
				movement_snapshot_average_ms = -1;
				movement_snapshot_previous_interval_ms = -1;
				movement_snapshot_jitter_ms = -1;
				movement_snapshot_active_interval_count = 0;
			}

			/* Short gaps or movement-active gaps belong to the active relay stream.
			Count the interval, seed unavailable peak/average values from it, then retain
			peaks or blend the average at 20 percent */
			else
			{
				movement_snapshot_active_interval_count++;
				movement_snapshot_interval_ms = interval_ms;
				movement_snapshot_peak_interval_ms = movement_snapshot_peak_interval_ms < 0
					? interval_ms
					: max(movement_snapshot_peak_interval_ms, interval_ms);
				movement_snapshot_average_ms = movement_snapshot_average_ms < 0
					? interval_ms
					: lerp(movement_snapshot_average_ms, interval_ms, 0.20);

				/* Only an existing active interval permits a jitter difference. The first
				interval seeds timing without comparing against an unavailable sentinel */
				if (movement_snapshot_previous_interval_ms >= 0)
				{
					/* interval_delta is the absolute millisecond change between active intervals.
					The first difference seeds jitter and later differences blend at 12.5 percent */
					var interval_delta = abs(interval_ms - movement_snapshot_previous_interval_ms);
					movement_snapshot_jitter_ms = movement_snapshot_active_interval_count <= 2
						? interval_delta
						: lerp(movement_snapshot_jitter_ms, interval_delta, 0.125);
				}
				movement_snapshot_previous_interval_ms = interval_ms;
			}
		}

		movement_snapshot_last_at = now;
		movement_snapshot_count++;
		movement_snapshot_has_server_position = true;
		movement_snapshot_server_x = authoritative_x;
		movement_snapshot_server_y = authoritative_y;
		movement_snapshot_last_dx = authoritative_x - predicted_x;
		movement_snapshot_last_dy = authoritative_y - predicted_y;
		movement_snapshot_last_error = point_distance(predicted_x, predicted_y, authoritative_x, authoritative_y);

		/* Seed an unavailable peak with the first prediction-distance sample.
		Later relays keep the largest pixel discrepancy observed during this session */
		movement_snapshot_peak_error = movement_snapshot_peak_error < 0
			? movement_snapshot_last_error
			: max(movement_snapshot_peak_error, movement_snapshot_last_error);

		/* Only explicit true marks the recorded client or server sample as moving.
		Other values record inactivity for stream-gap classification */
		movement_snapshot_client_moving = client_moving == true;
		movement_snapshot_server_moving = server_moving == true;

		/* Count a hard safety correction only when the caller explicitly reports one.
		Ordinary smoothed relays leave the snap counter unchanged */
		if (safety_snap == true)
		{
			movement_snapshot_safety_snaps++;
		}
		return movement_snapshot_last_error;
	}

	/// @description Draw GUI latency, authority, relay and observer diagnostics and restore drawing defaults
	/// @returns {Bool} Whether a joined enabled panel was drawn
	draw_network_diagnostics = function()
	{
		/* Draw the panel only for enabled diagnostics on a joined player.
		Unjoined state has no movement session to explain */
		if (!network_diagnostics_enabled || ID == noone)
		{
			return false;
		}

		/* This local formatter displays negative unavailable measurements as --.
		Valid measurements get one decimal and the millisecond unit */
		/// @description Format an optional millisecond measurement
		/// @param {Real} value Measurement, with negative meaning unavailable
		/// @returns {String} One-decimal duration or --
		var format_ms = function(value)
		{
			return value < 0 ? "--" : string_format(value, 1, 1) + " ms";
		};

		/* This local formatter uses -- for unavailable numeric samples and caller-
		selected decimal precision otherwise, defaulting to one decimal */
		/// @description Format an optional numeric measurement
		/// @param {Real} value Measurement, with negative meaning unavailable
		/// @param {Real} decimals Decimal precision, defaulting to one
		/// @returns {String} Formatted number or --
		var format_number = function(value, decimals = 1)
		{
			return value < 0 ? "--" : string_format(value, 1, decimals);
		};

		/* This local formatter displays YES for true values and NO otherwise,
		keeping movement flags readable beside numeric relay diagnostics */
		/// @description Format a diagnostic flag
		/// @param {Bool} value Flag to display
		/// @returns {String} YES for true, otherwise NO
		var bool_text = function(value)
		{
			return value ? "YES" : "NO";
		};

		/* Find the existing local player without creating one. Position text begins
		unavailable and live_relay_distance starts -1 pixels. Moving flags start from the
		last relay sample, while local_authority_active starts false until player inspection */
		var local_player = player_controller_get_player(ID, false);
		var local_position_text = "Player position unavailable";
		var live_relay_distance = -1;
		var live_client_moving = movement_snapshot_client_moving;
		var live_server_moving = movement_snapshot_server_moving;
		var local_authority_active = false;

		/* An existing player supplies current visual position, movement and negotiated
		authority. Without it, keep the unavailable position/authority defaults */
		if (local_player != noone)
		{
			/* Authority is active only when the player has the negotiated flag and it is
			true. Older player shapes remain in server-authority compatibility display */
			local_authority_active = variable_struct_exists(local_player, "client_position_authority")
				&& local_player.client_position_authority;

			/* Compute the live pixel distance only after a relay position exists.
			Otherwise origin defaults must not appear as a measured server discrepancy */
			if (movement_snapshot_has_server_position)
			{
				live_relay_distance = point_distance(
					local_player.visual_pos.x,
					local_player.visual_pos.y,
					movement_snapshot_server_x,
					movement_snapshot_server_y
				);
			}
			live_client_moving = local_player.is_moving;

			/* Display the latest relay coordinates when a sample exists. Otherwise show
			waiting beside the current client coordinates rather than presenting zeros as data */
			local_position_text = "Client position ("
				+ string_format(local_player.visual_pos.x, 1, 1) + ", "
				+ string_format(local_player.visual_pos.y, 1, 1) + ")  |  latest server relay "
				+ (movement_snapshot_has_server_position
					? "(" + string_format(movement_snapshot_server_x, 1, 1) + ", " + string_format(movement_snapshot_server_y, 1, 1) + ")"
					: "waiting");
		}

		/* The probe label begins ready. Exhausted optional probing and an outstanding
		sequence replace it with their specific stopped/waiting states */
		var probe_status = "ready";

		/* Three unanswered probes take priority in the status label, explaining why
		this client will not continue probing an older/unresponsive server */
		if (latency_probe_exhausted)
		{
			probe_status = "stopped after 3 timeouts (server may be an older build)";
		}

		/* A still-pending sequence shows waiting for reply. With neither condition,
		retain ready for the next scheduled attempt */
		else if (latency_probe_pending_sequence != noone)
		{
			probe_status = "waiting for reply";
		}

		/* snapshot_rate converts a positive average interval into Hz, or -1 when
		unavailable. snapshot_age uses the last current_time timestamp, or -1 before the
		first relay. movement_active combines current client and relay movement */
		var snapshot_rate = movement_snapshot_average_ms > 0
			? 1000 / movement_snapshot_average_ms
			: -1;
		var snapshot_age = movement_snapshot_last_at > 0
			? max(0, current_time - movement_snapshot_last_at)
			: -1;
		var movement_active = live_client_moving || live_server_moving;

		/* An old relay while both sides are idle is displayed as idle rather than lag.
		Other samples use their millisecond age. The threshold follows the server snapshot
		period with a 500 ms floor */
		var snapshot_age_text = !movement_active && snapshot_age >= max(500, latency_server_snapshot_interval_ms * 3)
			? "idle (last " + format_ms(snapshot_age) + " ago)"
			: format_ms(snapshot_age);

		/* authority_text describes negotiated client ownership or compatibility server
		ownership. correction_text uses the same distinction because relay snapshots
		cannot correct a client-owned local position, while fallback may safety-snap */
		var authority_text = local_authority_active
			? "CLIENT (negotiated, immediate local movement)"
			: "SERVER (compatibility fallback, no client-authority ACK)";
		var correction_text = local_authority_active
			? "OFF - relay snapshots cannot pull or snap the local player"
			: "ON for compatibility fallback  |  safety snaps " + string(movement_snapshot_safety_snaps);

		/* Start with no counted observers and no remote_sample. player_controller
		borrows the roster, which is scanned only if its players array is available */
		var remote_player_count = 0;
		var remote_sample = noone;
		var player_controller = scr_get_player_controller();

		/* Inspect observers only when the controller and players array exist.
		Missing roster state leaves the no-observer defaults intact */
		if (is_struct(player_controller)
		&& variable_struct_exists(player_controller, "players")
		&& is_array(player_controller.players))
		{
			/* Visit every zero-based roster entry. Count occupied nonlocal players and
			select one representative, preferring moving observers for smoothing diagnostics */
			for (var remote_index = 0; remote_index < array_length(player_controller.players); remote_index++)
			{
				/* remote_player is this roster entry, which may be noone for an empty slot.
				Its logical ID distinguishes the local player from remote observers */
				var remote_player = player_controller.players[remote_index];

				/* Skip empty entries and the local player before counting observers or reading
				remote movement state */
				if (remote_player == noone || remote_player.ID == ID)
				{
					continue;
				}

				remote_player_count++;

				/* Choose the first observer, then replace an idle sample with a moving one.
				Once the sample is moving, other observers do not repeatedly replace it */
				if (remote_sample == noone || (!remote_sample.is_moving && remote_player.is_moving))
				{
					remote_sample = remote_player;
				}
			}
		}

		/* Default observer text explains an empty roster. A selected remote player
		replaces it with sample age/rate and bounded prediction information */
		var remote_summary = "Remote observer smoothing: no other players connected";

		/* Only a selected observer has snapshot timing and velocity fields to inspect.
		Without one, retain the explicit no-other-players message */
		if (remote_sample != noone)
		{
			/* remote_age measures milliseconds since a recorded observer relay, or -1 when
			absent. remote_rate converts a positive average interval to Hz, otherwise -1.
			extrapolation_age is clamped to the player prediction limit only when moving with
			valid velocity, and is zero when prediction is inactive */
			var remote_age = remote_sample.remote_snapshot_received_at > 0
				? max(0, current_time - remote_sample.remote_snapshot_received_at)
				: -1;
			var remote_rate = remote_sample.remote_snapshot_average_ms > 0
				? 1000 / remote_sample.remote_snapshot_average_ms
				: -1;
			var extrapolation_age = remote_sample.authoritative_is_moving
			&& remote_sample.remote_velocity_valid
				? min(max(0, remote_age), remote_sample.remote_extrapolation_limit_ms)
				: 0;

			/* Add the plural suffix only for counts other than one, then report this
			observer sample timing and permitted prediction duration */
			remote_summary = "Remote observer smoothing " + string(remote_player_count)
				+ " player" + (remote_player_count == 1 ? "" : "s")
				+ "  |  sample age/rate " + format_ms(remote_age) + " / " + format_number(remote_rate) + " Hz"
				+ "  |  prediction " + format_ms(extrapolation_age);
		}

		/* Begin with native Runner FPS diagnostics. html5_perf borrows the browser
		performance sampler so HTML5 can replace this row with measured frame percentiles */
		var frame_rate_row = "Runner FPS client " + format_number(fps_real) + "  |  server " + format_number(latency_server_fps);
		var html5_perf = scr_get_html5_performance();

		/* HTML5 uses sampled frame-time percentiles rather than treating fps_real as
		measured browser throughput. Native builds retain the Runner FPS row */
		if (html5_perf.is_html5)
		{
			frame_rate_row = "HTML5 frame time p50/p95/p99 "
				+ html5_perf.format_ms(html5_perf.frame_p50_ms) + " / "
				+ html5_perf.format_ms(html5_perf.frame_p95_ms) + " / "
				+ html5_perf.format_ms(html5_perf.frame_p99_ms)
				+ "  |  samples " + string(html5_perf.sample_count)
				+ "  |  fps_real cadence hint " + format_number(fps_real)
				+ "  |  server runner " + format_number(latency_server_fps);
		}

		/* rows stores panel text in display order. Build text falls back to waiting
		until a server build arrives, and the last row explains negotiated client authority
		or legacy prediction according to local_authority_active */
		var rows =
		[
			"Movement authority " + authority_text,
			"Transport " + net.transport_to_string(transport) + "  |  " + string(connect_address),
			"Build client " + string(scr_get_build_date(true, true)) + "  |  server " + (latency_server_build == "" ? "waiting" : latency_server_build),
			frame_rate_row,
			"RTT last/avg/min/max " + format_ms(latency_rtt_ms) + " / " + format_ms(latency_rtt_average_ms) + " / " + format_ms(latency_rtt_min_ms) + " / " + format_ms(latency_rtt_max_ms),
			"RTT jitter " + format_ms(latency_rtt_jitter_ms) + "  |  replies " + string(latency_probe_reply_count) + "/" + string(latency_probe_sent_count) + "  |  timeouts " + string(latency_probe_timeout_count),
			"Probe " + probe_status,
			"Server loop " + format_number(latency_server_tick_rate_hz) + " Hz  |  5s max gap " + format_ms(latency_server_tick_max_gap_ms) + "  |  snapshot target " + format_ms(latency_server_snapshot_interval_ms),
			"Server update work last/avg/5s peak " + format_ms(latency_server_tick_ms) + " / " + format_ms(latency_server_tick_average_ms) + " / " + format_ms(latency_server_tick_peak_ms),
			"Active movement relays " + format_number(snapshot_rate) + " Hz  |  interval last/max " + format_ms(movement_snapshot_interval_ms) + " / " + format_ms(movement_snapshot_peak_interval_ms),
			"Active relay average/jitter " + format_ms(movement_snapshot_average_ms) + " / " + format_ms(movement_snapshot_jitter_ms),
			"Time since last relay received " + snapshot_age_text + "  |  samples " + string(movement_snapshot_count),
			"Client-to-relay distance now " + format_number(live_relay_distance) + " px  |  at receipt last/peak " + format_number(movement_snapshot_last_error) + " / " + format_number(movement_snapshot_peak_error) + " px",
			"Last relay offset (" + string_format(movement_snapshot_last_dx, 1, 1) + ", " + string_format(movement_snapshot_last_dy, 1, 1) + ") px  |  moving client/relay " + bool_text(live_client_moving) + "/" + bool_text(live_server_moving),
			"Local correction " + correction_text,
			remote_summary,
			local_position_text,
			local_authority_active
				? "Your movement is local, network latency only delays what other players see."
				: "This server has not enabled client-owned movement, legacy prediction is active."
		];

		/* Panel geometry is in GUI pixels. gui_width is bounded away from zero,
		panel_width fits the viewport within its 420-to-940 range, row_height is 23 pixels,
		and panel_height includes heading plus all rows. left/top place it 12 pixels inset */
		var gui_width = max(1, display_get_gui_width());
		var panel_width = min(940, max(420, gui_width - 24));
		var row_height = 23;
		var panel_height = 48 + array_length(rows) * row_height;
		var left = 12;
		var top = 12;

		draw_set_alpha(0.90);
		draw_set_colour(make_color_rgb(10, 13, 18));
		draw_rectangle(left, top, left + panel_width, top + panel_height, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(74, 190, 255));
		draw_rectangle(left, top, left + panel_width, top + panel_height, true);
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		draw_set_colour(make_color_rgb(150, 220, 255));
		scr_render_text(left + 10, top + 7, "NETWORK / MOVEMENT DIAGNOSTICS (F4)", 20, panel_width - 20);

		/* Draw every zero-based text row once, spacing them by row_height.
		The final authority explanation gets a distinct color while other rows stay white */
		for (var row = 0; row < array_length(rows); row++)
		{
			draw_set_colour(row == array_length(rows) - 1 ? make_color_rgb(170, 230, 180) : c_white);
			scr_render_text(left + 10, top + 39 + row * row_height, rows[row], 16, panel_width - 20);
		}

		draw_set_alpha(1);
		draw_set_colour(c_white);
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		return true;
	}
	#endregion /* Network / Movement Diagnostics END */

	#region /* LAN Discovery */
	/// @description Apply supported hostname/input restrictions to shared transport parsing
	/// @param {String} address Hostname, IPv4:port or explicit WebSocket URL
	/// @param {Real} default_port Optional port. undefined retains shared transport defaults
	/// @returns {Struct} Shared parse result with validated ok/message fields
	parse_server_address = function(address, default_port = undefined)
	{
		/* Trim the proposed address and parse its transport/port through the shared
		network parser. This wrapper adds the server-list hostname restrictions */
		var target = string_trim(string(address));

		/* parsed is the shared connection result, using the runtime transport when the
		address does not specify one. Further checks may change its ok/message fields */
		var parsed = net.parse_server_address(target, default_port, net.default_client_transport());

		/* Keep the shared parser failure instead of applying hostname checks to an
		already invalid connection target */
		if (!parsed.ok) return parsed;

		/* host begins with the original trimmed address and lower_target supplies
		case-insensitive scheme detection. Remove scheme, path and port for host validation */
		var host = target;
		var lower_target = string_lower(target);

		/* Remove a leading secure scheme for hostname checks. A plain ws scheme uses
		the five-character alternative. A slash without either scheme is rejected because
		this input expects a hostname, IP:port or explicit WebSocket URL */
		if (string_pos("wss://", lower_target) == 1) host = string_delete(host, 1, 6);

		/* A plain WebSocket scheme follows the same host validation path after
		removing its shorter prefix */
		else if (string_pos("ws://", lower_target) == 1) host = string_delete(host, 1, 5);

		/* Without an explicit WebSocket scheme, a slash is outside the supported
		hostname/IP input format. Reject it rather than treating a path as a host */
		else if (string_pos("/", host) > 0)
		{
			parsed.ok = false;
			parsed.message = "Use a hostname, IP:port, or ws:// / wss:// address.";
			return parsed;
		}

		/* Inspect every one-based input character for whitespace/control characters.
		The first such character rejects the address before DNS or connection startup */
		for (var char_index = 1; char_index <= string_length(target); char_index++)
		{
			/* Spaces and control characters cannot occur in a connection address.
			Return an input error rather than silently splitting or trimming internal text */
			if (ord(string_char_at(target, char_index)) <= 32)
			{
				parsed.ok = false;
				parsed.message = "Server addresses cannot contain spaces or line breaks.";
				return parsed;
			}
		}

		/* slash locates an optional WebSocket path. A positive position removes that
		path from host-only validation, while no slash leaves the host intact */
		var slash = string_pos("/", host);

		/* Validate only the host before the path delimiter. Path text remains in the
		parsed connection URL rather than being treated as a hostname */
		if (slash > 0) host = string_copy(host, 1, slash - 1);

		/* This wrapper accepts IPv4 or hostname targets, not IPv6 colon notation.
		Reject multiple host colons rather than misidentifying them as a port */
		if (string_count(":", host) > 1)
		{
			parsed.ok = false;
			parsed.message = "Use an IPv4 address or hostname.";
			return parsed;
		}

		/* colon is the remaining host/port delimiter, or zero when no port was given.
		A positive delimiter strips the port before validating hostname characters */
		var colon = string_pos(":", host);

		/* Remove the explicit port from hostname checks. Shared parsing has already
		validated its numeric destination range */
		if (colon > 0) host = string_copy(host, 1, colon - 1);

		/* Validate every one-based hostname character. Letters, decimal digits, dots
		and hyphens are accepted, while the first other character returns an error */
		for (var host_index = 1; host_index <= string_length(host); host_index++)
		{
			/* Reject characters outside the supported hostname/IPv4 alphabet so the server
			list cannot store a target this connection flow does not accept */
			if (string_pos(string_lower(string_char_at(host, host_index)), "abcdefghijklmnopqrstuvwxyz0123456789.-") <= 0)
			{
				parsed.ok = false;
				parsed.message = "Use an IPv4 address or hostname (for example play.example.com).";
				return parsed;
			}
		}
		return parsed;
	}

	/// @description Remove a mapped-IPv4 prefix from a UDP source address
	/// @param {String} ip_text GameMaker-reported UDP source
	/// @returns {String} Source text without a leading mapped-IPv4 prefix
	normalize_discovery_ip = function(ip_text)
	{
		/* ip is the UDP source address as text. ipv6_prefix identifies the mapped-IPv4
		notation that GameMaker may provide for an otherwise ordinary IPv4 sender */
		var ip = string(ip_text);
		var ipv6_prefix = "::ffff:";

		/* Strip only a leading mapped-IPv4 prefix. Other source addresses are preserved
		so matching does not remove unrelated text */
		if (string_copy(ip, 1, string_length(ipv6_prefix)) == ipv6_prefix)
		{
			ip = string_copy(ip, string_length(ipv6_prefix) + 1, string_length(ip) - string_length(ipv6_prefix));
		}

		return ip;
	}

	/// @description Load the bounded sandbox list once, retaining failure state to protect unread data
	load_saved_servers = function()
	{
		/* Load the saved list once per client state. Later calls reuse it instead of
		re-reading disk and replacing edits made during this session */
		if (saved_servers_loaded) return;
		saved_servers_loaded = true;
		saved_servers = [];

		/* A missing saved-list file means no user entries yet. Retain the empty list
		without treating first use as a persistence error */
		if (!file_exists(saved_servers_file)) return;
		try
		{
			ini_open(saved_servers_file);

			/* count is the saved entry count normalized to zero through 128. A missing count
			means no entries and the bound prevents untrusted INI values expanding the scan */
			var count = clamp(floor(ini_read_real("servers", "count", 0)), 0, 128);

			/* Read numbered sections from zero up to the stored bounded count.
			Malformed entries are skipped while later valid entries remain eligible */
			for (var i = 0; i < count; i++)
			{
				/* section identifies this stored row. saved_name/address are trimmed and
				bounded to their UI limits, and parsed validates/canonicalizes the address before
				that row can become a usable saved-server entry */
				var section = "server_" + string(i);
				var saved_name = string_copy(string_trim(ini_read_string(section, "name", "")), 1, 64);
				var saved_address = string_copy(string_trim(ini_read_string(section, "address", "")), 1, 160);
				var parsed = parse_server_address(saved_address);

				/* Keep only a named entry with a valid non-template address. Invalid or
				incomplete rows are skipped instead of being offered as joinable saved targets */
				if (saved_name != "" && parsed.ok && !parsed.placeholder)
				{
					/* Store only the visible name and canonical connection address. Runtime
					status, ping and discovery metadata are rebuilt rather than persisted */
					saved_servers[array_length(saved_servers)] = { name: saved_name, address: parsed.address };
				}
			}
			ini_close();
		}
		catch (e)
		{
			try { ini_close(); } catch (close_error) {}
			saved_servers_load_failed = true;
			saved_servers_error = "Could not load saved servers.";
			debug_error(saved_servers_error + " " + string(e.message));
		}
	}

	/// @description Persist names/addresses, remove stale sections and commit in-memory state only on success
	/// @param {Array} updated_servers Candidate name/address structs in saved-row order
	/// @returns {Bool} Whether persistence succeeded
	write_saved_servers = function(updated_servers)
	{
		/* Do not overwrite a list that failed to load, protecting unread saved data
		from being replaced with this session partial/empty view */
		if (saved_servers_load_failed) return false;
		saved_servers_error = "";
		try
		{
			ini_open(saved_servers_file);

			/* previous_count is the old bounded section count, needed to remove stale
			numbered sections after the list shrinks */
			var previous_count = clamp(floor(ini_read_real("servers", "count", 0)), 0, 128);

			/* Write every zero-based updated entry name/address to its numbered section.
			The loop ends after the supplied list, then old excess sections are removed */
			for (var i = 0; i < array_length(updated_servers); i++)
			{
				/* section is the destination INI section corresponding to this updated row */
				var section = "server_" + string(i);
				ini_write_string(section, "name", updated_servers[i].name);
				ini_write_string(section, "address", updated_servers[i].address);
			}

			/* Delete only old numbered sections beyond the new list length. Starting at
			the first removed row preserves every section just written */
			for (var stale_index = array_length(updated_servers); stale_index < previous_count; stale_index++)
			{
				ini_section_delete("server_" + string(stale_index));
			}
			ini_write_real("servers", "count", array_length(updated_servers));
			ini_close();
			saved_servers = updated_servers;
			return true;
		}
		catch (e)
		{
			try { ini_close(); } catch (close_error) {}
			saved_servers_error = "Could not save the server list. Please try again.";
			debug_error(saved_servers_error + " " + string(e.message));
			return false;
		}
	}

	/// @description Validate and persist a saved target without duplicate addresses
	/// @param {Real} saved_index Existing saved row index, or noone to append
	/// @param {String} server_name Visible name trimmed to 64 characters
	/// @param {String} server_address Connection address to validate/canonicalize
	/// @returns {Bool} Whether the candidate row was persisted
	store_saved_server = function(saved_index, server_name, server_address)
	{
		load_saved_servers();

		/* A prior load failure blocks edits from overwriting unread list contents.
		Keep its error state rather than inventing a replacement list */
		if (saved_servers_load_failed) return false;
		saved_servers_error = "";
		server_name = string_copy(string_trim(string(server_name)), 1, 64);

		/* parsed validates and canonicalizes the proposed address before editing the
		saved list. server_name has already been trimmed and bounded to 64 characters */
		var parsed = parse_server_address(server_address);

		/* A saved row needs a nonempty name and real usable address. Feedback prefers
		the missing-name error, then parse failure, then the unchanged-template error */
		if (server_name == "" || !parsed.ok || parsed.placeholder)
		{
			saved_servers_error = server_name == "" ? "Enter a server name." : (!parsed.ok ? parsed.message : "Enter your server's address.");
			return false;
		}

		/* Edits must refer to an existing saved-list index. noone means append and
		bypasses this bounds check, while invalid existing selections return feedback */
		if (saved_index != noone && (saved_index < 0 || saved_index >= array_length(saved_servers)))
		{
			saved_servers_error = "Select a saved server first.";
			return false;
		}

		/* Only appending can exceed the 128-entry saved-list capacity. Existing rows
		remain editable at capacity, while a full-list append is rejected */
		if (saved_index == noone && array_length(saved_servers) >= 128)
		{
			saved_servers_error = "Your server list is full (128 servers).";
			return false;
		}

		/* Check every zero-based saved row for a duplicate canonical address.
		The row currently being edited is excluded so retaining its own address is allowed */
		for (var i = 0; i < array_length(saved_servers); i++)
		{
			/* Another saved row with the same case-insensitive address would duplicate
			the endpoint. Reject it and direct the user to edit the existing row */
			if (i != saved_index && string_lower(saved_servers[i].address) == string_lower(parsed.address))
			{
				saved_servers_error = "That address is already saved. Select it and choose Edit.";
				return false;
			}
		}

		/* Copy current entries into a separate candidate list. Persistence commits it
		to saved_servers only after the write succeeds, preserving current data on failure */
		var updated_servers = [];
		array_copy(updated_servers, 0, saved_servers, 0, array_length(saved_servers));

		/* A new row uses the candidate list length as its append index. An edit reuses
		the selected saved index. The replacement struct stores name and canonical address */
		var target_index = saved_index == noone ? array_length(updated_servers) : saved_index;
		updated_servers[target_index] = { name: server_name, address: parsed.address };
		return write_saved_servers(updated_servers);
	}

	/// @description Persist deletion from a candidate copy of the saved list
	/// @param {Real} saved_index Existing zero-based saved row index
	/// @returns {Bool} Whether the smaller list was persisted
	delete_saved_server = function(saved_index)
	{
		/* Deletion requires an existing saved row. Invalid indexes return false before
		copying or changing the persisted list */
		if (saved_index < 0 || saved_index >= array_length(saved_servers)) return false;

		/* Build a candidate copy for deletion. The original in-memory list is replaced
		only when write_saved_servers successfully persists the smaller list */
		var updated_servers = [];
		array_copy(updated_servers, 0, saved_servers, 0, array_length(saved_servers));
		array_delete(updated_servers, saved_index, 1);
		return write_saved_servers(updated_servers);
	}

	/// @description Rebuild normalized official/saved endpoints with unknown status and start native DNS resolution
	/// @param {Bool} reset_status Retained interface flag, defaulting to false. The current body rebuilds status for either value
	sync_official_servers = function(reset_status = false)
	{
		official_servers = [];
		load_admin_credentials();
		load_saved_servers();

		/* server_configs starts empty before copying official configuration and
		appending user-saved rows. official_count marks the boundary used to recover each
		saved row original index */
		var server_configs = [];

		/* Copy official definitions only from an available array. Missing configuration
		leaves the candidate list empty before saved entries are appended */
		if (variable_struct_exists(net, "official_servers") && is_array(net.official_servers))
		{
			array_copy(server_configs, 0, net.official_servers, 0, array_length(net.official_servers));
		}
		var official_count = array_length(server_configs);

		/* Append saved rows in their stored zero-based order after official definitions.
		The boundary preserves each saved row identity for Edit/Delete UI */
		for (var saved_index = 0; saved_index < array_length(saved_servers); saved_index++)
		{
			server_configs[array_length(server_configs)] = saved_servers[saved_index];
		}

		/* Normalize every combined configuration in order. Invalid objects or targets
		are skipped while later configurations can still form server-list entries */
		for (var i = 0; i < array_length(server_configs); i++)
		{
			/* config is the current official or saved definition. It must be a struct
			before its optional transport, address and naming fields are inspected */
			var config = server_configs[i];

			/* Skip a malformed configuration without attempting its fields or preventing
			other entries from being normalized */
			if (!is_struct(config))
			{
				continue;
			}

			/* Entries after the official boundary recover their zero-based saved index.
			Official entries use noone. A valid owner credential forces official targets to
			WebSocket, while saved targets and uncredentialed clients use the runtime default */
			var config_saved_index = i >= official_count ? i - official_count : noone;
			var config_transport = config_saved_index == noone && admin_credential_valid
				? TRANSPORT_WS
				: net.default_client_transport();

			/* The connection target starts empty until a supported config address is found.
			An available WebSocket address takes priority for WebSocket transport */
			var config_address = "";

			/* Prefer the explicit WebSocket route when this entry uses WebSocket and has
			that route. Other configurations may use their ordinary address field */
			if (config_transport == TRANSPORT_WS
			&& variable_struct_exists(config, "websocket_address"))
			{
				config_address = string(config.websocket_address);
			}

			/* Without the preferred WebSocket field, use the ordinary address when present.
			Missing both leaves empty text so this configuration is skipped */
			else if (variable_struct_exists(config, "address"))
			{
				config_address = string(config.address);
			}

			/* A configuration without a selected connection address cannot form a server
			row. Continue to the next definition */
			if (config_address == "")
			{
				continue;
			}

			/* parsed normalizes the selected endpoint. Its omitted explicit port uses the
			public WebSocket default for WebSocket or native TCP default otherwise */
			var parsed = net.parse_server_address(config_address, config_transport == TRANSPORT_WS ? net.websocket_public_port : net.port, config_transport);

			/* Skip an endpoint the shared parser rejected. Later list rows can still be
			built from valid configurations */
			if (!parsed.ok)
			{
				continue;
			}

			/* Discovery target/response port start absent as empty text/zero until filled
			from a valid native endpoint. Keep official TCP/UDP status targets separate from
			WSS gameplay so administrator credentials stay on that secure connection */
			var discovery_ip = "";
			var discovery_response_port = 0;

			/* An ordinary configured address may supply native TCP discovery metadata.
			Without it, the later fallback can use a TCP gameplay endpoint */
			if (variable_struct_exists(config, "address"))
			{
				/* Parse native discovery independently of the selected WSS gameplay address,
				keeping admin credentials away from the UDP status route */
				var parsed_discovery = net.parse_server_address(string(config.address), net.port, TRANSPORT_TCP);

				/* Use only a successfully parsed TCP target for UDP discovery metadata.
				Invalid or explicitly WebSocket targets leave discovery absent */
				if (parsed_discovery.ok && parsed_discovery.transport == TRANSPORT_TCP)
				{
					discovery_ip = parsed_discovery.url;
					discovery_response_port = parsed_discovery.port;
				}
			}

			/* A TCP gameplay endpoint can fill missing discovery host/response-port data.
			A WSS endpoint cannot replace that native discovery information */
			if (discovery_ip == "" && parsed.transport == TRANSPORT_TCP)
			{
				discovery_ip = parsed.url;
				discovery_response_port = parsed.port;
			}

			/* Browser status address/URL/port start absent. Saved WebSocket entries can
			reuse their connection route, while an explicit configured status route overrides it */
			var status_address = "";
			var status_url = "";
			var status_port = 0;

			/* Saved WebSocket rows reuse their endpoint for status probing when no separate
			status route was configured. Official rows wait for their explicit status route */
			if (config_saved_index != noone && parsed.transport == TRANSPORT_WS)
			{
				status_address = parsed.address;
				status_url = parsed.url;
				status_port = parsed.port;
			}

			/* A separate WebSocket status address takes precedence when it is provided.
			Other transport configurations retain their existing status fallback */
			if (config_transport == TRANSPORT_WS
			&& variable_struct_exists(config, "websocket_status_address"))
			{
				/* Normalize the independent browser status route using the public port default.
				Its parse result controls whether it can replace fallback status metadata */
				var parsed_status = net.parse_server_address(string(config.websocket_status_address), net.websocket_public_port, TRANSPORT_WS);

				/* Replace status routing only after a successful parse. Invalid status config
				does not erase a previously established saved-route fallback */
				if (parsed_status.ok)
				{
					status_address = parsed_status.address;
					status_url = parsed_status.url;
					status_port = parsed_status.port;
				}
			}

			/* server_name starts with the branded official fallback and is replaced by
			nonempty configured text so incomplete definitions still have a visible label */
			var server_name = net.official_server_name;

			/* Use a configured name only when its field exists and contains text.
			Otherwise keep the branded fallback */
			if (variable_struct_exists(config, "name")
			&& string(config.name) != "")
			{
				server_name = string(config.name);
			}

			/* Default the UDP destination to the shared discovery port. A positive config
			port can replace it for public port forwarding */
			var official_discovery_port = net.discovery_port;

			/* Use a positive per-server discovery port when provided, otherwise retain
			the network default */
			if (variable_struct_exists(config, "discovery_port")
			&& config.discovery_port > 0)
			{
				official_discovery_port = config.discovery_port;
			}

			/* The normalized entry keeps saved-row identity, display name and separate
			connection/discovery/status endpoints. players/max_players/ping start -1 as unknown.
			last_seen/last_probe/first_probe are unavailable current_time timestamps at -1,
			and checking/failed begin false until probing updates them */
			official_servers[array_length(official_servers)] =
			{
				saved_index: config_saved_index,
				name: server_name,
				address: parsed.address,
				ip: parsed.url,
				port: parsed.port,
				transport: parsed.transport,
				placeholder: parsed.placeholder,
				discovery_ip: discovery_ip,
				discovery_response_port: discovery_response_port,
				status_address: status_address,
				status_url: status_url,
				status_port: status_port,
				discovery_port: official_discovery_port,
				players: -1,
				max_players: -1,
				ping_ms: -1,
				last_seen: -1,
				last_probe: -1,
				first_probe: -1,
				status_checking: false,
				status_failed: false
			};
		}

		resolve_discovery_domains();
	}

	/// @description Expire native DNS waits and start one lookup per unresolved discovery hostname
	resolve_discovery_domains = function()
	{
		/* Browsers do not use native UDP discovery, so they skip hostname resolution
		for those discovery targets. Their WebSocket URLs handle hostname connection */
		if (net.is_browser_runtime())
		{
			return;
		}

		/* Walk pending requests backward from the last index so deleting expired
		entries cannot shift an unvisited request past the scan */
		for (var pending_index = array_length(discovery_dns_requests) - 1; pending_index >= 0; pending_index--)
		{
			/* An elapsed current_time deadline retires this DNS request and marks matching
			server entries failed. Requests still within their wait remain pending */
			if (current_time >= discovery_dns_requests[pending_index].deadline)
			{
				/* Capture the expired hostname before deleting its request, so all server
				aliases using that discovery name receive the same timeout state */
				var expired_domain = discovery_dns_requests[pending_index].domain;
				array_delete(discovery_dns_requests, pending_index, 1);

				/* Check every zero-based configured entry for the timed-out discovery hostname.
				Other endpoint names retain their current status */
				for (var expired_index = 0; expired_index < array_length(official_servers); expired_index++)
				{
					/* Only entries sharing the expired discovery domain become failed.
					Do not mark unrelated server addresses unavailable */
					if (official_servers[expired_index].discovery_ip == expired_domain)
					{
						official_servers[expired_index].status_failed = true;
					}
				}
				debug_error("Discovery DNS timed out for: " + expired_domain);
			}
		}

		/* Inspect every normalized server discovery target. Skip resolved/missing hosts
		and start at most one pending DNS request per unresolved domain */
		for (var i = 0; i < array_length(official_servers); i++)
		{
			/* discovery_target is the native UDP host, which may still be a hostname.
			Resolution changes only this discovery field rather than the secure gameplay URL */
			var discovery_target = official_servers[i].discovery_ip;

			/* Empty targets cannot be resolved and IPv4 targets are already usable.
			Skip both instead of issuing unnecessary HTTP DNS requests */
			if (discovery_target == "" || is_ipv4_address(discovery_target))
			{
				continue;
			}

			/* Start with no known duplicate request. The pending-request scan sets true
			only when this hostname already has an outstanding lookup */
			var already_resolving = false;

			/* Check all pending zero-based DNS entries until this hostname is found.
			One match is enough to prevent a duplicate lookup */
			for (var j = 0; j < array_length(discovery_dns_requests); j++)
			{
				/* An outstanding lookup already owns this hostname resolution.
				Mark it found and stop scanning to reuse that future response */
				if (discovery_dns_requests[j].domain == discovery_target)
				{
					already_resolving = true;
					break;
				}
			}

			/* Leave this hostname attached to its existing request. Continue with other
			server entries instead of submitting another identical DNS request */
			if (already_resolving)
			{
				continue;
			}

			/* req_id is the async HTTP correlation handle. The request record stores that
			ID, the hostname it resolves and a current_time deadline using connect_timeout_ms */
			var req_id = dns_resolve_domain(discovery_target);
			discovery_dns_requests[array_length(discovery_dns_requests)] =
			{
				request_id: req_id,
				domain: discovery_target,
				deadline: current_time + net.connect_timeout_ms
			};

			/* A negative HTTP request result could not start resolution. Mark this server
			failed and report it rather than implying the DNS query is active */
			if (req_id < 0)
			{
				official_servers[i].status_failed = true;
				debug_error("Could not start discovery DNS for: " + discovery_target);
			}

			/* A valid request handle means DNS is now pending. Report startup while its
			stored deadline continues to govern the eventual response */
			else
			{
				debug_log("Discovery DNS resolution started for: " + discovery_target);
			}
		}
	}

	/// @description Complete a known DNS wait and update every matching discovery alias
	/// @param {Real} request_id Async HTTP correlation ID
	/// @param {String} resolved_ip Valid IPv4 answer, or empty text on failure
	/// @returns {Bool} Whether the response belonged to a pending discovery query
	on_discovery_dns_resolved = function(request_id, resolved_ip)
	{
		/* domain starts unresolved and request_index starts -1 to mean no matching
		pending DNS request. The correlation scan fills both together */
		var domain = "";
		var request_index = -1;

		/* Search zero-based pending request entries for this async HTTP ID.
		Stop at the matching request, preserving its hostname before removal */
		for (var i = 0; i < array_length(discovery_dns_requests); i++)
		{
			/* The matching HTTP ID identifies which hostname this response resolves.
			Capture the index/domain and stop before inspecting unrelated requests */
			if (discovery_dns_requests[i].request_id == request_id)
			{
				domain = discovery_dns_requests[i].domain;
				request_index = i;
				break;
			}
		}

		/* A stale or unrelated HTTP reply has no pending discovery request.
		Return false so it cannot update arbitrary server discovery state */
		if (request_index < 0)
		{
			return false;
		}

		array_delete(discovery_dns_requests, request_index, 1);

		/* Missing or malformed IPv4 data completes this known request as failed.
		Mark only server entries using that hostname, then report the response consumed */
		if (resolved_ip == "" || !is_ipv4_address(resolved_ip))
		{
			/* Scan all configured aliases so every entry depending on this failed hostname
			receives consistent unavailable status */
			for (var failed_index = 0; failed_index < array_length(official_servers); failed_index++)
			{
				/* Only entries using this failed domain change status, keeping unrelated
				DNS resolutions intact */
				if (official_servers[failed_index].discovery_ip == domain)
				{
					official_servers[failed_index].status_failed = true;
				}
			}
			debug_error("Discovery DNS resolution failed for: " + domain);
			return true;
		}

		/* updated begins false and becomes true when at least one matching server
		receives the resolved address, controlling whether an immediate probe is scheduled */
		var updated = false;

		/* Visit every zero-based server entry to update all aliases of this hostname.
		The gameplay endpoint stays unchanged while discovery receives the IPv4 address */
		for (var i = 0; i < array_length(official_servers); i++)
		{
			/* Replace the matching discovery domain and clear its failure flag.
			Other hosts retain their previous discovery metadata */
			if (official_servers[i].discovery_ip == domain)
			{
				official_servers[i].discovery_ip = resolved_ip;
				official_servers[i].status_failed = false;
				debug_log("Discovery DNS resolved " + domain + " -> " + resolved_ip + " for official server " + official_servers[i].address);
				updated = true;
			}
		}

		/* At least one newly usable target deserves an immediate discovery attempt.
		Set the next deadline to zero rather than waiting out the previous scan interval */
		if (updated)
		{
			next_discovery_request = 0;
		}

		return true;
	}

	/// @description Find a canonical address in received LAN records
	/// @param {String} address Canonical IP:port text
	/// @returns {Real} Zero-based LAN row, or noone
	find_discovery_server = function(address)
	{
		/* Find a LAN entry by its exact canonical address, scanning zero-based rows.
		Exhausting the list returns noone so a new server can be appended */
		for (var i = 0; i < array_length(discovery_servers); i++)
		{
			/* Return the matching LAN row index, allowing replies to refresh an existing
			entry rather than adding a duplicate */
			if (discovery_servers[i].address == address)
			{
				return i;
			}
		}

		return noone;
	}

	/// @description Find a canonical address in normalized official/saved records
	/// @param {String} address Canonical connection address
	/// @returns {Real} Zero-based configured row, or noone
	find_official_server = function(address)
	{
		/* Search normalized official/saved entries in zero-based order.
		A missing address returns noone rather than selecting a different endpoint */
		for (var i = 0; i < array_length(official_servers); i++)
		{
			/* This canonical address identifies the existing configured entry.
			Return its index so callers retain its configured routing metadata */
			if (official_servers[i].address == address)
			{
				return i;
			}
		}

		return noone;
	}

	/// @description Match a UDP reply to a configured public endpoint without guessing ambiguous forwards
	/// @param {String} ip Normalized UDP source IPv4
	/// @param {Real} port Server-advertised game port
	/// @param {Real} response_port Actual UDP source port
	/// @param {Real} ping_ms Correlated reply age, or -1 when absent
	/// @returns {Real} Configured row index, or noone when unmatched/ambiguous
	find_official_server_by_response = function(ip, port, response_port, ping_ms)
	{
		/* Forwarded servers can advertise their internal game port. First match a recent
		correlated reply to the public UDP endpoint actually queried. Uncorrelated or
		expired replies skip this forwarding-aware path and use direct matching */
		if (ping_ms >= 0 && ping_ms <= net.discovery_timeout_ms)
		{
			/* No forwarding candidate or public response port is selected initially.
			forwarded_ambiguous begins false and is set if recent candidates identify different
			public game endpoints behind the same queried UDP endpoint */
			var forwarded_index = noone;
			var forwarded_port = noone;
			var forwarded_ambiguous = false;

			/* Check all configured zero-based targets for a recent probe of this source
			IP/UDP port, preferring an exact advertised game-port match */
			for (var probe_index = 0; probe_index < array_length(official_servers); probe_index++)
			{
				/* probed is one configured discovery endpoint with its latest current_time
				probe timestamp and expected public response/game port */
				var probed = official_servers[probe_index];

				/* A forwarding candidate must match source IP, queried UDP port and a recent
				sent probe. These checks tie the reply to a target this client actually queried */
				if (probed.discovery_ip == ip
				&& probed.discovery_port == response_port
				&& probed.last_probe >= 0
				&& current_time - probed.last_probe <= net.discovery_timeout_ms)
				{
					/* An advertised game port matching the configured public endpoint resolves the
					candidate directly, without guessing between forwarded aliases */
					if (probed.discovery_response_port == port) return probe_index;

					/* Retain the first forwarding candidate and its public game port.
					Later candidates are compared with it for ambiguity */
					if (forwarded_index == noone)
					{
						forwarded_index = probe_index;
						forwarded_port = probed.discovery_response_port;
					}

					/* Different public game ports sharing this queried UDP endpoint make the reply
					ambiguous. Do not let the first entry silently claim another forwarded server */
					else if (forwarded_port != probed.discovery_response_port)
					{
						forwarded_ambiguous = true;
					}
				}
			}

			/* Saved servers may share a default discovery port. If this reply cannot distinguish
			those public endpoints, return no match rather than updating the wrong saved server */
			if (forwarded_ambiguous) return noone;

			/* One unambiguous recent queried endpoint may use the forwarding fallback even
			when the server advertises its internal game port */
			if (forwarded_index != noone) return forwarded_index;
		}

		/* For LAN/legacy replies, scan each configured entry for direct source-IP and
		advertised game-port matching. No match returns noone */
		for (var i = 0; i < array_length(official_servers); i++)
		{
			/* official is the current direct-match candidate with resolved discovery host
			and configured game response port */
			var official = official_servers[i];

			/* Skip another source host before comparing ports, preventing a different
			machine with the same game port from being selected */
			if (official.discovery_ip != ip)
			{
				continue;
			}

			/* A matching source IP and expected game port identifies this direct endpoint.
			Return its configured row index */
			if (official.discovery_response_port == port)
			{
				return i;
			}

		}

		return noone;
	}

	/// @description Release the owned browser status socket and clear its target checking flag
	close_status_probe = function()
	{
		/* Retain the associated server row before clearing probe state, so its
		checking flag can be cleared after the owned socket is released */
		var closing_index = status_probe_official_index;

		/* Unregister and destroy only a valid client-owned status socket.
		Absent or failed handles skip resource release */
		if (is_real(status_probe_socket) && status_probe_socket >= 0)
		{
			net.unregister_socket_transport(status_probe_socket);
			network_destroy(status_probe_socket);
		}

		status_probe_socket = noone;
		status_probe_official_index = noone;
		status_probe_started = 0;
		status_probe_deadline = 0;

		/* Clear checking only for a present in-range row index. Rebuilt/absent lists
		cannot be indexed using an obsolete probe target */
		if (closing_index != noone
		&& closing_index >= 0
		&& closing_index < array_length(official_servers))
		{
			official_servers[closing_index].status_checking = false;
		}
	}

	/// @description Close the current probe and mark its still-valid target row failed
	fail_status_probe = function()
	{
		/* Save the affected row before close_status_probe clears ownership state.
		Failure feedback belongs to that same configured server entry */
		var failed_index = status_probe_official_index;
		close_status_probe();

		/* Mark failure only for a still-valid configured row. If the list changed or
		no target was assigned, socket cleanup still completes without indexing it */
		if (failed_index != noone
		&& failed_index >= 0
		&& failed_index < array_length(official_servers))
		{
			official_servers[failed_index].status_checking = false;
			official_servers[failed_index].status_failed = true;
		}
	}

	/// @description Fail an allocated browser probe when its current_time deadline elapses
	update_status_probe_timeout = function()
	{
		/* An allocated status socket whose current_time deadline has elapsed becomes
		failed. Missing probes and probes still within their wait remain unchanged */
		if (is_real(status_probe_socket)
		&& status_probe_socket >= 0
		&& current_time >= status_probe_deadline)
		{
			fail_status_probe();
		}
	}

	/// @description Start at most one optional browser probe in rotating configured-row order
	/// @param {Bool} force Bypass the interval deadline, defaulting to false
	/// @returns {Real} Connection startup result, or zero when skipped/no usable target
	send_browser_status_probe = function(force = false)
	{
		/* Browser status probing requires both browser runtime and enabled optional
		probe support. Other states return zero and create no extra status sockets */
		if (!net.is_browser_runtime()
		|| !variable_struct_exists(net, "status_probes_enabled")
		|| !net.status_probes_enabled)
		{
			return 0;
		}

		update_status_probe_timeout();

		/* Only one status socket is active at a time. Leave its reply/timeout pending
		rather than allocating another overlapping probe */
		if (is_real(status_probe_socket) && status_probe_socket >= 0)
		{
			return 0;
		}

		/* Ordinary probes wait for their current_time interval deadline. A forced
		refresh bypasses that schedule but still respects single-socket ownership */
		if (!force && current_time < next_discovery_request)
		{
			return 0;
		}

		next_discovery_request = current_time + net.status_probe_interval_ms;

		/* status_target_count bounds one round-robin pass across all configured rows.
		An empty list gives zero iterations and avoids modulo by zero */
		var status_target_count = array_length(official_servers);

		/* Try at most one pass of row offsets from zero. Start from the next rotating
		index and return after the first usable connection, skipping invalid targets */
		for (var offset = 0; offset < status_target_count; offset++)
		{
			/* i wraps the rotating row index within the nonempty list, and official is the
			candidate entry whose independent browser status route will be probed */
			var i = (status_probe_next_index + offset) mod status_target_count;
			var official = official_servers[i];

			/* Template addresses are not actual servers. Skip placeholder entries rather
			than opening their unresolved configured routes */
			if (variable_struct_exists(official, "placeholder")
			&& official.placeholder)
			{
				continue;
			}

			/* A usable status target needs a nonempty URL and positive port.
			Skip incomplete metadata instead of passing it to socket creation/connection */
			if (!variable_struct_exists(official, "status_url")
			|| string(official.status_url) == ""
			|| !variable_struct_exists(official, "status_port")
			|| official.status_port <= 0)
			{
				continue;
			}

			/* Create a client-owned WebSocket status handle using its URL secure scheme.
			A successful probe stores it for timeout/reply cleanup */
			var status_socket = network_create_socket(net.socket_type_for_transport(TRANSPORT_WS, official.status_url));

			/* Socket creation failure marks this row unavailable, then tries another row.
			There is no allocated handle to destroy for this negative result */
			if (status_socket < 0)
			{
				official_servers[i].status_failed = true;
				official_servers[i].status_checking = false;
				continue;
			}

			net.register_socket_transport(status_socket, TRANSPORT_WS);

			/* connect_result reports startup on the independent status route.
			A successful start becomes the one active probe while its async reply is awaited */
			var connect_result = net.connect(status_socket, official.status_url, official.status_port, TRANSPORT_WS);

			/* Failed startup releases the newly allocated socket and registration before
			trying another row, preventing an orphaned status resource */
			if (connect_result < 0)
			{
				net.unregister_socket_transport(status_socket);
				network_destroy(status_socket);
				official_servers[i].status_failed = true;
				official_servers[i].status_checking = false;
				continue;
			}

			status_probe_socket = status_socket;
			status_probe_next_index = (i + 1) mod status_target_count;
			status_probe_official_index = i;
			status_probe_started = current_time;
			status_probe_deadline = current_time + net.status_probe_timeout_ms;
			official_servers[i].status_checking = true;
			official_servers[i].status_failed = false;

			/* Record the first current_time probe timestamp only once for timeout UI.
			Later attempts update last_probe while retaining when checking originally began */
			if (official_servers[i].first_probe < 0)
			{
				official_servers[i].first_probe = current_time;
			}
			official_servers[i].last_probe = current_time;
			debug_log("Browser server status probe started: " + official.status_address);
			return connect_result;
		}

		return 0;
	}

	/// @description Consume only the owned browser status socket and update its listing metadata
	/// @param {Real} network_id Async id handle
	/// @param {Real} network_type Async network event constant
	/// @param {Real} network_socket Async socket handle
	/// @param {Id.Buffer} network_data Borrowed packet buffer retained by the interface
	/// @returns {Bool} Whether the event belongs to the current status probe
	handle_status_probe_async = function(network_id, network_type, network_socket, network_data)
	{
		/* This event belongs to status probing only when its id or socket matches the
		currently valid probe handle. Other events remain available to gameplay routing */
		var is_status_socket = is_real(status_probe_socket)
			&& status_probe_socket >= 0
			&& (network_id == status_probe_socket || network_socket == status_probe_socket);

		/* Return false for unrelated handles so this optional status path cannot consume
		an active gameplay or stale socket event */
		if (!is_status_socket)
		{
			return false;
		}

		/* Remember the target row for this event before closing/failing the probe can
		clear its stored index */
		var official_index = status_probe_official_index;

		/* Connection completion sends the query, data consumes a validated status,
		and disconnect finishes/fails the probe. Other events on this handle are consumed
		without being mistaken for gameplay events */
		switch (network_type)
		{
			/* The status query waits for a successful async connection result before
			writing to its WebSocket handle */
			case network_type_non_blocking_connect:

				/* Assume connection failure until the async map explicitly reports success.
				A missing succeeded field cannot authorize sending a status query */
				var succeeded = false;

				/* Read the success flag only when present and accept numeric one.
				Otherwise retain the failure default */
				if (ds_map_exists(async_load, "succeeded"))
				{
					succeeded = async_load[? "succeeded"] == 1;
				}

				/* Unsuccessful status connection closes the probe and marks its target failed.
				The successful alternative sends the bodyless status request */
				if (!succeeded)
				{
					fail_status_probe();
				}

				/* A completed status connection can request server listing data.
				Its send failure still follows the same target/socket cleanup path */
				else
				{
					net.start(N_SERVER_STATUS_REQUEST, noone);

					/* status_send_result reports delivery of the query over its explicit WebSocket
					route rather than the client gameplay socket */
					var status_send_result = net.send(status_probe_socket, true, TRANSPORT_WS);

					/* A failed/partial query send cannot produce a reliable status response.
					Fail and release the probe rather than waiting out its deadline */
					if (status_send_result < 0)
					{
						fail_status_probe();
					}
				}
				return true;

			/* Status-socket data is separate from gameplay. Only N_SERVER_STATUS has a
			body interpreted by this probe handler */
			case network_type_data:

				/* Consume unexpected packets on the probe handle without applying them to
				client gameplay. Keep waiting for status or its timeout */
				if (net.header.type != N_SERVER_STATUS)
				{
					return true;
				}

				/* A status response needs both signed count fields and a terminated name.
				Malformed data fails the probe before any partial metadata reaches the list */
				if (!net.can_read_fields([buffer_s16, buffer_s16, buffer_string]))
				{
					fail_status_probe();
					return true;
				}

				/* player_count/player_max are the reported gameplay counts, and server_name
				is the optional advertised label. Ping uses elapsed current_time since probe start */
				var player_count = net.read(buffer_s16);
				var player_max = net.read(buffer_s16);
				var server_name = net.read(buffer_string);

				/* Update counts/ping/status only for a still-present in-range target row.
				If configuration changed, close the owned socket without indexing stale metadata */
				if (official_index != noone
				&& official_index >= 0
				&& official_index < array_length(official_servers))
				{
					official_servers[official_index].players = player_count;
					official_servers[official_index].max_players = player_max;
					official_servers[official_index].ping_ms = max(0, current_time - status_probe_started);
					official_servers[official_index].last_seen = current_time;
					official_servers[official_index].status_checking = false;
					official_servers[official_index].status_failed = false;

					/* Store an advertised label only when the server supplied visible text.
					An empty reply name does not overwrite an existing advertised name */
					if (server_name != "")
					{
						official_servers[official_index].advertised_name = server_name;
					}
				}

				close_status_probe();
				return true;

			/* A disconnect while checking means no complete status arrived. A probe that
			already finished only needs final socket cleanup */
			case network_type_disconnect:

				/* Mark failure only when the target row is valid and still awaiting status.
				Finished or unavailable row state takes ordinary close cleanup instead */
				if (official_index != noone
				&& official_index >= 0
				&& official_index < array_length(official_servers)
				&& official_servers[official_index].status_checking)
				{
					fail_status_probe();
				}

				/* When no valid row is still checking, close remaining probe ownership without
				claiming a new server-status failure */
				else
				{
					close_status_probe();
				}
				return true;
		}

		return true;
	}

	/// @description Rebuild grouped official, saved and native LAN rows from current status
	/// @returns {Array} UI rows with heading, availability and connection metadata
	build_server_list_entries = function()
	{
		/* entries accumulates UI rows from an empty list, entry_count starts zero for
		append positions, and saved_entries collects saved rows separately so headings
		remain grouped. Separator/empty rows carry label text and are never selectable */
		var entries = [];
		var entry_count = 0;
		var saved_entries = [];

		entries[entry_count++] =
		{
			kind: "separator",
			label: "Official Servers",
			selectable: false
		};

		/* A missing or empty official configuration gets a nonselectable explanation.
		Saved entries can still appear under their own heading */
		if (!is_array(net.official_servers) || array_length(net.official_servers) <= 0)
		{
			entries[entry_count++] =
			{
				kind: "empty",
				label: "No official servers configured.",
				selectable: false
			};
		}

		/* Normalize available official/saved runtime records into UI rows.
		An empty combined list skips the scan without suppressing section headings */
		if (array_length(official_servers) > 0)
		{
			/* Visit each zero-based normalized server record. Official rows append directly,
			while saved rows are collected for their later heading */
			for (var i = 0; i < array_length(official_servers); i++)
			{
				/* official is the normalized row. saved_index uses its field or noone for an
				older official shape, transport uses its field or TCP, and browser_ws identifies
				the browser WebSocket route. age is elapsed current_time since last_seen, or -1
				when unavailable. Placeholder/failure flags require their fields and true values */
				var official = official_servers[i];
				var saved_index = variable_struct_exists(official, "saved_index") ? official.saved_index : noone;
				var official_transport = variable_struct_exists(official, "transport") ? official.transport : TRANSPORT_TCP;
				var official_is_browser_ws = net.is_browser_runtime() && official_transport == TRANSPORT_WS;
				var official_age = official.last_seen >= 0 ? current_time - official.last_seen : -1;
				var official_is_placeholder = variable_struct_exists(official, "placeholder") && official.placeholder;
				var official_status_failed = variable_struct_exists(official, "status_failed") && official.status_failed;

				/* Both transport alternatives currently treat non-placeholder configured
				endpoints as connectable even without discovery. Actual connection determines
				reachability. This flag is not proof that a recent status reply arrived */
				var official_online = official_is_browser_ws
					? !official_is_placeholder
					: !official_is_placeholder;

				/* checking requires the optional active-probe flag. Browser freshness permits
				its longer probe interval plus timeout, while native freshness uses discovery_timeout.
				recent requires a nonnegative age within that limit. full needs recent valid counts
				at capacity. official_status starts ready before more specific states replace it */
				var official_checking = variable_struct_exists(official, "status_checking") && official.status_checking;
				var official_status_timeout = official_is_browser_ws
					? net.status_probe_interval_ms + net.status_probe_timeout_ms
					: net.discovery_timeout_ms;
				var official_recent = official_age >= 0 && official_age <= official_status_timeout;
				var official_full = official_recent && official.players >= 0
					&& official.max_players > 0
					&& official.players >= official.max_players;
				var official_status = "Ready to connect.";

				/* Browser rows use WebSocket probe state and placeholder feedback.
				Native rows use the separate UDP status timing path */
				if (official_is_browser_ws)
				{
					/* An unchanged public endpoint template needs configuration rather than a
					connection attempt, so show the setup message */
					if (official.placeholder)
					{
						official_status = "Set PUBLIC_WSS_ADDRESS before publishing.";
					}

					/* A browser probe still awaiting its reply shows checking before applying
					cached capacity or availability labels */
					else if (official_checking)
					{
						official_status = "Checking status...";
					}

					/* Fresh status at gameplay capacity shows full rather than a ready/online label */
					else if (official_full)
					{
						official_status = "Server is full.";
					}

					/* A fresh browser reply below capacity shows online. Stale or missing replies
					continue to the failure/ready alternatives */
					else if (official_recent)
					{
						official_status = "Online";
					}

					/* A failed browser status check shows unavailable status, while the configured
					endpoint can still be tried by its real connection path */
					else if (official_status_failed)
					{
						official_status = "Status unavailable.";
					}

					/* With no placeholder, active check, fresh reply or recorded failure, a browser
					endpoint stays ready to connect. Discovery is not required to try it */
					else
					{
						official_status = "Ready to connect.";
					}
				}

				/* Fresh native status at capacity also takes the full label before general
				online feedback */
				else if (official_full)
				{
					official_status = "Server is full.";
				}

				/* A recent native UDP reply below capacity shows online rather than waiting
				for another probe */
				else if (official_recent)
				{
					official_status = "Online";
				}

				/* A recorded native failure or an initial probe unanswered for the discovery
				timeout shows status unavailable. The endpoint remains available for a real join */
				else if (official_status_failed
				|| (official.first_probe >= 0 && current_time - official.first_probe >= net.discovery_timeout_ms))
				{
					official_status = "Status unavailable.";
					official_status_failed = true;
				}

				/* A saved route with no native discovery host is ready to connect instead of
				showing an impossible UDP scan as still checking */
				else if (saved_index != noone && official.discovery_ip == "")
				{
					official_status = "Ready to connect.";
				}

				/* Other native entries are still awaiting discovery. Show checking and set its
				UI flag while retaining configured connection routing */
				else
				{
					official_status = "Checking status...";
					official_checking = true;
				}

				/* The UI row keeps kind/source/saved index, name and connection endpoint.
				Fresh replies provide players/capacity/ping, otherwise -1 means unknown. last_seen
				retains its timestamp. online/full/placeholder determine joinable. checking/status
				carry feedback, and failure is shown only when no fresh reply supersedes it.
				Server rows remain selectable for inspection even when joining is unavailable */
				var list_entry =
				{
					kind: "server",
					source: saved_index == noone ? "official" : "saved",
					saved_index: saved_index,
					name: official.name,
					address: official.address,
					ip: official.ip,
					port: official.port,
					transport: official_transport,
					placeholder: official_is_placeholder,
					players: official_recent ? official.players : -1,
					max_players: official_recent ? official.max_players : -1,
					ping_ms: official_recent && variable_struct_exists(official, "ping_ms") ? official.ping_ms : -1,
					last_seen: official.last_seen,
					online: official_online,
					full: official_full,
					joinable: official_online && !official_full && !official_is_placeholder,
					checking: official_checking,
					status_failed: official_status_failed && !official_recent,
					status: official_status,
					selectable: true
				};

				/* Official rows append under the current heading. Saved indexes instead send
				the row to saved_entries so user entries appear under Saved Servers */
				if (saved_index == noone) entries[entry_count++] = list_entry;

				/* Keep saved rows aside for their own heading, preserving their edit/delete
				index rather than mixing them among official endpoints */
				else saved_entries[array_length(saved_entries)] = list_entry;
			}
		}

		entries[entry_count++] = { kind: "separator", label: "Saved Servers", selectable: false };

		/* An empty saved section gets an Add Server hint instead of an unexplained
		blank heading. Existing saved rows skip that hint */
		if (array_length(saved_entries) == 0)
		{
			entries[entry_count++] = { kind: "empty", label: "Choose Add Server to save a name and address.", selectable: false };
		}

		/* Append each collected saved row in zero-based order beneath its section
		heading, completing the user-list group before LAN rows */
		for (var saved_row = 0; saved_row < array_length(saved_entries); saved_row++)
		{
			entries[entry_count++] = saved_entries[saved_row];
		}

		/* Native builds can scan UDP LAN servers and show their heading.
		Browser builds skip this group because HTML5 has no LAN discovery socket */
		if (!net.is_browser_runtime())
		{
			entries[entry_count++] =
			{
				kind: "separator",
				label: "Found Local Servers",
				selectable: false
			};

			/* With no LAN replies yet, show a nonselectable scanning row.
			Once records exist, the alternative builds their current availability state */
			if (array_length(discovery_servers) <= 0)
			{
				entries[entry_count++] =
				{
					kind: "empty",
					label: "Scanning for games on your local network...",
					selectable: false
				};
			}

			/* LAN replies exist, so build selectable server rows rather than the empty
			scanning message */
			else
			{
				/* Visit each zero-based LAN record once. Its age and reported capacity determine
				online/full/joinable state for this UI rebuild */
				for (var j = 0; j < array_length(discovery_servers); j++)
				{
					/* local is this LAN record and local_age is milliseconds since last_seen.
					Online means age remains within discovery_timeout. Full requires online status and
					known valid counts at capacity, avoiding capacity decisions from stale replies */
					var local = discovery_servers[j];
					var local_age = current_time - local.last_seen;
					var local_online = local_age <= net.discovery_timeout_ms;
					var local_full = local_online
						&& local.players >= 0
						&& local.max_players > 0
						&& local.players >= local.max_players;

					/* A LAN server row uses its advertised name, address, network
					host/port and TCP transport. Counts/time/ping reflect the record, with missing ping
					shown as -1. Online and not full permits joining. It is not actively checking,
					and status selects full, online or unavailable in that priority order */
					entries[entry_count++] =
					{
						kind: "server",
						source: "local",
						name: local.name,
						address: local.address,
						ip: local.ip,
						port: local.port,
						transport: TRANSPORT_TCP,
						players: local.players,
						max_players: local.max_players,
						ping_ms: variable_struct_exists(local, "ping_ms") ? local.ping_ms : -1,
						last_seen: local.last_seen,
						online: local_online,
						full: local_full,
						joinable: local_online && !local_full,
						checking: false,
						status: local_full ? "Server is full." : (local_online ? "Online" : "Can't connect to server"),
						selectable: true
					};
				}
			}
		}

		server_list_entries = entries;
		return server_list_entries;
	}

	/// @description Clear received rows and force the runtime-supported status/discovery refresh
	refresh_discovery = function()
	{
		close_status_probe();
		sync_official_servers(true);
		discovery_found = false;
		discovery_address = "";
		discovery_servers = [];
		server_list_entries = [];

		/* Refresh messaging describes browser WebSocket selection or native LAN scanning
		according to runtime support, matching the discovery path below */
		discovery_status = net.is_browser_runtime()
			? "Browser build uses WebSockets. Select the official server or type a WSS address."
			: "Scanning for servers on your local network...";
		next_discovery_request = 0;

		/* Browsers refresh configured routes and optional status probing, then rebuild
		the UI without creating a UDP socket */
		if (net.is_browser_runtime())
		{
			send_browser_status_probe(true);
			build_server_list_entries();
			return;
		}

		/* Start native discovery only when no valid scan socket exists.
		An existing scan handle is reused for the forced refresh request */
		if (!is_real(discovery_socket) || discovery_socket < 0)
		{
			start_discovery();
		}

		send_discovery_request(true);
	}

	/// @description Reuse or allocate native UDP scanning, or configure browser-only server rows
	/// @returns {Real} Owned discovery socket, a negative creation result, or noone for browsers
	start_discovery = function()
	{
		/* Browser startup builds configured WebSocket rows and explains that UDP LAN
		scanning is unavailable. It returns noone rather than allocating a native socket */
		if (net.is_browser_runtime())
		{
			close_status_probe();
			sync_official_servers(false);
			discovery_servers = [];
			server_list_entries = [];
			discovery_status = "Browser build uses WebSockets. LAN discovery is not available in HTML5.";
			send_browser_status_probe(true);
			debug_log(discovery_status);
			return noone;
		}

		/* Reuse an existing native scan socket. Repeated startup must not leak a second
		socket/buffer pair */
		if (is_real(discovery_socket) && discovery_socket >= 0)
		{
			return discovery_socket;
		}

		discovery_found = false;
		discovery_address = "";
		sync_official_servers(false);
		discovery_servers = [];
		server_list_entries = [];
		discovery_socket = network_create_socket_ext(network_socket_udp, net.discovery_port);
		discovery_listen_port = net.discovery_port;

		/* If binding the shared UDP discovery port fails, try an unbound scan socket.
		The listen-port marker becomes noone because replies use its assigned local port */
		if (discovery_socket < 0)
		{
			debug_error("LAN discovery could not listen on UDP port " + string(net.discovery_port) + ". Trying fallback scan socket.");
			discovery_socket = network_create_socket(network_socket_udp);
			discovery_listen_port = noone;

			/* If the fallback also fails, report scanning unavailable and return the
			creation error. Manual address connection remains possible */
			if (discovery_socket < 0)
			{
				discovery_status = "LAN scan failed. You can still type the server address manually.";
				debug_error(discovery_status);
				return discovery_socket;
			}
		}

		/* Create the client-owned byte-aligned discovery writer after socket success.
		Its 256-byte initial capacity can grow, and stop_discovery deletes it */
		discovery_buffer = buffer_create(256, buffer_grow, 1);
		discovery_status = "Scanning for servers on your local network...";
		next_discovery_request = 0;
		debug_log("LAN discovery scan started on UDP port " + string(discovery_listen_port) + ". Sending requests to UDP port " + string(net.discovery_port));
		return discovery_socket;
	}

	/// @description Remove expired UDP echo records backward without skipping shifted entries
	cleanup_discovery_ping_requests = function()
	{
		/* Scan ping records backward from the final index so deleting expired entries
		does not skip records shifted by array deletion */
		for (var i = array_length(discovery_ping_requests) - 1; i >= 0; i--)
		{
			/* Retire correlation records older than the discovery timeout.
			Recent records remain available to measure echoed reply round trips */
			if (current_time - discovery_ping_requests[i].sent_time > net.discovery_timeout_ms)
			{
				array_delete(discovery_ping_requests, i, 1);
			}
		}
	}

	/// @description Record a new clock/sequence echo ID for discovery round-trip measurement
	/// @returns {String} Request ID retained with its current_time send timestamp
	make_discovery_request_id = function()
	{
		discovery_ping_sequence++;

		/* request_id combines the current millisecond clock and increasing sequence
		for echo correlation. Its record stores that text and sent_time on the same clock */
		var request_id = string(current_time) + "_" + string(discovery_ping_sequence);
		discovery_ping_requests[array_length(discovery_ping_requests)] =
		{
			request_id: request_id,
			sent_time: current_time
		};
		cleanup_discovery_ping_requests();
		return request_id;
	}

	/// @description Measure elapsed time for a retained echoed discovery request
	/// @param {String} request_id Echo ID, with empty meaning unavailable
	/// @returns {Real} Nonnegative milliseconds or -1 without correlation
	get_discovery_ping_ms = function(request_id)
	{
		/* An older broadcast/reply without an echoed ID has no measured round trip.
		Return -1 so unavailable ping is distinct from a real zero-millisecond reply */
		if (string(request_id) == "")
		{
			return -1;
		}

		/* Search every zero-based retained ping record for this echo ID.
		No match returns unavailable ping rather than using another request clock */
		for (var i = 0; i < array_length(discovery_ping_requests); i++)
		{
			/* A matching echo identifies its original send timestamp. Return nonnegative
			elapsed current_time milliseconds for that request */
			if (discovery_ping_requests[i].request_id == request_id)
			{
				return max(0, current_time - discovery_ping_requests[i].sent_time);
			}
		}

		return -1;
	}

	/// @description Broadcast native discovery and probe resolved configured UDP endpoints
	/// @param {Bool} force Bypass the next scan deadline, defaulting to false
	/// @returns {Real} LAN broadcast result, zero when skipped, or -1 without usable resources
	send_discovery_request = function(force = false)
	{
		/* Browsers cannot send native UDP discovery, so return zero without treating
		unsupported scanning as a gameplay connection failure */
		if (net.is_browser_runtime())
		{
			return 0;
		}

		/* A missing or failed scan socket cannot send a request. Return -1 before
		building or broadcasting discovery bytes */
		if (!is_real(discovery_socket) || discovery_socket < 0)
		{
			return -1;
		}

		/* Require the client-owned discovery writer to exist before seeking/writing.
		A missing/deleted buffer makes the scan attempt fail */
		if (is_undefined(discovery_buffer) || !buffer_exists(discovery_buffer))
		{
			return -1;
		}

		/* Ordinary scans wait for their millisecond deadline, while a forced refresh
		bypasses the interval. Both advance the next schedule after an eligible attempt */
		if (!force && current_time < next_discovery_request)
		{
			return 0;
		}

		next_discovery_request = current_time + net.discovery_interval_ms;

		resolve_discovery_domains();

		/* Create an echo ID and retain its send timestamp for UDP round-trip matching.
		The pipe-separated text packet carries magic, REQUEST, brand name and this ID */
		var request_id = make_discovery_request_id();

		buffer_seek(discovery_buffer, buffer_seek_start, 0);

		/* The request label is readable metadata.
		discovery_magic is the compatibility check */
		buffer_write(discovery_buffer, buffer_string, net.discovery_magic + "|REQUEST|" + net.game_name + "|" + request_id);

		/* packet_size is the written text-packet byte count. send_result captures LAN
		broadcast delivery, while configured unicast probes are attempted separately */
		var packet_size = buffer_tell(discovery_buffer);
		var send_result = network_send_broadcast(discovery_socket, net.discovery_port, discovery_buffer, packet_size);

		/* Visit configured zero-based targets and send the same request to resolved
		IPv4 discovery endpoints as well as the LAN broadcast */
		for (var i = 0; i < array_length(official_servers); i++)
		{
			/* Unicast only to a validated resolved IPv4 target. Unresolved hostnames wait
			for DNS rather than being passed to the UDP send */
			if (is_ipv4_address(official_servers[i].discovery_ip))
			{
				/* Record first_probe once on the current_time clock so initial timeout feedback
				has a stable origin. last_probe advances for every actual unicast attempt */
				if (official_servers[i].first_probe < 0)
				{
					official_servers[i].first_probe = current_time;
				}

				official_servers[i].last_probe = current_time;
				network_send_udp(discovery_socket, official_servers[i].discovery_ip, official_servers[i].discovery_port, discovery_buffer, packet_size);
			}
		}

		/* A failed LAN broadcast updates scan feedback and logs the transport result.
		Configured unicast attempts already ran, so this does not claim they all failed */
		if (send_result < 0)
		{
			discovery_status = "LAN scan could not send a broadcast. You can still type the server address manually.";
			net.log_send_error("LAN discovery request failed. result=" + string(send_result));
		}

		return send_result;
	}

	/// @description Close browser status probing and release owned native discovery resources
	stop_discovery = function()
	{
		close_status_probe();
		discovery_dns_requests = [];

		/* Destroy only a valid client-owned UDP scan socket. Failed/absent handles
		need no resource release */
		if (is_real(discovery_socket) && discovery_socket >= 0)
		{
			network_destroy(discovery_socket);
		}

		/* Delete the writer only when allocated and still existing.
		Then restore absent discovery handles/listen-port state for a later restart */
		if (!is_undefined(discovery_buffer) && buffer_exists(discovery_buffer))
		{
			buffer_delete(discovery_buffer);
		}

		discovery_socket = noone;
		discovery_buffer = noone;
		discovery_listen_port = noone;
	}

	/// @description Consume only the client discovery UDP socket before binary packet parsing
	/// @param {Real} network_id Async id field
	/// @param {Id.Buffer} network_data Borrowed packet buffer
	/// @param {String} network_ip UDP source IP
	/// @param {Real} network_port UDP source port
	/// @returns {Bool} Whether the event belongs to discovery, including ignored malformed replies
	handle_discovery_async = function(network_id, network_data, network_ip, network_port)
	{
		/* Only a valid event ID matching the valid client scan socket belongs here.
		Other events return false so binary gameplay routing remains available */
		if (!is_real(discovery_socket)
		|| discovery_socket < 0
		|| !is_real(network_id)
		|| network_id < 0
		|| network_id != discovery_socket)
		{
			return false;
		}

		/* A discovery-owned event with no live buffer is consumed but ignored.
		Return true so malformed UDP does not enter binary gameplay packet decoding */
		if (is_undefined(network_data) || !buffer_exists(network_data))
		{
			return true;
		}

		/* Ignore empty or over-2-KiB discovery buffers before string decoding.
		This text protocol has no need to accept arbitrary large packet data */
		if (buffer_get_size(network_data) <= 0 || buffer_get_size(network_data) > 2048) return true;
		buffer_seek(network_data, buffer_seek_start, 0);

		/* message begins empty and receives the text packet in try. A failed string
		read is consumed without changing discovered servers */
		var message = "";
		try { message = buffer_read(network_data, buffer_string); }
		catch (read_error) { return true; }

		/* parts holds the pipe-delimited discovery fields. The protocol begins with
		matching project magic, RESPONSE and advertised game port */
		var parts = string_split(message, "|");

		/* At least three fields, exact project/protocol magic and RESPONSE kind are
		required. Ignore foreign games and nonreply traffic on the shared UDP port */
		if (array_length(parts) < 3 || parts[0] != net.discovery_magic || parts[1] != "RESPONSE")
		{
			return true;
		}

		/* The advertised game port needs one to five decimal digits. Reject malformed
		text before converting it, keeping discovery metadata within its wire format */
		if (parts[2] == "" || string_length(parts[2]) > 5 || string_digits(parts[2]) != parts[2]) return true;

		/* found_port is the advertised game destination port after decimal validation,
		which may be an internal port for a publicly forwarded server */
		var found_port = real(parts[2]);

		/* Reject out-of-range advertised ports rather than adding an unusable server
		connection target to the list */
		if (found_port < 1 || found_port > 65535)
		{
			return true;
		}

		/* found_ip is the actual UDP source with any mapped-IPv4 prefix removed.
		It identifies the machine answering instead of trusting a claimed host in text */
		var found_ip = normalize_discovery_ip(network_ip);

		/* An absent source address cannot form a usable discovery endpoint.
		Consume the reply without adding an empty-host server */
		if (found_ip == "")
		{
			return true;
		}

		/* Use the branded fallback when an older/minimal reply lacks a name.
		An optional nonempty fourth field replaces this label */
		var server_name = net.default_server_name;

		/* Use the advertised name only when its field exists and has text.
		Otherwise retain the branded fallback */
		if (array_length(parts) >= 4 && string(parts[3]) != "")
		{
			server_name = string(parts[3]);
		}

		/* Reported players/capacity start -1 as unknown for older replies.
		Both are replaced together only when the two optional count fields exist */
		var player_count = -1;
		var player_max = -1;

		/* Decode counts only when both optional fields are present. Replies without
		them keep unknown capacity rather than inventing zero players */
		if (array_length(parts) >= 6)
		{
			/* Validate the two zero-based count fields at indexes four and five.
			Both must be the unknown sentinel or bounded decimal text before conversion */
			for (var count_index = 4; count_index <= 5; count_index++)
			{
				/* count_text is this players/capacity field, permitting -1 for unknown but
				requiring decimal digits for an actual count */
				var count_text = parts[count_index];

				/* Accept the explicit unknown marker or one-to-five decimal digits.
				Malformed counts consume the reply without updating list capacity state */
				if (count_text != "-1" && (count_text == "" || string_length(count_text) > 5 || string_digits(count_text) != count_text)) return true;
			}
			player_count = real(parts[4]);
			player_max = real(parts[5]);
		}

		/* The echo ID starts absent for unsolicited or older replies.
		A seventh field supplies correlation with a retained ping send timestamp */
		var response_request_id = "";

		/* Read the optional echo ID only when present. Otherwise ping remains
		unavailable instead of borrowing another request timestamp */
		if (array_length(parts) >= 7)
		{
			response_request_id = string(parts[6]);
		}

		/* ping_ms is elapsed client milliseconds or -1 without correlation.
		found_address combines actual source IP and advertised game port. server_entry
		stores visible name, endpoint/counts/ping and a current_time last_seen timestamp */
		var ping_ms = get_discovery_ping_ms(response_request_id);
		var found_address = found_ip + ":" + string(found_port);
		var server_entry =
		{
			name: server_name,
			address: found_address,
			ip: found_ip,
			port: found_port,
			players: player_count,
			max_players: player_max,
			ping_ms: ping_ms,
			last_seen: current_time
		};

		/* Match configured forwarding-aware endpoints before creating a LAN row.
		The UDP source port and correlated ping help distinguish public port mappings */
		var official_index = find_official_server_by_response(found_ip, found_port, network_port, ping_ms);

		/* Feedback initially describes a local address. A matched configured row
		replaces status_address with its public target and selects official/saved wording */
		var status_address = found_address;
		var status_label = "Found local server: ";

		/* A matched configured endpoint updates its aliases rather than adding a
		separate row based on the server internal advertised game port */
		if (official_index != noone)
		{
			/* matched_server is the identified configured public endpoint. Use its resolved
			host and expected game port for alias matching, rather than the advertised
			internal port. Separate forwarded servers can all advertise port 8080 */
			var matched_server = official_servers[official_index];

			/* Scan all configured zero-based entries to update aliases of the matched
			address/public endpoint, leaving other forwarded servers untouched */
			for (var match_index = 0; match_index < array_length(official_servers); match_index++)
			{
				/* match is one configured alias candidate. same_public_endpoint requires a
				nonempty shared discovery IP plus the same configured public game-response port */
				var match = official_servers[match_index];
				var same_public_endpoint = match.discovery_ip != ""
					&& match.discovery_ip == matched_server.discovery_ip
					&& match.discovery_response_port == matched_server.discovery_response_port;

				/* Skip entries that are neither the selected row, the same connection address
				nor the same public game endpoint. Matching only an internal advertised port
				would incorrectly merge separate forwarded servers */
				if (match_index != official_index && match.address != matched_server.address && !same_public_endpoint) continue;
				match.players = player_count;
				match.max_players = player_max;

				/* Replace ping only with an actual correlated measurement.
				An older uncorrelated broadcast leaves the prior valid ping intact */
				if (ping_ms >= 0) match.ping_ms = ping_ms;
				match.last_seen = current_time;
				match.status_checking = false;
				match.status_failed = false;
				match.advertised_name = server_name;
			}
			status_address = official_servers[official_index].address;

			/* noone saved identity marks a configured official row. A real saved index
			uses saved-server wording while preserving the configured public address */
			status_label = official_servers[official_index].saved_index == noone ? "Found official server: " : "Found saved server: ";
		}

		/* An unmatched reply belongs to the LAN collection. Refresh its canonical
		address entry if present, otherwise append a new record */
		else
		{
			/* server_index locates an existing LAN address or noone for its first reply.
			This prevents repeat announcements from producing duplicate local rows */
			var server_index = find_discovery_server(found_address);

			/* A first reply for this LAN address appends the populated record.
			Existing rows use the replacement path instead */
			if (server_index == noone)
			{
				discovery_servers[array_length(discovery_servers)] = server_entry;
			}

			/* Refresh the existing LAN row counts, ping and last_seen timestamp rather
			than adding another copy of the same endpoint */
			else
			{
				discovery_servers[server_index] = server_entry;
			}
		}

		/* Publish found-server feedback only when the selected address changes.
		Repeated replies still refresh metadata without logging the same discovery each time */
		if (status_address != discovery_address)
		{
			discovery_address = status_address;
			discovery_found = true;
			discovery_status = status_label + discovery_address;
			debug_success(discovery_status);
		}

		return true;
	}
	#endregion /* LAN Discovery END */

	#region /* Async Router */
	/// @description Check whether either event handle matches client gameplay, status or discovery ownership
	/// @param {Real} network_id Async id handle
	/// @param {Real} network_socket Async socket handle
	/// @param {Real} network_server Retained listener field, defaulting to noone and unused by this client check
	/// @returns {Bool} Whether a valid owned socket matches
	owns_socket_event = function(network_id, network_socket, network_server = noone)
	{
		/* id_is_valid/socket_is_valid distinguish usable actual event handles from
		missing/negative IDs before comparing client-owned gameplay, status or discovery
		sockets. The optional listener parameter is retained but unused by this check */
		var id_is_valid = is_real(network_id) && network_id >= 0;
		var socket_is_valid = is_real(network_socket) && network_socket >= 0;

		/* With neither valid event handle, no client-owned socket can match.
		Return false before evaluating ownership alternatives */
		if (!id_is_valid && !socket_is_valid)
		{
			return false;
		}

		/* An event belongs to the client when either valid event field matches its
		valid gameplay, status-probe or discovery handle. These are actual socket IDs,
		independent of logical player slots */
		return (is_real(socket) && socket >= 0
			&& ((id_is_valid && network_id == socket) || (socket_is_valid && network_socket == socket)))
			|| (is_real(status_probe_socket) && status_probe_socket >= 0
			&& ((id_is_valid && network_id == status_probe_socket) || (socket_is_valid && network_socket == status_probe_socket)))
			|| (is_real(discovery_socket) && discovery_socket >= 0
			&& ((id_is_valid && network_id == discovery_socket) || (socket_is_valid && network_socket == discovery_socket)));
	}

	/// @description Restrict gameplay routing to the current valid client socket
	/// @param {Real} network_id Async id handle
	/// @param {Real} network_socket Async socket handle
	/// @returns {Bool} Whether either field identifies the active gameplay connection
	is_active_socket_event = function(network_id, network_socket)
	{
		/* Without a valid gameplay socket, no event can belong to the active session.
		Reject it rather than matching a stale/absent handle */
		if (!is_real(socket) || socket < 0)
		{
			return false;
		}

		/* Either async id or socket may identify the active connection.
		Matching one accepts the gameplay event, while unmatched handles are stale/other */
		return network_id == socket || network_socket == socket;
	}

	/// @description Route status probes separately, then handle only the active gameplay socket
	/// @param {Real} network_id Async id field
	/// @param {Real} network_type GameMaker network event type
	/// @param {Real} network_socket Async socket field
	/// @param {Id.Buffer} network_data Borrowed packet buffer
	/// @param {Real} network_server Retained listener field, defaulting to noone and unused by this body
	on_async = function(network_id, network_type, network_socket, network_data, network_server = noone)
	{
		/* async_name is the diagnostic label for this event type, leaving raw numeric
		IDs available beside it for unfamiliar event cases */
		var async_name = net.event_type_to_string(network_type);

		/* Log connection/lifecycle events normally. Frequent data events get this
		extra routing log only in verbose mode */
		if (network_type != network_type_data || net.verbose)
		{
			debug_log("Client async event: " + async_name + " (" + string(network_type) + "), socket=" + string(network_socket) + ", id=" + string(network_id));
		}

		/* A consumed status-probe event must stop before gameplay routing.
		Its socket belongs to an independent listing query, not the joined player session */
		if (handle_status_probe_async(network_id, network_type, network_socket, network_data))
		{
			return;
		}

		/* Ignore unrelated or stale gameplay handles after the probe path has had its
		chance. A prior connection event cannot reset the current client session */
		if (!is_active_socket_event(network_id, network_socket))
		{
			net.log_verbose("Ignoring client async event for stale socket " + string(network_socket));
			return;
		}

		/* Route active gameplay connection completion, disconnection and data.
		Other event types only produce optional diagnostics */
		switch(network_type)
		{

			#region /* Connection Events */
			/* Async completion requires an explicit success flag before submitting the
			join request. Missing/false success can fail a still-pending attempt */
			case network_type_non_blocking_connect:

				/* Connection success begins false until the async map reports numeric one.
				An absent succeeded field must not authorize a join */
				var succeeded = false;

				/* Read the success field only when present. Numeric one sets true, while other
				values preserve failure behavior */
				if (ds_map_exists(async_load, "succeeded"))
				{
					succeeded = async_load[? "succeeded"] == 1;
				}

				/* Successful completion advances the pending join through its duplicate-safe
				method. Failure continues to the pending-connect alternative */
				if (succeeded)
				{
					complete_socket_connect();
				}

				/* Only a still-pending unsuccessful connection gets failure cleanup.
				An already settled session ignores this failure event */
				else if (connect_pending)
				{
					fail_pending_connect("Could not connect to " + connect_address);
				}
				break;

			/* The direct connect event uses the same guarded completion method, so either
			GameMaker completion form cannot send the join twice */
			case network_type_connect:
				complete_socket_connect();
				break;

			/* Release the active socket and clear session identity/admin waits.
			Client-only world cleanup preserves shared local-server state when hosting */
			case network_type_disconnect:

				/* Show unexpected connection loss only before a return-to-list transition
				already recorded its intentional reason. Existing list feedback remains intact */
				if (!needs_server_list)
				{
					connect_status = "Lost connection to server.";
					connect_failed_message = connect_status;
				}
				net.unregister_socket_transport(socket);
				network_destroy(socket);
				socket = noone;
				ID = noone;
				host_player_slot = noone;
				assigned_username = "";
				join_request_sent = false;
				admin_connection_intent = false;
				reset_admin_session();
				connect_pending = false;
				connect_deadline = 0;
				needs_server_list = true;
				reset_disconnected_client_state();
				debug_error("Client disconnected from socket " + string(network_socket));
				break;
			#endregion /* Connection Events END */

			#region /* Data Packets */
			/* Incoming gameplay data refreshes the current_time last-heard clock before
			packet dispatch, allowing the watchdog to distinguish silence from active traffic */
			case network_type_data:
				last_server_heard = current_time;
				scr_on_data_client();

				/* packet_name labels the dispatched packet for diagnostics without rereading
				its body or changing its shared reader cursor */
				var packet_name = net.message_type_to_string(net.header.type);

				/* Log packet summaries according to normal/verbose suppression rules.
				Routine movement/drawing traffic can remain quiet while still being fully processed */
				if (net.should_log_packet(net.header.type))
				{
					debug_log("Client data packet: " + packet_name + " (" + string(net.header.type) + "), receiver=" + scr_network_debug_client_label() + ", sender=" + scr_network_debug_id_text(net.header.socketID));
				}
				break;
			#endregion /* Data Packets END */

			/* Unsupported active-socket events perform no session operation.
			Verbose logging retains their numeric type for investigation */
			default:
				net.log_verbose("Client async event ignored (type=" + string(network_type) + ")");
				break;
		}
	}
	#endregion /* Async Router END */

}

/// @description Get the process-wide client session. Creates it on first use
/// @returns {Struct} Shared scr_client instance
function scr_get_client()
{
	/* Create the process-wide client once on first access. Repeated callers share
	its socket, discovery state and session methods instead of allocating new clients */
	static n = new scr_client();
	return n;
}
