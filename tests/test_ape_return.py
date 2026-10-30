import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path('tools').resolve()))
import progression as P
from world_check import World,MODELS,explore,rooms_of

class ApeReturn(unittest.TestCase):
    def test_return_closes_without_losing_either_forward_route(self):
        world=World('worlds/story')
        base=set(world.solid)
        with patch.object(P,'_BASE',base),patch.object(P,'_WALLS',P.breakwalls(world)),patch.object(P,'_GATES',P.boss_gates(world)),patch.object(P,'_AFTER_GATES',P.after_gates(world)):
            world.solid=P.blocked({'dash'})
            ox,oy,_=world.rooms['j3_jungle_hills']
            ground,_=explore(world,MODELS['cautious'],{'dash'},[(ox+2,oy+10)])
            self.assertIn('a1_ape_arena',rooms_of(world,ground))
            self.assertNotIn('l1_jungle_depths',rooms_of(world,ground))
            world.solid=P.blocked({'ape','dash','climb','attack'})
            ax,ay,_=world.rooms['a1_ape_arena']
            ground,_=explore(world,MODELS['generous'],{'ape','dash','climb','attack'},[(ax+2,ay+18)])
            reached=set(rooms_of(world,ground))
            self.assertTrue({'l1_jungle_depths','s1_sand_cave','l3_treetop_village'}<=reached)
            self.assertFalse({'j1_jungle_edge','j2_jungle_falls','m1_meadow'}&reached)
