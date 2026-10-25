extends Node
# Deterministic gameplay regression suite. Bot supplies scripted input and step() advances a known number of 1/60-second updates. Each check describes expected behavior and failures contribute to the exit code.
# Reading help: docs/CODE_GUIDE.md.

# Headless physics checks. Run:  godot --headless --path . res://tests/test.tscn
# Exit code = number of failures.

const PlayerScript := preload("res://scripts/player.gd")
const E := preload("res://scripts/entities.gd")
const Tuning := preload("res://scripts/tuning.gd")
const DT := 1.0 / 60.0

# Scripted player input for repeatable tests; it uses the real movement implementation.
class Bot extends "res://scripts/player.gd":
	# scripted input instead of the keyboard
	var hold := {}  # action -> true
	var tap := {}
	# Initialize this test helper with the same production dependencies as its parent.
	func _init(world, spawn: Vector2) -> void:
		super(world, spawn)
	# Supply scripted actions instead of physical keyboard/gamepad events for deterministic movement.
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
		interact = tap.has("interact")
		tap.clear()
		jump_check = hold.has("jump")
		grab_check = hold.has("grab")

# Capture the real draw request at the texture boundary, without needing a display.
# Test texture boundary that records drawing requests without depending on GPU output.
class EnemyDrawTexture extends Texture2D:
	var destinations: Array[Rect2] = []
	# Report the stub texture width used to capture draw requests in tests.
	func _get_width() -> int: return 64
	# Report the stub texture height used to capture draw requests in tests.
	func _get_height() -> int: return 240
	# Capture the requested destination rectangle so tests can check drawing alignment without a rendered display.
	func _draw_rect_region(_canvas: RID, destination: Rect2, _source: Rect2, _modulate: Color, _transpose: bool, _clip: bool) -> void:
		destinations.append(destination)

# Canvas node that invokes real enemy drawing so test textures can capture the requested rectangles.
class EnemyDrawProbe extends Node2D:
	var enemy
	# Record the real draw request or its timing for this test helper.
	func _draw() -> void:
		enemy.draw(self)

# Editor test helper that records how often its background is redrawn.
class TrackedEditor extends "res://scripts/editor.gd":
	var background_draw_count := 0
	# Count background drawing before delegating to the production editor implementation.
	func _draw_background(ci: CanvasItem) -> void:
		background_draw_count += 1
		super(ci)

var fails := 0
var w

# Record a failed expectation with its explanation so the runner can report failures and return an appropriate exit code.
func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1

# Build a disposable level and scripted player so each test starts from a known terrain/object state.
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

# Advance a specified number of fixed physics steps with scripted input, making the test reproducible.
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

# Return the active scripted player in the current disposable test World.
func p():
	return w.player

# Make a deep fixture copy with one field replaced or removed, leaving the original test data intact.

func _with(d: Dictionary, key: String, v) -> Dictionary:
	var c := d.duplicate(true)
	if v == null:
		c.erase(key)
	else:
		c[key] = v
	return c

# Write fixture text to the requested scratch file for file-loading regression tests.
func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

# Verify terrain chunks still share the editable tile data after an editor operation.
func check_editor_tiles(ed, action: String) -> void:
	var expected := Vector2i(ceili(ed.level.w / 32.0), ceili(ed.level.h / 32.0))
	check(ed.tile_layer.chunk_grid == expected and ed.tile_layer.chunks.size() == expected.x * expected.y,
		"tile chunk grid follows editor %s" % action)
	check(is_same(ed.tile_layer.tiles, ed.level.tiles), "tile layer shares current editor tiles after %s" % action)

# Regression coverage for tile layer. The assertions below state the expected behavior of this case.
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

# Regression coverage for environment themes. The assertions below state the expected behavior of this case.
func check_environment_themes() -> void:
	var world := Game.Adventure.load_world("res://worlds/story/world.json")
	var counts := {}
	var valid := true
	for room_data in world.rooms.values():
		var environment: String = room_data.level.get("environment", "")
		valid = valid and environment in load("res://scripts/environment_art.gd").THEMES
		counts[environment] = int(counts.get(environment, 0)) + 1
	check(valid, "every story room has a supported environment")
	check(counts.size() >= 4 and not counts.has(""), "story rooms use several environment themes (%s)" % [counts.keys()])
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

# Regression coverage for character animation. The assertions below state the expected behavior of this case.
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
	var run_poses := {}
	var planted := true
	var lifted := 0
	var flight_poses := 0
	for i in 8:
		var pose := atlas.get_region(Rect2i(i*16,16,16,16))
		run_poses[pose.get_data().hex_encode()] = true
		var groups := 0
		var in_foot := false
		for x in 16:
			var shoe := pose.get_pixel(x,15).is_equal_approx(art.PALETTE.k)
			if shoe and not in_foot: groups += 1
			in_foot = shoe
			if pose.get_pixel(x,14).is_equal_approx(art.PALETTE.k): lifted += 1
		planted = planted and groups <= 1
		flight_poses += int(groups == 0)
	check(planted, "run poses never spread both planted feet along the ground")
	check(lifted > 0, "run cycle lifts the recovering foot above the ground")
	check(run_poses.size() == 8, "run cycle has eight distinct contact and passing poses")
	check(flight_poses == 2, "run includes a short flight pose between each planted step")
	check(art.frame("fall",100.0).x == 3 and art.frame("fall",100.13).x == 3 and art.frame("apex",100.0).x == 1 and art.frame("apex",100.2).x == 1, "airborne recovery settles instead of cycling the legs while falling")
	var idle_pose := atlas.get_region(Rect2i(0,0,16,16))
	var clear_face := true
	var airborne := true
	for animation in ["jump", "apex", "fall"]:
		var spec: Array = art.ANIMATIONS[animation]
		var poses := {}
		for i in int(spec[1]):
			var pose := atlas.get_region(Rect2i(i*16,int(spec[0])*16,16,16))
			poses[pose.get_data().hex_encode()] = true
			airborne = airborne and pose.get_data() != idle_pose.get_data()
			clear_face = clear_face and pose.get_region(Rect2i(5,4,6,5)).get_data() == idle_pose.get_region(Rect2i(5,4,6,5)).get_data()
		check(poses.size() == int(spec[1]), "%s has distinct authored airborne poses" % animation)
	check(clear_face, "airborne arms stay below the face instead of painting over it")
	check(airborne, "jump, apex and fall use airborne silhouettes rather than standing poses")
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

# Copy fixture world files into scratch storage so editing tests do not modify shipped rooms.

func _copy_world(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(FIXTURE_WORLD):
		if f.ends_with(".json"):
			_write(dir + f, FileAccess.get_file_as_string(FIXTURE_WORLD + f))

# Remove the temporary fixture files and their scratch directory after the test.

func _remove_dir(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)

# The shipped world: every room loads, nothing overlaps, every room is reachable through passages.
# (Movement reachability and ability gates were checked with the world generator's tools.)
# Regression coverage for shipped world. The assertions below state the expected behavior of this case.
func check_shipped_world() -> void:
	const Adventure := preload("res://scripts/adventure.gd")
	# entrance spawns (tools/world_fixups.py): on ground with 2 tiles of headroom, in every world
	for wp in [Game.STORY_WORLD]:
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
	# a cross-room door (the story's net trap) moves the player into the linked room
	var zebes := Adventure.load_world(Game.WORLDS_DIR + "story/world.json")
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
	check(w.room == str(door.to).get_slice(":", 0), "door %s:%s leads into room %s (now in %s)" % [src, door.id, str(door.to).get_slice(":", 0), w.room])
	w.queue_free()
	w = null
	Game.adv = {}
	# story world (docs/STORY_DESIGN.md): jump only at the start, the first stretch of rooms
	var story := Adventure.load_world(Game.WORLDS_DIR + "story/world.json")
	check(story.start == "m1_meadow" and story.rooms.size() >= 4 and Adventure.overlaps(story).is_empty() and Adventure.new_run(story).abilities.is_empty(), "story world loads, starts in the meadow with jump only (%d rooms)" % story.rooms.size())
	var story_ents := []
	for rn in story.rooms:
		story_ents += story.rooms[rn].level.entities.map(func(e): return e.t)
	check(story_ents.has("energy_block") and story_ents.filter(func(t): return t.begins_with("enemy")).all(func(t): return t == "enemy_mosstrot"), "story has the town's energy block, and its only enemies are calm Mosstrots")
	# a bot holding right and jumping (jump only) goes meadow -> big jump (falls in) -> lake cave (swims over the hole) -> cove town -> jungle
	Game.adv_world = story
	Game.adv = Adventure.new_run(story)
	Game.adv.blocks = 30  # a big energy budget: this checks the route, not the energy tuning (jumps and water drain it)
	Game.adv.energy = 3000.0
	Game.adv_temp = true
	Game.settings.invincible = true  # the route only: past The Hole there are hazards a hold-right bot can't dodge
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
	var kept_old := false
	var jumped_at := -1.0
	for i in 12000:
		if sw.room == "j3_jungle_hills" and p().pos.x > 72 * 8 or p().dead:
			break
		var head: Rect2i = p().hurt_rect()
		head.position.y -= 8
		# one ground jump per landing (a second buffered tap would wall-jump); walk, don't jump, under a low ceiling (hollow trunks)
		if walk > 0:
			walk -= 1
		elif p().state == p().ST_SWIM:  # swim: stroke whenever the last one is done
			if i % 15 == 0 and p().underwater:
				p().tap["jump"] = true
		elif p().on_ground and p().speed.y >= 0 and sw.collide_solid(head) == null:
			if absf(p().pos.x - jumped_at) < 1:  # the last jump got nowhere (a trunk ahead): walk a bit instead
				walk = 20
			jumped_at = p().pos.x
			if walk == 0:
				p().tap["jump"] = true
		step()
		if sw.room != story_seen[-1]:
			story_seen.append(sw.room)
			if sw.room == "j2_jungle_falls":  # dropped in from Jungle Edge, one screen above
				kept_old = sw.leaving_ents.any(func(e): return e.d.t == "leaf") and sw.leaving_rect == Rect2(0, -23 * 8, 40 * 8, 23 * 8)
	Game.settings.invincible = false
	check(story_seen == ["m1_meadow", "m2_big_jump", "m3_the_hole", "c1_lake_cave", "c2_cave_teeth", "c3_cove_tunnel", "t1_cove_town", "j1_jungle_edge", "j2_jungle_falls", "j3_jungle_hills"] and sw.deaths == 0, "story bot reaches the end of the jungle with jump only (%s, deaths %d, at tile %s)" % [story_seen, sw.deaths, (p().pos / 8).floor()])
	check(kept_old, "entering a room keeps drawing the old room's objects, in place, during the transition")
	# the hazards past The Hole can be crossed with plain jumps: the Ape's planner finds a spike-free run across
	# each room that is crossed left to right
	for rn in ["m1_meadow", "c2_cave_teeth", "c3_cove_tunnel", "j1_jungle_edge", "j3_jungle_hills", "s2_shore"]:
		Game.level = story.rooms[rn].level
		var pw = load("res://scripts/world.gd").new()
		add_child(pw)
		pw.set_physics_process(false)
		var lv: Dictionary = story.rooms[rn].level
		var starts: Array = lv.entities.filter(func(e): return e.t == "spawn")
		starts.sort_custom(func(a, b): return a.x < b.x)
		var sx: int = int(starts[0].x)
		var sy: int = int(starts[0].y) + 8
		var to_x: float = {"j1_jungle_edge": 30 * 8.0, "j3_jungle_hills": 31 * 8.0, "s2_shore": 54 * 8.0}.get(rn, lv.w * 8 - 24.0)  # up to the drop / the trunk / the lighthouse
		var run: PackedVector2Array = E.ApeChase.plan(pw, Rect2i(sx - 16, sy - 32, 32, 32), to_x, false, 0)
		check(not run.is_empty(), "%s: a spike-free path across with plain jumps" % rn)
		pw.free()
	# fundamental rule: respawn points are never in a hazard. Every spawn marker of every story room is safe
	# (out of water/acid, clear of spikes, on ground); a room with no safe point keeps the last safe respawn.
	var unsafe := []
	for rn in story.rooms:
		Game.adv = Adventure.new_run(story)
		Game.adv.room = rn
		Game.adv.spawn = null
		Game.level = story.rooms[rn].level
		var sw3 = load("res://scripts/world.gd").new()
		add_child(sw3)
		sw3.set_physics_process(false)
		for d in story.rooms[rn].level.entities:
			if d.t == "spawn" and not sw3.safe_spawn(Vector2(float(d.x) + 4, float(d.y) + 8)):
				unsafe.append("%s %d,%d" % [rn, d.x / 8, d.y / 8])
		sw3.free()
	check(unsafe.is_empty(), "every spawn marker is a safe respawn point (%s)" % [unsafe])
	Game.adv = Adventure.new_run(story)
	Game.adv.room = "c1_lake_cave"
	Game.adv.spawn = null
	Game.level = story.rooms["c1_lake_cave"].level
	var fw = load("res://scripts/world.gd").new()
	w = fw
	add_child(fw)
	fw.set_physics_process(false)
	var dry_spawn: Vector2 = fw.spawn
	var c4_origin: Vector2 = Vector2(story.rooms["c4_deep_lake"].pos * 8)
	var c1_origin: Vector2 = Vector2(story.rooms["c1_lake_cave"].pos * 8)
	fw.enter_room("c4_deep_lake", Vector2(20 * 8, 10 * 8))  # swimming in
	var kept: bool = fw.room == "c4_deep_lake" and fw.spawn_room == "c1_lake_cave" and Game.adv.room == "c1_lake_cave"
	p().die(Vector2.UP)
	fw.respawn_timer = 0.0
	fw.paused = false
	fw._physics_process(DT)
	check(kept and fw.room == "c1_lake_cave" and not p().dead and fw.spawn == dry_spawn,
		"a flooded room gets no respawn point: dying there returns to the last safe one (%s, %s, %s)" % [fw.room, fw.spawn_room, fw.spawn])
	fw.queue_free()
	# the Ape arena's walk-in is automatic on every entry, not only after a death: crossing in from the jungle
	Game.adv = Adventure.new_run(story)
	Game.adv.room = "j3_jungle_hills"
	Game.adv.spawn = null
	Game.level = story.rooms["j3_jungle_hills"].level
	var jw = load("res://scripts/world.gd").new()
	w = jw
	add_child(jw)
	jw.set_physics_process(false)
	var arena_y: float = (story.rooms["a1_ape_arena"].pos.y - story.rooms["j3_jungle_hills"].pos.y + 15) * 8.0
	jw.player = Bot.new(jw, Vector2(story.rooms["j3_jungle_hills"].level.w * 8 - 6, arena_y))
	p().hold = {"right": true}
	for k in 30:
		step()
		if jw.room == "a1_ape_arena":
			break
	p().hold = {}
	var entered_x: float = p().pos.x
	step(70)
	check(jw.room == "a1_ape_arena" and p().pos.x - entered_x > 40.0, "entering the Ape arena always walks the player in (from %.0f to %.0f)" % [entered_x, p().pos.x])
	jw.queue_free()
	# sideways room changes walk the player 1 unit in, to the middle of the second tile column, where they respawn
	Game.adv = Adventure.new_run(story)
	Game.adv.room = "c2_cave_teeth"
	Game.adv.spawn = null
	Game.level = story.rooms["c2_cave_teeth"].level
	var ww = load("res://scripts/world.gd").new()
	w = ww
	add_child(ww)
	ww.set_physics_process(false)
	ww.player = Bot.new(ww, Vector2(40 * 8 - 6, 19 * 8))
	p().hold = {"right": true}
	for k in 30:
		step()
		if ww.room == "c3_cove_tunnel":
			break
	p().hold = {}  # let go: the walk carries on by itself
	for k in 40:
		step()
	check(ww.cam_prev.distance_to(ww.cam_now) < 8.0, "render interpolation follows a room change instead of sweeping (cam %s -> %s)" % [ww.cam_prev, ww.cam_now])
	check(ww.room == "c3_cove_tunnel" and absf(p().pos.x - 12) <= 3 and absf(ww.spawn.x - 12) <= 1, "entering a room sideways walks 1 unit in and respawns there (at %s, spawn %s)" % [p().pos.x, ww.spawn.x])
	ww.queue_free()
	# house doors: standing at one (or pressing up) does nothing; interact goes inside, and again comes back out
	Game.adv = Adventure.new_run(story)
	Game.adv.room = "t1_cove_town"
	Game.adv.spawn = null
	Game.level = story.rooms["t1_cove_town"].level
	var hw = load("res://scripts/world.gd").new()
	w = hw
	add_child(hw)
	hw.set_physics_process(false)
	hw.player = Bot.new(hw, Vector2(88, 19 * 8))
	step(20)
	p().hold = {"up": true}
	step(5)
	p().hold = {}
	var stayed: bool = hw.room == "t1_cove_town" and hw.door_near != null
	p().tap = {"interact": true}
	step(3)
	var inside: String = hw.room
	step(20)  # one press: no bounce straight back
	var held_inside: String = hw.room
	p().tap = {"interact": true}
	step(3)
	check(stayed and inside == "h1_villager_house" and held_inside == inside and hw.room == "t1_cove_town", "house door: up does nothing, interact goes inside, a new press comes back out (%s, %s, %s)" % [inside, held_inside, hw.room])
	# door prompt: the interact button as a keycap, or the pad button once a pad is used
	var BA = load("res://scripts/button_art.gd")
	var key_ev := InputEventKey.new()
	Game._input(key_ev)
	var kt: Texture2D = BA.prompt("interact")
	var pad_ev := InputEventJoypadButton.new()
	pad_ev.pressed = true
	Game._input(pad_ev)
	var pt: Texture2D = BA.prompt("interact")
	var b_red: bool = Game.settings.pad.interact != JOY_BUTTON_B or pt.get_image().get_pixel(5, 2).r > 0.7
	Game.pad_ps = true
	var ps_t: Texture2D = BA.prompt("interact")
	Game.pad_ps = false
	check(ps_t != pt and ps_t.get_size() == Vector2(11, 11) and Game.is_ps_pad("PS5 Controller") and Game.is_ps_pad("Sony DualSense") and not Game.is_ps_pad("Xbox Series X Controller"),
		"PlayStation pads get their own symbols in prompts")
	Game._input(key_ev)
	check(kt.get_size() == Vector2(7, 10) and pt.get_size() == Vector2(11, 11) and b_red and BA.prompt("interact") == kt,
		"door prompt shows the interact key, or the pad button after pad input (%s, %s)" % [kt.get_size(), pt.get_size()])
	# the lighthouse: the shore door leads into the stairs, the stairs' top door out onto the lamp's gallery
	hw.player.pos = Vector2(0, 0)
	hw.enter_room("s2_shore", Vector2(45 * 8, 19 * 8))
	step(5)
	p().tap = {"interact": true}
	step(3)
	var in_stairs: String = hw.room
	p().pos = Vector2(16 * 8, 5 * 8)  # at the top door (as if climbed)
	step(5)
	p().tap = {"interact": true}
	step(3)
	check(in_stairs == "lh1_lighthouse_stairs" and hw.room == "s3_lighthouse_top", "lighthouse: shore door into the stairs, top door out to the lamp (%s, %s)" % [in_stairs, hw.room])
	# the sand cave: the Ape waits, wakes once the player passes its trigger, and chases by the player's own
	# movement rules; standing still gets the player caught, reaching the end makes it give up for the run
	E.ApeChase._plans.clear()
	hw.enter_room("s1_sand_cave", Vector2(2 * 8, 39 * 8))
	step(5)
	var ape = hw.ents.filter(func(e): return e.d.t == "ape_chase")[0]
	for k in 60:
		if ape.planner.done:
			break
		step()
	check(ape.planner.done and not ape.path.is_empty() and ape.planner.max_run_ms < E.ApeChase.PLAN_SLICE_MS + 4,
		"sand cave Ape: plans its route a slice per frame while waiting (worst frame %.1f ms, total %.1f ms)" % [ape.planner.max_run_ms, ape.planner.spent_ms])
	var waited: bool = ape.phase == "wait" and not ape.hurts()
	p().pos = Vector2(15 * 8, 35 * 8)
	step(2)
	var woke: bool = ape.phase == "roar"
	step(400)
	check(waited and woke and p().dead, "sand cave Ape: waits, screams past the trigger, catches a player who stands still (%s)" % ape.phase)
	# corners don't save you: a tunnel-high kill line moves with the Ape; once it's past the player, they die
	p().dead = false
	hw.enter_room("s1_sand_cave", Vector2(2 * 8, 39 * 8))
	step(2)
	ape = hw.ents.filter(func(e): return e.d.t == "ape_chase")[0]
	p().pos = Vector2(15 * 8, 35 * 8)
	step(2)
	ape.phase = "chase"
	var past := 0
	while past < ape.path.size() - 1 and ape.path[past].x <= p().center().x + 1:
		past += 1
	ape.at = past  # its next replayed frame is just past the player, whatever their height
	step()
	check(p().dead, "sand cave Ape: once it's past the player (at any height) it's game over")
	# the whole run, at a player waiting past its end: it smashes every hanging rock (blinking, hurt), then
	# stops at its end as the ceiling caves in ahead of it, sealing the way back for good
	p().dead = false
	hw.enter_room("s1_sand_cave", Vector2(2 * 8, 39 * 8))
	step(2)
	ape = hw.ents.filter(func(e): return e.d.t == "ape_chase")[0]
	var rocks: Array = hw.solids.filter(func(e): return e is E.BreakWall)
	check(rocks.size() >= 6 and rocks.all(func(e): return e.collidable and hw.collide_solid(e.rect) == e), "sand cave: hanging rocks and the low ceiling are solid for the player (%d)" % rocks.size())
	Game.settings.invincible = true
	p().pos = Vector2(117 * 8, 9 * 8)
	var blinks := 0
	var was_flash := false
	var landed := false
	for i in 60 * 30:
		step()
		if ape.flash > 0 and not was_flash:
			blinks += 1
		was_flash = ape.flash > 0
		landed = landed or not ape.debris.is_empty()
	Game.settings.invincible = false
	var touched := false
	var on_breakable := false
	for f in ape.path:
		var feet := Rect2i(int(f.x) - 3, int(f.y) - 8, 6, 8)
		touched = touched or hw.touching_spikes(feet)
		for e in hw.solids:
			if (e is E.Crumble and e.rect.intersects(Rect2i(int(f.x) - 4, int(f.y) - 11, 8, 12))) or (e is E.BreakWall and e.rect.intersects(Rect2i(int(f.x) - 4, int(f.y), 8, 1))):
				on_breakable = true
	check(not on_breakable, "sand cave Ape: its path never touches crumble nor stands on breakable rock")
	check(rocks.all(func(e): return not e.collidable) and blinks == rocks.size(), "sand cave Ape: smashes every rock on its way, hurt (blinks) by each (%d blinks, %d rocks)" % [blinks, rocks.size()])
	check(landed, "sand cave Ape: its landings shake debris off the ceiling")
	var clipped := 0
	var ape_last: Vector2 = ape.path[-1] if not ape.path.is_empty() else Vector2.ZERO
	var keep_pos: Vector2i = ape.rect.position
	for f in ape.path:
		ape.rect.position = Vector2i(roundi(f.x - ape.SIZE / 2.0), roundi(f.y) - ape.SIZE)
		var c = hw.collide_solid(ape.touch_rect(), ape)
		if c != null and not c is E.BreakWall and not c is E.FallingBlock:
			clipped += 1
	ape.rect.position = keep_pos
	check(clipped == 0, "sand cave Ape: its whole body stays out of the terrain along the path (%d frames clip)" % clipped)
	check(ape.path.size() > 60 and ape_last.x >= 98 * 8 and not touched and ape.rect.end.y == int(ape_last.y),
		"sand cave Ape: replays a planned run up the cave to its end, by the player's rules, never on spikes (%d frames to x %d)" % [ape.path.size(), ape_last.x])
	var seal := Rect2i(ape.d.seal[0], ape.d.seal[1], ape.d.seal[2], ape.d.seal[3])
	check(ape.phase == "gone" and hw.broken.has(ape.id) and hw.collide_solid(seal) is E.FallingBlock and seal.position.x > ape_last.x,
		"sand cave Ape: reaching its end, the ceiling caves in just ahead of it and it's done (%s)" % ape.phase)
	hw.enter_room("s1_sand_cave", Vector2(2 * 8, 39 * 8))
	step(2)
	check(hw.collide_solid(seal) is E.FallingBlock, "sand cave: the cave-in stays for the rest of the run")
	check(hw.solids.filter(func(e): return e is E.BreakWall).all(func(e): return e.collidable), "sand cave: smashed rocks are back when the room is entered again")
	hw.queue_free()
	sw.queue_free()
	w = keep_w
	Game.adv = {}
	Game.adv_temp = false
	# The chase plan cache keys on every planner input: endpoint, terrain, tuning; identical inputs reuse it.
	E.ApeChase._plans.clear()
	var chase_end := func(end_x: int, wall := false) -> float:
		var lv := Game.new_level("cache_probe", 60, 30)
		if wall:
			for y in range(20, 27):
				lv.tiles[y] = lv.tiles[y].substr(0, 30) + "1" + lv.tiles[y].substr(31)
		lv.entities = [{"t": "spawn", "x": 100, "y": 216}, {"t": "ape_chase", "x": 64, "y": 192, "trigger": 0, "end": end_x}]
		Game.level = lv
		var cw = load("res://scripts/world.gd").new()
		add_child(cw)
		cw.set_physics_process(false)
		var chaser = cw.ents.filter(func(e): return e.d.t == "ape_chase")[0]
		chaser.update(1.0 / 60.0)
		var last: float = chaser.path[-1].x if not chaser.path.is_empty() else -1.0
		cw.free()
		return last
	var near: float = chase_end.call(200)
	var far: float = chase_end.call(350)
	check(far > near + 100, "chase plans differ for different endpoints (%.0f vs %.0f)" % [near, far])
	var cached: int = E.ApeChase._plans.size()
	chase_end.call(350)
	check(E.ApeChase._plans.size() == cached, "identical chase inputs reuse the cached plan")
	chase_end.call(350, true)
	check(E.ApeChase._plans.size() == cached + 1, "changed terrain plans the chase again")
	Game.tuning = {"MAX_RUN": 120.0}
	chase_end.call(350)
	Game.tuning = {}
	check(E.ApeChase._plans.size() == cached + 2, "changed tuning plans the chase again")
	# no route at all (a wall it can't climb): planning gives up within its budget and the Ape leaves on its trigger
	var nl := Game.new_level("no_route", 60, 30)
	for y in range(5, 27):
		nl.tiles[y] = nl.tiles[y].substr(0, 30) + "1" + nl.tiles[y].substr(31)
	nl.entities = [{"t": "spawn", "x": 100, "y": 216}, {"t": "ape_chase", "x": 64, "y": 192, "trigger": 0, "end": 400}]
	Game.level = nl
	var nw = load("res://scripts/world.gd").new()
	add_child(nw)
	nw.set_physics_process(false)
	var lost = nw.ents.filter(func(e): return e.d.t == "ape_chase")[0]
	var t_plan := Time.get_ticks_msec()
	lost.update(1.0 / 60.0)
	var plan_ms := Time.get_ticks_msec() - t_plan
	check(lost.path.is_empty() and plan_ms < E.ApeChase.PLAN_BUDGET_MS * 3 and lost.phase == "dying", "no route: planning stops in budget (%d ms) and the Ape leaves (%s)" % [plan_ms, lost.phase])
	nw.free()
	E.ApeChase._plans.clear()

# Regression coverage for doors. The assertions below state the expected behavior of this case.
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

# Regression coverage for placeholders. The assertions below state the expected behavior of this case.
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

# Regression coverage for dirs. The assertions below state the expected behavior of this case.
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

# Regression coverage for floor gaps. The assertions below state the expected behavior of this case.
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

# Regression coverage for room seams. The assertions below state the expected behavior of this case.
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

# Regression coverage for attack. The assertions below state the expected behavior of this case.
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

# Regression coverage for connected block art. The assertions below state the expected behavior of this case.
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

# Regression coverage for new enemy sprite animation. The assertions below state the expected behavior of this case.
func check_new_enemy_sprite_animation() -> void:
	var art = load("res://scripts/enemy_art.gd")
	var atlas: Image = art.atlas()
	for family in ["enemy_mosstrot", "enemy_cragjaw", "enemy_murkspore"]:
		var frames := {}
		var row: int = art.KINDS.find(family)
		var bounded := true
		for frame in 4:
			var image := atlas.get_region(Rect2i(frame*art.SIZE,row*art.SIZE,art.SIZE,art.SIZE))
			frames[image.get_data().hex_encode()] = true
			var used := image.get_used_rect()
			bounded = bounded and used.position.x >= 1 and used.position.y >= 1 and used.end.x < art.SIZE and used.end.y < art.SIZE
		check(frames.size() == 4, "%s has four distinct animation poses" % family)
		check(bounded, "%s animation stays inside its cell with a transparent margin" % family)

# Regression coverage for enemy facing alignment. The assertions below state the expected behavior of this case.
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

# Regression coverage for combat enemies. The assertions below state the expected behavior of this case.
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
	# walkers go right up to the edge: the box's side lines up with the end of the floor before turning
	make_world([{"t": "enemy_mosstrot", "x": 164, "y": 152}], [[20, 20], [21, 20]])
	enemy = w.ents.filter(func(e): return e.d.t == "enemy_mosstrot")[0]
	var reached := {}
	for i in 600:
		enemy.update(DT)
		reached[enemy.rect.position.x] = true
	check(reached.has(160) and reached.has(176 - enemy.rect.size.x) and enemy.rect.position.x >= 160 and enemy.rect.end.x <= 176, "Mosstrot walks until its box is flush with each end of its floor (%s)" % [reached.keys()])

# Regression coverage for enemy variants. The assertions below state the expected behavior of this case.
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
	check(recording.destinations.any(func(r): return absf(r.size.y) == art.SIZE * 2), "Giant enemies draw at twice the size")
	probe.free()
	art._texture = previous
	Game.settings.invincible = false

# Cragjaw (leaping brute) and Murkspore (hovering spitter), the two big families.
# Regression coverage for big enemies. The assertions below state the expected behavior of this case.
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

# Regression coverage for bugfixes. The assertions below state the expected behavior of this case.
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
	var bad := Adventure.restore_run(aw, {"room": "a2_little_gap", "spawn": ["bad", {}], "blocks": -20, "energy": 99999.0, "deaths": -3, "time": INF, "stars": [1, "s"]})
	check(bad.spawn == null and bad.blocks == 1 and bad.energy == Adventure.energy_max(bad) and bad.deaths == 0 and bad.time == 0.0 and bad.stars == ["s"], "malformed save values are normalized (%s)" % bad)
	check(Adventure.restore_run(aw, {"room": "a2_little_gap", "spawn": [1.0, NAN]}).spawn == null, "non-finite spawn is dropped")
	var legacy := Adventure.restore_run(aw, {"room": "a2_little_gap", "spawn": [40, 80], "blocks": 2.0, "energy": 30, "deaths": 4})
	check(legacy.spawn == [40, 80] and legacy.blocks == 2 and legacy.energy == 30.0 and legacy.deaths == 4, "valid int/float saves keep their values (%s)" % legacy)
	Game.adv_world = aw
	Game.adv = bad
	Game.level = aw.rooms[bad.room].level
	var bw = load("res://scripts/world.gd").new()
	add_child(bw)
	check(bw.player != null and bw.spawn.is_finite(), "a world builds from a normalized malformed save")
	bw.free()
	Game.adv = {}
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

# Boss 1, the Ape: distance picks the attack; a stone fells the trunk; spikes hurt it; three hits beat it.
# Regression coverage for ape hitbox shapes. The assertions below state the expected behavior of this case.
func check_ape_hitbox_shapes() -> void:
	make_world([{"t":"boss_ape","x":200,"y":192}])
	var ape = w.ents.filter(func(e): return e is E.Ape)[0]
	check(ape.body_boxes() == [ape.touch_rect()] and ape.touch_rect() == Rect2i(ape.rect.position + Vector2i(4, 4), Vector2i(24, 24)), "Ape contact is one centred 24px square (%s)" % [ape.body_boxes()])
	ape.phase = "scream"
	ape.timer = -0.1
	var c: Vector2 = ape.center()
	check(ape.scream_hits(Rect2i(Vector2i(c)+Vector2i(37,-1),Vector2i(2,2))), "round scream reaches the cardinal edge")
	check(not ape.scream_hits(Rect2i(Vector2i(c)+Vector2i(33,33),Vector2i(2,2))), "round scream excludes the old square corners")
	check(ape.damage_circles().size()==1 and ape.damage_boxes().is_empty(), "scream overlay exposes the actual circular damage shape")
	check(ape.scream_hits(Rect2i(Vector2i(c)+Vector2i(39,-1),Vector2i(4,2))), "scream detects an overlapping player edge even when their centre is outside")
	var arena := Game.load_level("a1_ape_arena", "res://worlds/story/")
	check(arena.entities.all(func(e): return e.t != "ape_trunk"), "Ape arena removes the tree obstacle")
	var boss: Dictionary = arena.entities.filter(func(e): return e.t == "boss_ape")[0]
	check(not boss.has("range2") and int(boss.range[0]) == 8 and int(boss.range[1]) == 304 and int(arena.w) == 39, "Ape arena (39 tiles wide) uses one unrestricted fighting range")
	check(arena.tiles[19].substr(20,10)=="1".repeat(10), "former tree bridge pit is safe solid ground")
	# the Ape gets everywhere in the arena: leaps at players all over it never stick or end inside terrain, and land
	# on the floor, both exit ledges and every platform, edge to edge
	var keep_lv = Game.level
	var keep_world = w
	var keep_inv2: bool = Game.settings.invincible
	Game.settings.invincible = true
	var lv2: Dictionary = arena.duplicate(true)
	lv2.entities = lv2.entities.filter(func(e): return e.t != "auto_walk")
	Game.level = lv2
	var aw = load("res://scripts/world.gd").new()
	add_child(aw)
	aw.set_physics_process(false)
	var bape = aw.ents.filter(func(e): return e.d.t == "boss_ape")[0]
	var spots := []
	for x in range(1, int(lv2.w) - 1):
		for y in range(1, 22):
			if lv2.tiles[y][x] == "0" and lv2.tiles[y - 1][x] == "0" and lv2.tiles[y + 1][x] == "1":
				spots.append(Vector2(x * 8 + 4, (y + 1) * 8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bad := 0
	var cols := {}
	var rows := {}
	for it in 600:
		aw.player.pos = spots[rng.randi() % spots.size()]
		bape.phase = "crouch"
		bape.timer = 0.0
		bape.hp = 99
		var air := 0
		bape.update(DT)
		while bape.phase == "air" and air < 240:
			bape.update(DT)
			air += 1
		if bape.phase == "air" or aw.collide_solid(bape.rect, bape) != null:
			bad += 1
		cols[int(bape.center().x / 8)] = true
		rows[bape.rect.end.y / 8] = true
		bape.stones.clear()
	aw.free()
	w = keep_world
	Game.level = keep_lv
	Game.settings.invincible = keep_inv2
	# every surface it fits on (3+ tiles wide under 4 open rows) must get landings; read from the layout, so
	# editing the arena keeps the check honest
	var surfaces := {}
	for y in range(5, 22):
		var run := 0
		for x in range(1, int(lv2.w)):
			var ok: bool = lv2.tiles[y][x] == "1" and range(1, 5).all(func(k): return lv2.tiles[y - k][x] == "0")
			run = run + 1 if ok else 0
			if run >= 3:
				surfaces[y] = true
	var missed: Array = surfaces.keys().filter(func(y): return not rows.has(y))
	# (spots with no room above for its 32px arc, like the right exit ledge under the row-11 block, stay Ape-free)
	check(bad == 0 and missed.is_empty() and cols.size() > 24,
		"the Ape reaches every surface it fits on and is never stuck or inside rock (%d bad, missed rows %s, %d columns)" % [bad, missed, cols.size()])
	# conditional rooms: once the Ape is beaten, entering the arena loads its aftermath variant
	var Adv = load("res://scripts/adventure.gd")
	var sw2: Dictionary = Adv.load_world("res://worlds/story/world.json")
	var base_lv: Dictionary = Adv.room_level(sw2, "a1_ape_arena", [])
	var ape_id: String = sw2.rooms.a1_ape_arena.variants[0].when
	var after: Dictionary = Adv.room_level(sw2, "a1_ape_arena", [ape_id])
	check(base_lv.entities.any(func(e): return e.t == "boss_ape") and not after.entities.any(func(e): return e.t == "boss_ape" or e.t == "boss_gate")
		and after.tiles == base_lv.tiles and after.entities.filter(func(e): return e.t == "spawn").size() == base_lv.entities.filter(func(e): return e.t == "spawn").size()
		and after.entities.any(func(e): return e.t == "energy_orb"),
		"a beaten Ape's arena comes back as its variant: no boss or gates, same terrain and spawns, the orb")

# Regression coverage for ape. The assertions below state the expected behavior of this case.
func check_ape() -> void:
	var floor_y := 28 * 8
	var keep_inv: bool = Game.settings.invincible
	var find := func(cls): return w.ents.filter(func(e): return is_instance_of(e, cls))
	# far: a stone thrown in an arc towards the player
	Game.settings.invincible = true
	make_world([{"t": "boss_ape", "x": 300, "y": floor_y - 32, "range": [0, 480]}])
	var ape = find.call(E.Ape)[0]
	ape.phase = "idle"  # awake, the player far away
	var thrown := false
	for k in 120:
		step()
		if not ape.stones.is_empty():
			thrown = ape.stones[0][1].x < 0 and ape.stones[0][1].y < 0
			break
	check(thrown, "the Ape throws a stone in an arc at a far player")
	check(ape.damage_boxes().size() == 1 and ape.damage_boxes()[0].size == Vector2i(16, 16), "the hitbox overlay sees the flying stone (%s)" % [ape.damage_boxes()])
	# phase 1: a stone that meets the standing trunk fells it into a bridge at its base (and it stays down)
	make_world([{"t": "ape_trunk", "x": 200, "y": floor_y - 112, "w": 16, "h": 112}, {"t": "boss_ape", "x": 380, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	var trunk = find.call(E.ApeTrunk)[0]
	ape.phase = "idle"  # as if the player had walked past the trunk
	for k in 300:
		step()
		if trunk.down():
			break
	check(trunk.down() and trunk.collidable and trunk.rect == Rect2i(200, floor_y, 112, 8) and w.broken.has(trunk.id), "a stone fells the trunk into a bridge as long as it was tall, and it stays down (%s)" % trunk.rect)
	# the arena's entrance: an auto walk carries the player in, and the gate behind them shuts while the Ape lives
	make_world([{"t": "boss_ape", "x": 420, "y": floor_y - 32},
		{"t": "auto_walk", "x": 72, "y": floor_y - 32, "w": 24, "h": 32, "dir": 1, "time": 0.5, "while_boss": true},
		{"t": "boss_gate", "x": 56, "y": floor_y - 32, "w": 8, "h": 32, "closes_behind": true}])
	ape = find.call(E.Ape)[0]
	var gate_in = find.call(E.BossGate)[0]
	var x_in: float = p().pos.x
	var gate_open_first: bool = not gate_in.collidable
	step(40)
	check(p().pos.x - x_in > 20 and gate_in.collidable, "entering the arena walks the player in (%s px) and the gate behind shuts" % (p().pos.x - x_in))
	ape.phase = "gone"
	step(2)
	check(gate_open_first and not gate_in.collidable, "the entrance gate opens again once the Ape is beaten")
	make_world([{"t": "auto_walk", "x": 72, "y": floor_y - 32, "w": 24, "h": 32, "dir": 1, "time": 0.5, "while_boss": true}])
	x_in = p().pos.x
	step(40)
	check(absf(p().pos.x - x_in) < 2, "no Ape, no auto walk")
	# it sleeps until the player comes near
	make_world([{"t": "boss_ape", "x": 400, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	step(10)
	var slept: bool = ape.phase == "sleep"
	p().pos = Vector2(300, floor_y)
	step(5)
	check(slept and ape.phase == "scream", "the Ape wakes when the player comes near, and the fight opens with its scream")
	var sfx = Game.get_sfx()
	var scream: AudioStreamWAV = sfx.streams.get("ape_scream")
	var echoed: AudioStreamWAV = sfx.streams.get("ape_scream_cave")
	check(scream != null and echoed != null and echoed.get_length() > scream.get_length() + 1.0, "the Ape has a scream, and an echoing cave version that rings on longer")
	# a leap that meets the standing trunk fells it; then, outside its new range, it leaps across
	make_world([{"t": "ape_trunk", "x": 200, "y": floor_y - 112, "w": 16, "h": 112},
		{"t": "boss_ape", "x": 120, "y": floor_y - 32, "range": [40, 216], "range2": [330, 460]}])
	ape = find.call(E.Ape)[0]
	trunk = find.call(E.ApeTrunk)[0]
	p().pos = Vector2(236, floor_y)
	ape.phase = "idle"
	for k in 200:
		step()
		if trunk.down():
			break
	check(trunk.down(), "the Ape's leap crashes into the standing trunk and fells it")
	p().pos = Vector2(400, floor_y)
	for k in 240:
		step()
		if ape.phase != "air" and ape.center().x >= 330:
			break
	check(ape.center().x >= 330 and ape.center().x <= 460, "with the trunk down the Ape leaps across into its second range (at %s)" % ape.center().x)
	# mid range: the leap lands past the player, on the far side from the Ape
	make_world([{"t": "boss_ape", "x": 360, "y": floor_y - 32}])  # 56 px apart: leap range (NEAR..FAR)
	ape = find.call(E.Ape)[0]
	p().pos = Vector2(320, floor_y)
	ape.phase = "idle"
	var landed_x := -1.0
	for k in 200:
		step()
		if ape.phase == "air":
			landed_x = 0.0
		elif landed_x == 0.0:
			landed_x = ape.center().x
			break
	check(landed_x > 0 and landed_x < p().center().x - 8, "the Ape's leap lands past the player (at %s, player %s)" % [landed_x, p().center().x])
	# player straight above (far enough to be in throw range): it leaps, never throws
	make_world([{"t": "boss_ape", "x": 360, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	p().pos = Vector2(ape.center().x + 10, floor_y - 140)
	ape.phase = "idle"
	ape.timer = 0.0
	step()
	check(ape.phase == "crouch", "a player above the Ape makes it leap (phase %s)" % ape.phase)
	# spikes: a landing on them is a hit, and the next patch appears; three hits beat it
	make_world([{"t": "spikes_up", "x": 288, "y": floor_y - 8}, {"t": "spikes_up", "x": 296, "y": floor_y - 8}, {"t": "spikes_up", "x": 304, "y": floor_y - 8},
		{"t": "boss_ape", "x": 370, "y": floor_y - 32, "spikes": [[[100, floor_y - 8, 2]]], "orb": [200, floor_y - 16]},
		{"t": "boss_gate", "x": 440, "y": floor_y - 32, "w": 8, "h": 32}])
	ape = find.call(E.Ape)[0]
	var gate = find.call(E.BossGate)[0]
	p().pos = Vector2(320, floor_y)
	ape.phase = "idle"
	var live := func(): return find.call(E.Spikes).filter(func(e): return e.collidable)
	for k in 200:
		step()
		if ape.hp < E.Ape.HP:
			break
	step(2)
	check(ape.hp == E.Ape.HP - 1 and live.call().size() == 2 and live.call().all(func(e): return e.rect.position.x < 120),
		"landing on spikes hurts the Ape; those spikes crumble and the next patch appears on the other side (hp %d, %d live)" % [ape.hp, live.call().size()])
	step(2)
	check(gate.collidable, "boss gates stay shut while the Ape lives")
	ape.hp = 1
	ape.rect.position = Vector2i(live.call()[0].rect.position.x - 8, floor_y - 32)  # onto the new patch
	ape._land()
	step(90)
	check(ape.phase == "gone" and not gate.collidable and w.broken.has(ape.id) and find.call(E.EnergyOrb).size() == 1, "the last hit beats the Ape: gates open, it stays beaten, an energy orb appears")
	# dying before leaving the room: the rebuilt room keeps the spikes as the fight left them, and the orb
	var live_spikes := func(): return find.call(E.Spikes).filter(func(e): return e.collidable).map(func(e): return Vector2i(e.d.x, e.d.y))
	var left_by_fight: Array = live_spikes.call()
	left_by_fight.sort()
	w._build()
	step(3)
	var after_death: Array = live_spikes.call()
	after_death.sort()
	check(after_death == left_by_fight and find.call(E.EnergyOrb).size() == 1, "after the fight, a death in the room keeps its spikes as they were (%s vs %s)" % [after_death, left_by_fight])
	# the landing slams the ground: a shockwave hits beside the body, not just under it
	Game.settings.invincible = false
	make_world([{"t": "boss_ape", "x": 200, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	p().pos = Vector2(200 + 32 + 10, floor_y)  # just right of the body
	ape.phase = "air"
	ape._land()
	step(2)
	var slam_hit: bool = p().dead
	make_world([{"t": "boss_ape", "x": 200, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	p().pos = Vector2(200 + 32 + 30, floor_y)  # out of reach
	ape.phase = "air"
	ape._land()
	step(2)
	check(slam_hit and not p().dead and ape.slam_box() == Rect2i(176, floor_y - 8, 80, 8), "the Ape's landing slam hits beside it along the ground, not beyond its reach")
	check(is_equal_approx(ape.timer + 2 * DT, 0.6 * E.Ape.PAUSE), "the Ape waits 15%% less after a landing (%s)" % ape.timer)
	# enraged (2 hits taken): a scream is followed by 2 hops in place, shockwaves 125% then 150% wide; landings drop 2 logs
	Game.settings.invincible = true
	make_world([{"t": "boss_ape", "x": 200, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	ape.hp = E.Ape.ENRAGED_HP
	p().pos = Vector2(60, floor_y)
	ape.phase = "scream"
	ape.timer = -0.34
	var widths := []
	var xs := []
	var logs_seen := 0
	for k in 240:
		step()
		if is_equal_approx(ape.slam_t, E.Ape.SLAM_TIME):  # landed this tick
			widths.append(ape.slam_box().size.x)
			xs.append(ape.rect.position.x)
		logs_seen = maxi(logs_seen, ape.logs.size())
	check(widths.size() >= 2 and widths[0] == 100 and widths[1] == 120 and xs[0] == 200 and xs[1] == 200, "enraged scream: 2 hops in place, shockwaves 100 then 120 wide (%s at %s)" % [widths, xs])
	check(logs_seen == 0, "the hops in place drop no logs (%d)" % logs_seen)
	ape.phase = "air"
	ape.slam_scale = 1.0
	ape._land()
	check(ape.logs.size() == 2 and is_equal_approx(ape.logs[1][2] - ape.logs[0][2], E.Ape.LOG_GAP), "an enraged leap drops 2 logs, 0.5 s apart (%s)" % [ape.logs])
	var apart := true
	var spread := {}
	for k in 200:
		ape.logs.clear()
		ape._drop_logs()
		apart = apart and absf(ape.logs[0][0].x - ape.logs[1][0].x) >= E.Ape.LOG.x
		spread[int(ape.logs[0][0].x / 64)] = true
	check(apart and spread.size() >= 4, "the 2 logs land at random spots across the arena and never overlap (%d zones)" % spread.size())
	# enraged stones split in two when they reach the ground
	make_world([{"t": "boss_ape", "x": 300, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	ape.hp = E.Ape.ENRAGED_HP
	ape.phase = "gone"
	ape.stones.append([Vector2(120, floor_y - 40), Vector2(0, 100), E.Ape.STONE])
	var halves := 0
	for k in 60:
		step()
		halves = maxi(halves, ape.stones.filter(func(st): return st[2] == E.Ape.STONE / 2).size())
	check(halves == 2, "an enraged stone splits in two on the ground (%d halves)" % halves)
	Game.settings.invincible = false
	# near: the scream reaches around its body
	Game.settings.invincible = keep_inv
	make_world([{"t": "boss_ape", "x": 140, "y": floor_y - 32}])
	ape = find.call(E.Ape)[0]
	p().pos = Vector2(124, floor_y)
	ape.phase = "idle"
	for k in 90:
		step()
		if p().dead:
			break
	check(p().dead and ape.phase == "scream", "close to the Ape, its scream hits (phase %s)" % ape.phase)
	Game.settings.invincible = keep_inv

# Monsters page (main menu) and the map screen's Map / Monsters tabs (L1 / R1).
# Themed backgrounds stay with the camera: the perspective shift is smooth and bounded (no wrap-around jumps).
# Regression coverage for background parallax. The assertions below state the expected behavior of this case.
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

# Regression coverage for bestiary. The assertions below state the expected behavior of this case.
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
# Regression coverage for energy. The assertions below state the expected behavior of this case.
func check_energy() -> void:
	const Adventure := preload("res://scripts/adventure.gd")
	var world := Adventure.load_world(FIXTURE_WORLD + "world.json")
	var run := Adventure.new_run(world)
	check(run.blocks == 1 and run.energy == 20.0 and Adventure.energy_max(run) == 20.0, "a run starts with the base: 20 energy")
	check(Adventure.spend_energy(run, 10) and run.energy == 10.0, "spending takes energy")
	Adventure.regen_energy(run, 1.0)
	check(is_equal_approx(run.energy, 16.0), "energy regenerates 6 per second (%s)" % run.energy)
	Adventure.regen_energy(run, 10.0)
	check(run.energy == 20.0, "regeneration stops at the top of the base")
	run.energy = 0.0
	Adventure.regen_energy(run, 2.0)
	check(is_equal_approx(run.energy, 12.0), "the base always regenerates, even from 0 (%s)" % run.energy)
	Adventure.regen_energy(run, 100.0)
	check(not Adventure.spend_energy(run, 80) and run.energy == 20.0, "can't spend more than you have")
	Adventure.add_energy_block(run)
	check(run.blocks == 2 and run.energy == 30.0 and Adventure.energy_max(run) == 30.0, "a new block adds a full 10")
	Adventure.spend_energy(run, 20)
	Adventure.regen_energy(run, 10.0)
	check(run.energy == 20.0, "a fully spent block doesn't refill")
	Adventure.spend_energy(run, 20)
	Adventure.regen_energy(run, 100.0)
	check(run.energy == 20.0, "the base refills, but not the spent block above it")
	Adventure.refill_energy(run)
	Adventure.spend_energy(run, 5)
	Adventure.regen_energy(run, 100.0)
	check(run.energy == 30.0, "a partly spent block refills to its top")

	# in the world: a block pickup (once per run), hits, the attack gate
	Game.adv_world = world
	Game.adv = Adventure.new_run(world)
	Game.adv_temp = true
	make_world([{"t": "energy_block", "x": 80, "y": 26 * 8}])
	step(3)
	check(Game.adv.blocks == 2 and Game.adv.energy == 30.0 and Game.adv.taken.size() == 1, "energy block pickup adds a full block (10)")
	make_world([{"t": "energy_block", "x": 80, "y": 26 * 8}])
	step(3)
	check(Game.adv.blocks == 2, "an energy block is taken once per run")
	Game.adv.energy = 12.0
	p().die(Vector2.ZERO)
	var after_hit: float = Game.adv.energy
	p().dead = false
	Game.adv.energy = 0.0
	p().die(Vector2.ZERO)
	check(w.deaths == 2 and after_hit == 12.0 and Game.adv.energy == 0.0, "a hit is always a death, and leaves energy as it was")
	w.respawn()  # the respawn refills the base bar; extra blocks above it stay as they were
	var low: float = Game.adv.energy
	Game.adv.energy = 30.0
	p().die(Vector2.ZERO)
	w.respawn()
	check(low == Adventure.BASE_ENERGY and Game.adv.energy >= 30.0 and not p().dead, "respawn comes back with full base energy (%s), never lowers it (%s)" % [low, Game.adv.energy])
	# each jump costs 2.5 energy and needs it: with less there's no jump
	make_world([])
	step(5)
	Game.adv.energy = 50.0
	p().tap = {"jump": true}
	step()
	var after_jump: float = Game.adv.energy
	step(60)
	Game.adv.energy = 2.0
	var y0: float = p().pos.y
	p().tap = {"jump": true}
	step(4)
	check(absf(after_jump - 47.5) < 0.3 and p().on_ground and p().pos.y == y0, "a jump costs 2.5 energy; with less there's no jump (%s)" % after_jump)
	check(w.energy_log.size() > 0 and w.energy_log[-1][1] == "jump" and is_equal_approx(w.energy_log[-1][2], -2.5), "energy changes are logged with their cause (%s)" % [w.energy_log])
	var EP = load("res://scripts/energy_panel.gd")
	var ep = EP.new()
	ep.world = w
	add_child(ep)
	ep._process(0.0)
	check(EP.regen_top(15.0) == 20.0 and EP.regen_top(25.0) == 30.0 and EP.regen_top(30.0) == 30.0 and ep.rate()[0] >= 0.0 and ep.history.size() == 1,
		"F3 energy panel: regen top per block, live rate and history")
	ep.free()
	Game.adv.energy = 100.0

	# HUD energy bars: one per block, filled by its share of the energy
	var fills: Array = load("res://scripts/world.gd").Hud.block_fills(25.0, 3)
	check(fills == [1.0, 0.5, 0.0], "HUD energy bars: the base, then block by block (%s)" % [fills])
	Game.adv.energy = 0.19 * Adventure.energy_max(Game.adv)
	var grey: bool = p().hair_color() == p().HAIR_USED
	Game.adv.energy = 0.21 * Adventure.energy_max(Game.adv)
	check(grey and p().hair_color() != p().HAIR_USED, "hair turns grey below 20% energy")
	Game.adv.energy = 100.0
	# touch controls keep their distance to the nearest screen edges on any screen shape (phones are wider than 16:9)
	var tc = load("res://scripts/touch_controls.gd").new()
	tc.size = Vector2(1560, 720)
	check(tc.at(Vector2(1150, 600)) == Vector2(1430, 600) and tc.at(Vector2(190, 540)) == Vector2(190, 540) and tc.at(Vector2(1220, 50)) == Vector2(1500, 50), "touch controls hug the screen edges on a wide phone")
	tc.size = Vector2(1280, 960)
	check(tc.at(Vector2(1150, 600)) == Vector2(1150, 840) and tc.at(Vector2(190, 540)) == Vector2(190, 780), "touch controls hug the bottom on a tall screen")
	tc.free()
	var Hud = load("res://scripts/world.gd").Hud
	check(Hud.bar_color(0.0).is_equal_approx(Color("ff4a3a")) and Hud.bar_color(0.5).is_equal_approx(Color("ffd84a")) and Hud.bar_color(1.0).is_equal_approx(Color("7cf0c0")), "HUD energy bar colour: red empty, yellow half, mint full (%s %s %s)" % [Hud.bar_color(0.0), Hud.bar_color(0.5), Hud.bar_color(1.0)])

	# water drains 2.08 energy every 0.1 s and stops regeneration; at 0 energy in water the player dies
	make_world([{"t": "water", "x": 0, "y": 20 * 8, "w": 40 * 8, "h": 10 * 8}])
	step(5)
	Game.adv.energy = 150.0
	var before: float = Game.adv.energy
	step(60)
	check(w.in_water() and absf(before - Game.adv.energy - 20.8) < 0.01, "a second in water costs 20.8 energy, no regeneration (%s)" % (before - Game.adv.energy))
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

# Regression coverage for adventure. The assertions below state the expected behavior of this case.
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
	Game.world_path = Game.STORY_WORLD
	check(Game._run_key() == "run_story" and key != "run_story" and not Game.has_adventure_save(), "each world keeps its own save")
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
	Game.world_path = Game.STORY_WORLD
	_remove_dir(dir)

# Start the test/benchmark scene, configure its disposable fixtures and run the checks.
func _ready() -> void:
	Game.settings.air_dashes = 0
	Game.settings.infinite_stamina = false
	Game.settings.invincible = false
	Game.settings.shake = false

	check_environment_themes()
	check_character_animation()
	check_connected_block_art()
	check_new_enemy_sprite_animation()
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
	var graph = load("res://scripts/debug_panel.gd").StateGraph
	var fake := {"in_waterfall": true}
	check(graph.LAYERS.map(func(l): return l[0]) == ["Attack", "Waterfall"] and graph.layer_on(fake, "Waterfall"), "the state machine view lists the attack and waterfall layers and lights the active ones")
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
	check(Tuning.list_presets().has(preset), "saved preset is listed")
	Tuning.delete_preset(preset)
	check(not FileAccess.file_exists(Tuning.preset_path(preset)) and not Tuning.list_presets().has(preset), "preset deletes")
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

	# Normal (Underwater) replaces Normal in water: slow sinking, no walking on the floor, a weaker jump
	make_world([{"t": "water", "x": 0, "y": 8 * 8, "w": 60 * 8, "h": 22 * 8}])
	p().pos = Vector2(88, 14 * 8)
	step(40)
	var sink: float = p().speed.y
	check(p().state == p().ST_SWIM and sink <= p().WATER_MAX_FALL + 0.01, "in water the state is Normal (Underwater), sinking slowly (%s)" % sink)
	p().tap = {"jump": true}
	step()
	check(p().state == p().ST_SWIM and p().speed.y < 0, "Jumping (Underwater) works mid-water (%s)" % p().speed.y)
	step(2)
	p().tap = {"jump": true}
	step()
	check(p().speed.y == p().WATER_STROKE, "underwater, jump works every time it's pressed (%s)" % p().speed.y)
	step(400)  # settle on the floor
	var bed_x: float = p().pos.x
	p().hold = {"right": true}
	step(30)
	check(p().on_ground and p().pos.x - bed_x > 20 and p()._animation() != "run", "along the floor underwater the player moves as mid-water, not walking (moved %s px, pose %s)" % [p().pos.x - bed_x, p()._animation()])
	p().hold = {}
	var bed_y: float = p().pos.y
	var top_swim := bed_y
	p().tap = {"jump": true}
	for k in 40:
		step()
		top_swim = minf(top_swim, p().pos.y)
	make_world([])
	step(10)
	var ground_y: float = p().pos.y
	var top_jump := ground_y
	p().tap = {"jump": true}
	p().hold = {"jump": true}
	for k in 40:
		step()
		top_jump = minf(top_jump, p().pos.y)
	p().hold = {}
	check(p().state == p().ST_NORMAL and bed_y - top_swim > 4 and bed_y - top_swim < ground_y - top_jump, "Jumping (Underwater) rises less than a jump (%s px vs %s px); out of water it's Normal again" % [bed_y - top_swim, ground_y - top_jump])
	# shallow water (2 tiles): with the surface this close, jump leaps out like a normal jump
	make_world([{"t": "water", "x": 0, "y": 26 * 8, "w": 60 * 8, "h": 2 * 8}])
	step(30)
	var in_shallow: bool = p().state == p().ST_SWIM
	p().tap = {"jump": true}
	p().hold = {"jump": true}
	var top_out: float = p().pos.y
	for k in 40:
		step()
		top_out = minf(top_out, p().pos.y)
	p().hold = {}
	check(in_shallow and top_out < 26 * 8 - 8, "near the surface, jump leaps out of the water (feet up to %s, surface %s)" % [top_out, 26 * 8])
	make_world([{"t": "waterfall", "x": 64, "y": 0, "w": 48, "h": 30 * 8}])
	p().pos = Vector2(88, 27 * 8)
	step(5)
	var fall_floor: float = p().pos.y
	p().tap = {"jump": true}
	p().hold = {"jump": true}
	var top_y := fall_floor
	for k in 40:
		step()
		top_y = minf(top_y, p().pos.y)
	p().hold = {}
	var fall_rise: float = fall_floor - top_y
	make_world([])
	step(5)
	var free_floor: float = p().pos.y
	p().tap = {"jump": true}
	p().hold = {"jump": true}
	var free_top := free_floor
	for k in 40:
		step()
		free_top = minf(free_top, p().pos.y)
	p().hold = {}
	check(fall_rise > 8 and fall_rise < (free_floor - free_top) * 0.8, "a waterfall layer pulls down: a jump inside it still rises, but less (%s px vs %s px)" % [fall_rise, free_floor - free_top])

	# down + jump on a jump-through drops through it; jump alone still jumps
	make_world([{"t": "jumpthru", "x": 64, "y": 20 * 8, "w": 48, "h": 8}])
	p().pos = Vector2(88, 20 * 8)
	step(10)
	var on_top: bool = p().on_ground and p().pos.y == 20 * 8
	p().hold = {"down": true}
	p().tap = {"jump": true}
	step(20)
	check(on_top and p().pos.y > 20 * 8 + 8, "down + jump drops through a jump-through (y %s)" % p().pos.y)
	p().pos = Vector2(88, 20 * 8)
	p().hold = {}
	step(10)
	p().tap = {"jump": true}
	step(3)
	check(p().pos.y < 20 * 8, "jump alone on a jump-through still jumps")

	# spikes kill
	make_world([{"t": "spikes_up", "x": 120, "y": 27 * 8}])
	step(5)
	p().hold = {"right": true}
	step(40)
	check(p().dead, "walking into spikes kills")
	var hr: Rect2i = p().hurt_rect()
	var dr: Rect2i = p().damage_rect()
	check(dr.size == Vector2i((Vector2(hr.size) * 0.8).round()) and dr.end.y == hr.end.y and hr.encloses(dr), "hazards hit a box 20%% smaller than the hurtbox (%s in %s)" % [dr, hr])

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
	check_dirs()
	check_adventure()
	check_energy()
	check_bugfixes()
	check_bestiary()
	check_ape_hitbox_shapes()
	check_ape()
	check_background_parallax()

	print("\n%d failure(s)" % fails)
	Game.quit_game(fails)
