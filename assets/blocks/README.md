# Connected special-block graphics

Original native pixel art in `scripts/block_art.gd`. Gameplay and editor use the
same artwork. Every entity rectangle has a single continuous perimeter: light
top/left edges, shadowed bottom/right edges, four corner joints, material grain,
and one central symbol where it fits. Shapes are authored at their exact world
size, so thin platforms and non-multiple-of-8 sizes keep their end caps.

Styles: cracked breakable wall, brittle crumble platform, riveted falling block,
brass moving block, and thin one-way rail. Dream blocks retain their original
dark fill, white outline, and animated stars; the teal reference exports are unused. Damage and shaking
remain tied to existing entity states; hitboxes and mechanics are unchanged.

Open [preview.html](preview.html) for labelled examples at several sizes and damage
states. One sheet per style (`<style>.png`: one 56×32 cell per example size; breakwall adds a
damage row), described in `manifest.json`. They are reference exports, not runtime dependencies.

```sh
godot --headless --path . --script res://tools/export_blocks.gd
```

Textures are shared by style/size/damage. The shared cache has an LRU pixel budget
(one oversized texture may exceed it); current canvas draw commands retain their
textures independently, so eviction cannot remove artwork still being displayed.
Existing Paper Pixels sprites and their licenses are preserved.
