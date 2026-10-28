# Lake Caves maze (tools/story/gen_first_stretch.py section 3), with the cautious jump-only model of tools/world_check.py.
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from world_check import World, MODELS, explore, rooms_of

ROOT = Path(__file__).resolve().parents[1] / "worlds" / "story"
LAKE = {"c0_roar_tunnel", "c1_lake_cave", "c5_lake_crossing", "c6_wall_cave", "c2_cave_teeth", "c3_cove_tunnel", "c4_deep_lake"}


class LakeCaves(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.W = World(str(ROOT))
        ox, oy = cls.W.rooms["c1_lake_cave"][:2]
        cls.landing = (ox + 20, oy + 23 + 18)  # under the shaft (The Hole is the top 23 rows)
        cls.ground, cls.touched = explore(cls.W, MODELS["cautious"], set(), [cls.landing])

    def test_every_lake_room_and_both_stars(self):
        reached = set(rooms_of(self.W, self.ground))
        self.assertTrue(LAKE <= reached, LAKE - reached)
        stars = {k.split(":")[1] for k in self.touched if k.startswith("strawberry:c")}
        self.assertEqual(stars, {"c0_roar_tunnel", "c4_deep_lake"})


if __name__ == "__main__":
    unittest.main()
