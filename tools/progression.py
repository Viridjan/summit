#!/usr/bin/env python3
"""Progression map: how the world opens up as abilities are collected.

    python3 tools/progression.py [world_dir] [out.html]     (defaults: worlds/story, reports/progression.html)

Each node is a set of abilities. From the start (no abilities) the movement models explore the world; every
ability pickup reachable the intended way is a choice, and taking it is a branch down to a new node. Top to
bottom = progress, left to right = choices. Branches carry the rooms they open.

Clicking a node shows the whole map, each place coloured by how it can be reached with those abilities:
  green  - normally (cautious model: what a normal player does)
  orange - with skill (generous model: precise jumps, long dashes, climb jumps)
  purple - not intended (exploit model: beyond what the game asks; a sign of a sequence break)
  red    - not at all
Breakable walls count as rock until the attack is owned. The models are approximations (tools/world_check.py).
"""
import json, os, sys
import multiprocessing
from concurrent.futures import ProcessPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_check import World, MODELS, explore, T

EXPLOIT = dict(MODELS["generous"], jump=5, hover=3, dash=6, dash_carry=4)
ABILITIES = ["dash", "climb", "attack"]  # Adventure.ABILITIES
TIERS = [("g", MODELS["cautious"]), ("o", MODELS["generous"]), ("p", EXPLOIT)]


def breakwalls(W):
    cells = set()
    for name, (ox, oy, lvl) in W.rooms.items():
        for e in lvl["entities"]:
            if e["t"] == "breakwall":
                for i in range(int(e["w"]) // T):
                    for j in range(int(e["h"]) // T):
                        cells.add((ox + int(e["x"]) // T + i, oy + int(e["y"]) // T + j))
    return cells


_W = None  # the world, shared with worker processes (fork)
_SOLID = None  # (rock, rock + breakable walls)


def _pool():
    return ProcessPoolExecutor(mp_context=multiprocessing.get_context("fork"))


def _survey_one(job):
    abilities, tier = job
    _W.solid = _SOLID[0] if "attack" in abilities else _SOLID[1]
    ground, touched = explore(_W, dict(TIERS)[tier], set(abilities), [_W.spawn])
    return ground, [k for k in touched if k.startswith("ability_")]


# Explore several ability sets under every model at once; per set: {cell: tier} (best tier wins), pickups per tier.
def survey_many(W, base_solid, walls, sets):
    global _W, _SOLID
    _W, _SOLID = W, (base_solid, base_solid | walls)
    jobs = [(sorted(ab), tier) for ab in sets for tier, _ in TIERS]
    with _pool() as pool:
        found = list(pool.map(_survey_one, jobs))
    out = {ab: ({}, {}) for ab in sets}
    for (ab, tier), (ground, keys) in zip(jobs, found):  # jobs are in tier order per set: best tier first
        cells, pickups = out[frozenset(ab)]
        for c in ground:
            cells.setdefault(c, tier)
        for k in keys:
            pickups.setdefault(k, tier)
    W.solid = base_solid
    return out


# Zones for one ability set: rooms you can go back and forth between (cautious model). From each room's spawn points
# we explore where you can get; two rooms are in one zone when each reaches the other. An arrow between zones is a
# way that doesn't lead back (a drop, a one-way door, a collapse): a zone with two arrows out is a choice.
def _from_entrance(job):  # one entrance (spawn point): the room's ground it reaches and where it steps out
    name, start, abilities, extra = job
    _W.solid = _W.solid | set(extra)  # a forked copy: the cave-in rock only in this search
    out = set()
    ground, _ = explore(_W, MODELS["cautious"], set(abilities), [start], room=name, exits=out)
    return ground, out


# Cave-ins (the Sand Cave chase's "seal"): {room: (seal world column, rock cells)}. Behind it there's no way back.
def seals(W):
    out = {}
    for name, (ox, oy, lvl) in W.rooms.items():
        for e in lvl["entities"]:
            if e["t"] == "ape_chase" and e.get("seal"):
                x, y, w, h = (int(v) for v in e["seal"])
                out[name] = (ox + x // T, {(ox + x // T + i, oy + y // T + j) for i in range(w // T) for j in range(h // T)})
    return out


# Zones for one ability set (cautious model). The nodes are a room's entrances (its spawn points): from each we
# search inside its room, which other entrances of the room it reaches, and where it steps into other rooms (that
# lands at the nearest entrance there). Entrances that reach each other form a zone; an arrow between zones is a
# way that doesn't lead back (a drop, a one-way door, a cave-in). A zone with two arrows out is a choice. Entrances
# behind a cave-in search with its rock down.
def zones(W, base_solid, walls, abilities):
    W.solid = base_solid if "attack" in abilities else base_solid | walls
    global _W
    _W = W
    cave = seals(W)
    ents = []  # (room, cell)
    for name, (ox, oy, lvl) in W.rooms.items():
        for e in lvl["entities"]:
            if e["t"] == "spawn":
                ents.append((name, (ox + int(e["x"]) // T, oy + int(e["y"]) // T)))
    if W.spawn not in [c for _, c in ents]:
        ents.append((W.room_of[W.spawn], W.spawn))
    jobs = [(n, c, sorted(abilities), sorted(cave[n][1]) if n in cave and c[0] >= cave[n][0] else []) for n, c in ents]
    with _pool() as pool:
        found = list(pool.map(_from_entrance, jobs))
    W.solid = base_solid
    by_room = {}
    for i, (n, c) in enumerate(ents):
        by_room.setdefault(n, []).append(i)
    step = [set() for _ in ents]
    for i, (ground, out) in enumerate(found):
        n = ents[i][0]
        for j in by_room[n]:
            cx, cy = ents[j][1]
            if j != i and any((cx + dx, cy + dy) in ground for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                step[i].add(j)
        for m, x, y in out:
            if m in by_room:
                step[i].add(min(by_room[m], key=lambda k: abs(ents[k][1][0] - x) + abs(ents[k][1][1] - y)))
    reach = []
    for i in range(len(ents)):
        seen, todo = {i}, [i]
        while todo:
            for j in step[todo.pop()]:
                if j not in seen:
                    seen.add(j)
                    todo.append(j)
        reach.append(seen)
    start = next(i for i, (n, c) in enumerate(ents) if c == W.spawn)
    from_start = reach[start]
    zone_of, zl = {}, []
    for i in sorted(from_start, key=lambda i: -len(reach[i])):
        if i in zone_of:
            continue
        z = sorted(j for j in from_start if j in reach[i] and i in reach[j])
        for j in z:
            zone_of[j] = len(zl)
        zl.append(z)
    ahead = [set().union(*(reach[j] for j in z)) & from_start for z in zl]
    kids = []
    for i in range(len(zl)):
        below = [j for j in range(len(zl)) if j != i and zl[j][0] in ahead[i]]
        kids.append([j for j in below if not any(k != j and zl[j][0] in ahead[k] for k in below)])  # direct only
    depth = [0] * len(zl)
    first = zone_of[start]
    stack = [first]
    while stack:  # longest path down from the start zone
        i = stack.pop()
        for j in kids[i]:
            if depth[j] < depth[i] + 1:
                depth[j] = depth[i] + 1
                stack.append(j)
    rooms_of_z = lambda z: sorted({ents[j][0] for j in z})
    return [dict(rooms=rooms_of_z(z), kids=kids[i], depth=depth[i], ahead=rooms_of_z(ahead[i])) for i, z in enumerate(zl)], first


def build(world_dir):
    W = World(world_dir)
    base, walls = set(W.solid), breakwalls(W)
    nodes, order = {}, []
    placed = {t[len("ability_"):] for items in W.items.values() for t, _, _ in items if t.startswith("ability_")}
    unplaced = [a for a in ABILITIES if a not in placed]  # no pickup in the world yet: dashed "what if" branches
    todo = [frozenset()]
    while todo:
        level = sorted({ab for ab in todo if ab not in nodes}, key=sorted)  # one level of the graph at a time, in parallel
        todo = []
        done = survey_many(W, base, walls, level)
        for ab in level:
            todo += _node(W, base, walls, ab, done[ab], nodes, order, unplaced)
    return W, nodes, order


def _node(W, base, walls, ab, survey_result, nodes, order, unplaced):
    if True:
        cells, pickups = survey_result
        rooms = {}
        for c, tier in cells.items():
            r = W.room_of.get(c)
            if r and (r not in rooms or "gop".index(tier) < "gop".index(rooms[r])):
                rooms[r] = tier
        choices = sorted({k.split(":")[0][len("ability_"):] for k, tier in pickups.items() if tier == "g"} - ab)
        skill = sorted({k.split(":")[0][len("ability_"):] for k, tier in pickups.items() if tier != "g"} - ab)
        zl, first = zones(W, base, walls, ab)
        nodes[ab] = dict(abilities=sorted(ab), rooms=rooms, cells=cells, choices=choices, skill=skill,
                         unplaced=[a for a in unplaced if a not in ab], zones=zl, first=first)
        order.append(ab)
        return [ab | {a} for a in choices + nodes[ab]["unplaced"]]


def page(W, nodes, order):
    room_list = []
    for name, (ox, oy, lvl) in W.rooms.items():
        room_list.append(dict(name=name, title=lvl.get("name", name), x=ox, y=oy, w=lvl["w"], h=lvl["h"], tiles=lvl["tiles"]))
    regions = {}
    try:
        for g in json.load(open(os.path.join(W.dir, "world.json"))).get("regions", []):
            for r in g["rooms"]:
                regions[r] = g["name"]
    except (OSError, ValueError):
        pass
    out_nodes = []
    for ab in order:
        n = nodes[ab]
        marks = {}  # room -> string of w*h chars: g/o/p for a reachable standing cell, "." otherwise
        for name, (ox, oy, lvl) in W.rooms.items():
            row = ["."] * (lvl["w"] * lvl["h"])
            for y in range(lvl["h"]):
                for x in range(lvl["w"]):
                    t = n["cells"].get((ox + x, oy + y))
                    if t:
                        row[y * lvl["w"] + x] = t
            marks[name] = "".join(row)
        parent_rooms = set()
        for prev in order:
            if prev < ab and len(prev) == len(ab) - 1:
                parent_rooms |= {r for r, t in nodes[prev]["rooms"].items() if t == "g"}
        opened = sorted(r for r, t in n["rooms"].items() if t == "g" and r not in parent_rooms) if ab else []
        out_nodes.append(dict(id="+".join(n["abilities"]) or "start", abilities=n["abilities"], depth=len(ab),
                              parents=["+".join(sorted(p)) or "start" for p in order if p < ab and len(p) == len(ab) - 1],
                              rooms=n["rooms"], marks=marks, choices=n["choices"], skill=n["skill"], opened=opened,
                              unplaced=n["unplaced"], zones=n["zones"], first=n["first"]))
    data = json.dumps(dict(rooms=room_list, regions=regions, nodes=out_nodes))
    return TEMPLATE.replace("/*DATA*/", data)


TEMPLATE = r"""<!doctype html><html><head><meta charset="utf-8"><title>Progression Map</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{--bg:#16161c;--fg:#e8e8ee;--dim:#8a8a99;--line:#555566;--card:#20202a;--g:#3fbf5f;--o:#f0a030;--p:#b060e0;--r:#c04040;--rock:#2c2c36}
body{margin:0;background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif}
main{display:grid;grid-template-columns:minmax(300px,2fr) 3fr;gap:16px;padding:16px}
@media (max-width:800px){main{grid-template-columns:1fr}}
h1{font-size:18px;margin:0 0 4px} p{color:var(--dim);margin:0 0 12px}
.card{background:var(--card);border-radius:8px;padding:12px;overflow:auto}
svg text{fill:var(--fg);font-size:12px} .node{cursor:pointer} .node rect{fill:#2a2a38;stroke:var(--line)}
.node.sel rect{stroke:var(--fg);stroke-width:2} .edge{stroke:var(--line);stroke-width:2;fill:none}
.legend span{display:inline-block;margin-right:12px} .sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px}
canvas{image-rendering:pixelated;width:100%;height:auto;background:#0d0d12;border-radius:4px}
#info{margin-top:8px;color:var(--dim)} #info b{color:var(--fg)}
</style></head><body><main>
<section class="card"><h1>Progression</h1><p>Top to bottom: progress. Left to right: choices. Click a node. Dashed: an ability with no pickup in the world yet.</p><svg id="graph"></svg></section>
<section class="card"><div class="legend"><span><i class="sw" style="background:var(--g)"></i>normal</span><span><i class="sw" style="background:var(--o)"></i>with skill</span><span><i class="sw" style="background:var(--p)"></i>not intended</span><span><i class="sw" style="background:var(--r)"></i>unreachable</span></div>
<canvas id="map"></canvas><div id="info"></div></section>
<section class="card"><h1>Choices</h1><p id="zhead">Zones: rooms you can go back and forth between. Arrows: ways that don't lead back. Two arrows out: a choice. Click a zone.</p><svg id="zgraph"></svg></section>
<section class="card"><div class="legend"><span><i class="sw" style="background:#5fa8ff"></i>this zone</span><span><i class="sw" style="background:var(--g)"></i>still ahead</span><span><i class="sw" style="background:var(--r)"></i>left behind (no way back)</span><span><i class="sw" style="background:#44444f"></i>not reached</span></div>
<canvas id="zmap"></canvas><div id="zinfo"></div></section></main>
<script>
const D=/*DATA*/;
const C={g:"#3fbf5f",o:"#f0a030",p:"#b060e0",r:"#c04040"};
const svg=document.getElementById("graph"),NS="http://www.w3.org/2000/svg";
const rows={};D.nodes.forEach(n=>(rows[n.depth]=rows[n.depth]||[]).push(n));
const W=120,H=34,GX=16,GY=56,pos={};let width=0;
Object.keys(rows).forEach(d=>{rows[d].forEach((n,i)=>{pos[n.id]=[12+i*(W+GX),12+d*(H+GY)];width=Math.max(width,24+(i+1)*(W+GX))})});
const height=24+Object.keys(rows).length*(H+GY);svg.setAttribute("width",width);svg.setAttribute("height",height);
function el(t,a,p){const e=document.createElementNS(NS,t);for(const k in a)e.setAttribute(k,a[k]);(p||svg).appendChild(e);return e}
D.nodes.forEach(n=>n.parents.forEach((pid,i)=>{const [px,py]=pos[pid],[x,y]=pos[n.id];
 const par=D.nodes.find(q=>q.id==pid),dashed=par&&n.abilities.some(a=>par.unplaced.includes(a)&&!par.abilities.includes(a));
 el("path",{class:"edge",style:dashed?"stroke-dasharray:4 4":"",d:`M${px+W/2},${py+H} C${px+W/2},${py+H+GY/2} ${x+W/2},${y-GY/2} ${x+W/2},${y}`});
 const gained=n.abilities.filter(a=>!pid.split("+").includes(a)).join(",");
 const t=el("text",{x:x+4,y:y-6-13*i,style:"font-size:11px;fill:var(--dim)"});t.textContent="+"+gained+(n.opened.length?" ("+n.opened.length+" rooms)":"")}));
const boxes={};
D.nodes.forEach(n=>{const [x,y]=pos[n.id];const g=el("g",{class:"node",transform:`translate(${x},${y})`});
 el("rect",{width:W,height:H,rx:6},g);const t=el("text",{x:8,y:15},g);t.textContent=n.id;
 const s=el("text",{x:8,y:28,style:"fill:var(--dim);font-size:11px"},g);const cnt=Object.values(n.rooms).filter(v=>v=="g").length;s.textContent=cnt+"/"+D.rooms.length+" rooms";
 g.onclick=()=>show(n);boxes[n.id]=g});
const cv=document.getElementById("map"),cx=cv.getContext("2d");
let minx=1e9,miny=1e9,maxx=-1e9,maxy=-1e9;D.rooms.forEach(r=>{minx=Math.min(minx,r.x);miny=Math.min(miny,r.y);maxx=Math.max(maxx,r.x+r.w);maxy=Math.max(maxy,r.y+r.h)});
const S=3;cv.width=(maxx-minx)*S;cv.height=(maxy-miny)*S;
function show(n){Object.values(boxes).forEach(b=>b.classList.remove("sel"));boxes[n.id].classList.add("sel");
 cx.clearRect(0,0,cv.width,cv.height);
 D.rooms.forEach(r=>{const tier=n.rooms[r.name]||"r",ox=(r.x-minx)*S,oy=(r.y-miny)*S,m=n.marks[r.name];
  cx.globalAlpha=0.28;cx.fillStyle=C[tier];cx.fillRect(ox,oy,r.w*S,r.h*S);cx.globalAlpha=1;
  for(let y=0;y<r.h;y++)for(let x=0;x<r.w;x++){if(r.tiles[y][x]=="1"){cx.fillStyle="#2c2c36";cx.fillRect(ox+x*S,oy+y*S,S,S)}
   const k=m[y*r.w+x];if(k!="."){cx.fillStyle=C[k];cx.fillRect(ox+x*S,oy+y*S,S,S)}}
  cx.strokeStyle=C[tier];cx.lineWidth=1;cx.strokeRect(ox+.5,oy+.5,r.w*S-1,r.h*S-1)});
 const by={g:[],o:[],p:[],r:[]};D.rooms.forEach(r=>by[n.rooms[r.name]||"r"].push(r.title));
 document.getElementById("info").innerHTML=`<b>${n.id}</b> &middot; choices here: ${n.choices.join(", ")||"none"}${n.skill.length?" &middot; only with skill: "+n.skill.join(", "):""}<br>`+
  ["o","p","r"].map(k=>by[k].length?`<span style="color:${C[k]}">${{o:"with skill",p:"not intended",r:"unreachable"}[k]}:</span> ${by[k].join(", ")}`:"").filter(Boolean).join("<br>")}
const zsvg=document.getElementById("zgraph"),zcv=document.getElementById("zmap"),zcx=zcv.getContext("2d");zcv.width=cv.width;zcv.height=cv.height;
const base=n=>n,title=n=>(D.rooms.find(r=>r.name==n)||{title:n}).title;
let zboxes=[];
function zones(n){zsvg.innerHTML="";zboxes=[];const Z=n.zones,rowsz={};
 document.getElementById("zhead").textContent=`With ${n.id=="start"?"no abilities":n.id}: ${Z.length} zones. Arrows: ways that don't lead back. Two arrows out: a choice. Click a zone.`;
 Z.forEach((z,i)=>{(rowsz[z.depth]=rowsz[z.depth]||[]).push(i)});
 const ZW=170,ZH=40,ZGX=14,ZGY=46,zp={};let zw=0;
 Object.keys(rowsz).forEach(d=>rowsz[d].forEach((i,k)=>{zp[i]=[12+k*(ZW+ZGX),12+d*(ZH+ZGY)];zw=Math.max(zw,24+(k+1)*(ZW+ZGX))}));
 zsvg.setAttribute("width",zw);zsvg.setAttribute("height",24+Object.keys(rowsz).length*(ZH+ZGY));
 Z.forEach((z,i)=>z.kids.forEach(j=>{const [px,py]=zp[i],[x,y]=zp[j];
  el("path",{class:"edge",style:z.kids.length>1?"stroke:#f0d060":"",d:`M${px+ZW/2},${py+ZH} C${px+ZW/2},${py+ZH+ZGY/2} ${x+ZW/2},${y-ZGY/2} ${x+ZW/2},${y}`},zsvg)}));
 Z.forEach((z,i)=>{const [x,y]=zp[i];const g=el("g",{class:"node",transform:`translate(${x},${y})`},zsvg);
  el("rect",{width:ZW,height:ZH,rx:6},g);const t=el("text",{x:8,y:15},g);t.textContent=(i==n.first?"> ":"")+title(z.rooms[0])+(z.rooms.length>1?" +"+(z.rooms.length-1):"");
  const s=el("text",{x:8,y:30,style:"fill:var(--dim);font-size:11px"},g);s.textContent=z.kids.length>1?"choice: "+z.kids.length+" ways":(z.kids.length?"one way on":"end");
  g.onclick=()=>zshow(n,i);zboxes.push(g)});
 zshow(n,n.first)}
function zshow(n,i){zboxes.forEach(b=>b.classList.remove("sel"));zboxes[i].classList.add("sel");const z=n.zones[i];
 const here=new Set(z.rooms.map(base)),ahead=new Set(z.ahead.map(base)),seen=new Set(n.zones.flatMap(q=>q.rooms).map(base));
 zcx.clearRect(0,0,zcv.width,zcv.height);
 D.rooms.forEach(r=>{const col=here.has(r.name)?"#5fa8ff":ahead.has(r.name)?C.g:seen.has(r.name)?C.r:"#44444f",ox=(r.x-minx)*S,oy=(r.y-miny)*S;
  zcx.globalAlpha=0.35;zcx.fillStyle=col;zcx.fillRect(ox,oy,r.w*S,r.h*S);zcx.globalAlpha=1;
  for(let y=0;y<r.h;y++)for(let x=0;x<r.w;x++)if(r.tiles[y][x]=="1"){zcx.fillStyle="#2c2c36";zcx.fillRect(ox+x*S,oy+y*S,S,S)}
  zcx.strokeStyle=col;zcx.strokeRect(ox+.5,oy+.5,r.w*S-1,r.h*S-1)});
 const behind=[...seen].filter(r=>!ahead.has(r)&&!here.has(r)).map(title),partly=z.rooms.filter(r=>n.zones.filter(q=>q.rooms.includes(r)).length>1);
 document.getElementById("zinfo").innerHTML=`<b>${z.rooms.map(title).join(", ")}</b><br>`+(behind.length?`<span style="color:${C.r}">left behind:</span> ${behind.join(", ")}<br>`:"")+(partly.length?`only part of: ${partly.map(title).join(", ")} (the rest is in another zone)<br>`:"")+
  (z.kids.length?`ways on: `+z.kids.map(j=>title(n.zones[j].rooms[0])).join(" | "):"no way on")}
const show0=show;show=function(n){show0(n);zones(n)};
show(D.nodes[0]);
</script></body></html>"""


if __name__ == "__main__":
    world_dir = sys.argv[1] if len(sys.argv) > 1 else "worlds/story"
    out = sys.argv[2] if len(sys.argv) > 2 else "reports/progression.html"
    W, nodes, order = build(world_dir)
    W.dir = world_dir
    open(out, "w").write(page(W, nodes, order))
    for ab in order:
        n = nodes[ab]
        tiers = {t: sum(1 for v in n["rooms"].values() if v == t) for t in "gop"}
        print("%-20s green %d  orange %d  purple %d  red %d  choices %s" % ("+".join(n["abilities"]) or "start", tiers["g"], tiers["o"], tiers["p"],
              len(W.rooms) - len(n["rooms"]), n["choices"] or "-"))
    print("wrote", out)
