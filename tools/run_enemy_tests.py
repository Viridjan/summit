"""Run the existing enemy regression checks without loading unrelated test groups.

Stages selected test helpers from test_runner.gd in a disposable Godot scene.
The complete suite remains: godot --headless --path . res://tests/test.tscn
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def block(source, kind, name):
    match = re.search(rf'^{kind} {re.escape(name)}\b[^\n]*\n', source, re.M)
    if not match:
        raise ValueError(f'Missing test helper: {name}')
    next_declaration = re.search(r'^(?:func |class |var |const )', source[match.end():], re.M)
    end = match.end() + next_declaration.start() if next_declaration else len(source)
    return source[match.start():end].rstrip() + '\n\n'


def main():
    source = (ROOT / 'tests/test_runner.gd').read_text()
    script = 'extends Node\nconst PlayerScript := preload("res://scripts/player.gd")\nconst E := preload("res://scripts/entities.gd")\nconst DT := 1.0 / 60.0\n\n'
    for name in ['Bot', 'EnemyDrawTexture', 'EnemyDrawProbe']:
        script += block(source, 'class', name)
    script += 'var fails := 0\nvar w\n\n'
    checks = ['check_enemy_facing_alignment', 'check_combat_enemies', 'check_enemy_variants', 'check_hk_combat_placements']
    for name in ['check', 'make_world', 'step', 'p', *checks]:
        script += block(source, 'func', name)
    script += '''func _ready() -> void:
	Game.settings.air_dashes = 0
	Game.settings.infinite_stamina = false
	Game.settings.invincible = false
	Game.settings.shake = false
	await check_enemy_facing_alignment()
	check_combat_enemies()
	check_enemy_variants()
	check_hk_combat_placements()
	print("\\n%d focused enemy failure(s)" % fails)
	get_tree().quit(fails)
'''
    with tempfile.TemporaryDirectory(prefix='summit-enemy-checks-') as temporary:
        stage = Path(temporary)
        script_path = stage / 'enemy_tests.gd'
        script_path.write_text(script)
        scene = stage / 'enemy_tests.tscn'
        scene.write_text('[gd_scene load_steps=2 format=3]\n'
                         f'[ext_resource type="Script" path="{script_path}" id="1"]\n'
                         '[node name="EnemyChecks" type="Node"]\nscript = ExtResource("1")\n')
        environment = os.environ.copy()
        environment['XDG_DATA_HOME'] = str(stage / 'runtime')
        try:
            result = subprocess.run(['godot', '--headless', '--path', str(ROOT), str(scene)], env=environment, timeout=120)
        except subprocess.TimeoutExpired:
            print('Enemy tests timed out; inspect the Godot errors above.')
            return 2
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
