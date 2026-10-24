# Tile-level reachability checker for the adventure world.
# Player = 1 column x 2 rows, (x, y) = feet cell. Two movement models:
#   cautious : a bit weaker than the real player -> "reachable" claims are safe
#   generous : a bit stronger than the real player -> "unreachable" (gate) claims are safe
# Usage: python3 tools/world_check.py adventure     (softlocks: python3 tools/world_softlock.py adventure)
import json, sys, os
from collections import deque

T = 8
MODELS = {
    "cautious": dict(jump=3, hover=1, dash=4, dash_carry=1, drift_every=2, drift_free=3, stam=12, wj_lock=2, climb_jump=False),
    "generous": dict(jump=4, hover=2, dash=5, dash_carry=3, drift_every=1, drift_free=99, stam=99, wj_lock=1, climb_jump=True),
}


class World:
    def __init__(self, d):
        w = json.load(open(os.path.join(d, "world.json")))
        self.start = w["start"]
        self.rooms = {}
        for name, pos in w["rooms"].items():
            lvl = json.load(open(os.path.join(d, name + ".json")))
            self.rooms[name] = (pos[0], pos[1], lvl)
        self.solid, self.plat, self.spike, self.items = set(), set(), set(), {}
        self.inside = set()
        self.room_of = {}
        for name, (ox, oy, lvl) in self.rooms.items():
            for y, row in enumerate(lvl["tiles"]):
                for x, c in enumerate(row):
                    p = (ox + x, oy + y)
                    self.inside.add(p)
                    self.room_of[p] = name
                    if c == "1":
                        self.solid.add(p)
            for e in lvl["entities"]:
                ex, ey = ox + int(e["x"]) // T, oy + int(e["y"]) // T
                t = e["t"]
                if t in ("jumpthru", "leaf"):
                    for i in range(int(e["w"]) // T):
                        self.plat.add((ex + i, ey))
                elif t.startswith("spikes_"):
                    self.spike.add((ex, ey))
                elif t in ("ability_dash", "ability_climb", "goal", "strawberry", "refill"):
                    self.items.setdefault((ex, ey), []).append((t, name, e))
                elif t == "spawn" and name == self.start and not hasattr(self, "spawn"):
                    self.spawn = (ex, ey)
        # the player may rise up to 3 tiles (24px) above a room's top edge (Player._enforce_bounds)
        for name, (ox, oy, lvl) in self.rooms.items():
            for x in range(lvl["w"]):
                if lvl["tiles"][0][x] == "0":
                    for dy in (1, 2, 3):
                        p = (ox + x, oy - dy)
                        if p not in self.room_of:
                            self.inside.add(p)

    def S(self, x, y):
        return (x, y) in self.solid or (x, y) not in self.inside

    def free(self, x, y):
        return not self.S(x, y) and not self.S(x, y - 1)

    def dead(self, x, y):
        return (x, y) in self.spike or (x, y - 1) in self.spike

    def support(self, x, y):
        return self.S(x, y + 1) or (x, y + 1) in self.plat


def explore(W, m, abilities, starts, goal=None, good=None):
    """BFS over (x, y, mode, k, dash, lock, stam). Returns visited ground cells and items touched."""
    has_dash, has_climb = "dash" in abilities, "climb" in abilities
    full_stam = m["stam"] if has_climb else 0
    seen = set()
    q = deque()
    ground = set()
    touched = {}

    def push(s):
        x, y = s[0], s[1]
        if not W.free(x, y) or W.dead(x, y):
            return
        if s in seen:
            return
        seen.add(s)
        q.append(s)

    for (x, y) in starts:
        push((x, y, "G", 0, 1, 0, full_stam))
    while q:
        s = q.popleft()
        x, y, mode, k, dash, lock, stam = s
        for c in ((x, y), (x, y - 1)):
            for it in W.items.get(c, ()):
                touched.setdefault(it[0] + ":" + it[1] + ":%d,%d" % c, (x, y))
                if goal and it[0] == goal:
                    return True
                if it[0] == "refill":
                    dash = 1
        if mode == "G":
            if not W.support(x, y):
                push((x, y, "F", 0, dash, 0, stam))
                continue
            if good is not None and (x, y) in good:
                return True
            ground.add((x, y))
            dash, stam = 1, full_stam
            for dx in (-1, 1):
                if W.free(x + dx, y):
                    push((x + dx, y, "G", 0, 1, 0, stam))
            push((x, y, "U", m["jump"], 1, 0, stam))
        air = mode in ("U", "H", "F")
        # dash (any state, once per airtime)
        if has_dash and dash:  # Celeste lets you dash out of a climb too
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    cx, cy = x, y
                    ok = True
                    for _ in range(m["dash"]):
                        nx, ny = cx + dx, cy + dy
                        if not W.free(nx, ny) or (dx and dy and (not W.free(cx + dx, cy) or not W.free(cx, cy + dy))):
                            break
                        if W.dead(nx, ny):
                            ok = False
                            break
                        cx, cy = nx, ny
                    if ok and (cx, cy) != (x, y):
                        nd = 1 if any(i[0] == "refill" for c in ((cx, cy), (cx, cy - 1)) for i in W.items.get(c, ())) else 0
                        if dy < 0 and dx == 0:
                            push((cx, cy, "H", m["hover"], nd, 0, stam))
                        else:
                            push((cx, cy, "F", 0, nd, (m["dash_carry"] * dx) if dx else 0, stam))
        if air or mode == "C":
            # wall jump / grab
            for side in (-1, 1):
                if W.S(x + side, y - 1) or W.S(x + side, y):
                    # wall jump: pushed away for the whole rise (no climbing a single wall by wall jumps)
                    push((x, y, "U", m["jump"], dash, -side * (m["jump"] + m["hover"]), stam))
                    if has_climb and W.S(x + side, y - 1) and stam > 0 and mode != "C":
                        push((x, y, "C", side, dash, 0, stam))
        if mode == "U":
            dxs = (lock // abs(lock),) if lock else (-1, 0, 1)
            nl = lock - (1 if lock > 0 else -1) if lock else 0
            for dx in dxs:
                nx = x + dx if W.free(x + dx, y) else x
                if W.free(nx, y - 1):
                    push((nx, y - 1, "U" if k > 1 else "H", k - 1 if k > 1 else m["hover"], dash, nl, stam))
                else:
                    push((nx, y, "H", 0, dash, nl, stam))
        elif mode == "H":
            dxs = (lock // abs(lock),) if lock else (-1, 0, 1)
            nl = lock - (1 if lock > 0 else -1) if lock else 0
            for dx in dxs:
                nx = x + dx if W.free(x + dx, y) else x
                if k > 1:
                    push((nx, y, "H", k - 1, dash, nl, stam))
                else:
                    push((nx, y, "F", 0, dash, nl, stam))
        elif mode == "F":
            if W.support(x, y):
                push((x, y, "G", 0, dash, 0, stam))
                continue
            can_drift = k < m["drift_free"] or k % m["drift_every"] == 0
            dxs = (lock // abs(lock),) if lock else ((-1, 0, 1) if can_drift else (0,))
            nl = lock - (1 if lock > 0 else -1) if lock else 0
            for dx in dxs:
                nx = x + dx if W.free(x + dx, y) and W.free(x + dx, y + 1) else x
                if W.free(nx, y + 1):
                    nk = k + 1  # only the drift pattern matters: fold the counter into a short cycle
                    if m["drift_every"] == 1:
                        nk = min(nk, m["drift_free"], 1)
                    elif nk >= m["drift_free"] + 2:
                        nk -= 2
                    push((nx, y + 1, "F", nk, dash, nl, stam))
        elif mode == "C":
            side = k
            if not W.S(x + side, y - 1):
                continue
            if W.support(x, y) and (x, y + 1) in W.plat:
                push((x, y, "G", 0, dash, 0, stam))
            push((x, y, "F", 0, dash, 0, stam))  # let go
            if m["climb_jump"] and stam > 3:
                push((x, y, "U", m["jump"], dash, 0, stam - 3 if stam < 99 else stam))
            if stam > 0:
                if W.S(x + side, y - 2):
                    if W.free(x, y - 1):
                        push((x, y - 1, "C", side, dash, 0, stam - 1 if stam < 99 else stam))
                elif W.free(x + side, y - 2) and W.free(x, y - 1):
                    push((x + side, y - 2, "G", 0, dash, 0, stam))  # climb hop over the top
            if W.free(x, y + 1) and W.S(x + side, y):
                push((x, y + 1, "C", side, dash, 0, stam))
    if goal:
        return False
    return ground, touched


def rooms_of(W, cells):
    out = {}
    for c in cells:
        r = W.room_of.get(c)
        out[r] = out.get(r, 0) + 1
    return out


def report(W, name, ground, touched):
    rs = rooms_of(W, ground)
    print(f"  [{name}] rooms reached: {len(rs)}/{len(W.rooms)}  missing: {sorted(set(W.rooms) - set(rs))}")
    kinds = {}
    for key in touched:
        kinds.setdefault(key.split(':')[0], []).append(key.split(':', 1)[1])
    for k in sorted(kinds):
        print(f"    {k}: {sorted(kinds[k])}")


if __name__ == "__main__":
    W = World(sys.argv[1])
    for model in ("cautious", "generous"):
        m = MODELS[model]
        print(f"== {model}")
        for ab in ((), ("dash",), ("climb",), ("dash", "climb")):
            g, t = explore(W, m, set(ab), [W.spawn])
            report(W, "+".join(ab) or "none", g, t)
