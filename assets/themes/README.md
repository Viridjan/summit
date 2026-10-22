# Summit environment themes

Original procedural pixel art authored for Summit, following its existing 8×8
terrain scale, bright top edges, shaded side/bottom edges and quiet scenery.
No third-party images were added or modified. Existing Paper Pixels attribution
and licenses remain in `assets/paper-pixels/`.

Open `preview.html` for all seven themes: sand, sea, cavern, cavern_deep, sky,
temple and building. The HK world assigns a theme to each room using its `environment` field.
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
