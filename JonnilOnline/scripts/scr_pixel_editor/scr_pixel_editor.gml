/* Tool identifiers are shared by the stamp and character editors for pen, eraser, fill, colour picking and selection */
#macro PIXEL_EDITOR_TOOL_PEN 0
#macro PIXEL_EDITOR_TOOL_ERASER 1
#macro PIXEL_EDITOR_TOOL_FILL 2
#macro PIXEL_EDITOR_TOOL_COLOR_PICKER 3
#macro PIXEL_EDITOR_TOOL_SELECT 4

/// @description Own an RGBA pixel canvas, inclusive cell selection and undo/redo history
/// @param {Real} _grid_w Initial width in pixels, defaulting to 32. Rounded down and clamped to at least one
/// @param {Real} _grid_h Initial height in pixels, defaulting to 32. Rounded down and clamped to at least one
function scr_pixel_editor(_grid_w = 32, _grid_h = 32) constructor
{
	/* grid_w/grid_h are positive integer pixel dimensions derived from the requested initial canvas size */
	grid_w = max(1, floor(real(_grid_w)));
	grid_h = max(1, floor(real(_grid_h)));

	/* Row-major packed ABGR integers.
	Zero represents transparent black */
	pixels = array_create(grid_w * grid_h, 0);

	/* undo_stack and redo_stack hold independent dimension-and-pixel snapshots, starting empty
	undo_limit caps retained undo snapshots at 64 */
	undo_stack = [];
	redo_stack = [];
	undo_limit = 64;

	/* selection_active starts false, with all inclusive left/top/right/bottom cell bounds at zero until a selection is made
	selection_anchor_col/row mark the drag's fixed selection corner */
	selection_active = false;
	selection_left = 0;
	selection_top = 0;
	selection_right = 0;
	selection_bottom = 0;
	selection_anchor_col = 0;
	selection_anchor_row = 0;

	/* An empty drag mode means no selection gesture
	selection_drag_start_col/row store its initial pointer cell, and selection_move_origin_left/top store the original rectangle */
	selection_drag_mode = "";
	selection_drag_start_col = 0;
	selection_drag_start_row = 0;
	selection_move_origin_left = 0;
	selection_move_origin_top = 0;

	/* The move preview starts inactive, with left/top at zero until dragging positions a proposed destination */
	selection_preview_active = false;
	selection_preview_left = 0;
	selection_preview_top = 0;

	#region /* Pixel Packing and Cell Coordinates */
	/// @description Convert a channel to a floored integer byte
	/// @param {Real} raw_value Channel value
	/// @returns {Real} Integer from 0 to 255
	clamp_byte = function(raw_value)
	{
		return clamp(floor(real(raw_value)), 0, 255);
	}

	/// @description Pack integer RGBA bytes with red low and alpha high
	/// @param {Real} raw_red Red byte
	/// @param {Real} raw_green Green byte
	/// @param {Real} raw_blue Blue byte
	/// @param {Real} raw_alpha Alpha byte
	/// @returns {Real} Packed ABGR value
	pack_rgba = function(raw_red, raw_green, raw_blue, raw_alpha)
	{
		/* Clamp each RGBA channel to an integer byte before packing red in the low byte and alpha in the high byte */
		var packed_red = clamp_byte(raw_red);
		var packed_green = clamp_byte(raw_green);
		var packed_blue = clamp_byte(raw_blue);
		var packed_alpha = clamp_byte(raw_alpha);
		return packed_red + packed_green * 256 + packed_blue * 65536 + packed_alpha * 16777216;
	}

	/// @description Extract the red byte from a packed pixel
	/// @param {Real} pixel_value Packed ABGR integer
	/// @returns {Real} Channel byte from 0 to 255
	pixel_red = function(pixel_value)
	{
		return pixel_value & 255;
	}

	/// @description Extract the green byte from a packed pixel
	/// @param {Real} pixel_value Packed ABGR integer
	/// @returns {Real} Channel byte from 0 to 255
	pixel_green = function(pixel_value)
	{
		return (pixel_value >> 8) & 255;
	}

	/// @description Extract the blue byte from a packed pixel
	/// @param {Real} pixel_value Packed ABGR integer
	/// @returns {Real} Channel byte from 0 to 255
	pixel_blue = function(pixel_value)
	{
		return (pixel_value >> 16) & 255;
	}

	/// @description Extract the alpha byte from a packed pixel
	/// @param {Real} pixel_value Packed ABGR integer
	/// @returns {Real} Channel byte from 0 to 255
	pixel_alpha = function(pixel_value)
	{
		return (pixel_value >> 24) & 255;
	}

	/// @description Resolve canvas coordinates to a row-major index
	/// @param {Real} pixel_col Canvas column
	/// @param {Real} pixel_row Canvas row
	/// @returns {Real} Index or noone outside the bounds. Callers supply integer cells
	cell_index = function(pixel_col, pixel_row)
	{
		/* Reject coordinates outside the canvas before calculating their row-major array index */
		if (pixel_col < 0 || pixel_col >= grid_w || pixel_row < 0 || pixel_row >= grid_h)
		{
			return noone;
		}

		return pixel_row * grid_w + pixel_col;
	}

	/// @description Constrain a region's left edge to fit the canvas when possible
	/// @param {Real} raw_left Proposed column
	/// @param {Real} region_w Region width in cells
	/// @returns {Real} Integer left edge, or zero for a region at least as wide as the canvas
	clamp_region_left = function(raw_left, region_w)
	{
		/* Floor and clamp the region width to at least one cell before calculating its allowed left-edge position */
		var safe_w = max(1, floor(real(region_w)));

		/* A region at least as wide as the canvas must start at column zero, with excess columns clipped later */
		if (safe_w >= grid_w)
		{
			return 0;
		}

		return clamp(floor(real(raw_left)), 0, grid_w - safe_w);
	}

	/// @description Constrain a region's top edge to fit the canvas when possible
	/// @param {Real} raw_top Proposed row
	/// @param {Real} region_h Region height in cells
	/// @returns {Real} Integer top edge, or zero for a region at least as tall as the canvas
	clamp_region_top = function(raw_top, region_h)
	{
		/* Floor and clamp the region height before calculating its allowed top-edge position */
		var safe_h = max(1, floor(real(region_h)));

		/* A region at least as tall as the canvas starts at row zero, with excess rows clipped later */
		if (safe_h >= grid_h)
		{
			return 0;
		}

		return clamp(floor(real(raw_top)), 0, grid_h - safe_h);
	}
	#endregion /* Pixel Packing and Cell Coordinates END */

	#region /* Selection and Shared Region Clipboard */
	/// @description Clear active selection, drag mode and move preview
	/// @returns {Bool} Always true
	clear_selection = function()
	{
		selection_active = false;
		selection_drag_mode = "";
		selection_preview_active = false;
		return true;
	}

	/// @description Check for a selection or move gesture
	/// @returns {Bool} Whether drag mode is nonempty
	selection_drag_active = function()
	{
		/* Any nonempty drag mode identifies an active selection gesture */
		return selection_drag_mode != "";
	}

	/// @description Measure inclusive selected columns
	/// @returns {Real} Selected width, or zero without a selection
	selection_width = function()
	{
		/* An active selection includes both horizontal endpoints, otherwise its width is zero */
		return selection_active ? max(1, selection_right - selection_left + 1) : 0;
	}

	/// @description Measure inclusive selected rows
	/// @returns {Real} Selected height, or zero without a selection
	selection_height = function()
	{
		/* An active selection includes both vertical endpoints, otherwise its height is zero */
		return selection_active ? max(1, selection_bottom - selection_top + 1) : 0;
	}

	/// @description Clamp and order endpoints into an active inclusive cell rectangle
	/// @param {Real} col_a First column
	/// @param {Real} row_a First row
	/// @param {Real} col_b Second column
	/// @param {Real} row_b Second row
	/// @returns {Bool} Always true
	set_selection_rect = function(col_a, row_a, col_b, row_b)
	{
		/* Clamp and floor both endpoint columns and rows to the canvas, then order them into inclusive rectangle bounds */
		var safe_col_a = clamp(floor(real(col_a)), 0, grid_w - 1);
		var safe_col_b = clamp(floor(real(col_b)), 0, grid_w - 1);
		var safe_row_a = clamp(floor(real(row_a)), 0, grid_h - 1);
		var safe_row_b = clamp(floor(real(row_b)), 0, grid_h - 1);
		selection_left = min(safe_col_a, safe_col_b);
		selection_right = max(safe_col_a, safe_col_b);
		selection_top = min(safe_row_a, safe_row_b);
		selection_bottom = max(safe_row_a, safe_row_b);
		selection_active = true;
		return true;
	}

	/// @description Constrain the current selection after canvas dimensions change
	/// @returns {Bool} Whether an active ordered rectangle remains
	clamp_selection_to_canvas = function()
	{
		/* Without a selection, there is no rectangle to constrain */
		if (!selection_active)
		{
			return false;
		}

		selection_left = clamp(selection_left, 0, grid_w - 1);
		selection_right = clamp(selection_right, 0, grid_w - 1);
		selection_top = clamp(selection_top, 0, grid_h - 1);
		selection_bottom = clamp(selection_bottom, 0, grid_h - 1);

		/* Clear a rectangle whose ordered bounds are invalid after clamping */
		if (selection_right < selection_left || selection_bottom < selection_top)
		{
			clear_selection();
			return false;
		}

		return true;
	}

	/// @description Test a cell against the active inclusive selection
	/// @param {Real} pixel_col Canvas column
	/// @param {Real} pixel_row Canvas row
	/// @returns {Bool} Whether the cell belongs to the selection
	selection_contains = function(pixel_col, pixel_row)
	{
		/* Require an active selection and include each of its four cell-coordinate edges in the containment test */
		return selection_active
			&& pixel_col >= selection_left
			&& pixel_col <= selection_right
			&& pixel_row >= selection_top
			&& pixel_row <= selection_bottom;
	}

	/// @description Copy a canvas region with transparent values outside its bounds
	/// @param {Real} region_left Source left column
	/// @param {Real} region_top Source top row
	/// @param {Real} region_w Positive integer width after normalization
	/// @param {Real} region_h Positive integer height after normalization
	/// @returns {Struct} width, height and independent row-major pixels
	copy_region = function(region_left, region_top, region_w, region_h)
	{
		/* safe_w/safe_h are positive integer region dimensions, and region_pixels starts transparent for the independent row-major copy */
		var safe_w = max(1, floor(real(region_w)));
		var safe_h = max(1, floor(real(region_h)));
		var region_pixels = array_create(safe_w * safe_h, 0);

		/* Copy zero-based region rows in source order */
		for (var region_row = 0; region_row < safe_h; region_row++)
		{
			/* Copy every zero-based column through get_pixel, which returns transparent black outside the canvas */
			for (var region_col = 0; region_col < safe_w; region_col++)
			{
				region_pixels[region_row * safe_w + region_col] = get_pixel(region_left + region_col, region_top + region_row);
			}
		}

		/* The returned region stores width/height in cells and owns its new packed-pixel array */
		return
		{
			width: safe_w,
			height: safe_h,
			pixels: region_pixels
		};
	}

	/// @description Copy the active selection into independent region data
	/// @returns {Struct} Region, or noone without a selection
	copy_selected_region = function()
	{
		/* No active selection returns noone instead of treating the default zero bounds as a copied region */
		if (!selection_active)
		{
			return noone;
		}

		return copy_region(selection_left, selection_top, selection_width(), selection_height());
	}

	/// @description Copy normalized region dimensions and pixel data
	/// @param {Struct} source_region Numeric width/height and packed pixels array
	/// @returns {Struct} Independent region, or noone for missing required fields
	copy_region_struct = function(source_region)
	{
		/* Check the source is a struct before reading its width, height and pixel fields
		Callers still need to supply numeric dimensions and an array of packed pixels */
		if (!is_struct(source_region)
		|| !variable_struct_exists(source_region, "width")
		|| !variable_struct_exists(source_region, "height")
		|| !variable_struct_exists(source_region, "pixels"))
		{
			return noone;
		}

		/* Normalize dimensions, borrow source_pixels, create a transparent copied_pixels array,
		and bound copy_count to the shorter array so missing source pixels remain transparent */
		var safe_w = max(1, floor(real(source_region.width)));
		var safe_h = max(1, floor(real(source_region.height)));
		var source_pixels = source_region.pixels;
		var copied_pixels = array_create(safe_w * safe_h, 0);
		var copy_count = min(array_length(source_pixels), array_length(copied_pixels));

		/* Copy each zero-based available pixel into a separate array to avoid shared edits */
		for (var pixel_index = 0; pixel_index < copy_count; pixel_index++)
		{
			copied_pixels[pixel_index] = source_pixels[pixel_index];
		}

		/* Return the normalized width/height with the independent copied pixel array */
		return
		{
			width: safe_w,
			height: safe_h,
			pixels: copied_pixels
		};
	}

	/* Share copied regions between stamp and character editors without sharing their pixel arrays */
	/// @description Store an independent region copy in the shared editor clipboard
	/// @param {Struct} region Region data to copy
	/// @returns {Bool} Whether a usable copy was stored
	set_region_clipboard = function(region)
	{
		/* Copy the supplied region before storing it in the game-wide editor clipboard */
		var region_copy = copy_region_struct(region);

		/* An unusable source leaves the previous shared clipboard unchanged */
		if (!is_struct(region_copy))
		{
			return false;
		}

		/* The shared global stores a copied editor region for cross-editor paste, separate from the operating-system text clipboard */
		global.pixel_editor_region_clipboard = region_copy;
		return true;
	}

	/// @description Set the shared editor clipboard to noone
	/// @returns {Bool} Always true
	clear_region_clipboard = function()
	{
		/* noone marks the shared editor clipboard as empty */
		global.pixel_editor_region_clipboard = noone;
		return true;
	}

	/// @description Read the shared editor clipboard without copying it
	/// @returns {Struct} Stored region or noone
	region_clipboard = function()
	{
		/* Check existence before reading the shared global, returning it only when it is a region struct */
		if (variable_global_exists("pixel_editor_region_clipboard")
		&& is_struct(global.pixel_editor_region_clipboard))
		{
			return global.pixel_editor_region_clipboard;
		}

		return noone;
	}

	/// @description Check required clipboard fields and positive dimensions
	/// @returns {Bool} Whether the stored region is available
	region_clipboard_available = function()
	{
		/* Borrow the shared region before checking its required fields and positive dimensions */
		var clipboard_region = region_clipboard();

		/* Guard field reads with type and existence checks, then require positive width and height for paste availability */
		return is_struct(clipboard_region)
			&& variable_struct_exists(clipboard_region, "width")
			&& variable_struct_exists(clipboard_region, "height")
			&& variable_struct_exists(clipboard_region, "pixels")
			&& clipboard_region.width > 0
			&& clipboard_region.height > 0;
	}

	/// @description Copy the selected region into the shared editor clipboard
	/// @returns {Bool} Whether copying succeeded
	copy_selection_to_clipboard = function()
	{
		return set_region_clipboard(copy_selected_region());
	}

	/// @description Clear nonzero selected pixels with at most one undo snapshot
	/// @param {Bool} push_undo Save a snapshot before the first change. Defaults to true
	/// @returns {Bool} Whether any packed pixel changed
	clear_selected_pixels = function(push_undo = true)
	{
		/* Without an active rectangle, leave all pixels and history unchanged */
		if (!selection_active)
		{
			return false;
		}

		/* changed starts false until a nonzero pixel is cleared, and pushed_snapshot prevents more than one undo entry for this operation */
		var changed = false;
		var pushed_snapshot = false;

		/* Traverse inclusive selected rows, with pixel_row indexing canvas cells */
		for (var pixel_row = selection_top; pixel_row <= selection_bottom; pixel_row++)
		{
			/* Visit inclusive selected columns within each row */
			for (var pixel_col = selection_left; pixel_col <= selection_right; pixel_col++)
			{
				/* Resolve the selected cell to its row-major pixel position before testing its contents */
				var target_index = cell_index(pixel_col, pixel_row);

				/* Only valid nonzero cells need clearing, so already-transparent pixels create neither a change nor an undo snapshot */
				if (target_index != noone && pixels[target_index] != 0)
				{
					/* When requested, snapshot immediately before the first changed pixel and retain that one snapshot for the rest of the clear */
					if (push_undo && !pushed_snapshot)
					{
						push_undo_snapshot();
						pushed_snapshot = true;
					}

					pixels[target_index] = 0;
					changed = true;
				}
			}
		}

		return changed;
	}

	/// @description Copy the selection, then clear its nonzero pixels with undo
	/// @returns {Bool} Whether pixels were cleared. Copy may succeed even when false
	cut_selection_to_clipboard = function()
	{
		/* Only a successful copy permits clearing the selected source pixels */
		if (!copy_selection_to_clipboard())
		{
			return false;
		}

		return clear_selected_pixels(true);
	}

	/// @description Paste visible pixels and select the destination. Transparent source pixels preserve existing pixels
	/// @param {Struct} region Width, height and row-major packed RGBA pixel array
	/// @param {Real} raw_left Destination cell column, clamped to the canvas
	/// @param {Real} raw_top Destination cell row, clamped to the canvas
	/// @param {Bool} push_undo Save one snapshot before the first changed pixel, defaulting to true
	/// @returns {Bool} Whether any pixel changed. Selection may change even when false
	paste_region_at = function(region, raw_left, raw_top, push_undo = true)
	{
		/* Clone the source region so pasting reads a stable independent pixel array */
		var paste_region = copy_region_struct(region);

		/* Invalid region data cannot establish a destination selection or change pixels */
		if (!is_struct(paste_region))
		{
			return false;
		}

		/* Clamp the destination left/top to fit the region when possible
		changed records actual pixel differences and pushed_snapshot starts false for one optional undo entry */
		var target_left = clamp_region_left(raw_left, paste_region.width);
		var target_top = clamp_region_top(raw_top, paste_region.height);
		var changed = false;
		var pushed_snapshot = false;

		/* Traverse the source's zero-based rows, clipping any portion taller than the destination canvas */
		for (var region_row = 0; region_row < paste_region.height; region_row++)
		{
			/* Translate the source-relative row into a destination canvas row */
			var target_row = target_top + region_row;

			/* Skip rows outside the canvas instead of writing invalid indices */
			if (target_row < 0 || target_row >= grid_h)
			{
				continue;
			}

			/* Traverse the source's zero-based columns within an accepted destination row */
			for (var region_col = 0; region_col < paste_region.width; region_col++)
			{
				/* Translate the source-relative column into a destination canvas column */
				var target_col = target_left + region_col;

				/* Skip columns outside the canvas instead of writing invalid indices */
				if (target_col < 0 || target_col >= grid_w)
				{
					continue;
				}

				/* Read this row-major source pixel before testing whether its alpha makes it visible */
				var source_pixel = paste_region.pixels[region_row * paste_region.width + region_col];

				/* Transparent source pixels preserve existing destination pixels */
				if (pixel_alpha(source_pixel) <= 0)
				{
					continue;
				}

				/* Compute the valid destination pixel's row-major index */
				var target_index = target_row * grid_w + target_col;

				/* Write only different packed values so the result and undo history reflect actual pixel changes */
				if (pixels[target_index] != source_pixel)
				{
					/* Capture one pre-paste snapshot immediately before the first changed pixel when requested */
					if (push_undo && !pushed_snapshot)
					{
						push_undo_snapshot();
						pushed_snapshot = true;
					}

					pixels[target_index] = source_pixel;
					changed = true;
				}
			}
		}

		set_selection_rect(target_left, target_top, min(grid_w - 1, target_left + paste_region.width - 1), min(grid_h - 1, target_top + paste_region.height - 1));
		return changed;
	}

	/// @description Paste shared visible pixels at a clamped destination with undo
	/// @param {Real} raw_left Destination column
	/// @param {Real} raw_top Destination row
	/// @returns {Bool} Whether any pixel changed. Destination selection may change when false
	paste_clipboard_at = function(raw_left, raw_top)
	{
		return paste_region_at(region_clipboard(), raw_left, raw_top, true);
	}

	/// @description Scan a supplied pixel array for nonzero alpha
	/// @param {Struct} region Region containing an assumed packed pixels array
	/// @returns {Bool} Whether visible content exists
	region_has_visible_pixels = function(region)
	{
		/* Require a region struct with a pixel field before scanning its assumed array */
		if (!is_struct(region) || !variable_struct_exists(region, "pixels"))
		{
			return false;
		}

		/* Scan all zero-based region pixels until one nonzero alpha proves visible content exists */
		for (var pixel_index = 0; pixel_index < array_length(region.pixels); pixel_index++)
		{
			/* The first visible pixel ends the search, while an entirely transparent region returns false below */
			if (pixel_alpha(region.pixels[pixel_index]) > 0)
			{
				return true;
			}
		}

		return false;
	}

	/// @description Move copied visible pixels after one undo snapshot and clear the old selection
	/// @param {Real} raw_left Proposed destination column
	/// @param {Real} raw_top Proposed destination row
	/// @returns {Bool} Whether a visible-region move was accepted. Empty selections may move their rectangle when false
	move_selection_to = function(raw_left, raw_top)
	{
		/* Without an active rectangle, there is no source region to move */
		if (!selection_active)
		{
			return false;
		}

		/* Copy the selected source before clearing it, preserving pixels even when the new region overlaps the old one */
		var move_region = copy_selected_region();

		/* A failed source copy leaves the canvas and history intact */
		if (!is_struct(move_region))
		{
			return false;
		}

		/* Clamp the copied region's destination left/top before checking whether movement is needed */
		var target_left = clamp_region_left(raw_left, move_region.width);
		var target_top = clamp_region_top(raw_top, move_region.height);

		/* An unchanged destination clears the preview and returns false without an undo entry */
		if (target_left == selection_left && target_top == selection_top)
		{
			selection_preview_active = false;
			return false;
		}

		/* An empty region moves only the selection rectangle, reporting no artwork operation and creating no undo entry */
		if (!region_has_visible_pixels(move_region))
		{
			set_selection_rect(target_left, target_top, min(grid_w - 1, target_left + move_region.width - 1), min(grid_h - 1, target_top + move_region.height - 1));
			selection_preview_active = false;
			return false;
		}

		push_undo_snapshot();
		clear_selected_pixels(false);

		/* After the single undo snapshot and source clear, traverse the copied zero-based rows */
		for (var region_row = 0; region_row < move_region.height; region_row++)
		{
			/* Map this copied row into the destination canvas */
			var target_row = target_top + region_row;

			/* Clip rows outside the destination canvas */
			if (target_row < 0 || target_row >= grid_h)
			{
				continue;
			}

			/* Visit the copied region's zero-based columns in each accepted row */
			for (var region_col = 0; region_col < move_region.width; region_col++)
			{
				/* Map this copied column into the destination canvas */
				var target_col = target_left + region_col;

				/* Clip columns outside the destination canvas */
				if (target_col < 0 || target_col >= grid_w)
				{
					continue;
				}

				/* Read the preserved source pixel after the old selection has been cleared */
				var source_pixel = move_region.pixels[region_row * move_region.width + region_col];

				/* Only visible source pixels overwrite the destination, preserving pixels under transparent source areas */
				if (pixel_alpha(source_pixel) > 0)
				{
					pixels[target_row * grid_w + target_col] = source_pixel;
				}
			}
		}

		set_selection_rect(target_left, target_top, min(grid_w - 1, target_left + move_region.width - 1), min(grid_h - 1, target_top + move_region.height - 1));
		selection_preview_active = false;
		return true;
	}

	/// @description Begin moving an existing selection or anchoring a new rectangle
	/// @param {Real} pixel_col Pointer canvas column
	/// @param {Real} pixel_row Pointer canvas row
	/// @returns {String} move or select
	begin_selection_drag = function(pixel_col, pixel_row)
	{
		/* Floor and clamp the pointer cell for the gesture's initial column and row */
		var safe_col = clamp(floor(real(pixel_col)), 0, grid_w - 1);
		var safe_row = clamp(floor(real(pixel_row)), 0, grid_h - 1);
		selection_drag_start_col = safe_col;
		selection_drag_start_row = safe_row;

		/* A press inside the active selection starts moving its existing rectangle
		A press elsewhere starts a new selection anchored at that cell */
		if (selection_contains(safe_col, safe_row))
		{
			selection_drag_mode = "move";
			selection_move_origin_left = selection_left;
			selection_move_origin_top = selection_top;
			selection_preview_left = selection_left;
			selection_preview_top = selection_top;
			selection_preview_active = true;
			return "move";
		}

		selection_drag_mode = "select";
		selection_anchor_col = safe_col;
		selection_anchor_row = safe_row;
		selection_preview_active = false;
		set_selection_rect(safe_col, safe_row, safe_col, safe_row);
		return "select";
	}

	/// @description Update the move preview or new selection bounds without committing pixels
	/// @param {Real} pixel_col Current pointer column
	/// @param {Real} pixel_row Current pointer row
	/// @returns {Bool} Always false because no pixel operation is committed
	update_selection_drag = function(pixel_col, pixel_row)
	{
		/* Without an active gesture, leave selection and preview state alone */
		if (selection_drag_mode == "")
		{
			return false;
		}

		/* Clamp the current pointer cell before measuring its displacement or selection endpoint */
		var safe_col = clamp(floor(real(pixel_col)), 0, grid_w - 1);
		var safe_row = clamp(floor(real(pixel_row)), 0, grid_h - 1);

		/* Moving updates only the clamped preview until finish_selection_drag commits it
		Selection gestures instead update the inclusive rectangle below, with both paths returning false for no committed pixel operation */
		if (selection_drag_mode == "move")
		{
			selection_preview_left = clamp_region_left(selection_move_origin_left + safe_col - selection_drag_start_col, selection_width());
			selection_preview_top = clamp_region_top(selection_move_origin_top + safe_row - selection_drag_start_row, selection_height());
			selection_preview_active = true;
			return false;
		}

		set_selection_rect(selection_anchor_col, selection_anchor_row, safe_col, safe_row);
		return false;
	}

	/// @description Commit an active move and clear the gesture preview
	/// @returns {Bool} Move result, or false for a selection-only or absent gesture
	finish_selection_drag = function()
	{
		/* No active gesture means there is nothing to commit */
		if (selection_drag_mode == "")
		{
			return false;
		}

		/* Start with no pixel operation and replace the result only when committing a move */
		var changed = false;

		/* Only move gestures alter artwork at completion, while selection gestures merely finish their rectangle */
		if (selection_drag_mode == "move")
		{
			changed = move_selection_to(selection_preview_left, selection_preview_top);
		}

		selection_drag_mode = "";
		selection_preview_active = false;
		return changed;
	}

	/// @description Clear the gesture and move preview without committing it
	/// @returns {Bool} Always true
	cancel_selection_drag = function()
	{
		selection_drag_mode = "";
		selection_preview_active = false;
		return true;
	}
	#endregion /* Selection and Shared Region Clipboard END */

	#region /* Canvas Snapshots and Undo History */
	/// @description Copy the canvas pixel array for independent reading
	/// @returns {Array<Real>} Row-major packed pixels
	copy_pixels = function()
	{
		/* Allocate an independent pixel array matching the current canvas for stable undo and transformation reads */
		var snapshot = array_create(array_length(pixels), 0);

		/* Copy every zero-based row-major pixel into the snapshot */
		for (var pixel_index = 0; pixel_index < array_length(pixels); pixel_index++)
		{
			snapshot[pixel_index] = pixels[pixel_index];
		}

		return snapshot;
	}

	/// @description Copy canvas dimensions and pixels for history
	/// @returns {Struct} grid_w, grid_h and independent pixels
	copy_snapshot = function()
	{
		/* A complete snapshot stores grid_w/grid_h and an independent packed-pixel array so undo can also restore dimensions */
		return
		{
			grid_w: grid_w,
			grid_h: grid_h,
			pixels: copy_pixels()
		};
	}

	/// @description Restore a dimensioned snapshot or legacy pixel array
	/// @param {Struct|Array<Real>} snapshot Trusted snapshot data. Legacy arrays retain current dimensions
	/// @returns {Bool} Always true. Clears uncopied pixels and clamps selection
	restore_pixels = function(snapshot)
	{
		/* Assume a legacy pixel array initially, replacing it with the pixel field when the supplied snapshot is a dimensioned struct */
		var snapshot_pixels = snapshot;

		/* Dimensioned snapshots recreate the canvas at their stored size before copying pixels
		Legacy array snapshots retain the current dimensions */
		if (is_struct(snapshot))
		{
			grid_w = max(1, floor(real(snapshot.grid_w)));
			grid_h = max(1, floor(real(snapshot.grid_h)));
			pixels = array_create(grid_w * grid_h, 0);
			snapshot_pixels = snapshot.pixels;
		}

		/* Copy only the overlap between source data and the destination pixel array */
		var copy_count = min(array_length(snapshot_pixels), array_length(pixels));

		/* Restore each zero-based available source pixel */
		for (var pixel_index = 0; pixel_index < copy_count; pixel_index++)
		{
			pixels[pixel_index] = snapshot_pixels[pixel_index];
		}

		/* Fill remaining destination positions with transparent black when the snapshot is shorter */
		for (var clear_index = copy_count; clear_index < array_length(pixels); clear_index++)
		{
			pixels[clear_index] = 0;
		}

		clamp_selection_to_canvas();
		return true;
	}

	/// @description Copy the current dimensions and pixels before an edit and clear redo history
	/// @returns {Bool} True after storing the snapshot, bounding undo history and clearing redo
	push_undo_snapshot = function()
	{
		undo_stack[array_length(undo_stack)] = copy_snapshot();

		/* Discard oldest snapshots beyond the 64-entry limit before clearing redo for the new edit */
		while (array_length(undo_stack) > undo_limit)
		{
			array_delete(undo_stack, 0, 1);
		}

		redo_stack = [];
		return true;
	}

	/// @description Check whether a prior canvas snapshot is available
	/// @returns {Bool} Whether undo history is nonempty
	can_undo = function()
	{
		/* A nonempty undo stack permits restoring an earlier snapshot */
		return array_length(undo_stack) > 0;
	}

	/// @description Check whether a displaced snapshot is available
	/// @returns {Bool} Whether redo history is nonempty
	can_redo = function()
	{
		/* A nonempty redo stack permits restoring a snapshot displaced by undo */
		return array_length(redo_stack) > 0;
	}

	/// @description Save the current canvas to redo and restore the newest undo snapshot
	/// @returns {Bool} Whether an undo snapshot existed
	undo = function()
	{
		/* Count available snapshots before selecting the newest zero-based entry */
		var undo_count = array_length(undo_stack);

		/* No undo history leaves the canvas and redo stack unchanged */
		if (undo_count <= 0)
		{
			return false;
		}

		redo_stack[array_length(redo_stack)] = copy_snapshot();

		/* Keep the last undo snapshot before removing it, after saving the current canvas to redo */
		var snapshot = undo_stack[undo_count - 1];
		array_delete(undo_stack, undo_count - 1, 1);
		restore_pixels(snapshot);
		return true;
	}

	/// @description Save the current canvas to bounded undo and restore the newest redo snapshot
	/// @returns {Bool} Whether a redo snapshot existed
	redo = function()
	{
		/* Count available redo snapshots before choosing the newest entry */
		var redo_count = array_length(redo_stack);

		/* No redo history leaves the canvas and undo stack unchanged */
		if (redo_count <= 0)
		{
			return false;
		}

		undo_stack[array_length(undo_stack)] = copy_snapshot();

		/* Restoring redo also enforces the bounded undo history after storing the current canvas */
		while (array_length(undo_stack) > undo_limit)
		{
			array_delete(undo_stack, 0, 1);
		}

		/* Keep the last redo snapshot before removing and restoring it */
		var snapshot = redo_stack[redo_count - 1];
		array_delete(redo_stack, redo_count - 1, 1);
		restore_pixels(snapshot);
		return true;
	}
	#endregion /* Canvas Snapshots and Undo History END */

	#region /* Pixel Painting and Fill */
	/// @description Set all pixels transparent and clear selection without automatically saving undo
	/// @returns {Bool} Always true
	clear = function()
	{
		/* Set every zero-based canvas pixel to transparent black, then clear selection without adding undo automatically */
		for (var pixel_index = 0; pixel_index < array_length(pixels); pixel_index++)
		{
			pixels[pixel_index] = 0;
		}

		clear_selection();
		return true;
	}

	/// @description Read a packed canvas cell
	/// @param {Real} pixel_col Integer canvas column
	/// @param {Real} pixel_row Integer canvas row
	/// @returns {Real} Packed value, or transparent zero outside the bounds
	get_pixel = function(pixel_col, pixel_row)
	{
		/* Resolve the supplied canvas coordinates to the packed row-major index before accessing pixels */
		var target_index = cell_index(pixel_col, pixel_row);

		/* Out-of-bounds coordinates return transparent black without accessing the pixel array */
		if (target_index == noone)
		{
			return 0;
		}

		return pixels[target_index];
	}

	/* Stroke callers push one undo snapshot before repeated per-pixel changes */
	/// @description Write clamped RGBA at a valid cell without adding undo
	/// @param {Real} pixel_col Integer canvas column
	/// @param {Real} pixel_row Integer canvas row
	/// @param {Real} raw_red Red byte
	/// @param {Real} raw_green Green byte
	/// @param {Real} raw_blue Blue byte
	/// @param {Real} raw_alpha Alpha byte
	/// @returns {Bool} Whether the coordinates were accepted, including an identical value
	set_pixel_rgba = function(pixel_col, pixel_row, raw_red, raw_green, raw_blue, raw_alpha)
	{
		/* Resolve the supplied canvas coordinates to the packed row-major index before accessing pixels */
		var target_index = cell_index(pixel_col, pixel_row);

		/* Out-of-bounds coordinates return false without accessing the pixel array */
		if (target_index == noone)
		{
			return false;
		}

		pixels[target_index] = pack_rgba(raw_red, raw_green, raw_blue, raw_alpha);
		return true;
	}

	/// @description Write a fully opaque RGB pixel without adding undo
	/// @param {Real} pixel_col Integer column
	/// @param {Real} pixel_row Integer row
	/// @param {Real} raw_red Red byte
	/// @param {Real} raw_green Green byte
	/// @param {Real} raw_blue Blue byte
	/// @returns {Bool} Whether coordinates were accepted, including an identical colour
	paint_pixel = function(pixel_col, pixel_row, raw_red, raw_green, raw_blue)
	{
		return set_pixel_rgba(pixel_col, pixel_row, raw_red, raw_green, raw_blue, 255);
	}

	/// @description Clear a valid cell to transparent black without adding undo
	/// @param {Real} pixel_col Integer column
	/// @param {Real} pixel_row Integer row
	/// @returns {Bool} Whether coordinates were accepted, including an already-transparent cell
	erase_pixel = function(pixel_col, pixel_row)
	{
		/* Resolve the supplied canvas coordinates to the packed row-major index before accessing pixels */
		var target_index = cell_index(pixel_col, pixel_row);

		/* Out-of-bounds coordinates return false without accessing the pixel array */
		if (target_index == noone)
		{
			return false;
		}

		pixels[target_index] = 0;
		return true;
	}

	/// @description Flood-fill exact matching RGBA values with opaque RGB using four-neighbor traversal
	/// @param {Real} pixel_col Integer seed column
	/// @param {Real} pixel_row Integer seed row
	/// @param {Real} raw_red Red byte
	/// @param {Real} raw_green Green byte
	/// @param {Real} raw_blue Blue byte
	/// @returns {Bool} Whether pixels changed. Caller supplies the undo snapshot
	fill_pixels = function(pixel_col, pixel_row, raw_red, raw_green, raw_blue)
	{
		/* Resolve the fill seed to a canvas index before reading its original packed colour */
		var start_index = cell_index(pixel_col, pixel_row);

		/* An out-of-bounds seed cannot start a fill */
		if (start_index == noone)
		{
			return false;
		}

		/* target_pixel is the exact original RGBA value to replace, while fill_pixel is the requested colour with full alpha */
		var target_pixel = pixels[start_index];
		var fill_pixel = pack_rgba(raw_red, raw_green, raw_blue, 255);

		/* An already-matching seed needs no traversal or pixel changes */
		if (target_pixel == fill_pixel)
		{
			return false;
		}

		/* Parallel queue_cols/queue_rows hold cell coordinates from the seed onward
		queue_head starts at zero for the next pending entry, and changed records whether any matching pixel was replaced */
		var queue_cols = [pixel_col];
		var queue_rows = [pixel_row];
		var queue_head = 0;
		var changed = false;

		/* Process queued cells until every appended neighbor has been checked */
		while (queue_head < array_length(queue_cols))
		{
			/* Read the current queued column/row before advancing queue_head */
			var check_col = queue_cols[queue_head];
			var check_row = queue_rows[queue_head];
			queue_head++;

			/* Resolve this queued neighbor before comparing its packed colour */
			var check_index = cell_index(check_col, check_row);

			/* Skip out-of-bounds cells before array access, plus pixels that differ from the original colour
			Already-filled pixels differ too, so repeated neighbor entries cannot expand again */
			if (check_index == noone || pixels[check_index] != target_pixel)
			{
				continue;
			}

			pixels[check_index] = fill_pixel;
			changed = true;

			queue_cols[array_length(queue_cols)] = check_col - 1;
			queue_rows[array_length(queue_rows)] = check_row;
			queue_cols[array_length(queue_cols)] = check_col + 1;
			queue_rows[array_length(queue_rows)] = check_row;
			queue_cols[array_length(queue_cols)] = check_col;
			queue_rows[array_length(queue_rows)] = check_row - 1;
			queue_cols[array_length(queue_cols)] = check_col;
			queue_rows[array_length(queue_rows)] = check_row + 1;
		}

		return changed;
	}
	#endregion /* Pixel Painting and Fill END */

	#region /* Canvas Transformations */
	/// @description Snapshot and mirror canvas columns, then clear selection
	/// @returns {Bool} Whether width permits a flip. Symmetric pixels may remain identical
	flip_horizontal = function()
	{
		/* A one-cell width has no opposing cells to swap, so skip the transformation */
		if (grid_w <= 1)
		{
			return false;
		}

		push_undo_snapshot();
		clear_selection();

		/* Traverse all zero-based rows to swap each mirrored pair once */
		for (var pixel_row = 0; pixel_row < grid_h; pixel_row++)
		{
			/* Traverse only the left half of columns while reflecting pixels across the canvas */
			for (var pixel_col = 0; pixel_col < floor(grid_w * 0.5); pixel_col++)
			{
				/* The paired indices locate opposite pixels, and temp_pixel preserves the first packed value during the swap */
				var left_index = cell_index(pixel_col, pixel_row);
				var right_index = cell_index(grid_w - 1 - pixel_col, pixel_row);
				var temp_pixel = pixels[left_index];
				pixels[left_index] = pixels[right_index];
				pixels[right_index] = temp_pixel;
			}
		}

		return true;
	}

	/// @description Snapshot and mirror canvas rows, then clear selection
	/// @returns {Bool} Whether height permits a flip. Symmetric pixels may remain identical
	flip_vertical = function()
	{
		/* A one-cell height has no opposing cells to swap, so skip the transformation */
		if (grid_h <= 1)
		{
			return false;
		}

		push_undo_snapshot();
		clear_selection();

		/* Traverse only the top half of rows to swap each mirrored pair once */
		for (var pixel_row = 0; pixel_row < floor(grid_h * 0.5); pixel_row++)
		{
			/* Traverse all zero-based columns while reflecting pixels across the canvas */
			for (var pixel_col = 0; pixel_col < grid_w; pixel_col++)
			{
				/* The paired indices locate opposite pixels, and temp_pixel preserves the first packed value during the swap */
				var top_index = cell_index(pixel_col, pixel_row);
				var bottom_index = cell_index(pixel_col, grid_h - 1 - pixel_row);
				var temp_pixel = pixels[top_index];
				pixels[top_index] = pixels[bottom_index];
				pixels[bottom_index] = temp_pixel;
			}
		}

		return true;
	}

	/// @description Snapshot and rotate the canvas 90 degrees clockwise, exchanging dimensions
	/// @returns {Bool} Always true. Does not test pixel differences
	rotate_clockwise = function()
	{
		push_undo_snapshot();
		clear_selection();

		/* Preserve old dimensions and an independent old_pixels copy, then exchange width/height for the rotated canvas
		new_pixels starts transparent before every source cell maps into its destination */
		var old_grid_w = grid_w;
		var old_grid_h = grid_h;
		var old_pixels = copy_pixels();
		var new_grid_w = old_grid_h;
		var new_grid_h = old_grid_w;
		var new_pixels = array_create(new_grid_w * new_grid_h, 0);

		/* Traverse all zero-based source rows for the quarter-turn mapping */
		for (var pixel_row = 0; pixel_row < old_grid_h; pixel_row++)
		{
			/* Map every zero-based source column into the rotated canvas */
			for (var pixel_col = 0; pixel_col < old_grid_w; pixel_col++)
			{
				/* Clockwise mapping reflects the source row into the new column and uses the old column as the new row */
				var target_col = old_grid_h - 1 - pixel_row;
				var target_row = pixel_col;
				new_pixels[target_row * new_grid_w + target_col] = old_pixels[pixel_row * old_grid_w + pixel_col];
			}
		}

		grid_w = new_grid_w;
		grid_h = new_grid_h;
		pixels = new_pixels;
		return true;
	}

	/// @description Snapshot and rotate the canvas 90 degrees counterclockwise, exchanging dimensions
	/// @returns {Bool} Always true. Does not test pixel differences
	rotate_counterclockwise = function()
	{
		push_undo_snapshot();
		clear_selection();

		/* Preserve old dimensions and an independent old_pixels copy, then exchange width/height for the rotated canvas
		new_pixels starts transparent before every source cell maps into its destination */
		var old_grid_w = grid_w;
		var old_grid_h = grid_h;
		var old_pixels = copy_pixels();
		var new_grid_w = old_grid_h;
		var new_grid_h = old_grid_w;
		var new_pixels = array_create(new_grid_w * new_grid_h, 0);

		/* Traverse all zero-based source rows for the quarter-turn mapping */
		for (var pixel_row = 0; pixel_row < old_grid_h; pixel_row++)
		{
			/* Map every zero-based source column into the rotated canvas */
			for (var pixel_col = 0; pixel_col < old_grid_w; pixel_col++)
			{
				/* Counterclockwise mapping uses the old row as the new column and reflects the old column into the new row */
				var target_col = pixel_row;
				var target_row = old_grid_w - 1 - pixel_col;
				new_pixels[target_row * new_grid_w + target_col] = old_pixels[pixel_row * old_grid_w + pixel_col];
			}
		}

		grid_w = new_grid_w;
		grid_h = new_grid_h;
		pixels = new_pixels;
		return true;
	}

	/// @description Snapshot and translate pixels, discarding content outside the canvas
	/// @param {Real} delta_col Column displacement, floored to integer cells
	/// @param {Real} delta_row Row displacement, floored to integer cells
	/// @returns {Bool} Whether displacement was nonzero. Does not test pixel differences
	shift_pixels = function(delta_col, delta_row)
	{
		/* Floor the requested column/row displacement to integer cells, retaining negative direction */
		var move_col = floor(real(delta_col));
		var move_row = floor(real(delta_row));

		/* A zero displacement skips snapshot creation and leaves the canvas unchanged */
		if (move_col == 0 && move_row == 0)
		{
			return false;
		}

		push_undo_snapshot();
		clear_selection();

		/* Copy original pixels before filling a transparent destination array, so uncovered areas remain transparent */
		var old_pixels = copy_pixels();
		var new_pixels = array_create(grid_w * grid_h, 0);

		/* Traverse all zero-based source rows for translation */
		for (var pixel_row = 0; pixel_row < grid_h; pixel_row++)
		{
			/* Translate every source column within its row */
			for (var pixel_col = 0; pixel_col < grid_w; pixel_col++)
			{
				/* Add the integer displacement to obtain this source cell's destination column and row */
				var target_col = pixel_col + move_col;
				var target_row = pixel_row + move_row;

				/* Copy only destinations still inside the canvas, discarding pixels shifted beyond its edges */
				if (target_col >= 0 && target_col < grid_w && target_row >= 0 && target_row < grid_h)
				{
					new_pixels[target_row * grid_w + target_col] = old_pixels[pixel_row * grid_w + pixel_col];
				}
			}
		}

		pixels = new_pixels;
		return true;
	}

	/// @description Save undo state and centre-crop or centre-pad the pixels and clear selection
	/// @param {Real} new_grid_w New canvas width in pixels, at least one
	/// @param {Real} new_grid_h New canvas height in pixels, at least one
	/// @returns {Bool} Whether the dimensions changed
	resize_canvas = function(new_grid_w, new_grid_h)
	{
		/* Normalize the requested new dimensions to positive integer cell counts */
		var safe_grid_w = max(1, floor(real(new_grid_w)));
		var safe_grid_h = max(1, floor(real(new_grid_h)));

		/* Identical dimensions skip resize and its undo entry */
		if (safe_grid_w == grid_w && safe_grid_h == grid_h)
		{
			return false;
		}

		push_undo_snapshot();
		clear_selection();

		/* Preserve old dimensions and pixels before allocating the new transparent canvas
		copy_w/copy_h limit copying to the shared extent of old and new sizes */
		var old_grid_w = grid_w;
		var old_grid_h = grid_h;
		var old_pixels = copy_pixels();
		var new_pixels = array_create(safe_grid_w * safe_grid_h, 0);
		var copy_w = min(old_grid_w, safe_grid_w);
		var copy_h = min(old_grid_h, safe_grid_h);

		/* Source offsets centre-crop a smaller destination, while target offsets centre-pad a larger destination
		Flooring odd differences puts the extra crop or padding on the right or bottom */
		var source_start_col = max(0, floor((old_grid_w - safe_grid_w) * 0.5));
		var source_start_row = max(0, floor((old_grid_h - safe_grid_h) * 0.5));
		var target_start_col = max(0, floor((safe_grid_w - old_grid_w) * 0.5));
		var target_start_row = max(0, floor((safe_grid_h - old_grid_h) * 0.5));

		/* Traverse zero-based rows within the overlapping copy height */
		for (var copy_row = 0; copy_row < copy_h; copy_row++)
		{
			/* Copy each zero-based column within the shared width */
			for (var copy_col = 0; copy_col < copy_w; copy_col++)
			{
				/* source_col/source_row add the crop offset, and target_col/target_row add the padding offset */
				var source_col = source_start_col + copy_col;
				var source_row = source_start_row + copy_row;
				var target_col = target_start_col + copy_col;
				var target_row = target_start_row + copy_row;
				new_pixels[target_row * safe_grid_w + target_col] = old_pixels[source_row * old_grid_w + source_col];
			}
		}

		grid_w = safe_grid_w;
		grid_h = safe_grid_h;
		pixels = new_pixels;
		return true;
	}
	#endregion /* Canvas Transformations END */

	#region /* Pixel Serialization and Sprite Import */
	/// @description Encode one clamped four-bit value
	/// @param {Real} value Value to floor and clamp
	/// @returns {String} Uppercase hex digit
	hex_digit = function(value)
	{
		return string_char_at("0123456789ABCDEF", clamp(floor(real(value)), 0, 15) + 1);
	}

	/// @description Encode one clamped byte
	/// @param {Real} raw_value Byte value
	/// @returns {String} Two uppercase hex digits
	byte_to_hex = function(raw_value)
	{
		/* Clamp to an integer byte, then encode its high and low four-bit halves as two uppercase digits */
		var byte_value = clamp_byte(raw_value);
		return hex_digit(floor(byte_value / 16)) + hex_digit(byte_value mod 16);
	}

	/// @description Decode one hex character, using zero for invalid text
	/// @param {String} raw_char Hex character
	/// @returns {Real} Four-bit value
	hex_value = function(raw_char)
	{
		/* Convert the one-based hex-digit lookup into a four-bit value, using zero for unrecognized text */
		var digit_index = string_pos(string_upper(string(raw_char)), "0123456789ABCDEF");
		return max(0, digit_index - 1);
	}

	/// @description Decode two adjacent hex characters
	/// @param {String} hex_text Source text
	/// @param {Real} offset One-based first-character position
	/// @returns {Real} Byte value. Invalid digits contribute zero
	hex_pair_to_byte = function(hex_text, offset)
	{
		return hex_value(string_char_at(hex_text, offset)) * 16 + hex_value(string_char_at(hex_text, offset + 1));
	}

	/// @description Serialize rows in RRGGBBAA channel order for the PNG helper and editor saves
	/// @returns {String} Eight uppercase hex characters per pixel
	to_hex_string = function()
	{
		/* Start the serialized pixel text empty */
		var hex_text = "";

		/* Serialize every zero-based packed pixel in row-major order */
		for (var pixel_index = 0; pixel_index < array_length(pixels); pixel_index++)
		{
			/* Read the packed pixel once before extracting red, green, blue and alpha for RRGGBBAA output */
			var pixel_value = pixels[pixel_index];
			hex_text += byte_to_hex(pixel_red(pixel_value))
				+ byte_to_hex(pixel_green(pixel_value))
				+ byte_to_hex(pixel_blue(pixel_value))
				+ byte_to_hex(pixel_alpha(pixel_value));
		}

		return hex_text;
	}

	/// @description Load the current canvas from row-major RRGGBBAA hex. Does not create an undo snapshot
	/// @param {String} hex_text At least grid_w * grid_h * 8 characters. Callers validate source data
	/// @returns {Bool} Whether enough pixel data was supplied
	load_hex_string = function(hex_text)
	{
		/* Normalize source case, and expected_chars requires eight text characters per current canvas pixel */
		var clean_hex = string_upper(string(hex_text));
		var expected_chars = grid_w * grid_h * 8;

		/* Reject short text before modifying pixels
		Digit validity and trailing characters are left to callers */
		if (string_length(clean_hex) < expected_chars)
		{
			return false;
		}

		/* Decode the current canvas's zero-based pixel count, ignoring any trailing source text */
		for (var pixel_index = 0; pixel_index < array_length(pixels); pixel_index++)
		{
			/* Compute the one-based first character of this pixel's eight-character RGBA record */
			var hex_offset = pixel_index * 8 + 1;
			pixels[pixel_index] = pack_rgba(
				hex_pair_to_byte(clean_hex, hex_offset),
				hex_pair_to_byte(clean_hex, hex_offset + 2),
				hex_pair_to_byte(clean_hex, hex_offset + 4),
				hex_pair_to_byte(clean_hex, hex_offset + 6)
			);
		}

		return true;
	}

	/// @description Extract sprite subimage zero and resize the editor before loading pixels
	/// @param {Asset.GMSprite} source_sprite Borrowed source sprite
	/// @param {Real} alpha_cutoff Transparent-black byte threshold. Defaults to 0
	/// @returns {Bool} Whether extraction and loading succeeded. Resize creates undo only if dimensions change
	load_from_sprite = function(source_sprite, alpha_cutoff = 0)
	{
		/* Reject missing source sprites before reading dimensions or allocating extraction resources */
		if (!sprite_exists(source_sprite))
		{
			return false;
		}

		/* Use the source sprite's positive pixel dimensions, and loaded_region holds the PNG helper's extracted RGBA result */
		var source_w = max(1, sprite_get_width(source_sprite));
		var source_h = max(1, sprite_get_height(source_sprite));
		var loaded_region = RgbaPng.sprite_region_to_rgba_hex(source_sprite, 0, 0, source_w, source_h, alpha_cutoff);

		/* Failed extraction leaves the editor size and pixels unchanged */
		if (!loaded_region.ok)
		{
			return false;
		}

		resize_canvas(source_w, source_h);
		return load_hex_string(loaded_region.hex);
	}

	/// @description Extract a sprite crop and resize the editor before loading pixels
	/// @param {Asset.GMSprite} source_sprite Borrowed source sprite
	/// @param {Real} source_x Crop left in pixels
	/// @param {Real} source_y Crop top in pixels
	/// @param {Real} source_w Crop width in pixels
	/// @param {Real} source_h Crop height in pixels
	/// @param {Real} alpha_cutoff Transparent-black byte threshold. Defaults to 0
	/// @returns {Bool} Whether extraction and loading succeeded. Resize creates undo only if dimensions change
	load_from_sprite_region = function(source_sprite, source_x, source_y, source_w, source_h, alpha_cutoff = 0)
	{
		/* Reject missing source sprites before attempting a crop */
		if (!sprite_exists(source_sprite))
		{
			return false;
		}

		/* safe_w/safe_h normalize crop dimensions, and loaded_region holds the RGBA extraction result */
		var safe_w = max(1, floor(real(source_w)));
		var safe_h = max(1, floor(real(source_h)));
		var loaded_region = RgbaPng.sprite_region_to_rgba_hex(source_sprite, source_x, source_y, safe_w, safe_h, alpha_cutoff);

		/* Failed crop extraction leaves the canvas intact */
		if (!loaded_region.ok)
		{
			return false;
		}

		resize_canvas(safe_w, safe_h);
		return load_hex_string(loaded_region.hex);
	}
	#endregion /* Pixel Serialization and Sprite Import END */

	/// @description Clear and draw pixels into a caller-owned surface, then reset the surface target
	/// @param {Id.Surface} target_surface Borrowed existing surface sized to contain the canvas
	/// @returns {Bool} Whether the surface exists and was drawn
	draw_to_surface = function(target_surface)
	{
		/* A missing borrowed target cannot receive canvas pixels */
		if (!surface_exists(target_surface))
		{
			return false;
		}

		surface_set_target(target_surface);
		draw_clear_alpha(c_black, 0);

		/* Traverse zero-based canvas rows into the borrowed target */
		for (var pixel_row = 0; pixel_row < grid_h; pixel_row++)
		{
			/* Draw each zero-based cell within the current row */
			for (var pixel_col = 0; pixel_col < grid_w; pixel_col++)
			{
				/* Read the packed row-major value and extract its byte alpha before deciding whether to draw */
				var pixel_value = pixels[pixel_row * grid_w + pixel_col];
				var alpha_value = pixel_alpha(pixel_value);

				/* Visible pixels draw with their byte alpha divided by 255, while transparent cells retain the cleared target */
				if (alpha_value > 0)
				{
					draw_set_alpha(alpha_value / 255);
					draw_set_colour(make_color_rgb(pixel_red(pixel_value), pixel_green(pixel_value), pixel_blue(pixel_value)));
					draw_rectangle(pixel_col, pixel_row, pixel_col + 1, pixel_row + 1, false);
				}
			}
		}
		draw_set_alpha(1);
		surface_reset_target();
		return true;
	}

	/// @description Draw a transparency checkerboard, artwork and optional cell boundaries
	/// @param {Real} draw_left Left in caller drawing coordinates
	/// @param {Real} draw_top Top in caller drawing coordinates
	/// @param {Real} cell_size Displayed pixels per canvas cell, at least one
	/// @param {Real} draw_alpha Overall opacity. Defaults to 1
	/// @param {Bool} show_grid Draw boundary lines. Defaults to false
	/// @returns {Bool} Always true. Leaves draw alpha at 1
	draw_pixels = function(draw_left, draw_top, cell_size, draw_alpha = 1, show_grid = false)
	{
		/* Clamp displayed cell width/height to at least one drawing-coordinate pixel */
		var safe_cell_size = max(1, real(cell_size));

		/* Traverse zero-based rows for checkerboard and pixel rendering */
		for (var pixel_row = 0; pixel_row < grid_h; pixel_row++)
		{
			/* Draw each zero-based column at its scaled display position */
			for (var pixel_col = 0; pixel_col < grid_w; pixel_col++)
			{
				/* Alternate checker shades from row-plus-column parity, making transparency visible beneath artwork */
				var checker_even = ((pixel_col + pixel_row) mod 2) == 0;
				draw_set_alpha(draw_alpha);
				draw_set_colour(checker_even ? make_color_rgb(214, 214, 218) : make_color_rgb(164, 166, 172));
				draw_rectangle(draw_left + pixel_col * safe_cell_size, draw_top + pixel_row * safe_cell_size, draw_left + (pixel_col + 1) * safe_cell_size, draw_top + (pixel_row + 1) * safe_cell_size, false);

				/* Borrow the cell's packed colour and extract byte alpha for compositing over its checkerboard */
				var pixel_value = get_pixel(pixel_col, pixel_row);
				var alpha_value = pixel_alpha(pixel_value);

				/* Visible cells multiply their alpha by draw_alpha, while transparent cells show only the checkerboard */
				if (alpha_value > 0)
				{
					draw_set_alpha(draw_alpha * alpha_value / 255);
					draw_set_colour(make_color_rgb(pixel_red(pixel_value), pixel_green(pixel_value), pixel_blue(pixel_value)));
					draw_rectangle(draw_left + pixel_col * safe_cell_size, draw_top + pixel_row * safe_cell_size, draw_left + (pixel_col + 1) * safe_cell_size, draw_top + (pixel_row + 1) * safe_cell_size, false);
				}
			}
		}

		/* Draw cell boundary lines only when the caller requests the grid overlay */
		if (show_grid)
		{
			draw_set_alpha(draw_alpha * 0.35);
			draw_set_colour(c_black);

			/* Include columns zero through grid_w so both outside vertical edges and every internal boundary are drawn */
			for (var grid_col = 0; grid_col <= grid_w; grid_col++)
			{
				draw_line(draw_left + grid_col * safe_cell_size, draw_top, draw_left + grid_col * safe_cell_size, draw_top + grid_h * safe_cell_size);
			}

			/* Include rows zero through grid_h for all horizontal boundaries */
			for (var grid_row = 0; grid_row <= grid_h; grid_row++)
			{
				draw_line(draw_left, draw_top + grid_row * safe_cell_size, draw_left + grid_w * safe_cell_size, draw_top + grid_row * safe_cell_size);
			}
		}

		draw_set_alpha(1);
		return true;
	}
}
