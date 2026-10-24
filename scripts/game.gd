extends Node
# Autoload "Game": settings, controls, level files, save progress, screen switching.

const Entities := preload("res://scripts/entities.gd")
const Tuning := preload("res://scripts/tuning.gd")
const Adventure := preload("res://scripts/adventure.gd")
const LEVEL_DIR := "user://levels/"
const ADVENTURE_DIR := "res://adventure/"
const WORLDS_DIR := "res://worlds/"  # extra worlds: one folder each with world.json + rooms (docs/WORLD_DESIGN.md)
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"
var save_path := SAVE_PATH  # tests point this at a scratch file

# Art caches live in static vars, which outlive the scene tree: drop them on quit so Godot
# doesn't report the cached textures as leaked at exit.
# They're loaded at runtime here: a const preload in this autoload would itself keep a script alive at exit.
func _exit_tree() -> void:
	load("res://scripts/ape_art.gd")._textures.clear()
	load("res://scripts/environment_art.gd")._textures.clear()
	load("res://scripts/block_art.gd")._textures.clear()
	load("res://scripts/character_art.gd")._textures.clear()
	load("res://scripts/art.gd")._hair_cache.clear()
	load("res://scripts/enemy_art.gd")._texture = null

# Default controls (Celeste keyboard layout + gamepad).
const DEFAULT_KEYS := {
	"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
	"jump": KEY_C, "dash": KEY_X, "grab": KEY_Z, "pause": KEY_ESCAPE,
	"map": KEY_M, "debug": KEY_F1, "attack": KEY_A, "hitboxes": KEY_F2,
	"assist": KEY_F12, "interact": KEY_S,
}
const ALT_KEYS := {"jump": KEY_SPACE, "dash": KEY_SHIFT, "grab": KEY_V}
# Gamepad: one button per action (JOY_BUTTON_*), PAD_AXIS + axis for a trigger, -1 = none.
const PAD_AXIS := 100
const DEFAULT_PAD := {
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
	"jump": JOY_BUTTON_A, "attack": JOY_BUTTON_X, "dash": JOY_BUTTON_RIGHT_SHOULDER,
	"grab": PAD_AXIS + JOY_AXIS_TRIGGER_RIGHT, "pause": JOY_BUTTON_START,
	"map": JOY_BUTTON_BACK, "debug": -1, "hitboxes": -1, "assist": -1, "interact": JOY_BUTTON_B,
}
const PAD_NAMES := {
	JOY_BUTTON_A: "A / Cross", JOY_BUTTON_B: "B / Circle", JOY_BUTTON_X: "X / Square", JOY_BUTTON_Y: "Y / Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1",
	PAD_AXIS + JOY_AXIS_TRIGGER_LEFT: "LT / L2", PAD_AXIS + JOY_AXIS_TRIGGER_RIGHT: "RT / R2",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Back / Select",
	JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Home",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right", -1: "-",
}
const ACTION_NAMES := ["left", "right", "up", "down", "jump", "dash", "grab", "attack", "interact", "pause", "map", "debug", "hitboxes", "assist"]

var main: Node
var sfx: Node
var music_engine: Node
var theme: Theme
var settings := {
	"sfx_volume": 1.0, "music_volume": 1.0,
	"fullscreen": false, "vsync": true, "shake": true, "hitboxes": false,
	"game_speed": 1.0, "infinite_stamina": false, "air_dashes": 0, "invincible": false,
	"keys": DEFAULT_KEYS.duplicate(),
	"pad": DEFAULT_PAD.duplicate(),
	"tuning_preset": "",  # active movement preset in user://tuning/ ("" = project defaults)
	"tuning_open_groups": [],  # debug panel variable groups left open (all collapsed by default)
	"world": "",  # adventure world picked in the menu ("" = the main one in ADVENTURE_DIR)
}
# Player tuning overrides (var name -> value), applied to every new Player. See tuning.gd.
var tuning: Dictionary = {}
# Level being played. playtest = launched from the editor (exit goes back there).
var level: Dictionary = {}
var playtest := false
var editor_level: Dictionary = {}
var editor_dir := LEVEL_DIR  # where the level editor saves (ADVENTURE_DIR when editing a world room)
var editor_file := ""  # fixed file name when editing a world room (renaming must not break world.json)
var editor_return := "menu"  # screen the editor's Menu button goes back to
var adv: Dictionary = {}  # active adventure run (see start_adventure); empty outside it
var adv_world: Dictionary = {}  # Adventure.load_world() result for that run
var adv_temp := false  # world-editor playtest: never saved, exits back to the world editor
var world_path := ADVENTURE_DIR + "world.json"  # tests point this at a scratch file

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(LEVEL_DIR)
	theme = Theme.new()
	theme.default_font_size = 26
	_load_settings()
	apply_settings()
	tuning = Tuning.startup(settings.tuning_preset)
	if settings.world != "" and FileAccess.file_exists(settings.world):
		world_path = settings.world


func get_sfx() -> Node:
	if not is_instance_valid(sfx):
		sfx = load("res://scripts/sfx.gd").new()
		add_child(sfx)
	return sfx

func play_sfx(key: String, pitch: float = 1.0) -> void:
	get_sfx().play(key, pitch)

func get_music_engine() -> Node:
	# SiON has global synthesis state. Keep one driver for the application lifetime.
	if not is_instance_valid(music_engine):
		music_engine = load("res://scripts/music_engine.gd").new()
		add_child(music_engine)
	return music_engine

# ---------- screens ----------
func goto(screen: String) -> void:
	if is_instance_valid(music_engine):
		music_engine.stop()
	for c in main.get_children():
		c.queue_free()
	main.add_child(load("res://scripts/%s.gd" % screen).new())

func play(level_data: Dictionary, from_editor: bool) -> void:
	adv = {}
	level = level_data
	playtest = from_editor
	goto("world")

# ---------- settings ----------
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("s", k, settings[k])
	if not cf.has_section_key("s", "music_volume"):  # saved before the volume sliders: effects start at 100%
		settings.sfx_volume = 1.0
	for a in DEFAULT_KEYS:  # keep any new actions added after the file was saved
		if not settings.keys.has(a):
			settings.keys[a] = DEFAULT_KEYS[a]
		if not settings.pad.has(a):
			settings.pad[a] = DEFAULT_PAD[a]

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("s", k, settings[k])
	cf.save(SETTINGS_PATH)

func apply_settings() -> void:
	if is_instance_valid(sfx):
		sfx.set_volume(float(settings.sfx_volume))
	if is_instance_valid(music_engine):
		music_engine.set_level(float(settings.music_volume))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	_apply_input()

func _apply_input() -> void:
	for a in ACTION_NAMES:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
		else:
			InputMap.add_action(a, 0.3)
		var k := InputEventKey.new()
		k.physical_keycode = settings.keys[a]
		InputMap.action_add_event(a, k)
		if ALT_KEYS.has(a) and ALT_KEYS[a] != settings.keys[a]:
			var k2 := InputEventKey.new()
			k2.physical_keycode = ALT_KEYS[a]
			InputMap.action_add_event(a, k2)
		var pb: int = settings.pad[a]
		if pb >= PAD_AXIS:
			var t := InputEventJoypadMotion.new()
			t.axis = pb - PAD_AXIS
			t.axis_value = 1.0
			InputMap.action_add_event(a, t)
		elif pb >= 0:
			var jb := InputEventJoypadButton.new()
			jb.button_index = pb
			InputMap.action_add_event(a, jb)
	for pair in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = pair[1]
		m.axis_value = pair[2]
		InputMap.action_add_event(pair[0], m)
	# Menus: jump key confirms, dash key goes back (like Celeste), on top of Enter/Esc.
	for m in [["ui_accept", "jump", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], JOY_BUTTON_A], ["ui_cancel", "dash", [KEY_ESCAPE], JOY_BUTTON_B]]:
		InputMap.action_erase_events(m[0])
		for code in m[2] + [settings.keys[m[1]]]:
			var e := InputEventKey.new()
			e.physical_keycode = code
			InputMap.action_add_event(m[0], e)
		var jb := InputEventJoypadButton.new()
		jb.button_index = m[3]
		InputMap.action_add_event(m[0], jb)

func key_name(action: String) -> String:
	return OS.get_keycode_string(settings.keys[action])

func pad_name(action: String) -> String:
	return PAD_NAMES.get(settings.pad[action], "Button %d" % settings.pad[action])

# ---------- levels ----------
static func new_level(level_name := "untitled", w := 40, h := 23) -> Dictionary:
	var rows := []
	for y in h:
		var row := ""
		for x in w:
			row += "1" if (y >= h - 2 or x == 0 or x == w - 1) else "0"
		rows.append(row)
	return {"name": level_name, "w": w, "h": h, "tiles": rows,
		"entities": [{"t": "spawn", "x": 16, "y": (h - 3) * 8}]}

func list_levels() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(LEVEL_DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out

static func file_safe(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	return out if out != "" else "untitled"

func save_level(d: Dictionary, dir := LEVEL_DIR, fname := "") -> String:
	if fname == "":
		fname = file_safe(d.name)
	var f := FileAccess.open(dir + fname + ".json", FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(d, "\t"))
	return fname

func load_level(fname: String, dir := LEVEL_DIR) -> Dictionary:
	var f := FileAccess.open(dir + fname + ".json", FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()  # instance parse: bad JSON returns an error code instead of logging one
	if json.parse(f.get_as_text()) != OK:
		return {}
	return validate_level(json.data, fname)

const MAX_LEVEL_SIZE := 400  # tiles; matches the editor's size spinners
const MAX_COORD := 1 << 20  # pixels; far beyond any level, keeps int() conversion sane

# Normalizes a parsed level in place and returns it, or {} if anything is malformed.
static func validate_level(d, fallback_name := "untitled") -> Dictionary:
	if not d is Dictionary:
		return {}
	var environment = d.get("environment", "")
	if not environment is String or (environment != "" and environment not in load("res://scripts/environment_art.gd").THEMES):
		return {}
	var w = d.get("w")
	var h = d.get("h")
	if not (_is_whole(w) and _is_whole(h)):
		return {}
	var name = d.get("name", fallback_name)
	var tiles = d.get("tiles")
	var ents = d.get("entities")
	if not name is String or not tiles is Array or tiles.size() != h or not ents is Array:
		return {}
	var tile_re := RegEx.create_from_string("^[01]*$")
	for row in tiles:
		if not row is String or row.length() != w or tile_re.search(row) == null:
			return {}
	for e in ents:
		if not e is Dictionary or not e.get("t") is String or not Entities.TYPES.has(e.t):
			return {}
		if not (_is_num(e.get("x"), -MAX_COORD, MAX_COORD) and _is_num(e.get("y"), -MAX_COORD, MAX_COORD)):
			return {}
		for k in ["tx", "ty"]:  # optional
			if e.has(k) and not _is_num(e[k], -MAX_COORD, MAX_COORD):
				return {}
		# entity draw/build loops walk every 8px cell, so sizes must stay level-sized
		if e.has("text") and not (e.text is String and e.text.length() <= 500):  # optional (notes)
			return {}
		for k in ["id", "to"]:  # optional (doors)
			if e.has(k) and not (e[k] is String and e[k].length() <= 100):
				return {}
		for k in ["w", "h"]:  # optional
			if e.has(k) and not _is_num(e[k], 1, MAX_LEVEL_SIZE * 8):
				return {}
		if e.has("hp") and not _is_num(e.hp, 1, 99):  # optional (breakable walls)
			return {}
		for k in ["facing", "patrol"]:  # optional (enemies)
			if e.has(k) and not _is_num(e[k], -MAX_COORD, MAX_COORD):
				return {}
		if e.has("top") and not e.top is bool:  # optional (liquids)
			return {}
	d.name = name
	d.w = int(w)
	d.h = int(h)
	return d

# NaN fails both comparisons, so this also rejects non-finite values.
static func _is_num(v, lo: float, hi: float) -> bool:
	return (v is float or v is int) and v >= lo and v <= hi

static func _is_whole(v) -> bool:
	return _is_num(v, 1, MAX_LEVEL_SIZE) and v == floor(v)

func delete_level(fname: String) -> void:
	DirAccess.remove_absolute(LEVEL_DIR + fname + ".json")

# ---------- adventure ----------
# One run per world; saved under [adventure] in the save file. Empty adv = not in the adventure.
func has_adventure_save() -> bool:
	var cf := ConfigFile.new()
	cf.load(save_path)
	return cf.has_section_key("adventure", _run_key())

# "run" for the main world (older saves keep working), "run_<folder>" for the others.
func _run_key() -> String:
	return "run" if world_path == ADVENTURE_DIR + "world.json" else "run_" + world_path.get_base_dir().get_file()

# [[title, world.json path]]: the main world first, then every folder in WORLDS_DIR.
func world_list() -> Array:
	var out := [["Summit", ADVENTURE_DIR + "world.json"]]
	for d in DirAccess.get_directories_at(WORLDS_DIR):
		var p := WORLDS_DIR + d + "/world.json"
		if FileAccess.file_exists(p):
			out.append([d.capitalize(), p])
	return out

func start_adventure(fresh: bool) -> void:
	adv_world = Adventure.load_world(world_path)
	if adv_world.rooms.is_empty():
		return
	var cf := ConfigFile.new()
	cf.load(save_path)
	var run = cf.get_value("adventure", _run_key()) if cf.has_section_key("adventure", _run_key()) else null
	adv = Adventure.new_run(adv_world) if fresh else Adventure.restore_run(adv_world, run)
	adv_temp = false
	_enter_adventure()

# World-editor playtest: a throwaway run from any room that is never saved.
func playtest_adventure(world: Dictionary, room: String) -> void:
	adv_world = world
	adv = Adventure.new_run(world)
	adv.room = room
	adv.visited = [room]
	adv_temp = true
	_enter_adventure()

func _enter_adventure() -> void:
	level = adv_world.rooms[adv.room].level
	playtest = false
	goto("world")

func save_adventure() -> void:
	if adv.is_empty() or adv_temp:
		return
	var cf := ConfigFile.new()
	cf.load(save_path)
	cf.set_value("adventure", _run_key(), adv)
	cf.save(save_path)

# Outside the adventure every move is available.
func has_ability(a: String) -> bool:
	return adv.is_empty() or adv.abilities.has(a)

# ---------- progress ----------
func get_record(fname: String) -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(save_path)
	return cf.get_value("levels", fname, {})

func submit_record(fname: String, time: float, deaths: int, berries: int, total: int) -> void:
	var cf := ConfigFile.new()
	cf.load(save_path)
	var r: Dictionary = cf.get_value("levels", fname, {})
	r.best_time = min(r.get("best_time", INF), time)
	r.berries = max(r.get("berries", 0), berries)
	r.total = total
	r.fewest_deaths = min(r.get("fewest_deaths", 1 << 30), deaths)
	r.clears = r.get("clears", 0) + 1
	cf.set_value("levels", fname, r)
	cf.save(save_path)

static func fmt_time(t: float) -> String:
	var m := int(t) / 60
	return "%d:%02d.%03d" % [m, int(t) % 60, int(t * 1000) % 1000]

# ---------- small UI helpers shared by menus ----------
func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): play_sfx("ui"))
	b.pressed.connect(cb)
	return b

func label(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
