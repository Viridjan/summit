# Codex prompt: artwork for the one-way platforms (Jump-Through and Leaf Platform)

Read `AGENTS.md` first. Stay inside this repository. Do not change gameplay, collision, room files or generators.

## Context (verified in code, 2026-10-26)

- Two editor tools place the same one-way platform: `jumpthru` ("Jump-Through") and `leaf` ("Leaf Platform").
  Both are `JumpThru` in `scripts/entities.gd` (`class Leaf extends JumpThru` only overrides `draw`).
  Behaviour is identical: land on it from above, jump up through it, down + jump drops through.
- Collision: the entity's `rect` is `w` px wide (a multiple of 8, from 16 to about 80) and **5 px tall**
  (`JumpThru.setup` sets `rect.size.y = 5`); the level file stores `h: 8`. The top edge of `rect` is the
  standing surface.
- Current art is procedural and placeholder-grade:
  - `jumpthru`: `scripts/block_art.gd` style `"jumpthru"` (bevelled slab, grain every 8 px), drawn by
    `BlockArt.draw(ci, rect, "jumpthru")`.
  - `leaf`: `Leaf.draw` in `scripts/entities.gd` paints flat green rectangles on a 1 px stem.
- Usage today: 113 jump-throughs across every environment; 16 leaf platforms, all in jungle rooms
  (`j1`-`j3`, `l1`-`l3`, environment `forest`). Environments in use: forest, sand, sea, sky, temple, building,
  cavern, cavern_deep, island_shore, volcano, volcanic_cave.

## What to make

1. **Jump-Through (generic)**: a thin plank or ledge that reads as "you can stand on the top and pass through
   from below", for every environment. One shared design is fine; a palette or material per environment
   (wood, stone, basalt, coral...) is better if it stays readable. Use `Room.environment` (the room's
   `environment`) to pick it.
2. **Leaf Platform (jungle)**: broad leaves or a fern frond on a stem, clearly organic, same footprint.

For both:
- **The art must match the collision exactly where it matters**: the top surface line is the rect's top edge;
  nothing solid-looking above it. The body may hang at most 3 px below the 5 px rect (decorative underside,
  roots, leaf tips), never wider than `rect`.
- Tile horizontally for any width that is a multiple of 8 (left cap, repeatable middle, right cap), no visible
  seams.
- Pixel art at the game's native scale (1 game px = 1 art px), matching `assets/paper-pixels/` and the
  existing block art: limited palette, crisp edges, top light / bottom shadow like the other blocks.
- Optional: a 2-4 frame idle sway for the leaf (very subtle, max 1 px), driven by world time.

## Deliverables

- Generated or hand-made sprites under `assets/platforms/` (PNG + a short `README.md` with sizes, palette and
  licence: original work).
- Drawing code: keep the call sites (`JumpThru.draw`, `Leaf.draw`); draw the new art inside the same `rect`
  rules above. If you add a texture cache, key it by style, environment and width.
- A preview page like `assets/blocks/preview.html` / `assets/island/preview.html` showing both platforms at
  widths 16, 24, 40, 80 in every environment.
- A check runner (see `tests/island_art.gd` / `tests/ape_art.gd`): exact image sizes, transparent background,
  top row of the art at the rect's top, nothing outside the allowed bounds, the leaf animation (if any) has
  distinct frames. Add it to `tools/verify.sh` with a success line.
- Run `sh tools/verify.sh` (0 failing) before handing back. Note in `gdd.txt` (one dated line).

## Out of scope

Behaviour changes, merging the two types, editing room JSON, new environments, sound.
