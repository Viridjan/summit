extends RefCounted
# Registry and behavior of the objects placed in level JSON: hazards, pickups, platforms and enemies.
# TYPES connects each saved type ID to an editor label, sizing flag, color and implementation class.
# Each object is a small RefCounted object. World calls its setup/update/touch/draw methods explicitly;
# these are project conventions, unlike Godot's automatic _ready/_process callbacks.
# A class inherits common behavior with 'extends'; super.method() calls the parent's implementation.
# Editor previews pass w=null: setup and drawing must work without a running player or room.
# Positions and rectangles use pixels; timer values and update(dt) use seconds.
# The image may extend outside rect: movement, damage, interaction and visibility use separate boxes.
# Reading help: docs/CODE_GUIDE.md.

# All level objects. Each is a small class; TYPES drives the editor palette.
# Behaviour follows Celeste's entities, simplified where noted.

const T := 8
const Art := preload("res://scripts/art.gd")
const EnemyArt := preload("res://scripts/enemy_art.gd")
const BlockArt := preload("res://scripts/block_art.gd")
const ButtonArt := preload("res://scripts/button_art.gd")
const IslandArt := preload("res://scripts/island_art.gd")
const MonsterLib := preload("res://scripts/monster_library.gd")

# The entity registry: the one place a type is declared.
# type id (saved in level JSON) -> [editor label, sized (drag a rect in the editor), palette color, class]
# See docs/ADDING_ENTITIES.md before adding a type.
# Registry row layout: [editor label, can drag to size, representative color, implementation class].
# JSON uses the string key (for example refill), not the class name.
const TYPES := {
	"spawn": ["Spawn", false, Color("ffffff"), SpawnMarker],
	"spikes_up": ["Spikes ^", false, Color("dddddd"), Spikes],
	"spikes_down": ["Spikes v", false, Color("dddddd"), Spikes],
	"spikes_left": ["Spikes <", false, Color("dddddd"), Spikes],
	"spikes_right": ["Spikes >", false, Color("dddddd"), Spikes],
	"spring_up": ["Spring ^", false, Color("e0a030"), Spring],
	"spring_left": ["Spring <", false, Color("e0a030"), Spring],
	"spring_right": ["Spring >", false, Color("e0a030"), Spring],
	"refill": ["Dash Crystal", false, Color("4ee05a"), Refill],
	"refill_two": ["Double Crystal", false, Color("ff6def"), Refill],
	"strawberry": ["Star", false, Color("ffd34e"), Star],  # id kept for old level files
	"energy_fragment": ["Energy Fragment (Interact)", false, Color("8ce1cc"), Discovery],
	"discovery_npc": ["Character (Interact)", false, Color("a4b7cf"), Discovery],
	"jumpthru": ["Jump-Through", true, Color("a07850"), JumpThru],
	"crumble": ["Crumble Block", true, Color("8a7a6a"), Crumble],
	"falling": ["Falling Block", true, Color("7a6a9a"), FallingBlock],
	"zip": ["Zip Mover", true, Color("d0b040"), ZipMover],
	"dream": ["Dream Block", true, Color("101018"), DreamBlock],
	"booster": ["Green Bubble", false, Color("2ea04f"), Booster],
	"booster_red": ["Red Bubble", false, Color("d03a3a"), Booster],
	"bumper": ["Bumper", false, Color("4060d0"), Bumper],
	"feather": ["Feather", false, Color("ffd65c"), Feather],
	"goal": ["Crystal Heart", false, Color("50b0ff"), Goal],
	# adventure ability pickups: the part after "ability_" must be in Adventure.ABILITIES
	"ability_dash": ["Dash Ability", false, Color("ff7a3a"), AbilityOrb],
	"ability_climb": ["Climb Ability", false, Color("3ad0ff"), AbilityOrb],
	"ability_attack": ["Attack Ability", false, Color("e8e8e8"), AbilityOrb],
	# adventure stamina (docs/STORY_DESIGN.md): a new block once per run; an orb that refills stamina
	"stamina_block": ["Stamina Block", false, Color("7cf0c0"), StaminaBlock],
	"stamina_orb": ["Stamina Orb", false, Color("b8ffe0"), StaminaOrb],
	# door: drag its size; "id" names it, "to" = "room:id" (or just "id" in the same level) is where it leads.
	# Links rooms that don't touch (elevators, trams) or that sit behind a wall.
	"door": ["Door", true, Color("40e0ff"), Door],
	# house door: a visible wooden door; stand at it and press interact (S / pad B) to go through ("id"/"to" like the Door)
	"house_door": ["House Door", true, Color("8a5a34"), HouseDoor],
	# building: scenery behind the player (walk through it), "style" = "house" (roof on top) or "tower" (stone)
	"building": ["Building", true, Color("c8a878"), Building],
	# placeholders from reference maps: "text" names the thing (e.g. "Crawlid", "grub jar")
	"enemy": ["Enemy (placeholder)", true, Color("e04848"), Placeholder],
	# enemies: one row per family, then that family's variants (see CombatEnemy.VARIANTS)
	"enemy_thornmite": ["Thornmite · wall crawler", false, Color("e6a76c"), ThornmiteEnemy],
	"enemy_skree": ["Dropwing · ceiling dive", false, Color("e8bd78"), SkreeEnemy],
	"enemy_bat": ["Duskflit · swoop", false, Color("9872af"), BatEnemy],
	"enemy_skeleton": ["Ossling · bone throw", false, Color("d8d8bd"), SkeletonEnemy],
	"enemy_hornback": ["Hornback · charge", false, Color("6483aa"), HornbackEnemy],
	"enemy_fuzzbob": ["Fuzzbob · bouncing flight", false, Color("83b7a0"), FuzzbobEnemy],
	"enemy_cragjaw": ["Cragjaw · leaping brute", false, Color("a58a6a"), CragjawEnemy],
	"enemy_murkspore": ["Murkspore · spore spitter", false, Color("8a6aa8"), MurksporeEnemy],
	"enemy_mosstrot": ["Mosstrot · calm wanderer", false, Color("7fae4e"), MosstrotEnemy],
	"enemy_monster": ["Monster · from the action library", false, Color("d070a0"), ActionMonster],
	"enemy_thornmite_swift": ["Thornmite · Swift", false, Color("f08d87"), ThornmiteEnemy],
	"enemy_thornmite_venom": ["Thornmite · Venom", false, Color("8fd14f"), ThornmiteEnemy],
	"enemy_thornmite_brood": ["Thornmite · Brood", false, Color("c8d06a"), ThornmiteEnemy],
	"enemy_thornmite_giant": ["Thornmite · Giant", false, Color("c0703a"), ThornmiteEnemy],
	"enemy_skree_swift": ["Dropwing · Swift", false, Color("f08d87"), SkreeEnemy],
	"enemy_skree_armored": ["Dropwing · Armored", false, Color("899cae"), SkreeEnemy],
	"enemy_skree_venom": ["Dropwing · Venom", false, Color("8fd14f"), SkreeEnemy],
	"enemy_bat_swift": ["Duskflit · Swift", false, Color("f08d87"), BatEnemy],
	"enemy_bat_brood": ["Duskflit · Brood", false, Color("c8d06a"), BatEnemy],
	"enemy_skeleton_armored": ["Ossling · Armored", false, Color("899cae"), SkeletonEnemy],
	"enemy_skeleton_shielded": ["Ossling · Shielded", false, Color("d3ad74"), SkeletonEnemy],
	"enemy_skeleton_giant": ["Ossling · Giant", false, Color("c0703a"), SkeletonEnemy],
	"enemy_hornback_shielded": ["Hornback · Shielded", false, Color("d3ad74"), HornbackEnemy],
	"enemy_hornback_swift": ["Hornback · Swift", false, Color("f08d87"), HornbackEnemy],
	"enemy_hornback_giant": ["Hornback · Giant", false, Color("c0703a"), HornbackEnemy],
	"enemy_fuzzbob_brood": ["Fuzzbob · Brood", false, Color("c8d06a"), FuzzbobEnemy],
	"enemy_fuzzbob_venom": ["Fuzzbob · Venom", false, Color("8fd14f"), FuzzbobEnemy],
	"enemy_fuzzbob_giant": ["Fuzzbob · Giant", false, Color("c0703a"), FuzzbobEnemy],
	"enemy_cragjaw_armored": ["Cragjaw · Armored", false, Color("899cae"), CragjawEnemy],
	"enemy_cragjaw_shielded": ["Cragjaw · Shielded", false, Color("d3ad74"), CragjawEnemy],
	"enemy_murkspore_swift": ["Murkspore · Swift", false, Color("f08d87"), MurksporeEnemy],
	"enemy_murkspore_venom": ["Murkspore · Venom", false, Color("8fd14f"), MurksporeEnemy],
	"enemy_murkspore_brood": ["Murkspore · Brood", false, Color("c8d06a"), MurksporeEnemy],
	"breakable": ["Breakable (placeholder)", true, Color("e09a40"), Placeholder],
	# breakable wall: solid until struck "hp" times (default 3) by the attack; stays broken for the run
	"breakwall": ["Breakable Wall", true, Color("b08a60"), BreakWall],
	"water": ["Water", true, Color("4a8ae0"), Liquid],
	# story jungle (docs/STORY_DESIGN.md 1.5): a leafy jump-through, and falling water that pushes the player down
	"waterfall": ["Waterfall", true, Color("8ac8f0"), Waterfall],
	"acid": ["Acid", true, Color("6ae070"), Liquid],
	# design note: marks what a spot needs (a power-up not built yet, a boss, a secret...)
	"note": ["Note", false, Color("ffe08a"), Note],
	# Boss 1, the Ape (docs/STORY_DESIGN.md section 2), with its arena pieces
	"boss_ape": ["Ape (boss)", false, Color("6a4430"), Ape],
	# the Ape chasing the player up the sand cave: wakes when the player passes x "trigger", gives up at x "end"
	"ape_chase": ["Ape (chase)", false, Color("8a5440"), ApeChase],
	"ape_trunk": ["Trunk (Ape arena)", true, Color("7a5638"), ApeTrunk],
	"boss_gate": ["Boss Gate", true, Color("4a6a3a"), BossGate],
	# walks the player in d.dir (1 right, -1 left) for d.time seconds on touch; "while_boss": only while an Ape lives
	"auto_walk": ["Auto Walk", true, Color("a0d0ff"), AutoWalk],
	# fixed camera: while the player is inside the zone, the view centres on d.focus [x, y] px (default: the zone's centre)
	"camera_zone": ["Camera Zone", true, Color("c0a0ff"), CameraZone],
	# Boss 2, the volcanic guardian (docs/reviews/eastern-island): bait its eruptions onto the vent plugs
	"boss_guardian": ["Guardian (boss)", true, Color("7a3a2a"), Guardian],
	"vent_plug": ["Vent Plug", false, Color("ff7a30"), VentPlug],
	# rocks drop from the ceiling strip it covers, one at a time, at random spots; d.every: seconds between rocks
	"rockfall": ["Falling Rocks", true, Color("8a8478"), RockFall],
	"village_elf": ["Treetop Elf", false, Color("648f85"), IslandProp],
	"village_mage": ["Lighthouse Mage", false, Color("8c687f"), IslandProp],
	"island_prop": ["Island Landmark", false, Color("969098"), IslandProp],
}

const DOOR_TYPES := ["door", "house_door"]  # objects that link to another door by "id"/"to"

# Construct the implementation class for a saved type ID; unknown types return no object.
static func make(w, d: Dictionary):
	var entry = TYPES.get(d.t)
	return entry[3].new(w, d) if entry != null else null

# Base entity. The contract every type follows (details: docs/ADDING_ENTITIES.md):
#   w          world (null for editor previews: setup/draw must work without it)
#   d          the level JSON dict; rect = d.x, d.y, d.w|8, d.h|8 (setup may reshape it)
#   flags      solid -> World.solids (blocks the player; dream also -> World.dreams)
#              jumpthru -> World.jumpthrus; neither -> World.touchables (touch() on overlap)
#              collidable (live on/off switch), safe (ground that banks collected stars)
#   setup()    one-time init from d     update(dt)  every tick, even offscreen
#   draw(ci)   stay inside vis_rect()   touch(p)    player hurtbox overlaps touch_rect()
#   respawn    seconds until usable again (convention for pickups)
#   Player hooks entities may call: die, bounce, super_bounce, side_bounce, explode_launch,
#   use_refill, refill_dash, refill_stamina, boost, start_star_fly, set_lift_speed.
#   World hooks: freeze_for, shake_dir, burst, dust, collect_berry, complete.
# Base contract shared by all placed objects. Flags choose which World collision lists contain it.
# These objects are not Nodes: World must call update(), touch() and draw() itself.
class Ent extends RefCounted:
	var w
	var d: Dictionary
	var rect: Rect2i
	var solid := false
	var fixed := false  # a solid whose rect never changes after setup: World files it by column for fast collision
	var jumpthru := false
	var dream := false
	var collidable := true
	var safe := true
	var lift := Vector2.ZERO
	var rem := Vector2.ZERO
	var shake := Vector2.ZERO
	var respawn := 0.0

	# Attach the owner/data and initial pixel rectangle, then call the subclass setup hook.
	func _init(world, data: Dictionary) -> void:
		w = world
		d = data
		rect = Rect2i(int(data.x), int(data.y), int(data.get("w", T)), int(data.get("h", T)))
		setup()

	# Optional construction hook; subclasses set dimensions, flags and their own starting state here.
	func setup() -> void: pass
	# The editor's preview objects (it has no World), so drawing can see neighbours there too.
	static var editor_ents: Array = []
	static var draw_peers = null  # set while drawing a group that isn't w.ents (the room being left)
	# The objects this one draws among: its room's, or the group being drawn, or the editor's.
	func peers() -> Array:
		if draw_peers != null:
			return draw_peers
		return w.ents if w != null else editor_ents
	# Sides (BlockArt.JOIN_* bits) where another collidable object of the same type touches this one along an edge:
	# touching blocks draw as one. sides limits which sides are looked at.
	func joins(sides := 15) -> int:
		var out := 0
		var me := Rect2(rect)
		for e in peers():
			if e == self or e == null or e.d.t != d.t or not e.collidable:
				continue
			var o := Rect2(e.rect)
			var vert := me.position.y < o.end.y and o.position.y < me.end.y
			var horiz := me.position.x < o.end.x and o.position.x < me.end.x
			if vert and o.end.x == me.position.x: out |= BlockArt.JOIN_LEFT
			if vert and o.position.x == me.end.x: out |= BlockArt.JOIN_RIGHT
			if horiz and o.end.y == me.position.y: out |= BlockArt.JOIN_TOP
			if horiz and o.position.y == me.end.y: out |= BlockArt.JOIN_BOTTOM
		return out & sides
	# What it is and what it is doing, for the F2 overlay's mouse-over (subclasses add their state).
	func describe() -> String:
		return str(TYPES[d.t][0]) if TYPES.has(d.t) else str(d.t)
	# Report whether Ent currently participates in lethal contact checks.
	func hurts() -> bool: return false  # true: touching it is damage, checked against the player's smaller damage_rect()
	# Expose active circular hazards; an empty list means no circular damage is active.
	func damage_circles() -> Array: return []  # [centre, radius] for exact round hazards
	# Expose active rectangular damage regions to the hitbox overlay and shared inspection tools.
	func damage_boxes() -> Array: return []  # extra boxes that hurt (projectiles, waves), for the hitbox overlay
	# Optional per-physics-step hook. The base object has no timed behavior.
	func update(_dt: float) -> void: pass
	# Optional drawing hook. The base object has no artwork of its own.
	func draw(_ci: CanvasItem) -> void: pass
	# Optional contact hook. The base object does nothing; interactive subclasses override it.
	func touch(_p) -> void: pass  # player hurtbox overlaps touch_rect()
	# Return the pixel rectangle that activates Ent contact, separate from artwork bounds.
	func touch_rect() -> Rect2i: return rect
	# Conservative draw bounds, used only to skip offscreen drawing (sprites overhang
	# rect by up to 8px: jump-through rails, spring pads, shake, bobbing).
	# Return conservative visible bounds including Ent effects so camera culling does not hide them.
	func vis_rect() -> Rect2i: return rect.grow(8)

	# Return this object rectangle centre in room-local pixels.
	func center() -> Vector2:
		return Vector2(rect.position) + Vector2(rect.size) / 2.0

	# Ask Player whether it is supported by or clinging to this solid before the solid moves.
	func player_riding() -> bool:
		# cheap reject first: riding means touching within a pixel
		return w != null and w.player != null and not w.player.dead and rect.grow(2).intersects(w.player.hitbox()) and w.player.is_riding(self)

	# Monocle Solid.Move: push or carry the player
	# Move a solid while carrying riders and pushing the player clear of its path.
	func move_by(amount: Vector2, dt: float) -> void:
		rem += amount
		var mx := roundi(rem.x)
		var my := roundi(rem.y)
		rem -= Vector2(mx, my)
		lift = amount / dt if dt > 0 else Vector2.ZERO
		var p = w.player if w != null else null
		var riding: bool = p != null and not p.dead and p.is_riding(self)
		if mx != 0:
			_move_axis(true, mx, p, riding)
		if my != 0:
			_move_axis(false, my, p, riding)

	# Resolve one axis of a moving solid in whole pixels so pushing and squashing stay deterministic.
	func _move_axis(h: bool, m: int, p, riding: bool) -> void:
		if h:
			rect.position.x += m
		else:
			rect.position.y += m
		if p == null or p.dead or not collidable:
			return
		collidable = false
		var pr: Rect2i = p.hitbox()
		if rect.intersects(pr) and p.state != p.ST_DREAM_DASH:
			p.set_lift_speed(lift)
			if h:
				p.move_h_exact(rect.end.x - pr.position.x if m > 0 else rect.position.x - pr.end.x, 2)
			else:
				p.move_v_exact(rect.end.y - pr.position.y if m > 0 else rect.position.y - pr.end.y, 2)
		elif riding:
			p.set_lift_speed(lift)
			if h:
				p.move_h_exact(m)
			else:
				p.move_v_exact(m)
		collidable = true

	# Advance the visual shaking offset while active, otherwise restore its resting offset.
	func shaken(dt: float, active: bool) -> void:
		shake = Vector2(randi_range(-1, 1), randi_range(-1, 1)) if active and dt > 0 else Vector2.ZERO


# Editor marker for the player feet position; World extracts it instead of spawning a gameplay object.
class SpawnMarker extends Ent:
	# Initialize SpawnMarker dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		collidable = false
	# Draw SpawnMarker at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if w == null:  # editor only
			ci.draw_rect(Rect2(rect.position.x, rect.position.y - 3, 8, 11), Color(1, 1, 1, 0.6), false, 1.0)
			ci.draw_rect(Rect2(rect.position.x + 2, rect.position.y - 1, 4, 3), Color("ac3232"))


# Directional lethal surface. The contact rules consider approach direction instead of killing through its back.
class Spikes extends Ent:
	func describe() -> String:
		return "Spikes: deadly when you move into the points (touch box 7 px along the tile)"
	var dir := "up"
	# Report whether Spikes currently participates in lethal contact checks.
	func hurts() -> bool: return true
	# Initialize Spikes dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		dir = (d.t as String).substr(7)
		var p := rect.position
		match dir:  # 7 px along the tile: 10% less than the full 8 (whole pixels; the art stays 8 wide)
			"up": rect = Rect2i(p.x, p.y + 5, 7, 3)
			"down": rect = Rect2i(p.x, p.y, 7, 3)
			"left": rect = Rect2i(p.x + 5, p.y, 3, 7)
			"right": rect = Rect2i(p.x, p.y, 3, 7)
	# Apply Spikes interaction when World reports an overlapping player.
	func touch(p) -> void:
		match dir:
			"up":
				if p.speed.y >= 0 and p.bottom() <= rect.end.y:
					p.die(Vector2.UP)
			"down":
				if p.speed.y <= 0:
					p.die(Vector2.DOWN)
			"left":
				if p.speed.x >= 0:
					p.die(Vector2.LEFT)
			"right":
				if p.speed.x <= 0:
					p.die(Vector2.RIGHT)
	# Draw Spikes at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := Color("e8e8f0")
		var r := Rect2(rect)
		var pts: PackedVector2Array
		match dir:
			"up":
				for i in 2:
					var x := r.position.x + i * 4
					pts = [Vector2(x, r.end.y), Vector2(x + 2, r.position.y - 1), Vector2(x + 4, r.end.y)]
					ci.draw_colored_polygon(pts, c)
			"down":
				for i in 2:
					var x := r.position.x + i * 4
					pts = [Vector2(x, r.position.y), Vector2(x + 2, r.end.y + 1), Vector2(x + 4, r.position.y)]
					ci.draw_colored_polygon(pts, c)
			"left":
				for i in 2:
					var y := r.position.y + i * 4
					pts = [Vector2(r.end.x, y), Vector2(r.position.x - 1, y + 2), Vector2(r.end.x, y + 4)]
					ci.draw_colored_polygon(pts, c)
			"right":
				for i in 2:
					var y := r.position.y + i * 4
					pts = [Vector2(r.position.x, y), Vector2(r.end.x + 1, y + 2), Vector2(r.position.x, y + 4)]
					ci.draw_colored_polygon(pts, c)


# Reusable launcher. Its orientation chooses an upward or sideways bounce and a short pressed animation.
class Spring extends Ent:
	var dir := "up"
	var anim := 0.0
	# Initialize Spring dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		dir = (d.t as String).substr(7)
		var p := rect.position
		match dir:
			"up": rect = Rect2i(p.x, p.y + 4, 8, 4)
			"left": rect = Rect2i(p.x + 4, p.y, 4, 8)
			"right": rect = Rect2i(p.x, p.y, 4, 8)
	# Advance Spring timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		anim = maxf(0, anim - dt)
	# Apply Spring interaction when World reports an overlapping player.
	func touch(p) -> void:
		if p.state == p.ST_DREAM_DASH:
			return
		match dir:
			"up":
				if p.speed.y >= 0:
					p.super_bounce(rect.position.y)
					anim = 0.2
			"left":
				if p.side_bounce(-1, rect.position.x, center().y):
					anim = 0.2
			"right":
				if p.side_bounce(1, rect.end.x, center().y):
					anim = 0.2
	# Draw Spring at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		var ext := 3.0 if anim > 0 else 0.0
		var base := Color("6a6a7a")
		var pad := Color("e0a030")
		match dir:
			"up":
				ci.draw_rect(Rect2(r.position.x + 1, r.end.y - 2, 6, 2), base)
				ci.draw_rect(Rect2(r.position.x, r.position.y - ext, 8, 2), pad)
			"left":
				ci.draw_rect(Rect2(r.end.x - 2, r.position.y + 1, 2, 6), base)
				ci.draw_rect(Rect2(r.position.x - ext, r.position.y, 2, 8), pad)
			"right":
				ci.draw_rect(Rect2(r.position.x, r.position.y + 1, 2, 6), base)
				ci.draw_rect(Rect2(r.end.x - 2 + ext, r.position.y, 2, 8), pad)


# Dash/stamina crystal. It disappears temporarily only when the player actually benefits from using it.
class Refill extends Ent:
	var two := false
	var t := 0.0
	# Initialize Refill dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		two = d.t == "refill_two"
		rect = Rect2i(rect.position.x, rect.position.y, 8, 8)  # exactly the sprite
	# Advance Refill timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	# Apply Refill interaction when World reports an overlapping player.
	func touch(p) -> void:
		if respawn <= 0 and p.use_refill(two):
			w.freeze_for(0.05)
			w.burst(center(), Color("ff6def") if two else Color("4ee05a"), 8)
			respawn = 2.5
	# Draw Refill at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 3) * 1.0))
		if respawn > 0:
			ci.draw_arc(c, 2, 0, TAU, 8, Color(1, 1, 1, 0.3), 1.0)
			return
		var col := Color("ff6def") if two else Color("4ee05a")
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0)]), col)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(1.5, 0), c + Vector2(0, 1), c + Vector2(-1.5, 0)]), col.lightened(0.6))


# Adventure pickup that unlocks one movement ability for the rest of the run.
class AbilityOrb extends Ent:  # adventure pickup that unlocks a move for the rest of the run
	var ability := ""
	var t := 0.0
	# Initialize AbilityOrb dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		ability = d.t.trim_prefix("ability_")
		rect = Rect2i(rect.position.x - 3, rect.position.y - 3, 14, 14)  # exactly the sprite
		collidable = w == null or not Game.has_ability(ability)  # already owned (or not in the adventure): gone
	# Advance AbilityOrb timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
	# Apply AbilityOrb interaction when World reports an overlapping player.
	func touch(_p) -> void:
		collidable = false
		w.grant_ability(ability)
		w.freeze_for(0.1)
		w.burst(center(), TYPES[d.t][2], 14)
	# Draw AbilityOrb at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := center() + Vector2(0, round(sin(t * 2.5) * 1.5))
		var col: Color = TYPES[d.t][2]
		ci.draw_circle(c, 5, col.darkened(0.4))
		ci.draw_circle(c, 4, col)
		ci.draw_arc(c, 6.5 + sin(t * 4), 0, TAU, 16, Color(col, 0.5), 1.0)
		ci.draw_rect(Rect2(c + Vector2(-1, -2), Vector2(2, 2)), Color.WHITE)


# One-time adventure upgrade that increases stamina capacity and records its room-specific pickup ID.
class StaminaBlock extends Ent:  # adventure: +1 stamina block, once per run
	var key := ""
	var t := 0.0
	# Initialize StaminaBlock dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect = Rect2i(rect.position.x - 3, rect.position.y - 3, 14, 14)  # exactly the sprite
		if w != null:
			key = str(d.get("pickup_key", "%s:%d:%d" % [w.room, int(d.x), int(d.y)]))
		collidable = w == null or (w.adventure() and not w.stamina_block_taken(key))
	# Advance StaminaBlock timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
	# Apply StaminaBlock interaction when World reports an overlapping player.
	func touch(_p) -> void:
		collidable = false
		w.add_stamina_block(key)
		w.freeze_for(0.1)
		w.burst(center(), TYPES[d.t][2], 14)
	# Draw StaminaBlock at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := center() + Vector2(0, round(sin(t * 2.5) * 1.5))
		var col: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), col.darkened(0.4))
		ci.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), col)
		ci.draw_rect(Rect2(c - Vector2(6.5, 6.5), Vector2(13, 13)).grow(sin(t * 4)), Color(col, 0.5), false, 1.0)


# ponytail: refills all stamina; collectibles that restore part of it come with the stamina design
# Reusable adventure stamina refill with a delay before it becomes available again.
class StaminaOrb extends Ent:  # adventure: refills stamina, back after 2.5 s
	var t := 0.0
	# Initialize StaminaOrb dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect = Rect2i(rect.position.x - 1, rect.position.y - 1, 10, 10)  # exactly the sprite
	# Advance StaminaOrb timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	# Apply StaminaOrb interaction when World reports an overlapping player.
	func touch(_p) -> void:
		if respawn <= 0 and w.adventure() and Game.adv.stamina < Game.Adventure.stamina_max(Game.adv):
			w.refill_stamina()
			respawn = 2.5
			w.burst(center(), TYPES[d.t][2], 8)
	# Draw StaminaOrb at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var col: Color = TYPES[d.t][2] if respawn <= 0 else Color(0.3, 0.3, 0.4)
		var c := center() + Vector2(0, round(sin(t * 3)))
		ci.draw_circle(c, 3, col)
		ci.draw_arc(c, 5, 0, TAU, 12, Color(col, 0.6), 1.0)


# Automatic linked doorway. It queues travel for World to resolve after contact iteration.
class Door extends Ent:  # touching it moves the player to the linked door (World.door_hit)
	# Queue doorway travel for after the current player-contact loop.
	func touch(_p) -> void:
		w.door_hit(self)
	# Return conservative visible bounds including Door effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return rect.grow(8) if w != null else Rect2i(rect.position - Vector2i(160, 24), rect.size + Vector2i(320, 32))
	# Draw Door at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c := Color("40e0ff")
		ci.draw_rect(Rect2(rect), Color(c, 0.12 if w != null else 0.25))
		ci.draw_rect(Rect2(rect), Color(c, 0.6), false, 1.0)
		if w == null:  # editor: "id -> target"
			var t := "%s -> %s" % [d.get("id", "?"), d.get("to", "?")]
			var f := ThemeDB.fallback_font
			ci.draw_string(f, Vector2(rect.position) + Vector2(0, -2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, c)


# A visible wooden door. Standing at it shows a prompt; pressing interact takes the player through
# (World.after_player_move), to the door its "to" names, like the Door object.
# Visible building entrance. Nearby contact shows a prompt; World requires the Interact action to travel.
class HouseDoor extends Door:
	var near := 0.0  # > 0 while the player stands at it (drawn prompt)
	# Mark this entrance as nearby; World waits for grounded Interact input before using it.
	func touch(_p) -> void:
		w.door_near = self
		near = 0.1
	# Advance HouseDoor timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		near = maxf(0.0, near - dt)
	# Return conservative visible bounds including HouseDoor effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return rect.grow(48 if d.get("skin", "") == "signpost" else 12) if w != null else super.vis_rect()
	# Draw HouseDoor at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		if d.get("skin", "") == "signpost":
			_draw_signpost(ci, r)
		else:
			var frame := Color("4e3422")
			ci.draw_rect(r, frame)  # exactly its hitbox: frame, planks inside, a knob
			var inner := r.grow(-1)
			ci.draw_rect(inner, Color("8a5a34"))
			for x in range(int(inner.position.x) + 4, int(inner.end.x), 4):
				ci.draw_rect(Rect2(x, inner.position.y, 1, inner.size.y), Color("6e4628"))
			ci.draw_rect(Rect2(inner.position.x, inner.position.y + 2, inner.size.x, 1), Color("6e4628"))
			ci.draw_rect(Rect2(inner.end.x - 3, inner.position.y + inner.size.y / 2.0, 2, 2), Color("e0c060"))
		if near > 0:  # prompt: the interact button (key or pad, whichever was used last), bobbing above the door
			var tex: Texture2D = ButtonArt.prompt("interact")
			ci.draw_texture(tex, Vector2(roundf(r.position.x + (r.size.x - tex.get_width()) / 2.0), r.position.y - tex.get_height() - 2 + roundf(sin(Time.get_ticks_msec() / 150.0))))
		if w == null and d.has("to"):
			super.draw(ci)  # editor: the link label
	# A signed path uses the existing deliberate travel input, with a visible destination.
	func _draw_signpost(ci: CanvasItem, r: Rect2) -> void:
		var at := r.position
		ci.draw_rect(Rect2(at + Vector2(7, 7), Vector2(3, r.size.y - 7)), Color("6e4628"))
		ci.draw_rect(Rect2(at + Vector2(7, 8), Vector2(1, r.size.y - 8)), Color("b58d6b"))
		ci.draw_rect(Rect2(at + Vector2(0, 3), Vector2(16, 9)), Color("4e3422"))
		ci.draw_rect(Rect2(at + Vector2(1, 4), Vector2(14, 6)), Color("c8a875"))
		var north: bool = d.get("direction", "north") == "north"
		var tip := at + Vector2(8, 5 if north else 9)
		var dy := 1 if north else -1
		ci.draw_rect(Rect2(tip, Vector2(1, 1)), Color("4e3422"))
		ci.draw_rect(Rect2(tip + Vector2(-1, dy), Vector2(3, 1)), Color("4e3422"))
		ci.draw_rect(Rect2(tip + Vector2(-2, 2 * dy), Vector2(5, 1)), Color("4e3422"))
		ci.draw_rect(Rect2(at + Vector2(8, 6), Vector2(1, 3)), Color("4e3422"))
		if near > 0:
			var label := "Follow path: " + str(d.get("label", "Coast"))
			var font := ThemeDB.fallback_font
			var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
			var origin := Vector2(roundf(r.get_center().x - size.x / 2), r.position.y - 16)
			ci.draw_rect(Rect2(origin - Vector2(2, 7), Vector2(size.x + 4, 10)), Color(0.08, 0.08, 0.12, 0.95))
			ci.draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("f0dfb1"))


# Non-solid backdrop scenery; it is drawn behind the separately placed doorway.
class Building extends Ent:  # backdrop only: never collides; put it before its door so the door draws on top
	# Initialize Building dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		collidable = false
	# Draw Building at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		if d.get("style", "house") == "tower":
			ci.draw_rect(r, Color("8f8a80"))
			for y in range(int(r.position.y) + 4, int(r.end.y), 4):  # stone courses, joints staggered
				ci.draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color("6f6a62"))
				for x in range(int(r.position.x) + (4 if y % 8 == 0 else 0), int(r.end.x), 8):
					ci.draw_rect(Rect2(x, y - 3, 1, 3), Color("6f6a62"))
			ci.draw_rect(r, Color("4f4a44"), false, 1.0)
			return
		var roof := minf(16.0, r.size.y / 2.0)
		var wall := Rect2(r.position.x, r.position.y + roof, r.size.x, r.size.y - roof)
		ci.draw_rect(wall, Color("c8a878"))
		ci.draw_rect(wall, Color("6e4628"), false, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([  # roof overhanging the walls by 2 px
			Vector2(r.position.x - 2, wall.position.y), Vector2(r.position.x + 4, r.position.y),
			Vector2(r.end.x - 4, r.position.y), Vector2(r.end.x + 2, wall.position.y)]), Color("9a3a2a"))
		for y in range(int(r.position.y) + 4, int(wall.position.y), 4):  # tile rows
			ci.draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color("7a2a1e"))


# Harmless labelled stand-in used to plan objects that do not yet have a full implementation.
class Placeholder extends Ent:  # enemy / breakable stand-in: a labelled box, harmless
	# Initialize Placeholder dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		collidable = false
	# Return conservative visible bounds including Placeholder effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return rect.grow(2) if w != null else Rect2i(rect.position - Vector2i(80, 12), rect.size + Vector2i(160, 14))
	# Draw Placeholder at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(rect), Color(c, 0.3))
		ci.draw_rect(Rect2(rect), c, false, 1.0)
		if w == null and str(d.get("text", "")) != "":
			ci.draw_string(ThemeDB.fallback_font, Vector2(rect.position) + Vector2(0, -2), str(d.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, c)


# Small, deterministic enemies: hit() integrates with the existing melee sector.
# A type id is "enemy_<family>" or "enemy_<family>_<variant>"; each family registers only the variants that suit it.
# Common enemy health, variants, safe movement, detection, contact damage and projectile handling.
# Variants adjust this shared behavior so each family does not reimplement shields, venom and health.
class CombatEnemy extends Ent:
	const PHASE_HELP := {"idle": "patrolling or waiting", "windup": "winding up an attack: get clear", "dive": "diving at you",
		"swoop": "swooping at you", "charge": "charging along the ground", "leap": "leaping at you", "rest": "recovering: safe to hit",
		"return": "going back to its spot"}
	func describe() -> String:
		if not collidable:
			return "%s: defeated" % TYPES[d.t][0]
		return "%s (HP %d) - %s: %s" % [TYPES[d.t][0], hp, phase, PHASE_HELP.get(phase, phase)]
	# Report whether CombatEnemy currently participates in lethal contact checks.
	func hurts() -> bool: return true
	# variant -> [speed, warning, recovery multipliers, body scale]
	const VARIANTS := {
		"": [1.0, 1.0, 1.0, 1.0],
		"swift": [1.35, 0.75, 0.7, 1.0],  # faster, one hit point less
		"armored": [0.75, 1.25, 1.25, 1.0],  # slower, two hit points more
		"giant": [0.7, 1.2, 1.2, 2.0],  # twice the size, double hit points
		"shielded": [0.9, 1.0, 1.0, 1.0],  # blocks hits from the front
		"brood": [1.0, 1.0, 1.0, 1.0],  # splits into two small, fast copies when killed
		"venom": [1.0, 1.0, 1.0, 1.0],  # leaves short-lived poison puddles
	}
	var variant := ""
	var speed_multiplier := 1.0
	var warning_multiplier := 1.0
	var recovery_multiplier := 1.0
	var scale := 1.0  # body and sprite size (giant 2, brood children 0.5)
	var hp := 1
	var facing := -1
	var clock := 0.0
	var flash := 0.0
	var seen := false  # reported to the Monsters tab once on screen
	var home := Vector2.ZERO
	var phase := "idle"
	var timer := 0.0
	var puddles: Array = []  # venom: [Rect2i, seconds left]
	var drip := 0.5

	# Extract the known variant suffix from an enemy type ID, or return empty for the base family.

	static func variant_of(t: String) -> String:
		var v := t.get_slice("_", t.get_slice_count("_") - 1)
		return v if v != "" and VARIANTS.has(v) and t.count("_") >= 2 else ""

	# Read variant modifiers before setup so subclass health/speed calculations use the selected variant.
	func _init(world, data: Dictionary) -> void:
		super(world, data)
		if d.get("brood_child", false):
			scale = 0.5
			speed_multiplier = 1.35
			hp = 1
		if scale != 1.0:  # grow or shrink from the top-left the level placed it at
			rect.size = Vector2i((Vector2(rect.size) * scale).round()).max(Vector2i(4, 4))
			home = Vector2(rect.position)

	# Initialize CombatEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect.size = Vector2i(8, 12)
		variant = variant_of(d.t)
		var m: Array = VARIANTS[variant]
		speed_multiplier = m[0]
		warning_multiplier = m[1]
		recovery_multiplier = m[2]
		scale = m[3]
		hp = variant_hp(1)
		facing = -1 if int(d.get("facing", -1)) < 0 else 1
		home = Vector2(rect.position)

	# Adjust a family baseline health value using the selected enemy variant.
	func variant_hp(base: int) -> int:
		match variant:
			"swift": return maxi(1, base - 1)
			"armored": return base + 2
			"giant": return base * 2
			"shielded": return base + 1
		return base

	# Variants are traits; an ActionMonster can have several.
	func has_trait(t: String) -> bool:
		return variant == t

	# Return the base family ID so variants can share art and common metadata.
	func family() -> String:
		return d.t.trim_suffix("_" + variant) if variant != "" else d.t

	# Advance shared enemy timing and determine whether this living enemy should run its behavior.
	func active(dt: float) -> bool:
		clock += dt
		flash = maxf(0, flash - dt)
		var on: bool = collidable and w != null and w.player != null and not w.player.dead and center().distance_to(w.player.center()) < 320
		if on and not seen and w.view_rect().intersects(Rect2(rect)):
			seen = true
			w.saw_enemy(d.t)
		if on and has_trait("venom"):
			update_venom(dt)
		return on

	# Check whether a proposed enemy rectangle overlaps terrain or a solid object.
	func blocked(at: Rect2i) -> bool:
		return w != null and (not w.bounds.encloses(at) or w.collide_solid(at) != null)

	# Accumulate fractional motion and move whole pixels, checking obstructions and player contact along the way.
	func move_enemy(delta: Vector2) -> bool:
		rem += delta
		var amount := Vector2i(roundi(rem.x), roundi(rem.y))
		rem -= Vector2(amount)
		var hit := false
		for axis in 2:
			var count: int = amount.x if axis == 0 else amount.y
			var step := Vector2i(signi(count), 0) if axis == 0 else Vector2i(0, signi(count))
			for i in absi(count):
				var next := Rect2i(rect.position + step, rect.size)
				if blocked(next):
					hit = true
					if axis == 0: rem.x = 0
					else: rem.y = 0
					break
				rect = next
				contact()
		return hit

	# Floor walkers: the next pixel ahead has floor under it and no acid or spikes, so a walker stops with
	# its box's leading edge exactly over the edge of the ground.
	# Check that the leading foot has support and will not step into nearby spikes or acid.
	func safe_step() -> bool:
		var foot := Rect2i(rect.end.x if facing > 0 else rect.position.x - 1, rect.end.y, 1, 2)
		if w.collide_solid(foot) == null:
			return false
		for entity in w.touchables:
			if entity.collidable and (entity.d.t == "acid" or entity.d.t.begins_with("spikes_")) and entity.rect.intersects(Rect2i(rect.position + Vector2i(facing * 2, 0), rect.size).grow(2)):
				return false
		return true

	# Walks px forward one pixel at a time; true when a wall or the edge of the floor stops it.
	var walk_rem := 0.0
	# Advance the floor patrol one pixel at a time, stopping before a wall or unsafe ledge.
	func walk(px: float) -> bool:
		walk_rem += px
		var n := int(walk_rem)
		walk_rem -= n
		for i in n:
			var next := Rect2i(rect.position + Vector2i(facing, 0), rect.size)
			if not safe_step() or blocked(next):
				walk_rem = 0.0
				return true
			rect = next
			contact()
		return false

	# Test player contact immediately after enemy movement so a fast step cannot skip the damage check.
	func contact() -> void:
		if w != null and w.player != null and not w.player.dead and rect.intersects(w.player.damage_rect()):
			touch(w.player)

	# Check player distance and probe the line of sight for intervening solid terrain.
	func sees_player(distance: float) -> bool:
		if w == null or w.player == null or w.player.dead:
			return false
		var target: Vector2 = w.player.center()
		var start := center()
		if start.distance_to(target) > distance:
			return false
		var steps := maxi(1, ceili(start.distance_to(target) / 4))
		for i in range(1, steps):
			var spot := start.lerp(target, float(i) / steps)
			if w.collide_solid(Rect2i(Vector2i(spot), Vector2i.ONE)) != null:
				return false
		return true

	# Shielded: the side it faces. A hit from there (and not from above) is blocked.
	# Return the facing direction used to distinguish the shielded front from an exposed rear.
	func front() -> Vector2:
		return Vector2(facing, 0)

	# Check whether the incoming attack reaches the protected shield side rather than an exposed angle.
	func blocks(p) -> bool:
		var to: Vector2 = p.center() - center()
		return has_trait("shielded") and to.dot(front()) > 0 and to.y > -rect.size.y * 0.5

	# Apply one sword hit, respecting shield/flash protection and triggering death or variant reactions.
	func hit(p) -> void:
		if not collidable or flash > 0:
			return
		if blocks(p):
			Game.play_sfx("shield")
			flash = 0.12
			if w != null:
				w.burst(center() + front() * rect.size.x * 0.5, Color("f8d89b"), 3)
			return
		Game.play_sfx("enemy_die" if hp <= 1 else "enemy_hit")
		hp -= 1
		flash = 0.12
		if hp <= 0:
			collidable = false
			puddles.clear()
			if w != null:
				w.killed_enemy(d.t)
				w.burst(center(), EnemyArt.COLORS["y"], 6)
				if has_trait("brood"):
					brood()

	# Queue smaller child enemies after a brood-variant parent is defeated.
	func brood() -> void:
		var kid_t: String = family() + "_swift" if TYPES.has(family() + "_swift") else family()
		for side in [-1, 1]:
			var kid := Rect2i(Vector2i(center()) + Vector2i(side * 4 - 2, -2), Vector2i(4, 4))
			var at: Vector2i = kid.position if not blocked(kid.grow(2)) else Vector2i(center()) - Vector2i(2, 2)
			w.spawn_entity({"t": kid_t, "x": at.x, "y": at.y, "facing": side, "brood_child": true})

	# Venom: every so often a puddle on the surface below; the player dies on touching one.
	# Compute the small surface region where this venom variant leaves a harmful trail.
	func venom_spot() -> Rect2i:
		var below := Rect2i(rect.position.x, rect.end.y, rect.size.x, 1)
		for i in 96:
			if blocked(below):
				return Rect2i(int(center().x) - 5, below.position.y - 4, 10, 4)  # tall enough to reach a standing player's hurtbox
			below.position.y += 1
		return Rect2i()

	# Update venom puddle lifetime/spawning and check their damage contacts.
	func update_venom(dt: float) -> void:
		drip -= dt
		if drip <= 0:
			drip = 0.8
			var spot := venom_spot()
			if spot.has_area():
				puddles.append([spot, 3.0])
		for i in range(puddles.size() - 1, -1, -1):
			puddles[i][1] -= dt
			if puddles[i][1] <= 0:
				puddles.remove_at(i)
			elif puddles[i][0].intersects(w.player.damage_rect()):
				w.player.die(Vector2.UP)

	# Apply CombatEnemy interaction when World reports an overlapping player.
	func touch(p) -> void:
		if collidable:
			p.die((p.center() - center()).normalized())

	# Return conservative visible bounds including CombatEnemy effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return body_rect()

	# Return the drawn body bounds separately from surrounding venom or projectile effects.
	func body_rect() -> Rect2i:  # the sprite overhangs the body; venom puddles lie around it
		var area := rect.grow(8 + int(rect.size.x * 0.5))
		for pd in puddles:
			area = area.merge(pd[0])
		return area

	# Draw CombatEnemy at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		for pd in puddles:
			ci.draw_rect(Rect2(pd[0]), Color(0.55, 0.85, 0.3, minf(1.0, pd[1]) * 0.45))  # fades as it dries
		if not collidable:
			return
		EnemyArt.draw(ci, d.t, center(), facing, clock, flash > 0, scale)
		if has_trait("shielded"):  # bright edge on the guarded side
			var f := front()
			var edge := center() + f * (rect.size.x * 0.5 + 1)
			ci.draw_rect(Rect2(edge - Vector2(1, rect.size.y * 0.4), Vector2(2, rect.size.y * 0.8)) if f.x != 0 else Rect2(edge - Vector2(rect.size.x * 0.4, 1), Vector2(rect.size.x * 0.8, 2)), Color("f8d89b"))
		if phase == "windup" and int(clock * 12) % 2 == 0:
			ci.draw_rect(Rect2(center().x - 1, rect.position.y - 4, 2, 2), Color("f8d89b"))

	# Projectiles owned by an enemy: [position, velocity, seconds left]. They stop at rock, can be swatted by the attack.
	# Advance owned projectiles with gravity/lifetime limits and resolve wall/player impacts.
	func update_shots(shots: Array, dt: float, gravity: float) -> void:
		for i in range(shots.size() - 1, -1, -1):
			var shot: Array = shots[i]
			shot[2] -= dt
			shot[1].y += gravity * dt
			var delta: Vector2 = shot[1] * dt
			var count := maxi(1, ceili(delta.length()))
			var remove: bool = shot[2] <= 0
			for j in count:
				shot[0] += delta / count
				var box := Rect2i(Vector2i(shot[0]) - Vector2i.ONE, Vector2i(3, 3))
				if blocked(box):
					remove = true
					break
				var p = w.player
				var to_shot: Vector2 = shot[0] - p.center()
				if p.attacking() and to_shot.length() <= p.ATTACK_RANGE and absf(p.attack_dir.angle_to(to_shot)) <= deg_to_rad(p.ATTACK_ARC) / 2:
					remove = true
					break
				if box.intersects(p.damage_rect()):
					p.die(shot[1].normalized())
					remove = true
					break
			if remove: shots.remove_at(i)

	# Expose active rectangular damage regions to the hitbox overlay and shared inspection tools.
	func damage_boxes() -> Array:  # projectiles (as update_shots tests them) and venom puddles
		var out := []
		for shots in [get("bones"), get("orbs")]:
			if shots is Array:
				for shot in shots:
					out.append(Rect2i(Vector2i(shot[0]) - Vector2i.ONE, Vector2i(3, 3)))
		for pd in puddles:
			out.append(pd[0])
		return out

	# Combine projectile bounds with the body so off-screen culling does not hide visible shots.
	func shots_rect(shots: Array) -> Rect2i:
		var area := body_rect()
		for shot in shots:
			area = area.merge(Rect2i(Vector2i(shot[0]) - Vector2i(3, 3), Vector2i(6, 6)))
		return area


# Ceiling ambusher: warn, dive, rest on impact and return toward its starting height.
class SkreeEnemy extends CombatEnemy:
	var vertical_speed := 0.0
	# Advance SkreeEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		match phase:
			"idle":
				var offset: Vector2 = w.player.center() - center()
				if offset.y > 6 and absf(offset.x) < 28 and sees_player(112):
					Game.play_sfx("enemy_alert")
					phase = "windup"
					timer = 0.35 * warning_multiplier
			"windup":
				timer -= dt
				if timer <= 0:
					Game.play_sfx("enemy_attack")
					phase = "dive"
					vertical_speed = 50
			"dive":
				vertical_speed = minf(180 * speed_multiplier, vertical_speed + 360 * speed_multiplier * dt)
				if move_enemy(Vector2(0, vertical_speed * dt)):
					phase = "rest"
					timer = 0.8 * recovery_multiplier
			"rest":
				timer -= dt
				if timer <= 0: phase = "return"
			"return":
				if rect.position.y <= home.y:
					rect.position.y = int(home.y)
					rem.y = 0
					phase = "idle"
				elif move_enemy(Vector2(0, -36 * speed_multiplier * dt)):
					phase = "idle"  # something solid above: wait here instead of pushing forever


# Flying ambusher: aim one swoop toward the detected player, then fly back to its perch.
class BatEnemy extends CombatEnemy:
	var velocity := Vector2.ZERO
	# Initialize BatEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(10, 8)
	# Advance BatEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		if phase == "idle":
			if sees_player(96):
				Game.play_sfx("enemy_alert")
				phase = "windup"
				timer = 0.4 * warning_multiplier
		elif phase == "windup":
			timer -= dt
			if timer <= 0:
				velocity = (w.player.center() - center()).normalized() * 65 * speed_multiplier
				Game.play_sfx("enemy_attack")
				phase = "swoop"
				timer = 0.9 * recovery_multiplier
		elif phase == "swoop":
			facing = -1 if velocity.x < 0 else 1
			timer -= dt
			if move_enemy(velocity * dt) or timer <= 0:
				phase = "return"
		elif phase == "return":
			var delta := home - Vector2(rect.position)
			if delta.length() < 2:
				phase = "idle"
			elif move_enemy(delta.normalized() * 30 * speed_multiplier * dt):
				# A blocked direct return perches at the new location instead of phasing through rock.
				home = Vector2(rect.position)
				phase = "idle"


# Ground patrol that warns and throws bone projectiles toward a visible player.
class SkeletonEnemy extends CombatEnemy:
	var gravity_speed := 0.0
	var bones: Array = []  # owned projectiles (see update_shots)
	# Initialize SkeletonEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		hp = variant_hp(3)
		timer = 1.0 * recovery_multiplier
	# Advance SkeletonEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		update_bones(dt)
		gravity_speed = minf(140, gravity_speed + 400 * dt)
		if move_enemy(Vector2(0, gravity_speed * dt)): gravity_speed = 0
		var offset: Vector2 = w.player.center() - center()
		if phase == "windup":
			timer -= dt
			if timer <= 0:
				var volley := 2 if variant == "armored" else 1
				for arc in mini(volley, 3 - bones.size()):
					Game.play_sfx("projectile")
					bones.append([center() + Vector2(facing * 5, -2), Vector2(facing * 60 * speed_multiplier, -65 - arc * 25), 2.0])
				phase = "idle"
				timer = 1.7 * recovery_multiplier
			return
		timer -= dt
		if absf(offset.y) < 40 * scale and sees_player(104 * scale):
			facing = -1 if offset.x < 0 else 1
			if timer <= 0 and bones.size() < 3:
				Game.play_sfx("enemy_alert")
				phase = "windup"
				timer = 0.45 * warning_multiplier
			return
		var reach := clampf(float(d.get("patrol", 40)), 8, 96)
		if not safe_step() or (absf(rect.position.x - home.x) >= reach and signf(rect.position.x - home.x) == facing):
			facing *= -1
		elif walk(14 * speed_multiplier * dt):
			facing *= -1
	# Apply one sword hit, respecting shield/flash protection and triggering death or variant reactions.
	func hit(p) -> void:
		super.hit(p)
		if not collidable: bones.clear()
	# Advance the skeleton bone projectiles through the common projectile update helper.
	func update_bones(dt: float) -> void:
		update_shots(bones, dt, 150)
	# Return conservative visible bounds including SkeletonEnemy effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return shots_rect(bones)
	# Draw SkeletonEnemy at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		super.draw(ci)
		for bone in bones:
			var at: Vector2 = bone[0].round()
			ci.draw_rect(Rect2(at - Vector2(2, 0), Vector2(4, 1)), Color("d8d8bd"))
			ci.draw_rect(Rect2(at - Vector2(2, 1), Vector2(1, 3)), Color("d8d8bd"))
			ci.draw_rect(Rect2(at + Vector2(1, -1), Vector2(1, 3)), Color("d8d8bd"))


# Surface-following crawler; its travel direction and support probes rotate around corners.
class ThornmiteEnemy extends CombatEnemy:
	# Crawls around terrain like a mite on a rock: floors, walls and ceilings, turning at every corner.
	var dir := Vector2i.RIGHT  # crawl direction
	var down := Vector2i.DOWN  # the surface it clings to
	var crawl := 0.0  # sub-pixel movement owed
	var fall := 0.0
	# Initialize ThornmiteEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(8, 8)
		hp = variant_hp(2)
		dir = Vector2i(facing, 0)
	# Determine whether this crawler has a supporting surface to continue following.
	func clings() -> bool:
		return blocked(Rect2i(rect.position + down, rect.size))
	# Return the facing direction used to distinguish the shielded front from an exposed rear.
	func front() -> Vector2:
		return Vector2(dir)
	# Compute the small surface region where this venom variant leaves a harmful trail.
	func venom_spot() -> Rect2i:  # a trail on whatever surface it clings to
		match down:
			Vector2i.UP: return Rect2i(rect.position.x, rect.position.y, rect.size.x, 4)
			Vector2i.LEFT: return Rect2i(rect.position.x, rect.position.y, 4, rect.size.y)
			Vector2i.RIGHT: return Rect2i(rect.end.x - 4, rect.position.y, 4, rect.size.y)
		return Rect2i(rect.position.x, rect.end.y - 4, rect.size.x, 4)
	# Advance ThornmiteEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		if not clings():
			down = Vector2i.DOWN
			if not clings():  # nothing to hold: drop to the floor below
				fall = minf(160, fall + 400 * dt)
				if move_enemy(Vector2(0, fall * dt)):
					fall = 0
					dir = Vector2i(facing, 0)
				return
		crawl += 20 * speed_multiplier * dt
		while crawl >= 1:
			crawl -= 1
			var ahead := Rect2i(rect.position + dir, rect.size)
			if blocked(ahead):  # inner corner: climb the wall ahead
				var turned := -down
				down = dir
				dir = turned
				continue
			rect = ahead
			contact()
			if not clings():  # outer corner: turn and step around the edge in one move, so it never lets go
				var turned := down
				down = -dir
				dir = turned
				var around := Rect2i(rect.position + dir, rect.size)
				if not blocked(around):
					rect = around
					contact()
		facing = 1 if down.x * dir.y - down.y * dir.x < 0 else -1
	# Draw ThornmiteEnemy at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if down == Vector2i.DOWN or not collidable:
			super.draw(ci)
			return
		for pd in puddles:
			ci.draw_rect(Rect2(pd[0]), Color(0.55, 0.85, 0.3, minf(1.0, pd[1]) * 0.45))  # fades as it dries
		ci.draw_set_transform(center(), Vector2(Vector2i.DOWN).angle_to(Vector2(down)), Vector2.ONE)  # feet on its surface
		EnemyArt.draw(ci, d.t, Vector2.ZERO, facing, clock, flash > 0, scale)
		ci.draw_set_transform(Vector2.ZERO)


# Ground charger: face the player, warn, charge and pause before the next attack.
class HornbackEnemy extends CombatEnemy:
	# Walks its floor. A player at its height in sight gets a warning, then a fast charge that stops at walls and ledges.
	var gravity_speed := 0.0
	# Initialize HornbackEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(12, 10)
		hp = variant_hp(3)
	# Advance HornbackEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		gravity_speed = minf(140, gravity_speed + 400 * dt)
		if move_enemy(Vector2(0, gravity_speed * dt)): gravity_speed = 0
		timer -= dt
		match phase:
			"windup":
				if timer <= 0:
					Game.play_sfx("enemy_attack")
					phase = "charge"
					timer = 1.2
			"charge":
				if walk(110 * speed_multiplier * dt) or timer <= 0:
					phase = "rest"
					timer = 0.9 * recovery_multiplier
			"rest":
				if timer <= 0: phase = "idle"
			_:
				var offset: Vector2 = w.player.center() - center()
				if absf(offset.y) < 12 * scale and sees_player(120 * scale):
					facing = -1 if offset.x < 0 else 1
					Game.play_sfx("enemy_alert")
					phase = "windup"
					timer = 0.5 * warning_multiplier
				elif not safe_step():
					facing *= -1
				elif walk(16 * speed_multiplier * dt):
					facing *= -1


# A monster assembled from the action library (scripts/monster_library.gd): one move, its attacks, its traits.
# Placed without a build (a fresh editor placement), it rolls one, seeded by its position, and keeps it in its data.
class ActionMonster extends CombatEnemy:
	var orbs: Array = []  # its bolts, straight: [position, velocity, seconds left] (CombatEnemy.update_shots)
	var bones: Array = []  # its lobbed globs, falling (named like the Ossling's so damage_boxes sees them)
	var velocity := Vector2.ZERO
	var on_floor := false
	var attack := ""  # the attack under way
	var hop_t := 0.0
	func describe() -> String:
		return super.describe() + " - " + MonsterLib.describe(d)
	func setup() -> void:
		if not d.has("move"):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([d.x, d.y])
			d.merge(MonsterLib.build(rng))
		rect.size = Vector2i(10, 10)
		variant = ""
		for t in d.traits:  # traits stack: multiply their speed / warning / recovery, keep the biggest size
			var m: Array = VARIANTS[t]
			speed_multiplier *= m[0]
			warning_multiplier *= m[1]
			recovery_multiplier *= m[2]
			scale = maxf(scale, m[3])
		hp = MonsterLib.MOVES[d.move].hp
		for t in d.traits:
			variant = t
			hp = variant_hp(hp)
		variant = ""
		facing = -1 if int(d.get("facing", -1)) < 0 else 1
		home = Vector2(rect.position)
	func has_trait(t: String) -> bool:
		return t in d.get("traits", [])
	func ground() -> bool:
		return MonsterLib.MOVES[d.move].ground
	func brood() -> void:  # two small, quick copies without the brood trait
		for side in [-1, 1]:
			var kid: Dictionary = d.duplicate(true)
			kid.traits = d.traits.filter(func(t): return t != "brood")
			var at := Vector2i(center()) + Vector2i(side * 4 - 2, -2)
			kid.merge({"x": at.x, "y": at.y, "facing": side, "brood_child": true}, true)
			w.spawn_entity(kid)
	func update(dt: float) -> void:
		if w != null and w.player != null:
			update_shots(orbs, dt, 0.0)
			update_shots(bones, dt, 240.0)
		if not active(dt): return
		if ground() and not (phase == "attack" and attack == "leap"):
			velocity.y = minf(140, velocity.y + 400 * dt)
			on_floor = move_enemy(Vector2(0, velocity.y * dt)) and velocity.y > 0
			if on_floor:
				velocity.y = 0
		timer -= dt
		match phase:
			"windup":
				if timer <= 0:
					Game.play_sfx("enemy_attack")
					_start(attack)
			"attack":
				if _attack(dt):
					phase = "rest"
					timer = 0.9 * recovery_multiplier
			"rest":
				if timer <= 0:
					phase = "return" if not ground() else "idle"
			"return":  # flyers go back to their spot
				var back := home - Vector2(rect.position)
				if back.length() < 2 or move_enemy(back.limit_length(40 * speed_multiplier * dt)):
					phase = "idle"
			_:
				_move(dt)
				for a in d.attacks:
					if sees_player(MonsterLib.ATTACKS[a].range * scale) and (a not in ["charge"] or absf(w.player.center().y - center().y) < 12 * scale):
						facing = -1 if w.player.center().x < center().x else 1
						Game.play_sfx("enemy_alert")
						attack = a
						phase = "windup"
						timer = 0.5 * warning_multiplier
						break
	func _move(dt: float) -> void:
		match d.move:
			"patrol":
				if not safe_step() or walk(16 * speed_multiplier * dt):
					facing *= -1
			"hop":
				hop_t -= dt
				if on_floor and hop_t <= 0:
					if not safe_step():
						facing *= -1
					hop_t = 0.8 / speed_multiplier
					velocity = Vector2(facing * 40 * speed_multiplier, -110)
				if not on_floor and move_enemy(Vector2(velocity.x * dt, 0)):
					facing *= -1
					velocity.x = -velocity.x
			"hover":
				var goal := home + Vector2(sin(clock * 0.8) * 12, sin(clock * 1.6) * 4)
				move_enemy((goal - Vector2(rect.position)).limit_length(30 * speed_multiplier * dt))
	func _start(a: String) -> void:
		phase = "attack"
		var to: Vector2 = w.player.center() - center()
		match a:
			"charge": timer = 1.2
			"leap": velocity = Vector2(clampf(to.x / 0.6, -120, 120), -170)
			"shoot": orbs.append([center(), to.normalized() * 100, 2.5])
			"lob": bones.append([center(), Vector2(to.x / 1.0, -120), 2.5])
			"dive":
				velocity = to.normalized() * 150 * speed_multiplier
				timer = 0.6
	func _attack(dt: float) -> bool:  # true when the attack is over
		match attack:
			"charge":
				return walk(110 * speed_multiplier * dt) or timer <= 0
			"leap":
				velocity.y += 450 * dt
				move_enemy(Vector2(velocity.x * dt, 0))
				var landed := move_enemy(Vector2(0, velocity.y * dt)) and velocity.y > 0
				if landed:
					velocity = Vector2.ZERO
				return landed
			"dive":
				return move_enemy(velocity * dt) or timer <= 0
		return true  # shoot, lob: the shot is out
	func vis_rect() -> Rect2i:
		var area := body_rect()
		for o in orbs + bones:
			area = area.merge(Rect2i(Vector2i(o[0]) - Vector2i(2, 2), Vector2i(5, 5)))
		return area
	func draw(ci: CanvasItem) -> void:
		for o in orbs + bones:
			ci.draw_rect(Rect2(o[0] - Vector2(1.5, 1.5), Vector2(3, 3)), Color("e070b0"))
		if not collidable:
			super.draw(ci)
			return
		var keep_t: String = d.t
		d.t = d.get("look", "enemy_mosstrot")  # wears a family's art
		super.draw(ci)
		d.t = keep_t
		for i in int(d.get("tier", 0)):  # upgrades: a small mark per tier over the head
			ci.draw_rect(Rect2(center().x - 3 + i * 4, rect.position.y - 7, 2, 2), Color("ff6060"))


# Ground walker that turns at walls and unsafe floor edges instead of wandering into hazards.
class MosstrotEnemy extends CombatEnemy:
	# Jungle wanderer: walks back and forth on its floor, turning at walls and ledges. Never chases; touching it still hurts.
	var gravity_speed := 0.0
	# Initialize MosstrotEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(12, 8)
		hp = variant_hp(2)
	# Advance MosstrotEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		gravity_speed = minf(140, gravity_speed + 400 * dt)
		if move_enemy(Vector2(0, gravity_speed * dt)): gravity_speed = 0
		if walk(14 * speed_multiplier * dt):
			facing *= -1


# Floating enemy with a repeating motion around its home position.
class FuzzbobEnemy extends CombatEnemy:
	# Drifts diagonally and bounces off anything solid; it never chases, its path is the threat.
	var velocity := Vector2.ZERO
	# Initialize FuzzbobEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(10, 10)
		hp = variant_hp(2)
		velocity = Vector2(facing, 1).normalized() * 30 * speed_multiplier
	# Advance FuzzbobEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		if move_enemy(Vector2(velocity.x * dt, 0)): velocity.x = -velocity.x
		if move_enemy(Vector2(0, velocity.y * dt)): velocity.y = -velocity.y
		facing = 1 if velocity.x > 0 else -1


# Heavy ground enemy that telegraphs a leap, lands and recovers before attacking again.
class CragjawEnemy extends CombatEnemy:
	# Big brute: plods along its floor; a player in reach gets a warning, then a leap that slams down near them.
	var velocity := Vector2.ZERO
	# Initialize CragjawEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(20, 20)
		hp = variant_hp(6)
	# Advance CragjawEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		velocity.y = minf(220, velocity.y + 400 * dt)
		if move_enemy(Vector2(velocity.x * dt, 0)): velocity.x = 0
		if move_enemy(Vector2(0, velocity.y * dt)):
			if velocity.y > 0 and phase == "leap":
				phase = "rest"
				timer = 1.0 * recovery_multiplier
				velocity.x = 0
				w.shake_dir(Vector2.DOWN, 0.15)
			velocity.y = 0
		timer -= dt
		match phase:
			"windup":
				if timer <= 0:
					Game.play_sfx("enemy_attack")
					phase = "leap"
					velocity = Vector2(clampf((w.player.center().x - center().x) / 0.8, -110, 110) * speed_multiplier, -170)
			"leap":
				pass
			"rest":
				if timer <= 0: phase = "idle"
			_:
				var offset: Vector2 = w.player.center() - center()
				if absf(offset.x) < 140 * scale and absf(offset.y) < 64 * scale and sees_player(150 * scale):
					facing = -1 if offset.x < 0 else 1
					Game.play_sfx("enemy_alert")
					phase = "windup"
					timer = 0.6 * warning_multiplier
				elif not safe_step():
					facing *= -1
				elif walk(12 * speed_multiplier * dt):
					facing *= -1


# Floating ranged enemy that launches orb projectiles after a visible warning.
class MurksporeEnemy extends CombatEnemy:
	# Big hovering spore: keeps its distance, bobs, and spits a three-orb spread at a visible player.
	var orbs: Array = []  # owned projectiles (see update_shots)
	var bob := 0.0
	# Initialize MurksporeEnemy dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(16, 14)
		hp = variant_hp(5)
		timer = 1.0
	# Advance MurksporeEnemy timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if not active(dt): return
		update_orbs(dt)
		bob += dt * 2.0
		var to: Vector2 = w.player.center() - center()
		var sees := sees_player(180)
		var goal: Vector2 = (to - to.normalized() * 80) if sees else (home - Vector2(rect.position))
		var v: Vector2 = goal.limit_length(24 * speed_multiplier)
		move_enemy(Vector2(v.x * dt, 0))
		move_enemy(Vector2(0, (v.y + sin(bob) * 10) * dt))
		if sees:
			facing = -1 if to.x < 0 else 1
		timer -= dt
		if phase == "windup":
			if timer <= 0:
				for a in [-0.3, 0.0, 0.3]:
					Game.play_sfx("projectile")
					orbs.append([center(), to.normalized().rotated(a) * 70, 3.0])
				phase = "idle"
				timer = 2.2 * recovery_multiplier
		elif timer <= 0 and sees and orbs.is_empty():
			Game.play_sfx("enemy_alert")
			phase = "windup"
			timer = 0.5 * warning_multiplier
	# Advance this enemy orb projectiles through the shared projectile update helper.
	func update_orbs(dt: float) -> void:
		update_shots(orbs, dt, 0)
	# Apply one sword hit, respecting shield/flash protection and triggering death or variant reactions.
	func hit(p) -> void:
		super.hit(p)
		if not collidable: orbs.clear()
	# Return conservative visible bounds including MurksporeEnemy effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return shots_rect(orbs)
	# Draw MurksporeEnemy at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		super.draw(ci)
		for orb in orbs:
			ci.draw_circle(orb[0].round(), 2.5, Color("b07ad8"))
			ci.draw_circle(orb[0].round(), 1.2, Color("f0d8ff"))


# Water/acid region. Water drains adventure stamina; acid is a lethal contact surface.
class Liquid extends Ent:  # water: drains adventure stamina (World.update_stamina); acid: kills on touch (like spikes)
	func describe() -> String:
		return "Acid: deadly to touch" if d.t == "acid" else "Water: you swim; drains stamina 40/s, no regeneration; 0 drowns"
	# Report whether Liquid currently participates in lethal contact checks.
	func hurts() -> bool: return d.t == "acid"
	# Initialize Liquid dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		collidable = d.t == "acid"
	# Kill the player on an enabled acid contact; ordinary water is handled by separate immersion checks.
	func touch(p) -> void:
		p.die(Vector2.UP)
	# Draw Liquid at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if d.t == "acid" and d.get("skin", "") == "lava":
			ci.draw_rect(Rect2(rect), Color("b9533e"))
			if d.get("top", true) and joins(BlockArt.JOIN_TOP) == 0:  # the glowing top only where nothing is above
				var tex := IslandArt.texture("lava", "idle", int(Time.get_ticks_msec()/150) if w != null else 0)
				for x in range(0, rect.size.x, 32):
					var size := Vector2(mini(32, rect.size.x-x), mini(8, rect.size.y))
					ci.draw_texture_rect_region(tex, Rect2(Vector2(rect.position)+Vector2(x,0),size),Rect2(Vector2.ZERO,size))
			return
		var c: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(rect), Color(c, 0.35))
		if d.get("top", true):  # the surface line, only where no other pool of the same liquid sits right above
			var above := Rect2(rect.position.x, rect.position.y - 1, rect.size.x, 1)
			var covers: Array = []  # x spans of pools over the top edge (usually none)
			for e in peers():
				if e != self and e is Liquid and e.d.t == d.t and Rect2(e.rect).intersects(above):
					covers.append(Vector2(e.rect.position.x, e.rect.end.x))
			var col := Color(c.lightened(0.4), 0.9)
			if covers.is_empty():
				ci.draw_line(Vector2(rect.position), Vector2(rect.end.x, rect.position.y), col, 1.0)
				return
			var step := 8 if rect.position.x % 8 == 0 and rect.size.x % 8 == 0 else 1
			var x := rect.position.x
			while x < rect.end.x:
				var x1 := x
				while x1 < rect.end.x and not covers.any(func(v): return x1 >= v.x and x1 < v.y):
					x1 += step
				if x1 > x:
					ci.draw_line(Vector2(x, rect.position.y), Vector2(x1, rect.position.y), col, 1.0)
				x = x1 + step


# Attackable solid wall. Destroying it records a persistent ID so it stays gone in the adventure.
class BreakWall extends Ent:
	var id := ""
	var hp := 3
	var flash := 0.0
	# Initialize BreakWall dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		fixed = true
		hp = int(d.get("hp", 3))
		id = "%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
			collidable = not w.broken.has(id)
	# Apply one sword hit, respecting shield/flash protection and triggering death or variant reactions.
	func hit(_p) -> void:
		Game.play_sfx("impact")
		hp -= 1
		flash = 0.12
		w.burst(center(), TYPES.breakwall[2], 4)
		if hp <= 0:
			collidable = false
			w.break_wall(id)
			w.burst(center(), TYPES.breakwall[2], 20)
			w.shake_dir(Vector2.ZERO, 0.15)
	# Advance BreakWall timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		flash = maxf(flash - dt, 0)
		shaken(dt, flash > 0)
	# Draw BreakWall at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var damage := clampi(int(d.get("hp", 3)) - hp, 0, 2)
		BlockArt.draw(ci, rect, "breakwall", shake, damage, joins())
		var r := Rect2(Vector2(rect.position) + shake, rect.size)
		if flash > 0:
			ci.draw_rect(r, Color(1, 1, 1, 0.5))


# Editor reminder or authored one-shot sound trigger; sound triggers stay invisible during gameplay.
class Note extends Ent:  # design reminder or a one-shot authored sound trigger
	var sound_played := false
	# Return the pixel rectangle that activates Note contact, separate from artwork bounds.
	func touch_rect() -> Rect2i:
		return rect.grow(8)
	# Play an authored sound once per object lifetime, or renew the visible note message while nearby.
	func touch(_p) -> void:
		if d.has("sound"):
			if not sound_played:
				sound_played = true
				Game.play_sfx(str(d.sound))
			return
		w.show_note(str(d.get("text", "")))
	# Return conservative visible bounds including Note effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return rect.grow(8) if w != null else Rect2i(rect.position - Vector2i(160, 24), Vector2i(328, 40))
	# Draw Note at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if w != null and d.has("sound"):
			return
		var p := Vector2(rect.position)
		ci.draw_rect(Rect2(p + Vector2(1, 0), Vector2(6, 8)), Color("ffe08a"))
		ci.draw_rect(Rect2(p + Vector2(1, 0), Vector2(6, 8)), Color("8a6a2a"), false, 1.0)
		ci.draw_rect(Rect2(p + Vector2(3.5, 1.5), Vector2(1, 3)), Color("8a3a2a"))  # "!"
		ci.draw_rect(Rect2(p + Vector2(3.5, 5.5), Vector2(1, 1)), Color("8a3a2a"))
		if w == null:  # editor: the text above the note
			var t := str(d.get("text", ""))
			var f := ThemeDB.fallback_font
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
			ci.draw_rect(Rect2(p + Vector2(4 - tw / 2 - 1, -9), Vector2(tw + 2, 8)), Color(0, 0, 0, 0.7))
			ci.draw_string(f, p + Vector2(4 - tw / 2, -3), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffe08a"))


# Collectible that follows the player, then banks after a short stay on safe ground.
class Discovery extends Ent:
	var key := ""
	var near := 0.0
	var clock := 0.0
	var speaking := 0.0
	func setup() -> void:
		rect.size = Vector2i(8,12) if d.t == "energy_fragment" else Vector2i(16,16)
		if d.t == "energy_fragment": rect.position.y -= 4
		if w != null:
			key = "fragment:%s:%s" % [w.room, str(d.get("id", "%d_%d" % [int(d.x),int(d.y)]))]
			if d.t == "energy_fragment": collidable = w.adventure() and not w.stamina_block_taken(key)
	func touch_rect() -> Rect2i:
		return rect.grow(8)
	func vis_rect() -> Rect2i:
		return rect.grow(20)
	func update(dt: float) -> void:
		near = maxf(0,near-dt)
		speaking = maxf(0,speaking-dt)
		clock += dt
	func touch(p) -> void:
		near = 0.12
		if p.dead or not p.interact:
			return
		p.interact = false  # one press cannot also activate a nearby doorway
		if d.t == "energy_fragment":
			if w.collect_energy_fragment(key): collidable = false
		else:
			speaking = 3.0
			w.show_interaction("%s: %s" % [d.get("name","Traveller"),d.get("text","...")])
			Game.play_sfx("note")
	func draw(ci: CanvasItem) -> void:
		if not collidable: return
		if d.t == "energy_fragment":
			var c := Vector2(rect.get_center())
			ci.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-5),c+Vector2(4,-1),c+Vector2(1,5),c+Vector2(-4,2)]),Color("8ce1cc"))
			ci.draw_line(c+Vector2(0,-3),c+Vector2(-1,2),Color("d9fff0"),1.0)
		else:
			ci.draw_texture_rect(IslandArt.texture(str(d.get("kind","elf")),"talk" if speaking>0 else "idle",int(clock*5),int(d.get("variant",0))),Rect2(rect),false)
		if near > 0 and w != null:
			var icon := ButtonArt.prompt("interact")
			ci.draw_texture_rect(icon,Rect2(Vector2(rect.get_center())-Vector2(5,rect.size.y/2.0+13),Vector2(10,10)),false)


class Star extends Ent:  # legacy collectible; new discovery placements use explicit interaction
	const STAR_PTS := [Vector2(0, -4.5), Vector2(1.2, -1.6), Vector2(4.3, -1.4), Vector2(1.9, 0.6), Vector2(2.6, 3.6), Vector2(0, 2), Vector2(-2.6, 3.6), Vector2(-1.9, 0.6), Vector2(-4.3, -1.4), Vector2(-1.2, -1.6)]  # 5-point star around (0, 0)
	var id := ""
	var following := false
	var collect_timer := 0.0
	var pos := Vector2.ZERO
	var t := 0.0
	# Initialize Star dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		id = str(d.get("persistent_id", "%d_%d" % [rect.position.x, rect.position.y]))
		if w != null:
			id = w.star_key(id)
		rect = Rect2i(rect.position.x - 1, rect.position.y - 1, 10, 10)
		pos = center()
		collidable = w == null or not w.collected.has(id)
	# Move an unbanked star behind the player and bank it after the player rests on safe ground.
	func update(dt: float) -> void:
		t += dt
		if not collidable:
			return
		var p = w.player
		if following and p != null and not p.dead:
			var idx: int = p.followers.find(self)
			var target: Vector2 = p.pos + Vector2(-p.facing * (8 + idx * 8), -10)
			pos = pos.lerp(target, 1.0 - pow(0.001, dt))
			if p.on_safe_ground and p.state != p.ST_DREAM_DASH:
				collect_timer += dt
				if collect_timer > 0.15:
					collidable = false
					w.collect_berry(self)
					p.followers.erase(self)
			else:
				collect_timer = 0
	# Apply Star interaction when World reports an overlapping player.
	func touch(p) -> void:
		if collidable and not following:
			Game.play_sfx("pickup", 0.8)
			following = true
			p.followers.append(self)
	# Return the pixel rectangle that activates Star contact, separate from artwork bounds.
	func touch_rect() -> Rect2i:  # exactly the sprite at rest
		return Rect2i(rect.position + Vector2i(2, 2), Vector2i(6, 7)) if not following else Rect2i()
	# Return conservative visible bounds including Star effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:  # drawn at pos, which trails the player
		return Rect2i(Vector2i(pos) - Vector2i(8, 8), Vector2i(16, 16))
	# Draw Star at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := pos + Vector2(0, 0 if following else round(sin(t * 2.5)))
		ci.draw_colored_polygon(Transform2D(0, c) * PackedVector2Array(STAR_PTS), Color("ffd34e"))
		ci.draw_rect(Rect2(c.x - 1, c.y - 1, 1, 1), Color("fff6c0"))


# One-way platform: supports downward landings but permits upward travel through it.
# One-way platform: land on it from above, jump up through it, down + jump drops through. Its look follows the
# room's environment (d.look overrides it): leaves in the jungle (forest), the plank rail elsewhere until each
# environment has its own art (docs/reviews/platform-art/CODEX_PROMPT.md). Old "leaf" platforms load as
# jump-throughs with look "forest" (Game.validate_level).
class JumpThru extends Ent:
	static var editor_look := ""  # the editor sets this to the edited room's environment before drawing
	# Initialize JumpThru dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		jumpthru = true
		rect.size.y = 5
	func look() -> String:
		if d.has("look"):
			return str(d.look)
		return str(w.data.get("environment", "")) if w != null else editor_look
	# Draw JumpThru at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if look() == "forest":
			_draw_leaves(ci)
		else:  # side by side, rails join (5 px tall: only left and right)
			BlockArt.draw(ci, rect, "jumpthru", Vector2.ZERO, 0, joins(BlockArt.JOIN_LEFT | BlockArt.JOIN_RIGHT))
	# Leaves on a stem, filling the box exactly.
	func _draw_leaves(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color("41673a"))  # stem
		for x in range(0, int(r.size.x), 6):
			var lw := minf(5, r.size.x - x)
			ci.draw_rect(Rect2(r.position + Vector2(x, 0), Vector2(lw, r.size.y - 1)), Color("7fc04e") if x % 12 else Color("6aa840"))
			ci.draw_rect(Rect2(r.position + Vector2(x + 1, 0), Vector2(maxf(0, lw - 2), 1)), Color("b6e080"))


# Falling-water artwork; Player separately applies its downward force as a movement layer.
class Waterfall extends Ent:  # falling water; the push is the player's waterfall layer (Player._layers)
	var t := 0.0
	# Advance Waterfall timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
	# Draw Waterfall at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		ci.draw_rect(r, Color(0.54, 0.78, 0.94, 0.45))
		for x in range(1, int(r.size.x) - 1, 3):  # streaks scrolling down
			var y := fposmod(t * 120.0 + x * 7, 12.0)
			while y < r.size.y:
				ci.draw_rect(Rect2(r.position + Vector2(x, y), Vector2(1, minf(4, r.size.y - y))), Color(0.9, 0.97, 1.0, 0.6))
				y += 12.0


# Temporary support that shakes under a rider, disappears and reforms when the space is clear.
class Crumble extends Ent:
	var st := 0  # 0 idle, 1 shaking, 2 gone
	var timer := 0.0
	# Initialize Crumble dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		fixed = true
		safe = false
	# Advance Crumble timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		match st:
			0:
				if player_riding():
					Game.play_sfx("mechanism")
					st = 1
					timer = 0.4 if w.player.state != w.player.ST_CLIMB else 0.6
			1:
				timer -= dt
				shaken(dt, true)
				if timer <= 0:
					Game.play_sfx("crumble")
					st = 2
					collidable = false
					timer = 2.0
					shake = Vector2.ZERO
					w.burst(center(), Color("8a7a6a"), 6)
			2:
				timer -= dt
				if timer <= 0 and (w.player == null or w.player.dead or not rect.intersects(w.player.hitbox())):
					st = 0
					collidable = true
	# Draw Crumble at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			ci.draw_rect(Rect2(rect), Color(1, 1, 1, 0.08), false, 1.0)
			return
		BlockArt.draw(ci, rect, "crumble", shake, 1 if st == 1 else 0, joins())


# Heavy support that shakes when ridden, falls pixel by pixel and stops when it reaches solid terrain.
class FallingBlock extends Ent:
	var st := 0  # 0 wait, 1 shake, 2 fall, 3 landed
	var timer := 0.0
	var vy := 0.0
	# Initialize FallingBlock dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		safe = false
	# Advance FallingBlock timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		match st:
			0:
				if player_riding():
					Game.play_sfx("mechanism")
					st = 1
					timer = 0.2
			1:
				timer -= dt
				shaken(dt, true)
				if timer <= 0:
					st = 2
					shake = Vector2.ZERO
			2:
				vy = Player_approach(vy, 160.0, 500.0 * dt)
				rem.y += vy * dt
				var m := roundi(rem.y)
				rem.y -= m
				for i in m:
					collidable = false
					var below = w.collide_solid(Rect2i(rect.position + Vector2i(0, 1), rect.size))
					collidable = true
					if below != null or rect.position.y > w.bounds.end.y + 16:
						st = 3
						lift = Vector2.ZERO
						w.shake_dir(Vector2.DOWN, 0.1)
						break
					move_by(Vector2(0, 1), dt)
					lift = Vector2(0, vy)
	# Move a value toward its target by a limited amount; used here for falling-block acceleration.
	static func Player_approach(v: float, t: float, a: float) -> float:
		return minf(v + a, t) if v <= t else maxf(v - a, t)
	# Draw FallingBlock at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		BlockArt.draw(ci, rect, str(d.get("art", "falling")), shake)


# Rail platform that travels to a configured target, waits and returns to its starting point.
class ZipMover extends Ent:
	var start := Vector2.ZERO
	var target := Vector2.ZERO
	var st := 0
	var timer := 0.0
	var at := 0.0
	# Initialize ZipMover dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		start = Vector2(rect.position)
		target = Vector2(float(d.get("tx", rect.position.x)), float(d.get("ty", rect.position.y - 32)))
	# Return conservative visible bounds including ZipMover effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:  # block plus the whole rail
		var r := rect.merge(Rect2i(Vector2i(start), rect.size)).merge(Rect2i(Vector2i(target), rect.size))
		return r.grow(8)
	# Ease progress from slow to fast with a sine curve, giving the rail platform a less abrupt departure.
	static func sine_in(x: float) -> float:
		return 1.0 - cos(x * PI / 2.0)
	# Move this rail platform toward an interpolated position while preserving rider/pushing behavior.
	func _goto(p: Vector2, dt: float) -> void:
		move_by(p - (Vector2(rect.position) + rem), dt)
	# Advance ZipMover timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		match st:
			0:
				if player_riding():
					Game.play_sfx("mechanism")
					st = 1
					timer = 0.1
			1:
				timer -= dt
				shaken(dt, true)
				if timer <= 0:
					shake = Vector2.ZERO
					st = 2
					at = 0
			2:
				at = move_toward(at, 1.0, 2.0 * dt)
				_goto(start.lerp(target, sine_in(at)), dt)
				if at >= 1.0:
					w.shake_dir((target - start).normalized(), 0.15)
					st = 3
					timer = 0.5
			3:
				lift = Vector2.ZERO
				timer -= dt
				if timer <= 0:
					st = 4
					at = 0
			4:
				at = move_toward(at, 1.0, 0.5 * dt)
				_goto(target.lerp(start, sine_in(at)), dt)
				if at >= 1.0:
					st = 5
					timer = 0.5
			5:
				lift = Vector2.ZERO
				timer -= dt
				if timer <= 0:
					st = 0
	# Draw ZipMover at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var half := Vector2(rect.size) / 2.0
		var a := start + half
		var b := target + half
		ci.draw_line(a, b, Color("4a4030"), 2.0)
		ci.draw_circle(a, 2, Color("4a4030"))
		ci.draw_circle(b, 2, Color("4a4030"))
		var r := Rect2(Vector2(rect.position) + shake, rect.size)
		BlockArt.draw(ci, rect, "zip", shake)
		var lit := Color("60e060") if st in [0, 5] else (Color("e04040") if st != 3 else Color("e0e040"))
		ci.draw_rect(Rect2(r.get_center() - Vector2(1.5, 1.5), Vector2(3, 3)), lit)


# Solid special block for normal movement, traversable only during dream-dash behavior.
class DreamBlock extends Ent:
	var stars: Array = []
	var t := 0.0
	# Initialize DreamBlock dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		fixed = true
		dream = true
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(rect)
		for i in maxi(2, rect.get_area() / 40):
			stars.append([Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y), [Color("ffef70"), Color("70ffef"), Color("ff70d0"), Color.WHITE][rng.randi() % 4]])
	# Advance DreamBlock timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
	# Draw DreamBlock at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		ci.draw_rect(r, Color("101018"))
		for s in stars:
			var p: Vector2 = r.position + s[0]
			if int(t * 4 + p.x) % 3 != 0:
				ci.draw_rect(Rect2(p.floor(), Vector2.ONE), s[1])
		ci.draw_rect(r, Color.WHITE, false)


# Bubble that captures the player and launches a normal or red dash before recharging.
class Booster extends Ent:
	var red := false
	var cannot_use := 0.0
	var t := 0.0
	# Initialize Booster dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		red = d.t == "booster_red"
		rect = Rect2i(rect.position.x - 3, rect.position.y - 3, 14, 14)  # exactly the sprite
	# Advance Booster timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
		cannot_use = maxf(0, cannot_use - dt)
		if respawn > 0:
			respawn -= dt
	# Apply Booster interaction when World reports an overlapping player.
	func touch(p) -> void:
		if respawn <= 0 and cannot_use <= 0 and p.state != p.ST_BOOST:
			cannot_use = 0.45
			p.boost(self, red)
	# Start the booster recharge timer after it successfully launches the player.
	func player_boosted() -> void:
		respawn = 1.0
	# Start the recharge timer when the player leaves this booster.
	func player_released() -> void:
		respawn = 1.0
	# Draw Booster at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c := center()
		var col := Color("d03a3a") if red else Color("2ea04f")
		if respawn > 0:
			ci.draw_arc(c, 2, 0, TAU, 8, Color(col, 0.4), 1.0)
			return
		var rr := 7.0 + sin(t * 4) * 0.5
		ci.draw_circle(c, rr, Color(col, 0.35))
		ci.draw_arc(c, rr, 0, TAU, 20, col.lightened(0.3), 1.0)
		ci.draw_circle(c + Vector2(-2, -3), 1.2, Color(1, 1, 1, 0.7))


# Reusable radial launcher that pushes the player away from its centre.
class Bumper extends Ent:
	var t := 0.0
	# Initialize Bumper dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect = Rect2i(rect.position.x - 5, rect.position.y - 5, 18, 18)  # exactly the sprite
	# Advance Bumper timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	# Apply Bumper interaction when World reports an overlapping player.
	func touch(p) -> void:
		if respawn <= 0:
			p.explode_launch(center(), false)
			respawn = 0.6
			w.burst(center(), Color("80a0ff"), 10)
	# Draw Bumper at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 2) * 1.0))
		var col := Color("4060d0") if respawn <= 0 else Color("303050")
		ci.draw_circle(c, 9, col)
		ci.draw_arc(c, 9, 0, TAU, 24, col.lightened(0.4), 1.0)
		ci.draw_circle(c, 3, col.lightened(0.5))


# Temporary flight pickup that starts or extends the player flight mode.
class Feather extends Ent:
	# Return the pixel rectangle that activates Feather contact, separate from artwork bounds.
	func touch_rect() -> Rect2i:  # exactly the sprite
		return Rect2i(rect.position + Vector2i(1, 2), Vector2i(9, 9))
	var t := 0.0
	# Initialize Feather dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect = Rect2i(rect.position.x - 2, rect.position.y - 2, 12, 12)
	# Advance Feather timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	# Apply Feather interaction when World reports an overlapping player.
	func touch(p) -> void:
		if respawn <= 0 and p.start_star_fly():
			respawn = 3.0
			w.burst(center(), Color("ffd65c"), 8)
	# Draw Feather at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 3) * 1.5))
		if respawn > 0:
			ci.draw_arc(c, 2, 0, TAU, 8, Color(1, 0.85, 0.4, 0.3), 1.0)
			return
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 4), c + Vector2(4, -4), c + Vector2(2, 2)]), Color("ffd65c"))
		ci.draw_line(c + Vector2(-5, 5), c + Vector2(3, -3), Color("fff3c0"), 1.0)


# End-of-level marker that asks World to record completion once.
class Goal extends Ent:
	# Return the pixel rectangle that activates Goal contact, separate from artwork bounds.
	func touch_rect() -> Rect2i:  # exactly the sprite
		return Rect2i(rect.position + Vector2i(2, 4), Vector2i(11, 9))
	var t := 0.0
	# Initialize Goal dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect = Rect2i(rect.position.x - 4, rect.position.y - 4, 16, 16)
	# Advance Goal timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		t += dt
	# Apply Goal interaction when World reports an overlapping player.
	func touch(_p) -> void:
		w.complete()
	# Draw Goal at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 2) * 1.5))
		var col := Color("50b0ff")
		ci.draw_circle(c + Vector2(-2.5, -1.5), 3, col)
		ci.draw_circle(c + Vector2(2.5, -1.5), 3, col)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5.5, -1), c + Vector2(5.5, -1), c + Vector2(0, 6)]), col)
		ci.draw_rect(Rect2(c.x - 3, c.y - 3, 1, 1), Color.WHITE)


# ---------------- Boss 1: the Ape (docs/STORY_DESIGN.md section 2) ----------------
# A tall trunk in the arena. Standing it's scenery (no collision); a thrown stone fells it to the right,
# where it lies at its base's height as a bridge as long as it was tall. Stays down for the run.
# Arena tree obstacle; a boss impact fells it into a persistent horizontal bridge.
class ApeTrunk extends Ent:
	const FALL_TIME := 0.6
	var id := ""
	var standing := Rect2i()
	var fall := 0.0  # 0 standing .. 1 down
	var falling := false
	# Initialize ApeTrunk dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		collidable = false
		standing = rect
		id = "%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
			if w.broken.has(id):
				_lay()
	# Report whether the arena trunk has finished becoming a horizontal bridge.
	func down() -> bool:
		return fall >= 1.0
	# Start the trunk falling sequence once, in response to an arena impact.
	func fell() -> void:
		if falling or down():
			return
		falling = true
		if w != null:
			w.burst(Vector2(standing.position.x + standing.size.x / 2.0, standing.position.y + 8), Color("c8a070"), 10)
	# Replace the upright trunk collision rectangle with the final bridge rectangle.
	func _lay() -> void:
		fall = 1.0
		falling = false
		collidable = true
		rect = Rect2i(standing.position.x, standing.end.y, standing.size.y, 8)
	# Advance ApeTrunk timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(dt: float) -> void:
		if falling:
			fall = minf(1.0, fall + dt / FALL_TIME)
			if fall >= 1.0:
				_lay()
				w.break_wall(id)
				w.shake_dir(Vector2.DOWN, 0.25)
				w.dust(Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y), Vector2.UP, 12)
	# Return conservative visible bounds including ApeTrunk effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		var h := standing.size.y
		return Rect2i(standing.position.x - 8, standing.position.y - 8, h + 24, h + 24)
	# Draw ApeTrunk at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var bark := Color("7a5638")
		var dark := Color("4e3422")
		if down():
			ci.draw_rect(Rect2(rect), bark)
			ci.draw_rect(Rect2(rect.position.x, rect.end.y - 2, rect.size.x, 2), dark)
			for x in range(rect.position.x + 6, rect.end.x - 2, 11):
				ci.draw_rect(Rect2(x, rect.position.y + 2, 3, 1), dark)
			return
		# standing (or falling): drawn upright, rotated about the base's right corner
		var pivot := Vector2(standing.end.x, standing.end.y)
		ci.draw_set_transform(pivot, fall * PI / 2.0)
		var r := Rect2(-standing.size.x, -standing.size.y, standing.size.x, standing.size.y)
		ci.draw_rect(r, bark)
		ci.draw_rect(Rect2(r.position.x, r.position.y, 2, r.size.y), dark)
		for y in range(int(r.position.y) + 5, -2, 9):
			ci.draw_rect(Rect2(r.position.x + 4, y, r.size.x - 8, 1), dark)
		var knot := minf(6.0, r.size.y)
		ci.draw_rect(Rect2(r.position.x + r.size.x / 2.0 - 3, r.position.y + minf(10.0, r.size.y - knot), 6, knot), Color("e0c060"))  # the target knot
		ci.draw_set_transform(Vector2.ZERO)


# Seals an exit while the room's Ape is alive (solid); open once it's beaten. "closes_behind": stays open
# until the player has passed it (left to right), then shuts behind them.
# Arena barrier that follows the living boss state and can close behind the entering player.
class BossGate extends Ent:
	func describe() -> String:
		return "Boss gate: %s" % ("shut (opens when the boss is beaten)" if collidable else "open")
	var passed := false
	# Initialize BossGate dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		solid = true
		fixed = true
		collidable = w == null or not d.get("closes_behind", false)
	# Advance BossGate timers and behavior for dt seconds; this is called by World, not by Godot automatically.
	func update(_dt: float) -> void:
		if d.has("until"):  # shut until that boss is beaten (in any room), e.g. a way on that opens after the fight
			collidable = not w.broken.has(str(d.until))
			return
		if d.get("closes_behind", false) and not passed:
			passed = w.player.hitbox().position.x >= rect.end.x  # fully past it (a respawn next to it counts)
		collidable = Ape.alive_in(w) and (passed or not d.get("closes_behind", false))
	# Draw BossGate at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var r := Rect2(rect)
		ci.draw_rect(r, Color("2e4a26"))
		for x in range(int(r.position.x), int(r.end.x), 4):  # thorny vines
			ci.draw_rect(Rect2(x, r.position.y, 2, r.size.y), Color("4a6a3a"))
			for y in range(int(r.position.y) + (x % 8), int(r.end.y), 8):
				ci.draw_rect(Rect2(x + 2, y, 2, 2), Color("c8d06a"))


# Decorative village inhabitants and island landmarks; no dialogue or quest behavior.
class IslandProp extends Ent:
	var clock := 0.0
	var kind := "landmark"
	func setup() -> void:
		kind = "elf" if d.t == "village_elf" else "mage" if d.t == "village_mage" else str(d.get("kind", "landmark"))
		rect.size = IslandArt.build(kind, "idle", 0, int(d.get("variant", 0))).get_size()
		collidable = false
	func update(dt: float) -> void:
		clock += dt
	func draw(ci: CanvasItem) -> void:
		ci.draw_texture_rect(IslandArt.texture(kind, str(d.get("pose", "idle")), int(clock*5), int(d.get("variant", 0))), Rect2(rect), false)


# A cooled-rock plug over a vent. Broken plugs are rubble on intact ground.
# A cracked ceiling strip: every d.every seconds a rock (8x8) shakes loose at a random spot along it (dust for
# WARN seconds first), falls, kills on contact and breaks on the ground. Never two rocks in the same column at once.
class RockFall extends Ent:
	func describe() -> String:
		return "Falling rocks: one every %.1f s at a random spot; dust shows where, %.1f s before it drops" % [float(d.get("every", 1.4)), WARN]
	const ROCK := 8
	const WARN := 0.6
	const G := 300.0
	const MAX_FALL := 200.0
	var timer := 0.0
	var rocks: Array = []  # [top-left, vy, warn]
	func setup() -> void:
		timer = float(d.get("every", 1.4))
	func update(dt: float) -> void:
		if w == null:
			return
		timer -= dt
		if timer <= 0:
			timer = float(d.get("every", 1.4))
			for tries in 10:
				var x := float(randi_range(rect.position.x, rect.end.x - ROCK))
				if rocks.all(func(k): return absf(k[0].x - x) >= ROCK):
					rocks.append([Vector2(x, rect.position.y), 0.0, WARN])
					break
		for i in range(rocks.size() - 1, -1, -1):
			var k: Array = rocks[i]
			if k[2] > 0:
				k[2] -= dt
				continue
			k[1] = minf(k[1] + G * dt, MAX_FALL)
			k[0].y += k[1] * dt
			var box := Rect2i(Vector2i(k[0]), Vector2i(ROCK, ROCK))
			if not w.player.dead and box.intersects(w.player.damage_rect()):
				w.player.die(Vector2.DOWN)
			elif w.collide_solid(box) == null and k[0].y < w.gh * T + 32:
				continue
			w.burst(Vector2(box.get_center()), Color("8a8478"), 6)
			rocks.remove_at(i)
	func damage_boxes() -> Array:
		return rocks.filter(func(k): return k[2] <= 0).map(func(k): return Rect2i(Vector2i(k[0]), Vector2i(ROCK, ROCK)))
	func vis_rect() -> Rect2i:
		return Rect2i(rect.position, Vector2i(rect.size.x, maxi(rect.size.y, (w.gh * T if w != null else 0) - rect.position.y)))
	func draw(ci: CanvasItem) -> void:
		if w == null:  # editor: the strip
			ci.draw_rect(Rect2(rect), Color(0.54, 0.52, 0.47, 0.4))
			return
		for k in rocks:
			var at: Vector2 = k[0]
			if k[2] > 0:  # dust and a shaking rock in the crack
				at.x += sin(k[2] * 70.0)
				ci.draw_rect(Rect2(at + Vector2(1, -1), Vector2(1, 1)), Color(0.8, 0.75, 0.65, 0.8))
				ci.draw_rect(Rect2(at + Vector2(6, -2), Vector2(1, 1)), Color(0.8, 0.75, 0.65, 0.8))
			ci.draw_rect(Rect2(at + Vector2(1, 0), Vector2(6, 8)), Color("8a8478"))
			ci.draw_rect(Rect2(at + Vector2(0, 1), Vector2(8, 6)), Color("8a8478"))
			ci.draw_rect(Rect2(at + Vector2(2, 2), Vector2(3, 2)), Color("b0aa9c"))


class VentPlug extends Ent:
	func describe() -> String:
		return "Vent plug: broken (rubble)" if broken else "Vent plug: bait an eruption onto it to hurt the Guardian"
	var broken := false
	func draw(ci: CanvasItem) -> void:
		ci.draw_texture_rect(IslandArt.texture("vent", "broken" if broken else "idle"), Rect2(rect), false)


# The volcanic guardian: a coiled serpent in the chamber's ceiling. It marks the ground under the player (glowing cracks),
# then erupts there: a column of fire up from that surface (ERUPT_W x ERUPT_H px). An eruption that covers a vent
# plug breaks it and hurts the guardian; when every plug is broken it is beaten (saved like the Ape, so the
# boss gates open and the room's "after" variant loads). The warning shortens as plugs break. The body is out of
# reach: only the eruptions hurt. d.door: a house door spawned on victory (the shortcut home).
class Guardian extends Ent:
	const PHASE_HELP := {"sleep": "asleep until you come in", "idle": "pausing before the next eruption",
		"warn": "the glowing cracks mark where it erupts: leave them", "erupt": "fire column: deadly", "hurt": "a plug broke under it: reeling",
		"dying": "beaten", "gone": "beaten"}
	func describe() -> String:
		return "Guardian (%d plugs left) - %s: %s" % [plugs().size() if w != null else 0, phase, PHASE_HELP.get(phase, "")]
	const ERUPT_W := 24
	const ERUPT_H := 32
	const WARN := [1.0, 0.85, 0.7]  # telegraph per plug broken so far
	const ERUPT_TIME := 0.35
	const PAUSE := 1.0
	var phase := "sleep"  # sleep, idle, warn, erupt, hurt, dying, gone
	var timer := 0.0
	var target := Vector2.ZERO  # eruption base: centre x, surface y
	var flash := 0.0
	var stage := 0
	var id := ""
	# Initialize Guardian dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		id = "guardian_%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
			if w.broken.has(id):
				phase = "gone"
				_spawn_door()
	func plugs() -> Array:
		return w.ents.filter(func(e): return e is VentPlug and not e.broken)
	# The eruption's hitbox: up from the marked surface, plus the surface row itself (where the plugs are).
	func erupt_rect() -> Rect2i:
		return Rect2i(int(target.x) - ERUPT_W / 2, int(target.y) - ERUPT_H, ERUPT_W, ERUPT_H + T)
	# The first tile or jump-through top at or under the player's feet.
	func _surface_under(p) -> Vector2:
		var x := int(p.center().x)
		var y := (int(p.pos.y) / T) * T
		while y < w.gh * T:
			var cell := Rect2i(x - 1, y, 2, T)
			if w.collide_solid(cell) != null or w.collide_jumpthru(cell) != null:
				return Vector2(x, y)
			y += T
		return Vector2(x, w.gh * T)
	func damage_boxes() -> Array:
		return [erupt_rect()] if phase == "erupt" else []
	# Advance the attack cycle: wake when the player is in the chamber, then warn, erupt, pause.
	func update(dt: float) -> void:
		flash = maxf(0.0, flash - dt)
		if phase == "gone":
			return
		timer -= dt
		var p = w.player
		match phase:
			"sleep":
				if p.hitbox().position.x > 2 * T:  # inside, past the entrance gate
					Game.play_sfx("ape_scream", 0.5)
					w.shake_dir(Vector2.ZERO, 0.3)
					_go("idle", PAUSE)
			"idle":
				if timer <= 0 and not p.dead:
					target = _surface_under(p)
					_go("warn", WARN[mini(stage, WARN.size() - 1)])
			"warn":
				if timer <= 0:
					Game.play_sfx("impact")
					w.shake_dir(Vector2.UP, 0.15)
					w.burst(target, Color("ff9a3a"), 12)
					_go("erupt", ERUPT_TIME)
					for e in plugs():
						if e.rect.intersects(erupt_rect()):
							e.broken = true
							_hurt()
							break
			"erupt":
				if not p.dead and erupt_rect().intersects(p.damage_rect()):
					p.die(Vector2.UP)
				if timer <= 0:
					if plugs().is_empty():
						_go("dying", 1.5)
					else:
						_go("hurt" if flash > 0 else "idle", 0.5 if flash > 0 else PAUSE)
			"hurt":
				if timer <= 0:
					_go("idle", PAUSE * 0.6)
			"dying":
				if timer <= 0:
					_beaten()
	func _go(ph: String, t: float) -> void:
		phase = ph
		timer = t
	# A broken plug vents into the guardian; the eruption still finishes, then it reels (or, the last plug, dies).
	func _hurt() -> void:
		stage += 1
		flash = 0.8
		Game.play_sfx("enemy_hit", 0.6)
		w.burst(center(), Color("ff6040"), 16)
	func _beaten() -> void:
		Game.play_sfx("complete")
		phase = "gone"
		w.break_wall(id)
		w.shake_dir(Vector2.ZERO, 0.4)
		_spawn_door()
	func _spawn_door() -> void:
		if w != null and d.has("door") and not w.ents.any(func(e): return e.d.get("id", "") == d.door.id and e.d.t == "house_door"):
			w.spawn_entity(d.door)
	func vis_rect() -> Rect2i:
		return rect.grow(600)
	# Draw Guardian at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		var a := 1.0 if phase != "dying" else clampf(timer / 1.5, 0.2, 1.0)
		if phase == "gone": a = 0.35
		var pose := "idle"
		if phase == "warn": pose = "warn"
		elif phase == "erupt": pose = "attack"
		elif phase in ["dying", "gone"]: pose = "defeat"
		elif phase == "hurt" or flash > 0: pose = "hurt"
		var frame := int(Time.get_ticks_msec()/150) if w != null else 0
		ci.draw_texture_rect(IslandArt.texture("serpent",pose,frame),r,false,Color(1,1,1,a))
		if w == null: return
		if phase == "warn":
			ci.draw_texture_rect(IslandArt.texture("rock_warning","idle",frame),Rect2(target-Vector2(12,8),Vector2(24,8)),false)
		elif phase == "erupt":
			ci.draw_texture_rect(IslandArt.texture("eruption","idle",frame),Rect2(erupt_rect()),false)


# Walks the player in for a moment (the arena's entrance), using Celeste's forced movement. Once per visit.
# One-use trigger that briefly forces horizontal movement, usually to walk into the boss arena.
class CameraZone extends Ent:
	# The point the view centres on while the player is inside.
	func focus() -> Vector2:
		return Vector2(float(d.focus[0]), float(d.focus[1])) if d.has("focus") else Vector2(rect.get_center())
	func describe() -> String:
		return "Camera zone: the view stays fixed on %s while you are inside" % focus()
	# Editor only: a dashed frame and its focus point; invisible in the game.
	func draw(ci: CanvasItem) -> void:
		if w != null:
			return
		var r := Rect2(rect)
		var c := Color(0.75, 0.63, 1.0)
		ci.draw_rect(r, Color(c, 0.12))
		for x in range(int(r.position.x), int(r.end.x), 6):
			ci.draw_line(Vector2(x, r.position.y), Vector2(minf(x + 3, r.end.x), r.position.y), c, 1.0)
			ci.draw_line(Vector2(x, r.end.y), Vector2(minf(x + 3, r.end.x), r.end.y), c, 1.0)
		var f := focus()
		ci.draw_line(f - Vector2(4, 0), f + Vector2(4, 0), c, 1.0)
		ci.draw_line(f - Vector2(0, 4), f + Vector2(0, 4), c, 1.0)


class AutoWalk extends Ent:
	var used := false
	# Apply AutoWalk interaction when World reports an overlapping player.
	func touch(p) -> void:
		if used or (d.get("while_boss", false) and not Ape.alive_in(w)):
			return
		used = true
		w.walk_dir = 0  # takes over from a room change's short walk-in, which would otherwise cut it short
		p.force_move_x = int(d.get("dir", 1))
		p.force_move_x_timer = float(d.get("time", 0.6))
	# Draw AutoWalk at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		if w == null:  # editor only: a dashed arrow
			var r := Rect2(rect)
			ci.draw_rect(r, Color(0.6, 0.8, 1, 0.25))
			var y := r.position.y + r.size.y / 2.0
			ci.draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y), Color(0.6, 0.8, 1), 1.0)


# The Ape: wakes when the player comes near, then picks its attack by distance. Far: a stone thrown in an
# arc. Mid: a leap that lands a bit past the player (standing still gets you hit by the arc; moving towards
# it is safe). Near: a scream around its body. A player beyond its leaps' reach always gets a leap (which
# stops at the range's edge). Its leaps stay inside d.range ([x0, x1] px); once the arena's
# trunk is down, inside d.range2, and it leaps there first if it's outside. A stone or a leap that meets
# the standing trunk fells it. Landing on spikes is a hit: it screams, leaps again, the spikes in its range
# crumble and the next patch appears (d.spikes, one list per hit: [x, y, count] in px; author them on the
# other side). Four hits (HP) beat it: the exits open, the
# an stamina orb appears (d.orb).
# Arena boss: choose a stone throw, leap/slam or scream according to player distance and fight state.
class Ape extends Ent:
	const PHASE_HELP := {"sleep": "asleep; wakes when you come near", "idle": "pausing before its next attack",
		"throw": "about to throw a stone at you", "crouch": "winding up a leap: it lands past you", "air": "leaping; the landing shockwave hurts",
		"scream": "screaming: the circle around it is deadly", "hurt": "landed on spikes: hurt", "dying": "beaten", "gone": "gone",
		"wait": "waiting out of sight", "off": "not here yet", "roar": "roaring before the chase", "chase": "chasing: if it passes you, you die"}
	func describe() -> String:
		return "%s - %s: %s%s" % ["Ape (chase)" if self is ApeChase else "Ape (HP %d)" % hp, phase, PHASE_HELP.get(phase, ""),
			" (enraged)" if not self is ApeChase and enraged() and phase != "gone" else ""]
	const HP := 4
	const SIZE := 32
	const BODY := 24  # contact box: one square, a bit larger than the 22px body bands it replaced
	const LEAP_G := 600.0
	const LEAP_TIME := 0.75
	const OVERSHOOT := 24.0  # the slam lands this far past the player
	const STONE_G := 400.0
	const STONE := 16  # stone size = its hitbox
	const SCREAM_REACH := 24  # 3 units around the body
	const SLAM_REACH := 14  # landing shockwave (60 px wide in all): this far out on both sides, along the ground
	const SLAM_HEIGHT := 8
	const SLAM_TIME := 0.2
	const THROW_CHANCE := 0.2  # each attack: a stone throw at random; otherwise distance picks scream or leap
	const VOLLEY := 3  # a cornered player: the Ape leaps to the far side and throws this many stones...
	const VOLLEY_GAP := 0.35  # ...this far apart (a single throw winds up 0.7 s)
	const NEAR := 44.0
	const WAKE := 220.0
	const PAUSE := 0.765  # idle waits between attacks are scaled by this (0.85, then 10% less)
	const ENRAGED_HP := HP - 2  # from 2 hits on: stones split, screams add 2 hops in place
	const HOP_SCALE := [1.7, 1.3]  # shockwave width of the 2nd and 1st hop (indexed by hops left)
	const LOG := Vector2i(19, 6)  # 20% smaller than the first 24x8
	const LOG_G := 200.0  # logs fall at half the stones' gravity
	const LOG_MAX_FALL := 140.0
	const LOG_WAIT := 0.4  # the log shakes at the top this long before it drops
	var hp := HP
	var phase := "sleep"  # sleep, idle, throw, crouch, air, scream, hurt, dying, gone
	var timer := 0.0
	var vel := Vector2.ZERO
	var facing := -1
	var stage := 0
	var then_slam := false
	var hops := 0  # in-place hops still to do after an enraged scream
	var retreat := false  # this leap goes away from a cornered player, then a volley follows
	var volley := 0  # stones still to throw in a volley
	var throw_chance := THROW_CHANCE  # tests pin it to 0 or 1
	var slam_scale := 1.0
	var logs: Array = []  # [top-left, vy, wait]
	var stones: Array = []  # [centre, velocity, size]
	var flash := 0.0
	var clock := 0.0
	var slam_t := 0.0  # the landing shockwave is live while > 0
	var id := ""
	var x_min := 0.0
	var x_max := 0.0
	var restored := false  # aftermath (kept spikes, orb) applied after a respawn
	# True while the room has an Ape that isn't beaten (gates and the entrance walk follow it).
	# Find whether this room still contains an undefeated arena Ape, excluding the chase version.
	static func alive_in(world) -> bool:
		for e in world.ents:
			if ((e is Ape and not e is ApeChase) or e is Guardian) and e.phase != "gone":
				return true
		return false
	# Report whether Ape currently participates in lethal contact checks.
	func hurts() -> bool:
		return phase != "gone" and phase != "dying"
	# Initialize Ape dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		rect.size = Vector2i(SIZE, SIZE)
		var r: Array = d.get("range", [rect.position.x - 200, rect.end.x + 200])
		x_min = float(r[0])
		x_max = float(r[1])
		id = "ape_%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
			if w.broken.has(id):
				phase = "gone"
				collidable = false
	# [x0, x1] the leaps stay in: d.range, or d.range2 once the arena's trunk is down.
	# Choose the current permitted landing range, accounting for the arena trunk state.
	func leap_range() -> Vector2:
		var t = trunk()
		var r: Array = d.get("range2", []) if t != null and t.down() and d.has("range2") else [x_min, x_max]
		return Vector2(float(r[0]), float(r[1]))
	# Find the arena tree object needed for boss targeting and bridge interactions.
	func trunk():
		for e in w.ents:
			if e is ApeTrunk:
				return e
		return null
	# The movement footprint stays 32px; contact damage uses one centred 24px square.
	# Return the pixel rectangle that activates Ape contact, separate from artwork bounds.
	func touch_rect() -> Rect2i:
		return Rect2i(rect.position + Vector2i((SIZE - BODY) / 2, (SIZE - BODY) / 2), Vector2i(BODY, BODY))
	# Expose body-contact boxes for both gameplay checks and the hitbox overlay.
	func body_boxes() -> Array:
		return [touch_rect()]
	# Check whether any boss body-contact box overlaps the supplied player damage rectangle.
	func body_hits(area: Rect2i) -> bool:
		for box in body_boxes():
			if box.intersects(area): return true
		return false
	# Return the circular range of the boss scream in world pixels.
	func scream_radius() -> float:
		return SIZE / 2.0 + SCREAM_REACH
	# Measure the nearest point of a rectangle against the circular scream, avoiding square-corner false hits.
	func scream_hits(area: Rect2i) -> bool:
		var c := center()
		var nearest := c.clamp(Vector2(area.position),Vector2(area.end))
		return area.has_area() and c.distance_squared_to(nearest) < scream_radius() * scream_radius()
	# Expose active circular hazards; an empty list means no circular damage is active.
	func damage_circles() -> Array:
		return [[center(),scream_radius()]] if phase == "scream" and timer <= 0.0 and timer > -0.35 else []
	# Apply Ape interaction when World reports an overlapping player.
	func touch(p) -> void:
		if hurts() and body_hits(p.damage_rect()):
			p.die((p.center() - center()).normalized())
	# Advance boss timers, stones and phases; select attacks by distance and test circular scream damage only in its active window.
	func update(dt: float) -> void:
		clock += dt
		flash = maxf(0.0, flash - dt)
		_update_stones(dt)
		_update_logs(dt)
		if phase == "gone":
			if not restored and w.kept_spikes.has(w.room):
				_restore_aftermath()
			return
		if slam_t > 0:
			slam_t -= dt
			if not w.player.dead and slam_box().intersects(w.player.damage_rect()):
				w.player.die(Vector2(signf(w.player.center().x - center().x), -1).normalized())
		var p = w.player
		var dx: float = p.center().x - center().x
		var dist: float = p.center().distance_to(center())  # attack choice is radial; dx only picks the side
		if phase in ["idle", "throw", "crouch", "scream"]:
			facing = 1 if dx > 0 else -1
		timer -= dt
		match phase:
			"sleep":
				if dist < WAKE:
					_go("scream", 0.5)  # the fight opens with a scream
			"idle":
				if timer <= 0:
					var r := leap_range()
					if center().x < r.x or center().x > r.y:  # outside its range (the trunk just fell): leap there
						_go("crouch", 0.45)
					elif p.center().x < r.x or p.center().x > r.y:  # player out of its reach (past the trunk): leap at them
						_go("crouch", 0.45)
					elif randf() < throw_chance:
						_go("throw", 0.7)
					elif absf(p.center().y - center().y) > absf(dx):  # player above or below (steeper than 45 degrees): leap
						_go("crouch", 0.45)
					elif _cornered(p):  # the player is pinned against a wall: leap away to the far side, then 3 stones
						retreat = true
						_go("crouch", 0.45)
					elif dist > NEAR:
						_go("crouch", 0.45)
					else:
						_go("scream", 0.5)
			"throw":
				if timer <= 0:
					_throw(p.center())
					volley = maxi(0, volley - 1)
					if volley > 0:
						_go("throw", VOLLEY_GAP)
					else:
						_go("idle", 1.0 * PAUSE)
			"crouch":
				if timer <= 0:
					var side := 1.0 if dx > 0 else -1.0
					var r := leap_range()
					var tx := clampf(p.center().x + side * OVERSHOOT, r.x + SIZE / 2.0, r.y - SIZE / 2.0)
					if retreat:  # to the end of its range away from the player
						tx = r.x + SIZE / 2.0 if side > 0 else r.y - SIZE / 2.0
					slam_scale = 1.0
					if hops > 0:  # enraged: hop straight up and down where it stands, a wider shockwave each time
						tx = center().x
						slam_scale = HOP_SCALE[hops - 1]
						hops -= 1
					vel = Vector2((tx - center().x) / LEAP_TIME, -0.5 * LEAP_G * LEAP_TIME)
					phase = "air"
			"air":
				vel.y += LEAP_G * dt
				_move(dt)
				var t = trunk()
				if t != null and not t.down() and not t.falling and rect.intersects(t.standing):
					t.fell()  # crashed into the standing trunk
			"scream":
				if timer <= 0.0 and timer > -0.35:  # the scream itself, after the 0.5 s wind-up
					if not p.dead and scream_hits(p.damage_rect()):
						p.die((p.center() - center()).normalized())
				elif timer <= -0.35:
					if enraged():
						then_slam = false
						hops = 2
						_go("crouch", 0.3)
					elif then_slam:
						then_slam = false
						_go("crouch", 0.3)
					else:
						_go("idle", 0.8 * PAUSE)
			"hurt":
				if timer <= 0:
					then_slam = true
					_go("scream", 0.3)
			"dying":
				if timer <= 0:
					_beaten()
	# The player is between the Ape and a wall, and the scream would cover all the floor up to that wall: no way to
	# dodge it, so it leaps instead.
	func _cornered(p) -> bool:
		var side := signf(p.center().x - center().x)
		var c := center()
		var x := c.x
		while absf(x - c.x) <= scream_radius() and w.collide_solid(Rect2i(int(x), int(c.y), 1, 1)) == null:
			x += side
		return absf(x - c.x) <= scream_radius()

	# Change the boss phase and set its duration, emitting the appropriate one-time attack cue.
	func _go(ph: String, t: float) -> void:
		if ph == "scream":
			Game.play_sfx("ape_scream")
		elif ph == "hurt" or ph == "dying":
			Game.play_sfx("enemy_hit", 0.6)
		phase = ph
		timer = t
	# Create a ballistic stone velocity aimed toward a target, including gravity over its planned flight time.
	func _throw(target: Vector2) -> void:
		Game.play_sfx("projectile", 0.6)
		var from := Vector2(center().x + facing * 10, rect.position.y)
		var t := clampf(absf(target.x - from.x) / 220.0, 0.7, 1.3)
		stones.append([from, Vector2((target.x - from.x) / t, (target.y - from.y) / t - 0.5 * STONE_G * t), STONE])
	# Resolve boss displacement in whole pixels and trigger the landing reaction on downward impact.
	func _move(dt: float) -> void:
		rem += vel * dt  # whole pixels move, the rest carries over (Ent.rem)
		var step := rem.round()
		rem -= step
		var r := Rect2i(rect)
		r.position.x += int(step.x)
		if w.collide_solid(r) == null:
			rect.position.x = r.position.x
		r = Rect2i(rect)
		r.position.y += int(step.y)
		if w.collide_solid(r) == null:
			rect.position.y = r.position.y
		elif vel.y > 0:
			while w.collide_solid(Rect2i(rect.position + Vector2i(0, 1), rect.size)) == null:
				rect.position.y += 1
			_land()
		else:
			vel.y = 0
	# Expose active rectangular damage regions to the hitbox overlay and shared inspection tools.
	func damage_boxes() -> Array:  # stones, and the scream and the landing shockwave while they're live
		var out := []
		for s in stones:
			out.append(Rect2i(Vector2i(s[0]) - Vector2i(s[2] / 2, s[2] / 2), Vector2i(s[2], s[2])))
		for l in logs:
			out.append(Rect2i(Vector2i(l[0]), LOG))
		if slam_t > 0:
			out.append(slam_box())
		return out
	# The landing shockwave along the ground, both sides of the body.
	# Return the ground-level shockwave rectangle used by both damage and its visual overlay.
	func slam_box() -> Rect2i:
		var wide := roundi((SIZE + 2 * SLAM_REACH) * slam_scale)
		return Rect2i(rect.position.x + (SIZE - wide) / 2, rect.end.y - SLAM_HEIGHT, wide, SLAM_HEIGHT)
	# Stop the leap, create the shockwave and check whether the landing feet overlap an arena spike patch.
	func _land() -> void:
		Game.play_sfx("impact")
		vel = Vector2.ZERO
		slam_t = SLAM_TIME
		w.shake_dir(Vector2.DOWN, 0.2)
		w.dust(Vector2(center().x, rect.end.y), Vector2.UP, 10)
		var feet := Rect2i(rect.position.x, rect.end.y - 4, rect.size.x, 4)
		for e in w.touchables:
			if e is Spikes and e.collidable and e.rect.intersects(feet):
				_hit()
				return
		_drop_log()  # every landing shakes one log loose, the hops in place too
		if hops > 0:
			_go("crouch", 0.25)
		elif retreat:  # landed away from a cornered player: a volley of 3 stones
			retreat = false
			volley = VOLLEY
			_go("throw", VOLLEY_GAP)
		else:
			_go("idle", 0.6 * PAUSE)
	# Remove boss health, select the hurt/dying phase and reveal the next arena hazards when applicable.
	func _hit() -> void:
		hp -= 1
		hops = 0
		retreat = false
		volley = 0
		var feet := Rect2i(rect.position.x, rect.end.y - 4, rect.size.x, 4)
		flash = 0.8
		w.burst(center(), Color("ff6040"), 14)
		if hp <= 0:
			_go("dying", 1.2)
			return
		stage += 1
		for e in w.touchables:  # only the spikes it landed on break under it
			if e is Spikes and e.dir == "up" and e.collidable and e.rect.intersects(feet):
				e.collidable = false
				w.burst(Vector2(e.rect.get_center()), Color("e8e8f0"), 3)
		_go("hurt", 0.8)
	# Record permanent boss defeat, release the arena and spawn the configured reward.
	func _beaten() -> void:
		Game.play_sfx("complete")
		phase = "gone"
		collidable = false
		restored = true
		var kept := []  # the spikes as the fight left them: a death before leaving the room keeps them
		for e in w.touchables:
			if e is Spikes and e.collidable:
				kept.append([e.d.t, int(e.d.x), int(e.d.y)])
		w.kept_spikes[w.room] = kept
		w.break_wall(id)
		w.shake_dir(Vector2.ZERO, 0.4)
		if d.has("orb"):
			w.spawn_entity({"t": "stamina_orb", "x": int(d.orb[0]), "y": int(d.orb[1])})
	# Rebuilt after a death in the room it was beaten in: the spikes go back to how the fight left them, the orb too.
	func _restore_aftermath() -> void:
		restored = true
		var kept: Array = w.kept_spikes[w.room]
		var have := {}
		for e in w.touchables:
			if e is Spikes:
				var k := [e.d.t, int(e.d.x), int(e.d.y)]
				e.collidable = kept.has(k)
				have[str(k)] = true
		for k in kept:
			if not have.has(str(k)):
				w.spawn_entity({"t": k[0], "x": k[1], "y": k[2]})
		if d.has("orb"):
			w.spawn_entity({"t": "stamina_orb", "x": int(d.orb[0]), "y": int(d.orb[1])})
	# Hitbox overlay (F2): how it picks its attack, by the straight-line distance from its centre to the player's.
	func _draw_ranges(ci: CanvasItem) -> void:
		var c := center()
		var font := ThemeDB.fallback_font
		for b in [[NEAR, "scream (else leap; 20% throw)", Color(1, 0.35, 0.3)], [WAKE, "wake", Color(0.4, 0.75, 1)]]:
			ci.draw_arc(c, b[0], 0.0, TAU, 96, Color(b[2], 0.7), 1.0)
			ci.draw_string(font, c + Vector2(-12.0, -b[0] + 7.0), "%s %d" % [b[1], b[0]], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, b[2])
		for d in [Vector2(1, 1), Vector2(-1, 1)]:  # above/below these diagonals it always leaps
			ci.draw_line(c - d * WAKE, c + d * WAKE, Color(1, 0.8, 0.3, 0.5), 1.0)
	# From 2 hits on.
	func enraged() -> bool:
		return hp <= ENRAGED_HP
	# A gentle red light pulse marks phase two while preserving the original sprites.
	func sprite_tint() -> Color:
		var alpha := clampf(timer / 1.2, 0.0, 1.0) if phase == "dying" else 1.0
		var tint := Color(1, 1, 1, alpha)
		if not self is ApeChase and enraged() and phase not in ["dying", "gone"]:
			var pulse := (sin(clock * TAU * 2.0) + 1.0) * 0.5
			tint = tint.lerp(Color(1.5, 0.28, 0.22, alpha), pulse)
		if flash > 0 and int(flash * 20) % 2 == 0:
			tint = Color(1.8, 1.5, 1.3, alpha)
		return tint
	# A log shakes loose from the ceiling at a random spot across the arena, never overlapping a log still falling.
	func _drop_log() -> void:
		var r := leap_range()
		var lx := NAN
		var spikes: Array = w.touchables.filter(func(e): return e is Spikes and e.collidable)
		var pr: Rect2i = w.player.hitbox()
		for tries in 40:  # ponytail: rejection sampling, fine for an arena much wider than a log
			var x := randf_range(r.x, r.y - LOG.x)
			var span := Vector2(x, x + LOG.x)
			var clear := func(a: float, b: float) -> bool: return b <= span.x or a >= span.y
			if logs.all(func(l): return absf(l[0].x - x) >= LOG.x) and clear.call(pr.position.x, pr.end.x) \
					and spikes.all(func(e): return clear.call(e.rect.position.x, e.rect.end.x)):
				lx = x  # not onto another log, the player's column, or a spike already there
				break
		if is_nan(lx):
			return  # no free spot this time: no log
		var y := 0
		while y < w.gh * T and w.collide_solid(Rect2i(int(lx), y, LOG.x, LOG.y)) != null:
			y += T
		logs.append([Vector2(lx, y), 0.0, LOG_WAIT])
	# Where a log breaks on the ground it leaves a 1-tile spike (the only spikes the fight makes).
	func _log_spike(box: Rect2i) -> void:
		var tx := int(box.get_center().x) / T
		var ty := (box.end.y - 1) / T  # the ground row the log broke on
		var cell := Rect2i(tx * T, (ty - 1) * T, T, T)
		if not (w.collide_solid(Rect2i(tx * T, ty * T, T, T)) is String) or w.collide_solid(cell) != null:
			return  # only on open tile ground (not a gate or another block), on an empty cell
		for e in w.touchables:
			if e is Spikes and e.collidable and e.rect.intersects(cell):
				return
		w.spawn_entity({"t": "spikes_up", "x": tx * T, "y": (ty - 1) * T})
	# Logs wait, then fall; they kill on contact and break on the ground.
	func _update_logs(dt: float) -> void:
		for i in range(logs.size() - 1, -1, -1):
			var l: Array = logs[i]
			l[2] -= dt
			if l[2] > 0:
				continue
			l[1] = minf(l[1] + LOG_G * dt, LOG_MAX_FALL)
			l[0].y += l[1] * dt
			var box := Rect2i(Vector2i(l[0]), LOG)
			if not w.player.dead and box.intersects(w.player.damage_rect()):
				w.player.die(Vector2.DOWN)
			elif w.collide_solid(box) == null and l[0].y < w.gh * T + 64:
				continue
			else:
				_log_spike(box)
			w.burst(Vector2(box.get_center()), Color("6b4a2a"), 8)
			logs.remove_at(i)
	# Move thrown stones, then resolve player, trunk and solid-terrain impacts.
	func _update_stones(dt: float) -> void:
		var t = trunk() if w != null else null
		for i in range(stones.size() - 1, -1, -1):
			var s: Array = stones[i]
			s[1].y += STONE_G * dt
			s[0] += s[1] * dt
			var box := Rect2i(Vector2i(s[0]) - Vector2i(s[2] / 2, s[2] / 2), Vector2i(s[2], s[2]))
			var gone := false
			if not w.player.dead and box.intersects(w.player.damage_rect()):
				w.player.die(s[1].normalized())
				gone = true
			elif t != null and not t.down() and not t.falling and box.intersects(t.standing):
				t.fell()
				gone = true
			elif w.collide_solid(box) != null or s[0].y > w.gh * T + 64:
				gone = true
				if s[2] == STONE and enraged() and s[1].y > 0:  # enraged: the stone splits in two on the ground
					var back: Vector2 = s[0] - s[1] * dt
					for side in [-1.0, 1.0]:
						stones.append([back + Vector2(side * 4, -4), Vector2(side * 90.0, -150.0), STONE / 2])
			if gone:
				w.burst(s[0], Color("9a9080"), 8)
				stones.remove_at(i)
	# Return conservative visible bounds including Ape effects so camera culling does not hide them.
	func vis_rect() -> Rect2i:
		return rect.grow(400)
	# Draw Ape at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		for s in stones:  # preserve the original Ape projectile artwork
			var k: float = s[2] / 16.0
			var at: Vector2 = s[0] - Vector2(s[2] / 2.0, s[2] / 2.0)
			ci.draw_rect(Rect2(at + Vector2(2, 0) * k, Vector2(12, 16) * k), Color("8a8478"))
			ci.draw_rect(Rect2(at + Vector2(0, 2) * k, Vector2(16, 12) * k), Color("8a8478"))
			ci.draw_rect(Rect2(at + Vector2(3, 3) * k, Vector2(5, 3) * k), Color("b0aa9c"))
		for l in logs:  # logs: exactly their hitbox, shaking at the top before they drop
			var at: Vector2 = l[0] + (Vector2(sin(clock * 60.0), 0) if l[2] > 0 else Vector2.ZERO)
			ci.draw_rect(Rect2(at, Vector2(LOG)), Color("6b4a2a"))
			ci.draw_rect(Rect2(at + Vector2(1, 1), Vector2(LOG.x - 2, 2)), Color("8c6a40"))
			ci.draw_rect(Rect2(at + Vector2(LOG.x - 4, 2), Vector2(3, LOG.y - 3)), Color("c9a46a"))
		if phase == "gone":
			return
		if w != null and Game.settings.hitboxes and not self is ApeChase:
			_draw_ranges(ci)
		var pose := phase
		if phase in ["chase", "running"]:
			pose = "run"
		elif phase == "roar":
			pose = "scream"
		elif phase == "crouch" and timer < 0.12:
			pose = "launch"
		if slam_t > 0 and phase not in ["hurt", "dying"]:
			pose = "land"
		var art = load("res://scripts/ape_art.gd")
		if phase == "air" and slam_t <= 0:
			pose = art.jump_pose(vel.y)
		var o := Vector2(rect.position)
		ci.draw_set_transform(o + Vector2(SIZE / 2.0, 0), 0.0, Vector2(facing, 1))
		ci.draw_texture_rect(art.texture(pose, int(clock * 10.0)), Rect2(-SIZE / 2.0, 0, SIZE, SIZE), false, sprite_tint())
		if phase == "throw":
			ci.draw_rect(Rect2(3, -5, 8, 6), Color("8a8478"))
			ci.draw_rect(Rect2(4, -4, 4, 2), Color("b0aa9c"))
		ci.draw_set_transform(Vector2.ZERO)
		if slam_t > 0:  # textured impact stays inside the unchanged damage bounds
			var sb := Rect2(slam_box())
			var impact_frame := clampi(int((1.0 - slam_t / SLAM_TIME) * 4.0), 0, 3)
			ci.draw_texture_rect(art.impact_texture(int(sb.size.x), int(sb.size.y), impact_frame), sb, false)
		if phase == "scream" and timer <= 0.0 and timer > -0.35:  # the scream's reach
			var c := center()
			for k in 3:
				ci.draw_arc(c, minf(scream_radius(), scream_radius() * (k + 1) / 3.0 + fmod(clock * 30.0, 6.0)), 0, TAU, 24, Color(1, 0.9, 0.7, 0.5 - k * 0.12), 2.0)
		elif phase == "scream":  # wind-up warning
			ci.draw_arc(center(), SIZE / 2.0 + SCREAM_REACH, 0, TAU, 24, Color(1, 0.4, 0.3, 0.35), 1.0)


# The Ape after its defeat, chasing the player up the sand cave. It moves by the player's rules along one fixed,
# known-good path that never touches breakable blocks (they are empty to the planner, so it jumps clear over them): when the room loads, plan() simulates the player's movement code (ChaseRunner) running right
# and searches, jump by jump, for a take-off distance that clears every step and pit without touching spikes.
# The Ape only ever replays that run, one recorded frame per tick, so it can't miss a jump. Touching it is a death;
# dying rebuilds the room, which puts it back to waiting. Once the player passes x "end" it gives up for the run.
# Story chase using a preplanned sequence of feet positions; the route is simulated before replay.
# Planning is a hypothetical run; replay advances through its recorded positions during the real chase.
# The cache key must include route inputs, because an edited level can share the same room/spawn name.
class ApeChase extends Ape:
	const ROAR_TIME := 1.0  # it screams this long before giving chase
	const SEAL_TIME := 0.4  # the cave-in rock takes this long to drop
	const PLAN_BUDGET_MS := 1500  # give up after this much planning work (an edited room with no route); generous: the web build runs the planner several times slower (Sand Cave: ~90 ms native)
	const PLAN_SLICE_MS := 3.0  # planning work per frame while waiting
	static var _plans := {}  # hash of planner inputs -> PackedVector2Array of feet positions, one per tick
	var path := PackedVector2Array()
	var at := 0.0  # index into path
	var seal_t := -1.0  # cave-in drop time; < 0 when not dropping
	var sealed := false
	var debris: Array = []  # [pos, vy]: cosmetic grit shaken off the ceiling by its landings
	var planner: ChasePlan
	var plan_key := 0
	# Initialize ApeChase dimensions, collision flags and starting data before World uses the object.
	func setup() -> void:
		super.setup()
		if phase != "gone":
			phase = "wait"
			if w != null and d.has("after") and not w.broken.has(str(d.after)):
				phase = "off"  # d.after: only once that boss is beaten (the Ape follows you out of its arena)
		elif w != null:
			_seal()  # it gave up earlier this run: the cave-in stays
	# d.dir: 1 chases rightward (default), -1 leftward; trigger and end are then crossed going left.
	func dir() -> int:
		return int(d.get("dir", 1))
	# d.seal = [x, y, w, h] px: the rock that falls in front of the Ape when it reaches d.end, stopping it and blocking the way back for good
	# (saved with the Ape's own "gone" flag). A resting falling block: solid, same art.
	# Queue the persistent cave-in block once; World creates it after the current object-update iteration.
	func _seal() -> void:
		if d.has("seal") and not sealed:
			sealed = true
			var s: Array = d.seal
			w.spawn_entity({"t": "falling", "x": int(s[0]), "y": int(s[1]), "w": int(s[2]), "h": int(s[3]), "art": "breakwall"})
	# No body contact: the chase kills through its full-height line instead (update()).
	func hurts() -> bool:
		return false
	func touch(_p) -> void:
		pass
	# The kill line: tunnel-high, at the Ape's centre. Once the Ape is past the player, it caught them.
	func caught(p) -> bool:
		return phase == "chase" and (p.center().x - center().x) * dir() < 0
	# Advance trigger, roar and chase replay. Cache routes by their simulation inputs and end the chase after the exit threshold.
	func update(dt: float) -> void:
		clock += dt
		flash = maxf(0.0, flash - dt)
		if seal_t >= 0:
			seal_t += dt
			var s: Array = d.seal
			if seal_t >= SEAL_TIME and not Rect2i(int(s[0]), int(s[1]), int(s[2]), int(s[3])).intersects(w.player.hitbox()):
				seal_t = -1.0
				_seal()
				w.shake_dir(Vector2.DOWN, 0.35)
				w.burst(Vector2(s[0] + s[2] / 2.0, s[1] + s[3]), TYPES.breakwall[2], 24)
				Game.play_sfx("impact")
		_update_debris(dt)
		if phase == "gone" or phase == "off":
			return
		var p = w.player
		timer -= dt
		match phase:
			"wait":
				if planner == null:
					_start_plan()
				if not planner.done and planner.run(PLAN_SLICE_MS):  # a few ms per frame while the player approaches
					_plans[plan_key] = planner.result
				path = planner.result
				if (p.center().x - float(d.get("trigger", rect.end.x + 64))) * dir() > 0:
					if not planner.done:  # reached the trigger first: finish now (still within its budget)
						planner.run(INF)
						_plans[plan_key] = planner.result
						path = planner.result
					Game.play_sfx("ape_scream_cave")
					w.shake_dir(Vector2.ZERO, 0.3)
					facing = dir()
					phase = "roar"
					if path.is_empty():  # no route (edited room): it screams and leaves; not saved, so a fixed room chases again
						push_warning("ApeChase: no route, the Ape leaves")
						phase = "dying"
						timer = 1.2
					timer = ROAR_TIME
			"roar", "chase":
				if phase == "roar":
					if timer <= 0:
						phase = "chase"
				elif not path.is_empty():
					var was := int(at)
					at = minf(at + dt * 60.0, path.size() - 1)
					for i in range(maxi(was, 1) + 1, int(at) + 1):  # a landing (falling, then level) shakes grit loose
						if path[i - 1].y > path[i - 2].y and path[i].y == path[i - 1].y:
							_shake_ceiling()
					var f: Vector2 = path[int(at)]
					rect.position = Vector2i(roundi(f.x - SIZE / 2.0), roundi(f.y) - SIZE)
					for e in w.solids:  # rock in its way bursts; not saved, so a retry has it back
						if e is BreakWall and e.collidable and e.rect.intersects(rect.grow(2)):
							e.collidable = false
							w.burst(e.center(), TYPES.breakwall[2], 20)
							w.shake_dir(Vector2.ZERO, 0.2)
							Game.play_sfx("crumble")
							flash = 0.4  # the rock hurts it: blink, like a hit in the boss fight
							Game.play_sfx("enemy_hit", 0.6)
					if not p.dead and caught(p):
						p.die(Vector2(dir(), 0))
					if int(at) == path.size() - 1:  # reached d.end: the ceiling caves in ahead of it and it's done
						Game.play_sfx("ape_scream_cave", 0.8)
						w.break_wall(id)  # gone for the rest of the run
						phase = "dying"
						timer = 1.2
						if d.has("seal"):
							seal_t = 0.0
							Game.play_sfx("crumble")
			"dying":
				if timer <= 0:
					phase = "gone"
					collidable = false
	# Reuse a cached route, or start a sliced search. Every planner input is in the key: a changed room, world,
	# endpoint or tuning plans again.
	func _start_plan() -> void:
		var end := float(d.get("end", w.bounds.end.x if dir() > 0 else 0)) + 16.0 * dir()
		plan_key = hash([Game.world_path, w.room, w.room_origin, w.data, Game.tuning, rect.position, end, dir()])
		planner = ChasePlan.new(w, rect, end, true, PLAN_BUDGET_MS, dir())
		if _plans.has(plan_key):
			planner.done = true
			planner.result = _plans[plan_key]
		elif _plans.size() >= 16:
			_plans.clear()  # ponytail: drop all; a story has a handful of chases
	# A few bits of rock fall from the ceiling around where it landed.
	func _shake_ceiling() -> void:
		w.shake_dir(Vector2.DOWN, 0.08)
		for k in 3:
			var x := center().x + randf_range(-28.0, 40.0)
			var y := float(rect.position.y)
			var up := 0
			while up < 120 and w.collide_solid(Rect2i(int(x), int(y) - 1, 3, 1)) == null:
				y -= 1.0
				up += 1
			debris.append([Vector2(x, y), randf_range(0.0, 40.0)])
	func _update_debris(dt: float) -> void:
		for i in range(debris.size() - 1, -1, -1):
			var b: Array = debris[i]
			b[1] += 300.0 * dt
			b[0].y += b[1] * dt
			if w.collide_solid(Rect2i(Vector2i(b[0]) + Vector2i(0, 3), Vector2i(3, 1))) != null or b[0].y > w.gh * T:
				w.burst(b[0], TYPES.breakwall[2], 2)
				debris.remove_at(i)
	# Draw ApeChase at its current pose; this must also work for an editor preview with no World.
	func draw(ci: CanvasItem) -> void:
		for b in debris:
			ci.draw_rect(Rect2(Vector2(roundf(b[0].x), roundf(b[0].y)), Vector2(3, 3)), Color("8a6a44"))
		if seal_t >= 0:  # the cave-in rock dropping from the ceiling into place
			var s: Array = d.seal
			var k := minf(seal_t / SEAL_TIME, 1.0)
			BlockArt.draw(ci, Rect2i(int(s[0]), int(s[1] - s[3] * (1.0 - k * k)), int(s[2]), int(s[3])), "breakwall", Vector2.ZERO)
		if phase != "wait" and phase != "off":
			super.draw(ci)

	# Tries take-off distances (px before a wall, px past the edge of a gap) until a simulated run from the Ape's
	# spot reaches end_x without touching spikes. Returns that run's feet positions, or an empty path if none works.
	# body: also keep the Ape's BODY box out of the terrain (off for proving a player-sized route).
	# Try jump timing combinations until a simulated route reaches the endpoint safely; empty means none succeeded.
	# budget_ms: stop searching after this long (0 = no limit, for offline proofs). All at once; ChasePlan slices it.
	static func plan(world, from: Rect2i, end_x: float, body := true, budget_ms := PLAN_BUDGET_MS, dir_ := 1) -> PackedVector2Array:
		var cp := ChasePlan.new(world, from, end_x, body, budget_ms, dir_)
		cp.run(INF)
		return cp.result

	# The box, or the pixel row under it, overlaps crumble; or it stands on a breakable wall.
	# Passing through a breakable wall is fine: the chasing Ape smashes it (update()).
	# Reject route positions supported by temporary terrain the chase cannot safely rely on.
	static func _on_breakable(world, hb: Rect2i) -> bool:
		var feet := Rect2i(hb.position, hb.size + Vector2i(0, 1))
		var under := Rect2i(hb.position.x, hb.end.y, hb.size.x, 1)
		for e in world.solids:
			if (e is Crumble and e.rect.intersects(feet)) or (e is BreakWall and e.rect.intersects(under)):
				return true
		return false



# A resumable chase-route search: run(ms) advances it at most that long, so the Ape can plan a few ms per frame.
# Tries take-off distances in order; each trial runs the player's movement code (ChaseRunner) rightward and is
# rejected when it touches spikes or crumble, stands on breakable rock, clips the Ape's body (body), falls out or
# gets stuck. result holds the first full run's feet positions, one per tick.
class ChasePlan:
	const SIZE := 32
	const BODY := 24
	var world
	var from: Rect2i
	var end_x := 0.0
	var body := true
	var budget_ms := 0
	var dir := 1  # 1 runs right, -1 left
	var combos: Array = []  # [wall, gap, brk]
	var ci := -1
	var r  # current trial's runner
	var path := PackedVector2Array()
	var best := -1e9
	var still := 0
	var tick := 0
	var spent_ms := 0.0
	var max_run_ms := 0.0  # longest single run() call: the worst frame it cost
	var done := false
	var result := PackedVector2Array()
	func _init(w_, from_: Rect2i, end_x_: float, body_ := true, budget_ms_ := 0, dir_ := 1) -> void:
		world = w_
		from = from_
		end_x = end_x_
		body = body_
		budget_ms = budget_ms_
		dir = dir_
		for brk in [2, 4, 6, 8, 3, 5]:  # extra take-off margin before a breakable block
			for wall in [22, 26, 18, 30, 34, 16, 14, 12, 10, 8, 6]:  # long run-ups first: the Ape's 24px body needs them
				for gap in [1, 2, 4, 6, 8]:
					combos.append([wall, gap, brk])
		_next()
	# Start the next trial, or finish empty-handed.
	func _next() -> void:
		ci += 1
		if ci >= combos.size():
			push_warning("ApeChase: no path found to x %d" % end_x)
			done = true
			return
		r = ChaseRunner.new(ChaseWorld.new(world), Vector2.ZERO)
		r.pos = Vector2(from.position.x + SIZE / 2.0, from.end.y)
		r.pos.x -= r.hitbox().get_center().x - r.pos.x
		r.pos.y -= r.bottom() - from.end.y
		r.dir = dir
		r.wall_d = combos[ci][0]
		r.gap_d = combos[ci][1]
		r.brk_d = combos[ci][1] + combos[ci][2]
		path = PackedVector2Array()
		best = -1e9
		still = 0
		tick = 0
	# Advance for up to ms; true once finished (result set, maybe empty).
	func run(ms: float) -> bool:
		var t0 := Time.get_ticks_usec()
		while not done:
			_tick()
			var used := (Time.get_ticks_usec() - t0) / 1000.0
			if budget_ms > 0 and spent_ms + used > budget_ms:  # an impossible room: stop, don't stall the game
				push_warning("ApeChase: no path found to x %d within %d ms" % [end_x, budget_ms])
				done = true
			elif used >= ms:
				break
		var took := (Time.get_ticks_usec() - t0) / 1000.0
		spent_ms += took
		max_run_ms = maxf(max_run_ms, took)
		return done
	# One simulated tick of the current trial.
	func _tick() -> void:
		r.update(1.0 / 60.0)
		tick += 1
		var hb: Rect2i = r.hitbox()
		path.append(Vector2(hb.get_center().x, hb.end.y))
		# the Ape's own contact box (BODY px, inside its SIZE sprite) must stay out of the terrain the small runner squeezes past
		var box := Rect2i(roundi(hb.get_center().x - BODY / 2.0), hb.end.y - (SIZE + BODY) / 2, BODY, BODY)
		if world.touching_spikes(r.damage_rect()) or hb.position.y > world.bounds.end.y or ApeChase._on_breakable(world, hb) or (body and r.w.collide_solid(box) != null):
			_next()
		elif (hb.end.x >= end_x) if dir > 0 else (hb.position.x <= end_x):
			result = path
			done = true
		else:
			var ahead := float(hb.end.x if dir > 0 else -hb.position.x)
			if ahead > best:
				best = ahead
				still = 0
			else:
				still += 1
			if still > 90 or tick >= 60 * 60:  # stuck under a step it never cleared
				_next()


# The chasing Ape's body while planning: the player's movement code, always running right, jumping wall_d px
# before a wall and when the floor ends within gap_d px.
# Silent scripted Player used only for route planning, with automated run/jump input.
class ChaseRunner extends "res://scripts/player.gd":
	var dir := 1  # running right (1) or left (-1)
	var wall_d := 12.0
	var gap_d := 1.0
	var brk_d := 3.0  # take-off distance when the floor ahead is a breakable block
	var hold_jump := 0.0
	# Initialize ordinary Player movement, then silence effects for the many simulated route attempts.
	func _init(world, spawn: Vector2) -> void:
		super(world, spawn)
		quiet = true
	# Supply automated rightward movement and timed jump presses instead of reading real controls.
	func _read_input(dt: float) -> void:
		in_x = dir
		in_y = 0
		aim_raw = Vector2(in_x, 0)
		aim_free = aim_raw
		jump_buf -= dt
		dash_buf -= dt
		attack_buf -= dt
		hold_jump -= dt
		if not on_ground:
			jump_buf = 0.0  # a press left over in the air would wall-jump it back off a step
		elif w.collide_solid(rect_at(pos + Vector2(wall_d * dir, 0))) != null or _gap_within(gap_d) or _breakable_within(brk_d):
			jump_buf = INPUT_BUFFER
			hold_jump = VAR_JUMP_TIME
		jump_check = hold_jump > 0
		grab_check = false
	# A breakable block under the pixel d px past the leading edge (the planner's world sees it as a gap).
	# Look ahead for temporary support that requires an earlier takeoff.
	func _breakable_within(d: float) -> bool:
		var hb := hitbox()
		var hit = w.real.collide_solid(Rect2i(_ahead(d), hb.end.y, 1, 2))
		return hit is Crumble or hit is BreakWall

	# No floor under the pixel d px past the leading edge.
	# Probe support just ahead of the runner to decide when it should jump a gap.
	func _gap_within(d: float) -> bool:
		var hb := hitbox()
		return w.collide_solid(Rect2i(_ahead(d), hb.end.y, 1, 2)) == null
	# The pixel column d px past the leading edge, in the running direction.
	func _ahead(d: float) -> int:
		var hb := hitbox()
		return hb.end.x + int(d) - 1 if dir > 0 else hb.position.x - int(d)


# What the chasing Ape's runner sees of the world: the same collision, none of the player's side effects
# (stamina, sounds, dust, touches, deaths, room exits).
# Collision adapter for the planner. It borrows real terrain but disables gameplay side effects.
class ChaseWorld:
	var real
	var bounds: Rect2i
	var time := 0.0
	var ents: Array = []
	var parts: Array = []
	# Retain real collision access and room bounds for the side-effect-free simulation adapter.
	func _init(world) -> void:
		real = world
		bounds = world.bounds
	# Breakable blocks (crumble, breakable walls) count as empty: the Ape's path never stands on or leans on them.
	# Delegate real collision while treating breakable supports as empty for the planned route.
	func collide_solid(r: Rect2i, ignore = null, skip_dream := false):
		var hit = real.collide_solid(r, ignore, skip_dream)
		if hit == null or hit is String or not (hit is Crumble or hit is BreakWall):
			return hit  # tiles are checked first: an entity here means no tile overlaps
		for e in real.solids:
			if e.collidable and e != ignore and not (skip_dream and e.dream) and not (e is Crumble or e is BreakWall) and e.rect.intersects(r):
				return e
		return null
	# Reuse the real dream-block query without running gameplay interactions.
	func collide_dream(r: Rect2i):
		return real.collide_dream(r)
	# Reuse the real one-way-platform query during the silent route simulation.
	func collide_jumpthru(r: Rect2i):
		return real.collide_jumpthru(r)
	# Reuse the real newly-entered one-way-platform query for simulated movement.
	func collide_jumpthru_outside(r_at: Rect2i, r_now: Rect2i):
		return real.collide_jumpthru_outside(r_at, r_now)
	# Reuse real liquid-region detection so simulated movement applies the correct water physics.
	func liquid_at(r: Rect2i, t: String) -> bool:
		return real.liquid_at(r, t)
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func touching_spikes(_r: Rect2i) -> bool: return false
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func can_exit(_p: Vector2) -> bool: return false
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func adventure() -> bool: return false
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func dust(_at: Vector2, _dir: Vector2, _n: int, _col := Color.WHITE) -> void: pass
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func shake_dir(_dir: Vector2, _t: float) -> void: pass
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func add_trail(_p) -> void: pass
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func freeze_for(_t: float) -> void: pass
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func player_touch(_p) -> void: pass
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func on_player_death(_p, _dir: Vector2) -> void: pass
	# Intentionally do nothing in route planning: simulated movement must not alter real gameplay or emit this effect.
	func drain_stamina(_amount: float, _why := "") -> void: pass
