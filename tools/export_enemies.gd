extends SceneTree
# Offline export of the enemy artwork (drawn at runtime by scripts/enemy_art.gd) as reference sheets: one per family,
# `assets/enemies/<family>.png`, one row per type (the original first, then its variants in registry order), four
# 32x32 frames per row. `manifest.json` lists the rows. The Ape has its own sheet (tools/export_ape.gd).
# Reading help: docs/CODE_GUIDE.md.

const EnemyArt := preload("res://scripts/enemy_art.gd")
const CELL := 32

func _initialize() -> void:
	var atlas := EnemyArt.atlas()  # one row per EnemyArt.KINDS entry
	var families := {}  # "thornmite" -> [kind, ...]
	for kind in EnemyArt.KINDS:
		var family: String = kind.get_slice("_", 1)
		if not families.has(family):
			families[family] = []
		families[family].append(kind)
	var manifest := {"cell": [CELL, CELL], "frames": 4, "source": "scripts/enemy_art.gd (drawn at runtime; these are reference exports)", "sheets": []}
	for family in families:
		var kinds: Array = families[family]
		var sheet := Image.create(CELL * 4, CELL * kinds.size(), false, Image.FORMAT_RGBA8)
		for row in kinds.size():
			sheet.blit_rect(atlas, Rect2i(0, EnemyArt.KINDS.find(kinds[row]) * CELL, CELL * 4, CELL), Vector2i(0, row * CELL))
		sheet.save_png("res://assets/enemies/%s.png" % family)
		manifest.sheets.append({"file": family + ".png", "rows": kinds})
	FileAccess.open("res://assets/enemies/manifest.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	quit()
