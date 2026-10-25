extends RefCounted
# Creates connected-looking artwork for platforms and special blocks of different sizes.
# Drawing one complete piece avoids outlining every tile inside a larger block.
# Small clipped rectangles keep partial tiles and narrow platforms inside their requested image.
# Cache keys include the style, dimensions and damage state so equal blocks share a texture.
# Reading help: docs/CODE_GUIDE.md.

# Original 1:1 pixel artwork. One perimeter per object, never a box around each tile.
# Textures are shared by material/size/damage; movement and shaking do not rebake them.
const STYLES := ["breakwall", "crumble", "falling", "zip", "dream", "jumpthru"]
# body, shadow, highlight, outer rim, accent
const PALETTES := {
	"breakwall": [Color("8c7663"), Color("645753"), Color("d4b987"), Color("443d43"), Color("bca17b")],
	"crumble": [Color("927d70"), Color("655e63"), Color("d9bc96"), Color("4c4550"), Color("b49a7c")],
	"falling": [Color("525f7c"), Color("3e475f"), Color("a6acc2"), Color("2c344c"), Color("c2ac83")],
	"zip": [Color("384859"), Color("293545"), Color("d6b96e"), Color("202b3e"), Color("8b815e")],
	"dream": [Color("152638"), Color("102033"), Color("87d4ca"), Color("375969"), Color("4a8b9e")],
	"jumpthru": [Color("75685e"), Color("514f57"), Color("9ac6d2"), Color("37465c"), Color("b3a387")],
}
const GLYPHS := {
	"breakwall": ["   xx   ", "    x   ", "   x    ", "  xx    ", "    x   ", "   x    ", "  x     ", "        "],
	"crumble": ["        ", " xxxxx  ", "    x   ", "   xx   ", "  x     ", " xxxxx  ", "        ", "        "],
	"falling": ["   xx   ", "   xx   ", "   xx   ", " xxxxxx ", "  xxxx  ", "   xx   ", "        ", "        "],
	"zip": ["  x  x  ", " xxxxxx ", "xx    xx", " x xx x ", " x xx x ", "xx    xx", " xxxxxx ", "  x  x  "],
}
const SMALL_GLYPHS := {
	"breakwall": [" xx ", "  x ", " x  ", "  x "],
	"crumble": ["xxx ", " x  ", "  x ", " xxx"],
	"falling": [" x  ", " x  ", "xxx ", " x  "],
	"zip": [" xx ", "x  x", "x  x", " xx "],
}
const CACHE_PIXEL_BUDGET := 1048576
static var _textures: Dictionary = {}
static var _cached_pixels := 0

# Fill only the part of a detail rectangle that fits inside the block image.
static func _fill(img: Image, rect: Rect2i, color: Color) -> void:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if area.has_area(): img.fill_rect(area, color)

# Draw a whole connected platform/block image with style-specific edges and damage markings.
static func build_piece(style: String, size: Vector2i, damage := 0) -> Image:
	var img := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	var colors: Array = PALETTES[style]
	var width := img.get_width()
	var height := img.get_height()
	img.fill(colors[0])
	# Repeat material grain inside a SINGLE border. There are no per-cell outlines.
	for y in range(2, height - 2):
		for x in range(2, width - 2):
			var grain := (x * 13 + y * 7) % 29
			match style:
				"breakwall":
					if y % 8 == 4 or (x + (y / 8 % 2) * 8) % 16 == 0:
						img.set_pixel(x, y, colors[1])
					elif grain == 0: img.set_pixel(x, y, colors[4])
				"crumble":
					if y % 4 == 3: img.set_pixel(x, y, colors[1])
					elif (x + (y / 4) * 3) % 11 == 0: img.set_pixel(x, y, colors[4])
				"falling":
					if x % 8 in [3, 4]: img.set_pixel(x, y, colors[1])
				"zip":
					if (x + y) % 8 == 0: img.set_pixel(x, y, colors[1])
				"dream":
					if grain == 0: img.set_pixel(x, y, colors[1])
				"jumpthru":
					if x % 8 == 4: img.set_pixel(x, y, colors[1])
	# Coherent bevels: top/left light, bottom/right shadow, four corner joints.
	_fill(img, Rect2i(0, 0, width, 1), colors[2])
	_fill(img, Rect2i(0, 1, 1, height - 1), colors[2].darkened(0.18))
	_fill(img, Rect2i(0, height - 1, width, 1), colors[3])
	_fill(img, Rect2i(width - 1, 0, 1, height), colors[3])
	if width >= 4 and height >= 4:
		_fill(img, Rect2i(1, 1, width - 2, 1), colors[4])
		_fill(img, Rect2i(1, height - 2, width - 2, 1), colors[1])
		for corner in [Vector2i.ZERO, Vector2i(width - 2, 0), Vector2i(0, height - 2), Vector2i(width - 2, height - 2)]:
			_fill(img, Rect2i(corner, Vector2i(2, 2)), colors[3])
			img.set_pixelv(corner + Vector2i(1, 1) if corner == Vector2i.ZERO else corner, colors[4])
	if width >= 14 and height >= 12:
		for point in [Vector2i(3, 3), Vector2i(width - 4, 3), Vector2i(3, height - 4), Vector2i(width - 4, height - 4)]:
			img.set_pixelv(point, colors[2] if style in ["falling", "zip"] else colors[4])
	# A single central symbol, not an icon stamped on every block in the structure.
	if GLYPHS.has(style) and width >= 6 and height >= 6:
		var glyph: Array = GLYPHS[style] if width >= 12 and height >= 10 else SMALL_GLYPHS[style]
		var glyph_size := glyph.size()
		var origin := Vector2i((width - glyph_size) / 2, (height - glyph_size) / 2)
		for y in glyph_size:
			for x in glyph_size:
				if glyph[y][x] == "x":
					img.set_pixelv(origin + Vector2i(x, y), colors[3] if style in ["breakwall", "crumble"] else colors[2])
	if style in ["breakwall", "crumble"] and damage > 0 and width >= 6 and height >= 6:
		var start_x := width / 2
		for y in range(2, height - 2):
			var x := clampi(start_x + (y / 3 % 3) - 1, 2, width - 3)
			img.set_pixel(x, y, colors[3])
			if damage > 1 and y % 3 == 0:
				_fill(img, Rect2i(maxi(2, x - 3), y, 4, 1), colors[3])
	return img

# Reuse complete block artwork for identical style, size and damage settings.
static func texture(style: String, size: Vector2i, damage := 0) -> Texture2D:
	var key := "%s:%d:%d:%d" % [style, size.x, size.y, damage]
	if _textures.has(key):
		var cached: Texture2D = _textures[key]
		_textures.erase(key)
		_textures[key] = cached  # insertion order is the LRU order
		return cached
	var area := maxi(1, size.x) * maxi(1, size.y)
	while not _textures.is_empty() and _cached_pixels + area > CACHE_PIXEL_BUDGET:
		var first = _textures.keys()[0]
		var oldest: Texture2D = _textures[first]
		_cached_pixels -= oldest.get_width() * oldest.get_height()
		_textures.erase(first)
	var result := ImageTexture.create_from_image(build_piece(style, size, damage))
	_textures[key] = result
	_cached_pixels += area
	return result

# Place the cached block image at its world rectangle, including any visual shake offset.
static func draw(ci: CanvasItem, rect: Rect2i, style: String, offset := Vector2.ZERO, damage := 0) -> void:
	var image := texture(style, rect.size, damage)
	# Retained canvas commands use texture RIDs: keep every texture from this draw
	# alive even if another piece evicts it from the shared size cache.
	var frame := Engine.get_process_frames()
	if ci.get_meta("_block_art_frame", -1) != frame:
		ci.set_meta("_block_art_frame", frame)
		ci.set_meta("_block_art_textures", {})
	var retained: Dictionary = ci.get_meta("_block_art_textures")
	retained[image.get_instance_id()] = image
	ci.draw_texture(image, Vector2(rect.position) + offset.round())
