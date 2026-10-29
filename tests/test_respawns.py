import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import world_fixups as F


def room(rows):
    return {"name": "r", "w": len(rows[0]), "h": len(rows), "tiles": rows, "entities": []}


class Respawns(unittest.TestCase):
    def test_one_per_entry_on_the_floor(self):
        # a: 10x6 with a right doorway (rows 2..4) into b; c above b, joined by a roof opening (cols 3..5 of b)
        a = room(["1111111111", "1000000001", "1000000000", "1000000000", "1000000000", "1111111111"])
        b = room(["1110001111", "1000000001", "0000000001", "0000000001", "0000000001", "1111111111"])
        c = room(["1111111111", "1000000001", "1000000001", "1000000001", "1000000001", "1110001111"])
        with tempfile.TemporaryDirectory() as d:
            for n, r in (("a", a), ("b", b), ("c", c)):
                json.dump(r, open(os.path.join(d, n + ".json"), "w"))
            json.dump({"start": "a", "rooms": {"a": [0, 6], "b": [10, 6], "c": [10, 0]}}, open(os.path.join(d, "world.json"), "w"))
            errors = F.add_respawns(d)
            got = {n: [(e["x"] // 8, e["y"] // 8) for e in json.load(open(os.path.join(d, n + ".json")))["entities"] if e["t"] == "respawn"]
                   for n in "abc"}
        self.assertEqual(got["a"], [(8, 4)])  # side entry: 1 tile in from the edge, on the floor under its lowest row
        self.assertIn((1, 4), got["b"])  # b's left entry
        self.assertIn((4, 4), got["b"])  # b's roof entry: its middle column, first floor below
        self.assertEqual(got["c"], [])  # c's floor opening: no floor above it on that column...
        self.assertEqual(len(errors), 1)  # ...so an error instead
        self.assertIn("c: bottom entry", errors[0])


if __name__ == "__main__":
    unittest.main()
