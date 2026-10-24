class_name SyntyFixes
extends RefCounted
## In-memory corrections to purchased Synty meshes (D-043). The pack files are
## shared and read-only, so nothing is written: at boot each listed mesh
## resource is loaded once and kept referenced, and its surfaces are cleared,
## so every prefab instance, tracked wrapper and baked MultiMesh copy made
## afterwards draws nothing for it. Data: data/art/synty_fixes.json
## ("hide_meshes": extracted .res paths). Missing files are skipped.

const PATH := "res://data/art/synty_fixes.json"

static var _held: Array = []  # keeps the patched resources in the loader cache


static func apply() -> void:
	if not _held.is_empty():
		return
	var d: Variant = DictUtil.load_json(PATH)
	if not d is Dictionary:
		return
	for p: Variant in DictUtil.get_arr(d, "hide_meshes"):
		var path := str(p)
		if not ResourceLoader.exists(path):
			continue
		var m := load(path) as ArrayMesh
		if m == null:
			continue
		m.clear_surfaces()
		_held.append(m)
