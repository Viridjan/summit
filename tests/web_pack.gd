extends SceneTree
func _initialize() -> void:
	for path in ["scripts/world_editor.gd", "scripts/music_studio.gd", "scripts/art_gallery.gd", "scripts/progression_job.gd", "assets/nori/nori.png", "assets/enemies/ape.png"]:
		if ResourceLoader.exists("res://" + path):
			push_error("Development resource remains: " + path)
			quit(1)
			return
	for path in ["scripts/menu.gd", "scripts/world.gd", "scripts/bestiary.gd", "assets/music/mountain.wav", "assets/themes/forest/terrain.png"]:
		if load("res://" + path) == null:
			push_error("Missing gameplay resource: " + path)
			quit(1)
			return
	print("WEB PACK OK")
	quit(0)
