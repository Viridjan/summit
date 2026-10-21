extends SceneTree
const EnemyArt := preload("res://scripts/enemy_art.gd")
func _initialize() -> void:
	var img := EnemyArt.atlas()
	img.save_png("res://assets/enemies/enemies.png")
	img.resize(512, 640, Image.INTERPOLATE_NEAREST)
	img.save_png("/tmp/summit-enemy-atlas.png")
	quit()
