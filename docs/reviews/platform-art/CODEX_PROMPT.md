# Codex prompt: a jump-through for each environment

Read `AGENTS.md` and `assets/README.md` (the art layout standard) first. Stay inside this repository. Do not change
gameplay, collision, room files or generators. Use the `pixel-art-studio` skill for the sprites.

## Context (verified in code, 2026-10-28)

- There is one one-way platform type, `jumpthru` ("Jump-Through", `class JumpThru` in `scripts/entities.gd`). The
  former Leaf Platform is now a jump-through with the jungle look (old `"leaf"` data converts on load).
- Behaviour: land on it from above, jump up through it, down + jump drops through.
- Collision: `rect` is `w` px wide (a multiple of 8, about 16 to 80) and **5 px tall** (`JumpThru.setup`); the room
  file stores `h: 8`. The rect's top edge is the standing surface.
- **Look**: `JumpThru.look()` returns `d.look` if the platform sets one, else the room's `environment`
  (`World.data.environment`; in the editor, `JumpThru.editor_look`). `JumpThru.draw` picks the art from it:
  today `forest` draws procedural leaves (`_draw_leaves`), everything else the plank rail
  (`BlockArt.draw(ci, rect, "jumpthru")`, `scripts/block_art.gd`).
- Environments (`EnvironmentArt.THEMES`, `scripts/environment_art.gd`): `sand`, `sea`, `cavern`, `cavern_deep`,
  `sky`, `temple`, `building`, `forest`, `island_shore`, `volcano`, `volcanic_cave`; plus `""` (editor levels
  with no environment). Their terrain, backgrounds and decorations are in `assets/themes/<environment>/`.
- Jump-throughs in the story today, by look: volcanic_cave 46, island_shore 24, forest 22, temple 13, volcano 11,
  cavern_deep 10, building 4, sea 2 (sand, cavern, sky: none yet, but give them one).

## What to make

One jump-through design per environment (12 looks: the 11 environments and `""`), each matching its
environment's terrain palette and materials, for example: driftwood or coral (sea, island_shore), sandstone slab
(sand), mossy stone ledge (cavern), dark crystal shelf (cavern_deep), cloud or rope bridge (sky), carved stone
(temple), wooden shelf or beam (building), leaves on a branch (forest, keep the current idea), cooled basalt
(volcano), obsidian with a faint glow (volcanic_cave), the current plank rail (`""`).

For every look:
- **Collision honesty**: the top surface line is the rect's top edge; nothing solid-looking above it. Decoration
  may hang at most 3 px below the 5 px rect, never wider than the rect.
- **Tiling**: any width that is a multiple of 8: left cap, repeatable 8 px middle, right cap; no seams.
- **Readable as one-way**: a thin, light top edge and an open or airy underside, so it never reads as a solid block.
- Pixel art at native scale (1 art px = 1 game px), limited palette, nearest filtering, consistent light from the
  top-left like the rest of the game.
- Optional, subtle idle motion (max 1 px, 2-4 frames) only where it fits (leaves, cloud, glow).

## Deliverables

- `assets/platforms/<look>.png` (one sheet per look: row 0 = left cap, middle tiles, right cap as 8x8 cells; extra
  rows for animation frames) and `assets/platforms/manifest.json` (cell size, columns, frames per look), a
  `README.md` and a `preview.html` showing every look at widths 16, 24, 40, 80, following `assets/README.md`.
- Drawing: `JumpThru.draw` keeps its signature; draw the sheet for `look()`, falling back to the plank rail for an
  unknown look. Cache textures by look and width.
- A check runner like `tests/island_art.gd`: one sheet per environment, exact cell sizes, transparent background,
  art top row at the rect's top, nothing outside the allowed bounds, animation frames distinct where animated.
  Add it to `tools/verify.sh` with a success line.
- `sh tools/verify.sh` at 0 failing; one dated line in `gdd.txt`.

## Out of scope

Behaviour or collision changes, editing room files, new environments, sound.
