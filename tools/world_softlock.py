# Softlock check: at each progression stage, every reachable standing spot must still reach the next pickup.
# Usage: python3 tools/world_softlock.py adventure
import sys
from world_check import World, MODELS, explore

W = World(sys.argv[1])
m = MODELS["cautious"]
stages = [((), "ability_dash"), (("dash",), "ability_climb"), (("dash", "climb"), "goal")]
starts = [W.spawn]
ok = True
for ab, target in stages:
    ground, touched = explore(W, m, set(ab), starts)
    hits = [k for k in touched if k.startswith(target + ":")]
    if not hits:
        print(f"stage {ab}: {target} NOT reachable"); ok = False; break
    # standing spots from which the target can be touched: grow GOOD outward
    good, bad = set(), set()
    for g in sorted(ground):
        if g in good:
            continue
        if explore(W, m, set(ab), [g], goal=target, good=good):
            good.add(g)
        else:
            bad.add(g)
    rooms = {}
    for b in bad:
        rooms.setdefault(W.room_of.get(b), []).append(b)
    print(f"stage {ab or ('none',)} -> {target}: {len(ground)} spots, stuck spots: {len(bad)} {({r: len(v) for r, v in rooms.items()})}")
    for r, v in rooms.items():
        ox, oy, _ = W.rooms[r]
        print("   ", r, sorted((x - ox, y - oy) for x, y in v)[:12])
    ok = ok and not bad
    starts = [touched[hits[0]]]
print("SOFTLOCK-FREE" if ok else "PROBLEMS")
