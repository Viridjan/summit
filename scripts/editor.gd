extends Node2D
# Edits one room's tiles and placed objects; it does not run their gameplay behavior.
# level is the editable JSON-shaped dictionary; preview contains disposable drawable objects.
# Undo stores deep copies so later edits cannot accidentally alter an older snapshot.
# The camera turns screen mouse positions into world pixels; editing then snaps them to 8px tiles.
# Retained tile chunks redraw only when affected cells change; UI and object previews are separate.
# Reading help: docs/CODE_GUIDE.md.

# Level editor.
# LMB: paint tiles / place entity (drag to size blocks).  RMB: erase tile / delete entity.
# MMB or Space+drag: pan.  Wheel: zoom.  Ctrl+Z undo, Ctrl+S save, F5 playtest.
# Shift+drag: select an area; Ctrl+C / Ctrl+X copy or cut it, Ctrl+V pastes at the mouse (also in another room).

const E := preload("res://scripts/entities.gd")
const Art := preload("res://scripts/art.gd")
const TileLayer := preload("res://scripts/tile_layer.gd")
const T := 8
const MAX_UNDO := 60

# Background is behind retained terrain; parent draws entities and overlays.
# Separate drawing node kept behind cached terrain so changing objects do not force terrain redraws.
class Background extends Node2D:
	var screen: Node2D
	# Draw object previews, editing grid and the current placement/selection guides.
	func _draw() -> void:
		screen._draw_background(self)

var tile_layer: TileLayer
var background: Background

var level: Dictionary
var tool := "tile"
var cam: Camera2D
var preview: Array = []  # entity instances used only for drawing; index-aligned with level.entities
var undo_stack: Array = []
var saved_level: Dictionary  # last saved (or opened) state, to warn about unsaved changes
var dragging_paint := 0  # 0 none, 1 paint, -1 erase
var last_cell := Vector2i(-1, -1)
var rect_start = null  # Vector2i cell where a sized drag began
var zip_pending = null  # zip mover dict waiting for its target click
var sel_start = null  # Vector2i cell where a Shift+drag selection began
var sel := Rect2i()  # selected cells (Shift+drag); Ctrl+C / Ctrl+X copy or cut them
static var clip := {}  # {w, h, tiles: [String], entities: [Dictionary]}; kept across rooms
var panning := false
var space_down := false

var ui: CanvasLayer
var name_edit: LineEdit
var w_spin: SpinBox
var h_spin: SpinBox
var enemy_spin: SpinBox
var navigation_box: VBoxContainer
var navigation_dialog: ConfirmationDialog
var arrows: Array = []  # [{name, dir: Vector2i, at: Vector2 (room px)}]: connected rooms touching an edge
var status: Label
var load_menu: MenuButton
var tool_group := ButtonGroup.new()
var msg := ""
var msg_t := 0.0

# Invalidate object and background visuals after edits while terrain chunks redraw independently.
func _redraw() -> void:
	queue_redraw()
	if background != null:
		background.queue_redraw()

# Create background and chunked-terrain nodes behind object previews.
func _create_tile_layer() -> void:
	background = Background.new()
	background.screen = self
	background.z_index = -2
	add_child(background)
	tile_layer = TileLayer.new()
	tile_layer.z_index = -1
	add_child(tile_layer)

# Copy the editable level, centre its camera and build editing tools and preview objects.
func _ready() -> void:
	level = Game.editor_level.duplicate(true) if not Game.editor_level.is_empty() else Game.new_level()
	saved_level = level.duplicate(true)
	cam = Camera2D.new()
	cam.zoom = Vector2(3, 3)
	add_child(cam)
	cam.make_current()
	cam.position = Vector2(level.w * T, level.h * T) / 2.0
	_build_ui()
	_create_tile_layer()
	tile_layer.setup(level.tiles, level.w, level.h, level.get("environment", ""))
	_refresh()
	_frame_room()

# ---------------- UI ----------------
# Create the name/size controls, load/save actions, object palette and status bar.
func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Game.theme.duplicate()
	root.theme.default_font_size = 18
	ui.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var bar := HBoxContainer.new()
	top.add_child(bar)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(180, 0)
	name_edit.text = level.name
	name_edit.text_changed.connect(func(t: String): level.name = t)
	bar.add_child(_lbl("Name"))
	bar.add_child(name_edit)
	w_spin = _spin(10, 400, level.w)
	h_spin = _spin(6, 400, level.h)
	bar.add_child(_lbl("W"))
	bar.add_child(w_spin)
	bar.add_child(_lbl("H"))
	bar.add_child(h_spin)
	bar.add_child(_btn("Resize", _resize))
	bar.add_child(VSeparator.new())
	bar.add_child(_btn("New", _new))
	bar.add_child(_btn("Save", _save))
	load_menu = MenuButton.new()
	load_menu.text = "Load"
	load_menu.flat = false
	load_menu.about_to_popup.connect(_fill_load_menu)
	load_menu.get_popup().index_pressed.connect(_load_index)
	bar.add_child(load_menu)
	bar.add_child(_btn("Undo", _undo))
	bar.add_child(VSeparator.new())
	bar.add_child(_btn("Playtest", _playtest))
	bar.add_child(_btn("Menu" if Game.editor_return == "menu" else "World", _leave))

	var side := PanelContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	side.offset_top = 48
	side.offset_bottom = -32
	side.custom_minimum_size = Vector2(190, 0)
	root.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var tools := VBoxContainer.new()
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tools)
	tools.add_child(_lbl("Enemies (-1 = automatic)"))
	enemy_spin = _spin(-1, 1000, int(level.get("enemy_count", -1)))
	enemy_spin.tooltip_text = "Generated enemy budget when building; 0 disables population. Safe placement and peaceful regions still apply."
	enemy_spin.value_changed.connect(func(v: float): level.enemy_count = int(v))
	tools.add_child(enemy_spin)
	navigation_box = VBoxContainer.new()
	tools.add_child(navigation_box)
	_refresh_navigation()
	var groups := {}  # group -> [ids], in registry order (enemies sorted by family below)
	var order: Array = []
	for t in ["tile"] + E.TYPES.keys():
		var g := palette_group(t)
		if not groups.has(g):
			groups[g] = []
			order.append(g)
		groups[g].append(t)
	order.sort_custom(func(a, b): return GROUP_ORDER.find(a.get_slice(":", 0)) < GROUP_ORDER.find(b.get_slice(":", 0)) or (a.get_slice(":", 0) == b.get_slice(":", 0) and a < b))
	if groups.has("Enemies & bosses"):  # each enemy family together (original first), then the bosses
		var keys: Array = E.TYPES.keys()
		groups["Enemies & bosses"].sort_custom(func(a, b): return _enemy_key(a, keys) < _enemy_key(b, keys))
	for g in order:
		var box := VBoxContainer.new()
		var head := Button.new()  # click to fold/unfold the group
		head.text = "%s %s" % ["v" if g == "Terrain" else ">", g.replace(":", ": ")]
		head.flat = true
		head.focus_mode = Control.FOCUS_NONE
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_theme_color_override("font_color", Color("ffd34e"))
		box.visible = g == "Terrain"
		head.pressed.connect(func():
			box.visible = not box.visible
			head.text = ("v " if box.visible else "> ") + g.replace(":", ": "))
		tools.add_child(head)
		tools.add_child(box)
		var sub_box: VBoxContainer = null
		var sub_name := ""
		for t in groups[g]:
			var parent: VBoxContainer = box
			if g == "Enemies & bosses":  # one foldable subgroup per enemy family / boss
				if palette_subgroup(t) != sub_name:
					sub_name = palette_subgroup(t)
					sub_box = _fold(box, sub_name, Color("e6c27a"))
				parent = sub_box
			if t == "tile":
				_tool_button(parent, "tile", "Ground Tiles", Color("7d84c4"))
			elif rotations_of(t).is_empty() or rotations_of(t)[0] == t:  # one entry per rotatable family
				_tool_button(parent, t, E.TYPES[t][0].trim_suffix(" ^") if not rotations_of(t).is_empty() else E.TYPES[t][0], E.TYPES[t][2])

	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -32
	root.add_child(bottom)
	status = Label.new()
	bottom.add_child(status)

const GROUP_ORDER := ["Terrain", "Hazards", "Movement", "Pickups", "Doors & people", "Triggers", "Enemies & bosses", "Placeholders", "Other"]
# Palette section for a tool id: terrain pieces, hazards, movement gadgets, pickups, doors and people, and one section
# for every enemy and boss (registry order: each enemy family together, then the bosses and their arena pieces).
static func palette_group(t: String) -> String:
	if t == "note" or (E.TYPES.has(t) and E.TYPES[t][3] == E.Placeholder):  # stand-ins and design notes
		return "Placeholders"
	if t.begins_with("enemy") or t.begins_with("boss") or t.begins_with("ape") or t in ["auto_walk", "vent_plug"]:
		return "Enemies & bosses"
	if t in ["tile", "jumpthru", "crumble", "falling", "breakable", "breakwall", "waterfall", "water", "acid"]:
		return "Terrain"
	if t.begins_with("spikes") or t in ["rockfall"]:
		return "Hazards"
	if t.begins_with("spring") or t.begins_with("booster") or t in ["refill", "refill_two", "bumper", "feather", "dream", "zip"]:
		return "Movement"
	if t in ["camera_zone"]:
		return "Triggers"
	if t.begins_with("ability") or t.begins_with("stamina") or t in ["strawberry", "goal", "energy_fragment"]:
		return "Pickups"
	if t in ["spawn", "door", "house_door", "building", "note", "island_prop", "discovery_npc"] or t.begins_with("village"):
		return "Doors & people"
	return "Other"

# A folded sub-header inside a palette group; returns the box its buttons go in.
func _fold(parent: Control, title: String, col: Color) -> VBoxContainer:
	var head := Button.new()
	head.text = "   > " + title
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_color_override("font_color", col)
	var box := VBoxContainer.new()
	box.visible = false
	head.pressed.connect(func():
		box.visible = not box.visible
		head.text = ("   v " if box.visible else "   > ") + title)
	parent.add_child(head)
	parent.add_child(box)
	return box

# Subgroup inside Enemies & bosses: the enemy family's name (from its original type's label), or the boss.
static func palette_subgroup(t: String) -> String:
	if t.begins_with("enemy_"):
		var fam := "enemy_" + t.get_slice("_", 1)
		return str(E.TYPES[fam][0]).get_slice(" · ", 0) if E.TYPES.has(fam) else fam
	if t in ["boss_ape", "ape_chase", "ape_trunk"]:
		return "Ape"
	if t in ["boss_guardian", "vent_plug"]:
		return "Guardian"
	return "Boss arena"

# Sort key in Enemies & bosses: enemies by family (original first, then variants in registry order), bosses after.
static func _enemy_key(t: String, keys: Array) -> Array:
	if t.begins_with("enemy_"):
		var fam := "enemy_" + t.get_slice("_", 1)
		return [0, keys.find(fam), keys.find(t)]
	return [1, ["Ape", "Guardian", "Boss arena"].find(palette_subgroup(t)), keys.find(t)]

# Create a small editor label.
func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

# Create an editor action button and connect its callback.
func _btn(t: String, cb: Callable) -> Button:
	var b := Game.button(t, cb)
	b.focus_mode = Control.FOCUS_NONE
	return b

# Create a numeric field with the supplied limits and initial value.
func _spin(lo: int, hi: int, v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = v
	return s

# Add a palette button that selects a tile/object placement tool.
func _tool_button(parent: Control, id: String, text: String, col: Color) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = tool_group
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", col.lightened(0.6) if col.v < 0.3 else col)
	b.button_pressed = id == tool
	b.toggled.connect(func(on: bool):
		if on:
			tool = id
			zip_pending = null
			rect_start = null)
	parent.add_child(b)

# Refresh the load popup from level files currently available on disk.
func _fill_load_menu() -> void:
	var p := load_menu.get_popup()
	p.clear()
	for f in Game.list_levels():
		p.add_item(f)

# Open the custom level corresponding to a selected popup entry.
func _load_index(i: int) -> void:
	var d := Game.load_level(load_menu.get_popup().get_item_text(i))
	if d.is_empty():
		_status("Could not load level")
		return
	_push_undo()
	_set_level(d)
	Game.editor_dir = Game.LEVEL_DIR
	Game.editor_file = load_menu.get_popup().get_item_text(i)
	_status("Loaded " + d.name)

# Show the current level name and dimensions after loading or undoing changes.
func _sync_fields() -> void:
	name_edit.text = level.name
	w_spin.value = level.w
	h_spin.value = level.h
	enemy_spin.set_value_no_signal(int(level.get("enemy_count", -1)))

# Show a short temporary message in the editor status bar.
func _status(t: String) -> void:
	msg = t
	msg_t = 3.0

# ---------------- actions ----------------
# Save a deep snapshot before an edit and keep the undo history within its maximum size.
func _push_undo() -> void:
	undo_stack.append(level.duplicate(true))
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()

# Restore the most recent snapshot and rebuild previews to match it.
func _undo() -> void:
	if undo_stack.is_empty():
		return
	_set_level(undo_stack.pop_back())

# Replace the editable level with a fresh room.
func _new() -> void:
	_push_undo()
	_set_level(Game.new_level())
	Game.editor_dir = Game.LEVEL_DIR
	Game.editor_file = ""

# Every whole-level replacement goes through here so pending edits never point at stale data.
# Adopt a level dictionary, reset transient placement state and synchronize terrain and controls.
func _set_level(d: Dictionary) -> void:
	level = d
	zip_pending = null
	rect_start = null
	_sync_fields()
	tile_layer.setup(level.tiles, level.w, level.h, level.get("environment", ""))
	_refresh()

# Write the room to its correct custom-level or world-room filename, then remember the saved snapshot.
func _save() -> bool:
	var f := Game.save_level(level, Game.editor_dir, Game.editor_file)
	_status("Saved as %s.json" % f if f != "" else "Save failed")
	if f == "": return false
	Game.editor_file = f
	Game.editor_level = level.duplicate(true)
	saved_level = level.duplicate(true)
	_refresh_navigation()
	return true

# Go back to the menu or the World Editor; with unsaved edits, ask first: Save, Don't save, or Cancel (stay).
func _leave() -> void:
	if level == saved_level:
		Game.goto(Game.editor_return)
		return
	if get_children().any(func(c): return c is ConfirmationDialog):
		return  # already asking
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Save your changes before leaving?"
	dlg.ok_button_text = "Save"
	dlg.add_button("Don't save", true, "discard")
	dlg.confirmed.connect(func():
		if _save(): Game.goto(Game.editor_return))
	dlg.custom_action.connect(func(action: StringName):
		if action == "discard":
			Game.goto(Game.editor_return))
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

# Resize tile rows, discard objects outside the new bounds and rebuild the affected previews.
func _resize() -> void:
	_push_undo()
	var nw := int(w_spin.value)
	var nh := int(h_spin.value)
	var rows := []
	for y in nh:
		var old: String = level.tiles[y] if y < level.h else ""
		var row := old.substr(0, nw) if old.length() >= nw else old + "0".repeat(nw - old.length())
		rows.append(row)
	level.tiles = rows
	level.w = nw
	level.h = nh
	level.entities = level.entities.filter(func(e): return int(e.x) < nw * T and int(e.y) < nh * T)
	zip_pending = null
	tile_layer.setup(level.tiles, level.w, level.h, level.get("environment", ""))
	_refresh()

# Require a spawn, copy the current edit and start gameplay without losing the editor copy.
func _playtest() -> void:
	if level.entities.filter(func(e): return e.t == "spawn").is_empty():
		_status("Place a Spawn first")
		return
	Game.editor_level = level.duplicate(true)
	Game.play(level.duplicate(true), true)

# Full rebuild: load, undo, new, resize.
# Recreate all preview objects after a structural edit such as load, resize or undo.
func _refresh() -> void:
	_refresh_navigation()
	preview.clear()
	for d in level.entities:
		preview.append(E.make(null, d))
	_redraw()

# Rebuild one preview after level.entities[i] was appended or edited in place.
# Rebuild only one object preview when the rest of the room has not changed.
func _refresh_one(i: int) -> void:
	var e = E.make(null, level.entities[i])
	if i == preview.size():
		preview.append(e)
	else:
		preview[i] = e
	_redraw()

# ---------------- editing ----------------
# Convert the camera-adjusted mouse position from pixels to a tile coordinate.
func _cell_at_mouse() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x / T), floori(p.y / T))

# Check that a tile coordinate lies inside the editable room.
func _in_level(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < level.w and c.y < level.h

# Change one character in a tile row and invalidate neighboring visual chunks only when it changed.
func _set_tile(c: Vector2i, v: bool) -> void:
	if not _in_level(c):
		return
	var row: String = level.tiles[c.y]
	var ch := "1" if v else "0"
	if row[c.x] != ch:
		level.tiles[c.y] = row.substr(0, c.x) + ch + row.substr(c.x + 1)
		tile_layer.mark_cell_dirty(c)

# Fill the cells between mouse samples so a fast brush drag does not leave holes.
func _paint_line(a: Vector2i, b: Vector2i, v: bool) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := 0.0 if n == 0 else float(i) / n
		_set_tile(Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t))), v)

# Copy the selected cells' tiles and the objects whose top-left lies inside; a cut also clears them.
func _copy(cut: bool) -> void:
	var o := sel.position * T
	clip = {w = sel.size.x, h = sel.size.y, tiles = [], entities = []}
	for y in range(sel.position.y, sel.end.y):
		clip.tiles.append(level.tiles[y].substr(sel.position.x, sel.size.x))
	var area := Rect2i(o, sel.size * T)
	var inside := func(e: Dictionary) -> bool: return area.has_point(Vector2i(int(e.x), int(e.y)))
	for e in level.entities.filter(inside):
		var d: Dictionary = e.duplicate(true)
		_shift(d, -o)
		clip.entities.append(d)
	if cut:
		_push_undo()
		for y in range(sel.position.y, sel.end.y):
			for x in range(sel.position.x, sel.end.x):
				_set_tile(Vector2i(x, y), false)
		level.entities = level.entities.filter(func(e): return not inside.call(e))
		_refresh()
	_status("%s %dx%d, %d objects (Ctrl+V pastes at the mouse)" % ["Cut" if cut else "Copied", sel.size.x, sel.size.y, clip.entities.size()])

# Paste the clipboard with its top-left at cell c: tiles overwrite, objects are added (one spawn per room).
func _paste(c: Vector2i) -> void:
	_push_undo()
	for y in int(clip.h):
		for x in int(clip.w):
			_set_tile(c + Vector2i(x, y), clip.tiles[y][x] == "1")
	var bounds := Rect2i(0, 0, level.w * T, level.h * T)
	for e in clip.entities:
		var d: Dictionary = e.duplicate(true)
		_shift(d, c * T)
		if not bounds.has_point(Vector2i(int(d.x), int(d.y))):
			continue
		if d.t == "spawn":
			level.entities = level.entities.filter(func(o): return o.t != "spawn")
		level.entities.append(d)
	sel = Rect2i(c, Vector2i(clip.w, clip.h)).intersection(Rect2i(0, 0, level.w, level.h))
	_refresh()
	_status("Pasted %dx%d" % [clip.w, clip.h])

# Move an object dictionary by off pixels (zip movers' targets too).
func _shift(d: Dictionary, off: Vector2i) -> void:
	d.x = int(d.x) + off.x
	d.y = int(d.y) + off.y
	if d.has("tx"):
		d.tx = int(d.tx) + off.x
		d.ty = int(d.ty) + off.y

# Find the topmost placed object under a tile-centred click; return -1 when none is found.
func _entity_at(c: Vector2i) -> int:
	var p := Vector2i(c.x * T + 4, c.y * T + 4)
	for i in range(level.entities.size() - 1, -1, -1):
		var e: Dictionary = level.entities[i]
		var r := Rect2i(int(e.x), int(e.y), int(e.get("w", T)), int(e.get("h", T)))
		if r.has_point(p):
			return i
	return -1

# Place a single-cell object, avoid duplicates and handle spawn uniqueness or note editing.
# Rotatable objects: one palette entry each (the first id); placing faces away from the wall it touches,
# clicking a placed one turns it to the next direction.
const ROTATIONS := {"spikes": ["spikes_up", "spikes_right", "spikes_down", "spikes_left"], "spring": ["spring_up", "spring_right", "spring_left"]}
# The wall each direction sits on: up = floor below, down = roof above, left = wall to the right, right = wall to the left.
const MOUNT := {"up": Vector2i.DOWN, "down": Vector2i.UP, "left": Vector2i.RIGHT, "right": Vector2i.LEFT}

func rotations_of(t: String) -> Array:
	for k in ROTATIONS:
		if t in ROTATIONS[k]:
			return ROTATIONS[k]
	return []

func _solid(c: Vector2i) -> bool:
	return not _in_level(c) or level.tiles[c.y][c.x] == "1"

# The first direction of the family whose wall is next to cell c (the floor first), else the first.
func oriented(fam: Array, c: Vector2i) -> String:
	for t in fam:
		if _solid(c + MOUNT[t.get_slice("_", t.get_slice_count("_") - 1)]):
			return t
	return fam[0]

func _place_point(c: Vector2i, click := false) -> void:
	if not _in_level(c):
		return
	var x := c.x * T
	var y := c.y * T
	var fam := rotations_of(tool)
	if not fam.is_empty():
		for i in level.entities.size():
			var e: Dictionary = level.entities[i]
			if int(e.x) == x and int(e.y) == y and e.t in fam:
				if click:  # click again: rotate
					e.t = fam[(fam.find(e.t) + 1) % fam.size()]
					_refresh_one(i)
				return
		level.entities.append({"t": oriented(fam, c), "x": x, "y": y})
		_refresh_one(level.entities.size() - 1)
		return
	for e in level.entities:
		if int(e.x) == x and int(e.y) == y and not E.TYPES[e.t][1]:
			if e.t == tool:
				if tool == "note":
					_ask_note(e)
				return  # already there
	if tool == "spawn":
		level.entities = level.entities.filter(func(e): return e.t != "spawn")
	level.entities.append({"t": tool, "x": x, "y": y})
	if tool == "note":
		level.entities[-1].text = ""
		_ask_note(level.entities[-1])
	if tool == "spawn":  # removed the old spawn: rare, so rebuild everything
		_refresh()
	else:
		_refresh_one(level.entities.size() - 1)

# Design note text (e.g. "Needs double jump"). Click a placed note with the Note tool to edit it.
# Open a text dialog linked to this note dictionary and refresh the preview after confirmation.
func _ask_note(e: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Note"
	var edit := LineEdit.new()
	edit.text = e.get("text", "")
	edit.placeholder_text = "e.g. Needs double jump / Boss arena / Secret wall"
	edit.custom_minimum_size.x = 420
	edit.max_length = 500
	dlg.add_child(edit)
	dlg.register_text_enter(edit)
	dlg.confirmed.connect(func():
		e.text = edit.text
		for i in level.entities.size():
			if is_same(level.entities[i], e):
				_refresh_one(i)
		_redraw())
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
	edit.grab_focus()

# Door link: its own id, and "room:id" of the door it leads to ("id" alone = a door in this level).
# Edit the doorway ID and destination, using room:id for a link to another room.
func _ask_door(e: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Door"
	var box := VBoxContainer.new()
	var id_edit := LineEdit.new()
	id_edit.text = e.get("id", "")
	id_edit.placeholder_text = "this door's id, e.g. d1"
	var to_edit := LineEdit.new()
	to_edit.text = e.get("to", "")
	to_edit.placeholder_text = "leads to: room_name:door_id (or door_id in this level)"
	to_edit.custom_minimum_size.x = 420
	for le in [id_edit, to_edit]:
		le.max_length = 100
	box.add_child(Game.label("Id", 16))
	box.add_child(id_edit)
	box.add_child(Game.label("Leads to", 16))
	box.add_child(to_edit)
	dlg.add_child(box)
	dlg.register_text_enter(to_edit)
	dlg.confirmed.connect(func():
		e.id = id_edit.text
		e.to = to_edit.text
		for i in level.entities.size():
			if is_same(level.entities[i], e):
				_refresh_one(i)
		_redraw())
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
	to_edit.grab_focus()

# Convert a drag range to a sized object and request extra data for doors or moving platforms.
func _place_rect(a: Vector2i, b: Vector2i) -> void:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)).clamp(Vector2i.ZERO, Vector2i(level.w - 1, level.h - 1))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)).clamp(Vector2i.ZERO, Vector2i(level.w - 1, level.h - 1))
	var d := {"t": tool, "x": lo.x * T, "y": lo.y * T, "w": (hi.x - lo.x + 1) * T, "h": (hi.y - lo.y + 1) * T}
	if tool == "jumpthru":
		d.h = T
	level.entities.append(d)
	if tool == "zip":
		zip_pending = d
	if tool in E.DOOR_TYPES:
		var n := 1
		while level.entities.any(func(e): return e.t in E.DOOR_TYPES and e.get("id", "") == "d%d" % n):
			n += 1
		d.id = "d%d" % n
		d.to = ""
		_ask_door(d)
	_refresh_one(level.entities.size() - 1)

# Translate keyboard/mouse gestures into undo, saving, playtesting, painting, erasing and panning.
func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(navigation_dialog): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_save()
		elif event.keycode in [KEY_C, KEY_X] and event.ctrl_pressed and sel.has_area():
			_copy(event.keycode == KEY_X)
		elif event.ctrl_pressed and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:  # Ctrl + arrow: next room
			var dir: Vector2i = {KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT, KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN}[event.keycode]
			var options := arrows.filter(func(a): return a.dir == dir and not a.get("door", false))
			if not options.is_empty():  # several on one side: the one nearest the middle of the view
				options.sort_custom(func(a, b): return a.at.distance_to(cam.position) < b.at.distance_to(cam.position))
				get_viewport().set_input_as_handled()
				_request_room(options[0].name)
		elif event.keycode == KEY_V and event.ctrl_pressed and not clip.is_empty():
			_paste(_cell_at_mouse())
		elif event.keycode == KEY_F5:
			_playtest()
		elif event.keycode == KEY_ESCAPE:  # back to where the editor was opened from (asks to save first)
			get_viewport().set_input_as_handled()
			_leave()
	if event is InputEventKey and event.keycode == KEY_SPACE:
		space_down = event.pressed

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_refresh_navigation.call_deferred()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(0.8)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and space_down):
			panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_left(mb.pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_right(mb.pressed)
	elif event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
			dragging_paint = 0  # the button was released over the UI, where we never saw it
			rect_start = null
		if panning:
			cam.position -= event.relative / cam.zoom
		elif dragging_paint != 0:
			var c := _cell_at_mouse()
			if tool == "tile" or dragging_paint == -1:
				if dragging_paint == -1 and tool != "tile":
					var i := _entity_at(c)
					if i >= 0:
						_erase_entity(i)
				else:
					_paint_line(last_cell, c, dragging_paint == 1)
			elif not E.TYPES[tool][1] and tool != "note":  # notes: one per click (each asks for text)
				_place_point(c)
			last_cell = c
		_redraw()

# Begin or finish a left-button placement gesture, including sized objects and moving-platform targets.
func _left(pressed: bool) -> void:
	var c := _cell_at_mouse()
	if pressed and _arrow_at(get_global_mouse_position()) != null:  # an edge arrow: edit that room
		_request_room(_arrow_at(get_global_mouse_position()).name)
		return
	if pressed and Input.is_key_pressed(KEY_SHIFT):  # Shift+drag: select an area
		sel_start = c
		sel = Rect2i(c, Vector2i.ONE)
		_redraw()
		return
	if not pressed and sel_start != null:
		sel = Rect2i(Vector2i(mini(sel_start.x, c.x), mini(sel_start.y, c.y)), (sel_start - c).abs() + Vector2i.ONE).intersection(Rect2i(0, 0, level.w, level.h))
		sel_start = null
		_redraw()
		return
	if pressed:
		sel = Rect2i()
		if zip_pending != null:
			_push_undo()
			zip_pending.tx = c.x * T
			zip_pending.ty = c.y * T
			for i in level.entities.size():
				if is_same(level.entities[i], zip_pending):
					_refresh_one(i)
					break
			zip_pending = null
			_status("Zip mover placed")
			return
		_push_undo()
		var hit := _entity_at(c)
		if tool == "door" and hit >= 0 and level.entities[hit].t in E.DOOR_TYPES:
			_ask_door(level.entities[hit])  # click a door with the Door tool to edit its link
			return
		if tool == "tile":
			dragging_paint = 1
			_set_tile(c, true)
		elif E.TYPES[tool][1]:
			rect_start = c
		else:
			dragging_paint = 1
			_place_point(c, true)
		last_cell = c
	else:
		if rect_start != null:
			_place_rect(rect_start, c)
			rect_start = null
		dragging_paint = 0
	_redraw()

# Begin or finish an erase gesture, saving the appropriate undo snapshot.
func _right(pressed: bool) -> void:
	if pressed:
		_push_undo()
		dragging_paint = -1
		var c := _cell_at_mouse()
		last_cell = c
		if tool == "tile":
			_set_tile(c, false)
		else:
			var i := _entity_at(c)
			if i >= 0:
				_erase_entity(i)
	else:
		dragging_paint = 0
	_redraw()

# Remove an object and keep the data and preview arrays aligned.
func _erase_entity(i: int) -> void:
	if is_same(level.entities[i], zip_pending):
		zip_pending = null
	level.entities.remove_at(i)
	preview.remove_at(i)
	_redraw()

# Change camera zoom while preserving the world point under the mouse.
func _zoom(f: float) -> void:
	var before := get_global_mouse_position()
	cam.zoom = (cam.zoom * f).clamp(Vector2(0.5, 0.5), Vector2(10, 10))
	cam.position += before - get_global_mouse_position()
	_redraw()

# Update temporary messages and editor hover/drag visuals between input events.
func _process(dt: float) -> void:
	var v := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if v != Vector2.ZERO and not Input.is_key_pressed(KEY_CTRL) and not (get_viewport().gui_get_focus_owner() is LineEdit):
		cam.position += v * 400 * dt / cam.zoom.x
		_redraw()
	var c := _cell_at_mouse()
	msg_t -= dt
	var over = _arrow_at(get_global_mouse_position())
	if over != null:
		status.text = "Click: edit %s (Ctrl + arrow key)" % over.name
	elif zip_pending != null:
		status.text = "Zip mover: click where it should travel to"
	elif msg_t > 0:
		status.text = msg
	else:
		status.text = "Tile %d, %d   |   LMB place/paint  RMB erase  MMB/Space+drag pan  Wheel zoom  Ctrl+Z undo  Shift+drag select  Ctrl+X/C/V cut/copy/paste  Ctrl+S save  F5 playtest" % [c.x, c.y]

# ---------------- drawing ----------------
# Draw room scenery and editor background beneath the retained terrain.
func _draw_background(ci: CanvasItem) -> void:
	var vs := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.position - vs / 2.0, vs)
	ci.draw_rect(view, Color("0c0c1e"))
	var b := Rect2(0, 0, level.w * T, level.h * T)
	if level.get("environment", "") != "":
		Art.draw_background(ci, view, 0.0, level.environment, b)
	else:
		ci.draw_rect(b, Art.SKY)
	if cam.zoom.x >= 2:
		var gc := Color(1, 1, 1, 0.05)
		for x in range(0, level.w + 1):
			ci.draw_line(Vector2(x * T, 0), Vector2(x * T, b.size.y), gc)
		for y in range(0, level.h + 1):
			ci.draw_line(Vector2(0, y * T), Vector2(b.size.x, y * T), gc)

# Draw object previews, editing grid and the current placement/selection guides.
func _draw() -> void:
	# Also follow redraws requested directly by tools or benchmark subclasses.
	background.queue_redraw()
	var vs := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.position - vs / 2.0, vs)
	var b := Rect2(0, 0, level.w * T, level.h * T)
	var cull := Rect2i(view.position.floor(), view.size.ceil()).grow(1)
	E.JumpThru.editor_look = str(level.get("environment", ""))  # jump-throughs take the room's look
	E.Ent.editor_ents = preview  # touching blocks and pools draw as one
	for e in preview:
		if e != null and e.vis_rect().intersects(cull):
			e.draw(self)
	# Hide scenery and edge artwork outside the authored room, even while panning.
	var outside := Color("0c0c1e")
	var visible := view.grow(2.0 / cam.zoom.x)
	for strip in [Rect2(visible.position, Vector2(visible.size.x, maxf(0, b.position.y - visible.position.y))),
		Rect2(Vector2(visible.position.x, b.end.y), Vector2(visible.size.x, maxf(0, visible.end.y - b.end.y))),
		Rect2(Vector2(visible.position.x, b.position.y), Vector2(maxf(0, b.position.x - visible.position.x), b.size.y)),
		Rect2(Vector2(b.end.x, b.position.y), Vector2(maxf(0, visible.end.x - b.end.x), b.size.y))]:
		if strip.has_area(): draw_rect(strip, outside)
	draw_rect(b, Color(1, 1, 1, 0.5), false, 1.0 / cam.zoom.x)
	var c := _cell_at_mouse()
	if rect_start != null:
		var lo := Vector2(mini(rect_start.x, c.x), mini(rect_start.y, c.y)) * T
		var hi := Vector2(maxi(rect_start.x, c.x) + 1, maxi(rect_start.y, c.y) + 1) * T
		draw_rect(Rect2(lo, hi - lo), Color(E.TYPES[tool][2], 0.5))
	else:
		draw_rect(Rect2(c * T, Vector2(T, T)), Color(1, 1, 1, 0.3), false, 1.0 / cam.zoom.x)
	if sel_start != null or sel.has_area():
		var sr: Rect2i = Rect2i(Vector2i(mini(sel_start.x, c.x), mini(sel_start.y, c.y)), (sel_start - c).abs() + Vector2i.ONE) if sel_start != null else sel
		draw_rect(Rect2(sr.position * T, sr.size * T), Color(0.4, 0.8, 1.0, 0.15))
		draw_rect(Rect2(sr.position * T, sr.size * T), Color(0.4, 0.8, 1.0), false, 1.0 / cam.zoom.x)
	var hover = _arrow_at(get_global_mouse_position())
	for a in arrows:  # edge arrows to the connected rooms
		var k := 9.0 / cam.zoom.x + 3
		var d := Vector2(a.dir)
		var side := Vector2(-d.y, d.x)
		var tip: Vector2 = a.at + d * k
		var col := (Color("9ff4ff") if a == hover else Color("40c8e0")) if a.get("door", false) else (Color("ffe070") if a == hover else Color("d0a030"))
		draw_colored_polygon(PackedVector2Array([tip, a.at - d * k * 0.4 + side * k, a.at - d * k * 0.4 - side * k]), col)
	if zip_pending != null:
		var from := Vector2(zip_pending.x, zip_pending.y) + Vector2(zip_pending.w, zip_pending.h) / 2.0
		draw_line(from, Vector2(c * T) + Vector2(4, 4), Color("d0b040"), 1.0 / cam.zoom.x)

# Use live source geometry, saved neighboring rooms and valid explicit door targets.
func _connected_rooms() -> Array:
	var result: Array = []
	if Game.editor_return != "world_editor": return result
	var world: Dictionary = Game.Adventure.load_world(Game.world_path)
	if not world.get("rooms", {}).has(Game.editor_file): return result
	var source: Dictionary = world.rooms[Game.editor_file].duplicate(true)
	source.level = level
	for name in world.rooms:
		if name == Game.editor_file: continue
		var pair := {"rooms": {Game.editor_file: source, name: world.rooms[name]}}
		var linked := not Game.Adventure.doorways(pair).is_empty()
		for entity in level.entities:
			if entity.t not in E.DOOR_TYPES: continue
			var target := str(entity.get("to", ""))
			if target.get_slice(":", 0) != name or not target.contains(":"): continue
			for arrival in world.rooms[name].level.entities:
				if arrival.t in E.DOOR_TYPES and str(arrival.get("id", "")) == target.get_slice(":", 1):
					linked = true
		if linked: result.append(name)
	result.sort()
	return result

# Arrows just outside the room's edges, one per connected room that touches that edge, at the middle of the
# shared stretch (yellow; click one or press Ctrl + arrow key), and over each door to another room (cyan; click).
func _edge_arrows(names: Array) -> Array:
	var out: Array = []
	if Game.editor_return != "world_editor": return out
	var world: Dictionary = Game.Adventure.load_world(Game.world_path)
	if not world.get("rooms", {}).has(Game.editor_file): return out
	var me := Rect2i(world.rooms[Game.editor_file].pos, Vector2i(level.w, level.h))
	for name in names:
		var o := Rect2i(world.rooms[name].pos, Vector2i(world.rooms[name].level.w, world.rooms[name].level.h))
		var ys := Vector2(maxi(me.position.y, o.position.y), mini(me.end.y, o.end.y))  # shared rows / columns
		var xs := Vector2(maxi(me.position.x, o.position.x), mini(me.end.x, o.end.x))
		var mid_y := ((ys.x + ys.y) / 2.0 - me.position.y) * T
		var mid_x := ((xs.x + xs.y) / 2.0 - me.position.x) * T
		if o.position.x == me.end.x and ys.y > ys.x:
			out.append({"name": name, "dir": Vector2i.RIGHT, "at": Vector2(level.w * T + 10, mid_y)})
		elif o.end.x == me.position.x and ys.y > ys.x:
			out.append({"name": name, "dir": Vector2i.LEFT, "at": Vector2(-10, mid_y)})
		elif o.position.y == me.end.y and xs.y > xs.x:
			out.append({"name": name, "dir": Vector2i.DOWN, "at": Vector2(mid_x, level.h * T + 10)})
		elif o.end.y == me.position.y and xs.y > xs.x:
			out.append({"name": name, "dir": Vector2i.UP, "at": Vector2(mid_x, -10)})
	for e in level.entities:  # doors to another room: a cyan arrow over the door
		var to := str(e.get("to", ""))
		if e.t in E.DOOR_TYPES and to.contains(":") and to.get_slice(":", 0) in names:
			out.append({"name": to.get_slice(":", 0), "dir": Vector2i.UP, "door": true,
				"at": Vector2(int(e.x) + int(e.get("w", T)) / 2.0, int(e.y) - 8)})
	return out

func _arrow_at(p: Vector2):
	for a in arrows:
		if p.distance_to(a.at) <= 9.0 / cam.zoom.x + 4:
			return a
	return null

func _refresh_navigation() -> void:
	arrows = _edge_arrows(_connected_rooms())
	queue_redraw()
	if navigation_box == null: return
	for child in navigation_box.get_children():
		navigation_box.remove_child(child)
		child.queue_free()
	if Game.editor_return != "world_editor": return
	navigation_box.add_child(_lbl("Connected rooms"))
	for name in _connected_rooms():
		var button := _btn(str(name), func(): _request_room(name))
		button.tooltip_text = "Edit connected room " + str(name)
		navigation_box.add_child(button)

func _request_room(name: String) -> void:
	if name not in _connected_rooms():
		_status("Room is no longer connected")
		return
	if level == saved_level:
		_open_connected_room(name)
		return
	if is_instance_valid(navigation_dialog): return
	var dlg := ConfirmationDialog.new()
	navigation_dialog = dlg
	dlg.dialog_text = "Save your changes before opening %s?" % name
	dlg.ok_button_text = "Save"
	dlg.add_button("Don't save", true, "discard")
	dlg.confirmed.connect(func():
		if _save(): _open_connected_room(name)
		dlg.queue_free())
	dlg.custom_action.connect(func(action: StringName):
		if action == "discard":
			_open_connected_room(name)
			dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

func _open_connected_room(name: String) -> void:
	var data := Game.load_level(name, Game.world_path.get_base_dir() + "/")
	if data.is_empty():
		_status("Could not load connected room")
		return
	Game.editor_dir = Game.world_path.get_base_dir() + "/"
	Game.editor_file = name
	Game.editor_level = data.duplicate(true)
	saved_level = data.duplicate(true)
	undo_stack.clear()
	sel = Rect2i()
	sel_start = null
	dragging_paint = 0
	_set_level(data)
	_frame_room()
	_refresh_navigation()
	_status("Opened " + str(level.name))

# Fit the complete destination beside the palette, below the toolbar and above status.
func _frame_room() -> void:
	var screen := get_viewport_rect().size
	var workspace := Rect2(Vector2(230, 50), Vector2(maxf(1, screen.x - 246), maxf(1, screen.y - 100)))
	var room_size := Vector2(level.w * T, level.h * T)
	var scale := minf(workspace.size.x / room_size.x, workspace.size.y / room_size.y)
	cam.zoom = Vector2.ONE * minf(scale, 10.0)
	cam.position = room_size / 2.0 - (workspace.get_center() - screen / 2.0) / cam.zoom
	cam.reset_smoothing()
	_redraw()
