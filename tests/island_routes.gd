extends Node
# Exercise the real player-contact and door-transfer path, including the explicit input gate.
var failures := 0

class RouteBot extends "res://scripts/player.gd":
	var horizontal := 0
	var vertical := 0
	var jump_now := false
	var jump_hold := 0
	func _read_input(dt: float) -> void:
		in_x = horizontal
		in_y = vertical
		aim_raw = Vector2(in_x, in_y).normalized()
		jump_buf = INPUT_BUFFER if jump_now else jump_buf - dt
		dash_buf -= dt
		attack_buf -= dt
		jump_hold = 12 if jump_now else maxi(0, jump_hold - 1)
		jump_check = jump_hold > 0
		jump_now = false
		grab_check = false
		interact = false

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	Game.main = self
	Game.settings.invincible = true
	var story: Dictionary = Game.Adventure.load_world("res://worlds/story/world.json")
	var shores := ["i01_west_shore", "i02_north_shore", "i03_south_shore", "i08_east_shore"]
	var opposite := {"i01_west_shore":"i08_east_shore", "i08_east_shore":"i01_west_shore", "i02_north_shore":"i03_south_shore", "i03_south_shore":"i02_north_shore"}
	var world
	for source in shores:
		for target in shores:
			if source == target or target == opposite[source]: continue
			Game.playtest_adventure(story, source)
			await get_tree().process_frame
			world = get_child(get_child_count() - 1)
			world.set_physics_process(false)
			_use_panel(world, target)
	# The post-Guardian West Shore variant must retain the travel network.
	Game.playtest_adventure(story, "i02_north_shore")
	await get_tree().process_frame
	world = get_child(get_child_count() - 1)
	world.set_physics_process(false)
	world.broken["i16_guardian_chamber:guardian_112_16"] = true
	_use_panel(world, "i01_west_shore")
	check(world.data.w == 120 and world.ents.any(func(e): return e.d.get("id", "") == "home"), "Post-Guardian West Shore retains its long beach and reward door")
	# Step away from the arrival panel before deliberately returning through it.
	world.player.pos.x += 32
	world.player.interact = false
	world.player_touch(world.player)
	world.after_player_move()
	_use_panel(world, "i02_north_shore")
	# Walk every new stretch with real movement, including the shallow pools.
	for room in shores:
		Game.playtest_adventure(story, room)
		await get_tree().process_frame
		world = get_child(get_child_count() - 1)
		world.set_physics_process(false)
		world.player = RouteBot.new(world, Vector2(320, (world.gh - 3) * 8))
		Game.adv.blocks = 100
		Game.adv.stamina = 5000.0
		for tick in 1800:
			var bot = world.player
			bot.horizontal = 1
			if tick % 15 == 0 and (bot.on_ground or bot.state == bot.ST_SWIM): bot.jump_now = true
			world._physics_process(1.0 / 60.0)
			if bot.pos.x >= 118 * 8 or world.room != room: break
		check(world.room == room and world.player.pos.x >= 118 * 8 and not world.player.dead, "The extended " + room + " beach is traversable with jump/swim only")
	# Traverse the actual tall i09 tunnel with production movement and jump only.
	Game.playtest_adventure(story, "i04_foothills")
	await get_tree().process_frame
	world = get_child(get_child_count() - 1)
	world.set_physics_process(false)
	world.player = RouteBot.new(world, Vector2(64, 104))
	Game.adv.blocks = 100
	Game.adv.stamina = 5000.0
	var entered_tunnel := false
	for tick in 2400:
		var bot = world.player
		bot.vertical = 1
		bot.horizontal = 0
		if bot.on_ground and tick % 15 == 0: bot.jump_now = true
		if world.room == "i09_sea_cave":
			entered_tunnel = true
			if bot.pos.y >= 343: bot.horizontal = -1
		world._physics_process(1.0 / 60.0)
		if world.room == "i10_junction": break
	check(world.room == "i10_junction" and entered_tunnel, "Player descends from Foothills through i09 into the shifted maze (room=%s, pos=%s)" % [world.room, world.player.pos])
	for tick in 3600:
		var bot = world.player
		bot.vertical = 0
		bot.horizontal = 1 if world.room == "i10_junction" else 1 if bot.pos.x < 62 else -1 if bot.pos.x > 66 else 0
		if bot.on_ground and tick % 15 == 0: bot.jump_now = true
		world._physics_process(1.0 / 60.0)
		if world.room == "i04_foothills": break
	check(world.room == "i04_foothills", "Player climbs i09 back to Foothills with jump only (room=%s, pos=%s)" % [world.room, world.player.pos])
	print("ISLAND ROUTES OK" if failures == 0 else "ISLAND ROUTES FAILED")
	Game.quit_game(failures)

func _use_panel(world, target: String) -> void:
	var sign
	for entity in world.ents:
		if entity.d.get("skin", "") == "signpost" and str(entity.d.get("to", "")).get_slice(":", 0) == target:
			sign = entity
	check(sign != null, "Shore has a separate direction panel for " + target)
	if sign == null: return
	world.player.pos = Vector2(sign.rect.get_center().x, sign.rect.end.y)
	world.player.on_ground = true
	world.player.interact = false
	world.player_touch(world.player)
	world.after_player_move()
	check(world.room != target, "Approaching a panel does not travel automatically")
	world.player.interact = true
	world.player_touch(world.player)
	world.after_player_move()
	check(world.room == target, "Interact follows the selected shore panel to " + target)
	check(world.collide_solid(world.player.hitbox()) == null, "Shore arrival leaves the player clear of terrain")
	check(world.collide_solid(world.player.hitbox().grow_individual(0, 0, 0, 1)) != null, "Shore arrival has a safe standing surface")
