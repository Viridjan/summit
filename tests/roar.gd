extends SceneTree
# Checks the cave roar samples for left/right energy balance and verifies that its placed trigger plays only once.
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
	var sfx = game.get_sfx()
	if not sfx.streams.has("cave_roar"):
		check(false, "Cave roar has its own sound")
		quit(failures)
		return
	var stream: AudioStreamWAV = sfx.streams.cave_roar
	check(stream.stereo and stream.get_length() > 2.0, "Roar is a sustained stereo sound")
	var left := 0.0
	var right := 0.0
	var pcm := stream.data  # one copy: the property returns a fresh copy on every read
	for i in range(0, pcm.size(), 4):
		left += pow(float(pcm.decode_s16(i)), 2)
		right += pow(float(pcm.decode_s16(i + 2)), 2)
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
		var loud: Array = sfx.voices.filter(func(v): return v.playing and v.stream == stream)
		check(loud.size() == 1 and is_equal_approx(loud[0].volume_db, sfx.BASE_DB + linear_to_db(0.4)), "The roar plays at 200% of the effects level")
		sfx.cooldowns.clear()
		trigger.touch(null)
		playing = 0
		for voice in sfx.voices:
			if voice.playing and voice.stream == stream:
				playing += 1
		check(playing == 1, "Remaining on the trigger does not repeat the roar")
	print("ROAR OK" if failures == 0 else "ROAR FAILED")
	root.get_node("Game").quit_game(failures)
