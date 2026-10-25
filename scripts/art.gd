extends RefCounted
# Shared drawing helpers for terrain and the original Paper Pixels sprite sheet.
# An atlas is one image containing many small pictures; a region selects one picture from it.
# The helpers only draw: the tile grid and entity rectangles still decide physical collisions.
# Caches reuse textures instead of creating the same image for every frame or object.
# Reading help: docs/CODE_GUIDE.md.

# Sprite drawing helpers for the Paper Pixels pack (CC0, VEXED) in assets/paper-pixels.
# Sheet coordinates below are 8x8 cells unless noted as pixel rects.

const EnvironmentArt := preload("res://scripts/environment_art.gd")

const TILES := preload("res://assets/paper-pixels/Tiles.png")
const PLAYER := preload("res://assets/paper-pixels/Player.png")
const T := 8

const SKY := Color("1b2036")
const FILL := Color("2a3150")
const BOTTOM_EDGE := Color("404960")

# ground autotile pieces
const TOP_EDGES := [Vector2i(4, 6), Vector2i(5, 6)]
const CORNER_TL := Vector2i(3, 6)
const CORNER_TR := Vector2i(6, 6)
const EDGE_L := Vector2i(2, 8)
const EDGE_R := Vector2i(7, 8)
const TEXTURES := [Vector2i(4, 8), Vector2i(5, 8), Vector2i(4, 9), Vector2i(5, 9), Vector2i(4, 12), Vector2i(5, 12)]
const GRASS := [Vector2i(3, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(5, 5), Vector2i(6, 5)]
const FLOWERS := [Vector2i(2, 5), Vector2i(7, 5), Vector2i(7, 6), Vector2i(2, 6)]
const RAIL := Vector2i(2, 18)
const STONE := Vector2i(0, 18)
const STONE_2 := Vector2i(9, 18)

# background sprites (pixel rects)
const MOON := Rect2(42, 4, 35, 17)
const CLOUDS := [Rect2(82, 2, 29, 12), Rect2(113, 3, 21, 11), Rect2(81, 18, 54, 12), Rect2(83, 34, 28, 12)]
const TREES := [Rect2(9, 100, 15, 38), Rect2(26, 106, 13, 32), Rect2(41, 97, 15, 40), Rect2(58, 101, 13, 36)]

# player sheet rows (facing right): run 8 frames, idle 4, jump 4
const RUN_ROW := 1
const IDLE_ROW := 7
const JUMP_ROW := 10
const HAIR_COLORS := [Color8(118, 118, 118), Color8(145, 145, 145)]

static var _hair_cache := {}

# Draw one 8px tile from the source atlas at a world-pixel position.
static func cell(ci: CanvasItem, c: Vector2i, at: Vector2, mod := Color.WHITE) -> void:
	ci.draw_texture_rect_region(TILES, Rect2(at, Vector2(T, T)), Rect2(c * T, Vector2(T, T)), mod)

# Draw a pixel rectangle from the sprite sheet at the supplied world position.
static func region(ci: CanvasItem, src: Rect2, at: Vector2, mod := Color.WHITE) -> void:
	ci.draw_texture_rect_region(TILES, Rect2(at, src.size), src, mod)

# Generate a stable coordinate-based variation so terrain details do not flicker between frames.
static func _h(x: int, y: int) -> int:
	return absi(hash(Vector2i(x, y)))

# Player sheet with the gray hair pixels recoloured (Celeste-style dash indicator).
# Recolor the original sheet hair pixels and cache the result, leaving unrelated gray pixels untouched.
static func player_sheet(hair: Color) -> Texture2D:
	var key := hair.to_html()
	if _hair_cache.has(key):
		return _hair_cache[key]
	var img: Image = PLAYER.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		if y % T > 2:  # hair lives in the top rows of each frame; shoes share the gray
			continue
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0 and c.is_equal_approx(HAIR_COLORS[0]):
				img.set_pixel(x, y, hair.darkened(0.25))
			elif c.a > 0 and c.is_equal_approx(HAIR_COLORS[1]):
				img.set_pixel(x, y, hair)
	var tex := ImageTexture.create_from_image(img)
	_hair_cache[key] = tex
	return tex

# Cull the terrain to the camera view, then pass its visible tile range to the chunk-compatible renderer.
static func draw_tiles(ci: CanvasItem, tiles: Array, gw: int, gh: int, view: Rect2) -> void:
	var x0 := clampi(int(view.position.x / T) - 1, 0, gw)
	var x1 := clampi(int(view.end.x / T) + 2, 0, gw)
	var y0 := clampi(int(view.position.y / T) - 1, 0, gh)
	var y1 := clampi(int(view.end.y / T) + 2, 0, gh)
	draw_tile_range(ci, tiles, gw, gh, x0, y0, x1, y1)

# Half-open cell range; neighbours are read from the full level, not the chunk.
# Draw only a rectangular tile subset, choosing themed artwork or the default tile treatment.
static func draw_tile_range(ci: CanvasItem, tiles: Array, gw: int, gh: int, x0: int, y0: int, x1: int, y1: int, environment := "") -> void:
	if environment in EnvironmentArt.THEMES:
		EnvironmentArt.draw_range(ci, tiles, gw, gh, x0, y0, x1, y1, environment)
		return
	# Neighbour checks are inlined (a lambda call per lookup dominated zoomed-out views).
	# The level border counts as solid, so no edges are drawn there.
	for y in range(y0, y1):
		var row: String = tiles[y]
		var up: String = tiles[y - 1] if y > 0 else ""
		var down: String = tiles[y + 1] if y < gh - 1 else ""
		for x in range(x0, x1):
			if row.unicode_at(x) != 49:
				continue
			var at := Vector2(x * T, y * T)
			var top := y > 0 and up.unicode_at(x) != 49
			var left := x > 0 and row.unicode_at(x - 1) != 49
			var right := x < gw - 1 and row.unicode_at(x + 1) != 49
			var bot := y < gh - 1 and down.unicode_at(x) != 49
			var h := _h(x, y)
			ci.draw_rect(Rect2(at, Vector2(T, T)), FILL)
			if not top and h % 6 == 0:
				cell(ci, TEXTURES[(h / 6) % TEXTURES.size()], at)
			if top:
				if left:
					cell(ci, CORNER_TL, at)
				if right:
					cell(ci, CORNER_TR, at)
				if not left and not right:
					cell(ci, TOP_EDGES[x % 2], at)
				# grass and flowers on the open tile above
				if y > 0:
					if h % 4 == 0:
						cell(ci, GRASS[(h / 4) % GRASS.size()], at - Vector2(0, T))
					elif h % 17 == 1:
						cell(ci, FLOWERS[(h / 17) % FLOWERS.size()], at - Vector2(0, T))
			else:
				if left:
					cell(ci, EDGE_L, at)
				if right:
					cell(ci, EDGE_R, at)
			if bot:
				ci.draw_rect(Rect2(at.x, at.y + T - 1, T, 1), BOTTOM_EDGE)

# Parallax backdrop: moon, drifting clouds, tree line.
# Draw the default background treatment for a supplied camera view.
static func draw_background(ci: CanvasItem, view: Rect2, t: float, environment := "", area := Rect2()) -> void:
	if environment in EnvironmentArt.THEMES:
		EnvironmentArt.draw_background(ci, view, environment, area)
		return
	ci.draw_rect(view.grow(16), SKY)
	var moon_at := view.position + Vector2(view.size.x * 0.72, 18) + EnvironmentArt.parallax_shift(view, area) * 0.3
	region(ci, MOON, moon_at.floor(), Color(1, 1, 1, 0.8))
	for i in 6:
		var src: Rect2 = CLOUDS[i % CLOUDS.size()]
		var span := view.size.x + 120
		var x := fposmod(i * 97.0 - view.position.x * 0.15 + t * (3 + i % 3), span) - 60
		var y := 10 + (i * 37) % 70
		region(ci, src, (view.position + Vector2(x, y)).floor(), Color(1, 1, 1, 0.35))
	for i in 12:
		var src: Rect2 = TREES[i % TREES.size()]
		var span := view.size.x + 80
		var x := fposmod(i * 29.0 - view.position.x * 0.4, span) - 40
		var y := view.size.y - src.size.y + 6 + (i * 7) % 10
		region(ci, src, (view.position + Vector2(x, y)).floor(), Color(0.6, 0.6, 0.8, 0.35))
