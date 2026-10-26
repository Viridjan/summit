extends SceneTree
# Offline export of the special-block artwork (drawn at runtime by scripts/block_art.gd) as reference sheets:
# one sheet per style, `assets/blocks/<style>.png`, one 56x32 cell per example size (each piece top-left in its
# cell); breakwall has a second row with its three damage states. `manifest.json` lists cells and sizes.
# Reading help: docs/CODE_GUIDE.md.

const BlockArt := preload("res://scripts/block_art.gd")
const CELL := Vector2i(56, 32)
const SIZES := [Vector2i(8, 8), Vector2i(32, 8), Vector2i(24, 24), Vector2i(16, 32), Vector2i(56, 24), Vector2i(29, 13)]

func _initialize() -> void:
	var manifest := {"cell": [CELL.x, CELL.y], "source": "scripts/block_art.gd (drawn at runtime; these are reference exports)", "sheets": []}
	for style in BlockArt.STYLES:
		var rows := 2 if style == "breakwall" else 1
		var sheet := Image.create(CELL.x * SIZES.size(), CELL.y * rows, false, Image.FORMAT_RGBA8)
		var sizes := []
		for column in SIZES.size():
			var size: Vector2i = SIZES[column]
			if style == "jumpthru": size.y = 5
			sheet.blit_rect(BlockArt.build_piece(style, size), Rect2i(Vector2i.ZERO, size), Vector2i(column * CELL.x, 0))
			sizes.append([size.x, size.y])
		var entry := {"file": style + ".png", "rows": ["sizes"], "sizes": sizes}
		if style == "breakwall":
			for damage in 3:
				sheet.blit_rect(BlockArt.build_piece("breakwall", Vector2i(32, 32), damage), Rect2i(0, 0, 32, 32), Vector2i(damage * CELL.x, CELL.y))
			entry.rows.append("damage 0, 1, 2 (32x32)")
		sheet.save_png("res://assets/blocks/%s.png" % style)
		manifest.sheets.append(entry)
	FileAccess.open("res://assets/blocks/manifest.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	quit()
