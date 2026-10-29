# Island connections · 2026-10-29

All four shores are now 120 tiles long, three times their original width.
Each shore has two interactable direction panels to neighboring shores.
North–South and East–West have no direct panel. North Shore’s original `coast_path` leads to West Shore; the other
panel leads east. North and South occupy separate map locations, with their
old vertical exits sealed. West–Foothills and East–volcano side passages remain.

Foothills connects directly to i09, Ash Passage, a 24×46 tall tunnel. The volcano
and maze move together to retain their relative offsets beside the longer West
Shore. The post-Guardian West Shore keeps its reward door and both panels.

`tests/island_routes.tscn` checks all 8 panel routes, explicit Interact gating,
safe arrivals, the post-Guardian variant, real jump/swim traversal of each new
beach stretch, and the jump-only round trip through Ash Passage.
`tests/test_island_connections.py` independently checks layout, connectivity and
panel reachability. Both shore and island link tools are idempotent.

Validation: all 8 real panel transfers, extended beach traversal, the Guardian
variant and the Ash Passage round trip pass. Eight focused Python checks pass;
entrance validation reports zero bad entrances. Gameplay and smoke checks pass.
The existing broader `test_new_fragments_and_characters_are_reachable` still
fails: its hub-start jump-only model misses the same five discoveries (three
shore fragments and two characters). This test remains unchanged.
