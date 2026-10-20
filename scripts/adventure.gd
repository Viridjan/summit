extends RefCounted
# Adventure world: ordinary level files (rooms) placed on one big tile grid, Metroid style.
# Walking off a room's edge enters whichever room covers that spot; there are no door objects.
# world.json: {"start": "room_name", "rooms": {"room_name": [tile_x, tile_y], ...}}
# Room files live next to it: <dir>/<room_name>.json. Notes and future ideas: docs/METROID_NOTES.md.

const T := 8
# Moves the player starts the adventure without; ability pickups ("ability_<name>") unlock them.
const ABILITIES := ["dash", "climb"]

# -> {"start": String, "rooms": {name: {"pos": Vector2i (tiles), "level": Dictionary}}}
# Rooms whose file is missing or invalid are skipped.
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
	var ab = json.data.get("abilities", [])
	if ab is Array:
		out.abilities = ab.filter(func(a): return a in ABILITIES)
	var start = json.data.get("start", "")
	out.start = start if out.rooms.has(start) else (out.rooms.keys()[0] if not out.rooms.is_empty() else "")
	return out

# Writes world.json only; room files are saved separately (Game.save_level).
static func save_world(path: String, world: Dictionary) -> bool:
	var rooms := {}
	for name in world.rooms:
		var p: Vector2i = world.rooms[name].pos
		rooms[name] = [p.x, p.y]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"start": world.start, "abilities": world.get("abilities", []), "rooms": rooms}, "\t"))
	return true

# Room area in world pixels.
static func room_rect(room: Dictionary) -> Rect2i:
	return Rect2i(room.pos * T, Vector2i(room.level.w, room.level.h) * T)

# Name of the room covering world-pixel point p ("" if none). Overlaps: first match wins.
# Room boxes may overlap (irregular rooms): prefer the one that is open at that spot.
static func room_at(world: Dictionary, p: Vector2, exclude := "") -> String:
	var fallback := ""
	for name in world.rooms:
		if name != exclude and Rect2(room_rect(world.rooms[name])).has_point(p):
			if _open(world.rooms[name], int(floor(p.x / T)), int(floor(p.y / T))):
				return name
			if fallback == "":
				fallback = name
	return fallback

static func _open(room: Dictionary, tx: int, ty: int) -> bool:
	var lvl: Dictionary = room.level
	tx -= room.pos.x
	ty -= room.pos.y
	return tx >= 0 and ty >= 0 and tx < lvl.w and ty < lvl.h and lvl.tiles[ty].unicode_at(tx) != 49

# Openings between touching rooms, for the world editor: [[a, b], ...] world-pixel segments.
# A tile on the shared border counts when it is empty on both sides.
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

static func _open_overlap(a: Dictionary, b: Dictionary, r: Rect2i) -> bool:
	for ty in range(r.position.y, r.end.y):
		var ra: String = a.level.tiles[ty - a.pos.y]
		var rb: String = b.level.tiles[ty - b.pos.y]
		for tx in range(r.position.x, r.end.x):
			if ra.unicode_at(tx - a.pos.x) != 49 and rb.unicode_at(tx - b.pos.x) != 49:
				return true
	return false

# A fresh run (what the save file stores under [adventure]).
static func new_run(world: Dictionary) -> Dictionary:
	return {"room": world.start, "spawn": null, "abilities": world.get("abilities", []).duplicate(), "visited": [world.start],
		"stars": [], "deaths": 0, "time": 0.0, "done": false}

# Total stars in the world, for the HUD.
static func star_count(world: Dictionary) -> int:
	var n := 0
	for name in world.rooms:
		for e in world.rooms[name].level.entities:
			if e.t == "strawberry":
				n += 1
	return n
