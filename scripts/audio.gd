extends RefCounted
# Small shared audio operations, used by the music engine and sound-effects service.
# These helpers do not own a player, synth or bus: their callers manage those lifetimes.
# Keeping volume conversion and WAV setup here prevents the two services drifting apart.
# Reading help: docs/CODE_GUIDE.md.

# Set a named, already-created bus from a 0..1 slider value. Zero mutes it explicitly;
# the small positive floor avoids asking the logarithm to convert zero into decibels.
static func set_bus_volume(bus_name: String, value: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(bus, value <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(value, 0.001, 1.0)))

# Wrap existing signed 16-bit PCM bytes without changing their samples.
# sample_rate is samples per second. Stereo data alternates left/right samples;
# mono uses one sample per instant. The caller has already generated that layout.
static func pcm16(data: PackedByteArray, sample_rate: int, stereo: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = stereo
	stream.data = data
	return stream
