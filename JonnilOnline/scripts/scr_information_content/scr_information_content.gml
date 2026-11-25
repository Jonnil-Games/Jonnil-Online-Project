/// @description Accept public HTTPS destinations, optionally restricted to a Patreon campaign path
/// @param {Any} raw_url Configured destination, never an executable or local path
/// @param {Bool} patreon_only Whether to require the public Patreon host and a path
/// @returns {Bool} Whether the destination passes the menu's syntax and host checks
function scr_information_content_url_is_valid(raw_url, patreon_only = false)
{
	if (!is_string(raw_url)) return false;
	var url = string_trim(raw_url);
	if (string_length(url) > 2048 || string_pos("https://", url) != 1 || string_length(url) <= 8) return false;
	if (string_pos(" ", url) > 0 || string_pos("\t", url) > 0 || string_pos("\r", url) > 0 || string_pos("\n", url) > 0) return false;
	if (!patreon_only) return true;

	var public_prefix = "https://www.patreon.com/";
	var short_prefix = "https://patreon.com/";
	return (string_pos(public_prefix, url) == 1 && string_length(url) > string_length(public_prefix))
		|| (string_pos(short_prefix, url) == 1 && string_length(url) > string_length(short_prefix));
}

/// @description Load one Information content snapshot from fixed Included File paths
/// @returns {Struct} Validated destinations and optional approved text, with absent pages unavailable
function scr_information_content_load()
{
	/* Each Information entry gets a fresh snapshot. Empty optional files add no visible page or promise */
	var data =
	{
		schema_version: 1,
		patreon_url: "",
		privacy_url: "",
		support_text: "",
		privacy_text: "",
		credits_text: "",
		support_available: false,
		policy_available: false
	};

	if (file_exists("information/menu.json"))
	{
		try
		{
			var config_text = scr_read_included_text_file("information/menu.json");
			if (string_length(config_text) > 0 && string_length(config_text) <= 16384)
			{
				var config = json_parse(config_text);
				if (is_struct(config) && variable_struct_exists(config, "schema_version")
				&& is_real(config.schema_version) && config.schema_version == 1)
				{
					if (variable_struct_exists(config, "patreon_url") && scr_information_content_url_is_valid(config.patreon_url, true))
					{
						data.patreon_url = string_trim(config.patreon_url);
					}
					if (variable_struct_exists(config, "privacy_url") && scr_information_content_url_is_valid(config.privacy_url))
					{
						data.privacy_url = string_trim(config.privacy_url);
					}
				}
			}
		}
		catch(content_error)
		{
			debug_error("Could not load Information menu configuration.");
		}
	}

	/* Only these bundled filenames are read. Remote content cannot introduce file paths or actions */
	if (file_exists("information/support.txt")) data.support_text = string_trim(scr_read_included_text_file("information/support.txt"));
	if (file_exists("information/privacy.txt")) data.privacy_text = string_trim(scr_read_included_text_file("information/privacy.txt"));
	if (file_exists("information/credits.txt")) data.credits_text = string_trim(scr_read_included_text_file("information/credits.txt"));
	data.support_available = data.patreon_url != "" || data.support_text != "";
	data.policy_available = data.privacy_url != "" || data.privacy_text != "";
	return data;
}

/// @description List bundled third-party notices without replacing or rewriting their original text
/// @returns {Array<Struct>} Stable page IDs, visible titles, and fixed Included File paths
function scr_information_content_notices()
{
	return
	[
		{id: "legal_noto", title: "Noto Sans CJK font license", path: "Fonts/NotoSansCJK_LICENSE.txt"},
		{id: "legal_discord", title: "Discord extension license", path: "Legal/discord_social_extension_LICENSE.txt"},
		{id: "legal_discord_sdk", title: "Discord SDK notices", path: "Legal/discord_social_sdk_NOTICES.txt"},
		{id: "legal_process", title: "libxprocess license", path: "Legal/libxprocess_LICENSE.txt"},
		{id: "legal_process_adapter", title: "Process adapter license", path: "Legal/libxprocess_adapter_LICENSE.txt"},
		{id: "legal_process_win", title: "Windows process notices", path: "Legal/libxprocess_Windows_LICENSES.txt"},
		{id: "legal_process_linux", title: "Linux process notices", path: "Legal/libxprocess_Linux_LICENSES.txt"},
		{id: "legal_process_phnt", title: "PHNT notices", path: "Legal/libxprocess_PHNT.txt"},
		{id: "legal_linux", title: "Linux desktop license", path: "Legal/linux_desktop_LICENSE.txt"}
	];
}

/// @description Provide page text and actions using the current Information snapshot and runtime capabilities
/// @param {String} page Stable page ID, independent of its visible title
/// @param {Struct} data Snapshot returned by scr_information_content_load
/// @returns {Struct} Page title, body, actions, and availability
function scr_information_content(page, data)
{
	var content = {title: "Information", body: "", actions: [], available: true};
	var website_url = variable_struct_exists(data, "website_url") ? data.website_url : "https://www.jonnil.games/";
	var community_url = variable_struct_exists(data, "community_url") ? data.community_url : "https://discord.jonnil.games";

	switch (page)
	{
		case "main":
		case "about":
			content.title = "About Jonnil Online";
			content.body = "Welcome to Jonnil Online!\n\nWalk around, chat, and draw together on one shared canvas. Join a server or host a session, then make something together.\n\nYou can create your own characters and stamps, explore drawing tools, and save PNG copies of artwork you want to keep.\n\nUse Information to read update notes, find the community, learn about saving your work, and view credits.";
			content.actions =
			[
				{id: "about_website", label: "Visit website", kind: "url", target: website_url, enabled: scr_information_content_url_is_valid(website_url)},
				{id: "about_privacy", label: "Privacy and data", kind: "page", target: "privacy", enabled: true}
			];
			break;

		case "whats_new":
			content.title = "What's New";
			content.body = "Read the update notes included with this game version.";
			break;

		case "links":
			content.title = "Links";
			content.body = "Community and studio destinations open in your browser.";
			break;

		case "backups":
			content.title = "Keep your work safe";
			content.body = "Save artwork you want to keep\n\nUse Screenshot in the drawing toolbar to export a PNG. A PNG keeps the visible picture. It does not keep the editable drawing history or restore a whole server.\n\nKeep an independent copy\n\nCopy important screenshots, custom characters, and stamps to another location. To copy a desktop host's saved state, close the game first and copy its save-data folder. Keep the drawing history, walls, settings, and custom content together.\n\nA shared canvas can change or reset\n\nThe host stores accepted drawing history and can make reset or restart archives. These files are not a separate off-device backup, and another server's saves are controlled by its host.\n\nBrowser play\n\nBrowser saves belong to this browser's site storage. Keep downloaded PNGs and exported custom content outside that storage before clearing it or changing browser.";
			if (scr_desktop_folder_opening_is_enabled() && string(game_save_id) != "")
			{
				content.actions =
				[
					{id: "backups_save", label: "Open save-data folder", kind: "folder", target: game_save_id, enabled: true},
					{id: "backups_screenshots", label: "Open screenshots folder", kind: "folder", target: scr_get_drawing().screenshot_folder_path(), enabled: true},
					{id: "backups_characters", label: "Open character folder", kind: "folder", target: scr_get_player_characters().custom_folder_path(), enabled: true},
					{id: "backups_stamps", label: "Open stamps folder", kind: "folder", target: scr_get_stamps().stamp_root_path(), enabled: true}
				];
			}
			break;

		case "community":
			content.title = "Join the community";
			content.body = "Find other players and follow development\n\nJoin the Discord community to share artwork and characters, discuss drawing ideas, follow game updates, and give feedback.\n\nFound a problem? Describe what happened, include your game version, and share a screenshot when it helps. Avoid posting passwords, private messages, or other people's personal details.\n\nEveryone can take part, from first-time players to experienced artists. Follow the rules of the server and community you join.";
			content.actions = [{id: "community_discord", label: "Visit Discord community", kind: "url", target: community_url, enabled: scr_information_content_url_is_valid(community_url)}];
			break;

		case "credits":
			content.title = "Credits";
			content.body = "Jonnil Online\n\nCreated by Jonnil.\n\nBuilt with GameMaker.\n\nThird-party software\n\nThis game includes Noto Sans CJK font software and platform integrations for Discord activity and desktop features. Their original licenses and notices are available below.\n\nOriginal game source code is licensed under Apache License 2.0 where covered by the project's license scope. Artwork, fonts, logos, and third-party components keep their own terms.";
			if (data.credits_text != "") content.body += "\n\n" + data.credits_text;
			var notices = scr_information_content_notices();
			for (var notice_index = 0; notice_index < array_length(notices); notice_index++)
			{
				var notice = notices[notice_index];
				array_push(content.actions, {id: notice.id, label: notice.title, kind: "page", target: notice.id, enabled: file_exists(notice.path)});
			}
			break;

		case "privacy":
			content.title = "Privacy and data";
			content.body = "Playing with other people\n\nWhen you join a server, your chosen name, chat messages, drawing actions, and shared character content are sent to that server and other players as needed for the session. Treat the shared canvas and game chat as public to the people in that session.\n\nThe server host\n\nThe host can save shared drawing history, canvas images, chat logs, and diagnostic logs. Hosts manage their own server files and may use different rules. Check with the host before sharing anything personal.\n\nYour device\n\nThe game saves preferences, selected characters, saved-server entries, and custom content locally. Desktop drawing exports and logs are local files. Browser builds use the browser's site storage and downloads.\n\nOptional accounts\n\nYou can create an optional account with a private username and password. No email address is needed. The service stores your login username, password and recovery-code hashes, sessions, creation time, and a profile with your public display name and built-in character and pet choices. Your login username is separate from your gameplay name. On Windows and supported browser pages, you can keep your sign-in for 30 days or until you sign out. Browser sign-in uses a protected cookie. Browser privacy settings or clearing site data can end it. The game never saves your password or recovery code. Password recovery or server revocation can also end a remembered sign-in. Signing out forgets the saved sign-in on this device. If the service cannot confirm browser sign-out, the game explains what to do. While signed in, your display name and built-in character and pet choices save to your account automatically. Changes stay on this device while saving is unavailable. If another device changes the same profile, choose which version to keep. Custom artwork is not uploaded. Guest play stays available, and signing out restores your local guest profile. Save your recovery code privately. Losing both your password and code means you cannot recover the account. Account settings lets you replace the code, export your data or delete your account. Deletion removes live account data. Private backups may retain older copies, and other devices can retain local profile caches and exported files.\n\nDiscord activity\n\nSupported desktop builds can share game activity with Discord. Options includes controls for activity sharing, public name, and joining through invitations.\n\nExternal links\n\nCommunity and website buttons open external services. Those services have their own privacy choices and policies.";
			if (data.privacy_text != "")
			{
				array_push(content.actions, {id: "privacy_policy", label: "Read Privacy Policy", kind: "page", target: "policy", enabled: true});
			}
			if (data.privacy_url != "")
			{
				array_push(content.actions, {id: "privacy_website", label: "Privacy Policy website", kind: "url", target: data.privacy_url, enabled: true});
			}
			break;

		case "policy":
			content.title = "Privacy Policy";
			content.body = data.privacy_text;
			content.available = data.privacy_text != "";
			if (data.privacy_url != "") content.actions = [{id: "policy_website", label: "Privacy Policy website", kind: "url", target: data.privacy_url, enabled: true}];
			break;

		case "support":
			content.title = "Support development";
			content.available = data.support_available;
			content.body = "Support is optional. You can keep playing and use all Information pages without joining Patreon.";
			if (data.support_text != "") content.body += "\n\n" + data.support_text;
			if (data.patreon_url != "")
			{
				content.body += "\n\nVisit Patreon to read the creator's current support options. The page opens in your browser.";
				content.actions = [{id: "support_patreon", label: "Visit Patreon", kind: "url", target: data.patreon_url, enabled: true}];
			}
			break;

		default:
			content.available = false;
			var license_notices = scr_information_content_notices();
			for (var license_index = 0; license_index < array_length(license_notices); license_index++)
			{
				var license_notice = license_notices[license_index];
				if (license_notice.id != page) continue;
				content.title = license_notice.title;
				content.body = file_exists(license_notice.path) ? scr_read_included_text_file(license_notice.path) : "";
				content.available = content.body != "";
				break;
			}
			break;
	}
	return content;
}
