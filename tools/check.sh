#!/usr/bin/env bash
# Fast local gate: re-import (refreshes class cache), domain tests, scene smoke.
# Usage: tools/check.sh   (GODOT_BIN overrides the binary)
set -u
GODOT="${GODOT_BIN:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import --quit-after 2000 >/tmp/ga_import.log 2>&1
grep -E "SCRIPT ERROR|Parse Error" /tmp/ga_import.log | sort -u | head -20
"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|tests,|Indholdsfejl" 
T=${PIPESTATUS[0]}
"$GODOT" --headless --path . --script res://tests/scene_smoke.gd 2>&1 | grep -E "SMOKE|FAIL|SCRIPT ERROR|ERROR" | sort -u | head -40
S=${PIPESTATUS[0]}
echo "tests_exit=$T smoke_exit=$S"
exit $(( T | S ))
