extends Control
# Monsters page: every enemy in the entity registry, one row per kind, one column per variant.
# Shown from the main menu (Monsters) and as the second tab of the map screen.

const E := preload("res://scripts/entities.gd")
const EnemyArt := preload("res://scripts/enemy_art.gd")
const VARIANTS := ["", "_swift", "_armored"]
const VARIANT_NAMES := ["Original", "Swift", "Armored"]
const NAME_W := 230.0
const COL_W := 200.0
const ROW_H := 80.0
const SCALE := 4.0

var rows: Array[String] = []  # base type ids ("enemy_thornmite"), registry order
var hp := {}  # type id -> hit points
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in E.TYPES:
		var e = E.make(null, {"t": t, "x": 0, "y": 0})
		if e is E.CombatEnemy:
			hp[t] = e.hp
			if not (t.ends_with("_swift") or t.ends_with("_armored")):
				rows.append(t)

func _process(dt: float) -> void:
	clock += dt
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var x0 := maxf(0.0, (size.x - NAME_W - COL_W * VARIANTS.size()) / 2.0)
	for v in VARIANTS.size():
		draw_string(font, Vector2(x0 + NAME_W + v * COL_W, 24), VARIANT_NAMES[v], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.7, 0.8))
	for r in rows.size():
		var y := 40.0 + r * ROW_H
		var label: String = E.TYPES[rows[r]][0]
		draw_string(font, Vector2(x0, y + 40), label.get_slice(" · ", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		draw_string(font, Vector2(x0, y + 64), label.get_slice(" · ", 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.8))
		for v in VARIANTS.size():
			var t: String = rows[r] + VARIANTS[v]
			if not hp.has(t):
				continue
			var at := Vector2(x0 + NAME_W + v * COL_W + 36, y + 40)
			draw_set_transform(at, 0, Vector2(SCALE, SCALE))
			EnemyArt.draw(self, t, Vector2.ZERO, 1, clock + r * 0.3)
			draw_set_transform(Vector2.ZERO)
			draw_string(font, at + Vector2(48, 8), "HP %d" % hp[t], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
