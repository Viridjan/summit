extends Node
# Review-only captures of Story rooms. Uses temporary adventure progress; no normal saves are written.
# Invincibility is enabled for stable visual inspection, not as evidence of level survivability.
func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	get_window().size = Vector2i(1280,720)
	var story := Game.Adventure.load_world("res://worlds/story/world.json")
	for room in ["m1_meadow", "j1_jungle_edge", "a1_ape_arena", "s1_sand_cave", "s3_lighthouse_top", "i06_crater", "i17_crystal_pocket"]:
		if not story.rooms.has(room):
			continue
		Game.playtest_adventure(story,room)
		for tick in 90:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://reports/quality-review-2026-10-27/"+room+".png")
		print("CAPTURE ",room)
	print("STORY REVIEW CAPTURES OK")
	get_tree().quit()
