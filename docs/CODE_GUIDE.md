# Reading the Summit code

You do not need to understand every file at once. Summit has three main jobs: run a room, edit a room, and arrange rooms into a world. Most files serve one of those jobs. The comments in the first-party source explain their responsibilities and individual functions; this guide connects them.

## Start here

1. Open `scripts/main.gd`. This is the small entry point attached to `main.tscn`.
2. Read the header and screen-switching functions in `scripts/game.gd`.
3. Read `scripts/world.gd`: start with `_ready()`, `_build()` and `_physics_process()`.
4. Read `scripts/player.gd`: start with its state/position comments, then `update()`, `_state_update()` and `_set_state()`.
5. In `scripts/entities.gd`, read `TYPES`, `make()` and the base `Ent` class. Then choose one simple object, such as `Refill`, before reading an enemy or the Ape.
6. Read the `check()` helper and one test in `tests/test_runner.gd` to see how expected behavior is demonstrated.

A leading underscore usually marks an internal/helper function. Some underscore functions, such as `_ready()` and `_process()`, are Godot callbacks: the engine calls them automatically. In contrast, an entity's `update()`, `touch()` and `draw()` are project conventions: `World` must call them explicitly.

## How one frame works

`main.tscn` creates the root → `main.gd` registers it with `Game` → `Game.goto("menu")` opens the menu. A play action selects level data and creates the `World` screen.

During gameplay, `World._physics_process()` advances the simulation. The player reads actions, updates timers and chooses its movement state. That state computes velocity; the movement helpers convert velocity × elapsed seconds into whole-pixel steps. Each step checks terrain and relevant objects. Contacts can activate pickups, damage the player or request a door transition. World finishes deferred operations at a safe point, updates objects and camera, and requests fresh drawing.

Drawing displays the resulting positions. It should not decide whether a sword hits, a wall blocks movement or an item is collected. Those decisions belong in the simulation. This separation makes the same behavior testable without a visible window.

The physics timestep is 1/60 second. `_process()` follows the display/frame rate and is used for presentation, loading work and UI updates. A paused World stops its own simulation; the entire Godot application is not necessarily paused, so menus and other nodes can keep processing.

## Coordinates, speed and time

| Value | Meaning | Example |
| --- | --- | --- |
| Tile | A terrain cell, 8 × 8 game pixels | Tile `(3, 5)` begins at pixel `(24, 40)` |
| Room pixels | Coordinates within one room | The room top-left is `(0, 0)` |
| World pixels | Coordinates across the adventure layout | `room_origin + local_position` |
| Screen pixels | Where something appears after camera/zoom transforms | A mouse click starts in screen coordinates |
| `dt` | Seconds advanced by one simulation update | Usually `1.0 / 60.0` |
| Velocity | Pixels travelled per second | `speed.x = 90` gives about 1.5 pixels per normal physics step |
| Acceleration | Change of velocity per second | Gravity adds downward velocity over time |
| Timer | Seconds remaining before something ends | A positive dash cooldown blocks another dash |

Positive X points right. Positive Y points down, so a negative vertical velocity rises.

`Player.pos` is the bottom centre of the movement box, near the feet. An entity's `rect.position` is its rectangle's top-left. Do not substitute one for the other without converting the anchor.

`rem` keeps fractional movement. For example, four steps of 0.25 pixel must add up to one whole pixel rather than disappearing through rounding. Integer positions keep collision behavior and pixel artwork consistent.

## The boxes have different jobs

- **Movement box (`hitbox`)**: stops the player from going through solid terrain.
- **Interaction box (`hurt_rect`)**: used by interactions such as pickups.
- **Damage box (`damage_rect`)**: a smaller, forgiving target for lethal hazards and enemies.
- **Entity `touch_rect()`**: the area in which that object's interaction activates.
- **Visual bounds (`vis_rect`)**: includes sprite overhang and effects so off-screen culling does not hide visible artwork.

Culling means skipping drawing when nothing from an object is visible. A large visual rectangle should not make the player take damage farther away. Conversely, a sprite's transparent pixels do not automatically create a physical opening: collision reads boxes or explicit shapes, not the image.

`Rect2i` uses whole-number coordinates; `Rect2` permits fractions. `Vector2` stores an X/Y pair. A direction vector and a velocity both use that type, but have different meanings: a unit direction chooses where, while velocity also includes how fast.

## Who owns what

| File | Responsibility |
| --- | --- |
| `main.gd` | Root entry point and screen host |
| `game.gd` | Persistent settings, input bindings, audio access, files, saves and screen switching |
| `world.gd` | Current room simulation, object lists, camera, transitions and in-game overlays |
| `player.gd` | Player movement, collision response, sword and visual state |
| `entities.gd` | Placed object registry and individual object/enemy behavior |
| `adventure.gd` | World-layout queries, progress normalization and energy rules |
| `editor.gd` | Editing the tiles and objects in one room |
| `world_editor.gd` | Positioning room files and displaying their connections |
| `options.gd`, `menu.gd` | Settings and navigation interfaces |
| `debug_panel.gd`, `tuning.gd` | Live movement inspection, configurable values and presets |
| `map_view.gd`, `bestiary.gd` | Read-only map and enemy catalogue |
| `touch_controls.gd` | Translate touch gestures into ordinary input actions |
| `art.gd`, `*_art.gd` | Generate/cache/draw artwork, independently of collision |
| `tile_layer.gd` | Cache terrain drawing in chunks, rebuilding only affected regions |
| `audio.gd` | Shared bus-volume conversion and 16-bit PCM stream construction |
| `sfx.gd` | Synthesize and play short effects through a bounded voice pool |
| `environment_music.gd` | Original environment score data and arrangement |
| `music_engine.gd` | Shared synthesizer, music playback and Music bus settings |
| `music_studio.gd` | Edit and preview music patterns |

`Game` is an **autoload**: Godot creates it before the main scene and keeps it when the active screen changes. Its name is available throughout the project. The active World/player are shorter-lived.

A **Node** belongs to Godot's scene tree and can receive automatic lifecycle callbacks. A **RefCounted** object is an ordinary helper whose lifetime is managed by references. Entities and Player are RefCounted: they do not automatically receive a physics tick just because they have an `update()` method.

A subclass uses `extends` to reuse a parent. `super.method()` runs that parent's implementation. In an override, forwarding a parameter such as `keep_player` matters: dropping it can change what happens during room transitions.

## Data and files

`res://` means the project directory. In an exported game it may be read-only. `user://` means Godot's per-user storage: settings, saves, custom levels and tuning presets belong there.

A **Dictionary** maps names to values. For example, an entity dictionary can contain `t`, `x`, `y`, `w` and `h`: type, pixel position and optional size. An **Array** is an ordered list. `PackedByteArray` and other packed arrays store many values of one type efficiently.

Level JSON stores a room name, width/height in tiles, tile rows and placed entities. A tile row is a string of `0` and `1`: empty and solid. `world.json` places those room files on the adventure grid. A saved run is different: it stores player progress such as visited rooms, collected IDs, unlocked abilities and energy.

`duplicate(true)` creates a deep copy, including nested containers. Editors and tests need this when they must change a copy without changing the saved/previous version.

Validation checks data before constructing gameplay objects. A valid JSON document can still contain unusable game data: a spawn of `["bad", {}]` is syntactically valid JSON but not a valid coordinate pair.

## Movement states and timed actions

A **state machine** runs one main movement mode at a time: normal, climb, dash, booster, flight and so on. `_state_update()` asks the active mode what to do next. `_set_state()` performs old-state cleanup and new-state initialization once. Visual animation names are separate from these physical states.

Small timers make controls forgiving. An **input buffer** remembers a recent press briefly, so a jump pressed just before landing can still happen. **Coyote time** allows a jump briefly after leaving a ledge. These are intentional rules, not slow input handling.

Some actions have multiple stages. `co_step` and `co_wait` implement these short timed sequences without a blocking delay. `await` in tests/UI instead suspends that function until an event arrives; it does not mean all gameplay should stop.

## Objects, enemies and the Ape

`Entities.TYPES` is the catalogue used by loading, editing and previews. Its saved string IDs should remain stable because room files refer to them.

`Ent` defines the common object contract. Subclasses customize setup, timed behavior, interaction and drawing. Collision flags determine whether World stores an object with solids, one-way platforms or touchables. Moving solids must carry/push a player carefully, which is why they use movement helpers rather than simply changing their position.

`CombatEnemy` centralizes health, variant modifiers, safe steps, shields, venom and projectiles. Family subclasses select their own movement/attack sequence. A **phase** is a behavior stage such as idle, windup, attack and recovery. Keeping those stages explicit makes enemy timing inspectable.

The arena Ape chooses attacks by distance and exposes separate contact, stone, scream and slam shapes. The chase Ape instead plans a route using a quiet scripted Player and a collision-only World adapter, then replays recorded feet positions. Planning should not spend the real player's energy, create effects or overwrite progress. A cached route must identify all its relevant inputs; reusing a route after terrain or tuning changed is a logic error.

## Drawing and audio vocabulary

An **atlas** packs many small images into a single image. A row selects an animation/type and a column selects a frame. **Nearest-neighbor** scaling preserves hard pixel edges; filtering would blur them.

A **cache** retains expensive work for reuse. Its key must include every input that changes the result. For example, character textures depend on hair color, and block textures depend on style, dimensions and damage. Cache invalidation means discarding outdated results when inputs change.

Audio **PCM samples** are amplitude numbers sent to the speaker at a sample rate, such as 22,050 samples/second. Signed 16-bit samples occupy two bytes each. Stereo stores alternating left/right samples. A volume **envelope** fades a sound in/out and shapes its attack/decay. It is different from the player-controlled volume slider.

An audio **bus** is a mixer channel. Music and SFX have separate buses so their volume/muting are independent. A **voice** is one currently playing effect; a fixed voice pool allows overlap without creating unlimited players. Noise synthesis uses a seeded random generator so test runs can recreate the same samples.

## Editing, testing and offline tools

The room editor changes copied level data. Its preview objects draw artwork with no live World. The world editor changes room offsets and writes the manifest; it delegates room-content changes to the room editor.

Use `sh tools/verify.sh` for the aggregate checks. Read its output and any referenced logs; a process exit of zero alone does not always mean Godot encountered no script errors.

`tests/test_runner.gd` uses scripted input and fixed steps for reproducibility. `tests/smoke.gd` exercises real screens and editor workflows. Audio/art runners inspect actual generated data. `tests/bench.gd` measures timing; warm-up work is excluded, and timings depend on the machine.

Use disposable user storage, for example:

```sh
XDG_DATA_HOME=/tmp/summit-learning godot --headless --path . res://tests/test.tscn
```

Offline tools have different effects:

| Tool | What running it can do |
| --- | --- |
| `tools/export_*.gd` | Rewrite generated/reference artwork |
| `tools/story/gen_first_stretch.py` | Rewrite generated story rooms/layout |
| `tools/world_fixups.py` | Repair and rewrite world room JSON |
| `tools/world_accessibility.py`, `world_check.py`, `check_*.py` | Analyze data; some options also write reports/maps |
| `tools/test_room_safety.gd` | Simulate diagnostic arrivals and write a findings report |
| `tools/install-dev-skills.sh` | Install external developer instructions outside normal game data |

The Python reachability tools approximate movement on a tile grid. A region being connected in that model is not proof that every real jump can be made. Godot movement regressions and manual playtesting provide different evidence.

## Making a small change safely

Choose the file that owns the behavior. Read its header, the relevant function and its callers. State what should happen with a concrete example. If changing behavior, add or update a regression that would notice the wrong result, then make the smallest change and run the appropriate checks. For art, also inspect the generated image and its animation. For audio, listen as well as checking samples.

Prefer a shared helper when several functions repeat the same rule with only a few inputs changed. Pass those varying inputs as parameters. Keep separate functions when their names describe different responsibilities, even if each delegates to a shared helper. A generic function with many unrelated flags is often harder to follow than two short explicit functions.

Comments explain purpose, units, ownership and surprising rules. They are not a second implementation: when behavior changes, check whether the nearby explanation still describes it. Third-party addon code and asset licenses are intentionally left in their original form.

## Assistant development skills

See [the development skills installation report](DEVELOPMENT_SKILLS.md) for the seven new skills, their exact source revisions, verification results and how to reproduce the Codex/Claude setup.
