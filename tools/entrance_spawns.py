# Adds a spawn marker near every entrance of every room of an adventure world, so dying or pressing Retry puts the
# player back at the way they came in (World.enter_room picks the spawn closest to the entry point).
# An entrance is an open stretch of a room's edge that continues into another room, or a door.
# The spawn is the nearest spot inside the room, by path through open tiles, where the player stands on ground with
# 2 tiles of headroom, away from hazards. Generated markers carry "entrance": true and are replaced on every run.
# Usage: python3 tools/entrance_spawns.py <world_dir> [<world_dir> ...]
import json, os, sys
from collections import deque

T = 8
HAZARD = ("acid", "water", "spikes_up", "spikes_down", "spikes_left", "spikes_right")
SOLID_ENTS = ("breakwall", "crumble", "falling", "zip", "dream", "jumpthru")


def add_spawns(world_dir):
    W = json.load(open(os.path.join(world_dir, "world.json")))
    rooms = {}
    for n, (x, y) in W["rooms"].items():
        path = os.path.join(world_dir, n + ".json")
        text = open(path).read()
        rooms[n] = (x, y, json.loads(text), "\n" in text.strip())
    owner = {}  # global open tile -> room
    for n, (x, y, L, _) in rooms.items():
        for ty, row in enumerate(L["tiles"]):
            for tx, c in enumerate(row):
                if c == "0":
                    owner[(x + tx, y + ty)] = n
    total = 0
    for n, (rx, ry, L, pretty) in rooms.items():
        w, h, tiles = L["w"], L["h"], L["tiles"]
        L["entities"] = [e for e in L["entities"] if not (e["t"] == "spawn" and e.get("entrance"))]
        is_open = lambda tx, ty: 0 <= tx < w and 0 <= ty < h and tiles[ty][tx] == "0"
        bad = set()
        for e in L["entities"]:
            if e["t"] in HAZARD or e["t"] in SOLID_ENTS:
                ex, ey = int(e["x"]) // T, int(e["y"]) // T
                ew, eh = max(1, int(e.get("w", T)) // T), max(1, int(e.get("h", T)) // T)
                for yy in range(ey - 1, ey + eh + 1):
                    for xx in range(ex - 1, ex + ew + 1):
                        bad.add((xx, yy))
        # entrances: runs of edge tiles open on both sides of the room border, plus doors
        seeds = []
        for side in "lrtb":
            run = []
            for i in range(h if side in "lr" else w):
                tx, ty = {"l": (0, i), "r": (w - 1, i), "t": (i, 0), "b": (i, h - 1)}[side]
                ox, oy = {"l": (-1, 0), "r": (1, 0), "t": (0, -1), "b": (0, 1)}[side]
                other = owner.get((rx + tx + ox, ry + ty + oy))
                if is_open(tx, ty) and other is not None and other != n:
                    run.append((tx, ty))
                elif run:
                    seeds.append(run)
                    run = []
            if run:
                seeds.append(run)
        for e in L["entities"]:
            if e["t"] == "door":
                ex, ey = int(e["x"]) // T, int(e["y"]) // T
                seeds.append([(ex + i, ey + j) for i in range(max(1, int(e.get("w", T)) // T))
                              for j in range(max(1, int(e.get("h", T)) // T)) if is_open(ex + i, ey + j)])
        spots = []
        for seed in seeds:
            q = deque(seed)
            seen = set(seed)
            found = None
            while q and len(seen) < 4000:
                tx, ty = q.popleft()
                if (1 <= tx < w - 1 and 2 <= ty < h - 1 and is_open(tx, ty - 1) and not is_open(tx, ty + 1)
                        and (tx, ty) not in bad and (tx, ty - 1) not in bad):
                    found = (tx, ty)
                    break
                for ax, ay in ((tx + 1, ty), (tx - 1, ty), (tx, ty + 1), (tx, ty - 1)):
                    if is_open(ax, ay) and (ax, ay) not in seen:
                        seen.add((ax, ay))
                        q.append((ax, ay))
            if found and all(abs(found[0] - s[0]) + abs(found[1] - s[1]) > 4 for s in spots):
                spots.append(found)
        # before any hand-placed spawn: the world uses the last spawn in the list as the level start
        L["entities"] = [{"t": "spawn", "x": sx * T, "y": sy * T, "entrance": True} for sx, sy in spots] + L["entities"]
        total += len(spots)
        with open(os.path.join(world_dir, n + ".json"), "w") as f:
            json.dump(L, f, indent="\t" if pretty else None, separators=None if pretty else (",", ":"))
    print(f"{world_dir}: {total} entrance spawns in {len(rooms)} rooms")


if __name__ == "__main__":
    for d in sys.argv[1:]:
        add_spawns(d)
