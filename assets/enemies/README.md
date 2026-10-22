# Summit enemy sprites

Original pixel artwork authored in `scripts/enemy_art.gd`, exported to `enemies.png`.
No extracted Metroid or Castlevania artwork is included. Behaviour adaptations,
controls, placement and references are documented in [ENEMIES.md](../../docs/ENEMIES.md).

Open `preview.html` for an animated gallery. Each 16×16 cell belongs to a shared
64×80 atlas: Ripper, Skree, bat, skeleton, Medusa Head, in that row order.

Regenerate with `godot --headless --path . --script res://tools/export_enemies.gd`.
