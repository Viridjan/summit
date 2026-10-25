# Eastern island and village artwork

Original deterministic pixel art authored in `scripts/island_art.gd`. No
third-party images, extracted sprites, or generated-image services were used.
Flat color clusters, angular silhouettes, nearest-neighbor filtering; existing
sprite licenses elsewhere in the project are unchanged.

Open [preview.html](preview.html) for an animated gallery. `manifest.json`
records native cell sizes, row names, variants, anchors and provenance. Every
atlas has four frame columns; rows are grouped first by appearance, then pose.

| Asset | Native cell | Rows |
|---|---|---|
| Serpent | 96×64 | idle, move, warn, attack, hurt, defeat |
| Rock | 16×16 | falling/tumbling rock frames |
| Rock warning / impact | 24×8 / 32×16 | four warning / breakup frames |
| Eruption | 24×32 | four fire-column frames |
| Vent | 16×8 | intact, broken |
| Elf / mage | 16×16 | idle, walk, talk, gesture; five appearances each |
| Landmark | 32×32 | split rock, crystal group, root arch (three variants) |
| Raft | 48×24 | four sail frames |
| Mirror / beacon | 24×24 / 24×32 | mirror; animated magical flame |
| Lava | 32×8 | four surface frames |

## In-game use

- The current Guardian uses the serpent artwork, with its existing eruption
  behavior, collision bounds, gate logic and persistence. This is an art pass,
  not a new moving or segmented serpent combat system.
- Existing Ape stones keep their original artwork, as requested. The separate
  falling-rock pack is exported for a future dedicated rockfall hazard;
  no new rockfall gameplay was added. Warning and impact assets are available.
- Five elves inhabit Treetop Village and five mages inhabit Lighthouse Top.
  Their visible heights range from 11–15 pixels, close to Nori's 12-pixel
  standing height. Each has different headwear/hair, proportions and small
  accessories, as well as subtle palette changes; they share a foot baseline.
  These are animated decorative entities. Walking/talking/gesture rows are
  available, but default placements idle. No dialogue, quests or pathfinding
  were added. Magic flame and mirror are visual props, not a mirror puzzle.
- Island rooms use new `island_shore`, `volcano` and `volcanic_cave` themes.
  Maze junctions have distinct landmarks. Lava reuses existing acid behavior
  with `skin: "lava"`; its damage rules are unchanged.
- Raft artwork decorates the existing island entrance; actual quest-gated
  raft travel remains separate from these assets.

## Rebuild

```sh
godot --headless --path . --script res://tools/export_island_art.gd
godot --headless --editor --path . --import --quit
python3 tools/story/dress_regions.py
godot --headless --path . --script res://tests/island_art.gd
```

The exporter writes only this pack and the three new environment directories.
It does not regenerate the eight existing themes. The dressing script is
idempotent: it edits regional environment/visual metadata and marked decorative
entities, preserving terrain and gameplay entities. Re-run it after regenerating
island or village room files with the existing story generators.
