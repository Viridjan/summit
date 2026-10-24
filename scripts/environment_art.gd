extends RefCounted
## Room-local environment graphics; collision still reads the original tile grid.
const THEMES := ["sand", "sea", "cavern", "cavern_deep", "sky", "temple", "building", "forest"]
static var _textures: Dictionary = {}
static func texture(environment: String, asset: String) -> Texture2D:
	var key := environment + "/" + asset
	if not _textures.has(key):
		_textures[key] = load("res://assets/themes/%s/%s.png" % [environment, asset])
	return _textures[key]
static func solid(tiles: Array, w: int, h: int, x: int, y: int) -> bool:
	return x < 0 or y < 0 or x >= w or y >= h or tiles[y].unicode_at(x) == 49
static func draw_range(ci: CanvasItem, tiles: Array, w: int, h: int, x0: int, y0: int, x1: int, y1: int, environment: String) -> void:
	var atlas := texture(environment, "terrain")
	var corners := texture(environment, "inner_corners")
	var props := texture(environment, "decorations")
	for y in range(y0, y1):
		for x in range(x0, x1):
			if tiles[y].unicode_at(x) != 49: continue
			var up := solid(tiles,w,h,x,y-1)
			var right := solid(tiles,w,h,x+1,y)
			var down := solid(tiles,w,h,x,y+1)
			var left := solid(tiles,w,h,x-1,y)
			var mask := (0 if up else 1) + (0 if right else 2) + (0 if down else 4) + (0 if left else 8)
			var code := absi(hash(Vector2i(x,y)))
			var dest := Rect2(x*8,y*8,8,8)
			ci.draw_texture_rect_region(atlas,dest,Rect2(mask*8,(code%4)*8,8,8))
			for corner in 4:
				var dx := 1 if corner%2 else -1
				var dy := 1 if corner>=2 else -1
				if (right if dx==1 else left) and (down if dy==1 else up) and not solid(tiles,w,h,x+dx,y+dy):
					ci.draw_texture_rect_region(corners,dest,Rect2(corner*8,0,8,8))
			# Props require two clear cells overhead; they never affect collision.
			if not up and y>=2 and code%11==0 and not solid(tiles,w,h,x,y-2) and not solid(tiles,w,h,x+1,y-1) and not solid(tiles,w,h,x+1,y-2):
				ci.draw_texture_rect_region(props,Rect2(x*8,y*8-16,16,16),Rect2((code/11%8)*16,0,16,16))
# Where the camera is in the room (area) sets the perspective: a smooth shift, at most the 10% overscan
# (slack) each way, so the picture never jumps. 0 when the room fits the view.
static func parallax_shift(view: Rect2, area: Rect2) -> Vector2:
	var slack := view.size * 0.1
	var t := Vector2(0.5, 0.5)
	if area.size.x > view.size.x: t.x = clampf((view.position.x - area.position.x) / (area.size.x - view.size.x), 0, 1)
	if area.size.y > view.size.y: t.y = clampf((view.position.y - area.position.y) / (area.size.y - view.size.y), 0, 1)
	return (Vector2(0.5, 0.5) - t) * 2 * slack
# clip (optional): draw only inside it, e.g. one room's part of the screen during a room transition.
static func draw_background(ci: CanvasItem, view: Rect2, environment: String, area := Rect2(), clip := Rect2()) -> void:
	# Room-sized paintings that stay with the camera; only the perspective shifts (parallax_shift).
	var extent := view.size * 1.2
	var slack := view.size * 0.1
	var shift := parallax_shift(view, area)
	_painting(ci, texture(environment, "background"), Rect2(view.position + (shift * 0.4 - slack).floor(), extent), clip)
	_painting(ci, texture(environment, "foreground"), Rect2(view.position + (shift - slack).floor(), extent), clip)
static func _painting(ci: CanvasItem, tex: Texture2D, dest: Rect2, clip: Rect2) -> void:
	if not clip.has_area():
		ci.draw_texture_rect(tex, dest, false)
		return
	var part := dest.intersection(clip)
	if part.has_area():
		var k := tex.get_size() / dest.size
		ci.draw_texture_rect_region(tex, part, Rect2((part.position - dest.position) * k, part.size * k))
