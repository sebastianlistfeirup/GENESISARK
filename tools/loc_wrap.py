#!/usr/bin/env python3
"""One-off (re-runnable) transform: wraps player-facing Danish string literals
in GDScript with Loc.t("...") so they can be translated. Conservative: skips
comments, const blocks, dictionary keys, match patterns, comparisons, node and
bus names, developer-only validation files. Prints what it skipped for review.
Usage: python3 tools/loc_wrap.py [--dry]"""
import glob, re, sys
DRY = "--dry" in sys.argv
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
SKIP_FILES = {"scripts/domain/content/content_db.gd", "scripts/core/loc.gd", "scripts/runtime/common/debug_capture.gd",
              "scripts/runtime/common/debug_fixtures.gd"}
SKIP_VALUES = {"Proxy", "Asset", "ShipBuilder", "Dressing", "Captain", "CameraRig", "VisualPivot", "Terrain", "TerrainMesh",
               "TerrainBody", "Collision", "Geometry", "Props", "Scatter", "GhostTip", "Master", "Music", "SFX", "Ambience",
               "UI", "Voice", "Godot", "GENESIS ARK", "ARK", "Shift", "Escape", "Tab", "Space", "Ctrl", "Enter", "Equal",
               "Minus", "Left", "Right", "Up", "Down", "Windows Desktop", "Linux", "Web", "Linux", "Kaptajn [B]"}
WORDS = {"kendt", "ukendt", "skøn", "høj", "middel", "lav", "ja", "nej", "tomt", "forbundet", "ingen", "manuel", "rådet",
         "gratis", "Pause", "Journal", "Logbog", "Rejse", "Sammenligning", "Forsyning", "Befolkning", "Fremtid", "Mål", "Luk",
         "Strøm", "Vand", "Mad", "Dragt", "Prøver", "Kaptajnen", "Autogem", "Fortsæt", "Afslut", "Indstillinger", "Tilbage",
         "Hovedmenu", "Indlæs", "Lyd", "Taster", "Mus", "Flaskehalse", "Planeten", "Landingssites", "Kendt", "Ukendt",
         "Viden", "Rute", "Kohorter", "Inkubation", "Generationsspring", "EPILOG", "AUTOPILOT", "kredsløb", "Samlet",
         "Musik", "Effekter", "Stemning", "Brugerflade", "Følsomhed", "Undertekster", "Landingszone", "Ressourceområde",
         "Boligzone", "Startlager", "Kendte risici", "Byg", "Drej", "Fortryd", "Løb", "Log", "Tid", "Rejs hertil", "Pause tid",
         "Frem", "Venstre", "Højre", "Interagér", "Kolonitilstand", "Bekræft", "Autopilot", "Dronereserve", "Slot 1", "Slot 2",
         "Slot 3", "Krediteringer", "Byggemateriale", "Brug", "Ekspedition", "Ekspedition: ", "Embryobanken", "Fjernsonde", "Geotermi", "Kamerarystelser", "Kendt: ", "Kolonien", "Mangler", "Verden", "Placering: ", "Prioritet: ", "Pris: ", "Sonde", "Sonde: ", "Stjernekort", "Tabt", "Tilslut", "Midterklik", "Auto", "Drone", "Indholdsfejl: ", "Sprog", "kendt", "storm", "nat", "STORM", "NAT", "voksne", "børn", "levende"}

def player_text(t):
    if t in SKIP_VALUES or t.startswith(("res://", "user://", "#", "%s:", "era:", "p:", "dbg", "smoke")):
        return False
    if t in WORDS:
        return True
    if not re.search(r"[A-Za-zÆØÅæøå]{2,}", t):
        return False
    if re.fullmatch(r"[a-z0-9_.:/%-]+", t):
        return False  # identifiers, keys, paths
    return " " in t.strip() or bool(re.search("[æøåÆØÅ]", t))

changed = skipped = 0
review = []
for f in sorted(glob.glob("scripts/**/*.gd", recursive=True)):
    if f in SKIP_FILES:
        continue
    src = open(f, encoding="utf-8").read().split("\n")
    out = []
    in_const = 0
    for line in src:
        st = line.strip()
        if st.startswith("const ") and ("{" in st or "[" in st):
            in_const = st.count("{") + st.count("[") - st.count("}") - st.count("]")
            out.append(line); continue
        if in_const > 0:
            in_const += line.count("{") + line.count("[") - line.count("}") - line.count("]")
            out.append(line); continue
        if st.startswith(("#", "##", "const ", "@export", "class_name", "extends", "push_error", "print(", "match ")):
            out.append(line); continue
        new = ""
        pos = 0
        for m in LIT.finditer(line):
            t = m.group(1)
            a, b = m.span()
            before = line[:a].rstrip()
            after = line[b:].lstrip()
            ok = player_text(t)
            if ok and (after.startswith(":") and not after.startswith(":=")):
                ok = False  # dict key or match pattern
            if ok and (before.endswith(("==", "!=", "Loc.t(", "tr(", " in", ".has(", "begins_with(", "ends_with(",
                                        "get_node(", "has_node(", "get_node_or_null(", "has_meta(", "get_meta(", "set_meta(",
                                        "push_error(", "print(", "push_warning(", "find(")) or after.startswith(("in ", "==", "!="))):
                ok = False
            if ok and "BUSES" in line:
                ok = False
            new += line[pos:a]
            if ok:
                new += 'Loc.t("%s")' % t
                changed += 1
            else:
                new += line[a:b]
                if player_text(t):
                    review.append("%s: %s" % (f, t)); skipped += 1
            pos = b
        new += line[pos:]
        out.append(new)
    if not DRY:
        open(f, "w", encoding="utf-8").write("\n".join(out))
print("wrapped", changed, "skipped-candidates", skipped)
for r in review:
    print("  skip", r)
