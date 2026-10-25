extends RefCounted
# Original side-view Ape pixel art, shared by the arena boss and the Sand Cave chase.
# Coordinates describe a 32x32 image facing right; the entity mirrors it when facing left.
# Polygons form body parts and small rectangles add brows, fur highlights and knuckle details.
# Images are CPU-side editable pixels; ImageTexture converts an image into something Godot can draw.
# The texture cache uses a canonical animation frame so repeated loops reuse identical artwork.
# Reading help: docs/CODE_GUIDE.md.

## Original 32px side-view gorilla. Faces right; the entity mirrors the whole pose.
const INK := Color("241f23")
const SHADOW := Color("3c3030")
const FUR := Color("624638")
const LIGHT := Color("876047")
const RIDGE := Color("a17a58")
const SKIN := Color("b58d6b")
const SKIN_DARK := Color("775b4e")
static var _textures: Dictionary = {}

# Run is a 4-frame loop; other poses are still. Canonical frame feeds both the key and build().
# Normalize pose/frame cache identity and reuse its generated GPU texture.
static func texture(pose: String, frame: int) -> Texture2D:
	frame = posmod(frame, 4) if pose == "run" else 0
	var key := "%s:%d" % [pose, frame]
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(build(pose, frame))
	return _textures[key]

# Fill pixels whose centres lie inside a polygon, producing sharp original pixel-art body parts.
static func poly(img: Image, points: Array, color: Color) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(Vector2(point[0], point[1]))
	for y in 32:
		for x in 32:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon):
				img.set_pixel(x, y, color)

# Fill a small detail rectangle clipped to the 32px image bounds.
static func box(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, 32, 32))
	if r.has_area():
		img.fill_rect(r, color)

# Compose one right-facing pose from shaded body polygons and face/hand details.
static func build(pose: String, frame: int) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var drop := 3 if pose == "crouch" else 1 if pose == "run" and frame % 2 else 0
	var lift := -3 if pose == "air" else 0
	# Rear haunch and foot, behind the silverback's sloping trunk.
	poly(img, [[3,17+drop],[11,17],[14,24],[10,29+lift],[13,30+lift],[13,32+lift],[4,32+lift],[3,28],[5,24]], INK)
	poly(img, [[5,18+drop],[10,19],[11,24],[7,28+lift],[6,30+lift],[4,30+lift],[5,25]], SHADOW)
	# Far arm and hand are deliberately darker than the near shoulder.
	poly(img, [[18,11+drop],[23,13+drop],[24,22],[29,27+lift],[29,30+lift],[23,30+lift],[20,25],[17,18]], INK)
	poly(img, [[19,14+drop],[22,15],[22,22],[26,27+lift],[24,28+lift],[20,23]], SHADOW)
	# Hunched back, massive shoulders and narrower waist.
	poly(img, [[2,19+drop],[3,12+drop],[7,7+drop],[13,4+drop],[20,5+drop],[25,10+drop],[24,18+drop],[18,24],[9,26],[4,24]], INK)
	poly(img, [[3,18+drop],[5,12+drop],[9,8+drop],[15,6+drop],[20,7+drop],[23,11+drop],[22,18+drop],[17,22],[9,24],[5,22]], FUR)
	poly(img, [[5,13+drop],[10,8+drop],[16,6+drop],[19,8+drop],[13,10+drop],[9,14+drop],[8,19+drop],[5,21+drop]], LIGHT)
	box(img, 8, 10+drop, 2, 2, RIDGE)
	box(img, 5, 15+drop, 2, 3, RIDGE)
	# Profile: low cranium, brow ridge, a single visible eye and protruding muzzle.
	poly(img, [[17,2+drop],[23,2+drop],[26,5+drop],[26,8+drop],[30,10+drop],[31,14+drop],[28,17+drop],[22,16+drop],[18,12+drop],[16,7+drop]], INK)
	poly(img, [[18,3+drop],[22,3+drop],[24,5+drop],[24,9+drop],[21,12+drop],[18,10+drop],[17,6+drop]], FUR)
	box(img, 18, 4+drop, 4, 1, LIGHT)
	box(img, 18, 8+drop, 2, 3, SKIN_DARK) # ear
	box(img, 19, 9+drop, 1, 1, SKIN)
	poly(img, [[23,8+drop],[26,9+drop],[29,10+drop],[30,13+drop],[28,15+drop],[23,14+drop],[21,11+drop]], SKIN_DARK)
	box(img, 25, 10+drop, 4, 3, SKIN)
	box(img, 27, 10+drop, 3, 1, INK) # nostril
	box(img, 23, 7+drop, 4, 2, INK) # heavy brow
	box(img, 24, 8+drop, 1, 1, Color("edc578"))
	box(img, 26, 14+drop, 3, 1, INK)
	if pose == "scream":
		box(img, 25, 12+drop, 6, 5, INK)
		box(img, 26, 12+drop, 4, 1, Color("e6d4ad"))
		box(img, 26, 16+drop, 4, 1, Color("b37665"))
	# Forearm bends and grounded knuckles carry the weight; throw reaches overhead.
	if pose == "throw":
		poly(img, [[14,13],[12,9],[15,4],[19,0],[23,0],[23,4],[19,7],[19,14]], INK)
		poly(img, [[15,12],[14,9],[17,5],[20,2],[22,2],[21,4],[17,8],[18,12]], LIGHT)
		box(img, 19, 0, 7, 3, SKIN_DARK)
	elif pose == "air":
		poly(img, [[13,13],[18,12],[21,16],[20,22],[25,22],[26,26],[20,28],[16,24],[15,19],[11,17]], INK)
		poly(img, [[14,14],[17,14],[19,17],[18,23],[22,25],[20,26],[17,23],[16,18],[13,17]], LIGHT)
		box(img, 21, 23, 4, 3, SKIN_DARK)
	else:
		var swing: int = [-2, 0, 2, 0][posmod(frame, 4)] if pose == "run" else 0
		poly(img, [[12,12+drop],[17,11+drop],[21,14+drop],[21,20],[18+swing,26],[23+swing,28],[23+swing,32],[15+swing,32],[12+swing,29],[14,23],[12,19],[10,16]], INK)
		poly(img, [[13,13+drop],[17,13+drop],[19,15+drop],[19,20],[16+swing,26],[15+swing,29],[14+swing,28],[16,22],[14,19],[12,16]], FUR)
		box(img, 14, 14+drop, 3, 2, LIGHT)
		box(img, 16, 17+drop, 2, 3, LIGHT)
		box(img, 16+swing, 28, 6, 3, SKIN_DARK)
		for finger in 3:
			box(img, 17+swing+finger*2, 29, 1, 1, SKIN)
	# Short fur ridges follow the back rather than random single-pixel noise.
	box(img, 8, 17+drop, 1, 3, SHADOW)
	box(img, 10, 19+drop, 1, 3, SHADOW)
	return img
