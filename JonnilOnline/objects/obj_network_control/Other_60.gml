/// @description Dispatch asynchronous image loading to characters before drawing images

/* Let the character service inspect this image-load completion first.
image_loaded_handled records whether the event belongs to a character request,
so the same completion is not also applied as a shared-canvas image */
var image_loaded_handled = player_character_handle_image_loaded(async_load);

/* Only an image completion unclaimed by characters is offered to drawing.
A claimed character image keeps its own installation and resource ownership */
if (!image_loaded_handled)
{
	/* Borrow the canvas image-loading service for the remaining asynchronous request */
	var drawing = scr_get_drawing();

	/* Dispatch unclaimed image events only when drawing state and its completion
	handler exist. Otherwise leave this event without a canvas update */
	if (is_struct(drawing)
	&& variable_struct_exists(drawing, "handle_image_loaded"))
	{
		drawing.handle_image_loaded(async_load);
	}
}
