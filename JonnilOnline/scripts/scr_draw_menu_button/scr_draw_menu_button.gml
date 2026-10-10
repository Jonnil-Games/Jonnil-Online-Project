/* Shared menu-button shape, transparency and icon identifiers */
#macro JONNIL_MENU_BUTTON_RECTANGLE 0
#macro JONNIL_MENU_BUTTON_ROUND 1
#macro JONNIL_MENU_BUTTON_OPAQUE 0
#macro JONNIL_MENU_BUTTON_SEE_THROUGH 1
#macro JONNIL_MENU_BUTTON_OUTLINES_ONLY 2
#macro JONNIL_MENU_BUTTON_INVISIBLE 3
#macro JONNIL_MENU_ICON_OPTIONS "options"
#macro JONNIL_MENU_ICON_QUIT "quit"
#macro JONNIL_MENU_ICON_INFORMATION "information"

/// @function scr_menu_button_default_theme()
/// @description Create a fresh copy of the authored button theme
/// @returns {Struct} Theme with colour, shape, transparency and focus colour
function scr_menu_button_default_theme()
{
	/* Each call returns independent theme fields, so an editor can change colour without mutating another copy
	The authored default_colour remains the reset reference, colour is the active fill, shape selects rounded edges,
	transparency starts opaque, and focus_colour marks keyboard or gamepad selection */
	return
	{
		default_colour: make_color_rgb(72, 176, 214),
		colour: make_color_rgb(72, 176, 214),
		shape: JONNIL_MENU_BUTTON_ROUND,
		transparency: JONNIL_MENU_BUTTON_OPAQUE,
		focus_colour: make_color_rgb(255, 220, 95)
	};
}

/// @function scr_menu_button_reset_theme()
/// @description Replace global.menu_button_theme with the authored default
/// @returns {Struct} Newly assigned theme
function scr_menu_button_reset_theme()
{
	/* Replacing the shared theme discards previous custom settings and makes the authored colours active again */
	global.menu_button_theme = scr_menu_button_default_theme();
	return global.menu_button_theme;
}

/// @function scr_menu_button_set_theme(colour, shape, transparency)
/// @description Apply the selected button design to global.menu_button_theme
/// @param {Real} colour GameMaker color value
/// @param {Real} shape JONNIL_MENU_BUTTON_* shape value, rounded and clamped
/// @param {Real} transparency JONNIL_MENU_BUTTON_* transparency value, rounded and clamped
/// @returns {Struct} Newly assigned theme
function scr_menu_button_set_theme(colour, shape, transparency)
{
	/* Start with a fresh authored theme so omitted fields retain their defaults, then apply the caller's colour
	Shape and transparency are rounded and clamped to the supported identifier ranges */
	var theme = scr_menu_button_default_theme();
	theme.colour = colour;
	theme.shape = clamp(round(shape), JONNIL_MENU_BUTTON_RECTANGLE, JONNIL_MENU_BUTTON_ROUND);
	theme.transparency = clamp(round(transparency), JONNIL_MENU_BUTTON_OPAQUE, JONNIL_MENU_BUTTON_INVISIBLE);
	global.menu_button_theme = theme;
	return theme;
}

/// @function scr_menu_button_get_theme()
/// @description Return the active theme, creating the authored default when needed
/// @returns {Struct} Shared global.menu_button_theme
function scr_menu_button_get_theme()
{
	/* Check existence before reading the global, then replace a missing or non-struct theme so callers receive usable fields */
	if (!variable_global_exists("menu_button_theme")
	|| !is_struct(global.menu_button_theme))
	{
		scr_menu_button_reset_theme();
	}
	return global.menu_button_theme;
}

/// @function scr_draw_menu_icon(icon, x, y, size, colour, alpha)
/// @description Draw a built-in icon or sprite. Changes draw alpha and colour
/// @param {Any} icon JONNIL_MENU_ICON_* string or sprite asset. Empty values skip drawing
/// @param {Real} x Horizontal centre in the caller's drawing coordinates
/// @param {Real} y Vertical centre in the caller's drawing coordinates
/// @param {Real} size Maximum icon dimension in pixels
/// @param {Real} colour GameMaker color value, defaulting to c_white
/// @param {Real} alpha Opacity from 0 to 1, defaulting to 1 for full opacity
/// @returns {Bool} Whether the icon was recognised and drawn
function scr_draw_menu_icon(icon, x, y, size, colour = c_white, alpha = 1)
{
	/* An absent icon, noone, or an empty name reserves no icon space and leaves drawing state untouched */
	if (is_undefined(icon)
	|| icon == noone
	|| string(icon) == "")
	{
		return false;
	}

	draw_set_alpha(alpha);
	draw_set_colour(colour);

	/* Only non-string sprite assets take the sprite path, so named built-in icons are never passed to sprite_exists */
	if (!is_string(icon)
	&& sprite_exists(icon))
	{
		/* The sprite dimensions are clamped to at least one pixel to prevent division by zero
		sprite_scale fits its longest side into size, while sprite_x and sprite_y compensate for the asset origin
		so the displayed image is centred on the requested coordinates */
		var icon_sprite_width = max(1, sprite_get_width(icon));
		var icon_sprite_height = max(1, sprite_get_height(icon));
		var sprite_scale = size / max(icon_sprite_width, icon_sprite_height);
		var sprite_x = x + (sprite_get_xoffset(icon) - icon_sprite_width * 0.5) * sprite_scale;
		var sprite_y = y + (sprite_get_yoffset(icon) - icon_sprite_height * 0.5) * sprite_scale;
		draw_sprite_ext(icon, 0, sprite_x, sprite_y, sprite_scale, sprite_scale, 0, colour, alpha);
		return true;
	}

	/* Normalize built-in names for case-insensitive matching
	half is half the requested pixel size and anchors the hand-drawn icon geometry */
	var icon_name = string_lower(string(icon));
	var half = size * 0.5;

	/* The options name draws a gear from eight spokes and two outline circles */
	if (icon_name == JONNIL_MENU_ICON_OPTIONS)
	{
		/* spoke_inner and spoke_outer set the radial ends of each gear tooth in pixels
		spoke_width keeps the teeth visible at small sizes */
		var spoke_inner = size * 0.25;
		var spoke_outer = size * 0.43;
		var spoke_width = max(2, size * 0.09);

		/* Draw eight equally spaced teeth, with spoke indexing the 45-degree rotations around the centre */
		for (var spoke = 0; spoke < 8; spoke++)
		{
			/* Convert the tooth index into GameMaker direction degrees for the radial endpoints */
			var spoke_direction = spoke * 45;
			draw_line_width(
				x + lengthdir_x(spoke_inner, spoke_direction),
				y + lengthdir_y(spoke_inner, spoke_direction),
				x + lengthdir_x(spoke_outer, spoke_direction),
				y + lengthdir_y(spoke_outer, spoke_direction),
				spoke_width
			);
		}
		draw_circle(x, y, size * 0.29, true);
		draw_circle(x, y, size * 0.11, true);
		return true;
	}

	/* The quit name draws a door and an outward arrow to identify the exit action */
	if (icon_name == JONNIL_MENU_ICON_QUIT)
	{
		/* These left, right, top and bottom coordinates bound the door in the caller's drawing space */
		var door_left = x - half * 0.72;
		var door_right = x + half * 0.04;
		var door_top = y - half * 0.72;
		var door_bottom = y + half * 0.72;
		draw_rectangle(door_left, door_top, door_right, door_bottom, true);
		draw_circle(door_left + (door_right - door_left) * 0.72, y, max(1, size * 0.045), false);

		/* arrow_left and arrow_right position the exit arrow horizontally across the door's right side */
		var arrow_left = x - size * 0.05;
		var arrow_right = x + half * 0.78;
		draw_line_width(arrow_left, y, arrow_right, y, max(2, size * 0.08));
		draw_line_width(arrow_right, y, arrow_right - size * 0.20, y - size * 0.18, max(2, size * 0.08));
		draw_line_width(arrow_right, y, arrow_right - size * 0.20, y + size * 0.18, max(2, size * 0.08));
		return true;
	}

	/* The information name draws a circled lowercase i, using the same centre and pixel-size scale */
	if (icon_name == JONNIL_MENU_ICON_INFORMATION)
	{
		draw_circle(x, y, half * 0.82, true);
		draw_circle(x, y - size * 0.20, max(1, size * 0.055), false);
		draw_line_width(x, y - size * 0.04, x, y + size * 0.25, max(2, size * 0.09));
		return true;
	}

	/* Unrecognized icon names report no drawing, allowing the button label to use the full content area */
	return false;
}

/// @function scr_draw_menu_button(x, y, width, height, label, hovered, focused, enabled, subdued, danger, text_height, theme, icon)
/// @description Draw a themed button. The caller handles input and supplies hover and focus state
/// @param {Real} x Left edge in the caller's drawing coordinates
/// @param {Real} y Top edge in the caller's drawing coordinates
/// @param {Real} width Button width in pixels
/// @param {Real} height Button height in pixels
/// @param {String} label Visible button text
/// @param {Bool} hovered Whether the pointer is over the button, defaulting to false
/// @param {Bool} focused Whether keyboard/gamepad selection is on the button, defaulting to false
/// @param {Bool} enabled Use the enabled appearance, defaulting to true. Input eligibility is enforced separately
/// @param {Bool} subdued Dim the base color, defaulting to false
/// @param {Bool} danger Use warning color instead of base color, defaulting to false
/// @param {Real} text_height Requested text height in pixels, defaulting to 20
/// @param {Struct} theme Theme override, defaulting to undefined for the global theme
/// @param {Any} icon Built-in icon string or sprite asset, defaulting to undefined for no icon
/// Drawing finishes with alpha 1, white colour, left alignment and top vertical alignment.
function scr_draw_menu_button(x, y, width, height, label, hovered = false, focused = false, enabled = true, subdued = false, danger = false, text_height = 20, theme = undefined, icon = undefined)
{
	/* A missing or non-struct override uses the shared theme instead of attempting field access on invalid data */
	if (is_undefined(theme)
	|| !is_struct(theme))
	{
		theme = scr_menu_button_get_theme();
	}

	/* Read each optional theme field only when present, otherwise use its authored fallback
	base_colour controls the palette, shape selects rectangle or rounded geometry, transparency controls visibility,
	and focus_colour distinguishes keyboard or gamepad focus */
	var base_colour = variable_struct_exists(theme, "colour")
		? theme.colour
		: make_color_rgb(72, 176, 214);
	var shape = variable_struct_exists(theme, "shape")
		? theme.shape
		: JONNIL_MENU_BUTTON_ROUND;
	var transparency = variable_struct_exists(theme, "transparency")
		? theme.transparency
		: JONNIL_MENU_BUTTON_OPAQUE;
	var focus_colour = variable_struct_exists(theme, "focus_colour")
		? theme.focus_colour
		: make_color_rgb(255, 220, 95);

	/* Either pointer hover or explicit focus highlights the button */
	var selected = hovered || focused;

	/* Danger takes priority over subdued styling and replaces the base colour with the warning red */
	if (danger)
	{
		base_colour = make_color_rgb(128, 55, 60);
	}

	/* Without danger styling, subdued buttons blend toward grey to reduce their visual prominence */
	else if (subdued)
	{
		base_colour = merge_color(base_colour, make_color_rgb(70, 72, 78), 0.68);
	}

	/* fill_colour darkens the base, border_colour lightens it, and text_colour controls label contrast
	Disabled buttons use stronger darkening, a dimmer border and grey text */
	var fill_colour = merge_color(base_colour, c_black, enabled ? 0.24 : 0.62);
	var border_colour = merge_color(base_colour, c_white, enabled ? 0.48 : 0.12);
	var text_colour = enabled ? c_white : make_color_rgb(126, 128, 134);

	/* Hover or focus brightens the fill, with a smaller change for disabled buttons
	Keyboard or gamepad focus uses focus_colour on the border, while pointer-only hover uses the lightened base */
	if (selected)
	{
		fill_colour = enabled
			? merge_color(base_colour, c_white, 0.18)
			: merge_color(fill_colour, c_white, 0.08);
		border_colour = focused ? focus_colour : merge_color(base_colour, c_white, 0.72);
	}

	/* fill_alpha and border_alpha start with enabled or dimmed disabled opacity before transparency styling is applied */
	var fill_alpha = enabled ? 0.96 : 0.72;
	var border_alpha = enabled ? 1 : 0.65;

	/* See-through styling reduces fill opacity while retaining the border */
	if (transparency == JONNIL_MENU_BUTTON_SEE_THROUGH)
	{
		fill_alpha *= 0.38;
	}

	/* Outline-only styling skips the fill and leaves the border visible */
	else if (transparency == JONNIL_MENU_BUTTON_OUTLINES_ONLY)
	{
		fill_alpha = 0;
	}

	/* Invisible styling hides both background and border so only the contents remain */
	else if (transparency == JONNIL_MENU_BUTTON_INVISIBLE)
	{
		fill_alpha = 0;
		border_alpha = 0;

		/* An enabled invisible button still signals hover or focus by changing the text to the focus colour */
		if (selected && enabled)
		{
			text_colour = focus_colour;
		}
	}

	/* right and bottom convert the supplied width and height into drawing edges
	radius scales the corner rounding with button height, constrained between 2 and 12 pixels */
	var right = x + width;
	var bottom = y + height;
	var radius = min(12, max(2, height * 0.5));

	/* Draw the background only when its effective opacity is visible */
	if (fill_alpha > 0)
	{
		draw_set_alpha(fill_alpha);
		draw_set_colour(fill_colour);

		/* Rounded themes use curved fill corners */
		if (shape == JONNIL_MENU_BUTTON_ROUND)
		{
			draw_roundrect_color_ext(x, y, right, bottom, radius, radius, fill_colour, fill_colour, false);
		}

		/* Rectangle themes draw the same filled bounds with square corners */
		else
		{
			draw_rectangle(x, y, right, bottom, false);
		}
	}

	/* Draw the outline only when its opacity remains visible after transparency styling */
	if (border_alpha > 0)
	{
		draw_set_alpha(border_alpha);
		draw_set_colour(border_colour);

		/* Match the border's curved corners to the rounded fill */
		if (shape == JONNIL_MENU_BUTTON_ROUND)
		{
			draw_roundrect_color_ext(x, y, right, bottom, radius, radius, border_colour, border_colour, true);
		}

		/* Square themes outline the rectangular bounds */
		else
		{
			draw_rectangle(x, y, right, bottom, true);
		}
	}

	draw_set_alpha(1);

	/* icon_size fits the icon to button height within a 16-to-26-pixel range
	icon_drawn records whether the requested icon was recognized, which determines how much label space to reserve */
	var icon_size = min(26, max(16, height - 18));
	var icon_drawn = scr_draw_menu_icon(icon, x + max(18, height * 0.5), y + height * 0.5, icon_size, text_colour, 1);
	draw_set_alpha(1);
	draw_set_halign(fa_center);
	draw_set_valign(fa_top);
	draw_set_colour(text_colour);

	/* Convert the supplied label to text before deciding whether there is anything to render */
	var label_text = string(label);

	/* Empty labels skip text drawing while keeping any icon and background already rendered */
	if (label_text != "")
	{
		/* label_left and label_right reserve ten-pixel side margins in the caller's drawing space */
		var label_left = x + 10;
		var label_right = x + width - 10;

		/* Reserve space to the right of a drawn icon, capped at the button centre so some text width remains */
		if (icon_drawn)
		{
			label_left = min(x + width * 0.5, x + max(height + 4, icon_size + 24));
		}

		/* Keep the available text width at least one pixel, then centre and scale the label within those bounds */
		var label_width = max(1, label_right - label_left);
		scr_render_text(label_left + label_width * 0.5, y + max(1, (height - text_height) * 0.5 - 1), label_text, text_height, label_width);
	}
	draw_set_halign(fa_left);
	draw_set_colour(c_white);
}
