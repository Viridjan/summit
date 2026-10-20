# Summit Optimization Results

Follow-up to `OPTIMIZATION_STRATEGY.md`. All numbers below were measured in this session with `tests/bench.tscn`; nothing is estimated unless stated.

## Environment

| | |
|---|---|
| Engine | Godot 4.7.2.stable.arch_linux |
| Renderer | gl_compatibility (project setting), X11 window 1280x720, vsync forced off in-memory |
| CPU / GPU | Intel i5-13400F (6P+4E cores), AMD Radeon RX 6700-class (Navi 22) |
| OS | CachyOS Linux, governor `powersave` |
| Method | 3 runs x 600 ticks after 60 warm-up ticks per scenario, fixed seed 12345, fixed scripted input; medians/p95 pooled over the 3 runs |

The final A/B comparison ran the untouched original scripts (a copy kept outside the repo) and the modified scripts back to back, pinned to the P-cores (`taskset -c 0-11`). Without pinning, physics timings for unchanged code moved by up to ~2x between launches (E-core scheduling). Even when pinned, they still drift ±20% between launches. Treat physics differences of that size as noise, because no physics code changed.

## Benchmark harness (`tests/bench.gd`, `tests/bench.tscn`)

```sh
godot --headless --path . res://tests/bench.tscn      # CPU: physics tick + _draw recording
godot --path . res://tests/bench.tscn                 # rendered: adds frame, render CPU/GPU time
# env: BENCH_OUT=file.json BENCH_RUNS=3 BENCH_TICKS=600 BENCH_ONLY=normal,dense,moving,large_blocks,editor
```

Levels are built in memory. The harness saves nothing under `user://`, does not save settings, and sets `Game.playtest = true` so no records are written. The player is a scripted bot, and respawns rebuild it as a bot too. The harness subclasses `world.gd`/`editor.gd` only to time `_draw()` and to count queries; that counting runs in an extra pass that is never timed.

| Scenario | Content |
|---|---|
| normal | Smoke-test room 60x30, one of every entity type except goal (19 entities) |
| dense | 240x40, 1500 touchables + 1000 static solids/jump-throughs (2500 entities) |
| moving | 120x200, 100 zip movers kept triggered + 100 falling blocks released at start |
| large_blocks | 400x80, 32 blocks of 24x24 tiles (crumble/falling/dream/zip) |
| editor | 400x400 map, 30% random terrain, 3000 entities: rebuild, place, erase, undo, paint, draw at zoom 3/2/0.5 |

Recorded per scenario: physics tick time, world `_draw()` time, whole-frame time, viewport render CPU/GPU time (rendered only), `_build()` (respawn) time, and collision queries per tick with linear-scan candidate counts.

## Baseline findings (original code, rendered, P-cores)

| Scenario | Physics ms med/p95 | `_draw` ms med/p95 | Frame ms med/p95 | Render CPU / GPU ms |
|---|---|---|---|---|
| normal | 0.19 / 0.32 | 0.92 / 1.42 | 2.35 / 3.81 | 0.51 / 0.10 |
| dense | 4.43 / 6.00 | 17.48 / 19.82 | **34.47 / 39.11** | 6.64 / 6.63 |
| moving | 0.69 / 3.35 | 2.36 / 3.10 | 5.60 / 8.42 | 1.23 / 0.69 |
| large_blocks | 0.26 / 0.39 | 4.56 / 5.69 | 7.33 / 8.80 | 1.53 / 0.24 |

Editor (400x400, 3000 entities): place point 12.7 ms, place rect 12.5 ms, erase 12.9 ms, undo 13.2 ms (each one is a full preview rebuild, which costs 12.2 ms on its own). The frame took 32.9 ms at zoom 3, 37.1 ms at zoom 2 and 100.6 ms at zoom 0.5. A full-width tile-row stroke took 0.45 ms, and one drag event took under 0.01 ms. One undo snapshot is 431 KB serialized, and the 60-snapshot stack used 119 MB.

Collision profile, from a headless per-tick split of the dense scenario: queries cost ~1.3 ms per tick (`player_touch` 0.56 ms, plus about 4 `collide_solid` calls scanning 750 solids each, ~0.7 ms). The entity `update()` loop cost 1.4 ms and has to stay, because offscreen simulation remains active. In the moving scenario, most of the 0.7 ms is falling blocks calling `collide_solid` once per pixel. In the normal room, queries are negligible: about 15 solid candidates per tick.

## Changes

### Retained

1. **Entity draw culling.** `scripts/entities.gd` and `scripts/world.gd`. A new `Ent.vis_rect()` returns conservative draw bounds: `rect.grow(8)` covers rails, spring pads, spike tips, bobbing and shake. Two overrides cover cases that rect does not: `Strawberry` draws at `pos`, which trails the player, and `ZipMover` draws its whole rail. `World._draw()` skips entities whose bounds miss the view. `update()` still runs for every entity.
   Measured independently, before the other changes, unpinned rendered: dense frame 31.23 → 4.88 ms median (p95 36.93 → 9.31), dense `_draw` 15.38 → 1.71 ms, large_blocks `_draw` 4.42 → 0.52 ms, moving `_draw` 2.13 → 0.59 ms. Normal room headless `_draw` went 0.74 → 0.75 ms (no regression).
2. **Editor preview culling.** `scripts/editor.gd` uses the same `vis_rect()` test. Measured independently, rendered: frame at zoom 3 went 47.1 → 6.1 ms, zoom 2 52.0 → 9.8 ms, zoom 0.5 129.3 → 98.9 ms.
3. **Terrain neighbour lookups inlined.** `scripts/art.gd` `draw_tiles()` used to make a lambda call per solid check (five per tile). It now reads the row and the rows above and below directly. Output is unchanged, as verified below. Terrain `_draw` time on the editor map went 49.4 → 20.9 ms at zoom 0.5 and 1.55 → 0.81 ms at zoom 3. Normal room world `_draw` went 0.75 → 0.35 ms headless. Profiling showed terrain was most of the remaining editor zoom-out cost, so this cheaper fix was tried before any caching.
4. **Incremental editor previews.** `scripts/editor.gd`. `preview` is now index-aligned with `level.entities`. Placing a point or rect appends one preview. Setting a zip target rebuilds that mover's preview, found by identity with `is_same`. Erasing removes one preview. Load, undo, new, resize and spawn replacement still do a full rebuild. Measured: place point 12.7 → 0.32 ms, place rect 12.5 → 0.01 ms, erase 12.9 → <0.01 ms.

### Rejected or not implemented (with the measurement behind the decision)

- **Visible-only editor grid lines.** Implemented, then reverted. In a 3x A/B on the 400x400 map, zoom 3 frame was 5.64/3.54/5.78 ms before and 5.37/5.74/5.37 ms after; zoom 2 was 8.32/8.59/8.73 before and 8.38/8.40/8.54 after. That is no difference beyond noise.
- **Skipping unchanged label updates.** Not implemented. The editor status `_process()` costs 0.02–0.05 ms per frame in total. The gameplay HUD shows milliseconds, so its text changes every tick and a change check would never skip anything.
- **Batching tile-row edits.** Not implemented. The whole cost it could remove is 0.45 ms for a full 400-cell row stroke and under 0.01 ms per drag event, against the 50 ms interaction target.
- **Undo storage change.** Not implemented. Push latency is 2.0–2.8 ms. Memory reached 119 MB for 60 snapshots, but only in the 3000-entity stress map, and `MAX_UNDO` bounds it. Typical-map memory was not measured.
- **Entity spatial index.** Not implemented. Queries cost ~1.3 ms per tick, and only in the 2500-entity stress level. After culling, every stress scenario's p95 frame time is under 16.67 ms: dense 8.42, moving 4.45, large_blocks 2.87. Normal-room queries are well below 0.1 ms. The ordering, flag and moving-platform invariants an index would have to preserve were not worth risking for that gain.
- **Terrain caching.** Not implemented. Gameplay terrain cost is under 0.4 ms. The only case over budget is the editor at zoom 0.5 on a 400x400 noisy map, at a 64.6 ms frame. There, render CPU and GPU (31.6 / 28.1 ms) cost more than GDScript recording (29.2 ms), so retained canvas chunks would remove only part of it. A texture cache would also need edit invalidation and memory budgeting.

## Before/after (rendered, P-cores, original vs final)

| Scenario | Frame ms med/p95 before → after | `_draw` ms med before → after | Render CPU ms before → after |
|---|---|---|---|
| normal | 2.35/3.81 → 1.53/3.10 | 0.92 → 0.35 | 0.51 → 0.36 |
| dense | 34.47/39.11 → **6.77/8.42** | 17.48 → 2.07 | 6.64 → 0.65 |
| moving | 5.60/8.42 → 1.95/4.45 | 2.36 → 0.24 | 1.23 → 0.23 |
| large_blocks | 7.33/8.80 → 0.97/2.87 | 4.56 → 0.17 | 1.53 → 0.19 |

| Editor (400x400, 3000 entities) | Before | After |
|---|---|---|
| Frame, zoom 3 (med/p95) | 32.90 / 36.35 ms | 4.51 / 5.88 ms |
| Frame, zoom 2 | 37.11 / 43.77 ms | 6.97 / 10.33 ms |
| Frame, zoom 0.5 | 100.57 / 122.82 ms | 64.63 / 76.32 ms |
| Place point / place rect / erase | 12.70 / 12.50 / 12.87 ms | 0.32 / 0.01 / <0.01 ms |
| Undo / full rebuild (unchanged path) | 13.22 / 12.22 ms | 14.98 / 13.85 ms (noise; same code) |

Headless, P-cores, physics median before → after: normal 0.19 → 0.22, dense 3.33 → 3.67, moving 0.66 → 0.67, large_blocks 0.23 → 0.26. Rendered: normal 0.19 → 0.14, dense 4.43 → 3.30. These shift in both directions within the launch-to-launch noise described above. No physics or collision code was changed.

Determinism: every run ended with the same player state for each scenario, for example dense `(322, 286)`, alive, 0 deaths. The editor tile hash after the paint sequence was identical before and after (3974068580).

## Verification

- **Pixel comparison.** 30 rendered screenshots from the original and the final code were pixel-identical. They cover four world scenarios at four ticks each, and the editor at zoom 0.5/1/2/3/10 including the map corners and edges, on both the 400x400 map and the default map.
- **`godot --headless --path . res://tests/test.tscn`:** 62 PASS, `0 failure(s)`, exit 0.
- **`godot --headless --path . res://tests/smoke.tscn`:** `SMOKE OK`. A rendered smoke run with `SHOT_DIR` also passed, and its world, pause, editor and menu screenshots were inspected and look correct.
- **New regression check in `tests/test_runner.gd`.** After a spawn replacement, a point placement, a duplicate placement, a rect, a zip mover plus its target click, a strawberry, and an erase, the incremental previews must match a full rebuild index for index (same dict identity, `rect`, `vis_rect`), and the zip preview must have the clicked target. Removing the zip-target refresh makes both checks fail, so the test catches the regression.

## Limitations

- No interactive keyboard play-through was done. Visual checks were deterministic screenshots and the smoke-test screenshots.
- Benchmarks come from one machine with the `powersave` governor. Physics noise is described above.
- Render GPU timings come from Godot's viewport timer under the Compatibility renderer.
- The draw bounds in `vis_rect()` are hand-derived. A future sprite that overhangs its rect by more than 8 px needs its own override.

## Remaining work

- Editor zoom-out on maximum-size maps (64.6 ms frames at zoom 0.5). A chunked texture cache for terrain, with per-tile invalidation, is the next step if large maps become common.
- An entity spatial index, if real levels approach thousands of entities. The candidate counters in the benchmark harness are the place to start.
- Measure undo memory on typical-size maps before changing undo storage.

## Follow-up: retained tile chunks (2026-10-19)

This follow-up supersedes the earlier decision to leave terrain caching unimplemented. The pre-existing culling, inline neighbour checks, incremental previews, and benchmark harness were confirmed in the code and preserved. Collision indexing, undo changes, row batching, and label/grid changes remain deferred for the reasons above.

### Implementation

- `scripts/art.gd`: extracted `draw_tile_range()` without changing the autotile logic or hash-based decorations. `draw_tiles()` retains its original viewport margins and delegates to the range helper.
- `scripts/tile_layer.gd`: added 32x32-cell child chunks with retained CanvasItem commands. Each cell has exactly one drawing owner. Dirty edits invalidate the owning chunk and any chunks containing its cardinal neighbours; diagonal chunks do not depend on the edit. The chunks share the live tile array. Their recorded drawing bounds include grass extending above the source cell.
- `scripts/world.gd`: initializes terrain once, retains both chunks and the tile array on respawn, and redraws the animated background separately.
- `scripts/editor.gd`: marks changed tiles dirty and rebuilds chunks on load, undo, new, and resize to bind the replacement tile array. Existing incremental entity previews remain intact.
- `tests/test_runner.gd`: added chunk coverage, invalidation, live-data, retained-command, respawn, editor replacement, layering, and background redraw checks.

Final relative draw order: background node at **-2**, tile chunks at **-1**, parent-drawn entities and effects at **0**. Gameplay background includes snow; editor background includes sky and grid. The background follows both internal redraw requests and direct `queue_redraw()` calls from tools. Chunk draw commands are not invalidated by parent redraws or camera movement.

### Measurements

Throwaway instrumented project copies and harnesses were kept under `/tmp/summit-tile-before` and `/tmp/summit-tile-after`; no benchmark instrumentation was added to production scripts. Results are in `/tmp/summit-tile-measurements.json` for this session.

Environment: Godot 4.7.2, Linux, Intel i5-13400F, headless, 1280x720 viewport. Three alternating before/after runs, 90 samples per case after warm-up, seed 12345. The world uses the existing normal-room fixture, a 320x180 camera view, and disabled simulation to isolate drawing. The editor uses the existing 400x400 fixture with 3000 entities, zoom 0.5. Camera movement requests one redraw per sample; paint samples also alternate one interior tile. All draw callback CPU time is summed, **including the new background and chunk callbacks**, rather than timing only the parent's `_draw()`.

Values below are the median across runs of each run's median/p95, in milliseconds:

| Case | All draw callbacks, median/p95 before | After | Terrain recording median before → after |
|---|---|---|---|
| World camera movement | 0.215 / 0.318 | 0.122 / 0.177 | 0.099 → 0 |
| Editor camera movement | 21.146 / 21.720 | 3.291 / 3.541 | 17.887 → 0 |
| Editor interior tile edit + movement | 21.099 / 21.382 | 3.635 / 3.972 | 17.825 → 0.332 |

Steady-state camera movement makes zero terrain recording calls. An interior edit records one chunk. Boundary invalidation is verified separately by deterministic tests. Editor pan draw recording improves by about 84%; this is **not** a measured rendered-frame or GPU improvement.

The cache moves work to initialization and whole-level replacement. On the large editor fixture, median node setup increased from 16.4 to 19.4 ms; initial draw recording increased from 23.0 to 58.2 ms, including 54.6 ms of terrain recording for all 169 chunks. This initial cost recurs when undo/load/new/resize rebuild chunks. Retained commands consume additional memory, which was not quantified here. Chunks cache commands rather than raster textures, so visible tile rendering still costs CPU/GPU work each frame.

### Validation and limitations

- Physics/regression scene: **95 PASS, 0 failures**, exit 0.
- Headless smoke scene: **SMOKE OK**, exit 0.
- Neither successful test log contains `SCRIPT ERROR` or `ERROR` lines.
- A throwaway recorder compared the original terrain helper with chunk-range drawing on a seeded 100x70 map crossing chunk boundaries: the same **9,965 draw commands**, with no missing or duplicate commands. Software compositing those commands against the sprite sheet produced identical 800x560 RGBA pixels despite the changed chunk traversal order.
- The software comparison covers terrain output; it does not validate Godot rendering, engine culling, or complete screen layering. Those still need a rendered check.
- The requested rendered smoke screenshot capture was attempted before editing, but the environment could not connect to either X11 or Wayland. Consequently no before/after world, pause, editor, or menu screenshot comparison, rendered benchmark, or interactive play-through was possible. Layer order is checked structurally, and background draw execution is tested headlessly.
- Tests and benchmark processes use disposable `XDG_DATA_HOME` directories under `/tmp`, leaving personal levels, settings, and saves untouched. `AGENTS.md`, player movement, collision code, and physics settings were not changed.
