extends Node2D
# Gameplay screen: runs one level (Game.level), owns collision queries for the player.

const E := preload("res://scripts/entities.gd")
const Art := preload("res://scripts/art.gd")
const TileLayer := preload("res://scripts/tile_layer.gd")
const PlayerScript := preload("res://scripts/player.gd")
const OptionsPanel := preload("res://scripts/options.gd")
const DebugPanel := preload("res://scripts/debug_panel.gd")
const MapView := preload("res://scripts/map_view.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const Adventure := preload("res://scripts/adventure.gd")
const T := 8
const DT := 1.0 / 60.0
const ZOOM := 4.8  # screen pixels per game pixel (4 = the original 320x180 view; 4.8 = 120%)
const VIEW := Vector2(1280, 720) / ZOOM

# Background is behind retained terrain; parent draws entities and overlays.
class Background extends Node2D:
	var screen: Node2D
	func _draw() -> void:
		screen._draw_background(self)

# Hitbox overlay (F2) colours, also listed in its legend: [label, colour].
const HITBOX_KEY := [
	["Solid, platform", Color(1, 0.9, 0.2, 0.9)],
	["Touch: pickups, hazards, triggers", Color(1, 0.5, 0.1, 0.9)],
	["Damage: projectiles, scream, slam", Color(1, 0.15, 0.2, 0.9)],
	["Player: collision", Color(0.2, 1, 0.3, 0.9)],
	["Player: damage box", Color(1, 0.3, 0.8, 0.9)],
	["Attack swing", Color(0.55, 0.8, 1, 0.9)],
]

# On-screen HUD: energy (top left), area name (top centre), timer and deaths (top right).
class Hud extends Control:
	const M := 16.0  # margin from the screen edges
	const BOLT := [Vector2(10, 0), Vector2(1, 16), Vector2(8, 16), Vector2(4, 28), Vector2(18, 10), Vector2(11, 10), Vector2(16, 0)]
	const SKULL := ["  ####  ", " ###### ", "##.##.##", "########", " ##..## ", "  # # # "]  # 8x6, "." = eye/nose holes
	var world

	# Fill of each bar, 0..1: the base first, then one per extra block.
	static func block_fills(energy: float, blocks: int) -> Array:
		var out := [clampf(energy / Adventure.BASE_ENERGY, 0.0, 1.0)]
		for i in blocks - 1:
			out.append(clampf((energy - Adventure.BASE_ENERGY - i * Adventure.ENERGY_PER_BLOCK) / Adventure.ENERGY_PER_BLOCK, 0.0, 1.0))
		return out

	func _text(font: Font, at: Vector2, s: String, fs: int, col := Color.WHITE) -> void:
		draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
		draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var w = world
		var sz := get_viewport_rect().size
		var y := M
		# top left: energy (adventure) as a bolt and one bar per block, then the stars
		if w.adventure():
			var bolt := PackedVector2Array(BOLT.map(func(p): return p + Vector2(M, y)))
			draw_colored_polygon(bolt, Color("ffd84a"))
			draw_polyline(bolt + PackedVector2Array([bolt[0]]), Color.BLACK, 2.0)
			var low: bool = Game.adv.energy < 30.0
			var x := M + 26.0
			var fills := block_fills(Game.adv.energy, int(Game.adv.blocks))
			for i in fills.size():
				var f: float = fills[i]
				var cap: float = Adventure.BASE_ENERGY if i == 0 else Adventure.ENERGY_PER_BLOCK
				var r := Rect2(x, y + 7, roundf(cap * 0.46), 14)  # bar width follows what it holds
				draw_rect(r.grow(2), Color.BLACK)
				draw_rect(r, Color(0.12, 0.15, 0.2))
				draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color("ff9a4a") if low else Color("7cf0c0"))
				x += r.size.x + 8.0
			y += 34.0
		if w.total_berries > 0:
			_text(font, Vector2(M, y + 18), "★ %d/%d" % [w.collected.size(), w.total_berries], 18, Color("ffd34e"))
		# top centre: the area's name
		var area: String = w.data.get("name", "")
		var aw := font.get_string_size(area, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(font, Vector2((sz.x - aw) / 2.0, M + 24), area, 26)
		# top right: timer, deaths under it
		var t: String = Game.fmt_time(w.time)
		_text(font, Vector2(sz.x - M - font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x, M + 24), t, 26)
		var d := str(w.deaths)
		var dx: float = sz.x - M - font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_text(font, Vector2(dx, M + 54), d, 22)
		for row in SKULL.size():  # skull icon left of the number, 3 px per pixel
			for col in 8:
				var c: String = SKULL[row][col]
				if c != " ":
					draw_rect(Rect2(dx - 32 + col * 3, M + 36 + row * 3, 3, 3), Color.BLACK if c == "." else Color("e8e4dc"))
		# bottom right: the hitbox overlay's legend, while it's on
		if Game.settings.hitboxes:
			var key: Array = w.HITBOX_KEY
			var fs := 14
			var widest := 0.0
			for k in key:
				widest = maxf(widest, font.get_string_size(k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			var box := Rect2(sz.x - M - widest - 40, sz.y - M - key.size() * 20 - 12, widest + 40, key.size() * 20 + 12)
			draw_rect(box, Color(0, 0, 0, 0.6))
			for i in key.size():
				var ky := box.position.y + 8 + i * 20
				draw_rect(Rect2(box.position.x + 10, ky + 3, 14, 10), key[i][1], false, 1.0)
				draw_string(font, Vector2(box.position.x + 32, ky + 13), key[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

var tile_layer: TileLayer
var background: Background

var data: Dictionary
var level_id := ""
var gw := 0
var gh := 0
var tiles: Array = []
var grid := PackedByteArray()
var bounds: Rect2i
var ents: Array = []
var solids: Array = []
var jumpthrus: Array = []
var dreams: Array = []
var spikes: Array = []
var touchables: Array = []
var player
var spawn := Vector2.ZERO
var total_berries := 0
var broken := {}  # breakable wall ids (star_key) broken this run (adventure: run.broken)
var collected := {}  # star id -> true, banked this run (adventure: run.stars, ids prefixed by room)
# Adventure only: current room of Game.adv_world and its top-left in world pixels.
var room := ""
var room_origin := Vector2.ZERO
var floor_gaps: Array = []  # openings in the room's bottom edge: [x0, x1 (px), leads to another room]
var near_layers := {}  # adventure: room name -> TileLayer of a room within a screen of this one (terrain only)
var near_rooms: Array = []  # adventure: [Rect2i in this room's tile coords, tiles] of rooms around, for collisions past the edge
var near_queue: Array[String] = []  # neighbours still to build, one per frame (_process)

var cam: Camera2D
var cam_pos := Vector2.ZERO
var freeze := 0.0
var shake_t := 0.0
var deaths := 0
var time := 0.0
var respawn_timer := 0.0
var parts: Array = []   # [pos, vel, life, color]
var trails: Array = []  # [Rect2, color, life]
var snow: Array = []
var paused := false
var done := false

var ui: CanvasLayer
var touch: Control  # phone controls, only on touchscreens
var hud: Hud
var note_label: Label  # design note under the player (entities.gd Note)
var note_t := 0.0
var spawn_queue: Array = []  # entity dicts to add after this tick (spawn_entity); never saved
# Adventure: the room just left keeps drawing its objects (frozen) until the camera has left it.
var leaving_ents: Array = []
var leaving_rect := Rect2()  # that room, in this room's coordinates
var pending_door = null  # door touched this tick (Door entity); used after the touch loop
var door_block := Rect2i()  # the door we arrived on: ignored until the player steps off it
var overlay: Control
var debug_panel: Control  # F1: state machine + tuning
var map_view: Control  # M: full-screen map (pauses)

func _redraw() -> void:
	queue_redraw()
	if background != null:
		background.queue_redraw()

func _create_tile_layer() -> void:
	background = Background.new()
	background.screen = self
	background.z_index = -2
	add_child(background)
	tile_layer = TileLayer.new()
	tile_layer.z_index = -1
	add_child(tile_layer)

func _ready() -> void:
	data = Game.level
	level_id = Game.file_safe(data.get("name", "untitled"))
	if adventure():
		room = Game.adv.room
		room_origin = Vector2(Game.adv_world.rooms[room].pos * T)
		for k in Game.adv.stars:
			collected[k] = true
		for k in Game.adv.get("broken", []):
			broken[k] = true
		deaths = Game.adv.deaths
		time = Game.adv.time
	cam = Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	add_child(cam)
	cam.make_current()
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	hud.theme = Game.theme
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hud)
	if TouchControls.wanted():
		touch = TouchControls.new()
		ui.add_child(touch)
	note_label = Label.new()
	note_label.theme = Game.theme
	note_label.add_theme_color_override("font_color", Color("ffe08a"))
	note_label.add_theme_color_override("font_outline_color", Color.BLACK)
	note_label.add_theme_constant_override("outline_size", 6)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.position = Vector2(140, 600)
	note_label.size = Vector2(1000, 80)
	ui.add_child(note_label)
	for i in 60:
		snow.append(Vector2(randf() * VIEW.x, randf() * VIEW.y))
	_build()
	_create_tile_layer()
	tile_layer.setup(tiles, gw, gh, data.get("environment", ""))
	_load_near()
	_scan_floor_gaps()
	cam_pos = _clamp_cam(player.camera_target())

func _build(keep_player := false) -> void:
	if tiles.is_empty():
		tiles = data.tiles.duplicate()
	gw = int(data.w)
	gh = int(data.h)
	grid.resize(gw * gh)
	for y in gh:
		var row: String = tiles[y]
		for x in gw:
			grid[y * gw + x] = 1 if row.unicode_at(x) == 49 else 0
	bounds = Rect2i(0, 0, gw * T, gh * T)
	leaving_ents = []
	ents.clear(); solids.clear(); jumpthrus.clear(); dreams.clear(); spikes.clear(); touchables.clear(); spawn_queue.clear()
	total_berries = 0
	spawn = Vector2(gw * T / 2.0, 16)
	for d in data.entities:
		if d.t == "spawn":
			spawn = Vector2(float(d.x) + 4, float(d.y) + 8)
			continue
		var e = E.make(self, d)
		if e == null:
			continue
		ents.append(e)
		if e.solid:
			solids.append(e)
			if e.dream:
				dreams.append(e)
		elif e.jumpthru:
			jumpthrus.append(e)
		else:
			touchables.append(e)
			if e is E.Spikes:
				spikes.append(e)
		if e is E.Star:
			total_berries += 1
	if adventure():
		total_berries = Adventure.star_count(Game.adv_world)
		if Game.adv.spawn is Array:
			spawn = Vector2(Game.adv.spawn[0], Game.adv.spawn[1])
	# draw solids under everything else
	ents.sort_custom(func(a, b): return int(a.solid or a.jumpthru) > int(b.solid or b.jumpthru))
	if not keep_player:
		player = PlayerScript.new(self, spawn)

# ---------------- adventure rooms ----------------
func adventure() -> bool:
	return not Game.adv.is_empty()

# Star ids are per room in the adventure so equal coordinates in two rooms don't clash.
func star_key(id: String) -> String:
	return room + ":" + id if adventure() else id

# True when local point p (just outside this room) lies inside another room: the player may walk there.
func can_exit(p: Vector2) -> bool:
	return adventure() and Adventure.room_at(Game.adv_world, room_origin + p, room) != ""

# Called after the player moves: once their centre leaves the room, switch to the room it is in.
func _check_room_exit() -> void:
	if not adventure() or player.dead or Rect2(bounds).has_point(player.center()):
		return
	var g: Vector2 = room_origin + player.center()
	var next := Adventure.room_at(Game.adv_world, g, room)
	if next != "":
		enter_room(next)

# Room changes after the player moved: walking off an edge, or a door touched this tick.
func after_player_move() -> void:
	for d in spawn_queue:  # entities born this tick (a Brood enemy splitting), added once nothing is iterating ents
		var e = E.make(self, d)
		ents.append(e)
		touchables.append(e)
	spawn_queue.clear()
	_check_room_exit()
	if pending_door != null and not player.dead:
		_go_door(pending_door)
	if door_block.has_area() and not door_block.intersects(player.hurt_rect()):
		door_block = Rect2i()

func spawn_entity(d: Dictionary) -> void:
	spawn_queue.append(d)

func door_hit(door) -> void:
	if not door_block.intersects(door.rect):
		pending_door = door

# "room:id" or "id" (same level). The player keeps speed and their offset inside the doorway.
func _go_door(door) -> void:
	pending_door = null
	var to: String = door.d.get("to", "")
	var target_room := room
	if to.contains(":"):
		target_room = to.get_slice(":", 0)
		to = to.get_slice(":", 1)
	var lvl: Dictionary = data if target_room == room else (Game.adv_world.rooms[target_room].level if adventure() and Game.adv_world.rooms.has(target_room) else {})
	var dest = null
	for e in lvl.get("entities", []):
		if e.t == "door" and e.get("id", "") == to:
			dest = e
	if dest == null:
		show_note("door leads to \"%s\", which doesn't exist" % door.d.get("to", ""))
		return
	var dr := Rect2(float(dest.x), float(dest.y), float(dest.get("w", T)), float(dest.get("h", T)))
	var off: Vector2 = player.pos - Vector2(door.rect.position)
	# player.pos is the bottom centre of an 8x11 hitbox: keep the whole box inside the target doorway
	var at := dr.position + Vector2(clampf(off.x, minf(4, dr.size.x / 2), maxf(dr.size.x - 4, dr.size.x / 2)),
		clampf(off.y, minf(11, dr.size.y), dr.size.y))
	if target_room == room:
		player.pos = at
		_unstick()
	else:
		enter_room(target_room, at)
		cam_pos = _clamp_cam(player.camera_target())  # a door can lead anywhere: don't sweep the view across the world
	door_block = Rect2i(dr)

func enter_room(next: String, at = null) -> void:
	var global: Vector2 = room_origin + player.pos
	var old_origin := room_origin
	var old_room := room
	var went_up: bool = player.center().y < 0
	room = next
	room_origin = Vector2(Game.adv_world.rooms[room].pos * T)
	data = Game.adv_world.rooms[room].level
	tiles = []
	player.followers.clear()  # unbanked stars go back to their room
	var left := ents.duplicate()
	var left_size := Vector2(gw * T, gh * T)
	_build(true)
	leaving_ents = left
	leaving_rect = Rect2(old_origin - room_origin, left_size)
	player.pos = global - room_origin if at == null else at
	if went_up and at == null:  # Celeste-style lift so an upward exit doesn't fall straight back
		player.speed.y = minf(player.speed.y, player.JUMP_SPEED)
	# respawn at the room's spawn marker closest to where we came in, else at the entry point
	var best: Vector2 = player.pos
	var best_d := INF
	for d in data.entities:
		if d.t == "spawn":
			var sp := Vector2(float(d.x) + 4, float(d.y) + 8)
			if sp.distance_to(player.pos) < best_d:
				best_d = sp.distance_to(player.pos)
				best = sp
	spawn = best
	Game.adv.room = room
	Game.adv.spawn = [spawn.x, spawn.y]
	if not Game.adv.visited.has(room):
		Game.adv.visited.append(room)
	_save_run()
	# the next room's terrain is usually drawn already as a neighbour: swap it in, keep the old room as one
	if near_layers.has(room):
		near_layers[old_room] = tile_layer
		tile_layer = near_layers[room]
		near_layers.erase(room)
		tiles = tile_layer.tiles
	else:
		tile_layer.setup(tiles, gw, gh, data.get("environment", ""))
	_load_near()
	_scan_floor_gaps()
	_unstick()
	cam_pos -= room_origin - old_origin  # keep the view where it was, then ease into the new room
	if map_view != null:
		_toggle_map()

# Terrain of the rooms around this one, so crossing into one shows no pop-in; entities load only on entry.
# Built one room per frame so entering a room doesn't hitch.
func _load_near() -> void:
	if not adventure():
		return
	var rooms: Dictionary = Game.adv_world.rooms
	var area := Adventure.room_rect(rooms[room]).grow_individual(int(VIEW.x), int(VIEW.y), int(VIEW.x), int(VIEW.y))
	near_rooms = []
	var here: Vector2i = rooms[room].pos
	for n in rooms:
		if n != room and Adventure.room_rect(rooms[n]).intersects(area.grow(T * 4)):
			var lv: Dictionary = rooms[n].level
			near_rooms.append([Rect2i(rooms[n].pos - here, Vector2i(lv.w, lv.h)), lv.tiles])
	for n in near_layers.keys():
		if not Adventure.room_rect(rooms[n]).intersects(area):
			near_layers[n].queue_free()
			near_layers.erase(n)
	near_queue.clear()
	for n in rooms:
		if n != room and not near_layers.has(n) and Adventure.room_rect(rooms[n]).intersects(area):
			near_queue.append(n)
	tile_layer.position = Vector2.ZERO
	for n in near_layers:
		near_layers[n].position = Vector2(rooms[n].pos * T) - room_origin

func _process(_delta: float) -> void:
	if touch != null:
		touch.visible = not (paused or done or map_view != null or debug_panel != null)
	if near_queue.is_empty():
		return
	var n: String = near_queue.pop_front()
	if not adventure() or not Game.adv_world.rooms.has(n):
		return
	var r: Dictionary = Game.adv_world.rooms[n]
	var l := TileLayer.new()
	l.z_index = -1
	l.position = Vector2(r.pos * T) - room_origin
	add_child(l)
	l.setup(r.level.tiles, int(r.level.w), int(r.level.h), r.level.get("environment", ""))
	near_layers[n] = l

func break_wall(id: String) -> void:
	broken[id] = true
	_save_run()

# Falling out of the bottom edge kills unless another room is below: mark each opening as pit (red) or hole (cyan).
func _scan_floor_gaps() -> void:
	floor_gaps.clear()
	var row: String = tiles[gh - 1]
	var x := 0
	while x < gw:
		if row.unicode_at(x) == 49:
			x += 1
			continue
		var hole := can_exit(Vector2(x * T + 4, gh * T + 4))
		var x0 := x
		while x < gw and row.unicode_at(x) != 49 and can_exit(Vector2(x * T + 4, gh * T + 4)) == hole:
			x += 1
		floor_gaps.append([x0 * T, x * T, hole])

func _draw_floor_gaps() -> void:
	var y := float(gh * T)
	for g in floor_gaps:
		var w: float = g[1] - g[0]
		var col := Color("40e0ff") if g[2] else Color("ff3030")
		for i in 4:  # glow fading upward from the edge
			draw_rect(Rect2(g[0], y - 3 * (i + 1), w, 3), Color(col, 0.28 - i * 0.06))
		if g[2]:  # hole: arrows pointing down
			var bob := roundf(sin(time * 4.0))
			for x in range(int(g[0]) + 4, int(g[1]), 8):
				draw_colored_polygon(PackedVector2Array([Vector2(x - 2, y - 7 + bob), Vector2(x + 2, y - 7 + bob), Vector2(x, y - 4 + bob)]), Color(col, 0.8))
		else:  # pit: red teeth along the edge
			for x in range(int(g[0]), int(g[1]), 4):
				draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 4, y), Vector2(x + 2, y - 3)]), Color(col, 0.85))

func show_note(text: String) -> void:
	note_label.text = "Note: " + text
	note_t = 0.1

# Adventure energy: regenerates out of water; in water it drains, and running out there drowns the player.
func update_energy(dt: float) -> void:
	if not adventure() or player.dead:
		return
	if not in_water():
		Adventure.regen_energy(Game.adv, dt)
	elif not Adventure.water_energy(Game.adv, dt):
		player.die(Vector2.UP)

func in_water() -> bool:
	return liquid_at(player.hurt_rect(), "water")

# True when r overlaps an entity of type t (water, waterfall...).
func liquid_at(r: Rect2i, t: String) -> bool:
	for e in touchables:
		if e.d.t == t and e.rect.intersects(r):
			return true
	return false

func energy_block_taken(key: String) -> bool:
	return Game.adv.get("taken", []).has(key)

func add_energy_block(key: String) -> void:
	if adventure() and not energy_block_taken(key):
		Game.adv.taken.append(key)
		Adventure.add_energy_block(Game.adv)
		_save_run()

func drain_energy(amount: float) -> void:
	if adventure():
		Adventure.drain_energy(Game.adv, amount)

func refill_energy() -> void:
	if adventure():
		Adventure.refill_energy(Game.adv)

func grant_ability(a: String) -> void:
	if adventure() and not Game.adv.abilities.has(a):
		Game.adv.abilities.append(a)
		_save_run()

func _save_run() -> void:
	if not adventure():
		return
	Game.adv.deaths = deaths
	Game.adv.time = time
	Game.adv.stars = collected.keys()
	Game.adv.broken = broken.keys()
	Game.save_adventure()

# ---------------- collision queries (used by player + entities) ----------------
func collide_solid(r: Rect2i, ignore = null, skip_dream := false):
	var x0 := floori(r.position.x / float(T))
	var x1 := floori((r.end.x - 1) / float(T))
	var y0 := floori(r.position.y / float(T))
	var y1 := floori((r.end.y - 1) / float(T))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x >= 0 and y >= 0 and x < gw and y < gh:
				if grid[y * gw + x] == 1:
					return "tile"
			elif _near_solid(x, y):  # past this room's edge: the next room's rock blocks too
				return "tile"
	for s in solids:
		if s.collidable and s != ignore and not (skip_dream and s.dream) and s.rect.intersects(r):
			return s
	return null

# Tile (x, y) in this room's coordinates, outside it: rock in a neighbouring room? No room there = open.
func _near_solid(x: int, y: int) -> bool:
	for nr in near_rooms:
		var rr: Rect2i = nr[0]
		if rr.has_point(Vector2i(x, y)):
			return (nr[1][y - rr.position.y] as String).unicode_at(x - rr.position.x) == 49
	return false

# After a room change or door arrival: if the body overlaps rock, move it to the nearest free spot (16px at most)
# whose centre is inside a room. Back across the edge is allowed: an object the player couldn't see from there
# (a breakable wall) then simply blocks the way.
func _unstick() -> void:
	if collide_solid(player.hitbox()) == null:
		return
	for d in range(1, 17):
		for off in [Vector2(0, -d), Vector2(-d, 0), Vector2(d, 0), Vector2(0, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]:
			var r: Rect2i = player.rect_at(player.pos + off)
			var c := Vector2(r.get_center())
			if (Rect2(bounds).has_point(c) or can_exit(c)) and collide_solid(r) == null:  # stay inside some room
				player.pos += off
				return

func collide_jumpthru_outside(r_at: Rect2i, r_now: Rect2i):
	for j in jumpthrus:
		if j.collidable and j.rect.intersects(r_at) and not j.rect.intersects(r_now):
			return j
	return null

func collide_jumpthru(r: Rect2i):
	for j in jumpthrus:
		if j.collidable and j.rect.intersects(r):
			return j
	return null

func collide_dream(r: Rect2i):
	for d in dreams:
		if d.collidable and d.rect.intersects(r):
			return d
	return null

func touching_spikes(r: Rect2i) -> bool:
	for s in spikes:
		if s.rect.intersects(r):
			return true
	return false

func player_touch(p) -> void:
	var hr: Rect2i = p.hurt_rect()
	var dr: Rect2i = p.damage_rect()
	for e in touchables:
		if p.dead or done:
			return
		if e.collidable and e.touch_rect().intersects(dr if e.hurts() else hr):
			e.touch(p)

# ---------------- events ----------------
func freeze_for(t: float) -> void:
	freeze = maxf(freeze, t)

func shake_dir(_dir: Vector2, t: float) -> void:
	if Game.settings.shake:
		shake_t = maxf(shake_t, t)

func dust(at: Vector2, dir: Vector2, n: int, col := Color(1, 1, 1, 0.7)) -> void:
	for i in n:
		var v := dir.rotated(randf_range(-0.6, 0.6)) * randf_range(10, 40)
		parts.append([at + Vector2(randf_range(-2, 2), randf_range(-2, 2)), v, randf_range(0.2, 0.4), col])

func burst(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		parts.append([at, Vector2.RIGHT.rotated(TAU * i / n) * 60, 0.4, col])

func add_trail(p) -> void:
	trails.append([Rect2(p.hitbox()), p.hair_color(), 0.35])

# Every respawn counts as a death. In the adventure a hit also costs an energy block; losing the
# last one refills energy (a spare block is simply spent, like Hollow Knight's hazard respawn).
func on_player_death(p, _dir: Vector2) -> void:
	deaths += 1
	if adventure() and not Adventure.hit_energy(Game.adv):
		Adventure.refill_energy(Game.adv)
	respawn_timer = 0.6
	burst(p.center(), p.hair_color(), 12)
	shake_t = 0.3 if Game.settings.shake else 0.0

func collect_berry(b) -> void:
	collected[b.id] = true
	_save_run()
	burst(b.pos, Color("e03c3c"), 10)

func complete() -> void:
	if done:
		return
	done = true
	if adventure():
		Game.adv.done = true
		_save_run()
	elif not Game.playtest:
		Game.submit_record(level_id, time, deaths, collected.size(), total_berries)
	_show_complete()

# ---------------- loop ----------------
func _unhandled_input(event: InputEvent) -> void:
	if done or paused:
		pass
	elif event.is_action_pressed("map") or (map_view != null and event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		_toggle_map()
		return
	elif map_view == null and (event.is_action_pressed("debug") or (debug_panel != null and event.is_action_pressed("pause"))):
		get_viewport().set_input_as_handled()
		_toggle_debug()
		return
	elif event.is_action_pressed("hitboxes"):
		get_viewport().set_input_as_handled()
		Game.settings.hitboxes = not Game.settings.hitboxes
		Game.save_settings()
		if debug_panel != null:
			debug_panel.hitbox_btn.set_pressed_no_signal(Game.settings.hitboxes)
		return
	# handled here (not in _physics_process) so the options screen can swallow Esc first
	if event.is_action_pressed("pause") and not done and not (overlay is OptionsPanel):
		get_viewport().set_input_as_handled()
		_set_paused(not paused)

func _physics_process(_delta: float) -> void:
	if paused or done or map_view != null:
		return
	if debug_panel != null and (debug_panel.typing() or debug_panel.sim_paused):
		if debug_panel.typing() or debug_panel.step_frames == 0:
			return
		debug_panel.step_frames -= 1
	var dt: float = DT * Game.settings.game_speed
	if freeze > 0:
		freeze -= dt
		return
	time += dt
	if player.dead:
		respawn_timer -= dt
		if respawn_timer <= 0:
			_build()
	else:
		player.update(dt)
		after_player_move()
		update_energy(dt)
	for e in ents:
		e.update(dt)
	for i in range(parts.size() - 1, -1, -1):
		var pt = parts[i]
		pt[0] += pt[1] * dt
		pt[1] *= 0.92
		pt[2] -= dt
		if pt[2] <= 0:
			parts.remove_at(i)
	for i in range(trails.size() - 1, -1, -1):
		trails[i][2] -= dt
		if trails[i][2] <= 0:
			trails.remove_at(i)
	for i in snow.size():
		snow[i] = Vector2(fposmod(snow[i].x - 20 * dt, VIEW.x), fposmod(snow[i].y + 12 * dt, VIEW.y))

	if not player.dead:
		var target: Vector2 = _clamp_cam(player.camera_target())
		cam_pos += (target - cam_pos) * (1.0 - pow(0.01, dt))
	var off := Vector2.ZERO
	if shake_t > 0:
		shake_t -= dt
		off = Vector2(randi_range(-1, 1), randi_range(-1, 1))
	cam.position = (cam_pos + off).round()
	note_t -= dt
	note_label.visible = note_t > 0 and map_view == null
	hud.queue_redraw()
	_redraw()

func _clamp_cam(t: Vector2) -> Vector2:
	var half := VIEW / 2.0
	var b := Rect2(bounds)
	var x := b.get_center().x if b.size.x <= VIEW.x else clampf(t.x, half.x, b.end.x - half.x)
	var y := b.get_center().y if b.size.y <= VIEW.y else clampf(t.y, half.y, b.end.y - half.y)
	return Vector2(x, y)

# Where the view would settle with the camera in room area (as _clamp_cam does for this room).
func _rest_view(view: Rect2, area: Rect2) -> Rect2:
	var x := area.get_center().x - VIEW.x / 2 if area.size.x <= VIEW.x else clampf(view.position.x, area.position.x, area.end.x - VIEW.x)
	var y := area.get_center().y - VIEW.y / 2 if area.size.y <= VIEW.y else clampf(view.position.y, area.position.y, area.end.y - VIEW.y)
	return Rect2(x, y, VIEW.x, VIEW.y)

func _draw_background(ci: CanvasItem) -> void:
	var view := Rect2(cam.position - VIEW / 2.0, VIEW)
	Art.draw_background(ci, view, time, data.get("environment", ""), Rect2(0, 0, data.w * T, data.h * T))
	if adventure():  # each themed room's painting belongs to its room: it slides in and out with it in a transition
		for n in [room] + near_layers.keys():
			var r: Dictionary = Game.adv_world.rooms[n]
			var area := Rect2(Vector2(r.pos * T) - room_origin, Vector2(r.level.w, r.level.h) * T)
			var env: String = r.level.get("environment", "")
			if area.intersects(view) and env in Art.EnvironmentArt.THEMES:
				Art.EnvironmentArt.draw_background(ci, _rest_view(view, area), env, area, area.intersection(view))
	for s in (snow if data.get("environment", "") == "" else []):
		ci.draw_rect(Rect2((view.position + s).floor(), Vector2.ONE), Color(1, 1, 1, 0.35))

func _draw() -> void:
	# Also follow redraws requested directly by tools or benchmark subclasses.
	background.queue_redraw()
	var view := Rect2(cam.position - VIEW / 2.0, VIEW)
	var cull := Rect2i(view.position.floor(), view.size.ceil()).grow(1)
	var over: Array = []  # water and waterfalls draw over the player
	for e in ents:
		if e.vis_rect().intersects(cull):  # offscreen entities still update, just don't draw
			if e.d.t == "water" or e.d.t == "waterfall":
				over.append(e)
			else:
				e.draw(self)
	if not leaving_ents.is_empty():
		if not leaving_rect.intersects(view):  # the transition is over
			leaving_ents = []
		draw_set_transform(leaving_rect.position)
		var old_cull := Rect2i(cull.position - Vector2i(leaving_rect.position), cull.size)
		for e in leaving_ents:
			if e.vis_rect().intersects(old_cull):
				e.draw(self)
		draw_set_transform(Vector2.ZERO)
	_draw_floor_gaps()
	for t in trails:
		draw_rect(t[0], Color(t[1], minf(t[2] * 1.5, 0.6)))
	player.draw(self)
	for e in over:
		e.draw(self)
	for pt in parts:
		draw_rect(Rect2(pt[0].floor(), Vector2.ONE), Color(pt[3], clampf(pt[2] * 3, 0, 1)))
	if Game.settings.hitboxes:
		_draw_hitboxes(cull)

# Debug overlay (Options / F1 "Hitboxes"): the rects collision and touches actually use.
# Thin lines (-1: one screen pixel at any zoom), colours from HITBOX_KEY.
func _draw_hitboxes(cull: Rect2i) -> void:
	for e in ents:
		if not e.vis_rect().intersects(cull):
			continue
		if e.solid or e.jumpthru:  # what the player collides with
			if e.collidable:
				draw_rect(Rect2(e.rect), HITBOX_KEY[0][1], false, -1.0)
		elif e is E.Ape:
			for box in e.body_boxes():
				draw_rect(Rect2(box), HITBOX_KEY[1][1] if e.collidable else Color(HITBOX_KEY[1][1],0.3), false, -1.0)
		elif e.touch_rect().has_area():  # what the player touches: pickups, hazards, triggers
			draw_rect(Rect2(e.touch_rect()), HITBOX_KEY[1][1] if e.collidable else Color(HITBOX_KEY[1][1], 0.3), false, -1.0)
	for e in ents:  # what hurts besides the bodies: projectiles, puddles, the Ape's stones, scream and slam
		for b in e.damage_boxes():
			draw_rect(Rect2(b), HITBOX_KEY[2][1], false, -1.0)
		for circle in e.damage_circles():
			draw_arc(circle[0],circle[1],0,TAU,64,HITBOX_KEY[2][1],-1.0)
	draw_rect(Rect2(player.hitbox()), HITBOX_KEY[3][1], false, -1.0)
	draw_rect(Rect2(player.damage_rect()), HITBOX_KEY[4][1], false, -1.0)  # what hazards test against
	if player.attacking():
		var c: Vector2 = player.center()
		var half := deg_to_rad(player.ATTACK_ARC) / 2.0
		var pts := PackedVector2Array([c])
		for i in 13:
			pts.append(c + Vector2.from_angle(player.attack_dir.angle() - half + 2.0 * half * i / 12.0) * player.ATTACK_RANGE)
		pts.append(c)
		draw_polyline(pts, HITBOX_KEY[5][1], -1.0)

# ---------------- menus ----------------
func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null

func _panel(title: String) -> VBoxContainer:
	_clear_overlay()
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = Game.theme
	ui.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(Game.label(title, 44))
	return box

func _set_paused(v: bool) -> void:
	paused = v
	if not v:
		_clear_overlay()
		return
	var box := _panel("Paused")
	var resume := Game.button("Resume", func(): _set_paused(false))
	box.add_child(resume)
	box.add_child(Game.button("Retry", func():
		_set_paused(false)
		player.die(Vector2.ZERO)
		if not player.dead:  # invincible: force a respawn anyway
			_build()))
	if not adventure():
		box.add_child(Game.button("Restart Level", _restart))
	box.add_child(Game.button("Options", _open_options))
	box.add_child(Game.button("Tuning && State (%s)" % Game.key_name("debug"), func():
		_set_paused(false)
		if debug_panel == null:
			_toggle_debug()))
	box.add_child(Game.button(_exit_label(), _exit))
	resume.grab_focus()

func _toggle_debug() -> void:
	if debug_panel != null:
		debug_panel.queue_free()
		debug_panel = null
	else:
		debug_panel = DebugPanel.new(self)
		ui.add_child(debug_panel)

func _toggle_map() -> void:
	if map_view != null:
		map_view.queue_free()
		map_view = null
	else:
		map_view = MapView.new(self)
		ui.add_child(map_view)
	hud.visible = map_view == null

func _open_options() -> void:
	_clear_overlay()
	overlay = OptionsPanel.new()
	ui.add_child(overlay)
	overlay.closed.connect(func(): _set_paused(true))

func _restart() -> void:
	paused = false
	done = false
	_clear_overlay()
	deaths = 0
	time = 0
	collected.clear()
	broken.clear()
	pending_door = null
	door_block = Rect2i()
	_build()
	cam_pos = _clamp_cam(player.camera_target())

func _exit_label() -> String:
	return "Back to Editor" if Game.playtest else ("Back to World Editor" if Game.adv_temp and adventure() else "Exit to Menu")

func _exit() -> void:
	_save_run()
	if Game.playtest:
		Game.goto("editor")
	elif Game.adv_temp and adventure():
		Game.goto("world_editor")
	else:
		Game.goto("menu")

func _show_complete() -> void:
	var box := _panel("Adventure Complete!" if adventure() else "Level Complete!")
	box.add_child(Game.label("Time  %s" % Game.fmt_time(time)))
	box.add_child(Game.label("Deaths  %d" % deaths))
	box.add_child(Game.label("Stars  %d / %d" % [collected.size(), total_berries]))
	if not Game.playtest and not adventure():
		var rec := Game.get_record(level_id)
		box.add_child(Game.label("Best  %s" % Game.fmt_time(rec.get("best_time", time)), 20))
	var first := Game.button(_exit_label(), _exit)
	if not adventure():
		first = Game.button("Play Again", _restart)
		box.add_child(first)
		box.add_child(Game.button(_exit_label(), _exit))
	else:
		box.add_child(first)
	first.grab_focus()
