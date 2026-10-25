extends Node
# Rendered diagnostic scene for inspecting body/contact rectangles beside their artwork; it does not define production collision behavior.
# Reading help: docs/CODE_GUIDE.md.

# Pickups and platforms touch exactly what they draw: renders each type alone and compares the drawn
# pixels with touch_rect(). Needs a renderer (not --headless):
#   godot --path . res://tools/check_hitboxes.tscn   (exit code = mismatches)
const E := preload("res://scripts/entities.gd")
const TYPES := ["refill", "refill_two", "ability_dash", "ability_climb", "ability_attack", "stamina_block", "stamina_orb",
	"strawberry", "booster", "booster_red", "bumper", "feather", "goal", "jumpthru", "leaf", "crumble", "breakwall",
	"boss_ape", "ape_trunk", "boss_gate", "house_door"]

class Canvas extends Node2D:
	var e
	# Draw the diagnostic World hitbox overlay on this canvas.
	func _draw() -> void:
		e.draw(self)

# Begin the standalone diagnostic scene once its nodes are available.
func _ready() -> void:
	var bad := 0
	for t in TYPES:
		var d := {"t": t, "x": 64, "y": 64}
		if E.TYPES[t][1]:
			d.w = 32
			d.h = 8
		var e = E.make(null, d)
		var vp := SubViewport.new()
		vp.size = Vector2i(200, 200)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var c := Canvas.new()
		c.e = e
		vp.add_child(c)
		for i in 3:
			await RenderingServer.frame_post_draw
		var drawn := vp.get_texture().get_image().get_used_rect()
		var touch: Rect2i = e.touch_rect() if not (e.solid or e.jumpthru) else e.rect
		if e.has_method("body_boxes"):  # a shaped body (the Ape): its bands must sit inside the sprite
			touch = drawn if e.body_boxes().all(func(b): return drawn.encloses(b)) else e.body_boxes()[0]
		if drawn != touch:
			bad += 1
			print("MISMATCH %s: drawn %s, hitbox %s" % [t, drawn, touch])
		vp.queue_free()
	print("%d hitbox mismatch(es)" % bad)
	get_tree().quit(bad)
