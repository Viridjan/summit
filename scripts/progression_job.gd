extends RefCounted
# Python owns the background work; this object only polls an atomic status file.
var pid := -1
var state := "idle"
var world_dir := ""
var output_dir := ""
var report := ""
var error := ""
var opened := false

func start(source: String, destination: String) -> bool:
	if state == "running": return false
	world_dir = source
	output_dir = destination
	report = destination.path_join("index.html")
	error = ""
	opened = false
	if OS.has_feature("web"):
		error = "Progression analysis requires the desktop source version."
		state = "failed"
		return false
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		error = "Could not create the progression report folder."
		state = "failed"
		return false
	var tool := ProjectSettings.globalize_path("res://tools/progression_job.py")
	pid = _launch(tool, source, destination)
	if pid <= 0:
		error = "Could not start Python 3. Install Python 3 to generate progression reports."
		state = "failed"
		return false
	state = "running"
	return true

func _launch(tool: String, source: String, destination: String) -> int:
	return OS.create_process("python3", [tool, "--world", source, "--output", destination], false)

func _is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)

func poll() -> String:
	if state != "running": return state
	var file := FileAccess.open(output_dir.path_join("status.json"), FileAccess.READ)
	if file != null:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("world", "") == world_dir:
			if data.get("state", "") == "complete" and FileAccess.file_exists(report): state = "complete"
			elif data.get("state", "") == "failed":
				state = "failed"
				error = str(data.get("error", "Analysis failed. See analysis.log in the report folder."))
	if state == "running" and not _is_running():
		state = "failed"
		error = "The progression process stopped before finishing. See analysis.log in the report folder."
	return state
