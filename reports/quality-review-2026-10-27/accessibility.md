# World accessibility audit

World: `worlds/story`. Start: `m1_meadow`. 39 rooms; 12 door entities.

This is a static connectivity test, **not a physics playthrough**. It ignores gravity, jump/dash reach, stamina, and return paths. Crouch models allow a one-tile body everywhere; standing requires two vertical tiles (conservative for the actual 8×11px hitbox). Breakable walls are assumed broken. Hazard rectangles are rounded outward to tiles; spikes are treated as lethal from every direction. Doors allow any valid target tile, rather than reproducing the runtime arrival offset. No enemies or moving entities are simulated, and temporary travel above room tops is omitted. Results identify routes to investigate; neither green cells nor flagged rooms establish live traversability.

Map: green = standing model; blue = crouch model only; amber = topology only; red = disconnected even without hazards.

| Model | Reached rooms | Unreached rooms |
|---|---:|---|
| topology | 39/39 | None |
| acid | 39/39 | None |
| hazards | 39/39 | None |
| standing | 39/39 | None |

## Rooms flagged by hazard or standing models

| Room | World tile origin | Markers | Flags |
|---|---|---|---|
