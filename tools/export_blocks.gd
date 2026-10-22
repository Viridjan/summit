extends SceneTree
const BlockArt := preload("res://scripts/block_art.gd")
func _initialize() -> void:
	var sheet := Image.create(224, 288, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1b2036"))
	var sizes := [Vector2i(8, 8), Vector2i(32, 8), Vector2i(24, 24), Vector2i(16, 32), Vector2i(56, 24), Vector2i(29, 13)]
	var positions := [8, 24, 64, 96, 120, 184]
	for row in BlockArt.STYLES.size():
		var style: String = BlockArt.STYLES[row]
		for column in sizes.size():
			var size: Vector2i = sizes[column]
			if style == "jumpthru": size.y = 5
			var piece := BlockArt.build_piece(style, size)
			piece.save_png("res://assets/blocks/%s-%dx%d.png" % [style, size.x, size.y])
			sheet.blit_rect(piece, Rect2i(Vector2i.ZERO, size), Vector2i(positions[column], row * 40 + 4))
	for damage in 3:
		var piece := BlockArt.build_piece("breakwall", Vector2i(32, 32), damage)
		piece.save_png("res://assets/blocks/breakwall-damage-%d.png" % damage)
		sheet.blit_rect(piece, Rect2i(0, 0, 32, 32), Vector2i(24 + damage * 48, 248))
	sheet.save_png("res://assets/blocks/contact-sheet.png")
	sheet.resize(sheet.get_width() * 5, sheet.get_height() * 5, Image.INTERPOLATE_NEAREST)
	sheet.save_png("/tmp/summit-block-art-preview.png")
	quit()
