#!/usr/bin/env python3
"""ONE-OFF: makes English the source language (D-025).

Reads a mapping CSV (keys = current Danish source text, en = English) and
  1. replaces every Loc.t("<danish>") literal and every label-dictionary value
     (loc_extract.DICT_CONSTS) in scripts/**/*.gd with the English text,
  2. replaces every player-facing text field (loc_extract.TEXT_KEYS) in data/**/*.json,
  3. writes localization/translations.csv inverted: keys = English, da = Danish.
Anything without a mapping is reported and left unchanged.

  python3 tools/loc_flip_source.py <mapping.csv> [--dry]
"""
import csv, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import loc_extract as LX  # noqa: E402

LIT = r'"((?:[^"\\]|\\.)*)"'


def unesc(s: str) -> str:
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def flip_code(mapping, dry, missing):
    changed = 0
    for base, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in files:
            if not f.endswith(".gd"):
                continue
            path = os.path.join(base, f)
            src = open(path, encoding="utf-8").read()
            out = src

            def sub_call(m):
                da = unesc(m.group(1))
                if da in mapping:
                    return 'Loc.t("%s")' % esc(mapping[da])
                missing.add(("code", os.path.relpath(path, ROOT), da))
                return m.group(0)

            out = re.sub(r'Loc\.t\(' + LIT + r'\)', sub_call, out)
            for name in LX.DICT_CONSTS:
                span = LX.dict_body(out, name)
                if not span:
                    continue

                def sub_val(vm):
                    da = unesc(vm.group(2))
                    if da in mapping:
                        return '%s: "%s"' % (vm.group(1), esc(mapping[da]))
                    missing.add(("dict", name, da))
                    return vm.group(0)

                body = re.sub(r'("(?:[^"\\]|\\.)*")\s*:\s*' + LIT, sub_val, out[span[0]:span[1]])
                out = out[:span[0]] + body + out[span[1]:]
            if out != src:
                changed += 1
                if not dry:
                    open(path, "w", encoding="utf-8").write(out)
    return changed


def indent_of(text: str) -> int:
    for line in text.splitlines()[1:]:
        if line.strip():
            return len(line) - len(line.lstrip(" "))
    return 2


def flip_data(mapping, dry, missing):
    changed = 0
    for base, _dirs, files in os.walk(os.path.join(ROOT, "data")):
        for f in files:
            if not f.endswith(".json"):
                continue
            path = os.path.join(base, f)
            rel = os.path.relpath(path, ROOT)
            if rel.split(os.sep)[1] in LX.SKIP_DATA:
                continue
            raw = open(path, encoding="utf-8").read()
            doc = json.loads(raw)
            hits = [0]

            def walk(o, key=None):
                if isinstance(o, dict):
                    for k in list(o.keys()):
                        v = o[k]
                        if isinstance(v, str) and k in LX.TEXT_KEYS and v.strip():
                            if v in mapping:
                                if mapping[v] != v:
                                    o[k] = mapping[v]
                                    hits[0] += 1
                            else:
                                missing.add(("data", rel, v))
                        else:
                            walk(v, k)
                elif isinstance(o, list):
                    for i, x in enumerate(o):
                        if isinstance(x, str) and key in LX.TEXT_KEYS and x.strip():
                            if x in mapping:
                                if mapping[x] != x:
                                    o[i] = mapping[x]
                                    hits[0] += 1
                            else:
                                missing.add(("data", rel, x))
                        else:
                            walk(x, key)

            walk(doc)
            if hits[0]:
                changed += 1
                if not dry:
                    with open(path, "w", encoding="utf-8") as fh:
                        json.dump(doc, fh, indent=indent_of(raw), ensure_ascii=False)
                        fh.write("\n")
    return changed


def main() -> int:
    dry = "--dry" in sys.argv
    src = [a for a in sys.argv[1:] if not a.startswith("--")][0]
    rows = list(csv.DictReader(open(src, encoding="utf-8")))
    mapping = {r["keys"]: r["en"] for r in rows if r["en"]}
    missing = set()
    c = flip_code(mapping, dry, missing)
    d = flip_data(mapping, dry, missing)
    if not dry:
        with open(LX.CSV_PATH, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=["keys", "da"], lineterminator="\n")
            w.writeheader()
            seen = set()
            for r in rows:
                if r["en"] and r["en"] not in seen:
                    seen.add(r["en"])
                    w.writerow({"keys": r["en"], "da": r["keys"]})
    print("flip: %d scripts, %d data files changed%s" % (c, d, " (dry run)" if dry else ""))
    for kind, where, text in sorted(missing)[:40]:
        print("  unmapped %-5s %-40s %s" % (kind, where[:40], text[:70].replace("\n", "\\n")))
    print("unmapped total:", len(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
