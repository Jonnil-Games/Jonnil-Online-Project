/* Clear in-memory account authority before application shutdown */
if (variable_instance_exists(id, "account_menu"))
{
	account_menu.sync_flush_local();
	account_menu.password = "";
}
if (variable_instance_exists(id, "accounts")) accounts.shutdown();
keyboard_string = "";

/* This controller is the sole owner of the initialized Discord client */
jonnil_discord_extension_finalize();
if (variable_instance_exists(id, "presence") && is_struct(presence)) presence.handoff.close();

/// @description Save pending zoom settings, release the grid surface, and shut down server logging

/* Flush a final held +/- adjustment before the application closes */
if (network_camera_zoom_settings_dirty)
{
	network_camera_save_zoom_settings();
}

/* Release the controller-owned cached grid only if its GPU surface still exists.
Surface loss can invalidate this handle before shutdown, so never free a missing surface */
if (surface_exists(network_world_grid_surface))
{
	surface_free(network_world_grid_surface);
	network_world_grid_surface = -1;
}

/* Borrow the server service for application-exit cleanup. This reference is the
server state struct, separate from its owned network listener handles */
var closing_server = scr_get_server();

/* Shut down only an available, running server that exposes the shutdown method.
Request its shutdown archive before logging stops. Inactive client-only server
state needs no hosting cleanup */
if (is_struct(closing_server)
&& variable_struct_exists(closing_server, "is_running")
&& closing_server.is_running()
&& variable_struct_exists(closing_server, "shutdown"))
{
	closing_server.shutdown("application_exit", true);
}

/* Stop the server log capture after server shutdown has written its final messages */
scr_server_logs_stop("Application exit.");

/* Release the runtime font handles after the final shutdown messages */
scr_render_text_font_cleanup();
