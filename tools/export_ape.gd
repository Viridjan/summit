extends SceneTree

func _initialize() -> void:
	var art = load("res://scripts/ape_art.gd")
	var poses := ["idle", "crouch", "air", "throw", "scream", "run"]
	var sheet := Image.create(128, poses.size() * 32, false, Image.FORMAT_RGBA8)
	for row in poses.size():
		for frame in 4:
			sheet.blit_rect(art.build(poses[row], frame), Rect2i(0, 0, 32, 32), Vector2i(frame * 32, row * 32))
	sheet.save_png("res://assets/enemies/ape.png")
	sheet.resize(768, poses.size() * 192, Image.INTERPOLATE_NEAREST)
	sheet.save_png("/tmp/summit-ape-preview.png")
	quit()
