#!/usr/bin/env python3
"""Background World Editor job: snapshot a world, generate HTML and publish status."""
import argparse
from contextlib import redirect_stderr, redirect_stdout
import json
from pathlib import Path
import shutil
import time
import traceback
import progression


def write_status(output, **values):
    target = output / 'status.json'
    temporary = output / 'status.tmp'
    temporary.write_text(json.dumps(values, indent=2) + '\n')
    temporary.replace(target)


def snapshot_world(source, target):
    manifest = json.loads((source / 'world.json').read_text())
    names = list(manifest['rooms'])
    names += [v['room'] for variants in manifest.get('variants', {}).values() for v in variants]
    target.mkdir(parents=True, exist_ok=True)
    for name in dict.fromkeys(names):
        relative = Path(name + '.json')
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Invalid room path: ' + name)
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, destination)
    (target / 'world.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return target


def run_job(world_dir, output_dir):
    source, output = Path(world_dir).resolve(), Path(output_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    info = dict(world=str(source), report=str(output / 'index.html'), started=time.time())
    write_status(output, state='running', **info)
    with (output / 'analysis.log').open('w') as log, redirect_stdout(log), redirect_stderr(log):
        try:
            snapshot = snapshot_world(source, output / 'snapshot')
            world, nodes, order = progression.build(str(snapshot))
            world.dir = str(snapshot)
            page = progression.page(world, nodes, order)
            temporary = output / 'index.tmp'
            temporary.write_text(page)
            temporary.replace(output / 'index.html')
            write_status(output, state='complete', finished=time.time(), **info)
            return 0
        except Exception as error:
            traceback.print_exc()
            write_status(output, state='failed', error=str(error), finished=time.time(), **info)
            return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    return run_job(args.world, args.output)


if __name__ == '__main__':
    raise SystemExit(main())
