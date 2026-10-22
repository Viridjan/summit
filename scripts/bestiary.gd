extends Control
# Monsters page: every enemy family in the entity registry, one row each, with the variants that family comes in.
# Shown from the main menu (Monsters) and as the second tab of the map screen.

const E := preload("res://scripts/entities.gd")
const EnemyArt := preload("res://scripts/enemy_art.gd")
const NAME_W := 210.0
const CELL_W := 150.0
const ROW_H := 64.0
const SPRITE_H := 40.0  # the biggest body is scaled down to fit this height

var rows: Array[String] = []  # family type ids ("enemy_thornmite"), registry order
var variants := {}  # family -> [type id, ...], the original first
var hp := {}  # type id -> hit points
var body := {}  # type id -> body size in pixels (giants are bigger)
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in E.TYPES:
		var e = E.make(null, {"t": t, "x": 0, "y": 0})
		if not e is E.CombatEnemy:
			continue
		hp[t] = e.hp
		body[t] = Vector2(e.rect.size)
		var family: String = e.family()
		if not variants.has(family):
			rows.append(family)
			variants[family] = []
		variants[family].append(t)

func _process(dt: float) -> void:
	clock += dt
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var most := 1
	for f in rows:
		most = maxi(most, variants[f].size())
	var x0: float = maxf(0.0, (size.x - NAME_W - CELL_W * most) / 2.0)
	for r in rows.size():
		var y: float = r * ROW_H
		var label: String = E.TYPES[rows[r]][0]
		draw_string(font, Vector2(x0, y + 30), label.get_slice(" · ", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		draw_string(font, Vector2(x0, y + 50), label.get_slice(" · ", 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.7, 0.8))
		for i in variants[rows[r]].size():
			var t: String = variants[rows[r]][i]
			var cx: float = x0 + NAME_W + i * CELL_W
			var b: Vector2 = body[t]
			var scale := 2.0 if t.ends_with("_giant") else 1.0
			var s := minf(3.0, SPRITE_H / (maxf(b.x, b.y) + 8.0 * scale))  # sprite = body plus its overhang
			draw_set_transform(Vector2(cx + 28, y + 28), 0, Vector2(s, s))
			EnemyArt.draw(self, t, Vector2.ZERO, 1, clock + r * 0.3, false, scale)
			draw_set_transform(Vector2.ZERO)
			var variant: String = "Original" if i == 0 else E.TYPES[t][0].get_slice(" · ", 1)
			draw_string(font, Vector2(cx + 58, y + 26), variant, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.8, 0.9))
			draw_string(font, Vector2(cx + 58, y + 44), "HP %d" % hp[t], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
