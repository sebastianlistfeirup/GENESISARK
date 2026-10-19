#!/usr/bin/env bash
# Fast local gate: re-import (refreshes class cache), parse-check every script,
# translation sync, domain tests, scene smoke, touch feel, one full campaign. Fails fast on parse errors so a
# broken script can never hang the smoke run.
# Usage: tools/check.sh   (GODOT_BIN overrides the binary)
set -u
GODOT="${GODOT_BIN:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import --quit-after 2000 >/tmp/ga_import.log 2>&1
grep -E "SCRIPT ERROR|Parse Error" /tmp/ga_import.log | sort -u | head -20
C_OUT=$(timeout 120 "$GODOT" --headless --path . res://scenes/tests/compile_all.tscn 2>&1 | grep -E "^COMPILE")
echo "$C_OUT"
if ! echo "$C_OUT" | grep -q " 0 failed"; then
	echo "compile_exit=1 (parse errors above; run: godot --headless --path . --check-only --script <file>)"
	exit 1
fi
python3 tools/loc_extract.py --check
L=$?
T_OUT=$("$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1)
T=$?
echo "$T_OUT" | grep -E "FAIL|SCRIPT ERROR|tests,|Indholdsfejl"
# A script error inside a test aborts that test silently; treat it as a failure.
if echo "$T_OUT" | grep -q "SCRIPT ERROR"; then T=1; fi
S_OUT=$(timeout 300 "$GODOT" --headless --path . res://scenes/tests/scene_smoke.tscn 2>&1)
S=$?
echo "$S_OUT" | grep -E "SMOKE|FAIL|SCRIPT ERROR|ERROR" | sort -u | head -120
if echo "$S_OUT" | grep -q "SCRIPT ERROR"; then S=1; fi
F_OUT=$(timeout 120 "$GODOT" --headless --path . res://scenes/tests/touch_feel.tscn -- --touch 2>&1)
F=$?
echo "$F_OUT" | grep -E "^TOUCH|SCRIPT ERROR"
if echo "$F_OUT" | grep -q "SCRIPT ERROR"; then F=1; fi
# One whole campaign (Sere, middle choices) with invariants and save round-trips.
# Full matrix: godot --headless --path . --script res://tools/campaign/campaign_bot.gd  (~7 min). CHECK_FAST=1 skips.
B=0
if [ "${CHECK_FAST:-0}" != "1" ]; then
	B_OUT=$(timeout 300 "$GODOT" --headless --path . --script res://tools/campaign/campaign_bot.gd -- --planet=sere --policy=middle 2>&1)
	B=$?
	echo "$B_OUT" | grep -E "^CAMPAIGN|^FAIL|SCRIPT ERROR"
	if echo "$B_OUT" | grep -q "SCRIPT ERROR"; then B=1; fi
fi
echo "loc_exit=$L tests_exit=$T smoke_exit=$S touch_exit=$F campaign_exit=$B"
exit $(( L | T | S | F | B ))
