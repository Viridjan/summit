import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,str(Path('tools').resolve()))
import progression_job as J

class ProgressionJob(unittest.TestCase):
    def test_snapshot_is_used_and_success_is_atomic(self):
        with tempfile.TemporaryDirectory() as temp:
            source=Path(temp,'world');source.mkdir();output=Path(temp,'report')
            (source/'world.json').write_text(json.dumps({'start':'room','rooms':{'room':[0,0]}}))
            (source/'room.json').write_text('{"name":"Original"}')
            def build(snapshot):
                (source/'room.json').write_text('{"name":"Changed"}')
                self.assertEqual(json.loads(Path(snapshot,'room.json').read_text())['name'],'Original')
                return SimpleNamespace(),{},[]
            with patch.object(J.progression,'build',side_effect=build),patch.object(J.progression,'page',return_value='<html>report</html>'):
                self.assertEqual(J.run_job(source,output),0)
            self.assertEqual(json.loads((output/'status.json').read_text())['state'],'complete')
            self.assertEqual((output/'index.html').read_text(),'<html>report</html>')

    def test_failure_is_reported_with_a_log(self):
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp,'report')
            self.assertEqual(J.run_job(Path(temp,'missing'),output),1)
            self.assertEqual(json.loads((output/'status.json').read_text())['state'],'failed')
            self.assertTrue((output/'analysis.log').read_text())
            self.assertFalse((output/'index.html').exists())
