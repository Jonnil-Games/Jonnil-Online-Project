/// @description Consume the current server packet in the client method context. Uses its net, ID, and session methods
function scr_on_data_client()
{
	/* _id holds the logical player slot from the current entry, and _x/_y hold
	its signed world-pixel coordinates. They begin unassigned and are filled only by
	packet branches whose layouts include those fields */
	var _id, _x, _y;

	/* Borrow the shared client that owns this session. preserve_local_server_state
	is true only for a present client in local-host mode, where server/client paths
	share player and canvas state and client cleanup must not erase the live host */
	var packet_client = scr_get_client();
	var preserve_local_server_state = is_struct(packet_client)
		&& variable_struct_exists(packet_client, "local_host_mode")
		&& packet_client.local_host_mode;

	/* Dispatch the server body using the type already read in the shared header.
	Each branch reads only its own wire layout and routes changes to their owning
	client, player, chat, canvas or lifecycle service */
	switch(net.header.type)
	{
		/* The wall-settings packet carries one strict Boolean byte, enabling client
		wall support while keeping the server policy authoritative */
		case N_WALL_SETTINGS:

			/* Require exactly one readable body byte. Truncation or extra bytes stops this
			branch rather than applying a malformed wall policy */
			if (!net.can_read_fields([buffer_u8]) || net.reader_size - buffer_tell(net.reader_buffer) != 1) break;

			/* walls_enabled is the wire policy byte. It must be zero or one before being
			stored as the client enabled flag */
			var walls_enabled = net.read(buffer_u8);

			/* Reject bytes outside the Boolean wire format instead of treating any
			nonzero value as permission to draw walls */
			if (walls_enabled > 1) break;

			/* A valid settings packet establishes wall support for this connection.
			Only byte one enables editing, while zero disables it */
			packet_client.wall_drawing_supported = true;
			packet_client.wall_drawing_enabled = walls_enabled == 1;
			scr_get_walls().set_client_enabled(packet_client.wall_drawing_enabled);
			break;

		/* Apply a server-approved edit through the wall client handler rather than
		interpreting its body as a local drawing action */
		case N_WALL_EDIT:
			scr_get_walls().receive_edit_client();
			break;

		/* The wall service owns snapshot decoding and replacement of synchronized
		wall layout */
		case N_WALL_SNAPSHOT:
			scr_get_walls().receive_snapshot();
			break;

		/* Wall corrections contain two signed four-byte pixel coordinates and target
		the local player, allowing server layout changes to resolve its position */
		case N_WALL_PLAYER_CORRECTION:

			/* Require exactly the two correction coordinates. An incomplete or oversized
			body must not alter the local player position */
			if (!net.can_read_fields([buffer_s32, buffer_s32]) || net.reader_size - buffer_tell(net.reader_buffer) != 8) break;

			/* wall_correction_x/y are corrected world-pixel coordinates from the server.
			wall_correction_player resolves the existing local logical ID without creating
			a missing player */
			var wall_correction_x = net.read(buffer_s32);
			var wall_correction_y = net.read(buffer_s32);
			var wall_correction_player = player_controller_get_player(ID, false);

			/* Deliver correction only to an existing player with the correction method.
			Missing players or older player shapes leave their position unchanged */
			if (wall_correction_player != noone && variable_struct_exists(wall_correction_player, "receive_wall_correction"))
			{
				wall_correction_player.receive_wall_correction(wall_correction_x, wall_correction_y);
			}
			break;

		/* The assignment reply completes a pending join, carrying the local slot,
		position, name, visual state, character identity and drawing-author identity */
		case N_ID:

			/* Accept assignment only before an ID exists and while a sent join is pending.
			Duplicate or unsolicited replies cannot replace an established session identity */
			if (ID != noone || !connect_pending || !join_request_sent) break;

			/* The assignment must contain a complete extended player entry before reading
			its fields. A truncated reply fails the pending connection with a reconnect message */
			if (!packet_client.can_read_player_entry(true))
			{
				packet_client.fail_pending_connect("The server sent an incomplete join response. Please reconnect.");
				break;
			}
			_id = net.read(TYPE_ID);
			_x = net.read(TYPE_POSITION);
			_y = net.read(TYPE_POSITION);

			/* assigned_name is the server-approved username. assigned_direction and
			assigned_is_moving initialize its visual state. The character manifest/key identify
			its appearance, and assigned_drawing_author_id associates future drawing ownership */
			var assigned_name = net.read(buffer_string);
			var assigned_direction = net.read(buffer_u8);
			var assigned_is_moving = net.read(buffer_u8);
			var assigned_character_manifest = scr_get_player_characters().read_manifest(net);
			var assigned_character_key = assigned_character_manifest.network_key;
			var assigned_drawing_author_id = net.read(buffer_u32);

			/* Older servers omit the optional canvas capability byte, so false starts the
			quiet-window compatibility fallback. A byte one enables explicit history completion */
			var canvas_sync_completion_required = false;

			/* Consume the capability only when another byte is available. Otherwise keep
			the legacy fallback instead of reading beyond an older assignment layout */
			if (net.can_read_fields([buffer_u8]))
			{
				canvas_sync_completion_required = net.read(buffer_u8) == 1;
			}

			ID = _id;
			assigned_username = assigned_name;

			/* Borrow the shared chat state to store the assigned username and show the
			join announcement. Local-host mode retains server-owned typing and AFK indicators */
			var chat = scr_get_chat();
			chat.assigned_username = assigned_name;

			/* Remote joins clear stale typing and AFK entries from the previous session.
			Local hosts retain these shared server indicators */
			if (!preserve_local_server_state)
			{
				chat.clear_typing_states(false);
				chat.clear_afk_states();
			}

			/* Use the client chat receiver when available so it can handle join-time
			queuing and export behavior. The alternative writes directly to chat */
			if (is_struct(packet_client)
			&& variable_struct_exists(packet_client, "add_received_chat_message"))
			{
				packet_client.add_received_chat_message(CHAT_TYPE_SYSTEM, noone, "", assigned_name + " joined the game.");
			}

			/* Without the client message wrapper, add the join announcement directly.
			This preserves the existing chat fallback for older client shapes */
			else
			{
				chat.add_message(CHAT_TYPE_SYSTEM, noone, "", assigned_name + " joined the game.");
			}
			connect_pending = false;
			connect_deadline = 0;
			connect_failed_message = "";
			needs_server_list = false;
			debug_success("Client received assigned ID packet.");
			debug_log("My identity is " + scr_network_debug_id_label(_id, assigned_name) + " character=" + assigned_character_key + " drawingAuthor=" + string(assigned_drawing_author_id));

			/* Borrow the drawing service to connect the assigned slot/name to its stable
			author ID and begin initial history synchronization */
			var drawing_identity = scr_get_drawing();

			/* A drawing service with identity support receives the assigned author
			metadata. Missing support skips identity setup without calling an invalid method */
			if (is_struct(drawing_identity)
			&& variable_struct_exists(drawing_identity, "set_local_identity"))
			{
				drawing_identity.set_local_identity(_id, assigned_name, assigned_drawing_author_id);
			}

			/* Begin history synchronization only when this drawing service exposes the
			compatibility batching method. The capability flag selects explicit completion
			or the legacy quiet-window fallback */
			if (is_struct(drawing_identity)
			&& variable_struct_exists(drawing_identity, "begin_legacy_client_history_sync_batch"))
			{
				/* Older servers omit the capability and retain the quiet-window fallback.
				Updated servers require their ordered history-completion packet */
				drawing_identity.client_history_sync_completion_required = canvas_sync_completion_required;
				drawing_identity.begin_legacy_client_history_sync_batch();
			}

			/* Local hosts first reuse the player already created by their server path.
			Remote joins start with noone and create the client player from the assignment */
			var created_local_player = preserve_local_server_state
				? player_controller_get_player(_id, false)
				: noone;

			/* Create the local player only when no host-owned player was found.
			This prevents replacing shared host state with a second player instance */
			if (created_local_player == noone)
			{
				created_local_player = player_controller_make_player(_id, _x, _y, assigned_name, assigned_character_key);
			}

			/* The host already owns this player. Refresh its assigned name and character
			instead of discarding its current shared state */
			else
			{
				created_local_player.username = assigned_name;

				/* Update the reused host player appearance when its character method exists.
				Older player shapes retain their existing appearance */
				if (variable_struct_exists(created_local_player, "set_character_key"))
				{
					created_local_player.set_character_key(assigned_character_key);
				}
			}

			/* If creation also failed, stop join completion and report reconnect guidance.
			Later visual or authority methods require an actual player */
			if (created_local_player == noone)
			{
				debug_error("Failed to create local player for ID " + string(_id));
				packet_client.fail_pending_connect("Could not create your player. Please reconnect.");
				break;
			}

			/* Apply assignment direction and moving state when this player supports
			visual initialization. Missing support leaves its existing visual state */
			if (variable_struct_exists(created_local_player, "set_visual_state"))
			{
				created_local_player.set_visual_state(assigned_direction, assigned_is_moving);
			}

			/* Request the movement protocol handshake only when the player supports client
			movement authority. Older players keep their existing movement mode */
			if (variable_struct_exists(created_local_player, "request_client_movement_authority"))
			{
				created_local_player.request_client_movement_authority();
			}
			scr_get_player_characters().set_selected_key(assigned_character_key, false);
			scr_get_player_characters().send_selected_to_server();
			packet_client.send_player_pet(scr_get_pets().load_selected_key());

			/* An available admin-auth method may start optional admin authentication after
			joining. Clients without that capability complete gameplay normally */
			if (is_struct(packet_client)
			&& variable_struct_exists(packet_client, "send_admin_auth"))
			{
				packet_client.send_admin_auth();
			}

			debug_log("Created local player " + scr_network_debug_id_label(ID, assigned_name) + " at (" + string(_x) + ", " + string(_y) + ")");
			break;

		/* A roster-add packet describes another player slot and its initial position,
		name, movement visuals and character. Local hosts reuse their existing server player */
		case N_NEW_PLAYER:

			/* Skip an incomplete roster entry before reading any of its fields, preventing
			a truncated update from constructing a player with partial state */
			if (!packet_client.can_read_player_entry()) break;
			_id = net.read(TYPE_ID);
			_x = net.read(TYPE_POSITION);
			_y = net.read(TYPE_POSITION);

			/* new_player_name and movement bytes initialize this roster player. Its decoded
			character manifest provides new_player_character_key for the appearance lookup */
			var new_player_name = net.read(buffer_string);
			var new_player_direction = net.read(buffer_u8);
			var new_player_is_moving = net.read(buffer_u8);
			var new_player_character_manifest = scr_get_player_characters().read_manifest(net);
			var new_player_character_key = new_player_character_manifest.network_key;

			debug_success("Client received new player packet.");
			debug_log("New player joined: " + scr_network_debug_id_label(_id, new_player_name) + " character=" + new_player_character_key);

			/* Reuse the shared server player during local hosting. Other clients start
			with noone so the roster entry creates their representation of this remote player */
			var created_new_player = preserve_local_server_state
				? player_controller_get_player(_id, false)
				: noone;

			/* Create the roster player when no existing local-host representation was
			found. A reused host player takes the following metadata-update path */
			if (created_new_player == noone)
			{
				created_new_player = player_controller_make_player(_id, _x, _y, new_player_name, new_player_character_key);
			}

			/* The local server already created this player. Refresh name and appearance
			without replacing its server-owned position and state */
			else
			{
				created_new_player.username = new_player_name;

				/* Update the reused player character when the setter is supported.
				Otherwise retain the existing character rather than calling an unavailable method */
				if (variable_struct_exists(created_new_player, "set_character_key"))
				{
					created_new_player.set_character_key(new_player_character_key);
				}
			}

			/* A failed creation has no player state to initialize. Report it and stop this
			packet branch while leaving existing roster entries intact */
			if (created_new_player == noone)
			{
				debug_error("Failed to create new player for ID " + string(_id));
				break;
			}

			/* A player with visual-state support receives the roster direction and moving
			flag. Other player shapes keep their current visual state */
			if (variable_struct_exists(created_new_player, "set_visual_state"))
			{
				created_new_player.set_visual_state(new_player_direction, new_player_is_moving);
			}

			debug_log("Created new player " + scr_network_debug_id_label(_id, new_player_name) + " at (" + string(_x) + ", " + string(_y) + ")");
			break;

		/* The initial roster repeats player entries and ends with a noone slot marker.
		Validate each entry before creating or updating its client representation */
		case N_PLAYER_LIST:

			/* Continue while at least a signed two-byte slot remains. A noone slot ends
			the roster, and incomplete entries stop processing without reading stale capacity */
			while (buffer_tell(net.reader_buffer) + 2 <= net.reader_size)
			{
				/* list_entry_start saves this entry byte offset. After checking the terminator
				slot, rewind here so the player-entry validator sees the complete entry */
				var list_entry_start = buffer_tell(net.reader_buffer);
				_id = net.read(TYPE_ID);

				/* The noone slot is the explicit end-of-roster marker. Stop instead of treating
				it as a player index */
				if (_id == noone)
				{
					break;
				}

				buffer_seek(net.reader_buffer, buffer_seek_start, list_entry_start);

				/* An incomplete roster entry makes the connection unusable for synchronization.
				Mark it lost and stop rather than installing partial player state */
				if (!packet_client.can_read_player_entry())
				{
					packet_client.mark_connection_lost("The server sent an incomplete player list. Please reconnect.");
					break;
				}
				_id = net.read(TYPE_ID);

				_x = net.read(TYPE_POSITION);
				_y = net.read(TYPE_POSITION);

				/* list_player_name and movement bytes describe this roster entry.
				list_player_character_manifest/key supply its appearance identity */
				var list_player_name = net.read(buffer_string);
				var list_player_direction = net.read(buffer_u8);
				var list_player_is_moving = net.read(buffer_u8);
				var list_player_character_manifest = scr_get_player_characters().read_manifest(net);
				var list_player_character_key = list_player_character_manifest.network_key;

				debug_success("Client received new player packet.");
				debug_log("New player joined: " + scr_network_debug_id_label(_id, list_player_name) + " character=" + list_player_character_key);

				/* Local hosts reuse the existing server player at this slot. Remote clients
				start with noone and build a player from the validated roster entry */
				var list_created_new_player = preserve_local_server_state
					? player_controller_get_player(_id, false)
					: noone;

				/* Create this roster player only when a shared host player was not found */
				if (list_created_new_player == noone)
				{
					list_created_new_player = player_controller_make_player(_id, _x, _y, list_player_name, list_player_character_key);
				}

				/* Refresh the existing host player name/character while preserving its shared
				server-owned state */
				else
				{
					list_created_new_player.username = list_player_name;

					/* Change the reused host player appearance only when its character setter
					exists. Missing capability preserves its current character */
					if (variable_struct_exists(list_created_new_player, "set_character_key"))
					{
						list_created_new_player.set_character_key(list_player_character_key);
					}
				}

				/* If creation fails, stop the roster loop because this entry cannot receive
				visual state. Earlier successfully created players remain in the roster */
				if (list_created_new_player == noone)
				{
					debug_error("Failed to create new player for ID " + string(_id));
					break;
				}

				/* Initialize direction and motion only for a player that supports visual-state
				updates. Other shapes keep their existing presentation */
				if (variable_struct_exists(list_created_new_player, "set_visual_state"))
				{
					list_created_new_player.set_visual_state(list_player_direction, list_player_is_moving);
				}

				debug_log("Created new player " + scr_network_debug_id_label(_id, list_player_name) + " at (" + string(_x) + ", " + string(_y) + ")");
			}
			break;

		/* Remove the departed logical slot from client player and chat indicators.
		If it was the host slot, clear that ownership marker as well */
		case N_REMOVE_PLAYER:
			_id = net.read(TYPE_ID);

			/* Clear host ownership only when that client field exists and names this
			departing slot. Other departures leave the host marker unchanged */
			if (is_struct(packet_client)
			&& variable_struct_exists(packet_client, "host_player_slot")
			&& packet_client.host_player_slot == _id)
			{
				packet_client.host_player_slot = noone;
			}
			scr_get_chat().set_typing_state(_id, "", false);
			scr_get_chat().set_afk_state(_id, "", false);

			/* Log removal only when a player entry was actually removed.
			An already absent player needs no second removal announcement */
			if (player_controller_remove_player(_id))
			{
				debug_log("Removed player " + scr_network_debug_id_text(_id));
			}
			break;

		/* full_message is the join-rejection text supplied by the server.
		The fallback ensures pending connection failure always has a visible explanation */
		case N_SERVER_FULL:
			var full_message = net.read(buffer_string);

			/* Invalid or empty server text uses the existing full-server message.
			A valid nonempty explanation passes through to pending-join failure */
			if (!is_string(full_message) || full_message == "")
			{
				full_message = "Server is full.";
			}

			packet_client.fail_pending_connect(full_message);
			break;

		/* kick_message is the server removal reason, with empty text replaced by a
		clear fallback. kick_client owns normal session cleanup when its handler exists */
		case N_SERVER_KICK:
			var kick_message = net.read(buffer_string);

			/* Use the fallback removal text when the server supplied no reason, so the
			player does not return to the server list without an explanation */
			if (kick_message == "")
			{
				kick_message = "You were kicked from the server.";
			}

			/* Borrow the session owner to apply the kick reason and connection cleanup */
			var kick_client = scr_get_client();

			/* The session kick handler performs normal cleanup when available.
			Otherwise the following compatibility path updates the essential connection state */
			if (is_struct(kick_client)
			&& variable_struct_exists(kick_client, "handle_server_kick"))
			{
				kick_client.handle_server_kick(kick_message);
			}

			/* Without the kick handler, set failure/list state directly. Remote clients
			clear gameplay services, while local hosts retain shared server state */
			else
			{
				connect_status = kick_message;
				connect_failed_message = kick_message;
				needs_server_list = true;
				host_player_slot = noone;

				/* Only remote-client state may be cleared here. Local-host player, chat,
				drawing and collision state belongs to the still-shared server path */
				if (!preserve_local_server_state)
				{
					player_controller_clear_players();
					scr_get_chat().clear_typing_states(false);
					scr_get_chat().clear_afk_states();
					scr_get_drawing().reset_client();
					scr_get_collision_objects().reset_client();
				}
			}
			debug_error(kick_message);
			break;

		/* drawing is the shared canvas service responsible for decoding this approved
		server drawing command */
		case N_DRAW_COMMAND:
			var drawing = scr_get_drawing();

			/* Only an available receive_command capability applies the drawing operation.
			Missing drawing support leaves the canvas unchanged */
			if (is_struct(drawing)
			&& variable_struct_exists(drawing, "receive_command"))
			{
				drawing.receive_command();
			}
			break;

		/* history_drawing owns synchronization of saved drawing operations into the
		client canvas */
		case N_DRAW_HISTORY:
			var history_drawing = scr_get_drawing();

			/* Apply history only when its receiving method exists. Missing capability
			skips the history packet without an invalid method call */
			if (is_struct(history_drawing)
			&& variable_struct_exists(history_drawing, "receive_history"))
			{
				history_drawing.receive_history();
			}
			break;

		/* image_drawing owns client assembly of image chunks and their drawing state */
		case N_DRAW_IMAGE:
			var image_drawing = scr_get_drawing();

			/* Deliver image bytes only to a present image-chunk receiver. Missing support
			leaves pending images unchanged */
			if (is_struct(image_drawing)
			&& variable_struct_exists(image_drawing, "receive_image_chunk"))
			{
				image_drawing.receive_image_chunk();
			}
			break;

		/* collision_objects is the shared collision service that decodes this server
		state packet body */
		case N_COLLISION_OBJECT_STATE:
			var collision_objects = scr_get_collision_objects();

			/* Apply collision state only through an available receiving method.
			Without that capability this packet does not change collision objects */
			if (is_struct(collision_objects)
			&& variable_struct_exists(collision_objects, "receive_state_packet_body"))
			{
				collision_objects.receive_state_packet_body();
			}
			break;

		/* Read the character slot and manifest. character_key is its network appearance
		identity, and character_player resolves an existing player without creating one */
		case N_PLAYER_CHARACTER:
			_id = net.read(TYPE_ID);
			var character_manifest = scr_get_player_characters().read_manifest(net);
			var character_key = character_manifest.network_key;
			var character_player = player_controller_get_player(_id, false);

			/* Change appearance only for an existing player with a character setter.
			Unknown slots or unsupported player shapes leave roster state unchanged */
			if (character_player != noone
			&& variable_struct_exists(character_player, "set_character_key"))
			{
				character_player.set_character_key(character_key);
			}

			/* The local assigned slot also updates the selected-character setting, keeping
			the character UI aligned with the server-approved appearance */
			if (_id == ID)
			{
				scr_get_player_characters().set_selected_key(character_key, false);
			}
			break;

		/* Pet packets use the owner in the server header and a strict equipped byte.
		Their shared manifest changes only the pet slot, leaving player appearance alone */
		case N_PLAYER_PET:
			if (!net.can_read_fields([buffer_u8])) break;
			var pet_equipped = net.read(buffer_u8);
			if (pet_equipped > 1) break;

			/* Only equipped pets carry the shared manifest fields. Validate their entire
			body before decoding so a truncated packet cannot create a partial pet */
			if (pet_equipped == 1 && !net.can_read_fields([
				buffer_string, buffer_string, buffer_string, buffer_string,
				buffer_u8, buffer_u32, buffer_u16, buffer_u8, buffer_u8,
				buffer_string, buffer_string, buffer_string])) break;
			var pet_manifest = pet_equipped == 1
				? scr_get_player_characters().read_manifest(net, false)
				: noone;
			if (buffer_tell(net.reader_buffer) != net.reader_size) break;
			packet_client.acknowledge_player_pet(net.header.socketID, pet_manifest);
			scr_get_pets().receive_player_pet(net.header.socketID, pet_manifest);
			break;

		/* Character and pet assets share the character service, which owns chunk
		validation and the image cache used by both appearances */
		case N_PLAYER_CHARACTER_CHUNK:
			scr_get_player_characters().receive_character_chunk();
			break;

		/* status_players, status_max_players and status_server_name consume the listing
		response in wire order. This gameplay dispatcher currently does not apply them
		to the server-list UI */
		case N_SERVER_STATUS:
			var status_players = net.read(buffer_s16);
			var status_max_players = net.read(buffer_s16);
			var status_server_name = net.read(buffer_string);
			break;

		/* received_host_slot is the logical player slot owning the host marker, or
		noone when there is no host player. Validate numeric slots before storing it */
		case N_HOST_STATUS:
			var received_host_slot = net.read(TYPE_ID);

			/* Only an assigned host slot needs bounds validation. The noone marker is
			already a valid representation of absent host ownership */
			if (received_host_slot != noone)
			{
				/* received_host_index is the whole-number candidate used to reject fractional
				or out-of-capacity player-slot values */
				var received_host_index = floor(received_host_slot);

				/* Reject fractional, negative and out-of-storage host slots. Clear the marker
				rather than exposing an invalid logical ID to host UI */
				if (received_host_slot != received_host_index
				|| received_host_index < 0
				|| received_host_index >= net.max_clients)
				{
					debug_error("Client received invalid host player slot: " + string(received_host_slot));
					received_host_slot = noone;
				}
			}
			host_player_slot = received_host_slot;
			debug_log("Client host player slot is now " + string(host_player_slot));
			break;

		/* Read one logical player slot and its signed world-pixel coordinates.
		The resolved player receives interpolation-aware updates when supported */
		case N_PLAYER_POSITION:
			_id = net.read(TYPE_ID);
			_x = net.read(TYPE_POSITION);
			_y = net.read(TYPE_POSITION);

			/* p is the existing player representation for this logical slot.
			A missing player cannot receive a position update */
			var p = player_controller_get_player(_id);

			/* Ignore positions for an absent player instead of creating an incomplete
			roster entry from movement data */
			if (p == noone)
			{
				break;
			}

			/* Use the player position receiver when available so it can manage smoothing
			and local movement authority. Older players use the direct-position fallback */
			if (variable_struct_exists(p, "receive_server_position"))
			{
				p.receive_server_position(_x, _y);
			}

			/* Without the specialized receiver, write the server coordinates directly to
			this player position, retaining compatibility with older player shapes */
			else
			{
				p.pos.x = _x;
				p.pos.y = _y;
			}

			break;

		/* Position batches repeat logical slot plus two signed pixel coordinates,
		ending at the noone slot marker or received-byte boundary */
		case N_PLAYER_POSITION_BATCH:

			/* Continue while another two-byte slot is readable. The end marker or an
			incomplete coordinate pair stops the batch without reading spare buffer bytes */
			while (buffer_tell(net.reader_buffer) + 2 <= net.reader_size)
			{
				_id = net.read(TYPE_ID);

				/* The noone slot terminates the position batch and is not a movement target */
				if (_id == noone)
				{
					break;
				}

				/* A position entry needs eight more bytes for x/y. Stop at a truncated pair
				before changing any player from that incomplete entry */
				if (buffer_tell(net.reader_buffer) + 8 > net.reader_size) break;
				_x = net.read(TYPE_POSITION);
				_y = net.read(TYPE_POSITION);

				/* batch_player resolves the logical slot for this entry. A missing player is
				skipped while later batch entries can still update existing players */
				var batch_player = player_controller_get_player(_id);

				/* This entry has no known player. Continue to the next entry instead of
				creating a partial player from position bytes alone */
				if (batch_player == noone)
				{
					continue;
				}

				/* Use the player receiver when supported, preserving its smoothing/authority
				rules. Otherwise apply the compatible direct-position update */
				if (variable_struct_exists(batch_player, "receive_server_position"))
				{
					batch_player.receive_server_position(_x, _y);
				}

				/* Older player shapes receive x/y directly because they have no specialized
				server-position method */
				else
				{
					batch_player.pos.x = _x;
					batch_player.pos.y = _y;
				}
			}
			break;

		/* State batches include position, direction and moving flag for each logical
		slot. The noone marker terminates the list */
		case N_PLAYER_STATE_BATCH:

			/* Read another entry only while its two-byte slot fits. The terminator or
			incomplete remaining state ends the batch safely */
			while (buffer_tell(net.reader_buffer) + 2 <= net.reader_size)
			{
				_id = net.read(TYPE_ID);

				/* Stop at the noone state-batch terminator rather than treating it as a player */
				if (_id == noone)
				{
					break;
				}

				/* Each state body needs two four-byte coordinates and two visual bytes.
				Stop before a partial entry can change the player */
				if (buffer_tell(net.reader_buffer) + 10 > net.reader_size) break;
				_x = net.read(TYPE_POSITION);
				_y = net.read(TYPE_POSITION);

				/* state_direction and state_is_moving are the visual fields for this entry.
				state_player resolves its logical slot after all body bytes have been read */
				var state_direction = net.read(buffer_u8);
				var state_is_moving = net.read(buffer_u8);

				var state_player = player_controller_get_player(_id);

				/* Skip unknown roster players while continuing through later valid state
				entries, avoiding incomplete player creation from movement traffic */
				if (state_player == noone)
				{
					continue;
				}

				/* The specialized receiver accepts position and visual state together.
				Older shapes fall back to direct coordinates */
				if (variable_struct_exists(state_player, "receive_server_position"))
				{
					state_player.receive_server_position(_x, _y, state_direction, state_is_moving);
				}

				/* Without the state receiver, update only the existing position fields.
				The fallback does not apply direction or moving bytes */
				else
				{
					state_player.pos.x = _x;
					state_player.pos.y = _y;
				}
			}
			break;

		/* chat_type selects message presentation, sender_id is a logical slot and
		sender_name/content carry the approved visible text. sent_at starts with the local
		display timestamp so older servers without a timestamp remain readable */
		case N_MESSAGE:
			var chat_type = net.read(buffer_u8);
			var sender_id = net.read(TYPE_ID);
			var sender_name = net.read(buffer_string);
			var content = net.read(buffer_string);
			var sent_at = chat_display_timestamp();

			/* Read an optional server timestamp only when a live numeric buffer has bytes
			remaining by its capacity check. Otherwise retain the local timestamp fallback.
			This existing check uses capacity rather than reader_size */
			if (is_real(net.reader_buffer)
			&& buffer_exists(net.reader_buffer)
			&& buffer_tell(net.reader_buffer) < buffer_get_size(net.reader_buffer))
			{
				sent_at = net.read(buffer_string);
			}

			/* Use the client message wrapper when present for session-aware reception.
			The compatibility alternative adds the message directly to chat */
			if (is_struct(packet_client)
			&& variable_struct_exists(packet_client, "add_received_chat_message"))
			{
				packet_client.add_received_chat_message(chat_type, sender_id, sender_name, content, sent_at);
			}

			/* Older clients without the wrapper still display the received message through
			the shared chat service */
			else
			{
				scr_get_chat().add_message(chat_type, sender_id, sender_name, content, sent_at);
			}
			break;

		/* layer_vote_drawing owns the current vote state and receives the server ballot
		or result through its canvas protocol handler */
		case N_LAYER_VOTE:
			var layer_vote_drawing = scr_get_drawing();

			/* Apply vote packets only when the canvas vote receiver exists.
			Otherwise leave voting state unchanged */
			if (is_struct(layer_vote_drawing)
			&& variable_struct_exists(layer_vote_drawing, "receive_layer_vote_packet"))
			{
				layer_vote_drawing.receive_layer_vote_packet();
			}
			break;

		/* typing_state interprets the nonzero wire flag, typing_name is the displayed
		player name and typing_chat owns its slot-indexed indicator. The header slot
		identifies whose typing state changes */
		case N_TYPING_STATE:
			var typing_state = net.read(buffer_u8) != 0;
			var typing_name = net.read(buffer_string);
			var typing_chat = scr_get_chat();
			typing_chat.set_typing_state(net.header.socketID, typing_name, typing_state);

			/* Verbose mode adds typing snapshots for diagnostics. Normal mode updates the
			indicator without injecting debug chat messages */
			if (scr_get_network().verbose)
			{
				/* typing_slot is the validated indicator slot for diagnostics.
				typing_state_text chooses ON for active typing and OFF otherwise */
				var typing_slot = typing_chat.typing_slot_from_value(net.header.socketID);
				var typing_state_text = typing_state ? "ON" : "OFF";
				typing_chat.add_message(CHAT_TYPE_SYSTEM, noone, "", "[debug] received typing " + typing_state_text + " from " + typing_name + " slot " + string(typing_slot));
				debug_log("[typing] " + typing_chat.typing_debug_snapshot());
			}
			break;

		/* afk_state interprets the nonzero wire flag, afk_name is the displayed player
		name and afk_chat owns the idle indicator indexed by the header logical slot */
		case N_AFK_STATE:
			var afk_state = net.read(buffer_u8) != 0;
			var afk_name = net.read(buffer_string);
			var afk_chat = scr_get_chat();
			afk_chat.set_afk_state(net.header.socketID, afk_name, afk_state);

			/* Verbose mode emits AFK diagnostics. Normal mode updates the idle indicator
			without adding debug-only chat text */
			if (scr_get_network().verbose)
			{
				/* afk_slot is the normalized indicator slot for diagnostics.
				afk_state_text chooses ON for idle state and OFF for activity */
				var afk_slot = afk_chat.typing_slot_from_value(net.header.socketID);
				var afk_state_text = afk_state ? "ON" : "OFF";
				afk_chat.add_message(CHAT_TYPE_SYSTEM, noone, "", "[debug] received AFK " + afk_state_text + " from " + afk_name + " slot " + string(afk_slot));
				debug_log("[afk] " + afk_chat.afk_debug_snapshot());
			}
			break;

		/* lifecycle_action selects countdown, reset or shutdown behavior.
		lifecycle_client owns the session-side application of those server lifecycle events */
		case N_SERVER_LIFECYCLE:
			var lifecycle_action = net.read(buffer_u8);
			var lifecycle_client = scr_get_client();

			/* Status packets update countdown state, reset packets archive/reset drawing,
			and shutdown packets archive before leaving. Unknown actions log an error */
			switch (lifecycle_action)
			{
				/* lifecycle_enabled is the reset policy flag, lifecycle_interval_minutes is
				the configured period and lifecycle_remaining_seconds is the current countdown */
				case SERVER_LIFECYCLE_STATUS:
					var lifecycle_enabled = net.read(buffer_u8) != 0;
					var lifecycle_interval_minutes = net.read(buffer_u16);
					var lifecycle_remaining_seconds = net.read(buffer_u32);

					/* Apply reset status only when the client status method exists.
					Missing support leaves its current displayed countdown unchanged */
					if (is_struct(lifecycle_client)
					&& variable_struct_exists(lifecycle_client, "apply_server_lifecycle_status"))
					{
						lifecycle_client.apply_server_lifecycle_status(lifecycle_enabled, lifecycle_interval_minutes, lifecycle_remaining_seconds);
					}
					break;

				/* lifecycle_reset_id identifies this reset event and lifecycle_reset_reason
				explains its cause to client archive/reset handling */
				case SERVER_LIFECYCLE_RESET_NOW:
					var lifecycle_reset_id = net.read(buffer_u32);
					var lifecycle_reset_reason = net.read(buffer_string);

					/* Handle the reset only when the client drawing-reset method exists.
					Without it this dispatcher does not reset canvas state */
					if (is_struct(lifecycle_client)
					&& variable_struct_exists(lifecycle_client, "handle_server_drawing_reset"))
					{
						lifecycle_client.handle_server_drawing_reset(lifecycle_reset_id, lifecycle_reset_reason);
					}
					break;

				/* lifecycle_shutdown_reason is the server explanation passed to client shutdown
				archive handling */
				case SERVER_LIFECYCLE_SHUTDOWN:
					var lifecycle_shutdown_reason = net.read(buffer_string);

					/* Archive shutdown state only through an available client handler.
					Missing support leaves shutdown handling to the remaining connection flow */
					if (is_struct(lifecycle_client)
					&& variable_struct_exists(lifecycle_client, "handle_server_shutdown_archive"))
					{
						lifecycle_client.handle_server_shutdown_archive(lifecycle_shutdown_reason);
					}
					break;

				/* Unknown lifecycle actions are logged and perform no reset or shutdown action */
				default:
					debug_error("Client received unknown server lifecycle action: " + string(lifecycle_action));
					break;
			}
			break;

		/* server_player_limit is the new unsigned gameplay capacity. player_limit_client
		owns the client status/UI copy, distinct from maximum socket storage */
		case N_SERVER_PLAYER_LIMIT:
			var server_player_limit = net.read(buffer_u16);
			var player_limit_client = scr_get_client();

			/* Apply the limit only through the available client setter.
			Missing support leaves its previous capacity display unchanged */
			if (is_struct(player_limit_client)
			&& variable_struct_exists(player_limit_client, "apply_server_player_limit"))
			{
				player_limit_client.apply_server_player_limit(server_player_limit);
			}
			break;

		/* latency_sequence matches a pending client probe. The following float fields
		report last/average/peak tick duration, maximum tick gap in milliseconds, tick rate
		in Hz and server FPS. latency_snapshot_interval_ms is the server broadcast period,
		latency_server_build identifies its build, and latency_client owns probe timing */
		case N_LATENCY_REPLY:
			var latency_sequence = net.read(buffer_u32);
			var latency_tick_last_ms = net.read(buffer_f32);
			var latency_tick_average_ms = net.read(buffer_f32);
			var latency_tick_peak_ms = net.read(buffer_f32);
			var latency_tick_rate_hz = net.read(buffer_f32);
			var latency_tick_max_gap_ms = net.read(buffer_f32);
			var latency_server_fps = net.read(buffer_f32);
			var latency_snapshot_interval_ms = net.read(buffer_u16);
			var latency_server_build = net.read(buffer_string);
			var latency_client = scr_get_client();

			/* An available latency receiver matches the sequence and calculates round-trip
			time. Without that capability the diagnostics remain unchanged */
			if (is_struct(latency_client)
			&& variable_struct_exists(latency_client, "receive_latency_reply"))
			{
				latency_client.receive_latency_reply(
					latency_sequence,
					latency_tick_last_ms,
					latency_tick_average_ms,
					latency_tick_peak_ms,
					latency_tick_rate_hz,
					latency_tick_max_gap_ms,
					latency_server_fps,
					latency_snapshot_interval_ms,
					latency_server_build
				);
			}
			break;

		/* movement_protocol_version and movement_send_interval_ms describe accepted
		client movement authority. movement_player resolves the existing local player */
		case N_CLIENT_PLAYER_STATE_ACK:
			var movement_protocol_version = net.read(buffer_u8);
			var movement_send_interval_ms = net.read(buffer_u16);
			var movement_player = player_controller_get_player(ID, false);

			/* Activate client authority only for an existing player with the handshake
			method, letting that method validate the received protocol and send interval */
			if (movement_player != noone
			&& variable_struct_exists(movement_player, "activate_client_movement_authority"))
			{
				movement_player.activate_client_movement_authority(movement_protocol_version, movement_send_interval_ms);
			}
			break;

		/* heartbeat_sequence is echoed to the server so it can keep this connection
		alive without confusing heartbeat traffic with gameplay input */
		case N_HEARTBEAT_PING:
			var heartbeat_sequence = net.read(buffer_u32);
			send_heartbeat_pong(heartbeat_sequence);
			break;

		/* The client log-transfer service owns decoding and assembling this admin
		export packet */
		case N_ADMIN_LOGS:
			packet_client.admin_logs.receive();
			break;

		/* Admin status fields carry protocol/version correlation, authentication and
		reset flags, reset interval in minutes, remaining seconds, player counts,
		restart flag and visible message. The client receiver validates and stores them */
		case N_ADMIN_STATUS:
			var admin_status_version = net.read(buffer_u8);
			var admin_status_request_id = net.read(buffer_u32);
			var admin_status_authenticated = net.read(buffer_u8);
			var admin_status_reset_enabled = net.read(buffer_u8);
			var admin_status_reset_interval = net.read(buffer_u16);
			var admin_status_reset_remaining = net.read(buffer_u32);
			var admin_status_connected = net.read(buffer_u16);
			var admin_status_max = net.read(buffer_u16);
			var admin_status_restarting = net.read(buffer_u8);
			var admin_status_message = net.read(buffer_string);

			/* Deliver status fields only when the client admin receiver exists.
			Unsupported clients leave admin UI state unchanged */
			if (is_struct(packet_client)
			&& variable_struct_exists(packet_client, "receive_admin_status"))
			{
				packet_client.receive_admin_status(
					admin_status_version,
					admin_status_request_id,
					admin_status_authenticated,
					admin_status_reset_enabled,
					admin_status_reset_interval,
					admin_status_reset_remaining,
					admin_status_connected,
					admin_status_max,
					admin_status_restarting,
					admin_status_message
				);
			}
			break;

		/* Admin result fields identify protocol, request, action, outcome code and
		visible response message. The client receiver matches them to its pending request */
		case N_ADMIN_RESULT:
			var admin_result_version = net.read(buffer_u8);
			var admin_result_request_id = net.read(buffer_u32);
			var admin_result_action = net.read(buffer_u8);
			var admin_result_code = net.read(buffer_u8);
			var admin_result_message = net.read(buffer_string);

			/* Apply the request outcome only when the client admin-result method exists.
			Missing support leaves its pending admin state unchanged */
			if (is_struct(packet_client)
			&& variable_struct_exists(packet_client, "receive_admin_result"))
			{
				packet_client.receive_admin_result(
					admin_result_version,
					admin_result_request_id,
					admin_result_action,
					admin_result_code,
					admin_result_message
				);
			}
			break;

		/* Unknown server packet types produce an error and apply no client action */
		default:
			debug_error("Client received unknown packet type: " + string(net.header.type));
			break;
	}
}
