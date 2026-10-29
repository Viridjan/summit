"""Exercise the browser's pure branching layout without rerunning world physics."""
import json
from pathlib import Path
import re
import subprocess
import unittest


class BranchLayout(unittest.TestCase):
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
