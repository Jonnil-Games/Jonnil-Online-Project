/// @description Own optional HTTPS sign-in and account-owned cloud profile requests
function scr_accounts() constructor
{
	configured = false;
	browser_target = os_browser != browser_not_a_browser;
	browser_page_unsupported = false;
	browser_authorized = false;
	browser_cookie_proof = undefined;
	browser_restore_storage_ok = true;
	supported_target = browser_target || os_type == os_windows;
	availability_message = "";
	busy = false;
	state = "guest";
	status_text = "Playing as guest.";
	account_id = "";
	account_username = "";
	recovery_code = "";
	export_data = "";
	cloud_profile = undefined;
	profile_loaded = false;
	conflict = false;
	session_generation = 0;
	completion_serial = 0;
	last_operation = "";
	last_success = false;
	last_http_status = 0;
	uncertain_result = false;
	base_url = "";
	access_token = "";
	token_deadline = 0;
	session_mode = "session";
	request_id = noone;
	request_kind = "";
	request_generation = 0;
	request_owner = "";
	request_deadline = 0;
	retired_requests = [];
	request_timeout_ms = 20000;
	keep_signed_in = false;
	remember_duration = "30_days";
	login_session_mode = "session";
	remembered_on_device = false;
	vault_available = false;
	vault_target = "";
	vault_status = "";
	vault_cleanup_failed = false;
	device_preferences_file = "account_device.ini";
	login_remember_choice = false;
	restore_pending = false;
	restore_failed = false;
	restore_retry_available = false;
	restore_status = "";
	restore_candidate = "";
	restored_identity = undefined;

	clock_ms = function() { return get_timer() / 1000; }

	builtin_character = function(key) { return jonnil_account_builtin_character(key); }
	builtin_pet = function(key) { return jonnil_account_builtin_pet(key); }

	valid_account_id = function(value)
	{
		if (!is_string(value) || string_length(value) != 36) return false;
		for (var i = 1; i <= 36; i++)
		{
			var character = string_char_at(value, i);
			if (i == 9 || i == 14 || i == 19 || i == 24)
			{
				if (character != "-") return false;
			}
			else if (string_pos(character, "0123456789abcdef") == 0) return false;
		}
		return true;
	}

	signed_in = function()
	{
		return account_id != "" && (browser_target ? browser_authorized : access_token != "") && !session_expired();
	}

	/// @description Apply a local timer only to a verified timed session
	session_expired = function()
	{
		return session_mode != "until_sign_out" && clock_ms() >= token_deadline;
	}

	set_remember_duration = function(mode)
	{
		if (!is_string(mode) || (mode != "30_days" && mode != "until_sign_out") || busy || signed_in()) return false;
		remember_duration = mode;
		return true;
	}

	/// @description Infer legacy replies only as timed sessions, never as unlimited sign-in
	reply_session_mode = function(result)
	{
		if (!is_struct(result)) return "";
		if (variable_struct_exists(result, "session_mode"))
		{
			var mode = result.session_mode;
			return is_string(mode) && (mode == "session" || mode == "30_days" || mode == "until_sign_out") ? mode : "";
		}
		if (!variable_struct_exists(result, "remember_me") || !is_bool(result.remember_me)) return "";
		return result.remember_me ? "30_days" : "session";
	}

	valid_session_token = function(value)
	{
		if (!is_string(value) || string_length(value) != 32) return false;
		for (var i = 1; i <= 32; i++)
			if (string_pos(string_char_at(value, i), "abcdefghijklmnopqrstuvwxyz0123456789") == 0) return false;
		return true;
	}

	account_status_label = function()
	{
		if (is_struct(restored_identity)) return "Account: Ready in main menu";
		if (restore_pending) return "Account: Checking sign-in...";
		if (signed_in()) return "Signed in as " + account_username;
		if (restore_failed && remembered_on_device) return "Account: Sign-in paused";
		if (state == "expired") return "Account: Sign-in needed";
		return "Account: Guest";
	}

	write_device_preference = function(enabled)
	{
		if (browser_target) return true;
		try
		{
			ini_open(device_preferences_file);
			ini_write_real("account", "keep_signed_in", enabled ? 1 : 0);
			ini_write_string("account", "remember_duration", remember_duration);
			ini_close();
			return true;
		}
		catch(preference_error)
		{
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Forget this device's saved sign-in while leaving an active in-memory session available
	forget_saved_sign_in = function()
	{
		if (busy && request_kind == "restore_session")
		{
			retire_request();
			session_generation++;
		}
		keep_signed_in = false;
		remembered_on_device = false;
		restore_pending = false;
		restore_failed = false;
		restore_retry_available = false;
		restore_candidate = "";
		restored_identity = undefined;
		restore_status = "";
		var preference_removed = write_device_preference(false);
		var credential_removed = true;
		if (!browser_target && vault_available && vault_target != "")
		{
			try { credential_removed = jonnil_vault_delete(vault_target) == 1; }
			catch(vault_error) { credential_removed = false; }
		}
		vault_cleanup_failed = !preference_removed || !credential_removed;
		vault_status = !vault_cleanup_failed ? ""
			: "Saved sign-in was disabled, but this device could not remove all saved sign-in data.";
		return preference_removed && credential_removed;
	}

	set_keep_signed_in = function(enabled)
	{
		if (!is_bool(enabled)) return false;
		if (browser_target)
		{
			if (busy || signed_in()) return false;
			keep_signed_in = enabled;
			return true;
		}
		if (!enabled) return forget_saved_sign_in();
		if (!vault_available)
		{
			keep_signed_in = false;
			vault_status = "Windows protected sign-in storage is unavailable. You can still sign in for this session.";
			return false;
		}
		if (signed_in()) return remembered_on_device || remember_current_session();
		keep_signed_in = true;
		vault_status = "";
		return true;
	}

	stop_remembering = function()
	{
		if (!browser_target) return forget_saved_sign_in();
		if (!start_request("browser_forget", "/accounts/v1/forget", {}, true)) return false;
		status_text = "Changing browser sign-in to this session...";
		return true;
	}

	remember_current_session = function()
	{
		if (browser_target || !vault_available || !valid_session_token(access_token) || session_expired()) return false;
		var written = false;
		try { written = jonnil_vault_write(vault_target, access_token) == 1; } catch(vault_error) {}
		if (written && write_device_preference(true))
		{
			keep_signed_in = true;
			remembered_on_device = true;
			vault_cleanup_failed = false;
			vault_status = session_mode == "until_sign_out"
				? "Your sign-in is remembered on this Windows device until you sign out."
				: "Your current sign-in is remembered on this Windows device until its original expiry.";
			return true;
		}
		forget_saved_sign_in();
		vault_status = "Signed in for this session. This device could not save a protected sign-in.";
		return false;
	}

	valid_session_reply = function(result, needs_token)
	{
		if (!is_struct(result) || !variable_struct_exists(result, "user") || !is_struct(result.user)
		|| !variable_struct_exists(result.user, "id") || !valid_account_id(result.user.id)
		|| !variable_struct_exists(result.user, "username") || !valid_username(result.user.username)
		|| !variable_struct_exists(result, "remember_me") || !is_bool(result.remember_me)
		|| !variable_struct_exists(result, "expires_in")) return false;
		var mode = reply_session_mode(result);
		if (mode == "" || result.remember_me != (mode != "session")) return false;
		if (mode == "until_sign_out")
		{
			/* JSON null becomes undefined. Missing fields and numeric or string substitutes are rejected */
			if (!variable_struct_exists(result, "session_mode") || !is_undefined(result.expires_in)) return false;
		}
		else if (!is_real(result.expires_in)
		|| !(result.expires_in > 5 && result.expires_in <= (mode == "30_days" ? 2592000 : 43200))) return false;
		if (needs_token && (!variable_struct_exists(result, "access_token") || !valid_session_token(result.access_token))) return false;
		if (browser_target && variable_struct_exists(result, "access_token")) return false;
		return true;
	}

	/// @description Verify a saved credential before assigning account identity or profile ownership
	restore_retry = function()
	{
		if (!configured || busy || signed_in()) return false;
		if (browser_target)
		{
			if (html5_accounts_restore_allowed(base_url + "/accounts/v1") != 1) return false;
			restore_pending = true;
			restore_failed = false;
			remembered_on_device = true;
			restore_status = "Checking browser sign-in...";
			if (start_request("restore_session", "/accounts/v1/session", {}, false, "GET")) return true;
			restore_pending = false;
			restore_failed = true;
			restore_retry_available = true;
			restore_status = "Could not check browser sign-in. Retry when connected. Guest play is available.";
			return false;
		}
		if (!vault_available || !keep_signed_in) return false;
		var candidate = "";
		var native_error = 0;
		try
		{
			candidate = jonnil_vault_read(vault_target);
			native_error = jonnil_vault_last_error();
		}
		catch(vault_error) { native_error = -1; }
		if (!valid_session_token(candidate))
		{
			if (native_error == 0 || native_error == 13 || native_error == 1168)
			{
				forget_saved_sign_in();
				restore_failed = true;
				restore_status = native_error == 1168 ? "No saved sign-in was found. Sign in again."
					: "The saved sign-in was invalid and has been removed. Sign in again.";
			}
			else
			{
				remembered_on_device = true;
				restore_failed = true;
				restore_retry_available = true;
				restore_status = "Windows could not open the saved sign-in. Retry, sign in with your password, or continue as guest.";
			}
			return false;
		}
		restore_candidate = candidate;
		restored_identity = undefined;
		remembered_on_device = true;
		restore_pending = true;
		restore_failed = false;
		restore_retry_available = false;
		restore_status = "Checking your saved sign-in...";
		if (!start_request("restore_session", "/accounts/v1/session", {}, true, "GET", candidate))
		{
			restore_pending = false;
			restore_failed = true;
			restore_retry_available = true;
			restore_status = "Could not check your saved sign-in. Retry when connected. Guest play is available.";
			return false;
		}
		return true;
	}

	/// @description Pause saved sign-in for guest play without forgetting this device's protected credential
	pause_restore_for_guest = function()
	{
		/* This action cannot change an active or expired account's profile ownership */
		if (account_id != "" || access_token != "" || (busy && request_kind != "restore_session")) return false;
		if (busy && request_kind == "restore_session") retire_request();
		session_generation++;
		restore_candidate = "";
		restored_identity = undefined;
		restore_pending = false;
		restore_failed = remembered_on_device && keep_signed_in;
		restore_retry_available = restore_failed;
		restore_status = restore_failed
			? "Saved sign-in is paused. You can play as a guest. Open Account to retry when connected."
			: "Playing as guest.";
		state = "guest";
		complete("pause_restore", true, restore_status);
		return true;
	}

	/// @description Activate a verified identity only when the account menu controller is safely in the main menu
	activate_restored = function()
	{
		if (!is_struct(restored_identity) || busy || signed_in()) return false;
		if (restored_identity.mode != "until_sign_out" && clock_ms() >= restored_identity.deadline)
		{
			forget_saved_sign_in();
			restore_status = "Saved sign-in expired. Sign in again.";
			return false;
		}
		retire_request();
		session_generation++;
		account_id = restored_identity.id;
		account_username = restored_identity.username;
		access_token = browser_target ? "" : restored_identity.token;
		browser_authorized = browser_target;
		token_deadline = restored_identity.deadline;
		session_mode = restored_identity.mode;
		if (browser_target)
		{
			keep_signed_in = session_mode != "session";
			remembered_on_device = keep_signed_in;
		}
		if (session_mode != "session") remember_duration = session_mode;
		cloud_profile = undefined;
		profile_loaded = false;
		conflict = false;
		state = "signed_in";
		restored_identity = undefined;
		restore_candidate = "";
		restore_pending = false;
		restore_failed = false;
		restore_retry_available = false;
		restore_status = "Saved sign-in restored.";
		complete("restore_session", true, "Signed in.");
		load_profile();
		return true;
	}

	complete = function(kind, success, message)
	{
		uncertain_result = false;
		last_operation = kind;
		last_success = success;
		status_text = message;
		completion_serial++;
	}

	retire_request = function()
	{
		if (request_id != noone)
		{
			if (browser_target) html5_accounts_abort(request_id);
			array_push(retired_requests, { id: request_id, deadline: clock_ms() + 60000 });
			if (array_length(retired_requests) > 32) array_delete(retired_requests, 0, 1);
		}
		request_id = noone;
		request_kind = "";
		request_owner = "";
		request_deadline = 0;
		busy = false;
	}

	expire_session = function()
	{
		forget_saved_sign_in();
		retire_request();
		session_generation++;
		access_token = "";
		browser_authorized = false;
		token_deadline = 0;
		session_mode = "session";
		state = "expired";
		/* Keep the applied profile until the controller can safely return to the guest menu */
		complete("expired", false, "Session ended. Sign in again, or continue as guest.");
	}

	start_request = function(kind, path, body, authenticated, method = "POST", saved_bearer = "", expected_account = "")
	{
		if (!configured || busy) return false;
		last_http_status = 0;
		if (authenticated && saved_bearer == "" && !signed_in())
		{
			expire_session();
			return false;
		}
		var headers = ds_map_create();
		headers[? "Content-Type"] = "application/json";
		headers[? "Accept"] = "application/json";
		if (authenticated && !browser_target) headers[? "Authorization"] = "Bearer " + (saved_bearer != "" ? saved_bearer : access_token);
		var next_id = -1;
		try
		{
			if (browser_target)
			{
				var operation = string_replace(path, "/accounts/v1/", "");
				if (operation == "profile" && method == "PUT") operation = "profile-save";
				if (expected_account == "" && authenticated) expected_account = account_id;
				next_id = html5_accounts_request(base_url + "/accounts/v1", operation, "POST", json_stringify(body), expected_account);
			}
			else next_id = http_request(base_url + path, method, headers, method == "GET" ? "" : json_stringify(body));
		}
		catch(request_error) {}
		ds_map_destroy(headers);
		if (next_id < 0)
		{
			complete(kind, false, "Account service unavailable. You can still play as a guest.");
			return false;
		}
		request_id = next_id;
		request_kind = kind;
		request_generation = session_generation;
		request_owner = account_id;
		request_deadline = clock_ms() + request_timeout_ms;
		busy = true;
		conflict = false;
		return true;
	}

	valid_username = function(username)
	{
		if (!is_string(username)) return false;
		for (var i = 1; i <= string_length(username); i++) if (string_ord_at(username, i) > 127) return false;
		var value = string_lower(string_trim(username));
		if (string_length(value) < 3 || string_length(value) > 24) return false;
		for (var i = 1; i <= string_length(value); i++)
		{
			if (string_pos(string_char_at(value, i), "abcdefghijklmnopqrstuvwxyz0123456789_") == 0) return false;
		}
		return true;
	}

	valid_recovery_code = function(value)
	{
		if (!is_string(value) || string_length(value) != 64) return false;
		for (var i = 1; i <= 64; i++)
		{
			if (string_pos(string_char_at(value, i), "0123456789abcdef") == 0) return false;
		}
		return true;
	}

	valid_login = function(username, password)
	{
		if (!configured)
		{
			complete("configuration", false, "Accounts are not set up in this build. You can still play as a guest.");
			return false;
		}
		if (busy || signed_in()) return false;
		if (!valid_username(username) || !is_string(password)
		|| string_length(password) < 12 || string_length(password) > 128)
		{
			complete("credentials", false, "Use 3 to 24 characters: A-Z, 0-9 or _. Passwords need 12 to 128 characters.");
			return false;
		}
		return true;
	}

	begin_login = function(kind, username, password)
	{
		/* A deliberate password attempt supersedes a pending restore, including its late HTTP reply */
		if (busy && request_kind == "restore_session")
		{
			retire_request();
			session_generation++;
			restore_candidate = "";
			restored_identity = undefined;
			restore_pending = false;
		}
		restore_failed = false;
		restore_status = "";
		if (!valid_login(username, password)) return false;
		var remember_choice = keep_signed_in && (browser_target || vault_available);
		forget_saved_sign_in();
		if (browser_target)
			browser_restore_storage_ok = html5_accounts_suppress_restore(base_url + "/accounts/v1", true) == 1;
		keep_signed_in = remember_choice;
		login_remember_choice = remember_choice;
		login_session_mode = remember_choice ? remember_duration : "session";
		/* A new login cannot inherit the previous account's profile or pending HTTP reply */
		retire_request();
		session_generation++;
		account_id = "";
		account_username = "";
		recovery_code = "";
		export_data = "";
		access_token = "";
		browser_authorized = false;
		browser_cookie_proof = undefined;
		token_deadline = 0;
		session_mode = "session";
		cloud_profile = undefined;
		profile_loaded = false;
		conflict = false;
		state = "guest";
		var path = kind == "register" ? "/accounts/v1/register" : "/accounts/v1/login";
		if (!start_request(kind, path, { username: string_lower(string_trim(username)), password: password,
			remember_me: login_remember_choice, session_mode: login_session_mode }, false)) return false;
		state = "working";
		status_text = kind == "register" ? "Creating account..." : "Signing in...";
		return true;
	}

	register = function(username, password) { return begin_login("register", username, password); }
	sign_in = function(username, password) { return begin_login("sign_in", username, password); }

	recover = function(username, code, password)
	{
		if (!valid_login(username, password)) return false;
		code = string_lower(string_trim(code));
		if (!valid_recovery_code(code))
		{
			complete("recover", false, "Enter the full 64-character recovery code.");
			return false;
		}
		recovery_code = "";
		if (!start_request("recover", "/accounts/v1/recover", {
			username: string_lower(string_trim(username)), recovery_code: code, password: password }, false)) return false;
		status_text = "Recovering account...";
		return true;
	}

	password_action = function(kind, password)
	{
		if (!is_string(password) || string_length(password) < 12 || string_length(password) > 128)
		{
			complete(kind, false, "Enter your current password.");
			return false;
		}
		var path = kind == "delete_account" ? "/accounts/v1/delete" : "/accounts/v1/recovery-code";
		if (!start_request(kind, path, { password: password }, true)) return false;
		status_text = kind == "delete_account" ? "Deleting account..." : "Replacing recovery code...";
		return true;
	}

	export_account = function()
	{
		export_data = "";
		if (!start_request("export_account", "/accounts/v1/export", {}, true, "GET")) return false;
		status_text = "Preparing account data...";
		return true;
	}

	load_profile = function()
	{
		if (!start_request("load_profile", "/accounts/v1/profile", {}, true, "GET")) return false;
		profile_loaded = false;
		status_text = "Loading cloud profile...";
		return true;
	}

	valid_profile = function(profile, response)
	{
		if (!is_struct(profile)) return false;
		if (!variable_struct_exists(profile, "display_name") || !is_string(profile.display_name)
		|| string_length(profile.display_name) < 3 || string_length(profile.display_name) > 16
		|| chat_sanitize_username(profile.display_name) != profile.display_name
		|| !variable_struct_exists(profile, "character_key") || !builtin_character(profile.character_key)
		|| !variable_struct_exists(profile, "pet_key") || !builtin_pet(profile.pet_key)) return false;
		if (response)
		{
			if (!variable_struct_exists(profile, "account_id") || profile.account_id != account_id
			|| !variable_struct_exists(profile, "game_id") || profile.game_id != "jonnil-online"
			|| !variable_struct_exists(profile, "schema_version") || profile.schema_version != 1
			|| !variable_struct_exists(profile, "revision") || !is_real(profile.revision)
			|| profile.revision < 1 || profile.revision > 2147483647 || floor(profile.revision) != profile.revision
			|| !variable_struct_exists(profile, "updated_at") || !is_string(profile.updated_at)) return false;
		}
		return true;
	}

	save_profile = function(profile, expected_revision)
	{
		if (!profile_loaded)
		{
			complete("save_profile", false, "Reload the cloud profile before saving.");
			return false;
		}
		if (!valid_profile(profile, false) || !is_real(expected_revision)
		|| expected_revision < 0 || expected_revision > 2147483646 || floor(expected_revision) != expected_revision)
		{
			complete("save_profile", false, "Choose a name and built-in character and pet before saving.");
			return false;
		}
		/* Send only the three editable fields. A client cannot supply ownership or grants */
		var payload = { display_name: profile.display_name, character_key: profile.character_key, pet_key: profile.pet_key };
		if (!start_request("save_profile", "/accounts/v1/profile",
			{ display_name: payload.display_name, character_key: payload.character_key, pet_key: payload.pet_key, expected_revision: expected_revision }, true, "PUT")) return false;
		status_text = "Saving cloud profile...";
		return true;
	}

	sign_out = function()
	{
		var previous_token = access_token;
		var previous_account = account_id;
		var revoke_browser = browser_target && browser_authorized && previous_account != "";
		if (revoke_browser)
			browser_restore_storage_ok = html5_accounts_suppress_restore(base_url + "/accounts/v1", true) == 1;
		var saved_sign_in_removed = forget_saved_sign_in();
		retire_request();
		session_generation++;
		account_id = "";
		account_username = "";
		recovery_code = "";
		export_data = "";
		access_token = "";
		browser_authorized = false;
		browser_cookie_proof = undefined;
		token_deadline = 0;
		session_mode = "session";
		cloud_profile = undefined;
		profile_loaded = false;
		conflict = false;
		state = "guest";
		complete("sign_out", true, saved_sign_in_removed ? "Playing as guest." : "Playing as guest. " + vault_status);
		if (revoke_browser)
		{
			if (start_request("browser_logout", "/accounts/v1/logout", {}, false, "POST", "", previous_account))
				status_text = "Playing as guest. Confirming browser sign-out...";
			else unknown_result("browser_logout", "");
			return;
		}
		/* Local sign-out succeeds offline. Revoke only this device's provider session when reachable */
		if (configured && previous_token != "")
		{
			var headers = ds_map_create();
			headers[? "Content-Type"] = "application/json";
				headers[? "Authorization"] = "Bearer " + previous_token;
			var logout_id = -1;
			try { logout_id = http_request(base_url + "/accounts/v1/logout", "POST", headers, "{}"); }
			catch(logout_error) {}
			ds_map_destroy(headers);
			if (logout_id >= 0)
			{
				array_push(retired_requests, { id: logout_id, deadline: clock_ms() + 60000 });
				if (array_length(retired_requests) > 32) array_delete(retired_requests, 0, 1);
			}
		}
		previous_token = "";
	}

	unknown_result = function(kind, fallback)
	{
		var message = fallback;
		if (browser_target && (kind == "sign_in" || kind == "register" || kind == "browser_proof"))
		{
			browser_restore_storage_ok = html5_accounts_suppress_restore(base_url + "/accounts/v1", true) == 1;
			if (kind == "browser_proof" && is_struct(browser_cookie_proof))
			{
				kind = browser_cookie_proof.operation;
				message = kind == "register"
					? "Account created, but browser sign-in was not confirmed. Save your recovery code, then check your browser cookie settings."
					: "Browser sign-in was not confirmed. Your browser may be blocking account cookies. Check its cookie settings or try another browser.";
			}
			else if (message == "") message = kind == "register" ? "Creation result unknown. Try signing in. If it works, replace your recovery code."
				: "Sign-in result unknown. Try again, or play as a guest.";
			browser_cookie_proof = undefined;
			browser_authorized = false;
			message += browser_restore_storage_ok ? " A browser session may remain, but automatic sign-in is paused."
				: " A browser session may remain. Automatic sign-in could not be paused. Clear this site's account cookies on shared devices.";
		}
		else if (kind == "browser_logout")
		{
			message = "This page is now a guest, but browser sign-out was not confirmed. A browser session may remain.";
			if (!browser_restore_storage_ok) message += " Automatic sign-in could not be paused. Clear this site's account cookies on shared devices.";
		}
		else if (kind == "browser_forget") message = "Could not confirm the browser sign-in change. It may still be remembered. Try signing out instead.";
		else if (kind == "restore_session")
		{
			restore_pending = false;
			restore_failed = true;
			restore_retry_available = remembered_on_device;
			restore_status = "Could not check your saved sign-in. Retry when connected. Guest play is available.";
			message = restore_status;
		}
		else if (kind == "save_profile")
		{
			profile_loaded = false;
			message = "Save result unknown. Reload the cloud profile before saving again.";
		}
		else if (kind == "recover") message = "Recovery result unknown. Try the new password. If it works, replace your recovery code.";
		else if (kind == "recovery_code") message = "Code replacement result unknown. Replace it again before relying on your saved code.";
		else if (kind == "register") message = "Creation result unknown. Try signing in. If it works, replace your recovery code.";
		else if (kind == "delete_account")
		{
			forget_saved_sign_in();
			shutdown();
			message = "Deletion result unknown. Sign in again to check. Your guest profile remains available.";
		}
		complete(kind, false, message);
		uncertain_result = true;
	}

	cancel = function()
	{
		if (!busy) return;
		var kind = request_kind;
		retire_request();
		session_generation++;
		state = signed_in() ? "signed_in" : "guest";
		unknown_result(kind, "Account request cancelled.");
	}

	update = function()
	{
		var now = clock_ms();
		if (browser_target && request_id != noone)
		{
			var browser_reply = html5_accounts_poll(request_id);
			if (browser_reply != "")
			{
				var event = -1;
				try
				{
					event = json_decode(browser_reply);
					if (ds_exists(event, ds_type_map)) handle_http(event);
				}
				catch(browser_reply_error) {}
				if (event >= 0 && ds_exists(event, ds_type_map)) ds_map_destroy(event);
			}
		}
		for (var i = array_length(retired_requests) - 1; i >= 0; i--)
		{
			if (retired_requests[i].deadline <= now) array_delete(retired_requests, i, 1);
		}
		if ((access_token != "" || browser_authorized) && session_expired())
		{
			expire_session();
			return;
		}
		if (busy && now >= request_deadline)
		{
			var kind = request_kind;
			retire_request();
			session_generation++;
			state = signed_in() ? "signed_in" : "guest";
			unknown_result(kind, "Account request timed out. You can still play as a guest.");
		}
	}

	handle_http = function(event)
	{
		if (!ds_map_exists(event, "id")) return false;
		var incoming_id = event[? "id"];
		for (var i = 0; i < array_length(retired_requests); i++)
		{
			if (incoming_id == retired_requests[i].id) return true;
		}
		if (incoming_id != request_id || request_id == noone) return false;
		if (!ds_map_exists(event, "status")) return true;
		var async_status = event[? "status"];
		if (async_status > 0) return true;
		var kind = request_kind;
		var valid_generation = request_generation == session_generation && request_owner == account_id;
		var code = ds_map_exists(event, "http_status") ? event[? "http_status"] : 0;
		last_http_status = code;
		retire_request();
		if (!valid_generation) return true;
		if ((access_token != "" || browser_authorized) && session_expired())
		{
			expire_session();
			return true;
		}
		state = signed_in() ? "signed_in" : "guest";
		if (async_status < 0 || code < 200 || code >= 300)
		{
			var browser_error = "";
			if (browser_target && ds_map_exists(event, "result") && is_string(event[? "result"]))
			{
				try
				{
					var error_reply = json_parse(event[? "result"]);
					if (is_struct(error_reply) && variable_struct_exists(error_reply, "error") && is_string(error_reply.error)) browser_error = error_reply.error;
				}
				catch(browser_error_parse) {}
			}
			if (browser_target && kind == "browser_proof")
			{
				unknown_result(kind, "");
				return true;
			}
			if (browser_target && kind == "browser_logout")
			{
				unknown_result(kind, "");
				return true;
			}
			if (browser_target && kind == "restore_session" && code == 401)
			{
				forget_saved_sign_in();
				complete(kind, true, "Playing as guest.");
				return true;
			}
			if (browser_target && (browser_error == "browser_identity_changed"
			|| (browser_error == "invalid_session" && kind != "sign_in" && kind != "register" && kind != "recover")))
			{
				expire_session();
				status_text = "Browser sign-in changed or ended. Sign in again, or play as a guest.";
				return true;
			}
			if (browser_target && browser_error == "browser_origin_not_allowed")
			{
				forget_saved_sign_in();
				configured = false;
				availability_message = "Accounts are not available on this hosted page yet. You can still play as a guest.";
				complete(kind, false, availability_message);
				return true;
			}
			if (kind == "restore_session")
			{
				if (async_status < 0 || code == 0 || code >= 500 || code == 429 || code == 404 || code == 405)
					unknown_result(kind, "Saved sign-in could not be checked.");
				else
				{
					forget_saved_sign_in();
					restore_failed = true;
					restore_status = "Saved sign-in expired or was revoked. Sign in again, or play as a guest.";
					complete(kind, false, restore_status);
				}
				return true;
			}
			if (async_status < 0 || code == 0 || code >= 500)
			{
				var unavailable = "Account service unavailable. You can still play as a guest.";
				if (kind == "sign_in") unavailable = code >= 500
					? "The sign-in service is temporarily unavailable. Try again later or play as a guest."
					: "Could not reach the sign-in service. Check your connection and try again. Guest play is available.";
				if (browser_target && code == 0) unavailable = "Could not reach the account server. Check your connection and try again. You can still play as a guest.";
				unknown_result(kind, unavailable);
				return true;
			}
			if (kind == "save_profile") profile_loaded = false;
			if (code == 401 && (kind == "load_profile" || kind == "save_profile" || kind == "export_account"))
			{
				expire_session();
				return true;
			}
			conflict = code == 409 && kind == "save_profile";
			var message = "Account service unavailable. You can still play as a guest.";
			if (conflict) message = "The cloud profile changed. Reload it before choosing what to keep.";
			else if (code == 429) message = "Too many account requests. Wait a moment before trying again.";
			else if (kind == "sign_in" && code == 401)
				message = "Username and password do not match. Try again, or choose Recover account.";
			else if (kind == "sign_in" && code == 400)
				message = "Sign-in request was not accepted. Check your details or update the game.";
			else if (kind == "sign_in" && (code == 404 || code == 405))
				message = "Sign-in is unavailable in this version. Update the game or try again later.";
			else if (kind == "sign_in" && code >= 400 && code < 500)
				message = "Sign-in was not accepted. Try again later, or choose Recover account.";
			else if (kind == "register" && code >= 400 && code < 500)
				message = "Could not create the account. Check your details or try signing in.";
			else if (kind == "recover" && code >= 400 && code < 500)
				message = "Could not recover the account. Check your username, recovery code and new password.";
			else if ((kind == "delete_account" || kind == "recovery_code") && code >= 400 && code < 500)
				message = "Could not confirm this action. Check your current password, or sign in again.";
			else if (code == 400) message = "The profile was not saved. Check its name and built-in choices.";
			complete(kind, false, message);
			return true;
		}
		var result = undefined;
		if (ds_map_exists(event, "result") && is_string(event[? "result"])
		&& string_byte_length(event[? "result"]) <= 65536)
		{
			try { result = json_parse(event[? "result"], undefined, true); } catch(parse_error) {}
		}
		if (!is_struct(result))
		{
			if (browser_target && (kind == "browser_proof" || kind == "browser_logout" || kind == "browser_forget"))
			{
				unknown_result(kind, "");
				return true;
			}
			if (kind == "restore_session")
			{
				forget_saved_sign_in();
				restore_failed = true;
				restore_status = "The saved sign-in could not be verified. Sign in again.";
				complete(kind, false, restore_status);
				return true;
			}
			if (kind == "save_profile") profile_loaded = false;
			complete(kind, false, "The account service returned an invalid reply. Try again.");
			return true;
		}
		if (kind == "register" || kind == "sign_in")
		{
			if (browser_target && kind == "register" && variable_struct_exists(result, "recovery_code") && valid_recovery_code(result.recovery_code))
				recovery_code = result.recovery_code;
			if (!valid_session_reply(result, !browser_target) || reply_session_mode(result) != login_session_mode
			|| (kind == "register" && (!variable_struct_exists(result, "recovery_code") || !valid_recovery_code(result.recovery_code))))
			{
				if (browser_target) unknown_result(kind, recovery_code != ""
					? "Account created, but sign-in could not be verified. Save your recovery code, then try signing in."
					: "Sign-in could not be verified. Update the game or try again later.");
				else complete(kind, false, "Sign-in could not be verified. Update the game or try again later.");
				return true;
			}
			if (browser_target)
			{
				if (kind == "register") recovery_code = result.recovery_code;
				browser_cookie_proof = { id: string_lower(result.user.id), username: result.user.username,
					mode: reply_session_mode(result), operation: kind };
				if (!start_request("browser_proof", "/accounts/v1/session", {}, false, "GET", "", browser_cookie_proof.id))
					unknown_result("browser_proof", "");
				else status_text = "Checking browser sign-in...";
				return true;
			}
			account_id = string_lower(result.user.id);
			account_username = result.user.username;
			if (kind == "register") recovery_code = result.recovery_code;
			access_token = result.access_token;
			session_mode = reply_session_mode(result);
			token_deadline = session_mode == "until_sign_out" ? 0 : clock_ms() + (result.expires_in - 5) * 1000;
			if (result.remember_me) remember_current_session();
			state = "signed_in";
			complete(kind, true, "Signed in.");
			load_profile();
			return true;
		}
		if (kind == "restore_session")
		{
			if (!valid_session_reply(result, false) || (!browser_target && !valid_session_token(restore_candidate)))
			{
				forget_saved_sign_in();
				restore_failed = true;
				restore_status = "The saved sign-in reply was invalid. Sign in again.";
				complete(kind, false, restore_status);
				return true;
			}
			var verified_mode = reply_session_mode(result);
			var verified = { id: string_lower(result.user.id), username: result.user.username,
				token: restore_candidate, mode: verified_mode,
				deadline: verified_mode == "until_sign_out" ? 0 : clock_ms() + (result.expires_in - 5) * 1000 };
			restored_identity = verified;
			restore_candidate = "";
			restore_pending = true;
			restore_failed = false;
			restore_retry_available = false;
			restore_status = "Saved sign-in verified. It will be restored in the main menu.";
			complete(kind, true, restore_status);
			return true;
		}
		if (kind == "browser_proof")
		{
			if (!is_struct(browser_cookie_proof) || !valid_session_reply(result, false)
			|| result.user.id != browser_cookie_proof.id || result.user.username != browser_cookie_proof.username
			|| reply_session_mode(result) != browser_cookie_proof.mode)
			{
				unknown_result(kind, "");
				return true;
			}
			var operation = browser_cookie_proof.operation;
			account_id = browser_cookie_proof.id;
			account_username = browser_cookie_proof.username;
			browser_cookie_proof = undefined;
			browser_authorized = true;
			access_token = "";
			session_mode = reply_session_mode(result);
			token_deadline = session_mode == "until_sign_out" ? 0 : clock_ms() + (result.expires_in - 5) * 1000;
			keep_signed_in = result.remember_me;
			browser_restore_storage_ok = html5_accounts_suppress_restore(base_url + "/accounts/v1", false) == 1;
			remembered_on_device = result.remember_me && browser_restore_storage_ok;
			if (session_mode != "session") remember_duration = session_mode;
			state = "signed_in";
			vault_status = browser_restore_storage_ok ? "" : "Signed in now, but automatic sign-in is unavailable in this browser.";
			complete(operation, true, vault_status != "" ? vault_status : "Signed in.");
			load_profile();
			return true;
		}
		if (kind == "browser_logout")
		{
			if (!variable_struct_exists(result, "signed_out") || result.signed_out != true) unknown_result(kind, "");
			else complete(kind, true, "Signed out of this browser. Your guest profile is ready.");
			return true;
		}
		if (kind == "browser_forget")
		{
			if (!valid_session_reply(result, false) || result.user.id != account_id || reply_session_mode(result) != "session")
			{
				complete(kind, false, "Could not stop remembering this browser. Try signing out instead.");
				return true;
			}
			keep_signed_in = false;
			remembered_on_device = false;
			session_mode = "session";
			token_deadline = clock_ms() + (result.expires_in - 5) * 1000;
			complete(kind, true, "This sign-in now uses a browser session cookie. Browser session restore can keep it open. Sign out to end it.");
			return true;
		}
		if (kind == "recover" || kind == "recovery_code")
		{
			if (!variable_struct_exists(result, "recovery_code") || !valid_recovery_code(result.recovery_code)
			|| (kind == "recover" && (!variable_struct_exists(result, "recovered") || result.recovered != true)))
			{
				complete(kind, false, "The recovery result was invalid. Sign in and replace your recovery code.");
				return true;
			}
			recovery_code = result.recovery_code;
			if (kind == "recover") forget_saved_sign_in();
			complete(kind, true, kind == "recover" ? "Password changed. Save the new recovery code, then sign in." : "Recovery code replaced. Save the new code.");
			return true;
		}
		if (kind == "delete_account")
		{
			if (!variable_struct_exists(result, "deleted") || result.deleted != true)
			{
				complete(kind, false, "The deletion result was invalid. Sign in again to check your account.");
				return true;
			}
			forget_saved_sign_in();
			shutdown();
			complete(kind, true, "Account deleted. Your guest profile is still available.");
			return true;
		}
		if (kind == "export_account")
		{
			if (!variable_struct_exists(result, "account") || !is_struct(result.account)
			|| !variable_struct_exists(result.account, "id") || result.account.id != account_id
			|| !variable_struct_exists(result.account, "username") || result.account.username != account_username
			|| !variable_struct_exists(result.account, "created_at") || !is_string(result.account.created_at)
			|| !variable_struct_exists(result, "profile") || (!is_undefined(result.profile) && !valid_profile(result.profile, true)))
			{
				complete(kind, false, "The account export was invalid. No file was saved.");
				return true;
			}
			/* Export only public contract fields, never an unexpected server field or token */
			var exported_profile = undefined;
			if (is_struct(result.profile)) exported_profile = {
				account_id: account_id, game_id: "jonnil-online", schema_version: 1,
				revision: result.profile.revision, display_name: result.profile.display_name,
				character_key: result.profile.character_key, pet_key: result.profile.pet_key,
				updated_at: result.profile.updated_at };
			export_data = json_stringify({ account: { id: account_id, username: account_username,
				created_at: result.account.created_at }, profile: exported_profile });
			complete(kind, true, "Account data is ready to save.");
			return true;
		}
		if (!variable_struct_exists(result, "exists") || !is_bool(result.exists)
		|| (result.exists && (!variable_struct_exists(result, "profile") || !valid_profile(result.profile, true)))
		|| (kind == "save_profile" && !result.exists))
		{
			if (kind == "save_profile") profile_loaded = false;
			complete(kind, false, "The account service returned an invalid profile. No choices were changed.");
			return true;
		}
		cloud_profile = result.exists ? result.profile : undefined;
		profile_loaded = true;
		conflict = false;
		complete(kind, true, kind == "save_profile" ? "Cloud profile saved."
			: (result.exists ? "Cloud profile loaded." : "Your public profile choices will save automatically."));
		return true;
	}

	shutdown = function()
	{
		/* Clear RAM authority. An opted-in credential stays only in the Windows user vault */
		retire_request();
		session_generation++;
		access_token = "";
		browser_authorized = false;
		browser_cookie_proof = undefined;
		account_id = "";
		account_username = "";
		recovery_code = "";
		export_data = "";
		cloud_profile = undefined;
		profile_loaded = false;
		token_deadline = 0;
		session_mode = "session";
		state = "guest";
		restore_candidate = "";
		restored_identity = undefined;
		restore_pending = false;
	}

	/* No account requests are made until the operator explicitly enables this build */
	var config = undefined;
	var config_file = "accounts/config.json";
	if (file_exists(config_file))
	{
		var file = -1;
		try
		{
			file = file_text_open_read(config_file);
			var text = "";
			while (!file_text_eof(file) && string_byte_length(text) <= 8192)
			{
				text += file_text_read_string(file);
				file_text_readln(file);
			}
			file_text_close(file);
			file = -1;
			if (string_byte_length(text) <= 8192) config = json_parse(text);
		}
		catch(config_error) { if (file >= 0) file_text_close(file); }
	}
	/* Browser authority uses protected cookies. Only Windows may use the native credential vault */
	if (supported_target && is_struct(config) && variable_struct_exists(config, "enabled") && config.enabled == true
	&& variable_struct_exists(config, "api_origin") && is_string(config.api_origin))
	{
		var url = config.api_origin;
		var secure_origin = url == "https://online.jonnil.games";
		var development_origin = variable_struct_exists(config, "allow_development_http")
			&& config.allow_development_http == true && url == "http://127.0.0.1:8790";
		if (secure_origin || development_origin)
		{
			base_url = url;
			configured = true;
			var scope = "live";
			if (variable_struct_exists(config, "credential_scope"))
			{
				var candidate_scope = config.credential_scope;
				var valid_scope = is_string(candidate_scope) && string_length(candidate_scope) >= 4
					&& string_length(candidate_scope) <= 64 && string_copy(candidate_scope, 1, 3) == "qa/";
				if (valid_scope)
				{
					for (var i = 4; i <= string_length(candidate_scope); i++)
						if (string_pos(string_char_at(candidate_scope, i), "abcdefghijklmnopqrstuvwxyz0123456789_-") == 0) valid_scope = false;
				}
				if (valid_scope) scope = candidate_scope;
				else configured = false;
			}
			if (configured && browser_target)
			{
				var context_allowed = 0;
				try { context_allowed = html5_accounts_context_allowed(base_url + "/accounts/v1"); } catch(context_error) {}
				if (context_allowed != 1)
				{
					configured = false;
					browser_page_unsupported = context_allowed == 2;
					availability_message = context_allowed == 2
						? "Accounts are not available on this hosted page yet. You can still play as a guest."
						: "Sign-in needs a secure browser page. Open the game using HTTPS.";
				}
				else restore_retry();
			}
			if (configured && !browser_target)
			{
				vault_target = "JonnilOnline/accounts/v1/" + (secure_origin ? "online.jonnil.games/" : "127.0.0.1-8790/") + scope;
				if (scope != "live") device_preferences_file = "account_device_" + string_replace_all(scope, "/", "_") + ".ini";
				else if (development_origin) device_preferences_file = "account_device_local.ini";
				try { vault_available = jonnil_vault_available() == 1; } catch(vault_error) { vault_available = false; }
				try
				{
					if (vault_available && file_exists(device_preferences_file))
					{
						ini_open(device_preferences_file);
						keep_signed_in = ini_read_real("account", "keep_signed_in", 0) == 1;
						var saved_duration = ini_read_string("account", "remember_duration", "30_days");
						if (keep_signed_in && (saved_duration == "30_days" || saved_duration == "until_sign_out")) remember_duration = saved_duration;
						ini_close();
					}
				}
				catch(preference_error) { try { ini_close(); } catch(close_error) {} }
				if (keep_signed_in) restore_retry();
			}
		}
	}
}
