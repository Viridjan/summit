# World accessibility audit

World: `worlds/story`. Start: `m1_meadow`. 47 rooms; 20 door entities.

This is a static connectivity test, **not a physics playthrough**. It ignores gravity, jump/dash reach, stamina, and return paths. Crouch models allow a one-tile body everywhere; standing requires two vertical tiles (conservative for the actual 8×11px hitbox). Breakable walls are assumed broken. Hazard rectangles are rounded outward to tiles; spikes are treated as lethal from every direction. Doors allow any valid target tile, rather than reproducing the runtime arrival offset. No enemies or moving entities are simulated, and temporary travel above room tops is omitted. Results identify routes to investigate; neither green cells nor flagged rooms establish live traversability.

Map: green = standing model; blue = crouch model only; amber = topology only; red = disconnected even without hazards.

| Model | Reached rooms | Unreached rooms |
|---|---:|---|
| topology | 41/47 | `hub_landing`, `w1_wilds_gate`, `w2_wilds_hollow`, `w3_wilds_roots`, `w4_wilds_den`, `w5_wilds_drop` |
| acid | 41/47 | `hub_landing`, `w1_wilds_gate`, `w2_wilds_hollow`, `w3_wilds_roots`, `w4_wilds_den`, `w5_wilds_drop` |
| hazards | 41/47 | `hub_landing`, `w1_wilds_gate`, `w2_wilds_hollow`, `w3_wilds_roots`, `w4_wilds_den`, `w5_wilds_drop` |
| standing | 41/47 | `hub_landing`, `w1_wilds_gate`, `w2_wilds_hollow`, `w3_wilds_roots`, `w4_wilds_den`, `w5_wilds_drop` |

## Rooms flagged by hazard or standing models

| Room | World tile origin | Markers | Flags |
|---|---|---|---|
| `hub_landing` | [-40, 0] | You land here. Left: the Western Wilds. Right: the meadow. | topology, acid, hazards, standing |
| `w1_wilds_gate` | [-80, 0] | — | topology, acid, hazards, standing |
| `w2_wilds_hollow` | [-120, 0] | — | topology, acid, hazards, standing |
| `w3_wilds_roots` | [-80, 23] | — | topology, acid, hazards, standing |
| `w4_wilds_den` | [-120, 23] | — | topology, acid, hazards, standing |
| `w5_wilds_drop` | [-40, 23] | — | topology, acid, hazards, standing |
