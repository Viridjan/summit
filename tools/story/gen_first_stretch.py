# One-off generator for worlds/story (chapter 1, first stretch). Rooms are edited in-game afterwards.
import json, os, sys
OUT = sys.argv[1]
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
# lower cave (one screen, cols 80..119 rows 23..45): a hole in the lake floor drops into a deep lake
c.open(88, 21, 91, 25)
c.open(81, 26, 118, 40)
c.water(81, 34, 118, 40)
c.solid(98, 26, 108, 29)                     # ceiling tooth
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
mosstrot(j3, 26, 18); mosstrot(j3, 70, 14)
j3.ent("note", 75, 14, text="Boss 1, the Ape, waits past here (not built yet)")

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
    (t, 240, 23), (j1, 280, 23), (j2, 280, 46), (j3, 360, 46)]
for r, _, _ in rooms:
    r.save()
json.dump({"start": "m1_meadow", "abilities": [], "rooms": {r.name: [x, y] for r, x, y in rooms}},
          open(os.path.join(OUT, "world.json"), "w"), indent="\t")
print("wrote", len(rooms), "rooms")
