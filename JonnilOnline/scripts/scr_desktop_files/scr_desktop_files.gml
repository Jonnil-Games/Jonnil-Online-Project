#region /* Native PNG Import */
/// @description Choose a desktop PNG. Linux copies it into the writable save area before returning
/// @param {String} linux_cache_path Game-owned destination for the Linux import copy
/// @returns {Struct} selected_path for display, readable_path for loading, cancelled and error_message
function scr_desktop_pick_png(linux_cache_path)
{
	/* Keep the original selected_path for display and readable_path for loading
	Both start empty, cancelled starts false, and error_message stays empty until a failure is detected */
	var result =
	{
		selected_path: "",
		readable_path: "",
		cancelled: false,
		error_message: ""
	};

	/* Linux uses the bundled native picker and copies outside-save files into the game's writable cache
	Other native platforms use GameMaker's filename dialog below */
	if (os_type == os_linux)
	{
		/* Convert the game-owned import destination to text before passing it to the native extension */
		var cache_path = string(linux_cache_path);

		/* An empty cache path cannot receive a Linux import copy, so return a preparation error */
		if (string_trim(cache_path) == "")
		{
			result.error_message = "Could not prepare the Linux PNG import path.";
			return result;
		}

		try
		{
			/* The extension returns the original selection after copying it, or empty text when selection or copying fails */
			var linux_selected_path = string(linux_desktop_pick_png_to(cache_path));

			/* Accept the import only when a selected name is returned and the readable cache file exists */
			if (string_trim(linux_selected_path) != "" && file_exists(cache_path))
			{
				result.selected_path = linux_selected_path;
				result.readable_path = cache_path;
			}

			/* An empty native response is presented as cancellation
			The extension also uses this response for picker or copy failures, so this wrapper cannot distinguish those cases */
			else if (string_trim(linux_selected_path) == "")
			{
				result.cancelled = true;
			}

			/* A returned selection without its copied cache file reports an import-copy failure */
			else
			{
				result.error_message = "Could not copy the selected PNG into the game save folder.";
			}
		}

		/* Log an extension exception and return a user-facing picker error */
		catch(e)
		{
			debug_error("Could not open Linux PNG picker: " + string(e.message));
			result.error_message = "Could not open the Linux PNG picker.";
		}
		return result;
	}

	/* Store the dialog's selection, which native Windows and macOS can read directly */
	var desktop_selected_path = get_open_filename("PNG images|*.png", "");

	/* A nonempty selection supplies both the displayed and readable path */
	if (string_trim(string(desktop_selected_path)) != "")
	{
		result.selected_path = desktop_selected_path;
		result.readable_path = desktop_selected_path;
	}

	/* An empty filename-dialog response is returned as cancellation */
	else
	{
		result.cancelled = true;
	}
	return result;
}

/// @description Request xdg-open through the bundled Linux desktop extension
/// @param {String} raw_path Native path to open
/// @returns {Bool} Whether the extension accepted the request. Other platforms return false
function scr_linux_open_path(raw_path)
{
	/* Avoid calling the Linux-only extension on other platforms */
	if (os_type != os_linux)
	{
		return false;
	}

	try
	{
		/* A positive native result means a desktop opener was launched, without confirming that a window appeared */
		return linux_desktop_open_path(string(raw_path)) > 0;
	}

	/* A native extension exception is logged and converted to a failed launch request */
	catch(e)
	{
		debug_error("Could not open Linux desktop path: " + string(e.message));
		return false;
	}
}
#endregion /* Native PNG Import END */

#region /* Folder Validation and Launch */
/* Opened means an opener launch was accepted, ManualOpenNeeded means the folder exists but launch failed,
FailedToCreate covers unsafe or unwritable paths, and Disabled identifies unsupported runtimes */
enum FolderOpenResult
{
	Opened,
	ManualOpenNeeded,
	FailedToCreate,
	Disabled
}

/// @function scr_desktop_folder_opening_is_enabled()
/// @description Check whether the runtime supports opening a desktop file manager
/// @returns {Bool} Whether this is a native Windows, macOS or Linux runtime
function scr_desktop_folder_opening_is_enabled()
{
	/* Enable folder opening only on native Windows, macOS and Linux, excluding browser and GX runtimes */
	return os_browser == browser_not_a_browser
		&& os_type != os_gxgames
		&& (os_type == os_windows || os_type == os_macosx || os_type == os_linux);
}

/// @description Normalize separators for the current native platform
/// @param {String} raw_path Path to normalize
/// @returns {String} Normalized path
function scr_desktop_folder_normalize_path(raw_path)
{
	/* Convert the supplied path to text before normalizing its separators */
	var path_text = string(raw_path);

	/* Windows needs backslashes, while other platforms replace backslashes with forward slashes */
	if (os_type == os_windows)
	{
		return string_replace_all(path_text, "/", "\\");
	}

	return string_replace_all(path_text, "\\", "/");
}

/// @description Require game_save_id or a path beneath it and reject parent traversal segments
/// @param {String} raw_path Folder path to check
/// @returns {Bool} Whether the normalized path passes the save-root check
function scr_desktop_folder_path_is_game_owned(raw_path)
{
	/* folder_path is the normalized requested folder and save_root is the normalized game-owned save directory
	separator matches the platform for both prefix and traversal checks */
	var folder_path = scr_desktop_folder_normalize_path(raw_path);
	var save_root = scr_desktop_folder_normalize_path(game_save_id);
	var separator = os_type == os_windows ? "\\" : "/";

	/* Remove trailing separators from the save root while preserving a one-character root */
	while (string_length(save_root) > 1
	&& string_char_at(save_root, string_length(save_root)) == separator)
	{
		save_root = string_delete(save_root, string_length(save_root), 1);
	}

	/* Empty folder or root text cannot establish ownership */
	if (folder_path == "" || save_root == "")
	{
		return false;
	}

	/* Windows comparisons ignore case, while other platforms retain the original case
	compare_path and compare_root are comparison copies, leaving the normalized source text intact */
	var compare_path = os_type == os_windows ? string_lower(folder_path) : folder_path;
	var compare_root = os_type == os_windows ? string_lower(save_root) : save_root;

	/* Accept only the save root itself or a prefix followed by a separator
	That boundary prevents a sibling directory with a similar name from passing the prefix check */
	if (compare_path != compare_root
	&& string_pos(compare_root + separator, compare_path) != 1)
	{
		return false;
	}

	/* relative_path removes the checked root prefix, and path_parts splits the remaining path into directory segments */
	var relative_path = string_delete(folder_path, 1, string_length(save_root));
	var path_parts = string_split(relative_path, separator);

	/* Check every zero-based relative-path segment for explicit parent traversal */
	for (var part_index = 0; part_index < array_length(path_parts); part_index++)
	{
		/* Reject '..' even beneath the save-root prefix, since it could step outside the owned directory */
		if (path_parts[part_index] == "..")
		{
			return false;
		}
	}

	return true;
}

/// @description Create a missing directory and confirm its existence
/// @param {String} raw_path Folder to prepare. Caller must validate ownership first
/// @returns {Bool} Whether the folder exists after preparation
function scr_desktop_folder_ensure_exists(raw_path)
{
	/* Normalize the directory that this operation will inspect or create */
	var folder_path = scr_desktop_folder_normalize_path(raw_path);

	/* Whitespace-only paths cannot identify a usable directory */
	if (string_trim(folder_path) == "")
	{
		return false;
	}

	try
	{
		/* Create a missing directory, then check existence again so failure is not inferred from the create call alone */
		if (!directory_exists(folder_path))
		{
			directory_create(folder_path);
		}
		return directory_exists(folder_path);
	}

	/* Convert a filesystem exception into a log message and false result */
	catch(e)
	{
		/* Read a structured exception message only after verifying its field, otherwise log the entire exception as text */
		var error_message = is_struct(e) && variable_struct_exists(e, "message")
			? string(e.message)
			: string(e);
		debug_error("Could not create folder " + folder_path + ": " + error_message);
		return false;
	}
}

/// @description Normalize a Windows path and wrap it as one quoted argument
/// @param {String} raw_path Path. Embedded double quotes are removed
/// @returns {String} Quoted argument
function scr_desktop_folder_windows_quote(raw_path)
{
	/* Remove embedded double quotes from the normalized path before enclosing it in one quoted Windows argument */
	var clean_path = string_replace_all(scr_desktop_folder_normalize_path(raw_path), chr(34), "");
	return chr(34) + clean_path + chr(34);
}

/// @description Normalize a POSIX path and quote its literal contents for a shell
/// @param {String} raw_path Path to quote
/// @returns {String} Single-quoted argument with embedded quotes escaped
function scr_desktop_folder_posix_quote(raw_path)
{
	/* clean_path is the normalized argument, single_quote is its shell delimiter,
	and escaped_quote temporarily leaves single-quote mode to include a literal quote inside the path */
	var clean_path = scr_desktop_folder_normalize_path(raw_path);
	var single_quote = "'";
	var escaped_quote = single_quote + chr(34) + single_quote + chr(34) + single_quote;
	return single_quote + string_replace_all(clean_path, single_quote, escaped_quote) + single_quote;
}

/// @description Request the platform file manager. Callers must check the path before launching
/// @param {String} raw_path Folder to open
/// @returns {Bool} Whether the launch request succeeded
function scr_desktop_folder_launch(raw_path)
{
	/* Normalize the folder passed to the platform opener without changing the caller's input */
	var folder_path = scr_desktop_folder_normalize_path(raw_path);
	try
	{
		/* Choose the native platform's file-manager command
		Unsupported platform values fall through to false below */
		switch (os_type)
		{
			/* Windows asks Explorer to open the quoted path
			windows_process_id records the launch result, accepted only when it is a positive numeric process ID */
			case os_windows:
				var windows_process_id = execute_shell("explorer", scr_desktop_folder_windows_quote(folder_path));
				return is_real(windows_process_id) && windows_process_id > 0;

			/* macOS uses open with '--' before the quoted path
			mac_process_id records the launch result, accepted only when it is a positive numeric process ID */
			case os_macosx:
				var mac_process_id = execute_shell("open", "-- " + scr_desktop_folder_posix_quote(folder_path));
				return is_real(mac_process_id) && mac_process_id > 0;

			case os_linux:

				/* The bundled libxprocess package does not include every Linux binary.
				Use the native Linux desktop extension to launch xdg-open */
				return scr_linux_open_path(folder_path);
		}
	}

	/* Log a thrown launch error and fall through to the failed result */
	catch(e)
	{
		/* Prefer a verified structured message, otherwise stringify the exception without reading a missing field */
		var error_message = is_struct(e) && variable_struct_exists(e, "message")
			? string(e.message)
			: string(e);
		debug_error("Could not open folder " + folder_path + ": " + error_message);
	}

	return false;
}
#endregion /* Folder Validation and Launch END */

#region /* Folder Display and Feedback */
/// @description Read and normalize a home-directory environment value for display matching
/// @param {String} variable_name Environment variable name
/// @returns {String} Trimmed value with forward slashes, or empty text on exception
function scr_desktop_folder_environment_path(variable_name)
{
	try
	{
		return string_replace_all(string_trim(string(environment_get_variable(variable_name))), "\\", "/");
	}

	/* An unavailable environment value is treated as an empty path so display redaction can try another source */
	catch(e)
	{
		return "";
	}
}

/// @description Replace the detected home folder name in a displayed path
/// @param {String} display_path Forward-slash display path
/// @param {String} raw_home_path Candidate home directory
/// @returns {String} Redacted display path, or the original when the prefix does not match
function scr_desktop_folder_redact_home_prefix(display_path, raw_home_path)
{
	/* Convert the candidate home directory to text before removing redundant trailing slashes */
	var home_path = string(raw_home_path);

	/* Trim trailing slashes while retaining a one-character root for prefix comparison */
	while (string_length(home_path) > 1
	&& string_char_at(home_path, string_length(home_path)) == "/")
	{
		home_path = string_delete(home_path, string_length(home_path), 1);
	}

	/* Without a home path, preserve the supplied display text for the next redaction strategy */
	if (home_path == "")
	{
		return display_path;
	}

	/* Lowercase comparison copies make home-prefix detection case-insensitive without altering the displayed path */
	var compare_path = string_lower(display_path);
	var compare_home = string_lower(home_path);

	/* Redact only an exact home path or a descendant separated by '/', avoiding similarly named sibling directories */
	if (compare_path != compare_home
	&& string_pos(compare_home + "/", compare_path) != 1)
	{
		return display_path;
	}

	/* Zero means no slash has been found yet in the home path */
	var last_separator = 0;

	/* Scan one-based character positions backwards to locate the home folder's final separator */
	for (var char_index = string_length(home_path); char_index >= 1; char_index--)
	{
		/* The first slash found from the end identifies the start of the home folder name, so stop scanning */
		if (string_char_at(home_path, char_index) == "/")
		{
			last_separator = char_index;
			break;
		}
	}

	/* Preserve the parent prefix and replace the final home folder with '*'
	If there is no separator, replace the whole home name instead */
	var redacted_home = last_separator > 0
		? string_copy(home_path, 1, last_separator) + "*"
		: "*";
	return redacted_home + string_delete(display_path, 1, string_length(home_path));
}

/// @description Replace the username following a recognized directory marker
/// @param {String} display_path Forward-slash display path
/// @param {String} segment_marker Username-parent marker such as /Users/
/// @returns {String} Display path with that username replaced by an asterisk
function scr_desktop_folder_redact_user_segment(display_path, segment_marker)
{
	/* lower_path and lower_marker support case-insensitive marker matching
	marker_position is its one-based location, or zero when no marker is found */
	var lower_path = string_lower(display_path);
	var lower_marker = string_lower(segment_marker);
	var marker_position = string_pos(lower_marker, lower_path);

	/* Without the user-directory marker, leave the displayed path unchanged */
	if (marker_position <= 0)
	{
		return display_path;
	}

	/* user_start locates the username after the marker, remaining_path contains that username and its descendants,
	and next_separator identifies where the username ends */
	var user_start = marker_position + string_length(segment_marker);
	var remaining_path = string_copy(display_path, user_start, string_length(display_path));
	var next_separator = string_pos("/", remaining_path);

	/* A username with no following slash is the final path segment, so replace the entire remaining text */
	if (next_separator <= 0)
	{
		return string_copy(display_path, 1, user_start - 1) + "*";
	}

	return string_copy(display_path, 1, user_start - 1)
		+ "*"
		+ string_copy(remaining_path, next_separator, string_length(remaining_path));
}

/// @description Hide the user folder in the displayed path while preserving the original path for copying
/// @param {String} raw_path Native path
/// @returns {String} Display path with the detected home or user segment replaced by an asterisk
function scr_desktop_folder_display_path(raw_path)
{
	/* Use forward slashes for display, while home_path first tries Windows USERPROFILE for username redaction */
	var display_path = string_replace_all(scr_desktop_folder_normalize_path(raw_path), "\\", "/");
	var home_path = scr_desktop_folder_environment_path("USERPROFILE");

	/* When USERPROFILE is unavailable, try the HOME environment value used on other platforms */
	if (home_path == "")
	{
		home_path = scr_desktop_folder_environment_path("HOME");
	}

	/* First attempt the detected home prefix before trying recognizable user-directory markers */
	var redacted_path = scr_desktop_folder_redact_home_prefix(display_path, home_path);

	/* An unchanged home-prefix result falls back to the '/Users/' username pattern */
	if (redacted_path == display_path)
	{
		redacted_path = scr_desktop_folder_redact_user_segment(display_path, "/Users/");
	}

	/* If redaction still has not changed the text, try the '/home/' username pattern */
	if (redacted_path == display_path)
	{
		redacted_path = scr_desktop_folder_redact_user_segment(display_path, "/home/");
	}

	return redacted_path;
}

/// @description Describe the folder result and platform-specific manual-opening steps
/// @param {Real} result FolderOpenResult value
/// @param {String} folder_label Human-readable folder name
/// @returns {String} Modal feedback text
function scr_desktop_folder_result_text(result, folder_label)
{
	/* Lowercase the folder label for its use within the feedback sentence */
	var folder_description = string_lower(string(folder_label));

	/* Unsafe or uncreated folders need write-access feedback rather than instructions to open a prepared folder */
	if (result == FolderOpenResult.FailedToCreate)
	{
		return "The game could not create the " + folder_description
			+ ". Check that it can write to its local save-data folder, then try again.";
	}

	/* Unsupported runtimes show that folder opening is unavailable */
	if (result == FolderOpenResult.Disabled)
	{
		return "Opening folders is not available on this platform.";
	}

	/* Use launch-request wording for Opened and manual-opening wording for other prepared-folder results */
	var intro = result == FolderOpenResult.Opened
		? "The game asked your operating system to open the " + folder_description + "."
		: "The folder is ready, but the file manager could not be started automatically.";

	/* Windows feedback explains how to paste the path into the Run dialog when Explorer did not appear */
	if (os_type == os_windows)
	{
		return intro + "\n\nIf Explorer did not appear, choose Copy to Clipboard, press Windows + R, paste the path, and press Enter.";
	}

	/* macOS feedback uses Finder's Go to Folder shortcut, while the final return describes a Linux launcher */
	if (os_type == os_macosx)
	{
		return intro + "\n\nIf Finder did not appear, choose Copy to Clipboard, press Shift + Command + G, paste the path, and press Return.";
	}

	return intro + "\n\nIf your file manager did not appear, choose Copy to Clipboard, press Alt + F2, paste the path, and press Enter.";
}

/// @description Describe the folder result for a compact modal
/// @param {Real} result FolderOpenResult value
/// @param {String} folder_label Human-readable folder name
/// @returns {String} Short modal feedback
function scr_desktop_folder_compact_result_text(result, folder_label)
{
	/* Lowercase the supplied label for compact feedback on small modal layouts */
	var folder_description = string_lower(string(folder_label));

	/* Uncreated or rejected folders show a short write-access error */
	if (result == FolderOpenResult.FailedToCreate)
	{
		return "The game could not create the " + folder_description + ". Check save-folder write access and try again.";
	}

	/* Unsupported platforms show a short unavailable message */
	if (result == FolderOpenResult.Disabled)
	{
		return "Opening folders is not available on this platform.";
	}

	/* An accepted launch still includes manual-opening advice because the request does not prove a window appeared */
	if (result == FolderOpenResult.Opened)
	{
		return "The folder is ready. If it did not appear, copy the path and open it in your file manager.";
	}

	return "The folder is ready, but the file manager did not open. Copy the path below and open it manually.";
}
#endregion /* Folder Display and Feedback END */

/// @description Own the folder-result modal, redacted display path and original clipboard path
function scr_open_folder_modal() constructor
{
	/* active starts false until show opens the modal
	folder_path retains the original clipboard path, while display_path stores its username-redacted form
	folder_label defaults to 'Folder', and both message strings start empty until a result is shown */
	active = false;
	folder_path = "";
	display_path = "";
	folder_label = "Folder";
	message_text = "";
	compact_message_text = "";

	/* result starts Disabled and can_copy starts false so no path action is offered before show
	selected_key starts on Back, hover_key is empty until pointer hit testing, and both current_time
	feedback deadlines start at zero so neither success nor failure feedback is visible */
	result = FolderOpenResult.Disabled;
	can_copy = false;
	selected_key = "back";
	hover_key = "";
	copied_until = 0;
	copy_failed_until = 0;

	/* Opening a modal releases the previous UI action before accepting its own input */
	input_release_pending = false;

	/// @description Open the modal with fresh path, result and input-release state
	/// @param {String} raw_path Original path retained for clipboard copying
	/// @param {String} raw_label Folder title. Empty text uses Folder
	/// @param {Real} open_result FolderOpenResult value
	show = function(raw_path, raw_label, open_result)
	{
		folder_path = scr_desktop_folder_normalize_path(raw_path);
		display_path = scr_desktop_folder_display_path(folder_path);
		folder_label = string_trim(string(raw_label));

		/* An empty supplied label uses 'Folder' to keep the modal title and feedback readable */
		if (folder_label == "")
		{
			folder_label = "Folder";
		}

		result = open_result;
		message_text = scr_desktop_folder_result_text(result, folder_label);
		compact_message_text = scr_desktop_folder_compact_result_text(result, folder_label);

		/* Copy is available only when folder opening is supported and a path remains
		Select Copy when available, otherwise Back, then clear old hover and feedback for this newly opened result */
		can_copy = result != FolderOpenResult.Disabled && folder_path != "";
		selected_key = can_copy ? "copy" : "back";
		hover_key = "";
		copied_until = 0;
		copy_failed_until = 0;
		input_release_pending = true;
		active = true;
	}

	/// @description Close the modal and reset hover and selection
	close_modal = function()
	{
		active = false;
		hover_key = "";
		selected_key = "back";
	}

	/// @description Report whether the modal owns screen input
	/// @returns {Bool} Whether the modal is active
	blocks_input = function()
	{
		/* While the modal is active, the caller must withhold input from the screen behind it */
		return active;
	}

	/// @description Consume the one-time release requested when the modal opens
	/// @returns {Bool} Whether the controller must release input held by the preceding screen
	consume_input_release = function()
	{
		/* Without a pending release, leave the caller's input state alone
		The first call after show clears the flag and requests one release to avoid carrying the opening action into the modal */
		if (!input_release_pending)
		{
			return false;
		}

		input_release_pending = false;
		return true;
	}

	/// @description Calculate responsive GUI geometry shared by drawing and input
	/// @returns {Struct} Panel, text and button positions in GUI pixels, plus compact flags
	layout = function()
	{
		/* gui_w/gui_h are positive GUI pixel dimensions
		panel_margin scales edge clearance from 6 to 32 pixels, panel_w/panel_h cap the panel at 806 by 600,
		and panel_left/panel_top centre it within the GUI */
		var gui_w = max(1, display_get_gui_width());
		var gui_h = max(1, display_get_gui_height());
		var panel_margin = clamp(floor(min(gui_w, gui_h) * 0.04), 6, 32);
		var panel_w = min(806, max(1, gui_w - panel_margin * 2));
		var panel_h = min(600, max(1, gui_h - panel_margin * 2));
		var panel_left = (gui_w - panel_w) * 0.5;
		var panel_top = (gui_h - panel_h) * 0.5;

		/* very_compact marks panels below 330 pixels high
		compact also covers heights below 520 or widths below 640, reducing text and spacing to fit */
		var very_compact = panel_h < 330;
		var compact = very_compact || panel_h < 520 || panel_w < 640;

		/* button_w shrinks side padding on compact panels
		button_h, button_gap and bottom_padding step down further in very compact layouts
		button_left centres both actions, back_top anchors Back at the bottom, and copy_top places Copy above it */
		var button_w = min(512, max(1, panel_w - (compact ? 24 : 64)));
		var button_h = very_compact ? 28 : (compact ? 36 : 44);
		var button_gap = very_compact ? 4 : (compact ? 7 : 10);
		var bottom_padding = very_compact ? 8 : (compact ? 14 : 24);
		var button_left = panel_left + (panel_w - button_w) * 0.5;
		var back_top = panel_top + panel_h - bottom_padding - button_h;
		var copy_top = back_top - button_gap - button_h;

		/* title_y/title_size and message_y/message_size use smaller offsets and text sizes as the panel gets shorter
		path_label_y reserves space above Copy, and path_text_y positions the redacted path below its label */
		var title_y = panel_top + (very_compact ? 8 : (compact ? 16 : 34));
		var title_size = very_compact ? 18 : (compact ? 22 : 28);
		var message_y = title_y + (very_compact ? 26 : (compact ? 40 : 60));
		var message_size = very_compact ? 12 : (compact ? 15 : 18);
		var path_label_y = very_compact
			? copy_top - 45
			: (compact ? copy_top - 62 : min(panel_top + 330, copy_top - 92));
		var path_text_y = path_label_y + (very_compact ? 15 : (compact ? 19 : 27));

		/* Return GUI dimensions, panel edges/size, compact flags, title/message/path positions and text sizes,
		plus Copy/Back hit rectangles and their shared button size, so drawing and input use identical geometry */
		return
		{
			gui_w: gui_w,
			gui_h: gui_h,
			left: panel_left,
			top: panel_top,
			right: panel_left + panel_w,
			bottom: panel_top + panel_h,
			w: panel_w,
			h: panel_h,
			compact: compact,
			very_compact: very_compact,
			title_y: title_y,
			title_size: title_size,
			message_y: message_y,
			message_size: message_size,
			path_label_y: path_label_y,
			path_text_y: path_text_y,
			copy_left: button_left,
			copy_top: copy_top,
			copy_right: button_left + button_w,
			copy_bottom: copy_top + button_h,
			back_left: button_left,
			back_top: back_top,
			back_right: button_left + button_w,
			back_bottom: back_top + button_h,
			button_w: button_w,
			button_h: button_h
		};
	}

	/// @description Test a point against an inclusive GUI rectangle
	/// @param {Real} point_x Point's horizontal coordinate
	/// @param {Real} point_y Point's vertical coordinate
	/// @param {Real} left Rectangle's left edge
	/// @param {Real} top Rectangle's top edge
	/// @param {Real} right Rectangle's right edge
	/// @param {Real} bottom Rectangle's bottom edge
	/// @returns {Bool} Whether the point is inside or on an edge
	point_in_rect = function(point_x, point_y, left, top, right, bottom)
	{
		/* Include all four rectangle edges in the hit test so visible boundary pixels remain clickable */
		return point_x >= left && point_x <= right && point_y >= top && point_y <= bottom;
	}

	/// @description Copy the original path and update millisecond feedback deadlines
	/// @returns {Bool} Whether copying succeeded. Logs exceptions and sets failure feedback
	copy_path = function()
	{
		/* A disabled copy action exits without touching the clipboard or feedback deadlines */
		if (!can_copy)
		{
			return false;
		}

		try
		{
			clipboard_set_text(folder_path);

			/* A successful copy shows feedback for 1500 current_time milliseconds and clears any previous failure feedback */
			copied_until = current_time + 1500;
			copy_failed_until = 0;
			return true;
		}

		/* Clipboard errors are logged and show failure feedback for 2500 current_time milliseconds instead of success */
		catch(e)
		{
			/* Read e.message only when the exception is a struct containing that field, otherwise use its text form */
			var error_message = is_struct(e) && variable_struct_exists(e, "message")
				? string(e.message)
				: string(e);
			debug_error("Could not copy folder path: " + error_message);
			copy_failed_until = current_time + 2500;
			copied_until = 0;
			return false;
		}
	}

	/// @description Handle pointer, keyboard and first-four-gamepad modal actions
	/// @returns {Bool} Whether the active modal owns this frame's input
	update_input = function()
	{
		/* A closed modal handles no input, allowing the controller to continue with the current screen */
		if (!active)
		{
			return false;
		}

		/* modal_layout supplies this frame's shared GUI geometry
		mouse_x_gui/mouse_y_gui translate device-zero pointer coordinates into that same space */
		var modal_layout = layout();
		var mouse_x_gui = device_mouse_x_to_gui(0);
		var mouse_y_gui = device_mouse_y_to_gui(0);
		hover_key = "";

		/* Hover Copy only when it is available and the pointer is inside its visible rectangle */
		if (can_copy
		&& point_in_rect(mouse_x_gui, mouse_y_gui, modal_layout.copy_left, modal_layout.copy_top, modal_layout.copy_right, modal_layout.copy_bottom))
		{
			hover_key = "copy";
		}

		/* Otherwise hover Back when the pointer reaches its rectangle */
		else if (point_in_rect(mouse_x_gui, mouse_y_gui, modal_layout.back_left, modal_layout.back_top, modal_layout.back_right, modal_layout.back_bottom))
		{
			hover_key = "back";
		}

		/* A hovered button becomes the selected action so pointer and keyboard acceptance agree */
		if (hover_key != "")
		{
			selected_key = hover_key;
		}

		/* navigate_pressed combines vertical arrows and W/S, accept_pressed combines Enter/Space/Z,
		and back_pressed combines Escape/Backspace/X with right-click dismissal */
		var navigate_pressed = keyboard_check_pressed(vk_up)
			|| keyboard_check_pressed(vk_down)
			|| keyboard_check_pressed(ord("W"))
			|| keyboard_check_pressed(ord("S"));
		var accept_pressed = keyboard_check_pressed(vk_enter)
			|| keyboard_check_pressed(vk_space)
			|| keyboard_check_pressed(ord("Z"));
		var back_pressed = keyboard_check_pressed(vk_escape)
			|| keyboard_check_pressed(vk_backspace)
			|| keyboard_check_pressed(ord("X"))
			|| mouse_check_button_pressed(mb_right);

		/* Check the first four zero-based gamepad slots and merge their modal actions with keyboard input */
		for (var gamepad_slot = 0; gamepad_slot < 4; gamepad_slot++)
		{
			/* Skip disconnected slots before querying their buttons */
			if (!gamepad_is_connected(gamepad_slot))
			{
				continue;
			}

			navigate_pressed = navigate_pressed
				|| gamepad_button_check_pressed(gamepad_slot, gp_padu)
				|| gamepad_button_check_pressed(gamepad_slot, gp_padd);
			accept_pressed = accept_pressed || gamepad_button_check_pressed(gamepad_slot, gp_face1);
			back_pressed = back_pressed || gamepad_button_check_pressed(gamepad_slot, gp_face2);
		}

		/* With two actions available, vertical navigation toggles Copy and Back
		Without Copy, Back remains the only selection */
		if (can_copy && navigate_pressed)
		{
			selected_key = selected_key == "copy" ? "back" : "copy";
		}

		/* Dismissal takes priority over copy and accept actions during the same frame */
		if (back_pressed)
		{
			close_modal();
			return true;
		}

		/* Ctrl+C copies only when the modal exposes a usable path, then consumes this frame's input */
		if (can_copy
		&& keyboard_check(vk_control)
		&& keyboard_check_pressed(ord("C")))
		{
			copy_path();
			return true;
		}

		/* Capture the left-button press edge once for the two pointer actions */
		var mouse_pressed = mouse_check_button_pressed(mb_left);

		/* A press over Copy sends the original path to the clipboard and consumes the input */
		if (mouse_pressed && hover_key == "copy")
		{
			copy_path();
			return true;
		}

		/* A press over Back closes the modal and consumes the input */
		if (mouse_pressed && hover_key == "back")
		{
			close_modal();
			return true;
		}

		/* Keyboard or gamepad acceptance activates the currently selected action */
		if (accept_pressed)
		{
			/* Copy acceptance requires both selection and availability */
			if (selected_key == "copy" && can_copy)
			{
				copy_path();
			}

			/* All other accepted selections dismiss the modal */
			else
			{
				close_modal();
			}
		}

		return true;
	}

	/// @description Draw the active modal and restore alpha, colour and alignment
	draw = function()
	{
		/* Closed modals draw nothing, leaving the current screen unobscured */
		if (!active)
		{
			return;
		}

		/* Use the same GUI layout as input for the dimmed background, panel, text and button rectangles */
		var modal_layout = layout();
		draw_set_alpha(0.82);
		draw_set_colour(c_black);
		draw_rectangle(0, 0, modal_layout.gui_w, modal_layout.gui_h, false);

		draw_set_alpha(1);
		draw_set_colour(make_color_rgb(28, 25, 40));
		draw_rectangle(modal_layout.left, modal_layout.top, modal_layout.right, modal_layout.bottom, false);
		draw_set_colour(make_color_rgb(178, 180, 190));
		draw_rectangle(modal_layout.left, modal_layout.top, modal_layout.right, modal_layout.bottom, true);

		draw_set_halign(fa_center);
		draw_set_valign(fa_top);
		draw_set_colour(c_white);
		scr_render_text(modal_layout.left + modal_layout.w * 0.5, modal_layout.title_y, folder_label, modal_layout.title_size, modal_layout.w - 40);

		/* Start feedback in white, then assign a result-specific colour */
		var message_colour = c_white;

		/* Accepted launch requests use pale green feedback */
		if (result == FolderOpenResult.Opened)
		{
			message_colour = make_color_rgb(198, 235, 204);
		}

		/* Prepared folders needing manual opening use yellow feedback */
		else if (result == FolderOpenResult.ManualOpenNeeded)
		{
			message_colour = make_color_rgb(255, 220, 95);
		}

		/* Rejected or uncreated folders use red feedback */
		else if (result == FolderOpenResult.FailedToCreate)
		{
			message_colour = make_color_rgb(244, 112, 112);
		}

		draw_set_colour(message_colour);

		/* Compact panels use the shorter feedback text, narrower padding and fewer line-gap pixels
		Very compact layouts reduce the line gap again to keep the message above the path actions */
		var visible_message = modal_layout.compact ? compact_message_text : message_text;
		scr_render_text_wrapped(
			modal_layout.left + modal_layout.w * 0.5,
			modal_layout.message_y,
			visible_message,
			modal_layout.message_size,
			modal_layout.w - (modal_layout.compact ? 38 : 86),
			modal_layout.very_compact ? 2 : (modal_layout.compact ? 3 : 5)
		);

		/* Show the redacted path only when an original path is available to copy */
		if (can_copy)
		{
			/* Omit the explanatory path label on the shortest panels, and use a smaller label on compact panels */
			if (!modal_layout.very_compact)
			{
				draw_set_colour(make_color_rgb(164, 166, 176));
				scr_render_text(modal_layout.left + modal_layout.w * 0.5, modal_layout.path_label_y, "Folder path (username hidden)", modal_layout.compact ? 12 : 14, modal_layout.w - 40);
			}
			draw_set_colour(make_color_rgb(194, 229, 222));

			/* Compact panels shrink the path to one line, with the smallest text in very compact layouts */
			if (modal_layout.compact)
			{
				scr_render_text(modal_layout.left + modal_layout.w * 0.5, modal_layout.path_text_y, display_path, modal_layout.very_compact ? 11 : 14, modal_layout.w - 38);
			}

			/* Larger panels can wrap the redacted path across multiple lines */
			else
			{
				scr_render_text_wrapped(modal_layout.left + modal_layout.w * 0.5, modal_layout.path_text_y, display_path, 17, modal_layout.w - 68, 4);
			}
		}

		/* Draw the Copy button only while its action is available */
		if (can_copy)
		{
			/* The copy label starts with its action name and is temporarily replaced by feedback text */
			var copy_button_label = "Copy to Clipboard";

			/* Show success while its millisecond deadline is still in the future */
			if (copied_until > current_time)
			{
				copy_button_label = "Copied!";
			}

			/* If success feedback is inactive, show failure until its own deadline expires */
			else if (copy_failed_until > current_time)
			{
				copy_button_label = "Copy Failed";
			}
			scr_draw_menu_button(
				modal_layout.copy_left,
				modal_layout.copy_top,
				modal_layout.button_w,
				modal_layout.button_h,
				copy_button_label,
				hover_key == "copy",
				selected_key == "copy",
				true,
				false,
				false,
				19
			);
		}

		scr_draw_menu_button(
			modal_layout.back_left,
			modal_layout.back_top,
			modal_layout.button_w,
			modal_layout.button_h,
			"Back",
			hover_key == "back",
			selected_key == "back",
			true,
			false,
			false,
			19
		);

		draw_set_alpha(1);
		draw_set_colour(c_white);
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
	}
}

/// @description Get the shared folder-result modal
/// @returns {Struct} Lazily constructed scr_open_folder_modal instance
function scr_get_open_folder_modal()
{
	/* Construct one shared modal for the runtime so controller input and drawing observe the same state */
	static modal = new scr_open_folder_modal();
	return modal;
}

/// @function scr_open_folder(folder_path, folder_label)
/// @description Prepare a folder under game_save_id, request its file manager and show the path modal
/// @param {String} folder_path Absolute game-save path without parent traversal segments
/// @param {String} folder_label Human-readable folder name, defaulting to Folder
/// @returns {Real} FolderOpenResult. Opened means the launch request succeeded, not that a window appeared
function scr_open_folder(folder_path, folder_label = "Folder")
{
	/* normalized_path is the launch and clipboard path
	open_result starts Disabled and changes only after platform support and path preparation are checked */
	var normalized_path = scr_desktop_folder_normalize_path(folder_path);
	var open_result = FolderOpenResult.Disabled;

	/* Only supported native platforms attempt save-root validation, directory creation and launching */
	if (scr_desktop_folder_opening_is_enabled())
	{
		/* Reject paths outside the save root or containing parent traversal before any create or launch operation
		Clear the path so the modal cannot offer the rejected destination for copying */
		if (!scr_desktop_folder_path_is_game_owned(normalized_path))
		{
			open_result = FolderOpenResult.FailedToCreate;
			debug_error("Refused to open a folder outside game_save_id: " + normalized_path);
			normalized_path = "";
		}

		/* A safe path that cannot be prepared reports creation failure */
		else if (!scr_desktop_folder_ensure_exists(normalized_path))
		{
			open_result = FolderOpenResult.FailedToCreate;
		}

		/* A prepared folder whose opener launch is accepted reports Opened */
		else if (scr_desktop_folder_launch(normalized_path))
		{
			open_result = FolderOpenResult.Opened;
			debug_log("Opened " + string(folder_label) + ": " + normalized_path);
		}

		/* Keep the prepared path available for copying when automatic file-manager launching fails */
		else
		{
			open_result = FolderOpenResult.ManualOpenNeeded;
			debug_error("The file manager could not open " + string(folder_label) + ": " + normalized_path);
		}
	}

	scr_get_open_folder_modal().show(normalized_path, folder_label, open_result);
	return open_result;
}
