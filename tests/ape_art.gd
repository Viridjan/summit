extends SceneTree
# Checks boss artwork bounds, distinct action poses and deterministic texture-cache behavior at different animation clocks.
# Reading help: docs/CODE_GUIDE.md.


var failures := 0

# Record a failed expectation with its explanation so the runner can report failures and return an appropriate exit code.
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

# Godot calls this SceneTree entry point at startup; begin or schedule the standalone runner workload.
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
	# Cold caches first touched at different clocks: same canonical frame, same image; the run loops every 4.
	art._textures.clear()
	var late: Image = art.texture("run", 7).get_image()
	art._textures.clear()
	check(art.texture("run", 3).get_image().get_data() == late.get_data(), "Run frame 7 and 3 share one image whichever comes first")
	check(art.build("run", 0).get_data() == art.build("run", 4).get_data(), "Run animation loops every 4 frames")
	check(art.build("run", 0).get_data() != art.build("run", 1).get_data(), "Run frames differ within the loop")
	check(art.texture("idle", 5) == art.texture("idle", 0), "Still poses share one texture")
	print("APE ART OK" if failures == 0 else "APE ART FAILED")
	quit(failures)
