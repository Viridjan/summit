extends Node
## Four-channel step sequencer. SiON schedules notes on its audio clock.

const EnvironmentMusic := preload("res://scripts/environment_music.gd")

const PRESETS := ["square", "triangle8", "saw", "snare", "closedhh", "bassdrumm", "midi.piano5"]
const INSTRUMENT_NAMES := ["Pulse", "Triangle", "Saw", "Snare", "Hi-hat", "Kick", "FM piano"]
const NOTE_NAMES := ["c", "c+", "d", "d+", "e", "f", "f+", "g", "g+", "a", "a+", "b"]

var driver: SiONDriver
var presets: SiONVoicePresetUtil
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
const TEMPO_SCALE := 0.75  # every song 25% slower
const TRANSPOSE := -4  # every song two whole tones lower (semitones)

const BUS := "Music"
const MUFFLE_HZ := 600.0  # low-pass cutoff while muffled (pause menu, map)

func _ready() -> void:
	presets = SiONVoicePresetUtil.generate_voices()
	driver = SiONDriver.create()
	add_child(driver)
	driver.volume = volume
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = MUFFLE_HZ
		AudioServer.add_bus_effect(i, lp)
		AudioServer.set_bus_effect_enabled(i, 0, false)
	driver.get_audio_player().bus = BUS
	load_demo()

func load_demo() -> void:
	title = "Demo"
	step_length = 16
	patterns = [
		[72, -1, 76, 79, -1, 76, 74, -1, 72, -1, 76, 81, 79, -1, 76, -1],
		[60, 64, 67, 64, 60, 64, 67, 64, 57, 60, 64, 60, 59, 62, 67, 62],
		[48, -1, -1, -1, 48, -1, -1, -1, 45, -1, -1, -1, 43, -1, -1, -1],
		[-1, -1, -1, -1, 48, -1, -1, -1, -1, -1, -1, -1, 48, -1, 48, -1],
	]

func load_environment(key: String) -> void:
	var score := EnvironmentMusic.arrange(key)
	environment = score.environment
	title = score.title
	bpm = score.bpm
	step_length = score.step_length
	patterns = score.patterns
	instruments.assign(score.instruments)
	muted.assign([false, false, false, false])

func follow_environment(key: String) -> void:
	var resolved := key if EnvironmentMusic.SCORES.has(key) else ""
	if playing and environment == resolved and title != "Demo":
		return
	load_environment(resolved)
	play()

func build_mml(loop: bool = true) -> String:
	var headers := ""
	var tracks := ""
	for channel in patterns.size():
		var voice: SiONVoice = presets.get_voice_preset(PRESETS[instruments[channel]])
		headers += voice.get_mml(channel, -1, false)
		tracks += "t%d %%5 @%d v%d q6 l16 %s" % [clampi(roundi(bpm * TEMPO_SCALE), 40, 240), channel, 0 if muted[channel] else 6, "$" if loop else ""]
		for note: int in patterns[channel]:
			if note < 0:
				tracks += "r%d" % step_length
			else:
				var n := clampi(note + TRANSPOSE, 0, 119)
				tracks += "o%d%s%d" % [n / 12, NOTE_NAMES[n % 12], step_length]
		tracks += ";"
	return headers + tracks

func play() -> void:
	driver.volume = volume
	driver.play(build_mml())
	playing = true

func set_muffled(on: bool) -> void:
	if on != muffled:
		muffled = on
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(BUS), 0, on)

func stop() -> void:
	driver.stop()
	playing = false

func _exit_tree() -> void:
	stop()
	presets.free()
