# Read-only world check for safe, flat entry tiles during the brief automatic walk into neighboring rooms. Coordinates in this checker are tiles unless converted explicitly.
# Reading help: docs/CODE_GUIDE.md.

"""Sideways room entrances must be flat for their first two tiles on both sides, so the walk-in after a room
change (World.enter_room) lands on solid ground: floor (or a jump-through) at the doorway's floor row,
2 tiles of headroom, no spikes or acid. Usage: python3 tools/check_entrances.py worlds/story
"""
import json, os, sys


# Find border entrances whose initial walk-in space is blocked or lacks the expected support.
def bad_entrances(d):
    # Read one JSON document and close the file before returning its data.
    def load(name):
        with open(os.path.join(d, name)) as f:
            return json.load(f)
    W = load("world.json")
    rooms = {n: (p[0], p[1], load(n + ".json")) for n, p in W["rooms"].items()}
    # Look up one tile, handling coordinates that fall outside the selected room.
    def tile(n, x, y):
        rx, ry, L = rooms[n]
        if 0 <= x < L["w"] and 0 <= y < L["h"]: return L["tiles"][y][x]
        return None
    owner = {}
    for n, (rx, ry, L) in rooms.items():
        for y, row in enumerate(L["tiles"]):
            for x, c in enumerate(row):
                owner[(rx + x, ry + y)] = n
    plat = {}
    for n, (rx, ry, L) in rooms.items():
        for e in L["entities"]:
            if e["t"] in ("jumpthru", "leaf"):
                for i in range(int(e["w"]) // 8):
                    plat[(n, int(e["x"]) // 8 + i, int(e["y"]) // 8)] = True
    spikes = {}
    for n, (rx, ry, L) in rooms.items():
        for e in L["entities"]:
            if e["t"].startswith("spikes") or e["t"] == "acid":
                for i in range(max(1, int(e.get("w", 8)) // 8)):
                    for j in range(max(1, int(e.get("h", 8)) // 8)):
                        spikes[(rx + int(e["x"]) // 8 + i, ry + int(e["y"]) // 8 + j)] = True
    bad = []
    for n, (rx, ry, L) in rooms.items():
        w, h = L["w"], L["h"]
        for side, x, dx in (("left", 0, 1), ("right", w - 1, -1)):
            y = 0
            while y < h:
                o = owner.get((rx + x - dx, ry + y))
                if L["tiles"][y][x] == "0" and o and o != n:
                    y0 = y
                    while y < h and L["tiles"][y][x] == "0" and owner.get((rx + x - dx, ry + y)) == o: y += 1
                    floor = y  # first solid row under the opening (in this room)
                    # tiles 0 and 1 inside: open at floor-1, floor-2; solid at floor; no spikes
                    ok = floor < h
                    for k in (0, 1):
                        tx = x + dx * k
                        ok = ok and (tile(n, tx, floor) == "1" or plat.get((n, tx, floor))) and tile(n, tx, floor - 1) == "0" and tile(n, tx, floor - 2) == "0" and not spikes.get((rx + tx, ry + floor - 1))
                    if not ok:
                        bad.append((n, side, "rows %d..%d" % (y0, y - 1), "floor row %d" % floor))
                else:
                    y += 1
    return bad


if __name__ == "__main__":
    bad = bad_entrances(sys.argv[1])
    for b in bad:
        print(*b)
    print(len(bad), "bad entrance(s)")
    sys.exit(1 if bad else 0)
