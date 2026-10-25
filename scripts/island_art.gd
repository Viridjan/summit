extends RefCounted
## Original flat pixel artwork for the eastern island and its inhabitants.
## All builders are deterministic; native dimensions and bottom anchors stay fixed.
const SERPENT_POSES := ["idle", "move", "warn", "attack", "hurt", "defeat"]
const PEOPLE_POSES := ["idle", "walk", "talk", "gesture"]
const THEMES := ["island_shore", "volcano", "volcanic_cave"]
const INK := Color("242734")
const ROCK := Color("545060")
const EDGE := Color("969098")
const HOT := Color("ef8247")
const GOLD := Color("f5d58b")
static var _cache: Dictionary = {}

static func canvas(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func box(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.has_area():
		img.fill_rect(r, color)

static func poly(img: Image, points: Array, color: Color) -> void:
	var polygon := PackedVector2Array()
	for p in points:
		polygon.append(Vector2(p[0], p[1]))
	for y in img.get_height():
		for x in img.get_width():
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon):
				img.set_pixel(x, y, color)

static func texture(kind: String, pose := "idle", frame := 0, variant := 0) -> Texture2D:
	frame = posmod(frame, 4)
	var key := "%s:%s:%d:%d" % [kind, pose, frame, variant]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(build(kind, pose, frame, variant))
	return _cache[key]

static func build(kind: String, pose: String, frame: int, variant: int) -> Image:
	frame = posmod(frame, 4)
	match kind:
		"serpent": return serpent(pose, frame)
		"elf", "mage": return person(kind, pose, frame, posmod(variant, 3))
		"rock", "rock_warning", "rock_impact", "eruption", "vent": return effect(kind, pose, frame)
		"landmark": return landmark(posmod(variant, 3))
		"raft": return raft(frame)
		"mirror", "beacon", "lava": return lighthouse(kind, frame)
	return canvas(16, 16)

static func lighthouse(kind: String, frame: int) -> Image:
	if kind == "lava":
		var img := canvas(32,8)
		box(img,0,1,32,7,Color("b9533e"))
		for i in 8:
			box(img,i*4,1+posmod(i+frame,2),4,2,HOT)
			box(img,posmod(i*7+frame*2,30),4,2,1,GOLD)
		return img
	var img := canvas(24,32 if kind == "beacon" else 24)
	if kind == "mirror":
		poly(img,[[3,4],[16,1],[21,14],[8,18]],INK)
		poly(img,[[5,5],[15,3],[19,13],[9,16]],Color("83b4bb"))
		poly(img,[[6,6],[14,4],[15,6],[8,13]],Color("c9e2d2"))
		box(img,11,17,3,5,EDGE); box(img,6,22,13,2,ROCK)
	else:
		box(img,3,27,18,5,ROCK); box(img,7,23,10,4,EDGE)
		poly(img,[[5,23],[3,19],[7,20],[12,2+frame%3],[16,13],[20,10],[20,20],[17,24]],Color("6ca6b1"))
		poly(img,[[9,23],[8,17],[12,9+frame%2],[15,17],[17,16],[16,23]],Color("d3e9ce"))
	return img

static func serpent(pose: String, frame: int) -> Image:
	var img := canvas(96, 64)
	var body := Color("497b72")
	var dark := Color("345250")
	var belly := Color("d3b982")
	if pose == "hurt": body = Color("b36c62")
	if pose == "defeat": body = Color("686773"); belly = Color("95909a")
	var bob: int = [0, -1, 0, 1][frame]
	var head_y := 13 + bob if pose != "defeat" else 36 + frame
	if pose == "warn": head_y -= 4
	if pose == "attack": head_y += 5
	# Two overlapping coils, broad flat bands and a narrow tapered tail.
	poly(img, [[3,49],[12,45],[23,45],[24,40],[40,38],[66,40],[83,45],[89,52],[84,59],[68,62],[28,62],[15,58],[13,53],[7,54]], INK)
	poly(img, [[17,48],[28,42],[46,41],[66,43],[81,47],[85,52],[79,57],[63,59],[28,59],[18,55]], dark)
	poly(img, [[18,48],[30,44],[51,44],[69,46],[78,50],[74,54],[54,55],[31,54],[24,51]], body)
	poly(img, [[24,51],[40,53],[64,53],[75,50],[74,54],[60,57],[33,56]], belly)
	# Upright S-shaped neck; shifting bends make breathing visible without pivot drift.
	poly(img, [[32,46],[31,37],[38,29],[50,25],[54,head_y+6],[66,head_y+5],[69,head_y+15],[62,34],[48,39],[47,46],[58,49],[54,54],[39,53]], INK)
	poly(img, [[35,45],[35,38],[43,31],[55,29],[58,head_y+8],[64,head_y+8],[65,head_y+15],[58,32],[44,37],[43,46],[51,50],[41,50]], body)
	poly(img, [[44,35],[56,29],[60,head_y+14],[65,head_y+13],[61,32],[48,39],[47,46],[43,45]], belly)
	# Angular horned head, one visible eye and an unambiguous right-facing muzzle.
	poly(img, [[52,head_y+3],[49,head_y-6],[58,head_y-1],[67,head_y-2],[72,head_y+2],[83,head_y+4],[88,head_y+9],[85,head_y+16],[67,head_y+18],[57,head_y+12]], INK)
	poly(img, [[55,head_y+3],[60,head_y+1],[68,head_y+1],[72,head_y+5],[82,head_y+6],[85,head_y+10],[81,head_y+14],[68,head_y+15],[60,head_y+10]], body)
	box(img, 68, head_y+6, 7, 2, INK)
	box(img, 72, head_y+7, 2, 2, GOLD if pose != "defeat" else INK)
	box(img, 82, head_y+9, 2, 1, INK)
	box(img, 72, head_y+13, 11, 2, belly)
	if pose in ["warn", "attack"]:
		box(img, 74, head_y+12, 11, 5 if pose == "attack" else 3, INK)
		box(img, 76, head_y+12, 2, 3, GOLD)
		if pose == "attack": box(img, 82, head_y+15, 9, 1, HOT)
	for i in 5:
		box(img, 24+i*10, 46 + (i%2)*2, 3, 2, belly)
	if pose == "move":
		box(img, 5+frame*2, 50, 5, 2, body)
	return img

static func person(kind: String, pose: String, frame: int, variant: int) -> Image:
	var img := canvas(16, 24)
	var cloth: Color = [Color("557954"), Color("9a754d"), Color("648f85")][variant] if kind == "elf" else [Color("5d648f"), Color("8c687f"), Color("728690")][variant]
	var hair: Color = [Color("c8ad73"), Color("563e38"), Color("c3c2b4")][variant]
	var skin := Color("dfaf82") if variant != 1 else Color("b68161")
	var bob := 1 if pose in ["talk", "walk"] and frame%2 else 0
	var step: int = [-1, 0, 1, 0][frame] if pose == "walk" else 0
	# Stable bottom anchor, separate feet even beneath the mage's robe.
	box(img, 5-step, 21, 3, 3, INK); box(img, 9+step, 21, 3, 3, INK)
	if kind == "elf":
		poly(img, [[5,11+bob],[11,11+bob],[13,20],[10,21],[8,19],[5,21],[3,20]], INK)
		poly(img, [[6,12+bob],[10,12+bob],[11,19],[8,18],[5,19]], cloth)
		box(img, 5, 16+bob, 7, 2, Color("705343"))
		poly(img, [[4,7+bob],[0,5+bob],[2,10+bob],[5,11+bob]], skin)
		poly(img, [[11,7+bob],[15,5+bob],[14,10+bob],[11,11+bob]], skin)
	else:
		poly(img, [[5,10+bob],[11,10+bob],[14,22],[2,22]], INK)
		poly(img, [[6,11+bob],[10,11+bob],[12,21],[4,21]], cloth)
		box(img, 7, 13+bob, 2, 8-bob, GOLD)
	# Head, flat hair cap, a single profile eye and clear ears/hood.
	box(img, 4, 4+bob, 8, 8, INK)
	box(img, 5, 6+bob, 7, 5, skin)
	box(img, 4, 4+bob, 8, 3, hair)
	box(img, 4, 6+bob, 2, 5, hair)
	box(img, 10, 8+bob, 1, 1, INK)
	if pose == "idle" and frame == 3: box(img, 10, 8+bob, 1, 1, skin)
	if kind == "elf":
		poly(img, [[4,5+bob],[5,1+bob],[11,3+bob],[13,6+bob]], cloth)
		box(img, 7, 3+bob, 3, 1, GOLD)
	else:
		poly(img, [[3,6+bob],[5,3+bob],[7,0+bob],[10,3+bob],[12,6+bob]], cloth)
		box(img, 2, 6+bob, 12, 2, INK)
		box(img, 3, 6+bob, 10, 1, cloth)
		if variant == 2: box(img, 7, 10+bob, 4, 3, hair)
	var hand_y := 14+bob
	if pose == "gesture": hand_y = 9 + frame%2
	box(img, 11, hand_y, 3, 3, cloth)
	box(img, 13, hand_y, 2, 2, skin)
	if pose == "talk": box(img, 10, 10+bob, 2, 1, INK if frame%2 else skin)
	if kind == "mage":
		box(img, 1, 11, 1, 12, Color("a18261"))
		box(img, 0, 10, 3, 2, GOLD if frame%2 else Color("aa97c1"))
	return img

static func effect(kind: String, pose: String, frame: int) -> Image:
	var sizes := {"rock": Vector2i(16,16), "rock_warning": Vector2i(24,8), "rock_impact": Vector2i(32,16), "eruption": Vector2i(24,32), "vent": Vector2i(16,8)}
	var size: Vector2i = sizes[kind]
	var img := canvas(size.x, size.y)
	match kind:
		"rock":
			poly(img, [[4,0],[11,0],[15,4],[16,11],[11,16],[3,15],[0,10],[0,5]], INK)
			poly(img, [[4,1],[10,1],[14,5],[14,11],[10,14],[3,13],[1,9],[2,4]], ROCK)
			poly(img, [[4,2],[9,2],[7,6],[2,8],[3,4]], EDGE)
			box(img, 7+frame%3, 7, 1, 5, INK)
			box(img, 8, 7+frame%2, 4, 1, INK)
		"rock_warning":
			for i in 4:
				box(img, 2+i*6, 1+posmod(i+frame,3), 3, 1, EDGE)
			box(img, 9, 6, 6, 1, GOLD if frame%2 else HOT)
		"rock_impact":
			for i in 7:
				var x := 2+i*4
				var y := 12 - posmod(i*3+frame*2,10)
				box(img, x, y, 3, 2, EDGE if i%2 else ROCK)
			box(img, 2+frame*2, 14, 28-frame*4, 2, Color("bba88b"))
		"eruption":
			for x in range(1,23):
				var top := 1+posmod(x*3+frame*5,9)
				box(img, x, top, 1, 32-top, HOT)
				if x>5 and x<18: box(img, x, top+5, 1, 27-top, GOLD)
			box(img, 10, 0, 4, 3, HOT)
		"vent":
			poly(img, [[1,7],[2,3],[5,1],[12,1],[15,4],[15,8]], INK)
			box(img, 3, 3, 10, 4, ROCK)
			box(img, 6, 2, 2, 5, HOT if pose != "broken" else INK)
			if pose == "broken": box(img, 2, 1, 13, 3, Color.TRANSPARENT)
	return img

static func landmark(variant: int) -> Image:
	var img := canvas(32, 32)
	match variant:
		0:
			poly(img, [[2,31],[5,13],[12,5],[17,6],[14,31]], INK)
			poly(img, [[17,31],[20,10],[26,15],[30,31]], INK)
			poly(img, [[5,29],[8,14],[13,9],[11,29]], ROCK)
			poly(img, [[20,29],[22,15],[25,18],[27,29]], ROCK)
		1:
			for p in [[3,15,7],[13,3,9],[23,12,6]]:
				poly(img, [[p[0],30],[p[0],p[1]+5],[p[0]+p[2]/2,p[1]],[p[0]+p[2],p[1]+5],[p[0]+p[2],30]], Color("416e78"))
				box(img, p[0]+2, p[1]+6, 2, 20-p[1], Color("94c8bf"))
		2:
			poly(img, [[1,31],[2,10],[8,3],[24,3],[30,10],[31,31],[26,31],[25,12],[21,8],[11,8],[7,12],[6,31]], INK)
			poly(img, [[3,30],[4,11],[9,5],[23,5],[28,11],[29,30],[27,30],[26,11],[22,7],[10,7],[6,11],[5,30]], Color("796549"))
	return img

static func raft(frame: int) -> Image:
	var img := canvas(48, 24)
	for i in 4:
		box(img, 2, 14+i*2, 43, 2, Color("8e704e") if i%2 else Color("b29261"))
	box(img, 10, 13, 2, 10, INK); box(img, 35, 13, 2, 10, INK)
	box(img, 23, 1, 2, 15, Color("b29261"))
	poly(img, [[25,2],[38,5+frame%2],[34,11],[25,10]], Color("dfd2ad"))
	return img

static func palette(theme: String) -> Array:
	if theme == "island_shore": return [Color("9b8669"), Color("665c59"), Color("d8c496")]
	return [Color("494752"), Color("2c303c"), Color("96909a")] if theme == "volcano" else [Color("3c414e"), Color("242a37"), Color("747f8b")]

static func terrain(theme: String) -> Image:
	var img := canvas(128, 32)
	var p := palette(theme)
	for variant in 4:
		for mask in 16:
			var x := mask*8
			var y := variant*8
			box(img,x,y,8,8,p[0])
			box(img,x+2,y+3+variant%2,3,1,p[1])
			box(img,x+5,y+2,1,3,p[1])
			if mask&1: box(img,x,y,8,1,p[2])
			if mask&2: box(img,x+7,y,1,8,p[1])
			if mask&4: box(img,x,y+7,8,1,p[1])
			if mask&8: box(img,x,y,1,8,p[2])
	return img

static func corners(theme: String) -> Image:
	var img := canvas(32,8)
	var p := palette(theme)
	for i in 4:
		box(img,i*8+(7 if i%2 else 0),7 if i>=2 else 0,1,1,p[2] if i<2 else p[1])
	return img

static func scenery(theme: String, foreground: bool) -> Image:
	var img := canvas(320,180)
	var cave := theme == "volcanic_cave"
	var shore := theme == "island_shore"
	var sky := Color("567b89") if shore else Color("514653")
	var silhouette := Color("334c59") if shore else Color("34333f")
	if cave: sky = Color("1e2636"); silhouette = Color("2e3748")
	if not foreground: img.fill(sky)
	if cave:
		for i in 12:
			var x := i*29-8
			box(img,x,0,12,25+posmod(i*17,55),silhouette)
			box(img,x+5,128-posmod(i*13,30),17,60,silhouette)
		if not foreground:
			poly(img,[[101,180],[106,77],[120,64],[144,63],[157,79],[165,180],[151,180],[147,87],[138,79],[121,80],[117,91],[115,180]],Color("394452"))
	else:
		if not foreground:
			# Stepped volcanic cone, open crater and a subdued angular ash plume.
			poly(img,[[61,153],[105,119],[135,89],[160,55],[176,59],[183,55],[204,83],[229,119],[278,153]],silhouette)
			poly(img,[[160,55],[168,57],[176,59],[183,55],[178,64],[169,64]],Color("8d645d"))
			for i in 5: box(img,165-i*5,45-i*7,20+i*5,5,Color("70606a"))
			if shore:
				box(img,0,149,320,31,Color("426674"))
				for i in 14: box(img,i*25,156+i%3*6,15,1,Color("71918e"))
		else:
			for i in 10:
				var y := 161+posmod(i*7,13)
				box(img,i*35-8,y,23,180-y,Color("313a42"))
	return img

static func decorations(theme: String) -> Image:
	var img := canvas(128,16)
	for i in 8:
		var p := palette(theme)
		poly(img,[[i*16+2,16],[i*16+3,11-i%3],[i*16+7,7-i%4],[i*16+13,11],[i*16+14,16]],p[1])
		box(img,i*16+5,10-i%3,4,2,p[2])
	return img
