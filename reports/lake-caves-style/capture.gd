extends Node
func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	for name in ["c0_roar_tunnel", "c1_lake_cave", "c2_cave_teeth", "c3_cove_tunnel", "c4_deep_lake"]:
		Game.adv = {}
		Game.play(Game.load_level(name, "res://worlds/story/"), true)
		var world = get_child(get_child_count()-1)
		if name == "c1_lake_cave": world.player.pos = Vector2(360,144)
		for i in 45: await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://reports/lake-caves-style/" + name + "-runtime.png")
	print("LAKE CAVES CAPTURE OK")
	Game.quit_game(0)
