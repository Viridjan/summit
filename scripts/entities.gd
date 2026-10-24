extends RefCounted
# All level objects. Each is a small class; TYPES drives the editor palette.
# Behaviour follows Celeste's entities, simplified where noted.

const T := 8
const Art := preload("res://scripts/art.gd")
const EnemyArt := preload("res://scripts/enemy_art.gd")
const BlockArt := preload("res://scripts/block_art.gd")

# The entity registry: the one place a type is declared.
# type id (saved in level JSON) -> [editor label, sized (drag a rect in the editor), palette color, class]
# See docs/ADDING_ENTITIES.md before adding a type.
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
	# adventure energy (docs/STORY_DESIGN.md): a new block once per run; an orb that refills energy
	"energy_block": ["Energy Block", false, Color("7cf0c0"), EnergyBlock],
	"energy_orb": ["Energy Orb", false, Color("b8ffe0"), EnergyOrb],
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
	"leaf": ["Leaf Platform", true, Color("7fc04e"), Leaf],
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
}

const DOOR_TYPES := ["door", "house_door"]  # objects that link to another door by "id"/"to"

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
class Ent extends RefCounted:
	var w
	var d: Dictionary
	var rect: Rect2i
	var solid := false
	var jumpthru := false
	var dream := false
	var collidable := true
	var safe := true
	var lift := Vector2.ZERO
	var rem := Vector2.ZERO
	var shake := Vector2.ZERO
	var respawn := 0.0

	func _init(world, data: Dictionary) -> void:
		w = world
		d = data
		rect = Rect2i(int(data.x), int(data.y), int(data.get("w", T)), int(data.get("h", T)))
		setup()

	func setup() -> void: pass
	func hurts() -> bool: return false  # true: touching it is damage, checked against the player's smaller damage_rect()
	func damage_circles() -> Array: return []  # [centre, radius] for exact round hazards
	func damage_boxes() -> Array: return []  # extra boxes that hurt (projectiles, waves), for the hitbox overlay
	func update(_dt: float) -> void: pass
	func draw(_ci: CanvasItem) -> void: pass
	func touch(_p) -> void: pass  # player hurtbox overlaps touch_rect()
	func touch_rect() -> Rect2i: return rect
	# Conservative draw bounds, used only to skip offscreen drawing (sprites overhang
	# rect by up to 8px: jump-through rails, spring pads, shake, bobbing).
	func vis_rect() -> Rect2i: return rect.grow(8)

	func center() -> Vector2:
		return Vector2(rect.position) + Vector2(rect.size) / 2.0

	func player_riding() -> bool:
		return w != null and w.player != null and not w.player.dead and w.player.is_riding(self)

	# Monocle Solid.Move: push or carry the player
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

	func shaken(dt: float, active: bool) -> void:
		shake = Vector2(randi_range(-1, 1), randi_range(-1, 1)) if active and dt > 0 else Vector2.ZERO


class SpawnMarker extends Ent:
	func setup() -> void:
		collidable = false
	func draw(ci: CanvasItem) -> void:
		if w == null:  # editor only
			ci.draw_rect(Rect2(rect.position.x, rect.position.y - 3, 8, 11), Color(1, 1, 1, 0.6), false, 1.0)
			ci.draw_rect(Rect2(rect.position.x + 2, rect.position.y - 1, 4, 3), Color("ac3232"))


class Spikes extends Ent:
	var dir := "up"
	func hurts() -> bool: return true
	func setup() -> void:
		dir = (d.t as String).substr(7)
		var p := rect.position
		match dir:
			"up": rect = Rect2i(p.x, p.y + 5, 8, 3)
			"down": rect = Rect2i(p.x, p.y, 8, 3)
			"left": rect = Rect2i(p.x + 5, p.y, 3, 8)
			"right": rect = Rect2i(p.x, p.y, 3, 8)
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
	func draw(ci: CanvasItem) -> void:
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


class Spring extends Ent:
	var dir := "up"
	var anim := 0.0
	func setup() -> void:
		dir = (d.t as String).substr(7)
		var p := rect.position
		match dir:
			"up": rect = Rect2i(p.x, p.y + 4, 8, 4)
			"left": rect = Rect2i(p.x + 4, p.y, 4, 8)
			"right": rect = Rect2i(p.x, p.y, 4, 8)
	func update(dt: float) -> void:
		anim = maxf(0, anim - dt)
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


class Refill extends Ent:
	var two := false
	var t := 0.0
	func setup() -> void:
		two = d.t == "refill_two"
		rect = Rect2i(rect.position.x, rect.position.y, 8, 8)  # exactly the sprite
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	func touch(p) -> void:
		if respawn <= 0 and p.use_refill(two):
			w.freeze_for(0.05)
			w.burst(center(), Color("ff6def") if two else Color("4ee05a"), 8)
			respawn = 2.5
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 3) * 1.0))
		if respawn > 0:
			ci.draw_arc(c, 2, 0, TAU, 8, Color(1, 1, 1, 0.3), 1.0)
			return
		var col := Color("ff6def") if two else Color("4ee05a")
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0)]), col)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(1.5, 0), c + Vector2(0, 1), c + Vector2(-1.5, 0)]), col.lightened(0.6))


class AbilityOrb extends Ent:  # adventure pickup that unlocks a move for the rest of the run
	var ability := ""
	var t := 0.0
	func setup() -> void:
		ability = d.t.trim_prefix("ability_")
		rect = Rect2i(rect.position.x - 3, rect.position.y - 3, 14, 14)  # exactly the sprite
		collidable = w == null or not Game.has_ability(ability)  # already owned (or not in the adventure): gone
	func update(dt: float) -> void:
		t += dt
	func touch(_p) -> void:
		collidable = false
		w.grant_ability(ability)
		w.freeze_for(0.1)
		w.burst(center(), TYPES[d.t][2], 14)
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := center() + Vector2(0, round(sin(t * 2.5) * 1.5))
		var col: Color = TYPES[d.t][2]
		ci.draw_circle(c, 5, col.darkened(0.4))
		ci.draw_circle(c, 4, col)
		ci.draw_arc(c, 6.5 + sin(t * 4), 0, TAU, 16, Color(col, 0.5), 1.0)
		ci.draw_rect(Rect2(c + Vector2(-1, -2), Vector2(2, 2)), Color.WHITE)


class EnergyBlock extends Ent:  # adventure: +1 energy block, once per run
	var key := ""
	var t := 0.0
	func setup() -> void:
		rect = Rect2i(rect.position.x - 3, rect.position.y - 3, 14, 14)  # exactly the sprite
		if w != null:
			key = "%s:%d:%d" % [w.room, int(d.x), int(d.y)]
		collidable = w == null or (w.adventure() and not w.energy_block_taken(key))
	func update(dt: float) -> void:
		t += dt
	func touch(_p) -> void:
		collidable = false
		w.add_energy_block(key)
		w.freeze_for(0.1)
		w.burst(center(), TYPES[d.t][2], 14)
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := center() + Vector2(0, round(sin(t * 2.5) * 1.5))
		var col: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), col.darkened(0.4))
		ci.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), col)
		ci.draw_rect(Rect2(c - Vector2(6.5, 6.5), Vector2(13, 13)).grow(sin(t * 4)), Color(col, 0.5), false, 1.0)


# ponytail: refills all energy; collectibles that restore part of it come with the energy design
class EnergyOrb extends Ent:  # adventure: refills energy, back after 2.5 s
	var t := 0.0
	func setup() -> void:
		rect = Rect2i(rect.position.x - 1, rect.position.y - 1, 10, 10)  # exactly the sprite
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	func touch(_p) -> void:
		if respawn <= 0 and w.adventure() and Game.adv.energy < Game.Adventure.energy_max(Game.adv):
			w.refill_energy()
			respawn = 2.5
			w.burst(center(), TYPES[d.t][2], 8)
	func draw(ci: CanvasItem) -> void:
		var col: Color = TYPES[d.t][2] if respawn <= 0 else Color(0.3, 0.3, 0.4)
		var c := center() + Vector2(0, round(sin(t * 3)))
		ci.draw_circle(c, 3, col)
		ci.draw_arc(c, 5, 0, TAU, 12, Color(col, 0.6), 1.0)


class Door extends Ent:  # touching it moves the player to the linked door (World.door_hit)
	func touch(_p) -> void:
		w.door_hit(self)
	func vis_rect() -> Rect2i:
		return rect.grow(8) if w != null else Rect2i(rect.position - Vector2i(160, 24), rect.size + Vector2i(320, 32))
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
class HouseDoor extends Door:
	var near := 0.0  # > 0 while the player stands at it (drawn prompt)
	func touch(_p) -> void:
		w.door_near = self
		near = 0.1
	func update(dt: float) -> void:
		near = maxf(0.0, near - dt)
	func vis_rect() -> Rect2i:
		return rect.grow(12) if w != null else super.vis_rect()
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		var frame := Color("4e3422")
		ci.draw_rect(r, frame)  # exactly its hitbox: frame, planks inside, a knob
		var inner := r.grow(-1)
		ci.draw_rect(inner, Color("8a5a34"))
		for x in range(int(inner.position.x) + 4, int(inner.end.x), 4):
			ci.draw_rect(Rect2(x, inner.position.y, 1, inner.size.y), Color("6e4628"))
		ci.draw_rect(Rect2(inner.position.x, inner.position.y + 2, inner.size.x, 1), Color("6e4628"))
		ci.draw_rect(Rect2(inner.end.x - 3, inner.position.y + inner.size.y / 2.0, 2, 2), Color("e0c060"))
		if near > 0:  # prompt: an arrow above the door
			var c := Vector2(r.position.x + r.size.x / 2.0, r.position.y - 6 + roundf(sin(Time.get_ticks_msec() / 150.0)))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 2), c + Vector2(3, 2), c + Vector2(0, -2)]), Color.WHITE)
		if w == null and d.has("to"):
			super.draw(ci)  # editor: the link label


class Building extends Ent:  # backdrop only: never collides; put it before its door so the door draws on top
	func setup() -> void:
		collidable = false
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


class Placeholder extends Ent:  # enemy / breakable stand-in: a labelled box, harmless
	func setup() -> void:
		collidable = false
	func vis_rect() -> Rect2i:
		return rect.grow(2) if w != null else Rect2i(rect.position - Vector2i(80, 12), rect.size + Vector2i(160, 14))
	func draw(ci: CanvasItem) -> void:
		var c: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(rect), Color(c, 0.3))
		ci.draw_rect(Rect2(rect), c, false, 1.0)
		if w == null and str(d.get("text", "")) != "":
			ci.draw_string(ThemeDB.fallback_font, Vector2(rect.position) + Vector2(0, -2), str(d.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, c)


# Small, deterministic enemies: hit() integrates with the existing melee sector.
# A type id is "enemy_<family>" or "enemy_<family>_<variant>"; each family registers only the variants that suit it.
class CombatEnemy extends Ent:
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
	var home := Vector2.ZERO
	var phase := "idle"
	var timer := 0.0
	var puddles: Array = []  # venom: [Rect2i, seconds left]
	var drip := 0.5

	static func variant_of(t: String) -> String:
		var v := t.get_slice("_", t.get_slice_count("_") - 1)
		return v if v != "" and VARIANTS.has(v) and t.count("_") >= 2 else ""

	func _init(world, data: Dictionary) -> void:
		super(world, data)
		if d.get("brood_child", false):
			scale = 0.5
			speed_multiplier = 1.35
			hp = 1
		if scale != 1.0:  # grow or shrink from the top-left the level placed it at
			rect.size = Vector2i((Vector2(rect.size) * scale).round()).max(Vector2i(4, 4))
			home = Vector2(rect.position)

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

	func variant_hp(base: int) -> int:
		match variant:
			"swift": return maxi(1, base - 1)
			"armored": return base + 2
			"giant": return base * 2
			"shielded": return base + 1
		return base

	func family() -> String:
		return d.t.trim_suffix("_" + variant) if variant != "" else d.t

	func active(dt: float) -> bool:
		clock += dt
		flash = maxf(0, flash - dt)
		var on: bool = collidable and w != null and w.player != null and not w.player.dead and center().distance_to(w.player.center()) < 320
		if on and variant == "venom":
			update_venom(dt)
		return on

	func blocked(at: Rect2i) -> bool:
		return w != null and (not w.bounds.encloses(at) or w.collide_solid(at) != null)

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

	func contact() -> void:
		if w != null and w.player != null and not w.player.dead and rect.intersects(w.player.damage_rect()):
			touch(w.player)

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
	func front() -> Vector2:
		return Vector2(facing, 0)

	func blocks(p) -> bool:
		var to: Vector2 = p.center() - center()
		return variant == "shielded" and to.dot(front()) > 0 and to.y > -rect.size.y * 0.5

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
				w.burst(center(), EnemyArt.COLORS["y"], 6)
				if variant == "brood":
					brood()

	func brood() -> void:
		var kid_t: String = family() + "_swift" if TYPES.has(family() + "_swift") else family()
		for side in [-1, 1]:
			var kid := Rect2i(Vector2i(center()) + Vector2i(side * 4 - 2, -2), Vector2i(4, 4))
			var at: Vector2i = kid.position if not blocked(kid.grow(2)) else Vector2i(center()) - Vector2i(2, 2)
			w.spawn_entity({"t": kid_t, "x": at.x, "y": at.y, "facing": side, "brood_child": true})

	# Venom: every so often a puddle on the surface below; the player dies on touching one.
	func venom_spot() -> Rect2i:
		var below := Rect2i(rect.position.x, rect.end.y, rect.size.x, 1)
		for i in 96:
			if blocked(below):
				return Rect2i(int(center().x) - 5, below.position.y - 4, 10, 4)  # tall enough to reach a standing player's hurtbox
			below.position.y += 1
		return Rect2i()

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

	func touch(p) -> void:
		if collidable:
			p.die((p.center() - center()).normalized())

	func vis_rect() -> Rect2i:
		return body_rect()

	func body_rect() -> Rect2i:  # the sprite overhangs the body; venom puddles lie around it
		var area := rect.grow(8 + int(rect.size.x * 0.5))
		for pd in puddles:
			area = area.merge(pd[0])
		return area

	func draw(ci: CanvasItem) -> void:
		for pd in puddles:
			ci.draw_rect(Rect2(pd[0]), Color(0.55, 0.85, 0.3, minf(1.0, pd[1]) * 0.45))  # fades as it dries
		if not collidable:
			return
		EnemyArt.draw(ci, d.t, center(), facing, clock, flash > 0, scale)
		if variant == "shielded":  # bright edge on the guarded side
			var f := front()
			var edge := center() + f * (rect.size.x * 0.5 + 1)
			ci.draw_rect(Rect2(edge - Vector2(1, rect.size.y * 0.4), Vector2(2, rect.size.y * 0.8)) if f.x != 0 else Rect2(edge - Vector2(rect.size.x * 0.4, 1), Vector2(rect.size.x * 0.8, 2)), Color("f8d89b"))
		if phase == "windup" and int(clock * 12) % 2 == 0:
			ci.draw_rect(Rect2(center().x - 1, rect.position.y - 4, 2, 2), Color("f8d89b"))

	# Projectiles owned by an enemy: [position, velocity, seconds left]. They stop at rock, can be swatted by the attack.
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

	func damage_boxes() -> Array:  # projectiles (as update_shots tests them) and venom puddles
		var out := []
		for shots in [get("bones"), get("orbs")]:
			if shots is Array:
				for shot in shots:
					out.append(Rect2i(Vector2i(shot[0]) - Vector2i.ONE, Vector2i(3, 3)))
		for pd in puddles:
			out.append(pd[0])
		return out

	func shots_rect(shots: Array) -> Rect2i:
		var area := body_rect()
		for shot in shots:
			area = area.merge(Rect2i(Vector2i(shot[0]) - Vector2i(3, 3), Vector2i(6, 6)))
		return area


class SkreeEnemy extends CombatEnemy:
	var vertical_speed := 0.0
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


class BatEnemy extends CombatEnemy:
	var velocity := Vector2.ZERO
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(10, 8)
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


class SkeletonEnemy extends CombatEnemy:
	var gravity_speed := 0.0
	var bones: Array = []  # owned projectiles (see update_shots)
	func setup() -> void:
		super.setup()
		hp = variant_hp(3)
		timer = 1.0 * recovery_multiplier
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
	func hit(p) -> void:
		super.hit(p)
		if not collidable: bones.clear()
	func update_bones(dt: float) -> void:
		update_shots(bones, dt, 150)
	func vis_rect() -> Rect2i:
		return shots_rect(bones)
	func draw(ci: CanvasItem) -> void:
		super.draw(ci)
		for bone in bones:
			var at: Vector2 = bone[0].round()
			ci.draw_rect(Rect2(at - Vector2(2, 0), Vector2(4, 1)), Color("d8d8bd"))
			ci.draw_rect(Rect2(at - Vector2(2, 1), Vector2(1, 3)), Color("d8d8bd"))
			ci.draw_rect(Rect2(at + Vector2(1, -1), Vector2(1, 3)), Color("d8d8bd"))


class ThornmiteEnemy extends CombatEnemy:
	# Crawls around terrain like a mite on a rock: floors, walls and ceilings, turning at every corner.
	var dir := Vector2i.RIGHT  # crawl direction
	var down := Vector2i.DOWN  # the surface it clings to
	var crawl := 0.0  # sub-pixel movement owed
	var fall := 0.0
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(8, 8)
		hp = variant_hp(2)
		dir = Vector2i(facing, 0)
	func clings() -> bool:
		return blocked(Rect2i(rect.position + down, rect.size))
	func front() -> Vector2:
		return Vector2(dir)
	func venom_spot() -> Rect2i:  # a trail on whatever surface it clings to
		match down:
			Vector2i.UP: return Rect2i(rect.position.x, rect.position.y, rect.size.x, 4)
			Vector2i.LEFT: return Rect2i(rect.position.x, rect.position.y, 4, rect.size.y)
			Vector2i.RIGHT: return Rect2i(rect.end.x - 4, rect.position.y, 4, rect.size.y)
		return Rect2i(rect.position.x, rect.end.y - 4, rect.size.x, 4)
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
	func draw(ci: CanvasItem) -> void:
		if down == Vector2i.DOWN or not collidable:
			super.draw(ci)
			return
		for pd in puddles:
			ci.draw_rect(Rect2(pd[0]), Color(0.55, 0.85, 0.3, minf(1.0, pd[1]) * 0.45))  # fades as it dries
		ci.draw_set_transform(center(), Vector2(Vector2i.DOWN).angle_to(Vector2(down)), Vector2.ONE)  # feet on its surface
		EnemyArt.draw(ci, d.t, Vector2.ZERO, facing, clock, flash > 0, scale)
		ci.draw_set_transform(Vector2.ZERO)


class HornbackEnemy extends CombatEnemy:
	# Walks its floor. A player at its height in sight gets a warning, then a fast charge that stops at walls and ledges.
	var gravity_speed := 0.0
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(12, 10)
		hp = variant_hp(3)
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


class MosstrotEnemy extends CombatEnemy:
	# Jungle wanderer: walks back and forth on its floor, turning at walls and ledges. Never chases; touching it still hurts.
	var gravity_speed := 0.0
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(12, 8)
		hp = variant_hp(2)
	func update(dt: float) -> void:
		if not active(dt): return
		gravity_speed = minf(140, gravity_speed + 400 * dt)
		if move_enemy(Vector2(0, gravity_speed * dt)): gravity_speed = 0
		if walk(14 * speed_multiplier * dt):
			facing *= -1


class FuzzbobEnemy extends CombatEnemy:
	# Drifts diagonally and bounces off anything solid; it never chases, its path is the threat.
	var velocity := Vector2.ZERO
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(10, 10)
		hp = variant_hp(2)
		velocity = Vector2(facing, 1).normalized() * 30 * speed_multiplier
	func update(dt: float) -> void:
		if not active(dt): return
		if move_enemy(Vector2(velocity.x * dt, 0)): velocity.x = -velocity.x
		if move_enemy(Vector2(0, velocity.y * dt)): velocity.y = -velocity.y
		facing = 1 if velocity.x > 0 else -1


class CragjawEnemy extends CombatEnemy:
	# Big brute: plods along its floor; a player in reach gets a warning, then a leap that slams down near them.
	var velocity := Vector2.ZERO
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(20, 20)
		hp = variant_hp(6)
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


class MurksporeEnemy extends CombatEnemy:
	# Big hovering spore: keeps its distance, bobs, and spits a three-orb spread at a visible player.
	var orbs: Array = []  # owned projectiles (see update_shots)
	var bob := 0.0
	func setup() -> void:
		super.setup()
		rect.size = Vector2i(16, 14)
		hp = variant_hp(5)
		timer = 1.0
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
	func update_orbs(dt: float) -> void:
		update_shots(orbs, dt, 0)
	func hit(p) -> void:
		super.hit(p)
		if not collidable: orbs.clear()
	func vis_rect() -> Rect2i:
		return shots_rect(orbs)
	func draw(ci: CanvasItem) -> void:
		super.draw(ci)
		for orb in orbs:
			ci.draw_circle(orb[0].round(), 2.5, Color("b07ad8"))
			ci.draw_circle(orb[0].round(), 1.2, Color("f0d8ff"))


class Liquid extends Ent:  # water: drains adventure energy (World.update_energy); acid: kills on touch (like spikes)
	func hurts() -> bool: return d.t == "acid"
	func setup() -> void:
		collidable = d.t == "acid"
	func touch(p) -> void:
		p.die(Vector2.UP)
	func draw(ci: CanvasItem) -> void:
		var c: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(rect), Color(c, 0.35))
		if d.get("top", true):  # only a pool's surface row draws the line (tools/world_fixups.py settle_liquids)
			ci.draw_line(Vector2(rect.position), Vector2(rect.end.x, rect.position.y), Color(c.lightened(0.4), 0.9), 1.0)


class BreakWall extends Ent:
	var id := ""
	var hp := 3
	var flash := 0.0
	func setup() -> void:
		solid = true
		hp = int(d.get("hp", 3))
		id = "%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
			collidable = not w.broken.has(id)
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
	func update(dt: float) -> void:
		flash = maxf(flash - dt, 0)
		shaken(dt, flash > 0)
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var damage := clampi(int(d.get("hp", 3)) - hp, 0, 2)
		BlockArt.draw(ci, rect, "breakwall", shake, damage)
		var r := Rect2(Vector2(rect.position) + shake, rect.size)
		if flash > 0:
			ci.draw_rect(r, Color(1, 1, 1, 0.5))


class Note extends Ent:  # design reminder or a one-shot authored sound trigger
	var sound_played := false
	func touch_rect() -> Rect2i:
		return rect.grow(8)
	func touch(_p) -> void:
		if d.has("sound"):
			if not sound_played:
				sound_played = true
				Game.play_sfx(str(d.sound))
			return
		w.show_note(str(d.get("text", "")))
	func vis_rect() -> Rect2i:
		return rect.grow(8) if w != null else Rect2i(rect.position - Vector2i(160, 24), Vector2i(328, 40))
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


class Star extends Ent:  # the collectible (type id "strawberry")
	const STAR_PTS := [Vector2(0, -4.5), Vector2(1.2, -1.6), Vector2(4.3, -1.4), Vector2(1.9, 0.6), Vector2(2.6, 3.6), Vector2(0, 2), Vector2(-2.6, 3.6), Vector2(-1.9, 0.6), Vector2(-4.3, -1.4), Vector2(-1.2, -1.6)]  # 5-point star around (0, 0)
	var id := ""
	var following := false
	var collect_timer := 0.0
	var pos := Vector2.ZERO
	var t := 0.0
	func setup() -> void:
		id = "%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
		rect = Rect2i(rect.position.x - 1, rect.position.y - 1, 10, 10)
		pos = center()
		collidable = w == null or not w.collected.has(id)
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
	func touch(p) -> void:
		if collidable and not following:
			Game.play_sfx("pickup", 0.8)
			following = true
			p.followers.append(self)
	func touch_rect() -> Rect2i:  # exactly the sprite at rest
		return Rect2i(rect.position + Vector2i(2, 2), Vector2i(6, 7)) if not following else Rect2i()
	func vis_rect() -> Rect2i:  # drawn at pos, which trails the player
		return Rect2i(Vector2i(pos) - Vector2i(8, 8), Vector2i(16, 16))
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var c := pos + Vector2(0, 0 if following else round(sin(t * 2.5)))
		ci.draw_colored_polygon(Transform2D(0, c) * PackedVector2Array(STAR_PTS), Color("ffd34e"))
		ci.draw_rect(Rect2(c.x - 1, c.y - 1, 1, 1), Color("fff6c0"))


class JumpThru extends Ent:
	func setup() -> void:
		jumpthru = true
		rect.size.y = 5
	func draw(ci: CanvasItem) -> void:
		BlockArt.draw(ci, rect, "jumpthru")


class Leaf extends JumpThru:  # a jump-through drawn as leaves on a stem, filling its box exactly
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color("41673a"))  # stem
		for x in range(0, int(r.size.x), 6):
			var lw := minf(5, r.size.x - x)
			ci.draw_rect(Rect2(r.position + Vector2(x, 0), Vector2(lw, r.size.y - 1)), Color("7fc04e") if x % 12 else Color("6aa840"))
			ci.draw_rect(Rect2(r.position + Vector2(x + 1, 0), Vector2(maxf(0, lw - 2), 1)), Color("b6e080"))


class Waterfall extends Ent:  # falling water; the push is the player's waterfall layer (Player._layers)
	var t := 0.0
	func update(dt: float) -> void:
		t += dt
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		ci.draw_rect(r, Color(0.54, 0.78, 0.94, 0.45))
		for x in range(1, int(r.size.x) - 1, 3):  # streaks scrolling down
			var y := fposmod(t * 120.0 + x * 7, 12.0)
			while y < r.size.y:
				ci.draw_rect(Rect2(r.position + Vector2(x, y), Vector2(1, minf(4, r.size.y - y))), Color(0.9, 0.97, 1.0, 0.6))
				y += 12.0


class Crumble extends Ent:
	var st := 0  # 0 idle, 1 shaking, 2 gone
	var timer := 0.0
	func setup() -> void:
		solid = true
		safe = false
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
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			ci.draw_rect(Rect2(rect), Color(1, 1, 1, 0.08), false, 1.0)
			return
		BlockArt.draw(ci, rect, "crumble", shake, 1 if st == 1 else 0)


class FallingBlock extends Ent:
	var st := 0  # 0 wait, 1 shake, 2 fall, 3 landed
	var timer := 0.0
	var vy := 0.0
	func setup() -> void:
		solid = true
		safe = false
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
	static func Player_approach(v: float, t: float, a: float) -> float:
		return minf(v + a, t) if v <= t else maxf(v - a, t)
	func draw(ci: CanvasItem) -> void:
		BlockArt.draw(ci, rect, "falling", shake)


class ZipMover extends Ent:
	var start := Vector2.ZERO
	var target := Vector2.ZERO
	var st := 0
	var timer := 0.0
	var at := 0.0
	func setup() -> void:
		solid = true
		start = Vector2(rect.position)
		target = Vector2(float(d.get("tx", rect.position.x)), float(d.get("ty", rect.position.y - 32)))
	func vis_rect() -> Rect2i:  # block plus the whole rail
		var r := rect.merge(Rect2i(Vector2i(start), rect.size)).merge(Rect2i(Vector2i(target), rect.size))
		return r.grow(8)
	static func sine_in(x: float) -> float:
		return 1.0 - cos(x * PI / 2.0)
	func _goto(p: Vector2, dt: float) -> void:
		move_by(p - (Vector2(rect.position) + rem), dt)
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


class DreamBlock extends Ent:
	var stars: Array = []
	var t := 0.0
	func setup() -> void:
		solid = true
		dream = true
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(rect)
		for i in maxi(2, rect.get_area() / 40):
			stars.append([Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y), [Color("ffef70"), Color("70ffef"), Color("ff70d0"), Color.WHITE][rng.randi() % 4]])
	func update(dt: float) -> void:
		t += dt
	func draw(ci: CanvasItem) -> void:
		var r := Rect2(rect)
		ci.draw_rect(r, Color("101018"))
		for s in stars:
			var p: Vector2 = r.position + s[0]
			if int(t * 4 + p.x) % 3 != 0:
				ci.draw_rect(Rect2(p.floor(), Vector2.ONE), s[1])
		ci.draw_rect(r, Color.WHITE, false)


class Booster extends Ent:
	var red := false
	var cannot_use := 0.0
	var t := 0.0
	func setup() -> void:
		red = d.t == "booster_red"
		rect = Rect2i(rect.position.x - 3, rect.position.y - 3, 14, 14)  # exactly the sprite
	func update(dt: float) -> void:
		t += dt
		cannot_use = maxf(0, cannot_use - dt)
		if respawn > 0:
			respawn -= dt
	func touch(p) -> void:
		if respawn <= 0 and cannot_use <= 0 and p.state != p.ST_BOOST:
			cannot_use = 0.45
			p.boost(self, red)
	func player_boosted() -> void:
		respawn = 1.0
	func player_released() -> void:
		respawn = 1.0
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


class Bumper extends Ent:
	var t := 0.0
	func setup() -> void:
		rect = Rect2i(rect.position.x - 5, rect.position.y - 5, 18, 18)  # exactly the sprite
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	func touch(p) -> void:
		if respawn <= 0:
			p.explode_launch(center(), false)
			respawn = 0.6
			w.burst(center(), Color("80a0ff"), 10)
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 2) * 1.0))
		var col := Color("4060d0") if respawn <= 0 else Color("303050")
		ci.draw_circle(c, 9, col)
		ci.draw_arc(c, 9, 0, TAU, 24, col.lightened(0.4), 1.0)
		ci.draw_circle(c, 3, col.lightened(0.5))


class Feather extends Ent:
	func touch_rect() -> Rect2i:  # exactly the sprite
		return Rect2i(rect.position + Vector2i(1, 2), Vector2i(9, 9))
	var t := 0.0
	func setup() -> void:
		rect = Rect2i(rect.position.x - 2, rect.position.y - 2, 12, 12)
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	func touch(p) -> void:
		if respawn <= 0 and p.start_star_fly():
			respawn = 3.0
			w.burst(center(), Color("ffd65c"), 8)
	func draw(ci: CanvasItem) -> void:
		var c := center() + Vector2(0, round(sin(t * 3) * 1.5))
		if respawn > 0:
			ci.draw_arc(c, 2, 0, TAU, 8, Color(1, 0.85, 0.4, 0.3), 1.0)
			return
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 4), c + Vector2(4, -4), c + Vector2(2, 2)]), Color("ffd65c"))
		ci.draw_line(c + Vector2(-5, 5), c + Vector2(3, -3), Color("fff3c0"), 1.0)


class Goal extends Ent:
	func touch_rect() -> Rect2i:  # exactly the sprite
		return Rect2i(rect.position + Vector2i(2, 4), Vector2i(11, 9))
	var t := 0.0
	func setup() -> void:
		rect = Rect2i(rect.position.x - 4, rect.position.y - 4, 16, 16)
	func update(dt: float) -> void:
		t += dt
	func touch(_p) -> void:
		w.complete()
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
class ApeTrunk extends Ent:
	const FALL_TIME := 0.6
	var id := ""
	var standing := Rect2i()
	var fall := 0.0  # 0 standing .. 1 down
	var falling := false
	func setup() -> void:
		solid = true
		collidable = false
		standing = rect
		id = "%d_%d" % [rect.position.x, rect.position.y]
		if w != null:
			id = w.star_key(id)
			if w.broken.has(id):
				_lay()
	func down() -> bool:
		return fall >= 1.0
	func fell() -> void:
		if falling or down():
			return
		falling = true
		if w != null:
			w.burst(Vector2(standing.position.x + standing.size.x / 2.0, standing.position.y + 8), Color("c8a070"), 10)
	func _lay() -> void:
		fall = 1.0
		falling = false
		collidable = true
		rect = Rect2i(standing.position.x, standing.end.y, standing.size.y, 8)
	func update(dt: float) -> void:
		if falling:
			fall = minf(1.0, fall + dt / FALL_TIME)
			if fall >= 1.0:
				_lay()
				w.break_wall(id)
				w.shake_dir(Vector2.DOWN, 0.25)
				w.dust(Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y), Vector2.UP, 12)
	func vis_rect() -> Rect2i:
		var h := standing.size.y
		return Rect2i(standing.position.x - 8, standing.position.y - 8, h + 24, h + 24)
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
class BossGate extends Ent:
	var passed := false
	func setup() -> void:
		solid = true
		collidable = w == null or not d.get("closes_behind", false)
	func update(_dt: float) -> void:
		if d.get("closes_behind", false) and not passed:
			passed = w.player.hitbox().position.x > rect.end.x + 4
		collidable = Ape.alive_in(w) and (passed or not d.get("closes_behind", false))
	func draw(ci: CanvasItem) -> void:
		if not collidable:
			return
		var r := Rect2(rect)
		ci.draw_rect(r, Color("2e4a26"))
		for x in range(int(r.position.x), int(r.end.x), 4):  # thorny vines
			ci.draw_rect(Rect2(x, r.position.y, 2, r.size.y), Color("4a6a3a"))
			for y in range(int(r.position.y) + (x % 8), int(r.end.y), 8):
				ci.draw_rect(Rect2(x + 2, y, 2, 2), Color("c8d06a"))


# Walks the player in for a moment (the arena's entrance), using Celeste's forced movement. Once per visit.
class AutoWalk extends Ent:
	var used := false
	func touch(p) -> void:
		if used or (d.get("while_boss", false) and not Ape.alive_in(w)):
			return
		used = true
		p.force_move_x = int(d.get("dir", 1))
		p.force_move_x_timer = float(d.get("time", 0.6))
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
# the standing trunk fells it. Landing on spikes is a hit: it screams, leaps again, and the next spike patch
# appears (d.spikes, one list per hit: [x, y, count] in px). Three hits beat it: the exits open, the
# player is exhausted (energy 5) and an energy orb appears (d.orb).
class Ape extends Ent:
	const HP := 3
	const SIZE := 32
	const BODY := 24  # contact box: one square, a bit larger than the 22px body bands it replaced
	const LEAP_G := 600.0
	const LEAP_TIME := 0.75
	const OVERSHOOT := 24.0  # the slam lands this far past the player
	const STONE_G := 400.0
	const STONE := 16  # stone size = its hitbox
	const SCREAM_REACH := 24  # 3 units around the body
	const SLAM_REACH := 16  # landing shockwave: this far out on both sides, along the ground
	const SLAM_HEIGHT := 8
	const SLAM_TIME := 0.2
	const FAR := 140.0
	const NEAR := 44.0
	const WAKE := 220.0
	var hp := HP
	var phase := "sleep"  # sleep, idle, throw, crouch, air, scream, hurt, dying, gone
	var timer := 0.0
	var vel := Vector2.ZERO
	var facing := -1
	var stage := 0
	var then_slam := false
	var stones: Array = []  # [centre, velocity]
	var flash := 0.0
	var clock := 0.0
	var slam_t := 0.0  # the landing shockwave is live while > 0
	var id := ""
	var x_min := 0.0
	var x_max := 0.0
	# True while the room has an Ape that isn't beaten (gates and the entrance walk follow it).
	static func alive_in(world) -> bool:
		for e in world.ents:
			if e is Ape and not e is ApeChase and e.phase != "gone":
				return true
		return false
	func hurts() -> bool:
		return phase != "gone" and phase != "dying"
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
	func leap_range() -> Vector2:
		var t = trunk()
		var r: Array = d.get("range2", []) if t != null and t.down() and d.has("range2") else [x_min, x_max]
		return Vector2(float(r[0]), float(r[1]))
	func trunk():
		for e in w.ents:
			if e is ApeTrunk:
				return e
		return null
	# The movement footprint stays 32px; contact damage uses one centred 24px square.
	func touch_rect() -> Rect2i:
		return Rect2i(rect.position + Vector2i((SIZE - BODY) / 2, (SIZE - BODY) / 2), Vector2i(BODY, BODY))
	func body_boxes() -> Array:
		return [touch_rect()]
	func body_hits(area: Rect2i) -> bool:
		for box in body_boxes():
			if box.intersects(area): return true
		return false
	func scream_radius() -> float:
		return SIZE / 2.0 + SCREAM_REACH
	func scream_hits(area: Rect2i) -> bool:
		var c := center()
		var nearest := c.clamp(Vector2(area.position),Vector2(area.end))
		return area.has_area() and c.distance_squared_to(nearest) < scream_radius() * scream_radius()
	func damage_circles() -> Array:
		return [[center(),scream_radius()]] if phase == "scream" and timer <= 0.0 and timer > -0.35 else []
	func touch(p) -> void:
		if hurts() and body_hits(p.damage_rect()):
			p.die((p.center() - center()).normalized())
	func update(dt: float) -> void:
		clock += dt
		flash = maxf(0.0, flash - dt)
		_update_stones(dt)
		if phase == "gone":
			return
		if slam_t > 0:
			slam_t -= dt
			if not w.player.dead and slam_box().intersects(w.player.damage_rect()):
				w.player.die(Vector2(signf(w.player.center().x - center().x), -1).normalized())
		var p = w.player
		var dx: float = p.center().x - center().x
		if phase in ["idle", "throw", "crouch", "scream"]:
			facing = 1 if dx > 0 else -1
		timer -= dt
		match phase:
			"sleep":
				if absf(dx) < WAKE:
					_go("scream", 0.5)  # the fight opens with a scream
			"idle":
				if timer <= 0:
					var r := leap_range()
					if center().x < r.x or center().x > r.y:  # outside its range (the trunk just fell): leap there
						_go("crouch", 0.45)
					elif p.center().x < r.x or p.center().x > r.y:  # player out of its reach (past the trunk): leap at them
						_go("crouch", 0.45)
					elif absf(dx) > FAR:
						_go("throw", 0.7)
					elif absf(dx) > NEAR:
						_go("crouch", 0.45)
					else:
						_go("scream", 0.5)
			"throw":
				if timer <= 0:
					_throw(p.center())
					_go("idle", 1.0)
			"crouch":
				if timer <= 0:
					var side := 1.0 if dx > 0 else -1.0
					var r := leap_range()
					var tx := clampf(p.center().x + side * OVERSHOOT, r.x + SIZE / 2.0, r.y - SIZE / 2.0)
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
					if then_slam:
						then_slam = false
						_go("crouch", 0.3)
					else:
						_go("idle", 0.8)
			"hurt":
				if timer <= 0:
					then_slam = true
					_go("scream", 0.3)
			"dying":
				if timer <= 0:
					_beaten()
	func _go(ph: String, t: float) -> void:
		if ph == "scream":
			Game.play_sfx("ape_scream")
		elif ph == "hurt" or ph == "dying":
			Game.play_sfx("enemy_hit", 0.6)
		phase = ph
		timer = t
	func _throw(target: Vector2) -> void:
		Game.play_sfx("projectile", 0.6)
		var from := Vector2(center().x + facing * 10, rect.position.y)
		var t := clampf(absf(target.x - from.x) / 220.0, 0.7, 1.3)
		stones.append([from, Vector2((target.x - from.x) / t, (target.y - from.y) / t - 0.5 * STONE_G * t)])
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
	func damage_boxes() -> Array:  # stones, and the scream and the landing shockwave while they're live
		var out := []
		for s in stones:
			out.append(Rect2i(Vector2i(s[0]) - Vector2i(STONE / 2, STONE / 2), Vector2i(STONE, STONE)))
		if slam_t > 0:
			out.append(slam_box())
		return out
	# The landing shockwave along the ground, both sides of the body.
	func slam_box() -> Rect2i:
		return Rect2i(rect.position.x - SLAM_REACH, rect.end.y - SLAM_HEIGHT, SIZE + 2 * SLAM_REACH, SLAM_HEIGHT)
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
		_go("idle", 0.6)
	func _hit() -> void:
		hp -= 1
		flash = 0.8
		w.burst(center(), Color("ff6040"), 14)
		if hp <= 0:
			_go("dying", 1.2)
			return
		stage += 1
		var patches: Array = d.get("spikes", [])
		if stage - 1 < patches.size():
			for patch in patches[stage - 1]:
				for i in int(patch[2]):
					w.spawn_entity({"t": "spikes_up", "x": int(patch[0]) + i * T, "y": int(patch[1])})
		_go("hurt", 0.8)
	func _beaten() -> void:
		Game.play_sfx("complete")
		phase = "gone"
		collidable = false
		w.break_wall(id)
		w.shake_dir(Vector2.ZERO, 0.4)
		if w.adventure():
			Game.adv.energy = minf(Game.adv.energy, 5.0)  # the fight leaves the hero exhausted
		if d.has("orb"):
			w.spawn_entity({"t": "energy_orb", "x": int(d.orb[0]), "y": int(d.orb[1])})
	func _update_stones(dt: float) -> void:
		var t = trunk() if w != null else null
		for i in range(stones.size() - 1, -1, -1):
			var s: Array = stones[i]
			s[1].y += STONE_G * dt
			s[0] += s[1] * dt
			var box := Rect2i(Vector2i(s[0]) - Vector2i(STONE / 2, STONE / 2), Vector2i(STONE, STONE))
			var gone := false
			if not w.player.dead and box.intersects(w.player.damage_rect()):
				w.player.die(s[1].normalized())
				gone = true
			elif t != null and not t.down() and not t.falling and box.intersects(t.standing):
				t.fell()
				gone = true
			elif w.collide_solid(box) != null or s[0].y > w.gh * T + 64:
				gone = true
			if gone:
				w.burst(s[0], Color("9a9080"), 8)
				stones.remove_at(i)
	func vis_rect() -> Rect2i:
		return rect.grow(400)
	func draw(ci: CanvasItem) -> void:
		for s in stones:  # stones: 16x16, exactly their hitbox
			var at: Vector2 = s[0] - Vector2(STONE / 2.0, STONE / 2.0)
			ci.draw_rect(Rect2(at + Vector2(2, 0), Vector2(12, 16)), Color("8a8478"))
			ci.draw_rect(Rect2(at + Vector2(0, 2), Vector2(16, 12)), Color("8a8478"))
			ci.draw_rect(Rect2(at + Vector2(3, 3), Vector2(5, 3)), Color("b0aa9c"))
		if phase == "gone":
			return
		var a := 1.0 if phase != "dying" else clampf(timer / 1.2, 0.0, 1.0)
		var pose := phase
		if phase in ["chase", "running"]:
			pose = "run"
		elif phase == "roar":
			pose = "scream"
		var art = load("res://scripts/ape_art.gd")
		var o := Vector2(rect.position)
		var tint := Color(1, 1, 1, a)
		if flash > 0 and int(flash * 20) % 2 == 0:
			tint = Color(1.8, 1.5, 1.3, a)
		ci.draw_set_transform(o + Vector2(SIZE / 2.0, 0), 0.0, Vector2(facing, 1))
		ci.draw_texture_rect(art.texture(pose, int(clock * 10.0)), Rect2(-SIZE / 2.0, 0, SIZE, SIZE), false, tint)
		if phase == "throw":
			ci.draw_rect(Rect2(3, -5, 8, 6), Color("8a8478"))
			ci.draw_rect(Rect2(4, -4, 4, 2), Color("b0aa9c"))
		ci.draw_set_transform(Vector2.ZERO)
		if slam_t > 0:  # the shockwave, exactly its hitbox
			var sb := Rect2(slam_box())
			ci.draw_rect(sb, Color(0.85, 0.75, 0.55, 0.35 + slam_t))
			ci.draw_rect(Rect2(sb.position, Vector2(sb.size.x, 2)), Color(1, 0.95, 0.8, 0.8))
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
class ApeChase extends Ape:
	const ROAR_TIME := 1.0  # it screams this long before giving chase
	static var _plans := {}  # room key -> PackedVector2Array of feet positions, one per tick
	var path := PackedVector2Array()
	var at := 0.0  # index into path
	func setup() -> void:
		super.setup()
		if phase != "gone":
			phase = "wait"
	func hurts() -> bool:
		return phase == "chase"
	func touch(p) -> void:
		if hurts() and body_hits(p.damage_rect()):
			p.die((p.center() - center()).normalized())
	func update(dt: float) -> void:
		clock += dt
		if phase == "gone":
			return
		var p = w.player
		timer -= dt
		match phase:
			"wait":
				if p.center().x > float(d.get("trigger", rect.end.x + 64)):
					Game.play_sfx("ape_scream_cave")
					w.shake_dir(Vector2.ZERO, 0.3)
					facing = 1
					var key := "%s:%d:%d" % [w.star_key(""), rect.position.x, rect.position.y]
					if not _plans.has(key):  # planned once per room, when first needed
						_plans[key] = plan(w, rect, float(d.get("end", w.bounds.end.x)) + 16.0)
					path = _plans[key]
					phase = "roar"
					timer = ROAR_TIME
			"roar", "chase":
				if phase == "roar":
					if timer <= 0:
						phase = "chase"
				elif not path.is_empty():
					at = minf(at + dt * 60.0, path.size() - 1)
					var f: Vector2 = path[int(at)]
					rect.position = Vector2i(roundi(f.x - SIZE / 2.0), roundi(f.y) - SIZE)
					if not p.dead and body_hits(p.damage_rect()):
						touch(p)
				if p.center().x > float(d.get("end", 1e9)):
					Game.play_sfx("ape_scream_cave", 0.8)
					w.break_wall(id)  # gone for the rest of the run
					phase = "dying"
					timer = 1.2
			"dying":
				if timer <= 0:
					phase = "gone"
					collidable = false
	func draw(ci: CanvasItem) -> void:
		if phase != "wait":
			super.draw(ci)

	# Tries take-off distances (px before a wall, px past the edge of a gap) until a simulated run from the Ape's
	# spot reaches end_x without touching spikes. Returns that run's feet positions, or an empty path if none works.
	static func plan(world, from: Rect2i, end_x: float) -> PackedVector2Array:
		for brk in [2, 4, 6, 8, 3, 5]:  # extra take-off margin before a breakable block
			for wall in [12, 8, 16, 10, 14, 6, 18]:
				for gap in [1, 2, 4, 6, 8]:
					var run := _simulate(world, from, end_x, wall, gap, brk)
					if not run.is_empty():
						return run
		push_warning("ApeChase: no path found to x %d" % end_x)
		return PackedVector2Array()

	# The box, or the pixel row under it, overlaps a breakable block.
	static func _on_breakable(world, hb: Rect2i) -> bool:
		var feet := Rect2i(hb.position, hb.size + Vector2i(0, 1))
		for e in world.solids:
			if (e is Crumble or e is BreakWall) and e.rect.intersects(feet):
				return true
		return false

	# One run to the right; empty when it touches spikes or a breakable, falls out or gets stuck.
	static func _simulate(world, from: Rect2i, end_x: float, wall: float, gap: float, brk: float) -> PackedVector2Array:
		var r := ChaseRunner.new(ChaseWorld.new(world), Vector2.ZERO)
		r.pos = Vector2(from.position.x + SIZE / 2.0, from.end.y)
		r.pos.x -= r.hitbox().get_center().x - r.pos.x
		r.pos.y -= r.bottom() - from.end.y
		r.wall_d = wall
		r.gap_d = gap
		r.brk_d = gap + brk
		var path := PackedVector2Array()
		var best := -1e9
		var still := 0
		for tick in 60 * 60:
			r.update(1.0 / 60.0)
			var hb: Rect2i = r.hitbox()
			path.append(Vector2(hb.get_center().x, hb.end.y))
			if world.touching_spikes(r.damage_rect()) or hb.position.y > world.bounds.end.y or _on_breakable(world, hb):
				return PackedVector2Array()
			if hb.end.x >= end_x:
				return path
			if hb.end.x > best:
				best = hb.end.x
				still = 0
			else:
				still += 1
				if still > 90:  # stuck under a step it never cleared
					return PackedVector2Array()
		return PackedVector2Array()


# The chasing Ape's body while planning: the player's movement code, always running right, jumping wall_d px
# before a wall and when the floor ends within gap_d px.
class ChaseRunner extends "res://scripts/player.gd":
	var wall_d := 12.0
	var gap_d := 1.0
	var brk_d := 3.0  # take-off distance when the floor ahead is a breakable block
	var hold_jump := 0.0
	func _init(world, spawn: Vector2) -> void:
		super(world, spawn)
		quiet = true
	func _read_input(dt: float) -> void:
		in_x = 1
		in_y = 0
		aim_raw = Vector2(in_x, 0)
		aim_free = aim_raw
		jump_buf -= dt
		dash_buf -= dt
		attack_buf -= dt
		hold_jump -= dt
		if not on_ground:
			jump_buf = 0.0  # a press left over in the air would wall-jump it back off a step
		elif w.collide_solid(rect_at(pos + Vector2(wall_d, 0))) != null or _gap_within(gap_d) or _breakable_within(brk_d):
			jump_buf = INPUT_BUFFER
			hold_jump = VAR_JUMP_TIME
		jump_check = hold_jump > 0
		grab_check = false
	# A breakable block under the pixel d px past the leading edge (the planner's world sees it as a gap).
	func _breakable_within(d: float) -> bool:
		var hb := hitbox()
		var hit = w.real.collide_solid(Rect2i(hb.end.x + int(d) - 1, hb.end.y, 1, 2))
		return hit is Crumble or hit is BreakWall

	# No floor under the pixel d px past the leading edge.
	func _gap_within(d: float) -> bool:
		var hb := hitbox()
		return w.collide_solid(Rect2i(hb.end.x + int(d) - 1, hb.end.y, 1, 2)) == null


# What the chasing Ape's runner sees of the world: the same collision, none of the player's side effects
# (energy, sounds, dust, touches, deaths, room exits).
class ChaseWorld:
	var real
	var bounds: Rect2i
	var time := 0.0
	var ents: Array = []
	var parts: Array = []
	func _init(world) -> void:
		real = world
		bounds = world.bounds
	# Breakable blocks (crumble, breakable walls) count as empty: the Ape's path never stands on or leans on them.
	func collide_solid(r: Rect2i, ignore = null, skip_dream := false):
		var hit = real.collide_solid(r, ignore, skip_dream)
		if hit == null or hit is String or not (hit is Crumble or hit is BreakWall):
			return hit  # tiles are checked first: an entity here means no tile overlaps
		for e in real.solids:
			if e.collidable and e != ignore and not (skip_dream and e.dream) and not (e is Crumble or e is BreakWall) and e.rect.intersects(r):
				return e
		return null
	func collide_dream(r: Rect2i):
		return real.collide_dream(r)
	func collide_jumpthru(r: Rect2i):
		return real.collide_jumpthru(r)
	func collide_jumpthru_outside(r_at: Rect2i, r_now: Rect2i):
		return real.collide_jumpthru_outside(r_at, r_now)
	func liquid_at(r: Rect2i, t: String) -> bool:
		return real.liquid_at(r, t)
	func touching_spikes(_r: Rect2i) -> bool: return false
	func can_exit(_p: Vector2) -> bool: return false
	func adventure() -> bool: return false
	func dust(_at: Vector2, _dir: Vector2, _n: int, _col := Color.WHITE) -> void: pass
	func shake_dir(_dir: Vector2, _t: float) -> void: pass
	func add_trail(_p) -> void: pass
	func freeze_for(_t: float) -> void: pass
	func player_touch(_p) -> void: pass
	func on_player_death(_p, _dir: Vector2) -> void: pass
	func drain_energy(_amount: float) -> void: pass
