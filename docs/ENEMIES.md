# Combat enemies in the HK reference world

Five small enemies adapt recognizable encounter patterns from Metroid: Zero Mission and Castlevania. Artwork is original native pixel art in `scripts/enemy_art.gd`; no extracted game sprites are used. They share the player's block-scale palette and render as one cached texture quad per body.

| Type / editor label | Inspiration | Behaviour | Hits to defeat |
|---|---|---|---:|
| `enemy_ripper` / Ripper | Metroid: Zero Mission | Slow horizontal patrol; reverses at rock, bounds, and its local patrol limit | 2 |
| `enemy_skree` / Skree | Metroid: Zero Mission | Ceiling perch; detects a player below; 0.35s warning, accelerating dive, rest, return | 1 |
| `enemy_bat` / Bat | Castlevania | Perches until a visible player approaches; 0.4s warning; commits to a swoop, then returns | 1 |
| `enemy_skeleton` / Skeleton | Castlevania | Platform patrol, ledge avoidance; faces visible players, 0.45s warning, ballistic bone throw | 3 |
| `enemy_medusa` / Medusa | Castlevania | Horizontal sine-wave flight, 8px amplitude; reverses at terrain and patrol limits | 2 |

These are adaptations, not exact frame/timing reproductions. The Skree returns after a dive rather than shattering into fragments. The wave flyer is a finite local encounter rather than an infinite off-screen spawner.

## Three variants per family

Each base type has Original, Swift (`_swift`) and Armored (`_armored`) editor entries.
Swift versions use a coral palette, move 35% faster, warn for 25% less time, recover
30% faster, and have one fewer hit point (minimum one). Armored versions use slate
colours with bronze shoulder plates, move 25% slower, warn/recover 25% longer,
and have two extra hit points. Base-version timing is unchanged.

| Family | Original HP | Swift HP | Armored HP | Additional variation |
|---|---:|---:|---:|---|
| Ripper | 2 | 1 | 4 | Armored warns for 0.5s, then charges for up to 0.6s with a recovery pause |
| Skree | 1 | 1 | 3 | Dive and return speeds and warning/rest durations follow the variant |
| Bat | 1 | 1 | 3 | Swoop speed, warning and recovery differ |
| Skeleton | 3 | 2 | 5 | Armored throws a two-arc volley; cap remains three live bones |
| Medusa | 2 | 1 | 4 | Swift wave amplitude is 6px; Original 8px; Armored 12px |

All three versions share the same body collision size and facing alignment.
All fifteen versions are available in the editor, for example `enemy_bat_swift`
and `enemy_skeleton_armored`.

## Playing and editing

Choose **Adventure → World: Hollow Knight**. There are **90 real enemies across 51 rooms**, six of each variant. One Ripper introduces the set in King's Pass (`r005`, local top-left 840,1016). The first skeleton is in `r012`; the first Skree and bat are in `r017`. See `reports/hk-enemy-placements.json` for every position.

Attack with **A**, holding a direction to aim the melee swing. Enemies use the existing one-hit player death system. An enemy takes at most one hit per swing, with a brief hurt flash. Defeated enemies become harmless; they respawn when the room is rebuilt. No player health, movement or collision tuning was changed.

The skeleton's bones collide with terrain and room boundaries, expire after two seconds, and can be swatted by the attack's existing range/arc. Killing the skeleton removes its bones. A skeleton owns at most three bones. Flyers and walkers use pixel-step terrain collision and cannot cross room bounds. Target acquisition is distance-limited and requires line of sight. Enemies more than 320px from the player sleep; this also freezes owned bones until the player returns.

All fifteen types are registered in `Entities.TYPES` and available in the editor. Their collision sizes are fixed; `facing` selects initial direction, and `patrol` optionally selects a bounded range. Setup/drawing support editor previews without a world. Enemy hitboxes are not solid platforms.

## Placement and regeneration

Existing placeholder enemies were replaced selectively. All other placeholder populations, bosses, terrain, doors and entrance markers are preserved. Each replacement records its old label and position in `reference_text` / `reference_position` and is tagged `summit_enemy_set: 1`.

The placer preserves existing encounters and chooses open patrol envelopes, floor-supported skeletons and overhead perches with clear dive space. It avoids hazard footprints, keeps encounters apart, leaves at least 96px from local spawn/door markers, and installs at most two enemies per selected room (one in King's Pass). This is encounter-scale validation, not proof of whole-world progression.

```sh
python3 tools/place_reference_enemies.py          # dry run / idempotency check
python3 tools/place_reference_enemies.py --apply  # install after rebuilding HK reference data
```

Rebuilding `tools/reference_worlds.py` overwrites room edits; reapply the placer afterwards. It scans the current world manifest after prioritizing the original introductory rooms. Its room IDs target the current HK partition and will need updating if the partition changes.

## Art preview and tests

Open `assets/enemies/preview.html` for the animated sprite gallery. The export atlas is 64×240px: fifteen rows, four 16×16 frames per row. Regenerate it with:

```sh
godot --headless --path . --script res://tools/export_enemies.gd
python3 tools/run_enemy_tests.py  # focused enemy regressions, disposable runtime data
godot --headless --path . res://tests/test.tscn
godot --headless --path . res://tests/smoke.tscn
```

Deterministic tests cover wall reversal, warning/dive/recovery, line of sight, committed bat swoops, bounded wave flight, skeleton throws, melee parries, projectile terrain/bounds collision, damage/death, ledge avoidance, and actual HK placements. Smoke adds an on-screen encounter set to the generic entity registry sweep. Sprite atlas inspection is possible without a display; visual gameplay inspection still requires a desktop session.

The first five atlas rows retain their original order. Rows 5–14 hold Swift/Armored
pairs in family order. The placement regression also checks that repeat runs create
no duplicates and preserve all terrain and entrance/door markers.

## References

- [Metroid: Zero Mission manual, enemy section](https://metroid.retropixel.net/games/metroidzm/manual/metroidzm_manual.pdf).
- [Nintendo Playing with Power enemy guide](https://primagames.com/eguides/nintendo-playing-power-eguide/metroid/enemies) for classic Metroid enemy patterns.
- [Castlevania: Bloodlines manual](https://bdjogos.com.br/manuais/36-castlevania-bloodlines-mega-drive-manual-usa.pdf), “Some terrors that await,” for bat / Medusa visual archetypes.
- [Castlevania enemy guide](https://strategywiki.org/wiki/Castlevania/Enemies) and [Symphony of the Night Medusa movement reference](https://castlevaniaspeedruns.com/mediawiki/index.php?mobileaction=toggle_view_desktop&title=SOTN%2FMedusa_Head).
