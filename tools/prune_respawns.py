#!/usr/bin/env python3
"""Remove duplicate checkpoints and keep the closest existing point per entrance.
Preview: python3 tools/prune_respawns.py [world_dir]
Apply: add --apply (exact originals saved in reports/respawn-cleanup/backup.json).
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


def prune(level, entrances, keep_start=False):
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
    level['entities']=[e for e in level['entities'] if e['t'] not in TYPES or any(e is point for point in kept)]
    return len(markers),len(kept)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('world',nargs='?',type=Path,default=Path('worlds/story'))
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    world=json.loads((args.world/'world.json').read_text())
    levels={n:json.loads((args.world/(n+'.json')).read_text()) for n in world['rooms']}
    proposals=[];total_before=total_after=0
    for name in world['rooms']:
        level=json.loads(json.dumps(levels[name]))
        before,after=prune(level,entrance_points(world,levels,name),name==world['start'])
        total_before+=before;total_after+=after
        if before!=after:
            print(f'{name}: {before} -> {after}')
            proposals.append((name,level))
    # Variants share entrances but retain their own authored checkpoint list.
    for name,variants in world.get('variants',{}).items():
        for variant in variants:
            target=variant['room'];level=json.loads((args.world/(target+'.json')).read_text())
            before,after=prune(level,entrance_points(world,levels,name),name==world['start'])
            if before!=after:
                print(f'{target}: {before} -> {after}')
                proposals.append((target,level))
    if args.apply and proposals:
        report=Path('reports/respawn-cleanup');report.mkdir(parents=True,exist_ok=True)
        backup=report/'backup.json'
        if backup.exists(): raise SystemExit('Backup exists; use a fresh report directory before another application')
        backup.write_text(json.dumps({n:(args.world/(n+'.json')).read_text() for n,_ in proposals},indent=2)+'\n')
        for name,level in proposals:(args.world/(name+'.json')).write_text(json.dumps(level,indent='\t')+'\n')
    print(f'{"Applied" if args.apply else "Preview"}: {total_before} -> {total_after} main-world checkpoints')


if __name__=='__main__': main()
