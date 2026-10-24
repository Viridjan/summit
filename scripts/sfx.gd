extends Node
## Original synthesized effects. Cached PCM keeps playback independent of the music synth.
## Parameters: duration, start/end pitch, noise mix, pulse mix.
const SOUNDS := {
	"jump": [0.12, 260, 650, 0.05, 0.25],
	"wall_jump": [0.15, 360, 900, 0.12, 0.3],
	"dash": [0.18, 800, 100, 0.65, 0.15],
	"attack": [0.14, 650, 130, 0.8, 0.05],
	"land": [0.09, 120, 45, 0.6, 0.05],
	"step": [0.045, 170, 70, 0.75, 0.0],
	"climb": [0.08, 230, 90, 0.65, 0.0],
	"spring": [0.3, 180, 1000, 0.05, 0.4],
	"refill": [0.28, 600, 1400, 0.02, 0.15],
	"death": [0.45, 450, 45, 0.45, 0.4],
	"respawn": [0.3, 180, 800, 0.08, 0.15],
	"boost": [0.32, 160, 1200, 0.35, 0.2],
	"dream": [0.28, 800, 1600, 0.1, 0.1],
	"feather": [0.4, 500, 1800, 0.08, 0.05],
	"splash": [0.2, 350, 70, 0.85, 0.0],
	"pickup": [0.3, 700, 1600, 0.0, 0.2],
	"unlock": [0.7, 330, 1320, 0.0, 0.15],
	"door": [0.22, 180, 70, 0.4, 0.2],
	"note": [0.12, 650, 850, 0.0, 0.15],
	"checkpoint": [0.45, 440, 1100, 0.0, 0.2],
	"complete": [0.9, 400, 1600, 0.0, 0.25],
	"enemy_alert": [0.18, 220, 480, 0.1, 0.5],
	"enemy_attack": [0.2, 380, 90, 0.45, 0.3],
	"projectile": [0.16, 900, 240, 0.3, 0.3],
	"enemy_hit": [0.12, 200, 55, 0.65, 0.3],
	"enemy_die": [0.3, 280, 30, 0.6, 0.35],
	"shield": [0.2, 1700, 900, 0.15, 0.2],
	"crumble": [0.25, 110, 35, 0.85, 0.1],
	"mechanism": [0.23, 100, 250, 0.4, 0.5],
	"impact": [0.28, 90, 25, 0.65, 0.2],
	"boss_roar": [0.65, 100, 45, 0.5, 0.5],
	"ui": [0.065, 700, 1000, 0.0, 0.2],
}
const VOICES := 16
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cooldowns: Dictionary = {}
var cursor := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
	for key in SOUNDS:
		streams[key] = _synthesize(SOUNDS[key])
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		voice.volume_db = -10.0
		add_child(voice)
		voices.append(voice)
	set_volume(float(Game.settings.sfx_volume))

func set_volume(value: float) -> void:
	var bus := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(bus, value <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(value, 0.001, 1.0)))

func play(key: String, pitch: float = 1.0) -> void:
	if not streams.has(key):
		return
	var now := Time.get_ticks_msec()
	if now < int(cooldowns.get(key, 0)):
		return
	cooldowns[key] = now + 35
	var voice := voices[cursor]
	cursor = (cursor + 1) % VOICES
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	voice.stream = streams[key]
	voice.pitch_scale = clampf(pitch, 0.5, 2.0)
	voice.play()

func _synthesize(spec: Array) -> AudioStreamWAV:
	var rate := 22050
	var count := int(float(spec[0]) * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919
	var phase := 0.0
	var noise := 0.0
	for i in count:
		var t := float(i) / count
		phase += lerpf(float(spec[1]), float(spec[2]), t) / rate
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.6)
		var tone := sin(phase * TAU)
		tone = lerpf(tone, 1.0 if fposmod(phase, 1.0) < 0.35 else -1.0, float(spec[4]))
		var sample := lerpf(tone, noise, float(spec[3]))
		var envelope := minf(float(i) / (rate * 0.004), 1.0) * pow(1.0 - t, 1.8)
		bytes.encode_s16(i * 2, int(sample * envelope * 22000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
