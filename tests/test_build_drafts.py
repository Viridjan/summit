import json, os, subprocess, sys, tempfile, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
from world_check import World, MODELS, explore, rooms_of


def empty(w=40, h=23):  # like Game.new_level, marked as a draft
    rows = ["".join("1" if (y >= h - 2 or x == 0 or x == w - 1) else "0" for x in range(w)) for y in range(h)]
    return {"name": "Room", "w": w, "h": h, "tiles": rows, "entities": [], "draft": True}


class BuildDrafts(unittest.TestCase):
    def test_maze_of_drafts(self):
        with tempfile.TemporaryDirectory() as d:
            rooms = {}
            for i in range(3):
                for j in range(2):
                    rooms["r%d%d" % (i, j)] = [i * 40, j * 23]
            for n in rooms:
                json.dump(empty(), open(os.path.join(d, n + ".json"), "w"))
            json.dump({"start": "r00", "rooms": rooms, "regions": [{"name": "Test", "color": "#808080", "rooms": list(rooms)}]},
                      open(os.path.join(d, "world.json"), "w"))
            out = subprocess.run([sys.executable, os.path.join(HERE, "..", "tools", "story", "build_drafts.py"), d, "--seed", "4", "--extra", "2"],
                                 capture_output=True, text=True, check=True).stdout
            self.assertIn("built 6 drafts, 7 links (2 behind an ability)", out)  # a tree (5) + 2 gated shortcuts
            for n in rooms:
                self.assertNotIn("draft", json.load(open(os.path.join(d, n + ".json"))))
            W = World(d)
            ox, oy = rooms["r00"]
            start = W.spawn  # an entrance spawn of the start room (world_fixups)
            ground, _ = explore(W, MODELS["cautious"], set(), [start])
            self.assertEqual(set(rooms_of(W, ground)), set(rooms))  # no abilities: every room reachable


if __name__ == "__main__":
    unittest.main()
