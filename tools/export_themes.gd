extends SceneTree
## Original 8px environment art, matching Summit's native terrain scale.
const THEMES := {
	"sand": ["d7af6c", "a67749", "f6d990", "6b7791", "343952", "efbe78"],
	"sea": ["477e8a", "285269", "8acabb", "24475e", "122d46", "e1b992"],
	"cavern": ["626079", "3f405a", "9392a4", "242b42", "151d32", "83bba6"],
	"cavern_deep": ["374655", "222c40", "648283", "101a2c", "090f20", "74dcca"],
	"sky": ["aaa1a1", "766f86", "ede0c5", "89a8bf", "d1c8bf", "f2e6ca"],
	"temple": ["a59b81", "6d706a", "dbcfaa", "424f60", "252e43", "b6b789"],
	"building": ["b4a58b", "6b5a50", "e0cda5", "71858a", "354b50", "e9bb75"],
}
func box(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.has_area(): img.fill_rect(r, col)
func canvas(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)
func tile(theme: String, mask: int, variant := 0) -> Image:
	var p: Array = THEMES[theme]
	var body := Color(p[0]); var shade := Color(p[1]); var light := Color(p[2])
	var img := canvas(8, 8)
	img.fill(body)
	# bits indicate exposed edges: top=1, right=2, bottom=4, left=8.
	if theme == "building":
		box(img, 0, 6, 8, 2, shade)
		box(img, 0, 0, 1, 8, shade)
		if variant % 2:
			for y in 6: box(img, y+1, y, 1, 1, shade)
		else: box(img, 4, 3, 2, 1, body.darkened(0.1))
	elif theme == "temple":
		box(img, 0, 4, 8, 1, shade)
		box(img, 3 + variant % 2, 0, 1, 4, shade)
		box(img, 6, 5, 1, 3, shade)
	else:
		box(img, 2 + variant % 3, 3, 2, 1, shade)
		box(img, 5, 6 - variant % 2, 1, 1, light.darkened(0.12))
		if theme == "sand": box(img, 0, 6, 4, 1, body.darkened(0.08))
		if theme == "sea": box(img, 1, 5, 1, 2, Color(p[5]))
	if mask & 1:
		box(img, 0, 0, 8, 1, light)
		box(img, 0, 1, 8, 1, body.lightened(0.12))
	if mask & 2: box(img, 7, 0, 1, 8, shade)
	if mask & 4: box(img, 0, 7, 8, 1, shade.darkened(0.12))
	if mask & 8: box(img, 0, 0, 1, 8, light.darkened(0.1))
	return img
func background(theme: String, foreground: bool) -> Image:
	var p: Array = THEMES[theme]
	var img := canvas(320, 180)
	var distant := Color(p[3]); var near := Color(p[4]); var accent := Color(p[5])
	if not foreground:
		img.fill(distant)
		for y in 180: box(img, 0, y, 320, 1, distant.lerp(near, float(y) / 240.0))
	var col := near if foreground else distant.lerp(near, 0.5)
	var base := 172 if foreground else 143
	match theme:
		"sand":
			for x in 320:
				var y := base - 12 - int(sin(float(x) / 48.0) * 11 + cos(float(x) / 25.0) * 4)
				box(img, x, y, 1, 180-y, col)
			if not foreground:
				for y in 17: box(img, 239-(8-absi(y-8)), 27+y, 2*(8-absi(y-8))+1, 1, accent)
		"sea":
			for x in 320:
				var y := base - int(sin(float(x) / 18.0) * 3)
				box(img, x, y, 1, 180-y, col)
			for i in 12:
				var x := i*27+6
				if foreground:
					for y in 26: box(img, x+int(sin(y*0.3+i)*2), 151+y, 2, 2, col.lightened(0.1))
				else: box(img, x, 110+i%3*9, 13, 1, distant.lightened(0.15))
		"cavern", "cavern_deep":
			for x in 320:
				var tooth := int(abs(sin(float(x) / 19.0)) * (24 if foreground else 42))
				box(img, x, 0, 1, tooth+8, col)
				box(img, x, base-tooth/2, 1, 180, col)
			if theme == "cavern_deep":
				for i in 10:
					var x := i*31+8
					box(img, x, 145-i%3*7, 2, 7, accent.darkened(0.25) if foreground else accent.darkened(0.6))
		"sky":
			for i in 7:
				var x := i*49-8; var y := 22+i%3*38 if not foreground else 153+i%2*10
				box(img, x+6, y, 25, 4, col)
				box(img, x, y+4, 42, 5, col)
				box(img, x+8, y+9, 30, 3, col)
		"temple":
			for i in 5:
				var x := i*72+12; var y := 65+i%2*23
				box(img, x, y, 9, 180-y, col)
				box(img, x-3, y, 15, 4, col)
				box(img, x+37, y, 9, 180-y, col)
				box(img, x, y-5, 46, 5, col)
		"building":
			# Low cottages, pitched roofs, timber frames and hedges.
			for x in 320:
				var hill := 148 + int(sin(float(x)/39.0)*8)
				box(img,x,hill,1,180-hill,col)
			for i in 5:
				var x := i*73-14; var y := 114+i%2*13
				var wall := col.lightened(0.13)
				box(img,x,y,40,35,wall)
				for roof_y in 19: box(img,x+20-roof_y,y-19+roof_y,roof_y*2+1,1,col)
				box(img,x+29,y-23,4,15,col)
				box(img,x+2,y,2,35,col); box(img,x+36,y,2,35,col)
				box(img,x,y+17,40,2,col)
				box(img,x+17,y+19,7,16,col)
				for wx in [8,27]:
					box(img,x+wx,y+6,6,7,accent.darkened(0.35) if foreground else wall.lightened(0.12))
					box(img,x+wx+2,y+6,1,7,col)
				# Fence between cottages.
				box(img,x+42,y+24,29,2,col)
				for post in 4: box(img,x+43+post*8,y+20,2,14,col)

	return img
func decorations(theme: String) -> Image:
	var img := canvas(128, 16)
	var p: Array = THEMES[theme]
	for i in 8:
		var x := i*16; var col := Color(p[5]); var dark := Color(p[1])
		match theme:
			"sand":
				box(img,x+6,5,3,11,col); box(img,x+2,8,4,3,col); box(img,x+10,3,2,6,col)
			"sea":
				for y in 12: box(img,x+6+int(sin(y*0.7+i)*2),y+4,2,1,col)
				box(img,x+2,10,5,2,col); box(img,x+9,7,4,2,col)
			"cavern", "cavern_deep":
				for y in 12: box(img,x+7-y/4,4+y,1+y/2,1,col if i%2==0 else dark)
			"sky":
				box(img,x+3,8,10,4,col); box(img,x+6,5,5,4,col)
			"temple":
				box(img,x+5,3,6,13,col); box(img,x+3,2,10,3,col); box(img,x+7,6,1,8,dark)
			"building":
				match i % 4:
					0: # fence
						box(img,x+1,8,14,2,col); box(img,x+1,12,14,1,col)
						box(img,x+2,5,2,11,dark); box(img,x+12,5,2,11,dark)
					1: # barrel
						box(img,x+4,5,8,11,dark); box(img,x+5,6,6,9,col.darkened(0.2))
						box(img,x+4,8,8,1,dark); box(img,x+4,13,8,1,dark)
					2: # wheat
						for stem in 3:
							box(img,x+4+stem*4,6-stem%2*3,1,10,col)
							box(img,x+3+stem*4,5-stem%2*3,3,3,col)
					3: # signpost
						box(img,x+7,4,2,12,dark); box(img,x+2,3,12,5,col)
						box(img,x+4,5,7,1,dark)
		# Alternate height/damage silhouettes rather than recolours alone.
		if i%2: box(img,x+1,0,14,3+i%4,Color.TRANSPARENT)
	return img
func _initialize() -> void:
	for theme in THEMES:
		var dir: String = "res://assets/themes/"+theme
		DirAccess.make_dir_recursive_absolute(dir)
		var atlas := canvas(128,32)
		for variant in 4:
			for mask in 16: atlas.blit_rect(tile(theme,mask,variant),Rect2i(0,0,8,8),Vector2i(mask*8,variant*8))
		atlas.save_png(dir+"/terrain.png")
		var corners := canvas(32,8)
		for corner in 4:
			var cx := corner*8 + (7 if corner%2 else 0)
			var cy := 7 if corner>=2 else 0
			box(corners,cx,cy,1,1,Color(THEMES[theme][2 if corner<2 else 1]))
			box(corners,cx + (-1 if corner%2 else 1),cy,1,1,Color(THEMES[theme][0]).lightened(0.08))
		corners.save_png(dir+"/inner_corners.png")
		var far := background(theme,false); var near := background(theme,true)
		far.save_png(dir+"/background.png"); near.save_png(dir+"/foreground.png")
		var props := decorations(theme); props.save_png(dir+"/decorations.png")
		var scene := far.duplicate()
		scene.blend_rect(near,Rect2i(0,0,320,180),Vector2i.ZERO)
		for y in range(19,23):
			for x in 40:
				var surface := 21 if x>12 and x<24 else 19
				if y<surface: continue
				var mask := 1 if y==surface else 0
				scene.blit_rect(tile(theme,mask,(x+y)%4),Rect2i(0,0,8,8),Vector2i(x*8,y*8))
		for i in 8: scene.blend_rect(props,Rect2i(i*16,0,16,16),Vector2i(i*40,136 if i<3 or i>4 else 152))
		scene.save_png(dir+"/preview.png")
		print("EXPORTED ",theme," (terrain + two scenery layers + decorations + preview)")
	quit()
