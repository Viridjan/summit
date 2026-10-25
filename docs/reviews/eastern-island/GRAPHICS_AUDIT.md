# Eastern island graphics — implementation status

Updated 2026-10-25. The original missing-art inventory is now implemented in
`scripts/island_art.gd` and exported under `assets/island/`.

## Created

- Serpent: idle, movement, warning, attack, hurt and defeat rows, four frames
  each. Connected to the current Guardian's existing eruption behavior.
- Falling-rock pack: rock, ceiling warning and breakup/impact sprite sheets.
  The dedicated falling-rock hazard behavior remains separate; this pass
  supplies graphics. The Ape's projectiles retain their earlier stone artwork
  at the user's request.
- Treetop elves and lighthouse mages: five appearances each, with idle,
  walk, talk and gesture rows. Five animated decorative inhabitants are placed
  in each village. Dialogue, quests and NPC movement are not implemented.
- Shore, volcano and volcanic cave: complete compatible terrain, corner,
  decoration and parallax packs. Assigned to the new island rooms.
- Maze landmarks: split rock, crystal formation and root arch, placed at
  selected junctions and in the crystal pocket.
- Lava surface animation, eruption, intact/broken vent plugs, raft,
  lighthouse magic flame and mirror artwork. These are connected to existing
  visual props and hazards where applicable, without changing damage rules.

## Style and constraints

Flat, angular pixel art; nearest-neighbor sampling; existing 8×8 terrain
layout and atlas formats. The approved Ape landing graphics remain unchanged.
New environment names reuse existing music scores and recordings.

## Review and maintenance

- `assets/island/preview.html`: animated gallery of every pose and appearance.
- `assets/island/manifest.json`: native sizes, row layout and provenance.
- `assets/island/README.md`: runtime integration, rebuild and limitations.
- `tools/export_island_art.gd`: deterministic source-to-PNG exporter.
- `tools/story/dress_regions.py`: repeatable visual placement pass, needed
  after existing story generators rewrite the affected room files.
- `tests/island_art.gd`: size, transparency, animation and theme checks.

The serpent artwork is integrated as a visual replacement for the former
stone-face Guardian, not a newly designed moving serpent combat system.
Raft quest gating and the lighthouse mirror puzzle are still separate gameplay
work. No claim is made that decorative villagers implement those systems.
