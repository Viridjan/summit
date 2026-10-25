extends SceneTree
## Offline export; changes only the island art pack and three new theme folders.
const Art := preload("res://scripts/island_art.gd")
const DIR := "res://assets/island/"
var failed := false

func save(img: Image, path: String) -> void:
	if img.save_png(path) != OK:
		failed = true
		push_error("Could not export " + path)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var manifest := {"source": "scripts/island_art.gd", "provenance": "Original procedural pixel art authored for Summit; no third-party source images.", "filter": "nearest", "frames": 4, "assets": []}
	for kind in ["serpent", "rock", "rock_warning", "rock_impact", "eruption", "vent", "elf", "mage", "landmark", "raft", "mirror", "beacon", "lava"]:
		var poses: Array = Art.SERPENT_POSES if kind == "serpent" else Art.PEOPLE_POSES if kind in ["elf", "mage"] else ["idle", "broken"] if kind == "vent" else ["idle"]
		var variants := 3 if kind in ["elf", "mage", "landmark"] else 1
		var sample := Art.build(kind, poses[0], 0, 0)
		var size := sample.get_size()
		var sheet := Art.canvas(size.x*4, size.y*poses.size()*variants)
		for variant in variants:
			for row in poses.size():
				for frame in 4:
					var img := Art.build(kind, poses[row], frame, variant)
					sheet.blit_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i(frame*size.x,(variant*poses.size()+row)*size.y))
		save(sheet, DIR+kind+".png")
		manifest.assets.append({"name": kind, "file": kind+".png", "cell": [size.x,size.y], "poses": poses, "variants": variants, "anchor": "bottom center", "collision": "Artwork only; gameplay defines collision separately."})
	for theme in Art.THEMES:
		var dir: String = "res://assets/themes/"+theme+"/"
		DirAccess.make_dir_recursive_absolute(dir)
		var terrain := Art.terrain(theme)
		var far := Art.scenery(theme,false)
		var near := Art.scenery(theme,true)
		save(terrain,dir+"terrain.png"); save(Art.corners(theme),dir+"inner_corners.png")
		save(far,dir+"background.png"); save(near,dir+"foreground.png")
		save(Art.decorations(theme),dir+"decorations.png")
		var preview := far.duplicate()
		preview.blend_rect(near,Rect2i(0,0,320,180),Vector2i.ZERO)
		for y in range(19,23):
			for x in 40:
				preview.blit_rect(terrain,Rect2i(8 if y==19 else 0,(x%4)*8,8,8),Vector2i(x*8,y*8))
		save(preview,dir+"preview.png")
	var out := FileAccess.open(DIR+"manifest.json",FileAccess.WRITE)
	if out == null:
		failed = true
	else:
		out.store_string(JSON.stringify(manifest,"\t")+"\n")
	print("ISLAND ART EXPORTED" if not failed else "ISLAND ART EXPORT FAILED")
	quit(1 if failed else 0)
