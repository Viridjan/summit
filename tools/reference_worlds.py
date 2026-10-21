# Rebuilds the four reference worlds (res://worlds/) from their map images, scaled so the player matches
# each game's character, then doubled (SCALE). Each world is cut into non-overlapping rectangular rooms along
# its natural walls (see partition), every room is made reachable (passages, door links), and objects are
# placed. Not navigable on purpose: shapes only, to be playtested and fixed in the editors.
#
# Usage: python3 -I tools/reference_worlds.py <maps_dir> worlds [world,world,...]   (default: all four)
# Map images are not in the repo; download them into <maps_dir> under these names:
#   hk_clean.png      https://cdn.wikimg.net/en/hkwiki/images/9/9c/Clean_map_updated.png (hollowknight.wiki)
#   ss_clean.png      https://cdn.wikimg.net/en/hkwiki/images/7/75/Silksong_Full_Map_Clean.png (hollowknight.wiki)
#   sotn_ingame.png   https://www.vgmaps.com/Atlas/PSX/Castlevania-SymphonyOfTheNight-Castles(In-GameMap).png
#   mzm_<Area>.png    https://www.vgmaps.com/Atlas/GBA/Metroid-ZeroMission-<Area>(In-GameMap).png
#                     for Area in Brinstar Crateria Kraid Norfair Ridley Tourian Chozodia
# Hollow Knight also uses (in <maps_dir>):
#   hn_z5.png         downloaded automatically from hallownest.net's tile server (real screenshots)
#   hk_annotations/   enemies/spikes/water/acid/breakables read off hallownest.net zoom-7 crops (see hk_features)
#   mapgenie_hk.json  https://mapgenie.io/api/v1/maps/725/data plus the page's category list
# Re-running overwrites every room in the rebuilt world folders (edits made in the editors are lost):
# pass the world names to rebuild only those, e.g. ... worlds hollow_knight
#
# Scale: our player's hitbox is 8x11 px = 1.375 tiles tall. Each game's world unit is converted so its
# character's height becomes 1.375 tiles:
#   Metroid Zero Mission: Samus standing hitbox = 2 blocks (mzm decomp, sSamusHitboxData); a map tile is one
#     15x10-block screen (minimap.c) -> 1 block = 0.6875 tiles, a screen = 10.3 x 6.9 tiles.
#   Symphony of the Night: Alucard collision = 47 px (sotn-decomp, g_SensorsCeilingDefault -22 to
#     g_SensorsFloorDefault +25); a map square = 256 px -> 7.5 x 7.5 tiles.
#   Hollow Knight: Knight ~1.3 units; Hallownest ~1200 units across ~4150 map px -> 0.31 tiles per map px.
#   Silksong: same map drawing scale assumed, Hornet ~1.6 units -> 0.25 tiles per map px (least certain).
import json, os, sys
from collections import deque
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
T = 8
MAX_ROOM = 400  # Game.MAX_LEVEL_SIZE: bigger regions are cut into pieces that meet edge to edge


# ---------------------------------------------------------------- shared output
SCALE = 2  # everything twice the character-matched size: the originals have many passages 1 tile tall at 1x


def partition(open_, comp, max_side=MAX_ROOM, min_side=24 * SCALE):
    """Non-overlapping room rectangles covering every open tile. A box is cut along the row/column with the least
    open space (natural rock lines) while it is too big, holds more than one separate region, or is mostly rock."""
    H, W = open_.shape
    leaves = []
    stack = [(0, 0, W, H)]
    while stack:
        bx0, by0, bx1, by1 = stack.pop()
        sub = open_[by0:by1, bx0:bx1]
        if not sub.any():
            continue
        rows, cols = np.nonzero(sub.any(axis=1))[0], np.nonzero(sub.any(axis=0))[0]
        # trim to the content plus one tile of the rock around it (floors!), never past this box
        x0, x1 = max(bx0, bx0 + cols[0] - 1), min(bx1, bx0 + cols[-1] + 2)
        y0, y1 = max(by0, by0 + rows[0] - 1), min(by1, by0 + rows[-1] + 2)
        sub = open_[y0:y1, x0:x1]
        w, h = x1 - x0, y1 - y0
        must = w > max_side or h > max_side
        lab = None if must else components(sub, 1)  # separate areas inside this box
        nlab = 0 if lab is None else int(lab.max()) + 1
        if nlab > 1:
            # bits clipped off a passage that runs past this box: rock here (a room never holds two separate areas)
            sizes = np.bincount(lab[lab >= 0])
            big = int(np.argmax(sizes))
            tiny = [i for i in range(nlab) if i != big and sizes[i] < 40 * SCALE * SCALE]
            if tiny and len(tiny) == nlab - 1:
                fill = np.isin(lab, tiny)
                open_[y0:y1, x0:x1][fill] = False
                stack.append((bx0, by0, bx1, by1))
                continue
        want = must or nlab > 1 or (sub.mean() < 0.15 and w * h > 4 * 40 * 23 * SCALE * SCALE)
        band = None
        # a band of solid rock a screen thick inside the box: cut through it whatever is left on either side,
        # or the room becomes two passages with a wall of nothing between them
        for axis, sums in (("x", sub.sum(axis=0)), ("y", sub.sum(axis=1))):
            run, gap, cum = 0, 12 * SCALE, np.cumsum(sums)
            for i, v in enumerate(sums):
                run = run + 1 if v == 0 else 0
                big = min(cum[i], cum[-1] - cum[i]) >= 30 * SCALE * SCALE  # no scraps
                if run >= gap and big and (band is None or run > band[0][0]):
                    band = ((run,), axis, i + 1 - run // 2)
        if band is not None:
            _, axis, c = band
            stack += [(x0, y0, x0 + c, y1), (x0 + c, y0, x1, y1)] if axis == "x" else [(x0, y0, x1, y0 + c), (x0, y0 + c, x1, y1)]
            continue
        if not want:
            leaves.append((int(x0), int(y0), int(x1), int(y1)))
            continue
        if nlab > 1:
            # cut between the areas: prefer a line no area crosses, then the fewest crossing, then least open space
            sel = lab >= 0
            ys_, xs_ = np.nonzero(sel)
            ls = lab[sel]
            best = None
            for axis, n, coord, sums in (("x", w, xs_, sub.sum(axis=0)), ("y", h, ys_, sub.sum(axis=1))):
                lo = np.full(nlab, n); hi = np.full(nlab, -1)
                np.minimum.at(lo, ls, coord); np.maximum.at(hi, ls, coord)
                for c in range(1, n):
                    cross = int(((lo < c) & (hi >= c)).sum())
                    if not ((hi < c).any() or cross) or not ((lo >= c).any() or cross):
                        continue
                    thin = c < min_side or n - c < min_side
                    score = (cross, thin, int(sums[c - 1]) + int(sums[c]) if c < n else 0, abs(c - n / 2) / n)
                    if best is None or score < best[0]:
                        best = (score, axis, c)
            if best is not None:
                _, axis, c = best
                stack += [(x0, y0, x0 + c, y1), (x0 + c, y0, x1, y1)] if axis == "x" else [(x0, y0, x1, y0 + c), (x0, y0 + c, x1, y1)]
                continue
        best = None
        for axis, n, sums in (("x", w, sub.sum(axis=0)), ("y", h, sub.sum(axis=1))):
            if n < 2 * min_side or (must and (w > max_side) != (axis == "x") and max(w, h) > max_side and (w > max_side) ^ (h > max_side)):
                continue
            cum = np.cumsum(sums)
            tot = int(cum[-1])
            min_open = 150 * SCALE * SCALE  # never cut off a scrap: each side keeps a real amount of space
            for c in range(min_side, n - min_side + 1):
                left = int(cum[c - 1])
                if not must and (0 < left < min_open or 0 < tot - left < min_open):
                    continue
                cost = int(sums[c - 1]) + int(sums[c]) if c < n else int(sums[c - 1])
                score = (cost, abs(c - n / 2) / n)
                if best is None or score < best[0]:
                    best = (score, axis, c)
        if best is None:
            leaves.append((int(x0), int(y0), int(x1), int(y1)))
            continue
        _, axis, c = best
        if axis == "x":
            stack += [(x0, y0, x0 + c, y1), (x0 + c, y0, x1, y1)]
        else:
            stack += [(x0, y0, x1, y0 + c), (x0, y0 + c, x1, y1)]
    kept = []
    for (x0, y0, x1, y1) in leaves:  # slivers a cut left behind: too small to stand in, become rock
        if open_[y0:y1, x0:x1].sum() < 10 * SCALE * SCALE:
            open_[y0:y1, x0:x1] = False
        else:
            kept.append((x0, y0, x1, y1))
    return kept


def _win(o):
    """Top-left corners of fully open 2x2 squares (the player fits there)."""
    return o[:-1, :-1] & o[1:, :-1] & o[:-1, 1:] & o[1:, 1:]


def _sh(a, dy, dx):
    """out[y, x] = a[y + dy, x + dx], False outside."""
    out = np.zeros_like(a)
    H, W = a.shape
    out[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)] = a[max(0, dy):H - max(0, -dy), max(0, dx):W - max(0, -dx)]
    return out


# window offset -> intermediate windows, one of which must exist for the two to be one passage
_JOINS = {(1, 1): [(0, 1), (1, 0)], (1, -1): [(0, -1), (1, 0)], (1, 2): [(0, 1), (1, 1)], (1, -2): [(0, -1), (1, -1)],
          (2, 1): [(1, 0), (1, 1)], (2, -1): [(1, 0), (1, -1)]}


def widen(solid, protect=None, iters=60):
    """Navigable = inside an open 2x2. Carves rock until every open tile is in an open 2x2 and 2x2 spots that touch
    only at a corner, or through a 1-tile-high gap, are joined. Never carves `protect` tiles or the map border."""
    solid = solid.copy()
    H, W = solid.shape
    block = np.zeros((H, W), bool) if protect is None else protect.copy()
    block[[0, -1], :] = True
    block[:, [0, -1]] = True
    for _ in range(iters):
        o = ~solid
        win = _win(o)
        s = solid.astype(np.int8)
        sb = (solid & block).astype(np.int8)
        cost = s[:-1, :-1] + s[1:, :-1] + s[:-1, 1:] + s[1:, 1:]
        cost[(sb[:-1, :-1] + sb[1:, :-1] + sb[:-1, 1:] + sb[1:, 1:]) > 0] = 99
        fat = np.zeros((H, W), bool)
        fat[:-1, :-1] |= win; fat[1:, :-1] |= win; fat[:-1, 1:] |= win; fat[1:, 1:] |= win
        todo = []
        for y, x in zip(*np.nonzero(o & ~fat)):
            todo.append([(y - 1, x - 1), (y - 1, x), (y, x - 1), (y, x)])
        if not todo:
            for (dy, dx), inter in _JOINS.items():
                m = win & _sh(win, dy, dx)
                for iy, ix in inter:
                    m &= ~_sh(win, iy, ix)
                for y, x in zip(*np.nonzero(m)):
                    todo.append([(y + iy, x + ix) for iy, ix in inter])
        changed = False
        for cands in todo:
            ok = [(int(cost[wy, wx]), wy, wx) for wy, wx in cands if 0 <= wy < H - 1 and 0 <= wx < W - 1]
            if not ok:
                continue
            c, wy, wx = min(ok)
            if 0 < c < 99 and solid[wy:wy + 2, wx:wx + 2].any():
                solid[wy:wy + 2, wx:wx + 2] = False
                cost[max(0, wy - 1):wy + 2, max(0, wx - 1):wx + 2] = np.minimum(cost[max(0, wy - 1):wy + 2, max(0, wx - 1):wx + 2], 98)
                changed = True
        if not changed:
            break
    return solid


def _protect(shape, extra):
    """Rock that objects rest on or sit in (spike supports, around liquids): widen() must not carve it."""
    H, W = shape
    p = np.zeros(shape, bool)
    sup = {"spikes_up": (1, 0), "spikes_down": (-1, 0), "spikes_left": (0, 1), "spikes_right": (0, -1)}
    for e in extra:
        x, y = int(e["x"]), int(e["y"])
        if e["t"] in sup:
            dy, dx = sup[e["t"]]
            if 0 <= y + dy < H and 0 <= x + dx < W:
                p[y + dy, x + dx] = True
        elif e["t"] in ("water", "acid"):
            p[max(0, y - 1):min(H, y + int(e["h"]) + 1), max(0, x - 1):min(W, x + int(e["w"]) + 1)] = True
    return p


def unblock_acid(open_, extra, links):
    """Acid kills, so a pool across the only way on cuts the map (in Hollow Knight those need Isma's Tear).
    Areas split only by acid get joined: smallest pools first become water, each with a note; big lakes stay."""
    H, W = open_.shape
    acid = np.zeros((H, W), bool)
    for e in extra:
        if e["t"] == "acid":
            acid[e["y"]:e["y"] + e["h"], e["x"]:e["x"] + e["w"]] = True
    if not acid.any():
        return extra
    lab = components(open_ & ~acid, 1)
    parent = {}

    def find(a):
        while parent.get(a, a) != a:
            a = parent[a]
        return a
    for ra, rb in links:
        la, lb = int(lab[ra[1], ra[0]]), int(lab[rb[1], rb[0]])
        if la >= 0 and lb >= 0:
            parent[find(la)] = find(lb)
    # touching acid boxes are one pool
    ys, xs = np.nonzero(acid)
    y0, y1, x0, x1 = ys.min() - 1, ys.max() + 2, xs.min() - 1, xs.max() + 2
    plab = np.full((H, W), -1, np.int32)
    plab[y0:y1, x0:x1] = components(acid[y0:y1, x0:x1], 1)
    pools = {}
    for i, e in enumerate(extra):
        if e["t"] == "acid":
            pools.setdefault(int(plab[e["y"], e["x"]]), []).append(i)
    sides = {}  # pool -> labels around it
    for pid in pools:
        py, px = np.nonzero(plab == pid)
        r = lab[max(0, py.min() - 1):py.max() + 2, max(0, px.min() - 1):px.max() + 2]
        sides[pid] = set(np.unique(r[r >= 0]).tolist())
    base = dict(parent)

    def joined(use):  # union-find over links + the given water pools
        parent.clear(); parent.update(base)
        for q in use:
            ls = [find(l) for l in sides[q]]
            for l in ls:
                parent[l] = ls[0]
    notes = []
    for pid in sorted(pools, key=lambda p: int((plab == p).sum())):  # smallest pools first
        m = plab == pid
        py, px = np.nonzero(m)
        ring = np.zeros((H, W), bool)
        ring[max(0, py.min() - 1):py.max() + 2, max(0, px.min() - 1):px.max() + 2] = True
        r = lab[ring]
        roots = {find(l) for l in np.unique(r[r >= 0]).tolist()}
        if len(roots) < 2:
            continue
        for l in roots:
            parent[l] = min(roots)
        for i in pools[pid]:
            extra[i] = dict(extra[i], t="water")
        e = extra[pools[pid][0]]
        notes.append({"t": "note", "x": e["x"] + e["w"] // 2, "y": e["y"], "w": 1, "h": 1,
                      "text": "Acid in the original (needs Isma's Tear). Water here so the way on stays open."})
    # put back acid where its sides connect another way anyway (largest pools first)
    water = [pid for pid in pools if extra[pools[pid][0]]["t"] == "water"]
    for pid in sorted(water, key=lambda p: -int((plab == p).sum())):
        rest = [q for q in water if q != pid]
        joined(rest)
        if len({find(l) for l in sides[pid]}) == 1:
            water = rest
            for i in pools[pid]:
                extra[i] = dict(extra[i], t="acid")
    keep = {(extra[pools[q][0]]["x"] + extra[pools[q][0]]["w"] // 2, extra[pools[q][0]]["y"]) for q in water}
    notes = [n for n in notes if (n["x"], n["y"]) in keep]
    print(f"  acid turned to water so nothing is cut off: {len(notes)} of {len(pools)} pools")
    return extra + notes


def drop_low_spikes(open_, extra, min_head=4, max_run=4):
    """Floor spikes under a ceiling too low to jump over them, in runs longer than a dash crosses, block the way: drop them."""
    low = {}
    for i, e in enumerate(extra):
        if e["t"] == "spikes_up":
            x, y = e["x"], e["y"]
            head = 0
            while head < min_head and y - 1 - head >= 0 and open_[y - 1 - head, x]:
                head += 1
            if head < min_head:
                low[(x, y)] = i
    drop = set()
    for (x, y), i in low.items():
        if (x - 1, y) in low:
            continue  # not the start of a run
        run = [i]
        while (x + len(run), y) in low:
            run.append(low[(x + len(run), y)])
        if len(run) > max_run:
            drop.update(run)
    print(f"  floor spikes under a low ceiling dropped: {len(drop)}")
    return [e for i, e in enumerate(extra) if i not in drop]


def _nearest(a_idx, b_idx, cap=1500):
    """Closest pair of tiles between two (N, 2) arrays of (y, x)."""
    rng = np.random.default_rng(0)
    if len(a_idx) > cap:
        a_idx = a_idx[rng.choice(len(a_idx), cap, replace=False)]
    if len(b_idx) > cap * 4:
        b_idx = b_idx[rng.choice(len(b_idx), cap * 4, replace=False)]
    best = (1e18, None, None)
    for i in range(0, len(a_idx), 256):
        A = a_idx[i:i + 256]
        d = ((A[:, None, :] - b_idx[None, :, :]) ** 2).sum(axis=2)
        k = np.unravel_index(np.argmin(d), d.shape)
        if d[k] < best[0]:
            best = (d[k], A[k[0]], b_idx[k[1]])
    return best[1], best[2]


def write_world(out, solid, title, start_near, notes=(), extra=(), thin_links=False, min_island=None):
    """solid: HxW bool rock map. Writes non-overlapping rectangular rooms (see partition), links them so every room
    is reachable (edge passages, doors across thin walls when thin_links, and a door pair from any cut-off group to
    the nearest reachable room), and places spawn, notes and extra objects ({"t", "x", "y", "w", "h"} in tiles)."""
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".json"):
            os.remove(os.path.join(out, f))
    H, W = solid.shape
    if min_island is None:
        min_island = 120 * SCALE * SCALE
    solid = widen(solid, _protect(solid.shape, extra))  # every passage at least 2x2
    comp = components(~solid, min_island)  # specks (mostly in-game map icons) become rock
    links = []  # (rect_a, rect_b) door pairs, rects (x0, y0, x1, y1) inclusive tiles
    if thin_links:
        # Regions facing each other across a thin wall at 2+ places are one map split by a line drawn on the source
        # map: open the wall along those contacts. A single contact becomes a door link.
        for _ in range(3):
            cands = thin_wall_doors(comp, 2 * SCALE, 12 * SCALE)
            pairs = {}
            for la, ra, lb, rb in cands:
                pairs.setdefault((min(la, lb), max(la, lb)), []).append((ra, rb))
            merged = False
            for key, cs in pairs.items():
                if len(cs) < 2:
                    continue
                merged = True
                for ra, rb in cs:
                    if ra[0] == ra[2] and rb[0] == rb[2] and ra[0] != rb[0]:  # vertical wall between columns
                        solid[ra[1]:ra[3] + 1, min(ra[0], rb[0]) + 1:max(ra[0], rb[0])] = False
                    else:  # horizontal wall between rows
                        solid[min(ra[1], rb[1]) + 1:max(ra[1], rb[1]), ra[0]:ra[2] + 1] = False
            comp = components(~solid, min_island)
            if not merged:
                break
        links = [(ra, rb) for (_, ra, _, rb) in thin_wall_doors(comp, 2 * SCALE, 12 * SCALE)]
    open_ = comp >= 0
    leaves = sorted(partition(open_, comp), key=lambda r: (r[1], r[0]))
    names = [f"r{i:03d}" for i in range(len(leaves))]
    owner = np.full((H, W), -1, np.int32)
    for i, (x0, y0, x1, y1) in enumerate(leaves):
        owner[y0:y1, x0:x1] = i
    links = [(ra, rb) for ra, rb in links if owner[ra[1], ra[0]] >= 0 and owner[rb[1], rb[0]] >= 0 and open_[ra[1], ra[0]] and open_[rb[1], rb[0]]]
    acid = np.zeros((H, W), bool)
    for e in extra:
        if e["t"] == "acid":
            acid[e["y"]:e["y"] + e["h"], e["x"]:e["x"] + e["w"]] = True
    extra = drop_low_spikes(open_, list(extra))
    for e in extra:  # doors keep a tile away from spikes: arriving next to them kills
        if e["t"].startswith("spikes_"):
            acid[max(0, e["y"] - 1):e["y"] + 2, max(0, e["x"] - 1):e["x"] + 2] = True
    links = [(ra, rb) for ra, rb in links if not acid[ra[1]:ra[3] + 1, ra[0]:ra[2] + 1].any() and not acid[rb[1]:rb[3] + 1, rb[0]:rb[2] + 1].any()]
    extra = unblock_acid(open_, extra, links)
    acid[:] = False
    for e in extra:
        if e["t"] == "acid":
            acid[e["y"]:e["y"] + e["h"], e["x"]:e["x"] + e["w"]] = True
    # room graph: open tiles of different rooms side by side = passage; plus door links
    parent = list(range(len(leaves)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def join(a, b):
        parent[find(a)] = find(b)
    for A, B, M in ((owner[:, :-1], owner[:, 1:], open_[:, :-1] & open_[:, 1:]), (owner[:-1], owner[1:], open_[:-1] & open_[1:])):
        sel = M & (A != B) & (A >= 0) & (B >= 0)
        for a, b in set(zip(A[sel].tolist(), B[sel].tolist())):
            join(a, b)
    for ra, rb in links:
        join(int(owner[ra[1], ra[0]]), int(owner[rb[1], rb[0]]))
    # spawn: open spot with ground under it, closest to start_near
    ok = open_[1:H - 1] & open_[0:H - 2] & ~open_[2:H]
    for ra, rb in links:
        for r in (ra, rb):
            ok[max(0, r[1] - 3):r[3] + 2, max(0, r[0] - 2):r[2] + 3] = False
    sy, sx = np.nonzero(ok)
    k = int(np.argmin((sx - start_near[0]) ** 2 + (sy + 1 - start_near[1]) ** 2))
    spawn = (int(sx[k]), int(sy[k]) + 1)
    start = int(owner[spawn[1], spawn[0]])
    # connect every cut-off group of rooms to the start's group with a door pair at their closest tiles
    room_tiles = {i: None for i in range(len(leaves))}
    for e in extra:
        if e["t"].startswith("spikes_"):
            acid[max(0, e["y"] - 1):e["y"] + 2, max(0, e["x"] - 1):e["x"] + 2] = True  # no door on or next to spikes
    stand = open_ & ~acid & np.vstack([np.zeros((1, W), bool), open_[:-1] & ~acid[:-1]])  # fits the player, not in acid
    while True:
        groups = {}
        for i in range(len(leaves)):
            groups.setdefault(find(i), []).append(i)
        main = find(start)
        others = [g for g in groups if g != main]
        if not others:
            break
        in_main = np.isin(owner, groups[main]) & stand
        bi = np.argwhere(in_main)
        g = max(others, key=lambda g: len(groups[g]))
        ai = np.argwhere(np.isin(owner, groups[g]) & stand)
        if len(ai) == 0 or len(bi) == 0:
            for i in groups[g]:
                parent[i] = main  # nowhere to stand: leave as is
            continue
        pa, pb = _nearest(ai, bi)
        links.append(((int(pa[1]), int(pa[0]) - 1, int(pa[1]), int(pa[0])), (int(pb[1]), int(pb[0]) - 1, int(pb[1]), int(pb[0]))))
        join(int(owner[pa[0], pa[1]]), main)
    ents = {i: [] for i in range(len(leaves))}

    def put(i, d):
        x0, y0 = leaves[i][0], leaves[i][1]
        d = dict(d)
        d["x"] = int((d["x"] - x0) * T)
        d["y"] = int((d["y"] - y0) * T)
        if "w" in d:
            d["w"], d["h"] = int(d["w"] * T), int(d["h"] * T)
        ents[i].append(d)
    for n, (ra, rb) in enumerate(links):
        ia, ib = int(owner[ra[1], ra[0]]), int(owner[rb[1], rb[0]])
        for (i, r, me, to) in ((ia, ra, f"d{2 * n}", f"{names[ib]}:d{2 * n + 1}"), (ib, rb, f"d{2 * n + 1}", f"{names[ia]}:d{2 * n}")):
            put(i, {"t": "door", "x": r[0], "y": r[1], "w": r[2] - r[0] + 1, "h": r[3] - r[1] + 1, "id": me, "to": to})
    put(start, {"t": "spawn", "x": spawn[0], "y": spawn[1]})
    for (nx_, ny_, text) in notes:
        if 0 <= ny_ < H and 0 <= nx_ < W and owner[ny_, nx_] >= 0:
            put(int(owner[ny_, nx_]), {"t": "note", "x": nx_, "y": ny_, "text": text})
    for e in extra:
        cx, cy = int(e["x"] + e["w"] / 2), int(e["y"] + e["h"] / 2)
        if not (0 <= cx < W and 0 <= cy < H) or not open_[cy, cx] or owner[cy, cx] < 0:
            continue
        i = int(owner[cy, cx])
        x0, y0, x1, y1 = leaves[i]
        d = dict(e)
        d["x"], d["y"] = max(x0, d["x"]), max(y0, d["y"])  # keep it inside its room
        d["w"], d["h"] = max(1, min(d["w"], x1 - d["x"])), max(1, min(d["h"], y1 - d["y"]))
        if d["t"].startswith("spikes_") or d["t"] == "note":
            d.pop("w"); d.pop("h")
        put(i, d)
    rooms = {}
    for i, (x0, y0, x1, y1) in enumerate(leaves):
        part = ~open_[y0:y1, x0:x1]
        lvl = {"name": f"{title} {names[i][1:]}", "w": int(x1 - x0), "h": int(y1 - y0),
               "tiles": ["".join("1" if v else "0" for v in row) for row in part], "entities": ents[i]}
        json.dump(lvl, open(os.path.join(out, names[i] + ".json"), "w"), separators=(",", ":"))
        rooms[names[i]] = [int(x0), int(y0)]
    json.dump({"start": names[start], "abilities": ["dash", "climb"], "rooms": rooms}, open(os.path.join(out, "world.json"), "w"), indent="\t")
    big = max(max(r[2] - r[0], r[3] - r[1]) for r in leaves)
    print(f"{title}: {W}x{H} tiles, {len(leaves)} rooms (largest side {big}), {len(links)} door links, start {names[start]}")


def components(open_mask, min_size):
    """4-connected regions of open tiles; regions smaller than min_size become rock (-1)."""
    H, W = open_mask.shape
    label = np.full((H, W), -1, np.int32)
    nxt = 0
    om = open_mask.tolist()
    lab = label.tolist()
    for y in range(H):
        for x in range(W):
            if om[y][x] and lab[y][x] < 0:
                cells = [(x, y)]
                lab[y][x] = nxt
                q = deque(cells)
                while q:
                    cx, cy = q.popleft()
                    for ax, ay in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= ax < W and 0 <= ay < H and om[ay][ax] and lab[ay][ax] < 0:
                            lab[ay][ax] = nxt
                            q.append((ax, ay))
                            cells.append((ax, ay))
                if len(cells) < min_size:
                    for cx, cy in cells:
                        lab[cy][cx] = -2
                else:
                    nxt += 1
    label = np.array(lab, np.int32)
    label[label == -2] = -1
    return label


# ---------------------------------------------------------------- Hollow Knight / Silksong
def hk_tiles(path, s):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    L = a.max(axis=2)
    openf = ((L >= 20) & (L < 95)).astype(np.int32)  # room fill (black = rock, bright = wall lines)
    wallf = (L >= 95).astype(np.int32)
    h, w = L.shape
    tw, th = int(w * s), int(h * s)
    xs = (np.arange(tw + 1) / s).astype(int)
    ys = (np.arange(th + 1) / s).astype(int)
    io = np.pad(openf.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    iw = np.pad(wallf.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    Y0, Y1 = ys[:-1][:, None], np.maximum(ys[1:], ys[:-1] + 1)[:, None]
    X0, X1 = xs[:-1][None, :], np.maximum(xs[1:], xs[:-1] + 1)[None, :]
    n = (Y1 - Y0) * (X1 - X0)
    o = io[Y1, X1] - io[Y0, X1] - io[Y1, X0] + io[Y0, X0]
    wl = iw[Y1, X1] - iw[Y0, X1] - iw[Y1, X0] + iw[Y0, X0]
    return ~((o * 2 >= n) & (wl * 3 < n))


def hk_areas(path, s, solid):
    """Area index per tile (-1 = rock): each area of the map has its own flat fill colour."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    L = a.max(axis=2)
    fill = (L >= 20) & (L < 95)
    q = (a // 6)
    key = (q[:, :, 0] * 64 + q[:, :, 1]) * 64 + q[:, :, 2]
    vals, counts = np.unique(key[fill], return_counts=True)
    palette = vals[counts > 10000]
    h, w = L.shape
    tw, th = solid.shape[1], solid.shape[0]
    xs = np.minimum((np.arange(tw) / s).astype(int), w - 1)
    ys = np.minimum((np.arange(th) / s).astype(int), h - 1)
    best = np.zeros((th, tw), np.int32)
    area = np.full((th, tw), -1, np.int32)
    for i, v in enumerate(palette):
        m = (fill & (key == v)).astype(np.int32)
        cnt = np.add.reduceat(np.add.reduceat(m, ys, axis=0), xs, axis=1)
        better = cnt > best
        best[better] = cnt[better]
        area[better] = i
    area[solid] = -1
    return area


def regions(area, min_size=800):
    """Connected tiles of the same area; scraps smaller than min_size join their most common neighbour."""
    H, W = area.shape
    ar = area.tolist()
    lab = [[-1] * W for _ in range(H)]
    sizes, cells_of = [], []
    for y in range(H):
        for x in range(W):
            if ar[y][x] >= 0 and lab[y][x] < 0:
                n = len(sizes)
                lab[y][x] = n
                q, cells = deque([(x, y)]), [(x, y)]
                while q:
                    cx, cy = q.popleft()
                    for ax, ay in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= ax < W and 0 <= ay < H and lab[ay][ax] < 0 and ar[ay][ax] == ar[cy][cx]:
                            lab[ay][ax] = n
                            q.append((ax, ay))
                            cells.append((ax, ay))
                sizes.append(len(cells))
                cells_of.append(cells)
    for n in sorted(range(len(sizes)), key=lambda i: sizes[i]):
        if sizes[n] >= min_size:
            break
        near = {}
        for cx, cy in cells_of[n]:
            for ax, ay in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if 0 <= ax < W and 0 <= ay < H and lab[ay][ax] >= 0 and lab[ay][ax] != n:
                    near[lab[ay][ax]] = near.get(lab[ay][ax], 0) + 1
        to = max(near, key=near.get) if near else (n if sizes[n] >= 40 else -1)
        for cx, cy in cells_of[n]:
            lab[cy][cx] = to
        if to >= 0 and to != n:
            sizes[to] += sizes[n]
            cells_of[to] += cells_of[n]
    label = np.array(lab, np.int32)
    _, inv = np.unique(label, return_inverse=True)  # renumber 0.. (keeping -1)
    out = inv.reshape(label.shape).astype(np.int32) - (1 if (label < 0).any() else 0)
    return out


def thin_wall_doors(label, max_wall=2, max_run=12):
    """Regions facing each other across a wall of 1..max_wall tiles become door pairs, one per contact run
    (runs longer than max_run are parallel corridors, not passages, and are skipped)."""
    H, W = label.shape
    contacts = {}  # (la, lb, axis, k, fixed coord) -> list of positions along the run
    for k in range(0, max_wall + 1):
        # horizontal: open a at x, wall x+1..x+k, open b at x+k+1
        a, b = label[:, :W - k - 1], label[:, k + 1:]
        wall = np.ones_like(a, bool)
        for j in range(1, k + 1):
            wall &= label[:, j:W - k - 1 + j] < 0
        ys, xs = np.nonzero((a >= 0) & (b >= 0) & (a != b) & wall)
        for y, x in zip(ys, xs):
            contacts.setdefault((int(a[y, x]), int(b[y, x]), "h", k, int(x)), []).append(int(y))
        a, b = label[:H - k - 1, :], label[k + 1:, :]
        wall = np.ones_like(a, bool)
        for j in range(1, k + 1):
            wall &= label[j:H - k - 1 + j, :] < 0
        ys, xs = np.nonzero((a >= 0) & (b >= 0) & (a != b) & wall)
        for y, x in zip(ys, xs):
            contacts.setdefault((int(a[y, x]), int(b[y, x]), "v", k, int(y)), []).append(int(x))
    doors, seen = [], set()
    for (la, lb, axis, k, c), pos in contacts.items():
        pos.sort()
        runs, start = [], pos[0]
        for p0, p1 in zip(pos, pos[1:] + [None]):
            if p1 != p0 + 1:
                runs.append((start, p0))
                start = p1
        if k == 0:  # areas touching directly: one door per 12 tiles of their border, however long
            runs = [(a0, min(a0 + max_run - 1, r1)) for r0, r1 in runs for a0 in range(r0, r1 + 1, max_run)]
        for r0, r1 in runs:
            if r1 - r0 + 1 < 2 or (k > 0 and r1 - r0 + 1 > max_run):
                continue
            key = (min(la, lb), max(la, lb), axis, r0 // 6)
            if key in seen:
                continue
            seen.add(key)
            if axis == "h":
                doors.append((la, (c, r0, c, r1), lb, (c + k + 1, r0, c + k + 1, r1)))
            else:
                doors.append((la, (r0, c, r1, c), lb, (r0, c + k + 1, r1, c + k + 1)))
    return doors


# ---------------------------------------------------------------- Hollow Knight from the real stitched map
# hallownest.net (TheEmbracedOne's map of in-game screenshots, tiles hosted at lorthiz.github.io/MapRealm-HollowKnight):
# foreground rock is pure black there, everything coloured is open space or background art. The in-game map
# (hk_clean.png) says which open space belongs to a room: each of its areas is registered onto the real map
# separately (the in-game map is stylised, areas sit a few screens off), and only open space inside a
# registered area is kept. That drops background vistas and the in-game map's glow halos.
HN_TILES = "https://lorthiz.github.io/MapRealm-HollowKnight/0/{z}/{y}/{x}.webp"
HN_Z5_ROW0 = 4            # the z5 mosaic starts at tile row 4 (rows above are empty)
HK_Z8_PER_TILE = 50.0 / SCALE  # real-map px (zoom 8) per tile: Knight ~1.3 units, ~60 px per unit at zoom 8


def hn_mosaic(maps, z=5, rows=(4, 28), cols=(0, 32)):
    """Downloads (once) and stitches a zoom level of hallownest.net into maps/hn_z<z>.png."""
    import urllib.request
    from concurrent.futures import ThreadPoolExecutor
    out = os.path.join(maps, f"hn_z{z}.png")
    if os.path.exists(out):
        return out
    cache = os.path.join(maps, f"hn_z{z}")
    os.makedirs(cache, exist_ok=True)

    def get(yx):
        y, x = yx
        p = os.path.join(cache, f"{y}_{x}.webp")
        if not os.path.exists(p):
            try:
                req = urllib.request.Request(HN_TILES.format(z=z, y=y, x=x), headers={"User-Agent": "Mozilla/5.0"})
                open(p, "wb").write(urllib.request.urlopen(req, timeout=30).read())
            except Exception:
                return None
        return p
    jobs = [(y, x) for y in range(*rows) for x in range(*cols)]
    with ThreadPoolExecutor(16) as ex:
        paths = list(ex.map(get, jobs))
    m = Image.new("RGB", ((cols[1] - cols[0]) * 256, (rows[1] - rows[0]) * 256))
    for (y, x), p in zip(jobs, paths):
        if p:
            try:
                m.paste(Image.open(p).convert("RGB"), ((x - cols[0]) * 256, (y - rows[0]) * 256))
            except Exception:
                pass
    m.save(out)
    return out


def hk_real(maps):
    """Returns (solid, label) on a tile grid laid over the real map, plus the tile -> z5 px factor."""
    real = np.asarray(Image.open(hn_mosaic(maps)).convert("RGB")).max(axis=2)
    f = HK_Z8_PER_TILE / 8  # z5 px per tile
    th, tw = int(real.shape[0] / f), int(real.shape[1] / f)
    ys = (np.arange(th + 1) * f).astype(int)
    xs = (np.arange(tw + 1) * f).astype(int)
    lit = (real > 3).astype(np.int32)  # foreground rock is 0 (webp noise up to ~3)
    cnt = np.add.reduceat(np.add.reduceat(lit, ys[:-1], axis=0), xs[:-1], axis=1)
    area = np.outer(np.diff(ys), np.diff(xs))
    ro = cnt * 2 >= area  # open on the real map
    # in-game map areas, on their own tile grid (0.31 tiles per map px)
    s = 0.31
    sol = hk_tiles(os.path.join(maps, "hk_clean.png"), s)
    lab_s = regions(hk_areas(os.path.join(maps, "hk_clean.png"), s, sol))
    # global fit, in-game map px -> real z5 mosaic px (found by aligning the two masks): real = k * sch + o
    kx, ky, ox, oy = 1.9995, 1.9552, -691.1, 259.2
    ty, tx = np.mgrid[0:th, 0:tw]
    sx_ = (((tx + 0.5) * f - ox) / kx * s).astype(int)
    sy_ = (((ty + 0.5) * f - oy) / ky * s).astype(int)
    inside = (sx_ >= 0) & (sy_ >= 0) & (sx_ < lab_s.shape[1]) & (sy_ < lab_s.shape[0])
    lg = np.full((th, tw), -1, np.int32)
    lg[inside] = lab_s[sy_[inside], sx_[inside]]
    # register each area on its own: shift (up to 12 tiles) to best cover open real-map tiles
    label = np.full((th, tw), -1, np.int32)
    score_at = np.full((th, tw), -1e9)
    shifts = {}  # in-game-map area -> (dy, dx) tiles
    R = 12 * SCALE
    for L in np.unique(lg[lg >= 0]):
        yy, xx = np.nonzero(lg == L)
        best, bd = -1e9, (0, 0)
        for dy in range(-R, R + 1, 2 * SCALE):
            for dx in range(-R, R + 1, 2 * SCALE):
                y2, x2 = yy + dy, xx + dx
                ok = (y2 >= 0) & (x2 >= 0) & (y2 < th) & (x2 < tw)
                hit = ro[y2[ok], x2[ok]]
                sc = hit.sum() - 0.6 * (~hit).sum()
                if sc > best:
                    best, bd = sc, (dy, dx)
        shifts[int(L)] = bd
        y2, x2 = yy + bd[0], xx + bd[1]
        ok = (y2 >= 0) & (x2 >= 0) & (y2 < th) & (x2 < tw)
        y2, x2 = y2[ok], x2[ok]
        better = score_at[y2, x2] < best
        label[y2[better], x2[better]] = L
        score_at[y2[better], x2[better]] = best
    reg = label.copy()  # registered in-game-map shapes, before growing
    # grow areas by 4 tiles so rooms drawn slightly off on the in-game map still keep their real open edge
    for _ in range(4 * SCALE):
        g = label.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.full_like(label, -1)
            sh[max(dy, 0):th + min(dy, 0), max(dx, 0):tw + min(dx, 0)] = label[max(-dy, 0):th + min(-dy, 0), max(-dx, 0):tw + min(-dx, 0)]
            g = np.where((g < 0) & (sh >= 0), sh, g)
        label = g
    label[~ro] = -1
    # The Abyss (and other unlit rooms deep down) is nearly black even in the screenshots: where a registered
    # in-game-map area in the lower map has little real open space behind it, use its in-game-map shape instead.
    # Upper dark areas are the in-game map's glow halos (background) and stay out.
    for L, (dy, dx) in shifts.items():
        m = reg == L
        if m.sum() < 50 * SCALE * SCALE:
            continue
        cy_sch = np.nonzero(lab_s == L)[0].mean() / s
        if ro[m].mean() < 0.35 and cy_sch > 2000:
            label[m & (label < 0)] = L
    # drop specks: regions of the same label smaller than 30 tiles
    label = regions(label, 20 * SCALE * SCALE)

    def to_tile(px, py):
        """In-game map (hk_clean) pixel -> tile, including that area's registration shift."""
        tx, ty = ((kx * px + ox) / f, (ky * py + oy) / f)
        sx, sy = int(px * s), int(py * s)
        best = None
        for r in range(0, 6):  # nearest in-game-map area around the point (in-game map tiles)
            win = lab_s[max(0, sy - r):sy + r + 1, max(0, sx - r):sx + r + 1]
            vals = win[win >= 0]
            if vals.size:
                best = int(np.bincount(vals).argmax())
                break
        dy, dx = shifts.get(best, (0, 0)) if best is not None else (0, 0)
        return tx + dx, ty + dy
    return label < 0, label, f, to_tile


# ---------------------------------------------------------------- Hollow Knight objects
# Two sources, both in <maps_dir>:
#   hk_annotations/out_*.json : boxes read off hallownest.net zoom-7 crops (1024 px, file c_<x>_<y>.jpg = crop origin
#                               in zoom-7 px), types enemy / spikes / water / acid / breakable. Read visually, so names
#                               are partly guesses and small things can be missed.
#   mapgenie_hk.json          : https://mapgenie.io/api/v1/maps/725/data (exact markers: bosses, one per enemy
#                               species, breakable surfaces, geo deposits, grubs, benches, stags...)
MG_Z, MG_TX0, MG_TY0 = 12, 2034, 2035                      # Map Genie mosaic used for the fit (zoom, first tile)
MG_TO_SCH = (2.1152, 2.12167, -914.71, -1250.49)            # mosaic px -> in-game map px: k * p + o


def hk_features(maps, solid, f, to_tile):
    import glob, math
    H, W = solid.shape
    out = []

    def open_at(x, y):
        return 0 <= x < W and 0 <= y < H and not solid[y, x]

    def snap(x, y, r=8 * SCALE, ground=False):
        """Nearest open tile (with ground under it when asked) to (x, y)."""
        x, y = int(round(x)), int(round(y))
        for d in range(r + 1):
            best = None
            for yy in range(y - d, y + d + 1):
                for xx in range(x - d, x + d + 1):
                    if max(abs(xx - x), abs(yy - y)) != d or not open_at(xx, yy):
                        continue
                    if ground and open_at(xx, yy + 1) and d < r:
                        continue
                    best = (xx, yy)
                    break
                if best:
                    return best
        return None
    # 1) annotations
    for fn in sorted(glob.glob(os.path.join(maps, "hk_annotations", "out_*.json"))):
        for crop, items in json.load(open(fn)).items():
            ox, oy = (int(v) for v in crop[2:-4].split("_"))
            for it in items:
                x0 = (ox + it["x0"]) / 4 / f; x1 = (ox + it["x1"]) / 4 / f
                y0 = ((oy + it["y0"]) / 4 - HN_Z5_ROW0 * 256) / f; y1 = ((oy + it["y1"]) / 4 - HN_Z5_ROW0 * 256) / f
                t, name = it.get("type", ""), str(it.get("name", ""))[:60]
                if t == "spikes":
                    dr = it.get("dir", "up")
                    if dr not in ("up", "down", "left", "right"):
                        dr = "up"
                    if dr in ("up", "down"):
                        for x in range(int(x0), int(math.ceil(x1))):
                            ys = range(int(y1) + 1, int(y0) - 2, -1) if dr == "up" else range(int(y0) - 1, int(y1) + 2)
                            for y in ys:  # floor (up) or ceiling (down) inside/next to the box
                                if open_at(x, y) and not open_at(x, y + (1 if dr == "up" else -1)):
                                    out.append({"t": "spikes_" + dr, "x": x, "y": y, "w": 1, "h": 1, "src": "map"})
                                    break
                    else:
                        for y in range(int(y0), int(math.ceil(y1))):
                            xs = range(int(x1) + 1, int(x0) - 2, -1) if dr == "left" else range(int(x0) - 1, int(x1) + 2)
                            for x in xs:  # wall to the right (spikes point left) or to the left
                                if open_at(x, y) and not open_at(x + (1 if dr == "left" else -1), y):
                                    out.append({"t": "spikes_" + dr, "x": x, "y": y, "w": 1, "h": 1, "src": "map"})
                                    break
                elif t in ("water", "acid"):
                    # trim to the open tiles inside the box, then let it settle onto the floor below
                    bx0, by0 = max(0, int(round(x0))), max(0, int(round(y0)))
                    bx1, by1 = min(W, max(bx0 + 1, int(round(x1)))), min(H, max(by0 + 1, int(round(y1))))
                    sub = ~solid[by0:by1, bx0:bx1]
                    if not sub.any():
                        continue
                    cols, rows = np.nonzero(sub.any(axis=0))[0], np.nonzero(sub.any(axis=1))[0]
                    lx0, lx1, ly0, ly1 = bx0 + cols[0], bx0 + cols[-1] + 1, by0 + rows[0], by0 + rows[-1] + 1
                    for _ in range(3 * SCALE):
                        if ly1 < H and (~solid[ly1, lx0:lx1]).mean() > 0.5:
                            ly1 += 1
                    out.append({"t": t, "x": int(lx0), "y": int(ly0), "w": int(lx1 - lx0), "h": int(ly1 - ly0), "src": "map"})
                elif t in ("enemy", "breakable"):
                    c = snap((x0 + x1) / 2, (y0 + y1) / 2, 4 * SCALE)
                    if c:
                        w_, h_ = max(1, int(round(x1 - x0))), max(1, int(round(y1 - y0)))
                        out.append({"t": t, "x": c[0] - w_ // 2, "y": c[1] - h_ + 1, "w": w_, "h": h_, "text": name, "src": "map"})
    # 2) Map Genie markers
    kinds = {"Boss": ("enemy", "Boss: {}"), "Journal Entry": ("enemy", "{}"), "Breakable Surface": ("breakable", "{}"),
             "Geo Deposit": ("breakable", "geo deposit"), "Captive Grub": ("breakable", "grub jar"),
             "Bench": ("note", "Bench"), "Stag Station": ("note", "Stag station: {}"), "Tram Station": ("note", "Tram: {}"),
             "Vendor": ("note", "Vendor: {}"), "Hot Spring": ("note", "Hot spring")}
    mg = json.load(open(os.path.join(maps, "mapgenie_hk.json")))
    cats = {}
    src = mg.get("categories") or {}
    for c in (src.values() if isinstance(src, dict) else src):
        cats[c["id"]] = c["title"]
    if not cats:  # categories live in the page data; fall back to titles stored on locations
        pass
    n = 256 * 2 ** MG_Z
    kx, ky, okx, oky = MG_TO_SCH
    mg_items = []
    for l in mg["locations"]:
        cat = cats.get(l["category_id"], "")
        if cat not in kinds:
            continue
        lat, lng = math.radians(float(l["latitude"])), float(l["longitude"])
        px = (lng + 180) / 360 * n - MG_TX0 * 256
        py = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n - MG_TY0 * 256
        tx, ty = to_tile(kx * px + okx, ky * py + oky)
        t, fmt = kinds[cat]
        c = snap(tx, ty, 10 * SCALE)
        if not c:
            continue
        text = fmt.format(l.get("title") or cat)[:60]
        if t == "note":
            mg_items.append({"t": "note", "x": c[0], "y": c[1], "w": 1, "h": 1, "text": text, "src": "mapgenie"})
        else:
            sz = 2 * SCALE if t == "enemy" else SCALE
            mg_items.append({"t": t, "x": c[0], "y": c[1] - sz + 1, "w": sz, "h": sz, "text": text, "src": "mapgenie"})
    # merge: a map-read box within 2 tiles of a Map Genie marker of the same type is the same thing
    keep = []
    for e in out:
        if e["t"] in ("enemy", "breakable") and any(m["t"] == e["t"] and abs(m["x"] - e["x"]) <= 2 * SCALE and abs(m["y"] - e["y"]) <= 2 * SCALE for m in mg_items):
            continue
        keep.append(e)
    allx = keep + mg_items
    for e in allx:
        e.pop("src", None)
    from collections import Counter
    print("  objects:", dict(Counter(e["t"] if not e["t"].startswith("spikes") else "spikes" for e in allx)))
    return allx


# ---------------------------------------------------------------- cell maps (Metroid, Symphony of the Night)
def cell_world(is_room, sides, sx, sy):
    """is_room: rows x cols bool. sides[(cx, cy, s)] in {'open', 'door', 'wall'} for s in l r t b.
    Each cell becomes a block of tiles (sx, sy tiles per cell, fractional ok). Rooms = cells joined by open sides.
    Walls are one tile thick inside the cell; a door is a gap in the wall with a door object on each side."""
    rows, cols = is_room.shape
    xr = [round(c * sx) for c in range(cols + 1)]
    yr = [round(r * sy) for r in range(rows + 1)]
    W, H = xr[-1], yr[-1]
    # rooms via union-find over open sides
    parent = {}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for cy in range(rows):
        for cx in range(cols):
            if is_room[cy, cx]:
                parent[(cx, cy)] = (cx, cy)
    for cy in range(rows):
        for cx in range(cols):
            if not is_room[cy, cx]:
                continue
            for s, (nx, ny) in (("r", (cx + 1, cy)), ("b", (cx, cy + 1))):
                if (nx, ny) in parent and sides[(cx, cy, s)] == "open":
                    parent[find((cx, cy))] = find((nx, ny))
    ids = {}
    label = np.full((H, W), -1, np.int32)
    for (cx, cy) in parent:
        L = ids.setdefault(find((cx, cy)), len(ids))
        label[yr[cy]:yr[cy + 1], xr[cx]:xr[cx + 1]] = L
    doors = []
    for (cx, cy) in parent:
        x0, x1, y0, y1 = xr[cx], xr[cx + 1] - 1, yr[cy], yr[cy + 1] - 1
        L = label[y0, x0]
        for s, (nx, ny) in (("l", (cx - 1, cy)), ("r", (cx + 1, cy)), ("t", (cx, cy - 1)), ("b", (cx, cy + 1))):
            k = sides[(cx, cy, s)]
            inside = (nx, ny) in parent
            if k == "open" and inside and find((nx, ny)) == find((cx, cy)):
                continue
            # wall on this side, SCALE tiles thick
            k_ = SCALE
            if s == "l": label[y0:y1 + 1, x0:x0 + k_] = -1
            if s == "r": label[y0:y1 + 1, x1 - k_ + 1:x1 + 1] = -1
            if s == "t": label[y0:y0 + k_, x0:x1 + 1] = -1
            if s == "b": label[y1 - k_ + 1:y1 + 1, x0:x1 + 1] = -1
            if k == "door" and inside and s in "rb":  # each door once, from its left/top cell
                nx0, nx1, ny0, ny1 = xr[nx], xr[nx + 1] - 1, yr[ny], yr[ny + 1] - 1
                Lb = label[(ny0 + ny1) // 2, (nx0 + nx1) // 2]
                if s == "r":  # gap 3*SCALE tiles tall just above the floor, through both walls
                    g0, g1 = max(y0 + k_, y1 - k_ - 3 * k_ + 1), y1 - k_
                    doors.append([L, (x1 - k_ + 1, g0, x1, g1), Lb, (nx0, g0, nx0 + k_ - 1, g1)])
                else:  # hole 3*SCALE tiles wide in the floor/ceiling
                    mid = (x0 + x1) // 2
                    h = 3 * k_ // 2
                    doors.append([L, (mid - h, y1 - k_ + 1, mid + h, y1), Lb, (mid - h, ny0, mid + h, ny0 + k_ - 1)])
    for la, ra, lb, rb in doors:  # carve the gaps after all walls are in
        label[ra[1]:ra[3] + 1, ra[0]:ra[2] + 1] = la
        label[rb[1]:rb[3] + 1, rb[0]:rb[2] + 1] = lb
    return label < 0, label, [tuple(d) for d in doors]


def mzm_cells(path):
    """In-game map: 8 px cells with borders at x%8, y%8 in {2, 3}; white = wall, coloured mark = door."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    H, W = a.shape[:2]
    white = a.min(axis=2) > 200
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    bg = ((r < 60) & (g < 60) & (b < 60)) | ((r < 20) & (g > 70) & (g < 110) & (b < 30))
    room = ~bg & ~white
    cols, rows = (W - 3) // 8, (H - 3) // 8
    plain = {(248, 248, 248), (0, 0, 248), (32, 192, 104), (32, 40, 32), (8, 88, 16)}
    is_room = np.zeros((rows, cols), bool)
    for cy in range(rows):
        for cx in range(cols):
            x0, y0 = 3 + cx * 8, 3 + cy * 8
            is_room[cy, cx] = room[y0 + 1:y0 + 7, x0 + 1:x0 + 7].sum() >= 18
    sides = {}
    for cy in range(rows):
        for cx in range(cols):
            x0, y0 = 3 + cx * 8, 3 + cy * 8
            for s in "lrtb":
                if s == "l": line, wl = a[y0 + 1:y0 + 7, x0], white[y0 + 1:y0 + 7, x0]
                elif s == "r": line, wl = a[y0 + 1:y0 + 7, x0 + 7], white[y0 + 1:y0 + 7, x0 + 7]
                elif s == "t": line, wl = a[y0, x0 + 1:x0 + 7], white[y0, x0 + 1:x0 + 7]
                else: line, wl = a[y0 + 7, x0 + 1:x0 + 7], white[y0 + 7, x0 + 1:x0 + 7]
                if any(tuple(int(v) for v in p) not in plain for p in line):
                    sides[(cx, cy, s)] = "door"
                elif wl.sum() >= 4:
                    sides[(cx, cy, s)] = "wall"
                else:
                    sides[(cx, cy, s)] = "open"
    # a door is only a door if both cells agree there is a link; otherwise trust the wall
    for (cx, cy, s), k in list(sides.items()):
        if s in "rb":
            o = (cx + 1, cy, "l") if s == "r" else (cx, cy + 1, "t")
            if o in sides and "door" in (k, sides[o]):
                sides[(cx, cy, s)] = sides[o] = "door"
    return is_room, sides


def sotn_cells(path, x_end):
    """vgmaps in-game map: cells ~21.73 x 20.11 px (fitted), borders at 9.25 + 21.73k, 14.75 + 20.11k.
    Blue/navy/red/water = room; white border = wall; a blue notch through the border = door."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)[:, :x_end]
    H, W = a.shape[:2]
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    white = a.min(axis=2) > 200
    roomc = ((b > 80) & (r < 120) & ~white) | ((r > 170) & (g < 90) & (b < 90)) | ((g > 170) & (b > 170) & (r < 120))
    PX, PY, OX, OY = 21.73, 20.11, 9.25, 14.75
    cols, rows = int((W - OX) / PX), int((H - OY) / PY)
    is_room = np.zeros((rows, cols), bool)
    for cy in range(rows):
        for cx in range(cols):
            x0, y0 = OX + cx * PX, OY + cy * PY
            blk = roomc[int(y0 + PY * 0.3):int(y0 + PY * 0.7), int(x0 + PX * 0.3):int(x0 + PX * 0.7)]
            is_room[cy, cx] = blk.mean() > 0.5
    is_room[:8, :19] = False   # legend box
    is_room[:6, :] = False     # titles
    sides = {}
    for cy in range(rows):
        for cx in range(cols):
            x0, y0 = OX + cx * PX, OY + cy * PY
            for s in "lrtb":
                if s in "lr":
                    x = int(round(x0 if s == "l" else x0 + PX))
                    strip_w = white[int(y0 + PY * 0.15):int(y0 + PY * 0.85), x - 2:x + 3]
                    strip_r = roomc[int(y0 + PY * 0.15):int(y0 + PY * 0.85), x - 2:x + 3]
                else:
                    y = int(round(y0 if s == "t" else y0 + PY))
                    strip_w = white[y - 2:y + 3, int(x0 + PX * 0.15):int(x0 + PX * 0.85)]
                    strip_r = roomc[y - 2:y + 3, int(x0 + PX * 0.15):int(x0 + PX * 0.85)]
                # across the border: fully room-coloured = same room; white with a room-coloured notch = door
                across = strip_r.all(axis=1 if s in "lr" else 0) if strip_r.size else np.array([False])
                if strip_w.mean() < 0.15:
                    sides[(cx, cy, s)] = "open"
                elif across.any():
                    sides[(cx, cy, s)] = "door"
                else:
                    sides[(cx, cy, s)] = "wall"
    for (cx, cy, s), k in list(sides.items()):
        if s in "rb":
            o = (cx + 1, cy, "l") if s == "r" else (cx, cy + 1, "t")
            if o in sides and k != sides[o]:
                sides[(cx, cy, s)] = sides[o] = "door" if "door" in (k, sides[o]) else "wall"
    return is_room, sides


# ---------------------------------------------------------------- build
def build(maps, out, only=None):
    """only: world folder names to rebuild (default all). Rebuilding a world overwrites edits made to it."""
    want = lambda name: only is None or name in only
    if want("hollow_knight"):
        build_hk(maps, out)
    if want("silksong"):
        build_ss(maps, out)
    if want("symphony_of_the_night"):
        build_sotn(maps, out)
    if want("metroid_zero_mission"):
        build_mzm(maps, out)
    # seal edge openings that lead nowhere, then a spawn near every room entrance (dying or Retry returns you there)
    import importlib.util
    spec = importlib.util.spec_from_file_location("world_fixups", os.path.join(os.path.dirname(os.path.abspath(__file__)), "world_fixups.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for name in ("hollow_knight", "silksong", "symphony_of_the_night", "metroid_zero_mission"):
        if want(name):
            mod.seal_edges(os.path.join(out, name))
            mod.add_spawns(os.path.join(out, name))


def build_hk(maps, out):
    # Hollow Knight: real terrain from hallownest.net, areas from the in-game map
    solid, label, f, to_tile = hk_real(maps)
    objects = hk_features(maps, solid, f, to_tile)
    objects += kings_pass(solid)
    sch = lambda x, y: (int((1.9995 * x - 691.1) / f), int((1.9552 * y + 259.2) / f))  # in-game map px -> tile
    write_world(os.path.join(out, "hollow_knight"), solid.copy(), "Hallownest",
                sch(1657, 580), [
        (*sch(1650, 540), "King's Pass (start)"), (*sch(1620, 660), "Dirtmouth above, Forgotten Crossroads below"),
        (*sch(2722, 1467), "City of Tears"), (*sch(710, 828), "Greenpath"), (*sch(3077, 2367), "The Abyss / Ancient Basin")], objects, thin_links=True)


def kings_pass(solid):
    """Hand fixes to the start area (world tiles), edits solid in place; returns objects to add.
    The top-right corridor ends in a breakable wall; behind it a tunnel slopes down into the cave that leads to Dirtmouth."""
    solid[475:478, 749:751] = False  # 1-tile pillar in the bottom tunnel
    solid[417:428, 872] = False  # corridor end wall -> breakable wall
    solid[417:428, 873:918] = False  # tunnel, then a 1-in-2 slope down into the cave
    for x in range(918, 964):
        top = 417 + (x - 918) // 2
        solid[top:top + 11, x] = False
    return [{"t": "breakwall", "x": 870, "y": 417, "w": 3, "h": 11}]


def build_ss(maps, out):
    s = 0.25 * SCALE
    solid = hk_tiles(os.path.join(maps, "ss_clean.png"), s)
    label = regions(hk_areas(os.path.join(maps, "ss_clean.png"), s, solid), 800 * SCALE * SCALE)  # drops glow halos
    write_world(os.path.join(out, "silksong"), label < 0, "Pharloom",
                (int(1150 * s), int(2960 * s)), [(int(1150 * s), int(2940 * s), "Moss Grotto (start, approximate)")], thin_links=True)


def build_sotn(maps, out):
    # Symphony of the Night: Dracula's Castle (left half of the image)
    is_room, sides = sotn_cells(os.path.join(maps, "sotn_ingame.png"), 1390)
    c = 7.5 * SCALE
    solid, label, doors = cell_world(is_room, sides, c, c)
    write_world(os.path.join(out, "symphony_of_the_night"), solid, "Dracula's Castle",
                (int((140 - 9.25) / 21.73 * c), int((910 - 14.75) / 20.11 * c)),
                [(int((150 - 9.25) / 21.73 * c), int((905 - 14.75) / 20.11 * c), "Entrance (start)")])


def build_mzm(maps, out):
    # Metroid Zero Mission: the 7 areas laid out like the official guide map (in the game they link by elevators)
    SX, SY = 15 * 0.6875 * SCALE, 10 * 0.6875 * SCALE
    layout = [["Crateria", "Chozodia"], ["Tourian", "Brinstar", "Norfair"], ["Kraid", "Ridley"]]
    areas = {a: mzm_cells(os.path.join(maps, f"mzm_{a}.png")) for row in layout for a in row}
    gap = 3  # cells between areas
    rows_h = [max(areas[a][0].shape[0] for a in row) for row in layout]
    width = max(sum(areas[a][0].shape[1] for a in row) + gap * (len(row) - 1) for row in layout)
    is_room = np.zeros((sum(rows_h) + gap * (len(layout) - 1), width), bool)
    sides, y, origin = {}, 0, {}
    for row, rh in zip(layout, rows_h):
        x = 0
        for a in row:
            ir, sd = areas[a]
            is_room[y:y + ir.shape[0], x:x + ir.shape[1]] = ir
            for (cx, cy, s_), k in sd.items():
                sides[(cx + x, cy + y, s_)] = k
            origin[a] = (x, y)
            x += ir.shape[1] + gap
        y += rh + gap
    for cy in range(is_room.shape[0]):
        for cx in range(is_room.shape[1]):
            for s_ in "lrtb":
                sides.setdefault((cx, cy, s_), "wall")
    solid, label, doors = cell_world(is_room, sides, SX, SY)
    notes = []
    for a, (ox, oy) in origin.items():
        ys, xs = np.nonzero(areas[a][0])
        cx, cy = ox + int(xs.min()), oy + int(ys[xs == xs.min()].min())
        notes.append((round(cx * SX) + 2 * SCALE, round((cy + 1) * SY) - 2 * SCALE, f"{a} (links to other areas by elevator in the original)"))
    bx, by = origin["Brinstar"]
    write_world(os.path.join(out, "metroid_zero_mission"), solid, "Zebes",
                (round((bx + 1) * SX), round((by + 15) * SY)), notes)


if __name__ == "__main__":
    # python3 -I tools/reference_worlds.py <maps_dir> worlds [hollow_knight,silksong,...]
    build(sys.argv[1], sys.argv[2], sys.argv[3].split(",") if len(sys.argv) > 3 else None)
