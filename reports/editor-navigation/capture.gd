extends Node
func _ready() -> void:
	Game.main = self
	Game.world_path = Game.STORY_WORLD
	Game.editor_return = "world_editor"
	Game.editor_dir = "res://worlds/story/"
	Game.editor_file = "i02_north_shore"
	Game.editor_level = Game.load_level(Game.editor_file, Game.editor_dir)
	Game.goto("editor")
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/editor-navigation/buttons.png")
	var editor = get_child(get_child_count()-1)
	editor.level.name += " edited"
	editor._request_room("i01_west_shore")
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/editor-navigation/save-prompt.png")
	Game.quit_game(0)
