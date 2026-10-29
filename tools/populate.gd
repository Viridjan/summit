extends SceneTree
# Fill each region with monsters from the action library (scripts/monster_library.gd).
#
#   godot --headless --path . --script tools/populate.gd -- [--world res://worlds/story/] [--seed 1] [--dry] [--clear]
# --dry prints the plan without saving; --clear only removes the monsters it placed before.
#
# Regions are taken in world.json order; peaceful ones (or without a sign) get none and don't pass monsters on.
# A region's monsters are, of the whole population:
#   30% picked from the previous region's monsters, as they are,
#   20% picked from the previous region's monsters, upgraded one tier,
#   50% the region's own (natives of its zodiac sign).
# Picks are spread over the previous region's kinds in proportion (a kind that was 20% gives 20% of the picks);
# a share that isn't a whole number is rounded up or down at random, weighted by its fraction.
# A twice-upgraded monster (tier 2) stays in the region it appeared in: it's never picked for the next one.
# Every upgraded copy of one kind in a region is the same upgrade (one upgraded version per region).
# Monsters this tool placed carry "populated": true and are replaced on the next run; hand-placed enemies stay.

const Lib := preload("res://scripts/monster_library.gd")
const T := 8
const KEEP := 0.3
const UPGRADE := 0.2
const PER_ROOM_CELLS := 200  # one monster per this many open cells, at most MAX_PER_ROOM
const MAX_PER_ROOM := 3
const NATIVES := 3  # kinds of native monster per region

var rng := RandomNumberGenerator.new()
var only_rooms: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := "res://worlds/story/"
	var dry := "--dry" in args
	rng.seed = 1
	for i in args.size():
		if args[i] == "--world" and i + 1 < args.size():
			dir = args[i + 1].trim_suffix("/") + "/"
		elif args[i] == "--rooms" and i + 1 < args.size():
			only_rooms = Array(args[i + 1].split(",", false))
		elif args[i] == "--seed" and i + 1 < args.size():
			rng.seed = int(args[i + 1])
	var game = root.get_node("Game")
	var world: Dictionary = load("res://scripts/adventure.gd").load_world(dir + "world.json")  # loaded late: it needs the Game autoload
	var before := {}
	for name in world.rooms:
		before[name] = JSON.stringify(world.rooms[name].level.entities)
	var report := populate(world) if not "--clear" in args else ["cleared"]
	if "--clear" in args:
		for name in world.rooms:
			var lvl: Dictionary = world.rooms[name].level
			lvl.entities = lvl.entities.filter(func(e): return not e.get("populated", false))
	for line in report:
		print(line)
	if not dry:  # only the rooms whose objects changed (saving rewrites the key order)
		var saved := 0
		for name in world.rooms:
			if JSON.stringify(world.rooms[name].level.entities) != before[name]:
				game.save_level(world.rooms[name].level, dir, name)
				saved += 1
		print("saved %d rooms in %s" % [saved, dir])
	quit()

# Fills world.rooms[*].level.entities in place; returns report lines.
func populate(world: Dictionary) -> Array:
	var out: Array = []
	var prev: Array = []  # the previous fighting region's monsters
	for g in world.regions:
		for name in g.rooms:
			if not only_rooms.is_empty() and name not in only_rooms: continue
			var lvl: Dictionary = world.rooms[name].level
			lvl.entities = lvl.entities.filter(func(e): return not e.get("populated", false))
		if g.get("peaceful", false) or not Lib.SIGNS.has(g.get("sign", "")):
			out.append("%-16s peaceful" % g.name)
			continue
		var spots: Array = []
		for name in g.rooms:
			if not only_rooms.is_empty() and name not in only_rooms: continue
			for s in spots_in(world.rooms[name].level):
				spots.append([name, s])
		var pop := mix(prev, spots.size(), g.name, g.sign)
		shuffle(spots)
		for i in pop.size():
			place(world.rooms[spots[i][0]].level, spots[i][1], pop[i])
		var tiers := [0, 0, 0]
		for m in pop:
			tiers[mini(int(m.tier), 2)] += 1
		out.append("%-16s %-11s %2d monsters  tier0 %d  tier1 %d  tier2 %d" % [g.name, g.sign, pop.size(), tiers[0], tiers[1], tiers[2]])
		if not pop.is_empty():  # a region with no room for monsters passes the previous ones on
			prev = pop
	return out

# The population of n monsters for a region after prev (see the header).
func mix(prev: Array, n: int, region: String, sign: String) -> Array:
	var natives: Array = []
	var nr := RandomNumberGenerator.new()
	nr.seed = hash(region)
	for i in NATIVES * 4:  # a few tries for NATIVES different kinds
		var m := Lib.native(sign, nr)
		if not natives.any(func(o): return Lib.key(o) == Lib.key(m)):
			natives.append(m)
		if natives.size() == NATIVES:
			break
	var pool: Array = prev.filter(func(m): return int(m.tier) < 2)
	var pop: Array = []
	if not pool.is_empty():
		var kept := pick(pool, round_random(n * KEEP))
		var ups := pick(pool, round_random(n * UPGRADE))
		pop += kept.map(func(m): return m.duplicate(true))
		for m in ups:
			var ur := RandomNumberGenerator.new()
			ur.seed = hash([region, Lib.key(m), m.tier])  # one upgraded version per kind per region
			pop.append(Lib.upgrade(m, ur))
	while pop.size() < n:
		pop.append(natives[rng.randi() % natives.size()].duplicate(true))
	shuffle(pop)
	return pop.slice(0, n)

# k monsters from pool, spread over its kinds in proportion; fractions rounded at random by their weight.
func pick(pool: Array, k: int) -> Array:
	var kinds := {}
	for m in pool:
		kinds.get_or_add(Lib.key(m) + "#" + str(m.tier), []).append(m)
	var out: Array = []
	var rest := {}
	for key in kinds:
		var share: float = k * float(kinds[key].size()) / pool.size()
		for i in floori(share):
			out.append(kinds[key][0])
		rest[key] = share - floori(share)
	while out.size() < k and not rest.is_empty():  # the leftover units go to kinds at random, weighted by fraction
		var total := 0.0
		for key in rest:
			total += rest[key]
		var r := rng.randf() * total
		for key in rest.keys():
			r -= rest[key]
			if r <= 0 or key == rest.keys()[-1]:
				out.append(kinds[key][0])
				rest.erase(key)
				break
	return out

func shuffle(a: Array) -> void:  # with the tool's seed (Array.shuffle uses the global one)
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func round_random(x: float) -> int:
	return floori(x) + (1 if rng.randf() < x - floori(x) else 0)

func solid(lvl: Dictionary, x: int, y: int) -> bool:
	return x < 0 or y < 0 or x >= lvl.w or y >= lvl.h or lvl.tiles[y][x] == "1"

# Floor cells (the open cell just above solid ground) where a monster can stand: a flat run of 3, two open rows
# above, away from the edges (doorways) and 3 tiles from liquids, spikes, spawn points and other enemies; spaced 8 apart.
func spots_in(lvl: Dictionary) -> Array:
	if lvl.get("arena", false):
		return []  # a boss arena waiting for its boss
	for e in lvl.entities:
		if e.t.begins_with("boss") or e.t.begins_with("ape") or e.t in ["auto_walk", "building", "house_door"]:
			return []  # boss arenas and towns: none
	var avoid: Array = []
	for e in lvl.entities:
		if e.t in ["water", "acid", "spawn"] or e.t.begins_with("spikes") or e.t.begins_with("enemy"):
			avoid.append(Rect2i(int(e.x), int(e.y), int(e.get("w", T)), int(e.get("h", T))).grow(3 * T))
	var open := 0
	for row in lvl.tiles:
		open += row.count("0")
	var requested := int(lvl.get("enemy_count", -1))
	var want := maxi(0, requested) if requested >= 0 else mini(MAX_PER_ROOM, open / PER_ROOM_CELLS)
	var cand: Array = []
	for y in range(3, lvl.h - 1):
		for x in range(5, lvl.w - 6):
			var ok := true
			for dx in 3:
				if solid(lvl, x + dx, y) or solid(lvl, x + dx, y - 1) or solid(lvl, x + dx, y - 2) or not solid(lvl, x + dx, y + 1):
					ok = false
					break
			var cell := Rect2i(x * T, (y - 1) * T, 3 * T, 2 * T)
			if ok and not avoid.any(func(a): return a.intersects(cell)):
				cand.append(Vector2i(x + 1, y))
	shuffle(cand)
	var out: Array = []
	for c in cand:
		if out.size() >= want:
			break
		if out.all(func(o): return absi(o.x - c.x) >= 8 or absi(o.y - c.y) >= 4):
			out.append(c)
	return out

# Put monster m standing on floor cell c (flyers float two tiles higher). ActionMonster grows giant / upgraded
# ones upward and to both sides from this spot.
func place(lvl: Dictionary, c: Vector2i, m: Dictionary) -> void:
	var e: Dictionary = m.duplicate(true)  # placed at the base 10 px size: bigger ones grow up and out from it
	e.x = c.x * T - 5 + T / 2
	e.y = (c.y + 1) * T - 10 - (2 * T if m.move == "hover" else 0)
	e.facing = -1 if rng.randf() < 0.5 else 1
	e.populated = true
	lvl.entities.append(e)
