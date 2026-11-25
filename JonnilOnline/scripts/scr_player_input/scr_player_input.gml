/* Movement action IDs index binding/held-state arrays and travel in the key-press
and key-release packets. Left/right/up/down keep wire values 0/1/2/3, while
PLAYER_INPUT_COUNT is the four-action array size and iteration bound, not a fifth
action. Preserve this order so client/server input agrees */
#macro PLAYER_INPUT_LEFT	0
#macro PLAYER_INPUT_RIGHT	1
#macro PLAYER_INPUT_UP		2
#macro PLAYER_INPUT_DOWN	3
#macro PLAYER_INPUT_COUNT	4

#region /* Input Bindings and Action Identifiers */
/// @description Return the shared WASD and arrow-key bindings indexed by PLAYER_INPUT_* actions. Callers should treat them as read-only
/// @returns {Array} Cached arrays of keyboard codes for each movement action
function scr_player_input_default_bindings()
{
	/* Cache the movement-key arrays across calls. undefined means the shared
	bindings have not been built yet, so the first request creates them */
	static bindings = undefined;

	/* Build the bindings only when the cache is unavailable.
	Keep one array per action, with WASD and the matching arrow key as alternatives */
	if (!is_array(bindings))
	{
		bindings = array_create(PLAYER_INPUT_COUNT);

		/* Each action's entry stores its two keyboard codes: A/left, D/right,
		W/up and S/down. All callers read these shared arrays in action-ID order */
		bindings[PLAYER_INPUT_LEFT] = [ord("A"), vk_left];
		bindings[PLAYER_INPUT_RIGHT] = [ord("D"), vk_right];
		bindings[PLAYER_INPUT_UP] = [ord("W"), vk_up];
		bindings[PLAYER_INPUT_DOWN] = [ord("S"), vk_down];
	}

	return bindings;
}

/// @description Return a movement action label for menus and diagnostics
/// @param {Real} action_id Movement action identifier
/// @returns {String} left, right, up, down, or unknown
function scr_player_input_action_name(action_id)
{
	/* Round down the numeric action code and translate the four defined
	movement directions to their labels. Other codes fall through to unknown */
	switch (floor(real(action_id)))
	{
		case PLAYER_INPUT_LEFT: return "left";
		case PLAYER_INPUT_RIGHT: return "right";
		case PLAYER_INPUT_UP: return "up";
		case PLAYER_INPUT_DOWN: return "down";
	}

	return "unknown";
}

/// @description Clamp a numeric movement action to the four action identifiers used by packets
/// @param {Real} action_id Numeric action to normalize
/// @returns {Real} Integer from zero through PLAYER_INPUT_COUNT - 1
function scr_player_input_action_code(action_id)
{
	/* Use a whole-number action inside the defined movement range.
	Out-of-range numeric codes choose the nearest endpoint rather than noone */
	return clamp(floor(real(action_id)), 0, PLAYER_INPUT_COUNT - 1);
}

/// @description Map a keyboard code through the shared movement bindings
/// @param {Real} key_code Keyboard code. undefined and noone are treated as unbound
/// @returns {Real} PLAYER_INPUT_* action, or noone when no binding matches
function scr_player_input_action_from_key(key_code)
{
	/* An absent key or noone is unbound, so return before numeric conversion.
	Supplied keys continue through the shared binding lookup */
	if (is_undefined(key_code)
	|| key_code == noone)
	{
		return noone;
	}

	/* Use a whole-number keyboard code and the cached movement bindings.
	clean_key is the lookup value, and bindings groups keys by movement action */
	var clean_key = floor(real(key_code));
	var bindings = scr_player_input_default_bindings();

	/* Search each zero-based movement action until one of its keys matches.
	action_index is also the action code returned for a successful lookup */
	for (var action_index = 0; action_index < PLAYER_INPUT_COUNT; action_index++)
	{
		/* Select this action's list of alternative keyboard codes */
		var keys = bindings[action_index];

		/* Check every alternative in the current action's list, starting at its
		first entry. A list without a match allows the outer search to continue */
		for (var key_index = 0; key_index < array_length(keys); key_index++)
		{
			/* Return this action on an exact key-code match so either binding can drive
			it. Otherwise keep searching the remaining keys and actions */
			if (keys[key_index] == clean_key)
			{
				return action_index;
			}
		}
	}

	/* No binding matched, so return the unbound sentinel rather than inventing
	a movement direction */
	return noone;
}

/// @description Accept current action identifiers and legacy keyboard-code movement packets
/// @param {Real} raw_value Packet movement value. Current identifiers take precedence over keyboard bindings
/// @returns {Real} Movement action, or noone for an unrecognized value
function scr_player_input_network_value_to_action(raw_value)
{
	/* Missing input and noone do not identify a movement action.
	Return noone so the server's press and release handlers ignore this value */
	if (is_undefined(raw_value)
	|| raw_value == noone)
	{
		return noone;
	}

	/* Both formats use whole-number codes. Keep the rounded-down packet value
	in clean_value so the action check and legacy key lookup use the same number */
	var clean_value = floor(real(raw_value));

	/* Current packets use 0 for left, 1 for right, 2 for up and 3 for down.
	Check both bounds before accepting the value directly so this format takes
	priority over the legacy keyboard-code lookup */
	if (clean_value >= 0
	&& clean_value < PLAYER_INPUT_COUNT)
	{
		return clean_value;
	}

	/* Values outside the action-ID range use the older keyboard-code format.
	The shared lookup accepts WASD and arrow keys, or returns noone when unbound */
	return scr_player_input_action_from_key(clean_value);
}
#endregion /* Input Bindings and Action Identifiers END */

#region /* Movement State and Network Sends */
/// @description Check whether any bound key for a movement action is held
/// @param {Real} action_id Numeric action, clamped to the valid action range
/// @returns {Bool} Whether a bound key is held
function scr_player_input_action_down(action_id)
{
	/* Normalize the requested action, then borrow its keys from the shared
	bindings. action_index selects the direction and keys lists its alternatives */
	var action_index = scr_player_input_action_code(action_id);
	var bindings = scr_player_input_default_bindings();
	var keys = bindings[action_index];

	/* Visit the bound keys from the first entry until one is held or the list
	ends. No match leaves this action released */
	for (var key_index = 0; key_index < array_length(keys); key_index++)
	{
		/* Read this alternative's keyboard code for the held-key check */
		var key_code = keys[key_index];

		/* Ignore the unbound-key sentinel before polling keyboard state.
		Either usable key being held activates the action, so stop on the first match */
		if (key_code != vk_nokey
		&& keyboard_check(key_code))
		{
			return true;
		}
	}

	return false;
}

/// @description Sample local keyboard input into the state shape stored by player data
/// @returns {Struct} left, right, up, and down values, each either zero or one
function scr_player_input_movement_state()
{
	/* Sample each direction independently into the player's numeric input shape.
	Each field starts at 1 for a held bound key or 0 for a released direction */
	return
	{
		left: scr_player_input_action_down(PLAYER_INPUT_LEFT) ? 1 : 0,
		right: scr_player_input_action_down(PLAYER_INPUT_RIGHT) ? 1 : 0,
		up: scr_player_input_action_down(PLAYER_INPUT_UP) ? 1 : 0,
		down: scr_player_input_action_down(PLAYER_INPUT_DOWN) ? 1 : 0
	};
}

/// @description Read a player movement action as zero or one
/// @param {Struct} player Player data with left, right, up, and down fields
/// @param {Real} action_id Numeric action, clamped to the valid action range
/// @returns {Real} Zero for an invalid player, otherwise the normalized action state
function scr_player_input_player_action_state(player, action_id)
{
	/* Without a player struct, report a released action instead of reading
	movement fields from an invalid value */
	if (!is_struct(player))
	{
		return 0;
	}

	/* Read the field selected by the normalized action. Each direction treats
	any nonzero stored state as held and returns 1, or returns 0 when released */
	switch (scr_player_input_action_code(action_id))
	{
		case PLAYER_INPUT_LEFT: return player.left != 0 ? 1 : 0;
		case PLAYER_INPUT_RIGHT: return player.right != 0 ? 1 : 0;
		case PLAYER_INPUT_UP: return player.up != 0 ? 1 : 0;
		case PLAYER_INPUT_DOWN: return player.down != 0 ? 1 : 0;
	}

	return 0;
}

/// @description Set one movement field on player data without moving the player
/// @param {Struct} player Player data to update
/// @param {Real} action_id Numeric action, clamped to the valid action range
/// @param {Bool} is_down Whether the movement action is held
/// @returns {Bool} Whether the player struct was updated
function scr_player_input_set_player_action_state(player, action_id, is_down)
{
	/* Only a player struct can receive a movement-field update.
	Return false for other values without trying to assign a field */
	if (!is_struct(player))
	{
		return false;
	}

	/* Convert the caller's held/released flag into the shared numeric 1/0
	representation before selecting which player field to update */
	var state_value = is_down ? 1 : 0;

	/* Update only the requested direction's field and report success.
	The normalized action chooses left, right, up or down without moving the player */
	switch (scr_player_input_action_code(action_id))
	{
		case PLAYER_INPUT_LEFT:
			player.left = state_value;
			return true;
		case PLAYER_INPUT_RIGHT:
			player.right = state_value;
			return true;
		case PLAYER_INPUT_UP:
			player.up = state_value;
			return true;
		case PLAYER_INPUT_DOWN:
			player.down = state_value;
			return true;
	}

	return false;
}

/// @description Send a press or release only when the normalized action state changes. Replaces the network writer packet
/// @param {Struct} net Network controller used to start, write, and send the packet
/// @param {Real} player_slot_id Player array slot used in the packet header, not an operating-system socket
/// @param {Real} action_id Movement action sent as one unsigned byte
/// @param {Real} old_state Previous action state. Any nonzero value means held
/// @param {Real} new_state New action state. Any nonzero value means held
/// @returns {Real} Zero when unchanged, otherwise the network send result. A negative value indicates failure
function scr_player_input_send_action_if_changed(net, player_slot_id, action_id, old_state, new_state)
{
	/* Normalize both previous and current states to 1 for held or 0 for released.
	old_value and new_value make equivalent nonzero inputs compare equally */
	var old_value = old_state != 0 ? 1 : 0;
	var new_value = new_state != 0 ? 1 : 0;

	/* Unchanged input needs no edge packet. Return zero so holding a key does
	not resend the same press on every update */
	if (old_value == new_value)
	{
		return 0;
	}

	/* Choose a press packet when the new action state is held and a release
	packet otherwise, then attach the player's logical slot and action code */
	var packet_type = new_value != 0 ? N_KEY_PRESS : N_KEY_RELEASE;
	net.start(packet_type, player_slot_id);
	net.write(buffer_u8, scr_player_input_action_code(action_id));
	return net.send_server();
}
#endregion /* Movement State and Network Sends END */
