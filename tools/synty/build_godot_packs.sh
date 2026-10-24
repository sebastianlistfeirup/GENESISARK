#!/usr/bin/env bash
# Builds slot wrappers from Synty packs already extracted into assets/Synty
# (Godot-format packs + source FBX for characters/animations). Two passes:
# retarget/material import settings -> re-import -> wrappers + animation libraries.
set -uo pipefail
GODOT="${GODOT_BIN:-godot}"
cd "$(dirname "$0")/../.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tools/synty/build_wrappers.gd 2>&1 | grep -vE "^Godot Engine|^$|leaked|Leaked|at: |RID alloc|PagedAllocator|resources still" || true
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tools/synty/build_wrappers.gd 2>&1 | grep -vE "^Godot Engine|^$|leaked|Leaked|at: |RID alloc|PagedAllocator|resources still" || true
