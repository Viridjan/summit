extends RefCounted
# All level objects. Each is a small class; TYPES drives the editor palette.
# Behaviour follows Celeste's entities, simplified where noted.

const T := 8
const Art := preload("res://scripts/art.gd")

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
	# door: drag its size; "id" names it, "to" = "room:id" (or just "id" in the same level) is where it leads.
	# Links rooms that don't touch (elevators, trams) or that sit behind a wall.
	"door": ["Door", true, Color("40e0ff"), Door],
	# placeholders from reference maps: "text" names the thing (e.g. "Crawlid", "grub jar")
	"enemy": ["Enemy (placeholder)", true, Color("e04848"), Placeholder],
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


class Liquid extends Ent:  # water: looks only; acid: kills on touch (like spikes)
	func setup() -> void:
		collidable = d.t == "acid"
	func touch(p) -> void:
		p.die(Vector2.UP)
	func draw(ci: CanvasItem) -> void:
		var c: Color = TYPES[d.t][2]
		ci.draw_rect(Rect2(rect), Color(c, 0.35))
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
		for y in range(rect.position.y, rect.end.y, T):
			for x in range(rect.position.x, rect.end.x, T):
				Art.cell(ci, Art.STONE, Vector2(x, y) + shake)
		var r := Rect2(rect)
		for i in 3 - clampi(hp, 0, 3):  # a crack per hit taken
			var x := r.position.x + r.size.x * (0.3 + 0.2 * i)
			ci.draw_line(Vector2(x, r.position.y + 2), Vector2(x - 2, r.end.y - 2), Color(0, 0, 0, 0.6))
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
		for x in range(rect.position.x, rect.end.x, T):
			Art.cell(ci, Art.RAIL, Vector2(x, rect.position.y))


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
		for y in range(rect.position.y, rect.end.y, T):
			for x in range(rect.position.x, rect.end.x, T):
				Art.cell(ci, Art.STONE, Vector2(x, y) + shake)


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
		for y in range(rect.position.y, rect.end.y, T):
			for x in range(rect.position.x, rect.end.x, T):
				Art.cell(ci, Art.STONE_2, Vector2(x, y) + shake, Color(1.0, 0.8, 1.0))


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
		ci.draw_rect(r, Color("1e1e24"))
		ci.draw_rect(r.grow(-1), Color("d0b040"), false, 1.0)
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
		ci.draw_rect(r, Color("08080f"))
		for s in stars:
			var p: Vector2 = r.position + s[0]
			if int(t * 4 + p.x) % 3 != 0:
				ci.draw_rect(Rect2(p.floor(), Vector2.ONE), s[1])
		ci.draw_rect(r, Color.WHITE, false, 1.0)


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
