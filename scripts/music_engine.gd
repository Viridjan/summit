extends Node
# One persistent SiON synthesizer shared by the game and music studio.
# Patterns contain note numbers and -1 rests; build_mml() translates them into a compact music language.
# The synthesizer schedules notes on the audio clock instead of relying on frame timing.
# A separate Music audio bus provides volume and a low-pass effect (muffled sound while paused).
# Written score tempo/pitch and playback tempo/transposition are deliberately separate.
# Reading help: docs/CODE_GUIDE.md.

## Four-channel step sequencer. SiON schedules notes on its audio clock.

const Audio := preload("res://scripts/audio.gd")

const EnvironmentMusic := preload("res://scripts/environment_music.gd")

const PRESETS := ["square", "triangle8", "saw", "snare", "closedhh", "bassdrumm", "midi.piano5"]
const INSTRUMENT_NAMES := ["Pulse", "Triangle", "Saw", "Snare", "Hi-hat", "Kick", "FM piano"]
const NOTE_NAMES := ["c", "c+", "d", "d+", "e", "f", "f+", "g", "g+", "a", "a+", "b"]

# The SiON synth is a native add-on built for Linux only; elsewhere (web, Windows...) the engine plays each
# song's recording instead (assets/music, made by tools/bake_music.gd), so patterns edited in the studio
# don't sound there. SiON classes are reached by name so this script loads without the add-on.
var synth := ClassDB.class_exists("SiONDriver") and OS.get_environment("SUMMIT_NO_SYNTH") == ""
var driver  # SiONDriver
var presets  # SiONVoicePresetUtil
var baked: AudioStreamPlayer  # without the synth
var patterns: Array = []
var instruments: Array[int] = [0, 2, 1, 3]
var muted: Array[bool] = [false, false, false, false]
var bpm := 112
var volume := 0.3
var playing := false
var environment := ""
var title := "Demo"
var step_length := 16
var muffled := false

# Applied when playing, so scores and the studio keep their written tempo and notes.
const TEMPO_SCALE := 0.6  # every song 40% slower (25%, then another 20%)
const TRANSPOSE := -4  # every song two whole tones lower (semitones)

const BUS := "Music"
const MUFFLE_HZ := 600.0  # low-pass cutoff while muffled (pause menu, map)

# Create the single SiON driver, prepare its voices and Music bus, then load the initial demo.
func _ready() -> void:
	if synth:
		presets = ClassDB.class_call_static("SiONVoicePresetUtil", "generate_voices")
		driver = ClassDB.class_call_static("SiONDriver", "create")
		add_child(driver)
		driver.volume = volume
	else:
		baked = AudioStreamPlayer.new()
		add_child(baked)
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = MUFFLE_HZ
		AudioServer.add_bus_effect(i, lp)
		AudioServer.set_bus_effect_enabled(i, 0, false)
	(driver.get_audio_player() if synth else baked).bus = BUS
	set_level(float(Game.settings.music_volume))
	load_demo()

# Replace the editable patterns with the original four-channel demo.
func load_demo() -> void:
	title = "Demo"
	step_length = 16
	patterns = [
		[72, -1, 76, 79, -1, 76, 74, -1, 72, -1, 76, 81, 79, -1, 76, -1],
		[60, 64, 67, 64, 60, 64, 67, 64, 57, 60, 64, 60, 59, 62, 67, 62],
		[48, -1, -1, -1, 48, -1, -1, -1, 45, -1, -1, -1, 43, -1, -1, -1],
		[-1, -1, -1, -1, 48, -1, -1, -1, -1, -1, -1, -1, 48, -1, 48, -1],
	]

# Convert the chosen environment score into channel patterns, instrument choices and written tempo.
func load_environment(key: String) -> void:
	var score := EnvironmentMusic.arrange(key)
	environment = score.environment
	title = score.title
	bpm = score.bpm
	step_length = score.step_length
	patterns = score.patterns
	instruments.assign(score.instruments)
	muted.assign([false, false, false, false])

# Keep a matching song playing across room changes; load and start another only when needed.
func follow_environment(key: String) -> void:
	var resolved := key if EnvironmentMusic.SCORES.has(key) else ""
	if playing and environment == resolved and title != "Demo":
		return
	load_environment(resolved)
	play()

# Translate channel patterns to SiON Music Macro Language, applying playback tempo and note transposition.
# MML examples: t sets tempo, o selects octave, note names select pitch, r means rest and ; ends a channel.
func build_mml(loop: bool = true) -> String:
	var headers := ""
	var tracks := ""
	for channel in patterns.size():
		var voice = presets.get_voice_preset(PRESETS[instruments[channel]])
		headers += voice.get_mml(channel, -1, false)
		tracks += "t%d %%5 @%d v%d q6 l16 %s" % [clampi(roundi(bpm * TEMPO_SCALE), 20, 240), channel, 0 if muted[channel] else 6, "$" if loop else ""]
		for note: int in patterns[channel]:
			if note < 0:
				tracks += "r%d" % step_length
			else:
				var n := clampi(note + TRANSPOSE, 0, 119)
				tracks += "o%d%s%d" % [n / 12, NOTE_NAMES[n % 12], step_length]
		tracks += ";"
	return headers + tracks

# Start/restart synthesis using the current pattern data and driver volume.
func play() -> void:
	playing = true
	if not synth:
		var path := baked_path(environment)
		if ResourceLoader.exists(path):
			var stream: AudioStreamWAV = load(path)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
			baked.stream = stream
			baked.play()
		return
	driver.volume = volume
	driver.play(build_mml())

# The recording of an environment's song ("" is the mountain).
static func baked_path(key: String) -> String:
	return "res://assets/music/%s.wav" % (key if key != "" else "mountain")

# The Options music volume (0..1) on the Music bus; 0 mutes it.
# Apply the user music volume on its dedicated audio bus without changing effect volume.
func set_level(value: float) -> void:
	Audio.set_bus_volume(BUS, value)

# Toggle the Music bus low-pass filter only when pause/map state actually changes.
func set_muffled(on: bool) -> void:
	if on != muffled:
		muffled = on
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(BUS), 0, on)

# Stop synthesis and clear the transport flag used by gameplay and studio controls.
func stop() -> void:
	if synth:
		driver.stop()
	else:
		baked.stop()
	playing = false

# Stop the driver and release the manually owned preset utility during shutdown.
func _exit_tree() -> void:
	stop()
	if presets != null:
		presets.free()
