# Eastern island — review

**Status: built as a blockout on 2026-10-25** with the recommended defaults (boss 40×46, door shortcut, raft door,
no reward). Room IDs: i01..i13 (`tools/story/gen_island.py`).

Reviewed 2026-10-25 against `BRIEF.md`, `MAP_PROPOSAL.md`, `docs/STORY_DESIGN.md`, `worlds/story/world.json`
and the code. Labels: **[fact]** checked in code or measured; **[proposal]** a recommendation; **[question]** for the user.

## Measurements (default tuning, 60 Hz, headless probe on a flat test level)

- **[fact]** Full held jump from a full run: apex **29 px (3.6 tiles)**, airtime **0.67 s**, flat distance **63 px (7.9 tiles)**.
  Constants in `scripts/player.gd` (`JUMP_SPEED -105`, `GRAVITY 900`, `MAX_RUN 90`).
  Blockout rule: required rises ≤ 3 tiles, required gaps ≤ 5 tiles; 6-7 tile gaps only for optional pickups.
- **[fact]** Energy (as of today's change): base **20**, jump **2.5**, regen **6/s** everywhere outside water, also mid-air
  (`World.update_energy`, `scripts/world.gd:628`; `Adventure.regen_energy`). A jump regains 6 × 0.67 ≈ 4 energy in the
  air, more than the 2.5 it costs. **Chained jumps on land never run out**; energy limits only water and very fast
  repeated short hops. The proposal's "energy regeneration supports the ascent" is satisfied by construction; recovery
  shelves are a pacing tool, not an energy need. Respawn refills the base bar (`World.respawn`).
- **[fact]** Map space: existing rooms end at x = 679 tiles (Shore, Lighthouse Top), y spans -14..137. Everything from
  x ≥ 700 is free. The coordinates below were checked by script: no overlap with existing or new rooms.

## Blocking issues

1. **Boss plumbing is Ape-only.** [fact] `BossGate` and `AutoWalk` decide with `Ape.alive_in(w)`, which only finds
   `e is Ape and not e is ApeChase` (`scripts/entities.gd`, class `Ape.alive_in`, `BossGate.update`, `AutoWalk.touch`).
   A new boss can't lock gates or trigger the walk-in. Needed: a shared `boss_alive(w)` (any entity with a `boss`
   flag, not gone). Small change, but it must come first.
2. **No raft, NPC or quest flags.** [fact] `grep raft|quest scripts/` finds nothing; `STORY_DESIGN.md` §Systems lists
   NPCs, dialogue and quest flags as not built. **Existing parts that cover most of it:**
   - travel: the cross-room `door` entity (`"to": "room:id"`, `World._go_door`, `scripts/world.gd:425`) can be the raft,
     with no long room in between;
   - gating: `world.json` `"variants"` swap a room when an id is in the run's `broken` set
     (`Adventure.room_level`, used by the Ape arena). A quest flag can be one more id in that set, so "raft usable" is a
     Shore variant with the door. Missing is only the thing that writes the flag (an NPC talk).
   Until then: a dev-only door, never in the shipped Shore (as the brief says).
3. **An 80-tile boss room is 3.5 screens tall.** [fact] One screen is 40×23 tiles (`docs/WORLD_DESIGN.md`). Telegraphs
   and landing targets more than ~11 tiles above or below the player are off screen, which fails the acceptance check
   "camera framing … without offscreen jumps". [proposal] **40×46** (two screens): still clearly tall, ledge tiers
   fit, every attack readable. [question] keep 80 with a zoomed-out camera for this room (new camera rule), or go to 46?
4. **I11 Return Tunnel (112×24) can't be placed** as one straight room without crossing the maze or the sea gap.
   [proposal] Drop it. After victory the boss room's variant opens a `door` back to I01 (and I01's variant gets the
   matching door). Both use existing systems, persist via `broken`, and give no way in from the Shore before the fight.
5. **Touching rooms open automatically.** [fact] Two rooms that share an edge get a passage wherever both sides have
   open tiles (README, World editor). In the embedding below every touching pair is an intended link, but the shared
   spans are long (I06/I07 share 72 columns, I07/I08 32 rows): only the passage tiles may be open, the rest of each
   edge must stay solid. `tools/check_entrances.py`
   and the room-safety tool should run on the island before linking.

## Design improvements

- **Order is right**: shore → volcano → maze → boss, matching the climb-up-then-down shape. The maze joining the
  volcano through the crater floor (vertical) is better than a side door: the descent is the reveal.
- **Area minimums**: Shore 2 (I01, S02), Volcano 3 (I02-I04), Maze 5 (I05-I09); optional rooms and the shortcut are not
  counted. Refuge stays in the maze. Boss is one room. Sizes vary (24-96 wide, 24-72 tall). ✔
- **Maze loop**: junction → gallery → lower maze → vent shaft → junction works physically (embedding below).
  Every drop into the lower maze or a dead end needs a way back up within 3-tile rises; the vent shaft
  (32×64) is the natural climb back, so put shelves every 3 tiles there.
- **Landmarks**: give each junction a silhouette (split rock in I05, crystal in I06, root arch in I07) and repeat the
  next room's landmark at the doorway, as the proposal says. Use the map (M) explored state as the second aid.
- **Boss** (volcanic guardian, floor plugs): distinct from the Ape (it stays put and strikes where you stand, the Ape
  leaps and throws). In a tall room, put plugs on **three tiers**: bait on the floor, then a mid ledge, then a high
  ledge, with the safe ledge always one ≤3-tile jump away. Broken plugs become solid rubble, never holes, so the
  retry spawn and floor stay safe. Reuse: kill on contact (`Player.die`), `burst`/`shake_dir`, `spawn_entity`,
  victory persistence via `break_wall(id)` (same as the Ape). Retry spawn: I09 Refuge owns it (`World.safe_spawn`
  already rejects hazards); the boss room's own spawn sits behind the entry gate.
- **No lava rules yet**: use `acid` as the stand-in for lava (exists, kills on touch).

## Recommended room graph and coordinates (tiles; checked for overlap)

| Room | Size | Position | Connects |
|---|---|---|---|
| I01 Island Shore | 96×24 | (700, 46) | raft door ↔ Shore; east edge → S02; after victory: door from boss |
| S02 Tidal Terraces | 48×36 | (796, 34) | west ← I01; east → I02 |
| I02 Basalt Foothills | 64×32 | (844, 38) | west ← S02; top (cols 868-907) → I03 |
| I03 Volcano Ascent | 40×72 | (868, -34) | bottom ← I02; east edge (rows -30..17) → I04 |
| I04 Crater Descent | 48×48 | (908, -30) | west ← I03; floor (cols 916-955) → I05 |
| I05 Underground Junction | 48×32 | (916, 18) | top ← I04; east → I06; floor (cols 940-963) → I08 |
| I06 Echo Gallery | 80×24 | (964, 18) | west ← I05; floor → I07; ceiling (cols 990-1013) → O1 |
| I07 Lower Maze | 72×40 | (972, 42) | top ← I06; west ← I08; east → I09 |
| I08 Vent Shaft | 32×64 | (940, 50) | top → I05; east → I07; west → O2 |
| I09 Quiet Refuge | 32×24 | (1044, 58) | west ← I07; east (gate) → I10 |
| I10 Boss Chamber | 40×46 | (1076, 36) | west ← I09 (boss gate); after victory: door → I01 |
| O1 Crystal Pocket | 24×24 | (990, -6) | floor → I06 (dead end, drop back down) |
| O2 Sealed Overlook | 40×24 | (900, 80) | east → I08 (dead end) |

Horizontal links: I01-S02-I02, I03-I04, I05-I06, I08-I07, I07-I09-I10, O2-I08.
Vertical links: I02-I03, I04-I05, I05-I08, I06-I07, I06-O1.

## Decisions for the user

1. Boss room height: 46 (recommended) or 80 with a special camera?
2. Boss reward: dash (opens `m2_big_jump`'s gap), something else, or none for now? Nothing is assumed.
3. Return: door shortcut after victory (recommended) instead of the 112-wide tunnel?
4. Raft before NPCs exist: dev-only door now, real raft + quest flag later?
5. Energy is no longer a limit for jumping on land (see Measurements). Is that intended for the island, or should
   regen pause mid-air?

## Implementation sequence

1. Generic boss check (`boss_alive`) for `BossGate`/`AutoWalk`; keep the Ape tests green.
2. Generator script for the island (`tools/story/gen_island.py`, same `Room` helpers), blockout only, rooms placed as
   above, unlinked edges walled; dev door from the Shore.
3. Checks: `world_fixups.py`, `check_entrances.py`, room safety; a test that walks the mandatory route with the
   test runner's Bot (jump-only, default tuning), plus the maze loop both ways.
4. Boss in a static blockout: plugs, tiers, telegraph; then the attack loop; then victory → `break_wall(id)`,
   variants for I10 (open gate) and I01 (shortcut door). Tests for death reset, reload mid-fight, victory persistence,
   no Shore-side entry before victory.
5. Raft as a Shore variant door once a quest flag exists (NPC talk writes the id).
6. Art, `acid`→lava visuals, music key for the island, sounds.
