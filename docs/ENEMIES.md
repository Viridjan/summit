# Combat enemies in the HK reference world

Six small enemies with original names and original pixel art (`scripts/enemy_art.gd`; no extracted game sprites). Three adapt encounter patterns from Hollow Knight. The other three adapt patterns from Metroid: Zero Mission and Castlevania. Each one renders as a single cached texture quad.

| Type id / name | Inspired by | Behaviour | Hits to defeat |
|---|---|---|---:|
| `enemy_thornmite` / Thornmite | HK Tiktik | Crawls around terrain: floors, walls and ceilings, turning at inner and outer corners. Drops to the floor if placed in the air | 2 |
| `enemy_skree` / Dropwing | Metroid ceiling divers | Ceiling perch; spots a player below. 0.35s warning, accelerating dive, rest, then returns (waits if blocked) | 1 |
| `enemy_bat` / Duskflit | Castlevania bats | Perches until a visible player is near. 0.4s warning, then a committed swoop and a return | 1 |
| `enemy_skeleton` / Ossling | Castlevania bone throwers | Platform patrol with ledge avoidance. Faces visible players; 0.45s warning, then a ballistic bone throw | 3 |
| `enemy_hornback` / Hornback | HK charging husks | Floor patrol. A player at its height in sight gets a 0.5s warning, then a fast charge that stops at walls, ledges and hazards | 3 |
| `enemy_fuzzbob` / Fuzzbob | HK Gruzzer | Drifts diagonally and bounces off anything solid. It never chases; its path is the threat | 2 |

The type ids `enemy_skree`, `enemy_bat` and `enemy_skeleton` are internal and were kept, so existing levels still load. Only the names shown in game and in the editor changed.

## Three variants per family

Each base type has Original, Swift (`_swift`) and Armored (`_armored`) editor entries.

- **Swift:** coral palette, 35% faster, 25% shorter warnings, 30% faster recovery, one fewer hit point (minimum one).
- **Armored:** slate palette with bronze shoulder plates, 25% slower, warnings and recovery 25% longer, two extra hit points.

| Family | Original HP | Swift HP | Armored HP | Notes |
|---|---:|---:|---:|---|
| Thornmite | 2 | 1 | 4 | Crawl speed follows the variant |
| Dropwing | 1 | 1 | 3 | Dive and return speeds, warning and rest follow the variant |
| Duskflit | 1 | 1 | 3 | Swoop speed, warning and recovery differ |
| Ossling | 3 | 2 | 5 | Armored throws a two-arc volley; at most three live bones |
| Hornback | 3 | 2 | 5 | Charge speed, warning and rest follow the variant |
| Fuzzbob | 2 | 1 | 4 | Drift speed follows the variant |

All three versions of a family share the same collision size and facing alignment. All 18 types are available in the editor and on the Monsters page (main menu, and the map screen's second tab).

## Playing and editing

Choose **Adventure → World: Hollow Knight**. There are **108 enemies across 68 rooms**, six of each variant. A Thornmite introduces the set in King's Pass (`r005`). See `reports/hk-enemy-placements.json` for every position.

Attack with **A**; hold a direction to aim the swing. Enemies use the existing one-hit player death system. An enemy takes at most one hit per swing, with a brief hurt flash. Defeated enemies become harmless and respawn when the room is rebuilt.

Ossling bones collide with terrain and room bounds, expire after two seconds, and can be swatted by the attack. Enemies more than 320px from the player sleep. Target acquisition is distance-limited and needs line of sight. Enemy hitboxes are not solid platforms.

## Placement and regeneration

`tools/place_reference_enemies.py` replaces selected HK placeholder enemies. Each replacement is tagged `summit_enemy_set: 1` and records the placeholder's `reference_text`, `reference_position` and `reference_size`. When a kind is removed from the tool, its placements turn back into the original placeholders on the next run, and new kinds take free slots.

The placer has different rules per enemy type:
- **Floor walkers (Thornmite, Ossling, Hornback):** stand on a 7-tile floor with clear space either side.
- **Dropwing and Duskflit:** need an overhead perch with clear dive space below.
- **Fuzzbob:** needs a wide open area.

It also:
- avoids hazards;
- keeps encounters apart;
- stays at least 96px from spawns and doors;
- uses at most two enemies per room (one in King's Pass).

```sh
python3 tools/place_reference_enemies.py          # dry run / idempotency check
python3 tools/place_reference_enemies.py --apply  # install, then write the report
```

Rebuilding `tools/reference_worlds.py` overwrites room edits, so run the placer again afterwards. Its room list targets the current HK partition.

## Art preview and tests

Open `assets/enemies/preview.html` for the animated gallery. The atlas is 64×288px: 18 rows of four 16×16 frames. Rows 0–5 hold the families in the order above. Rows 6–17 hold the Swift/Armored pairs in the same order.

```sh
godot --headless --path . --script res://tools/export_enemies.gd  # regenerate enemies.png
python3 tools/run_enemy_tests.py  # focused enemy checks
godot --headless --path . res://tests/test.tscn
godot --headless --path . res://tests/smoke.tscn
python3 -m unittest tests/test_reference_enemy_placement.py
```

The checks cover:
- **Thornmite:** crawling over a block, and dropping to the floor.
- **Hornback:** its warning, charging, and stopping at walls and ledges.
- **Fuzzbob:** bounces.
- **Dropwing:** the dive and return.
- **Duskflit:** line of sight and the committed swoop.
- **Ossling:** throws, parries and bone collisions.
- **All enemies:** damage, variants, original names, and the real HK placements.

## References

- Hollow Knight (Team Cherry): Tiktik, charging husks and Gruzzer as encounter archetypes.
- [Metroid: Zero Mission manual, enemy section](https://metroid.retropixel.net/games/metroidzm/manual/metroidzm_manual.pdf).
- [Castlevania enemy guide](https://strategywiki.org/wiki/Castlevania/Enemies).
