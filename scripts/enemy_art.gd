extends RefCounted
# Original native pixel sprites; enemy behaviour references are documented in docs/ENEMIES.md.
const SIZE := 16
const KINDS := ["enemy_thornmite", "enemy_skree", "enemy_bat", "enemy_skeleton", "enemy_hornback", "enemy_fuzzbob", "enemy_thornmite_swift", "enemy_thornmite_armored", "enemy_skree_swift", "enemy_skree_armored", "enemy_bat_swift", "enemy_bat_armored", "enemy_skeleton_swift", "enemy_skeleton_armored", "enemy_hornback_swift", "enemy_hornback_armored", "enemy_fuzzbob_swift", "enemy_fuzzbob_armored"]
const COLORS := {
	"o": Color("e6a76c"), "O": Color("a95c53"), "y": Color("f8d89b"),
	"b": Color("6483aa"), "B": Color("33465f"), "p": Color("9872af"),
	"P": Color("58446f"), "s": Color("d8d8bd"), "S": Color("8c9e9c"),
	"g": Color("83b7a0"), "G": Color("436c75"), "e": Color("f4a16b"), "k": Color("253247"),
}
const SPRITES := {
	"enemy_thornmite": ["            ", "  y  y  y   ", " yOyOOyOy   ", " OoooooooO  ", "OoyyoooooeO ", "OoooooooekO ", " OOOOOOOOO  ", "  k k k k   "],
	"enemy_skree": ["    yyyy    ", "   OooooO   ", "   OOooOO   ", "    OeeO    ", "    OooO    ", "   bOooOb   ", "   bBOOBb   ", "    bBBb    ", "     BB     ", "     BB     ", "     kk     "],
	"enemy_bat": ["            ", "            ", "    P  P    ", "    PppP    ", "    peep    ", "    PppP    ", "     PP     ", "            "],
	"enemy_skeleton": ["    ssss    ", "   sssssS   ", "   skskss   ", "    ssSs    ", "     SS     ", "   Ssssss   ", "   s Ss s   ", "   ssss s   ", "     SS     ", "    sS s    ", "    S  S    ", "   ss  ss   "],
	"enemy_hornback": ["        yy  ", "       yBy  ", "    BBBBBy  ", "   BbbbbBBB ", "  BbbbbbbBeB", "  BbBbbBbBBB", "  BBBBBBBBBB", "   k k  k k "],
	"enemy_fuzzbob": ["  s      s  ", " sss    sss ", "  sGGGGGGs  ", "  GgggggggG ", " GgggggggggG", " GggeggggegG", " GgggggggggG", "  GgggggggG ", "   GGGGGG   "],
}
static var _texture: Texture2D

static func atlas() -> Image:
	var img := Image.create(SIZE * 4, SIZE * KINDS.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for row in KINDS.size():
		var kind: String = KINDS[row]
		var base_kind := kind.trim_suffix("_swift").trim_suffix("_armored")
		var colors := COLORS.duplicate()
		if kind.ends_with("_swift"):
			for key in ["o", "O", "b", "B", "p", "P", "g", "G"]:
				colors[key] = COLORS[key].lerp(Color("e66786"), 0.55)
			colors["s"] = Color("f5d1ad")
			colors["S"] = Color("b17b92")
		elif kind.ends_with("_armored"):
			for key in ["o", "O", "b", "B", "p", "P", "g", "G", "s", "S"]:
				colors[key] = COLORS[key].lerp(Color("536a85"), 0.65)
			colors["e"] = Color("ffce75")
		var sprite: Array = SPRITES[base_kind]
		for frame in 4:
			var origin := Vector2i(frame * SIZE, row * SIZE)
			var top := (SIZE - sprite.size()) / 2
			if base_kind == "enemy_bat":
				var wing_y: int = [3, 5, 7, 5][frame]
				img.fill_rect(Rect2i(origin + Vector2i(1, wing_y), Vector2i(5, 2)), colors["P"])
				img.fill_rect(Rect2i(origin + Vector2i(10, wing_y), Vector2i(5, 2)), colors["P"])
				img.fill_rect(Rect2i(origin + Vector2i(4, mini(wing_y + 1, 7)), Vector2i(2, maxi(1, 8 - wing_y))), colors["P"])
				img.fill_rect(Rect2i(origin + Vector2i(10, mini(wing_y + 1, 7)), Vector2i(2, maxi(1, 8 - wing_y))), colors["P"])
				img.fill_rect(Rect2i(origin + Vector2i(2, wing_y), Vector2i(3, 1)), colors["p"])
				img.fill_rect(Rect2i(origin + Vector2i(11, wing_y), Vector2i(3, 1)), colors["p"])
			for y in sprite.size():
				for x in sprite[y].length():
					var ch: String = sprite[y][x]
					if colors.has(ch):
						var offset := 0
						var lift := 0
						if base_kind == "enemy_thornmite" and y >= 7:  # scuttling legs
							offset = (1 if x % 4 < 2 else -1) if frame % 2 else 0
						if base_kind == "enemy_hornback" and y >= 7:
							offset = (1 if x < 6 else -1) if frame % 2 else 0
						if base_kind == "enemy_fuzzbob" and y < 2 and frame % 2:  # wings flap
							lift = 1
						if base_kind == "enemy_skeleton" and y >= 9:
							offset = (1 if x < 6 else -1) if frame % 2 else 0
						img.set_pixelv(origin + Vector2i(x + 2 + offset, y + top + lift), colors[ch])
			if base_kind == "enemy_skree" and frame % 2:
				img.fill_rect(Rect2i(origin + Vector2i(4, 8), Vector2i(2, 2)), colors["b"])
				img.fill_rect(Rect2i(origin + Vector2i(10, 8), Vector2i(2, 2)), colors["b"])
			if kind.ends_with("_armored"):
				# Shared bronze shoulder plates distinguish armour even in monochrome.
				img.fill_rect(Rect2i(origin + Vector2i(4, 8), Vector2i(2, 2)), Color("d3ad74"))
				img.fill_rect(Rect2i(origin + Vector2i(10, 8), Vector2i(2, 2)), Color("d3ad74"))
	return img

static func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(atlas())
	return _texture

static func draw(ci: CanvasItem, kind: String, at: Vector2, facing: int, clock: float, flash := false) -> void:
	var frame := int(clock * 8) % 4
	var source := Rect2(frame * SIZE, KINDS.find(kind) * SIZE, SIZE, SIZE)
	# Negative width flips the texture in-place; both facings share the same origin.
	var dest := Rect2(at.round() + Vector2(-8, -8), Vector2(-16 if facing < 0 else 16, 16))
	ci.draw_texture_rect_region(texture(), dest, source, Color(1.8, 1.6, 1.4) if flash else Color.WHITE)
