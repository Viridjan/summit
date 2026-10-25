extends RefCounted
# Original pixel artwork for enemy families and their variants.
# A family defines a base shape; a variant changes its palette and optional decorative features.
# The atlas packs four frames per enemy type into one shared image.
# Drawing places that frame relative to an enemy's collision body; the two need not have equal sizes.
# Reading help: docs/CODE_GUIDE.md.

# Original native pixel sprites; enemy behaviour references are documented in docs/ENEMIES.md.
# One 32x32 cell per frame, four frames per row, one row per enemy type (same order as Entities.TYPES).
const SIZE := 32
const KINDS := ["enemy_thornmite", "enemy_skree", "enemy_bat", "enemy_skeleton", "enemy_hornback", "enemy_fuzzbob", "enemy_cragjaw", "enemy_murkspore", "enemy_mosstrot", "enemy_thornmite_swift", "enemy_thornmite_venom", "enemy_thornmite_brood", "enemy_thornmite_giant", "enemy_skree_swift", "enemy_skree_armored", "enemy_skree_venom", "enemy_bat_swift", "enemy_bat_brood", "enemy_skeleton_armored", "enemy_skeleton_shielded", "enemy_skeleton_giant", "enemy_hornback_shielded", "enemy_hornback_swift", "enemy_hornback_giant", "enemy_fuzzbob_brood", "enemy_fuzzbob_venom", "enemy_fuzzbob_giant", "enemy_cragjaw_armored", "enemy_cragjaw_shielded", "enemy_murkspore_swift", "enemy_murkspore_venom", "enemy_murkspore_brood"]
const COLORS := {
	"o": Color("e6a76c"), "O": Color("a95c53"), "y": Color("f8d89b"),
	"b": Color("6483aa"), "B": Color("33465f"), "p": Color("9872af"),
	"P": Color("58446f"), "s": Color("d8d8bd"), "S": Color("8c9e9c"),
	"g": Color("83b7a0"), "G": Color("436c75"), "e": Color("f4a16b"), "k": Color("253247"),
	"r": Color("a58a6a"), "R": Color("5e4a3c"), "m": Color("8a6aa8"), "M": Color("4a3866"),
	"q": Color("c5af89"), "v": Color("b696c5"), "n": Color("b2ce79"), "t": Color("c19a65"),
	"l": Color("7fae4e"), "L": Color("41673a"), "h": Color("9a7452"), "H": Color("5a3f2e"),
}
const BODY := ["o", "O", "b", "B", "p", "P", "g", "G", "s", "S", "r", "R", "m", "M", "l", "L", "h", "H", "q", "v", "n", "t"]  # recoloured by variants
# variant -> [tint, tint amount, eye colour or null]
const TINTS := {
	"swift": [Color("e66786"), 0.55, null],
	"armored": [Color("536a85"), 0.65, Color("ffce75")],
	"giant": [Color("8a3b2a"), 0.35, Color("ff5a3a")],
	"shielded": [Color("d3ad74"), 0.3, null],
	"brood": [Color("c8d06a"), 0.45, Color("fff27a")],
	"venom": [Color("7bd36a"), 0.5, Color("d6ff6a")],
}
const SPRITES := {
	"enemy_thornmite": ["            ", "  y  y  y   ", " yOyOOyOy   ", " OoooooooO  ", "OoyyoooooeO ", "OoooooooekO ", " OOOOOOOOO  ", "  k k k k   "],
	"enemy_skree": ["    yyyy    ", "   OooooO   ", "   OOooOO   ", "    OeeO    ", "    OooO    ", "   bOooOb   ", "   bBOOBb   ", "    bBBb    ", "     BB     ", "     BB     ", "     kk     "],
	"enemy_bat": ["            ", "            ", "    P  P    ", "    PppP    ", "    peep    ", "    PppP    ", "     PP     ", "            "],
	"enemy_skeleton": ["    ssss    ", "   sssssS   ", "   skskss   ", "    ssSs    ", "     SS     ", "   Ssssss   ", "   s Ss s   ", "   ssss s   ", "     SS     ", "    sS s    ", "    S  S    ", "   ss  ss   "],
	"enemy_hornback": ["        yy  ", "       yBy  ", "    BBBBBy  ", "   BbbbbBBB ", "  BbbbbbbBeB", "  BbBbbBbBBB", "  BBBBBBBBBB", "   k k  k k "],
	"enemy_fuzzbob": ["  s      s  ", " sss    sss ", "  sGGGGGGs  ", "  GgggggggG ", " GgggggggggG", " GggeggggegG", " GgggggggggG", "  GgggggggG ", "   GGGGGG   "],
	"enemy_cragjaw": ["       RRR  RRR         ", "     RRqqrRRrrrRR       ", "    RqqrrrrrrrrrrR      ", "   RqrrrRRrrrrrrrrR     ", "  RqrrRRrrrRRrrrrrrR    ", "  RrrRrrrrrrrrRrrrrrR   ", " RqrrrrrrrRrrrrrrerrR   ", " RrrrrrRrrrrrrrrrekrrR  ", " RrrrrrrrrrrrrRrrrrrrR  ", " RrrRrrrrrrrRRRRRRRRRR  ", " RrrrrrrrrrRyRyyRyyRyR  ", " RrrrrRrrrrRkkkkkkkkkR  ", "  RrrrrrrrrRyyRyyRyyRR  ", "  RrrrrrrrrrRRRRRRRRR   ", "   RrrRRRRRRRRRrrR      ", "   RrqR       RrqR      ", "   RrrR       RrrR      ", "  kkkkk      kkkkk      "],
	"enemy_mosstrot": ["   n  n  l  ", "  nlnnlLllL ", " LnllllllLlL", "  LLLLLLLLL ", " HttthhhhheH", " HhthhhhhekH", "  HHHHHHHHH ", "  kk k  kk  "],
	"enemy_murkspore": ["       MMMMMMMM       ", "     MMvvvvmmmmMM     ", "    MvvvymmmmyvmmM    ", "   MvvmmmmmmmmmmmmM   ", "   MvmmmyvmmmmmymmM   ", "  MmmmmmmmmmmmmmmmmM  ", "  MMMMMMMMMMMMMMMMMM  ", "   MvMvMvMvMvMvMvM    ", "    MssssSSssssssM    ", "    MsseeksseekssM    ", "     MssSkkSsssM      ", "      MSSssSSMM       ", "       m  m  m        ", "      m   m   m       ", "       M  M  M        "],
}
static var _texture: Texture2D

# Resolve a variant type ID to its base family so it can share the underlying shape.
static func family_of(kind: String) -> String:
	for f in SPRITES:
		if kind == f or kind.begins_with(f + "_"):
			return f
	return kind

# Build all four-frame enemy rows, applying variant colors and pose-specific pixel changes.
static func atlas() -> Image:
	var img := Image.create(SIZE * 4, SIZE * KINDS.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for row in KINDS.size():
		var kind: String = KINDS[row]
		var base_kind := family_of(kind)
		var variant := kind.trim_prefix(base_kind + "_") if kind != base_kind else ""
		var colors := COLORS.duplicate()
		if TINTS.has(variant):
			var tint: Array = TINTS[variant]
			for key in BODY:
				colors[key] = COLORS[key].lerp(tint[0], tint[1])
			if tint[2] != null:
				colors["e"] = tint[2]
			if variant == "swift":
				colors["s"] = Color("f5d1ad")
				colors["S"] = Color("b17b92")
		var sprite: Array = SPRITES[base_kind]
		var width: int = sprite[0].length()
		for frame in 4:
			var origin := Vector2i(frame * SIZE, row * SIZE)
			var o16 := origin + Vector2i((SIZE - 16) / 2, (SIZE - 16) / 2)  # small sprites were drawn on a 16px cell
			var top := origin.y + (SIZE - sprite.size()) / 2
			var left := origin.x + (SIZE - width) / 2
			if base_kind == "enemy_bat":
				var wing_y: int = [3, 5, 7, 5][frame]
				img.fill_rect(Rect2i(o16 + Vector2i(1, wing_y), Vector2i(5, 2)), colors["P"])
				img.fill_rect(Rect2i(o16 + Vector2i(10, wing_y), Vector2i(5, 2)), colors["P"])
				img.fill_rect(Rect2i(o16 + Vector2i(4, mini(wing_y + 1, 7)), Vector2i(2, maxi(1, 8 - wing_y))), colors["P"])
				img.fill_rect(Rect2i(o16 + Vector2i(10, mini(wing_y + 1, 7)), Vector2i(2, maxi(1, 8 - wing_y))), colors["P"])
				img.fill_rect(Rect2i(o16 + Vector2i(2, wing_y), Vector2i(3, 1)), colors["p"])
				img.fill_rect(Rect2i(o16 + Vector2i(11, wing_y), Vector2i(3, 1)), colors["p"])
			for y in sprite.size():
				for x in width:
					var ch: String = sprite[y][x]
					if colors.has(ch):
						var offset := 0
						var lift := 0
						if base_kind == "enemy_thornmite" and y >= 7:  # scuttling legs
							offset = (1 if x % 4 < 2 else -1) if frame % 2 else 0
						if base_kind in ["enemy_skeleton", "enemy_hornback"] and y >= sprite.size() - 3:
							offset = (1 if x < width / 2 else -1) if frame % 2 else 0
						if base_kind == "enemy_cragjaw":
							# A heavy shoulder roll, with alternating planted feet.
							if y < 14: lift = [0, 1, 0, 0][frame]
							if y >= 15:
								offset = [0, 1, -1, 0][frame] * (1 if x < width / 2 else -1)
								if (frame == 1 and x < width / 2) or (frame == 3 and x >= width / 2): lift = -1
						if base_kind == "enemy_mosstrot":
							if y < 3: offset = [0, 1, 0, -1][frame]
							if y == sprite.size() - 1:
								offset = [0, 1, -1, 0][frame] * (1 if x < width / 2 else -1)
						if base_kind == "enemy_murkspore":
							lift = [0, -1, 0, 1][frame]
						if base_kind == "enemy_murkspore" and y >= 12:  # drifting tendrils
							offset = [0, 1, 0, -1][(frame + y) % 4]
						if base_kind == "enemy_fuzzbob" and y < 2 and frame % 2:  # wings flap
							lift = 1
						img.set_pixelv(Vector2i(left + x + offset, top + y + lift), colors[ch])
			if base_kind == "enemy_skree" and frame % 2:
				img.fill_rect(Rect2i(o16 + Vector2i(4, 8), Vector2i(2, 2)), colors["b"])
				img.fill_rect(Rect2i(o16 + Vector2i(10, 8), Vector2i(2, 2)), colors["b"])
			if variant == "armored":  # bronze shoulder plates read even in monochrome
				img.fill_rect(Rect2i(Vector2i(left + width / 2 - 4, top + sprite.size() / 2), Vector2i(2, 2)), Color("d3ad74"))
				img.fill_rect(Rect2i(Vector2i(left + width / 2 + 2, top + sprite.size() / 2), Vector2i(2, 2)), Color("d3ad74"))
			if variant == "brood":  # pale egg spots
				for spot in [Vector2i(-2, 0), Vector2i(2, -2), Vector2i(1, 2)]:
					img.set_pixelv(Vector2i(left + width / 2, top + sprite.size() / 2) + spot, Color("fffbd0"))
			if variant == "venom":  # a drip that falls frame by frame
				img.set_pixelv(Vector2i(left + width / 2, top + sprite.size() + frame), Color("8fd14f"))
	return img

# Create the shared enemy atlas texture once and reuse it for subsequent draws.
static func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(atlas())
	return _texture

# Choose a family/variant atlas frame and draw it centred on the collision body with facing and scale.
static func draw(ci: CanvasItem, kind: String, at: Vector2, facing: int, clock: float, flash := false, scale := 1.0) -> void:
	var frame := int(clock * 8) % 4
	var source := Rect2(frame * SIZE, KINDS.find(kind) * SIZE, SIZE, SIZE)
	# Negative width flips the texture in-place; both facings share the same origin.
	var half := SIZE * scale / 2.0
	var dest := Rect2(at.round() - Vector2(half, half), Vector2(-SIZE * scale if facing < 0 else SIZE * scale, SIZE * scale))
	ci.draw_texture_rect_region(texture(), dest, source, Color(1.8, 1.6, 1.4) if flash else Color.WHITE)
