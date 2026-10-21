extends RefCounted
# Original native pixel sprites; enemy behaviour references are documented in docs/ENEMIES.md.
const SIZE := 16
const KINDS := ["enemy_ripper", "enemy_skree", "enemy_bat", "enemy_skeleton", "enemy_medusa"]
const COLORS := {
	"o": Color("e6a76c"), "O": Color("a95c53"), "y": Color("f8d89b"),
	"b": Color("6483aa"), "B": Color("33465f"), "p": Color("9872af"),
	"P": Color("58446f"), "s": Color("d8d8bd"), "S": Color("8c9e9c"),
	"g": Color("83b7a0"), "G": Color("436c75"), "e": Color("f4a16b"), "k": Color("253247"),
}
const SPRITES := {
	"enemy_ripper": ["            ", "            ", "   OOOOO    ", "  OoooooO   ", " OoyyyoooO  ", " OooooooOek ", "  BBBBBBB   ", "   bB bB    "],
	"enemy_skree": ["    yyyy    ", "   OooooO   ", "   OOooOO   ", "    OeeO    ", "    OooO    ", "   bOooOb   ", "   bBOOBb   ", "    bBBb    ", "     BB     ", "     BB     ", "     kk     "],
	"enemy_bat": ["            ", "            ", "    P  P    ", "    PppP    ", "    peep    ", "    PppP    ", "     PP     ", "            "],
	"enemy_skeleton": ["    ssss    ", "   sssssS   ", "   skskss   ", "    ssSs    ", "     SS     ", "   Ssssss   ", "   s Ss s   ", "   ssss s   ", "     SS     ", "    sS s    ", "    S  S    ", "   ss  ss   "],
	"enemy_medusa": ["   g gg g   ", "  GgggggG   ", "  ggSSggg   ", " GgsssssgG  ", "  GseessG   ", "  GsssssG   ", "   GssSG    ", "   gGGgG    ", "  Gg  Gg    ", "            "],
}
static var _texture: Texture2D

static func atlas() -> Image:
	var img := Image.create(SIZE * 4, SIZE * KINDS.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for row in KINDS.size():
		var kind: String = KINDS[row]
		var sprite: Array = SPRITES[kind]
		for frame in 4:
			var origin := Vector2i(frame * SIZE, row * SIZE)
			var top := (SIZE - sprite.size()) / 2
			if kind == "enemy_bat":
				var wing_y: int = [3, 5, 7, 5][frame]
				img.fill_rect(Rect2i(origin + Vector2i(1, wing_y), Vector2i(5, 2)), COLORS["P"])
				img.fill_rect(Rect2i(origin + Vector2i(10, wing_y), Vector2i(5, 2)), COLORS["P"])
				img.fill_rect(Rect2i(origin + Vector2i(2, wing_y), Vector2i(3, 1)), COLORS["p"])
				img.fill_rect(Rect2i(origin + Vector2i(11, wing_y), Vector2i(3, 1)), COLORS["p"])
			for y in sprite.size():
				for x in sprite[y].length():
					var ch: String = sprite[y][x]
					if COLORS.has(ch):
						var offset := 0
						if kind == "enemy_skeleton" and y >= 9:
							offset = (1 if x < 6 else -1) if frame % 2 else 0
						img.set_pixelv(origin + Vector2i(x + 2 + offset, y + top), COLORS[ch])
			if kind == "enemy_ripper":
				img.fill_rect(Rect2i(origin + Vector2i(4 + frame % 2, 11), Vector2i(2, 1)), COLORS["b"])
	return img

static func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(atlas())
	return _texture

static func draw(ci: CanvasItem, kind: String, at: Vector2, facing: int, clock: float, flash := false) -> void:
	var frame := int(clock * 8) % 4
	var source := Rect2(frame * SIZE, KINDS.find(kind) * SIZE, SIZE, SIZE)
	# Flip only the destination quad, without replacing the world's canvas transform.
	var dest := Rect2(at.round() + Vector2(8 if facing < 0 else -8, -8), Vector2(-16 if facing < 0 else 16, 16))
	ci.draw_texture_rect_region(texture(), dest, source, Color(1.8, 1.6, 1.4) if flash else Color.WHITE)
