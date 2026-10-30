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
from pathlib import Path
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
            if e["t"] != "boss_gate" or e.get("closes_behind") or e.get("after"):
                continue
            b = next((b for b, flag in BOSSES.items() if str(e.get("until", "")).startswith(flag)), None) if e.get("until") else room_boss
            if b:
                for i in range(int(e["w"]) // T):
                    for j in range(int(e["h"]) // T):
                        out[b].add((ox + int(e["x"]) // T + i, oy + int(e["y"]) // T + j))
    return out


def after_gates(W):
    out={boss:set() for boss in BOSSES}
    for name,(ox,oy,level) in W.rooms.items():
        for e in level['entities']:
            if e['t']!='boss_gate' or not e.get('after'): continue
            boss=next((b for b,flag in BOSSES.items() if str(e['after']).startswith(flag)),None)
            if boss:
                out[boss].update((ox+int(e['x'])//T+x,oy+int(e['y'])//T+y) for x in range(int(e['w'])//T) for y in range(int(e['h'])//T))
    return out


def blocked(abilities):  # the rock for this set of powers: breakable walls without attack, gates of bosses not beaten
    extra = set() if "attack" in abilities else _WALLS
    for b, cells in _GATES.items():
        if b not in abilities:
            extra = extra | cells
    for b, cells in _AFTER_GATES.items():
        if b in abilities: extra = extra | cells
    return _BASE | extra


_BASE, _WALLS, _GATES = set(), set(), {}
_AFTER_GATES = {}
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
    starts=[_W.spawn]
    # Once a boss is beaten, progress continues from that arena, not the now-sealed approach.
    for boss,flag in BOSSES.items():
        if boss in abilities:
            name=flag.split(":")[0]
            ox,oy,level=_W.rooms[name]
            markers=[e for e in level['entities'] if e['t'] in ('spawn','respawn')]
            if markers: starts=[(ox+int(e['x'])//T,oy+int(e['y'])//T) for e in markers]
    ground, touched = explore(_W, dict(TIERS)[tier], set(abilities), starts)
    return ground, [k for k in touched if k.startswith("ability_") or k.startswith("boss_")]


# Explore several ability sets under every model at once; per set: {cell: tier} (best tier wins), pickups per tier.
def survey_many(W, base_solid, walls, sets):
    global _W, _BASE, _WALLS, _GATES, _AFTER_GATES
    _W, _BASE, _WALLS, _GATES = W, base_solid, walls, boss_gates(W)
    _AFTER_GATES = after_gates(W)
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
        for e in lvl.get("entities", []):
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
    cave = seals(W)
    for (source, cell), (_, exits) in zip(entrances, found):
        for target, _, _ in exits:
            if source == target or target not in W.rooms: continue
            if source in cave and cell[0] < cave[source][0]:
                continue  # a cave-in room: its chase starts on entering, so there's no going back the way you came
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
    global _BASE, _WALLS, _GATES, _AFTER_GATES
    _BASE, _WALLS, _GATES = base_solid, walls, boss_gates(W)
    _AFTER_GATES = after_gates(W)
    W.solid = blocked(abilities)
    global _W
    _W = W
    cave = seals(W)
    ents = []  # (room, cell)
    for name, (ox, oy, lvl) in W.rooms.items():
        for e in lvl["entities"]:
            if e["t"] in ("spawn", "respawn"):  # room entrances (respawn slabs) and the start
                ents.append((name, (ox + int(e["x"]) // T, oy + int(e["y"]) // T)))
            elif e["t"] in ("door", "house_door"):  # where you stand arriving through a door
                ents.append((name, (ox + (int(e["x"]) + int(e.get("w", T)) // 2) // T, oy + (int(e["y"]) + int(e.get("h", T))) // T - 1)))
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
    starting = frozenset(json.loads(Path(world_dir, "world.json").read_text()).get("abilities", []))
    unplaced = [a for a in ABILITIES if a not in placed and a not in starting]  # no pickup in the world yet: dashed "what if" branches
    todo = [starting]
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
    requirements = {}
    for room in rooms:
        states = [set(node["abilities"]) & BOSSES.keys() for node in nodes if node.get("rooms", {}).get(room["name"]) == "g"]
        requirements[room["name"]] = sorted(set.intersection(*states)) if states else []
    return dict(rooms={r["name"]: "g" for r in rooms}, requirements=requirements,
                links=[dict(zip(("from", "to", "direction"), edge)) for edge in sorted(links)])


def page(W, nodes, order):
    room_list = []
    for name, (ox, oy, lvl) in W.rooms.items():
        room_list.append(dict(name=name, title=lvl.get("name", name), x=ox, y=oy, w=lvl["w"], h=lvl["h"], tiles=lvl["tiles"], bosses=[e["t"][5:] for e in lvl["entities"] if e["t"] in ("boss_ape", "boss_guardian")],
                              after_barriers=[boss for boss,flag in BOSSES.items() if any(e["t"]=="boss_gate" and str(e.get("after", "")).startswith(flag) for e in lvl["entities"])]))
    regions = {}
    try:
        for g in json.loads(Path(W.dir, "world.json").read_text()).get("regions", []):
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
    # JSON is embedded inside an HTML script element, not a standalone JSON response.
    data = data.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
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
#graph{display:block;max-width:none}
#unlock-viewport{overflow:auto;max-height:78vh;margin-top:6px}
svg text{fill:var(--fg);font-size:12px} .node{cursor:pointer} .node rect{fill:#2a2a38;stroke:var(--line)}
.node.sel rect{stroke:var(--fg);stroke-width:2} .edge{stroke:var(--line);stroke-width:2;fill:none}
.legend span{display:inline-block;margin-right:12px} .sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px}
#route-viewport{overflow:auto;max-height:78vh;margin-top:6px}
#route-map{position:sticky;top:16px;align-self:start}
#zgraph{display:block;max-width:none}
.route-controls button{cursor:pointer;padding:5px 10px}
canvas{image-rendering:pixelated;width:100%;height:auto;background:#0d0d12;border-radius:4px}
#unlock-path{margin-top:12px;padding:10px;background:#16161c;border-radius:5px;line-height:1.6}
#unlock-path ol{margin:6px 0 0;padding-left:24px}
#unlock-path .chosen{color:#5fa8ff;font-weight:600}
#info{margin-top:8px;color:var(--dim)} #info b{color:var(--fg)}

[hidden]{display:none!important}
*{box-sizing:border-box}
.page-header{max-width:1700px;margin:auto;padding:16px 20px 12px;display:flex;align-items:center;justify-content:space-between;gap:16px}
.page-header h1{font-size:19px;margin:0}
.page-header nav{display:flex;background:var(--card);padding:4px;border-radius:8px;gap:4px}
.page-header button{border:0;background:transparent;color:var(--dim);padding:9px 18px;cursor:pointer;border-radius:5px;font:inherit}
.page-header button[aria-selected="true"]{background:#3565b7;color:white}
.play-link{color:var(--dim);text-decoration:none}
main{max-width:1700px;margin:0 auto;display:grid;grid-template-columns:minmax(310px,32%) minmax(0,1fr);gap:16px;padding:0 20px 20px}
.card{min-width:0;overflow:hidden;padding:14px}
.graph-pane,.map-pane{height:calc(100vh - 100px);min-height:380px}
.graph-pane{display:flex;flex-direction:column}
.pane-head,.map-toolbar{display:flex;align-items:center;gap:10px;min-height:28px}
h2{font-size:16px;margin:0}
.count{color:var(--dim);font-size:12px;margin-left:auto}
.hint{color:var(--dim);cursor:help}
.unlock-filters{font-size:12px;margin:8px 0!important;gap:12px!important}
.unlock-filters label,.same-toggle{cursor:pointer;color:var(--dim)}
.same-toggle{font-size:12px;margin:8px 0}
#unlock-viewport,#route-viewport{flex:1;min-height:0;max-height:none;overflow:auto;margin-top:8px}
.map-pane{display:flex;flex-direction:column;overflow:auto}
#route-map{position:static;align-self:auto}
.map-toolbar{position:relative;justify-content:space-between;flex:none}
.map-toolbar h2{max-width:85%;font-weight:500;overflow-wrap:anywhere}
.legend-pop{font-size:12px;position:relative}
.legend-pop summary{cursor:pointer;color:var(--dim);padding:5px 8px;list-style:none}
.legend-pop[open]{z-index:5}
.legend-pop[open]>:not(summary){background:#15151d;padding:10px;display:block;position:relative;min-width:220px}
.legend-pop[open]{position:absolute;right:0;top:0;background:#15151d;border:1px solid #41414f;border-radius:6px;max-width:300px;box-shadow:0 8px 24px #0008}
.legend-pop .legend span{display:block;margin:5px 0}
#upgrade-legend{display:flex!important;flex-direction:column;gap:5px!important;margin:0!important}
.map-frame{flex:1;min-height:260px;max-height:65vh;display:flex;align-items:center;justify-content:center;background:#0d0d12;border-radius:6px;margin-top:12px;overflow:hidden}
.map-frame canvas{display:block;width:100%;height:100%;object-fit:contain;max-height:65vh}
.map-details{flex:none;display:flex;gap:18px;flex-wrap:wrap;margin-top:12px}
.map-details details{width:100%;color:var(--dim)}
.map-details summary{cursor:pointer;font-size:12px;padding:4px 0}
.map-details details:not([open]){width:auto}
.selection-status{font-size:12px;color:#f0b65c;min-height:0;margin-top:8px}
.selection-status:empty{display:none}
#unlock-path{margin:0;padding:8px;background:transparent;font-size:12px}
#info,#zinfo{font-size:12px;line-height:1.6}
@media(max-width:850px){.page-header{padding:12px;flex-wrap:wrap;gap:8px}.page-header h1{font-size:16px}.page-header button{padding:8px 12px}main{padding:0 12px 12px;grid-template-columns:1fr}.map-pane{grid-row:1;height:auto;min-height:360px}.map-frame{height:38vh;flex:none;min-height:210px}.graph-pane{height:55vh;min-height:300px}.play-link{display:none}}
</style></head><body>
<header class="page-header"><h1>World explorer</h1><nav role="tablist" aria-label="Visualization"><button id="tab-unlocks" role="tab" aria-controls="unlock-map" aria-selected="true" data-view="unlocks">Progression</button><button id="tab-routes" role="tab" aria-controls="route-map" aria-selected="false" data-view="routes" tabindex="-1">Route choices</button></nav><a class="play-link" href="https://viridjan.github.io/summit/" target="_blank" rel="noopener">Play ↗</a></header>
<main>
<section class="card graph-pane view-unlocks" id="unlock-graph" aria-label="Progression graph"><header class="pane-head"><h2>Conditions</h2><span id="unlock-filter-status" class="count" role="status" aria-live="polite"></span><span class="hint" tabindex="0" title="Click a later step to move forward while keeping the route where possible. Click an earlier step once to reroute through it without moving the map, then click it again to show that state. Incoming paths preserve acquisition order. Blue is the map state; amber is the pending step.">ⓘ</span></header>
<div class="unlock-filters" style="display:flex;flex-wrap:wrap;gap:12px;margin:10px 0"><label title="Collapse conditions with no pickup placed. Preserve boss conditions reached after those hidden steps."><input type="checkbox" role="switch" id="hide-unplaced"> Unplaced</label><label title="Hide unavailable actions while collapsing unplaced prerequisites, preserving valid Ape and Guardian progression."><input type="checkbox" role="switch" id="hide-unavailable"> Unavailable</label></div>
<div id="unlock-viewport"><svg id="graph" aria-label="Upgrade progression"></svg></div></section>
<section class="card map-pane view-unlocks" id="unlock-map" role="tabpanel" aria-labelledby="tab-unlocks"><header class="map-toolbar"><h2 id="map-selection">Start</h2><details class="legend-pop"><summary>Key</summary><div class="legend"><span><i class="sw" style="background:var(--g)"></i>normal</span><span><i class="sw" style="background:var(--o)"></i>with skill</span><span><i class="sw" style="background:var(--p)"></i>not intended</span><span><i class="sw" style="background:var(--r)"></i>unreachable</span></div><div id="upgrade-legend"></div><small>Dim paths: unplaced pickups. Blue station: map state. Amber: pending step.</small></details></header>
<div class="map-frame"><canvas id="map" aria-label="Progression reachability map"></canvas></div>
<div id="interaction-status" class="selection-status" role="status" aria-live="polite"></div>
<div class="map-details"><details><summary>Route</summary><div id="unlock-path" role="status" aria-live="polite"></div></details><details><summary>Rooms</summary><div id="info"></div></details></div></section>
<section class="card graph-pane view-routes" id="route-card" aria-label="Route graph"><header class="pane-head"><h2>Regions</h2><span id="zhead" class="hint" tabindex="0">ⓘ</span></header><label class="same-toggle" title="Dashed connectors identify the same group appearing on two branches; they are not travel routes."><input type="checkbox" id="route-same"> Same stops</label><div id="route-viewport"><svg id="zgraph" aria-label="Grouped route choices"></svg></div></section>
<section class="card map-pane view-routes" id="route-map" role="tabpanel" aria-labelledby="tab-routes"><header class="map-toolbar"><h2 id="route-selection">World routes</h2><details class="legend-pop"><summary>Key</summary><div class="legend"><span><i class="sw" style="background:#5fa8ff"></i>selected room</span><span><i class="sw" style="background:var(--g)"></i>reachable from here</span><span><i class="sw" style="background:var(--r)"></i>no return route</span><span><i class="sw" style="background:#44444f"></i>not reached</span></div><small>Solid metro lines: paths. Optional dashed connectors: identical groups.</small></details></header><div class="map-frame"><canvas id="zmap" aria-label="Route map"></canvas></div><div class="map-details"><details><summary>Rooms</summary><div id="zinfo"></div></details></div></section>
</main>
<script>
const D=/*DATA*/;
const C={g:"#3fbf5f",o:"#f0a030",p:"#b060e0",r:"#c04040"};
const svg=document.getElementById("graph"),NS="http://www.w3.org/2000/svg";
function escapeHtml(value){const span=document.createElement('span');span.textContent=String(value);return span.innerHTML}
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
 const CX=o.columnGap||34,RY=58,X0=30,Y0=30,col=li=>X0+li*CX,row=i=>Y0+rank[i]*RY,LX=col(routes.length-1)+28;
 sv.setAttribute("width",LX+260);sv.setAttribute("height",Y0+order.length*RY+10);
 const lines=el("g",{},sv),links=el("g",{},sv),stops=el("g",{},sv),labels=el("g",{},sv);
 routes.forEach((r,li)=>{const c=LINE_COLORS[li%LINE_COLORS.length],x=col(li);
  const group=el("g",{class:"unlock-line","data-line":li},lines);
  const choose=step=>{o.click(r[step]);if(o.route)o.route(li,r,step)};
  for(let k=0;k<r.length-1;k++){
   const segment=el("line",{class:"unlock-segment","data-line":li,"data-step":k+1,x1:x,y1:row(r[k]),x2:x,y2:row(r[k+1]),stroke:c,"stroke-width":9,"stroke-linecap":"round",opacity:o.faded&&o.faded(r[k],r[k+1])?0.3:1,style:"cursor:pointer"},group);
   const hint=el("title",{},segment);hint.textContent=`Line ${li+1}: ${o.transition?o.transition(r[k],r[k+1]):o.label(r[k+1])}`;
   segment.onclick=()=>choose(k+1);
  }
  const t=el("text",{x:x,y:row(r[r.length-1])+24,"text-anchor":"middle",role:"button",tabindex:0,style:`fill:${c};font-size:11px;font-weight:600;cursor:pointer`},labels);t.textContent=li+1;
  t.onclick=()=>choose(r.length-1);t.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();choose(r.length-1)}};
  const hint=el("title",{},t);hint.textContent='Select line '+(li+1)+' to see its full progression order';
 });
 const occupied=(y,li)=>routes[li].some(i=>row(i)==y);
 order.forEach(i=>{const ls=at[i].slice().sort((a,b)=>a-b),y=row(i),choice=N[i].kids.length>1;
  for(let a=0;a<ls.length-1;a++){const l1=ls[a],l2=ls[a+1],x1=col(l1),x2=col(l2);
   let blocked=false;for(let k=l1+1;k<l2;k++)if(occupied(y,k))blocked=true;
   el("path",{d:blocked?`M${x1},${y} C${x1},${y-34} ${x2},${y-34} ${x2},${y}`:`M${x1},${y} L${x2},${y}`,stroke:"#d8d8e0","stroke-width":2.5,"stroke-dasharray":"5 4",fill:"none"},links)}
  const g=el("g",{style:"cursor:pointer"},stops);boxes[i]=g;
  ls.forEach(li=>{
   const circle=el("circle",{class:"unlock-station","data-line":li,cx:col(li),cy:y,r:choice?9:7,fill:"#fff",stroke:choice?"#16161c":LINE_COLORS[li%LINE_COLORS.length],"stroke-width":choice?4:3,role:"button",tabindex:0,"aria-label":`Line ${li+1}: ${o.label(i)}`},g);
   const choose=()=>{o.click(i);if(o.route)o.route(li,routes[li],routes[li].indexOf(i))};
   circle.onclick=e=>{e.stopPropagation();choose()};circle.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();choose()}};
  });
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
let unlockHiddenPowers=new Set();
const gainOf=(a,b)=>D.nodes[b].abilities.filter(x=>!unlockHiddenPowers.has(x)&&!D.nodes[a].abilities.includes(x));
function atip(i){const n=D.nodes[i],k=activeUnlockGraph?(activeUnlockGraph.children[String(i)]||[]).map(Number):AN[i].kids;
 let s=`<b>${n.id=="start"?"Start: no abilities":"With "+n.abilities.filter(p=>!unlockHiddenPowers.has(p)).map(nm).join(" + ")}</b><br>${greenOf(n)}/${D.rooms.length} rooms reachable normally.`;
 if(k.length)s+=`<br>${k.length>1?"<b>Choice</b>: ":"Next: "}`+k.map(j=>{const g=gainOf(i,j)[0],d=greenOf(D.nodes[j])-greenOf(n);
  return `<b>${act(g)}</b> (${d>0?"+"+d+" rooms":"no new rooms"}${n.unplaced.includes(g)?", no pickup placed yet":""})`}).join(k.length>1?" or ":"");
 else s+="<br>All abilities.";return s}
function unlockSteps(nodes,path,hidden=[]){
 return path.slice(1).map((node,i)=>nodes[node].abilities.find(power=>!hidden.includes(power)&&!nodes[path[i]].abilities.includes(power)));
}
function showUnlockPath(line,path,step,heading="Line"){
 svg.querySelectorAll('.unlock-line,.unlock-station').forEach(e=>e.setAttribute('opacity',Number(e.dataset.line)===line?1:.2));
 const panel=document.getElementById('unlock-path');panel.replaceChildren();
 const head=document.createElement('b'),steps=unlockSteps(D.nodes,path,[...unlockHiddenPowers]),action=step?act(steps[step-1]):'start with '+(D.nodes[path[0]].abilities.filter(p=>!unlockHiddenPowers.has(p)).map(nm).join(' + ')||'no abilities');
 head.textContent=(heading?`${heading} ${line+1} · `:"")+`Choice made: ${action}`;head.style.color=LINE_COLORS[line%LINE_COLORS.length];panel.append(head);
 const list=document.createElement('ol');
 steps.forEach((power,i)=>{const item=document.createElement('li');item.textContent=act(power)+(D.nodes[path[i]].unplaced.includes(power)?' (pickup not placed yet)':'');
  if(i===step-1)item.className='chosen';if(i>=step)item.style.opacity='.45';list.append(item)});
 panel.append(list);
}
// Show every ability/boss state, like the original metro chart. Unplaced pickups are explicit hypothetical segments.
let boxes={};
function mergedUnlocks(nodes){
 const byKey={},canonical={},names=[],parents={},children={},links=[],seen=new Set();
 nodes.forEach((n,i)=>{const key=n.abilities.slice().sort().join('+');if(byKey[key]===undefined){byKey[key]=String(i);names.push(String(i))}canonical[i]=byKey[key]});
 names.forEach(id=>{parents[id]=[];children[id]=[]});
 nodes.forEach((n,i)=>n.parents.forEach(id=>{const index=nodes.findIndex(q=>q.id===id);if(index<0)return;
  const from=canonical[index],to=canonical[i],key=from+'|'+to;
  if(from===to||seen.has(key))return;seen.add(key);links.push({from,to});parents[to].push(from);children[from].push(to);
 }));
 return {names,parents,children,links,canonical};
}
function filteredUnlocks(nodes,hideUnplaced=false,hideUnavailable=false){
 const collapseUnplaced=hideUnplaced||hideUnavailable;
 const missing=new Set(nodes.flatMap(n=>n.unplaced||[])),byKey={},canonical={},names=[],display={},parents={},children={},links=[],seen=new Set();
 nodes.forEach((node,i)=>{const visible=node.abilities.filter(p=>!collapseUnplaced||!missing.has(p)),key=visible.slice().sort().join('+');
  if(byKey[key]===undefined){byKey[key]=String(i);names.push(String(i));display[i]=visible;parents[i]=[];children[i]=[]}canonical[i]=byKey[key];
 });
 nodes.forEach((node,i)=>node.parents.forEach(id=>{const index=nodes.findIndex(n=>n.id===id);if(index<0)return;
  const before=nodes[index],added=node.abilities.filter(p=>!before.abilities.includes(p));
  if(hideUnavailable&&added.some(p=>!(collapseUnplaced&&missing.has(p))&&!(before.choices||[]).includes(p)))return;
  const from=canonical[index],to=canonical[i],key=from+'|'+to;
  if(from===to||seen.has(key))return;seen.add(key);links.push({from,to});
 }));
 const root=canonical[nodes.findIndex(n=>!n.parents.length)],reached=new Set([root]),todo=[root];
 while(todo.length){const from=todo.pop();links.filter(e=>e.from===from).forEach(e=>{if(!reached.has(e.to)){reached.add(e.to);todo.push(e.to)}})}
 const keptLinks=links.filter(e=>reached.has(e.from)&&reached.has(e.to));
 keptLinks.forEach(e=>{parents[e.to].push(e.from);children[e.from].push(e.to)});
 return {names:names.filter(id=>reached.has(id)),parents,children,links:keptLinks,canonical,display};
}
function planUnlockRoute(graph,route,target,via){
 target=Number(target);const root=Number(graph.names.find(id=>!graph.parents[id].length));
 const path=(from,to)=>{from=Number(from);to=Number(to);const todo=[[from]],seen=new Set([from]);
  for(let i=0;i<todo.length;i++){const current=todo[i],last=current[current.length-1];if(last===to)return current;
   for(const child of graph.children[String(last)]||[]){const next=Number(child);if(!seen.has(next)){seen.add(next);todo.push(current.concat([next]))}}
  }return null;
 };
 const waypoint=via===undefined?target:Number(via),old=route.length?route:[root];
 let prefix=null;
 for(let i=old.length-1;i>=0;i--){const tail=path(old[i],waypoint);if(tail){prefix=old.slice(0,i+1).concat(tail.slice(1));break}}
 if(!prefix)prefix=path(root,waypoint)||[root];
 if(via!==undefined&&prefix[prefix.length-1]!==target){const tail=path(waypoint,target);if(tail)prefix=prefix.concat(tail.slice(1))}
 const end=old[old.length-1];let result=prefix,current=result[result.length-1];
 if(path(current,end))for(const stop of old){const tail=path(current,stop);if(tail&&path(stop,end)){result=result.concat(tail.slice(1));current=stop}}
 return result;
}
function selectUnlockStep(graph,route,mapState,pending,target,via){
 target=Number(target);const nextRoute=planUnlockRoute(graph,route,target,via);
 const previous=graph.display[String(target)].length<graph.display[String(mapState)].length;
 const waiting=previous&&(pending===null||Number(pending)!==target);
 return {route:nextRoute,mapState:waiting?Number(mapState):target,pending:waiting?target:null,mapChanged:!waiting};
}
let unlockSelectedPath=[],activeUnlockGraph,unlockMapState=0,unlockPendingStep=null;
function drawTop(){
 svg.innerHTML='';boxes={};unlockSelectedPath=[];
 const hideUnplaced=document.getElementById('hide-unplaced').checked,hideUnavailable=document.getElementById('hide-unavailable').checked;
 unlockHiddenPowers=new Set((hideUnplaced||hideUnavailable)?D.nodes.flatMap(n=>n.unplaced):[]);
 const graph=filteredUnlocks(D.nodes,hideUnplaced,hideUnavailable),root=graph.canonical[String(D.nodes.findIndex(n=>!n.parents.length))];
 activeUnlockGraph=graph;
 const allStates=mergedUnlocks(D.nodes).names.length;
 const filterStatus=document.getElementById('unlock-filter-status');filterStatus.textContent=`${graph.names.length} / ${allStates}`;
 filterStatus.title=(hideUnplaced||hideUnavailable)?'Unplaced prerequisites are collapsed; reachable Ape and Guardian conditions remain visible.':'Visible upgrade states / total states';
 const powers=[...new Set(D.nodes.flatMap(n=>n.abilities))],colorOf=power=>LINE_COLORS[Math.max(0,powers.indexOf(power))%LINE_COLORS.length];
 const legend=document.getElementById('upgrade-legend');legend.replaceChildren();
 powers.filter(power=>graph.links.some(e=>gainOf(Number(e.from),Number(e.to)).includes(power))).forEach(power=>{const label=document.createElement('span');label.style.color=colorOf(power);label.textContent='● '+act(power);legend.append(label)});
 const layers={},pos={},order=[];
 graph.names.forEach(id=>{const depth=graph.display[id].length;(layers[depth]??=[]).push(id)});
 const maxLayer=Math.max(1,...Object.values(layers).map(a=>a.length));
 Object.keys(layers).map(Number).sort((a,b)=>a-b).forEach(depth=>{
  const members=layers[depth];
  const average=id=>graph.parents[id].length?graph.parents[id].reduce((sum,p)=>sum+(pos[p]?.x||0),0)/graph.parents[id].length:0;
  members.sort((a,b)=>average(a)-average(b)||Number(a)-Number(b));
  members.forEach((id,index)=>{pos[id]={x:28+((maxLayer-members.length)/2+index)*36,y:26+order.length*62};order.push(id)});
 });
 const LX=28+maxLayer*36+24;
 svg.removeAttribute('viewBox');svg.setAttribute('width',LX+430);svg.setAttribute('height',order.length*62+35);
 const gl=el('g',{},svg),gs=el('g',{},svg);
 const choose=(id,parent)=>{
  const selection=selectUnlockStep(graph,unlockSelectedPath,unlockMapState,unlockPendingStep,id,parent);
  unlockSelectedPath=selection.route;unlockMapState=selection.mapState;unlockPendingStep=selection.pending;
  const path=unlockSelectedPath,selected=path.indexOf(Number(id));
  if(selection.mapChanged)show(D.nodes[unlockMapState]);
  const steps=unlockSteps(D.nodes,path,[...unlockHiddenPowers]),last=steps[Math.max(0,selected-1)];
  showUnlockPath(Math.max(0,powers.indexOf(last)),path,Math.max(0,selected),'');
  const pairs=new Set(path.slice(1).map((to,i)=>path[i]+'|'+to));
  svg.querySelectorAll('.unlock-segment').forEach(e=>e.setAttribute('opacity',pairs.has(e.dataset.from+'|'+e.dataset.to)?1:.2));
  gs.querySelectorAll('circle').forEach(e=>{const stop=Number(e.dataset.stop);e.setAttribute('fill',stop===unlockMapState?'#5fa8ff':stop===unlockPendingStep?'#f0a030':'#fff');e.setAttribute('opacity',path.includes(stop)||stop===unlockMapState?1:.45)});
  const status=document.getElementById('interaction-status');if(status)status.textContent=unlockPendingStep!==null?'Route updated. Click the same step again to show it on the map.':'';
  const panel=document.getElementById('unlock-path');
  if(graph.parents[id].length>1){const hint=document.createElement('p');hint.textContent='Same upgrades, different orders. Choose an arrival:';panel.append(hint);
   graph.parents[id].forEach(from=>{const button=document.createElement('button');button.textContent=act(gainOf(Number(from),Number(id))[0])+' after '+(D.nodes[Number(from)].abilities.map(nm).join(' + ')||'start');button.style.cssText='display:block;margin:4px 0';button.onclick=()=>choose(id,from);panel.append(button)});
  }
 };
 graph.links.forEach(e=>{const a=pos[e.from],b=pos[e.to],power=gainOf(Number(e.from),Number(e.to))[0],hypothetical=D.nodes[Number(e.from)].unplaced.includes(power);
  const middle=a.y+Math.min(18,(b.y-a.y)/3),d=`M${a.x},${a.y} V${middle} C${a.x},${middle+10} ${b.x},${middle+10} ${b.x},${middle+24} V${b.y}`;
  const path=el('path',{class:'unlock-line unlock-segment','data-from':e.from,'data-to':e.to,d,fill:'none',stroke:colorOf(power),'stroke-width':6,'stroke-linecap':'round',opacity:hypothetical?.35:1,style:'cursor:pointer'},gl);
  el('title',{},path).textContent=act(power)+' → '+D.nodes[Number(e.to)].abilities.map(nm).join(' + ');path.onclick=()=>choose(e.to,e.from);
 });
 order.forEach(id=>{const n=D.nodes[Number(id)],point=pos[id],merges=graph.parents[id].length>1,splits=graph.children[id].length>1;
  const label=(id===root?'Start · ':'')+(graph.display[id].length?graph.display[id].map(nm).join(' + '):'no abilities');
  const g=el('g',{class:'unlock-stop','data-node':id,role:'button',tabindex:0,'aria-label':label,style:'cursor:pointer'},gs);boxes[id]=g;
  el('line',{x1:point.x+10,y1:point.y,x2:LX-6,y2:point.y,stroke:'#34343f','stroke-width':1},g);
  el('circle',{class:'unlock-station','data-stop':id,cx:point.x,cy:point.y,r:merges||splits?8:6,fill:'#fff',stroke:merges?'#5fa8ff':'#16161c','stroke-width':merges||splits?4:3},g);
  el('text',{x:LX,y:point.y+1,style:'font-size:14px;font-weight:600'},g).textContent=label.length>32?label.slice(0,31)+'…':label;
  el('text',{x:LX,y:point.y+19,style:'font-size:11px;fill:#9a9aaa'},g).textContent=greenOf(n)+' rooms'+(merges?' · '+graph.parents[id].length+' arrivals':'')+(splits?' · '+graph.children[id].length+' next':'');
  g.onclick=()=>choose(id);g.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();choose(id)}};
  g.onmouseenter=()=>{tip.innerHTML=atip(Number(id));tip.style.display='block'};g.onmousemove=e=>{tip.style.left=(e.pageX+14)+'px';tip.style.top=(e.pageY+14)+'px'};g.onmouseleave=()=>tip.style.display='none';
 });
 const bounds=svg.getBBox();svg.setAttribute('width',Math.ceil(bounds.x+bounds.width+20));
 unlockMapState=Number(root);unlockPendingStep=null;unlockSelectedPath=[Number(root)];
 show(D.nodes[Number(root)]);
 const status=document.getElementById('interaction-status');if(status)status.textContent='';
 document.getElementById('unlock-path').replaceChildren();
}
document.getElementById('hide-unplaced').onchange=drawTop;
document.getElementById('hide-unavailable').onchange=drawTop;
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
 const index=D.nodes.indexOf(n),visible=activeUnlockGraph?.display[String(index)]||n.abilities;
 const options=activeUnlockGraph?(activeUnlockGraph.children[String(index)]||[]).flatMap(to=>gainOf(index,Number(to))):n.choices;
 const hidden=n.abilities.filter(p=>unlockHiddenPowers.has(p));
 const summary=visible.length?visible.map(nm).join(' + '):'Start';
 document.getElementById("map-selection").textContent=summary;
 document.getElementById("info").innerHTML=`<b>${escapeHtml(summary)}</b> &middot; available bosses / powerups: ${[...new Set(options)].map(act).map(escapeHtml).join(", ")||"none"}`+
  (hidden.length?`<br>Underlying reachability assumes hidden upgrades: ${hidden.map(escapeHtml).join(", ")}`:"")+"<br>"+
  ["g","o","p","r"].map(k=>by[k].length?`<span style="color:${C[k]}">${{g:"accessible rooms",o:"with skill",p:"not intended",r:"unreachable"}[k]}:</span> ${by[k].map(escapeHtml).join(", ")}`:"").filter(Boolean).join("<br>")}

const zsvg=document.getElementById("zgraph"),zcv=document.getElementById("zmap"),zcx=zcv.getContext("2d");zcv.width=cv.width;zcv.height=cv.height;
let routeGroupData;
const title=n=>routeGroupData?.groups[n]?.title||(D.rooms.find(r=>r.name==n)||{title:n}).title;

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
function groupRoutes(roomData,regions,n,start){
 const names=Object.keys(n.rooms),bosses=new Set(roomData.filter(r=>r.bosses?.length).map(r=>r.name));
 const required=r=>n.requirements?.[r]||[],signature=r=>required(r).join(',');
 const groupOf={},groups={},neighbors=Object.fromEntries(names.map(r=>[r,[]]));
 n.links.forEach(e=>{if(neighbors[e.from]&&neighbors[e.to]){neighbors[e.from].push(e.to);neighbors[e.to].push(e.from)}});
 names.forEach(seed=>{if(groupOf[seed])return;const id='group:'+seed,region=regions[seed]||seed,members=[],todo=[seed];groupOf[seed]=id;
  while(todo.length){const r=todo.pop();members.push(r);
   if(!bosses.has(seed))neighbors[r].forEach(next=>{if(!groupOf[next]&&!bosses.has(next)&&(regions[next]||next)===region&&signature(next)===signature(seed)){groupOf[next]=id;todo.push(next)}})
  }
  const boss=roomData.find(r=>r.name===seed);
  const splitRegion=names.some(other=>(regions[other]||other)===region&&!bosses.has(other)&&signature(other)!==signature(seed));
  const label=required(seed).length&&splitRegion&&boss?.title?boss.title:region+(required(seed).length?' · after '+required(seed).map(b=>b[0].toUpperCase()+b.slice(1)).join(' + '):'');
  groups[id]={title:bosses.has(seed)?boss.title||seed:label,rooms:members,boss:bosses.has(seed)};
 });
 const seen=new Set(),links=[];
 n.links.forEach(e=>{let from=groupOf[e.from],to=groupOf[e.to];
  const sourceBosses=roomData.find(r=>r.name===e.from)?.bosses||[];
  const closing=(roomData.find(r=>r.name===e.to)?.after_barriers||[]).filter(b=>sourceBosses.includes(b)||required(e.from).includes(b));
  if(closing.length){
   const continuation=n.links.find(next=>next.from===e.to&&closing.every(b=>required(next.to).includes(b))&&!roomData.find(r=>r.name===next.to)?.bosses?.length);
   if(continuation)to=groupOf[continuation.to];
  }
  const added=required(e.to).filter(b=>!required(e.from).includes(b)&&!sourceBosses.includes(b));
  if(added.length){const gate=roomData.find(r=>r.bosses?.includes(added[added.length-1]));if(gate)from=groupOf[gate.name]}
  const key=from+'|'+to;
  if(from&&to&&from!==to&&!seen.has(key)){seen.add(key);links.push({...e,from,to})}
 });
 return {groups,groupOf,rooms:Object.fromEntries(Object.keys(groups).map(g=>[g,'g'])),links,start:groupOf[start]};
}
function compactRoutes(original,start,keepRooms=[],all=false){
 const visible=new Set(original.names.filter(r=>all||r===start||original.children[r].length!==1||keepRooms.includes(r)||original.aliases[r]||Object.values(original.aliases).includes(r)));
 const children=Object.fromEntries([...visible].map(r=>[r,[]])),parent={},links=[],pos={},names=[];
 function connect(r,depth){names.push(r);
  original.children[r].forEach(first=>{let target=first;const via=[];
   while(!visible.has(target)){via.push(target);target=original.children[target][0]}
   children[r].push(target);parent[target]=r;
   const edge=original.links.find(e=>e.from===r&&e.to===first);
   links.push({from:r,to:target,direction:edge?.direction||'route',via});connect(target,depth+1);
  });
 }
 if(original.pos[start])connect(start,0);
 let leaf=0;
 function place(r,depth){children[r].forEach(c=>place(c,depth+1));const kids=children[r];
  pos[r]={x:kids.length?(pos[kids[0]].x+pos[kids[kids.length-1]].x)/2:30+230*leaf++,y:30+90*depth};
 }
 if(names.length)place(start,0);
 Object.entries(original.aliases).forEach(([copy,real])=>{if(pos[copy]&&pos[real])links.push({from:copy,to:real,sameStation:true,direction:'same station'})});
 return {...original,names,children,parent,links,pos,width:Math.max(500,leaf*230+40)};
}
// Graph 2 layout, like a git graph: one stop per row (top to bottom in route order), the first way on continues
// in the same column, every other way branches into a new coloured column; names in one column on the right.
function zones(raw){zsvg.innerHTML="";
 routeGroupData=groupRoutes(D.rooms,D.regions,raw,D.start);
 const n=routeGroupData,root=n.start;
 const names=Object.keys(n.rooms).filter(r=>n.rooms[r]==="g").sort();
 const links=n.links.filter(e=>names.includes(e.from)&&names.includes(e.to));
 const choiceRooms=Object.keys(n.groups).filter(g=>n.groups[g].boss);
 const tree=compactRoutes(routeTree(names,links,root,choiceRooms),root,choiceRooms,true);
 const real=x=>tree.aliases[x]||x;  // "same station" stubs stand for the stop they point to
 const reachOf={},reach=a=>{if(reachOf[a])return reachOf[a];const s=new Set([a]),todo=[a];
  while(todo.length){const x=todo.pop();links.filter(e=>e.from===x).forEach(e=>{if(!s.has(e.to)){s.add(e.to);todo.push(e.to)}})}return reachOf[a]=s};
 // rows (depth-first) and columns
 const row={},col={},order=[];let ncol=1;
 (function walk(r,c){row[r]=order.length;col[r]=c;order.push(r);
  tree.children[r].forEach((k,i)=>walk(k,i===0?c:ncol++))})(root,0);
 const showSame=document.getElementById("route-same").checked;  // dashed: the same stop shown twice
 const same=showSame?tree.links.filter(l=>l.sameStation&&row[l.from]!==undefined&&row[l.to]!==undefined):[];
 // where each column has a line: from its branch point down to its last stop (rows)
 const span={};order.forEach(r=>{const c=col[r],top=tree.parent[r]!==undefined&&col[tree.parent[r]]!==c?row[tree.parent[r]]:row[r];
  span[c]=span[c]?[Math.min(span[c][0],top),Math.max(span[c][1],row[r])]:[top,row[r]]});
 const busy=(c,rw)=>span[c]&&span[c][0]<=rw&&rw<=span[c][1];
 // each dashed link gets its own lane: in a gutter left of the lines or right of them (before the names),
 // whichever crosses fewer lines on its way out and back in
 const lanes=same.map(l=>{const a=row[l.from],b=row[l.to],ca=col[l.from],cb=col[l.to];let left=0,right=0;
  for(let c=0;c<ncol;c++){if(c<ca&&busy(c,a))left++;if(c<cb&&busy(c,b))left++;if(c>ca&&busy(c,a))right++;if(c>cb&&busy(c,b))right++}
  return right<left?"right":"left"});
 const nl=lanes.filter(v=>v==="left").length,nr=lanes.filter(v=>v==="right").length,LANE=9;
 const CX=26,RY=46,X0=18+nl*LANE,Y0=22,x=r=>X0+col[r]*CX,y=r=>Y0+row[r]*RY,LX=X0+(ncol-1)*CX+20+nr*LANE;
 zsvg.removeAttribute("viewBox");zsvg.style.width="";zsvg.style.height="";
 zsvg.setAttribute("width",LX+340);zsvg.setAttribute("height",Y0+order.length*RY);
 const colour=r=>LINE_COLORS[col[r]%LINE_COLORS.length];
 const gl=el("g",{},zsvg),gr=el("g",{},zsvg),gs=el("g",{},zsvg);
 order.forEach(r=>{if(tree.parent[r]===undefined)return;const p=tree.parent[r],px=x(p),py=y(p),cx=x(r),cy=y(r);
  const d=px===cx?`M${px},${py} L${cx},${cy}`:`M${px},${py} C${px},${py+RY*.6} ${cx},${py+RY*.1} ${cx},${py+RY*.7} L${cx},${cy}`;
  const e=tree.links.find(l=>l.from===p&&l.to===r),path=el("path",{d,fill:"none",stroke:colour(r),"stroke-width":7,"stroke-linecap":"round"},gl);
  const t=el("title",{},path);t.textContent=`${title(real(p))} → ${(e?.via||[]).map(title).concat([title(real(r))]).join(" → ")}${e?.direction?" ("+e.direction+")":""}`});
 let li=0,ri=0;
 same.forEach((l,k)=>{const ax=x(l.from),ay=y(l.from),bx=x(l.to),by=y(l.to),R=6;
  const lx=lanes[k]==="left"?X0-12-(li++)*LANE:X0+(ncol-1)*CX+14+(ri++)*LANE,dy=by>ay?1:-1,sx=lx<ax?-1:1,tx=lx<bx?-1:1;
  // out sideways, a rounded corner, along the lane, a rounded corner, back in to the other stop
  const d=`M${ax},${ay} H${lx-sx*R} Q${lx},${ay} ${lx},${ay+dy*R} V${by-dy*R} Q${lx},${by} ${lx-tx*R},${by} H${bx}`;
  const path=el("path",{d,fill:"none",stroke:"#c8c8d0","stroke-width":1.8,"stroke-dasharray":"5 4",opacity:.75},gr);
  const t=el("title",{},path);t.textContent="Same stop: "+title(real(l.to))});
 order.forEach(r=>{const kids=tree.children[r].map(k=>({to:k})),g=el("g",{style:"cursor:pointer"},gs);
  const lost=kids.filter(a=>kids.some(b=>b!==a&&!reach(real(a.to)).has(real(b.to)))).map(a=>title(real(a.to)));
  const choice=lost.length>0,same=!!tree.aliases[r];
  el("line",{x1:x(r)+10,y1:y(r),x2:LX-4,y2:y(r),stroke:"#34343f","stroke-width":1},g);
  el("circle",{class:"metro-station","data-room":real(r),cx:x(r),cy:y(r),r:choice?8:6,fill:"#fff",stroke:choice?"#16161c":colour(r),"stroke-width":choice?4:3},g);
  const t=el("text",{x:LX,y:y(r)+1,fill:same?"#9a9aaa":"#eee",style:"font-size:14px;font-weight:600"},g);t.textContent=(same?"↩ ":"")+title(real(r));
  const sub=el("text",{x:LX,y:y(r)+17,fill:choice?"#f0d060":"#9a9aaa",style:"font-size:12px"},g);
  sub.textContent=same?"already shown above":choice?`◆ choice: no way back from ${lost.join(" / ")}`:kids.length>1?`${kids.length} ways, you can come back`:"";
  g.onmouseenter=()=>{tip.innerHTML=`<b>${escapeHtml(title(real(r)))}</b><br>Rooms: ${(n.groups[real(r)]?.rooms||[real(r)]).map(title).map(escapeHtml).join(", ")}`+
   (kids.length?"<br>Ways on: "+kids.map(k=>title(real(k.to))).join(", "):"")+(choice?`<br><b>Choice</b>: no way back from ${lost.join(" / ")}.`:"");tip.style.display="block"};
  g.onmousemove=e=>{tip.style.left=(e.pageX+14)+"px";tip.style.top=(e.pageY+14)+"px"};
  g.onmouseleave=()=>tip.style.display="none";
  g.onclick=()=>zshow(raw,real(r))});
 document.getElementById("zhead").title=`Rooms grouped by region (bosses on their own). ${order.length} stops, one per row; a new colour is a branch. ◆ choice: an irreversible decision. Hover a stop for its rooms, click it for the map.`;
 zshow(raw,root);
}
document.getElementById("route-same").onchange=()=>zones(D.routes);
function zshow(n,room){
 const members=new Set(routeGroupData?.groups[room]?.rooms||[room]);
 zsvg.querySelectorAll(".metro-station").forEach(c=>c.setAttribute("fill",c.getAttribute("data-room")===room?"#5fa8ff":"#fff"));
 const links=n.links.filter(e=>n.rooms[e.from]==="g"&&n.rooms[e.to]==="g"),ahead=new Set(members),todo=[...members];
 while(todo.length){const r=todo.pop();links.filter(e=>e.from===r).forEach(e=>{if(!ahead.has(e.to)){ahead.add(e.to);todo.push(e.to)}})}
 zcx.clearRect(0,0,zcv.width,zcv.height);
 D.rooms.forEach(r=>{const col=members.has(r.name)?"#5fa8ff":ahead.has(r.name)?C.g:n.rooms[r.name]==="g"?C.r:"#44444f",ox=(r.x-minx)*S,oy=(r.y-miny)*S;
 zcx.globalAlpha=.35;zcx.fillStyle=col;zcx.fillRect(ox,oy,r.w*S,r.h*S);zcx.globalAlpha=1;
 for(let y=0;y<r.h;y++)for(let x=0;x<r.w;x++)if(r.tiles[y][x]==="1"){zcx.fillStyle="#2c2c36";zcx.fillRect(ox+x*S,oy+y*S,S,S)}
 zcx.strokeStyle=col;zcx.strokeRect(ox+.5,oy+.5,r.w*S-1,r.h*S-1)});
 document.getElementById("route-selection").textContent=title(room);
 const info=document.getElementById("zinfo");info.replaceChildren();const head=document.createElement("b");head.textContent=title(room);info.append(head);
 const list=document.createElement("p");list.textContent=[...members].map(title).join(", ");info.append(list);
}
function selectVisualization(view){
 document.querySelectorAll('[role="tab"]').forEach(button=>{const active=button.dataset.view===view;button.setAttribute('aria-selected',String(active));button.tabIndex=active?0:-1});
 document.querySelectorAll('.view-unlocks').forEach(card=>card.hidden=view!=='unlocks');
 document.querySelectorAll('.view-routes').forEach(card=>card.hidden=view!=='routes');
 document.querySelector('main').dataset.view=view;
}
document.querySelectorAll('[role="tab"]').forEach(button=>{
 button.onclick=()=>selectVisualization(button.dataset.view);
 button.onkeydown=event=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();const next=event.key==='Home'?'unlocks':event.key==='End'?'routes':button.dataset.view==='unlocks'?'routes':'unlocks';selectVisualization(next);document.getElementById('tab-'+next).focus()}};
});
drawTop();
zones(D.routes);
let hashState="";try{hashState=decodeURIComponent(location.hash.slice(1))}catch(error){hashState=""}
const fromHash=D.nodes.find(q=>q.id===hashState);  // e.g. progression.html#ape+dash
if(fromHash){unlockMapState=D.nodes.indexOf(fromHash);unlockSelectedPath=planUnlockRoute(activeUnlockGraph,unlockSelectedPath,unlockMapState);show(fromHash)}
selectVisualization("unlocks");
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
