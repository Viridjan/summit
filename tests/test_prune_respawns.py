import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path('tools').resolve()))
from prune_respawns import prune

class PruneRespawns(unittest.TestCase):
    def test_alias_duplicates_and_unnecessary_interior_point(self):
        room={'entities':[{'t':'respawn','x':8,'y':80},{'t':'spawn','x':16,'y':80},
                          {'t':'respawn','x':160,'y':80},{'t':'respawn','x':304,'y':80},
                          {'t':'note','x':80,'y':24,'text':'Keep me'}]}
        self.assertEqual(prune(room,[(0,80),(312,80)]),(4,2))
        self.assertEqual([(e['x'],e['y']) for e in room['entities'] if e['t'] in ('spawn','respawn')],[(16,80),(304,80)])
        self.assertEqual(room['entities'][-1]['text'],'Keep me')
        original=copy.deepcopy(room)
        prune(room,[(0,80),(312,80)])
        self.assertEqual(room,original)

    def test_three_separate_entrances_keep_three_points(self):
        room={'entities':[{'t':'spawn','x':x,'y':328} for x in [8,224,160]]}
        self.assertEqual(prune(room,[(0,320),(232,320),(160,0)]),(3,3))

    def test_start_room_retains_its_start_marker(self):
        room={'entities':[{'t':'respawn','x':8,'y':80},{'t':'spawn','x':160,'y':80}]}
        prune(room,[(0,80)],keep_start=True)
        self.assertEqual(len(room['entities']),2)
