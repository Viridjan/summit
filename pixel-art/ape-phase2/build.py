"""Original phase-two silverback, authored at 32px using pixel-art-studio.

Run from any directory: python3 pixel-art/ape-phase2/build.py
Deferred ape-trueform concept; this script does not change runtime artwork.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path.home() / ".codex/skills/pixel-art-studio/scripts"))
from pixelstudio import Sprite

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
POSES = ["idle", "crouch", "air", "throw", "scream", "run", "land",
         "launch", "rise", "apex", "fall", "hurt", "dying", "sleep"]
# Top-left light; cool charcoal shadows, warm silver ridge and copper bare skin.
INK, DARK, FUR, LIGHT = "#211f2b", "#343443", "#505363", "#747989"
MANE_DARK, MANE, MANE_LIGHT = "#92969e", "#c2bcae", "#e2d8bb"
SKIN_DARK, SKIN, SCAR, EYE, TOOTH = "#79483f", "#b66a50", "#d99b72", "#f6c75a", "#f0dfb1"
PALETTE = [INK, DARK, FUR, LIGHT, MANE_DARK, MANE, MANE_LIGHT,
           SKIN_DARK, SKIN, SCAR, EYE, TOOTH]


def draw_pose(pose, frame=0):
    s = Sprite(32, 32, palette=PALETTE)
    bob = [0, 1, 0, 1][frame] if pose == "run" else 0
    drop = {"crouch": 4, "launch": 5, "land": 5, "hurt": 2,
            "sleep": 3, "apex": 1, "rise": -1}.get(pose, bob)
    airborne = pose in ("air", "rise", "apex", "fall")
    swing = [-2, 0, 2, 0][frame] if pose == "run" else 0

    def poly(points, color, offset=0):
        s.polygon([(x, y + offset) for x, y in points], color)

    def box(x, y, w, h, color):
        s.rect(x, y, x + w - 1, y + h - 1, color)

    if pose == "dying":
        # A collapsed shoulder and low muzzle, still resting on the same baseline.
        poly([(1,29),(3,23),(8,19),(17,20),(23,24),(28,25),(31,29),(30,31),(2,31)], INK)
        poly([(3,28),(6,23),(12,21),(18,23),(23,27),(28,27),(29,30),(4,30)], FUR)
        poly([(5,24),(9,21),(14,22),(18,24),(14,25),(8,26)], MANE)
        poly([(5,24),(9,22),(12,22),(9,24)], MANE_LIGHT)
        box(23,27,7,3,SKIN_DARK)
        box(24,27,4,1,SKIN)
        box(23,26,3,1,INK)
        box(12,28,9,3,DARK)
        box(15,30,7,1,SKIN_DARK)
        return s

    # Far-side limbs: separate dark masses behind the body and near arm.
    if airborne:
        knee = 21 if pose == "apex" else 24
        poly([(3,17),(10,17),(13,knee),(9,knee+4),(4,knee+3),(2,knee)], INK)
        poly([(4,19),(9,19),(10,knee),(7,knee+2),(4,knee+1)], DARK)
        box(5,knee+2,5,2,SKIN_DARK)
    else:
        poly([(3,17),(10,18),(13,25),(9,29),(12,30),(12,31),(2,31),(2,27),(5,23)], INK)
        poly([(5,20),(9,20),(10,25),(6,29),(4,29),(5,25)], DARK)
        box(3,30,6,1,SKIN_DARK)
    if pose in ("rise", "throw"):
        poly([(20,15),(23,10),(25,4),(28,2),(31,3),(30,9),(27,12),(24,20)], INK)
        poly([(23,15),(25,9),(27,5),(29,4),(28,9),(25,17)], DARK)
        box(27,3,3,3,SKIN_DARK)
    else:
        poly([(20,12),(25,15),(25,22),(29,26),(30,30),(24,30),(21,25),(18,19)], INK)
        poly([(22,16),(24,17),(23,23),(27,27),(25,28),(22,24)], DARK)
        box(25,28,4,2,SKIN_DARK)

    # The raised, serrated silver mantle changes the outline as well as the palette.
    poly([(1,18),(2,11),(4,10),(4,7),(7,7),(8,4),(11,5),(13,2),
          (16,4),(19,4),(24,9),(23,18),(18,23),(9,26),(3,23)], INK, drop)
    poly([(3,17),(4,11),(7,8),(11,6),(15,4),(20,6),(22,10),
          (21,18),(16,22),(8,24),(4,21)], FUR, drop)
    poly([(3,14),(5,9),(9,6),(14,4),(19,5),(20,8),(16,9),
          (12,12),(10,17),(6,21),(4,19)], MANE_DARK, drop)
    poly([(4,12),(7,8),(11,6),(15,5),(18,6),(15,8),(11,10),
          (8,15),(6,18),(4,18)], MANE, drop)
    poly([(6,10),(10,7),(14,5),(16,6),(12,8),(8,11)], MANE_LIGHT, drop)
    # Broken tufts keep the mantle a fur mass rather than a smooth white cape.
    poly([(5,15),(7,12),(7,16),(6,19),(4,20)], MANE_DARK, drop)
    poly([(10,10),(13,8),(12,11),(10,13)], LIGHT, drop)
    # Directional clusters, not a full rim of parallel highlight bands.
    poly([(10,15),(13,12),(17,11),(16,14),(12,18),(10,22),(7,23)], LIGHT, drop)
    poly([(6,20),(9,17),(8,22),(6,23)], DARK, drop)

    # Low forward brow, clipped ear and scar crossing the forehead.
    poly([(17,3),(23,3),(26,6),(26,9),(30,11),(31,15),(29,18),
          (22,17),(18,13),(16,8)], INK, drop)
    poly([(18,5),(22,4),(24,6),(24,10),(21,12),(18,10)], FUR, drop)
    box(18,6+drop,4,1,LIGHT)
    box(18,10+drop,2,3,SKIN_DARK)
    poly([(23,10),(26,10),(30,12),(30,15),(28,16),(23,15),(21,13)], SKIN_DARK, drop)
    box(25,12+drop,5,2,SKIN)
    box(28,12+drop,2,1,INK)
    # Two-pixel slanted brow scar; the eye is the sole bright one-pixel accent.
    box(22,6+drop,1,2,SCAR)
    box(23,7+drop,1,2,SCAR)
    poly([(22,8),(26,9),(27,10),(23,10)], INK, drop)
    box(25,10+drop,1,1,EYE)
    box(23,11+drop,2,1,INK)
    box(26,16+drop,4,1,INK)
    if pose == "scream":
        box(25,13+drop,6,6,INK)
        box(26,13+drop,4,1,TOOTH)
        box(26,14+drop,1,2,TOOTH)
        box(29,14+drop,1,2,TOOTH)
        box(27,17+drop,3,1,SKIN)
    elif pose not in ("sleep", "hurt"):
        box(27,16+drop,2,1,TOOTH)
    if pose == "sleep":
        box(24,10+drop,3,1,INK)

    # Near arm: longer planted knuckles and a broad pale shoulder tuft.
    if pose in ("throw", "rise"):
        poly([(12,16),(10,10),(12,5),(16,0),(21,0),(22,4),(18,7),(17,14),(15,19)], INK)
        poly([(13,14),(12,10),(14,6),(17,2),(20,2),(19,4),(15,8),(15,15)], FUR)
        box(16,0,5,3,SKIN_DARK)
        box(17,0,4,1,SKIN)
        poly([(11,10),(13,6),(15,5),(14,10),(15,14),(12,15)], MANE)
    elif pose == "apex":
        poly([(11,14),(17,13),(22,17),(23,21),(20,25),(15,25),(11,21),(9,17)], INK)
        poly([(12,15),(17,15),(20,18),(20,21),(17,23),(13,20),(11,17)], FUR)
        poly([(11,15),(15,14),(17,16),(14,17),(12,19)], MANE)
        box(17,22,5,2,SKIN_DARK)
    elif pose in ("air", "fall"):
        poly([(11,13),(17,12),(21,16),(20,22),(23,25),(25,28),(24,31),(17,31),(14,26),(14,20),(10,17)], INK)
        poly([(12,14),(16,14),(18,17),(17,23),(21,28),(19,29),(16,25),(16,19),(12,17)], FUR)
        poly([(11,14),(14,13),(17,14),(16,17),(12,18)], MANE)
        box(18,28,6,2,SKIN_DARK)
        box(19,28,4,1,SKIN)
    elif pose in ("land", "launch", "crouch"):
        shoulder = 17 if pose == "land" else 15
        poly([(10,shoulder),(16,shoulder-1),(21,21),(23,26),(29,27),(30,31),
              (20,31),(16,27),(13,23),(9,22)], INK)
        poly([(11,shoulder+1),(16,shoulder+1),(19,22),(20,27),(23,29),
              (20,29),(17,25),(14,22),(11,21)], FUR)
        poly([(10,shoulder),(14,shoulder-1),(17,shoulder+1),(15,shoulder+3),(11,shoulder+3)], MANE)
        box(22,28,7,3,SKIN_DARK)
        box(23,28,5,1,SKIN)
        for finger in (23,25,27): box(finger,30,1,1,SCAR)
    else:
        poly([(10,12),(16,11),(21,14),(21,20),(18+swing,26),
              (23+swing,28),(24+swing,31),(14+swing,31),
              (12+swing,28),(14,23),(12,19),(9,16)], INK, 0)
        poly([(11,14),(16,13),(19,15),(19,20),(16+swing,26),
              (16+swing,29),(14+swing,28),(16,22),(14,19),(11,17)], FUR)
        poly([(10,13),(14,11),(18,13),(17,16),(14,17),(11,16)], MANE)
        poly([(11,13),(14,12),(16,13),(13,14)], MANE_LIGHT)
        box(16+swing,28,7,3,SKIN_DARK)
        box(17+swing,28,5,1,SKIN)
        for finger in (17,19,21): box(finger+swing,30,1,1,SCAR)
    if pose == "hurt":
        # Closed eye and a recoiling shoulder distinguish hurt from idle.
        box(24,10+drop,3,1,INK)
        poly([(10,13),(14,10),(17,12),(15,16),(12,18)], MANE)
    if pose in ("idle", "run", "scream"):
        # A warm, broad elbow plane separates the long arm from the far leg.
        poly([(15,20),(18,19),(17,23),(16+swing,26),(14+swing,26)], LIGHT)
    return s


def main():
    atlas = Image.new("RGBA", (128, 32 * len(POSES)))
    frames = {}
    for row, pose in enumerate(POSES):
        frames[pose] = []
        for frame in range(4):
            sprite = draw_pose(pose, frame if pose == "run" else 0)
            image = sprite.composite()
            atlas.paste(image, (32 * frame, 32 * row))
            frames[pose].append(image)
    atlas.save(HERE / "ape-phase2.png")
    # Labelled, integer-scaled comparison of one pose per row.
    preview = Image.new("RGB", (900, len(POSES) * 145), "#202432")
    pen = ImageDraw.Draw(preview)
    for row, pose in enumerate(POSES):
        pen.text((8, row * 145 + 5), pose, fill="#e2d8bb")
        for frame in range(4):
            image = frames[pose][frame].resize((128, 128), Image.Resampling.NEAREST)
            preview.paste(image, (140 + frame * 180, row * 145 + 12), image)
    preview.save(HERE / "preview.png")
    comparison = Image.new("RGB", (320, 164), "#202432")
    labels = ImageDraw.Draw(comparison)
    first = Image.open(ROOT / "assets/enemies/ape.png").convert("RGBA").crop((0,0,32,32))
    for index, image in enumerate([first, frames["idle"][0]]):
        labels.text((16+index*160,8), "Phase one" if index == 0 else "Phase two", fill="#e2d8bb")
        enlarged=image.resize((128,128),Image.Resampling.NEAREST)
        comparison.paste(enlarged,(16+index*160,28),enlarged)
    comparison.save(HERE / "comparison.png")
    # Real run-loop timing: runtime advances at 10 fps. Three loops for inspection.
    run = []
    for image in frames["run"] * 3:
        bg = Image.new("RGBA", (32,32), "#202432")
        bg.alpha_composite(image)
        run.append(bg.convert("RGB").resize((192,192), Image.Resampling.NEAREST))
    run[0].save(HERE / "run.gif", save_all=True, append_images=run[1:], duration=100, loop=0)
    # Jump sequence demonstrates pose continuity; game uses actual velocity to select it.
    jump = []
    for pose in ["idle","crouch","launch","rise","apex","fall","land","idle"]:
        bg=Image.new("RGBA",(32,32),"#202432")
        bg.alpha_composite(frames[pose][0])
        jump.append(bg.convert("RGB").resize((192,192),Image.Resampling.NEAREST))
    jump[0].save(HERE / "jump.gif",save_all=True,append_images=jump[1:],duration=[300,150,80,140,150,140,200,300],loop=0)
    manifest = {"cell": [32,32], "columns":4, "poses":POSES,
                "looping":{"run":{"frames":4,"fps":10}}, "palette": PALETTE,
                "anchor":"bottom center", "license":"Original Summit artwork; project license."}
    (HERE / "manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    master=Sprite.from_png(str(HERE/"ape-phase2.png"),scale=1)
    master.stats()
    master.save_silhouette(str(HERE/"silhouette.png"))
    master.save_swatch(str(HERE/"palette.png"))
    print("Built phase-two Ape: 14 poses, 32x32, 12-color budget")


if __name__ == "__main__":
    main()
