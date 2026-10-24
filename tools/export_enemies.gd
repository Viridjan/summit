extends SceneTree
const EnemyArt := preload("res://scripts/enemy_art.gd")
func _initialize() -> void:
	var img := EnemyArt.atlas()
	img.save_png("res://assets/enemies/enemies.png")
	var details := Image.create(128, 96, false, Image.FORMAT_RGBA8)
	for i in 3:
		var kind: String = ["enemy_mosstrot", "enemy_cragjaw", "enemy_murkspore"][i]
		details.blit_rect(img, Rect2i(0, EnemyArt.KINDS.find(kind)*32, 128, 32), Vector2i(0,i*32))
	details.save_png("res://assets/enemies/new-families.png")
	details.resize(768,576,Image.INTERPOLATE_NEAREST)
	details.save_png("/tmp/summit-new-enemies.png")
	img.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
	img.save_png("/tmp/summit-enemy-atlas.png")
	quit()
