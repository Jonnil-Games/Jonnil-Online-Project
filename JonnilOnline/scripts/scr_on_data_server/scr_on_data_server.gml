/// @description Preflight client packet structure without advancing the shared read cursor
/// @param {Struct} net Network reader already primed past its three-byte header
/// @returns {Bool} Whether structural preflight passed. Legacy joins bypass body checks and log requests defer final validation to their handler
function scr_server_packet_is_valid(net)
{
	/* packet_size is the received byte count capped by buffer capacity. Reused
	buffers can contain spare bytes that do not belong to this incoming packet */
	var packet_size = min(net.reader_size, buffer_get_size(net.reader_buffer));

	/* Reject data shorter than the three-byte type/slot header or larger than the
	16 KiB accepted packet limit before inspecting the body */
	if (packet_size < 3 || packet_size > 16384) return false;

	/* cursor copies the body byte offset after the header. Validation advances
	this local position only, preserving the shared cursor for actual packet dispatch */
	var cursor = buffer_tell(net.reader_buffer);

	/* Positive entries count fixed bytes.
	Negative entries bound NUL-terminated string bytes */
	var manifest_fields = [-256, -256, -256, -64, 9, -256, -256, -64];

	/* fields receives the ordered body-size manifest selected by packet type.
	Unknown types return false before this uninitialized manifest can be traversed */
	var fields;

	/* Select a structural layout from the packet type, independently of gameplay
	permissions. Positive entries count fixed bytes and negative entries bound strings.
	The dispatcher later consumes the same field order */
	switch (net.header.type)
	{
		/* Versioned joins prepend a two-byte version and bounded username to the
		character manifest, establishing compatibility before gameplay setup */
		case N_JOIN_GAME_VERSIONED: fields = array_concat([2, -128], manifest_fields); break;

		/* A character change carries the manifest without join metadata */
		case N_PLAYER_CHARACTER: fields = manifest_fields; break;

		/* Pet selection carries a strict equipped flag and only includes image
		metadata when equipped. Removal ends immediately after its zero flag */
		case N_PLAYER_PET:
			if (packet_size - cursor < 1) return false;
			var pet_flag = buffer_peek(net.reader_buffer, cursor, buffer_u8);
			if (pet_flag > 1) return false;
			fields = pet_flag == 1 ? array_concat([1], manifest_fields) : [1];
			break;

		/* Character chunks add a leading two-byte field and trailing chunk index/data
		to the same manifest layout, bounding serialized chunk text */
		case N_PLAYER_CHARACTER_CHUNK: fields = array_concat([2], manifest_fields, [2, -12000]); break;

		/* Client chat is a bounded NUL-terminated string, preventing reads beyond
		this packet while leaving command interpretation to the chat handler */
		case N_MESSAGE: fields = [-960]; break;

		/* Admin auth carries version/request bytes followed by bounded key/token text.
		This validates structure only, and credential acceptance remains server-owned */
		case N_ADMIN_AUTH: fields = [5, -256, -4096]; break;

		/* Status requests contain one protocol byte and a four-byte request ID */
		case N_ADMIN_STATUS: fields = [5]; break;

		/* Admin commands add an action byte after version/request metadata.
		The selected action determines whether an additional setting value is present */
		case N_ADMIN_COMMAND:

			/* The action can be inspected only when its six-byte command header fits.
			Reject truncated requests before peeking at the action byte */
			if (packet_size - cursor < 6) return false;

			/* admin_action reads the command action without moving the shared cursor.
			Its offset follows the protocol byte and four-byte request ID */
			var admin_action = buffer_peek(net.reader_buffer, cursor + 5, buffer_u8);
			fields = [6];

			/* Enable/disable settings add one Boolean byte to the command header.
			Other commands keep their base size unless the next check requires a wider value */
			if (admin_action == ADMIN_ACTION_SET_RESET_ENABLED || admin_action == ADMIN_ACTION_SET_WALL_DRAWING) fields = [7];

			/* Minute intervals and player limits add a two-byte unsigned setting value.
			The final exact-size check rejects extra or missing command bytes */
			if (admin_action == ADMIN_ACTION_SET_RESET_INTERVAL || admin_action == ADMIN_ACTION_SET_MAX_PLAYERS) fields = [8];
			break;

		/* Heartbeat replies and latency probes each carry a four-byte sequence ID.
		Typing and legacy movement actions instead use a single state/action byte */
		case N_HEARTBEAT_PONG:
		case N_LATENCY_PROBE: fields = [4]; break;

		/* typing_is_active treats nonzero packet bytes as active. typing_server owns
		the sender typing indicator and broadcasts changes to other clients */
		case N_TYPING_STATE:

		/* Read the legacy movement byte into _key. pressed_player resolves the logical
		sender player, and pressed_action maps current action IDs or compatible key codes */
		case N_KEY_PRESS:
		case N_KEY_RELEASE: fields = [1]; break;

		/* Client movement carries a version byte, two signed four-byte pixel positions,
		and direction/moving bytes */
		case N_CLIENT_PLAYER_STATE: fields = [11]; break;

		/* Layer ballots use a six-byte fixed body. The drawing service interprets its
		vote subtype and IDs after structural validation */
		case N_LAYER_VOTE: fields = [6]; break;

		/* Serialized drawing commands use a bounded string body, leaving command
		semantics and authority checks to the drawing handler */
		case N_DRAW_COMMAND: fields = [-16380]; break;

		/* Wall edits require their fixed 15-byte body before wall validation runs */
		case N_WALL_EDIT: fields = [15]; break;

		/* Image packets combine fixed metadata and bounded strings for identifiers,
		manifest data and chunk text. Each component must fit in received bytes */
		case N_DRAW_IMAGE: fields = [32, -384, 9, -640, -12000]; break;

		/* Leave, gameplay-activity and status-query packets have no body. Exact cursor
		matching below rejects extra data for these empty-body messages */
		case N_LEAVE_GAME:

		/* afk_activity_server owns gameplay-idle timing. This packet refreshes the
		sender gameplay activity rather than merely keeping its socket alive */
		case N_AFK_ACTIVITY:
		case N_SERVER_STATUS_REQUEST: fields = []; break;

		/* Log requests accept a six-to-12-byte body here because their dedicated
		handler validates the action-specific layout. Other sizes are rejected */
		case N_ADMIN_LOGS: return packet_size - cursor >= 6 && packet_size - cursor <= 12;

		/* Legacy joins retain the existing body-check bypass for compatibility.
		Their acceptance here is not a gameplay or identity permission check */
		case N_JOIN_GAME: return true;

		/* Unrecognized packet types have no validated layout. Reject them before
		passing attacker-controlled body bytes to gameplay dispatch */
		default: return false;
	}

	/* Visit each zero-based manifest field in wire order until every required
	component is checked. i indexes layout entries, not sockets or players */
	for (var i = 0; i < array_length(fields); i++)
	{
		/* field is the current manifest width or negative string bound.
		Its sign selects fixed-size advancement or a bounded terminator search */
		var field = fields[i];

		/* Fixed-size fields need exactly their declared byte width. Strings instead
		use the negative-width branch because their actual length varies */
		if (field >= 0)
		{
			/* Reject a fixed field crossing the received-byte boundary so later reads do
			not consume unused buffer capacity */
			if (cursor + field > packet_size) return false;
			cursor += field;
		}

		/* Negative manifest entries bound a string search. Accept only a terminator
		within the packet and that field limit */
		else
		{
			/* string_end is the exclusive byte limit for this bounded string, capped by
			received data. terminated begins false until a zero byte is actually found */
			var string_end = min(packet_size, cursor - field + 1);
			var terminated = false; /* No terminator has been found for this string yet */

			/* Inspect bytes until the terminator is found or the bounded received range
			ends. cursor advances locally, preserving the shared reader position */
			while (cursor < string_end)
			{
				/* A zero byte completes this string. Mark it valid and stop searching so the
				following manifest field begins after its terminator */
				if (buffer_peek(net.reader_buffer, cursor++, buffer_u8) == 0)
				{
					terminated = true;
					break;
				}
			}

			/* No terminator within the allowed bytes means this string is incomplete or
			too long. Reject the packet instead of allowing an unbounded read */
			if (!terminated) return false;
		}
	}

	/* All described fields must consume the entire received packet. Remaining
	bytes indicate an unexpected layout, while an exact match passes preflight */
	return cursor == packet_size;
}

/// @description Consume a client packet after structural preflight in the server method context
/// @param {Array} sockets Server socket-slot array retained by the dispatch interface
/// @param {Real} sender_slot Socket-derived logical slot, defaulting to noone for the packet-header fallback
function scr_on_data_server(sockets, sender_slot = noone)
{
	/* Use the shared reader already primed for this packet. _key is populated
	only by legacy movement packets, and _id starts with the socket-derived logical
	sender slot supplied by the async server router */
	var net = scr_get_network();
	var _key;
	var _id = sender_slot;

	/* An omitted socket-derived slot falls back to the packet header for the
	retained dispatch interface. Normal async routing supplies the actual slot */
	if (_id == noone)
	{
		_id = net.header.socketID;
	}

	/* When the header claims another player, keep the router-established identity
	and log the correction. A client header cannot override its actual socket slot */
	else if (_id != net.header.socketID)
	{
		net.log_verbose("Packet header " + scr_network_debug_server_slot_label(net.header.socketID) + " corrected to actual " + scr_network_debug_server_slot_label(_id));
	}

	/* Dispatch the structurally validated client request to its owning service.
	Every handler receives the established logical sender slot rather than choosing
	an identity from packet body metadata */
	switch(net.header.type)
	{
		/* Wall requests are delegated to the wall service, which applies wall policy
		and edit validation before changing shared layout */
		case N_WALL_EDIT:
			scr_get_walls().receive_edit(_id);
			break;

		/* The log service owns final action validation and transfer state for this
		administrator log request */
		case N_ADMIN_LOGS:
			scr_admin_logs_server_receive(scr_get_server(), _id);
			break;

		/* Read admin protocol version, correlation request ID and supplied key/token
		strings in wire order. admin_auth_server is the shared server that validates them */
		case N_ADMIN_AUTH:
			var admin_auth_version = net.read(buffer_u8);
			var admin_auth_request_id = net.read(buffer_u32);
			var admin_auth_key_id = net.read(buffer_string);
			var admin_auth_token = net.read(buffer_string);
			var admin_auth_server = scr_get_server();

			/* Authentication runs only when the server and handler exist. Missing server
			capability skips this request without calling an invalid field */
			if (is_struct(admin_auth_server)
			&& variable_struct_exists(admin_auth_server, "handle_admin_auth"))
			{
				admin_auth_server.handle_admin_auth(
					_id,
					admin_auth_version,
					admin_auth_request_id,
					admin_auth_key_id,
					admin_auth_token
				);
			}
			break;

		/* The status version and request ID identify this protocol request.
		admin_status_server supplies the authenticated status handler */
		case N_ADMIN_STATUS:
			var admin_status_version = net.read(buffer_u8);
			var admin_status_request_id = net.read(buffer_u32);
			var admin_status_server = scr_get_server();

			/* Deliver status requests only to a present server method. An unavailable
			handler leaves this packet unapplied */
			if (is_struct(admin_status_server)
			&& variable_struct_exists(admin_status_server, "handle_admin_status_request"))
			{
				admin_status_server.handle_admin_status_request(_id, admin_status_version, admin_status_request_id);
			}
			break;

		/* Read command version, request ID and action before its optional setting value.
		admin_command_value starts undefined for actions that do not carry a value */
		case N_ADMIN_COMMAND:
			var admin_command_version = net.read(buffer_u8);
			var admin_command_request_id = net.read(buffer_u32);
			var admin_command_action = net.read(buffer_u8);
			var admin_command_value = undefined;

			/* Enable/reset-policy and wall-policy actions read a Boolean byte. Reset
			interval and maximum-player actions read an unsigned two-byte value. Actions
			without a value retain undefined for the server command handler */
			switch(admin_command_action)
			{
				case ADMIN_ACTION_SET_RESET_ENABLED:
				case ADMIN_ACTION_SET_WALL_DRAWING:
					admin_command_value = net.read(buffer_u8);
					break;
				case ADMIN_ACTION_SET_RESET_INTERVAL:
					admin_command_value = net.read(buffer_u16);
					break;
				case ADMIN_ACTION_SET_MAX_PLAYERS:
					admin_command_value = net.read(buffer_u16);
					break;
			}

			/* Borrow the server that authenticates and applies the requested admin action */
			var admin_command_server = scr_get_server();

			/* Only a present command handler receives this request. Missing support skips
			the operation rather than interpreting an administrator command locally */
			if (is_struct(admin_command_server)
			&& variable_struct_exists(admin_command_server, "handle_admin_command"))
			{
				admin_command_server.handle_admin_command(
					_id,
					admin_command_version,
					admin_command_request_id,
					admin_command_action,
					admin_command_value
				);
			}
			break;

		/* Admin outcomes belong to server replies. Ignore client-sent outcomes rather
		than allowing a client to manufacture the result of its own request */
		case N_ADMIN_RESULT:
			debug_error("Server ignored an admin result packet sent by a client.");
			break;

		/* Only the server publishes player capacity. Ignore client-sent capacity
		updates so a peer cannot change the authoritative limit */
		case N_SERVER_PLAYER_LIMIT:
			debug_error("Server ignored a player-limit packet sent by a client.");
			break;

		/* leave_server is the shared server used to close this sender slot. Returning
		to the list releases gameplay state instead of leaving a connected player behind */
		case N_LEAVE_GAME:
			var leave_server = scr_get_server();

			/* Close the slot only when its owning server supplies cleanup. Missing server
			support skips the call rather than attempting an invalid method */
			if (is_struct(leave_server)
			&& variable_struct_exists(leave_server, "close_client_slot"))
			{
				leave_server.close_client_slot(_id, "client returned to server list", true, true);
			}
			break;

		/* Consume the echoed sequence, then use heartbeat_server to mark this sender
		responsive. Heartbeats track connection liveness rather than gameplay activity */
		case N_HEARTBEAT_PONG:
			net.read(buffer_u32);
			var heartbeat_server = scr_get_server();

			/* Record liveness only when the shared server provides its activity method.
			An unavailable capability leaves heartbeat tracking unchanged */
			if (is_struct(heartbeat_server)
			&& variable_struct_exists(heartbeat_server, "note_client_activity"))
			{
				heartbeat_server.note_client_activity(_id);
			}
			break;

		/* latency_sequence is the client probe ID to echo. latency_server owns the
		reply timing limit and server diagnostics added to the response */
		case N_LATENCY_PROBE:
			var latency_sequence = net.read(buffer_u32);
			var latency_server = scr_get_server();

			/* A present server can record liveness and answer the probe. Without one,
			skip both operations rather than inspecting server methods */
			if (is_struct(latency_server))
			{
				/* Treat a valid probe as connection activity when that liveness capability
				exists. This does not mark the player as performing gameplay input */
				if (variable_struct_exists(latency_server, "note_client_activity"))
				{
					latency_server.note_client_activity(_id);
				}

				/* Answer through the server reply method when available, allowing its
				per-slot cooldown to control probe frequency */
				if (variable_struct_exists(latency_server, "send_latency_reply"))
				{
					latency_server.send_latency_reply(_id, latency_sequence);
				}
			}
			break;
		case N_TYPING_STATE:
			var typing_is_active = net.read(buffer_u8) != 0;
			var typing_server = scr_get_server();

			/* Apply typing changes only through a present server method, keeping missing
			capabilities from interrupting packet dispatch */
			if (is_struct(typing_server)
			&& variable_struct_exists(typing_server, "set_client_typing"))
			{
				typing_server.set_client_typing(_id, typing_is_active);
			}
			break;
		case N_AFK_ACTIVITY:
			var afk_activity_server = scr_get_server();

			/* Refresh gameplay activity when the server capability exists.
			Otherwise leave the current AFK state unchanged */
			if (is_struct(afk_activity_server)
			&& variable_struct_exists(afk_activity_server, "note_client_gameplay_activity"))
			{
				afk_activity_server.note_client_gameplay_activity(_id);
			}
			break;

		/* drawing is the shared canvas service that validates and applies the sender
		command from the remaining reader bytes */
		case N_DRAW_COMMAND:
			var drawing = scr_get_drawing();

			/* Pass the command only to an available drawing handler. Missing drawing
			support skips the request without reading it as another packet type */
			if (is_struct(drawing)
			&& variable_struct_exists(drawing, "server_handle_command"))
			{
				drawing.server_handle_command(_id);
			}
			break;

		/* drawing_image owns image-chunk assembly for this sender and consumes the
		remaining image metadata/body through its server handler */
		case N_DRAW_IMAGE:
			var drawing_image = scr_get_drawing();

			/* Accept image chunks only when the image-upload handler exists.
			Otherwise this packet cannot modify drawing state */
			if (is_struct(drawing_image)
			&& variable_struct_exists(drawing_image, "server_handle_image_chunk"))
			{
				drawing_image.server_handle_image_chunk(_id);
			}
			break;

		/* Decode requested character metadata without remembering it in the registry yet.
		character_server validates and assigns it to the sender before publishing the
		resulting appearance identity */
		case N_PLAYER_CHARACTER:
			var requested_character_manifest = scr_get_player_characters().read_manifest(net, false);
			var character_server = scr_get_server();

			/* Assign the character only through an available server handler. Missing
			capability leaves the sender current character unchanged */
			if (is_struct(character_server)
			&& variable_struct_exists(character_server, "set_client_character"))
			{
				character_server.set_client_character(_id, requested_character_manifest);
			}
			break;

		/* Pet selection has its own owner slot and reuses character metadata. The
		server validates this request before updating or broadcasting the pet */
		case N_PLAYER_PET:
			var requested_pet_equipped = net.read(buffer_u8);
			var requested_pet_manifest = requested_pet_equipped == 1
				? scr_get_player_characters().read_manifest(net, false)
				: noone;
			scr_get_server().set_client_pet(_id, requested_pet_manifest);
			break;

		/* chunk_server owns shared image transfer for the sender slot. Its chunk
		handler consumes and validates the remaining packet body */
		case N_PLAYER_CHARACTER_CHUNK:
			var chunk_server = scr_get_server();

			/* Delegate chunks only when the server transfer method exists, avoiding an
			invalid field call when character upload is unavailable */
			if (is_struct(chunk_server)
			&& variable_struct_exists(chunk_server, "handle_client_character_chunk"))
			{
				chunk_server.handle_client_character_chunk(_id);
			}
			break;

		/* raw_input is the complete submitted chat text. server is the shared server
		whose chat handler applies sender identity, commands and chat rules */
		case N_MESSAGE:
			var raw_input = net.read(buffer_string);
			var server = scr_get_server();

			/* Without the server chat method, report the missing capability and stop this
			packet branch rather than interpreting user text elsewhere */
			if (!is_struct(server)
			|| !variable_struct_exists(server, "handle_chat_input"))
			{
				debug_error("Server chat handler is missing.");
				break;
			}

			server.handle_chat_input(_id, raw_input);
			break;

		/* Read movement protocol, signed world-pixel x/y, direction and moving byte
		in their wire order. movement_server owns validation and accepted-state broadcast */
		case N_CLIENT_PLAYER_STATE:
			var movement_protocol_version = net.read(buffer_u8);
			var movement_x = net.read(TYPE_POSITION);
			var movement_y = net.read(TYPE_POSITION);
			var movement_direction = net.read(buffer_u8);
			var movement_is_moving = net.read(buffer_u8);
			var movement_server = scr_get_server();

			/* Apply movement only through a present authoritative server handler.
			Missing support leaves player state unchanged */
			if (is_struct(movement_server)
			&& variable_struct_exists(movement_server, "apply_client_player_state"))
			{
				movement_server.apply_client_player_state(
					_id,
					movement_protocol_version,
					movement_x,
					movement_y,
					movement_direction,
					movement_is_moving
				);
			}
			break;

		/* layer_vote_drawing owns the active drawing-layer vote and validates this
		sender ballot against that vote */
		case N_LAYER_VOTE:
			var layer_vote_drawing = scr_get_drawing();

			/* Deliver the ballot only when the shared drawing service exposes its server
			vote handler. Otherwise leave vote state unchanged */
			if (is_struct(layer_vote_drawing)
			&& variable_struct_exists(layer_vote_drawing, "server_handle_layer_vote_packet"))
			{
				layer_vote_drawing.server_handle_layer_vote_packet(_id);
			}
			break;
		case N_KEY_PRESS:
			_key = net.read(buffer_u8);
			var pressed_player = player_controller_get_player(_id);
			var pressed_action = scr_player_input_network_value_to_action(_key);

			/* Emit press diagnostics only in verbose mode. Normal movement processing
			continues without adding a message for every key press */
			if (net.verbose)
			{
				debug_log("Player " + string(_id) + " pressed movement " + scr_player_input_action_name(pressed_action) + ": " + string(_key));
			}

			/* An unavailable player or unrecognized movement action cannot be applied.
			Stop this packet before changing input state or gameplay activity */
			if (pressed_player == noone
			|| pressed_action == noone)
			{
				break;
			}

			/* Borrow the server that refreshes AFK activity for this accepted press */
			var pressed_activity_server = scr_get_server();

			/* Record the accepted gameplay input when the server provides AFK tracking.
			Missing tracking support does not prevent the movement action itself */
			if (is_struct(pressed_activity_server)
			&& variable_struct_exists(pressed_activity_server, "note_client_gameplay_activity"))
			{
				pressed_activity_server.note_client_gameplay_activity(_id);
			}

			scr_player_input_set_player_action_state(pressed_player, pressed_action, true);

			break;

		/* Read the legacy release byte into _key. released_player resolves the sender,
		and released_action decodes its movement action before changing held input */
		case N_KEY_RELEASE:
			_key = net.read(buffer_u8);
			var released_player = player_controller_get_player(_id);
			var released_action = scr_player_input_network_value_to_action(_key);

			/* Emit release diagnostics only in verbose mode, keeping routine movement
			releases out of normal logs */
			if (net.verbose)
			{
				debug_log("Player " + string(_id) + " released movement " + scr_player_input_action_name(released_action) + ": " + string(_key));
			}

			/* Ignore a release with no player or recognized action. This prevents invalid
			packet values from altering another input state */
			if (released_player == noone
			|| released_action == noone)
			{
				break;
			}

			/* Borrow the server that records this accepted release as gameplay activity */
			var released_activity_server = scr_get_server();

			/* Refresh AFK activity when its server capability exists. Otherwise the valid
			movement release still clears the held action */
			if (is_struct(released_activity_server)
			&& variable_struct_exists(released_activity_server, "note_client_gameplay_activity"))
			{
				released_activity_server.note_client_gameplay_activity(_id);
			}

			scr_player_input_set_player_action_state(released_player, released_action, false);
			break;

		/* Unexpected dispatch IDs produce a diagnostic and perform no gameplay
		operation, leaving unsupported requests unapplied */
		default:
			debug_error("Server received unknown packet type: " + string(net.header.type));
			break;
	}
}
