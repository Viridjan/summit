#!/usr/bin/env python3
"""Build the draft rooms of a world: connect them as a maze, then give each one terrain.

    python3 tools/story/build_drafts.py [world_dir] [--seed N] [--extra K] [--dry]

A draft is a room whose file has "draft": true (World Editor > Add > empty room). Place drafts where you want them;
rooms that touch along an edge (3+ tiles) can be linked. Then:

1. Maze: a random spanning tree over the drafts, so there is exactly one way into each (the base pattern). A
   draft next to a finished room links to it only where that room's edge is already open (an exit waiting).
2. Shortcuts: K extra links between drafts (default 2), each closed by an ability gate: "attack" (a breakable
   wall in the doorway), "dash" (a spike pit in front of it) or "climb" (the doorway high up a sheer wall).
   Upgrades cut into the map.
3. Terrain: each draft gets a floor, its doorways (3 tiles), and stepping platforms (rises of at most 3 tiles,
   gaps of at most 3) up to every doorway; a few bumps for variety. The room is checked with the cautious
   movement model (tools/world_check.py): every ungated doorway must reach every other; it's rebuilt with
   another seed until it does.
4. The room loses "draft" and keeps its region; drafts with no region join the region of a finished neighbour.

It finishes with world_fixups' edge sealing and entrance spawns (not its unreachable-room sweep). The World Editor's
"Build drafts" button runs it on the open world.
"""
import json, os, random, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from world_check import World, MODELS, explore

T = 8
GATES = ["attack", "dash", "climb"]
DOOR = 3  # doorway size in tiles


def load(d):
    W = json.load(open(os.path.join(d, "world.json")))
    rooms = {n: json.load(open(os.path.join(d, n + ".json"))) for n in W["rooms"]}
    return W, rooms


# Shared border between two rooms: ("x", x, y0, y1) for a vertical edge at world column x (a on the left),
# ("y", y, x0, x1) for a horizontal one (a above); None when they don't touch along 3+ tiles.
def border(W, rooms, a, b):
    (ax, ay), (bx, by) = W["rooms"][a], W["rooms"][b]
    aw, ah, bw, bh = rooms[a]["w"], rooms[a]["h"], rooms[b]["w"], rooms[b]["h"]
    if ax + aw == bx or bx + bw == ax:
        y0, y1 = max(ay, by), min(ay + ah, by + bh)
        if y1 - y0 >= DOOR + 2:
            return ("x", ax + aw if ax + aw == bx else ax, y0, y1, a if ax + aw == bx else b)
    if ay + ah == by or by + bh == ay:
        x0, x1 = max(ax, bx), min(ax + aw, bx + bw)
        if x1 - x0 >= DOOR + 2:
            return ("y", ay + ah if ay + ah == by else ay, x0, x1, a if ay + ah == by else b)
    return None


# Where a finished room's edge is open along a border: list of world cells just inside it.
def open_cells(W, rooms, name, edge):
    ox, oy = W["rooms"][name]
    t = rooms[name]["tiles"]
    kind, at, lo, hi, first = edge
    out = []
    for v in range(lo, hi):
        if kind == "x":
            x = at - 1 if first == name else at
            if t[v - oy][x - ox] == "0":
                out.append(v)
        else:
            y = at - 1 if first == name else at
            if t[y - oy][v - ox] == "0":
                out.append(v)
    return out


def maze(W, rooms, drafts, rng, extra):
    links = {}  # frozenset(a, b) -> {"edge", "gate", "span": (lo, hi) world cells of the doorway}
    finished_exits = []
    for d in drafts:
        for n in rooms:
            if n == d or n in drafts:
                continue
            e = border(W, rooms, d, n)
            if e:
                cells = open_cells(W, rooms, n, e)
                if len(cells) >= 2:
                    finished_exits.append((d, n, e, (min(cells), max(cells) + 1)))
    pairs = [(a, b, border(W, rooms, a, b)) for i, a in enumerate(drafts) for b in drafts[i + 1:]]
    pairs = [p for p in pairs if p[2]]
    rng.shuffle(pairs)
    parent = {d: d for d in drafts}

    def root(x):
        while parent[x] != x:
            x = parent[x]
        return x
    for d, n, e, span in finished_exits:  # every exit of a finished room into a draft stays a way in
        links[frozenset((d, n))] = dict(edge=e, gate=None, span=span)
        parent[root(d)] = root(n) if n in parent else "__finished__"
        parent.setdefault("__finished__", "__finished__")
    spare = []
    for a, b, e in pairs:  # spanning tree (Kruskal)
        if root(a) != root(b):
            parent[root(a)] = root(b)
            links[frozenset((a, b))] = dict(edge=e, gate=None, span=None)
        else:
            spare.append((a, b, e))
    for a, b, e in spare[:extra]:  # shortcuts behind an ability (a roof or floor doorway: a breakable plug)
        links[frozenset((a, b))] = dict(edge=e, gate=rng.choice(GATES) if e[0] == "x" else "attack", span=None)
    for key, v in links.items():  # doorway position on a draft-draft border, inside both rooms' open area
        if v["span"] is None:
            kind, at, lo, hi, _ = v["edge"]
            for n in key:
                (ox, oy), lvl = W["rooms"][n], rooms[n]
                if kind == "x":  # door rows between the roof (row 2) and the floor (row h-3)
                    lo, hi = max(lo, oy + 2), min(hi, oy + lvl["h"] - 2)
                else:
                    lo, hi = max(lo, ox + 2), min(hi, ox + lvl["w"] - 2)
            if hi - lo < DOOR:
                continue  # no room for a doorway: left closed
            gate = v["gate"]
            if kind == "x" and gate == "dash":
                s = hi - DOOR  # a spike pit needs the doorway on the floor
            elif kind == "x" and gate == "climb":
                s = lo  # high up, over a sheer wall
            else:
                s = rng.randint(lo, hi - DOOR)
            v["span"] = (s, s + DOOR)
    return {k: v for k, v in links.items() if v["span"] is not None}


def carve(t, x, y, ch="0"):
    if 0 <= y < len(t) and 0 <= x < len(t[0]):
        t[y][x] = ch


# Terrain for one draft: returns (tiles, entities) or None when the checker can't cross it.
def build_room(name, lvl, pos, doors, rng):
    w, h = lvl["w"], lvl["h"]
    ox, oy = pos
    t = [["1"] * w for _ in range(h)]
    floor = h - 3  # the standing row; rows below are rock
    for y in range(2, floor + 1):
        for x in range(1, w - 1):
            t[y][x] = "0"
    ents = []
    plats = []  # (x0, x1, y) one-way platforms
    targets = []  # standing cells to reach: (x, y, gated)
    for side, lo, hi, gate in doors:  # lo..hi in room coordinates along the side
        if side in ("L", "R"):
            x = 0 if side == "L" else w - 1
            sill = min(hi, floor + 1)  # standing row of the doorway: its lowest open cell
            for y in range(lo, hi):
                carve(t, x, y)
            for y in range(hi, floor + 1):  # rock under a raised doorway, so it has a sill
                carve(t, x, y, "1")
            inner = 1 if side == "L" else w - 2
            targets.append((inner, hi - 1, gate))
            if hi <= floor:  # a raised doorway: a 3-wide rock ledge under it
                for dx in range(3):
                    carve(t, inner + (dx if side == "L" else -dx), hi, "1")
            if gate == "climb":  # a sheer wall below the doorway: no platforms up to it
                for y in range(hi, floor + 1):
                    for dx in range(3):
                        carve(t, inner + (dx if side == "L" else -dx), y, "1")
            if gate == "attack":
                ents.append({"t": "breakwall", "x": x * T if side == "L" else (w - 1) * T, "y": lo * T, "w": T, "h": (hi - lo) * T})
            if gate == "dash":  # a spike pit in front of the doorway, 6 wide
                for dx in range(2, 8):
                    xx = inner + (dx if side == "L" else -dx)
                    carve(t, xx, floor + 1, "0")
                    ents.append({"t": "spikes_up", "x": xx * T, "y": (floor + 1) * T})
        else:
            y = 0 if side == "T" else h - 1
            for x in range(lo, hi):
                carve(t, x, y)
                if side == "T":
                    carve(t, x, 1)
                else:
                    for yy in range(floor + 1, h):
                        carve(t, x, yy)
            targets.append((lo + 1, 1 if side == "T" else h - 1, gate))
            if gate == "attack":  # plug the shaft with a breakable wall (in the lower room's roof)
                if side == "T":
                    ents.append({"t": "breakwall", "x": lo * T, "y": 0, "w": (hi - lo) * T, "h": 2 * T})
            if side == "T":  # a one-way ledge under a doorway in the roof
                plats.append((lo, hi, 2))
    # stepping platforms up to every raised target: a staircase of 3-wide ledges, rising 3 at a time
    for tx, ty, gate in targets:
        if gate == "climb" or ty >= floor - 2:
            continue
        x, y = tx, ty + 1  # the ledge row under the target
        direction = 1 if tx < w // 2 else -1
        while y < floor - 2:  # down 3 rows at a time until the floor is in jumping reach
            y += 3
            if y > floor:
                break
            x = max(2, min(w - 5, x + direction * rng.randint(2, 4)))
            plats.append((x, x + 3, y))
    for x0, x1, y in plats:
        ents.append({"t": "jumpthru", "x": x0 * T, "y": y * T, "w": (x1 - x0) * T, "h": T})
    # rock chunks for shape: overhangs, pillars, bumps; never on a doorway, ledge, platform or pit (+2 tiles)
    keep_clear = set()
    for tx, ty, _ in targets:
        for y in range(ty - 4, ty + 3):
            for x in range(tx - 5, tx + 6):
                keep_clear.add((x, y))
    for x0, x1, y in plats:
        for yy in range(y - 4, y + 2):
            for x in range(x0 - 2, x1 + 2):
                keep_clear.add((x, yy))
    for e in ents:
        for x in range(e["x"] // T - 2, (e["x"] + e.get("w", T)) // T + 2):
            for y in range(e["y"] // T - 3, (e["y"] + e.get("h", T)) // T + 2):
                keep_clear.add((x, y))
    for _ in range(rng.randint(4, 8)):
        cw, ch = rng.randint(2, 7), rng.randint(2, 5)
        cx = rng.randint(2, w - cw - 2)
        cy = rng.choice([2, floor - ch + 1, rng.randint(4, max(4, floor - ch - 3))])  # hanging, standing or floating
        cells = [(x, y) for x in range(cx, cx + cw) for y in range(cy, cy + ch)]
        if not any(c in keep_clear for c in cells):
            for x, y in cells:
                carve(t, x, y, "1")
    tiles = ["".join(r) for r in t]
    return tiles, ents, targets


def check_room(name, lvl, targets):
    with tempfile.TemporaryDirectory() as d:
        json.dump({"start": name, "rooms": {name: [0, 0]}}, open(os.path.join(d, "world.json"), "w"))
        json.dump(lvl, open(os.path.join(d, name + ".json"), "w"))
        Wc = World(d)
        free = [(x, y) for x, y, gate in targets if gate is None]
        for i, a in enumerate(free):
            ground, _ = explore(Wc, MODELS["cautious"], set(), [a])
            reach = {(x, y) for x, y in ground}
            for b in free:
                if b != a and not any(abs(b[0] - x) <= 1 and abs(b[1] - y) <= 1 for x, y in reach):
                    return False
        return True


def main():
    args = sys.argv[1:]
    d = next((a for a in args if not a.startswith("--") and not a.isdigit()), "worlds/story")
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else 1
    extra = int(args[args.index("--extra") + 1]) if "--extra" in args else 2
    rng = random.Random(seed)
    W, rooms = load(d)
    drafts = sorted(n for n, r in rooms.items() if r.get("draft"))
    if not drafts:
        print("no draft rooms in", d)
        return
    links = maze(W, rooms, drafts, rng, extra)
    for name in drafts:
        lvl = rooms[name]
        ox, oy = W["rooms"][name]
        doors = []
        for key, v in links.items():
            if name not in key:
                continue
            kind, at, lo, hi, first = v["edge"]
            s0, s1 = v["span"]
            if kind == "x":
                doors.append(("R" if first == name else "L", s0 - oy, s1 - oy, v["gate"]))
            else:
                doors.append(("B" if first == name else "T", s0 - ox, s1 - ox, v["gate"]))
        for tries in range(20):
            tiles, ents, targets = build_room(name, lvl, (ox, oy), doors, random.Random(seed * 1000 + tries + hash(name) % 997))
            trial = dict(lvl, tiles=tiles, entities=ents)
            if check_room(name, trial, targets):
                break
        else:
            print("  %s: no crossable layout found, kept the last try" % name)
        lvl.update(tiles=tiles, entities=[e for e in lvl["entities"] if e["t"] not in ("spawn",) and e["t"] != "jumpthru"] + ents)
        lvl.pop("draft", None)
        print("%-24s doors %s" % (name, ", ".join("%s%s" % (s, "(" + g + ")" if g else "") for s, _, _, g in doors) or "none"))
    regions = W.get("regions", [])
    for name in drafts:  # drafts with no region join a finished neighbour's
        if any(name in g["rooms"] for g in regions):
            continue
        for key in links:
            other = next(iter(key - {name}), None) if name in key else None
            g = next((g for g in regions if other in g["rooms"]), None)
            if g:
                g["rooms"].append(name)
                break
    if "--dry" in args:
        print("dry run: nothing written")
        return
    for name in drafts:
        json.dump(rooms[name], open(os.path.join(d, name + ".json"), "w"), indent="\t")
    json.dump(W, open(os.path.join(d, "world.json"), "w"), indent="\t")
    import world_fixups  # close edges that lead nowhere and add entrance spawns (not the unreachable-room sweep)
    world_fixups.seal_edges(d)
    world_fixups.add_spawns(d)
    gated = sum(1 for v in links.values() if v["gate"])
    print("built %d drafts, %d links (%d behind an ability)" % (len(drafts), len(links), gated))


if __name__ == "__main__":
    main()
