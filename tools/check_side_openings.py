"""Find open left/right terrain edges facing no room or solid neighbouring terrain."""
import argparse
import json
from pathlib import Path


def audit(directory):
    directory = Path(directory)
    manifest = json.loads((directory / 'world.json').read_text())
    rooms = {name: (pos, json.loads((directory / (name + '.json')).read_text())) for name, pos in manifest['rooms'].items()}
    findings = []
    checked = 0
    for name, (pos, level) in rooms.items():
        for side in ('left', 'right'):
            sx = 0 if side == 'left' else level['w'] - 1
            gx = pos[0] - 1 if side == 'left' else pos[0] + level['w']
            pending = None
            for y in range(level['h'] + 1):
                reason = target = None
                if y < level['h'] and level['tiles'][y][sx] != '1':
                    checked += 1
                    gy = pos[1] + y
                    matches = [(rn, rp, rl) for rn, (rp, rl) in rooms.items() if rn != name and rp[0] <= gx < rp[0] + rl['w'] and rp[1] <= gy < rp[1] + rl['h']]
                    # Runtime prefers an open room if rectangles overlap, otherwise the first solid one.
                    open_matches = [m for m in matches if m[2]['tiles'][gy - m[1][1]][gx - m[1][0]] != '1']
                    if not matches:
                        reason = 'no_adjacent_room'
                    elif not open_matches:
                        reason, target = 'neighbour_wall', matches[0][0]
                key = (reason, target) if reason else None
                if pending and pending['_key'] != key:
                    pending['y_end_px_exclusive'] = y * 8
                    pending.pop('_key')
                    findings.append(pending)
                    pending = None
                if reason and pending is None:
                    pending = {'source': name, 'side': side, 'reason': reason, 'target': target,
                               'boundary_x_local_px': 0 if side == 'left' else level['w'] * 8,
                               'y_start_px': y * 8, '_key': key,
                               'world_boundary_tile': [pos[0] if side == 'left' else pos[0] + level['w'], pos[1] + y]}
    return {'world': str(directory), 'room_count': len(rooms), 'checked_open_edge_tiles': checked,
            'findings': findings, 'limits': 'Static terrain edge checks, not spawn reachability. Counts maximal adjacent vertical spans with the same issue/target, not separate tiles. Does not flag sealed solid edges. Valid adjacent empty tiles still need whole-player clearance and movement checks. A no-room opening can be intentionally clamped by player bounds; it is not automatically a playable exit or an out-of-bounds exploit.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('world', nargs='?', default='worlds/story')
    parser.add_argument('--output', type=Path, default=Path('reports/story-side-openings.json'))
    args = parser.parse_args()
    result = audit(args.world)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"Checked {result['checked_open_edge_tiles']} open edge tiles; {len(result['findings'])} bad opening spans in {len({f['source'] for f in result['findings']})} rooms")
    for reason in ('no_adjacent_room', 'neighbour_wall'):
        print(reason, sum(f['reason'] == reason for f in result['findings']))


if __name__ == '__main__':
    main()
