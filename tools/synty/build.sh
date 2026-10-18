#!/usr/bin/env bash
# Synty -> game in one go, after unpack.py and a look at data/art/synty_choices.json:
#   stage chosen files -> Godot import -> build wrappers -> (re-import if atlas
#   materials were set) -> build again -> audit.  Usage: tools/synty/build.sh
set -euo pipefail
GODOT="${GODOT_BIN:-godot}"
cd "$(dirname "$0")/../.."
python3 tools/synty/stage.py "$@"
"$GODOT" --headless --path . --import --quit-after 3000 >/dev/null 2>&1 || true
OUT=$("$GODOT" --headless --path . --script res://tools/synty/build_wrappers.gd 2>&1 | grep -vE "^Godot Engine|^$" || true)
echo "$OUT"
if echo "$OUT" | grep -q "import settings updated"; then
	"$GODOT" --headless --path . --import --quit-after 3000 >/dev/null 2>&1 || true
	"$GODOT" --headless --path . --script res://tools/synty/build_wrappers.gd 2>&1 | grep -E "wrappers:|FAIL" || true
fi
echo "Report: evidence/synty_build.json · see it in the game: godot --path . (or F5)"
