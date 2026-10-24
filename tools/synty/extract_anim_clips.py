#!/usr/bin/env python3
"""Extract the Synty animation FBX files the D-040 animation pass needs into
assets/imported/anim_pass/ (gitignored, local only: purchased content).

    python3 tools/synty/extract_anim_clips.py ["<folder with the Synty ANIMATION_*_SourceFiles zips>"]

Every res://assets/imported/anim_pass/<file>.fbx named in data/art/animation_overrides.json
is looked up by file name inside the zips (POLYGON clips only), plus the root-motion
twins tools/anim_probe.gd uses to cross-check speeds. Existing files are kept.
Then run tools/synty/build_godot_packs.sh (import, retarget, rebuild libraries).
"""
import json
import os
import re
import stat
import sys
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "imported", "anim_pass")
DEFAULT_ZIPS = os.path.join(os.path.expanduser("~"), "Desktop", "Art assets", "Synty Fbx and GoDot")
PROBE_TWINS = ["A_Walk_F_RootMotion_Masc.fbx", "A_Run_F_RootMotion_Masc.fbx", "A_Sprint_F_RootMotion_Masc.fbx",
               "A_Walk_ToIdleF_LFootRootMotion_Masc.fbx", "A_Run_ToIdleF_LFootRootMotion_Masc.fbx"]


def wanted() -> set:
    with open(os.path.join(ROOT, "data", "art", "animation_overrides.json"), encoding="utf-8") as f:
        text = f.read()
    names = set(re.findall(r"res://assets/imported/anim_pass/([^\"]+\.fbx)", text))
    return names | set(PROBE_TWINS)


def main() -> int:
    zdir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ZIPS
    os.makedirs(OUT, exist_ok=True)
    need = {n for n in wanted() if not os.path.exists(os.path.join(OUT, n))}
    for zname in sorted(os.listdir(zdir)):
        if not (zname.startswith("ANIMATION_") and zname.endswith(".zip")) or not need:
            continue
        with zipfile.ZipFile(os.path.join(zdir, zname)) as z:
            for info in z.infolist():
                base = info.filename.rsplit("/", 1)[-1]
                if base in need and "/Polygon/" in info.filename:
                    dst = os.path.join(OUT, base)
                    with z.open(info) as src, open(dst, "wb") as f:
                        f.write(src.read())
                    os.chmod(dst, stat.S_IWRITE | stat.S_IREAD)
                    need.discard(base)
                    print("extracted", base, "from", zname)
    for n in sorted(need):
        print("MISSING", n)
    return 1 if need else 0


if __name__ == "__main__":
    sys.exit(main())
