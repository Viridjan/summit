# Summit enemy sprites

Original pixel artwork authored in `scripts/enemy_art.gd`, exported to `enemies.png`.
No extracted artwork from any other game is included. Behaviour adaptations,
controls, placement and references are documented in [ENEMIES.md](../../docs/ENEMIES.md).

Open `preview.html` for an animated gallery. The atlas has one row per enemy type in
`Entities.TYPES` order (the nine families, then each family's variants), four 32×32
frames per row. Small sprites sit centred in their cell; Giants are drawn at 2×.

Regenerate with `godot --headless --path . --script res://tools/export_enemies.gd`.

Mosstrot, Cragjaw and Murkspore have a refined material pass: clustered leaf and
bark highlights, a faceted rock brow and toothy jaw, and a shaded mushroom cap
with gills. Their four poses use leaf sway, alternating heavy steps, and a
breathing cap/tendril cycle. Variants share the refined shapes and tint the new
highlight colours. Gameplay hitboxes, draw origins and enemy behaviour are unchanged.
`new-families.png` shows these three rows at native resolution.
