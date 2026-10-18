#!/usr/bin/env python3
"""Exports every story line to docs/VO_SCRIPT.csv for voice production
(ElevenLabs or a human actor). line_id matches the runtime lookup
assets/audio/vo/<line_id>.ogg. Re-run after editing data/story/scenes.json;
existing status/take columns are preserved.
Usage: python3 tools/export_vo_script.py"""
import csv, json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "VO_SCRIPT.csv")
VOICES = {"NAV": "nav_computer", "ARK": "ark_ai", "CAPTAIN": "captain", "NARRATOR": "narrator", "noor": "noor", "elias": "elias", "sana": "sana"}
DIRECTION = {
    "NAV": "Navigation computer: dry, matter-of-fact, entirely without emotion, even pace, numbers clearly spoken. No warmth, no humor in the voice (the dryness is in the words).",
    "ARK": "Calm, precise, warm underneath. Low dynamics, no robot filter in the recording (added in Godot).",
    "CAPTAIN": "Tired, lonely, quiet. Gender-neutral role: choose the voice deliberately and keep it for the whole game.",
    "NARRATOR": "Optional. Recommendation: subtitles only (bible p.13). Record only if playtests show a need.",
    "noor": "Young adult, forward-leaning, curious.", "elias": "Young adult, cautious, thoughtful.", "sana": "Young adult, calm and firm.",
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
                     "voice_id": VOICES.get(sp, sp), "text": line["text"], "chars": len(line["text"]),
                     "direction": DIRECTION.get(sp, ""), "status": prev.get("status", "NEEDED"),
                     "take": prev.get("take", ""), "tool": prev.get("tool", ""), "license": prev.get("license", "")})
# NAV (data/story/nav.json): lines with {numbers} are filled in at runtime. Record the
# number-free ones as nav_<id>; the dynamic ones play with subtitle + computer tick
# until a runtime TTS or number splicing is chosen (docs/PRODUCTION_PLAN.md §5).
nav = json.load(open(os.path.join(ROOT, "data", "story", "nav.json"), encoding="utf-8"))["lines"]
for nid, nl in nav.items():
    lid = "nav_" + nid
    prev = old.get(lid, {})
    dyn = "{" in nl["text"]
    rows.append({"line_id": lid, "scene": "nav", "trigger": nid, "speaker": "NAV", "voice_id": VOICES["NAV"], "text": nl["text"],
                 "chars": len(nl["text"]), "direction": DIRECTION["NAV"] + (" DYNAMIC: numbers are filled in by the game." if dyn else ""),
                 "status": prev.get("status", "DYNAMIC" if dyn else "NEEDED"), "take": prev.get("take", ""), "tool": prev.get("tool", ""),
                 "license": prev.get("license", "")})
with open(OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
by = {}
for r in rows:
    by[r["speaker"]] = by.get(r["speaker"], 0) + r["chars"]
print(f"{len(rows)} lines, {sum(by.values())} chars:", by)
