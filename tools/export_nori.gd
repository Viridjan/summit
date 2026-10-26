extends SceneTree
# Offline artwork export: reads the same procedural character source used at runtime and writes the reference atlas PNG (the run poses are its second row). Running it updates assets; it does not change movement or collision.
# Reading help: docs/CODE_GUIDE.md.

# Rebuild the reference atlas after editing the code-authored character art:
# godot --headless --path . --script res://tools/export_nori.gd

const CharacterArt := preload("res://scripts/character_art.gd")

# Run this offline image export and quit; output images are regenerated from the authored source.
func _initialize() -> void:
	var image := CharacterArt.build_atlas()
	var result := image.save_png("res://assets/nori/nori.png")
	if result != OK:
		push_error("Could not export Nori atlas: %s" % result)
		quit(1)
		return
	image.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
	image.save_png("/tmp/summit-nori-atlas-preview.png")
	print("Exported Nori: 128x208 atlas, 13 animation rows")
	quit()
