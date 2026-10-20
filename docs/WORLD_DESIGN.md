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

**Scale:** the character's height becomes our player's 1.375 tiles (an 11 px hitbox).

| World | Source map | Scale | Rooms / door ends |
|---|---|---|---|
| Metroid Zero Mission (Zebes) | vgmaps in-game maps, 7 areas | Samus' standing hitbox is 2 blocks (mzm decomp `sSamusHitboxData`); a map tile is one 15×10-block screen (`minimap.c`) → 1 block = 0.69 tiles, a screen = 10.3×6.9 tiles | 383 / 628 |
| Symphony of the Night (Dracula's Castle) | vgmaps in-game map | Alucard's collision box is 47 px (sotn-decomp `g_SensorsCeilingDefault` −22 to `g_SensorsFloorDefault` +25); a map square = 256 px → 7.5×7.5 tiles | 273 / 570 |
| Hollow Knight (Hallownest) | hallownest.net (real screenshots) + wiki "Clean map updated" + Map Genie markers | Knight ≈ 1.3 units; 50 px of the hallownest.net map (full zoom, ~60 px per unit) = 1 tile (estimate) | 399 / 1402 |
| Silksong (Pharloom) | wiki "Silksong Full Map Clean" | same map drawing scale assumed as Hollow Knight, Hornet ≈ 1.6 units → 0.25 tiles/px (least certain) | 63 / 188 |

**Rooms are the originals, not a grid:**
- **Symphony of the Night / Metroid:** a room is a group of map cells with no wall between them, exactly as the map draws it.
- **Hollow Knight / Silksong:** a room is one area (each area has its own map color), cut into pieces only where it is bigger than 400 tiles (`Game.MAX_LEVEL_SIZE`).

Room boxes may overlap where one of them is rock. The overlap check and the map only count open space.
Edge exits pick the room that is open at that spot.

**Hollow Knight is built differently**, from three sources:
- **Terrain:** from hallownest.net, TheEmbracedOne's stitched map of real screenshots.
  - Foreground rock is pure black there, so black = rock and lit = open.
  - Lit space counts only inside a room of the in-game map. Each in-game-map area is registered onto the real map separately, because the in-game map is stylized and areas sit a few screens off.
  - This removes background art: vistas outside rooms (City of Tears rain backdrop, Howling Cliffs fog) and the in-game map's glow halos.
  - The Abyss and other unlit rooms in the lower map are nearly black even in the screenshots. There, the registered in-game-map shape is used instead, so they are open but have no real platforms inside.
- **Enemies, spikes, water, acid, breakables:** read visually from 342 zoom-7 crops of hallownest.net (about 41×41 tiles each).
  - About 1,120 enemy placeholders, 1,930 spike tiles, 106 acid and 9 water pools, about 440 breakables.
  - Species names are often guesses or descriptions. Lamps are marked breakable. Teal liquid was mostly marked acid, even in the Waterways where some is water. Spike directions on wall strips are approximate.
- **Map Genie markers** (mapgenie.io, exact positions): bosses, one marker per enemy species (journal entries), breakable surfaces, geo deposits and grub jars become placeholders; benches, stag and tram stations, vendors and hot springs become notes. A visually read item within 2 tiles of a Map Genie marker of the same kind is dropped as a duplicate.

**Doors (the "Door" object, cyan):**
- **What it does:** a rectangle with an `id` and a target `to` = `room:id`, or just `id` for a door in the same level. Touching it moves you to the target door, keeping your speed and your height in the doorway. You can't bounce straight back: the door you arrive on stays inactive until you step off it.
- **In the editors:** drag a rectangle with the Door tool, then type the id and target; click a door with the Door tool to edit it. The world editor draws every door link as a cyan line.
- **Linking places that don't touch:** elevators, trams, Metroid's elevators between areas, and shortcuts are not linked yet; add them with doors.
- **Generated doors:**
  - Symphony of the Night / Metroid: a 3-tile gap in the wall wherever the map shows a door, with a door object on each side.
  - Hollow Knight / Silksong: wherever two areas touch, or face each other across a wall 1–2 tiles thick (contacts longer than 12 tiles count as parallel corridors and are skipped). This is a guess, so expect some doors in the wrong place and some missing.

**Other notes:**
- The Metroid areas are placed the way the official guide map arranges them.
- A few notes name the start areas.
- The Inverted Castle is not included (it's the same castle upside down).

Source images, the scale reasoning and rebuild instructions are in `tools/reference_worlds.py`.
Rebuilding overwrites every room in those folders, including any edits.
