#macro PlayerCharacters scr_get_player_characters()

/// @description Test text against the characters used by package-key sanitization
/// @param {String} ch Character examined by safe_folder_key
/// @returns {Bool} Whether its lowercase form occurs in the package-key character set
function scr_player_character_is_key_char_allowed(ch)
{
	/* lower converts this candidate character to lowercase so key validation accepts either letter
	case consistently */
	var lower = string_lower(string(ch));

	/* A key character may be a lowercase letter, digit, underscore or hyphen. Other punctuation cannot
	enter a filesystem-safe custom basename */
	return string_pos(lower, "abcdefghijklmnopqrstuvwxyz0123456789_-") > 0;
}

/// @description Own official, installed, and remote character entries, cached sprite sheets, saved selection, and PNG transfers
function scr_player_characters() constructor
{
	/* default_key identifies the bundled fallback character used when a selection or requested key
	cannot be resolved */
	default_key = "player1";

	/* custom_prefix marks custom keys, separating installed and network custom identities from bundled
	character keys */
	custom_prefix = "custom:";

	/* settings_file is the client INI used for saved selection and browser installation metadata */
	settings_file = "client_settings.ini";

	/* settings_section and settings_key locate the chosen character under profile/character_key */
	settings_section = "profile";
	settings_key = "character_key";

	/* official_folder_name identifies bundled packages and custom_folder_name identifies installed
	custom packages */
	official_folder_name = "Characters";
	custom_folder_name = "custom_characters";

	/* temp_cache_folder_name names this game's temporary root, and temp_character_cache_folder_name
	contains received character packages beneath it */
	temp_cache_folder_name = "JonnilOnline";
	temp_character_cache_folder_name = "character_cache";

	/* network_custom_separator separates a custom basename and its content hash in a network key */
	network_custom_separator = ":";

	/* character_chunk_size limits each outgoing base64 fragment to 12000 characters */
	character_chunk_size = 12000;

	/* character_max_bytes caps a transferred PNG at 262144 bytes, or 256 KiB. character_max_chunks
	caps its fragment count at 64 */
	character_max_bytes = 262144;
	character_max_chunks = 64;

	/* expected_sheet_w and expected_sheet_h require a 48 by 76 pixel PNG matching the character frame
	grid */
	expected_sheet_w = 48;
	expected_sheet_h = 76;

	/* frame_w and frame_h measure one character frame in source pixels, 16 by 19 */
	frame_w = 16;
	frame_h = 19;

	/* column_count and row_count describe the three animation columns and four facing-direction rows */
	column_count = 3;
	row_count = 4;

	/* origin_x and origin_y locate the drawing origin inside a frame in source pixels, including the
	half-pixel vertical center */
	origin_x = 8;
	origin_y = 9.5;

	/* source_scale converts original character pixels to project sprite dimensions with a factor of
	two */
	source_scale = 2;

	/* characters starts as the current discovered list. official_characters holds bundled records, and
	official_characters_scanned prevents repeating bundled discovery */
	characters = [];
	official_characters = [];
	official_characters_scanned = false;

	/* cache_keys and cache_sheets are parallel arrays starting empty. The registry owns cached sprite
	sheets until explicit invalidation */
	cache_keys = [];
	cache_sheets = [];

	/* selected_key starts at the bundled fallback. loaded_selection tracks whether settings have been
	read and scanned tracks whether general discovery has run */
	selected_key = default_key;
	loaded_selection = false;
	scanned = false;

	/* Last completed installation supplies its local key to callers that equip a pet rather than
	changing the player's character. Failed operations never replace this result */
	last_saved_key = "";

	/* status_text starts empty, status_colour starts white, and status_until starts zero until a
	transient selector message is shown */
	status_text = "";
	status_colour = c_white;
	status_until = 0;

	/* remote_manifests remembers transfer metadata, pending_character_receives holds incomplete
	owner/key assemblies, and remote_failures tracks unavailable identities. All start empty for
	this registry */
	remote_manifests = [];
	pending_character_receives = [];
	remote_failures = [];

	/* browser_index_section and browser_index_count_key identify the saved custom-character index and
	its numeric entry count */
	browser_index_section = "browser_custom_characters";
	browser_index_count_key = "count";

	/* browser_storage_prefix marks PNG files created and owned by browser custom-character
	installation */
	browser_storage_prefix = "browser_custom_character_";

	/* browser_import_pending starts false until a file-picker request is opened.
	browser_remote_characters also retains native session-only PNGs when remote package caching
	is disabled, without registering them as permanent installations */
	browser_import_pending = false;
	browser_import_target = "player"; /* Destination captured while an asynchronous picker is open */
	browser_remote_characters = [];

	#region /* Character Package Paths and Keys */
	/// @description Return this platform's separator for newly constructed filesystem paths
	/// @returns {String} Backslash on Windows, forward slash elsewhere
	path_separator = function()
	{
		/* Use Windows backslashes on Windows and forward slashes elsewhere when assembling filesystem
		paths */
		return os_type == os_windows ? "\\" : "/";
	}

	/// @description Choose browser-backed PNG files and saved index metadata for browser and GX.games builds
	/// @returns {Bool} Whether native character-package directories are unavailable on this platform
	uses_browser_storage = function()
	{
		/* Browser and GX.games environments use browser storage because native package directories are
		not available */
		return os_browser != browser_not_a_browser || os_type == os_gxgames;
	}

	/// @description Convert both supported separator forms to this platform's filesystem form
	/// @param {String} raw_path Path to normalize
	/// @returns {String} Normalized path
	normalize_path = function(raw_path)
	{
		/* path_text converts the input to a path string before normalizing separators */
		var path_text = string(raw_path);

		/* On Windows, convert forward slashes to backslashes. Other platforms use the forward-slash
		conversion below */
		if (os_type == os_windows)
		{
			return string_replace_all(path_text, "/", "\\");
		}

		return string_replace_all(path_text, "\\", "/");
	}

	/// @description Join normalized base and leaf paths while handling empty parts and existing trailing separators
	/// @param {String} base_path Parent path
	/// @param {String} leaf_path Relative child path
	/// @returns {String} Joined platform path
	path_join = function(base_path, leaf_path)
	{
		/* left and right normalize the base and leaf paths before joining them */
		var left = normalize_path(base_path);
		var right = normalize_path(leaf_path);

		/* An empty base contributes no separator, so return the leaf path directly */
		if (left == "")
		{
			return right;
		}

		/* An empty leaf returns the base unchanged instead of adding a trailing separator */
		if (right == "")
		{
			return left;
		}

		/* last_char is the base path's final character used to detect an existing separator */
		var last_char = string_char_at(left, string_length(left));

		/* A base already ending in either separator joins directly to the leaf and avoids adding a
		second separator */
		if (last_char == "/" || last_char == "\\")
		{
			return left + right;
		}

		return left + path_separator() + right;
	}

	/// @description Wrap base64 PNG data in the data-URL format used to load browser character sprites
	/// @param {String} base64_text Complete PNG data encoded as base64
	/// @returns {String} PNG data URL
	character_data_url = function(base64_text)
	{
		return "data:image/png;base64," + string(base64_text);
	}

	/// @description Extract the final component of a path using either slash form
	/// @param {String} raw_path File or folder path
	/// @returns {String} Leaf component, or the whole input when it has no separator
	path_leaf = function(raw_path)
	{
		/* path_text is the supplied path and last_separator starts zero to mean no directory boundary
		has been found */
		var path_text = string(raw_path);
		var last_separator = 0;

		/* char_pos visits the path's one-based character positions to remember its final slash or
		backslash */
		for (var char_pos = 1; char_pos <= string_length(path_text); char_pos++)
		{
			/* ch is the path character currently checked for a directory boundary */
			var ch = string_char_at(path_text, char_pos);

			/* Either slash form updates the last directory separator so mixed-platform paths still
			yield their final leaf */
			if (ch == "/" || ch == "\\")
			{
				last_separator = char_pos;
			}
		}

		/* A path with no separator is already a leaf name and is returned unchanged */
		if (last_separator <= 0)
		{
			return path_text;
		}

		return string_copy(path_text, last_separator + 1, string_length(path_text) - last_separator);
	}

	/// @description Extract the text preceding a path's final slash or backslash
	/// @param {String} raw_path File or folder path
	/// @returns {String} Parent path, or empty when the final separator is absent or at the first character
	path_parent = function(raw_path)
	{
		/* path_text is the source path and last_separator starts zero until a directory boundary is
		encountered */
		var path_text = normalize_path(raw_path);
		var last_separator = 0;

		/* char_pos scans all one-based character positions to locate the final directory separator */
		for (var char_pos = 1; char_pos <= string_length(path_text); char_pos++)
		{
			/* ch is the current path character under the separator test */
			var ch = string_char_at(path_text, char_pos);

			/* Remember each slash or backslash so the final match identifies the path's parent
			boundary */
			if (ch == "/" || ch == "\\")
			{
				last_separator = char_pos;
			}
		}

		/* A path with no parent boundary, or one only at its first character, yields an empty parent
		here */
		if (last_separator <= 1)
		{
			return "";
		}

		return string_copy(path_text, 1, last_separator - 1);
	}

	/// @description Remove a filename's final dot suffix while preserving names with no extension or only a leading dot
	/// @param {String} raw_name Filename to inspect
	/// @returns {String} Filename without its final extension
	strip_extension = function(raw_name)
	{
		/* name_text is the supplied filename and last_dot starts zero until an extension separator is
		found */
		var name_text = string(raw_name);
		var last_dot = 0;

		/* name_index visits the filename's one-based character positions to retain its final dot */
		for (var name_index = 1; name_index <= string_length(name_text); name_index++)
		{
			/* A dot records the latest possible extension boundary rather than stopping at an earlier
			dot in the filename */
			if (string_char_at(name_text, name_index) == ".")
			{
				last_dot = name_index;
			}
		}

		/* A missing dot or leading dot does not provide an extension to strip, so preserve the name */
		if (last_dot <= 1)
		{
			return name_text;
		}

		return string_copy(name_text, 1, last_dot - 1);
	}

	/// @description Turn underscores and hyphens into spaces for a readable package label
	/// @param {String} raw_slug Package or filename stem
	/// @returns {String} Cleaned label, or Custom Character when empty
	display_from_slug = function(raw_slug)
	{
		/* slug replaces underscores and hyphens with spaces and trims the result for a human-readable
		label */
		var slug = string_replace_all(string(raw_slug), "_", " ");
		slug = string_replace_all(slug, "-", " ");
		slug = string_trim(slug);

		/* An empty cleaned slug falls back to Custom Character so a package still has a display name */
		return slug == "" ? "Custom Character" : slug;
	}

	/// @description Build a lowercase basename retaining letters, digits, underscores and hyphens, replacing other character runs with underscores
	/// @param {String} raw_name Requested basename or display label
	/// @returns {String} Safe basename with custom_character fallback
	safe_folder_key = function(raw_name)
	{
		/* raw is the lowercase trimmed requested basename. result starts empty and last_separator
		tracks whether a replacement underscore was just added */
		var raw = string_lower(string_trim(string(raw_name)));
		var result = "";
		var last_separator = false;

		/* raw_index visits the input's one-based character positions to construct one filesystem-safe
		basename */
		for (var raw_index = 1; raw_index <= string_length(raw); raw_index++)
		{
			/* ch is the current candidate basename character */
			var ch = string_char_at(raw, raw_index);

			/* Allowed letters, digits, underscores and hyphens are copied directly and clear the
			replacement-separator flag */
			if (scr_player_character_is_key_char_allowed(ch))
			{
				result += ch;
				last_separator = false;
			}

			/* Other characters add one separating underscore only after existing text and when a
			previous replacement has not already added one */
			else if (!last_separator && result != "")
			{
				result += "_";
				last_separator = true;
			}
		}

		/* Remove trailing replacement underscores while any remain, avoiding an empty-looking suffix
		in the installed name */
		while (string_length(result) > 0
		&& string_char_at(result, string_length(result)) == "_")
		{
			result = string_delete(result, string_length(result), 1);
		}

		/* An input producing no usable name falls back to custom_character */
		if (result == "")
		{
			result = "custom_character";
		}

		return result;
	}

	/// @description Normalize an identifier to twelve lowercase hexadecimal characters by filtering, truncating and zero padding
	/// @param {String} raw_hash Candidate content identifier
	/// @returns {String} Twelve-character identifier without verifying any PNG content
	safe_hash_key = function(raw_hash)
	{
		/* raw is the lowercase trimmed supplied hash and result starts empty until hexadecimal
		characters are collected */
		var raw = string_lower(string_trim(string(raw_hash)));
		var result = "";

		/* raw_index visits the supplied hash's one-based characters */
		for (var raw_index = 1; raw_index <= string_length(raw); raw_index++)
		{
			/* ch is the current lowercase hash character */
			var ch = string_char_at(raw, raw_index);

			/* Keep only hexadecimal digits so punctuation and non-hex letters cannot enter the
			normalized identifier */
			if (string_pos(ch, "0123456789abcdef") > 0)
			{
				result += ch;
			}
		}

		/* Identifiers longer than the protocol's twelve hex characters are truncated to that fixed
		width */
		if (string_length(result) > 12)
		{
			result = string_copy(result, 1, 12);
		}

		/* Append zeros until a short normalized identifier reaches twelve characters, providing a
		stable fixed-width fallback */
		while (string_length(result) < 12)
		{
			result += "0";
		}

		return result;
	}

	/// @description Extract and sanitize the basename before an optional custom network hash
	/// @param {String} raw_key Local or network custom identity
	/// @returns {String} Safe custom basename
	custom_key_name_part = function(raw_key)
	{
		/* key_text normalizes the requested key before extracting its custom basename */
		var key_text = string_lower(string_trim(string(raw_key)));

		/* Remove the custom prefix when present so the name portion excludes the key category marker */
		if (string_copy(key_text, 1, string_length(custom_prefix)) == custom_prefix)
		{
			key_text = string_copy(key_text, string_length(custom_prefix) + 1, string_length(key_text) - string_length(custom_prefix));
		}

		/* colon_pos locates the custom network key's name/hash boundary */
		var colon_pos = string_pos(network_custom_separator, key_text);

		/* A network separator truncates the name before its hash, leaving only the local basename to
		sanitize */
		if (colon_pos > 0)
		{
			key_text = string_copy(key_text, 1, colon_pos - 1);
		}

		return safe_folder_key(key_text);
	}

	/// @description Extract and normalize a custom key's content identifier when a network separator exists
	/// @param {String} raw_key Character identity
	/// @returns {String} Twelve-character hash, or empty for a name-only key
	custom_key_hash_part = function(raw_key)
	{
		/* key_text normalizes the key before extracting its network content hash */
		var key_text = string_lower(string_trim(string(raw_key)));

		/* A custom prefix is removed before locating the name/hash separator */
		if (string_copy(key_text, 1, string_length(custom_prefix)) == custom_prefix)
		{
			key_text = string_copy(key_text, string_length(custom_prefix) + 1, string_length(key_text) - string_length(custom_prefix));
		}

		/* colon_pos locates the separator preceding a network custom hash */
		var colon_pos = string_pos(network_custom_separator, key_text);

		/* A key without that separator has no network hash and returns empty */
		if (colon_pos <= 0)
		{
			return "";
		}

		/* hash_text is the portion following the network separator, normalized before returning it */
		var hash_text = string_copy(key_text, colon_pos + 1, string_length(key_text) - colon_pos);
		return safe_hash_key(hash_text);
	}

	/// @description Identify keys whose normalized text starts with the custom category prefix
	/// @param {String} raw_key Character identity
	/// @returns {Bool} Whether the key uses custom:
	is_custom_key = function(raw_key)
	{
		/* A leading custom prefix identifies custom keys, including local name-only keys */
		return string_copy(string_lower(string_trim(string(raw_key))), 1, string_length(custom_prefix)) == custom_prefix;
	}

	/// @description Identify custom keys with an extractable normalized network hash, without inspecting PNG content
	/// @param {String} raw_key Character identity
	/// @returns {Bool} Whether the key contains both the custom prefix and a hash portion
	is_network_custom_key = function(raw_key)
	{
		/* A custom key with a nonempty extracted hash counts as a network custom identity. Extraction
		normalizes its hash rather than validating raw PNG content */
		return is_custom_key(raw_key) && custom_key_hash_part(raw_key) != "";
	}

	/// @description Normalize official names and custom basename/hash keys, resolving empty input to player1
	/// @param {String} raw_key Requested character identity
	/// @returns {String} Canonical registry key
	sanitize_key = function(raw_key)
	{
		/* key_text is the lowercase trimmed requested identity */
		var key_text = string_lower(string_trim(string(raw_key)));

		/* An empty requested identity resolves to the bundled fallback */
		if (key_text == "")
		{
			return default_key;
		}

		/* Custom keys require separate basename/hash normalization rather than bundled-name cleanup */
		if (string_copy(key_text, 1, string_length(custom_prefix)) == custom_prefix)
		{
			/* custom_part removes the category prefix, custom_name extracts its normalized basename,
			and custom_hash extracts any normalized network identifier */
			var custom_part = string_copy(key_text, string_length(custom_prefix) + 1, string_length(key_text) - string_length(custom_prefix));
			var custom_name = custom_key_name_part(custom_part);
			var custom_hash = custom_key_hash_part(custom_part);

			/* A nonempty hash rebuilds the custom network identity with its separator */
			if (custom_hash != "")
			{
				return custom_prefix + custom_name + network_custom_separator + custom_hash;
			}

			/* A custom identity without a hash remains a local installed key with only its normalized
			basename */
			return custom_prefix + custom_name;
		}

		return safe_folder_key(key_text);
	}

	/// @description Normalize a character key while preserving the custom name and optional content-hash components
	/// @param {String} raw_key Official key, custom:name, or custom:name:hash
	/// @returns {String} Sanitized key. Availability is checked separately by registry lookup
	network_key = function(raw_key)
	{
		return sanitize_key(raw_key);
	}

	/// @description Locate permanent custom installations beneath game_save_id, using a relative folder when its root is empty
	/// @returns {String} Installed custom-character directory
	custom_folder_path = function()
	{
		/* An empty game save root uses the relative custom folder. Otherwise place installed
		characters beneath game_save_id */
		if (string(game_save_id) == "")
		{
			return custom_folder_name;
		}

		return path_join(game_save_id, custom_folder_name);
	}

	/// @description Locate this game's temporary cache root
	/// @returns {String} JonnilOnline cache directory beneath the runtime temporary directory
	temp_root_path = function()
	{
		return path_join(temp_directory, temp_cache_folder_name);
	}

	/// @description Locate the received-character cache beneath the game's temporary root
	/// @returns {String} Temporary character-cache directory
	temp_character_cache_path = function()
	{
		return path_join(temp_root_path(), temp_character_cache_folder_name);
	}

	/// @description Choose the temporary package directory for a normalized content identifier
	/// @param {String} raw_hash Character content identifier
	/// @returns {String} Hash-named cache package path
	temp_character_folder_for_hash = function(raw_hash)
	{
		return path_join(temp_character_cache_path(), safe_hash_key(raw_hash));
	}

	/// @description Prepare the game temporary root and its character-cache child in parent-first order
	/// @returns {Bool} Whether both directories are available
	ensure_temp_character_cache = function()
	{
		/* Create the temporary root first and its character-cache child second, returning success only
		when both directory preparations succeed */
		return ensure_folder(temp_root_path()) && ensure_folder(temp_character_cache_path());
	}
	#endregion /* Character Package Paths and Keys END */

	#region /* Package Status and Folders */
	/// @description Show a character-selector message until 4200 milliseconds after this call
	/// @param {String} message Status wording
	/// @param {Colour} colour_value Message colour. Defaults to c_white when omitted
	set_status = function(message, colour_value = c_white)
	{
		/* Display the supplied message and colour for 4200 milliseconds from the current runtime clock */
		status_text = string(message);
		status_colour = colour_value;
		status_until = current_time + 4200;
	}

	/// @description Clear the transient character-selector message and expiration time
	clear_status = function()
	{
		status_text = "";
		status_until = 0;
	}

	/// @description Create a missing directory and report whether it exists, logging creation exceptions
	/// @param {String} folder_path Directory to prepare
	/// @returns {Bool} Whether the directory is visible after preparation
	ensure_folder = function(folder_path)
	{
		try
		{
			/* Create the requested directory only when it does not already exist */
			if (!directory_exists(folder_path))
			{
				directory_create(folder_path);
			}

			/* Report success only when the directory is visible after the create attempt */
			return directory_exists(folder_path);
		}
		catch(e)
		{
			debug_error("Could not create character folder " + string(folder_path) + ": " + string(e.message));
			return false;
		}
	}

	/// @description Prepare the permanent installed custom-character directory
	/// @returns {Bool} Whether the installed directory is available
	ensure_custom_folder = function()
	{
		return ensure_folder(custom_folder_path());
	}
	#endregion /* Package Status and Folders END */

	#region /* Character Metadata */
	/// @description Parse enabled/disabled words or numeric metadata, preserving the supplied fallback when conversion fails
	/// @param {Any} raw_value Saved permission value
	/// @param {Bool} fallback_value Value for uninterpretable metadata. Defaults to true when omitted
	/// @returns {Bool} Resolved metadata permission
	metadata_bool = function(raw_value, fallback_value = true)
	{
		/* value_text is the lowercase trimmed metadata text used by Boolean parsing */
		var value_text = string_lower(string_trim(string(raw_value)));

		/* Recognized enabled words and numeric 1 return true */
		if (value_text == "1"
		|| value_text == "true"
		|| value_text == "yes"
		|| value_text == "on")
		{
			return true;
		}

		/* Recognized disabled words and numeric 0 return false */
		if (value_text == "0"
		|| value_text == "false"
		|| value_text == "no"
		|| value_text == "off")
		{
			return false;
		}

		try
		{
			/* Other parseable numeric metadata is enabled when nonzero */
			return real(value_text) != 0;
		}
		catch(e)
		{
			/* Unparseable metadata uses fallback_value converted to a Boolean */
			return fallback_value ? true : false;
		}
	}

	/// @description Flatten line breaks, trim metadata and restrict its text length
	/// @param {Any} raw_text Metadata value to clean
	/// @param {Real} max_length Maximum character count. Defaults to 96 when omitted
	/// @returns {String} Bounded single-line text
	metadata_text = function(raw_text, max_length = 96)
	{
		/* result converts input to text, replaces line breaks with spaces and trims it for single-line
		metadata */
		var result = string(raw_text);
		result = string_replace_all(result, "\r", " ");
		result = string_replace_all(result, "\n", " ");
		result = string_trim(result);

		/* Metadata longer than max_length is truncated so persisted labels and provenance stay bounded */
		if (string_length(result) > max_length)
		{
			result = string_copy(result, 1, max_length);
		}

		return result;
	}

	/// @description Normalize a nonempty content identifier while retaining an empty optional hash
	/// @param {String} raw_hash Optional identifier
	/// @returns {String} Empty text or twelve-character normalized hash
	optional_hash_key = function(raw_hash)
	{
		/* hash_text is the trimmed optional content identifier */
		var hash_text = string_trim(string(raw_hash));

		/* An absent optional hash remains empty instead of becoming a padded zero identifier */
		if (hash_text == "")
		{
			return "";
		}

		return safe_hash_key(hash_text);
	}

	/// @description Build a discovered character record with identity, source data, permissions, provenance and shared sprite-sheet metrics
	/// @param {String} key_text Local entry identity
	/// @param {String} label_text Selector display label
	/// @param {String} source_file PNG path or browser data URL
	/// @param {Bool} official_value Whether the entry belongs to bundled characters
	/// @param {String} network_key_text Transfer identity. Defaults to empty and uses key_text when omitted
	/// @param {String} hash_text Content identifier. Defaults to empty when omitted
	/// @param {Bool} remote_value Whether this is a received cache entry. Defaults to false when omitted
	/// @param {Bool} allow_clone_value Custom clone permission. Defaults to true when omitted
	/// @param {Bool} allow_temp_cache_value Custom temporary-cache permission. Defaults to true when omitted
	/// @param {String} original_creator_name_text Creator name. Defaults to empty when omitted
	/// @param {String} original_creator_id_text Creator identity. Defaults to empty when omitted
	/// @param {String} copied_from_hash_text Source-copy identifier. Defaults to empty when omitted
	/// @param {String} base64_text Retained custom PNG data. Defaults to empty when omitted
	/// @param {Real} byte_size_value PNG byte count. Defaults to zero when omitted
	/// @param {String} browser_storage_file_text Owned browser PNG filename. Defaults to empty when omitted
	/// @returns {Struct} Character record with fixed frame/grid/origin metrics
	make_entry = function(key_text, label_text, source_file, official_value, network_key_text = "", hash_text = "", remote_value = false, allow_clone_value = true, allow_temp_cache_value = true, original_creator_name_text = "", original_creator_id_text = "", copied_from_hash_text = "", base64_text = "", byte_size_value = 0, browser_storage_file_text = "")
	{
		/* clean_key normalizes the entry's local identity. clean_network_key uses a supplied network
		key or that local identity, clean_hash uses a supplied identifier or extracts it from that
		network key, and clean_custom distinguishes custom from official records */
		var clean_key = sanitize_key(key_text);
		var clean_network_key = string_trim(string(network_key_text)) == "" ? clean_key : sanitize_key(network_key_text);
		var clean_hash = string_trim(string(hash_text)) == "" ? custom_key_hash_part(clean_network_key) : safe_hash_key(hash_text);
		var clean_custom = !official_value;

		/* The entry stores local/network identity, display/source fields, official/remote status and
		hash aliases. Custom permission/provenance/data fields preserve their inputs, while official
		records disable cloning, enable cache permission and leave custom-only provenance and image
		data empty. Frame/grid/origin/scale fields carry this registry's shared sheet metrics */
		return
		{
			key: clean_key,
			network_key: clean_network_key,
			display_label: string(label_text),
			source_file: string(source_file),
			official: official_value,
			remote: remote_value,
			hash: clean_hash,
			character_hash: clean_hash,

			/* Custom entries parse their requested clone/cache permissions, defaulting to enabled on
			invalid metadata. Official entries disable the manifest clone flag and keep cache
			permission enabled */
			allow_clone: clean_custom ? metadata_bool(allow_clone_value, true) : false,
			allow_multiplayer_temp_cache: clean_custom ? metadata_bool(allow_temp_cache_value, true) : true,

			/* Custom creator name and ID are bounded to 64 characters, copied_from_hash keeps an
			optional source identifier, base64 retains encoded PNG data, byte_size is nonnegative
			whole bytes, and browser_storage_file records the owned image filename. Official entries
			leave these custom-only fields empty or zero */
			original_creator_name: clean_custom ? metadata_text(original_creator_name_text, 64) : "",
			original_creator_id: clean_custom ? metadata_text(original_creator_id_text, 64) : "",
			copied_from_hash: clean_custom ? optional_hash_key(copied_from_hash_text) : "",
			base64: clean_custom ? string(base64_text) : "",
			byte_size: clean_custom ? max(0, floor(real(byte_size_value))) : 0,
			browser_storage_file: clean_custom ? string(browser_storage_file_text) : "",
			frame_w: frame_w,
			frame_h: frame_h,
			column_count: column_count,
			row_count: row_count,
			origin_x: origin_x,
			origin_y: origin_y,
			source_scale: source_scale
		};
	}
	#endregion /* Character Metadata END */

	#region /* Bundled Character Discovery */
	/// @description Find an exact bundled character identity in the official-only records
	/// @param {String} raw_key Requested bundled key
	/// @returns {Real} Zero-based official index, or noone when absent
	official_entry_index = function(raw_key)
	{
		/* key_text is the normalized official identity requested from the bundled-only array */
		var key_text = sanitize_key(raw_key);

		/* entry_index visits bundled entries until an exact key match is found */
		for (var entry_index = 0; entry_index < array_length(official_characters); entry_index++)
		{
			/* A matching bundled key returns its zero-based official entry index */
			if (official_characters[entry_index].key == key_text)
			{
				return entry_index;
			}
		}

		return noone;
	}

	/// @description Inspect a bundled package's configuration and image, registering it only when its official key is unique
	/// @param {String} folder_path Candidate package root
	/// @param {String} folder_name Candidate folder basename used for default key and label
	/// @returns {Bool} Whether one official record was appended
	add_official_folder = function(folder_path, folder_name)
	{
		/* config_path identifies the candidate package's data/character_config.ini metadata */
		var config_path = path_join(path_join(folder_path, "data"), "character_config.ini");

		/* A bundled package without its required configuration is skipped */
		if (!file_exists(config_path))
		{
			return false;
		}

		/* key_text starts from the folder name, label_text starts from its readable slug, source_text
		starts official, and sprite_file_name starts player.png before INI overrides */
		var key_text = safe_folder_key(folder_name);
		var label_text = display_from_slug(folder_name);
		var source_text = "official";
		var sprite_file_name = "player.png";
		try
		{
			ini_open(config_path);
			key_text = sanitize_key(ini_read_string("info", "character_key", key_text));
			label_text = string_trim(string(ini_read_string("info", "character_name", label_text)));
			source_text = string_lower(string_trim(string(ini_read_string("info", "source", source_text))));
			sprite_file_name = path_leaf(ini_read_string("sprite_sheet", "file", sprite_file_name));
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not read official character config " + config_path + ": " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}

		/* Reject nonofficial source tags, custom keys and duplicate bundled identities so discovery
		remains a unique official list */
		if (source_text != "official"
		|| is_custom_key(key_text)
		|| official_entry_index(key_text) != noone)
		{
			return false;
		}

		/* An empty configured label falls back to the readable folder name */
		if (label_text == "")
		{
			label_text = display_from_slug(folder_name);
		}

		/* sprite_path locates the configured image beneath this bundled package's sprites directory */
		var sprite_path = path_join(path_join(folder_path, "sprites"), sprite_file_name);

		/* Missing configured PNG files are skipped rather than registered as loadable bundled
		characters */
		if (!file_exists(sprite_path))
		{
			debug_error("Skipping official character " + key_text + ": missing " + sprite_path + ".");
			return false;
		}

		official_characters[array_length(official_characters)] = make_entry(key_text, label_text, sprite_path, true);
		return true;
	}

	/// @description Discover bundled packages once, using numbered browser lookup or native directory enumeration, with a player1 fallback
	/// @returns {Array} Shared bundled character records
	discover_official_entries = function()
	{
		/* Reuse bundled discovery once completed instead of scanning packaged files repeatedly */
		if (official_characters_scanned)
		{
			return official_characters;
		}

		official_characters = [];

		/* root_paths starts with the bundled Characters path available to all platforms */
		var root_paths = [official_folder_name];

		/* Native builds also search datafiles/Characters for packaged assets accessed through that
		layout */
		if (!uses_browser_storage())
		{
			root_paths[array_length(root_paths)] = path_join("datafiles", official_folder_name);
		}

		/* Numbered Player folders can be found even on browser targets, where bundled directories cannot be enumerated.
		Stop a browser scan after a generous missing run so three bundled characters do not cause hundreds of HTTP 404s */
		/* browser_numbered_scan selects the browser fallback strategy and browser_missing_streak
		starts zero for consecutive absent player folders */
		var browser_numbered_scan = uses_browser_storage();
		var browser_missing_streak = 0;

		/* player_number checks numbered player folders from 1 through 512, allowing browser discovery
		without directory enumeration */
		for (var player_number = 1; player_number <= 512; player_number++)
		{
			/* numbered_folder names the candidate bundled player package and numbered_folder_added
			starts false until a root provides it */
			var numbered_folder = "Player" + string(player_number);
			var numbered_folder_added = false;

			/* root_index visits possible bundled roots until this numbered folder is registered */
			for (var root_index = 0; root_index < array_length(root_paths); root_index++)
			{
				/* A successful package registration marks this numbered candidate found and stops
				duplicate root lookup */
				if (add_official_folder(path_join(root_paths[root_index], numbered_folder), numbered_folder))
				{
					numbered_folder_added = true;
					break;
				}
			}

			/* Only browser discovery uses the consecutive-missing-folder stop rule */
			if (browser_numbered_scan)
			{
				/* Found numbered packages reset the missing streak, while absent numbered packages
				increase it */
				browser_missing_streak = numbered_folder_added ? 0 : browser_missing_streak + 1;

				/* After finding any bundled character, eight consecutive missing numbered folders end
				the browser search */
				if (array_length(official_characters) > 0 && browser_missing_streak >= 8)
				{
					break;
				}
			}
		}

		/* Native builds can also discover official folders with non-numbered names */
		/* Native builds additionally enumerate directories to discover non-numbered bundled package
		names */
		if (!uses_browser_storage())
		{
			/* root_index visits each native bundled root */
			for (var root_index = 0; root_index < array_length(root_paths); root_index++)
			{
				/* root_path identifies the current native directory being enumerated */
				var root_path = root_paths[root_index];

				/* A missing root has no bundled subdirectories to inspect */
				if (!directory_exists(root_path))
				{
					continue;
				}

				/* search_mask targets all immediate children of this native bundled root */
				var search_mask = path_join(root_path, "*");

				/* find_attributes selects directory filtering on Windows and normal platform search
				elsewhere */
				var find_attributes = os_type == os_windows ? fa_directory : fa_none;

				/* found retains the current filesystem search result until enumeration returns an
				empty name */
				var found = file_find_first(search_mask, find_attributes);

				/* Inspect each available child entry and end the loop when no search results remain */
				while (found != "")
				{
					/* folder_name is the current result's leaf name */
					var folder_name = path_leaf(found);

					/* Dot entries are skipped because they refer to directory navigation rather than
					character packages */
					if (folder_name != "." && folder_name != "..")
					{
						/* folder_path joins this bundled root with the returned leaf name */
						var folder_path = path_join(root_path, folder_name);

						/* If the joined path is missing but the returned search result is itself an
						existing directory, use that returned path */
						if (!directory_exists(folder_path) && directory_exists(found))
						{
							folder_path = found;
						}

						/* Only existing directories are passed to bundled package registration */
						if (directory_exists(folder_path))
						{
							add_official_folder(folder_path, folder_name);
						}
					}

					found = file_find_next();
				}

				file_find_close();
			}
		}

		/* If discovery lacks player1, insert a default record so selection fallback still has a known
		identity */
		if (official_entry_index(default_key) == noone)
		{
			array_insert(official_characters, 0, make_entry(default_key, "Player 1", "Characters/Player1/sprites/player.png", true));
			debug_error("Could not discover the default official character. Using the Player 1 fallback entry.");
		}

		official_characters_scanned = true;
		return official_characters;
	}

	/// @description Append the cached bundled records to the current discovered character list
	add_official_entries = function()
	{
		discover_official_entries();

		/* entry_index visits all bundled records and appends each to the current discovered character
		list */
		for (var entry_index = 0; entry_index < array_length(official_characters); entry_index++)
		{
			characters[array_length(characters)] = official_characters[entry_index];
		}
	}
	#endregion /* Bundled Character Discovery END */

	#region /* Native Character Packages and Manifests */
	/// @description Read and trim a native package's display label while preserving the supplied fallback on missing or invalid metadata
	/// @param {String} folder_path Custom package root
	/// @param {String} fallback_label Readable label used when no nonempty saved label is available
	/// @returns {String} Resolved package label
	read_custom_display_label = function(folder_path, fallback_label)
	{
		/* label_text starts as the caller's readable fallback and config_path locates optional package
		metadata */
		var label_text = string(fallback_label);
		var config_path = path_join(path_join(folder_path, "data"), "character_config.ini");

		/* Without package metadata, keep the caller's fallback display name */
		if (!file_exists(config_path))
		{
			return label_text;
		}

		try
		{
			ini_open(config_path);
			label_text = string(ini_read_string("info", "character_name", label_text));
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not read custom character config " + config_path + ": " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		label_text = string_trim(label_text);

		/* Trim the loaded display name and use the caller's fallback when it is empty */
		return label_text == "" ? string(fallback_label) : label_text;
	}

	/// @description Read one native package info field, preserving its fallback when metadata is absent or a read fails
	/// @param {String} folder_path Custom package root
	/// @param {String} key_name INI info key to read
	/// @param {String} fallback_value Text used when the key or configuration is unavailable
	/// @returns {String} Saved or fallback field
	read_custom_config_string = function(folder_path, key_name, fallback_value)
	{
		/* result starts with the caller's fallback metadata text and config_path identifies its
		optional package INI */
		var result = string(fallback_value);
		var config_path = path_join(path_join(folder_path, "data"), "character_config.ini");

		/* Without a config file, return the supplied fallback instead of attempting a read */
		if (!file_exists(config_path))
		{
			return result;
		}

		try
		{
			ini_open(config_path);
			result = string(ini_read_string("info", key_name, result));
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not read custom character config key " + string(key_name) + ": " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		return string_trim(result);
	}

	/// @description Read a native package permission and parse it without losing its fallback on absent or invalid metadata
	/// @param {String} folder_path Custom package root
	/// @param {String} key_name INI info permission key
	/// @param {Bool} fallback_value Permission used when the key is absent or cannot be parsed
	/// @returns {Bool} Resolved package permission
	read_custom_config_bool = function(folder_path, key_name, fallback_value)
	{
		/* result starts from the Boolean fallback and config_path locates its optional package INI */
		var result = fallback_value ? true : false;
		var config_path = path_join(path_join(folder_path, "data"), "character_config.ini");

		/* An absent config leaves the requested fallback permission unchanged */
		if (!file_exists(config_path))
		{
			return result;
		}

		try
		{
			ini_open(config_path);

			/* Only an explicitly present INI key overrides the permission fallback */
			if (ini_key_exists("info", key_name))
			{
				/* Read the flag with its current numeric 1 or 0 fallback, then parse the saved text
				without losing that fallback on an invalid value */
				result = metadata_bool(ini_read_string("info", key_name, result ? "1" : "0"), result);
			}
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not read custom character config bool " + string(key_name) + ": " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		return result;
	}

	/// @description Read package permissions and provenance. Older packages default missing clone and temporary-cache flags to true
	/// @param {String} folder_path Character package root containing data/character_config.ini
	/// @param {String} fallback_hash Hash to use when older package metadata omits character_hash. Defaults to empty when omitted
	/// @returns {Struct} Permissions, creator fields, and content-hash metadata
	read_custom_metadata = function(folder_path, fallback_hash = "")
	{
		/* config_hash starts from the saved character_hash or the supplied fallback identifier */
		var config_hash = read_custom_config_string(folder_path, "character_hash", fallback_hash);

		/* An empty saved hash retains fallback_hash rather than clearing available content identity */
		if (config_hash == "")
		{
			config_hash = fallback_hash;
		}

		/* Return clone and temporary-cache flags with enabled defaults, creator name/ID trimmed to 64
		characters, an optional character hash and optional copied-from hash */
		return
		{
			allow_clone: read_custom_config_bool(folder_path, "allow_clone", true),
			allow_multiplayer_temp_cache: read_custom_config_bool(folder_path, "allow_multiplayer_temp_cache", true),
			original_creator_name: metadata_text(read_custom_config_string(folder_path, "original_creator_name", ""), 64),
			original_creator_id: metadata_text(read_custom_config_string(folder_path, "original_creator_id", ""), 64),
			character_hash: optional_hash_key(config_hash),
			copied_from_hash: optional_hash_key(read_custom_config_string(folder_path, "copied_from_hash", ""))
		};
	}

	/// @description Convert a clamped whole number from zero through fifteen to its lowercase hexadecimal digit
	/// @param {Real} value Digit value
	/// @returns {String} One hexadecimal character
	hex_digit = function(value)
	{
		/* digits lists the hexadecimal alphabet and index clamps the requested whole digit to the
		zero-based range 0 through 15 */
		var digits = "0123456789abcdef";
		var index = clamp(floor(real(value)), 0, 15);
		return string_char_at(digits, index + 1);
	}

	/// @description Encode the low-order hexadecimal digits of a nonnegative whole value with leading zero padding
	/// @param {Real} value Number to encode
	/// @param {Real} digit_count Number of output digits
	/// @returns {String} Fixed-width lowercase hexadecimal text
	hex_fixed = function(value, digit_count)
	{
		/* remaining starts as a nonnegative whole number and result starts empty before fixed-width
		hexadecimal conversion */
		var remaining = max(0, floor(real(value)));
		var result = "";

		/* digit_index visits exactly digit_count output positions, including leading zero positions
		once remaining is exhausted */
		for (var digit_index = 0; digit_index < digit_count; digit_index++)
		{
			/* digit extracts the least significant hexadecimal digit, which is prepended before
			dividing remaining by 16 */
			var digit = remaining mod 16;
			result = hex_digit(digit) + result;
			remaining = floor(remaining / 16);
		}

		return result;
	}

	/// @description Compute the protocol's 12-character content identifier. This checksum is not a cryptographic signature
	/// @param {Id.Buffer} source_buffer Borrowed buffer. Its cursor is reset to zero after hashing
	/// @param {Real} byte_size Bytes to hash, limited to the existing buffer size
	/// @returns {String} Twelve lowercase hexadecimal characters
	buffer_hash12 = function(source_buffer, byte_size)
	{
		/* An undefined or missing borrowed buffer returns the twelve-zero fallback identifier */
		if (is_undefined(source_buffer)
		|| !buffer_exists(source_buffer))
		{
			return "000000000000";
		}

		/* size is the bounded nonnegative byte count to hash. h1 and h2 start from separate seeded
		accumulators incorporating that count */
		var size = max(0, min(floor(real(byte_size)), buffer_get_size(source_buffer)));
		var h1 = (2166136261 + size) mod 1000000007;
		var h2 = (16777619 + size * 17) mod 1000000009;
		buffer_seek(source_buffer, buffer_seek_start, 0);

		/* byte_index reads all bytes from zero through size minus one, mixing byte position into both
		accumulators */
		for (var byte_index = 0; byte_index < size; byte_index++)
		{
			/* byte_value is the current unsigned PNG byte added to the deterministic checksum
			accumulators */
			var byte_value = buffer_read(source_buffer, buffer_u8);
			h1 = (h1 * 33 + byte_value + byte_index) mod 1000000007;
			h2 = (h2 * 131 + byte_value + size - byte_index) mod 1000000009;
		}

		buffer_seek(source_buffer, buffer_seek_start, 0);
		return string_copy(hex_fixed(h1, 8), 3, 6) + string_copy(hex_fixed(h2, 8), 3, 6);
	}

	/// @description Inspect and encode a valid transferable 48x76 PNG, releasing the locally loaded buffer on completion
	/// @param {String} file_path PNG source path
	/// @returns {Struct} ok, hash, byte_size, base64 and diagnostic message without an owned buffer
	png_hash_for_path = function(file_path)
	{
		/* result starts as a failed PNG read with no hash, encoded data or byte count and a diagnostic
		message */
		var result =
		{
			ok: false,
			hash: "",
			byte_size: 0,
			base64: "",
			message: "Could not read PNG file."
		};

		/* source_buffer starts without an owned handle and is released after inspection or failure */
		var source_buffer = noone;
		try
		{
			source_buffer = buffer_load(file_path);

			/* An undefined or missing loaded buffer cannot supply PNG metadata and returns the failed
			result */
			if (is_undefined(source_buffer)
			|| !buffer_exists(source_buffer))
			{
				return result;
			}

			/* byte_size is the loaded PNG's actual allocation size used for validation, hashing and
			encoding */
			var byte_size = buffer_get_size(source_buffer);
			result.byte_size = byte_size;

			/* Reject an empty image or one exceeding the 262144-byte character-transfer limit */
			if (byte_size <= 0 || byte_size > character_max_bytes)
			{
				result.message = "Character PNG must be 256 KB or smaller.";
			}

			/* A PNG within the size limit proceeds to header and dimensions validation */
			else
			{
				/* png_info retains the borrowed buffer's PNG-header inspection */
				var png_info = png_dimensions_from_buffer(source_buffer);

				/* A failed header inspection propagates its diagnostic rather than encoding invalid
				image data */
				if (!png_info.ok)
				{
					result.message = png_info.message;
				}

				/* Only the required 48 by 76 pixel sheet is eligible for a transferable character */
				else if (png_info.width != expected_sheet_w || png_info.height != expected_sheet_h)
				{
					result.message = "PNG must be exactly " + string(expected_sheet_w) + "x" + string(expected_sheet_h) + " pixels.";
				}

				/* A correctly sized PNG can be hashed and base64 encoded and clears the provisional
				error */
				else
				{
					result.hash = buffer_hash12(source_buffer, byte_size);
					result.base64 = buffer_base64_encode(source_buffer, 0, byte_size);
					result.ok = true;
					result.message = "";
				}
			}
		}
		catch(e)
		{
			result.message = "Could not inspect PNG: " + string(e.message);
		}

		/* Release the locally owned loaded buffer if it remains live after inspection or an exception */
		if (!is_undefined(source_buffer)
		&& buffer_exists(source_buffer))
		{
			buffer_delete(source_buffer);
		}

		return result;
	}

	/// @description Normalize protocol identity, payload sizes, permissions and provenance into one custom or official manifest
	/// @param {String} network_key_text Official or custom transfer identity
	/// @param {String} display_text Human-readable character name
	/// @param {String} safe_name_text Custom basename
	/// @param {String} hash_text Custom content identifier
	/// @param {Bool} is_custom_value Whether the manifest describes custom PNG data
	/// @param {Real} byte_size_value PNG byte count
	/// @param {Real} chunk_count_value Base64 fragment count
	/// @param {String} base64_text Encoded PNG content. Defaults to empty when omitted
	/// @param {Bool} allow_clone_value Custom clone permission. Defaults to true when omitted
	/// @param {Bool} allow_temp_cache_value Custom temporary-cache permission. Defaults to true when omitted
	/// @param {String} original_creator_name_text Creator name. Defaults to empty when omitted
	/// @param {String} original_creator_id_text Creator ID. Defaults to empty when omitted
	/// @param {String} copied_from_hash_text Source-copy identifier. Defaults to empty when omitted
	/// @returns {Struct} Normalized manifest with no allocated PNG buffer
	make_manifest_struct = function(network_key_text, display_text, safe_name_text, hash_text, is_custom_value, byte_size_value, chunk_count_value, base64_text = "", allow_clone_value = true, allow_temp_cache_value = true, original_creator_name_text = "", original_creator_id_text = "", copied_from_hash_text = "")
	{
		/* clean_custom resolves the requested type, clean_hash applies only to custom images,
		clean_name is their normalized basename, and clean_key combines that name/hash or the
		normalized official identity */
		var clean_custom = is_custom_value ? true : false;
		var clean_hash = clean_custom ? safe_hash_key(hash_text) : "";
		var clean_name = clean_custom ? safe_folder_key(safe_name_text) : "";
		var clean_key = clean_custom
			? custom_prefix + clean_name + network_custom_separator + clean_hash
			: sanitize_key(network_key_text);

		/* The manifest stores network identity, label, safe name and hash aliases, custom status,
		nonnegative PNG bytes/chunk count and optional base64. Custom permissions/provenance retain
		their supplied values, while bundled manifests have no image payload or custom provenance
		and disable cloning */
		return
		{
			network_key: clean_key,
			display_label: string(display_text),
			safe_name: clean_name,
			hash: clean_hash,
			character_hash: clean_hash,
			custom: clean_custom,
			byte_size: max(0, floor(real(byte_size_value))),
			chunk_count: max(0, floor(real(chunk_count_value))),
			base64: string(base64_text),
			allow_clone: clean_custom ? metadata_bool(allow_clone_value, true) : false,
			allow_multiplayer_temp_cache: clean_custom ? metadata_bool(allow_temp_cache_value, true) : true,
			original_creator_name: clean_custom ? metadata_text(original_creator_name_text, 64) : "",
			original_creator_id: clean_custom ? metadata_text(original_creator_id_text, 64) : "",
			copied_from_hash: clean_custom ? optional_hash_key(copied_from_hash_text) : ""
		};
	}

	/// @description Add custom permissions and provenance to valid image metadata without replacing its content identity or bytes
	/// @param {Struct} payload_manifest Actual PNG identity, sizes and base64
	/// @param {Struct} metadata_manifest Display, permission and creator metadata
	/// @returns {Struct} Combined custom manifest, or unchanged payload when either input is unsuitable
	manifest_with_metadata = function(payload_manifest, metadata_manifest)
	{
		/* An invalid payload manifest cannot be enriched, so return it unchanged */
		if (!manifest_is_valid_shape(payload_manifest))
		{
			return payload_manifest;
		}

		/* Missing or invalid metadata and official payloads leave the payload unchanged because this
		merge describes custom-image provenance and permissions */
		if (!manifest_is_valid_shape(metadata_manifest)
		|| !payload_manifest.custom)
		{
			return payload_manifest;
		}

		/* Rebuild custom metadata around the payload's actual identity, bytes, fragments and base64 so
		metadata merging cannot replace its image content */
		return make_manifest_struct(
			payload_manifest.network_key,
			metadata_manifest.display_label,
			payload_manifest.safe_name,
			payload_manifest.hash,
			true,
			payload_manifest.byte_size,
			payload_manifest.chunk_count,

			/* Use metadata clone/cache permission fields when available, otherwise enable their legacy
			defaults. Missing creator/copy fields remain empty */
			variable_struct_exists(payload_manifest, "base64") ? payload_manifest.base64 : "",
			variable_struct_exists(metadata_manifest, "allow_clone") ? metadata_manifest.allow_clone : true,
			variable_struct_exists(metadata_manifest, "allow_multiplayer_temp_cache") ? metadata_manifest.allow_multiplayer_temp_cache : true,
			variable_struct_exists(metadata_manifest, "original_creator_name") ? metadata_manifest.original_creator_name : "",
			variable_struct_exists(metadata_manifest, "original_creator_id") ? metadata_manifest.original_creator_id : "",
			variable_struct_exists(metadata_manifest, "copied_from_hash") ? metadata_manifest.copied_from_hash : ""
		);
	}

	/// @description Build metadata-only bundled identity, using player1 when the requested discovery entry is missing or nonofficial
	/// @param {String} raw_key Requested bundled character key
	/// @returns {Struct} Official manifest with no PNG payload
	official_manifest = function(raw_key)
	{
		/* Official manifests are the small network description used when no custom PNG data needs to be transferred.
		Only keys found in the bundled official character folders are accepted, so unknown keys safely use Player 1 */
		/* key_text is the normalized requested bundled identity and entry_index locates it in
		discovered entries */
		var key_text = sanitize_key(raw_key);
		var entry_index = find_index(key_text);

		/* Missing or nonofficial identities fall back to the default bundled key because official
		manifests contain no custom image data */
		if (entry_index == noone || !characters[entry_index].official)
		{
			key_text = default_key;
		}

		return make_manifest_struct(key_text, display_name(key_text), "", "", false, 0, 0, "");
	}

	/// @description Check required manifest field presence without validating their values, full protocol identity or PNG content
	/// @param {Any} manifest Candidate metadata
	/// @returns {Bool} Whether the candidate exposes the required manifest shape
	manifest_is_valid_shape = function(manifest)
	{
		/* Required manifest shape means a struct exposing identity, display, custom flag, byte size
		and chunk count. This shape check does not validate their values or PNG bytes */
		return is_struct(manifest)
			&& variable_struct_exists(manifest, "network_key")
			&& variable_struct_exists(manifest, "display_label")
			&& variable_struct_exists(manifest, "custom")
			&& variable_struct_exists(manifest, "byte_size")
			&& variable_struct_exists(manifest, "chunk_count");
	}

	/// @description Replace or append remembered character metadata by normalized network identity
	/// @param {Struct} manifest Manifest with required fields
	/// @returns {Bool} Whether metadata was stored
	remember_manifest = function(manifest)
	{
		/* Only manifests with required fields enter the remembered metadata array */
		if (!manifest_is_valid_shape(manifest))
		{
			return false;
		}

		/* key_text is the normalized network identity used to replace or append remembered metadata */
		var key_text = sanitize_key(manifest.network_key);

		/* manifest_index visits all remembered manifests looking for that identity */
		for (var manifest_index = 0; manifest_index < array_length(remote_manifests); manifest_index++)
		{
			/* A matching network key replaces its remembered metadata so later UI and transfer lookups
			use the latest record */
			if (remote_manifests[manifest_index].network_key == key_text)
			{
				remote_manifests[manifest_index] = manifest;
				return true;
			}
		}

		remote_manifests[array_length(remote_manifests)] = manifest;
		return true;
	}

	/// @description Retrieve remembered metadata for one normalized network identity
	/// @param {String} raw_key Character network key
	/// @returns {Struct|Real} Remembered manifest reference, or noone
	manifest_for_network_key = function(raw_key)
	{
		/* key_text normalizes the remembered remote identity being requested */
		var key_text = sanitize_key(raw_key);

		/* manifest_index visits remembered manifests until a matching network key is found */
		for (var manifest_index = 0; manifest_index < array_length(remote_manifests); manifest_index++)
		{
			/* A matching remembered identity returns its manifest reference */
			if (remote_manifests[manifest_index].network_key == key_text)
			{
				return remote_manifests[manifest_index];
			}
		}

		return noone;
	}

	/// @description Register a native installed custom package, retaining saved identity when image inspection cannot supply a hash
	/// @param {String} folder_path Installed package root
	/// @param {String} folder_key Package basename used for local identity
	/// @returns {Bool} Whether a record was appended for an existing player.png
	add_custom_entry = function(folder_path, folder_key)
	{
		/* custom_key is the sanitized local installed identity and sprite_path locates the package's
		fixed player.png image */
		var custom_key = custom_prefix + safe_folder_key(folder_key);
		var sprite_path = path_join(path_join(folder_path, "sprites"), "player.png");

		/* A native custom package without its image is omitted from discovery */
		if (!file_exists(sprite_path))
		{
			return false;
		}

		/* label_text is the package's readable name, hash_info inspects its PNG, network_key_text
		initially uses the local key, hash_text starts empty, and saved_network_key reads its
		optional recorded network identity */
		var label_text = read_custom_display_label(folder_path, display_from_slug(folder_key));
		var hash_info = png_hash_for_path(sprite_path);
		var network_key_text = custom_key;
		var hash_text = "";
		var saved_network_key = read_custom_config_string(folder_path, "network_key", "");

		/* A valid PNG inspection establishes the installed image's actual content identifier */
		if (hash_info.ok)
		{
			hash_text = hash_info.hash;

			/* Retain a nonempty saved network key when its extracted hash matches the inspected PNG
			identifier */
			if (saved_network_key != "" && custom_key_hash_part(saved_network_key) == hash_text)
			{
				network_key_text = saved_network_key;
			}

			/* Otherwise rebuild network identity from the installed basename and computed content hash */
			else
			{
				network_key_text = custom_prefix + safe_folder_key(folder_key) + network_custom_separator + hash_text;
			}
		}

		/* A failed image inspection may still preserve the package's recorded identity rather than
		omitting this entry */
		else
		{
			/* A nonempty saved network key supplies fallback identity and its embedded hash when
			inspection could not establish one */
			if (saved_network_key != "")
			{
				network_key_text = saved_network_key;
				hash_text = custom_key_hash_part(saved_network_key);
			}
		}

		/* metadata resolves the package's saved permissions and provenance with the available hash as
		fallback */
		var metadata = read_custom_metadata(folder_path, hash_text);
		characters[array_length(characters)] = make_entry(
			custom_key,
			label_text,
			sprite_path,
			false,
			network_key_text,

			/* A saved nonempty character_hash takes precedence in this entry, otherwise use the
			inspected or key-derived hash */
			metadata.character_hash == "" ? hash_text : metadata.character_hash,
			false,
			metadata.allow_clone,
			metadata.allow_multiplayer_temp_cache,
			metadata.original_creator_name,
			metadata.original_creator_id,
			metadata.copied_from_hash
		);
		return true;
	}

	/// @description Register a received native cache package using its saved network identity and creator metadata
	/// @param {String} folder_path Temporary package root
	/// @param {String} folder_key Cache directory basename used as fallback hash
	/// @returns {Bool} Whether a remote record was appended for an existing player.png
	add_temp_entry = function(folder_path, folder_key)
	{
		/* sprite_path locates the temporary package's fixed player.png image */
		var sprite_path = path_join(path_join(folder_path, "sprites"), "player.png");

		/* A temporary package missing its PNG cannot enter remote character discovery */
		if (!file_exists(sprite_path))
		{
			return false;
		}

		/* fallback_hash comes from the cache folder name, saved_network_key and saved_hash read
		package identity, and safe_name starts as the package's remote basename fallback */
		var fallback_hash = safe_hash_key(folder_key);
		var saved_network_key = read_custom_config_string(folder_path, "network_key", "");
		var saved_hash = read_custom_config_string(folder_path, "character_hash", fallback_hash);
		var safe_name = read_custom_config_string(folder_path, "safe_name", "remote_character");

		/* A missing saved network key is rebuilt from the available safe name and saved hash */
		if (saved_network_key == "")
		{
			saved_network_key = custom_prefix + safe_folder_key(safe_name) + network_custom_separator + safe_hash_key(saved_hash);
		}

		/* label_text is the readable remote package name and metadata resolves its saved permissions
		and provenance */
		var label_text = read_custom_display_label(folder_path, display_from_slug(safe_name));
		var metadata = read_custom_metadata(folder_path, saved_hash);
		characters[array_length(characters)] = make_entry(
			saved_network_key,
			label_text,
			sprite_path,
			false,
			saved_network_key,

			/* Use a nonempty metadata character_hash for the remote record, otherwise keep the saved
			cache identity's hash */
			metadata.character_hash == "" ? saved_hash : metadata.character_hash,
			true,
			metadata.allow_clone,
			metadata.allow_multiplayer_temp_cache,
			metadata.original_creator_name,
			metadata.original_creator_id,
			metadata.copied_from_hash
		);
		return true;
	}
	#endregion /* Native Character Packages and Manifests END */

	#region /* Browser Character Storage */
	/// @description Choose this registry's owned browser PNG filename from a safe name and content identifier
	/// @param {String} safe_name_text Installed character basename
	/// @param {String} hash_text PNG content identifier
	/// @returns {String} Browser storage filename
	browser_storage_file_for_character = function(safe_name_text, hash_text)
	{
		/* Browser PNG filenames combine the normalized safe basename and content identifier under this
		registry's owned storage prefix */
		return browser_storage_prefix + safe_folder_key(safe_name_text) + "_" + safe_hash_key(hash_text) + ".png";
	}

	/// @description Recognize saved index source tags belonging to locally installed custom characters
	/// @param {String} raw_source Saved source category
	/// @returns {Bool} Whether the tag is recognized as owned, including an empty legacy tag
	browser_index_source_is_owned = function(raw_source)
	{
		/* source_text normalizes the saved index source tag before checking whether it describes a
		locally owned custom installation */
		var source_text = string_lower(string_trim(string(raw_source)));

		/* Only the recognized local import, editor, copy and saved-remote source tags count as owned
		installations. Empty source tags remain compatible with older entries */
		return source_text == ""
			|| source_text == "browser_custom"
			|| source_text == "browser_import"
			|| source_text == "character_maker"
			|| source_text == "character_maker_edit"
			|| source_text == "official_copy"
			|| source_text == "custom_copy"
			|| source_text == "remote_saved"
			|| source_text == "custom";
	}

	/// @description Test current discovery and saved owned browser-index entries for a local key collision
	/// @param {String} local_key Candidate installation identity
	/// @returns {Bool} Whether the local key is already reserved
	browser_index_local_key_exists = function(local_key)
	{
		/* key_text is the normalized local installation key checked for browser naming collisions */
		var key_text = sanitize_key(local_key);

		/* entry_index visits the currently discovered entries before checking the persisted browser
		index */
		for (var entry_index = 0; entry_index < array_length(characters); entry_index++)
		{
			/* An existing matching registry key already occupies this local installation name */
			if (characters[entry_index].key == key_text)
			{
				return true;
			}
		}

		/* Without a saved settings file there are no persisted browser names to check */
		if (!file_exists(settings_file))
		{
			return false;
		}

		try
		{
			ini_open(settings_file);

			/* count is the number of persisted browser index entries */
			var count = max(0, floor(real(ini_read_real(browser_index_section, browser_index_count_key, 0))));

			/* i visits their zero-based numeric slots to find an owned matching local key */
			for (var i = 0; i < count; i++)
			{
				/* saved_local_key is this slot's saved local identity and saved_source records its
				ownership tag */
				var saved_local_key = sanitize_key(ini_read_string(browser_index_section, "local_key_" + string(i), ""));
				var saved_source = string(ini_read_string(browser_index_section, "source_" + string(i), ""));

				/* Skip entries with unrecognized ownership or hashed network keys, since they do not
				reserve a locally installed browser name here */
				if (!browser_index_source_is_owned(saved_source)
				|| is_network_custom_key(saved_local_key))
				{
					continue;
				}

				/* A matching owned saved key reserves the candidate even before it has been scanned
				into the registry */
				if (saved_local_key == key_text)
				{
					ini_close();
					return true;
				}
			}
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not read browser custom character index: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		return false;
	}

	/// @description Choose an unused browser local identity from a sanitized basename, hash prefix and optional numeric suffix
	/// @param {String} base_name_text Requested installation name
	/// @param {String} hash_text PNG content identifier
	/// @returns {String} Unique custom local key
	browser_unique_local_key = function(base_name_text, hash_text)
	{
		/* base_key combines the sanitized requested name and first eight content-hash characters.
		candidate initially uses that custom key, and suffix starts at 2 for collisions */
		var base_key = safe_folder_key(base_name_text) + "_" + string_copy(safe_hash_key(hash_text), 1, 8);
		var candidate = custom_prefix + base_key;
		var suffix = 2;

		/* Keep adding numeric suffixes while the candidate local key exists in memory or the saved
		browser index */
		while (browser_index_local_key_exists(candidate))
		{
			candidate = custom_prefix + base_key + "_" + string(suffix);
			suffix++;
		}

		return candidate;
	}

	/// @description Decode and validate an up-to-256-KiB 48x76 PNG, releasing failures and transferring buffer ownership on success
	/// @param {String} base64_text Complete encoded PNG
	/// @returns {Struct} ok, buffer, base64, byte_size, hash and message. A successful buffer is caller-owned and must be deleted
	validate_raw_character_base64 = function(base64_text)
	{
		/* result begins with rejected state, no decoded buffer, the submitted encoded text, zero byte
		count, no hash and a provisional invalid-PNG message */
		var result =
		{
			ok: false,
			buffer: noone,
			base64: string(base64_text),
			byte_size: 0,
			hash: "",
			message: "Invalid custom character PNG."
		};

		/* decoded_buffer starts without an owned handle and is released on failure or transferred to
		result.buffer on success */
		var decoded_buffer = noone;
		try
		{
			decoded_buffer = buffer_base64_decode(base64_text);

			/* An undefined or missing decoded buffer stops validation before attempting byte or header
			reads */
			if (is_undefined(decoded_buffer)
			|| !buffer_exists(decoded_buffer))
			{
				result.message = "Could not decode character PNG.";
				return result;
			}

			/* byte_size measures the actual decoded image allocation in bytes */
			var byte_size = buffer_get_size(decoded_buffer);
			result.byte_size = byte_size;

			/* Reject empty PNG data or allocations above the 262144-byte character-transfer limit */
			if (byte_size <= 0 || byte_size > character_max_bytes)
			{
				result.message = "Character PNG must be 256 KB or smaller.";
			}

			/* Content within the size limit proceeds to PNG header and dimensions inspection */
			else
			{
				/* png_info reports the decoded header type and pixel dimensions without retaining
				buffer ownership */
				var png_info = png_dimensions_from_buffer(decoded_buffer);

				/* A malformed PNG header supplies the validation diagnostic */
				if (!png_info.ok)
				{
					result.message = png_info.message;
				}

				/* The PNG must contain the exact 48 by 76 pixel character-sheet grid */
				else if (png_info.width != expected_sheet_w || png_info.height != expected_sheet_h)
				{
					result.message = "PNG must be exactly " + string(expected_sheet_w) + "x" + string(expected_sheet_h) + " pixels. This file is " + string(png_info.width) + "x" + string(png_info.height) + ".";
				}

				/* A recognized sheet of the required size transfers the decoded buffer to the
				successful result along with its content hash and byte count */
				else
				{
					result.hash = buffer_hash12(decoded_buffer, byte_size);
					result.buffer = decoded_buffer;
					result.ok = true;
					result.message = "";
					return result;
				}
			}
		}
		catch(e)
		{
			result.message = "Could not decode character PNG: " + string(e.message);
		}

		/* Release the temporary decoded buffer on unsuccessful validation. Successful returns leave it
		owned by the caller */
		if (!is_undefined(decoded_buffer)
		&& buffer_exists(decoded_buffer))
		{
			buffer_delete(decoded_buffer);
		}

		return result;
	}

	/// @description Inspect a stored browser PNG and return encoded content after releasing its locally loaded buffer
	/// @param {String} storage_file Browser PNG filename
	/// @returns {Struct} ok, base64, byte_size, hash and message without an owned buffer
	browser_load_storage_base64 = function(storage_file)
	{
		/* result starts as a failed browser-file read with no encoded data, byte count or hash,
		retaining a diagnostic for the caller */
		var result =
		{
			ok: false,
			base64: "",
			byte_size: 0,
			hash: "",
			message: "Could not read browser custom character."
		};

		/* source_buffer starts with no owned resource and is released after the browser file is
		inspected and encoded */
		var source_buffer = noone;
		try
		{
			source_buffer = buffer_load(storage_file);

			/* An undefined or missing loaded buffer cannot provide a browser PNG and returns the
			failed read result */
			if (is_undefined(source_buffer)
			|| !buffer_exists(source_buffer))
			{
				return result;
			}

			/* byte_size is the stored image's actual byte count for validation and later transfer
			metadata */
			var byte_size = buffer_get_size(source_buffer);
			result.byte_size = byte_size;

			/* Reject empty browser image files and files larger than 262144 bytes */
			if (byte_size <= 0 || byte_size > character_max_bytes)
			{
				result.message = "Stored character PNG must be 256 KB or smaller.";
			}

			/* A file within the transfer-size limit can be checked for PNG header and dimensions */
			else
			{
				/* png_info retains the inspected stored-image header and its diagnostic */
				var png_info = png_dimensions_from_buffer(source_buffer);

				/* A malformed header supplies the browser-file validation error */
				if (!png_info.ok)
				{
					result.message = png_info.message;
				}

				/* A stored PNG with the wrong 48 by 76 pixel dimensions cannot be registered as a
				character */
				else if (png_info.width != expected_sheet_w || png_info.height != expected_sheet_h)
				{
					result.message = "Stored PNG has the wrong size.";
				}

				/* A correctly sized PNG supplies its hash and base64 representation and clears the
				provisional error */
				else
				{
					result.hash = buffer_hash12(source_buffer, byte_size);
					result.base64 = buffer_base64_encode(source_buffer, 0, byte_size);
					result.ok = true;
					result.message = "";
				}
			}
		}
		catch(e)
		{
			result.message = "Could not read browser custom character: " + string(e.message);
		}

		/* Release the loaded browser-file buffer after inspection, leaving only strings and scalar
		metadata in the result */
		if (!is_undefined(source_buffer)
		&& buffer_exists(source_buffer))
		{
			buffer_delete(source_buffer);
		}

		return result;
	}

	/// @description Register retained browser PNG data as an installed or remote character and remember its manifest
	/// @param {String} local_key_text Installed local identity, unused for remote entries
	/// @param {Struct} manifest Custom transfer metadata
	/// @param {String} base64_text Complete encoded PNG retained by the record
	/// @param {Bool} remote_value Whether this is a received cache entry
	/// @param {String} storage_file_text Owned browser PNG filename. Defaults to empty when omitted
	/// @returns {Bool} Whether the record was appended
	add_browser_entry = function(local_key_text, manifest, base64_text, remote_value, storage_file_text = "")
	{
		/* Register only a custom manifest with required fields and nonempty encoded PNG data */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| string_trim(string(base64_text)) == "")
		{
			return false;
		}

		/* key_text uses the network key for remote cache entries and the normalized local key for
		owned installations */
		var key_text = remote_value ? manifest.network_key : sanitize_key(local_key_text);
		characters[array_length(characters)] = make_entry(
			key_text,
			manifest.display_label,
			character_data_url(base64_text),
			false,
			manifest.network_key,
			manifest.hash,
			remote_value,

			/* Older manifests default to enabled clone/cache permissions and empty creator/copy
			provenance when their optional fields are absent */
			variable_struct_exists(manifest, "allow_clone") ? manifest.allow_clone : true,
			variable_struct_exists(manifest, "allow_multiplayer_temp_cache") ? manifest.allow_multiplayer_temp_cache : true,
			variable_struct_exists(manifest, "original_creator_name") ? manifest.original_creator_name : "",
			variable_struct_exists(manifest, "original_creator_id") ? manifest.original_creator_id : "",
			variable_struct_exists(manifest, "copied_from_hash") ? manifest.copied_from_hash : "",
			base64_text,
			manifest.byte_size,
			storage_file_text
		);
		remember_manifest(manifest);
		return true;
	}

	/// @description Persist a custom manifest and its PNG filename in an existing or newly appended browser-index slot
	/// @param {String} local_key_text Installed custom identity
	/// @param {Struct} manifest Custom identity, permissions and provenance
	/// @param {String} storage_file_text Saved browser PNG filename
	/// @param {String} source_text Installation source tag. Defaults to browser_custom when omitted
	/// @returns {Bool} Whether index metadata was written
	write_browser_index_entry = function(local_key_text, manifest, storage_file_text, source_text = "browser_custom")
	{
		/* Browser index persistence requires a custom manifest with the required metadata fields */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom)
		{
			return false;
		}

		try
		{
			/* local_key_text_clean normalizes the browser installation identity written to its index
			slot */
			var local_key_text_clean = sanitize_key(local_key_text);
			ini_open(settings_file);

			/* count is the existing index size and slot starts unresolved until a matching local key
			is found */
			var count = max(0, floor(real(ini_read_real(browser_index_section, browser_index_count_key, 0))));
			var slot = noone;

			/* i visits every saved zero-based browser slot to update an existing installation instead
			of appending a duplicate */
			for (var i = 0; i < count; i++)
			{
				/* saved_local_key is this slot's normalized local identity */
				var saved_local_key = sanitize_key(ini_read_string(browser_index_section, "local_key_" + string(i), ""));

				/* A matching key reuses its existing slot for the new manifest and storage filename */
				if (saved_local_key == local_key_text_clean)
				{
					slot = i;
					break;
				}
			}

			/* An unresolved slot appends one new index entry and increases the persisted entry count */
			if (slot == noone)
			{
				slot = count;
				count++;
				ini_write_real(browser_index_section, browser_index_count_key, count);
			}

			ini_write_string(browser_index_section, "local_key_" + string(slot), local_key_text_clean);
			ini_write_string(browser_index_section, "network_key_" + string(slot), manifest.network_key);
			ini_write_string(browser_index_section, "display_label_" + string(slot), manifest.display_label);
			ini_write_string(browser_index_section, "safe_name_" + string(slot), manifest.safe_name);
			ini_write_string(browser_index_section, "hash_" + string(slot), manifest.hash);
			ini_write_string(browser_index_section, "storage_file_" + string(slot), storage_file_text);
			ini_write_string(browser_index_section, "source_" + string(slot), source_text);

			/* Clone permission is persisted as 1 or 0 after resolving the manifest's custom clone flag */
			ini_write_real(browser_index_section, "allow_clone_" + string(slot), manifest_allows_clone(manifest) ? 1 : 0);

			/* A present enabled cache permission is saved as 1, otherwise 0. This writer treats
			missing cache permission as disabled */
			ini_write_real(browser_index_section, "allow_multiplayer_temp_cache_" + string(slot), variable_struct_exists(manifest, "allow_multiplayer_temp_cache") && metadata_bool(manifest.allow_multiplayer_temp_cache, true) ? 1 : 0);

			/* Persist optional creator and copy metadata when present, otherwise write empty fields
			for compatibility with older manifests */
			ini_write_string(browser_index_section, "original_creator_name_" + string(slot), variable_struct_exists(manifest, "original_creator_name") ? metadata_text(manifest.original_creator_name, 64) : "");
			ini_write_string(browser_index_section, "original_creator_id_" + string(slot), variable_struct_exists(manifest, "original_creator_id") ? metadata_text(manifest.original_creator_id, 64) : "");
			ini_write_string(browser_index_section, "copied_from_hash_" + string(slot), variable_struct_exists(manifest, "copied_from_hash") ? optional_hash_key(manifest.copied_from_hash) : "");
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not write browser custom character index: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Update the clone flag for an existing saved browser local key
	/// @param {String} local_key_text Installed identity to find
	/// @param {Bool} allow_clone_value Requested permission
	/// @returns {Bool} Whether a matching saved slot was updated
	update_browser_index_allow_clone = function(local_key_text, allow_clone_value)
	{
		/* Without a saved browser index there is no installed clone setting to update */
		if (!file_exists(settings_file))
		{
			return false;
		}

		try
		{
			/* key_text normalizes the installed browser key being edited */
			var key_text = sanitize_key(local_key_text);
			ini_open(settings_file);

			/* count is the number of persisted slots available for this permission lookup */
			var count = max(0, floor(real(ini_read_real(browser_index_section, browser_index_count_key, 0))));

			/* i visits saved zero-based browser slots until the requested local installation is found */
			for (var i = 0; i < count; i++)
			{
				/* A matching local key receives the numeric clone permission and returns success after
				closing the INI */
				if (sanitize_key(ini_read_string(browser_index_section, "local_key_" + string(i), "")) == key_text)
				{
					/* Store enabled cloning as 1 and disabled cloning as 0 */
					ini_write_real(browser_index_section, "allow_clone_" + string(i), metadata_bool(allow_clone_value, true) ? 1 : 0);
					ini_close();
					return true;
				}
			}
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not update browser custom character save permission: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		return false;
	}

	/// @description Reload owned browser index entries, validating their stored PNGs and correcting stale network content identities
	scan_browser_custom_entries = function()
	{
		/* A missing browser settings file has no saved custom installations to discover */
		if (!file_exists(settings_file))
		{
			return;
		}

		try
		{
			ini_open(settings_file);

			/* count is the persisted browser index length */
			var count = max(0, floor(real(ini_read_real(browser_index_section, browser_index_count_key, 0))));

			/* i visits each saved slot to validate its ownership and reload its PNG data */
			for (var i = 0; i < count; i++)
			{
				/* local_key_text is the saved installation identity, storage_file locates its PNG, and
				source_text records its ownership category */
				var local_key_text = sanitize_key(ini_read_string(browser_index_section, "local_key_" + string(i), ""));
				var storage_file = string(ini_read_string(browser_index_section, "storage_file_" + string(i), ""));
				var source_text = string(ini_read_string(browser_index_section, "source_" + string(i), ""));

				/* Skip default bundled entries, hashed network identities, missing image filenames and
				unrecognized source tags so only owned browser installations enter discovery */
				if (local_key_text == default_key
				|| is_network_custom_key(local_key_text)
				|| storage_file == ""
				|| !browser_index_source_is_owned(source_text))
				{
					continue;
				}

				/* loaded inspects and encodes the saved PNG without retaining a buffer in the registry */
				var loaded = browser_load_storage_base64(storage_file);

				/* An unreadable or invalid stored PNG is omitted from the discovered character list */
				if (!loaded.ok)
				{
					debug_error("Skipping browser custom character " + local_key_text + ": " + loaded.message);
					continue;
				}

				/* safe_name is the installed key's basename, display_label is its persisted human name
				and network_key_text is its recorded transfer identity */
				var safe_name = safe_folder_key(ini_read_string(browser_index_section, "safe_name_" + string(i), custom_key_name_part(local_key_text)));
				var display_label = string(ini_read_string(browser_index_section, "display_label_" + string(i), display_from_slug(safe_name)));
				var network_key_text = sanitize_key(ini_read_string(browser_index_section, "network_key_" + string(i), ""));

				/* Rebuild a missing network identity or one with a mismatched hash from the validated
				PNG's actual content identifier */
				if (!is_network_custom_key(network_key_text)
				|| custom_key_hash_part(network_key_text) != loaded.hash)
				{
					network_key_text = custom_prefix + safe_name + network_custom_separator + loaded.hash;
				}

				/* chunk_count counts 12000-character fragments needed to transfer the stored encoded
				PNG, with at least one fragment */
				var chunk_count = max(1, ceil(string_length(loaded.base64) / character_chunk_size));

				/* manifest combines the validated PNG with saved permissions and provenance. Missing
				browser permission keys default to enabled in this reader */
				var manifest = make_manifest_struct(
					network_key_text,
					display_label,
					safe_name,
					loaded.hash,
					true,
					loaded.byte_size,
					chunk_count,
					loaded.base64,
					ini_read_real(browser_index_section, "allow_clone_" + string(i), 1) != 0,
					ini_read_real(browser_index_section, "allow_multiplayer_temp_cache_" + string(i), 1) != 0,
					ini_read_string(browser_index_section, "original_creator_name_" + string(i), ""),
					ini_read_string(browser_index_section, "original_creator_id_" + string(i), ""),
					ini_read_string(browser_index_section, "copied_from_hash_" + string(i), "")
				);
				add_browser_entry(local_key_text, manifest, loaded.base64, false, storage_file);
			}
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not scan browser custom characters: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}
	}

	/// @description Check discovered installed custom records for the same network identity or content identifier
	/// @param {String} network_key_text Requested network identity
	/// @param {String} hash_text Requested content hash
	/// @returns {Bool} Whether an installed nonremote custom match exists
	installed_character_already_scanned = function(network_key_text, hash_text)
	{
		/* clean_network_key normalizes the remote identity and clean_hash normalizes its content
		identifier for duplicate-installed checks */
		var clean_network_key = sanitize_key(network_key_text);
		var clean_hash = safe_hash_key(hash_text);

		/* entry_index visits all discovered entries until an installed custom package matches */
		for (var entry_index = 0; entry_index < array_length(characters); entry_index++)
		{
			/* entry is the current registry record under consideration */
			var entry = characters[entry_index];

			/* Official entries and remote cache entries cannot satisfy the installed-custom duplicate
			test */
			if (entry.official
			|| (variable_struct_exists(entry, "remote") && entry.remote))
			{
				continue;
			}

			/* entry_network_key uses the recorded network identity or local key. entry_hash prefers
			character_hash, then hash, then its network key's identifier */
			var entry_network_key = variable_struct_exists(entry, "network_key") ? entry.network_key : entry.key;
			var entry_hash = variable_struct_exists(entry, "character_hash") ? entry.character_hash : (variable_struct_exists(entry, "hash") ? entry.hash : custom_key_hash_part(entry_network_key));

			/* A matching network key or matching content hash means an installed custom character
			already provides this remote image */
			if (entry_network_key == clean_network_key || entry_hash == clean_hash)
			{
				return true;
			}
		}

		return false;
	}

	/// @description Retain completed remote PNG base64 in session memory by shared image identity
	/// @param {Struct} manifest Custom transfer metadata
	/// @param {String} base64_text Complete encoded PNG
	/// @returns {Bool} Whether the in-memory remote record was stored
	remember_browser_remote_character = function(manifest, base64_text)
	{
		/* Remember only custom manifests with required fields and nonempty PNG base64 */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| string_trim(string(base64_text)) == "")
		{
			return false;
		}

		/* key_text is the normalized remote identity used to replace a prior browser cache record */
		var key_text = sanitize_key(manifest.network_key);

		/* remote_index visits all in-memory remote browser characters before deciding to append one */
		for (var remote_index = 0; remote_index < array_length(browser_remote_characters); remote_index++)
		{
			/* A matching remote key replaces its manifest and base64 record so discovery sees the
			newest completed transfer */
			if (browser_remote_characters[remote_index].manifest.network_key == key_text)
			{
				browser_remote_characters[remote_index] =
				{
					manifest: manifest,
					base64: string(base64_text)
				};
				return true;
			}
		}

		/* A new browser remote record owns its manifest reference and encoded PNG string for this
		registry's lifetime, without allocating a sprite yet */
		browser_remote_characters[array_length(browser_remote_characters)] =
		{
			manifest: manifest,
			base64: string(base64_text)
		};
		return true;
	}

	/// @description Publish session-memory downloads into discovery while skipping installed custom images
	scan_browser_remote_entries = function()
	{
		/* remote_index visits the completed remote browser records to publish them into discovery */
		for (var remote_index = 0; remote_index < array_length(browser_remote_characters); remote_index++)
		{
			/* remote_entry is the cached manifest/data pair and manifest is the metadata used for
			duplicate checks and registration */
			var remote_entry = browser_remote_characters[remote_index];
			var manifest = remote_entry.manifest;

			/* An already installed matching identity or content hash keeps the remote cache copy out
			of the discovered entries */
			if (installed_character_already_scanned(manifest.network_key, manifest.hash))
			{
				continue;
			}

			add_browser_entry(manifest.network_key, manifest, remote_entry.base64, true, "");
		}
	}
	#endregion /* Browser Character Storage END */

	#region /* Character Discovery and Lookup */
	/// @description Discover native installed custom package directories and close the filesystem finder afterward
	scan_custom_folder = function()
	{
		/* root_path is the native installed-custom directory searched for package subfolders */
		var root = custom_folder_path();

		/* A missing installed directory has no native custom packages to scan */
		if (!directory_exists(root))
		{
			return;
		}

		/* search_mask targets all immediate children of the custom-character root */
		var search_mask = path_join(root, "*");

		/* File attributes are only supported by GameMaker on Windows */
		/* find_attributes requests directory entries on Windows and the platform's normal search mode
		elsewhere */
		var find_attributes = os_type == os_windows ? fa_directory : fa_none;

		/* found holds the first filesystem search result and becomes empty when enumeration is
		exhausted */
		var found = file_find_first(search_mask, find_attributes);

		/* Continue visiting search results while found names remain available, then close the shared
		finder */
		while (found != "")
		{
			/* folder_key is the leaf name of the current search result */
			var folder_key = path_leaf(found);

			/* Skip the dot directory entries so only actual package candidates are inspected */
			if (folder_key != "." && folder_key != "..")
			{
				/* folder_path initially combines the root and discovered leaf name */
				var folder_path = path_join(root, folder_key);

				/* When the joined path is missing but the search result is already an existing
				directory path, use that returned path directly */
				if (!directory_exists(folder_path) && directory_exists(found))
				{
					folder_path = found;
				}

				/* Only existing directories are inspected as native custom packages */
				if (directory_exists(folder_path))
				{
					add_custom_entry(folder_path, folder_key);
				}
			}

			found = file_find_next();
		}

		file_find_close();
	}

	/// @description Discover native received-character cache directories and close the filesystem finder afterward
	scan_temp_folder = function()
	{
		/* root_path is the temporary remote-character cache directory searched for received packages */
		var root = temp_character_cache_path();

		/* A missing cache directory has no received native character packages to discover */
		if (!directory_exists(root))
		{
			return;
		}

		/* search_mask targets immediate children of the temporary-character root */
		var search_mask = path_join(root, "*");

		/* File attributes are only supported by GameMaker on Windows */
		/* find_attributes requests directory results on Windows and normal platform results elsewhere */
		var find_attributes = os_type == os_windows ? fa_directory : fa_none;

		/* found is the current filesystem result and becomes empty after the final cache entry */
		var found = file_find_first(search_mask, find_attributes);

		/* Inspect each available search result until enumeration is exhausted, then close the shared
		finder */
		while (found != "")
		{
			/* folder_key is the current received-package directory's leaf name */
			var folder_key = path_leaf(found);

			/* Dot entries are skipped because they identify directory navigation rather than a cached
			character package */
			if (folder_key != "." && folder_key != "..")
			{
				/* folder_path joins the cache root and current leaf name */
				var folder_path = path_join(root, folder_key);

				/* If the search result already names an existing directory and the joined path does
				not, use the returned directory path */
				if (!directory_exists(folder_path) && directory_exists(found))
				{
					folder_path = found;
				}

				/* Only existing directories can be registered as received temporary character packages */
				if (directory_exists(folder_path))
				{
					add_temp_entry(folder_path, folder_key);
				}
			}

			found = file_find_next();
		}

		file_find_close();
	}

	/// @description Build platform discovery from bundled, installed and received records, reusing the list unless forced
	/// @param {Bool} force Whether to repeat platform discovery. Defaults to false when omitted
	/// @returns {Array} Current shared character records
	scan = function(force = false)
	{
		/* Reuse the existing discovery list after the first scan unless force requests fresh platform
		discovery */
		if (scanned && !force)
		{
			return characters;
		}

		characters = [];
		add_official_entries();

		/* Browser builds discover owned files from their saved index and completed remote characters
		from the in-memory cache */
		if (uses_browser_storage())
		{
			scan_browser_custom_entries();
			scan_browser_remote_entries();
		}

		/* Native builds discover permanent custom packages and temporary received packages from their
		directories */
		else
		{
			scan_custom_folder();
			scan_browser_remote_entries();
			scan_temp_folder();
		}
		scanned = true;
		return characters;
	}

	/// @description Force a fresh platform discovery while reusing cached bundled records
	/// @returns {Array} Current shared character records
	refresh = function()
	{
		scanned = false;
		return scan(true);
	}

	/// @description Resolve exact local/network keys first, then prefer installed entries over remote entries during custom hash/name fallback
	/// @param {String} raw_key Character key to normalize and look up
	/// @returns {Real} Index in characters, or noone when unavailable
	find_index = function(raw_key)
	{
		/* key_text normalizes the requested local or network identity before searching discovered
		entries */
		var key_text = sanitize_key(raw_key);
		scan(false);

		/* matching_custom_index starts unresolved for a possible remote fallback. key_is_custom
		selects custom-name/hash matching, and key_hash/key_name stay empty for official identities */
		var matching_custom_index = noone;
		var key_is_custom = is_custom_key(key_text);
		var key_hash = key_is_custom ? custom_key_hash_part(key_text) : "";
		var key_name = key_is_custom ? custom_key_name_part(key_text) : "";

		/* entry_index visits discovered entries in order to resolve exact identities or custom
		content/name equivalents */
		for (var entry_index = 0; entry_index < array_length(characters); entry_index++)
		{
			/* entry is the candidate record and entry_network_key falls back to its local key when no
			network identity is stored */
			var entry = characters[entry_index];
			var entry_network_key = variable_struct_exists(entry, "network_key") ? entry.network_key : entry.key;

			/* An exact local or network key match returns immediately, preserving direct identity
			lookup */
			if (entry.key == key_text || entry_network_key == key_text)
			{
				return entry_index;
			}

			/* Non-custom queries and official candidates cannot participate in custom hash/name
			fallback matching */
			if (!key_is_custom || entry.official)
			{
				continue;
			}

			/* entry_hash uses a recorded hash when present or extracts the candidate network key's
			identifier */
			var entry_hash = variable_struct_exists(entry, "character_hash") ? entry.character_hash : custom_key_hash_part(entry_network_key);

			/* A query carrying a hash compares content identifiers. A name-only custom query compares
			the candidate's local or network basename instead */
			var entry_matches = key_hash != ""
				? entry_hash == key_hash
				: (custom_key_name_part(entry.key) == key_name || custom_key_name_part(entry_network_key) == key_name);

			/* Matching custom candidates may supply an installed entry immediately or a remote
			fallback if no installed entry matches later */
			if (entry_matches)
			{
				/* entry_remote is true only when the optional remote field exists and is enabled */
				var entry_remote = variable_struct_exists(entry, "remote") && entry.remote;

				/* Prefer an installed custom match over a remembered remote match for fallback lookup */
				if (!entry_remote)
				{
					return entry_index;
				}

				matching_custom_index = entry_index;
			}
		}

		return matching_custom_index;
	}

	/// @description Test whether discovery resolves a local or network character identity
	/// @param {String} raw_key Requested identity
	/// @returns {Bool} Whether a matching entry exists
	has_key = function(raw_key)
	{
		/* A resolved registry index means this identity has a discovered entry */
		return find_index(raw_key) != noone;
	}

	/// @description Retrieve a discovered record, resolving missing identities to the bundled default or a new fallback record
	/// @param {String} raw_key Requested character identity
	/// @returns {Struct} Matching or default character entry
	entry_for_key = function(raw_key)
	{
		/* entry_index resolves the requested identity or stays noone when discovery has no matching
		entry */
		var entry_index = find_index(raw_key);

		/* Return the matched registry record whenever one was found */
		if (entry_index != noone)
		{
			return characters[entry_index];
		}

		/* default_index locates the bundled fallback entry used when the requested identity is missing */
		var default_index = find_index(default_key);

		/* If discovery lacks even the default entry, construct a fallback record. Otherwise borrow the
		existing default record */
		return default_index == noone ? make_entry(default_key, "Player 1", "Characters/Player1/sprites/player.png", true) : characters[default_index];
	}

	/// @description Test unavailable identities while treating the bundled default as always available
	/// @param {String} raw_key Requested character identity
	/// @returns {Bool} Whether a nondefault identity cannot be resolved
	is_missing = function(raw_key)
	{
		/* key_text is the normalized identity tested for unavailable-character status */
		var key_text = sanitize_key(raw_key);

		/* The default bundled key is never reported as missing, even when its fallback record has not
		been scanned */
		if (key_text == default_key)
		{
			return false;
		}

		/* Any other identity is missing when registry lookup cannot resolve it */
		return find_index(key_text) == noone;
	}

	/// @description Resolve a discovered character label or remembered missing-remote label
	/// @param {String} raw_key Character identity
	/// @returns {String} Available label or Missing custom character fallback
	display_name = function(raw_key)
	{
		/* key_text normalizes the identity whose human-readable name is requested */
		var key_text = sanitize_key(raw_key);

		/* An unavailable key can still have remembered remote display metadata */
		if (is_missing(key_text))
		{
			/* remote_manifest is the previously received metadata for the missing identity */
			var remote_manifest = manifest_for_network_key(key_text);

			/* Use a nonempty remembered display name when available, otherwise show the missing-custom
			fallback label */
			if (remote_manifest != noone
			&& string_trim(remote_manifest.display_label) != "")
			{
				return remote_manifest.display_label;
			}


			return "Missing custom character";
		}

		return entry_for_key(key_text).display_label;
	}

	/// @description Identify a discovered character record belonging to the received cache
	/// @param {String} raw_key Character identity
	/// @returns {Bool} Whether a matching entry has remote enabled
	entry_is_remote = function(raw_key)
	{
		/* entry_index locates the requested discovered character for its remote-cache test */
		var entry_index = find_index(raw_key);

		/* A missing entry does not count as a remote cache record */
		if (entry_index == noone)
		{
			return false;
		}

		/* entry is the matched character record */
		var entry = characters[entry_index];

		/* An entry counts as remote only when its optional remote field exists and is true */
		return variable_struct_exists(entry, "remote") && entry.remote;
	}

	/// @description Allow structured official and installed custom records in local character selection while excluding remote cache records
	/// @param {Struct} entry Candidate discovered record
	/// @returns {Bool} Whether the record is locally selectable
	entry_is_selectable = function(entry)
	{
		/* A selectable record must be a struct outside the remote cache, allowing bundled and
		installed custom characters in local navigation */
		return is_struct(entry) && !(variable_struct_exists(entry, "remote") && entry.remote);
	}

	/// @description Count selectable records and format the selected entry's one-based position among them
	/// @returns {String} Selected position/total, with position zero when selection is unmatched
	selected_position_text = function()
	{
		load_selected_key();
		scan(false);

		/* selected_position starts zero until a selectable selection is found. selectable_total starts
		zero for the number of eligible entries */
		var selected_position = 0;
		var selectable_total = 0;

		/* entry_index visits all discovered characters, counting only entries available for local
		selection */
		for (var entry_index = 0; entry_index < array_length(characters); entry_index++)
		{
			/* entry is the current discovery record being considered for selectable-character counting */
			var entry = characters[entry_index];

			/* Skip remote-cache or otherwise unselectable entries so they do not change local
			selection positions */
			if (!entry_is_selectable(entry))
			{
				continue;
			}

			selectable_total++;

			/* A selectable key matching the selection records the current one-based position among
			eligible entries */
			if (entry.key == selected_key)
			{
				selected_position = selectable_total;
			}
		}

		return string(selected_position) + "/" + string(selectable_total);
	}

	/// @description Check for an installed custom record matching a network identity or its nonempty content hash
	/// @param {String} raw_key Custom network identity
	/// @returns {Bool} Whether an installed nonremote custom match exists
	has_installed_network_key = function(raw_key)
	{
		/* key_text is the normalized custom network identity and key_hash is its embedded content
		identifier */
		var key_text = sanitize_key(raw_key);
		var key_hash = custom_key_hash_part(key_text);
		scan(false);

		/* entry_index visits discovered entries looking for an installed custom match */
		for (var entry_index = 0; entry_index < array_length(characters); entry_index++)
		{
			/* entry is the candidate registry record */
			var entry = characters[entry_index];

			/* Bundled entries cannot count as installed copies of a custom network character */
			if (entry.official)
			{
				continue;
			}

			/* entry_network_key falls back to the local key, entry_remote detects optional cache
			status, and entry_hash prefers recorded hash or the network key's identifier */
			var entry_network_key = variable_struct_exists(entry, "network_key") ? entry.network_key : entry.key;
			var entry_remote = variable_struct_exists(entry, "remote") && entry.remote;
			var entry_hash = variable_struct_exists(entry, "character_hash") ? entry.character_hash : (variable_struct_exists(entry, "hash") ? entry.hash : custom_key_hash_part(entry_network_key));

			/* Only nonremote candidates count as installed, and they must match the network identity
			or its nonempty content hash */
			if (!entry_remote
			&& (entry_network_key == key_text || (key_hash != "" && entry_hash == key_hash)))
			{
				return true;
			}
		}

		return false;
	}

	/// @description Resolve custom clone permission, allowing legacy custom manifests without the field
	/// @param {Struct} manifest Candidate custom metadata
	/// @returns {Bool} Whether a valid custom manifest permits cloning
	manifest_allows_clone = function(manifest)
	{
		/* Only custom manifests with the required shape can grant remote cloning through this
		permission test */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom)
		{
			return false;
		}

		/* Older custom manifests lacking allow_clone remain cloneable for compatibility */
		if (!variable_struct_exists(manifest, "allow_clone"))
		{
			return true;
		}

		/* An existing clone field is parsed as a Boolean with enabled fallback for an uninterpretable
		value */
		return metadata_bool(manifest.allow_clone, true);
	}

	/// @description Resolve save metadata from one owner while retaining the shared image identity
	/// @param {String} raw_key Remote artwork network key
	/// @param {Struct|Real} owner_manifest Owner-specific metadata, or undefined for legacy callers
	/// @returns {Struct|Real} Complete save metadata, or noone when supplied owner identity does not match
	remote_save_manifest = function(raw_key, owner_manifest = undefined)
	{
		var key_text = sanitize_key(raw_key);
		var payload_manifest = manifest_for_key(key_text, false);

		/* Existing character callers can use remembered metadata. Pet Card supplies its owner's
		manifest explicitly so another owner of the same image cannot replace save permission */
		if (is_undefined(owner_manifest))
		{
			return payload_manifest;
		}
		if (!manifest_is_valid_shape(owner_manifest)
		|| sanitize_key(owner_manifest.network_key) != key_text
		|| !owner_manifest.custom)
		{
			return noone;
		}
		return manifest_with_metadata(payload_manifest, owner_manifest);
	}

	/// @description Resolve a hashed custom identity's clone permission from owner or remembered metadata
	/// @param {String} raw_key Remote character network identity
	/// @param {Struct|Real} owner_manifest Optional owner-specific permission metadata
	/// @returns {Bool} Whether remembered custom metadata allows cloning
	remote_character_clone_allowed = function(raw_key, owner_manifest = undefined)
	{
		/* key_text normalizes the requested remote character identity */
		var key_text = sanitize_key(raw_key);

		/* Clone permission applies only to custom network identities carrying a content hash */
		if (!is_network_custom_key(key_text))
		{
			return false;
		}

		/* manifest is the remembered metadata whose clone flag governs this remote save */
		var manifest = remote_save_manifest(key_text, owner_manifest);
		return manifest_allows_clone(manifest);
	}

	/// @description Show saving only for downloaded, cloneable custom characters without a matching installed copy
	/// @param {String} raw_key Remote character identity
	/// @param {Struct|Real} owner_manifest Optional owner-specific permission metadata
	/// @returns {Bool} Whether the remote save action is available
	remote_character_save_available = function(raw_key, owner_manifest = undefined)
	{
		/* key_text is the normalized requested remote key */
		var key_text = sanitize_key(raw_key);

		/* Expose saving only for a downloaded remote custom character that is not already installed
		and whose remembered clone permission allows copying */
		return is_network_custom_key(key_text)
			&& entry_is_remote(key_text)
			&& !has_installed_network_key(key_text)
			&& remote_character_clone_allowed(key_text, owner_manifest);
	}

	/// @description Explain an installed remote copy or a creator-disabled save action
	/// @param {String} raw_key Remote character identity
	/// @param {Struct|Real} owner_manifest Optional owner-specific permission metadata
	/// @returns {String} Already-saved or disabled wording, otherwise empty
	remote_character_save_status = function(raw_key, owner_manifest = undefined)
	{
		/* key_text normalizes the identity whose remote-save label is requested */
		var key_text = sanitize_key(raw_key);

		/* Official and name-only keys have no remote-save status */
		if (!is_network_custom_key(key_text))
		{
			return "";
		}

		/* An installed matching custom identity reports Already saved before testing download or
		permission state */
		if (has_installed_network_key(key_text))
		{
			return "Custom character already saved";
		}

		/* An entry outside the remote cache has no downloaded remote save action to label */
		if (!entry_is_remote(key_text))
		{
			return "";
		}

		/* A downloaded remote character with disabled clone permission reports Saving disabled by
		creator */
		if (!remote_character_clone_allowed(key_text, owner_manifest))
		{
			return "Saving disabled by creator";
		}

		return "";
	}

	/// @description Label missing custom identities as downloading when metadata exists, or unavailable after failure or absent metadata
	/// @param {String} raw_key Character identity
	/// @returns {String} Download status, or empty for available and nonnetwork-custom keys
	remote_character_status = function(raw_key)
	{
		/* key_text is the normalized identity whose download status is requested */
		var key_text = sanitize_key(raw_key);

		/* Only hashed custom keys use the remote download status text */
		if (!is_network_custom_key(key_text))
		{
			return "";
		}

		/* A discovered character is already available and needs no missing-download status */
		if (!is_missing(key_text))
		{
			return "";
		}

		/* failure_index visits all remembered failed remote identities before considering pending
		metadata */
		for (var failure_index = 0; failure_index < array_length(remote_failures); failure_index++)
		{
			/* A recorded failure reports Character unavailable instead of continuing to show a
			downloading state */
			if (remote_failures[failure_index] == key_text)
			{
				return "Custom character unavailable";
			}
		}

		/* Remembered remote metadata suggests a pending download. Without metadata, report the
		character unavailable */
		if (manifest_for_network_key(key_text) != noone)
		{
			return "Downloading custom character...";
		}

		return "Custom character unavailable";
	}
	#endregion /* Character Discovery and Lookup END */

	#region /* Sprite Cache and Saved Selection */
	/// @description Locate the shared position of a character key in the aligned key/sheet cache arrays
	/// @param {String} raw_key Cached character identity
	/// @returns {Real} Zero-based cache index, or noone
	cache_index = function(raw_key)
	{
		/* key_text normalizes the identity used by the parallel sprite-cache arrays */
		var key_text = sanitize_key(raw_key);

		/* cache_index_value visits cached keys until the matching sheet position is found */
		for (var cache_index_value = 0; cache_index_value < array_length(cache_keys); cache_index_value++)
		{
			/* A matching key returns the corresponding zero-based position shared by cache_keys and
			cache_sheets */
			if (cache_keys[cache_index_value] == key_text)
			{
				return cache_index_value;
			}
		}

		return noone;
	}

	/// @description Delete a cached sheet's live sprite and remove its aligned key/sheet entries
	/// @param {String} raw_key Character identity to invalidate
	/// @returns {Bool} Whether a cache entry was removed
	drop_cached_sheet = function(raw_key)
	{
		/* found_cache_index locates the cached sheet to invalidate */
		var found_cache_index = cache_index(raw_key);

		/* An uncached identity owns no sheet resource here and needs no deletion */
		if (found_cache_index == noone)
		{
			return false;
		}

		/* character_sheet is the registry-owned cached sprite-sheet record being removed */
		var character_sheet = cache_sheets[found_cache_index];

		/* Delete a live sprite only when the cached record exposes a valid sprite field, then clear
		that handle before removing its aligned cache entries */
		if (is_struct(character_sheet)
		&& variable_struct_exists(character_sheet, "sprite")
		&& sprite_exists(character_sheet.sprite))
		{
			sprite_delete(character_sheet.sprite);
			character_sheet.sprite = noone;
		}

		array_delete(cache_keys, found_cache_index, 1);
		array_delete(cache_sheets, found_cache_index, 1);
		return true;
	}

	/// @description Return a registry-owned cached sheet using the entry lookup fallback. Callers must not delete its sprite
	/// @param {String} raw_key Local or network character key
	/// @returns {Struct} Cached lazy-loading sprite-sheet data
	get_sheet = function(raw_key)
	{
		/* key_text normalizes the request and entry resolves it with the bundled fallback when
		unavailable */
		var key_text = sanitize_key(raw_key);
		var entry = entry_for_key(key_text);

		/* resolved_key is the actual entry identity used to share cached sheets, and found_cache_index
		locates any existing cache slot */
		var resolved_key = entry.key;
		var found_cache_index = cache_index(resolved_key);

		/* Return the existing registry-owned sheet when cached instead of creating another resource
		owner */
		if (found_cache_index != noone)
		{
			return cache_sheets[found_cache_index];
		}

		/* character_sheet is a new registry-owned lazy PNG sprite sheet with the entry's frame grid,
		origin and source scaling */
		var character_sheet = new player_character_sprite_sheet(
			entry.source_file,
			entry.frame_w,
			entry.frame_h,
			entry.column_count,
			entry.row_count,
			entry.origin_x,
			entry.origin_y,
			entry.source_scale
		);

		/* Native session-only artwork retains encoded PNG bytes instead of a remote package.
		The existing decoder attempts to delete its short-lived input file after producing pixels */
		if (!uses_browser_storage()
		&& variable_struct_exists(entry, "base64") && entry.base64 != ""
		&& variable_struct_exists(entry, "remote") && entry.remote)
		{
			character_sheet.load_attempted = true;
			var decoded_surface = noone; /* Owned staging surface released after creation or failure */
			try
			{
				var decoded_pixels = RgbaPng.png_base64_to_rgba_hex(entry.base64, expected_sheet_w, expected_sheet_h, 0);
				if (decoded_pixels.ok)
				{
					decoded_surface = RgbaPng.rgba_hex_to_surface(expected_sheet_w, expected_sheet_h, decoded_pixels.hex);
					if (surface_exists(decoded_surface))
					{
						character_sheet.sprite = sprite_create_from_surface(decoded_surface, 0, 0, expected_sheet_w, expected_sheet_h, false, false, 0, 0);
					}
				}
			}
			catch(e)
			{
				debug_error("Could not decode session-only artwork: " + string(e.message));
			}
			if (surface_exists(decoded_surface))
			{
				surface_free(decoded_surface);
			}
			character_sheet.loaded = sprite_exists(character_sheet.sprite);
			character_sheet.load_failed = !character_sheet.loaded;
			character_sheet.loaded_file = "session PNG data";
			if (!character_sheet.loaded)
			{
				debug_error("Could not load session-only custom artwork.");
			}
		}

		/* insert_index is the shared new position in both key and sheet arrays, keeping cache lookup
		aligned */
		var insert_index = array_length(cache_keys);
		cache_keys[insert_index] = resolved_key;
		cache_sheets[insert_index] = character_sheet;
		return character_sheet;
	}

	/// @description Route borrowed Image Loaded async data to the matching cached sprite sheet
	/// @param {Id.DsMap} load_map Image Loaded event map
	/// @returns {Bool} Whether a cached sheet recognized the event
	handle_image_loaded = function(load_map)
	{
		/* sheet_index visits all cached sheets so browser image-load events can be offered to their
		owners */
		for (var sheet_index = 0; sheet_index < array_length(cache_sheets); sheet_index++)
		{
			/* character_sheet is the cached sprite-sheet record currently checking this borrowed
			asynchronous event map */
			var character_sheet = cache_sheets[sheet_index];

			/* A sheet accepting the image-loaded event marks the event recognized and stops dispatch */
			if (is_struct(character_sheet)
			&& variable_struct_exists(character_sheet, "mark_image_loaded")
			&& character_sheet.mark_image_loaded(load_map))
			{
				return true;
			}
		}

		return false;
	}

	/// @description Restore profile.character_key once, keeping Player 1 when the saved package is missing or remote-only
	/// @returns {String} Selected local character key
	/// @description Load and validate persisted selection once, falling back from missing or remote-only entries to player1
	/// @returns {String} Current local selected key
	load_selected_key = function()
	{
		/* Once selection is loaded, later calls reuse it instead of rereading settings */
		if (loaded_selection)
		{
			return selected_key;
		}

		loaded_selection = true;

		/* saved_key starts at the bundled default so absent or unreadable settings leave a usable
		selection */
		var saved_key = default_key;
		try
		{
			/* Read the persisted selection only when the settings file exists */
			if (file_exists(settings_file))
			{
				ini_open(settings_file);
				saved_key = ini_read_string(settings_section, settings_key, default_key);
				ini_close();
			}
		}
		catch(e)
		{
			debug_error("Could not load selected character: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
		}

		saved_key = sanitize_key(saved_key);
		refresh();

		/* saved_index resolves the saved key against freshly scanned selectable entries */
		var saved_index = find_index(saved_key);

		/* Missing or remote-only saved entries fall back to the bundled default because they cannot be
		the local selection */
		if (saved_index == noone || !entry_is_selectable(characters[saved_index]))
		{
			selected_key = default_key;

			/* Show the missing-selected warning only when the unavailable saved key differs from the
			ordinary bundled default */
			if (saved_key != default_key)
			{
				set_status("Saved character is missing, using Player 1.", make_color_rgb(255, 220, 95));
			}
		}

		/* A selectable saved entry restores its local installation key */
		else
		{
			selected_key = characters[saved_index].key;
		}

		return selected_key;
	}

	/// @description Persist the current selected character key in client settings
	/// @returns {Bool} Whether the settings write succeeded
	save_selected_key = function()
	{
		try
		{
			ini_open(settings_file);
			ini_write_string(settings_section, settings_key, selected_key);
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not save selected character: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Apply the current selected key through the assigned local player record's character setter
	/// @returns {Bool} Whether an assigned local player with the setter received the key
	apply_selected_to_local_player = function()
	{
		/* client borrows current connection state to find the local player record */
		var client = scr_get_client();

		/* Applying selection requires a structured client with an assigned player ID */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone)
		{
			return false;
		}

		/* player is the local player record whose character setter will receive the selected key */
		var player = player_controller_get_player(client.ID, false);

		/* A missing player or unavailable character setter cannot accept the selection and returns
		failure */
		if (player == noone
		|| !variable_struct_exists(player, "set_character_key"))
		{
			return false;
		}

		player.set_character_key(selected_key);
		return true;
	}
	#endregion /* Sprite Cache and Saved Selection END */

	#region /* Character Identity and Network Selection */
	/// @description Resolve local creator attribution from assigned client name, requested name or assigned chat name
	/// @returns {String} Bounded creator display name, or empty
	local_creator_name = function()
	{
		/* client borrows the client connection state to resolve the local creator's display identity */
		var client = scr_get_client();

		/* A structured client can provide an assigned or requested username before the chat fallback
		is consulted */
		if (is_struct(client))
		{
			/* Prefer a nonempty assigned_username because it is the server-approved display identity */
			if (variable_struct_exists(client, "assigned_username")
			&& string_trim(string(client.assigned_username)) != "")
			{
				return metadata_text(client.assigned_username, 64);
			}

			/* Before assignment, a nonempty requested_username supplies the user's chosen creator name */
			if (variable_struct_exists(client, "requested_username")
			&& string_trim(string(client.requested_username)) != "")
			{
				return metadata_text(client.requested_username, 64);
			}
		}

		/* chat is the shared chat state used when the client has no available username */
		var chat = scr_get_chat();

		/* Use chat's nonempty assigned username only when its state and field exist, otherwise leave
		creator attribution empty */
		if (is_struct(chat)
		&& variable_struct_exists(chat, "assigned_username")
		&& string_trim(string(chat.assigned_username)) != "")
		{
			return metadata_text(chat.assigned_username, 64);
		}

		return "";
	}

	/// @description Resolve a bounded creator identity from the client's assigned logical player ID
	/// @returns {String} Debug player identity, or empty before assignment
	local_creator_id = function()
	{
		/* client supplies the assigned logical player ID for creator provenance */
		var client = scr_get_client();

		/* Creator IDs are available only from a client with an assigned ID, so an unassigned client
		returns an empty identity */
		if (is_struct(client)
		&& variable_struct_exists(client, "ID")
		&& client.ID != noone)
		{
			return metadata_text(scr_network_debug_id_text(client.ID), 64);
		}

		return "";
	}

	/// @description Build character metadata, resolving official fallbacks or remembered remote metadata when an entry is missing
	/// @param {String} raw_key Local or network character key
	/// @param {Bool} include_base64 Whether installed custom PNG data should be included for transfer. Defaults to false when omitted
	/// @returns {Struct} Manifest with a network key, permissions, provenance, byte size, chunk count, and optional PNG data
	manifest_for_key = function(raw_key, include_base64 = false)
	{
		/* key_text normalizes the requested character key and entry_index locates its discovered
		registry entry */
		var key_text = sanitize_key(raw_key);
		var entry_index = find_index(key_text);

		/* A key missing from discovery needs either an official fallback or remembered remote transfer
		metadata */
		if (entry_index == noone)
		{
			/* Keys without a hashed custom identity resolve through official_manifest and its default
			bundled fallback */
			if (!is_network_custom_key(key_text))
			{
				return official_manifest(key_text);
			}

			/* remembered is any previously received manifest for this missing custom network key */
			var remembered = manifest_for_network_key(key_text);

			/* Return remembered remote metadata when available so an undownloaded custom character
			keeps its display name and permissions */
			if (remembered != noone)
			{
				return remembered;
			}

			/* Without remembered metadata, create a custom placeholder with its key's name/hash and
			zero payload sizes */
			return make_manifest_struct(key_text, "Custom Character", custom_key_name_part(key_text), custom_key_hash_part(key_text), true, 0, 0, "");
		}

		/* entry is the discovered character record used to resolve its official or custom manifest */
		var entry = characters[entry_index];

		/* Bundled characters use metadata-only official manifests and need no PNG transfer payload */
		if (entry.official)
		{
			return official_manifest(entry.key);
		}

		/* safe_name comes from the local custom key and display_label is the entry's selector name */
		var safe_name = custom_key_name_part(entry.key);
		var display_label = entry.display_label;

		/* hash_text retains the entry's hash when present or starts empty for entries needing their
		image inspected */
		var hash_text = variable_struct_exists(entry, "hash") ? entry.hash : "";

		/* source_file is the image path used when base64 is not already retained by the entry */
		var source_file = entry.source_file;

		/* base64_text starts empty, while byte_size and chunk_count start zero until available PNG
		data establishes transfer sizes */
		var base64_text = "";
		var byte_size = 0;
		var chunk_count = 0;

		/* An entry carrying nonempty base64 can build its manifest directly from cached encoded image
		data */
		if (variable_struct_exists(entry, "base64")
		&& string_trim(string(entry.base64)) != "")
		{
			base64_text = string(entry.base64);

			/* Use the entry's nonnegative whole byte_size when recorded, otherwise leave zero so
			validation can recover it */
			byte_size = variable_struct_exists(entry, "byte_size") ? max(0, floor(real(entry.byte_size))) : 0;

			/* A missing or zero byte count requires decoding the cached PNG to recover its actual size
			and identifier */
			if (byte_size <= 0)
			{
				/* decoded validates the cached base64 and owns a decoded buffer only when validation
				succeeds */
				var decoded = validate_raw_character_base64(base64_text);

				/* Successful cached-image validation supplies its actual content hash and byte count */
				if (decoded.ok)
				{
					hash_text = decoded.hash;
					byte_size = decoded.byte_size;

					/* Release the temporary decoded buffer after recovering metadata because this
					manifest retains encoded text rather than a buffer */
					if (buffer_exists(decoded.buffer))
					{
						buffer_delete(decoded.buffer);
					}
				}
			}
			chunk_count = max(1, ceil(string_length(base64_text) / character_chunk_size));

			/* Metadata-only requests remove base64 after measuring its chunk count, keeping payload
			and transfer description separate */
			if (!include_base64)
			{
				base64_text = "";
			}
		}

		/* Entries without retained base64 inspect their source file to establish image metadata */
		else
		{
			/* png_info owns no persistent buffer and reports the source PNG's hash, bytes and encoded
			data when valid */
			var png_info = png_hash_for_path(source_file);

			/* A validated source file supplies the custom content identifier and transfer byte count */
			if (png_info.ok)
			{
				hash_text = png_info.hash;
				byte_size = png_info.byte_size;

				/* Include encoded PNG data only when the caller requested transfer content */
				if (include_base64)
				{
					base64_text = png_info.base64;
				}
				chunk_count = max(1, ceil(string_length(png_info.base64) / character_chunk_size));
			}

			/* If source inspection fails but a network key exists, recover its hash so remembered
			identity remains available without image data */
			else if (variable_struct_exists(entry, "network_key"))
			{
				hash_text = custom_key_hash_part(entry.network_key);
			}
		}

		/* network_key_text combines the custom basename and normalized 12-character content identifier */
		var network_key_text = custom_prefix + safe_name + network_custom_separator + safe_hash_key(hash_text);
		return make_manifest_struct(
			network_key_text,
			display_label,
			safe_name,
			hash_text,
			true,
			byte_size,
			chunk_count,
			base64_text,

			/* Custom manifests preserve recorded clone/cache permissions or allow them when absent,
			and preserve creator/copy provenance with empty fallbacks for older entries */
			variable_struct_exists(entry, "allow_clone") ? entry.allow_clone : true,
			variable_struct_exists(entry, "allow_multiplayer_temp_cache") ? entry.allow_multiplayer_temp_cache : true,
			variable_struct_exists(entry, "original_creator_name") ? entry.original_creator_name : "",
			variable_struct_exists(entry, "original_creator_id") ? entry.original_creator_id : "",
			variable_struct_exists(entry, "copied_from_hash") ? entry.copied_from_hash : ""
		);
	}

	/// @description Load selection, refresh discovery and build its official or custom transfer manifest
	/// @param {Bool} include_base64 Whether to retain custom PNG data. Defaults to false when omitted
	/// @returns {Struct} Selected character manifest
	selected_manifest = function(include_base64 = false)
	{
		load_selected_key();
		refresh();
		return manifest_for_key(selected_key, include_base64);
	}

	/// @description Append manifest metadata to an already-started packet. PNG data travels separately in character chunks
	/// @param {Struct} net_ref Network writer positioned at the manifest body
	/// @param {Struct} manifest Manifest to serialize. Invalid shapes use the default official manifest
	write_manifest = function(net_ref, manifest)
	{
		/* outgoing is the supplied manifest when its required fields exist, otherwise the default
		official manifest, ensuring a consistent packet schema */
		var outgoing = manifest_is_valid_shape(manifest) ? manifest : official_manifest(default_key);
		net_ref.write(buffer_string, outgoing.network_key);
		net_ref.write(buffer_string, outgoing.display_label);

		/* Missing safe_name and hash are derived from the network key so older manifest shapes still
		serialize their identity */
		net_ref.write(buffer_string, variable_struct_exists(outgoing, "safe_name") ? outgoing.safe_name : custom_key_name_part(outgoing.network_key));
		net_ref.write(buffer_string, variable_struct_exists(outgoing, "hash") ? outgoing.hash : custom_key_hash_part(outgoing.network_key));

		/* Encode custom as a one-byte flag, with 1 for custom characters and 0 for bundled characters */
		net_ref.write(buffer_u8, outgoing.custom ? 1 : 0);
		net_ref.write(buffer_u32, max(0, floor(real(outgoing.byte_size))));
		net_ref.write(buffer_u16, max(0, floor(real(outgoing.chunk_count))));

		/* Encode the resolved clone permission as 1 or 0 in a one-byte protocol field */
		net_ref.write(buffer_u8, manifest_allows_clone(outgoing) ? 1 : 0);

		/* outgoing_allow_temp_cache is true only when the optional field exists and parses as enabled.
		A missing field is transmitted as disabled here */
		var outgoing_allow_temp_cache = variable_struct_exists(outgoing, "allow_multiplayer_temp_cache") && metadata_bool(outgoing.allow_multiplayer_temp_cache, true);

		/* Write temporary-cache permission as a one-byte 1 or 0 flag */
		net_ref.write(buffer_u8, outgoing_allow_temp_cache ? 1 : 0);

		/* Creator names and IDs are trimmed to 64 characters when present, otherwise serialized empty.
		Missing copy provenance also serializes empty */
		net_ref.write(buffer_string, variable_struct_exists(outgoing, "original_creator_name") ? metadata_text(outgoing.original_creator_name, 64) : "");
		net_ref.write(buffer_string, variable_struct_exists(outgoing, "original_creator_id") ? metadata_text(outgoing.original_creator_id, 64) : "");
		net_ref.write(buffer_string, variable_struct_exists(outgoing, "copied_from_hash") ? optional_hash_key(outgoing.copied_from_hash) : "");
	}

	/// @description Read metadata in write_manifest field order from the current packet cursor. The caller must supply a complete body
	/// @param {Struct} net_ref Primed network reader positioned at the manifest body
	/// @param {Bool} remember_received Whether to record the received metadata in remote_manifests. Defaults to true when omitted
	/// @returns {Struct} Normalized character manifest without the PNG chunk data
	read_manifest = function(net_ref, remember_received = true)
	{
		/* network_key_text, display_text, safe_name_text and hash_text read the four identity strings
		in write_manifest order */
		var network_key_text = string(net_ref.read(buffer_string));
		var display_text = string(net_ref.read(buffer_string));
		var safe_name_text = string(net_ref.read(buffer_string));
		var hash_text = string(net_ref.read(buffer_string));

		/* Any nonzero custom flag marks a custom manifest. byte_size_value is unsigned 32-bit PNG
		bytes and chunk_count_value is the unsigned 16-bit fragment count */
		var is_custom_value = net_ref.read(buffer_u8) != 0;
		var byte_size_value = net_ref.read(buffer_u32);
		var chunk_count_value = net_ref.read(buffer_u16);

		/* Nonzero one-byte flags enable cloning and temporary caching, preserving the permissions
		written by the sender */
		var allow_clone_value = net_ref.read(buffer_u8) != 0;
		var allow_temp_cache_value = net_ref.read(buffer_u8) != 0;

		/* original_creator_name_text, original_creator_id_text and copied_from_hash_text retain the
		three provenance strings following the flags */
		var original_creator_name_text = string(net_ref.read(buffer_string));
		var original_creator_id_text = string(net_ref.read(buffer_string));
		var copied_from_hash_text = string(net_ref.read(buffer_string));

		/* manifest normalizes the received values without image data because PNG base64 arrives in
		separate chunk packets */
		var manifest = make_manifest_struct(network_key_text, display_text, safe_name_text, hash_text, is_custom_value, byte_size_value, chunk_count_value, "", allow_clone_value, allow_temp_cache_value, original_creator_name_text, original_creator_id_text, copied_from_hash_text);

		/* Record the manifest in the registry only when remember_received is enabled */
		if (remember_received) remember_manifest(manifest);
		return manifest;
	}

	/// @description Write one selected-owner custom fragment when an assigned multiplayer server connection exists
	/// @param {Struct} manifest Character transfer metadata
	/// @param {Real} chunk_index Zero-based fragment index
	/// @param {String} chunk_text Base64 fragment
	/// @returns {Real} Transport send result, or zero when connection state skips sending
	send_character_chunk_to_server = function(manifest, chunk_index, chunk_text)
	{
		/* client borrows the current client connection and assigned player identity for this outgoing
		chunk */
		var client = scr_get_client();

		/* Skip sending without a structured assigned multiplayer client and usable server socket,
		returning zero without creating a packet */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone
		|| (variable_struct_exists(client, "singleplayer_mode") && client.singleplayer_mode)
		|| !is_real(client.socket)
		|| client.socket < 0)
		{
			return 0;
		}

		/* net_ref borrows the shared writer. The packet identifies the client in its header and
		repeats the character owner in the body */
		var net_ref = scr_get_network();
		net_ref.start(N_PLAYER_CHARACTER_CHUNK, client.ID);
		net_ref.write(TYPE_ID, client.ID);
		write_manifest(net_ref, manifest);
		net_ref.write(buffer_u16, chunk_index);
		net_ref.write(buffer_string, chunk_text);
		return net_ref.send_server();
	}

	/// @description Split custom base64 into ordered fragments and stop at the first negative server send result
	/// @param {Struct} manifest Custom manifest including PNG base64 and valid transfer sizes
	/// @returns {Real} Count of nonnegative fragment-send results, zero for invalid input, or -1 on send failure
	send_character_chunks_to_server = function(manifest)
	{
		/* Chunk sending requires a custom manifest with encoded data, a PNG within the 262144-byte
		limit and between 1 and 64 fragments */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| string_trim(manifest.base64) == ""
		|| manifest.byte_size <= 0
		|| manifest.byte_size > character_max_bytes
		|| manifest.chunk_count <= 0
		|| manifest.chunk_count > character_max_chunks)
		{
			return 0;
		}

		/* sent_chunks starts at zero and counts each chunk whose send helper did not return a negative
		failure */
		var sent_chunks = 0;

		/* chunk_index visits zero-based fragments up to the declared chunk_count */
		for (var chunk_index = 0; chunk_index < manifest.chunk_count; chunk_index++)
		{
			/* chunk_start converts the zero-based fragment index to a one-based string offset.
			chunk_text is at most 12000 base64 characters */
			var chunk_start = chunk_index * character_chunk_size + 1;
			var chunk_text = string_copy(manifest.base64, chunk_start, character_chunk_size);

			/* send_result is this chunk's transport outcome, including zero when the single-chunk
			helper skipped sending */
			var send_result = send_character_chunk_to_server(manifest, chunk_index, chunk_text);

			/* Stop on a negative transport failure so later fragments are not counted as sent */
			if (send_result < 0)
			{
				return -1;
			}
			sent_chunks++;
		}

		return sent_chunks;
	}

	/// @description Send each declared custom fragment to one socket, stopping at a negative send result
	/// @param {Struct} manifest Custom manifest including PNG base64
	/// @param {Real} owner_id Logical player slot whose image is transferred
	/// @param {Real} target_socket Recipient socket handle
	/// @returns {Real} Fragment count, zero for invalid input, or -1 on send failure
	send_character_chunks_to_socket = function(manifest, owner_id, target_socket)

	{
		/* Only a custom manifest with nonempty base64 and a supported fragment count can be written to
		the target socket */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| string_trim(manifest.base64) == ""
		|| manifest.chunk_count <= 0
		|| manifest.chunk_count > character_max_chunks)
		{
			return 0;
		}

		/* net_ref is the shared packet writer and sent_chunks starts with no nonnegative chunk-send
		results */
		var net_ref = scr_get_network();
		var sent_chunks = 0;

		/* chunk_index visits each zero-based declared fragment once for this target socket */
		for (var chunk_index = 0; chunk_index < manifest.chunk_count; chunk_index++)
		{
			/* chunk_start is the one-based base64 offset and chunk_text is the fragment limited to
			12000 characters */
			var chunk_start = chunk_index * character_chunk_size + 1;
			var chunk_text = string_copy(manifest.base64, chunk_start, character_chunk_size);
			net_ref.start(N_PLAYER_CHARACTER_CHUNK, owner_id);

			write_character_chunk_packet(net_ref, owner_id, manifest, chunk_index, chunk_text);

			/* send_result records this fragment's send outcome for the target socket */
			var send_result = net_ref.send(target_socket);

			/* Return failure on a negative send result rather than continuing an incomplete image
			transfer */
			if (send_result < 0)
			{
				return -1;
			}
			sent_chunks++;
		}

		return sent_chunks;
	}

	/// @description Broadcast each custom fragment and accumulate successful recipients across fragments
	/// @param {Struct} manifest Custom manifest including PNG base64
	/// @param {Real} owner_id Logical player slot whose image is transferred
	/// @param {Array} sockets Socket handles indexed by logical slot
	/// @param {Real} exception Logical slot to exclude. Defaults to noone when omitted
	/// @returns {Real} Successful recipient total, zero for invalid input, or -1 on any failed fragment broadcast
	send_character_chunks_to_all = function(manifest, owner_id, sockets, exception = noone)

	{
		/* Broadcasting requires custom encoded data and a declared count within the 1 to 64 fragment
		limit */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| string_trim(manifest.base64) == ""
		|| manifest.chunk_count <= 0
		|| manifest.chunk_count > character_max_chunks)
		{
			return 0;
		}

		/* net_ref borrows the shared writer. sent_packets starts at zero and accumulates successful
		recipients across fragment broadcasts */
		var net_ref = scr_get_network();
		var sent_packets = 0;

		/* chunk_index visits each declared base64 fragment in order before broadcasting its packet */
		for (var chunk_index = 0; chunk_index < manifest.chunk_count; chunk_index++)
		{
			/* chunk_start is the fragment's one-based text offset and chunk_text retains up to 12000
			base64 characters */
			var chunk_start = chunk_index * character_chunk_size + 1;
			var chunk_text = string_copy(manifest.base64, chunk_start, character_chunk_size);
			net_ref.start(N_PLAYER_CHARACTER_CHUNK, owner_id);
			write_character_chunk_packet(net_ref, owner_id, manifest, chunk_index, chunk_text);

			/* send_result is the broadcast's successful recipient count, or a negative result when any
			eligible send failed */
			var send_result = net_ref.send_all(sockets, exception);

			/* A failed broadcast stops the transfer and returns -1 rather than reporting a partial
			recipient total */
			if (send_result < 0)
			{
				return -1;
			}
			sent_packets += send_result;
		}

		return sent_packets;
	}

	/// @description Announce selected metadata, send following custom fragments and notify the optional transport-loss handler on failure
	/// @returns {Real} Manifest packet send result, or zero when disconnected. A later chunk failure does not replace this return value
	send_selected_to_server = function()
	{
		/* client supplies the assigned player identity, connection mode and server socket for the
		selected-character announcement */
		var client = scr_get_client();

		/* Skip the announcement without an assigned multiplayer connection and usable server socket */
		if (!is_struct(client)
		|| !variable_struct_exists(client, "ID")
		|| client.ID == noone
		|| (variable_struct_exists(client, "singleplayer_mode") && client.singleplayer_mode)
		|| !variable_struct_exists(client, "socket")
		|| !is_real(client.socket)
		|| client.socket < 0)
		{
			return 0;
		}

		/* net_ref borrows the shared writer and manifest includes the selected custom PNG data needed
		for subsequent chunk sends */
		var net = scr_get_network();
		var manifest = selected_manifest(true);
		net.start(N_PLAYER_CHARACTER, client.ID);
		write_manifest(net, manifest);

		/* send_result is the selected-character manifest packet's transport outcome */
		var send_result = net.send_server();

		/* A failed manifest send invokes the optional transport-loss handler so the client can react
		to its disconnected socket */
		if (send_result < 0
		&& variable_struct_exists(client, "mark_connection_lost"))
		{
			client.mark_connection_lost("Lost connection to server.");
		}

		/* Only a nonnegative manifest send for custom content proceeds to image chunks, keeping their
		metadata announcement first */
		else if (send_result >= 0 && manifest.custom)
		{
			/* chunk_result records the custom image's fragment-send outcome separately from the
			returned manifest-send result */
			var chunk_result = send_character_chunks_to_server(manifest);

			/* A chunk failure also invokes the optional transport-loss handler, while this function
			still returns the earlier manifest packet result */
			if (chunk_result < 0
			&& variable_struct_exists(client, "mark_connection_lost"))
			{
				client.mark_connection_lost("Lost connection to server.");
			}
		}

		return send_result;
	}

	/// @description Choose an installed selectable entry or Player 1, persist selection, update the local player, and optionally announce it
	/// @param {String} raw_key Requested local or network key
	/// @param {Bool} should_broadcast Whether to send the selection and custom PNG chunks to the server. Defaults to true when omitted
	/// @returns {String} Selected local key
	set_selected_key = function(raw_key, should_broadcast = true)
	{
		/* next_key is the normalized requested selection and may be replaced by the default bundled
		fallback */
		var next_key = sanitize_key(raw_key);
		refresh();

		/* selected_index locates the selectable installation corresponding to the requested key */
		var selected_index = find_index(next_key);

		/* A missing or remote-cache-only entry cannot become the local selected character, so choose
		the bundled default and show a warning */
		if (selected_index == noone || !entry_is_selectable(characters[selected_index]))
		{
			next_key = default_key;
			set_status("Character is missing, using Player 1.", make_color_rgb(255, 220, 95));
		}

		/* A selectable entry supplies its local key and clears the missing-character warning */
		else
		{
			next_key = characters[selected_index].key;
			set_status("Selected " + display_name(next_key) + ".", make_color_rgb(126, 245, 150));
		}

		selected_key = next_key;
		save_selected_key();
		apply_selected_to_local_player();

		/* Broadcast the selected character only when should_broadcast is enabled. Saving settings and
		applying the local player were attempted first */
		if (should_broadcast)
		{
			send_selected_to_server();
		}

		return selected_key;
	}
	#endregion /* Character Identity and Network Selection END */

	#region /* Selected Character Tools */
	/// @description Load selection and resolve its readable character label
	/// @returns {String} Selected character display name
	selected_display_name = function()
	{
		load_selected_key();
		return display_name(selected_key);
	}

	/// @description Refresh discovery and test whether selection resolves to an installed nonofficial nonremote record
	/// @returns {Bool} Whether selection is an installed custom character
	selected_is_installed_custom = function()
	{
		load_selected_key();
		return is_installed_custom(selected_key);
	}

	/// @description Test a key for a permanent local custom installation without changing selection
	/// @param {String} raw_key Character or pet artwork key
	/// @returns {Bool} Whether the record is installed custom artwork
	is_installed_custom = function(raw_key)
	{
		scan(false);

		/* Resolve the supplied artwork independently of either equipped role */
		var entry_index = find_index(raw_key);

		/* A missing requested entry cannot count as an installed custom artwork package */
		if (entry_index == noone)
		{
			return false;
		}

		/* entry is the requested artwork record checked for official and remote-cache status */
		var entry = characters[entry_index];

		/* Only nonofficial entries outside the remote cache count as installed custom characters */
		return !entry.official && !(variable_struct_exists(entry, "remote") && entry.remote);
	}

	/// @description Provide the selected sheet and provenance to the character editor, distinguishing overwritable local packages
	/// @returns {Struct} ok and message, plus a borrowed sprite and sheet metrics when ready. The registry retains sprite ownership
	selected_editor_source = function()
	{
		load_selected_key();
		return editor_source_for_key(selected_key);
	}

	/// @description Borrow a keyed sheet and its provenance for either Character Maker destination
	/// @param {String} raw_key Character or pet artwork to edit
	/// @returns {Struct} Editor source, retaining registry sprite ownership
	editor_source_for_key = function(raw_key)
	{
		refresh();

		/* Resolve the requested source without temporarily selecting it as the player character */
		var entry_index = find_index(raw_key);

		/* Missing requested artwork returns a failed source result before attempting sheet loading */
		if (entry_index == noone)
		{
			return
			{
				ok: false,
				message: "No character selected."
			};
		}

		/* character_entry carries artwork metadata, while character_sheet borrows its registry-owned
		sprite and frame metrics */
		var character_entry = characters[entry_index];
		var character_sheet = get_sheet(character_entry.key);

		/* The editor needs an actually loaded sheet with the required load methods. Pending
		asynchronous loads and invalid sheets return a failed source result */
		if (!is_struct(character_sheet)
		|| !variable_struct_exists(character_sheet, "ensure_loaded")
		|| !character_sheet.ensure_loaded()
		|| !variable_struct_exists(character_sheet, "is_loaded")
		|| !character_sheet.is_loaded())
		{
			return
			{
				ok: false,
				message: "Character sheet is still loading."
			};
		}

		/* Finish optional sheet padding before exposing frame-grid coordinates to the editor */
		if (variable_struct_exists(character_sheet, "finish_padding_if_ready"))
		{
			character_sheet.finish_padding_if_ready();
		}

		/* The editor-source result reports success and selection identity, permissions and provenance,
		borrowed sprite and source data, frame/grid/origin metrics, and expected 48 by 76 sheet
		size. Older optional metadata uses enabled permissions or empty text, and absent padding
		metrics use zero gutter and raw frame dimensions */
		return
		{
			ok: true,
			message: "",
			key: character_entry.key,
			network_key: variable_struct_exists(character_entry, "network_key") ? character_entry.network_key : character_entry.key,
			label: character_entry.display_label,
			official: character_entry.official,
			remote: variable_struct_exists(character_entry, "remote") && character_entry.remote,
			can_overwrite: !character_entry.official && !(variable_struct_exists(character_entry, "remote") && character_entry.remote),
			allow_clone: variable_struct_exists(character_entry, "allow_clone") ? metadata_bool(character_entry.allow_clone, true) : true,
			allow_multiplayer_temp_cache: variable_struct_exists(character_entry, "allow_multiplayer_temp_cache") ? metadata_bool(character_entry.allow_multiplayer_temp_cache, true) : true,
			original_creator_name: variable_struct_exists(character_entry, "original_creator_name") ? character_entry.original_creator_name : "",
			original_creator_id: variable_struct_exists(character_entry, "original_creator_id") ? character_entry.original_creator_id : "",
			copied_from_hash: variable_struct_exists(character_entry, "copied_from_hash") ? character_entry.copied_from_hash : "",
			source_file: character_entry.source_file,
			base64: variable_struct_exists(character_entry, "base64") ? character_entry.base64 : "",
			sprite: character_sheet.sprite,
			frame_w: frame_w,
			frame_h: frame_h,
			column_count: column_count,
			row_count: row_count,
			sheet_gutter: variable_struct_exists(character_sheet, "sheet_gutter") ? character_sheet.sheet_gutter : 0,
			sheet_cell_w: variable_struct_exists(character_sheet, "sheet_cell_w") ? character_sheet.sheet_cell_w : frame_w,
			sheet_cell_h: variable_struct_exists(character_sheet, "sheet_cell_h") ? character_sheet.sheet_cell_h : frame_h,
			expected_sheet_w: expected_sheet_w,
			expected_sheet_h: expected_sheet_h
		};
	}

	/// @description Resolve the selected clone-toggle state, allowing bundled, missing and legacy selections by default
	/// @returns {Bool} Selected custom permission or enabled UI fallback
	selected_allow_clone = function()
	{
		load_selected_key();
		return allow_clone_for_key(selected_key);
	}

	/// @description Read shared artwork save permission without changing the equipped player or pet
	/// @param {String} raw_key Artwork package key
	/// @returns {Bool} Stored permission, allowing bundled and older artwork by default
	allow_clone_for_key = function(raw_key)
	{
		scan(false);

		/* Lookup uses artwork identity because both equipped roles share the same package */
		var entry_index = find_index(raw_key);

		/* A missing requested entry uses enabled cloning as this UI accessor's fallback state */
		if (entry_index == noone)
		{
			return true;
		}

		/* entry is the requested package record used by the shared artwork permission control */
		var entry = characters[entry_index];

		/* Official entries show enabled cloning in this accessor so bundled characters can be copied
		into editable custom packages */
		if (entry.official)
		{
			return true;
		}

		/* Custom entries use their stored clone permission when present, otherwise allow cloning for
		older packages */
		return variable_struct_exists(entry, "allow_clone") ? metadata_bool(entry.allow_clone, true) : true;
	}

	/// @description Persist and verify an installed custom character's clone flag, then announce updated metadata
	/// @param {Any} raw_allow_clone Requested permission parsed with enabled fallback
	/// @returns {Bool} Whether an eligible installed character's permission was saved and verified
	set_selected_allow_clone = function(raw_allow_clone)
	{
		load_selected_key();
		return set_allow_clone_for_key(selected_key, raw_allow_clone, true);
	}

	/// @description Persist keyed artwork permission while retaining independent equipped roles
	/// @param {String} raw_key Installed custom artwork key
	/// @param {Any} raw_allow_clone Requested save permission
	/// @param {Bool} should_broadcast Announce changed metadata for each equipped role using this artwork
	/// @returns {Bool} Whether the saved permission was verified
	set_allow_clone_for_key = function(raw_key, raw_allow_clone, should_broadcast = true)
	{
		load_selected_key();
		refresh();

		/* Resolve the requested package rather than changing player selection to edit a pet */
		var entry_index = find_index(raw_key);

		/* A missing entry cannot persist a clone setting, so report failure */
		if (entry_index == noone)
		{
			set_status("No custom character selected.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* entry is the requested record whose package or browser index will receive the clone setting */
		var entry = characters[entry_index];

		/* Only installed custom characters can have their clone setting edited here. Official and
		remote-cache entries remain ineligible */
		if (entry.official
		|| (variable_struct_exists(entry, "remote") && entry.remote))
		{
			set_status("Only installed custom characters have save permissions.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* allow_clone_value parses the requested permission with enabled fallback and is used
		consistently by persistence and status wording */
		var allow_clone_value = metadata_bool(raw_allow_clone, true);

		/* Browser builds change the installed entry's settings index rather than native package INI
		files */
		if (uses_browser_storage())
		{
			/* Report failure if the browser index cannot persist the requested permission */
			if (!update_browser_index_allow_clone(entry.key, allow_clone_value))
			{
				set_status("Could not update character settings.", make_color_rgb(244, 84, 84));
				return false;
			}

			refresh();

			/* Read the setting back after refresh and reject a value differing from the requested
			permission */
			if (allow_clone_for_key(entry.key) != allow_clone_value)
			{
				set_status("Could not verify character settings.", make_color_rgb(244, 84, 84));
				return false;

			}

			/* Broadcast player metadata only if this shared artwork is also the equipped character */
			if (should_broadcast && selected_key == entry.key)
			{
				send_selected_to_server();
			}

			/* A pet using the same artwork needs its updated save permission too */
			if (should_broadcast && scr_get_pets().load_selected_key() == entry.key)
			{
				scr_get_pets().apply_selected_to_local_player();
				scr_get_client().send_player_pet(entry.key);
			}

			/* The status text reports the enabled or disabled cloning state after successfully sending
			updated metadata */
			set_status(allow_clone_value ? "Other players can save this character." : "Saving disabled for other players.", make_color_rgb(126, 245, 150));
			return true;
		}

		/* folder_key identifies the requested local package. package_path is its installed root and
		data_path is its configuration directory */
		var folder_key = custom_key_name_part(entry.key);
		var package_path = path_join(custom_folder_path(), folder_key);
		var data_path = path_join(package_path, "data");

		/* The configuration directory must exist before writing the native clone flag */
		if (!ensure_folder(data_path))
		{
			set_status("Could not update character settings.", make_color_rgb(244, 84, 84));
			return false;
		}

		try
		{
			ini_open(path_join(data_path, "character_config.ini"));

			/* Encode clone permission numerically as 1 or 0 for INI compatibility */
			ini_write_real("info", "allow_clone", allow_clone_value ? 1 : 0);

			/* allow_temp_cache_value preserves an existing parsed cache flag and falls back to false
			when that field is missing */
			var allow_temp_cache_value = variable_struct_exists(entry, "allow_multiplayer_temp_cache") && metadata_bool(entry.allow_multiplayer_temp_cache, true);

			/* Encode the retained cache permission as 1 or 0 */
			ini_write_real("info", "allow_multiplayer_temp_cache", allow_temp_cache_value ? 1 : 0);

			/* Persist character_hash when present, otherwise use the entry's hash field. Creator and
			copy fields use empty fallbacks for older records */
			ini_write_string("info", "character_hash", variable_struct_exists(entry, "character_hash") ? entry.character_hash : entry.hash);
			ini_write_string("info", "original_creator_name", variable_struct_exists(entry, "original_creator_name") ? entry.original_creator_name : "");
			ini_write_string("info", "original_creator_id", variable_struct_exists(entry, "original_creator_id") ? entry.original_creator_id : "");
			ini_write_string("info", "copied_from_hash", variable_struct_exists(entry, "copied_from_hash") ? entry.copied_from_hash : "");
			ini_close();
		}
		catch(e)
		{
			debug_error("Could not update custom character save permission: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			set_status("Could not update character settings.", make_color_rgb(244, 84, 84));
			return false;
		}

		refresh();

		/* Verify the native clone flag by reloading it before announcing success */
		if (allow_clone_for_key(entry.key) != allow_clone_value)
		{
			set_status("Could not verify character settings.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* An unequipped package edit must leave player selection and its saved setting untouched */
		if (should_broadcast && selected_key == entry.key)
		{
			send_selected_to_server();
		}

		/* The companion remains independently equipped while sharing this package's permission */
		if (should_broadcast && scr_get_pets().load_selected_key() == entry.key)
		{
			scr_get_pets().apply_selected_to_local_player();
			scr_get_client().send_player_pet(entry.key);
		}

		/* Status wording reflects whether cloning is now allowed or disabled */
		set_status(allow_clone_value ? "Other players can save this character." : "Saving disabled for other players.", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Invert the selected resolved clone state and persist the new permission
	/// @returns {Bool} Whether the permission update succeeded
	toggle_selected_allow_clone = function()
	{
		/* Invert the selected accessor's resolved clone state before persisting it */
		return set_selected_allow_clone(!selected_allow_clone());
	}

	/// @description Move by whole selectable-character steps, wrapping and skipping received cache entries, then persist and broadcast selection
	/// @param {Real} delta Navigation direction and magnitude. Zero retains selection
	/// @returns {String} Final selected key
	select_relative = function(delta)
	{
		load_selected_key();
		refresh();

		/* A zero navigation delta keeps the currently selected character */
		if (delta == 0)
		{
			return selected_key;
		}

		/* count is the discovered entry count used for wraparound and bounded search */
		var count = array_length(characters);

		/* An empty registry has no alternative selection to navigate to */
		if (count <= 0)
		{
			return selected_key;
		}

		/* selectable_count starts at zero to count entries eligible for local selection */
		var selectable_count = 0;

		/* The zero-based entry_index visits all discovered characters to count selectable
		installations */
		for (var entry_index = 0; entry_index < count; entry_index++)
		{
			/* Count only official or installed custom entries, excluding remote-cache entries from
			local character navigation */
			if (entry_is_selectable(characters[entry_index]))
			{
				selectable_count++;
			}
		}

		/* With no selectable entries, retain the current key rather than searching indefinitely */
		if (selectable_count <= 0)
		{
			return selected_key;
		}

		/* current_index locates the selected record in the refreshed character array */
		var current_index = find_index(selected_key);

		/* An unresolved current selection needs a starting position chosen for the navigation
		direction */
		if (current_index == noone)
		{
			/* Reverse movement starts at zero so its first step wraps to the last entry. Forward
			movement starts at -1 so its first step reaches the first entry */
			current_index = delta < 0 ? 0 : -1;
		}

		/* direction is -1 for reverse and 1 otherwise. step_count is at least one whole step, and
		next_index begins at the current position */
		var index_direction = delta < 0 ? -1 : 1;
		var step_count = max(1, abs(floor(real(delta))));
		var next_index = current_index;

		/* step_index counts requested navigation steps until the normalized step count is reached */
		for (var step_index = 0; step_index < step_count; step_index++)
		{
			/* guard bounds each search to at most count candidates, avoiding an endless loop while
			skipping remote entries */
			for (var guard = 0; guard < count; guard++)
			{
				next_index = (next_index + index_direction) mod count;

				/* A negative wrapped index is brought back inside the zero-based character array */
				if (next_index < 0)
				{
					next_index += count;
				}

				/* Stop this search step at the next selectable entry, continuing past remote-cache
				entries */
				if (entry_is_selectable(characters[next_index]))
				{
					break;
				}
			}
		}

		return set_selected_key(characters[next_index].key, true);
	}
	#endregion /* Selected Character Tools END */

	#region /* PNG Validation and Package Configuration */
	/// @description Read four unsigned bytes at the current cursor as one big-endian PNG integer
	/// @param {Id.Buffer} source_buffer Borrowed readable buffer with four bytes available
	/// @returns {Real} Unsigned 32-bit value, advancing the cursor by four bytes
	png_read_u32_be = function(source_buffer)
	{
		/* a, b, c and d read the next four unsigned bytes, from most to least significant, for a
		big-endian PNG integer */
		var a = buffer_read(source_buffer, buffer_u8);
		var b = buffer_read(source_buffer, buffer_u8);
		var c = buffer_read(source_buffer, buffer_u8);
		var d = buffer_read(source_buffer, buffer_u8);
		return a * 16777216 + b * 65536 + c * 256 + d;
	}

	/// @description Inspect a borrowed buffer's PNG signature and first IHDR dimensions without decoding its image pixels
	/// @param {Id.Buffer} source_buffer Borrowed PNG bytes. Cursor is reset for inspection and left after the dimensions
	/// @returns {Struct} ok, width, height and diagnostic message
	png_dimensions_from_buffer = function(source_buffer)
	{
		/* result starts with an invalid PNG flag, zero pixel dimensions and a signature-failure
		message until the header is recognized */
		var result =
		{
			ok: false,
			width: 0,
			height: 0,
			message: "Not a PNG file."
		};

		/* A live buffer with at least 24 bytes is needed for the PNG signature, first chunk header and
		two dimensions */
		if (is_undefined(source_buffer)
		|| !buffer_exists(source_buffer)
		|| buffer_get_size(source_buffer) < 24)
		{
			result.message = "File is too small to be a PNG.";
			return result;
		}

		buffer_seek(source_buffer, buffer_seek_start, 0);

		/* signature holds the exact eight PNG signature bytes in their on-disk order */
		var signature = [137, 80, 78, 71, 13, 10, 26, 10];

		/* sig_index visits each signature byte from zero until all eight have matched */
		for (var sig_index = 0; sig_index < array_length(signature); sig_index++)
		{
			/* Any mismatching signature byte returns the provisional Not a PNG result without
			interpreting its dimensions */
			if (buffer_read(source_buffer, buffer_u8) != signature[sig_index])
			{
				return result;
			}
		}

		/* chunk_length reads the first PNG chunk's big-endian payload length and chunk_type starts
		empty until its four type bytes are read */
		var chunk_length = png_read_u32_be(source_buffer);
		var chunk_type = "";

		/* type_index reads four ASCII bytes to assemble the first chunk's type name */
		for (var type_index = 0; type_index < 4; type_index++)
		{
			chunk_type += chr(buffer_read(source_buffer, buffer_u8));
		}

		/* Dimensions are read only from an IHDR chunk containing at least eight data bytes */
		if (chunk_type != "IHDR" || chunk_length < 8)
		{
			result.message = "PNG header is missing IHDR.";
			return result;
		}

		result.width = png_read_u32_be(source_buffer);
		result.height = png_read_u32_be(source_buffer);
		result.ok = true;
		result.message = "";
		return result;
	}

	/// @description Inspect a file's PNG header and required 48x76 dimensions, releasing its locally loaded buffer
	/// @param {String} file_path PNG source path
	/// @returns {Struct} ok, width, height and diagnostic message
	validate_png_path = function(file_path)
	{
		/* result begins as unsuccessful with zero pixel dimensions and no diagnostic until the file is
		inspected */
		var result =
		{
			ok: false,
			width: 0,
			height: 0,
			message: ""
		};

		/* source_buffer starts with no owned handle and is deleted after any completed load attempt */
		var source_buffer = noone;
		try
		{
			source_buffer = buffer_load(file_path);

			/* An undefined or missing loaded buffer reports an unreadable PNG instead of examining its
			header */
			if (is_undefined(source_buffer)
			|| !buffer_exists(source_buffer))
			{
				result.message = "Could not read PNG file.";
			}

			/* A live source buffer can provide header dimensions for this file validation */
			else
			{
				/* png_info retains the inspected header's success state, dimensions and failure
				message */
				var png_info = png_dimensions_from_buffer(source_buffer);
				result.width = png_info.width;
				result.height = png_info.height;

				/* Copy an invalid PNG header's diagnostic into the file result */
				if (!png_info.ok)
				{
					result.message = png_info.message;
				}

				/* Reject PNG dimensions differing from the required 48 by 76 pixel character sheet */
				else if (png_info.width != expected_sheet_w || png_info.height != expected_sheet_h)
				{
					result.message = "PNG must be exactly " + string(expected_sheet_w) + "x" + string(expected_sheet_h) + " pixels. This file is " + string(png_info.width) + "x" + string(png_info.height) + ".";
				}

				/* A recognized PNG with exact character-sheet dimensions clears the failure message
				and marks this inspection successful */
				else
				{
					result.ok = true;
					result.message = "";
				}

			}
		}
		catch(e)
		{
			result.message = "Could not inspect PNG: " + string(e.message);
		}

		/* Release the locally owned file buffer if it is still live after inspection or an exception */
		if (!is_undefined(source_buffer)
		&& buffer_exists(source_buffer))
		{
			buffer_delete(source_buffer);
		}

		return result;
	}

	/// @description Write native package identity, permissions, creator metadata, frame grid and sprite-origin configuration
	/// @param {String} folder_path Package root
	/// @param {String} folder_key Installed basename
	/// @param {String} label_text Display name
	/// @param {String} network_key_text Transfer identity. Defaults to empty and derives from folder/hash when omitted
	/// @param {String} hash_text Content identifier. Defaults to empty and attempts PNG inspection when omitted
	/// @param {String} source_text Installation source tag. Defaults to custom when omitted
	/// @param {Bool} temporary_value Whether this is a received cache package. Defaults to false when omitted
	/// @param {Bool} allow_clone_value Clone permission. Defaults to true when omitted
	/// @param {Bool} allow_temp_cache_value Temporary-cache permission. Defaults to true when omitted
	/// @param {String} original_creator_name_text Creator name. Defaults to empty when omitted
	/// @param {String} original_creator_id_text Creator ID. Defaults to empty when omitted
	/// @param {String} copied_from_hash_text Source-copy identifier. Defaults to empty when omitted
	/// @returns {Bool} Whether both configuration INIs were written
	write_package_ini = function(folder_path, folder_key, label_text, network_key_text = "", hash_text = "", source_text = "custom", temporary_value = false, allow_clone_value = true, allow_temp_cache_value = true, original_creator_name_text = "", original_creator_id_text = "", copied_from_hash_text = "")
	{
		/* data_path is the package's metadata directory, kept separate from sprites/player.png */
		var data_path = path_join(folder_path, "data");

		/* Configuration cannot be written unless the package's data directory can be prepared */
		if (!ensure_folder(data_path))
		{
			return false;
		}

		try
		{
			/* local_key is the sanitized installed custom identifier. saved_hash starts empty until a
			supplied hash or PNG inspection establishes it */
			var local_key = custom_prefix + safe_folder_key(folder_key);
			var saved_hash = "";

			/* With no supplied content hash, inspect the package's player.png to recover its
			identifier */
			if (string_trim(string(hash_text)) == "")
			{
				/* package_sprite_path points at the package image and package_hash starts as an
				unsuccessful lookup with no identifier */
				var package_sprite_path = path_join(path_join(folder_path, "sprites"), "player.png");
				var package_hash =
				{
					ok: false,
					hash: ""
				};

				/* Only an existing image file can supply the package's computed hash */
				if (file_exists(package_sprite_path))
				{
					package_hash = png_hash_for_path(package_sprite_path);
				}

				/* Use a successful image inspection's content hash, otherwise keep the saved hash
				empty */
				saved_hash = package_hash.ok ? package_hash.hash : "";
			}

			/* A supplied content hash is normalized directly rather than recomputed from the package
			image */
			else
			{
				saved_hash = safe_hash_key(hash_text);
			}

			/* A supplied network key is normalized and retained. Otherwise use the local key alone
			when no hash exists, or append the available hash to form a network identity */
			var saved_network_key = string_trim(string(network_key_text)) == ""
				? (saved_hash == "" ? local_key : custom_prefix + safe_folder_key(folder_key) + network_custom_separator + saved_hash)
				: sanitize_key(network_key_text);

			/* An empty saved hash falls back to the final network key's embedded identifier */
			if (saved_hash == "")
			{
				saved_hash = custom_key_hash_part(saved_network_key);
			}

			/* saved_allow_clone and saved_allow_temp_cache parse requested permissions, allowing each
			when its input cannot be interpreted */
			var saved_allow_clone = metadata_bool(allow_clone_value, true);
			var saved_allow_temp_cache = metadata_bool(allow_temp_cache_value, true);
			ini_open(path_join(data_path, "character_config.ini"));
			ini_write_string("info", "character_key", local_key);
			ini_write_string("info", "network_key", saved_network_key);
			ini_write_string("info", "character_hash", saved_hash);
			ini_write_string("info", "safe_name", safe_folder_key(folder_key));
			ini_write_string("info", "character_name", label_text);
			ini_write_string("info", "source", source_text);

			/* Store temporary, clone and temporary-cache flags as numeric 1 or 0 values alongside the
			package's identity and creator metadata */
			ini_write_real("info", "temporary", temporary_value ? 1 : 0);
			ini_write_real("info", "allow_clone", saved_allow_clone ? 1 : 0);
			ini_write_real("info", "allow_multiplayer_temp_cache", saved_allow_temp_cache ? 1 : 0);
			ini_write_string("info", "original_creator_name", metadata_text(original_creator_name_text, 64));
			ini_write_string("info", "original_creator_id", metadata_text(original_creator_id_text, 64));
			ini_write_string("info", "copied_from_hash", optional_hash_key(copied_from_hash_text));
			ini_write_string("sprite_sheet", "file", "player.png");
			ini_write_string("sprite_sheet", "frame_width", string(frame_w));
			ini_write_string("sprite_sheet", "frame_height", string(frame_h));
			ini_write_string("sprite_sheet", "columns", string(column_count));
			ini_write_string("sprite_sheet", "rows", string(row_count));
			ini_write_string("sprite_sheet", "source_scale", string(source_scale));
			ini_close();

			ini_open(path_join(data_path, "sprite_origin_point.ini"));
			ini_write_string("sprite origin points", "sprite_player_xorig", string(origin_x));
			ini_write_string("sprite origin points", "sprite_player_yorig", string(origin_y));
			ini_close();
			return true;
		}
		catch(e)
		{
			debug_error("Could not write custom character package config: " + string(e.message));
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}
	#endregion /* PNG Validation and Package Configuration END */

	#region /* Character Chunk Reassembly */
	/// @description Append owner ID, manifest, zero-based fragment index and base64 text to an already-started packet
	/// @param {Struct} net_ref Shared network writer positioned at the packet body
	/// @param {Real} owner_id Logical player slot owning the character
	/// @param {Struct} manifest Character metadata repeated with the fragment
	/// @param {Real} chunk_index Zero-based fragment index written as unsigned 16-bit
	/// @param {String} chunk_text Fragment's base64 text
	write_character_chunk_packet = function(net_ref, owner_id, manifest, chunk_index, chunk_text)
	{
		net_ref.write(TYPE_ID, owner_id);
		write_manifest(net_ref, manifest);
		net_ref.write(buffer_u16, chunk_index);
		net_ref.write(buffer_string, chunk_text);
	}

	/// @description Read a complete character-fragment body in write_character_chunk_packet field order
	/// @param {Struct} net_ref Primed shared reader positioned at the fragment body
	/// @param {Bool} remember_received Whether to retain its manifest. Defaults to true when omitted
	/// @returns {Struct} owner_id, manifest, chunk_index and chunk_text without an owned PNG buffer
	read_character_chunk_packet = function(net_ref, remember_received = true)
	{
		/* owner_id reads the player slot, manifest reads its following metadata, chunk_index is
		unsigned 16-bit zero-based fragment position, and chunk_text is the fragment's base64 string */
		var owner_id = net_ref.read(TYPE_ID);
		var manifest = read_manifest(net_ref, remember_received);
		var chunk_index = net_ref.read(buffer_u16);
		var chunk_text = string(net_ref.read(buffer_string));

		/* The returned packet groups the owner, manifest, fragment index and fragment text for
		reassembly without owning a PNG buffer */
		return
		{
			owner_id: owner_id,
			manifest: manifest,
			chunk_index: chunk_index,
			chunk_text: chunk_text
		};
	}

	/// @description Record a normalized unavailable-character identity once
	/// @param {String} raw_key Failed remote network key
	mark_remote_failure = function(raw_key)
	{
		/* key_text normalizes the character identity recorded as unavailable */
		var key_text = sanitize_key(raw_key);

		/* failure_index visits all zero-based failed identities to avoid storing duplicates */
		for (var failure_index = 0; failure_index < array_length(remote_failures); failure_index++)
		{
			/* An already recorded failure needs no second entry or state change */
			if (remote_failures[failure_index] == key_text)
			{
				return;
			}
		}

		remote_failures[array_length(remote_failures)] = key_text;
	}

	/// @description Remove all recorded failures for a normalized remote character identity
	/// @param {String} raw_key Successfully recovered remote network key
	clear_remote_failure = function(raw_key)
	{
		/* key_text is the normalized identity to remove from unavailable-character state */
		var key_text = sanitize_key(raw_key);

		/* failure_index walks backward through the failure array so deleting matches cannot skip
		shifted entries */
		for (var failure_index = array_length(remote_failures) - 1; failure_index >= 0; failure_index--)
		{
			/* Delete each recorded matching identity, allowing a later successful transfer to remove
			stale unavailable status */
			if (remote_failures[failure_index] == key_text)
			{
				array_delete(remote_failures, failure_index, 1);
			}
		}
	}

	/// @description Locate an incomplete transfer by both logical player owner and normalized character identity
	/// @param {Real} owner_id Logical player slot
	/// @param {String} raw_key Custom network identity
	/// @returns {Real} Zero-based pending assembly index, or noone
	pending_character_index = function(owner_id, raw_key)
	{
		/* key_text normalizes the requested transfer identity before matching pending assemblies */
		var key_text = sanitize_key(raw_key);

		/* pending_index visits each zero-based pending transfer until the owner/key pair matches */
		for (var pending_index = 0; pending_index < array_length(pending_character_receives); pending_index++)
		{
			/* pending is the current assembly being tested for both player owner and character
			identity */
			var pending = pending_character_receives[pending_index];

			/* Only an assembly with the same owner slot and normalized network key belongs to this
			incoming transfer */
			if (pending.owner_id == owner_id && pending.network_key == key_text)
			{
				return pending_index;
			}
		}

		return noone;
	}

	/// @description Decode a complete transfer and check its declared byte size, 48x76 PNG header, and protocol content identifier
	/// @param {Struct} manifest Custom character manifest accompanying the transfer
	/// @param {String} base64_text Reassembled PNG data
	/// @returns {Struct} Validation result. When ok is true, buffer is caller-owned and must be deleted
	validate_received_character_base64 = function(manifest, base64_text)
	{
		/* result starts rejected, retaining its manifest and encoded text, with no owned decoded
		buffer and a provisional invalid-PNG diagnostic */
		var result =
		{
			ok: false,
			manifest: manifest,
			base64: string(base64_text),
			buffer: noone,
			message: "Invalid custom character PNG."
		};

		/* Received validation requires the manifest's required shape and a custom character flag */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom)
		{
			result.message = "Missing custom character manifest.";
			return result;
		}

		/* The declared PNG byte count must be positive and at most 262144 before any base64 allocation
		is accepted */
		if (manifest.byte_size <= 0 || manifest.byte_size > character_max_bytes)
		{
			result.message = "Character PNG must be 256 KB or smaller.";
			return result;
		}

		/* decoded_buffer starts unowned. A successful decode is deleted on failure or transferred
		through result.buffer on success */
		var decoded_buffer = noone;
		try
		{
			decoded_buffer = buffer_base64_decode(base64_text);

			/* An undefined or missing decoded buffer reports a decode failure without attempting byte
			or header reads */
			if (is_undefined(decoded_buffer)
			|| !buffer_exists(decoded_buffer))
			{
				result.message = "Could not decode character PNG.";
				return result;
			}

			/* byte_size is the decoded PNG's actual buffer size in bytes */
			var byte_size = buffer_get_size(decoded_buffer);

			/* Reject content whose actual byte count differs from the manifest, preventing metadata
			from describing another payload */
			if (byte_size != manifest.byte_size)
			{
				result.message = "Character PNG size mismatch.";
			}

			/* Matching byte size permits inspecting the PNG header and required character-sheet
			dimensions */
			else
			{
				/* png_info reports the decoded header's recognized type and pixel dimensions */
				var png_info = png_dimensions_from_buffer(decoded_buffer);

				/* A malformed PNG header supplies its inspection diagnostic */
				if (!png_info.ok)
				{
					result.message = png_info.message;
				}

				/* Reject a valid PNG header whose dimensions are not the required 48 by 76 pixels */
				else if (png_info.width != expected_sheet_w || png_info.height != expected_sheet_h)
				{
					result.message = "PNG must be exactly " + string(expected_sheet_w) + "x" + string(expected_sheet_h) + " pixels.";
				}

				/* A correctly sized sheet proceeds to the protocol content-identifier check */
				else
				{
					/* computed_hash identifies the decoded bytes with the registry's deterministic
					12-character checksum */
					var computed_hash = buffer_hash12(decoded_buffer, byte_size);

					/* A different computed hash means these bytes do not match the declared character
					identity */
					if (computed_hash != manifest.hash)
					{
						result.message = "Character PNG hash mismatch.";
					}

					/* A matching identifier transfers decoded_buffer ownership to the successful
					result and rebuilds its normalized manifest */
					else
					{
						result.ok = true;
						result.message = "";
						result.buffer = decoded_buffer;
						result.manifest = make_manifest_struct(
							custom_prefix + manifest.safe_name + network_custom_separator + computed_hash,
							manifest.display_label,
							manifest.safe_name,
							computed_hash,
							true,
							byte_size,
							manifest.chunk_count,
							string(base64_text),

							/* The validated manifest preserves received permission fields or enables
							missing legacy ones, and keeps provenance fields with empty fallbacks
							when absent */
							variable_struct_exists(manifest, "allow_clone") ? manifest.allow_clone : true,
							variable_struct_exists(manifest, "allow_multiplayer_temp_cache") ? manifest.allow_multiplayer_temp_cache : true,
							variable_struct_exists(manifest, "original_creator_name") ? manifest.original_creator_name : "",
							variable_struct_exists(manifest, "original_creator_id") ? manifest.original_creator_id : "",
							variable_struct_exists(manifest, "copied_from_hash") ? manifest.copied_from_hash : ""
						);
						return result;
					}
				}
			}
		}
		catch(e)
		{
			result.message = "Could not decode character PNG: " + string(e.message);
		}

		/* Release any still-live decoded buffer on unsuccessful validation. Successful returns leave
		it owned by result.buffer */
		if (!is_undefined(decoded_buffer)
		&& buffer_exists(decoded_buffer))
		{
			buffer_delete(decoded_buffer);
		}

		return result;
	}

	/* The supplied PNG buffer remains borrowed. This writer saves its contents and metadata without
	deleting it */
	/// @description Save borrowed received PNG bytes and manifest metadata to a native temporary or permanent package
	/// @param {Struct} manifest Validated custom metadata
	/// @param {Id.Buffer} decoded_buffer Borrowed live PNG buffer. This writer never deletes it
	/// @param {Bool} temporary_value Whether to use the hash-named temporary cache instead of a unique installed package
	/// @returns {Bool} Whether the PNG and metadata were saved
	write_received_character_package = function(manifest, decoded_buffer, temporary_value)
	{
		/* Reject missing custom metadata or a dead buffer before creating any package folders */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| is_undefined(decoded_buffer)
		|| !buffer_exists(decoded_buffer))
		{
			return false;
		}

		/* Package caching and permanent saving have separate creator permissions. Session-memory
		preview remains available even when neither disk operation is permitted */
		if ((temporary_value && variable_struct_exists(manifest, "allow_multiplayer_temp_cache")
			&& !metadata_bool(manifest.allow_multiplayer_temp_cache, true))
		|| (!temporary_value && !manifest_allows_clone(manifest)))
		{
			return false;
		}

		/* Temporary downloads use a hash-named cache folder. Permanent saves get a collision-free
		folder under installed custom characters */
		var folder_path = temporary_value
			? temp_character_folder_for_hash(manifest.hash)
			: path_join(custom_folder_path(), unique_custom_folder_key(manifest.safe_name + "_" + string_copy(manifest.hash, 1, 8)));

		/* sprite_folder is the package's sprites directory, separate from its data metadata directory */
		var sprite_folder = path_join(folder_path, "sprites");

		/* Temporary packages require the cache hierarchy before their individual folders can be
		created */
		if (temporary_value)
		{
			/* Stop when the parent cache folders cannot be created, leaving buffer cleanup to the
			caller */
			if (!ensure_temp_character_cache())
			{
				return false;
			}
		}

		/* A permanent installation requires the custom-character root. Report failure when that root
		cannot be prepared */
		else if (!ensure_custom_folder())
		{
			return false;
		}

		/* Both the package root and sprites folder must exist before writing the PNG */
		if (!ensure_folder(folder_path) || !ensure_folder(sprite_folder))
		{
			return false;
		}

		/* sprite_path is the fixed player.png destination within this package */
		var sprite_path = path_join(sprite_folder, "player.png");
		try
		{
			buffer_save(decoded_buffer, sprite_path);
		}
		catch(e)
		{
			debug_error("Could not write received character PNG: " + string(e.message));
			return false;
		}

		/* The saved file must be visible to the filesystem before configuration is written */
		if (!file_exists(sprite_path))
		{
			return false;
		}

		/* folder_key records the package's final leaf name for its local character identifier */
		var folder_key = path_leaf(folder_path);

		/* Persist the received identity, display name and permissions. Temporary packages are tagged
		remote_temp, permanent ones custom. Missing permission fields allow cloning and temporary
		caching, while absent creator and copy fields remain empty */
		var package_saved = write_package_ini(
			folder_path,
			folder_key,
			manifest.display_label,
			manifest.network_key,
			manifest.hash,
			temporary_value ? "remote_temp" : "custom",
			temporary_value,
			variable_struct_exists(manifest, "allow_clone") ? manifest.allow_clone : true,
			variable_struct_exists(manifest, "allow_multiplayer_temp_cache") ? manifest.allow_multiplayer_temp_cache : true,
			variable_struct_exists(manifest, "original_creator_name") ? manifest.original_creator_name : "",
			variable_struct_exists(manifest, "original_creator_id") ? manifest.original_creator_id : "",
			variable_struct_exists(manifest, "copied_from_hash") ? manifest.copied_from_hash : ""
		);
		if (package_saved && !temporary_value)
		{
			last_saved_key = custom_prefix + folder_key;
		}
		return package_saved;
	}

	/// @description Reassemble chunks by owner and network key, verify the complete PNG, and optionally cache the remote package
	/// @param {Real} owner_id Player slot whose character is being transferred
	/// @param {Struct} manifest Custom manifest repeated with each chunk
	/// @param {Real} chunk_index Zero-based chunk index
	/// @param {String} chunk_text Base64 fragment. Senders split at character_chunk_size characters
	/// @param {Bool} write_temp_package Whether a completed transfer should enter the platform remote-character cache
	/// @returns {Struct} ok, complete, manifest, base64, and message. Accepted partial chunks have complete set to false
	accept_character_chunk = function(owner_id, manifest, chunk_index, chunk_text, write_temp_package)
	{
		/* result starts rejected and incomplete, retains the submitted manifest, and leaves assembled
		base64 and diagnostic message empty */
		var result =
		{
			ok: false,
			complete: false,
			manifest: manifest,
			base64: "",
			message: ""
		};

		/* Reject non-custom manifests, PNG sizes outside 1 to 262144 bytes, counts outside 1 to 64,
		invalid zero-based indices, or fragments longer than the 12000-character limit plus 1024
		tolerance */
		if (!manifest_is_valid_shape(manifest)
		|| !manifest.custom
		|| manifest.byte_size <= 0
		|| manifest.byte_size > character_max_bytes
		|| manifest.chunk_count <= 0
		|| manifest.chunk_count > character_max_chunks
		|| chunk_index < 0
		|| chunk_index >= manifest.chunk_count
		|| string_length(chunk_text) > character_chunk_size + 1024)
		{
			result.message = "Bad custom character chunk metadata.";
			mark_remote_failure(manifest.network_key);
			return result;
		}

		remember_manifest(manifest);

		/* pending_index locates this owner's transfer for this network key. pending will reference
		either that existing assembly or the new one below */
		var pending_index = pending_character_index(owner_id, manifest.network_key);
		var pending;

		/* The first chunk for an owner/key pair creates a fresh assembly so unrelated players cannot
		share receipt counters */
		if (pending_index == noone)
		{
			/* The assembly retains owner_id and network_key for lookup, the first manifest for
			consistency checks, one empty base64 string per chunk, and a received count starting at
			zero */
			pending =
			{
				owner_id: owner_id,
				network_key: manifest.network_key,
				manifest: manifest,
				chunks: array_create(manifest.chunk_count, ""),
				received: 0
			};
			pending_index = array_length(pending_character_receives);
			pending_character_receives[pending_index] = pending;
		}

		/* Later chunks reuse the assembly and must agree with its original content identity and
		expected sizes */
		else
		{
			pending = pending_character_receives[pending_index];

			/* Discard the entire pending transfer when hash, byte count or chunk count changes, since
			mixing those fragments cannot form one valid PNG */
			if (pending.manifest.hash != manifest.hash
			|| pending.manifest.byte_size != manifest.byte_size
			|| pending.manifest.chunk_count != manifest.chunk_count)
			{
				array_delete(pending_character_receives, pending_index, 1);
				result.message = "Custom character chunk metadata mismatch.";
				mark_remote_failure(manifest.network_key);
				return result;
			}
		}

		/* An empty chunk slot accepts its fragment and increments the receipt count. Already populated
		slots keep their first fragment so duplicate packets cannot advance completion */
		if (pending.chunks[chunk_index] == "")
		{
			pending.chunks[chunk_index] = chunk_text;
			pending.received++;
		}

		pending_character_receives[pending_index] = pending;
		result.ok = true;

		/* Keep the accepted assembly pending until its receipt counter reaches the declared chunk
		count */
		if (pending.received < pending.manifest.chunk_count)
		{
			return result;
		}

		/* base64_text accumulates fragments in their original order, starting with an empty payload */
		var base64_text = "";

		/* The zero-based i counter visits all declared chunks to reconstruct the encoded PNG from
		first fragment to last */
		for (var i = 0; i < pending.manifest.chunk_count; i++)
		{
			/* An empty fragment still leaves the transfer incomplete, even if the receipt counter has
			reached its target */
			if (pending.chunks[i] == "")
			{
				return result;
			}
			base64_text += pending.chunks[i];
		}

		array_delete(pending_character_receives, pending_index, 1);

		/* validation checks the completed payload and owns a decoded PNG buffer only when successful */
		var validation = validate_received_character_base64(pending.manifest, base64_text);

		/* A failed size, dimensions or content-identifier check rejects the assembled transfer and
		records its character as unavailable */
		if (!validation.ok)
		{
			result.ok = false;
			result.message = validation.message;
			mark_remote_failure(pending.manifest.network_key);
			return result;
		}

		/* Preview callers publish completed bytes to session memory or permitted temporary packages.
		Disabling retained packages still allows the artwork to appear during this session */
		if (write_temp_package)
		{
			var allow_disk_cache = !variable_struct_exists(validation.manifest, "allow_multiplayer_temp_cache")
				|| metadata_bool(validation.manifest.allow_multiplayer_temp_cache, true);

			/* Browser downloads and native downloads with disk caching disabled share the in-memory
			base64 store. Neither path creates a permanent installation */
			if (uses_browser_storage() || !allow_disk_cache)
			{
				/* If the browser cache refuses the validated character, reject completion and release
				the decoded buffer */
				if (!remember_browser_remote_character(validation.manifest, base64_text))
				{
					result.ok = false;
					result.message = "Could not cache temporary character.";
					mark_remote_failure(validation.manifest.network_key);

					/* Delete the validation-owned buffer when the failed browser cache path leaves it
					live */
					if (buffer_exists(validation.buffer))
					{
						buffer_delete(validation.buffer);
					}
					return result;
				}
				refresh();
			}

			/* Native builds write the received PNG and metadata to the temporary cache. A write
			failure rejects completion and releases its decoded buffer */
			else if (!write_received_character_package(validation.manifest, validation.buffer, true))
			{
				result.ok = false;
				result.message = "Could not write temporary character package.";
				mark_remote_failure(validation.manifest.network_key);

				/* Free the decoded PNG before returning the native-cache failure */
				if (buffer_exists(validation.buffer))
				{
					buffer_delete(validation.buffer);
				}
				return result;
			}
			refresh();
		}

		/* Successful validation no longer needs its decoded buffer once any requested cache write has
		finished */
		if (buffer_exists(validation.buffer))
		{
			buffer_delete(validation.buffer);
		}

		clear_remote_failure(validation.manifest.network_key);
		remember_manifest(validation.manifest);
		result.ok = true;
		result.complete = true;
		result.manifest = validation.manifest;
		result.base64 = base64_text;
		result.message = "";
		return result;
	}

	/// @description Read the current fragment packet, accept it into reassembly and log any diagnostic rejection
	/// @returns {Struct} Acceptance result including completion state and validated metadata
	receive_character_chunk = function()
	{
		/* net_ref borrows the shared packet reader, chunk contains its decoded
		owner/manifest/index/text, and result records acceptance or completion of that fragment */
		var net_ref = scr_get_network();
		var chunk = read_character_chunk_packet(net_ref);
		var result = accept_character_chunk(chunk.owner_id, chunk.manifest, chunk.chunk_index, chunk.chunk_text, true);

		/* Log a rejected fragment only when acceptance supplied a diagnostic message */
		if (!result.ok && result.message != "")
		{
			debug_error("Custom character chunk rejected: " + result.message);
		}
		return result;
	}
	#endregion /* Character Chunk Reassembly END */

	#region /* Character Import and Installation */
	/// @description Choose an unused sanitized installation directory name by adding numeric suffixes from 2
	/// @param {String} base_key Requested installation basename
	/// @returns {String} Directory basename not currently present beneath custom_folder_path
	unique_custom_folder_key = function(base_key)
	{
		/* root is the permanent custom-character directory. folder_key is the sanitized requested
		basename, candidate initially uses it unchanged, and suffix starts at 2 for subsequent
		collisions */
		var root = custom_folder_path();
		var folder_key = safe_folder_key(base_key);
		var candidate = folder_key;
		var suffix = 2;

		/* While a candidate directory already exists, try the next numeric suffix to preserve
		installed packages */
		while (directory_exists(path_join(root, candidate)))
		{
			candidate = folder_key + "_" + string(suffix);
			suffix++;
		}

		return candidate;
	}

	/// @description Validate a browser PNG, verify any supplied expected hash, persist its file/index and optionally select it
	/// @param {String} base64_text Complete 48x76 PNG data
	/// @param {String} label_text Display label, with Custom Character fallback when blank
	/// @param {String} base_folder_name Requested local basename, using label_text when blank
	/// @param {String} network_key_text Network identity to preserve or repair. Defaults to empty when omitted
	/// @param {String} hash_text Expected content hash to verify. Defaults to empty when omitted
	/// @param {Bool} select_after Whether to select and announce the new entry. Defaults to false when omitted
	/// @param {Bool} allow_clone_value Clone permission. Defaults to true when omitted
	/// @param {Bool} allow_temp_cache_value Temporary-cache permission. Defaults to true when omitted
	/// @param {String} original_creator_name_text Creator name. Defaults to empty when omitted
	/// @param {String} original_creator_id_text Creator ID. Defaults to empty when omitted
	/// @param {String} copied_from_hash_text Copy-source identifier. Defaults to empty when omitted
	/// @param {String} source_text Index ownership/source tag. Defaults to browser_custom when omitted
	/// @returns {Bool} Whether the browser image and its index metadata were saved
	install_browser_custom_base64 = function(base64_text, label_text, base_folder_name, network_key_text = "", hash_text = "", select_after = false, allow_clone_value = true, allow_temp_cache_value = true, original_creator_name_text = "", original_creator_id_text = "", copied_from_hash_text = "", source_text = "browser_custom")
	{
		/* validation checks the base64 PNG and transfers ownership of its decoded buffer to this
		installer on success */
		var validation = validate_raw_character_base64(base64_text);

		/* Reject invalid PNG data before allocating browser storage or changing the selected character */
		if (!validation.ok)
		{
			set_status(validation.message, make_color_rgb(244, 84, 84));
			return false;
		}

		/* clean_label is the trimmed display name shown in the character selector */
		var clean_label = string_trim(string(label_text));

		/* An empty display name uses Custom Character so the installed entry remains identifiable */
		if (clean_label == "")
		{
			clean_label = "Custom Character";
		}

		/* final_hash is computed from the validated PNG bytes rather than the requested name */
		var final_hash = validation.hash;

		/* A supplied expected hash must match the PNG's computed identifier. Reject mismatched content
		before storing it */
		if (string_trim(string(hash_text)) != ""
		&& safe_hash_key(hash_text) != final_hash)
		{
			/* Release the validation-owned buffer on the hash mismatch path */
			if (buffer_exists(validation.buffer))
			{
				buffer_delete(validation.buffer);
			}
			set_status("Custom character PNG hash mismatch.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* base_name uses the explicit folder name when provided, otherwise the display label.
		local_key gets a unique browser installation name, and safe_name extracts that local
		basename */
		var base_name = string_trim(string(base_folder_name)) == "" ? clean_label : string(base_folder_name);
		var local_key = browser_unique_local_key(base_name, final_hash);
		var safe_name = custom_key_name_part(local_key);

		/* final_network_key uses a supplied network identity when present, otherwise combines the
		unique local name and computed content hash */
		var final_network_key = string_trim(string(network_key_text)) == ""
			? custom_prefix + safe_name + network_custom_separator + final_hash
			: sanitize_key(network_key_text);

		/* Repair a non-network or mismatched-hash key to carry the actual validated PNG identifier */
		if (!is_network_custom_key(final_network_key)
		|| custom_key_hash_part(final_network_key) != final_hash)
		{
			final_network_key = custom_prefix + custom_key_name_part(final_network_key) + network_custom_separator + final_hash;
		}

		/* manifest_safe_name comes from the final network key. chunk_count measures 12000-character
		base64 fragments, with at least one fragment for a valid PNG */
		var manifest_safe_name = custom_key_name_part(final_network_key);
		var chunk_count = max(1, ceil(string_length(validation.base64) / character_chunk_size));

		/* manifest combines validated content sizes with the requested permissions and creator/copy
		provenance for persistence and later transfer */
		var manifest = make_manifest_struct(
			final_network_key,
			clean_label,
			manifest_safe_name,
			final_hash,
			true,
			validation.byte_size,
			chunk_count,
			validation.base64,
			allow_clone_value,
			allow_temp_cache_value,
			original_creator_name_text,
			original_creator_id_text,
			copied_from_hash_text
		);

		/* storage_file is the browser PNG filename derived from the local safe name and content hash */
		var storage_file = browser_storage_file_for_character(safe_name, final_hash);
		try
		{
			buffer_save(validation.buffer, storage_file);
		}
		catch(e)
		{
			/* Release the decoded PNG when its browser save throws before returning a failure status */
			if (buffer_exists(validation.buffer))
			{
				buffer_delete(validation.buffer);
			}
			set_status("Could not save browser custom character: " + string(e.message), make_color_rgb(244, 84, 84));
			return false;
		}

		/* The browser file write has finished, so release the installer-owned decoded buffer */
		if (buffer_exists(validation.buffer))
		{
			buffer_delete(validation.buffer);
		}

		/* A missing saved file prevents adding an index entry that would point at unavailable PNG data */
		if (!file_exists(storage_file))
		{
			set_status("Browser storage did not save the custom character.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* A PNG without a saved browser index cannot be rediscovered as an installed character, so
		report the metadata write failure */
		if (!write_browser_index_entry(local_key, manifest, storage_file, source_text))
		{
			set_status("Could not write browser custom character config.", make_color_rgb(244, 84, 84));
			return false;
		}

		refresh();

		/* Requested selection applies and broadcasts the newly installed key, then reports an import */
		last_saved_key = local_key;
		if (select_after)
		{
			set_selected_key(local_key, true);
			set_status("Imported " + clean_label + ".", make_color_rgb(126, 245, 150));
		}

		/* Saving without selection leaves the current character active and reports the new stored copy */
		else
		{
			set_status("Saved " + clean_label + ".", make_color_rgb(126, 245, 150));
		}

		return true;
	}

	/// @description Validate and save an editor PNG, replacing only installed custom packages and retaining their permissions and provenance
	/// @param {String} base64_text Complete 48x76 PNG encoded as base64
	/// @param {String} label_text Display name for the saved package
	/// @param {String} existing_key_text Installed custom key to overwrite. Other keys create a new package. Defaults to empty when omitted
	/// @param {Bool} select_after Whether to select and announce the saved package. Defaults to true when omitted
	/// @returns {Bool} Whether the package and metadata were saved
	save_editor_character_base64 = function(base64_text, label_text, existing_key_text = "", select_after = true)
	{
		/* validation checks the editor's exported PNG and owns its decoded buffer after success */
		var validation = validate_raw_character_base64(base64_text);

		/* Reject invalid editor exports before locating or overwriting an installed package */
		if (!validation.ok)
		{
			set_status(validation.message, make_color_rgb(244, 84, 84));
			return false;
		}

		/* clean_label is the trimmed saved display name */
		var clean_label = string_trim(string(label_text));

		/* Use Custom Character when the editor supplies a blank display name */
		if (clean_label == "")
		{
			clean_label = "Custom Character";
		}

		/* An empty existing_key_text requests a new package. Otherwise existing_entry_index resolves
		the overwrite candidate and existing_entry retains its struct only when found */
		var existing_entry_index = string_trim(string(existing_key_text)) == "" ? noone : find_index(existing_key_text);
		var existing_entry = existing_entry_index == noone ? noone : characters[existing_entry_index];

		/* can_overwrite permits only installed custom entries. Official assets and remote cache
		entries must be preserved by saving a new package instead */
		var can_overwrite = is_struct(existing_entry)
			&& !existing_entry.official
			&& !(variable_struct_exists(existing_entry, "remote") && existing_entry.remote);

		/* saved_local_key stays empty until a complete save succeeds, saved_ok starts false, and
		final_hash identifies the validated exported PNG */
		var saved_local_key = "";
		var saved_ok = false;
		var final_hash = validation.hash;

		/* Overwrites retain existing clone and temporary-cache permissions when available. New
		packages and older entries lacking those fields default to allowing both */
		var final_allow_clone = can_overwrite && variable_struct_exists(existing_entry, "allow_clone") ? metadata_bool(existing_entry.allow_clone, true) : true;
		var final_allow_temp_cache = can_overwrite && variable_struct_exists(existing_entry, "allow_multiplayer_temp_cache") ? metadata_bool(existing_entry.allow_multiplayer_temp_cache, true) : true;

		/* Retain an overwritten package's creator identity when present, otherwise use the local
		creator. copied_from_hash preserves existing copy provenance or stays empty */
		var final_original_creator_name = can_overwrite && variable_struct_exists(existing_entry, "original_creator_name") ? existing_entry.original_creator_name : local_creator_name();
		var final_original_creator_id = can_overwrite && variable_struct_exists(existing_entry, "original_creator_id") ? existing_entry.original_creator_id : local_creator_id();
		var final_copied_from_hash = can_overwrite && variable_struct_exists(existing_entry, "copied_from_hash") ? existing_entry.copied_from_hash : "";

		/* final_source distinguishes an edit of an installed custom character from a newly created
		editor character */
		var final_source = can_overwrite ? "character_maker_edit" : "character_maker";

		/* Browser storage writes one PNG file and a settings index entry rather than a native package
		directory */
		if (uses_browser_storage())
		{
			/* local_key, safe_name and storage_file start empty until the overwrite or new-install
			branch chooses their browser destinations */
			var local_key = "";
			var safe_name = "";
			var storage_file = "";

			/* An overwrite retains the installed local key and existing browser filename so the saved
			entry keeps its identity */
			if (can_overwrite)
			{
				local_key = existing_entry.key;
				safe_name = custom_key_name_part(local_key);

				/* Reuse an existing browser_storage_file field when present, otherwise defer filename
				construction to the fallback below */
				storage_file = variable_struct_exists(existing_entry, "browser_storage_file") ? string(existing_entry.browser_storage_file) : "";

				/* An older entry without a storage filename gets a new name based on its local key and
				updated content hash */
				if (string_trim(storage_file) == "")
				{
					storage_file = browser_storage_file_for_character(safe_name, final_hash);
				}
			}

			/* A new browser character gets a collision-free local key and a filename for its validated
			PNG */
			else
			{
				local_key = browser_unique_local_key(clean_label, final_hash);
				safe_name = custom_key_name_part(local_key);
				storage_file = browser_storage_file_for_character(safe_name, final_hash);
			}

			/* final_network_key combines the retained or new local basename with updated content.
			chunk_count counts its base64 transfer fragments */
			var final_network_key = custom_prefix + safe_name + network_custom_separator + final_hash;
			var chunk_count = max(1, ceil(string_length(validation.base64) / character_chunk_size));

			/* The saved manifest carries the exported bytes, final permissions and preserved
			creator/copy provenance */
			var manifest = make_manifest_struct(
				final_network_key,
				clean_label,
				safe_name,
				final_hash,
				true,
				validation.byte_size,
				chunk_count,
				validation.base64,
				final_allow_clone,
				final_allow_temp_cache,
				final_original_creator_name,
				final_original_creator_id,
				final_copied_from_hash
			);

			/* browser_write_ok starts false and becomes true only when the saved browser file is
			visible */
			var browser_write_ok = false;
			try
			{
				buffer_save(validation.buffer, storage_file);

				/* Record whether browser storage exposes the PNG after buffer_save, before attempting
				its index metadata */
				browser_write_ok = file_exists(storage_file);
			}
			catch(e)
			{
				set_status("Could not save browser custom character: " + string(e.message), make_color_rgb(244, 84, 84));
			}

			/* Treat the browser save as complete only when both the PNG file and its settings index
			entry were saved */
			if (browser_write_ok
			&& write_browser_index_entry(local_key, manifest, storage_file, final_source))
			{
				saved_local_key = local_key;
				saved_ok = true;
			}

			/* A failed PNG write reports the missing stored image rather than a metadata problem */
			else if (!browser_write_ok)
			{
				set_status("Browser storage did not save the custom character.", make_color_rgb(244, 84, 84));
			}

			/* When the PNG exists but the index write fails, report the configuration failure */
			else
			{
				set_status("Could not write browser custom character config.", make_color_rgb(244, 84, 84));
			}
		}

		/* Native builds save a sprites/player.png file and package INI files under the
		custom-character directory */
		else
		{
			/* Report a root-folder failure without attempting to create the package beneath it */
			if (!ensure_custom_folder())
			{
				set_status("Could not create custom character folder.", make_color_rgb(244, 84, 84));
			}

			/* Once the installed-character root exists, resolve the package destination and write its
			image and metadata */
			else
			{
				/* folder_key and package_path remain empty until the overwrite or new-package branch
				determines the native destination */
				var folder_key = "";
				var package_path = "";

				/* Overwriting derives the existing package path from its sprite file so the local
				installation key stays stable */
				if (can_overwrite)
				{
					/* sprite_folder_path removes player.png from the current source path, allowing its
					parent package directory to be reused */
					var sprite_folder_path = path_parent(existing_entry.source_file);
					package_path = path_parent(sprite_folder_path);
					folder_key = path_leaf(package_path);
				}

				/* A newly created character uses an unused package folder to avoid replacing unrelated
				installations */
				else
				{
					folder_key = unique_custom_folder_key(clean_label);
					package_path = path_join(custom_folder_path(), folder_key);
				}

				/* sprite_folder is the package's image directory */
				var sprite_folder = path_join(package_path, "sprites");

				/* Report failure if either package directory cannot be prepared before saving
				player.png */
				if (!ensure_folder(package_path) || !ensure_folder(sprite_folder))
				{
					set_status("Could not create custom character package.", make_color_rgb(244, 84, 84));
				}

				/* Prepared package folders allow the PNG write and subsequent metadata write */
				else
				{
					/* destination_path is the package's player.png file. desktop_write_ok starts false
					until that file becomes visible after saving */
					var destination_path = path_join(sprite_folder, "player.png");
					var desktop_write_ok = false;
					try
					{
						buffer_save(validation.buffer, destination_path);

						/* Record that the destination image exists before attempting to publish its
						configuration */
						desktop_write_ok = file_exists(destination_path);
					}
					catch(e)
					{
						set_status("Could not write custom character PNG: " + string(e.message), make_color_rgb(244, 84, 84));
					}

					/* The native save succeeds only when both its PNG and package configuration are
					present */
					if (desktop_write_ok
					&& write_package_ini(package_path, folder_key, clean_label, custom_prefix + safe_folder_key(folder_key) + network_custom_separator + final_hash, final_hash, final_source, false, final_allow_clone, final_allow_temp_cache, final_original_creator_name, final_original_creator_id, final_copied_from_hash))
					{
						saved_local_key = custom_prefix + safe_folder_key(folder_key);
						saved_ok = true;
					}

					/* If the PNG never appeared, report the image write failure */
					else if (!desktop_write_ok)
					{
						set_status("Custom character PNG was not written.", make_color_rgb(244, 84, 84));
					}

					/* If the PNG exists but package metadata cannot be written, report the
					configuration failure */
					else
					{
						set_status("Could not write custom character package config.", make_color_rgb(244, 84, 84));
					}
				}
			}
		}

		/* Release the validated decoded PNG after either platform's save attempt */
		if (buffer_exists(validation.buffer))
		{
			buffer_delete(validation.buffer);
		}

		/* Stop before cache invalidation or selection when no complete package was saved */
		if (!saved_ok)
		{
			return false;
		}

		/* An overwrite invalidates cached sheets for the previous image so later draws load the newly
		saved PNG */
		if (can_overwrite)
		{
			drop_cached_sheet(existing_entry.key);

			/* Also drop the previous network-key cache entry when one was recorded, since it refers to
			the replaced content */
			if (variable_struct_exists(existing_entry, "network_key"))
			{
				drop_cached_sheet(existing_entry.network_key);
			}
		}

		refresh();

		/* Selecting the saved package applies and broadcasts it only when the caller requests that
		behavior */
		last_saved_key = saved_local_key;
		if (select_after)
		{
			set_selected_key(saved_local_key, true);
		}

		/* Editing pet artwork shared with the equipped character also changes its content hash */
		else if (can_overwrite && selected_key == saved_local_key)
		{
			apply_selected_to_local_player();
			send_selected_to_server();
		}

		/* An overwritten shared package may also be equipped as a companion */
		if (can_overwrite && scr_get_pets().load_selected_key() == saved_local_key)
		{
			/* Local rendering also needs the new content hash when there is no multiplayer connection */
			scr_get_pets().apply_selected_to_local_player();
			scr_get_client().send_player_pet(saved_local_key);
		}

		/* The status wording distinguishes an overwritten character from a newly saved character */
		set_status((can_overwrite ? "Updated " : "Saved ") + clean_label + ".", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Start an asynchronous browser PNG picker or acknowledge one already open, updating selector status
	/// @returns {Bool} Whether a picker is active or reported already open
	/// @param {String} target Equipped role receiving the new artwork, player or pet
	start_browser_import = function(target = "player")
	{
		/* An already pending browser import keeps the picker request active and reminds the user to
		choose a file */
		if (browser_import_pending)
		{
			set_status("Choose a PNG in the browser file picker.", make_color_rgb(255, 220, 95));
			return true;
		}

		/* start_result records whether the browser extension opened the picker, found one already
		open, or could not open it */
		var start_result = html5_custom_character_import_start();

		/* A positive picker result marks this registry as awaiting asynchronous file selection */
		if (start_result > 0)
		{
			browser_import_pending = true;
			browser_import_target = target == "pet" ? "pet" : "player";
			set_status("Choose a 48x76 PNG sheet.", make_color_rgb(255, 220, 95));
			return true;
		}

		/* A negative extension result reports an already open picker and is treated as an active
		request */
		if (start_result < 0)
		{
			set_status("Browser file picker is already open.", make_color_rgb(255, 220, 95));
			return true;
		}

		set_status("Browser file picker is unavailable.", make_color_rgb(244, 84, 84));
		return false;
	}

	/// @description Poll a pending browser picker, clear completed extension state and install a successfully chosen PNG
	/// @returns {Bool} Whether this poll completed a successful installation
	update_browser_import = function()
	{
		/* Poll import completion only in browser builds while this registry has a pending request */
		if (!uses_browser_storage()
		|| !browser_import_pending)
		{
			return false;
		}

		/* import_status is the extension's asynchronous picker state used to distinguish waiting,
		success and cancellation */
		var import_status = html5_custom_character_import_status();

		/* Status 1 keeps waiting for browser file selection without completing an import */
		if (import_status == 1)
		{
			return false;
		}

		browser_import_pending = false;

		/* Status 2 provides a chosen file and its PNG data for validation and permanent installation */
		if (import_status == 2)
		{
			/* file_name and base64_text capture the chosen filename and PNG bytes before clearing the
			extension's import result */
			var file_name = html5_custom_character_import_name();
			var base64_text = html5_custom_character_import_base64();
			html5_custom_character_import_clear();

			/* label_text turns the file's leaf name without its extension into a readable character
			label */
			var label_text = display_from_slug(strip_extension(path_leaf(file_name)));
			/* Capture the role chosen when this asynchronous request started. A Pet Card import must
			never replace the player's character when the browser finishes later */
			var import_for_pet = browser_import_target == "pet";
			var imported = install_browser_custom_base64(base64_text, label_text, label_text, "", "", !import_for_pet, true, true, local_creator_name(), local_creator_id(), "", "browser_import");
			if (imported && import_for_pet)
			{
				return scr_get_pets().equip_local(last_saved_key);
			}
			return imported;
		}

		/* error_text retains any extension diagnostic before its import state is cleared */
		var error_text = html5_custom_character_import_error();
		html5_custom_character_import_clear();

		/* Status -2 means the user cancelled selection, so report cancellation without installing a
		character */
		if (import_status == -2)
		{
			set_status("Import cancelled.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* Use the extension's error when it is nonempty, otherwise show a general browser import
		failure */
		set_status(string_trim(error_text) == "" ? "Could not import browser PNG." : error_text, make_color_rgb(244, 84, 84));
		return false;
	}

	/// @description Start browser import or synchronously pick, validate, copy and select a native PNG package
	/// @returns {Bool} Whether a browser picker is active, or a native package was installed
	/// @param {String} target Equipped role receiving the new artwork, player or pet
	import_png_from_dialog = function(target = "player")
	{
		/* Browser builds start an asynchronous file picker rather than using the native desktop picker */
		if (uses_browser_storage())
		{
			return start_browser_import(target);
		}

		/* linux_cache_path is the readable save-area copy used by the desktop picker. picked_file
		records its outcome and source_path is the path this importer can read */
		var linux_cache_path = path_join(string(game_save_id), "linux_character_import.png");
		var picked_file = scr_desktop_pick_png(linux_cache_path);
		var source_path = picked_file.readable_path;

		/* A blank readable path means no PNG can be imported, whether selection was cancelled or the
		picker failed */
		if (string_trim(source_path) == "")
		{
			/* import_error uses the picker's optional diagnostic or an empty fallback, allowing
			cancelled selection to have a clear status */
			var import_error = variable_struct_exists(picked_file, "error_message") ? string_trim(string(picked_file.error_message)) : "";

			/* A supplied picker error is shown directly. With no diagnostic, show Import cancelled */
			set_status(import_error == "" ? "Import cancelled." : import_error, make_color_rgb(244, 84, 84));
			return false;
		}

		/* validation inspects the selected PNG header and required 48 by 76 pixel dimensions */
		var validation = validate_png_path(source_path);

		/* Reject a wrong-sized or unreadable PNG before creating an installed package */
		if (!validation.ok)
		{
			set_status(validation.message, make_color_rgb(244, 84, 84));
			return false;
		}

		/* The installed-character root must exist before copying the selected PNG */
		if (!ensure_custom_folder())
		{
			set_status("Could not create custom character folder.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* label_text is derived from the original selected filename. folder_key chooses an unused
		installed name, package_path is its root, and sprite_path is its sprites directory */
		var label_text = display_from_slug(strip_extension(path_leaf(picked_file.selected_path)));
		var folder_key = unique_custom_folder_key(label_text);
		var package_path = path_join(custom_folder_path(), folder_key);
		var sprite_path = path_join(package_path, "sprites");

		/* Both the package directory and its image directory must exist before the file copy */
		if (!ensure_folder(package_path) || !ensure_folder(sprite_path))
		{
			set_status("Could not create custom character package.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* destination_path is the installed sprites/player.png file */
		var destination_path = path_join(sprite_path, "player.png");
		try
		{
			file_copy(source_path, destination_path);
		}
		catch(e)
		{
			set_status("Could not copy custom character PNG: " + string(e.message), make_color_rgb(244, 84, 84));
			return false;
		}

		/* A missing copied PNG prevents publishing a character whose image cannot be loaded */
		if (!file_exists(destination_path))
		{
			set_status("Custom character PNG was not copied.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* Write default clone/cache permissions and local creator identity only after the imported
		image exists. Failure leaves the import unselected */
		if (!write_package_ini(package_path, folder_key, label_text, "", "", "custom", false, true, true, local_creator_name(), local_creator_id(), ""))
		{
			set_status("Could not write custom character package config.", make_color_rgb(244, 84, 84));
			return false;
		}

		refresh();
		last_saved_key = custom_prefix + folder_key;

		/* Pet imports equip only the companion. Existing calls keep their player-character behavior */
		if (target == "pet")
		{
			if (!scr_get_pets().equip_local(last_saved_key))
			{
				return false;
			}
		}
		else
		{
			set_selected_key(last_saved_key, true);
		}
		set_status("Imported " + label_text + ".", make_color_rgb(126, 245, 150));
		return true;
	}

	/// @description Copy a source PNG into a new custom package, using encoded browser installation when native folders are unavailable
	/// @param {String} source_path Readable PNG source path
	/// @param {String} label_text Installed display label
	/// @param {String} base_folder_name Requested unique local basename
	/// @param {String} network_key_text Preserved transfer identity. Defaults to empty when omitted
	/// @param {String} hash_text Expected browser hash or native inspection fallback. Defaults to empty when omitted
	/// @param {Bool} select_after Whether to select and announce the copy. Defaults to false when omitted
	/// @param {Bool} allow_clone_value Clone permission. Defaults to true when omitted
	/// @param {Bool} allow_temp_cache_value Temporary-cache permission. Defaults to true when omitted
	/// @param {String} original_creator_name_text Creator name. Defaults to empty when omitted
	/// @param {String} original_creator_id_text Creator ID. Defaults to empty when omitted
	/// @param {String} copied_from_hash_text Copy-source identifier. Defaults to empty when omitted
	/// @param {String} source_text Installation source tag. Defaults to custom when omitted
	/// @returns {Bool} Whether the new image and configuration were saved
	install_sprite_as_custom = function(source_path, label_text, base_folder_name, network_key_text = "", hash_text = "", select_after = false, allow_clone_value = true, allow_temp_cache_value = true, original_creator_name_text = "", original_creator_id_text = "", copied_from_hash_text = "", source_text = "custom")
	{
		/* Browser builds load and encode the source PNG before handing installation to the browser
		index writer */
		if (uses_browser_storage())
		{
			/* browser_source begins as a failed read with no encoded data, content hash or byte count,
			and keeps a user-facing diagnostic until validation succeeds */
			var browser_source =
			{
				ok: false,
				base64: "",
				hash: "",
				byte_size: 0,
				message: "Could not read character PNG."
			};

			/* source_buffer starts with no owned resource. A successful load is released before
			leaving the browser branch */
			var source_buffer = noone;
			try
			{
				source_buffer = buffer_load(source_path);

				/* A live loaded buffer can be checked and encoded as a browser installation source */
				if (buffer_exists(source_buffer))
				{
					/* byte_size is the loaded PNG's actual byte count for the transfer-size limit and
					content identifier */
					var byte_size = buffer_get_size(source_buffer);
					browser_source.byte_size = byte_size;

					/* Reject empty images and PNG files larger than the 262144-byte transfer limit */
					if (byte_size <= 0 || byte_size > character_max_bytes)
					{
						browser_source.message = "Character PNG must be 256 KB or smaller.";
					}

					/* An image within the size limit proceeds to PNG-header and dimensions checks */
					else
					{
						/* png_info extracts the PNG header dimensions without taking ownership of
						source_buffer */
						var png_info = png_dimensions_from_buffer(source_buffer);

						/* A failed header inspection supplies the browser source's diagnostic */
						if (!png_info.ok)
						{
							browser_source.message = png_info.message;
						}

						/* Only the required 48 by 76 pixel sheet may become a browser character */
						else if (png_info.width != expected_sheet_w || png_info.height != expected_sheet_h)
						{
							browser_source.message = "PNG must be exactly " + string(expected_sheet_w) + "x" + string(expected_sheet_h) + " pixels.";
						}

						/* A valid sheet can be hashed and encoded, clearing the provisional error
						state */
						else
						{
							browser_source.hash = buffer_hash12(source_buffer, byte_size);
							browser_source.base64 = buffer_base64_encode(source_buffer, 0, byte_size);
							browser_source.ok = true;
							browser_source.message = "";
						}
					}
				}
			}
			catch(e)
			{
				browser_source.message = "Could not read character PNG: " + string(e.message);
			}

			/* Release the locally owned loaded PNG buffer before returning or invoking the browser
			installer */
			if (buffer_exists(source_buffer))
			{
				buffer_delete(source_buffer);
			}

			/* Report the browser-source read or validation failure without creating an installation */
			if (!browser_source.ok)
			{
				set_status(browser_source.message, make_color_rgb(244, 84, 84));
				return false;
			}

			/* Use the computed source hash when no expected hash was supplied, otherwise let the
			browser installer verify the caller's expected identifier */
			return install_browser_custom_base64(browser_source.base64, label_text, base_folder_name, network_key_text, hash_text == "" ? browser_source.hash : hash_text, select_after, allow_clone_value, allow_temp_cache_value, original_creator_name_text, original_creator_id_text, copied_from_hash_text, source_text);
		}

		/* validation inspects the source PNG's required sheet dimensions for a native copy */
		var validation = validate_png_path(source_path);

		/* A failed header or dimensions check prevents native package creation */
		if (!validation.ok)
		{
			set_status(validation.message, make_color_rgb(244, 84, 84));
			return false;
		}

		/* The permanent custom-character root must exist before copying the source PNG */
		if (!ensure_custom_folder())
		{
			set_status("Could not create custom character folder.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* folder_key chooses an unused sanitized installation name. package_path is its root and
		sprite_folder is the image directory beneath it */
		var folder_key = unique_custom_folder_key(base_folder_name);
		var package_path = path_join(custom_folder_path(), folder_key);
		var sprite_folder = path_join(package_path, "sprites");

		/* Prepare both package and sprite folders before copying the source image */
		if (!ensure_folder(package_path) || !ensure_folder(sprite_folder))
		{
			set_status("Could not create custom character package.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* destination_path is the permanent package's sprites/player.png file */
		var destination_path = path_join(sprite_folder, "player.png");
		try
		{
			file_copy(source_path, destination_path);
		}
		catch(e)
		{
			set_status("Could not copy custom character PNG: " + string(e.message), make_color_rgb(244, 84, 84));
			return false;
		}

		/* Do not write metadata for a copied PNG that does not exist at its destination */
		if (!file_exists(destination_path))
		{
			set_status("Custom character PNG was not copied.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* hash_info tries to identify the copied file. final_hash uses its verified content identifier
		on success, otherwise the normalized caller-supplied hash */
		var hash_info = png_hash_for_path(destination_path);
		var final_hash = hash_info.ok ? hash_info.hash : safe_hash_key(hash_text);

		/* final_network_key preserves a supplied network identity, or derives one from the new local
		folder and final hash */
		var final_network_key = string_trim(string(network_key_text)) == ""
			? custom_prefix + safe_folder_key(folder_key) + network_custom_separator + final_hash
			: sanitize_key(network_key_text);

		/* A complete native installation requires its permission/provenance configuration after the
		PNG copy */
		if (!write_package_ini(package_path, folder_key, label_text, final_network_key, final_hash, source_text, false, allow_clone_value, allow_temp_cache_value, original_creator_name_text, original_creator_id_text, copied_from_hash_text))
		{
			set_status("Could not write custom character package config.", make_color_rgb(244, 84, 84));
			return false;
		}

		refresh();

		/* Requested selection applies and broadcasts the installed copy, then reports the copied
		character */
		last_saved_key = custom_prefix + folder_key;
		if (select_after)
		{
			set_selected_key(custom_prefix + folder_key, true);
			set_status("Copied " + string(label_text) + ".", make_color_rgb(126, 245, 150));
		}

		/* An installation without selection reports its saved copy while keeping the current character
		active */
		else
		{
			set_status("Saved " + string(label_text) + ".", make_color_rgb(126, 245, 150));
		}

		return true;
	}

	/// @description Install and select a custom copy of the current image, recording source attribution and enabling clone/cache permissions
	/// @returns {Bool} Whether the copy was installed
	copy_selected_to_custom = function()
	{
		load_selected_key();
		return copy_key_to_custom(selected_key, true);
	}

	/// @description Copy shared artwork into a new custom package, optionally selecting it as the player
	/// @param {String} raw_key Source artwork key
	/// @param {Bool} select_after Whether to equip the copy as the player character
	/// @returns {Bool} Whether the copy was installed. last_saved_key identifies the result
	copy_key_to_custom = function(raw_key, select_after = true)
	{
		refresh();

		/* Resolve the requested source independently of the equipped player character */
		var entry_index = find_index(raw_key);

		/* Missing requested artwork cannot supply the source PNG for a copy */
		if (entry_index == noone)
		{
			set_status("No character selected to copy.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* entry is the requested registry record and source_path identifies its image for native copies
		or browser file loading */
		var entry = characters[entry_index];
		var source_path = entry.source_file;

		/* Native copying requires an existing source file. Browser entries may provide base64 instead
		of a filesystem path */
		if (!uses_browser_storage() && !file_exists(source_path))
		{
			set_status("Selected character PNG is missing.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* label_text marks the new character as a copy in the selector */
		var label_text = entry.display_label + " Copy";

		/* source_hash prefers character_hash, then the entry's older hash field, or empty when neither
		exists. copied_from_hash records it for custom sources and stays empty for official sources */
		var source_hash = variable_struct_exists(entry, "character_hash") ? entry.character_hash : (variable_struct_exists(entry, "hash") ? entry.hash : "");
		var copied_from_hash = entry.official ? "" : source_hash;

		/* original_creator_name and original_creator_id begin empty until the source type supplies
		attribution */
		var original_creator_name = "";
		var original_creator_id = "";

		/* Copies of custom characters preserve their recorded creator identity where available */
		if (!entry.official)
		{
			/* Missing custom creator fields initially remain empty so the local creator fallback below
			can fill them */
			original_creator_name = variable_struct_exists(entry, "original_creator_name") ? entry.original_creator_name : "";
			original_creator_id = variable_struct_exists(entry, "original_creator_id") ? entry.original_creator_id : "";

			/* An empty custom creator name uses the local creator name for the copy's attribution */
			if (string_trim(original_creator_name) == "")
			{
				original_creator_name = local_creator_name();
			}

			/* An empty custom creator ID uses the local creator ID */
			if (string_trim(original_creator_id) == "")
			{
				original_creator_id = local_creator_id();
			}
		}

		/* Copies of bundled characters record Official as the creator name and use the official key as
		its identity */
		else
		{
			original_creator_name = "Official";
			original_creator_id = entry.key;
		}

		/* A browser entry with cached base64 can be copied directly without loading its source path */
		if (uses_browser_storage()
		&& variable_struct_exists(entry, "base64")
		&& string_trim(string(entry.base64)) != "")
		{
			/* The browser copy records official_copy or custom_copy according to its source. Selection
			follows the caller's destination and both permissions start enabled */
			return install_browser_custom_base64(entry.base64, label_text, label_text, "", "", select_after, true, true, original_creator_name, original_creator_id, copied_from_hash, entry.official ? "official_copy" : "custom_copy");
		}

		/* Sources requiring file access use the sprite installer and retain the same source-type tag,
		attribution and enabled permissions */
		return install_sprite_as_custom(source_path, label_text, label_text, "", "", select_after, true, true, original_creator_name, original_creator_id, copied_from_hash, entry.official ? "official_copy" : "custom_copy");
	}

	/// @description Install a downloaded remote character when its clone flag permits saving and keep the received creator metadata
	/// @param {String} raw_key Network custom character key including its content hash
	/// @param {Struct|Real} owner_manifest Optional owner-specific permission and creator metadata
	/// @returns {Bool} Whether the character was saved or already installed
	save_remote_character = function(raw_key, owner_manifest = undefined)
	{
		/* key_text is the normalized requested remote network identity */
		var key_text = sanitize_key(raw_key);

		/* Saving a remote character requires a custom key with a content hash */
		if (!is_network_custom_key(key_text))
		{
			set_status("Only custom characters can be saved.", make_color_rgb(244, 84, 84));
			return false;
		}

		/* An already installed matching character counts as success and does not create a duplicate
		package */
		if (has_installed_network_key(key_text))
		{
			set_status("Character is already saved.", make_color_rgb(126, 245, 150));
			return true;
		}

		/* entry_index locates the downloaded cache entry corresponding to the requested remote key */
		var entry_index = find_index(key_text);

		/* A missing entry or an entry outside the remote cache cannot be installed through this save
		action */
		if (entry_index == noone || !entry_is_remote(key_text))
		{
			set_status("Custom character is not downloaded yet.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* Image bytes remain shared by key. Owner-specific permission and creator fields retain the
		card's actual source even when another player uses the same PNG */
		var entry = characters[entry_index];
		var manifest = remote_save_manifest(key_text, owner_manifest);

		/* The manifest's clone permission must allow permanent saving before the downloaded image is
		copied */
		if (!manifest_allows_clone(manifest))
		{
			set_status("Saving disabled by creator.", make_color_rgb(255, 220, 95));
			return false;
		}

		/* base_name combines the remote safe name and first eight hash characters to distinguish
		installed copies */
		var base_name = manifest.safe_name + "_" + string_copy(manifest.hash, 1, 8);

		/* original_creator_name and original_creator_id use received provenance fields or empty
		fallbacks when absent */
		var original_creator_name = variable_struct_exists(manifest, "original_creator_name") ? manifest.original_creator_name : "";
		var original_creator_id = variable_struct_exists(manifest, "original_creator_id") ? manifest.original_creator_id : "";

		/* If the received creator name is empty, use the downloaded character's display label as its
		saved attribution */
		if (string_trim(original_creator_name) == "")
		{
			original_creator_name = manifest.display_label;
		}

		/* Browser saves install the in-memory remote PNG through browser storage */
		if (uses_browser_storage())
		{
			/* A browser cache entry without base64 has no completed image available for permanent
			saving */
			if (!variable_struct_exists(entry, "base64")
			|| string_trim(string(entry.base64)) == "")
			{
				set_status("Custom character is not downloaded yet.", make_color_rgb(255, 220, 95));
				return false;
			}

			/* Install the received bytes under the remembered network identity and creator metadata.
			The saved copy enables cloning and temporary caching and records the received hash as
			its copy source */
			return install_browser_custom_base64(
				entry.base64,
				manifest.display_label,
				base_name,
				manifest.network_key,
				manifest.hash,
				false,
				true,
				true,
				original_creator_name,
				original_creator_id,
				manifest.hash,
				"remote_saved"
			);
		}

		/* Native session-memory previews have no source file to copy. Explicit Save writes their
		validated bytes to a permanent package only after the owner-specific clone check above */
		if (variable_struct_exists(entry, "base64") && string_trim(entry.base64) != "")
		{
			var saved_manifest = make_manifest_struct(manifest.network_key, manifest.display_label,
				manifest.safe_name, manifest.hash, true, manifest.byte_size, manifest.chunk_count,
				entry.base64, true, true, original_creator_name, original_creator_id, manifest.hash);
			var validation = validate_received_character_base64(saved_manifest, entry.base64);
			if (!validation.ok)
			{
				set_status(validation.message, make_color_rgb(244, 84, 84));
				return false;
			}
			var package_saved = write_received_character_package(validation.manifest, validation.buffer, false);
			if (buffer_exists(validation.buffer))
			{
				buffer_delete(validation.buffer);
			}
			if (!package_saved)
			{
				set_status("Could not save custom artwork package.", make_color_rgb(244, 84, 84));
				return false;
			}
			refresh();
			set_status("Saved " + manifest.display_label + ".", make_color_rgb(126, 245, 150));
			return true;
		}

		/* Native saves copy the downloaded package PNG with the same received identity and
		attribution, enabling both permissions and tagging the installation remote_saved */
		return install_sprite_as_custom(
			entry.source_file,
			manifest.display_label,
			base_name,
			manifest.network_key,
			manifest.hash,
			false,
			true,
			true,
			original_creator_name,
			original_creator_id,
			manifest.hash,
			"remote_saved"
		);
	}

	/// @description Ask the desktop folder opener to prepare/open permanent custom characters and show its outcome
	/// @returns {Bool} Whether the opener reported Opened
	open_custom_folder = function()
	{
		/* folder_path locates permanent custom characters. open_result records the desktop folder
		opener's outcome, and opened is true only when the opener reports Opened */
		var folder_path = custom_folder_path();
		var open_result = scr_open_folder(folder_path, "Custom Characters Folder");
		var opened = open_result == FolderOpenResult.Opened;

		/* A disabled folder opener means this platform cannot open a desktop character directory */
		if (open_result == FolderOpenResult.Disabled)
		{
			set_status("Characters folder is only available on desktop builds.", make_color_rgb(255, 220, 95));
		}

		/* A creation failure means the custom-character folder could not be prepared */
		else if (open_result == FolderOpenResult.FailedToCreate)
		{
			set_status("Could not create custom character folder.", make_color_rgb(244, 84, 84));
		}

		/* When automatic opening requires a manual step, show the path popup guidance */
		else if (open_result == FolderOpenResult.ManualOpenNeeded)
		{
			set_status("Characters folder is ready. Use the popup path to open it manually.", make_color_rgb(255, 220, 95));
		}

		/* Other opener outcomes use opened to choose success or failure wording and its corresponding
		status colour */
		else
		{
			set_status(opened ? "Opened characters folder." : "Could not open characters folder.", opened ? make_color_rgb(126, 245, 150) : make_color_rgb(244, 84, 84));
		}
		return opened;
	}
	#endregion /* Character Import and Installation END */

	#region /* Character Drawing and Bounds */
	/// @description Lazily load and draw one character frame at its origin in the current draw coordinate space
	/// @param {String} raw_key Character key resolved through the registry
	/// @param {Real} facing_direction Facing-direction row, clamped to the sheet
	/// @param {Bool} is_walking Whether to select the timed walk column
	/// @param {Real} draw_x Horizontal drawing origin
	/// @param {Real} draw_y Vertical drawing origin
	/// @param {Real} project_scale Scale applied after the source-to-project sprite scale
	/// @param {Real} colour Sprite tint color. Defaults to c_white when omitted
	/// @param {Real} alpha Sprite opacity. Defaults to 1 when omitted
	/// @returns {Bool} Whether a loaded frame was drawn. Pending browser loads return false
	draw_character = function(raw_key, facing_direction, is_walking, draw_x, draw_y, project_scale, colour = c_white, alpha = 1)
	{
		/* character_sheet borrows the registry-owned cached sheet for loading and drawing */
		var character_sheet = get_sheet(raw_key);

		/* A usable sheet must expose ensure_loaded and successfully start or finish its load before
		drawing can proceed */
		if (is_struct(character_sheet)
		&& variable_struct_exists(character_sheet, "ensure_loaded")
		&& character_sheet.ensure_loaded())
		{
			/* A pending asynchronous load is not ready to draw, even when ensure_loaded started it
			successfully */
			if (!variable_struct_exists(character_sheet, "is_loaded")
			|| !character_sheet.is_loaded())
			{
				return false;
			}

			/* Finish optional anti-bleed padding when that sheet supports it before calculating
			texture coordinates */
			if (variable_struct_exists(character_sheet, "finish_padding_if_ready"))
			{
				character_sheet.finish_padding_if_ready();
			}

			/* row clamps the facing direction to a valid zero-based sheet row. column clamps the timed
			walking column to this sheet's frame count */
			var row = clamp(floor(facing_direction), 0, character_sheet.row_count - 1);
			var column = clamp(player_character_walk_column(is_walking), 0, character_sheet.column_count - 1);

			/* draw_scale combines the requested project scale and source-to-project scale */
			var draw_scale = project_scale * character_sheet.scale_to_project_sprite;

			/* part_x and part_y locate the frame inside the padded texture cell, excluding its gutter
			in source pixels */
			var part_x = column * character_sheet.sheet_cell_w + character_sheet.sheet_gutter;
			var part_y = row * character_sheet.sheet_cell_h + character_sheet.sheet_gutter;

			draw_sprite_part_ext(
				character_sheet.sprite,
				0,
				part_x,
				part_y,
				character_sheet.frame_w,
				character_sheet.frame_h,
				draw_x - character_sheet.xorigin * draw_scale,
				draw_y - character_sheet.yorigin * draw_scale,
				draw_scale,
				draw_scale,
				colour,
				alpha
			);
			return true;
		}

		return false;
	}

	/// @description Convert a character drawing origin to its frame's top edge using cached metrics
	/// @param {String} raw_key Character identity
	/// @param {Real} draw_y Vertical drawing origin in current draw coordinates
	/// @param {Real} project_scale Scale after source-to-project conversion
	/// @returns {Real} Frame top edge in the same coordinate space
	top_y = function(raw_key, draw_y, project_scale)
	{
		/* character_sheet borrows cached frame metrics to convert the drawing origin to its top edge */
		var character_sheet = get_sheet(raw_key);
		return draw_y - character_sheet.yorigin * character_sheet.scale_to_project_sprite * project_scale;
	}

	/// @description Convert a character drawing origin to its frame's bottom edge using cached metrics
	/// @param {String} raw_key Character identity
	/// @param {Real} draw_y Vertical drawing origin in current draw coordinates
	/// @param {Real} project_scale Scale after source-to-project conversion
	/// @returns {Real} Frame bottom edge in the same coordinate space
	bottom_y = function(raw_key, draw_y, project_scale)
	{
		/* character_sheet supplies the frame height and origin needed to calculate its bottom edge */
		var character_sheet = get_sheet(raw_key);
		return draw_y + (character_sheet.frame_h - character_sheet.yorigin) * character_sheet.scale_to_project_sprite * project_scale;
	}

	/// @description Convert a character drawing origin to its frame's horizontal center using cached metrics
	/// @param {String} raw_key Character identity
	/// @param {Real} draw_x Horizontal drawing origin in current draw coordinates
	/// @param {Real} project_scale Scale after source-to-project conversion
	/// @returns {Real} Frame center in the same coordinate space
	center_x = function(raw_key, draw_x, project_scale)
	{
		/* character_sheet supplies frame width and horizontal origin for the visual center offset */
		var character_sheet = get_sheet(raw_key);
		return draw_x + (character_sheet.frame_w * 0.5 - character_sheet.xorigin) * character_sheet.scale_to_project_sprite * project_scale;
	}

	/// @description Calculate a character frame's drawn edges and center from its origin and cached metrics
	/// @param {String} raw_key Character identity
	/// @param {Real} draw_x Horizontal drawing origin
	/// @param {Real} draw_y Vertical drawing origin
	/// @param {Real} project_scale Scale after source-to-project conversion
	/// @returns {Struct} left, top, right, bottom, center_x and center_y in current draw coordinates
	bounds = function(raw_key, draw_x, draw_y, project_scale)
	{
		/* character_sheet borrows the frame metrics used by all bounds calculations */
		var character_sheet = get_sheet(raw_key);

		/* draw_scale combines source and requested scales. left_value and top_value are the resulting
		frame's edges in the current draw coordinates */
		var draw_scale = project_scale * character_sheet.scale_to_project_sprite;
		var left_value = draw_x - character_sheet.xorigin * draw_scale;
		var top_value = draw_y - character_sheet.yorigin * draw_scale;

		/* The returned bounds contain left/top/right/bottom edges and center_x/center_y in the
		caller's draw coordinate space */
		return
		{
			left: left_value,
			top: top_value,
			right: left_value + character_sheet.frame_w * draw_scale,
			bottom: top_value + character_sheet.frame_h * draw_scale,
			center_x: left_value + character_sheet.frame_w * draw_scale * 0.5,
			center_y: top_value + character_sheet.frame_h * draw_scale * 0.5
		};
	}

	/// @description Borrow the registry-owned lazy sprite-sheet record for frame, grid, origin and scaling metrics
	/// @param {String} raw_key Character identity
	/// @returns {Struct} Shared cached sheet. Callers must not delete its sprite
	metrics = function(raw_key)
	{
		return get_sheet(raw_key);
	}

	/// @description Draw one character frame positioned by visual horizontal center and bottom edge
	/// @param {String} raw_key Character identity
	/// @param {Real} facing_direction Zero-based facing row
	/// @param {Bool} is_walking Whether timed walk animation is active
	/// @param {Real} center_x Visual horizontal center in current draw coordinates
	/// @param {Real} bottom_y Visual bottom edge in current draw coordinates
	/// @param {Real} project_scale Scale after source-to-project conversion
	/// @param {Colour} colour Tint. Defaults to c_white when omitted
	/// @param {Real} alpha Opacity. Defaults to 1 when omitted
	/// @returns {Bool} Whether the loaded frame was drawn
	draw_character_at_bottom = function(raw_key, facing_direction, is_walking, center_x, bottom_y, project_scale, colour = c_white, alpha = 1)
	{
		/* character_sheet borrows cached frame metrics and draw_scale combines its native sprite scale
		with the requested project scale */
		var character_sheet = get_sheet(raw_key);
		var draw_scale = project_scale * character_sheet.scale_to_project_sprite;

		/* origin_draw_x converts a visual center to the sprite's horizontal origin. origin_draw_y
		converts the requested bottom edge to its vertical origin */
		var origin_draw_x = center_x + (character_sheet.xorigin - character_sheet.frame_w * 0.5) * draw_scale;
		var origin_draw_y = bottom_y - (character_sheet.frame_h - character_sheet.yorigin) * draw_scale;
		return draw_character(raw_key, facing_direction, is_walking, origin_draw_x, origin_draw_y, project_scale, colour, alpha);
	}

	/// @description Fit a character frame proportionally inside a rectangle and center it in both axes
	/// @param {String} raw_key Character identity
	/// @param {Real} facing_direction Zero-based facing row
	/// @param {Bool} is_walking Whether timed walk animation is active
	/// @param {Real} box_left Destination left edge
	/// @param {Real} box_top Destination top edge
	/// @param {Real} box_right Destination right edge
	/// @param {Real} box_bottom Destination bottom edge
	/// @param {Colour} colour Tint. Defaults to c_white when omitted
	/// @param {Real} alpha Opacity. Defaults to 1 when omitted
	/// @returns {Bool} Whether the fitted loaded frame was drawn
	draw_character_in_box = function(raw_key, facing_direction, is_walking, box_left, box_top, box_right, box_bottom, colour = c_white, alpha = 1)
	{
		/* character_sheet supplies cached dimensions for fitting one frame inside the requested
		rectangle */
		var character_sheet = get_sheet(raw_key);

		/* box_w and box_h measure the destination rectangle in draw coordinates and stay at least one
		unit to keep scale division valid */
		var box_w = max(1, box_right - box_left);
		var box_h = max(1, box_bottom - box_top);

		/* project_scale is the smaller width or height fit, preserving aspect ratio while keeping the
		frame inside the box */
		var project_scale = min(
			box_w / max(1, character_sheet.frame_w * character_sheet.scale_to_project_sprite),
			box_h / max(1, character_sheet.frame_h * character_sheet.scale_to_project_sprite)
		);

		/* visual_h is the fitted frame height. box_center_x centers it horizontally and box_bottom_y
		places its bottom so the frame is centered vertically */
		var visual_h = character_sheet.frame_h * character_sheet.scale_to_project_sprite * project_scale;
		var box_center_x = (box_left + box_right) * 0.5;
		var box_bottom_y = box_top + (box_h + visual_h) * 0.5;
		return draw_character_at_bottom(raw_key, facing_direction, is_walking, box_center_x, box_bottom_y, project_scale, colour, alpha);
	}
	#endregion /* Character Drawing and Bounds END */

}

/// @description Return the shared character registry
/// @returns {Struct} Lazily constructed character registry
function scr_get_player_characters()
{
	/* registry is constructed once on the first accessor call and keeps the shared discovery,
	selection, transfer and sprite-cache state for later calls */
	static registry = new scr_player_characters();
	return registry;
}
