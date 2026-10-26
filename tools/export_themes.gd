extends SceneTree
# Offline procedural authoring of environment terrain, paintings and decorative sprites. Running it rewrites generated theme assets, so normal gameplay only loads its outputs.
# Reading help: docs/CODE_GUIDE.md.

## Original 8px environment art, matching Summit's native terrain scale.
const THEMES := {
	"sand": ["d7af6c", "a67749", "f6d990", "6b7791", "343952", "efbe78"],
	"sea": ["477e8a", "285269", "8acabb", "24475e", "122d46", "e1b992"],
	"cavern": ["626079", "3f405a", "9392a4", "242b42", "151d32", "83bba6"],
	"cavern_deep": ["374655", "222c40", "648283", "101a2c", "090f20", "74dcca"],
	"sky": ["aaa1a1", "766f86", "ede0c5", "89a8bf", "d1c8bf", "f2e6ca"],
	"temple": ["a59b81", "6d706a", "dbcfaa", "424f60", "252e43", "b6b789"],
	"building": ["b4a58b", "6b5a50", "e0cda5", "71858a", "354b50", "e9bb75"],
	"forest": ["5e4a36", "3a2c22", "7fae4e", "2f5a3c", "17301f", "a8d86a"],
}
# Fill a clipped rectangle in the generated image; coordinates are image pixels.
func box(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.has_area(): img.fill_rect(r, col)
# Create a transparent image of the requested pixel dimensions.
func canvas(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)
# Draw one terrain tile using its exposed-edge bit mask and stable visual variant.
func tile(theme: String, mask: int, variant := 0) -> Image:
	var p: Array = THEMES[theme]
	var body := Color(p[0]); var shade := Color(p[1]); var light := Color(p[2])
	var img := canvas(8, 8)
	img.fill(body)
	# Quiet material clusters; edge masks still follow the original 8px grid.
	var grain := body.lerp(shade, 0.28)
	var glint := body.lerp(light, 0.24)
	match theme:
		"sand":
			box(img,0,3+variant%2,5,1,grain)
			box(img,4,6,4,1,glint)
			if variant == 2: box(img,6,2,1,1,grain)
		"sea":
			box(img,1,5,4,1,grain); box(img,4,2,3,1,glint)
			if variant%2:
				box(img,2,2,2,2,body.lerp(Color(p[5]),0.45))
				box(img,3,2,1,1,grain)
		"cavern", "cavern_deep":
			box(img,0,2+variant%3,4,1,grain)
			box(img,4,4+variant%2,4,1,glint)
			box(img,3,3+variant%2,1,2,grain)
			if theme == "cavern_deep" and variant==3:
				box(img,5,2,1,2,body.lerp(Color(p[5]),0.28))
		"sky":
			box(img,1,3,4,1,glint)
			box(img,3+variant%2,5,3,1,grain)
		"temple":
			box(img,0,6,8,1,grain)
			box(img,2+variant%3,0,1,6,grain)
			box(img,3+variant%3,1,3,1,glint)
			if variant==3: box(img,5,3,1,2,grain)
		"building":
			# Plaster with occasional exposed timber, not a lattice on every cell.
			box(img,1,5,4,1,grain)
			if variant==0: box(img,0,0,2,8,shade.lerp(body,0.3))
			if variant==2:
				box(img,5,2,2,3,grain); box(img,5,2,1,2,glint)
		"forest":
			box(img,0,3+variant%2,5,1,grain)
			box(img,4,6,3,1,glint)
			if variant==2:
				box(img,2,1,1,4,body.lerp(light,0.14))
				box(img,3,4,2,1,body.lerp(light,0.14))

	if mask & 1 and theme == "forest":  # grass top with a ragged edge
		box(img, 0, 0, 8, 1, light)
		box(img, 0, 1, 8, 1, light.darkened(0.22))
		box(img, variant % 4 * 2, 2, 2, 1, light.darkened(0.2))
	elif mask & 1:
		box(img, 0, 0, 8, 1, light)
		box(img, 0, 1, 8, 1, body.lightened(0.12))
	if mask & 2: box(img, 7, 0, 1, 8, shade)
	if mask & 4: box(img, 0, 7, 8, 1, shade.darkened(0.12))
	if mask & 8: box(img, 0, 0, 1, 8, light.darkened(0.1))
	return img
# Create a layered theme painting for background or foreground use.
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
				var y: int = base - 12 - [0, 0, 4, 8, 8, 12, 12, 8, 4, 4, 0, -4, -4, -8, -8, -4, 0, 4, 4, 0][(x / 16) % 20]
				box(img, x, y, 1, 180-y, col)
			if not foreground:
				for y in 17: box(img, 239-(8-absi(y-8)), 27+y, 2*(8-absi(y-8))+1, 1, accent)
		"sea":
			for x in 320:
				var y: int = base - [0, 0, 2, 2, 0, 0, -2, -2][(x / 8) % 8]
				box(img, x, y, 1, 180-y, col)
			for i in 12:
				var x := i*27+6
				if foreground:
					for y in 26: box(img, x+((y / 6 + i) % 3 - 1)*2, 151+y, 2, 2, col.lightened(0.1))
				else: box(img, x, 110+i%3*9, 13, 1, distant.lightened(0.15))
		"cavern", "cavern_deep":
			for x in 320:
				var tooth: int = [8, 8, 16, 24, 24, 12, 12, 32, 20, 20, 8, 16, 16, 28, 28, 12, 36, 36, 20, 8][(x / 16) % 20] + (0 if foreground else 8)
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
		"forest":
			forest_layer(img, foreground, col, accent)

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
				var hill: int = 148 + [0, 0, 4, 4, 8, 8, 4, 0, -4, -4][(x / 16) % 10]
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

	background_details(img, theme, foreground, col, accent)
	return img
# Broad rectangular masses with two clear steps; never approximate an ellipse.
# Add a group of pixel rectangles forming one background silhouette.
func block_cluster(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	var tier := maxi(1, h / 3)
	var inset := maxi(1, w / 5)
	box(img, x, y + tier, w, h - tier, col)
	box(img, x + inset, y, w - inset * 2, tier, col)
	box(img, x + w - inset * 2, y + tier / 2, inset, tier, col)
# Compose a forest scenery layer with the supplied depth and palette.
func forest_layer(img: Image, foreground: bool, col: Color, accent: Color) -> void:
	var bark := col.lightened(0.045)
	var leaf := col.lerp(accent,0.075)
	# Uneven spacing leaves a quiet clearing around the player.
	var positions := [-13,39,116,212,288] if foreground else [18,83,155,244,315]
	for i in positions.size():
		var x: int = positions[i]
		var width := (13+i%3*3) if foreground else 6+i%2*3
		var bend := 3 if i%2 else -3
		box(img,x,17,width,163,col)
		box(img,x+bend,0,width,66,col)
		box(img,x+2,45,2,55,bark)
		box(img,x+width-4,113,1,28,bark)
		for branch in 3:
			var y := 31+branch*18+i%3*6
			for step in 12:
				var dx := step if (i+branch)%2 else -step
				box(img,x+width/2+dx,y-step/2,3,3,col)
		box(img,x-5,155,width+10,7,col)
		box(img,x-9,162,width+18,18,col)
		block_cluster(img,x-28,-12,68,44,col)
		block_cluster(img,x-12,9,43,22,leaf)
		if not foreground:
			var vine_x := x+width+9
			var length := 27+i%3*14
			for y in length:
				box(img,vine_x+((y / 12) % 2)*2,31+y,1,1,leaf.lightened(0.04))
			for y in range(38,31+length,9): box(img,vine_x-1,y,3,1,leaf.lightened(0.07))
	for i in 12:
		block_cluster(img,i*29-10,154+i%3*3,38,24,col)
		if foreground: box(img,i*29+2,156+i%3*3,6,1,leaf)
# Add theme-specific scenery details without adding gameplay collision.
func background_details(img: Image, theme: String, foreground: bool, col: Color, accent: Color) -> void:
	var soft := col.lightened(0.055)
	match theme:
		"sand":
			if not foreground:
				for i in 3:
					var x := i*107+24; var y := 96+i%2*16
					box(img,x,y,18,60,col); box(img,x-4,y+14,26,39,col)
					box(img,x+2,y+2,2,29,soft)
					box(img,x-2,y+22,21,2,soft)
			else:
				for i in 8: box(img,i*43,161+i%3*3,23,1,soft)
		"sea":
			if not foreground:
				for i in 5:
					var x := i*74-6; var y := 111-i%3*12
					box(img,x,y,11,43,col); box(img,x-3,y+8,19,30,col)
					box(img,x+1,y,7,1,soft)
				for i in 10: box(img,i*37,139+i%3*7,17-i%4,1,soft)
			else:
				for i in 7:
					var x := i*49+9
					box(img,x,153+i%3*4,3,27,col)
					box(img,x-5,157+i%3*4,6,2,soft)
		"cavern", "cavern_deep":
			for i in 9:
				var x := i*41-5; var height := 16+(i*17)%37
				# Angular formations add depth to the stepped cave ceiling.
				for y in height: box(img,x+y/6,y,maxi(1,12-y/4),1,col)
				if foreground: box(img,x+2,7,1,height/2,soft)
			if not foreground:
				for i in 6:
					var x := i*61+7
					box(img,x,62+i%3*13,3,75,col)
					box(img,x-7,121+i%3*4,25,2,soft)
			if theme=="cavern_deep":
				for i in 11:
					var x := i*31+12; var y := 142-i%3*5
					var glow := col.lerp(accent,0.22 if foreground else 0.11)
					box(img,x-2,y+3,7,1,glow.darkened(0.1))
					box(img,x,y,2,4,glow)
		"sky":
			for i in 4:
				var x := i*91-15; var y := 29+i%3*32
				block_cluster(img,x+8,y,35+i%2*14,12,soft)
				block_cluster(img,x,y+6,66,13,col.lightened(0.025))
				box(img,x+12,y+17,37,2,col)
			if not foreground:
				for i in 3:
					var x := i*119+42; var y := 127-i%2*26
					box(img,x,y,24,2,soft)
					for yy in 10: box(img,x+yy,y+2+yy,24-yy*2,1,col)
		"temple":
			for i in 5:
				var x := i*72+12; var y := 65+i%2*23
				box(img,x+2,y+7,1,57,soft); box(img,x+39,y+8,1,60,soft)
				box(img,x-2,y-4,42,1,soft)
				box(img,x-3,136,15,3,col)
				box(img,x+36,140,16,3,col)
				if i%2==0:
					box(img,x+10,y-5,4,5,Color.TRANSPARENT if foreground else Color(THEMES[theme][3]))
					for yy in 18: box(img,x+2,y+4+yy,1,1,col.lerp(accent,0.12))
		"building":
			for i in 5:
				var x := i*73-14; var y := 114+i%2*13
				for roof_y in range(5,19,4): box(img,x+20-roof_y,y-19+roof_y,roof_y*2+1,1,soft)
				box(img,x-1,y,42,2,col)
				box(img,x+3,y+4,1,29,soft)
				for step in 14:
					box(img,x+4+step,y+3+step,1,1,col)
					box(img,x+34-step,y+3+step,1,1,col)
				for wx in [8,27]: box(img,x+wx,y+9,6,1,col)
				if not foreground:
					block_cluster(img,x+27,y-31,7,5,soft)
					block_cluster(img,x+29,y-37,10,4,soft)
# Build the theme prop sheet used for small visual accents above terrain.
func decorations(theme: String) -> Image:
	var img := canvas(128,16)
	var p: Array = THEMES[theme]
	var accent := Color(p[5]); var shadow := Color(p[1])
	var mid := Color(p[0]).lerp(accent,0.35)
	for i in 8:
		var x := i*16; var kind := i%4; var shift := i/4
		match theme:
			"forest":
				match kind:
					0: # fern fronds
						box(img,x+7,6-shift,1,10+shift,shadow)
						for j in 4:
							box(img,x+3+j,8+j*2,4-j,1,mid)
							box(img,x+8,7+j*2,4-j,1,accent.darkened(0.12))
					1: # berry shrub
						block_cluster(img,x+2,8-shift,12,8+shift,shadow)
						block_cluster(img,x+3,7-shift,10,6,mid)
						box(img,x+5,9-shift,3,1,accent)
						box(img,x+10,11,1,1,Color("c27768"))
					2: # mossy stump
						box(img,x+4,9-shift*2,7,7+shift*2,shadow)
						box(img,x+5,10,1,5,mid)
						box(img,x+3,8-shift*2,9,2,mid)
						box(img,x+5,8-shift*2,4,1,accent.darkened(0.12))
					3: # paired mushrooms
						box(img,x+5,10,1,6,mid); box(img,x+10,12,1,4,mid)
						block_cluster(img,x+2,7-shift,7,4,accent.darkened(0.22))
						block_cluster(img,x+8,10,6,3,mid)
			"sand":
				if kind<2:
					box(img,x+6,5-shift*2,3,11+shift*2,shadow)
					box(img,x+6,5-shift*2,1,10,mid)
					box(img,x+3,9,4,2,shadow); box(img,x+3,6,2,4,mid)
					if kind==1: box(img,x+9,7,4,2,mid); box(img,x+11,4,2,4,mid)
				else:
					block_cluster(img,x+2,12-shift,12,4+shift,shadow)
					box(img,x+4,12-shift,6,1,mid)
			"sea":
				if kind<2:
					box(img,x+7,7,2,9,shadow)
					for j in 3:
						box(img,x+3+j*3,5+absi(j-1)*3-shift,2,8,mid)
						box(img,x+4+j*3,4+absi(j-1)*3-shift,2,2,accent.darkened(0.15))
				else:
					block_cluster(img,x+3,11-shift,10,5+shift,mid)
					box(img,x+5,11-shift,1,3,accent); box(img,x+8,10,1,4,shadow)
			"cavern", "cavern_deep":
				for shard in 2+kind%2:
					var height := 5+(shard*3+kind+shift*2)%8
					var xx := x+3+shard*4
					for y in height: box(img,xx-y/5,16-height+y,2+y/4,1,shadow)
					box(img,xx,17-height,1,height-2,mid if theme=="cavern" else accent.darkened(0.16+kind*0.06))
			"sky":
				if kind<2:
					block_cluster(img,x+1,11,14,5,mid)
					block_cluster(img,x+4,8-shift,8,6,accent)
				else:
					box(img,x+7,8-shift,1,8+shift,shadow)
					for j in 3: box(img,x+5-j,9+j*2,3+j,1,mid)
			"temple":
				var top := 4+kind*2-shift
				box(img,x+4,top,8,16-top,shadow)
				box(img,x+5,top+2,2,13-top,mid)
				box(img,x+3,top,10,2,accent.darkened(0.15))
				box(img,x+2,14,12,2,shadow)
				if kind%2: box(img,x+8,top,2,2,Color.TRANSPARENT)
			"building":
				match kind:
					0:
						box(img,x+1,9,14,2,mid); box(img,x+1,13,14,1,mid)
						box(img,x+2,6,2,10,shadow); box(img,x+12,6,2,10,shadow)
						box(img,x+2,6,1,9,accent)
					1:
						box(img,x+4,5,8,11,shadow); box(img,x+5,6,6,9,mid)
						box(img,x+7,7,1,7,accent.darkened(0.15))
						box(img,x+4,8,8,1,shadow); box(img,x+4,13,8,1,shadow)
					2:
						for stem in 3:
							var xx := x+4+stem*4; var yy := 5-stem%2*2-shift
							box(img,xx,yy,1,16-yy,mid)
							box(img,xx-1,yy,3,3,accent)
					3:
						box(img,x+7,5,2,11,shadow); box(img,x+2,4-shift,12,5,shadow)
						box(img,x+3,5-shift,10,2,mid); box(img,x+4,5-shift,4,1,accent)
	return img
# Run this offline image export and quit; output images are regenerated from the authored source.
func _initialize() -> void:
	var theme_index := 0
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
		theme_index += 1
		print("EXPORTED ",theme," (terrain + two scenery layers + decorations + preview)")
	quit()
