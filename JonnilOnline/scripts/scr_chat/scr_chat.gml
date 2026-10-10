#macro Chat scr_get_chat()

#region /* Username and Message Helpers */
/// @description Compare the beginning of a string with a supplied prefix
/// @param {String} text Text to inspect
/// @param {String} prefix Prefix to match
/// @returns {Bool} Whether the initial slice equals the prefix, including an empty prefix
function chat_text_starts_with(text, prefix)
{
	/* target is the supplied text and start is the prefix to compare at one-based position one */
	var target = string(text);
	var start = string(prefix);

	/* A matching initial slice accepts the prefix, including an empty prefix */
	return string_copy(target, 1, string_length(start)) == start;
}

/// @description Check one character against the username letter, digit and underscore policy
/// @param {String} ch Single candidate character
/// @returns {Bool} Whether the character is accepted
function chat_username_char_allowed(ch)
{
	/* Keep Scandinavian and other Latin-1 letters while excluding multiplication and division signs */
	var allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖabcdefghijklmnopqrstuvwxyzåäö0123456789_";

	/* Explicit Latin letters, Scandinavian letters, digits and underscore are accepted before the wider Latin-1 check */
	if (string_pos(ch, allowed) > 0)
	{
		return true;
	}

	/* Read the character's code point for the remaining accented Latin-1 range */
	var code = ord(ch);

	/* Accept codes 192–255 except multiplication and division signs, preserving accented letters without those symbols */
	return code >= 192 && code <= 255 && code != 215 && code != 247;
}

/// @description Find a case-insensitive username collision without changing the roster
/// @param {String} candidate Requested name
/// @param {Array} usernames Names indexed by zero-based player slot
/// @param {Real} ignore_slot Slot to skip during renaming. Defaults to noone
/// @returns {Bool} Whether another slot has this name. False for a non-array roster
function chat_username_is_taken(candidate, usernames, ignore_slot = noone)
{
	/* Without an array of known names, there is no roster to search */
	if (!is_array(usernames))
	{
		return false;
	}

	/* Lowercase the candidate once so name collision checks ignore letter case */
	var lowered = string_lower(string(candidate));

	/* Visit every zero-based roster slot when checking a requested name */
	for (var i = 0; i < array_length(usernames); i++)
	{
		/* Skip the caller's existing slot during a rename so its current name does not collide with itself */
		if (i == ignore_slot)
		{
			continue;
		}

		/* The first case-insensitive name match reports a collision */
		if (string_lower(string(usernames[i])) == lowered)
		{
			return true;
		}
	}

	return false;
}

/// @description Filter a server username to 16 allowed characters and replace names shorter than three with Player
/// @param {String} raw_username Requested name
/// @returns {String} Filtered fallback name. Uniqueness is handled separately
function chat_sanitize_username(raw_username)
{
	/* raw is the trimmed requested name, and result starts empty for its accepted characters */
	var raw = string_trim(string(raw_username));
	var result = "";

	/* Scan one-based characters in their original order */
	for (var i = 1; i <= string_length(raw); i++)
	{
		/* Read this candidate character before applying the username allowlist */
		var ch = string_char_at(raw, i);

		/* Append only characters permitted by the shared username policy */
		if (chat_username_char_allowed(ch))
		{
			result += ch;
		}
	}

	/* Keep only the first sixteen accepted characters so server names meet the wire/UI length bound */
	if (string_length(result) > 16)
	{
		result = string_copy(result, 1, 16);
	}

	/* Names shorter than three accepted characters use Player so the server always assigns a readable fallback */
	if (string_length(result) < 3)
	{
		result = "Player";
	}

	return result;
}

/// @description Filter editable username input without adding the server fallback
/// @param {String} raw_username Current field contents
/// @returns {String} Up to 16 allowed characters, possibly empty
function chat_filter_username_input(raw_username)
{
	/* raw is the editable name text, and result starts empty for its accepted characters */
	var raw = string(raw_username);
	var result = "";

	/* Scan one-based characters in their original order */
	for (var i = 1; i <= string_length(raw); i++)
	{
		/* Read this candidate character before applying the username allowlist */
		var ch = string_char_at(raw, i);

		/* Append only characters permitted by the shared username policy */
		if (chat_username_char_allowed(ch))
		{
			result += ch;
		}

		/* Stop once sixteen accepted characters are retained, without adding the server's fallback during editing */
		if (string_length(result) >= 16)
		{
			break;
		}
	}

	return result;
}

/// @description Search for a case-insensitive unused server name, trying numeric suffixes before a random fallback
/// @param {String} raw_username Requested name
/// @param {Array} usernames Names indexed by server slot
/// @param {Real} ignore_slot Existing slot to exclude during a rename, defaulting to noone for no exclusion
/// @returns {String} Name of at most 16 characters. The random fallback is not checked again for uniqueness
function chat_make_unique_username(raw_username, usernames, ignore_slot = noone)
{
	/* base is the sanitized requested name, and candidate begins with it before suffix trials */
	var base = chat_sanitize_username(raw_username);
	var candidate = base;

	/* An unused base is accepted immediately without a numeric suffix */
	if (!chat_username_is_taken(candidate, usernames, ignore_slot))
	{
		return candidate;
	}

	/* Try numeric suffixes from two through 9999 in ascending order */
	for (var suffix = 2; suffix < 10000; suffix++)
	{
		/* suffix_text contains the current number, and base_length reserves enough of the sixteen-character limit to append it */
		var suffix_text = string(suffix);
		var base_length = max(1, 16 - string_length(suffix_text));
		candidate = string_copy(base, 1, base_length) + suffix_text;

		/* The first unused suffixed candidate ends the search
		After all trials, the random fallback below is not checked again for collisions */
		if (!chat_username_is_taken(candidate, usernames, ignore_slot))
		{
			return candidate;
		}
	}

	return string_copy(base, 1, 12) + string(irandom_range(1000, 9999));
}

/// @description Remove CR/LF, trim outer whitespace and truncate message text
/// @param {String} raw_text Input text
/// @param {Real} max_length Maximum retained characters. Defaults to 240
/// @returns {String} Cleaned message, possibly empty
function chat_sanitize_message(raw_text, max_length = 240)
{
	/* Convert message input and remove CR/LF before trimming surrounding whitespace */
	var text = string(raw_text);
	text = string_replace_all(text, "\r", "");
	text = string_replace_all(text, "\n", "");
	text = string_trim(text);

	/* Truncate only when the normalized message exceeds the caller's character limit */
	if (string_length(text) > max_length)
	{
		text = string_copy(text, 1, max_length);
	}

	return text;
}

/// @description Format the local wall-clock transcript timestamp with a current_time millisecond remainder
/// @returns {String} YYYY-MM-DD HH:MM:SS.mmm text
function chat_export_timestamp()
{
	/* Capture local wall-clock date/time once, then append the current_time millisecond remainder for the retained transcript */
	var now = date_current_datetime();
	return scr_debug_export_pad_number(date_get_year(now), 4)
		+ "-" + scr_debug_export_pad_number(date_get_month(now), 2)
		+ "-" + scr_debug_export_pad_number(date_get_day(now), 2)
		+ " "
		+ scr_debug_export_pad_number(date_get_hour(now), 2)
		+ ":" + scr_debug_export_pad_number(date_get_minute(now), 2)
		+ ":" + scr_debug_export_pad_number(date_get_second(now), 2)
		+ "." + scr_debug_export_pad_number(current_time mod 1000, 3);
}

/// @description Format the current local wall-clock time for the visible chat log
/// @returns {String} HH:MM text
function chat_display_timestamp()
{
	/* Capture local time once for the visible HH:MM timestamp */
	var now = date_current_datetime();
	return scr_debug_export_pad_number(date_get_hour(now), 2)
		+ ":" + scr_debug_export_pad_number(date_get_minute(now), 2);
}

/// @description Format the sender prefix for player and SAY messages, leaving other kinds as plain content
/// @param {Real} chat_type CHAT_TYPE_* message kind
/// @param {String} sender_name Display name
/// @param {String} content Message text
/// @returns {String} Formatted chat line
function chat_format_message_line(chat_type, sender_name, content)
{
	/* Ordinary player messages use angle-bracketed names, /say uses square brackets,
	and error/system/unknown kinds show content without a sender prefix */
	switch (chat_type)
	{
		case CHAT_TYPE_PLAYER:
			return "<" + string(sender_name) + "> " + string(content);

		case CHAT_TYPE_SAY:
			return "[" + string(sender_name) + "] " + string(content);

		case CHAT_TYPE_ERROR:
			return string(content);

		case CHAT_TYPE_SYSTEM:
		default:
			return string(content);
	}
}
#endregion /* Username and Message Helpers END */

/// @description Own chat input, retained messages, player presence and world/GUI chat rendering
function scr_chat() constructor
{
	/* messages starts as the visible history array, and export_messages keeps an independent retained transcript
	max_messages caps visible entries at 120, while the negative max_export_messages default retains all transcript lines until clear_messages */
	messages = [];
	export_messages = [];
	max_messages = 120;
	max_export_messages = -1;

	/* max_chat_length limits accepted message content to 240 characters, and max_input_length caps the editable field at 160
	closed_visible_ms keeps recent chat visible for 9000 current_time milliseconds after activity */
	max_chat_length = 240;
	max_input_length = 160;
	closed_visible_ms = 9000;

	/* Chat starts unfocused with empty input and no assigned name
	latest_activity_time zero is the last activity clock, and released_movement_on_open prevents repeating the opening movement release */
	is_open = false;
	input_text = "";
	assigned_username = "";
	latest_activity_time = 0;
	released_movement_on_open = false;

	/* Clipboard feedback starts empty with white text and no active deadline
	clipboard_notice_until uses current_time milliseconds, with clipboard_notice_ms setting the default 6500-ms duration */
	clipboard_notice_text = "";
	clipboard_notice_color = c_white;
	clipboard_notice_until = 0;
	clipboard_notice_ms = 6500;

	/* Window x/y and width/height are GUI pixels, starting at x 16, y 0, width 640 and zero height until layout runs
	window_user_moved starts false so automatic lower-screen positioning remains active */
	window_x = 16;
	window_y = 0;
	window_width = 640;
	window_height = 0;
	window_user_moved = false;

	/* dragging starts false, drag_offset_x/y retain pointer-to-window GUI offsets,
	and scroll_lines zero selects the newest wrapped log lines */
	dragging = false;
	drag_offset_x = 0;
	drag_offset_y = 0;
	scroll_lines = 0;

	/* content_padding is the ten-pixel window inset
	text_height/timestamp_text_height are 18/13 GUI-pixel targets, timestamp_column_width reserves 50 pixels,
	and line_gap adds four pixels to line_height for wrapped message rows */
	content_padding = 10;
	text_height = 18;
	timestamp_text_height = 13;
	timestamp_column_width = 50;
	line_gap = 4;
	line_height = text_height + line_gap;

	/* log_x/y/width/height and input_x/y/width/height start at zero until layout computes their GUI rectangles */
	log_x = 0;
	log_y = 0;
	log_width = 0;
	log_height = 0;
	input_x = 0;
	input_y = 0;
	input_width = 0;
	input_height = 0;

	/* visible_log_lines starts with no rows, message_revision counts history mutations, and log_lines_cache starts empty
	Its width/height/revision/social-change keys start at -1 so the first layout rebuilds filtered wrapping */
	visible_log_lines = 0;
	message_revision = 0;
	log_lines_cache = [];
	log_lines_cache_width = -1;
	log_lines_cache_height = -1;
	log_lines_cache_message_revision = -1;
	log_lines_cache_social_change_time = -1;

	/* Input wrap caching starts with empty text/lines and invalid -1 width/height keys
	It rebuilds when editable text or its GUI dimensions change */
	input_wrap_cache_text = "";
	input_wrap_cache_width = -1;
	input_wrap_cache_height = -1;
	input_wrap_cache_lines = [];

	/* Speech bubbles last 6500 current_time milliseconds and fade during their final 900 ms
	bubble_text_height and bubble_line_gap use 18/3 room-coordinate pixels, with text width capped at 260 */
	bubble_visible_ms = 6500;
	bubble_fade_ms = 900;
	bubble_text_height = 18;
	bubble_line_gap = 3;
	bubble_max_text_width = 260;

	/* bubble_min_width requests at least 76 room pixels when space permits, and bubble_max_lines caps content at four lines
	Horizontal/vertical padding is 13/8 pixels, corner radius is 10, tail width/height is 20/14,
	and bubble_view_margin keeps an eight-pixel clearance inside room/camera bounds */
	bubble_min_width = 76;
	bubble_max_lines = 4;
	bubble_padding_x = 13;
	bubble_padding_y = 8;
	bubble_corner_radius = 10;
	bubble_tail_width = 20;
	bubble_tail_height = 14;
	bubble_view_margin = 8;

	/* Remote typing expires after 10000 current_time milliseconds without refresh, while local active typing refreshes every 4000 ms */
	typing_timeout_ms = 10000;
	typing_refresh_ms = 4000;

	/* These empty parallel arrays store active flags, display names and current_time
	millisecond expiration deadlines by zero-based server slot */
	typing_active = [];
	typing_names = [];
	typing_deadlines = [];

	/* typing_local_active tracks the local indicator, typing_last_sent_state tracks the last accepted network state,
	typing_next_refresh_time uses current_time milliseconds, with zero permitting an immediate refresh, and typing_last_input_text detects editable-text changes */
	typing_local_active = false;
	typing_last_sent_state = false;
	typing_next_refresh_time = 0;
	typing_last_input_text = "";

	/* Typing footer height/x/y start at zero until chat layout positions the GUI summary
	typing_view_margin reserves eight room pixels around world indicators */
	typing_footer_height = 0;
	typing_footer_x = 0;
	typing_footer_y = 0;
	typing_view_margin = 8;

	/* AFK activity reports are paced at 30000 current_time milliseconds, with afk_next_activity_time zero allowing the first report */
	afk_activity_refresh_ms = 30000;
	afk_next_activity_time = 0;

	/* Parallel empty arrays store AFK active flags, names and current_time millisecond activation times by server slot
	afk_view_margin reserves eight room pixels around AFK labels */
	afk_active = [];
	afk_names = [];
	afk_started = [];
	afk_view_margin = 8;

	#region /* Input Cleaning and Clipboard Notices */
	/// @description Apply the shared server username policy, including the Player fallback
	/// @param {String} raw_username Requested name
	/// @returns {String} Sanitized name of at most 16 characters
	sanitize_username = function(raw_username)
	{
		return chat_sanitize_username(raw_username);
	}

	/// @description Filter editable username text without inserting the server fallback
	/// @param {String} raw_username Field contents
	/// @returns {String} At most 16 allowed characters, possibly empty
	filter_username_input = function(raw_username)
	{
		return chat_filter_username_input(raw_username);
	}

	/// @description Check the shared case-insensitive username collision policy
	/// @param {String} candidate Requested name
	/// @param {Array} usernames Names indexed by zero-based player slot
	/// @param {Real} ignore_slot Existing slot to exclude. Defaults to noone
	/// @returns {Bool} Whether another roster slot has this name
	is_username_taken = function(candidate, usernames, ignore_slot = noone)
	{
		return chat_username_is_taken(candidate, usernames, ignore_slot);
	}

	/// @description Select a server name using the shared suffix search and unchecked random fallback
	/// @param {String} raw_username Requested name
	/// @param {Array} usernames Names indexed by zero-based player slot
	/// @param {Real} ignore_slot Existing slot to exclude. Defaults to noone
	/// @returns {String} Sanitized candidate of at most 16 characters
	make_unique_username = function(raw_username, usernames, ignore_slot = noone)
	{
		return chat_make_unique_username(raw_username, usernames, ignore_slot);
	}

	/// @description Sanitize submitted text using this chat state maximum message length
	/// @param {String} raw_text Submitted input
	/// @returns {String} Single-line trimmed message, possibly empty
	sanitize_chat_input = function(raw_text)
	{
		return chat_sanitize_message(raw_text, max_chat_length);
	}

	/// @description Remove CR, replace LF with spaces and enforce the editable input limit
	/// @param {String} raw_text Keyboard field contents
	/// @returns {String} Cleaned text of at most max_input_length characters
	clean_input_text = function(raw_text)
	{
		/* Convert editable input, remove CR and replace LF with spaces so the chat field remains a single logical message */
		var text = string(raw_text);
		text = string_replace_all(text, "\r", "");
		text = string_replace_all(text, "\n", " ");

		/* Keep editable input within max_input_length after newline normalization */
		if (string_length(text) > max_input_length)
		{
			text = string_copy(text, 1, max_input_length);
		}

		return text;
	}

	/// @description Identify browser and GX runtimes for clipboard feedback
	/// @returns {Bool} Whether browser clipboard behavior applies
	clipboard_is_browser_runtime = function()
	{
		/* Browser or GX builds use browser-specific clipboard feedback */
		return os_browser != browser_not_a_browser || os_type == os_gxgames;
	}

	/// @description Choose the authored platform-specific clipboard failure or permission message
	/// @param {String} action_text Action label such as Copy
	/// @returns {String} Clipboard feedback text
	clipboard_browser_context_text = function(action_text)
	{
		/* Convert the requested clipboard action name for the platform-specific explanation */
		var action = string(action_text);

		/* Firefox receives its authored clipboard-permission advice */
		if (os_browser == browser_firefox)
		{
			return action + " may be blocked in Firefox HTML5 builds. Try Chrome or Edge, or allow clipboard permission.";
		}

		/* Internet Explorer receives the unavailable-action message */
		if (os_browser == browser_ie)
		{
			return action + " is not available in this browser.";
		}

		/* Other browser runtimes receive generic permission advice, while native failures use the final short error */
		if (clipboard_is_browser_runtime())
		{
			return action + " may need browser clipboard permission. Allow it if prompted, then try again.";
		}

		return action + " failed.";
	}

	/// @description Set timed clipboard feedback and refresh the chat activity clock
	/// @param {String} message Feedback text
	/// @param {Real} notice_color Drawing color. Defaults to c_white
	/// @param {Real} duration_ms Local millisecond lifetime. Defaults to clipboard_notice_ms
	set_clipboard_notice = function(message, notice_color = c_white, duration_ms = clipboard_notice_ms)
	{
		clipboard_notice_text = string(message);
		clipboard_notice_color = notice_color;

		/* Schedule feedback in current_time milliseconds and record activity so the chat overlay remains visible */
		clipboard_notice_until = current_time + duration_ms;
		latest_activity_time = current_time;
	}

	/// @description Clear feedback text and its active deadline
	clear_clipboard_notice = function()
	{
		clipboard_notice_text = "";
		clipboard_notice_until = 0;
	}

	/// @description Check feedback text and its inclusive current_time millisecond deadline
	/// @returns {Bool} Whether clipboard feedback remains active
	clipboard_notice_active = function()
	{
		/* Feedback requires nonempty text and remains active through its inclusive current_time deadline */
		return clipboard_notice_text != "" && current_time <= clipboard_notice_until;
	}
	#endregion /* Input Cleaning and Clipboard Notices END */

	#region /* Message History and Local Filtering */
	/// @description Clear visible history, invalidate wrapping and reset scrolling while preserving the export transcript
	clear_visible_messages = function()
	{
		messages = [];
		message_revision++;
		scroll_lines = 0;
		latest_activity_time = 0;
	}

	/// @description Clear both visible history and the retained export transcript
	clear_messages = function()
	{
		clear_visible_messages();
		export_messages = [];
	}

	/// @description Append a sanitized timestamped transcript line and server chat log entry, trimming only a positive retention limit
	/// @param {Real} chat_type CHAT_TYPE_* kind
	/// @param {Real} sender_id Sender slot or system sentinel for logging
	/// @param {String} sender_name Display name
	/// @param {String} content Message to flatten and truncate
	record_export_message = function(chat_type, sender_id, sender_name, content)
	{
		/* Flatten CR/LF into transcript-safe text before applying the message-length cap */
		var clean_content = string_replace_all(string(content), "\r", "");
		clean_content = string_replace_all(clean_content, "\n", " ");

		/* Cap the retained message before formatting either the local transcript or server log */
		if (string_length(clean_content) > max_chat_length)
		{
			clean_content = string_copy(clean_content, 1, max_chat_length);
		}

		/* recorded_at captures local transcript time, and export_line formats this message with its kind and sender name */
		var recorded_at = chat_export_timestamp();
		var export_line = "[" + recorded_at + "] " + chat_format_message_line(chat_type, sender_name, clean_content);
		export_messages[array_length(export_messages)] = export_line;
		scr_server_logs_append("chat", "[" + recorded_at + "] [type=" + string(chat_type)
			+ " sender=" + string(sender_id) + "] " + chat_format_message_line(chat_type, sender_name, clean_content));

		/* Only positive transcript limits trim oldest entries, leaving the negative default unlimited until clear_messages */
		while (max_export_messages > 0 && array_length(export_messages) > max_export_messages)
		{
			array_delete(export_messages, 0, 1);
		}
	}

	/// @description Copy retained transcript lines into an independent array for export
	/// @returns {Array<String>} Transcript lines in recorded order
	copy_export_lines = function()
	{
		/* line_count bounds the retained transcript and lines is a fresh array for a stable export copy */
		var line_count = array_length(export_messages);
		var lines = array_create(line_count);

		/* Copy every zero-based transcript entry in recorded order */
		for (var line_index = 0; line_index < line_count; line_index++)
		{
			lines[line_index] = export_messages[line_index];
		}

		return lines;
	}

	/// @description Add a received or local message to the visible history and optionally its export transcript
	/// @param {Real} chat_type CHAT_TYPE_* value
	/// @param {Real} sender_id Zero-based player slot, or noone for system messages
	/// @param {String} sender_name Display name
	/// @param {String} content Message text, flattened and limited to max_chat_length
	/// @param {String} sent_at Display timestamp, defaulting to empty for local HH:MM generation
	/// @param {Bool} record_for_export Also record the message in the retained transcript, defaulting to true
	add_message = function(chat_type, sender_id, sender_name, content, sent_at = "", record_for_export = true)
	{
		/* Flatten incoming message text before retention and display */
		var clean_content = string_replace_all(string(content), "\r", "");
		clean_content = string_replace_all(clean_content, "\n", " ");

		/* Cap the normalized content to max_chat_length */
		if (string_length(clean_content) > max_chat_length)
		{
			clean_content = string_copy(clean_content, 1, max_chat_length);
		}

		/* bubble_sender_index normalizes a possible player slot, while display_timestamp trims the caller's optional visible time */
		var bubble_sender_index = bubble_sender_slot_from_value(sender_id);
		var display_timestamp = string_trim(string(sent_at));

		/* Empty supplied time uses the local HH:MM when this message is received or added */
		if (display_timestamp == "")
		{
			display_timestamp = chat_display_timestamp();
		}

		/* Retain a transcript entry only when requested, allowing callers to add display-only messages */
		if (record_for_export)
		{
			record_export_message(chat_type, sender_id, sender_name, clean_content);
		}

		/* Store kind, normalized slot when valid or original sender value otherwise, name, content and display timestamp
		time records local current_time milliseconds for overlay and bubble lifetime calculations */
		messages[array_length(messages)] =
		{
			kind: chat_type,
			sender_id: bubble_sender_index != noone ? bubble_sender_index : sender_id,
			sender_name: string(sender_name),
			content: clean_content,
			sent_at: display_timestamp,
			time: current_time
		};

		/* Trim oldest visible entries above max_messages while leaving the separate export transcript intact */
		while (array_length(messages) > max_messages)
		{
			array_delete(messages, 0, 1);
		}
		message_revision++;

		/* A view already at the newest lines stays at offset zero after adding a message */
		if (scroll_lines <= 0)
		{
			scroll_lines = 0;
		}

		latest_activity_time = current_time;
	}

	/// @description Add an error message to visible history and the export transcript
	/// @param {String} content Error text
	add_local_error = function(content)
	{
		add_message(CHAT_TYPE_ERROR, noone, "", content);
	}

	/// @description Format a retained message using its kind and sender label
	/// @param {Struct} entry Retained message record
	/// @returns {String} Visible message text
	format_message = function(entry)
	{
		return chat_format_message_line(entry.kind, entry.sender_name, entry.content);
	}

	/// @description Choose the display color for the retained message kind
	/// @param {Struct} entry Message record with kind
	/// @returns {Real} System, error or SAY color, otherwise c_white
	message_color = function(entry)
	{
		/* System uses yellow, errors red, /say pale yellow, and ordinary or unknown kinds white */
		switch (entry.kind)
		{
			case CHAT_TYPE_SYSTEM: return make_color_rgb(255, 255, 85);
			case CHAT_TYPE_ERROR: return make_color_rgb(255, 85, 85);
			case CHAT_TYPE_SAY: return make_color_rgb(255, 220, 95);
			case CHAT_TYPE_PLAYER:
			default:
				return c_white;
		}
	}

	/// @description Apply slot and username blocking to player and SAY messages only
	/// @param {Struct} entry Message record to inspect
	/// @returns {Bool} Whether social filtering hides it. Incomplete and other-kind records return false
	message_is_blocked = function(entry)
	{
		/* Check the entry type before its kind field, treating incomplete records as unblocked here */
		if (!is_struct(entry)
		|| !variable_struct_exists(entry, "kind"))
		{
			return false;
		}

		/* Only player and /say kinds use social sender filtering, leaving system and error messages visible */
		if (entry.kind != CHAT_TYPE_PLAYER
		&& entry.kind != CHAT_TYPE_SAY)
		{
			return false;
		}

		/* Borrow the shared local social filter before checking optional sender identity fields */
		var social = scr_get_social();

		/* A present blocked sender slot hides the player message */
		if (variable_struct_exists(entry, "sender_id")
		&& social.is_blocked_slot(entry.sender_id))
		{
			return true;
		}

		/* A present blocked name also hides the message, supporting name-based filtering independently of slot lookup */
		if (variable_struct_exists(entry, "sender_name")
		&& social.is_blocked_username(entry.sender_name))
		{
			return true;
		}

		return false;
	}
	#endregion /* Message History and Local Filtering END */

	#region /* World Speech Bubbles */
	/// @description Convert a sender value to a nonnegative integer player slot
	/// @param {Any} raw_sender_id Sender value to normalize
	/// @returns {Real} Zero-based slot or noone for a missing, unconvertible, fractional or negative value
	bubble_sender_slot_from_value = function(raw_sender_id)
	{
		/* Absent or noone sender values have no player slot */
		if (is_undefined(raw_sender_id)
		|| raw_sender_id == noone)
		{
			return noone;
		}

		/* Start with no slot before attempting conversion from the supplied sender value */
		var numeric_sender_id = noone;
		try
		{
			numeric_sender_id = real(raw_sender_id);
		}

		/* Unconvertible sender values return noone instead of interrupting chat drawing */
		catch (e)
		{
			return noone;
		}

		/* Floor the converted value for comparison with a zero-based integer slot */
		var sender_index = floor(numeric_sender_id);

		/* Reject fractions and negative slots so bubble callers cannot use them as player-array indices */
		if (numeric_sender_id != sender_index
		|| sender_index < 0)
		{
			return noone;
		}

		return sender_index;
	}

	/// @description Check required message fields, eligible kind, sender block and nonempty bubble content
	/// @param {Struct} entry Retained message record
	/// @returns {Bool} Whether the message is eligible for world bubble selection
	bubble_message_should_draw = function(entry)
	{
		/* Require a struct with kind, sender_id, content and time before evaluating bubble eligibility */
		if (!is_struct(entry)
		|| !variable_struct_exists(entry, "kind")
		|| !variable_struct_exists(entry, "sender_id")
		|| !variable_struct_exists(entry, "content")
		|| !variable_struct_exists(entry, "time"))
		{
			return false;
		}

		/* Only ordinary player and /say messages receive world speech bubbles */
		if (entry.kind != CHAT_TYPE_PLAYER
		&& entry.kind != CHAT_TYPE_SAY)
		{
			return false;
		}

		/* Normalize this message's sender into a zero-based player slot */
		var sender_index = bubble_sender_slot_from_value(entry.sender_id);

		/* Require a valid slot, no slot-based block and nonempty content before layout */
		return sender_index != noone
			&& !scr_get_social().is_blocked_slot(sender_index)
			&& string(entry.content) != "";
	}

	/// @description Check whether this drawing pass already selected a message for the sender
	/// @param {Real} sender_id Zero-based player slot
	/// @param {Array<Real>} seen_senders Slots already selected
	/// @returns {Bool} Whether this sender appears in the array
	bubble_sender_seen = function(sender_id, seen_senders)
	{
		/* Search zero-based sender entries already selected for this bubble pass */
		for (var i = 0; i < array_length(seen_senders); i++)
		{
			/* An existing sender match prevents drawing an older second bubble for the same player */
			if (seen_senders[i] == sender_id)
			{
				return true;
			}
		}

		return false;
	}

	/// @description Wrap bubble text and retain at most bubble_max_lines with an ellipsis on truncation
	/// @param {String} content Bubble message
	/// @param {Real} max_width Maximum room-pixel text width
	/// @returns {Array<String>} Wrapped and optionally truncated rows
	bubble_entry_lines = function(content, max_width)
	{
		/* Wrap content at the requested room-pixel width, then split its LF-separated lines */
		var wrapped = scr_text_wrap(content, bubble_text_height, max_width);
		var lines = string_split(wrapped, "\n");

		/* Content already within the line cap needs no truncation or ellipsis */
		if (array_length(lines) <= bubble_max_lines)
		{
			return lines;
		}

		/* Start a new array for the first bubble_max_lines rows only */
		var limited = [];

		/* Copy zero-based lines through the bubble line cap */
		for (var i = 0; i < bubble_max_lines; i++)
		{
			limited[i] = lines[i];
		}

		/* last_index identifies the final retained line and last_line holds its text for truncation feedback */
		var last_index = bubble_max_lines - 1;
		var last_line = string(limited[last_index]);

		/* Long enough final lines replace their last three characters with an ellipsis */
		if (string_length(last_line) > 3)
		{
			last_line = string_copy(last_line, 1, max(1, string_length(last_line) - 3)) + "...";
		}

		/* Short final lines append an ellipsis without removing all their content */
		else
		{
			last_line += "...";
		}
		limited[last_index] = last_line;
		return limited;
	}

	/// @description Measure and place a view-clamped speech bubble, setting fnt_ui for font metrics
	/// @param {Struct} entry Message with content and local millisecond time
	/// @param {Struct} player Player with position and optional visual position and character metadata
	/// @param {Id.Camera} camera_id Active room camera
	/// @returns {Struct|Real} Room-pixel box, text, tail and opacity layout, or noone when it cannot be drawn
	bubble_make_layout = function(entry, player, camera_id)
	{
		/* A missing player or invalid camera cannot provide a room position for this bubble */
		if (player == noone
		|| !is_real(camera_id)
		|| camera_id < 0)
		{
			return noone;
		}

		/* Read the camera rectangle in room pixels so bubble placement follows the visible world */
		var view_x = camera_get_view_x(camera_id);
		var view_y = camera_get_view_y(camera_id);
		var view_w = camera_get_view_width(camera_id);
		var view_h = camera_get_view_height(camera_id);

		/* A camera with no drawable area cannot contain a bubble */
		if (view_w <= 0 || view_h <= 0)
		{
			return noone;
		}

		/* Start with the authoritative player position in room pixels */
		var player_x = player.pos.x;
		var player_y = player.pos.y;

		/* Follow the interpolated position when available so the bubble stays with the visible character */
		if (variable_struct_exists(player, "visual_pos"))
		{
			player_x = player.visual_pos.x;
			player_y = player.visual_pos.y;
		}

		/* Players outside the camera do not need a visible speech bubble */
		if (player_x < view_x
		|| player_x > view_x + view_w
		|| player_y < view_y
		|| player_y > view_y + view_h)
		{
			return noone;
		}

		/* Intersect the camera and room bounds, then leave the configured margin on each edge */
		var bounds_left = max(0, view_x) + bubble_view_margin;
		var bounds_top = max(0, view_y) + bubble_view_margin;
		var bounds_right = min(room_width, view_x + view_w) - bubble_view_margin;
		var bounds_bottom = min(room_height, view_y + view_h) - bubble_view_margin;

		/* Margins that consume the entire visible rectangle leave no space for a bubble */
		if (bounds_right <= bounds_left
		|| bounds_bottom <= bounds_top)
		{
			return noone;
		}

		draw_set_font(fnt_ui);

		/* Scale the UI font to the requested room-pixel text height and wrap within the available padded width
		lines holds the wrapped rows and line_count controls measurement and drawing */
		var scale = scr_render_text_scale(bubble_text_height);
		var max_text_width = min(bubble_max_text_width, max(40, bounds_right - bounds_left - bubble_padding_x * 2));
		var lines = bubble_entry_lines(string(entry.content), max_text_width);
		var line_count = array_length(lines);

		/* An empty set of wrapped rows has no bubble content to measure */
		if (line_count <= 0)
		{
			return noone;
		}

		/* Accumulate the widest scaled row, starting at zero before any line is measured */
		var text_width = 0;

		/* Measure each zero-based wrapped row to size the bubble around its text */
		for (var i = 0; i < line_count; i++)
		{
			text_width = max(text_width, string_width(lines[i]) * scale);
		}

		/* Limit the box to the visible width while respecting the preferred minimum when it fits
		text_height_total includes gaps between rows only, and box_height adds vertical padding */
		var max_box_width = max(32, bounds_right - bounds_left);
		var min_box_width = min(bubble_min_width, max_box_width);
		var box_width = clamp(ceil(text_width + bubble_padding_x * 2), min_box_width, max_box_width);
		var text_height_total = line_count * (bubble_text_height + bubble_line_gap) - bubble_line_gap;
		var box_height = ceil(text_height_total + bubble_padding_y * 2);

		/* A bubble taller than the available view cannot be placed without clipping */
		if (box_height > bounds_bottom - bounds_top)
		{
			return noone;
		}

		/* Use the player scale when present, otherwise the standard 2.5 scale
		The character key selects sprite bounds and defaults to player1 when older player records omit it */
		var player_size_value = variable_struct_exists(player, "player_size") ? player.player_size : 2.5;
		var bubble_character_key = variable_struct_exists(player, "character_key") ? player.character_key : "player1";

		/* Resolve the actual character top and horizontal center so different character sprites share the same attachment rules
		nameplate_gap and nameplate_height reserve 10 and 22 room pixels above the sprite */
		var sprite_top = player_character_top_y_key(bubble_character_key, player_y, player_size_value);
		var sprite_center_x = player_character_center_x_key(bubble_character_key, player_x, player_size_value);
		var nameplate_gap = 10;
		var nameplate_height = 22;

		/* Clamp the tail tip inside the view and place it above the nameplate
		box_x centers the bubble over the sprite, while the two preferred Y positions leave room for its tail */
		var anchor_x = clamp(sprite_center_x, bounds_left + 2, bounds_right - 2);
		var anchor_y = clamp(sprite_top - nameplate_gap - nameplate_height - 2, bounds_top + 2, bounds_bottom - 2);
		var box_x = clamp(sprite_center_x - box_width * 0.5, bounds_left, bounds_right - box_width);
		var preferred_above_y = anchor_y - bubble_tail_height - 4 - box_height;
		var preferred_below_y = anchor_y + bubble_tail_height + 4;

		/* Try the above-character position first before considering a lower placement */
		var box_y = preferred_above_y;

		/* When the bubble would cross the top edge, look for space below its anchor */
		if (preferred_above_y < bounds_top)
		{
			/* Use the lower position only when the entire bubble fits before the bottom edge */
			if (preferred_below_y + box_height <= bounds_bottom)
			{
				box_y = preferred_below_y;
			}

			/* If neither preferred position fits, clamp the above position into the remaining vertical space */
			else
			{
				box_y = clamp(preferred_above_y, bounds_top, bounds_bottom - box_height);
			}
		}

		/* age is elapsed local milliseconds since receipt, and alpha starts fully visible before the fade interval */
		var age = current_time - entry.time;
		var alpha = 1;

		/* Fade during the final bubble_fade_ms milliseconds, clamping expired bubbles to transparent */
		if (age > bubble_visible_ms - bubble_fade_ms)
		{
			alpha = clamp((bubble_visible_ms - age) / bubble_fade_ms, 0, 1);
		}

		/* Limit the tail width relative to the box and point it toward the character anchor
		tail_on_top chooses the nearest horizontal edge, while tail_base_x keeps the base away from rounded corners */
		var tail_half = min(bubble_tail_width * 0.5, box_width * 0.25);
		var tail_on_top = box_y > anchor_y;
		var tail_base_y = tail_on_top ? box_y : box_y + box_height;
		var tail_base_x = clamp(anchor_x, box_x + tail_half + 5, box_x + box_width - tail_half - 5);

		/* Return room-pixel box bounds, padded text origin and width, wrapped rows and font scale
		Tail fields define the triangle attachment, and alpha carries the age-based visibility to both drawing passes */
		return
		{
			x1: box_x,
			y1: box_y,
			x2: box_x + box_width,
			y2: box_y + box_height,
			text_x: box_x + bubble_padding_x,
			text_y: box_y + bubble_padding_y,
			text_w: box_width - bubble_padding_x * 2,
			lines: lines,
			line_count: line_count,
			text_scale: scale,
			tail_tip_x: anchor_x,
			tail_tip_y: anchor_y,
			tail_base_x: tail_base_x,
			tail_base_y: tail_base_y,
			tail_half: tail_half,
			tail_on_top: tail_on_top,
			alpha: alpha
		};
	}

	/// @description Draw the layout text, then reset horizontal alignment to left and alpha to one
	/// @param {Struct} layout Bubble layout from bubble_make_layout
	draw_bubble_text = function(layout)
	{
		draw_set_font(fnt_ui);
		draw_set_halign(fa_center);
		draw_set_colour(c_black);
		draw_set_alpha(layout.alpha);

		/* Center every row within the box and advance yy from the padded text origin */
		var center_x = (layout.x1 + layout.x2) * 0.5;
		var yy = layout.text_y;

		/* Draw the zero-based wrapped rows at a consistent height and interline gap */
		for (var i = 0; i < layout.line_count; i++)
		{
			scr_render_text_draw_scaled(center_x, yy, layout.lines[i], layout.text_scale);
			yy += bubble_text_height + bubble_line_gap;
		}

		draw_set_halign(fa_left);
		draw_set_alpha(1);
	}

	/// @description Draw the bubble shadow, rounded box and tail, leaving border color active and alpha at one
	/// @param {Struct} layout Bubble layout from bubble_make_layout
	draw_bubble_shape = function(layout)
	{
		/* Clamp corner rounding to the bubble height, offset the shadow by three room pixels and use a muted border color */
		var radius = min(bubble_corner_radius, (layout.y2 - layout.y1) * 0.45);
		var shadow_offset = 3;
		var border_color = make_color_rgb(82, 86, 92);

		draw_set_alpha(layout.alpha * 0.22);
		draw_set_colour(c_black);
		draw_roundrect_ext(layout.x1 + shadow_offset, layout.y1 + shadow_offset, layout.x2 + shadow_offset, layout.y2 + shadow_offset, radius, radius, false);
		draw_triangle(
			layout.tail_base_x - layout.tail_half + shadow_offset,
			layout.tail_base_y + shadow_offset,
			layout.tail_base_x + layout.tail_half + shadow_offset,
			layout.tail_base_y + shadow_offset,
			layout.tail_tip_x + shadow_offset,
			layout.tail_tip_y + shadow_offset,
			false
		);

		draw_set_alpha(layout.alpha * 0.96);
		draw_set_colour(c_white);
		draw_roundrect_ext(layout.x1, layout.y1, layout.x2, layout.y2, radius, radius, false);

		draw_set_alpha(layout.alpha);
		draw_set_colour(border_color);
		draw_roundrect_ext(layout.x1, layout.y1, layout.x2, layout.y2, radius, radius, true);

		draw_set_colour(c_white);
		draw_triangle(
			layout.tail_base_x - layout.tail_half,
			layout.tail_base_y,
			layout.tail_base_x + layout.tail_half,
			layout.tail_base_y,
			layout.tail_tip_x,
			layout.tail_tip_y,
			false
		);

		draw_set_colour(border_color);
		draw_line_width(layout.tail_base_x - layout.tail_half, layout.tail_base_y, layout.tail_tip_x, layout.tail_tip_y, 2);
		draw_line_width(layout.tail_base_x + layout.tail_half, layout.tail_base_y, layout.tail_tip_x, layout.tail_tip_y, 2);
		draw_set_alpha(1);
	}

	/// @description Draw the newest visible message per player in room coordinates
	/// @param {Real} camera_id Active room camera used to clamp bubble positions
	draw_speech_bubbles = function(camera_id)
	{
		/* No retained messages or usable camera means there are no world bubbles to draw */
		if (array_length(messages) <= 0
		|| !is_real(camera_id)
		|| camera_id < 0)
		{
			return;
		}

		/* Fetch the shared player roster used to resolve each message sender */
		var controller = scr_get_player_controller();

		/* Require an initialized player array before indexing message senders */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			return;
		}

		/* Collect eligible messages and their zero-based sender slots separately
		entry_count starts at zero and records how many newest-per-player messages were retained */
		var recent_entries = [];
		var seen_senders = [];
		var entry_count = 0;

		/* Visit history newest first so the first eligible message for each sender wins */
		for (var message_index = array_length(messages) - 1; message_index >= 0; message_index--)
		{
			/* Inspect this retained message using its local receipt time */
			var entry = messages[message_index];

			/* Stop at the first expired message because history is ordered from older to newer receipt times */
			if (current_time - entry.time > bubble_visible_ms)
			{
				break;
			}

			/* Skip messages that lack drawable content or are hidden by social filtering */
			if (!bubble_message_should_draw(entry))
			{
				continue;
			}

			/* Convert the stored sender identifier into a zero-based player slot before roster access */
			var sender_id = bubble_sender_slot_from_value(entry.sender_id);

			/* Unusable sender identifiers cannot be attached to a player */
			if (sender_id == noone)
			{
				continue;
			}

			/* Hide messages belonging to players excluded by the current visibility settings */
			if (!scr_get_social().player_visible(sender_id))
			{
				continue;
			}

			/* Ignore slots outside the current roster to avoid indexing a departed or unknown player */
			if (sender_id >= array_length(controller.players))
			{
				continue;
			}

			/* Keep the newer selected message instead of adding an older bubble for the same sender */
			if (bubble_sender_seen(sender_id, seen_senders))
			{
				continue;
			}

			seen_senders[array_length(seen_senders)] = sender_id;
			recent_entries[entry_count++] = entry;
		}

		/* Draw selected messages from older to newer so the newest bubble is painted last */
		for (var i = entry_count - 1; i >= 0; i--)
		{
			/* Resolve the selected message and its sender slot for the rendering pass */
			var bubble_entry = recent_entries[i];
			var bubble_sender_index = bubble_sender_slot_from_value(bubble_entry.sender_id);

			/* Skip a sender that no longer resolves to a usable slot */
			if (bubble_sender_index == noone)
			{
				continue;
			}

			/* Read the player currently occupying this selected sender slot */
			var bubble_player = controller.players[bubble_sender_index];

			/* A vacant or socially hidden player has no bubble to render */
			if (bubble_player == noone
			|| !scr_get_social().player_visible(bubble_sender_index))
			{
				continue;
			}

			/* Compute a view-clamped bubble layout for this message and visible player */
			var layout = bubble_make_layout(bubble_entry, bubble_player, camera_id);

			/* Skip messages whose text or player position cannot produce a fitting layout */
			if (layout == noone)
			{
				continue;
			}

			draw_bubble_shape(layout);
			draw_bubble_text(layout);
		}

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	#endregion /* World Speech Bubbles END */

	#region /* Typing and AFK State */
	/// @description Normalize a presence identifier into a nonnegative integer slot
	/// @param {Any} raw_slot Slot value to convert
	/// @returns {Real} Zero-based slot or noone for invalid input
	typing_slot_from_value = function(raw_slot)
	{
		/* Missing values and the noone sentinel do not identify a player slot */
		if (is_undefined(raw_slot)
		|| raw_slot == noone)
		{
			return noone;
		}

		/* Keep conversion invalid until real accepts the supplied slot value */
		var numeric_slot = noone;
		try
		{
			numeric_slot = real(raw_slot);
		}

		/* A conversion exception means the supplied value is not a usable numeric slot */
		catch (e)
		{
			return noone;
		}

		/* floor supplies an integer candidate for a zero-based array index */
		var slot_index = floor(numeric_slot);

		/* Reject fractional or negative slots rather than silently redirecting them to another player */
		if (numeric_slot != slot_index
		|| slot_index < 0)
		{
			return noone;
		}

		return slot_index;
	}

	/// @description Grow aligned typing arrays through a valid requested slot
	/// @param {Any} raw_slot Slot to normalize
	/// @returns {Real} Zero-based slot or noone when invalid
	typing_ensure_slot = function(raw_slot)
	{
		/* Normalize the requested zero-based slot before growing its parallel state arrays */
		var slot = typing_slot_from_value(raw_slot);

		/* Invalid slots cannot allocate typing state */
		if (slot == noone)
		{
			return noone;
		}

		/* Extend all three arrays through the requested slot so their indices remain aligned */
		while (array_length(typing_active) <= slot)
		{
			/* Append an inactive slot with no display name and no millisecond expiry deadline */
			var insert_index = array_length(typing_active);
			typing_active[insert_index] = false;
			typing_names[insert_index] = "";
			typing_deadlines[insert_index] = 0;
		}

		return slot;
	}

	/// @description Check whether input contains any non-whitespace text
	/// @param {String} raw_text Input to inspect
	/// @returns {Bool} Whether the trimmed string is nonempty
	typing_input_has_content = function(raw_text)
	{
		/* Whitespace alone does not count as typing content */
		return string_trim(string(raw_text)) != "";
	}

	/// @description Resolve a presence label from preferred, roster, matching client, assigned chat or generic name
	/// @param {Any} raw_slot Player slot to normalize
	/// @param {String} preferred_name Explicit label. Defaults to an empty string
	/// @returns {String} Resolved display name
	typing_name_for_slot = function(raw_slot, preferred_name = "")
	{
		/* Resolve the slot and normalize the preferred label to a string */
		var slot = typing_slot_from_value(raw_slot);
		var display_name = string(preferred_name);

		/* An explicit nonempty label takes precedence over names found in player or client state */
		if (display_name != "")
		{
			return display_name;
		}

		/* Use a generic label when no valid player slot is available */
		if (slot == noone)
		{
			return "Player";
		}

		/* Look up the existing player without creating a missing player record */
		var player = player_controller_get_player(slot, false);

		/* Use a populated player username when the roster already knows this slot */
		if (player != noone
		&& variable_struct_exists(player, "username")
		&& string(player.username) != "")
		{
			return string(player.username);
		}

		/* Check whether this slot belongs to the local client, whose assigned name may arrive before roster data */
		var client = scr_get_client();

		/* Use the local assigned username only when the client ID matches this normalized slot */
		if (is_struct(client)
		&& variable_struct_exists(client, "ID")
		&& typing_slot_from_value(client.ID) == slot
		&& variable_struct_exists(client, "assigned_username")
		&& string(client.assigned_username) != "")
		{
			return string(client.assigned_username);
		}

		/* Fall back to the chat subsystem assigned name when no player or matching client name was found */
		if (assigned_username != "")
		{
			return assigned_username;
		}

		return "Player";
	}

	/// @description Grow aligned AFK arrays through a valid requested slot
	/// @param {Any} raw_slot Slot to normalize
	/// @returns {Real} Zero-based slot or noone when invalid
	afk_ensure_slot = function(raw_slot)
	{
		/* Normalize the requested zero-based slot before extending its away-state arrays */
		var slot = typing_slot_from_value(raw_slot);

		/* Invalid slots cannot allocate AFK state */
		if (slot == noone)
		{
			return noone;
		}

		/* Grow active flags, names and start times together through the requested slot */
		while (array_length(afk_active) <= slot)
		{
			/* Append an inactive AFK slot with an empty name and zero meaning no local start time */
			var insert_index = array_length(afk_active);
			afk_active[insert_index] = false;
			afk_names[insert_index] = "";
			afk_started[insert_index] = 0;
		}

		return slot;
	}

	/// @description Apply the AFK state received from the server
	/// @param {Real} raw_slot Zero-based server slot
	/// @param {String} username Preferred display name
	/// @param {Bool} is_afk Whether the player is away
	/// @returns {Bool} Whether the slot was accepted
	set_afk_state = function(raw_slot, username, is_afk)
	{
		/* Ensure aligned AFK storage exists for the received zero-based slot */
		var slot = afk_ensure_slot(raw_slot);

		/* Reject AFK updates whose slot cannot be normalized */
		if (slot == noone)
		{
			return false;
		}

		/* Record the display name and current local millisecond time when the player becomes away */
		if (is_afk)
		{
			afk_active[slot] = true;
			afk_names[slot] = typing_name_for_slot(slot, username);
			afk_started[slot] = current_time;
		}

		/* An active player clears the away flag, remembered name and start-time sentinel */
		else
		{
			afk_active[slot] = false;
			afk_names[slot] = "";
			afk_started[slot] = 0;
		}

		return true;
	}

	/// @description Discard all AFK flags, names and start times and reset the activity-send throttle
	clear_afk_states = function()
	{
		afk_active = [];
		afk_names = [];
		afk_started = [];
		afk_next_activity_time = 0;
	}

	/// @description Collect active, unblocked AFK slot and name records
	/// @returns {Array<Struct>} Display records with slot and name
	afk_build_entries = function()
	{
		/* Collect visible away-player records and count accepted entries from zero */
		var entries = [];
		var count = 0;

		/* Visit every zero-based slot with allocated AFK state */
		for (var slot = 0; slot < array_length(afk_active); slot++)
		{
			/* Exclude inactive or blocked slots from the away-player display */
			if (!afk_active[slot]
			|| scr_get_social().is_blocked_slot(slot))
			{
				continue;
			}

			/* Each display record carries its player slot and the resolved human-readable name */
			entries[count++] =
			{
				slot: slot,
				name: typing_name_for_slot(slot, afk_names[slot])
			};
		}

		return entries;
	}

	/// @description Format the socially filtered AFK entries for diagnostic output
	/// @returns {String} Slot/name summary or explicit none text
	afk_debug_snapshot = function()
	{
		/* Build the socially filtered AFK list used for this diagnostic summary */
		var entries = afk_build_entries();

		/* Report an explicit empty state when no visible player is away */
		if (array_length(entries) <= 0)
		{
			return "AFK active: none";
		}

		/* Start the diagnostic line with a label before appending player details */
		var snapshot = "AFK active:";

		/* Append each zero-based entry as slot and name so the debug output can identify the player */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			snapshot += " " + string(entries[entry_index].slot) + ":" + entries[entry_index].name;
		}

		return snapshot;
	}

	/// @description Refresh or clear a player typing indicator from local or network state
	/// @param {Real} raw_slot Zero-based server slot
	/// @param {String} username Preferred display name
	/// @param {Bool} is_typing Whether the indicator is active
	/// @returns {Bool} Whether the slot was accepted
	set_typing_state = function(raw_slot, username, is_typing)
	{
		/* Ensure parallel typing arrays can hold the received zero-based slot */
		var slot = typing_ensure_slot(raw_slot);

		/* Reject typing updates that do not identify a valid slot */
		if (slot == noone)
		{
			return false;
		}

		/* Activate the indicator with a resolved name and a local millisecond timeout refreshed from now */
		if (is_typing)
		{
			typing_active[slot] = true;
			typing_names[slot] = typing_name_for_slot(slot, username);
			typing_deadlines[slot] = current_time + typing_timeout_ms;
		}

		/* Stop displaying this slot and clear its expiry deadline, leaving its remembered name available */
		else
		{
			typing_active[slot] = false;
			typing_deadlines[slot] = 0;
		}

		return true;
	}

	/// @description Send or throttle a typing-state packet and report connection loss on a failed transport send
	/// @param {Bool} is_typing Requested active state
	/// @param {Bool} force_send Bypass unchanged-state throttling. Defaults to false
	/// @returns {Real} Zero when skipped, -1 for an invalid local slot, otherwise the transport result
	typing_send_network_state = function(is_typing, force_send = false)
	{
		/* Read the client transport and assigned player slot used for the typing packet */
		var client = scr_get_client();

		/* Skip network typing when offline or missing an assigned slot or usable socket
		The ordered checks avoid reading absent client fields */
		if (!is_struct(client)
		|| (variable_struct_exists(client, "singleplayer_mode") && client.singleplayer_mode)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone
		|| !variable_struct_exists(client, "socket")
		|| !is_real(client.socket)
		|| client.socket < 0)
		{
			return 0;
		}

		/* Active typing may need a periodic refresh even when its Boolean state has not changed */
		if (is_typing)
		{
			/* Avoid resending an unchanged active state before its refresh deadline unless forced */
			if (typing_last_sent_state
			&& !force_send
			&& current_time < typing_next_refresh_time)
			{
				return 0;
			}
		}

		/* An already inactive state needs no repeated stop packet unless forced */
		else if (!typing_last_sent_state && !force_send)
		{
			return 0;
		}

		/* Convert the client ID into the zero-based sender slot encoded in this packet */
		var local_slot = typing_slot_from_value(client.ID);

		/* An invalid assigned slot is an error rather than an ordinary skipped update */
		if (local_slot == noone)
		{
			return -1;
		}

		/* Use the shared packet writer for a N_TYPING_STATE message */
		var net = scr_get_network();
		net.start(N_TYPING_STATE, local_slot);

		/* Encode the Boolean typing state as the protocol byte 1 or 0 */
		net.write(buffer_u8, is_typing ? 1 : 0);

		/* Keep the transport result so callers can distinguish skipped sends from failures */
		var send_result = net.send_server();

		/* Remember only successful sends and schedule the next active refresh in local milliseconds
		An inactive state clears the refresh deadline to zero */
		if (send_result >= 0)
		{
			typing_last_sent_state = is_typing;
			typing_next_refresh_time = is_typing ? current_time + typing_refresh_ms : 0;
		}

		/* A failed send reports the lost connection when the client exposes that handler */
		else if (is_struct(client)
		&& variable_struct_exists(client, "mark_connection_lost"))
		{
			client.mark_connection_lost("Lost connection to server.");
		}

		return send_result;
	}

	/// @description Update and refresh the local player typing indicator without sending a packet
	/// @param {Bool} is_typing Requested active state
	/// @returns {Bool} Whether the local flag changed. False when the assigned slot is unavailable
	typing_set_local_display = function(is_typing)
	{
		/* Read the local client ID so the immediate typing display uses the same slot as network state */
		var client = scr_get_client();

		/* No assigned local slot means there is no player indicator to update */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone)
		{
			return false;
		}

		/* Normalize the assigned ID into the typing array index */
		var local_slot = typing_slot_from_value(client.ID);

		/* Reject an assigned ID that cannot be used as a nonnegative integer slot */
		if (local_slot == noone)
		{
			return false;
		}

		/* Resolve the local label and record whether the visible active flag changed
		set_typing_state also refreshes the expiry deadline when the flag stays active */
		var username = typing_name_for_slot(local_slot, "");
		var changed = typing_local_active != is_typing;
		typing_local_active = is_typing;
		set_typing_state(local_slot, username, is_typing);
		return changed;
	}

	/// @description Clear local typing and refresh state, optionally sending the server a stop packet
	/// @param {Bool} send_off Notify the server. Defaults to true
	typing_stop_local = function(send_off = true)
	{
		/* Normally send a stop packet before clearing the immediate local indicator */
		if (send_off)
		{
			typing_send_network_state(false);
		}

		/* When notification is suppressed, clear the remembered sent flag locally */
		else
		{
			typing_last_sent_state = false;
		}

		typing_set_local_display(false);
		typing_local_active = false;
		typing_next_refresh_time = 0;
		typing_last_input_text = "";
	}

	/// @description Expose the local typing-stop operation to callers
	/// @param {Bool} send_off Notify the server. Defaults to true
	stop_local_typing = function(send_off = true)
	{
		typing_stop_local(send_off);
	}

	/// @description Discard all typing arrays and local send state, optionally notifying the server first
	/// @param {Bool} send_off Send a local stop before clearing. Defaults to false
	clear_typing_states = function(send_off = false)
	{
		/* Optionally notify the server before discarding all local typing records */
		if (send_off)
		{
			typing_stop_local(true);
		}

		typing_active = [];
		typing_names = [];
		typing_deadlines = [];
		typing_local_active = false;
		typing_last_sent_state = false;
		typing_next_refresh_time = 0;
		typing_last_input_text = "";
	}

	/// @description Send a throttled local activity packet and report connection loss when transport fails
	/// @param {Bool} force_send Bypass the activity refresh deadline. Defaults to false
	/// @returns {Real} Zero when skipped, -1 for an invalid local slot, otherwise the transport result
	afk_send_activity = function(force_send = false)
	{
		/* Read the client transport and assigned slot used to report recent local activity */
		var client = scr_get_client();

		/* Offline mode or missing connection state needs no AFK activity packet
		Check the struct and field presence before reading optional client values */
		if (!is_struct(client)
		|| (variable_struct_exists(client, "singleplayer_mode") && client.singleplayer_mode)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone
		|| !variable_struct_exists(client, "socket")
		|| !is_real(client.socket)
		|| client.socket < 0)
		{
			return 0;
		}

		/* Throttle ordinary activity reports until the local millisecond refresh deadline */
		if (!force_send
		&& current_time < afk_next_activity_time)
		{
			return 0;
		}

		/* Normalize the local assigned ID into the sender slot for N_AFK_ACTIVITY */
		var local_slot = typing_slot_from_value(client.ID);

		/* An invalid assigned player slot prevents constructing a valid activity packet */
		if (local_slot == noone)
		{
			return -1;
		}

		/* Use the shared network writer for the activity packet */
		var net = scr_get_network();
		net.start(N_AFK_ACTIVITY, local_slot);

		/* Preserve the network result so callers can detect an activity-send failure */
		var send_result = net.send_server();

		/* Advance the activity throttle only after a successful send */
		if (send_result >= 0)
		{
			afk_next_activity_time = current_time + afk_activity_refresh_ms;
		}

		/* Report a failed send as a lost connection when the handler is available */
		else if (is_struct(client)
		&& variable_struct_exists(client, "mark_connection_lost"))
		{
			client.mark_connection_lost("Lost connection to server.");
		}

		return send_result;
	}

	/// @description Synchronize typing display and packets from editable text, reporting edits as AFK activity
	/// @param {Bool} force_send Request a typing refresh without unchanged-state throttling. Defaults to false
	typing_sync_input_state = function(force_send = false)
	{
		/* Track edits separately from nonblank content so edits report activity while whitespace stops typing */
		var text_changed = input_text != typing_last_input_text;
		var has_text = typing_input_has_content(input_text);

		/* Editing the input counts as local activity for the throttled AFK report */
		if (text_changed)
		{
			afk_send_activity(false);
		}

		/* Nonblank input activates and refreshes the immediate local typing indicator */
		if (has_text)
		{
			typing_set_local_display(true);

			/* Send active typing when text changed, notification is forced, no active state was sent or its refresh is due */
			if (text_changed
			|| force_send
			|| !typing_last_sent_state
			|| current_time >= typing_next_refresh_time)
			{
				typing_send_network_state(true, force_send);
			}
		}

		/* Blank input sends a stop only when local display or remembered network state was active */
		else if (typing_local_active || typing_last_sent_state)
		{
			typing_stop_local(true);
		}

		typing_last_input_text = input_text;
	}

	/// @description Clear active indicators whose current_time millisecond deadlines have elapsed
	typing_update_expired = function()
	{
		/* Check each zero-based typing slot against its local millisecond expiry */
		for (var slot = 0; slot < array_length(typing_active); slot++)
		{
			/* Inactive slots have no expiry work to perform */
			if (!typing_active[slot])
			{
				continue;
			}

			/* Keep indicators whose last received refresh still falls within the timeout */
			if (current_time < typing_deadlines[slot])
			{
				continue;
			}

			typing_active[slot] = false;
			typing_deadlines[slot] = 0;
		}
	}

	/// @description Expire stale typing indicators and collect active unblocked slot/name records
	/// @returns {Array<Struct>} Visible entries with slot and name
	typing_build_entries = function()
	{
		typing_update_expired();

		/* Collect visible typing records and count accepted entries from zero */
		var entries = [];
		var entry_count = 0;

		/* Visit allocated typing slots after removing expired indicators */
		for (var slot = 0; slot < array_length(typing_active); slot++)
		{
			/* Exclude inactive and blocked players from the typing summary */
			if (!typing_active[slot]
			|| scr_get_social().is_blocked_slot(slot))
			{
				continue;
			}

			/* Each summary record holds a zero-based player slot and its resolved display name */
			entries[entry_count++] =
			{
				slot: slot,
				name: typing_name_for_slot(slot, typing_names[slot])
			};
		}

		return entries;
	}

	/// @description Format up to four typing names or a collective label for larger lists
	/// @param {Array<Struct>} entries Visible slot/name records
	/// @param {Bool} include_dots Append textual dots. Defaults to true
	/// @returns {String} Typing label or an empty string for no entries
	typing_summary_from_entries = function(entries, include_dots = true)
	{
		/* Count eligible people before selecting a readable summary format */
		var entry_count = array_length(entries);

		/* No active entries produce an empty footer label */
		if (entry_count <= 0)
		{
			return "";
		}

		/* Append textual dots only when requested, allowing the footer to draw animated dots separately */
		var suffix = include_dots ? "..." : "";

		/* Use a collective label when naming everyone would make the summary too long */
		if (entry_count > 4)
		{
			return "Several people are typing" + suffix;
		}

		/* A single active player can be named directly */
		if (entry_count == 1)
		{
			return entries[0].name + " is typing" + suffix;
		}

		/* Join two names with and without using the longer comma-separated form */
		if (entry_count == 2)
		{
			return entries[0].name + " and " + entries[1].name + " is typing" + suffix;
		}

		/* Start an empty label for the remaining three- or four-person cases */
		var summary_text = "";

		/* Join each zero-based entry into the named typing summary */
		for (var entry_index = 0; entry_index < entry_count; entry_index++)
		{
			/* The first name starts the label without a separator */
			if (entry_index == 0)
			{
				summary_text = entries[entry_index].name;
			}

			/* Introduce the final name with a comma and and */
			else if (entry_index == entry_count - 1)
			{
				summary_text += ", and " + entries[entry_index].name;
			}

			/* Separate intervening names with commas */
			else
			{
				summary_text += ", " + entries[entry_index].name;
			}
		}

		return summary_text + " is typing" + suffix;
	}

	/// @description Expire stale typing state and format visible slots and names for diagnostics
	/// @returns {String} Typing summary or explicit none text
	typing_debug_snapshot = function()
	{
		/* Use the same expired-state cleanup and social filtering as the visible typing list */
		var entries = typing_build_entries();

		/* Report an explicit empty state when nobody visible is typing */
		if (array_length(entries) <= 0)
		{
			return "typing active: none";
		}

		/* Start the diagnostic label before appending slot and name pairs */
		var snapshot = "typing active:";

		/* Append each zero-based visible typing entry for debugging */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			snapshot += " " + string(entries[entry_index].slot) + ":" + entries[entry_index].name;
		}

		return snapshot;
	}
	#endregion /* Typing and AFK State END */

	#region /* World Presence Indicators */
	/// @description Animate three dots on a 180-millisecond cycle and reset alpha to one
	/// @param {Real} dot_start_x First dot center X in the caller drawing coordinates
	/// @param {Real} dot_center_y Dot center Y in the caller drawing coordinates
	/// @param {Real} base_alpha Active-dot opacity. Defaults to 1
	draw_typing_dots = function(dot_start_x, dot_center_y, base_alpha = 1)
	{
		/* Cycle the highlighted dot every 180 local milliseconds across indices zero through two */
		var active_dot = (current_time div 180) mod 3;

		/* Draw all three dots with seven pixels between their centers */
		for (var dot_index = 0; dot_index < 3; dot_index++)
		{
			/* The active dot uses full requested opacity and a 2.5-pixel radius
			Other dots use 35 percent opacity and a two-pixel radius to make the animation readable */
			var dot_alpha = dot_index == active_dot ? base_alpha : base_alpha * 0.35;
			var dot_radius = dot_index == active_dot ? 2.5 : 2;
			draw_set_alpha(dot_alpha);
			draw_circle(dot_start_x + dot_index * 7, dot_center_y, dot_radius, false);
		}

		draw_set_alpha(1);
	}

	/// @description Draw the current typing summary and animated dots in GUI coordinates, leaving left alignment and alpha one
	draw_typing_footer = function()
	{
		/* Build the currently visible typing list and omit textual dots because the footer animates them */
		var entries = typing_build_entries();
		var summary_text = typing_summary_from_entries(entries, false);

		/* An empty summary leaves no footer text or dots to draw */
		if (summary_text == "")
		{
			return;
		}

		draw_set_font(fnt_ui);
		draw_set_halign(fa_left);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(190, 195, 205));
		scr_render_text(typing_footer_x, typing_footer_y, summary_text, 16, log_width);

		/* Measure the 16-pixel summary and place its dots after the text while reserving room at the right edge */
		var summary_scale = scr_render_text_scale(16);
		var dot_start = min(typing_footer_x + string_width(summary_text) * summary_scale + 8, typing_footer_x + log_width - 22);
		draw_typing_dots(dot_start, typing_footer_y + 10, 1);
	}

	/// @description Draw visible typing pills above world characters, preferring visual positions and resetting alignment and alpha
	/// @param {Id.Camera} camera_id Active room camera
	draw_typing_indicators = function(camera_id)
	{
		/* A missing or invalid camera cannot position presence labels in the world */
		if (!is_real(camera_id)
		|| camera_id < 0)
		{
			return;
		}

		/* Collect unexpired, socially visible typing slots for this world rendering pass */
		var entries = typing_build_entries();

		/* An empty presence list needs no world drawing */
		if (array_length(entries) <= 0)
		{
			return;
		}

		/* Resolve each presence slot against the current player roster */
		var controller = scr_get_player_controller();

		/* Require an initialized player array before accessing player positions */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			return;
		}

		/* Read the camera rectangle in room pixels for visibility and placement limits */
		var view_x = camera_get_view_x(camera_id);
		var view_y = camera_get_view_y(camera_id);
		var view_w = camera_get_view_width(camera_id);
		var view_h = camera_get_view_height(camera_id);

		/* Intersect the camera with the room and inset each edge by typing_view_margin room pixels */
		var bounds_left = max(0, view_x) + typing_view_margin;
		var bounds_top = max(0, view_y) + typing_view_margin;
		var bounds_right = min(room_width, view_x + view_w) - typing_view_margin;
		var bounds_bottom = min(room_height, view_y + view_h) - typing_view_margin;

		/* Skip rendering when the room intersection and margins leave no usable label area */
		if (bounds_right <= bounds_left
		|| bounds_bottom <= bounds_top)
		{
			return;
		}

		draw_set_font(fnt_ui);
		draw_set_halign(fa_left);
		draw_set_alpha(1);

		/* Visit each zero-based presence entry to locate its corresponding player */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			/* Read this player slot and typing name from the visible entry list */
			var typing_entry = entries[entry_index];

			/* Skip slots beyond the roster because they have no player position to attach to */
			if (typing_entry.slot >= array_length(controller.players))
			{
				continue;
			}

			/* Resolve the current player occupying the typing slot */
			var typing_player = controller.players[typing_entry.slot];

			/* A vacant roster slot cannot display a typing pill */
			if (typing_player == noone)
			{
				continue;
			}

			/* Start at the authoritative room position before considering interpolation */
			var player_draw_x = typing_player.pos.x;
			var player_draw_y = typing_player.pos.y;

			/* Use visual_pos when available so the label follows the rendered character during interpolation */
			if (variable_struct_exists(typing_player, "visual_pos"))
			{
				player_draw_x = typing_player.visual_pos.x;
				player_draw_y = typing_player.visual_pos.y;
			}

			/* Players outside the camera view do not need a presence label */
			if (player_draw_x < view_x
			|| player_draw_x > view_x + view_w
			|| player_draw_y < view_y
			|| player_draw_y > view_y + view_h)
			{
				continue;
			}

			/* Measure the named typing label at 14 room pixels high
			The pill adds 44 pixels for padding and animated dots and uses a fixed 22-pixel height */
			var label_text = typing_entry.name + " is typing";
			var label_scale = scr_render_text_scale(14);
			var label_width = string_width(label_text) * label_scale;
			var pill_width = ceil(label_width + 44);
			var pill_height = 22;

			/* Use the stored character scale and key, falling back to 2.5 and player1 for older player records */
			var player_size_value = variable_struct_exists(typing_player, "player_size") ? typing_player.player_size : 2.5;
			var typing_character_key = variable_struct_exists(typing_player, "character_key") ? typing_player.character_key : "player1";

			/* Use character bounds to place the pill above the nameplate, whose top is 34 pixels above the sprite
			Clamp its four room-pixel edges into the view and use five-pixel rounded corners */
			var sprite_top = player_character_top_y_key(typing_character_key, player_draw_y, player_size_value);
			var sprite_center_x = player_character_center_x_key(typing_character_key, player_draw_x, player_size_value);
			var nameplate_top = sprite_top - 34;
			var pill_left = clamp(sprite_center_x - pill_width * 0.5, bounds_left, bounds_right - pill_width);
			var pill_top = clamp(nameplate_top - pill_height - 4, bounds_top, bounds_bottom - pill_height);
			var pill_right = pill_left + pill_width;
			var pill_bottom = pill_top + pill_height;
			var pill_radius = 5;

			draw_set_alpha(0.78);
			draw_set_colour(c_black);
			draw_roundrect_ext(pill_left, pill_top, pill_right, pill_bottom, pill_radius, pill_radius, false);
			draw_set_alpha(1);
			draw_set_colour(make_color_rgb(185, 195, 210));
			scr_render_text_draw_scaled(pill_left + 9, pill_top + 4, label_text, label_scale);
			draw_set_colour(make_color_rgb(185, 195, 210));
			draw_typing_dots(pill_left + 18 + label_width, pill_top + pill_height * 0.5 + 1, 1);
		}

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}

	/// @description Draw bobbing AFK labels above visible world characters, suppressing slots with active typing and resetting alignment and alpha
	/// @param {Id.Camera} camera_id Active room camera
	draw_afk_indicators = function(camera_id)
	{
		/* A missing or invalid camera cannot position presence labels in the world */
		if (!is_real(camera_id)
		|| camera_id < 0)
		{
			return;
		}

		/* Collect visible AFK slots for this world rendering pass */
		var entries = afk_build_entries();

		/* An empty presence list needs no world drawing */
		if (array_length(entries) <= 0)
		{
			return;
		}

		/* Resolve each presence slot against the current player roster */
		var controller = scr_get_player_controller();

		/* Require an initialized player array before accessing player positions */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			return;
		}

		/* Read the camera rectangle in room pixels for visibility and placement limits */
		var view_x = camera_get_view_x(camera_id);
		var view_y = camera_get_view_y(camera_id);
		var view_w = camera_get_view_width(camera_id);
		var view_h = camera_get_view_height(camera_id);

		/* An empty camera rectangle cannot contain an AFK label */
		if (view_w <= 0 || view_h <= 0)
		{
			return;
		}

		/* Inset the camera and room intersection by the presence-label margin in room pixels */
		var bounds_left = max(0, view_x) + afk_view_margin;
		var bounds_top = max(0, view_y) + afk_view_margin;
		var bounds_right = min(room_width, view_x + view_w) - afk_view_margin;
		var bounds_bottom = min(room_height, view_y + view_h) - afk_view_margin;

		/* Skip rendering when the room intersection and margins leave no usable label area */
		if (bounds_right <= bounds_left
		|| bounds_bottom <= bounds_top)
		{
			return;
		}

		draw_set_font(fnt_ui);
		draw_set_halign(fa_center);

		/* Visit each zero-based presence entry to locate its corresponding player */
		for (var entry_index = 0; entry_index < array_length(entries); entry_index++)
		{
			/* Read the zero-based away-player slot selected for this rendering pass */
			var afk_entry = entries[entry_index];

			/* Ignore AFK slots that no longer exist in the current roster */
			if (afk_entry.slot >= array_length(controller.players))
			{
				continue;
			}

			/* Typing takes visual precedence over AFK so both labels do not occupy the same space */
			if (afk_entry.slot < array_length(typing_active)
			&& typing_active[afk_entry.slot])
			{
				continue;
			}

			/* Resolve the current player record for this away slot */
			var afk_player = controller.players[afk_entry.slot];

			/* A vacant player slot has no character to carry an away label */
			if (afk_player == noone)
			{
				continue;
			}

			/* Start at the authoritative room position before considering interpolation */
			var player_draw_x = afk_player.pos.x;
			var player_draw_y = afk_player.pos.y;

			/* Follow the interpolated visual position when available to keep the label with the displayed sprite */
			if (variable_struct_exists(afk_player, "visual_pos"))
			{
				player_draw_x = afk_player.visual_pos.x;
				player_draw_y = afk_player.visual_pos.y;
			}

			/* Players outside the camera view do not need a presence label */
			if (player_draw_x < view_x
			|| player_draw_x > view_x + view_w
			|| player_draw_y < view_y
			|| player_draw_y > view_y + view_h)
			{
				continue;
			}

			/* Measure the Zzz label at a 20-room-pixel text height for placement and horizontal clamping */
			var label_text = "Zzz";
			var label_scale = scr_render_text_scale(20);
			var label_width = string_width(label_text) * label_scale;

			/* Use the player character scale and key, falling back to 2.5 and player1 when absent */
			var player_size_value = variable_struct_exists(afk_player, "player_size") ? afk_player.player_size : 2.5;
			var afk_character_key = variable_struct_exists(afk_player, "character_key") ? afk_player.character_key : "player1";

			/* Locate the character bounds and reserve the nameplate area above its top
			bob adds a two-pixel sine motion using local milliseconds and the slot as a phase offset
			label_x and label_y clamp the animated text origin to the visible room bounds */
			var sprite_top = player_character_top_y_key(afk_character_key, player_draw_y, player_size_value);
			var sprite_center_x = player_character_center_x_key(afk_character_key, player_draw_x, player_size_value);
			var nameplate_top = sprite_top - 34;
			var bob = sin(current_time / 420 + afk_entry.slot) * 2;
			var label_x = clamp(sprite_center_x, bounds_left + label_width * 0.5, bounds_right - label_width * 0.5);
			var label_y = clamp(nameplate_top - 25 + bob, bounds_top, bounds_bottom - 22);

			draw_set_alpha(0.72);
			draw_set_colour(c_black);
			scr_render_text_draw_scaled(label_x + 1, label_y + 1, label_text, label_scale);
			draw_set_alpha(1);
			draw_set_colour(make_color_rgb(185, 195, 210));
			scr_render_text_draw_scaled(label_x, label_y, label_text, label_scale);
		}

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	#endregion /* World Presence Indicators END */

	#region /* Player List and Social Rows */
	/// @description Collect occupied socially visible roster slots with names, character keys and local, host and friend flags
	/// @returns {Array<Struct>} Roster display entries with zero-based id
	build_player_list_entries = function()
	{
		/* Build a fresh visible roster list and count accepted entries from zero */
		var entries = [];
		var entry_count = 0;

		/* Read the shared player roster without allocating missing player records */
		var controller = scr_get_player_controller();

		/* An unavailable or uninitialized roster produces an empty list */
		if (!is_struct(controller)
		|| !variable_struct_exists(controller, "players")
		|| !is_array(controller.players))
		{
			return entries;
		}

		/* Read the local and host slot identifiers, starting both at noone when those client fields are unavailable */
		var client = scr_get_client();
		var local_id = noone;
		var host_id = noone;

		/* Identify the local row only when the client has an assigned slot field */
		if (is_struct(client)
		&& variable_struct_exists(client, "ID"))
		{
			local_id = client.ID;
		}

		/* Use the server-provided host slot when available for host labeling and highlighting */
		if (is_struct(client)
		&& variable_struct_exists(client, "host_player_slot"))
		{
			host_id = client.host_player_slot;
		}

		/* Walk the zero-based roster slots rather than treating their indices as socket IDs */
		for (var i = 0; i < array_length(controller.players); i++)
		{
			/* Hide players excluded by the current social visibility settings */
			if (!scr_get_social().player_visible(i))
			{
				continue;
			}

			/* Read the player currently occupying this visible roster slot */
			var player = controller.players[i];

			/* Skip vacant slots rather than creating placeholder rows */
			if (player == noone)
			{
				continue;
			}

			/* Use Player as a readable fallback until the roster supplies a nonempty username */
			var display_name = "Player";

			/* Prefer the populated player username when present */
			if (variable_struct_exists(player, "username")
			&& string(player.username) != "")
			{
				display_name = string(player.username);
			}

			/* Each row keeps the zero-based slot, resolved name and character key, with player1 as the missing-key fallback
			Local and host flags compare slot identifiers, while the friend flag uses the resolved username */
			entries[entry_count++] =
			{
				id: i,
				name: display_name,
				character_key: variable_struct_exists(player, "character_key") ? player.character_key : "player1",
				is_local: i == local_id,
				is_host: i == host_id,
				is_friend: scr_get_social().is_friend_username(display_name)
			};
		}

		return entries;
	}

	/// @description Draw the fixed five-bar green roster icon without measuring latency
	/// @param {Real} x Icon left in GUI pixels
	/// @param {Real} y Icon top in GUI pixels
	draw_player_list_ping_icon = function(x, y)
	{
		/* Draw the five fixed green bars used as the roster connection icon
		This shape does not measure or display the player network latency */
		for (var bar = 0; bar < 5; bar++)
		{
			/* Increase each bar by three GUI pixels and space their left edges five GUI pixels apart */
			var bar_h = 5 + bar * 3;
			var bar_x = x + bar * 5;
			draw_set_colour(make_color_rgb(0, 235, 55));
			draw_rectangle(bar_x, y + 18 - bar_h, bar_x + 4, y + 18, false);
		}
	}

	/// @description Draw the Tab-held roster and up to six blocked names, publishing GUI hit rectangles for social actions
	draw_player_list_overlay = function()
	{
		/* Use shared social state for filtering and for the clickable rectangles produced by this panel */
		var social = scr_get_social();

		/* Hide the panel when Tab is released and clear its hit rectangles so invisible rows cannot receive clicks */
		if (!keyboard_check(vk_tab))
		{
			social.update_player_list_rows([]);
			social.update_block_list_rows([]);
			return;
		}

		/* Read visible roster rows and blocked names separately
		player_count and blocked_count track their totals, while blocked_visible_count caps the displayed blocked rows at six */
		var entries = build_player_list_entries();
		var player_count = array_length(entries);
		var blocked_entries = social.blocked_entries();
		var blocked_count = array_length(blocked_entries);
		var blocked_visible_count = min(blocked_count, 6);

		/* An empty roster and blocked list leave no panel content, so also clear stale hit rectangles */
		if (player_count <= 0 && blocked_visible_count <= 0)
		{
			social.update_player_list_rows([]);
			social.update_block_list_rows([]);
			return;
		}

		/* Measure the GUI viewport in GUI pixels before positioning the roster panel */
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();

		/* Fetch network and client state used by the panel context */
		var net = scr_get_network();
		var client = scr_get_client();

		/* Treat the panel as offline only when the client exposes an enabled singleplayer flag */
		var singleplayer_mode = is_struct(client)
			&& variable_struct_exists(client, "singleplayer_mode")
			&& client.singleplayer_mode;

		/* Use the advertised server capacity when available, otherwise the visible roster count */
		var max_players = is_struct(client) && variable_struct_exists(client, "server_max_players")
			? client.server_max_players
			: player_count;

		/* Offline capacity matches the visible player count rather than any remembered server setting */
		if (singleplayer_mode)
		{
			max_players = player_count;
		}

		/* Begin with at most ten players per column and derive the row count
		Column, row, header and padding sizes are GUI pixels used by both rendering and hit rectangles */
		var columns = max(1, ceil(player_count / 10));
		var rows = ceil(player_count / columns);
		var column_width = 224;
		var row_height = 28;
		var header_height = 54;
		var padding = 8;

		/* Reserve a blocked heading and its row area only when blocked entries are visible */
		var blocked_header_height = blocked_visible_count > 0 ? 28 : 0;
		var blocked_row_height = 26;
		var blocked_section_height = blocked_visible_count > 0 ? blocked_header_height + blocked_visible_count * blocked_row_height + padding : 0;

		/* Size the complete roster and optional blocked section within the viewport width
		Center panel_x horizontally and begin panel_y 18 GUI pixels below the top */
		var panel_width = min(gui_width - 32, columns * column_width + padding * 2);
		var panel_height = header_height + rows * row_height + padding * 2 + blocked_section_height;
		var panel_x = (gui_width - panel_width) * 0.5;
		var panel_y = 18;

		/* When the initial panel is too tall, reduce rows to fit and redistribute players into more columns */
		if (panel_height > gui_height - 36)
		{
			rows = max(1, floor((gui_height - 36 - header_height - padding * 2 - blocked_section_height) / row_height));
			columns = max(1, ceil(player_count / rows));
			panel_width = min(gui_width - 32, columns * column_width + padding * 2);
			panel_height = header_height + rows * row_height + padding * 2 + blocked_section_height;
			panel_x = (gui_width - panel_width) * 0.5;
		}

		draw_set_alpha(0.72);
		draw_set_colour(c_black);
		draw_rectangle(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, false);
		draw_set_alpha(1);

		draw_set_colour(make_color_rgb(86, 86, 90));
		draw_rectangle(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, true);

		draw_set_halign(fa_center);
		draw_set_colour(c_white);

		/* Choose an offline or online player-count label from the panel mode */
		var header_text = singleplayer_mode
			? string(player_count) + "/" + string(max_players) + " players in singleplayer"
			: string(player_count) + "/" + string(max_players) + " players online";
		scr_render_text(panel_x + panel_width * 0.5, panel_y + 9, header_text, 18, panel_width - padding * 2);

		/* Start with the offline reset explanation until an online countdown can be requested */
		var reset_timer_text = "Singleplayer: automatic drawing reset disabled";

		/* Use the client countdown only online and only when that helper exists */
		if (!singleplayer_mode
		&& is_struct(client)
		&& variable_struct_exists(client, "server_reset_countdown_text"))
		{
			reset_timer_text = client.server_reset_countdown_text();
		}

		/* Show the offline reset explanation in gray and the online countdown in yellow */
		draw_set_colour(singleplayer_mode ? make_color_rgb(150, 150, 156) : make_color_rgb(255, 220, 95));
		scr_render_text(panel_x + panel_width * 0.5, panel_y + 31, reset_timer_text, 14, panel_width - padding * 2);
		draw_set_halign(fa_left);

		/* Place the roster inside panel padding and split its usable width evenly across columns
		player_rows starts empty and receives the clickable GUI rectangles for visible player rows */
		var list_x = panel_x + padding;
		var list_y = panel_y + padding + header_height;
		var usable_column_width = (panel_width - padding * 2) / columns;
		var player_rows = [];

		/* Lay out each zero-based roster entry down its column before moving to the next */
		for (var i = 0; i < player_count; i++)
		{
			/* Resolve this entry column, row and record, then compute its GUI-pixel rectangle with a four-pixel horizontal gutter */
			var column = floor(i / rows);
			var row = i mod rows;
			var entry = entries[i];
			var row_x = list_x + column * usable_column_width;
			var row_y = list_y + row * row_height;
			var row_w = usable_column_width - 4;

			/* The host receives the highest-priority background highlight */
			if (entry.is_host)
			{
				draw_set_alpha(0.42);
				draw_set_colour(make_color_rgb(112, 88, 28));
				draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_height - 2, false);
				draw_set_alpha(1);
			}

			/* Highlight the local player when the row did not already receive the host highlight */
			else if (entry.is_local)
			{
				draw_set_alpha(0.38);
				draw_set_colour(make_color_rgb(86, 92, 106));
				draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_height - 2, false);
				draw_set_alpha(1);
			}

			/* Give remaining friend rows a green background highlight */
			else if (entry.is_friend)
			{
				draw_set_alpha(0.30);
				draw_set_colour(make_color_rgb(34, 96, 50));
				draw_rectangle(row_x, row_y, row_x + row_w, row_y + row_height - 2, false);
				draw_set_alpha(1);
			}

			/* Choose the character-box background by host status first, then friendship, then the regular row color */
			draw_set_colour(entry.is_host ? make_color_rgb(108, 82, 24) : (entry.is_friend ? make_color_rgb(27, 82, 38) : make_color_rgb(34, 54, 38)));
			draw_rectangle(row_x + 4, row_y + 4, row_x + 24, row_y + 24, false);
			player_character_draw_key_in_box(entry.character_key, PLAYER_DIRECTION_DOWN, false, row_x + 4, row_y + 4, row_x + 24, row_y + 24, c_white, 1);

			/* Draw a friend marker even when the row also belongs to the host or local player */
			if (entry.is_friend)
			{
				draw_set_colour(make_color_rgb(0, 225, 80));
				draw_circle(row_x + 14, row_y + 21, 4, false);
			}

			/* Name color prioritizes host, then local player, then friend, then ordinary white */
			draw_set_colour(entry.is_host ? make_color_rgb(255, 220, 95) : (entry.is_local ? make_color_rgb(255, 255, 160) : (entry.is_friend ? make_color_rgb(126, 245, 150) : c_white)));

			/* Prefix only the host label while preserving the underlying name for social actions */
			var player_list_name = entry.is_host ? "[HOST] " + entry.name : entry.name;
			scr_render_text(row_x + 32, row_y + 6, player_list_name + " " + scr_network_debug_id_text(entry.id), 16, max(40, row_w - 70));

			draw_player_list_ping_icon(row_x + row_w - 30, row_y + 5);

			/* Publish this row bounds in GUI pixels with its zero-based slot and unprefixed name for social hit testing */
			player_rows[array_length(player_rows)] =
			{
				x1: row_x,
				y1: row_y,
				x2: row_x + row_w,
				y2: row_y + row_height - 2,
				slot_id: entry.id,
				name: entry.name
			};
		}

		/* Start a separate hit-rectangle list for the optional unblock rows */
		var block_rows = [];

		/* Draw the blocked section only when at least one blocked name can be displayed */
		if (blocked_visible_count > 0)
		{
			/* Position the blocked heading after the roster row area and section padding */
			var block_top = list_y + rows * row_height + padding;
			draw_set_colour(make_color_rgb(255, 130, 130));
			scr_render_text(list_x, block_top + 4, "Blocked", 16, panel_width - padding * 2);

			/* Start blocked rows below their heading */
			var block_y = block_top + blocked_header_height;

			/* Draw at most six zero-based blocked entries and publish their unblock hit rectangles */
			for (var block_index = 0; block_index < blocked_visible_count; block_index++)
			{
				/* Read the blocked record and prefer its display spelling when available, otherwise its stored name */
				var block_entry = blocked_entries[block_index];
				var block_name = variable_struct_exists(block_entry, "display") ? block_entry.display : block_entry.name;

				/* Compute the blocked row GUI bounds with a three-pixel bottom gutter */
				var row_left = list_x;
				var row_top = block_y + block_index * blocked_row_height;
				var row_right = panel_x + panel_width - padding;
				var row_bottom = row_top + blocked_row_height - 3;

				draw_set_alpha(0.28);
				draw_set_colour(make_color_rgb(90, 36, 38));
				draw_rectangle(row_left, row_top, row_right, row_bottom, false);
				draw_set_alpha(1);
				draw_set_colour(c_white);
				scr_render_text(row_left + 8, row_top + 5, block_name, 15, max(60, row_right - row_left - 96));
				draw_set_colour(make_color_rgb(255, 200, 200));
				draw_set_halign(fa_right);
				scr_render_text(row_right - 8, row_top + 5, "Unblock", 15, 76);
				draw_set_halign(fa_left);

				/* Each unblock hit record contains its GUI-pixel bounds and the name shown in that row */
				block_rows[array_length(block_rows)] =
				{
					x1: row_left,
					y1: row_top,
					x2: row_right,
					y2: row_bottom,
					name: block_name
				};
			}
		}

		social.update_player_list_rows(player_rows);
		social.update_block_list_rows(block_rows);

		draw_set_alpha(1);
		draw_set_halign(fa_left);
	}
	#endregion /* Player List and Social Rows END */

	#region /* Chat Wrapping and Window Layout */
	/// @description Rebuild or reuse socially filtered wrapped rows, caching both full history and individual message wrapping
	/// @param {Real} width Total log width in GUI pixels, including its timestamp column
	/// @returns {Array<Struct>} Rows containing text, color and a timestamp on each message first row
	build_log_lines = function(width)
	{
		/* Reserve the timestamp column and keep at least 40 GUI pixels for wrapped message text */
		var message_width = max(40, width - timestamp_column_width);

		/* Use social state to invalidate the rendered history when blocking changes
		social_change_time defaults to -1 when older social state has no revision time */
		var social = scr_get_social();
		var social_change_time = variable_struct_exists(social, "last_change_time") ? social.last_change_time : -1;

		/* Reuse cached rows only when width, font height, message revision and social revision all still match */
		if (log_lines_cache_width == message_width
		&& log_lines_cache_height == text_height
		&& log_lines_cache_message_revision == message_revision
		&& log_lines_cache_social_change_time == social_change_time)
		{
			return log_lines_cache;
		}

		/* Start an empty flattened row list and count appended rows from zero */
		var lines = [];
		var line_count = 0;

		/* Visit retained messages oldest first so their wrapped rows preserve history order */
		for (var message_index = 0; message_index < array_length(messages); message_index++)
		{
			/* Read the current retained message before deciding whether it belongs in the visible log */
			var entry = messages[message_index];

			/* Exclude socially blocked messages before measuring or appending their text */
			if (message_is_blocked(entry))
			{
				continue;
			}

			/* Cache each message wrap so new messages do not remeasure the existing history */
			if (!variable_struct_exists(entry, "wrapped_lines")
			|| entry.wrapped_width != message_width
			|| entry.wrapped_height != text_height)
			{
				/* Store this message wrapped text and the GUI-pixel width and font height that produced it
				These lazy fields let unchanged messages retain their own wrap when the full log cache is rebuilt */
				entry.wrapped_lines = string_split(scr_text_wrap(format_message(entry), text_height, message_width), "\n");
				entry.wrapped_width = message_width;
				entry.wrapped_height = text_height;
			}

			/* Use the cached rows and message-type color, with an empty timestamp when no sent_at field exists */
			var parts = entry.wrapped_lines;
			var color = message_color(entry);
			var sent_at = variable_struct_exists(entry, "sent_at") ? string(entry.sent_at) : "";

			/* Append each wrapped row, attaching the message timestamp only to its first row */
			for (var part_index = 0; part_index < array_length(parts); part_index++)
			{
				/* Each log row holds text, its drawing color and an optional first-row timestamp */
				lines[line_count++] =
				{
					text: parts[part_index],
					color: color,
					timestamp: part_index == 0 ? sent_at : ""
				};
			}
		}

		log_lines_cache = lines;
		log_lines_cache_width = message_width;
		log_lines_cache_height = text_height;
		log_lines_cache_message_revision = message_revision;
		log_lines_cache_social_change_time = social_change_time;
		return log_lines_cache;
	}

	/// @description Clamp the chat window origin into the GUI viewport with an eight-pixel outer margin
	clamp_window = function()
	{
		/* Measure the GUI viewport and keep an eight-pixel outer margin when clamping the chat window */
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();
		var outer_margin = 8;

		window_x = clamp(window_x, outer_margin, max(outer_margin, gui_width - window_width - outer_margin));
		window_y = clamp(window_y, outer_margin, max(outer_margin, gui_height - window_height - outer_margin));
	}

	/// @description Rebuild the cached prompt wrapping only when input text, width or font height changes
	/// @returns {Array<String>} Wrapped prompt rows including the final cursor marker
	input_wrapped_lines = function()
	{
		/* Rewrap only after text, width or font height changes
		The cached prompt includes its cursor marker so blinking can hide it without repeatedly measuring text */
		if (input_wrap_cache_text != input_text
		|| input_wrap_cache_width != input_width
		|| input_wrap_cache_height != text_height)
		{
			input_wrap_cache_text = input_text;
			input_wrap_cache_width = input_width;
			input_wrap_cache_height = text_height;
			input_wrap_cache_lines = string_split(scr_text_wrap("> " + input_text + "|", text_height, input_width), "\n");
		}
		return input_wrap_cache_lines;
	}

	/// @description Compute GUI rectangles, footer space and scroll bounds, preserving a user-moved window origin
	/// @returns {Array<Struct>} Current wrapped log rows
	update_layout = function()
	{
		/* Read the GUI viewport for chat width and available vertical space */
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();
		window_width = min(640, max(240, gui_width - 32));
		log_width = max(40, window_width);
		input_width = log_width;

		/* Closed chat has no input rows or input height
		Open chat wraps its prompt and reserves at least 32 GUI pixels for the input box */
		var input_lines = is_open ? array_length(input_wrapped_lines()) : 0;
		input_height = is_open ? max(32, input_lines * line_height - line_gap + 16) : 0;

		/* Prefer ten log rows while editing and six while closed
		available_for_log leaves room for the input and margins, with at least one line height available for calculation */
		var preferred_lines = is_open ? 10 : 6;
		var available_for_log = max(line_height, gui_height - input_height - 56);
		visible_log_lines = max(0, min(preferred_lines, floor(available_for_log / line_height)));

		/* Build the socially filtered wrapped log and count how many rows fit
		An empty log uses zero height rather than a negative trailing line gap */
		var log_lines = build_log_lines(log_width);
		var drawn_line_count = min(visible_log_lines, array_length(log_lines));
		log_height = drawn_line_count > 0 ? drawn_line_count * line_height - line_gap : 0;

		/* Reserve one footer line only when someone visible is typing */
		var typing_entries = typing_build_entries();
		typing_footer_height = array_length(typing_entries) > 0 ? line_height : 0;

		/* Add six GUI pixels between a nonempty log and footer, and eight before an open input when earlier content exists */
		var typing_footer_gap = typing_footer_height > 0 && log_height > 0 ? 6 : 0;
		var input_gap = is_open && (log_height > 0 || typing_footer_height > 0) ? 8 : 0;
		window_height = content_padding * 2 + log_height + typing_footer_gap + typing_footer_height + input_gap + input_height;

		/* Keep the default chat window near the lower left until the user explicitly drags it */
		if (!window_user_moved)
		{
			window_x = 16;
			window_y = gui_height - window_height - 18;
		}

		clamp_window();

		log_x = window_x;
		log_y = window_y + content_padding;
		typing_footer_x = window_x;
		typing_footer_y = log_y + log_height + typing_footer_gap;
		input_x = window_x;
		input_y = typing_footer_y + typing_footer_height + input_gap;

		/* Limit the zero-based row offset to the history remaining beyond the visible log */
		var max_scroll = max(0, array_length(log_lines) - visible_log_lines);
		scroll_lines = clamp(scroll_lines, 0, max_scroll);

		return log_lines;
	}

	/// @description Check whether a point lies within an inclusive rectangle
	/// @param {Real} mx Point X
	/// @param {Real} my Point Y
	/// @param {Real} x1 Left bound
	/// @param {Real} y1 Top bound
	/// @param {Real} x2 Right bound
	/// @param {Real} y2 Bottom bound
	/// @returns {Bool} Whether the point is inside or on an edge
	mouse_in_rect = function(mx, my, x1, y1, x2, y2)
	{
		/* Count the rectangle edges as inside so dragging and scrolling share inclusive GUI hit testing */
		return mx >= x1 && mx <= x2 && my >= y1 && my <= y2;
	}

	/// @description Update GUI layout, open-chat dragging and hovered-log wheel scrolling
	update_mouse_interaction = function()
	{
		/* Refresh layout first so the current history and window dimensions define hit testing */
		var log_lines = update_layout();

		/* Read mouse coordinates in GUI pixels and include the eight-pixel window border in its hit rectangle
		in_window records whether the pointer is inside that complete area */
		var mx = device_mouse_x_to_gui(0);
		var my = device_mouse_y_to_gui(0);
		var outer_x1 = window_x - 8;
		var outer_y1 = window_y - 8;
		var outer_x2 = window_x + window_width + 8;
		var outer_y2 = window_y + window_height + 8;
		var in_window = mouse_in_rect(mx, my, outer_x1, outer_y1, outer_x2, outer_y2);

		/* An initial left press inside open chat starts dragging and preserves the pointer offset from its origin */
		if (is_open && mouse_check_button_pressed(mb_left) && in_window)
		{
			dragging = true;
			window_user_moved = true;
			drag_offset_x = mx - window_x;
			drag_offset_y = my - window_y;
		}

		/* Continue a previously started drag even after the pointer leaves the original window bounds */
		if (dragging)
		{
			/* While the left button remains held, move the window with the pointer and clamp it into the GUI */
			if (mouse_check_button(mb_left))
			{
				window_x = mx - drag_offset_x;
				window_y = my - drag_offset_y;
				clamp_window();
			}

			/* Releasing the left button ends the drag */
			else
			{
				dragging = false;
			}
		}

		/* Only a nonempty log can receive scroll input
		hovering_log adds a four-pixel hit margin around its GUI rectangle */
		var log_has_area = visible_log_lines > 0 && log_height > 0;
		var hovering_log = log_has_area
			&& mouse_in_rect(mx, my, log_x - 4, log_y - 4, log_x + log_width + 4, log_y + log_height + 4);

		/* Scroll history only while chat is open and the pointer is over its log */
		if (is_open && hovering_log)
		{
			/* Wheel up moves three wrapped rows toward older history */
			if (mouse_wheel_up())
			{
				scroll_lines += 3;
			}

			/* Wheel down moves three wrapped rows toward the newest messages */
			if (mouse_wheel_down())
			{
				scroll_lines -= 3;
			}

			/* Clamp wheel movement to valid history offsets so the log cannot scroll beyond either end */
			var max_scroll = max(0, array_length(log_lines) - visible_log_lines);
			scroll_lines = clamp(scroll_lines, 0, max_scroll);
		}
	}
	#endregion /* Chat Wrapping and Window Layout END */

	#region /* Chat Focus and Submission */
	/// @description Request a clipboard copy and show feedback, attempting browser readback without requiring confirmation
	/// @returns {Bool} Whether a nonempty copy request was accepted without a clipboard-set exception
	copy_current_input = function()
	{
		/* Empty input produces a brief notice because there is no chat text to copy */
		if (input_text == "")
		{
			set_clipboard_notice("Nothing to copy.", make_color_rgb(255, 220, 95), 3000);
			return false;
		}

		/* Assume clipboard submission succeeds unless clipboard_set_text throws */
		var copy_failed = false;
		try
		{
			clipboard_set_text(input_text);
		}

		/* Remember a clipboard exception so the shared failure path can show browser-context feedback */
		catch(e)
		{
			copy_failed = true;
		}

		/* A failed clipboard request displays the contextual error and reports failure */
		if (copy_failed)
		{
			set_clipboard_notice(clipboard_browser_context_text("Copy"), make_color_rgb(255, 110, 110));
			return false;
		}

		/* Browser clipboard requests may be asynchronous or permission gated, so attempt an optional readback */
		if (clipboard_is_browser_runtime())
		{
			/* Keep browser confirmation false until a readable clipboard exactly matches the requested text */
			var verified = false;
			try
			{
				/* Compare text only when the clipboard reports a readable text value */
				if (clipboard_has_text())
				{
					verified = string(clipboard_get_text()) == input_text;
				}
			}

			/* A blocked clipboard read cannot confirm the earlier request */
			catch(e)
			{
				verified = false;
			}

			/* An unconfirmed browser request still reports acceptance and asks the user to allow any clipboard permission prompt */
			if (!verified)
			{
				set_clipboard_notice("Copy requested. Allow browser clipboard permission if prompted.", make_color_rgb(255, 220, 95));
				return true;
			}
		}

		set_clipboard_notice("Copied chat text.", make_color_rgb(126, 245, 150), 3000);
		return true;
	}

	/// @description Call the available client movement-release helper
	/// @returns {Bool} Client helper result, or false when the helper is unavailable
	release_local_movement = function()
	{
		/* Use the client movement-release helper to stop held movement when chat gains focus */
		var client = scr_get_client();

		/* Release movement only when the client exposes the helper, otherwise report that no release occurred */
		if (is_struct(client)
		&& variable_struct_exists(client, "release_local_movement"))
		{
			return client.release_local_movement();
		}
		return false;
	}

	/// @description Focus chat with prefilled text, reset scrolling, release held movement once and synchronize typing
	/// @param {String} prefill Initial input. Defaults to an empty string
	open = function(prefill = "")
	{
		is_open = true;
		input_text = string(prefill);
		keyboard_string = input_text;
		typing_last_input_text = "";
		scroll_lines = 0;
		latest_activity_time = current_time;

		/* Release held movement once so opening chat does not leave the player walking */
		if (!released_movement_on_open)
		{
			release_local_movement();
			released_movement_on_open = true;
		}

		typing_sync_input_state(true);
	}

	/// @description Stop local typing and clear chat focus, keyboard text, dragging, scrolling and the opening movement-release flag
	close = function()
	{
		typing_stop_local(true);
		is_open = false;
		input_text = "";
		keyboard_string = "";
		dragging = false;
		scroll_lines = 0;
		released_movement_on_open = false;
	}

	/// @description Send validated chat to the server, or echo it locally in singleplayer, then close chat
	/// @returns {Bool} Whether the send was accepted. Online display waits for the server echo
	send_current_input = function()
	{
		/* Sanitize the current input before command validation or network encoding */
		var text = sanitize_chat_input(input_text);

		/* Empty sanitized input simply closes chat without sending a message */
		if (text == "")
		{
			close();
			return false;
		}

		/* A leading slash enters command validation rather than sending an ordinary player message */
		if (chat_text_starts_with(text, "/"))
		{
			/* Use a lowercase copy for command matching while preserving the submitted text spelling */
			var lower_text = string_lower(text);

			/* Only a nonempty /say command is accepted here
			Unknown commands and empty /say content show an error and close without sending */
			if (!chat_text_starts_with(lower_text, "/say ")
			|| string_trim(string_copy(text, 6, string_length(text) - 5)) == "")
			{
				add_local_error("Unknown command.");
				close();
				return false;
			}
		}

		/* Read the assigned sender slot and offline mode from client state */
		var client = scr_get_client();

		/* Require a connected or offline-initialized client with an assigned slot before accepting chat */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone)
		{
			add_local_error("Cannot send chat while disconnected.");
			close();
			return false;
		}

		/* Offline chat echoes locally because there is no server to validate and relay it */
		if (variable_struct_exists(client, "singleplayer_mode")
		&& client.singleplayer_mode)
		{
			/* Use the offline assigned username as the local message sender label */
			var singleplayer_name = client.assigned_username;

			/* Use Player when the offline assigned name is empty */
			if (singleplayer_name == "")
			{
				singleplayer_name = "Player";
			}

			/* An offline /say message stores only its sanitized command content with the SAY message type */
			if (chat_text_starts_with(string_lower(text), "/say "))
			{
				/* Strip the five-character /say prefix and sanitize the remaining emote text */
				var singleplayer_say_content = chat_sanitize_message(string_copy(text, 6, string_length(text) - 5));

				/* Append the local SAY entry only when its sanitized content remains nonempty */
				if (singleplayer_say_content != "")
				{
					add_message(CHAT_TYPE_SAY, client.ID, singleplayer_name, singleplayer_say_content);
				}
			}

			/* Other offline input becomes an ordinary local player-message entry */
			else
			{
				add_message(CHAT_TYPE_PLAYER, client.ID, singleplayer_name, text);
			}

			close();
			return true;
		}

		/* Use the shared network writer to send N_MESSAGE with the client assigned sender slot */
		var net = scr_get_network();
		net.start(N_MESSAGE, client.ID);
		net.write(buffer_string, text);

		/* Retain the transport result for both error reporting and the accepted-send return value */
		var send_result = net.send_server();

		/* A failed transport send adds a local chat error before closing the input */
		if (send_result < 0)
		{
			add_local_error("Chat message could not be sent.");

			/* Also notify the client connection-loss handler when it is available */
			if (is_struct(client)
			&& variable_struct_exists(client, "mark_connection_lost"))
			{
				client.mark_connection_lost("Lost connection to server.");
			}
		}

		/* Online chat appears when the server echoes an accepted send as N_MESSAGE */
		close();

		/* Accept nonnegative transport results while online rendering waits for the server echo */
		return send_result >= 0;
	}

	/// @description Handle chat focus, paste, commands and typing state during the client Step
	/// @returns {Bool} Whether chat handled input this step. Callers use this to suppress movement
	update_client_input = function()
	{
		/* Closed chat checks its opening shortcuts before deciding whether the game should retain normal input */
		if (!is_open)
		{
			/* T or Enter opens an empty chat prompt and consumes this step input */
			if (keyboard_check_pressed(ord("T")))
			|| (keyboard_check_pressed(vk_enter))
			{
				open("");
				return true;
			}

			/* The slash shortcut opens chat with a command prefix already inserted */
			if (keyboard_check_pressed(ord("/")))
			{
				open("/");
				return true;
			}

			return false;
		}

		/* Remember the previous input so clipboard notices clear only when keyboard synchronization actually edits it */
		var input_before_keyboard_sync = input_text;
		scr_text_input_update("chat", input_text, max_input_length);

		/* Clean changed keyboard text before it enters chat state */
		if (keyboard_string != input_text)
		{
			input_text = clean_input_text(keyboard_string);

			/* Write the cleaned value back when sanitation changed it so the next step does not reintroduce rejected text */
			if (keyboard_string != input_text) keyboard_string = input_text;
		}
		update_mouse_interaction();

		/* Compare the synchronized input against its saved value to detect an actual edit */
		var input_changed_by_keyboard_sync = input_text != input_before_keyboard_sync;

		/* New input invalidates feedback about an earlier clipboard operation */
		if (input_changed_by_keyboard_sync)
		{
			clear_clipboard_notice();
		}

		/* Read Control for the chat copy shortcut */
		var ctrl_down = keyboard_check(vk_control);

		/* Control+C copies the current chat text and consumes the shortcut */
		if (ctrl_down && keyboard_check_pressed(ord("C")))
		{
			copy_current_input();
			return true;
		}

		/* Escape cancels chat focus and consumes the key without submitting text */
		if (keyboard_check_pressed(vk_escape))
		{
			close();
			return true;
		}

		/* Enter submits the current input and consumes the key even when validation rejects the message */
		if (keyboard_check_pressed(vk_enter))
		{
			send_current_input();
			return true;
		}

		typing_sync_input_state(false);
		return true;
	}
	#endregion /* Chat Focus and Submission END */

	/// @description Draw recent or open GUI chat, scrolling, typing, blinking input and clipboard feedback using cached wrapping
	draw_overlay = function()
	{
		/* Show chat while editing, while retained messages are within the closed visibility interval or while someone is typing
		The message check uses local milliseconds since the most recent chat activity */
		var should_draw = is_open
			|| (array_length(messages) > 0 && current_time - latest_activity_time <= closed_visible_ms)
			|| array_length(typing_build_entries()) > 0;

		/* Skip layout and drawing once closed chat has no recent message or active typing indicator */
		if (!should_draw)
		{
			return;
		}

		/* Refresh the cached wrapped log and choose its visible zero-based row range after applying scroll_lines
		last_line is exclusive, and first_line is clamped to the beginning of retained history */
		var log_lines = update_layout();
		var total_lines = array_length(log_lines);
		var last_line = max(0, total_lines - scroll_lines);
		var first_line = max(0, last_line - visible_log_lines);

		/* Use a stronger background while editing and a lighter background for the passive chat overlay */
		draw_set_alpha(is_open ? 0.62 : 0.38);
		draw_set_colour(c_black);
		draw_rectangle(window_x - 8, window_y - 8, window_x + window_width + 8, window_y + window_height + 8, false);
		draw_set_alpha(1);

		/* Open chat receives a top strip indicating the movable window */
		if (is_open)
		{
			draw_set_alpha(0.38);
			draw_set_colour(make_color_rgb(44, 44, 48));
			draw_rectangle(window_x - 8, window_y - 8, window_x + window_width + 8, window_y - 2, false);
			draw_set_alpha(1);
		}

		/* Start history drawing at the log GUI origin and advance by one configured line height per row */
		var yy = log_y;

		/* Draw only the selected half-open wrapped-row range */
		for (var i = first_line; i < last_line; i++)
		{
			/* Render the timestamp column only on rows carrying a nonempty first-row timestamp */
			if (log_lines[i].timestamp != "")
			{
				draw_set_colour(make_color_rgb(150, 150, 156));
				scr_render_text(log_x, yy + 3, log_lines[i].timestamp, timestamp_text_height, timestamp_column_width - 6);
			}
			draw_set_colour(log_lines[i].color);
			scr_render_text(log_x + timestamp_column_width, yy, log_lines[i].text, text_height, max(40, log_width - timestamp_column_width));
			yy += line_height;
		}

		/* Draw the typing footer only when layout reserved space for visible typing entries */
		if (typing_footer_height > 0)
		{
			draw_typing_footer();
		}

		/* Open chat also draws the editable prompt and any active clipboard notice */
		if (is_open)
		{
			/* Start with a visible cursor marker before applying its blink phase */
			var cursor = "|";

			/* Hide the cursor on alternate 500-millisecond intervals without changing input text */
			if ((current_time div 500) mod 2 == 1)
			{
				cursor = "";
			}

			draw_set_alpha(0.75);
			draw_set_colour(c_black);
			draw_rectangle(input_x - 4, input_y - 2, input_x + input_width + 4, input_y + input_height, false);
			draw_set_alpha(1);

			draw_set_colour(c_white);

			/* Use the cached wrapped prompt, which retains its final cursor marker for layout */
			var input_lines = input_wrapped_lines();

			/* Draw each zero-based prompt row in GUI pixels */
			for (var input_line_index = 0; input_line_index < array_length(input_lines); input_line_index++)
			{
				/* Copy the row locally so hiding its cursor does not mutate the wrap cache */
				var input_line = input_lines[input_line_index];

				/* During the hidden phase, remove only the cursor marker at the end of the final prompt row */
				if (cursor == "" && input_line_index == array_length(input_lines) - 1)
				{
					input_line = string_copy(input_line, 1, max(0, string_length(input_line) - 1));
				}
				scr_render_text(input_x, input_y + 7 + input_line_index * line_height, input_line, text_height, input_width);
			}

			/* Draw clipboard feedback only while its local millisecond lifetime remains active */
			if (clipboard_notice_active())
			{
				/* Measure the wrapped notice at 14 GUI pixels high and initially place it six pixels above the input */
				var notice_height = scr_text_line_count(scr_text_wrap(clipboard_notice_text, 14, input_width)) * 16 + 6;
				var notice_y = input_y - notice_height - 6;

				/* Move the notice below the input when its preferred position would rise above the window border */
				if (notice_y < window_y - 8)
				{
					notice_y = input_y + input_height + 6;
				}

				draw_set_alpha(0.82);
				draw_set_colour(c_black);
				draw_rectangle(input_x - 4, notice_y - 3, input_x + input_width + 4, notice_y + notice_height, false);
				draw_set_alpha(1);

				draw_set_colour(clipboard_notice_color);
				scr_render_text_wrapped(input_x, notice_y, clipboard_notice_text, 14, input_width, 2);
			}
		}
	}
}

/// @description Get the shared chat state
/// @returns {Struct} Lazily constructed scr_chat instance
function scr_get_chat()
{
	/* Create one shared chat state on first access and retain its history, input, layout caches and presence arrays */
	static chat = new scr_chat();
	return chat;
}
