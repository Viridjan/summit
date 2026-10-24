# Hallownest room-transition and boundary safety

World: `res://worlds/story/world.json` — 18 rooms. This report only reads the game; it changes nothing.

## Results

- **0 directed room-edge connections** produced collision-overlapping arrivals (0 failing probes).
- **0 door connection** produced collision-overlapping arrivals (0 failing probes).
- **0 upward boundary locations** allowed the player past the normal 24px ceiling allowance with the centre outside every room.
- **7 bad left/right opening spans in 4 rooms:** 4 face no neighbouring room; 3 face a neighbour's solid terrain.

The 60 Hz replays below run the original failure cases with actual player updates, dash input, collision callbacks, entity touches, room changes, and dash freeze timing. They start from seeded local positions, not from a demonstrated route from the world spawn. A seed that is inside rock before moving is out of date (its spot changed), not a failure.

## Reproduced examples

| Source and action | Start feet position, local px | Result |
|---|---|---|
| `c3_cove_tunnel` — Cove Tunnel into Cove Town | [308, 152] | No overlap reproduced |
| `l2_net_trap` — Net trap door to the treetops | [168, 152] | No overlap reproduced |
| `m1_meadow` — Meadow open sky | [320, 152] | No overlap reproduced |

Tick numbers are zero-based, at 60 Hz. Start coordinates refer to the player’s feet, not the top-left of the sprite.

## What failed before, and the fix

- Fixed: collisions past a room edge now test the next room's tiles (`World._near_solid`), so its rock blocks before the room changes. After a room change or door arrival `World._unstick` moves the body out of any overlap. You can rise above a room's top only where another room touches it directly. Side and top openings facing no room or rock are sealed by `tools/world_fixups.py`.

The original findings:

- Edge movement collides only against the current room. The room changes after the player centre crosses the boundary; terrain in the destination can already overlap the body. `Adventure.room_at` can also return a solid-room fallback. Entry does not reject or resolve the collision.
- Door arrivals clamp the player to the target doorway rectangle but do not validate that the hitbox is free of terrain. The reproduced `r023:d8 → r039:d9` case places the player at `(156,24)` inside terrain.
- Ceiling bounds consult a point at the top of the hitbox, while room changes use the centre. Across a gap between room rectangles, that point can already be in another room while the centre is still in unassigned space. In the three replayed cases this lasts one frame and is followed by embedding in the upper room.
- An opening facing no room is often stopped by the horizontal bounds clamp. It is a visual/map-connectivity defect, not automatically an out-of-bounds exploit. Wall-facing openings are more dangerous because `can_exit` accepts the neighbour rectangle even where its terrain is solid.

## Coverage and limits

- Tested 12,183 valid seeded edge starts; 11,751 crossings. All integer seam alignments, both directions, standing/crouched, with [1, 4, 8] pixel movement batches.
- Tested 2,024 valid integer doorway-contact offsets and 8,369 valid outer-edge starts.
- Probe runner uses the real movement, bounds, door and room-entry methods. Rendering and save writes are disabled; static room collision structures are cached. General edge probes isolate cardinal movement and omit ordinary hazard touches; full-update replays do include touches.
- Outer-boundary sweep uses 1px cardinal movement. The normal 24px top allowance and the brief bottom death margin are excluded from failures. Invincibility is off.
- This is not exhaustive over every velocity, subpixel remainder, diagonal input, movement state, moving obstacle, or recovery sequence. No claim is made that all remaining locations are safe.
- Side openings are maximal contiguous vertical terrain spans with the same issue and target. A two-tile opening counts as one span. Other valid-looking openings can still be too small for the complete player hitbox.

## Re-run

```sh
godot --headless --path . res://tools/room_safety.tscn
godot --headless --path . res://tools/room_safety.tscn -- --phase replay --output res://reports/story-room-safety-replays.json
python3 tools/check_side_openings.py
python3 tools/summarize_room_safety.py
```

Runtime checker exits 1 when it reproduces a failure, 0 when the selected checks find none, and 2 for invalid configuration/output. Use a disposable `XDG_DATA_HOME` for sandbox runs, e.g. `env XDG_DATA_HOME=/tmp/summit-room-safety godot ...`. It never writes the gameplay adventure save. The replay phase seeds three story-world spots. Other worlds can use `--world res://adventure/world.json --output /tmp/adventure-safety.json` for edge/door/bounds sweeps.

## All failing room connections

| Type | Source → target | Failing probes | Sample start → arrival (local px) |
|---|---|---:|---|

## All bad left/right openings

| Room | Side | Local vertical span (px, end exclusive) | Faces |
|---|---|---|---|
| `c2_cave_teeth` | right | 72–104 | Solid wall in `c3_cove_tunnel` |
| `s1_sand_cave` | left | 256–280 | Solid wall in `a1_ape_arena` |
| `s2_shore` | left | 8–16 | Solid wall in `s1_sand_cave` |
| `s3_lighthouse_top` | left | 0–88 | No adjacent room |
| `s3_lighthouse_top` | left | 104–184 | No adjacent room |
| `s3_lighthouse_top` | right | 0–88 | No adjacent room |
| `s3_lighthouse_top` | right | 104–184 | No adjacent room |
