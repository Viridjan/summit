import os, sys, tempfile, unittest
from types import SimpleNamespace
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from unittest.mock import patch
import progression as P


class Progression(unittest.TestCase):
    def test_reversible_forks_remain_choices(self):
        world = SimpleNamespace(rooms={"ape": (40, 0, {}), "jungle": (0, 0, {}), "sand": (80, 0, {})})
        entrances = [("ape", (41, 5)), ("jungle", (38, 5)), ("sand", (81, 5))]
        found = [(set(), {("jungle", 38, 5), ("sand", 81, 5)}),
                 (set(), {("ape", 41, 5)}), (set(), {("ape", 41, 5)})]
        links = P.room_links(world, entrances, found)
        self.assertEqual({e["to"] for e in links if e["from"] == "ape"}, {"jungle", "sand"})
        self.assertEqual({e["direction"] for e in links if e["from"] == "ape"}, {"left", "right"})
        self.assertEqual(len(links), 4)  # Return routes do not erase the choice.

    def test_cave_seal_does_not_leak_between_worker_jobs(self):
        world = SimpleNamespace(solid={(99, 99)})
        with patch.object(P, "_W", world), patch.object(P, "_BASE", {(0, 0)}), \
             patch.object(P, "_WALLS", set()), patch.object(P, "_GATES", {}), \
             patch.object(P, "explore", return_value=(set(), set())):
            P._from_entrance(("room", (1, 1), [], [(5, 5)]))
            self.assertEqual(world.solid, {(0, 0), (5, 5)})
            P._from_entrance(("room", (1, 1), [], []))
            self.assertEqual(world.solid, {(0, 0)})

    def test_branches_and_page(self):
        W, nodes, order = P.build("worlds/story")
        self.assertEqual(order[0], frozenset())  # the start comes first, then one node per ability set reached
        for ab in order[1:]:
            self.assertTrue(any(p < ab and len(p) == len(ab) - 1 for p in order), ab)
        for n in nodes.values():
            self.assertTrue(set(n["rooms"]) <= set(W.rooms))
            self.assertTrue(set(n["rooms"].values()) <= set("gop"))
        after_ape = nodes[frozenset({"ape", "dash"})]
        self.assertEqual(after_ape["rooms"].get("l1_jungle_depths"), "g")
        self.assertEqual(after_ape["rooms"].get("s1_sand_cave"), "g")
        self.assertTrue(after_ape["links"])
        W.dir = "worlds/story"
        html = P.page(W, nodes, order)
        self.assertIn('"nodes"', html)
        self.assertNotIn("/*DATA*/", html)


if __name__ == "__main__":
    unittest.main()
