/* These version-one message identifiers define the shared start/pull/cancel and manifest/chunk/error/wait exchange
Chunks are capped at 4096 bytes, manifests at 128 files, each file at 128 MiB and the total at 256 MiB */
#macro ADMIN_LOG_PROTOCOL_VERSION 1
#macro ADMIN_LOG_START 0
#macro ADMIN_LOG_PULL 1
#macro ADMIN_LOG_CANCEL 2
#macro ADMIN_LOG_MANIFEST 3
#macro ADMIN_LOG_CHUNK 4
#macro ADMIN_LOG_ERROR 5
#macro ADMIN_LOG_WAIT 6
#macro ADMIN_LOG_CHUNK_BYTES 4096
#macro ADMIN_LOG_MAX_FILES 128
#macro ADMIN_LOG_MAX_FILE_BYTES 134217728
#macro ADMIN_LOG_MAX_TOTAL_BYTES 268435456

/// @description Count unread bytes within the received packet length
/// @param {Struct} net Primed network reader
/// @returns {Real} Non-negative unread byte count
function scr_admin_logs_remaining(net)
{
	/* Start with the allocated reader buffer size, then constrain it to the received packet length when available */
	var size = buffer_get_size(net.reader_buffer);

	/* Only read the optional reader_size field after checking it exists, so unused buffer capacity is excluded when possible */
	if (variable_struct_exists(net, "reader_size")) size = min(size, net.reader_size);
	return max(0, size - buffer_tell(net.reader_buffer));
}

/// @description Read a terminated log-protocol string only when it fits the current packet and limit
/// @param {Struct} net Primed network reader
/// @param {Real} limit Maximum string bytes before its terminator
/// @returns {String|Undefined} String, or undefined without advancing when no bounded terminator exists
function scr_admin_logs_read_string(net, limit)
{
	/* position preserves the current reader cursor, and available bounds the terminator search to packet bytes and limit plus one */
	var position = buffer_tell(net.reader_buffer);
	var available = min(scr_admin_logs_remaining(net), limit + 1);

	/* Scan zero-based byte offsets without advancing the reader until a bounded terminator is found */
	for (var i = 0; i < available; i++)
	{
		/* A NUL within the search range makes the string safe for net.read
		Without one, return undefined below while leaving the reader position unchanged */
		if (buffer_peek(net.reader_buffer, position + i, buffer_u8) == 0)
		{
			return net.read(buffer_string);
		}
	}
	return undefined;
}

/// @description Validate a server log basename before creating a local download file
/// @param {String} name Expected .txt filename from an allowed server/debug/chat prefix
/// @returns {Bool} Whether the name has no traversal component and only allowed characters
function scr_admin_logs_safe_name(name)
{
	/* Reject nonstrings before string operations, then require a 5-to-160-character .txt basename without '..' */
	if (!is_string(name) || string_length(name) < 5 || string_length(name) > 160
	|| string_pos("..", name) > 0 || string_lower(filename_ext(name)) != ".txt")
	{
		return false;
	}

	/* Allow only the game's server, debug and chat filename prefixes, preventing arbitrary filenames from becoming download targets */
	if (string_pos("Server_", name) != 1
	&& string_pos("JonnilOnline_DebugLog_", name) != 1
	&& string_pos("JonnilOnline_ChatLog_", name) != 1)
	{
		return false;
	}

	/* Check each one-based filename character against the ASCII basename allowlist */
	for (var i = 1; i <= string_length(name); i++)
	{
		/* Reject separators and all other characters outside letters, digits, underscore, hyphen and dot */
		if (string_pos(string_char_at(name, i), "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.") == 0)
		{
			return false;
		}
	}
	return true;
}

/// @description Start a server log response with version, request ID, and message kind
/// @param {Struct} net Shared packet writer
/// @param {Real} request_id Nonzero transfer request ID
/// @param {Real} kind ADMIN_LOG message kind
function scr_admin_logs_packet(net, request_id, kind)
{
	net.start(N_ADMIN_LOGS, noone);
	net.write(buffer_u8, ADMIN_LOG_PROTOCOL_VERSION);
	net.write(buffer_u32, request_id);
	net.write(buffer_u8, kind);
}

/// @description Send a bounded WebSocket log-download error to the requesting slot
/// @param {Struct} server Authoritative server with socket-slot state
/// @param {Real} slot Validated requesting player slot
/// @param {Real} request_id Request ID echoed to the client
/// @param {String} message Error text truncated to 240 characters
function scr_admin_logs_server_error(server, slot, request_id, message)
{
	/* Use the shared writer to return a bounded error to this requesting slot's WebSocket */
	var net = scr_get_network();
	scr_admin_logs_packet(net, request_id, ADMIN_LOG_ERROR);
	net.write(buffer_string, string_copy(string(message), 1, 240));
	net.send(server.sockets[slot], false, TRANSPORT_WS);
}

/// @description Handle an authenticated log start, pull, or cancel request on the shared reader
/// @param {Struct} server Authoritative server that owns the single active transfer
/// @param {Real} raw_slot Socket-derived requesting player slot
function scr_admin_logs_server_receive(server, raw_slot)
{
	/* net is the primed shared reader, and slot validates the socket-derived player slot before array or authentication access */
	var net = scr_get_network();
	var slot = server.slot_from_value(raw_slot);

	/* Authentication is tied to the current socket and checked on every request */
	if (slot == noone || !server.admin_slot_is_authenticated(slot)
	|| scr_admin_logs_remaining(net) < 6)
	{
		return;
	}

	/* Read the six-byte request header: version selects the protocol, request_id correlates the transfer,
	and kind selects start, pull or cancellation handling */
	var version = net.read(buffer_u8);
	var request_id = net.read(buffer_u32);
	var kind = net.read(buffer_u8);

	/* Unsupported versions and zero request IDs cannot identify a supported transfer */
	if (version != ADMIN_LOG_PROTOCOL_VERSION || request_id == 0)
	{
		scr_admin_logs_server_error(server, slot, request_id, "Unsupported server log download request.");
		return;
	}

	/* One snapshot transfer owns the server cursor.
	Its slot and socket must still match on each pull */
	var transfer = server.admin_log_transfer;

	/* Expire the single transfer only after its 30-second current_time deadline has passed, allowing a later start to replace it */
	if (is_struct(transfer) && current_time > transfer.deadline)
	{
		server.admin_log_transfer = undefined;
		transfer = undefined;
	}

	/* Cancellation has no reply and releases the transfer only when the requesting slot and request ID own it */
	if (kind == ADMIN_LOG_CANCEL)
	{
		/* Check that a live transfer belongs to this slot and ID before clearing another client's state */
		if (is_struct(transfer) && transfer.slot == slot && transfer.request_id == request_id)
		{
			server.admin_log_transfer = undefined;
		}
		return;
	}

	/* Start requests build a fixed filename-and-size snapshot for paced sequential pulls */
	if (kind == ADMIN_LOG_START)
	{
		/* A start request has no body, so reject unexpected trailing bytes */
		if (scr_admin_logs_remaining(net) != 0) return;

		/* The server supports one active snapshot cursor, so a second request must wait for completion or expiry */
		if (is_struct(transfer))
		{
			scr_admin_logs_server_error(server, slot, request_id, "Another server log download is active. Try again after it finishes.");
			return;
		}

		/* The shared five-second current_time cooldown prevents repeated manifest creation */
		if (current_time < server.admin_log_next_start_at)
		{
			scr_admin_logs_server_error(server, slot, request_id, "Please wait a few seconds before requesting another log download.");
			return;
		}
		server.admin_log_next_start_at = current_time + 5000;

		/* Collect the bounded saved-game log manifest after advancing the start cooldown */
		var manifest = scr_server_logs_manifest();

		/* A manifest error uses its diagnostic, while an empty successful manifest reports that no saved logs are available */
		if (!manifest.ok || array_length(manifest.files) == 0)
		{
			scr_admin_logs_server_error(server, slot, request_id, manifest.ok ? "No saved game logs were found on this server." : manifest.message);
			return;
		}

		/* Bind this snapshot to its requesting slot, current socket and request ID.
		files fixes names and byte lengths now, leaving later appends outside this download.
		index/offset begin at the first file's first byte, deadline allows 30,000 ms of
		inactivity on current_time, and next_pull_at zero permits the first pull immediately */
		transfer = {
			slot: slot, socket: server.sockets[slot], request_id: request_id,
			files: manifest.files, index: 0, offset: 0,
			deadline: current_time + 30000, next_pull_at: 0
		};
		server.admin_log_transfer = transfer;
		scr_admin_logs_packet(net, request_id, ADMIN_LOG_MANIFEST);
		net.write(buffer_u16, array_length(manifest.files));
		net.write(buffer_u32, manifest.total_bytes);

		/* Serialize each snapshot entry's basename and byte size in the same zero-based order used by later pulls */
		for (var i = 0; i < array_length(manifest.files); i++)
		{
			net.write(buffer_string, manifest.files[i].name);
			net.write(buffer_u32, manifest.files[i].size);
		}

		/* A failed manifest send abandons the snapshot so it does not hold the single server cursor */
		if (net.send(transfer.socket, false, TRANSPORT_WS) < 0)
		{
			server.admin_log_transfer = undefined;
		}
		return;
	}

	/* A pull needs exactly a file index and byte offset, plus a live transfer bound to this slot, socket and request ID
	Check the transfer's struct type before reading its fields, preventing stale or unrelated requests from using its cursor */
	if (kind != ADMIN_LOG_PULL || scr_admin_logs_remaining(net) != 6
	|| !is_struct(transfer) || transfer.slot != slot
	|| transfer.socket != server.sockets[slot] || transfer.request_id != request_id)
	{
		scr_admin_logs_server_error(server, slot, request_id, "Log download expired or is invalid. Start a new download.");
		return;
	}

	/* file_index is the requested zero-based manifest entry, and offset is the requested byte position within that file */
	var file_index = net.read(buffer_u16);
	var offset = net.read(buffer_u32);

	/* Only the exact next snapshot cursor is accepted, so retries or jumps cannot duplicate or skip bytes */
	if (file_index != transfer.index || offset != transfer.offset)
	{
		server.admin_log_transfer = undefined;
		scr_admin_logs_server_error(server, slot, request_id, "Log download offset did not match the snapshot.");
		return;
	}

	/* Pulls arriving before the pacing deadline receive WAIT and leave the snapshot cursor unchanged */
	if (current_time < transfer.next_pull_at)
	{
		scr_admin_logs_packet(net, request_id, ADMIN_LOG_WAIT);
		net.send(transfer.socket, false, TRANSPORT_WS);
		return;
	}

	/* file is the current snapshot entry, and handle starts at -1 until this operation opens its binary reader */
	var file = transfer.files[file_index];
	var handle = -1;
	try
	{
		/* A deleted snapshot source cannot be delivered, so enter the common transfer-error cleanup */
		if (!file_exists(file.path)) throw "A saved game log is no longer available.";
		handle = file_bin_open(file.path, 0);

		/* Verify a usable handle before reading its size, and reject a source shorter than the snapshotted length */
		if (handle < 0 || file_bin_size(handle) < file.size)
		{
			throw "A saved server log changed or became unavailable. Start a new download.";
		}
		file_bin_seek(handle, offset);

		/* Read at most one 4096-byte chunk without passing the snapshot's original byte length */
		var length = min(ADMIN_LOG_CHUNK_BYTES, file.size - offset);
		scr_admin_logs_packet(net, request_id, ADMIN_LOG_CHUNK);
		net.write(buffer_u16, file_index);
		net.write(buffer_u32, offset);
		net.write(buffer_u16, length);

		/* Copy exactly length bytes from the file into the packet, with i indexing bytes within this chunk */
		for (var i = 0; i < length; i++)
		{
			net.write(buffer_u8, file_bin_read_byte(handle));
		}

		/* Record the close result and clear the handle sentinel so later cleanup cannot close it twice */
		var closed = file_bin_close(handle);
		handle = -1;

		/* A reported close failure aborts delivery before the snapshot cursor advances */
		if (!closed) throw "Could not read the saved game log.";

		/* A failed chunk send enters cleanup and releases the transfer instead of advancing its cursor */
		if (net.send(transfer.socket, false, TRANSPORT_WS) < 0)
		{
			throw "Could not send the server log data.";
		}
		transfer.offset += length;
		transfer.next_pull_at = current_time + 40;
		transfer.deadline = current_time + 30000;

		/* Reaching the snapshotted file length advances to the next manifest entry and resets its byte offset */
		if (transfer.offset == file.size)
		{
			transfer.index++;
			transfer.offset = 0;

			/* After the final file, release the server's transfer cursor */
			if (transfer.index == array_length(transfer.files))
			{
				server.admin_log_transfer = undefined;
			}
		}
	}

	/* Read, close or send failures release any open handle, clear the transfer and return a bounded restart error */
	catch(e)
	{
		/* Close the reader only when failure occurred before its successful close */
		if (handle >= 0) file_bin_close(handle);
		server.admin_log_transfer = undefined;
		scr_admin_logs_server_error(server, slot, request_id, "Could not read or send a saved game log. Start a new download.");
	}
}

/// @description Create the desktop client log-download state machine and local-file writer
/// @param {Struct} client Owning client session supplying authentication, socket, and request IDs
function scr_admin_log_download(client) constructor
{
	/* owner supplies the session's authentication, socket and request IDs
	available excludes browser runtimes, while active and complete start false until a transfer is requested */
	owner = client;
	available = !scr_get_network().is_browser_runtime();
	active = false;
	complete = false;

	/* folder starts empty until a validated manifest creates a destination
	message explains desktop availability using available, and request_id zero means no transfer has been started */
	folder = "";
	message = available ? "Saved game chat and debug logs. System service logs are separate." : "Download server logs using the desktop game.";
	request_id = 0;

	/* files holds validated manifest entries, file_index selects the current entry, and offset tracks its received bytes
	total is the promised snapshot byte count and received counts bytes written across files, all starting at zero */
	files = [];
	file_index = 0;
	offset = 0;
	total = 0;
	received = 0;

	/* waiting tracks an outstanding manifest or chunk reply
	The current_time deadline and next_pull_at start at zero until a request schedules them
	manifest_received starts false and becomes true only after validation and local manifest creation */
	waiting = false;
	deadline = 0;
	next_pull_at = 0;
	manifest_received = false;

	/// @description Send the transfer request. Pull bodies add file index:u16 then byte offset:u32
	/// @param {Real} kind ADMIN_LOG_START, ADMIN_LOG_PULL, or ADMIN_LOG_CANCEL
	/// @returns {Bool} Whether the request was sent
	send = function(kind)
	{
		/* Use the shared writer with the owner's player ID and this transfer's request ID */
		var net = scr_get_network();
		net.start(N_ADMIN_LOGS, owner.ID);
		net.write(buffer_u8, ADMIN_LOG_PROTOCOL_VERSION);
		net.write(buffer_u32, request_id);
		net.write(buffer_u8, kind);

		/* Only pull requests include the current zero-based file index and byte offset */
		if (kind == ADMIN_LOG_PULL)
		{
			net.write(buffer_u16, file_index);
			net.write(buffer_u32, offset);
		}

		/* A nonnegative send result means this request was accepted for sending, without confirming a server reply */
		return net.send_server() >= 0;
	}

	/// @description Stop the transfer and retain incomplete files for inspection
	/// @param {String} reason Operation reason used in logs or lifecycle packets
	/// @param {Bool} notify_server Whether to notify the authenticated server before cleanup, defaulting to true
	fail = function(reason, notify_server = true)
	{
		/* Notify cancellation only for a live transfer whose owner still has authentication and a usable socket */
		if (active && notify_server && owner.admin_authenticated && owner.socket >= 0)
		{
			send(ADMIN_LOG_CANCEL);
		}
		active = false;
		complete = false;
		waiting = false;
		files = [];

		/* Retain the failure reason and add incomplete-file advice only when a local destination folder exists */
		message = string(reason) + (folder != "" ? " Incomplete files remain in the download folder." : "");
	}

	/// @description Cancel an active server log download through the common failure cleanup
	cancel = function()
	{
		/* Cancel only an active transfer, preserving the current feedback when there is nothing to stop */
		if (active) fail("Server log download cancelled.");
	}

	/// @description Start an authenticated desktop WebSocket download and wait for its manifest
	/// @returns {Bool} Whether the initial request was sent
	start = function()
	{
		/* A download needs desktop support, no active transfer, admin eligibility/authentication, WebSocket transport,
		an assigned player ID and a usable socket before changing any state */
		if (!available || active || !owner.admin_eligible || !owner.admin_authenticated
		|| owner.transport != TRANSPORT_WS || owner.ID == noone || owner.socket < 0)
		{
			return false;
		}
		request_id = owner.next_admin_request_id();
		active = true;
		complete = false;
		folder = "";
		files = [];
		file_index = 0;
		offset = 0;
		total = 0;
		received = 0;
		manifest_received = false;
		waiting = true;
		deadline = current_time + 15000;
		message = "Requesting saved game logs from the official server...";

		/* If the initial request cannot be sent, run local failure cleanup without notifying a server that received no start */
		if (!send(ADMIN_LOG_START))
		{
			fail("Could not request server logs.", false);
			return false;
		}
		return true;
	}

	/// @description Request the completed or partial download folder through the folder-opening UI
	/// @returns {Real} FolderOpenResult from scr_open_folder, or Disabled without a download folder
	open_folder = function()
	{
		/* A known destination can be opened even after an incomplete transfer
		Without one, return Disabled instead of launching a file manager */
		if (folder != "") return scr_open_folder(folder, "Official Server Logs");
		return FolderOpenResult.Disabled;
	}

	/// @description Advance permission, reply deadline, and paced chunk-pull state while connected
	tick = function()
	{
		/* Inactive transfers need no authentication, timeout or pacing updates */
		if (!active) return;

		/* Lost authentication, player ID or socket interrupts the download without attempting a cancellation on that session */
		if (!owner.admin_authenticated || owner.ID == noone || owner.socket < 0)
		{
			fail("Server log download interrupted by disconnect or lost permission.", false);
			return;
		}

		/* The current_time reply deadline distinguishes a missing initial manifest from a timeout during an established transfer */
		if (current_time >= deadline)
		{
			fail(manifest_received ? "Server log download timed out." : "The server did not answer the log request. It may need the newer server build.");
			return;
		}

		/* Request the next chunk only after the manifest exists, no reply is outstanding and the local pacing deadline is reached */
		if (manifest_received && !waiting && current_time >= next_pull_at)
		{
			waiting = true;

			/* A failed pull enters the common failure path rather than leaving waiting true indefinitely */
			if (!send(ADMIN_LOG_PULL)) fail("Could not request the next log chunk.");
		}
	}

	/// @description Validate response order and byte counts before writing .part files and final completion markers
	receive = function()
	{
		/* Read responses from the primed shared network reader */
		var net = scr_get_network();

		/* Ignore packets outside an active authenticated eligible WebSocket download or shorter than the six-byte header */
		if (!active || !owner.admin_authenticated || !owner.admin_eligible
		|| owner.transport != TRANSPORT_WS || scr_admin_logs_remaining(net) < 6) return;

		/* version selects the reply format, response_id correlates it to this transfer,
		and kind identifies the server's manifest, chunk, wait or error response */
		var version = net.read(buffer_u8);
		var response_id = net.read(buffer_u32);
		var kind = net.read(buffer_u8);

		/* Ignore replies for another request without changing this transfer's state */
		if (response_id != request_id) return;

		/* A matching request with an unsupported version ends the transfer with a protocol error */
		if (version != ADMIN_LOG_PROTOCOL_VERSION)
		{
			fail("The server log download protocol is not supported.");
			return;
		}

		/* handle and text_handle start at -1 and track owned binary/log-marker files for cleanup after exceptions */
		var handle = -1;
		var text_handle = -1;
		try
		{
			/* Server errors end the transfer locally without sending cancellation back */
			if (kind == ADMIN_LOG_ERROR)
			{
				/* Read a bounded error string, using a generic diagnostic if no safe terminator was found */
				var reason = scr_admin_logs_read_string(net, 960);
				fail(is_undefined(reason) ? "Invalid server log error response." : reason, false);
				return;
			}

			/* An awaited chunk may be paced by WAIT, which clears waiting and delays the next pull by 100 milliseconds */
			if (kind == ADMIN_LOG_WAIT && manifest_received && waiting)
			{
				waiting = false;
				next_pull_at = current_time + 100;
				return;
			}

			/* Accept the manifest only as the first awaited response, preventing a second manifest from replacing an established download */
			if (kind == ADMIN_LOG_MANIFEST && !manifest_received && waiting)
			{
				/* Require the file-count and total-byte fields before reading them */
				if (scr_admin_logs_remaining(net) < 6) throw "Incomplete manifest.";

				/* count is the promised manifest entry count, and total records the aggregate snapshot bytes */
				var count = net.read(buffer_u16);
				total = net.read(buffer_u32);

				/* Require at least one file and enforce the file-count and total-byte caps before allocating entries */
				if (count < 1 || count > ADMIN_LOG_MAX_FILES || total > ADMIN_LOG_MAX_TOTAL_BYTES) throw "Invalid manifest size.";

				/* Accumulate declared file bytes from zero to verify the aggregate manifest total */
				var sum = 0;

				/* Validate each zero-based manifest entry before using its basename as a local filename */
				for (var i = 0; i < count; i++)
				{
					/* Read a bounded filename that must pass the saved-game-log basename allowlist */
					var name = scr_admin_logs_read_string(net, 160);

					/* Reject unsafe or missing names and truncated size fields before consuming a declared file length */
					if (!scr_admin_logs_safe_name(name) || scr_admin_logs_remaining(net) < 4) throw "Invalid log filename.";

					/* The entry's size is its snapshotted byte length, including zero-byte files */
					var size = net.read(buffer_u32);

					/* Enforce the per-file byte cap before storing the entry */
					if (size > ADMIN_LOG_MAX_FILE_BYTES) throw "Log file is too large.";

					/* Compare the new name with every previously accepted entry using zero-based j */
					for (var j = 0; j < array_length(files); j++)
					{
						/* Reject case-insensitive duplicates so files cannot collide on platforms with case-insensitive filenames */
						if (string_lower(files[j].name) == string_lower(name)) throw "Duplicate log filename.";
					}

					/* Store only the validated basename and byte size, then add its size to the manifest sum */
					files[i] = {name: name, size: size};
					sum += size;
				}

				/* Require an exact aggregate total and no trailing manifest bytes before preparing any local download files */
				if (sum != total || scr_admin_logs_remaining(net) != 0) throw "Manifest total did not match.";

				/* A missing writable debug-export root prevents creating a reliable download destination */
				if (!scr_debug_export_ensure_folder(false)) throw "Could not create the local debug logs folder.";

				/* base is the official_server subdirectory under debug exports */
				var base = scr_debug_export_path_join(scr_debug_export_folder_path(), "official_server");

				/* Create the shared server-download parent only when absent */
				if (!directory_exists(base)) directory_create(base);

				/* stem combines the local export timestamp and request ID for this transfer's directory name */
				var stem = scr_debug_export_timestamp() + "_" + string(request_id);
				folder = scr_debug_export_path_join(base, stem);

				/* Start collision suffixes at one, leaving the unsuffixed stem as the first destination candidate */
				var suffix = 1;

				/* Advance the suffix while a destination already exists so a new transfer preserves earlier downloads */
				while (directory_exists(folder))
				{
					folder = scr_debug_export_path_join(base, stem + "_" + string(suffix++));
				}
				directory_create(folder);

				/* Confirm the unique destination was created before writing its manifest */
				if (!directory_exists(folder)) throw "Could not create the download folder.";
				text_handle = file_text_open_write(scr_debug_export_path_join(folder, "manifest.txt"));

				/* A failed text-file open cannot record the promised snapshot, so enter failure cleanup */
				if (text_handle < 0) throw "Could not write the download manifest.";
				scr_debug_export_write_line(text_handle, "Official server saved game logs (snapshot at download start)");
				scr_debug_export_write_line(text_handle, "Source: online.jonnil.games; system journal is not included.");
				scr_debug_export_write_line(text_handle, "Only a COMPLETED.txt marker confirms the entire download finished.");

				/* Write each validated entry's name and byte length into the local manifest for later inspection */
				for (var i = 0; i < count; i++) scr_debug_export_write_line(text_handle, files[i].name + "\t" + string(files[i].size) + " bytes");

				/* Retain the manifest close result, then clear its handle sentinel to avoid a duplicate close */
				var text_closed = file_text_close(text_handle);
				text_handle = -1;

				/* Do not treat the manifest as ready when its close reports failure */
				if (!text_closed) throw "Could not save the download manifest.";
				manifest_received = true;
			}

			/* After the manifest, only an awaited chunk may advance the binary file cursor */
			else if (kind == ADMIN_LOG_CHUNK && manifest_received && waiting)
			{
				/* Require the chunk's index, offset and length header before reading its fields */
				if (scr_admin_logs_remaining(net) < 8) throw "Incomplete chunk.";

				/* response_index and response_offset must match the next expected file and byte position
				length is this chunk's byte count, and file is that validated snapshot entry */
				var response_index = net.read(buffer_u16);
				var response_offset = net.read(buffer_u32);
				var length = net.read(buffer_u16);
				var file = files[file_index];

				/* Require exact cursor order, the bounded expected chunk length and exactly that many remaining packet bytes */
				if (response_index != file_index || response_offset != offset
				|| length > ADMIN_LOG_CHUNK_BYTES || length != min(ADMIN_LOG_CHUNK_BYTES, file.size - offset)
				|| scr_admin_logs_remaining(net) != length) throw "Invalid log chunk offset or length.";

				/* target is the final validated filename, while partial adds '.part' until the complete file size is verified */
				var target = scr_debug_export_path_join(folder, file.name);
				var partial = target + ".part";

				/* The first chunk opens in write mode, while later chunks open the existing partial file for update */
				handle = file_bin_open(partial, offset == 0 ? 1 : 2);

				/* A failed binary open cannot receive this chunk */
				if (handle < 0) throw "Could not write a downloaded log.";

				/* Rewrite the partial file only for the first chunk so old bytes cannot survive a fresh transfer */
				if (offset == 0) file_bin_rewrite(handle);

				/* Require the local partial file to match the expected cursor before appending */
				if (file_bin_size(handle) != offset) throw "Downloaded log size changed.";
				file_bin_seek(handle, offset);

				/* Write the validated chunk's bytes in order, with i indexing bytes in this packet */
				for (var i = 0; i < length; i++) file_bin_write_byte(handle, buffer_read(net.reader_buffer, buffer_u8));

				/* Verify that the binary writer advanced by the entire chunk length */
				if (file_bin_position(handle) != offset + length) throw "Could not save the entire log chunk.";

				/* Capture this chunk file's close result and clear handle before any later checks throw */
				var closed = file_bin_close(handle);
				handle = -1;

				/* A reported close failure prevents this chunk from advancing the received counters */
				if (!closed) throw "Could not save the downloaded log chunk.";
				offset += length;
				received += length;

				/* At the snapshot's full byte length, reopen and verify the partial file before giving it its final name */
				if (offset == file.size)
				{
					handle = file_bin_open(partial, 0);

					/* Check the verification handle first, then require the saved file size to equal the manifest length */
					if (handle < 0 || file_bin_size(handle) != file.size) throw "Saved log size did not match the server snapshot.";

					/* Keep the verification close result and clear the handle sentinel */
					var verified_close = file_bin_close(handle);
					handle = -1;

					/* A failed verification close stops promotion of the partial file */
					if (!verified_close) throw "Could not verify the saved log.";
					file_rename(partial, target);

					/* Confirm the final filename exists after renaming before advancing to the next manifest entry */
					if (!file_exists(target)) throw "Could not finish the downloaded log file.";
					file_index++;
					offset = 0;
				}

				/* After every file is received and promoted, write and promote the completion marker */
				if (file_index == array_length(files))
				{
					/* Only the final COMPLETED.txt marker confirms every snapshot file was received
					and renamed successfully. Its .part file stays provisional until closed */
					var completion_path = scr_debug_export_path_join(folder, "COMPLETED.txt");
					text_handle = file_text_open_write(completion_path + ".part");

					/* A failed marker open leaves the download incomplete even when all log files are present */
					if (text_handle < 0) throw "Could not record download completion.";
					scr_debug_export_write_line(text_handle, "Downloaded " + string(file_index) + " game log files, " + string(received) + " bytes at " + scr_debug_export_timestamp());

					/* Retain the marker close result, then clear its text handle for safe exception cleanup */
					var completion_closed = file_text_close(text_handle);
					text_handle = -1;

					/* Do not promote a completion marker whose close reports failure */
					if (!completion_closed) throw "Could not save the download completion marker.";
					file_rename(completion_path + ".part", completion_path);

					/* Confirm marker promotion before publishing complete true to the UI */
					if (!file_exists(completion_path)) throw "Could not finish the download completion marker.";
					active = false;
					complete = true;
					files = [];
					message = "Downloaded " + string(file_index) + " server log files. Select Open Downloaded Logs to view them.";
					return;
				}
			}

			/* All other response kinds or sequencing combinations fail rather than silently advancing download state */
			else throw "Unexpected server log response.";
			waiting = false;
			deadline = current_time + 15000;
			next_pull_at = current_time + 50;
			message = "Downloading server logs: " + string(floor(received * 100 / max(1, total)))
				+ "% (" + string(file_index) + "/" + string(array_length(files)) + " files).";
		}

		/* Close any still-owned files and route the exception through the common failure state */
		catch(e)
		{
			/* Close a binary file only if an exception occurred while its handle was still owned */
			if (handle >= 0) file_bin_close(handle);

			/* Close a manifest or completion-marker file only if it remained open at the failure point */
			if (text_handle >= 0) file_text_close(text_handle);
			fail("Server log download failed: " + scr_debug_export_exception_text(e));
		}
	}
}
