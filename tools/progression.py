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


# Explore with one ability set under every model; return {cell: tier} (best tier wins) and the pickups each tier touches.
def survey(W, base_solid, walls, abilities):
    W.solid = base_solid if "attack" in abilities else base_solid | walls
    cells, pickups = {}, {}
    for tier, model in TIERS:
        ground, touched = explore(W, model, set(abilities), [W.spawn])
        for c in ground:
            cells.setdefault(c, tier)
        for key in touched:
            if key.startswith("ability_"):
                pickups.setdefault(key, tier)
    W.solid = base_solid
    return cells, pickups


def build(world_dir):
    W = World(world_dir)
    base, walls = set(W.solid), breakwalls(W)
    nodes, order = {}, []
    placed = {t[len("ability_"):] for items in W.items.values() for t, _, _ in items if t.startswith("ability_")}
    unplaced = [a for a in ABILITIES if a not in placed]  # no pickup in the world yet: dashed "what if" branches
    todo = [frozenset()]
    while todo:
        ab = todo.pop(0)
        if ab in nodes:
            continue
        cells, pickups = survey(W, base, walls, ab)
        rooms = {}
        for c, tier in cells.items():
            r = W.room_of.get(c)
            if r and (r not in rooms or "gop".index(tier) < "gop".index(rooms[r])):
                rooms[r] = tier
        choices = sorted({k.split(":")[0][len("ability_"):] for k, tier in pickups.items() if tier == "g"} - ab)
        skill = sorted({k.split(":")[0][len("ability_"):] for k, tier in pickups.items() if tier != "g"} - ab)
        nodes[ab] = dict(abilities=sorted(ab), rooms=rooms, cells=cells, choices=choices, skill=skill,
                         unplaced=[a for a in unplaced if a not in ab])
        order.append(ab)
        todo += [ab | {a} for a in choices + nodes[ab]["unplaced"]]
    return W, nodes, order


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
                              unplaced=n["unplaced"]))
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
<canvas id="map"></canvas><div id="info"></div></section></main>
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
