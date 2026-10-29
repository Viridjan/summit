import os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import progression as P


class Progression(unittest.TestCase):
    def test_branches_and_page(self):
        W, nodes, order = P.build("worlds/story")
        self.assertEqual(order[0], frozenset())  # the start comes first, then one node per ability set reached
        for ab in order[1:]:
            self.assertTrue(any(p < ab and len(p) == len(ab) - 1 for p in order), ab)
        for n in nodes.values():
            self.assertTrue(set(n["rooms"]) <= set(W.rooms))
            self.assertTrue(set(n["rooms"].values()) <= set("gop"))
        W.dir = "worlds/story"
        html = P.page(W, nodes, order)
        self.assertIn('"nodes"', html)
        self.assertNotIn("/*DATA*/", html)


if __name__ == "__main__":
    unittest.main()
