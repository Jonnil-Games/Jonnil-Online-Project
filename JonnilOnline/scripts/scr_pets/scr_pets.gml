#macro Pets scr_get_pets()

/// @description Own independent pet equipment while sharing character packages, sprites and permissions
function scr_pets() constructor
{
	/* An empty profile.pet_key means no companion. Character selection remains in profile.character_key */
	selected_key = "";
	loaded_selection = false;
	settings_file = "client_settings.ini";

	/* Cosmetic following uses room pixels and current_time milliseconds.
	The bounded trail records the owner's route instead of steering through corners */
	follow_distance = 72;
	teleport_distance = 256;
	max_trail_points = 256;
	pet_size_ratio = 0.5;

	/// @description Return installed artwork choices with an empty first entry for putting the pet away
	/// @returns {Array} Local package keys, including bundled characters
	selectable_keys = function()
	{
		/* Discovery and ownership checks are shared with the player character library */
		var registry = scr_get_player_characters();
		registry.scan(false);
		var keys = [""];

		/* Remote session caches cannot be equipped until the permitted artwork is saved locally */
		for (var i = 0; i < array_length(registry.characters); i++)
		{
			var entry = registry.characters[i];
			if (registry.entry_is_selectable(entry))
			{
				array_push(keys, entry.key);
			}
		}
		return keys;
	}

	/// @description Restore pet equipment once, leaving it empty when the package no longer exists
	/// @returns {String} Installed local key or empty
	load_selected_key = function()
	{
		/* Repeated card and join requests reuse the selection already loaded this session */
		if (loaded_selection)
		{
			return selected_key;
		}
		loaded_selection = true;
		try
		{
			/* A new profile has no pet until the player chooses one */
			if (file_exists(settings_file))
			{
				ini_open(settings_file);
				selected_key = ini_read_string("profile", "pet_key", "");
				ini_close();
			}
		}
		catch(e)
		{
			debug_error("Could not load selected pet: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		/* A missing installation clears pet equipment without substituting a player character */
		if (selected_key != "")
		{
			var registry = scr_get_player_characters();
			registry.scan(false);
			var index = registry.find_index(selected_key);
			if (index == noone || !registry.entry_is_selectable(registry.characters[index]))
			{
				selected_key = "";
				registry.set_status("Saved pet is missing. Choose another pet.", make_color_rgb(255, 220, 95));
			}
			else
			{
				selected_key = registry.characters[index].key;
			}
		}
		return selected_key;
	}

	/// @description Apply saved equipment to the current local player without changing its character
	/// @returns {Bool} Whether the local player exists
	apply_selected_to_local_player = function()
	{
		var player = player_controller_get_player(scr_get_client().ID, false);
		if (player == noone)
		{
			return false;
		}
		var key = load_selected_key();
		var next_key = key == "" ? "" : scr_get_player_characters().network_key(key);

		/* Permission and attribution belong to this owner's advertised equipment.
		Identical image keys may be equipped by other owners with different metadata */
		player.pet_manifest = key == "" ? noone : scr_get_player_characters().manifest_for_key(key, false);

		/* Keep the current trail when equipment has not changed, including permission refreshes */
		if (player.pet_key != next_key)
		{
			player.pet_key = next_key;
			player.pet_follow_state = undefined;
		}
		return true;
	}

	/// @description Persist an installed pet or put it away, then update and optionally announce equipment
	/// @param {String} raw_key Local artwork key, or empty to put away
	/// @param {Bool} should_broadcast Whether to announce the change to multiplayer peers
	/// @returns {Bool} Whether the choice is valid and saved
	equip_local = function(raw_key, should_broadcast = true)
	{
		var registry = scr_get_player_characters();
		var next_key = string(raw_key);

		/* Only locally selectable artwork can become saved equipment */
		if (next_key != "")
		{
			registry.scan(false);
			var index = registry.find_index(next_key);
			if (index == noone || !registry.entry_is_selectable(registry.characters[index]))
			{
				registry.set_status("Save this artwork locally before using it as a pet.", make_color_rgb(255, 220, 95));
				return false;
			}
			next_key = registry.characters[index].key;
		}

		/* Save before replacing equipment so a settings failure leaves the previous choice intact */
		try
		{
			ini_open(settings_file);
			ini_write_string("profile", "pet_key", next_key);
			ini_close();
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
			registry.set_status("Could not save pet selection.", make_color_rgb(244, 84, 84));
			debug_error("Could not save selected pet: " + string(e.message));
			return false;
		}
		selected_key = next_key;
		loaded_selection = true;
		apply_selected_to_local_player();
		registry.set_status(next_key == "" ? "Pet put away." : "Selected pet: " + registry.display_name(next_key) + ".", make_color_rgb(126, 245, 150));

		/* Offline equipment stays local. The client helper skips sends without a multiplayer connection */
		if (should_broadcast)
		{
			scr_get_client().send_player_pet(next_key);
		}
		return true;
	}

	/// @description Cycle the shared artwork library while retaining a separate pet selection
	/// @param {Real} delta Negative for previous, positive for next
	select_relative = function(delta)
	{
		load_selected_key();
		var keys = selectable_keys();
		var current = 0;
		for (var i = 0; i < array_length(keys); i++)
		{
			if (keys[i] == selected_key) current = i;
		}
		var count = array_length(keys);
		var next = (current + (delta < 0 ? -1 : 1) + count) mod count;
		return equip_local(keys[next]);
	}

	/// @description Resolve the pet's shared artwork label or the empty-state label
	selected_display_name = function()
	{
		var key = load_selected_key();
		return key == "" ? "No pet" : scr_get_player_characters().display_name(key);
	}

	/// @description Format pet selection position, with zero identifying no pet
	selected_position_text = function()
	{
		load_selected_key();
		var keys = selectable_keys();
		var position = 0;
		for (var i = 1; i < array_length(keys); i++)
		{
			if (keys[i] == selected_key) position = i;
		}
		return string(position) + "/" + string(array_length(keys) - 1);
	}

	/// @description Test whether the pet artwork has editable local custom metadata
	selected_is_installed_custom = function()
	{
		var key = load_selected_key();
		return key != "" && scr_get_player_characters().is_installed_custom(key);
	}

	/// @description Read the shared artwork's copy permission
	selected_allow_clone = function()
	{
		var key = load_selected_key();
		return key != "" && scr_get_player_characters().allow_clone_for_key(key);
	}

	/// @description Change the artwork's copy permission and announce every equipped role using it
	toggle_selected_allow_clone = function()
	{
		var registry = scr_get_player_characters();
		var key = load_selected_key();
		if (key == "" || !registry.set_allow_clone_for_key(key, !selected_allow_clone(), true))
		{
			return false;
		}
		/* The shared setter announces every equipped role that uses this artwork */
		return true;
	}

	/// @description Apply received equipment to its owner, keeping image transfer in the character registry
	/// @param {Real} owner_id Assigned player slot
	/// @param {Struct|Real} manifest Existing character manifest, or noone for no pet
	receive_player_pet = function(owner_id, manifest)
	{
		var player = player_controller_get_player(owner_id, false);
		if (player == noone)
		{
			return false;
		}
		var next_key = "";
		player.pet_manifest = manifest;

		/* Put-away packets carry no manifest. Equipped artwork retains shared credits and permissions */
		if (is_struct(manifest))
		{
			var registry = scr_get_player_characters();
			registry.remember_manifest(manifest);
			next_key = manifest.network_key;
		}
		if (player.pet_key != next_key)
		{
			player.pet_key = next_key;
			player.pet_follow_state = undefined;
		}
		return true;
	}

	/// @description Advance a cosmetic companion along its owner's visible route and draw it at half size
	/// @param {Struct} player Visible owner whose interpolated position was already updated
	render_for_player = function(player)
	{
		/* Empty equipment allocates no trail or sprite */
		if (player.pet_key == "") return;
		var registry = scr_get_player_characters();
		var owner_x = registry.center_x(player.character_key, player.visual_pos.x, player.player_size);
		var owner_y = registry.bottom_y(player.character_key, player.visual_pos.y, player.player_size);
		var state = player.pet_follow_state;

		/* New artwork starts at its owner's feet. Large corrections reset the trail to avoid crossing the room */
		if (!is_struct(state) || state.key != player.pet_key
		|| point_distance(state.owner_x, state.owner_y, owner_x, owner_y) > teleport_distance)
		{
			state = { key: player.pet_key, x: owner_x, y: owner_y, owner_x: owner_x, owner_y: owner_y,
				trail: [], direction: player.facing_direction, moving: false, updated_at: current_time };
			player.pet_follow_state = state;
		}

		/* Retain each visible route segment. Subpixel movement accumulates until it is worth recording */
		if (point_distance(state.owner_x, state.owner_y, owner_x, owner_y) >= 2)
		{
			array_push(state.trail, { x: owner_x, y: owner_y });
			state.owner_x = owner_x;
			state.owner_y = owner_y;
		}

		/* A long stalled trail catches up to its oldest retained point and remains bounded */
		if (array_length(state.trail) > max_trail_points)
		{
			state.x = state.trail[0].x;
			state.y = state.trail[0].y;
			array_delete(state.trail, 0, 1);
		}

		/* Total queued distance sets the stopping gap. The pet consumes route segments in order */
		var route_length = 0;
		var route_x = state.x;
		var route_y = state.y;
		for (var i = 0; i < array_length(state.trail); i++)
		{
			var point = state.trail[i];
			route_length += point_distance(route_x, route_y, point.x, point.y);
			route_x = point.x;
			route_y = point.y;
		}

		/* Cap elapsed time after a stalled frame. Longer routes allow modest catch-up without instant jumps */
		var elapsed = clamp((current_time - state.updated_at) / 1000, 0, 0.05);
		state.updated_at = current_time;
		var travel = min(max(0, route_length - follow_distance), (player.movement_speed * 60 + max(0, route_length - 200)) * elapsed);
		state.moving = travel > 0.1;

		while (travel > 0 && array_length(state.trail) > 0)
		{
			var target = state.trail[0];
			var dx = target.x - state.x;
			var dy = target.y - state.y;
			var distance = point_distance(state.x, state.y, target.x, target.y);

			/* Completed segments are discarded. Partial travel follows this segment before visiting the next */
			if (distance <= travel)
			{
				state.x = target.x;
				state.y = target.y;
				travel -= distance;
				array_delete(state.trail, 0, 1);
			}
			else
			{
				state.x += dx * travel / distance;
				state.y += dy * travel / distance;
				travel = 0;
			}
			state.direction = player_character_direction_from_delta(dx, dy, state.direction);
		}
		registry.draw_character_at_bottom(player.pet_key, state.direction, state.moving, state.x, state.y, player.player_size * pet_size_ratio, c_white, 1);
	}

	/// @description Pick a visible follower using the same camera conversion as player-card hit testing
	/// @returns {Real} Owner slot, or noone when no follower contains the GUI point
	owner_at_gui_point = function(camera_id, point_x, point_y)
	{
		/* Invalid camera and canvas dimensions cannot map the pointer into the world */
		if (!is_real(camera_id) || camera_id < 0) return noone;
		var view_w = camera_get_view_width(camera_id);
		var view_h = camera_get_view_height(camera_id);
		var gui_w = display_get_gui_width();
		var gui_h = display_get_gui_height();
		if (view_w <= 0 || view_h <= 0 || gui_w <= 0 || gui_h <= 0) return noone;
		var world_x = camera_get_view_x(camera_id) + point_x * view_w / gui_w;
		var world_y = camera_get_view_y(camera_id) + point_y * view_h / gui_h;
		var players = scr_get_player_controller().players;
		var registry = scr_get_player_characters();

		/* Reverse render order resolves overlaps. A blocked owner hides both the player and companion */
		for (var i = array_length(players) - 1; i >= 0; i--)
		{
			var player = players[i];
			if (player == noone || !scr_get_social().player_visible(i) || player.pet_key == ""
			|| !is_struct(player.pet_follow_state)) continue;
			var state = player.pet_follow_state;
			var sheet = registry.metrics(player.pet_key);
			var scale = player.player_size * pet_size_ratio * sheet.scale_to_project_sprite;
			var left = state.x - sheet.frame_w * scale * 0.5;
			var top = state.y - sheet.frame_h * scale;
			if (world_x >= left && world_x <= left + sheet.frame_w * scale
			&& world_y >= top && world_y <= state.y) return i;
		}
		return noone;
	}
}

/// @description Return the shared pet equipment service without duplicating the artwork registry
function scr_get_pets()
{
	static pets = new scr_pets();
	return pets;
}
