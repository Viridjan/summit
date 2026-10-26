extends VBoxContainer
# Art screen (main menu → Art): every sprite sheet and theme image in assets/, one section at a time, plus the
# Ape's poses (drawn in code). Read-only. Uses ResourceLoader.list_directory so it works in exported builds too.

const ApeArt := preload("res://scripts/ape_art.gd")
const CELL := 110.0  # minimum cell width (px); images show at their true size (1 art px = 1 screen px)
const SKIP := ["res://assets/themes/review/"]  # before/after review shots, not game art
const APE_POSES := ["idle", "crouch", "air", "land", "throw", "scream", "run"]

var sections := {}  # title -> [[name, Texture2D], ...]
var order: Array = []
var current := ""
var grid: HFlowContainer
var buttons: Control

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_collect("res://assets/")
	var ape := []
	for pose in APE_POSES:
		ape.append([pose, ApeArt.texture(pose, 0)])
	sections["Ape"] = ape
	order.append("Ape")
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
	grid = HFlowContainer.new()  # cells as wide as their image: big sheets take a whole row
	grid.custom_minimum_size.x = 840
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	if not order.is_empty():
		_show(order[0])

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
				sections[title].append([f.get_basename(), tex])

static func _title(dir: String) -> String:
	var rel := dir.trim_prefix("res://assets/").trim_suffix("/")
	if rel.begins_with("themes/"):
		return "Theme: " + rel.get_slice("/", 1)
	return rel.capitalize() if rel != "" else "Other"

# Fill the grid with one section's images.
func _show(title: String) -> void:
	current = title
	for b in buttons.get_children():  # the open section stands out
		b.modulate = Color("ffd34e") if b.get_meta("section") == title else Color.WHITE
	for c in grid.get_children():
		c.queue_free()
	for item in sections[title]:
		var tex: Texture2D = item[1]
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = maxf(CELL, tex.get_width())
		var pic := TextureRect.new()  # true size: no scaling at all
		pic.texture = tex
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.stretch_mode = TextureRect.STRETCH_KEEP
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(pic)
		var l := Label.new()
		l.text = "%s\n%dx%d" % [item[0], tex.get_width(), tex.get_height()]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.custom_minimum_size.x = maxf(CELL, tex.get_width())
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		cell.add_child(l)
		grid.add_child(cell)
