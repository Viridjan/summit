extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func wheel(at: Vector2, direction: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = direction
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
func check_help(node: Node) -> void:
	if node is Button and not node.text.is_empty():
		check(not node.tooltip_text.is_empty(), "Hover help exists for " + node.text)
	for child in node.get_children(): check_help(child)
func _ready() -> void:
	Game.main = self
	Game.editor_return = "menu"
	Game.editor_level = Game.new_level()
	Game.goto("editor")
	await get_tree().process_frame
	await get_tree().process_frame
	var editor = get_child(get_child_count()-1)
	check_help(editor.ui)
	var initial_spawns: int = editor.level.entities.filter(func(e): return e.t == "spawn").size()
	editor._push_undo()
	editor.tool = "spawn"
	editor._place_point(Vector2i(8,8))
	check(editor.level.entities.filter(func(e): return e.t == "spawn").size() == initial_spawns+1, "Manual Spawn placement preserves existing respawns")
	editor._undo()
	check(editor.level.entities.filter(func(e): return e.t == "spawn").size() == initial_spawns, "Undo restores spawn markers")
	editor.clip = {"w":1,"h":1,"tiles":["0"],"entities":[{"t":"spawn","x":0,"y":0}]}
	editor._paste(Vector2i(9,8))
	check(editor.level.entities.filter(func(e): return e.t == "spawn").size() == initial_spawns+1, "Pasting a Spawn preserves existing respawns")
	editor.clip = {}
	editor._undo()
	var zoom: Vector2 = editor.cam.zoom
	var position: Vector2 = editor.cam.position
	await wheel(Vector2(80,300), MOUSE_BUTTON_WHEEL_UP)
	await wheel(Vector2(80,300), MOUSE_BUTTON_WHEEL_DOWN)
	check(editor.cam.zoom == zoom and editor.cam.position == position, "Room palette scrolling never moves or zooms the room")
	await wheel(Vector2(600,16), MOUSE_BUTTON_WHEEL_UP)
	check(editor.cam.zoom == zoom, "Room toolbar consumes wheel input")
	await wheel(Vector2(600,300), MOUSE_BUTTON_WHEEL_UP)
	check(editor.cam.zoom != zoom, "Room canvas still accepts wheel zoom")
	Game.world_path = Game.STORY_WORLD
	Game.goto("world_editor")
	await get_tree().process_frame
	await get_tree().process_frame
	var map = get_child(get_child_count()-1)
	var map_zoom: float = map.zoom
	var pan: Vector2 = map.pan
	await wheel(Vector2(map.size.x-100,300), MOUSE_BUTTON_WHEEL_UP)
	await wheel(Vector2(map.size.x-100,300), MOUSE_BUTTON_WHEEL_DOWN)
	check(map.zoom == map_zoom and map.pan == pan, "Map menu scrolling never moves or zooms the map")
	await wheel(Vector2(300,300), MOUSE_BUTTON_WHEEL_UP)
	check(map.zoom != map_zoom, "Map canvas still accepts wheel zoom")
	print("EDITOR SCROLL OK" if failures == 0 else "EDITOR SCROLL FAILED")
	Game.quit_game(failures)
