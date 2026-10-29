"""Connect i09 under Foothills, shift the maze as a unit, and link shore signs.

Run on the compact island: python3 tools/story/link_island_routes.py worlds/story
Preserves the maze's internal room offsets and the authored room contents.
"""
import itertools
import json
import sys
from pathlib import Path


def apply(directory):
    directory = Path(directory)
    def load(name):
        return json.loads((directory/(name+".json")).read_text())
    def save(name,data):
        path = directory/(name+".json")
        if path.exists() and json.loads(path.read_text()) == data: return
        path.write_text(json.dumps(data,indent="\t")+"\n")
    def rect(data,x0,y0,x1,y1,value="0"):
        grid = list(map(list,data["tiles"]))
        for y in range(y0,y1+1):
            for x in range(x0,x1+1): grid[y][x] = value
        data["tiles"] = ["".join(row) for row in grid]
    def add(data,entity):
        if entity not in data["entities"]: data["entities"].append(entity)
    def rail(data,x,y,width):
        add(data,dict(t="jumpthru",x=x*8,y=y*8,w=width*8,h=8))

    world = load("world")
    obsolete = "i18_ash_passage"
    world["rooms"].pop(obsolete,None)
    for region in world.get("regions",[]):
        region["rooms"] = [n for n in region["rooms"] if n != obsolete]
    data = {n:load(n) for n in world["rooms"]}
    foothills,gallery,east,tunnel = (data[n] for n in
        ["i04_foothills","i12_echo_gallery","i08_east_shore","i09_sea_cave"])
    # Undo the rejected extra-room link, leaving the gallery's original geometry.
    rect(foothills,3,foothills["h"]-3,5,foothills["h"]-1,"1")
    foothills["entities"] = [e for e in foothills["entities"] if not
        (e["t"] == "jumpthru" and e["x"] == 24 and e.get("w") == 24 and e["y"] == (foothills["h"]-3)*8)]
    rect(gallery,3,0,5,0,"1")
    gallery["entities"] = [e for e in gallery["entities"] if not
        (e["t"] == "jumpthru" and e["x"] == 24 and e.get("w") == 24 and e["y"] in (16,24,40,48,64,72,88))]

    fx,fy = world["rooms"]["i04_foothills"]
    old_x,old_y = world["rooms"]["i09_sea_cave"]
    new_x,new_y = fx,fy+foothills["h"]
    extension = max(0,46-tunnel["h"])
    dx,dy = new_x-old_x,new_y-old_y+extension
    maze = next(r for r in world["regions"] if r["name"] == "Volcanic Maze")
    for name in maze["rooms"]:
        if name != "i09_sea_cave":
            x,y = world["rooms"][name]
            world["rooms"][name] = [x+dx,y+dy]
    world["rooms"]["i09_sea_cave"] = [new_x,new_y]
    if extension:
        # Extend the existing entrance vertically; its lower chamber, left exit,
        # water and inhabitants move down together, preserving the junction link.
        upper = ["1"*tunnel["w"] for _ in range(extension)]
        extended = dict(tiles=upper,w=tunnel["w"],h=extension)
        for y in range(extension):
            x0,x1 = ((6,9) if y < 2 else (3,13) if y < 8 else (5,17) if y < 15 else (3,14))
            rect(extended,x0,y,x1,y)
        tunnel["tiles"] = extended["tiles"]+tunnel["tiles"]
        tunnel["h"] += extension
        for e in tunnel["entities"]:
            e["y"] += extension*8
            if "ty" in e: e["ty"] += extension*8
            if e["t"] == "jumpthru":
                e["x"] = (5 if (e["y"]//8)%2 else 8)*8
                e["w"] = 8*8  # overlapping rungs keep a jump-only climb
        for y in range(0,extension,3): rail(tunnel,6,y,4 if y == 0 else 6)
        rect(tunnel,3,6,5,6,"1")
        add(tunnel,dict(t="spawn",x=4*8,y=5*8,entrance=True))
    tunnel["name"] = "Ash Passage"
    # The former East Shore descent no longer leads into the relocated maze.
    rect(east,6,east["h"]-3,9,east["h"]-1,"1")
    east["entities"] = [e for e in east["entities"] if not
        (e["t"] == "jumpthru" and e["x"] == 48 and e.get("w") == 32 and e["y"] == (east["h"]-3)*8)]
    rect(foothills,6,foothills["h"]-3,9,foothills["h"]-1)
    rail(foothills,6,foothills["h"]-3,4)
    for room,target,x,y,direction,label in [
        ("i02_north_shore","i03_south_shore",11,10,"south","South Shore"),
        ("i03_south_shore","i02_north_shore",36,14,"north","North Shore"),
    ]:
        data[room]["entities"] = [e for e in data[room]["entities"] if e.get("id") != "coast_path"]
        add(data[room],dict(t="house_door",skin="signpost",x=x*8,y=y*8,w=16,h=24,
                            id="coast_path",to=target+":coast_path",direction=direction,label=label))
    # Validate the proposed layout before writing any room or manifest.
    for a,b in itertools.combinations(world["rooms"],2):
        ax,ay = world["rooms"][a]; bx,by = world["rooms"][b]
        if max(ax,bx) < min(ax+data[a]["w"],bx+data[b]["w"]) and max(ay,by) < min(ay+data[a]["h"],by+data[b]["h"]):
            raise ValueError(f"Relocation would overlap {a} and {b}")
    for name in ["i02_north_shore","i03_south_shore","i04_foothills","i08_east_shore","i09_sea_cave","i12_echo_gallery"]:
        save(name,data[name])
    save("world",world)
    old = directory/(obsolete+".json")
    if old.exists(): old.unlink()
    print("Linked Foothills → i09 (Ash Passage) → Volcanic Maze; shifted the maze together; shore signs retained")


if __name__ == "__main__":
    apply(sys.argv[1] if len(sys.argv)>1 else "worlds/story")
