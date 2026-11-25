#macro RgbaPng scr_get_rgba_png()

/// @description Convert row-major RRGGBBAA hex pixels to and from PNG files or base64
function scr_rgba_png() constructor
{
	/* Alpha bytes at or below 2 become transparent black during pixel extraction, unless a caller supplies another cutoff */
	alpha_cutoff_default = 2;

	#region /* Pixel and Path Helpers */
	/// @description Get the native directory separator
	/// @returns {String} Backslash on Windows, forward slash elsewhere
	path_separator = function()
	{
		/* Windows paths use backslashes, while other platforms use forward slashes */
		return os_type == os_windows ? "\\" : "/";
	}

	/// @description Convert both separator styles to the current platform's style
	/// @param {String} raw_path Path to normalize
	/// @returns {String} Normalized path
	normalize_path = function(raw_path)
	{
		/* Convert the supplied path to text before replacing its separators for the current platform */
		var path_text = string(raw_path);

		/* Windows replaces forward slashes, while the return below normalizes backslashes on other platforms */
		if (os_type == os_windows)
		{
			return string_replace_all(path_text, "/", "\\");
		}

		return string_replace_all(path_text, "\\", "/");
	}

	/// @description Join normalized paths with one separator at their boundary
	/// @param {String} base_path Base directory
	/// @param {String} leaf_path Leaf path
	/// @returns {String} Joined path. Does not remove a leading separator from the leaf
	path_join = function(base_path, leaf_path)
	{
		/* left is the normalized base directory and right is the normalized leaf path */
		var left = normalize_path(base_path);
		var right = normalize_path(leaf_path);

		/* An empty base leaves the leaf unchanged rather than adding a leading separator */
		if (left == "")
		{
			return right;
		}

		/* An empty leaf returns the base without appending a separator */
		if (right == "")
		{
			return left;
		}

		/* Inspect the base's final character to avoid inserting a second directory separator */
		var last_char = string_char_at(left, string_length(left));

		/* A base already ending in either separator joins directly to the leaf */
		if (last_char == "/" || last_char == "\\")
		{
			return left + right;
		}

		return left + path_separator() + right;
	}

	/// @description Convert a value to an integer byte
	/// @param {Real} raw_value Value to floor and clamp
	/// @returns {Real} Integer from 0 to 255
	clamp_byte = function(raw_value)
	{
		return clamp(floor(real(raw_value)), 0, 255);
	}

	/// @description Encode one clamped four-bit value
	/// @param {Real} value Value to floor and clamp
	/// @returns {String} One uppercase hex digit
	hex_digit = function(value)
	{
		return string_char_at("0123456789ABCDEF", clamp(floor(real(value)), 0, 15) + 1);
	}

	/// @description Encode a clamped byte
	/// @param {Real} raw_value Byte value
	/// @returns {String} Two uppercase hex digits
	byte_to_hex = function(raw_value)
	{
		/* Clamp the input to an integer byte, then encode its high and low four-bit halves as two uppercase hex digits */
		var byte_value = clamp_byte(raw_value);
		return hex_digit(floor(byte_value / 16)) + hex_digit(byte_value mod 16);
	}

	/// @description Decode a hex character with zero as the fallback
	/// @param {String} raw_char Hex character
	/// @returns {Real} Four-bit value, or zero for unrecognized text
	hex_value = function(raw_char)
	{
		/* The one-based lookup position maps to a four-bit value after subtracting one
		Unrecognized input falls back to zero rather than reporting a parse error */
		var digit_index = string_pos(string_upper(string(raw_char)), "0123456789ABCDEF");
		return max(0, digit_index - 1);
	}

	/// @description Decode two consecutive hex characters
	/// @param {String} hex_text Source hex text
	/// @param {Real} offset One-based position of the first character
	/// @returns {Real} Byte value. Invalid characters decode as zero
	hex_pair_to_byte = function(hex_text, offset)
	{
		return hex_value(string_char_at(hex_text, offset)) * 16 + hex_value(string_char_at(hex_text, offset + 1));
	}

	/// @description Pack clamped RGBA bytes for the Windows surface buffer
	/// @param {Real} raw_red Red byte
	/// @param {Real} raw_green Green byte
	/// @param {Real} raw_blue Blue byte
	/// @param {Real} raw_alpha Alpha byte
	/// @returns {Real} Packed value with red in the low byte and alpha in the high byte
	pack_rgba = function(raw_red, raw_green, raw_blue, raw_alpha)
	{
		return clamp_byte(raw_red)
			+ clamp_byte(raw_green) * 256
			+ clamp_byte(raw_blue) * 65536
			+ clamp_byte(raw_alpha) * 16777216;
	}

	/// @description Check that text is long enough for the requested pixel grid
	/// @param {String} hex_text Pixel text to measure
	/// @param {Real} raw_width Width, floored and clamped to at least one
	/// @param {Real} raw_height Height, floored and clamped to at least one
	/// @returns {Bool} Whether at least eight characters per pixel are present. Does not validate digits
	hex_is_valid_size = function(hex_text, raw_width, raw_height)
	{
		/* safe_w and safe_h are positive integer pixel dimensions used for the required text length */
		var safe_w = max(1, floor(real(raw_width)));
		var safe_h = max(1, floor(real(raw_height)));

		/* Each pixel needs eight RRGGBBAA characters, so reject short input
		This is a length check and does not validate individual hex digits or reject trailing pixels */
		return string_length(string(hex_text)) >= safe_w * safe_h * 8;
	}

	/// @description Prefix base64 bytes for use as a PNG data URL
	/// @param {String} base64_text Encoded PNG bytes
	/// @returns {String} PNG data URL
	data_url = function(base64_text)
	{
		return "data:image/png;base64," + string(base64_text);
	}

	/// @description Create an empty failure result for a PNG operation
	/// @param {String} message_text Initial message. Defaults to RGBA PNG operation failed.
	/// @returns {Struct} ok, hex, base64, byte_size, width, height and message
	make_result = function(message_text = "RGBA PNG operation failed.")
	{
		/* A result begins as failure with empty hex/base64 payloads, zero byte count and unknown zero dimensions
		message holds the caller's failure text until a successful operation clears it */
		return
		{
			ok: false,
			hex: "",
			base64: "",
			byte_size: 0,
			width: 0,
			height: 0,
			message: string(message_text)
		};
	}
	#endregion /* Pixel and Path Helpers END */

	#region /* PNG Encoding */
	/// @description Create a surface from eight hex characters per pixel, row by row
	/// @param {Real} raw_width Width in pixels
	/// @param {Real} raw_height Height in pixels
	/// @param {String} hex_text Row-major RRGGBBAA pixels
	/// @returns {Id.Surface} New surface owned by the caller, or noone on failure
	rgba_hex_to_surface = function(raw_width, raw_height, hex_text)
	{
		/* safe_w and safe_h clamp the requested pixel dimensions to positive integers */
		var safe_w = max(1, floor(real(raw_width)));
		var safe_h = max(1, floor(real(raw_height)));

		/* Do not allocate a surface when the input cannot provide all requested RGBA pixels */
		if (!hex_is_valid_size(hex_text, safe_w, safe_h))
		{
			return noone;
		}

		/* The new surface belongs to this operation until it is returned to the caller
		Failure paths free it after any later buffer allocation fails */
		var target_surface = surface_create(safe_w, safe_h);

		/* A failed surface allocation has no usable pixels, so return noone before setting a render target */
		if (!surface_exists(target_surface))
		{
			return noone;
		}

		/* Other platforms draw individual RGBA pixels to avoid relying on Windows surface-buffer channel ordering */
		if (os_type != os_windows)
		{
			/* Outside Windows, direct pixel drawing keeps channel order stable because
			buffer_set_surface uses platform-dependent ordering. Normalize the text once
			before per-pixel conversion and clear the surface to transparent black */
			var portable_hex = string_upper(string(hex_text));
			surface_set_target(target_surface);
			draw_clear_alpha(c_black, 0);
			gpu_set_blendmode_ext(bm_one, bm_zero);

			/* Walk zero-based rows from top to bottom, matching the input's row-major pixel order */
			for (var portable_row = 0; portable_row < safe_h; portable_row++)
			{
				/* Visit every zero-based column in the current row before advancing to the next row */
				for (var portable_col = 0; portable_col < safe_w; portable_col++)
				{
					/* portable_offset is the one-based text position of this pixel's red byte
					portable_alpha reads its fourth byte and controls the pixel's drawing opacity */
					var portable_offset = (portable_row * safe_w + portable_col) * 8 + 1;
					var portable_alpha = hex_pair_to_byte(portable_hex, portable_offset + 6);

					/* Fully transparent pixels keep the cleared surface value and need no draw call */
					if (portable_alpha <= 0)
					{
						continue;
					}

					draw_set_colour(make_color_rgb(
						hex_pair_to_byte(portable_hex, portable_offset),
						hex_pair_to_byte(portable_hex, portable_offset + 2),
						hex_pair_to_byte(portable_hex, portable_offset + 4)
					));
					draw_set_alpha(portable_alpha / 255);
					draw_point(portable_col, portable_row);
				}
			}
			gpu_set_blendmode(bm_normal);
			draw_set_alpha(1);
			draw_set_colour(c_white);
			surface_reset_target();
			return target_surface;
		}

		/* Windows stages four bytes per pixel in an owned fixed buffer, which is deleted after copying into the surface */
		var pixel_buffer = buffer_create(safe_w * safe_h * 4, buffer_fixed, 1);

		/* If staging allocation fails, release the already-created surface before returning failure */
		if (!buffer_exists(pixel_buffer))
		{
			surface_free(target_surface);
			return noone;
		}

		/* Uppercase the source text once for the Windows buffer conversion */
		var clean_hex = string_upper(string(hex_text));

		/* Write rows in input order using pixel_row as a zero-based row index */
		for (var pixel_row = 0; pixel_row < safe_h; pixel_row++)
		{
			/* Fill each row from left to right with zero-based pixel_col */
			for (var pixel_col = 0; pixel_col < safe_w; pixel_col++)
			{
				/* hex_offset locates the pixel's first RRGGBBAA character using one-based string positions
				pixel_value packs those four bytes with red in the low byte for the Windows surface transfer */
				var hex_offset = (pixel_row * safe_w + pixel_col) * 8 + 1;
				var pixel_value = pack_rgba(
					hex_pair_to_byte(clean_hex, hex_offset),
					hex_pair_to_byte(clean_hex, hex_offset + 2),
					hex_pair_to_byte(clean_hex, hex_offset + 4),
					hex_pair_to_byte(clean_hex, hex_offset + 6)
				);
				buffer_poke(pixel_buffer, (pixel_row * safe_w + pixel_col) * 4, buffer_u32, pixel_value);
			}
		}

		buffer_set_surface(pixel_buffer, target_surface, 0);
		buffer_delete(pixel_buffer);
		return target_surface;
	}

	/// @description Save RGBA pixels through an owned temporary surface
	/// @param {String} destination_path PNG destination
	/// @param {Real} raw_width Width in pixels
	/// @param {Real} raw_height Height in pixels
	/// @param {String} hex_text Row-major RRGGBBAA pixels
	/// @returns {Bool} Whether the destination exists after saving. Releases the temporary surface
	rgba_hex_to_png_file = function(destination_path, raw_width, raw_height, hex_text)
	{
		/* Create an owned temporary surface from the requested pixels, then free it after the save attempt */
		var target_surface = rgba_hex_to_surface(raw_width, raw_height, hex_text);

		/* Conversion failure leaves no surface to save, so report false immediately */
		if (!surface_exists(target_surface))
		{
			return false;
		}

		/* Start with failure and mark saved only when the destination exists after surface_save
		This checks file existence rather than verifying that an existing file was replaced successfully */
		var saved = false;
		try
		{
			surface_save(target_surface, destination_path);
			saved = file_exists(destination_path);
		}

		/* A thrown save error is logged and keeps the result false, while the shared cleanup still frees the surface */
		catch(e)
		{
			debug_error("Could not save RGBA PNG " + string(destination_path) + ": " + string(e.message));
			saved = false;
		}

		surface_free(target_surface);
		return saved;
	}

	/// @description Read file bytes as base64 without validating their PNG contents
	/// @param {String} file_path PNG file path
	/// @returns {Struct} Result with ok, base64, byte_size and message. Releases the loaded buffer
	read_png_base64 = function(file_path)
	{
		/* result carries the failure message or encoded bytes
		source_buffer starts as noone and becomes an owned file buffer that is released after reading */
		var result = make_result("Could not read PNG file.");
		var source_buffer = noone;
		try
		{
			source_buffer = buffer_load(file_path);

			/* Check the load result before querying its size, and return the failure result if no usable buffer exists */
			if (is_undefined(source_buffer) || !buffer_exists(source_buffer))
			{
				return result;
			}

			/* The loaded buffer size is the number of file bytes to encode, not a pixel count */
			var byte_size = buffer_get_size(source_buffer);

			/* An empty file cannot provide a useful PNG payload */
			if (byte_size <= 0)
			{
				result.message = "PNG file is empty.";
			}

			/* Encode a nonempty file and publish its byte size, without validating the PNG format here */
			else
			{
				result.base64 = buffer_base64_encode(source_buffer, 0, byte_size);
				result.byte_size = byte_size;
				result.ok = true;
				result.message = "";
			}
		}

		/* Expose a read or encoding exception through the result message instead of propagating it */
		catch(e)
		{
			result.message = "Could not read PNG file: " + string(e.message);
		}

		/* Release the loaded buffer if it still exists, including after a caught encoding error */
		if (!is_undefined(source_buffer) && buffer_exists(source_buffer))
		{
			buffer_delete(source_buffer);
		}

		return result;
	}

	/// @description Encode through a temporary native PNG file and read its bytes
	/// @param {Real} raw_width Width in pixels
	/// @param {Real} raw_height Height in pixels
	/// @param {String} hex_text Row-major RRGGBBAA pixels
	/// @returns {Struct} Encoding result. Attempts to delete the temporary file
	rgba_hex_to_png_base64_desktop = function(raw_width, raw_height, hex_text)
	{
		/* result begins as failure, and safe_w/safe_h are positive integer pixel dimensions
		temp_path identifies this operation's intermediate PNG using current_time milliseconds and a random suffix */
		var result = make_result("Could not encode RGBA PNG.");
		var safe_w = max(1, floor(real(raw_width)));
		var safe_h = max(1, floor(real(raw_height)));
		var temp_path = path_join(temp_directory, "JonnilOnline_RGBA_" + string(current_time) + "_" + string(irandom(999999)) + ".png");

		/* A failed intermediate save ends encoding before attempting to read a nonexistent PNG */
		if (!rgba_hex_to_png_file(temp_path, safe_w, safe_h, hex_text))
		{
			return result;
		}

		result = read_png_base64(temp_path);

		/* Remove the temporary PNG after reading it when it exists
		Deletion errors are intentionally ignored so they do not replace the encoding result */
		if (file_exists(temp_path))
		{
			try { file_delete(temp_path); } catch(delete_error) {}
		}

		result.width = safe_w;
		result.height = safe_h;
		return result;
	}

	/// @description Encode pixels through the browser bridge with its legacy alias as fallback
	/// @param {Real} raw_width Width in pixels
	/// @param {Real} raw_height Height in pixels
	/// @param {String} hex_text Row-major RRGGBBAA pixels
	/// @returns {Struct} Result with ok, base64, dimensions and message
	rgba_hex_to_png_base64_browser = function(raw_width, raw_height, hex_text)
	{
		/* result starts with the browser failure message, while safe_w and safe_h normalize the requested dimensions */
		var result = make_result("Could not encode browser RGBA PNG.");
		var safe_w = max(1, floor(real(raw_width)));
		var safe_h = max(1, floor(real(raw_height)));
		try
		{
			/* Keep the browser bridge's return text here, starting empty until an encoding call succeeds */
			var base64_text = "";
			try
			{
				base64_text = html5_rgba_hex_to_png_base64(safe_w, safe_h, hex_text);
			}

			/* If the newer bridge entry point throws, try the older stamp-named encoder for compatibility */
			catch(alias_error)
			{
				base64_text = html5_stamp_rgba_hex_to_png_base64(safe_w, safe_h, hex_text);
			}

			/* An empty bridge response provides no PNG bytes, so retain failure and try to obtain the bridge's diagnostic */
			if (string_trim(string(base64_text)) == "")
			{
				/* Start without a bridge diagnostic, and ignore errors while reading the optional last-error entry point
				Use its text only when nonempty, otherwise keep the original operation message */
				var error_text = "";
				try { error_text = html5_stamp_last_error(); } catch(error_read) {}
				result.message = string_trim(error_text) == "" ? result.message : error_text;
				return result;
			}

			result.ok = true;
			result.base64 = base64_text;
			result.width = safe_w;
			result.height = safe_h;
			result.message = "";
		}

		/* Report a bridge exception in the result without throwing it into the editor or export caller */
		catch(e)
		{
			result.message = "Could not encode browser RGBA PNG: " + string(e.message);
		}

		return result;
	}

	/// @description Encode RGBA pixels using the browser bridge or a temporary desktop PNG
	/// @param {Real} raw_width Width in pixels
	/// @param {Real} raw_height Height in pixels
	/// @param {String} hex_text Row-major RRGGBBAA pixels
	/// @returns {Struct} Result with ok, base64, dimensions and message
	rgba_hex_to_png_base64 = function(raw_width, raw_height, hex_text)
	{
		/* Browser and GX builds use the JavaScript encoder, while native builds encode through a temporary PNG file */
		if (os_browser != browser_not_a_browser || os_type == os_gxgames)
		{
			return rgba_hex_to_png_base64_browser(raw_width, raw_height, hex_text);
		}

		return rgba_hex_to_png_base64_desktop(raw_width, raw_height, hex_text);
	}
	#endregion /* PNG Encoding END */

	#region /* Surface Pixel Sampling */
	/* Windows reads from the start of the surface buffer. Supply an origin-aligned
	cropped surface of the requested size, as sprite_region_to_rgba_hex does.
	Other platforms sample source_x and source_y directly */
	/// @description Read a surface region as row-major RGBA hex. Windows requires an origin-aligned crop
	/// @param {Id.Surface} source_surface Surface to sample
	/// @param {Real} source_x Region's left edge. Ignored by the Windows buffer path
	/// @param {Real} source_y Region's top edge. Ignored by the Windows buffer path
	/// @param {Real} raw_width Region width in pixels
	/// @param {Real} raw_height Region height in pixels
	/// @param {Real} alpha_cutoff Byte threshold for transparent black. Defaults to alpha_cutoff_default (2)
	/// @returns {Struct} Result with ok, hex, dimensions and message. Leaves the source surface owned by its caller
	surface_region_to_rgba_hex = function(source_surface, source_x, source_y, raw_width, raw_height, alpha_cutoff = alpha_cutoff_default)
	{
		/* result holds sampled pixels or a failure message, and safe_w/safe_h normalize the requested region dimensions */
		var result = make_result("Could not read RGBA pixels.");
		var safe_w = max(1, floor(real(raw_width)));
		var safe_h = max(1, floor(real(raw_height)));

		/* A missing source cannot be sampled, so return a descriptive failure before allocating readback storage */
		if (!surface_exists(source_surface))
		{
			result.message = "Source surface is missing.";
			return result;
		}

		/* sample_buffer starts unallocated and is owned only by the Windows readback path */
		var sample_buffer = noone;

		/* Windows reads a four-byte-per-pixel surface buffer, while other platforms sample the requested coordinates directly */
		if (os_type == os_windows)
		{
			sample_buffer = buffer_create(safe_w * safe_h * 4, buffer_fixed, 1);

			/* A failed readback allocation returns failure before attempting to copy surface data */
			if (!buffer_exists(sample_buffer))
			{
				result.message = "Could not create RGBA pixel buffer.";
				return result;
			}

			buffer_get_surface(sample_buffer, source_surface, 0);
		}

		/* safe_alpha_cutoff bounds the transparency threshold to an integer byte
		hex_text accumulates the row-major RRGGBBAA result, starting empty */
		var safe_alpha_cutoff = clamp(floor(real(alpha_cutoff)), 0, 255);
		var hex_text = "";

		/* Traverse the requested region's zero-based rows to preserve row-major serialization */
		for (var pixel_row = 0; pixel_row < safe_h; pixel_row++)
		{
			/* Sample every zero-based column within the current row */
			for (var pixel_col = 0; pixel_col < safe_w; pixel_col++)
			{
				/* buffer_get_surface byte ordering can vary by platform. On Windows, sampled_pixel
				comes from the origin-aligned buffer. Other platforms use surface_getpixel_ext
				at source_x/source_y plus column/row for stable packed ABGR. sampled_alpha
				extracts its high byte as zero-to-255 opacity */
				var sampled_pixel = os_type == os_windows
					? buffer_peek(sample_buffer, (pixel_row * safe_w + pixel_col) * 4, buffer_u32)
					: surface_getpixel_ext(source_surface, source_x + pixel_col, source_y + pixel_row);
				var sampled_alpha = (sampled_pixel >> 24) & 255;

				/* Pixels at or below the cutoff serialize as transparent black, removing hidden RGB values */
				if (sampled_alpha <= safe_alpha_cutoff)
				{
					hex_text += "00000000";
				}

				/* Visible pixels preserve the sampled red, green, blue and alpha bytes in that order */
				else
				{
					hex_text += byte_to_hex(colour_get_red(sampled_pixel))
						+ byte_to_hex(colour_get_green(sampled_pixel))
						+ byte_to_hex(colour_get_blue(sampled_pixel))
						+ byte_to_hex(sampled_alpha);
				}
			}
		}

		/* Release Windows readback storage after sampling, while the noone sentinel needs no cleanup on other platforms */
		if (buffer_exists(sample_buffer))
		{
			buffer_delete(sample_buffer);
		}
		result.ok = true;
		result.hex = hex_text;
		result.width = safe_w;
		result.height = safe_h;
		result.message = "";
		return result;
	}

	/// @description Draw a sprite crop into an owned surface, then read its RGBA pixels
	/// @param {Asset.GMSprite} source_sprite Sprite to crop at subimage zero
	/// @param {Real} source_x Crop's left edge in pixels
	/// @param {Real} source_y Crop's top edge in pixels
	/// @param {Real} raw_width Crop width in pixels
	/// @param {Real} raw_height Crop height in pixels
	/// @param {Real} alpha_cutoff Byte threshold. Defaults to alpha_cutoff_default (2)
	/// @returns {Struct} Pixel result. Frees the crop surface and restores texture filtering, with normal blending
	sprite_region_to_rgba_hex = function(source_sprite, source_x, source_y, raw_width, raw_height, alpha_cutoff = alpha_cutoff_default)
	{
		/* result carries the extracted pixel data or failure, and safe_w/safe_h normalize the crop dimensions */
		var result = make_result("Could not read sprite RGBA pixels.");
		var safe_w = max(1, floor(real(raw_width)));
		var safe_h = max(1, floor(real(raw_height)));

		/* Reject missing sprite assets before creating the crop surface */
		if (!sprite_exists(source_sprite))
		{
			result.message = "Source sprite is missing.";
			return result;
		}

		/* This operation owns a crop surface with the requested region aligned to its top-left origin */
		var sample_surface = surface_create(safe_w, safe_h);

		/* Allocation failure prevents drawing the crop and returns a descriptive result */
		if (!surface_exists(sample_surface))
		{
			result.message = "Could not create RGBA sample surface.";
			return result;
		}

		/* Save the caller's texture-filter setting so exact pixel sampling can disable interpolation temporarily */
		var restore_filter = gpu_get_texfilter();
		gpu_set_texfilter(false);
		surface_set_target(sample_surface);
		draw_set_alpha(1);
		draw_clear_alpha(c_black, 0);
		gpu_set_blendmode_ext(bm_one, bm_zero);
		draw_sprite_part_ext(
			source_sprite,
			0,
			floor(real(source_x)),
			floor(real(source_y)),
			safe_w,
			safe_h,
			0,
			0,
			1,
			1,
			c_white,
			1
		);
		gpu_set_blendmode(bm_normal);
		surface_reset_target();
		gpu_set_texfilter(restore_filter);

		result = surface_region_to_rgba_hex(sample_surface, 0, 0, safe_w, safe_h, alpha_cutoff);
		surface_free(sample_surface);
		return result;
	}
	#endregion /* Surface Pixel Sampling END */

	/// @description Decode an exact-size PNG through the browser bridge
	/// @param {String} base64_text PNG base64 bytes
	/// @param {Real} expected_w Required pixel width
	/// @param {Real} expected_h Required pixel height
	/// @param {Real} alpha_cutoff Byte threshold. Defaults to alpha_cutoff_default (2)
	/// @returns {Struct} Result with ok, hex, dimensions and message
	png_base64_to_rgba_hex_browser = function(base64_text, expected_w, expected_h, alpha_cutoff = alpha_cutoff_default)
	{
		/* result starts as failure, safe_w/safe_h are the required integer PNG dimensions,
		and safe_alpha_cutoff is the integer-byte threshold passed to the decoder */
		var result = make_result("Could not decode browser PNG base64.");
		var safe_w = max(1, floor(real(expected_w)));
		var safe_h = max(1, floor(real(expected_h)));
		var safe_alpha_cutoff = clamp(floor(real(alpha_cutoff)), 0, 255);
		try
		{
			/* Store the browser decoder's row-major RGBA text before checking that it contains the required pixel count */
			var hex_text = html5_png_base64_to_rgba_hex(base64_text, safe_w, safe_h, safe_alpha_cutoff);

			/* A short response cannot represent the expected dimensions, so obtain bridge diagnostics and keep the failure result */
			if (!hex_is_valid_size(hex_text, safe_w, safe_h))
			{
				/* An empty diagnostic preserves the original failure message
				Errors from the optional last-error entry point are ignored so the decode result remains available */
				var error_text = "";
				try { error_text = html5_stamp_last_error(); } catch(error_read) {}
				result.message = string_trim(error_text) == "" ? result.message : error_text;
				return result;
			}

			result.ok = true;
			result.hex = hex_text;
			result.width = safe_w;
			result.height = safe_h;
			result.message = "";
		}

		/* Return thrown bridge errors in the message field instead of propagating them */
		catch(e)
		{
			result.message = "Could not decode browser PNG base64: " + string(e.message);
		}

		return result;
	}

	/// @description Decode a PNG of the expected size to row-major RRGGBBAA pixels
	/// @param {String} base64_text PNG bytes encoded as base64, without a data URL prefix
	/// @param {Real} expected_w Required width in pixels
	/// @param {Real} expected_h Required height in pixels
	/// @param {Real} alpha_cutoff Alpha bytes at or below this value become transparent black. Defaults to alpha_cutoff_default, initially 2
	/// @returns {Struct} Result with ok, hex, dimensions and message
	png_base64_to_rgba_hex = function(base64_text, expected_w, expected_h, alpha_cutoff = alpha_cutoff_default)
	{
		/* Browser and GX builds decode through the JavaScript bridge, while native builds use a temporary local PNG */
		if (os_browser != browser_not_a_browser || os_type == os_gxgames)
		{
			return png_base64_to_rgba_hex_browser(base64_text, expected_w, expected_h, alpha_cutoff);
		}

		/* result starts as failure, source_buffer/source_sprite begin as unallocated owned resources,
		and temp_path names this operation's intermediate file using current_time milliseconds plus a random suffix */
		var result = make_result("Could not decode PNG base64.");
		var source_buffer = noone;
		var source_sprite = noone;
		var temp_path = path_join(temp_directory, "jonnilonline_png_decode_" + string(current_time) + "_" + string(irandom(999999)) + ".png");
		try
		{
			source_buffer = buffer_base64_decode(string(base64_text));

			/* A missing decoded buffer produces a failure message without attempting file output */
			if (is_undefined(source_buffer) || !buffer_exists(source_buffer))
			{
				result.message = "Could not decode PNG base64 buffer.";
			}

			/* With decoded bytes available, save them to a local path for synchronous native sprite loading */
			else
			{
				buffer_save(source_buffer, temp_path);

				/* If the intermediate file is absent, skip sprite creation and report preparation failure */
				if (!file_exists(temp_path))
				{
					result.message = "Could not prepare PNG for pixel decoding.";
				}

				/* An existing intermediate file can be passed to the native sprite loader */
				else
				{
					/* A local path loads synchronously on desktop. Sampling a data URL before
					its sprite finished loading caused transparent Linux stamps */
					source_sprite = sprite_add(temp_path, 1, false, false, 0, 0);

					/* A failed sprite load cannot provide pixels and keeps the result in failure */
					if (!sprite_exists(source_sprite))
					{
						result.message = "Could not create PNG sprite.";
					}

					/* A loaded sprite must still match the caller's expected dimensions before its pixels are accepted */
					else
					{
						/* safe_w and safe_h normalize the expected width and height to positive integer pixel counts */
						var safe_w = max(1, floor(real(expected_w)));
						var safe_h = max(1, floor(real(expected_h)));

						/* Reject a PNG of a different size rather than scaling it into the requested pixel grid */
						if (sprite_get_width(source_sprite) != safe_w || sprite_get_height(source_sprite) != safe_h)
						{
							result.message = "PNG must be exactly " + string(safe_w) + "x" + string(safe_h) + " pixels.";
						}

						/* Matching dimensions allow exact pixel extraction with the caller's alpha cutoff */
						else
						{
							result = sprite_region_to_rgba_hex(source_sprite, 0, 0, safe_w, safe_h, alpha_cutoff);
						}
					}
				}
			}
		}

		/* Convert native decode or sampling exceptions into the result message, then run resource cleanup */
		catch(e)
		{
			result.message = "Could not decode PNG base64: " + string(e.message);
		}

		/* Release the owned decoded byte buffer if allocation succeeded */
		if (!is_undefined(source_buffer) && buffer_exists(source_buffer))
		{
			buffer_delete(source_buffer);
		}

		/* Delete the temporary sprite after sampling or failure */
		if (sprite_exists(source_sprite))
		{
			sprite_delete(source_sprite);
		}

		/* Remove the intermediate file when present, ignoring deletion errors so the decode result is preserved */
		if (file_exists(temp_path))
		{
			try { file_delete(temp_path); } catch(delete_error) {}
		}
		return result;
	}
}

/// @description Get the shared PNG conversion helper
/// @returns {Struct} Lazily constructed scr_rgba_png instance
function scr_get_rgba_png()
{
	/* Construct one helper for this runtime and share it across editor, import and export operations */
	static helper = new scr_rgba_png();
	return helper;
}
