#!/usr/bin/env python3
"""Exports every story line to docs/VO_SCRIPT.csv for voice production
(ElevenLabs or a human actor). line_id matches the runtime lookup
assets/audio/vo/<line_id>.ogg. Re-run after editing data/story/scenes.json;
existing status/take columns are preserved.
Usage: python3 tools/export_vo_script.py"""
import csv, json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "VO_SCRIPT.csv")
VOICES = {"ARK": "ark_ai", "CAPTAIN": "captain", "NARRATOR": "narrator", "noor": "noor", "elias": "elias", "sana": "sana"}
DIRECTION = {
    "ARK": "Rolig, præcis, varm under overfladen. Lav dynamik, ingen robotfilter i optagelsen (tilføjes i Godot).",
    "CAPTAIN": "Træt, ensom, lavmælt. Kønsneutral rolle: vælg stemme bevidst og hold den hele spillet.",
    "NARRATOR": "Valgfri. Anbefaling: kun undertekst (bibel s. 13). Indtal kun hvis playtest viser behov.",
    "noor": "Ung voksen, fremadlænet, nysgerrig.", "elias": "Ung voksen, forsigtig, eftertænksom.", "sana": "Ung voksen, rolig og bestemt.",
}
old = {}
if os.path.exists(OUT):
    for r in csv.DictReader(open(OUT, encoding="utf-8")):
        old[r["line_id"]] = r
scenes = json.load(open(os.path.join(ROOT, "data", "story", "scenes.json"), encoding="utf-8"))["scenes"]
rows = []
for sc in scenes:
    for i, line in enumerate(sc["lines"], 1):
        lid = f"{sc['id']}_{i:02d}"
        sp = line["speaker"]
        prev = old.get(lid, {})
        rows.append({"line_id": lid, "scene": sc["id"], "trigger": sc.get("trigger", ""), "speaker": sp,
                     "voice_id": VOICES.get(sp, sp), "text_da": line["text"], "chars": len(line["text"]),
                     "direction": DIRECTION.get(sp, ""), "status": prev.get("status", "NEEDED"),
                     "take": prev.get("take", ""), "tool": prev.get("tool", ""), "license": prev.get("license", "")})
with open(OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
by = {}
for r in rows:
    by[r["speaker"]] = by.get(r["speaker"], 0) + r["chars"]
print(f"{len(rows)} lines, {sum(by.values())} chars:", by)
