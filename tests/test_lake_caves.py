# Lake Caves maze (tools/story/gen_first_stretch.py section 3), with the cautious jump-only model of tools/world_check.py.
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from world_check import World, MODELS, explore, rooms_of

ROOT = Path(__file__).resolve().parents[1] / "worlds" / "story"
LAKE = {"c0_roar_tunnel", "c1_lake_cave", "c2_cave_teeth", "c3_cove_tunnel", "c4_deep_lake"}


class LakeCaves(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.W = World(str(ROOT))
        ox, oy = cls.W.rooms["c1_lake_cave"][:2]
        cls.landing = (ox + 20, oy + 18)  # under the shaft from The Hole
        cls.ground, cls.touched = explore(cls.W, MODELS["cautious"], set(), [cls.landing])

    def test_through_to_cove_town_with_both_stars(self):
        reached = set(rooms_of(self.W, self.ground))
        self.assertTrue(LAKE | {"t1_cove_town"} <= reached, LAKE - reached)
        stars = {k.split(":")[1] for k in self.touched if k.startswith("strawberry:c")}
        self.assertEqual(stars, {"c0_roar_tunnel", "c4_deep_lake"})

    def test_back_from_cove_town(self):
        tx, ty = self.W.rooms["t1_cove_town"][:2]
        start = min(c for c in self.ground if self.W.room_of.get(c) == "t1_cove_town")
        back = rooms_of(self.W, explore(self.W, MODELS["cautious"], set(), [start])[0])
        self.assertIn("c1_lake_cave", back)
        self.assertIn("c0_roar_tunnel", back)

    def test_the_main_tunnel_is_walled_after_the_lake(self):
        # without the Deep Lake, the far side of Lake Cave is cut off: the detour is part of the route
        ox, oy = self.W.rooms["c1_lake_cave"][:2]
        lv = self.W.rooms["c1_lake_cave"][2]
        wall = [lv["tiles"][y][60] for y in range(15, 19)]
        self.assertEqual(wall, ["1"] * 4)


if __name__ == "__main__":
    unittest.main()
