extends ColorRect
# Options screen: video and key remapping. Used by the main menu and the pause menu.
# With pad_page set it is the controller button page instead (opened from "Controller Buttons").
# With assist_page set it is the Assist Mode page instead (opened in game with the assist key, F12).

signal closed

var waiting_for := ""  # action being rebound
var key_buttons := {}
var pad_page := false
var assist_page := false

func _ready() -> void:
	color = Color(0.05, 0.05, 0.12, 1.0 if pad_page else 0.95)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Game.theme
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)

	if pad_page:
		_build_pad(box)
		return
	if assist_page:
		_build_assist(box)
		return
	box.add_child(Game.label("Options", 44))
	box.add_child(Game.label("Video", 22))
	var first := _toggle(box, "Fullscreen", "fullscreen")
	_toggle(box, "VSync", "vsync")
	_toggle(box, "Screen Shake", "shake")

	box.add_child(Game.label("Audio", 22))
	_slider(box, "Music", "music_volume")
	_slider(box, "Sound Effects", "sfx_volume")

	box.add_child(Game.label("Controls (keyboard)", 22))
	for a in Game.ACTION_NAMES:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = a.capitalize()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Game.button(Game.key_name(a), _rebind.bind(a))
		b.custom_minimum_size = Vector2(200, 0)
		row.add_child(b)
		key_buttons[a] = b
		box.add_child(row)
	box.add_child(Game.button("Reset Controls", _reset_keys))
	var pad_btn := Game.button("Controller Buttons", func(): pass)
	pad_btn.pressed.connect(_open_pad.bind(pad_btn))
	box.add_child(pad_btn)
	box.add_child(Game.button("Back", _close))
	first.grab_focus()

func _open_pad(from: Button) -> void:
	var o: Control = (get_script() as GDScript).new()
	o.pad_page = true
	add_child(o)
	o.closed.connect(from.grab_focus)

func _build_assist(box: VBoxContainer) -> void:
	box.add_child(Game.label("Assist Mode", 44))
	var first := _choice(box, "Game Speed", "game_speed", ["50%", "60%", "70%", "80%", "90%", "100%"], [0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
	_toggle(box, "Infinite Stamina", "infinite_stamina")
	_choice(box, "Air Dashes", "air_dashes", ["Default", "Two", "Infinite"], [0, 1, 2])
	_toggle(box, "Invincibility", "invincible")
	_toggle(box, "Show Hitboxes", "hitboxes")
	box.add_child(Game.button("Back", _close))
	first.grab_focus()

func _build_pad(box: VBoxContainer) -> void:
	box.add_child(Game.label("Controller Buttons", 44))
	box.add_child(Game.label("Pick an action, then press a button or trigger. The left stick always moves.", 16))
	var first: Button = null
	for a in Game.ACTION_NAMES:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = a.capitalize()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Game.button(Game.pad_name(a), _rebind.bind(a))
		b.custom_minimum_size = Vector2(240, 0)
		row.add_child(b)
		key_buttons[a] = b
		box.add_child(row)
		if first == null:
			first = b
	box.add_child(Game.button("Reset Buttons", _reset_keys))
	box.add_child(Game.button("Back", _close))
	first.grab_focus()

func _toggle(box: VBoxContainer, text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = Game.settings[key]
	# spell the state out: the switch icon alone is too small to read
	var show := func(v: bool):
		c.text = "%s:  %s" % [text, "ON" if v else "OFF"]
		for k in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
			c.add_theme_color_override(k, Color("ffd34e") if v else Color(0.75, 0.75, 0.8))
	show.call(c.button_pressed)
	c.toggled.connect(func(v: bool):
		show.call(v)
		_apply(key, v))
	box.add_child(c)
	return c

func _choice(box: VBoxContainer, text: String, key: String, labels: Array, values: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	for s in labels:
		o.add_item(s)
	o.selected = maxi(values.find(Game.settings[key]), 0)
	o.item_selected.connect(func(i: int): _apply(key, values[i]))
	row.add_child(o)
	box.add_child(row)
	return o

# 0..100% in steps of 5; the setting stores 0..1.
func _slider(box: VBoxContainer, text: String, key: String) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.custom_minimum_size = Vector2(240, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.step = 5
	s.value = roundf(float(Game.settings[key]) * 100.0)
	var show := func(v: float): l.text = "%s:  %d%%" % [text, v]
	show.call(s.value)
	s.value_changed.connect(func(v: float):
		show.call(v)
		_apply(key, v / 100.0))
	row.add_child(s)
	box.add_child(row)
	return s

func _apply(key: String, v) -> void:
	Game.settings[key] = v
	Game.apply_settings()
	Game.save_settings()

func _rebind(action: String) -> void:
	waiting_for = action
	key_buttons[action].text = "Press a button..." if pad_page else "Press a key..."

func _input(event: InputEvent) -> void:
	if waiting_for == "":
		return
	var code := -2
	if pad_page:
		if event is InputEventJoypadButton and event.pressed:
			code = event.button_index
		elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.6:
			code = Game.PAD_AXIS + event.axis
		elif event is InputEventKey and event.pressed:  # any key cancels
			get_viewport().set_input_as_handled()
			key_buttons[waiting_for].text = Game.pad_name(waiting_for)
			waiting_for = ""
			return
	elif event is InputEventKey and event.pressed:
		code = event.physical_keycode
	if code == -2:
		return
	get_viewport().set_input_as_handled()
	if pad_page:
		Game.settings.pad[waiting_for] = code
		key_buttons[waiting_for].text = Game.pad_name(waiting_for)
	else:
		Game.settings.keys[waiting_for] = code
		key_buttons[waiting_for].text = Game.key_name(waiting_for)
	waiting_for = ""
	Game.apply_settings()
	Game.save_settings()

func _reset_keys() -> void:
	if pad_page:
		Game.settings.pad = Game.DEFAULT_PAD.duplicate()
	else:
		Game.settings.keys = Game.DEFAULT_KEYS.duplicate()
	for a in key_buttons:
		key_buttons[a].text = Game.pad_name(a) if pad_page else Game.key_name(a)
	Game.apply_settings()
	Game.save_settings()

func _unhandled_input(event: InputEvent) -> void:
	if waiting_for == "" and (event.is_action_pressed("ui_cancel") or (assist_page and event.is_action_pressed("assist"))):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
