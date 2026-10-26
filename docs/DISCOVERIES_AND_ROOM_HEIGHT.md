# Discoveries and room height

Updated 2026-10-26 from the user's direction.

## Optional discoveries

The Meadow's opening star has been removed. New optional rewards should be
entities to interact with: fragments, characters or encounters/minibosses.
Existing passive stars are legacy content being replaced gradually.

This first batch replaces five stars:

| Location | New discovery |
|---|---|
| North Shore cliff | Energy fragment |
| South Shore rocks | Energy fragment |
| East Shore | Energy fragment |
| Jungle Edge leaf perch | Aerin, an elf who speaks when interacted with |
| Crystal Pocket | Crystal Keeper, a mage who explains fragments |

Press the existing **Interact** action (S / controller B by default) near an
entity. A prompt appears in range. Merely touching a fragment does not collect
it. Three fragments grant one capacity upgrade: the existing +20 stamina
block, filled when granted. Partial progress and collected piece IDs persist;
pieces cannot grant upgrades again after death or reload. The HUD shows the
number of fragments toward the next upgrade.

Characters use the player-scale elf/mage sprites and simple timed dialogue.
This batch does not introduce quest chains or new miniboss combat. The remaining
stars are still legacy collectibles pending individual replacement designs.

## Height contrast

Eighteen rooms were shortened; 20 of the 39 rooms now have heights of 13–18
tiles. Remaining ordinary rooms retain extra space where it serves depth,
architecture or vertical connections. The 46-tile volcano climb/descent,
lighthouse stairs, sand-cave setpiece and single tall Guardian arena remain.
The 32-tile vent shaft remains a dedicated vertical connector.

Most trimming removes unused overhead space and moves the room's world origin
down by the same amount. Floor geometry, player routes and side-seam positions
therefore stay in the same global coordinates. Roof/open-sky treatment is
preserved. The lighthouse balcony instead loses inaccessible space below its
continuous floor. Rooms entered through their ceilings were not top-trimmed.

Stable legacy pickup IDs prevent duplicate rewards after coordinates change.
Saved spawn positions are validated against the new room; invalid ones fall
back to an authored safe spawn.

## Maintenance and validation

- `tools/story/refine_regions.py <world-directory>` applies this pass after a
  fresh layout generation. Review a disposable copy first; ordinary story
  generators still author their original layout dimensions. The refinement is
  idempotent on an already-refined layout. Avoid mixing a single untrimmed room
  with an already-trimmed manifest without checking its world position.
- `vertical_trim` records removed top rows. The visual dressing helper respects
  this offset when placing villagers and props.
- `tests/discoveries.gd` checks three-piece upgrades, reloads, duplicate
  collection, Interact requirements, room rebuilds and stale saved spawns.
- The Python reachability suite checks all new discovery locations and keeps
  the island loop/return checks. Engine gameplay and smoke tests cover actual
  collision and room/door transitions, with fixture positions updated for the
  resized rooms.
