# Nori — Summit character

Original mountain-courier pixel artwork, authored in `scripts/character_art.gd`.
Swept dark brown hair, blue parka, copper backpack, dark boots, and flowing dash-colour locks.
No Celeste sprite artwork is included. Existing Paper Pixels assets and licenses
remain available unchanged.

The character follows animation principles visible in the published Celeste
[player controller](https://github.com/NoelFB/Celeste/blob/master/Source/Player/Player.cs):
state-specific poses, counterbalanced skids, squash/stretch, and a trailing dash
colour cue. Nori's body poses and appearance are original to this repository.

## Preview and edit

Open `preview.html` in a browser for all 13 animated states, facing and hair controls.
`nori.png` is a reference/export atlas: 128×208, eight columns of 16×16 frames.
Rows, counts and playback rates are defined by `CharacterArt.ANIMATIONS`.

Edit the native pixel-shape authoring code, then refresh the exported atlas:

```sh
godot --headless --path . --script res://tools/export_nori.gd
```

Gameplay builds and shares one texture from that same source; it does not load the
reference PNG. No per-frame image generation is required. The player applies facing,
existing squash/stretch, tired/feather tinting, and the dash-colour hair separately.
The hair uses the existing trailing-chain positions. A stationary wall hold freezes
the climbing cycle; run cadence follows speed. The original hitboxes, timestep,
movement tuning, and collision logic are unchanged.

Rendered gameplay still needs manual inspection on a working display. The HTML
preview shows body animation, with a stylized hair rather than game physics.

## Validation

Both existing Godot runners pass (198 checks; smoke reports `SMOKE OK`), with
no script errors. New checks cover atlas bounds, every populated frame, cached
texture reuse, animation transitions, landing recovery, stationary wall holds,
and unchanged physical hitboxes. The exported atlas was visually inspected.
The preview JavaScript passes `node --check`. Browser screenshot automation and
rendered gameplay inspection were unavailable in this session due to display
and socket restrictions.

## Side-view run cycle

The run row uses eight authored leg poses: contact, down, passing and recovery,
then the opposite leg. Contact frames plant one boot while the other bends and passes above it.
Each half-cycle then has a brief flight frame with both boots off the baseline. A darker far-leg shade separates the two legs at this scale.
The supporting foot travels backward through each step rather than both boots
spreading apart on the floor. Hip placement, body height and draw origin stay
fixed; speed scaling and movement physics are unchanged. `run-poses.png` shows
the full row. The browser preview uses the current idle timing and avoids adding
a run-only hair bob that the runtime does not apply.

### Coordinated motion pass

Running now uses four rows for hips and bent legs, a sleeve swing opposite the
forward knee, and a one-pixel compression on each down-step. Hair anchors follow
the same head drop. Jump, apex and fall have full authored poses with sleeves
below the face, connected hips, tucked knees and distinct recovery frames.
The preview includes a complete jump arc and left/right run examples so pose
transitions can be assessed in motion. Character height and gameplay are unchanged.

### Celeste motion reference pass

Reviewed the moving `UndergrowthGif3.gif` in the map creator's
[gameplay gallery](https://nicgib.github.io/project-celeste.html), frame by frame.
The official [Celeste trailer](https://www.youtube.com/watch?v=FqBj2IGg6Uw)
could not be fetched in this environment. Celeste's published
[player animation selection](https://github.com/NoelFB/Celeste/blob/master/Source/Player/Player.cs)
was also checked for its speed and rise/fall state handling. Reference media stays
outside the project; no Celeste pixels were copied into Nori's assets.

The revised run uses an 18fps base cadence, alternating contacts and two short
flight poses across the eight-frame cycle. The visible sleeve changes phase
when the near/far legs swap. Existing speed scaling still controls playback.
Jump knees tuck underneath the body rather than projecting sideways. Apex and
fall now advance into a settled pose and hold, instead of looping the legs while
falling. The HTML preview follows the same non-looping rules and frame timings.
Hitboxes, velocities, jump height and movement controls are unchanged.

### Leg and hair revision

Slate trousers use a darker far leg and a lighter near leg, with warm tan boots. Revised run poses separate knee bends and planted feet. Hair is dark brown when a dash is available and neutral gray when empty; refilling restores brown. Head and trailing locks share the same neutral shading, without the former white cooldown flash.
