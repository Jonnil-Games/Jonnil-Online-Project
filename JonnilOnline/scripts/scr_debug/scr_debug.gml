#region /* Debug Message Store */
/// @description Own the visible debug history and the larger export transcript
function scr_debug() constructor
{

	/* messages owns the visible ds_list and export_messages owns a separate transcript list
	Both are shared through this constructor instance, and clear empties their contents without destroying the lists */
	messages = ds_list_create();
	export_messages = ds_list_create();

	/* scroll_offset starts at the latest entries with zero older-line offset
	max_messages caps visible history at 200 lines, while max_export_messages retains up to 10000 transcript lines */
	scroll_offset = 0;
	max_messages = 200;
	max_export_messages = 10000;
	
	/// @description Redact, split and retain a coloured message in visible and export histories
	/// @param {String} message Text to record
	/// @param {Real} r Red channel byte
	/// @param {Real} g Green channel byte
	/// @param {Real} b Blue channel byte
	/// @param {String} level Transcript severity. Defaults to INFO
	make_message = function(message, r, g, b, level = "INFO")
	{
		/* Redact before storing either the visible lines or the persistent transcript */
		var _text = scr_server_logs_redact(message);
		scr_server_logs_append("technical", "[" + chat_export_timestamp() + "] [" + string(level) + "] " + _text);
		_text = string_replace_all(_text, "\r", "");

		/* _lines splits normalized LF-separated text, _count bounds traversal, and now captures local wall-clock time
		stamp combines local HH:MM:SS with the current_time millisecond remainder for each exported line */
		var _lines = string_split(_text, "\n");
		var _count = array_length(_lines);
		var now = date_current_datetime();
		var stamp = scr_debug_export_pad_number(date_get_hour(now), 2)
			+ ":" + scr_debug_export_pad_number(date_get_minute(now), 2)
			+ ":" + scr_debug_export_pad_number(date_get_second(now), 2)
			+ "." + string(current_time mod 1000);
		
		/* If splitting returns no entries, retain the original text as one message so the call is still recorded */
		if (_count <= 0)
		{
			_lines = [ _text ];
			_count = 1;
		}
		
		/* Store every zero-based split line in order in both histories */
		for (var i = 0; i < _count; i++)
		{
			/* Keep this line's text separately so an empty entry can be replaced without changing the source array */
			var _line = _lines[i];

			/* Use a single space for blank entries so visible line spacing is retained */
			if (_line == "")
			{
				_line = " ";
			}
			
			/* Each visible entry stores txt and the red/green/blue byte values used by draw_log */
			ds_list_add(messages,
			{
				txt: _line,
				red: r,
				green: g,
				blue: b
			});
			ds_list_add(export_messages, stamp + " [" + string(level) + "] " + _line);

			/* Drop oldest visible lines above the 200-line cap and reduce the scroll offset to account for their removal */
			while (ds_list_size(messages) > max_messages)
			{
				ds_list_delete(messages, 0);
				scroll_offset = max(0, scroll_offset - 1);
			}

			/* Trim only the oldest transcript lines above its separate 10000-line cap */
			while (ds_list_size(export_messages) > max_export_messages)
			{
				ds_list_delete(export_messages, 0);
			}
		}
	}
	
	/// @description Clamp the older-line offset to the current panel capacity
	/// @param {Real} max_visible Maximum visible lines
	clamp_scroll = function(max_visible)
	{
		/* Compute the largest older-line offset that still fills the visible panel, with zero when the history is short */
		var max_offset = max(0, ds_list_size(messages) - max_visible);
		scroll_offset = clamp(scroll_offset, 0, max_offset);
	}
	
	/// @description Move the view toward older or newer messages
	/// @param {Real} delta Line offset. Positive values select older messages
	scroll_by = function(delta)
	{
		scroll_offset += delta;

		/* Negative offsets cannot move newer than the latest message, so clamp that end immediately */
		if (scroll_offset < 0)
		{
			scroll_offset = 0;
		}
	}
	
	/// @description Return the view to the latest messages
	scroll_home = function()
	{
		scroll_offset = 0;
	}
	
	/// @description Record a white informational message
	/// @param {String} message Text to retain and persist
	log = function(message)
	{
		make_message(message, 255, 255, 255, "INFO");
	}
	
	/// @description Record a red error message
	/// @param {String} message Text to retain and persist
	error = function(message)
	{
		make_message(message, 255, 0, 0, "ERROR");
	}
	
	/// @description Record a green success message
	/// @param {String} message Text to retain and persist
	success = function(message)
	{
		make_message(message, 0, 255, 0, "SUCCESS");
	}
	
	/// @description Empty both in-memory histories and reset scrolling
	clear = function()
	{
		ds_list_clear(messages);
		ds_list_clear(export_messages);
		scroll_offset = 0;
	}

	/// @description Copy the retained transcript for export
	/// @returns {Array<String>} New array in recorded line order
	copy_export_lines = function()
	{
		/* line_count is the retained transcript length, and lines is a new array for a stable export snapshot */
		var line_count = ds_list_size(export_messages);
		var lines = array_create(line_count);

		/* Copy every zero-based transcript entry in recorded order without altering the store */
		for (var line_index = 0; line_index < line_count; line_index++)
		{
			lines[line_index] = ds_list_find_value(export_messages, line_index);
		}

		return lines;
	}
	
	/// @description Draw visible debug history using a cached surface
	/// @param {Real} x1 Left GUI fraction. Defaults to 0
	/// @param {Real} y1 Top GUI fraction. Defaults to 0
	/// @param {Real} x2 Right GUI fraction. Defaults to 1
	/// @param {Real} y2 Bottom GUI fraction. Defaults to 1
	/// @param {Real} size Text height as a panel-height fraction. Defaults to 0.16
	draw_log = function(x1 = 0, y1 = 0, x2 = 1, y2 = 1, size = 0.16)
	{
		/* gui_width/gui_height convert the supplied fractional panel bounds into GUI pixels */
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();
		
		/* xx/yy are the panel's GUI top-left, and width/height are its pixel dimensions
		Scale the requested fractional text size by panel height */
		var xx = x1 * gui_width;
		var yy = y1 * gui_height;
		var width = (x2 - x1) * gui_width;
		var height = (y2 - y1) * gui_height;
		size *= height;
		
		/* Keep one owned log surface between draws, starting at noone until the first allocation
		It is recreated after surface loss, using the dimensions of that allocation */
		static surface = noone;
		
		/* Create the cached surface when missing before setting it as the render target */
		if (!surface_exists(surface))
		{
			surface = surface_create(width, height);
		}
		
		surface_set_target(surface);
		draw_clear(make_colour_rgb(25, 25, 25));

		/* padding leaves a 16-pixel inset, line_height keeps the divisor at least one pixel,
		and max_visible is the number of complete lines that fit in the panel */
		var padding = 16;
		var line_height = max(1, size);
		var max_visible = max(1, floor((height - padding * 2) / line_height));
		clamp_scroll(max_visible);
		
		/* total counts retained visible messages, newest offsets backwards from the latest entry,
		oldest bounds the displayed range, and dy starts at the panel's lower padding edge */
		var total = ds_list_size(messages);
		var newest = total - 1 - scroll_offset;
		var oldest = max(0, newest - max_visible + 1);
		var dy = height - padding;
		
		/* Walk the selected zero-based indices from newest to oldest while drawing upward from the bottom */
		for(var i = newest; i >= oldest; i--)
		{
			/* Borrow the visible entry's text and RGB fields for this draw */
			var msg = ds_list_find_value(messages, i)
			draw_set_colour(make_color_rgb(msg.red, msg.green, msg.blue));
			dy -= size;
			scr_render_text(padding, dy - padding, msg.txt, size, width - padding * 2);
		}
		
		/* Only histories larger than the viewport need a line-range and scrolling indicator */
		if (total > max_visible)
		{
			draw_set_colour(c_ltgray);

			/* Display one-based range numbers to the human reader while the underlying message indices remain zero-based */
			var indicator = "Log " + string(oldest + 1) + "-" + string(newest + 1) + "/" + string(total)
				+ "  Wheel/PgUp/PgDn scroll, Home latest";
			scr_render_text(padding, padding, indicator, max(10, size * 0.35), width - padding * 2);
		}
		
		surface_reset_target();
		draw_surface(surface, xx, yy);
	}
}

/// @description Get the shared debug message store
/// @returns {Struct} Lazily constructed scr_debug instance
function scr_get_debug()
{
	/* Construct one runtime-wide debug store shared by all logging, scrolling and export calls */
	static d = new scr_debug();
	return d;
}

/// @description Get the shared debug store only when it is a struct
/// @returns {Struct|Undefined} Debug store, or undefined
function scr_try_get_debug()
{
	/* Get the shared store before checking that it is a usable struct */
	var _debugger = scr_get_debug();
	
	/* Return the store only when its type is usable, otherwise return undefined for guarded callers */
	if (is_struct(_debugger))
	{
		return _debugger;
	}
	
	return undefined;
}

/// @description Redact and append an informational message to Runner output and the debug store
/// @param {String} message Text to record. Newlines become separate visible entries
function debug_log(message)
{
	/* Redact the message before either Runner output or the retained debug histories receive it */
	var _message = scr_server_logs_redact(message);
	show_debug_message("[LOG] " + _message);
	
	/* Borrow the shared store for the corresponding message-level method */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before checking the method field, so Runner output remains available even without a usable store method */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "log"))
	{
		_debugger.log(_message);
	}
}

/// @description Redact and append an error message to Runner output and the debug store
/// @param {String} message Error text
function debug_error(message)
{
	/* Redact the message before either Runner output or the retained debug histories receive it */
	var _message = scr_server_logs_redact(message);
	show_debug_message("[ERROR] " + _message);
	
	/* Borrow the shared store for the corresponding message-level method */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before checking the method field, so Runner output remains available even without a usable store method */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "error"))
	{
		_debugger.error(_message);
	}
}

/// @description Redact and append a success message to Runner output and the debug store
/// @param {String} message Success text
function debug_success(message)
{
	/* Redact the message before either Runner output or the retained debug histories receive it */
	var _message = scr_server_logs_redact(message);
	show_debug_message("[SUCCESS] " + _message);
	
	/* Borrow the shared store for the corresponding message-level method */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before checking the method field, so Runner output remains available even without a usable store method */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "success"))
	{
		_debugger.success(_message);
	}
}

/// @description Clear both in-memory histories and reset scrolling. Saved server logs are retained
function debug_clear()
{
	/* Borrow the shared debug store before calling its requested operation */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before looking up the method, avoiding an invalid call when the store is unavailable */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "clear"))
	{
		_debugger.clear();
	}
}

/// @description Move the debug view relative to the newest entry
/// @param {Real} delta Number of lines. Positive values move toward older messages
function debug_scroll(delta)
{
	/* Borrow the shared debug store before calling its requested operation */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before looking up the method, avoiding an invalid call when the store is unavailable */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "scroll_by"))
	{
		_debugger.scroll_by(delta);
	}
}

/// @description Return the shared debug view to its newest retained entry
function debug_scroll_home()
{
	/* Borrow the shared debug store before calling its requested operation */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before looking up the method, avoiding an invalid call when the store is unavailable */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "scroll_home"))
	{
		_debugger.scroll_home();
	}
}

/// @description Draw the shared debug history using fractions of the GUI dimensions
/// @param {Real} x1 Left edge as a fraction of GUI width, defaulting to 0
/// @param {Real} y1 Top edge as a fraction of GUI height, defaulting to 0
/// @param {Real} x2 Right edge as a fraction of GUI width, defaulting to 1
/// @param {Real} y2 Bottom edge as a fraction of GUI height, defaulting to 1
/// @param {Real} size Text height as a fraction of the log panel height, defaulting to 0.16
function debug_draw_log(x1 = 0, y1 = 0, x2 = 1, y2 = 1, size = 0.16)
{
	/* Borrow the shared debug store before calling its requested operation */
	var _debugger = scr_try_get_debug();
	
	/* Check the store type before looking up the method, avoiding an invalid call when the store is unavailable */
	if (is_struct(_debugger) && variable_struct_exists(_debugger, "draw_log"))
	{
		_debugger.draw_log(x1, y1, x2, y2, size);
	}
}
#endregion /* Debug Message Store END */

#region /* GUI Performance Measurements */
/// @description Read the overlay flag, initializing it to false when absent
/// @returns {Bool} Whether GUI timing measurements are enabled
function scr_ui_perf_enabled()
{
	/* Create the overlay flag only when absent, defaulting measurements to disabled */
	if (!variable_global_exists("ui_perf_overlay"))
	{
		global.ui_perf_overlay = false;
	}

	return global.ui_perf_overlay;
}

/// @description Toggle measurements and clear timing history when disabling them
/// @returns {Bool} New overlay-enabled state
function scr_ui_perf_toggle()
{
	global.ui_perf_overlay = !scr_ui_perf_enabled();

	/* Turning measurements off clears accumulated timings so a later toggle starts a fresh overlay */
	if (!global.ui_perf_overlay)
	{
		/* Clear smoothed named buckets only when their global has been initialized */
		if (variable_global_exists("ui_perf_buckets"))
		{
			global.ui_perf_buckets = {};
		}

		/* Clear current-frame totals only when their global has been initialized */
		if (variable_global_exists("ui_perf_frame_totals"))
		{
			global.ui_perf_frame_totals = {};
		}
	}
	return global.ui_perf_overlay;
}

/// @description Fold the previous frame into the overlay and reset totals at the start of the controller Draw event
/// @returns {Bool} Whether measurements are enabled
function scr_ui_perf_frame_begin()
{
	/* Disabled measurements skip frame aggregation and return false */
	if (!scr_ui_perf_enabled())
	{
		return false;
	}

	/* Create an empty smoothed-bucket struct for a missing or invalid global, checking existence before its type */
	if (!variable_global_exists("ui_perf_buckets") || !is_struct(global.ui_perf_buckets))
	{
		global.ui_perf_buckets = {};
	}

	/* Create an empty current-frame total struct for a missing or invalid global */
	if (!variable_global_exists("ui_perf_frame_totals") || !is_struct(global.ui_perf_frame_totals))
	{
		global.ui_perf_frame_totals = {};
	}

	/* At the start of Draw, fold the previous frame into smoothed millisecond totals.
	totals borrows those frame samples, and bucket_names lists existing smoothed categories */
	var totals = global.ui_perf_frame_totals;
	var bucket_names = variable_struct_get_names(global.ui_perf_buckets);

	/* Update each existing zero-based category using the previous frame's elapsed milliseconds */
	for (var bucket_index = 0; bucket_index < array_length(bucket_names); bucket_index++)
	{
		/* key names the current category, elapsed_ms uses its frame total or zero when absent,
		and previous is its smoothed value before the 82-percent-old, 18-percent-new blend */
		var key = bucket_names[bucket_index];
		var elapsed_ms = variable_struct_exists(totals, key) ? totals[$ key] : 0;
		var previous = global.ui_perf_buckets[$ key];
		global.ui_perf_buckets[$ key] = previous * 0.82 + elapsed_ms * 0.18;
	}

	/* List current-frame categories to discover samples without an existing smoothed bucket */
	var total_names = variable_struct_get_names(totals);

	/* Visit each zero-based sampled category to initialize new buckets */
	for (var total_index = 0; total_index < array_length(total_names); total_index++)
	{
		/* Select the sampled category's key for its initial smoothed value */
		var total_key = total_names[total_index];

		/* A newly sampled category starts directly at its current-frame total instead of blending against an invented prior value */
		if (!variable_struct_exists(global.ui_perf_buckets, total_key))
		{
			global.ui_perf_buckets[$ total_key] = totals[$ total_key];
		}
	}
	global.ui_perf_frame_totals = {};
	return true;
}

/// @description Add elapsed time to a named GUI performance bucket for this frame
/// @param {String} bucket_name Measurement group shown by the overlay
/// @param {Real} elapsed_ms Nonnegative elapsed milliseconds
/// @returns {Bool} Whether measurements are enabled and the sample was recorded
function scr_ui_perf_record(bucket_name, elapsed_ms)
{
	/* Skip recording when measurements are disabled */
	if (!scr_ui_perf_enabled())
	{
		return false;
	}

	/* Ensure current-frame totals are a struct before writing a named category */
	if (!variable_global_exists("ui_perf_frame_totals") || !is_struct(global.ui_perf_frame_totals))
	{
		global.ui_perf_frame_totals = {};
	}

	/* key converts the supplied group name to text, and previous is its frame total or zero for a first sample
	Clamp new elapsed time at zero before accumulating it in milliseconds */
	var key = string(bucket_name);
	var previous = variable_struct_exists(global.ui_perf_frame_totals, key)
		? global.ui_perf_frame_totals[$ key]
		: 0;
	global.ui_perf_frame_totals[$ key] = previous + max(0, real(elapsed_ms));
	return true;
}

/// @description Start a GUI performance measurement
/// @param {String} bucket_name Group name supplied by callers. Timing begins independently of the name
/// @returns {Real} get_timer timestamp in microseconds, or -1 when the overlay is disabled
function scr_ui_perf_begin(bucket_name)
{
	/* Return -1 when disabled so callers know no microsecond start timestamp was acquired */
	if (!scr_ui_perf_enabled())
	{
		return -1;
	}

	return get_timer();
}

/// @description Record the elapsed time since a GUI performance measurement began
/// @param {String} bucket_name Measurement group
/// @param {Real} started_at Microsecond timestamp returned by scr_ui_perf_begin
/// @returns {Bool} Whether a valid enabled measurement was recorded
function scr_ui_perf_end(bucket_name, started_at)
{
	/* Reject an invalid start token or measurements disabled since the sample began */
	if (started_at < 0 || !scr_ui_perf_enabled())
	{
		return false;
	}

	/* Convert get_timer's microsecond difference into milliseconds before recording it */
	var elapsed_ms = (get_timer() - started_at) / 1000;
	return scr_ui_perf_record(bucket_name, elapsed_ms);
}

/// @description Draw the known GUI categories from smoothed millisecond totals
/// @returns {Bool} Whether the enabled overlay was drawn
function scr_ui_perf_draw_overlay()
{
	/* Draw only when measurements are enabled and the smoothed-bucket global exists as a usable struct */
	if (!scr_ui_perf_enabled()
	|| !variable_global_exists("ui_perf_buckets")
	|| !is_struct(global.ui_perf_buckets))
	{
		return false;
	}

	/* gui_w bounds the panel's horizontal position, panel_w is 300 GUI pixels, and row_h is 16 pixels per measurement */
	var gui_w = max(1, display_get_gui_width());
	var panel_w = 300;
	var row_h = 16;

	/* These ordered category names select the known editor, drawing and text timings shown by the overlay */
	var rows =
	[
		"stamp.draw_library",
		"stamp.draw_editor",
		"stamp.grid",
		"stamp.preview",
		"stamp.colour_controls",
		"character.draw_main",
		"character.grid",
		"character.frames",
		"drawing.composite",
		"render_text"
	];

	/* panel_h fits the fixed header plus all rows, left anchors near the GUI's right edge,
	and top leaves an eight-pixel upper margin */
	var panel_h = 28 + array_length(rows) * row_h;
	var left = max(4, gui_w - panel_w - 8);
	var top = 8;

	draw_set_alpha(0.86);
	draw_set_colour(make_color_rgb(12, 14, 18));
	draw_rectangle(left, top, left + panel_w, top + panel_h, false);
	draw_set_alpha(1);
	draw_set_colour(make_color_rgb(255, 220, 95));
	draw_rectangle(left, top, left + panel_w, top + panel_h, true);
	draw_set_colour(c_white);
	scr_render_text(left + 8, top + 6, "UI perf ms (F9)", 13, panel_w - 16);

	/* Borrow the smoothed millisecond totals for drawing */
	var buckets = global.ui_perf_buckets;

	/* Draw each zero-based category row in the authored order */
	for (var row = 0; row < array_length(rows); row++)
	{
		/* key is the row's category name, and value uses its smoothed time or zero when no sample exists */
		var key = rows[row];
		var value = variable_struct_exists(buckets, key) ? buckets[$ key] : 0;

		/* Times above 4 ms use red, above 1.5 ms use yellow, and smaller totals use pale green */
		draw_set_colour(value > 4 ? make_color_rgb(244, 84, 84) : (value > 1.5 ? make_color_rgb(255, 220, 95) : make_color_rgb(178, 220, 184)));
		scr_render_text(left + 8, top + 25 + row * row_h, key + " " + string_format(value, 1, 2), 11, panel_w - 16);
	}

	draw_set_alpha(1);
	return true;
}
#endregion /* GUI Performance Measurements END */
