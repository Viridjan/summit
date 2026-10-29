#!/usr/bin/env python3
"""Remove duplicate checkpoints and merge nearby checkpoints on safe shared landings.
Preview: python3 tools/prune_respawns.py [world_dir]
Apply: add --apply --output REPORT_DIR (exact originals saved in backup.json).
See docs/RESPAWN_POINTS.md for rules and examples.
"""
import argparse
import json
from pathlib import Path

TYPES = {'spawn', 'respawn'}


def entrance_points(world, levels, name):
    level = levels[name]
    ox, oy = world['rooms'][name]
    owners = {}
    for other, (rx, ry) in world['rooms'].items():
        if other == name: continue
        room = levels[other]
        for y, row in enumerate(room['tiles']):
            for x, tile in enumerate(row):
                if tile == '0': owners[(rx+x, ry+y)] = other
    points = []
    for side in 'lrtb':
        run, previous = [], None
        for i in range((level['h'] if side in 'lr' else level['w'])+1):
            x,y = {'l':(0,i),'r':(level['w']-1,i),'t':(i,0),'b':(i,level['h']-1)}[side]
            dx,dy = {'l':(-1,0),'r':(1,0),'t':(0,-1),'b':(0,1)}[side]
            other = owners.get((ox+x+dx,oy+y+dy)) if 0<=x<level['w'] and 0<=y<level['h'] and level['tiles'][y][x]=='0' else None
            if run and other != previous:
                points.append((sum(p[0] for p in run)/len(run)*8,sum(p[1] for p in run)/len(run)*8))
                run=[]
            if other: run.append((x,y))
            previous=other
    for entity in level['entities']:
        if entity['t'] in ('door','house_door') and entity.get('to'):
            points.append((entity['x']+entity.get('w',8)/2,entity['y']+entity.get('h',8)-8))
    return points


def shared_landing(level, a, b, distance=48):
    """Nearby floor checkpoints can share a flat, hazard-free walk (bridges allowed)."""
    if 'tiles' not in level or a['y'] != b['y'] or abs(a['x']-b['x']) > distance: return False
    from checkpoint_ground import solid_ground
    if not all(solid_ground(level,int(e['x']),int(e['y'])) for e in (a,b)): return False
    y=int(a['y']);feet=y+8
    platforms=[e for e in level['entities'] if e['t']=='jumpthru' and e['y']==feet]
    for x in range(int(min(a['x'],b['x'])),int(max(a['x'],b['x']))+1):
        for px in (x,x+7):
            if level['tiles'][y//8][px//8]!='0' or level['tiles'][(y-3)//8][px//8]!='0': return False
        for px in range(x+1,x+7):
            if level['tiles'][feet//8][px//8]!='1' and not any(e['x']<=px<e['x']+e.get('w',8) for e in platforms): return False
        for e in level['entities']:
            kind=e['t']
            if kind not in ('water','acid','breakwall','crumble','falling','zip','dream','boss_gate') and not kind.startswith(('spikes','enemy','boss_')): continue
            if max(x,e['x'])<min(x+8,e['x']+e.get('w',8)) and max(y-3,e['y'])<min(feet,e['y']+e.get('h',8)): return False
    return True


def prune(level, entrances, keep_start=False, merge_distance=48):
    markers = [e for e in level['entities'] if e['t'] in TYPES]
    # Prefer the original start-marker type when old and new aliases overlap.
    unique=[]
    for entity in sorted(markers,key=lambda e:e['t']!='spawn'):
        if not any(entity['y']==e['y'] and abs(entity['x']-e['x'])<=16 for e in unique): unique.append(entity)
    kept=[]
    for x,y in entrances:
        if unique:
            marker=min(unique,key=lambda e:abs(e['x']-x)+abs(e['y']-y))
            if marker not in kept: kept.append(marker)
    starts=[e for e in markers if e['t']=='spawn']
    if keep_start and starts:
        start=starts[-1]
        kept=[e for e in kept if e is start or not (e['y']==start['y'] and abs(e['x']-start['x'])<=16)]
        if start not in kept: kept.append(start)
    if not kept and unique: kept=[unique[0]]
    locked=starts[-1] if keep_start and starts else None
    # Anchor to the actual entrance rather than an intermediate landing.
    rank=lambda e:(e is not locked,min((abs(e['x']-x)+abs(e['y']-y) for x,y in entrances),default=0))
    accepted=[]
    for marker in sorted(kept,key=rank):
        if marker is locked or not any(shared_landing(level,marker,other,merge_distance) for other in accepted): accepted.append(marker)
    kept=accepted
    level['entities']=[e for e in level['entities'] if e['t'] not in TYPES or any(e is point for point in kept)]
    return len(markers),len(kept)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('world',nargs='?',type=Path,default=Path('worlds/story'))
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--output',type=Path,default=Path('reports/respawn-cleanup'),help='Report and backup directory')
    parser.add_argument('--rooms',nargs='+',help='Only inspect these room IDs')
    parser.add_argument('--merge-distance',type=int,default=48,help='Maximum shared-landing distance in pixels (default 48 / 6 tiles)')
    args=parser.parse_args()
    if args.merge_distance < 0: parser.error('--merge-distance must be nonnegative')
    world=json.loads((args.world/'world.json').read_text())
    levels={n:json.loads((args.world/(n+'.json')).read_text()) for n in world['rooms']}
    proposals=[];total_before=total_after=0
    if args.rooms and set(args.rooms)-set(world['rooms']): parser.error('Unknown room IDs')
    for name in world['rooms']:
        if args.rooms and name not in args.rooms: continue
        level=json.loads(json.dumps(levels[name]))
        before,after=prune(level,entrance_points(world,levels,name),name==world['start'],args.merge_distance)
        total_before+=before;total_after+=after
        if before!=after:
            print(f'{name}: {before} -> {after}')
            proposals.append((name,level))
    # Variants share entrances but retain their own authored checkpoint list.
    for name,variants in world.get('variants',{}).items():
        if args.rooms and name not in args.rooms: continue
        for variant in variants:
            target=variant['room'];level=json.loads((args.world/(target+'.json')).read_text())
            before,after=prune(level,entrance_points(world,levels,name),name==world['start'],args.merge_distance)
            if before!=after:
                print(f'{target}: {before} -> {after}')
                proposals.append((target,level))
    if args.apply and proposals:
        report=args.output;report.mkdir(parents=True,exist_ok=True)
        backup=report/'backup.json'
        if backup.exists(): raise SystemExit('Backup exists; use a fresh report directory before another application')
        backup.write_text(json.dumps({n:(args.world/(n+'.json')).read_text() for n,_ in proposals},indent=2)+'\n')
        for name,level in proposals:(args.world/(name+'.json')).write_text(json.dumps(level,indent='\t')+'\n')
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'summary.json').write_text(json.dumps({'applied':args.apply,'before':total_before,'after':total_after,'merge_distance':args.merge_distance,'rooms':[n for n,_ in proposals]},indent=2)+'\n')
    print(f'{"Applied" if args.apply else "Preview"}: {total_before} -> {total_after} main-world checkpoints')


if __name__=='__main__': main()
