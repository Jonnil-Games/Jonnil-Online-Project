/// @description Format a logical player-slot ID for network diagnostics
/// @param {Any} raw_slot Slot value to validate. undefined or noone means pending
/// @returns {String} ID followed by a non-negative integer, or IDpending
function scr_network_debug_id_text(raw_slot)
{
	/* An absent or noone slot has not received a logical player identity.
	Use the pending label rather than displaying a socket handle as a player ID */
	if (is_undefined(raw_slot)
	|| raw_slot == noone)
	{
		return "IDpending";
	}

	/* slot_value begins unresolved and receives a numeric conversion in try.
	A conversion exception returns the pending label without interrupting diagnostics */
	var slot_value = noone;
	try
	{
		slot_value = real(raw_slot);
	}
	catch(e)
	{
		return "IDpending";
	}

	/* slot_index is the whole-number candidate for this logical player slot.
	Comparing it with the original converted value detects fractional IDs */
	var slot_index = floor(slot_value);

	/* Only nonnegative whole numbers are displayable player IDs. Fractional or
	negative values retain the pending label rather than implying an assigned slot */
	if (slot_value != slot_index || slot_index < 0)
	{
		return "IDpending";
	}

	return "ID" + string(slot_index);
}

/// @description Append an optional username to the diagnostic player-slot label
/// @param {Any} raw_slot Logical player-slot value
/// @param {String} username Display name, defaulting to empty for an ID-only label. Whitespace is trimmed
/// @returns {String} Diagnostic identity label
function scr_network_debug_id_label(raw_slot, username = "")
{
	var label = scr_network_debug_id_text(raw_slot); /* Diagnostic slot text, with pending used for unassigned IDs */
	var clean_name = string_trim(string(username)); /* Visible username text with surrounding whitespace removed */

	/* Append a name only when trimming leaves visible text. Empty names keep the
	ID label readable without an empty pair of parentheses */
	if (clean_name != "")
	{
		label += "(" + clean_name + ")";
	}

	return label;
}

/// @description Describe the shared client using its assigned name or pending requested name
/// @returns {String} Client diagnostic identity, or IDpending before a client is available
function scr_network_debug_client_label()
{
	/* Borrow the shared client state used by connection diagnostics.
	The client owns its socket and assigned player identity */
	var client = scr_get_client();

	/* Before client state is available, diagnostics have no identity to inspect.
	Return the pending label instead of accessing unavailable fields */
	if (!is_struct(client))
	{
		return "IDpending";
	}

	/* Start without a displayed name. A nonempty server-assigned name takes
	priority, while the requested pre-join name is the compatibility fallback */
	var username = "";

	/* Use the assigned name only when its field exists and its trimmed text is
	nonempty, so a completed server identity replaces the requested name */
	if (variable_struct_exists(client, "assigned_username")
	&& string_trim(string(client.assigned_username)) != "")
	{
		username = string(client.assigned_username);
	}

	/* Without a usable assigned name, retain the requested name when that field
	exists. Otherwise the initially empty name leaves only the slot label */
	else if (variable_struct_exists(client, "requested_username"))
	{
		username = string(client.requested_username);
	}

	/* raw_slot uses the client logical ID when present. An older or incomplete
	client without that field is treated as pending rather than indexed */
	var raw_slot = variable_struct_exists(client, "ID") ? client.ID : noone;
	return scr_network_debug_id_label(raw_slot, username);
}

/// @description Describe a server slot with its name, socket, transport, character, and drawing author
/// @param {Any} raw_slot Logical server player-slot value
/// @returns {String} Available slot metadata, or the pending ID label
function scr_network_debug_server_slot_label(raw_slot)
{
	/* Borrow the server for validated logical-slot metadata. slot_index starts
	unresolved and is filled only through the server slot-normalization method */
	var server = scr_get_server();
	var slot_index = noone; /* Unresolved logical slot, pending server validation */

	/* Use server metadata only when the server exists and provides slot validation.
	Otherwise retain the unresolved slot and fall back to a basic ID label */
	if (is_struct(server)
	&& variable_struct_exists(server, "slot_from_value"))
	{
		slot_index = server.slot_from_value(raw_slot);
	}

	/* An invalid or unavailable server slot cannot safely index metadata arrays.
	Return the basic pending/ID formatting instead */
	if (slot_index == noone)
	{
		return scr_network_debug_id_text(raw_slot);
	}

	/* The slot label begins without a username. A matching entry in the server
	name array can provide it, while older server shapes keep the empty fallback */
	var username = "";

	/* Read the name only from an existing array containing this logical slot.
	These checks keep diagnostics compatible with incomplete server state */
	if (variable_struct_exists(server, "slot_usernames")
	&& is_array(server.slot_usernames)
	&& slot_index < array_length(server.slot_usernames))
	{
		username = string(server.slot_usernames[slot_index]);
	}

	/* label starts with the normalized player ID and optional name.
	The following guarded lookups append only metadata this server actually has */
	var label = scr_network_debug_id_label(slot_index, username);

	/* Append an actual socket handle only for an existing in-range array entry
	that is occupied. Empty slots keep the player label without a socket claim */
	if (variable_struct_exists(server, "sockets")
	&& is_array(server.sockets)
	&& slot_index < array_length(server.sockets)
	&& server.sockets[slot_index] != noone)
	{
		label += " socket=" + string(server.sockets[slot_index]);
	}

	/* Append a transport when the aligned slot array exists and contains this
	index. Missing transport state leaves the rest of the label usable */
	if (variable_struct_exists(server, "slot_transports")
	&& is_array(server.slot_transports)
	&& slot_index < array_length(server.slot_transports))
	{
		label += " transport=" + scr_get_network().transport_to_string(server.slot_transports[slot_index]);
	}

	/* Append the character key only for an existing in-range, nonempty entry.
	An unresolved character does not add an empty diagnostic field */
	if (variable_struct_exists(server, "slot_character_keys")
	&& is_array(server.slot_character_keys)
	&& slot_index < array_length(server.slot_character_keys)
	&& string(server.slot_character_keys[slot_index]) != "")
	{
		label += " character=" + string(server.slot_character_keys[slot_index]);
	}

	/* Positive drawing-author IDs identify a registered author. Append one only
	when the aligned array exists and its slot contains that assigned identity */
	if (variable_struct_exists(server, "slot_drawing_author_ids")
	&& is_array(server.slot_drawing_author_ids)
	&& slot_index < array_length(server.slot_drawing_author_ids)
	&& server.slot_drawing_author_ids[slot_index] > 0)
	{
		label += " author=" + string(server.slot_drawing_author_ids[slot_index]);
	}

	return label;
}

/// @description Describe every connected server socket slot for diagnostic logs
/// @returns {String} Comma-separated player identities, or the unavailable/empty-state label
function scr_network_debug_player_map()
{
	/* Read the shared server socket-slot array to build a connected-player map.
	These are logical array slots rather than socket IDs */
	var server = scr_get_server();

	/* An unavailable server or missing/nonarray socket storage cannot supply a
	player map. Return the unavailable label instead of attempting iteration */
	if (!is_struct(server)
	|| !variable_struct_exists(server, "sockets")
	|| !is_array(server.sockets))
	{
		return "players: server unavailable";
	}

	/* summary accumulates connected-player labels. Empty text initially means no
	occupied slot has contributed, which also controls comma placement */
	var summary = "";

	/* Visit every zero-based logical slot until the socket array ends. Empty slots
	are skipped, and each occupied slot contributes its diagnostic identity once */
	for (var slot_index = 0; slot_index < array_length(server.sockets); slot_index++)
	{
		/* An unoccupied slot has no connected player to describe. Skip it while
		keeping later occupied slots eligible for the map */
		if (server.sockets[slot_index] == noone)
		{
			continue;
		}

		/* Add a separator only after a player label already exists, avoiding a
		leading comma in the first entry */
		if (summary != "")
		{
			summary += ", ";
		}

		summary += scr_network_debug_server_slot_label(slot_index);
	}

	/* No occupied slot contributed a label. Report the explicit empty-state
	message rather than returning an unexplained blank player map */
	if (summary == "")
	{
		return "players: none connected";
	}

	return "players: " + summary;
}
