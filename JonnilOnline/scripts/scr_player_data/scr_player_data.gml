#macro PLAYER_DIRECTION_DOWN 0
#macro PLAYER_DIRECTION_LEFT 1
#macro PLAYER_DIRECTION_RIGHT 2
#macro PLAYER_DIRECTION_UP 3

/// @description Choose facing from a movement vector, preferring the vertical axis when magnitudes tie
/// @param {Real} dx Horizontal movement delta
/// @param {Real} dy Vertical movement delta
/// @param {Real} fallback_direction Direction to keep when both deltas are zero
/// @returns {Real} PLAYER_DIRECTION_* value or the supplied fallback
function player_character_direction_from_delta(dx, dy, fallback_direction)
{
	/* Prefer horizontal facing only when horizontal movement has the larger magnitude. Ties continue
	to vertical facing below */
	if (abs(dx) > abs(dy))
	{
		/* Negative horizontal movement faces left and positive movement faces right, matching the sign
		of room x travel */
		return dx < 0 ? PLAYER_DIRECTION_LEFT : PLAYER_DIRECTION_RIGHT;
	}

	/* Any remaining vertical movement sets up or down facing. A stationary vertical axis continues to
	the horizontal fallback */
	if (dy != 0)
	{
		/* Negative y travels upward in the room and positive y travels down, so select the matching
		sprite row */
		return dy < 0 ? PLAYER_DIRECTION_UP : PLAYER_DIRECTION_DOWN;
	}

	/* Retain a horizontal direction when it is nonzero after the earlier tests. A fully stationary
	vector keeps the previous facing */
	if (dx != 0)
	{
		/* Use left for negative x and right for positive x to keep animation facing aligned with
		horizontal travel */
		return dx < 0 ? PLAYER_DIRECTION_LEFT : PLAYER_DIRECTION_RIGHT;
	}

	return fallback_direction;
}

/// @description Own a lazily loaded sprite sheet and its padded replacement. Browser loads complete through the Image Loaded event
/// @param {String} file_name PNG path or data URL
/// @param {Real} frame_width Width of one source frame in pixels
/// @param {Real} frame_height Height of one source frame in pixels
/// @param {Real} columns Number of animation columns
/// @param {Real} rows Number of facing-direction rows
/// @param {Real} origin_x Horizontal origin within a source frame in pixels
/// @param {Real} origin_y Vertical origin within a source frame in pixels
/// @param {Real} source_scale Scale from source pixels to project sprite pixels
function player_character_sprite_sheet(file_name, frame_width, frame_height, columns, rows, origin_x, origin_y, source_scale) constructor
{

	#region /* Sprite Sheet State */
	/* Registry-owned sprite handle starts unallocated. ensure_loaded creates it and apply_padding can
	replace and delete the source sprite */
	sprite = noone;

	/* Configured PNG path or data URL used when sprite loading starts */
	source_file = string(file_name);

	/* Actual loaded source label starts empty until native loading or an Image Loaded event records it
	for diagnostics */
	loaded_file = "";

	/* frame_w and frame_h are source-frame dimensions in pixels. column_count and row_count describe
	the supplied animation grid */
	frame_w = frame_width;
	frame_h = frame_height;
	column_count = columns;
	row_count = rows;

	/* xorigin and yorigin place the draw origin within one source frame. scale_to_project_sprite
	converts its source pixels to the project's character size */
	xorigin = origin_x;
	yorigin = origin_y;
	scale_to_project_sprite = source_scale;

	/* load_attempted prevents repeated creation attempts, load_pending marks an unfinished browser
	request, loaded permits drawing and load_failed records rejection. All begin false before a
	request is made */
	load_attempted = false;
	load_pending = false;
	loaded = false;
	load_failed = false;

	/* load_status and load_http_status start at zero before any async result. Matching Image Loaded
	events replace them with runtime and HTTP diagnostics */
	load_status = 0;
	load_http_status = 0;

	/* padding adds one transparent pixel around each frame. padding_attempted starts false,
	sheet_gutter starts zero and sheet_cell_w/h initially equal the unpadded source frame dimensions */
	padding = 1;
	padding_attempted = false;
	sheet_gutter = 0;
	sheet_cell_w = frame_w;
	sheet_cell_h = frame_h;
	#endregion /* Sprite Sheet State END */

	#region /* Sprite Loading and Padding */
	/// @description Make a compact diagnostic label without exposing embedded PNG bytes
	/// @param {String} raw_file File path or data URL
	/// @returns {String} Embedded-data label or a path capped at 120 characters
	file_debug_label = function(raw_file)
	{
		/* String source label used for readable diagnostics rather than passing raw file or data
		values onward */
		var text = string(raw_file);

		/* Embedded PNG URLs are summarized so diagnostics never print the entire base64 image payload */
		if (string_copy(text, 1, 22) == "data:image/png;base64,")
		{
			return "embedded PNG data";
		}

		/* Long file labels are shortened to 120 characters, keeping logs readable while ordinary paths
		remain unchanged */
		if (string_length(text) > 120)
		{
			return string_copy(text, 1, 117) + "...";
		}

		return text;
	}

	/// @description Select the asynchronous sprite-loading path used by browser and GX Games runtimes
	/// @returns {Bool} Whether this runtime needs browser image loading
	is_browser_sprite_runtime = function()
	{
		/* A browser environment or GX Games uses asynchronous image loading. Desktop runtimes follow
		the synchronous sprite_add path */
		return os_browser != browser_not_a_browser || os_type == os_gxgames;
	}

	/// @description Build a sprite grid with transparent gutters and free the temporary surface
	/// @param {Id.Sprite} source_sprite Loaded source sheet retained by the caller
	/// @returns {Id.Sprite|Real} New owned sprite, or noone if the temporary surface could not be created
	build_padded_sprite = function(source_sprite)
	{
		/* padded_width and padded_height are source pixels for the entire grid including gutters.
		sheet_surface is a temporary owned surface released after extracting the new sprite */
		var padded_width = (frame_w + padding * 2) * column_count;
		var padded_height = (frame_h + padding * 2) * row_count;
		var sheet_surface = surface_create(padded_width, padded_height);

		/* Surface allocation failure leaves no target to draw into. Report it and return noone so the
		caller can retain the unpadded sprite */
		if (!surface_exists(sheet_surface))
		{
			debug_error("Could not create padded player character sheet surface.");
			return noone;
		}

		surface_set_target(sheet_surface);
		draw_clear_alpha(c_black, 0);

		/* row begins at facing row zero and visits each configured row once. The loop ends after
		row_count rows */
		for (var row = 0; row < row_count; row++)
		{
			/* column begins at animation column zero and copies every frame in this row. Padding
			offsets leave a transparent border between frames */
			for (var column = 0; column < column_count; column++)
			{
				draw_sprite_part(
					source_sprite,
					0,
					column * frame_w,
					row * frame_h,
					frame_w,
					frame_h,
					column * (frame_w + padding * 2) + padding,
					row * (frame_h + padding * 2) + padding
				);
			}
		}

		surface_reset_target();

		/* Replacement sprite is extracted from the completed temporary sheet with origin zero. The
		surface can then be freed because the sprite owns its texture */
		var padded_sprite = sprite_create_from_surface(
			sheet_surface,
			0,
			0,
			padded_width,
			padded_height,
			false,
			false,
			0,
			0
		);
		surface_free(sheet_surface);

		/* Only a successfully created replacement changes the sheet's gutter and cell dimensions.
		Failure retains the unpadded layout */
		if (sprite_exists(padded_sprite))
		{
			sheet_gutter = padding;
			sheet_cell_w = frame_w + padding * 2;
			sheet_cell_h = frame_h + padding * 2;
		}

		return padded_sprite;
	}

	/// @description Log a loaded texture smaller than the configured grid without discarding its resource
	validate_dimensions = function()
	{
		/* A texture smaller than the configured grid cannot contain all promised frames. Log that
		mismatch while retaining the loaded resource for the existing draw path */
		if (sprite_get_width(sprite) < frame_w * column_count
		|| sprite_get_height(sprite) < frame_h * row_count)
		{
			debug_error("Player character sheet " + file_debug_label(loaded_file) + " is smaller than the configured " + string(column_count) + "x" + string(row_count) + " grid.");
		}
	}

	/// @description Require both an existing sprite resource and completed image loading
	/// @returns {Bool} Whether the sheet can provide real pixels for drawing or padding
	is_loaded = function()
	{
		/* Drawing requires both a surviving sprite resource and a completed load. A browser
		placeholder alone must not be treated as loaded artwork */
		return sprite_exists(sprite) && loaded;
	}

	/// @description Attempt transparent gutters once, deleting the source only after successful replacement
	/// @returns {Bool} Whether the requested padding is installed
	apply_padding = function()
	{
		/* Already attempted or installed padding is not retried. Return whether the desired gutter is
		actually present so failures remain visible to the caller */
		if (padding_attempted || sheet_gutter == padding)
		{
			/* The gutter matching padding means the replacement succeeded. A previous failed attempt
			instead returns false */
			return sheet_gutter == padding;
		}

		padding_attempted = true;

		/* source_sprite retains the original handle until replacement succeeds. padded_sprite receives
		the newly allocated guttered sheet */
		var source_sprite = sprite;
		var padded_sprite = build_padded_sprite(source_sprite);

		/* A valid replacement becomes the owned sprite and releases the source handle. Failed
		replacement leaves the source usable */
		if (sprite_exists(padded_sprite))
		{
			sprite = padded_sprite;
			sprite_delete(source_sprite);
			return true;
		}

		sheet_gutter = 0;
		sheet_cell_w = frame_w;
		sheet_cell_h = frame_h;
		debug_error("Falling back to unpacked player character sheet.");
		return false;
	}

	/// @description Apply gutters lazily after the image has finished loading without repeating failed attempts
	/// @returns {Bool} Whether the requested padding is installed
	finish_padding_if_ready = function()
	{
		/* An installed gutter or a prior attempt ends this lazy padding check, avoiding repeated
		texture work */
		if (sheet_gutter == padding || padding_attempted)
		{
			/* Report actual installed padding rather than claiming that an attempted conversion
			succeeded */
			return sheet_gutter == padding;
		}

		/* An unfinished or failed load cannot supply real pixels for padding. Wait until is_loaded
		confirms the texture */
		if (!is_loaded())
		{
			return false;
		}

		return apply_padding();
	}

	/// @description Record an Image Loaded result for this sheet. Success is tracked separately from whether the event matches
	/// @param {Id.DsMap} load_map Async image event data. The caller retains ownership
	/// @returns {Bool} Whether the event sprite id belongs to this sheet
	mark_image_loaded = function(load_map)
	{
		/* Only an event for this existing sprite handle is consumed. Missing IDs, unrelated images and
		absent sprites return false without changing sheet state */
		if (!sprite_exists(sprite)
		|| !ds_map_exists(load_map, "id")
		|| load_map[? "id"] != sprite)
		{
			return false;
		}

		load_pending = false;

		/* Optional async status fields default to zero and a missing filename retains source_file.
		This allows events with fewer diagnostic members to complete the same load path */
		load_status = ds_map_exists(load_map, "status") ? load_map[? "status"] : 0;
		load_http_status = ds_map_exists(load_map, "http_status") ? load_map[? "http_status"] : 0;
		loaded_file = ds_map_exists(load_map, "filename") ? string(load_map[? "filename"]) : source_file;

		/* A negative async status marks this matching request failed. Record the diagnostic but return
		true because the event belongs to this sheet */
		if (load_status < 0)
		{
			loaded = false;
			load_failed = true;
			debug_error("Player character sheet " + file_debug_label(loaded_file) + " failed to load. status=" + string(load_status) + " http_status=" + string(load_http_status));
			return true;
		}

		loaded = true;
		load_failed = false;
		validate_dimensions();
		debug_log("Player character sheet loaded: " + file_debug_label(loaded_file));
		return true;
	}

	/// @description Attempt sprite creation once. A successful browser request can still be waiting for the Image Loaded event
	/// @returns {Bool} Whether a sprite resource exists, including a browser loading placeholder
	ensure_loaded = function()
	{
		/* Reuse an existing sprite resource, including a browser placeholder. Completion is checked
		separately by is_loaded */
		if (sprite_exists(sprite))
		{
			return true;
		}

		/* A previous attempt that left no sprite is not repeated automatically. Return false rather
		than starting another load each draw */
		if (load_attempted)
		{
			return false;
		}

		load_attempted = true;

		try
		{
			debug_log("Loading player character sheet: " + file_debug_label(source_file));

			/* Browser and GX Games runtimes start an asynchronous sprite_add_ext request. The sheet
			remains pending until its Image Loaded event */
			if (is_browser_sprite_runtime())
			{
				sprite = sprite_add_ext(source_file, 1, 0, 0, true);
				load_pending = true;
				loaded = false;
			}

			/* Desktop sprite_add loads synchronously, so record the source and mark the texture loaded
			immediately */
			else
			{
				sprite = sprite_add(source_file, 1, false, false, 0, 0);
				loaded_file = source_file;
				loaded = true;
			}
		}
		catch (e)
		{
			/* Failure message identifies the requested source and exception. It is expanded with
			detailed text only when the exception provides it */
			var load_message = "Could not load player character sheet " + file_debug_label(source_file) + ": " + string(e.message);

			/* Append longMessage only when present so diagnostic handling avoids another
			missing-member error */
			if (variable_struct_exists(e, "longMessage"))
			{
				load_message += "\n" + e.longMessage;
			}
			debug_error(load_message);
			sprite = noone;
			load_pending = false;
			loaded = false;
			load_failed = true;
			return false;
		}

		/* A creation call can return without an actual sprite resource. Treat that as failure and
		reset pending state before returning false */
		if (!sprite_exists(sprite))
		{
			debug_error("Could not load player character sheet " + file_debug_label(source_file) + ".");
			sprite = noone;
			load_pending = false;
			loaded = false;
			load_failed = true;
			return false;
		}

		/* Browser placeholders must keep unpadded cell geometry until their real image arrives. Return
		successfully started status without reading or padding placeholder pixels */
		if (is_browser_sprite_runtime())
		{
			/* HTML5 starts with a 1x1 placeholder. The Image Loaded async event
			marks this sheet loaded after the browser has the real texture */
			sheet_gutter = 0;
			sheet_cell_w = frame_w;
			sheet_cell_h = frame_h;
			return true;
		}

		validate_dimensions();
		apply_padding();

		return true;
	}
	#endregion /* Sprite Loading and Padding END */

}

#region /* Character Access and Drawing */
/// @description Return the registry-owned Player 1 sheet. Loading starts when it is drawn
/// @returns {Struct} Cached sprite-sheet data
function player_character_get_default()
{
	return scr_get_player_characters().get_sheet("player1");
}

/// @description Return a registry-owned character sheet, resolving unavailable keys through Player 1
/// @param {String} character_key Local or network character key
/// @returns {Struct} Cached sprite-sheet data
function player_character_get(character_key)
{
	return scr_get_player_characters().get_sheet(character_key);
}

/// @description Forward an Image Loaded async map to the character registry without taking ownership of the map
/// @param {Id.DsMap} load_map Image Loaded event data containing the sprite id and load status
/// @returns {Bool} Whether a cached sheet recognized the event
function player_character_handle_image_loaded(load_map)
{
	return scr_get_player_characters().handle_image_loaded(load_map);
}

/* Return this character's top draw bound through the registry's origin and source-scale calculation */
/// @description Return the requested character's top draw bound
/// @param {String} character_key Character key resolved through the registry
/// @param {Real} y Vertical draw origin in the current coordinate space
/// @param {Real} project_scale Extra scale after the sheet's source-to-project scale
/// @returns {Real} Top frame coordinate
function player_character_top_y_key(character_key, y, project_scale)
{
	return scr_get_player_characters().top_y(character_key, y, project_scale);
}

/* Return the bottom draw bound for the requested character, allowing nameplates and markers to align
with its actual height */
/// @description Return the requested character's bottom draw bound
/// @param {String} character_key Character key resolved through the registry
/// @param {Real} y Vertical draw origin in the current coordinate space
/// @param {Real} project_scale Extra scale after the sheet's source-to-project scale
/// @returns {Real} Bottom frame coordinate
function player_character_bottom_y_key(character_key, y, project_scale)
{
	return scr_get_player_characters().bottom_y(character_key, y, project_scale);
}

/* Resolve the character-specific horizontal center rather than assuming its draw origin is centered */
/// @description Return the requested character's horizontal draw center
/// @param {String} character_key Character key resolved through the registry
/// @param {Real} x Horizontal draw origin in the current coordinate space
/// @param {Real} project_scale Extra scale after the sheet's source-to-project scale
/// @returns {Real} Horizontal frame center
function player_character_center_x_key(character_key, x, project_scale)
{
	return scr_get_player_characters().center_x(character_key, x, project_scale);
}

/// @description Return the full sprite frame bounds at its drawing origin. These are not movement collision bounds
/// @param {String} character_key Character key resolved by the registry
/// @param {Real} x Horizontal drawing origin in the current coordinate space
/// @param {Real} y Vertical drawing origin in the current coordinate space
/// @param {Real} project_scale Additional scale applied after the sheet source scale
/// @returns {Struct} left, top, right, bottom, center_x, and center_y in the drawing coordinate space
function player_character_bounds_key(character_key, x, y, project_scale)
{
	return scr_get_player_characters().bounds(character_key, x, y, project_scale);
}

/* Use Player 1's top draw bound for callers using the original default-character helper */
/// @description Return Player 1's top draw bound for default-character callers
/// @param {Real} y Vertical draw origin in the current coordinate space
/// @param {Real} project_scale Extra scale after the sheet's source-to-project scale
/// @returns {Real} Top frame coordinate
function player_character_top_y(y, project_scale)
{
	return player_character_top_y_key("player1", y, project_scale);
}

/// @description Select the three-frame walk cycle using a 140-millisecond interval. Idle uses the middle column
/// @param {Bool} is_walking Whether to animate the walk cycle
/// @returns {Real} Zero-based animation column
function player_character_walk_column(is_walking)
{
	/* Idle animation holds the middle column instead of cycling walk frames, so a stationary player
	retains its neutral pose */
	if (!is_walking)
	{
		return 1;
	}

	/* current_time milliseconds advances the four-stage walk rhythm every 140 ms. The stage sequence
	is first walk, idle, second walk, idle before repeating */
	switch ((current_time div 140) mod 4)
	{
		/* Stage zero selects the first walking column */
		case 0: return 0;

		/* Stage one selects the middle idle column between footfall frames */
		case 1: return 1;

		/* Stage two selects the second walking column */
		case 2: return 2;

		/* The final stage returns to the middle column before the cycle starts again */
		default: return 1;
	}
}

/// @description Draw a default Player 1 frame through the shared character registry
/// @param {Real} facing_direction Direction row from PLAYER_DIRECTION constants
/// @param {Bool} is_walking Whether to use the timed walk sequence
/// @param {Real} x Horizontal draw origin
/// @param {Real} y Vertical draw origin
/// @param {Real} project_scale Additional scale after the sheet's source-to-project scale
/// @param {Real} colour Sprite tint, default c_white
/// @param {Real} alpha Opacity, default 1
/// @returns {Bool} Whether a loaded frame was drawn
function player_character_draw(facing_direction, is_walking, x, y, project_scale, colour = c_white, alpha = 1)
{
	return scr_get_player_characters().draw_character("player1", facing_direction, is_walking, x, y, project_scale, colour, alpha);
}

/// @description Draw the requested character with its configured origin and timed animation
/// @param {String} character_key Character key resolved through the registry
/// @param {Real} facing_direction Direction row from PLAYER_DIRECTION constants
/// @param {Bool} is_walking Whether to use the timed walk sequence
/// @param {Real} x Horizontal draw origin
/// @param {Real} y Vertical draw origin
/// @param {Real} project_scale Additional scale after the sheet's source-to-project scale
/// @param {Real} colour Sprite tint, default c_white
/// @param {Real} alpha Opacity, default 1
/// @returns {Bool} Whether a loaded frame was drawn
function player_character_draw_key(character_key, facing_direction, is_walking, x, y, project_scale, colour = c_white, alpha = 1)
{
	return scr_get_player_characters().draw_character(character_key, facing_direction, is_walking, x, y, project_scale, colour, alpha);
}

/// @description Fit the requested character into a supplied draw rectangle and preserve its aspect ratio
/// @param {String} character_key Character key resolved through the registry
/// @param {Real} facing_direction Direction row from PLAYER_DIRECTION constants
/// @param {Bool} is_walking Whether to use the timed walk sequence
/// @param {Real} box_left Left draw coordinate
/// @param {Real} box_top Top draw coordinate
/// @param {Real} box_right Right draw coordinate
/// @param {Real} box_bottom Bottom draw coordinate
/// @param {Real} colour Sprite tint, default c_white
/// @param {Real} alpha Opacity, default 1
/// @returns {Bool} Whether a loaded frame was drawn
function player_character_draw_key_in_box(character_key, facing_direction, is_walking, box_left, box_top, box_right, box_bottom, colour = c_white, alpha = 1)
{
	return scr_get_player_characters().draw_character_in_box(character_key, facing_direction, is_walking, box_left, box_top, box_right, box_bottom, colour, alpha);
}
#endregion /* Character Access and Drawing END */

#region /* Player Room Bounds */
/// @description Reserve space for the default character frame and standard nameplate inside the current room
/// @returns {Struct} left, top, right, and bottom limits in room pixels
function player_world_bounds()
{
	/* Default character metrics establish the room margins shared by player movement */
	var character = player_character_get_default();

	/* player_size is the default additional draw multiplier. draw_scale includes the source-to-project
	conversion so margins use room pixels */
	var player_size = 2.5;
	var draw_scale = player_size * character.scale_to_project_sprite;

	/* nameplate_width and nameplate_height are standard room-pixel label dimensions. nameplate_gap
	reserves ten room pixels between the label and sprite */
	var nameplate_width = 116;
	var nameplate_height = 22;
	var nameplate_gap = 10;

	/* left_margin and right_margin reserve the larger of the sprite overhang or half the nameplate
	width. top_margin includes the label and gap, and bottom_margin includes the sprite below its
	origin */
	var left_margin = max(character.xorigin * draw_scale, nameplate_width * 0.5);
	var right_margin = max((character.frame_w - character.xorigin) * draw_scale, nameplate_width * 0.5);
	var top_margin = character.yorigin * draw_scale + nameplate_gap + nameplate_height;
	var bottom_margin = (character.frame_h - character.yorigin) * draw_scale;

	/* Returned left, top, right and bottom limit the player's draw origin in room pixels, keeping the
	default sprite and label inside the room */
	return
	{
		left: left_margin,
		top: top_margin,
		right: room_width - right_margin,
		bottom: room_height - bottom_margin
	};
}

/// @description Clamp a player drawing origin to the current room margins
/// @param {Real} x Horizontal room position in pixels
/// @param {Real} y Vertical room position in pixels
/// @returns {Struct} Clamped x and y room coordinates
function player_clamp_position(x, y)
{
	/* Room-pixel bounds for a player draw origin. Returned x and y clamp each supplied axis
	independently into those limits */
	var bounds = player_world_bounds();
	return
	{
		x: clamp(x, bounds.left, bounds.right),
		y: clamp(y, bounds.top, bounds.bottom)
	};
}
#endregion /* Player Room Bounds END */

/// @description Store one network slot's movement and drawing state. Local authority, server state, and remote interpolation share this struct
/// @param {Real} socket_id Player slot identifier, not an operating-system socket
/// @param {Real} x Initial horizontal room position in pixels
/// @param {Real} y Initial vertical room position in pixels
/// @param {String} display_name Display name, defaulting to empty when omitted. An empty name becomes Player
/// @param {String} player_character_key Local or network character key, defaulting to empty when omitted. An empty key selects Player 1
function scr_player_data(socket_id, x, y, display_name = "", player_character_key = "") constructor
{

	#region /* Player Identity and Movement State */
	/* Network player-slot identity supplied by the controller and reused for packet routing and
	local-player checks */
	ID = socket_id;

	/* Display name begins with the supplied text and falls back below when empty */
	username = string(display_name);

	/* A blank supplied username becomes Player so world labels remain readable */
	if (username == "")
	{
		username = "Player";
	}

	/* An empty character key selects Player 1. Other keys resolve to the registry's network identity
	so custom sheets keep their content-hash identity */
	character_key = player_character_key == "" ? "player1" : scr_get_player_characters().network_key(player_character_key);

	/* Pet equipment shares artwork keys but has its own role and cosmetic route.
	Empty equipment and undefined follow state allocate no companion before selection */
	pet_key = "";
	pet_manifest = noone;
	pet_follow_state = undefined;

	/* Clamped room-pixel spawn position shared by both physics and initial drawing */
	var start_pos = player_clamp_position(x, y);

	/* Network and collision state use pos.
	Drawing uses visual_pos */
	/* pos stores x and y for network and collision state. visual_pos has separate x and y initialized
	to the same spawn, then interpolated for drawing */
	pos = { x: start_pos.x, y: start_pos.y };
	visual_pos = { x: start_pos.x, y: start_pos.y };

	/* left, right, up and down start released at zero. Input polling or network action packets update
	them and opposite directions cancel in the movement vector */
	left = 0;
	right = 0;
	up = 0;
	down = 0;

	/* facing_direction starts down and is_moving starts false, keeping the initial sprite idle until
	input or a snapshot supplies motion */
	facing_direction = PLAYER_DIRECTION_DOWN;
	is_moving = false;

	/* Legacy movement_speed is five room pixels per update. The fixed collision circle is centered
	on pos and keeps the same radius when facing, animation or cosmetic sprite scale changes */
	movement_speed = 5; /* Room pixels per legacy Step or nominal 60 Hz movement step */
	wall_collision_radius = PLAYER_COLLISION_RADIUS; /* Room pixels */
	/* player_size multiplies the sheet's project scale for rendering. remote_lerp_amount advances
	remote visuals toward their target and the two local correction amounts apply weaker adjustment
	while local input is active */
	player_size = 2.5;
	remote_lerp_amount = 0.35;
	local_correction_lerp = 0.10;
	local_movement_correction_lerp = 0.04;

	/* local_movement_correction_deadzone ignores corrections within 64 room pixels during active
	fallback prediction. local_snap_distance forces immediate correction above 96 room pixels */
	local_movement_correction_deadzone = 64;
	local_snap_distance = 96;

	/* remote_snapshot_received_at starts zero with no timed snapshot yet, using current_time
	milliseconds. remote_snapshot_interval_ms and remote_snapshot_average_ms start at -1 to mark
	unavailable timing samples */
	remote_snapshot_received_at = 0;
	remote_snapshot_interval_ms = -1;
	remote_snapshot_average_ms = -1;

	/* remote_snapshot_x and remote_snapshot_y start at the spawn and become the last received room
	position used to measure snapshot velocity */
	remote_snapshot_x = start_pos.x;
	remote_snapshot_y = start_pos.y;

	/* remote_velocity_x and remote_velocity_y start at zero room pixels per millisecond.
	remote_velocity_valid begins false until snapshots establish a usable motion estimate */
	remote_velocity_x = 0; /* Room pixels per millisecond, sampled between server snapshots */
	remote_velocity_y = 0;
	remote_velocity_valid = false;

	/* remote_velocity_smoothing blends 65 percent of a new sample into the previous velocity.
	remote_extrapolation_limit_ms caps how far past a snapshot the draw target can advance */
	remote_velocity_smoothing = 0.65;
	remote_extrapolation_limit_ms = 180;

	/* authoritative_is_moving begins false until server or owned local state reports motion.
	client_position_authority remains false until negotiation succeeds and its request_sent flag
	prevents duplicate requests */
	authoritative_is_moving = false;
	client_position_authority = false;
	client_position_authority_request_sent = false;

	/* client_state_send_interval_ms initially schedules 67 ms between positional sends, then the
	acknowledged server interval replaces it. client_state_next_send_at is a current_time
	millisecond deadline starting zero so the first send need not wait */
	client_state_send_interval_ms = 67;
	client_state_next_send_at = 0;

	/* No owned state has been sent initially. last_sent_x/y/direction/moving start noone and are only
	used as prior state after client_state_has_sent becomes true */
	client_state_has_sent = false;
	client_state_last_sent_x = noone;
	client_state_last_sent_y = noone;
	client_state_last_sent_direction = noone;
	client_state_last_sent_moving = noone;
	#endregion /* Player Identity and Movement State END */

	#region /* Player Position and Wall Corrections */
	/// @description Identify whether this player slot belongs to the local client
	/// @returns {Bool} Whether the client's assigned ID matches this player
	is_local_client_player = function()
	{
		/* Shared client identity is compared with this player slot rather than its operating-system
		socket handle */
		var client = scr_get_client();

		/* This struct is local only when the client is a struct with an ID matching this player's ID.
		Otherwise movement and rendering follow remote-player behavior */
		return is_struct(client)
			&& variable_struct_exists(client, "ID")
			&& client.ID == ID;
	}

	/// @description Constrain authoritative position to player room margins
	apply_clamp = function()
	{
		/* Clamped copy of the authoritative room position used to bring both axes back inside player
		margins */
		var clamped = player_clamp_position(pos.x, pos.y);
		pos.x = clamped.x;
		pos.y = clamped.y;
	}

	/// @description Pause movement for unfinished wall snapshots, otherwise resolve room and wall travel
	/// @param {Real} from_x Starting horizontal room coordinate in pixels
	/// @param {Real} from_y Starting vertical room coordinate in pixels
	/// @param {Real} to_x Requested horizontal room coordinate in pixels
	/// @param {Real} to_y Requested vertical room coordinate in pixels
	/// @param {Bool} use_server Whether to test authoritative server walls, default false
	/// @returns {Struct} Accepted x/y room coordinates and blocked for rejected wall travel
	resolve_wall_position = function(from_x, from_y, to_x, to_y, use_server = false)
	{
		/* walls supplies client/server collision snapshots and client reports whether this local
		connection supports them */
		var walls = scr_get_walls();
		var client = scr_get_client();

		/* On the server, an outstanding wall snapshot job pauses this slot's movement. On the client,
		only the local supported wall feature waits while the grid is not ready */
		var waiting_for_walls = use_server
			? walls.job_index(ID) != noone
			: (is_local_client_player() && client.wall_drawing_supported && !walls.client_ready);

		/* While the required wall snapshot is unfinished, retain the source x/y so movement cannot
		enter unseen geometry */
		if (waiting_for_walls)
		{
			/* Do not walk into walls before their complete, visible snapshot arrives.
			A client that moved before receiving settings is corrected once by the server */
			/* The waiting result keeps the source coordinates. blocked is true only for a server-side
			request that tried to move, allowing one corrective packet for premature travel */
			return { x: from_x, y: from_y, blocked: use_server && (to_x != from_x || to_y != from_y) };
		}

		/* clamped is the requested destination inside room margins. resolved sweeps the collision
		circle toward it and reports accepted coordinates and wall blocking */
		var clamped = player_clamp_position(to_x, to_y);
		var resolved = player_resolve_wall_movement(from_x, from_y, clamped.x, clamped.y, wall_collision_radius, use_server);

		/* Only a blocked local client move reports contact to the wall UI. Server movement and remote
		visuals avoid recording local contact effects */
		if (resolved.blocked && !use_server && is_local_client_player())
		{
			scr_get_walls().note_contact(resolved.x, resolved.y);
		}
		return resolved;
	}

	/// @description Apply a server wall correction only to the local player, snap its visual position, and reset the next state send
	/// @param {Real} x Corrected horizontal room position in pixels
	/// @param {Real} y Corrected vertical room position in pixels
	/// @returns {Bool} Whether this struct belongs to the local player
	receive_wall_correction = function(x, y)
	{
		/* Wall corrections belong to the local player only. Remote slots ignore this packet path and
		retain their interpolation state */
		if (!is_local_client_player()) return false;

		/* Corrected server coordinates clamped into player room margins before physics and drawing are
		snapped together */
		var corrected = player_clamp_position(x, y);
		pos.x = corrected.x;
		pos.y = corrected.y;
		visual_pos.x = pos.x;
		visual_pos.y = pos.y;
		client_state_has_sent = false;
		client_state_next_send_at = 0;
		scr_get_walls().note_contact(pos.x, pos.y);
		return true;
	}

	/// @description Send the local owner's accepted position after wall blocking, choosing a safe nearby integer packet coordinate when necessary
	/// @param {Struct} server Server with occupied sockets and slot transports
	/// @returns {Real} Zero when no slot can receive the correction, otherwise the send result
	send_wall_correction = function(server)
	{
		/* Without a server, a valid slot index or an occupied server socket, no correction can be
		routed. Skip sending and return zero */
		if (!is_struct(server)
		|| ID < 0 || ID >= array_length(server.sockets)
		|| server.sockets[ID] == noone) return 0;

		/* correction_x and correction_y are integer room coordinates for the packet. walls tests
		whether rounding changed a safe fractional position into a collision */
		var correction_x = round(pos.x);
		var correction_y = round(pos.y);
		var walls = scr_get_walls();

		/* Integer movement packets must not round a safe position into the wall */
		/* Search nearby integer coordinates only when rounded coordinates overlap a wall but the
		original position was clear. Already safe rounding and genuinely overlapping originals
		retain their rounded packet values */
		if (walls.circle_overlaps(correction_x, correction_y, wall_collision_radius, true)
		&& !walls.circle_overlaps(pos.x, pos.y, wall_collision_radius, true))
		{
			/* best_distance starts beyond nearby candidates so the closest clear integer correction
			can replace it */
			var best_distance = 1000000;

			/* offset_x visits -1, zero and +1 room-pixel offsets around the rounded position, checking
			the three neighboring integer columns */
			for (var offset_x = -1; offset_x <= 1; offset_x++)
			{
				/* offset_y visits the same three offsets in each column, producing at most nine
				candidate correction positions */
				for (var offset_y = -1; offset_y <= 1; offset_y++)
				{
					/* candidate_x and candidate_y are this nearby integer room position.
					candidate_distance measures its separation from the safe fractional position */
					var candidate_x = round(pos.x) + offset_x;
					var candidate_y = round(pos.y) + offset_y;
					var candidate_distance = point_distance(pos.x, pos.y, candidate_x, candidate_y);

					/* Keep a candidate only when it is nearer than the current best and its collision
					circle is clear in server walls */
					if (candidate_distance < best_distance
					&& !walls.circle_overlaps(candidate_x, candidate_y, wall_collision_radius, true))
					{
						correction_x = candidate_x;
						correction_y = candidate_y;
						best_distance = candidate_distance;
					}
				}
			}
		}

		/* Shared packet writer sends the selected integer correction to this player's transport */
		var net = scr_get_network();
		net.start(N_WALL_PLAYER_CORRECTION, noone);
		net.write(TYPE_POSITION, correction_x);
		net.write(TYPE_POSITION, correction_y);

		/* Network send result determines whether the client's connection must be closed after a failed
		correction */
		var send_result = net.send(server.sockets[ID], false, server.slot_transports[ID]);

		/* A negative send result closes this slot through the server's normal cleanup path. Successful
		sends leave the connection in place */
		if (send_result < 0)
		{
			server.close_client_slot(ID, "sending wall collision correction", true, true);
		}
		return send_result;
	}
	#endregion /* Player Position and Wall Corrections END */

	#region /* Movement and Facing State */
	/// @description Set facing and walking animation from a movement vector while retaining idle facing
	/// @param {Real} dx Horizontal direction input
	/// @param {Real} dy Vertical direction input
	/// @returns {Bool} Whether facing or walking changed
	set_motion_from_vector = function(dx, dy)
	{
		/* old_direction and old_moving retain prior animation state so callers can decide whether it
		needs immediate relaying */
		var old_direction = facing_direction;
		var old_moving = is_moving;

		/* Any horizontal or vertical input sets facing from the movement vector and enables walking
		animation */
		if (dx != 0 || dy != 0)
		{
			facing_direction = player_character_direction_from_delta(dx, dy, facing_direction);
			is_moving = true;
		}

		/* A zero vector leaves facing unchanged and stops walking animation, retaining the last
		direction for the idle sprite */
		else
		{
			is_moving = false;
		}

		/* Return true when either facing or walking state changed so callers can send an animation
		update even without a positional change */
		return old_direction != facing_direction || old_moving != is_moving;
	}

	/// @description Apply received facing and walking state while constraining the direction row
	/// @param {Real} new_direction Received facing value
	/// @param {Real} new_is_moving Received movement flag, nonzero means walking
	/// @returns {Bool} Whether facing or walking changed
	set_visual_state = function(new_direction, new_is_moving)
	{
		/* Previous facing and walking state are retained to compare against this received visual state */
		var old_direction = facing_direction;
		var old_moving = is_moving;

		facing_direction = clamp(floor(new_direction), PLAYER_DIRECTION_DOWN, PLAYER_DIRECTION_UP);

		/* Any nonzero network movement flag enables walking. Zero selects the idle state independent
		of facing */
		is_moving = new_is_moving != 0;

		/* Changed facing or walking state requires a visual update. Unchanged state returns false to
		avoid unnecessary relays */
		return old_direction != facing_direction || old_moving != is_moving;
	}

	/// @description Resolve and store the character's network identity
	/// @param {String} raw_character_key Local or network character key
	/// @returns {String} Resolved network character key
	set_character_key = function(raw_character_key)
	{
		character_key = scr_get_player_characters().network_key(raw_character_key);
		return character_key;
	}

	/// @description Scale nominal movement distance by delta_time, capping long frames at three nominal steps
	/// @returns {Real} Room-pixel travel for one directional axis this update
	movement_step_distance = function()
	{
		/* Client-owned movement uses five pixels per nominal 60 Hz Step, or 300 px/s.
		Delta time scales that distance. The three-step cap limits jumps after a long frame */
		/* nominal_step_microseconds is one sixtieth of a second. step_scale converts delta_time
		microseconds to nominal steps and caps long frames at three steps */
		var nominal_step_microseconds = 1000000 / 60;
		var step_scale = clamp(delta_time / nominal_step_microseconds, 0, 3);
		return movement_speed * step_scale;
	}
	#endregion /* Movement and Facing State END */

	#region /* Client Movement Authority */
	/// @description Send one request for optional client-owned movement from this connection's local player
	/// @returns {Real} Zero when skipped, otherwise the send result
	request_client_movement_authority = function()
	{
		/* An enabled authority mode or an already sent request needs no further handshake packet.
		Return zero without retrying */
		if (client_position_authority || client_position_authority_request_sent)
		{
			return 0;
		}

		/* Local client connection used to request optional client-owned movement from the server */
		var client = scr_get_client();

		/* Only this connection's local player with a valid numeric nonnegative socket can request
		authority. Other slots or disconnected clients skip the packet */
		if (!is_local_client_player()
		|| !is_struct(client)
		|| !variable_struct_exists(client, "socket")
		|| !is_real(client.socket)
		|| client.socket < 0)
		{
			return 0;
		}

		/* Shared network writer creates the authority-request state packet using the current visual
		position */
		var net = scr_get_network();
		net.start(N_CLIENT_PLAYER_STATE, ID);
		net.write(buffer_u8, CLIENT_MOVEMENT_PROTOCOL_VERSION);
		net.write(TYPE_POSITION, round(visual_pos.x));
		net.write(TYPE_POSITION, round(visual_pos.y));
		net.write(buffer_u8, facing_direction);

		/* Encode walking as byte one and idle as byte zero so the server receives the same compact
		movement flag used by later state packets */
		net.write(buffer_u8, is_moving ? 1 : 0);

		/* Send result is returned to the caller and negative failure results trigger connection-loss
		handling */
		var send_result = net.send_server();

		/* Failed requests do not mark request_sent. Return the failure after notifying the client when
		its loss handler exists */
		if (send_result < 0)
		{
			/* Call connection-loss handling only when that optional method is present. The failed
			result is still returned without it */
			if (variable_struct_exists(client, "mark_connection_lost"))
			{
				client.mark_connection_lost("Lost connection to server.");
			}
			return send_result;
		}

		client_position_authority_request_sent = true;
		return send_result;
	}

	/// @description Enable local position ownership only after the server acknowledges the supported movement protocol and send the first owned state
	/// @param {Real} protocol_version Acknowledged CLIENT_MOVEMENT_PROTOCOL_VERSION
	/// @param {Real} accepted_send_interval_ms Server send interval in milliseconds, clamped to 16 through 1000
	/// @returns {Bool} Whether authority was enabled for the local player
	activate_client_movement_authority = function(protocol_version, accepted_send_interval_ms)
	{
		/* Authority is enabled only for the supported protocol version and this client's local player.
		Reject other acknowledgements before changing ownership */
		if (protocol_version != CLIENT_MOVEMENT_PROTOCOL_VERSION
		|| !is_local_client_player())
		{
			return false;
		}

		client_position_authority = true;
		client_state_send_interval_ms = clamp(round(accepted_send_interval_ms), 16, 1000);
		pos.x = visual_pos.x;
		pos.y = visual_pos.y;
		authoritative_is_moving = is_moving;
		client_state_has_sent = false;
		client_state_next_send_at = 0;
		send_client_player_state(true);
		return true;
	}

	/// @description Send changed integer room coordinates and animation state. Visual changes bypass the position send interval
	/// @param {Bool} force_send Whether to bypass unchanged-state and interval checks, default false
	/// @returns {Real} Zero when skipped, otherwise the network send result. Negative values mark the connection lost
	send_client_player_state = function(force_send = false)
	{
		/* Shared client supplies slot and socket state required to send owned movement */
		var client = scr_get_client();

		/* State sends require negotiated ownership, a matching client ID and a numeric nonnegative
		socket. Otherwise return zero and leave send history unchanged */
		if (!client_position_authority
		|| !is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID != ID
		|| !variable_struct_exists(client, "socket")
		|| !is_real(client.socket)
		|| client.socket < 0)
		{
			return 0;
		}

		/* send_x and send_y round the owned room position for compact integer packets.
		has_previous_state distinguishes the first send from comparisons with valid stored history */
		var send_x = round(pos.x);
		var send_y = round(pos.y);
		var has_previous_state = client_state_has_sent;

		/* Position is changed when nothing has been sent or either integer coordinate differs.
		Subpixel travel alone does not force another position packet */
		var position_changed = !has_previous_state
			|| send_x != client_state_last_sent_x
			|| send_y != client_state_last_sent_y;

		/* Visual state is changed on the first send or when facing or walking differs. Animation
		changes can bypass the position-send cooldown */
		var visual_state_changed = !has_previous_state
			|| facing_direction != client_state_last_sent_direction
			|| is_moving != client_state_last_sent_moving;

		/* Normal sends without an animation change apply the position gate below. Forced sends and
		changed visuals proceed immediately */
		if (!force_send && !visual_state_changed)
		{
			/* Skip unchanged positions and positions whose current_time deadline has not arrived. An
			eligible changed position continues to packet construction */
			if (!position_changed || current_time < client_state_next_send_at)
			{
				return 0;
			}
		}

		/* Shared network writer builds the owned position and animation packet for this slot */
		var net = scr_get_network();
		net.start(N_CLIENT_PLAYER_STATE, ID);
		net.write(buffer_u8, CLIENT_MOVEMENT_PROTOCOL_VERSION);
		net.write(TYPE_POSITION, send_x);
		net.write(TYPE_POSITION, send_y);
		net.write(buffer_u8, facing_direction);

		/* Represent walking with one and idle with zero for the packet's byte-sized animation flag */
		net.write(buffer_u8, is_moving ? 1 : 0);

		/* Send result controls connection-loss reporting and whether this state becomes the new
		successful-send baseline */
		var send_result = net.send_server();

		/* A negative send result leaves prior send history intact and returns failure after optional
		connection-loss reporting */
		if (send_result < 0)
		{
			/* Notify the client of connection loss only when its handler exists, then return the
			failed send result */
			if (variable_struct_exists(client, "mark_connection_lost"))
			{
				client.mark_connection_lost("Lost connection to server.");
			}
			return send_result;
		}

		client_state_has_sent = true;
		client_state_last_sent_x = send_x;
		client_state_last_sent_y = send_y;
		client_state_last_sent_direction = facing_direction;
		client_state_last_sent_moving = is_moving;
		client_state_next_send_at = current_time + client_state_send_interval_ms;
		return send_result;
	}

	/// @description Apply client-owned movement on the server through room and wall checks, mark relay state dirty, and send wall corrections when blocked
	/// @param {Real} x Requested horizontal room position in pixels
	/// @param {Real} y Requested vertical room position in pixels
	/// @param {Real} client_direction Facing direction from the client packet
	/// @param {Real} client_is_moving Nonzero when the client reports movement
	/// @returns {Bool} Whether position or animation state changed
	receive_client_player_state = function(x, y, client_direction, client_is_moving)
	{
		/* old_x and old_y retain the server's previous room position. clamped resolves the client
		request against room margins and authoritative walls before it is stored */
		var old_x = pos.x;
		var old_y = pos.y;
		var clamped = resolve_wall_position(old_x, old_y, x, y, true);
		pos.x = clamped.x;
		pos.y = clamped.y;
		visual_pos.x = pos.x;
		visual_pos.y = pos.y;

		/* visual_state_changed records a facing/walking update and position_changed compares accepted
		room coordinates with the old server position */
		var visual_state_changed = set_visual_state(client_direction, client_is_moving);
		var position_changed = pos.x != old_x || pos.y != old_y;

		/* Shared server records activity, schedules position relays and sends wall corrections for
		this player */
		var server = scr_get_server();

		/* Accepted positional movement counts as gameplay activity when the server provides its
		activity hook. Animation-only updates do not reset that activity here */
		if (position_changed
		&& is_struct(server)
		&& variable_struct_exists(server, "note_client_gameplay_activity"))
		{
			server.note_client_gameplay_activity(ID);
		}

		/* A position or visual change marks this slot dirty when supported, ensuring the next relay
		carries whichever part changed */
		if ((position_changed || visual_state_changed)
		&& is_struct(server)
		&& variable_struct_exists(server, "mark_position_dirty"))
		{
			server.mark_position_dirty(ID);
		}

		/* Blocked wall travel sends corrected accepted coordinates back to the owner so client and
		server agree on the wall boundary */
		if (clamped.blocked)
		{
			send_wall_correction(server);
		}

		/* Report a change for accepted movement or animation changes, even when the requested
		destination was constrained */
		return position_changed || visual_state_changed;
	}
	#endregion /* Client Movement Authority END */

	#region /* Server Snapshots and Visual Interpolation */
	/// @description Consume a server snapshot. Local owned movement records diagnostics while remote movement updates interpolation samples
	/// @param {Real} x Server horizontal room position in pixels
	/// @param {Real} y Server vertical room position in pixels
	/// @param {Real} server_direction Optional facing direction from newer snapshot packets, default undefined
	/// @param {Real} server_is_moving Optional movement state, default undefined. Both animation fields must be present to update visual state
	receive_server_position = function(x, y, server_direction = undefined, server_is_moving = undefined)
	{
		/* is_local distinguishes ownership handling. predicted_x/y retain the drawn position for
		diagnostics, client_was_moving keeps predicted animation, previous_direction controls
		whether a new velocity sample can be smoothed */
		var is_local = is_local_client_player();
		var predicted_x = visual_pos.x;
		var predicted_y = visual_pos.y;
		var client_was_moving = is_moving;
		var previous_direction = facing_direction;

		/* Server coordinates constrained to room margins before use as a snapshot target or diagnostic
		acknowledgement */
		var clamped = player_clamp_position(x, y);

		/* Both optional animation fields must be present to accept server walking state. Older
		position-only snapshots leave authoritative_is_moving unchanged */
		if (!is_undefined(server_direction)
		&& !is_undefined(server_is_moving))
		{
			/* A nonzero server walking flag means motion is active. Zero clears it independently of
			the facing field */
			authoritative_is_moving = server_is_moving != 0;
		}

		/* This client's position is now authoritative for its own movement. Server
		snapshots are relay acknowledgements for diagnostics only and must never
		pull, lerp, or snap the local player backward */
		if (is_local && client_position_authority)
		{
			/* Local client records relay diagnostics without altering this owned player's predicted
			coordinates */
			var client = scr_get_client();

			/* Record acknowledgement diagnostics only when the client exposes the optional
			movement-snapshot hook. Otherwise still return from this owned-player path */
			if (is_struct(client)
			&& variable_struct_exists(client, "record_local_movement_snapshot"))
			{
				client.record_local_movement_snapshot(
					predicted_x,
					predicted_y,
					clamped.x,
					clamped.y,
					client_was_moving,
					authoritative_is_moving,
					false
				);
			}
			return;
		}

		pos.x = clamped.x;
		pos.y = clamped.y;

		/* Update facing and walking together only when both optional snapshot fields are present,
		preserving compatibility with older position-only packets */
		if (!is_undefined(server_direction)
		&& !is_undefined(server_is_moving))
		{
			set_visual_state(server_direction, server_is_moving);
		}

		/* Only remote snapshots establish extrapolation velocity. Local fallback snapshots continue
		through correction and diagnostics instead */
		if (!is_local)
		{
			/* Arrival timestamp uses current_time milliseconds and becomes the baseline for the next
			remote interval sample */
			var snapshot_now = current_time;

			/* A previous nonzero arrival time permits a measured interval and velocity. The first
			snapshot establishes the baseline without deriving motion from spawn time */
			if (remote_snapshot_received_at > 0)
			{
				/* snapshot_elapsed_ms is at least one millisecond to avoid zero-interval velocity
				division and becomes the most recent arrival interval */
				var snapshot_elapsed_ms = max(1, snapshot_now - remote_snapshot_received_at);
				remote_snapshot_interval_ms = snapshot_elapsed_ms;

				/* The first timing sample replaces the -1 average sentinel. Later samples blend 20
				percent of the new interval into the existing average */
				remote_snapshot_average_ms = remote_snapshot_average_ms < 0
					? snapshot_elapsed_ms
					: lerp(remote_snapshot_average_ms, snapshot_elapsed_ms, 0.20);

				/* sampled_velocity_x and sampled_velocity_y measure room pixels per millisecond since
				the last snapshot. maximum_axis_velocity limits each axis to 1.5 times nominal
				movement speed */
				var sampled_velocity_x = (pos.x - remote_snapshot_x) / snapshot_elapsed_ms;
				var sampled_velocity_y = (pos.y - remote_snapshot_y) / snapshot_elapsed_ms;
				var maximum_axis_velocity = movement_speed * 60 / 1000 * 1.5;
				sampled_velocity_x = clamp(sampled_velocity_x, -maximum_axis_velocity, maximum_axis_velocity);
				sampled_velocity_y = clamp(sampled_velocity_y, -maximum_axis_velocity, maximum_axis_velocity);

				/* Older packets infer movement from sampled nonzero velocity. Newer packets use their
				explicit movement flag so stationary snapshots can discard residual velocity */
				var snapshot_reports_movement = is_undefined(server_is_moving)
					? sampled_velocity_x != 0 || sampled_velocity_y != 0
					: server_is_moving != 0;

				/* Reported movement keeps a usable velocity estimate for brief extrapolation. Idle
				reports instead reset both axes below */
				if (snapshot_reports_movement)
				{
					/* A first velocity sample or changed facing starts a fresh estimate to avoid
					blending incompatible directions */
					if (!remote_velocity_valid || previous_direction != facing_direction)
					{
						remote_velocity_x = sampled_velocity_x;
						remote_velocity_y = sampled_velocity_y;
					}

					/* With valid same-direction history, smooth the new sample into the previous
					velocity to reduce snapshot timing jitter */
					else
					{
						remote_velocity_x = lerp(remote_velocity_x, sampled_velocity_x, remote_velocity_smoothing);
						remote_velocity_y = lerp(remote_velocity_y, sampled_velocity_y, remote_velocity_smoothing);
					}
					remote_velocity_valid = true;
				}

				/* Idle snapshots clear motion estimates so remote visuals stop extrapolating past the
				stationary position */
				else
				{
					remote_velocity_x = 0;
					remote_velocity_y = 0;
					remote_velocity_valid = false;
				}
			}
			remote_snapshot_received_at = snapshot_now;
			remote_snapshot_x = pos.x;
			remote_snapshot_y = pos.y;
		}

		/* dx and dy measure the room-pixel correction from the draw position to the snapshot.
		safety_snap compares squared distance with the configured snap radius */
		var dx = pos.x - visual_pos.x;
		var dy = pos.y - visual_pos.y;
		var safety_snap = dx * dx + dy * dy > local_snap_distance * local_snap_distance;

		/* A correction beyond local_snap_distance immediately aligns visuals with the snapshot.
		Smaller gaps remain for normal interpolation */
		if (safety_snap)
		{
			visual_pos.x = pos.x;
			visual_pos.y = pos.y;

			/* Remote safety snaps discard velocity so extrapolation cannot immediately pull away from
			the corrected position */
			if (!is_local)
			{
				remote_velocity_x = 0;
				remote_velocity_y = 0;
				remote_velocity_valid = false;
			}
		}

		/* Only local fallback movement records correction diagnostics here. Owned local movement
		returned earlier without applying snapshots */
		if (is_local)
		{
			/* Fallback client receives predicted and corrected positions for movement diagnostics */
			var fallback_client = scr_get_client();

			/* Record fallback diagnostics only when that optional client hook exists, leaving
			correction behavior independent of diagnostic availability */
			if (is_struct(fallback_client)
			&& variable_struct_exists(fallback_client, "record_local_movement_snapshot"))
			{
				fallback_client.record_local_movement_snapshot(
					predicted_x,
					predicted_y,
					pos.x,
					pos.y,
					client_was_moving,
					authoritative_is_moving,
					safety_snap
				);
			}
		}
	}

	/// @description Update draw position using owned local movement, fallback correction or constrained remote interpolation
	update_visual = function()
	{
		/* Local-player status decides whether visuals directly follow owned movement or use
		correction/interpolation */
		var is_local = is_local_client_player();

		/* Owned local positions copy directly to visual_pos and return, keeping server relays from
		dragging the owner backward */
		if (is_local && client_position_authority)
		{
			visual_pos.x = pos.x;
			visual_pos.y = pos.y;
			return;
		}

		/* target_x and target_y begin at the received physics position. Eligible remote movement below
		can extend that target briefly */
		var target_x = pos.x;
		var target_y = pos.y;

		/* Extrapolate only remote players that the server reports moving, with valid velocity and a
		timed snapshot. Other players keep the received position as their target */
		if (!is_local
		&& authoritative_is_moving
		&& remote_velocity_valid
		&& remote_snapshot_received_at > 0)
		{
			/* Position batches are intentionally sparse. Continue along the measured
			path briefly so remote players do not accelerate toward a snapshot and
			then visibly slow down while waiting for the next one */
			/* snapshot_age_ms is current_time time since receipt, capped by the extrapolation limit.
			extrapolated applies the velocity estimate through room and wall constraints */
			var snapshot_age_ms = clamp(current_time - remote_snapshot_received_at, 0, remote_extrapolation_limit_ms);
			var extrapolated = resolve_wall_position(
				pos.x,
				pos.y,
				pos.x + remote_velocity_x * snapshot_age_ms,
				pos.y + remote_velocity_y * snapshot_age_ms
			);
			target_x = extrapolated.x;
			target_y = extrapolated.y;
		}

		/* dx and dy measure the room-pixel gap to this target. local_active_movement combines local
		ownership status with walking animation for fallback correction strength */
		var dx = target_x - visual_pos.x;
		var dy = target_y - visual_pos.y;
		var local_active_movement = is_local && is_moving;

		/* During local fallback movement, ignore gaps inside the correction deadzone so small relays
		do not fight current input. Larger gaps and idle or remote players continue to interpolation */
		if (local_active_movement
		&& dx * dx + dy * dy <= local_movement_correction_deadzone * local_movement_correction_deadzone)
		{
			return;
		}

		/* amount uses the weaker movement correction for an active local fallback, ordinary local
		correction while idle and remote_lerp_amount for remote players */
		var amount = is_local
			? (local_active_movement ? local_movement_correction_lerp : local_correction_lerp)
			: remote_lerp_amount;

		/* Only remote interpolation is adjusted for delta_time so its visual smoothing has similar
		timing across frame rates */
		if (!is_local)
		{
			/* frame_scale converts delta_time microseconds into nominal 60 Hz steps and caps
			long-frame correction at three steps */
			var frame_scale = clamp(delta_time / (1000000 / 60), 0, 3);
			amount = 1 - power(1 - remote_lerp_amount, frame_scale);
		}

		/* Within half a room pixel, finish the correction exactly and return instead of continuing an
		almost-complete interpolation */
		if (dx * dx + dy * dy <= 0.25)
		{
			visual_pos.x = target_x;
			visual_pos.y = target_y;
			return;
		}

		/* clamped resolves the interpolated move against walls and room bounds so visual smoothing
		does not draw the player through collision geometry */
		var clamped = resolve_wall_position(
			visual_pos.x,
			visual_pos.y,
			lerp(visual_pos.x, target_x, amount),
			lerp(visual_pos.y, target_y, amount)
		);
		visual_pos.x = clamped.x;
		visual_pos.y = clamped.y;
	}
	#endregion /* Server Snapshots and Visual Interpolation END */

	#region /* Player Rendering */
	/// @description Draw this player's character, social marker, hover highlight and host-aware nameplate at its visual position
	render = function()
	{
		update_visual();

		/* draw_x and draw_y use visual_pos, keeping the character, nameplate and social marker aligned
		with interpolation */
		var draw_x = visual_pos.x;
		var draw_y = visual_pos.y;

		/* Diagnostics fades only the artwork to half opacity. The fixed collision body and movement
		stay the same when the local overlay setting is enabled */
		var show_collision_mask = global.show_collision_mask;
		var character_alpha = show_collision_mask ? 0.5 : 1;

		/* Draw the companion before its owner so overlapping artwork keeps the player visible */
		scr_get_pets().render_for_player(self);
		scr_get_social().draw_friend_marker(self);
		player_character_draw_key(character_key, facing_direction, is_moving, draw_x, draw_y, player_size, c_white, character_alpha);

		/* Shared social state decides whether the hovered player card should highlight this sprite */
		var social_manager = scr_get_social();

		/* Only a social manager with the hover method returning true adds the translucent highlight.
		Other sprites use their ordinary draw */
		if (is_struct(social_manager)
		&& variable_struct_exists(social_manager, "player_card_hovered")
		&& social_manager.player_card_hovered(ID))
		{
			gpu_set_blendmode(bm_add);
			player_character_draw_key(character_key, facing_direction, is_moving, draw_x, draw_y, player_size, c_white, 0.30 * character_alpha);
			gpu_set_blendmode(bm_normal);
		}

		/* Nameplate text begins with the stored username before applying readable fallback and host
		labeling */
		var name_text = string(username);

		/* An empty stored name draws Player, retaining a readable label even when identity data is
		incomplete */
		if (name_text == "")
		{
			name_text = "Player";
		}

		/* Client identity metadata supplies the host slot for the nameplate marker */
		var identity_client = scr_get_client();

		/* A player is the host only when the client exposes a host_player_slot matching this ID.
		Missing metadata leaves it unmarked */
		var is_host_player = is_struct(identity_client)
			&& variable_struct_exists(identity_client, "host_player_slot")
			&& identity_client.host_player_slot == ID;

		/* Host players receive the HOST prefix so the session owner is identifiable in world view */
		if (is_host_player)
		{
			name_text = "[HOST] " + name_text;
		}

		/* Hosts use a wider 154-pixel nameplate for the prefix. Other players keep the standard
		116-pixel width */
		var nameplate_width = is_host_player ? 154 : 116;

		/* nameplate_height is 22 room pixels and nameplate_gap is ten. sprite_top and sprite_center_x
		anchor the label to the selected character's actual frame metrics */
		var nameplate_height = 22;
		var nameplate_gap = 10;
		var sprite_top = player_character_top_y_key(character_key, draw_y, player_size);
		var sprite_center_x = player_character_center_x_key(character_key, draw_x, player_size);

		/* plate_x1 and plate_y1 are the nameplate's top-left room coordinates. plate_x2 and plate_y2
		add its width and height for drawing */
		var plate_x1 = sprite_center_x - nameplate_width * 0.5;
		var plate_y1 = sprite_top - nameplate_gap - nameplate_height;
		var plate_x2 = plate_x1 + nameplate_width;
		var plate_y2 = plate_y1 + nameplate_height;

		draw_set_alpha(0.54);
		draw_set_colour(c_black);
		draw_rectangle(plate_x1, plate_y1, plate_x2, plate_y2, false);
		draw_set_alpha(1);

		/* Host labels add a gold outline. Ordinary players retain the plain filled plate */
		if (is_host_player)
		{
			draw_set_colour(make_color_rgb(255, 220, 95));
			draw_rectangle(plate_x1, plate_y1, plate_x2, plate_y2, true);
		}

		draw_set_halign(fa_center);

		/* Host name text uses the same gold accent as its outline, while other usernames remain white */
		draw_set_colour(is_host_player ? make_color_rgb(255, 220, 95) : c_white);
		scr_render_text(sprite_center_x, plate_y1 + 3, name_text, 16, nameplate_width - 10);
		draw_set_halign(fa_left);

		/* Show the circle used by movement at its actual physics position. Smoothed sprite placement
		is a separate marker so network interpolation cannot disguise the tested collision shape */
		if (show_collision_mask)
		{
			/* Retain the caller's draw state so the diagnostic shapes and labels do not affect later
			players or world rendering */
			var restore_alpha = draw_get_alpha();
			var restore_colour = draw_get_colour();
			var restore_font = draw_get_font();
			var restore_halign = draw_get_halign();
			var restore_valign = draw_get_valign();

			/* Compare the visual origin with physics exactly. Green marks the collision body and cyan
			marks the separate visual position */
			var visual_origin_differs = draw_x != pos.x || draw_y != pos.y;
			var mask_colour = make_color_rgb(100, 230, 140);
			var visual_colour = make_color_rgb(80, 220, 255);

			draw_set_colour(mask_colour);
			draw_set_alpha(0.20);
			draw_circle(pos.x, pos.y, wall_collision_radius, false);
			draw_set_alpha(1);
			draw_circle(pos.x, pos.y, wall_collision_radius, true);

			/* A cyan X and line identify the sprite's smoothed draw origin only when it differs from
			the circle's center. They are not another collision mask */
			if (visual_origin_differs)
			{
				draw_set_colour(visual_colour);
				draw_set_alpha(0.75);
				draw_line(pos.x, pos.y, draw_x, draw_y);
				draw_set_alpha(1);
				draw_line_width(draw_x - 4, draw_y - 4, draw_x + 4, draw_y + 4, 2);
				draw_line_width(draw_x - 4, draw_y + 4, draw_x + 4, draw_y - 4, 2);
			}

			draw_set_colour(c_red);
			draw_line_width(pos.x - 6, pos.y, pos.x + 6, pos.y, 2);
			draw_line_width(pos.x, pos.y - 6, pos.x, pos.y + 6, 2);

			/* Sheet offsets use source pixels. The circle uses room pixels and remains independent
			of these visual metrics, including for custom characters */
			var character_sheet = player_character_get(character_key);

			/* Labels describe the collision size, visual offsets and marker meanings. A fifth row is
			needed only while the visual origin is separated from physics */
			var debug_lines = [
				"Radius: " + string(wall_collision_radius) + " room px",
				"X Offset: " + string(character_sheet.xorigin) + " source px",
				"Y Offset: " + string(character_sheet.yorigin) + " source px",
				"Red +: actual collision origin"
			];
			if (visual_origin_differs)
			{
				debug_lines[array_length(debug_lines)] = "Cyan X: smoothed sprite origin";
			}

			/* The panel is at most 240 room pixels wide, with 17 pixels per row and eight for padding.
			Keep its edges four pixels inside the room. Position it above the nameplate when space
			permits, or below the full sprite frame near the top edge */
			var debug_width = min(240, room_width - 8);
			var debug_height = array_length(debug_lines) * 17 + 8;
			var debug_left = clamp(sprite_center_x - debug_width * 0.5, 4, room_width - debug_width - 4);
			var debug_top = plate_y1 - debug_height - 6;
			if (debug_top < 4)
			{
				debug_top = player_character_bottom_y_key(character_key, draw_y, player_size) + 6;
			}
			debug_top = clamp(debug_top, 4, room_height - debug_height - 4);
			draw_set_colour(c_black);
			draw_set_alpha(0.72);
			draw_rectangle(debug_left, debug_top, debug_left + debug_width, debug_top + debug_height, false);
			draw_set_alpha(1);
			draw_set_colour(c_white);
			draw_set_halign(fa_left);
			draw_set_valign(fa_top);
			for (var debug_line = 0; debug_line < array_length(debug_lines); debug_line++)
			{
				scr_render_text(debug_left + 6, debug_top + 4 + debug_line * 17, debug_lines[debug_line], 14, debug_width - 12);
			}

			draw_set_alpha(restore_alpha);
			draw_set_colour(restore_colour);
			draw_set_font(restore_font);
			draw_set_halign(restore_halign);
			draw_set_valign(restore_valign);
		}
	}
	#endregion /* Player Rendering END */

	#region /* Movement Updates */
	/// @description Poll local input, send changed actions, and advance either negotiated local movement or the legacy prediction fallback
	update_client = function()
	{
		/* Shared network writer is reused to send each changed movement action for this player */
		var net = scr_get_network();

		/* Fresh movement input state supplies the four current directional flags */
		var input_state = scr_player_input_movement_state();

		/* action_changes pairs each movement action with its stored old_state and freshly polled
		new_state. All four records share this layout so unchanged actions can be skipped by the
		sender */
		var action_changes =
		[
			{ action: PLAYER_INPUT_LEFT, old_state: left, new_state: input_state.left },
			{ action: PLAYER_INPUT_RIGHT, old_state: right, new_state: input_state.right },
			{ action: PLAYER_INPUT_UP, old_state: up, new_state: input_state.up },
			{ action: PLAYER_INPUT_DOWN, old_state: down, new_state: input_state.down }
		];

		/* i visits the four action records from zero to the end, stopping the update if any
		changed-action send fails */
		for (var i = 0; i < array_length(action_changes); i++)
		{
			/* action_change is the current direction record and send_result reports the helper's
			skipped, successful or failed send */
			var action_change = action_changes[i];
			var send_result = scr_player_input_send_action_if_changed(net, ID, action_change.action, action_change.old_state, action_change.new_state);

			/* A failed action send aborts this input update before stored flags or movement are
			changed, then reports connection loss when supported */
			if (send_result < 0)
			{
				/* Shared client is retrieved only on send failure to notify its connection-loss
				handler */
				var client = scr_get_client();

				/* Notify connection loss only when the client is a struct exposing the handler,
				otherwise return with the failed send still ending this update */
				if (is_struct(client)
				&& variable_struct_exists(client, "mark_connection_lost"))
				{
					client.mark_connection_lost("Lost connection to server.");
				}
				return;
			}
		}

		left = input_state.left;
		right = input_state.right;
		up = input_state.up;
		down = input_state.down;

		/* dx and dy combine opposing directional inputs into the requested movement vector.
		motion_changed records facing or walking changes for immediate animation sends */
		var dx = right - left;
		var dy = down - up;
		var motion_changed = set_motion_from_vector(dx, dy);

		/* Negotiated local authority updates pos directly, mirrors it for drawing and sends owned
		state. Without authority, use the legacy visual prediction path below */
		if (client_position_authority)
		{
			/* Nonzero input advances owned position through room and wall checks. A stationary vector
			retains its position but can still send changed animation */
			if (dx != 0 || dy != 0)
			{
				/* step_distance is delta-time-scaled room travel and movement contains the
				collision-constrained destination for this input vector */
				var step_distance = movement_step_distance();
				var movement = resolve_wall_position(pos.x, pos.y, pos.x + dx * step_distance, pos.y + dy * step_distance);
				pos.x = movement.x;
				pos.y = movement.y;
			}
			visual_pos.x = pos.x;
			visual_pos.y = pos.y;
			authoritative_is_moving = is_moving;
			send_client_player_state(motion_changed);
			return;
		}

		/* Compatibility fallback for older servers that do not acknowledge the
		optional client-owned movement protocol */
		/* Legacy fallback predicts only while input requests movement. Idle visuals remain available
		for server correction through update_visual */
		if (dx != 0 || dy != 0)
		{
			/* Constrained visual prediction uses the legacy pixels-per-Step speed because older
			servers retain authoritative position updates */
			var clamped = resolve_wall_position(visual_pos.x, visual_pos.y, visual_pos.x + dx * movement_speed, visual_pos.y + dy * movement_speed);
			visual_pos.x = clamped.x;
			visual_pos.y = clamped.y;
		}
	}

	/// @description Poll input and advance room and wall-constrained movement using delta time
	update_singleplayer = function()
	{
		/* Current singleplayer input supplies directional state without requiring network action
		messages */
		var input_state = scr_player_input_movement_state();
		left = input_state.left;
		right = input_state.right;
		up = input_state.up;
		down = input_state.down;

		/* dx and dy form the local movement vector from opposing input flags */
		var dx = right - left;
		var dy = down - up;
		set_motion_from_vector(dx, dy);

		/* Only nonzero input needs collision-resolved travel. At rest the position and visuals remain
		unchanged while animation has already been updated */
		if (dx != 0 || dy != 0)
		{
			/* step_distance scales travel with delta_time and movement stores the
			room/wall-constrained destination, shared by physics and drawing */
			var step_distance = movement_step_distance();
			var movement = resolve_wall_position(pos.x, pos.y, pos.x + dx * step_distance, pos.y + dy * step_distance);
			pos.x = movement.x;
			pos.y = movement.y;
			visual_pos.x = pos.x;
			visual_pos.y = pos.y;
		}
	}

	/// @description Advance legacy server-owned movement once per server Step. Negotiated client-owned positions are supplied by packets
	update_server = function()
	{
		/* Shared server supplies this slot's connection state before applying legacy authoritative
		movement */
		var server = scr_get_server();

		/* A missing server, missing socket array, invalid slot or empty socket clears held inputs and
		skips movement. Disconnected players must not continue walking from stale flags */
		if (!is_struct(server)
		|| !variable_struct_exists(server, "sockets")
		|| !is_array(server.sockets)
		|| ID < 0
		|| ID >= array_length(server.sockets)
		|| server.sockets[ID] == noone)
		{
			left = 0;
			right = 0;
			up = 0;
			down = 0;
			return;
		}

		/* Negotiated client-owned slots are moved by received packets. Mirror their position for
		drawing and return so the legacy Step path does not also advance them */
		if (variable_struct_exists(server, "slot_uses_client_movement_authority")
		&& server.slot_uses_client_movement_authority(ID))
		{
			visual_pos.x = pos.x;
			visual_pos.y = pos.y;
			return;
		}

		/* dx/dy form the held-input vector, old_x/old_y retain the previous position and
		visual_state_changed records this update's facing/walking change */
		var dx = right - left;
		var dy = down - up;
		var old_x = pos.x;
		var old_y = pos.y;
		var visual_state_changed = set_motion_from_vector(dx, dy);

		/* A nonzero vector attempts collision-constrained movement against server walls. Zero input
		skips position travel */
		if (dx != 0 || dy != 0)
		{
			/* movement contains the accepted room coordinates from the requested legacy movement
			increment */
			var movement = resolve_wall_position(pos.x, pos.y, pos.x + dx * movement_speed, pos.y + dy * movement_speed, true);
			pos.x = movement.x;
			pos.y = movement.y;
		}

		apply_clamp();

		/* Actual position changes align visuals and trigger gameplay activity and position relays.
		Unchanged coordinates leave those hooks for the animation-only alternative */
		if (pos.x != old_x || pos.y != old_y)
		{
			visual_pos.x = pos.x;
			visual_pos.y = pos.y;

			/* Record activity only when the server exposes its activity hook, so compatibility does
			not prevent accepted movement */
			if (variable_struct_exists(server, "note_client_gameplay_activity"))
			{
				server.note_client_gameplay_activity(ID);
			}

			/* Mark changed coordinates dirty only when the server provides this relay hook */
			if (variable_struct_exists(server, "mark_position_dirty"))
			{
				server.mark_position_dirty(ID);
			}
		}

		/* With no positional change, changed animation still requests a relay when the hook exists.
		Completely unchanged state schedules no additional packet */
		else if (visual_state_changed
		&& variable_struct_exists(server, "mark_position_dirty"))
		{
			server.mark_position_dirty(ID);
		}
	}
	#endregion /* Movement Updates END */

}
