/// @description Draw local account identity only inside its screen's reserved row
if (managed_dedicated_server || !variable_instance_exists(id, "accounts")) return;
var account_bounds = account_status_layout();
if (!is_struct(account_bounds)) return;

var previous_alpha = draw_get_alpha();
var previous_colour = draw_get_colour();
var previous_halign = draw_get_halign();
var previous_valign = draw_get_valign();
var previous_font = draw_get_font();
draw_set_alpha(0.94);
draw_set_colour(make_color_rgb(18, 21, 25));
draw_rectangle(account_bounds.x - 8, account_bounds.y - 4,
	account_bounds.x + account_bounds.width + 8, account_bounds.bottom + 4, false);
draw_set_alpha(1);
draw_set_colour(account_bounds.active ? make_color_rgb(170, 220, 182) : make_color_rgb(210, 213, 220));
draw_set_halign(fa_left);
draw_set_valign(fa_top);
scr_render_text_wrapped(account_bounds.x, account_bounds.y, account_bounds.label, 16, account_bounds.width, 3);
draw_set_font(previous_font);
draw_set_halign(previous_halign);
draw_set_valign(previous_valign);
draw_set_colour(previous_colour);
draw_set_alpha(previous_alpha);
