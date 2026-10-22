# Code health

Audit of 2026-10-22, using the dev skills from `tools/install-dev-skills.sh`: godot-best-practices, godot-state-machine, systematic-debugging, test-driven-development and verification-before-completion.

## Verdict

The core is solid:

- The Celeste port is faithful: update order, corner correction, climb hop and coroutine timing all match.
- Movement is integer-pixel with sub-pixel remainders.
- Level JSON is validated before any entity is built.
- Nothing is loaded in a hot loop, and there are no `get_parent` chains.
- Entities and the player are RefCounted, so freed-node bugs can't happen.
- The player state machine is already disciplined: everything goes through `_set_state`, which runs the end and begin steps. A node-based FSM rewrite (godot-state-machine) would cost more than it gains.

The weak spots were save and editor robustness, a few gameplay edge cases, a test net that could not fail, and an untyped API between objects.

## Workflow for every fix

1. Reproduce the bug with a `check()` in `tests/test_runner.gd`, or in `tests/smoke.gd` for UI. Watch it fail.
2. Find the root cause before changing code. Two suspected bugs turned out not to be real (see below).
3. Make the smallest fix, then run all three suites:
   ```sh
   godot --headless --path . res://tests/test.tscn    # exit code = failures
   godot --headless --path . res://tests/smoke.tscn   # exit code = failures
   python3 -m unittest tests/test_world_accessibility.py
   ```
   CI (`.github/workflows/pages.yml`) runs the same three before every deploy.

## Fixed (regression checks in `check_bugfixes()`)

- **Smoke test could never fail.** It now exits with its failure count. Its touch-Jump check was flaky (about 1 run in 3) because buffered input wasn't flushed; that's fixed too.
- **Free-aim super jumps.** With `DASH_DIRS = 4`, super jumps and super wall jumps never fired. The checks now use an 8-way snap of the dash direction (`dash_dir8()`).
- **Red bubble aim.** It ignored `DASH_DIRS`; it now follows it.
- **Room-seam walls.** A wall on a shared room edge couldn't be climbed or wall-jumped. It now works like any other wall.
- **Restart Level** now clears broken walls and a pending door.
- **Dead player and doors.** A player who died this tick is no longer moved by a door.
- **Camera through doors.** A door into a far room now snaps the camera instead of sweeping it across the world.
- **Dropwing** (then called Skree) no longer gets stuck pushing forever against a ceiling on its way home.
- **Level validation** now rejects bad `facing`, `patrol` and `top` values.
- **Old saves.** Continue on an old or hand-edited save no longer crashes: `Adventure.restore_run` fills in missing fields.
- **Editor:**
  - New/Load never overwrite the world room the editor was opened on.
  - It asks before leaving with unsaved changes.
  - A drag released over the UI no longer keeps painting.
- **World editor:** a level that can't be loaded is reported instead of crashing.

Checked and **not** bugs:

- `WALL_SLIDE_TIME = 0` can't produce NaN, because a wall slide only starts while its timer is above 0.
- In `world_check.py`, refills do reach the next states the BFS explores.

## Open findings (low severity, fix when nearby)

- **Undo history.** The editor pushes undo on every click, even when nothing changes. The no-ops fill the 60-step history.
- **Stale references after a room change.** The player keeps references into the old room (`climb_hop_solid`, `dream_block`, `current_booster`, `attack_hit`). This is harmless today because the objects are RefCounted.
- **`tools/world_check.py`** raises `AttributeError` when the start room has no spawn.
- **`tools/world_fixups.py` `drop_unreachable`** deletes room files and has no dry run. A rebuild restores them.
- **`tools/place_reference_enemies.py`** hard-codes room ids, which break if the HK world is repartitioned.
- **Test isolation.** Tests use the real `user://`, and one long `_ready` holds most checks.
- **Magic numbers.** Some tests depend on them (e.g. `Tuning.names().size() == 99`).

## Optimization strategy (not started)

Measure first with `tests/bench.tscn`. Add an enemy-heavy scene before changing anything, because the current "normal" scene predates enemies. Don't re-propose what `OPTIMIZATION_RESULTS.md` already rejected: particle pooling, spatial index, HUD label skipping, batched tile edits, undo storage.

1. **Line of sight.** `CombatEnemy.sees_player` (`entities.gd`) runs up to about 28 `collide_solid` calls per enemy per tick. Check only the tile grid, and/or run it every N ticks.
2. **`SkeletonEnemy.safe_step`** string-matches every touchable every tick. Cache the hazard rects once per `_build`.
3. **Colours parsed per draw.** Turn the `Color("hex")` calls in entity `draw()` and `_draw_floor_gaps` into consts. Cache `CharacterArt.hair_shades()` per colour.
4. **Array literals in per-frame code.** Make them consts: `player.gd` (`state not in [...]`, `visual_animation in [...]`) and `character_art.gd` `frame()`.
5. **`_draw_floor_gaps`** draws across the whole room width. Cull it to the view.
6. **Neighbour `TileLayer` build.** A large neighbour room is built in one frame and can hitch. Spread its chunks over several frames.

## Future-feature compatibility (not started)

In dependency order. Hurt/HP unlocks most of `TODO.md`.

1. **Hurt entry point.** Add `player.hurt(src, dmg)`, which for now calls `die()`, and route the 8 call sites that kill the player instantly through it:
   - `entities.gd`: Spikes, CombatEnemy, bones, Liquid
   - `world.gd`: pits
   After that, HP, knockback and invincibility frames only change one function.
2. **Save version.** Add a `"v"` field to the adventure run, with a `migrate()` step on top of `restore_run`. This is a prerequisite for save slots.
3. **Typed state enum.** Replace the anonymous enum with `enum State {...}` and build `STATE_NAMES` from `State.keys()`. Adding a state currently means updating about 9 places in `player.gd`.
4. **Enemies in one place.**
   - Phase enums instead of strings.
   - One shared patrol/turn helper for the floor walkers (Ossling, Hornback).
   - Move the `EnemyArt.KINDS/SPRITES` lookups into the `TYPES` row.
5. **Typed API.**
   - Add `class_name` and types for `w`, `player` and `ents`.
   - `collide_solid` returns the string `"tile"` or an entity. Give it one typed result.
6. **Per-run ability overrides.** Layer them above tuning (`DASH_DIRS`/`ATTACK_DIRS`) for direction upgrades. `world_softlock.py` should read its stages from `world.json` instead of hard-coding dash → climb → goal.
7. **One reachability model.** Four exist today: `world_check`, `world_accessibility`, `world_fixups.drop_unreachable` and `check_shipped_world`. Pick one as the authority.
8. **Stale `TODO.md` entries.** "Web version" is done. Shade Cloak no longer needs "enemies that hurt" (they kill already). The placeholder rooms were replaced.
