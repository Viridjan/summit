extends RefCounted
## Pixel-art button prompts, generated: a keycap with the bound key for keyboard, the bound button for a pad
## (Xbox-coloured A/B/X/Y circles, shoulders, triggers, d-pad). prompt(action) follows the last device used.
const INK := Color("1a1a22")
const CAP := Color("eae6dc")
const CAP_SIDE := Color("9c968a")
const PAD_BODY := Color("3a3a46")
const FACE := {JOY_BUTTON_A: ["A", Color("4caf50")], JOY_BUTTON_B: ["B", Color("e0483e")],
	JOY_BUTTON_X: ["X", Color("3a7bd5")], JOY_BUTTON_Y: ["Y", Color("f0c419")]}
const PAD_TEXT := {JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "BK", JOY_BUTTON_START: "ST", JOY_BUTTON_GUIDE: "H",
	JOY_BUTTON_DPAD_UP: "^", JOY_BUTTON_DPAD_DOWN: "v", JOY_BUTTON_DPAD_LEFT: "<", JOY_BUTTON_DPAD_RIGHT: ">"}
const PS_TEXT := {JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_BACK: "SH",
	JOY_BUTTON_START: "OP", JOY_BUTTON_GUIDE: "PS"}
# PlayStation face symbols (5x5, centred on a dark disc) and their colours.
const PS_FACE := {
	JOY_BUTTON_A: ["1000101010001000101010001", Color("7aa7e8")],  # cross
	JOY_BUTTON_B: ["0111010001100011000101110", Color("e8605a")],  # circle
	JOY_BUTTON_X: ["1111110001100011000111111", Color("e48ac4")],  # square
	JOY_BUTTON_Y: ["0010000100010100101011111", Color("4cc4a0")],  # triangle
}
# 3x5 glyphs, rows top to bottom; arrows are ^ v < >.
const FONT := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
	"2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
	"6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
	"^": "010111010010010", "v": "010010010111010", "<": "001011111011001", ">": "100110111110100",
}
static var _cache := {}

# The prompt for an action on the device the player last used.
static func prompt(action: String) -> Texture2D:
	if Game.using_pad:
		return pad(int(Game.settings.pad[action]))
	return key(int(Game.settings.keys[action]))

# A keycap: the key's letter, an arrow, or its name's first 3 letters ("SPA", "SHI", "F1").
static func key(code: int) -> Texture2D:
	var name := OS.get_keycode_string(code).to_upper()
	var text: String = {"UP": "^", "DOWN": "v", "LEFT": "<", "RIGHT": ">"}.get(name, "")
	if text == "":
		for ch in name:
			if FONT.has(ch) and ch not in "^v<>":
				text += ch
		text = text.substr(0, 3) if text != "" else "?"
	return _cached("k:" + text, func(): return _keycap(text))

# ps: PlayStation look (cross/circle/square/triangle, L1/R1/L2/R2, Options/Share) instead of Xbox.
static func pad(button: int, ps := Game.pad_ps) -> Texture2D:
	var k := "p%s:%d" % ["s" if ps else "x", button]
	if FACE.has(button):
		if ps:
			return _cached(k, func(): return _ps_face(button))
		return _cached(k, func(): return _face(FACE[button][0], FACE[button][1]))
	var text: String = (PS_TEXT if ps else PAD_TEXT).get(button, PAD_TEXT.get(button, ""))
	if button == Game.PAD_AXIS + JOY_AXIS_TRIGGER_LEFT:
		text = "L2" if ps else "LT"
	elif button == Game.PAD_AXIS + JOY_AXIS_TRIGGER_RIGHT:
		text = "R2" if ps else "RT"
	return _cached(k, func(): return _pill(text if text != "" else "?"))

static func _cached(k: String, make: Callable) -> Texture2D:
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(make.call())
	return _cache[k]

static func _text(img: Image, text: String, x: int, y: int, c: Color) -> void:
	for ch in text:
		var g: String = FONT.get(ch, FONT["0"])
		for i in 15:
			if g[i] == "1":
				img.set_pixel(x + i % 3, y + i / 3, c)
		x += 4

# Light keycap with a darker front edge (keyboard).
static func _keycap(text: String) -> Image:
	var w := 4 * text.length() + 3
	var img := Image.create(w, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	img.fill_rect(Rect2i(1, 0, w - 2, 10), INK)
	img.fill_rect(Rect2i(0, 1, w, 8), INK)
	img.fill_rect(Rect2i(1, 1, w - 2, 8), CAP_SIDE)
	img.fill_rect(Rect2i(1, 1, w - 2, 7), CAP)
	_text(img, text, 2, 2, INK)
	return img

# Round coloured face button with a white letter (pad A/B/X/Y).
static func _face(letter: String, c: Color) -> Image:
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in 11:
		for x in 11:
			var dd := Vector2(x - 5, y - 5).length()
			if dd <= 5.4:
				img.set_pixel(x, y, INK if dd > 4.4 else c)
	_text(img, letter, 4, 3, Color.WHITE)
	return img

# Dark disc with the coloured PlayStation symbol.
static func _ps_face(button: int) -> Image:
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in 11:
		for x in 11:
			var dd := Vector2(x - 5, y - 5).length()
			if dd <= 5.4:
				img.set_pixel(x, y, INK if dd > 4.4 else PAD_BODY)
	var g: String = PS_FACE[button][0]
	for i in 25:
		if g[i] == "1":
			img.set_pixel(3 + i % 5, 3 + i / 5, PS_FACE[button][1])
	return img

# Dark rounded pill for shoulders, triggers, sticks, d-pad and menu buttons.
static func _pill(text: String) -> Image:
	var w := 4 * text.length() + 3
	var img := Image.create(w, 9, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	img.fill_rect(Rect2i(1, 0, w - 2, 9), INK)
	img.fill_rect(Rect2i(0, 1, w, 7), INK)
	img.fill_rect(Rect2i(1, 1, w - 2, 7), PAD_BODY)
	_text(img, text, 2, 2, Color.WHITE)
	return img
