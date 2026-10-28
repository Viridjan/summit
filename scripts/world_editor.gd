extends Control
# Arranges room files on the larger adventure map, rather than editing individual tiles.
# world.json stores room names and tile offsets; each room has its own level JSON file.
# Screen pixels are converted to map tiles for dragging; room origins always snap to whole tiles.
# Expensive overlap and passage checks are cached after edits instead of repeated during drawing.
# Changing this layout writes project files; room editing itself is delegated to editor.gd.
# Reading help: docs/CODE_GUIDE.md.

# World editor (main menu > World Editor, only when run from source): places adventure rooms on the world grid.
# Rooms are ordinary level files in the world folder (res://worlds/story/); world.json stores where each one sits.
# Drag a room to move it (snaps to tiles); where two rooms touch, matching open tiles become passages (green).
# Overlapping rooms are outlined red. Every change is saved straight away.
# Mouse: LMB select/drag room · RMB or MMB drag pan · wheel zoom.

const Adventure := preload("res://scripts/adventure.gd")
const E := preload("res://scripts/entities.gd")
const MapView := preload("res://scripts/map_view.gd")
const T := 8

var world: Dictionary
var thumbs := {}  # room name -> ImageTexture
var selected := ""
var zoom := 0.5  # screen pixels per tile
var pan := Vector2(320, 120)
var drag_room := ""
var drag_from := Vector2.ZERO  # mouse position in tiles when the drag started
var drag_pos0 := Vector2i.ZERO
var panning := false
var info: Label
var add_menu: MenuButton
var room_buttons: Array[Button] = []
var status: Label
var cache_bad := {}  # room -> true when its open space overlaps another room
var cache_ways := []  # Adventure.doorways(world)
var cache_links := []  # [from, to] world-pixel centres of linked doors

# Load the world layout, create room thumbnails and build the room-management controls.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Game.theme.duplicate()
	theme.default_font_size = 16
	world = Adventure.load_world(Game.world_path)
	for name in world.rooms:
		thumbs[name] = MapView.terrain(world.rooms[name].level)
	selected = world.start
	var side := PanelContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -260
	add_child(side)
	var box := VBoxContainer.new()
	side.add_child(box)
	box.add_child(Game.label("World Editor", 24))
	box.add_child(Game.button("+ Add empty room", func(): _add_index(0)))
	add_menu = MenuButton.new()
	add_menu.text = "+ Add copy of my level..."
	add_menu.flat = false
	add_menu.about_to_popup.connect(_fill_add_menu)
	add_menu.get_popup().index_pressed.connect(func(i: int): _add_index(i + 1))
	box.add_child(add_menu)
	box.add_child(HSeparator.new())
	info = Game.label("", 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	for b in [["Edit room", _edit], ["Playtest from here", _playtest], ["Set as start", _set_start], ["Remove from world", _remove]]:
		var btn := Game.button(b[0], b[1])
		box.add_child(btn)
		room_buttons.append(btn)
	box.add_child(HSeparator.new())
	box.add_child(Game.button("Menu", func(): Game.goto("menu")))
	status = Game.label("", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var help := Game.label("LMB drag room · RMB/MMB pan · wheel zoom\nGreen: passage between rooms · cyan: door link · red: overlap", 13)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)
	_recalc()
	_update_info()
	_fit.call_deferred()  # needs the laid-out size

# Zoom and pan so every room fits the canvas (left of the side panel).
# Choose zoom and pan so all rooms fit beside the side panel.
func _fit() -> void:
	if world.rooms.is_empty():
		return
	var area := Rect2()
	for name in world.rooms:
		var r: Dictionary = world.rooms[name]
		var rr := Rect2(Vector2(r.pos), Vector2(r.level.w, r.level.h))
		area = rr if area.size == Vector2.ZERO else area.merge(rr)
	var canvas := Vector2(size.x - 260, size.y)
	zoom = clampf(minf((canvas.x - 80) / area.size.x, (canvas.y - 80) / area.size.y), 0.1, 8.0)
	pan = (canvas - area.size * zoom) / 2.0 - area.position * zoom
	queue_redraw()

# Overlaps, passages and door links are slow on big worlds: computed after changes, not every frame.
# Recompute overlap warnings, connecting passages and explicit door links after layout changes.
func _recalc() -> void:
	cache_bad = {}
	for pair in Adventure.overlaps(world):
		cache_bad[pair[0]] = true
		cache_bad[pair[1]] = true
	cache_ways = Adventure.doorways(world)
	cache_links = []
	var doors := {}  # "room:id" -> world-pixel centre
	for name in world.rooms:
		var r: Dictionary = world.rooms[name]
		for e in r.level.entities:
			if e.t in E.DOOR_TYPES:
				doors[name + ":" + str(e.get("id", ""))] = [name, Vector2(r.pos * T) + Vector2(float(e.x), float(e.y)) + Vector2(float(e.get("w", T)), float(e.get("h", T))) / 2.0]
	for key in doors:
		var name: String = doors[key][0]
		for e in world.rooms[name].level.entities:
			if e.t in E.DOOR_TYPES and name + ":" + str(e.get("id", "")) == key:
				var to: String = str(e.get("to", ""))
				var tk := to if to.contains(":") else name + ":" + to
				if doors.has(tk):
					cache_links.append([doors[key][1], doors[tk][1]])

# Write world.json and show whether the project location accepted the save.
func _save() -> void:
	status.text = "Saved" if Adventure.save_world(Game.world_path, world) else "Save failed (res:// is read-only here)"

# world tiles <-> screen
# Convert world-map tile coordinates into screen pixels using zoom and pan.
func to_screen(tile: Vector2) -> Vector2:
	return tile * zoom + pan

# Undo the map view transform so a screen click becomes a world-map tile position.
func to_tile(screen: Vector2) -> Vector2:
	return (screen - pan) / zoom

# Draw the grid, room thumbnails, passages, door links and selection/overlap outlines.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10102a"))
	# grid every 8 tiles
	var step := 8.0 * zoom
	if step >= 6:
		var o := Vector2(fposmod(pan.x, step), fposmod(pan.y, step))
		for x in range(int(size.x / step) + 2):
			draw_line(Vector2(o.x + x * step, 0), Vector2(o.x + x * step, size.y), Color(1, 1, 1, 0.04))
		for y in range(int(size.y / step) + 2):
			draw_line(Vector2(0, o.y + y * step), Vector2(size.x, o.y + y * step), Color(1, 1, 1, 0.04))
	var bad := cache_bad
	var font := get_theme_default_font()
	var named := {}  # region name -> [colour, screen rect of its rooms]
	for name in world.rooms:
		var r: Dictionary = world.rooms[name]
		var rect := Rect2(to_screen(Vector2(r.pos)), Vector2(r.level.w, r.level.h) * zoom)
		var g := Adventure.region_of(world, name)
		draw_rect(rect, Color("1e2442") if name == selected else Color("121526"))
		draw_texture_rect(thumbs[name], rect, false)
		if not g.is_empty():  # rooms tinted by region, over the thumbnail
			draw_rect(rect, Color(g.color, 0.35))
			named[g.name] = [g.color, named[g.name][1].merge(rect) if named.has(g.name) else rect]
		var edge := Color.RED if bad.has(name) else (Color.WHITE if name == selected else (Color(g.color, 0.8) if not g.is_empty() else Color(1, 1, 1, 0.3)))
		draw_rect(rect, edge, false, 2.0 if name == selected or bad.has(name) else 1.0)
		var label: String = ("* " if name == world.start else "") + name
		draw_string(font, rect.position + Vector2(4, 16), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 14, Color.WHITE)
	for n in named:  # region names, centred over each region
		var at: Vector2 = named[n][1].get_center() + Vector2(-font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x / 2.0, 8)
		draw_string_outline(font, at, n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.85))
		draw_string(font, at, n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, named[n][0].lightened(0.35))
	for seg in cache_ways:
		draw_line(to_screen(seg[0] / T), to_screen(seg[1] / T), Color("4ee05a"), 3.0)
	for l in cache_links:  # doors: cyan line from each door to where it leads
		draw_line(to_screen(l[0] / T), to_screen(l[1] / T), Color(0.25, 0.88, 1.0, 0.7), 1.5)

# Select/drag rooms or pan/zoom the map, committing layout changes at the relevant gesture boundary.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before := to_tile(event.position)
		zoom = clampf(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.1, 8.0)
		pan += event.position - to_screen(before)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		panning = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := Adventure.room_at(world, to_tile(event.position) * T)
			if hit != "" and event.double_click:  # double click: edit that room
				selected = hit
				drag_room = ""
				_edit()
				return
			if hit != "":
				selected = hit
				drag_room = hit
				drag_from = to_tile(event.position)
				drag_pos0 = world.rooms[hit].pos
				_update_info()
		elif drag_room != "":
			if world.rooms[drag_room].pos != drag_pos0:
				_save()
				_recalc()
			drag_room = ""
		queue_redraw()
	elif event is InputEventMouseMotion:
		if panning:
			pan += event.relative
			queue_redraw()
		elif drag_room != "":
			move_room(drag_room, drag_pos0 + Vector2i((to_tile(event.position) - drag_from).round()))

# Change a room tile offset and request a visual update.
func move_room(name: String, pos: Vector2i) -> void:
	world.rooms[name].pos = pos
	queue_redraw()

# Update the selected room details and enable only actions that have a valid selection.
func _update_info() -> void:
	for b in room_buttons:
		b.disabled = selected == ""
	if selected == "":
		info.text = "No room selected" if not world.rooms.is_empty() else "No rooms yet: use + Add empty room"
		return
	var r: Dictionary = world.rooms[selected]
	var links := 0
	for seg in cache_ways:
		if Rect2(Adventure.room_rect(r)).grow(1).has_point((seg[0] + seg[1]) / 2.0):
			links += 1
	info.text = "%s\n\"%s\"  %dx%d tiles\nat %d, %d\npassage tiles: %d%s" % [selected, r.level.name, r.level.w, r.level.h, r.pos.x, r.pos.y, links, "\nstart room" if selected == world.start else ""]

# ---- add / remove ----
# List custom levels that can be copied into this world.
func _fill_add_menu() -> void:
	var p := add_menu.get_popup()
	p.clear()
	if Game.list_levels().is_empty():
		p.add_item("(no levels in Custom Levels yet)")
		p.set_item_disabled(0, true)
	for f in Game.list_levels():
		p.add_item("Copy of my level: " + f)

# Create an empty room or copy a selected custom level, then fit the view to the expanded layout.
func _add_index(i: int) -> void:
	var lvl: Dictionary
	var base := "room"
	if i == 0:
		lvl = Game.new_level("Room", 40, 23)
	else:
		base = Game.list_levels()[i - 1]
		lvl = Game.load_level(base)
		if lvl.is_empty():
			status.text = "Could not load level %s" % base
			return
	add_room(base, lvl, _free_spot(lvl))
	_fit()

# Right of the selected room (so it connects), sliding right past any room in the way.
# Search to the right of the selected room for a placement that avoids existing room bounds.
func _free_spot(lvl: Dictionary) -> Vector2i:
	if not world.rooms.has(selected):
		return Vector2i.ZERO
	var r: Dictionary = world.rooms[selected]
	var pos: Vector2i = r.pos + Vector2i(r.level.w, r.level.h - lvl.h)
	var hit := true
	while hit:
		hit = false
		for name in world.rooms:
			var o: Dictionary = world.rooms[name]
			if Rect2i(pos, Vector2i(lvl.w, lvl.h)).intersects(Rect2i(o.pos, Vector2i(o.level.w, o.level.h))):
				pos.x = o.pos.x + o.level.w
				hit = true
	return pos

# Copies the level into the adventure folder under a free name and places it.
# Choose a unique room filename, save its contents and add its tile position to the manifest.
func add_room(base: String, lvl: Dictionary, pos: Vector2i) -> String:
	var name := Game.file_safe(base)
	var n := 2
	while world.rooms.has(name) or FileAccess.file_exists(Game.world_path.get_base_dir() + "/" + name + ".json"):
		name = "%s_%d" % [Game.file_safe(base), n]
		n += 1
	if Game.save_level(lvl, Game.world_path.get_base_dir() + "/", name) == "":
		status.text = "Could not write the room file"
		return ""
	world.rooms[name] = {"pos": pos, "level": lvl}
	thumbs[name] = MapView.terrain(lvl)
	if world.start == "":
		world.start = name
	selected = name
	_save()
	_recalc()
	_update_info()
	queue_redraw()
	return name

# Remove a room from the layout while deliberately retaining its JSON file on disk.
func _remove() -> void:
	world.rooms.erase(selected)  # the room file stays in the folder
	thumbs.erase(selected)
	if world.start == selected:
		world.start = world.rooms.keys()[0] if not world.rooms.is_empty() else ""
	selected = ""
	_save()
	_recalc()
	_update_info()
	queue_redraw()

# Make the selected room the spawn room for new runs and save that manifest change.
func _set_start() -> void:
	world.start = selected
	_save()
	_update_info()
	queue_redraw()

# Pass a copy of the selected room and its fixed filename to the single-room editor.
func _edit() -> void:
	Game.editor_level = world.rooms[selected].level.duplicate(true)
	Game.editor_dir = Game.world_path.get_base_dir() + "/"
	Game.editor_file = selected
	Game.editor_return = "world_editor"
	Game.goto("editor")

# Start a temporary run from the selected room without changing normal adventure saves.
func _playtest() -> void:
	Game.playtest_adventure(world, selected)

# Return to the main menu when the cancel action was not consumed by a control.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Game.goto("menu")
