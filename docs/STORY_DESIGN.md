# Story world: chapter 1

Design notes from 2026-10-24. Not built yet; tasks are in `TODO.md` (Story world).
More details will be added later.

The player faces right from the start, and the route mostly moves right.

## 1. Route

### 1.1 Start: flat meadow
- Mostly flat, a few jumps and a few spikes, nothing excessive.
- No enemies.

### 1.2 The big jump
- A gap meant for a **wavedash**, not a normal jump.
- Shape: a cone or triangle with the narrow point facing up.
- **Not crossable at the start:** the player has jump only, and a wavedash needs dash. It's a gate for later: the player returns once dash comes from a later level (which level is still open).

### 1.3 First lake and cave (below the jump)
- A lake at the bottom, darker than the meadow.
- A few tunnels that lead nowhere in particular.
- **Roaring sounds come from the left** (stereo, panned left; see Audio). They hint at the ape.

### 1.4 Cove or small city
- Further right: a cove or small town with a couple of NPCs.
- NPCs don't exist in the game yet (see Systems).
- **The second energy block is collected here.**
- Has at least one quest that rewards a skill point (true for every village).

### 1.5 Jungle (right of the city)
- A waterfall, lots of vegetation, a lake; the player drops down again here.
- Big trees and tree trunks.
- Enemies that aren't aggressive: they just walk back and forth.
- Exploration: hills and tunnels, still heading right.
- In a couple of places, platforms made of leaves can be reached.
- New content: **leaf platforms**, a **forest** environment theme, **waterfall blocks**.

### 1.6 Boss 1: the Ape (end of the jungle)
See Bosses. Reward: a power-up.

### 1.7 The fork after the Ape
Past the Ape the path splits. Each side changes the story.

**Right: sand cave → shore**
- A cave full of sand and breakable platforms, climbing diagonally at about 30°, with some platforming.
- Entering triggers the Ape's scream; **the Ape chases the player**.
- Sounds: the arena fight opens with `ape_scream`; the cave chase uses `ape_scream_cave` (same cry, echoed). Both are synthesized in `scripts/sfx.gd`, 5 tones lower than the first draft.
- The chase replays one planned run (`ApeChase.plan` in `scripts/entities.gd`): the player's own movement code, off spikes and breakables, with the Ape's whole 24px contact box clear of the terrain. Breakable rock (low ceiling, hanging chunks): the player passes under it, the Ape smashes through (not saved, so it is back after a death).
- At a small gap the player hears the Ape hit the wall; rocks fall and seal the cave behind them. This starts the second part.
  Built: six breakable rocks (the low ceiling over the third pit and five hanging chunks) hurt the Ape as it smashes them (it blinks). The player only dies if the Ape gets past them: a tunnel-high line at its centre, so corners don't save you. Each landing shakes debris off the ceiling. The Ape itself triggers the end: reaching its last stretch (`end`), the ceiling caves in just ahead of it (`seal`), stopping it and sealing the way back for good.
- Reward on this path: **the sword** (see Energy for its costs).
- The sealed cave can't be re-entered, so the only way is right, to the shore.
- The shore offers two options:
  1. **Left: a mountain.** Clearly climbable, but beyond the player's current abilities. Hints that it can be climbed later; nothing else for now (maybe some collectibles).
  2. **Right: a raft** ("zattera") to reach the next island to the right.
- **Lighthouse:** next to the raft stands a big, primitive stone lighthouse. On top burns a magic flame, aimed in a single direction by mirrors.
- **Silent village** at the top of the lighthouse: 4-5 NPCs who answer every interaction with "...". One NPC gives a quest; the raft can't be used until the player has spoken to them.

**Left: jungle again → Treetop Village**
- The Ape screams and the jungle has to be crossed again.
- The player is caught by people with spears: a net on the floor snares them (needs a capture animation), and they are taken up into the trees.
- **Treetop level:** platforming matters most here.
- It starts with a **treetop village** where the player can't fall down.
- Bridges between platforms: moving, oddly behaving bridges (needs a flexible bridge entity).
- Reward on this path: **wall grab** (holding onto a vertical wall).
- Still open: where the player goes after the village (TODO).

## 2. Bosses

Every boss is a gimmick boss, mostly based on platforming.

### The Ape
- Size: about 4 units. Comes back to life (reanimates).
- The player dodges parabolic throws (like the Skeleton's), slime on the ground, and the scream.

Attacks, chosen by distance to the player:

| Attack | Range | Detail |
|---|---|---|
| Stone throw | far | Big stone: 2.5-unit sprite, 2x2-unit hitbox. Parabolic arc. |
| Slam | mid | Jumps and slams the ground. Overshoots on purpose (below). |
| Scream | near | Reaches 3 units around the Ape. |

Arena and collision:
- The tree obstacle, fallen-trunk bridge, bridge pit and tree-bait tutorial are removed.
  The former pit is filled with solid ground. The Ape uses one leap range across
  the arena (`range: [72, 568]`); there is no tree-dependent `range2` stage.
- Lure the Ape's overshooting leaps onto spikes. Three spike hits beat it;
  subsequent hits introduce more spike patches. Gates and the energy reward remain.
- Body contact uses 70% of the original width and height, rounded from 32 to
  **22×22 pixels**, centred inside the sprite's movement footprint. Three bands
  narrow the upper body around the head and shoulders; the head follows crouching.
  This is 70% per dimension, not 70% of area. Drawing and terrain movement retain
  the original 32×32 footprint, so boss placement and landing remain stable.
- The scream is an exact circle centred on the Ape, radius **40 pixels** (16px
  half-body + 24px reach). Collision uses the nearest point of the player's damage
  rectangle, so square corners are safe while an overlapping edge is still hit.
  Its 0.5s wind-up and 0.35s active window remain. Hitbox debug drawing uses the
  same body bands and circle; the scream animation stays inside its damage radius.

## 3. Energy

(Dropped: boss fights no longer drain energy.)

Energy is also health:
- It replaces hearts. The icon is still undecided; it shows as **blocks**.
- **1 block = 100 energy** in code. Every value below is in code units.
- In code now (scripts/adventure.gd; F3 in game shows it all live): the run starts with a **base of 25** that always regenerates (6/s). Each energy block picked up adds **10** (capacity and energy). A jump costs and needs 5. A hit is always a death and doesn't touch energy. Water drains 20.8/s and stops regeneration; 0 in water drowns. An energy orb refills to max (back after 2.5 s). Hair turns grey below 20%.
- With 1 block the player can use one ability, then has to rest before using another.
- The 2nd block comes from the first city.

More energy unlocks more abilities:

| Energy | Unlocks |
|---|---|
| some | jump about 10% higher |
| more | attack |
| more again | the cool abilities (some need even more) |

The thresholds aren't set yet.

Costs:
- Sword: needs 2 blocks (200) to be used at all.
- Sword swing: 10 per swing.
- Sword hit: 15 more per enemy hit (25 for a swing that lands). Swing only when you mean it.
- Wall grab: 20-30 per second while holding on.
- Jump: 5 per jump, and a jump needs those 5: with less there's no jump (wall jumps and swim strokes stay free).
- Some abilities cost a whole block and have to be recovered before reuse.

Regeneration:
- 6 energy per second (doubled from 3 on 2026-10-24).
- The base (the first 50) always refills, even from 0.
- Above it, only inside the current block: an extra block that is fully spent doesn't refill.

Water:
- Underwater is its own state, **Normal (Underwater)**, which replaces Normal in water: slow sinking, no walking on the floor (along it the player moves as mid-water), and no normal jump. **Jumping (Underwater)** is a weaker stroke (about half a jump's height) that works from the floor or mid-water, every time jump is pressed; with the surface close above, it leaps out of the water like a normal jump. Dash still works.
- Waterfalls are a layer on top of the current state: inside one the player is pulled down, so jumps rise much less.
- Staying in water costs 2.08 energy every 0.1 s (20.8 per second), and energy doesn't regenerate there.
- Running out of energy in water is a death (drowning).

## 4. Skill points

- Every village has at least one quest that rewards a skill point.
- Skill points go into regeneration, damage, speed and other stats.
- Later, active abilities can be bought with them too.

## 5. Systems the story needs

- **NPCs:** scripts don't exist yet. Needed: dialogue, a talk button, the "..." reply, quest flags (the raft needs the quest NPC).
- **Interact button:** none exists yet.
- **Positional audio:** a stereo engine where sounds attach to sprites and pan by position (enemy on the right → heard on the right). Above and below are harder; research how other games fake height (HRTF or elevation cues) before building.
- **New content:** leaf platforms, forest environment theme, waterfall blocks, moving bridges, breakable sand platforms, net capture animation, raft, lighthouse.

## 6. Built so far

`worlds/story/` (Adventure menu → World: Story), 18 rooms, jump only:
Meadow → The Big Jump (fall into the gap) → Lake Cave → Cave Teeth → Cove Tunnel → Cove Town (energy block on a roof).
Lake Cave has neighbours of its own: Roar Tunnel on the left (dead end, the roar), and Deep Lake below. A hole in the lake floor drops into Deep Lake (flooded, a star in the corner), and a shaft of jump-through platforms climbs back up into Lake Cave.
Right of Cove Town the jungle (forest theme) runs Jungle Edge → (drop) → Jungle Falls → Jungle Hills, with leaf platforms, a waterfall over a lake, hollow trunks, tunnel hills and calm Mosstrots. A star sits at the top of each leaf climb.
Past the jungle: the Ape Arena, with the fight built (see section 2: open arena, four spike hits, gated exits), then the fork. Right: Sand Cave (a climb at about 25°, crumble blocks for breakable sand) → Shore (the mountain's foot, the sea, the lighthouse) → (its door) Lighthouse Stairs → Lighthouse Top (the silent village). Left: a hole in the arena floor → Jungle Depths → Net Trap (a door stands in for the net lift) → Treetop Village above the arena.
Roar Tunnel plays a one-shot stereo roar from the left, with cave reflections. NPCs, quests, the chase, the rock fall, the raft and the rewards (sword, wall grab) are notes in the rooms for now.
`tools/story/gen_first_stretch.py` generates these rooms, but only the rooms you name (`... worlds/story a1_ape_arena`, or `all`), since rooms are also edited in-game.
`tests/test_runner.gd` runs a jump-only bot from the meadow to the end of the jungle.

## 7. Decisions

- 2026-10-24: the story world starts with **jump only**. Dash, climb and attack are adventure abilities unlocked by orbs (`Game.has_ability`).
- 2026-10-24: the big jump gets nothing for now. It stays uncrossable until dash comes from a later level.
- 2026-10-24: water drains energy (0.05 every 0.1 s, no regeneration in water); out of energy in water = death.
- 2026-10-24: water drain raised 10x, to 0.5 every 0.1 s (5 per second).
- 2026-10-24: water drain doubled to 1 every 0.1 s (10 per second); the waterfall pull is softer (jumps rise, less).
- 2026-10-24: water drain doubled again, to 2 every 0.1 s (20 per second).
- 2026-10-24: water drain set to 80% of that: 1.6 every 0.1 s (16 per second). No energy, no jump. Jump cost lowered to 5.
- 2026-10-24: water drain raised 30%, to 2.08 every 0.1 s (20.8 per second).
- 2026-10-24: an energy block adds 75 (was 100); a hit still costs 100.
- 2026-10-24: waterfall blocks (my reading of the brief): falling water the player can walk through but not jump up; it pushes them down.
- 2026-10-24 (superseded by tree removal below): Ape arena reworked: you meet the Ape first, on your side of the pit. Get past it, stand past the tree, and its stone or leap fells the tree across the pit; it follows you over for the spike phase.
- 2026-10-24 (tree setup superseded below): Ape fight built. Walking past the trunk wakes it; standing behind the trunk baits the stone that fells it. Stones are 2x2 units with the sprite the same size as the hitbox. Exits are sealed until it's beaten; afterwards energy drops to 5 and an energy orb appears. The power-up reward is still open.
- 2026-10-24: the run starts with a base of 50 energy that always regenerates; energy blocks add 100 each. A jump needs its 5.
- 2026-10-24: Ape arena 70% as wide (56 tiles); entering, the player is walked off the ledge into it and the entrance shuts until the Ape is beaten. Sand Cave, Shore and Lighthouse Top moved 24 tiles left to stay attached.
- 2026-10-24: the lighthouse reworked: a solid tower on the shore with a house door at its foot, an inside room (Lighthouse Stairs, two screens of zigzag platforms) and a door at the top onto the gallery where the silent village is.
- 2026-10-24: Cove Town's houses open: house doors (stand at one, press up) lead to the Villager's House and the Quest Giver's House, where the NPCs will live (notes for now).
- 2026-10-24: the death counter counts every respawn, including hits that only cost a spare block.
- 2026-10-24: energy built first. A hit with a block to spare costs the block and respawns the player at the room's spawn, like Hollow Knight's hazard respawn; the last block is a death and refills energy.

- 2026-10-24: the Ape's contact hitbox is one rectangle, 24x24 centred (a bit larger than the head-contour bands it replaced).
- 2026-10-24: Removed the arena tree puzzle and bridge pit, unified the leap range, reduced body-contact bounds to 22×22 with a head contour, and made scream collision circular (40px radius).

## 8. Open questions

1. Which later level gives dash, so the big jump (section 1.2) can be crossed.
2. Energy thresholds for each unlock (+10% jump, attack, abilities).
3. Energy icon to use instead of hearts.
4. Where the Treetop Village leads.
5. How the two branches meet again, if they do.
6. Wall grab costs 20 or 30 per second?
7. How much energy collectibles restore (the energy orb refills everything for now).

