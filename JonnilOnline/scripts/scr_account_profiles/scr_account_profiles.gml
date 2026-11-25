#macro AccountProfiles scr_get_account_profiles()

/// @description Return the built-in character identities supported by the cloud profile schema
function jonnil_account_character_keys()
{
	return ["player1", "player2", "player3"];
}

/// @description Return the built-in pet identities, including putting the pet away
function jonnil_account_pet_keys()
{
	return ["", "player1", "player2", "player3"];
}

/// @description Test an exact built-in character key without trusting installed custom packages
function jonnil_account_builtin_character(raw_key)
{
	if (!is_string(raw_key)) return false;
	var keys = jonnil_account_character_keys();
	for (var i = 0; i < array_length(keys); i++)
	{
		if (raw_key == keys[i]) return true;
	}
	return false;
}

/// @description Test an exact built-in pet key or the empty no-pet choice
function jonnil_account_builtin_pet(raw_key)
{
	return is_string(raw_key) && (raw_key == "" || jonnil_account_builtin_character(raw_key));
}

/// @description Keep the original guest profile separate from each account's device-local cache
function scr_account_profiles() constructor
{
	/* Account caches contain profile choices only. Passwords and session tokens stay in memory */
	account_id = "";
	guest_file = "client_settings.ini";
	profile_section = "profile";

	/// @description Accept a bounded opaque ID that cannot escape its cache filename
	valid_account_id = function(raw_id)
	{
		if (!is_string(raw_id)) return false;
		var count = string_length(raw_id);
		if (count < 1 || count > 64) return false;
		for (var i = 1; i <= count; i++)
		{
			if (string_pos(string_char_at(raw_id, i), "abcdefghijklmnopqrstuvwxyz0123456789_-") <= 0) return false;
		}
		return true;
	}

	/// @description Return the active profile filename without changing device or social settings
	active_file = function()
	{
		return account_id == "" ? guest_file : "account_profile_" + account_id + ".ini";
	}

	/// @description Restrict this store to the three profile choices rather than credentials or device settings
	allowed_key = function(key)
	{
		return key == "username" || key == "character_key" || key == "pet_key";
	}

	/// @description Read one choice from a selected profile file without creating missing storage
	read_file_string = function(filename, key, fallback)
	{
		if (!allowed_key(key)) return fallback;
		try
		{
			if (!file_exists(filename)) return fallback;
			ini_open(filename);
			var value = ini_read_string(profile_section, key, fallback);
			ini_close();
			return value;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
			debug_error("Could not load local profile choice.");
			return fallback;
		}
	}

	/// @description Read a guest choice or the active account's device cache
	read_string = function(key, fallback)
	{
		return read_file_string(active_file(), key, fallback);
	}

	/// @description Save one choice without changing another profile or any device settings
	write_string = function(key, value)
	{
		if (!allowed_key(key) || !is_string(value)) return false;
		try
		{
			ini_open(active_file());
			ini_write_string(profile_section, key, value);
			ini_close();
			return true;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
			debug_error("Could not save local profile choice.");
			return false;
		}
	}

	/// @description Read account-owned pending cloud choices without storing credentials
	read_cloud_sync = function()
	{
		if (account_id == "") return undefined;
		var temporary_buffer = -1;
		try
		{
			if (!file_exists(active_file())) return undefined;
			ini_open(active_file());
			var encoded = ini_read_string("cloud_sync", "pending_b64", "");
			ini_close();
			if (encoded == "" || string_byte_length(encoded) > 8192) return undefined;
			temporary_buffer = buffer_base64_decode(encoded);
			if (temporary_buffer < 0) return undefined;
			if (buffer_get_size(temporary_buffer) > 4097)
			{
				buffer_delete(temporary_buffer);
				return undefined;
			}
			var text = buffer_read(temporary_buffer, buffer_string);
			buffer_delete(temporary_buffer);
			temporary_buffer = -1;
			if (string_byte_length(text) > 4096) return undefined;
			var result = json_parse(text);
			return is_struct(result) ? result : undefined;
		}
		catch(e)
		{
			if (temporary_buffer >= 0 && buffer_exists(temporary_buffer)) buffer_delete(temporary_buffer);
			try { ini_close(); } catch(close_error) {}
			return undefined;
		}
	}

	/// @description Preserve a pending profile and its verified baseline in this account's local cache
	write_cloud_sync = function(value)
	{
		if (account_id == "" || !is_struct(value)) return false;
		var temporary_buffer = -1;
		try
		{
			var text = json_stringify(value);
			if (string_byte_length(text) > 4096) return false;
			/* INI strings do not escape JSON quotes. Encode the UTF-8 string including its terminator */
			temporary_buffer = buffer_create(string_byte_length(text) + 1, buffer_fixed, 1);
			buffer_write(temporary_buffer, buffer_string, text);
			var encoded = buffer_base64_encode(temporary_buffer, 0, buffer_tell(temporary_buffer));
			buffer_delete(temporary_buffer);
			temporary_buffer = -1;
			ini_open(active_file());
			ini_write_string("cloud_sync", "pending_b64", encoded);
			ini_close();
			return true;
		}
		catch(e)
		{
			if (temporary_buffer >= 0 && buffer_exists(temporary_buffer)) buffer_delete(temporary_buffer);
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Remove only acknowledged cloud-save metadata, preserving local choices
	clear_cloud_sync = function()
	{
		if (account_id == "") return false;
		try
		{
			if (!file_exists(active_file())) return true;
			ini_open(active_file());
			ini_section_delete("cloud_sync");
			ini_close();
			return true;
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Reload selection caches after changing owners, without persisting or broadcasting choices
	reload_selections = function()
	{
		var characters = scr_get_player_characters();
		var pets = scr_get_pets();
		characters.selected_key = characters.default_key;
		characters.loaded_selection = false;
		pets.selected_key = "";
		pets.loaded_selection = false;
		characters.load_selected_key();
		pets.load_selected_key();
	}

	/// @description Return to the untouched guest profile. Call only outside a gameplay session
	use_guest = function()
	{
		account_id = "";
		reload_selections();
		return true;
	}

	/// @description Remove only the deleted account's local profile cache, preserving guest and device settings
	forget_account = function(raw_id)
	{
		if (!valid_account_id(raw_id)) return false;
		var filename = "account_profile_" + raw_id + ".ini";
		try { if (file_exists(filename)) file_delete(filename); }
		catch(cache_error) { return false; }
		return !file_exists(filename);
	}

	/// @description Activate only this account's cache. Call only outside a gameplay session
	use_account = function(raw_id)
	{
		if (!valid_account_id(raw_id)) return false;
		account_id = raw_id;
		reload_selections();
		return true;
	}

	/// @description Read guest choices explicitly for an optional import, preserving custom local keys
	snapshot_guest = function()
	{
		return
		{
			display_name: read_file_string(guest_file, "username", ""),
			character_key: read_file_string(guest_file, "character_key", "player1"),
			pet_key: read_file_string(guest_file, "pet_key", "")
		};
	}

	/// @description Create an upload allowlist and explain choices that cannot travel between devices yet
	cloud_from_profile = function(profile)
	{
		if (!is_struct(profile)) return undefined;
		if (!variable_struct_exists(profile, "display_name") || !is_string(profile.display_name)
		|| !variable_struct_exists(profile, "character_key") || !is_string(profile.character_key)
		|| !variable_struct_exists(profile, "pet_key") || !is_string(profile.pet_key)) return undefined;
		var character_local_only = !jonnil_account_builtin_character(profile.character_key);
		var pet_local_only = !jonnil_account_builtin_pet(profile.pet_key);
		return
		{
			display_name: chat_filter_username_input(profile.display_name),
			character_key: character_local_only ? "player1" : profile.character_key,
			pet_key: pet_local_only ? "" : profile.pet_key,
			character_local_only: character_local_only,
			pet_local_only: pet_local_only,
			preserved_character: character_local_only,
			preserved_pet: pet_local_only
		};
	}

	/// @description Capture the active local choices for an explicit cloud save, excluding custom artwork
	capture_cloud = function(display_name)
	{
		return cloud_from_profile(
		{
			display_name: string(display_name),
			character_key: scr_get_player_characters().load_selected_key(),
			pet_key: scr_get_pets().load_selected_key()
		});
	}

	/// @description Apply validated cloud choices only to an account, keeping custom local equipment unless explicitly replaced
	apply_cloud = function(profile, fallback_display_name = "", preserve_custom = true)
	{
		var result = { ok: false, display_name: "", character_key: "player1", pet_key: "",
			preserved_character: false, preserved_pet: false };
		if (account_id == "" || !is_struct(profile)) return result;
		if (!variable_struct_exists(profile, "character_key") || !jonnil_account_builtin_character(profile.character_key)
		|| !variable_struct_exists(profile, "pet_key") || !jonnil_account_builtin_pet(profile.pet_key)) return result;
		var display_name = variable_struct_exists(profile, "display_name") ? profile.display_name : fallback_display_name;
		if (!is_string(display_name) || chat_filter_username_input(display_name) != display_name
		|| string_length(display_name) < 3) return result;

		var characters = scr_get_player_characters();
		var pets = scr_get_pets();
		var previous_character = characters.load_selected_key();
		var previous_pet = pets.load_selected_key();
		result.preserved_character = preserve_custom && characters.is_installed_custom(previous_character);
		result.preserved_pet = preserve_custom && previous_pet != "" && characters.is_installed_custom(previous_pet);
		result.display_name = display_name;
		result.character_key = result.preserved_character ? previous_character : profile.character_key;
		result.pet_key = result.preserved_pet ? previous_pet : profile.pet_key;

		/* Write all three fields together before rebinding the loaded selections */
		try
		{
			ini_open(active_file());
			ini_write_string(profile_section, "username", result.display_name);
			ini_write_string(profile_section, "character_key", result.character_key);
			ini_write_string(profile_section, "pet_key", result.pet_key);
			ini_close();
		}
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
			debug_error("Could not save restored account profile.");
			return result;
		}
		reload_selections();
		result.character_key = characters.load_selected_key();
		result.pet_key = pets.load_selected_key();
		result.ok = true;
		return result;
	}
}

/// @description Return the shared profile store without loading any account credentials
function scr_get_account_profiles()
{
	static profiles = new scr_account_profiles();
	return profiles;
}
