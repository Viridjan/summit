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
BOSSES = {"ape": "a1_ape_arena:ape_", "guardian": "i16_guardian_chamber:guardian_"}  # a boss beaten counts as a power:
# its gates open (boss_gate: the arena's exit, or "until" its flag); reaching it offers "beat it" as a branch


def power(key):  # "ability_dash:room:x,y" -> "dash", "boss_ape:..." -> "ape"
    t = key.split(":")[0]
    return t[len("ability_"):] if t.startswith("ability_") else t[len("boss_"):]


# Boss gate cells, per boss: shut until it's beaten (gates that only close behind you count as open).
def boss_gates(W):
    out = {b: set() for b in BOSSES}
    for name, (ox, oy, lvl) in W.rooms.items():
        room_boss = next((e["t"][len("boss_"):] for e in lvl["entities"] if e["t"] in ("boss_ape", "boss_guardian")), None)
        for e in lvl["entities"]:
            if e["t"] != "boss_gate" or e.get("closes_behind"):
                continue
            b = next((b for b, flag in BOSSES.items() if str(e.get("until", "")).startswith(flag)), None) if e.get("until") else room_boss
            if b:
                for i in range(int(e["w"]) // T):
                    for j in range(int(e["h"]) // T):
                        out[b].add((ox + int(e["x"]) // T + i, oy + int(e["y"]) // T + j))
    return out


def blocked(abilities):  # the rock for this set of powers: breakable walls without attack, gates of bosses not beaten
    extra = set() if "attack" in abilities else _WALLS
    for b, cells in _GATES.items():
        if b not in abilities:
            extra = extra | cells
    return _BASE | extra


_BASE, _WALLS, _GATES = set(), set(), {}
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
    _W.solid = blocked(abilities)
    ground, touched = explore(_W, dict(TIERS)[tier], set(abilities), [_W.spawn])
    return ground, [k for k in touched if k.startswith("ability_") or k.startswith("boss_")]


# Explore several ability sets under every model at once; per set: {cell: tier} (best tier wins), pickups per tier.
def survey_many(W, base_solid, walls, sets):
    global _W, _BASE, _WALLS, _GATES
    _W, _BASE, _WALLS, _GATES = W, base_solid, walls, boss_gates(W)
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
    _W.solid = blocked(abilities) | set(extra)  # a forked copy: the cave-in rock only in this search
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
def room_links(W, entrances, found):
    """Keep direct room exits, including reversible branches; never merge a fork."""
    links = set()
    for (source, _), (_, exits) in zip(entrances, found):
        for target, _, _ in exits:
            if source == target or target not in W.rooms: continue
            ax, ay, _ = W.rooms[source]
            bx, by, _ = W.rooms[target]
            direction = "right" if bx > ax else "left" if bx < ax else "down" if by > ay else "up"
            # Explicit long-distance doors/panels are travel links, not physical adjacency.
            level = W.rooms[source][2]
            if any(str(e.get("to", "")).startswith(target + ":") for e in level.get("entities", [])):
                direction = "panel / door"
            links.add((source, target, direction))
    return [dict(zip(("from", "to", "direction"), link)) for link in sorted(links)]


def zones(W, base_solid, walls, abilities):
    global _BASE, _WALLS, _GATES
    _BASE, _WALLS, _GATES = base_solid, walls, boss_gates(W)
    W.solid = blocked(abilities)
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
    return [dict(rooms=rooms_of_z(z), kids=kids[i], depth=depth[i], ahead=rooms_of_z(ahead[i])) for i, z in enumerate(zl)], first, room_links(W, ents, found)


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
        choices = sorted({power(k) for k, tier in pickups.items() if tier == "g"} - ab)
        skill = sorted({power(k) for k, tier in pickups.items() if tier != "g"} - ab)
        zl, first, links = zones(W, base, walls, ab)
        nodes[ab] = dict(abilities=sorted(ab), rooms=rooms, cells=cells, choices=choices, skill=skill,
                         unplaced=[a for a in unplaced if a not in ab], zones=zl, first=first, links=links)
        order.append(ab)
        return [ab | {a} for a in choices + nodes[ab]["unplaced"]]


def route_graph(rooms, nodes):
    """Static route topology, with all modeled gates open; no selected unlock state."""
    links = {(e["from"], e["to"], e["direction"]) for node in nodes for e in node["links"]}
    return dict(rooms={r["name"]: "g" for r in rooms},
                links=[dict(zip(("from", "to", "direction"), edge)) for edge in sorted(links)])


def page(W, nodes, order):
    room_list = []
    for name, (ox, oy, lvl) in W.rooms.items():
        room_list.append(dict(name=name, title=lvl.get("name", name), x=ox, y=oy, w=lvl["w"], h=lvl["h"], tiles=lvl["tiles"], bosses=[e["t"][5:] for e in lvl["entities"] if e["t"] in ("boss_ape", "boss_guardian")]))
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
                              unplaced=n["unplaced"], zones=n["zones"], first=n["first"], links=n["links"]))
    data = json.dumps(dict(rooms=room_list, regions=regions, nodes=out_nodes, routes=route_graph(room_list, out_nodes), start=W.room_of.get(W.spawn)))
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
#route-card{grid-column:1 / -1}
#route-viewport{overflow:auto;max-height:80vh;margin-top:10px}
#zgraph{display:block;max-width:none}
.route-controls button{cursor:pointer;padding:5px 10px}
canvas{image-rendering:pixelated;width:100%;height:auto;background:#0d0d12;border-radius:4px}
#info{margin-top:8px;color:var(--dim)} #info b{color:var(--fg)}
</style></head><body><main>
<section class="card"><h1>Graph 1 · Unlocks <a href="https://viridjan.github.io/summit/" target="_blank" rel="noopener" style="float:right;font-size:13px;font-weight:600;color:#fff;background:#2f7fe0;border-radius:6px;padding:4px 10px;text-decoration:none">▶ Play the game</a></h1><p>Bosses beaten and powerups collected determine all accessible rooms. Both branches after a gate count as accessible, regardless of which route you take. Select a state to inspect its accessible rooms. This graph has its own selection and map.</p><div id="assume" style="margin:-4px 0 10px;color:var(--fg)"><span style="color:var(--dim)">Assume (no pickup in the world yet): </span></div><svg id="graph"></svg></section>
<section class="card"><div class="legend"><span><i class="sw" style="background:var(--g)"></i>normal</span><span><i class="sw" style="background:var(--o)"></i>with skill</span><span><i class="sw" style="background:var(--p)"></i>not intended</span><span><i class="sw" style="background:var(--r)"></i>unreachable</span></div>
<canvas id="map"></canvas><div id="info"></div></section>
<section class="card" id="route-card"><h1>Graph 2 · Route choices</h1><p id="zhead">Zones: rooms you can go back and forth between. Arrows: ways that don't lead back. Two arrows out: a choice. Click a zone.</p><div class="route-controls"><button id="route-fit">Fit graph</button> <button id="route-in">Zoom +</button> <button id="route-out">Zoom −</button></div><div id="route-viewport"><svg id="zgraph"></svg></div></section>
<section class="card"><div class="legend"><span><i class="sw" style="background:#5fa8ff"></i>selected room</span><span><i class="sw" style="background:var(--g)"></i>reachable from here</span><span><i class="sw" style="background:var(--r)"></i>no return route</span><span><i class="sw" style="background:#44444f"></i>not reached</span></div>
<canvas id="zmap"></canvas><div id="zinfo"></div></section></main>
<script>
const D=/*DATA*/;
const C={g:"#3fbf5f",o:"#f0a030",p:"#b060e0",r:"#c04040"};
const svg=document.getElementById("graph"),NS="http://www.w3.org/2000/svg";
function el(t,a,p){const e=document.createElementNS(NS,t);for(const k in a)e.setAttribute(k,a[k]);(p||svg).appendChild(e);return e}
const LINE_COLORS=["#e8443a","#2f7fe0","#2fb35a","#f29b1d","#9b59d0","#17b3b0","#c0632d","#e05a9d","#7a8a99","#c8b400"];
const tip=document.createElement("div");tip.style.cssText="position:absolute;display:none;max-width:320px;background:#0d0d12;border:1px solid #555566;border-radius:6px;padding:8px 10px;font-size:13px;line-height:1.4;pointer-events:none;z-index:9";document.body.appendChild(tip);
// A metro map: N = [{kids, depth}], one thick line per route from `first` to an end, one row per stop; a stop on
// several lines is joined by a dashed link (arched over any other stop in between). o: label(i), tip(i), click(i),
// faded(a, b) (segment drawn faint). Returns {stop index: <g>} and the number of lines.
function metro(sv,N,first,o){sv.innerHTML="";const boxes={};
 const routes=[],walk=(i,path)=>{path=path.concat([i]);if(!N[i].kids.length)routes.push(path);else N[i].kids.forEach(j=>walk(j,path))};walk(first,[]);
 const at={};routes.forEach((r,li)=>r.forEach(i=>{(at[i]=at[i]||[]);if(!at[i].includes(li))at[i].push(li)}));
 const order=Object.keys(at).map(Number).sort((a,b)=>N[a].depth-N[b].depth||at[a][0]-at[b][0]),rank={};order.forEach((i,k)=>rank[i]=k);
 const CX=34,RY=58,X0=30,Y0=30,col=li=>X0+li*CX,row=i=>Y0+rank[i]*RY,LX=col(routes.length-1)+28;
 sv.setAttribute("width",LX+260);sv.setAttribute("height",Y0+order.length*RY+10);
 const lines=el("g",{},sv),links=el("g",{},sv),stops=el("g",{},sv),labels=el("g",{},sv);
 routes.forEach((r,li)=>{const c=LINE_COLORS[li%LINE_COLORS.length],x=col(li);
  for(let k=0;k<r.length-1;k++)el("line",{x1:x,y1:row(r[k]),x2:x,y2:row(r[k+1]),stroke:c,"stroke-width":9,"stroke-linecap":"round",opacity:o.faded&&o.faded(r[k],r[k+1])?0.3:1},lines);
  const t=el("text",{x:x,y:row(r[r.length-1])+24,"text-anchor":"middle",style:`fill:${c};font-size:11px;font-weight:600`},labels);t.textContent=li+1});
 const occupied=(y,li)=>routes[li].some(i=>row(i)==y);
 order.forEach(i=>{const ls=at[i].slice().sort((a,b)=>a-b),y=row(i),choice=N[i].kids.length>1;
  for(let a=0;a<ls.length-1;a++){const l1=ls[a],l2=ls[a+1],x1=col(l1),x2=col(l2);
   let blocked=false;for(let k=l1+1;k<l2;k++)if(occupied(y,k))blocked=true;
   el("path",{d:blocked?`M${x1},${y} C${x1},${y-34} ${x2},${y-34} ${x2},${y}`:`M${x1},${y} L${x2},${y}`,stroke:"#d8d8e0","stroke-width":2.5,"stroke-dasharray":"5 4",fill:"none"},links)}
  const g=el("g",{style:"cursor:pointer"},stops);boxes[i]=g;
  ls.forEach(li=>el("circle",{cx:col(li),cy:y,r:choice?9:7,fill:"#fff",stroke:choice?"#16161c":LINE_COLORS[li%LINE_COLORS.length],"stroke-width":choice?4:3},g));
  el("line",{x1:col(ls[ls.length-1])+10,y1:y,x2:LX-6,y2:y,stroke:"#3a3a48","stroke-width":1},links);
  const t=el("text",{x:LX,y:y+4,style:"font-size:12px"},labels);t.textContent=o.label(i)+(choice && o.choices!==false?"  ◆ choice":"");
  g.onmouseenter=()=>{tip.innerHTML=o.tip(i);tip.style.display="block"};
  g.onmousemove=e=>{tip.style.left=(e.pageX+14)+"px";tip.style.top=(e.pageY+14)+"px"};
  g.onmouseleave=()=>tip.style.display="none";
  g.onclick=()=>o.click(i)});
 return [boxes,routes.length]}
const mark=(boxes,i)=>{Object.values(boxes).forEach(b=>b.querySelectorAll("circle").forEach(c=>c.setAttribute("fill","#fff")));if(boxes[i])boxes[i].querySelectorAll("circle").forEach(c=>c.setAttribute("fill","#5fa8ff"))};
// top: ability sets (stops) and the order you pick abilities up (lines)
const AN=D.nodes.map(n=>({kids:D.nodes.map((q,k)=>q.parents.includes(n.id)?k:-1).filter(k=>k>=0),depth:n.depth}));
const BOSS={ape:"the Ape",guardian:"the Guardian"},nm=a=>BOSS[a]?BOSS[a].replace("the ","")+" beaten":a,act=a=>BOSS[a]?"beat "+BOSS[a]:"pick up "+a;
const greenOf=n=>Object.values(n.rooms).filter(v=>v=="g").length;
const gainOf=(a,b)=>D.nodes[b].abilities.filter(x=>!D.nodes[a].abilities.includes(x));
function atip(i){const n=D.nodes[i],k=AN[i].kids;
 let s=`<b>${n.id=="start"?"Start: no abilities":"With "+n.abilities.map(nm).join(" + ")}</b><br>${greenOf(n)}/${D.rooms.length} rooms reachable normally.`;
 if(k.length)s+=`<br>${k.length>1?"<b>Choice</b>: ":"Next: "}`+k.map(j=>{const g=gainOf(i,j)[0],d=greenOf(D.nodes[j])-greenOf(n);
  return `<b>${act(g)}</b> (${d>0?"+"+d+" rooms":"no new rooms"}${n.unplaced.includes(g)?", no pickup placed yet":""})`}).join(k.length>1?" or ":"");
 else s+="<br>All abilities.";return s}
// abilities with no pickup in the world can't be a real choice yet: they're assumed with the checkboxes, and the
// lines show only real choices (placed pickups, bosses) on top of them
const FREE=D.nodes[0].unplaced,ASSUME=new Set();
const part=n=>n.abilities.filter(a=>FREE.includes(a)).sort().join("+");
let boxes={},shown=[];
function drawTop(){const want=[...ASSUME].sort().join("+");
 shown=D.nodes.map((n,k)=>k).filter(k=>part(D.nodes[k])==want);
 const N=D.nodes.map((n,k)=>({kids:AN[k].kids.filter(j=>shown.includes(j)),depth:n.abilities.filter(a=>!FREE.includes(a)).length}));
 const first=shown.find(k=>N[k].depth==0);
 [boxes]=metro(svg,N,first,{choices:false,label:i=>{const n=D.nodes[i],real=n.abilities.filter(a=>!FREE.includes(a));
   return (real.length?real.map(nm).join(" + "):"start")+" · "+greenOf(n)+" rooms"},tip:atip,click:i=>show(D.nodes[i])});
 show(D.nodes[first])}
const box=document.getElementById("assume");
FREE.forEach(a=>{const l=document.createElement("label");l.style.cssText="margin-right:12px;cursor:pointer";
 const c=document.createElement("input");c.type="checkbox";c.checked=false;c.onchange=()=>{c.checked?ASSUME.add(a):ASSUME.delete(a);drawTop()};
 l.append(c," "+a);box.append(l)});
if(!FREE.length)box.style.display="none";
const cv=document.getElementById("map"),cx=cv.getContext("2d");
let minx=1e9,miny=1e9,maxx=-1e9,maxy=-1e9;D.rooms.forEach(r=>{minx=Math.min(minx,r.x);miny=Math.min(miny,r.y);maxx=Math.max(maxx,r.x+r.w);maxy=Math.max(maxy,r.y+r.h)});
const S=3;cv.width=(maxx-minx)*S;cv.height=(maxy-miny)*S;
function show(n){mark(boxes,D.nodes.indexOf(n));
 cx.clearRect(0,0,cv.width,cv.height);
 D.rooms.forEach(r=>{const tier=n.rooms[r.name]||"r",ox=(r.x-minx)*S,oy=(r.y-miny)*S,m=n.marks[r.name];
  cx.globalAlpha=0.28;cx.fillStyle=C[tier];cx.fillRect(ox,oy,r.w*S,r.h*S);cx.globalAlpha=1;
  for(let y=0;y<r.h;y++)for(let x=0;x<r.w;x++){if(r.tiles[y][x]=="1"){cx.fillStyle="#2c2c36";cx.fillRect(ox+x*S,oy+y*S,S,S)}
   const k=m[y*r.w+x];if(k!="."){cx.fillStyle=C[k];cx.fillRect(ox+x*S,oy+y*S,S,S)}}
  cx.strokeStyle=C[tier];cx.lineWidth=1;cx.strokeRect(ox+.5,oy+.5,r.w*S-1,r.h*S-1)});
 const by={g:[],o:[],p:[],r:[]};D.rooms.forEach(r=>by[n.rooms[r.name]||"r"].push(r.title));
 document.getElementById("info").innerHTML=`<b>${n.id}</b> &middot; available bosses / powerups: ${n.choices.map(act).join(", ")||"none"}${n.skill.length?" &middot; only with skill: "+n.skill.join(", "):""}<br>`+
  ["g","o","p","r"].map(k=>by[k].length?`<span style="color:${C[k]}">${{g:"accessible rooms",o:"with skill",p:"not intended",r:"unreachable"}[k]}:</span> ${by[k].join(", ")}`:"").filter(Boolean).join("<br>")}
const zsvg=document.getElementById("zgraph"),zcv=document.getElementById("zmap"),zcx=zcv.getContext("2d");zcv.width=cv.width;zcv.height=cv.height;
const title=n=>(D.rooms.find(r=>r.name==n)||{title:n}).title;

function routeTree(names,links,start,choiceRooms=[]){
 const children=Object.fromEntries(names.map(r=>[r,[]])),parent={},depth={},queue=[];
 if(names.includes(start)){depth[start]=0;queue.push(start)}
 for(let i=0;i<queue.length;i++){
  const r=queue[i];
  links.filter(e=>e.from===r).sort((a,b)=>{
   const rank={left:0,up:1,down:2,right:3};return (rank[a.direction]??2)-(rank[b.direction]??2)||a.to.localeCompare(b.to)
  }).forEach(e=>{if(depth[e.to]===undefined){parent[e.to]=r;depth[e.to]=depth[r]+1;children[r].push(e.to);queue.push(e.to)}})
 }
 const aliases={},displayLinks=links.slice();
 links.forEach(e=>{if(choiceRooms.includes(e.from)&&parent[e.to]!==e.from&&depth[e.from]!==undefined&&depth[e.to]!==undefined){
  const ref=e.from+"::"+e.to;aliases[ref]=e.to;children[ref]=[];parent[ref]=e.from;depth[ref]=depth[e.from]+1;children[e.from].unshift(ref);queue.push(ref);
  displayLinks[displayLinks.indexOf(e)]={...e,to:ref};displayLinks.push({...e,from:ref});
 }});
 let leaf=0;const pos={};
 function place(r){const kids=children[r];kids.forEach(place);
  const x=kids.length?(pos[kids[0]].x+pos[kids[kids.length-1]].x)/2:30+leaf++*230;
  pos[r]={x,y:30+depth[r]*110};
 }
 if(queue.length)place(start);
 const extra=links.filter(e=>pos[e.from]&&pos[e.to]&&parent[e.to]!==e.from);
 return {children,parent,pos,extra,aliases,links:displayLinks,names:queue,width:Math.max(500,leaf*230+40)};
}
let routeZoom=1;
function fitRoutes(){routeZoom=1;resizeRoutes()}
function resizeRoutes(){
 const bounds=zsvg.getAttribute("viewBox").split(" ").map(Number);
 const width=Math.max(1,document.getElementById("route-viewport").clientWidth)*routeZoom;
 zsvg.style.width=width+"px";zsvg.style.height=(width*bounds[3]/bounds[2])+"px";
}
document.getElementById("route-fit").onclick=fitRoutes;
document.getElementById("route-in").onclick=()=>{routeZoom=Math.min(6,routeZoom*1.4);resizeRoutes()};
document.getElementById("route-out").onclick=()=>{routeZoom=Math.max(1,routeZoom/1.4);resizeRoutes()};
window.addEventListener("resize",()=>{if(zsvg.hasAttribute("viewBox"))resizeRoutes()});
function zones(n){zsvg.innerHTML="";
 const names=Object.keys(n.rooms).filter(r=>n.rooms[r]==="g").sort();
 const links=n.links.filter(e=>names.includes(e.from)&&names.includes(e.to));
 const choiceRooms=D.rooms.filter(r=>r.bosses?.length).map(r=>r.name);
 const tree=routeTree(names,links,D.start,choiceRooms),pos=tree.pos,width=tree.width;
 zsvg.setAttribute("width",width);zsvg.setAttribute("height",Math.max(120,...Object.values(pos).map(p=>p.y+80)));
 const lineColors={};let nextColor=1;
 function colorBranch(r,color){lineColors[r]=color;tree.children[r].forEach((child,i)=>colorBranch(child,i===0?color:LINE_COLORS[nextColor++%LINE_COLORS.length]))}
 if(pos[D.start])colorBranch(D.start,LINE_COLORS[0]);
 const defs=el("defs",{},zsvg),marker=el("marker",{id:"arrow",viewBox:"0 0 10 10",refX:9,refY:5,markerWidth:6,markerHeight:6,orient:"auto"},defs);
 el("path",{d:"M0 0 L10 5 L0 10 z",fill:"#8a8a99"},marker);
 tree.links.filter(e=>pos[e.from]&&pos[e.to]).forEach(e=>{const a=pos[e.from],b=pos[e.to],back=tree.parent[e.to]!==e.from;
 const path=el("path",{class:back?"metro-return":"metro-route",d:back?`M${a.x+90},${a.y+20} C${a.x+200},${a.y-24} ${b.x+200},${b.y-24} ${b.x+90},${b.y+20}`:`M${a.x+90},${a.y+20} V${a.y+48} L${b.x+90},${b.y-8} V${b.y+20}`,fill:"none",stroke:back?"#a0a0b0":lineColors[e.to],"stroke-width":back?1.5:8,"stroke-linecap":"round","stroke-linejoin":"round","stroke-dasharray":back?"4 5":"none",opacity:back?.4:1},zsvg);
 const t=el("title",{},path);t.textContent=`${title(e.from)} → ${title(e.to)} (${e.direction})`});
 tree.names.forEach(r=>{const p=pos[r],kids=tree.links.filter(e=>e.from===r&&tree.parent[e.to]===r),g=el("g",{style:"cursor:pointer"},zsvg);
 el("circle",{class:"metro-station","data-room":tree.aliases[r]||r,cx:p.x+90,cy:p.y+20,r:kids.length>1?9:7,fill:"#fff",stroke:kids.length>1?"#16161c":lineColors[r],"stroke-width":kids.length>1?4:3},g);
 const t=el("text",{x:p.x+105,y:p.y+17,fill:"#eee",style:"font-size:11px;paint-order:stroke;stroke:#20202a;stroke-width:3px"},g);t.textContent=title(tree.aliases[r]||r);
 const sub=el("text",{x:p.x+105,y:p.y+32,fill:"#aaa",style:"font-size:10px;paint-order:stroke;stroke:#20202a;stroke-width:3px"},g);sub.textContent=tree.aliases[r]?"↩ existing route":kids.length>1?`${kids.length} route choices`:"";
 g.onclick=()=>zshow(n,tree.aliases[r]||r);const tt=el("title",{},g);tt.textContent=kids.map(e=>e.direction+": "+title(e.to)).join("\n")});
 document.getElementById("zhead").textContent=`World route choices, independent of Graph 1. Shows routes with gates open; it does not filter by boss or powerup selection. Choose which connected room to visit. Start at the root and follow colored metro lines, branching at each choice. Dashed links are returns or connections to an existing branch. Hover arrows for direction.`;
 // Include labels and return curves, not just station coordinates, in the fitted bounds.
 const bounds=zsvg.getBBox(),pad=20;
 zsvg.setAttribute("viewBox",[bounds.x-pad,bounds.y-pad,bounds.width+pad*2,bounds.height+pad*2].join(" "));
 fitRoutes();
 zshow(n,names.includes(D.start)?D.start:names[0]);
}
function zshow(n,room){
 zsvg.querySelectorAll(".metro-station").forEach(c=>c.setAttribute("fill",c.getAttribute("data-room")===room?"#5fa8ff":"#fff"));
 const links=n.links.filter(e=>n.rooms[e.from]==="g"&&n.rooms[e.to]==="g"),ahead=new Set([room]),todo=[room];
 while(todo.length){const r=todo.pop();links.filter(e=>e.from===r).forEach(e=>{if(!ahead.has(e.to)){ahead.add(e.to);todo.push(e.to)}})}
 zcx.clearRect(0,0,zcv.width,zcv.height);
 D.rooms.forEach(r=>{const col=r.name===room?"#5fa8ff":ahead.has(r.name)?C.g:n.rooms[r.name]==="g"?C.r:"#44444f",ox=(r.x-minx)*S,oy=(r.y-miny)*S;
 zcx.globalAlpha=.35;zcx.fillStyle=col;zcx.fillRect(ox,oy,r.w*S,r.h*S);zcx.globalAlpha=1;
 for(let y=0;y<r.h;y++)for(let x=0;x<r.w;x++)if(r.tiles[y][x]==="1"){zcx.fillStyle="#2c2c36";zcx.fillRect(ox+x*S,oy+y*S,S,S)}
 zcx.strokeStyle=col;zcx.strokeRect(ox+.5,oy+.5,r.w*S-1,r.h*S-1)});
 const info=document.getElementById("zinfo");info.replaceChildren();const head=document.createElement("b");head.textContent=title(room);info.append(head);
 links.filter(e=>e.from===room).forEach(e=>{const b=document.createElement("button");b.textContent=e.direction+" → "+title(e.to);b.style.cssText="display:block;margin:6px 0;padding:6px;cursor:pointer";b.onclick=()=>zshow(n,e.to);info.append(b)})}
drawTop();
zones(D.routes);
const fromHash=D.nodes.find(q=>q.id==decodeURIComponent(location.hash.slice(1)));  // e.g. progression.html#ape+dash
if(fromHash){ASSUME.clear();fromHash.abilities.filter(a=>FREE.includes(a)).forEach(a=>ASSUME.add(a));box.querySelectorAll("input").forEach((c,k)=>c.checked=ASSUME.has(FREE[k]));drawTop();show(fromHash)}
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
