"""Exercise the browser's pure branching layout without rerunning world physics."""
import json
from pathlib import Path
import re
import subprocess
import unittest


class BranchLayout(unittest.TestCase):
    def test_route_graph_is_independent_of_unlock_selection(self):
        import sys
        sys.path.insert(0, str(Path('tools').resolve()))
        import progression
        nodes = [{"abilities": [], "links": []},
                 {"abilities": ["ape"], "links": [{"from": "start", "to": "sand", "direction": "right"}]}]
        routes = progression.route_graph([{"name":"start"}, {"name":"sand"}], nodes)
        self.assertEqual(set(routes["rooms"]), {"start", "sand"})
        self.assertEqual(routes["links"], nodes[1]["links"])
        self.assertNotIn("abilities", routes)
        self.assertNotIn('show=function(n){show0(n);zones(n)}', progression.TEMPLATE)

    def test_start_is_root_and_choices_split_without_return_branches(self):
        source = Path('tools/progression.py').read_text()
        match = re.search(r'function routeTree\(names,links,start[^)]*\)\{.*?\n\}', source, re.S)
        self.assertIsNotNone(match, 'Renderer has a rooted branch layout')
        code = match.group(0) + '''
const links=[['start','ape'],['ape','start'],['ape','left'],['ape','right'],['left','ape'],['right','ape']].map(([from,to])=>({from,to}));
console.log(JSON.stringify(routeTree(['start','ape','left','right'],links,'start')));
'''
        result = json.loads(subprocess.check_output(['node', '-e', code], text=True))
        self.assertEqual(result['children']['start'], ['ape'])
        self.assertEqual(result['children']['ape'], ['left', 'right'])
        pos = result['pos']
        self.assertLess(pos['start']['y'], pos['ape']['y'])
        self.assertLess(pos['left']['x'], pos['ape']['x'])
        self.assertGreater(pos['right']['x'], pos['ape']['x'])
        self.assertEqual(pos['start']['x'], pos['ape']['x'])
        self.assertEqual(len(result['extra']), 3)

    def test_compact_graph_collapses_chains_and_dashes_only_identical_stations(self):
        source=Path('tools/progression.py').read_text()
        tree=re.search(r'function routeTree\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        compact=re.search(r'function compactRoutes\([^)]*\)\{.*?\n\}',source,re.S)
        self.assertIsNotNone(compact)
        code=tree+'\n'+compact.group(0)+'''
const links=[['start','hall'],['hall','fork'],['fork','left'],['fork','right'],['left','fork'],['right','fork']].map(([from,to])=>({from,to,direction:'right'}));
const original=routeTree(['start','hall','fork','left','right'],links,'start',['left']);
const result=compactRoutes(original,'start',['fork']);
console.log(JSON.stringify(result));
'''
        result=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertNotIn('hall',result['names'])
        self.assertIn('start',result['names'])
        self.assertIn('fork',result['names'])
        for edge in result['links']:
            if edge.get('sameStation'):
                self.assertEqual(result['aliases'][edge['from']],edge['to'])

    def test_grouping_combines_regions_but_preserves_boss_choice(self):
        source=Path('tools/progression.py').read_text()
        fn=re.search(r'function groupRoutes\([^)]*\)\{.*?\n\}',source,re.S)
        self.assertIsNotNone(fn)
        code=fn.group(0)+'''
const rooms=[{name:'a'},{name:'b'},{name:'ape',bosses:['ape']},{name:'sand'}];
const links=[['a','b'],['b','ape'],['ape','b'],['ape','sand']].map(([from,to])=>({from,to,direction:'right'}));
const result=groupRoutes(rooms,{a:'Jungle',b:'Jungle',ape:'Jungle',sand:'Sand'}, {rooms:{a:'g',b:'g',ape:'g',sand:'g'},links},'a');
console.log(JSON.stringify(result));
'''
        result=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(result['groupOf']['a'],result['groupOf']['b'])
        self.assertNotEqual(result['groupOf']['ape'],result['groupOf']['b'])
        self.assertEqual(len(result['groups']),3)
