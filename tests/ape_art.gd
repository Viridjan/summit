extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/ape_art.gd"):
		check(false, "Ape has authored profile artwork")
		quit(failures)
		return
	var art = load("res://scripts/ape_art.gd")
	var poses := {}
	for pose in ["idle", "crouch", "air", "throw", "scream", "run"]:
		var img: Image = art.build(pose, 0)
		check(img.get_size() == Vector2i(32, 32), "%s preserves the boss footprint" % pose)
		check(img.get_used_rect().has_area(), "%s has visible artwork" % pose)
		poses[img.get_data()] = true
	check(poses.size() == 6, "Attacks and movement have distinct silhouettes")
	var image: Image = art.build("idle", 0)
	var mirrored := image.duplicate()
	mirrored.flip_x()
	check(image.get_data() != mirrored.get_data(), "Profile silhouette has a clear facing direction")
	print("APE ART OK" if failures == 0 else "APE ART FAILED")
	quit(failures)
