# Checkpoint cleanup · 2026-10-30

Reviewed all 47 main-world rooms and configured variants. Removed eight redundant
markers: 81 → 73. C1 retains its three agreed floor positions. Every remaining
point passes the runtime safety audit. Terrain, other entities and room layout
are unchanged. `backup.json` stores exact pre-cleanup contents for changed rooms.

`python3 tools/prune_respawns.py` previews; `--apply` applies once with a backup.
Selection uses distinct physical/door entrances and preserves the world start.
Repeating the review after cleanup reports no changes.
