"""First discovery migration and compact ordinary rooms; preserves global floor geometry.

Run against a disposable world first, then review its JSON changes. Pass the
world directory explicitly. Re-running is idempotent. Tall setpiece rooms and
rooms entered through their ceiling are deliberately excluded from top trims.
"""
import argparse
import json
from pathlib import Path

TARGETS = {
    "m1_meadow":16, "m2_big_jump":16, "c0_roar_tunnel":16,
    "c2_cave_teeth":18, "c3_cove_tunnel":16, "t1_cove_town":16,
    "j1_jungle_edge":20, "j3_jungle_hills":19, "l2_net_trap":16,
    "l3_treetop_village":18, "i02_north_shore":16, "i04_foothills":16,
    "i06_crater":16, "i08_east_shore":16, "i10_junction":16,
    "i11_flooded_hall":16, "i12_echo_gallery":16,
}
FRAGMENTS = {"i02_north_shore":"north_cliff", "i03_south_shore":"south_rocks", "i08_east_shore":"east_coast"}
CHARACTERS = {
    "j1_jungle_edge":("Aerin","elf",0,"Leaf paths lead to places the main trail misses."),
    "i17_crystal_pocket":("Crystal Keeper","mage",2,"Three energy fragments form one energy upgrade."),
}


def speaker_floor(data, entity):
    x = int((entity["x"]+4)//8)
    floors = [y*8 for y,row in enumerate(data["tiles"]) if y*8>=entity["y"] and row[x]=="1"]
    floors += [e["y"] for e in data["entities"] if e["t"] in ("jumpthru","leaf")
               and e["x"]<=entity["x"]+4<e["x"]+e.get("w",8) and e["y"]>=entity["y"]]
    return min(floors)-16


def apply(directory):
    directory = Path(directory)
    world = json.loads((directory/"world.json").read_text())
    changes = []
    for path in sorted(directory.glob("*.json")):
        if path.name == "world.json": continue
        data = json.loads(path.read_text())
        old = json.dumps(data,sort_keys=True)
        name = path.stem
        if name == "m1_meadow":
            data["entities"] = [e for e in data["entities"] if e["t"]!="strawberry"]
        # Only the first star in each selected room changes in this initial batch.
        for e in data["entities"]:
            if e["t"] != "strawberry": continue
            if name in FRAGMENTS and not any(p["t"]=="energy_fragment" and p.get("id")==FRAGMENTS[name] for p in data["entities"]):
                e.update(t="energy_fragment",id=FRAGMENTS[name])
                break
            if name in CHARACTERS and not any(p["t"]=="discovery_npc" and p.get("name")==CHARACTERS[name][0] for p in data["entities"]):
                speaker,kind,variant,text = CHARACTERS[name]
                e["y"] = speaker_floor(data,e)
                e["x"] -= 4
                e.update(t="discovery_npc",name=speaker,kind=kind,variant=variant,text=text)
                break
        if name in TARGETS and data["h"]>TARGETS[name]:
            cut = data["h"]-TARGETS[name]
            # Move ceiling emitters with the ceiling; their landing floor stays put.
            for e in data["entities"]:
                if e["t"] == "rockfall" and e["y"]<(cut+1)*8:
                    e["y"] = (cut+1)*8
            safe_cut = min((int(e["y"]//8)-1 for e in data["entities"]),default=cut)
            cut = max(0,min(cut,safe_cut))
            if cut:
                old_top = data["tiles"][0]
                data["tiles"] = data["tiles"][cut:]
                data["tiles"][0] = old_top  # retain the original roof/open-sky treatment
                data["h"] -= cut
                for e in data["entities"]:
                    if e["t"]=="stamina_block": e.setdefault("pickup_key",f"{name}:{int(e['x'])}:{int(e['y'])}")
                    if e["t"]=="strawberry": e.setdefault("persistent_id",f"{int(e['x'])}_{int(e['y'])}")
                    e["y"] -= cut*8
                    if "ty" in e: e["ty"] -= cut*8
                    # Boss reward door data, if ever used in an ordinary room.
                    if isinstance(e.get("door"),dict): e["door"]["y"] -= cut*8
                data["vertical_trim"] = int(data.get("vertical_trim",0))+cut
                if name in world["rooms"]: world["rooms"][name][1] += cut
        if name == "s3_lighthouse_top" and data["h"]>13:
            # The balcony has an unbroken floor at rows 11/12. Everything below
            # is inaccessible visual tower space, with travel handled by doors.
            data["entities"] = [e for e in data["entities"] if e["y"]<13*8]
            data["tiles"] = data["tiles"][:13]
            data["h"] = 13
        if json.dumps(data,sort_keys=True)!=old:
            path.write_text(json.dumps(data,indent="\t")+"\n")
            changes.append(name)
    (directory/"world.json").write_text(json.dumps(world,indent="\t")+"\n")
    print("Refined",len(changes),"rooms:",", ".join(changes))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("world_dir",type=Path)
    apply(parser.parse_args().world_dir)
