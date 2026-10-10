#macro Network scr_get_network()
#macro GAME_DISPLAY_NAME "Jonnil Online"
#macro GAME_DISCOVERY_PROTOCOL_VERSION 1
#macro PUBLIC_WSS_ADDRESS "wss://online.jonnil.games/ws"
#macro PUBLIC_WSS_STATUS_ADDRESS "wss://online.jonnil.games/status"
#macro TRANSPORT_TCP 0
#macro TRANSPORT_WS 1
#macro TRANSPORT_UDP 2

/// @description Build the shared LAN-discovery brand key from the game display name
/// @param {String} display_name Game name. Non-alphanumeric runs become underscores
/// @returns {String} Uppercase key, or ONLINE_GAME when no letters or digits remain
function scr_network_make_brand_key(display_name)
{
	var raw = string_upper(string(display_name)); /* Uppercase display-name text, giving discovery peers the same case */
	var key = ""; /* Discovery identifier accumulated from usable name characters */
	var last_was_separator = false; /* Tracks whether an underscore was just emitted, initially false */

	/* Walk the display name from its first character to its last. GML strings use
	one-based positions, and every character contributes either a letter, digit,
	or separator to the shared discovery key */
	for (var i = 1; i <= string_length(raw); i++)
	{
		var ch = string_char_at(raw, i); /* Current one-based display-name character */
		var is_letter = string_pos(ch, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") > 0; /* Whether this character belongs to the accepted uppercase alphabet */
		var is_number = string_pos(ch, "0123456789") > 0; /* Whether this character is an accepted decimal digit */

		/* Letters and digits remain in the key so both peers derive the same project
		identifier from its display name. Other characters use the separator path */
		if (is_letter || is_number)
		{
			key += ch;
			last_was_separator = false;
		}

		/* Add one underscore after an existing word. Leading punctuation and repeated
		separators add nothing, keeping the discovery identifier predictable */
		else if (!last_was_separator && key != "")
		{
			key += "_";
			last_was_separator = true;
		}
	}

	/* Remove trailing separator characters until a word ends the key or it becomes
	empty. Checking length first prevents reading a nonexistent final character */
	while (string_length(key) > 0
	&& string_char_at(key, string_length(key)) == "_")
	{
		key = string_delete(key, string_length(key), 1);
	}

	/* A display name containing only punctuation has no usable identifier.
	Use the stable fallback so discovery packets still carry a nonempty brand key */
	if (key == "")
	{
		key = "ONLINE_GAME";
	}

	return key;
}

/// @description Create the shared transport registry and reusable packet writer/reader
function scr_network() constructor
{

	#region /* Project Branding */
	/* Edit GAME_DISPLAY_NAME above when this framework becomes a new game.
	Runtime UI and network discovery labels are built from this one string.
	GameMaker project names, exported filenames, icons, and target metadata can still
	need separate changes in Game Options because they are not runtime GML values */
	game_name = GAME_DISPLAY_NAME;
	game_key = scr_network_make_brand_key(game_name);
	official_server_name = game_name + " Official";
	lan_server_name = game_name + " LAN World";
	default_server_name = game_name + " Server";
	#endregion /* Project Branding END */

	/* The native connection defaults to TCP at the loopback host and port below.
	The discovery port receives LAN UDP announcements, websocket_port serves local
	WebSocket clients, and websocket_public_port is the secure public endpoint */
	type = network_socket_tcp;
	url = "127.0.0.1";
	port = 8080;
	discovery_port = 8081;
	websocket_port = 8082;
	websocket_public_port = 443;

	/* The gameplay and status WebSocket routes come from the project endpoint macros.
	Native manual input starts at the loopback TCP address, while browser input
	starts at the public gameplay route */
	public_websocket_address = PUBLIC_WSS_ADDRESS;
	public_websocket_status_address = PUBLIC_WSS_STATUS_ADDRESS;
	native_default_address = url + ":" + string(port);
	browser_default_address = public_websocket_address;

	/* Discovery magic is a project/protocol identifier, not an executable name.
	Clients and servers only discover each other when this value matches.
	The version suffix lets a future incompatible framework change ignore old servers */
	discovery_magic = game_key + "_LAN_" + string(GAME_DISCOVERY_PROTOCOL_VERSION);

	/* Broadcast LAN availability every discovery_interval_ms milliseconds.
	discovery_timeout_ms removes a server after five seconds without an announcement.
	Both schedules use current_time rather than Step counts */
	discovery_interval_ms = 1000;
	discovery_timeout_ms = 5000;

	/* Disabled for now because extra browser status sockets have triggered Runner AppHang regressions */
	status_probes_enabled = false;

	/* Status probes, when enabled, wait 60 seconds between requests and expire after
	five seconds. connect_timeout_ms gives an asynchronous gameplay connection ten
	seconds before the client reports a timeout */
	status_probe_interval_ms = 60000;
	status_probe_timeout_ms = 5000;
	connect_timeout_ms = 10000;

	/* 10s x 3 keeps heartbeat traffic tiny while clearing forced-close clients in about 30s */
	client_heartbeat_interval_ms = 10000;
	client_heartbeat_missed_limit = 3;

	/* Socket/player storage reserves 128 aligned slots so a public server's saved
	gameplay limit can change without rebuilding its arrays or listeners. Ten keeps
	the earlier default, while the one-to-100 range is the supported settings policy.
	Join acceptance checks this logical limit separately from available storage.
	These bounds are project defaults, not a measured guarantee of server performance */
	max_clients = 128;
	default_max_players = 10;
	min_player_limit = 1;
	max_player_limit = 100;

	/* This list seeds discovery before LAN announcements. Entries carry a UI name,
	native TCP address, browser gameplay/status routes and UDP discovery port.
	Update it when official addresses change. Internet tests need a public IP or
	domain after port forwarding. Private 192.168.x.x addresses serve the same LAN */
	official_servers =
	[
		{
			name: official_server_name,
			address: "online.jonnil.games:28080",
			websocket_address: public_websocket_address,
			websocket_status_address: public_websocket_status_address,
			discovery_port: 28081
		}
	];

	/* Verbose packet logging starts disabled. last_send_error begins empty and
	next_send_error_time starts at zero on the current_time millisecond clock, so
	the first send failure can be reported immediately without duplicate-log delay */
	verbose = false;
	last_send_error = "";
	next_send_error_time = 0;

	/* Parallel failure lists begin empty. Their matching entries identify the
	logical player slot and actual socket handle for server cleanup after a broadcast.
	tracked_sockets and tracked_transports form a separate empty transport registry */
	failed_send_slots = [];
	failed_send_sockets = [];
	tracked_sockets = [];
	tracked_transports = [];

	/* The shared writer owns a growable byte-aligned buffer, initially 1,024 bytes.
	start rewinds it and write appends packet fields. It lives with the shared network
	service rather than being created for each packet */
	buffer = buffer_create(1024, buffer_grow, 1);

	/* The reader borrows an async-event buffer rather than owning it. A negative
	handle and zero received length mark an unprimed reader. header begins without
	fields and prime_reader adds its packet type and logical sender slot */
	reader_buffer = -1;
	reader_size = 0;
	header = {};

	/// @description Name an async network event for diagnostics
	/// @param {Real} network_type GameMaker network event constant
	/// @returns {String} Known event name, or UNKNOWN
	event_type_to_string = function(network_type)
	{
		/* Match async event constants to diagnostic labels. An unknown constant
		returns UNKNOWN so logs still show an unexpected event */
		switch (network_type)
		{
			case network_type_connect: return "CONNECT";
			case network_type_disconnect: return "DISCONNECT";
			case network_type_data: return "DATA";
			case network_type_non_blocking_connect: return "NON_BLOCKING_CONNECT";
			default: return "UNKNOWN";
		}
	}

	#region /* Transport Helpers */
	/// @description Identify browser runtimes that need browser transport
	/// @returns {Bool} Whether the browser or GX.games route applies
	is_browser_runtime = function()
	{
		/* A browser host or GX.games runtime needs the browser transport route.
		Native builds return false and keep the TCP default */
		return (os_browser != browser_not_a_browser) || (os_type == os_gxgames);
	}

	/// @description Name a transport ID for diagnostic text
	/// @param {Real} transport TRANSPORT value
	/// @returns {String} Readable transport name, or Unknown
	transport_to_string = function(transport)
	{
		/* Name the recognized transports. An unsupported ID gets the Unknown label
		rather than implying it uses a valid connection type */
		switch (transport)
		{
			case TRANSPORT_TCP: return "TCP";
			case TRANSPORT_WS: return "WebSocket";
			case TRANSPORT_UDP: return "UDP";
			default: return "Unknown";
		}
	}

	/// @description Choose the runtime-supported initial client transport
	/// @returns {Real} WebSocket for browsers, otherwise TCP
	default_client_transport = function()
	{
		/* Browsers use WebSocket because they cannot open the native TCP connection.
		Native builds use TCP unless an explicit address selects another transport */
		return is_browser_runtime() ? TRANSPORT_WS : TRANSPORT_TCP;
	}

	/// @description Choose the runtime-appropriate initial manual address
	/// @returns {String} Public browser route or native loopback address
	default_manual_address = function()
	{
		/* Show the public browser route in browser input and loopback TCP in native
		input, matching the transport each runtime can open by default */
		return is_browser_runtime() ? browser_default_address : native_default_address;
	}

	/// @description Detect a domain template that has not been configured
	/// @param {String} address Proposed server address
	/// @returns {Bool} Whether the placeholder marker remains
	is_public_wss_placeholder = function(address)
	{
		/* An address containing the template domain marker is still unconfigured.
		The caller uses this result to prevent treating that placeholder as a server */
		return string_pos("REPLACE_WITH_DOMAIN", string_upper(string(address))) > 0;
	}

	/// @description Compare an exact text prefix after string conversion
	/// @param {Any} text Value to inspect
	/// @param {Any} prefix Expected starting text
	/// @returns {Bool} Whether the prefix matches
	text_starts_with = function(text, prefix)
	{
		var target = string(text); /* Prefix-test text normalized to a string */
		var start = string(prefix); /* Prefix string that the caller wants to match */

		/* Only a prefix at the beginning matches. Address parsing uses this result
		to select a scheme without mistaking matching text elsewhere in the URL */
		return string_copy(target, 1, string_length(start)) == start;
	}

	/// @description Find the final possible host/port separator
	/// @param {String} text Address text to scan
	/// @returns {Real} One-based colon position, or zero when absent
	find_last_colon = function(text)
	{
		/* The last-colon position starts at zero to mean no separator was found.
		Scanning all one-based string positions lets a later colon replace an earlier one */
		var result = 0;

		/* Scan all one-based characters for the final colon. Finishing without a match
		leaves zero, marking an address with no explicit port separator */
		for (var i = 1; i <= string_length(text); i++)
		{
			/* Retain each colon position so the final match identifies the possible port
			separator. Characters other than a colon leave the current result unchanged */
			if (string_char_at(text, i) == ":")
			{
				result = i;
			}
		}

		return result;
	}

	/// @description Normalize an address without opening a connection
	/// @param {String} address Host:port or ws/wss URL
	/// @param {Real} default_port Fallback port, defaulting to undefined for the native port or public WebSocket port. Explicit ws/wss schemes use their configured ports
	/// @param {Real} default_transport TRANSPORT fallback, defaulting to undefined for the runtime default. An explicit ws/wss scheme selects WebSocket
	/// @returns {Struct} Parsed target with ok, url, port, address, display_address, placeholder, and failure message
	parse_server_address = function(address, default_port = undefined, default_transport = undefined)
	{
		/* Build the parse result in a failure state. Empty host/address/message fields,
		port zero and placeholder false do not describe a connection yet. transport uses
		the caller override when supplied, otherwise the runtime default. Successful
		branches populate url for connection, address/display_address for UI, and ok */
		var result =
		{
			ok: false,
			url: "",
			port: 0,
			address: "",
			display_address: "",
			transport: is_undefined(default_transport) ? default_client_transport() : default_transport,
			placeholder: false,
			message: ""
		};

		var target = string_trim(string(address)); /* Address text without surrounding whitespace */

		/* An empty trimmed address cannot identify a server. Return the failure result
		with a message before looking for a scheme or port */
		if (target == "")
		{
			result.message = "Missing server address.";
			return result;
		}

		var lower_target = string_lower(target); /* Case-normalized text for scheme detection */
		var has_ws_scheme = text_starts_with(lower_target, "ws://"); /* Whether the input explicitly selects plain WebSocket */
		var has_wss_scheme = text_starts_with(lower_target, "wss://"); /* Whether the input explicitly selects secure WebSocket */

		/* An explicit ws or wss prefix selects WebSocket even when the caller default
		was TCP. Secure and insecure schemes determine the default port below */
		if (has_ws_scheme || has_wss_scheme)
		{
			result.transport = TRANSPORT_WS;

			/* Secure wss has a six-character prefix and uses the public secure port.
			Plain ws has a five-character prefix and uses the local WebSocket port.
			rest removes that prefix, slash_pos locates the path, host_port initially keeps
			the full remainder, and path defaults to the server root */
			var scheme_length = has_wss_scheme ? 6 : 5;
			var scheme = has_wss_scheme ? "wss://" : "ws://";
			var default_ws_port = has_wss_scheme ? websocket_public_port : websocket_port;
			var rest = string_copy(target, scheme_length + 1, string_length(target) - scheme_length);
			var slash_pos = string_pos("/", rest);
			var host_port = rest;
			var path = "/";

			/* A slash separates the host and optional port from the URL path. Preserve
			that path for the WebSocket route. Without a slash, keep the root path */
			if (slash_pos > 0)
			{
				host_port = string_copy(rest, 1, slash_pos - 1);
				path = string_copy(rest, slash_pos, string_length(rest) - slash_pos + 1);
			}

			/* A scheme with no host cannot be connected. Return the descriptive failure
			before trying to split its port */
			if (host_port == "")
			{
				result.message = "Missing WebSocket host.";
				return result;
			}

			/* Start with the full host text and scheme-selected port. colon_pos identifies
			a possible explicit port. A missing colon keeps those defaults */
			var host = host_port;
			var ws_port = default_ws_port;
			var colon_pos = find_last_colon(host_port);

			/* Treat the final colon as a port separator only for an unbracketed host.
			Bracketed hosts keep their text intact rather than splitting an IPv6 address */
			if (colon_pos > 0
			&& string_pos("[", host_port) <= 0)
			{
				/* ws_port_text holds the trimmed explicit port suffix. The host is trimmed
				separately so surrounding whitespace does not become part of the connection URL */
				var ws_port_text = string_trim(string_copy(host_port, colon_pos + 1, string_length(host_port) - colon_pos));
				host = string_trim(string_copy(host_port, 1, colon_pos - 1));

				/* Check each one-based port character before numeric conversion. Any nondigit
				returns a parsing error, while reaching the end allows conversion */
				for (var port_index = 1; port_index <= string_length(ws_port_text); port_index++)
				{
					/* Ports accept decimal digits only. Reject punctuation or letters rather than
					passing malformed input to real */
					if (string_pos(string_char_at(ws_port_text, port_index), "0123456789") <= 0)
					{
						result.message = "WebSocket port must be a number.";
						return result;
					}
				}

				/* A colon with no following digits is an incomplete explicit port.
				Report it instead of silently using the scheme default */
				if (ws_port_text == "")
				{
					result.message = "Missing WebSocket port.";
					return result;
				}
				ws_port = real(ws_port_text);
			}

			/* Splitting an explicit port must leave a host. If it does not, return the
			missing-host error instead of constructing an unusable WebSocket URL */
			if (host == "")
			{
				result.message = "Missing WebSocket host.";
				return result;
			}

			/* Only ports one through 65,535 identify a network destination.
			Reject values outside that range before marking the address usable */
			if (ws_port < 1 || ws_port > 65535)
			{
				result.message = "WebSocket port must be between 1 and 65535.";
				return result;
			}

			result.ok = true;
			result.url = scheme + host + path;
			result.port = ws_port;

			/* Omit the explicit port from the display address when it matches the scheme
			default. Include nondefault ports so copying this address preserves the destination */
			result.address = scheme + host + (ws_port == default_ws_port ? "" : ":" + string(ws_port)) + path;
			result.display_address = result.address;
			result.placeholder = is_public_wss_placeholder(result.address);
			return result;
		}

		/* The caller port replaces the native default when supplied. For a WebSocket
		address without a scheme or caller port, the next branch chooses the public port */
		var fallback_port = is_undefined(default_port) ? port : default_port;

		/* An implicit browser route with no supplied port uses the public WebSocket
		port rather than the native TCP port. Explicit caller ports remain unchanged */
		if (result.transport == TRANSPORT_WS && is_undefined(default_port))
		{
			fallback_port = websocket_public_port;
		}

		/* separator is the final colon position, or zero when there is no explicit port.
		host_text initially contains the whole address and parsed_port begins at the
		fallback, allowing a host-only address to use its transport default */
		var separator = find_last_colon(target);
		var host_text = target;
		var parsed_port = fallback_port;

		/* A host:port suffix overrides the fallback. Without a colon, preserve the
		whole target as the host and keep the default port */
		if (separator > 0)
		{
			host_text = string_trim(string_copy(target, 1, separator - 1));

			/* port_text contains only the explicit decimal port suffix after the host.
			Validation checks it before converting it into parsed_port */
			var port_text = string_trim(string_copy(target, separator + 1, string_length(target) - separator));

			/* An explicit separator must be followed by a port. Return an error instead
			of treating incomplete host: input as a valid host-only address */
			if (port_text == "")
			{
				result.message = "Missing port.";
				return result;
			}

			/* Read each one-based port character until the suffix ends. The first nondigit
			stops parsing with an error, so real receives decimal text only */
			for (var i = 1; i <= string_length(port_text); i++)
			{
				/* Reject nondecimal port characters before conversion so the connection target
				cannot depend on real interpreting an invalid suffix */
				if (string_pos(string_char_at(port_text, i), "0123456789") <= 0)
				{
					result.message = "Port must be a number.";
					return result;
				}
			}

			parsed_port = real(port_text);
		}

		/* A native or implicit browser address still requires a host.
		Return the failure result before marking the parsed target usable */
		if (host_text == "")
		{
			result.message = "Missing IP address or host.";
			return result;
		}

		/* Reject ports outside the valid destination range. Keeping the result in its
		failure state prevents the caller from opening this target */
		if (parsed_port < 1 || parsed_port > 65535)
		{
			result.message = "Port must be between 1 and 65535.";
			return result;
		}

		result.ok = true;
		result.port = parsed_port;

		/* For an implicit WebSocket target, build a scheme-bearing root URL that the
		browser connection accepts. The TCP alternative keeps a plain host */
		if (result.transport == TRANSPORT_WS)
		{
			/* The configured public port selects secure wss for 443 and plain ws otherwise.
			This branch uses that configured port to infer the scheme for a scheme-less address */
			var browser_scheme = websocket_public_port == 443 ? "wss://" : "ws://";
			result.url = browser_scheme + host_text + "/";
			result.address = browser_scheme + host_text + ":" + string(parsed_port) + "/";
		}

		/* Native targets keep a plain host for TCP connection and host:port for UI.
		They do not require the browser URL scheme or root path */
		else
		{
			result.url = host_text;
			result.address = host_text + ":" + string(parsed_port);
		}

		result.display_address = result.address;
		result.placeholder = is_public_wss_placeholder(result.address);
		return result;
	}

	/// @description Select a GameMaker socket type from transport and optional URL
	/// @param {Real} transport TRANSPORT value
	/// @param {String} address URL for secure WebSocket detection, defaulting to empty for plain ws
	/// @returns {Real} TCP, UDP, ws, or wss socket constant
	socket_type_for_transport = function(transport, address = "")
	{
		/* WebSocket transport needs a ws or wss socket type. Other transports fall
		through to UDP or the native TCP default */
		if (transport == TRANSPORT_WS)
		{
			/* Normalize only for scheme detection. The original address remains available
			to the caller, while a wss prefix selects the secure WebSocket socket type */
			var lower_address = string_lower(string(address));

			/* A secure WebSocket URL requires the wss socket type. Other WebSocket addresses
			fall through to the plain ws type */
			if (text_starts_with(lower_address, "wss://"))
			{
				return network_socket_wss;
			}

			return network_socket_ws;
		}

		/* Use the datagram socket type for UDP. Remaining values use TCP, preserving
		the native transport default */
		if (transport == TRANSPORT_UDP)
		{
			return network_socket_udp;
		}

		return network_socket_tcp;
	}

	/// @description Create a transport-specific listener
	/// @param {Real} transport TRANSPORT value
	/// @param {Real} server_port Local listen port
	/// @param {Real} max_client Socket capacity
	/// @returns {Real} Caller-owned listener handle, or a negative creation result
	create_server = function(transport, server_port, max_client)
	{
		/* WebSocket listeners use raw packet bodies because WebSocket owns framing.
		Other listeners use the GameMaker-framed creation API */
		if (transport == TRANSPORT_WS)
		{
			return network_create_server_raw(socket_type_for_transport(transport), server_port, max_client);
		}

		return network_create_server(socket_type_for_transport(transport), server_port, max_client);
	}

	/// @description Start the transport-specific connection on an existing socket
	/// @param {Real} socket Caller-owned socket handle
	/// @param {String} connect_url Host or WebSocket URL
	/// @param {Real} connect_port Destination port
	/// @param {Real} transport TRANSPORT value
	/// @returns {Real} Connection result. TCP and WebSocket complete asynchronously
	connect = function(socket, connect_url, connect_port, transport)
	{
		/* WebSocket connects through the raw asynchronous API. The later paths keep
		UDP connection semantics and asynchronous native TCP connection */
		if (transport == TRANSPORT_WS)
		{
			return network_connect_raw_async(socket, connect_url, connect_port);
		}

		/* UDP uses the datagram connection API. Other non-WebSocket connections use
		asynchronous TCP so the controller can wait without blocking */
		if (transport == TRANSPORT_UDP)
		{
			return network_connect(socket, connect_url, connect_port);
		}

		return network_connect_async(socket, connect_url, connect_port);
	}

	/// @description Add or replace a socket transport in the parallel registry
	/// @param {Real} socket Numeric socket handle
	/// @param {Real} transport TRANSPORT value to associate
	/// @returns {Bool} Whether registration accepted the handle
	register_socket_transport = function(socket, transport)
	{
		/* Negative creation results and nonnumeric values are not usable socket handles.
		Reject them so the transport registry contains only valid connection identities */
		if (!is_real(socket) || socket < 0)
		{
			return false;
		}

		/* Search registry indexes from zero until this socket is found or the array
		ends. Existing sockets get updated, while absent sockets are appended */
		for (var i = 0; i < array_length(tracked_sockets); i++)
		{
			/* Replace the matching socket transport in place to avoid duplicate mappings */
			if (tracked_sockets[i] == socket)
			{
				tracked_transports[i] = transport;
				return true;
			}
		}

		/* Append at the current registry length so the new socket and its transport
		occupy the same zero-based index in both parallel arrays */
		var index = array_length(tracked_sockets);
		tracked_sockets[index] = socket;
		tracked_transports[index] = transport;
		return true;
	}

	/// @description Remove registration without destroying the socket
	/// @param {Real} socket Handle to unregister
	/// @returns {Bool} Whether a matching entry was removed
	unregister_socket_transport = function(socket)
	{
		/* Find this actual handle in the zero-based registry. A match removes its
		socket/transport pair, while no match leaves registration unchanged */
		for (var i = 0; i < array_length(tracked_sockets); i++)
		{
			/* Remove the transport at the matching socket index as well, keeping the
			registry arrays aligned */
			if (tracked_sockets[i] == socket)
			{
				/* Starting at the removed index, move each later pair left until the old last
				pair is copied. Resizing then drops the duplicated trailing entry */
				for (var j = i; j < array_length(tracked_sockets) - 1; j++)
				{
					tracked_sockets[j] = tracked_sockets[j + 1];
					tracked_transports[j] = tracked_transports[j + 1];
				}

				array_resize(tracked_sockets, array_length(tracked_sockets) - 1);
				array_resize(tracked_transports, array_length(tracked_transports) - 1);
				return true;
			}
		}

		return false;
	}

	/// @description Resolve a registered socket transport
	/// @param {Real} socket Actual socket handle
	/// @param {Real} fallback Transport for an unregistered handle, defaulting to TCP
	/// @returns {Real} Registered transport or fallback
	get_socket_transport = function(socket, fallback = TRANSPORT_TCP)
	{
		/* Scan zero-based registry entries for this handle. Finishing without a match
		returns the supplied transport fallback */
		for (var i = 0; i < array_length(tracked_sockets); i++)
		{
			/* This matching handle shares its index with the registered transport.
			Return that route without inspecting unrelated sockets */
			if (tracked_sockets[i] == socket)
			{
				return tracked_transports[i];
			}
		}

		return fallback;
	}
	#endregion /* Transport Helpers END */

	#region /* Packet Names */
	/// @description Name a packet ID without reading its body
	/// @param {Real} message_type N_ packet type
	/// @returns {String} Protocol name, or UNKNOWN_PACKET
	message_type_to_string = function(message_type)
	{
		/* Known packet IDs get their protocol names for logs. The default reports
		UNKNOWN_PACKET so unsupported types remain visible */
		switch (message_type)
		{
			case N_ID: return "N_ID";
			case N_MESSAGE: return "N_MESSAGE";
			case N_NEW_PLAYER: return "N_NEW_PLAYER";
			case N_PLAYER_LIST: return "N_PLAYER_LIST";
			case N_REMOVE_PLAYER: return "N_REMOVE_PLAYER";
			case N_KEY_PRESS: return "N_KEY_PRESS";
			case N_KEY_RELEASE: return "N_KEY_RELEASE";
			case N_PLAYER_POSITION: return "N_PLAYER_POSITION";
			case N_SERVER_FULL: return "N_SERVER_FULL";
			case N_SERVER_STATUS: return "N_SERVER_STATUS";
			case N_SERVER_STATUS_REQUEST: return "N_SERVER_STATUS_REQUEST";
			case N_JOIN_GAME: return "N_JOIN_GAME";
			case N_LEAVE_GAME: return "N_LEAVE_GAME";
			case N_PLAYER_POSITION_BATCH: return "N_PLAYER_POSITION_BATCH";
			case N_HEARTBEAT_PING: return "N_HEARTBEAT_PING";
			case N_HEARTBEAT_PONG: return "N_HEARTBEAT_PONG";
			case N_TYPING_STATE: return "N_TYPING_STATE";
			case N_AFK_ACTIVITY: return "N_AFK_ACTIVITY";
			case N_AFK_STATE: return "N_AFK_STATE";
			case N_SERVER_KICK: return "N_SERVER_KICK";
			case N_DRAW_COMMAND: return "N_DRAW_COMMAND";
			case N_DRAW_HISTORY: return "N_DRAW_HISTORY";
			case N_PLAYER_STATE_BATCH: return "N_PLAYER_STATE_BATCH";
			case N_DRAW_IMAGE: return "N_DRAW_IMAGE";
			case N_COLLISION_OBJECT_STATE: return "N_COLLISION_OBJECT_STATE";
			case N_PLAYER_CHARACTER: return "N_PLAYER_CHARACTER";
			case N_PLAYER_CHARACTER_CHUNK: return "N_PLAYER_CHARACTER_CHUNK";
			case N_HOST_STATUS: return "N_HOST_STATUS";
			case N_SERVER_LIFECYCLE: return "N_SERVER_LIFECYCLE";
			case N_LATENCY_PROBE: return "N_LATENCY_PROBE";
			case N_LATENCY_REPLY: return "N_LATENCY_REPLY";
			case N_CLIENT_PLAYER_STATE: return "N_CLIENT_PLAYER_STATE";
			case N_CLIENT_PLAYER_STATE_ACK: return "N_CLIENT_PLAYER_STATE_ACK";
			case N_LAYER_VOTE: return "N_LAYER_VOTE";
			case N_ADMIN_AUTH: return "N_ADMIN_AUTH";
			case N_ADMIN_STATUS: return "N_ADMIN_STATUS";
			case N_ADMIN_COMMAND: return "N_ADMIN_COMMAND";
			case N_ADMIN_RESULT: return "N_ADMIN_RESULT";
			case N_ADMIN_LOGS: return "N_ADMIN_LOGS";
			case N_SERVER_PLAYER_LIMIT: return "N_SERVER_PLAYER_LIMIT";
			case N_JOIN_GAME_VERSIONED: return "N_JOIN_GAME_VERSIONED";
			case N_WALL_SETTINGS: return "N_WALL_SETTINGS";
			case N_WALL_EDIT: return "N_WALL_EDIT";
			case N_WALL_SNAPSHOT: return "N_WALL_SNAPSHOT";
			case N_WALL_PLAYER_CORRECTION: return "N_WALL_PLAYER_CORRECTION";
			case N_PLAYER_PET: return "N_PLAYER_PET";
			default: return "UNKNOWN_PACKET";
		}
	}
	#endregion /* Packet Names END */

	#region /* Packet Logging and Buffer Operations */
	/// @description Write diagnostic text only in verbose mode
	/// @param {Any} message Text converted to a string
	log_verbose = function(message)
	{
		/* Verbose mode emits these diagnostic messages. Normal mode skips the log
		without changing packet processing */
		if (verbose)
		{
			debug_log("[NET] " + string(message));
		}
	}

	/// @description Suppress routine traffic in normal packet logs
	/// @param {Real} message_type N_ packet type
	/// @returns {Bool} Whether logging should include this packet
	should_log_packet = function(message_type)
	{
		/* Verbose logging includes all packet types. Normal logging instead consults
		the suppression list below to keep routine updates quiet */
		if (verbose)
		{
			return true;
		}

		/* The listed high-frequency state, drawing, heartbeat and admin packets are
		suppressed in normal logs. Other IDs fall through to true, keeping connection
		and chat traffic visible */
		switch (message_type)
		{
			case N_KEY_PRESS:
			case N_KEY_RELEASE:
			case N_PLAYER_POSITION:
			case N_PLAYER_POSITION_BATCH:
			case N_HEARTBEAT_PING:
			case N_HEARTBEAT_PONG:
			case N_TYPING_STATE:
			case N_AFK_ACTIVITY:
			case N_AFK_STATE:
			case N_DRAW_COMMAND:
			case N_DRAW_HISTORY:
			case N_PLAYER_STATE_BATCH:
			case N_DRAW_IMAGE:
			case N_COLLISION_OBJECT_STATE:
			case N_PLAYER_CHARACTER:
			case N_PLAYER_CHARACTER_CHUNK:
			case N_SERVER_LIFECYCLE:
			case N_LATENCY_PROBE:
			case N_LATENCY_REPLY:
			case N_CLIENT_PLAYER_STATE:
			case N_LAYER_VOTE:
			case N_ADMIN_AUTH:
			case N_ADMIN_STATUS:
			case N_ADMIN_COMMAND:
			case N_ADMIN_RESULT:
			case N_ADMIN_LOGS:
			case N_SERVER_PLAYER_LIMIT:
			case N_WALL_EDIT:
			case N_WALL_SNAPSHOT:
			case N_WALL_PLAYER_CORRECTION:
				return false;
	}

		return true;
	}

	/// @description Log changed errors immediately and duplicates at most once a second
	/// @param {Any} message Failure text compared with the preceding logged failure
	log_send_error = function(message)
	{
		var error_text = string(message); /* Printable send failure compared against the last logged failure */

		/* A different failure is logged immediately. Repeated text waits until its
		current_time deadline, preventing the same send error flooding logs each Step */
		if (error_text != last_send_error
		|| current_time >= next_send_error_time)
		{
			debug_error(error_text);
			last_send_error = error_text;
			next_send_error_time = current_time + 1000;
		}
	}

	/// @description Empty the failed slot/socket lists before a broadcast
	clear_failed_sends = function()
	{
		failed_send_slots = [];
		failed_send_sockets = [];
	}

	/// @description Record a failed broadcast recipient for server cleanup
	/// @param {Real} slot Logical zero-based player slot
	/// @param {Real} socket Actual socket handle at that slot
	record_failed_send = function(slot, socket)
	{
		var failed_index = array_length(failed_send_slots); /* Next index shared by the failed slot and socket lists */
		failed_send_slots[failed_index] = slot;
		failed_send_sockets[failed_index] = socket;
	}

	/// @description Borrow a packet buffer and consume type:u8 followed by logical player slot:s16
	/// @param {Id.Buffer} _buffer Borrowed async packet buffer. Do not delete it
	/// @param {Real} _size Received byte count, defaulting to undefined for buffer capacity. A numeric count is bounded by capacity
	/// @returns {Bool} Whether a complete three-byte header was read
	prime_reader = function(_buffer, _size = undefined)
	{
		/* An absent or deleted async buffer cannot supply a packet header.
		Report the invalid handle and leave the reader unprimed for this call */
		if (is_undefined(_buffer) || !buffer_exists(_buffer))
		{
			debug_error("prime_reader received invalid buffer: " + string(_buffer));
			return false;
		}

		reader_buffer = _buffer;
		reader_size = buffer_get_size(_buffer);

		/* When the async event supplies a byte count, bound it to a whole nonnegative
		length no larger than buffer capacity. Otherwise retain the capacity fallback */
		if (is_real(_size)) reader_size = min(reader_size, max(0, floor(_size)));

		/* A packet needs one type byte and two signed slot bytes. Shorter data is
		rejected before seeking or reading the header */
		if (reader_size < 3) return false;
		buffer_seek(reader_buffer, buffer_seek_start, 0);
		header.type = buffer_read(reader_buffer, buffer_u8);
		header.socketID = buffer_read(reader_buffer, buffer_s16);
		return true;
	}

	/// @description Rewind the shared writer and begin a packet. Following write calls define its body order
	/// @param {Real} message_type N_ packet type encoded as u8
	/// @param {Real} socket_id Logical player slot encoded as s16. undefined becomes noone
	start = function(message_type, socket_id)
	{
		buffer_seek(buffer, buffer_seek_start, 0);
		buffer_write(buffer, buffer_u8, message_type);

		/* The packet header carries a logical player slot, starting from the caller
		value. An omitted value is normalized to noone to represent no player sender */
		var sender_id = socket_id;

		/* Packets without an identified player use noone in the signed header field.
		Defined caller values keep their identity */
		if (is_undefined(sender_id))
		{
			sender_id = noone;
		}

		buffer_write(buffer, buffer_s16, sender_id);
	}

	/// @description Append one field to the shared packet writer
	/// @param {Real} type GameMaker buffer type in wire order
	/// @param {Any} data Field value matching the receiver buffer type
	write = function(type, data)
	{
		buffer_write(buffer, type, data);
	}

	/// @description Check required field sizes and string terminators without consuming reader state
	/// @param {Array} types Ordered GameMaker buffer types expected from the current reader cursor
	/// @returns {Bool} Whether every required field fits reader_size
	can_read_fields = function(types)
	{
		/* Without a live borrowed reader buffer there are no fields to validate.
		Return false before inspecting its cursor */
		if (!buffer_exists(reader_buffer)) return false;

		/* position is a local byte cursor copied from the reader. Preflight advances
		this copy only, leaving actual consumption to read */
		var position = buffer_tell(reader_buffer);

		/* Walk each expected field in wire order using its zero-based array index.
		All fields must fit the received byte count before the handler can consume them */
		for (var field_index = 0; field_index < array_length(types); field_index++)
		{
			/* The current expected buffer type determines whether preflight searches for
			a string terminator or advances by a fixed byte size */
			var field_type = types[field_index];

			/* Strings end at a zero byte rather than a fixed field width.
			Search within received bytes, while other types use their known byte sizes */
			if (field_type == buffer_string)
			{
				/* Advance while received bytes remain and the next byte is not a string
				terminator. The size check protects the peek from reading past the packet */
				while (position < reader_size && buffer_peek(reader_buffer, position, buffer_u8) != 0)
				{
					position++;
				}

				/* Reaching the received-byte boundary without a zero terminator means the
				string is incomplete. Reject it instead of letting the handler read stale capacity */
				if (position >= reader_size) return false;
				position++;
			}

			/* Fixed-width fields advance by their byte size. They use bounds validation
			rather than the string terminator search */
			else
			{
				position += buffer_sizeof(field_type);

				/* A fixed-size field crossing the received-byte boundary is incomplete.
				Reject the packet before its handler consumes that field */
				if (position > reader_size) return false;
			}
		}
		return true;
	}

	/// @description Consume one typed field from the primed shared packet reader
	/// @param {Real} type GameMaker buffer type in wire order
	/// @returns {Any} Decoded field, or undefined when the reader buffer is invalid
	read = function(type)
	{
		/* A missing or deleted reader cannot decode a field. Log the misuse and
		return undefined instead of reading from an invalid handle */
		if (is_undefined(reader_buffer) || !buffer_exists(reader_buffer))
		{
			debug_error("Network.read called without a valid reader buffer.");
			return undefined;
		}

		log_verbose("Read cursor=" + string(buffer_tell(reader_buffer)) + ", buffer_type=" + string(type));
		return buffer_read(reader_buffer, type);
	}

	/// @description Send binary WebSocket data or a framed GameMaker packet
	/// @param {Real} socket Destination GameMaker socket ID
	/// @param {Bool} log_errors Whether failures are logged, defaulting to true
	/// @param {Real} transport_override TRANSPORT value, defaulting to undefined for socket registration
	/// @returns {Real} Transport byte-count result, or -1 for invalid, failed, or partial sends
	send_packet = function(socket, log_errors = true, transport_override = undefined)
	{
		/* A nonnumeric or negative destination cannot send a packet. Return failure
		before accessing the transport, with optional logging controlled by log_errors */
		if (!is_real(socket)
		|| socket < 0)
		{
			/* Log this invalid destination when the caller requests it. Silent broadcasts
			still get a failure result and can report their player-slot context */
			if (log_errors)
			{
				log_send_error("Network.send received invalid socket: " + string(socket));
			}
			return -1;
		}

		/* The writer cursor gives completed body bytes, independent of spare buffer
		capacity. Sending transmits this length only */
		var packet_size = buffer_tell(buffer);

		/* The writer has no bytes before its current cursor, so there is no packet to
		send. Return failure rather than issuing an empty transport operation */
		if (packet_size <= 0)
		{
			/* Report empty-writer misuse when logs are enabled. Silent callers still
			receive failure and cannot treat an empty send as successful */
			if (log_errors)
			{
				log_send_error("Network.send attempted to send empty packet.");
			}
			return -1;
		}

		/* An explicit transport overrides the registry. Without one, use the registered
		socket transport and fall back to TCP for unregistered handles */
		var transport = is_undefined(transport_override) ? get_socket_transport(socket, TRANSPORT_TCP) : transport_override;
		var sent; /* Transport byte-count result, assigned by the selected send branch */

		/* WebSocket sends binary body bytes directly. The alternative uses GameMaker
		packet framing for native sockets */
		if (transport == TRANSPORT_WS)
		{
			sent = network_send_raw(socket, buffer, packet_size, network_send_binary);
		}

		/* Other transports send a GameMaker-framed packet. The completeness check
		below includes its header bytes */
		else
		{
			sent = network_send_packet(socket, buffer, packet_size);
		}

		/* expected_size counts the complete successful send result in bytes.
		WebSocket sends return body bytes only, while framed GameMaker sends also count
		the 12-byte header. Comparing like sizes identifies partial sends */
		var expected_size = packet_size + (transport == TRANSPORT_WS ? 0 : 12);

		/* A nonnegative send result still fails if it reports fewer bytes than the
		complete packet. Return -1 so callers treat a partial send as a connection failure */
		if (sent >= 0 && sent < expected_size)
		{
			/* Log the partial-send counts when enabled. The return value remains failure
			even when this diagnostic is suppressed */
			if (log_errors)
			{
				log_send_error("Incomplete network send over " + transport_to_string(transport) + ". socket=" + string(socket)
					+ ", expected=" + string(expected_size) + ", sent=" + string(sent));
			}
			return -1;
		}

		/* A negative transport result is a send failure. Log it when requested and
		return the same failure to the caller. Successful results pass through unchanged */
		if (sent < 0)
		{
			/* Log this transport failure when enabled. Silent callers still receive the
			negative result and can close the failed connection */
			if (log_errors)
			{
				log_send_error("Network send failed over " + transport_to_string(transport) + ". socket=" + string(socket) + ", size=" + string(packet_size) + ", result=" + string(sent));
			}
		}

		return sent;
	}

	/// @description Send the shared packet through the client session socket and transport
	/// @returns {Real} Transport send result, or -1 for an invalid client socket
	send_server = function()
	{
		/* Borrow the current client session socket for this send. The client owns and
		releases it, and a failed or absent handle cannot deliver the writer contents */
		var socket = Client.socket;

		/* The client must hold a numeric live socket before sending to its server.
		Otherwise report failure and avoid a transport call */
		if (!is_real(socket) || socket < 0)
		{
			debug_error("Network.send_server received invalid socket: " + string(socket));
			return -1;
		}

		/* Use the client session transport when that field exists. Older client shapes
		fall back to socket registration, then TCP, preserving compatible send routing */
		var transport = variable_struct_exists(Client, "transport") ? Client.transport : get_socket_transport(socket, TRANSPORT_TCP);
		return send_packet(socket, true, transport);
	}

	/// @description Send the shared packet through send_packet validation
	/// @param {Real} socket Destination socket handle
	/// @param {Bool} log_errors Whether failures are logged, defaulting to true
	/// @param {Real} transport_override TRANSPORT value, defaulting to undefined for socket registration
	/// @returns {Real} Byte-count result, or -1 for invalid, failed, or partial sends
	send = function(socket, log_errors = true, transport_override = undefined)
	{
		return send_packet(socket, log_errors, transport_override);
	}

	/// @description Broadcast the shared packet and collect failed socket slots for server cleanup
	/// @param {Array} sockets Socket IDs indexed by logical player slot. noone entries are skipped
	/// @param {Real} exception Logical slot to exclude, defaulting to noone for no exclusion. This is not a socket ID
	/// @returns {Real} Successful recipient count, or -1 if any eligible send fails
	send_all = function(sockets, exception = noone)
	{
		clear_failed_sends();

		/* A broadcast requires a slot-indexed socket array. Return failure for another
		value rather than iterating invalid storage */
		if (!is_array(sockets))
		{
			debug_error("Network.send_all received invalid sockets array: " + string(sockets));
			return -1;
		}

		/* The writer cursor gives body bytes available to broadcast. An empty writer
		cannot deliver a protocol packet to any recipient */
		var packet_size = buffer_tell(buffer);

		/* Reject an empty broadcast before visiting player sockets. This packet
		construction failure does not identify an individual failed player */
		if (packet_size <= 0)
		{
			debug_error("Network.send_all attempted to send empty packet to all.");
			return -1;
		}

		/* send_count starts with no successful recipients and failed_count with no
		failures. Their final values distinguish a clean broadcast from partial failure */
		var send_count = 0;
		var failed_count = 0;

		/* Visit every zero-based player slot, including empty entries. Each occupied
		eligible slot gets one send attempt, and the loop ends after the final array entry */
		for(var i = 0; i < array_length(sockets); i++)
		{
			/* target_socket is the actual socket handle stored at this logical player slot.
			Keep both identities available so failed sends can be matched during cleanup */
			var target_socket = sockets[i];

			/* Skip the excluded logical slot and unoccupied noone entries. Neither counts
			as a failed recipient because neither should receive this broadcast */
			if ((i == exception)
			|| (target_socket == noone))
			{
				continue;
			}

			/* An occupied slot with an invalid handle counts as a failed recipient.
			Record its slot/socket pair and continue so other players still receive the packet */
			if (!is_real(target_socket)
			|| target_socket < 0)
			{
				failed_count += 1;
				record_failed_send(i, target_socket);
				log_send_error("Network.send_all found invalid socket in slot " + string(i) + ": " + string(target_socket));
				continue;
			}

			/* send_result is the transport result for this recipient. Disable per-send logs
			here so the broadcast can report failure together with its logical player slot */
			var send_result = send(target_socket, false);

			/* Record failed or partial sends for later server cleanup, then move to the
			next player instead of cancelling delivery to every remaining recipient */
			if (send_result < 0)
			{
				failed_count += 1;
				record_failed_send(i, target_socket);
				log_send_error("Network.send_all send failed for slot " + string(i) + " on socket " + string(target_socket));
				continue;
			}

			send_count += 1;
		}

		/* Any failed eligible recipient makes the broadcast result -1, even if other
		sends succeeded. With no failures, return the successful recipient count */
		if (failed_count > 0)
		{
			return -1;
		}

		return send_count;
	}
	#endregion /* Packet Logging and Buffer Operations END */

}

/// @description Get the process-wide network service. Creates it on first use
/// @returns {Struct} Shared scr_network instance
function scr_get_network()
{
	/* The static service is created on first access and reused for the process.
	It owns the writer buffer and registry, while reader buffers remain borrowed */
	static n = new scr_network();
	return n;
}

/// @description Create the selected transport listener through the shared network service
/// @param {Real} transport TRANSPORT_TCP, TRANSPORT_WS, or TRANSPORT_UDP
/// @param {Real} port Local listen port
/// @param {Real} max_clients Socket capacity
/// @returns {Real} GameMaker listener ID, or a negative creation result
function scr_network_create_server(transport, port, max_clients)
{
	return scr_get_network().create_server(transport, port, max_clients);
}

/// @description Connect a socket using the selected transport
/// @param {Real} socket GameMaker socket ID
/// @param {String} url Host or WebSocket URL expected by the transport
/// @param {Real} port Remote port
/// @param {Real} transport TRANSPORT_TCP, TRANSPORT_WS, or TRANSPORT_UDP
/// @returns {Real} GameMaker connection result. TCP and WebSocket completion arrives asynchronously
function scr_network_connect(socket, url, port, transport)
{
	return scr_get_network().connect(socket, url, port, transport);
}

/// @description Send the packet currently written in the shared network buffer
/// @param {Real} socket Destination socket ID
/// @param {Bool} log_errors Whether failed or partial sends are logged, defaulting to true
/// @param {Real} transport_override TRANSPORT value, defaulting to undefined for the registered socket transport
/// @returns {Real} Transport send result, or -1 for an invalid, failed, or partial send
function scr_network_send(socket, log_errors = true, transport_override = undefined)
{
	return scr_get_network().send(socket, log_errors, transport_override);
}

/// @description Prime the shared reader and consume its three-byte packet header before dispatch
/// @param {Id.Buffer} network_data Borrowed asynchronous packet buffer. Do not delete it
/// @param {Real} network_size Received byte count, defaulting to undefined for buffer capacity
/// @returns {Bool} Whether the buffer contains the message-type byte and signed logical-slot ID
function scr_network_handle_packet(network_data, network_size = undefined)
{
	/* Acquire the shared network service used to prime this async packet reader.
	The service owns header state, but the async event still owns network_data */
	var net = scr_get_network();

	/* A missing service or absent reader method cannot dispatch the packet.
	Return false before looking up or invoking the method */
	if (!is_struct(net)
	|| !variable_struct_exists(net, "prime_reader"))
	{
		debug_error("scr_network_handle_packet could not find Network.prime_reader.");
		return false;
	}

	/* Capture the service reader method after its field has been checked.
	The method keeps its bound network state when invoked below */
	var prime_reader = net.prime_reader;

	/* A present field must also be a bound method. Reject another value rather
	than calling invalid reader state */
	if (!is_method(prime_reader))
	{
		debug_error("scr_network_handle_packet found an invalid Network.prime_reader method.");
		return false;
	}

	return prime_reader(network_data, network_size);
}

/// @description Validate four decimal IPv4 octets
/// @param {String} host Address to check
/// @returns {Bool} Whether every octet contains digits and is between 0 and 255
function is_ipv4_address(host)
{
	/* Split the proposed IPv4 host into its decimal octets. The resulting array
	must contain four entries before any per-octet validation */
	var parts = string_split(host, ".");

	/* IPv4 uses four octets. A different number of dot-separated parts cannot be
	an IPv4 A-record address, so reject it before converting components */
	if (array_length(parts) != 4)
	{
		return false;
	}

	/* Inspect each zero-based octet index from zero to three. Every octet must
	pass before the address is accepted */
	for (var i = 0; i < 4; i++)
	{
		/* part is the current decimal octet text, kept as text until digit and length
		checks establish that numeric conversion is meaningful */
		var part = parts[i];

		/* An octet needs one to three decimal digits. Empty components and longer
		text cannot represent the permitted zero-to-255 range */
		if (string_length(part) == 0 || string_length(part) > 3)
		{
			return false;
		}

		/* Inspect every one-based character in the octet. A nondigit rejects the whole
		host, while reaching the end allows conversion */
		for (var j = 1; j <= string_length(part); j++)
		{
			/* Only decimal digits belong in an IPv4 octet. Reject signs, spaces and other
			characters before converting the octet */
			if (string_pos(string_char_at(part, j), "0123456789") <= 0)
			{
				return false;
			}
		}

		/* Convert the validated decimal octet into num so its permitted numeric
		range can be checked without accepting arbitrary hostname text */
		var num = real(part);

		/* Each IPv4 octet is one byte, so values outside zero through 255 are invalid.
		All four in-range components are required for a true result */
		if (num < 0 || num > 255)
		{
			return false;
		}
	}

	return true;
}

/// @description Read the first valid IPv4 A-record answer from the DNS HTTP response
/// @param {String} json_text JSON response body
/// @returns {String} IPv4 address, or an empty string for a missing or invalid answer
function dns_extract_ip_from_json(json_text)
{
	/* text holds the HTTP body as a string and parsed receives its decoded JSON.
	A parse exception returns no address rather than interrupting DNS fallback */
	var text = string(json_text);
	var parsed; /* Decoded DNS reply, assigned only when JSON parsing succeeds */

	try
	{
		parsed = json_parse(text);
	}
	catch(e)
	{
		return "";
	}

	/* The DNS reply must be an object with named fields. Other JSON values cannot
	supply the expected Answer array */
	if (!is_struct(parsed))
	{
		return "";
	}

	/* A reply without Answer contains no usable A-record result. Return the empty
	fallback so the connection flow can handle unresolved DNS */
	if (!variable_struct_exists(parsed, "Answer"))
	{
		return "";
	}

	/* answers is the DNS response record list. Only array entries are scanned,
	and the first valid IPv4 A record becomes the resolved address */
	var answers = parsed.Answer;

	/* An absent or empty record list contains no address to use.
	Return the unresolved fallback without attempting indexed access */
	if (!is_array(answers) || array_length(answers) == 0)
	{
		return "";
	}

	/* Scan DNS answers in response order with a zero-based record index.
	Return at the first usable A record or finish with no resolved address */
	for (var i = 0; i < array_length(answers); i++)
	{
		/* answer is the current DNS record. Its type and data fields are inspected
		only after confirming that the entry is a struct */
		var answer = answers[i];

		/* Skip malformed nonobject records so a later valid A record can still resolve
		the host */
		if (!is_struct(answer))
		{
			continue;
		}

		/* Both the record type and address data must exist before the entry can be
		recognized. Skip incomplete records and continue searching */
		if (!variable_struct_exists(answer, "type") || !variable_struct_exists(answer, "data"))
		{
			continue;
		}

		/* DNS type one denotes an IPv4 A record. Accept it only when its data also
		passes octet validation, avoiding other records and malformed address text */
		if (answer.type == 1 && is_ipv4_address(string(answer.data)))
		{
			return string(answer.data);
		}
	}

	return "";
}

/// @description Start an asynchronous DNS-over-HTTPS A-record lookup
/// @param {String} domain Hostname to resolve
/// @returns {Real} HTTP request ID matched by obj_network_control Async HTTP
function dns_resolve_domain(domain)
{
	/* The request URL asks the DNS-over-HTTPS endpoint for IPv4 A records of this
	hostname. Its HTTP request ID is matched by the controller Async HTTP event */
	var url = "https://dns.google/resolve?name=" + string(domain) + "&type=A";
	return http_get(url);
}
