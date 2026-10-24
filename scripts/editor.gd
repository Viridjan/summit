extends Node2D
# Level editor.
# LMB: paint tiles / place entity (drag to size blocks).  RMB: erase tile / delete entity.
# MMB or Space+drag: pan.  Wheel: zoom.  Ctrl+Z undo, Ctrl+S save, F5 playtest.

const E := preload("res://scripts/entities.gd")
const Art := preload("res://scripts/art.gd")
const TileLayer := preload("res://scripts/tile_layer.gd")
const T := 8
const MAX_UNDO := 60

# Background is behind retained terrain; parent draws entities and overlays.
class Background extends Node2D:
	var screen: Node2D
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
var panning := false
var space_down := false

var ui: CanvasLayer
var name_edit: LineEdit
var w_spin: SpinBox
var h_spin: SpinBox
var status: Label
var load_menu: MenuButton
var tool_group := ButtonGroup.new()
var msg := ""
var msg_t := 0.0

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

# ---------------- UI ----------------
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
	_tool_button(tools, "tile", "Ground Tiles", Color("7d84c4"))
	for t in E.TYPES:
		_tool_button(tools, t, E.TYPES[t][0], E.TYPES[t][2])

	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -32
	root.add_child(bottom)
	status = Label.new()
	bottom.add_child(status)

func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Game.button(t, cb)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _spin(lo: int, hi: int, v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = v
	return s

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

func _fill_load_menu() -> void:
	var p := load_menu.get_popup()
	p.clear()
	for f in Game.list_levels():
		p.add_item(f)

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

func _sync_fields() -> void:
	name_edit.text = level.name
	w_spin.value = level.w
	h_spin.value = level.h

func _status(t: String) -> void:
	msg = t
	msg_t = 3.0

# ---------------- actions ----------------
func _push_undo() -> void:
	undo_stack.append(level.duplicate(true))
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	_set_level(undo_stack.pop_back())

func _new() -> void:
	_push_undo()
	_set_level(Game.new_level())
	Game.editor_dir = Game.LEVEL_DIR
	Game.editor_file = ""

# Every whole-level replacement goes through here so pending edits never point at stale data.
func _set_level(d: Dictionary) -> void:
	level = d
	zip_pending = null
	rect_start = null
	_sync_fields()
	tile_layer.setup(level.tiles, level.w, level.h, level.get("environment", ""))
	_refresh()

func _save() -> void:
	var f := Game.save_level(level, Game.editor_dir, Game.editor_file)
	_status("Saved as %s.json" % f if f != "" else "Save failed")
	Game.editor_level = level.duplicate(true)
	saved_level = level.duplicate(true)

func _leave() -> void:
	if level == saved_level:
		Game.goto(Game.editor_return)
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Leave without saving your changes?"
	dlg.ok_button_text = "Leave"
	dlg.confirmed.connect(func(): Game.goto(Game.editor_return))
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

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

func _playtest() -> void:
	if level.entities.filter(func(e): return e.t == "spawn").is_empty():
		_status("Place a Spawn first")
		return
	Game.editor_level = level.duplicate(true)
	Game.play(level.duplicate(true), true)

# Full rebuild: load, undo, new, resize.
func _refresh() -> void:
	preview.clear()
	for d in level.entities:
		preview.append(E.make(null, d))
	_redraw()

# Rebuild one preview after level.entities[i] was appended or edited in place.
func _refresh_one(i: int) -> void:
	var e = E.make(null, level.entities[i])
	if i == preview.size():
		preview.append(e)
	else:
		preview[i] = e
	_redraw()

# ---------------- editing ----------------
func _cell_at_mouse() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x / T), floori(p.y / T))

func _in_level(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < level.w and c.y < level.h

func _set_tile(c: Vector2i, v: bool) -> void:
	if not _in_level(c):
		return
	var row: String = level.tiles[c.y]
	var ch := "1" if v else "0"
	if row[c.x] != ch:
		level.tiles[c.y] = row.substr(0, c.x) + ch + row.substr(c.x + 1)
		tile_layer.mark_cell_dirty(c)

func _paint_line(a: Vector2i, b: Vector2i, v: bool) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := 0.0 if n == 0 else float(i) / n
		_set_tile(Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t))), v)

func _entity_at(c: Vector2i) -> int:
	var p := Vector2i(c.x * T + 4, c.y * T + 4)
	for i in range(level.entities.size() - 1, -1, -1):
		var e: Dictionary = level.entities[i]
		var r := Rect2i(int(e.x), int(e.y), int(e.get("w", T)), int(e.get("h", T)))
		if r.has_point(p):
			return i
	return -1

func _place_point(c: Vector2i) -> void:
	if not _in_level(c):
		return
	var x := c.x * T
	var y := c.y * T
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_save()
		elif event.keycode == KEY_F5:
			_playtest()
	if event is InputEventKey and event.keycode == KEY_SPACE:
		space_down = event.pressed

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
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

func _left(pressed: bool) -> void:
	var c := _cell_at_mouse()
	if pressed:
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
			_place_point(c)
		last_cell = c
	else:
		if rect_start != null:
			_place_rect(rect_start, c)
			rect_start = null
		dragging_paint = 0
	_redraw()

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

func _erase_entity(i: int) -> void:
	if is_same(level.entities[i], zip_pending):
		zip_pending = null
	level.entities.remove_at(i)
	preview.remove_at(i)
	_redraw()

func _zoom(f: float) -> void:
	var before := get_global_mouse_position()
	cam.zoom = (cam.zoom * f).clamp(Vector2(0.5, 0.5), Vector2(10, 10))
	cam.position += before - get_global_mouse_position()
	_redraw()

func _process(dt: float) -> void:
	var v := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if v != Vector2.ZERO and not (get_viewport().gui_get_focus_owner() is LineEdit):
		cam.position += v * 400 * dt / cam.zoom.x
		_redraw()
	var c := _cell_at_mouse()
	msg_t -= dt
	if zip_pending != null:
		status.text = "Zip mover: click where it should travel to"
	elif msg_t > 0:
		status.text = msg
	else:
		status.text = "Tile %d, %d   |   LMB place/paint  RMB erase  MMB/Space+drag pan  Wheel zoom  Ctrl+Z undo  Ctrl+S save  F5 playtest" % [c.x, c.y]

# ---------------- drawing ----------------
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

func _draw() -> void:
	# Also follow redraws requested directly by tools or benchmark subclasses.
	background.queue_redraw()
	var vs := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.position - vs / 2.0, vs)
	var b := Rect2(0, 0, level.w * T, level.h * T)
	var cull := Rect2i(view.position.floor(), view.size.ceil()).grow(1)
	for e in preview:
		if e != null and e.vis_rect().intersects(cull):
			e.draw(self)
	draw_rect(b, Color(1, 1, 1, 0.5), false, 1.0 / cam.zoom.x)
	var c := _cell_at_mouse()
	if rect_start != null:
		var lo := Vector2(mini(rect_start.x, c.x), mini(rect_start.y, c.y)) * T
		var hi := Vector2(maxi(rect_start.x, c.x) + 1, maxi(rect_start.y, c.y) + 1) * T
		draw_rect(Rect2(lo, hi - lo), Color(E.TYPES[tool][2], 0.5))
	else:
		draw_rect(Rect2(c * T, Vector2(T, T)), Color(1, 1, 1, 0.3), false, 1.0 / cam.zoom.x)
	if zip_pending != null:
		var from := Vector2(zip_pending.x, zip_pending.y) + Vector2(zip_pending.w, zip_pending.h) / 2.0
		draw_line(from, Vector2(c * T) + Vector2(4, 4), Color("d0b040"), 1.0 / cam.zoom.x)
