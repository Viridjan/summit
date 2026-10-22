# World design

The shipped adventure (`res://adventure/`): 14 rooms in 4 areas, each borrowing from one game.
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

# Reference worlds (`res://worlds/`)

There are four extra worlds, picked with **World:** in the Adventure menu. Each one has its own save, and each run starts with dash and climb.
They are room shapes traced from each game's full map, scaled so the player has the same size relative to the world as that game's character.
They are **not made playable**: there are no platforms inside the big rooms, no gates and no items.
Fix them by playtesting in the level editor and the world editor.

**Scale:** first matched by character height (the character's height becomes our player's 1.375 tiles), then **doubled**.
At the matched size the originals had too many passages only 1 tile tall. `SCALE` in the converter sets the factor.

| World | Source map | Matched scale (×2 applied) | Rooms |
|---|---|---|---|
| Metroid Zero Mission (Zebes) | vgmaps in-game maps, 7 areas | Samus' standing hitbox is 2 blocks (mzm decomp `sSamusHitboxData`); a map tile is one 15×10-block screen (`minimap.c`) → a screen = 10.3×6.9 tiles, ×2 | 134 rooms |
| Symphony of the Night (Dracula's Castle) | vgmaps in-game map | Alucard's collision box is 47 px (sotn-decomp `g_SensorsCeilingDefault` −22 to `g_SensorsFloorDefault` +25); a map square = 256 px → 7.5 tiles, ×2 | 48 rooms |
| Hollow Knight (Hallownest) | hallownest.net (real screenshots) + wiki "Clean map updated" + Map Genie markers | Knight ≈ 1.3 units; 50 px of the hallownest.net map (full zoom) = 1 tile (estimate), ×2 | 225 rooms |
| Silksong (Pharloom) | wiki "Silksong Full Map Clean" | same map drawing scale assumed as Hollow Knight, Hornet ≈ 1.6 units → 0.25 tiles/px (least certain), ×2 | 197 rooms |

**How rooms are made (all four worlds):**
- **Every passage is at least 2×2:** an open tile counts as navigable only inside a fully open 2×2 square. Rock is carved until every open tile is, and 2×2 spots that touch only at a corner or through a 1-tile-high gap are joined.
  - Rock that spikes sit on, and rock around pools, is never carved. A few narrow spots remain there.
- **One area per room:** a room never holds two open areas that don't connect inside it. Such a room is cut again between the areas. Tiny bits of a passage clipped off at a room's edge (under 160 tiles) become rock, and so do leftover slivers under 40 tiles.
- **No overlaps:** every world is cut into rectangles that never overlap. A piece is cut further while it is over 400 tiles a side (`Game.MAX_LEVEL_SIZE`), holds more than one separate region, or is mostly rock.
  - Cuts go along the line with the least open space, so they follow the map's natural walls.
  - No cut lands closer than 48 tiles to a piece's edge, so there are no thin strips that only slice through passing corridors.
  - A band of solid rock a screen thick inside a piece is always cut through, so one room never holds two passages with empty rock between them.
  - No cut leaves a scrap of open space behind.
  - Each room keeps one tile of the rock around it, so floors are inside the room.
  - Open space crossing a cut is an ordinary edge passage (green in the world editor).
- **Fewer disconnected rooms:**
  - Tiny isolated scraps (mostly icons drawn on the in-game maps) are dropped.
  - Hollow Knight / Silksong: two regions facing each other across a thin wall at 2 or more places are one map split by a line on the source map, so the wall is opened there. A single such contact becomes a door link.
  - Any group of rooms still cut off is linked to the rest with a door pair at their closest point. Example: Metroid's areas, which use elevators in the original.
  - A test checks that no boxes overlap and that every room is reachable from the start.
- **Symphony of the Night / Metroid:** blue cells (and green hidden cells in Metroid) are open space, white lines are walls 2 tiles thick, and door marks are gaps through them.
- The Metroid areas are placed the way the official guide map arranges them; a few notes name the start areas.
- The Inverted Castle is not included (it's the same castle upside down).

**Hollow Knight is built from three sources:**
- **Terrain:** from hallownest.net, TheEmbracedOne's stitched map of real screenshots.
  - Foreground rock is pure black there, so black = rock and lit = open.
  - Lit space counts only inside a room of the in-game map. Each in-game-map area is registered onto the real map separately, because the in-game map is stylized and areas sit a few screens off.
  - This removes background art: vistas outside rooms (City of Tears rain backdrop, Howling Cliffs fog) and the in-game map's glow halos.
  - The Abyss and other unlit rooms in the lower map are nearly black even in the screenshots. There, the registered in-game-map shape is used instead, so they are open but have no real platforms inside.
- **Enemies, spikes, water, acid, breakables:** read visually from 342 zoom-7 crops of hallownest.net.
  - About 1,130 enemy placeholders, 3,600 spike tiles, 107 acid and 9 water pools, about 440 breakables.
  - Species names are often guesses or descriptions. Lamps are marked breakable. Teal liquid was mostly marked acid, even in the Waterways where some is water. Spike directions on wall strips are approximate.
- **Map Genie markers** (mapgenie.io, exact positions): bosses, one marker per enemy species (journal entries), breakable surfaces, geo deposits and grub jars become placeholders; benches, stag and tram stations, vendors and hot springs become notes. A visually read item within 2 tiles of a Map Genie marker of the same kind is dropped as a duplicate.

**Doors (the "Door" object, cyan):**
- **What it does:** a rectangle with an `id` and a target `to` = `room:id`, or just `id` for a door in the same level. Touching it moves you to the target door, keeping your speed and your height in the doorway. You can't bounce straight back: the door you arrive on stays inactive until you step off it.
- **In the editors:** drag a rectangle with the Door tool, then type the id and target; click a door with the Door tool to edit it. The world editor draws every door link as a cyan line.
- **Linking places that don't touch:** Hollow Knight's trams and stag stations, and the exact elevator spots, are not linked yet; add them with doors. (Metroid's areas get one generated link each, at their closest point, not at the real elevator.)
- **Generated doors:**
  - Door objects remain only where a wall still separates two parts: a single thin-wall contact (Hollow Knight / Silksong), or a link added to reach a cut-off group. All other connections are open passages.

Source images, the scale reasoning and rebuild instructions are in `tools/reference_worlds.py`.
Rebuilding overwrites every room in those folders, including any edits.

**Hazards never cut the map** (checked with acid and spikes treated as walls):
- **Water and acid fill their basin:** every row of a pool runs wall to wall, never into rock or open air. A pool that would spill out of its room lowers its surface; one that can't be held at any level is removed (24 in Hollow Knight, mostly pools across a room boundary). Only a pool's top row draws the surface line.
- **Acid:** where an acid pool is the only way between two parts, or covers a door, it becomes water with a note: "Acid in the original (needs Isma's Tear)". In Hollow Knight, 13 of the 27 settled pools.
- **Unreachable rooms are deleted:** rooms you can't reach from the start (through open space and doors, acid as a wall) are removed with the doors into them: 7 in Hollow Knight, 4 in Silksong, 16 in Metroid.
- **Spikes:** a run of 5 or more floor spikes under a ceiling too low to jump over them is removed; a dash crosses shorter runs. Generated doors never go in acid, on spikes, or next to spikes.

**Entrance spawns:** every room gets a spawn marker near each entrance: an edge passage or a door. Each sits on the nearest ground with 2 tiles of headroom, away from hazards. When you enter a room, dying or **Retry** in the pause menu puts you back at the spawn nearest where you came in. Rooms with no floor, such as straight shafts, have none.
- `tools/world_fixups.py <world_dir>` adds them (marked `"entrance": true`) and replaces old ones. Before that it seals side and top edge openings that face no room or the next room's rock (they acted as invisible walls), settles water and acid, unblocks acid and deletes unreachable rooms (see above). The converter runs it after a rebuild; run it yourself after editing a world.

**Pits and holes:** an opening in a room's bottom edge shows red teeth when falling through kills (no room below), and cyan arrows when it leads to another room.

**King's Pass fixes** (`kings_pass()` in the converter, kept on rebuild):
- The 1-tile pillar in the bottom tunnel is removed.
- The top-right corridor ends in a Breakable Wall. Behind it, a tunnel slopes down into the cave that leads to Dirtmouth.

## Repeatable reference-world accessibility audit

Run from the repository root (Python 3, no extra packages or display needed):

```sh
python3 tools/world_accessibility.py worlds/hollow_knight --output reports/hk-automated
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
python3 tools/world_accessibility.py worlds/hollow_knight --strict topology --output /tmp/hk-check
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

## Runtime transition and boundary probes

```sh
godot --headless --path . res://tools/room_safety.tscn
godot --headless --path . res://tools/room_safety.tscn -- --phase replay --output res://reports/hk-room-safety-replays.json
python3 tools/check_side_openings.py
python3 tools/summarize_room_safety.py
```

`room_safety.tscn` defaults to the HK world. It uses the real player collision,
bounds, door-arrival and room-entry methods, with rendering/save writes disabled.
It sweeps all integer alignments along shared room edges (standing/crouched,
1/4/8px movement batches), doorway-contact offsets, and open outer edges.
`--phase edges`, `doors`, or `bounds` runs only one portion; `--phase replay`
runs five HK-specific failures through the actual 60 Hz player state machine.
`--world res://adventure/world.json --output /tmp/room-safety.json` selects
another world for the general sweeps. Exit code 1 means a failure was reproduced;
2 means invalid configuration or output, and 0 means no failure in that phase.
Run with disposable `XDG_DATA_HOME` if personal runtime settings must be isolated.

The runner seeds collision-free local positions; it does not establish routes
from the starting spawn. Cardinal probes do not exhaust diagonal motion, subpixel
remainders, states, moving geometry, or possible recovery inputs. The normal top
24px travel allowance and brief bottom fall-before-death are intentional and do
not count as escapes. Full-update replay JSON records every frame so a one-frame
escape is retained. General probes omit ordinary hazard touches; replays include
them. Static room collision data is cached, so these sweeps target static maps.

`check_side_openings.py` groups open left/right edge tiles into contiguous spans
that face either no room or a neighbour's wall. No-room openings are often safely
clamped by bounds, so they are distinct from confirmed out-of-bounds exploits.
The generated `reports/hk-room-safety.md` combines both audits and replay examples.
No map or gameplay fixes are applied by these tools.

## Active enemies in the HK world

93 reference placeholders have been replaced by 31 enemy types (three each) from eight
original families: Thornmite, Dropwing, Duskflit, Ossling, Hornback, Fuzzbob, and the big
Cragjaw and Murkspore. Each family comes in the variants that suit it (Swift, Armored, Giant,
Shielded, Brood, Venom). They occupy 56 rooms, including one introductory Thornmite in
King's Pass. The remaining reference enemy/boss markers retain their placeholder
behaviour. See [ENEMIES.md](ENEMIES.md) for controls, AI, tests, and how to reapply
these placements after rebuilding the reference terrain.

## Room environment artwork

A level's optional `environment` field selects `sand`, `sea`, `cavern`,
`cavern_deep`, `sky`, `temple`, or `building`. Omit it (or use an empty string)
for the original Paper Pixels terrain and backdrop. Unsupported values are
rejected by level validation. Saving and undo preserve this field.

The HK world uses all seven: rural buildings near the start, sky at the top,
sea in western rooms, sand in eastern rooms, temple rooms in the middle,
and deep cavern rooms below. Room geometry, entities and connections are
unchanged. `reports/hk-environment-themes.json` lists assignments;
`assets/themes/preview.html` includes a coloured room map and art previews.

`environment_art.gd` handles atlas edges, concave corners, decorative props
and two background layers. Each retained terrain chunk keeps its own theme,
including neighbouring rooms cached before a transition. The editor renders
the same theme and invalidates neighbouring chunks for concave caps and props.
The building theme depicts a rural settlement with timber/plaster walls,
pitched-roof cottages, fences, barrels, wheat and signposts.
