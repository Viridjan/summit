extends Node2D
# A playable room: joins together terrain, the player, objects, camera, sound and menus.
# Game.level supplies the room data; Game.adv adds persistent progress in an adventure run.
# Physics changes the simulation at 60 steps/second. Drawing only displays its current state.
# Terrain is an 8px tile grid; entity rectangles and player positions are in world pixels.
# Room-local coordinates start at (0,0); room_origin translates them onto the adventure map.
# The separate entity lists speed up queries: solids block movement; touchables react to overlap.
# See docs/CODE_GUIDE.md for the complete path from a button press to a rendered frame.
# Reading help: docs/CODE_GUIDE.md.

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
# Separate drawing node kept behind cached terrain so changing objects do not force terrain redraws.
class Background extends Node2D:
	var screen: Node2D
	# Draw active and leaving-room objects, movement trails and particles over retained terrain.
	func _draw() -> void:
		screen._draw_background(self)

# Black mask over everything outside a room smaller than the view (the room sits centred in it). It fades in once
# the camera has settled and drops as soon as the player enters the next room, so the transition shows both rooms.
class RoomMask extends Node2D:
	var screen: Node2D
	func _draw() -> void:
		screen._draw_room_mask(self)

# Hitbox overlay (F2) colours, also listed in its legend: [label, colour].
const HITBOX_KEY := [  # [label, colour, mouse-over explanation]
	["Solid, platform", Color(1, 0.9, 0.2, 0.9), "Blocks movement: walls, blocks, gates; jump-throughs hold you from above only."],
	["Touch: pickups, hazards, triggers", Color(1, 0.5, 0.1, 0.9), "Something happens when your damage box overlaps it: pick up, die, open, play a sound. Faded: inactive."],
	["Damage: projectiles, scream, slam", Color(1, 0.15, 0.2, 0.9), "Live attacks: touching one with your damage box kills you (stones, logs, rocks, screams, shockwaves, eruptions)."],
	["Player: collision", Color(0.2, 1, 0.3, 0.9), "What hits walls and floors (8 x 11 px, shorter when ducking)."],
	["Player: damage box", Color(1, 0.3, 0.8, 0.9), "The smaller box hazards and attacks must touch to kill you."],
	["Attack swing", Color(0.55, 0.8, 1, 0.9), "The sword swing's reach while attacking: hits enemies and breakable walls."],
]
const PlayerStates := preload("res://scripts/debug_panel.gd")

# On-screen HUD: stamina (top left), area name (top centre), timer and deaths (top right).
# Draws black bars around the fixed game view when the window has extra screen space.
class Letterbox extends Control:
	# Read the chosen level, build the playable room and interface, then prepare music and neighboring terrain.
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	# Draw active and leaving-room objects, movement trails and particles over retained terrain.
	func _draw() -> void:
		var inner := Rect2((size - Vector2(1280, 720)) / 2.0, Vector2(1280, 720))
		var black := Color.BLACK
		draw_rect(Rect2(0, 0, size.x, inner.position.y), black)
		draw_rect(Rect2(0, inner.end.y, size.x, size.y - inner.end.y), black)
		draw_rect(Rect2(0, inner.position.y, inner.position.x, 720), black)
		draw_rect(Rect2(inner.end.x, inner.position.y, size.x - inner.end.x, 720), black)


# Screen-space heads-up display: draws counters/resources without moving with the world camera.
class Hud extends Control:
	const M := 16.0  # margin from the screen edges
	const BOLT := [Vector2(10, 0), Vector2(1, 16), Vector2(8, 16), Vector2(4, 28), Vector2(18, 10), Vector2(11, 10), Vector2(16, 0)]
	const SKULL := ["  ####  ", " ###### ", "##.##.##", "########", " ##..## ", "  # # # "]  # 8x6, "." = eye/nose holes
	var world

	# Stamina bar colour by how full the whole bar is: red when empty, yellow at half, mint when full.
	# Choose the HUD stamina-bar color from its remaining percentage.
	static func bar_color(pct: float) -> Color:
		pct = clampf(pct, 0.0, 1.0)
		if pct < 0.5:
			return Color("ff4a3a").lerp(Color("ffd84a"), pct * 2.0)
		return Color("ffd84a").lerp(Color("7cf0c0"), pct * 2.0 - 1.0)

	# Fill of each bar, 0..1: the base first, then one per extra block.
	# Convert current stamina into the per-block fill values used by the HUD.
	static func block_fills(stamina: float, blocks: int) -> Array:
		var out := [clampf(stamina / Adventure.BASE_STAMINA, 0.0, 1.0)]
		for i in blocks - 1:
			out.append(clampf((stamina - Adventure.BASE_STAMINA - i * Adventure.STAMINA_PER_BLOCK) / Adventure.STAMINA_PER_BLOCK, 0.0, 1.0))
		return out

	# Draw a small HUD text item with consistent font/position settings.
	# A wrapped mouse-over box (F2 overlay), kept on screen.
	func _tooltip(font: Font, at: Vector2, lines: Array) -> void:
		const TW := 360.0
		var fs := 14
		var text := "\n".join(lines)
		var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, TW, fs).y
		var pos := at + Vector2(16, 16)
		pos.x = minf(pos.x, size.x - TW - 20)
		pos.y = minf(pos.y, size.y - h - 20)
		draw_rect(Rect2(pos - Vector2(8, 6), Vector2(TW + 16, h + 12)), Color(0.04, 0.05, 0.09, 0.92))
		draw_multiline_string(font, pos + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, TW, fs, -1, Color.WHITE)

	func _text(font: Font, at: Vector2, s: String, fs: int, col := Color.WHITE) -> void:
		draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
		draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# Draw active and leaving-room objects, movement trails and particles over retained terrain.
	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var w = world
		var sz := get_viewport_rect().size
		var y := M
		# top left: stamina (adventure) as a bolt and one bar per block, then the stars
		if w.adventure():
			var bolt := PackedVector2Array(BOLT.map(func(p): return p + Vector2(M, y)))
			draw_colored_polygon(bolt, Color("ffd84a"))
			draw_polyline(bolt + PackedVector2Array([bolt[0]]), Color.BLACK, 2.0)
			var col := bar_color(Game.adv.stamina / Adventure.stamina_max(Game.adv))
			var x := M + 26.0
			var fills := block_fills(Game.adv.stamina, int(Game.adv.blocks))
			for i in fills.size():
				var f: float = fills[i]
				var cap: float = Adventure.BASE_STAMINA if i == 0 else Adventure.STAMINA_PER_BLOCK
				var r := Rect2(x, y + 7, roundf(cap * 0.92), 14)  # bar width follows what it holds (0.92 px per stamina)
				draw_rect(r.grow(2), Color.BLACK)
				draw_rect(r, Color(0.12, 0.15, 0.2))
				draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
				x += r.size.x + 8.0
			y += 34.0
			_text(font,Vector2(M,y+18),"Fragments %d/3" % (int(Game.adv.get("fragments",0)) % 3),18,Color("8ce1cc"))
			y += 26.0
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
			var mouse := get_local_mouse_position()
			var tip := ""
			for i in key.size():
				var ky := box.position.y + 8 + i * 20
				draw_rect(Rect2(box.position.x + 10, ky + 3, 14, 10), key[i][1], false, 1.0)
				draw_string(font, Vector2(box.position.x + 32, ky + 13), key[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
				if Rect2(box.position.x, ky, box.size.x, 20).has_point(mouse):
					tip = key[i][2]
			var lines: Array = [tip] if tip != "" else w.hover_lines()
			if not lines.is_empty():
				_tooltip(font, mouse, lines)

var tile_layer: TileLayer
var background: Background
var room_mask: RoomMask
var mask_a := 0.0  # room mask opacity

var data: Dictionary
var level_id := ""
var gw := 0
var gh := 0
var tiles: Array = []
var grid := PackedByteArray()
var bounds: Rect2i
var ents: Array = []
var solids: Array = []
var solid_cols: Array = []  # fixed solids by COL-px column of the room, for collide_solid; moving ones in loose_solids
var loose_solids: Array = []
var jumpthru_cols: Array = []  # jump-throughs (they never move), by column
var touch_by_type := {}  # touchables by type id ("water"...), for liquid_at
const COL := 64
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
# Render interpolation: physics runs at 60 Hz, the screen often faster (120/144/165 Hz). Each displayed frame
# draws the camera and the player between their last two ticks (_process), so motion doesn't judder or blur.
var cam_prev := Vector2.ZERO
var cam_now := Vector2.ZERO
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
var spawn_room := ""  # adventure: the room the respawn point (spawn) is in; another room when this one has no safe point
var kept_spikes := {}  # room -> [[type, x, y]...]: spikes as a boss fight left them, kept for respawns until the room is left
var stamina_log: Array = []  # [time, cause, delta], newest first (F3 panel)
var stamina_totals := {}  # cause -> [times, total delta] since the level started (F3 recap); regen/water: [seconds, total]
var stamina_panel: Control
var touch: Control  # phone controls, only on touchscreens
var hud: Hud
var note_label: Label  # design note under the player (entities.gd Note)
var note_t := 0.0
var spawn_queue: Array = []  # entity dicts to add after this tick (spawn_entity); never saved
# Adventure: the room just left keeps drawing its objects (frozen) until the camera has left it.
var leaving_ents: Array = []
# Adventure: after crossing into a room sideways the player is walked to the middle of its second tile column.
var walk_dir := 0
var door_near = null  # house door the player stands at this tick (interact to go through)
var walk_target_x := 0.0
var leaving_rect := Rect2()  # that room, in this room's coordinates
var pending_door = null  # door touched this tick (Door entity); used after the touch loop
var door_block := Rect2i()  # the door we arrived on: ignored until the player steps off it
var overlay: Control
var debug_panel: Control  # F1: movement tuning
var state_panel: Control  # F4: state machine and live variables
var map_view: Control  # M: full-screen map (pauses)

# Request fresh object and background drawing; retained terrain chunks manage their own redraws.
func _redraw() -> void:
	queue_redraw()
	if background != null:
		background.queue_redraw()
	if room_mask != null:
		room_mask.queue_redraw()

# Create the background and chunked terrain nodes in the correct back-to-front order.
func _create_tile_layer() -> void:
	background = Background.new()
	background.screen = self
	background.z_index = -2
	add_child(background)
	tile_layer = TileLayer.new()
	tile_layer.z_index = -1
	add_child(tile_layer)
	room_mask = RoomMask.new()
	room_mask.screen = self
	room_mask.z_index = 50
	add_child(room_mask)

# Read the chosen level, build the playable room and interface, then prepare music and neighboring terrain.
func _ready() -> void:
	data = Game.level
	level_id = Game.file_safe(data.get("name", "untitled"))
	if adventure():
		room = Game.adv.room
		spawn_room = room
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
	# The screen may be wider or taller than 1280x720 (stretch aspect "expand", so phone controls reach the
	# screen edges); the world view stays 1280x720 in the middle, with black bars around it.
	var bars := CanvasLayer.new()
	bars.layer = 1
	add_child(bars)
	var letterbox := Letterbox.new()
	bars.add_child(letterbox)
	ui = CanvasLayer.new()
	ui.layer = 2
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
	Game.get_music_engine().follow_environment(data.get("environment", ""))
	_load_near()
	_scan_floor_gaps()
	cam_pos = _clamp_cam(player.camera_target())
	snap_interp()

# Recreate the collision grid and entity objects; keep_player preserves the actor during a room transition.
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
	loose_solids.clear()
	solid_cols.clear()
	jumpthru_cols.clear()
	touch_by_type.clear()
	total_berries = 0
	spawn = Vector2(gw * T / 2.0, 16)
	for d in data.entities:
		if d.t == "spawn":
			spawn = Vector2(float(d.x) + 4, float(d.y) + 8)
			continue
		var e = E.make(self, d)
		if e == null:
			continue
		_register(e)
		if e is E.Star:
			total_berries += 1
	if adventure():
		total_berries = Adventure.star_count(Game.adv_world)
		if Game.adv.spawn is Array and Game.adv.room == room:
			var saved_spawn := Vector2(Game.adv.spawn[0], Game.adv.spawn[1])
			if safe_spawn(saved_spawn):
				spawn = saved_spawn
			else:
				Game.adv.spawn = null
	# draw solids under everything else
	ents.sort_custom(func(a, b): return int(a.solid or a.jumpthru) > int(b.solid or b.jumpthru))
	if not keep_player:
		player = PlayerScript.new(self, spawn)

# ---------------- adventure rooms ----------------
# Distinguish a connected adventure run from a standalone custom level.
func adventure() -> bool:
	return not Game.adv.is_empty()

# Star ids are per room in the adventure so equal coordinates in two rooms don't clash.
# Prefix a persistent object ID with its room name so equal coordinates in different rooms do not collide.
func star_key(id: String) -> String:
	return room + ":" + id if adventure() else id

# True when local point p (just outside this room) lies inside another room: the player may walk there.
# Check whether a point beyond this room belongs to another adventure room.
func can_exit(p: Vector2) -> bool:
	return adventure() and Adventure.room_at(Game.adv_world, room_origin + p, room) != ""

# Called after the player moves: once their centre leaves the room, switch to the room it is in.
# After movement, enter the neighboring room containing the player centre outside these bounds.
func _check_room_exit() -> void:
	if not adventure() or player.dead or Rect2(bounds).has_point(player.center()):
		return
	var g: Vector2 = room_origin + player.center()
	var next := Adventure.room_at(Game.adv_world, g, room)
	if next != "":
		enter_room(next)

# File an entity in the lists collision and contact checks walk.
# Register a placed or dynamically spawned object in the collision lists matching its flags.
func _register(e) -> void:
	ents.append(e)
	if e.solid:
		solids.append(e)
		if e.fixed:
			_col_add(solid_cols, e)
		else:
			loose_solids.append(e)
		if e.dream:
			dreams.append(e)
	elif e.jumpthru:
		jumpthrus.append(e)
		_col_add(jumpthru_cols, e)
	else:
		touchables.append(e)
		if not touch_by_type.has(e.d.t):
			touch_by_type[e.d.t] = []
		touch_by_type[e.d.t].append(e)
		if e is E.Spikes:
			spikes.append(e)

# Column index: cols[i] lists the entities overlapping x in [i * COL, (i + 1) * COL); edges clamp.
func _col_add(cols: Array, e) -> void:
	if cols.is_empty():
		cols.resize(gw * T / COL + 1)
		for i in cols.size():
			cols[i] = []
	for c in _col_span(cols, e.rect):
		cols[c].append(e)

func _col_span(cols: Array, r: Rect2i) -> Array:
	if cols.is_empty():
		return []
	return range(clampi(r.position.x / COL, 0, cols.size() - 1), clampi((r.end.x - 1) / COL, 0, cols.size() - 1) + 1)

# Room changes after the player moved: walking off an edge, or a door touched this tick.
# Apply deferred spawns and transitions after contact iteration is finished, avoiding mid-loop list changes.
func after_player_move() -> void:
	for d in spawn_queue:  # entities born this tick (a Brood enemy splitting, a cave-in), added once nothing is iterating ents
		_register(E.make(self, d))
	spawn_queue.clear()
	_check_room_exit()
	if pending_door != null and not player.dead:
		_go_door(pending_door)
	elif door_near != null and not player.dead and player.on_ground and player.interact:
		var d = door_near
		door_near = null
		_go_door(d)
	if door_block.has_area() and not door_block.intersects(player.hurt_rect()):
		door_block = Rect2i()
	if walk_dir != 0 and (player.dead or (player.pos.x - walk_target_x) * walk_dir >= 0 or player.force_move_x_timer <= 0):
		if not player.dead:
			player.force_move_x_timer = 0.0
		walk_dir = 0

# Queue an object dictionary for creation after the current update/contact work is safe to finish.
func spawn_entity(d: Dictionary) -> void:
	spawn_queue.append(d)

# Remember a touched automatic door unless its arrival lock is still preventing a return trip.
func door_hit(door) -> void:
	if not door_block.intersects(door.rect):
		pending_door = door

# "room:id" or "id" (same level). The player keeps speed and their offset inside the doorway.
# Resolve the linked doorway, transfer the player with a safe offset and prevent immediate teleporting back.
func _go_door(door) -> void:
	Game.play_sfx("door")
	pending_door = null
	var to: String = door.d.get("to", "")
	var target_room := room
	if to.contains(":"):
		target_room = to.get_slice(":", 0)
		to = to.get_slice(":", 1)
	var lvl: Dictionary = data if target_room == room else (Adventure.room_level(Game.adv_world, target_room, broken) if adventure() and Game.adv_world.rooms.has(target_room) else {})
	var dest = null
	for e in lvl.get("entities", []):
		if e.t in E.DOOR_TYPES and e.get("id", "") == to:
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
		snap_interp()
	door_block = Rect2i(dr)

# Swap room data while retaining player motion, update respawn/progress and reposition cached terrain.
# One player object crosses rooms. Its velocity stays intact while local coordinates and object lists change.
func enter_room(next: String, at = null) -> void:
	var global: Vector2 = room_origin + player.pos
	var old_origin := room_origin
	var old_room := room
	var went_up: bool = player.center().y < 0
	var in_dir := 0  # sideways crossings get the brief walk in
	if at == null:
		in_dir = 1 if player.center().x >= gw * T else (-1 if player.center().x < 0 else 0)
	room = next
	mask_a = 0.0  # the mask drops at once: the slide into the next room shows both
	room_origin = Vector2(Game.adv_world.rooms[room].pos * T)
	data = Adventure.room_level(Game.adv_world, room, broken)
	kept_spikes.clear()  # the room is left: a fight's leftovers don't carry over
	Game.get_music_engine().follow_environment(data.get("environment", ""))
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
	walk_dir = in_dir
	if in_dir != 0:  # walk 1 unit in: to the middle of the second tile column (where the entrance spawn sits)
		walk_target_x = T * 1.5 if in_dir > 0 else (gw - 1.5) * T
		player.force_move_x = in_dir
		player.force_move_x_timer = 0.6
	# Respawn at the safe spawn marker closest to where we came in, else the entry point if it's safe.
	# Fundamental rule: never in a hazard (docs/WORLD_DESIGN.md). With no safe point here (a flooded room,
	# mid-air), the last safe respawn stays, even in the previous room; the save keeps it too.
	var points: Array = []
	for d in data.entities:
		if d.t == "spawn":
			points.append(Vector2(float(d.x) + 4, float(d.y) + 8))
	points.sort_custom(func(a, b): return a.distance_to(player.pos) < b.distance_to(player.pos))
	points.append(player.pos)  # markers first; the entry point is the fallback
	for sp in points:
		if safe_spawn(sp):
			spawn = sp
			spawn_room = room
			Game.adv.room = room
			Game.adv.spawn = [spawn.x, spawn.y]
			break
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
	cam_prev -= room_origin - old_origin  # interpolation follows the re-based coordinates
	cam_now -= room_origin - old_origin
	player.prev_pos -= room_origin - old_origin
	if map_view != null:
		_toggle_map()

# Terrain of the rooms around this one, so crossing into one shows no pop-in; entities load only on entry.
# Built one room per frame so entering a room doesn't hitch.
# Find neighboring room tiles needed for collision and queue their visual layers for gradual loading.
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

# Refresh non-physics presentation and load queued neighboring artwork without building it all in one frame.
# Snap interpolation after a jump of the view or the player (room change, door, respawn): no sweep across.
func snap_interp() -> void:
	cam_now = cam_pos
	cam_prev = cam_pos
	if player != null:
		player.prev_pos = player.pos
		player.draw_off = Vector2.ZERO

func _process(_delta: float) -> void:
	if player != null:
		var f := Engine.get_physics_interpolation_fraction()
		var c := cam_prev.lerp(cam_now, f) if cam_prev.distance_to(cam_now) < 64.0 else cam_now
		cam.position = c.round()
		player.draw_off = (player.prev_pos.lerp(player.pos, f) - player.pos) if player.prev_pos.distance_to(player.pos) < 16.0 else Vector2.ZERO
		_redraw()
	if is_instance_valid(Game.music_engine):
		Game.music_engine.set_muffled(paused or map_view != null)
	if touch != null:
		touch.visible = not (paused or done or map_view != null or debug_panel != null or state_panel != null)
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

# Remember a destroyed wall or persistent boss object in the current run.
func break_wall(id: String) -> void:
	Game.play_sfx("crumble")
	broken[id] = true
	_save_run()

# Falling out of the bottom edge kills unless another room is below: mark each opening as pit (red) or hole (cyan).
# Collect exposed floor gaps once after building a room so visual warnings need not rescan every frame.
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

# Display the precomputed floor-gap markers without changing their collision or danger rules.
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

# Display a short room-design message and avoid replaying its sound on every contact step.
func show_note(text: String) -> void:
	if note_t <= 0 or note_label.text != "Note: " + text:
		Game.play_sfx("note")
	note_label.text = "Note: " + text
	note_t = 0.1

# Adventure stamina: regenerates out of water; in water it drains, and running out there drowns the player.
# Regenerate adventure stamina outside water or drain it underwater, triggering drowning at zero.
func update_stamina(dt: float) -> void:
	if not adventure() or player.dead:
		return
	var was: float = Game.adv.stamina
	var why := "regen"
	if player.state == player.ST_CLIMB:
		why = "climbing"  # on the wall: no regeneration (the climb drains it)
	elif not in_water():
		Adventure.regen_stamina(Game.adv, dt)
	else:
		why = "water"
		if not Adventure.water_stamina(Game.adv, dt):
			player.die(Vector2.UP)
	if Game.adv.stamina != was:
		_tally(why, Game.adv.stamina - was, dt)

# A respawn point is safe when the player standing there is out of water and acid, clear of spikes and on ground.
func safe_spawn(p: Vector2) -> bool:
	var body := Rect2i(int(p.x) - 4, int(p.y) - 11, 8, 11)
	if liquid_at(body, "water") or liquid_at(body, "acid") or touching_spikes(body.grow(1)):
		return false
	var feet := Rect2i(int(p.x) - 3, int(p.y), 6, 1)
	return collide_solid(feet) != null or collide_jumpthru(feet) != null

# Check whether the player centre is inside a water entity.
func in_water() -> bool:
	return liquid_at(player.hurt_rect(), "water")

# True when r overlaps an entity of type t (water, waterfall...).
# Test a rectangle against liquid objects of one named type, including non-collidable water.
func liquid_at(r: Rect2i, t: String) -> bool:
	for e in touch_by_type.get(t, []):
		if e.rect.intersects(r):
			return true
	return false

# Check the persistent pickup list before showing a one-time stamina-capacity upgrade.
func stamina_block_taken(key: String) -> bool:
	return Game.adv.get("taken", []).has(key)

# Increase stamina capacity, record this pickup and save the updated run.
func add_stamina_block(key: String) -> void:
	Game.play_sfx("unlock")
	if adventure() and not stamina_block_taken(key):
		Game.adv.taken.append(key)
		Adventure.add_stamina_block(Game.adv)
		stamina_event("stamina block (+capacity)", Adventure.STAMINA_PER_BLOCK)
		_save_run()

func show_interaction(text: String) -> void:
	note_label.text = text
	note_t = 3.0

func collect_energy_fragment(key: String) -> bool:
	if not adventure() or not Adventure.collect_energy_fragment(Game.adv,key):
		return false
	var complete: bool = int(Game.adv.fragments) % 3 == 0
	Game.play_sfx("unlock" if complete else "pickup")
	show_interaction("Energy upgraded! +%d capacity" % int(Adventure.STAMINA_PER_BLOCK) if complete else "Energy fragment %d/3" % (int(Game.adv.fragments)%3))
	_save_run()
	return true

# Spend adventure stamina for an action; standalone levels have no adventure stamina cost.
func drain_stamina(amount: float, why := "jump") -> void:
	if adventure():
		var was: float = Game.adv.stamina
		Adventure.drain_stamina(Game.adv, amount)
		stamina_event(why, Game.adv.stamina - was)

# F2 overlay mouse-over: what is under the mouse in the world (the player, then objects), with its state.
func hover_lines() -> Array:
	var at := get_global_mouse_position()
	var out := []
	if Rect2(player.hitbox()).grow(1).has_point(at):
		var help: String = PlayerStates.StateGraph.HELP[player.state] if player.state < PlayerStates.StateGraph.HELP.size() else ""
		out.append("Player - %s" % help)
	for e in ents:
		if out.size() >= 4:
			break
		var hit: bool = Rect2(e.rect).grow(1).has_point(at) or Rect2(e.touch_rect()).grow(1).has_point(at)
		for b in e.damage_boxes():
			hit = hit or Rect2(b).grow(1).has_point(at)
		if hit and not e is E.Building and not e is E.SpawnMarker:
			out.append(e.describe())
	return out

# Monsters tab (map screen): a monster counts as found once it is on screen, and every kill is counted.
func saw_enemy(t: String) -> void:
	if adventure() and not Game.adv.seen.has(t):
		Game.adv.seen.append(t)
func killed_enemy(t: String) -> void:
	if adventure():
		saw_enemy(t)
		Game.adv.kills[t] = int(Game.adv.kills.get(t, 0)) + 1
# The camera's view in room pixels.
func view_rect() -> Rect2:
	return Rect2(cam.position - VIEW / 2.0, VIEW) if cam != null else Rect2(bounds)

# Add to the F3 recap: how often (or how long) a cause changed stamina, and by how much in all.
func _tally(why: String, delta: float, amount: float) -> void:
	var t: Array = stamina_totals.get(why, [0.0, 0.0])
	stamina_totals[why] = [t[0] + amount, t[1] + delta]

# Remember a one-off stamina change and its cause, for the F3 stamina panel (last few only).
func stamina_event(why: String, delta: float) -> void:
	_tally(why, delta, 1.0)
	stamina_log.push_front([time, why, delta])
	if stamina_log.size() > 10:
		stamina_log.pop_back()

# Restore adventure stamina to the capacity determined by the current block count.
func refill_stamina() -> void:
	Game.play_sfx("refill")
	if adventure():
		var was: float = Game.adv.stamina
		Adventure.refill_stamina(Game.adv)
		stamina_event("stamina orb (refill)", Game.adv.stamina - was)

# Unlock an adventure move once and save progress so it remains available after a room change.
func grant_ability(a: String) -> void:
	Game.play_sfx("unlock")
	if adventure() and not Game.adv.abilities.has(a):
		Game.adv.abilities.append(a)
		_save_run()

# Copy room-owned counters and persistent object IDs into Game.adv before writing the save file.
func _save_run() -> void:
	if not adventure():
		return
	Game.adv.deaths = deaths
	Game.adv.time = time
	Game.adv.stars = collected.keys()
	Game.adv.broken = broken.keys()
	Game.save_adventure()

# ---------------- collision queries (used by player + entities) ----------------
# Find a tile or solid object overlapping a pixel rectangle; outside-room cells also consult neighbors.
# Collision reads numeric grid cells and entity rectangles, never the decorative background pixels.
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
	for c in _col_span(solid_cols, r):
		for s in solid_cols[c]:
			if s.collidable and s != ignore and not (skip_dream and s.dream) and s.rect.intersects(r):
				return s
	for s in loose_solids:
		if s.collidable and s != ignore and not (skip_dream and s.dream) and s.rect.intersects(r):
			return s
	return null

# Tile (x, y) in this room's coordinates, outside it: rock in a neighbouring room? No room there = open.
# Check neighboring room tiles outside local bounds, accounting for overlapping irregular room layouts.
func _near_solid(x: int, y: int) -> bool:
	for nr in near_rooms:
		var rr: Rect2i = nr[0]
		if rr.has_point(Vector2i(x, y)):
			return (nr[1][y - rr.position.y] as String).unicode_at(x - rr.position.x) == 49
	return false

# After a room change or door arrival: if the body overlaps rock, move it to the nearest free spot (16px at most)
# whose centre is inside a room. Back across the edge is allowed: an object the player couldn't see from there
# (a breakable wall) then simply blocks the way.
# Search a short distance for free space after arrival so a room or door transition cannot embed the player in rock.
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

# Find one-way platforms entered by a proposed movement, excluding those already overlapping the body.
func collide_jumpthru_outside(r_at: Rect2i, r_now: Rect2i):
	for c in _col_span(jumpthru_cols, r_at):
		for j in jumpthru_cols[c]:
			if j.collidable and j.rect.intersects(r_at) and not j.rect.intersects(r_now):
				return j
	return null

# Find any enabled one-way platform overlapping the supplied pixel rectangle.
func collide_jumpthru(r: Rect2i):
	for c in _col_span(jumpthru_cols, r):
		for j in jumpthru_cols[c]:
			if j.collidable and j.rect.intersects(r):
				return j
	return null

# Find an enabled dream block overlapping the supplied rectangle.
func collide_dream(r: Rect2i):
	for d in dreams:
		if d.collidable and d.rect.intersects(r):
			return d
	return null

# Check lethal spike surfaces against the supplied damage box.
func touching_spikes(r: Rect2i) -> bool:
	for s in spikes:
		if s.collidable and s.rect.intersects(r):
			return true
	return false

# Check object contacts using the appropriate interaction/damage shapes, then call each object reaction.
func player_touch(p) -> void:
	door_near = null
	var hr: Rect2i = p.hurt_rect()
	var dr: Rect2i = p.damage_rect()
	var near := hr.merge(dr).grow(16)  # cheap reject first: no touch_rect reaches more than 8 px past its entity
	for e in touchables:
		if p.dead or done:
			return
		if e.collidable and e.rect.intersects(near) and e.touch_rect().intersects(dr if e.hurts() else hr):
			e.touch(p)

# ---------------- events ----------------
# Request brief hit-stop: physics waits while the scene can still display the impact.
func freeze_for(t: float) -> void:
	freeze = maxf(freeze, t)

# Request camera shake if the player has enabled that visual effect.
func shake_dir(_dir: Vector2, t: float) -> void:
	if Game.settings.shake:
		shake_t = maxf(shake_t, t)

# Create short-lived particles leaving a surface in a given direction.
func dust(at: Vector2, dir: Vector2, n: int, col := Color(1, 1, 1, 0.7)) -> void:
	for i in n:
		var v := dir.rotated(randf_range(-0.6, 0.6)) * randf_range(10, 40)
		parts.append([at + Vector2(randf_range(-2, 2), randf_range(-2, 2)), v, randf_range(0.2, 0.4), col])

# Create a radial group of colored particles for pickups and impacts.
func burst(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		parts.append([at, Vector2.RIGHT.rotated(TAU * i / n) * 60, 0.4, col])

# Record a fading player silhouette at the current pose for fast-movement effects.
func add_trail(p) -> void:
	trails.append([Rect2(p.hitbox()), p.hair_color(), 0.35])

# Every hit is a death (a respawn); stamina has nothing to do with it, and the respawn refills the base bar.
# Count the death and start the short respawn delay.
func on_player_death(p, _dir: Vector2) -> void:
	deaths += 1
	respawn_timer = 0.6
	burst(p.center(), p.hair_color(), 12)
	shake_t = 0.3 if Game.settings.shake else 0.0

# Rebuild the room (or go back to the last safe one) with the base stamina bar full; extra blocks keep their stamina.
func respawn() -> void:
	Game.play_sfx("respawn")
	if adventure() and spawn_room != room:  # this room has no safe point: back to the last one
		enter_room(spawn_room, spawn)
	_build()
	if adventure() and Game.adv.stamina < Adventure.BASE_STAMINA:
		stamina_event("respawn (base refill)", Adventure.BASE_STAMINA - Game.adv.stamina)
		Game.adv.stamina = Adventure.BASE_STAMINA

# Bank a following star, persist its ID and show its collection burst.
func collect_berry(b) -> void:
	Game.play_sfx("pickup")
	collected[b.id] = true
	_save_run()
	burst(b.pos, Color("e03c3c"), 10)

# Finish the run once, store its result and open the completion panel.
func complete() -> void:
	if done:
		return
	Game.play_sfx("complete")
	done = true
	if adventure():
		Game.adv.done = true
		_save_run()
	elif not Game.playtest:
		Game.submit_record(level_id, time, deaths, collected.size(), total_berries)
	_show_complete()

# ---------------- loop ----------------
# Handle gameplay shortcuts only after interface controls had a chance to consume the event.
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
	elif map_view == null and (event.is_action_pressed("state_debug") or (state_panel != null and event.is_action_pressed("pause"))):
		get_viewport().set_input_as_handled()
		_toggle_state()
		return
	elif event.is_action_pressed("stamina_debug"):
		get_viewport().set_input_as_handled()
		_toggle_stamina_panel()
		return
	elif event.is_action_pressed("hitboxes"):
		get_viewport().set_input_as_handled()
		Game.settings.hitboxes = not Game.settings.hitboxes
		Game.save_settings()
		if debug_panel != null:
			debug_panel.hitbox_btn.set_pressed_no_signal(Game.settings.hitboxes)
		return
	elif event.is_action_pressed("assist") and map_view == null:
		get_viewport().set_input_as_handled()
		_open_assist()
		return
	# handled here (not in _physics_process) so the options screen can swallow Esc first
	if event.is_action_pressed("pause") and not done and not (overlay is OptionsPanel):
		get_viewport().set_input_as_handled()
		_set_paused(not paused)

# Advance a fixed simulation tick unless paused; update player before entities, then particles and camera.
# Order matters: player movement produces contacts/transitions before entities react to the new position.
# A fixed DT preserves the original movement feel; the assist speed scales simulated time deliberately.
func _physics_process(_delta: float) -> void:
	cam_prev = cam_now  # no tick (paused, frozen) = no motion to interpolate
	player.prev_pos = player.pos
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
			respawn()
	else:
		player.update(dt)
		after_player_move()
		update_stamina(dt)
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
	cam_now = cam_pos + off
	cam.position = cam_now.round()
	mask_a = move_toward(mask_a, 1.0 if _cam_settled() else 0.0, dt * 4.0)
	note_t -= dt
	note_label.visible = note_t > 0 and map_view == null
	hud.queue_redraw()
	_redraw()

# The camera has arrived along every axis on which the room is smaller than the view (so it is centred there).
func _cam_settled() -> bool:
	var d: Vector2 = (_clamp_cam(player.camera_target()) - cam_pos).abs()
	return (bounds.size.x >= VIEW.x or d.x < 1.0) and (bounds.size.y >= VIEW.y or d.y < 1.0)

# Black over the parts of the view outside this room (they only show when the room is smaller than the view).
func _draw_room_mask(ci: CanvasItem) -> void:
	if mask_a <= 0.0:
		return
	var v := Rect2(cam.position - VIEW / 2.0, VIEW).grow(2)
	var b := Rect2(bounds)
	var c := Color(0, 0, 0, mask_a)
	ci.draw_rect(Rect2(v.position.x, v.position.y, v.size.x, b.position.y - v.position.y), c)  # above
	ci.draw_rect(Rect2(v.position.x, b.end.y, v.size.x, v.end.y - b.end.y), c)  # below
	ci.draw_rect(Rect2(v.position.x, b.position.y, b.position.x - v.position.x, b.size.y), c)  # left
	ci.draw_rect(Rect2(b.end.x, b.position.y, v.end.x - b.end.x, b.size.y), c)  # right

# Keep the camera within the room limits while handling rooms smaller than the view.
func _clamp_cam(t: Vector2) -> Vector2:
	var half := VIEW / 2.0
	var b := Rect2(bounds)
	var x := b.get_center().x if b.size.x <= VIEW.x else clampf(t.x, half.x, b.end.x - half.x)
	var y := b.get_center().y if b.size.y <= VIEW.y else clampf(t.y, half.y, b.end.y - half.y)
	return Vector2(x, y)

# Where the view would settle with the camera in room area (as _clamp_cam does for this room).
# Compute a stable room-relative view for drawing backgrounds during camera transitions.
func _rest_view(view: Rect2, area: Rect2) -> Rect2:
	var x := area.get_center().x - VIEW.x / 2 if area.size.x <= VIEW.x else clampf(view.position.x, area.position.x, area.end.x - VIEW.x)
	var y := area.get_center().y - VIEW.y / 2 if area.size.y <= VIEW.y else clampf(view.position.y, area.position.y, area.end.y - VIEW.y)
	return Rect2(x, y, VIEW.x, VIEW.y)

# Paint room scenery, including visible portions of adjacent rooms during a transition.
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

# Draw active and leaving-room objects, movement trails and particles over retained terrain.
func _draw() -> void:
	# Also follow redraws requested directly by tools or benchmark subclasses.
	background.queue_redraw()
	var view := Rect2(cam.position - VIEW / 2.0, VIEW)
	var cull := Rect2i(view.position.floor(), view.size.ceil()).grow(1)
	var over: Array = []  # water and waterfalls draw over the player
	for e in ents:  # buildings first: they are backdrops, whatever their order in the level file
		if e is E.Building and e.vis_rect().intersects(cull):
			e.draw(self)
	for e in ents:
		if e is E.Building:
			continue
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
# Overlay the actual collision and damage geometry for diagnosing gameplay contacts.
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
# Schedule the existing menu overlay for deletion and drop the reference to it.
func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null

# Build the common darkened overlay and centred vertical container used by in-game menus.
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

# Toggle simulation pause and construct or remove the pause menu.
func _set_paused(v: bool) -> void:
	Game.play_sfx("ui")
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
	box.add_child(Game.button(_exit_label(), _exit))
	# the debug tools, top right: each closes the menu and opens its panel
	var tools := HBoxContainer.new()
	tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tools.offset_left = -12
	tools.offset_right = -12
	tools.offset_top = 12
	tools.add_theme_constant_override("separation", 8)
	overlay.add_child(tools)
	for t in [["Tuning", "debug", _toggle_debug, func(): return debug_panel], ["State", "state_debug", _toggle_state, func(): return state_panel],
			["Stamina", "stamina_debug", _toggle_stamina_panel, func(): return stamina_panel]]:
		var b := Game.button("%s (%s)" % [t[0], Game.key_name(t[1])], func():
			_set_paused(false)
			if t[3].call() == null:
				t[2].call())
		b.add_theme_font_size_override("font_size", 18)
		tools.add_child(b)
	resume.grab_focus()

# Create or close the movement-tuning developer panel.
func _toggle_debug() -> void:
	if debug_panel != null:
		debug_panel.queue_free()
		debug_panel = null
	else:
		debug_panel = DebugPanel.new(self)
		ui.add_child(debug_panel)

# Create or close the state machine / live variables panel (F4).
func _toggle_state() -> void:
	if state_panel != null:
		state_panel.queue_free()
		state_panel = null
	else:
		state_panel = DebugPanel.new(self, "state")
		ui.add_child(state_panel)

# Create or close the stamina panel (F3).
func _toggle_stamina_panel() -> void:
	if stamina_panel != null:
		stamina_panel.queue_free()
		stamina_panel = null
	else:
		stamina_panel = load("res://scripts/stamina_panel.gd").new()
		stamina_panel.world = self
		ui.add_child(stamina_panel)

# Create or close the paused map overlay and hide the normal HUD while viewing it.
func _toggle_map() -> void:
	if map_view != null:
		map_view.queue_free()
		map_view = null
	else:
		map_view = MapView.new(self)
		ui.add_child(map_view)
	hud.visible = map_view == null

# Replace the pause overlay with settings, reconnecting its close signal to the owning screen.
func _open_options() -> void:
	_clear_overlay()
	overlay = OptionsPanel.new()
	ui.add_child(overlay)
	overlay.closed.connect(func(): _set_paused(true))

# Assist Mode (F12): pauses the game behind its own page; closing it resumes.
# Open the assist settings overlay while preserving the World beneath it.
func _open_assist() -> void:
	paused = true
	_clear_overlay()
	overlay = OptionsPanel.new()
	overlay.assist_page = true
	ui.add_child(overlay)
	overlay.closed.connect(func():
		overlay = null
		paused = false)

# Reset standalone level progress and rebuild its starting state.
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
	snap_interp()

# Choose a return-button label appropriate to adventure or editor playtesting.
func _exit_label() -> String:
	return "Back to Editor" if Game.playtest else ("Back to World Editor" if Game.adv_temp and adventure() else "Exit to Menu")

# Leave gameplay through the correct menu/editor route, saving adventure progress when appropriate.
func _exit() -> void:
	_save_run()
	if Game.playtest:
		Game.goto("editor")
	elif Game.adv_temp and adventure():
		Game.goto("world_editor")
	else:
		Game.goto("menu")

# Build the result panel, star count and available restart/return actions.
func _show_complete() -> void:
	var box := _panel("Adventure Complete!" if adventure() else "Level Complete!")
	box.add_child(Game.label("Time  %s" % Game.fmt_time(time)))
	box.add_child(Game.label("Deaths  %d" % deaths))
	box.add_child(Game.label("Stars  %d / %d" % [collected.size(), total_berries]))
	if not Game.playtest and not adventure():
		var rec := Game.get_record(level_id)
		box.add_child(Game.label("Best  %s" % Game.fmt_time(rec.get("best_time", time)), 20))
	var first: Button = Game.button("Play Again", _restart) if not adventure() else Game.button(_exit_label(), _exit)
	box.add_child(first)
	if not adventure():
		box.add_child(Game.button(_exit_label(), _exit))
	first.grab_focus()

# Release presentation state and stop this World music when it is actually leaving the screen.
func _exit_tree() -> void:
	if is_instance_valid(Game.music_engine) and (not is_instance_valid(Game.main) or Game.main.get_child_count() == 0 or Game.main.get_child(Game.main.get_child_count() - 1) == self):
		Game.music_engine.set_muffled(false)
		Game.music_engine.stop()
