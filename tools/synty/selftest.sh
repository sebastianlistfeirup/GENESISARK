#!/usr/bin/env bash
# End-to-end test of the Synty pipeline with a FAKE pack (no purchased files):
# make_test_pack -> unpack -> match -> stage -> import -> build -> import -> build,
# then checks the report and removes everything it created.
# Usage: tools/synty/selftest.sh   (exit 0 = pipeline works)
set -uo pipefail
GODOT="${GODOT_BIN:-godot}"
cd "$(dirname "$0")/../.."
TMP=$(mktemp -d)
PACK=SelfTestSyntyPack
CHOICES=res://assets/imported/$PACK.choices.json
cleanup() {
	rm -rf "assets/quarantine/$PACK" "assets/imported/$PACK" "assets/imported/$PACK.choices.json"* \
		art/prefabs/_selftest "art/materials/$(echo $PACK | sed -E 's/([a-z])([A-Z])/\1_\2/g' | tr A-Z a-z)_atlas.tres"* \
		data/art/_selftest_slot_scenes.json* "$TMP"
	rmdir art/prefabs art/materials art 2>/dev/null || true
}
trap cleanup EXIT
python3 tools/synty/make_test_pack.py "$TMP/$PACK.unitypackage" >/dev/null
python3 tools/synty/unpack.py "$TMP/$PACK.unitypackage" --pack $PACK
python3 tools/synty/match.py --packs $PACK --out "assets/imported/$PACK.choices.json" | tail -1
python3 tools/synty/stage.py --choices "assets/imported/$PACK.choices.json"
ARGS=(--choices=$CHOICES --prefabs=res://art/prefabs/_selftest --slot-scenes=res://data/art/_selftest_slot_scenes.json)
for pass in 1 2; do
	"$GODOT" --headless --path . --import --quit-after 3000 >/dev/null 2>&1
	"$GODOT" --headless --path . --script res://tools/synty/build_wrappers.gd -- "${ARGS[@]}" 2>&1 | grep -E "wrappers:|FAIL|import settings"
done
python3 - <<'PY'
import json, sys
r = {s["slot"]: s for s in json.load(open("evidence/synty_build.json"))["slots"]}
checks = {
    "all built": all(s["ok"] for s in r.values()) and len(r) >= 10,
    "crate cm -> m": abs(r["ship.crate"]["scale"] - 0.01) < 1e-6 and abs(r["ship.crate"]["size_m"][1] - 1.2) < 0.02,
    "floor fits 4 m grid": r["ship.floor"]["size_m"][0] == 4.0 and r["ship.floor"]["size_m"][2] == 4.0,
    "habitat inside footprint": r["building.habitat"]["size_m"][0] <= r["building.habitat"]["proxy_m"][0] + 0.01,
    "atlas material in use": all(s["uses_atlas"] for s in r.values()),
    "too-small rock flagged": bool(r["surface.desert_rock"]["warnings"]),
    "rock variants built": len(r["surface.rock_small"].get("scenes", [])) == 3,
}
for k, v in checks.items():
    print(("PASS " if v else "FAIL ") + k)
sys.exit(0 if all(checks.values()) else 1)
PY
RC=$?
mv evidence/synty_build.json evidence/synty_selftest.json 2>/dev/null
exit $RC
