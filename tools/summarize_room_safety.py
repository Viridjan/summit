"""Combine runtime transition probes, replay traces and side-opening checks into one report."""
import argparse
from collections import Counter
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--transitions', type=Path, default=Path('reports/hk-room-safety.json'))
    parser.add_argument('--edges', type=Path, help='Optional denser edge sweep overriding the edge portion')
    parser.add_argument('--replays', type=Path, default=Path('reports/hk-room-safety-replays.json'))
    parser.add_argument('--openings', type=Path, default=Path('reports/hk-side-openings.json'))
    parser.add_argument('--output', type=Path, default=Path('reports/hk-room-safety.md'))
    args = parser.parse_args()
    runtime = json.loads(args.transitions.read_text())
    if args.edges:
        edges = json.loads(args.edges.read_text())
        runtime['finding_groups'] = [g for g in runtime['finding_groups'] if 'edge' not in g['samples'][0] or g['kind'] != 'embedded_arrival'] + edges['finding_groups']
        for key in ('edge_candidates', 'edge_valid_starts', 'edge_crossings'):
            runtime['counts'][key] = edges['counts'][key]
        runtime['step_sizes_px'] = edges['step_sizes_px']
    replay = json.loads(args.replays.read_text())
    openings = json.loads(args.openings.read_text())
    combined = {'transitions': runtime, 'replays': replay['replays'], 'side_openings': openings}
    json_path = args.output.with_name(args.output.stem + '-combined.json')
    json_path.write_text(json.dumps(combined, indent=2) + '\n')
    groups = runtime['finding_groups']
    seam = [g for g in groups if g['kind'] == 'embedded_arrival' and 'edge' in g['samples'][0]]
    door = [g for g in groups if g['kind'] == 'embedded_arrival' and 'door' in g['samples'][0]]
    bounds = [g for g in groups if g['kind'] != 'embedded_arrival']
    causes = Counter(f['reason'] for f in openings['findings'])
    lines = ['# Hallownest room-transition and boundary safety', '',
             f"World: `{runtime['world']}` — {runtime['room_count']} rooms. Game data and gameplay code were not changed.", '',
             '## Results', '',
             f"- **{len(seam)} directed room-edge connections** produced collision-overlapping arrivals ({sum(g['occurrences'] for g in seam):,} failing probes).",
             f"- **{len(door)} door connection** produced collision-overlapping arrivals ({sum(g['occurrences'] for g in door):,} failing probes).",
             f"- **{len(bounds)} upward boundary locations** allowed the player past the normal 24px ceiling allowance with the centre outside every room.",
             f"- **{len(openings['findings'])} bad left/right opening spans in {len({f['source'] for f in openings['findings']})} rooms:** {causes['no_adjacent_room']} face no neighbouring room; {causes['neighbour_wall']} face a neighbour's solid terrain.", '',
             'The five representative 60 Hz replays below reproduce failures using actual player updates, dash input, collision callbacks, entity touches, room changes, and dash freeze timing. They start from seeded collision-free local positions, not from a demonstrated route from the world spawn. All five remained embedded through tick 89 while the scripted direction was held. This confirms local failures without claiming every seed is reachable in normal progression or that no recovery input could ever work.', '',
             '## Reproduced examples', '',
             '| Source and action | Start feet position, local px | Result |', '|---|---|---|']
    for case in replay['replays']:
        source = case['case']
        trace = case['trace']
        overlap = next((t for t in trace if t['embedded']), None)
        escaped = next((t for t in trace if t['outside_allowance']), None)
        result = f"Embedded in `{overlap['room']}` at {overlap['position']} on tick {overlap['tick']}" if overlap else 'No overlap reproduced'
        if escaped:
            result += f"; outside room union beyond ceiling allowance on tick {escaped['tick']}"
        lines.append(f"| `{source['room']}` — {source['label']} | {source['at']} | {result} |")
    lines += ['', 'Tick numbers are zero-based, at 60 Hz. Start coordinates refer to the player’s feet, not the top-left of the sprite.', '',
              '## Why these fail', '',
              '- Edge movement collides only against the current room. The room changes after the player centre crosses the boundary; terrain in the destination can already overlap the body. `Adventure.room_at` can also return a solid-room fallback. Entry does not reject or resolve the collision.',
              '- Door arrivals clamp the player to the target doorway rectangle but do not validate that the hitbox is free of terrain. The reproduced `r023:d8 → r039:d9` case places the player at `(156,24)` inside terrain.',
              '- Ceiling bounds consult a point at the top of the hitbox, while room changes use the centre. Across a gap between room rectangles, that point can already be in another room while the centre is still in unassigned space. In the three replayed cases this lasts one frame and is followed by embedding in the upper room.',
              '- An opening facing no room is often stopped by the horizontal bounds clamp. It is a visual/map-connectivity defect, not automatically an out-of-bounds exploit. Wall-facing openings are more dangerous because `can_exit` accepts the neighbour rectangle even where its terrain is solid.', '',
              '## Coverage and limits', '',
              f"- Tested {runtime['counts']['edge_valid_starts']:,} valid seeded edge starts; {runtime['counts']['edge_crossings']:,} crossings. All integer seam alignments, both directions, standing/crouched, with {runtime.get('step_sizes_px', [1])} pixel movement batches.",
              f"- Tested {runtime['counts']['door_valid_starts']:,} valid integer doorway-contact offsets and {runtime['counts']['bounds_valid_starts']:,} valid outer-edge starts.",
              '- Probe runner uses the real movement, bounds, door and room-entry methods. Rendering and save writes are disabled; static room collision structures are cached. General edge probes isolate cardinal movement and omit ordinary hazard touches; full-update replays do include touches.',
              '- Outer-boundary sweep uses 1px cardinal movement. The normal 24px top allowance and the brief bottom death margin are excluded from failures. Invincibility is off.',
              '- This is not exhaustive over every velocity, subpixel remainder, diagonal input, movement state, moving obstacle, or recovery sequence. No claim is made that all remaining locations are safe.',
              '- Side openings are maximal contiguous vertical terrain spans with the same issue and target. A two-tile opening counts as one span. Other valid-looking openings can still be too small for the complete player hitbox.', '',
              '## Re-run', '', '```sh',
              'godot --headless --path . res://tools/room_safety.tscn',
              'godot --headless --path . res://tools/room_safety.tscn -- --phase replay --output res://reports/hk-room-safety-replays.json',
              'python3 tools/check_side_openings.py',
              'python3 tools/summarize_room_safety.py', '```', '',
              'Runtime checker exits 1 when it reproduces a failure, 0 when the selected checks find none, and 2 for invalid configuration/output. Use a disposable `XDG_DATA_HOME` for sandbox runs, e.g. `env XDG_DATA_HOME=/tmp/summit-room-safety godot ...`. It never writes the gameplay adventure save. The replay phase contains HK-specific seeds. Other worlds can use `--world res://adventure/world.json --output /tmp/adventure-safety.json` for edge/door/bounds sweeps.', '',
              '## All failing room connections', '', '| Type | Source → target | Failing probes | Sample start → arrival (local px) |', '|---|---|---:|---|']
    for group in sorted(groups, key=lambda g: (g['kind'], g['source'], g['target'])):
        sample = group['samples'][0]
        kind = 'door ' + sample['door'] if 'door' in sample else group['kind']
        lines.append(f"| {kind} | `{group['source']} → {group['target']}` | {group['occurrences']} | {sample['start_local_px']} → {sample['arrival_local_px']} |")
    lines += ['', '## All bad left/right openings', '', '| Room | Side | Local vertical span (px, end exclusive) | Faces |', '|---|---|---|---|']
    for item in openings['findings']:
        target = 'No adjacent room' if item['reason'] == 'no_adjacent_room' else f"Solid wall in `{item['target']}`"
        lines.append(f"| `{item['source']}` | {item['side']} | {item['y_start_px']}–{item['y_end_px_exclusive']} | {target} |")
    args.output.write_text('\n'.join(lines) + '\n')
    print(f"Wrote {args.output} and {json_path}")


if __name__ == '__main__':
    main()
