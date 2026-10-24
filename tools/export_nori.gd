extends SceneTree
# Rebuild the reference atlas after editing the code-authored character art:
# godot --headless --path . --script res://tools/export_nori.gd

const CharacterArt := preload("res://scripts/character_art.gd")

func _initialize() -> void:
	var image := CharacterArt.build_atlas()
	var result := image.save_png("res://assets/nori/nori.png")
	if result != OK:
		push_error("Could not export Nori atlas: %s" % result)
		quit(1)
		return
	var stride := image.get_region(Rect2i(0,16,128,16))
	stride.save_png("res://assets/nori/run-poses.png")
	stride.resize(1024,128,Image.INTERPOLATE_NEAREST)
	stride.save_png("/tmp/summit-run-poses.png")
	image.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
	image.save_png("/tmp/summit-nori-atlas-preview.png")
	print("Exported Nori: 128x208 atlas, 13 animation rows")
	quit()
