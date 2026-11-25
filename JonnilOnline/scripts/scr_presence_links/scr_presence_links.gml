#region /* Installed Game Join Links */
/// @description Quote one argument for Windows process creation without invoking a shell
/// @param {String} raw_argument One argument, including any embedded quotes
/// @returns {String} A quoted Windows command-line argument
function jonnil_presence_windows_quote_argument(raw_argument)
{
	var argument_text = string(raw_argument);
	var quoted_text = "\"";
	var slash_count = 0;

	/* Backslashes escape quotes only when immediately before a quote or the closing delimiter */
	for (var character_index = 1; character_index <= string_length(argument_text); character_index++)
	{
		var character_text = string_char_at(argument_text, character_index);
		if (character_text == "\\")
		{
			slash_count++;
			continue;
		}

		if (character_text == "\"")
		{
			quoted_text += string_repeat("\\", slash_count * 2 + 1) + character_text;
		}
		else
		{
			quoted_text += string_repeat("\\", slash_count) + character_text;
		}
		slash_count = 0;
	}

	return quoted_text + string_repeat("\\", slash_count * 2) + "\"";
}

/// @description Accept an installed Windows game executable and exclude IDE runners and temporary exports
/// @param {String} raw_path Executable path supplied by the native process extension
/// @returns {Bool} Whether this path can own the installed game's URL handler
function jonnil_presence_join_executable_is_installed(raw_path)
{
	var executable_path = string_replace_all(string(raw_path), "/", "\\");
	var compare_path = string_lower(executable_path);
	var executable_name = string_lower(filename_name(executable_path));

	/* A persistent drive-rooted executable is required because the handler survives this session */
	if (string_length(executable_path) < 8
	|| string_char_at(executable_path, 2) != ":"
	|| string_char_at(executable_path, 3) != "\\"
	|| string_lower(filename_ext(executable_path)) != ".exe"
	|| executable_name == "runner.exe"
	|| executable_name == "gamemaker.exe")
	{
		return false;
	}

	for (var character_index = 1; character_index <= string_length(executable_path); character_index++)
	{
		var character_code = ord(string_char_at(executable_path, character_index));
		if (character_code < 32 || character_code == 34) return false;
	}

	var temporary_parts = ["\\gms2temp\\", "\\gms2cache\\", "\\cache\\runtimes\\", "\\appdata\\local\\temp\\"];
	for (var part_index = 0; part_index < array_length(temporary_parts); part_index++)
	{
		if (string_pos(temporary_parts[part_index], compare_path) > 0) return false;
	}

	/* Reject custom TEMP and TMP locations as well as GameMaker's usual temporary folders */
	var temporary_names = ["TEMP", "TMP"];
	for (var temporary_index = 0; temporary_index < array_length(temporary_names); temporary_index++)
	{
		var temporary_root = string_lower(string_replace_all(EnvironmentGetVariable(temporary_names[temporary_index]), "/", "\\"));
		while (string_length(temporary_root) > 0 && string_char_at(temporary_root, string_length(temporary_root)) == "\\")
		{
			temporary_root = string_delete(temporary_root, string_length(temporary_root), 1);
		}
		if (temporary_root != "" && string_pos(temporary_root + "\\", compare_path) == 1) return false;
	}

	return true;
}

/// @description Run one fixed registry command and retain its output for verification
/// @param {String} executable_path Fully qualified Windows reg.exe path
/// @param {String} arguments_text Arguments constructed only by the join-link registration function
/// @returns {Struct} completed and output. Completion alone does not indicate command success
function jonnil_presence_registry_command(executable_path, arguments_text)
{
	var process_index = -1;
	var command_result = { completed: false, output: "" };
	try
	{
		/* ProcessExecute calls CreateProcess directly and waits, without cmd.exe or PowerShell */
		process_index = ProcessExecute(jonnil_presence_windows_quote_argument(executable_path) + " " + arguments_text);
		if (process_index > 0 && CompletionStatusFromExecutedProcess(process_index))
		{
			command_result.completed = true;
			command_result.output = ExecutedProcessReadFromStandardOutput(process_index);
		}
		if (process_index > 0)
		{
			FreeExecutedProcessStandardInput(process_index);
			FreeExecutedProcessStandardOutput(process_index);
		}
	}
	catch(exception)
	{
		/* A missing process extension or a failed native request leaves registration unconfirmed */
		if (process_index > 0)
		{
			FreeExecutedProcessStandardInput(process_index);
			FreeExecutedProcessStandardOutput(process_index);
		}
	}
	return command_result;
}

/// @description Check the REG_SZ payload from a query for exactly one named registry value
/// @param {Struct} query_result Completion and captured output from reg.exe
/// @param {String} expected_value Exact value that must have been stored
/// @param {Bool} exact_filter Whether reg.exe already applied an exact case-sensitive data filter
/// @returns {Bool} Whether the stored value was confirmed
function jonnil_presence_registry_value_matches(query_result, expected_value, exact_filter)
{
	if (!query_result.completed) return false;
	var output_lines = string_split(string_replace_all(query_result.output, "\r", ""), "\n");
	for (var line_index = 0; line_index < array_length(output_lines); line_index++)
	{
		var output_line = output_lines[line_index];
		var type_position = string_pos("    REG_SZ", output_line);
		if (type_position <= 0) continue;
		/* The native process bridge does not convert legacy stdout code pages to UTF-8
		For a Unicode path, let reg.exe check the data and inspect only its ASCII type marker */
		if (!is_undefined(exact_filter) && exact_filter) return true;
		var stored_value = string_trim(string_delete(output_line, 1, type_position + 9));
		return stored_value == expected_value;
	}
	return false;
}

/// @description Register installed Windows join links only after the player chooses this action
/// @returns {Bool} Whether all stored URL-handler values were read back and confirmed
function jonnil_presence_register_join_links()
{
	if (os_type != os_windows || os_browser != browser_not_a_browser) return false;

	try
	{
		var executable_path = string_replace_all(ExecutableFromSelf(), "/", "\\");
		if (!jonnil_presence_join_executable_is_installed(executable_path)) return false;

		/* Use the operating system's executable through its full path, without searching PATH */
		var windows_root = string_replace_all(EnvironmentGetVariable("SystemRoot"), "/", "\\");
		if (string_length(windows_root) < 3 || string_char_at(windows_root, 2) != ":") return false;
		var registry_executable = windows_root + "\\System32\\reg.exe";
		var protocol_key = "HKCU\\Software\\Classes\\jonnilonline";
		var command_key = protocol_key + "\\shell\\open\\command";
		var protocol_description = "URL:Jonnil Online";
		var launch_command = jonnil_presence_windows_quote_argument(executable_path) + " -join \"%1\"";

		/* Percent-one remains literal because these arguments never pass through a command shell */
		jonnil_presence_registry_command(registry_executable, "add " + jonnil_presence_windows_quote_argument(protocol_key)
			+ " /ve /t REG_SZ /d " + jonnil_presence_windows_quote_argument(protocol_description) + " /f");
		jonnil_presence_registry_command(registry_executable, "add " + jonnil_presence_windows_quote_argument(command_key)
			+ " /ve /t REG_SZ /d " + jonnil_presence_windows_quote_argument(launch_command) + " /f");
		jonnil_presence_registry_command(registry_executable, "add " + jonnil_presence_windows_quote_argument(protocol_key)
			+ " /v \"URL Protocol\" /t REG_SZ /d \"\" /f");

		/* The process API has no exit-code function, so confirm the actual values instead */
		var description_result = jonnil_presence_registry_command(registry_executable,
			"query " + jonnil_presence_windows_quote_argument(protocol_key) + " /ve");
		var command_result = jonnil_presence_registry_command(registry_executable,
			"query " + jonnil_presence_windows_quote_argument(command_key) + " /ve /f "
			+ jonnil_presence_windows_quote_argument(launch_command) + " /d /e /c /t REG_SZ");
		var protocol_result = jonnil_presence_registry_command(registry_executable,
			"query " + jonnil_presence_windows_quote_argument(protocol_key) + " /v \"URL Protocol\"");

		return jonnil_presence_registry_value_matches(description_result, protocol_description)
			&& jonnil_presence_registry_value_matches(command_result, launch_command, true)
			&& jonnil_presence_registry_value_matches(protocol_result, "");
	}
	catch(exception)
	{
		return false;
	}
}
#endregion /* Installed Game Join Links END */

#region /* Existing Instance Join Handoff */
/// @description Allow only the fixed lease or a decimal process mailbox in the game's save area
function jonnil_presence_handoff_filename(file_name)
{
	if (!is_string(file_name)) return false;
	if (file_name == "presence_instance.json") return true;
	if (string_length(file_name) < 19 || string_length(file_name) > 40
	|| string_copy(file_name, string_length(file_name) - 4, 5) != ".json") return false;
	var prefix_length = 0;
	if (string_pos("presence_join_", file_name) == 1) prefix_length = 14;
	else if (string_pos("presence_ack_", file_name) == 1) prefix_length = 13;
	if (prefix_length == 0) return false;
	var process_text = string_copy(file_name, prefix_length + 1, string_length(file_name) - prefix_length - 5);
	if (string_length(process_text) < 1 || string_length(process_text) > 10) return false;
	for (var character_index = 1; character_index <= string_length(process_text); character_index++)
		if (string_pos(string_char_at(process_text, character_index), "0123456789") == 0) return false;
	var process_value = int64(process_text);
	return process_value > 0 && process_value <= 4294967295;
}

/// @description Read at most 2048 bytes from one game-owned presence file before parsing JSON
function jonnil_presence_handoff_read(file_name)
{
	if (!jonnil_presence_handoff_filename(file_name)) return undefined;
	var file_handle = -1;
	var data_buffer = -1;
	try
	{
		if (!file_exists(file_name)) return undefined;
		file_handle = file_bin_open(file_name, 0);
		if (file_handle < 0) return undefined;
		var byte_count = file_bin_size(file_handle);
		if (byte_count <= 0 || byte_count > 2048)
		{
			file_bin_close(file_handle);
			return undefined;
		}
		data_buffer = buffer_create(byte_count + 1, buffer_fixed, 1);
		for (var byte_index = 0; byte_index < byte_count; byte_index++)
			buffer_write(data_buffer, buffer_u8, file_bin_read_byte(file_handle));
		file_bin_close(file_handle);
		file_handle = -1;
		buffer_write(data_buffer, buffer_u8, 0);
		buffer_seek(data_buffer, buffer_seek_start, 0);
		var json_text = buffer_read(data_buffer, buffer_string);
		buffer_delete(data_buffer);
		data_buffer = -1;
		var document = json_parse(json_text);
		return is_struct(document) ? document : undefined;
	}
	catch(read_error)
	{
		if (file_handle >= 0) file_bin_close(file_handle);
		if (data_buffer >= 0) buffer_delete(data_buffer);
		return undefined;
	}
}

/// @description Write one bounded UTF-8 document using only a fixed sandbox filename
function jonnil_presence_handoff_write(file_name, document)
{
	if (!jonnil_presence_handoff_filename(file_name)) return false;
	var file_handle = -1;
	var data_buffer = -1;
	try
	{
		var json_text = json_stringify(document);
		var byte_count = string_byte_length(json_text);
		if (byte_count <= 0 || byte_count > 2048) return false;
		data_buffer = buffer_create(byte_count + 1, buffer_fixed, 1);
		buffer_write(data_buffer, buffer_string, json_text);
		buffer_seek(data_buffer, buffer_seek_start, 0);
		file_handle = file_bin_open(file_name, 1);
		if (file_handle < 0)
		{
			buffer_delete(data_buffer);
			return false;
		}
		for (var byte_index = 0; byte_index < byte_count; byte_index++)
			file_bin_write_byte(file_handle, buffer_read(data_buffer, buffer_u8));
		file_bin_close(file_handle);
		buffer_delete(data_buffer);
		return true;
	}
	catch(write_error)
	{
		if (file_handle >= 0) file_bin_close(file_handle);
		if (data_buffer >= 0) buffer_delete(data_buffer);
		return false;
	}
}

/// @description Check a process identifier without allowing a fractional or out-of-range value
function jonnil_presence_handoff_pid(value)
{
	return is_numeric(value) && value > 0 && value <= 4294967295 && floor(value) == value;
}

/// @description Restrict session and request nonces to bounded decimal identifiers
function jonnil_presence_handoff_nonce(value)
{
	if (!is_string(value) || string_length(value) < 3 || string_length(value) > 80) return false;
	for (var character_index = 1; character_index <= string_length(value); character_index++)
		if (string_pos(string_char_at(value, character_index), "0123456789_") == 0) return false;
	return true;
}

/// @description Forward a public invitation to the same installed game's active Windows instance
function jonnil_presence_handoff() constructor
{
	enabled = false;
	process_id = 0;
	executable_path = "";
	compare_executable = "";
	session_nonce = "";
	lease_file = "presence_instance.json";
	inbox_file = "";
	ack_file = "";
	owner = false;
	waiting = false;
	forward_allowed = false;
	forward_attempted = false;
	forwarded = false;
	request_sequence = 0;
	outgoing_request = undefined;
	received_request = undefined;
	last_received_nonce = "";
	next_poll = 0;
	next_heartbeat = 0;
	lease_absent_since = -1;
	wait_deadline = 0;
	previous_time = current_time;

	valid_header = function(document, expected_kind, now)
	{
		return is_struct(document)
			&& variable_struct_exists(document, "kind") && document.kind == expected_kind
			&& variable_struct_exists(document, "version") && document.version == 1
			&& variable_struct_exists(document, "protocol") && document.protocol == GAMEPLAY_PROTOCOL_VERSION
			&& variable_struct_exists(document, "time") && is_numeric(document.time)
			&& document.time > 0 && document.time <= now + 2 && now - document.time <= 8
			&& variable_struct_exists(document, "exe") && is_string(document.exe)
			&& string_byte_length(document.exe) <= 1024
			&& string_lower(string_replace_all(document.exe, "/", "\\")) == compare_executable
			&& variable_struct_exists(document, "session") && jonnil_presence_handoff_nonce(document.session);
	}

	live_process = function(candidate_pid)
	{
		if (!jonnil_presence_handoff_pid(candidate_pid) || !ProcIdExists(candidate_pid)) return false;
		var candidate_executable = string_lower(string_replace_all(ExeFromProcId(candidate_pid), "/", "\\"));
		return candidate_executable == compare_executable;
	}

	valid_lease = function(document, now)
	{
		return valid_header(document, "lease", now)
			&& variable_struct_exists(document, "pid") && live_process(document.pid);
	}

	valid_request = function(document, expected_kind, now)
	{
		return valid_header(document, expected_kind, now)
			&& variable_struct_exists(document, "source_pid") && jonnil_presence_handoff_pid(document.source_pid)
			&& variable_struct_exists(document, "target_pid") && jonnil_presence_handoff_pid(document.target_pid)
			&& variable_struct_exists(document, "nonce") && jonnil_presence_handoff_nonce(document.nonce)
			&& variable_struct_exists(document, "target") && jonnil_presence_public_join_protocol(document.target) > 0;
	}

	write_lease = function(now)
	{
		var lease = { kind: "lease", version: 1, protocol: GAMEPLAY_PROTOCOL_VERSION,
			pid: process_id, exe: executable_path, time: now, session: session_nonce };
		if (!jonnil_presence_handoff_write(lease_file, lease)) return false;
		var saved_lease = jonnil_presence_handoff_read(lease_file);
		return is_struct(saved_lease) && variable_struct_exists(saved_lease, "pid")
			&& saved_lease.pid == process_id && variable_struct_exists(saved_lease, "session")
			&& saved_lease.session == session_nonce;
	}

	/// @description Acknowledge only after the controller accepts the received public invitation
	acknowledge_received = function()
	{
		if (!enabled || !is_struct(received_request)) return false;
		var request = received_request;
		var acknowledgement = { kind: "ack", version: 1, protocol: GAMEPLAY_PROTOCOL_VERSION,
			source_pid: request.source_pid, target_pid: process_id, exe: executable_path,
			time: jonnil_presence_unix_time(), session: session_nonce, nonce: request.nonce, target: request.target };
		var target_ack_file = "presence_ack_" + string(request.source_pid) + ".json";
		if (!jonnil_presence_handoff_write(target_ack_file, acknowledgement)) return false;
		var saved_ack = jonnil_presence_handoff_read(target_ack_file);
		if (!is_struct(saved_ack) || !variable_struct_exists(saved_ack, "nonce") || saved_ack.nonce != request.nonce) return false;
		last_received_nonce = request.nonce;
		var saved_request = jonnil_presence_handoff_read(inbox_file);
		if (is_struct(saved_request) && variable_struct_exists(saved_request, "nonce") && saved_request.nonce == request.nonce)
			file_delete(inbox_file);
		received_request = undefined;
		return true;
	}

	/// @description Poll and heartbeat without waiting. A confirmed acknowledgement is the only forwarded result
	update = function(pending_join)
	{
		var handoff_result = { received_target: "", forwarded: false, waiting: waiting };
		if (!enabled || forwarded) return handoff_result;
		/* Forwarding belongs only to the original URI launch, never to a later invitation */
		if (pending_join == "")
		{
			forward_allowed = false;
			forward_attempted = false;
			waiting = false;
			handoff_result.waiting = false;
		}
		if (current_time < previous_time)
		{
			next_poll = 0;
			next_heartbeat = 0;
			lease_absent_since = -1;
			if (waiting) wait_deadline = current_time + 3000;
		}
		previous_time = current_time;
		if (current_time < next_poll) return handoff_result;
		next_poll = current_time + 500;
		try
		{
			var now = jonnil_presence_unix_time();
			var lease = jonnil_presence_handoff_read(lease_file);
			var fresh_lease = valid_lease(lease, now);
			owner = fresh_lease && lease.pid == process_id && lease.session == session_nonce;
			if (fresh_lease) lease_absent_since = -1;
			else if (lease_absent_since < 0) lease_absent_since = current_time;

			if (waiting)
			{
				var acknowledgement = jonnil_presence_handoff_read(ack_file);
				if (valid_request(acknowledgement, "ack", now)
				&& acknowledgement.source_pid == process_id
				&& acknowledgement.target_pid == outgoing_request.target_pid
				&& acknowledgement.session == outgoing_request.session
				&& acknowledgement.nonce == outgoing_request.nonce
				&& live_process(acknowledgement.target_pid))
				{
					waiting = false;
					forwarded = true;
					handoff_result.forwarded = true;
					handoff_result.waiting = false;
					return handoff_result;
				}
				if (current_time >= wait_deadline) waiting = false;
				handoff_result.waiting = waiting;
				return handoff_result;
			}

			if (!fresh_lease && current_time - lease_absent_since >= 1500)
			{
				owner = write_lease(now);
				lease_absent_since = current_time;
				next_heartbeat = current_time + 2000;
			}
			if (owner)
			{
				if (current_time >= next_heartbeat)
				{
					write_lease(now);
					next_heartbeat = current_time + 2000;
				}
				var incoming_request = jonnil_presence_handoff_read(inbox_file);
				if (valid_request(incoming_request, "join", now)
				&& incoming_request.target_pid == process_id && incoming_request.session == session_nonce
				&& incoming_request.source_pid != process_id && live_process(incoming_request.source_pid))
				{
					received_request = incoming_request;
					if (incoming_request.nonce == last_received_nonce) acknowledge_received();
					else handoff_result.received_target = incoming_request.target;
				}
			}
			else if (fresh_lease && forward_allowed && pending_join == "public" && !forward_attempted)
			{
				forward_attempted = true;
				request_sequence++;
				outgoing_request = { kind: "join", version: 1, protocol: GAMEPLAY_PROTOCOL_VERSION,
					source_pid: process_id, target_pid: lease.pid, exe: executable_path, time: now,
					session: lease.session, nonce: session_nonce + "_" + string(request_sequence),
					target: "jo1:public:" + string(GAMEPLAY_PROTOCOL_VERSION) };
				var target_inbox_file = "presence_join_" + string(lease.pid) + ".json";
				if (jonnil_presence_handoff_write(target_inbox_file, outgoing_request))
				{
					var saved_request = jonnil_presence_handoff_read(target_inbox_file);
					waiting = is_struct(saved_request) && variable_struct_exists(saved_request, "nonce")
						&& saved_request.nonce == outgoing_request.nonce;
					if (waiting) wait_deadline = current_time + 3000;
				}
				handoff_result.waiting = waiting;
			}
		}
		catch(handoff_error)
		{
			/* Failure keeps the invitation in this instance instead of closing an unconfirmed launch */
			waiting = false;
			handoff_result.waiting = false;
		}
		return handoff_result;
	}

	/// @description Remove only this process's lease and its matching request or acknowledgement
	close = function()
	{
		if (!enabled) return;
		try
		{
			var lease = jonnil_presence_handoff_read(lease_file);
			if (is_struct(lease) && variable_struct_exists(lease, "pid") && lease.pid == process_id
			&& variable_struct_exists(lease, "session") && lease.session == session_nonce) file_delete(lease_file);
			var incoming_request = jonnil_presence_handoff_read(inbox_file);
			if (is_struct(incoming_request) && variable_struct_exists(incoming_request, "target_pid")
			&& incoming_request.target_pid == process_id && variable_struct_exists(incoming_request, "session")
			&& incoming_request.session == session_nonce) file_delete(inbox_file);
			if (is_struct(outgoing_request))
			{
				var target_inbox_file = "presence_join_" + string(outgoing_request.target_pid) + ".json";
				var request = jonnil_presence_handoff_read(target_inbox_file);
				if (is_struct(request) && variable_struct_exists(request, "nonce")
				&& request.nonce == outgoing_request.nonce) file_delete(target_inbox_file);
				var acknowledgement = jonnil_presence_handoff_read(ack_file);
				if (is_struct(acknowledgement) && variable_struct_exists(acknowledgement, "nonce")
				&& acknowledgement.nonce == outgoing_request.nonce) file_delete(ack_file);
			}
		}
		catch(close_error) { }
		enabled = false;
		waiting = false;
	}

	/* A normal IDE runner can exchange invitations with another runner using this game's save area
	URL-handler registration still excludes the runner and remains a separate explicit action */
	if (os_type == os_windows && os_browser == browser_not_a_browser)
	{
		try
		{
			process_id = ProcIdFromSelf();
			executable_path = string_replace_all(ExecutableFromSelf(), "/", "\\");
			compare_executable = string_lower(executable_path);
			enabled = jonnil_presence_handoff_pid(process_id) && executable_path != ""
				&& string_byte_length(executable_path) <= 1024;
			if (enabled)
			{
				session_nonce = string(process_id) + "_" + string(int64(get_timer()));
				inbox_file = "presence_join_" + string(process_id) + ".json";
				ack_file = "presence_ack_" + string(process_id) + ".json";
			}
		}
		catch(identity_error) { enabled = false; }
	}
}
#endregion /* Existing Instance Join Handoff END */
