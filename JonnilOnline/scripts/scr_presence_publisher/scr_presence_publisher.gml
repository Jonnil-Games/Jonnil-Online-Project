/// @description Publish one optional Discord channel message from the trusted game server
function scr_presence_publisher() constructor
{
	/* Only an active native server reads the environment. No webhook credential is
	stored in a game asset, client setting, message, or diagnostic */
	initialized = false;
	session_active = false;
	enabled = false;
	webhook_url = "";
	message_id = "";
	create_pending = false;
	settings_file = "server_settings.ini";
	status_text = "Discord channel status is disabled.";
	request_id = -1;
	request_is_create = false;
	request_deadline = 0;
	request_timed_out = false;
	request_oversize = false;
	request_fingerprint = "";
	request_settings_file = "";
	last_fingerprint = "";
	last_success_at = 0;
	previous_update_at = 0;
	next_attempt_at = 0;
	failure_count = 0;
	minimum_interval_ms = 15000;
	heartbeat_interval_ms = 60000;
	request_timeout_ms = 15000;
	maximum_response_bytes = 16384;

	/// @description Validate a snowflake without converting its exact digits to a real
	is_message_id = function(value)
	{
		if (!is_string(value) || string_length(value) < 17 || string_length(value) > 22) return false;
		for (var i = 1; i <= string_length(value); i++)
		{
			if (string_pos(string_char_at(value, i), "0123456789") == 0) return false;
		}
		return true;
	}

	/// @description Accept only Discord's HTTPS incoming-webhook routes and token alphabet
	valid_webhook_url = function(value)
	{
		if (!is_string(value) || string_length(value) > 512) return false;
		var prefix = "https://discord.com/api/webhooks/";
		if (string_copy(value, 1, string_length(prefix)) != prefix)
		{
			prefix = "https://discord.com/api/v10/webhooks/";
			if (string_copy(value, 1, string_length(prefix)) != prefix) return false;
		}
		var path = string_delete(value, 1, string_length(prefix));
		var separator = string_pos("/", path);
		if (separator <= 1) return false;
		if (!is_message_id(string_copy(path, 1, separator - 1))) return false;
		var token = string_delete(path, 1, separator);
		if (string_length(token) < 32 || string_length(token) > 256) return false;
		for (var i = 1; i <= string_length(token); i++)
		{
			if (string_pos(string_char_at(token, i), "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.") == 0) return false;
		}
		return true;
	}

	/// @description Read optional server-only configuration once per hosting session
	load_configuration = function(server_state)
	{
		initialized = true;
		enabled = false;
		message_id = "";
		create_pending = false;
		last_fingerprint = "";
		last_success_at = 0;
		failure_count = 0;
		next_attempt_at = max(next_attempt_at, current_time);
		settings_file = server_state.lifecycle_settings_file;
		webhook_url = string_trim(string(environment_get_variable("JONNIL_DISCORD_STATUS_WEBHOOK")));
		if (webhook_url == "")
		{
			status_text = "Discord channel status is disabled. No server webhook is configured.";
			return false;
		}
		if (!valid_webhook_url(webhook_url))
		{
			webhook_url = "";
			status_text = "Discord channel status has an invalid server webhook configuration.";
			debug_error(status_text);
			return false;
		}
		scr_server_logs_protect_secret(webhook_url);
		var token_start = string_length(webhook_url);
		while (token_start > 0 && string_char_at(webhook_url, token_start) != "/") token_start--;
		scr_server_logs_protect_secret(string_delete(webhook_url, 1, token_start));
		try
		{
			if (file_exists(settings_file))
			{
				ini_open(settings_file);
				var saved_id = ini_read_string("presence", "discord_message_id", "");
				create_pending = ini_read_real("presence", "discord_create_pending", 0) != 0;
				ini_close();
				if (saved_id != "" && !is_message_id(saved_id))
				{
					status_text = "Discord channel status has an invalid saved message ID.";
					debug_error(status_text);
					return false;
				}
				message_id = saved_id;
				if (message_id == "" && create_pending)
				{
					status_text = "A previous Discord status message creation wasn't confirmed. Check the channel, then set discord_message_id or clear discord_create_pending before restarting publishing.";
					debug_error(status_text);
					return false;
				}
			}
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) { }
			status_text = "Discord channel status couldn't read its server settings.";
			debug_error(status_text);
			return false;
		}
		enabled = true;
		status_text = "Discord channel status is ready.";
		return true;
	}

	/// @description Keep the returned message ID so later updates edit the same message
	save_message_id = function(value, target_file)
	{
		try
		{
			ini_open(target_file);
			ini_write_string("presence", "discord_message_id", value);
			ini_write_real("presence", "discord_create_pending", 0);
			ini_close();
			create_pending = false;
			return true;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) { }
			debug_error("Discord channel status couldn't save its message ID. The pending-create marker prevents another create after restart.");
			return false;
		}
	}

	/// @description Reserve message creation on disk before sending a non-idempotent POST
	mark_create_pending = function()
	{
		try
		{
			ini_open(settings_file);
			ini_write_real("presence", "discord_create_pending", 1);
			ini_close();
			create_pending = true;
			return true;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) { }
			enabled = false;
			status_text = "Discord channel status couldn't save its pending-create marker. No message was sent.";
			debug_error(status_text);
			return false;
		}
	}

	/// @description Capture a Discord timestamp without changing the game's date settings
	unix_timestamp = function()
	{
		var previous_zone = date_get_timezone();
		date_set_timezone(timezone_utc);
		var epoch = date_create_datetime(1970, 1, 1, 0, 0, 0);
		var now = date_current_datetime();
		date_set_timezone(previous_zone);
		return floor(date_second_span(epoch, now));
	}

	/// @description Fit the approved transient roster into Discord's 2,000-character limit
	build_content = function(snapshot)
	{
		var text = snapshot.server_name + "\nReported players: " + string(snapshot.players)
			+ "/" + string(snapshot.max_players)
			+ "\nJoining: " + (snapshot.joinable ? "available" : "unavailable");
		var names = "";
		var shown = 0;
		for (var i = 0; i < array_length(snapshot.roster); i++)
		{
			var player = snapshot.roster[i];
			var label = string_replace_all(player.name, "_", "\\_") + (player.afk ? " (AFK)" : "");
			var candidate = names + (names == "" ? "" : ", ") + label;
			if (string_length(candidate) > 1100) break;
			names = candidate;
			shown++;
		}
		text += "\nPublic names: " + (names == "" ? "none shared" : names);
		if (shown < array_length(snapshot.roster)) text += "\nMore shared names are on the online page.";
		var unnamed = max(0, snapshot.players - snapshot.published_names);
		if (unnamed > 0) text += "\nPlayers without a public name: " + string(unnamed);
		var timestamp = string(unix_timestamp());
		text += "\nLast server update: <t:" + timestamp + ":F> (<t:" + timestamp + ":R>)"
			+ "\nTreat this report as unavailable if the update is over 2 minutes old.";
		if (variable_struct_exists(snapshot, "server_key") && snapshot.server_key == "public")
		{
			text += "\nCheck status or join: https://online.jonnil.games/online";
		}
		return text;
	}

	/// @description Back off failed edits without recording response bodies or credentials
	note_failure = function(http_code)
	{
		failure_count = min(failure_count + 1, 5);
		var delay = min(300000, 15000 * power(2, failure_count));
		next_attempt_at = max(next_attempt_at, current_time + delay);
		status_text = "Discord channel status update failed. Retrying later. HTTP " + string(http_code) + ".";
		debug_error(status_text);
	}

	/// @description Read a bounded rate-limit delay, preferring Discord's JSON retry_after
	retry_seconds = function(event_map, parsed_body)
	{
		if (is_struct(parsed_body) && variable_struct_exists(parsed_body, "retry_after")
		&& is_real(parsed_body.retry_after) && parsed_body.retry_after > 0) return parsed_body.retry_after;
		if (ds_map_exists(event_map, "response_headers"))
		{
			var headers = event_map[? "response_headers"];
			if (is_real(headers) && ds_exists(headers, ds_type_map))
			{
				var key = ds_map_find_first(headers);
				for (var i = 0; i < 64 && !is_undefined(key); i++)
				{
					if (string_lower(string(key)) == "retry-after")
					{
						var raw = headers[? key];
						if (is_string(raw) && string_length(raw) <= 16)
						{
							try { var seconds = real(raw); if (seconds > 0) return seconds; } catch(e) { }
						}
					}
					key = ds_map_find_next(headers, key);
				}
			}
		}
		return 60;
	}

	/// @description Maintain one in-flight request, coalescing changes and periodic refreshes
	update = function(server_state = undefined)
	{
		if (current_time < previous_update_at)
		{
			next_attempt_at = 0;
			last_success_at = 0;
			if (request_id >= 0) request_deadline = current_time + request_timeout_ms;
		}
		previous_update_at = current_time;
		if (is_undefined(server_state)) server_state = scr_get_server();
		var active = os_browser == browser_not_a_browser && is_struct(server_state)
			&& server_state.is_running() && server_state.public_presence_enabled;
		if (request_id >= 0 && !request_timed_out && current_time >= request_deadline)
		{
			request_timed_out = true;
			status_text = "Discord channel status request timed out. Waiting for its final result.";
			debug_error(status_text);
			/* GameMaker has no per-request cancellation. Keep ownership until completion
			so a late create cannot overlap another POST and leave duplicate messages */
		}
		if (!active)
		{
			session_active = false;
			initialized = false;
			enabled = false;
			webhook_url = "";
			return;
		}
		if (!session_active)
		{
			session_active = true;
			initialized = false;
		}
		if (request_id >= 0) return;
		if (!initialized) load_configuration(server_state);
		if (!enabled || current_time < next_attempt_at) return;
		var snapshot = server_state.get_public_presence_snapshot();
		var fingerprint = json_stringify(snapshot);
		if (fingerprint == last_fingerprint && current_time >= last_success_at
		&& current_time - last_success_at < heartbeat_interval_ms) return;
		var content = build_content(snapshot);
		if (string_length(content) > 1900)
		{
			enabled = false;
			status_text = "Discord channel status message exceeded its size limit.";
			debug_error(status_text);
			return;
		}
		var payload = json_stringify({ content: content, allowed_mentions: { parse: [] } });
		request_is_create = message_id == "";
		if (request_is_create && !mark_create_pending()) return;
		var headers = ds_map_create();
		headers[? "Content-Type"] = "application/json";
		var target = webhook_url + (request_is_create ? "?wait=true" : "/messages/" + message_id);
		var request_method = request_is_create ? "POST" : "PATCH";
		request_fingerprint = fingerprint;
		request_settings_file = settings_file;
		request_timed_out = false;
		request_oversize = false;
		request_deadline = current_time + request_timeout_ms;
		next_attempt_at = current_time + minimum_interval_ms;
		try { request_id = http_request(target, request_method, headers, payload); }
		catch(e) { request_id = -1; }
		ds_map_destroy(headers);
		if (request_id < 0)
		{
			if (request_is_create && !save_message_id("", settings_file)) enabled = false;
			note_failure(0);
		}
		else status_text = "Discord channel status update is pending.";
	}

	/// @description Consume only this publisher's HTTP events and bound all JSON parsing
	handle_http = function(event_map)
	{
		if (request_id < 0 || !ds_map_exists(event_map, "id")
		|| event_map[? "id"] != request_id) return false;
		var completion = ds_map_exists(event_map, "status") ? event_map[? "status"] : -1;
		if (ds_map_exists(event_map, "contentLength") && event_map[? "contentLength"] > maximum_response_bytes) request_oversize = true;
		if (ds_map_exists(event_map, "sizeDownloaded") && event_map[? "sizeDownloaded"] > maximum_response_bytes) request_oversize = true;
		if (completion > 0) return true;
		request_id = -1;
		var http_code = ds_map_exists(event_map, "http_status") ? event_map[? "http_status"] : 0;
		var parsed = undefined;
		if (!request_oversize && (request_is_create || http_code == 429)
		&& ds_map_exists(event_map, "result"))
		{
			var body = event_map[? "result"];
			if (is_string(body) && string_byte_length(body) <= maximum_response_bytes)
			{
				try { parsed = json_parse(body); } catch(e) { }
			}
		}
		if (completion == 0 && http_code >= 200 && http_code < 300)
		{
			if (request_is_create)
			{
				if (!is_struct(parsed) || !variable_struct_exists(parsed, "id") || !is_message_id(parsed.id))
				{
					enabled = false;
					status_text = "Discord created a status message but returned no usable ID. Set discord_message_id before restarting publishing.";
					debug_error(status_text);
					return true;
				}
				message_id = parsed.id;
				save_message_id(message_id, request_settings_file);
			}
			else if (create_pending) save_message_id(message_id, request_settings_file);
			last_fingerprint = request_fingerprint;
			last_success_at = current_time;
			failure_count = 0;
			status_text = "Discord channel status was updated.";
			return true;
		}
		if (http_code == 429)
		{
			if (request_is_create && !save_message_id("", request_settings_file)) enabled = false;
			var seconds = retry_seconds(event_map, parsed);
			if (seconds > 3600)
			{
				enabled = false;
				status_text = "Discord channel status is paused by a long rate limit. Restart publishing after the limit expires.";
			}
			else
			{
				next_attempt_at = max(next_attempt_at, current_time + max(15000, ceil(seconds * 1000)));
				status_text = "Discord channel status is waiting for its rate limit to expire.";
			}
			debug_error(status_text);
			return true;
		}
		if (http_code == 404 && !request_is_create)
		{
			/* A deleted saved message may be replaced once. An invalid webhook then
			fails its create and disables publishing instead of producing a retry loop */
			message_id = "";
			save_message_id("", request_settings_file);
			next_attempt_at = max(next_attempt_at, current_time + minimum_interval_ms);
			status_text = "Discord status message was removed. A replacement is queued.";
			debug_error(status_text);
			return true;
		}
		if (http_code >= 400 && http_code < 500)
		{
			if (request_is_create) save_message_id("", request_settings_file);
			enabled = false;
			status_text = "Discord channel status was rejected. Check the server webhook and channel permissions. HTTP " + string(http_code) + ".";
			debug_error(status_text);
			return true;
		}
		if (request_is_create)
		{
			/* Retrying an unconfirmed POST could create another permanent message */
			enabled = false;
			status_text = "Discord status message creation wasn't confirmed. Check the channel and set discord_message_id before restarting publishing.";
			debug_error(status_text);
			return true;
		}
		note_failure(http_code);
		return true;
	}
}
