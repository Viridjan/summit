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
	for i in 50:
		sfx.play("jump")
	check(sfx.get_child_count() <= 16, "Rapid effects use a bounded voice pool")
	game.settings.sfx_volume = 0.0
	game.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX volume zero mutes effects independently")
	game.settings.sfx_volume = 0.7
	game.apply_settings()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Raising SFX volume unmutes effects")
	print("SFX OK" if failures == 0 else "SFX FAILED: %d" % failures)
	quit(failures)
