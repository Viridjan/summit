# Summit enemy sprites

Original pixel artwork authored in `scripts/enemy_art.gd`, exported as one sheet per family (`thornmite.png`, `skree.png`, ... `mosstrot.png`): the original type in row 0, then its variants, four 32×32 frames per row; `manifest.json` lists the rows.
No extracted artwork from any other game is included. Behaviour adaptations,
controls, placement and references are documented in [ENEMIES.md](../../docs/ENEMIES.md).

Open `preview.html` for an animated gallery. Each family sheet has one row per type
(the original, then its variants in `Entities.TYPES` order), four 32×32 frames per row. Small sprites sit centred in their cell; Giants are drawn at 2×.

Regenerate with `godot --headless --path . --script res://tools/export_enemies.gd`.

Mosstrot, Cragjaw and Murkspore have a refined material pass: clustered leaf and
bark highlights, a faceted rock brow and toothy jaw, and a shaded mushroom cap
with gills. Their four poses use leaf sway, alternating heavy steps, and a
breathing cap/tendril cycle. Variants share the refined shapes and tint the new
highlight colours. Gameplay hitboxes, draw origins and enemy behaviour are unchanged.
`mosstrot.png`, `cragjaw.png` and `murkspore.png` show them at native resolution.

## Ape profile artwork

The arena boss and Sand Cave chase share original 32×32 side-view artwork from `scripts/ape_art.gd`. It faces its movement/attack direction and uses distinct idle, crouch, airborne, throw, scream and running silhouettes. Collision and attack areas retain their existing dimensions.

Rebuild `ape.png` with `godot --headless --path . --script tools/export_ape.gd`. Rows follow the pose order above, four frames per row.

The proposed silverback transformation is deferred as `ape-trueform` in
[`TODO.md`](../../TODO.md). Its artwork and preview are preserved in
[`pixel-art/ape-phase2`](../../pixel-art/ape-phase2/README.md).
Current phase two keeps the original sprites and adds a pulsing red tint.
