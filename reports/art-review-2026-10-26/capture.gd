extends Node

func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	var story := Game.Adventure.load_world("res://worlds/story/world.json")
	var examples := {}
	for key in story.rooms:
		var theme: String = story.rooms[key].level.get("environment", "")
		if not examples.has(theme): examples[theme] = key
	for key in ["l3_treetop_village", "s3_lighthouse_top", "i06_crater", "i17_crystal_pocket"]:
		if story.rooms.has(key): examples[key] = key
	for label in examples:
		Game.adv = {}
		var level: Dictionary = story.rooms[examples[label]].level.duplicate(true)
		Game.play(level, true)
		for i in 30: await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://reports/art-review-2026-10-26/runtime/settled_" + label + ".png")
		print("CAPTURE ", label)
	print("ART CAPTURE OK")
	get_tree().quit()
