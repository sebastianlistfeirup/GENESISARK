#!/usr/bin/env python3
"""Copies the Poly Perfect creatures Genesis Ark uses (ground wildlife, D-053)
from the owner's purchased pack into assets/imported/polyperfect/ (gitignored:
the repository is PUBLIC, purchased files never go into git).

Usage: python3 tools/polyperfect/stage.py [--src <pack dir>] [--dest <repo root>]
Then: godot --headless --path . --import --quit-after 2000
Only file names live here; the meshes, clips and textures stay local. Missing
files are reported and skipped (GroundWildlife skips species without a model).
"""
import argparse, os, shutil, stat

PACK = r"C:\Users\compu\Desktop\Art assets\Poly Perfect\Low Poly Animated Fantasy Creatures"
# mesh file (Meshes/<group>/) -> texture stem (Textures/Creatures/<stem>_COL_2k.png, optional _EMIT_2k)
CREATURES = {
    "Stags/SKM_Stag_Fantasy_Common.fbx": "Stag_Fantasy_Common",
    "Stags/SKM_Stag_Fantasy_Frost.fbx": "Stag_Fantasy_Frost",
    "Stags/SKM_Stag_Fantasy_Undead.fbx": "Stag_Fantasy_Undead",
    "Bulls Fantasy/SKM_Bull_Fantasy.fbx": "Bull_Fantasy",
    "Bears Fantasy/SKM_Bear_Fantasy_Forest.fbx": "Bear_Fantasy_Forest",
    "Bears Fantasy/SKM_Bear_Fantasy_Snow.fbx": "Bear_Fantasy_Snow",
    "Horses Fantasy/SKM_Horse_Thoroughbred.fbx": "Horse_Thoroughbred",
    "Horses Fantasy/SKM_Horse_Unicorn.fbx": "Horse_Unicorn",
    "Horses Fantasy/SKM_Horse_Skeleton.fbx": "Horse_Skeleton",
    "Gryphons/SKM_Gryphon.fbx": "Gryphon",
    "Hippogryph/SKM_Hippogryph.fbx": "Hippogryph",
}


def copy(src: str, dst: str) -> bool:
    if not os.path.exists(src):
        print("missing:", src)
        return False
    if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src):
        shutil.copyfile(src, dst)
    os.chmod(dst, stat.S_IWRITE | stat.S_IREAD)  # packs unzip read-only: Godot must write .import files
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=PACK)
    ap.add_argument("--dest", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    a = ap.parse_args()
    out = os.path.join(a.dest, "assets", "imported", "polyperfect")
    os.makedirs(out, exist_ok=True)
    n = 0
    for mesh, stem in CREATURES.items():
        n += copy(os.path.join(a.src, "Meshes", mesh), os.path.join(out, os.path.basename(mesh)))
        copy(os.path.join(a.src, "Textures", "Creatures", stem + "_COL_2k.png"), os.path.join(out, stem + "_COL_2k.png"))
        emit = os.path.join(a.src, "Textures", "Creatures", "Textures_Creatures_EMIT", stem + "_EMIT_2k.png")
        if os.path.exists(emit):
            copy(emit, os.path.join(out, stem + "_EMIT_2k.png"))
    print("staged", n, "creatures into", out)


if __name__ == "__main__":
    main()
