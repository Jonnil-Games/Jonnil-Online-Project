#macro Social scr_get_social()

/// @description Own local friend and block lists keyed by normalized usernames, plus GUI player-card state
function scr_social() constructor
{
	/* Client settings file owns local relationship persistence. friends_section and blocks_section
	keep the friend and block records in separate INI sections without changing other settings */
	settings_file = "client_settings.ini";
	friends_section = "social_friends";
	blocks_section = "social_blocks";

	/* friends and blocks start empty until load reads saved username-keyed records. loaded starts
	false so the first relationship access attempts restoration */
	friends = [];
	blocks = [];
	loaded = false;

	/* card_open starts false with no active card. card_player_id is noone until an online slot is
	chosen, or remains noone for a username-only card */
	card_open = false;
	card_player_id = noone;

	/* card_username stores a normalized relationship key and card_display_name its readable casing.
	Both start empty, as do the relationship status and hovered button key */
	card_username = "";
	card_display_name = "";
	card_status_text = "";
	card_hover_button = "";

	/* card_x and card_y begin at zero GUI pixels before update_card_layout centers the card. card_w
	and card_h start at nominal 340 by 430 GUI pixels and are recalculated for the current view and
	card type */
	card_x = 0;
	card_y = 0;
	card_w = 340;
	card_h = 430;

	/* card_buttons, block_list_rows and player_list_rows start empty. Layout builds button hit regions
	and the player-list renderer supplies row hit regions used by click handling */
	card_buttons = [];

	/* Pet Card has its own owner and layout. It uses the same artwork library and button drawing
	without turning the companion into the player's selected character */
	pet_card_open = false;
	pet_card_player_id = noone;
	pet_card_display_name = "";
	pet_card_hover_button = "";
	pet_card_buttons = [];
	pet_card_x = 0;
	pet_card_y = 0;
	pet_card_w = 360;
	pet_card_h = 660;
	pet_card_scale = 1; /* Uniform GUI scale keeps the full card inside short or narrow canvases */
	pet_card_focus = 0; /* Button index used by keyboard and controller navigation */
	pet_card_navigation = false;
	pet_card_pointer_x = 0;
	pet_card_pointer_y = 0;
	block_list_rows = [];
	player_list_rows = [];

	/* last_change_time starts zero before any relationship update and records current_time
	milliseconds when one occurs. player_card_hover_player_id starts noone until input hit testing
	finds a player */
	last_change_time = 0;
	player_card_hover_player_id = noone;

	#region /* Relationship Keys and Lists */
	/// @description Test an inclusive GUI or room-space rectangle using matching point coordinates
	/// @param {Real} point_x Horizontal point coordinate
	/// @param {Real} point_y Vertical point coordinate
	/// @param {Real} left_value Rectangle left edge
	/// @param {Real} top_value Rectangle top edge
	/// @param {Real} right_value Rectangle right edge
	/// @param {Real} bottom_value Rectangle bottom edge
	/// @returns {Bool} Whether both axes are inside or on the edges
	point_in_rect = function(point_x, point_y, left_value, top_value, right_value, bottom_value)
	{
		/* Include rectangle boundaries on both axes so a point on the visible button or row edge still
		counts as a hit */
		return point_x >= left_value
			&& point_x <= right_value
			&& point_y >= top_value
			&& point_y <= bottom_value;
	}

	/// @description Sanitize display text and make a lowercase relationship key
	/// @param {String} raw_username Unsanitized username
	/// @returns {String} Case-independent stored identity
	normalize_username = function(raw_username)
	{
		/* Sanitized readable username is converted to lowercase for stable relationship identity,
		keeping stored matches independent of display casing */
		var clean_name = chat_sanitize_username(raw_username);
		return string_lower(clean_name);
	}

	/// @description Sanitize a username while retaining readable display casing
	/// @param {String} raw_username Unsanitized username
	/// @returns {String} Display-safe username
	display_username = function(raw_username)
	{
		return chat_sanitize_username(raw_username);
	}

	/// @description Read the shared client's assigned player slot
	/// @returns {Real} Local slot ID, or noone when the client has no ID
	local_player_id = function()
	{
		/* Shared client supplies the currently assigned local player slot rather than a socket handle */
		var client = scr_get_client();

		/* Without a client struct and ID member, no local slot is available. Return noone so callers
		can distinguish unassigned identity */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID"))
		{
			return noone;
		}

		return client.ID;
	}

	/// @description Convert a slot value to a nonnegative integer without assuming player-array capacity
	/// @param {Real|String} raw_slot Candidate player slot
	/// @returns {Real} Integer slot, or noone for missing, nonnumeric, fractional or negative input
	slot_from_value = function(raw_slot)
	{
		/* Undefined and noone cannot name a player slot. Reject them before numeric conversion */
		if (is_undefined(raw_slot)
		|| raw_slot == noone)
		{
			return noone;
		}

		/* slot_value starts noone and receives real(raw_slot) only if conversion succeeds, keeping
		malformed input out of array indexing */
		var slot_value = noone;
		try
		{
			slot_value = real(raw_slot);
		}
		catch(e)
		{
			return noone;
		}

		/* Floored candidate index detects fractional IDs and supplies the returned zero-based slot
		number */
		var slot_index = floor(slot_value);

		/* Fractional and negative slot values are rejected. This helper does not enforce player-array
		capacity, which is checked by player_controller_get_player */
		if (slot_value != slot_index || slot_index < 0)
		{
			return noone;
		}

		return slot_index;
	}

	/// @description Resolve a current player's username through the controller's validated slot lookup
	/// @param {Real} raw_slot Candidate player slot
	/// @returns {String} Occupant's username, or empty text for missing player or username state
	player_username = function(raw_slot)
	{
		/* Validated nonnegative integer slot used to resolve the current occupant's username */
		var slot_index = slot_from_value(raw_slot);

		/* Unusable slot input has no username to expose, so return empty text */
		if (slot_index == noone)
		{
			return "";
		}

		/* Current player data is fetched through the controller's capacity checks, with invalid-slot
		logging disabled */
		var player = player_controller_get_player(slot_index, false);

		/* An empty or invalid player slot, or an occupant without username state, has no name to
		return */
		if (player == noone
		|| !variable_struct_exists(player, "username"))
		{
			return "";
		}

		return string(player.username);
	}

	/// @description Find a normalized username in a relationship list
	/// @param {Array} target_list Records containing name and display fields
	/// @param {String} raw_username Username to sanitize and match
	/// @returns {Real} Matching array index, or noone when absent
	list_index = function(target_list, raw_username)
	{
		/* Normalized target key makes the lookup independent of display casing */
		var key = normalize_username(raw_username);

		/* list_pos begins at zero and searches each saved relationship entry until a key matches or
		the list ends */
		for (var list_pos = 0; list_pos < array_length(target_list); list_pos++)
		{
			/* Current relationship record is checked before its normalized name key is accessed */
			var entry = target_list[list_pos];

			/* Only struct entries with a name equal to the target key are matches. Missing, malformed
			and unrelated entries continue the search */
			if (is_struct(entry)
			&& variable_struct_exists(entry, "name")
			&& entry.name == key)
			{
				return list_pos;
			}
		}

		return noone;
	}

	/// @description Test normalized username membership in a relationship list
	/// @param {Array} target_list Records containing normalized name keys
	/// @param {String} raw_username Username to match
	/// @returns {Bool} Whether a matching record exists
	list_contains = function(target_list, raw_username)
	{
		/* A list_index result other than noone means a normalized username is stored. This Boolean is
		reused by friendship and block decisions */
		return list_index(target_list, raw_username) != noone;
	}

	/// @description Delete the first matching relationship record or retain an unchanged list
	/// @param {Array} target_list Relationship records to update
	/// @param {String} raw_username Username to remove
	/// @returns {Array} Updated relationship list
	remove_from_list = function(target_list, raw_username)
	{
		/* Matching storage index identifies the one relationship record to remove */
		var remove_index = list_index(target_list, raw_username);

		/* Absent relationships return the supplied list unchanged, avoiding deletion at an invalid
		array index */
		if (remove_index == noone)
		{
			return target_list;
		}

		array_delete(target_list, remove_index, 1);
		return target_list;
	}

	/// @description Add or replace one normalized relationship while retaining its sanitized display name
	/// @param {Array} target_list Relationship records to update
	/// @param {String} raw_username Username to insert or refresh
	/// @returns {Array} Updated relationship list
	upsert_list = function(target_list, raw_username)
	{
		/* clean_display preserves sanitized display casing, clean_key is its lowercase identity and
		existing_index locates any current relationship with that identity */
		var clean_display = display_username(raw_username);
		var clean_key = normalize_username(clean_display);
		var existing_index = list_index(target_list, clean_key);

		/* Relationship records store name as the normalized matching key and display as the readable
		username shown in lists */
		var entry =
		{
			name: clean_key,
			display: clean_display
		};

		/* A username not already stored appends a new record rather than overwriting another
		relationship */
		if (existing_index == noone)
		{
			target_list[array_length(target_list)] = entry;
		}

		/* An existing normalized key is updated in place so display spelling stays current without
		duplicating the relationship */
		else
		{
			target_list[existing_index] = entry;
		}

		return target_list;
	}
	#endregion /* Relationship Keys and Lists END */

	#region /* Saved Relationships */
	/// @description Read indexed relationship records from an already open INI section
	/// @param {String} section_name INI section containing count, name_N and display_N
	/// @returns {Array} Nonblank saved identities and sanitized display names
	load_list_from_ini = function(section_name)
	{
		/* result starts empty and receives usable saved entries. item_count is the nonnegative integer
		count read from the open INI, defaulting to zero for older or absent sections */
		var result = [];
		var item_count = max(0, floor(ini_read_real(section_name, "count", 0)));

		/* item_index visits saved name_N and display_N entries from zero through count minus one */
		for (var item_index = 0; item_index < item_count; item_index++)
		{
			/* key is the saved matching identity. display uses its saved readable name or falls back
			to key when older records omit display_N */
			var key = string(ini_read_string(section_name, "name_" + string(item_index), ""));
			var display = string(ini_read_string(section_name, "display_" + string(item_index), key));

			/* Blank saved keys do not identify a relationship and are skipped before constructing a
			record */
			if (string_trim(key) == "")
			{
				continue;
			}

			/* display_name is sanitized for UI text and normalized is its lowercase form for
			comparison with the saved key */
			var display_name = display_username(display);
			var normalized = normalize_username(display_name);

			/* Retain records when display and key agree or the saved key is nonempty. The earlier
			blank-key guard makes the latter true for remaining entries, so this does not reject
			mismatched display names */
			if (normalized == key || string_trim(key) != "")
			{
				/* Loaded entries use the lowercased saved key as name and sanitized display_name as
				display, retaining historical saved identity rather than rebuilding it from display
				text */
				result[array_length(result)] =
				{
					name: string_lower(key),
					display: display_name
				};
			}
		}

		return result;
	}

	/// @description Write count and indexed relationship records into an already open INI section
	/// @param {String} section_name Destination relationship section
	/// @param {Array} target_list Records with name and display fields
	save_list_to_ini = function(section_name, target_list)
	{
		ini_write_real(section_name, "count", array_length(target_list));

		/* item_index starts at zero and writes each relationship under matching name_N and display_N
		indexes. The stored count limits subsequent reads even if old trailing INI keys remain */
		for (var item_index = 0; item_index < array_length(target_list); item_index++)
		{
			/* Current relationship record supplies both the matching name and readable display value
			to save */
			var entry = target_list[item_index];
			ini_write_string(section_name, "name_" + string(item_index), entry.name);
			ini_write_string(section_name, "display_" + string(item_index), entry.display);
		}
	}

	/// @description Attempt to restore relationships once from client_settings.ini. Missing files leave empty lists and failures are logged
	/// @returns {Bool} True after the load attempt, including a logged failure
	load = function()
	{
		/* Once loaded is set, reuse in-memory relationships rather than overwriting current changes
		with repeated disk reads */
		if (loaded)
		{
			return true;
		}

		loaded = true;
		try
		{
			/* Read saved lists only when the shared settings file exists. Missing files leave the
			starting empty lists available */
			if (file_exists(settings_file))
			{
				ini_open(settings_file);
				friends = load_list_from_ini(friends_section);
				blocks = load_list_from_ini(blocks_section);
				ini_close();
			}
		}
		catch(e)
		{
			debug_error("Could not load social settings: " + string(e.message));
		}

		return true;
	}

	/// @description Write the social_friends and social_blocks sections of the shared client settings file
	/// @returns {Bool} Whether writing the relationship lists succeeded
	save = function()
	{
		load();
		try
		{
			ini_open(settings_file);
			save_list_to_ini(friends_section, friends);
			save_list_to_ini(blocks_section, blocks);
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not save social settings: " + string(e.message));
			return false;
		}
	}
	#endregion /* Saved Relationships END */

	#region /* Relationship Updates and Visibility */
	/// @description Rebuild drawing history through the updated local visibility filter after a friend or block change
	notify_relationship_changed = function()
	{
		last_change_time = current_time;

		/* Shared drawing service can replay retained history through the new relationship visibility
		filter */
		var drawing = scr_get_drawing();

		/* When replay_client_history is available, rebuild visible drawing immediately after a
		relationship change. Otherwise retain the updated lists without a replay call */
		if (is_struct(drawing)
		&& variable_struct_exists(drawing, "replay_client_history"))
		{
			drawing.replay_client_history();
		}
	}

	/// @description Restore saved relationships if needed and test friendship by normalized username
	/// @param {String} raw_username Username to match
	/// @returns {Bool} Whether the username is in the local friend list
	is_friend_username = function(raw_username)
	{
		load();

		/* Normalized username membership in the loaded friends list determines this Boolean result for
		friend markers and card actions */
		return list_contains(friends, raw_username);
	}

	/// @description Restore saved relationships if needed and test blocking by normalized username
	/// @param {String} raw_username Username to match
	/// @returns {Bool} Whether the username is in the local block list
	is_blocked_username = function(raw_username)
	{
		load();

		/* Normalized username membership in the loaded blocks list determines this Boolean result for
		visibility and card actions */
		return list_contains(blocks, raw_username);
	}

	/// @description Resolve a slot's current username against local blocks while keeping the local player unblocked
	/// @param {Real} raw_slot Candidate player slot
	/// @returns {Bool} Whether this remote occupant's username is blocked
	is_blocked_slot = function(raw_slot)
	{
		/* Validated slot used to resolve a blocked username without treating raw input as an array
		index */
		var slot_index = slot_from_value(raw_slot);

		/* Invalid slot input is not considered blocked because it has no usable player identity */
		if (slot_index == noone)
		{
			return false;
		}

		/* Never hide the local player through the block filter, even if their username appears in a
		saved block record */
		if (slot_index == local_player_id())
		{
			return false;
		}

		/* A valid remote slot is blocked according to its occupant's current username, not according
		to a reusable slot number */
		return is_blocked_username(player_username(slot_index));
	}

	/// @description Resolve a remote slot's username against local friendship, excluding the local player
	/// @param {Real} raw_slot Candidate player slot
	/// @returns {Bool} Whether this remote occupant is a saved friend
	is_friend_slot = function(raw_slot)
	{
		/* Validated player slot used to query the friendship list */
		var slot_index = slot_from_value(raw_slot);

		/* Invalid input and the local player receive no friend marker. Only remote occupants are
		matched against saved usernames */
		if (slot_index == noone || slot_index == local_player_id())
		{
			return false;
		}

		/* Friendship follows the remote occupant's normalized username so the relationship remains
		meaningful when network slots change */
		return is_friend_username(player_username(slot_index));
	}

	/// @description Apply the local username block list to a network slot. The local player remains visible
	/// @param {Real} raw_slot Player array slot resolved to its current username
	/// @returns {Bool} Whether local rendering and chat should include the player
	player_visible = function(raw_slot)
	{
		/* A nonblocked slot is visible to local rendering and chat. The block check keeps the local
		player visible and treats unusable slots as unblocked */
		return !is_blocked_slot(raw_slot);
	}

	/// @description Remove any block, add friendship, attempt persistence and replay filtered drawing
	/// @param {String} raw_username Username to normalize and store
	/// @returns {Bool} True after in-memory changes, even when save reports a persistence failure
	add_friend = function(raw_username)
	{
		load();

		/* Sanitized display name is used consistently to remove any block and insert the friend record */
		var display_name = display_username(raw_username);
		blocks = remove_from_list(blocks, display_name);
		friends = upsert_list(friends, display_name);
		save();
		notify_relationship_changed();
		return true;
	}

	/// @description Remove friendship, attempt persistence and replay drawing after the relationship update
	/// @param {String} raw_username Username to remove
	/// @returns {Bool} True after in-memory changes, even when save reports a persistence failure
	remove_friend = function(raw_username)
	{
		load();
		friends = remove_from_list(friends, raw_username);
		save();
		notify_relationship_changed();
		return true;
	}

	/// @description Remove friendship, add the local block, attempt persistence, close the card, and replay filtered drawing history
	/// @param {String} raw_username Username to normalize through chat sanitization
	/// @returns {Bool} True after updating in-memory relationships. Persistence errors are reported by save
	block_player = function(raw_username)
	{
		load();

		/* Sanitized display name identifies the friendship to remove and the block record to add,
		avoiding contradictory in-memory relationship lists */
		var display_name = display_username(raw_username);
		friends = remove_from_list(friends, display_name);
		blocks = upsert_list(blocks, display_name);
		save();
		close_card();
		notify_relationship_changed();
		return true;
	}

	/// @description Remove a local block, attempt persistence and replay drawing with the new visibility filter
	/// @param {String} raw_username Username to unblock
	/// @returns {Bool} True after in-memory changes, even when save reports a persistence failure
	unblock_player = function(raw_username)
	{
		load();
		blocks = remove_from_list(blocks, raw_username);
		save();
		notify_relationship_changed();
		return true;
	}

	/// @description Restore saved relationships if needed and expose the local block records for UI rows
	/// @returns {Array} Current blocked-name records
	blocked_entries = function()
	{
		load();
		return blocks;
	}

	/// @description Choose the self, block or friend label in that priority order
	/// @param {Real} raw_slot Online player slot or noone for a name-only card
	/// @param {String} raw_username Username whose local relationship is displayed
	/// @returns {String} You, Blocked, Friend or empty text
	relationship_status = function(raw_slot, raw_username)
	{
		/* Validated slot used to distinguish a self card from username-based relationship status */
		var slot_index = slot_from_value(raw_slot);

		/* An assigned slot equal to the local ID takes the You label before block or friendship labels */
		if (slot_index != noone && slot_index == local_player_id())
		{
			return "You";
		}

		/* A stored block takes precedence over friendship for this username, matching its effect on
		local visibility */
		if (is_blocked_username(raw_username))
		{
			return "Blocked";
		}

		/* Without a block, a stored friendship returns Friend. Other names keep an empty relationship
		label */
		if (is_friend_username(raw_username))
		{
			return "Friend";
		}

		return "";
	}
	#endregion /* Relationship Updates and Visibility END */

	#region /* Player Cards and Hit Testing */
	/// @description Open a GUI player card and release held local movement before it captures input
	/// @param {Real} raw_slot Player array slot, or noone for a name-only card
	/// @param {String} raw_username Display username, default empty text resolved from the slot
	/// @returns {Bool} Whether a nonempty sanitized display name was available
	open_card = function(raw_slot, raw_username = "")
	{
		/* slot_index is a validated online slot or noone for a name-only card. display_name begins
		with caller text and can be filled from that slot */
		var slot_index = slot_from_value(raw_slot);
		var display_name = raw_username;

		/* Resolve an absent display name from the slot only when a slot is available. Explicit caller
		text remains authoritative for name-only cards */
		if (string_trim(string(display_name)) == "" && slot_index != noone)
		{
			display_name = player_username(slot_index);
		}

		display_name = display_username(display_name);

		/* After sanitization, a blank display name cannot identify a relationship. Leave the current
		card unchanged and report failure */
		if (string_trim(display_name) == "")
		{
			return false;
		}

		/* Shared client is used to release held movement before the card captures input */
		var movement_client = scr_get_client();

		/* Release local movement when the client exposes the hook, preventing keys held before opening
		the card from continuing to move the player */
		if (is_struct(movement_client)
		&& variable_struct_exists(movement_client, "release_local_movement"))
		{
			movement_client.release_local_movement();
		}

		card_player_id = slot_index;
		close_pet_card();
		card_username = normalize_username(display_name);
		card_display_name = display_name;
		card_status_text = relationship_status(slot_index, display_name);
		card_open = true;
		card_hover_button = "";
		return true;
	}

	/// @description Close either social card and clear identity, hover and generated hit regions
	close_card = function()
	{
		/* Mode changes and departure cleanup already use this entry point for social UI */
		close_pet_card();
		card_open = false;
		card_player_id = noone;
		card_username = "";
		card_display_name = "";
		card_status_text = "";
		card_hover_button = "";
		card_buttons = [];
	}

	/// @description Convert a player sprite and standard nameplate bounds from room coordinates into GUI pixels
	/// @param {Struct} player Player data with position, character, and scale information
	/// @param {Real} camera_id Camera used for the room-to-GUI conversion
	/// @returns {Struct} left, top, right, and bottom GUI coordinates, or noone when the view is invalid
	player_hit_rect_gui = function(player, camera_id)
	{
		/* An empty player or invalid camera cannot provide draw bounds for hit testing. Return noone
		before view access */
		if (player == noone
		|| !is_real(camera_id)
		|| camera_id < 0)
		{
			return noone;
		}

		/* view_left/top and view_width/height are camera room-pixel bounds. gui_width/height supply
		the GUI-pixel scale for returned hit coordinates */
		var view_left = camera_get_view_x(camera_id);
		var view_top = camera_get_view_y(camera_id);
		var view_width = camera_get_view_width(camera_id);
		var view_height = camera_get_view_height(camera_id);
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();

		/* Both the camera view and GUI canvas must have positive dimensions to support room-to-GUI
		conversion. Otherwise skip this hit rectangle */
		if (view_width <= 0 || view_height <= 0 || gui_width <= 0 || gui_height <= 0)
		{
			return noone;
		}

		/* Prefer visual_pos x/y so hits match the drawn interpolated sprite. Older player data without
		it uses pos. player_size_value uses its stored multiplier or the default 2.5 */
		var player_draw_x = variable_struct_exists(player, "visual_pos") ? player.visual_pos.x : player.pos.x;
		var player_draw_y = variable_struct_exists(player, "visual_pos") ? player.visual_pos.y : player.pos.y;
		var player_size_value = variable_struct_exists(player, "player_size") ? player.player_size : 2.5;

		/* hit_character_key uses the player's character when available or Player 1 otherwise.
		character supplies frame metrics and draw_scale includes both player size and source scaling */
		var hit_character_key = variable_struct_exists(player, "character_key") ? player.character_key : "player1";
		var character = scr_get_player_characters().metrics(hit_character_key);
		var draw_scale = player_size_value * character.scale_to_project_sprite;

		/* sprite_left/top/right/bottom are the drawn frame bounds in room pixels. sprite_center_x
		anchors the standard nameplate above that frame */
		var sprite_left = player_draw_x - character.xorigin * draw_scale;
		var sprite_top = player_character_top_y_key(hit_character_key, player_draw_y, player_size_value);
		var sprite_right = sprite_left + character.frame_w * draw_scale;
		var sprite_bottom = sprite_top + character.frame_h * draw_scale;
		var sprite_center_x = sprite_left + character.frame_w * draw_scale * 0.5;

		/* The standard nameplate is 116 by 22 room pixels with a ten-pixel sprite gap. plate_left/top
		place that label above the sprite */
		var nameplate_width = 116;
		var nameplate_height = 22;
		var nameplate_gap = 10;
		var plate_left = sprite_center_x - nameplate_width * 0.5;
		var plate_top = sprite_top - nameplate_gap - nameplate_height;

		/* hit_left/top/right/bottom combine the sprite and nameplate into one room-space rectangle so
		either visible area can open its card */
		var hit_left = min(sprite_left, plate_left);
		var hit_top = min(sprite_top, plate_top);
		var hit_right = max(sprite_right, plate_left + nameplate_width);
		var hit_bottom = max(sprite_bottom, plate_top + nameplate_height);

		/* Returned left, top, right and bottom subtract the view origin and scale into GUI pixels,
		matching device_mouse_to_gui input */
		return
		{
			left: (hit_left - view_left) * gui_width / view_width,
			top: (hit_top - view_top) * gui_height / view_height,
			right: (hit_right - view_left) * gui_width / view_width,
			bottom: (hit_bottom - view_top) * gui_height / view_height
		};
	}

	/// @description Pick the last-rendered visible player whose sprite or nameplate contains a GUI point
	/// @param {Real} camera_id Camera for room-to-GUI conversion
	/// @param {Real} point_x GUI horizontal pointer coordinate
	/// @param {Real} point_y GUI vertical pointer coordinate
	/// @returns {Real} Occupied player slot, or noone for a miss
	player_at_gui_point = function(camera_id, point_x, point_y)
	{
		/* Shared player controller provides the occupied slots for reverse-order hit testing */
		var controller = scr_get_player_controller();

		/* No usable players array means there are no safe entries to hit-test, so return noone */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			return noone;
		}

		/* player_index starts at the final slot and counts down through zero. Reverse order selects
		the last-rendered matching player first when sprites overlap */
		for (var player_index = array_length(controller.players) - 1; player_index >= 0; player_index--)
		{
			/* Current occupant in this player slot is inspected before its visual bounds are
			calculated */
			var player = controller.players[player_index];

			/* Empty slots and players hidden by the local block list cannot be card targets */
			if (player == noone || !player_visible(player_index))
			{
				continue;
			}

			/* GUI rectangle for this player's sprite and nameplate, or noone if camera or canvas state
			is invalid */
			var hit_rect = player_hit_rect_gui(player, camera_id);

			/* Return the first valid rectangle containing the GUI point. Misses continue toward
			earlier-rendered player slots */
			if (hit_rect != noone
			&& point_in_rect(point_x, point_y, hit_rect.left, hit_rect.top, hit_rect.right, hit_rect.bottom))
			{
				return player_index;
			}
		}

		return noone;
	}
	#endregion /* Player Cards and Hit Testing END */

	#region /* Player Card Input */
	/// @description Replace player-list hit regions supplied by the UI renderer
	/// @param {Array} rows GUI x1/y1/x2/y2 rectangles with slot_id and name, invalid input clears rows
	update_player_list_rows = function(rows)
	{
		/* Accept renderer-supplied player row hit regions only as an array. Invalid input clears stale
		regions so old rows cannot be clicked */
		player_list_rows = is_array(rows) ? rows : [];
	}

	/// @description Replace blocked-name hit regions supplied by the UI renderer
	/// @param {Array} rows GUI x1/y1/x2/y2 rectangles with name, invalid input clears rows
	update_block_list_rows = function(rows)
	{
		/* Accept renderer-supplied blocked-name rows only as an array. Invalid input clears stale
		unblock targets */
		block_list_rows = is_array(rows) ? rows : [];
	}

	/// @description Open a clicked player card or unblock a clicked blocked-name row
	/// @param {Real} point_x GUI horizontal click coordinate
	/// @param {Real} point_y GUI vertical click coordinate
	/// @returns {Bool} Whether a row handled the click
	handle_player_list_click = function(point_x, point_y)
	{
		/* row_index walks the visible player-list hit regions from zero until a hit opens a card or
		all rows are exhausted */
		for (var row_index = 0; row_index < array_length(player_list_rows); row_index++)
		{
			/* Current row stores x1/y1/x2/y2 GUI bounds, slot_id and display name used to open the
			selected player's card */
			var row = player_list_rows[row_index];

			/* A click within this row opens its player card and returns that operation's result,
			ending the row search */
			if (point_in_rect(point_x, point_y, row.x1, row.y1, row.x2, row.y2))
			{
				return open_card(row.slot_id, row.name);
			}
		}

		/* block_index visits stored block-list rows after no player row consumed the click */
		for (var block_index = 0; block_index < array_length(block_list_rows); block_index++)
		{
			/* Current blocked row supplies its GUI rectangle and username to remove from the local
			block list */
			var block_row = block_list_rows[block_index];

			/* Clicking a blocked-name row unblocks that username immediately and consumes the click.
			Other rows continue the search */
			if (point_in_rect(point_x, point_y, block_row.x1, block_row.y1, block_row.x2, block_row.y2))
			{
				unblock_player(block_row.name);
				return true;
			}
		}

		return false;
	}

	/// @description Resolve the saved local selection for a self card or the live occupant's remote character
	/// @returns {String} Preview character key, falling back to Player 1
	card_preview_character_key = function()
	{
		/* is_self requires an assigned card slot matching this client's ID, distinguishing local
		character selection from a remote preview */
		var is_self = card_player_id != noone && card_player_id == local_player_id();

		/* Shared registry supplies selected local characters and fallback character keys */
		var registry = scr_get_player_characters();

		/* The self card reloads and previews the saved local selection, allowing character changes
		before an online player is present */
		if (is_self)
		{
			registry.load_selected_key();
			return registry.selected_key;
		}

		/* Resolve preview_player only when the card has a slot. Name-only cards keep noone and fall
		through to the default character */
		var preview_player = card_player_id == noone ? noone : player_controller_get_player(card_player_id, false);

		/* An available player with a character_key supplies its current character for the preview.
		Missing data falls back to Player 1 */
		if (preview_player != noone
		&& variable_struct_exists(preview_player, "character_key"))
		{
			return preview_player.character_key;
		}

		return "player1";
	}

	/// @description Require a remote unblocked card and registry permission to save its downloaded character
	/// @returns {Bool} Whether this card can expose Save Character
	card_can_save_remote_character = function()
	{
		/* Name-only cards, self cards and blocked usernames cannot save remote artwork. Reject them
		before querying download and creator permission state */
		if (card_player_id == noone
		|| card_player_id == local_player_id()
		|| is_blocked_username(card_display_name))
		{
			return false;
		}

		/* The registry permits saving only when the preview's custom character has downloaded content
		and creator clone permission */
		return scr_get_player_characters().remote_character_save_available(card_preview_character_key());
	}

	/// @description Rebuild card geometry and buttons for local customization or remote relationship actions in current GUI pixels
	update_card_layout = function()
	{
		/* gui_width and gui_height are current canvas pixels. is_self chooses the taller local
		customization layout, registry provides selection data, show_clone_toggle requires an
		installed custom selection and can_save_remote determines whether a save action is shown */
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();
		var is_self = card_player_id != noone && card_player_id == local_player_id();
		var registry = scr_get_player_characters();
		var show_clone_toggle = is_self && registry.selected_is_installed_custom();
		var can_save_remote = card_can_save_remote_character();
		var can_open_pet = is_self || pet_key_for_player(card_player_id) != "";
		card_w = min(360, max(300, gui_width - 32));

		/* Self cards reserve customization space, eligible remote cards reserve an extra save row and
		ordinary remote cards use the shorter layout. Each height is bounded relative to the GUI
		canvas */
		card_h = is_self ? min(662, max(632, gui_height - 36)) : (can_save_remote ? min(474, max(430, gui_height - 36)) : min(430, max(390, gui_height - 36))) + (can_open_pet && !is_self ? 42 : 0);
		card_x = (gui_width - card_w) * 0.5;
		card_y = max(18, (gui_height - card_h) * 0.5);
		card_buttons = [];

		/* button_w/h define GUI-pixel action size and button_x/y its initial position. close_button_y
		anchors the final close row near the card bottom */
		var button_w = card_w - 52;
		var button_h = 34;
		var button_x = card_x + 26;
		var button_y = card_y + card_h - 154;
		var close_button_y = card_y + card_h - 48;

		/* button_index starts at zero and appends buttons in their drawing and hit-testing order as
		this layout is rebuilt */
		var button_index = 0;

		/* Self cards expose local character controls rather than friendship or blocking controls */
		if (is_self)
		{
			/* picker_y anchors customization rows above the close button and arrow_w gives each
			previous/next selection arrow its GUI width */
			var picker_y = card_y + card_h - 310;
			var arrow_w = 42;

			/* Each button record uses key for input routing and label for displayed text. x/y give its
			GUI-pixel top-left and w/h its size. All following records share this format */
			card_buttons[button_index++] =
			{
				key: "char_prev",
				label: "<",
				x: button_x,
				y: picker_y,
				w: arrow_w,
				h: button_h
			};
			card_buttons[button_index++] =
			{
				key: "char_next",
				label: ">",
				x: button_x + button_w - arrow_w,
				y: picker_y,
				w: arrow_w,
				h: button_h
			};

			/* half_gap separates side-by-side import and folder buttons. half_w splits their available
			width evenly and can_open_character_folder follows the desktop capability check */
			var half_gap = 8;
			var half_w = (button_w - half_gap) * 0.5;
			var can_open_character_folder = scr_desktop_folder_opening_is_enabled();
			card_buttons[button_index++] =
			{
				key: "character_import",
				label: "Import 48x76 PNG",
				x: button_x,
				y: picker_y + 42,

				/* When folder opening is available, import uses half the row beside that button. Other
				runtimes give import the full row width */
				w: can_open_character_folder ? half_w : button_w,
				h: button_h
			};

			/* Create a folder action only where desktop folder opening is supported. Browser cards
			retain the import action without a misleading folder control */
			if (can_open_character_folder)
			{
				card_buttons[button_index++] =
				{
					key: "character_folder",
					label: "Characters Folder",
					x: button_x + half_w + half_gap,
					y: picker_y + 42,
					w: half_w,
					h: button_h
				};
			}

			card_buttons[button_index++] =
			{
				key: "character_maker",
				label: "Character Maker",
				x: button_x,
				y: picker_y + 84,
				w: button_w,
				h: button_h
			};

			/* Installed custom selections expose creator clone permission. Official or unavailable
			selections omit this toggle */
			if (show_clone_toggle)
			{
				card_buttons[button_index++] =
				{
					key: "character_allow_clone",
					label: "Allow other players to save this character",
					x: button_x,
					y: picker_y + 126,
					w: button_w,
					h: button_h,

					/* toggle marks a checkbox-style button and checked reads the selected character's
					current clone permission so drawing reflects saved policy */
					toggle: true,
					checked: registry.selected_allow_clone()
				};
			}

			card_buttons[button_index++] =
			{
				key: "character_copy",
				label: "Copy Current",
				x: button_x,
				y: picker_y + 168,
				w: button_w,
				h: button_h
			};
			card_buttons[button_index++] =
			{
				key: "pet_card",
				label: "Pet Card",
				x: button_x,
				y: picker_y + 210,
				w: button_w,
				h: button_h
			};
		}

		/* Remote and name-only cards use relationship actions, with a save row included only when
		downloaded character permissions allow it */
		else
		{
			/* A savable remote character reserves three action rows above close. Other remote cards
			reserve the two relationship rows */
			button_y = close_button_y - (can_save_remote ? 126 : 84) - (can_open_pet ? 42 : 0);

			/* Only cards with a savable remote character receive Save Character. Its added row shifts
			the relationship actions downward */
			if (can_save_remote)
			{
				card_buttons[button_index++] =
				{
					key: "save_character",
					label: "Save Character",
					x: button_x,
					y: button_y,
					w: button_w,
					h: button_h
				};
				button_y += 42;
			}

			/* Remote owners expose a separate card only while a visible companion is active */
			if (can_open_pet)
			{
				card_buttons[button_index++] =
				{
					key: "pet_card",
					label: "Pet Card",
					x: button_x,
					y: button_y,
					w: button_w,
					h: button_h
				};
				button_y += 42;
			}

			/* friend_label chooses Remove Friend for an existing friendship and Add Friend otherwise,
			describing the action that clicking will perform */
			var friend_label = is_friend_username(card_display_name) ? "Remove Friend" : "Add Friend";
			card_buttons[button_index++] =
			{
				key: "friend",
				label: friend_label,
				x: button_x,
				y: button_y,
				w: button_w,
				h: button_h
			};

			/* block_label chooses Unblock for a stored block and Block otherwise, keeping action text
			aligned with current relationship state */
			var block_label = is_blocked_username(card_display_name) ? "Unblock" : "Block";
			card_buttons[button_index++] =
			{
				key: "block",
				label: block_label,
				x: button_x,
				y: button_y + 42,
				w: button_w,
				h: button_h
			};
		}

		card_buttons[button_index++] =
		{
			key: "close",
			label: "Close",
			x: button_x,
			y: close_button_y,
			w: button_w,
			h: button_h
		};
	}

	/// @description Update hover and consume open-card input, routing buttons or closing on dismissal
	/// @returns {Bool} True while the card handles input, including frames without a click
	handle_card_input = function()
	{
		update_card_layout();

		/* point_x and point_y read the mouse in GUI pixels so button tests match the card layout */
		var point_x = device_mouse_x_to_gui(0);
		var point_y = device_mouse_y_to_gui(0);
		card_hover_button = "";

		/* button_index starts at zero and searches generated buttons until the first containing
		rectangle or the end of the array */
		for (var button_index = 0; button_index < array_length(card_buttons); button_index++)
		{
			/* Current button record contains its routing key and GUI dimensions */
			var button = card_buttons[button_index];

			/* The first hovered button supplies card_hover_button and ends the search, keeping drawing
			and click routing on one target */
			if (point_in_rect(point_x, point_y, button.x, button.y, button.x + button.w, button.y + button.h))
			{
				card_hover_button = button.key;
				break;
			}
		}

		/* Escape or a right click closes the card and consumes this input, preventing it from reaching
		gameplay */
		if (keyboard_check_pressed(vk_escape)
		|| mouse_check_button_pressed(mb_right))
		{
			close_card();
			return true;
		}

		/* Only a newly pressed left button activates actions. With no click, the open card still
		consumes input while hover state updates */
		if (mouse_check_button_pressed(mb_left))
		{
			/* Companion management uses a distinct card and retains this owner's identity */
			if (card_hover_button == "pet_card")
			{
				open_pet_card(card_player_id);
				return true;
			}

			/* The friend action toggles the saved relationship for this displayed username, then
			refreshes its card status */
			if (card_hover_button == "friend")
			{
				/* Existing friends are removed so the button acts as Remove Friend */
				if (is_friend_username(card_display_name))
				{
					remove_friend(card_display_name);
				}

				/* Other usernames are added as friends, also removing any conflicting local block
				through add_friend */
				else
				{
					add_friend(card_display_name);
				}
				card_status_text = relationship_status(card_player_id, card_display_name);
				return true;
			}

			/* The block action toggles visibility policy for the card's username and consumes the
			click */
			if (card_hover_button == "block")
			{
				/* A stored block is removed and the remaining relationship status is refreshed */
				if (is_blocked_username(card_display_name))
				{
					unblock_player(card_display_name);
					card_status_text = relationship_status(card_player_id, card_display_name);
				}

				/* An unblocked username is newly blocked, which also closes its card and replays
				filtered drawing history */
				else
				{
					block_player(card_display_name);
				}
				return true;
			}

			/* Save Character forwards the preview key to the registry's permission and installation
			checks, leaving the card available afterward */
			if (card_hover_button == "save_character")
			{
				scr_get_player_characters().save_remote_character(card_preview_character_key());
				return true;
			}

			/* is_self is recalculated against the current local ID so customization actions cannot be
			applied through another player's card */
			var is_self = card_player_id != noone && card_player_id == local_player_id();

			/* The previous-character action requires a self card and steps one selection backward */
			if (is_self && card_hover_button == "char_prev")
			{
				scr_get_player_characters().select_relative(-1);
				return true;
			}

			/* The next-character action also requires a self card and advances one selection */
			if (is_self && card_hover_button == "char_next")
			{
				scr_get_player_characters().select_relative(1);
				return true;
			}

			/* Only the self card can start importing a local character PNG */
			if (is_self && card_hover_button == "character_import")
			{
				scr_get_player_characters().import_png_from_dialog();
				return true;
			}

			/* Opening the character folder is a local customization action and requires the self card */
			if (is_self && card_hover_button == "character_folder")
			{
				scr_get_player_characters().open_custom_folder();
				return true;
			}

			/* The self card can hand input to Character Maker. Close the social card after opening the
			editor so both panels do not own the same click stream */
			if (is_self && card_hover_button == "character_maker")
			{
				scr_get_character_maker().open_start();
				close_card();
				return true;
			}

			/* The creator clone toggle applies only to the local selected character on a self card */
			if (is_self && card_hover_button == "character_allow_clone")
			{
				scr_get_player_characters().toggle_selected_allow_clone();
				return true;
			}

			/* Copy Current creates a custom copy of the local selected character through the self card */
			if (is_self && card_hover_button == "character_copy")
			{
				scr_get_player_characters().copy_selected_to_custom();
				return true;
			}

			/* Close or a click outside the card dismisses it and consumes that click. Other clicks
			inside the open card remain consumed without performing an action */
			if (card_hover_button == "close"
			|| !point_in_rect(point_x, point_y, card_x, card_y, card_x + card_w, card_y + card_h))
			{
				close_card();
				return true;
			}

			return true;
		}

		return true;
	}

	/// @description Respect drawing, stamp and character editor input ownership before social interactions
	/// @returns {Bool} Whether another tool or editor currently blocks player cards
	player_card_interactions_blocked = function()
	{
		/* Shared drawing service can claim the mouse for tools before social cards handle it */
		var drawing_manager = scr_get_drawing();

		/* A drawing service exposing blocks_player_cards and returning true owns this interaction.
		Stop checking other services once it blocks cards */
		if (is_struct(drawing_manager)
		&& variable_struct_exists(drawing_manager, "blocks_player_cards")
		&& drawing_manager.blocks_player_cards())
		{
			return true;
		}

		/* Shared stamp service reports whether stamp placement or a panel has input priority */
		var stamp_manager = scr_get_stamps();

		/* When the stamp service exposes a blocking member that reports ownership, it prevents social
		interaction. Otherwise continue to the character editor check */
		if (is_struct(stamp_manager)
			&& variable_struct_exists(stamp_manager, "blocks_player_cards")
			&& stamp_manager.blocks_player_cards())
		{
			return true;
		}

		/* Shared Character Maker service is the final input-owner check */
		var character_manager = scr_get_character_maker();

		/* Cards are blocked when a character editor struct exposes blocks_game_input and it returns
		true. Missing editor capability leaves social interaction available */
		return is_struct(character_manager)
			&& variable_struct_exists(character_manager, "blocks_game_input")
			&& character_manager.blocks_game_input();
	}

	/// @description Allow a world highlight only for the current valid hover while cards and other tools are idle
	/// @param {Real} raw_slot Candidate player slot
	/// @returns {Bool} Whether this player can show the social hover highlight
	player_card_hovered = function(raw_slot)
	{
		/* Validated player slot is compared with the current hover target before choosing whether to
		render a highlight */
		var slot_index = slot_from_value(raw_slot);

		/* Invalid slots, nonhovered slots and an already open card suppress world-player highlighting */
		if (slot_index == noone
		|| slot_index != player_card_hover_player_id
		|| card_open || pet_card_open)
		{
			return false;
		}

		/* Even a matching hover remains unhighlighted while drawing, stamps or the character editor
		own the interaction */
		return !player_card_interactions_blocked();
	}

	/// @description Poll pending character imports, then handle player cards when drawing, stamp, and character editor input ownership permits
	/// @param {Real} camera_id Camera used to hit-test room players in GUI coordinates
	/// @returns {Bool} Whether the social card or player-list interaction consumed input
	update_client_input = function(camera_id)
	{
		load();
		scr_get_player_characters().update_browser_import();
		player_card_hover_player_id = noone;

		/* Tool and editor input ownership takes priority over social cards. Release any active card
		and report input unconsumed so its owner can handle it */
		if (player_card_interactions_blocked())
		{
			/* Close a card only when one is open, clearing stale card controls when another UI takes
			input ownership */
			if (card_open)
			{
				close_card();
			}
			close_pet_card();

			return false;
		}

		/* An open card handles hover and actions exclusively. World and player-list picking wait until
		it closes */
		if (pet_card_open)
		{
			return handle_pet_card_input();
		}

		if (card_open)
		{
			return handle_card_input();
		}

		/* tab_held records whether the player list is visible so clicks can follow its row bounds
		rather than world-sprite hit regions */
		var tab_held = keyboard_check(vk_tab);

		/* A left press while Tab is held tests list rows and unblock rows. Other frames leave these
		list interactions idle */
		if (tab_held && mouse_check_button_pressed(mb_left))
		{
			/* tab_x and tab_y are this click's GUI-pixel position used by renderer-supplied list hit
			regions */
			var tab_x = device_mouse_x_to_gui(0);
			var tab_y = device_mouse_y_to_gui(0);

			/* A list click that opens a card or unblocks a name is consumed immediately. Misses
			continue to the remaining input checks */
			if (handle_player_list_click(tab_x, tab_y))
			{
				return true;
			}
		}

		/* Only without Tab does the mouse hover and pick world players, preventing clicks on a visible
		list from also opening an underlying sprite card */
		if (!tab_held)
		{
			/* point_x and point_y are GUI-pixel mouse coordinates for this frame's world-player hit
			test */
			var point_x = device_mouse_x_to_gui(0);
			var point_y = device_mouse_y_to_gui(0);
			player_card_hover_player_id = player_at_gui_point(camera_id, point_x, point_y);

			/* A new left press opens a card only when hit testing found a visible occupied slot. Empty
			world clicks leave gameplay input available */
			if (mouse_check_button_pressed(mb_left)
			&& player_card_hover_player_id != noone)
			{
				open_card(player_card_hover_player_id, player_username(player_card_hover_player_id));
				return true;
			}

			/* Players win overlapping hit tests. A companion can open its own card on an otherwise
			unclaimed world click */
			if (mouse_check_button_pressed(mb_left) && player_card_hover_player_id == noone)
			{
				var pet_owner_id = scr_get_pets().owner_at_gui_point(camera_id, point_x, point_y);
				if (pet_owner_id != noone)
				{
					return open_pet_card(pet_owner_id);
				}
			}
		}

		return false;
	}
	#endregion /* Player Card Input END */

	#region /* Pet Cards */
	/// @description Resolve independently equipped companion artwork for a local or remote owner
	/// @param {Real} raw_slot Companion owner's player slot
	/// @returns {String} Artwork key, or empty text when the owner has no visible pet
	pet_key_for_player = function(raw_slot)
	{
		/* Local equipment is saved separately from player character selection */
		if (raw_slot != noone && raw_slot == local_player_id())
		{
			return scr_get_pets().load_selected_key();
		}

		/* Remote equipment follows its current occupied slot and respects the same local block list */
		var player = raw_slot == noone ? noone : player_controller_get_player(raw_slot, false);
		if (player == noone || !variable_struct_exists(player, "pet_key")
		|| is_blocked_username(player.username))
		{
			return "";
		}
		return string(player.pet_key);
	}

	/// @description Read this owner's pet metadata instead of another owner's shared PNG cache metadata
	/// @param {Real} raw_slot Companion owner's player slot
	/// @returns {Struct|Real} Matching owner manifest, or noone when no current metadata is available
	pet_manifest_for_player = function(raw_slot)
	{
		var key = pet_key_for_player(raw_slot);
		if (key == "")
		{
			return noone;
		}
		if (raw_slot == local_player_id())
		{
			return scr_get_player_characters().manifest_for_key(key, false);
		}

		/* Remote equipment retains its own permissions and attribution even with identical image bytes */
		var player = player_controller_get_player(raw_slot, false);
		if (player == noone || !variable_struct_exists(player, "pet_manifest")
		|| !is_struct(player.pet_manifest)
		|| !variable_struct_exists(player.pet_manifest, "network_key")
		|| player.pet_manifest.network_key != key)
		{
			return noone;
		}
		return player.pet_manifest;
	}

	/// @description Release held movement and open a separate card for one player's companion
	/// @param {Real} raw_slot Companion owner's player slot
	/// @returns {Bool} Whether an occupied, visible owner could be opened
	open_pet_card = function(raw_slot)
	{
		/* The owner's slot and readable identity remain separate from the pet artwork key */
		var owner_id = slot_from_value(raw_slot);
		var owner_name = display_username(player_username(owner_id));
		if (owner_id == noone || owner_name == ""
		|| (owner_id != local_player_id() && pet_key_for_player(owner_id) == ""))
		{
			return false;
		}

		close_card();
		scr_get_chat().close();
		scr_get_client().release_local_movement();
		pet_card_player_id = owner_id;
		pet_card_display_name = owner_name;
		pet_card_open = true;
		pet_card_hover_button = "";
		pet_card_focus = 0;
		pet_card_navigation = false;
		pet_card_pointer_x = device_mouse_x_to_gui(0);
		pet_card_pointer_y = device_mouse_y_to_gui(0);
		return true;
	}

	/// @description Clear companion-card identity and button state without changing equipped artwork
	close_pet_card = function()
	{
		pet_card_open = false;
		pet_card_player_id = noone;
		pet_card_display_name = "";
		pet_card_hover_button = "";
		pet_card_buttons = [];
	}

	/// @description Keep gameplay input captured by either card
	/// @returns {Bool} Whether Player Card or Pet Card is open
	blocks_game_input = function()
	{
		return card_open || pet_card_open;
	}

	/// @description Build companion controls with the same spacing and button records as Player Card
	update_pet_card_layout = function()
	{
		/* Local cards reserve shared-library controls. Remote cards show artwork save and owner links */
		var is_self = pet_card_player_id == local_player_id();
		var pets = scr_get_pets();
		var registry = scr_get_player_characters();
		var key = pet_key_for_player(pet_card_player_id);
		var base_height = is_self ? 662 : 430;
		pet_card_scale = max(0.1, min(1, (display_get_gui_width() - 32) / 360, (display_get_gui_height() - 36) / base_height));
		var ui_scale = pet_card_scale;
		pet_card_w = 360 * ui_scale;
		pet_card_h = base_height * ui_scale;
		pet_card_x = (display_get_gui_width() - pet_card_w) * 0.5;
		pet_card_y = max(18, (display_get_gui_height() - pet_card_h) * 0.5);
		pet_card_buttons = [];

		/* Button geometry uses GUI pixels and each appended record is shared by input and drawing */
		var button_x = pet_card_x + 26 * ui_scale;
		var button_w = pet_card_w - 52 * ui_scale;
		var button_h = 34 * ui_scale;
		var button_y = pet_card_y + pet_card_h - 352 * ui_scale;
		var button_index = 0;
		if (is_self)
		{
			pet_card_buttons[button_index++] = { key: "pet_prev", label: "<", x: button_x, y: button_y, w: 42 * ui_scale, h: button_h };
			pet_card_buttons[button_index++] = { key: "pet_next", label: ">", x: button_x + button_w - 42 * ui_scale, y: button_y, w: 42 * ui_scale, h: button_h };

			/* Folder access keeps the platform check used by character import */
			var can_open_folder = scr_desktop_folder_opening_is_enabled();
			var half_w = (button_w - 8 * ui_scale) * 0.5;
			pet_card_buttons[button_index++] = { key: "pet_import", label: "Import 48x76 PNG", x: button_x, y: button_y + 42 * ui_scale, w: can_open_folder ? half_w : button_w, h: button_h };
			if (can_open_folder)
			{
				pet_card_buttons[button_index++] = { key: "pet_folder", label: "Artwork Folder", x: button_x + half_w + 8 * ui_scale, y: button_y + 42 * ui_scale, w: half_w, h: button_h };
			}
			pet_card_buttons[button_index++] = { key: "pet_maker", label: "Pet Maker", x: button_x, y: button_y + 84 * ui_scale, w: button_w, h: button_h };

			/* Saving permission belongs to the shared artwork package, including when used in both roles */
			if (pets.selected_is_installed_custom())
			{
				pet_card_buttons[button_index++] = { key: "pet_allow_clone", label: "Allow other players to save this artwork", x: button_x, y: button_y + 126 * ui_scale, w: button_w, h: button_h, toggle: true, checked: pets.selected_allow_clone() };
			}

			/* A removed pet has no artwork to copy or unequip. Import and creating a blank stay available */
			if (key != "")
			{
				pet_card_buttons[button_index++] = { key: "pet_copy", label: "Copy Current", x: button_x, y: button_y + 168 * ui_scale, w: button_w, h: button_h };
				pet_card_buttons[button_index++] = { key: "pet_remove", label: "Put Pet Away", x: button_x, y: button_y + 210 * ui_scale, w: button_w, h: button_h };
			}
		}
		else
		{
			/* Completed remote artwork can be saved only when its original creator allows it */
			if (registry.remote_character_save_available(key, pet_manifest_for_player(pet_card_player_id)))
			{
				pet_card_buttons[button_index++] = { key: "pet_save", label: "Save Pet Artwork", x: button_x, y: pet_card_y + pet_card_h - 142 * ui_scale, w: button_w, h: button_h };
			}
		}

		pet_card_buttons[button_index++] = { key: "player_card", label: "Player Card", x: button_x, y: pet_card_y + pet_card_h - 100 * ui_scale, w: button_w, h: button_h };
		pet_card_buttons[button_index++] = { key: "close", label: "Close", x: button_x, y: pet_card_y + pet_card_h - 48 * ui_scale, w: button_w, h: button_h };

		/* Button rendering reads the same uniform scale as layout and hit testing */
		for (var scale_index = 0; scale_index < array_length(pet_card_buttons); scale_index++)
		{
			pet_card_buttons[scale_index].ui_scale = ui_scale;
		}
	}

	/// @description Consume companion-card input and route equipment changes through shared artwork tools
	/// @returns {Bool} True while the Pet Card owns input
	handle_pet_card_input = function()
	{
		/* A disconnected owner, replaced slot or removed remote companion cannot retain a stale card */
		var is_self = pet_card_player_id == local_player_id();
		if (normalize_username(player_username(pet_card_player_id)) != normalize_username(pet_card_display_name)
		|| (!is_self && pet_key_for_player(pet_card_player_id) == ""))
		{
			close_pet_card();
			return true;
		}

		update_pet_card_layout();
		var point_x = device_mouse_x_to_gui(0);
		var point_y = device_mouse_y_to_gui(0);
		var pad_connected = gamepad_is_connected(0);
		var back_pressed = keyboard_check_pressed(vk_escape) || mouse_check_button_pressed(mb_right)
			|| (pad_connected && gamepad_button_check_pressed(0, gp_face2));
		if (back_pressed)
		{
			close_pet_card();
			return true;
		}

		/* Mouse motion returns control to the pointer. Arrow keys and D-pad navigate every action */
		if (point_x != pet_card_pointer_x || point_y != pet_card_pointer_y)
		{
			pet_card_navigation = false;
		}
		pet_card_pointer_x = point_x;
		pet_card_pointer_y = point_y;
		var previous_pressed = keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_left)
			|| (pad_connected && (gamepad_button_check_pressed(0, gp_padu) || gamepad_button_check_pressed(0, gp_padl)));
		var next_pressed = keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_right)
			|| (pad_connected && (gamepad_button_check_pressed(0, gp_padd) || gamepad_button_check_pressed(0, gp_padr)));
		var button_count = array_length(pet_card_buttons);
		if (previous_pressed || next_pressed)
		{
			pet_card_focus = (pet_card_focus + (previous_pressed ? -1 : 1) + button_count) mod button_count;
			pet_card_navigation = true;
		}
		pet_card_focus = clamp(pet_card_focus, 0, button_count - 1);
		pet_card_hover_button = pet_card_navigation ? pet_card_buttons[pet_card_focus].key : "";
		if (!pet_card_navigation)
		{
			for (var button_index = 0; button_index < button_count; button_index++)
			{
				var button = pet_card_buttons[button_index];
				if (point_in_rect(point_x, point_y, button.x, button.y, button.x + button.w, button.y + button.h))
				{
					pet_card_hover_button = button.key;
					pet_card_focus = button_index;
					break;
				}
			}
		}

		/* Enter and the primary controller button activate the same focused actions as mouse clicks */
		var clicked = mouse_check_button_pressed(mb_left);
		var accepted = keyboard_check_pressed(vk_enter)
			|| (pad_connected && gamepad_button_check_pressed(0, gp_face1));
		if (!clicked && !accepted)
		{
			return true;
		}
		if (accepted)
		{
			pet_card_hover_button = pet_card_buttons[pet_card_focus].key;
			pet_card_navigation = true;
		}

		var pets = scr_get_pets();
		var registry = scr_get_player_characters();
		var key = pet_key_for_player(pet_card_player_id);
		if (is_self)
		{
			/* Shared-library operations target only independent companion equipment */
			switch (pet_card_hover_button)
			{
				case "pet_prev": pets.select_relative(-1); return true;
				case "pet_next": pets.select_relative(1); return true;
				case "pet_import": registry.import_png_from_dialog("pet"); return true;
				case "pet_folder": registry.open_custom_folder(); return true;
				case "pet_maker":
					scr_get_character_maker().open_start("pet", key);
					close_pet_card();
					return true;
				case "pet_allow_clone": pets.toggle_selected_allow_clone(); return true;
				case "pet_copy":
					if (registry.copy_key_to_custom(key, false))
					{
						pets.equip_local(registry.last_saved_key);
					}
					return true;
				case "pet_remove": pets.equip_local(""); return true;
			}
		}
		else if (pet_card_hover_button == "pet_save")
		{
			registry.save_remote_character(key, pet_manifest_for_player(pet_card_player_id));
			return true;
		}

		/* Returning to the owner keeps Player Card and Pet Card distinct */
		if (pet_card_hover_button == "player_card")
		{
			open_card(pet_card_player_id, pet_card_display_name);
			return true;
		}
		if (pet_card_hover_button == "close"
		|| (clicked && !point_in_rect(point_x, point_y, pet_card_x, pet_card_y, pet_card_x + pet_card_w, pet_card_y + pet_card_h)))
		{
			close_pet_card();
		}
		return true;
	}

	/// @description Draw a companion preview and independent controls using Player Card's appearance
	draw_pet_card = function()
	{
		update_pet_card_layout();
		var is_self = pet_card_player_id == local_player_id();
		var pets = scr_get_pets();
		var registry = scr_get_player_characters();
		var key = pet_key_for_player(pet_card_player_id);
		var owner_manifest = pet_manifest_for_player(pet_card_player_id);
		var center_x = pet_card_x + pet_card_w * 0.5;
		var ui_scale = pet_card_scale;
		var text_width = pet_card_w - 44 * ui_scale;
		var picker_y = pet_card_y + pet_card_h - 352 * ui_scale;
		draw_set_alpha(0.34);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
		draw_set_alpha(0.96);
		draw_set_colour(make_color_rgb(22, 24, 28));
		draw_roundrect_ext(pet_card_x, pet_card_y, pet_card_x + pet_card_w, pet_card_y + pet_card_h, 8, 8, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_roundrect_ext(pet_card_x, pet_card_y, pet_card_x + pet_card_w, pet_card_y + pet_card_h, 8, 8, true);
		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(center_x, pet_card_y + 22 * ui_scale, "Pet Card", 28 * ui_scale, text_width);
		scr_render_text(center_x, pet_card_y + 60 * ui_scale, key == "" ? "No Pet" : (is_struct(owner_manifest) ? owner_manifest.display_label : registry.display_name(key)), 18 * ui_scale, text_width);
		draw_set_colour(make_color_rgb(178, 178, 184));
		scr_render_text(center_x, pet_card_y + 86 * ui_scale, "Owner: " + pet_card_display_name, 16 * ui_scale, text_width);

		/* Pet previews use the same frame-grid drawing at half the player preview size */
		var preview_bottom = is_self ? picker_y - 78 * ui_scale : pet_card_y + 232 * ui_scale;
		if (key != "")
		{
			draw_set_alpha(0.55);
			draw_set_colour(make_color_rgb(8, 9, 10));
			draw_ellipse(center_x - 34 * ui_scale, preview_bottom - 6 * ui_scale, center_x + 34 * ui_scale, preview_bottom + 6 * ui_scale, false);
			draw_set_alpha(1);
			registry.draw_character_at_bottom(key, PLAYER_DIRECTION_DOWN, false, center_x, preview_bottom, 1.55 * ui_scale, c_white, 1);
			var manifest = owner_manifest;
			if (is_struct(manifest) && variable_struct_exists(manifest, "original_creator_name")
			&& string_trim(manifest.original_creator_name) != "")
			{
				draw_set_colour(make_color_rgb(178, 178, 184));
				scr_render_text(center_x, pet_card_y + 112 * ui_scale, "Artwork by " + manifest.original_creator_name, 13 * ui_scale, text_width);
			}
		}
		else
		{
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(center_x, preview_bottom - 36 * ui_scale, "Choose or draw a companion below.", 16 * ui_scale, text_width);
		}

		if (is_self)
		{
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(center_x, picker_y - 18 * ui_scale, "Shared character artwork, 48x76 PNG", 13 * ui_scale, text_width);
			draw_set_colour(c_white);
			scr_render_text(center_x, picker_y + 8 * ui_scale, pets.selected_display_name(), 18 * ui_scale, pet_card_w - 150 * ui_scale);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(center_x, picker_y + 27 * ui_scale, pets.selected_position_text(), 12 * ui_scale, pet_card_w - 150 * ui_scale);
			if (registry.status_text != "" && current_time <= registry.status_until)
			{
				draw_set_colour(registry.status_colour);
				scr_render_text(center_x, picker_y - 46 * ui_scale, registry.status_text, 15 * ui_scale, text_width);
			}
		}
		else
		{
			/* Transfer feedback takes priority over the shared artwork's permanent-save permission */
			var remote_status = registry.remote_character_status(key);
			if (remote_status == "")
			{
				remote_status = registry.remote_character_save_status(key, owner_manifest);
			}
			draw_set_colour(make_color_rgb(255, 220, 95));
			scr_render_text(center_x, pet_card_y + 250 * ui_scale, remote_status, 14 * ui_scale, text_width);
		}

		draw_set_halign(fa_left);
		for (var button_index = 0; button_index < array_length(pet_card_buttons); button_index++)
		{
			social_draw_button(pet_card_buttons[button_index], pet_card_hover_button);
		}
		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	#endregion /* Pet Cards END */

	#region /* Social Rendering */
	/// @description Draw a green room-space marker under a visible remote friend's character
	/// @param {Struct} player Occupied player data with identity, position and character metrics
	draw_friend_marker = function(player)
	{
		/* Only valid player data with an ID recognized as a remote friend gets a marker. Missing
		identity, local players and nonfriends skip this draw operation */
		if (player == noone
		|| !variable_struct_exists(player, "ID")
		|| !is_friend_slot(player.ID))
		{
			return;
		}

		/* draw_x/y use interpolated visual_pos when available and pos otherwise. player_size_value
		takes the player's draw multiplier or default 2.5 for older data */
		var draw_x = variable_struct_exists(player, "visual_pos") ? player.visual_pos.x : player.pos.x;
		var draw_y = variable_struct_exists(player, "visual_pos") ? player.visual_pos.y : player.pos.y;
		var player_size_value = variable_struct_exists(player, "player_size") ? player.player_size : 2.5;

		/* marker_character_key chooses the player's character or Player 1. character supplies source
		metrics and draw_scale combines them with the player multiplier */
		var marker_character_key = variable_struct_exists(player, "character_key") ? player.character_key : "player1";
		var character = scr_get_player_characters().metrics(marker_character_key);
		var draw_scale = player_size_value * character.scale_to_project_sprite;

		/* marker_x centers the marker under the frame and marker_y is two room pixels above its
		bottom. marker_w/h size the ellipse from frame dimensions with visible minimum sizes */
		var marker_x = player_character_center_x_key(marker_character_key, draw_x, player_size_value);
		var marker_y = player_character_bottom_y_key(marker_character_key, draw_y, player_size_value) - 2;
		var marker_w = max(54, character.frame_w * draw_scale * 0.72);
		var marker_h = max(13, character.frame_h * draw_scale * 0.15);
		draw_set_alpha(0.22);
		draw_set_colour(make_color_rgb(0, 205, 75));
		draw_ellipse(marker_x - marker_w * 0.5, marker_y - marker_h * 0.5, marker_x + marker_w * 0.5, marker_y + marker_h * 0.5, false);
		draw_set_alpha(0.18);
		draw_set_colour(make_color_rgb(0, 255, 95));
		draw_ellipse(marker_x - marker_w * 0.62, marker_y - marker_h * 0.68, marker_x + marker_w * 0.62, marker_y + marker_h * 0.68, false);
		draw_set_alpha(0.86);
		draw_set_colour(make_color_rgb(0, 235, 86));
		draw_ellipse(marker_x - marker_w * 0.5, marker_y - marker_h * 0.5, marker_x + marker_w * 0.5, marker_y + marker_h * 0.5, true);
		draw_set_alpha(1);
	}

	/// @description Draw one GUI card action or checkbox using current hover and checked state
	/// @param {Struct} button Layout record with key, label, x, y, w and h, plus optional toggle and checked
	/// @param {String} hovered_key Optional card hover key, defaulting to Player Card hover
	social_draw_button = function(button, hovered_key = undefined)
	{
		/* hovered compares this button's routing key with the mouse target selected by
		handle_card_input */
		var hovered = button.key == (is_undefined(hovered_key) ? card_hover_button : hovered_key);
		var ui_scale = variable_struct_exists(button, "ui_scale") ? button.ui_scale : 1;

		/* Toggle-marked buttons draw their own checkbox and text inside the shared menu background.
		Ordinary actions use the standard labeled menu button below */
		if (variable_struct_exists(button, "toggle") && button.toggle)
		{
			scr_draw_menu_button(button.x, button.y, button.w, button.h, "", hovered, false, true, false, false, 1);

			/* box_size is an 18-GUI-pixel checkbox. box_x/y position it with ten pixels of left
			padding and center it vertically in the button */
			var box_size = 18 * ui_scale;
			var box_x = button.x + 10 * ui_scale;
			var box_y = button.y + (button.h - box_size) * 0.5;
			draw_set_colour(make_color_rgb(18, 20, 24));
			draw_rectangle(box_x, box_y, box_x + box_size, box_y + box_size, false);
			draw_set_colour(make_color_rgb(220, 220, 224));
			draw_rectangle(box_x, box_y, box_x + box_size, box_y + box_size, true);

			/* A present true checked field draws the green tick. Missing or false checked state leaves
			the box empty */
			if (variable_struct_exists(button, "checked") && button.checked)
			{
				draw_set_colour(make_color_rgb(126, 245, 150));
				draw_line_width(box_x + 4 * ui_scale, box_y + 10 * ui_scale, box_x + 8 * ui_scale, box_y + 14 * ui_scale, 2 * ui_scale);
				draw_line_width(box_x + 8 * ui_scale, box_y + 14 * ui_scale, box_x + 15 * ui_scale, box_y + 4 * ui_scale, 2 * ui_scale);
			}

			draw_set_halign(fa_left);
			draw_set_colour(c_white);
			scr_render_text(button.x + 36 * ui_scale, button.y + 8 * ui_scale, button.label, 16 * ui_scale, button.w - 46 * ui_scale);
			return;
		}

		scr_draw_menu_button(button.x, button.y, button.w, button.h, button.label, hovered, false, true, false, false, 18 * ui_scale);
	}

	/// @description Draw the open GUI card, live character preview, relationship status and generated action buttons
	draw_card = function()
	{
		/* Existing GUI composition draws the separate Pet Card through this shared entry point */
		if (pet_card_open)
		{
			draw_pet_card();
			return;
		}

		/* A closed card draws nothing, avoiding stale card state covering the game */
		if (!card_open)
		{
			return;
		}

		update_card_layout();
		card_status_text = relationship_status(card_player_id, card_display_name);

		/* is_self distinguishes customization text from remote relationship information. registry
		supplies selection, remote download status and character metrics */
		var is_self = card_player_id != noone && card_player_id == local_player_id();
		var registry = scr_get_player_characters();
		registry.load_selected_key();

		draw_set_alpha(0.34);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);

		draw_set_alpha(0.96);
		draw_set_colour(make_color_rgb(22, 24, 28));
		draw_roundrect_ext(card_x, card_y, card_x + card_w, card_y + card_h, 8, 8, false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(112, 116, 124));
		draw_roundrect_ext(card_x, card_y, card_x + card_w, card_y + card_h, 8, 8, true);

		draw_set_halign(fa_center);
		draw_set_colour(c_white);
		scr_render_text(card_x + card_w * 0.5, card_y + 22, card_display_name, 28, card_w - 44);
		draw_set_colour(make_color_rgb(178, 178, 184));

		/* A card without an assigned slot displays IDpending. Other cards format the debug player ID
		for the identity line */
		var id_text = card_player_id == noone ? "IDpending" : scr_network_debug_id_text(card_player_id);
		scr_render_text(card_x + card_w * 0.5, card_y + 58, id_text, 18, card_w - 44);

		/* preview_direction starts facing down and preview_moving starts idle for name-only or empty
		slots. preview_key resolves the character and preview_player is looked up only when a slot
		is assigned */
		var preview_direction = PLAYER_DIRECTION_DOWN;
		var preview_moving = false;
		var preview_key = card_preview_character_key();
		var preview_player = card_player_id == noone ? noone : player_controller_get_player(card_player_id, false);

		/* An available occupant replaces fallback animation with its current facing and walking state,
		making the card preview follow the live player */
		if (preview_player != noone)
		{
			preview_direction = preview_player.facing_direction;
			preview_moving = preview_player.is_moving;
		}

		/* character_label is the readable registry name and missing_character marks unavailable
		artwork for warning coloration */
		var character_label = registry.display_name(preview_key);
		var missing_character = registry.is_missing(preview_key);

		/* Remote cards show the player's character and transfer status. Self cards instead draw local
		selection information below */
		if (!is_self)
		{
			/* Missing remote artwork uses a yellow label warning. Available artwork uses the ordinary
			muted text color */
			draw_set_colour(missing_character ? make_color_rgb(255, 220, 95) : make_color_rgb(178, 178, 184));
			scr_render_text(card_x + card_w * 0.5, card_y + 82, character_label, 16, card_w - 44);

			/* Remote download status is checked before clone/save status so an unfinished transfer
			takes priority in the displayed message */
			var remote_status = registry.remote_character_status(preview_key);

			/* Without a download-status message, use the registry's save-status explanation instead */
			if (remote_status == "")
			{
				remote_status = registry.remote_character_save_status(preview_key);
			}

			/* Only nonempty remote status needs a text row. Empty status leaves the preview area
			uncluttered */
			if (remote_status != "")
			{
				/* Unavailable custom characters use a red error accent. Other pending or permission
				messages use yellow */
				draw_set_colour(remote_status == "Custom character unavailable" ? make_color_rgb(244, 84, 84) : make_color_rgb(255, 220, 95));
				scr_render_text(card_x + card_w * 0.5, card_y + 102, remote_status, 14, card_w - 44);
			}
		}

		/* status_label uses Player when no relationship label is stored. status_y reserves the larger
		self-card customization area or positions the remote relationship line according to button
		count */
		var status_label = card_status_text == "" ? "Player" : card_status_text;
		var status_y = is_self ? card_y + card_h - 380 : (array_length(card_buttons) > 1 ? card_y + 250 : card_y + 258);

		/* preview_x centers the sprite horizontally and preview_project_scale enlarges it for the
		card. character and character_draw_scale resolve the actual selected sheet size */
		var preview_x = card_x + card_w * 0.5;
		var preview_project_scale = 3.1;
		var character = registry.metrics(preview_key);
		var character_draw_scale = preview_project_scale * character.scale_to_project_sprite;

		/* character_w is the preview's GUI-pixel width and character_bottom_y anchors it above status.
		shadow_w has a minimum visible width and shadow_y lies one pixel above that anchor */
		var character_w = character.frame_w * character_draw_scale;
		var character_bottom_y = status_y - 16;
		var shadow_w = max(68, character_w * 1.12);
		var shadow_y = character_bottom_y - 1;

		draw_set_alpha(0.55);
		draw_set_colour(make_color_rgb(8, 9, 10));
		draw_ellipse(preview_x - shadow_w * 0.5, shadow_y - 7, preview_x + shadow_w * 0.5, shadow_y + 7, false);
		draw_set_alpha(1);

		registry.draw_character_at_bottom(preview_key, preview_direction, preview_moving, preview_x, character_bottom_y, preview_project_scale, c_white, 1);

		/* Friend status is green and Blocked status red. Other relationship labels use ordinary light
		gray so visual emphasis follows local policy */
		draw_set_colour(card_status_text == "Friend" ? make_color_rgb(94, 215, 122) : (card_status_text == "Blocked" ? make_color_rgb(244, 84, 84) : make_color_rgb(210, 210, 214)));
		scr_render_text(card_x + card_w * 0.5, status_y, status_label, 20, card_w - 44);
		draw_set_halign(fa_left);

		/* Only the self card draws selection controls and local character import/status information */
		if (is_self)
		{
			/* GUI-pixel picker row matches update_card_layout so text and the previous/next buttons
			share an anchor */
			var picker_y = card_y + card_h - 310;
			draw_set_halign(fa_center);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(card_x + card_w * 0.5, picker_y - 18, "48x76 PNG sheet, 3x4 frames, 16x19 each", 13, card_w - 44);
			draw_set_colour(c_white);
			scr_render_text(card_x + card_w * 0.5, picker_y + 8, registry.selected_display_name(), 18, card_w - 150);
			draw_set_colour(make_color_rgb(178, 178, 184));
			scr_render_text(card_x + card_w * 0.5, picker_y + 27, registry.selected_position_text(), 12, card_w - 150);

			/* Show registry feedback only while its nonempty message has not expired on the
			current_time millisecond clock. Old feedback is left out of the card */
			if (string_trim(registry.status_text) != "" && current_time <= registry.status_until)
			{
				draw_set_colour(registry.status_colour);
				scr_render_text(card_x + card_w * 0.5, picker_y - 38, registry.status_text, 15, card_w - 44);
			}
			draw_set_halign(fa_left);
		}

		/* button_index visits every current layout button from zero to the end so its draw order
		matches hit testing */
		for (var button_index = 0; button_index < array_length(card_buttons); button_index++)
		{
			social_draw_button(card_buttons[button_index]);
		}

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	#endregion /* Social Rendering END */

}

/// @description Return the shared local social manager
/// @returns {Struct} Lazily constructed social manager
function scr_get_social()
{
	/* Construct the local social manager once and retain its lists and card state for later calls */
	static social = new scr_social();
	return social;
}
