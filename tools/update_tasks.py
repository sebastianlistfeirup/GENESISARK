#!/usr/bin/env python3
"""Sets task statuses from the evidence files (DONE only with a PASS result.json)
and records implementation notes for work done ahead of a gate.
Usage: python3 tools/update_tasks.py <commit>"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
commit = sys.argv[1]
path = os.path.join(ROOT, "tasks.json")
d = json.load(open(path, encoding="utf-8"))
NOTES = {
    "GA-11": ("VERIFYING", "Hele kæden ark→stjernekort→indflyvning→ekspedition→landing→robotkoloni→save/load er implementeret og kørt automatisk (scene_smoke). Mangler: én optaget menneskelig 20-min gennemspilning og retning af de tre største friktioner."),
    "GA-12": ("VERIFYING", "Linux- og Windows-eksport lykkedes; Linux-build kørt under Xvfb (screenshot). Mangler: Windows-build kørt på referencemaskinen, visuel kontrol og GA-11 DONE før fase 1-tag."),
    "GA-13": ("TODO", "Klar: VisualSlot-registret (81 slots), wrapper-regler, ledger og samleguide (docs/SCENE_ASSEMBLY.md). Kræver de købte Synty-filer."),
    "GA-14": ("TODO", "Klar: CharacterAnimator + data/art/animation_map.json (in-place, hastighedsskaleret). Kræver rig og klip."),
    "GA-15": ("IN_PROGRESS", "Implementeret før porten: seks planeter, 3 sites pr. biome, viden i fire niveauer med validator, sammenligning kendt/skøn/ukendt, balance-harness viser levedygtig plan pr. planet."),
    "GA-16": ("IN_PROGRESS", "Implementeret før porten: 12 byggeklasser, moduler, workforce, vedligehold, batteri, biomemodifikatorer, prioriteret strøm, cancel/refusion."),
    "GA-17": ("IN_PROGRESS", "Implementeret: kohorter, omsorg/uddannelse/helbred, krav til første fødsel, første-fødsel-scene (lys/lyd/tekst)."),
    "GA-18": ("IN_PROGRESS", "Greybox: tre biome-terræner, farezoner og en kolonifare pr. biome (moduler/storme/nat). Synty-dressing mangler."),
    "GA-19": ("TODO", "Undertekster, UI-skala, lydgrupper og alarmer findes. Eksterne testere utilgængelige i ferien (udestående)."),
    "GA-21": ("IN_PROGRESS", "Implementeret: deterministisk dag-simulator, prognose→godkend, stop ved krise/underskud, institutioner efter plan; test viser prognose == resultat."),
    "GA-22": ("IN_PROGRESS", "Seks håndskrevne scoutingproblemer i data/surveys med to ruter, risikoprøve og evakuering."),
    "GA-23": ("IN_PROGRESS", "Tre biomekriser + seks borgerhændelser med pris, krav, konsekvens og gratis fallback."),
    "GA-24": ("IN_PROGRESS", "Råd (kræver voksne + skole), tre unge stemmer ved år 20, tillid/selvbestemmelse."),
    "GA-25": ("IN_PROGRESS", "Tre slutprofiler fra faktiske målinger, epilog med planet/kriser/kohorter, final_state og fortsæt fra backup."),
    "GA-28": ("IN_PROGRESS", "tools/balance/run_balance.gd: 6 planeter × 3 strategier til år 40; se evidence/balance."),
    "GA-29": ("IN_PROGRESS", "Tasteomlægning, UI-skala, reduceret bevægelse, undertekster; profilering af dagstick (tools/balance/profile_tick.gd)."),
}
for t in d["tasks"]:
    ev = os.path.join(ROOT, "evidence", t["id"], "result.json")
    if os.path.exists(ev) and json.load(open(ev, encoding="utf-8")).get("status") == "PASS":
        t["status"] = "DONE"
        t["last_commit"] = commit
        t["owner"] = "claude-code (ferie-session)"
    if t["id"] in NOTES:
        st, note = NOTES[t["id"]]
        if t["status"] != "DONE":
            t["status"] = st
        t["notes"] = note
        t["owner"] = "claude-code (ferie-session)"
        if st in ("IN_PROGRESS", "VERIFYING"):
            t["last_commit"] = commit
json.dump(d, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print({s: sum(1 for t in d["tasks"] if t["status"] == s) for s in {t["status"] for t in d["tasks"]}})
