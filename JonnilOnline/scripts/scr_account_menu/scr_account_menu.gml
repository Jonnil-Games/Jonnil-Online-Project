/// @description Optional account controls that leave guest play and its profile available
function scr_account_menu(controller_id, account_service) constructor
{
	controller = controller_id;
	service = account_service;
	opened = false;
	focus = "username";
	hover = "";
	input_truncated = { username: false, password: false, recovery: false };
	username = ""; input_truncated.username = false;
	password = ""; input_truncated.password = false;
	password_visible = false;
	recovery_input = ""; input_truncated.recovery = false;
	page = "sign_in";
	form_completion = service.completion_serial;
	restore_prompt_dismissed = false;
	display_name = "";
	notice = "";
	browser_copy_pending = false;
	browser_copy_due = 0;
	browser_copy_generation = 0;
	confirm_action = "";
	known_account_id = "";
	seen_completion = 0;
	navigation_due = 0;
	controls = [];
	panel_x = 0;
	panel_y = 0;
	panel_width = 600;
	panel_height = 590;
	ui_scale = 1;
	password_extra_height = 0;
	password_shift_after = 10000;
	feedback_tops = [];
	feedback_extra_height = 0;
	status_extra_height = 0;
	sync_owner = "";
	sync_ready = false;
	sync_dirty = false;
	sync_conflict = false;
	sync_paused = false;
	sync_storage_failed = false;
	sync_cache_blocked = false;
	sync_baseline = undefined;
	sync_revision = 0;
	sync_observed = undefined;
	sync_inflight = undefined;
	sync_initial = undefined;
	sync_request = "";
	sync_reconcile = false;
	sync_retry_count = 0;
	sync_due = 0;
	sync_last_write = -2000;
	sync_status = "";

	clear_credential_inputs = function()
	{
		password = ""; input_truncated.password = false;
		password_visible = false;
		recovery_input = ""; input_truncated.recovery = false;
		if (focus == "password" || focus == "recovery") keyboard_string = "";
	}

	profile_payload = function(profile)
	{
		return { display_name: profile.display_name, character_key: profile.character_key,
			pet_key: profile.pet_key };
	}

	profile_equal = function(first, second)
	{
		if (!is_struct(first) || !is_struct(second)) return !is_struct(first) && !is_struct(second);
		return first.display_name == second.display_name && first.character_key == second.character_key
			&& first.pet_key == second.pet_key;
	}

	sync_owns_cache = function()
	{
		return sync_owner != "" && sync_owner == service.account_id
			&& known_account_id == sync_owner && AccountProfiles.account_id == sync_owner;
	}

	sync_active = function()
	{
		return service.signed_in() && sync_owns_cache();
	}

	/// @description Project built-in choices while keeping custom artwork and its last cloud choice separate
	sync_capture = function()
	{
		var draft = AccountProfiles.capture_cloud(controller.client_username);
		if (!is_struct(draft)) return undefined;
		if (is_struct(sync_baseline))
		{
			if (draft.character_local_only) draft.character_key = sync_baseline.character_key;
			if (draft.pet_local_only) draft.pet_key = sync_baseline.pet_key;
		}
		return profile_payload(draft);
	}

	sync_record_pending = function()
	{
		if (!sync_owns_cache()) return false;
		if (!sync_dirty && !is_struct(sync_inflight))
		{
			sync_storage_failed = !AccountProfiles.clear_cloud_sync();
			return !sync_storage_failed;
		}
		var draft = sync_capture();
		if (!service.valid_profile(draft, false)) return false;
		sync_storage_failed = !AccountProfiles.write_cloud_sync({ version: 1, revision: sync_revision,
			baseline: sync_baseline, draft: draft, submitted: sync_inflight });
		return !sync_storage_failed;
	}

	/// @description Bind save state to this account before accepting its first cloud response
	sync_begin = function()
	{
		sync_owner = service.account_id;
		sync_ready = false;
		sync_dirty = false;
		sync_conflict = false;
		sync_paused = false;
		sync_storage_failed = false;
		sync_cache_blocked = false;
		sync_baseline = undefined;
		sync_revision = 0;
		sync_inflight = undefined;
		sync_request = "";
		sync_reconcile = false;
		sync_retry_count = 0;
		sync_due = 0;
		sync_last_write = -2000;
		sync_initial = sync_capture();
		sync_observed = sync_initial;
		sync_status = "Loading your saved profile...";
		var pending = AccountProfiles.read_cloud_sync();
		if (is_struct(pending) && variable_struct_exists(pending, "version") && pending.version == 1
		&& variable_struct_exists(pending, "revision") && is_real(pending.revision)
		&& pending.revision >= 0 && pending.revision < 2147483647 && floor(pending.revision) == pending.revision
		&& variable_struct_exists(pending, "baseline")
		&& (pending.revision == 0 ? !is_struct(pending.baseline) : service.valid_profile(pending.baseline, false))
		&& variable_struct_exists(pending, "draft") && service.valid_profile(pending.draft, false))
		{
			sync_revision = pending.revision;
			sync_baseline = pending.baseline;
			sync_dirty = true;
			if (variable_struct_exists(pending, "submitted") && service.valid_profile(pending.submitted, false))
				sync_inflight = profile_payload(pending.submitted);
			/* Restore the durable pending draft before comparing it with the cloud */
			if (!sync_apply(pending.draft, true))
			{
				sync_cache_blocked = true;
				sync_storage_failed = true;
				sync_conflict = true;
				sync_paused = true;
			}
			sync_observed = sync_capture();
			sync_status = "Checking changes saved on this device...";
		}
	}

	sync_apply = function(profile, preserve_custom)
	{
		var applied = AccountProfiles.apply_cloud(profile, controller.client_username, preserve_custom);
		if (!applied.ok) return false;
		controller.client_username = applied.display_name;
		display_name = applied.display_name;
		controller.network_update_window_caption();
		if (focus == "name") keyboard_string = display_name;
		return true;
	}

	sync_retry_later = function()
	{
		sync_request = "";
		sync_reconcile = true;
		sync_retry_count++;
		if (sync_retry_count > 3)
		{
			sync_paused = true;
			sync_status = "Not saved to your account. Changes stay on this device. Choose Retry cloud save.";
			return;
		}
		var delays = [5000, 15000, 60000];
		sync_due = service.clock_ms() + delays[sync_retry_count - 1];
		sync_status = "Waiting to reconnect. Changes are saved on this device and will retry automatically.";
	}

	/// @description Reconcile uncertain writes before using a new revision or applying another device's profile
	sync_loaded = function()
	{
		if (!sync_active() || !service.profile_loaded) return;
		var in_menu = controller.network_mode_screen && controller.network_mode_page == "main";
		var remote = is_struct(service.cloud_profile) ? profile_payload(service.cloud_profile) : undefined;
		var revision = is_struct(service.cloud_profile) ? service.cloud_profile.revision : 0;
		var local = sync_capture();
		var had_pending = sync_dirty || is_struct(sync_inflight);
		sync_request = "";
		sync_reconcile = false;
		/* Restoring a profile must not change an active gameplay session */
		if (!had_pending && !in_menu) return;
		if (sync_conflict)
		{
			sync_ready = true;
			sync_status = "Cloud changes found. Choose Use cloud profile or Keep this device.";
			return;
		}
		if (had_pending)
		{
			var acknowledged = profile_equal(remote, local)
				|| (is_struct(sync_inflight) && profile_equal(remote, sync_inflight));
			var unchanged = revision == sync_revision && profile_equal(remote, sync_baseline);
			if (!acknowledged && !unchanged)
			{
				sync_ready = true;
				sync_conflict = true;
				sync_status = "Cloud changes found. Your device changes are safe. Choose which profile to keep.";
				return;
			}
			sync_baseline = remote;
			sync_revision = revision;
			sync_inflight = undefined;
			sync_ready = true;
			sync_observed = sync_capture();
			sync_dirty = !profile_equal(sync_observed, sync_baseline);
			if (!sync_dirty) sync_retry_count = 0;
			sync_due = service.clock_ms() + 1000;
			sync_status = sync_dirty ? "Changes saved on this device. Saving to your account automatically..." : "All profile changes are saved to your account.";
			sync_record_pending();
			return;
		}
		if (!sync_ready && !profile_equal(local, sync_initial))
		{
			/* A choice made while sign-in was loading cannot silently replace the remote profile */
			sync_ready = true;
			sync_dirty = true;
			sync_conflict = true;
			sync_baseline = remote;
			sync_revision = revision;
			sync_observed = sync_capture();
			sync_record_pending();
			sync_status = "Your choices changed while loading. Choose which profile to keep.";
			return;
		}
		sync_baseline = remote;
		sync_revision = revision;
		if (is_struct(remote) && !sync_apply(service.cloud_profile, true))
		{
			sync_paused = true;
			sync_status = "Could not restore your profile on this device. Choose Retry cloud save.";
			return;
		}
		sync_ready = true;
		sync_observed = sync_capture();
		sync_dirty = service.valid_profile(sync_observed, false) && !profile_equal(sync_observed, sync_baseline);
		if (!sync_dirty) sync_retry_count = 0;
		sync_due = service.clock_ms() + 1000;
		sync_status = sync_dirty ? "Saving your profile to your account automatically..." : (is_struct(remote)
			? "All profile changes are saved to your account." : "Choose a valid display name. Profile changes save automatically.");
		sync_record_pending();
	}

	sync_completed = function()
	{
		if (!sync_active()) return;
		if (service.last_operation == "load_profile")
		{
			if (service.last_success) sync_loaded();
			else sync_retry_later();
		}
		else if (service.last_operation == "save_profile" && sync_request == "save")
		{
			sync_request = "";
			if (service.last_success && is_struct(service.cloud_profile))
			{
				sync_baseline = profile_payload(service.cloud_profile);
				sync_revision = service.cloud_profile.revision;
				sync_inflight = undefined;
				sync_retry_count = 0;
				sync_reconcile = false;
				sync_paused = false;
				/* Never apply an old save reply over edits made while its request was pending */
				sync_observed = sync_capture();
				sync_dirty = !profile_equal(sync_observed, sync_baseline);
				sync_due = service.clock_ms() + 1000;
				sync_status = sync_dirty ? "Saving your latest changes automatically..." : "All profile changes are saved to your account.";
				sync_record_pending();
			}
			else if (service.conflict)
			{
				sync_conflict = true;
				sync_reconcile = true;
				sync_inflight = undefined;
				sync_due = service.clock_ms();
				sync_status = "Cloud profile changed on another device. Loading it so you can choose what to keep...";
				sync_record_pending();
			}
			else if (service.last_http_status == 400)
			{
				sync_paused = true;
				sync_reconcile = true;
				sync_status = "Profile not saved. Check your display name, then choose Retry cloud save.";
			}
			else sync_retry_later();
		}
	}

	sync_retry_now = function()
	{
		if (!sync_active() || service.busy) return false;
		sync_paused = false;
		sync_retry_count = 0;
		sync_reconcile = true;
		sync_due = service.clock_ms();
		sync_status = "Checking the cloud profile before saving...";
		return true;
	}

	sync_keep_device = function()
	{
		if (!sync_active() || service.busy || !service.profile_loaded) return false;
		sync_baseline = is_struct(service.cloud_profile) ? profile_payload(service.cloud_profile) : undefined;
		sync_revision = is_struct(service.cloud_profile) ? service.cloud_profile.revision : 0;
		sync_ready = true;
		sync_conflict = false;
		sync_paused = false;
		sync_reconcile = false;
		sync_cache_blocked = false;
		sync_inflight = undefined;
		sync_retry_count = 0;
		sync_observed = sync_capture();
		sync_dirty = !profile_equal(sync_observed, sync_baseline);
		sync_due = service.clock_ms();
		sync_status = sync_dirty ? "Saving the profile you chose to keep..." : "All profile changes are saved to your account.";
		sync_record_pending();
		return true;
	}

	sync_use_cloud = function()
	{
		if (!sync_active() || service.busy || !service.profile_loaded || !is_struct(service.cloud_profile)) return false;
		if (!sync_apply(service.cloud_profile, false)) return false;
		sync_baseline = profile_payload(service.cloud_profile);
		sync_revision = service.cloud_profile.revision;
		sync_observed = sync_capture();
		sync_ready = true;
		sync_dirty = false;
		sync_conflict = false;
		sync_paused = false;
		sync_reconcile = false;
		sync_cache_blocked = false;
		sync_inflight = undefined;
		sync_retry_count = 0;
		sync_status = "Cloud profile restored. All profile changes are saved to your account.";
		sync_record_pending();
		return true;
	}

	/// @description Flush the latest local choices before sign-out or shutdown without starting HTTP work
	sync_flush_local = function(force = true)
	{
		if (!sync_owns_cache()) return true;
		if (sync_cache_blocked) return false;
		var current = sync_capture();
		if (!service.valid_profile(current, false)) return !sync_storage_failed;
		var changed = !profile_equal(current, sync_observed);
		if (changed)
		{
			sync_observed = current;
			sync_dirty = sync_ready ? !profile_equal(current, sync_baseline)
				: (sync_dirty || !profile_equal(current, sync_initial));
			sync_due = max(sync_due, service.clock_ms() + 1000);
			if (!sync_conflict && !sync_paused) sync_status = sync_dirty
				? "Changes saved on this device. Saving to your account automatically..." : "All profile changes are saved to your account.";
		}
		if (changed || (force && (sync_dirty || is_struct(sync_inflight)))) return sync_record_pending();
		return !sync_storage_failed;
	}

	/// @description Save a valid public name locally immediately, then debounce its cloud upload
	sync_set_name = function(value)
	{
		display_name = value;
		if (!sync_active() || !is_string(value) || string_length(value) < 3 || string_length(value) > 16
		|| chat_sanitize_username(value) != value) return false;
		if (value == controller.client_username) return true;
		if (!AccountProfiles.write_string("username", value))
		{
			notice = "Could not save this display name on your device.";
			return false;
		}
		controller.client_username = value;
		controller.network_update_window_caption();
		sync_flush_local();
		return true;
	}

	/// @description Keep saving in menus and gameplay, with bounded retries and account-owned local recovery
	sync_update = function()
	{
		sync_flush_local(false);
		if (!sync_active()) return;
		var now = service.clock_ms();
		if (!sync_ready && !sync_paused && service.profile_loaded && !service.busy) sync_loaded();
		if (service.busy || sync_paused || sync_cache_blocked || now < sync_due) return;
		if (sync_reconcile)
		{
			sync_request = "reconcile";
			if (!service.load_profile() && !service.busy) sync_retry_later();
			return;
		}
		if (!sync_ready || sync_conflict || !sync_dirty || service.recovery_code != "" || now < sync_last_write + 2000) return;
		if (opened && page == "profile" && focus == "name" && (string_length(display_name) < 3
		|| chat_sanitize_username(display_name) != display_name)) return;
		var draft = sync_capture();
		if (!service.valid_profile(draft, false)) return;
		if (!service.profile_loaded) { sync_reconcile = true; return; }
		sync_inflight = profile_payload(draft);
		sync_record_pending();
		sync_request = "save";
		sync_last_write = now;
		if (service.save_profile(sync_inflight, sync_revision)) sync_status = "Saving profile changes to your account...";
		else if (!service.busy && service.last_operation != "save_profile") sync_retry_later();
	}

	set_focus = function(key)
	{
		/* Focus changes preserve the current form's Show/Hide choice */
		focus = key;
		keyboard_string = focus == "username" ? username
			: (focus == "password" ? password : (focus == "recovery" ? recovery_input : (focus == "name" ? display_name : "")));
	}

	set_auth_page = function(next_page)
	{
		page = next_page;
		password_visible = false;
		restore_prompt_dismissed = true;
		password = ""; input_truncated.password = false;
		recovery_input = ""; input_truncated.recovery = false;
		notice = "";
		form_completion = service.completion_serial;
		set_focus(service.configured ? "username" : "back");
	}

	activate_guest = function()
	{
		password_visible = false;
		username = ""; input_truncated.username = false;
		password = ""; input_truncated.password = false;
		recovery_input = ""; input_truncated.recovery = false;
		page = "sign_in";
		form_completion = service.completion_serial;
		confirm_action = "";
		AccountProfiles.use_guest();
		controller.client_username = controller.client_load_saved_username();
		controller.client_username_persistence_suppressed = false;
		known_account_id = "";
		sync_owner = "";
		sync_ready = false;
		sync_dirty = false;
		sync_conflict = false;
		sync_request = "";
		display_name = controller.client_username;
		controller.network_update_window_caption();
		if (opened) set_focus(service.configured ? "username" : "back");
	}

	show_restore_prompt = function()
	{
		return !service.signed_in() && service.restore_failed && service.remembered_on_device
			&& !restore_prompt_dismissed;
	}

	update = function()
	{
		if (browser_copy_pending)
		{
			var copy_status = html5_diag_copy_status_for(browser_copy_generation);
			if (copy_status == 2 || copy_status < 0 || service.clock_ms() >= browser_copy_due)
			{
				browser_copy_pending = false;
				notice = copy_status == 2 ? "Recovery code copied. Keep it somewhere private."
					: "Your browser could not copy the code. Save the full code shown here before continuing.";
			}
		}
		/* A restored identity may only replace the guest at the safe main menu */
		var in_menu = controller.network_mode_screen && controller.network_mode_page == "main";
		if (in_menu) service.activate_restored();
		if (opened && !in_menu) close();
		if (service.state == "expired" && in_menu)
		{
			sync_flush_local();
			service.sign_out();
			activate_guest();
			notice = "Your session ended. Sign in again, or play as a guest.";
		}
		if (service.signed_in() && service.account_id != known_account_id && in_menu)
		{
			clear_credential_inputs();
			username = ""; input_truncated.username = false;
			confirm_action = "";
			page = "profile";
			var guest_name = controller.client_username;
			if (AccountProfiles.use_account(service.account_id))
			{
				known_account_id = service.account_id;
				controller.client_username = AccountProfiles.read_string("username", guest_name);
				display_name = controller.client_username;
				controller.client_username_persistence_suppressed = false;
				controller.network_update_window_caption();
				sync_begin();
				set_focus("name");
			}
		}
		if (service.completion_serial != seen_completion)
		{
			seen_completion = service.completion_serial;
			sync_completed();
			if (service.last_success && (service.last_operation == "sign_in" || service.last_operation == "register"
			|| service.last_operation == "recover" || service.last_operation == "recovery_code" || service.last_operation == "delete_account"))
			{
				clear_credential_inputs();
				confirm_action = "";
			}
			if (service.last_success && (service.last_operation == "sign_in" || service.last_operation == "register")
			&& service.login_remember_choice && !service.remembered_on_device && service.vault_status != "")
				notice = service.vault_status;
			if (service.last_operation == "browser_logout" || service.last_operation == "browser_forget") notice = service.status_text;
			if (service.last_operation == "delete_account" && !service.signed_in())
			{
				var cache_removed = AccountProfiles.forget_account(known_account_id);
				activate_guest();
				notice = service.last_success ? (cache_removed ? "Account deleted. Your guest profile is still available."
					: "Account deleted. Its local cache could not be removed on this device.") : service.status_text;
			}
			if (service.last_success && service.last_operation == "export_account" && service.export_data != "")
			{
				if (service.browser_target) notice = "Your account data is ready. Choose Download account data.";
				else
				{
					var export_file = -1;
					try
					{
						var filename = "account_export_" + service.account_id + ".json";
						export_file = file_text_open_write(filename);
						file_text_write_string(export_file, service.export_data);
						file_text_close(export_file);
						export_file = -1;
						notice = "Saved " + filename + " in the game save folder.";
					}
					catch(export_error)
					{
						if (export_file >= 0) file_text_close(export_file);
						notice = "Could not save the account export on this device.";
					}
					service.export_data = "";
				}
			}
		}
		sync_update();
		if (service.recovery_code == "" && !service.signed_in() && opened)
		{
			if (service.restore_pending && focus != "continue_guest" && focus != "back") set_focus("continue_guest");
			else if (show_restore_prompt() && focus != "retry_sign_in" && focus != "password_sign_in"
			&& focus != "continue_guest" && focus != "back") set_focus("retry_sign_in");
		}
		if (service.recovery_code != "")
		{
			clear_credential_inputs();
			if (focus != "copy_code" && focus != "code_saved") set_focus("copy_code");
		}
	}

	open = function()
	{
		if (!controller.network_mode_screen || controller.network_mode_page != "main") return false;
		controller.client_save_username();
		opened = true;
		password_visible = false;
		restore_prompt_dismissed = false;
		notice = "";
		confirm_action = "";
		password = ""; input_truncated.password = false;
		recovery_input = ""; input_truncated.recovery = false;
		page = service.signed_in() ? "profile" : "sign_in";
		form_completion = service.completion_serial;
		display_name = controller.client_username;
		controller.network_mode_focus = "";
		controller.escape_exit_hold_reset();
		set_focus(service.signed_in() ? "name" : (service.restore_pending ? "continue_guest"
			: (show_restore_prompt() ? "retry_sign_in" : (service.configured ? "username" : "back"))));
		return true;
	}

	close = function()
	{
		if (service.recovery_code != "") return;
		/* Profile requests belong to the signed-in session and continue after this page closes */
		if (service.busy && service.request_kind != "save_profile" && service.request_kind != "load_profile"
		&& !service.restore_pending) service.cancel();
		opened = false;
		browser_copy_pending = false;
		password_visible = false;
		password = ""; input_truncated.password = false;
		recovery_input = ""; input_truncated.recovery = false;
		service.export_data = "";
		confirm_action = "";
		keyboard_string = "";
		controller.network_mode_focus = "";
		controller.network_mode_gamepad_focus = "account";
		controller.escape_exit_hold_reset();
	}

	add_control = function(key, label, top, enabled = true, kind = "button", height = 40)
	{
		var feedback_shift = 0;
		for (var i = 0; i < array_length(feedback_tops); i++)
			if (top > feedback_tops[i]) feedback_shift += 24;
		if (top > password_shift_after) top += password_extra_height;
		top += feedback_shift;
		array_push(controls, { key: key, label: label, kind: kind, enabled: enabled,
			x: panel_x + 28 * ui_scale, y: panel_y + top * ui_scale,
			width: panel_width - 56 * ui_scale, height: height * ui_scale });
	}

	field_feedback = function(key)
	{
		var value = key == "username" ? string_trim(username) : (key == "password" ? password : string_trim(recovery_input));
		var count = string_length(value);
		var typed = string_length(key == "username" ? username : (key == "password" ? password : recovery_input));
		var maximum = key == "username" ? 24 : (key == "password" ? 128 : 64);
		var reason = "";
		if (input_truncated[$ key]) return { count: count, typed: typed, maximum: maximum,
			reason: "Input was cut off. Clear this field and enter it again.",
			hint: "Input was cut off. Clear this field and enter it again.", valid: false };
		if (key == "username")
		{
			if (count == 0) reason = "Use 3 to 24 characters: A-Z, 0-9 or _.";
			else if (!service.valid_username(username)) reason = count < 3 ? "Use at least 3 characters."
				: (count > 24 ? "Use at most 24 characters." : "Use only A-Z, 0-9 or _." );
		}
		else if (key == "password")
		{
			if (count == 0) reason = "Use 12 to 128 characters.";
			else if (count < 12) reason = "Use at least 12 characters.";
			else if (count > 128) reason = "Use at most 128 characters. Showing the end.";
		}
		else if (!service.valid_recovery_code(string_lower(value))) reason = count != 64
			? "Enter all 64 recovery-code characters." : "Use only 0-9 and A-F.";
		var hint = reason;
		if (key != "recovery" && credential_has_escapes(key == "password" ? password : username))
		{
			if (hint != "") hint += " Escaped view.";
			else hint = credential_view(key == "password" ? password : username).shortened
				? "Escaped view. Showing the end." : "Escaped view: \\n, \\r, \\t, \\xNN and \\\\.";
		}
		if (hint == "" && key != "password" && value != (key == "username" ? username : recovery_input)) hint = "Outer spaces are ignored.";
		return { count: count, typed: typed, maximum: maximum, reason: reason, hint: hint, valid: reason == "" };
	}

	credential_has_escapes = function(value)
	{
		for (var i = 1; i <= string_length(value); i++)
		{
			var code = string_ord_at(value, i);
			if (code < 32 || code == 127 || code == 92) return true;
		}
		return false;
	}

	/// @description Bound the display by whole escaped tokens without changing the input
	credential_view = function(source)
	{
		var result = "";
		var shortened = false;
		var digits = "0123456789ABCDEF";
		for (var i = string_length(source); i >= 1; i--)
		{
			var code = string_ord_at(source, i);
			var token = string_char_at(source, i);
			if (code == 92) token = "\\\\";
			else if (code == 10) token = "\\n";
			else if (code == 13) token = "\\r";
			else if (code == 9) token = "\\t";
			else if (code < 32 || code == 127) token = "\\x" + string_char_at(digits, (code div 16) + 1) + string_char_at(digits, (code mod 16) + 1);
			if (string_length(token + result) > 128) { shortened = true; break; }
			result = token + result;
		}
		return { text: (shortened ? "..." : "") + result, shortened: shortened };
	}

	password_view = function() { return credential_view(password).text; }

	submission_ready = function(key)
	{
		if (service.busy || !service.configured || !service.supported_target) return false;
		if (!field_feedback("password").valid) return false;
		if (key == "confirm") return service.signed_in();
		if (service.signed_in() || !field_feedback("username").valid) return false;
		return key != "recover" || field_feedback("recovery").valid;
	}

	/// @description Wrap revealed text by character so spaces and every entered character remain visible
	password_display_lines = function(value, height, width)
	{
		var lines = [];
		var line = "";
		var scale = scr_render_text_scale(height, scr_render_text_font_for_text(value));
		for (var i = 1; i <= string_length(value); i++)
		{
			var character = string_char_at(value, i);
			if (line != "" && !scr_text_fits_width(line + character, scale, width))
			{
				array_push(lines, line);
				line = "";
			}
			line += character;
		}
		array_push(lines, line);
		return lines;
	}

	/// @description Keep the reveal action beside the label without reducing the editable field
	add_password_control = function(label, top, enabled)
	{
		add_control("password", label, top, enabled, "field", 40 + password_extra_height);
		password_shift_after = top;
		var can_toggle = enabled || (service.busy && service.configured && service.supported_target
			&& !service.browser_page_unsupported && password != "");
		add_control("show_password", password_visible ? "Hide password" : "Show password", top - 30, can_toggle, "button", 28);
		controls[array_length(controls) - 1].x = panel_x + panel_width - 192 * ui_scale;
		controls[array_length(controls) - 1].width = 164 * ui_scale;
	}

	status_message = function()
	{
		var status = notice != "" ? notice : service.status_text;
		if (notice == "" && service.signed_in() && page == "profile" && sync_status != "") status = sync_status;
		if (notice == "" && !service.signed_in() && !service.busy && service.recovery_code == ""
		&& !service.uncertain_result && service.completion_serial == form_completion)
		{
			status = "";
		}
		if (notice == "" && !service.signed_in() && (service.restore_pending || show_restore_prompt())) status = service.restore_status;
		if (notice == "" && !service.signed_in() && !service.restore_pending && !show_restore_prompt()
		&& page != "recover" && (focus == "keep_signed_in" || focus == "remember_duration"))
			status = !service.keep_signed_in ? (service.browser_target
				? "Off uses a browser session cookie for up to 12 hours. Reload can restore sign-in. Sign out on shared devices."
				: "Remember this device only if it is yours. Leave this off on shared devices.")
				: (service.remember_duration == "until_sign_out"
					? (service.browser_target ? "Stay signed in until you sign out, subject to browser storage limits. Recovery or revocation can also end it."
						: "Stay signed in until you sign out. Password recovery, deletion or server revocation can also end it.")
					: (service.browser_target ? "Stay signed in for up to 30 days, subject to browser storage limits. Reload does not extend the period."
						: "Stay signed in for up to 30 days. Reopening the game does not extend this period."));
		if (notice == "" && !service.browser_target && !service.signed_in() && !service.busy && !service.vault_available
		&& page != "recover" && !service.restore_pending && !show_restore_prompt())
			status = "Keep me signed in is unavailable on this device. You can still sign in for this session.";
		if (notice == "" && !service.signed_in() && service.restore_failed && !restore_prompt_dismissed)
			status = service.restore_status;
		if (!service.configured) status = service.availability_message != "" ? service.availability_message : "Account service is not available yet. You can still play as a guest.";
		if (!service.supported_target) status = "Accounts are available in the Windows and browser versions. You can still play as a guest.";
		if (sync_conflict && page == "profile") status = sync_status;
		if (sync_storage_failed && service.signed_in()) status = "Could not preserve pending changes on this device. Keep the game open until the cloud save succeeds.";
		if (service.vault_cleanup_failed && service.vault_status != "" && string_pos(service.vault_status, status) == 0)
			status += (status != "" ? " " : "") + service.vault_status;
		return status;
	}

	layout = function()
	{
		var gui_width = display_get_gui_width();
		var gui_height = display_get_gui_height();
		password_shift_after = 10000;
		password_extra_height = 0;
		feedback_tops = [];
		var has_password = !service.browser_page_unsupported && service.recovery_code == "" && (confirm_action == "delete_account" || confirm_action == "recovery_code"
			|| (confirm_action == "" && !service.signed_in() && !service.restore_pending && !show_restore_prompt()));
		if (has_password) feedback_tops = confirm_action != "" ? [250] : (page == "recover" ? [150, 230, 310] : [148, 220]);
		feedback_extra_height = array_length(feedback_tops) * 24;
		if (password_visible && has_password)
		{
			var lines = password_display_lines(password_view() + "|", 20, 524);
			password_extra_height = max(0, array_length(lines) * 24 - 4 + 16 - 40);
		}
		status_extra_height = max(0, scr_text_wrapped_height(status_message(), 16, 544, 3) - 48);
		var layout_height = 590 + password_extra_height + feedback_extra_height + status_extra_height;
		ui_scale = min(1, min((gui_width - 24) / 600, (gui_height - 24) / layout_height));
		ui_scale = max(0.25, ui_scale);
		panel_width = 600 * ui_scale;
		panel_height = layout_height * ui_scale;
		panel_x = (gui_width - panel_width) * 0.5;
		panel_y = (gui_height - panel_height) * 0.5;
		controls = [];
		if (service.recovery_code != "")
		{
			add_control("copy_code", "Copy recovery code", 350, !browser_copy_pending);
			add_control("code_saved", "I've saved my recovery code", 402, !browser_copy_pending);
		}
		else if (confirm_action != "")
		{
			if (confirm_action == "delete_account" || confirm_action == "recovery_code")
				add_password_control("Current password", 250, !service.busy);
			var label = confirm_action == "sign_out" ? "Sign out" : (confirm_action == "delete_account"
				? "Delete account" : (confirm_action == "recovery_code" ? "Replace recovery code"
				: (confirm_action == "use_cloud" ? "Use cloud profile" : (confirm_action == "keep_device" ? "Keep this device" : "Copy guest profile"))));
			add_control("confirm", label, 350, !service.busy && ((confirm_action != "delete_account" && confirm_action != "recovery_code") || submission_ready("confirm")));
			add_control("cancel_confirm", "Go back", 402, !service.busy);
		}
		else if (!service.signed_in() && service.restore_pending)
		{
			add_control("continue_guest", "Continue as guest", 350);
		}
		else if (show_restore_prompt())
		{
			add_control("retry_sign_in", "Retry sign-in", 300, !service.busy);
			add_control("password_sign_in", "Sign in with password", 350, !service.busy);
			add_control("continue_guest", "Continue as guest", 400);
		}
		else if (service.browser_page_unsupported && !service.signed_in())
		{
			add_control("unsupported_page", "Guest play is still available.", 180, false, "hint", 32);
		}
		else if (page == "recover" && !service.signed_in())
		{
			add_control("username", "Username", 150, !service.busy && service.configured, "field");
			add_control("recovery", "Recovery code", 230, !service.busy && service.configured, "field");
			add_password_control("New password", 310, !service.busy && service.configured);
			add_control("recover", "Set new password", 380, submission_ready("recover"));
			add_control("profile_page", "Back to sign in", 430, !service.busy);
		}
		else if (page == "manage" && service.signed_in())
		{
			var manage_top = service.remembered_on_device ? 150 : 180;
			add_control("export", service.browser_target && service.export_data != "" ? "Download account data" : "Export account data", manage_top, !service.busy);
			add_control("replace_code", "Replace recovery code", manage_top + 50, !service.busy);
			if (service.remembered_on_device)
			{
				add_control("forget_sign_in", "Stop remembering this device", manage_top + 100, !service.busy);
				manage_top += 50;
			}
			add_control("delete_account", "Delete account", manage_top + 100, !service.busy);
			add_control("sign_out", "Sign out", manage_top + 150, !service.busy);
			add_control("profile_page", "Back to profile", manage_top + 200, !service.busy);
		}
		else if (service.signed_in())
		{
			add_control("name", "Display name (shown to other players)", 170, true, "field");
			add_control("load", "Use cloud profile", 226, !service.busy && service.profile_loaded && is_struct(service.cloud_profile));
			if (sync_conflict) add_control("keep_device", "Keep this device", 270, !service.busy && service.profile_loaded);
			else if (sync_paused) add_control("retry_save", "Retry cloud save", 270, !service.busy);
			add_control("copy_guest", "Copy guest profile", 320, !service.busy && sync_ready && !sync_conflict && service.profile_loaded);
			add_control("refresh", "Refresh cloud profile", 370, !service.busy);
			add_control("manage", "Account settings", 420, !service.busy);
		}
		else
		{
			add_control("username", "Username", 148, !service.busy && service.configured, "field");
			add_password_control(page == "register" ? "New password" : "Password", 220, !service.busy && service.configured);
			{
				add_control("keep_signed_in", "Keep me signed in", 274,
					!service.busy && service.configured && (service.browser_target || service.vault_available), "toggle", 32);
				add_control("remember_duration", service.remember_duration == "until_sign_out" ? "Until I sign out" : "For 30 days", 274,
					!service.busy && service.configured && (service.browser_target || service.vault_available) && service.keep_signed_in, "button", 32);
				var choice_width = (panel_width - 64 * ui_scale) * 0.5;
				controls[array_length(controls) - 2].width = choice_width;
				controls[array_length(controls) - 1].x = panel_x + panel_width * 0.5 + 4 * ui_scale;
				controls[array_length(controls) - 1].width = choice_width;
			}
			if (page == "register")
			{
				add_control("register", "Create account", 320, submission_ready("register"));
				add_control("sign_in_page", "Back to sign in", 370, !service.busy);
			}
			else
			{
				add_control("sign_in", "Sign in", 320, submission_ready("sign_in"));
				add_control("register_page", "Create a new account", 370, !service.busy && service.configured);
				add_control("recover_page", "Recover account", 420, !service.busy && service.configured);
			}
		}
		if (service.recovery_code == "") add_control("back", service.busy && service.request_kind != "load_profile"
			&& service.request_kind != "save_profile" && !service.restore_pending ? "Leave request" : "Back", 540 + status_extra_height);
	}

	save_draft = function(from_guest)
	{
		if (!service.signed_in() || known_account_id != service.account_id
		|| AccountProfiles.account_id != service.account_id)
		{
			confirm_action = "";
			notice = "Sign in again before saving a cloud profile.";
			return;
		}
		var draft = from_guest
			? AccountProfiles.cloud_from_profile(AccountProfiles.snapshot_guest())
			: AccountProfiles.capture_cloud(display_name);
		if (!is_struct(draft) || string_length(draft.display_name) < 3)
		{
			notice = "Choose a display name with 3 to 16 letters or numbers.";
			confirm_action = "";
			return;
		}
		if (!sync_ready || sync_conflict || !sync_apply(draft, true))
		{
			notice = "The profile could not be copied. Refresh the cloud profile and try again.";
			confirm_action = "";
			return;
		}
		sync_observed = sync_capture();
		sync_dirty = !profile_equal(sync_observed, sync_baseline);
		sync_due = service.clock_ms();
		sync_record_pending();
		sync_status = "Guest choices copied. Saving to your account automatically...";
		confirm_action = "";
		notice = "";
	}

	action = function(key)
	{
		if (!controller.network_mode_screen || controller.network_mode_page != "main") { close(); return; }
		if (key == "back") { close(); return; }
		if (key == "cancel_confirm")
		{
			if (service.busy) return;
			confirm_action = "";
			clear_credential_inputs();
			set_focus(page == "manage" ? "profile_page" : "name");
			return;
		}
		if (service.busy && key != "copy_code" && key != "code_saved" && key != "show_password"
		&& !(key == "continue_guest" && service.restore_pending)) return;
		if ((key == "sign_in" || key == "register" || key == "recover"
		|| (key == "confirm" && (confirm_action == "delete_account" || confirm_action == "recovery_code")))
		&& !submission_ready(key)) return;
		notice = "";
		switch (key)
		{
			case "show_password":
				if (service.configured && service.supported_target && !service.browser_page_unsupported
				&& (!service.busy || password != "")) password_visible = !password_visible;
				break;
			case "keep_signed_in":
				if (!service.set_keep_signed_in(!service.keep_signed_in))
					notice = "Could not change the saved sign-in preference on this device.";
				break;
			case "remember_duration":
				if (service.keep_signed_in && !service.set_remember_duration(service.remember_duration == "30_days" ? "until_sign_out" : "30_days"))
					notice = "Could not change the sign-in duration.";
				break;
			case "retry_sign_in":
				restore_prompt_dismissed = false;
				service.restore_retry();
				set_focus("continue_guest");
				break;
			case "password_sign_in":
				restore_prompt_dismissed = true;
				set_auth_page("sign_in");
				break;
			case "continue_guest":
				if (!service.pause_restore_for_guest())
				{
					notice = "Account state changed. Open Account again to continue.";
					break;
				}
				restore_prompt_dismissed = true;
				activate_guest();
				close();
				break;
			case "forget_sign_in":
				if (service.stop_remembering())
					notice = service.browser_target ? "" : "This device will ask you to sign in next time. You are still signed in now.";
				else notice = service.vault_status != "" ? service.vault_status : "Could not remove the saved sign-in.";
				set_focus("profile_page");
				break;
			case "copy_code":
				if (service.browser_target)
				{
					browser_copy_generation = html5_diag_copy_generation() + 1;
					browser_copy_pending = html5_diag_copy_text(service.recovery_code) >= 1;
					browser_copy_due = service.clock_ms() + 10000;
					notice = browser_copy_pending ? "Copying recovery code..."
						: "Your browser could not copy the code. Save the full code shown here before continuing.";
				}
				else
				{
					clipboard_set_text(service.recovery_code);
					notice = "Recovery code copied. Keep it somewhere private.";
				}
				break;
			case "code_saved":
				if (browser_copy_pending) break;
				/* Remove only our own secret from the clipboard, preserving any newer copied text */
				if (!service.browser_target && clipboard_get_text() == service.recovery_code) clipboard_set_text("");
				service.recovery_code = "";
				clear_credential_inputs();
				page = service.signed_in() ? "profile" : "sign_in";
				set_focus(service.signed_in() ? "name" : "username");
				break;
			case "manage": page = "manage"; set_focus("profile_page"); break;
			case "profile_page":
				page = service.signed_in() ? "profile" : "sign_in";
				form_completion = service.completion_serial;
				password = ""; input_truncated.password = false;
				password_visible = false;
				recovery_input = ""; input_truncated.recovery = false;
				set_focus(service.signed_in() ? "name" : "username");
				break;
			case "sign_in_page": set_auth_page("sign_in"); break;
			case "register_page": set_auth_page("register"); break;
			case "recover_page": set_auth_page("recover"); break;
			case "recover":
				if (page != "recover" || service.signed_in()) break;
				service.recover(username, recovery_input, password);
				set_focus("recover");
				break;
			case "export":
				if (service.browser_target && service.export_data != "")
				{
					var downloaded = html5_download_account_json("account_export_" + service.account_id + ".json", service.export_data) == 1;
					notice = downloaded ? "Download requested. Check your browser downloads."
						: "Your browser could not start the download. Try again.";
					if (downloaded) service.export_data = "";
				}
				else service.export_account();
				break;
			case "delete_account":
			case "replace_code":
				confirm_action = key == "delete_account" ? "delete_account" : "recovery_code";
				password = ""; input_truncated.password = false;
				password_visible = false;
				set_focus("password");
				break;
			case "sign_in":
				if (page != "sign_in" || service.signed_in()) break;
				service.sign_in(username, password);
				set_focus("sign_in");
				break;
			case "register":
				if (page != "register" || service.signed_in()) break;
				service.register(username, password);
				set_focus("register");
				break;
			case "refresh": sync_retry_now(); break;
			case "retry_save": sync_retry_now(); break;
			case "load":
				confirm_action = "use_cloud";
				set_focus("cancel_confirm");
				break;
			case "keep_device": confirm_action = "keep_device"; set_focus("cancel_confirm"); break;
			case "copy_guest": confirm_action = "copy_guest"; set_focus("cancel_confirm"); break;
			case "sign_out": confirm_action = "sign_out"; set_focus("cancel_confirm"); break;
			case "confirm":
				if (confirm_action == "sign_out")
				{
					if (!sync_flush_local())
					{
						notice = "Could not preserve your pending changes. Retry the cloud save or choose Use cloud profile before signing out.";
						break;
					}
					service.sign_out();
					activate_guest();
					confirm_action = "";
					password = ""; input_truncated.password = false;
					password_visible = false;
					set_focus("username");
					notice = service.browser_target ? service.status_text : "Signed out. Your guest profile is ready."
						+ (service.vault_status != "" ? " " + service.vault_status : "");
				}
				else if (confirm_action == "delete_account" || confirm_action == "recovery_code")
				{
					service.password_action(confirm_action, password);
					set_focus("confirm");
				}
				else if (confirm_action == "use_cloud" || confirm_action == "keep_device")
				{
					var restored = confirm_action == "use_cloud" ? sync_use_cloud() : sync_keep_device();
					confirm_action = "";
					set_focus("name");
					if (!restored) notice = "The profile could not be restored. Refresh the cloud profile and try again.";
				}
				else save_draft(true);
				break;
		}
	}

	update_input = function()
	{
		if (!opened) return false;
		if (!controller.network_mode_screen || controller.network_mode_page != "main") { close(); return false; }
		layout();
		var mouse_gui_x = scr_gui_mouse_x(0);
		var mouse_gui_y = scr_gui_mouse_y(0);
		hover = "";
		for (var i = 0; i < array_length(controls); i++)
		{
			var control = controls[i];
			if (mouse_gui_x >= control.x && mouse_gui_x <= control.x + control.width
			&& mouse_gui_y >= control.y && mouse_gui_y <= control.y + control.height)
			{
				hover = control.key;
				if (mouse_check_button_pressed(mb_left) && control.enabled)
				{
					/* Revealing text must not replace the focused field's input buffer */
					if (control.key != "show_password") set_focus(control.key);
					if (control.kind == "button" || control.kind == "toggle") action(control.key);
					return true;
				}
			}
		}
		if (keyboard_check_pressed(vk_escape)
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face2)))
		{
			if (service.recovery_code != "") { set_focus("code_saved"); }
			else if (confirm_action != "" && service.busy) close();
			else if (confirm_action != "") { confirm_action = ""; password = ""; input_truncated.password = false; password_visible = false; set_focus(page == "manage" ? "profile_page" : "name"); }
			else if (service.busy) close();
			else if (!service.signed_in() && page != "sign_in") set_auth_page("sign_in");
			else if (service.signed_in() && page != "profile") { page = "profile"; password = ""; input_truncated.password = false; password_visible = false; recovery_input = ""; input_truncated.recovery = false; set_focus("name"); }
			else close();
			return true;
		}

		var move = 0;
		if (keyboard_check_pressed(vk_tab)) move = keyboard_check(vk_shift) ? -1 : 1;
		if (gamepad_is_connected(0) && current_time >= navigation_due)
		{
			var up = gamepad_button_check(0, gp_padu) || gamepad_axis_value(0, gp_axislv) < -0.65;
			var down = gamepad_button_check(0, gp_padd) || gamepad_axis_value(0, gp_axislv) > 0.65;
			if (up != down) { move = up ? -1 : 1; navigation_due = current_time + 180; }
		}
		if (move != 0)
		{
			var index = -1;
			for (var i = 0; i < array_length(controls); i++) if (controls[i].key == focus) index = i;
			for (var step = 0; step < array_length(controls); step++)
			{
				index = (index + move + array_length(controls)) mod array_length(controls);
				if (controls[index].enabled) { set_focus(controls[index].key); break; }
			}
			return true;
		}
		if ((!service.busy || (focus == "name" && service.signed_in()))
		&& (focus == "username" || focus == "password" || focus == "name" || focus == "recovery"))
		{
			var previous = focus == "username" ? username : (focus == "password" ? password : (focus == "recovery" ? recovery_input : display_name));
			/* Keep invalid overlength credentials visible instead of turning them into a valid prefix */
			var limit = focus == "name" ? 16 : 1024;
			scr_text_input_update("account_" + focus, previous, limit, focus != "name");
			if (focus != "name" && (global.text_input_truncated || string_length(keyboard_string) > limit)) input_truncated[$ focus] = true;
			var value = string_copy(focus != "name" ? keyboard_string : scr_text_input_clean_paste(keyboard_string, limit), 1, limit);
			if (focus == "name") value = chat_filter_username_input(value);
			if ((keyboard_check(vk_control) || keyboard_check_pressed(vk_control) || keyboard_check_released(vk_control))
			&& keyboard_check_pressed(ord("A"))) value = "";
			if (focus != "name" && value == "") input_truncated[$ focus] = false;
			if (focus == "username") username = value;
			else if (focus == "password") password = value;
			else if (focus == "recovery") recovery_input = value;
			else sync_set_name(value);
			keyboard_string = value;
		}
		if (keyboard_check_pressed(vk_enter)
		|| ((focus == "keep_signed_in" || focus == "remember_duration" || focus == "show_password") && keyboard_check_pressed(vk_space))
		|| (gamepad_is_connected(0) && gamepad_button_check_pressed(0, gp_face1)))
		{
			var selected = focus;
			if (focus == "username" || focus == "password" || focus == "recovery")
				selected = confirm_action != "" ? "confirm" : (page == "recover" ? "recover" : (page == "register" ? "register" : "sign_in"));
			for (var i = 0; i < array_length(controls); i++)
			{
				if (controls[i].key == selected && controls[i].enabled
				&& (controls[i].kind == "button" || controls[i].kind == "toggle"))
				{
					action(selected);
					break;
				}
			}
		}
		return true;
	}

	draw = function()
	{
		if (!opened) return;
		layout();
		draw_set_alpha(0.97);
		draw_set_colour(make_color_rgb(8, 9, 10));
		draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(24, 26, 30));
		draw_rectangle(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, false);
		draw_set_colour(make_color_rgb(94, 99, 110));
		draw_rectangle(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, true);
		draw_set_halign(fa_center);
		draw_set_valign(fa_top);
		draw_set_colour(c_white);
		var heading = "Account";
		if (service.recovery_code != "") heading = "Save your recovery code";
		else if (service.browser_page_unsupported) heading = "Browser accounts";
		else if (confirm_action == "sign_out") heading = "Sign out";
		else if (confirm_action == "delete_account") heading = "Delete account";
		else if (confirm_action == "recovery_code") heading = "Replace recovery code";
		else if (confirm_action == "use_cloud" || confirm_action == "keep_device") heading = "Choose a profile";
		else if (confirm_action != "") heading = "Copy guest profile";
		else if (!service.signed_in() && service.restore_pending) heading = "Restoring your account";
		else if (show_restore_prompt()) heading = "Sign-in needs attention";
		else if (!service.signed_in()) heading = page == "register" ? "Create account" : (page == "recover" ? "Recover account" : "Sign in");
		else if (page == "manage") heading = "Account settings";
		scr_render_text(panel_x + panel_width * 0.5, panel_y + 22 * ui_scale, heading, 30 * ui_scale, panel_width - 48 * ui_scale);
		draw_set_halign(fa_left);
		draw_set_colour(make_color_rgb(190, 194, 204));
		var login_label = service.account_username;
		if (string_length(login_label) > 48) login_label = string_copy(login_label, 1, 30) + "..." + string_copy(login_label, string_length(login_label) - 14, 15);
		var summary = service.signed_in() ? "Username (sign-in): " + login_label + "\nPrivate. Display name is public."
			: "Use your existing account to restore your saved profile. You can also play as a guest.";
		if (service.recovery_code != "") summary = "Save this one recovery code. It is shown once. Keep it private. Losing both your password and code means losing access.";
		else if (service.browser_page_unsupported) summary = "Accounts are not available on this browser page. Choose Back to keep playing as a guest.";
		else if (confirm_action == "sign_out") summary = sync_dirty || is_struct(sync_inflight)
			? "Some profile changes are not saved to your account yet. They stay on this device for your next sign-in. They will not appear on another device yet. Sign out and return to your guest profile?"
			: "Sign out and return to your separate guest profile?";
		else if (confirm_action == "delete_account") summary = "Permanently delete your account and cloud profile? Your local guest profile stays. Private backups may retain older copies. Enter your current password to confirm.";
		else if (confirm_action == "recovery_code") summary = "Replace your recovery code? The previous code will stop working. Enter your current password to confirm.";
		else if (confirm_action == "use_cloud") summary = "Use your saved cloud profile? This replaces this device's pending profile choices. Your separate guest profile stays unchanged.";
		else if (confirm_action == "keep_device") summary = "Keep this device's current profile and replace the cloud choices? These choices will then be available on your other devices.";
		else if (confirm_action != "")
		{
			summary = "Copy your guest choices into this account and save them to the cloud? Your guest profile stays unchanged.\n\n"
				+ "This copies your public name and built-in character and pet choices. Custom artwork stays on this device.";
		}
		else if (!service.signed_in() && service.restore_pending) summary = "Checking this device's saved sign-in. Continue as a guest to pause this check. Your saved sign-in stays for next time.";
		else if (show_restore_prompt()) summary = "Your saved sign-in could not be checked. Retry, use your password, or play as a guest. Guest play keeps your saved sign-in for next time.";
		else if (page == "recover") summary = "Reset your password with your private recovery code. Other devices will be signed out, and you'll receive a new code.";
		else if (page == "register" && !service.signed_in()) summary = "Create an optional account to save your profile across devices. You'll get a private recovery code to keep.";
		else if (page == "manage") summary = "Signed in as " + login_label + ".\nYour username is private. Exports contain private data.";
		scr_render_text_wrapped(panel_x + 28 * ui_scale, panel_y + 70 * ui_scale,
			summary, 18 * ui_scale, panel_width - 56 * ui_scale, 4 * ui_scale);
		if (service.recovery_code != "")
		{
			draw_set_colour(make_color_rgb(190, 194, 204));
			scr_render_text(panel_x + 28 * ui_scale, panel_y + 150 * ui_scale,
				"One recovery code (64 characters)", 17 * ui_scale, panel_width - 56 * ui_scale);
			draw_set_colour(make_color_rgb(8, 8, 8));
			draw_rectangle(panel_x + 28 * ui_scale, panel_y + 180 * ui_scale,
				panel_x + panel_width - 28 * ui_scale, panel_y + 238 * ui_scale, false);
			draw_set_colour(c_gray);
			draw_rectangle(panel_x + 28 * ui_scale, panel_y + 180 * ui_scale,
				panel_x + panel_width - 28 * ui_scale, panel_y + 238 * ui_scale, true);
			draw_set_colour(c_white);
			scr_render_text(panel_x + 38 * ui_scale, panel_y + 198 * ui_scale,
				service.recovery_code, 18 * ui_scale, panel_width - 76 * ui_scale);
		}
		var status = status_message();
		draw_set_colour(make_color_rgb(200, 205, 218));
		scr_render_text_wrapped(panel_x + 28 * ui_scale, panel_y + (480 + password_extra_height + feedback_extra_height) * ui_scale,
			status, 16 * ui_scale, panel_width - 56 * ui_scale, 3 * ui_scale);
		for (var i = 0; i < array_length(controls); i++)
		{
			var control = controls[i];
			if (control.kind == "field")
			{
				var credential = control.key == "username" || control.key == "password" || control.key == "recovery";
				var feedback = credential ? field_feedback(control.key) : undefined;
				var invalid = credential && !feedback.valid;
				draw_set_halign(fa_left);
				draw_set_colour(invalid ? make_color_rgb(255, 150, 150) : c_ltgray);
				var label = control.label + (credential ? " (" + (feedback.typed != feedback.count ? string(feedback.typed) + " typed, " : "")
					+ string(feedback.count) + "/" + string(feedback.maximum) + (feedback.typed != feedback.count ? " used" : "") + ")" : "");
				scr_render_text(control.x, control.y - 24 * ui_scale, label, 17 * ui_scale,
					control.key == "password" ? control.width - 180 * ui_scale : control.width);
				draw_set_colour(make_color_rgb(8, 8, 8));
				draw_rectangle(control.x, control.y, control.x + control.width, control.y + control.height, false);
				draw_set_colour(invalid ? make_color_rgb(255, 125, 125) : (focus == control.key ? c_white : c_gray));
				draw_rectangle(control.x, control.y, control.x + control.width, control.y + control.height, true);
				if (invalid && focus == control.key)
				{
					draw_set_colour(c_white);
					draw_rectangle(control.x - 2 * ui_scale, control.y - 2 * ui_scale, control.x + control.width + 2 * ui_scale, control.y + control.height + 2 * ui_scale, true);
				}
				var value = control.key == "username" ? credential_view(username).text : (control.key == "password" ? (password_visible ? password_view() : string_repeat("*", min(128, string_length(password)))) : (control.key == "recovery" ? string_repeat("*", min(64, string_length(recovery_input))) : display_name));
				if (focus == control.key && (current_time div 500) mod 2 == 0) value += "|";
				draw_set_colour(!control.enabled ? c_gray : (invalid ? make_color_rgb(255, 150, 150) : c_white));
				if (control.key == "password" && password_visible)
				{
					var lines = password_display_lines(value, 20 * ui_scale, control.width - 20 * ui_scale);
					for (var line = 0; line < array_length(lines); line++)
						scr_render_text(control.x + 10 * ui_scale, control.y + (8 + line * 24) * ui_scale,
							lines[line], 20 * ui_scale);
				}
				else
				{
					if (credential)
					{
						var scale = scr_render_text_scale(20 * ui_scale);
						var preview = value;
						while (string_length(preview) > 0 && !scr_text_fits_width(preview, scale, control.width - 20 * ui_scale))
							preview = "..." + string_delete(preview, 1, string_copy(preview, 1, 3) == "..." ? 4 : 1);
						value = preview;
					}
					scr_render_text(control.x + 10 * ui_scale, control.y + 8 * ui_scale,
						value, 20 * ui_scale, credential ? -1 : control.width - 20 * ui_scale);
				}
				if (credential && feedback.hint != "")
				{
					draw_set_colour(invalid ? make_color_rgb(255, 150, 150) : c_ltgray);
					scr_render_text(control.x, control.y + control.height + 4 * ui_scale,
						feedback.hint, 16 * ui_scale, control.width);
				}
			}
			else if (control.kind == "hint")
			{
				draw_set_halign(fa_left);
				draw_set_colour(c_ltgray);
				scr_render_text(control.x, control.y + 7 * ui_scale, control.label, 17 * ui_scale, control.width);
			}
			else if (control.kind == "toggle")
			{
				/* Match the existing social-card checkbox inside the shared menu button */
				scr_draw_menu_button(control.x, control.y, control.width, control.height, "",
					hover == control.key, focus == control.key, control.enabled, false, false, 1);
				var box_size = 18 * ui_scale;
				var box_x = control.x + 10 * ui_scale;
				var box_y = control.y + (control.height - box_size) * 0.5;
				draw_set_colour(make_color_rgb(18, 20, 24));
				draw_rectangle(box_x, box_y, box_x + box_size, box_y + box_size, false);
				draw_set_colour(control.enabled ? make_color_rgb(220, 220, 224) : c_gray);
				draw_rectangle(box_x, box_y, box_x + box_size, box_y + box_size, true);
				if (service.keep_signed_in)
				{
					draw_set_colour(control.enabled ? make_color_rgb(126, 245, 150) : c_gray);
					draw_line_width(box_x + 4 * ui_scale, box_y + 10 * ui_scale,
						box_x + 8 * ui_scale, box_y + 14 * ui_scale, 2 * ui_scale);
					draw_line_width(box_x + 8 * ui_scale, box_y + 14 * ui_scale,
						box_x + 15 * ui_scale, box_y + 4 * ui_scale, 2 * ui_scale);
				}
				draw_set_halign(fa_left);
				draw_set_colour(control.enabled ? c_white : c_gray);
				scr_render_text(control.x + 36 * ui_scale, control.y + 7 * ui_scale,
					control.label, 17 * ui_scale, control.width - 46 * ui_scale);
			}
			else
			{
				scr_draw_menu_button(control.x, control.y, control.width, control.height, control.label,
					hover == control.key, focus == control.key, control.enabled, control.key == "back", false, 19 * ui_scale);
			}
		}
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		draw_set_colour(c_white);
	}
}
