extends Node
func _ready() -> void:
	Game.main = self
	var story: Dictionary = Game.Adventure.load_world(Game.STORY_WORLD)
	for after in [false,true]:
		Game.playtest_adventure(story,"j3_jungle_hills")
		await get_tree().process_frame
		var world = get_child(get_child_count()-1)
		world.set_physics_process(false)
		world.set_process(false)
		if after: world.broken["a1_ape_arena:ape_144_120"]=true
		for entity in world.ents:
			if entity.d.t=="boss_gate":entity.update(0)
		world.player.pos=Vector2(424,120)
		world.cam_pos=world.cam_goal()
		world.snap_interp()
		world.cam.position=world.cam_pos.round()
		world.mask_a=1.0
		world.reveal_t=1.0
		world.queue_redraw()
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://reports/ape-return-barrier/"+("after" if after else "before")+".png")
	Game.quit_game(0)
