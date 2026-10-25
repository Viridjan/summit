# Eastern island — review brief

Status: design proposal for Claude review; no island rooms or gameplay changes implemented.
Prepared: 2026-10-25.

## Confirmed user requirements

- An island east of the current story area.
- A shore, a volcano, an underground maze, and a boss fight.
- Shore, volcano, and underground maze are areas containing at least two
  distinct rooms each. Rooms may connect horizontally or vertically.
- The boss arena is the exception: one single tall room.
- Diversify room sizes and proportions across the island; do not make every
  room the same screen-sized rectangle.
- Files prepared for Claude to review before further work.

The earlier detailed request is unavailable in this session. Everything beyond
these requirements is a proposal, not a recovered user decision.

## Existing project context

- The playable world is `worlds/story/world.json`.
- `docs/STORY_DESIGN.md`, section 1.7, describes a raft from the shore to the
  next island to the right. Lighthouse quest interaction gates the raft.
- `worlds/story/s2_shore.json` currently contains a note for that connection;
  the island is not built in this checkout.
- NPCs, dialogue, quest flags, and the raft remain dependencies documented in
  the story design. Verify actual implementation before integrating travel.
- The story starts without dash, climb, or attack. The right branch proposes
  a sword reward, but its availability must be verified before relying on it.
- Story bosses are intended to be platforming gimmick bosses.

## Proposed experience

Arrive at a calm shore with the volcano visible to the east. Climb its lower
slopes, enter a crater passage, and descend into a maze of volcanic tunnels.
Landmarks and loops make the maze learnable. Emerge at a quiet boss approach,
fight using movement and the environment, then unlock a short return route.

Use jump-only movement for the mandatory route until arrival abilities are
explicitly agreed. Dash, wall grab, sword, and heat resistance must not become
accidental requirements. A new ability reward is deliberately undecided.

## Scope of the next implementation

1. Measure default movement and energy constraints with existing test helpers.
2. Build a disposable island blockout before linking it into the story manifest.
3. Validate room transitions, return routes, maze navigation, and boss retries.
4. Add boss behavior only after its movement puzzle works in a static blockout.
5. Integrate actual raft travel and quest gating when those systems exist.
6. Add art, effects, and audio after the route is playable.

Do not edit the existing shore, regenerate existing rooms, or add the proposed
rooms to the live manifest merely to review this packet.

## Decisions for review

| Question | Proposed default |
|---|---|
| Arrival abilities? | Jump only; other abilities optional. |
| Order of areas? | Shore → volcano → underground maze → a single tall boss arena. The first three areas each have at least two rooms. |
| Maze complexity? | One main loop, two optional branches, repeated landmarks. |
| Boss concept? | Volcanic guardian defeated by baiting attacks at weak floor plugs. |
| Reward? | Leave open; dash is a candidate because the earlier big jump needs it. |
| Return travel? | Bidirectional raft after arrival; no quest repeated on return. |
| Saving and retries? | Use existing save/respawn behavior; no new save-slot system. |

## References

- `docs/reviews/eastern-island/MAP_PROPOSAL.md`: topology and room beats.
- `docs/reviews/eastern-island/CLAUDE_REVIEW.md`: review instructions and checks.
- `docs/STORY_DESIGN.md`: existing narrative and progression constraints.
- `scripts/player.gd`, `scripts/adventure.gd`: actual movement and energy rules.
- `scripts/entities.gd`: existing hazards and boss implementation.

Story notes contain historical and potentially conflicting numbers. Code and
fresh measurements should determine blockout metrics, not copied prose values.
