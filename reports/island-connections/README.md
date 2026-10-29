# Island connections · 2026-10-29

Foothills now connects directly to **i09, Ash Passage**, a 24×46 tall tunnel.
A ladder of overlapping rungs and an upper rest ledge support jump-only travel
in both directions. The original lower chamber, pool and inhabitants remain,
with its left exit connected to Junction.

The tunnel is now at [740,69]. The rest of the Volcanic Maze moves left by 128
and down by 23 tiles, including Serpent Lair. Its internal room offsets and
shapes remain intact. The extra i18 switchback room is removed. East Shore's
former descent is sealed. The rejected Echo Gallery roof link is restored.

North Shore ↔ South Shore uses paired direction signs: arrows, named destination,
and bound Interact prompt. Walking into a sign does not cause travel. The South
Shore sign stands near the eastern end, away from the initial monster placements.

Validation: `tests/island_routes.tscn` descends from Foothills through i09 into
Junction and climbs back using production player physics and jump only. It
also checks both coastal signs, Interact gating and clear grounded arrivals.
The cautious model independently checks the direct route with the summit and
east coast blocked, the tall entrance placement and preserved maze offsets.
`tools/check_entrances.py worlds/story` reports zero bad side entrances.

The existing `test_island.Island.test_new_fragments_and_characters_are_reachable`
fails on the unchanged baseline as well: its jump-only search from the new hub
start misses five discoveries. It is not relaxed by this work.
