# Summit art review — 2026-10-26

Verdict: **FIX for visual consistency; preserve the existing character and environment foundation.** The largest gains come from consistent pixel presentation, clearer one-way platforms, and bringing the island scenery up to the older packs' standard.

Review uses pixel-art-studio's silhouette, cluster, palette, lighting, outline, animation, and export checklist. This is a review, with no production artwork or gameplay changes.

## Evidence and scope

- Inventoried 135 PNG files under `assets/`, including historical previews. Measured 114 non-preview/non-contact-sheet PNGs in [asset-stats.tsv](asset-stats.tsv).
- Visually inspected all 11 theme previews, terrain and decoration atlases, Nori's 13 pose rows, all 32 enemy rows, all six ape pose rows, the island pack, special-block examples, and legacy Paper Pixels sheets. Historical before-images are reference material, not the proposed visual target.
- Inspected procedural rendering in `art.gd`, `character_art.gd`, `enemy_art.gd`, `ape_art.gd`, `island_art.gd`, `block_art.gd`, `environment_art.gd`, `entities.gd`, and player drawing; reviewed gameplay/UI captures from the existing smoke runner.
- Captured 14 settled standalone room examples: ten themes used by the loaded story plus village, lighthouse, crater and crystal pocket. The unused-in-this-run `cavern` theme is covered by its exported preview. See [runtime overview](runtime-overview.png).
- Used the skill's `Sprite.from_png`, `stats()` and silhouette export on Nori, ape, serpent and a one-way rail. These have 11, 10, 9 and 6 visible colors respectively, no partial alpha and no near-duplicate colors under the skill's heuristic. Nori has one isolated pixel at atlas `(28,101)` in wall-slide frame 1: inspect the intended hand-drag pose before removing it.
- Read [the platform brief](../../docs/reviews/platform-art/CODEX_PROMPT.md) as requested. Its art/collision constraints are incorporated below.

Limitations: static frame inspection does not certify animation timing or every gameplay state. The smoke run exercised motion but no frame-by-frame motion recording was made. Settled captures use standalone playtests, so they do not establish adventure progression or dialogue behavior. The village's missing-door message in that capture is a standalone-context artifact, not evidence of a broken adventure door. The display manager produced 1280×1432 captures despite a requested 1280×720 window; black margins and HUD placement in those captures are not treated as native-resolution defects. Overview sheets are reduced navigation aids; inspect source PNGs/full screenshots for pixel judgments.

## Prioritized findings

### 1. High — fractional rendering undermines otherwise clean pixels

`scripts/world.gd:24` sets `ZOOM = 4.8`. Nearest filtering is correctly configured, but 1 source pixel cannot occupy a uniform integer number of screen pixels at this zoom. `scripts/environment_art.gd:56` also stretches a 320×180 painting to `view.size * 1.2`; at the nominal view this is approximately 320×180, with a different effective scale from terrain. Camera/character transforms introduce further fractional movement and squash.

Recommendation: evaluate an integer-scaled low-resolution world viewport, with UI rendered separately. Preserve the intended camera framing explicitly rather than merely replacing 4.8 with 4, which changes how much of the level is visible. Keep squash/stretch as a deliberate animation exception. Acceptance: compare a stationary scene, slow pan, run and jump at target resolutions; stationary terrain and background clusters should retain consistent screen-pixel widths.

### 2. High — one-way platforms do not explain their shared behavior

`JumpThru.draw` uses the enclosed beveled `jumpthru` slab; `Leaf.draw` paints segmented green bars. The generic object resembles a solid miniature block; the leaf lacks a convincing leaf silhouette. Both allow passage from below, but the art offers little shared indication of this.

Follow `docs/reviews/platform-art/CODEX_PROMPT.md`: keep the top at `rect.position.y`, never draw solid-looking pixels above it, never exceed its width, retain the 5px collision height, and allow only up to 3px of decorative underside. Use a clear lit standing edge with an open/light underside, capped seamless sections, and broad connected leaf clusters. A restrained material palette per environment would integrate the rail better than the current universal pale cyan bevel.

Acceptance: widths 16/24/40/80 across all eleven environments; leaves read as organic at native size; both types communicate one-way passage. Preserve the draw call sites and physics. The brief also requires an original-asset README, preview page, bounds checks, verify-runner integration and a dated `gdd.txt` note when implemented. No implementation is included in this review.

### 3. High — the three island themes look like an earlier production stage

Compare [theme overview](themes.png), [materials](materials.png), and `runtime/settled_island_shore.png`. Island terrain uses three colors and a strongly repeated hooked mark. All three packs reuse closely related rock decorations; shore/volcano backgrounds are dominated by the same cone and detached horizontal smoke bars. `volcanic_cave` has large rectangular teeth and a single arch, with little intermediate detail. Forest, building and temple have richer material language and depth.

Recommendation: retain angular silhouettes and quiet backgrounds, but add irregular connected rock strata, distinct shore/basalt/cave props, overlapping ash clusters, and two or three depth bands. Break motif repetition across wider areas rather than adding random single-pixel noise. Start with value grouping; adding colors alone will not solve this.

### 4. Medium — new humanoids are readable by costume but less modeled than Nori

Elves read through ears/headwear; mages through hats and robes. Their broad flat faces and rectangular torsos have fewer internal landmarks than Nori. In `runtime/settled_s3_lighthouse_top.png`, the pale beacon overlaps the light clouds in value; green villagers also compete with the forest palette.

Recommendation: strengthen one face/hand cluster, a darker far-side sleeve or leg, and one coherent shadow edge. Preserve native size, variant silhouettes and foot baseline. Give the beacon a darker backing/base separation without making the whole prop brighter. Avoid a global black outline pass: Nori already works primarily through colored clusters.

### 5. Medium — enemy variants need stronger behavioral identification

The nine base families have useful silhouette variety, especially Cragjaw, Murkspore and the skeleton. However, swift, shielded and other variants often share almost the same silhouette, relying on tint or very small marks. The source adds shoulder plates, brood spots and venom drips, but these are subtle at play size. See [all enemy rows](enemies-detail.png).

Recommendation: reserve one visible shape cue per dangerous distinction: a leading shield plate, a swept posture/fin, or a larger persistent venom sac. Judge in grayscale and against each assigned biome. Keep established collision bounds; don't imply protection or reach that behavior doesn't provide. Four-frame cycles generally make small pose changes; stronger contact/compression differences would improve weight for the heavier families.

### 6. Medium — serpent attack poses have less force than its scale suggests

The serpent has a clear S-neck and right-facing head with a compact nine-color palette. Warn/attack change head height and mouth, while coils remain largely fixed; the much smaller ape has stronger crouch/airborne/throw/run silhouette changes.

Recommendation: exaggerate anticipation through neck compression and jaw opening, then recovery through a distinct neck bend. Keep warning/eruption timing and combat bounds unchanged. Check the runtime destination rectangle before adding detail: Guardian drawing resizes the whole native 96×64 image to its entity rect, which can alter the intended proportions for other placements. This is a placement-dependent risk, not a confirmed defect in every room.

### 7. Medium — primitives and authored sprites use different visual languages

White triangular spikes are exceptionally legible. Refill diamonds, circular boosters/bumpers, rings, water rectangles, gates, notes and fragments use simpler procedural geometry alongside modeled pixel sprites. Several effects use fractional coordinates/radii. This is especially apparent around the ape's large thin circular effect and the saturated diamonds in the smoke room.

Recommendation: preserve the successful hazard silhouettes, then standardize a small set of native-grid edge weights, highlight placements and sparkle shapes. Give interactable fragments a distinctive shard silhouette and prompt treatment so they cannot be mistaken for passive refills. Preserve three-fragments-per-upgrade behavior and the project's interactable-discovery direction; do not introduce replacement stars.

### 8. Medium/low — menus communicate tools better than the game's identity

Main menu, pause, options, map, editor and Music Studio use readable system-style controls, but the title screen has no authored mountain/character composition. Map markers are largely small colored dots; the editor sidebar distinguishes many entries by text/color rather than miniature art. See [UI overview](ui-overview.png) and `runtime/menu.png`.

Recommendation: add one restrained pixel-art title composition and consistent illustrated category/interaction icons. Retain readable UI text; a pixel font is optional. Keep technical editors functional and separate from the world palette. Give important map marker categories shape differences, then inspect actual-size legibility and keyboard focus states.

## Coverage and disposition

| Group | Keep | Next improvement |
|---|---|---|
| Nori, 13 states | Small palette, backpack identity, coherent near/far legs, authored air poses | Check wall-slide isolated pixel and animation in motion; avoid wholesale redraw |
| Ape, six poses | Strong profile, arm/knuckle mass, recognizable pose changes | Verify telegraphs and thin effects against both cave and forest |
| Enemy families/variants | Distinct base species; expressive jaw and cap silhouettes | Behavioral variant shapes and weight/contact poses |
| Sand / sea | Warm/cool distinction, clear terrain tops | Reduce material repetition; expand cactus/coral prop silhouettes |
| Cavern / cavern_deep | Quiet values, crystal accents, readable surfaces | Differentiate more than darkness; avoid losing dark enemies |
| Sky | Calm stepped clouds and clean surfaces | Preserve foreground separation on light clouds |
| Temple | Pillar rhythm, architectural material | More broken/offset motifs so repeated pillars feel less uniform |
| Building | Timber houses, pitched roofs, fence/wheat language | Interior-specific scenery where the room is inside a house |
| Forest | Layered trunks, canopy, roots, restrained depth | Better villager contrast; leaf platform silhouette |
| Island shore / volcano / volcanic cave | Clear broad biome colors | Highest-priority environment refinement, described above |
| Breakwall / crumble / falling / zip | Continuous perimeter across arbitrary sizes; good material separation | Strengthen small-size symbols; reduce common box framing where behavior differs |
| Dream blocks | Strong dark field, star motion and perimeter identity | Review actual runtime art; teal exports are explicitly unused references |
| Island props | Raft sail, mirror and landmark silhouettes | Root arch thickness/material and beacon background separation |
| Rock / warning / impact / eruption / lava | Simple danger colors and hard alpha | More expressive breakup/eruption clusters; distinguish visual states without noise |
| Legacy Paper Pixels | Useful compact terrain vocabulary; retain license | Treat unused legacy player and before-images as references, not cleanup targets |
| HUD / prompts / map / touch controls / editors | Clear labels and keyboard/pad prompts | Shared icon vocabulary, native-size marker tests, restrained title artwork |

## Suggested order and verification

1. Establish pixel presentation and camera-framing policy.
2. Implement the narrowly scoped platform brief.
3. Refine the island materials/backgrounds and NPC separation.
4. Strengthen enemy/boss pose and variant cues.
5. Unify effects, interaction icons and title-screen identity.

For artwork revisions use the established GDScript authoring/export sources rather than editing derived PNGs. Require native-size and integer-enlarged previews, grayscale/silhouette checks, and a motion review for animations. Do not apply a single color budget to the entire enemy atlas: 89 colors across 32 variants is not itself palette bloat. The only measured partial-alpha source here is the legacy `assets/paper-pixels/Player.png` (118 pixels); that does not establish a current player-rendering issue.

The existing rendered smoke runner exited 0 with `SMOKE OK`; it emitted an ApeChase path warning in its synthetic fixture. The additional capture runner exited 0 with `ART CAPTURE OK`. No production code changed, and no gameplay-suite pass is claimed. The verification-before-completion skill is used to check these results and the review artifacts before delivery.
