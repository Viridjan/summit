extends Node
# Headless physics checks. Run:  godot --headless --path . res://tests/test.tscn
# Exit code = number of failures.

const PlayerScript := preload("res://scripts/player.gd")
const E := preload("res://scripts/entities.gd")
const Tuning := preload("res://scripts/tuning.gd")
const DT := 1.0 / 60.0

class Bot extends "res://scripts/player.gd":
	# scripted input instead of the keyboard
	var hold := {}  # action -> true
	var tap := {}
	func _init(world, spawn: Vector2) -> void:
		super(world, spawn)
	func _read_input(dt: float) -> void:
		in_x = int(hold.has("right")) - int(hold.has("left"))
		in_y = int(hold.has("down")) - int(hold.has("up"))
		aim_raw = Vector2(in_x, in_y).normalized()
		jump_buf -= dt
		dash_buf -= dt
		if tap.has("jump"): jump_buf = INPUT_BUFFER
		if tap.has("dash"): dash_buf = INPUT_BUFFER
		tap.clear()
		jump_check = hold.has("jump")
		grab_check = hold.has("grab")

class TrackedEditor extends "res://scripts/editor.gd":
	var background_draw_count := 0
	func _draw_background(ci: CanvasItem) -> void:
		background_draw_count += 1
		super(ci)

var fails := 0
var w

func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1

func make_world(ents: Array, extra_tiles := []) -> void:
	if w:
		w.queue_free()
	var d := Game.new_level("test", 60, 30)
	for t in extra_tiles:  # [x, y]
		var row: String = d.tiles[t[1]]
		d.tiles[t[1]] = row.substr(0, t[0]) + "1" + row.substr(t[0] + 1)
	d.entities = [{"t": "spawn", "x": 80, "y": 27 * 8}] + ents
	Game.level = d
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)

func step(n := 1) -> void:
	for i in n:
		if w.freeze > 0:
			w.freeze -= DT
			continue
		if not w.player.dead:
			w.player.update(DT)
			w.after_player_move()
		for e in w.ents:
			e.update(DT)

func p():
	return w.player

func _with(d: Dictionary, key: String, v) -> Dictionary:
	var c := d.duplicate(true)
	if v == null:
		c.erase(key)
	else:
		c[key] = v
	return c

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func check_editor_tiles(ed, action: String) -> void:
	var expected := Vector2i(ceili(ed.level.w / 32.0), ceili(ed.level.h / 32.0))
	check(ed.tile_layer.chunk_grid == expected and ed.tile_layer.chunks.size() == expected.x * expected.y,
		"tile chunk grid follows editor %s" % action)
	check(is_same(ed.tile_layer.tiles, ed.level.tiles), "tile layer shares current editor tiles after %s" % action)

func check_tile_layer() -> void:
	var layer = load("res://scripts/tile_layer.gd").new()
	var d := Game.new_level("chunks", 100, 70)
	layer.setup(d.tiles, d.w, d.h)
	add_child(layer)
	check(layer.chunks.size() == 12, "100x70 tiles produce 12 chunks")
	var coverage := PackedByteArray()
	coverage.resize(100 * 70)
	for chunk in layer.chunks:
		for y in range(chunk.cells.position.y, chunk.cells.end.y):
			for x in range(chunk.cells.position.x, chunk.cells.end.x):
				coverage[y * 100 + x] += 1
	check(coverage.count(1) == 7000, "chunk ranges cover each cell exactly once, including partial edges")
	check(layer.mark_cell_dirty(Vector2i(12, 12)) == [Vector2i(0, 0)], "interior edit marks one chunk")
	check(layer.mark_cell_dirty(Vector2i(32, 12)) == [Vector2i(1, 0), Vector2i(0, 0)], "edge edit also marks adjacent chunk")
	check(layer.mark_cell_dirty(Vector2i(32, 32)) == [Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0)],
		"corner edit marks owner and two cardinal chunks, not diagonal")
	check(layer.mark_cell_dirty(Vector2i(31, 31)) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		"opposite corner edit marks right and bottom neighbours")
	check(layer.mark_cell_dirty(Vector2i(0, 0)) == [Vector2i(0, 0)] and layer.mark_cell_dirty(Vector2i(-1, 0)).is_empty(),
		"level boundaries reject invalid chunks")
	d.tiles[32] = "0".repeat(100)
	check(layer.chunks[5].tiles[32] == d.tiles[32] and is_same(layer.tiles, d.tiles), "chunks read live tile array")
	# Let CanvasItem draw commands be recorded, then verify cache reuse and invalidation.
	await get_tree().process_frame
	await get_tree().process_frame
	var before: Array[int] = []
	for chunk in layer.chunks:
		before.append(chunk.draw_count)
	layer.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var retained := true
	for i in layer.chunks.size():
		retained = retained and layer.chunks[i].draw_count == before[i]
	check(before[0] > 0 and retained, "parent redraw retains cached chunk commands")
	var marked: Array = layer.mark_cell_dirty(Vector2i(32, 32))
	await get_tree().process_frame
	await get_tree().process_frame
	var invalidated := true
	for i in layer.chunks.size():
		var coordinate := Vector2i(i % layer.chunk_grid.x, i / layer.chunk_grid.x)
		invalidated = invalidated and layer.chunks[i].draw_count == before[i] + (1 if coordinate in marked else 0)
	check(invalidated, "only marked chunks record draw commands again")
	layer.free()

func check_character_animation() -> void:
	var art = load("res://scripts/character_art.gd")
	var atlas: Image = art.build_atlas()
	check(atlas.get_size() == Vector2i(128, 208), "Nori atlas contains thirteen 16px animation rows")
	var valid := true
	for animation in art.ANIMATIONS:
		var spec: Array = art.ANIMATIONS[animation]
		var last: Vector2i = art.frame(animation, 100.0)
		valid = valid and last.x >= 0 and last.x < spec[1] and last.y == spec[0]
		for i in int(spec[1]):
			valid = valid and atlas.get_region(Rect2i(i * 16, int(spec[0]) * 16, 16, 16)).get_used_rect().has_area()
	check(valid, "every authored animation frame is populated and sampling remains in range")
	check(art.frame("land", 100).x == 2 and art.frame("jump", 100).x == 1, "landing and jump poses hold their last frame")
	check(art.texture() == art.texture(), "Nori shares one cached texture")
	var actor = PlayerScript.new(null, Vector2(40, 40))
	actor.on_ground = true
	actor._update_visuals(DT)
	actor.was_on_ground = true
	actor.landing_visual_timer = 0
	actor._update_visuals(DT)
	check(actor.visual_animation == "idle", "grounded stationary character selects idle")
	actor.speed = Vector2(90, 0)
	actor.in_x = 1
	actor._update_visuals(DT)
	check(actor.visual_animation == "run" and actor.visual_clock == 0, "run transition starts on its first frame")
	actor._update_visuals(DT)
	check(actor.visual_clock > 0, "run animation advances while moving")
	actor.in_x = -1
	actor._update_visuals(DT)
	check(actor.visual_animation == "skid", "opposing input selects the braking pose")
	actor.on_ground = false
	actor.speed.y = -100
	check(actor._animation() == "jump", "upward motion selects jump")
	actor.speed.y = 0
	check(actor._animation() == "apex", "jump apex has its own pose")
	actor.speed.y = 100
	check(actor._animation() == "fall", "downward motion selects fall")
	actor.wall_slide_dir = 1
	check(actor._animation() == "wall_slide", "wall contact selects a distinct slide pose")
	actor.state = actor.ST_CLIMB
	actor.speed = Vector2.ZERO
	actor._update_visuals(DT)
	actor._update_visuals(DT)
	check(actor.visual_animation == "climb" and actor.visual_clock == 0, "stationary climb holds its contact pose")
	for dash_state in [actor.ST_DASH, actor.ST_RED_DASH, actor.ST_DREAM_DASH]:
		actor.state = dash_state
		check(actor._animation() == "dash", "dash state %d overrides airborne poses" % dash_state)
	actor.state = actor.ST_STAR_FLY
	check(actor._animation() == "fly", "feather selects flight pose")
	actor.state = actor.ST_BOOST
	check(actor._animation() == "boost", "booster selects tucked pose")
	actor.state = actor.ST_NORMAL
	actor.wall_slide_dir = 0
	actor.on_ground = true
	actor.speed = Vector2.ZERO
	actor.set_ducking(true)
	check(actor._animation() == "duck", "ducking selects low silhouette")
	actor.set_ducking(false)
	actor.was_on_ground = false
	actor._update_visuals(DT)
	check(actor.visual_animation == "land" and actor.landing_visual_timer > 0, "ground contact triggers landing recovery")
	actor.was_on_ground = true
	actor._update_visuals(0.2)
	check(actor.visual_animation == "idle", "landing recovery returns to idle")
	check(actor.hitbox() == Rect2i(36, 29, 8, 11), "new character art preserves the original physical hitbox")

const FIXTURE_WORLD := "res://tests/fixtures/adventure/"  # 3 tiny rooms the adventure tests rely on

func _copy_world(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(FIXTURE_WORLD):
		if f.ends_with(".json"):
			_write(dir + f, FileAccess.get_file_as_string(FIXTURE_WORLD + f))

func _remove_dir(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)

# The shipped world: every room loads, nothing overlaps, every room is reachable through passages.
# (Movement reachability and ability gates were checked with the world generator's tools.)
func check_shipped_world() -> void:
	const Adventure := preload("res://scripts/adventure.gd")
	var world := Adventure.load_world(Game.ADVENTURE_DIR + "world.json")
	var files := Array(DirAccess.get_files_at(Game.ADVENTURE_DIR)).filter(func(f): return f.ends_with(".json") and f != "world.json")
	check(world.rooms.size() == files.size() and world.rooms.has(world.start), "shipped world loads every room file (%d/%d)" % [world.rooms.size(), files.size()])
	check(Adventure.overlaps(world).is_empty(), "shipped rooms don't overlap")
	var links := {}
	for seg in Adventure.doorways(world):
		var mid: Vector2 = (seg[0] + seg[1]) / 2.0
		var dir: Vector2 = (seg[1] - seg[0]).normalized().orthogonal()
		var a := Adventure.room_at(world, mid + dir * 4)
		var b := Adventure.room_at(world, mid - dir * 4)
		links[a] = links.get(a, []) + [b]
		links[b] = links.get(b, []) + [a]
	var seen := {world.start: true}
	var todo := [world.start]
	while not todo.is_empty():
		for n in links.get(todo.pop_back(), []):
			if n != "" and not seen.has(n):
				seen[n] = true
				todo.append(n)
	check(seen.size() == world.rooms.size(), "every shipped room is connected to the start (%d/%d)" % [seen.size(), world.rooms.size()])
	var counts := {}
	for n in world.rooms:
		for e in world.rooms[n].level.entities:
			counts[e.t] = counts.get(e.t, 0) + 1
			if e.t == "note":
				check(str(e.get("text", "")) != "", "note in %s has text" % n)
	check(counts.get("ability_dash", 0) == 1 and counts.get("ability_climb", 0) == 1 and counts.get("goal", 0) == 1, "shipped world has one dash orb, one climb orb, one goal")
	# reference worlds in res://worlds/ (a cross-room door in Zebes moves the player into the linked room)
	var zebes := Adventure.load_world(Game.WORLDS_DIR + "metroid_zero_mission/world.json")
	var src := ""
	var door: Dictionary = {}
	for rn in zebes.rooms:
		for e in zebes.rooms[rn].level.entities:
			if e.t == "door" and src == "":
				src = rn
				door = e
	Game.adv_world = zebes
	Game.adv = Adventure.new_run(zebes)
	Game.adv_temp = true
	Game.adv.room = src
	Game.level = zebes.rooms[src].level
	if w:
		w.queue_free()
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)
	w.room = src
	p().pos = Vector2(float(door.x) + float(door.w) / 2, float(door.y) + float(door.h))
	step()
	check(w.room == str(door.to).get_slice(":", 0), "Zebes door %s:%s leads into room %s (now in %s)" % [src, door.id, str(door.to).get_slice(":", 0), w.room])
	w.queue_free()
	w = null
	Game.adv = {}
	# reference worlds: listed in the menu, load, start with every ability
	var listed: Array = Game.world_list()
	check(listed.size() == 5 and listed[0][1] == Game.ADVENTURE_DIR + "world.json", "menu lists the main world and the 4 reference worlds (%d)" % listed.size())
	for w in listed.slice(1):
		var rw := Adventure.load_world(w[1])
		var has_spawn: bool = rw.rooms.has(rw.start) and rw.rooms[rw.start].level.entities.any(func(e): return e.t == "spawn")
		check(rw.rooms.size() > 10 and has_spawn and Adventure.overlaps(rw).is_empty() and Adventure.new_run(rw).abilities == ["dash", "climb"], "%s loads: %d rooms, spawn, no overlaps, starts with dash+climb" % [w[0], rw.rooms.size()])
		var ids := {}
		var door_to := []
		for rn in rw.rooms:
			for e in rw.rooms[rn].level.entities:
				if e.t == "door":
					ids[rn + ":" + e.id] = true
					door_to.append(e.to)
		check(not door_to.is_empty() and door_to.all(func(t): return ids.has(t)), "%s: all %d doors lead to a door that exists" % [w[0], door_to.size()])

func check_doors() -> void:
	# same level: door a -> b keeps speed and height in the doorway, no bounce back, and works the other way
	make_world([{"t": "door", "x": 200, "y": 200, "w": 8, "h": 24, "id": "a", "to": "b"},
		{"t": "door", "x": 400, "y": 120, "w": 8, "h": 24, "id": "b", "to": "a"}])
	p().pos = Vector2(204, 220)
	p().speed = Vector2(60, 0)
	step()
	check(Rect2(400, 120, 8, 24).grow(1).has_point(p().pos) and p().speed.x > 0, "a door moves the player to the linked door and keeps speed (at %s)" % p().pos)
	step(3)
	check(p().pos.x > 390, "arriving on a door doesn't bounce straight back")
	p().pos = Vector2(500, 200)
	step()
	p().pos = Vector2(404, 140)
	step()
	check(Rect2(200, 200, 8, 24).grow(1).has_point(p().pos), "the linked door leads back")
	make_world([{"t": "door", "x": 200, "y": 200, "w": 8, "h": 24, "id": "a", "to": "missing"}])
	p().pos = Vector2(204, 220)
	step()
	check(p().pos.distance_to(Vector2(204, 220)) < 4 and w.note_label.text.contains("missing"), "a door to nowhere leaves the player in place and says so")

func check_placeholders() -> void:
	make_world([{"t": "acid", "x": 160, "y": 200, "w": 64, "h": 24}, {"t": "enemy", "x": 320, "y": 200, "w": 16, "h": 16, "text": "Crawlid"},
		{"t": "water", "x": 400, "y": 200, "w": 64, "h": 24}, {"t": "breakable", "x": 480, "y": 200, "w": 8, "h": 8, "text": "grub jar"}])
	p().pos = Vector2(330, 216)
	step()
	p().pos = Vector2(430, 216)
	step()
	p().pos = Vector2(484, 208)
	step()
	check(not p().dead, "enemy / water / breakable placeholders are harmless")
	p().pos = Vector2(190, 216)
	step()
	check(p().dead, "acid kills on touch")

func check_adventure() -> void:
	const Adventure := preload("res://scripts/adventure.gd")
	Game.world_path = FIXTURE_WORLD + "world.json"
	var world := Adventure.load_world(Game.world_path)
	check(world.rooms.size() >= 3 and world.start == "a1_first_steps", "world.json loads the shipped rooms")
	check(Adventure.overlaps(world).is_empty(), "shipped rooms don't overlap")
	var links := Adventure.doorways(world)
	check(links.size() > 0 and links.any(func(sg): return sg[0].x == 40 * 8) and links.any(func(sg): return sg[0].x == 80 * 8), "neighbouring rooms have passages between them")
	check(Adventure.room_at(world, Vector2(41 * 8, 100)) == "a2_little_gap" and Adventure.room_at(world, Vector2(-5, 100)) == "", "room_at finds the room under a world point")

	# a bot runs and hops right from the start room through every room to the goal
	Game.adv_world = world
	Game.adv = Adventure.new_run(world)
	Game.adv_temp = true  # never saved
	Game.level = world.rooms[world.start].level
	if w:
		w.queue_free()
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)
	p().hold = {"right": true, "jump": true}
	var rooms_seen := [w.room]
	var kept_speed := true
	for i in 3000:
		if w.done or p().dead:
			break
		p().tap["jump"] = true
		var before: String = w.room
		var sx: float = p().speed.x
		step()
		if w.room != before:
			rooms_seen.append(w.room)
			kept_speed = kept_speed and p().speed.x > 0 and absf(p().speed.x - sx) < 20
	check(rooms_seen == ["a1_first_steps", "a2_little_gap", "a3_stairs"], "walking off an edge enters the next room (%s)" % [rooms_seen])
	check(kept_speed, "speed carries over a room change")
	check(w.done and Game.adv.done, "bot finishes the adventure")
	check(Game.adv.visited.size() == 3 and Game.adv.abilities.has("dash") and Game.adv.abilities.has("climb"), "visited rooms and ability pickups recorded")
	check(w.collected.keys().all(func(k): return k.contains(":")), "adventure star ids carry their room")

	# abilities gate moves
	Game.adv = Adventure.new_run(world)
	Game.level = world.rooms[world.start].level
	w.queue_free()
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)
	step(5)
	p().tap["dash"] = true
	step(2)
	check(p().state != p().ST_DASH, "no dash before the dash ability")
	w.grant_ability("dash")
	p().tap["dash"] = true
	step(2)
	check(p().state == p().ST_DASH, "dash works after picking it up")
	Game.adv = {}
	Game.adv_temp = false
	w.queue_free()
	w = null

	# runs save and load (scratch save file)
	Game.save_path = "user://test_save.cfg"
	DirAccess.remove_absolute(Game.save_path)
	check(not Game.has_adventure_save(), "no adventure save on a fresh file")
	Game.adv = Adventure.new_run(world)
	Game.adv.room = "a2_little_gap"
	Game.adv.abilities = ["dash"]
	Game.save_adventure()
	var cf := ConfigFile.new()
	cf.load(Game.save_path)
	var run: Dictionary = cf.get_value("adventure", Game._run_key(), {})
	check(Game.has_adventure_save() and run.get("room") == "a2_little_gap" and run.get("abilities") == ["dash"], "adventure run saves and loads")
	var key := Game._run_key()
	Game.world_path = Game.ADVENTURE_DIR + "world.json"
	check(Game._run_key() == "run" and key != "run" and not Game.has_adventure_save(), "each world keeps its own save (main world keeps the old key)")
	Game.world_path = FIXTURE_WORLD + "world.json"
	Game.adv = {}
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = Game.SAVE_PATH

	# world editor on a scratch copy of the world
	var dir := "user://test_world/"
	_copy_world(dir)
	Game.world_path = dir + "world.json"
	var we = load("res://scripts/world_editor.gd").new()
	add_child(we)
	we.move_room("a3_stairs", Vector2i(80, 10))
	we._save()
	var added: String = we.add_room("a1_first_steps", Game.new_level("Extra", 20, 10), Vector2i(0, 30))
	we.selected = "a2_little_gap"
	var spot: Vector2i = we._free_spot(Game.new_level("X", 40, 23))
	check(spot == Vector2i(120, 0), "new room goes right of the selected room, past rooms in the way (got %s)" % spot)
	var again := Adventure.load_world(Game.world_path)
	check(again.rooms.a3_stairs.pos == Vector2i(80, 10) and added == "a1_first_steps_2" and again.rooms.has(added), "world editor moves and adds rooms and saves them")
	we.queue_free()
	Game.world_path = Game.ADVENTURE_DIR + "world.json"
	_remove_dir(dir)

func _ready() -> void:
	Game.settings.air_dashes = 0
	Game.settings.infinite_stamina = false
	Game.settings.invincible = false
	Game.settings.shake = false

	check_character_animation()
	await check_tile_layer()

	# a script that fails to compile otherwise only shows up as engine errors
	for sc in ["world", "editor", "menu", "options", "debug_panel", "map_view", "player", "entities", "tuning"]:
		check(load("res://scripts/%s.gd" % sc).can_instantiate(), "%s.gd compiles" % sc)

	# registry contract: every registered type, automatically (see docs/ADDING_ENTITIES.md)
	make_world([])
	var all_level := Game.new_level("registry", 30, 20)
	for t in E.TYPES:
		var d := {"t": t, "x": 64, "y": 64, "w": 16, "h": 16, "tx": 96, "ty": 64}
		all_level.entities.append(d.duplicate())
		var in_world = E.make(w, d)
		var in_editor = E.make(null, d)
		check(in_world != null and in_editor != null and in_world is E.Ent, "%s constructs in world and editor" % t)
		check(in_world.vis_rect().encloses(in_world.rect) and in_world.vis_rect().encloses(in_world.touch_rect()), "%s draw bounds cover its rect" % t)
		var row: Array = E.TYPES[t]
		check(row.size() == 4 and row[0] is String and row[1] is bool and row[2] is Color, "%s registry row is [label, sized, color, class]" % t)
	var reg_tmp := "__regress_registry_%d" % Time.get_ticks_usec()
	_write(Game.LEVEL_DIR + reg_tmp + ".json", JSON.stringify(all_level))
	var reg_back := Game.load_level(reg_tmp)
	DirAccess.remove_absolute(Game.LEVEL_DIR + reg_tmp + ".json")
	check(reg_back.get("entities", []).size() == all_level.entities.size(), "level with every type survives save/load")

	# tuning: defaults are Celeste's values, overrides apply to new players, presets round-trip
	var defs := Tuning.defaults()
	check(defs.MAX_RUN == 90.0 and defs.GRAVITY == 900.0 and defs.DASH_SPEED == 240.0 and defs.JUMP_SPEED == -105.0 and defs.CLIMB_MAX_STAMINA == 110.0 and defs.INPUT_BUFFER == 0.08 and defs.DUCK_CORRECT_CHECK == 4 and defs.WALL_JUMP_H_SPEED == 130.0, "tuning defaults match the original constants")
	check(Tuning.names().size() == 93 and Tuning.names().all(func(n): return Tuning.group_of(n) != "Other"), "93 tunables, all grouped (%d)" % Tuning.names().size())
	check((Tuning.names() + Tuning.DERIVED).all(func(n): return Tuning.HELP.get(n, "") != ""), "every tunable has mouse-over help")
	check(load("res://scripts/debug_panel.gd").StateGraph.HELP.size() == load("res://scripts/player.gd").STATE_NAMES.size(), "every state has mouse-over help")
	Game.tuning = {"MAX_RUN": 120.0}
	make_world([])
	step(5)
	p().hold = {"right": true}
	step(40)
	check(absf(p().speed.x - 120.0) < 0.01 and p().WALL_JUMP_H_SPEED == 160.0, "MAX_RUN override applies and derived values follow (%.1f)" % p().speed.x)
	var preset := "__regress_tmp_preset"
	check(Tuning.save_preset(preset, Game.tuning), "preset saves")
	var back := Tuning.load_file(Tuning.preset_path(preset))
	check(back.MAX_RUN == 120.0 and back.DUCK_CORRECT_CHECK is int and back.size() == 93, "preset loads typed values")
	Tuning.delete_preset(preset)
	check(not FileAccess.file_exists(Tuning.preset_path(preset)), "preset deletes")
	Game.tuning = {}
	make_world([])
	step(5)
	p().hold = {"right": true}
	step(40)
	check(absf(p().speed.x - 90.0) < 0.01, "clearing overrides restores defaults")
	p().hold = {}
	step(20)
	p().hold = {"right": true}
	p().tap = {"dash": true}
	step(25)
	var tr: Dictionary = p().transitions
	check(tr.get(Vector2i(p().ST_NORMAL, p().ST_DASH), 0) == 1 and tr.get(Vector2i(p().ST_DASH, p().ST_NORMAL), 0) == 1 and p().transition_log.size() == 2, "state transitions are recorded")

	# old levels' "strawberry" entities are the star collectible
	make_world([{"t": "strawberry", "x": 200, "y": 100}])
	check(w.total_berries == 1 and w.ents.any(func(e): return e is E.Star), "strawberry id loads as a star")

	make_world([])
	var original_tiles = w.tile_layer.tiles
	var original_chunk = w.tile_layer.chunks[0]
	w._build()
	w.player = Bot.new(w, w.spawn)
	check(w.tile_layer.chunks[0] == original_chunk and is_same(w.tiles, original_tiles), "respawn retains tile chunks and tile array")
	check(w.background.z_index == -2 and w.tile_layer.z_index == -1 and w.z_index == 0, "world layering keeps background below terrain below actors")
	step(5)
	var floor_y: float = p().pos.y
	check(p().on_ground and floor_y == 28 * 8, "spawn lands on floor (y=%d)" % floor_y)

	# run speed
	p().hold = {"right": true}
	step(30)
	check(absf(p().speed.x - 90.0) < 0.01, "max run speed 90 (got %.2f)" % p().speed.x)
	p().hold = {}
	step(30)
	check(p().speed.x == 0, "friction stops the player")

	# full jump vs short hop
	var y0: float = p().pos.y
	p().tap = {"jump": true}
	p().hold = {"jump": true}
	var top := y0
	for i in 60:
		step()
		top = minf(top, p().pos.y)
	var full := y0 - top
	p().hold = {}
	step(30)
	p().tap = {"jump": true}
	step(1)
	top = y0
	for i in 60:
		step()
		top = minf(top, p().pos.y)
	var short := y0 - top
	check(full >= 20 and full <= 30, "full jump height ~3 tiles (got %d px)" % full)
	check(short < full - 6, "releasing jump early gives a lower jump (%d < %d)" % [short, full])

	# dash
	step(30)
	var x0: float = p().pos.x
	p().hold = {"right": true}
	p().tap = {"dash": true}
	step(1)
	check(p().state == p().ST_DASH and p().dashes == 0, "dash starts and uses the dash")
	step(16)
	check(p().state == p().ST_NORMAL, "dash ends after ~0.15s")
	var dist: float = p().pos.x - x0
	check(dist > 30 and dist < 60, "dash travels ~40px (got %d)" % dist)
	p().hold = {}
	step(20)
	check(p().dashes == 1, "dash refills on ground")

	# super jump: dash along ground then jump
	make_world([])
	step(5)
	p().hold = {"right": true}
	p().tap = {"dash": true}
	step(6)  # 3 freeze frames + dash start
	check(p().state == p().ST_DASH, "still dashing before the jump")
	p().tap = {"jump": true}
	step(1)
	check(absf(p().speed.x - 260.0) < 1.0, "super jump speed 260 (got %.1f)" % p().speed.x)

	# wall jump + climb: wall column at x=20
	var wall := []
	for y in range(10, 28):
		wall.append([20, y])
	make_world([], wall)
	step(5)
	p().hold = {"right": true}
	step(60)
	check(p().hitbox().end.x == 160, "walk into wall stops at it")
	p().tap = {"jump": true}
	p().hold = {"right": true, "jump": true}
	step(14)
	p().tap = {"jump": true}
	step(1)
	check(p().speed.x == -130.0, "wall jump pushes away at 130 (got %.1f)" % p().speed.x)
	p().hold = {}
	step(60)
	p().hold = {"right": true}
	step(30)
	p().hold = {"grab": true, "up": true}
	step(2)
	check(p().state == p().ST_CLIMB, "grab wall enters climb")
	var cy: float = p().pos.y
	step(30)
	check(p().pos.y < cy - 10 and p().stamina < 110, "climbing up moves up and drains stamina")
	p().hold = {"grab": true}
	for i in 60 * 12:
		step()
		if p().state != p().ST_CLIMB:
			break
	check(p().state != p().ST_CLIMB, "running out of stamina drops the player")
	# infinite stamina (assist option): hang on the same wall for 20 s
	Game.settings.infinite_stamina = true
	make_world([], wall)
	step(5)
	p().hold = {"right": true}
	step(60)
	p().hold = {"grab": true}
	step(2)
	var held := 0
	var min_st := 999.0
	for i in 60 * 20:
		step()
		min_st = minf(min_st, p().stamina)
		if p().state != p().ST_CLIMB:
			break
		held += 1
	check(held == 60 * 20, "infinite stamina keeps the player on the wall (held %d frames, min stamina %.1f)" % [held, min_st])
	Game.settings.infinite_stamina = false

	# spikes kill
	make_world([{"t": "spikes_up", "x": 120, "y": 27 * 8}])
	step(5)
	p().hold = {"right": true}
	step(40)
	check(p().dead, "walking into spikes kills")

	# spring super bounce
	make_world([{"t": "spring_up", "x": 104, "y": 27 * 8}])
	step(5)
	p().hold = {"right": true}
	var bounced := false
	for i in 40:
		step()
		if p().speed.y <= -170:
			bounced = true
			break
	check(bounced, "spring launches upward")

	# refill crystal in the air
	make_world([{"t": "refill", "x": 80, "y": 25 * 8}])
	step(5)
	p().dashes = 0
	p().pos.y = 210
	p().on_ground = false
	w.player_touch(p())
	check(p().dashes == 1, "dash crystal refills dash")

	# dream block: dash right through a 3-tile wide block
	make_world([{"t": "dream", "x": 112, "y": 25 * 8, "w": 24, "h": 24}])
	step(5)
	p().hold = {"right": true}
	p().tap = {"dash": true}
	var dreamed := false
	for i in 60:
		step()
		dreamed = dreamed or p().state == p().ST_DREAM_DASH
	check(dreamed and p().pos.x > 136 and not p().dead, "dash passes through dream block (x=%d)" % p().pos.x)

	# crumble block disappears under the player
	make_world([{"t": "crumble", "x": 72, "y": 28 * 8 - 24, "w": 24, "h": 8}])
	p().pos = Vector2(84, 28 * 8 - 24)
	step(5)
	check(p().on_ground, "standing on crumble block")
	step(40)
	check(w.solids[0].collidable == false, "crumble block crumbles")

	# feather
	make_world([{"t": "feather", "x": 80, "y": 26 * 8}])
	step(5)
	w.player_touch(p())
	p().pos.y -= 2
	step(1)
	check(p().state == p().ST_STAR_FLY, "feather starts flying")

	# zip mover carries the player
	make_world([{"t": "zip", "x": 72, "y": 20 * 8, "w": 24, "h": 8, "tx": 72 + 80, "ty": 20 * 8}])
	p().pos = Vector2(84, 20 * 8)
	step(5)
	var zx: float = p().pos.x
	step(40)
	check(p().pos.x > zx + 40, "zip mover carries rider (moved %d)" % (p().pos.x - zx))

	# booster
	make_world([{"t": "booster", "x": 80, "y": 26 * 8}])
	step(3)
	check(p().state == p().ST_BOOST or p().state == p().ST_DASH, "bubble captures player")

	# screens build without script errors
	for s in ["menu", "editor"]:
		var n = load("res://scripts/%s.gd" % s).new()
		add_child(n)
		n.queue_free()
	check(true, "menu + editor instantiate")

	# editor: undo/new/resize/erase must not leave zip_pending pointing at a removed mover
	Game.editor_level = {}
	var ed := TrackedEditor.new()
	add_child(ed)
	check_editor_tiles(ed, "initialization")
	check(ed.background.z_index == -2 and ed.tile_layer.z_index == -1, "editor layering keeps grid below terrain below previews")
	# headless: camera never applies, so map the mouse onto cell (5, 5) directly
	get_viewport().canvas_transform = Transform2D(0, get_viewport().get_mouse_position() - Vector2(44, 44))
	for action in ["undo", "new", "resize", "erase"]:
		ed.tool = "zip"
		var mc: Vector2i = ed._cell_at_mouse()
		ed._push_undo()  # _left(true) does this before a rect drag
		ed._place_rect(mc, mc + Vector2i(1, 1))
		if action == "undo":
			ed._undo()
		elif action == "new":
			ed._new()
		elif action == "resize":
			ed.w_spin.value = 10
			ed.h_spin.value = 6
			ed._resize()
		else:
			ed._right(true)  # RMB on the pending mover
			ed._right(false)
		check_editor_tiles(ed, action)
		check(ed.zip_pending == null, "zip_pending cleared after %s" % action)
		ed.msg = ""
		ed.tool = "tile"
		ed._left(true)
		ed._left(false)
		check(ed.msg != "Zip mover placed", "no phantom 'Zip mover placed' after %s" % action)
		ed._new()
	# previews update incrementally; they must match a full rebuild, index for index
	ed.tool = "spawn"  # replacing the spawn rebuilds everything, so do it first
	ed._place_point(Vector2i(9, 9))
	ed.tool = "refill"
	ed._place_point(Vector2i(2, 2))
	ed._place_point(Vector2i(2, 2))  # duplicate is ignored
	ed.tool = "crumble"
	ed._place_rect(Vector2i(1, 4), Vector2i(3, 5))
	ed.tool = "zip"
	ed._place_rect(Vector2i(6, 1), Vector2i(7, 1))
	ed._left(true)  # target click at cell (5, 5)
	ed._left(false)
	ed.tool = "strawberry"
	ed._place_point(Vector2i(8, 8))
	ed._erase_entity(ed._entity_at(Vector2i(2, 4)))
	var types := []
	var same: bool = ed.preview.size() == ed.level.entities.size()
	for i in ed.level.entities.size():
		var fresh = E.make(null, ed.level.entities[i])
		types.append(ed.level.entities[i].t)
		same = same and is_same(ed.preview[i].d, ed.level.entities[i]) and ed.preview[i].rect == fresh.rect and ed.preview[i].vis_rect() == fresh.vis_rect()
	check(same and types == ["spawn", "refill", "zip", "strawberry"], "incremental editor previews match a full rebuild %s" % [types])
	check(ed.preview[2].target == Vector2(40, 40), "zip preview picks up its target click")
	ed._set_level(Game.new_level("large", 100, 70))
	check_editor_tiles(ed, "load")
	ed._push_undo()
	ed._new()
	check_editor_tiles(ed, "new default map")
	ed._undo()
	check_editor_tiles(ed, "undo to large map")
	var paint_cell := Vector2i(32, 32)
	ed._set_tile(paint_cell, true)
	check(ed.tile_layer.chunks[5].tiles[32][32] == "1", "painting updates chunk source across boundary")
	ed.w_spin.value = 65
	ed.h_spin.value = 33
	ed._resize()
	check_editor_tiles(ed, "resize to partial chunks")
	await get_tree().process_frame
	await get_tree().process_frame
	var background_draws := ed.background_draw_count
	ed.cam.position += Vector2(8, 0)
	ed.queue_redraw()  # public CanvasItem API, also used by the benchmark harness
	await get_tree().process_frame
	await get_tree().process_frame
	check(background_draws > 0 and ed.background_draw_count > background_draws, "editor background draws initially and follows direct parent redraws")
	ed.queue_free()

	# level loading rejects malformed JSON gracefully (disposable files only)
	var tmp := "__regress_tmp_%d" % Time.get_ticks_usec()
	var tmp_path := Game.LEVEL_DIR + tmp + ".json"
	var good := Game.new_level("ok", 12, 8)
	good.entities.append({"t": "zip", "x": 8, "y": 8, "w": 16, "h": 8, "tx": 40, "ty": 8})
	good.entities.append({"t": "strawberry", "x": 24.0, "y": 16.0})
	var bad_cases := {
		"not json": "{oops",
		"array root": "[]",
		"tiles only": '{"tiles":[]}',
		"w string": JSON.stringify(_with(good, "w", "12")),
		"w zero": JSON.stringify(_with(good, "w", 0)),
		"h huge": JSON.stringify(_with(good, "h", 100000)),
		"w fractional": JSON.stringify(_with(good, "w", 12.5)),
		"tiles not array": JSON.stringify(_with(good, "tiles", "000")),
		"too few rows": JSON.stringify(_with(good, "tiles", good.tiles.slice(1))),
		"short row": JSON.stringify(_with(good, "tiles", ["0"] + good.tiles.slice(1))),
		"bad tile char": JSON.stringify(_with(good, "tiles", ["2".repeat(12)] + good.tiles.slice(1))),
		"row not string": JSON.stringify(_with(good, "tiles", [5] + good.tiles.slice(1))),
		"entities missing": JSON.stringify(_with(good, "entities", null)),
		"entities not array": JSON.stringify(_with(good, "entities", {})),
		"entity not dict": JSON.stringify(_with(good, "entities", [1])),
		"entity unknown type": JSON.stringify(_with(good, "entities", [{"t": "nope", "x": 0, "y": 0}])),
		"entity missing x": JSON.stringify(_with(good, "entities", [{"t": "spawn", "y": 0}])),
		"entity x string": JSON.stringify(_with(good, "entities", [{"t": "spawn", "x": "0", "y": 0}])),
		"entity w zero": JSON.stringify(_with(good, "entities", [{"t": "zip", "x": 0, "y": 0, "w": 0, "h": 8}])),
		"entity w huge": JSON.stringify(_with(good, "entities", [{"t": "crumble", "x": 0, "y": 0, "w": 1e9, "h": 1e9}])),
		"entity w under 1": JSON.stringify(_with(good, "entities", [{"t": "zip", "x": 0, "y": 0, "w": 0.5, "h": 8}])),
		"entity x huge": JSON.stringify(_with(good, "entities", [{"t": "spawn", "x": 1e300, "y": 0}])),
		"entity tx string": JSON.stringify(_with(good, "entities", [{"t": "zip", "x": 0, "y": 0, "tx": "a"}])),
		"name not string": JSON.stringify(_with(good, "name", 3)),
	}
	for k in bad_cases:
		_write(tmp_path, bad_cases[k])
		check(Game.load_level(tmp) == {}, "load_level rejects %s" % k)
	_write(tmp_path, JSON.stringify(good, "\t"))
	var got := Game.load_level(tmp)
	check(got.get("w") is int and got.get("w") == 12 and got.get("h") == 8 and got.get("entities", []).size() == 3, "load_level accepts valid level with optional entity fields")
	DirAccess.remove_absolute(tmp_path)

	check_shipped_world()
	check_doors()
	check_placeholders()
	check_adventure()

	print("\n%d failure(s)" % fails)
	get_tree().quit(fails)
