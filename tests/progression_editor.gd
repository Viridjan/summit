extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
class FakeJob extends "res://scripts/progression_job.gd":
	var args: Array = []
	func _launch(tool: String, source: String, destination: String) -> int:
		args = [tool,source,destination]
		return 123456
	func _is_running() -> bool: return true
class Editor extends "res://scripts/world_editor.gd":
	var opened: Array = []
	var fake = FakeJob.new()
	func _new_progression_job(): return fake
	func _open_progression_report(path: String) -> Error:
		opened.append(path)
		return OK
class ActualEditor extends "res://scripts/world_editor.gd":
	var opened: Array = []
	func _open_progression_report(path: String) -> Error:
		opened.append(path)
		return OK
func _ready() -> void:
	Game.main = self
	var folder := "user://progression-editor-world/"
	DirAccess.make_dir_recursive_absolute(folder)
	Game.save_level(Game.new_level("Room",20,16),folder,"room")
	var file := FileAccess.open(folder+"world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"start":"room","abilities":["dash","climb","attack"],"rooms":{"room":[0,0]}}));file.close()
	Game.world_path = folder+"world.json"
	Game.progression_job = null
	Game.last_progression_report = ""
	var editor := Editor.new()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var back: Button = null
	for node in editor.find_children("*", "Button", true, false):
		if node.text == "Back": back = node
	check(back != null, "World Editor has a Back button")
	if back != null:
		check(back.global_position.x < 260 and back.global_position.y + back.size.y >= editor.size.y - 8, "Back sits at the bottom left of the bar")
	check(editor._start_progression(),"World Editor starts progression analysis")
	check(editor.fake.args[1]==ProjectSettings.globalize_path(folder.trim_suffix('/')),"Analysis uses the open world")
	check(editor.progression_button.disabled,"Duplicate jobs are disabled")
	check(not editor._start_progression(),"Starting a duplicate job is rejected")
	var report := FileAccess.open(editor.fake.report,FileAccess.WRITE);report.store_string("<html>test</html>");report.close()
	var status := FileAccess.open(editor.fake.output_dir.path_join("status.json"),FileAccess.WRITE)
	status.store_string(JSON.stringify({"world":editor.fake.world_dir,"state":"complete"}));status.close()
	editor._poll_progression()
	check(editor.opened==[editor.fake.report],"Completed report opens once")
	editor._poll_progression()
	check(editor.opened.size()==1,"Polling does not repeatedly launch a browser")
	check(Game.last_progression_report==editor.fake.report and not editor.progression_button.disabled,"Report can be reopened and analysis rerun")
	var failed := FakeJob.new();failed.state="failed";failed.error="Synthetic failure";failed.output_dir="failed"
	Game.progression_job=failed
	editor._poll_progression()
	check(editor.status.text.contains("Synthetic failure"),"Analysis failure is visible in the editor")
	editor.queue_free()
	await get_tree().process_frame
	Game.progression_job = null
	var actual := ActualEditor.new()
	add_child(actual)
	await get_tree().process_frame
	check(actual._start_progression(), "World Editor launches an actual background Python job")
	var deadline := Time.get_ticks_msec()+60000
	var frames := 0
	while Game.progression_job.state == "running" and Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(0.1).timeout
		actual._poll_progression()
		frames += 1
	check(Game.progression_job.state == "complete", "Real job completes with a generated HTML report")
	check(frames>0 and actual.opened.size()==1, "Editor stays responsive and opens the real report once")
	print("PROGRESSION EDITOR OK" if failures==0 else "PROGRESSION EDITOR FAILED")
	Game.quit_game(failures)
