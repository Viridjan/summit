# Monster action library: monsters are built from one move, one or more attacks and traits picked at random.
# A monster is plain data, saved in the room like any entity:
#   {"t": "enemy_monster", "move": "patrol", "attacks": ["charge"], "traits": [], "tier": 0, "look": "enemy_hornback"}
# upgrade() adds one attack or trait and raises the tier (tier 1 = upgraded once, 2 = twice).
# ActionMonster (entities.gd) runs it.
extends RefCounted

# move -> label, walks on the ground?, art it can wear (EnemyArt kinds), base hit points
const MOVES := {
	"patrol": {"label": "walks its floor", "ground": true, "looks": ["enemy_mosstrot", "enemy_hornback", "enemy_skeleton"], "hp": 2},
	"hop": {"label": "hops along", "ground": true, "looks": ["enemy_cragjaw", "enemy_thornmite", "enemy_murkspore"], "hp": 3},
	"hover": {"label": "floats around its spot", "ground": false, "looks": ["enemy_bat", "enemy_fuzzbob", "enemy_skree"], "hp": 2},
}
# attack -> label, needs ground (true) / air (false) / either (null), reach in px
const ATTACKS := {
	"charge": {"label": "charges along the ground", "ground": true, "range": 120},
	"leap": {"label": "leaps at you", "ground": true, "range": 80},
	"shoot": {"label": "shoots a bolt", "ground": null, "range": 140},
	"lob": {"label": "lobs an arcing glob", "ground": null, "range": 110},
	"dive": {"label": "dives at you", "ground": false, "range": 100},
}
# traits = CombatEnemy variants (speed, warning, recovery, size; hit points in CombatEnemy.variant_hp)
const TRAITS := ["swift", "armored", "giant", "shielded", "brood", "venom"]

static func attacks_for(move: String) -> Array:
	return ATTACKS.keys().filter(func(a): return ATTACKS[a].ground == null or ATTACKS[a].ground == MOVES[move].ground)

# A new tier-0 monster: a random move, one attack it can use, a look that fits.
static func build(rng: RandomNumberGenerator) -> Dictionary:
	var move: String = MOVES.keys()[rng.randi() % MOVES.size()]
	var pool := attacks_for(move)
	var looks: Array = MOVES[move].looks
	return {"t": "enemy_monster", "move": move, "attacks": [pool[rng.randi() % pool.size()]], "traits": [], "tier": 0,
		"look": looks[rng.randi() % looks.size()]}

# The same monster one tier up: a new attack (if any is left) or a new trait, at random.
static func upgrade(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = m.duplicate(true)
	var new_attacks := attacks_for(out.move).filter(func(a): return a not in out.attacks)
	var new_traits := TRAITS.filter(func(t): return t not in out.traits)
	if not new_attacks.is_empty() and (new_traits.is_empty() or rng.randf() < 0.5):
		out.attacks.append(new_attacks[rng.randi() % new_attacks.size()])
	elif not new_traits.is_empty():
		out.traits.append(new_traits[rng.randi() % new_traits.size()])
	out.tier = int(out.get("tier", 0)) + 1
	return out

# One line for F2 and the editor: what it does.
static func describe(m: Dictionary) -> String:
	var parts: Array = [MOVES[m.move].label]
	for a in m.attacks:
		parts.append(ATTACKS[a].label)
	var s := ", ".join(parts)
	if not m.traits.is_empty():
		s += " [" + ", ".join(m.traits) + "]"
	return s + ("" if int(m.get("tier", 0)) == 0 else " (upgraded x%d)" % int(m.tier))

# A stable key for "the same monster" (counting, migration): everything but the position.
static func key(m: Dictionary) -> String:
	return "%s|%s|%s|%s" % [m.move, ",".join(m.attacks), ",".join(m.traits), m.get("look", "")]
