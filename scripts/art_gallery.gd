extends VBoxContainer
# Art screen (main menu → Art): every image in assets/, one folder per section. Sheets are cut into their single
# sprites (cell sizes from each folder's manifest.json, or the layouts below), one row per pose or variant, every
# sprite at its true size (1 art px = 1 screen px); full-screen backdrops at 30%. Read-only. Uses
# ResourceLoader.list_directory so it works in exported builds too.

const SKIP := ["res://assets/themes/review/"]  # before/after review shots, not game art
const BACKDROPS := ["background", "foreground", "preview"]  # full-screen images: shown whole, at 30%
const BACKDROP_SCALE := 0.3
const CharacterArt := preload("res://scripts/character_art.gd")
# Sheets without a manifest: [cell w, cell h, frames per row, row names] (empty names: "row N")
const LAYOUTS := {
	"enemies/ape.png": [32, 32, 4, ["idle", "crouch", "air", "throw", "scream", "run", "land"]],
	"paper-pixels/Tiles.png": [8, 8, 18, []],
	"terrain.png": [8, 8, 16, ["variant 1", "variant 2", "variant 3", "variant 4"]],
	"inner_corners.png": [8, 8, 4, ["corners"]],
	"decorations.png": [16, 16, 8, ["props"]],
}

var sections := {}  # title -> [[name, Texture2D, path], ...]
var order: Array = []
var current := ""
var list: VBoxContainer
var buttons: Control
var manifests := {}  # folder -> parsed manifest.json

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_collect("res://assets/")
	order.sort()
	var flow := HFlowContainer.new()  # section buttons, wrapping
	flow.custom_minimum_size = Vector2(860, 0)
	add_child(flow)
	for title in order:
		var b := Game.button("%s (%d)" % [title, sections[title].size()], _show.bind(title))
		b.add_theme_font_size_override("font_size", 16)
		b.set_meta("section", title)
		flow.add_child(b)
	buttons = flow
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.custom_minimum_size.x = 840
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if not order.is_empty():
		_show(order[0])
	get_viewport().size_changed.connect(func(): if current != "": _show(current))  # keep 1:1 when the window changes

# Every PNG under dir, grouped by folder ("themes/forest" -> "Theme: forest").
func _collect(dir: String) -> void:
	if SKIP.any(func(s): return dir.begins_with(s)):
		return
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with("/"):
			_collect(dir + f)
		elif f.ends_with(".png"):
			var tex = load(dir + f)
			if tex is Texture2D:
				var title := _title(dir)
				if not sections.has(title):
					sections[title] = []
					order.append(title)
				sections[title].append([f.get_basename(), tex, dir + f])

static func _title(dir: String) -> String:
	var rel := dir.trim_prefix("res://assets/").trim_suffix("/")
	if rel.begins_with("themes/"):
		return "Theme: " + rel.get_slice("/", 1)
	return rel.capitalize() if rel != "" else "Other"

func _manifest(dir: String) -> Dictionary:
	if not manifests.has(dir):
		var text := FileAccess.get_file_as_string(dir + "manifest.json")
		var m = JSON.parse_string(text) if text != "" else null
		manifests[dir] = m if m is Dictionary else {}
	return manifests[dir]

# The single sprites of a sheet: [[row label, [Rect2i, ...]], ...]; empty for an image shown whole.
func rows_of(path: String, tex: Texture2D) -> Array:
	var dir := path.get_base_dir() + "/"
	var file := path.get_file()
	var rel := path.trim_prefix("res://assets/")
	var m := _manifest(dir)
	for a in m.get("assets", []):  # island: per-file cell, rows = appearance x pose, four frames
		if a.file == file:
			var names := []
			for v in int(a.get("variants", 1)):
				for pose in a.poses:
					names.append(pose if int(a.get("variants", 1)) == 1 else "%d %s" % [v + 1, pose])
			return _grid(tex, Vector2i(int(a.cell[0]), int(a.cell[1])), 4, names)
	for sh in m.get("sheets", []):
		if sh.file == file:
			if sh.has("sizes"):  # blocks: one cell per example size, each cropped to its size; breakwall damage row
				var cw := int(m.cell[0])
				var rects := []
				for i in sh.sizes.size():
					rects.append(Rect2i(i * cw, 0, int(sh.sizes[i][0]), int(sh.sizes[i][1])))
				var out := [["sizes", rects]]
				if sh.rows.size() > 1:
					out.append(["damage", [0, 1, 2].map(func(d): return Rect2i(d * cw, int(m.cell[1]), 32, 32))])
				return out
			return _grid(tex, Vector2i(int(m.cell[0]), int(m.cell[1])), int(m.get("frames", 4)), sh.rows.map(func(r): return str(r).trim_prefix("enemy_")))
	if rel == "nori/nori.png":
		var names := []
		names.resize(CharacterArt.ANIMATIONS.size())
		for n in CharacterArt.ANIMATIONS:
			names[CharacterArt.ANIMATIONS[n][0]] = n
		return _grid(tex, Vector2i(16, 16), 8, names)
	for key in LAYOUTS:
		if rel == key or (not key.contains("/") and file == key):
			var l: Array = LAYOUTS[key]
			return _grid(tex, Vector2i(l[0], l[1]), l[2], l[3])
	return []

# Cut a sheet into cells, one row per sheet row, leaving out empty cells.
static func _grid(tex: Texture2D, cell: Vector2i, per_row: int, names: Array) -> Array:
	var img := tex.get_image()
	var out := []
	for r in tex.get_height() / cell.y:
		var rects := []
		for c in mini(per_row, tex.get_width() / cell.x):
			var rect := Rect2i(c * cell.x, r * cell.y, cell.x, cell.y)
			if not img.get_region(rect).is_invisible():
				rects.append(rect)
		if not rects.is_empty():
			out.append([names[r] if r < names.size() and str(names[r]) != "" else "row %d" % (r + 1), rects])
	return out

# Screen pixels per UI unit: the window scales the whole UI to its height (stretch mode canvas_items), so a sprite
# sized in UI units would be enlarged by that factor, unevenly when it isn't whole. Dividing by it puts one art
# pixel on exactly one physical screen pixel.
func _ui_scale() -> float:
	return get_viewport().get_final_transform().get_scale().y if is_inside_tree() else 1.0

# Show one section: per image a title line, then its sprites row by row (or the whole image if it isn't a sheet).
func _show(title: String) -> void:
	current = title
	for b in buttons.get_children():  # the open section stands out
		b.modulate = Color("ffd34e") if b.get_meta("section") == title else Color.WHITE
	for c in list.get_children():
		c.queue_free()
	for item in sections[title]:
		var tex: Texture2D = item[1]
		var rows := rows_of(item[2], tex)
		var head := Label.new()
		head.text = "%s   %dx%d%s" % [item[0], tex.get_width(), tex.get_height(), "   (30%)" if item[0] in BACKDROPS else ""]
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", Color("ffd34e"))
		list.add_child(head)
		if rows.is_empty():
			var k := BACKDROP_SCALE if item[0] in BACKDROPS else 1.0
			list.add_child(_pic(tex, Rect2i(Vector2i.ZERO, Vector2i(tex.get_width(), tex.get_height())), k / _ui_scale(), k == 1.0))
			continue
		for row in rows:
			var line := HFlowContainer.new()
			line.add_theme_constant_override("h_separation", 6)
			var l := Label.new()
			l.text = row[0]
			l.custom_minimum_size.x = 120
			l.add_theme_font_size_override("font_size", 13)
			line.add_child(l)
			for rect in row[1]:
				line.add_child(_pic(tex, rect, 1.0 / _ui_scale(), true))
			list.add_child(line)

# One sprite (a region of a sheet), k UI units per art pixel; crisp: nearest filtering (sprites at 1:1).
static func _pic(tex: Texture2D, rect: Rect2i, k: float, crisp: bool) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(rect)
	var pic := TextureRect.new()
	pic.texture = at
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if crisp else CanvasItem.TEXTURE_FILTER_LINEAR
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = Vector2(rect.size) * k
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pic
