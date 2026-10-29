extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	Game.main = self
	for mode in ["respawn", "none", "spawn"]:
		var level := Game.new_level("Playtest " + mode,40,23)
		level.entities = [] if mode == "none" else [{"t":mode,"x":24,"y":160}]
		Game.editor_level = level.duplicate(true)
		Game.editor_return = "menu"
		Game.goto("editor")
		await get_tree().process_frame
		var editor = get_child(get_child_count()-1)
		check(editor.tool_group.get_buttons().filter(func(b): return b.text == "Respawn").size() == 1, "Editor has one Respawn tool")
		editor._playtest()
		await get_tree().process_frame
		var screen = get_child(get_child_count()-1)
		check(screen != editor and screen.has_method("safe_spawn"), mode + " room starts Playtest")
		if screen.has_method("safe_spawn"):
			screen.set_physics_process(false)
			check(screen.safe_spawn(screen.player.pos), mode + " playtest starts on safe ground")
			var checkpoint = load("res://scripts/entities.gd").make(screen, {"t":"respawn","x":24,"y":160})
			check(load("res://scripts/entities.gd").TYPES.spawn[3] == load("res://scripts/entities.gd").TYPES.respawn[3], "Spawn and legacy Respawn use identical checkpoint behavior")
			var particles_before: int = screen.parts.size()
			screen.set_respawn(Vector2(60,168))
			check(screen.parts.size() == particles_before, "Checkpoint activation creates no particle animation")
			checkpoint.draw(null)  # Runtime checkpoints issue no drawing commands.
			check(checkpoint.describe().is_empty(), "Runtime respawns have no visible hover description")
		check(Game.editor_level == level, "Playtest preserves original editable entities")
	print("EDITOR PLAYTEST OK" if failures == 0 else "EDITOR PLAYTEST FAILED")
	Game.quit_game(failures)
