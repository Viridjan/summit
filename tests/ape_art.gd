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
	for pose in ["idle", "crouch", "air", "throw", "scream", "run", "land"]:
		var img: Image = art.build(pose, 0)
		check(img.get_size() == Vector2i(32, 32), "%s preserves the boss footprint" % pose)
		check(img.get_used_rect().has_area(), "%s has visible artwork" % pose)
		poses[img.get_data()] = true
	check(poses.size() == 7, "Attacks, movement and landing have distinct silhouettes")
	check(art.has_method("impact_texture"), "Landing has animated shockwave artwork")
	if art.has_method("impact_texture"):
		for width in [80, 100, 120]:
			var frames := {}
			for frame in 4:
				var impact: Texture2D = art.impact_texture(width, 8, frame)
				var pixels := impact.get_image()
				check(pixels.get_size() == Vector2i(width, 8), "Impact preserves damage bounds")
				check(pixels.get_used_rect().size.x == width, "Impact shows the full dangerous width")
				check(pixels.get_pixel(0, 0).a == 0.0, "Impact has a transparent silhouette")
				frames[pixels.get_data()] = true
			check(frames.size() == 4, "Impact evolves across its active window")
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
	# Airborne poses must change silhouette, not just shading or a clock-based loop.
	var jump_shapes := {}
	for pose in ["launch", "rise", "apex", "fall"]:
		var jump: Image = art.build(pose, 0)
		var mask := PackedByteArray()
		for y in 32:
			for x in 32:
				mask.append(1 if jump.get_pixel(x, y).a > 0 else 0)
		jump_shapes[mask] = true
	check(jump_shapes.size() == 4, "Takeoff, rise, apex and descent have different outlines")
	check(art.has_method("jump_pose"), "Jump artwork follows vertical movement")
	if art.has_method("jump_pose"):
		check(art.jump_pose(-180.0) == "rise", "Upward movement extends the rising pose")
		check(art.jump_pose(0.0) == "apex", "Jump peak uses the tucked pose")
		check(art.jump_pose(180.0) == "fall", "Descent prepares the fists for landing")
	print("APE ART OK" if failures == 0 else "APE ART FAILED")
	quit(failures)
