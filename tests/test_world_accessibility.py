"""Small deterministic maps that exercise the offline accessibility checker."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from world_accessibility import Audit, main
from check_side_openings import audit as audit_sides


class AccessibilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def world(self, rooms, positions=None):
        positions = positions or {name: [i * 10, 0] for i, name in enumerate(rooms)}
        (self.root / "world.json").write_text(json.dumps({"start": "a", "rooms": positions}))
        for name, (tiles, entities) in rooms.items():
            if name == "a":
                entities = [{"t": "spawn", "x": 16, "y": 16}] + entities
            (self.root / (name + ".json")).write_text(json.dumps({"name": name, "w": len(tiles[0]), "h": len(tiles), "tiles": tiles, "entities": entities}))
        return Audit(self.root)

    def test_disconnected_rooms_and_directed_doors(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        audit = self.world({"a": (tiles, []), "b": (tiles, [])})
        self.assertEqual(audit.run()["models"]["topology"]["unreached_rooms"], ["b"])
        audit = self.world({
            "a": (tiles, [{"t": "door", "id": "out", "to": "b:in", "x": 24, "y": 8, "w": 8, "h": 16}]),
            "b": (tiles, [{"t": "door", "id": "in", "to": "in", "x": 24, "y": 8, "w": 8, "h": 16}]),
        })
        result = audit.run()
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["models"]["standing"]["rooms_reached"], 2)

    def test_one_tile_passage_needs_crouch(self):
        # Adjacent rooms share a one-tile-high edge opening.
        a = ["1111111", "1000001", "1000000", "1000001", "1111111"]
        b = ["1111111", "1000001", "0000001", "1000001", "1111111"]
        result = self.world({"a": (a, []), "b": (b, [])}, {"a": [0, 0], "b": [7, 0]}).run()
        self.assertEqual(result["models"]["hazards"]["rooms_reached"], 2)
        self.assertEqual(result["models"]["standing"]["unreached_rooms"], ["b"])

    def test_acid_barrier_and_partial_regions(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        result = self.world({"a": (tiles, [{"t": "acid", "x": 24, "y": 8, "w": 8, "h": 24}])}).run()
        self.assertEqual(result["models"]["topology"]["partial_rooms"], [])
        self.assertEqual(result["models"]["acid"]["partial_rooms"], ["a"])
        self.assertEqual(result["models"]["acid"]["rooms"]["a"]["unreached_sample_local_tile"], [4, 1])

    def test_spikes_distinguished_from_acid(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        result = self.world({"a": (tiles, [{"t": "spikes_up", "x": 24, "y": 8, "w": 8, "h": 24}])}).run()
        self.assertEqual(result["models"]["acid"]["partial_rooms"], [])
        self.assertEqual(result["models"]["hazards"]["partial_rooms"], ["a"])

    def test_invalid_door_is_reported(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        result = self.world({"a": (tiles, [{"t": "door", "id": "bad", "to": "missing:door", "x": 8, "y": 8}])}).run()
        self.assertIn("missing target", result["errors"][0])

    def test_negative_world_coordinates(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        result = self.world({"a": (tiles, [])}, {"a": [-10, -10]}).run()
        self.assertEqual(result["spawn_tile"], (-8, -8))
        self.assertTrue(result["models"]["standing"]["spawn_valid"])

    def test_cli_strict_status_and_artifacts(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        self.world({"a": (tiles, []), "b": (tiles, [])})
        output = self.root / "results" / "audit"
        with patch.object(sys, "argv", ["world_accessibility.py", str(self.root), "--output", str(output), "--strict", "topology"]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 1)
        self.assertTrue(Path(str(output) + ".md").exists())
        self.assertEqual(Path(str(output) + ".png").read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(json.loads(Path(str(output) + ".json").read_text())["room_count"], 2)

    def test_spawn_outside_room_rejected(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        self.world({"a": (tiles, [])})
        path = self.root / "a.json"
        level = json.loads(path.read_text())
        level["entities"][0]["x"] = -800
        path.write_text(json.dumps(level))
        with self.assertRaisesRegex(ValueError, "spawn is outside"):
            Audit(self.root)

    def test_side_opening_into_void_is_grouped(self):
        tiles = ["1111111", "0000001", "0000001", "1000001", "1111111"]
        self.world({"a": (tiles, [])})
        result = audit_sides(self.root)
        self.assertEqual(len(result["findings"]), 1)
        opening = result["findings"][0]
        self.assertEqual((opening["reason"], opening["side"]), ("no_adjacent_room", "left"))
        self.assertEqual((opening["y_start_px"], opening["y_end_px_exclusive"]), (8, 24))

    def test_side_opening_distinguishes_wall_and_valid_exit(self):
        a = ["1111111", "1000000", "1000000", "1000001", "1111111"]
        b = ["1111111", "1000001", "0000001", "1000001", "1111111"]
        self.world({"a": (a, []), "b": (b, [])}, {"a": [0, 0], "b": [7, 0]})
        result = audit_sides(self.root)
        self.assertEqual(len(result["findings"]), 1)
        opening = result["findings"][0]
        self.assertEqual((opening["source"], opening["target"], opening["reason"]), ("a", "b", "neighbour_wall"))
        self.assertEqual((opening["y_start_px"], opening["y_end_px_exclusive"]), (8, 16))

    def test_overlap_rejected(self):
        tiles = ["1111111", "1000001", "1000001", "1000001", "1111111"]
        with self.assertRaisesRegex(ValueError, "overlapping"):
            self.world({"a": (tiles, []), "b": (tiles, [])}, {"a": [0, 0], "b": [0, 0]})


if __name__ == "__main__":
    unittest.main()
