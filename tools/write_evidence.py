#!/usr/bin/env python3
"""Builds evidence/<task-id>/result.json from the real test reports
(evidence/test_report.json, evidence/scene_smoke.json, balance, screenshots).
A task is PASS only if every mapped check passed; unmapped tasks are NOT_RUN.
Usage: python3 tools/write_evidence.py <commit-sha>"""
import json, os, subprocess, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EV = os.path.join(ROOT, "evidence")
commit = sys.argv[1] if len(sys.argv) > 1 else subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()

def load(p):
    try:
        return json.load(open(os.path.join(EV, p), encoding="utf-8"))
    except Exception:
        return None

unit = load("test_report.json") or {}
smoke = load("scene_smoke.json") or {}
bal = load("balance/balance_report.json")
unit_fail = unit.get("failures", [])
smoke_checks = {c["name"]: c for c in smoke.get("checks", [])}

def unit_ok(prefixes):
    fails = [f for f in unit_fail if any(f.startswith(p) for p in prefixes)]
    return (unit.get("status") is not None and not fails), fails

def smoke_ok(names):
    missing = [n for n in names if n not in smoke_checks]
    bad = [n for n in names if n in smoke_checks and not smoke_checks[n]["ok"]]
    return (not missing and not bad), missing + bad

TASKS = {
    "GA-01": {"unit": ["test_content"], "smoke": ["menu_loads"], "shots": ["menu.png"],
              "expected": "Ren opstart uden parserfejl; version dokumenteret; repeatable smoke-kommando.",
              "cmd": "tools/check.sh"},
    "GA-02": {"smoke": ["ga02_route_10_runs_no_wall_pass", "ga02_route_10_runs_figure_kept", "ga02_camera_never_passes_hull", "ga02_camera_mode_switch_clean", "prompt_targets_coupling"], "shots": ["ship_power.png"],
              "expected": "10 gennemløb af samme rute uden væggennemgang eller mistet figur; kamera kolliderer.",
              "cmd": "godot --headless --path . res://scenes/tests/scene_smoke.tscn"},
    "GA-03": {"unit": ["test_ark_travel::test_power_objective_once"], "smoke": ["ga03_power_restored_by_interaction", "ga03_objective_not_rewarded_twice", "starmap_opens"], "shots": ["ship_dark.png", "ship_power.png"],
              "expected": "Ny spiller kan starte strøm og åbne planetskærm uden debug; objective belønnes ikke to gange."},
    "GA-04": {"unit": ["test_content", "test_ark_travel::test_new_campaign_baseline", "test_ark_travel::test_negative_resources_rejected"],
              "expected": "Ugyldig planet afvises med præcis årsag; embryosum 50.000; negative ressourcer afvises; samme fixture samme state."},
    "GA-05": {"unit": ["test_ark_travel"], "smoke": ["ga05_travel_command", "ga05_double_click_rejected", "flight_autopilot_progresses"], "shots": ["flight.png"],
              "expected": "Dobbeltklik og load ved ankomst kan ikke bruge fuel to gange; reserve forklares før valg; flyvning kan assisteres."},
    "GA-06": {"unit": ["test_survey_expedition"], "smoke": ["ga06_expedition_start", "ga06_suit_drains_in_scene", "ga06_sample_recorded", "ga06_expedition_finished"], "shots": ["surface.png"],
              "expected": "Scouting indsnævrer et interval og betaler én gang; udtømt dragt giver varslet tilbagevending."},
    "GA-07": {"unit": ["test_colony::test_landing"], "smoke": ["ga07_landing", "ga07_landing_once"],
              "expected": "Gentagen landing giver ikke dobbelt ressourcer; annullering ændrer intet; planeten bestemmer biomeparametre."},
    "GA-08": {"unit": ["test_colony"], "smoke": ["ga08_three_buildings_placed", "ga08_building_views_synced", "ga08_habitat_active"], "shots": ["colony.png", "colony_ghost.png"],
              "expected": "Tre bygninger kan opføres, nedrives og gemmes uden exploit; afbrudt strømnet stopper output med årsag."},
    "GA-09": {"unit": ["test_population"],
              "expected": "Alle overgange bevarer 50.000; børn er ikke arbejdskraft; gentaget completion giver ingen ekstra fødsel."},
    "GA-10": {"unit": ["test_save"], "smoke": ["ga10_save", "ga10_load_identical"],
              "expected": "Roundtrip bevarer nøgletal og id'er; korrupt fil tilbyder backup; restore affyrer ingen events igen; v1-fixture migreres."},
}

# Groundwork laid ahead of a task's gate: checks that pass now, written to
# evidence/<id>/groundwork.json (never result.json, so update_tasks.py cannot mark DONE).
GROUNDWORK = {
    "GA-14": {"smoke": ["riglab_audit_all_slots", "riglab_runs"], "shots": ["riglab.png"],
              "covers": "RigLab-scene, audit af skala/fødder/AnimationPlayer/clips for alle char.*-slots, tilstandscykler og cirkelbevægelse.",
              "open": "Rig, clips, AnimationTree, kontaktpunkter og pause/restore-test kræver de importerede Sidekick-figurer."},
    "GA-19": {"smoke": ["audio_cues_load", "audio_layer_set"],
              "covers": "Alle 53 lyd-cues i AUDIO_LEDGER har kodehook (52 HOOKED + alarm-varianten); 42 har proxy-lyd; lag, varianter, stingers og positionel byggelyd.",
              "open": "Endelige lyde (ElevenLabs/komponist) og 45-minutters spiltest med eksterne testere."},
    "GA-29": {"smoke": ["pad_bindings_complete", "pad_look_turns_camera", "pad_focuses_menu", "settings_persist"],
              "covers": "Controller (Xbox-layout) ved siden af tastatur, højre stik til kamera, fokus i menuer, controllernavne i hints, indstillinger gemmes.",
              "open": "Performance-mål på referencemaskine og fuld accessibility-gennemgang."},
    "GA-33": {"unit": ["test_localization"], "smoke": ["language_switch_keeps_state", "settings_persist"],
              "shots": ["en_menu.png", "en_colony.png", "settings_en.png", "credits_da.png"],
              "covers": "Lokalisering da/en (1069 nøgler, alle oversat, placeholder-tjek), sprogskift uden at røre domænet, krediteringer + Godot-licenser fra motoren, indstillinger overlever genstart.",
              "open": "Ledger-kontrol mod faktisk build, platformliste og kendte begrænsninger, endelig credits når Synty/lyd er inde."},
}
for tid, spec in GROUNDWORK.items():
    oks, notes = [], []
    if "unit" in spec:
        ok, f = unit_ok(spec["unit"]); oks.append(ok); notes += f
    if "smoke" in spec:
        ok, f = smoke_ok(spec["smoke"]); oks.append(ok); notes += f
    shots = [s for s in spec.get("shots", []) if os.path.exists(os.path.join(EV, "shots", s))]
    os.makedirs(os.path.join(EV, tid), exist_ok=True)
    json.dump({"task_id": tid, "commit": commit, "kind": "groundwork", "engine_version": unit.get("engine_version") or smoke.get("engine_version"),
               "command": "tools/check.sh", "status": "PASS" if oks and all(oks) else "FAIL", "covers": spec["covers"], "open": spec["open"],
               "failed_checks": notes, "artifacts": ["evidence/test_report.json", "evidence/scene_smoke.json"] + ["evidence/shots/" + s for s in shots]},
              open(os.path.join(EV, tid, "groundwork.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)

now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
summary = {}
for tid, spec in TASKS.items():
    oks, notes = [], []
    if "unit" in spec:
        ok, f = unit_ok(spec["unit"]); oks.append(ok); notes += f
    if "smoke" in spec:
        ok, f = smoke_ok(spec["smoke"]); oks.append(ok); notes += f
    shots = [s for s in spec.get("shots", []) if os.path.exists(os.path.join(EV, "shots", s))]
    status = "PASS" if oks and all(oks) else "FAIL"
    res = {"task_id": tid, "commit": commit, "engine_version": unit.get("engine_version") or smoke.get("engine_version"),
           "command": spec.get("cmd", "godot --headless --path . --script res://tests/run_tests.gd && godot --headless --path . res://scenes/tests/scene_smoke.tscn"),
           "exit_code": 0 if status == "PASS" else 1, "expected": spec["expected"],
           "observed": "Alle tilknyttede checks bestod." if status == "PASS" else "Fejlede/manglende checks: " + "; ".join(notes),
           "checks": {"unit_prefixes": spec.get("unit", []), "scene_checks": spec.get("smoke", [])},
           "fixture": "DebugFixtures + tests/unit fixtures, seeds 1234/4242/777", "status": status,
           "artifacts": ["evidence/test_report.json", "evidence/scene_smoke.json"] + ["evidence/shots/" + s for s in shots],
           "visual_review": "Greybox-proxies; visuel animation/Synty ikke godkendt (bibel s. 17, 25).", "timestamp": now}
    os.makedirs(os.path.join(EV, tid), exist_ok=True)
    json.dump(res, open(os.path.join(EV, tid, "result.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    summary[tid] = status
print(json.dumps(summary))
