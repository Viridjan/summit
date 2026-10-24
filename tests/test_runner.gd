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
		attack_buf -= dt
		if tap.has("attack"): attack_buf = INPUT_BUFFER
		tap.clear()
		jump_check = hold.has("jump")
		grab_check = hold.has("grab")

# Capture the real draw request at the texture boundary, without needing a display.
class EnemyDrawTexture extends Texture2D:
	var destinations: Array[Rect2] = []
	func _get_width() -> int: return 64
	func _get_height() -> int: return 240
	func _draw_rect_region(_canvas: RID, destination: Rect2, _source: Rect2, _modulate: Color, _transpose: bool, _clip: bool) -> void:
		destinations.append(destination)

class EnemyDrawProbe extends Node2D:
	var enemy
	func _draw() -> void:
		enemy.draw(self)

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
			w.update_energy(DT)
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

func check_environment_themes() -> void:
	var world := Game.Adventure.load_world("res://worlds/hollow_knight/world.json")
	var counts := {}
	var allowed := ["sand", "sea", "cavern", "cavern_deep", "sky", "temple", "building"]
	var valid := true
	for room_data in world.rooms.values():
		var environment: String = room_data.level.get("environment", "")
		valid = valid and environment in allowed
		counts[environment] = int(counts.get(environment, 0)) + 1
	check(valid, "every HK room has a supported environment")
	check(counts.size() == 7 and not counts.has(""), "HK rooms include all seven environment themes")
	var sample := Game.new_level("theme validation", 8, 8)
	sample.environment = "../../invalid"
	check(Game.validate_level(sample).is_empty(), "level validation rejects unknown environment paths")
	sample.environment = "building"
	check(Game.validate_level(sample).get("environment") == "building", "level validation preserves rural environment")
	var layer = load("res://scripts/tile_layer.gd").new()
	layer.setup(Game.new_level("themed chunks", 70, 70).tiles, 70, 70, "sea")
	check(layer.chunks[0].environment == "sea", "terrain chunks preserve their own room theme")
	check(Vector2i(0,0) in layer.mark_cell_dirty(Vector2i(32,32)), "themed corner edits invalidate diagonal caps")
	layer.setup(Game.new_level("rural chunks", 70, 70).tiles, 70, 70, "building")
	check(layer.chunks[0].environment == "building", "room changes replace the cached chunk theme")
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
	# entrance spawns (tools/world_fixups.py): on ground with 2 tiles of headroom, in every world
	for wp in [Game.ADVENTURE_DIR + "world.json"] + Game.world_list().slice(1).map(func(x): return x[1]):
		var wd := Adventure.load_world(wp)
		var bad_spawns := []
		var n_spawns := 0
		for rn in wd.rooms:
			var lv: Dictionary = wd.rooms[rn].level
			for e in lv.entities:
				if e.t == "spawn" and e.get("entrance", false):
					n_spawns += 1
					var tx := int(e.x) / 8
					var ty := int(e.y) / 8
					var ok: bool = ty >= 1 and ty + 1 < lv.h and lv.tiles[ty][tx] == "0" and lv.tiles[ty - 1][tx] == "0" and lv.tiles[ty + 1][tx] == "1"
					if not ok:
						bad_spawns.append(rn)
		check(n_spawns > 0 and bad_spawns.is_empty(), "%s: %d entrance spawns, all standing on ground (bad: %s)" % [wp.get_base_dir().get_file(), n_spawns, bad_spawns])
		# water and acid (tools/world_fixups.py settle_liquids): every row open, with rock just left and right of it
		var bad_liquid := []
		for rn in wd.rooms:
			var lv: Dictionary = wd.rooms[rn].level
			for e in lv.entities:
				if e.t in ["water", "acid"]:
					var x0 := int(e.x) / 8
					var x1 := x0 + int(e.w) / 8
					for y in range(int(e.y) / 8, (int(e.y) + int(e.h)) / 8):
						var row: String = lv.tiles[y]
						if row.substr(x0, x1 - x0).contains("1") or x0 < 1 or x1 >= lv.w or row[x0 - 1] != "1" or row[x1] != "1":
							bad_liquid.append(rn)
							break
		check(bad_liquid.is_empty(), "%s: water/acid rows run wall to wall (bad: %s)" % [wp.get_base_dir().get_file(), bad_liquid])
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
	check(listed.size() == 4 and listed[0][1] == Game.ADVENTURE_DIR + "world.json", "menu lists the main world, the story world and the 2 reference worlds (%d)" % listed.size())
	# story world (docs/STORY_DESIGN.md): jump only at the start, the first stretch of rooms
	var story := Adventure.load_world(Game.WORLDS_DIR + "story/world.json")
	check(story.start == "m1_meadow" and story.rooms.size() >= 4 and Adventure.overlaps(story).is_empty() and Adventure.new_run(story).abilities.is_empty(), "story world loads, starts in the meadow with jump only (%d rooms)" % story.rooms.size())
	var story_ents := []
	for rn in story.rooms:
		story_ents += story.rooms[rn].level.entities.map(func(e): return e.t)
	check(story_ents.has("energy_block") and story_ents.filter(func(t): return t.begins_with("enemy")).all(func(t): return t == "enemy_mosstrot"), "story has the town's energy block, and its only enemies are calm Mosstrots")
	# a bot holding right and jumping (jump only) goes meadow -> big jump (falls in) -> lake cave -> deep lake (falls in) -> back up -> cove town -> jungle
	Game.adv_world = story
	Game.adv = Adventure.new_run(story)
	Game.adv_temp = true
	Game.level = story.rooms[story.start].level
	var sw = load("res://scripts/world.gd").new()
	var keep_w = w
	w = sw
	add_child(sw)
	sw.set_physics_process(false)
	sw.player = Bot.new(sw, sw.spawn)
	p().hold = {"right": true, "jump": true}
	var story_seen := [sw.room]
	var walk := 0
	var jumped_at := -1.0
	for i in 12000:
		if sw.room == "j3_jungle_hills" and p().pos.x > 72 * 8 or p().dead:
			break
		var head: Rect2i = p().hurt_rect()
		head.position.y -= 8
		# one ground jump per landing (a second buffered tap would wall-jump); walk, don't jump, under a low ceiling (hollow trunks)
		if walk > 0:
			walk -= 1
		elif p().on_ground and p().speed.y >= 0 and sw.collide_solid(head) == null:
			if absf(p().pos.x - jumped_at) < 1:  # the last jump got nowhere (a trunk ahead): walk a bit instead
				walk = 20
			jumped_at = p().pos.x
			p().tap["jump"] = walk == 0
		step()
		if sw.room != story_seen[-1]:
			story_seen.append(sw.room)
	check(story_seen == ["m1_meadow", "m2_big_jump", "c1_lake_cave", "c4_deep_lake", "c1_lake_cave", "c2_cave_teeth", "c3_cove_tunnel", "t1_cove_town", "j1_jungle_edge", "j2_jungle_falls", "j3_jungle_hills"] and sw.deaths == 0, "story bot reaches the end of the jungle with jump only (%s, deaths %d, at tile %s)" % [story_seen, sw.deaths, (p().pos / 8).floor()])
	sw.queue_free()
	w = keep_w
	Game.adv = {}
	Game.adv_temp = false
	for w in listed.slice(1).filter(func(x): return not x[1].contains("/story/")):
		var rw := Adventure.load_world(w[1])
		var has_spawn: bool = rw.rooms.has(rw.start) and rw.rooms[rw.start].level.entities.any(func(e): return e.t == "spawn")
		check(rw.rooms.size() > 10 and has_spawn and Adventure.overlaps(rw).is_empty() and Adventure.new_run(rw).abilities == ["dash", "climb", "attack"], "%s loads: %d rooms, spawn, no overlaps, starts with dash+climb+attack" % [w[0], rw.rooms.size()])
		var ids := {}
		var door_to := []
		for rn in rw.rooms:
			for e in rw.rooms[rn].level.entities:
				if e.t == "door":
					ids[rn + ":" + e.id] = true
					door_to.append(e.to)
		check(door_to.all(func(t): return ids.has(t)), "%s: all %d doors lead to a door that exists" % [w[0], door_to.size()])
		# room boxes never overlap, and every room is reachable from the start (passages + doors)
		var names: Array = rw.rooms.keys()
		var boxes_ok := true
		for i in names.size():
			for j in range(i + 1, names.size()):
				if Adventure.room_rect(rw.rooms[names[i]]).intersects(Adventure.room_rect(rw.rooms[names[j]])):
					boxes_ok = false
		check(boxes_ok, "%s: no two room boxes overlap" % w[0])
		var nb := {}
		for a in names:  # touching rooms with open tiles on both sides of their shared edge
			var ra: Rect2i = Rect2i(rw.rooms[a].pos, Vector2i(rw.rooms[a].level.w, rw.rooms[a].level.h))
			for b in names:
				var rb: Rect2i = Rect2i(rw.rooms[b].pos, Vector2i(rw.rooms[b].level.w, rw.rooms[b].level.h))
				var linked := false
				if ra.end.x == rb.position.x:
					for ty in range(maxi(ra.position.y, rb.position.y), mini(ra.end.y, rb.end.y)):
						if Adventure._open(rw.rooms[a], ra.end.x - 1, ty) and Adventure._open(rw.rooms[b], rb.position.x, ty):
							linked = true
							break
				elif ra.end.y == rb.position.y:
					for tx in range(maxi(ra.position.x, rb.position.x), mini(ra.end.x, rb.end.x)):
						if Adventure._open(rw.rooms[a], tx, ra.end.y - 1) and Adventure._open(rw.rooms[b], tx, rb.position.y):
							linked = true
							break
				if linked:
					nb[a] = nb.get(a, []) + [b]
					nb[b] = nb.get(b, []) + [a]
		for rn in rw.rooms:
			for e in rw.rooms[rn].level.entities:
				if e.t == "door":
					var tr: String = str(e.to).get_slice(":", 0)
					nb[rn] = nb.get(rn, []) + [tr]
					nb[tr] = nb.get(tr, []) + [rn]
		var reach := {rw.start: true}
		var queue := [rw.start]
		while not queue.is_empty():
			for n in nb.get(queue.pop_back(), []):
				if n != "" and not reach.has(n):
					reach[n] = true
					queue.append(n)
		check(reach.size() == rw.rooms.size(), "%s: every room is reachable from the start (%d/%d)" % [w[0], reach.size(), rw.rooms.size()])

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

func check_dirs() -> void:
	make_world([])
	var pl = p()
	pl.facing = 1
	pl.aim_raw = Vector2(1, -1).normalized()  # up-right held
	var want := {1: Vector2.RIGHT, -1: Vector2.UP, 2: Vector2.UP, 3: Vector2(1, -1).normalized(), 4: Vector2(1, -1).normalized()}
	for m in want:
		check(pl.dir_for(m).is_equal_approx(want[m]), "dirs mode %d with up-right held -> %s (got %s)" % [m, want[m], pl.dir_for(m)])
	pl.aim_raw = Vector2.ZERO
	check(pl.dir_for(1) == Vector2.RIGHT and pl.dir_for(-1) == Vector2.UP and pl.dir_for(3) == Vector2.RIGHT, "no direction held: facing (vertical-only: up)")
	pl.aim_free = Vector2(0.9, 0.3).normalized()
	check(pl.dir_for(4).is_equal_approx(Vector2(0.9, 0.3).normalized()) and pl.dir_for(3) == Vector2.RIGHT, "free aim follows the stick; 8-way ignores it")
	pl.aim_free = Vector2.ZERO
	pl.DASH_DIRS = 0
	pl.ATTACK_DIRS = 0
	step(5)
	pl.tap = {"dash": true}
	step()
	pl.tap = {"attack": true}
	step()
	check(pl.state == pl.ST_NORMAL, "mode 0 disables dash and attack")
	pl.DASH_DIRS = 1
	pl.hold = {"up": true}
	pl.tap = {"dash": true}
	step(8)
	check(pl.state == pl.ST_DASH and pl.dash_dir == Vector2.RIGHT, "horizontal-only dash ignores up (%s, state %d)" % [pl.dash_dir, pl.state])

func check_floor_gaps() -> void:
	# an opening in the bottom row of a plain level is a pit (red marker)
	if w:
		w.queue_free()
	var d := Game.new_level("gaps", 20, 10)
	var row: String = d.tiles[9]
	d.tiles[9] = row.substr(0, 5) + "00" + row.substr(7)
	d.entities = [{"t": "spawn", "x": 16, "y": 64}]
	Game.level = d
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	check(w.floor_gaps == [[40, 56, false]], "bottom-edge opening is marked as a pit (%s)" % [w.floor_gaps])

func check_room_seams() -> void:
	# two rooms stacked: room a's floor is open at x 2..3 (above rock in b) and at x 6..7 (above open space in b)
	const Adventure := preload("res://scripts/adventure.gd")
	var la := Game.new_level("a", 10, 6)
	var lb := Game.new_level("b", 10, 6)
	la.tiles = ["1111111111", "1000000001", "1000000001", "1000000001", "1000000001", "1100110011"]
	lb.tiles = ["1111110011", "1000000001", "1000000001", "1000000001", "1111111111", "1111111111"]
	la.entities = [{"t": "spawn", "x": 8, "y": 32}]
	lb.entities = []
	var world := {"start": "a", "abilities": [], "rooms": {"a": {"pos": Vector2i(0, 0), "level": la}, "b": {"pos": Vector2i(0, 6), "level": lb}}}
	Game.adv_world = world
	Game.adv = Adventure.new_run(world)
	Game.adv_temp = true
	Game.level = la
	if w:
		w.queue_free()
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)
	p().pos = Vector2(24, 40)  # above the hole whose floor below is the next room's rock
	step(30)
	check(w.room == "a" and w.collide_solid(p().hitbox()) == null and not p().dead, "the next room's rock blocks at the edge: no falling into it (room %s, at %s)" % [w.room, p().pos])
	p().pos = Vector2(56, 40)  # above the hole that opens into b
	step(40)
	check(w.room == "b" and w.collide_solid(p().hitbox()) == null, "an open seam still leads into the next room (room %s)" % w.room)
	w.queue_free()
	w = null
	Game.adv = {}

func check_attack() -> void:
	# wall 2 tiles right of the spawn (player at x 80): three swings break it, it stays broken after a death
	make_world([{"t": "breakwall", "x": 96, "y": 26 * 8, "w": 8, "h": 16}])
	step(5)
	var wall = w.ents.filter(func(e): return e.d.t == "breakwall")[0]
	p().hold = {"right": true}
	step(20)
	check(p().hitbox().end.x == 96, "breakable wall is solid (%d)" % p().hitbox().end.x)
	p().tap = {"attack": true}
	step()
	check(p().attacking() and p().state == p().ST_NORMAL and wall.hp == 2, "attack is a layer: state stays Normal while swinging, wall hit once")
	step(5)
	p().tap = {"attack": true}
	step()
	check(wall.hp == 2, "one swing hits a thing only once; attack cooldown holds a quick re-press")
	step(int(p().ATTACK_TIME / DT))
	check(not p().attacking(), "the swing ends after ATTACK_TIME")
	for i in 2:
		step(int(p().ATTACK_COOLDOWN / DT) + 1)
		p().tap = {"attack": true}
		step()
	check(not wall.collidable and w.broken.size() == 1, "third hit breaks the wall")
	step(20)
	check(p().hitbox().end.x > 104, "player walks through the broken wall")
	p().hold = {"left": true}
	p().tap = {"attack": true}
	step(int(p().ATTACK_COOLDOWN / DT) + 1)
	p().tap = {"attack": true}
	step()
	check(p().attack_dir == Vector2.LEFT, "swing points where the player pushes")
	step(int(p().ATTACK_COOLDOWN / DT) + 1)
	p().tap = {"attack": true, "dash": true}
	step(3)
	check(p().state == p().ST_DASH and p().attacking(), "dash attack: the swing goes on during a dash (state %d)" % p().state)
	w._build()
	check(w.ents.filter(func(e): return e.d.t == "breakwall")[0].collidable == false, "a broken wall stays broken after respawn")

func check_connected_block_art() -> void:
	var script_path := "res://scripts/block_art.gd"
	check(ResourceLoader.exists(script_path), "special blocks have connected piece artwork")
	if not ResourceLoader.exists(script_path): return
	var art = load(script_path)
	for style in ["breakwall", "crumble", "falling", "zip", "dream", "jumpthru"]:
		for size in [Vector2i(8, 8), Vector2i(24, 16), Vector2i(29, 13), Vector2i(32, 5)]:
			var piece: Image = art.build_piece(style, size)
			check(piece.get_size() == size and piece.get_used_rect() == Rect2i(Vector2i.ZERO, size), "%s artwork fits whole pieces and partial tiles at %s" % [style, size])
		var wide: Image = art.build_piece(style, Vector2i(40, 24))
		check(wide.get_pixel(0, 7) != wide.get_pixel(8, 7) and wide.get_pixel(39, 7) != wide.get_pixel(31, 7), "%s outlines appear at external left/right edges rather than every tile" % style)
		check(wide.get_pixel(7, 0) != wide.get_pixel(7, 8) and wide.get_pixel(7, 23) != wide.get_pixel(7, 15), "%s top/bottom caps remain outside the centre tiles" % style)
		check(art.texture(style, Vector2i(24, 16)) == art.texture(style, Vector2i(24, 16)), "%s shares cached artwork between equal pieces" % style)
	var intact: Image = art.build_piece("breakwall", Vector2i(24, 24), 0)
	var cracked: Image = art.build_piece("breakwall", Vector2i(24, 24), 2)
	check(intact.get_data() != cracked.get_data(), "struck breakable walls show additional connected cracks")
	var samples := []
	for style in ["breakwall", "crumble", "falling", "zip", "dream", "jumpthru"]:
		samples.append(art.build_piece(style, Vector2i(24, 16)).get_pixel(5, 5))
	var unique_colors := {}
	for color in samples: unique_colors[color] = true
	check(unique_colors.size() == 6, "special block materials have distinct colours")

func check_enemy_facing_alignment() -> void:
	var art = load("res://scripts/enemy_art.gd")
	var previous: Texture2D = art._texture
	var recording := EnemyDrawTexture.new()
	art._texture = recording
	# Every enemy type draws centred on its own hitbox (giants and brood children are scaled).
	var fixtures := []
	for t in E.TYPES:
		if t.begins_with("enemy_"):
			fixtures.append([t, E.make(null, {"t": t, "x": 100, "y": 90}).center()])
	for fixture in fixtures:
		var probe := EnemyDrawProbe.new()
		probe.enemy = E.make(null, {"t": fixture[0], "x": 100, "y": 90})
		add_child(probe)
		for facing in [-1, 1]:
			probe.enemy.facing = facing
			recording.destinations.clear()
			probe.queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			var aligned := not recording.destinations.is_empty()
			if aligned:
				var destination: Rect2 = recording.destinations[-1]
				# Godot flips a negative width in-place; it does not move the origin left.
				var drawn_centre := destination.position + destination.size.abs() / 2
				aligned = drawn_centre == fixture[1] and signf(destination.size.x) == facing
			check(aligned, "%s facing %d stays centred on its spawn hitbox before moving" % [fixture[0], facing])
		probe.free()
	art._texture = previous

func check_combat_enemies() -> void:
	var art = load("res://scripts/enemy_art.gd")
	var atlas: Image = art.atlas()
	var enemy_ids := E.TYPES.keys().filter(func(t): return t.begins_with("enemy_"))
	check(art.KINDS == enemy_ids, "sprite atlas rows match the enemy registry, in order")
	check(atlas.get_size() == Vector2i(4 * art.SIZE, art.SIZE * enemy_ids.size()), "every enemy type has a four-frame row in the atlas")
	for row in enemy_ids.size():
		check(atlas.get_region(Rect2i(0, row * art.SIZE, art.SIZE, art.SIZE)).get_used_rect().has_area(), "enemy sprite row %d contains visible artwork" % row)
	Game.settings.invincible = true
	# Thornmite crawls up, over and down a block on the floor without entering it
	make_world([{"t": "enemy_thornmite", "x": 200, "y": 216, "facing": 1}], [[30, 26], [31, 26], [30, 27], [31, 27]])
	var enemy = w.ents.filter(func(e): return e.d.t == "enemy_thornmite")[0]
	p().pos = Vector2(80, 216)
	var topped := false
	var inside := false
	for i in 600:
		enemy.update(DT)
		topped = topped or enemy.rect.position.y <= 200
		inside = inside or enemy.blocked(enemy.rect)
	check(topped and enemy.rect.position.x >= 256 and enemy.rect.position.y == 216 and not inside, "Thornmite crawls over a block and back down to the floor (at %s)" % enemy.rect.position)
	make_world([{"t": "enemy_thornmite", "x": 200, "y": 100}])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_thornmite")[0]
	for i in 200: enemy.update(DT)
	check(enemy.rect.position.y == 216, "Thornmite placed in the air drops to the floor and clings to it (y %d)" % enemy.rect.position.y)

	# Hornback spots the player at its height, warns, then charges and stops at a wall
	make_world([{"t": "enemy_hornback", "x": 160, "y": 214, "facing": 1}], [[30, 26], [30, 27]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_hornback")[0]
	p().pos = Vector2(232, 224)
	enemy.update(DT)
	check(enemy.phase == "windup", "Hornback warns before charging a player at its height")
	var start_x: int = enemy.rect.position.x
	for i in 20: enemy.update(DT)
	check(enemy.phase == "windup" and enemy.rect.position.x == start_x, "Hornback holds still during its warning")
	for i in 20: enemy.update(DT)
	check(enemy.phase == "charge" and enemy.rect.position.x > start_x, "then it charges")
	p().pos = Vector2(400, 100)
	for i in 120: enemy.update(DT)
	check(enemy.rect.end.x <= 240 and enemy.phase != "charge" and not enemy.blocked(enemy.rect), "Hornback's charge stops at a wall without tunnelling")
	make_world([{"t": "enemy_hornback", "x": 164, "y": 150, "facing": 1}], [[20, 20], [21, 20], [22, 20]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_hornback")[0]
	p().pos = Vector2(280, 160)
	var charged := false
	for i in 300:
		enemy.update(DT)
		charged = charged or enemy.phase == "charge"
	check(charged, "Hornback charges a player across the gap")
	check(enemy.rect.position.y == 150, "Hornback's charge stops at a ledge instead of running off it")

	# Fuzzbob drifts diagonally and bounces off walls and floors
	make_world([{"t": "enemy_fuzzbob", "x": 170, "y": 100, "facing": 1}], [[24, 8], [24, 9], [24, 10], [24, 11], [24, 12], [24, 13], [24, 14], [24, 15], [24, 16]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_fuzzbob")[0]
	var flipped_x := false
	var flipped_y := false
	var stuck := false
	for i in 600:
		var v: Vector2 = enemy.velocity
		enemy.update(DT)
		flipped_x = flipped_x or signf(enemy.velocity.x) != signf(v.x)
		flipped_y = flipped_y or signf(enemy.velocity.y) != signf(v.y)
		stuck = stuck or enemy.blocked(enemy.rect)
	check(flipped_x and flipped_y and not stuck, "Fuzzbob bounces off walls and floors without entering rock")

	make_world([{"t": "enemy_skree", "x": 160, "y": 64}])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_skree")[0]
	p().pos = Vector2(164, 148)
	enemy.update(DT)
	check(enemy.phase == "windup", "Dropwing notices a player below and telegraphs the dive")
	for i in 10: enemy.update(DT)
	check(enemy.rect.position.y == 64, "Dropwing stays on the ceiling during its warning")
	p().pos = Vector2(80, 216)
	for i in 500: enemy.update(DT)
	check(enemy.phase == "idle" and enemy.rect.position.y == 64, "Dropwing lands, rests, and returns to its ceiling perch")

	make_world([{"t": "enemy_bat", "x": 136, "y": 112}], [[20, 14], [20, 15], [20, 16]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_bat")[0]
	p().pos = Vector2(184, 128)
	for i in 90: enemy.update(DT)
	check(enemy.phase == "idle", "Duskflit cannot acquire a target through solid terrain")
	make_world([{"t": "enemy_bat", "x": 136, "y": 80}])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_bat")[0]
	p().pos = Vector2(160, 140)
	enemy.update(DT)
	check(enemy.phase == "windup", "Duskflit warns before swooping at a visible target")
	for i in 26: enemy.update(DT)
	var locked: Vector2 = enemy.velocity
	p().pos = Vector2(80, 216)
	enemy.update(DT)
	check(enemy.phase == "swoop" and enemy.velocity == locked and not enemy.blocked(enemy.rect), "Duskflit commits to its swoop instead of homing unfairly")

	make_world([{"t": "enemy_skeleton", "x": 180, "y": 204}])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_skeleton")[0]
	p().pos = Vector2(80, 216)
	for i in 100: enemy.update(DT)
	check(not enemy.bones.is_empty() and enemy.phase == "idle", "Ossling winds up, then throws a timed ballistic bone toward the player")
	enemy.bones = [[p().center() + Vector2(10, 0), Vector2.ZERO, 1.0]]
	p().attack_timer = 0.1
	p().attack_dir = Vector2.RIGHT
	enemy.update_bones(DT)
	check(enemy.bones.is_empty(), "Melee swings can swat an incoming bone")
	p().attack_timer = 0
	enemy.bones = [[Vector2(10, 80), Vector2(-180, 0), 1.0]]
	for i in 10: enemy.update_bones(DT)
	check(enemy.bones.is_empty(), "Ossling projectiles are removed at room bounds")
	make_world([{"t": "enemy_skeleton", "x": 180, "y": 204}], [[25, 18], [25, 19]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_skeleton")[0]
	enemy.bones = [[Vector2(195, 150), Vector2(180, 0), 1.0]]
	for i in 5: enemy.update_bones(DT)
	check(enemy.bones.is_empty(), "Bones collide with intervening terrain instead of passing through it")

	make_world([{"t": "enemy_thornmite", "x": 92, "y": 216}])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_thornmite")[0]
	p().pos = Vector2(80, 216)
	p().attack_dir = Vector2.RIGHT
	p()._attack_hits()
	p()._attack_hits()
	check(enemy.hp == 1, "Existing melee sector damages a real enemy once per swing")
	enemy.flash = 0
	p().attack_hit.clear()
	p()._attack_hits()
	check(not enemy.collidable, "A second melee swing defeats the two-hit crawler")
	Game.settings.invincible = false
	enemy.touch(p())
	check(not p().dead, "Defeated enemies no longer deal contact damage")
	var live = E.make(w, {"t": "enemy_bat", "x": 80, "y": 200})
	live.touch(p())
	check(p().dead, "Live enemy contact uses the existing player death system")

	# A ledge walker may turn, but must never step off the end of its floor.
	make_world([{"t": "enemy_skeleton", "x": 160, "y": 148}], [[20, 20], [21, 20]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_skeleton")[0]
	p().pos = Vector2(400, 216)
	for i in 240: enemy.update(DT)
	check(enemy.rect.position.y == 148 and enemy.rect.position.x >= 160 and enemy.rect.end.x <= 176, "Ossling patrol turns at ledges rather than walking into a pit")

func check_enemy_variants() -> void:
	var art = load("res://scripts/enemy_art.gd")
	var atlas: Image = art.atlas()
	var row_of := func(t): return atlas.get_region(Rect2i(0, art.KINDS.find(t) * art.SIZE, art.SIZE, art.SIZE)).get_data()
	Game.settings.invincible = true
	make_world([])
	for t in E.TYPES:
		var v: String = E.CombatEnemy.variant_of(t)
		if not t.begins_with("enemy_") or v == "":
			continue
		var base: String = t.trim_suffix("_" + v)
		check(row_of.call(t) != row_of.call(base), "%s looks different from %s" % [t, base])
		var o = E.make(w, {"t": base, "x": 160, "y": 112, "facing": 1})
		var e = E.make(w, {"t": t, "x": 160, "y": 112, "facing": 1})
		var ok: bool = {"swift": e.hp <= o.hp, "armored": e.hp > o.hp, "giant": e.hp > o.hp and e.rect.size == o.rect.size * 2,
			"shielded": e.hp >= o.hp, "brood": e.hp >= o.hp, "venom": e.hp >= o.hp}[v]
		check(ok and (v == "giant" or e.rect.size == o.rect.size), "%s: %s stats and size fit the variant (hp %d vs %d, %s)" % [t, v, e.hp, o.hp, e.rect.size])
	check(E.TYPES.keys().filter(func(t): return t.begins_with("enemy_") and E.CombatEnemy.variant_of(t) == "").size() == 9, "nine enemy families")

	# Swift crawls faster, Giant slower
	var crawlers := []
	for t in ["enemy_thornmite", "enemy_thornmite_swift", "enemy_thornmite_giant"]:
		var c = E.make(w, {"t": t, "x": 160, "y": 216 - (8 if t.ends_with("giant") else 0), "facing": 1})
		crawlers.append(c)
	p().pos = Vector2(80, 216)
	for i in 30:
		for c in crawlers: c.update(DT)
	check(crawlers[1].rect.position.x > crawlers[0].rect.position.x and crawlers[2].rect.position.x - 160 < crawlers[0].rect.position.x - 160, "Swift crawler moves faster; Giant crawls slower")

	# Armored Ossling throws a two-arc volley, capped at three bones
	var armored = E.make(w, {"t": "enemy_skeleton_armored", "x": 180, "y": 204, "facing": 1})
	p().pos = Vector2(80, 216)
	armored.phase = "windup"
	armored.timer = DT / 2
	armored.update(DT)
	check(armored.bones.size() == 2, "Armored Ossling throws a two-arc volley")
	armored.timer = DT / 2
	armored.phase = "windup"
	armored.update(DT)
	check(armored.bones.size() <= 3, "Armored Ossling respects the three-projectile cap")

	# Shielded blocks hits from the front, not from behind or above
	var sh = E.make(w, {"t": "enemy_hornback_shielded", "x": 160, "y": 214, "facing": 1})
	var hp0: int = sh.hp
	p().pos = Vector2(190, 224)
	sh.hit(p())
	check(sh.hp == hp0, "Shielded Hornback blocks a hit from the front")
	p().pos = Vector2(140, 224)
	sh.flash = 0
	sh.hit(p())
	check(sh.hp == hp0 - 1, "Shielded Hornback takes a hit from behind")
	p().pos = Vector2(166, 190)
	sh.flash = 0
	sh.hit(p())
	check(sh.hp == hp0 - 2, "Shielded Hornback takes a hit from above")

	# Brood splits into two small, fast copies when killed
	make_world([{"t": "enemy_bat_brood", "x": 160, "y": 100}])
	var brood = w.ents.filter(func(x): return x.d.t == "enemy_bat_brood")[0]
	p().pos = Vector2(80, 216)
	while brood.collidable:
		brood.flash = 0
		brood.hit(p())
	w.after_player_move()
	var kids: Array = w.ents.filter(func(x): return x.d.get("brood_child", false))
	check(kids.size() == 2 and kids.all(func(k): return k.collidable and k.hp == 1 and k.rect.size.x < brood.rect.size.x), "Brood splits into two small copies (%d)" % kids.size())

	# Venom leaves short-lived puddles that kill on touch
	Game.settings.invincible = false
	make_world([{"t": "enemy_thornmite_venom", "x": 200, "y": 216, "facing": 1}])
	var venom = w.ents.filter(func(x): return x.d.t == "enemy_thornmite_venom")[0]
	p().pos = Vector2(80, 216)
	for i in 60: venom.update(DT)
	check(not venom.puddles.is_empty(), "Venom Thornmite leaves a puddle on the surface it crawls on")
	var puddle: Rect2i = venom.puddles[0][0]
	p().pos = Vector2(puddle.get_center().x, puddle.end.y)
	venom.update(DT)
	check(p().dead, "touching a venom puddle kills")
	make_world([{"t": "enemy_thornmite_venom", "x": 200, "y": 216, "facing": 1}])
	venom = w.ents.filter(func(x): return x.d.t == "enemy_thornmite_venom")[0]
	p().pos = Vector2(80, 216)
	for i in 60: venom.update(DT)
	for i in 300: venom.update(DT)
	check(venom.puddles.all(func(pd): return pd[1] > 0) and venom.puddles.size() <= 6, "venom puddles dry up after a few seconds")
	Game.settings.invincible = true

	# Giants draw at twice the size
	var probe := EnemyDrawProbe.new()
	var recording := EnemyDrawTexture.new()
	var previous: Texture2D = art._texture
	art._texture = recording
	probe.enemy = E.make(null, {"t": "enemy_hornback_giant", "x": 100, "y": 90})
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not recording.destinations.is_empty() and absf(recording.destinations[-1].size.y) == art.SIZE * 2, "Giant enemies draw at twice the size")
	probe.free()
	art._texture = previous
	Game.settings.invincible = false

# Cragjaw (leaping brute) and Murkspore (hovering spitter), the two big families.
func check_big_enemies() -> void:
	Game.settings.invincible = true
	make_world([{"t": "enemy_cragjaw", "x": 200, "y": 204, "facing": -1}])
	var c = w.ents.filter(func(x): return x.d.t == "enemy_cragjaw")[0]
	check(c.rect.size.x >= 16 and c.rect.size.y >= 16, "Cragjaw is a big enemy (%s)" % c.rect.size)
	p().pos = Vector2(120, 224)
	c.update(DT)
	check(c.phase == "windup", "Cragjaw warns before leaping")
	var rose := false
	var landed := false
	var inside := false
	for i in 240:
		c.update(DT)
		rose = rose or c.velocity.y < 0
		landed = landed or (rose and c.phase == "rest")
		inside = inside or c.blocked(c.rect)
	check(rose and landed and not inside, "Cragjaw leaps toward the player and slams down without entering rock")

	make_world([{"t": "enemy_murkspore", "x": 200, "y": 120}])
	var m = w.ents.filter(func(x): return x.d.t == "enemy_murkspore")[0]
	p().pos = Vector2(120, 216)
	var spat := 0
	for i in 200:
		m.update(DT)
		spat = maxi(spat, m.orbs.size())
	check(spat == 3, "Murkspore spits a three-orb spread (%d)" % spat)
	m.orbs = [[p().center() + Vector2(10, 0), Vector2.ZERO, 1.0]]
	p().attack_timer = 0.1
	p().attack_dir = Vector2.RIGHT
	m.update_orbs(DT)
	check(m.orbs.is_empty(), "Melee swings can swat an incoming orb")
	p().attack_timer = 0
	Game.settings.invincible = false
	m.orbs = [[p().center() + Vector2(4, 0), Vector2(-60, 0), 1.0]]
	m.update_orbs(DT)
	check(p().dead, "a Murkspore orb kills on touch")

func check_hk_combat_placements() -> void:
	var world_data: Dictionary = load("res://scripts/adventure.gd").load_world("res://worlds/hollow_knight/world.json")
	var count := {}
	var failures := []
	Game.settings.invincible = true
	for room_name in world_data.rooms:
		var level: Dictionary = world_data.rooms[room_name].level
		if not level.entities.any(func(e): return e.get("summit_enemy_set", 0) == 1):
			continue
		if w: w.queue_free()
		Game.level = level
		w = load("res://scripts/world.gd").new()
		add_child(w)
		w.set_physics_process(false)
		w.player = Bot.new(w, w.spawn)
		for enemy in w.ents:
			if not enemy.d.get("summit_enemy_set", false): continue
			count[enemy.d.t] = count.get(enemy.d.t, 0) + 1
			if enemy.blocked(enemy.rect): failures.append(room_name + ": solid spawn")
			for marker in level.entities:
				if marker.t in ["spawn", "door"] and Vector2(marker.x, marker.y).distance_to(Vector2(enemy.rect.position)) < 96:
					failures.append(room_name + ": enemy too close to entrance")
			w.player.pos = enemy.center() + Vector2(0, 40)
			for i in 240:
				enemy.update(DT)
				if enemy.blocked(enemy.rect):
					failures.append(room_name + ": enemy entered terrain/bounds")
					break
	var enemy_types: int = E.TYPES.keys().filter(func(t): return t.begins_with("enemy_")).size()
	check(count.size() == enemy_types and count.values().all(func(n): return n == 3), "HK contains three of each of the %d enemy types (%s)" % [enemy_types, count])
	check(failures.is_empty(), "HK enemy placements stay clear of entrances, terrain, and room bounds (%s)" % [failures])
	Game.settings.invincible = false

# Regressions from the code-health audit: each check failed before its fix.
func check_bugfixes() -> void:
	# free-aim dash (DASH_DIRS 4) slightly above horizontal still counts as horizontal: super jump works
	make_world([])
	step(5)
	p().DASH_DIRS = 4
	p().aim_free = Vector2(0.95, -0.15).normalized()
	p().hold = {"right": true}
	p().tap = {"dash": true}
	step(6)
	p().tap = {"jump": true}
	step(2)
	check(p().state == p().ST_NORMAL and p().speed.x > p().DASH_SPEED and p().speed.y < 0, "free-aim near-horizontal dash allows a super jump (speed.x %d)" % p().speed.x)

	# red bubble obeys DASH_DIRS: horizontal-only never shoots up
	make_world([{"t": "booster_red", "x": 80, "y": 26 * 8}])
	p().DASH_DIRS = 1
	p().hold = {"up": true}
	var red_dir := Vector2.ZERO
	for i in 60:
		step()
		if p().state == p().ST_RED_DASH and p().dash_dir != Vector2.ZERO:
			red_dir = p().dash_dir
			break
	check(red_dir != Vector2.ZERO and red_dir.y == 0, "red bubble follows DASH_DIRS (dash %s)" % red_dir)

	# Restart Level clears broken walls and a pending door
	make_world([{"t": "breakwall", "x": 96, "y": 26 * 8, "w": 8, "h": 16}])
	w.break_wall(w.star_key("x"))
	w.pending_door = w.ents[0]
	w._restart()
	check(w.broken.is_empty() and w.pending_door == null, "Restart Level un-breaks walls and drops a pending door")

	# a player who died this tick doesn't travel through a door touched in the same tick
	make_world([{"t": "door", "x": 200, "y": 200, "w": 8, "h": 24, "id": "a", "to": "b"},
		{"t": "door", "x": 400, "y": 120, "w": 8, "h": 24, "id": "b", "to": "a"}])
	p().pos = Vector2(204, 220)
	p().die(Vector2.ZERO)
	w.door_hit(w.ents.filter(func(e): return e.d.get("id", "") == "a")[0])
	w.after_player_move()
	check(p().dead and p().pos.distance_to(Vector2(204, 220)) < 1, "a dead player isn't moved by a door (at %s)" % p().pos)

	# Dropwing returning home under a ceiling gives up instead of pushing forever
	make_world([{"t": "enemy_skree", "x": 200, "y": 100}], [[25, 11], [26, 11]])
	var sk = w.ents.filter(func(e): return e.d.t == "enemy_skree")[0]
	sk.home.y = 40
	sk.phase = "return"
	step(30)
	check(sk.phase != "return", "Dropwing blocked on its way home stops returning (phase %s)" % sk.phase)

	# level validation rejects wrong types for enemy fields
	for bad in [{"facing": [1]}, {"patrol": {}}, {"top": "false"}]:
		var lv := Game.new_level("v", 10, 5)
		var e := {"t": "enemy_skree", "x": 8, "y": 8}
		e.merge(bad)
		lv.entities = [e]
		check(Game.validate_level(lv).is_empty(), "level with %s is rejected" % [bad])
	var ok := Game.new_level("v", 10, 5)
	ok.entities = [{"t": "enemy_skree", "x": 8, "y": 8, "facing": 1, "patrol": 40}, {"t": "acid", "x": 8, "y": 16, "top": false}]
	check(not Game.validate_level(ok).is_empty(), "valid facing/patrol/top still load")

	# a partial or hand-edited adventure save is filled from a fresh run instead of crashing
	const Adventure := preload("res://scripts/adventure.gd")
	var aw := Adventure.load_world(FIXTURE_WORLD + "world.json")
	var run := Adventure.restore_run(aw, {"room": "a2_little_gap", "spawn": [5], "deaths": "x", "visited": []})
	check(run.room == "a2_little_gap" and run.spawn == null and run.deaths == 0 and run.stars == [] and run.abilities is Array
		and run.visited == ["a2_little_gap"] and run.has("time"), "partial save gets defaults (%s)" % run)
	check(Adventure.restore_run(aw, "junk").room == aw.start and Adventure.restore_run(aw, {"room": "gone"}).room == aw.start, "unusable save starts a fresh run")
	Game.adv_world = aw
	Game.adv = Adventure.restore_run(aw, {"room": "a1_first_steps"})
	Game.adv_temp = true
	Game.level = aw.rooms.a1_first_steps.level
	if w:
		w.queue_free()
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	check(w.room == "a1_first_steps" and w.deaths == 0, "world starts from a restored partial save")

	# a door into a far room snaps the camera there instead of sweeping across the world
	var la := Game.new_level("a", 20, 10)
	var lb := Game.new_level("b", 20, 10)
	la.entities.append({"t": "door", "x": 80, "y": 40, "w": 8, "h": 24, "id": "d1", "to": "b:d2"})
	lb.entities.append({"t": "door", "x": 40, "y": 40, "w": 8, "h": 24, "id": "d2", "to": "a:d1"})
	Game.adv_world = {"start": "a", "abilities": [], "rooms": {"a": {"pos": Vector2i(0, 0), "level": la}, "b": {"pos": Vector2i(200, 0), "level": lb}}}
	Game.adv = Adventure.new_run(Game.adv_world)
	Game.level = la
	w.queue_free()
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)
	p().pos = Vector2(84, 60)
	step()
	check(w.room == "b" and w.cam_pos.distance_to(w._clamp_cam(p().camera_target())) < 1, "door to a far room snaps the camera (room %s, cam %s)" % [w.room, w.cam_pos])
	w.queue_free()
	w = null
	Game.adv = {}
	Game.adv_temp = false

	# a wall that is the next room's rock, right on the shared edge, can be climbed and wall-jumped like any wall
	var ra := Game.new_level("a", 10, 8)
	var rb := Game.new_level("b", 10, 8)
	ra.tiles = ["1111111111", "1000000000", "1000000000", "1000000000", "1000000000", "1000000000", "1111111111", "1111111111"]
	rb.tiles = ["1111111111", "1100000001", "1100000001", "1100000001", "1100000001", "1100000001", "1111111111", "1111111111"]
	ra.entities = [{"t": "spawn", "x": 16, "y": 40}]
	rb.entities = []
	Game.adv_world = {"start": "a", "abilities": ["climb"], "rooms": {"a": {"pos": Vector2i(0, 0), "level": ra}, "b": {"pos": Vector2i(10, 0), "level": rb}}}
	Game.adv = Adventure.new_run(Game.adv_world)
	Game.adv_temp = true
	Game.level = ra
	w = load("res://scripts/world.gd").new()
	add_child(w)
	w.set_physics_process(false)
	w.player = Bot.new(w, w.spawn)
	p().pos = Vector2(74, 30)  # in the air against the seam wall at x 80
	p().hold = {"right": true, "grab": true}
	var climbed := false
	for i in 20:
		step()
		climbed = climbed or p().state == p().ST_CLIMB
	check(climbed and w.room == "a", "grab a wall on the shared room edge (state %d, at %s)" % [p().state, p().pos])
	w.queue_free()
	w = null
	Game.adv = {}
	Game.adv_temp = false

	# editor: New/Load never keep a world room's file name; a drag released over the UI ends
	Game.editor_level = Game.new_level("room", 20, 10)
	Game.editor_dir = FIXTURE_WORLD
	Game.editor_file = "a1_first_steps"
	var ed = load("res://scripts/editor.gd").new()
	add_child(ed)
	check(ed.level == ed.saved_level, "an untouched level counts as saved (no leave prompt)")
	ed._new()
	check(Game.editor_file == "" and Game.editor_dir == Game.LEVEL_DIR, "editor New saves as a custom level, not over the world room")
	ed.tool = "breakwall"
	ed.rect_start = Vector2i(1, 1)
	ed.dragging_paint = 1
	ed._unhandled_input(InputEventMouseMotion.new())  # no button held
	check(ed.rect_start == null and ed.dragging_paint == 0, "mouse moving with no button held ends a drag")
	ed.queue_free()
	Game.editor_level = {}

# Monsters page (main menu) and the map screen's Map / Monsters tabs (L1 / R1).
# Themed backgrounds stay with the camera: the perspective shift is smooth and bounded (no wrap-around jumps).
func check_background_parallax() -> void:
	const EnvArt := preload("res://scripts/environment_art.gd")
	var area := Rect2(0, 0, 320, 2000)
	var last := EnvArt.parallax_shift(Rect2(0, 0, 320, 180), area)
	var smooth := true
	for y in range(0, 1821, 4):
		var s := EnvArt.parallax_shift(Rect2(0, y, 320, 180), area)
		smooth = smooth and absf(s.y - last.y) < 0.1 and absf(s.y) <= 18.0 and s.x == 0
		last = s
	check(smooth and is_equal_approx(last.y, -18.0), "background perspective shifts smoothly with vertical camera moves, within the overscan")

func check_bestiary() -> void:
	var b = load("res://scripts/bestiary.gd").new()
	add_child(b)
	check(b.rows.size() == 9 and b.rows[0] == "enemy_thornmite" and not b.rows.has("enemy"), "monsters page lists each enemy family once (%s)" % [b.rows])
	check(b.hp.get("enemy_cragjaw", 0) == 6 and b.hp.has("enemy_hornback_giant") and not b.hp.has("enemy_hornback_brood"), "monsters page shows each family's own variants")
	check(b.hp.get("enemy_thornmite", 0) == 2, "monsters page shows enemy HP")
	var borrowed := ["Ripper", "Medusa", "Skree", "Bat ", "Skeleton", "Puffling"]
	for t in E.TYPES:
		if t.begins_with("enemy_"):
			check(not borrowed.any(func(n): return (E.TYPES[t][0] + " ").contains(n)), "%s has an original name (%s)" % [t, E.TYPES[t][0]])
	b.queue_free()
	make_world([])
	var mv = load("res://scripts/map_view.gd").new(w)
	add_child(mv)
	check(mv.tab == 0 and not mv.bestiary.visible, "the map screen opens on the Map tab")
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
	ev.pressed = true
	mv._input(ev)
	check(mv.tab == 1 and mv.bestiary.visible, "R1 switches to the Monsters tab")
	ev.button_index = JOY_BUTTON_LEFT_SHOULDER
	mv._input(ev)
	check(mv.tab == 0 and not mv.bestiary.visible, "L1 switches back to the Map tab")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	mv._input(key)
	check(mv.tab == 1, "E switches tabs on the keyboard")
	mv.queue_free()

# Energy (docs/STORY_DESIGN.md section 3): 100 per block, regen only inside a partly spent block,
# a hit costs a block, the last block is a death.
func check_energy() -> void:
	const Adventure := preload("res://scripts/adventure.gd")
	var world := Adventure.load_world(FIXTURE_WORLD + "world.json")
	var run := Adventure.new_run(world)
	check(run.blocks == 1 and run.energy == 100.0, "a run starts with one full energy block")
	check(Adventure.spend_energy(run, 10) and run.energy == 90.0, "spending takes energy")
	Adventure.regen_energy(run, 1.0)
	check(is_equal_approx(run.energy, 93.0), "energy regenerates 3 per second (%s)" % run.energy)
	Adventure.regen_energy(run, 10.0)
	check(run.energy == 100.0, "regeneration stops at the top of the block")
	check(not Adventure.spend_energy(run, 150) and run.energy == 100.0, "can't spend more than you have")
	Adventure.add_energy_block(run)
	check(run.blocks == 2 and run.energy == 200.0, "a new block arrives full")
	Adventure.spend_energy(run, 100)
	Adventure.regen_energy(run, 10.0)
	check(run.energy == 100.0, "a fully spent block doesn't refill")
	Adventure.spend_energy(run, 30)
	Adventure.regen_energy(run, 100.0)
	check(run.energy == 100.0, "a partly spent block refills to its top")

	# in the world: a block pickup (once per run), hits, the attack gate
	Game.adv_world = world
	Game.adv = Adventure.new_run(world)
	Game.adv_temp = true
	make_world([{"t": "energy_block", "x": 80, "y": 26 * 8}])
	step(3)
	check(Game.adv.blocks == 2 and Game.adv.energy == 200.0 and Game.adv.taken.size() == 1, "energy block pickup adds a full block")
	make_world([{"t": "energy_block", "x": 80, "y": 26 * 8}])
	step(3)
	check(Game.adv.blocks == 2, "an energy block is taken once per run")
	p().die(Vector2.ZERO)
	check(w.deaths == 0 and Game.adv.energy == 100.0, "a hit with a block to spare costs the block, not a life")
	p().dead = false
	p().die(Vector2.ZERO)
	check(w.deaths == 1 and Game.adv.energy == 200.0, "a hit on the last block is a death and refills energy")
	# water drains 0.05 energy every 0.1 s and stops regeneration; at 0 energy in water the player dies
	make_world([{"t": "water", "x": 0, "y": 20 * 8, "w": 40 * 8, "h": 10 * 8}])
	step(5)
	Game.adv.energy = 150.0
	var before: float = Game.adv.energy
	step(60)
	check(w.in_water() and is_equal_approx(before - Game.adv.energy, 0.5), "a second in water costs 0.5 energy, no regeneration (%s)" % (before - Game.adv.energy))
	Game.adv.energy = 0.004
	var deaths_before: int = w.deaths
	step(2)
	check(p().dead and w.deaths == deaths_before + 1, "out of energy in water: the player dies")
	make_world([])
	step(5)
	p().tap = {"attack": true}
	step()
	check(not p().attacking(), "no attack before the attack ability")
	w.grant_ability("attack")
	step(5)
	p().tap = {"attack": true}
	step()
	check(p().attacking(), "attack works after picking it up")
	Game.adv = {}
	Game.adv_temp = false
	w.queue_free()
	w = null

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

	check_environment_themes()
	check_character_animation()
	check_connected_block_art()
	await check_enemy_facing_alignment()
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
	check(Tuning.names().size() == 99 and Tuning.names().all(func(n): return Tuning.group_of(n) != "Other"), "99 tunables, all grouped (%d)" % Tuning.names().size())
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
	check(back.MAX_RUN == 120.0 and back.DUCK_CORRECT_CHECK is int and back.size() == 99, "preset loads typed values")
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
		check(n.is_inside_tree() and n.get_child_count() > 0, "%s builds its UI" % s)
		n.queue_free()

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
	check_floor_gaps()
	check_room_seams()
	check_attack()
	check_combat_enemies()
	await check_enemy_variants()
	check_big_enemies()
	check_hk_combat_placements()
	check_dirs()
	check_adventure()
	check_energy()
	check_bugfixes()
	check_bestiary()
	check_background_parallax()

	print("\n%d failure(s)" % fails)
	get_tree().quit(fails)
