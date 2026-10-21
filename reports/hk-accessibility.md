# Hallownest accessibility audit

Checked the local imported world `worlds/hollow_knight`, starting at King's Pass (`r005`, world tile 839,446). No world data was changed.

## Findings

- 232/232 rooms connect when hazards and movement limits are ignored. Every open terrain tile is connected through passages and/or doors in this optimistic model.
- All 108 door entities have valid targets (54 door pairs).
- Treating acid-covered tiles as impassable leaves **36 rooms unreached**.
- Also excluding spike-covered tiles leaves **39 rooms unreached**.

These are **static tile-connectivity results, not a completed physics playthrough**. Connectivity does not prove a jump, climb, door arrival, or return journey is possible. Narrow passages, finite player size, jump/dash reach, stamina, breakable-wall state, directional spike collisions, and precise liquid edges need runtime checks. The model permits movement in every direction without gravity, permits crouch-sized corridors, treats the breakable wall as already broken, and uses optimistic door destinations. Hazards are rounded outward to full tiles; this can flag routes that precise collisions allow.

## Acid-model unreached rooms

| Room | World position (tiles) | Local identifying markers |
|---|---|---|
| `r030` | 12, 554 | No named marker |
| `r058` | 1015, 702 | No named marker |
| `r063` | 1034, 729 | No named marker |
| `r065` | 985, 731 | No named marker |
| `r070` | 979, 781 | Bench |
| `r083` | 981, 838 | No named marker |
| `r098` | 1087, 887 | No named marker |
| `r157` | 1024, 1122 | Bench |
| `r166` | 1302, 1158 | Bench; Vendor: Tuk |
| `r167` | 1699, 1174 | No named marker |
| `r168` | 1163, 1178 | No named marker |
| `r169` | 1805, 1180 | No named marker |
| `r170` | 1746, 1181 | No named marker |
| `r172` | 1988, 1188 | No named marker |
| `r173` | 1089, 1190 | Bench |
| `r177` | 1804, 1217 | No named marker |
| `r198` | 1852, 1270 | No named marker |
| `r199` | 1913, 1274 | No named marker |
| `r200` | 1746, 1275 | No named marker |
| `r201` | 1699, 1277 | No named marker |
| `r208` | 1454, 1320 | Tram: Tram Station - Ancient Basin |
| `r209` | 1604, 1324 | No named marker |
| `r216` | 1335, 1364 | No named marker |
| `r217` | 1610, 1384 | No named marker |
| `r219` | 1208, 1405 | No named marker |
| `r221` | 1127, 1420 | Bench |
| `r222` | 1486, 1420 | No named marker |
| `r223` | 1748, 1442 | Bench; Stag station: Stag Station - Hidden Station |
| `r224` | 1044, 1456 | No named marker |
| `r225` | 1121, 1513 | No named marker |
| `r226` | 1434, 1513 | No named marker |
| `r227` | 1347, 1641 | No named marker |
| `r228` | 1596, 1681 | No named marker |
| `r229` | 1351, 1717 | No named marker |
| `r230` | 1939, 1755 | No named marker |
| `r231` | 1309, 1775 | No named marker |

## Additional rooms flagged only when spikes are included

- `r100` (2015, 893): Bench; Hot spring; Vendor: Little Fool
- `r105` (2153, 909): No named marker
- `r165` (220, 1156): No named marker

## Map and data

- `hk-accessibility.png`: green = reached with full-tile acid/spike exclusions; amber = reached only when hazards are ignored. This is not a movement feasibility map.
- `hk-acid-accessibility.png`: the same comparison with acid exclusions alone.
- The corresponding JSON files contain per-room reached/open tile counts and marker names.

## Next runtime checks

Prioritize the routes to `r208` (Ancient Basin tram), `r223` (Hidden Station), and `r166` (Tuk). Then check `r100`/`r105` near Little Fool, which are flagged only by the spike approximation. Notes for stag/tram stations are not functional transport links, so they cannot provide an alternate route in the current build.

## Runtime transition and edge-opening checks

The follow-up [room safety report](hk-room-safety.md) adds actual Godot transition probes, 60 Hz reproductions, one-frame boundary escapes, and every bad left/right opening. These checks expose collision failures that static connectivity alone cannot detect.
