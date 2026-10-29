"""Extend the four beaches and connect them by explicit destination panels.

python3 tools/story/link_shores.py worlds/story
The original North Shore coast_path panel leads west. Repeated runs are no-ops.
"""
import copy
import itertools
import json
import sys
from pathlib import Path

SHORES = {"west":"i01_west_shore","north":"i02_north_shore",
          "south":"i03_south_shore","east":"i08_east_shore"}


def panel_id(source,target):
    return "coast_path" if (source,target) == ("north","west") else "to_"+target


def apply(directory):
    directory = Path(directory)
    def load(name): return json.loads((directory/(name+".json")).read_text())
    def save(name,value):
        path=directory/(name+".json")
        if path.exists() and json.loads(path.read_text()) == value: return
        path.write_text(json.dumps(value,indent="\t")+"\n")
    world=load("world")
    data={name:load(name) for name in world["rooms"]}
    old_west=copy.deepcopy(data[SHORES["west"]])
    variant_name="i01_west_shore_after"
    variant=load(variant_name)
    extras=[e for e in variant["entities"] if e not in old_west["entities"] and not e.get("shore_panel")]
    changed=set()
    for side,name in SHORES.items():
        room=data[name]
        old_width,height=room["w"],room["h"]
        floor=height-3
        grid=list(map(list,room["tiles"]))
        if old_width < 120:
            edge=[row[-1] for row in grid]
            grid=[row+["1"]*(120-old_width) for row in grid]
            top=2 if side in ("west","south") else 1
            for y in range(top,floor):
                for x in range(old_width-1,119): grid[y][x]="0"
            for y in range(height): grid[y][119]=edge[y]
            room["w"]=120
            # Short, recoverable pools and low rock shelves vary the long beach.
            for x in (46,86):
                if x < old_width: continue
                for y in (floor,floor+1):
                    for cx in range(x,x+3): grid[y][cx]="0"
                room["entities"].append(dict(t="water",x=x*8,y=floor*8,w=24,h=16,shore_extension=True))
            for x,width,rise in [(54,3,1),(74,4,2),(96,3,1)]:
                if x < old_width: continue
                for y in range(floor-rise,floor):
                    for cx in range(x,x+width): grid[y][cx]="1"
        # Close the old vertical shore links and remove their obsolete ladders.
        if side == "west":
            for y in (0,1):
                for x in range(33,39): grid[y][x]="1"
            for y in range(floor,height):
                for x in range(30,34): grid[y][x]="1"
            room["entities"]=[e for e in room["entities"] if not (e["t"] == "jumpthru" and
                ((e["x"] in (208,264) and e["y"] <= 144) or (e["x"] == 240 and e["y"] == 160)))]
        elif side == "north":
            for y in range(floor,height):
                for x in range(33,39): grid[y][x]="1"
            room["entities"]=[e for e in room["entities"] if not (e["t"] == "jumpthru" and e["x"] == 264 and e["y"] == floor*8)]
        elif side == "south":
            for y in (0,1):
                for x in range(30,34): grid[y][x]="1"
            room["entities"]=[e for e in room["entities"] if not (e["t"] == "jumpthru" and e["x"] in (176,232) and e["y"] <= 120)]
        room["tiles"]=["".join(row) for row in grid]
        room["entities"]=[e for e in room["entities"] if not e.get("shore_panel") and not (
            e.get("skin") == "signpost" and e.get("to","").split(":")[0] in SHORES.values())]
        destinations=[target for target in SHORES if target != side]
        positions={"west":[40,60,110],"north":[11,60,110],"south":[30,60,110],"east":[10,60,110]}[side]
        for target,x in zip(destinations,positions):
            room["entities"].append(dict(t="house_door",skin="signpost",shore_panel=True,
                x=x*8,y=(floor-3)*8,w=16,h=24,id=panel_id(side,target),
                to=SHORES[target]+":"+panel_id(target,side),direction=target,label=target.title()+" Shore"))
            spawn=dict(t="spawn",x=x*8+4,y=(floor-1)*8,entrance=True,shore_panel=True)
            room["entities"].append(spawn)
        changed.add(name)
    # Preserve the mountain link at West Shore's new eastern edge. Its complete
    # volcano/maze block moves together, retaining the existing tunnel and routes.
    wx,wy=world["rooms"][SHORES["west"]]
    delta=wx+data[SHORES["west"]]["w"]-world["rooms"]["i04_foothills"][0]
    for region in world["regions"]:
        if region["name"] in ("Volcano","Volcanic Maze"):
            for name in region["rooms"]: world["rooms"][name][0]+=delta
    sx,sy=world["rooms"]["i07_east_slope"]
    world["rooms"][SHORES["east"]][0]=sx+data["i07_east_slope"]["w"]
    east_end=world["rooms"][SHORES["east"]][0]+data[SHORES["east"]]["w"]
    world["rooms"][SHORES["north"]]=[east_end+52,wy]
    world["rooms"][SHORES["south"]]=[east_end+212,wy]
    for a,b in itertools.combinations(world["rooms"],2):
        ax,ay=world["rooms"][a];bx,by=world["rooms"][b]
        if max(ax,bx)<min(ax+data[a]["w"],bx+data[b]["w"]) and max(ay,by)<min(ay+data[a]["h"],by+data[b]["h"]):
            raise ValueError(f"Shore extension would overlap {a} and {b}")
    for name in changed: save(name,data[name])
    post=copy.deepcopy(data[SHORES["west"]])
    post["entities"].extend(e for e in extras if e not in post["entities"])
    save(variant_name,post)
    save("world",world)
    print("Extended all shores to 120 tiles; installed 12 destination panels; detached North/South; mountain and maze links retained")


if __name__ == "__main__":
    apply(sys.argv[1] if len(sys.argv)>1 else "worlds/story")
