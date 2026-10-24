extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = root.get_node("Game")
	var engine = game.get_music_engine()
	if not engine.has_method("follow_environment"):
		check(false, "Music follows the room background")
		quit(failures)
		return
	var signatures := {}
	for environment in ["", "forest", "sand", "sea", "cavern", "cavern_deep", "sky", "temple", "building"]:
		engine.follow_environment(environment)
		check(engine.playing and engine.environment == environment, "Background selects playing theme: " + environment)
		check(engine.patterns.size() == 4 and engine.patterns[0].size() >= 64, "Theme has a complete multi-bar arrangement")
		var signature: String = str(engine.patterns[0])
		check(not signatures.has(signature), "Environment has its own melody")
		signatures[signature] = true
		engine.stop()
		var samples: PackedFloat64Array = engine.driver.render(engine.build_mml(false), 44100, 2)
		var peak := 0.0
		for sample in samples:
			peak = maxf(peak, absf(sample))
		check(peak > 0.001 and peak < 1.0, "Theme renders audible unclipped audio: " + environment)
	engine.follow_environment("sea")
	var data = engine.driver.get_data()
	engine.follow_environment("sea")
	check(engine.driver.get_data() == data, "Crossing rooms with the same background keeps the music running")
	engine.follow_environment("unknown")
	check(engine.environment == "", "Unknown background uses mountain theme")
	engine.stop()
	game.main = Node.new()
	root.add_child(game.main)
	game.goto("music_studio")
	await process_frame
	var studio = game.main.get_child(0)
	if not studio.has_method("_select_environment"):
		check(false, "Studio offers environment score previews")
	else:
		studio._select_environment(5)
		check(engine.environment == "cavern" and engine.patterns[0].size() == 64, "Studio loads the selected environment score")
		studio._next_page()
		var first: int = engine.patterns[0][0]
		var edited: int = engine.patterns[0][16]
		studio._cycle(0, 0)
		check(engine.patterns[0][0] == first and engine.patterns[0][16] != edited, "Editing page two changes that page only")
	game.main.queue_free()
	await process_frame
	print("ENVIRONMENT MUSIC OK" if failures == 0 else "ENVIRONMENT MUSIC FAILED: %d" % failures)
	quit(failures)
