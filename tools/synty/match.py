#!/usr/bin/env python3
"""Proposes a model for every visual slot from the packs in quarantine.

Uses the per-slot search patterns in data/art/synty_suggestions.json:
glob patterns (SM_Env_Floor*) score by their order, plain words ("floor tile")
score per matching word, a pack-name match and "_01" variants get a small bonus,
and a model already proposed for another slot is slightly penalised so slots
get distinct models where possible.

Writes data/art/synty_choices.json (slot -> chosen file + 4 alternatives). Only
file NAMES go in git, never the files. Entries you set to "status": "approved"
or "manual" are kept as they are on re-runs; "skip" leaves a slot on its proxy.
"variants" (rocks, trees, crates, citizens...) lists several models of one
family; the game picks one per placement. Edit or remove the list freely.
"auto" = confident name match (built), "weak" = one shared word only (listed,
not built until you approve it), "none" = nothing found.

  python3 tools/synty/match.py            # propose / refresh
  python3 tools/synty/match.py --report   # print the table only
"""
import fnmatch, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
Q = os.path.join(ROOT, "assets", "quarantine")
SUGG = os.path.join(ROOT, "data", "art", "synty_suggestions.json")
OUT = os.path.join(ROOT, "data", "art", "synty_choices.json")
MODEL_EXT = (".fbx", ".glb", ".gltf", ".obj")
IMAGE_EXT = (".png", ".tga", ".jpg", ".jpeg", ".psd")
KEEP_STATUS = ("approved", "manual", "skip")
# Particle FX are Unity particle systems: there is nothing to import as a model.
# They are rebuilt in Godot (GPUParticles3D) using the pack's textures.
MANUAL_CATEGORIES = ("fx.",)
WEAK_BELOW = 50   # scores under this are "weak": listed, but not built until approved
# Slots shown many times in a scene get up to MAX_VARIANTS models of the same
# family (SM_Env_Rock_01.._06), so no two rocks or trees in a row look alike.
VARIANT_SLOTS = ("surface.rock_small", "surface.rock_large", "surface.tree_green", "surface.plant_green", "surface.crystal_ice",
                 "surface.ice_spire", "surface.desert_rock", "ship.crate", "ship.pipe", "char.citizen_adult", "char.citizen_child",
                 "space.asteroid")
MAX_VARIANTS = 6


def family(src):
    return re.sub(r"_?\d+$", "", os.path.splitext(os.path.basename(src))[0].lower())


def inventory(only=None):
    """[(pack, rel_path, stem)] for every model and image in quarantine."""
    out = []
    if not os.path.isdir(Q):
        return out
    for pack in sorted(os.listdir(Q)):
        if only and pack not in only:
            continue
        mf = os.path.join(Q, pack, "manifest.json")
        if not os.path.exists(mf):
            continue
        for f in json.load(open(mf, encoding="utf-8"))["files"]:
            p = f["path"]
            out.append((pack, p, os.path.splitext(os.path.basename(p))[0]))
    return out


def words(s):
    return [w for w in re.split(r"[^a-z0-9]+", s.lower()) if w]


def score(slot, spec, pack, stem):
    best = 0
    for i, pat in enumerate(spec.get("search", [])):
        if any(ch in pat for ch in "*?") or pat.startswith(("SM_", "SK_", "FX_")):
            if fnmatch.fnmatch(stem.lower(), pat.lower()):
                best = max(best, 100 - 12 * i)
        else:
            hit = sum(1 for w in words(pat) if len(w) > 2 and w in words(stem))
            best = max(best, hit * 18)
    if best == 0:
        return 0
    if any(w in words(pack) for w in words(spec.get("pack", "")) if w not in ("polygon", "sci", "fi", "pack", "interface")):
        best += 12
    if re.search(r"_0?1$", stem):
        best += 5
    return best


def propose(slots, inv, previous):
    used = {}
    for c in previous.values():
        if c.get("status") in KEEP_STATUS and c.get("source"):
            used[c["source"]] = used.get(c["source"], 0) + 1
    out = {}
    for slot, spec in slots.items():
        prev = previous.get(slot, {})
        if prev.get("status") in KEEP_STATUS:
            out[slot] = prev
            continue
        if slot.startswith(MANUAL_CATEGORIES):
            out[slot] = {"source": "", "status": "manual", "note": "Particle FX: build GPUParticles3D in Godot with the pack textures (docs/SYNTY_INTEGRATION.md)."}
            continue
        want = IMAGE_EXT if slot.startswith("ui.") else MODEL_EXT
        ranked = []
        for pack, rel, stem in inv:
            if not rel.lower().endswith(want):
                continue
            s = score(slot, spec, pack, stem)
            if s > 0:
                src = pack + "/" + rel
                ranked.append((s - 8 * used.get(src, 0), src))
        ranked.sort(key=lambda t: (-t[0], t[1]))
        if not ranked:
            out[slot] = {"source": "", "status": "none", "note": "no match in quarantine; keep the proxy or choose by hand"}
            continue
        src = ranked[0][1]
        used[src] = used.get(src, 0) + 1
        # A name-pattern hit is trusted; a single shared word is only a suggestion.
        status = "auto" if ranked[0][0] >= WEAK_BELOW else "weak"
        out[slot] = {"source": src, "score": ranked[0][0], "status": status, "alternatives": [r[1] for r in ranked[1:5]]}
        if slot in VARIANT_SLOTS:
            fam = [r[1] for r in ranked if family(r[1]) == family(src) and r[0] >= WEAK_BELOW - 10]
            if len(fam) > 1:
                out[slot]["variants"] = sorted(fam)[:MAX_VARIANTS]
    return out


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="print only, write nothing")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--packs", nargs="*", help="only these quarantine packs (default: all)")
    a = ap.parse_args()
    slots = {k: v for k, v in json.load(open(SUGG, encoding="utf-8"))["slots"].items() if not k.startswith("_")}
    previous = {}
    if os.path.exists(a.out):
        previous = json.load(open(a.out, encoding="utf-8")).get("choices", {})
    inv = inventory(a.packs)
    choices = propose(slots, inv, previous)
    counts = {}
    for c in choices.values():
        counts[c["status"]] = counts.get(c["status"], 0) + 1
    for slot, c in choices.items():
        if c.get("source"):
            print("%-28s %-9s %s" % (slot, c["status"], c["source"]))
    print("packs: %d · models/images: %d · %s" % (len({p for p, _r, _s in inv}), len(inv), counts))
    if not a.report:
        doc = {"_note": "Slot -> chosen Synty file (path inside assets/quarantine). Set status to approved/manual to lock a choice, "
                        "skip to keep the proxy. Then: python3 tools/synty/stage.py && godot --headless --path . --import "
                        "&& godot --headless --path . --script res://tools/synty/build_wrappers.gd",
               "choices": choices}
        with open(a.out, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
