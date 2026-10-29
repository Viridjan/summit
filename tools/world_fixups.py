# World-data repair utilities. Unlike the audit tools, these functions can rewrite room JSON to seal edges, settle liquids, alter hazards, remove unreachable content or add spawns. Review generated changes before keeping them.
# Reading help: docs/CODE_GUIDE.md.

# Fix-ups for an adventure world, run after building or editing it:
# 1. seal_edges: an open tile on a room's left, right or top edge that faces no room, or rock in the next room, becomes
#    rock (it looked like a way through but was an invisible wall or led into rock). Bottom openings over nothing stay:
#    they are pits.
# 2. settle_liquids: water and acid fill their basin like real water: every row of a pool spans rock to rock
#    (never overlapping walls, never ending in mid-air). A row that would run out of the room or far past the pool
#    lowers the surface; a pool that can't be held at any level is removed. Pools become one rectangle per run of
#    equal rows; only a pool's top draws the surface line ("top": false on the others).
# 3. unblock_acid: acid kills, so a pool across the only way between two parts cuts the map (in Hollow Knight those
#    need Isma's Tear). Such pools become water with a note; smallest first, then any whose sides connect another way
#    turn back to acid. Door links count as connections; a pool covering a door is always water.
# 4. drop_unreachable: rooms the player can't reach from the start (through open space and doors, acid counts as
#    a wall) are deleted, with any doors leading into them.
# 5. add_spawns: safe entrance candidates, pruned to one point per ordinary room or two for long/tall rooms.
#    Authored checkpoints are retained; World.enter_room picks the closest safe point.
# An entrance is an open stretch of a room's edge that continues into another room, or a door.
# The spawn is the nearest spot inside the room, by path through open tiles, where the player stands on ground with
# 2 tiles of headroom, away from hazards. Generated markers carry "entrance": true and are replaced on every run.
# Usage: python3 tools/world_fixups.py <world_dir> [<world_dir> ...]
import json, os, sys
from collections import deque

T = 8
# World data is in whole units: the World Editor writes 8 as 8.0 (Godot JSON); read those back as ints.
def unit(text):
    v = float(text)
    return int(v) if v.is_integer() else v


HAZARD = ("acid", "water", "spikes_up", "spikes_down", "spikes_left", "spikes_right")
SOLID_ENTS = ("breakwall", "crumble", "falling", "zip", "dream", "jumpthru")


# Close exposed room-edge cells that do not lead to a valid matching neighbor.
def seal_edges(world_dir):
    W = json.load(open(os.path.join(world_dir, "world.json")), parse_float=unit)
    rooms = {}
    for n in W["rooms"]:
        text = open(os.path.join(world_dir, n + ".json")).read()
        rooms[n] = (json.loads(text, parse_float=unit), "\n" in text.strip())
    cell = {}
    for n, (x, y) in W["rooms"].items():
        for ty, row in enumerate(rooms[n][0]["tiles"]):
            for tx, c in enumerate(row):
                cell[(x + tx, y + ty)] = c
    total = 0
    for _ in range(4):  # sealing can expose the tile behind it; repeat until stable
        changed = 0
        for n, (x, y) in W["rooms"].items():
            L = rooms[n][0]
            w, h, tiles = L["w"], L["h"], L["tiles"]
            seal = set()
            for side, pts, (ox, oy) in (("l", [(0, i) for i in range(h)], (-1, 0)), ("r", [(w - 1, i) for i in range(h)], (1, 0)),
                                        ("t", [(i, 0) for i in range(w)], (0, -1))):
                for tx, ty in pts:
                    if tiles[ty][tx] != "0":
                        continue
                    o = cell.get((x + tx + ox, y + ty + oy))
                    if o == "1" or (o is None and side != "t"):  # the top may face nothing: you can jump a bit above it
                        seal.add((tx, ty))
            for tx, ty in seal:
                tiles[ty] = tiles[ty][:tx] + "1" + tiles[ty][tx + 1:]
                cell[(x + tx, y + ty)] = "1"
            changed += len(seal)
        total += changed
        if not changed:
            break
    for n, (L, pretty) in rooms.items():
        with open(os.path.join(world_dir, n + ".json"), "w") as f:
            json.dump(L, f, indent="\t" if pretty else None, separators=None if pretty else (",", ":"))
    print(f"{world_dir}: {total} edge tiles sealed")


# Read the world manifest and associated room dictionaries for the repair pass.
def _load(world_dir):
    W = json.load(open(os.path.join(world_dir, "world.json")), parse_float=unit)
    rooms = {}
    for n in W["rooms"]:
        text = open(os.path.join(world_dir, n + ".json")).read()
        rooms[n] = (json.loads(text, parse_float=unit), "\n" in text.strip())
    return W, rooms


# Write the modified room dictionaries back to their JSON files.
def _save(world_dir, rooms):
    for n, (L, pretty) in rooms.items():
        with open(os.path.join(world_dir, n + ".json"), "w") as f:
            json.dump(L, f, indent="\t" if pretty else None, separators=None if pretty else (",", ":"))


# Fit a liquid region into available terrain while tracking already occupied cells.
def settle_pool(tiles, w, h, x0, y0, pw, ph, taken):
    """Rows of a pool whose surface box is (x0, y0, pw, ph) in tiles: {y: [(xa, xb), ...]} (xb exclusive), or None."""
    is_open = lambda x, y: 0 <= x < w and 0 <= y < h and tiles[y][x] == "0" and (x, y) not in taken
    for level in range(y0, y0 + ph):
        seeds = [(x, y) for y in range(level, y0 + ph) for x in range(x0, x0 + pw) if is_open(x, y)]
        if not seeds:
            continue
        seen, q, leak = set(seeds), deque(seeds), False
        while q and not leak:
            x, y = q.popleft()
            if x <= 0 or x >= w - 1 or x < x0 - pw - 20 or x >= x0 + 2 * pw + 20:
                leak = True  # runs out of the room or far past the pool: not a basin at this level
                break
            for ax, ay in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if level <= ay < y0 + ph and is_open(ax, ay) and (ax, ay) not in seen:
                    seen.add((ax, ay))
                    q.append((ax, ay))
        if leak:
            continue
        rows = {}
        for y in sorted({y for _, y in seen}):
            xs = sorted(x for x, yy in seen if yy == y)
            runs, start = [], xs[0]
            for a, b in zip(xs, xs[1:] + [None]):
                if b != a + 1:
                    runs.append((start, a + 1))
                    start = b
            rows[y] = runs
        return rows
    return None


# Reposition liquid entities to align pools with the surrounding terrain.
def settle_liquids(world_dir):
    W, rooms = _load(world_dir)
    kept = dropped = 0
    for n, (L, _) in rooms.items():
        w, h, tiles = L["w"], L["h"], L["tiles"]
        out, taken = [], set()
        pools = [e for e in L["entities"] if e["t"] in ("acid", "water")]
        pools.sort(key=lambda e: e["t"] != "acid")  # acid first: where both claim a tile, it stays acid
        for e in pools:
            x0, y0 = int(e["x"]) // T, int(e["y"]) // T
            pw, ph = max(1, int(e.get("w", T)) // T), max(1, int(e.get("h", T)) // T)
            rows = settle_pool(tiles, w, h, x0, y0, pw, ph, taken)
            if rows is None:
                dropped += 1
                continue
            kept += 1
            # merge equal runs in consecutive rows into rectangles
            open_rects = {}
            for y in sorted(rows):
                nxt = {}
                for run in rows[y]:
                    for x in range(*run):
                        taken.add((x, y))
                    if run in open_rects:
                        nxt[run] = open_rects.pop(run)
                        nxt[run][1] = y + 1
                    else:
                        nxt[run] = [y, y + 1]
                for run, (ya, yb) in open_rects.items():
                    out.append((e, run, ya, yb))
                open_rects = nxt
            for run, (ya, yb) in open_rects.items():
                out.append((e, run, ya, yb))
        L["entities"] = [x for x in L["entities"] if x["t"] not in ("acid", "water")]
        surface = {}
        for src, run, ya, yb in out:
            surface.setdefault(id(src), min(r[2] for r in out if r[0] is src))
        for src, run, ya, yb in out:
            d = {"t": src["t"], "x": run[0] * T, "y": ya * T, "w": (run[1] - run[0]) * T, "h": (yb - ya) * T}
            if ya != surface[id(src)]:
                d["top"] = False
            L["entities"].append(d)
    _save(world_dir, rooms)
    print(f"{world_dir}: {kept} pools settled, {dropped} that could not be held removed")


# Assign connected-component labels to open grid cells using neighbor traversal.
def _label(free, H, W):
    """4-connected labels of the True cells of a flat list (row-major); -1 elsewhere."""
    lab = [-1] * (H * W)
    k = 0
    for i in range(H * W):
        if free[i] and lab[i] < 0:
            lab[i] = k
            q = [i]
            while q:
                j = q.pop()
                y, x = divmod(j, W)
                for a in ((j - 1) if x > 0 else -1, (j + 1) if x < W - 1 else -1, j - W, j + W):
                    if 0 <= a < H * W and free[a] and lab[a] < 0:
                        lab[a] = k
                        q.append(a)
            k += 1
    return lab


# Adjust acid barriers according to the repair pass connectivity rules.
def unblock_acid(world_dir):
    W_, rooms = _load(world_dir)
    pos = {n: W_["rooms"][n] for n in rooms}
    X0 = min(p[0] for p in pos.values()) - 1
    Y0 = min(p[1] for p in pos.values()) - 1
    W = max(pos[n][0] + rooms[n][0]["w"] for n in rooms) - X0 + 1
    H = max(pos[n][1] + rooms[n][0]["h"] for n in rooms) - Y0 + 1
    open_ = [False] * (W * H)
    acid = [False] * (W * H)
    rects = []  # (room, entity) acid rects
    doors = {}
    door_tiles = []
    for n, (L, _) in rooms.items():
        ox, oy = pos[n][0] - X0, pos[n][1] - Y0
        for y, row in enumerate(L["tiles"]):
            base = (oy + y) * W + ox
            for x, c in enumerate(row):
                if c == "0":
                    open_[base + x] = True
        for e in L["entities"]:
            ex, ey = ox + int(e["x"]) // T, oy + int(e["y"]) // T
            if e["t"] == "acid":
                rects.append((n, e))
                for y in range(ey, ey + int(e["h"]) // T):
                    for x in range(ex, ex + int(e["w"]) // T):
                        acid[y * W + x] = True
            elif e["t"] in ("door", "house_door"):
                doors[n + ":" + e["id"]] = (ey * W + ex, e["to"] if ":" in e["to"] else n + ":" + e["to"])
                door_tiles.extend((y * W + x) for y in range(ey, ey + int(e.get("h", T)) // T) for x in range(ex, ex + int(e.get("w", T)) // T))
    if not rects:
        return
    lab = _label([o and not a for o, a in zip(open_, acid)], H, W)
    plab = _label(acid, H, W)
    parent = {}

    # Find the representative of a connected group in the union/find bookkeeping.
    def find(a):
        while parent.get(a, a) != a:
            a = parent[a]
        return a
    base_links = []
    for k, (i, to) in doors.items():
        if to in doors and lab[i] >= 0 and lab[doors[to][0]] >= 0:
            base_links.append((lab[i], lab[doors[to][0]]))
    sides, size = {}, {}
    for i in range(W * H):
        p = plab[i]
        if p >= 0:
            size[p] = size.get(p, 0) + 1
            for a in (i - 1, i + 1, i - W, i + W):
                if 0 <= a < W * H and lab[a] >= 0:
                    sides.setdefault(p, set()).add(lab[a])

    # Check which region groups become connected under a proposed choice.
    def joined(use):
        parent.clear()
        for a, b in base_links:
            parent[find(a)] = find(b)
        for q in use:
            ls = [find(l) for l in sides.get(q, ())]
            for l in ls:
                parent[l] = ls[0]
    forced = {plab[i] for i in door_tiles if plab[i] >= 0}  # arriving through a door into acid kills: water there
    water = list(forced)
    joined(water)
    for p in sorted(sides, key=lambda p: size[p]):
        if p not in forced and len({find(l) for l in sides[p]}) > 1:
            water.append(p)
            ls = [find(l) for l in sides[p]]
            for l in ls:
                parent[l] = ls[0]
    for p in sorted(water, key=lambda p: -size[p]):  # put back acid whose sides connect another way anyway
        if p in forced:
            continue
        rest = [q for q in water if q != p]
        joined(rest)
        if len({find(l) for l in sides[p]}) == 1:
            water = rest
    water = set(water)
    noted = set()
    for n, e in rects:
        ox, oy = pos[n][0] - X0, pos[n][1] - Y0
        p = plab[(oy + int(e["y"]) // T) * W + ox + int(e["x"]) // T]
        if p in water:
            e["t"] = "water"
            if e.get("top", True) and p not in noted:
                noted.add(p)
                rooms[n][0]["entities"].append({"t": "note", "x": int(e["x"]) + int(e["w"]) // 2 // T * T, "y": int(e["y"]),
                                               "text": "Acid in the original (needs Isma's Tear). Water here so the way on stays open."})
    _save(world_dir, rooms)
    print(f"{world_dir}: {len(water)} of {len(sides)} acid pools turned to water so nothing is cut off")


# Remove placed content that the repair model classifies as unreachable.
def drop_unreachable(world_dir):
    W_, rooms = _load(world_dir)
    pos = W_["rooms"]
    cell = {}  # global tile -> (room, open and not acid)
    doors = {}
    start = None
    for n, (L, _) in rooms.items():
        ox, oy = pos[n]
        acid = set()
        for e in L["entities"]:
            ex, ey = ox + int(e["x"]) // T, oy + int(e["y"]) // T
            if e["t"] == "acid":
                acid.update((x, y) for y in range(ey, ey + int(e["h"]) // T) for x in range(ex, ex + int(e["w"]) // T))
            elif e["t"] in ("door", "house_door"):
                doors[n + ":" + e["id"]] = ((ex, ey), e["to"] if ":" in e["to"] else n + ":" + e["to"])
            elif e["t"] == "spawn" and n == W_["start"] and not e.get("entrance"):
                start = (ex, ey)
        for y, row in enumerate(L["tiles"]):
            for x, c in enumerate(row):
                cell[(ox + x, oy + y)] = (n, c == "0" and (ox + x, oy + y) not in acid)
    if start is None:
        print(f"{world_dir}: no start spawn, nothing removed")
        return
    jump = {at: doors[to][0] for at, to in doors.values() if to in doors}
    seen = {start}
    q = [start]
    while q:
        x, y = q.pop()
        nb = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        for t in ((x, y), (x, y - 1)):  # a door's top tile, reached standing on it or just below
            if t in jump:
                nb.append(jump[t])
        for a in nb:
            c = cell.get(a)
            if c and c[1] and a not in seen:
                seen.add(a)
                q.append(a)
    reached = {cell[t][0] for t in seen}
    gone = [n for n in rooms if n not in reached]
    for n in gone:
        del pos[n]
        del rooms[n]
        os.remove(os.path.join(world_dir, n + ".json"))
    for n, (L, _) in rooms.items():
        L["entities"] = [e for e in L["entities"] if not (e["t"] in ("door", "house_door") and ":" in e["to"] and e["to"].split(":")[0] in gone)]
    _save(world_dir, rooms)
    with open(os.path.join(world_dir, "world.json"), "w") as f:
        json.dump(W_, f, indent="\t")
    print(f"{world_dir}: {len(gone)} rooms that can't be reached removed {gone}")


def prune_spawns(level):
    """Preserve authored checkpoints; cap generated points and keep them apart."""
    authored = [e for e in level["entities"] if e["t"] == "spawn" and not e.get("entrance")]
    candidates = [e for e in level["entities"] if e["t"] == "spawn" and e.get("entrance")]
    budget = 2 if level["w"] >= 80 or level["h"] >= 40 else 1
    kept = list(authored)
    distance = lambda a,b: abs(a["x"]-b["x"]) + abs(a["y"]-b["y"])
    while candidates and len(kept) < budget:
        pick = max(candidates, key=lambda e: min(distance(e,k) for k in kept)) if kept else candidates[0]
        candidates.remove(pick)
        if all(distance(pick,k) >= 64 for k in kept): kept.append(pick)
    level["entities"] = [e for e in level["entities"] if e["t"] != "spawn" or not e.get("entrance") or any(e is k for k in kept)]


# Add room entry spawn markers derived from the available passages.
def add_spawns(world_dir):
    W = json.load(open(os.path.join(world_dir, "world.json")), parse_float=unit)
    rooms = {}
    for n, (x, y) in W["rooms"].items():
        path = os.path.join(world_dir, n + ".json")
        text = open(path).read()
        rooms[n] = (x, y, json.loads(text, parse_float=unit), "\n" in text.strip())
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
            if e["t"] in ("door", "house_door"):
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
        prune_spawns(L)
        total += sum(e["t"] == "spawn" and e.get("entrance", False) for e in L["entities"])
        with open(os.path.join(world_dir, n + ".json"), "w") as f:
            json.dump(L, f, indent="\t" if pretty else None, separators=None if pretty else (",", ":"))
    print(f"{world_dir}: {total} entrance spawns in {len(rooms)} rooms")


if __name__ == "__main__":
    for d in sys.argv[1:]:
        seal_edges(d)
        settle_liquids(d)
        unblock_acid(d)
        drop_unreachable(d)
        add_spawns(d)
