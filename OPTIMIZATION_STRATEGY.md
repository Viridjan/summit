# Summit Optimization Strategy

## Scope and evidence

Optimize gameplay frame time, editor responsiveness, and maintenance cost while preserving pixel movement, collision ordering, level JSON compatibility, and the 60 Hz physics timestep.

Sources: `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json`, and the current GDScript. Graphify contains 256 nodes, 511 edges, and 11 hyperedges. Its highly connected abstractions include `Entities.make()`, `Ent`, and player state transitions. Connectivity identifies change impact; it does not establish runtime bottlenecks. The priorities below are hypotheses until measured.

Two ambiguous graph relationships are resolved by the code:

- `Player.is_riding()` tests rectangles directly; it does not call `World.player_touch()`.
- Both world and editor call `Art.draw_tiles()`; the drawing helper does not call the editor.

## 1. Establish a reproducible baseline

Create disposable benchmark levels covering a normal room, dense static entities, moving platforms, large blocks, and a large editor map. Use fixed inputs and random seeds. Record engine version, hardware, renderer, viewport, entity count, and map dimensions.

Measure physics and rendered frame times separately, reporting median and p95 after warm-up across three runs. Instrument collision query counts and candidates, terrain drawing, entity drawing, preview rebuilds, undo memory, and respawn build time. Run rendered benchmarks for graphics costs; headless results cannot validate rendering performance.

Proposed acceptance targets: p95 frame time below 16.67 ms on the chosen reference machine, editor interactions below 50 ms, and at least 20% improvement in the targeted stress-case metric without more than 5% regression in a normal room. These are targets, not measured results.

## 2. Reduce rendering work

**Files:** `scripts/world.gd`, `scripts/art.gd`, `scripts/entities.gd`, `scripts/editor.gd`.

The world requests a redraw each physics tick. Terrain drawing already limits tile traversal to the viewport, but recomputes adjacency and decoration choices on each redraw. Every entity is drawn, including offscreen blocks whose drawing loops visit their cells.

1. Add conservative entity visual bounds and cull drawing outside the viewport. Include zip rails, moving decorations, shake, and effects in those bounds. Keep simulation active offscreen.
2. If terrain remains significant, cache tile appearance or separate static terrain into retained chunks. Invalidate edited tiles and neighboring tiles; account for grass extending above its tile. Avoid a single full-map texture with excessive memory cost.
3. Limit editor grid lines to visible coordinates. Update HUD and editor status labels only when their displayed value changes.

Verify screenshots at borders, camera positions, and zoom levels. Keep background animation and dynamic effects updating independently of cached terrain.

## 3. Accelerate collision candidates when profiling justifies it

**Files:** `scripts/world.gd`, `scripts/entities.gd`; preserve the player query API.

Tile collision already uses a packed grid. Entity collision queries scan category arrays, and pixel movement invokes queries repeatedly. A candidate-count reduction is more promising than changing movement semantics.

Introduce a uniform spatial index for entity bounds only if dense-level measurements show a meaningful cost. Deduplicate candidates and preserve original category-array order so overlapping objects return the same first hit. Keep `ignore`, `skip_dream`, and live `collidable` checks.

Update moving-solid membership immediately after each axis changes its rectangle, before push/carry collision queries. Index touchables using `touch_rect()`, which may differ from their solid rectangle. Rebuild the index on respawn and level replacement. Compare indexed query results against the existing scans across randomized deterministic rectangles before enabling it.

## 4. Make editor updates incremental

**File:** `scripts/editor.gd`.

`_refresh()` recreates every preview through `Entities.make()`. Undo stores deep copies of the entire level, and painting reconstructs a row string for each changed cell.

First update only affected entity previews; retain full rebuilds for load, resize, and whole-level replacement. Batch row edits within a paint event while preserving continuous stroke coverage. If measured undo memory is excessive, replace paint snapshots with per-stroke deltas, retaining snapshots for structural operations initially.

Preserve pending zip-mover identity handling, undo grouping, and editor/playtest copy isolation. Add regression checks for these behaviors before changing their storage model.

## 5. Protect central gameplay code

Graphify's state-machine and moving-platform hyperedges identify high-risk change areas. Keep `_set_state()` hooks, coroutine timing, per-pixel stepping, corner correction, and update order intact during performance work. Avoid a broad player-controller rewrite.

Keep `Entities.make()` as the shared world/editor construction boundary. Extract small helpers only where repeated logic and tests justify it. Particle pooling, texture-cache changes, and skipping entity updates should wait for evidence; the player hair texture cache already exists.

## Delivery and validation

Deliver separate changes in this order: baseline harness, drawing improvements, editor improvements, then a collision index if supported by measurements. Each change should include before/after metrics and an independent rollback path.

Run both existing runners after implementation:

```sh
godot --headless --path . res://tests/test.tscn
godot --headless --path . res://tests/smoke.tscn
```

Extend deterministic coverage for overlapping collisions, moving-platform carry/squish, jump-through edges, dream dash, and any changed editor behavior. Manually inspect rendered gameplay and editor output. Use disposable levels and isolated runtime data.

This document records a source-based strategy. No performance benchmark or test execution was performed for this planning change, and no speedup is claimed.
