# Art assets: layout standard

Most art is drawn by code at runtime (`scripts/*_art.gd`); the PNGs next to it are reference exports for previews,
the main menu's Art screen and review. The game loads PNGs only from `paper-pixels/` and the theme folders.

| Folder | Runtime? | Source | Regenerate |
|---|---|---|---|
| `paper-pixels/` | yes (`scripts/art.gd`) | Paper Pixels by VEXED, CC0 (third-party names kept) | - |
| `themes/<theme>/` | yes: `background`, `foreground`, `terrain`, `decorations`, `inner_corners` (`preview` is reference) | `tools/export_themes.gd`, `tools/export_island_art.gd` | see `themes/README.md` |
| `nori/` | no (`scripts/character_art.gd`) | original | `tools/export_nori.gd` |
| `enemies/` | no (`scripts/enemy_art.gd`, `scripts/ape_art.gd`) | original | `tools/export_enemies.gd`, `tools/export_ape.gd` |
| `blocks/` | no (`scripts/block_art.gd`) | original | `tools/export_blocks.gd` |
| `island/` | no (`scripts/island_art.gd`) | original | `tools/export_island_art.gd` |

Rules for new art:
1. **One sheet per subject** (a character, an enemy family, a block style): columns are animation frames, rows are
   poses or variants, every cell the same size. Single images only for things the game loads as one image (theme
   backgrounds, terrain atlases).
2. **A `manifest.json` per folder** with the cell size and what each sheet's rows are (see `island/`, `enemies/`,
   `blocks/`); sizes never go in file names.
3. **Names**: lowercase `snake_case`, the subject's name (`thornmite.png`, `serpent.png`).
4. **Each folder** has a `README.md` (source, licence, how to regenerate) and one `preview.html`.
5. Review captures and before/after shots go under `docs/reviews/`, not here.
