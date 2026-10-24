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
    def __init__(s, name, title, w, h, env, fill="0"):
        s.name, s.title, s.w, s.h, s.env = name, title, w, h, env
        s.g = [[fill] * w for _ in range(h)]
        s.ents = []
    def rect(s, x0, y0, x1, y1, c):  # inclusive
        for y in range(max(0, y0), min(s.h - 1, y1) + 1):
            for x in range(max(0, x0), min(s.w - 1, x1) + 1):
                s.g[y][x] = c
    def solid(s, *a): s.rect(*a, "1")
    def open(s, *a): s.rect(*a, "0")
    def ent(s, t, x, y, **kw): s.ents.append({"t": t, "x": x * T, "y": y * T, **kw})
    def spikes_up(s, x0, x1, y):
        for x in range(x0, x1 + 1): s.ent("spikes_up", x, y)
    def water(s, x0, y0, x1, y1, **kw):
        s.ents.append({"t": "water", "x": x0 * T, "y": y0 * T, "w": (x1 - x0 + 1) * T, "h": (y1 - y0 + 1) * T, **kw})
    def save(s):
        d = {"name": s.title, "w": s.w, "h": s.h, "environment": s.env,
             "tiles": ["".join(r) for r in s.g], "entities": s.ents}
        json.dump(d, open(os.path.join(OUT, s.name + ".json"), "w"), indent="\t")

G = 19  # ground top row everywhere (rows G..h-1 solid)

# 1. Meadow: flat, a few jumps and spikes, no enemies
m = Room("m1_meadow", "Meadow", 80, 23, "sky")
m.solid(0, G, 79, 22); m.solid(0, 0, 0, 22)
m.solid(14, 18, 16, 18)                      # low bump
m.solid(26, 17, 27, 18)                      # 2-high block
m.open(36, G, 38, G); m.spikes_up(36, 38, G) # small spike pit, 3 wide
m.solid(48, 17, 50, 18)
m.spikes_up(58, 58, 18)                      # one spike on the grass
m.solid(66, 17, 69, 18)
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
c.open(119, 9, 198, G - 1)                   # right chambers
c.solid(130, 9, 138, 11); c.solid(160, 9, 175, 12); c.solid(186, 9, 198, 13)  # ceiling teeth
c.open(150, 3, 152, 8)                       # dead-end tunnel up
c.solid(146, 16, 148, 18); c.solid(168, 17, 171, 18)  # rocks to hop over
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
c.ent("note", 3, 18, text="A roar from the left (stereo audio, not built yet)")
c.ent("note", 101, 5, text="Dead end")
c.ent("note", 151, 6, text="Dead end")
c.ent("strawberry", 82, 39)

# 4. Cove town: two NPCs, the second energy block, a quest
t = Room("t1_cove_town", "Cove Town", 40, 23, "sea")
t.solid(0, G, 39, 22); t.solid(0, 0, 0, 15); t.solid(39, 0, 39, 14)  # right edge rows 15..18 lead into the jungle
t.ents.append({"t": "jumpthru", "x": 8 * T, "y": 15 * T, "w": 6 * T, "h": 8})   # roof
t.ents.append({"t": "jumpthru", "x": 18 * T, "y": 15 * T, "w": 6 * T, "h": 8})  # second roof
t.solid(8, 16, 8, 18); t.solid(13, 16, 13, 18)   # house walls
t.solid(18, 16, 18, 18); t.solid(23, 16, 23, 18)
t.open(30, G, 38, 20); t.water(30, G, 38, 20)    # the sea
t.ent("spawn", 2, 18)
t.ent("energy_orb", 5, 17)
t.ent("energy_block", 20, 13)
t.ent("note", 10, 18, text="NPC (not built yet): villager")
t.ent("note", 26, 18, text="NPC (not built yet): quest giver, quest rewards a skill point")
t.ent("note", 15, 18, text="Houses: doors into them come later")

# 5. Jungle (section 1.5): forest theme, a hollow trunk, leaf platforms, calm Mosstrots; the player drops down again
def leaf(r, x, y, w): r.ents.append({"t": "leaf", "x": x * T, "y": y * T, "w": w * T, "h": 8})
def mosstrot(r, x, y): r.ents.append({"t": "enemy_mosstrot", "x": x * T, "y": y * T, "facing": 1})
j1 = Room("j1_jungle_edge", "Jungle Edge", 40, 23, "forest")
j1.solid(0, G, 39, 22); j1.solid(0, 0, 39, 1); j1.solid(0, 0, 0, 14); j1.solid(39, 0, 39, 22)
j1.solid(14, 4, 16, 15)                      # big trunk, hollow at the base (rows 16..18)
leaf(j1, 9, 16, 4); leaf(j1, 4, 13, 4); leaf(j1, 9, 10, 4); leaf(j1, 4, 7, 4)  # zigzag up the trunk's left side
j1.ent("strawberry", 5, 4)
mosstrot(j1, 24, 18)
j1.open(31, G, 38, 22)                       # the ground ends: drop into the falls below
j1.ent("note", 27, 18, text="Mosstrots just wander. Jump over them.")

j2 = Room("j2_jungle_falls", "Jungle Falls", 80, 23, "forest", fill="1")
j2.open(1, 3, 78, G - 1); j2.open(31, 0, 38, 2)   # the drop from Jungle Edge
j2.solid(5, 13, 22, 18); j2.open(5, 16, 22, 18)   # hill with a tunnel through it (dead end, a star)
j2.ent("strawberry", 6, 17)
mosstrot(j2, 14, 12); mosstrot(j2, 28, 18)
j2.open(40, G, 60, 20); j2.water(40, G, 60, 20)   # the lake
j2.ents.append({"t": "waterfall", "x": 44 * T, "y": 3 * T, "w": 4 * T, "h": 16 * T})
leaf(j2, 56, 16, 4); leaf(j2, 51, 13, 4); leaf(j2, 56, 10, 4)  # up from the lake's right shore
j2.ent("strawberry", 58, 7)
j2.solid(64, 17, 68, 18); j2.solid(69, 15, 78, 18)  # hills up to the exit
j2.open(79, 11, 79, 14)                      # right edge rows 11..14 lead on

j3 = Room("j3_jungle_hills", "Jungle Hills", 80, 23, "forest", fill="1")
for x0, x1, top in ((1, 15, 15), (16, 22, 17), (23, 57, 19), (58, 64, 17), (65, 78, 15)):
    j3.open(x0, 2, x1, top - 1)              # the ground's top row per stretch
j3.open(0, 11, 0, 14)
j3.solid(32, 6, 46, 18); j3.open(32, 16, 46, 18)  # hill with a tunnel through it
j3.solid(52, 2, 54, 16)                      # big trunk, hollow at the base
leaf(j3, 56, 16, 3); leaf(j3, 59, 13, 4); leaf(j3, 56, 10, 3)  # up the trunk's right side
j3.ent("strawberry", 57, 8)
mosstrot(j3, 39, 5)  # on the tunnel hill's top, off the walking path
j3.open(79, 11, 79, 14)                      # right edge rows 11..14 lead into the Ape's arena
j3.ent("note", 75, 14, text="A deep roar ahead: the Ape's arena")

# 6. The Ape's arena (section 1.6, the boss is not built yet) and the fork (1.7)
def door(r, x, y, did, to): r.ents.append({"t": "door", "x": x * T, "y": y * T, "w": 2 * T, "h": 3 * T, "id": did, "to": to})
a1 = Room("a1_ape_arena", "Ape Arena", 80, 23, "forest", fill="1")
a1.open(1, 2, 78, G - 1); a1.open(0, 11, 0, 14); a1.open(79, 12, 79, 15)
a1.solid(1, 15, 8, 18); a1.solid(71, 16, 78, 18)  # ledges at both exits (the right one is a 3-tile jump)
a1.open(12, G, 15, 22)                       # left branch: down, back through the jungle (gated during the fight)
# The tree puzzle and its bridge pit are removed: the fight uses one open arena.
a1.spikes_up(60, 62, 18)
a1.ents.append({"t": "boss_ape", "x": 26 * T, "y": 15 * T,
    "range": [9 * T, 71 * T],
    "spikes": [[[66 * T, 18 * T, 3]], [[56 * T, 18 * T, 2], [69 * T, 18 * T, 2]]],
    "orb": [64 * T, 16 * T]})
a1.ents.append({"t": "boss_gate", "x": 78 * T, "y": 12 * T, "w": T, "h": 4 * T})   # right exit
a1.ents.append({"t": "boss_gate", "x": 12 * T, "y": G * T, "w": 4 * T, "h": T})   # the hole to the left branch
a1.ent("note", 10, 18, text="Left branch, once the Ape is beaten: down here, back through the jungle")
a1.ent("note", 20, 18, text="The Ape! Move towards it when it leaps: it lands past you")
a1.ent("note", 57, 18, text="Lure its leaps onto spikes")
a1.ent("note", 75, 15, text="Right branch: the sand cave. Reward for the Ape: a power-up (not decided yet)")

# Right branch: a sand cave climbing at about 25-30 degrees, then the shore and the lighthouse
s1 = Room("s1_sand_cave", "Sand Cave", 80, 46, "sand", fill="1")
top = [39 - (x * 30) // 78 for x in range(80)]
for a, b in ((24, 27), (52, 55)):            # flat stretches over pits
    for x in range(a, b + 1): top[x] = top[a]
for x in range(80):
    s1.open(x, top[x] - 7, x, top[x] - 1)
for a, b in ((24, 27), (52, 55)):            # breakable sand: crumble blocks over 2-deep pits
    s1.open(a, top[a], b, top[a] + 1)
    s1.ents.append({"t": "crumble", "x": a * T, "y": top[a] * T, "w": (b - a + 1) * T, "h": 8})
s1.ent("note", 3, top[3] - 1, text="The Ape screams and chases you up the cave (not built yet)")
s1.ent("note", 12, top[12] - 1, text="Rocks fall and seal the cave behind you (not built yet)")
s1.ent("note", 22, top[22] - 1, text="Breakable sand platforms: crumble blocks stand in")
s1.ent("note", 70, top[70] - 1, text="Reward: the sword (not built yet; needs 2 energy blocks to use)")

s2 = Room("s2_shore", "Shore", 80, 23, "sea")
s2.solid(0, 9, 14, 22); s2.solid(0, 0, 0, 0)  # the cliff we come out on, the mountain's foot
s2.solid(8, 2, 12, 2)                        # mountain ledge, out of reach for now
s2.ent("strawberry", 10, 1)
s2.ent("note", 4, 8, text="The mountain: clearly climbable, but not yet")
s2.solid(15, G, 79, 22); s2.solid(79, 0, 79, 22)
s2.open(56, G, 78, 21); s2.water(56, G, 78, 21)  # the sea
s2.ent("note", 60, 18, text="Raft to the next island (not built): needs the lighthouse quest")
s2.solid(44, 0, 44, 18); s2.solid(52, 0, 52, 18); s2.open(44, 16, 44, 18)  # lighthouse, door on the left
for y in (16, 13, 10, 7, 4, 1):
    s2.ents.append({"t": "jumpthru", "x": 45 * T, "y": y * T, "w": 7 * T, "h": 8})
s2.ent("note", 41, 18, text="The lighthouse: climb to the top")

s3 = Room("s3_lighthouse_top", "Lighthouse Top", 40, 23, "sky")
s3.solid(4, 11, 4, 22); s3.solid(12, 11, 12, 22)  # the tower, continued from the shore
for y in (20, 17, 14):
    s3.ents.append({"t": "jumpthru", "x": 5 * T, "y": y * T, "w": 7 * T, "h": 8})
s3.solid(0, 11, 3, 12); s3.solid(13, 11, 39, 12)  # the top: the silent village
s3.ents.append({"t": "jumpthru", "x": 5 * T, "y": 11 * T, "w": 7 * T, "h": 8})
s3.solid(24, 7, 26, 10)                      # the flame's pedestal
s3.ent("note", 25, 6, text="Magic flame, aimed one way by mirrors (not built yet)")
for i, x in enumerate((15, 19, 29, 33)):
    s3.ent("note", x, 10, text='Silent villager (not built): "..."')
s3.ent("note", 37, 10, text='Silent villager with a quest (not built): "..." Speak to them before the raft works')

# Left branch: back through the jungle, a net trap, the treetop village
l1 = Room("l1_jungle_depths", "Jungle Depths", 80, 23, "forest", fill="1")
l1.open(1, 3, 78, G - 1); l1.open(12, 0, 15, 2); l1.open(0, 15, 0, 18)
l1.solid(30, 14, 40, 18); l1.open(30, 17, 40, 18)  # hill with a low tunnel
l1.open(60, G, 70, 20); l1.water(60, G, 70, 20)
mosstrot(l1, 22, 18); mosstrot(l1, 52, 18)
l1.ent("note", 8, 18, text="The Ape screams behind you; cross the jungle again (audio not built)")

l2 = Room("l2_net_trap", "Net Trap", 80, 23, "forest", fill="1")
l2.open(1, 3, 78, G - 1); l2.open(79, 15, 79, 18)
leaf(l2, 50, 15, 4); leaf(l2, 44, 12, 4)
mosstrot(l2, 60, 18)
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
def cut(name, title, x0, y0, w, h):
    r = Room(name, title, w, h, c.env)
    r.g = [row[x0:x0 + w] for row in c.g[y0:y0 + h]]
    for e in c.ents:
        if x0 * T <= e["x"] < (x0 + w) * T and y0 * T <= e["y"] < (y0 + h) * T:
            r.ents.append({**e, "x": e["x"] - x0 * T, "y": e["y"] - y0 * T})
    return r, 40 + x0, 23 + y0
rooms = [(m, 0, 0), (j, 80, 0),
    cut("c0_roar_tunnel", "Roar Tunnel", 0, 0, 40, 23),
    cut("c1_lake_cave", "Lake Cave", 40, 0, 80, 23),
    cut("c2_cave_teeth", "Cave Teeth", 120, 0, 40, 23),
    cut("c3_cove_tunnel", "Cove Tunnel", 160, 0, 40, 23),
    cut("c4_deep_lake", "Deep Lake", 80, 23, 40, 23),
    (t, 240, 23), (j1, 280, 23), (j2, 280, 46), (j3, 360, 46),
    (a1, 440, 46), (s1, 520, 23), (s2, 600, 23), (s3, 640, 0), (l1, 440, 69), (l2, 360, 69), (l3, 440, 23)]
unknown = ONLY - {"all"} - {r.name for r, _, _ in rooms}
if unknown:
    sys.exit("no such room: %s" % ", ".join(sorted(unknown)))
written = [r for r, _, _ in rooms if "all" in ONLY or r.name in ONLY]
for r in written:
    r.save()
if "all" in ONLY:
    json.dump({"start": "m1_meadow", "abilities": [], "rooms": {r.name: [x, y] for r, x, y in rooms}},
              open(os.path.join(OUT, "world.json"), "w"), indent="\t")
print("wrote", ", ".join(r.name for r in written))
