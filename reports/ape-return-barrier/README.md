# Post-Ape return barrier

Jungle Hills has a thorn barrier at (368,8), 8×112 pixels. It is open before
`a1_ape_arena:ape_144_120` is set and solid afterwards. The full-height barrier
separates the early Jungle approach from the Depths shaft, preserving both
onward routes: Jungle Depths/Treetop Village and Sand Cave.

- `before.png` / `after.png`: production-game captures.
- `tests/ape_return_barrier.tscn`: real collision, exit and room-reload checks.
- `tests/test_ape_return.py`: return blocked even with dash, climb and attack;
  forward routes remain reachable with the intended movement model.
- Progression report regenerated with post-boss barriers and arena continuation;
  browser checks confirm the Ape no longer offers early Jungle as a destination.

Gameplay runner: 0 failures. Smoke runner: SMOKE OK.
