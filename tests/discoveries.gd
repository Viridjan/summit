extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var rules = load("res://scripts/adventure.gd")
	check(rules.has_method("collect_energy_fragment"), "Energy fragments have persistent three-piece progression")
	if not rules.has_method("collect_energy_fragment"):
		quit(failures)
		return
	var world_data := {"start": "test", "rooms": {"test": {}}, "abilities": []}
	var progress: Dictionary = rules.new_run(world_data)
	check(rules.collect_energy_fragment(progress,"fragment:test:a") and progress.blocks == 1 and progress.fragments == 1, "One fragment does not grant a full upgrade")
	check(not rules.collect_energy_fragment(progress,"fragment:test:a") and progress.fragments == 1, "A fragment cannot be collected twice")
	rules.collect_energy_fragment(progress,"fragment:test:b")
	progress = rules.restore_run(world_data,str_to_var(var_to_str(progress)))
	check(progress.fragments == 2 and progress.blocks == 1, "Partial fragment progress survives reload")
	rules.collect_energy_fragment(progress,"fragment:test:c")
	check(progress.fragments == 3 and progress.blocks == 2 and rules.stamina_max(progress) == rules.BASE_STAMINA+rules.STAMINA_PER_BLOCK, "Three fragments grant one capacity upgrade")
	for i in 3: rules.collect_energy_fragment(progress,"fragment:test:next%d" % i)
	check(progress.fragments == 6 and progress.blocks == 3, "The next three fragments grant exactly one more upgrade")
	var game = root.get_node("Game")
	game.level = game.new_level("test",40,23)
	game.level.entities = [{"t":"spawn","x":80,"y":144},{"t":"energy_fragment","x":120,"y":136,"id":"test_piece"}]
	game.adv_world = {"start":"test","abilities":[],"rooms":{"test":{"pos":Vector2i.ZERO,"level":game.level}}}
	game.adv = rules.new_run(game.adv_world)
	game.adv_temp = true
	var screen = load("res://scripts/world.gd").new()
	root.add_child(screen)
	screen.set_physics_process(false)
	var piece = screen.ents.filter(func(e): return e.d.t == "energy_fragment")[0]
	screen.player.interact = false
	piece.touch(screen.player)
	check(game.adv.fragments == 0 and piece.collidable, "Touching a fragment alone does not collect it")
	screen.player.interact = true
	piece.touch(screen.player)
	check(game.adv.fragments == 1 and not piece.collidable, "Interact collects the fragment")
	screen._build()
	check(not screen.ents.filter(func(e): return e.d.t == "energy_fragment")[0].collidable, "Collected fragment stays gone after a room rebuild")
	game.adv.spawn = [10000,10000]
	screen._build()
	check(screen.bounds.has_point(Vector2i(screen.spawn)), "A saved spawn outside a shortened room falls back to its authored spawn")
	screen.free()
	game.adv = {}
	game.adv_world = {}
	game.adv_temp = false
	print("DISCOVERIES OK" if failures == 0 else "DISCOVERIES FAILED: %d" % failures)
	quit(failures)
