extends Node
const Entities := preload("res://scripts/entities.gd")

func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	Game.settings.hitboxes = false
	Game.play(Game.load_level("a1_ape_arena", "res://worlds/story/"), true)
	for i in 2: await get_tree().physics_frame
	var world = get_child(get_child_count() - 1)
	world.set_physics_process(false)
	world.set_process(false)
	for boss in world.ents:
		if not boss is Entities.Ape: continue
		boss.hp = 2
		boss.phase = "idle"
		boss.slam_t = 0
		boss.flash = 0
		boss.facing = -1
		for sample in [["red", 0.125], ["normal", 0.375]]:
			boss.clock = sample[1]
			world.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://reports/ape-red-pulse/" + sample[0] + ".png")
	print("APE RED PULSE CAPTURE OK")
	Game.quit_game(0)
