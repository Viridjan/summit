# Adding a power-up or interactable

Every level object is one class in `scripts/entities.gd` plus one line in its `TYPES` registry.
The world, editor palette, level validation, map view and the generic tests all read that registry,
so nothing else needs to list the new type.

New adventure ability? Add its name to `Adventure.ABILITIES` (`scripts/adventure.gd`), a row
`"ability_<name>": [label, false, color, AbilityOrb]`, and gate the move with `Game.has_ability("<name>")`
in `player.gd` (see the dash/climb checks at the top of `Player.update`). Ideas and patterns: `docs/METROID_NOTES.md`.

## 1. Decide what it is

| Kind | Flags in `setup()` | World list | Player interaction |
|---|---|---|---|
| Pickup / trigger (crystal, feather, bubble) | none | `touchables` | `touch(p)` when the hurtbox overlaps `touch_rect()` |
| Hazard | none (add to `spikes` only if it should kill on landing like spikes) | `touchables` | `touch(p)` calls `p.die(dir)` |
| Solid block (crumble, zip mover) | `solid = true` | `solids` | collision; move it with `move_by()` to carry/push the player |
| Platform you can jump up through | `jumpthru = true` | `jumpthrus` | one-way collision |

`World._build()` sorts entities into these lists from the flags; don't edit world.gd for this.

## 2. Write the class (`scripts/entities.gd`)

```gdscript
class SpeedRing extends Ent:
	var t := 0.0
	func setup() -> void:
		rect = Rect2i(rect.position.x - 4, rect.position.y - 4, 16, 16)  # hitbox around the 8px cell
	func update(dt: float) -> void:
		t += dt
		if respawn > 0:
			respawn -= dt
	func touch(p) -> void:
		if respawn <= 0:
			p.speed.x = 240.0 * p.facing
			respawn = 1.0
			w.burst(center(), Color("60e0ff"), 8)
	func draw(ci: CanvasItem) -> void:
		var col := Color("60e0ff") if respawn <= 0 else Color(0.3, 0.3, 0.4)
		ci.draw_arc(center() + Vector2(0, round(sin(t * 3))), 6, 0, TAU, 16, col, 1.5)
```

Rules (see the comment above `class Ent`):

- `setup()` and `draw()` must work with `w == null`; that is the editor preview.
- `update()` runs every tick even offscreen. Keep it cheap and deterministic; use `randi_range` only like the existing shake code.
- Draw inside `vis_rect()` (default: `rect` grown by 8 px). If the sprite can move away from `rect` (it follows the player, or has a rail), override `vis_rect()` like `Star` and `ZipMover`. Otherwise it vanishes at screen edges.
- Use the existing player and world hooks listed above `class Ent`. Don't write player internals from an entity unless you add a hook for it.

## 3. Register it

```gdscript
"speed_ring": ["Speed Ring", false, Color("60e0ff"), SpeedRing],
```

The fields are: editor label, `sized` (true means you drag a rectangle in the editor and `w`/`h` are saved), palette and map color, class.
The type id (`"speed_ring"`) is written into level JSON. Never rename it after levels use it; change the label instead (that's how `"strawberry"` became the Star).

## 4. If it needs a new player state

Only do this for something like a feather or a bubble, which takes over movement:

1. Add `ST_X` at the end of the `enum` in `player.gd` and a name at the same index in `STATE_NAMES`. The debug panel's state graph picks it up automatically.
2. Add an `_x_update(dt) -> int` branch to `_state_update()`, and begin/end handling to the two `match` blocks in `_set_state()`. Add it to the `co_active` list if it runs as a coroutine.
3. Put its numbers in `var UPPER_CASE` tunables next to the others. Add a prefix to `GROUPS` in `scripts/tuning.gd` so they appear in the F1 panel, and bump the tunable count in `tests/test_runner.gd`.
4. Expose an entry hook on the player, as `start_star_fly()` does, and call it from the entity's `touch()`.

## 5. Test it

You get these automatically, because `tests/test_runner.gd` runs them over every registered type:

- the type constructs in the world and in the editor
- `vis_rect()` covers `rect` and `touch_rect()`
- the registry row has the right shape
- a level containing the type survives save and load

`tests/smoke.tscn` places every type and runs/draws it.

Add one behavior test in `tests/test_runner.gd` with `make_world([...])`, `step(n)` and `check(...)`. Copy the "refill crystal" or "feather" tests as a starting point.

Run:

```sh
godot --headless --path . res://tests/test.tscn
godot --headless --path . res://tests/smoke.tscn
```

If the type draws a lot (big blocks, many particles), compare `godot --path . res://tests/bench.tscn` before and after adding it.

## Connected special-block artwork

Breakable walls, crumble/falling blocks, zip movers, dream blocks and jump-throughs
use `BlockArt` (`scripts/block_art.gd`). Call `BlockArt.draw(ci, rect, style, shake,
damage)` with the full entity rectangle; do not call it once per 8px tile. It draws
a single perimeter with connected end caps/corners and internal material grain.
The image is generated at the exact world size and shared between matching pieces.
Keep pieces separate when they have independent destruction or movement behaviour.
See `assets/blocks/preview.html` for the styles, sizes and breakable-wall damage.

## Adding an enemy or a variant

Enemies extend `CombatEnemy` in `scripts/entities.gd`; see `docs/ENEMIES.md`.

- **New family:** add one class plus one `"enemy_<family>"` row in `TYPES`, then add its sprite to `SPRITES` in `scripts/enemy_art.gd`.
- **Variant of an existing family:** add a `"enemy_<family>_<variant>"` row in `TYPES` (same class), using a variant from `CombatEnemy.VARIANTS`.

In both cases, also:
1. Add the type id to `EnemyArt.KINDS` in the same order as `TYPES`; a test checks they match.

A brand-new variant needs:
- a `VARIANTS` entry for its speed, warning, recovery and scale;
- `variant_hp()`, if it changes HP;
- a palette in `EnemyArt.TINTS`.

### Contoured and circular damage areas

`Ent.touch_rect()` remains the broad contact bound. The Ape verifies contact
against `body_boxes()` inside `touch()` (for the Ape: one centred 24px square, smaller than its 32px sprite);
its debug body overlay displays the same bands. `damage_boxes()` exposes rectangular
extra attacks. `damage_circles()` returns `[centre, radius]` entries for the hitbox
overlay; circular attacks must also use their matching geometric collision check
(the Ape's `scream_hits()` uses circle-versus-player-rectangle distance).
