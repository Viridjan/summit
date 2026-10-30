# World design

**Regions** (2026-10-28): rooms are grouped into named, coloured regions, set in `world.json` (`"regions": [{"name",
"color", "rooms"}]`) and shown on the map screen and in the World Editor. Story regions: Meadow, Lake Caves, Cove Town,
Jungle, Treetop Village, Sand Cave, Lighthouse Coast, Island Shores, Volcano, Volcanic Maze (grouped by background,
with small rooms joined to the region they belong to in the story). Older notes below say "area" for the same idea.

**Island connections (2026-10-29):** Foothills opens directly into `i09_sea_cave`,
now named **Ash Passage**: a 46-tile-tall, climbable tunnel. Its upper shaft has
closely spaced jump-through rungs and a rest ledge; the preserved lower chamber
exits left into Junction. Every other Volcanic Maze room, including Serpent
Lair, moves with the tunnel while retaining its room-to-room offsets. The
separate `i18_ash_passage` room is removed. East Shore's old downward opening is
sealed, since the maze entrance is now below Foothills.

All four shores are 120 tiles long. Each has two wooden direction panels,
one for each neighboring shore; North Shore's original `coast_path` points to West
Shore. Stand nearby and press Interact to follow the named route. Opposite shores (North–South and East–West) have no direct panel; travel
through a neighboring shore. The panels
show cardinal arrows and destination labels. North and South Shore sit apart
on the world map rather than sharing vertical exits. West Shore still joins
Foothills, and East Shore still joins the eastern volcano slope. The extended
beaches include shallow pools and low stone shelves, with safe panel arrivals.
The post-Guardian West Shore retains all routes and its reward door.
`tools/story/link_shores.py` reapplies this network idempotently;
`tools/story/link_island_routes.py` also invokes it after maintaining the tunnel.

For seeded terrain shaping of authored areas, use
[`tools/morph_terrain.py`](../tools/morph_terrain.py). Presets include `cavern`,
`desert`, `coast`, `volcanic`, `forest` and `ruins`; it produces a before/after
report, with explicit apply and restore.
See [Terrain morphing](TERRAIN_MORPHING.md) for commands and research references.

The former Summit world (`res://adventure/`, removed 2026-10-25; still in git history): 14 rooms in 4 areas, each borrowing from one game.
This is a study from knowledge of the games, not from their data files; Metroid Zero Mission
details come from the decompilation notes in `METROID_NOTES.md`.

## What was borrowed

| Idea | From | Where |
|---|---|---|
| Rooms sized in whole screens (1 cell = 40x23 tiles = one screen), placed on a grid | Metroid, Symphony of the Night | every room |
| Quiet surface town, a well as the way down | Hollow Knight (Dirtmouth) | Ashen Village, Old Well |
| One-way drop you can only climb back up later | Hollow Knight | Old Well (climb back to the village) |
| Hub room with bench and map seller, branches leaving it | Hollow Knight (Forgotten Crossroads) | Crossroads Hall |
| First ability as a boss reward in an arena | Hollow Knight (False Knight) | Forgotten Arena (dash orb) |
| Tall vertical shaft with doors at the bottom | Metroid Zero Mission (Brinstar) | Root Shaft |
| Dead-end item room: one obstacle, one pickup | Metroid | Climb Vault (climb orb) |
| Item you can see but not reach yet | Metroid | Sunken Pit, Grand Corridor |
| Long castle corridor, clock tower, small save room | Symphony of the Night | Grand Corridor, Clock Tower, Save Room |
| Vertical climbing gauntlet, thorns, rest ledges | Silksong | Citadel Spire |
| Summit arena with the final reward | Silksong | The Crown (goal) |

## Map (world cells, x right, y down)

```
                        y-4   [s1 Spire][s2 Crown ......]
                        y-3   [s1      ]
                        y-2   [s1      ]
                        y-1   [k4 Save][k3 Battlements ......][k2 Clock]
y 0  [v1 Ashen Village ........]                              [k2      ]
y 1             [c1 Well][c2 Crossroads Hall ..][k1 Grand Corridor ......][k2 ]
y 2  [c3 Arena .][c1    ]     [b1 Shaft]
y 3                  [b2 Vault][b1     ][b3 Mossy Tunnel][b4 Pit]
```

## Route and gates

1. Village → drop down the well (one way) → Arena: **dash orb**.
2. Crossroads Hall: a 10-tile spike pit only a dash crosses. Past it: the hole down to the Root Shaft, and the castle.
3. Root Shaft → Climb Vault (another dash pit): **climb orb**. Climb the stepped pillar back up to the Crossroads.
4. Castle: corridor → clock tower (jump-through ladders) → battlements. The opening to the spire starts 19 tiles above the floor:
   jump, dash up, grab, climb. That is out of reach for wall-jump chains, and there is no second wall to wall-jump between.
5. Spire: climb from rest ledge to rest ledge (18 apart), then walk into the Crown: **goal**.

Gate sizes come from the movement code:

| Move | Reach |
|---|---|
| Jump | about 3.5 tiles up, a gap of about 7 tiles running |
| Jump + dash | about 8 tiles up, a gap of about 13 tiles |
| Climb | about 13 tiles per stamina bar |

## Notes (the "Note" object)

The yellow "!" object holds a design note. In the editor, the text shows above the note; click a note with the Note tool to edit it.
In the game, the text appears at the bottom of the screen while you stand on it.
The shipped world uses notes for everything not built yet:
- benches, save and map stations;
- boss arenas and the lantern;
- an elevator shortcut and enemy patrols;
- a breakable wall and a clock-face shortcut;
- double jump and acid immunity, each guarding a visible star.

## Checking a changed world

```sh
python3 tools/world_check.py adventure      # rooms reached per ability set, two movement models
python3 tools/world_softlock.py adventure   # dash orb -> climb orb -> goal, from every reachable spot
```

The checkers model the player on whole tiles. They use two models:
- **cautious** (weaker jumps than the real player): when it reaches a spot, so does the real player;
- **generous** (stronger): when even it can't reach a spot, that gate holds.

What the checkers don't model:
- springs, bubbles and moving blocks;
- the real stamina numbers;
- expert tech such as hyper and wave dashes. Like Metroid, the world can be sequence-broken by experts.

`world_softlock.py` assumes the order dash → climb → goal; edit `stages` there if that changes.

## Doors (the "Door" object, cyan)

- **What it does:** a rectangle with an `id` and a target `to` = `room:id`, or just `id` for a door in the same level. Touching it moves you to the target door, keeping your speed and your height in the doorway. You can't bounce straight back: the door you arrive on stays inactive until you step off it.
- **In the editors:** drag a rectangle with the Door tool, then type the id and target; click a door with the Door tool to edit it. The world editor draws every door link as a cyan line.
- The story world's net trap uses one as a stand-in for the net lift.
- **House Door** (`house_door`): the same link, drawn as a wooden door, and it only works when you stand at it and press up (a ▲ prompt shows). Cove Town's houses use them.

## Repeatable world accessibility audit

Run from the repository root (Python 3, no extra packages or display needed):

```sh
python3 tools/world_accessibility.py worlds/story --output /tmp/story-accessibility
```

The checker writes Markdown, JSON, and a PNG map. It validates door references and
runs four flood-fill models from the configured starting room: topology without
hazards, acid excluded, acid plus spikes excluded, and two-tile standing clearance
with both hazard types excluded. It lists completely unreached rooms and partially
reached rooms. JSON includes marker names, world tile origins, and sample unreached
local tile coordinates. The map uses green for standing clearance, blue for
crouch-only clearance, amber for routes blocked by the hazard approximation, and
red for disconnected terrain. Map coordinates start at the world's minimum room
origin minus one tile in each direction.

For automated regression checks:

```sh
python3 tools/world_accessibility.py worlds/story --strict topology --output /tmp/story-check
python3 -m unittest discover -s tests -p 'test_world_accessibility.py'
```

Exit codes: 0 means the requested checks passed (or an informational audit completed),
1 means the selected `--strict` model found unreached rooms, partial regions, or an
invalid spawn, and 2 means invalid input or broken door references. Without `--strict`,
hazard flags are informational and do not fail the command.

This is **not a physics solver or playthrough bot**. It permits unlimited movement
in every direction, ignores stamina and ability progression, and assumes breakable
walls are already broken. Hazard footprints are rounded outward to full tiles;
spike direction and precise collision shapes are ignored. Standing clearance uses
an 8×16px tile envelope around the 8×11px hitbox. Door arrivals are optimistic;
return paths and exact offsets are not checked. Temporary movement above room tops
is omitted. It rejects overlapping room rectangles instead of guessing which room
owns them. Use the flagged routes to choose real Godot movement tests, rather than
treating these results as proof that rooms can or cannot be played through.

## Fundamental rule: respawn points are never in a hazard

A respawn point must be safe: the player standing there is out of water and acid, clear of spikes, and on
ground (World.safe_spawn). Entering a room picks its nearest safe spawn marker, else the entry point if that is
safe. A room with no safe point (flooded, like Deep Lake, or entered mid-air) gets none: the last safe
respawn stays, even in the previous room, and the save keeps it; dying there sends the player back to it.
Hazardous rooms therefore need no spawn of their own, and must never be given one inside the hazard. The tests
check every spawn marker of every story room against this rule.

## Walking in after a room change

Crossing into a room sideways walks the player 1 unit in: to the middle of the room's second tile
column (12 px from the edge), where the entrance spawn sits, and they respawn there
(`World.enter_room`; vertical crossings don't walk). So every sideways entrance must be flat for
its first two tiles on both sides: floor (or a jump-through) at the doorway's floor row, two tiles of
headroom, no spikes or acid. `python3 tools/check_entrances.py worlds/story` lists the ones that
aren't; `tests/test_story_entrances.py` keeps the story world at zero.

## Runtime transition and boundary probes

```sh
env XDG_DATA_HOME=/tmp/summit-rs godot --headless --path . res://tools/room_safety.tscn
env XDG_DATA_HOME=/tmp/summit-rs godot --headless --path . res://tools/room_safety.tscn -- --phase replay --output res://reports/story-room-safety-replays.json
python3 tools/check_side_openings.py
python3 tools/summarize_room_safety.py
```

All four default to the story world. `room_safety.tscn` uses the real player collision, bounds,
door-arrival and room-entry methods with rendering and save writes disabled. It sweeps every integer
alignment along shared room edges (standing and crouched, 1/4/8 px steps), doorway contact offsets and
open outer edges; `--phase edges|doors|bounds` runs one part, and `--phase replay` runs three seeded story
spots (Cove Tunnel into Cove Town, the net-trap door, the Meadow's open sky) through the 60 Hz state
machine. `--world <path>/world.json --output /tmp/other-safety.json` checks another world.
Exit code 1 = a failure was reproduced, 2 = bad configuration, 0 = none found.

`check_side_openings.py` groups open left/right edge tiles that face no room or a neighbour's wall
(usually harmless: the boundary clamps, or the player meets rock); `summarize_room_safety.py` combines
everything into `reports/story-room-safety.md`. Last run: no escapes or embeds in ~12,000 edge crossings,
~2,000 door arrivals and ~8,000 boundary probes; 7 side openings (3 facing a neighbour's rock, 4 on the
Lighthouse Top's open-sky edges).

## Room environment artwork

A level's optional `environment` field selects `sand`, `sea`, `cavern`,
`cavern_deep`, `sky`, `temple`, `building`, or `forest`. Omit it (or use an empty string)
for the original Paper Pixels terrain and backdrop. Unsupported values are
rejected by level validation. Saving and undo preserve this field.

The story world uses sky, cavern_deep, sea, forest and sand; `forest` is the jungle's.
`assets/themes/preview.html` shows every theme.

`environment_art.gd` handles atlas edges, concave corners, decorative props
and two background layers. Each retained terrain chunk keeps its own theme,
including neighbouring rooms cached before a transition. The editor renders
the same theme and invalidates neighbouring chunks for concave caps and props.
The building theme depicts a rural settlement with timber/plaster walls,
pitched-roof cottages, fences, barrels, wheat and signposts.

**Volcanic Maze cavern pass (2026-10-29):** Applied `morph_terrain.py` with
`--terrain cavern --region "Volcanic Maze" --seed 42` at default intensity 0.45.
The protected contour pass carved 10 tiles in Ash Passage and 2 in Junction;
the other eight rooms retained their protected geometry. Authored routes,
room positions, objects and volcanic cave artwork are preserved. Before/after
report and exact restore backup: `reports/terrain-morph/volcanic-maze-cavern/`.

**Room enemy budgets (2026-10-29):** Room JSON supports `enemy_count`: `-1`
(or omitted) uses automatic open-space density; `0` disables generated enemies;
a positive integer requests that many generated enemies. Edit it under
“Enemies (-1 = automatic)” in the room editor and save before building drafts.
`build_drafts.py` runs population after terrain, edge sealing and entrance
spawns, restricted to the newly built rooms. Direct `tools/populate.gd` runs
also honor the setting (`--rooms room_a,room_b` restricts population).
Safe spacing, available standing surfaces, peaceful regions and boss exclusions
still limit placement. Hand-placed enemies are retained separately from this
generated budget. Existing built rooms are not repopulated by Build drafts.

**Connected-room editing (2026-10-29):** When editing a world room, the palette
shows “Connected rooms” buttons for matching open borders and valid outgoing
door/panel destinations. Switching a dirty room asks Save / Don't save / Cancel.
Save failures retain the current room and edits. Switching loads the destination
with its own filename, clears undo/selection and centers the camera.

**Room editor framing (2026-10-29):** Opening the editor or following a
connected-room button fits the entire room inside the workspace beside the
palette. Outside-room scenery and terrain fringes are masked with the plain
editor backdrop, including while panning or zooming.

**Progression report graphs (2026-10-29):** Graph 1 enumerates boss/powerup
states and the union of rooms reachable with each state, including all route
alternatives. Graph 2 preserves direct room exits and return links instead of
merging reversible rooms into zones: a left/right fork remains a choice even
when both branches are accessible. Selecting an unlock state updates the route
graph. Unplaced powerups are optional unchecked assumptions.

**Rooted route visualization:** Graph 2 keeps the starting room as its root,
centers shared approaches above their branches, and splits solid paths at
choices. Return/cross-links are faint dashed arrows. Defeated-boss forks can
reference an earlier room as a branch leaf, preserving the Ape’s left/right
choice without duplicating whole routes or creating infinite loops.

The rooted choices graph retains metro styling: thick colored routes, circular
stations and dark interchange rings at forks; return links stay dashed.

**Independent progression graphs:** Graph 1 selects boss/powerup accessibility
states. Graph 2 independently displays world route topology with modeled gates
open. Neither graph’s selection changes the other graph or its map. Both retain
metro styling and Graph 2 retains the rooted branching layout.

The route metro graph uses the full page width and fits its actual SVG content
bounds, including labels and return curves. Fit/zoom controls and a dedicated
scrolling viewport keep branches accessible on smaller screens.

**Respawn density (2026-10-29):** Generated entrance markers are capped at one
per ordinary room, two in rooms at least 80 tiles wide or 40 tiles tall. Authored
checkpoints are preserved and count toward the cap. Generated points stay at
least eight tiles apart; the second favors the far end. Both `add_spawns` and
the shore-link generator apply this policy. The cleanup backup and safety audit
are in `reports/respawn-review/`; room terrain and other objects were retained.

**C1 respawns (2026-10-30):** Lake Cave has three authored floor respawns,
covering its left, right and central entrances: (8,328), (224,328), (160,328).
The intermediate upper marker is removed. Authored status preserves these
three points through entrance regeneration and density pruning.

**Editor input and hover help (2026-10-30):** Palette, toolbar and map-menu
panels consume wheel input so menu scrolling cannot zoom the underlying canvas.
Room-editor controls and palette tools have hover explanations. Manually placed
and pasted Spawn markers preserve other markers in the room; right-click removes
one, and Undo restores edits.

**Playtest and checkpoint visibility (2026-10-30):** Room Playtest accepts a
Spawn or Respawn marker. Without either, it uses a temporary safe floor start
that is never added to the editable/saved room; if none exists it explains what
to place. Respawn slabs retain their touch behavior but draw and describe
themselves only in editor previews, remaining invisible during play.

**Unified respawn tool (2026-10-30):** The room editor exposes a single Respawn
tool with the original white player outline and red head. Both saved `spawn`
and legacy `respawn` types use the same checkpoint behavior. Walking onto one
updates the respawn silently, without particles, hover text or in-game artwork.

**Checkpoint cleanup (2026-10-30):** Unified `spawn`/`respawn` markers are
reviewed together. Overlapping aliases and points not needed by distinct
entrances are removed; c1 retains exactly its three floor checkpoints. The
world start is preserved. `tools/prune_respawns.py` previews changes by default,
with `--apply` saving originals in `reports/respawn-cleanup/backup.json`. Entrance
generation respects existing authored checkpoint sets rather than adding a
second set, and new rooms use entrance coverage instead of a fixed room cap.

**Solid-ground checkpoints (2026-10-30):** Suspended jump-through platforms
do not count as checkpoint ground. Twelve affected points were moved onto safe
terrain. Placement skips platforms and searches for permanent floor; runtime
checkpoint activation requires solid terrain below the full standing footprint.

**Shared checkpoint landings (2026-10-30):** Nearby entrances may share one
checkpoint when a flat, hazard-free walk of at most six tiles connects them.
Both endpoint checkpoints must have permanent terrain support; fixed bridges
may support the walk. C6 retains its right `(160,48)` and distant left `(8,48)`
points; the intermediate `(120,48)` point is removed. This supersedes the
earlier fixed room caps. See [Respawn placement](RESPAWN_POINTS.md) for the
automation command, conservative merge rules and backup behavior.

**Grouped metro graph (2026-10-30):** Graph 2 now groups connected non-boss
rooms within each named region into one stop, with the room list on hover and
in the selected-group map details. Boss arenas remain distinct so their route
choices remain visible. The default view has 14 stops for the 47-room dataset
and fits both width and height. Dashed lines ONLY join repeated appearances of
the same group; they are identity links, never travel/return routes. Both
graphs remain independent. This supersedes the earlier per-room rendering and
return-link dash notation.

**Boss-aware region grouping:** Metro groups never mix rooms with different
mandatory boss requirements. Post-Ape Jungle Depths and Net Trap are separated
from the early Jungle, keeping Treetop Village downstream of the Ape. Graph 2
remains a static, independent diagram; boss-gated branches attach at the boss
stop instead of appearing as ungated shortcuts from an aggregated region.

**Ape return barrier (2026-10-30):** Beating the Ape grows a permanent thorn
barrier at Jungle Hills x368, from the roof to the floor immediately left of
the Depths shaft. The approach is open before the fight. Afterwards the early
Jungle cannot be reached from the arena, while Jungle Depths (and Treetop Village)
and Sand Cave remain available. The barrier persists through saves and room
reloads using the existing boss flag; dash, climb and attack cannot bypass it.
`boss_gate` supports `after` as the inverse of `until`. Progression searches
continue from defeated-boss arenas and include post-fight barriers, rather than
restarting behind a sealed route. The graph labels the post-fight Jungle group
Jungle Depths and treats the right-hand Hills corridor as its connector.

**Graph 1 original metro layout restored:** All ability combinations and
reachable boss-defeated states appear together as stations on colored order
lines. Repeated states are joined by dashed identity connectors. Blocking
events such as Ape beaten and Guardian beaten are explicit stops. Hypothetical
unplaced powerups have faint segments; Graph 2 remains independent and unchanged.

**Explicit Graph 1 choices:** Hovering a colored segment names its action.
Clicking a segment, station on a particular line, or line number selects that
route and displays its ordered powerup/boss steps below the chart. “Choice made”
names the clicked transition; later steps are dimmed. Paths that reach the same
ability set through different orders remain distinct. Graph 2 is unchanged.

**Rooted Graph 1 (2026-10-30):** The unlock chart now uses Graph 2’s branching
metro style: one shared start, continuous colored lines, and a new branch for
each ability/boss choice. Stops name the action and resulting state. Selecting
a stop displays the actual order along its branch. Optional dashed connectors
join identical states reached by different orders; they are not transitions.
Graph 2’s layout and selection remain independent.

**Merged upgrade stations:** Graph 1 now has exactly one station per sorted
set of owned abilities and defeated bosses. Different acquisition orders
converge at that shared station instead of creating duplicate stops or dashed
identity connectors. Each upgrade/boss action has a consistent line color.
Incoming paths retain their action and order; shared stations offer arrival
buttons to select the order explicitly. This reduces 24 displayed stops to 14
unique states while retaining one root and all branches. Graph 2 is unchanged.

**Graph 1 condition switches:** Hide unplaced conditions removes transitions
for missing pickups and states that depend on them. Hide unavailable steps
keeps only conditions normally reachable from the immediately preceding state;
blocked prerequisites and skill/exploit-only steps are excluded. Later boss
steps remain when a valid prerequisite path reaches them. Both switches default
to off, compose independently, retain the root, and affect only Graph 1. A status
line explains when no achievable next step remains under the active filters.

**Unplaced-filter correction:** Hide unplaced now collapses those pickup
steps and merges the resulting visible states; it does not delete later boss
conditions. Reachability checks still use the underlying states, so an Ape
condition reachable after a hidden dash step remains visible. This supersedes
the earlier rule that removed entire dependent paths. The unavailable-step
filter still checks each actual boss transition against its prerequisite state.

**World Editor progression integration (2026-10-30):** Progression saves the layout
and launches background snapshot analysis. The browser viewer has independent tabs
and a dominant map, with explanations in hover hints and compact details. See
[the current guide](PROGRESSION_REPORT.md) for navigation and filter semantics.
