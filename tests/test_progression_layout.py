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

    def test_region_grouping_never_bypasses_ape_gate(self):
        source=Path('tools/progression.py').read_text()
        fn=re.search(r'function groupRoutes\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        code=fn+"\nconst rooms=[{name:'entry',title:'Jungle'},{name:'ape',title:'Ape Arena',bosses:['ape']},{name:'depths'},{name:'village'}];\nconst links=[['entry','ape'],['ape','entry'],['entry','depths'],['depths','village']].map(([from,to])=>({from,to}));\nconsole.log(JSON.stringify(groupRoutes(rooms,{entry:'Jungle',ape:'Jungle',depths:'Jungle',village:'Village'}, {rooms:{entry:'g',ape:'g',depths:'g',village:'g'},requirements:{entry:[],ape:[],depths:['ape'],village:['ape']},links},'entry')));\n"
        result=json.loads(subprocess.check_output(['node','-e',code],text=True))
        groups=result['groupOf']
        self.assertNotEqual(groups['entry'],groups['depths'])
        self.assertNotIn((groups['entry'],groups['depths']),[(e['from'],e['to']) for e in result['links']])
        self.assertIn((groups['ape'],groups['depths']),[(e['from'],e['to']) for e in result['links']])

    def test_graph_one_shows_every_unlock_state_in_metro_lines(self):
        source=Path('tools/progression.py').read_text()
        start=source.index('function drawTop()')
        end=source.index('const cv=',start)
        top=source[start:end]
        self.assertNotIn('ASSUME',top)
        self.assertNotIn('choices:false',top)
        self.assertIn('graph.display[id].map(nm)',top)
        self.assertIn('unplaced.includes',top)

    def test_unlock_path_distinguishes_orders_that_end_at_same_state(self):
        source=Path('tools/progression.py').read_text()
        fn=re.search(r'function unlockSteps\([^)]*\)\{.*?\n\}',source,re.S)
        self.assertIsNotNone(fn)
        code=fn.group(0)+'''
const nodes=[{abilities:[]},{abilities:['attack']},{abilities:['dash']},{abilities:['attack','dash']}];
console.log(JSON.stringify([unlockSteps(nodes,[0,1,3]),unlockSteps(nodes,[0,2,3])]));
'''
        result=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(result,[['attack','dash'],['dash','attack']])

    def test_equal_upgrades_share_one_station_with_multiple_arrivals(self):
        source=Path('tools/progression.py').read_text()
        fn=re.search(r'function mergedUnlocks\([^)]*\)\{.*?\n\}',source,re.S)
        self.assertIsNotNone(fn)
        code=fn.group(0)+"\nconst nodes=[{id:'start',abilities:[],parents:[]},{id:'attack',abilities:['attack'],parents:['start']},{id:'dash',abilities:['dash'],parents:['start']},{id:'attack+dash',abilities:['attack','dash'],parents:['attack','dash']},{id:'duplicate',abilities:['dash','attack'],parents:['attack']}];\nconsole.log(JSON.stringify(mergedUnlocks(nodes)));\n"
        result=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(len(result['names']),4)
        self.assertEqual(set(result['parents']['3']),{'1','2'})
        self.assertEqual(result['canonical']['4'],'3')
        self.assertEqual(set(result['children']['0']),{'1','2'})

    def test_unlock_filters_distinguish_unplaced_and_blocked_steps(self):
        source=Path('tools/progression.py').read_text()
        merged=re.search(r'function mergedUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        filtered=re.search(r'function filteredUnlocks\([^)]*\)\{.*?\n\}',source,re.S)
        self.assertIsNotNone(filtered)
        code=merged+'\n'+filtered.group(0)+'''
const nodes=[
{id:'start',abilities:[],parents:[],choices:['attack'],unplaced:['climb']},
{id:'attack',abilities:['attack'],parents:['start'],choices:['ape'],unplaced:['climb']},
{id:'climb',abilities:['climb'],parents:['start'],choices:[],unplaced:[]},
{id:'ape',abilities:['ape'],parents:['start'],choices:[],unplaced:['climb']},
{id:'attack+ape',abilities:['attack','ape'],parents:['attack','ape'],choices:[],unplaced:['climb']}];
console.log(JSON.stringify([filteredUnlocks(nodes,true,false),filteredUnlocks(nodes,false,true)]));
'''
        unplaced,blocked=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertNotIn('2',unplaced['names'])
        self.assertIn('3',unplaced['names'])  # A placed but inaccessible boss is a separate filter.
        self.assertEqual(set(blocked['names']),{'0','1','4'})
        self.assertEqual(blocked['parents']['4'],['1'])

    def test_hiding_unplaced_upgrade_does_not_delete_achievable_boss(self):
        source=Path('tools/progression.py').read_text()
        merge=re.search(r'function mergedUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        fn=re.search(r'function filteredUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        code=merge+'\n'+fn+"\nconst nodes=[{id:'start',abilities:[],parents:[],choices:[],unplaced:['dash']},{id:'dash',abilities:['dash'],parents:['start'],choices:['ape'],unplaced:[]},{id:'ape+dash',abilities:['ape','dash'],parents:['dash'],choices:[],unplaced:[]}];\nconsole.log(JSON.stringify(filteredUnlocks(nodes,true,true)));\n"
        graph=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(graph['names'],['0','2'])
        self.assertEqual(graph['parents']['2'],['0'])

    def test_unavailable_filter_alone_keeps_both_bosses(self):
        source=Path('tools/progression.py').read_text()
        merge=re.search(r'function mergedUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        fn=re.search(r'function filteredUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        code=merge+'\n'+fn+"\nconst nodes=[{id:'start',abilities:[],parents:[],choices:[],unplaced:['dash','climb']},{id:'dash',abilities:['dash'],parents:['start'],choices:['ape'],unplaced:['climb']},{id:'ape+dash',abilities:['ape','dash'],parents:['dash'],choices:[],unplaced:['climb']},{id:'ape+climb+dash',abilities:['ape','climb','dash'],parents:['ape+dash'],choices:['guardian'],unplaced:[]},{id:'ape+climb+dash+guardian',abilities:['ape','climb','dash','guardian'],parents:['ape+climb+dash'],choices:[],unplaced:[]}];\nconsole.log(JSON.stringify(filteredUnlocks(nodes,false,true)));\n"
        graph=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(graph['display'][graph['canonical']['2']],['ape'])
        self.assertEqual(graph['display'][graph['canonical']['4']],['ape','guardian'])
        self.assertEqual(len(graph['names']),3)

    def test_generated_data_cannot_terminate_script_tag(self):
        import sys,tempfile
        from types import SimpleNamespace
        sys.path.insert(0,str(Path('tools').resolve()))
        import progression as P
        payload='</script><script>window.injected=true</script>'
        with tempfile.TemporaryDirectory() as folder:
            Path(folder,'world.json').write_text('{"regions":[]}')
            world=SimpleNamespace(dir=folder,spawn=(0,0),room_of={(0,0):'room'},rooms={'room':(0,0,{'name':payload,'w':2,'h':3,'tiles':['11','00','11'],'entities':[]})})
            nodes={frozenset():dict(abilities=[],rooms={'room':'g'},cells={},choices=[],skill=[],unplaced=[],zones=[],first=0,links=[])}
            html=P.page(world,nodes,[frozenset()])
            self.assertNotIn(payload,html)
            data=json.loads(re.search(r'const D=(.*?);\n',html).group(1))
            self.assertEqual(data['rooms'][0]['title'],payload)

    def test_filtered_graph_supports_an_owned_starting_upgrade(self):
        source=Path('tools/progression.py').read_text()
        merge=re.search(r'function mergedUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        fn=re.search(r'function filteredUnlocks\([^)]*\)\{.*?\n\}',source,re.S).group(0)
        code=merge+'\n'+fn+"\nconst nodes=[{id:'dash',abilities:['dash'],parents:[],choices:['ape'],unplaced:[]},{id:'ape+dash',abilities:['ape','dash'],parents:['dash'],choices:[],unplaced:[]}];\nconsole.log(JSON.stringify(filteredUnlocks(nodes,false,true)));\n"
        graph=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(graph['names'],['0','1'])

    def test_generator_begins_with_world_starting_abilities(self):
        import sys,tempfile
        from types import SimpleNamespace
        from unittest.mock import patch
        sys.path.insert(0,str(Path('tools').resolve()))
        import progression as P
        observed=[]
        with tempfile.TemporaryDirectory() as folder:
            Path(folder,'world.json').write_text('{"abilities":["dash"]}')
            world=SimpleNamespace(solid=set(),rooms={},items={})
            def node(world,base,walls,abilities,survey,nodes,order,unplaced):
                observed.append((abilities,unplaced));nodes[abilities]={};order.append(abilities);return []
            with patch.object(P,'World',return_value=world),patch.object(P,'survey_many',side_effect=lambda w,b,wall,sets:{a:None for a in sets}),patch.object(P,'_node',side_effect=node):
                P.build(folder)
        self.assertEqual(observed[0][0],frozenset({'dash'}))
        self.assertNotIn('dash',observed[0][1])

    def test_previous_click_reroutes_then_second_click_updates_map(self):
        source=Path('tools/progression.py').read_text()
        planner=re.search(r'function planUnlockRoute\([^)]*\)\{.*?\n\}',source,re.S)
        selector=re.search(r'function selectUnlockStep\([^)]*\)\{.*?\n\}',source,re.S)
        self.assertIsNotNone(planner)
        self.assertIsNotNone(selector)
        code=planner.group(0)+'\n'+selector.group(0)+'''
const graph={names:['0','1','2','3'],parents:{0:[],1:['0'],2:['0'],3:['1','2']},children:{0:['1','2'],1:['3'],2:['3'],3:[]},display:{0:[],1:['attack'],2:['dash'],3:['attack','dash']}};
const a=selectUnlockStep(graph,[0,1,3],3,null,'2');
const b=selectUnlockStep(graph,a.route,a.mapState,a.pending,'2');
const c=selectUnlockStep(graph,b.route,b.mapState,b.pending,'3');
console.log(JSON.stringify([a,b,c]));
'''
        first,second,next_step=json.loads(subprocess.check_output(['node','-e',code],text=True))
        self.assertEqual(first['route'],[0,2,3])
        self.assertEqual(first['mapState'],3)
        self.assertEqual(second['mapState'],2)
        self.assertEqual(next_step['route'],[0,2,3])
        self.assertEqual(next_step['mapState'],3)
