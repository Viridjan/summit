extends Node
func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	var story: Dictionary = Game.Adventure.load_world(Game.STORY_WORLD)
	var unsafe: Array = []
	var checked := 0
	for room in story.rooms:
		Game.playtest_adventure(story,room)
		await get_tree().process_frame
		var world = get_child(get_child_count()-1)
		world.set_physics_process(false)
		for entity in world.data.entities:
			if entity.t not in ["spawn", "respawn"]: continue
			checked += 1
			if not world.safe_spawn(Vector2(float(entity.x)+4,float(entity.y)+8)):
				unsafe.append([room,entity.x,entity.y,entity.get("entrance",false)])
	print("RESPAWN AUDIT: %d checked; unsafe: %s" % [checked,unsafe])
	Game.quit_game(0)
