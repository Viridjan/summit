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
	var sfx = game.get_sfx()
	if not sfx.streams.has("cave_roar"):
		check(false, "Cave roar has its own sound")
		quit(failures)
		return
	var stream: AudioStreamWAV = sfx.streams.cave_roar
	check(stream.stereo and stream.get_length() > 2.0, "Roar is a sustained stereo sound")
	var left := 0.0
	var right := 0.0
	for i in range(0, stream.data.size(), 4):
		left += pow(float(stream.data.decode_s16(i)), 2)
		right += pow(float(stream.data.decode_s16(i + 2)), 2)
	check(left > right * 4.0 and right > 1000.0, "Roar comes from the left with an audible echo on the right")
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/story/c0_roar_tunnel.json"))
	var trigger = null
	for data in level.entities:
		if data.get("sound", "") == "cave_roar":
			trigger = game.Entities.make(null, data)
	check(trigger != null, "Roar Tunnel contains the sound trigger")
	if trigger != null:
		trigger.touch(null)
		var playing := 0
		for voice in sfx.voices:
			if voice.playing and voice.stream == stream:
				playing += 1
		check(playing == 1, "Entering the trigger plays the roar")
		sfx.cooldowns.clear()
		trigger.touch(null)
		playing = 0
		for voice in sfx.voices:
			if voice.playing and voice.stream == stream:
				playing += 1
		check(playing == 1, "Remaining on the trigger does not repeat the roar")
	print("ROAR OK" if failures == 0 else "ROAR FAILED")
	quit(failures)
