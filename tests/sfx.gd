extends SceneTree
# Audio regression checks for generated waveform output, the reusable voice pool and independent music/effects volume. These inspect samples and playback state; they do not replace listening to the mix.
# Reading help: docs/CODE_GUIDE.md.


var failures := 0

# Record a failed expectation with its explanation so the runner can report failures and return an appropriate exit code.
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

# Godot calls this SceneTree entry point at startup; begin or schedule the standalone runner workload.
func _initialize() -> void:
	call_deferred("run")

# Execute this standalone regression workload and quit with its accumulated failure count.
func run() -> void:
	var game = root.get_node("Game")
	# Missing synthesis, silent samples, unbounded voices and missing muting break these checks.
	if not game.has_method("get_sfx"):
		check(false, "Game provides persistent sound effects")
		quit(failures)
		return
	var sfx = game.get_sfx()
	for key in sfx.SOUNDS:
		var stream: AudioStreamWAV = sfx.streams[key]
		check(stream.get_length() > 0.02 and stream.get_length() < 2.0, "%s has a short audible duration" % key)
		var peak := 0
		var bytes := stream.data
		for i in range(0, bytes.size(), 2):
			peak = maxi(peak, absi(bytes.decode_s16(i)))
		check(peak > 500 and peak < 32000, "%s is audible without clipping" % key)
	var playing := func() -> int: return sfx.voices.filter(func(v): return v.playing).size()
	for i in 50:
		sfx.play("jump")
	check(playing.call() == 1, "Repeats of one effect inside its cooldown are dropped (%d playing)" % playing.call())
	for key in sfx.streams:
		sfx.play(key)
	check(sfx.streams.size() > sfx.VOICES and playing.call() == sfx.VOICES and sfx.get_child_count() == sfx.VOICES,
		"More distinct effects than voices fill the pool without growing it (%d playing)" % playing.call())
	game.settings.sfx_volume = 0.0
	game.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX volume zero mutes effects independently")
	game.settings.sfx_volume = 0.7
	game.apply_settings()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Raising SFX volume unmutes effects")
	check(is_equal_approx(sfx.voices[0].volume_db, -10.0 + linear_to_db(0.2)), "Effects play at 20% of their synthesized level")
	game.get_music_engine()
	game.settings.music_volume = 0.0
	game.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music volume zero mutes the music")
	game.settings.music_volume = 0.5
	game.apply_settings()
	var mb := AudioServer.get_bus_index("Music")
	check(not AudioServer.is_bus_mute(mb) and is_equal_approx(AudioServer.get_bus_volume_db(mb), linear_to_db(0.5)), "Music volume sets the Music bus")
	print("SFX OK" if failures == 0 else "SFX FAILED: %d" % failures)
	root.get_node("Game").quit_game(failures)
