extends RefCounted
# Player movement and animation, stored as an ordinary object rather than a scene node.
# World owns this object and calls update(dt) once per physics step, then draw() when needed.
# Coordinates: +X is right, +Y is down; speed is pixels/second and dt is elapsed seconds.
# pos is the character's feet (bottom centre), not the top-left of the sprite.
# Movement checks whole pixels against World; rem saves fractions so slow movement is not lost.
# The state machine chooses one movement mode at a time; water effects can also layer on top.
# See docs/CODE_GUIDE.md for a reading order and explanations of the Godot vocabulary.
# Reading help: docs/CODE_GUIDE.md.

const Art := preload("res://scripts/art.gd")
const CharacterArt := preload("res://scripts/character_art.gd")
# Player controller: a GDScript port of Celeste's Player.cs
# (MIT, Maddy Makes Games - https://github.com/NoelFB/Celeste).
# Units are pixels and seconds, the same as the original, so values match 1:1.
# Position is the bottom-centre of the hitbox and always holds whole pixels;
# sub-pixel movement lives in `rem`, like Monocle's Actor.

# State IDs select mutually exclusive movement rules. They are not animation frame numbers.
enum { ST_NORMAL, ST_CLIMB, ST_DASH, ST_BOOST, ST_RED_DASH, ST_HIT_SQUASH, ST_LAUNCH, ST_DREAM_DASH, ST_STAR_FLY, ST_SWIM }
const STATE_NAMES := ["Normal", "Climb", "Dash", "Boost", "Red Dash", "Hit Squash", "Launch", "Dream Dash", "Star Fly", "Normal (Underwater)"]

# Movement tuning. These were Celeste's constants; they are vars so they can be tuned
# in-game (see scripts/tuning.gd). Defaults below are the Celeste values.
# Basic motion: speed limits are px/s, acceleration/gravity are px/s squared, delays are seconds.
# Negative vertical speed rises; positive vertical speed falls. See tuning.gd HELP for each adjustable value.
var MAX_FALL := 160.0
var GRAVITY := 900.0
var HALF_GRAV_THRESHOLD := 40.0
var FAST_MAX_FALL := 240.0
var FAST_MAX_ACCEL := 300.0
var MAX_RUN := 90.0
var RUN_ACCEL := 1000.0
var RUN_REDUCE := 400.0
var AIR_MULT := 0.65
var DUCK_FRICTION := 500.0
var DUCK_CORRECT_CHECK := 4
var DUCK_CORRECT_SLIDE := 50.0
var DODGE_SLIDE_SPEED_MULT := 1.2
var DUCK_SUPER_JUMP_X_MULT := 1.25
var DUCK_SUPER_JUMP_Y_MULT := 0.5
# Jump forgiveness: grace permits a short jump after leaving a ledge; variable hold controls jump height.
var JUMP_GRACE_TIME := 0.1
var JUMP_SPEED := -105.0
var JUMP_H_BOOST := 40.0
var VAR_JUMP_TIME := 0.2
var CEILING_VAR_JUMP_GRACE := 0.05
var UPWARD_CORNER_CORRECTION := 4
var WALL_SPEED_RETENTION_TIME := 0.06
var WALL_JUMP_CHECK_DIST := 3
var WALL_JUMP_FORCE_TIME := 0.16
var WALL_JUMP_H_SPEED := MAX_RUN + JUMP_H_BOOST
var WALL_SLIDE_START_MAX := 20.0
var WALL_SLIDE_TIME := 1.2
var BOUNCE_VAR_JUMP_TIME := 0.2
var BOUNCE_SPEED := -140.0
var BOUNCE_AUTO_JUMP_TIME := 0.1
var SUPER_BOUNCE_VAR_JUMP_TIME := 0.2
var SUPER_BOUNCE_SPEED := -185.0
var SUPER_JUMP_H := 260.0
var SUPER_WALL_JUMP_SPEED := -160.0
var SUPER_WALL_JUMP_VAR_TIME := 0.25
var SUPER_WALL_JUMP_H := MAX_RUN + JUMP_H_BOOST * 2
var SIDE_BOUNCE_SPEED := 240.0
var SIDE_BOUNCE_FORCE_TIME := 0.3
# Dash tuning: travel speed, duration, cooldown, refill delay and small collision-correction distances.
var DASH_SPEED := 240.0
var END_DASH_SPEED := 160.0
var END_DASH_UP_MULT := 0.75
var DASH_TIME := 0.15
var DASH_COOLDOWN := 0.2
var DASH_REFILL_COOLDOWN := 0.1
var DASH_H_JUMPTHRU_NUDGE := 6
var DASH_CORNER_CORRECTION := 4
var DASH_V_FLOOR_SNAP_DIST := 3
var DASH_ATTACK_TIME := 0.3
var BOOST_MOVE_SPEED := 80.0
var BOOST_TIME := 0.25
var REBOUND_SPEED_X := 120.0
var REBOUND_SPEED_Y := -120.0
var REBOUND_VAR_JUMP_TIME := 0.15
var DREAM_DASH_MIN_TIME := 0.1
var DREAM_DASH_END_WIGGLE := 5
# Wall climbing: stamina is a separate resource from adventure energy; costs below are stamina per second or action.
var CLIMB_MAX_STAMINA := 110.0
var CLIMB_UP_COST := 100.0 / 2.2
var CLIMB_STILL_COST := 100.0 / 10.0
var CLIMB_JUMP_COST := 110.0 / 4.0
var CLIMB_CHECK_DIST := 2
var CLIMB_UP_CHECK_DIST := 2
var CLIMB_NO_MOVE_TIME := 0.1
var CLIMB_TIRED_THRESHOLD := 20.0
var CLIMB_UP_SPEED := -45.0
var CLIMB_DOWN_SPEED := 80.0
var CLIMB_SLIP_SPEED := 30.0
var CLIMB_ACCEL := 900.0
var CLIMB_GRAB_Y_MULT := 0.2
var CLIMB_HOP_Y := -120.0
var CLIMB_HOP_X := 100.0
var CLIMB_HOP_FORCE_TIME := 0.2
var CLIMB_JUMP_BOOST_TIME := 0.2
var LAUNCH_SPEED := 280.0
var LAUNCH_CANCEL_THRESHOLD := 220.0
var LIFT_Y_CAP := -130.0
var LIFT_X_CAP := 250.0
var LIFT_SPEED_GRACE := 0.16
var JUMPTHRU_ASSIST_SPEED := -40.0
var HIT_SQUASH_NO_MOVE_TIME := 0.1
var HIT_SQUASH_FRICTION := 800.0
var STAR_FLY_TRANSFORM_DECCEL := 1000.0
var STAR_FLY_TIME := 2.0
var STAR_FLY_START_SPEED := 250.0
var STAR_FLY_TARGET_SPEED := 140.0
var STAR_FLY_MAX_SPEED := 190.0
var STAR_FLY_MAX_LERP_TIME := 1.0
var STAR_FLY_SLOW_SPEED := STAR_FLY_TARGET_SPEED * 0.65
var STAR_FLY_ACCEL := 1000.0
var STAR_FLY_ROTATE_SPEED := 320.0 * PI / 180.0
var STAR_FLY_END_FLASH := 0.5
var STAR_FLY_END_NO_BOUNCE := 0.2
var STAR_FLY_WALL_BOUNCE := -0.5
var STAR_FLY_MAX_EXIT_Y := 0.0
var STAR_FLY_MAX_EXIT_X := 140.0
var STAR_FLY_EXIT_UP := -100.0
var INPUT_BUFFER := 0.08
var ATTACK_TIME := 0.143  # 140% speed of the first 0.2s swing
var ATTACK_COOLDOWN := 0.25
var ATTACK_RANGE := 15.4  # 110% of the first 14 px
var ATTACK_ARC := 120.0
# Directions a move can go: 0 off, 1 horizontal, -1 vertical, 2 both (4-way), 3 + diagonals (8-way), 4 free aim (analog stick)
var DASH_DIRS := 3
var ATTACK_DIRS := 1

# These boxes are offsets from pos (the feet). HB blocks terrain; HURT activates interactions.
# damage_rect() shrinks HURT again for forgiving lethal-hazard contact. Art never defines these boxes.
const HB_NORMAL := Rect2i(-4, -11, 8, 11)
const HB_DUCK := Rect2i(-4, -6, 8, 6)
const HB_FLY := Rect2i(-4, -10, 8, 8)
const HURT_NORMAL := Rect2i(-4, -11, 8, 9)
# Normal (Underwater), ST_SWIM: replaces Normal while the player's centre is in water.
const WATER_MAX_FALL := 40.0  # buoyancy caps sinking...
const WATER_BUOYANCY := 0.6  # ...and cancels this share of gravity
const WATER_MAX_RISE := 110.0
const WATER_MAX_X := 55.0  # swimming speed; faster speeds are dragged down to it
const WATER_DRAG := 500.0
const WATER_ACCEL := 400.0
const WATER_STROKE := -100.0  # Jumping (Underwater): ~14 px of rise, against ~27 px for a normal jump
const WATER_SURFACE_REACH := 12  # px: with the surface this close above the centre, jump leaps out (a normal jump)
# Layer: applied on top of whatever state runs (_layers), not a state of its own.
const WATERFALL_PUSH := 70.0  # inside a waterfall: pulled down towards this speed...
const WATERFALL_FORCE := 600.0  # ...this hard (px/s²): jumps still rise, but much less
const JUMP_ENERGY := 5.0  # adventure: each jump costs this much, and needs it
const DAMAGE_SCALE := 0.8  # hazards and enemies hit a box 20% smaller than the hurtbox
const HURT_DUCK := Rect2i(-4, -6, 8, 4)
const HURT_FLY := Rect2i(-3, -9, 6, 6)

const HAIR_NORMAL := Color("493022")
const HAIR_USED := Color("929292")
const HAIR_TWO := Color("493022")
const HAIR_FLY := Color("f2eb6d")

# Ownership and physical state: w supplies collision/services; speed is velocity, not a per-frame displacement.
var w  # world
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO  # pos before the latest physics tick (render interpolation)
var draw_off := Vector2.ZERO  # set by World each displayed frame: where the body is drawn between ticks, minus pos
# Fractional motion accumulator: e.g. repeated 0.25px steps become one whole-pixel move after four updates.
var rem := Vector2.ZERO
var speed := Vector2.ZERO
var facing := 1
var collider := HB_NORMAL
var hurtbox := HURT_NORMAL
var state := ST_NORMAL
var prev_state := ST_NORMAL
var dead := false
var underwater := false  # centre inside water: Normal becomes Normal (Underwater)
var in_waterfall := false  # layer: hurtbox inside a waterfall
var bubble_t := 0.0

# Short-lived movement memory. Most timers count down to zero; they are measured in simulated seconds.
var step_sfx_timer := 0.0
var on_ground := false
var was_on_ground := false
var on_safe_ground := false
var jump_grace_timer := 0.0
var var_jump_timer := 0.0
var var_jump_speed := 0.0
var auto_jump := false
var auto_jump_timer := 0.0
var dash_attack_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_refill_cooldown_timer := 0.0
var dashes := 1
var stamina := CLIMB_MAX_STAMINA
var max_fall := MAX_FALL
var wall_slide_timer := WALL_SLIDE_TIME
var wall_slide_dir := 0
var wall_boost_timer := 0.0
var wall_boost_dir := 0
var force_move_x := 0
var force_move_x_timer := 0.0
var move_x := 0
var wall_speed_retention_timer := 0.0
var wall_speed_retained := 0.0
var hop_wait_x := 0
var hop_wait_x_speed := 0.0
var climb_hop_solid = null
var climb_hop_solid_pos := Vector2i.ZERO
var climb_no_move_timer := 0.0
var last_climb_move := 0
# Dash/launch memory persists across state-entry and collision callbacks until the action ends.
var dash_dir := Vector2.ZERO
var before_dash_speed := Vector2.ZERO
var dash_started_on_ground := false
var was_dash_b := false
var called_dash_events := false
var last_aim := Vector2.RIGHT
var last_dash_aim := Vector2.RIGHT  # last_aim limited by DASH_DIRS
var launched := false
var lift_current := Vector2.ZERO
var lift_last := Vector2.ZERO
var lift_timer := 0.0
var current_booster = null
var boost_target := Vector2.ZERO
var boost_red := false
var hit_squash_no_move_timer := 0.0
var dream_block = null
var dream_dash_can_end_timer := 0.0
var dream_jump := false
var star_fly_timer := 0.0
var star_fly_transforming := false
var star_fly_speed_lerp := 0.0
var star_fly_last_dir := Vector2.ZERO
# Active sword swing and recovery are separate: a released button cannot bypass the cooldown.
var attack_timer := 0.0
var attack_cooldown_timer := 0.0
var attack_dir := Vector2.RIGHT
var attack_hit: Array = []  # entities already struck by this swing

# coroutine emulation (Monocle Coroutine: yield null = next frame, yield t = wait t seconds)
# co_step is the current sequence stage, co_wait the remaining delay. No thread or blocking sleep is involved.
var co_active := false
var co_step := 0
var co_wait := 0.0

# input
var in_x := 0
var in_y := 0
var interact := false  # interact (S / pad B) pressed this tick: go through house doors
var aim_raw := Vector2.ZERO
var aim_free := Vector2.ZERO  # analog stick direction (free aim); zero on keyboard-only input
# Buffered presses remember a recent tap briefly; *_check values below represent buttons still held down.
var jump_buf := 0.0
var dash_buf := 0.0
var attack_buf := 0.0
var jump_check := false
var grab_check := false

# visuals
var scale := Vector2.ONE
var hair: Array[Vector2] = []
var hair_wave := 0.0
var flash := false
var flash_t := 0.0
var anim_t := 0.0
# Animation clocks are presentation state and must not determine collision or movement.
var visual_animation := "idle"
var visual_clock := 0.0
var landing_visual_timer := 0.0
var trail_timer := 0.0
var followers: Array = []  # stars following the player

# state machine record for the debug panel (bookkeeping only, never read by gameplay)
var transitions := {}  # Vector2i(from, to) -> count
var transition_log: Array = []  # last 10 [time, from, to]
var attack_log: Array = []  # times of the last 10 swings

# Create a player at the spawn feet position, apply movement tuning and initialize the hair chain.
func _init(world, spawn: Vector2) -> void:
	w = world
	if world != null:  # a world-less player is only used to read the default tuning
		apply_tuning(Game.tuning)
	stamina = CLIMB_MAX_STAMINA
	max_fall = MAX_FALL
	wall_slide_timer = WALL_SLIDE_TIME
	pos = spawn.floor()
	for i in 4:  # segments, as in Celeste
		hair.append(pos + Vector2(0, -9))
	dashes = max_dashes()

var quiet := false  # true for a stand-in runner (the chasing Ape): its moves make no player sounds

# Play a player effect unless this is a silent stand-in used by the chase planner.
func sfx(key: String, pitch := 1.0) -> void:
	if not quiet:
		Game.play_sfx(key, pitch)

# Overrides tunable vars by name, then recomputes the derived ones.
# Apply named movement overrides, then recalculate values derived from run and jump speeds.
func apply_tuning(values: Dictionary) -> void:
	for k in values:
		set(k, values[k])
	WALL_JUMP_H_SPEED = MAX_RUN + JUMP_H_BOOST
	SUPER_WALL_JUMP_H = MAX_RUN + JUMP_H_BOOST * 2
	STAR_FLY_SLOW_SPEED = STAR_FLY_TARGET_SPEED * 0.65

# ---------------- helpers ----------------
# Return the dash capacity selected by the assist setting; this is not the current remaining count.
func max_dashes() -> int:
	return 2 if Game.settings.air_dashes != 0 else 1

# Move the current local collision rectangle to a proposed feet position without moving the player.
func rect_at(p: Vector2) -> Rect2i:
	return Rect2i(Vector2i(p) + collider.position, collider.size)

# Return the world-space box used to stop movement against solid terrain.
func hitbox() -> Rect2i:
	return rect_at(pos)

# Return the interaction box used for touches such as pickups; it is shorter than the movement box.
func hurt_rect() -> Rect2i:
	return Rect2i(Vector2i(pos) + hurtbox.position, hurtbox.size)

# What hazards and enemies test against: the hurtbox 20% smaller each way (pickups keep hurt_rect).
# Centred sideways; the bottom edge stays put so floor spikes still reach the feet.
# Return the smaller forgiving target that hazards and enemies must overlap to hurt the player.
func damage_rect() -> Rect2i:
	var r := hurt_rect()
	var s := Vector2i((Vector2(r.size) * DAMAGE_SCALE).round())
	return Rect2i(r.position.x + (r.size.x - s.x) / 2, r.end.y - s.y, s.x, s.y)

# Return the centre of the current movement box, useful for aim and distance calculations.
func center() -> Vector2:
	return pos + Vector2(collider.position) + Vector2(collider.size) / 2.0

# Return the bottom Y coordinate of the movement box (screen Y grows downward).
func bottom() -> int:
	return int(pos.y) + collider.end.y

# Check whether the movement box would overlap a solid after applying a pixel offset.
func solid_at(off := Vector2.ZERO) -> bool:
	return w.collide_solid(rect_at(pos + off)) != null

# Find the first solid at the proposed offset; the result identifies a tile or movable object.
func solid_first(off := Vector2.ZERO):
	return w.collide_solid(rect_at(pos + off))

# Test a single pixel against World collision, for small probes around corners and ledges.
func point_solid(p: Vector2) -> bool:
	return w.collide_solid(Rect2i(Vector2i(p.floor()), Vector2i.ONE)) != null

# Find a one-way platform newly crossed at an offset, ignoring platforms already overlapping us.
func jumpthru_outside(off: Vector2):
	return w.collide_jumpthru_outside(rect_at(pos + off), hitbox())

# Probe below a proposed feet position; both solid ground and one-way platforms can support the player.
func on_ground_at(p: Vector2, dist := 1) -> bool:
	var r := rect_at(p + Vector2(0, dist))
	return w.collide_solid(r) != null or w.collide_jumpthru_outside(r, rect_at(p)) != null

# Report whether the short crouching collider is currently selected.
func ducking() -> bool:
	return collider == HB_DUCK

# Switch movement and interaction boxes together so crouching affects both consistently.
func set_ducking(v: bool) -> void:
	collider = HB_DUCK if v else HB_NORMAL
	hurtbox = HURT_DUCK if v else HURT_NORMAL

# Check that changing from the short box to the standing box would not enter a ceiling.
func can_unduck() -> bool:
	if not ducking():
		return true
	var was := collider
	collider = HB_NORMAL
	var ok := not solid_at()
	collider = was
	return ok

# Perform the standing-clearance check at another proposed position.
func can_unduck_at(p: Vector2) -> bool:
	var was := pos
	pos = p
	var ok := can_unduck()
	pos = was
	return ok

# Test whether the short crouching box fits at a proposed position.
func duck_free_at(p: Vector2) -> bool:
	var was := collider
	collider = HB_DUCK
	var ok: bool = w.collide_solid(rect_at(p)) == null
	collider = was
	return ok

# Compare remaining climbing stamina with the threshold that changes wall-hold behavior and visuals.
func is_tired() -> bool:
	return stamina < CLIMB_TIRED_THRESHOLD

# Report the brief dash-attack window, which can last longer than the movement dash itself.
func dash_attacking() -> bool:
	return dash_attack_timer > 0 or state == ST_RED_DASH

# Check the buffered request, remaining dashes and cooldowns before entering dash movement.
func can_dash() -> bool:
	return dash_buf > 0 and dash_cooldown_timer <= 0 and dashes > 0 and DASH_DIRS != 0

# Layers on top of the current state: a waterfall pulls the player down.
# Apply the waterfall downward pull on top of the current movement mode.
func _layers(dt: float) -> void:
	in_waterfall = w.liquid_at(hurt_rect(), "waterfall")
	if in_waterfall and speed.y < WATERFALL_PUSH:
		speed.y = approach(speed.y, WATERFALL_PUSH, WATERFALL_FORCE * dt)

# ---------------- NORMAL (UNDERWATER) ----------------
# Replaces Normal in water: no walking on the floor (it moves as mid-water) and no normal jump; Jumping (Underwater) is a weaker
# stroke that works from the floor or mid-water, every time jump is pressed. Dash still works. Leaving the water returns to Normal.
# Handle underwater steering, drag and jump strokes; return the movement state to run next.
func _swim_update(dt: float) -> int:
	if not underwater:
		return ST_NORMAL
	if can_dash():
		return _start_dash()
	# horizontal: the same as mid-water, also along the floor (no walking: the air poses, swim speed)
	if absf(speed.x) > WATER_MAX_X:
		speed.x = approach(speed.x, WATER_MAX_X * signf(speed.x), WATER_DRAG * dt)
	else:
		speed.x = approach(speed.x, WATER_MAX_X * move_x, WATER_ACCEL * dt)
	if not on_ground:
		speed.y = approach(speed.y, WATER_MAX_FALL, GRAVITY * (1.0 - WATER_BUOYANCY) * dt)
	speed.y = maxf(speed.y, -WATER_MAX_RISE)
	if jump_pressed():  # every press, as often as you like
		on_ground = false
		if can_jump() and not w.liquid_at(Rect2i(Vector2i(center()) - Vector2i(0, WATER_SURFACE_REACH), Vector2i.ONE), "water"):
			jump()  # the surface is close: a full jump out of the water
		else:  # Jumping (Underwater)
			jump_buf = 0
			sfx("splash", 1.3)
			speed.y = WATER_STROKE
	bubble_t -= dt
	if bubble_t <= 0:
		bubble_t = 0.45
		w.parts.append([center() + Vector2(facing * 3, -5), Vector2(0, -18), 0.9, Color(0.85, 0.95, 1.0)])
	return ST_SWIM

# Report a buffered jump request; a short input buffer makes near-miss button timing more forgiving.
func jump_pressed() -> bool:
	return jump_buf > 0

# Return the platform velocity still available through the short lift-memory grace period.
func lift_speed() -> Vector2:
	return lift_last if lift_current == Vector2.ZERO else lift_current

# Remember the velocity of a platform carrying or pushing the player.
func set_lift_speed(v: Vector2) -> void:
	lift_current = v
	if v != Vector2.ZERO:
		lift_last = v
		lift_timer = LIFT_SPEED_GRACE

# Limit inherited platform momentum so a fast lift cannot create an unintended enormous launch.
func lift_boost() -> Vector2:
	var v := lift_speed()
	if absf(v.x) > LIFT_X_CAP:
		v.x = LIFT_X_CAP * signf(v.x)
	v.y = clampf(v.y, LIFT_Y_CAP, 0.0)
	return v

# Celeste: no grabbing past the level edge. Past this room's edge lies the next room's rock, which is a real wall.
# Ensure the wall probe stays inside this room or a valid neighboring room.
func climb_bounds_check(dir: int) -> bool:
	var r := hitbox()
	if r.position.x + dir * CLIMB_CHECK_DIST >= w.bounds.position.x and r.end.x + dir * CLIMB_CHECK_DIST < w.bounds.end.x:
		return true
	return w.can_exit(Vector2(r.end.x + CLIMB_CHECK_DIST if dir > 0 else r.position.x - CLIMB_CHECK_DIST, r.get_center().y))

# Probe for a grabbable wall in the requested horizontal direction, optionally shifted vertically.
func climb_check(dir: int, y_add := 0) -> bool:
	return climb_bounds_check(dir) and solid_at(Vector2(dir * CLIMB_CHECK_DIST, y_add))

# Probe the slightly different reach used when jumping away from a wall.
func wall_jump_check(dir: int) -> bool:
	return climb_bounds_check(dir) and solid_at(Vector2(dir * WALL_JUMP_CHECK_DIST, 0))

# Determine whether the player stands on, clings to, or travels through this moving object.
func is_riding(s) -> bool:
	if state == ST_DREAM_DASH:
		return s.rect.intersects(hitbox())
	if state == ST_CLIMB or state == ST_HIT_SQUASH:
		return s.rect.intersects(rect_at(pos + Vector2(facing, 0)))
	if s.jumpthru:
		return speed.y >= 0 and s.rect.intersects(rect_at(pos + Vector2.DOWN)) and not s.rect.intersects(hitbox())
	return s.rect.intersects(rect_at(pos + Vector2.DOWN))

# Move one number toward a target by at most amount, without overshooting it.
static func approach(v: float, target: float, amount: float) -> float:
	return minf(v + amount, target) if v <= target else maxf(v - amount, target)

# Vector version of approach: limit the change in direction-and-speed to the given distance.
static func approach_v(v: Vector2, target: Vector2, amount: float) -> Vector2:
	var d := target - v
	return target if d.length() <= amount else v + d.normalized() * amount

# ---------------- movement (Monocle Actor) ----------------
# Accumulate horizontal fractions, move whole pixels and optionally invoke collision reactions.
func move_h(amount: float, callback := false) -> bool:
	rem.x += amount
	var m := roundi(rem.x)
	if m == 0:
		return false
	rem.x -= m
	return move_h_exact(m, 1 if callback else 0)

# Accumulate vertical fractions, move whole pixels and optionally invoke collision reactions.
func move_v(amount: float, callback := false) -> bool:
	rem.y += amount
	var m := roundi(rem.y)
	if m == 0:
		return false
	rem.y -= m
	return move_v_exact(m, 1 if callback else 0)

# cb: 0 = none, 1 = normal collide callback, 2 = squish (pushed by a solid)
# Walk a requested integer distance one pixel at a time, stopping at the first horizontal obstruction.
func move_h_exact(m: int, cb := 0) -> bool:
	var s := signi(m)
	while m != 0:
		var hit = solid_first(Vector2(s, 0))
		if hit != null:
			rem.x = 0
			if cb == 1:
				_on_collide_h(hit)
			elif cb == 2:
				_on_squish()
			return true
		pos.x += s
		m -= s
	return false

# Walk a requested integer distance one pixel at a time; descending also checks one-way platforms.
func move_v_exact(m: int, cb := 0) -> bool:
	var s := signi(m)
	while m != 0:
		var hit = solid_first(Vector2(0, s))
		if hit == null and s > 0:
			hit = jumpthru_outside(Vector2(0, 1))
		if hit != null:
			rem.y = 0
			if cb == 1:
				_on_collide_v(hit)
			elif cb == 2:
				_on_squish()
			return true
		pos.y += s
		m -= s
	return false

# Move toward an absolute X coordinate while respecting accumulated fractions and collision.
func move_to_x(x: float) -> void:
	move_h(x - (pos.x + rem.x))

# Move toward an absolute Y coordinate while respecting accumulated fractions and collision.
func move_to_y(y: float) -> void:
	move_v(y - (pos.y + rem.y))

# Apply an offset without collision resolution; callers must already know this relocation is safe.
func naive_move(v: Vector2) -> void:
	rem += v
	var m := Vector2(roundi(rem.x), roundi(rem.y))
	rem -= m
	pos += m

# Try the collision escape rules when a moving solid squeezes the player; die if no safe escape exists.
func _on_squish() -> void:
	# Monocle TrySquishWiggle: nudge up to 3px out of the solid, else die
	if not solid_at():
		return
	for x in range(0, 4):
		for y in range(0, 4):
			for sx in [1, -1]:
				for sy in [1, -1]:
					var off := Vector2(x * sx, y * sy)
					if not solid_at(off):
						pos += off
						return
	die(Vector2.ZERO)

# ---------------- input ----------------
# Read keyboard/gamepad actions, record short button buffers and update held movement directions.
func _read_input(dt: float) -> void:
	in_x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	in_y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	aim_raw = Vector2(in_x, in_y).normalized()
	aim_free = Input.get_vector("left", "right", "up", "down")
	jump_buf -= dt
	dash_buf -= dt
	if Input.is_action_just_pressed("jump"):
		jump_buf = INPUT_BUFFER
	if Input.is_action_just_pressed("dash"):
		dash_buf = INPUT_BUFFER
	attack_buf -= dt
	if Input.is_action_just_pressed("attack"):
		attack_buf = INPUT_BUFFER
	jump_check = Input.is_action_pressed("jump")
	grab_check = Input.is_action_pressed("grab")
	interact = Input.is_action_just_pressed("interact")

# Held direction limited to a *_DIRS mode (see DASH_DIRS). With no direction held: facing (vertical-only: up).
# Convert the current aim to the direction set allowed by the chosen movement tuning.
func dir_for(mode: int) -> Vector2:
	var v := aim_free if mode == 4 and aim_free != Vector2.ZERO else aim_raw
	var face := Vector2(facing, 0)
	match mode:
		1:
			return Vector2(signf(v.x), 0) if v.x != 0 else face
		-1:
			return Vector2(0, signf(v.y)) if v.y != 0 else Vector2.UP
		2:
			if v == Vector2.ZERO:
				return face
			return Vector2(0, signf(v.y)) if absf(v.y) >= absf(v.x) else Vector2(signf(v.x), 0)
		3:
			if v == Vector2.ZERO:
				return face
			var a := snappedf(v.angle(), PI / 4)
			return Vector2(roundf(cos(a)), roundf(sin(a))).normalized()
	return v.normalized() if v != Vector2.ZERO else face

# Combine directional buttons and analog input into the aiming vector used by attacks and dashes.
func aim_vector() -> Vector2:
	return aim_raw if aim_raw != Vector2.ZERO else Vector2(facing, 0)

# ---------------- main update (Player.Update) ----------------
# Run one simulation step: input, timers, ground checks, state logic, pixel movement, contacts and visuals.
func update(dt: float) -> void:
	step_sfx_timer = maxf(0.0, step_sfx_timer - dt)
	if not dead and step_sfx_timer <= 0.0:
		if on_ground and absf(speed.x) > 20 and state == ST_NORMAL:
			sfx("step")
			step_sfx_timer = 0.19
		elif state == ST_CLIMB and absf(speed.y) > 5:
			sfx("climb")
			step_sfx_timer = 0.25
	_read_input(dt)
	# adventure: moves not picked up yet do nothing (Game.has_ability is always true elsewhere)
	if not Game.has_ability("dash"):
		dash_buf = 0
	if not Game.has_ability("climb"):
		grab_check = false
	if not Game.has_ability("attack"):
		attack_buf = 0
	if Game.settings.infinite_stamina:
		stamina = CLIMB_MAX_STAMINA

	if state == ST_DREAM_DASH:
		on_ground = false
		on_safe_ground = false
	elif speed.y >= 0:
		var first = solid_first(Vector2.DOWN)
		if first == null:
			first = jumpthru_outside(Vector2.DOWN)
		on_ground = first != null
		on_safe_ground = on_ground and (typeof(first) == TYPE_STRING or first.safe)
	else:
		on_ground = false
		on_safe_ground = false

	if wall_slide_dir != 0:
		wall_slide_timer = maxf(wall_slide_timer - dt, 0)
		wall_slide_dir = 0

	if wall_boost_timer > 0:
		wall_boost_timer -= dt
		if move_x == wall_boost_dir:
			speed.x = WALL_JUMP_H_SPEED * move_x
			stamina += CLIMB_JUMP_COST
			wall_boost_timer = 0

	if on_ground and state != ST_CLIMB:
		auto_jump = false
		stamina = CLIMB_MAX_STAMINA
		wall_slide_timer = WALL_SLIDE_TIME

	if dash_attack_timer > 0:
		dash_attack_timer -= dt

	if on_ground:
		dream_jump = false
		jump_grace_timer = JUMP_GRACE_TIME
	elif jump_grace_timer > 0:
		jump_grace_timer -= dt

	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= dt
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= dt
	if dash_refill_cooldown_timer > 0:
		dash_refill_cooldown_timer -= dt
	elif Game.settings.air_dashes == 2:
		refill_dash()
	elif on_ground and not w.touching_spikes(hurt_rect()):
		refill_dash()

	if var_jump_timer > 0:
		var_jump_timer -= dt

	if auto_jump_timer > 0:
		if auto_jump:
			auto_jump_timer -= dt
			if auto_jump_timer <= 0:
				auto_jump = false
		else:
			auto_jump_timer = 0

	if force_move_x_timer > 0:
		force_move_x_timer -= dt
		move_x = force_move_x
	else:
		move_x = in_x
		climb_hop_solid = null

	if climb_hop_solid != null and not climb_hop_solid.collidable:
		climb_hop_solid = null
	elif climb_hop_solid != null and climb_hop_solid.rect.position != climb_hop_solid_pos:
		var mv: Vector2i = climb_hop_solid.rect.position - climb_hop_solid_pos
		climb_hop_solid_pos = climb_hop_solid.rect.position
		move_h_exact(mv.x)
		move_v_exact(mv.y)

	if move_x != 0 and state not in [ST_CLIMB, ST_RED_DASH, ST_HIT_SQUASH]:
		facing = move_x

	last_aim = aim_vector()
	last_dash_aim = dir_for(DASH_DIRS)

	if wall_speed_retention_timer > 0:
		if signf(speed.x) == -signf(wall_speed_retained):
			wall_speed_retention_timer = 0
		elif not solid_at(Vector2(signf(wall_speed_retained), 0)):
			speed.x = wall_speed_retained
			wall_speed_retention_timer = 0
		else:
			wall_speed_retention_timer -= dt

	if hop_wait_x != 0:
		if signf(speed.x) == -hop_wait_x or speed.y > 0:
			hop_wait_x = 0
		elif not solid_at(Vector2(hop_wait_x, 0)):
			speed.x = hop_wait_x_speed
			hop_wait_x = 0

	# state machine + coroutine
	var was_underwater := underwater
	underwater = w.liquid_at(Rect2i(Vector2i(center()), Vector2i.ONE), "water")
	if underwater != was_underwater:
		sfx("splash")
	_state_update(dt)
	if dead:
		return
	_layers(dt)

	# Actor.Update: lift speed resets each frame, with a short grace
	lift_current = Vector2.ZERO
	if lift_timer > 0:
		lift_timer -= dt
		if lift_timer <= 0:
			lift_last = Vector2.ZERO

	# jump-thru assist
	if not on_ground and speed.y <= 0 and (state != ST_CLIMB or last_climb_move == -1) and w.collide_jumpthru(hitbox()) != null:
		move_v(JUMPTHRU_ASSIST_SPEED * dt)

	# dash floor snapping
	if not on_ground and dash_attacking() and dash_dir8().y == 0:
		if solid_at(Vector2(0, DASH_V_FLOOR_SNAP_DIST)) or jumpthru_outside(Vector2(0, DASH_V_FLOOR_SNAP_DIST)) != null:
			move_v_exact(DASH_V_FLOOR_SNAP_DIST)

	if speed.y > 0 and can_unduck() and collider != HB_FLY and not on_ground:
		set_ducking(false)

	if state != ST_DREAM_DASH:
		move_h(speed.x * dt, true)
		move_v(speed.y * dt, true)
	if dead:
		return

	_attack_update(dt)
	w.player_touch(self)
	if not dead and state != ST_DREAM_DASH:
		_enforce_bounds()
	if dead:
		return

	_update_visuals(dt)
	was_on_ground = on_ground

# Resolve room edges after movement, allowing exits only where an adjacent adventure room exists.
func _enforce_bounds() -> void:
	var r := hitbox()
	var b: Rect2i = w.bounds
	var c := Vector2(r.get_center())
	# an edge that leads into a neighbouring adventure room (w.can_exit) lets the player through
	if r.position.x < b.position.x and not w.can_exit(Vector2(r.position.x, c.y)):
		pos.x += b.position.x - r.position.x
		_on_bounds_h()
	elif r.end.x > b.end.x and not w.can_exit(Vector2(r.end.x, c.y)):
		pos.x -= r.end.x - b.end.x
		_on_bounds_h()
	# up past the 24px allowance only where another room touches this one's top edge directly
	if r.position.y < b.position.y - 24 and not w.can_exit(Vector2(c.x, b.position.y - 1)):
		pos.y += b.position.y - 24 - r.position.y
		speed.y = 0
	elif r.position.y > b.end.y and not w.can_exit(Vector2(c.x, r.position.y)):
		die(Vector2.ZERO)

# React to a horizontal room boundary using the normal wall-collision behavior.
func _on_bounds_h() -> void:
	speed.x = 0
	rem.x = 0
	if state == ST_RED_DASH:
		_set_state(ST_NORMAL)

# ---------------- state machine ----------------
# Run the current movement mode, apply any requested state change and advance its timed sequence.
func _state_update(dt: float) -> void:
	var ns := state
	match state:
		ST_NORMAL: ns = _normal_update(dt)
		ST_CLIMB: ns = _climb_update(dt)
		ST_DASH: ns = _dash_update(dt)
		ST_BOOST: ns = _boost_update(dt)
		ST_RED_DASH: ns = _red_dash_update(dt)
		ST_HIT_SQUASH: ns = _hit_squash_update(dt)
		ST_LAUNCH: ns = _launch_update(dt)
		ST_DREAM_DASH: ns = _dream_dash_update(dt)
		ST_STAR_FLY: ns = _star_fly_update(dt)
		ST_SWIM: ns = _swim_update(dt)
	if dead:
		return
	_set_state(ns)
	if co_active:
		if co_wait > 0:
			co_wait -= dt
		else:
			_co_resume()

# Leave the old mode, reset its temporary data and enter the new mode exactly once per transition.
func _set_state(ns: int) -> void:
	if ns == state or dead:
		return
	prev_state = state
	match state:  # end
		ST_NORMAL:
			wall_boost_timer = 0
			wall_speed_retention_timer = 0
			hop_wait_x = 0
		ST_CLIMB:
			wall_speed_retention_timer = 0
		ST_DASH, ST_RED_DASH:
			_call_dash_events()
		ST_BOOST:
			var to := (boost_target - Vector2(collider.position) - Vector2(collider.size) / 2.0).floor()
			move_to_x(to.x)
			move_to_y(to.y)
		ST_DREAM_DASH:
			_dream_dash_end()
		ST_STAR_FLY:
			_star_fly_end()
	state = ns
	var key := Vector2i(prev_state, ns)
	transitions[key] = transitions.get(key, 0) + 1
	transition_log.append([w.time if w != null else 0.0, prev_state, ns])
	if transition_log.size() > 10:
		transition_log.pop_front()
	co_active = state in [ST_DASH, ST_BOOST, ST_RED_DASH, ST_STAR_FLY]
	co_step = 0
	co_wait = 0
	match state:  # begin
		ST_NORMAL:
			max_fall = MAX_FALL
		ST_CLIMB:
			_climb_begin()
		ST_DASH:
			_dash_begin()
		ST_BOOST:
			refill_dash()
			refill_stamina()
		ST_RED_DASH:
			_red_dash_begin()
		ST_HIT_SQUASH:
			hit_squash_no_move_timer = HIT_SQUASH_NO_MOVE_TIME
		ST_LAUNCH:
			launched = true
		ST_DREAM_DASH:
			_dream_dash_begin()
		ST_STAR_FLY:
			_star_fly_begin()
		ST_SWIM:
			set_ducking(false)
			auto_jump = false
			var_jump_timer = 0

# Advance a timed action sequence without blocking the game; co_wait stores delays between steps.
func _co_resume() -> void:
	match state:
		ST_DASH:
			if co_step == 0:
				co_step = 1  # yield null
			elif co_step == 1:
				_dash_co_start()
				co_step = 2
				co_wait = DASH_TIME
			else:
				w.add_trail(self)
				auto_jump = true
				auto_jump_timer = 0
				if dash_dir.y <= 0:
					speed = dash_dir * END_DASH_SPEED
				if speed.y < 0:
					speed.y *= END_DASH_UP_MULT
				co_active = false
				_set_state(ST_NORMAL)
		ST_BOOST:
			if co_step == 0:
				co_step = 1
				co_wait = BOOST_TIME
			else:
				co_active = false
				_set_state(ST_RED_DASH if boost_red else ST_DASH)
		ST_RED_DASH:
			if co_step == 0:
				co_step = 1
			else:
				speed = last_dash_aim * DASH_SPEED
				dash_dir = last_dash_aim
				w.shake_dir(dash_dir, 0.2)
				_call_dash_events()
				co_active = false
		ST_STAR_FLY:
			if co_step == 0:
				if speed == Vector2.ZERO:
					co_step = 1
					co_wait = 0.1
			else:
				star_fly_transforming = false
				star_fly_timer = STAR_FLY_TIME
				refill_dash()
				refill_stamina()
				var dir := aim_raw if aim_raw != Vector2.ZERO else Vector2(facing, 0)
				speed = dir * STAR_FLY_START_SPEED
				star_fly_last_dir = dir
				w.shake_dir(dir, 0.2)
				co_active = false

# ---------------- jumps ----------------
# Adventure: a jump needs its full cost in energy (wall jumps and swim strokes stay free).
# Check adventure energy before an ordinary jump; other jumping actions have their own rules.
func can_jump() -> bool:
	return not w.adventure() or Game.adv.energy >= JUMP_ENERGY

# Start a normal jump, spend its adventure energy and reset the variable-height jump timer.
func jump(particles := true) -> void:
	sfx("jump")
	w.drain_energy(JUMP_ENERGY)
	jump_buf = 0
	jump_grace_timer = 0
	var_jump_timer = VAR_JUMP_TIME
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = WALL_SLIDE_TIME
	wall_boost_timer = 0
	speed.x += JUMP_H_BOOST * move_x
	speed.y = JUMP_SPEED
	speed += lift_boost()
	var_jump_speed = speed.y
	scale = Vector2(0.6, 1.4)
	if particles:
		w.dust(pos, Vector2.UP, 4)

# Jump out of a ground dash, carrying the faster sideways momentum into the air.
func super_jump() -> void:
	sfx("jump")
	jump_buf = 0
	jump_grace_timer = 0
	var_jump_timer = VAR_JUMP_TIME
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = WALL_SLIDE_TIME
	wall_boost_timer = 0
	speed.x = SUPER_JUMP_H * facing
	speed.y = JUMP_SPEED
	speed += lift_boost()
	if ducking():
		set_ducking(false)
		speed.x *= DUCK_SUPER_JUMP_X_MULT
		speed.y *= DUCK_SUPER_JUMP_Y_MULT
	var_jump_speed = speed.y
	launched = true
	scale = Vector2(0.6, 1.4)
	w.dust(pos, Vector2.UP, 4)

# Jump away from a wall and briefly force movement outward so the player clears it.
func wall_jump(dir: int) -> void:
	sfx("wall_jump")
	set_ducking(false)
	jump_buf = 0
	jump_grace_timer = 0
	var_jump_timer = VAR_JUMP_TIME
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = WALL_SLIDE_TIME
	wall_boost_timer = 0
	if move_x != 0:
		force_move_x = dir
		force_move_x_timer = WALL_JUMP_FORCE_TIME
	if lift_speed() == Vector2.ZERO:
		var wall = solid_first(Vector2(-dir * WALL_JUMP_CHECK_DIST, 0))
		if wall != null and typeof(wall) != TYPE_STRING:
			set_lift_speed(wall.lift)
	speed.x = WALL_JUMP_H_SPEED * dir
	speed.y = JUMP_SPEED
	speed += lift_boost()
	var_jump_speed = speed.y
	scale = Vector2(0.6, 1.4)
	w.dust(center() + Vector2(-dir * 4, 0), Vector2(dir, -1).normalized(), 4)

# Apply the stronger wall-jump variant associated with a vertical dash.
func super_wall_jump(dir: int) -> void:
	sfx("wall_jump")
	set_ducking(false)
	jump_buf = 0
	jump_grace_timer = 0
	var_jump_timer = SUPER_WALL_JUMP_VAR_TIME
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = WALL_SLIDE_TIME
	wall_boost_timer = 0
	speed.x = SUPER_WALL_JUMP_H * dir
	speed.y = SUPER_WALL_JUMP_SPEED
	speed += lift_boost()
	var_jump_speed = speed.y
	launched = true
	scale = Vector2(0.6, 1.4)
	w.dust(center() + Vector2(-dir * 4, 0), Vector2(dir, -1).normalized(), 4)

# Jump while gripping a wall, applying its stamina and momentum rules.
func climb_jump() -> void:
	sfx("wall_jump")
	if not on_ground:
		stamina -= CLIMB_JUMP_COST
	dream_jump = false
	jump(false)
	if move_x == 0:
		wall_boost_dir = -facing
		wall_boost_timer = CLIMB_JUMP_BOOST_TIME
	w.dust(center() + Vector2(facing * 2, 0), Vector2(-facing, -1).normalized(), 4)

# ---------------- bounces (springs, bumpers) ----------------
# Reset shared dash, stamina and movement timers before an external bounce.
func _bounce_common() -> void:
	if state == ST_BOOST and current_booster != null:
		current_booster.player_released()
		current_booster = null
	refill_dash()
	refill_stamina()
	_set_state(ST_NORMAL)
	jump_grace_timer = 0
	dash_attack_timer = 0
	wall_slide_timer = WALL_SLIDE_TIME
	wall_boost_timer = 0
	launched = false

# Bounce upward from a given surface Y coordinate with a short automatic jump hold.
func bounce(from_y: float) -> void:
	var was := collider
	collider = HB_NORMAL
	move_v_exact(int(from_y - bottom()))
	_bounce_common()
	var_jump_timer = BOUNCE_VAR_JUMP_TIME
	auto_jump = true
	auto_jump_timer = BOUNCE_AUTO_JUMP_TIME
	speed.y = BOUNCE_SPEED
	var_jump_speed = speed.y
	scale = Vector2(0.6, 1.4)
	collider = was

# Apply the stronger upward spring bounce and restore the resources a spring is meant to refill.
func super_bounce(from_y: float) -> void:
	sfx("spring")
	var was := collider
	collider = HB_NORMAL
	move_v(from_y - bottom())
	_bounce_common()
	var_jump_timer = SUPER_BOUNCE_VAR_JUMP_TIME
	auto_jump = true
	auto_jump_timer = 0
	speed.x = 0
	speed.y = SUPER_BOUNCE_SPEED
	var_jump_speed = speed.y
	w.shake_dir(Vector2.UP, 0.1)
	scale = Vector2(0.5, 1.5)
	collider = was

# Bounce away from a sideways spring; return false when already travelling too fast in that direction.
func side_bounce(dir: int, from_x: float, from_y: float) -> bool:
	if absf(speed.x) > SIDE_BOUNCE_SPEED and signf(speed.x) == dir:
		return false
	sfx("spring")
	var was := collider
	collider = HB_NORMAL
	move_v(clampf(from_y - bottom(), -4, 4))
	var r := hitbox()
	if dir > 0:
		move_h(from_x - r.position.x)
	else:
		move_h(from_x - r.end.x)
	_bounce_common()
	var_jump_timer = BOUNCE_VAR_JUMP_TIME
	auto_jump = true
	auto_jump_timer = 0
	force_move_x = dir
	force_move_x_timer = SIDE_BOUNCE_FORCE_TIME
	speed.x = SIDE_BOUNCE_SPEED * dir
	speed.y = BOUNCE_SPEED
	var_jump_speed = speed.y
	w.shake_dir(Vector2(dir, 0), 0.1)
	scale = Vector2(1.5, 0.5)
	collider = was
	return true

# Apply the generic recoil motion, used when an interaction knocks the player back.
func rebound(direction := 0) -> void:
	speed.x = direction * REBOUND_SPEED_X
	speed.y = REBOUND_SPEED_Y
	var_jump_speed = speed.y
	var_jump_timer = REBOUND_VAR_JUMP_TIME
	auto_jump = true
	auto_jump_timer = 0
	dash_attack_timer = 0
	wall_slide_timer = WALL_SLIDE_TIME
	wall_boost_timer = 0
	launched = false
	force_move_x_timer = 0
	_set_state(ST_NORMAL)

# Launch away from a world-space source, as for a bumper; optionally bias the result upward.
func explode_launch(from: Vector2, snap_up := true) -> void:
	sfx("spring", 0.7)
	w.freeze_for(0.1)
	var normal := center() - from
	normal = normal.normalized() if normal != Vector2.ZERO else Vector2.UP
	var dot := normal.dot(Vector2.DOWN)
	if snap_up and dot <= -0.7:
		normal = Vector2.UP
	elif dot <= 0.55 and dot >= -0.55:
		normal = Vector2(signf(normal.x), 0)
	speed = LAUNCH_SPEED * normal
	if speed.y <= 50:
		speed.y = minf(-150, speed.y)
		auto_jump = true
	if in_x == signf(speed.x):
		speed.x *= 1.2
	refill_dash()
	refill_stamina()
	dash_cooldown_timer = DASH_COOLDOWN
	if state == ST_LAUNCH:
		launched = true
	_set_state(ST_LAUNCH)

# Restore normal dash capacity only when needed; return whether the count changed.
func refill_dash() -> bool:
	if dashes < max_dashes():
		dashes = max_dashes()
		return true
	return false

# Consume the effect of a refill crystal only if dash or stamina recovery is useful.
func use_refill(two: bool) -> bool:
	var target := 2 if two else max_dashes()
	if dashes < target or stamina < CLIMB_TIRED_THRESHOLD:
		sfx("refill")
		dashes = target
		refill_stamina()
		return true
	return false

# Restore the full climbing stamina pool.
func refill_stamina() -> void:
	stamina = CLIMB_MAX_STAMINA

# Begin death only once and tell World to count it, play effects and arrange the respawn.
func die(dir: Vector2) -> void:
	if dead or Game.settings.invincible:
		return
	sfx("death")
	dead = true
	speed = Vector2.ZERO
	w.on_player_death(self, dir)

# ---------------- boosters / feathers ----------------
# Enter a booster bubble, remembering its centre and whether it launches a normal or red dash.
func boost(b, red: bool) -> void:
	sfx("boost")
	_set_state(ST_BOOST)
	speed = Vector2.ZERO
	boost_target = b.center()
	boost_red = red
	current_booster = b

# Start or extend feather flight and restore the stamina associated with that pickup.
func start_star_fly() -> bool:
	refill_stamina()
	if state == ST_STAR_FLY:
		star_fly_timer = STAR_FLY_TIME
	else:
		_set_state(ST_STAR_FLY)
	return true

# Notify dash-reactive behavior once per dash rather than once per physics step.
func _call_dash_events() -> void:
	if called_dash_events:
		return
	called_dash_events = true
	if current_booster != null:
		current_booster.player_boosted()
		current_booster = null

# ---------------- collisions ----------------
# Handle wall contact, including dash correction, retained speed and special movement modes.
func _on_collide_h(hit) -> void:
	if state == ST_STAR_FLY:
		speed.x = 0 if star_fly_timer < STAR_FLY_END_NO_BOUNCE else speed.x * STAR_FLY_WALL_BOUNCE
		return
	if state == ST_DREAM_DASH:
		return
	if state == ST_DASH or state == ST_RED_DASH:
		if on_ground and duck_free_at(pos + Vector2(signf(speed.x), 0)):
			set_ducking(true)
			return
		elif speed.y == 0 and speed.x != 0:
			for i in range(1, DASH_CORNER_CORRECTION + 1):
				for j in [1, -1]:
					if not solid_at(Vector2(signf(speed.x), i * j)):
						move_v_exact(i * j)
						move_h_exact(int(signf(speed.x)))
						return
	if _dream_dash_check(Vector2(signf(speed.x), 0)):
		_set_state(ST_DREAM_DASH)
		dash_attack_timer = 0
		return
	if wall_speed_retention_timer <= 0:
		wall_speed_retained = speed.x
		wall_speed_retention_timer = WALL_SPEED_RETENTION_TIME
	speed.x = 0
	dash_attack_timer = 0
	if state == ST_RED_DASH:
		_set_state(ST_HIT_SQUASH)

# Handle floor/ceiling contact, including landing, corner corrections and jump cancellation.
func _on_collide_v(hit) -> void:
	if speed.y > 40:
		sfx("land")
	if state == ST_STAR_FLY:
		speed.y = 0 if star_fly_timer < STAR_FLY_END_NO_BOUNCE else speed.y * STAR_FLY_WALL_BOUNCE
		return
	if state == ST_DREAM_DASH:
		return
	if speed.y > 0:
		if (state == ST_DASH or state == ST_RED_DASH) and not dash_started_on_ground:
			if speed.x <= 0:
				for i in range(-1, -DASH_CORNER_CORRECTION - 1, -1):
					if not on_ground_at(pos + Vector2(i, 0)):
						move_h_exact(i)
						move_v_exact(1)
						return
			if speed.x >= 0:
				for i in range(1, DASH_CORNER_CORRECTION + 1):
					if not on_ground_at(pos + Vector2(i, 0)):
						move_h_exact(i)
						move_v_exact(1)
						return
		if _dream_dash_check(Vector2(0, signf(speed.y))):
			_set_state(ST_DREAM_DASH)
			dash_attack_timer = 0
			return
		# dash slide (wavedash setup)
		if dash_dir.x != 0 and dash_dir.y > 0 and speed.y > 0:
			dash_dir = Vector2(signf(dash_dir.x), 0)
			speed.y = 0
			speed.x *= DODGE_SLIDE_SPEED_MULT
			set_ducking(true)
		if state != ST_CLIMB:
			var squish := minf(speed.y / FAST_MAX_FALL, 1.0)
			scale = Vector2(lerpf(1, 1.6, squish), lerpf(1, 0.4, squish))
			if speed.y >= MAX_FALL / 2:
				w.dust(pos, Vector2.UP, 8)
	else:
		if speed.y < 0:
			if speed.x <= 0:
				for i in range(1, UPWARD_CORNER_CORRECTION + 1):
					if not solid_at(Vector2(-i, -1)):
						pos += Vector2(-i, -1)
						return
			if speed.x >= 0:
				for i in range(1, UPWARD_CORNER_CORRECTION + 1):
					if not solid_at(Vector2(i, -1)):
						pos += Vector2(i, -1)
						return
			if var_jump_timer < VAR_JUMP_TIME - CEILING_VAR_JUMP_GRACE:
				var_jump_timer = 0
		if _dream_dash_check(Vector2(0, signf(speed.y))):
			_set_state(ST_DREAM_DASH)
			dash_attack_timer = 0
			return
	dash_attack_timer = 0
	speed.y = 0
	if state == ST_RED_DASH:
		_set_state(ST_HIT_SQUASH)

# Test whether contact may enter a dream block instead of stopping at its surface.
func _dream_dash_check(dir: Vector2) -> bool:
	if not (dash_attacking() and (dir.x == signf(dash_dir.x) or dir.y == signf(dash_dir.y))):
		return false
	var block = w.collide_dream(rect_at(pos + dir))
	if block == null:
		return false
	if w.collide_solid(rect_at(pos + dir), null, true) != null:
		var side := Vector2(absf(dir.y), absf(dir.x))
		var check_neg: bool
		var check_pos: bool
		if dir.x != 0:
			check_neg = speed.y <= 0
			check_pos = speed.y >= 0
		else:
			check_neg = speed.x <= 0
			check_pos = speed.x >= 0
		if check_neg:
			for i in range(-1, -DASH_CORNER_CORRECTION - 1, -1):
				if w.collide_solid(rect_at(pos + dir + side * i), null, true) == null:
					pos += side * i
					dream_block = block
					return true
		if check_pos:
			for i in range(1, DASH_CORNER_CORRECTION + 1):
				if w.collide_solid(rect_at(pos + dir + side * i), null, true) == null:
					pos += side * i
					dream_block = block
					return true
		return false
	dream_block = block
	return true

# ---------------- NORMAL ----------------
# Compute walking, airborne gravity, jumping, grabbing and dash requests for ordinary movement.
func _normal_update(dt: float) -> int:
	if underwater:
		return ST_SWIM
	var lb := lift_boost()
	if lb.y < 0 and was_on_ground and not on_ground and speed.y >= 0:
		speed.y = lb.y

	if grab_check and not is_tired() and not ducking():
		if speed.y >= 0 and signf(speed.x) != -facing:
			if climb_check(facing):
				set_ducking(false)
				return ST_CLIMB
			if in_y < 1:
				for i in range(1, CLIMB_UP_CHECK_DIST + 1):
					if not solid_at(Vector2(0, -i)) and climb_check(facing, -i):
						move_v_exact(-i)
						set_ducking(false)
						return ST_CLIMB

	if can_dash():
		speed += lift_boost()
		return _start_dash()

	if ducking():
		if on_ground and in_y != 1:
			if can_unduck():
				set_ducking(false)
				scale = Vector2(0.8, 1.2)
			elif speed.x == 0:
				for i in range(DUCK_CORRECT_CHECK, 0, -1):
					if can_unduck_at(pos + Vector2(i, 0)):
						move_h(DUCK_CORRECT_SLIDE * dt)
						break
					elif can_unduck_at(pos - Vector2(i, 0)):
						move_h(-DUCK_CORRECT_SLIDE * dt)
						break
	elif on_ground and in_y == 1 and speed.y >= 0:
		set_ducking(true)
		scale = Vector2(1.4, 0.6)

	# running and friction
	if ducking() and on_ground:
		speed.x = approach(speed.x, 0, DUCK_FRICTION * dt)
	else:
		var mult := 1.0 if on_ground else AIR_MULT
		if absf(speed.x) > MAX_RUN and signf(speed.x) == move_x:
			speed.x = approach(speed.x, MAX_RUN * move_x, RUN_REDUCE * mult * dt)
		else:
			speed.x = approach(speed.x, MAX_RUN * move_x, RUN_ACCEL * mult * dt)

	# fast fall
	if in_y == 1 and speed.y >= MAX_FALL:
		max_fall = approach(max_fall, FAST_MAX_FALL, FAST_MAX_ACCEL * dt)
		var half := MAX_FALL + (FAST_MAX_FALL - MAX_FALL) * 0.5
		if speed.y >= half:
			var t := minf(1.0, (speed.y - half) / (FAST_MAX_FALL - half))
			scale = Vector2(lerpf(1, 0.5, t), lerpf(1, 1.5, t))
	else:
		max_fall = approach(max_fall, MAX_FALL, FAST_MAX_ACCEL * dt)

	# gravity + wall slide
	if not on_ground:
		var mx := max_fall
		if (move_x == facing or (move_x == 0 and grab_check)) and in_y != 1:
			if speed.y >= 0 and wall_slide_timer > 0 and climb_bounds_check(facing) and solid_at(Vector2(facing, 0)) and can_unduck():
				set_ducking(false)
				wall_slide_dir = facing
			if wall_slide_dir != 0:
				mx = lerpf(MAX_FALL, WALL_SLIDE_START_MAX, wall_slide_timer / WALL_SLIDE_TIME)
				if wall_slide_timer / WALL_SLIDE_TIME > 0.65 and randf() < 0.3:
					w.dust(center() + Vector2(wall_slide_dir * 5, 4), Vector2.UP, 1)
		var gmult := 0.5 if (absf(speed.y) < HALF_GRAV_THRESHOLD and (jump_check or auto_jump)) else 1.0
		speed.y = approach(speed.y, mx, GRAVITY * gmult * dt)

	# variable jump
	if var_jump_timer > 0:
		if auto_jump or jump_check:
			speed.y = minf(speed.y, var_jump_speed)
		else:
			var_jump_timer = 0

	# jumping (down + jump on a jump-through drops through it: once inside it, it no longer holds the player)
	if jump_pressed():
		if in_y == 1 and on_ground and solid_first(Vector2.DOWN) == null and jumpthru_outside(Vector2.DOWN) != null:
			jump_buf = 0
			jump_grace_timer = 0
			on_ground = false
			pos.y += 1
			speed.y = maxf(speed.y, 40.0)  # falling already, or the jump-thru assist would lift us back on top
		elif jump_grace_timer > 0 and can_jump():
			jump()
		elif can_unduck():
			if wall_jump_check(1):
				if facing == 1 and grab_check and stamina > 0:
					climb_jump()
				elif dash_attacking() and dash_dir8() == Vector2.UP:
					super_wall_jump(-1)
				else:
					wall_jump(-1)
			elif wall_jump_check(-1):
				if facing == -1 and grab_check and stamina > 0:
					climb_jump()
				elif dash_attacking() and dash_dir8() == Vector2.UP:
					super_wall_jump(1)
				else:
					wall_jump(1)
	return ST_NORMAL

# ---------------- CLIMB ----------------
# Initialize a wall grab and reduce vertical momentum before wall-climbing begins.
func _climb_begin() -> void:
	sfx("climb")
	auto_jump = false
	speed.x = 0
	speed.y *= CLIMB_GRAB_Y_MULT
	wall_slide_timer = WALL_SLIDE_TIME
	climb_no_move_timer = CLIMB_NO_MOVE_TIME
	wall_boost_timer = 0
	last_climb_move = 0
	for i in CLIMB_CHECK_DIST:
		if not solid_at(Vector2(facing, 0)):
			pos.x += facing
		else:
			break

# Probe near the hands to determine whether the wall still supports a stationary hold.
func _slip_check(add_y := 0.0) -> bool:
	var r := hitbox()
	var at: Vector2
	if facing == 1:
		at = Vector2(r.end.x, r.position.y + 4 + add_y)
	else:
		at = Vector2(r.position.x - 1, r.position.y + 4 + add_y)
	return not point_solid(at) and not point_solid(at + Vector2(0, -4 + add_y))

# Hop over the top of a wall, retaining motion from a moving surface when appropriate.
func _climb_hop() -> void:
	var hit = solid_first(Vector2(facing, 0))
	if hit != null:
		climb_hop_solid = hit if typeof(hit) != TYPE_STRING else null
		if climb_hop_solid != null:
			climb_hop_solid_pos = climb_hop_solid.rect.position
		hop_wait_x = facing
		hop_wait_x_speed = facing * CLIMB_HOP_X
	else:
		hop_wait_x = 0
		speed.x = facing * CLIMB_HOP_X
	speed.y = minf(speed.y, CLIMB_HOP_Y)
	force_move_x = 0
	force_move_x_timer = CLIMB_HOP_FORCE_TIME

# Update wall climbing and stamina, and decide when to jump, slip or release the wall.
func _climb_update(dt: float) -> int:
	climb_no_move_timer -= dt
	if on_ground:
		stamina = CLIMB_MAX_STAMINA

	if jump_pressed() and (not ducking() or can_unduck()):
		if move_x == -facing:
			wall_jump(-facing)
		else:
			climb_jump()
		return ST_NORMAL

	if can_dash():
		speed += lift_boost()
		return _start_dash()

	if not grab_check:
		speed += lift_boost()
		return ST_NORMAL

	if not solid_at(Vector2(facing, 0)):
		if speed.y < 0:
			_climb_hop()
		return ST_NORMAL

	var target := 0.0
	var try_slip := false
	if climb_no_move_timer <= 0:
		if in_y == -1:
			target = CLIMB_UP_SPEED
			if solid_at(Vector2.UP) or (solid_at(Vector2(0, -6)) and _slip_check(-1)):
				if speed.y < 0:
					speed.y = 0
				target = 0
				try_slip = true
			elif _slip_check():
				_climb_hop()
				return ST_NORMAL
		elif in_y == 1:
			target = CLIMB_DOWN_SPEED
			if on_ground:
				if speed.y > 0:
					speed.y = 0
				target = 0
			elif randf() < 0.3:
				w.dust(center() + Vector2(facing * 5, 4), Vector2.UP, 1)
		else:
			try_slip = true
	else:
		try_slip = true
	last_climb_move = int(signf(target))
	if try_slip and _slip_check():
		target = CLIMB_SLIP_SPEED
	speed.y = approach(speed.y, target, CLIMB_ACCEL * dt)

	if in_y != 1 and speed.y > 0 and not solid_at(Vector2(facing, 1)):
		speed.y = 0

	if climb_no_move_timer <= 0:
		if last_climb_move == -1:
			stamina -= CLIMB_UP_COST * dt
		elif last_climb_move == 0:
			stamina -= CLIMB_STILL_COST * dt

	if stamina <= 0:
		speed += lift_boost()
		return ST_NORMAL
	return ST_CLIMB

# ---------------- DASH ----------------
# Request the dash state and its initial freeze timing; the state-entry method performs setup.
func _start_dash() -> int:
	was_dash_b = dashes == 2
	dashes = maxi(0, dashes - 1)
	dash_buf = 0
	return ST_DASH

# Spend a dash and initialize the attack/cooldown windows before the timed launch starts.
func _dash_begin() -> void:
	sfx("dash")
	called_dash_events = false
	dash_started_on_ground = on_ground
	launched = false
	w.freeze_for(0.05)
	dash_cooldown_timer = DASH_COOLDOWN
	dash_refill_cooldown_timer = DASH_REFILL_COOLDOWN
	wall_slide_timer = WALL_SLIDE_TIME
	trail_timer = 0
	dash_attack_timer = DASH_ATTACK_TIME
	before_dash_speed = speed
	speed = Vector2.ZERO
	dash_dir = Vector2.ZERO
	if not on_ground and ducking() and can_unduck():
		set_ducking(false)

# Commit the chosen dash direction and speed after the initial dash sequence delay.
func _dash_co_start() -> void:
	var dir := last_dash_aim
	var new_speed := dir * DASH_SPEED
	if signf(before_dash_speed.x) == signf(new_speed.x) and absf(before_dash_speed.x) > absf(new_speed.x):
		new_speed.x = before_dash_speed.x
	speed = new_speed
	dash_dir = dir
	w.shake_dir(dash_dir, 0.2)
	if dash_dir.x != 0:
		facing = int(signf(dash_dir.x))
	_call_dash_events()
	if on_ground and dash_dir.x != 0 and dash_dir.y > 0 and speed.y > 0 and w.collide_dream(rect_at(pos + Vector2.DOWN)) == null:
		dash_dir = Vector2(signf(dash_dir.x), 0)
		speed.y = 0
		speed.x *= DODGE_SLIDE_SPEED_MULT
		set_ducking(true)
	w.add_trail(self)
	trail_timer = 0.08

# dash_dir snapped to 8 ways, so a free-aim dash (DASH_DIRS 4) close to an axis still allows super jumps
# Snap the dash direction onto eight compass directions for mechanics needing discrete directions.
func dash_dir8() -> Vector2:
	var a := snappedf(dash_dir.angle(), PI / 4)
	return Vector2(roundf(cos(a)), roundf(sin(a)))

# Nudge a nearby sideways dash onto a one-way surface, preserving the intended forgiving feel.
func _jumpthru_dash_nudge() -> void:
	var jt = w.collide_jumpthru(hitbox())
	if jt != null and bottom() - jt.rect.position.y <= DASH_H_JUMPTHRU_NUDGE:
		move_v_exact(jt.rect.position.y - bottom())

# Check special jump combinations available during a normal or red dash.
func _dash_jumps(red: bool) -> int:
	# shared by DASH and RED_DASH: super jump, super wall jump, wall jump out of a dash
	var d8 := dash_dir8()
	if d8.y == 0:
		_jumpthru_dash_nudge()
		if can_unduck() and jump_pressed() and jump_grace_timer > 0:
			super_jump()
			return ST_NORMAL
	if d8 == Vector2.UP:
		if jump_pressed() and can_unduck():
			if wall_jump_check(1):
				super_wall_jump(-1)
				return ST_NORMAL
			elif wall_jump_check(-1):
				super_wall_jump(1)
				return ST_NORMAL
	elif not red or d8.y != 0:
		if jump_pressed() and can_unduck():
			if wall_jump_check(1):
				wall_jump(-1)
				return ST_NORMAL
			elif wall_jump_check(-1):
				wall_jump(1)
				return ST_NORMAL
	return -1

# Update a normal dash and check opportunities to interrupt it with a special jump.
func _dash_update(dt: float) -> int:
	if trail_timer > 0:
		trail_timer -= dt
		if trail_timer <= 0:
			w.add_trail(self)
	var r := _dash_jumps(false)
	if r != -1:
		return r
	if speed != Vector2.ZERO and randf() < 0.5:
		w.dust(center(), -dash_dir, 1, HAIR_TWO if was_dash_b else HAIR_NORMAL)
	return ST_DASH

# ---------------- BOOST / RED DASH / HIT SQUASH ----------------
# Pull the player into the bubble centre and check for an early player-triggered launch.
func _boost_update(dt: float) -> int:
	var target_add := aim_raw * 3
	var c := Vector2(collider.position) + Vector2(collider.size) / 2.0
	var to := approach_v(pos + rem, boost_target - c + target_add, BOOST_MOVE_SPEED * dt)
	move_to_x(to.x)
	move_to_y(to.y)
	if dash_buf > 0:
		dash_buf = 0
		return ST_RED_DASH if boost_red else ST_DASH
	return ST_BOOST

# Initialize the booster-driven red dash, which follows different resource and stopping rules.
func _red_dash_begin() -> void:
	called_dash_events = false
	dash_started_on_ground = false
	w.freeze_for(0.05)
	dash_cooldown_timer = DASH_COOLDOWN
	dash_refill_cooldown_timer = DASH_REFILL_COOLDOWN
	dash_attack_timer = DASH_ATTACK_TIME
	speed = Vector2.ZERO
	if not on_ground and ducking() and can_unduck():
		set_ducking(false)

# Keep the red dash moving and handle its allowed jump interruptions.
func _red_dash_update(_dt: float) -> int:
	if can_dash():
		return _start_dash()
	var r := _dash_jumps(true)
	if r != -1:
		return r
	if randf() < 0.5:
		w.add_trail(self)
	return ST_RED_DASH

# Apply the brief movement restriction and friction after a dash impact.
func _hit_squash_update(dt: float) -> int:
	speed.x = approach(speed.x, 0, HIT_SQUASH_FRICTION * dt)
	speed.y = approach(speed.y, 0, HIT_SQUASH_FRICTION * dt)
	if jump_pressed():
		if on_ground and can_jump():
			jump()
		elif wall_jump_check(1):
			wall_jump(-1)
		elif wall_jump_check(-1):
			wall_jump(1)
		else:
			jump_buf = 0
		return ST_NORMAL
	if can_dash():
		return _start_dash()
	if grab_check and climb_check(facing):
		return ST_CLIMB
	if hit_squash_no_move_timer > 0:
		hit_squash_no_move_timer -= dt
	else:
		return ST_NORMAL
	return ST_HIT_SQUASH

# Update an external launch until normal steering is allowed again.
func _launch_update(dt: float) -> int:
	if can_dash():
		return _start_dash()
	if speed.y < 0:
		speed.y = approach(speed.y, MAX_FALL, GRAVITY * 0.5 * dt)
	else:
		speed.y = approach(speed.y, MAX_FALL, GRAVITY * 0.25 * dt)
	speed.x = approach(speed.x, 0, RUN_ACCEL * 0.2 * dt)
	return ST_NORMAL if speed.length() < LAUNCH_CANCEL_THRESHOLD else ST_LAUNCH

# ---------------- DREAM DASH ----------------
# Initialize travel through dream terrain and the minimum time before a permitted exit.
func _dream_dash_begin() -> void:
	sfx("dream")
	speed = dash_dir * DASH_SPEED
	dream_dash_can_end_timer = DREAM_DASH_MIN_TIME
	stamina = CLIMB_MAX_STAMINA
	dream_jump = false

# Clean up dream movement and restore the resources granted when leaving it.
func _dream_dash_end() -> void:
	if not dream_jump:
		auto_jump = true
		auto_jump_timer = 0
	refill_dash()
	refill_stamina()
	if dream_block != null:
		if dash_dir.x != 0:
			jump_grace_timer = JUMP_GRACE_TIME
			dream_jump = true
		else:
			jump_grace_timer = 0
		dream_block = null

# Check the exit box so leaving a dream block cannot place the player inside ordinary rock.
func _dream_dashed_into_solid() -> bool:
	if not solid_at():
		return false
	for x in range(1, DREAM_DASH_END_WIGGLE + 1):
		for xm in [-1, 1]:
			for y in range(1, DREAM_DASH_END_WIGGLE + 1):
				for ym in [-1, 1]:
					var add := Vector2(x * xm, y * ym)
					if not solid_at(add):
						pos += add
						return false
	return true

# Travel through dream blocks and resolve exiting into free space or forbidden solids.
func _dream_dash_update(dt: float) -> int:
	var old_pos := pos
	naive_move(speed * dt)
	if dream_dash_can_end_timer > 0:
		dream_dash_can_end_timer -= dt
	var block = w.collide_dream(hitbox())
	if block == null:
		if _dream_dashed_into_solid():
			if Game.settings.invincible:
				pos = old_pos
				speed *= -1
			else:
				die(Vector2.ZERO)
				return ST_DREAM_DASH
		elif dream_dash_can_end_timer <= 0:
			w.freeze_for(0.05)
			if jump_pressed() and dash_dir.x != 0 and can_jump():
				dream_jump = true
				jump()
			elif grab_check and (dash_dir.y >= 0 or dash_dir.x != 0) and ((move_x == 1 and climb_check(1)) or (move_x == -1 and climb_check(-1))):
				facing = move_x
				return ST_CLIMB
			return ST_NORMAL
	else:
		dream_block = block
		if randf() < 0.15:
			w.add_trail(self)
	return ST_DREAM_DASH

# ---------------- STAR FLY (feather) ----------------
# Start the feather transformation before fully steerable flight begins.
func _star_fly_begin() -> void:
	sfx("feather")
	star_fly_transforming = true
	star_fly_timer = STAR_FLY_TIME
	star_fly_speed_lerp = 0
	jump_grace_timer = 0
	collider = HB_FLY
	hurtbox = HURT_FLY

# Restore the ordinary collision shape and limit momentum when feather flight finishes.
func _star_fly_end() -> void:
	collider = HB_NORMAL
	hurtbox = HURT_NORMAL
	if solid_at():
		var start := pos
		pos.y -= HB_NORMAL.end.y - HB_FLY.end.y
		if not solid_at():
			return
		pos = start
		set_ducking(true)
		pos.y -= HB_DUCK.end.y - HB_FLY.end.y
		if not solid_at():
			return
		pos = start

# Steer feather flight with acceleration and turning limits, then handle its expiration.
func _star_fly_update(dt: float) -> int:
	if star_fly_transforming:
		speed = approach_v(speed, Vector2.ZERO, STAR_FLY_TRANSFORM_DECCEL * dt)
		return ST_STAR_FLY
	var aim := aim_raw
	var slow := false
	if aim == Vector2.ZERO:
		slow = true
		aim = star_fly_last_dir
	var cur := speed.normalized() if speed != Vector2.ZERO else Vector2.ZERO
	if cur == Vector2.ZERO:
		cur = aim
	else:
		var diff := wrapf(aim.angle() - cur.angle(), -PI, PI)
		cur = cur.rotated(clampf(diff, -STAR_FLY_ROTATE_SPEED * dt, STAR_FLY_ROTATE_SPEED * dt))
	star_fly_last_dir = cur
	var max_speed: float
	if slow:
		star_fly_speed_lerp = 0
		max_speed = STAR_FLY_SLOW_SPEED
	elif cur != Vector2.ZERO and cur.dot(aim) >= 0.45:
		star_fly_speed_lerp = approach(star_fly_speed_lerp, 1, dt / STAR_FLY_MAX_LERP_TIME)
		max_speed = lerpf(STAR_FLY_TARGET_SPEED, STAR_FLY_MAX_SPEED, star_fly_speed_lerp)
	else:
		star_fly_speed_lerp = 0
		max_speed = STAR_FLY_TARGET_SPEED
	speed = cur * approach(speed.length(), max_speed, STAR_FLY_ACCEL * dt)
	if randf() < 0.5:
		w.dust(center(), -speed.normalized(), 1, HAIR_FLY)

	if jump_pressed():
		if on_ground_at(pos, 3) and can_jump():
			jump()
			return ST_NORMAL
		elif wall_jump_check(-1):
			wall_jump(1)
			return ST_NORMAL
		elif wall_jump_check(1):
			wall_jump(-1)
			return ST_NORMAL
	if grab_check:
		if in_x != -1 and climb_check(1):
			facing = 1
			return ST_CLIMB
		elif in_x != 1 and climb_check(-1):
			facing = -1
			return ST_CLIMB
	if can_dash():
		return _start_dash()

	star_fly_timer -= dt
	if star_fly_timer <= 0:
		if in_y == -1:
			speed.y = STAR_FLY_EXIT_UP
		if in_y < 1:
			var_jump_speed = speed.y
			auto_jump = true
			auto_jump_timer = 0
			var_jump_timer = VAR_JUMP_TIME
		speed.y = minf(speed.y, STAR_FLY_MAX_EXIT_Y)
		if absf(speed.x) > STAR_FLY_MAX_EXIT_X:
			speed.x = STAR_FLY_MAX_EXIT_X * signf(speed.x)
		return ST_NORMAL
	return ST_STAR_FLY

# ---------------- visuals ----------------
# ---------------- attack (placeholder weapon: a triangle swung through ATTACK_ARC degrees) ----------------
# A layer on top of the movement state: swing while running, dashing (a dash attack), climbing or flying.
# Not inside bubbles or dream blocks. Movement is never changed by it.
const NO_ATTACK_STATES := [ST_BOOST, ST_RED_DASH, ST_DREAM_DASH]

# Report whether the current sword swing still has an active hit window.
func attacking() -> bool:
	return attack_timer > 0

# Start buffered sword swings, track their active/cooldown timers and test for hits.
func _attack_update(dt: float) -> void:
	if attack_timer > 0:
		attack_timer -= dt
		if state in NO_ATTACK_STATES:
			attack_timer = 0
	elif attack_buf > 0 and attack_cooldown_timer <= 0 and ATTACK_DIRS != 0 and state not in NO_ATTACK_STATES:
		attack_buf = 0
		sfx("attack")
		attack_timer = ATTACK_TIME
		attack_cooldown_timer = ATTACK_COOLDOWN
		attack_dir = dir_for(ATTACK_DIRS)
		attack_hit.clear()
		attack_log.append(w.time if w != null else 0.0)
		if attack_log.size() > 10:
			attack_log.pop_front()
	if attack_timer > 0:
		_attack_hits()

# Entities with a hit() method inside the swing's sector (radius ATTACK_RANGE from the centre) get struck once.
# Strike eligible objects inside the sword sector once each per swing.
func _attack_hits() -> void:
	if w == null:
		return
	var c := center()
	var half := deg_to_rad(ATTACK_ARC) / 2.0
	for e in w.ents:
		if not e.collidable or not e.has_method("hit") or e in attack_hit:
			continue
		var r := Rect2(e.rect)
		var v := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y)) - c
		if v.length() <= ATTACK_RANGE and (v.length() < 1.0 or absf(attack_dir.angle_to(v)) <= half):
			attack_hit.append(e)
			e.hit(self)

# Draw the visible sword arc from the same direction and timing used by attack logic.
func _draw_attack(ci: CanvasItem) -> void:
	var t := 1.0 - clampf(attack_timer / maxf(ATTACK_TIME, 0.001), 0, 1)
	var half := deg_to_rad(ATTACK_ARC) / 2.0
	var s := float(facing) if attack_dir.x == 0 else signf(attack_dir.x)  # overhead swing: starts above, ends below
	var base := attack_dir.angle()
	var a0 := base - s * half
	var a := a0 + s * 2.0 * half * t
	var c := center()
	ci.draw_arc(c, ATTACK_RANGE - 2, minf(a0, a), maxf(a0, a), 12, Color(1, 1, 1, 0.35), 2.0)
	var u := Vector2.from_angle(a)
	var n := u.orthogonal()
	ci.draw_colored_polygon(PackedVector2Array([c + u * ATTACK_RANGE, c + u * 4 + n * 2, c + u * 4 - n * 2]), Color("e8eef8"))

# Choose brown when a dash is available, gray when spent, or the special feather-flight cue.
func hair_color() -> Color:
	if state == ST_STAR_FLY:
		return HAIR_FLY if (star_fly_timer > STAR_FLY_END_FLASH or flash) else HAIR_NORMAL
	if w != null and w.adventure() and Game.adv.energy < 0.2 * Game.Adventure.energy_max(Game.adv):
		return HAIR_USED  # grey below 20% energy
	if dashes == 2:
		return HAIR_TWO
	if dashes == 1:
		return HAIR_NORMAL
	return HAIR_USED

# Return a camera focus point derived from the player position and current movement.
func camera_target() -> Vector2:
	var t := pos + Vector2(0, -6)
	if state == ST_STAR_FLY:
		t += speed * 0.2
	elif state == ST_RED_DASH:
		t += Vector2(signf(speed.x), signf(speed.y)) * 48
	return t

# Choose and time the sprite animation independently from physical movement.
func _update_visuals(dt: float) -> void:
	scale.x = approach(scale.x, 1.0, 1.75 * dt)
	scale.y = approach(scale.y, 1.0, 1.75 * dt)
	flash_t += dt
	anim_t += dt
	landing_visual_timer = maxf(0.0, landing_visual_timer - dt)
	if on_ground and not was_on_ground and state == ST_NORMAL:
		landing_visual_timer = 0.15
	var animation := _animation()
	if animation != visual_animation:
		visual_animation = animation
		visual_clock = 0.0
	else:
		var rate := clampf(absf(speed.x) / maxf(MAX_RUN, 1.0), 0.4, 1.8) if animation == "run" else 1.0
		# A stationary wall hold keeps its contact pose instead of climbing in place.
		if animation == "climb" and absf(speed.y) < 1:
			rate = 0.0
		visual_clock += dt * rate
	if flash_t >= 0.05:
		flash_t = 0
		flash = not flash
	var hair_frame := _frame()
	var hair_lean := 1 if visual_animation in ["run", "dash", "boost"] else -1 if visual_animation == "skid" else 0
	var head := pos + Vector2(facing * (-2 + hair_lean), -CharacterArt.pose_height(visual_animation, hair_frame.x) + 3 + CharacterArt.head_drop(visual_animation, hair_frame.x))
	hair[0] = head
	_update_hair(dt)

# Celeste's PlayerHair: each segment moves toward a rest spot below and behind the one before it
# at a capped speed (slower toward the tip), so the hair trails, swings and settles on its own.
const HAIR_MAX_DIST := 2.0
# Move the trailing hair chain toward the head while limiting gaps between its pixel clumps.
func _update_hair(dt: float) -> void:
	hair_wave += dt * 4.0
	# A round root settles into a tapered lock; speed gently lifts the ends.
	var motion := clampf(absf(speed.x) / maxf(MAX_RUN, 1.0), 0.0, 1.0)
	var down := lerpf(1.6, 0.9, motion)
	var back := lerpf(0.5, 1.1, motion)
	var sway := 0.25 if absf(speed.x) < 1 and on_ground else 0.0
	var follow := 64.0
	if state == ST_STAR_FLY:
		down = 0.6
		back = 1.2
		sway = 0.6
	elif state == ST_DASH or state == ST_RED_DASH:
		follow = 40.0  # streams out behind a dash
	var target := hair[0] + Vector2(-facing * back * 2.0, sin(hair_wave) * sway + down)
	for i in range(1, hair.size()):
		var mult := (1.0 - float(i) / hair.size() * 0.5) * follow
		hair[i] = hair[i].move_toward(target, mult * dt)
		if hair[i].distance_to(hair[i - 1]) > HAIR_MAX_DIST:
			hair[i] = hair[i - 1] + (hair[i] - hair[i - 1]).normalized() * HAIR_MAX_DIST
		target = hair[i] + Vector2(-facing * back, sin(hair_wave + i * 0.8) * sway + down)

# Select the animation name from movement mode, grounded state and velocity.
func _animation() -> String:
	if state == ST_STAR_FLY:
		return "fly"
	if state == ST_DASH or state == ST_RED_DASH or state == ST_DREAM_DASH:
		return "dash"
	if state == ST_BOOST:
		return "boost"
	if state == ST_CLIMB:
		return "climb"
	if wall_slide_dir != 0 and not on_ground:
		return "wall_slide"
	if ducking():
		return "duck"
	if not on_ground or state == ST_SWIM:  # underwater: always the air poses, never walking
		if speed.y < -40:
			return "jump"
		if speed.y < 40:
			return "apex"
		return "fall"
	if in_x != 0 and absf(speed.x) > 20 and signi(in_x) != signf(speed.x):
		return "skid"
	if landing_visual_timer > 0 and absf(speed.x) < 10:
		return "land"
	return "run" if absf(speed.x) > 1 else "idle"

# Convert the selected animation and its local clock into an atlas column and row.
func _frame() -> Vector2i:
	return CharacterArt.frame(visual_animation, visual_clock)

# Draw trailing hair, the body sprite and any sword swing using the current visual state.
func draw(ci: CanvasItem) -> void:
	if dead:
		return
	var hc := hair_color()
	# Flowing hair retains the familiar dash-availability colour cue.
	# pixel clumps, tip first so the larger ones near the head sit on top
	var shades := CharacterArt.hair_shades(hc)
	# Fill between clumps before adding highlights: sharp turns cannot split the lock.
	for i in range(hair.size() - 1, 0, -1):
		ci.draw_line((hair[i - 1] + draw_off).round(), (hair[i] + draw_off).round(), shades["h"], 2 if i < 3 else 1, false)
	for i in range(hair.size() - 1, -1, -1):
		var mask: Array = CharacterArt.HAIR_CLUMPS[mini(i, CharacterArt.HAIR_CLUMPS.size() - 1)]
		var tl := (hair[i] + draw_off).round() - Vector2(floori(mask[0].length() / 2.0), floori(mask.size() / 2.0))
		for y in mask.size():
			for x in mask[y].length():
				var ch: String = mask[y][x if facing > 0 else mask[y].length() - 1 - x]
				if shades.has(ch):
					ci.draw_rect(Rect2(tl + Vector2(x, y), Vector2.ONE), shades[ch])
	var mod := Color.WHITE
	if is_tired() and flash:
		mod = Color(1, 0.5, 0.5)
	elif state == ST_STAR_FLY:
		mod = Color(1, 0.95, 0.6)
	var f := _frame()
	var sc := Vector2(scale.x * facing, scale.y)
	ci.draw_set_transform((pos + draw_off).round(), 0, sc)
	ci.draw_texture_rect_region(CharacterArt.texture(hc), Rect2(-8, -16, 16, 16), Rect2(f * 16, Vector2(16, 16)), mod)
	ci.draw_set_transform(Vector2.ZERO)
	if attacking():
		_draw_attack(ci)
