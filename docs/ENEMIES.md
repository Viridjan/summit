# Combat enemies

Nine enemy families with original names and original pixel art (`scripts/enemy_art.gd`; no extracted game sprites). Each family comes in the variants that suit its behaviour (Mosstrot has none). 32 types in all.

## Families

| Family (type id) | Inspired by | Behaviour | HP | Variants |
|---|---|---|---:|---|
| Thornmite (`enemy_thornmite`) | HK Tiktik | Crawls around terrain: floors, walls and ceilings, turning at every corner. Drops to the floor if placed in the air | 2 | Swift, Venom, Brood, Giant |
| Dropwing (`enemy_skree`) | Metroid ceiling divers | Ceiling perch; spots a player below. Warning, accelerating dive, rest, return | 1 | Swift, Armored, Venom |
| Duskflit (`enemy_bat`) | Castlevania bats | Perches until a visible player is near. Warning, then a committed swoop and a return | 1 | Swift, Brood |
| Ossling (`enemy_skeleton`) | Castlevania bone throwers | Platform patrol with ledge avoidance. Faces visible players; throws arcing bones | 3 | Armored, Shielded, Giant |
| Hornback (`enemy_hornback`) | HK charging husks | Floor patrol. A player at its height in sight gets a warning, then a fast charge that stops at walls, ledges and hazards | 3 | Shielded, Swift, Giant |
| Fuzzbob (`enemy_fuzzbob`) | HK Gruzzer | Drifts diagonally and bounces off anything solid. It never chases | 2 | Brood, Venom, Giant |
| Cragjaw (`enemy_cragjaw`) | HK heavy brutes | Big (20×20) brute. Plods along its floor; a player in reach gets a warning, then a leap that slams down near them | 6 | Armored, Shielded |
| Murkspore (`enemy_murkspore`) | HK Aspid | Big (16×14) hovering spore. Keeps about 80px away and spits a three-orb spread at a visible player | 5 | Swift, Venom, Brood |
| Mosstrot (`enemy_mosstrot`) | HK Crawlid | Story jungle wanderer. Walks back and forth on its floor, turning at walls and ledges; never chases. Touching it still hurts | 2 | none |

The type ids `enemy_skree`, `enemy_bat` and `enemy_skeleton` come from the families' earlier names. They were kept so existing levels still load.

## Variants

A type id is `enemy_<family>_<variant>`. Variant stats are in `CombatEnemy.VARIANTS` (`scripts/entities.gd`), and each variant has its own palette in `EnemyArt.TINTS`.

| Variant | Look | Effect | HP |
|---|---|---|---|
| Swift | coral | 35% faster; warnings 25% shorter; recovers 30% faster | −1 (minimum 1) |
| Armored | slate, bronze shoulder plates | 25% slower; warnings and recovery 25% longer. Armored Ossling throws a two-arc volley | +2 |
| Giant | red-brown, 2× size | Body and sprite twice the size (grows from its top-left); 30% slower | ×2 |
| Shielded | gold tint, bright edge on its front | Blocks hits from the side it faces; hit it from behind or from above | +1 |
| Brood | pale, egg spots | Splits into two small, fast, one-hit copies when killed | same |
| Venom | toxic green, dripping | Leaves 3-second poison puddles that kill on touch. Thornmite leaves them on the surface it crawls on; others drip onto the floor below | same |

Ossling bones and Murkspore orbs collide with terrain and room bounds, expire after a few seconds, and can be swatted by the attack. Enemies more than 320px from the player sleep. Target acquisition is distance-limited and needs line of sight. Enemy hitboxes are not solid platforms.

## Playing and editing

Choose **Adventure → World: Hollow Knight**. There are **96 enemies across 59 rooms**: three of each type. A Thornmite introduces them in King's Pass (`r005`). See `reports/hk-enemy-placements.json` for every position. All 32 types are in the editor and on the Monsters page (main menu, or the map screen's second tab).

Attack with **A**; hold a direction to aim the swing. Enemies use the existing one-hit player death system. An enemy takes at most one hit per swing, with a brief hurt flash. Defeated enemies become harmless and respawn when the room is rebuilt.

## Placement and regeneration

`tools/place_reference_enemies.py` replaces selected HK placeholder enemies. Its `FAMILIES` table must match `Entities.TYPES`. Each replacement is tagged `summit_enemy_set: 1` and records the placeholder's `reference_text`, `reference_position` and `reference_size`. On each run:
- Placements of removed types, and any beyond three per type, turn back into their placeholders.
- New types take free slots.
- Each enemy's text and size are refreshed.

The placer has different rules per enemy type:
- **Floor walkers (Thornmite, Ossling, Hornback, Cragjaw, Mosstrot):** stand on a floor that reaches 3 tiles past each side, with clear space around.
- **Dropwing and Duskflit:** need an overhead perch with clear dive space below.
- **Fuzzbob and Murkspore:** need a wide open area.

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

## Art and tests

The atlas (`assets/enemies/enemies.png`, preview in `assets/enemies/preview.html`) has one row per type in `Entities.TYPES` order. Each row is four 32×32 frames, and small sprites sit centred in their cell. `EnemyArt.draw(..., scale)` draws Giants at 2× and Brood children at 0.5×.

```sh
godot --headless --path . --script res://tools/export_enemies.gd  # regenerate enemies.png
python3 tools/run_enemy_tests.py  # focused enemy checks
godot --headless --path . res://tests/test.tscn
godot --headless --path . res://tests/smoke.tscn
python3 -m unittest tests/test_reference_enemy_placement.py
```

The checks cover:
- **Atlas:** it matches the registry.
- **Each family:** its behaviour.
- **Each variant:** HP, size and look.
- **Shielded:** front/back/above hits.
- **Brood:** splitting.
- **Venom:** puddles that kill, then dry up.
- **Giant:** drawing at 2×.
- **Cragjaw:** the leap and slam.
- **Murkspore:** spit and swat.
- **HK world:** the real placements.

## References

- Hollow Knight (Team Cherry): Tiktik, charging husks, Gruzzer, Aspids and heavy brutes as encounter archetypes.
- [Metroid: Zero Mission manual, enemy section](https://metroid.retropixel.net/games/metroidzm/manual/metroidzm_manual.pdf).
- [Castlevania enemy guide](https://strategywiki.org/wiki/Castlevania/Enemies).
