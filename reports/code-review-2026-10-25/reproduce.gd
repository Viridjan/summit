extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	var t := Time.get_ticks_usec()
	game.get_sfx()
	print("PROBE cold SFX initialization ms: ", (Time.get_ticks_usec() - t) / 1000.0)
	var world_script = load("res://scripts/world.gd")
	var entities = load("res://scripts/entities.gd")
	entities.ApeChase._plans.clear()
	var worlds := []
	for end_x in [200, 350]:
		var level: Dictionary = game.new_level("cache_probe", 60, 30)
		level.entities = [{"t":"spawn","x":100,"y":216}, {"t":"ape_chase","x":64,"y":192,"trigger":0,"end":end_x}]
		game.level = level
		var world = world_script.new()
		root.add_child(world)
		world.set_physics_process(false)
		world.set_process(false)
		worlds.append(world)
		for entity in world.ents:
			if entity.d.t == "ape_chase":
				t = Time.get_ticks_usec()
				entity.update(1.0/60.0)
				print("PROBE end=",end_x," path frames=",entity.path.size()," last feet=",entity.path[-1] if not entity.path.is_empty() else Vector2.ZERO," plan ms=",(Time.get_ticks_usec()-t)/1000.0)
	var adventure = load("res://scripts/adventure.gd")
	var aw := {"start":"room", "rooms":{"room":{}}}
	var restored: Dictionary = adventure.restore_run(aw, {"room":"room","spawn":["bad",{}],"blocks":-20,"energy":99999.0})
	print("PROBE restored malformed spawn=",restored.spawn," blocks=",restored.blocks," energy=",restored.energy)
	var art = load("res://scripts/ape_art.gd")
	var p0: Image = art.build("run", 0)
	var p4: Image = art.build("run", 4)
	print("PROBE build frame0 == frame4 despite same texture cache key: ",p0.get_data()==p4.get_data())
	for world in worlds:
		world.free()
	quit()
