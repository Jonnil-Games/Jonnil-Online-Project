#macro PlayerController scr_get_player_controller()
#macro COLLISION_OBJECT_BALL 0

/* Wall movement and ball contact share a fixed room-pixel circle. Facing, animation and cosmetic
sprite scale do not change its radius */
#macro PLAYER_COLLISION_RADIUS 38

/// @description Own player structs indexed by network slot. Empty slots contain noone
function scr_player_controller() constructor
{
	/* Shared network configuration determines how many player slots the controller allocates */
	var net = scr_get_network();

	/* Fallback slot capacity is ten players until a valid network max_clients setting replaces it */
	var player_count = 10;

	/* Use the configured positive capacity only when the network struct exposes it. Otherwise retain
	the fallback so the player array can still be created */
	if (is_struct(net)
	&& variable_struct_exists(net, "max_clients")
	&& net.max_clients > 0)
	{
		player_count = floor(net.max_clients);
	}

	/* Slot indices match network player IDs.
	noone marks an unoccupied slot */
	players = array_create(player_count, noone);

	/// @description Replace a valid player slot with newly constructed identity and movement data
	/// @param {Real} socket_id Integer slot in players
	/// @param {Real} x Initial horizontal room position in pixels
	/// @param {Real} y Initial vertical room position in pixels
	/// @param {String} username Display name, empty defaults to Player
	/// @param {String} character_key Character key, empty defaults to Player 1
	/// @returns {Struct|Real} New player data, or noone for an invalid slot
	make_player = function(socket_id, x, y, username = "", character_key = "")
	{
		/* Reject invalid slot IDs before indexing players. Existing occupants in a valid slot are
		replaced by the newly constructed player */
		if (verify_socket(socket_id))
		{
			return noone;
		}

		/* socket_index is the validated integer player slot. p owns that slot's new movement, identity
		and drawing state from the supplied spawn position */
		var socket_index = floor(socket_id);
		var p = new scr_player_data(socket_index, x, y, username, character_key);
		players[socket_index] = p;

		/* Restore independently saved pet equipment only for the assigned local slot */
		if (scr_get_client().ID == socket_index)
		{
			scr_get_pets().apply_selected_to_local_player();
		}
		return p;
	}

	/// @description Clear a valid slot to noone without changing player capacity
	/// @param {Real} socket_id Integer slot in players
	/// @returns {Bool} Whether the slot was valid and cleared
	remove_player = function(socket_id)
	{
		/* Invalid slots cannot be removed. A valid slot is cleared to noone even if it was already
		empty */
		if (verify_socket(socket_id))
		{
			return false;
		}

		/* Integer slot index used to clear this player's registry entry */
		var socket_index = floor(socket_id);
		players[socket_index] = noone;
		return true;
	}

	/// @description Drop all stored player references while retaining allocated slot capacity
	clear_players = function()
	{
		/* Session and roster replacement invalidate both cards before a slot can be reused */
		scr_get_social().close_card();

		/* i starts at slot zero and visits each allocated slot once. Clearing to noone drops the
		controller's references without changing its capacity */
		for (var i = 0; i < array_length(players); i++)
		{
			players[i] = noone;
		}
	}

	/// @description Validate a player slot. True means the slot is invalid
	/// @param {Real} socket_id Integer slot in players
	/// @param {Bool} log_error Whether invalid values should log an error, default true
	/// @returns {Bool} Whether the slot must be rejected
	verify_socket = function(socket_id, log_error = true)
	{
		/* An absent ID has no player slot to validate, so report rejection before trying to round it */
		if (is_undefined(socket_id))
		{
			/* Log this rejection only when the caller requested diagnostics. Silent lookups can probe
			slots without flooding the log */
			if (log_error)
			{
				debug_error("socket_id is undefined");
			}
			return true;
		}

		/* Rounded candidate slot used to detect fractional IDs and enforce the players array bounds */
		var socket_index = floor(socket_id);

		/* Fractional IDs, negative slots and slots beyond capacity are rejected before any array
		access */
		if (socket_id != socket_index
		|| socket_index < 0
		|| socket_index >= array_length(players))
		{
			/* Keep error reporting optional here too, allowing the same validator to serve both
			commands and quiet lookups */
			if (log_error)
			{
				debug_error("socket_id " + string(socket_id) + " is out of bounds");
			}
			return true;
		}

		/* Reaching this point means the integer ID names an allocated slot. False follows this
		method's rejection-style result convention */
		return false;
	}

	/// @description Render occupied slots except usernames hidden by the local block list
	render_all_players = function()
	{
		/* Visit player slots from zero through the final allocated index, retaining slot IDs for the
		visibility check */
		for (var i = 0; i < array_length(players); i++)
		{
			/* Empty slots have no player to render, so continue directly to the next slot */
			if (players[i] == noone)
			{
				continue;
			}

			/* Locally blocked usernames hide their players. Skip their rendering while leaving their
			network slot state intact */
			if (!scr_get_social().player_visible(i))
			{
				continue;
			}

			players[i].render();
		}
	}
}

#region /* Player Slot Access */
/// @description Find player data by slot and log controller failures
/// @param {Real} socket_id Integer player array slot, not an operating-system socket handle
/// @param {Bool} log_error Whether invalid slot checks should log an error, default false
/// @returns {Struct} Player data, or noone for an empty or invalid slot
function player_controller_get_player(socket_id, log_error = false)
{
	try
	{
		/* Shared controller required to validate this slot and return its player data */
		var controller = scr_get_player_controller();

		/* Without a controller struct there is no safe slot lookup. Log the failure and return noone */
		if (!is_struct(controller))
		{
			debug_error("PlayerController is invalid.");
			return noone;
		}

		/* The players member must exist and be an array before a validated slot can be read. Reject
		malformed controller state */
		if (!variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			debug_error("PlayerController.players is invalid.");
			return noone;
		}

		/* A missing validator prevents bounds checking, so report the controller failure instead of
		reading its array */
		if (!variable_struct_exists(controller, "verify_socket"))
		{
			debug_error("PlayerController is missing verify_socket.");
			return noone;
		}

		/* Stored validator method keeps the call bound to the shared controller rather than
		duplicating its slot rules */
		var verify_socket_method = controller.verify_socket;

		/* A present member might still be non-callable. Return noone instead of attempting an invalid
		method call */
		if (!is_method(verify_socket_method))
		{
			debug_error("PlayerController.verify_socket is not callable.");
			return noone;
		}

		/* True from verify_socket means rejection. Leave the array unread for an invalid ID and use
		the validated slot otherwise */
		if (verify_socket_method(socket_id, log_error))
		{
			return noone;
		}

		/* Integer array index corresponding to the slot accepted by verify_socket */
		var socket_index = floor(socket_id);
		return controller.players[socket_index];
	}
	catch (e)
	{
		/* Base error report includes the operation and exception message. Extra exception detail is
		appended when provided */
		var msg = "player_controller_get_player failed: " + string(e.message);

		/* Append longMessage only if the exception includes it, preserving diagnostics without
		accessing a missing field */
		if (variable_struct_exists(e, "longMessage"))
		{
			msg += "\n" + e.longMessage;
		}
		debug_error(msg);
		return noone;
	}
}

/// @description Return the shared player-slot controller
/// @returns {Struct} Lazily constructed player controller
function scr_get_player_controller()
{
	/* Construct this controller only on the first call, then keep its player array shared by all later
	callers */
	static player_controller = new scr_player_controller();
	return player_controller;
}

/// @description Create or replace player data in a validated network slot
/// @param {Real} socket_id Integer slot in the player array
/// @param {Real} x Initial horizontal position in room pixels
/// @param {Real} y Initial vertical position in room pixels
/// @param {String} username Display name, defaulting to empty when omitted. An empty name becomes Player
/// @param {String} character_key Character key, defaulting to empty when omitted. An empty key selects Player 1
/// @returns {Struct} Created player data, or noone when creation fails
function player_controller_make_player(socket_id, x, y, username = "", character_key = "")
{
	try
	{
		/* Shared controller that creates player data and retains it in the requested slot */
		var controller = scr_get_player_controller();

		/* An unavailable controller cannot own the new player. Log this failure and return noone */
		if (!is_struct(controller))
		{
			debug_error("PlayerController is invalid.");
			return noone;
		}

		/* Reject a controller that lacks its creation method before attempting a call */
		if (!variable_struct_exists(controller, "make_player"))
		{
			debug_error("PlayerController is missing make_player.");
			return noone;
		}

		/* Creation method taken from the shared controller so its slot validation and storage behavior
		remain authoritative */
		var make_player_method = controller.make_player;

		/* Only a callable creation member can accept the supplied player information. Report
		non-callable state as failure */
		if (!is_method(make_player_method))
		{
			debug_error("PlayerController.make_player is not callable.");
			return noone;
		}

		return make_player_method(socket_id, x, y, username, character_key);
	}
	catch (e)
	{
		/* Failure report starts with the creation operation and exception message */
		var msg = "player_controller_make_player failed: " + string(e.message);

		/* Preserve optional detailed exception text when it exists, otherwise log only the base
		message */
		if (variable_struct_exists(e, "longMessage"))
		{
			msg += "\n" + e.longMessage;
		}
		debug_error(msg);
		return noone;
	}
}

/// @description Clear a validated player slot
/// @param {Real} socket_id Integer slot in the player array
/// @returns {Bool} Whether the slot was valid and cleared
function player_controller_remove_player(socket_id)
{
	try
	{
		/* Shared slot owner used to clear this player's entry */
		var controller = scr_get_player_controller();

		/* A missing controller cannot remove the entry, so return false and log the failure */
		if (!is_struct(controller))
		{
			debug_error("PlayerController is invalid.");
			return false;
		}

		/* Report removal failure when the controller exposes no removal operation */
		if (!variable_struct_exists(controller, "remove_player"))
		{
			debug_error("PlayerController is missing remove_player.");
			return false;
		}

		/* Bound removal method that performs the controller's slot validation before clearing its
		entry */
		var remove_player_method = controller.remove_player;

		/* Reject a non-callable removal member before invocation, returning false without altering
		players */
		if (!is_method(remove_player_method))
		{
			debug_error("PlayerController.remove_player is not callable.");
			return false;
		}

		return remove_player_method(socket_id);
	}
	catch (e)
	{
		/* Removal error text retains the operation name and exception's short message */
		var msg = "player_controller_remove_player failed: " + string(e.message);

		/* Add detailed exception text only when available so failure reporting does not itself access
		missing state */
		if (variable_struct_exists(e, "longMessage"))
		{
			msg += "\n" + e.longMessage;
		}
		debug_error(msg);
		return false;
	}
}

/// @description Empty all shared player slots, logging controller failures
function player_controller_clear_players()
{
	try
	{
		/* Shared controller whose complete players array is about to be cleared */
		var controller = scr_get_player_controller();

		/* A missing controller or clear method leaves the slots unchanged. This wrapper has no result
		value to report */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "clear_players"))
		{
			return;
		}

		/* Bound clear operation retrieved after checking that its member exists */
		var clear_players_method = controller.clear_players;

		/* Only invoke a callable clear method. A non-callable member leaves the registry as it is */
		if (is_method(clear_players_method))
		{
			clear_players_method();
		}
	}
	catch (e)
	{
		/* Clear-operation error report starts with the exception message */
		var msg = "player_controller_clear_players failed: " + string(e.message);

		/* Include longMessage when present to preserve the more detailed failure context */
		if (variable_struct_exists(e, "longMessage"))
		{
			msg += "\n" + e.longMessage;
		}
		debug_error(msg);
	}
}

/// @description Render occupied slots through the local social visibility filter
function player_controller_render_all_players()
{
	try
	{
		/* Shared controller that owns the occupied slots and their rendering loop */
		var controller = scr_get_player_controller();

		/* No controller means there are no shared players to render through this wrapper */
		if (!is_struct(controller))
		{
			return;
		}

		/* Skip rendering when the controller has no render operation instead of attempting a
		missing-member access */
		if (!variable_struct_exists(controller, "render_all_players"))
		{
			return;
		}

		/* Controller-bound rendering method used to retain its players and social visibility state */
		var render_all_method = controller.render_all_players;

		/* A non-callable rendering member cannot draw players. Leave the frame's player rendering
		skipped */
		if (!is_method(render_all_method))
		{
			return;
		}

		render_all_method();
	}
	catch (e)
	{
		/* Rendering failure report names this wrapper and stores the exception's message */
		var msg = "player_controller_render_all_players failed: " + string(e.message);

		/* Append optional exception detail only when present, then log the complete rendering failure */
		if (variable_struct_exists(e, "longMessage"))
		{
			msg += "\n" + e.longMessage;
		}
		debug_error(msg);
	}
}
#endregion /* Player Slot Access END */

#region /* Offscreen Player Indicators */
/// @description Draw GUI labels for visible remote players outside the supplied camera view
/// @param {Real} camera_id Camera used to convert room positions into GUI pixels
function player_controller_draw_edge_indicators(camera_id)
{
	try
	{
		/* Indicators require a numeric nonnegative camera handle to read the view. Invalid handles
		skip the entire overlay */
		if (!is_real(camera_id) || camera_id < 0)
		{
			return;
		}

		/* Shared player slots to inspect for offscreen remote players */
		var controller = scr_get_player_controller();

		/* Only a controller with a players array can supply indicator targets. Skip this overlay when
		that state is unavailable */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			return;
		}

		/* Local client state identifies which slot anchors the indicator rays */
		var client = scr_get_client();

		/* A client must expose an assigned ID before this overlay can distinguish its local player
		from remote targets */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone)
		{
			return;
		}

		/* Local player slot used as the ray origin and excluded from indicator targets */
		var local_id = client.ID;

		/* Reject local IDs outside the allocated players array before retrieving their position */
		if (local_id < 0 || local_id >= array_length(controller.players))
		{
			return;
		}

		/* Local player data supplies the position from which offscreen direction rays are drawn */
		var local_player = controller.players[local_id];

		/* An empty local slot has no usable ray origin, so no edge labels are drawn yet */
		if (local_player == noone)
		{
			return;
		}

		/* view_x and view_y are the camera origin in room pixels. view_w and view_h are its visible
		dimensions used to convert positions into GUI pixels */
		var view_x = camera_get_view_x(camera_id);
		var view_y = camera_get_view_y(camera_id);
		var view_w = camera_get_view_width(camera_id);
		var view_h = camera_get_view_height(camera_id);

		/* A view with zero or negative dimensions cannot provide the room-to-GUI scale. Skip
		indicators to avoid division by zero */
		if (view_w <= 0 || view_h <= 0)
		{
			return;
		}

		/* gui_w and gui_h are GUI canvas dimensions in pixels, used to place labels against its safe
		edges */
		var gui_w = display_get_gui_width();
		var gui_h = display_get_gui_height();

		/* A nonpositive GUI size leaves no drawable indicator area and cannot support coordinate
		scaling */
		if (gui_w <= 0 || gui_h <= 0)
		{
			return;
		}

		/* min_x and max_x inset the horizontal edges by 18 GUI pixels. min_y leaves 58 pixels above
		labels and max_y leaves 26 below, keeping them inside the overlay area */
		var min_x = 18;
		var max_x = gui_w - 18;
		var min_y = 58;
		var max_y = gui_h - 26;

		/* Start the local ray origin at its authoritative room position. Prefer its interpolated
		visual position when that field exists so labels track the drawn player */
		var local_world_x = local_player.pos.x;
		var local_world_y = local_player.pos.y;

		/* Use visual_pos for the ray origin when available. Older player data without it keeps the
		authoritative position */
		if (variable_struct_exists(local_player, "visual_pos"))
		{
			local_world_x = local_player.visual_pos.x;
			local_world_y = local_player.visual_pos.y;
		}

		/* center_x and center_y convert and clamp the local ray origin to the usable GUI edges. placed
		starts empty and placed_count tracks rectangles already reserved by earlier labels */
		var center_x = clamp((local_world_x - view_x) * gui_w / view_w, min_x, max_x);
		var center_y = clamp((local_world_y - view_y) * gui_h / view_h, min_y, max_y);
		var placed = [];
		var placed_count = 0;

		/// @description Choose the repeating accent color for a player slot
		/// @param {Real} player_slot_id Zero-based player slot
		/// @returns {Real} GameMaker color from the local repeating palette
		var indicator_color = function(player_slot_id)
		{
			/* Slot-indexed repeating colors let the same player keep the same edge accent without
			requiring a stored palette entry for every slot */
			var colors =
			[
				c_white,
				c_olive,
				c_maroon,
				c_navy,
			];
			return colors[player_slot_id mod array_length(colors)];
		}

		/// @description Test whether two padded GUI label rectangles overlap in their interiors
		/// @param {Struct} a First rectangle with x1, y1, x2 and y2
		/// @param {Struct} b Second rectangle with x1, y1, x2 and y2
		/// @returns {Bool} Whether both axes overlap
		var rects_overlap = function(a, b)
		{
			/* Rectangles overlap only when their interiors intersect on both axes. Touching edges
			remain available for another label */
			return a.x1 < b.x2
				&& a.x2 > b.x1
				&& a.y1 < b.y2
				&& a.y2 > b.y1;
		}

		/* i starts at player slot zero and visits all slots once to build one indicator per eligible
		remote player */
		for (var i = 0; i < array_length(controller.players); i++)
		{
			/* The local player anchors the rays and needs no offscreen label for itself, so exclude
			its slot */
			if (i == local_id)
			{
				continue;
			}

			/* Player data for this candidate slot. Empty slots remain noone and are skipped before
			reading their position */
			var player = controller.players[i];

			/* No occupant means there is no remote target to label */
			if (player == noone)
			{
				continue;
			}

			/* Honor the local social block filter on indicators just as on world rendering */
			if (!scr_get_social().player_visible(i))
			{
				continue;
			}

			/* world_x and world_y begin at the target's authoritative room position and are replaced
			by visual_pos when interpolation state exists */
			var world_x = player.pos.x;
			var world_y = player.pos.y;

			/* Use the target's drawn position when available so the edge label follows the same
			location as its sprite */
			if (variable_struct_exists(player, "visual_pos"))
			{
				world_x = player.visual_pos.x;
				world_y = player.visual_pos.y;
			}

			/* screen_x and screen_y are the target's projected GUI coordinates before edge clamping */
			var screen_x = (world_x - view_x) * gui_w / view_w;
			var screen_y = (world_y - view_y) * gui_h / view_h;

			/* Players inside the GUI area plus a 12-pixel allowance are already visible enough to need
			no edge indicator */
			if (screen_x >= -12
			&& screen_x <= gui_w + 12
			&& screen_y >= -12
			&& screen_y <= gui_h + 12)
			{
				continue;
			}

			/* dx and dy form the GUI-space ray from the local player to this offscreen target */
			var dx = screen_x - center_x;
			var dy = screen_y - center_y;

			/* A zero-length ray has no direction and cannot select a screen edge, so skip this target */
			if (dx == 0 && dy == 0)
			{
				continue;
			}

			/* intersection_t starts beyond ordinary edge intersections so the nearest candidate
			replaces it. edge initially names the right side and is updated with the selected
			intersection */
			var intersection_t = 1000000;
			var edge = "right";

			/* A rightward ray can hit the right safe edge. Leftward or vertical rays skip that
			candidate */
			if (dx > 0)
			{
				/* Ray multiplier at the right edge, measured relative to the complete dx and dy vector */
				var right_t = (max_x - center_x) / dx;

				/* Retain this edge only when its intersection is closer than the best candidate so far */
				if (right_t < intersection_t)
				{
					intersection_t = right_t;
					edge = "right";
				}
			}

			/* After excluding rightward rays, a leftward ray can intersect the left safe edge */
			else if (dx < 0)
			{
				/* Ray multiplier at the left edge used to compare against other boundary crossings */
				var left_t = (min_x - center_x) / dx;

				/* The closest boundary intersection decides where the target's label is anchored */
				if (left_t < intersection_t)
				{
					intersection_t = left_t;
					edge = "left";
				}
			}

			/* A downward ray adds the bottom edge as a candidate. Otherwise the bottom edge is
			irrelevant */
			if (dy > 0)
			{
				/* Ray multiplier for the bottom edge, compared with any earlier horizontal crossing */
				var bottom_t = (max_y - center_y) / dy;

				/* Replace the chosen edge when the bottom crossing is nearer to the local ray origin */
				if (bottom_t < intersection_t)
				{
					intersection_t = bottom_t;
					edge = "bottom";
				}
			}

			/* After excluding downward rays, an upward ray can reach the top safe edge */
			else if (dy < 0)
			{
				/* Ray multiplier for the top edge, retaining the earliest boundary crossing */
				var top_t = (min_y - center_y) / dy;

				/* A nearer top crossing replaces the horizontal edge selected earlier */
				if (top_t < intersection_t)
				{
					intersection_t = top_t;
					edge = "top";
				}
			}

			/* edge_x and edge_y are the chosen ray intersection clamped into the safe GUI rectangle */
			var edge_x = clamp(center_x + dx * intersection_t, min_x, max_x);
			var edge_y = clamp(center_y + dy * intersection_t, min_y, max_y);

			/* Fallback display name ensures the indicator remains readable for players without a
			usable username */
			var name_text = "Player";

			/* A present, nonempty username replaces Player. Missing or empty names retain the fallback */
			if (variable_struct_exists(player, "username")
			&& string(player.username) != "")
			{
				name_text = string(player.username);
			}

			draw_set_font(fnt_ui);

			/* text_height is the 16-pixel label height and text_scale converts the font to that
			height. text_w is capped to keep long usernames from consuming an entire edge */
			var text_height = 16;
			var text_scale = scr_render_text_scale(text_height);
			var text_w = clamp(string_width(name_text) * text_scale, 48, 150);

			/* group_h is the 28-pixel label height and group_w includes 48 pixels for its character
			icon and padding. group_x starts centered on the ray's edge intersection */
			var group_h = 28;
			var group_w = text_w + 48;
			var group_x = edge_x - group_w * 0.5;

			/* For the left edge, begin the label at the intersection so the whole label extends into
			the GUI */
			if (edge == "left")
			{
				group_x = edge_x;
			}

			/* For the right edge, shift the label's full width left of the intersection so it stays
			inside the GUI */
			else if (edge == "right")
			{
				group_x = edge_x - group_w;
			}

			/* group_y starts centered vertically on the intersection before both axes are clamped to
			the usable GUI area */
			var group_y = edge_y - group_h * 0.5;
			group_x = clamp(group_x, min_x, max(min_x, max_x - group_w));
			group_y = clamp(group_y, min_y, max(min_y, max_y - group_h));

			/* attempt starts at zero and allows up to ten overlap adjustments. Stop earlier when this
			label no longer intersects a previously placed label */
			for (var attempt = 0; attempt < 10; attempt++)
			{
				/* rect stores this attempt's x1, y1, x2 and y2 GUI bounds with two pixels of extra
				separation on every side */
				var rect =
				{
					x1: group_x - 2,
					y1: group_y - 2,
					x2: group_x + group_w + 2,
					y2: group_y + group_h + 2
				};

				/* Start each attempt with no detected overlap, then test only the placed_count
				rectangles already reserved by earlier players */
				var overlaps = false;

				/* placed_index visits reserved rectangles from zero to placed_count minus one. Unused
				entries beyond that count are not inspected */
				for (var placed_index = 0; placed_index < placed_count; placed_index++)
				{
					/* The first intersecting reserved rectangle marks this placement as occupied.
					Further tests are unnecessary for this attempt */
					if (rects_overlap(rect, placed[placed_index]))
					{
						overlaps = true;
						break;
					}
				}

				/* A clear rectangle finishes the placement search immediately. Only occupied
				placements need another adjustment */
				if (!overlaps)
				{
					break;
				}

				/* On either vertical edge, move along that edge instead of shifting the label away
				from its boundary */
				if (edge == "left" || edge == "right")
				{
					/* Move upward for labels above the local origin and downward for labels below it,
					separating nearby edge labels without crossing the origin */
					var y_direction = group_y < center_y ? -1 : 1;
					group_y = clamp(group_y + y_direction * (group_h + 5), min_y, max(min_y, max_y - group_h));
				}

				/* Top and bottom labels use horizontal adjustments because movement along those edges
				must keep their vertical anchor */
				else
				{
					/* Choose leftward or rightward movement according to the label's side of the local
					origin, then clamp the new position into the GUI */
					var x_direction = group_x < center_x ? -1 : 1;
					group_x = clamp(group_x + x_direction * (group_w * 0.5), min_x, max(min_x, max_x - group_w));
				}
			}

			/* Reserve the final x1, y1, x2 and y2 GUI rectangle including its two-pixel spacing.
			Increment placed_count so later players test against this label */
			placed[placed_count++] =
			{
				x1: group_x - 2,
				y1: group_y - 2,
				x2: group_x + group_w + 2,
				y2: group_y + group_h + 2
			};

			/* Slot-based accent color links this edge label to the target rather than its current
			screen position */
			var player_color = indicator_color(i);
			draw_set_alpha(0.78);
			draw_set_colour(c_black);
			draw_rectangle(group_x, group_y, group_x + group_w, group_y + group_h, false);
			draw_set_alpha(1);

			draw_set_colour(player_color);
			draw_rectangle(group_x, group_y, group_x + 4, group_y + group_h, false);
			draw_set_colour(make_color_rgb(88, 92, 98));
			draw_rectangle(group_x, group_y, group_x + group_w, group_y + group_h, true);

			draw_set_colour(make_color_rgb(34, 54, 38));
			draw_rectangle(group_x + 9, group_y + 5, group_x + 27, group_y + 23, false);

			/* Use the player's character key for its icon when present. Older data without that field
			falls back to Player 1 */
			var edge_character_key = variable_struct_exists(player, "character_key") ? player.character_key : "player1";
			player_character_draw_key_in_box(edge_character_key, PLAYER_DIRECTION_DOWN, false, group_x + 9, group_y + 5, group_x + 27, group_y + 23, c_white, 1);

			draw_set_halign(fa_left);
			draw_set_colour(c_white);
			scr_render_text(group_x + 34, group_y + 6, name_text, text_height, group_w - 42);
		}

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	catch (e)
	{
		/* Indicator failure report contains the operation and short exception message */
		var msg = "player_controller_draw_edge_indicators failed: " + string(e.message);

		/* Retain optional long exception text when supplied before writing the diagnostic */
		if (variable_struct_exists(e, "longMessage"))
		{
			msg += "\n" + e.longMessage;
		}
		debug_error(msg);
	}
}
#endregion /* Offscreen Player Indicators END */

#region /* Movement and Collision Bounds */
/// @description Check a short circle path against player room margins and wall cells at one-pixel intervals
/// @param {Real} from_x Accepted horizontal room position
/// @param {Real} from_y Accepted vertical room position
/// @param {Real} to_x Candidate horizontal room position
/// @param {Real} to_y Candidate vertical room position
/// @param {Real} radius Circle radius in room pixels
/// @param {Struct} bounds Player frame and nameplate room margins
/// @param {Bool} use_server Whether to test authoritative server walls, default false
/// @returns {Bool} Whether the full sampled path remains inside the room and outside occupied walls
function player_wall_path_clear(from_x, from_y, to_x, to_y, radius, bounds, use_server = false)
{
	/* Check room limits before scanning cells. Sliding must keep the same frame and nameplate
	margins as ordinary movement, even when its tangent adds an unrequested axis */
	if (to_x < bounds.left || to_x > bounds.right || to_y < bounds.top || to_y > bounds.bottom) return false;
	var walls = scr_get_walls();
	var move_x = to_x - from_x;
	var move_y = to_y - from_y;
	var sample_count = max(1, ceil(sqrt(move_x * move_x + move_y * move_y)));
	for (var sample_index = 1; sample_index <= sample_count; sample_index++)
	{
		/* Each sample advances no more than one room pixel. A clear endpoint alone must not accept
		a tangent or axis fallback that briefly crosses a thin wall or cell corner */
		var amount = sample_index / sample_count;
		if (walls.circle_overlaps(from_x + move_x * amount, from_y + move_y * amount, radius, use_server)) return false;
	}
	return true;
}

/// @description Trace room movement against wall cells, preserving contour sliding and escape from an existing overlap
/// @param {Real} from_x Starting horizontal position in room pixels
/// @param {Real} from_y Starting vertical position in room pixels
/// @param {Real} to_x Requested horizontal position, already clamped to the room
/// @param {Real} to_y Requested vertical position, already clamped to the room
/// @param {Real} radius Player collision radius in room pixels, default 38
/// @param {Bool} use_server Whether to test authoritative server walls instead of client walls, default false
/// @returns {Struct} x and y in room pixels, plus blocked when an attempted step intersects a wall
function player_resolve_wall_movement(from_x, from_y, to_x, to_y, radius = PLAYER_COLLISION_RADIUS, use_server = false)
{
	/* Shared wall grid used to test the swept player circle. move_x and move_y are requested
	room-pixel deltas and distance is their combined travel length */
	var walls = scr_get_walls();
	var move_x = to_x - from_x;
	var move_y = to_y - from_y;
	var distance = sqrt(move_x * move_x + move_y * move_y);

	/* No travel means the starting position already resolves this request. Return its x and y
	unchanged with blocked false */
	if (distance <= 0)
	{
		return { x: from_x, y: from_y, blocked: false };
	}

	/* Positions are clamped to the room before entering here. Four-pixel steps
	prevent thin strokes from being skipped by a delayed movement packet */
	/* step_count splits travel into at most four-pixel increments. step_x and step_y are the
	room-pixel deltas per increment. resolved_x and resolved_y start at the source position and
	advance only as collisions permit */
	var step_count = max(1, ceil(distance / 4));
	var step_x = move_x / step_count;
	var step_y = move_y / step_count;
	var resolved_x = from_x;
	var resolved_y = from_y;
	var bounds = player_world_bounds();

	/* blocked begins false until a blocked increment occurs. escaping_overlap records whether the
	starting collision circle is already inside a wall */
	var blocked = false;
	var escaping_overlap = walls.circle_overlaps(from_x, from_y, radius, use_server);

	/* step_index counts increments from zero to step_count minus one. Work can finish earlier when
	neither axis can advance */
	for (var step_index = 0; step_index < step_count; step_index++)
	{
		/* A previous contour slide can add travel on the other axis. Clamp every new request to the
		original player margins instead of assuming the initial destination still bounds that travel */
		var next_x = clamp(resolved_x + step_x, bounds.left, bounds.right);
		var next_y = clamp(resolved_y + step_y, bounds.top, bounds.bottom);
		var requested_x = next_x - resolved_x;
		var requested_y = next_y - resolved_y;
		var next_overlaps = walls.circle_overlaps(next_x, next_y, radius, use_server);
		if (escaping_overlap)
		{
			/* A wall can arrive over a player, including while joining. Let that
			player walk out. Ordinary blocking resumes as soon as they are clear */
			resolved_x = next_x;
			resolved_y = next_y;
			escaping_overlap = next_overlaps;
			continue;
		}

		/* An ordinary clear substep keeps its requested direction. Path samples also reject a brief
		corner crossing before either the contour or axis fallback is considered */
		if (!next_overlaps && player_wall_path_clear(resolved_x, resolved_y, next_x, next_y, radius, bounds, use_server))
		{
			resolved_x = next_x;
			resolved_y = next_y;
			continue;
		}

		/* previous_x and previous_y retain the last accepted position so blocked attempts can stop
		when neither axis advances */
		blocked = true;
		var previous_x = resolved_x;
		var previous_y = resolved_y;

		/* Nearby incoming cell contacts estimate the painted contour at this accepted position.
		Project only the part of input that pushes into it, retaining forward travel along the tangent */
		var normal = walls.circle_contact_normal(resolved_x, resolved_y, radius, requested_x, requested_y, use_server);
		var into_wall = requested_x * normal.x + requested_y * normal.y;
		var requested_length_squared = requested_x * requested_x + requested_y * requested_y;
		var slid = false;
		if (into_wall < 0)
		{
			var tangent_x = requested_x - normal.x * into_wall;
			var tangent_y = requested_y - normal.y * into_wall;
			var tangent_length_squared = tangent_x * tangent_x + tangent_y * tangent_y;

			/* A tangent below 2.5 percent of this substep is too small to distinguish from grid
			averaging noise. Flat head-on input therefore stops without choosing an arbitrary side */
			if (tangent_length_squared > requested_length_squared * 0.025 * 0.025)
			{
				var tangent_length = sqrt(tangent_length_squared);
				var outward_biases = [0, 0.05, 0.10, 0.20, 0.40];
				for (var slide_attempt = 0; slide_attempt < array_length(outward_biases); slide_attempt++)
				{
					/* Try the exact tangent first, then small bounded outward components for a rounded
					staircase corner. These are candidate movement deltas, not unchecked position nudges */
					var outward_amount = tangent_length * outward_biases[slide_attempt];
					var slide_x = tangent_x + normal.x * outward_amount;
					var slide_y = tangent_y + normal.y * outward_amount;
					var slide_length_squared = slide_x * slide_x + slide_y * slide_y;
					if (slide_length_squared > requested_length_squared)
					{
						/* Outward bias must not increase the available input speed */
						var speed_scale = sqrt(requested_length_squared / slide_length_squared);
						slide_x *= speed_scale;
						slide_y *= speed_scale;
					}

					/* Require positive progress along the input. A backstep or purely sideways escape
					cannot be selected merely because it is clear */
					if (slide_x * requested_x + slide_y * requested_y <= requested_length_squared * 0.0001) continue;
					if (!player_wall_path_clear(resolved_x, resolved_y, resolved_x + slide_x, resolved_y + slide_y, radius, bounds, use_server)) continue;
					resolved_x += slide_x;
					resolved_y += slide_y;
					slid = true;
					break;
				}
			}
		}
		if (slid) continue;

		/* Keep the unobstructed component so walking along a wall feels smooth */
		/* Keep horizontal travel only when this increment moves horizontally and the resulting circle
		is clear at the current vertical position. Otherwise leave that axis fixed */
		if (requested_x != 0 && player_wall_path_clear(resolved_x, resolved_y, next_x, resolved_y, radius, bounds, use_server))
		{
			resolved_x = next_x;
		}

		/* Test vertical travel at the possibly adjusted horizontal position. A zero or blocked
		vertical component stays fixed so the player can slide along clear axes */
		if (requested_y != 0 && player_wall_path_clear(resolved_x, resolved_y, resolved_x, next_y, radius, bounds, use_server))
		{
			resolved_y = next_y;
		}

		/* When both independent axis attempts leave the position unchanged, further increments cannot
		advance this move. Stop the sweep here */
		if (resolved_x == previous_x && resolved_y == previous_y)
		{
			break;
		}
	}

	/* Return accepted room coordinates in x and y. blocked remains true once any intended full
	increment intersects a wall, even when axis sliding still moved the player */
	return { x: resolved_x, y: resolved_y, blocked: blocked };
}

/// @description Return room limits inset by the collision object radius, with a four-pixel minimum margin
/// @param {Real} radius Collision radius in room pixels
/// @returns {Struct} left, top, right, and bottom room coordinates
function collision_object_room_bounds(radius)
{
	/* Room-pixel inset margin is at least four or the collision radius, whichever is larger. Returned
	left, top, right and bottom keep the full circle inside the room */
	var margin = max(4, radius);
	return
	{
		left: margin,
		top: margin,
		right: room_width - margin,
		bottom: room_height - margin
	};
}

/// @description Find the center of the collision object room bounds
/// @param {Real} radius Collision radius in room pixels
/// @returns {Struct} x and y room coordinates
function collision_object_start_position(radius)
{
	/* bounds is the radius-inset room rectangle. center_x and center_y are its midpoint coordinates in
	room pixels and become the returned x and y spawn position */
	var bounds = collision_object_room_bounds(radius);
	var center_x = (bounds.left + bounds.right) * 0.5;
	var center_y = (bounds.top + bounds.bottom) * 0.5;

	return
	{
		x: center_x,
		y: center_y
	};
}
#endregion /* Movement and Collision Bounds END */

/// @description Own the shared ball state. Server or singleplayer updates run physics and clients interpolate its drawing
function scr_collision_objects() constructor
{
	/* objects starts empty until make_ball establishes the default ball. server_state_dirty starts
	false until reset_server or physics changes require a network broadcast */
	objects = [];
	server_state_dirty = false;

	/* visual_lerp_amount advances client visuals by 34 percent of the gap each update.
	player_collision_radius and ball_radius measure collision circles in room pixels */
	visual_lerp_amount = 0.34;
	player_collision_radius = PLAYER_COLLISION_RADIUS;
	ball_radius = 30;

	/* ball_friction keeps 98.5 percent of velocity each physics update. ball_wall_bounce keeps 58
	percent after reversing an outward wall hit. ball_player_impulse is the base moving-player kick
	in room pixels per physics update */
	ball_friction = 0.985;
	ball_wall_bounce = 0.58;
	ball_player_impulse = 6.25;

	/* ball_overlap_impulse adds kick per pixel of overlap. ball_stationary_nudge pushes from idle
	players. ball_max_speed caps room pixels per physics update and ball_stop_speed snaps smaller
	speeds to rest */
	ball_overlap_impulse = 0.16;
	ball_stationary_nudge = 1.1;
	ball_max_speed = 17; /* Room pixels per physics update, not per second */
	ball_stop_speed = 0.08;

	#region /* Collision Object Lifecycle */
	/// @description Construct the default active ball at the room center with zero velocity
	/// @returns {Struct} Ball position, visual state, velocity and collision radius
	make_ball = function()
	{
		/* Room-center spawn for the new ball, calculated with ball_radius so its collision bounds
		remain inside the room */
		var start = collision_object_start_position(ball_radius);

		/* The ball's id is zero and kind selects the ball renderer. x and y start at the room center
		and visual_x and visual_y match them. vx and vy start at rest, radius uses ball_radius and
		active enables physics and drawing */
		return
		{
			id: 0,
			kind: COLLISION_OBJECT_BALL,
			x: start.x,
			y: start.y,
			visual_x: start.x,
			visual_y: start.y,
			vx: 0,
			vy: 0,
			radius: ball_radius,
			active: true
		};
	}

	/// @description Replace the collision-object collection with one centered resting ball
	reset_common = function()
	{
		objects = [make_ball()];
	}

	/// @description Reset client collision objects and clear pending server-broadcast state
	reset_client = function()
	{
		reset_common();
		server_state_dirty = false;
	}

	/// @description Reset server collision objects and request a broadcast of the initial state
	reset_server = function()
	{
		reset_common();
		server_state_dirty = true;
	}

	/// @description Restore the default ball only when the object collection is missing or empty
	ensure_defaults = function()
	{
		/* Missing or empty object storage restores the default ball. Existing object state is retained
		rather than respawned on every access */
		if (!is_array(objects) || array_length(objects) <= 0)
		{
			reset_common();
		}
	}

	/// @description Find an existing collision object by its packet ID
	/// @param {Real} collision_object_id Persistent object ID
	/// @returns {Real} Storage index, or noone when no occupied object matches
	find_object_index = function(collision_object_id)
	{
		/* i begins at object-array index zero and searches all stored entries until an ID matches or
		the array ends */
		for (var i = 0; i < array_length(objects); i++)
		{
			/* An occupied entry with an id member matching the packet's object ID identifies the
			existing object. Empty or unmatched entries are skipped */
			if (objects[i] != noone
			&& variable_struct_exists(objects[i], "id")
			&& objects[i].id == collision_object_id)
			{
				return i;
			}
		}

		return noone;
	}
	#endregion /* Collision Object Lifecycle END */

	#region /* Ball Physics */
	/// @description Clamp an object's center inside radius-inset room bounds and bounce outward velocity
	/// @param {Struct} obj Mutable collision object with position and velocity
	/// @returns {Bool} Whether its position or meaningful velocity changed
	clamp_object_to_room = function(obj)
	{
		/* Only a struct can provide position and velocity for room clamping. Return false for invalid
		input without changing anything */
		if (!is_struct(obj))
		{
			return false;
		}

		/* radius uses the object's own positive size when present or the configured ball size
		otherwise. bounds is its allowed room rectangle */
		var radius = variable_struct_exists(obj, "radius") ? max(1, obj.radius) : ball_radius;
		var bounds = collision_object_room_bounds(radius);

		/* old_x, old_y, old_vx and old_vy preserve the pre-clamp position and velocity so the return
		value can report a correction */
		var old_x = obj.x;
		var old_y = obj.y;
		var old_vx = obj.vx;
		var old_vy = obj.vy;

		/* A position left of the allowed inset is moved back to the left boundary. In-bounds positions
		continue unchanged */
		if (obj.x < bounds.left)
		{
			obj.x = bounds.left;

			/* Reverse only velocity still pointing outward through the left wall. Already inward
			movement needs no second bounce */
			if (obj.vx < 0)
			{
				obj.vx = -obj.vx * ball_wall_bounce;
			}
		}

		/* With the left side ruled out, a position beyond the right inset is corrected to the right
		boundary */
		else if (obj.x > bounds.right)
		{
			obj.x = bounds.right;

			/* A rightward velocity at the right boundary bounces left and loses energy. Inward or
			stationary velocity remains unchanged */
			if (obj.vx > 0)
			{
				obj.vx = -obj.vx * ball_wall_bounce;
			}
		}

		/* A position above the top inset is returned to that boundary so the ball remains inside the
		room */
		if (obj.y < bounds.top)
		{
			obj.y = bounds.top;

			/* Only upward motion at the top boundary needs to be reversed and damped */
			if (obj.vy < 0)
			{
				obj.vy = -obj.vy * ball_wall_bounce;
			}
		}

		/* After ruling out the top side, a position below the bottom inset is corrected to the bottom
		boundary */
		else if (obj.y > bounds.bottom)
		{
			obj.y = bounds.bottom;

			/* Downward motion bounces upward at the bottom boundary. Already inward velocity is
			retained */
			if (obj.vy > 0)
			{
				obj.vy = -obj.vy * ball_wall_bounce;
			}
		}

		/* Report a correction for any position change or velocity change above 0.001 room pixels per
		update, avoiding tiny floating-point differences in network dirty checks */
		return old_x != obj.x
			|| old_y != obj.y
			|| abs(old_vx - obj.vx) > 0.001
			|| abs(old_vy - obj.vy) > 0.001;
	}

	/// @description Cap object speed while retaining direction and stop speeds below the configured rest threshold
	/// @param {Struct} obj Collision object whose vx and vy are updated
	limit_object_velocity = function(obj)
	{
		/* speed_sq measures squared room pixels per physics update and max_speed_sq is the configured
		cap in the same units */
		var speed_sq = obj.vx * obj.vx + obj.vy * obj.vy;
		var max_speed_sq = ball_max_speed * ball_max_speed;

		/* Speeds above the cap are rescaled to ball_max_speed while keeping their direction. Lower
		speeds retain their components */
		if (speed_sq > max_speed_sq)
		{
			/* Actual velocity length is needed only for normalization after the squared-speed cap test
			fails */
			var velocity_length = sqrt(speed_sq);
			obj.vx = obj.vx / velocity_length * ball_max_speed;
			obj.vy = obj.vy / velocity_length * ball_max_speed;
			speed_sq = max_speed_sq;
		}

		/* Speeds below ball_stop_speed are treated as rest, stopping tiny friction-driven movement and
		unnecessary state broadcasts */
		if (speed_sq < ball_stop_speed * ball_stop_speed)
		{
			obj.vx = 0;
			obj.vy = 0;
		}
	}

	/// @description Resolve a normalized movement direction or an idle facing direction for player kicks
	/// @param {Struct} player Player input and facing state
	/// @returns {Struct} Unit x/y direction with moving indicating active input
	player_direction_vector = function(player)
	{
		/* move_x and move_y start at zero and accumulate available right-minus-left and down-minus-up
		input values */
		var move_x = 0;
		var move_y = 0;

		/* Only player structs can provide directional input members. Other values leave the movement
		vector at rest */
		if (is_struct(player))
		{
			/* Add right input when that member exists. Missing input contributes nothing to horizontal
			motion */
			if (variable_struct_exists(player, "right"))
			{
				move_x += player.right;
			}

			/* Subtract left input when present so opposite horizontal keys cancel */
			if (variable_struct_exists(player, "left"))
			{
				move_x -= player.left;
			}

			/* Add down input when present. Missing downward input retains the current vertical total */
			if (variable_struct_exists(player, "down"))
			{
				move_y += player.down;
			}

			/* Subtract up input when present so opposite vertical keys cancel */
			if (variable_struct_exists(player, "up"))
			{
				move_y -= player.up;
			}
		}

		/* Movement-vector length distinguishes a held direction from rest and normalizes diagonal
		kicks */
		var move_len = sqrt(move_x * move_x + move_y * move_y);

		/* A nonzero input vector returns a unit x/y direction with moving true so ball kicks follow
		actual movement */
		if (move_len > 0)
		{
			return
			{
				x: move_x / move_len,
				y: move_y / move_len,
				moving: true
			};
		}

		/* With no active input, use facing_direction when available or face down by default. This
		supplies x/y kick direction while moving remains false */
		var facing = variable_struct_exists(player, "facing_direction")
			? player.facing_direction
			: PLAYER_DIRECTION_DOWN;

		/* Idle facing selects a unit kick direction. Known left, right and up directions use their
		matching axes, while down or an unrecognized value uses downward movement */
		switch (facing)
		{
			case PLAYER_DIRECTION_LEFT:

				/* Left-facing idle players nudge toward negative x without being treated as actively
				moving */
				return { x: -1, y: 0, moving: false };
			case PLAYER_DIRECTION_RIGHT:

				/* Right-facing idle players nudge toward positive x */
				return { x: 1, y: 0, moving: false };
			case PLAYER_DIRECTION_UP:

				/* Up-facing idle players nudge toward negative y */
				return { x: 0, y: -1, moving: false };
			default:

				/* The remaining idle facing values use a downward nudge along positive y */
				return { x: 0, y: 1, moving: false };
		}
	}

	/// @description Separate an overlapping ball from a player and apply a movement or idle kick
	/// @param {Struct} obj Collision object updated in place
	/// @param {Struct} player Player with room position and movement state
	/// @returns {Bool} Whether an overlap was resolved
	resolve_player_collision = function(obj, player)
	{
		/* Collision requires object and player structs plus a position struct. Reject missing state
		before reading either position */
		if (!is_struct(obj)
		|| !is_struct(player)
		|| !variable_struct_exists(player, "pos")
		|| !is_struct(player.pos))
		{
			return false;
		}

		/* px and py are the player's room-pixel center. dx and dy point from that center to the ball.
		min_dist is the sum of collision radii and dist_sq avoids a square root for separated
		circles */
		var px = player.pos.x;
		var py = player.pos.y;
		var dx = obj.x - px;
		var dy = obj.y - py;
		var min_dist = obj.radius + player_collision_radius;
		var dist_sq = dx * dx + dy * dy;

		/* Circles separated by at least their combined radii do not overlap, so no push or velocity
		change is applied */
		if (dist_sq >= min_dist * min_dist)
		{
			return false;
		}

		/* player_dir provides a unit input or idle-facing direction. dist is the center separation
		with a small floor to avoid division by zero. nx and ny form the outward collision normal */
		var player_dir = player_direction_vector(player);
		var dist = sqrt(max(dist_sq, 0.0001));
		var nx = dx / dist;
		var ny = dy / dist;

		/* Coincident centers cannot define an outward normal. Use the player's direction instead to
		move the ball consistently without dividing by zero */
		if (dist_sq <= 0.0001)
		{
			nx = player_dir.x;
			ny = player_dir.y;
		}

		/* Overlap depth in room pixels determines how far the ball is separated from the player, with
		half a pixel of clearance added */
		var overlap = min_dist - dist;
		obj.x += nx * (overlap + 0.5);
		obj.y += ny * (overlap + 0.5);

		/* player_speed uses the player's movement setting or a five-pixel fallback. toward_amount is
		the positive portion of movement along the collision normal */
		var player_speed = variable_struct_exists(player, "movement_speed") ? player.movement_speed : 5;
		var toward_amount = max(0, player_dir.x * nx + player_dir.y * ny);

		/* Active movement combines the base kick with speed toward the ball. Idle contact uses
		ball_stationary_nudge so a resting player still separates the ball */
		var impulse = player_dir.moving
			? ball_player_impulse + player_speed * toward_amount
			: ball_stationary_nudge;

		impulse += overlap * ball_overlap_impulse;
		obj.vx += nx * impulse + player_dir.x * impulse * 0.35;
		obj.vy += ny * impulse + player_dir.y * impulse * 0.35;
		limit_object_velocity(obj);
		clamp_object_to_room(obj);
		return true;
	}

	/// @description Advance active ball physics, resolve player contacts and report state changes
	/// @param {Array} players Player-slot array, with noone in unoccupied slots
	/// @returns {Bool} Whether any collision object's state changed
	update_physics = function(players)
	{
		ensure_defaults();

		/* changed starts false and records any collision, movement or boundary correction requiring a
		fresh state packet */
		var changed = false;

		/* i visits each collision-object entry from zero to the end, updating active objects only */
		for (var i = 0; i < array_length(objects); i++)
		{
			/* Current collision-object reference. Empty or inactive entries are ignored before
			position and velocity are read */
			var obj = objects[i];

			/* Inactive objects do not participate in physics. Empty entries also skip this update */
			if (obj == noone || !obj.active)
			{
				continue;
			}

			/* old_x, old_y, old_vx and old_vy retain this object's starting state for the final change
			check */
			var old_x = obj.x;
			var old_y = obj.y;
			var old_vx = obj.vx;
			var old_vy = obj.vy;

			/* Player collisions are processed only when the caller supplies a players array. Object
			movement still proceeds without one */
			if (is_array(players))
			{
				/* p starts at player slot zero and tests all allocated player entries once for contact
				with this object */
				for (var p = 0; p < array_length(players); p++)
				{
					/* Occupied player slots that actually resolve an overlap mark the physics state
					changed. Empty or separated slots make no change */
					if (players[p] != noone && resolve_player_collision(obj, players[p]))
					{
						changed = true;
					}
				}
			}

			/* A nonzero velocity advances the object and applies friction. Resting objects skip
			movement and friction work */
			if (obj.vx != 0 || obj.vy != 0)
			{
				obj.x += obj.vx;
				obj.y += obj.vy;
				obj.vx *= ball_friction;
				obj.vy *= ball_friction;
				limit_object_velocity(obj);
				changed = true;
			}

			/* Room clamping marks state changed only when position or meaningful velocity correction
			occurred */
			if (clamp_object_to_room(obj))
			{
				changed = true;
			}

			/* Compare position and velocity with this update's starting state, including kicks or
			clamps that earlier flags did not catch */
			if (old_x != obj.x
			|| old_y != obj.y
			|| abs(old_vx - obj.vx) > 0.001
			|| abs(old_vy - obj.vy) > 0.001)
			{
				changed = true;
			}
		}

		/* True means at least one object's state changed during this physics pass and the server
		should relay a new snapshot */
		return changed;
	}

	/// @description Advance server physics and retain a dirty flag when a snapshot needs relaying
	/// @param {Array} players Server player slots
	update_server = function(players)
	{
		/* A changed physics pass sets the pending broadcast flag. An unchanged pass leaves any
		existing dirty flag as it was */
		if (update_physics(players))
		{
			server_state_dirty = true;
		}
	}

	/// @description Advance collision-object physics against the one local singleplayer
	/// @param {Struct} player Local player's movement and position data
	update_singleplayer = function(player)
	{
		update_physics([player]);
	}

	/// @description Clear the pending collision-object broadcast flag after the server handles it
	clear_dirty = function()
	{
		server_state_dirty = false;
	}
	#endregion /* Ball Physics END */

	#region /* Collision Object Packets */
	/// @description Append active collision objects and a noone ID terminator to an already-started network packet
	write_state_packet_body = function()
	{
		/* Field order and the noone terminator must match receive_state_packet_body */
		ensure_defaults();

		/* Shared network writer appends this packet body without starting or sending the containing
		packet */
		var net = scr_get_network();

		/* i traverses all collision-object entries in storage order and writes only active occupants */
		for (var i = 0; i < array_length(objects); i++)
		{
			/* Current object reference supplies the packet's ID, kind, room position, velocity and
			radius fields */
			var obj = objects[i];

			/* Empty or inactive entries have no active snapshot to send and are skipped */
			if (obj == noone || !obj.active)
			{
				continue;
			}

			net.write(TYPE_ID, obj.id);
			net.write(buffer_u8, obj.kind);
			net.write(TYPE_POSITION, round(obj.x));
			net.write(TYPE_POSITION, round(obj.y));
			net.write(buffer_f32, obj.vx);
			net.write(buffer_f32, obj.vy);
			net.write(buffer_s16, round(obj.radius));
		}

		net.write(TYPE_ID, noone);
	}

	/// @description Read collision objects from the current network reader through the noone ID terminator and retain interpolated visual positions
	receive_state_packet_body = function()
	{
		/* Shared network reader consumes the packet body whose field order matches
		write_state_packet_body */
		var net = scr_get_network();

		/* Read successive object records until the explicit noone ID terminator breaks the loop below.
		Each nonterminator ID is followed by the complete object field sequence */
		while (true)
		{
			/* Packet object ID identifies a persistent collision object rather than its current array
			position */
			var collision_object_id = net.read(TYPE_ID);

			/* The noone sentinel ends the body before any further object fields are read */
			if (collision_object_id == noone)
			{
				break;
			}

			/* object_kind selects rendering behavior. object_x and object_y are room coordinates,
			object_vx and object_vy are room pixels per physics update, and object_radius is the
			received room-pixel collision radius */
			var object_kind = net.read(buffer_u8);
			var object_x = net.read(TYPE_POSITION);
			var object_y = net.read(TYPE_POSITION);
			var object_vx = net.read(buffer_f32);
			var object_vy = net.read(buffer_f32);
			var object_radius = net.read(buffer_s16);

			/* collision_object_index locates an existing object by its persistent ID. obj will hold
			either that entry or the newly constructed record */
			var collision_object_index = find_object_index(collision_object_id);
			var obj;

			/* A previously unseen ID creates an object with visual_x and visual_y at the received x
			and y, avoiding interpolation from an unrelated starting point */
			if (collision_object_index == noone)
			{
				/* New object's id and kind come from the packet. x/y and visual_x/visual_y share the
				received position, vx/vy retain its motion, radius is at least one room pixel and
				active enables updates */
				obj =
				{
					id: collision_object_id,
					kind: object_kind,
					x: object_x,
					y: object_y,
					visual_x: object_x,
					visual_y: object_y,
					vx: object_vx,
					vy: object_vy,
					radius: max(1, object_radius),
					active: true
				};
				objects[array_length(objects)] = obj;
			}

			/* Known IDs update their physics fields while retaining visual_x and visual_y so the
			client can interpolate from the previously drawn position */
			else
			{
				obj = objects[collision_object_index];
				obj.kind = object_kind;
				obj.x = object_x;
				obj.y = object_y;
				obj.vx = object_vx;
				obj.vy = object_vy;
				obj.radius = max(1, object_radius);
				obj.active = true;
			}

			clamp_object_to_room(obj);
		}
	}
	#endregion /* Collision Object Packets END */

	#region /* Collision Object Rendering */
	/// @description Interpolate active collision-object draw positions toward received physics coordinates
	update_visuals = function()
	{
		/* i begins at storage index zero and updates every active object's visual position once */
		for (var i = 0; i < array_length(objects); i++)
		{
			/* Current object reference retains both the received position and the client's
			interpolated draw position */
			var obj = objects[i];

			/* Empty or inactive entries are excluded from visual interpolation just as from physics
			and packets */
			if (obj == noone || !obj.active)
			{
				continue;
			}

			/* dx and dy measure the remaining room-pixel gap between the draw position and the latest
			physics position */
			var dx = obj.x - obj.visual_x;
			var dy = obj.y - obj.visual_y;

			/* Within half a room pixel, snap visuals to the target rather than leaving a tiny
			interpolation tail */
			if (dx * dx + dy * dy <= 0.25)
			{
				obj.visual_x = obj.x;
				obj.visual_y = obj.y;
			}

			/* Larger gaps advance by visual_lerp_amount so sparse network updates do not cause
			immediate full-position jumps */
			else
			{
				obj.visual_x = lerp(obj.visual_x, obj.x, visual_lerp_amount);
				obj.visual_y = lerp(obj.visual_y, obj.y, visual_lerp_amount);
			}

			/* Radius-inset room limits clamp the interpolated center so the rendered ball also remains
			inside the room */
			var bounds = collision_object_room_bounds(obj.radius);
			obj.visual_x = clamp(obj.visual_x, bounds.left, bounds.right);
			obj.visual_y = clamp(obj.visual_y, bounds.top, bounds.bottom);
		}
	}

	/// @description Draw a soccer ball and its shadow at the interpolated position
	/// @param {Struct} obj Active ball record with radius and visual coordinates
	draw_ball = function(obj)
	{
		/* draw_x and draw_y are the interpolated room coordinates. draw_radius is the collision radius
		and sprite_scale makes the sprite diameter match that room-pixel size */
		var draw_x = obj.visual_x;
		var draw_y = obj.visual_y;
		var draw_radius = obj.radius;
		var sprite_scale = draw_radius * 2 / sprite_get_width(spr_soccerball);

		draw_set_alpha(0.28);
		draw_set_colour(c_black);
		draw_ellipse(draw_x - draw_radius * 0.88, draw_y + draw_radius * 0.62, draw_x + draw_radius * 0.88, draw_y + draw_radius * 1.04, false);
		draw_set_alpha(1);
		draw_sprite_ext(spr_soccerball, 0, draw_x, draw_y, sprite_scale, sprite_scale, 0, c_white, 1);
	}

	/// @description Restore default objects if needed, advance visuals and draw active supported kinds
	draw_world = function()
	{
		ensure_defaults();
		update_visuals();

		/* i traverses all stored objects in order and sends each active object to the renderer for its
		kind */
		for (var i = 0; i < array_length(objects); i++)
		{
			/* Current object reference supplies active state and kind before drawing */
			var obj = objects[i];

			/* Empty and inactive entries produce no world drawing */
			if (obj == noone || !obj.active)
			{
				continue;
			}

			/* Dispatch by collision-object kind so physics records can share the controller while
			using different artwork */
			switch (obj.kind)
			{
				case COLLISION_OBJECT_BALL:

					/* Ball records use the soccer-ball sprite and shadow. Other kinds have no renderer
					in this switch */
					draw_ball(obj);
					break;
			}
		}

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	#endregion /* Collision Object Rendering END */

}

/// @description Return the shared collision-object controller
/// @returns {Struct} Lazily constructed collision-object controller
function scr_get_collision_objects()
{
	/* Create the shared collision controller once so server, client and drawing callers use the same
	object collection */
	static controller = new scr_collision_objects();
	return controller;
}
