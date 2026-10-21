"""Repeatable static accessibility audit; no Godot or third-party packages required.

This is a tile-connectivity test, NOT a physics solver. Movement has no gravity,
range or stamina limit. Crouching and standing use one/two tile clearance.
Acid/spikes cover full tiles, so hazard results are candidates for live testing.
"""
import argparse
from collections import deque
import json
import math
from pathlib import Path
import struct
import sys
import zlib

TILE = 8
MODELS = (
    ("topology", 1, ()),
    ("acid", 1, ("acid",)),
    ("hazards", 1, ("acid", "spikes")),
    ("standing", 2, ("acid", "spikes")),
)


def entity_cells(entity):
    """Tile footprint, rounded outward (deliberately conservative for hazards)."""
    for y in range(math.floor(entity["y"] / TILE), math.ceil((entity["y"] + entity.get("h", TILE)) / TILE)):
        for x in range(math.floor(entity["x"] / TILE), math.ceil((entity["x"] + entity.get("w", TILE)) / TILE)):
            yield x, y


class Audit:
    def __init__(self, directory):
        self.directory = Path(directory)
        manifest = json.loads((self.directory / "world.json").read_text())
        self.start = manifest["start"]
        self.abilities = manifest.get("abilities", [])
        self.rooms = {}
        for name, position in manifest["rooms"].items():
            if Path(name).name != name or name in (".", ".."):
                raise ValueError(f"Invalid room id: {name!r}")
            level = json.loads((self.directory / (name + ".json")).read_text())
            width, height = level["w"], level["h"]
            if not (0 < width <= 400 and 0 < height <= 400):
                raise ValueError(f"{name}: invalid room dimensions")
            if len(level["tiles"]) != height or any(len(row) != width or set(row) - {"0", "1"} for row in level["tiles"]):
                raise ValueError(f"{name}: invalid tile rows")
            if len(position) != 2 or any(not isinstance(p, int) for p in position):
                raise ValueError(f"{name}: position must be two integer tiles")
            self.rooms[name] = (position, level)
        if self.start not in self.rooms:
            raise ValueError("Start room does not exist")
        self.left = min(pos[0] for pos, _ in self.rooms.values()) - 1
        self.top = min(pos[1] for pos, _ in self.rooms.values()) - 1
        self.width = max(pos[0] + level["w"] for pos, level in self.rooms.values()) - self.left + 1
        self.height = max(pos[1] + level["h"] for pos, level in self.rooms.values()) - self.top + 1
        if self.width * self.height > 30_000_000:
            raise ValueError("World exceeds the audit's 30 million tile memory limit")
        self.terrain = bytearray(self.width * self.height)
        self.hazard = bytearray(len(self.terrain))
        self.errors = []
        self.doors = {}
        self.door_count = 0
        self.spawn = None
        occupied = bytearray(len(self.terrain))
        ids = {}
        for name, (pos, level) in self.rooms.items():
            for y, row in enumerate(level["tiles"]):
                start = self.index(pos[0], pos[1] + y)
                if any(occupied[start:start + level["w"]]):
                    raise ValueError(f"{name}: overlapping room rectangles are not supported")
                occupied[start:start + level["w"]] = bytes([1]) * level["w"]
                self.terrain[start:start + level["w"]] = bytes(c == "0" for c in row)
            for entity in level.get("entities", []):
                kind = entity["t"]
                if kind == "spawn" and name == self.start and self.spawn is None:
                    sx, sy = math.floor(entity["x"] / TILE), math.floor(entity["y"] / TILE)
                    if not (0 <= sx < level["w"] and 0 <= sy < level["h"]):
                        raise ValueError(f"{name}: spawn is outside the room")
                    self.spawn = (pos[0] + sx, pos[1] + sy)
                if kind == "acid" or kind.startswith("spikes_"):
                    for x, y in entity_cells(entity):
                        if 0 <= x < level["w"] and 0 <= y < level["h"]:
                            self.hazard[self.index(pos[0] + x, pos[1] + y)] |= 1 if kind == "acid" else 2
                if kind == "door":
                    self.door_count += 1
                    key = name, entity.get("id", "")
                    if not key[1] or key in ids:
                        self.errors.append(f"{name}: empty or duplicate door id {key[1]!r}")
                    ids[key] = entity
        if self.spawn is None:
            # Match World._build's default feet position when no spawn marker exists.
            pos, level = self.rooms[self.start]
            self.spawn = (pos[0] + level["w"] // 2, pos[1] + 1)
        for (name, door_id), entity in ids.items():
            target = entity.get("to", "")
            target_key = tuple(target.split(":", 1)) if ":" in target else (name, target)
            if target_key not in ids:
                self.errors.append(f"{name}:{door_id} -> missing target {target!r}")
                continue
            source = self._door_cells(name, entity)
            destination = self._door_cells(target_key[0], ids[target_key])
            if not source or not destination:
                self.errors.append(f"{name}:{door_id}: door has no cells inside its room")
            for cell in source:
                self.doors.setdefault(cell, set()).update(destination)
        self.masks = {}

    def index(self, x, y):
        return (y - self.top) * self.width + x - self.left

    def _door_cells(self, name, entity):
        pos, level = self.rooms[name]
        return [self.index(pos[0] + x, pos[1] + y) for x, y in entity_cells(entity)
                if 0 <= x < level["w"] and 0 <= y < level["h"]]

    def explore(self, name, body_rows, exclusions):
        blocked = (1 if "acid" in exclusions else 0) | (2 if "spikes" in exclusions else 0)
        free = bytearray(bool(t and not (h & blocked)) for t, h in zip(self.terrain, self.hazard))
        valid = free.copy()
        if body_rows == 2:
            for i in range(len(valid)):
                valid[i] = bool(free[i] and i >= self.width and free[i - self.width])
        portals = self.doors
        # Door contact may occur at the player's head as well as at its feet.
        if body_rows == 2:
            portals = {cell: set(targets) for cell, targets in self.doors.items()}
            for cell, targets in self.doors.items():
                if cell + self.width < len(valid):
                    portals.setdefault(cell + self.width, set()).update(targets)
        seen = bytearray(len(valid))
        start = self.index(*self.spawn)
        queue = deque()
        if valid[start]:
            queue.append(start)
            seen[start] = 1
        while queue:
            p = queue.popleft()
            # A solid one-tile border prevents row wrapping and out-of-range neighbours.
            for n in (p - 1, p + 1, p - self.width, p + self.width):
                if 0 <= n < len(valid) and valid[n] and not seen[n]:
                    seen[n] = 1
                    queue.append(n)
            # Optimistic arrival: any valid feet cell in the target doorway.
            for n in portals.get(p, ()):
                if valid[n] and not seen[n]:
                    seen[n] = 1
                    queue.append(n)
        rooms = {}
        for room, (pos, level) in self.rooms.items():
            total = reached = eligible = 0
            sample = None
            for y in range(level["h"]):
                start = self.index(pos[0], pos[1] + y)
                end = start + level["w"]
                total += sum(self.terrain[start:end])
                reached += sum(seen[start:end])
                eligible += sum(valid[start:end])
                if sample is None:
                    for x in range(level["w"]):
                        if valid[start + x] and not seen[start + x]:
                            sample = [x, y]
                            break
            rooms[room] = {
                "position_tiles": pos, "name": level.get("name", room),
                "open_tiles": total, "eligible_feet_cells": eligible, "reached_feet_cells": reached,
                "unreached_sample_local_tile": sample,
                "markers": [e["text"] for e in level.get("entities", []) if e["t"] == "note" and e.get("text")],
            }
        self.masks[name] = seen
        return {
            "body_rows": body_rows, "excluded_hazards": list(exclusions), "spawn_valid": bool(valid[self.index(*self.spawn)]),
            "rooms_reached": sum(s["reached_feet_cells"] > 0 for s in rooms.values()),
            "unreached_rooms": [r for r, s in rooms.items() if not s["reached_feet_cells"]],
            "partial_rooms": [r for r, s in rooms.items() if 0 < s["reached_feet_cells"] < s["eligible_feet_cells"]],
            "rooms": rooms,
        }

    def run(self):
        return {
            "world": str(self.directory), "start_room": self.start, "spawn_tile": self.spawn,
            "abilities": self.abilities, "room_count": len(self.rooms), "door_count": self.door_count,
            "errors": self.errors, "kind": "static_tile_connectivity_not_physics",
            "models": {name: self.explore(name, rows, hazards) for name, rows, hazards in MODELS},
        }

    def write_map(self, path):
        """Dependency-free PNG. Green: standing; blue: crouch-only; amber: hazard flag; red: disconnected."""
        raw = bytearray()
        for y in range(self.height):
            raw.append(0)  # PNG scanline filter: none
            for x in range(self.width):
                i = y * self.width + x
                color = (18, 25, 38)
                if self.terrain[i]:
                    color = ((83, 180, 158) if self.masks["standing"][i] else
                             (94, 159, 224) if self.masks["hazards"][i] else
                             (236, 174, 64) if self.masks["topology"][i] else (227, 83, 100))
                raw.extend(color)
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def markdown(report):
    lines = ["# World accessibility audit", "", f"World: `{report['world']}`. Start: `{report['start_room']}`. "
             f"{report['room_count']} rooms; {report['door_count']} door entities.", "",
             "This is a static connectivity test, **not a physics playthrough**. It ignores gravity, jump/dash reach, stamina, "
             "and return paths. Crouch models allow a one-tile body everywhere; standing requires two vertical tiles "
             "(conservative for the actual 8×11px hitbox). Breakable walls are assumed broken. Hazard rectangles are rounded "
             "outward to tiles; spikes are treated as lethal from every direction. Doors allow any valid target tile, "
             "rather than reproducing the runtime arrival offset. No enemies or moving entities are simulated, and temporary travel above room tops is omitted. "
             "Results identify routes to investigate; neither green cells nor flagged rooms establish live traversability.", "",
             "Map: green = standing model; blue = crouch model only; amber = topology only; red = disconnected even without hazards.", "",
             "| Model | Reached rooms | Unreached rooms |", "|---|---:|---|"]
    for name, model in report["models"].items():
        missing = ", ".join(f"`{r}`" for r in model["unreached_rooms"]) or "None"
        lines.append(f"| {name} | {model['rooms_reached']}/{report['room_count']} | {missing} |")
    if report["errors"]:
        lines += ["", "## Invalid doors", ""] + [f"- {error}" for error in report["errors"]]
    lines += ["", "## Rooms flagged by hazard or standing models", "", "| Room | World tile origin | Markers | Flags |", "|---|---|---|---|"]
    for room, info in report["models"]["topology"]["rooms"].items():
        flags = [name for name, model in report["models"].items() if room in model["unreached_rooms"]]
        if flags:
            markers = "; ".join(info["markers"]).replace("|", "\\|") or "—"
            lines.append(f"| `{room}` | {info['position_tiles']} | {markers} | {', '.join(flags)} |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("world", nargs="?", default="worlds/hollow_knight", type=Path)
    parser.add_argument("--output", type=Path, default=Path("reports/world-accessibility"), help="Output filename prefix")
    parser.add_argument("--strict", choices=[m[0] for m in MODELS], help="Exit 1 if this model flags unreached rooms, partial regions, or invalid spawn")
    args = parser.parse_args()
    try:
        audit = Audit(args.world)
        report = audit.run()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        Path(str(args.output) + ".json").write_text(json.dumps(report, indent=2) + "\n")
        Path(str(args.output) + ".md").write_text(markdown(report))
        audit.write_map(Path(str(args.output) + ".png"))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Audit failed: {exc}", file=sys.stderr)
        return 2
    for name, model in report["models"].items():
        print(f"{name:10} {model['rooms_reached']}/{report['room_count']} rooms; "
              f"{len(model['partial_rooms'])} partial; spawn {'OK' if model['spawn_valid'] else 'BLOCKED'}")
        if model["unreached_rooms"]:
            print("  Unreached: " + ", ".join(model["unreached_rooms"]))
    print(f"Reports: {args.output}.{{md,json,png}}")
    if report["errors"]:
        print("\n".join(report["errors"]), file=sys.stderr)
        return 2
    if args.strict:
        model = report["models"][args.strict]
        if model["unreached_rooms"] or model["partial_rooms"] or not model["spawn_valid"]:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
