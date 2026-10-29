# Respawn checkpoint placement and cleanup

The editor has one **Respawn** tool with the original white player outline and
red head. Saved `spawn` and legacy `respawn` entities behave identically.
Checkpoints activate when walked onto, invisibly and without particles during
play. Placing or pasting a checkpoint keeps the other points; right-click removes
one and Undo restores edits.

## Ground and entrance coverage

Place checkpoints on permanent solid terrain, with clear headroom and no liquid,
spikes or solid objects intersecting the player. Suspended jump-through platforms
are valid paths but **do not count as checkpoint ground**. Placement and runtime
activation enforce this distinction.

Cover distinct entrances with safe landings rather than imposing a fixed number
per room. C1 keeps three floor points: left `(8,328)`, center `(160,328)`, and right
`(224,328)`. Nearby entrances can share one checkpoint when the route between them
is a short, safe walk.

## Automated cleanup

Preview the whole world (room files stay unchanged):

```sh
python3 tools/prune_respawns.py worlds/story --output reports/checkpoint-review
```

Inspect one room:

```sh
python3 tools/prune_respawns.py worlds/story --rooms c6_wall_cave --output reports/c6-review
```

Apply after reviewing the printed plan:

```sh
python3 tools/prune_respawns.py worlds/story --output reports/checkpoint-review --apply
```

The script handles base rooms and their variants. It removes overlapping old/new
marker aliases, selects entrance coverage, then merges redundant nearby points
on the same elevation. By default points must be within **48 pixels / six tiles**
(`--merge-distance 48`). A merge requires continuous support, clear player
headroom, and no hazards, enemies, breakable barriers or boss gates along the
walk. A fixed jump-through bridge may support the walk; both checkpoint locations
must themselves stand on terrain. Gaps and different elevations prevent merging.
This deliberately conservative rule does not attempt jumps or ability-dependent
routes.

The checkpoint closest to an entrance wins, and the world start is retained.
For C6, the right point `(160,48)` covers the nearby landing, so the intermediate
left point `(120,48)` is redundant; the room's distant left point `(8,48)` remains.
C1's center/right points are farther apart than this local merge distance and
remain separate.

Reports contain `summary.json`. Applying also saves exact original changed-room
contents in `backup.json`; an existing backup is never overwritten. Choose a
fresh output directory for a later application. Keep the backup before making
further editor changes; it contains the original room JSON strings if a manual
restore is needed. Repeating the preview after cleanup produces no changes.
The script removes checkpoint entities only, preserving terrain, layout and all
other entities. This is a local redundancy check, not proof of all progression
routes. Runtime safety and gameplay tests remain necessary.

## Validation

```sh
python3 -m unittest discover -s tests -p test_prune_respawns.py
python3 -m unittest discover -s tests -p test_checkpoint_ground.py
godot --headless --path . res://reports/respawn-review/check.tscn
godot --headless --path . res://tests/test.tscn
godot --headless --path . res://tests/smoke.tscn
```

Applied shared-landing cleanup: **73 → 70** main-world checkpoints. Removed one
redundant point each from C6, Foothills and Vent Shaft. See
[the applied summary](../reports/checkpoint-landings/summary.json).
