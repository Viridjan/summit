"""Foothills maze entrance and deliberate coastal travel."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from world_check import World, MODELS, explore, rooms_of

ROOT = Path(__file__).resolve().parents[1] / "worlds/story"


class IslandConnections(unittest.TestCase):
    def test_foothills_reaches_maze_without_the_summit_or_east_coast(self):
        world = World(str(ROOT))
        allowed = {"i04_foothills", "i09_sea_cave", "i10_junction"}
        world.solid.update(c for c, room in world.room_of.items() if room not in allowed)
        ox, oy, _ = world.rooms["i04_foothills"]
        ground = explore(world, MODELS["cautious"], set(), [(ox + 3, oy + 12)])[0]
        self.assertIn("i10_junction", rooms_of(world, ground))
        back_start = next(c for c in ground if world.room_of.get(c) == "i10_junction")
        back = explore(world, MODELS["cautious"], set(), [back_start])[0]
        self.assertIn("i04_foothills", rooms_of(world, back))

    def test_tall_i09_connects_directly_under_foothills(self):
        world = World(str(ROOT))
        self.assertNotIn("i18_ash_passage",set(world.rooms))
        fx,fy,foot = world.rooms["i04_foothills"]
        x,y,tunnel = world.rooms["i09_sea_cave"]
        self.assertEqual((x,y),(fx,fy+foot["h"]))
        self.assertGreaterEqual(tunnel["h"],40)
        self.assertEqual(tunnel["name"],"Ash Passage")

    def test_maze_internal_alignment_survives_the_shift(self):
        world = World(str(ROOT))
        jx,jy,_ = world.rooms["i10_junction"]
        # The maze retains its original room-to-room offsets.
        for name,delta in [("i11_flooded_hall",(-48,0)),("i12_echo_gallery",(-88,0)),
                           ("i13_lower_maze",(-88,16)),("i14_vent_shaft",(-40,16)),
                           ("i15_quiet_refuge",(-24,32)),("i16_guardian_chamber",(0,16)),
                           ("i17_crystal_pocket",(-80,39)),("x1_serpent_lair",(-88,55))]:
            x,y,_ = world.rooms[name]
            self.assertEqual((x-jx,y-jy),delta,name)

    def test_coastal_signs_link_to_each_other(self):
        world = World(str(ROOT))
        for room, target in [("i02_north_shore", "i03_south_shore"), ("i03_south_shore", "i02_north_shore")]:
            signs = [e for e in world.rooms[room][2]["entities"] if e.get("skin") == "signpost"]
            self.assertEqual(len(signs), 1, room)
            sign = signs[0]
            self.assertEqual(sign["t"], "house_door", "Travel must require Interact")
            self.assertEqual(sign["to"], target + ":coast_path")
            ox, oy, _ = world.rooms[room]
            self.assertIn((ox + sign["x"]//8, oy + sign["y"]//8), world.doors)


if __name__ == "__main__":
    unittest.main()
