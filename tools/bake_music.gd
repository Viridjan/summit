extends SceneTree
## Records every environment song for builds without the SiON synth (web, non-Linux): one seamless loop each,
## 22050 Hz mono 16-bit WAV in assets/music/. Needs the synth (Linux). Rerun after changing the scores, the
## tempo/transpose or the instruments:  godot --headless --path . --script tools/bake_music.gd
## The loop is the second of two rendered passes, so notes ringing over the loop point are already in it.
const OUT := "res://assets/music/"
const RATE := 22050

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	var engine = game.get_music_engine()
	if not engine.synth:
		push_error("bake_music needs the SiON synth (Linux build)")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var gain: float = await _live_gain(engine)
	for key in engine.EnvironmentMusic.KEYS:
		engine.load_environment(key)
		var tempo: int = clampi(roundi(engine.bpm * engine.TEMPO_SCALE), 20, 240)
		var secs: float = engine.patterns[0].size() * (4.0 / engine.step_length) * 60.0 / tempo
		var n := int(round(secs * 44100.0))
		var s: PackedFloat64Array = engine.driver.render(engine.build_mml(true), n * 4, 2)  # values: 2 passes x n frames x 2 channels
		assert(s.size() >= n * 4, "render returned %d values, wanted %d" % [s.size(), n * 4])
		var pcm := PackedByteArray()
		pcm.resize(n / 2 * 2)
		for i in n / 2:  # second pass, both channels and sample pairs averaged: 44.1 kHz stereo -> 22.05 kHz mono
			var j := (n + i * 2) * 2
			var v := (s[j] + s[j + 1] + s[j + 2] + s[j + 3]) * 0.25 * gain
			pcm.encode_s16(i * 2, clampi(roundi(v * 32767.0), -32768, 32767))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.stereo = false
		wav.data = pcm
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = n / 2
		var path: String = engine.baked_path(key)
		wav.save_to_wav(path)
		print("baked %s: %.1f s" % [path, secs])
	game.quit_game()

# render() ignores the driver's volume and the bus: match what the live synth sends to the Music bus by
# comparing a short live recording (Music bus at 0 dB) with a render of the same song.
func _live_gain(engine) -> float:
	engine.load_environment("forest")
	var bus := AudioServer.get_bus_index("Music")
	var keep_db := AudioServer.get_bus_volume_db(bus)
	var keep_mute := AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.set_bus_mute(bus, false)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus, rec)
	rec.set_recording_active(true)
	engine.play()
	await create_timer(4.0).timeout
	rec.set_recording_active(false)
	engine.stop()
	var live: AudioStreamWAV = rec.get_recording()
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	AudioServer.set_bus_volume_db(bus, keep_db)
	AudioServer.set_bus_mute(bus, keep_mute)
	var live_rms := 0.0
	var d := live.data
	for i in range(0, d.size(), 2):
		live_rms += pow(d.decode_s16(i) / 32768.0, 2)
	live_rms = sqrt(live_rms / (d.size() / 2))
	var s: PackedFloat64Array = engine.driver.render(engine.build_mml(true), 44100 * 8, 2)
	var r_rms := 0.0
	for v in s:
		r_rms += v * v
	r_rms = sqrt(r_rms / s.size())
	print("live rms %.4f, render rms %.4f" % [live_rms, r_rms])
	return live_rms / r_rms if r_rms > 0.0 else 1.0
