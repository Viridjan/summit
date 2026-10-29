"""Terrain morphing operates on authored rooms, never personal saves."""
import contextlib
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import morph_terrain as M


def fixture():
    rows = [list("1"*40) for _ in range(18)]
    for y in range(4,14):
        for x in range(1,39): rows[y][x] = "0"
    for y in (14,15):
        for x in range(26,30): rows[y][x] = "0"
    return dict(name="Test cavern", w=40, h=18, environment="cavern_deep",
                tiles=["".join(row) for row in rows],
                entities=[dict(t="spawn",x=24,y=104,entrance=True),
                          dict(t="water",x=208,y=112,w=32,h=16),
                          dict(t="spikes_down",x=80,y=32),
                          dict(t="breakwall",x=152,y=32,w=16,h=80),
                          dict(t="jumpthru",x=280,y=72,w=24,h=8)])


class MorphTerrain(unittest.TestCase):
    def test_clustered_cavern_changes_are_deterministic_without_mutating_input(self):
        original = fixture()
        snapshot = copy.deepcopy(original)
        result = M.morph_room(original, terrain="cavern", seed=42, intensity=0.5)
        self.assertEqual(original, snapshot)
        self.assertNotEqual(result["tiles"], original["tiles"])
        self.assertEqual(result, M.morph_room(original, terrain="cavern", seed=42, intensity=0.5))
        self.assertNotEqual(result["tiles"], M.morph_room(original, terrain="cavern", seed=19, intensity=0.5)["tiles"])

    def test_borders_entities_theme_and_standing_surfaces_are_preserved(self):
        original = fixture()
        result = M.morph_room(original, seed=42, intensity=1.0)
        self.assertEqual(result["entities"], original["entities"])
        self.assertEqual(result["environment"], "cavern_deep")
        a,b = original["tiles"],result["tiles"]
        self.assertEqual(a[:2],b[:2])
        self.assertEqual(a[-2:],b[-2:])
        for y,row in enumerate(a):
            self.assertEqual(row[:2],b[y][:2])
            self.assertEqual(row[-2:],b[y][-2:])
            for x,c in enumerate(row):
                if c == "0": self.assertEqual(b[y][x],"0", "Existing air and movement space stays open")
                if y >= 2 and c == "1" and a[y-1][x] == a[y-2][x] == "0":
                    self.assertEqual(b[y][x],"1", "Existing standing surfaces cannot become pits")
        # The liquid's sides, the ceiling spike anchor and the breakable gate stay fixed.
        for x,y in [(25,14),(30,14),(10,3),(19,3),(20,3)]:
            self.assertEqual(a[y][x],b[y][x])

    def test_thin_detour_walls_are_not_drilled_through(self):
        room = fixture()
        rows = list(map(list,room["tiles"]))
        for x in range(1,39): rows[8][x] = "1"
        room["tiles"] = ["".join(row) for row in rows]
        changed = M.morph_room(room,intensity=1.0)
        self.assertEqual(changed["tiles"][8],room["tiles"][8])

    def test_same_preset_is_idempotent_and_zero_intensity_is_noop(self):
        room = fixture()
        changed = M.morph_room(room,seed=42)
        self.assertEqual(changed,M.morph_room(changed,seed=42))
        self.assertEqual(room,M.morph_room(room,intensity=0.0))

    def test_boss_arenas_are_skipped(self):
        room = fixture()
        room["entities"].append(dict(t="boss_ape",x=96,y=80))
        self.assertEqual(room,M.morph_room(room,intensity=1.0))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.world = self.root/"world"
        self.world.mkdir()
        (self.world/"cave.json").write_text(json.dumps(fixture()))
        (self.world/"town.json").write_text(json.dumps(dict(fixture(),environment="building")))
        (self.world/"world.json").write_text(json.dumps(dict(start="cave",rooms={"cave":[0,0],"town":[40,0]},regions=[dict(name="Caves",rooms=["cave"])])))

    def run_cli(self,*args):
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            return M.main([str(self.world),"--output",str(self.root/"review"),*args])

    def test_preview_selects_region_without_writing_rooms_or_manifest(self):
        original = {p.name:p.read_bytes() for p in self.world.glob("*.json")}
        self.assertEqual(self.run_cli("--region","Caves"),0)
        self.assertEqual(original,{p.name:p.read_bytes() for p in self.world.glob("*.json")})
        report = json.loads((self.root/"review"/"plan.json").read_text())
        self.assertEqual([r["room"] for r in report["rooms"]],["cave"])
        self.assertTrue((self.root/"review"/"index.html").exists())

    def test_apply_and_restore_keep_original_bytes(self):
        path = self.world/"cave.json"
        path.chmod(0o640)
        original = path.read_bytes()
        town = (self.world/"town.json").read_bytes()
        self.assertEqual(self.run_cli("--region","Caves","--apply"),0)
        self.assertNotEqual(path.read_bytes(),original)
        self.assertEqual(path.stat().st_mode & 0o777,0o640)
        self.assertEqual((self.world/"town.json").read_bytes(),town)
        self.assertTrue((self.root/"review"/"backup.json").exists())
        self.assertEqual(self.run_cli("--restore",str(self.root/"review"/"backup.json")),0)
        self.assertEqual(path.read_bytes(),original)

    def test_failed_second_write_rolls_back_the_first_room(self):
        original = {p.name:p.read_bytes() for p in self.world.glob("*.json")}
        write = M.atomic_write
        def fail_on_town(path,data):
            if path == self.world/"town.json": raise OSError("Simulated disk failure")
            write(path,data)
        with patch.object(M,"atomic_write",side_effect=fail_on_town):
            self.assertEqual(self.run_cli("--rooms","cave","town","--apply"),2)
        self.assertEqual(original,{p.name:p.read_bytes() for p in self.world.glob("*.json")})

    def test_restore_refuses_to_overwrite_later_editor_changes(self):
        self.assertEqual(self.run_cli("--region","Caves","--apply"),0)
        path = self.world/"cave.json"
        edited = json.loads(path.read_text())
        edited["name"] = "Edited later"
        path.write_text(json.dumps(edited))
        before = path.read_bytes()
        self.assertEqual(self.run_cli("--restore",str(self.root/"review"/"backup.json")),2)
        self.assertEqual(path.read_bytes(),before)

    def test_invalid_later_room_prevents_partial_application(self):
        original = (self.world/"cave.json").read_bytes()
        (self.world/"town.json").write_text('{"broken":')
        self.assertEqual(self.run_cli("--rooms","cave","town","--apply"),2)
        self.assertEqual((self.world/"cave.json").read_bytes(),original)

    def test_unknown_preset_is_rejected_before_writing(self):
        with self.assertRaises(SystemExit) as exc:
            self.run_cli("--terrain","unsupported-terrain")
        self.assertEqual(exc.exception.code,2)
        self.assertFalse((self.root/"review").exists())

    def test_presets_change_geometry_not_only_palette(self):
        # Long, thick roof gives every brush enough room to express its pattern.
        room = dict(name="Contour sample",w=72,h=24,environment="cavern",
                    tiles=["1"*72]*6+["111"+"0"*66+"111"]*14+["1"*72]*4,entities=[])
        shapes = set()
        for terrain,environment in [("cavern","cavern"),("desert","sand"),("coast","island_shore"),
                                    ("volcanic","volcano"),("forest","forest"),("ruins","temple")]:
            with self.subTest(terrain=terrain):
                result = M.morph_room(room,terrain=terrain,seed=42,intensity=0.7)
                self.assertNotEqual(result["tiles"],room["tiles"])
                shapes.add(tuple(result["tiles"]))
                expected = "cavern" if terrain == "cavern" else environment
                self.assertEqual(result["environment"],expected)
                self.assertEqual(result,M.morph_room(result,terrain=terrain,seed=42,intensity=0.7))
        self.assertEqual(len(shapes),6,"Each preset must create a different contour")

    def test_every_preset_respects_the_same_protected_cells(self):
        room = fixture()
        protected = M.protected_cells(room)
        for terrain in ["cavern","desert","coast","volcanic","forest","ruins"]:
            with self.subTest(terrain=terrain):
                result = M.morph_room(room,terrain=terrain,intensity=1)
                for x,y in protected:
                    self.assertEqual(result["tiles"][y][x],room["tiles"][y][x])
                for y,row in enumerate(room["tiles"]):
                    for x,c in enumerate(row):
                        if c == "0": self.assertEqual(result["tiles"][y][x],"0")
                self.assertEqual(result["entities"],room["entities"])

    def test_preset_defaults_select_compatible_environments(self):
        self.assertEqual(self.run_cli("--terrain","ruins"),0)
        report = json.loads((self.root/"review"/"plan.json").read_text())
        self.assertEqual([r["room"] for r in report["rooms"]],["town"])
        self.assertEqual(report["rooms"][0]["after"]["environment"],"temple")

    def test_terrain_catalog_lists_presets_without_loading_a_world(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(M.main([str(self.root/"missing-world"),"--list-terrains"]),0)
        for name in ["cavern","desert","coast","volcanic","forest","ruins"]:
            self.assertIn(name,out.getvalue())


if __name__ == "__main__":
    unittest.main()
