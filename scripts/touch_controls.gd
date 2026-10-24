extends Control
# On-screen controls for phones and tablets. Each finger presses the same input actions as the keyboard,
# so gameplay code needs nothing special. Left: a stick (8 directions). Right: Jump, Dash, Attack, Grab.
# Top right: Pause and Map. Menus need nothing: Godot turns taps into mouse clicks.

# Positions as laid out on a 1280x720 screen; at(): each keeps its distance to the nearest screen edges,
# so on any screen shape the stick hugs the bottom left corner and the buttons the right side.
const STICK_C := Vector2(190, 540)
const STICK_R := 110.0
const DEAD := 30.0
const BUTTONS := [  # action, label, centre, radius
	["jump", "Jump", Vector2(1150, 600), 72.0],
	["dash", "Dash", Vector2(1150, 420), 60.0],
	["attack", "Atk", Vector2(990, 620), 60.0],
	["grab", "Grab", Vector2(990, 460), 54.0],
	["pause", "II", Vector2(1220, 50), 36.0],
	["map", "Map", Vector2(1130, 50), 36.0],
]
const DIRS := ["left", "right", "up", "down"]

var fingers := {}  # touch index -> "stick" or an action name
var stick := Vector2.ZERO  # finger offset from the stick centre
var held_dirs := {}  # direction actions the stick is pressing now

static func wanted() -> bool:
	return DisplayServer.is_touchscreen_available()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _input(event: InputEvent) -> void:
	# hidden: ignore new touches, but still let go of held ones (a lost release would leave a button stuck)
	if not is_visible_in_tree() and not (event is InputEventScreenTouch and not event.pressed):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var what := _hit(event.position)
			if what == "":
				return
			fingers[event.index] = what
			if what == "stick":
				_move_stick(event.position)
			else:
				_send(what, true)
		elif fingers.has(event.index):
			var what: String = fingers[event.index]
			fingers.erase(event.index)
			if what == "stick":
				_move_stick(at(STICK_C))
			elif not fingers.values().has(what):
				_send(what, false)
		else:
			return
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif event is InputEventScreenDrag and fingers.get(event.index, "") == "stick":
		_move_stick(event.position)
		get_viewport().set_input_as_handled()
		queue_redraw()

func at(p: Vector2) -> Vector2:
	return Vector2(p.x if p.x < 640 else size.x - (1280 - p.x), p.y if p.y < 360 else size.y - (720 - p.y))

func _hit(p: Vector2) -> String:
	for b in BUTTONS:
		if p.distance_to(at(b[2])) <= b[3] * 1.2:
			return b[0]
	if p.x < size.x * 0.4 and p.y > size.y * 0.35:  # anywhere in the lower left works as the stick
		return "stick"
	return ""

func _move_stick(p: Vector2) -> void:
	stick = (p - at(STICK_C)).limit_length(STICK_R)
	var on := {}
	if stick.length() > DEAD:
		var a := stick.angle()  # 8 sectors of 45 degrees
		on["right"] = absf(a) < PI * 3 / 8
		on["left"] = absf(a) > PI * 5 / 8
		on["down"] = a > PI / 8 and a < PI * 7 / 8
		on["up"] = a < -PI / 8 and a > -PI * 7 / 8
	for d in DIRS:
		if on.get(d, false) != held_dirs.get(d, false):
			held_dirs[d] = on.get(d, false)
			_send(d, held_dirs[d])

func _send(action: String, on: bool) -> void:  # a real event, so _unhandled_input (pause, map) sees it too
	var e := InputEventAction.new()
	e.action = action
	e.pressed = on
	e.strength = 1.0 if on else 0.0
	Input.parse_input_event(e)

func release_all() -> void:  # when hidden (menus), so nothing stays held
	for a in fingers.values():
		if a != "stick":
			_send(a, false)
	fingers.clear()
	_move_stick(at(STICK_C))
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var sc := at(STICK_C)
	draw_circle(sc, STICK_R, Color(1, 1, 1, 0.08))
	draw_arc(sc, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.3), 3.0)
	draw_circle(sc + stick, 44, Color(1, 1, 1, 0.3 if fingers.values().has("stick") else 0.18))
	for b in BUTTONS:
		var held: bool = fingers.values().has(b[0])
		var c := at(b[2])
		draw_circle(c, b[3], Color(1, 1, 1, 0.3 if held else 0.1))
		draw_arc(c, b[3], 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		var fs := 26 if b[3] > 40 else 20
		var w := font.get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w / 2, fs * 0.35), b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75))
