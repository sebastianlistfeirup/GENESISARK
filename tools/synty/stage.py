#!/usr/bin/env python3
"""Copies only the chosen Synty files from quarantine into the project.

For every slot in data/art/synty_choices.json with status auto/approved/manual
and a source, copies the model (plus a .gltf's .bin) and the pack's atlas
textures to assets/imported/<pack>/<same relative path>. Nothing else from the
pack enters the project. Writes assets/imported/<pack>/staged.json.

  python3 tools/synty/stage.py [--choices data/art/synty_choices.json]
Then: godot --headless --path . --import  (Godot imports the new files)
"""
import argparse, json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
Q = os.path.join(ROOT, "assets", "quarantine")
IMPORTED = os.path.join(ROOT, "assets", "imported")
BUILD_STATUS = ("auto", "approved", "manual")
IMAGE_EXT = (".png", ".tga", ".jpg", ".jpeg", ".psd")


def atlas_files(pack: str) -> list:
    """The pack's colour atlases: images named *Texture* (Synty convention), else all images in a Textures folder."""
    mf = json.load(open(os.path.join(Q, pack, "manifest.json"), encoding="utf-8"))
    imgs = [f["path"] for f in mf["files"] if f["path"].lower().endswith(IMAGE_EXT)]
    named = [p for p in imgs if "texture" in os.path.basename(p).lower()]
    return named or [p for p in imgs if "/textures/" in "/" + p.lower()]


def copy(pack: str, rel: str) -> str:
    src = os.path.join(Q, pack, rel)
    dst = os.path.join(IMPORTED, pack, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
        shutil.copy2(src, dst)
    return os.path.relpath(dst, ROOT).replace(os.sep, "/")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--choices", default=os.path.join(ROOT, "data", "art", "synty_choices.json"))
    a = ap.parse_args()
    choices = json.load(open(a.choices, encoding="utf-8"))["choices"]
    staged = {}
    for slot, c in sorted(choices.items()):
        if c.get("status") not in BUILD_STATUS or not c.get("source"):
            continue
        for src in [c["source"]] + [v for v in c.get("variants", []) if v != c["source"]]:
            vpack, vrel = src.split("/", 1)
            if not os.path.exists(os.path.join(Q, vpack, vrel)):
                print("  missing in quarantine:", src)
                continue
            files = staged.setdefault(vpack, {"models": {}, "atlas": []})
            files["models"].setdefault(slot, [])
            files["models"][slot].append(copy(vpack, vrel))
            if vrel.lower().endswith(".gltf"):
                bin_rel = os.path.splitext(vrel)[0] + ".bin"
                if os.path.exists(os.path.join(Q, vpack, bin_rel)):
                    copy(vpack, bin_rel)
    for pack, files in staged.items():
        files["atlas"] = [copy(pack, rel) for rel in atlas_files(pack)]
        with open(os.path.join(IMPORTED, pack, "staged.json"), "w", encoding="utf-8") as fh:
            json.dump(files, fh, indent=1)
        print("staged %-24s %d models, %d atlas textures -> assets/imported/%s/" % (pack, len(files["models"]), len(files["atlas"]), pack))
    if not staged:
        print("nothing to stage (no auto/approved choices with a source)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
