#!/usr/bin/env bash
# Fast local gate: re-import (refreshes class cache), parse-check every script,
# translation sync, domain tests, scene smoke. Fails fast on parse errors so a
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
timeout 300 "$GODOT" --headless --path . res://scenes/tests/scene_smoke.tscn 2>&1 | grep -E "SMOKE|FAIL|SCRIPT ERROR|ERROR" | sort -u | head -120
S=${PIPESTATUS[0]}
timeout 120 "$GODOT" --headless --path . res://scenes/tests/touch_feel.tscn -- --touch 2>&1 | grep -E "^TOUCH|SCRIPT ERROR"
F=${PIPESTATUS[0]}
echo "loc_exit=$L tests_exit=$T smoke_exit=$S touch_exit=$F"
exit $(( L | T | S | F ))
