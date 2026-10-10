/// @description Reset paste consumption once at the start of the controller Step event
function scr_text_input_begin_step()
{
	/* A desktop paste may reach several fields in the same Step.
	Reset this shared consumption flag here so only the focused field takes it */
	global.text_input_paste_handled = false;

	/* On browser targets, reset the JavaScript paste bridge as well.
	Desktop runners use the GML consumption flag and need no browser call */
	if (os_browser != browser_not_a_browser)
	{
		html5_text_input_begin_step();
	}
}

/// @description Check the desktop paste shortcuts on their press frame
/// @returns {Bool} Whether Ctrl+V or Shift+Insert was pressed
function scr_text_input_paste_pressed()
{
	/* Accept Ctrl+V or Shift+Insert only on the shortcut key's press frame.
	Holding the modifier alone does not repeatedly request clipboard text */
	return (keyboard_check(vk_control) && keyboard_check_pressed(ord("V")))
		|| (keyboard_check(vk_shift) && keyboard_check_pressed(vk_insert));
}

/// @description Limit pasted text and replace line breaks and tabs before removing control characters
/// @param {String} raw_text Clipboard text
/// @param {Real} max_length Character limit applied before cleaning
/// @returns {String} Text suitable for an append-only single-line field
function scr_text_input_clean_paste(raw_text, max_length)
{
	/* Limit the raw clipboard text before replacing whitespace and filtering
	control characters so an oversized paste does not enter the cleaning loop */
	var text = string_copy(string(raw_text), 1, max_length);
	text = string_replace_all(text, "\r\n", " ");
	text = string_replace_all(text, "\r", " ");
	text = string_replace_all(text, "\n", " ");
	text = string_replace_all(text, "\t", " ");

	/* Accumulate the accepted single-line characters from an empty result.
	This value becomes the cleaned paste, not the field's existing contents */
	var clean_text = "";

	/* Visit characters from GML's one-based string index through the clipped
	text length. Stop at the end so each pasted character is filtered once */
	for (var char_index = 1; char_index <= string_length(text); char_index++)
	{
		/* Read the current character and its code point to distinguish visible text
		from the control characters that are unsuitable for a single-line field */
		var character = string_char_at(text, char_index);
		var character_code = ord(character);

		/* Keep space and higher code points except DEL at 127.
		Other controls are discarded after line breaks and tabs were replaced above */
		if (character_code >= 32 && character_code != 127)
		{
			clean_text += character;
		}
	}
	return clean_text;
}

/// @description Append one paste to keyboard_string for the focused field, before field validation
/// @param {String} field_key Stable field identity used by the browser paste bridge
/// @param {String} previous_text Last validated text. Desktop paste starts from this value
/// @param {Real} max_length Maximum resulting character count, defaulting to 1024
/// @returns {Bool} Whether a nonempty cleaned paste was consumed. Text may be unchanged at the length limit
function scr_text_input_update(field_key, previous_text, max_length = 1024)
{
	/* Use a nonnegative whole-character limit for clipping the combined field.
	Keep an initially empty pasted_text until the platform supplies a paste,
	and start base_text from the current keyboard_string for the browser path */
	var limit = max(0, floor(max_length));
	var pasted_text = "";
	var base_text = string(keyboard_string);

	/* Browser paste arrives through the focused JavaScript field bridge.
	This path also receives Command+V and paste-menu events without polling
	the desktop clipboard shortcuts */
	if (os_browser != browser_not_a_browser)
	{
		/* Browser paste events also support Command+V and the browser's Paste menu */
		html5_text_input_focus(string(field_key));
		pasted_text = html5_text_input_take_paste(string(field_key));

		/* No queued browser paste leaves the field untouched and returns false */
		if (pasted_text == "") return false;
	}

	/* Desktop runners poll the paste shortcut and clipboard directly.
	Build from the previous validated text to avoid a shortcut or runner paste
	being counted twice in keyboard_string */
	else
	{
		/* Without a new paste shortcut, leave the field unchanged */
		if (!scr_text_input_paste_pressed()) return false;

		/* If another field already consumed this Step's desktop paste, skip it.
		Check that the global exists before reading it so the first call is safe */
		if (variable_global_exists("text_input_paste_handled")
		&& global.text_input_paste_handled) return false;
		global.text_input_paste_handled = true;

		/* Some runners insert the shortcut or clipboard into keyboard_string first.
		Build from the last validated value so the paste is applied exactly once */
		base_text = string(previous_text);
		try
		{
			pasted_text = string(clipboard_get_text());
		}

		/* A clipboard read exception leaves this paste unapplied. Restore the previous
		validated keyboard text and return false. paste_error is intentionally unused
		because this handler falls back without displaying clipboard diagnostics */
		catch (paste_error)
		{
			keyboard_string = base_text;
			return false;
		}
		keyboard_string = base_text;
	}

	pasted_text = scr_text_input_clean_paste(pasted_text, limit);

	/* An empty or fully filtered paste is not reported as consumed.
	Otherwise append it once and clip the result to the field's character limit */
	if (pasted_text == "") return false;
	keyboard_string = string_copy(base_text + pasted_text, 1, limit);
	return true;
}
