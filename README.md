# Summit

A Celeste-style platformer in Godot 4 (tested on 4.4.1 and 4.7.2) with a built-in world editor.

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
Arrows move · C/Space jump · X/Shift dash · Z/V grab · S interact (house doors) · A attack (swings toward the held direction; F1 → `DASH_DIRS` / `ATTACK_DIRS` limit dash and attack to 0 off, 1 horizontal, -1 vertical, 2 four-way, 3 eight-way, 4 free aim) · Esc pause · M map · F1 state machine & tuning · F2 hitboxes · F12 assist mode. Gamepad: A jump · R1 dash · X attack · R2 grab · B interact, back in menus (remap in Options → Controller Buttons).

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
**World:** in the Adventure menu switches to the story world (`res://worlds/story/`, chapter 1 in progress, see
`docs/STORY_DESIGN.md`); the world editor edits the picked world (cyan lines = door links).

**World editor** (main menu → World Editor, only when run from source because it writes `res://adventure/`):
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

Nine original enemy families:
Thornmite (wall crawler), Dropwing (ceiling dive), Duskflit (swoop), Ossling (bone
throw), Hornback (charge), Fuzzbob (bouncing flight), and the big Cragjaw (leaping
brute) and Murkspore (spore spitter), plus the story jungle's calm Mosstrot (wanders, never chases). Attack with A; bones and orbs can be swatted
away. Most families come in 2-4 variants (Swift, Armored, Giant, Shielded, Brood,
Venom); all 32 types are in the editor and on the Monsters page (main menu, or the map's second tab). See [behaviour and placement notes](docs/ENEMIES.md) and the
[animated sprite gallery](assets/enemies/preview.html).

## Tests
    godot --headless --path . res://tests/test.tscn    # physics checks, exit code = failures
    godot --headless --path . res://tests/smoke.tscn   # opens every screen
    godot --path . res://tests/bench.tscn              # benchmarks (see OPTIMIZATION_RESULTS.md)

### Music Studio (prototype)

Open **Music Studio** from the main menu and press **Play** to hear an original
four-channel chiptune loop. Click steps to cycle through rests and C-major notes;
choose pulse, triangle, saw, synthesized percussion, or FM piano per channel.
Tempo, volume, and channel mute controls are available. Pattern/instrument/tempo
edits restart playback; volume changes apply immediately. Back or Esc stops music.
Edits survive returning to the menu during the current session, but are not yet
saved to disk. This first version is a synth/sequencer; automatic composition and
gameplay-driven music are future work.

The bundled GDSiON 0.7-beta8 runtime currently supports **Linux x86_64**. Other
platforms need matching upstream binaries; see `addons/gdsion/README.md` for
provenance, licenses, and integration notes. Run the audio and lifecycle checks:

```sh
godot --headless --path . --script tests/music.gd
```

### Environment soundtrack

Gameplay now follows each room's background (`environment`). Nine original
8-bar chiptune arrangements cover mountain/default, forest, sand, sea, cavern,
deep cavern, sky, temple and village/building. Rooms with the same environment
continue the current loop; entering a different environment starts its theme.
Leaving gameplay stops music. The studio shares the gameplay volume control.

In **Music Studio**, select a named environment to hear its arrangement against
its background. Use **Steps … >** to browse all four pages of a 64-step score.
Selecting a theme replaces the current working pattern; Reset demo restores the
short demo. Theme changes currently restart immediately, without crossfading.
The compositions use adventure-game moods, modal melodies and chip instruments;
no Zelda melodies, recordings or samples are included.

Scores live in `scripts/environment_music.gd`. Each defines a key/mode, tempo,
instruments, chord progression and two original phrases, arranged as A/B/A'/B'.
Run the soundtrack rendering and selection checks with:

```sh
godot --headless --path . --script tests/environment_music.gd
```

### Sound effects

Original retro sound effects are synthesized and cached at startup in `scripts/sfx.gd`. Movement, combat, enemy warnings/projectiles, the Ape boss, pickups, doors, notes, blocks, and menu buttons trigger effects independently of the music synth. Options → Audio → Sound effects controls their volume (including Off). Playback uses a 16-voice pool and suppresses duplicate bursts. No external sound files or licenses are required.

Run audio checks with `godot --headless --path . --script tests/sfx.gd`.
