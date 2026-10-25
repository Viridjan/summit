extends RefCounted
# Original musical scores represented as numbers rather than recordings.
# A degree is a position in a musical scale; pitch() turns it into a semitone-based note number.
# -1 in a melody means rest (silence). Each arranged score has lead, harmony, bass and percussion.
# The music engine turns these patterns into instructions for the SiON synthesizer.
# Reading help: docs/CODE_GUIDE.md.

## Original eight-bar scores. Degrees describe a melody in each environment's mode.
## Adventure-game reference: singable motifs, modal harmony and contrasting regions.
## No third-party melodies, recordings or samples are used.

const KEYS := ["", "forest", "sand", "sea", "cavern", "cavern_deep", "sky", "temple", "building"]
const ALIASES := {"island_shore": "sea", "volcano": "sand", "volcanic_cave": "cavern_deep"}
const TITLES := ["Mountain · First Light", "Forest · Fernway", "Sand · Amber Caravan", "Sea · Lanterns on the Tide", "Cavern · Stone Echoes", "Deep cavern · Below the Lake", "Sky · Cloudward", "Temple · The Quiet Pillars", "Village · Hearthwindows"]
const MAJOR := [0, 2, 4, 5, 7, 9, 11]
const DORIAN := [0, 2, 3, 5, 7, 9, 10]
const MINOR := [0, 2, 3, 5, 7, 8, 10]
const LYDIAN := [0, 2, 4, 6, 7, 9, 11]
const PHRYGIAN := [0, 1, 3, 5, 7, 8, 10]

# Each phrase is two bars in eighth notes. A/B/A'/B' creates an eight-bar loop.
const SCORES := {
	"": {"root": 60, "mode": MAJOR, "bpm": 100, "voices": [0, 6, 1, 4], "chords": [0, 3, 5, 4, 0, 3, 4, 0],
		"a": [0, 2, 4, 4, 5, 4, 2, -1, 1, 2, 3, 2, 1, 0, 1, -1],
		"b": [2, 4, 7, 7, 6, 5, 4, -1, 3, 2, 1, 4, 2, 1, 0, 0]},
	"forest": {"root": 62, "mode": DORIAN, "bpm": 108, "voices": [0, 6, 1, 4], "chords": [0, 3, 6, 0, 5, 3, 4, 0],
		"a": [4, -1, 2, 3, 4, 6, 5, -1, 4, 2, 1, 2, 0, 0, -1, -1],
		"b": [2, 3, 4, 7, 6, -1, 5, 4, 3, 5, 4, 2, 1, 2, 0, -1]},
	"sand": {"root": 62, "mode": PHRYGIAN, "bpm": 116, "voices": [0, 2, 1, 5], "chords": [0, 1, 0, 6, 0, 3, 1, 0],
		"a": [0, 1, 4, -1, 3, 1, 0, -1, 1, 3, 4, 5, 4, 3, 1, -1],
		"b": [7, 6, 4, -1, 5, 4, 3, 1, 3, -1, 1, 0, 1, 1, 0, -1]},
	"sea": {"root": 65, "mode": MAJOR, "bpm": 84, "voices": [6, 0, 1, 4], "chords": [0, 5, 3, 4, 0, 2, 3, 0],
		"a": [2, 2, 4, 5, 4, 4, 2, -1, 1, 1, 3, 4, 2, 2, 0, -1],
		"b": [4, 4, 5, 7, 6, 5, 4, -1, 3, 3, 2, 1, 2, 2, 0, 0]},
	"cavern": {"root": 57, "mode": MINOR, "bpm": 68, "voices": [6, 1, 1, 4], "chords": [0, 0, 5, 3, 0, 6, 4, 0],
		"a": [0, 0, -1, -1, 4, 4, -1, -1, 2, 2, -1, 1, 0, 0, -1, -1],
		"b": [5, 5, -1, -1, 4, 2, -1, -1, 1, 1, 2, -1, 0, 0, -1, -1]},
	"cavern_deep": {"root": 54, "mode": PHRYGIAN, "bpm": 56, "voices": [1, 6, 1, 5], "chords": [0, 1, 0, 5, 0, 1, 6, 0],
		"a": [0, 0, 0, -1, -1, -1, 1, -1, 4, 4, -1, -1, 3, -1, 1, -1],
		"b": [5, 5, -1, -1, 4, 4, -1, 1, 0, 0, -1, -1, 1, -1, 0, -1]},
	"sky": {"root": 67, "mode": LYDIAN, "bpm": 96, "voices": [0, 6, 1, 4], "chords": [0, 1, 4, 0, 5, 1, 4, 0],
		"a": [0, 4, 7, 7, 6, 4, 3, -1, 2, 4, 6, 7, 5, 4, 2, -1],
		"b": [7, 6, 4, 3, 4, 5, 7, -1, 6, 4, 3, 2, 1, 2, 0, 0]},
	"temple": {"root": 60, "mode": DORIAN, "bpm": 72, "voices": [1, 6, 1, 5], "chords": [0, 3, 0, 6, 3, 5, 4, 0],
		"a": [0, 0, 4, 4, -1, 3, 2, -1, 1, 1, 5, 5, -1, 4, 3, -1],
		"b": [2, 2, 6, 6, 5, 4, -1, -1, 3, 3, 2, 1, 0, 0, 0, -1]},
	"building": {"root": 60, "mode": MAJOR, "bpm": 104, "voices": [6, 0, 1, 4], "chords": [0, 3, 0, 4, 5, 3, 4, 0],
		"a": [2, 4, 2, 0, 1, 2, 3, -1, 4, 5, 4, 2, 1, 1, 0, -1],
		"b": [5, 4, 2, -1, 3, 2, 0, 1, 2, 3, 4, 1, 2, 1, 0, 0]},
}

# Convert a scale degree, including degrees beyond one octave, into an absolute semitone note number.
static func pitch(root: int, mode: Array, degree: int) -> int:
	return root + int(mode[posmod(degree, 7)]) + int(floorf(degree / 7.0)) * 12

# Expand a score into 64 steps of melody, harmony, bass and percussion for the music engine.
static func arrange(environment: String) -> Dictionary:
	var key: String = ALIASES.get(environment, environment)
	if not SCORES.has(key): key = ""
	var score: Dictionary = SCORES[key]
	var melody: Array = score.a + score.b + score.a + score.b
	var tracks: Array = [[], [], [], []]
	var quiet: bool = key in ["cavern", "cavern_deep", "temple"]
	for step in 64:
		var bar := step / 8
		var beat := step % 8
		var chord: int = score.chords[bar]
		var degree: int = melody[step]
		# The second answer rises briefly, then resolves to the tonic for the loop.
		if step == 51 and degree >= 0:
			degree += 2
		tracks[0].append(-1 if degree < 0 else pitch(score.root + 12, score.mode, degree))
		var arp: int = [0, 2, 4, 2, 0, 2, 4, 6][beat]
		tracks[1].append(-1 if quiet and beat % 2 == 1 else pitch(score.root, score.mode, chord + arp))
		tracks[2].append(pitch(score.root - 12, score.mode, chord if beat < 4 else chord + 4) if beat in [0, 4] else -1)
		tracks[3].append(36 if (beat == 0 and bar % 2 == 0 if quiet else beat in [2, 6]) else -1)
	return {"environment": environment if ALIASES.has(environment) else key, "title": TITLES[KEYS.find(key)], "bpm": score.bpm,
		"instruments": score.voices.duplicate(), "patterns": tracks, "step_length": 8}
