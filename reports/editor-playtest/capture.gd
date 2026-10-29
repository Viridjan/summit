extends Node
func _ready() -> void:
	Game.main = self
	Game.editor_level = Game.load_level("c1_lake_cave", "res://worlds/story/")
	Game.goto("editor")
	await get_tree().process_frame
	var editor = get_child(get_child_count()-1)
	editor._playtest()
	for i in 3: await get_tree().process_frame
	var world = get_child(get_child_count()-1)
	world.set_physics_process(false)
	world.set_process(false)
	world.player.pos = Vector2(12,336)
	world.cam_pos = world.cam_goal()
	world.snap_interp()
	world.cam.position = world.cam_pos.round()
	world.mask_a = 1.0
	world.reveal_t = 1.0
	world.queue_redraw()
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/editor-playtest/hidden-respawn.png")
	Game.quit_game(0)
