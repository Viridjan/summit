import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path('tools').resolve()))
from checkpoint_ground import solid_ground,floor_below
class CheckpointGround(unittest.TestCase):
    def test_skips_suspended_platform_for_terrain_below(self):
        room={'w':8,'h':8,'tiles':['11111111']+['10000001']*5+['11111111']*2,
              'entities':[{'t':'jumpthru','x':16,'y':24,'w':24,'h':8}]}
        self.assertFalse(solid_ground(room,24,16))
        self.assertEqual(floor_below(room,24,16),(24,40))

    def test_generator_ignores_platform_under_top_entrance(self):
        import json,tempfile
        from world_fixups import add_respawns
        with tempfile.TemporaryDirectory() as folder:
            room={'w':8,'h':8,'tiles':['11101111']+['10000001']*5+['11111111']*2,
                  'entities':[{'t':'jumpthru','x':16,'y':24,'w':24,'h':8}]}
            above={'w':8,'h':4,'tiles':['11111111']*3+['11101111'],'entities':[]}
            Path(folder,'world.json').write_text(json.dumps({'start':'room','rooms':{'room':[0,0],'above':[0,-4]}}))
            for name,data in [('room',room),('above',above)]:Path(folder,name+'.json').write_text(json.dumps(data))
            add_respawns(folder)
            result=json.loads(Path(folder,'room.json').read_text())
            points=[e for e in result['entities'] if e['t']=='respawn']
            self.assertEqual([(e['x'],e['y']) for e in points],[(24,40)])
