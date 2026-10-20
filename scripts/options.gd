extends ColorRect
# Options screen: video, assist mode and key remapping. Used by the main menu and the pause menu.

signal closed

var waiting_for := ""  # action being rebound
var key_buttons := {}

func _ready() -> void:
	color = Color(0.05, 0.05, 0.12, 0.95)
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

	box.add_child(Game.label("Options", 44))
	box.add_child(Game.label("Video", 22))
	var first := _toggle(box, "Fullscreen", "fullscreen")
	_toggle(box, "VSync", "vsync")
	_toggle(box, "Screen Shake", "shake")

	box.add_child(Game.label("Assist Mode", 22))
	_choice(box, "Game Speed", "game_speed", ["50%", "60%", "70%", "80%", "90%", "100%"], [0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
	_toggle(box, "Infinite Stamina", "infinite_stamina")
	_choice(box, "Air Dashes", "air_dashes", ["Default", "Two", "Infinite"], [0, 1, 2])
	_toggle(box, "Invincibility", "invincible")

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

func _choice(box: VBoxContainer, text: String, key: String, labels: Array, values: Array) -> void:
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

func _apply(key: String, v) -> void:
	Game.settings[key] = v
	Game.apply_settings()
	Game.save_settings()

func _rebind(action: String) -> void:
	waiting_for = action
	key_buttons[action].text = "Press a key..."

func _input(event: InputEvent) -> void:
	if waiting_for == "" or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	Game.settings.keys[waiting_for] = event.physical_keycode
	key_buttons[waiting_for].text = Game.key_name(waiting_for)
	waiting_for = ""
	Game.apply_settings()
	Game.save_settings()

func _reset_keys() -> void:
	Game.settings.keys = Game.DEFAULT_KEYS.duplicate()
	for a in key_buttons:
		key_buttons[a].text = Game.key_name(a)
	Game.apply_settings()
	Game.save_settings()

func _unhandled_input(event: InputEvent) -> void:
	if waiting_for == "" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
