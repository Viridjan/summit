extends Control
# Full-screen map (M). The world pauses while it is open. Owned by world.gd.
# One level: that level. Adventure: every visited room on the world grid (unvisited rooms stay hidden).
# Wheel zooms, drag pans, M / Esc closes.

const E := preload("res://scripts/entities.gd")
const Adventure := preload("res://scripts/adventure.gd")
const T := 8

var world
var layers: Array = []  # [world-pixel Rect2, ImageTexture, is current room]
var area := Rect2()  # union of layers, world pixels
var zoom := 1.0  # extra zoom on top of fit-to-screen
var pan := Vector2.ZERO
var dragging := false

func _init(w) -> void:
	world = w

static func terrain(lvl: Dictionary) -> ImageTexture:
	# 1 pixel per tile, built once per opening (nothing changes while paused)
	var img := Image.create(lvl.w, lvl.h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# rock is drawn only where it borders open space, so overlapping room boxes don't hide each other
	var tiles: Array = lvl.tiles
	for y in lvl.h:
		var row: String = tiles[y]
		var up: String = tiles[y - 1] if y > 0 else ""
		var dn: String = tiles[y + 1] if y + 1 < lvl.h else ""
		for x in lvl.w:
			if row.unicode_at(x) != 49:
				continue
			var edge: bool = (x > 0 and row.unicode_at(x - 1) != 49) or (x + 1 < lvl.w and row.unicode_at(x + 1) != 49) \
				or (up != "" and up.unicode_at(x) != 49) or (dn != "" and dn.unicode_at(x) != 49)
			if edge:
				img.set_pixel(x, y, Color("5a64a0"))
	return ImageTexture.create_from_image(img)

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

# world pixels -> screen
func _xform() -> Transform2D:
	var avail := size - Vector2(80, 120)
	var s := minf(avail.x / area.size.x, avail.y / area.size.y) * zoom
	var origin := (size - area.size * s) / 2.0 + Vector2(0, 20) + pan - area.position * s
	return Transform2D(0, Vector2(s, s), 0, origin)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06, 0.92))
	var xf := _xform()
	var s := xf.get_scale().x
	for l in layers:
		var r := Rect2(xf * l[0].position, l[0].size * s)
		draw_rect(r, Color("262c4a") if l[2] else Color("1b2036"))
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
	var font := get_theme_default_font()
	var title := "Map — %s" % world.data.get("name", "")
	if world.adventure():
		title += "   (%d / %d rooms explored)" % [Game.adv.visited.size(), Game.adv_world.rooms.size()]
	else:
		title += "  (%dx%d)" % [world.gw, world.gh]
	draw_string(font, Vector2(24, 36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(24, size.y - 18), "Wheel zoom · drag pan · %s / Esc close" % Game.key_name("map"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.8))

func _gui_input(event: InputEvent) -> void:
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
