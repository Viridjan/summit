# Island connections · 2026-10-29

All four shores are now 120 tiles long, three times their original width.
Each shore has three separate interactable direction panels leading to every
other shore. North Shore’s original `coast_path` leads to West Shore; a separate
panel leads south. North and South occupy separate map locations, with their
old vertical exits sealed. West–Foothills and East–volcano side passages remain.

Foothills connects directly to i09, Ash Passage, a 24×46 tall tunnel. The volcano
and maze move together to retain their relative offsets beside the longer West
Shore. The post-Guardian West Shore keeps its reward door and all three panels.

`tests/island_routes.tscn` checks all 12 panel routes, explicit Interact gating,
safe arrivals, the post-Guardian variant, real jump/swim traversal of each new
beach stretch, and the jump-only round trip through Ash Passage.
`tests/test_island_connections.py` independently checks layout, connectivity and
panel reachability. Both shore and island link tools are idempotent.
