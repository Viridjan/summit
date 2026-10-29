"""Respawn placement requires permanent solid terrain, never entity platforms."""
def solid_ground(level, x, y):
    if y % 8: return False
    row=y//8
    if not (0<=x and x+8<=level['w']*8 and 1<=row<level['h']-1): return False
    tiles=level['tiles']
    columns=range(x//8,(x+7)//8+1)
    if any(tiles[row][column]!='0' or tiles[(y-3)//8][column]!='0' for column in columns): return False
    if any(tiles[row+1][px//8]!='1' for px in range(x+1,x+7)): return False
    left,top,right,bottom=x,y-3,x+8,y+8
    for entity in level['entities']:
        kind=entity['t']
        if kind not in ('water','acid','breakwall','crumble','falling','zip','dream','boss_gate') and not kind.startswith('spikes'): continue
        ex,ey=entity['x'],entity['y'];ew,eh=entity.get('w',8),entity.get('h',8)
        if max(left,ex)<min(right,ex+ew) and max(top,ey)<min(bottom,ey+eh): return False
    return True


def floor_below(level, x, y):
    return next(((x,cy) for cy in range(y,level['h']*8,8) if solid_ground(level,x,cy)),None)
