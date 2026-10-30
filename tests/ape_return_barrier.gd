extends Node
var failures := 0
const FLAG := "a1_ape_arena:ape_144_120"
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	Game.main = self
	var story: Dictionary = Game.Adventure.load_world(Game.STORY_WORLD)
	Game.playtest_adventure(story,"j3_jungle_hills")
	await get_tree().process_frame
	var world = get_child(get_child_count()-1)
	world.set_physics_process(false)
	var barriers = world.ents.filter(func(e): return e.d.get("id","") == "early_jungle_barrier")
	check(barriers.size()==1,"Jungle Hills has a post-Ape return barrier")
	if barriers.is_empty(): Game.quit_game(failures);return
	var barrier=barriers[0]
	barrier.update(0)
	check(not barrier.collidable,"The early Jungle passage is open before the Ape fight")
	world.broken[FLAG]=true
	barrier.update(0)
	check(barrier.collidable,"The return passage closes after the Ape is beaten")
	check(world.collide_solid(Rect2i(368,96,8,16))!=null,"The barrier blocks the approach to early Jungle")
	check(world.collide_solid(Rect2i(392,112,8,8))==null,"The drop into Jungle Depths stays open")
	world.enter_room("a1_ape_arena",Vector2(220,120))
	for gate in world.ents.filter(func(e): return e.d.t == "boss_gate"): gate.update(0)
	check(world.collide_solid(Rect2i(240,104,8,16))==null,"Sand Cave exit stays open after the Ape")
	world.enter_room("j3_jungle_hills",Vector2(420,112))
	barrier=world.ents.filter(func(e): return e.d.get("id","")=="early_jungle_barrier")[0]
	check(barrier.collidable,"Barrier remains closed on room reload")
	print("APE RETURN BARRIER OK" if failures==0 else "APE RETURN BARRIER FAILED")
	Game.quit_game(failures)
