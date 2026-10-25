# Story generation source. Room helpers use tile coordinates and convert placed objects to pixels. Executing this script writes room JSON/world layout and may replace hand-edited generated files; do not run it merely to read the code.
# Reading help: docs/CODE_GUIDE.md.

# Generator for worlds/story (chapter 1). Rooms are edited in-game too, so it only rewrites the rooms
# you name (their in-game edits are lost); "all" rewrites every room and world.json.
#   python3 -I tools/story/gen_first_stretch.py worlds/story a1_ape_arena [more rooms...]
import json, os, sys
OUT = sys.argv[1]
ONLY = set(sys.argv[2:])
if not ONLY:
    sys.exit("name the rooms to rewrite (or 'all'); in-game edits to them are lost")
T = 8

class Room:
    # Build the in-memory room/grid representation used by this tool from its input data.
    def __init__(s, name, title, w, h, env, fill="0"):
        s.name, s.title, s.w, s.h, s.env = name, title, w, h, env
        s.g = [[fill] * w for _ in range(h)]
        s.ents = []
    # Fill an inclusive tile rectangle in the generated room.
    def rect(s, x0, y0, x1, y1, c):  # inclusive
        for y in range(max(0, y0), min(s.h - 1, y1) + 1):
            for x in range(max(0, x0), min(s.w - 1, x1) + 1):
                s.g[y][x] = c
    # Fill a generated tile rectangle with solid terrain.
    def solid(s, *a): s.rect(*a, "1")
    # Clear a generated tile rectangle to walkable empty space.
    def open(s, *a): s.rect(*a, "0")
    # Append an object, converting its tile position into the pixel coordinates required by level JSON.
    def ent(s, t, x, y, **kw): s.ents.append({"t": t, "x": x * T, "y": y * T, **kw})
    # Place backdrop scenery ahead of its doorway in drawing order.
    def building(s, x, y, w, h, style):  # scenery, walked through; first in the list so doors draw over it
        s.ents.insert(0, {"t": "building", "x": x * T, "y": y * T, "w": w * T, "h": h * T, "style": style})
    # Place a row of upward-facing spikes across the requested tile interval.
    def spikes_up(s, x0, x1, y):
        for x in range(x0, x1 + 1): s.ent("spikes_up", x, y)
    # Place a rectangular water region, converting its tile dimensions into pixels.
    def water(s, x0, y0, x1, y1, **kw):
        s.ents.append({"t": "water", "x": x0 * T, "y": y0 * T, "w": (x1 - x0 + 1) * T, "h": (y1 - y0 + 1) * T, **kw})
    # Write the generated room dictionary as a project JSON file.
    def save(s):
        d = {"name": s.title, "w": s.w, "h": s.h, "environment": s.env,
             "tiles": ["".join(r) for r in s.g], "entities": s.ents}
        json.dump(d, open(os.path.join(OUT, s.name + ".json"), "w"), indent="\t")

G = 19  # ground top row everywhere (rows G..h-1 solid)

# 1. Meadow: learn to jump. Nothing here hurts: a missed jump only drops you onto grass or into a shallow dip
#    you can hop out of. Harm starts once you fall down the hole in The Big Jump.
m = Room("m1_meadow", "Meadow", 80, 23, "sky")
m.solid(0, G, 79, 22); m.solid(0, 0, 0, 22)
m.solid(14, 18, 16, 18)                      # low bump
m.solid(20, 16, 22, 16)                      # floating ledge over the path
m.solid(26, 17, 27, 18)                      # 2-high block
m.open(32, G, 36, 20)                        # shallow dip, 2 deep: jump it, or climb back out
m.solid(34, 19, 34, 20)                      # stepping stone in the dip
m.solid(41, 17, 43, 18); m.solid(57, 17, 59, 18)  # an arch: blocks at the ends, floating ledges between
for x, y in ((45, 15), (49, 13), (53, 15)):
    m.solid(x, y, x + 2, y)
m.ent("strawberry", 50, 11)                  # on top of the arch
m.open(61, G, 64, 20)                        # second dip
m.solid(66, 17, 69, 18)
m.solid(72, 16, 73, 18)                      # 3-high block: a full jump
m.ent("spawn", 3, 18)
m.ent("note", 6, 18, text="Chapter 1 (work in progress): head right")

# 2. The big jump: two stepped peaks (tip up), a gap only a wavedash crosses; falling in is the way on
j = Room("m2_big_jump", "The Big Jump", 40, 23, "sky")
j.solid(0, G, 39, 22); j.solid(39, 0, 39, 22)
for i in range(4):                           # left peak: 2-wide steps, cols 5..12, 1..4 high
    j.solid(5 + 2 * i, G - 1 - i, 6 + 2 * i, G - 1)
for i in range(4):                           # right peak: cols 27..34, 4..1 high
    j.solid(27 + 2 * i, G - 4 + i, 28 + 2 * i, G - 1)
j.open(13, G, 26, 22)                        # the gap drops into the lake cave
j.ent("spawn", 2, 18)
j.ent("note", 11, 14, text="The big jump: needs a wavedash (dash comes from a later level). Drop in to go on.")
j.ent("strawberry", 36, 16)                  # far side reward, for later

# The hole: the gap in The Big Jump drops a whole screen down this shaft before reaching the Lake Cave.
hole = Room("m3_the_hole", "The Hole", 40, 23, "cavern_deep", fill="1")
hole.open(13, 0, 26, 22)
hole.ent("note", 20, 3, text="Down you go. From here on, things can hurt")

# 3. Lake cave: darker, a lake, dead-end tunnels, a roar from the left. 5 screens wide, 2 tall.
c = Room("c1_lake_cave", "Lake Cave", 200, 46, "cavern_deep", fill="1")
# upper cave (row band 6..18, floor row G)
c.open(41, 6, 118, G - 1)                    # first chamber, under the big jump
c.open(53, 0, 66, 5)                         # shaft from the big jump
c.solid(41, 6, 48, 14)                       # rock; the roar tunnel runs under it
c.open(1, 15, 48, G - 1)                     # roar tunnel to the far left (dead end)
c.open(12, 8, 14, 14)                        # dead-end side tunnel up
c.solid(74, 6, 84, 8); c.solid(104, 6, 118, 9)  # uneven ceiling
c.open(100, 2, 102, 8)                       # dead-end tunnel up
c.solid(106, 13, 112, 13)                    # floating ledge
c.open(99, G, 101, 20); c.spikes_up(99, 101, 20)  # spike pit past the lake (3 tiles of run-up after it)
c.spikes_up(104, 110, 18); c.solid(107, 17, 107, 18)  # spiky floor with a stepping stone in the middle
c.open(119, 9, 198, G - 1)                   # right chambers
c.solid(130, 9, 138, 11); c.solid(160, 9, 175, 12); c.solid(186, 9, 198, 13)  # ceiling teeth
c.open(150, 3, 152, 8)                       # dead-end tunnel up
c.solid(146, 16, 148, 18); c.solid(168, 17, 171, 18)  # rocks to hop over
c.open(126, G, 128, 20); c.spikes_up(126, 128, 20)    # Cave Teeth: spike pits between the teeth
c.open(136, G, 138, 20); c.spikes_up(136, 138, 20)  # room to land before the tall rock
c.solid(154, 16, 155, 16)                             # a ledge to hop from
c.open(174, G, 176, 20); c.spikes_up(174, 176, 20)    # Cove Tunnel: a pit between the rocks and the ledge
c.open(189, G, 191, 20); c.spikes_up(189, 191, 20)    # and one under the low ceiling
c.solid(178, 13, 182, 13)                    # ledge
c.open(70, G, 95, 20); c.water(70, G, 95, 20)  # the lake, in a dip
c.open(199, 16, 199, 18)                     # right edge: rows 16..18 lead into Cove Town
# lower cave (one screen, cols 80..119 rows 23..45): a hole in the lake floor drops into a flooded deep lake
c.open(88, 21, 91, 25)
c.open(81, 26, 118, 40)
c.solid(98, 26, 108, 29)                     # ceiling tooth
# One body of water, surface at the lake (row 19): the hole, all of Deep Lake and the shaft back up are under it.
c.water(88, 21, 91, 22, top=False); c.water(114, G, 118, 22)  # hole and shaft, Lake Cave side
c.water(88, 23, 91, 25, top=False); c.water(114, 23, 118, 25, top=False)  # the same, Deep Lake side
c.water(81, 26, 97, 29, top=False); c.water(109, 26, 118, 29, top=False)  # either side of the tooth
c.water(81, 30, 118, 40, top=False)
c.open(114, G, 118, 25)                      # way back up: a shaft of jump-through platforms
for y in (37, 34, 31, 28, 25, 22, 19):       # the top one (row 19) carries the cave floor over the shaft
    c.ents.append({"t": "jumpthru", "x": 114 * T, "y": y * T, "w": 5 * T, "h": 8})
c.ent("spawn", 60, 18)
c.ent("spawn", 196, 18)
c.ent("note", 3, 18, text="A roar from the left", sound="cave_roar")
c.ent("note", 101, 5, text="Dead end")
c.ent("note", 151, 6, text="Dead end")
c.ent("strawberry", 82, 39)

# 4. Cove town: two NPCs, the second energy block, a quest
t = Room("t1_cove_town", "Cove Town", 40, 23, "sea")
t.solid(0, G, 39, 22); t.solid(0, 0, 0, 15); t.solid(39, 0, 39, 14)  # right edge rows 15..18 lead into the jungle
t.ents.append({"t": "jumpthru", "x": 8 * T, "y": 15 * T, "w": 6 * T, "h": 8})   # roof
t.ents.append({"t": "jumpthru", "x": 18 * T, "y": 15 * T, "w": 6 * T, "h": 8})  # second roof
t.building(8, 14, 6, 5, "house"); t.building(18, 14, 6, 5, "house")  # backdrops, not walls
t.open(30, G, 37, 20); t.water(30, G, 37, 20)    # the sea, ending a tile short of the jungle exit (flat entrance)
t.ent("spawn", 2, 18)
t.ent("energy_orb", 5, 17)
t.ent("energy_block", 20, 13)
t.ents.append({"t": "house_door", "x": 10 * T, "y": 16 * T, "w": 2 * T, "h": 3 * T, "id": "h1", "to": "h1_villager_house:out"})
t.ents.append({"t": "house_door", "x": 20 * T, "y": 16 * T, "w": 2 * T, "h": 3 * T, "id": "h2", "to": "h2_quest_house:out"})

# Cove Town's houses, inside (reached through their house doors; press interact at a door)
# Construct a small indoor room and its linked town entrance.
def house(name, title, town_door, note):
    h = Room(name, title, 30, 14, "building", fill="1")
    h.open(1, 1, 28, 11)                     # floor rows 12..13
    h.ents.append({"t": "house_door", "x": 2 * T, "y": 9 * T, "w": 2 * T, "h": 3 * T, "id": "out", "to": "t1_cove_town:" + town_door})
    h.ents.append({"t": "jumpthru", "x": 9 * T, "y": 8 * T, "w": 4 * T, "h": 8})   # shelves
    h.ents.append({"t": "jumpthru", "x": 20 * T, "y": 7 * T, "w": 5 * T, "h": 8})
    h.ent("note", 16, 11, text=note)
    return h
h1 = house("h1_villager_house", "Villager's House", "h1", "Villager (NPC, not built yet)")
h2 = house("h2_quest_house", "Quest Giver's House", "h2", "Quest giver (NPC, not built yet): the quest rewards a skill point")

# 5. Jungle (section 1.5): forest theme, a hollow trunk, leaf platforms, calm Mosstrots; the player drops down again
# Place a leaf-shaped one-way platform with tile-based width.
def leaf(r, x, y, w): r.ents.append({"t": "leaf", "x": x * T, "y": y * T, "w": w * T, "h": 8})
# Place a right-facing ground walker at the requested tile position.
def mosstrot(r, x, y): r.ents.append({"t": "enemy_mosstrot", "x": x * T, "y": y * T, "facing": 1})
j1 = Room("j1_jungle_edge", "Jungle Edge", 40, 23, "forest")
j1.solid(0, G, 39, 22); j1.solid(0, 0, 39, 1); j1.solid(0, 0, 0, 14); j1.solid(39, 0, 39, 22)
j1.solid(14, 4, 16, 15)                      # big trunk, hollow at the base (rows 16..18)
leaf(j1, 9, 16, 4); leaf(j1, 4, 13, 4); leaf(j1, 9, 10, 4); leaf(j1, 4, 7, 4)  # zigzag up the trunk's left side
j1.ent("strawberry", 5, 4)
mosstrot(j1, 26, 18)
j1.open(31, G, 38, 22)                       # the ground ends: drop into the falls below
j1.open(20, G, 22, 20); j1.spikes_up(20, 22, 20)  # thorn pit, 3 tiles past the hollow trunk

j2 = Room("j2_jungle_falls", "Jungle Falls", 80, 23, "forest", fill="1")
j2.open(1, 3, 78, G - 1); j2.open(31, 0, 38, 2)   # the drop from Jungle Edge
j2.solid(5, 13, 22, 18); j2.open(5, 16, 22, 18)   # hill with a tunnel through it (dead end, a star)
j2.ent("strawberry", 6, 17)
mosstrot(j2, 14, 12); mosstrot(j2, 28, 18)
j2.open(40, G, 60, 20); j2.water(40, G, 60, 20)   # the lake
j2.open(33, G, 35, 20); j2.spikes_up(33, 35, 20)  # thorn pit before the lake
leaf(j2, 41, 17, 2); leaf(j2, 49, 16, 3)          # leaf hops across the lake (or swim)
j2.ents.append({"t": "waterfall", "x": 44 * T, "y": 3 * T, "w": 4 * T, "h": 16 * T})
leaf(j2, 56, 16, 4); leaf(j2, 51, 13, 4); leaf(j2, 56, 10, 4)  # up from the lake's right shore
j2.ent("strawberry", 58, 7)
j2.solid(64, 17, 68, 18); j2.solid(69, 15, 78, 18)  # hills up to the exit
j2.open(79, 11, 79, 14)                      # right edge rows 11..14 lead on

j3 = Room("j3_jungle_hills", "Jungle Hills", 80, 23, "forest", fill="1")
for x0, x1, top in ((1, 15, 15), (16, 22, 17), (23, 57, 19), (58, 64, 17), (65, 78, 19)):
    j3.open(x0, 2, x1, top - 1)              # the ground's top row per stretch
j3.open(0, 11, 0, 14)
j3.solid(32, 6, 46, 18); j3.open(32, 16, 46, 18)  # hill with a tunnel through it
j3.solid(52, 2, 54, 16)                      # big trunk, hollow at the base
leaf(j3, 56, 16, 3); leaf(j3, 59, 13, 4); leaf(j3, 56, 10, 3)  # up the trunk's right side
j3.ent("strawberry", 57, 8)
j3.open(26, 19, 28, 20); j3.spikes_up(26, 28, 20)  # thorn pit on the long flat stretch
j3.open(48, G, 51, 22)                       # the way down to the left branch (Jungle Depths), before the arena
mosstrot(j3, 39, 5)  # on the tunnel hill's top, off the walking path
j3.open(79, 15, 79, 18)                      # right edge at floor level: into the Ape's arena, and back out of it

# 6. The Ape's arena (section 1.6, the boss is not built yet) and the fork (1.7)
# Place a doorway rectangle with its ID and destination link.
def door(r, x, y, did, to): r.ents.append({"t": "door", "x": x * T, "y": y * T, "w": 2 * T, "h": 3 * T, "id": did, "to": to})
AW = 31  # arena width: 56, then 39, then 31 (2026-10-25); the right branch moved left with it
a1 = Room("a1_ape_arena", "Ape Arena", AW, 23, "forest", fill="1")
a1.open(1, 2, AW - 2, G - 1); a1.open(0, 15, 0, 18); a1.open(AW - 1, 12, AW - 1, 15)  # left opening at floor level
# As edited in the World Editor (2026-10-25): an empty arena, no ledges, stairs, platforms or starting spikes, no
# walk-in. Both doorways drop into it (tools/check_entrances.py DROP_IN): the way back left is out of jump reach.
a1.ents.append({"t": "boss_gate", "x": 0, "y": 15 * T, "w": T, "h": 4 * T, "closes_behind": True})
for y in range(5, 9): a1.ent("spikes_right", 1, y)    # wall spikes, out of the Ape's range: they stay all fight
for y in range(4, 9): a1.ent("spikes_left", AW - 2, y)
# every leap drops a log that leaves a 1-tile spike where it breaks; landing on spikes hurts the Ape and breaks them
a1.ents.append({"t": "boss_ape", "x": 18 * T, "y": 15 * T, "range": [1 * T, (AW - 1) * T], "orb": [(AW - 8) * T, 16 * T]})
a1.ents.append({"t": "boss_gate", "x": (AW - 1) * T, "y": 12 * T, "w": T, "h": 4 * T})   # right exit
# After the Ape (world.json "variants"): the same terrain and spawns, with no boss or gates, the wall spikes and the orb.
APE_ID = "a1_ape_arena:ape_%d_%d" % (18 * T, 15 * T)
# Jungle Hills after the fight: the roots over the hole down to Jungle Depths give way, and leaving the arena on the
# left, the Ape follows you (right to left) until the big trunk's low hollow stops it, just short of the hole.
j3.ents.append({"t": "boss_gate", "x": 48 * T, "y": G * T, "w": 4 * T, "h": T, "until": APE_ID})
j3.ents.append({"t": "ape_chase", "x": 77 * T, "y": G * T - 32, "dir": -1, "trigger": 70 * T, "end": 58 * T, "after": APE_ID})
a1b = Room("a1_ape_arena_after", "Ape Arena", AW, 23, "forest", fill="1")
a1b.g = [row[:] for row in a1.g]  # ponytail: ignored at runtime (the base room's tiles are used), kept valid
for y in range(5, 9): a1b.ent("spikes_right", 1, y)
for y in range(4, 9): a1b.ent("spikes_left", AW - 2, y)
a1b.ent("energy_orb", AW - 8, 16)

# Right branch: a long sand cave climbing at about 14 degrees (30 rows over 120 columns), then the shore and the
# lighthouse. Jump-only challenges (no abilities yet), with the beaten Ape chasing the player up it.
# The climb is 15 steps 2 tiles high (each costs one jump: 5 energy), with flats between them for the challenges.
SW = 120
s1 = Room("s1_sand_cave", "Sand Cave", SW, 46, "sand", fill="1")
STEPS = [(k * SW + 8) // 16 for k in range(1, 16)]  # first column of each step: 8, 15, 23 ... 113
top = [39 - 2 * sum(1 for b in STEPS if b <= x) for x in range(SW)]  # first solid row under the corridor
for x in range(SW):
    s1.open(x, top[x] - 7, x, top[x] - 1)
# Carve a pit and place spikes along its floor.
def spike_pit(a, b):                         # 3 deep, spikes on its floor
    s1.open(a, top[a], b, top[a] + 2)
    s1.spikes_up(a, b, top[a] + 2)
# Place temporary support across a pit, optionally including spikes below.
def crumble_bridge(a, b, spikes=False):      # breakable sand over a 2-deep pit
    s1.open(a, top[a], b, top[a] + 1)
    if spikes: s1.spikes_up(a, b, top[a] + 1)
    s1.ents.append({"t": "crumble", "x": a * T, "y": top[a] * T, "w": (b - a + 1) * T, "h": 8})
# every pit and bridge starts 3 tiles after a step, so the jump up a step never carries into it
spike_pit(18, 20)
crumble_bridge(26, 28)       # 3 wide after 3 tiles of run-up: the Ape leaps clear of it
spike_pit(41, 43)
spike_pit(56, 58)
s1.ents.append({"t": "breakwall", "x": 55 * T, "y": (top[55] - 7) * T, "w": 5 * T, "h": 3 * T})  # low ceiling: only a short hop clears the pit; the Ape smashes it
crumble_bridge(79, 81, spikes=True)
spike_pit(93, 95)
spike_pit(108, 110)
for hx in (32, 47, 62, 70, 85):  # hanging rock: the player runs under it, the chasing Ape smashes it and gets hurt
    s1.ents.append({"t": "breakwall", "x": hx * T, "y": (top[hx] - 7) * T, "w": 2 * T, "h": 3 * T})
# The Ape stops at "end": the ceiling just ahead of it caves in ("seal"), for good. Overtaking the player kills.
s1.ents.append({"t": "ape_chase", "x": 0, "y": top[0] * T - 32, "trigger": 12 * T, "end": 99 * T,
                "seal": [102 * T, (top[102] - 7) * T, 2 * T, 7 * T]})
s1.ent("note", 116, top[116] - 1, text="Reward: the sword (not built yet; needs 2 energy blocks to use)")

s2 = Room("s2_shore", "Shore", 80, 23, "sea")
s2.solid(0, 9, 14, 22); s2.solid(0, 0, 0, 0)  # the cliff we come out on, the mountain's foot
s2.solid(8, 2, 12, 2)                        # mountain ledge, out of reach for now
s2.ent("strawberry", 10, 1)
s2.solid(15, G, 79, 22); s2.solid(79, 0, 79, 22)
s2.open(56, G, 78, 21); s2.water(56, G, 78, 21)  # the sea
s2.solid(20, 17, 21, 18); s2.solid(36, 17, 37, 18)  # rocks on the beach
s2.open(27, G, 29, 20); s2.spikes_up(27, 29, 20)    # urchins in a tide pool
# stepping stones and notes removed in the World Editor (2026-10-25). The raft (a house door: interact to sail)
# to the eastern island (tools/story/gen_island.py); the lighthouse quest gate isn't built yet.
s2.ents.append({"t": "house_door", "x": 53 * T, "y": 16 * T, "w": 2 * T, "h": 3 * T, "id": "raft", "to": "i01_west_shore:raft"})
s2.building(44, 0, 9, 19, "tower")  # the lighthouse: a backdrop with its door at the foot
s2.ents.append({"t": "house_door", "x": 44 * T, "y": 16 * T, "w": 2 * T, "h": 3 * T, "id": "lh", "to": "lh1_lighthouse_stairs:bottom"})

s3 = Room("s3_lighthouse_top", "Lighthouse Top", 40, 23, "sky")
s3.building(4, 13, 9, 10, "tower")           # the tower's top, continued from the shore
s3.building(5, 5, 5, 6, "tower")             # the lantern room around the door
s3.solid(0, 11, 39, 12)                      # the gallery: the silent village
s3.ents.append({"t": "house_door", "x": 7 * T, "y": 8 * T, "w": 2 * T, "h": 3 * T, "id": "top", "to": "lh1_lighthouse_stairs:top"})
s3.solid(24, 7, 26, 10)                      # the flame's pedestal
s3.ent("note", 25, 6, text="Magic flame, aimed one way by mirrors (not built yet)")
for i, x in enumerate((15, 19, 29, 33)):
    s3.ent("note", x, 10, text='Silent villager (not built): "..."')
s3.ent("note", 37, 10, text='Silent villager with a quest (not built): "..." Speak to them before the raft works')

# Inside the lighthouse: two screens of stairs, platforms zigzagging up 3 rows apart (jump only)
lh = Room("lh1_lighthouse_stairs", "Lighthouse Stairs", 20, 46, "temple", fill="1")
lh.open(1, 1, 18, 43)                        # floor rows 44..45
lh.ents.append({"t": "house_door", "x": 2 * T, "y": 41 * T, "w": 2 * T, "h": 3 * T, "id": "bottom", "to": "s2_shore:lh"})
for i, y in enumerate(range(41, 4, -3)):
    lh.ents.append({"t": "jumpthru", "x": (11 if i % 2 == 0 else 1) * T, "y": y * T, "w": 8 * T, "h": 8})
lh.ents.append({"t": "house_door", "x": 15 * T, "y": 2 * T, "w": 2 * T, "h": 3 * T, "id": "top", "to": "s3_lighthouse_top:top"})
lh.ent("note", 6, 43, text="Up the stairs to the lamp")

# Left branch: back through the jungle, a net trap, the treetop village
l1 = Room("l1_jungle_depths", "Jungle Depths", 80, 23, "forest", fill="1")
l1.open(1, 3, 78, G - 1); l1.open(12, 0, 15, 2); l1.open(0, 15, 0, 18)
l1.solid(30, 14, 40, 18); l1.open(30, 17, 40, 18)  # hill with a low tunnel
l1.open(60, G, 70, 20); l1.water(60, G, 70, 20)
mosstrot(l1, 22, 18); mosstrot(l1, 52, 18)
for a in (5, 46):                            # thorn pits: one on the way out (left), one off it
    l1.open(a, G, a + 2, 20); l1.spikes_up(a, a + 2, 20)
leaf(l1, 62, 16, 3)                          # a leaf hop over the pool
l1.ent("note", 8, 18, text="The Ape screams behind you; cross the jungle again", sound="ape_scream")

l2 = Room("l2_net_trap", "Net Trap", 80, 23, "forest", fill="1")
l2.open(1, 3, 78, G - 1); l2.open(79, 15, 79, 18)
leaf(l2, 50, 15, 4); leaf(l2, 44, 12, 4)
mosstrot(l2, 60, 18)
for a in (66, 34):                           # thorn pits on the way to the trap
    l2.open(a, G, a + 2, 20); l2.spikes_up(a, a + 2, 20)
door(l2, 20, 16, "net", "l3_treetop_village:net")
l2.ent("note", 25, 18, text="Net trap (not built): spear-carriers snare you and carry you up into the trees. The door stands in")

l3 = Room("l3_treetop_village", "Treetop Village", 80, 23, "forest", fill="1")
l3.open(1, 2, 78, 19)                        # a floor of branches below: nobody falls here
door(l3, 6, 17, "net", "l2_net_trap:net")
for x, y, w in ((14, 17, 6), (23, 14, 6), (32, 11, 6), (43, 14, 8), (55, 11, 6), (64, 8, 8)):
    l3.ents.append({"t": "jumpthru", "x": x * T, "y": y * T, "w": w * T, "h": 8})
leaf(l3, 34, 8, 4)
l3.ent("strawberry", 36, 6)
l3.ent("note", 10, 19, text="Treetop village: platforming first, and you can't fall")
l3.ent("note", 26, 13, text="Moving, oddly behaving bridges (not built): these jump-throughs stand in")
l3.ent("note", 50, 19, text="Village NPCs (not built)")
l3.ent("note", 68, 7, text="Reward: wall grab (not built yet)")
l3.ent("note", 76, 19, text="Where the village leads: still open")

# Lake Cave is built as one grid, then cut into rooms of its own (one per added screen).
# Extract a named smaller room from the larger authored layout and adjust its coordinates.
def cut(name, title, x0, y0, w, h):
    r = Room(name, title, w, h, c.env)
    r.g = [row[x0:x0 + w] for row in c.g[y0:y0 + h]]
    for e in c.ents:
        if x0 * T <= e["x"] < (x0 + w) * T and y0 * T <= e["y"] < (y0 + h) * T:
            r.ents.append({**e, "x": e["x"] - x0 * T, "y": e["y"] - y0 * T})
    return r, 40 + x0, 46 + y0
D = 23  # everything below the meadow sits one screen lower, under The Hole
rooms = [(m, 0, 0), (j, 80, 0), (hole, 80, 23),
    cut("c0_roar_tunnel", "Roar Tunnel", 0, 0, 40, 23),
    cut("c1_lake_cave", "Lake Cave", 40, 0, 80, 23),
    cut("c2_cave_teeth", "Cave Teeth", 120, 0, 40, 23),
    cut("c3_cove_tunnel", "Cove Tunnel", 160, 0, 40, 23),
    cut("c4_deep_lake", "Deep Lake", 80, 23, 40, 23),
    (t, 240, 23 + D), (j1, 280, 23 + D), (j2, 280, 46 + D), (j3, 360, 46 + D),
    (a1, 440, 46 + D), (h1, 240, 100 + D), (h2, 280, 100 + D), (lh, 593, -14), (s1, 471, 23 + D), (s2, 591, 23 + D),
    (s3, 631, 0 + D), (l1, 396, 69 + D), (l2, 316, 69 + D), (l3, 360, -2 + D)]
unknown = ONLY - {"all"} - {r.name for r, _, _ in rooms}
if unknown:
    sys.exit("no such room: %s" % ", ".join(sorted(unknown)))
written = [r for r, _, _ in rooms if "all" in ONLY or r.name in ONLY]
for r in written:
    r.save()
if a1 in written:
    a1b.save()
if "all" in ONLY:  # rewrites world.json without the island: run tools/story/gen_island.py again after
    json.dump({"start": "m1_meadow", "abilities": [], "rooms": {r.name: [x, y] for r, x, y in rooms},
               "variants": {"a1_ape_arena": [{"when": APE_ID, "room": "a1_ape_arena_after"}]}},
              open(os.path.join(OUT, "world.json"), "w"), indent="\t")
print("wrote", ", ".join(r.name for r in written))
