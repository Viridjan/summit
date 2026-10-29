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

    def test_nearby_entrances_share_right_checkpoint_across_safe_bridge(self):
        import json
        room=json.loads(Path('worlds/story/c6_wall_cave.json').read_text())
        room['entities'].append({'t':'respawn','x':120,'y':48})
        prune(room,[(0,40),(168,40),(136,80)])
        points=[(e['x'],e['y']) for e in room['entities'] if e['t'] in ('spawn','respawn')]
        self.assertIn((160,48),points)
        self.assertNotIn((120,48),points)
        self.assertIn((8,48),points)

    def test_bridge_with_hazard_or_gap_keeps_both_points(self):
        import json
        from prune_respawns import shared_landing
        for blocked in ('water','gap'):
            room=json.loads(Path('worlds/story/c6_wall_cave.json').read_text())
            a={'t':'respawn','x':120,'y':48};b={'t':'respawn','x':160,'y':48}
            if blocked=='water':room['entities'].append({'t':'water','x':136,'y':40,'w':8,'h':16})
            else:room['entities']=[e for e in room['entities'] if not (e['t']=='jumpthru' and e['y']==56)]
            self.assertFalse(shared_landing(room,a,b),blocked)
