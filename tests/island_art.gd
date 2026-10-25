extends SceneTree
# Asset contracts catch clipped exports, missing animation and opaque sprite backgrounds.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/island_art.gd"):
		check(false, "Island, serpent, rock and village artwork exists")
		quit(failures)
		return
	var art = load("res://scripts/island_art.gd")
	for spec in [["serpent", 96, 64], ["rock", 16, 16], ["rock_warning", 24, 8], ["rock_impact", 32, 16], ["eruption", 24, 32], ["vent", 16, 8], ["elf", 16, 24], ["mage", 16, 24], ["landmark", 32, 32], ["raft", 48, 24], ["mirror",24,24], ["beacon",24,32], ["lava",32,8]]:
		var frames := {}
		for frame in 4:
			var img: Image = art.build(spec[0], "idle", frame, 0)
			check(img.get_size() == Vector2i(spec[1], spec[2]), "%s export fits its slot" % spec[0])
			check(img.get_used_rect().has_area(), "%s is visible" % spec[0])
			check(img.get_pixel(0, 0).a == 0.0, "%s preserves transparent background" % spec[0])
			frames[img.get_data()] = true
		if spec[0] in ["serpent", "rock", "eruption", "elf", "mage"]:
			check(frames.size() > 1, "%s animates rather than repeating a still image" % spec[0])
	for kind in ["elf", "mage"]:
		var people := {}
		for variant in 3:
			people[art.build(kind, "idle", 0, variant).get_data()] = true
		check(people.size() == 3, "%s villagers have three distinct appearances" % kind)
	for theme in ["island_shore", "volcano", "volcanic_cave"]:
		var terrain: Image = art.terrain(theme)
		check(terrain.get_size() == Vector2i(128, 32), "Terrain preserves edge-mask atlas layout")
		check(art.corners(theme).get_size() == Vector2i(32, 8), "Concave corners preserve atlas layout")
		check(art.scenery(theme, false).get_size() == Vector2i(320, 180), "Scenery fits existing parallax pipeline")
	print("ISLAND ART OK" if failures == 0 else "ISLAND ART FAILED: %d" % failures)
	quit(failures)
