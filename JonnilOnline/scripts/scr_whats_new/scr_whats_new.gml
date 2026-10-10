/// @function scr_read_included_text_file(path)
/// @description Read Included Files text with newline separators
/// @param {String} path Included file path
/// @returns {String} File text, or an empty string for an unreadable or empty file
function scr_read_included_text_file(path)
{
	/* result accumulates the file's text from empty, and file starts at -1 until this operation owns a read handle */
	var result = "";
	var file = -1;

	try
	{
		file = file_text_open_read(path);

		/* An unreadable Included File returns empty text before attempting reads */
		if (file < 0)
		{
			return "";
		}

		/* first_line prevents a leading LF before the first retained line */
		var first_line = true;

		/* Read lines until EOF, advancing past each source line ending after collecting its text */
		while (!file_text_eof(file))
		{
			/* Insert LF between lines after the first, preserving separation without adding a leading newline */
			if (!first_line)
			{
				result += "\n";
			}

			result += file_text_read_string(file);
			file_text_readln(file);
			first_line = false;
		}

		file_text_close(file);
		file = -1;
	}

	/* A read exception returns empty text and releases any still-owned handle */
	catch(e)
	{
		/* Close only a handle still open at failure, ignoring a secondary close exception */
		if (file >= 0)
		{
			try { file_text_close(file); } catch(close_error) {}
		}
		return "";
	}

	return result;
}

/// @function scr_load_whats_new()
/// @description Set global.whats_new and global.whats_new_source from the platform-specific Included File
/// @returns {Bool} Whether a nonempty file was loaded. Switch falls back to default only when its file is absent
function scr_load_whats_new()
{
	/* default_path is the shared Included File, preferred_path initially selects it,
	and source_path stays empty until an existing candidate is chosen */
	var default_path = "whats_new/default.txt";
	var preferred_path = default_path;
	var source_path = "";

	/* Switch prefers its dedicated notes file */
	if (os_type == os_switch)
	{
		preferred_path = "whats_new/switch.txt";
	}

	/* Use an existing preferred file, even if its contents later prove empty or unreadable */
	if (file_exists(preferred_path))
	{
		source_path = preferred_path;
	}

	/* When a platform-specific file is absent, try an existing shared default
	A default already tried as preferred needs no duplicate fallback */
	else if (preferred_path != default_path
	&& file_exists(default_path))
	{
		source_path = default_path;
	}

	/* Reset visible notes to empty and record the selected source before reading, clearing a previous load's text */
	global.whats_new = "";
	global.whats_new_source = source_path;

	/* Without an existing candidate, leave the cleared notes and report failure */
	if (source_path == "")
	{
		return false;
	}

	global.whats_new = scr_read_included_text_file(source_path);

	/* Only nonempty loaded content reports success, without retrying after an empty preferred file */
	return global.whats_new != "";
}

/// @function scr_whats_new_content_digest(text)
/// @description Hash the notes so changing their contents makes them unread again
/// @param {String} text Current update notes
/// @returns {String} UTF-8 SHA-1 digest used as a read marker
function scr_whats_new_content_digest(text)
{
	return sha1_string_utf8(string(text));
}

/// @description Compare the saved read marker with the current notes
/// @param {String} settings_file Client INI path. The caller must not have another INI open
/// @param {String} text Current update notes
/// @returns {Bool} Whether the stored digest matches. Missing or unreadable settings return false
function scr_whats_new_was_read(settings_file, text)
{
	/* Start without a read marker, then load a saved digest only from an existing settings file */
	var saved_digest = "";
	try
	{
		/* Missing settings leave the empty marker without opening an INI */
		if (file_exists(settings_file))
		{
			ini_open(settings_file);
			saved_digest = ini_read_string("whats_new", "last_read_digest", "");
			ini_close();
		}
	}

	/* Close any INI left open by failure when possible, and treat unreadable settings as unread notes */
	catch(e)
	{
		try { ini_close(); } catch(close_error) {}
		return false;
	}

	/* Notes count as read only when their current content hash equals the saved marker */
	return saved_digest == scr_whats_new_content_digest(text);
}

/// @description Save the current notes digest in the client INI
/// @param {String} settings_file Client INI path. The caller must not have another INI open
/// @param {String} text Notes to mark as read
/// @returns {Bool} Whether the write completed without an exception
function scr_whats_new_mark_read(settings_file, text)
{
	try
	{
		ini_open(settings_file);
		ini_write_string("whats_new", "last_read_digest", scr_whats_new_content_digest(text));
		ini_close();
		return true;
	}

	/* A failed INI write attempts cleanup and reports false instead of claiming the marker was saved */
	catch(e)
	{
		try { ini_close(); } catch(close_error) {}
		return false;
	}
}

/// @description Pad a nonnegative integer to a minimum text width
/// @param {Real} value Value to floor and clamp at zero
/// @param {Real} digits Minimum character width
/// @returns {String} Zero-padded numeric text
function scr_whats_new_pad_number(value, digits)
{
	/* Clamp the value to nonnegative integer text before adding zero padding */
	var result = string(max(0, floor(real(value))));

	/* Prepend zeros until digits is reached, retaining longer values without truncation */
	while (string_length(result) < digits)
	{
		result = "0" + result;
	}
	return result;
}

/// @description Format GM_build_date for the update-notes footer
/// @returns {String} Build date and time as YYYY-MM-DD HH:MM
function scr_whats_new_build_datetime()
{
	return string(date_get_year(GM_build_date)) + "-"
		+ scr_whats_new_pad_number(date_get_month(GM_build_date), 2) + "-"
		+ scr_whats_new_pad_number(date_get_day(GM_build_date), 2) + " "
		+ scr_whats_new_pad_number(date_get_hour(GM_build_date), 2) + ":"
		+ scr_whats_new_pad_number(date_get_minute(GM_build_date), 2);
}
