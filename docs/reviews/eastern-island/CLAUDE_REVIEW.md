# Claude review handoff

Review the eastern-island design before implementation. These files were
requested by the user for review; the detailed earlier conversation was not
available when this proposal was written.

## Read first

1. Repository `AGENTS.md`.
2. `docs/reviews/eastern-island/BRIEF.md`.
3. `docs/reviews/eastern-island/MAP_PROPOSAL.md`.
4. Relevant parts of `docs/STORY_DESIGN.md`, the current story manifest, and
   movement, adventure, entity, and test code.

Stay within this project. Existing uncommitted changes predate this packet;
do not revert, stage, or rewrite them as part of review. The packet adds only
documentation and does not introduce playable rooms.

## Review questions

- Does the proposal deliver the confirmed requirements: eastern island,
  shore, volcano, underground maze, and a boss fight?
- Do the shore, volcano, and underground maze each contain at least two
  distinct rooms? Optional rooms and the return tunnel must not be used to
  satisfy their minimum counts. Is the boss arena one single tall room,
  with the refuge remaining part of the maze?
- Are room sizes and proportions meaningfully varied, with feasible horizontal
  and vertical placement? Check edge alignment and the maze's physical layout,
  rather than treating the room graph as a coordinate plan.
- Is the area order appropriate, or should the maze connect differently to
  the volcano? Treat the current topology as a proposal.
- Can every mandatory route work without dash, wall grab, or sword?
- Can energy regeneration support the ascent and boss without forcing damage
  or requiring optional upgrades? Identify measurements still needed.
- Does the maze offer meaningful exploration with enough landmarks to orient
  the player? Can all optional dead ends be exited?
- Is the proposed boss sufficiently distinct from the Ape while fitting the
  platforming-gimmick direction? Is its safe route readable and repeatable?
- Can the raft, quest gate, retry spawn, boss persistence, and return shortcut
  use existing systems? Name missing systems explicitly.
- Does the return shortcut preserve progression, including save/reload during
  arrival, the fight, victory, and return travel?
- Should the boss reward be dash, another upgrade, or deferred? Do not treat
  any reward as a confirmed user requirement.

## Requested review output

Write findings in `docs/reviews/eastern-island/REVIEW.md` when performing the
review. Start with blocking issues, then design improvements, then decisions
that need user input. Cite file paths and code evidence for technical claims.
Separate verified facts, proposals, and unanswered questions.

Conclude with a concrete recommended room graph and an implementation sequence.
Do not start implementing gameplay unless the user asks for implementation.

## Acceptance checks for later implementation

- At least two distinct rooms each in the shore, volcano, and maze, varied
  dimensions and proportions, and both horizontal and vertical connections.
- A single tall boss arena, with readable vertical combat and camera framing;
  do not split it into multiple rooms to satisfy the other areas' minimum.
- No overlap with existing room bounds; matching entrances and return exits.
- Mandatory route and maze loop traversable with default tuning and agreed
  arrival abilities; no collectible required to escape its own branch.
- Safe recovery shelves and repeatable boss attempts at minimum energy capacity.
- Boss gates close only after safe entry, open after victory, and recover
  correctly after death or reload.
- Victory and shortcut persist, with no boss bypass from the shore.
- Raft travel does not strand the player or repeat completed quest requirements.
- Run `godot --headless --path . res://tests/test.tscn` and
  `godot --headless --path . res://tests/smoke.tscn` after gameplay changes.
- Manually inspect the blockout and room transitions in the running game;
  graph connectivity and passing unit tests do not prove jump reachability.
