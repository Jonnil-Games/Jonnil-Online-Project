/// @description Own separate client and server wall-cell maps, derived tile surfaces, snapshot jobs, and persistent server state
function scr_walls() constructor
{
	cell_size = 4; /* Room pixels per collision cell, as required by version-1 saves */
	tile_cells = 64; /* Cells per cached tile edge */

	/* max_cells bounds each state to 65536 occupied cells, and max_segment_length caps a network stroke part at 512 room pixels */
	max_cells = 65536;
	max_segment_length = 512;

	/* Client walls start disabled and not ready until server policy and a complete snapshot permit them
	client_snapshot_active tracks a started transfer, while server_active starts false until hosting begins */
	client_enabled = false;
	client_ready = false;
	client_snapshot_active = false;
	server_active = false;

	/* server_dirty marks changes needing persistence, next_save is a current_time millisecond deadline,
	and save_failed prevents overwriting unreadable or unprotected recovered saves */
	server_dirty = false;
	next_save = 0;
	save_failed = false;

	/* snapshot_jobs starts empty and holds socket-bound row/delta transfer cursors
	rate_windows/rate_counts/rate_sockets are parallel zero-based server-slot arrays for one-second edit-rate windows */
	snapshot_jobs = [];
	rate_windows = [];
	rate_counts = [];
	rate_sockets = [];

	/* contact_until zero disables the contact flash, and contact_x/contact_y retain its room-pixel centre
	next_notice zero permits the first warning immediately, and persistence_file names the version-one wall save in local game storage */
	contact_until = 0;
	contact_x = 0;
	contact_y = 0;
	next_notice = 0;
	persistence_file = "server_walls.json";

	#region /* Wall State Lifecycle */
	/// @description Create independent owned cell/tile maps with empty cache metadata
	/// @returns {Struct} Wall state. clear_state retains its maps for reuse
	make_state = function()
	{
		/* Each state owns its cells and tiles ds_maps, starts with zero occupied cells, and has an empty cached tile-key list
		Cell entries hold RGB colours, tile entries hold derived surface metadata, and cached records the preceding visible tiles */
		return { cells: ds_map_create(), tiles: ds_map_create(), count: 0, cached: [] };
	}

	/* Create separate client and authoritative server states so server validation never depends on client rendering */
	client_state = make_state();
	server_state = make_state();

	/// @description Clear a wall state and free its cached tile surfaces while retaining the state-owned maps
	/// @param {Struct} state Wall state returned by make_state
	clear_state = function(state)
	{
		/* Begin at the first tile-map key so every state-owned cached surface can be released */
		var tile_key = ds_map_find_first(state.tiles);

		/* Visit tile-map entries until enumeration ends, retaining the maps themselves for reuse */
		while (!is_undefined(tile_key))
		{
			/* Borrow the current tile's metadata before releasing its owned surface */
			var tile = state.tiles[? tile_key];

			/* Free only a still-existing tile surface, allowing cleanup after surface loss */
			if (surface_exists(tile.surface)) surface_free(tile.surface);
			tile_key = ds_map_find_next(state.tiles, tile_key);
		}
		ds_map_clear(state.cells);
		ds_map_clear(state.tiles);
		state.count = 0;
		state.cached = [];
	}

	/// @description Read the client's singleplayer state
	/// @returns {Bool} Whether a usable client is in singleplayer mode
	is_offline = function()
	{
		/* Borrow the client controller to determine whether wall operations are local singleplayer work */
		var client = scr_get_client();

		/* Check the client type before reading its singleplayer flag */
		return is_struct(client) && client.singleplayer_mode;
	}

	/// @description Check offline permission or ready enabled online policy
	/// @returns {Bool} Whether drawing is currently permitted
	can_draw = function()
	{
		/* Offline editing is permitted immediately, while online drawing requires enabled policy and a complete wall snapshot */
		return is_offline() || (client_enabled && client_ready);
	}

	/// @description Set client wall policy using equality with true
	/// @param {Bool} enabled Requested policy
	set_client_enabled = function(enabled)
	{
		/* Accept only a value equal to true as the enabled client policy */
		client_enabled = enabled == true;
	}

	/// @description Clear client cells, readiness, policy and contact feedback
	reset_client = function()
	{
		clear_state(client_state);
		client_ready = false;
		client_snapshot_active = false;
		client_enabled = false;
		contact_until = 0;
	}
	#endregion /* Wall State Lifecycle END */

	#region /* Wall Grid and Collision */
	/* Cell and tile keys pack grid coordinates using the strides below */
	/// @description Pack grid coordinates with the 16384-cell row stride
	/// @param {Real} cx Cell column
	/// @param {Real} cy Cell row
	/// @returns {Real} Cell-map key
	cell_key = function(cx, cy) { return cy * 16384 + cx; }
	/// @description Pack the containing tile coordinates with the 256-tile row stride
	/// @param {Real} cx Cell column
	/// @param {Real} cy Cell row
	/// @returns {Real} Tile-map key
	tile_key_at = function(cx, cy) { return (cy div tile_cells) * 256 + (cx div tile_cells); }
	/// @description Check numeric integer cell coordinates against room and packed-grid bounds
	/// @param {Real} cx Cell column
	/// @param {Real} cy Cell row
	/// @returns {Bool} Whether the cell can be stored
	valid_cell = function(cx, cy)
	{
		/* Require numeric integer cell coordinates inside the room grid and below the 16384 coordinate stride
		Type checks precede floor and bounds operations */
		return is_real(cx) && is_real(cy) && cx == floor(cx) && cy == floor(cy)
			&& cx >= 0 && cy >= 0 && cx < min(16384, ceil(room_width / cell_size))
			&& cy < min(16384, ceil(room_height / cell_size));
	}

	/// @description Invalidate existing tile metadata at nonnegative neighbor coordinates
	/// @param {Struct} state Owned wall state
	/// @param {Real} cx Cell column
	/// @param {Real} cy Cell row
	mark_tile_dirty = function(state, cx, cy)
	{
		/* Negative neighbor coordinates cannot identify a valid tile and are skipped */
		if (cx < 0 || cy < 0) return;

		/* Convert the cell coordinates to the containing tile's packed map key */
		var key = tile_key_at(cx, cy);

		/* Only existing tile metadata needs invalidation, avoiding allocation for empty neighbors */
		if (ds_map_exists(state.tiles, key)) state.tiles[? key].dirty = true;
	}

	/// @description Insert, recolour or erase one cell and invalidate neighboring tile boundaries
	/// @param {Struct} state Wall state to edit
	/// @param {Real} cx Cell column
	/// @param {Real} cy Cell row
	/// @param {Real} colour RGB value trusted by the caller
	/// @param {Bool} erase Remove the cell instead of storing colour
	/// @returns {Bool} Whether occupancy or colour changed
	put_cell = function(state, cx, cy, colour, erase)
	{
		/* Reject cells outside the validated grid before accessing cell or tile maps */
		if (!valid_cell(cx, cy)) return false;

		/* key is the row-major packed cell coordinate and existed records whether the map already contains that cell */
		var key = cell_key(cx, cy);
		var existed = ds_map_exists(state.cells, key);

		/* Erasing an absent cell changes nothing and needs no tile work */
		if (erase && !existed) return false;

		/* Drawing rejects a new cell above capacity or an existing cell already holding the requested colour */
		if (!erase && ((!existed && state.count >= max_cells)
			|| (existed && state.cells[? key] == colour))) return false;

		/* Identify the cell's containing tile for count tracking and surface invalidation */
		var tile_key = tile_key_at(cx, cy);

		/* Create metadata only for a tile receiving its first relevant edit
		x/y are zero-based tile coordinates, surface starts unallocated, dirty requests a rebuild, and count starts at zero */
		if (!ds_map_exists(state.tiles, tile_key))
		{
			state.tiles[? tile_key] = { x: cx div tile_cells, y: cy div tile_cells,
				surface: noone, dirty: true, count: 0 };
		}

		/* Borrow the containing tile so its count and dirty flag follow the cell edit */
		var tile = state.tiles[? tile_key];

		/* Erase removes the cell and decrements both global occupied count and tile count */
		if (erase)
		{
			ds_map_delete(state.cells, key);
			state.count--;
			tile.count--;
		}

		/* Drawing stores the colour, incrementing counts only for a newly occupied cell */
		else
		{
			state.cells[? key] = colour;

			/* Replacing colour on an existing cell leaves occupancy counts unchanged */
			if (!existed) { state.count++; tile.count++; }
		}
		tile.dirty = true;
		mark_tile_dirty(state, cx - 1, cy);
		mark_tile_dirty(state, cx + 1, cy);
		mark_tile_dirty(state, cx, cy - 1);
		mark_tile_dirty(state, cx, cy + 1);

		/* An empty tile no longer needs metadata or a cached surface */
		if (tile.count <= 0)
		{
			/* Release an empty tile's still-existing surface before deleting its map entry */
			if (surface_exists(tile.surface)) surface_free(tile.surface);
			ds_map_delete(state.tiles, tile_key);
		}
		return true;
	}

	/// @description Measure point-to-segment squared distance without a zero-length division
	/// @param {Real} px Point horizontal room coordinate
	/// @param {Real} py Point vertical room coordinate
	/// @param {Real} x1 First endpoint horizontal coordinate
	/// @param {Real} y1 First endpoint vertical coordinate
	/// @param {Real} x2 Second endpoint horizontal coordinate
	/// @param {Real} y2 Second endpoint vertical coordinate
	/// @returns {Real} Squared room-pixel distance
	segment_distance_squared = function(px, py, x1, y1, x2, y2)
	{
		/* dx/dy describe the segment direction, and length_squared is its squared room-pixel length */
		var dx = x2 - x1;
		var dy = y2 - y1;
		var length_squared = dx * dx + dy * dy;

		/* For a nonzero segment, project the point and clamp its fraction to the segment endpoints
		A zero-length segment uses its first endpoint without division */
		var along = length_squared > 0 ? clamp(((px - x1) * dx + (py - y1) * dy) / length_squared, 0, 1) : 0;

		/* ex/ey are the point's displacement from the nearest projected segment point, used for squared distance */
		var ex = px - (x1 + along * dx);
		var ey = py - (y1 + along * dy);
		return ex * ex + ey * ey;
	}

	/// @description Rasterize a trusted stroke onto the shared cell-centre grid
	/// @param {Struct} state Wall state to edit
	/// @param {Struct} edit erase, width, colour and room-pixel x1/y1/x2/y2
	/// @returns {Bool} Whether any cell changed
	apply_segment = function(state, edit)
	{
		/* Snap both stroke endpoints to four-pixel cell centers in room space so
		authoritative and client occupancy use the same grid. This keeps collision
		physics independent of GPU surfaces */
		var x1 = floor(edit.x1 / cell_size) * cell_size + cell_size * 0.5;
		var y1 = floor(edit.y1 / cell_size) * cell_size + cell_size * 0.5;
		var x2 = floor(edit.x2 / cell_size) * cell_size + cell_size * 0.5;
		var y2 = floor(edit.y2 / cell_size) * cell_size + cell_size * 0.5;

		/* Use half the brush width with at least half a cell, covering a cell-centred point stroke */
		var radius = max(cell_size * 0.5, edit.width * 0.5);

		/* left/top/right/bottom bound the candidate cell rectangle around both endpoints and radius, clipped to the room grid */
		var left = max(0, floor((min(x1, x2) - radius) / cell_size));
		var top = max(0, floor((min(y1, y2) - radius) / cell_size));
		var right = min(ceil(room_width / cell_size) - 1, floor((max(x1, x2) + radius) / cell_size));
		var bottom = min(ceil(room_height / cell_size) - 1, floor((max(y1, y2) + radius) / cell_size));

		/* Start with no cell change and retain true once any put_cell edit succeeds */
		var changed = false;

		/* Traverse inclusive candidate cell rows using zero-based cy */
		for (var cy = top; cy <= bottom; cy++)
		{
			/* Visit inclusive columns in the current candidate row using zero-based cx */
			for (var cx = left; cx <= right; cx++)
			{
				/* Edit only cells whose centres lie within or on the stroke radius */
				if (segment_distance_squared(cx * cell_size + cell_size * 0.5,
					cy * cell_size + cell_size * 0.5, x1, y1, x2, y2) <= radius * radius)
				{
					/* A successful cell insertion, recolour or erase marks the overall stroke changed */
					if (put_cell(state, cx, cy, edit.colour, edit.erase)) changed = true;
				}
			}
		}
		return changed;
	}

	/// @description Test a circle against occupied wall cells. Disabled or incomplete online wall state does not block
	/// @param {Real} px Circle center horizontal position in room pixels
	/// @param {Real} py Circle center vertical position in room pixels
	/// @param {Real} radius Circle radius in room pixels
	/// @param {Bool} use_server Whether to use authoritative server state, defaulting to false for client state
	/// @returns {Bool} Whether an enabled wall cell intersects the circle
	circle_overlaps = function(px, py, radius, use_server = false)
	{
		/* Server collision requires active authoritative walls and the server's drawing policy */
		if (use_server)
		{
			/* Inactive hosting or disabled server wall policy makes authoritative walls nonblocking */
			if (!server_active || !scr_get_server().wall_drawing_enabled) return false;
		}

		/* Online client collision waits for both enabled policy and a complete snapshot, while offline state can block immediately */
		else if (!is_offline() && (!client_enabled || !client_ready)) return false;

		/* Select authoritative or client maps according to use_server */
		var state = use_server ? server_state : client_state;

		/* An empty cell map cannot block the circle */
		if (state.count <= 0) return false;

		/* tile_pixels converts a cached tile edge to room pixels, and nearby starts false for the coarse occupancy test */
		var tile_pixels = tile_cells * cell_size;
		var nearby = false;

		/* Scan tile rows crossed by the circle's bounds before the more expensive per-cell test */
		for (var ty = max(0, floor((py - radius) / tile_pixels)); ty <= floor((py + radius) / tile_pixels); ty++)

			/* Scan each candidate tile column within those bounds */
			for (var tx = max(0, floor((px - radius) / tile_pixels)); tx <= floor((px + radius) / tile_pixels); tx++)

				/* Any existing nearby tile permits the precise cell test */
				if (ds_map_exists(state.tiles, ty * 256 + tx)) nearby = true;

		/* Without nearby tile metadata, return immediately because no occupied cell can intersect */
		if (!nearby) return false;

		/* Clip the circle's candidate left/top/right/bottom cell coordinates to the room grid */
		var left = max(0, floor((px - radius) / cell_size));
		var top = max(0, floor((py - radius) / cell_size));
		var right = min(ceil(room_width / cell_size) - 1, floor((px + radius) / cell_size));
		var bottom = min(ceil(room_height / cell_size) - 1, floor((py + radius) / cell_size));

		/* Traverse inclusive candidate cell rows */
		for (var cy = top; cy <= bottom; cy++)
		{
			/* Traverse inclusive candidate cell columns within each row */
			for (var cx = left; cx <= right; cx++)
			{
				/* Skip empty cells before measuring their distance from the circle */
				if (!ds_map_exists(state.cells, cell_key(cx, cy))) continue;

				/* dx/dy measure the circle centre's displacement from its nearest point inside the occupied cell rectangle */
				var dx = px - clamp(px, cx * cell_size, (cx + 1) * cell_size);
				var dy = py - clamp(py, cy * cell_size, (cy + 1) * cell_size);

				/* Block only when squared distance is strictly inside the radius, allowing exact tangency */
				if (dx * dx + dy * dy < radius * radius) return true;
			}
		}
		return false;
	}

	/// @description Blend nearby incoming wall contacts into an outward circle normal for contour sliding
	/// @param {Real} px Accepted circle center horizontal position in room pixels
	/// @param {Real} py Accepted circle center vertical position in room pixels
	/// @param {Real} radius Circle radius in room pixels
	/// @param {Real} move_x Requested horizontal substep in room pixels
	/// @param {Real} move_y Requested vertical substep in room pixels
	/// @param {Bool} use_server Whether to use authoritative server walls, default false
	/// @returns {Struct} Unit x/y outward normal, or zero x/y when no incoming contacts provide a direction
	circle_contact_normal = function(px, py, radius, move_x, move_y, use_server = false)
	{
		/* The same policy and snapshot checks as circle_overlaps keep disabled or unfinished walls
		from steering a player on either side of the network */
		if (use_server)
		{
			if (!server_active || !scr_get_server().wall_drawing_enabled) return { x: 0, y: 0 };
		}
		else if (!is_offline() && (!client_enabled || !client_ready)) return { x: 0, y: 0 };

		var state = use_server ? server_state : client_state;
		if (state.count <= 0) return { x: 0, y: 0 };

		/* An eight-room-pixel halo blends adjacent four-pixel staircase facets instead of choosing
		one cell's axis. Exact circle tests still decide whether any resulting travel is safe */
		var search_radius = radius + cell_size * 2;
		var left = max(0, floor((px - search_radius) / cell_size));
		var top = max(0, floor((py - search_radius) / cell_size));
		var right = min(ceil(room_width / cell_size) - 1, floor((px + search_radius) / cell_size));
		var bottom = min(ceil(room_height / cell_size) - 1, floor((py + search_radius) / cell_size));
		var normal_x = 0;
		var normal_y = 0;

		/* Only blocked movement requests call this bounded cell scan. Closest-point directions use
		the same cell rectangles as circle_overlaps, including their corners */
		for (var cy = top; cy <= bottom; cy++)
		{
			for (var cx = left; cx <= right; cx++)
			{
				if (!ds_map_exists(state.cells, cell_key(cx, cy))) continue;
				var dx = px - clamp(px, cx * cell_size, (cx + 1) * cell_size);
				var dy = py - clamp(py, cy * cell_size, (cy + 1) * cell_size);
				var distance_squared = dx * dx + dy * dy;

				/* Ignore undefined directions, distant cells and contacts the input moves away from.
				A wall behind the player must not cancel the wall they are pressing into */
				if (distance_squared <= 0 || distance_squared >= search_radius * search_radius
				|| dx * move_x + dy * move_y >= 0) continue;
				var contact_distance = sqrt(distance_squared);
				var proximity = search_radius - contact_distance;
				var weight = proximity * proximity / contact_distance;
				normal_x += dx * weight;
				normal_y += dy * weight;
			}
		}

		/* Opposing or absent contacts have no stable tangent. Leave the ordinary axis fallback to
		handle those cases rather than inventing a slide direction */
		var normal_length = sqrt(normal_x * normal_x + normal_y * normal_y);
		if (normal_length <= 0.0001) return { x: 0, y: 0 };
		return { x: normal_x / normal_length, y: normal_y / normal_length };
	}

	/// @description Begin a 160-millisecond nearby-wall collision flash
	/// @param {Real} px Collision centre in room pixels
	/// @param {Real} py Collision centre in room pixels
	note_contact = function(px, py)
	{
		/* Store the collision's room-pixel centre and flash nearby occupied cells for 160 current_time milliseconds */
		contact_x = px;
		contact_y = py;
		contact_until = current_time + 160;
	}
	#endregion /* Wall Grid and Collision END */

	#region /* Wall Edit Protocol */
	/// @description Append a 15-byte wall edit body to the already-started network writer. read_edit must use the same field order
	/// @param {Struct} edit erase, width, colour, x1, y1, x2, and y2. Lengths and coordinates are room pixels
	write_edit = function(edit)
	{
		/* Borrow the shared packet writer for the fixed wall-edit field order */
		var net = scr_get_network();

		/* Encode erase as numeric one or zero, followed by pixel width, RGB colour and both room-pixel endpoints */
		net.write(buffer_u8, edit.erase ? 1 : 0);
		net.write(buffer_u16, edit.width);
		net.write(buffer_u32, edit.colour);
		net.write(buffer_u16, edit.x1);
		net.write(buffer_u16, edit.y1);
		net.write(buffer_u16, edit.x2);
		net.write(buffer_u16, edit.y2);
	}

	/// @description Validate exactly one wall edit from the current network reader position
	/// @returns {Struct} Validated edit, or noone for a wrong body size or out-of-range field
	read_edit = function()
	{
		/* Borrow the primed shared reader for one fixed-size wall edit */
		var net = scr_get_network();

		/* Require exactly the 15-byte body before consuming any wall fields */
		if (net.reader_size - buffer_tell(net.reader_buffer) != 15) return noone;

		/* erase_value is the raw flag byte, while edit stores the interpreted flag, brush width, RGB colour and endpoint coordinates */
		var erase_value = net.read(buffer_u8);
		var edit = { erase: erase_value == 1, width: net.read(buffer_u16), colour: net.read(buffer_u32),
			x1: net.read(buffer_u16), y1: net.read(buffer_u16), x2: net.read(buffer_u16), y2: net.read(buffer_u16) };

		/* Accept only flags zero/one, RGB within 24 bits, room-bounded endpoints and a bounded segment length
		Drawing widths range 4–32 pixels, while erasing permits 1–96 pixels */
		if (erase_value > 1 || edit.width < (edit.erase ? 1 : 4) || edit.width > (edit.erase ? 96 : 32) || edit.colour > $ffffff
			|| edit.x1 >= room_width || edit.x2 >= room_width || edit.y1 >= room_height || edit.y2 >= room_height
			|| point_distance(edit.x1, edit.y1, edit.x2, edit.y2) > max_segment_length + 2) return noone;
		return edit;
	}

	/// @description Show wall status at most once per current_time second
	/// @param {String} message Warning text
	notice = function(message)
	{
		/* Suppress repeated wall warnings until their one-second current_time cooldown expires */
		if (current_time < next_notice) return;
		next_notice = current_time + 1000;
		scr_get_drawing().set_screenshot_status(message, make_color_rgb(255, 220, 95));
	}

	/// @description Apply a wall stroke offline or send bounded stroke parts online. Online state waits for server updates
	/// @param {Real} x1 Stroke start horizontal room coordinate in pixels
	/// @param {Real} y1 Stroke start vertical room coordinate in pixels
	/// @param {Real} x2 Stroke end horizontal room coordinate in pixels
	/// @param {Real} y2 Stroke end vertical room coordinate in pixels
	/// @param {Real} width Brush width in room pixels, clamped to the protocol limits
	/// @param {Real} colour RGB color masked to 24 bits
	/// @param {Bool} erase Whether this stroke removes occupied cells, defaulting to false for painting
	/// @returns {Bool} Whether stroke dispatch completed. A later failed part can leave earlier parts sent
	send_segment = function(x1, y1, x2, y2, width, colour, erase = false)
	{
		/* Online editing waits for the complete wall snapshot before dispatching either draw or erase */
		if (!is_offline() && !client_ready) { notice("Walls are still loading."); return false; }

		/* Drawing needs enabled policy, while erasing is still allowed once online walls are ready */
		if (!erase && !can_draw()) { notice("Wall drawing is disabled by the server."); return false; }
		x1 = clamp(round(x1), 0, min(65535, room_width - 1));
		y1 = clamp(round(y1), 0, min(65535, room_height - 1));
		x2 = clamp(round(x2), 0, min(65535, room_width - 1));
		y2 = clamp(round(y2), 0, min(65535, room_height - 1));

		/* At the client cell cap, reject drawing before dispatch and advise erasing existing walls */
		if (!erase && client_state.count >= max_cells) { notice("Wall limit reached. Erase some walls first."); return false; }

		/* Split the room-pixel stroke into at least one part, each bounded by the 512-pixel segment limit */
		var parts = max(1, ceil(point_distance(x1, y1, x2, y2) / max_segment_length));

		/* Avoid turning a camera jump into an unbounded network burst */
		if (parts > 16) { notice("Move the wall brush in shorter strokes."); return false; }

		/* Borrow the shared writer for online parts, with offline parts applied directly below */
		var net = scr_get_network();

		/* Dispatch every zero-based interpolated stroke part in order */
		for (var part = 0; part < parts; part++)
		{
			/* Each part stores the erase flag, clamped draw/erase width, masked RGB and interpolated integer room-pixel endpoints */
			var edit = { erase: erase, width: clamp(round(width), erase ? 1 : 4, erase ? 96 : 32), colour: colour & $ffffff,
				x1: round(lerp(x1, x2, part / parts)), y1: round(lerp(y1, y2, part / parts)),
				x2: round(lerp(x1, x2, (part + 1) / parts)), y2: round(lerp(y1, y2, (part + 1) / parts)) };

			/* Offline parts update local occupancy immediately */
			if (is_offline()) apply_segment(client_state, edit);

			/* Online parts carry the local player ID and wait for authoritative server updates instead of changing client cells directly */
			else
			{
				net.start(N_WALL_EDIT, scr_get_client().ID);
				write_edit(edit);

				/* Stop at a failed part send, while earlier successfully dispatched parts remain sent */
				if (net.send_server() < 0) return false;
			}
		}
		return true;
	}
	#endregion /* Wall Edit Protocol END */

	#region /* Snapshot Transfer */
	/// @description Find the first queued snapshot for a player slot
	/// @param {Real} slot Zero-based server player slot
	/// @returns {Real} Job index, or noone
	job_index = function(slot)
	{
		/* Search zero-based queued snapshot jobs for this player slot */
		for (var i = 0; i < array_length(snapshot_jobs); i++)

			/* Return the first matching index, or noone below when no job exists */
			if (snapshot_jobs[i].slot == slot) return i;
		return noone;
	}

	/// @description Copy occupied cells into serialized row arrays
	/// @param {Struct} state Wall state to read
	/// @returns {Array} Independent [cell_x, cell_y, RGB] rows
	state_rows = function(state)
	{
		/* rows starts empty for serialized [cell_x, cell_y, RGB] entries, and key begins at the first occupied map cell */
		var rows = [];
		var key = ds_map_find_first(state.cells);

		/* Visit every occupied cell key and unpack its 16384-stride coordinates into snapshot rows */
		while (!is_undefined(key))
		{
			rows[array_length(rows)] = [key mod 16384, key div 16384, state.cells[? key]];
			key = ds_map_find_next(state.cells, key);
		}
		return rows;
	}

	/// @description Capture wall rows for a live server slot and replace its previous snapshot job. Later edits queue behind the rows
	/// @param {Real} slot Player slot whose current socket will receive the snapshot
	server_queue_snapshot = function(slot)
	{
		/* Borrow authoritative slot/socket state before capturing a new wall snapshot */
		var server = scr_get_server();

		/* Check slot bounds before reading its socket, and queue only a live connected slot */
		if (slot < 0 || slot >= array_length(server.sockets) || server.sockets[slot] == noone) return;

		/* Locate an earlier job for this player slot so a new snapshot can replace it */
		var previous = job_index(slot);

		/* Remove an existing slot job before appending the fresh snapshot */
		if (previous != noone) array_delete(snapshot_jobs, previous, 1);

		/* Bind the job to slot and current socket, capture current rows, and start its row cursor at zero
		started false requires the clear marker first, while empty deltas and delta_cursor zero track later edits */
		snapshot_jobs[array_length(snapshot_jobs)] = { slot: slot, socket: server.sockets[slot],
			rows: state_rows(server_state), cursor: 0, started: false, deltas: [], delta_cursor: 0 };
	}

	/// @description Send a trusted wall edit through this live slot's transport
	/// @param {Real} slot Valid live server slot
	/// @param {Struct} edit Trusted wall edit
	/// @returns {Real} Network send result, negative on failure
	send_edit_to_slot = function(slot, edit)
	{
		/* net borrows the shared writer and server supplies this slot's socket and transport */
		var net = scr_get_network();
		var server = scr_get_server();
		net.start(N_WALL_EDIT, noone);
		write_edit(edit);
		return net.send(server.sockets[slot], true, server.slot_transports[slot]);
	}

	/// @description Validate and rate-limit a client wall edit, update authoritative cells, and relay it or queue it behind active snapshots
	/// @param {Real} slot Authenticated server player slot supplied by the packet handler
	/// @returns {Bool} Whether the edit was accepted, including an edit that changes no cells
	receive_edit = function(slot)
	{
		/* edit is the validated reader body or noone, and server supplies authoritative policy and live sockets */
		var edit = read_edit();
		var server = scr_get_server();

		/* Require an active server, valid edit, bounded live slot and enabled drawing for non-erase operations */
		if (!server_active || edit == noone || slot < 0 || slot >= array_length(server.sockets)
			|| server.sockets[slot] == noone || (!edit.erase && !server.wall_drawing_enabled)) return false;

		/* Initialize a missing slot's rate state or replace it when the socket changed
		The window starts at current_time, its count starts zero, and the socket binding prevents a new occupant inheriting an old limit */
		if (slot >= array_length(rate_windows) || rate_sockets[slot] != server.sockets[slot])
		{
			rate_windows[slot] = current_time;
			rate_counts[slot] = 0;
			rate_sockets[slot] = server.sockets[slot];
		}

		/* After one second, begin a fresh rate window and reset its edit count */
		if (current_time - rate_windows[slot] >= 1000) { rate_windows[slot] = current_time; rate_counts[slot] = 0; }

		/* Reject requests above 120 edits in the current one-second slot window */
		if (++rate_counts[slot] > 120) return false;

		/* A valid no-change edit is accepted without persistence, activity or broadcast work */
		if (!apply_segment(server_state, edit)) return true;
		server_dirty = true;
		server.note_client_gameplay_activity(slot);

		/* Visit every zero-based server slot to relay the changed edit or queue it behind a pending snapshot */
		for (var target_slot = 0; target_slot < array_length(server.sockets); target_slot++)
		{
			/* Skip empty target slots before snapshot lookup or sending */
			if (server.sockets[target_slot] == noone) continue;

			/* Find this target slot's queued snapshot so later edits cannot overtake its captured rows */
			var index = job_index(target_slot);

			/* A target still receiving its snapshot accumulates edits in that job's delta queue */
			if (index != noone)
			{
				/* Borrow the queued target job before checking its bounded delta backlog */
				var job = snapshot_jobs[index];

				/* At 2048 queued deltas, replace the job with a fresh current-state snapshot instead of growing the backlog */
				if (array_length(job.deltas) >= 2048) server_queue_snapshot(target_slot);

				/* Below the delta cap, append this edit after the captured rows */
				else job.deltas[array_length(job.deltas)] = edit;
			}

			/* Targets without a snapshot receive the edit immediately, and a failed send closes only that client slot */
			else if (send_edit_to_slot(target_slot, edit) < 0)
				server.close_client_slot(target_slot, "wall update send failed", true, true);
		}
		return true;
	}

	/// @description Apply a validated incoming edit to client cells and ignore malformed bodies
	receive_edit_client = function()
	{
		/* Read a validated server wall edit before touching client cells */
		var edit = read_edit();

		/* Apply only an accepted edit body, ignoring malformed data */
		if (edit != noone) apply_segment(client_state, edit);
	}

	/// @description Consume a wall snapshot phase from the current reader. Phase 0 clears, phase 1 adds rows, and phase 2 permits movement and drawing
	/// @returns {Bool} Whether the phase body and sequencing were accepted
	receive_snapshot = function()
	{
		/* Borrow the shared reader for a single snapshot phase */
		var net = scr_get_network();

		/* Require the phase byte before consuming it */
		if (!net.can_read_fields([buffer_u8])) return false;

		/* phase selects clear, rows or ready, and remaining counts body bytes after that flag */
		var phase = net.read(buffer_u8);
		var remaining = net.reader_size - buffer_tell(net.reader_buffer);

		/* An empty clear phase resets client cells and starts a snapshot with movement/drawing readiness disabled */
		if (phase == 0 && remaining == 0)
		{
			clear_state(client_state);
			client_ready = false;
			client_snapshot_active = true;
			return true;
		}

		/* Rows and ready markers need a preceding accepted clear phase */
		if (!client_snapshot_active) return false;

		/* An empty ready phase ends the active transfer and enables use of the received wall state */
		if (phase == 2 && remaining == 0) { client_ready = true; client_snapshot_active = false; return true; }

		/* Only row phases with a count field may extend a snapshot that is not already ready */
		if (phase != 1 || remaining < 2 || client_ready) return false;

		/* Read the declared number of eight-byte cell-coordinate/RGB rows */
		var count = net.read(buffer_u16);

		/* Enforce the 256-row chunk cap, exact body length and conservative total-cell budget before allocating rows */
		if (count > 256 || remaining != 2 + count * 8 || client_state.count + count > max_cells) return false;

		/* Stage validated rows separately so a malformed row rejects this whole chunk before changing client cells */
		var rows = [];

		/* Validate every zero-based incoming row in the staged chunk */
		for (var i = 0; i < count; i++)
		{
			/* cx/cy are cell coordinates, and colour is the incoming 32-bit value restricted to 24-bit RGB */
			var cx = net.read(buffer_u16);
			var cy = net.read(buffer_u16);
			var colour = net.read(buffer_u32);

			/* Reject out-of-grid cells and colour values outside RGB before storing the row */
			if (!valid_cell(cx, cy) || colour > $ffffff) return false;
			rows[i] = [cx, cy, colour];
		}

		/* Only after all rows pass validation, apply every staged entry to client occupancy */
		for (var i = 0; i < count; i++) put_cell(client_state, rows[i][0], rows[i][1], rows[i][2], false);
		return true;
	}
	#endregion /* Snapshot Transfer END */

	#region /* Persistent Wall State */
	/// @description Verify a pending version-1 wall save before replacing the primary file and retain the backup for recovery
	/// @returns {Bool} Whether saving succeeded or no save was needed. save_failed prevents overwriting unreadable saves
	save_server = function()
	{
		/* Clean state needs no write, while save_failed blocks all writes to protect unreadable or unprotected recovery files
		The return is true only when saving has not been disabled */
		if (!server_dirty || save_failed) return !save_failed;

		/* pending stages the new text and backup retains the previous committed file
		handle starts at -1 until a writer is owned, and backup_created tracks whether this attempt moved the primary for rollback */
		var pending = persistence_file + ".pending";
		var backup = persistence_file + ".backup";
		var handle = -1;
		var backup_created = false;
		try
		{
			/* Serialize version one, the required cell size and occupied [x, y, RGB] rows into the staged file */
			var text = json_stringify({ version: 1, cell_size: cell_size, cells: state_rows(server_state) });
			handle = file_text_open_write(pending);

			/* A failed pending-file open cannot begin a verified save */
			if (handle < 0) throw "Could not open wall save.";
			file_text_write_string(handle, text);
			file_text_close(handle);
			handle = -1;

			/* Read the staged text back through the drawing persistence helper before replacing the committed file */
			var check = scr_get_drawing().server_history_persistence_read_text(pending);

			/* Require a successful read and exact serialized-text equality before backup or promotion */
			if (!check.ok || check.text != text) throw "Wall save verification failed.";

			/* Move an existing committed save to backup before promoting the staged replacement */
			if (file_exists(persistence_file))
			{
				/* Remove an older backup only when a current primary can replace it */
				if (file_exists(backup)) file_delete(backup);
				file_rename(persistence_file, backup);

				/* Confirm the primary moved and its backup exists before treating rollback as available */
				if (file_exists(persistence_file) || !file_exists(backup)) throw "Could not back up walls.";
				backup_created = true;
			}
			file_rename(pending, persistence_file);

			/* Read the newly promoted primary to verify the final path contains the exact staged text */
			var promoted = scr_get_drawing().server_history_persistence_read_text(persistence_file);

			/* A failed or mismatched promoted read enters rollback instead of clearing server_dirty */
			if (!promoted.ok || promoted.text != text) throw "Could not promote wall save.";
			server_dirty = false;
			return true;
		}

		/* A save exception attempts writer cleanup and backup restoration, then reports failure without clearing dirty state */
		catch(error)
		{
			/* Close a pending writer still owned at the failure point, ignoring secondary close errors */
			if (handle >= 0) { try { file_text_close(handle); } catch(close_error) { } }
			try
			{
				/* Delete a pending file only when a primary or backup remains, retaining the sole remaining copy otherwise */
				if ((file_exists(persistence_file) || file_exists(backup)) && file_exists(pending)) file_delete(pending);
			}

			/* Ignore a secondary pending-file cleanup failure so rollback is still attempted */
			catch(cleanup_error) { }
			try
			{
				/* Restore only the backup created by this save attempt, preventing replacement with an unrelated older backup */
				if (backup_created && file_exists(backup))
				{
					/* Remove a failed promoted primary before putting this attempt's previous save back in place */
					if (file_exists(persistence_file)) file_delete(persistence_file);
					file_rename(backup, persistence_file);
				}
			}

			/* Ignore a secondary restore exception and retain the failed-save result for the caller */
			catch(restore_error) { }
			debug_error("Could not save walls; previous save retained.");
			return false;
		}
	}

	/// @description Restore the first valid wall save in primary, backup, pending, then recovered order. Preserve recovered data before another save
	/// @returns {Bool} Whether a valid save was loaded or no save existed
	load_server = function()
	{
		/* recovery_file protects recovered content from later pending/backup replacement */
		var recovery_file = persistence_file + ".recovered";

		/* Search primary, committed backup, pending and protected recovery files in that
		order. Prefer the committed backup over an uncommitted, possibly failed reset */
		var paths = [persistence_file, persistence_file + ".backup", persistence_file + ".pending", recovery_file];

		/* found starts false and records whether any candidate exists, distinguishing a new server from unreadable saved data */
		var found = false;

		/* Try every zero-based recovery candidate until one complete valid state is found */
		for (var wall_save_index = 0; wall_save_index < array_length(paths); wall_save_index++)
		{
			/* Skip absent candidates without marking saved data unreadable */
			if (!file_exists(paths[wall_save_index])) continue;
			found = true;
			try
			{
				/* Read this candidate as text before validating its size and parsed fields */
				var read = scr_get_drawing().server_history_persistence_read_text(paths[wall_save_index]);

				/* Skip unreadable candidates and text above the four-MiB limit before JSON parsing */
				if (!read.ok || string_length(read.text) > 4194304) continue;

				/* Parse candidate JSON without changing authoritative occupancy until every stored row validates */
				var saved = json_parse(read.text);

				/* Require a struct with version one, matching cell size and a bounded cells array
				Check each field's existence and type before reading dependent data */
				if (!is_struct(saved) || !variable_struct_exists(saved, "version") || saved.version != 1
					|| !variable_struct_exists(saved, "cell_size") || saved.cell_size != cell_size
					|| !variable_struct_exists(saved, "cells") || !is_array(saved.cells)
					|| array_length(saved.cells) > max_cells) continue;

				/* Assume rows valid until the first malformed entry breaks the validation loop */
				var valid = true;

				/* Inspect every zero-based saved row before restoring any cell */
				for (var i = 0; i < array_length(saved.cells); i++)
				{
					/* Borrow the current candidate row for its coordinate and RGB checks */
					var row = saved.cells[i];

					/* Require exactly [cell_x, cell_y, RGB], valid integer room-grid coordinates and an integer 24-bit colour */
					if (!is_array(row) || array_length(row) != 3 || !valid_cell(row[0], row[1])
						|| !is_real(row[2]) || row[2] < 0 || row[2] > $ffffff || row[2] != floor(row[2]))
					{ valid = false; break; }
				}

				/* Reject the entire candidate if any row failed, then continue to the next recovery file */
				if (!valid) continue;

				/* Copy nonprimary data into the protected recovery path unless it already lives
				there. This prevents the next save from truncating a recovered pending file or
				replacing a recovered backup with a corrupt primary */
				if (wall_save_index > 0 && paths[wall_save_index] != recovery_file)
				{
					try
					{
						/* Remove an older protected copy before copying this selected valid recovery candidate */
						if (file_exists(recovery_file)) file_delete(recovery_file);
						file_copy(paths[wall_save_index], recovery_file);

						/* Read the protected recovery copy back to confirm it matches the accepted source text */
						var protected_save = scr_get_drawing().server_history_persistence_read_text(recovery_file);

						/* A failed or mismatched protection copy sets save_failed so future writes cannot overwrite the remaining recovery data */
						if (!protected_save.ok || protected_save.text != read.text) save_failed = true;
					}

					/* A protection-copy exception also disables future saving */
					catch(recovery_error) { save_failed = true; }

					/* Log that recovered data is usable in memory but existing save files will remain protected from writes */
					if (save_failed) debug_error("Recovered walls could not be backed up. Existing saves will not be overwritten.");
				}

				/* Restore every validated row only after complete validation and recovery protection attempts */
				for (var i = 0; i < array_length(saved.cells); i++)
					put_cell(server_state, saved.cells[i][0], saved.cells[i][1], saved.cells[i][2], false);

				/* Recovered nonprimary data stays dirty so a later permitted save can commit it to the primary path */
				server_dirty = wall_save_index > 0;
				return true;
			}

			/* Ignore one candidate's parsing or read exception and try the next recovery path */
			catch(error) { }
		}

		/* Existing candidates with no usable complete state disable saving to avoid overwriting unreadable evidence */
		if (found) { save_failed = true; debug_error("Wall save could not be read. Existing files will not be overwritten."); }

		/* No save files is a successful empty startup, while existing unreadable files report failure */
		return !found;
	}
	#endregion /* Persistent Wall State END */

	#region /* Server Lifecycle and Snapshot Dispatch */
	/// @description Clear transient server state, activate hosting and load persisted walls
	start_server = function()
	{
		clear_state(server_state);
		snapshot_jobs = [];
		rate_windows = [];
		rate_counts = [];
		rate_sockets = [];
		server_dirty = false;
		save_failed = false;
		server_active = true;

		/* Schedule the first periodic save five seconds from current_time before loading the existing authoritative state */
		next_save = current_time + 5000;
		load_server();
	}

	/// @description Attempt a final active-server save, then clear jobs and in-memory occupancy
	stop_server = function()
	{
		/* Attempt a final save only for an active server before clearing in-memory maps and pending jobs */
		if (server_active) save_server();
		server_active = false;
		snapshot_jobs = [];
		clear_state(server_state);
	}

	/// @description Commit an empty wall save before discarding the previous state and queuing snapshots for connected players
	/// @returns {Bool} Whether the empty save was committed
	reset_server = function()
	{
		/* Keep the old maps and cells available until the fresh empty state's save is committed */
		var previous_state = server_state;
		server_state = make_state();
		server_dirty = true;

		/* A failed empty save destroys only the newly allocated empty maps, restores the old state and leaves it dirty */
		if (!save_server())
		{
			ds_map_destroy(server_state.cells);
			ds_map_destroy(server_state.tiles);
			server_state = previous_state;
			server_dirty = true;
			return false;
		}
		clear_state(previous_state);
		ds_map_destroy(previous_state.cells);
		ds_map_destroy(previous_state.tiles);
		snapshot_jobs = [];

		/* Borrow connected server slots after the old state has been released and the empty save committed */
		var server = scr_get_server();

		/* Visit every zero-based slot to send a fresh empty snapshot to connected clients */
		for (var slot = 0; slot < array_length(server.sockets); slot++)

			/* Queue only live sockets, avoiding work for empty player slots */
			if (server.sockets[slot] != noone) server_queue_snapshot(slot);
		return true;
	}

	/// @description Advance snapshot rows, queued deltas, then the ready marker in order and periodically save dirty server walls
	server_update = function()
	{
		/* Inactive hosting skips snapshot dispatch and persistence scheduling */
		if (!server_active) return;

		/* server supplies live socket/transport state, and net is the shared packet writer */
		var server = scr_get_server();
		var net = scr_get_network();

		/* Allow up to four queued job turns per update, with each turn handling one phase or a bounded delta batch */
		var budget = 4;

		/* Continue only while this update has job-turn budget and pending snapshots remain */
		while (budget-- > 0 && array_length(snapshot_jobs) > 0)
		{
			/* Take the first queued job and remove it before processing so unfinished work can rotate to the queue's end */
			var job = snapshot_jobs[0];
			array_delete(snapshot_jobs, 0, 1);

			/* Discard jobs whose original slot/socket binding no longer matches the connected client */
			if (job.slot >= array_length(server.sockets) || server.sockets[job.slot] != job.socket) continue;

			/* finished starts false until the ready phase is sent, and sent starts zero for this turn's send result */
			var finished = false;
			var sent = 0;

			/* A fresh job first sends the clear phase before any captured row or later delta */
			if (!job.started)
			{
				net.start(N_WALL_SNAPSHOT, noone);
				net.write(buffer_u8, 0);
				job.started = true;
				sent = net.send(job.socket, true, server.slot_transports[job.slot]);
			}

			/* While captured rows remain, send the next bounded row chunk before queued live edits */
			else if (job.cursor < array_length(job.rows))
			{
				/* count caps this chunk at 256 rows without reading past the snapshot cursor */
				var count = min(256, array_length(job.rows) - job.cursor);
				net.start(N_WALL_SNAPSHOT, noone);
				net.write(buffer_u8, 1);
				net.write(buffer_u16, count);

				/* Write each zero-based row in this chunk while advancing the job's captured-row cursor */
				for (var i = 0; i < count; i++)
				{
					/* Borrow the next [cell_x, cell_y, RGB] row before serializing its eight-byte record */
					var row = job.rows[job.cursor++];
					net.write(buffer_u16, row[0]); net.write(buffer_u16, row[1]); net.write(buffer_u32, row[2]);
				}
				sent = net.send(job.socket, true, server.slot_transports[job.slot]);
			}

			/* After captured rows, dispatch queued live edits in their original order */
			else if (job.delta_cursor < array_length(job.deltas))
			{
				/* Send up to sixteen deltas this job turn, stopping if the backlog is exhausted */
				for (var i = 0; i < 16 && job.delta_cursor < array_length(job.deltas); i++)
				{
					sent = send_edit_to_slot(job.slot, job.deltas[job.delta_cursor++]);

					/* Stop the delta batch at its first failed send so common client cleanup can run */
					if (sent < 0) break;
				}
			}

			/* Only after rows and deltas are exhausted, send the ready marker and finish this job */
			else
			{
				net.start(N_WALL_SNAPSHOT, noone);
				net.write(buffer_u8, 2);
				sent = net.send(job.socket, true, server.slot_transports[job.slot]);
				finished = true;
			}

			/* A failed snapshot or delta send closes the bound client slot */
			if (sent < 0) server.close_client_slot(job.slot, "wall snapshot send failed", true, true);

			/* Successful unfinished jobs return to the queue's end, sharing update budget among clients */
			else if (!finished) snapshot_jobs[array_length(snapshot_jobs)] = job;
		}

		/* Dirty authoritative state saves only when its five-second current_time deadline is reached */
		if (server_dirty && current_time >= next_save)
		{
			next_save = current_time + 5000;
			save_server();
		}
	}
	#endregion /* Server Lifecycle and Snapshot Dispatch END */

	#region /* Wall Rendering and Export */
	/// @description Rebuild one owned cached tile surface from cell occupancy
	/// @param {Struct} state Wall state supplying colours
	/// @param {Struct} tile Tile metadata owning its surface
	/// @returns {Bool} Whether a surface exists and was rebuilt. Uses normal blending and alpha one
	build_tile = function(state, tile)
	{
		/* pixels is one cached tile edge in room pixels, derived from cell count times cell size */
		var pixels = tile_cells * cell_size;

		/* Allocate a missing tile-owned surface before rebuilding its contents */
		if (!surface_exists(tile.surface)) tile.surface = surface_create(pixels, pixels);

		/* A failed allocation leaves the tile dirty and reports that it cannot be drawn yet */
		if (!surface_exists(tile.surface)) return false;
		surface_set_target(tile.surface);
		draw_clear_alpha(c_black, 0);
		gpu_set_blendmode(bm_normal);
		draw_set_alpha(1);

		/* Traverse every zero-based row within the tile's cell grid */
		for (var row = 0; row < tile_cells; row++)
		{
			/* Visit each zero-based tile-local column */
			for (var col = 0; col < tile_cells; col++)
			{
				/* cx/cy convert tile-local positions to room-grid cells, and key packs them for occupancy lookup */
				var cx = tile.x * tile_cells + col;
				var cy = tile.y * tile_cells + row;
				var key = cell_key(cx, cy);

				/* Skip empty cells so they retain the cleared transparent tile background */
				if (!ds_map_exists(state.cells, key)) continue;

				/* colour is this occupied cell's RGB, while px/py locate its tile-local room-pixel rectangle */
				var colour = state.cells[? key];
				var px = col * cell_size;
				var py = row * cell_size;
				draw_set_colour(colour);
				draw_rectangle(px, py, px + cell_size, py + cell_size, false);

				/* Use black outlines above summed RGB brightness 382 and white outlines otherwise */
				var contrast = color_get_red(colour) + color_get_green(colour) + color_get_blue(colour) > 382 ? c_black : c_white;
				draw_set_colour(contrast);

				/* Draw the left boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx - 1, cy))) draw_line(px, py, px, py + cell_size);

				/* Draw the right boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx + 1, cy))) draw_line(px + cell_size - 1, py, px + cell_size - 1, py + cell_size);

				/* Draw the upper boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx, cy - 1))) draw_line(px, py, px + cell_size, py);

				/* Draw the lower boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx, cy + 1))) draw_line(px, py + cell_size - 1, px + cell_size, py + cell_size - 1);

				/* Every fourth diagonal cell parity adds a faint slash to distinguish wall artwork from ordinary drawing */
				if ((cx + cy) mod 4 == 0)
				{
					draw_set_alpha(0.55);
					draw_line(px + 1, py + cell_size - 1, px + cell_size - 1, py + 1);
					draw_set_alpha(1);
				}
			}
		}
		surface_reset_target();
		tile.dirty = false;
		return true;
	}

	/// @description Flatten room-pixel walls over the supplied drawing surface
	/// @param {Id.Surface} base_surface Borrowed drawing surface. This method does not free it
	/// @param {Bool} use_server Whether the export uses authoritative server walls, defaulting to false for client walls
	/// @returns {Id.Surface} The input surface when there are no cells, a new caller-owned surface otherwise, or noone on failure
	create_export_surface = function(base_surface, use_server = false)
	{
		/* Choose authoritative or client wall cells according to the requested export source */
		var state = use_server ? server_state : client_state;

		/* No walls returns the borrowed base surface directly, so the caller receives no new owned surface */
		if (state.count <= 0) return base_surface;

		/* A missing drawing base cannot be flattened with walls */
		if (!surface_exists(base_surface)) return noone;

		/* output starts unallocated, target_active tracks whether cleanup must reset a render target,
		and restore_alpha/colour/filter preserve the caller's drawing settings */
		var output = noone;
		var target_active = false;
		var restore_alpha = draw_get_alpha();
		var restore_colour = draw_get_colour();
		var restore_filter = gpu_get_texfilter();
		try
		{
			output = surface_create(surface_get_width(base_surface), surface_get_height(base_surface));

			/* Failed output allocation reports noone before changing the render target */
			if (!surface_exists(output)) return noone;
			surface_set_target(output);
			target_active = true;
			gpu_set_texfilter(false);
			draw_clear_alpha(c_black, 0);
			draw_set_alpha(1);
			draw_set_colour(c_white);
			gpu_set_blendmode_ext(bm_one, bm_zero);
			draw_surface(base_surface, 0, 0);
			gpu_set_blendmode(bm_normal);

			/* Server exports use authoritative policy, while client exports treat offline walls as enabled
			wall_alpha draws enabled walls fully opaque and disabled walls at 0.35 opacity */
			var enabled = use_server ? scr_get_server().wall_drawing_enabled : (client_enabled || is_offline());
			var wall_alpha = enabled ? 1 : 0.35;

			/* Begin at the first occupied wall cell in the chosen state */
			var key = ds_map_find_first(state.cells);

			/* Flatten every occupied cell into the new full-sized export surface */
			while (!is_undefined(key))
			{
				/* Unpack cx/cy from the cell key, borrow its RGB, and convert to room-pixel px/py for full-surface drawing */
				var cx = key mod 16384;
				var cy = key div 16384;
				var colour = state.cells[? key];
				var px = cx * cell_size;
				var py = cy * cell_size;
				draw_set_alpha(wall_alpha);
				draw_set_colour(colour);
				draw_rectangle(px, py, px + cell_size, py + cell_size, false);

				/* Choose a black or white cell boundary from the same RGB brightness threshold used by cached tiles */
				draw_set_colour(color_get_red(colour) + color_get_green(colour) + color_get_blue(colour) > 382 ? c_black : c_white);

				/* Draw the left boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx - 1, cy))) draw_line(px, py, px, py + cell_size);

				/* Draw the right boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx + 1, cy))) draw_line(px + cell_size - 1, py, px + cell_size - 1, py + cell_size);

				/* Draw the upper boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx, cy - 1))) draw_line(px, py, px + cell_size, py);

				/* Draw the lower boundary only when the neighboring cell is empty */
				if (!ds_map_exists(state.cells, cell_key(cx, cy + 1))) draw_line(px, py + cell_size - 1, px + cell_size, py + cell_size - 1);

				/* Every fourth diagonal cell parity adds a faint slash to distinguish wall artwork from ordinary drawing */
				if ((cx + cy) mod 4 == 0)
				{
					draw_set_alpha(wall_alpha * 0.55);
					draw_line(px + 1, py + cell_size - 1, px + cell_size - 1, py + 1);
				}
				key = ds_map_find_next(state.cells, key);
			}
			surface_reset_target();
			target_active = false;
		}

		/* On failure, reset an active target, release this operation's output surface and report noone */
		catch(error)
		{
			/* Reset the surface target only when failure occurred after it was set */
			if (target_active) surface_reset_target();

			/* Free an allocated output after failure while leaving the caller's base surface untouched */
			if (surface_exists(output)) surface_free(output);
			output = noone;
			debug_error("Could not include walls in the drawing export.");
		}
		gpu_set_blendmode(bm_normal);
		gpu_set_texfilter(restore_filter);
		draw_set_alpha(restore_alpha);
		draw_set_colour(restore_colour);
		return output;
	}

	/// @description Serialize wall rows for the browser flattened-export command stream
	/// @param {Bool} use_server Whether to export authoritative server walls, defaulting to false for client walls
	/// @returns {String} WALLS command containing cell size, drawing opacity, and cell-coordinate rows, or an empty string
	browser_export_commands = function(use_server = false)
	{
		/* Select authoritative or client wall rows for browser export */
		var state = use_server ? server_state : client_state;

		/* Empty wall state emits no command */
		if (state.count <= 0) return "";

		/* Server policy or client/offline availability selects full opacity, otherwise the WALLS command uses 0.35 */
		var enabled = use_server ? scr_get_server().wall_drawing_enabled : (client_enabled || is_offline());
		return "WALLS|" + string(cell_size) + "|" + string(enabled ? 1 : 0.35) + "|" + json_stringify(state_rows(state));
	}

	/// @description Draw visible client tiles and release offscreen cached surfaces
	draw_world = function()
	{
		/* Online rendering waits for snapshot readiness, and any empty client state skips drawing */
		if ((!is_offline() && !client_ready) || client_state.count <= 0) return;

		/* Borrow the first view's room camera to choose visible cached tiles */
		var camera = view_camera[0];

		/* Without a usable camera, no viewport tile range can be calculated */
		if (camera < 0) return;

		/* tile_pixels is the 256-room-pixel tile edge, and left/top/right/bottom bound its visible zero-based tile coordinates */
		var tile_pixels = tile_cells * cell_size;
		var left = max(0, floor(camera_get_view_x(camera) / tile_pixels));
		var top = max(0, floor(camera_get_view_y(camera) / tile_pixels));
		var right = min(255, floor((camera_get_view_x(camera) + camera_get_view_width(camera)) / tile_pixels));
		var bottom = min(255, floor((camera_get_view_y(camera) + camera_get_view_height(camera)) / tile_pixels));

		/* Inspect the preceding frame's zero-based cached tile list to release surfaces now outside the view */
		for (var i = 0; i < array_length(client_state.cached); i++)
		{
			/* Borrow the previous visible tile key before checking whether its metadata still exists */
			var key = client_state.cached[i];

			/* Skip stale tile keys whose empty metadata was removed by an edit */
			if (!ds_map_exists(client_state.tiles, key)) continue;

			/* Borrow the old cached tile's coordinates and surface for the visibility test */
			var tile = client_state.tiles[? key];

			/* An offscreen tile releases its cached surface while keeping occupancy and metadata for a later rebuild */
			if (tile.x < left || tile.x > right || tile.y < top || tile.y > bottom)
			{
				/* Free only an existing offscreen surface before clearing its handle */
				if (surface_exists(tile.surface)) surface_free(tile.surface);
				tile.surface = noone;
			}
		}
		client_state.cached = [];

		/* Enabled or offline walls draw fully opaque, while disabled online walls remain visible at 0.35 opacity
		restore_filter retains the caller's setting before pixel-art rendering disables interpolation */
		var alpha = client_enabled || is_offline() ? 1 : 0.35;
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);

		/* Traverse inclusive visible tile rows */
		for (var ty = top; ty <= bottom; ty++)
		{
			/* Traverse inclusive visible tile columns */
			for (var tx = left; tx <= right; tx++)
			{
				/* Pack the visible tile coordinate using the 256-tile row stride */
				var key = ty * 256 + tx;

				/* Tiles without occupancy metadata need no surface or draw call */
				if (!ds_map_exists(client_state.tiles, key)) continue;

				/* Borrow this visible tile for any necessary cached-surface rebuild */
				var tile = client_state.tiles[? key];

				/* Rebuild dirty or lost surfaces, skipping this tile only if its required rebuild fails */
				if ((tile.dirty || !surface_exists(tile.surface)) && !build_tile(client_state, tile)) continue;
				client_state.cached[array_length(client_state.cached)] = key;
				draw_set_alpha(alpha);
				draw_surface(tile.surface, tx * tile_pixels, ty * tile_pixels);
			}
		}

		/* A live 160-ms contact flash appears only for fully opaque walls and fades with the remaining deadline */
		if (current_time < contact_until && alpha == 1)
		{
			draw_set_colour(c_white);
			draw_set_alpha(0.6 * (contact_until - current_time) / 160);

			/* Traverse cell rows within 48 room pixels of the most recent collision centre */
			for (var cy = max(0, floor((contact_y - 48) / cell_size)); cy <= floor((contact_y + 48) / cell_size); cy++)

				/* Traverse nearby cell columns for the collision flash */
				for (var cx = max(0, floor((contact_x - 48) / cell_size)); cx <= floor((contact_x + 48) / cell_size); cx++)

					/* Flash only occupied cells, leaving nearby empty drawing space untouched */
					if (ds_map_exists(client_state.cells, cell_key(cx, cy)))
						draw_rectangle(cx * cell_size, cy * cell_size, (cx + 1) * cell_size, (cy + 1) * cell_size, false);
		}
		gpu_set_texfilter(restore_filter);
		draw_set_alpha(1);
		draw_set_colour(c_white);
	}
	#endregion /* Wall Rendering and Export END */

}

/// @description Return the shared wall controller
/// @returns {Struct} Lazily constructed wall controller
function scr_get_walls()
{
	/* Create one shared wall controller for client collision/rendering and authoritative server updates */
	static walls = new scr_walls();
	return walls;
}
