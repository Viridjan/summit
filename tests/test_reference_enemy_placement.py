"""Regression checks for safe, repeatable installation of every enemy type."""
from collections import Counter
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from place_reference_enemies import SIZES, install


class EnemyPlacementTests(unittest.TestCase):
    def test_all_variants_are_installed_without_changing_terrain_or_entrances(self):
        source = Path(__file__).resolve().parents[1] / 'worlds/hollow_knight'
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'hk'
            shutil.copytree(source, root)
            before = {p.name: json.loads(p.read_text()) for p in root.glob('r*.json')}
            result = install(root, apply=True)
            self.assertEqual(set(result['counts']), set(SIZES))
            self.assertTrue(all(result['counts'][kind] == 3 for kind in SIZES))
            self.assertEqual(len(result['placements']), 3 * len(SIZES))
            counts = Counter(item['room'] for item in result['placements'])
            self.assertTrue(all(n <= 2 for n in counts.values()))
            self.assertEqual(counts['r005'], 1)
            for name, old in before.items():
                new = json.loads((root / name).read_text())
                self.assertEqual(new['tiles'], old['tiles'], name)
                self.assertEqual([e for e in new['entities'] if e['t'] in ['spawn', 'door']],
                                 [e for e in old['entities'] if e['t'] in ['spawn', 'door']], name)
            rerun = install(root, apply=True)
            self.assertEqual(rerun['changed_rooms'], [])
            self.assertEqual(len(rerun['placements']), 3 * len(SIZES))


if __name__ == '__main__':
    unittest.main()
