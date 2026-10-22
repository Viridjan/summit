# Summit enemy sprites

Original pixel artwork authored in `scripts/enemy_art.gd`, exported to `enemies.png`.
No extracted artwork from any other game is included. Behaviour adaptations,
controls, placement and references are documented in [ENEMIES.md](../../docs/ENEMIES.md).

Open `preview.html` for an animated gallery. Each 16×16 cell belongs to a shared
64×288 atlas: the first six rows are Thornmite, Dropwing, Duskflit, Ossling, Hornback
and Fuzzbob. Rows 6–17 contain Swift/Armored pairs in the same family order.

Regenerate with `godot --headless --path . --script res://tools/export_enemies.gd`.
