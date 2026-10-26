extends Control
# Paused map overlay, with a second tab showing the enemy catalogue.
# Each room becomes a tiny texture with one image pixel per terrain tile.
# The map combines room-local terrain with each room's world offset, then fits it onto the screen.
# zoom and pan affect the map view only; they do not move the player or rearrange rooms.
# Reading help: docs/CODE_GUIDE.md.

# Full-screen map (M). The world pauses while it is open. Owned by world.gd.
# One level: that level. Adventure: every visited room on the world grid (unvisited rooms stay hidden).
# Wheel zooms, drag pans, M / Esc closes. Tabs: Map (always first) and Monsters; L1 / R1 or Q / E switch.

const E := preload("res://scripts/entities.gd")
const Adventure := preload("res://scripts/adventure.gd")
const T := 8
const Bestiary := preload("res://scripts/bestiary.gd")
const TABS := ["Map", "Monsters"]

var world
var layers: Array = []  # [world-pixel Rect2, ImageTexture, is current room]
var area := Rect2()  # union of layers, world pixels
var zoom := 1.0  # extra zoom on top of fit-to-screen
var pan := Vector2.ZERO
var dragging := false
var tab := 0
var tab_buttons: Array[Button] = []
var bestiary: Control

# Remember the World being viewed; the map reads it without advancing gameplay.
func _init(w) -> void:
	world = w

const OPEN := Color("3a5494")  # the player fits here (inside an open 2x2)
const NARROW := Color(0.23, 0.33, 0.58, 0.4)  # open but too tight to enter
const EDGE := Color("8d97d6")  # rock bordering open space

# Build a one-pixel-per-tile thumbnail showing open space, narrow passages and bordering rock.
static func terrain(lvl: Dictionary) -> ImageTexture:
	# 1 pixel per tile, built once per opening (nothing changes while paused). Rock stays transparent (room colour).
	var w: int = lvl.w
	var h: int = lvl.h
	var open := PackedByteArray()
	open.resize(w * h)
	var tiles: Array = lvl.tiles
	for y in h:
		var row: String = tiles[y]
		for x in w:
			open[y * w + x] = 1 if row.unicode_at(x) != 49 else 0
	var fits := PackedByteArray()  # open tiles inside a fully open 2x2
	fits.resize(w * h)
	for y in h - 1:
		for x in w - 1:
			var i := y * w + x
			if open[i] and open[i + 1] and open[i + w] and open[i + w + 1]:
				fits[i] = 1; fits[i + 1] = 1; fits[i + w] = 1; fits[i + w + 1] = 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var i := y * w + x
			if open[i]:
				img.set_pixel(x, y, OPEN if fits[i] else NARROW)
			elif (x > 0 and open[i - 1]) or (x + 1 < w and open[i + 1]) or (y > 0 and open[i - w]) or (y + 1 < h and open[i + w]):
				img.set_pixel(x, y, EDGE)
	return ImageTexture.create_from_image(img)

# Prepare visited-room thumbnails and create the Map/Monsters tab controls.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if world.adventure():
		for name in Game.adv.visited:
			if Game.adv_world.rooms.has(name):
				var r: Dictionary = Game.adv_world.rooms[name]
				layers.append([Rect2(Adventure.room_rect(r)), terrain(r.level), name == world.room])
	else:
		layers.append([Rect2(world.bounds), terrain(world.data), true])
	area = layers[0][0]
	for l in layers:
		area = area.merge(l[0])
	bestiary = Bestiary.new()
	if world.adventure():
		bestiary.run = Game.adv
	bestiary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bestiary.offset_top = 70
	bestiary.offset_bottom = -40
	add_child(bestiary)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-300, 12)
	bar.custom_minimum_size = Vector2(280, 0)
	bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(bar)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()  # tappable on touchscreens
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_tab.bind(i))
		bar.add_child(b)
		tab_buttons.append(b)
	_set_tab(0)

# Select a tab and synchronize buttons, content visibility and drawing.
func _set_tab(i: int) -> void:
	tab = i
	for j in tab_buttons.size():
		tab_buttons[j].button_pressed = j == i
		tab_buttons[j].modulate = Color(1, 1, 1, 1.0 if j == i else 0.45)
	bestiary.visible = i == 1
	queue_redraw()

# Switch tabs with keyboard or gamepad shoulder buttons and consume the handled event.
func _input(event: InputEvent) -> void:
	var step := 0
	if event is InputEventJoypadButton and event.pressed:
		step = -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else 0)
	elif event is InputEventKey and event.pressed and not event.echo:
		step = -1 if event.keycode == KEY_Q else (1 if event.keycode == KEY_E else 0)
	if step != 0:
		_set_tab(posmod(tab + step, TABS.size()))
		get_viewport().set_input_as_handled()

# world pixels -> screen
# Build the transform from world pixels to fitted, zoomed and panned map-screen coordinates.
func _xform() -> Transform2D:
	var avail := size - Vector2(80, 120)
	var s := minf(avail.x / area.size.x, avail.y / area.size.y) * zoom
	var origin := (size - area.size * s) / 2.0 + Vector2(0, 20) + pan - area.position * s
	return Transform2D(0, Vector2(s, s), 0, origin)

# Draw the current tab background and, for Map, terrain, objects, player and camera markers.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06, 0.92))
	var font := get_theme_default_font()
	var hint := "L1 / R1 (Q / E) tabs · %s / Esc close" % Game.key_name("map")
	if tab == 1:
		draw_string(font, Vector2(24, 36), "Monsters", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		draw_string(font, Vector2(24, size.y - 18), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.8))
		return
	var xf := _xform()
	var s := xf.get_scale().x
	for l in layers:
		var r := Rect2(xf * l[0].position, l[0].size * s)
		draw_rect(r, Color("1a1e33") if l[2] else Color("121526"))
		draw_texture_rect(l[1], r, false)
		draw_rect(r, Color(1, 1, 1, 0.5 if l[2] else 0.15), false, 1.0)
	# entities, spawn, camera view and player of the current room
	var o: Vector2 = world.room_origin
	for e in world.ents:
		var col: Color = E.TYPES[e.d.t][2]
		if e is E.Star:
			col = col if e.collidable else Color(0.4, 0.4, 0.4)
		elif not e.collidable:
			col = Color(col, 0.35)
		var r := Rect2(xf * (o + Vector2(e.rect.position)), Vector2(e.rect.size) * s)
		if e.solid or e.jumpthru:
			draw_rect(r, col.lightened(0.2) if col.v < 0.3 else col)
		else:
			draw_circle(r.get_center(), maxf(2.0, s * 3), col)
	draw_rect(Rect2(xf * (o + world.spawn - Vector2(4, 8)), Vector2(8, 8) * s), Color.WHITE, false, 1.0)
	var view := Rect2(o + world.cam.position - world.VIEW / 2.0, world.VIEW)
	draw_rect(Rect2(xf * view.position, view.size * s), Color(1, 1, 1, 0.6), false, 2.0)
	if not world.player.dead:
		var pp: Vector2 = xf * (o + world.player.center())
		draw_circle(pp, maxf(3.0, s * 4), world.player.hair_color())
		draw_arc(pp, maxf(3.0, s * 4) + 2, 0, TAU, 16, Color.WHITE, 1.5)
	var title := "Map — %s" % world.data.get("name", "")
	if world.adventure():
		title += "   (%d / %d rooms explored)" % [Game.adv.visited.size(), Game.adv_world.rooms.size()]
	else:
		title += "  (%dx%d)" % [world.gw, world.gh]
	draw_string(font, Vector2(24, 36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(24, size.y - 18), "Wheel zoom · drag pan · " + hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.8))

# Zoom around the mouse position or drag to pan the map without moving the game camera.
func _gui_input(event: InputEvent) -> void:
	if tab != 0:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before: Vector2 = _xform().affine_inverse() * event.position
		zoom = clampf(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.5, 20.0)
		pan += event.position - _xform() * before  # keep the point under the cursor fixed
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		dragging = event.pressed
	elif event is InputEventMouseMotion and dragging:
		pan += event.relative
		queue_redraw()
