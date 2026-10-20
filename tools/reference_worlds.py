# Rebuilds the four reference worlds (res://worlds/) from their map images, scaled so the player matches
# each game's character. Rooms follow the originals (any size, true position, boxes may overlap where one
# of them is rock) and are linked by door objects. Not navigable on purpose: shapes only, to be
# playtested and fixed in the editors.
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
def write_world(out, solid, label, doors, title, start_near, notes=(), extra=()):
    """solid: HxW bool. label: HxW int, room id per open tile (-1 = rock).
    doors: [(room_a, rect_a, room_b, rect_b)] with rects (x0, y0, x1, y1) in tiles, inclusive; one link each way."""
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".json"):
            os.remove(os.path.join(out, f))
    H, W = solid.shape
    pieces = {}  # name -> (x0, y0, x1, y1, room label) in tiles, exclusive end
    owner = {}   # (label, piece index) helper
    by_label = {}
    ys, xs = np.nonzero(label >= 0)
    labs = label[ys, xs]
    order = np.argsort(labs)
    ys, xs, labs = ys[order], xs[order], labs[order]
    bounds = np.flatnonzero(np.diff(labs)) + 1
    for grp in np.split(np.arange(len(labs)), bounds):
        if len(grp) == 0:
            continue
        L = int(labs[grp[0]])
        x0, x1 = max(0, xs[grp].min() - 1), min(W, xs[grp].max() + 2)
        y0, y1 = max(0, ys[grp].min() - 1), min(H, ys[grp].max() + 2)
        nx, ny = -(-(x1 - x0) // MAX_ROOM), -(-(y1 - y0) // MAX_ROOM)
        by_label[L] = []
        for j in range(ny):
            for i in range(nx):
                px0 = x0 + (x1 - x0) * i // nx
                px1 = x0 + (x1 - x0) * (i + 1) // nx
                py0 = y0 + (y1 - y0) * j // ny
                py1 = y0 + (y1 - y0) * (j + 1) // ny
                if not (label[py0:py1, px0:px1] == L).any():
                    continue
                name = f"r{L:03d}" if nx * ny == 1 else f"r{L:03d}_{i}{j}"
                pieces[name] = (int(px0), int(py0), int(px1), int(py1), L)
                by_label[L].append(name)

    def piece_of(L, x, y):
        for name in by_label.get(L, []):
            px0, py0, px1, py1, _ = pieces[name]
            if px0 <= x < px1 and py0 <= y < py1:
                return name
        return None

    ents = {name: [] for name in pieces}
    n = 0
    for (la, ra, lb, rb) in doors:
        pa = piece_of(la, (ra[0] + ra[2]) // 2, (ra[1] + ra[3]) // 2)
        pb = piece_of(lb, (rb[0] + rb[2]) // 2, (rb[1] + rb[3]) // 2)
        if pa is None or pb is None:
            continue
        ia, ib = f"d{n}", f"d{n + 1}"
        n += 2
        for (p, r, i, to) in ((pa, ra, ia, f"{pb}:{ib}"), (pb, rb, ib, f"{pa}:{ia}")):
            r = [int(v) for v in r]
            px0, py0 = pieces[p][0], pieces[p][1]
            ents[p].append({"t": "door", "x": (r[0] - px0) * T, "y": (r[1] - py0) * T,
                            "w": (r[2] - r[0] + 1) * T, "h": (r[3] - r[1] + 1) * T, "id": i, "to": to})
    # spawn: open spot with ground under it, closest to start_near
    ok = ~solid[1:H - 1] & ~solid[0:H - 2] & solid[2:H]
    for (la, ra, lb, rb) in doors:  # never spawn in a doorway (it would warp the player at once)
        for r in (ra, rb):
            ok[max(0, r[1] - 3):r[3] + 2, max(0, r[0] - 2):r[2] + 3] = False
    sy, sx = np.nonzero(ok)
    k = int(np.argmin((sx - start_near[0]) ** 2 + (sy + 1 - start_near[1]) ** 2))
    spawn = (int(sx[k]), int(sy[k]) + 1)
    start = piece_of(int(label[spawn[1], spawn[0]]), *spawn)
    ents[start].append({"t": "spawn", "x": (spawn[0] - pieces[start][0]) * T, "y": (spawn[1] - pieces[start][1]) * T})
    for (nx_, ny_, text) in notes:
        for name, (px0, py0, px1, py1, L) in pieces.items():
            if px0 <= nx_ < px1 and py0 <= ny_ < py1 and (label[py0:py1, px0:px1] == L).any():
                ents[name].append({"t": "note", "x": (nx_ - px0) * T, "y": (ny_ - py0) * T, "text": text})
                break
    # extra: [{"t", "x", "y", "w", "h" (tiles, world grid), ...}] -> the room piece that owns the open tile at its centre
    for e in extra:
        cx, cy = int(e["x"] + e["w"] / 2), int(e["y"] + e["h"] / 2)
        cx, cy = min(max(cx, 0), W - 1), min(max(cy, 0), H - 1)
        L = int(label[cy, cx])
        if L < 0:
            continue
        p = piece_of(L, cx, cy)
        if p is None:
            continue
        px0, py0 = pieces[p][0], pieces[p][1]
        d = dict(e)
        d.update({"x": int((e["x"] - px0) * T), "y": int((e["y"] - py0) * T), "w": int(e["w"] * T), "h": int(e["h"] * T)})
        if d["t"].startswith("spikes_") or d["t"] == "note":
            d.pop("w"); d.pop("h")
        ents[p].append(d)
    rooms = {}
    for name, (px0, py0, px1, py1, L) in pieces.items():
        part = label[py0:py1, px0:px1] != L
        lvl = {"name": f"{title} {name[1:]}", "w": int(px1 - px0), "h": int(py1 - py0),
               "tiles": ["".join("1" if v else "0" for v in row) for row in part], "entities": ents[name]}
        json.dump(lvl, open(os.path.join(out, name + ".json"), "w"), separators=(",", ":"))
        rooms[name] = [int(px0), int(py0)]
    json.dump({"start": start, "abilities": ["dash", "climb"], "rooms": rooms}, open(os.path.join(out, "world.json"), "w"), indent="\t")
    sizes = sorted(((pieces[p][2] - pieces[p][0]) * (pieces[p][3] - pieces[p][1]) for p in pieces), reverse=True)
    print(f"{title}: {W}x{H} tiles, {len(pieces)} rooms (largest {sizes[:3]} tiles), {n} door ends, start {start}")


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
HK_Z8_PER_TILE = 50.0     # real-map px (zoom 8) per tile: Knight ~1.3 units, ~60 px per unit at zoom 8


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
    R = 12
    for L in np.unique(lg[lg >= 0]):
        yy, xx = np.nonzero(lg == L)
        best, bd = -1e9, (0, 0)
        for dy in range(-R, R + 1, 2):
            for dx in range(-R, R + 1, 2):
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
    for _ in range(4):
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
        if m.sum() < 50:
            continue
        cy_sch = np.nonzero(lab_s == L)[0].mean() / s
        if ro[m].mean() < 0.35 and cy_sch > 2000:
            label[m & (label < 0)] = L
    # drop specks: regions of the same label smaller than 30 tiles
    label = regions(label, 20)

    def to_tile(px, py):
        """In-game map (hk_clean) pixel -> tile, including that area's registration shift."""
        tx, ty = ((kx * px + ox) / f, (ky * py + oy) / f)
        sx, sy = int(px * s), int(py * s)
        best = None
        for r in range(0, 6):  # nearest in-game-map area around the point
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

    def snap(x, y, r=8, ground=False):
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
                    for _ in range(3):
                        if ly1 < H and (~solid[ly1, lx0:lx1]).mean() > 0.5:
                            ly1 += 1
                    out.append({"t": t, "x": int(lx0), "y": int(ly0), "w": int(lx1 - lx0), "h": int(ly1 - ly0), "src": "map"})
                elif t in ("enemy", "breakable"):
                    c = snap((x0 + x1) / 2, (y0 + y1) / 2, 4)
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
        c = snap(tx, ty, 10)
        if not c:
            continue
        text = fmt.format(l.get("title") or cat)[:60]
        if t == "note":
            mg_items.append({"t": "note", "x": c[0], "y": c[1], "w": 1, "h": 1, "text": text, "src": "mapgenie"})
        else:
            mg_items.append({"t": t, "x": c[0], "y": c[1] - 1, "w": 2 if t == "enemy" else 1, "h": 2 if t == "enemy" else 1, "text": text, "src": "mapgenie"})
    # merge: a map-read box within 2 tiles of a Map Genie marker of the same type is the same thing
    keep = []
    for e in out:
        if e["t"] in ("enemy", "breakable") and any(m["t"] == e["t"] and abs(m["x"] - e["x"]) <= 2 and abs(m["y"] - e["y"]) <= 2 for m in mg_items):
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
            # wall line on this side
            if s == "l": label[y0:y1 + 1, x0] = -1
            if s == "r": label[y0:y1 + 1, x1] = -1
            if s == "t": label[y0, x0:x1 + 1] = -1
            if s == "b": label[y1, x0:x1 + 1] = -1
            if k == "door" and inside and s in "rb":  # each door once, from its left/top cell
                nx0, nx1, ny0, ny1 = xr[nx], xr[nx + 1] - 1, yr[ny], yr[ny + 1] - 1
                Lb = label[(ny0 + ny1) // 2, (nx0 + nx1) // 2]
                if s == "r":  # 3 tiles tall gap just above the floor, in both walls
                    g0, g1 = max(y0 + 1, y1 - 3), y1 - 1
                    doors.append([L, (x1, g0, x1, g1), Lb, (nx0, g0, nx0, g1)])
                else:  # 3 tiles wide hole in the floor/ceiling
                    mid = (x0 + x1) // 2
                    doors.append([L, (mid - 1, y1, mid + 1, y1), Lb, (mid - 1, ny0, mid + 1, ny0)])
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


def build_hk(maps, out):
    # Hollow Knight: real terrain from hallownest.net, areas from the in-game map
    solid, label, f, to_tile = hk_real(maps)
    objects = hk_features(maps, solid, f, to_tile)
    sch = lambda x, y: (int((1.9995 * x - 691.1) / f), int((1.9552 * y + 259.2) / f))  # in-game map px -> tile
    write_world(os.path.join(out, "hollow_knight"), solid, label, thin_wall_doors(label), "Hallownest",
                sch(1657, 580), [
        (*sch(1650, 540), "King's Pass (start)"), (*sch(1620, 660), "Dirtmouth above, Forgotten Crossroads below"),
        (*sch(2722, 1467), "City of Tears"), (*sch(710, 828), "Greenpath"), (*sch(3077, 2367), "The Abyss / Ancient Basin")], objects)


def build_ss(maps, out):
    s = 0.25
    solid = hk_tiles(os.path.join(maps, "ss_clean.png"), s)
    label = regions(hk_areas(os.path.join(maps, "ss_clean.png"), s, solid))
    write_world(os.path.join(out, "silksong"), label < 0, label, thin_wall_doors(label), "Pharloom",
                (int(1150 * s), int(2960 * s)), [(int(1150 * s), int(2940 * s), "Moss Grotto (start, approximate)")])


def build_sotn(maps, out):
    # Symphony of the Night: Dracula's Castle (left half of the image)
    is_room, sides = sotn_cells(os.path.join(maps, "sotn_ingame.png"), 1390)
    solid, label, doors = cell_world(is_room, sides, 7.5, 7.5)
    write_world(os.path.join(out, "symphony_of_the_night"), solid, label, doors, "Dracula's Castle",
                (int((140 - 9.25) / 21.73 * 7.5), int((910 - 14.75) / 20.11 * 7.5)),
                [(int((150 - 9.25) / 21.73 * 7.5), int((905 - 14.75) / 20.11 * 7.5), "Entrance (start)")])


def build_mzm(maps, out):
    # Metroid Zero Mission: the 7 areas laid out like the official guide map (in the game they link by elevators)
    SX, SY = 15 * 0.6875, 10 * 0.6875
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
        notes.append((round(cx * SX) + 2, round((cy + 1) * SY) - 2, f"{a} (links to other areas by elevator in the original)"))
    bx, by = origin["Brinstar"]
    write_world(os.path.join(out, "metroid_zero_mission"), solid, label, doors, "Zebes",
                (round((bx + 1) * SX), round((by + 15) * SY)), notes)


if __name__ == "__main__":
    # python3 -I tools/reference_worlds.py <maps_dir> worlds [hollow_knight,silksong,...]
    build(sys.argv[1], sys.argv[2], sys.argv[3].split(",") if len(sys.argv) > 3 else None)
