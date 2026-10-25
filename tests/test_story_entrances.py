# Regression tests for story entrances. Temporary fixtures keep these checks independent of personal save data.
# Reading help: docs/CODE_GUIDE.md.

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_entrances import bad_entrances


class StoryEntrances(unittest.TestCase):
    # Regression coverage for story entrances are flat for the walk in. The assertions below state the expected behavior of this case.
    def test_story_entrances_are_flat_for_the_walk_in(self):
        root = Path(__file__).resolve().parents[1] / "worlds" / "story"
        self.assertEqual(bad_entrances(str(root)), [])


if __name__ == "__main__":
    unittest.main()
