"""Foothills maze entrance and deliberate coastal travel."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from world_check import World, MODELS, explore, rooms_of

ROOT = Path(__file__).resolve().parents[1] / "worlds/story"


SHORES = {"i01_west_shore", "i02_north_shore", "i03_south_shore", "i08_east_shore"}


OPPOSITE = {"i01_west_shore":"i08_east_shore", "i08_east_shore":"i01_west_shore",
            "i02_north_shore":"i03_south_shore", "i03_south_shore":"i02_north_shore"}


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

    def test_each_long_shore_has_panels_only_for_neighboring_shores(self):
        world = World(str(ROOT))
        for room in SHORES:
            self.assertGreaterEqual(world.rooms[room][2]["w"],120,room)
            signs = [e for e in world.rooms[room][2]["entities"] if e.get("skin") == "signpost"]
            self.assertEqual({e["to"].split(":")[0] for e in signs},SHORES-{room,OPPOSITE[room]})
            self.assertEqual(len(signs),2,room)
            for sign in signs:
                self.assertEqual(sign["t"],"house_door","Travel must require Interact")
                target,did = sign["to"].split(":")
                arrival = next(e for e in world.rooms[target][2]["entities"] if e.get("id") == did)
                self.assertEqual(arrival["to"],room+":"+sign["id"])

    def test_original_north_panel_now_leads_west(self):
        world = World(str(ROOT))
        sign = next(e for e in world.rooms["i02_north_shore"][2]["entities"] if e.get("id") == "coast_path")
        self.assertEqual(sign["to"].split(":")[0],"i01_west_shore")
        self.assertEqual(sign["label"],"West Shore")

    def test_shores_do_not_share_physical_room_boundaries(self):
        world = World(str(ROOT))
        for a in SHORES:
            ax,ay,al = world.rooms[a]
            for b in SHORES-{a}:
                bx,by,bl = world.rooms[b]
                horizontal = ax+al["w"]==bx or bx+bl["w"]==ax
                vertical = ay+al["h"]==by or by+bl["h"]==ay
                self.assertFalse(horizontal and max(ay,by)<min(ay+al["h"],by+bl["h"]),(a,b))
                self.assertFalse(vertical and max(ax,bx)<min(ax+al["w"],bx+bl["w"]),(a,b))

    def test_all_panels_are_reachable_without_leaving_the_shores(self):
        world = World(str(ROOT))
        world.solid.update(c for c,room in world.room_of.items() if room not in SHORES)
        for room in SHORES:
            ox,oy,level = world.rooms[room]
            sign = next(e for e in level["entities"] if e.get("skin") == "signpost")
            start = (ox+sign["x"]//8+1,oy+(sign["y"]+sign["h"])//8-1)
            ground = explore(world,MODELS["cautious"],set(),[start])[0]
            self.assertTrue(SHORES <= set(rooms_of(world,ground)),room)
            for name in SHORES:
                rx,ry,data = world.rooms[name]
                for panel in data["entities"]:
                    if panel.get("skin") != "signpost": continue
                    self.assertIn((rx+panel["x"]//8+1,ry+(panel["y"]+panel["h"])//8-1),ground,(room,name,panel["id"]))

    def test_post_guardian_west_shore_keeps_the_panel_network(self):
        import json
        variant = json.loads((ROOT/"i01_west_shore_after.json").read_text())
        self.assertGreaterEqual(variant["w"],120)
        self.assertEqual(len([e for e in variant["entities"] if e.get("skin") == "signpost"]),2)
        self.assertTrue(any(e.get("id") == "home" for e in variant["entities"]))
        doors = [e for e in variant["entities"] if e["t"] == "house_door"]
        for panel in doors:
            for other in doors:
                if panel is other: continue
                self.assertFalse(
                    max(panel["x"],other["x"]) < min(panel["x"]+panel["w"],other["x"]+other["w"])
                    and max(panel["y"],other["y"]) < min(panel["y"]+panel["h"],other["y"]+other["h"]),
                    (panel["id"],other["id"]))


if __name__ == "__main__":
    unittest.main()
