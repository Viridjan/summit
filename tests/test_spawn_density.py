import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path('tools').resolve()))
import world_fixups as F

class SpawnDensity(unittest.TestCase):
    def test_authored_spawn_replaces_redundant_entrance_markers(self):
        authored={'t':'spawn','x':16,'y':80}
        room={'w':40,'h':16,'entities':[{'t':'spawn','x':8,'y':80,'entrance':True},authored,{'t':'spawn','x':288,'y':80,'entrance':True}]}
        F.prune_spawns(room)
        self.assertEqual(room['entities'],[authored])

    def test_long_room_keeps_two_separated_points(self):
        room={'w':120,'h':16,'entities':[{'t':'spawn','x':x,'y':80,'entrance':True} for x in [8,12,480,880]]}
        F.prune_spawns(room)
        spawns=room['entities']
        self.assertEqual([e['x'] for e in spawns],[8,880])
        F.prune_spawns(room)
        self.assertEqual(room['entities'],spawns)

    def test_authored_checkpoints_are_never_deleted(self):
        room={'w':40,'h':16,'entities':[{'t':'spawn','x':x,'y':80} for x in [8,80,240]]}
        F.prune_spawns(room)
        self.assertEqual(len(room['entities']),3)
