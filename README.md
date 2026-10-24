# Summit

A Celeste-style platformer in Godot 4 (tested on 4.4.1 and 4.7.2) with a built-in level editor.

Player physics are a GDScript port of Celeste's `Player.cs`
(MIT, Maddy Makes Games — https://github.com/NoelFB/Celeste).
Art: Paper Pixels (blue) by VEXED, CC0 — see `assets/paper-pixels/LICENSE.txt`.

## Play in the browser
https://viridjan.github.io/summit/ — built and published by `.github/workflows/pages.yml` on every push to `main`
(Godot web export, preset "Web" in `export_presets.cfg`). Click the game once so it gets keyboard focus.
In the browser, saves, options and your own levels are kept by the browser; the world editor and
"Add to Adventure" can't write the shipped files there, so do that work in the desktop version.

## Run
    sudo pacman -S godot
    godot --path . --import   # first time only: imports the sprite sheets
    godot --path .            # play
    godot -e --path .         # open in editor

## Controls (remappable in Options)
Arrows move · C/Space jump · X/Shift dash · Z/V grab · A attack (swings toward the held direction; F1 → `DASH_DIRS` / `ATTACK_DIRS` limit dash and attack to 0 off, 1 horizontal, -1 vertical, 2 four-way, 3 eight-way, 4 free aim) · Esc pause · M map · F1 state machine & tuning · F2 hitboxes. Gamepad: A jump · R1 dash · X attack · R2 grab · B back in menus (remap in Options → Controller Buttons).

## Moves
Run, variable jump, coyote time, input buffering, wall jump, wall slide, climb + stamina,
climb hop, 8-way dash, super/hyper jump, wavedash, super wall jump, corner correction, duck, fast fall.

## Objects
Spikes (4 dirs), springs (3 dirs), dash crystal, double-dash crystal, star (collectible), jump-through,
crumble block, falling block, zip mover, dream block, green/red bubble, bumper, feather, crystal heart (goal),
dash / climb ability orbs (adventure only), note (design reminder: "Needs double jump", "Boss arena"…;
its text shows in the editor, and in game while standing on it), door (drag a rectangle; links to another door by
"room:id" or "id": rooms that don't touch, elevators, shortcuts), water (looks only), acid (kills on touch),
enemy and breakable placeholders (named boxes, harmless, stand-ins until real ones are coded).
Breakable Wall: solid until hit 3 times with the attack (`hp` in the level file); stays broken for the run.

## Adventure
Title screen → Adventure → New Game / Continue. The adventure is one big world of connected rooms (Metroid style):
walk off a room's edge into the next one. You start without dash and climb; orbs in the world unlock them.
M shows every room explored so far. Progress saves automatically (`user://save.cfg`, section `[adventure]`).
The shipped world (14 rooms styled after Hollow Knight, Silksong, Symphony of the Night and Metroid Zero Mission)
is described in `docs/WORLD_DESIGN.md`; `tools/world_check.py` / `tools/world_softlock.py` check reachability and gates.
**World:** in the Adventure menu switches to one of two reference worlds in `res://worlds/` (Hallownest,
Zebes): the original rooms traced at each game's character scale and linked by doors, not yet playable;
the world editor edits the picked world (cyan lines = door links).

**World editor** (Adventure → World Editor, only when run from source because it writes `res://adventure/`):
drag rooms on the grid; where two rooms touch and both have open tiles on the shared edge, that's a passage (green).
"+ Add empty room" (placed right of the selected room) or "+ Add copy of my level", Edit room (opens the level editor; "World" goes back),
Playtest from here, Set as start. Files: `res://adventure/world.json` (room positions) + one level file per room.
Background and ideas for later (doors, gates, map stations, hurt states): `docs/METROID_NOTES.md`.

## Map and tuning (in-game, also in editor playtests)
M opens a full-screen map of the level (paused; wheel zoom, drag pan).
F1 opens the debug panel: the player's state machine (live state, transitions seen, recent log), live variables,
and every movement variable as an editable value. Edits apply immediately and survive respawns and playtests.
Save them as a named preset in `user://tuning/` (the last saved/loaded preset is active at startup);
"Export to project" writes `res://config/tuning.cfg`, the project-wide defaults (only when run from source).
"Pause sim" and "Step" advance the game one tick at a time. "Hitboxes" (also Options → Show Hitboxes) outlines the player (green), the sword swing (red) and objects (yellow/orange).

## Adding objects
See `docs/ADDING_ENTITIES.md`.

## Level editor
LMB paint/place (drag to size blocks; zip mover asks for a target click) · RMB erase ·
MMB or Space+drag pan · wheel zoom · Ctrl+Z undo · Ctrl+S save · F5 playtest.
Levels save as JSON in `user://levels/` (Linux: `~/.local/share/godot/app_userdata/Summit/levels/`).

## Combat enemies

The HK reference world includes 93 active enemies from eight original families:
Thornmite (wall crawler), Dropwing (ceiling dive), Duskflit (swoop), Ossling (bone
throw), Hornback (charge), Fuzzbob (bouncing flight), and the big Cragjaw (leaping
brute) and Murkspore (spore spitter). Attack with A; bones and orbs can be swatted
away. Each family comes in 2-4 variants (Swift, Armored, Giant, Shielded, Brood,
Venom); all 31 types are in the editor and on the Monsters page (main menu, or the map's second tab). See [behaviour and placement notes](docs/ENEMIES.md) and the
[animated sprite gallery](assets/enemies/preview.html).

## Tests
    godot --headless --path . res://tests/test.tscn    # physics checks, exit code = failures
    godot --headless --path . res://tests/smoke.tscn   # opens every screen
    godot --path . res://tests/bench.tscn              # benchmarks (see OPTIMIZATION_RESULTS.md)
