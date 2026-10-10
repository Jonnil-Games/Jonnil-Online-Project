/// @description Forward asynchronous text dialogs to the drawing system

/* Borrow the drawing service that owns pending asynchronous text-entry dialogs */
var drawing = scr_get_drawing();

/* Only drawing state with the text-dialog completion member can claim this event.
Missing support skips dialog dispatch rather than accessing unavailable state */
if (is_struct(drawing)
&& variable_struct_exists(drawing, "handle_text_dialog_async"))
{
	/* Capture the drawing-bound dialog handler before checking that it can be called */
	var dialog_handler = drawing.handle_text_dialog_async;

	/* Forward the dialog result only through a callable method. A malformed member
	must not interrupt the asynchronous event or mutate pending text */
	if (is_method(dialog_handler))
	{
		dialog_handler(async_load);
	}
}
