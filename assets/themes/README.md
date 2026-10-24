# Summit environment themes

Original procedural pixel art authored for Summit, following its existing 8×8
terrain scale, bright top edges, shaded side/bottom edges and quiet scenery.
No third-party images were added or modified. Existing Paper Pixels attribution
and licenses remain in `assets/paper-pixels/`.

Open `preview.html` for all eight themes: sand, sea, cavern, cavern_deep, sky,
temple, building and forest (the story world's jungle: grass tops, trunks, vines, ferns). Rooms pick a theme with their `environment` field.
The rural building theme uses timber, plaster and pitched-roof cottages.
Gameplay, editor and neighbouring-room terrain use the same room-local art. None of these graphics imply collision,
water behaviour, hazards or light sources.

Each theme directory contains:

- `terrain.png`: 128×32 RGBA atlas. Four material variants, one per row. Each
  8×8 cell's column is an exposed-edge mask: top=1, right=2, bottom=4, left=8.
  Add the relevant bits, so column 0 is interior, 9 is a top-left outer corner,
  and 15 is an isolated tile. Use a stable coordinate hash for variant choice.
- `inner_corners.png`: 32×8 transparent overlay atlas, in TL, TR, BL, BR order.
  Overlay a cell when both adjacent cardinal neighbours are solid but their
  shared diagonal neighbour is empty. This completes concave terrain joints.
- `decorations.png`: eight transparent 16×16 prop cells. Bottom aligned; place
  outside collision terrain. Cacti, coral, crystals, cloud wisps, broken columns
  or rural fences, barrels, wheat and signposts match the theme.
- `background.png`: opaque 320×180 distant scenery.
- `foreground.png`: transparent 320×180 nearer scenery for separate parallax.
  These are room-sized compositions, not horizontally seamless textures.
- `preview.png`: example scenery, terrain and prop composition.

Use nearest-neighbour filtering and integer positions/scales. Terrain is drawn
without scaling, so a game block stays 8 pixels. Background images can be drawn
behind gameplay with different camera factors. For large rooms repeat individual
motifs or compose additional scenery; do not stretch foreground terrain tiles.

Regenerate all PNGs deterministically:

```sh
godot --headless --path . --script res://tools/export_themes.gd
```

The exporter is self-contained and does not change level data or runtime art.

## Environment refinement

The export tool now builds quieter terrain material clusters, varied decorative
silhouettes and additional scenery depth for all eight themes. Forest foliage
uses layered pixel clusters, irregular trunks, branches and roots; rural cottages
retain pitched roofs with subtle shingles, timber braces and chimney smoke.
The atlas layout, collision grid and existing room assignments are unchanged.

Open `review/index.html` for before/after compositions; `review/before/` preserves
the artwork reviewed in this pass. `contact-sheet.png` shows the current eight
scenes. Both are review assets, not runtime texture dependencies.

### Squared visual style

Environment silhouettes use broad rectangular clusters and clear stepped edges.
Clouds, foliage, bushes, smoke, stones and mushroom caps avoid rounded outlines.
Cave ceilings, dunes, hills, waves and vines use stepped profiles. Preserve this
angular style when extending the packs. The before/after review now compares the
previous rounded pass against the squared revision.
