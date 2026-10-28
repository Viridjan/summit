# ape-trueform — deferred concept

Original Summit pixel artwork, created with pixel-art-studio/Pillow. No external
sprite artwork is used. Native cells are 32×32 RGBA with binary transparency,
a shared bottom-center anchor, top-left light, dark outlines, and a twelve-color
palette recorded in `manifest.json`.

`build.py` is the editable source. It generates `ape-phase2.png` here, a labelled 4× sheet,
silhouettes, palette swatch, and run/jump GIFs. Dependencies: Pillow and the
installed pixel-art-studio skill at `~/.codex/skills/pixel-art-studio`.

```sh
python3 pixel-art/ape-phase2/build.py
godot --headless --editor --path . --import --quit
godot --headless --path . --script tests/ape_art.gd
```

Open `preview.html` for all fourteen poses, facing/background controls, animated
run and jump previews, and before/after arena captures. Four frame columns per
row; rows follow `manifest.json`. Run is four frames at 10fps. Other poses hold
one authored frame; ascent/apex/descent follow the existing velocity selection.

This set is approved as a future direction and deferred under `ape-trueform`
in `TODO.md`. It is not loaded by the game. Phase two currently uses the original
brown sprites with a red pulse. The before/after images below are historical
concept captures, not the current runtime appearance. Rebuilding this concept
writes only into this directory.

Visual passes: first refined the mantle into broken fur clusters, then checked
all pose silhouettes and the rendered arena. The final atlas has twelve colors,
no partial alpha, no isolated pixels and no near-duplicate colors under the
skill's stats heuristic. Run frames and the jump sequence are provided for
timing review. The capture helper freezes simulation for reproducible images.
