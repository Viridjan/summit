extends RefCounted
# Original Celeste-inspired 16px climber. Frames are authored as native pixel shapes,
# then baked once into a shared atlas; gameplay draws one textured quad per body.

const SIZE := 16
const COLUMNS := 8
# Terrain uses 8px blocks; retain 16px atlas cells with bottom-aligned artwork.
const STANDING_HEIGHT := 12
const CROUCHED_HEIGHT := 8
const BODY_WIDTH := 12
# row, frame count, fps. Keep row order stable for the animation preview.
const ANIMATIONS := {
	"idle": [0, 8, 4.0], "run": [1, 8, 14.0], "jump": [2, 2, 8.0],
	"apex": [3, 2, 6.0], "fall": [4, 4, 8.0], "climb": [5, 4, 10.0],
	"wall_slide": [6, 2, 5.0], "dash": [7, 2, 16.0], "duck": [8, 2, 4.0],
	"skid": [9, 2, 10.0], "fly": [10, 4, 10.0], "boost": [11, 2, 6.0],
	"land": [12, 3, 20.0],
}
# Larger connected colour clusters, authored at the final world resolution.
const PALETTE := {
	"h": Color("a83c50"), "H": Color("e96962"), "L": Color("f2947d"),
	"s": Color("f1c3a1"), "e": Color("28354b"),
	"b": Color("3e79ad"), "B": Color("79b9d2"),
	"p": Color("94615b"), "D": Color("2c354d"), "d": Color("38445f"), "k": Color("293449"),
}
const STAND := [
	"    HLLH    ",
	"   hHHHHH   ",
	"   hHHHss   ",
	"   hHsses   ",
	"   hHssss   ",
	"   hhbbbb   ",
	"  ppbbBBbb  ",
	"  ppbbBBbs  ",
	"   pbbbbb   ",
	"    dddd    ",
	"    dd dd   ",
	"   kkk kk   ",
]
# Side-on contact, compression, passing and recovery; then the opposite leg.
# Four lower rows leave space for bent knees. D identifies the far leg.
const RUN_LOWER := [
	["   pDddd    ", "    D dd    ", "   kk dd    ", "      kkk   "],
	["   pDddd    ", "    DDdd    ", "    Dkdd    ", "     kkk    "],
	["   pDddd    ", "     dDD    ", "     d Dkk  ", "    kkk     "],
	["   pDddd    ", "    dd DD   ", "    dd  kk  ", "   kkk      "],
	["   pdDDD    ", "    d DD    ", "   kk DD    ", "      kkk   "],
	["   pdDDD    ", "    ddDD    ", "    dkDD    ", "     kkk    "],
	["   pdDDD    ", "     Ddd    ", "     D dkk  ", "    kkk     "],
	["   pdDDD    ", "    DD dd   ", "    DD  kk  ", "   kkk      "],
]
# Full poses keep hands below the face and connect sleeves, hips and bent legs.
const AIR_POSES := {
	"jump": [
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbbs ", "  ppbbBBb   ", "   pDddd    ", "    D ddkk  ", "    Ddk     ", "   kkk      "],
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbb  ", "  ppbbBBbbs ", "   pDdddd   ", "    DD ddkk ", "    kkkdd   ", "       kk   "],
	],
	"apex": [
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbb  ", "  ppbbBBbbs ", "   pDddd    ", "    D dd    ", "    kkddk   ", "      kk    "],
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbs  ", "  ppbbBBbb  ", "   pDddd    ", "    DDdd    ", "     kkdd   ", "       kk   "],
	],
	"fall": [
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbb  ", "  ppbbBBbb  ", "   pDdddbs  ", "    DDdd    ", "    D  dd   ", "    kk kk   "],
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbb  ", "  ppbbBBbbs ", "   pDdddb   ", "    Dddd    ", "    D  ddk  ", "    kk      "],
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbb  ", "  ppbbBBbs  ", "   pDdddb   ", "    DDdd    ", "    D  dd   ", "    kk kk   "],
		["    HLLH    ", "   hHHHHH   ", "   hHHHss   ", "   hHsses   ", "   hHssss   ", "   hhbbbb   ", "  ppbbBBbb  ", "  ppbbBBbbs ", "   pDdddb   ", "    Dddd    ", "    Dk dd   ", "       kk   "],
	],
}
const CROUCH := [
	"    HLLH    ",
	"   hHHHHH   ",
	"   hHHHss   ",
	"   hHsses   ",
	"  phHssss   ",
	"  ppbbBBbb  ",
	"   bbbbbbs  ",
	"   kkk kk   ",
]
# Idle breathing (2 s loop): head and shoulders sink 1px on these frames, blink on the last one.
const IDLE_EXHALE := [2, 3, 6, 7]
const IDLE_BLINK := 7
# Wall poses (facing right, wall just past column 9). Arms stay in front of the face, never over it.
# Climb alternates: reach high with the knee up, then pull with the hand at the shoulder and the leg pushing down.
const CLIMB_REACH := [
	"    HLLH  s ",
	"   hHHHHH b ",
	"   hHHHssb  ",
	"   hHssesb  ",
	"   hHssssb  ",
	"   hhbbbbb  ",
	"  ppbbBBbb  ",
	"  ppbbBBb   ",
	"   pbbbbbs  ",
	"    ddddd   ",
	"    dd  dk  ",
	"   kkk      ",
]
const CLIMB_PULL := [
	"    HLLH    ",
	"   hHHHHH   ",
	"   hHHHss   ",
	"   hHsses s ",
	"   hHssssbb ",
	"   hhbbbbb  ",
	"  ppbbBBbb  ",
	"  ppbbBBbs  ",
	"   pbbbbb   ",
	"    dddd    ",
	"    dd dd   ",
	"   kkk  kk  ",
]
# Sliding down a wall: one hand dragging up high, legs hanging.
const WALL_SLIDE := [
	"    HLLH  s ",
	"   hHHHHH b ",
	"   hHHHssb  ",
	"   hHssesb  ",
	"   hHssssb  ",
	"   hhbbbbb  ",
	"  ppbbBBbb  ",
	"  ppbbBBbs  ",
	"   pbbbbb   ",
	"    dddd    ",
	"    dd dd   ",
	"   kkk kk   ",
]
# Hair strand clumps, head to tip, in the sprite's own hair shades (h dark, H light).
# Drawn pixel by pixel at world resolution so they match the sprite, not smooth circles.
const HAIR_CLUMPS := [
	[" HH ", "hHHh", "hHHh", " hh "],
	["HHh", "hHh", " hh"],
	["Hh", "hh"],
	["h"],
]
static var _textures: Dictionary = {}

# Same two shades build_atlas uses for the hair on the head.
static func hair_shades(hair_color: Color) -> Dictionary:
	return {
		"h": hair_color.lerp(Color("57354c"), 0.2),
		"H": hair_color.lerp(Color("ffad88"), 0.45),
		"L": hair_color.lerp(Color("ffd2a1"), 0.65),
	}

# How far the head sits below its usual spot on this frame (the hair anchor follows it).
static func head_drop(animation: String, column: int) -> int:
	return 1 if (animation == "idle" and column in IDLE_EXHALE) or (animation == "run" and column in [1, 5]) else 0

static func frame(animation: String, clock: float) -> Vector2i:
	var spec: Array = ANIMATIONS[animation]
	var column := maxi(0, int(clock * spec[2]))
	if animation in ["jump", "land"]:
		column = mini(column, spec[1] - 1)
	else:
		column %= int(spec[1])
	return Vector2i(column, spec[0])

static func texture(hair_color: Color = Color("ac3232")) -> Texture2D:
	var key := hair_color.to_rgba32()
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(build_atlas(hair_color))
	return _textures[key]

static func pose_height(animation: String, i: int) -> int:
	if animation in ["duck", "boost"]:
		return CROUCHED_HEIGHT
	if animation == "land":
		return [8, 10, STANDING_HEIGHT][i]
	return STANDING_HEIGHT

static func _box(img: Image, origin: Vector2i, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(0, 0, SIZE, SIZE))
	if clipped.has_area():
		img.fill_rect(Rect2i(origin + clipped.position, clipped.size), color)

static func build_atlas(hair_color: Color = Color("ac3232")) -> Image:
	var img := Image.create(SIZE * COLUMNS, SIZE * ANIMATIONS.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var colors := PALETTE.duplicate()
	colors.merge(hair_shades(hair_color), true)
	for animation in ANIMATIONS:
		var spec: Array = ANIMATIONS[animation]
		for i in int(spec[1]):
			var origin := Vector2i(i * SIZE, int(spec[0]) * SIZE)
			_pose(img, origin, animation, i, colors)
	return img

static func _pose(img: Image, origin: Vector2i, animation: String, i: int, colors: Dictionary) -> void:
	var height := pose_height(animation, i)
	var rows: Array = CROUCH if height == CROUCHED_HEIGHT else STAND
	# Landing has a hand-drawn intermediate pose; never resample pixel clusters.
	if height == 10:
		rows = STAND.slice(0, 8) + STAND.slice(10, 12)
	if animation == "run":
		rows = STAND.slice(0, 8) + RUN_LOWER[i]
		rows = rows.duplicate()
		# The visible sleeve swings opposite the forward knee.
		rows[6] = ["  ppbbBBbs  ", "  ppbbBBbb  ", "  ppbbBBbb  ", "  ppbbBBbbs "][i % 4]
		rows[7] = ["  ppbbBBbb  ", "  ppbbBBbs  ", "  ppbbBBbbs ", "  ppbbBBbb  "][i % 4]
		if head_drop(animation, i):
			rows = [""] + rows.slice(0, 7) + rows.slice(8)
	elif AIR_POSES.has(animation):
		rows = AIR_POSES[animation][i]
	elif animation == "climb":
		rows = CLIMB_REACH if i % 2 == 0 else CLIMB_PULL
	elif animation == "wall_slide":
		rows = WALL_SLIDE
		if i == 1:  # hand drags one pixel lower: a small shudder while sliding
			rows = [WALL_SLIDE[0].replace("s", " "), WALL_SLIDE[1].replace("b", "s")] + WALL_SLIDE.slice(2)
	if animation == "idle":
		if i in IDLE_EXHALE:  # exhale: drop the head/collar rows by one, legs stay planted
			rows = [""] + STAND.slice(0, 5) + STAND.slice(6, 12)
		if i == IDLE_BLINK:
			rows = rows.duplicate()
			var eye: int = 4 if i in IDLE_EXHALE else 3
			rows[eye] = rows[eye].replace("e", "s")
	var lean := 1 if animation in ["run", "dash", "boost"] else -1 if animation == "skid" else 0
	var top := SIZE - height
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if colors.has(row[x]):
				img.set_pixelv(origin + Vector2i(x + 2 + lean, top + y), colors[row[x]])
	if height < STANDING_HEIGHT:
		return

	if animation in ["dash", "fly"]:
		_box(img, origin, Rect2i(5, 14, 8, 2), Color.TRANSPARENT)
		_box(img, origin, Rect2i(6 + lean, 14, 2, 2), colors["d"])
		_box(img, origin, Rect2i(5 + lean, 15, 3, 1), colors["k"])
		_box(img, origin, Rect2i(9 + lean, 13, 2, 2), colors["d"])
		_box(img, origin, Rect2i(10 + lean, 14, 2, 1), colors["k"])
