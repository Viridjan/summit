extends ColorRect
## Standalone music playground, deliberately separate from gameplay.

const MusicEngine := preload("res://scripts/music_engine.gd")
const CHANNELS := ["LEAD", "HARMONY", "BASS", "DRUMS"]
const PITCHES := [-1, 0, 2, 4, 5, 7, 9, 11, 12]
const BASES := [72, 60, 48, 48]

var engine: Node
var cells: Array = []
var transport: Button
var status: Label
var page := 0
var page_button: Button
var theme_picker: OptionButton
var tempo: SpinBox
var instrument_pickers: Array[OptionButton] = []
var mute_buttons: Array[CheckButton] = []
var scenery: TextureRect

func _ready() -> void:
	color = Color("141433")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Game.theme.duplicate()
	theme.default_font_size = 20
	engine = Game.get_music_engine()
	scenery = TextureRect.new()
	scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scenery.modulate = Color(0.6, 0.6, 0.6, 0.45)
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scenery)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	body.add_child(Game.label("MUSIC STUDIO", 36))
	var selection := HBoxContainer.new()
	body.add_child(selection)
	var themes := OptionButton.new()
	theme_picker = themes
	themes.add_item("Demo")
	for title in MusicEngine.EnvironmentMusic.TITLES:
		themes.add_item(title)
	if engine.title != "Demo":
		themes.select(MusicEngine.EnvironmentMusic.KEYS.find(engine.environment) + 1)
	themes.item_selected.connect(_select_environment)
	selection.add_child(themes)
	page_button = Game.button("", _next_page)
	selection.add_child(page_button)
	var controls := HBoxContainer.new()
	body.add_child(controls)
	transport = Game.button("Play", _toggle_play)
	controls.add_child(transport)
	controls.add_child(Game.label("  BPM ", 20))
	tempo = SpinBox.new()
	tempo.min_value = 40
	tempo.max_value = 240
	tempo.value = engine.bpm
	tempo.value_changed.connect(func(value: float):
		engine.bpm = int(value)
		_changed())
	controls.add_child(tempo)
	controls.add_child(Game.label("  Volume ", 20))
	var volume := HSlider.new()
	volume.custom_minimum_size.x = 180
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = engine.volume
	volume.value_changed.connect(func(value: float):
		engine.volume = value
		engine.driver.volume = value)
	controls.add_child(volume)
	controls.add_child(Game.button("Reset demo", func():
		themes.select(0)
		engine.load_demo()
		page = 0
		_refresh()
		_changed()))
	body.add_child(HSeparator.new())
	for channel in 4:
		var row := HBoxContainer.new()
		body.add_child(row)
		var name_label := Game.label(CHANNELS[channel], 20)
		name_label.custom_minimum_size.x = 140
		row.add_child(name_label)
		var instrument := OptionButton.new()
		for title in MusicEngine.INSTRUMENT_NAMES:
			instrument.add_item(title)
		instrument.select(engine.instruments[channel])
		instrument.item_selected.connect(func(index: int):
			engine.instruments[channel] = index
			_changed())
		row.add_child(instrument)
		instrument_pickers.append(instrument)
		var mute := CheckButton.new()
		mute.text = "Mute"
		mute.toggled.connect(func(value: bool):
			engine.muted[channel] = value
			_changed())
		row.add_child(mute)
		mute_buttons.append(mute)
		var grid := GridContainer.new()
		grid.columns = 16
		body.add_child(grid)
		var channel_cells: Array[Button] = []
		for step in 16:
			var cell := Game.button("", _cycle.bind(channel, step))
			cell.custom_minimum_size = Vector2(62, 36)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_font_size_override("font_size", 18)
			cell.tooltip_text = "Step %d: cycle rest / C major notes" % (step + 1)
			grid.add_child(cell)
			channel_cells.append(cell)
		cells.append(channel_cells)
	status = Game.label("Stopped", 18)
	body.add_child(status)
	body.add_child(Game.label("Click a step to cycle its note. Changes restart the loop.\nPulse / triangle / noise for 8-bit sounds; try FM piano for a richer palette.", 18))
	body.add_child(Game.button("Back to menu", _back))
	_refresh()
	transport.grab_focus()

func _cycle(channel: int, step: int) -> void:
	step += page * 16
	var note: int = engine.patterns[channel][step]
	var pitch: int = -1 if note < 0 else note - BASES[channel]
	var index := PITCHES.find(pitch)
	var next_pitch: int = PITCHES[(index + 1) % PITCHES.size()]
	engine.patterns[channel][step] = -1 if next_pitch < 0 else BASES[channel] + next_pitch
	_refresh()
	_changed()

func _select_environment(index: int) -> void:
	if index == 0:
		engine.load_demo()
	else:
		engine.load_environment(MusicEngine.EnvironmentMusic.KEYS[index - 1])
	page = 0
	_refresh()
	_changed()

func _next_page() -> void:
	page = (page + 1) % maxi(1, engine.patterns[0].size() / 16)
	_refresh()

func _refresh() -> void:
	theme_picker.select(0 if engine.title == "Demo" else MusicEngine.EnvironmentMusic.KEYS.find(engine.environment) + 1)
	tempo.set_value_no_signal(engine.bpm)
	page_button.text = "Steps %d–%d / %d  >" % [page * 16 + 1, page * 16 + 16, engine.patterns[0].size()]
	var path := "res://assets/themes/%s/background.png" % engine.environment
	scenery.texture = load(path) if engine.environment != "" and ResourceLoader.exists(path) else null
	status.text = ("Playing · " if engine.playing else "Stopped · ") + engine.title
	for channel in 4:
		instrument_pickers[channel].select(engine.instruments[channel])
		mute_buttons[channel].set_pressed_no_signal(engine.muted[channel])
		for step in 16:
			var note: int = engine.patterns[channel][page * 16 + step]
			var cell: Button = cells[channel][step]
			cell.text = "·" if note < 0 else "%s%d" % [MusicEngine.NOTE_NAMES[note % 12].to_upper().replace("+", "#"), note / 12 - 1]
			cell.modulate = Color("72728c") if note < 0 else Color("88e8dc")

func _changed() -> void:
	if engine.playing:
		engine.play()

func _toggle_play() -> void:
	if engine.playing:
		engine.stop()
	else:
		engine.play()
	transport.text = "Stop" if engine.playing else "Play"
	status.text = ("Playing · " if engine.playing else "Stopped · ") + engine.title

func _back() -> void:
	engine.stop()
	Game.goto("menu")

func _exit_tree() -> void:
	if not is_instance_valid(Game.main) or Game.main.get_child_count() == 0 or Game.main.get_child(Game.main.get_child_count() - 1) == self:
		engine.stop()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
