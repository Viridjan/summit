# Terrain morphing

`tools/morph_terrain.py` applies a terrain-specific contour pass to existing
authored areas. It supports six contour presets:

| Preset | Contour character | Default room selection | Output environment |
|---|---|---|---|
| `cavern` | Irregular shallow rock recesses | cavern, cavern_deep, volcanic_cave | Retains cave theme |
| `desert` | Broad, shallow sandstone scallops | sand | sand |
| `coast` | Scalloped cliff alcoves and overhangs | sea, island_shore | Retains coastal theme |
| `volcanic` | Narrow, jagged basalt cuts | volcano, volcanic_cave | Retains volcanic theme |
| `forest` | Stepped root-like pockets in rock banks | forest | forest |
| `ruins` | Rectangular alcoves aligned to a four-tile grid | temple, building | temple |

List the available presets without loading or modifying a world:

```sh
python3 tools/morph_terrain.py --list-terrains
```

[Compare the presets](../reports/terrain-morph/index.html) on one shared source
room, then follow each link to its preview on compatible project rooms.

Preview Lake Caves:

```sh
python3 tools/morph_terrain.py worlds/story --terrain cavern --region "Lake Caves"
```

Preview several areas or individual rooms:

```sh
python3 tools/morph_terrain.py worlds/story --region "Lake Caves" --region "Volcanic Maze" --seed 42 --output reports/terrain-morph/cavern
python3 tools/morph_terrain.py worlds/story --rooms c0_roar_tunnel c2_cave_teeth --intensity 0.6 --output reports/terrain-morph/tunnels
python3 tools/morph_terrain.py --terrain volcanic --region "Volcanic Maze"
python3 tools/morph_terrain.py --terrain forest --region "Jungle"
python3 tools/morph_terrain.py --terrain ruins --region "Cove Town"
```

Without a region/room selector, it previews rooms with compatible environments
as listed above. Region names correspond to the areas
in `world.json`; room IDs correspond to files in `worlds/story/`.

Open the generated `index.html` for before/after geometry. Orange marks rock
that would be carved; `plan.json` contains complete before/after room data.
Preview writes reports only. Default output is `reports/terrain-morph/<terrain>`;
different terrain types have separate report/backup directories. The supplied
comparisons and project-room previews do not apply changes to story files.

Apply the same settings after inspecting the preview:

```sh
python3 tools/morph_terrain.py worlds/story --region "Lake Caves" --region "Volcanic Maze" --seed 42 --output reports/terrain-morph/cavern --apply
```

Application saves original file contents in `backup.json`, then atomically
replaces changed room files. A failed write rolls back files already changed.
Every selected room is loaded and validated before any room is written.

Restore those exact original files:

```sh
python3 tools/morph_terrain.py worlds/story --restore reports/terrain-morph/cavern/backup.json
```

Restore refuses to overwrite subsequent editor changes. Reusing an output
directory containing a backup for a different application also refuses to
overwrite the backup; choose another `--output` directory. Repeating the same
settings on unchanged morphed rooms is a no-op. If comparing different seeds,
preview from the original source, or restore the previous application first.

## Shared rules and preset differences

- Correlated, seeded value noise selects contiguous boundary clusters. Presets
  vary noise scale, cluster width, spacing and depth. Desert uses broad shallow
  cuts; coast favors side walls and tapers its two-deep alcoves; volcanic uses
  folded noise and short alternating cuts; forest adds a small coordinate warp
  and stepped pockets; ruins snaps uniform alcoves to a four-tile world grid.
  The seed, coordinates, terrain and input determine the result.
- Recesses are one or two tiles deep and affect ceilings and side walls. Existing
  standing floors and their backing stay solid; existing air is never filled.
- The outer two tile rows/columns are fixed, retaining room seams and entrances.
  Thin walls retain at least two backing rock tiles. This is checked against
  current geometry before every brush, including edits on an opposite face.
- Every physical/interactable entity gets a protected neighborhood, including
  spawn support, hazard mounts, platforms, pools, signs and breakable barriers.
  Camera zones and automatic walk-in triggers do not mask entire rooms.
- A flood-fill guard rejects a brush that joins previously separate air regions.
  Boss arenas and rooms containing boss entities are skipped.
- Room dimensions, layout positions, entities and unrelated metadata are retained.
  Compatible palettes are preserved. Explicitly selecting an area with a
  different environment converts it to the preset's environment along with the
  geometry pass. `ruins` converts building artwork to temple artwork.
- `terrain_morph` metadata records the preset and output hash for repeatability.

The presets preserve standing surfaces, so they do not reshape pools,
raise floor bumps, relocate objects or redesign platform spacing. It creates
small-scale themed contours around the authored layout. This does not certify
that every existing ability gate retains exactly the same jumping possibilities;
the game's physics/reachability checks remain part of reviewing an application.
Rooms with tightly packed protected objects can legitimately produce no changes.

## Research and implementation choice

Researched on 2026-10-29:

- [Sebastian Lague's Procedural Cave Generation](https://github.com/SebLague/Procedural-Cave-Generation)
  is a complete source reference for his cave-generation tutorial series.
- [RogueBasin: Cellular Automata Method for Generating Random Cave-Like Levels](https://github.com/Chizaruu/roguebasin/blob/main/wiki/cellular_automata_method_for_generating_random_cave-like_levels.md)
  describes neighborhood smoothing and the disconnected-section problem, along
  with flood-fill and corridor strategies.
- [Red Blob Games: Making maps with noise functions](https://www.redblobgames.com/maps/terrain-from-noise/)
  explains spatial frequency, combining noise bands, ridges, terraces and biome
  shaping. The broad desert and jagged volcanic patterns adapt those ideas to
  small side-view contour brushes.
- [Red Blob Games: Island shaping functions](https://www.redblobgames.com/maps/terrain-from-noise/islands.html)
  compares shaping functions that preserve different amounts of noise variation.
- [BorisTheBrave: Dungeon Generation in Unexplored](https://www.boristhebrave.com/2021/04/10/dungeon-generation-in-unexplored/)
  describes an analysis of staged layout, terrain and finishing passes. Our
  forest and masonry brushes retain the authored layout while refining its edges.

For Summit, full random filling and cellular-automata regeneration would replace
authored level structure. The implemented choice is a constrained contour pass:
noise proposes clustered edits, protected cells preserve gameplay structure,
and connectivity checks reject destructive joins. This is our adaptation to
the project's side-view levels, not a claim that those tutorials prescribe it.
No external generator code or artwork was copied; the runtime tool uses Python's
standard library and does not need an internet connection.

## Validation

```sh
python3 -m unittest discover -s tests -p test_morph_terrain.py -v
sh tools/verify.sh
```

Tests cover seed reproducibility, input immutability, floors/borders/object
anchors, thin detour walls, boss exclusion, repeat application, region selection,
preview-only operation, apply/restore, restore conflict detection and invalid
input before any write. All six presets must create distinct contours on a
shared fixture and respect the same protected cells. The project's existing discovery-reachability test
currently fails independently of this tool; see the delivery notes for results.
