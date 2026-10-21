extends Control
# In-game debug panel (F1): live player state machine + variables, and movement tuning
# with named presets. Works in normal play and in editor playtests. Owned by world.gd.

const Tuning := preload("res://scripts/tuning.gd")
const PlayerScript := preload("res://scripts/player.gd")

# player variables shown live (label, property)
const LIVE := [
	["pos", "pos"], ["speed", "speed"], ["facing", "facing"], ["dashes", "dashes"], ["stamina", "stamina"],
	["on_ground", "on_ground"], ["on_safe_ground", "on_safe_ground"], ["ducking", "collider"],
	["jump_grace_timer", "jump_grace_timer"], ["var_jump_timer", "var_jump_timer"], ["var_jump_speed", "var_jump_speed"],
	["auto_jump", "auto_jump"], ["dash_cooldown_timer", "dash_cooldown_timer"], ["dash_attack_timer", "dash_attack_timer"],
	["wall_slide_timer", "wall_slide_timer"], ["force_move_x_timer", "force_move_x_timer"], ["max_fall", "max_fall"],
	["lift_speed", "lift_current"], ["co_step", "co_step"], ["star_fly_timer", "star_fly_timer"],
]

var world
var sim_paused := false  # world reads this; step_frames lets single ticks through
var step_frames := 0
var graph: StateGraph
const LIVE_HELP := {
	"state": "Current state of the player state machine (graph above).",
	"pos": "Feet position in the room, in pixels (8 per tile).",
	"speed": "Velocity x, y in px/s (negative y = up).",
	"facing": "1 = right, -1 = left.",
	"dashes": "Dashes left before touching the ground or a crystal.",
	"stamina": "Climbing stamina; drains while grabbing walls, refills on the ground.",
	"on_ground": "Standing on something solid this frame.",
	"on_safe_ground": "Standing on ground that banks following stars (not crumbling/moving blocks).",
	"ducking": "Crouched (smaller hitbox).",
	"jump_grace_timer": "Coyote time left: a jump still works until this reaches 0 (s).",
	"var_jump_timer": "Time left that holding jump keeps the jump's upward speed (s).",
	"var_jump_speed": "Upward speed kept while var_jump_timer runs (px/s).",
	"auto_jump": "Acts as if jump were held (after springs/bounces).",
	"dash_cooldown_timer": "Time until another dash is allowed (s).",
	"dash_attack_timer": "Time the current dash still counts as a dash attack (s).",
	"wall_slide_timer": "Wall-slide slowdown left; falls faster as it runs out (s).",
	"force_move_x_timer": "Time horizontal input is overridden (after wall jumps, side springs) (s).",
	"max_fall": "Current falling-speed cap (eases toward fast_max_fall when holding down) (px/s).",
	"lift_speed": "Speed of the moving platform you're on, inherited when jumping off (px/s).",
	"co_step": "Step of the running timed sequence (Celeste coroutine) for dash/bubble/feather states.",
	"star_fly_timer": "Feather flight time left (s).",
}
var live_vals: Array = []  # value labels: state, then LIVE order
var log_label: Label
var spins := {}  # var name -> SpinBox
var name_labels := {}  # var name -> Label
var sections := []  # [header Button, Grid, names]
var preset_menu: OptionButton
var preset_name: LineEdit
var filter: LineEdit
var pause_box: Button
var status: Label

func _init(w) -> void:
	world = w

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Game.theme.duplicate()
	theme.default_font_size = 14

	# left: state machine + live variables
	var left := _panel(Vector2(8, 40), Vector2(440, 672))
	var lbox := VBoxContainer.new()
	left.add_child(lbox)
	lbox.add_child(_label("State machine  (F1 closes)", Color("ffd34e")))
	var graph_row := HBoxContainer.new()  # graph | recent transitions, side by side
	graph_row.add_theme_constant_override("separation", 14)  # room for the right-side arrow counts
	lbox.add_child(graph_row)
	graph = StateGraph.new()
	graph.custom_minimum_size = Vector2(230, 290)
	graph_row.add_child(graph)
	log_label = _label("", Color(0.75, 0.75, 0.85))
	log_label.add_theme_font_size_override("font_size", 12)
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_row.add_child(log_label)
	lbox.add_child(_label("Variables", Color("ffd34e")))
	var live_grid := GridContainer.new()
	live_grid.columns = 4  # name, value, name, value
	live_grid.add_theme_constant_override("h_separation", 8)
	lbox.add_child(live_grid)
	for e in [["state", ""]] + LIVE:
		for c in [Color(0.7, 0.75, 0.9), Color.WHITE]:
			var l := _label(e[0] if c != Color.WHITE else "", c)
			l.add_theme_font_size_override("font_size", 12)
			l.tooltip_text = LIVE_HELP.get(e[0], "")
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			live_grid.add_child(l)
			if c == Color.WHITE:
				# fixed width sized for the widest value (a vector) so columns don't shift; longer text still grows
				l.custom_minimum_size.x = l.get_theme_font("font").get_string_size("-0000, -0000", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4
				live_vals.append(l)

	# right: tuning
	var right := _panel(Vector2(1280 - 448, 8), Vector2(440, 704))
	var rbox := VBoxContainer.new()
	right.add_child(rbox)
	rbox.add_child(_label("Movement tuning", Color("ffd34e")))
	var row := HBoxContainer.new()
	rbox.add_child(row)
	preset_menu = OptionButton.new()
	preset_menu.focus_mode = Control.FOCUS_NONE
	preset_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(preset_menu)
	row.add_child(_button("Load", _load_preset))
	row.add_child(_button("Delete", _delete_preset))
	row = HBoxContainer.new()
	rbox.add_child(row)
	preset_name = LineEdit.new()
	preset_name.placeholder_text = "preset name"
	preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_name.text_submitted.connect(func(_t): _save_preset())
	row.add_child(preset_name)
	row.add_child(_button("Save", _save_preset))
	row = HBoxContainer.new()
	rbox.add_child(row)
	row.add_child(_button("Reset all", _reset_all))
	var exp := _button("Export to project", _export)
	exp.disabled = not Tuning.can_export()
	exp.tooltip_text = Tuning.PROJECT_FILE + " (only when run from source)"
	row.add_child(exp)
	pause_box = Button.new()
	pause_box.toggle_mode = true
	pause_box.text = "Pause sim"
	pause_box.focus_mode = Control.FOCUS_NONE
	pause_box.toggled.connect(func(on: bool): sim_paused = on)
	row.add_child(pause_box)
	row.add_child(_button("Step", func(): step_frames += 1))
	var hb := Button.new()
	hb.toggle_mode = true
	hb.text = "Hitboxes"
	hb.tooltip_text = "Outline collision boxes: player (green), sword swing (red), objects (yellow), hazard/touch areas (orange)"
	hb.focus_mode = Control.FOCUS_NONE
	hb.button_pressed = Game.settings.hitboxes
	hb.toggled.connect(func(on: bool):
		Game.settings.hitboxes = on
		Game.save_settings())
	row.add_child(hb)
	status = _label("", Color(0.6, 1, 0.6))
	rbox.add_child(status)
	filter = LineEdit.new()
	filter.placeholder_text = "filter variables"
	filter.text_changed.connect(func(_t): _apply_filter())
	rbox.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_build_tunables(list)
	_fill_presets()
	_sync_spins()

func _panel(at: Vector2, size_px: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = at
	p.size = size_px
	p.custom_minimum_size = size_px
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.1, 0.6)  # see-through enough to watch the game behind
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p

func _label(t: String, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", c)
	return l

func _button(t: String, cb: Callable) -> Button:
	var b := Game.button(t, cb)
	b.focus_mode = Control.FOCUS_NONE  # keep jump/space from pressing it
	return b

func _build_tunables(list: VBoxContainer) -> void:
	var by_group := {}
	for n in Tuning.names():
		var g := Tuning.group_of(n)
		if not by_group.has(g):
			by_group[g] = []
		by_group[g].append(n)
	var order: Array = Tuning.GROUPS.map(func(g): return g[0]) + ["Other"]
	for g in order:
		if not by_group.has(g):
			continue
		var head := Button.new()
		var open: bool = Game.settings.tuning_open_groups.has(g)  # collapsed unless opened before
		head.text = ("- " if open else "+ ") + g
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.focus_mode = Control.FOCUS_NONE
		list.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.visible = open
		list.add_child(grid)
		head.pressed.connect(func():
			grid.visible = not grid.visible
			head.text = ("- " if grid.visible else "+ ") + g
			if filter.text == "":  # remember only the user's own choice, not filter auto-expansion
				var groups: Array = Game.settings.tuning_open_groups
				groups.erase(g)
				if grid.visible:
					groups.append(g)
				Game.save_settings())
		for n in by_group[g]:
			var l := _label(n.to_lower(), Color.WHITE)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.tooltip_text = "%s\nDefault %s" % [Tuning.HELP.get(n, ""), Tuning.defaults()[n]]
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			grid.add_child(l)
			var r := Tuning.range_of(n)
			var sp := SpinBox.new()
			sp.min_value = r[0]
			sp.max_value = r[1]
			sp.step = r[2]
			sp.custom_minimum_size = Vector2(130, 0)
			sp.get_line_edit().tooltip_text = l.tooltip_text
			sp.value_changed.connect(_on_value.bind(n))
			sp.get_line_edit().text_submitted.connect(func(_t): sp.get_line_edit().release_focus())
			grid.add_child(sp)
			spins[n] = sp
			name_labels[n] = l
		sections.append([head, grid, by_group[g], g])
	# derived values, read-only
	var head := _label("Derived (read-only)", Color(0.7, 0.7, 0.8))
	list.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	list.add_child(grid)
	for n in Tuning.DERIVED:
		var dl := _label(n.to_lower(), Color(0.7, 0.7, 0.8))
		dl.tooltip_text = Tuning.HELP.get(n, "")
		dl.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(dl)
		var v := _label("", Color(0.7, 0.7, 0.8))
		v.name = n
		grid.add_child(v)
	sections.append([head, grid, Tuning.DERIVED, ""])

func _apply_filter() -> void:
	var f := filter.text.to_lower()
	for s in sections:
		var grid: GridContainer = s[1]
		var any := false
		for n in s[2]:
			var show: bool = f == "" or f in n.to_lower()
			any = any or show
			for c in grid.get_children():
				if c == spins.get(n) or c == name_labels.get(n):
					c.visible = show
		if s[3] != "":  # filtering opens groups with matches; clearing it restores the saved state
			grid.visible = any if f != "" else Game.settings.tuning_open_groups.has(s[3])
			s[0].text = ("- " if grid.visible else "+ ") + s[3]

# ---------------- tuning ----------------
func _on_value(v: float, n: String) -> void:
	var val = Tuning.coerce(n, v)
	if val == Tuning.defaults()[n]:
		Game.tuning.erase(n)
	else:
		Game.tuning[n] = val
	world.player.apply_tuning({n: val})
	_mark(n)

func _mark(n: String) -> void:
	var changed := Game.tuning.has(n)
	name_labels[n].add_theme_color_override("font_color", Color("ffb347") if changed else Color.WHITE)

func _sync_spins() -> void:
	var cur := Tuning.current(Game.tuning)
	for n in spins:
		spins[n].set_value_no_signal(cur[n])
		_mark(n)

func _apply_all() -> void:
	world.player.apply_tuning(Tuning.current(Game.tuning))
	_sync_spins()

func _reset_all() -> void:
	Game.tuning.clear()
	_apply_all()
	status.text = "Reset to code defaults (not saved)"

func _fill_presets() -> void:
	preset_menu.clear()
	for p in Tuning.list_presets():
		preset_menu.add_item(p)
		if p == Game.settings.tuning_preset:
			preset_menu.select(preset_menu.item_count - 1)

func _save_preset() -> void:
	var n := Game.file_safe(preset_name.text if preset_name.text.strip_edges() != "" else "default")
	if Tuning.save_preset(n, Game.tuning):
		Game.settings.tuning_preset = n
		Game.save_settings()
		status.text = "Saved preset '%s' (active at startup)" % n
	else:
		status.text = "Could not save preset"
	preset_name.release_focus()
	_fill_presets()

func _load_preset() -> void:
	if preset_menu.selected < 0:
		return
	var n := preset_menu.get_item_text(preset_menu.selected)
	var values := Tuning.load_file(Tuning.preset_path(n))
	Game.tuning.clear()
	for k in values:  # store only differences from code defaults
		if values[k] != Tuning.defaults()[k]:
			Game.tuning[k] = values[k]
	Game.settings.tuning_preset = n
	Game.save_settings()
	_apply_all()
	status.text = "Loaded preset '%s' (active at startup)" % n

func _delete_preset() -> void:
	if preset_menu.selected < 0:
		return
	var n := preset_menu.get_item_text(preset_menu.selected)
	Tuning.delete_preset(n)
	if Game.settings.tuning_preset == n:
		Game.settings.tuning_preset = ""
		Game.save_settings()
	status.text = "Deleted preset '%s'" % n
	_fill_presets()

func _export() -> void:
	status.text = ("Exported to " + Tuning.PROJECT_FILE) if Tuning.export_project(Game.tuning) else "Export failed"

# ---------------- live view ----------------
# True while a text field here has keyboard focus, so typing doesn't move the player.
func typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit and is_ancestor_of(f)

func _process(_dt: float) -> void:
	var p = world.player
	graph.player = p
	graph.queue_redraw()
	var t := ""
	for e in p.transition_log:
		t += "%.2fs  %s -> %s\n" % [e[0], PlayerScript.STATE_NAMES[e[1]], PlayerScript.STATE_NAMES[e[2]]]
	log_label.text = t
	live_vals[0].text = PlayerScript.STATE_NAMES[p.state] + ("  + Attack" if p.attacking() else "") + ("  (dead)" if p.dead else "")
	for i in LIVE.size():
		var prop: String = LIVE[i][1]
		live_vals[i + 1].text = _fmt(p.ducking() if prop == "collider" else p.get(prop))
	for n in Tuning.DERIVED:
		var l := find_child(n, true, false) as Label
		if l:
			l.text = _fmt(p.get(n))

static func _fmt(v) -> String:
	if v is float:
		return "%.2f" % v
	if v is Vector2:
		return "%.0f, %.0f" % [v.x, v.y]  # whole pixels: keeps the fixed-width column narrow
	return str(v)


# States on a circle; edges = transitions seen this life, thicker when more frequent.
class StateGraph extends Control:
	# States stacked top to bottom. Each transition is an angled arrow:
	# downward ones run on the right, upward ones on the left, wider for longer jumps.
	var player
	const HW := 52.0  # half width of a state box
	# One line per PlayerScript.STATE_NAMES entry, same order.
	const HELP := [
		"Normal: running, jumping, falling, wall jumps. Most time is spent here.",
		"Climb: holding grab on a wall. Drains stamina; at 0 you let go.",
		"Dash: the 8-way dash (a short timed sequence). Ends in Normal, or a super/hyper jump.",
		"Boost: inside a green/red bubble, waiting for a direction before it launches you.",
		"Red Dash: travelling inside a red bubble until it hits something.",
		"Hit Squash: brief squash when a red bubble hits a wall.",
		"Launch: thrown by a bumper; air control is reduced until speed drops.",
		"Dream Dash: dashing through a dream block, moving straight until you exit.",
		"Star Fly: feather flight; steer freely until the timer runs out.",
	]
	# The attack is a layer on top of the state machine (drawn in its own row under it), not a state.
	const ATTACK_HELP := "Attack (layer): a swing in the held direction (attack key). It runs on top of the current state: while running, dashing (a dash attack), climbing or flying. Not inside bubbles or dream blocks. Lit while swinging."

	func _init() -> void:
		tooltip_text = " "  # non-empty, so Godot asks _get_tooltip

	func _get_tooltip(at: Vector2) -> String:
		var n: int = PlayerScript.STATE_NAMES.size()
		var i := clampi(int(at.y / (size.y / (n + 1))), 0, n)
		if absf(at.x - size.x / 2.0) > HW or player == null:
			return ""
		if i == n:
			return "%s\nSwings this life: %d." % [ATTACK_HELP, player.attack_log.size()]
		var into := 0
		var out := 0
		for key in player.transitions:
			if key.x != key.y:
				into += player.transitions[key] if key.y == i else 0
				out += player.transitions[key] if key.x == i else 0
		return "%s\nEntered %d times, left %d times (this life)." % [HELP[i], into, out]
	func _draw() -> void:
		if player == null:
			return
		var names: Array = PlayerScript.STATE_NAMES
		var cx := size.x / 2.0
		var row := size.y / (names.size() + 1)  # last row: the attack layer
		var ys := []
		for i in names.size():
			ys.append(row * (i + 0.5))
		var font := get_theme_default_font()
		var max_off := cx - HW - 4
		for key in player.transitions:
			if key.x == key.y:
				continue
			var down: bool = key.y > key.x
			var dir := 1.0 if down else -1.0
			var side := 1.0 if down else -1.0
			var x0 := cx + side * HW
			var off := minf(6.0 + 7.0 * absi(key.y - key.x), max_off)
			var y0: float = ys[key.x] + dir * 4
			var y1: float = ys[key.y] - dir * 4
			var dy := minf(off, absf(y1 - y0) / 2.0)
			var pts := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + side * off, y0 + dir * dy),
				Vector2(x0 + side * off, y1 - dir * dy), Vector2(x0, y1)])
			var recent: bool = key.x == player.prev_state and key.y == player.state
			var col := Color("ffd34e") if recent else Color(0.6, 0.65, 0.9, 0.7)
			draw_polyline(pts, col, clampf(1.0 + log(float(player.transitions[key])), 1.0, 3.0))
			var d := (pts[3] - pts[2]).normalized()
			draw_colored_polygon(PackedVector2Array([pts[3], pts[3] - d * 7 + d.orthogonal() * 4, pts[3] - d * 7 - d.orthogonal() * 4]), col)
			var n := str(player.transitions[key])
			var nw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var mid := Vector2(x0 + side * off, (y0 + y1) / 2.0)
			draw_string(font, mid + Vector2(3 if down else -3 - nw, 4), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		for i in names.size():
			var cur: bool = i == player.state
			var col := Color("ffd34e") if cur else (Color(0.45, 0.5, 0.8) if i == player.prev_state else Color(0.2, 0.22, 0.35))
			var box := Rect2(cx - HW, ys[i] - row * 0.36, HW * 2, row * 0.72)
			draw_rect(box, col)
			draw_rect(box, Color.WHITE if cur else Color(0.6, 0.6, 0.7), false, 1.0)
			var label: String = names[i]
			var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(font, Vector2(cx - sz.x / 2, ys[i] + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK if cur else Color.WHITE)
		# attack layer: separate from the states (dashed line), lit while a swing is active
		var ly := row * (names.size() + 0.5)
		for x in range(int(cx - HW - 20), int(cx + HW + 20), 6):
			draw_line(Vector2(x, ly - row * 0.5), Vector2(x + 3, ly - row * 0.5), Color(0.6, 0.6, 0.7, 0.6))
		var on: bool = player.attacking()
		var lbox := Rect2(cx - HW, ly - row * 0.36, HW * 2, row * 0.72)
		draw_rect(lbox, Color("ff8a5c") if on else Color(0.2, 0.22, 0.35))
		draw_rect(lbox, Color.WHITE if on else Color(0.6, 0.6, 0.7), false, 1.0)
		var lt := "Attack (layer)"
		var lsz := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, Vector2(cx - lsz.x / 2, ly + 4), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK if on else Color.WHITE)
