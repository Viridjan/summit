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

## Doors (the "Door" object, cyan)

- **What it does:** a rectangle with an `id` and a target `to` = `room:id`, or just `id` for a door in the same level. Touching it moves you to the target door, keeping your speed and your height in the doorway. You can't bounce straight back: the door you arrive on stays inactive until you step off it.
- **In the editors:** drag a rectangle with the Door tool, then type the id and target; click a door with the Door tool to edit it. The world editor draws every door link as a cyan line.
- The story world's net trap uses one as a stand-in for the net lift.

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

## Walking in after a room change

Crossing into a room sideways walks the player 1 unit in: to the middle of the room's second tile
column (12 px from the edge), where the entrance spawn sits, and they respawn there
(`World.enter_room`; vertical crossings don't walk). So every sideways entrance must be flat for
its first two tiles on both sides: floor (or a jump-through) at the doorway's floor row, two tiles of
headroom, no spikes or acid. `python3 tools/check_entrances.py worlds/story` lists the ones that
aren't; `tests/test_story_entrances.py` keeps the story world at zero.

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
