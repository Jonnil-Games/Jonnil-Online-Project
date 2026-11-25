/// @description Prepare binary network packets and dispatch each socket event to its owner

#region /* Async Network Payload */
/* network_id is the runtime event handle and network_type selects connect,
disconnect or data processing. These are socket/listener handles, not logical
zero-based player slots */
var network_id = async_load[? "id"];
var network_type = async_load[? "type"];

/* Use the event id as the initial socket handle because runtime event shapes vary.
The explicit socket field replaces it when present */
var network_socket = network_id;

/* An explicit socket field identifies the child/outbound connection separately
from the event id. Prefer it when available and retain the id fallback otherwise */
if (ds_map_exists(async_load, "socket"))
{
	network_socket = async_load[? "socket"];
}

/* Start without packet data. Data events may supply a borrowed ref buffer or
numeric buffer handle, which remains runtime-owned and must not be deleted here */
var network_data = undefined;

/* Copy the packet buffer only when the event supplies it. Nondata events can
legitimately leave network_data undefined */
if (ds_map_exists(async_load, "buffer"))
{
	network_data = async_load[? "buffer"];
}

/* The optional source host begins empty for events without an IP field.
UDP discovery handlers use it as the reply or advertised-address source */
var network_ip = "";

/* An available IP field supplies the source address. Keep empty when absent so
discovery cannot invent a unicast destination */
if (ds_map_exists(async_load, "ip"))
{
	network_ip = async_load[? "ip"];
}

/* The optional source port starts at -1 to indicate no usable destination.
Discovery reply routing replaces it from the event when available */
var network_port = -1;

/* Restore the source port only when supplied. The negative fallback prevents
missing event metadata from being mistaken for a valid reply port */
if (ds_map_exists(async_load, "port"))
{
	network_port = async_load[? "port"];
}

/* The optional server field starts unassigned. It can identify the listener
owning an accepted socket, separate from both event and player identities */
var network_server = noone;

/* An explicit server field helps the hosting service identify listener ownership.
Its absence leaves ownership to the remaining handle checks */
if (ds_map_exists(async_load, "server"))
{
	network_server = async_load[? "server"];
}

/* WebSocket message kind begins unknown. When the runtime exposes this field,
text data can be rejected before binary packet decoding */
var network_message_type = noone;

/* Record a reported WebSocket message kind when present. Other transports or
runtime shapes may leave it unknown without implying a text message */
if (ds_map_exists(async_load, "message_type"))
{
	network_message_type = async_load[? "message_type"];
}
#endregion /* Async Network Payload END */

#region /* Network Service Validation */
/* Borrow the shared network reader/diagnostics service used by both session sides */
var net = scr_get_network();

/* Without the shared network service, packets cannot be decoded or routed safely.
Report the unavailable state and end this asynchronous event */
if (!is_struct(net))
{
	show_debug_message("Network struct is invalid.");
	return;
}
#endregion /* Network Service Validation END */

#region /* LAN Discovery Pre-Dispatch */
/* Offer only data events to LAN discovery before binary preparation. Discovery
uses pipe-delimited text on its own UDP socket, while connect/disconnect events
need no discovery body decoding */
if (network_type == network_type_data)
{
	/* No discovery owner has claimed this data yet. discovery_server_checked tracks
	whether the hosted server was already offered the event, preventing a second
	server call during fallback routing */
	var discovery_handled = false;
	var discovery_server_checked = false;

	/* A live local host owns LAN discovery even while Host & Play displays its client.
	Offer its server handler first. Client-only mode bypasses this hosted path */
	if (is_hosting_server)
	{
		/* Borrow the hosted server that owns its discovery listener, not an accepted
		client socket. Mark this server as checked even when its handler is unavailable */
		var hosted_discovery_server = scr_get_server();
		discovery_server_checked = true;

		/* Call discovery only when the hosted server state and handler are available.
		The handler verifies its UDP ownership before claiming the event */
		if (is_struct(hosted_discovery_server)
		&& variable_struct_exists(hosted_discovery_server, "handle_discovery_async"))
		{
			discovery_handled = hosted_discovery_server.handle_discovery_async(network_id, network_data, network_ip, network_port, network_server);
		}
	}

	/* If hosting did not claim the data and the client view is active, offer it to
	client discovery. Claimed server discovery packets must not be consumed again */
	if (!discovery_handled && is_client)
	{
		/* Borrow the client service whose discovery socket receives LAN announcements */
		var discovery_client = scr_get_client();

		/* An available client discovery handler can test its own socket ownership.
		Missing support leaves this packet unclaimed for remaining routing */
		if (is_struct(discovery_client)
		&& variable_struct_exists(discovery_client, "handle_discovery_async"))
		{
			discovery_handled = discovery_client.handle_discovery_async(network_id, network_data, network_ip, network_port);
		}
	}

	/* Offer unclaimed data to the server only in server view and only if it has not
	already been checked. A standalone client also has an inactive Server struct,
	but that struct must not consume its client data */
	if (!discovery_handled && !discovery_server_checked && !is_client)
	{
		/* Borrow the dedicated-view server for the remaining discovery ownership check */
		var discovery_server = scr_get_server();

		/* The remaining server discovery route needs a present service and handler.
		Unavailable support leaves the event for binary socket routing */
		if (is_struct(discovery_server)
		&& variable_struct_exists(discovery_server, "handle_discovery_async"))
		{
			discovery_handled = discovery_server.handle_discovery_async(network_id, network_data, network_ip, network_port, network_server);
		}
	}

	/* A discovery owner has consumed the text packet. Return now so the shared binary
	reader does not interpret discovery fields as a gameplay header */
	if (discovery_handled)
	{
		return;
	}
}
#endregion /* LAN Discovery Pre-Dispatch END */

#region /* Async Diagnostics */
/* Create the diagnostics flag only when absent, retaining an existing true value.
False initially allows one verbose dump of the runtime event map shape */
if (!variable_instance_exists(id, "did_log_async_shape"))
{
	did_log_async_shape = false;
}

/* Verbose mode prints the event keys once per controller instance.
Mark the dump complete before iterating so later events do not repeat it */
if (net.verbose && !did_log_async_shape)
{
	did_log_async_shape = true;

	/* key begins at the first async-map member. The map API advances it until no key
	remains, revealing runtime-specific event fields for diagnostics */
	var key = ds_map_find_first(async_load);

	/* Continue while the map provides another key. Each iteration logs its value
	and advances to the next member, ending at the undefined end marker */
	while (!is_undefined(key))
	{
		debug_log("Async key [" + string(key) + "] = " + string(async_load[? key]));
		key = ds_map_find_next(async_load, key);
	}
}

/* Resolve the event code to its diagnostic name without changing socket routing */
var async_name = net.event_type_to_string(network_type);

/* Always log connection/lifecycle events, but log high-frequency data events only
in verbose mode so ordinary play does not flood the diagnostics */
if (network_type != network_type_data || net.verbose)
{
	debug_log(
		"Async event: " + async_name + " (" + string(network_type) + ")" +
		", id=" + string(network_id) +
		", socket=" + string(network_socket) +
		", server=" + string(network_server)
	);
}
#endregion /* Async Diagnostics END */

#region /* Binary Packet Preparation */
/* The reader method starts unavailable until copied from the shared service.
Data preparation separately checks that the captured member is callable */
var prime_reader = undefined;

/* Capture the reader member only when present. Missing reader support is reported
by the data-event validation below */
if (variable_struct_exists(net, "prime_reader"))
{
	prime_reader = net.prime_reader;
}

/* Only packet data needs binary validation and header preparation.
Connection and disconnection events keep their optional buffer unused */
if (network_type == network_type_data)
{
	/* Reject explicitly reported WebSocket text messages because gameplay expects
	binary packets. Unknown kinds still proceed to the binary buffer checks */
	if (network_message_type == network_send_text)
	{
		debug_error("Received WebSocket text data, but this game expects binary packets.");
		return;
	}

	/* A data event without its buffer key cannot contain a decodable packet.
	Report it and return before accessing shared reader state */
	if (!ds_map_exists(async_load, "buffer"))
	{
		show_debug_message("Network data event is missing buffer key.");
		return;
	}

	/* A missing or deleted borrowed buffer cannot supply a packet header.
	Ignore this invalid data event rather than seeking an unavailable resource */
	if (is_undefined(network_data) || !buffer_exists(network_data))
	{
		show_debug_message("Network packet has invalid buffer: " + string(network_data));
		return;
	}

	/* Do not attempt binary preparation through a missing or noncallable reader.
	Report the service problem and leave this packet undispatched */
	if (!is_method(prime_reader))
	{
		show_debug_message("Network prime_reader method is not callable.");
		return;
	}

	/* reader_ok records whether the shared reader consumed a complete type:u8 and
	logical slot:s16 header. Use the received size field when supplied, otherwise
	let preparation fall back to buffer capacity */
	var reader_ok = scr_network_handle_packet(network_data, ds_map_exists(async_load, "size") ? async_load[? "size"] : undefined);

	/* A rejected or short header cannot identify a valid gameplay body.
	Report preparation failure and stop before choosing a socket owner */
	if (!reader_ok)
	{
		show_debug_message("Network prime_reader failed for buffer: " + string(network_data));
		return;
	}

	/* Resolve the prepared message code for optional packet diagnostics */
	var packet_name = net.message_type_to_string(net.header.type);

	/* Log only packet types selected by the network logging policy.
	Routine packet traffic otherwise proceeds without this per-packet message */
	if (net.should_log_packet(net.header.type))
	{
		debug_log(
			"Async data prepared: packet=" + packet_name + " (" + string(net.header.type) + ")" +
			", header=" + scr_network_debug_id_text(net.header.socketID)
		);
	}
}
#endregion /* Binary Packet Preparation END */

#region /* Socket Owner Dispatch */
/* Borrow both client and server session services. client_owns_event and
server_owns_event begin false until each available service checks the actual
socket/listener handles, independent of logical player slots */
var async_client = scr_get_client();
var async_server = scr_get_server();
var client_owns_event = false;
var server_owns_event = false;

/* An available client ownership method can recognize its outbound gameplay or
status socket. Missing support leaves the client ownership flag false */
if (is_struct(async_client)
&& variable_struct_exists(async_client, "owns_socket_event"))
{
	client_owns_event = async_client.owns_socket_event(network_id, network_socket);
}

/* An available server ownership method can recognize listeners, accepted players
or pending/status children. Missing support leaves server ownership false */
if (is_struct(async_server)
&& variable_struct_exists(async_server, "owns_socket_event"))
{
	server_owns_event = async_server.owns_socket_event(network_id, network_socket, network_server);
}

/* No session handler is selected yet. Outbound loopback is the client side, while
listeners and accepted children belong to hosting. Choose one receiver below
because its read calls consume the shared packet cursor */
var handler = noone;

/* Prefer the client for a recognized outbound connection, including loopback
Host & Play traffic. That endpoint carries client-side replies */
if (client_owns_event)
{
	handler = async_client;
}

/* Otherwise a recognized server listener/child belongs to authoritative hosting.
Send it to the server rather than processing its body as a client reply */
else if (server_owns_event)
{
	handler = async_server;
}

/* For an event neither service recognizes, an active host receives the fallback.
This allows server first-connection handling to inspect previously untracked children */
else if (is_hosting_server)
{
	handler = async_server;
}

/* Without recognized ownership or active hosting, use the current view as the
fallback. Client view chooses its session and server view chooses hosting */
else
{
	handler = is_client ? async_client : async_server;
}

/* The chosen session must exist and provide asynchronous routing.
Missing state reports an error and stops before reading its handler member */
if (!is_struct(handler) || !variable_struct_exists(handler, "on_async"))
{
	show_debug_message("Network handler missing on_async method.");
	return;
}

/* Capture the selected session-bound router so its net/ID/state remain attached
when forwarding this asynchronous event */
var on_async_handler = handler.on_async;

/* A member named on_async must also be callable. Reject a malformed session
router instead of invoking it and losing the event to an invalid call */
if (!is_method(on_async_handler))
{
	show_debug_message("Network handler on_async is not callable.");
	return;
}

/* Forward the event once to its selected owner. Catch routing exceptions here so
network diagnostics can explain the failed event instead of interrupting the
controller with an uncaught asynchronous error */
try
{
	on_async_handler(network_id, network_type, network_socket, network_data, network_server);
}
catch(e)
{
	/* msg starts with the caught routing error message for both project and runner
	logs. Add the longer diagnostic only when the exception exposes it */
	var msg = "Network async error: " + string(e.message);

	/* An exception with longMessage provides extended call details.
	Append those details when available and keep the basic message otherwise */
	if (variable_struct_exists(e, "longMessage"))
	{
		msg += "\n" + e.longMessage;
	}
	debug_error(msg);
	show_debug_message(msg);
}
#endregion /* Socket Owner Dispatch END */
