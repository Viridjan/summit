extends Node2D
# Retained draw commands, partitioned into non-overlapping 32x32-cell chunks.

const Art := preload("res://scripts/art.gd")
const CHUNK_SIZE := 32

class Chunk extends Node2D:
	var tiles: Array
	var level_size: Vector2i
	var cells: Rect2i
	var draw_count := 0

	func _draw() -> void:
		draw_count += 1
		Art.draw_tile_range(self, tiles, level_size.x, level_size.y,
			cells.position.x, cells.position.y, cells.end.x, cells.end.y)

var tiles: Array = []
var level_size := Vector2i.ZERO
var chunk_grid := Vector2i.ZERO
var chunks: Array[Chunk] = []

func setup(level_tiles: Array, w: int, h: int) -> void:
	for chunk in chunks:
		remove_child(chunk)
		chunk.free()
	chunks.clear()
	tiles = level_tiles
	level_size = Vector2i(w, h)
	chunk_grid = Vector2i(ceili(w / float(CHUNK_SIZE)), ceili(h / float(CHUNK_SIZE)))
	for y in chunk_grid.y:
		for x in chunk_grid.x:
			var chunk := Chunk.new()
			chunk.tiles = tiles
			chunk.level_size = level_size
			var start := Vector2i(x, y) * CHUNK_SIZE
			chunk.cells = Rect2i(start, (start + Vector2i.ONE * CHUNK_SIZE).min(level_size) - start)
			chunks.append(chunk)
			add_child(chunk)

# Only this cell and its cardinal neighbours can change appearance. Decorations
# belong to their source cell even when drawn one tile above a chunk boundary.
# Return unique chunk coordinates for deterministic invalidation checks.
func mark_cell_dirty(c: Vector2i) -> Array[Vector2i]:
	var marked: Array[Vector2i] = []
	if not Rect2i(Vector2i.ZERO, level_size).has_point(c):
		return marked
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell: Vector2i = c + offset
		if not Rect2i(Vector2i.ZERO, level_size).has_point(cell):
			continue
		var index := Vector2i(cell.x / CHUNK_SIZE, cell.y / CHUNK_SIZE)
		if index not in marked:
			marked.append(index)
			chunks[index.y * chunk_grid.x + index.x].queue_redraw()
	return marked
