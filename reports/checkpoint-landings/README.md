# Shared checkpoint landings · 2026-10-30

Applied `tools/prune_respawns.py --output reports/checkpoint-landings --apply`.
Removed the intermediate C6 checkpoint `(120,48)`, retaining the right-hand
point `(160,48)`. Removed one nearby redundant point each in Foothills and Vent
Shaft. Main-world total: **73 → 70**. C1's three floor points are unchanged.

`summary.json` records the application; `backup.json` contains exact original
changed-room contents. Terrain and non-checkpoint entities are unchanged.
See [the guide](../../docs/RESPAWN_POINTS.md) for the reusable process.
