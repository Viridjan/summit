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
	"acid": ["Acid", true, Color("6ae070"), Liquid],
	# design note: marks what a spot needs (a power-up not built yet, a boss, a secret...)
	"note": ["Note", false, Color("ffe08a"), Note],
}

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
		rect = Rect2i(rect.position.x - 2, rect.position.y - 2, 12, 12)
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
		rect = Rect2i(rect.position.x - 2, rect.position.y - 2, 12, 12)
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
		rect = Rect2i(rect.position.x - 2, rect.position.y - 2, 12, 12)
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
		rect = Rect2i(rect.position.x - 2, rect.position.y - 2, 12, 12)
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

	# Floor walkers: the next step has floor under it and no acid or spikes.
	func safe_step() -> bool:
		var foot := Rect2i(rect.position.x + facing * 2, rect.end.y, rect.size.x, 2)
		if w.collide_solid(foot) == null:
			return false
		for entity in w.touchables:
			if entity.collidable and (entity.d.t == "acid" or entity.d.t.begins_with("spikes_")) and entity.rect.intersects(Rect2i(rect.position + Vector2i(facing * 2, 0), rect.size).grow(2)):
				return false
		return true

	func contact() -> void:
		if w != null and w.player != null and not w.player.dead and rect.intersects(w.player.hurt_rect()):
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
			flash = 0.12
			if w != null:
				w.burst(center() + front() * rect.size.x * 0.5, Color("f8d89b"), 3)
			return
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
			elif puddles[i][0].intersects(w.player.hurt_rect()):
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
				if box.intersects(p.hurt_rect()):
					p.die(shot[1].normalized())
					remove = true
					break
			if remove: shots.remove_at(i)

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
					phase = "windup"
					timer = 0.35 * warning_multiplier
			"windup":
				timer -= dt
				if timer <= 0:
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
				phase = "windup"
				timer = 0.4 * warning_multiplier
		elif phase == "windup":
			timer -= dt
			if timer <= 0:
				velocity = (w.player.center() - center()).normalized() * 65 * speed_multiplier
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
					bones.append([center() + Vector2(facing * 5, -2), Vector2(facing * 60 * speed_multiplier, -65 - arc * 25), 2.0])
				phase = "idle"
				timer = 1.7 * recovery_multiplier
			return
		timer -= dt
		if absf(offset.y) < 40 * scale and sees_player(104 * scale):
			facing = -1 if offset.x < 0 else 1
			if timer <= 0 and bones.size() < 3:
				phase = "windup"
				timer = 0.45 * warning_multiplier
			return
		var reach := clampf(float(d.get("patrol", 40)), 8, 96)
		if not safe_step() or (absf(rect.position.x - home.x) >= reach and signf(rect.position.x - home.x) == facing):
			facing *= -1
		elif move_enemy(Vector2(facing * 14 * speed_multiplier * dt, 0)):
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
					phase = "charge"
					timer = 1.2
			"charge":
				if not safe_step() or move_enemy(Vector2(facing * 110 * speed_multiplier * dt, 0)) or timer <= 0:
					phase = "rest"
					timer = 0.9 * recovery_multiplier
			"rest":
				if timer <= 0: phase = "idle"
			_:
				var offset: Vector2 = w.player.center() - center()
				if absf(offset.y) < 12 * scale and sees_player(120 * scale):
					facing = -1 if offset.x < 0 else 1
					phase = "windup"
					timer = 0.5 * warning_multiplier
				elif not safe_step():
					facing *= -1
				elif move_enemy(Vector2(facing * 16 * speed_multiplier * dt, 0)):
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
					phase = "windup"
					timer = 0.6 * warning_multiplier
				elif not safe_step():
					facing *= -1
				elif move_enemy(Vector2(facing * 12 * speed_multiplier * dt, 0)):
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
					orbs.append([center(), to.normalized().rotated(a) * 70, 3.0])
				phase = "idle"
				timer = 2.2 * recovery_multiplier
		elif timer <= 0 and sees and orbs.is_empty():
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


class Liquid extends Ent:  # water: looks only; acid: kills on touch (like spikes)
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


class Note extends Ent:  # level-design reminder; text is shown in the HUD while the player stands on it
	func touch_rect() -> Rect2i:
		return rect.grow(8)
	func touch(_p) -> void:
		w.show_note(str(d.get("text", "")))
	func vis_rect() -> Rect2i:
		return rect.grow(8) if w != null else Rect2i(rect.position - Vector2i(160, 24), Vector2i(328, 40))
	func draw(ci: CanvasItem) -> void:
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
			following = true
			p.followers.append(self)
	func touch_rect() -> Rect2i:
		return rect if not following else Rect2i()
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
					st = 1
					timer = 0.4 if w.player.state != w.player.ST_CLIMB else 0.6
			1:
				timer -= dt
				shaken(dt, true)
				if timer <= 0:
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
		rect = Rect2i(rect.position.x - 4, rect.position.y - 4, 16, 16)
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
		rect = Rect2i(rect.position.x - 6, rect.position.y - 6, 20, 20)
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
