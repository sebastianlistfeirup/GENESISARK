#!/usr/bin/env python3
"""Extracts every player-facing English source string into localization/translations.csv.

English source text is the translation key (D-017, D-025); the da column is the Danish translation. Sources:
  1. Loc.t("...") literals in scripts/**/*.gd
  2. Values of label dictionaries (const NAME := {...}) listed in DICT_CONSTS
  3. Text fields (TEXT_KEYS) in data/**/*.json — the same keys ContentDB.localize() walks

Existing translations in the CSV are kept; new keys get an empty English cell that
falls back to the Danish source at runtime. Keys that no longer exist are dropped
(reported) so the file never rots.
Usage: python3 tools/loc_extract.py [--check]   (--check exits 1 if the CSV is stale
                                                  or any key lacks a translation)"""
import csv, glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "localization", "translations.csv")
LANGS = ["da"]
LOC_CALL = re.compile(r'Loc\.t\("((?:[^"\\]|\\.)*)"\)')
STR = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
DICT_CONSTS = ["ACTION_LABELS", "PROPERTY_LABELS", "ATMOSPHERE_LABELS", "PRIORITY_LABELS", "REASONS", "STOP_TEXT",
               "FACT_LABELS", "SLOT_LABELS", "RES_LABELS", "SIDE_TEXT"]
# Keep in sync with ContentDB.TEXT_KEYS.
TEXT_KEYS = {"name", "description", "label", "result", "settlement_name", "text", "title", "warning", "criteria_text",
             "epilogue", "summary", "advantage", "briefing", "evacuation", "goal", "main", "price", "relay", "risk",
             "robust_plan", "tagline", "hint", "bio", "zone_label", "risk_note", "short", "subtitle", "role", "unit"}
SKIP_DATA = {"art", "levels", "balance"}


def unescape(s: str) -> str:
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def dict_body(src: str, name: str):
    """(start, end) of the body of `const NAME := {...}`, braces balanced, strings skipped."""
    m = re.search(r"const %s\s*:?=\s*\{" % name, src)
    if not m:
        return None
    depth, i, in_str = 1, m.end(), False
    while i < len(src) and depth:
        ch = src[i]
        if in_str:
            if ch == "\\":
                i += 1
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        i += 1
    return (m.end(), i - 1)


def from_code() -> dict:
    out = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "scripts/**/*.gd"), recursive=True)):
        rel = os.path.relpath(f, ROOT)
        src = open(f, encoding="utf-8").read()
        for m in LOC_CALL.finditer(src):
            out.setdefault(unescape(m.group(1)), rel)
        for name in DICT_CONSTS:
            span = dict_body(src, name)
            if not span:
                continue
            for km in STR.finditer(src[span[0]:span[1]]):
                out.setdefault(unescape(km.group(2)), "%s:%s" % (rel, name))
    return out


def from_data() -> dict:
    out = {}

    def walk(o, key, rel):
        if isinstance(o, dict):
            for k, v in o.items():
                walk(v, k, rel)
        elif isinstance(o, list):
            for v in o:
                walk(v, key, rel)
        elif isinstance(o, str) and key in TEXT_KEYS and o.strip():
            out.setdefault(o, rel)

    for f in sorted(glob.glob(os.path.join(ROOT, "data/**/*.json"), recursive=True)):
        rel = os.path.relpath(f, ROOT)
        if rel.split(os.sep)[1] in SKIP_DATA:
            continue
        walk(json.load(open(f, encoding="utf-8")), None, rel)
    return out


def load_existing() -> dict:
    if not os.path.exists(CSV_PATH):
        return {}
    with open(CSV_PATH, encoding="utf-8", newline="") as fh:
        return {row["keys"]: row for row in csv.DictReader(fh)}


def main() -> int:
    check = "--check" in sys.argv
    keys = {}
    keys.update(from_data())
    keys.update(from_code())
    existing = load_existing()
    rows = []
    for k in sorted(keys, key=lambda s: (keys[s], s)):
        row = {"keys": k}
        for lang in LANGS:
            row[lang] = existing.get(k, {}).get(lang, "")
        rows.append(row)
    dropped = sorted(set(existing) - set(keys))
    missing = [r["keys"] for r in rows if not all(r[l] for l in LANGS)]
    added = [k for k in keys if k not in existing]
    print("loc_extract: %d keys (%d code, %d data), %d new, %d dropped, %d untranslated"
          % (len(rows), len(from_code()), len(from_data()), len(added), len(dropped), len(missing)))
    if check:
        for k in added[:20]:
            print("  NEW  ", k[:90])
        for k in missing[:20]:
            print("  TODO ", k[:90])
        return 1 if (added or dropped or missing) else 0
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["keys"] + LANGS, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    for k in dropped[:20]:
        print("  dropped:", k[:90])
    return 0


if __name__ == "__main__":
    sys.exit(main())
