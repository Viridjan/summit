# Hallownest room-transition and boundary safety

World: `res://worlds/hollow_knight/world.json` — 232 rooms. Game data and gameplay code were not changed.

## Results

- **194 directed room-edge connections** produced collision-overlapping arrivals (28,074 failing probes).
- **1 door connection** produced collision-overlapping arrivals (138 failing probes).
- **3 upward boundary locations** allowed the player past the normal 24px ceiling allowance with the centre outside every room.
- **215 bad left/right opening spans in 102 rooms:** 55 face no neighbouring room; 160 face a neighbour's solid terrain.

The five representative 60 Hz replays below reproduce failures using actual player updates, dash input, collision callbacks, entity touches, room changes, and dash freeze timing. They start from seeded collision-free local positions, not from a demonstrated route from the world spawn. All five remained embedded through tick 89 while the scripted direction was held. This confirms local failures without claiming every seed is reachable in normal progression or that no recovery input could ever work.

## Reproduced examples

| Source and action | Start feet position, local px | Result |
|---|---|---|
| `r005` — King's Pass right edge | [1204, 852] | Embedded in `r012` at [0.0, 340.0] on tick 5 |
| `r023` — Door d8 to r039:d9 | [1557, 811] | Embedded in `r039` at [156.0, 24.0] on tick 0 |
| `r028` — r028 ceiling | [140, 11] | Embedded in `r017` at [2524.0, 563.0] on tick 12; outside room union beyond ceiling allowance on tick 11 |
| `r124` — r124 ceiling | [28, 11] | Embedded in `r090` at [948.0, 891.0] on tick 12; outside room union beyond ceiling allowance on tick 11 |
| `r125` — r125 ceiling | [164, 11] | Embedded in `r113` at [220.0, 227.0] on tick 12; outside room union beyond ceiling allowance on tick 11 |

Tick numbers are zero-based, at 60 Hz. Start coordinates refer to the player’s feet, not the top-left of the sprite.

## Why these fail

- Edge movement collides only against the current room. The room changes after the player centre crosses the boundary; terrain in the destination can already overlap the body. `Adventure.room_at` can also return a solid-room fallback. Entry does not reject or resolve the collision.
- Door arrivals clamp the player to the target doorway rectangle but do not validate that the hitbox is free of terrain. The reproduced `r023:d8 → r039:d9` case places the player at `(156,24)` inside terrain.
- Ceiling bounds consult a point at the top of the hitbox, while room changes use the centre. Across a gap between room rectangles, that point can already be in another room while the centre is still in unassigned space. In the three replayed cases this lasts one frame and is followed by embedding in the upper room.
- An opening facing no room is often stopped by the horizontal bounds clamp. It is a visual/map-connectivity defect, not automatically an out-of-bounds exploit. Wall-facing openings are more dangerous because `can_exit` accepts the neighbour rectangle even where its terrain is solid.

## Coverage and limits

- Tested 232,245 valid seeded edge starts; 232,185 crossings. All integer seam alignments, both directions, standing/crouched, with [1, 4, 8] pixel movement batches.
- Tested 44,517 valid integer doorway-contact offsets and 85,932 valid outer-edge starts.
- Probe runner uses the real movement, bounds, door and room-entry methods. Rendering and save writes are disabled; static room collision structures are cached. General edge probes isolate cardinal movement and omit ordinary hazard touches; full-update replays do include touches.
- Outer-boundary sweep uses 1px cardinal movement. The normal 24px top allowance and the brief bottom death margin are excluded from failures. Invincibility is off.
- This is not exhaustive over every velocity, subpixel remainder, diagonal input, movement state, moving obstacle, or recovery sequence. No claim is made that all remaining locations are safe.
- Side openings are maximal contiguous vertical terrain spans with the same issue and target. A two-tile opening counts as one span. Other valid-looking openings can still be too small for the complete player hitbox.

## Re-run

```sh
godot --headless --path . res://tools/room_safety.tscn
godot --headless --path . res://tools/room_safety.tscn -- --phase replay --output res://reports/hk-room-safety-replays.json
python3 tools/check_side_openings.py
python3 tools/summarize_room_safety.py
```

Runtime checker exits 1 when it reproduces a failure, 0 when the selected checks find none, and 2 for invalid configuration/output. Use a disposable `XDG_DATA_HOME` for sandbox runs, e.g. `env XDG_DATA_HOME=/tmp/summit-room-safety godot ...`. It never writes the gameplay adventure save. The replay phase contains HK-specific seeds. Other worlds can use `--world res://adventure/world.json --output /tmp/adventure-safety.json` for edge/door/bounds sweeps.

## All failing room connections

| Type | Source → target | Failing probes | Sample start → arrival (local px) |
|---|---|---:|---|
| embedded_arrival | `r001 → r005` | 96 | [2509.0, 648.0] → [413.0, 6.0] |
| embedded_arrival | `r003 → r002` | 336 | [1396.0, 83.0] → [0.0, 187.0] |
| embedded_arrival | `r004 → r001` | 300 | [428.0, 11.0] → [4.0, 653.0] |
| embedded_arrival | `r005 → r012` | 192 | [1204.0, 851.0] → [0.0, 339.0] |
| embedded_arrival | `r006 → r003` | 234 | [621.0, 11.0] → [157.0, 325.0] |
| embedded_arrival | `r006 → r010` | 249 | [1860.0, 699.0] → [0.0, 235.0] |
| embedded_arrival | `r006 → r014` | 189 | [4.0, 795.0] → [479.0, 27.0] |
| embedded_arrival | `r006 → r022` | 147 | [4.0, 2011.0] → [407.0, 635.0] |
| embedded_arrival | `r012 → r005` | 483 | [4.0, 19.0] → [1207.0, 531.0] |
| embedded_arrival | `r014 → r006` | 192 | [476.0, 169.0] → [0.0, 937.0] |
| embedded_arrival | `r014 → r015` | 48 | [4.0, 27.0] → [431.0, 19.0] |
| embedded_arrival | `r015 → r014` | 141 | [428.0, 57.0] → [0.0, 65.0] |
| embedded_arrival | `r016 → r023` | 99 | [2836.0, 857.0] → [0.0, 321.0] |
| embedded_arrival | `r016 → r025` | 48 | [4.0, 723.0] → [391.0, 75.0] |
| embedded_arrival | `r017 → r020` | 48 | [2684.0, 283.0] → [0.0, 43.0] |
| embedded_arrival | `r018 → r017` | 48 | [460.0, 115.0] → [0.0, 307.0] |
| embedded_arrival | `r019 → r020` | 192 | [4.0, 59.0] → [383.0, 19.0] |
| embedded_arrival | `r020 → r017` | 147 | [4.0, 291.0] → [2687.0, 531.0] |
| embedded_arrival | `r023 → r038` | 138 | [1125.0, 832.0] → [1125.0, 6.0] |
| door d8 | `r023 → r039` | 138 | [1557.0, 811.0] → [156.0, 24.0] |
| embedded_arrival | `r025 → r016` | 48 | [388.0, 113.0] → [0.0, 761.0] |
| embedded_arrival | `r027 → r029` | 48 | [4.0, 217.0] → [999.0, 185.0] |
| embedded_arrival | `r027 → r033` | 51 | [2068.0, 315.0] → [0.0, 43.0] |
| embedded_arrival | `r027 → r037` | 48 | [4.0, 747.0] → [679.0, 171.0] |
| embedded_arrival | `r027 → r041` | 528 | [133.0, 776.0] → [133.0, 6.0] |
| embedded_arrival | `r028 → r036` | 90 | [237.0, 496.0] → [549.0, 6.0] |
| embedded_arrival | `r029 → r027` | 48 | [996.0, 139.0] → [0.0, 171.0] |
| embedded_arrival | `r031 → r044` | 96 | [261.0, 752.0] → [341.0, 6.0] |
| embedded_arrival | `r032 → r027` | 192 | [4.0, 43.0] → [2071.0, 107.0] |
| embedded_arrival | `r033 → r027` | 141 | [4.0, 137.0] → [2071.0, 409.0] |
| embedded_arrival | `r036 → r027` | 330 | [4.0, 91.0] → [2071.0, 611.0] |
| embedded_arrival | `r036 → r028` | 150 | [380.0, 11.0] → [68.0, 501.0] |
| embedded_arrival | `r036 → r035` | 99 | [612.0, 137.0] → [0.0, 161.0] |
| embedded_arrival | `r036 → r054` | 123 | [612.0, 606.0] → [0.0, 6.0] |
| embedded_arrival | `r039 → r023` | 204 | [260.0, 11.0] → [1668.0, 837.0] |
| embedded_arrival | `r040 → r048` | 48 | [1052.0, 203.0] → [0.0, 27.0] |
| embedded_arrival | `r041 → r027` | 522 | [108.0, 11.0] → [108.0, 781.0] |
| embedded_arrival | `r041 → r042` | 285 | [1012.0, 99.0] → [0.0, 91.0] |
| embedded_arrival | `r041 → r045` | 144 | [4.0, 201.0] → [991.0, 161.0] |
| embedded_arrival | `r042 → r041` | 48 | [4.0, 219.0] → [1015.0, 227.0] |
| embedded_arrival | `r043 → r050` | 48 | [4.0, 337.0] → [567.0, 201.0] |
| embedded_arrival | `r043 → r056` | 48 | [4.0, 427.0] → [639.0, 35.0] |
| embedded_arrival | `r046 → r036` | 141 | [612.0, 27.0] → [0.0, 379.0] |
| embedded_arrival | `r048 → r016` | 48 | [388.0, 75.0] → [0.0, 1667.0] |
| embedded_arrival | `r049 → r035` | 24 | [4.0, 46.0] → [951.0, 446.0] |
| embedded_arrival | `r049 → r052` | 27 | [4.0, 54.0] → [399.0, 6.0] |
| embedded_arrival | `r051 → r054` | 198 | [4.0, 176.0] → [4.0, 6.0] |
| embedded_arrival | `r054 → r036` | 48 | [4.0, 161.0] → [615.0, 761.0] |
| embedded_arrival | `r057 → r061` | 48 | [4.0, 313.0] → [2455.0, 265.0] |
| embedded_arrival | `r058 → r063` | 24 | [292.0, 216.0] → [140.0, 6.0] |
| embedded_arrival | `r059 → r064` | 96 | [36.0, 208.0] → [36.0, 6.0] |
| embedded_arrival | `r061 → r057` | 96 | [2452.0, 227.0] → [0.0, 275.0] |
| embedded_arrival | `r062 → r045` | 270 | [236.0, 11.0] → [300.0, 629.0] |
| embedded_arrival | `r068 → r060` | 48 | [244.0, 11.0] → [100.0, 613.0] |
| embedded_arrival | `r069 → r062` | 174 | [1124.0, 11.0] → [348.0, 421.0] |
| embedded_arrival | `r070 → r065` | 474 | [108.0, 11.0] → [60.0, 405.0] |
| embedded_arrival | `r070 → r083` | 198 | [157.0, 456.0] → [141.0, 6.0] |
| embedded_arrival | `r071 → r086` | 96 | [4.0, 649.0] → [143.0, 129.0] |
| embedded_arrival | `r071 → r109` | 51 | [4.0, 1299.0] → [447.0, 171.0] |
| embedded_arrival | `r072 → r069` | 189 | [1020.0, 307.0] → [0.0, 315.0] |
| embedded_arrival | `r072 → r095` | 96 | [4.0, 977.0] → [759.0, 153.0] |
| embedded_arrival | `r072 → r114` | 48 | [1020.0, 1355.0] → [0.0, 51.0] |
| embedded_arrival | `r074 → r073` | 48 | [524.0, 161.0] → [0.0, 193.0] |
| embedded_arrival | `r076 → r072` | 144 | [756.0, 315.0] → [0.0, 515.0] |
| embedded_arrival | `r076 → r078` | 93 | [4.0, 297.0] → [927.0, 145.0] |
| embedded_arrival | `r077 → r090` | 96 | [524.0, 577.0] → [0.0, 241.0] |
| embedded_arrival | `r078 → r089` | 228 | [36.0, 192.0] → [236.0, 6.0] |
| embedded_arrival | `r083 → r070` | 336 | [52.0, 11.0] → [68.0, 461.0] |
| embedded_arrival | `r083 → r097` | 2313 | [396.0, 392.0] → [652.0, 6.0] |
| embedded_arrival | `r083 → r098` | 162 | [848.0, 392.0] → [0.0, 6.0] |
| embedded_arrival | `r085 → r091` | 75 | [180.0, 150.0] → [0.0, 6.0] |
| embedded_arrival | `r086 → r071` | 48 | [140.0, 83.0] → [0.0, 603.0] |
| embedded_arrival | `r086 → r085` | 9 | [4.0, 6.0] → [183.0, 6.0] |
| embedded_arrival | `r086 → r091` | 6 | [4.0, 144.0] → [4.0, 6.0] |
| embedded_arrival | `r087 → r088` | 288 | [428.0, 43.0] → [0.0, 43.0] |
| embedded_arrival | `r088 → r087` | 48 | [4.0, 169.0] → [431.0, 169.0] |
| embedded_arrival | `r088 → r116` | 540 | [356.0, 792.0] → [788.0, 6.0] |
| embedded_arrival | `r089 → r078` | 240 | [516.0, 11.0] → [316.0, 197.0] |
| embedded_arrival | `r090 → r077` | 96 | [4.0, 219.0] → [527.0, 555.0] |
| embedded_arrival | `r092 → r093` | 48 | [684.0, 179.0] → [0.0, 115.0] |
| embedded_arrival | `r097 → r117` | 336 | [20.0, 496.0] → [12.0, 6.0] |
| embedded_arrival | `r098 → r083` | 48 | [221.0, 11.0] → [1069.0, 397.0] |
| embedded_arrival | `r103 → r082` | 552 | [156.0, 11.0] → [156.0, 533.0] |
| embedded_arrival | `r103 → r113` | 96 | [396.0, 320.0] → [708.0, 6.0] |
| embedded_arrival | `r104 → r088` | 48 | [4.0, 267.0] → [567.0, 739.0] |
| embedded_arrival | `r104 → r089` | 108 | [508.0, 11.0] → [508.0, 477.0] |
| embedded_arrival | `r104 → r116` | 96 | [4.0, 563.0] → [999.0, 243.0] |
| embedded_arrival | `r109 → r071` | 51 | [444.0, 371.0] → [0.0, 1499.0] |
| embedded_arrival | `r110 → r105` | 198 | [28.0, 11.0] → [212.0, 133.0] |
| embedded_arrival | `r111 → r092` | 144 | [4.0, 67.0] → [687.0, 579.0] |
| embedded_arrival | `r112 → r111` | 384 | [4.0, 27.0] → [711.0, 27.0] |
| embedded_arrival | `r114 → r072` | 93 | [4.0, 73.0] → [1023.0, 1377.0] |
| embedded_arrival | `r116 → r088` | 96 | [452.0, 11.0] → [20.0, 797.0] |
| embedded_arrival | `r116 → r104` | 96 | [996.0, 139.0] → [0.0, 459.0] |
| embedded_arrival | `r117 → r097` | 276 | [85.0, 11.0] → [93.0, 501.0] |
| embedded_arrival | `r117 → r119` | 93 | [1660.0, 177.0] → [0.0, 25.0] |
| embedded_arrival | `r117 → r129` | 54 | [156.0, 424.0] → [164.0, 6.0] |
| embedded_arrival | `r118 → r094` | 138 | [20.0, 11.0] → [44.0, 637.0] |
| embedded_arrival | `r119 → r117` | 48 | [4.0, 89.0] → [1663.0, 241.0] |
| embedded_arrival | `r120 → r090` | 48 | [125.0, 11.0] → [621.0, 893.0] |
| embedded_arrival | `r120 → r123` | 96 | [4.0, 83.0] → [575.0, 59.0] |
| embedded_arrival | `r127 → r132` | 180 | [157.0, 264.0] → [157.0, 6.0] |
| embedded_arrival | `r128 → r116` | 48 | [524.0, 145.0] → [0.0, 569.0] |
| embedded_arrival | `r128 → r151` | 156 | [301.0, 728.0] → [37.0, 6.0] |
| embedded_arrival | `r129 → r117` | 48 | [141.0, 11.0] → [133.0, 429.0] |
| embedded_arrival | `r130 → r129` | 48 | [548.0, 83.0] → [0.0, 115.0] |
| embedded_arrival | `r132 → r071` | 48 | [364.0, 11.0] → [28.0, 1845.0] |
| embedded_arrival | `r132 → r127` | 246 | [205.0, 11.0] → [205.0, 269.0] |
| embedded_arrival | `r132 → r148` | 102 | [628.0, 592.0] → [420.0, 6.0] |
| embedded_arrival | `r136 → r139` | 48 | [700.0, 177.0] → [0.0, 153.0] |
| embedded_arrival | `r137 → r104` | 96 | [125.0, 11.0] → [1109.0, 933.0] |
| embedded_arrival | `r139 → r129` | 51 | [1308.0, 243.0] → [0.0, 443.0] |
| embedded_arrival | `r139 → r136` | 48 | [4.0, 251.0] → [703.0, 275.0] |
| embedded_arrival | `r140 → r141` | 96 | [692.0, 195.0] → [0.0, 147.0] |
| embedded_arrival | `r140 → r152` | 48 | [669.0, 504.0] → [741.0, 6.0] |
| embedded_arrival | `r141 → r136` | 51 | [316.0, 83.0] → [0.0, 179.0] |
| embedded_arrival | `r142 → r118` | 54 | [1268.0, 11.0] → [444.0, 621.0] |
| embedded_arrival | `r142 → r160` | 48 | [1684.0, 867.0] → [0.0, 155.0] |
| embedded_arrival | `r142 → r163` | 48 | [4.0, 977.0] → [439.0, 145.0] |
| embedded_arrival | `r143 → r133` | 51 | [612.0, 595.0] → [0.0, 875.0] |
| embedded_arrival | `r143 → r148` | 75 | [4.0, 318.0] → [439.0, 6.0] |
| embedded_arrival | `r145 → r144` | 246 | [36.0, 11.0] → [124.0, 277.0] |
| embedded_arrival | `r146 → r115` | 96 | [220.0, 11.0] → [1020.0, 1085.0] |
| embedded_arrival | `r146 → r149` | 96 | [4.0, 531.0] → [527.0, 491.0] |
| embedded_arrival | `r146 → r154` | 48 | [2420.0, 297.0] → [0.0, 105.0] |
| embedded_arrival | `r147 → r148` | 144 | [396.0, 11.0] → [0.0, 11.0] |
| embedded_arrival | `r147 → r159` | 48 | [269.0, 296.0] → [85.0, 6.0] |
| embedded_arrival | `r148 → r132` | 144 | [44.0, 11.0] → [252.0, 597.0] |
| embedded_arrival | `r148 → r143` | 48 | [436.0, 369.0] → [0.0, 681.0] |
| embedded_arrival | `r148 → r147` | 192 | [4.0, 131.0] → [399.0, 131.0] |
| embedded_arrival | `r149 → r146` | 387 | [524.0, 211.0] → [0.0, 251.0] |
| embedded_arrival | `r149 → r181` | 285 | [524.0, 1267.0] → [0.0, 107.0] |
| embedded_arrival | `r151 → r161` | 48 | [36.0, 384.0] → [68.0, 6.0] |
| embedded_arrival | `r152 → r178` | 48 | [44.0, 1072.0] → [84.0, 6.0] |
| embedded_arrival | `r153 → r156` | 459 | [676.0, 118.0] → [0.0, 6.0] |
| embedded_arrival | `r156 → r157` | 48 | [540.0, 707.0] → [0.0, 635.0] |
| embedded_arrival | `r157 → r156` | 192 | [4.0, 523.0] → [543.0, 595.0] |
| embedded_arrival | `r158 → r162` | 72 | [52.0, 152.0] → [140.0, 6.0] |
| embedded_arrival | `r160 → r142` | 195 | [4.0, 211.0] → [1687.0, 923.0] |
| embedded_arrival | `r161 → r151` | 48 | [85.0, 11.0] → [53.0, 389.0] |
| embedded_arrival | `r161 → r203` | 48 | [412.0, 1537.0] → [0.0, 369.0] |
| embedded_arrival | `r161 → r204` | 48 | [4.0, 1403.0] → [415.0, 219.0] |
| embedded_arrival | `r162 → r158` | 84 | [88.0, 11.0] → [0.0, 157.0] |
| embedded_arrival | `r163 → r142` | 48 | [436.0, 107.0] → [0.0, 939.0] |
| embedded_arrival | `r164 → r175` | 144 | [1692.0, 416.0] → [1372.0, 6.0] |
| embedded_arrival | `r166 → r168` | 99 | [4.0, 307.0] → [1111.0, 147.0] |
| embedded_arrival | `r168 → r166` | 93 | [1108.0, 201.0] → [0.0, 361.0] |
| embedded_arrival | `r170 → r177` | 42 | [460.0, 435.0] → [0.0, 147.0] |
| embedded_arrival | `r171 → r172` | 192 | [1060.0, 59.0] → [0.0, 11.0] |
| embedded_arrival | `r174 → r155` | 48 | [4.0, 75.0] → [423.0, 763.0] |
| embedded_arrival | `r175 → r164` | 48 | [1397.0, 11.0] → [1717.0, 421.0] |
| embedded_arrival | `r175 → r194` | 48 | [1293.0, 520.0] → [189.0, 6.0] |
| embedded_arrival | `r176 → r189` | 54 | [308.0, 328.0] → [332.0, 6.0] |
| embedded_arrival | `r176 → r190` | 102 | [548.0, 328.0] → [84.0, 6.0] |
| embedded_arrival | `r177 → r170` | 189 | [4.0, 59.0] → [463.0, 347.0] |
| embedded_arrival | `r178 → r152` | 102 | [556.0, 11.0] → [516.0, 1077.0] |
| embedded_arrival | `r178 → r214` | 435 | [4.0, 1171.0] → [719.0, 91.0] |
| embedded_arrival | `r179 → r178` | 345 | [4.0, 267.0] → [655.0, 267.0] |
| embedded_arrival | `r180 → r152` | 48 | [85.0, 11.0] → [1445.0, 1077.0] |
| embedded_arrival | `r181 → r146` | 48 | [1100.0, 11.0] → [1100.0, 1205.0] |
| embedded_arrival | `r182 → r180` | 99 | [4.0, 67.0] → [1255.0, 107.0] |
| embedded_arrival | `r183 → r188` | 72 | [460.0, 291.0] → [0.0, 203.0] |
| embedded_arrival | `r183 → r195` | 465 | [460.0, 302.0] → [0.0, 6.0] |
| embedded_arrival | `r184 → r185` | 51 | [4.0, 139.0] → [839.0, 115.0] |
| embedded_arrival | `r185 → r184` | 48 | [836.0, 131.0] → [0.0, 155.0] |
| embedded_arrival | `r185 → r206` | 96 | [836.0, 651.0] → [0.0, 131.0] |
| embedded_arrival | `r186 → r187` | 48 | [340.0, 59.0] → [0.0, 59.0] |
| embedded_arrival | `r188 → r149` | 96 | [444.0, 105.0] → [0.0, 1369.0] |
| embedded_arrival | `r188 → r183` | 48 | [4.0, 137.0] → [463.0, 225.0] |
| embedded_arrival | `r188 → r195` | 240 | [28.0, 208.0] → [28.0, 6.0] |
| embedded_arrival | `r189 → r176` | 48 | [141.0, 11.0] → [117.0, 333.0] |
| embedded_arrival | `r191 → r176` | 96 | [76.0, 11.0] → [812.0, 333.0] |
| embedded_arrival | `r194 → r175` | 48 | [124.0, 11.0] → [1228.0, 525.0] |
| embedded_arrival | `r195 → r183` | 387 | [4.0, 43.0] → [463.0, 339.0] |
| embedded_arrival | `r195 → r196` | 93 | [972.0, 41.0] → [0.0, 41.0] |
| embedded_arrival | `r197 → r205` | 48 | [221.0, 160.0] → [117.0, 6.0] |
| embedded_arrival | `r198 → r192` | 48 | [4.0, 217.0] → [383.0, 393.0] |
| embedded_arrival | `r202 → r204` | 48 | [1108.0, 193.0] → [0.0, 105.0] |
| embedded_arrival | `r203 → r161` | 195 | [4.0, 105.0] → [415.0, 1273.0] |
| embedded_arrival | `r205 → r197` | 48 | [28.0, 11.0] → [132.0, 165.0] |
| embedded_arrival | `r206 → r185` | 51 | [4.0, 107.0] → [839.0, 627.0] |
| embedded_arrival | `r207 → r220` | 306 | [1004.0, 864.0] → [484.0, 6.0] |
| embedded_arrival | `r208 → r209` | 240 | [1196.0, 99.0] → [0.0, 67.0] |
| embedded_arrival | `r208 → r216` | 48 | [4.0, 579.0] → [951.0, 227.0] |
| embedded_arrival | `r208 → r222` | 69 | [556.0, 800.0] → [300.0, 6.0] |
| embedded_arrival | `r210 → r178` | 579 | [1156.0, 27.0] → [0.0, 851.0] |
| embedded_arrival | `r210 → r203` | 96 | [4.0, 115.0] → [799.0, 459.0] |
| embedded_arrival | `r215 → r207` | 48 | [708.0, 137.0] → [0.0, 545.0] |
| embedded_arrival | `r217 → r222` | 246 | [12.0, 288.0] → [1004.0, 6.0] |
| embedded_arrival | `r219 → r221` | 48 | [189.0, 120.0] → [837.0, 6.0] |
| embedded_arrival | `r220 → r207` | 102 | [212.0, 11.0] → [732.0, 869.0] |
| embedded_arrival | `r221 → r219` | 96 | [716.0, 11.0] → [68.0, 125.0] |
| embedded_arrival | `r221 → r222` | 51 | [2868.0, 387.0] → [0.0, 387.0] |
| embedded_arrival | `r222 → r208` | 48 | [156.0, 11.0] → [412.0, 805.0] |
| embedded_arrival | `r222 → r217` | 48 | [1909.0, 11.0] → [917.0, 293.0] |
| uncontained_bounds | `r028 → r028` | 198 | [140.0, 11.0] → [140.0, -14.0] |
| uncontained_bounds | `r124 → r124` | 134 | [28.0, 11.0] → [28.0, -14.0] |
| uncontained_bounds | `r125 → r125` | 10 | [164.0, 11.0] → [164.0, -14.0] |

## All bad left/right openings

| Room | Side | Local vertical span (px, end exclusive) | Faces |
|---|---|---|---|
| `r003` | right | 72–80 | Solid wall in `r002` |
| `r003` | right | 144–192 | Solid wall in `r002` |
| `r003` | right | 240–280 | No adjacent room |
| `r005` | right | 840–856 | Solid wall in `r012` |
| `r005` | right | 872–904 | Solid wall in `r012` |
| `r005` | right | 904–944 | No adjacent room |
| `r006` | left | 784–792 | Solid wall in `r014` |
| `r006` | left | 808–816 | Solid wall in `r014` |
| `r006` | left | 832–840 | Solid wall in `r014` |
| `r006` | left | 2000–2032 | Solid wall in `r022` |
| `r006` | right | 688–712 | Solid wall in `r010` |
| `r006` | right | 720–736 | Solid wall in `r010` |
| `r006` | right | 744–760 | Solid wall in `r010` |
| `r006` | right | 776–784 | Solid wall in `r010` |
| `r014` | left | 16–24 | Solid wall in `r015` |
| `r014` | right | 168–200 | Solid wall in `r006` |
| `r015` | right | 56–72 | Solid wall in `r014` |
| `r016` | left | 552–632 | No adjacent room |
| `r016` | left | 712–720 | Solid wall in `r025` |
| `r016` | right | 856–864 | Solid wall in `r023` |
| `r016` | right | 880–896 | Solid wall in `r023` |
| `r017` | right | 272–280 | Solid wall in `r020` |
| `r018` | right | 104–112 | Solid wall in `r017` |
| `r019` | left | 48–64 | Solid wall in `r020` |
| `r019` | left | 144–160 | Solid wall in `r020` |
| `r020` | left | 280–312 | Solid wall in `r017` |
| `r020` | left | 400–416 | No adjacent room |
| `r020` | right | 376–400 | No adjacent room |
| `r025` | right | 112–120 | Solid wall in `r016` |
| `r027` | left | 216–224 | Solid wall in `r029` |
| `r027` | left | 496–528 | No adjacent room |
| `r027` | left | 736–744 | Solid wall in `r037` |
| `r027` | right | 304–320 | Solid wall in `r033` |
| `r028` | right | 24–48 | No adjacent room |
| `r028` | right | 56–72 | No adjacent room |
| `r028` | right | 96–112 | No adjacent room |
| `r028` | right | 128–144 | No adjacent room |
| `r028` | right | 168–184 | No adjacent room |
| `r028` | right | 376–416 | No adjacent room |
| `r029` | left | 48–112 | No adjacent room |
| `r029` | right | 128–136 | Solid wall in `r027` |
| `r032` | left | 32–40 | Solid wall in `r027` |
| `r032` | left | 112–136 | Solid wall in `r027` |
| `r033` | left | 136–152 | Solid wall in `r027` |
| `r034` | left | 88–144 | No adjacent room |
| `r036` | left | 80–96 | Solid wall in `r027` |
| `r036` | left | 152–160 | Solid wall in `r027` |
| `r036` | left | 224–256 | Solid wall in `r027` |
| `r036` | left | 256–264 | No adjacent room |
| `r036` | right | 136–144 | Solid wall in `r035` |
| `r036` | right | 168–184 | Solid wall in `r035` |
| `r036` | right | 600–624 | Solid wall in `r054` |
| `r040` | right | 192–200 | Solid wall in `r048` |
| `r041` | left | 200–224 | Solid wall in `r045` |
| `r041` | right | 88–112 | Solid wall in `r042` |
| `r041` | right | 184–192 | Solid wall in `r042` |
| `r041` | right | 208–216 | Solid wall in `r042` |
| `r042` | left | 208–216 | Solid wall in `r041` |
| `r043` | left | 336–344 | Solid wall in `r050` |
| `r043` | left | 416–424 | Solid wall in `r056` |
| `r046` | right | 16–24 | Solid wall in `r036` |
| `r046` | right | 120–128 | Solid wall in `r036` |
| `r048` | right | 64–72 | Solid wall in `r016` |
| `r049` | left | 40–48 | Solid wall in `r035` |
| `r049` | left | 48–56 | Solid wall in `r052` |
| `r054` | left | 160–168 | Solid wall in `r036` |
| `r057` | left | 312–320 | Solid wall in `r061` |
| `r061` | right | 216–232 | Solid wall in `r057` |
| `r071` | left | 504–520 | No adjacent room |
| `r071` | left | 648–664 | Solid wall in `r086` |
| `r071` | left | 840–904 | No adjacent room |
| `r071` | left | 1288–1304 | Solid wall in `r109` |
| `r072` | left | 976–992 | Solid wall in `r095` |
| `r072` | right | 296–304 | Solid wall in `r069` |
| `r072` | right | 416–448 | Solid wall in `r069` |
| `r072` | right | 448–456 | No adjacent room |
| `r072` | right | 1344–1352 | Solid wall in `r114` |
| `r074` | right | 160–168 | Solid wall in `r073` |
| `r075` | right | 400–432 | No adjacent room |
| `r076` | left | 296–304 | Solid wall in `r078` |
| `r076` | right | 304–312 | Solid wall in `r072` |
| `r076` | right | 352–368 | Solid wall in `r072` |
| `r077` | right | 576–592 | Solid wall in `r090` |
| `r084` | left | 88–216 | No adjacent room |
| `r084` | left | 224–352 | No adjacent room |
| `r085` | right | 144–160 | Solid wall in `r091` |
| `r086` | left | 0–8 | Solid wall in `r085` |
| `r086` | right | 72–80 | Solid wall in `r071` |
| `r087` | right | 32–48 | Solid wall in `r088` |
| `r087` | right | 96–112 | Solid wall in `r088` |
| `r087` | right | 264–280 | Solid wall in `r088` |
| `r088` | left | 168–176 | Solid wall in `r087` |
| `r088` | left | 696–712 | No adjacent room |
| `r090` | left | 208–224 | Solid wall in `r077` |
| `r092` | right | 168–176 | Solid wall in `r093` |
| `r097` | left | 208–232 | No adjacent room |
| `r099` | left | 8–48 | No adjacent room |
| `r100` | left | 128–144 | No adjacent room |
| `r100` | left | 152–240 | No adjacent room |
| `r100` | left | 256–280 | No adjacent room |
| `r104` | left | 256–264 | Solid wall in `r088` |
| `r104` | left | 552–568 | Solid wall in `r116` |
| `r109` | right | 360–376 | Solid wall in `r071` |
| `r111` | left | 56–72 | Solid wall in `r092` |
| `r111` | left | 96–104 | Solid wall in `r092` |
| `r112` | left | 16–32 | Solid wall in `r111` |
| `r112` | left | 48–96 | Solid wall in `r111` |
| `r114` | left | 72–80 | Solid wall in `r072` |
| `r116` | right | 128–136 | Solid wall in `r104` |
| `r116` | right | 592–600 | Solid wall in `r104` |
| `r117` | right | 176–184 | Solid wall in `r119` |
| `r119` | left | 88–96 | Solid wall in `r117` |
| `r120` | left | 72–88 | Solid wall in `r123` |
| `r120` | right | 96–136 | No adjacent room |
| `r120` | right | 168–200 | No adjacent room |
| `r124` | left | 32–48 | No adjacent room |
| `r124` | left | 64–112 | No adjacent room |
| `r124` | left | 144–176 | No adjacent room |
| `r125` | left | 256–360 | No adjacent room |
| `r125` | right | 216–264 | No adjacent room |
| `r128` | right | 144–152 | Solid wall in `r116` |
| `r128` | right | 296–312 | No adjacent room |
| `r128` | right | 336–352 | No adjacent room |
| `r130` | right | 72–80 | Solid wall in `r129` |
| `r133` | left | 256–280 | No adjacent room |
| `r136` | right | 176–184 | Solid wall in `r139` |
| `r139` | left | 240–248 | Solid wall in `r136` |
| `r139` | right | 232–248 | Solid wall in `r129` |
| `r140` | right | 184–192 | Solid wall in `r141` |
| `r140` | right | 232–240 | Solid wall in `r141` |
| `r141` | right | 72–88 | Solid wall in `r136` |
| `r142` | left | 784–800 | No adjacent room |
| `r142` | left | 976–984 | Solid wall in `r163` |
| `r142` | right | 400–424 | No adjacent room |
| `r142` | right | 456–472 | No adjacent room |
| `r142` | right | 856–864 | Solid wall in `r160` |
| `r143` | left | 312–320 | Solid wall in `r148` |
| `r143` | left | 624–632 | Solid wall in `r148` |
| `r143` | right | 584–600 | Solid wall in `r133` |
| `r146` | left | 520–536 | Solid wall in `r149` |
| `r146` | right | 296–304 | Solid wall in `r154` |
| `r147` | right | 0–16 | Solid wall in `r148` |
| `r147` | right | 200–208 | Solid wall in `r148` |
| `r148` | left | 120–152 | Solid wall in `r147` |
| `r148` | right | 368–376 | Solid wall in `r143` |
| `r149` | left | 712–760 | No adjacent room |
| `r149` | right | 200–272 | Solid wall in `r146` |
| `r149` | right | 1256–1288 | Solid wall in `r181` |
| `r149` | right | 1344–1352 | Solid wall in `r181` |
| `r153` | right | 56–112 | No adjacent room |
| `r153` | right | 112–184 | Solid wall in `r156` |
| `r153` | right | 200–208 | Solid wall in `r156` |
| `r155` | right | 848–864 | No adjacent room |
| `r156` | right | 696–704 | Solid wall in `r157` |
| `r156` | right | 856–904 | No adjacent room |
| `r156` | right | 944–984 | No adjacent room |
| `r157` | left | 512–536 | Solid wall in `r156` |
| `r157` | left | 576–584 | Solid wall in `r156` |
| `r158` | right | 136–152 | No adjacent room |
| `r160` | left | 200–240 | Solid wall in `r142` |
| `r160` | right | 168–184 | No adjacent room |
| `r161` | left | 1392–1400 | Solid wall in `r204` |
| `r161` | left | 1488–1536 | No adjacent room |
| `r161` | right | 1536–1544 | Solid wall in `r203` |
| `r163` | right | 96–104 | Solid wall in `r142` |
| `r166` | left | 296–320 | Solid wall in `r168` |
| `r168` | right | 200–208 | Solid wall in `r166` |
| `r170` | right | 72–104 | No adjacent room |
| `r170` | right | 432–440 | Solid wall in `r177` |
| `r171` | right | 48–72 | Solid wall in `r172` |
| `r171` | right | 88–96 | Solid wall in `r172` |
| `r173` | right | 152–200 | No adjacent room |
| `r174` | left | 64–72 | Solid wall in `r155` |
| `r177` | left | 48–80 | Solid wall in `r170` |
| `r177` | left | 128–136 | Solid wall in `r170` |
| `r178` | left | 1160–1200 | Solid wall in `r214` |
| `r178` | left | 1216–1240 | Solid wall in `r214` |
| `r178` | left | 1368–1376 | Solid wall in `r214` |
| `r178` | left | 1464–1472 | Solid wall in `r214` |
| `r179` | left | 256–288 | Solid wall in `r178` |
| `r179` | left | 312–344 | Solid wall in `r178` |
| `r179` | left | 360–376 | Solid wall in `r178` |
| `r182` | left | 56–80 | Solid wall in `r180` |
| `r183` | left | 624–672 | No adjacent room |
| `r183` | left | 864–912 | No adjacent room |
| `r183` | right | 280–296 | Solid wall in `r188` |
| `r183` | right | 296–304 | Solid wall in `r195` |
| `r183` | right | 656–704 | Solid wall in `r195` |
| `r183` | right | 712–752 | Solid wall in `r195` |
| `r184` | left | 128–144 | Solid wall in `r185` |
| `r185` | right | 120–128 | Solid wall in `r184` |
| `r185` | right | 640–648 | Solid wall in `r206` |
| `r185` | right | 712–720 | Solid wall in `r206` |
| `r186` | right | 48–56 | Solid wall in `r187` |
| `r188` | left | 136–144 | Solid wall in `r183` |
| `r188` | right | 104–120 | Solid wall in `r149` |
| `r190` | left | 80–136 | No adjacent room |
| `r195` | left | 32–88 | Solid wall in `r183` |
| `r195` | left | 496–512 | Solid wall in `r183` |
| `r195` | right | 40–48 | Solid wall in `r196` |
| `r198` | left | 216–224 | Solid wall in `r192` |
| `r200` | left | 104–216 | No adjacent room |
| `r202` | right | 192–200 | Solid wall in `r204` |
| `r203` | left | 104–112 | Solid wall in `r161` |
| `r203` | left | 128–152 | Solid wall in `r161` |
| `r203` | left | 312–320 | Solid wall in `r161` |
| `r206` | left | 96–112 | Solid wall in `r185` |
| `r206` | right | 32–72 | No adjacent room |
| `r208` | left | 568–576 | Solid wall in `r216` |
| `r208` | right | 88–128 | Solid wall in `r209` |
| `r210` | left | 104–112 | Solid wall in `r203` |
| `r210` | left | 160–168 | Solid wall in `r203` |
| `r210` | right | 16–120 | Solid wall in `r178` |
| `r215` | right | 136–144 | Solid wall in `r207` |
| `r221` | right | 376–392 | Solid wall in `r222` |
