#!/usr/bin/env python3
"""Validates tasks.json (bible p.48): unique ids, known dependencies, no cycles,
36 cards in 4 phases, valid statuses, DONE tasks have evidence. Prints the next
READY candidates (all depends_on DONE). Exit 1 on errors.
Usage: python3 tools/validate_plan.py [path/to/tasks.json]"""
import json, os, sys

STATUSES = {"TODO", "READY", "IN_PROGRESS", "VERIFYING", "DONE", "REWORK", "BLOCKED_ENVIRONMENT", "DROPPED"}
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "tasks.json")
tasks = json.load(open(path, encoding="utf-8"))["tasks"]
errors = []
ids = [t["id"] for t in tasks]
if len(ids) != len(set(ids)):
    errors.append("duplicate ids")
if len(tasks) != 36:
    errors.append(f"expected 36 tasks, found {len(tasks)}")
if sorted({t["phase"] for t in tasks}) != [1, 2, 3, 4]:
    errors.append("expected phases 1-4")
by_id = {t["id"]: t for t in tasks}
for t in tasks:
    if t["status"] not in STATUSES:
        errors.append(f"{t['id']}: unknown status {t['status']}")
    for d in t["depends_on"]:
        if d not in by_id:
            errors.append(f"{t['id']}: unknown dependency {d}")
    if t["status"] == "DONE":
        ev = os.path.join(root, t.get("evidence", ""))
        if not os.path.exists(ev):
            errors.append(f"{t['id']}: DONE without evidence file {t.get('evidence')}")
        for d in t["depends_on"]:
            if by_id.get(d, {}).get("status") != "DONE":
                errors.append(f"{t['id']}: DONE but dependency {d} is {by_id.get(d, {}).get('status')}")
# cycle check
state = {}
def visit(n, stack):
    if state.get(n) == 1:
        errors.append("cycle: " + " -> ".join(stack + [n])); return
    if state.get(n) == 2:
        return
    state[n] = 1
    for d in by_id[n]["depends_on"]:
        if d in by_id:
            visit(d, stack + [n])
    state[n] = 2
for i in ids:
    visit(i, [])
ready = [t["id"] for t in tasks if t["status"] in ("TODO", "READY", "REWORK")
         and all(by_id[d]["status"] == "DONE" for d in t["depends_on"])]
counts = {}
for t in tasks:
    counts[t["status"]] = counts.get(t["status"], 0) + 1
print("status:", counts)
print("next READY candidates:", ready[:6])
if errors:
    print("ERRORS:"); [print("  -", e) for e in errors]; sys.exit(1)
print("plan OK")
