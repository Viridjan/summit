# Summit enemy sprites

Original pixel artwork authored in `scripts/enemy_art.gd`, exported to `enemies.png`.
No extracted artwork from any other game is included. Behaviour adaptations,
controls, placement and references are documented in [ENEMIES.md](../../docs/ENEMIES.md).

Open `preview.html` for an animated gallery. The atlas has one row per enemy type in
`Entities.TYPES` order (the eight families, then each family's variants), four 32×32
frames per row. Small sprites sit centred in their cell; Giants are drawn at 2×.

Regenerate with `godot --headless --path . --script res://tools/export_enemies.gd`.
