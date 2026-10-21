extends Node
# Actual collision/transition methods, with rendering and save writes disabled.
# godot --headless --path . res://tools/room_safety.tscn -- --world res://worlds/hollow_knight/world.json
const Adventure := preload("res://scripts/adventure.gd")
const Player := preload("res://scripts/player.gd")
const Entities := preload("res://scripts/entities.gd")

class DrivenPlayer extends "res://scripts/player.gd":
	var intent := Vector2i.ZERO
	var frame_number := 0
	var press_dash := true
	func _read_input(dt: float) -> void:
		in_x = intent.x
		in_y = intent.y
		aim_raw = Vector2(intent).normalized()
		aim_free = aim_raw
		jump_buf -= dt
		dash_buf -= dt
		attack_buf -= dt
		if frame_number == 0 and press_dash:
			dash_buf = INPUT_BUFFER
		jump_check = false
		grab_check = false
		frame_number += 1

class QuietTiles extends "res://scripts/tile_layer.gd":
	func setup(level_tiles: Array, w: int, h: int) -> void:
		tiles = level_tiles
		level_size = Vector2i(w, h)

class ProbeWorld extends "res://scripts/world.gd":
	var cache := {}
	func _save_run() -> void:
		pass
	func _load_near() -> void:
		pass
	func _scan_floor_gaps() -> void:
		pass
	func show_note(text: String) -> void:
		pass
	func on_player_death(p, dir: Vector2) -> void:
		pass
	func _build(keep_player := false) -> void:
		if not cache.has(room):
			grid = PackedByteArray()
			ents = []; solids = []; jumpthrus = []; dreams = []; spikes = []; touchables = []
			super._build(true)
			cache[room] = [tiles, grid, ents, solids, jumpthrus, dreams, spikes, touchables]
		else:
			var saved: Array = cache[room]
			tiles = saved[0]
			grid = saved[1]
			ents = saved[2]
			solids = saved[3]
			jumpthrus = saved[4]
			dreams = saved[5]
			spikes = saved[6]
			touchables = saved[7]
			gw = int(data.w)
			gh = int(data.h)
			bounds = Rect2i(0, 0, gw * T, gh * T)

var world: ProbeWorld
var manifest := "res://worlds/hollow_knight/world.json"
var output := "res://reports/hk-room-safety.json"
var findings := {}
var counts := {"edge_candidates": 0, "edge_valid_starts": 0, "edge_crossings": 0, "door_valid_starts": 0, "door_crossings": 0, "bounds_valid_starts": 0}
var phase := "all"
var step_sizes := [1, 4, 8]
var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

func _ready() -> void:
	call_deferred("run")

func select_room(room: String) -> void:
	world.room = room
	world.room_origin = Vector2(Game.adv_world.rooms[room].pos * 8)
	world.data = Game.adv_world.rooms[room].level
	world.tiles = []
	world._build(true)
	world.pending_door = null
	world.door_block = Rect2i()
	world.done = false

func reset(room: String, at: Vector2, duck: bool) -> void:
	select_room(room)
	world.player.pos = at
	world.player.dead = false
	world.player.speed = Vector2.ZERO
	world.player.rem = Vector2.ZERO
	world.player.state = Player.ST_NORMAL
	world.player.set_ducking(duck)

func record(kind: String, source: String, at: Vector2, duck: bool, details: Dictionary) -> void:
	var target := world.room
	var key := "%s:%s:%s:%s" % [kind, source, target, details.get("edge", details.get("door", ""))]
	if not findings.has(key):
		findings[key] = {"kind": kind, "source": source, "target": target, "occurrences": 0, "samples": []}
	var group: Dictionary = findings[key]
	group.occurrences += 1
	if group.samples.size() < 5:
		var sample := {"start_local_px": [at.x, at.y], "arrival_local_px": [world.player.pos.x, world.player.pos.y], "crouched": duck}
		sample.merge(details)
		group.samples.append(sample)

func embedded() -> bool:
	return world.collide_solid(world.player.hitbox()) != null

func escape_directions() -> Array:
	var result := []
	for direction in directions:
		if world.collide_solid(world.player.rect_at(world.player.pos + Vector2(direction))) == null:
			result.append([direction.x, direction.y])
	return result

func outside_world() -> bool:
	var global: Vector2 = world.room_origin + world.player.center()
	return Adventure.room_at(Game.adv_world, global) == ""

func inspect_arrival(source: String, at: Vector2, duck: bool, details: Dictionary) -> void:
	if embedded():
		var extra := details.duplicate()
		extra["free_one_pixel_directions"] = escape_directions()
		record("embedded_arrival", source, at, duck, extra)
	if outside_world():
		record("arrival_outside_all_rooms", source, at, duck, details)

func edge_probe(source: String, at: Vector2, duck: bool, direction: Vector2i, step_size: int = 1) -> void:
	counts.edge_candidates += 1
	reset(source, at, duck)
	if embedded() or not Rect2(world.bounds).encloses(Rect2(world.player.hitbox())):
		return
	counts.edge_valid_starts += 1
	world.player.speed = Vector2(direction) * 240.0
	# Exact 1px movement isolates the earliest crossing, including a one-off bad alignment.
	for tick in ceili(16.0 / step_size):
		var before: Vector2 = world.player.pos
		if direction.x:
			world.player.move_h_exact(direction.x * step_size)
		else:
			world.player.move_v_exact(direction.y * step_size)
		world.player._enforce_bounds()
		if world.player.dead:
			return
		world.after_player_move()
		if world.room != source:
			counts.edge_crossings += 1
			inspect_arrival(source, at, duck, {"edge": [direction.x, direction.y], "tick": tick + 1, "step_px": step_size})
			return
		if world.player.pos == before:
			return

func check_edges() -> void:
	var rooms: Dictionary = Game.adv_world.rooms
	for source in rooms:
		var r := Adventure.room_rect(rooms[source])
		for target in rooms:
			if source == target:
				continue
			var s := Adventure.room_rect(rooms[target])
			var vertical := r.end.x == s.position.x or r.position.x == s.end.x
			var horizontal := r.end.y == s.position.y or r.position.y == s.end.y
			if vertical:
				var lo := maxi(r.position.y, s.position.y)
				var hi := mini(r.end.y, s.end.y)
				var dir := Vector2i.RIGHT if r.end.x == s.position.x else Vector2i.LEFT
				for duck in [false, true]:
					for y in range(lo, hi):
						for step_size in step_sizes:
							edge_probe(source, Vector2(r.size.x - 4 if dir.x > 0 else 4, y - r.position.y), duck, dir, step_size)
			if horizontal:
				var lo := maxi(r.position.x, s.position.x)
				var hi := mini(r.end.x, s.end.x)
				var dir := Vector2i.DOWN if r.end.y == s.position.y else Vector2i.UP
				for duck in [false, true]:
					for x in range(lo, hi):
						for step_size in step_sizes:
							edge_probe(source, Vector2(x - r.position.x, r.size.y if dir.y > 0 else 6 if duck else 11), duck, dir, step_size)
		print("Edges: ", source)

func check_doors() -> void:
	for source in Game.adv_world.rooms:
		var level: Dictionary = Game.adv_world.rooms[source].level
		for door in level.entities:
			if door.t != "door":
				continue
			var rect := Rect2i(int(door.x), int(door.y), int(door.get("w", 8)), int(door.get("h", 8)))
			for duck in [false, true]:
				# All integer offsets where the hurtbox can touch the trigger, not just its centre.
				for y in range(rect.position.y + 1, rect.end.y + (6 if duck else 11)):
					for x in range(rect.position.x - 3, rect.end.x + 4):
						var at := Vector2(x, y)
						reset(source, at, duck)
						if embedded() or not world.player.hurt_rect().intersects(rect):
							continue
						if not Rect2(world.bounds).encloses(Rect2(world.player.hitbox())):
							continue
						counts.door_valid_starts += 1
						world.player.speed = Vector2(240, 160)
						var entity = Entities.make(world, door)
						world.door_hit(entity)
						world.after_player_move()
						counts.door_crossings += 1
						inspect_arrival(source, at, duck, {"door": door.get("id", ""), "to": door.get("to", "")})

func bounds_probe(source: String, at: Vector2, duck: bool, direction: Vector2i) -> void:
	reset(source, at, duck)
	if embedded() or not Rect2(world.bounds).encloses(Rect2(world.player.hitbox())):
		return
	counts.bounds_valid_starts += 1
	world.player.speed = Vector2(direction) * 240
	for tick in 48:
		var before: Vector2 = world.player.pos
		if direction.x:
			world.player.move_h_exact(direction.x)
		else:
			world.player.move_v_exact(direction.y)
		world.player._enforce_bounds()
		if world.player.dead:
			return
		world.after_player_move()
		if world.room != source:
			return
		var hitbox: Rect2i = world.player.hitbox()
		# The 24px top allowance and brief bottom fall before death are intentional.
		if hitbox.position.y < -24 or hitbox.position.x < 0 or hitbox.end.x > world.bounds.end.x:
			if outside_world():
				record("uncontained_bounds", source, at, duck, {"edge": [direction.x, direction.y], "pixel_steps": tick + 1})
				return
		if world.player.pos == before:
			return
		if hitbox.position.y > world.bounds.end.y and outside_world():
			record("survived_bottom_void", source, at, duck, {"pixel_steps": tick + 1})
			return

func check_bounds() -> void:
	for source in Game.adv_world.rooms:
		var level: Dictionary = Game.adv_world.rooms[source].level
		for duck in [false, true]:
			for y in range(6 if duck else 11, int(level.h) * 8 + 1):
				bounds_probe(source, Vector2(4, y), duck, Vector2i.LEFT)
				bounds_probe(source, Vector2(int(level.w) * 8 - 4, y), duck, Vector2i.RIGHT)
			for x in range(4, int(level.w) * 8 - 3):
				bounds_probe(source, Vector2(x, 6 if duck else 11), duck, Vector2i.UP)
				bounds_probe(source, Vector2(x, int(level.h) * 8), duck, Vector2i.DOWN)

func replay_cases() -> Array:
	var cases := [
		{"room": "r005", "at": [1204, 852], "dir": [1, 0], "duck": false, "label": "King's Pass right edge"},
		{"room": "r023", "at": [1557, 811], "dir": [1, 0], "duck": false, "label": "Door d8 to r039:d9", "door": "d8"},
		{"room": "r028", "at": [140, 11], "dir": [0, -1], "duck": false, "label": "r028 ceiling"},
		{"room": "r124", "at": [28, 11], "dir": [0, -1], "duck": false, "label": "r124 ceiling"},
		{"room": "r125", "at": [164, 11], "dir": [0, -1], "duck": false, "label": "r125 ceiling"},
	]
	var results := []
	for item in cases:
		if not Game.adv_world.rooms.has(item.room):
			continue
		var bot := DrivenPlayer.new(world, Vector2.ZERO)
		world.player = bot
		reset(item.room, Vector2(item.at[0], item.at[1]), item.duck)
		bot.intent = Vector2i(item.dir[0], item.dir[1])
		bot.press_dash = not item.has("door")
		world.freeze = 0
		world.parts.clear()
		world.trails.clear()
		var trace := []
		var first_overlap := -1
		var first_void := -1
		for tick in 90:
			if world.freeze > 0:
				world.freeze -= 1.0 / 60.0
			else:
				bot.update(1.0 / 60.0)
				world.after_player_move()
			var overlap := embedded()
			var hb: Rect2i = bot.hitbox()
			var escaped :=  outside_world() and (hb.position.y < -24 or hb.position.x < 0 or hb.end.x > world.bounds.end.x or hb.position.y > world.bounds.end.y)
			if overlap and first_overlap < 0:
				first_overlap = tick
			if escaped and first_void < 0:
				first_void = tick
			trace.append({"tick": tick, "room": world.room, "position": [bot.pos.x, bot.pos.y], "state": bot.state, "speed": [bot.speed.x, bot.speed.y], "embedded": overlap, "outside_allowance": escaped, "dead": bot.dead})
			if bot.dead:
				break
		results.append({"case": item, "first_embedded_tick": first_overlap, "first_outside_tick": first_void, "trace": trace})
		print("REPLAY ", item.label, " embedded tick=", first_overlap, " outside tick=", first_void, " final=", bot.pos, " dead=", bot.dead)
	world.player = null
	return results

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--world" and i + 1 < args.size():
			manifest = args[i + 1]
		if args[i] == "--phase" and i + 1 < args.size():
			phase = args[i + 1]
		if args[i] == "--output" and i + 1 < args.size():
			output = args[i + 1]
	if phase not in ["all", "edges", "doors", "bounds", "replay"]:
		push_error("Unknown phase: " + phase)
		get_tree().quit(2)
		return
	Game.adv_world = Adventure.load_world(manifest)
	if Game.adv_world.rooms.is_empty():
		push_error("No rooms loaded: " + manifest)
		get_tree().quit(2)
		return
	Game.adv = Adventure.new_run(Game.adv_world)
	Game.adv_temp = true
	Game.settings.invincible = false
	world = ProbeWorld.new()
	world.tile_layer = QuietTiles.new()
	world.player = Player.new(world, Vector2.ZERO)
	if phase in ["all", "edges"]:
		check_edges()
	if phase in ["all", "doors"]:
		print("Checking doors...")
		check_doors()
	if phase in ["all", "bounds"]:
		print("Checking exterior bounds...")
		check_bounds()
	var replays := replay_cases() if phase == "replay" else []
	var report := {
		"world": manifest, "phase": phase, "replays": replays, "room_count": Game.adv_world.rooms.size(), "counts": counts,
		"finding_groups": findings.values(),
		"coverage": "Every integer seam alignment in both directions, standing/crouched; every valid integer door contact; every open outer-boundary alignment. Uses actual move_exact, bounds, room-exit, door, and enter_room methods. Rendering/saves disabled; room collision data cached.",
		"step_sizes_px": step_sizes,
		"limits": "Local probes are seeded at collision-free edges, not reached from spawn. Cardinal steps; no diagonal/subpixel state-machine playthrough, corner-correction callbacks, hazard survival, or moving entities. Top 24px allowance and bottom death margin are intentional. Findings are reproducible local transition failures, not proof every seed is reachable in a run. No guarantee against all untested inputs/states.",
	}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: " + output)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COUNTS ", counts)
	print("FINDING GROUPS ", findings.size(), " report: ", output)
	world.player = null
	world.tile_layer.free()
	world.free()
	Game.adv = {}
	var replay_failed := replays.any(func(result): return result.first_embedded_tick >= 0 or result.first_outside_tick >= 0)
	get_tree().quit(1 if not findings.is_empty() or replay_failed else 0)
