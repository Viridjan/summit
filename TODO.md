# TODO

- [ ] Web version: install Godot export templates (~1 GB), add a Web export preset, export to HTML5, publish as a private claude.ai page so the game is playable from a link.
- [ ] Adventure backlog (hurt/knockback state, more abilities, event flags, ability gates, map stations, camera zones, room-transition polish, save slots, areas): see `docs/METROID_NOTES.md` section 6.
- [ ] Replace the three placeholder adventure rooms with real ones (World Editor).

## Story world: chapter 1
Design: `docs/STORY_DESIGN.md`. Systems first, since the rooms depend on them.

### Systems
- [x] Energy as health: blocks of 100, start with 1 block, a hit costs a block (hazard respawn), last block = death; regen 3/s inside the current block (`Adventure.*_energy`, HUD line, `energy_block` + `energy_orb` pickups)
- [x] Attack is an adventure ability (`ability_attack` orb); existing worlds list it in their start abilities
- [x] Story world starts with jump only (`worlds/story`, `"abilities": []`)
- [ ] Big wavedash jump is a later gate (needs dash): decide which later level gives dash
- [ ] Decide energy thresholds, then build the unlocks: +10% jump, attack, abilities
- [ ] Energy costs: sword needs 200, swing 10, hit +15 (`Adventure.spend_energy`); decide wall grab 20 or 30/s
- [ ] Energy orb refills everything for now; decide how much collectibles restore
- [ ] Decide the energy icon, then replace the HUD's "Energy n/m" text with blocks
- [ ] Interact button (keyboard, controller, touch)
- [ ] NPC entity + dialogue box; "..." reply for silent NPCs
- [ ] Quests and story flags (village quest gives a skill point; quest NPC unlocks the raft)
- [ ] Skill points: regeneration, damage, speed, other stats; active abilities later
- [ ] Positional stereo audio: sounds attached to sprites, panned by position
- [ ] Research height cues for audio (above/below; HRTF or elevation tricks) before building

### Content
- [ ] Forest environment theme
- [ ] Leaf platforms
- [ ] Waterfall blocks
- [ ] Breakable sand platforms
- [ ] Moving bridges between platforms (flexible)
- [ ] Net trap + capture animation
- [ ] Raft (needs the quest flag)
- [ ] Stone lighthouse with a mirror-aimed magic flame
- [ ] Wandering jungle enemy (walks back and forth, not aggressive)

### Rooms
- [x] Start meadow: flat, few jumps and spikes, no enemies (`m1_meadow`)
- [x] Big wavedash jump (cone shape, tip up); uncrossable at the start, comes back when dash is unlocked (`m2_big_jump`, star on the far side)
- [x] First lake and dark cave with dead-end tunnels (`c1_lake_cave`); roar is a note until positional audio exists
- [x] Cove or small city: 2nd energy block (`t1_cove_town`); the 2 NPCs and the quest are notes until NPCs exist
- [ ] Jungle: waterfall, lake, big trees and trunks, hills and tunnels, leaf platforms
- [ ] Ape boss arena: falling-trunk crossing, spikes that grow with each hit
- [ ] Right branch: 30° sand cave, Ape chase, rock fall seals it; sword reward
- [ ] Shore: unclimbable mountain to the left (hints, collectibles), raft to the right
- [ ] Lighthouse silent village (4-5 "..." NPCs, one quest NPC)
- [ ] Left branch: jungle again, net capture, treetop village (no falling), moving bridges; wall grab reward
- [ ] Treetop Village: decide where the player goes after it (exits, next area, whether the two branches meet again)

### Boss: the Ape
- [ ] Ape enemy, 4 units, reanimates
- [ ] Stone throw (far): parabolic, 2.5-unit sprite, 2x2 hitbox
- [ ] Slam (mid): jump that overshoots the player; safe when moving toward the Ape
- [ ] Scream (near): 3-unit reach
- [ ] Ground slime hazard
- [ ] Gimmick: thrown stone knocks a trunk down to cross the arena; 3-4 spike hits, more spikes after each
- [ ] Post-boss exhaustion: power-up, energy drained

## Power-ups from the reference games
One ability = one coded unit (player state/flag + orb/pickup entity + tuning vars + test), added methodically per
`docs/ADDING_ENTITIES.md`. Grouped by scope: items in a group share code, so build them together.
Sources: HK Hollow Knight, SS Silksong, SotN Symphony of the Night, MZM Metroid Zero Mission.
Dropped by choice: Space Jump, Screw Attack, bat/wolf/mist forms, Dreamgate, Morph Ball, Needolin music doors, Sylphsong, Beastling Call, Elegy of the Deep.
Gathered from fan wikis/guides (Oct 2026); recheck details before building.

### Already in Summit
- [x] Dash (HK Mothwing Cloak, SS Swift Step dash)
- [x] Wall cling, wall jump, climb (HK Mantis Claw, SS Cling Grip)
- [x] Melee attack (HK nail, SS needle)

### Direction upgrades (DASH_DIRS / ATTACK_DIRS, already tunable in F1)
Pickups that raise the value for the run and save it: 1 horizontal -> 2 four-way -> 3 eight-way -> 4 free aim.
- [ ] Dash direction upgrades: start horizontal only, unlock four-way, eight-way, free aim
- [ ] Attack direction upgrades: start horizontal only, unlock up/down (four-way), eight-way, free aim
- [ ] Vertical-only stage (-1) as an option for special rooms or challenges

### Movement: jumps (player jump code)
- [ ] Double jump (HK Monarch Wings, SS Faydown Cloak, SotN Leap Stone)
- [ ] High jump, passive: higher normal jump (MZM Hi-Jump)
- [ ] Super jump, active: vertical launch (SS Silk Soar, SotN Gravity Boots)
- [ ] Glide (SS Drifter's Cloak)

### Movement: dashes and speed (dash / run code)
- [ ] Charged long horizontal super dash (HK Crystal Heart); reuse the red-bubble dash
- [ ] Dash through enemies, invulnerable while dashing (HK Shade Cloak); needs enemies that hurt
- [ ] Sprint after a dash (SS Swift Step)
- [ ] Speed Booster: long run builds speed, breaks blocks; Shinespark: store it, launch in any direction (MZM)

### Movement: body shape and grabbing (collision code)
- [ ] Ledge hang and pull up (MZM Power Grip)
- [ ] Grapple to a target point (SS Clawline)

### Environment: liquids and hazards (liquid entities)
- [ ] Acid immunity (HK Isma's Tear)
- [ ] Move freely in water: swim / walk underwater (SotN Holy Symbol, MZM Gravity Suit)
- [ ] Heat / damage reduction (MZM Varia Suit)
- [ ] Ferry across water (SotN Merman Statue)

### Gates and keys (door / block entities)
- [ ] Coloured key doors: blue doors (SotN Jewel of Open), missile red/green doors (MZM)
- [ ] Hidden wall: looks like rock, walk through it and it fades to reveal a secret (HK, SotN, MZM)
- [ ] Hidden things revealed by a special hit (HK Dream Nail / Awoken Dream Nail)
- [ ] Bomb blocks and bomb jump (MZM Bombs); screen-wide blast (MZM Power Bombs)

### Combat base (needed by everything below)
- [ ] Player health + hurt/knockback (HK masks, MZM energy)
- [ ] Resource meter for skills (HK soul, SS silk), filled by hitting enemies
- [ ] Healing from the meter (HK Focus, SS bind)

### Combat: melee upgrades (attack layer)
- [ ] Hold attack to charge a strong strike (HK Nail Arts: Cyclone, Dash, Great Slash; SS Needle Strike)
- [ ] Downward slam that breaks floors (HK Desolate Dive / Descending Dark)
- [ ] Parry / counter (SS Cross Stitch)
- [ ] Area lash around the player (SS Thread Storm)
- [ ] Dash blade through enemies (SS Sharpdart)
- [ ] Attack damage upgrades (HK nail upgrades, SS needle upgrades)

### Combat: projectiles (new projectile entity)
- [ ] Forward projectile (HK Vengeful Spirit / Shade Soul, SS Silkspear)
- [ ] Upward blast (HK Howling Wraiths / Abyss Shriek)
- [ ] Homing projectiles (SS Pale Nails)
- [ ] Beams that stack: Long, Charge, Ice (freeze enemies into platforms), Wave (through walls), Plasma (pierce) (MZM)
- [ ] Missiles / Super Missiles with ammo (MZM)
- [ ] Stun gun, short sequence (MZM Zero Suit Paralyzer)
- [ ] Rune Rage (SS); check details

### Capacity pickups (save data)
- [ ] Extra health (HK Mask Shards, MZM Energy Tanks)
- [ ] Bigger meter (HK Vessel Fragments)
- [ ] Ammo tanks (MZM Missile, Super Missile, Power Bomb tanks)
- [ ] Stat boosts (SotN Dracula's relics: Heart, Tooth, Rib, Ring, Eye of Vlad)

### Loadout systems (menus + save)
Build order: one equip screen (at benches/save rooms) + slot rules, then the items one by one.
Most items need the combat base (health, meter) first; movement ones can come earlier.

#### Charms (HK): passives, each costs 1-4 notches; 3 notches at start, 11 max
- [ ] Charm system: equip screen, notch budget, overcharm (equip over budget, take double damage)
- Attack:
  - [ ] Quick Slash: faster attacks
  - [ ] Longnail: +reach; Mark of Pride: +more reach
  - [ ] Fragile / Unbreakable Strength: +50% attack damage (fragile breaks on death)
  - [ ] Fury of the Fallen: more damage at 1 health
  - [ ] Heavy Blow: more knockback on enemies; Steady Body: no recoil when hitting
  - [ ] Grubberfly's Elegy: attack fires a beam while at full health
  - [ ] Nailmaster's Glory: charge strikes faster
- Meter and skills:
  - [ ] Soul Catcher / Soul Eater: more meter per hit
  - [ ] Shaman Stone: stronger skills; Spell Twister: skills cost less
  - [ ] Flukenest: forward projectile becomes a spread of small flies
  - [ ] Grubsong: meter when hurt
- Healing:
  - [ ] Quick Focus: heal faster; Deep Focus: heal 2 at once, slower
  - [ ] Shape of Unn: move while healing; Baldur Shell: shield while healing
  - [ ] Spore Shroom: healing releases a damaging cloud
  - [ ] Hiveblood: slowly regenerate 1 health
- Defense and health:
  - [ ] Fragile / Unbreakable Heart: +2 health
  - [ ] Lifeblood Heart (+2), Lifeblood Core (+4): extra blue health that doesn't heal back
  - [ ] Joni's Blessing: more health, all blue, no healing
  - [ ] Stalwart Shell: longer invulnerability after a hit
  - [ ] Thorns of Agony: hurt enemies around you when hit
  - [ ] Defender's Crest: poison cloud around you
  - [ ] Dreamshield: orbiting shield
  - [ ] Carefree Melody: chance to block a hit
- Movement:
  - [ ] Dashmaster: shorter dash cooldown, downward dash
  - [ ] Sprintmaster: faster running
  - [ ] Sharp Shadow: dashing through enemies damages them
- Companions:
  - [ ] Glowing Womb: spend meter to spawn small attackers
  - [ ] Weaversong: three helper spiders
  - [ ] Grimmchild: flying fire companion
- Map and economy:
  - [ ] Wayward Compass: your position on the map
  - [ ] Gathering Swarm: picks up dropped currency
  - [ ] Fragile / Unbreakable Greed: more currency
  - [ ] Dream Wielder: faster Dream Nail
  - [ ] Kingsoul / Void Heart: meter over time, story charm

#### Crests (SS): replace the attack moveset and set the tool slots
- [ ] Crest system: swap at benches; each crest = attack shapes + slot layout
- [ ] Hunter: forward slash, bouncing lunge dash, down stab; 1 slot of each colour (starter)
- [ ] Reaper: heavy slow slash, wide arcing down attack
- [ ] Wanderer: fast short slashes, quick down pogo; 2 yellow + 1 red
- [ ] Beast: scratches up/forward, rolling air spin; 2 red (+2 yellow)
- [ ] Witch: wide slashes in 3 directions, double-swipe dash; 2 red (+3 blue)
- [ ] Architect: drill thrust, stab, charge, diagonal dive; 3 red (+2 blue, +2 yellow)
- [ ] Shaman: beam slashes, projectile dash, down beam; skill slots instead of tools

#### Tools (SS): red = active with limited charges (refill at benches), blue = passive combat, yellow = passive exploration
- [ ] Tool system: slots from the crest, charges, refill at benches
- Red, thrown or shot:
  - [ ] Straight Pin (forward), Threefold Pin (spread of 3), Longpin (heavy, pierces in an arc)
  - [ ] Curveclaw / Curvesickle (arcing throw), Throwing Ring (ricochets), Conchcutter (bounces off walls)
  - [ ] Silkshot (piercing beam), Rosary Cannon (shoots currency), Cogwork Wheel (rolling saw)
- Red, traps and bombs:
  - [ ] Pimpillo (contact bomb), Snare Setter (ground mine), Sting Shard (hanging trap), Tacks (floor spikes)
  - [ ] Voltvessels (lightning column), Delver's Drill (drill down into an enemy)
- Red, buffs and helpers:
  - [ ] Flea Brew (faster for 10 s), Flintslate (more damage for 8 s), Cogfly (flying helper)
  - [ ] Plasmium Phial / Needle Phial (extra health item)
- Blue, attack:
  - [ ] Volt Filament (+damage to skills), Longclaw (+20% reach), Pin Badge (faster charged strike)
  - [ ] Pollip Pouch (poison on hits), Claw Mirror(s) (burst after healing), Quick Sling (throw 2 tools at once)
- Blue, survival:
  - [ ] Fractured Mask (survive one lethal hit), Warding Bell (no damage while healing)
  - [ ] Injector Band (heal faster), Multibinder (heal more), Reserve Bind (one free heal)
  - [ ] Magma Bell (less fire/hazard damage), Wreath of Purity (immunity to one status), Memory Crystal (ice burst when hit)
- Blue, meter:
  - [ ] Spool Extender (bigger meter), Weavelight (meter regen), Druid's Eye(s) (meter when hurt)
  - [ ] Egg of Flealia (cheaper skills at full health), Wispfire Lantern (spends meter near enemies), Sawtooth Circlet (slash on cloak use)
- Yellow, movement:
  - [ ] Ascendant's Grip (wall cling holds longer), Silkspeed Anklets (faster sprint), Scuttlebrace (quick backstep), Weighted Belt (less knockback)
- Yellow, map and economy:
  - [ ] Compass (position on map), Magnetite Brooch (pulls pickups), Shard Pendant / Thief's Mark / Snitch Pick (more currency)
  - [ ] Dead Bug's Purse (keep half currency on death), Shell Satchel (more tool charges)
- Yellow, other:
  - [ ] Barbed Bracelet (+25% damage), Magnetite Dice (chance to block), Spider Strings (wider song range)

#### Familiars (SotN): companions that follow and fight, level up with use
- [ ] Familiar system: one active at a time, follows the player, gains levels
- [ ] Bat: attacks enemies, later fires
- [ ] Ghost: drains health from enemies
- [ ] Faerie: heals and revives
- [ ] Demon: attacks, presses switches
- [ ] Sword: flies and slashes; can be wielded as a weapon at high level

### UI helpers
- [ ] Item drops / damage numbers / enemy names (SotN Cube of Zoe, Spirit Orb, Faerie Scroll)
