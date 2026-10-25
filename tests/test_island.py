# Eastern island routes (tools/story/gen_island.py), with the cautious jump-only movement model of tools/world_check.py.
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from world_check import World, MODELS, explore, rooms_of

ROOT = Path(__file__).resolve().parents[1] / "worlds" / "story"


class Island(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.W = World(str(ROOT))
        cls.island = {n for n in cls.W.rooms if n.startswith("i")}
        cls.ground, cls.touched = explore(cls.W, MODELS["cautious"], set(), [(706, 65)])  # the beach by the raft

    def test_every_island_room_is_reachable_jump_only(self):
        self.assertEqual(self.island - set(rooms_of(self.W, self.ground)), set())

    def test_every_island_star_is_reachable(self):
        stars = {(n, self.W.rooms[n][0] + int(e["x"])//8, self.W.rooms[n][1] + int(e["y"])//8)
                 for n in self.island for e in self.W.rooms[n][2]["entities"] if e["t"] == "strawberry"}
        got = {(k.split(":")[1], *map(int,k.split(":")[2].split(",")))
               for k in self.touched if k.startswith("strawberry:i")}
        self.assertEqual(stars - got, set())

    def test_the_far_rooms_lead_back_to_the_refuge_and_the_shore(self):
        for name in ("i16_guardian_chamber", "i17_crystal_pocket", "i02_north_shore", "i03_south_shore", "i11_flooded_hall", "i06_crater"):
            start = min(c for c in self.ground if self.W.room_of.get(c) == name)
            back = rooms_of(self.W, explore(self.W, MODELS["cautious"], set(), [start])[0])
            self.assertIn("i15_quiet_refuge", back, name)
            self.assertIn("i01_west_shore", back, name)

    def test_lower_maze_has_a_second_return_route_via_the_vent_shaft(self):
        # Closing the gallery must still leave a usable return to the junction.
        # This catches a decorative loop that is not actually traversable.
        world = World(str(ROOT))
        world.solid.update(cell for cell, room in world.room_of.items() if room == "i12_echo_gallery")
        start = min(cell for cell in self.ground if world.room_of.get(cell) == "i13_lower_maze")
        reached = rooms_of(world, explore(world, MODELS["cautious"], set(), [start])[0])
        self.assertIn("i10_junction", reached)


if __name__ == "__main__":
    unittest.main()
