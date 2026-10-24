extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Catches missing music screen and broken conversion from edited steps to audible notes.
	if not ResourceLoader.exists("res://scripts/music_engine.gd"):
		check(false, "Music engine is available")
		quit(failures)
		return
	var game = root.get_node("Game")
	if not game.has_method("get_music_engine"):
		check(false, "Music service provides a single persistent synth")
		quit(failures)
		return
	var engine = game.get_music_engine()
	engine.patterns = [ [60, -1, 64, 67], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1] ]
	var mml: String = engine.build_mml(false)
	check(mml.contains("o4g+16r16o5c16o5d+16"), "Edited notes keep their durations and play two whole tones lower")
	check(mml.contains("t%d " % roundi(engine.bpm * 0.75)), "Songs play 25% slower than written")
	var samples: PackedFloat64Array = engine.driver.render(mml, 44100, 2)
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	check(peak > 0.001, "Real synth renders non-silent audio from the pattern")
	# Each instrument must produce audio; catches unsupported preset serialization.
	for instrument in engine.PRESETS.size():
		engine.instruments[0] = instrument
		samples = engine.driver.render(engine.build_mml(false), 44100, 2)
		peak = 0.0
		for sample in samples:
			peak = maxf(peak, absf(sample))
		check(peak > 0.001, "Instrument %s renders audio" % engine.INSTRUMENT_NAMES[instrument])
	engine.muted[0] = true
	samples = engine.driver.render(engine.build_mml(false), 44100, 2)
	peak = 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	check(peak < 0.0001, "Muting the only active channel renders silence")
	engine.muted[0] = false
	engine.instruments[0] = 0
	engine.patterns[0] = [-1, -1, -1, -1]
	samples = engine.driver.render(engine.build_mml(false), 44100, 2)
	peak = 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	check(peak < 0.0001, "Rest-only patterns render silence")
	engine.load_demo()
	engine.play()
	await create_timer(2.5).timeout
	check(engine.playing and engine.driver.is_streaming(), "Transport starts the synth")
	engine.stop()
	check(not engine.playing and not engine.driver.is_streaming(), "Transport stops the synth")
	await process_frame
	game.main = Node.new()
	root.add_child(game.main)
	game.goto("music_studio")
	await process_frame
	var studio = game.main.get_child(0)
	studio._cycle(0, 0)
	check(engine.patterns[0][0] == 74, "Editing a step changes its pitch")
	studio._toggle_play()
	check(engine.playing, "Studio transport starts playback")
	game.goto("menu")
	await process_frame
	await process_frame
	check(not is_instance_valid(studio) and not engine.playing, "Leaving the studio stops playback")
	# Reopening must not create a second simultaneous SiON driver.
	game.goto("music_studio")
	await process_frame
	check(game.main.get_child(0).engine == engine, "Studio reuses its single synth when reopened")
	game.main.get_child(0).engine.play()
	game.main.get_child(0).engine.stop()
	game.main.queue_free()
	await process_frame
	print("MUSIC OK" if failures == 0 else "MUSIC FAILED: %d" % failures)
	quit(failures)
