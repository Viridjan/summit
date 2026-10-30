extends Node
func _ready() -> void:
	Game.main = self
	Game.world_path = Game.STORY_WORLD
	Game.goto("world_editor")
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/progression-review-2026-10-30/world-editor.png")
	Game.quit_game(0)
