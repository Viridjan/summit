# Map variety review

Reviewed 2026-10-25. Scope: all 39 rooms in the Story manifest; changes focus
on eight repetitive eastern-island rooms. Conclusions about variety are design
judgments, not a numerical fun score.

## Findings

The world already has good regional variety: 13 room dimensions and 10 visual
themes, horizontal and vertical routes, water, forest platforming, a chase,
settlements and two distinct boss encounters. Fifteen rooms share a 40×23
footprint; that is useful for pacing and is not itself a problem. Room size
alone does not distinguish the actions a player performs inside it.

The island had three specific weaknesses:

- The ascent and east slope each used ten evenly spaced jump-through rails.
  Despite opposite travel directions, they repeated essentially the same task.
- The underground “maze” was a branching tree, with no room-level loop:
  17 island rooms, 16 traversable shared-edge links, cycle rank zero. Most
  exploration meant following one corridor and retracing it.
- Falling rocks first appeared over deep water and narrow pillars, combining
  a new hazard with precision footing before a simpler introduction.

The mainland has stronger differences between its major beats. Its remaining
issues are unfinished village interactions and some long, empty return paths.
Those need narrative/gameplay decisions rather than randomly adding hazards.

## Research and application

These are our applications of the references, not layouts copied from them:

- **Recognizable places and discovery:** Team Cherry's direct interview
  describes sketching movement and side rooms before filling in interiors,
  and building locations that make sense together. This informed the return
  loop and optional routes within the island's existing physical layout.
  [Team Cherry interview, PC Gamer](https://www.pcgamer.com/how-to-design-a-great-metroidvania-map/).
- **A room's central activity:** the GDC workshop's developer discussion
  connects memorable spaces to a mechanic or setpiece, with difficulty and
  pacing considered across adjacent rooms. This informed different movement
  rhythms for the ascent and descent, rather than adding unrelated mechanics.
  [GDC Level Design Workshop developer Q&A](https://www.gamedeveloper.com/design/gdc-2017-level-design-workshop).
- **Teach, test, twist and recovery:** the original Level Design Book pacing
  chapter recommends developing a familiar activity and alternating intensity
  with recovery. The foothills now introduce falling rocks slowly over dry
  ground; Flooded Hall later combines them with narrow footing and water.
  The existing refuge remains quiet before the boss.
  [The Level Design Book: Pacing](https://book.leveldesignbook.com/process/preproduction/pacing).

## Applied changes

| Room | Change and purpose |
|---|---|
| South Shore | Optional cliff-top route and second star above the tide pool; the lower route stays open. |
| Foothills | One falling-rock column every 3.8 seconds over dry ground, with the existing 0.6-second warning. Flooded Hall retains its faster 1.2-second emitter. |
| Volcano Ascent | Four natural rock ledges, six rail connections and existing rest shelves replace ten identical rails. |
| East Slope | Five solid descent landings and five smaller return rails create a separate movement rhythm. |
| Flooded Hall | Two contained pools flank a dry well down to Vent Shaft. The original east/west crossing remains. |
| Echo Gallery | A shallow, escapable hollow and an upper stepping route interrupt the flat floor. |
| Lower Maze | Upper reward passage under the arch and a lower corridor offer a local choice; a new star rewards exploration. |
| Vent Shaft | Climbable connection to Flooded Hall closes a four-room loop through Echo Gallery and Lower Maze. |

The island now has 17 shared-edge links across 17 rooms: one independent
room-level loop. Both new stars are reachable in the cautious jump-only model.
The loop does not bypass the boss gate. Room positions and dimensions, the
39-room manifest, mainland geometry and the single tall boss arena are unchanged.

## Validation and limits

- All island rooms and every island star are reachable in the cautious
  jump-only model; far rooms retain return routes.
- A new regression blocks Echo Gallery and verifies that Lower Maze can
  still return to Junction through Vent Shaft and Flooded Hall. It failed on
  the old map and passes on the revised map.
- Entrance and spawn safety are checked separately from map connectivity.
- See [the before/after map viewer](map-variety.html) for actual geometry.

The Python movement model is approximate and does not simulate dynamic rocks,
enemies, or swimming energy. Engine regression tests and visual inspections
complement it; a full human traversal is still needed to judge pacing and fun.
No online guide or connectivity check can establish those by itself.

## Follow-up priorities

1. Playtest the new rockfall introduction and the length of the dry-well return.
2. Distinguish maze junctions with placed crystal/root landmarks; the current
   art-dressing helper still uses names from the previous island layout.
3. Give village rooms interactions when their NPC/quest system is ready.
4. Consider a discoverable mainland return shortcut after player testing,
   without opening the intentionally ability-gated early big jump.

Authored changes live in `tools/story/gen_island.py` as well as room JSON.
They were generated and repaired in a temporary copy first; only the eight
reviewed room files were applied to the project.
