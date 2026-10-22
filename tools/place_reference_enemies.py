"""Install a small, deterministic enemy set by replacing existing HK placeholders.
Only entities change. Re-run safely: converted placeholders are tagged and not duplicated.
Placements of kinds no longer in SIZES turn back into their original placeholder first.
"""
import argparse
from collections import Counter
import json
import math
from pathlib import Path

# family: (body size, name, variants) -- matches Entities.TYPES; a giant's body is twice the size
FAMILIES = {
    'thornmite': ((8, 8), 'Thornmite', ['swift', 'venom', 'brood', 'giant']),
    'skree': ((8, 12), 'Dropwing', ['swift', 'armored', 'venom']),
    'bat': ((10, 8), 'Duskflit', ['swift', 'brood']),
    'skeleton': ((8, 12), 'Ossling', ['armored', 'shielded', 'giant']),
    'hornback': ((12, 10), 'Hornback', ['shielded', 'swift', 'giant']),
    'fuzzbob': ((10, 10), 'Fuzzbob', ['brood', 'venom', 'giant']),
    'cragjaw': ((20, 20), 'Cragjaw', ['armored', 'shielded']),
    'murkspore': ((16, 14), 'Murkspore', ['swift', 'venom', 'brood']),
}
NAMES = {family: spec[1] for family, spec in FAMILIES.items()}
FLOOR_WALKERS = ('thornmite', 'skeleton', 'hornback', 'cragjaw')
SIZES = {}
for family, (size, _, variants) in FAMILIES.items():
    for variant in [''] + variants:
        SIZES[family + ('_' + variant if variant else '')] = (size[0] * 2, size[1] * 2) if variant == 'giant' else size
ROOMS = ['r005', 'r007', 'r012', 'r017', 'r018', 'r023', 'r025', 'r027', 'r029', 'r038', 'r039', 'r041', 'r045', 'r057', 'r062', 'r064', 'r067', 'r069', 'r070', 'r083', 'r090', 'r097']


def intersects(a, b):
    return a[0] < b[0] + b[2] and a[0] + a[2] > b[0] and a[1] < b[1] + b[3] and a[1] + a[3] > b[1]


def free(level, box):
    x, y, width, height = box
    if x < 16 or y < 16 or x + width > level['w'] * 8 - 16 or y + height > level['h'] * 8 - 16:
        return False
    return all(level['tiles'][ty][tx] == '0' for ty in range(math.floor(y / 8), math.ceil((y + height) / 8)) for tx in range(math.floor(x / 8), math.ceil((x + width) / 8)))


def valid(level, kind, x, y):
    width, height = SIZES[kind]
    base = kind.split('_')[0]
    reach = 40 if base in ('fuzzbob', 'murkspore') else 24
    box = (x, y, width, height)
    if not free(level, box):
        return False
    if base in FLOOR_WALKERS:
        floor = (y + height) // 8
        tx = x // 8
        if (y + height) % 8 or not (3 <= tx < level['w'] - 4) or floor >= level['h']:
            return False
        end = (x + width - 1) // 8
        if end + 4 > level['w'] or not all(level['tiles'][floor][i] == '1' for i in range(tx - 3, end + 4)):
            return False
        if not free(level, (x - 24, y, width + 48, height)):
            return False
        area = (x - 24, y - 16, width + 48, height + 16)
    elif base in ('skree', 'bat'):
        tx, ty = x // 8, y // 8
        if y % 8 or ty < 1 or level['tiles'][ty - 1][tx] != '1':
            return False
        if not free(level, (x - 8, y, width + 16, 64)):
            return False
        area = (x - 20, y, width + 40, 80)
    else:
        padding = 12 if base in ('fuzzbob', 'murkspore') else 0
        area = (x - reach, y - padding, width + reach * 2, height + padding * 2)
        if not free(level, area):
            return False
    for entity in level['entities']:
        ex, ey = entity['x'], entity['y']
        kind_id = entity['t']
        if kind_id in ('spawn', 'door') and math.hypot(ex - x, ey - y) < 96:
            return False
        if entity.get('summit_enemy_set') and math.hypot(ex - x, ey - y) < 88:
            return False
        if kind_id == 'acid' or kind_id.startswith('spikes_') or kind_id == 'breakwall':
            if intersects(area, (ex - 8, ey - 8, entity.get('w', 8) + 16, entity.get('h', 8) + 16)):
                return False
    return True


def install(root, per_type=3, apply=False):
    manifest = json.loads((root / 'world.json').read_text())
    ordered_rooms = ROOMS + [room for room in manifest['rooms'] if room not in ROOMS]
    levels = {room: json.loads((root / (room + '.json')).read_text()) for room in ordered_rooms}
    changed = set()
    kept = Counter()
    for room, level in levels.items():
        for i, e in enumerate(level['entities']):
            if not e.get('summit_enemy_set'):
                continue
            kind = e['t'].removeprefix('enemy_')
            kept[kind] += 1
            if kind not in SIZES or kept[kind] > per_type:  # removed kind or one too many: back to the placeholder
                w, h = e.get('reference_size', (16, 16))
                level['entities'][i] = {'t': 'enemy', 'x': e['reference_position'][0], 'y': e['reference_position'][1], 'w': w, 'h': h, 'text': e['reference_text']}
                changed.add(room)
            elif e.get('text') != NAMES[kind.split('_')[0]]:
                e['text'] = NAMES[kind.split('_')[0]]
            if kind in SIZES and (e.get('w'), e.get('h')) != SIZES[kind]:
                e['w'], e['h'] = SIZES[kind]
                changed.add(room)
    counts = Counter(e['t'].removeprefix('enemy_') for level in levels.values() for e in level['entities'] if e.get('summit_enemy_set'))
    placements = []
    # Interleave types/rooms so one room does not become a crowded enemy showcase.
    for iteration in range(per_type):
        for kind in SIZES:
            if counts[kind] >= per_type:
                continue
            placed = False
            for room in ordered_rooms:
                level = levels[room]
                if sum(bool(e.get('summit_enemy_set')) for e in level['entities']) >= (2 if room != 'r005' else 1):
                    continue
                originals = [(i, e) for i, e in enumerate(level['entities']) if e['t'] == 'enemy' and not str(e.get('text', '')).startswith('Boss:')]
                for index, original in originals:
                    ex, ey = int(original['x']) // 8, int(original['y']) // 8
                    offsets = sorted(((dx, dy) for dx in range(-6, 7) for dy in range(-8, 9)), key=lambda p: (abs(p[0]) + abs(p[1]), p[1], p[0]))
                    for dx, dy in offsets:
                        x, y = (ex + dx) * 8, (ey + dy) * 8
                        if kind.split('_')[0] in FLOOR_WALKERS:
                            y += -SIZES[kind][1] % 8  # feet on the 8px floor grid
                        if valid(level, kind, x, y):
                            entity = dict(original)
                            entity.update(t='enemy_' + kind, x=x, y=y, w=SIZES[kind][0], h=SIZES[kind][1], text=NAMES[kind.split('_')[0]], summit_enemy_set=1, reference_text=original.get('text', ''), reference_position=[original['x'], original['y']], reference_size=[original.get('w', 16), original.get('h', 16)], patrol=40)
                            level['entities'][index] = entity
                            changed.add(room)
                            counts[kind] += 1
                            placements.append({'room': room, **entity})
                            placed = True
                            break
                    if placed:
                        break
                if placed:
                    break
            if not placed:
                print('No safe slot for', kind, 'copy', iteration + 1)
    if apply:
        for room in sorted(changed):
            (root / (room + '.json')).write_text(json.dumps(levels[room], separators=(',', ':')) + '\n')
    existing = [{'room': room, **entity} for room, level in levels.items() for entity in level['entities'] if entity.get('summit_enemy_set')]
    return {'counts': dict(counts), 'changed_rooms': sorted(changed), 'placements': existing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    report = install(Path('worlds/hollow_knight'), apply=args.apply)
    print(json.dumps({'counts': report['counts'], 'changed_rooms': report['changed_rooms']}, indent=2))
    if args.apply:
        Path('reports/hk-enemy-placements.json').write_text(json.dumps(report, indent=2) + '\n')
    if any(report['counts'].get(kind, 0) < 3 for kind in SIZES):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
