extends RefCounted
# Data and rules shared by adventure rooms, the map and the world editor.
# Static functions are called on this script directly; no scene node needs to be created.
# world describes the layout and room files; run describes one player's saved progress.
# Layout positions use tiles (8px each); room_rect converts them into world pixels.
# Stamina is a number, distinct from blocks: blocks determine capacity, while actions spend stamina.
# Reading help: docs/CODE_GUIDE.md.

# Adventure world: ordinary level files (rooms) placed on one big tile grid, Metroid style.
# Walking off a room's edge enters whichever room covers that spot; there are no door objects.
# world.json: {"start": "room_name", "rooms": {"room_name": [tile_x, tile_y], ...}}
# Room files live next to it: <dir>/<room_name>.json. Notes and future ideas: docs/METROID_NOTES.md.

const T := 8
# Moves the player starts the adventure without; ability pickups ("ability_<name>") unlock them.
const ABILITIES := ["dash", "climb", "attack"]

# Stamina is the player's health and ability fuel (docs/STORY_DESIGN.md section 3).
# A run starts with a base of 40 that always regenerates; each stamina block picked up adds 20.
# run.blocks counts the base as the first block (so 1 = just the base).
const BASE_STAMINA := 40.0  # all stamina values doubled 2026-10-25: whole numbers (a jump costs 5)
const STAMINA_PER_BLOCK := 20.0  # what an stamina block pickup adds
const STAMINA_REGEN_MAX := 12.0  # per second at the best fill (see regen_factor), only inside a partly spent block
const WATER_DRAIN := 40.0  # per second while in water (4 every 0.1 s); no regeneration there

# -> {"start": String, "rooms": {name: {"pos": Vector2i (tiles), "level": Dictionary}}}
# Rooms whose file is missing or invalid are skipped.
# Read a world manifest and validated room files, skipping unusable entries before selecting a valid start room.
static func load_world(path: String) -> Dictionary:
	var out := {"start": "", "rooms": {}, "abilities": []}  # abilities: what a new run starts with
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not json.data is Dictionary or not json.data.get("rooms") is Dictionary:
		return out
	var dir := path.get_base_dir() + "/"
	for name in json.data.rooms:
		var p = json.data.rooms[name]
		if not (name is String and p is Array and p.size() == 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int)):
			continue
		var lvl := Game.load_level(name, dir)
		if not lvl.is_empty():
			out.rooms[name] = {"pos": Vector2i(int(p[0]), int(p[1])), "level": lvl}
	# Conditional rooms: "variants": {room: [{"when": run flag, "room": other file}]}. Once the run has the flag
	# (World.broken: a beaten boss, a broken wall...), entering the room loads the variant instead (room_level).
	var vs = json.data.get("variants", {})
	if vs is Dictionary:
		for name in vs:
			if not (out.rooms.has(name) and vs[name] is Array):
				continue
			for v in vs[name]:
				var lvl := Game.load_level(str(v.get("room", "")), dir) if v is Dictionary else {}
				var base: Dictionary = out.rooms[name].level
				if lvl.is_empty() or lvl.w != base.w or lvl.h != base.h:
					push_warning("variant %s of %s skipped: missing or a different size" % [v, name])
					continue
				out.rooms[name].get_or_add("variants", []).append({"when": str(v.get("when", "")), "room": str(v.room), "level": lvl})
	var ab = json.data.get("abilities", [])
	if ab is Array:
		out.abilities = ab.filter(func(a): return a in ABILITIES)
	var start = json.data.get("start", "")
	out.start = start if out.rooms.has(start) else (out.rooms.keys()[0] if not out.rooms.is_empty() else "")
	return out

# The level to build for a room: its first variant whose flag the run has, else its own.
# A variant brings its own objects; terrain and spawn markers stay the base room's, so tools that fix the base
# (edge sealing, entrance spawns) cover it too.
static func room_level(world: Dictionary, name: String, flags) -> Dictionary:
	var r: Dictionary = world.rooms[name]
	for v in r.get("variants", []):
		if flags.has(v.when):
			var lvl: Dictionary = v.level.duplicate()
			lvl.tiles = r.level.tiles
			lvl.entities = r.level.entities.filter(func(e): return e.t == "spawn") + v.level.entities.filter(func(e): return e.t != "spawn")
			return lvl
	return r.level

# Writes world.json only; room files are saved separately (Game.save_level).
# Write the room layout and starting abilities; individual room contents are saved separately.
static func save_world(path: String, world: Dictionary) -> bool:
	var rooms := {}
	for name in world.rooms:
		var p: Vector2i = world.rooms[name].pos
		rooms[name] = [p.x, p.y]
	var variants := {}
	for name in world.rooms:
		if world.rooms[name].has("variants"):
			variants[name] = world.rooms[name].variants.map(func(v): return {"when": v.when, "room": v.room})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var out := {"start": world.start, "abilities": world.get("abilities", []), "rooms": rooms}
	if not variants.is_empty():
		out.variants = variants
	f.store_string(JSON.stringify(out, "\t"))
	return true

# Room area in world pixels.
# Convert one room tile offset and dimensions to its rectangle in global world pixels.
static func room_rect(room: Dictionary) -> Rect2i:
	return Rect2i(room.pos * T, Vector2i(room.level.w, room.level.h) * T)

# Name of the room covering world-pixel point p ("" if none). Overlaps: first match wins.
# Room boxes may overlap (irregular rooms): prefer the one that is open at that spot.
# Find the room covering a world point, preferring open space when irregular room bounds overlap.
static func room_at(world: Dictionary, p: Vector2, exclude := "") -> String:
	var fallback := ""
	for name in world.rooms:
		if name != exclude and Rect2(room_rect(world.rooms[name])).has_point(p):
			if _open(world.rooms[name], int(floor(p.x / T)), int(floor(p.y / T))):
				return name
			if fallback == "":
				fallback = name
	return fallback

# Convert global tile coordinates to a room-local tile and report whether it is empty.
static func _open(room: Dictionary, tx: int, ty: int) -> bool:
	var lvl: Dictionary = room.level
	tx -= room.pos.x
	ty -= room.pos.y
	return tx >= 0 and ty >= 0 and tx < lvl.w and ty < lvl.h and lvl.tiles[ty].unicode_at(tx) != 49

# Openings between touching rooms, for the world editor: [[a, b], ...] world-pixel segments.
# A tile on the shared border counts when it is empty on both sides.
# Find matching empty border tiles between adjacent rooms, for displaying traversable passages.
static func doorways(world: Dictionary) -> Array:
	var out := []
	var names: Array = world.rooms.keys()
	for i in names.size():
		for j in names.size():
			if i == j:
				continue
			var a: Dictionary = world.rooms[names[i]]
			var b: Dictionary = world.rooms[names[j]]
			var ra := Rect2i(a.pos, Vector2i(a.level.w, a.level.h))
			var rb := Rect2i(b.pos, Vector2i(b.level.w, b.level.h))
			if ra.end.x == rb.position.x:  # b to the right of a
				for ty in range(maxi(ra.position.y, rb.position.y), mini(ra.end.y, rb.end.y)):
					if _open(a, ra.end.x - 1, ty) and _open(b, rb.position.x, ty):
						out.append([Vector2(ra.end.x, ty) * T, Vector2(ra.end.x, ty + 1) * T])
			if ra.end.y == rb.position.y:  # b below a
				for tx in range(maxi(ra.position.x, rb.position.x), mini(ra.end.x, rb.end.x)):
					if _open(a, tx, ra.end.y - 1) and _open(b, tx, rb.position.y):
						out.append([Vector2(tx, ra.end.y) * T, Vector2(tx + 1, ra.end.y) * T])
	return out

# Pairs of room names whose areas overlap (a layout error the world editor shows in red).
# Only open space counts: boxes of irregular rooms may overlap where one of them is rock.
# Find pairs of rooms with genuinely overlapping open space, not merely overlapping outer bounds.
static func overlaps(world: Dictionary) -> Array:
	var out := []
	var names: Array = world.rooms.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Dictionary = world.rooms[names[i]]
			var b: Dictionary = world.rooms[names[j]]
			var r := Rect2i(a.pos, Vector2i(a.level.w, a.level.h)).intersection(Rect2i(b.pos, Vector2i(b.level.w, b.level.h)))
			if r.has_area() and _open_overlap(a, b, r):
				out.append([names[i], names[j]])
	return out

# Inspect the intersection of two rooms to see whether any tile is open in both.
static func _open_overlap(a: Dictionary, b: Dictionary, r: Rect2i) -> bool:
	for ty in range(r.position.y, r.end.y):
		var ra: String = a.level.tiles[ty - a.pos.y]
		var rb: String = b.level.tiles[ty - b.pos.y]
		for tx in range(r.position.x, r.end.x):
			if ra.unicode_at(tx - a.pos.x) != 49 and rb.unicode_at(tx - b.pos.x) != 49:
				return true
	return false

# A fresh run (what the save file stores under [adventure]).
# Create the initial progress record with start room, starting abilities and base stamina.
static func new_run(world: Dictionary) -> Dictionary:
	return {"room": world.start, "spawn": null, "abilities": world.get("abilities", []).duplicate(), "visited": [world.start],
		"stars": [], "deaths": 0, "time": 0.0, "done": false,
		"blocks": 1, "stamina": BASE_STAMINA, "taken": []}  # taken: one-time pickups, "room:x:y"

# Calculate stamina capacity from the base allowance plus collected extra blocks.
static func stamina_max(run: Dictionary) -> float:
	return BASE_STAMINA + (run.blocks - 1) * STAMINA_PER_BLOCK

# The base always regenerates, even from 0. Above it, regeneration stops at the top of the current
# block: an extra block spent to its bottom stays empty.
# Regenerate within the permitted current stamina block without refilling already spent upper blocks.
static func regen_stamina(run: Dictionary, dt: float) -> void:
	var top := BASE_STAMINA
	if run.stamina > BASE_STAMINA:
		top = BASE_STAMINA + ceilf((run.stamina - BASE_STAMINA) / STAMINA_PER_BLOCK) * STAMINA_PER_BLOCK
	var rate := STAMINA_REGEN_MAX * regen_factor(run.stamina / stamina_max(run))
	run.stamina = minf(maxf(top, run.stamina), run.stamina + rate * dt)

# Regeneration speed as a share of STAMINA_REGEN_MAX, by how full the bar is (0..1): 0.5 when empty, rising
# linearly to 1 at half full, then down linearly to 0.75 when full.
static func regen_factor(fill: float) -> float:
	fill = clampf(fill, 0.0, 1.0)
	return 0.5 + fill if fill <= 0.5 else 1.0 - 0.5 * (fill - 0.5)

# Being in water drains stamina. Returns false when it's all gone: the player drowns.
# Drain stamina for the elapsed underwater time and report whether any stamina remains.
static func water_stamina(run: Dictionary, dt: float) -> bool:
	run.stamina = maxf(0.0, run.stamina - WATER_DRAIN * dt)
	return run.stamina > 0

# Wears stamina down by up to amount, never below 0 and never refusing (a jump always happens).
# Subtract an action cost without going below zero; this function itself never refuses the action.
static func drain_stamina(run: Dictionary, amount: float) -> void:
	run.stamina = maxf(0.0, run.stamina - amount)

# Pays for an action; false (nothing spent) when there isn't enough.
# Pay only when enough stamina is available; return whether payment succeeded.
static func spend_stamina(run: Dictionary, amount: float) -> bool:
	if run.stamina < amount:
		return false
	run.stamina -= amount
	return true

# Set current stamina to the full capacity of the collected blocks.
static func refill_stamina(run: Dictionary) -> void:
	run.stamina = stamina_max(run)

# A new block, already full.
# Increase capacity by one block and add the new block stamina immediately.
static func add_stamina_block(run: Dictionary) -> void:
	run.blocks += 1
	run.stamina += STAMINA_PER_BLOCK

# A saved run with missing or wrong-typed fields filled from a fresh one (older or hand-edited saves).
# Unusable saves (not a run, or its room is gone) start over.
# Normalize saved data against current world/rule limits before gameplay reads its fields.
static func restore_run(world: Dictionary, run) -> Dictionary:
	var fresh := new_run(world)
	if not run is Dictionary or not world.rooms.has(run.get("room")):
		return fresh
	if run.has("energy") and not run.has("stamina"):  # saves from before energy was renamed stamina
		run.stamina = run.energy
		run.erase("energy")
	for k in fresh:
		if run.has(k) and fresh[k] != null and typeof(run[k]) != typeof(fresh[k]) and not (_finite(run[k]) and _finite(fresh[k])):
			run.erase(k)  # int and float are interchangeable (JSON and older saves mix them)
	run.merge(fresh)
	if not (run.spawn is Array and run.spawn.size() == 2 and _finite(run.spawn[0]) and _finite(run.spawn[1])):
		run.spawn = null
	run.blocks = maxi(1, int(run.blocks)) if _finite(run.blocks) else 1
	run.deaths = maxi(0, int(run.deaths)) if _finite(run.deaths) else 0
	run.time = maxf(0.0, run.time) if _finite(run.time) else 0.0
	run.stamina = clampf(run.stamina, 0.0, stamina_max(run)) if _finite(run.stamina) else stamina_max(run)
	for k in ["abilities", "visited", "stars", "taken"]:
		run[k] = run[k].filter(func(x): return x is String)
	if not run.visited.has(run.room):
		run.visited.append(run.room)  # the map always shows the current room
	return run

# Accept finite numeric values while rejecting invalid types and non-finite values such as NaN.
static func _finite(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))

# Total stars in the world, for the HUD.
# Count all star objects in the world for the adventure completion display.
static func star_count(world: Dictionary) -> int:
	var n := 0
	for name in world.rooms:
		for e in world.rooms[name].level.entities:
			if e.t == "strawberry":
				n += 1
	return n
