#region /* Log Paths and Timestamps */
/// @description Convert an integer to zero-padded timestamp text
/// @param {Real} value Value to floor
/// @param {Real} digits Minimum character width
/// @returns {String} Padded text. Longer values are retained
function scr_debug_export_pad_number(value, digits)
{
	/* Convert the requested value to integer text before padding, retaining its sign if negative */
	var text = string(floor(real(value)));

	/* Pad shorter numeric text with leading zeros until the requested timestamp width is reached */
	while (string_length(text) < digits)
	{
		text = "0" + text;
	}

	return text;
}

/// @description Capture the local datetime as a filename-safe timestamp
/// @returns {String} YYYY-MM-DD_HH-MM-SS
function scr_debug_export_timestamp()
{
	/* Capture the local wall-clock datetime once so all filename components describe the same instant */
	var now = date_current_datetime();
	return scr_debug_export_pad_number(date_get_year(now), 4)
		+ "-" + scr_debug_export_pad_number(date_get_month(now), 2)
		+ "-" + scr_debug_export_pad_number(date_get_day(now), 2)
		+ "_"
		+ scr_debug_export_pad_number(date_get_hour(now), 2)
		+ "-" + scr_debug_export_pad_number(date_get_minute(now), 2)
		+ "-" + scr_debug_export_pad_number(date_get_second(now), 2);
}

/// @description Normalize native path separators
/// @param {String} raw_path Path to normalize
/// @returns {String} Backslashes on Windows, forward slashes elsewhere
function scr_debug_export_normalize_path(raw_path)
{
	/* Convert the supplied path to text before normalizing directory separators */
	var path_text = string(raw_path);

	/* Windows normalizes native paths to backslashes
	Other platforms fall through to forward-slash normalization */
	if (os_type == os_windows)
	{
		return string_replace_all(path_text, "/", "\\");
	}

	return string_replace_all(path_text, "\\", "/");
}

/// @description Convert backslashes for path display or file-URL use
/// @param {String} raw_path Path text
/// @returns {String} Forward-slash path without URL encoding
function scr_debug_export_file_url_path(raw_path)
{
	return string_replace_all(string(raw_path), "\\", "/");
}

/// @description Select the current platform's native directory separator
/// @returns {String} Backslash on Windows, forward slash elsewhere
function scr_debug_export_path_separator()
{
	/* Choose a backslash on Windows and a forward slash elsewhere so joins match path normalization */
	return os_type == os_windows ? "\\" : "/";
}

/// @description Join normalized base and leaf paths
/// @param {String} base_path Base directory
/// @param {String} leaf_path Leaf path
/// @returns {String} Joined path. Does not strip a leading separator from the leaf
function scr_debug_export_path_join(base_path, leaf_path)
{
	/* left is the normalized base and right is the normalized leaf path */
	var left = scr_debug_export_normalize_path(base_path);
	var right = scr_debug_export_normalize_path(leaf_path);

	/* An empty base uses the leaf alone, avoiding an unwanted leading separator */
	if (left == "")
	{
		return right;
	}

	/* An empty leaf leaves the base unchanged without adding a trailing separator */
	if (right == "")
	{
		return left;
	}

	/* Read the base's final one-based character to determine whether its join boundary already has a separator */
	var last_char = string_char_at(left, string_length(left));

	/* A base ending in either separator joins directly to the leaf, avoiding duplicate separators */
	if (last_char == "/" || last_char == "\\")
	{
		return left + right;
	}

	return left + scr_debug_export_path_separator() + right;
}

/// @description Locate the debug-export directory beneath game_save_id
/// @returns {String} Native path, or relative debug_logs when the save path is empty
function scr_debug_export_folder_path()
{
	/* An unavailable game_save_id uses relative debug_logs as a fallback
	Otherwise place the directory beneath the save root */
	if (string(game_save_id) == "")
	{
		return "debug_logs";
	}

	return scr_debug_export_path_join(game_save_id, "debug_logs");
}

/// @description Locate the persistent server-session log directory
/// @returns {String} server_sessions path beneath debug_logs
function scr_server_logs_folder_path()
{
	return scr_debug_export_path_join(scr_debug_export_folder_path(), "server_sessions");
}
#endregion /* Log Paths and Timestamps END */

#region /* Persistent Server Sessions */
/// @description Get persistent logging state shared by the server session and debug message store
/// @returns {Struct} Mutable state with separate technical and chat rotation counters
function scr_server_logs_state()
{
	/* The static state is shared for this runtime
	enabled starts false until startup, and writing guards nested appends until the attempt finishes
	session starts unnamed, parts begins at one for technical/chat indices 0/1, and bytes tracks those parts from zero
	last_error and failed_writes retain failures, next_warning_at zero permits the first current_time warning,
	and secrets stores runtime-wide redaction values that remain across server sessions */
	static state =
	{
		enabled: false,
		writing: false,
		session: "",
		parts: [1, 1],
		bytes: [0, 0],
		last_error: "",
		failed_writes: 0,
		next_warning_at: 0,
		secrets: []
	};
	return state;
}

/// @description Register every nonempty secret for exact-text redaction in future logs
/// @param {String} raw_secret Admin token or key ID. Registered values remain for this runtime session
function scr_server_logs_protect_secret(raw_secret)
{
	/* Convert the candidate secret to text before checking for an absent value */
	var secret = string(raw_secret);

	/* An empty value is absent configuration, so there is no secret to register.
	Keep every nonempty value, including short key IDs accepted by admin validation.
	A length cutoff would leave those configured values visible in persisted logs */
	if (secret == "")
	{
		return;
	}

	/* Use the shared runtime redaction list so future persisted and exported messages can replace this value */
	var state = scr_server_logs_state();

	/* Check every registered secret before adding a value so exact duplicates can be detected */
	for (var i = 0; i < array_length(state.secrets); i++)
	{
		/* A secret already registered needs no second copy because replacement covers every occurrence */
		if (state.secrets[i] == secret)
		{
			return;
		}
	}
	state.secrets[array_length(state.secrets)] = secret;
}

/// @description Replace every registered secret before text is logged or exported
/// @param {String} raw_text Unredacted text
/// @returns {String} Text with registered values replaced by <redacted>
function scr_server_logs_redact(raw_text)
{
	/* text is the output being redacted and secrets is the shared registration list */
	var text = string(raw_text);
	var secrets = scr_server_logs_state().secrets;

	/* Apply each registered secret's replacement to cover the full session list */
	for (var i = 0; i < array_length(secrets); i++)
	{
		text = string_replace_all(text, secrets[i], "<redacted>");
	}
	return text;
}

/// @description Retain a redacted write failure and pace direct debugger warnings
/// @param {String} message Failure text
/// @returns {Bool} Always false, for use by failed-write paths
function scr_server_logs_report_error(message)
{
	/* Retain the redacted error and count this failed write in the shared logging state */
	var state = scr_server_logs_state();
	state.last_error = scr_server_logs_redact(message);
	state.failed_writes++;

	/* After the 30-second current_time warning interval, show the latest failure and schedule the next warning
	Suppressed failures still update the error and failed-write count above */
	if (current_time >= state.next_warning_at)
	{
		state.next_warning_at = current_time + 30000;

		/* Do not route write failures through debug_error: that also appends a log */
		show_debug_message("[ERROR] Persistent server logging: " + state.last_error);
	}
	return false;
}

/// @description Append a redacted line to the active server session log
/// @param {String} kind Use chat for the chat channel. All other values select the technical channel
/// @param {String} raw_line Text to append
/// @returns {Bool} Whether the append and close succeeded. Disabled or guarded writes return false
function scr_server_logs_append(kind, raw_line)
{
	/* Read the shared logging state before choosing a channel or opening its append file */
	var state = scr_server_logs_state();

	/* Disabled logging or an active writing guard rejects the append before opening a file.
	The active attempt owns the guard until its finally block releases it,
	so nested appends cannot open a second writer */
	if (!state.enabled || state.writing)
	{
		return false;
	}

	/* channel selects index 1 for chat and index 0 for all other kinds, separating their byte totals and rotation parts */
	var channel = kind == "chat" ? 1 : 0;

	/* channel_name identifies the selected stream as chat or technical in its filename */
	var channel_name = channel == 1 ? "chat" : "technical";

	/* line contains exact-secret replacements, and line_bytes estimates its UTF-8 bytes plus a two-byte line ending for rotation */
	var line = scr_server_logs_redact(raw_line);
	var line_bytes = string_byte_length(line) + 2;

	/* Rotate before a line would push a nonempty channel part beyond 8 MiB
	An empty part accepts its first line even when that line alone exceeds the limit
	Files are closed after each append */
	if (state.bytes[channel] > 0 && state.bytes[channel] + line_bytes > 8388608)
	{
		state.parts[channel]++;
		state.bytes[channel] = 0;
	}

	/* file_path combines the session, channel name and four-digit rotation part
	file_handle starts at -1 until this operation owns an append handle */
	var file_path = scr_debug_export_path_join(scr_server_logs_folder_path(),
		state.session + "_" + channel_name + "_" + scr_debug_export_pad_number(state.parts[channel], 4) + ".txt");
	var file_handle = -1;

	/* Hold the guard through writing, closing and failure reporting.
	The finally block releases it on both return paths so later appends can proceed */
	state.writing = true;
	try
	{
		file_handle = file_text_open_append(file_path);

		/* A failed append-file open throws before writing, allowing the common error handler to report the invalid handle */
		if (file_handle < 0)
		{
			throw "Could not append to " + file_path;
		}
		file_text_write_string(file_handle, line);
		file_text_writeln(file_handle);

		/* Capture close success and clear the handle sentinel before reporting any flush failure */
		var closed_ok = file_text_close(file_handle);
		file_handle = -1;

		/* A reported close or flush failure means the append cannot be counted as successful */
		if (!closed_ok)
		{
			throw "Could not flush " + file_path;
		}
		state.bytes[channel] += line_bytes;
		return true;
	}

	/* Convert write errors to the shared persistent-logging diagnostic after attempting handle cleanup */
	catch(e)
	{
		/* Release a handle that remained open at the failure point
		Ignore a secondary close error so the original write error is retained */
		if (file_handle >= 0)
		{
			try { file_text_close(file_handle); } catch(close_error) { }
		}
		return scr_server_logs_report_error(scr_debug_export_exception_text(e));
	}
	finally
	{
		/* Release this attempt's guard after success or failure, including an early
		return from try or catch. The next technical or chat append can then start */
		state.writing = false;
	}
}

/// @description Start a desktop server log session and register admin environment secrets
/// @returns {Bool} Whether an existing session is enabled or both new session headers were written
function scr_server_logs_start()
{
	/* Inspect the existing runtime logging state before creating a new session */
	var state = scr_server_logs_state();

	/* Reuse an enabled session without resetting counters or creating another session name */
	if (state.enabled)
	{
		return true;
	}

	/* Browser and GX builds skip persistent desktop logging because they cannot use this native-folder path */
	if (os_browser != browser_not_a_browser || os_type == os_gxgames)
	{
		return false;
	}
	scr_server_logs_protect_secret(environment_get_variable("JONNIL_ADMIN_TOKEN"));
	scr_server_logs_protect_secret(environment_get_variable("JONNIL_ADMIN_KEY_ID"));
	try
	{
		/* root_folder is the debug-export root, and session_folder is its persistent server_sessions subdirectory */
		var root_folder = scr_debug_export_folder_path();
		var session_folder = scr_server_logs_folder_path();

		/* Create a missing debug-log root before preparing its server-session subfolder */
		if (!directory_exists(root_folder)) directory_create(root_folder);

		/* Create a missing session subfolder before opening any session log */
		if (!directory_exists(session_folder)) directory_create(session_folder);

		/* If folder creation still leaves the session directory absent, stop before opening log files */
		if (!directory_exists(session_folder))
		{
			throw "Could not create " + session_folder;
		}

		/* session_base combines the Server_ prefix and local timestamp
		suffix starts at one, and session_name includes it to avoid colliding with another run */
		var session_base = "Server_" + scr_debug_export_timestamp();
		var suffix = 1;
		var session_name = session_base + "_" + string(suffix);

		/* Advance the suffix while either channel's first-part path exists
		Both names must be unused so sessions with the same timestamp do not append to earlier logs */
		while (file_exists(scr_debug_export_path_join(session_folder, session_name + "_technical_0001.txt"))
		|| file_exists(scr_debug_export_path_join(session_folder, session_name + "_chat_0001.txt")))
		{
			suffix++;
			session_name = session_base + "_" + string(suffix);
		}
		state.session = session_name;
		state.parts = [1, 1];
		state.bytes = [0, 0];
		state.last_error = "";
		state.enabled = true;

		/* The shared header identifies the session, build, runtime and local timestamp convention */
		var header = "Jonnil Online server session " + session_name
			+ " | Build " + string(scr_get_build_date(true, true))
			+ " | Runtime " + string(GM_runtime_version)
			+ " | Timestamps: server local time; each append is closed immediately.";

		/* technical_ok and chat_ok record independent first-header append results for the two channels */
		var technical_ok = scr_server_logs_append("technical", header);
		var chat_ok = scr_server_logs_append("chat", header);

		/* Both channel-header appends must succeed before session startup reports success */
		return technical_ok && chat_ok;
	}

	/* Report folder or startup exceptions through the persistent logging state without enabling an unrelated debug append */
	catch(e)
	{
		return scr_server_logs_report_error(scr_debug_export_exception_text(e));
	}
}

/// @description Attempt a final technical entry and disable persistent appends
/// @param {String} reason Text recorded with the session end, defaulting to server stopped
function scr_server_logs_stop(reason = "server stopped")
{
	/* Use the current session's shared state for the final append attempt and disable flag */
	var state = scr_server_logs_state();

	/* An enabled session gets a final ending-entry attempt
	Disable subsequent appends regardless of whether that entry succeeds */
	if (state.enabled)
	{
		scr_server_logs_append("technical", "[" + chat_export_timestamp() + "] [INFO] Session ended: " + string(reason));
	}
	state.enabled = false;
}

/// @description Enumerate saved session and manual exports for the admin download protocol
/// @returns {Struct} ok, files with name/path/size, total_bytes and message. Sizes are bytes
function scr_server_logs_manifest()
{
	/* result starts failed with no files, zero total bytes and no diagnostic
	Each accepted file entry later records its basename, native path and snapshotted byte length */
	var result = { ok: false, files: [], total_bytes: 0, message: "" };

	/* Search entries pair a folder with its filename mask, covering both persistent channels and both manual transcript exports */
	var searches =
	[
		{ folder: scr_server_logs_folder_path(), mask: "Server_*_technical_*.txt" },
		{ folder: scr_server_logs_folder_path(), mask: "Server_*_chat_*.txt" },
		{ folder: scr_debug_export_folder_path(), mask: "JonnilOnline_DebugLog_*.txt" },
		{ folder: scr_debug_export_folder_path(), mask: "JonnilOnline_ChatLog_*.txt" }
	];

	/* file_handle starts unowned at -1, and find_open starts false until enumeration needs cleanup */
	var file_handle = -1;
	var find_open = false;
	try
	{
		/* Visit every saved-log search pattern so the manifest includes session channels and manual exports */
		for (var search_index = 0; search_index < array_length(searches); search_index++)
		{
			/* Select this zero-based folder/mask pair from the search list */
			var search = searches[search_index];

			/* Skip absent search folders so a missing log category does not prevent collecting the others */
			if (!directory_exists(search.folder)) continue;

			/* found stores the current filename from enumeration, with empty text marking the end of a search */
			var found = file_find_first(scr_debug_export_path_join(search.folder, search.mask), 0);
			find_open = true;

			/* Continue enumerating matches until the file search returns empty text */
			while (found != "")
			{
				/* name removes directory text from the match, and path reconstructs its native location within the searched folder */
				var name = filename_name(found);
				var path = scr_debug_export_path_join(search.folder, name);

				/* Inspect only existing files, skipping directory entries and matches that vanished during enumeration */
				if (file_exists(path) && !directory_exists(path))
				{
					file_handle = file_bin_open(path, 0);

					/* A failed binary open aborts the manifest instead of advertising an unreadable source file */
					if (file_handle < 0) throw "Could not read saved log " + name;

					/* Capture the file's current binary byte length for the fixed download snapshot */
					var size = file_bin_size(file_handle);
					file_bin_close(file_handle);
					file_handle = -1;

					/* Reject snapshots above 128 files, 128 MiB per file or 256 MiB total
					The diagnostic directs administrators to SSH for the full archive */
					if (size > 134217728 || result.total_bytes + size > 268435456
					|| array_length(result.files) >= 128)
					{
						throw "Saved logs exceed the in-game download limit (128 files, 128 MiB per file, 256 MiB total). Retrieve the full saved logs over SSH.";
					}

					/* Append the validated entry's basename, readable native path and byte length to the manifest */
					result.files[array_length(result.files)] = { name: name, path: path, size: size };
					result.total_bytes += size;
				}
				found = file_find_next();
			}
			file_find_close();
			find_open = false;
		}
		result.ok = true;

		/* An empty successful manifest receives an explanation, while populated manifests need no message */
		result.message = array_length(result.files) == 0 ? "No saved server logs are available yet." : "";
	}

	/* Discard the partially built manifest after a read or limit failure and retain its exception diagnostic */
	catch(e)
	{
		result.files = [];
		result.total_bytes = 0;
		result.message = scr_debug_export_exception_text(e);
	}
	finally
	{
		/* Close any binary handle still owned after manifest construction, including after exceptions */
		if (file_handle >= 0) file_bin_close(file_handle);

		/* End an active file search even if a read failure interrupted enumeration */
		if (find_open) file_find_close();
	}
	return result;
}
#endregion /* Persistent Server Sessions END */

#region /* Export Status and Folder Access */
/// @description Clear the shared export failure message and associated target path
function scr_debug_export_clear_error()
{
	/* These shared values start or reset empty, clearing both the last failure message and its associated target path */
	global.debug_export_last_error = "";
	global.debug_export_last_path = "";
}

/// @description Store and log an export failure with its optional target path
/// @param {String} message Failure text
/// @param {String} target_path Affected path. Defaults to empty text
function scr_debug_export_set_error(message, target_path = "")
{
	/* Store the failure message and its optional target as strings for status getters and error logging */
	global.debug_export_last_error = string(message);
	global.debug_export_last_path = string(target_path);

	/* A nonblank recorded path is included in the error log to identify the affected target */
	if (string_trim(global.debug_export_last_path) != "")
	{
		debug_error(global.debug_export_last_error + " Path: " + global.debug_export_last_path);
	}

	/* Without a recorded path, report the error alone so the message does not contain an empty path label */
	else
	{
		debug_error(global.debug_export_last_error);
	}
}

/// @description Read the most recent shared export diagnostic
/// @returns {String} Error text, or empty text before initialization
function scr_debug_export_last_error()
{
	/* Before the shared error is initialized, return empty text so status queries remain safe */
	if (!variable_global_exists("debug_export_last_error"))
	{
		return "";
	}

	return string(global.debug_export_last_error);
}

/// @description Read the target associated with the shared export diagnostic
/// @returns {String} Native target path, or empty text before initialization
function scr_debug_export_last_path()
{
	/* Before the shared target path is initialized, return empty text so callers can query status safely */
	if (!variable_global_exists("debug_export_last_path"))
	{
		return "";
	}

	return string(global.debug_export_last_path);
}

/// @description Shorten a path for error-status display
/// @param {String} raw_path Native path
/// @returns {String} debug_logs suffix when present, otherwise its final filename
function scr_debug_export_display_path(raw_path)
{
	/* path_text uses forward slashes for display, and marker_index is the one-based position of debug_logs or zero when absent */
	var path_text = scr_debug_export_file_url_path(raw_path);
	var marker_index = string_pos("debug_logs", path_text);

	/* When debug_logs occurs in the path, display that marker and its suffix without the preceding directories */
	if (marker_index > 0)
	{
		return string_copy(path_text, marker_index, string_length(path_text) - marker_index + 1);
	}

	/* Zero means no filename boundary has been found yet */
	var slash_index = 0;

	/* Scan the whole path for its final separator when no debug_logs marker was found */
	for (var path_char_index = 1; path_char_index <= string_length(path_text); path_char_index++)
	{
		/* Read the character at this one-based scan position to detect the final path separator */
		var path_char = string_char_at(path_text, path_char_index);

		/* Remember each slash or backslash position so the final match identifies the filename boundary */
		if (path_char == "/" || path_char == "\\")
		{
			slash_index = path_char_index;
		}
	}

	/* A path with no separator has no directory prefix to remove, so keep its text unchanged */
	if (slash_index <= 0)
	{
		return path_text;
	}

	return string_copy(path_text, slash_index + 1, string_length(path_text) - slash_index);
}

/// @description Append the shared error and shortened target to fallback feedback
/// @param {String} fallback Initial feedback text
/// @returns {String} Feedback capped at 130 characters when an error is present
function scr_debug_export_status_text(fallback)
{
	/* Read the shared failure text before deciding whether to extend the caller's fallback */
	var reason = scr_debug_export_last_error();

	/* Without a specific error, return the caller's fallback without an empty reason suffix */
	if (string_trim(reason) == "")
	{
		return string(fallback);
	}

	/* path_text is the optional failed target, and message starts with the fallback plus specific reason */
	var path_text = scr_debug_export_last_path();
	var message = string(fallback) + ": " + reason;

	/* A recorded failure path adds its shortened display form to identify the affected file or folder */
	if (string_trim(path_text) != "")
	{
		message += " (" + scr_debug_export_display_path(path_text) + ")";
	}

	/* Statuses above 130 characters keep the first 127 followed by an ellipsis */
	if (string_length(message) > 130)
	{
		message = string_copy(message, 1, 127) + "...";
	}

	return message;
}

/// @description Read a verified exception message or stringify the thrown value
/// @param {Any} exception_value Struct or other thrown value
/// @returns {String} Readable diagnostic
function scr_debug_export_exception_text(exception_value)
{
	/* Use a message field only after verifying the thrown value is a struct containing that field
	Otherwise stringify the whole value so plain-text throws remain readable */
	return is_struct(exception_value) && variable_struct_exists(exception_value, "message")
		? string(exception_value.message)
		: string(exception_value);
}

/// @description Create the log folder and optionally probe write access
/// @param {Bool} check_write Test writing with a temporary probe file, defaulting to false. The probe is removed after checking
/// @returns {Bool} Whether folder preparation succeeded. Failures populate shared export error state
function scr_debug_export_ensure_folder(check_write = false)
{
	/* Resolve the native debug-log directory once for creation, write probing and any reported failure path */
	var folder_path = scr_debug_export_folder_path();

	/* A blank destination path cannot be created or tested, so record an error and stop */
	if (string_trim(folder_path) == "")
	{
		scr_debug_export_set_error("Debug log folder path is empty.");
		return false;
	}

	try
	{
		/* Request creation when the log directory is absent, then check the result below */
		if (!directory_exists(folder_path))
		{
			directory_create(folder_path);
		}

		/* A directory still absent after creation cannot receive a probe, so report failure before opening one */
		if (!directory_exists(folder_path))
		{
			scr_debug_export_set_error("Debug log folder was not created.", folder_path);
			return false;
		}

		/* Probe write access only when check_write requests it
		Other calls prepare the folder without creating a test file */
		if (check_write)
		{
			/* probe_path identifies the temporary write-access test, and probe_handle owns its text writer until closed */
			var probe_path = scr_debug_export_path_join(folder_path, "_write_test.tmp");
			var probe_handle = file_text_open_write(probe_path);

			/* A failed probe open reports an unwritable folder before any write uses the invalid handle */
			if (probe_handle < 0)
			{
				scr_debug_export_set_error("Debug log folder is not writable.", probe_path);
				return false;
			}

			file_text_write_string(probe_handle, "debug log write test");
			file_text_close(probe_handle);
			probe_handle = -1;

			/* Delete an existing probe after closing it so the write-access check leaves no test file */
			if (file_exists(probe_path))
			{
				file_delete(probe_path);
			}
		}
	}

	/* Folder or probe exceptions populate the shared export error and return failure */
	catch(e)
	{
		scr_debug_export_set_error("Could not prepare debug log folder: " + scr_debug_export_exception_text(e), folder_path);
		return false;
	}

	return true;
}

/// @description Prepare and request the debug-log folder through the shared modal
/// @returns {Real} FolderOpenResult. Records shared errors for creation failure or unsupported platforms
function scr_debug_export_open_folder()
{
	scr_debug_export_clear_error();

	/* folder_path is the native debug-log directory, and open_result is the folder modal's preparation or launch outcome */
	var folder_path = scr_debug_export_folder_path();
	var open_result = scr_open_folder(folder_path, "Debug Logs Folder");

	/* An accepted file-manager launch returns Opened without setting an export error
	It does not confirm that a window appeared */
	if (open_result == FolderOpenResult.Opened)
	{
		return open_result;
	}

	/* FailedToCreate records the folder preparation or game-owned-path rejection in the shared export error */
	if (open_result == FolderOpenResult.FailedToCreate)
	{
		scr_debug_export_set_error("Debug log folder was not created.", folder_path);
	}

	/* Disabled records unsupported folder opening in the shared error
	ManualOpenNeeded keeps the existing path modal without setting an export error */
	else if (open_result == FolderOpenResult.Disabled)
	{
		scr_debug_export_set_error("Opening folders is not available on this platform.", folder_path);
	}

	return open_result;
}

/// @description Append text and a line ending to an already-owned writer
/// @param {Real} file_handle Open text-file handle owned by the caller
/// @param {Any} text Value to convert to text
function scr_debug_export_write_line(file_handle, text)
{
	file_text_write_string(file_handle, string(text));
	file_text_writeln(file_handle);
}
#endregion /* Export Status and Folder Access END */

/// @description Write build, network, drawing and retained debug history to a desktop text file
/// @returns {String} Created file path, or an empty string with shared export error state set
function scr_debug_export_save()
{
	scr_debug_export_clear_error();

	/* Failed folder preparation or write probing returns an empty export path, with the helper's detailed error retained */
	if (!scr_debug_export_ensure_folder(true))
	{
		return "";
	}

	/* filename embeds the local export timestamp, file_path places it beneath debug_logs,
	and file_handle starts at -1 until this export owns a text writer */
	var filename = "JonnilOnline_DebugLog_" + scr_debug_export_timestamp() + ".txt";
	var file_path = scr_debug_export_path_join(scr_debug_export_folder_path(), filename);
	var file_handle = -1;
	try
	{
		file_handle = file_text_open_write(file_path);

		/* A failed debug-log open records its target and returns before writing through an invalid handle */
		if (file_handle < 0)
		{
			scr_debug_export_set_error("file_text_open_write returned -1.", file_path);
			return "";
		}

		scr_debug_export_write_line(file_handle, "Jonnil Online Debug Log");
		scr_debug_export_write_line(file_handle, "Timestamp: " + scr_debug_export_timestamp());
		scr_debug_export_write_line(file_handle, "Build: " + string(scr_get_build_date(true, true)));
		scr_debug_export_write_line(file_handle, "Runtime: " + string(GM_runtime_version));
		scr_debug_export_write_line(file_handle, "Room: " + string(room_get_name(room)) + " " + string(room_width) + "x" + string(room_height));
		scr_debug_export_write_line(file_handle, "IDs: zero-indexed server slots. First joined client is ID0.");
		scr_debug_export_write_line(file_handle, "Verbose: " + string(scr_get_network().verbose));
		scr_debug_export_write_line(file_handle, scr_network_debug_player_map());

		/* Borrow the drawing controller for an optional diagnostic snapshot */
		var drawing = scr_get_drawing();

		/* Check drawing is a struct before looking up debug_export_summary
		Export that method's snapshot only when present, allowing the other diagnostics to be saved without it */
		if (is_struct(drawing)
		&& variable_struct_exists(drawing, "debug_export_summary"))
		{
			scr_debug_export_write_line(file_handle, "");
			scr_debug_export_write_line(file_handle, "[Drawing]");

			/* Keep the copied drawing summary so export traversal uses a stable array of text lines */
			var drawing_lines = drawing.debug_export_summary();

			/* Write every line of the drawing summary in order so the export includes the complete snapshot */
			for (var drawing_line_index = 0; drawing_line_index < array_length(drawing_lines); drawing_line_index++)
			{
				scr_debug_export_write_line(file_handle, drawing_lines[drawing_line_index]);
			}
		}

		scr_debug_export_write_line(file_handle, "");
		scr_debug_export_write_line(file_handle, "[Log Transcript]");

		/* Borrow the debug store for its retained transcript snapshot */
		var debugger = scr_get_debug();

		/* Check debugger is a struct before looking up copy_export_lines
		Copy the retained transcript when present, otherwise leave this section without log lines */
		if (is_struct(debugger)
		&& variable_struct_exists(debugger, "copy_export_lines"))
		{
			/* Copy the retained debug transcript before writing it in message order */
			var lines = debugger.copy_export_lines();

			/* Write every retained debug line in order so the saved transcript preserves the store's message sequence */
			for (var log_line_index = 0; log_line_index < array_length(lines); log_line_index++)
			{
				scr_debug_export_write_line(file_handle, lines[log_line_index]);
			}
		}

		file_text_close(file_handle);
		file_handle = -1;

		/* A destination absent after writing and closing is reported as failure instead of returning a successful path */
		if (!file_exists(file_path))
		{
			scr_debug_export_set_error("Debug log file was not created after writing.", file_path);
			return "";
		}

		scr_debug_export_clear_error();
		debug_success("Saved debug log: " + file_path);
		return file_path;
	}

	/* Release an open destination before recording the export exception and returning an empty path */
	catch(e)
	{
		/* Close a destination handle that remained open when an exception interrupted the export */
		if (file_handle >= 0)
		{
			file_text_close(file_handle);
		}

		scr_debug_export_set_error("Could not save debug log: " + scr_debug_export_exception_text(e), file_path);
		return "";
	}
}

/// @description Write the retained chat transcript to a desktop text file
/// @returns {String} Created file path, or an empty string with shared export error state set
function scr_chat_export_save()
{
	scr_debug_export_clear_error();

	/* Failed folder preparation or write probing returns an empty export path, with the helper's detailed error retained */
	if (!scr_debug_export_ensure_folder(true))
	{
		return "";
	}

	/* filename embeds the local timestamp, file_path places it in debug_logs,
	and file_handle starts at -1 until this operation owns its text writer */
	var filename = "JonnilOnline_ChatLog_" + scr_debug_export_timestamp() + ".txt";
	var file_path = scr_debug_export_path_join(scr_debug_export_folder_path(), filename);
	var file_handle = -1;
	try
	{
		file_handle = file_text_open_write(file_path);

		/* A failed chat-log open records its target and returns before writing through an invalid handle */
		if (file_handle < 0)
		{
			scr_debug_export_set_error("file_text_open_write returned -1.", file_path);
			return "";
		}

		scr_debug_export_write_line(file_handle, "Jonnil Online Chat Log");
		scr_debug_export_write_line(file_handle, "Saved: " + scr_debug_export_timestamp());
		scr_debug_export_write_line(file_handle, "Build: " + string(scr_get_build_date(true, true)));
		scr_debug_export_write_line(file_handle, "Room: " + string(room_get_name(room)) + " " + string(room_width) + "x" + string(room_height));
		scr_debug_export_write_line(file_handle, "Timestamps: local runtime time when each chat message was recorded.");
		scr_debug_export_write_line(file_handle, "");
		scr_debug_export_write_line(file_handle, "[Chat Transcript]");

		/* Borrow the chat store and start lines as an empty fallback until its export method is available */
		var chat = scr_get_chat();
		var lines = [];

		/* Check chat is a struct before looking up copy_export_lines
		Keep the empty fallback array when the method is absent so the transcript can still describe its empty state */
		if (is_struct(chat)
		&& variable_struct_exists(chat, "copy_export_lines"))
		{
			lines = chat.copy_export_lines();
		}

		/* An empty chat snapshot gets an explicit placeholder so readers can distinguish it from an unexplained missing section */
		if (array_length(lines) <= 0)
		{
			scr_debug_export_write_line(file_handle, "(No chat messages recorded.)");
		}

		/* With retained chat lines available, write the transcript instead of the empty-state placeholder */
		else
		{
			/* Visit every copied chat line in order so the export preserves the recorded message sequence */
			for (var chat_line_index = 0; chat_line_index < array_length(lines); chat_line_index++)
			{
				scr_debug_export_write_line(file_handle, lines[chat_line_index]);
			}
		}

		file_text_close(file_handle);
		file_handle = -1;

		/* A destination absent after writing and closing is reported as failure instead of returning a successful path */
		if (!file_exists(file_path))
		{
			scr_debug_export_set_error("Chat log file was not created after writing.", file_path);
			return "";
		}

		scr_debug_export_clear_error();
		debug_success("Saved chat log: " + file_path);
		return file_path;
	}

	/* Close a still-owned destination before recording failure and returning an empty export path */
	catch(e)
	{
		/* Close a destination handle that remained open when an exception interrupted the export */
		if (file_handle >= 0)
		{
			file_text_close(file_handle);
		}

		scr_debug_export_set_error("Could not save chat log: " + scr_debug_export_exception_text(e), file_path);
		return "";
	}
}
