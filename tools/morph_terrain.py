#!/usr/bin/env python3
"""Morph authored room contours using a terrain preset; preview unless --apply.

Presets: cavern, desert, coast, volcanic, forest and ruins. Seeded boundary
erosion preserves standing surfaces, room borders, thin walls and objects. See
docs/TERRAIN_MORPHING.md for usage, constraints and research references.
"""
import argparse
import copy
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile

VERSION = 1
CAVE_ENVIRONMENTS = {"cavern", "cavern_deep", "volcanic_cave"}
PRESETS = {
    "cavern": dict(label="Cavern",description="Irregular clustered rock recesses",select=CAVE_ENVIRONMENTS,
                   preserve=CAVE_ENVIRONMENTS,environment="cavern",width=(2,4),depth=1,gap=1,scale=7,fine=3,salt=0),
    "desert": dict(label="Desert",description="Broad shallow sandstone scallops",select={"sand"},
                   preserve={"sand"},environment="sand",width=(4,8),depth=1,gap=2,scale=14,fine=6,salt=101),
    "coast": dict(label="Coast",description="Scalloped cliff alcoves and overhangs",select={"sea","island_shore"},
                  preserve={"sea","island_shore"},environment="island_shore",width=(3,6),depth=2,gap=2,scale=10,fine=4,salt=211),
    "volcanic": dict(label="Volcanic",description="Narrow jagged basalt cuts",select={"volcano","volcanic_cave"},
                     preserve={"volcano","volcanic_cave"},environment="volcano",width=(2,3),depth=2,gap=1,scale=5,fine=2,salt=307),
    "forest": dict(label="Forest",description="Stepped root-like pockets in rock banks",select={"forest"},
                   preserve={"forest"},environment="forest",width=(3,5),depth=2,gap=2,scale=9,fine=3,salt=401),
    "ruins": dict(label="Ruins",description="Aligned rectangular masonry alcoves",select={"temple","building"},
                  preserve={"temple"},environment="temple",width=(4,4),depth=2,gap=4,scale=12,fine=6,salt=503),
}
INVISIBLE = {"camera_zone", "auto_walk"}
CARDINAL = ((0,1),(0,-1),(1,0),(-1,0))


def digest(value):
    return hashlib.sha256(value).hexdigest()


def tile_digest(rows):
    return digest("\n".join(rows).encode())


def validate(room):
    w,h = room.get("w"),room.get("h")
    rows = room.get("tiles")
    if type(w) is not int or type(h) is not int or w < 1 or h < 1:
        raise ValueError("Room dimensions must be positive whole numbers")
    if not isinstance(rows,list) or len(rows) != h or any(
        not isinstance(row,str) or len(row) != w or set(row)-set("01") for row in rows
    ):
        raise ValueError("Room tiles must be a w×h grid of 0/1 strings")
    if not isinstance(room.get("entities",[]),list):
        raise ValueError("Room entities must be a list")
    for e in room.get("entities",[]):
        if not isinstance(e,dict) or not isinstance(e.get("t"),str):
            raise ValueError("Every entity needs a type")
        for key in ("x","y","w","h"):
            value = e.get(key,8 if key in ("w","h") else None)
            if not isinstance(value,(int,float)) or not math.isfinite(value):
                raise ValueError("Entity coordinates and dimensions must be finite numbers")
            if key in ("w","h") and value <= 0:
                raise ValueError("Entity dimensions must be positive")


def protected_cells(room):
    """Keep all standing supports, border seams and entity neighborhoods fixed."""
    rows,w,h = room["tiles"],room["w"],room["h"]
    protected = {(x,y) for y in range(h) for x in range(w)
                 if x < 2 or y < 2 or x >= w-2 or y >= h-2}
    for y in range(2,h):
        for x in range(w):
            if rows[y][x] == "1" and rows[y-1][x] == rows[y-2][x] == "0":
                protected.add((x,y))
                if y+1 < h: protected.add((x,y+1))
    for e in room.get("entities",[]):
        if e["t"] in INVISIBLE: continue
        margin = 3 if e["t"] == "breakwall" or e["t"].startswith("boss_") else 2
        x0,y0 = math.floor(e["x"]/8)-margin,math.floor(e["y"]/8)-margin
        x1 = math.ceil((e["x"]+e.get("w",8))/8)+margin
        y1 = math.ceil((e["y"]+e.get("h",8))/8)+margin
        protected.update((x,y) for y in range(max(0,y0),min(h,y1))
                         for x in range(max(0,x0),min(w,x1)))
    return protected


def components(rows):
    labels = {}
    for y,row in enumerate(rows):
        for x,c in enumerate(row):
            if c != "0" or (x,y) in labels: continue
            label = len(labels)
            stack = [(x,y)]
            labels[x,y] = label
            while stack:
                cx,cy = stack.pop()
                for dx,dy in CARDINAL:
                    nx,ny = cx+dx,cy+dy
                    if 0 <= ny < len(rows) and 0 <= nx < len(row) and rows[ny][nx] == "0" and (nx,ny) not in labels:
                        labels[nx,ny] = label
                        stack.append((nx,ny))
    return labels


def preserves_components(rows, original):
    found = {}
    for cell,label in components(rows).items():
        if cell in original:
            previous = found.setdefault(label,original[cell])
            if previous != original[cell]: return False
    return True


def lattice(seed,x,y):
    key = f"{seed}:{x}:{y}".encode()
    return int.from_bytes(hashlib.blake2b(key,digest_size=8).digest(),"big") / (2**64-1)


def noise(seed,x,y,scale):
    x,y = x/scale,y/scale
    ix,iy = math.floor(x),math.floor(y)
    fx,fy = x-ix,y-iy
    fx,fy = fx*fx*(3-2*fx),fy*fy*(3-2*fy)
    a = lattice(seed,ix,iy)*(1-fx)+lattice(seed,ix+1,iy)*fx
    b = lattice(seed,ix,iy+1)*(1-fx)+lattice(seed,ix+1,iy+1)*fx
    return a*(1-fy)+b*fy


def contour_field(terrain,preset,seed,x,y):
    seed += preset["salt"]
    if terrain == "forest":
        x += (noise(seed+17,x,y,13)-0.5)*4
    value = 0.75*noise(seed,x,y,preset["scale"])+0.25*noise(seed+31,x,y,preset["fine"])
    if terrain == "volcanic": value = abs(2*value-1)
    return value


def brush_depth(terrain,index,width):
    if PRESETS[terrain]["depth"] == 1: return 1
    if terrain == "ruins": return 2
    if terrain == "coast": return 2 if 0 < index < width-1 else 1
    if terrain == "forest": return 2 if index % 3 == 1 else 1
    return 2 if index % 2 == 0 else 1


def carve_brush(rows,points,normal,terrain,protected,labels):
    """Keep two backing rock cells, even after a brush on the opposite face."""
    dx,dy = normal
    h,w = len(rows),len(rows[0])
    patch = set()
    for index,(x,y) in enumerate(points):
        depth = brush_depth(terrain,index,len(points))
        for k in range(depth+2):
            cell = (x-dx*k,y-dy*k)
            cx,cy = cell
            if not (0 <= cx < w and 0 <= cy < h) or rows[cy][cx] != "1": return
            if k < depth:
                if cell in protected: return
                patch.add(cell)
    if len(patch) < 2: return
    for x,y in patch: rows[y][x] = "0"
    if not preserves_components(rows,labels):
        for x,y in patch: rows[y][x] = "1"


def morph_room(room, terrain="cavern", seed=42, intensity=0.45, origin=(0,0)):
    if terrain not in PRESETS: raise ValueError("Unknown terrain preset: "+str(terrain))
    preset = PRESETS[terrain]
    if not math.isfinite(intensity) or not 0 <= intensity <= 1:
        raise ValueError("Intensity must be between 0 and 1")
    validate(room)
    result = copy.deepcopy(room)
    if intensity == 0 or room.get("arena") or any(e["t"].startswith("boss_") for e in room.get("entities",[])):
        return result
    identity = dict(version=VERSION,terrain=terrain,seed=seed,intensity=intensity,origin=list(origin))
    previous = room.get("terrain_morph",{})
    if all(previous.get(k) == v for k,v in identity.items()) and previous.get("result_tiles") == tile_digest(room["tiles"]):
        return result
    original = room["tiles"]
    rows = list(map(list,original))
    w,h = room["w"],room["h"]
    protected,labels = protected_cells(room),components(original)
    # The normal points from rock into air. Floors are retained; only roofs and
    # side walls get shallow recesses, with at least two solid backing cells.
    for dx,dy in ((0,1),(1,0),(-1,0)):
        lines = {}
        for y in range(2,h-2):
            for x in range(2,w-2):
                if (x,y) in protected or original[y][x] != "1": continue
                if original[y+dy][x+dx] != "0": continue
                if sum(original[y+ay][x+ax] == "0" for ax,ay in CARDINAL) != 1: continue
                if any(not (0 <= x-dx*k < w and 0 <= y-dy*k < h) or original[y-dy*k][x-dx*k] != "1" for k in (1,2)): continue
                gx,gy = x+origin[0],y+origin[1]
                value = contour_field(terrain,preset,seed,gx,gy)
                threshold = intensity*(0.85 if terrain == "coast" and dy else 1.0)
                if value > threshold: continue
                line,position = (y,x) if dy else (x,y)
                lines.setdefault(line,[]).append(position)
        for line,positions in sorted(lines.items()):
            positions.sort()
            runs = []
            for position in positions:
                if not runs or position != runs[-1][-1]+1: runs.append([])
                runs[-1].append(position)
            for run in runs:
                cursor = 0
                while len(run)-cursor >= 2:
                    if terrain == "ruins":
                        axis_origin = origin[0] if dy else origin[1]
                        cursor += (-(run[cursor]+axis_origin)) % 4
                        if len(run)-cursor < 4: break
                    low,high = preset["width"]
                    width = min(low+int(lattice(seed+preset["salt"],line,run[cursor])*(high-low+1)),len(run)-cursor)
                    patch = [(p,line) if dy else (line,p) for p in run[cursor:cursor+width]]
                    carve_brush(rows,patch,(dx,dy),terrain,protected,labels)
                    cursor += width+preset["gap"]
    result["tiles"] = ["".join(row) for row in rows]
    if result.get("environment") not in preset["preserve"]:
        result["environment"] = preset["environment"]
    if result != room:
        result["terrain_morph"] = dict(identity,result_tiles=tile_digest(result["tiles"]))
    return result


def room_path(world,name):
    if not isinstance(name,str) or not re.fullmatch(r"[A-Za-z0-9_-]+",name):
        raise ValueError(f"Invalid room identifier: {name!r}")
    path = world/(name+".json")
    if path.resolve().parent != world.resolve(): raise ValueError("Room file escapes the selected world")
    return path


def atomic_write(path,data):
    fd,name = tempfile.mkstemp(prefix=".morph-",dir=path.parent)
    try:
        with os.fdopen(fd,"wb") as f: f.write(data)
        if path.exists(): os.chmod(name,path.stat().st_mode & 0o777)
        os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)


def restore(world,backup):
    data = json.loads(backup.read_text())
    if data.get("version") != VERSION or data.get("world") != str(world.resolve()):
        raise ValueError("Backup belongs to another world or format")
    pending = []
    for item in data["rooms"]:
        path = room_path(world,item["room"])
        current,original = path.read_bytes(),item["before_text"].encode()
        if current == original: continue
        if digest(current) != item["after_sha256"]:
            raise ValueError(f"{item['room']} has later edits; restore refused")
        pending.append((path,current,original))
    commit_files(pending)
    print(f"Restored {len(pending)} room(s)")


def commit_files(pending):
    written = []
    try:
        for path,before,after in pending:
            atomic_write(path,after)
            written.append((path,before))
    except OSError:
        for path,before in reversed(written): atomic_write(path,before)
        raise


def svg(room, removed=()):
    w,h = room["w"]*8,room["h"]*8
    pieces = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="Room geometry"><rect width="{w}" height="{h}" fill="#182332"/>']
    for y,row in enumerate(room["tiles"]):
        for match in re.finditer("1+",row):
            pieces.append(f'<rect x="{match.start()*8}" y="{y*8}" width="{len(match[0])*8}" height="8" fill="#5d7180"/>')
    for x,y in removed:
        pieces.append(f'<rect x="{x*8}" y="{y*8}" width="8" height="8" fill="#e6a65d"/>')
    colors = {"water":"#5aa4c5","acid":"#ed8064","spawn":"#a9d578","jumpthru":"#e3c78e","breakwall":"#ab775d"}
    for e in room.get("entities",[]):
        if e["t"] in INVISIBLE: continue
        color = colors.get(e["t"],"#d18bae")
        pieces.append(f'<rect x="{e["x"]}" y="{e["y"]}" width="{e.get("w",8)}" height="{e.get("h",8)}" fill="{color}" opacity="0.85"><title>{html.escape(e["t"])}</title></rect>')
    return "".join(pieces)+"</svg>"


def write_report(output,plan):
    output.mkdir(parents=True,exist_ok=True)
    (output/"plan.json").write_text(json.dumps(plan,indent=2)+"\n")
    cards = []
    for item in plan["rooms"]:
        old,new = item["before"],item["after"]
        removed = [(x,y) for y,row in enumerate(old["tiles"]) for x,c in enumerate(row) if c != new["tiles"][y][x]]
        cards.append(f'<article><h2>{html.escape(item["room"])}</h2><p>{len(removed)} tiles · {html.escape(item["status"])}</p><div class="pair"><figure><figcaption>Before</figcaption>{svg(old)}</figure><figure><figcaption>After · orange marks carved rock</figcaption>{svg(new,removed)}</figure></div></article>')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Terrain morph</title><style>body{background:#182332;color:#eee;font:16px system-ui;max-width:1400px;margin:32px auto;padding:20px}p{line-height:1.5}article{margin:36px 0;border-top:1px solid #526673}svg{display:block;width:100%;min-width:240px;image-rendering:pixelated}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px}figure{margin:0}figcaption{padding:10px 0}a{color:#a9d578}@media(max-width:700px){.pair{grid-template-columns:1fr}}</style>'''
    page += '<h1>'+html.escape(PRESETS[plan["terrain"]]["label"])+' terrain morph</h1>'
    page += f'<p>{"Applied" if plan["applied"] else "Preview only"} · seed {plan["seed"]} · intensity {plan["intensity"]}. Floors, borders and entity neighborhoods are retained. These diagrams show geometry, not game artwork.</p><p><a href="plan.json">Full before/after data</a></p>'
    (output/"index.html").write_text(page+"".join(cards)+"</html>")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("world",type=Path,nargs="?",default=Path("worlds/story"))
    parser.add_argument("--terrain",choices=sorted(PRESETS),default="cavern")
    parser.add_argument("--list-terrains",action="store_true",help="List terrain presets without loading a world")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--region",action="append",help="Named area; repeat for multiple regions")
    selection.add_argument("--rooms",nargs="+",help="Explicit room IDs")
    parser.add_argument("--seed",type=int,default=42)
    parser.add_argument("--intensity",type=float,default=0.45)
    parser.add_argument("--output",type=Path,help="Report directory; default reports/terrain-morph/<terrain>")
    parser.add_argument("--apply",action="store_true",help="Write reviewed changes with an exact-byte backup")
    parser.add_argument("--restore",type=Path,help="Restore a backup, refusing to overwrite subsequent edits")
    args = parser.parse_args(argv)
    if args.list_terrains:
        for name,preset in PRESETS.items(): print(f"{name:10} {preset['description']}")
        return 0
    if args.output is None: args.output = Path("reports/terrain-morph")/args.terrain
    try:
        if args.restore:
            if args.apply: raise ValueError("Choose --restore or --apply, not both")
            restore(args.world,args.restore)
            return 0
        manifest = json.loads((args.world/"world.json").read_text())
        names = list(manifest["rooms"])
        if args.region:
            regions = {r["name"]:r["rooms"] for r in manifest.get("regions",[])}
            missing = set(args.region)-regions.keys()
            if missing: raise ValueError("Unknown region: "+", ".join(sorted(missing)))
            names = list(dict.fromkeys(n for r in args.region for n in regions[r]))
        elif args.rooms: names = list(dict.fromkeys(args.rooms))
        pending,items = [],[]
        for name in names:
            if name not in manifest["rooms"]: raise ValueError(f"Room is not in world manifest: {name}")
            path = room_path(args.world,name)
            raw = path.read_bytes()
            before = json.loads(raw)
            if not args.region and not args.rooms and before.get("environment") not in PRESETS[args.terrain]["select"]: continue
            after = morph_room(before,args.terrain,args.seed,args.intensity,manifest["rooms"][name])
            changed = before != after
            count = sum(a != b for ar,br in zip(before["tiles"],after["tiles"]) for a,b in zip(ar,br))
            items.append(dict(room=name,status="changed" if changed else "unchanged / protected",changed_tiles=count,before=before,after=after))
            if changed: pending.append((path,raw,(json.dumps(after,indent="\t")+"\n").encode()))
        if not items: raise ValueError("No rooms match the selected terrain or area")
        backup = args.output/"backup.json"
        if args.apply and pending:
            if backup.exists(): raise ValueError("This output already contains a backup; choose a new --output directory")
            args.output.mkdir(parents=True,exist_ok=True)
            saved = dict(version=VERSION,world=str(args.world.resolve()),rooms=[dict(room=p.stem,before_text=old.decode(),after_sha256=digest(new)) for p,old,new in pending])
            atomic_write(backup,(json.dumps(saved,indent=2)+"\n").encode())
            commit_files(pending)
        plan = dict(terrain=args.terrain,seed=args.seed,intensity=args.intensity,applied=args.apply,world=str(args.world.resolve()),rooms=items)
        write_report(args.output,plan)
        print(f"{'Applied' if args.apply else 'Previewed'} {len(pending)} changed / {len(items)} selected room(s): {args.output/'index.html'}")
        if args.apply and pending: print(f"Backup: {backup}")
        return 0
    except (OSError,ValueError,KeyError,TypeError) as exc:
        print(f"Terrain morph: {exc}",file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
