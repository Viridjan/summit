extends Node2D
# Gameplay screen: runs one level (Game.level), owns collision queries for the player.

const E := preload("res://scripts/entities.gd")
const Art := preload("res://scripts/art.gd")
const TileLayer := preload("res://scripts/tile_layer.gd")
const PlayerScript := preload("res://scripts/player.gd")
const OptionsPanel := preload("res://scripts/options.gd")
const DebugPanel := preload("res://scripts/debug_panel.gd")
const MapView := preload("res://scripts/map_view.gd")
const Adventure := preload("res://scripts/adventure.gd")
const T := 8
const DT := 1.0 / 60.0
const VIEW := Vector2(320, 180)

# Background is behind retained terrain; parent draws entities and overlays.
class Background extends Node2D:
	var screen: Node2D
	func _draw() -> void:
		screen._draw_background(self)

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
var collected := {}  # star id -> true, banked this run (adventure: run.stars, ids prefixed by room)
# Adventure only: current room of Game.adv_world and its top-left in world pixels.
var room := ""
var room_origin := Vector2.ZERO

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
var hud: Label
var note_label: Label  # design note under the player (entities.gd Note)
var note_t := 0.0
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
		deaths = Game.adv.deaths
		time = Game.adv.time
	cam = Camera2D.new()
	cam.zoom = Vector2(4, 4)
	add_child(cam)
	cam.make_current()
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(16, 10)
	hud.theme = Game.theme
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	ui.add_child(hud)
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
	tile_layer.setup(tiles, gw, gh)
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
	ents.clear(); solids.clear(); jumpthrus.clear(); dreams.clear(); spikes.clear(); touchables.clear()
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
	_check_room_exit()
	if pending_door != null:
		_go_door(pending_door)
	if door_block.has_area() and not door_block.intersects(player.hurt_rect()):
		door_block = Rect2i()

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
	else:
		enter_room(target_room, at)
	door_block = Rect2i(dr)

func enter_room(next: String, at = null) -> void:
	var global: Vector2 = room_origin + player.pos
	var old_origin := room_origin
	var went_up: bool = player.center().y < 0
	room = next
	room_origin = Vector2(Game.adv_world.rooms[room].pos * T)
	data = Game.adv_world.rooms[room].level
	tiles = []
	player.followers.clear()  # unbanked stars go back to their room
	_build(true)
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
	tile_layer.setup(tiles, gw, gh)
	cam_pos -= room_origin - old_origin  # keep the view where it was, then ease into the new room
	if map_view != null:
		_toggle_map()

func show_note(text: String) -> void:
	note_label.text = "Note: " + text
	note_t = 0.1

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
	Game.save_adventure()

# ---------------- collision queries (used by player + entities) ----------------
func collide_solid(r: Rect2i, ignore = null, skip_dream := false):
	var x0 := maxi(floori(r.position.x / float(T)), 0)
	var x1 := mini(floori((r.end.x - 1) / float(T)), gw - 1)
	var y0 := maxi(floori(r.position.y / float(T)), 0)
	var y1 := mini(floori((r.end.y - 1) / float(T)), gh - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if grid[y * gw + x] == 1:
				return "tile"
	for s in solids:
		if s.collidable and s != ignore and not (skip_dream and s.dream) and s.rect.intersects(r):
			return s
	return null

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
	for e in touchables:
		if p.dead or done:
			return
		if e.collidable and e.touch_rect().intersects(hr):
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

func on_player_death(p, _dir: Vector2) -> void:
	deaths += 1
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
	hud.text = ("%s    " % data.get("name", "") if adventure() else "") + "Stars %d/%d    Deaths %d    %s" % [collected.size(), total_berries, deaths, Game.fmt_time(time)]
	_redraw()

func _clamp_cam(t: Vector2) -> Vector2:
	var half := VIEW / 2.0
	var b := Rect2(bounds)
	var x := b.get_center().x if b.size.x <= VIEW.x else clampf(t.x, half.x, b.end.x - half.x)
	var y := b.get_center().y if b.size.y <= VIEW.y else clampf(t.y, half.y, b.end.y - half.y)
	return Vector2(x, y)

func _draw_background(ci: CanvasItem) -> void:
	var view := Rect2(cam.position - VIEW / 2.0, VIEW)
	Art.draw_background(ci, view, time)
	for s in snow:
		ci.draw_rect(Rect2((view.position + s).floor(), Vector2.ONE), Color(1, 1, 1, 0.35))

func _draw() -> void:
	# Also follow redraws requested directly by tools or benchmark subclasses.
	background.queue_redraw()
	var view := Rect2(cam.position - VIEW / 2.0, VIEW)
	var cull := Rect2i(view.position.floor(), view.size.ceil()).grow(1)
	for e in ents:
		if e.vis_rect().intersects(cull):  # offscreen entities still update, just don't draw
			e.draw(self)
	for t in trails:
		draw_rect(t[0], Color(t[1], minf(t[2] * 1.5, 0.6)))
	player.draw(self)
	for pt in parts:
		draw_rect(Rect2(pt[0].floor(), Vector2.ONE), Color(pt[3], clampf(pt[2] * 3, 0, 1)))

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
