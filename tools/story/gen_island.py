# Eastern island generator (design: docs/reviews/eastern-island/). Writes the island rooms, removes island rooms
# it no longer makes, and adds them (and the shortcut variants) to world.json; other rooms are untouched.
# Rooms are edited in-game too: rerunning rewrites the island rooms and loses those edits.
#   python3 -I tools/story/gen_island.py worlds/story
# then: python3 -I tools/world_fixups.py worlds/story ; python3 -I tools/check_entrances.py worlds/story
# Everything is in whole tiles (T = 8 px). Movement budget (default tuning, measured): rise <= 3 tiles,
# gaps <= 5 tiles. Vertical links are shafts of jump-throughs 3 rows apart; a jump-through flush with a floor over a
# hole is a crust: down + jump drops through it.
#
# Layout (world tiles), main route: West Shore -> Foothills -> Ascent -> Crater -> East Slope -> East Shore ->
# (down) Sea Cave -> Junction -> Flooded Hall -> Echo Gallery -> (down) Lower Maze -> Vent Shaft -> Refuge ->
# Guardian Chamber. Side rooms: North Shore (up from the west shore), South Shore (down from it), Crystal Pocket.
import glob, json, os, re, sys
OUT = sys.argv[1]
T = 8


class Room:
    def __init__(s, name, title, w, h, env, x, y):
        s.name, s.title, s.w, s.h, s.env, s.x, s.y = name, title, w, h, env, x, y
        s.g = [["1"] * w for _ in range(h)]
        s.ents = []
    def rect(s, x0, y0, x1, y1, c):  # inclusive
        for y in range(max(0, y0), min(s.h - 1, y1) + 1):
            for x in range(max(0, x0), min(s.w - 1, x1) + 1):
                s.g[y][x] = c
    def solid(s, *a): s.rect(*a, "1")
    def open(s, *a): s.rect(*a, "0")
    def ent(s, t, x, y, **kw): s.ents.append({"t": t, "x": x * T, "y": y * T, **kw})
    def thru(s, x0, x1, y): s.ents.append({"t": "jumpthru", "x": x0 * T, "y": y * T, "w": (x1 - x0 + 1) * T, "h": 8})
    # jump-throughs every 3 rows from y_low up to y_high, alternating between two column spans
    def ladder(s, y_low, y_high, a, b):
        for k, y in enumerate(range(y_low, y_high - 1, -3)):
            s.thru(*(a if k % 2 == 0 else b), y)
    def pool(s, x0, y0, x1, y1, kind="water", **kw):
        s.open(x0, y0, x1, y1)
        s.ents.append({"t": kind, "x": x0 * T, "y": y0 * T, "w": (x1 - x0 + 1) * T, "h": (y1 - y0 + 1) * T, **kw})
    def door(s, x, y, did, to): s.ents.append({"t": "house_door", "x": x * T, "y": y * T, "w": 2 * T, "h": 3 * T, "id": did, "to": to})
    def save(s, name=None, ents=None):
        d = {"name": s.title, "w": s.w, "h": s.h, "environment": s.env,
             "tiles": ["".join(r) for r in s.g], "entities": s.ents if ents is None else ents}
        json.dump(d, open(os.path.join(OUT, (name or s.name) + ".json"), "w"), indent="\t")


rooms = []
def room(*a):
    r = Room(*a)
    rooms.append(r)
    return r

SHORE, VOLCANO, CAVE = "island_shore", "volcano", "volcanic_cave"

# --- Shore: west (arrival), north, south, east ---------------------------------------------------------------------
w = room("i01_west_shore", "West Shore", 40, 23, SHORE, 700, 46)
w.open(1, 2, 38, 19); w.open(39, 16, 39, 19)
w.open(33, 0, 38, 1); w.ladder(18, 0, (33, 38), (26, 31))  # up to the north shore
w.open(30, 20, 33, 22); w.thru(30, 33, 20)                   # crust down to the south shore
w.solid(16, 18, 18, 19)
w.door(4, 17, "raft", "s2_shore:raft")

n = room("i02_north_shore", "North Shore", 40, 20, SHORE, 700, 26)
n.open(1, 2, 38, 16)
n.open(33, 17, 38, 19); n.thru(33, 38, 17)                   # the way back down (crust)
n.pool(4, 17, 9, 18)                                         # a tide pool
n.solid(15, 14, 17, 16); n.solid(18, 12, 23, 16); n.solid(24, 14, 26, 16)  # the cliff (steps both sides), a star on top
n.ent("energy_fragment", 21, 11, id="north_cliff")

s = room("i03_south_shore", "South Shore", 40, 20, SHORE, 700, 69)
s.open(1, 2, 38, 16)
s.open(30, 0, 33, 1); s.ladder(15, 0, (22, 27), (29, 34))   # back up to the west shore
s.pool(8, 17, 13, 18)
s.solid(4, 14, 6, 16); s.ent("energy_fragment", 5, 13, id="south_rocks")
# Optional cliff-top route over the tide pool; the floor route stays available.
s.solid(8, 11, 10, 11); s.solid(12, 10, 19, 10)
s.ent("strawberry", 16, 9)

e = room("i08_east_shore", "East Shore", 40, 23, SHORE, 868, 46)
e.open(1, 2, 38, 19); e.open(0, 16, 0, 19)
e.open(6, 20, 9, 22); e.thru(6, 9, 20)                       # crust: down into the sea cave
e.pool(28, 20, 37, 21)                                       # the sea
e.solid(20, 17, 22, 19); e.ent("energy_fragment", 21, 16, id="east_coast")

# --- Volcano: foothills, ascent, crater, east slope ----------------------------------------------------------------
f = room("i04_foothills", "Foothills", 40, 23, VOLCANO, 740, 46)
f.open(1, 2, 38, 19); f.open(0, 16, 0, 19); f.open(39, 16, 39, 19)
f.solid(10, 18, 13, 19); f.solid(22, 17, 26, 19); f.solid(30, 18, 32, 19)
# Introduce one slow, clearly warned falling-rock column over safe dry ground.
# The flooded hall later combines the same hazard with water and narrow pillars.
f.ents.append({"t": "rockfall", "x": 18*T, "y": 2*T, "w": T, "h": T, "every": 3.8})

a = room("i05_ascent", "Volcano Ascent", 24, 46, VOLCANO, 780, 23)
a.open(1, 2, 22, 42); a.open(0, 39, 0, 42); a.open(23, 6, 23, 9)
a.solid(19, 10, 23, 10)                                      # the shelf at the top exit
a.solid(19, 30, 22, 34)                                      # outcrop
# Short rail connections between four natural rock ledges, with two rest shelves.
# Jump spacing is unchanged; support types and silhouettes vary across the climb.
for x0, x1, y, solid in [(3,9,40,True), (11,17,37,False), (3,9,34,True),
                         (1,17,31,False), (3,9,28,True), (11,17,25,False),
                         (1,17,22,False), (11,17,19,False), (3,9,16,True), (11,17,13,False)]:
    if solid:
        a.solid(x0,y,x1,y)
    else:
        a.thru(x0,x1,y)

c = room("i06_crater", "Crater", 40, 23, VOLCANO, 804, 23)
c.open(1, 2, 38, 19); c.open(0, 6, 0, 9); c.open(39, 7, 39, 10)
c.solid(0, 10, 8, 19); c.solid(9, 13, 10, 19); c.solid(11, 16, 12, 19)  # the rim and steps down
c.solid(15, 18, 15, 19); c.solid(28, 18, 28, 19); c.solid(20, 17, 23, 19)  # lava pools either side of a rock
c.pool(16, 18, 19, 19, "acid", skin="lava"); c.pool(24, 18, 27, 19, "acid", skin="lava")
c.solid(29, 17, 30, 19); c.solid(31, 14, 32, 19); c.solid(33, 11, 39, 19)  # steps up to the far rim

d = room("i07_east_slope", "East Slope", 24, 46, VOLCANO, 844, 23)
d.open(1, 2, 22, 42); d.open(0, 7, 0, 10); d.open(23, 39, 23, 42)
d.solid(0, 11, 6, 11)
# Broad solid landings make descent deliberate; small intervening rails retain
# a jump-only route back up. This is a different rhythm from the ascent.
for x0, x1, y in [(8,14,14), (15,21,20), (8,14,26), (15,21,32), (8,14,38)]:
    d.solid(x0,y,x1,y)
for x0, x1, y in [(15,21,17), (8,14,23), (15,21,29), (8,14,35), (15,21,41)]:
    d.thru(x0,x1,y)

# --- Under the volcano ---------------------------------------------------------------------------------------------
k = room("i09_sea_cave", "Sea Cave", 24, 23, CAVE, 868, 69)
k.open(1, 2, 22, 19); k.open(6, 0, 9, 1); k.open(0, 16, 0, 19)
k.ladder(18, 0, (5, 10), (12, 17))
k.pool(16, 20, 19, 21)

j = room("i10_junction", "Junction", 40, 23, CAVE, 828, 69)
j.open(1, 2, 38, 19); j.open(39, 16, 39, 19); j.open(0, 10, 0, 13)
j.solid(0, 14, 8, 19); j.solid(9, 17, 10, 19)                # up to the flooded hall
j.solid(18, 2, 21, 9); j.solid(24, 2, 26, 7)                 # split rock hanging from the roof (landmark)
j.solid(30, 18, 33, 19)

h = room("i11_flooded_hall", "Flooded Hall", 48, 23, CAVE, 780, 69)
h.open(1, 2, 46, 21); h.open(0, 8, 0, 11); h.open(47, 10, 47, 13)
h.solid(40, 14, 47, 21); h.solid(1, 12, 6, 21)               # ledges at both ends
h.pool(7, 14, 18, 21); h.pool(24, 14, 39, 21)
for x in (34, 28, 16, 10):
    h.solid(x, 12, x + 1, 21)                                # stone pillars over it
# A dry central well connects to the vent shaft, closing a genuine maze loop.
# Rock walls contain the two pools; down+jump on the crust reveals the passage.
h.solid(19,14,19,22); h.solid(23,14,23,22)
h.open(20,14,22,22)
for y in (14,17,20): h.thru(20,22,y)
h.ents.append({"t": "rockfall", "x": 8 * T, "y": 2 * T, "w": 31 * T, "h": T, "every": 1.2})

g = room("i12_echo_gallery", "Echo Gallery", 40, 23, CAVE, 740, 69)
g.open(1, 2, 38, 19); g.open(39, 8, 39, 11)
g.solid(30, 12, 39, 19); g.solid(27, 15, 29, 19); g.solid(24, 18, 26, 19)  # down from the hall
g.open(4, 20, 7, 22); g.thru(4, 7, 20)                       # crust: down into the lower maze
g.ents.append({"t": "enemy_mosstrot", "x": 14 * T, "y": 19 * T, "facing": 1})
# Shallow, recoverable hollows break up the flat floor without adding lethal pits.
g.open(12,20,16,21); g.thru(12,16,18)

l = room("i13_lower_maze", "Lower Maze", 48, 23, CAVE, 740, 92)
l.open(1, 2, 46, 19); l.open(4, 0, 7, 1); l.open(47, 16, 47, 19)
l.ladder(18, 0, (3, 8), (10, 15))
l.solid(22, 2, 32, 6); l.solid(22, 7, 23, 12); l.solid(31, 7, 32, 12)  # root arch (landmark)
l.open(36, 20, 38, 21)
for x in (36, 37, 38):
    l.ent("spikes_up", x, 21)
l.open(20, 20, 23, 22); l.thru(20, 23, 20)                   # crust: down into the crystal pocket
l.ents.append({"t": "enemy_mosstrot", "x": 28 * T, "y": 19 * T, "facing": -1})
# An optional upper passage under the arch and a lower route below its shelf.
l.solid(18,16,34,16); l.thru(14,19,18); l.thru(32,35,18)
l.ent("strawberry", 27, 15)

v = room("i14_vent_shaft", "Vent Shaft", 16, 32, CAVE, 788, 92)
v.open(1, 2, 14, 28); v.open(0, 16, 0, 19); v.open(15, 25, 15, 28)
v.solid(0, 20, 6, 20)
v.thru(9, 14, 26); v.thru(9, 14, 23)                         # back up to the lower maze
v.open(12,0,14,1)
for x0,x1,y in [(8,14,17), (2,8,14), (8,14,11), (2,8,8), (8,14,5), (8,14,2), (11,14,0)]:
    v.thru(x0,x1,y)  # up to the flooded hall's dry well

r = room("i15_quiet_refuge", "Quiet Refuge", 24, 16, CAVE, 804, 108)
r.open(1, 2, 22, 12); r.open(0, 9, 0, 12); r.open(23, 9, 23, 12)
r.ent("stamina_orb", 12, 11)

# The Guardian: bait three eruptions onto the vent plugs (floor, middle ledge, high ledge). Jump-through rungs
# link the tiers.
b = room("i16_guardian_chamber", "Guardian Chamber", 40, 46, CAVE, 828, 92)
b.open(1, 2, 38, 41); b.open(0, 25, 0, 28)
b.solid(0, 29, 6, 29)                                        # entry ledge
b.solid(26, 33, 38, 33); b.solid(10, 21, 24, 21)             # middle and high ledges
b.thru(10, 15, 39); b.thru(18, 23, 36); b.thru(18, 23, 30); b.thru(10, 15, 27); b.thru(2, 8, 24)
b.ents.append({"t": "boss_gate", "x": 0, "y": 25 * T, "w": T, "h": 4 * T, "closes_behind": True})
HOME = {"t": "house_door", "x": 34 * T, "y": 39 * T, "w": 2 * T, "h": 3 * T, "id": "home", "to": "i01_west_shore:home"}
b.ents.append({"t": "boss_guardian", "x": 14 * T, "y": 2 * T, "w": 12 * T, "h": 8 * T, "door": HOME})
for x, y in ((30, 42), (33, 33), (16, 21)):
    b.ent("vent_plug", x, y, w=2 * T, h=T)
GUARDIAN_ID = "i16_guardian_chamber:guardian_%d_%d" % (14 * T, 2 * T)

o = room("i17_crystal_pocket", "Crystal Pocket", 24, 16, CAVE, 748, 115)
o.open(1, 2, 22, 12); o.open(12, 0, 15, 1)
o.ladder(12, 0, (11, 16), (4, 9))
o.ent("discovery_npc", 3.5, 11, name="Crystal Keeper", kind="mage", variant=2, text="Three energy fragments form one energy upgrade.")

# --- write ---------------------------------------------------------------------------------------------------------
names = {x.name for x in rooms}
for path in glob.glob(os.path.join(OUT, "i[0-9][0-9]_*.json")):  # island rooms from earlier layouts
    if re.sub(r"_after$", "", os.path.basename(path)[:-5]) not in names:
        os.remove(path)
for x in rooms:
    x.save()
# After the guardian (world.json "variants"): the chamber without boss or gate, with the door home; the west shore
# with the door back to the chamber.
b.save("i16_guardian_chamber_after", [x for x in b.ents if x["t"] not in ("boss_gate", "boss_guardian")] + [HOME])
w.save("i01_west_shore_after", w.ents + [{"t": "house_door", "x": 10 * T, "y": 17 * T, "w": 2 * T, "h": 3 * T, "id": "home", "to": "i16_guardian_chamber:home"}])

wp = os.path.join(OUT, "world.json")
W = json.load(open(wp))
W["rooms"] = {k: v for k, v in W["rooms"].items() if not re.match(r"i\d\d_", k)}
W["rooms"].update({x.name: [x.x, x.y] for x in rooms})
W["variants"] = {k: v for k, v in W.get("variants", {}).items() if not re.match(r"i\d\d_", k)}
W["variants"]["i16_guardian_chamber"] = [{"when": GUARDIAN_ID, "room": "i16_guardian_chamber_after"}]
W["variants"]["i01_west_shore"] = [{"when": GUARDIAN_ID, "room": "i01_west_shore_after"}]
json.dump(W, open(wp, "w"), indent="\t")
print("wrote", len(rooms), "island rooms + 2 variants")
