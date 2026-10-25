"""Apply original regional artwork without changing tiles, exits or collision.

Safe to re-run after the room generators. Decorative entities carry art_tag
so a later run replaces this pass rather than duplicating its villagers.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROOMS = ROOT / "worlds/story"


def decorate(name, theme=None, props=(), people=(), clear_notes=()):
    path = ROOMS / (name + ".json")
    if not path.exists():
        return
    data = json.loads(path.read_text())
    if theme:
        data["environment"] = theme
    data["entities"] = [e for e in data["entities"] if e.get("art_tag") != "regions-v1"
                        and not (e["t"] == "note" and any(s in e.get("text", "") for s in clear_notes))]
    for kind, x, y, variant in props:
        data["entities"].append(dict(t="island_prop", kind=kind, x=x, y=y, variant=variant, art_tag="regions-v1"))
    for kind, x, y, variant in people:
        data["entities"].append(dict(t="village_"+kind, x=x, y=y, variant=variant, art_tag="regions-v1"))
    if theme == "volcano":
        for e in data["entities"]:
            if e["t"] == "acid":
                e["skin"] = "lava"
    path.write_text(json.dumps(data, indent="\t") + "\n")


def main():
    for name in ("i01_island_shore", "i01_island_shore_after"):
        decorate(name, "island_shore", props=[("raft", 16, 136, 0)])
    decorate("i02_tidal_terraces", "island_shore")
    for name in ("i03_basalt_foothills", "i04_volcano_ascent", "i05_crater_descent"):
        decorate(name, "volcano")
    for name in ("i06_underground_junction", "i07_echo_gallery", "i08_lower_maze", "i09_vent_shaft", "i10_quiet_refuge", "i11_guardian_chamber", "i11_guardian_chamber_after", "i12_crystal_pocket", "i13_sealed_overlook"):
        props = {
            "i06_underground_junction": [("landmark", 40, 168, 0)],
            "i07_echo_gallery": [("landmark", 280, 144, 1)],
            "i08_lower_maze": [("landmark", 232, 48, 2)],
            "i12_crystal_pocket": [("landmark", 136, 120, 1)],
        }.get(name, [])
        decorate(name, "volcanic_cave", props=props)
    decorate("l3_treetop_village", people=[("elf", x, 136, i % 3) for i, x in enumerate((96, 248, 376, 488, 584))], clear_notes=["Village NPCs (not built)"])
    decorate("s3_lighthouse_top", props=[("beacon", 192, 24, 0), ("mirror", 160, 64, 0)],
             people=[("mage", x, 64, i % 3) for i, x in enumerate((112, 144, 224, 256, 288))],
             clear_notes=["Silent villager", "Magic flame, aimed"])
    print("Dressed island environments, landmarks, treetop elves and lighthouse mages")


if __name__ == "__main__":
    main()
