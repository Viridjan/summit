extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	Game.main = self
	var dir := "user://navigation-test/"
	DirAccess.make_dir_recursive_absolute(dir)
	var a := Game.new_level("First", 20, 16)
	var b := Game.new_level("Second", 20, 16)
	a.entities.append({"t":"house_door", "id":"out", "to":"b:in", "x":32, "y":80})
	b.entities.append({"t":"house_door", "id":"in", "to":"a:out", "x":32, "y":80})
	Game.save_level(a, dir, "a")
	Game.save_level(b, dir, "b")
	var manifest := {"start":"a", "rooms":{"a":[0,0], "b":[100,0], "sealed":[20,0]}}
	Game.save_level(Game.new_level("Sealed",20,16),dir,"sealed")
	var file := FileAccess.open(dir+"world.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	Game.world_path = dir+"world.json"
	Game.editor_dir = dir
	Game.editor_file = "a"
	Game.editor_return = "world_editor"
	Game.editor_level = a
	Game.goto("editor")
	await get_tree().process_frame
	var editor = get_child(get_child_count()-1)
	check(editor.has_method("_connected_rooms"), "Room editor exposes connected-room navigation")
	if not editor.has_method("_connected_rooms"):
		Game.quit_game(failures)
		return
	check(editor._connected_rooms() == ["b"], "Door link appears; sealed adjacent room does not")
	var neighbor := Game.load_level("sealed", dir)
	neighbor.tiles[12] = "0" + neighbor.tiles[12].substr(1)
	Game.save_level(neighbor, dir, "sealed")
	editor.level.tiles[12] = editor.level.tiles[12].substr(0, 19) + "0"
	check(editor._connected_rooms() == ["b", "sealed"], "Matching open borders enable adjacent-room navigation")
	editor.level = a.duplicate(true)
	editor.cam.zoom = Vector2(10, 10)
	editor._request_room("b")
	check(Game.editor_file == "b" and editor.level.name == "Second", "Clean room switches immediately")
	var screen: Vector2 = editor.get_viewport_rect().size
	var center: Vector2 = screen / 2.0 + (Vector2(editor.level.w * 4, editor.level.h * 4) - editor.cam.position) * editor.cam.zoom
	check(center.x > 220 and center.y > 48, "Destination is centered in the usable editor workspace")
	check(editor.level.w * 8 * editor.cam.zoom.x <= screen.x - 240 and editor.level.h * 8 * editor.cam.zoom.y <= screen.y - 100, "Room switch fits the destination within the workspace")
	editor.level.name = "Unsaved"
	editor._request_room("a")
	check(Game.editor_file == "b" and editor.navigation_dialog.visible, "Dirty navigation asks before switching")
	editor.navigation_dialog.canceled.emit()
	editor.navigation_dialog.hide()
	await get_tree().process_frame
	check(Game.editor_file == "b" and editor.level.name == "Unsaved", "Cancel retains edits and room")
	editor._request_room("a")
	editor.navigation_dialog.custom_action.emit("discard")
	await get_tree().process_frame
	check(Game.editor_file == "a" and Game.load_level("b",dir).name == "Second", "Discard switches without saving")
	editor.level.name = "Saved first"
	editor._request_room("b")
	editor.navigation_dialog.confirmed.emit()
	await get_tree().process_frame
	check(Game.editor_file == "b" and Game.load_level("a",dir).name == "Saved first", "Save writes source before switching")
	editor.level.name = "Cannot save"
	var snapshot: Dictionary = editor.saved_level.duplicate(true)
	Game.editor_dir = dir + "missing/"
	editor._request_room("a")
	editor.navigation_dialog.confirmed.emit()
	await get_tree().process_frame
	check(Game.editor_file == "b" and editor.saved_level == snapshot and editor.level.name == "Cannot save", "Failed save preserves current edits and cancels navigation")
	print("EDITOR NAVIGATION OK" if failures == 0 else "EDITOR NAVIGATION FAILED")
	Game.quit_game(failures)
