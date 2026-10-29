extends Node
func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	var story: Dictionary = Game.Adventure.load_world("res://worlds/story/world.json")
	for sample in [["i02_north_shore", "shore"], ["i03_south_shore", "shore"], ["i09_sea_cave", "upper"], ["i09_sea_cave", "lower"]]:
		var name: String = sample[0]
		Game.playtest_adventure(story, name)
		await get_tree().process_frame
		var world = get_child(get_child_count()-1)
		world.set_physics_process(false)
		world.set_process(false)
		for e in world.ents:
			if e.d.get("skin", "") == "signpost":
				world.player.pos = Vector2(e.rect.get_center().x+10, e.rect.end.y)
				e.near = 1.0
		if name == "i09_sea_cave":
			world.player.pos = Vector2(64, 64 if sample[1] == "upper" else 320)
		world.cam_pos = world.cam_goal()
		world.snap_interp()
		world.cam.position = world.cam_pos.round()
		world.mask_a = 1.0
		world.reveal_t = 1.0
		world.queue_redraw()
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://reports/island-connections/"+name+"-"+sample[1]+".png")
	print("ISLAND CONNECTION CAPTURE OK")
	Game.quit_game(0)
