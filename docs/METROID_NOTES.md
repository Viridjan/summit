# Metroid notes: what Zero Mission does, what Summit uses, what is left for later

Source: the Metroid Zero Mission decompilation, https://github.com/metroidret/mzm (`master`).
Paths like `src/room.c` refer to that repo. Unverified points are marked as such.

## 1. World and rooms

**mzm**
- 7 areas (`enum Area`, `include/constants/connection.h`). Each area has rooms (`struct RoomEntryRom`, `include/structs/room.h`).
  A room has tileset, BG layers, collision (`pClipData`), up to three enemy layouts picked by event flags,
  and **`mapX`/`mapY`: its top-left on the area map**. Room size is read from the collision data itself.
- Rooms connect through **doors** (`struct Door`, `include/structs/connection.h`):
  - Fields: `type`, `sourceRoom`, a block rectangle, `destinationDoor`, `xExit`/`yExit`.
  - Touching a transition block in the collision layer triggers `ConnectionCheckEnterDoor` (`src/connection.c`). It remembers Samus's height inside the doorway, fades out, loads the room, and places her at the destination door with the same height offset (`RoomReset`, `src/room.c`).
  - Unverified: whether velocity survives (pose and velocity are not reset in `RoomReset`).
- Areas link with `AREA_CONNECTION` doors and elevators (`sAreaConnections`, `ElevatorRoute`).
- Event flags can redirect a door to another destination (`sEventBasedConnections`, `src/data/hatch_data.c`).
- Camera: per-room "scroll" rectangles (`src/scroll.c`). The camera is clamped to the rectangle Samus is in, so one room can have several camera zones.

**Summit (implemented)**
- One world, no areas. Rooms are ordinary level files in `res://adventure/`. `res://adventure/world.json` stores each room's tile position on one big grid (our `mapX`/`mapY`) and the start room (`scripts/adventure.gd`).
- Celeste-style **edge transitions**, plus **Door objects** (`entities.gd` Door, `World._go_door`): mzm's `struct Door` in small, a rectangle with an `id` and a `to` = `room:id`, keeping the player's height in the doorway like `RoomReset`. The reference worlds in `res://worlds/` use them for every door on the original maps.
  - Walking off a room's edge enters whichever room covers that spot (`World.can_exit`, `World._check_room_exit`, `World.enter_room`).
  - Position is converted through world coordinates, so the player's height in the doorway is kept, like mzm's door offset.
  - Speed and state carry over; one tick, no fade.
  - Going up gets a small upward boost so the player doesn't fall straight back.
- A passage exists wherever two touching rooms both have open tiles on the shared border. The world editor draws these in green and outlines overlapping rooms in red.
- Respawn after death: the room's spawn marker closest to where the player came in, otherwise the entry point.
- Camera: clamped to the current room (one zone per room). On entry the view keeps its screen position and then eases into the new room.

## 2. Map

**mzm**
- A hand-drawn 32×32 tile map per area (`sMinimapDataPointers`). **One map tile = one screen of a room.**
- Explored state: `gVisitedMinimapTiles[area][32]` (u32 bitmask per row), saved.
- `MinimapCheckForUnexploredTile` (`src/minimap.c`): Samus position → screen → `+ mapX/mapY` → set bit.
- Map stations (`src/sprites_ai/map_station.c`) set `downloadedMapStatus |= 1 << area`. Unvisited but downloaded tiles then show in another colour.
- Collected items and boss icons are drawn on the map.

**Summit (implemented)**
- The map is generated from the rooms themselves (1 pixel per tile), not hand-drawn (`scripts/map_view.gd`).
- Explored state is **per room**: `adv.visited`. Rooms not visited yet are hidden.

## 3. State machine: Samus poses vs Summit player states

| | mzm (`src/samus.c`) | Summit (`scripts/player.gd`) |
|---|---|---|
| States | 69 `SamusPose` values, many of them animation-only variants (turning, shooting while…) | 9 `ST_*` states (Celeste's StateMachine) |
| Per-tick logic | `sSamusPoseFunctionPointers[pose]` returns the next pose (or `SPOSE_NONE`) | `_state_update` → `_<state>_update(dt)` returns the next state |
| Animation | separate table `sSamusPoseGfxFunctionPointers[pose]`, runs only if logic returned NONE; it can end a pose when its animation ends | sprite chosen from state + flags in `_update_visuals` / `character_art.gd`; never changes state |
| Change of state | `SamusSetPose`: snapshot old state (`gSamusDataCopy`), reset per-pose fields, copy selected fields per pose (`SamusCheckCarryFromCopy`) | `_set_state`: `match` on old state (end hooks), then on new state (begin hooks); timers live in named vars |
| Timed sequences | per-pose `timer` field | Celeste coroutines emulated with `co_step` / `co_wait` (`_co_resume`) |
| Context-dependent states | **request pseudo-poses** (`SPOSE_HURT_REQUEST`, `KNOCKBACK_REQUEST`, `LANDING_REQUEST`, `MID_AIR_REQUEST`) resolve to the right concrete pose for the current one (e.g. hurt in ball → `GETTING_HURT_IN_MORPH_BALL`) | none; death is a flag (`dead`), not a state |
| Hazards | `SamusTakeHazardDamage` runs before every pose handler and can skip it | spikes/out of bounds call `die()` directly |
| Abilities | `Equipment`: owned bitfields + separate "activated" bitfields; handlers check activation inline (e.g. morph needs `SMF_MORPH_BALL`) | `Game.has_ability(name)`, checked once in `Player.update` (dash input dropped, grab ignored) |

What carries over well:
- Our handlers already return the next state, the same as mzm. The begin/end `match` blocks in `_set_state` do the work of mzm's carry/reset step.
- The debug panel (F1) records every transition (`transitions`, `transition_log`), which mzm has no equivalent for.

## 4. Progression gating

**mzm**
- Items and abilities are tracked as equipment bits plus event flags (`enum Event`, `src/event.c`, bits in `gEventsTriggered`).
- Hatches (`HatchType`: normal, missile, super, power bomb, locked) need a given weapon to open, and opened ones are remembered per area (`gHatchesOpened`).
- Collected tanks: `gItemsCollected`. Blocks that never re-form: `gNeverReformBlocks`.

**Summit (implemented)**
- `Adventure.ABILITIES = ["dash", "climb"]`: an adventure starts without them.
- Pickups `ability_dash` / `ability_climb` (`AbilityOrb`, `scripts/entities.gd`) add the ability to `adv.abilities`; it is saved straight away.
- Outside the adventure (custom levels, editor playtests) every ability is available.

## 5. Save

**mzm**
- `struct SaveFile` (`include/structs/save_file.h`) holds the current area/room/door, camera, full Samus data, equipment, timers and cutscene flags.
- `SaveWorldData` inside it holds visited map tiles, broken blocks, collected items, opened hatches and events.
- 3 slots, each with a backup copy.

**Summit (implemented)**
- One run in `user://save.cfg`, section `[adventure]` key `run`: `room`, `spawn`, `abilities`, `visited`, `stars` (`room:x_y` ids), `deaths`, `time`, `done`.
- Saved on room entry, star bank, ability pickup and exit.

## 6. Backlog: ready to build later

Each item names where it would go. None of these exist yet.

1. **Hurt / knockback states** (mzm request pseudo-states). Add `ST_HURT` to the enum and `STATE_NAMES` in `player.gd`. Add a `hurt(dir)` that `_set_state`s into it with knockback speed and invincibility frames, and an `hp` value in `adv`. Spikes would call `hurt` instead of `die` when `hp > 1`.
2. **More abilities**: wall jump, double dash (replaces the `air_dashes` setting inside the adventure), feather-free flight.
   - Add the name to `Adventure.ABILITIES`, a registry row `ability_<name>` in `entities.gd`, and a check in `Player.update` or the specific move.
   - Owned vs active bits (mzm's `...Activation`) only if a toggle menu is wanted.
3. **Event flags**: `adv.events` (Array of names) and `World.set_event(name)`. Entities could read them in `setup()` to appear or disappear (mzm swaps enemy layouts by event).
4. **Locked passages / hatches**: a solid entity `gate_<ability>` that is `collidable` only while `not Game.has_ability(...)`, or while an event is unset. Opened gates go in `adv.events`. This is the same pattern as `AbilityOrb`.
5. **Map stations**: an entity that adds every room to a new `adv.revealed`. `map_view.gd` would draw revealed-but-unvisited rooms dimmed.
6. **Per-screen exploration**: mark 40×23-tile cells instead of whole rooms (mzm's tile bitmask) if rooms get large.
7. **Camera zones inside a room** (mzm scroll rectangles): optional rectangles in the level JSON; `World._clamp_cam` clamps to the one containing the player.
8. **Room transition polish**: a short freeze and camera pan like Celeste/mzm (today the switch is instant and the camera eases).
9. **Save slots**: key `run` → `run_1..3`, plus a slot picker in `menu.gd::_adventure`.
10. **Areas**: a group name per room in `world.json`, with music and background per area.
11. **Animation-driven state ends** (mzm gfx table): only needed if states start depending on animation length.
