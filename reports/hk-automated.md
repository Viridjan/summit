# World accessibility audit

World: `worlds/hollow_knight`. Start: `r005`. 232 rooms; 108 door entities.

This is a static connectivity test, **not a physics playthrough**. It ignores gravity, jump/dash reach, stamina, and return paths. Crouch models allow a one-tile body everywhere; standing requires two vertical tiles (conservative for the actual 8×11px hitbox). Breakable walls are assumed broken. Hazard rectangles are rounded outward to tiles; spikes are treated as lethal from every direction. Doors allow any valid target tile, rather than reproducing the runtime arrival offset. No enemies or moving entities are simulated, and temporary travel above room tops is omitted. Results identify routes to investigate; neither green cells nor flagged rooms establish live traversability.

Map: green = standing model; blue = crouch model only; amber = topology only; red = disconnected even without hazards.

| Model | Reached rooms | Unreached rooms |
|---|---:|---|
| topology | 232/232 | None |
| acid | 196/232 | `r030`, `r058`, `r063`, `r065`, `r070`, `r083`, `r098`, `r157`, `r166`, `r167`, `r168`, `r169`, `r170`, `r172`, `r173`, `r177`, `r198`, `r199`, `r200`, `r201`, `r208`, `r209`, `r216`, `r217`, `r219`, `r221`, `r222`, `r223`, `r224`, `r225`, `r226`, `r227`, `r228`, `r229`, `r230`, `r231` |
| hazards | 193/232 | `r030`, `r058`, `r063`, `r065`, `r070`, `r083`, `r098`, `r100`, `r105`, `r157`, `r165`, `r166`, `r167`, `r168`, `r169`, `r170`, `r172`, `r173`, `r177`, `r198`, `r199`, `r200`, `r201`, `r208`, `r209`, `r216`, `r217`, `r219`, `r221`, `r222`, `r223`, `r224`, `r225`, `r226`, `r227`, `r228`, `r229`, `r230`, `r231` |
| standing | 180/232 | `r016`, `r021`, `r023`, `r025`, `r030`, `r038`, `r039`, `r040`, `r048`, `r058`, `r063`, `r065`, `r070`, `r083`, `r098`, `r100`, `r102`, `r105`, `r111`, `r112`, `r157`, `r165`, `r166`, `r167`, `r168`, `r169`, `r170`, `r172`, `r173`, `r177`, `r187`, `r196`, `r198`, `r199`, `r200`, `r201`, `r208`, `r209`, `r216`, `r217`, `r219`, `r221`, `r222`, `r223`, `r224`, `r225`, `r226`, `r227`, `r228`, `r229`, `r230`, `r231` |

## Rooms flagged by hazard or standing models

| Room | World tile origin | Markers | Flags |
|---|---|---|---|
| `r016` | [256, 462] | Bench; Bench; Stag station: Stag Station - Greenpath | standing |
| `r021` | [74, 514] | Bench | standing |
| `r023` | [611, 529] | Bench | standing |
| `r025` | [207, 543] | — | standing |
| `r030` | [12, 554] | — | acid, hazards, standing |
| `r038` | [611, 633] | — | standing |
| `r039` | [787, 633] | — | standing |
| `r040` | [75, 639] | Bench | standing |
| `r048` | [207, 661] | — | standing |
| `r058` | [1015, 702] | — | acid, hazards, standing |
| `r063` | [1034, 729] | — | acid, hazards, standing |
| `r065` | [985, 731] | — | acid, hazards, standing |
| `r070` | [979, 781] | Bench | acid, hazards, standing |
| `r083` | [981, 838] | — | acid, hazards, standing |
| `r098` | [1087, 887] | — | acid, hazards, standing |
| `r100` | [2015, 893] | Bench; Hot spring; Vendor: Little Fool | hazards, standing |
| `r102` | [298, 899] | — | standing |
| `r105` | [2153, 909] | — | hazards, standing |
| `r111` | [207, 930] | — | standing |
| `r112` | [296, 930] | Stag station: Stag Station - Queen's Gardens | standing |
| `r157` | [1024, 1122] | Bench | acid, hazards, standing |
| `r165` | [220, 1156] | — | hazards, standing |
| `r166` | [1302, 1158] | Bench; Vendor: Tuk | acid, hazards, standing |
| `r167` | [1699, 1174] | — | acid, hazards, standing |
| `r168` | [1163, 1178] | — | acid, hazards, standing |
| `r169` | [1805, 1180] | — | acid, hazards, standing |
| `r170` | [1746, 1181] | — | acid, hazards, standing |
| `r172` | [1988, 1188] | — | acid, hazards, standing |
| `r173` | [1089, 1190] | Bench | acid, hazards, standing |
| `r177` | [1804, 1217] | — | acid, hazards, standing |
| `r187` | [68, 1239] | Stag station: Stag Station - Distant Village | standing |
| `r196` | [2195, 1269] | — | standing |
| `r198` | [1852, 1270] | — | acid, hazards, standing |
| `r199` | [1913, 1274] | — | acid, hazards, standing |
| `r200` | [1746, 1275] | — | acid, hazards, standing |
| `r201` | [1699, 1277] | — | acid, hazards, standing |
| `r208` | [1454, 1320] | Tram: Tram Station - Ancient Basin | acid, hazards, standing |
| `r209` | [1604, 1324] | — | acid, hazards, standing |
| `r216` | [1335, 1364] | — | acid, hazards, standing |
| `r217` | [1610, 1384] | — | acid, hazards, standing |
| `r219` | [1208, 1405] | — | acid, hazards, standing |
| `r221` | [1127, 1420] | Bench | acid, hazards, standing |
| `r222` | [1486, 1420] | — | acid, hazards, standing |
| `r223` | [1748, 1442] | Bench; Stag station: Stag Station - Hidden Station | acid, hazards, standing |
| `r224` | [1044, 1456] | — | acid, hazards, standing |
| `r225` | [1121, 1513] | — | acid, hazards, standing |
| `r226` | [1434, 1513] | — | acid, hazards, standing |
| `r227` | [1347, 1641] | — | acid, hazards, standing |
| `r228` | [1596, 1681] | — | acid, hazards, standing |
| `r229` | [1351, 1717] | — | acid, hazards, standing |
| `r230` | [1939, 1755] | — | acid, hazards, standing |
| `r231` | [1309, 1775] | — | acid, hazards, standing |

## Runtime transition and edge-opening checks

The follow-up [room safety report](hk-room-safety.md) adds actual Godot transition probes, 60 Hz reproductions, one-frame boundary escapes, and every bad left/right opening. These checks expose collision failures that static connectivity alone cannot detect.
