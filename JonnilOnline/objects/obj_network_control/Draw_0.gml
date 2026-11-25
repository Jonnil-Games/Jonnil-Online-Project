/// @description Draw the client world and player overlays through the world camera

/* Begin the frame performance sample before world rendering so GUI diagnostics
can report the current rendering workload */
scr_ui_perf_frame_begin();

/* Draw the world only for the client view, including the visible client in Host
& Play. Dedicated server mode skips camera, canvas, players and chat overlays */
if (is_client)
{
	network_camera_draw_world();
	scr_get_drawing().draw_world();
	scr_get_walls().draw_world();
	scr_get_drawing().draw_brush_world_preview();
	scr_get_collision_objects().draw_world();
	player_controller_render_all_players();
	scr_get_chat().draw_speech_bubbles(network_camera);
	scr_get_chat().draw_typing_indicators(network_camera);
	scr_get_chat().draw_afk_indicators(network_camera);
}
