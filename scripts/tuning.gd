extends RefCounted
# Player movement tuning: which Player variables are editable, their groups/ranges,
# and named presets on disk (ConfigFile, section "player", one key per variable).
# Startup: code defaults -> res://config/tuning.cfg (project) -> active user preset.

const PlayerScript := preload("res://scripts/player.gd")
const PRESET_DIR := "user://tuning/"
const PROJECT_FILE := "res://config/tuning.cfg"
# recomputed by Player.apply_tuning(), shown read-only
const DERIVED := ["WALL_JUMP_H_SPEED", "SUPER_WALL_JUMP_H", "STAR_FLY_SLOW_SPEED"]
# Mouse-over help for the debug panel. Units: px = pixels (8 per tile), s = seconds, px/s = speed, px/s² = acceleration.
# Negative Y is up.
const HELP := {
	"MAX_FALL": "Normal top falling speed (px/s).",
	"GRAVITY": "Downward acceleration (px/s²).",
	"HALF_GRAV_THRESHOLD": "Near the top of a jump (vertical speed below this, px/s) gravity is halved while jump is held: floatier apex.",
	"FAST_MAX_FALL": "Top falling speed while holding down (fast fall, px/s).",
	"FAST_MAX_ACCEL": "How quickly fall speed rises toward the fast-fall limit when holding down (px/s²).",
	"MAX_RUN": "Top running speed (px/s).",
	"RUN_ACCEL": "Acceleration toward run speed (px/s²).",
	"RUN_REDUCE": "Deceleration when above top speed while still holding that direction (px/s²); keeps momentum from dashes/boosts longer.",
	"AIR_MULT": "Multiplier on run acceleration/deceleration while in the air.",
	"DUCK_FRICTION": "Slowdown while ducking on the ground (px/s²).",
	"DUCK_CORRECT_CHECK": "How far (px) to look sideways for room to stand up when ducking under a low ceiling.",
	"DUCK_CORRECT_SLIDE": "Speed of that sideways slide toward room to stand (px/s).",
	"DODGE_SLIDE_SPEED_MULT": "Horizontal speed multiplier when a down-diagonal dash hits the ground (wavedash setup).",
	"DUCK_SUPER_JUMP_X_MULT": "Horizontal multiplier for a super jump done while ducking (hyper jump).",
	"DUCK_SUPER_JUMP_Y_MULT": "Vertical multiplier for a hyper jump (lower, longer jump).",
	"JUMP_GRACE_TIME": "Coyote time: how long after leaving the ground a jump still works (s).",
	"JUMP_SPEED": "Upward speed of a normal jump (px/s, negative = up).",
	"JUMP_H_BOOST": "Extra horizontal speed added when jumping while moving (px/s).",
	"VAR_JUMP_TIME": "How long holding jump keeps the upward speed (variable jump height, s).",
	"CEILING_VAR_JUMP_GRACE": "Bumping a ceiling this soon after jumping (s) doesn't cancel the jump hold.",
	"UPWARD_CORNER_CORRECTION": "Hitting a ceiling corner while rising slides you sideways up to this many px to get past it.",
	"WALL_SPEED_RETENTION_TIME": "After running into a wall, how long (s) your speed is remembered and restored if the wall clears.",
	"WALL_JUMP_CHECK_DIST": "Max distance (px) to a wall for a wall jump.",
	"WALL_JUMP_FORCE_TIME": "After a wall jump, how long (s) horizontal movement is forced away from the wall.",
	"WALL_SLIDE_START_MAX": "Fall speed at the start of a wall slide (px/s); it grows back to max_fall over wall_slide_time.",
	"WALL_SLIDE_TIME": "How long (s) a wall slide stays slowed before reaching full fall speed.",
	"BOUNCE_VAR_JUMP_TIME": "Jump-hold time after a normal bounce (s). Ported from Celeste; no object in this game uses bounce() yet.",
	"BOUNCE_SPEED": "Upward speed of a normal bounce (px/s). Unused until an object calls bounce().",
	"BOUNCE_AUTO_JUMP_TIME": "After a normal bounce, how long (s) it behaves as if jump were held. Unused until an object calls bounce().",
	"SUPER_BOUNCE_VAR_JUMP_TIME": "Jump-hold time after an up-spring (s).",
	"SUPER_BOUNCE_SPEED": "Upward speed from an up-spring (px/s).",
	"SUPER_JUMP_H": "Horizontal speed of a super jump (jump during a sideways dash on the ground, px/s).",
	"SUPER_WALL_JUMP_SPEED": "Upward speed of a super wall jump (jump off a wall during an up-dash, px/s).",
	"SUPER_WALL_JUMP_VAR_TIME": "Jump-hold time of a super wall jump (s).",
	"SIDE_BOUNCE_SPEED": "Horizontal speed from a side spring (px/s).",
	"SIDE_BOUNCE_FORCE_TIME": "How long (s) a side spring forces your horizontal direction.",
	"DASH_SPEED": "Speed during a dash (px/s).",
	"END_DASH_SPEED": "Speed left over when a dash ends (px/s).",
	"END_DASH_UP_MULT": "Extra multiplier on that leftover speed for upward dashes.",
	"DASH_TIME": "Dash duration (s).",
	"DASH_COOLDOWN": "Minimum time between dashes (s).",
	"DASH_REFILL_COOLDOWN": "After dashing, how long (s) before touching the ground can refill dashes.",
	"DASH_H_JUMPTHRU_NUDGE": "A sideways dash this close (px) below a jump-through's top pops you up onto it.",
	"DASH_CORNER_CORRECTION": "Dashing into a corner slides you around it by up to this many px.",
	"DASH_V_FLOOR_SNAP_DIST": "A sideways dash this close (px) above the floor snaps down onto it.",
	"DASH_ATTACK_TIME": "How long (s) after a dash starts it still counts as a dash attack (objects that react to dashes, floor snap).",
	"BOOST_MOVE_SPEED": "How fast a bubble pulls you to its centre before launching (px/s).",
	"BOOST_TIME": "How long (s) you sit in a bubble before it dashes you out automatically.",
	"REBOUND_SPEED_X": "Horizontal speed of a rebound (px/s). Ported from Celeste; no object in this game uses rebound() yet.",
	"REBOUND_SPEED_Y": "Upward speed of a rebound (px/s). Unused until an object calls rebound().",
	"REBOUND_VAR_JUMP_TIME": "Jump-hold time after a rebound (s).",
	"DREAM_DASH_MIN_TIME": "Minimum time (s) inside a dream block before you can exit.",
	"DREAM_DASH_END_WIGGLE": "When leaving a dream block into a wall, search this many px around for a free spot.",
	"CLIMB_MAX_STAMINA": "Stamina when full (climbing drains it).",
	"CLIMB_UP_COST": "Stamina used per second while climbing up.",
	"CLIMB_STILL_COST": "Stamina used per second while holding still on a wall.",
	"CLIMB_JUMP_COST": "Stamina used by a climb jump (jumping straight up while grabbing).",
	"CLIMB_CHECK_DIST": "Max distance (px) to a wall to grab it.",
	"CLIMB_UP_CHECK_DIST": "When grabbing, you can be shifted up by this many px to catch a wall edge.",
	"CLIMB_NO_MOVE_TIME": "Right after grabbing, how long (s) climbing input is ignored.",
	"CLIMB_TIRED_THRESHOLD": "Below this stamina you're tired: hair flashes, and you slip if it runs out.",
	"CLIMB_UP_SPEED": "Climbing up speed (px/s, negative = up).",
	"CLIMB_DOWN_SPEED": "Climbing down speed (px/s).",
	"CLIMB_SLIP_SPEED": "Slide-down speed when out of stamina or on a slippery wall (px/s).",
	"CLIMB_ACCEL": "Acceleration toward the climb speed (px/s²).",
	"CLIMB_GRAB_Y_MULT": "Vertical speed is multiplied by this when you grab a wall (catches falls).",
	"CLIMB_HOP_Y": "Upward speed of the hop over a wall's top edge (px/s).",
	"CLIMB_HOP_X": "Forward speed of that hop (px/s).",
	"CLIMB_HOP_FORCE_TIME": "How long (s) the hop forces forward movement.",
	"CLIMB_JUMP_BOOST_TIME": "After a climb jump, a window (s) to push away from the wall and get a wall jump's speed (refunds stamina).",
	"LAUNCH_SPEED": "Speed when launched by a bumper (px/s).",
	"LAUNCH_CANCEL_THRESHOLD": "The launch state ends once speed drops below this (px/s).",
	"LIFT_Y_CAP": "Max upward speed inherited from a moving platform when jumping off it (px/s).",
	"LIFT_X_CAP": "Max horizontal speed inherited from a moving platform (px/s).",
	"LIFT_SPEED_GRACE": "How long (s) after leaving a moving platform its speed can still be inherited.",
	"JUMPTHRU_ASSIST_SPEED": "Upward nudge speed that pops you onto a jump-through when you're barely below its top (px/s).",
	"HIT_SQUASH_NO_MOVE_TIME": "After a dash into a ceiling/floor squashes you, how long (s) before you can move.",
	"HIT_SQUASH_FRICTION": "Slowdown during that squash (px/s²).",
	"STAR_FLY_TRANSFORM_DECCEL": "Feather: slowdown during the short transform before flying (px/s²).",
	"STAR_FLY_TIME": "Feather flight duration (s).",
	"STAR_FLY_START_SPEED": "Feather: speed when flight begins (px/s).",
	"STAR_FLY_TARGET_SPEED": "Feather: cruising speed while steering (px/s).",
	"STAR_FLY_MAX_SPEED": "Feather: top speed when holding a direction (px/s).",
	"STAR_FLY_MAX_LERP_TIME": "Feather: time (s) to ramp from cruising to top speed.",
	"STAR_FLY_ACCEL": "Feather: acceleration toward the target speed (px/s²).",
	"STAR_FLY_ROTATE_SPEED": "Feather: turning rate (radians/s).",
	"STAR_FLY_END_FLASH": "Feather: hair starts flashing when this much flight time (s) is left.",
	"STAR_FLY_END_NO_BOUNCE": "Feather: in the last this-many s, hitting a wall stops you instead of bouncing.",
	"STAR_FLY_WALL_BOUNCE": "Feather: speed multiplier when bouncing off a wall (negative reverses).",
	"STAR_FLY_MAX_EXIT_Y": "Feather: max vertical speed when flight ends (px/s; 0 = can't keep rising).",
	"STAR_FLY_MAX_EXIT_X": "Feather: max horizontal speed when flight ends (px/s).",
	"STAR_FLY_EXIT_UP": "Feather: upward speed if you end flight holding up (px/s).",
	"INPUT_BUFFER": "Jump/dash/attack presses are remembered this long (s) so slightly early presses still count.",
	"ATTACK_TIME": "How long (s) one swing lasts; things are hit at any point during it.",
	"ATTACK_COOLDOWN": "Minimum time (s) from the start of one swing to the next.",
	"ATTACK_RANGE": "Reach of the swing from the player's centre (px).",
	"ATTACK_ARC": "Width of the swing (degrees), centred on the direction held (or facing).",
	"DASH_DIRS": "Dash directions: 0 no dash, 1 horizontal only, -1 vertical only, 2 horizontal + vertical, 3 + diagonals (8-way), 4 free aim (analog stick).",
	"ATTACK_DIRS": "Attack directions: 0 no attack, 1 horizontal only, -1 vertical only, 2 horizontal + vertical, 3 + diagonals (8-way), 4 free aim (analog stick).",
	"WALL_JUMP_H_SPEED": "Derived: max_run + jump_h_boost. Horizontal speed of a wall jump (px/s).",
	"SUPER_WALL_JUMP_H": "Derived: max_run + 2 × jump_h_boost. Horizontal speed of a super wall jump (px/s).",
	"STAR_FLY_SLOW_SPEED": "Derived: 0.65 × star_fly_target_speed. Feather speed when holding no direction (px/s).",
}

# group name, name prefixes; first match wins, so specific prefixes come first
const GROUPS := [
	["Gravity & Fall", ["MAX_FALL", "GRAVITY", "HALF_GRAV", "FAST_MAX"]],
	["Run", ["MAX_RUN", "RUN_", "AIR_MULT"]],
	["Duck", ["DUCK_", "DODGE_"]],
	["Wall", ["WALL_", "SUPER_WALL_"]],
	["Bounce & Springs", ["BOUNCE_", "SUPER_BOUNCE_", "SIDE_BOUNCE_", "SUPER_JUMP_", "REBOUND_"]],
	["Jump", ["JUMP_", "VAR_JUMP", "CEILING_", "UPWARD_", "JUMPTHRU_"]],
	["Dash", ["DASH_", "END_DASH_"]],
	["Boost & Launch", ["BOOST_", "LAUNCH_"]],
	["Climb", ["CLIMB_"]],
	["Dream Block", ["DREAM_"]],
	["Feather", ["STAR_FLY_"]],
	["Lift", ["LIFT_"]],
	["Hit Squash", ["HIT_"]],
	["Attack", ["ATTACK_"]],
	["Input", ["INPUT_"]],
]

static var _defaults := {}

# name -> default value, in declaration order (includes derived)
static func defaults() -> Dictionary:
	if _defaults.is_empty():
		var p = PlayerScript.new(null, Vector2.ZERO)
		for prop in p.get_property_list():
			var n: String = prop.name
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and n == n.to_upper() and (p.get(n) is float or p.get(n) is int):
				_defaults[n] = p.get(n)
	return _defaults

static func names() -> Array:
	return defaults().keys().filter(func(n): return not n in DERIVED)

static func group_of(n: String) -> String:
	for g in GROUPS:
		for pre in g[1]:
			if n.begins_with(pre):
				return g[0]
	return "Other"

# [min, max, step] for the editor spin box
static func range_of(n: String) -> Array:
	var d = defaults()[n]
	if n.ends_with("_DIRS"):
		return [-1, 4, 1]
	var hi := maxf(absf(d) * 4.0, 1.0)
	var step := 1.0 if d is int else (0.001 if absf(d) < 1.0 else 0.1)
	return [-hi, hi, step]

static func coerce(n: String, v):
	return int(v) if defaults()[n] is int else float(v)

# Current value of every tunable: defaults with overrides applied.
static func current(overrides: Dictionary) -> Dictionary:
	var out := {}
	for n in names():
		out[n] = overrides.get(n, defaults()[n])
	return out

# Only the known tunables from a file, typed like their defaults. {} if unreadable.
static func load_file(path: String) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return {}
	var out := {}
	for n in names():
		var v = cf.get_value("player", n) if cf.has_section_key("player", n) else null  # a null default still logs an error
		if v is float or v is int:
			out[n] = coerce(n, v)
	return out

static func save_file(path: String, values: Dictionary) -> bool:
	var cf := ConfigFile.new()
	for n in names():
		cf.set_value("player", n, values.get(n, defaults()[n]))
	return cf.save(path) == OK

static func preset_path(preset: String) -> String:
	return PRESET_DIR + Game.file_safe(preset) + ".cfg"

static func list_presets() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(PRESET_DIR):
		if f.ends_with(".cfg"):
			out.append(f.get_basename())
	out.sort()
	return out

static func save_preset(preset: String, overrides: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	return save_file(preset_path(preset), current(overrides))

static func delete_preset(preset: String) -> void:
	DirAccess.remove_absolute(preset_path(preset))

# res:// is only writable when running from the Godot editor / a source checkout.
static func can_export() -> bool:
	return OS.has_feature("editor")

static func export_project(overrides: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(PROJECT_FILE.get_base_dir())
	return save_file(PROJECT_FILE, current(overrides))

# Overrides used at startup: project file, then the active user preset on top.
static func startup(active_preset: String) -> Dictionary:
	var out := load_file(PROJECT_FILE)
	if active_preset != "":
		out.merge(load_file(preset_path(active_preset)), true)
	return out
