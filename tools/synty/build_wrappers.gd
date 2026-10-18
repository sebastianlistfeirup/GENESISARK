extends SceneTree
## Builds a wrapper scene per chosen Synty model and maps it to its slot.
##   godot --headless --path . --import            (after tools/synty/stage.py)
##   godot --headless --path . --script res://tools/synty/build_wrappers.gd [-- --choices=res://data/art/synty_choices.json]
##
## For every slot with status auto/approved/manual and a staged model:
##   1. instance the imported model (vendor file stays read-only; bible p.23)
##   2. apply the facing fix (choices[slot].rotation_y, default 0)
##   3. fit it to the slot's proxy, by slot kind:
##        module    - ship grid pieces: uniform scale so the footprint matches the 4 m cell, aligned to the proxy box
##        footprint - colony buildings: scale to sit inside the gameplay footprint, centred, base on the ground
##        size      - space objects: scale to the proxy's largest extent, centred
##        natural   - characters/props/rocks/vehicles: real size, only cm->m (x0.01) or m->cm fixes, feet on the ground
##      (choices[slot].fit overrides; choices[slot].extra_scale multiplies)
##   4. untextured materials get the pack's shared atlas (art/materials/<pack>_atlas.tres)
##      through the model's import settings ("Use External"), exactly what Advanced
##      Import Settings does by hand, so wrappers stay tiny and follow the source
##   5. save art/prefabs/<slot>.tscn and record it in data/art/slot_scenes.json
## If import settings changed it says so: run `godot --headless --path . --import` once more.
## Collision and interaction stay on the game's own nodes, never in wrappers.
## Report: evidence/synty_build.json.

const CHOICES := "res://data/art/synty_choices.json"


func _init() -> void:
	var choices_path := CHOICES
	var prefab_dir := SyntyWrapperBuilder.PREFABS
	var scenes_path := SyntyWrapperBuilder.SLOT_SCENES
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--choices="):
			choices_path = a.substr(10)
		elif a.begins_with("--prefabs="):
			prefab_dir = a.substr(10)
		elif a.begins_with("--slot-scenes="):
			scenes_path = a.substr(14)
	var doc: Variant = DictUtil.load_json(choices_path)
	if not doc is Dictionary:
		push_error("build_wrappers: cannot read " + choices_path)
		quit(1)
		return
	var builder := SyntyWrapperBuilder.new()
	var mapped := SyntyWrapperBuilder.load_mappings(scenes_path)
	var report: Array = []
	var failed := 0
	var choices: Dictionary = DictUtil.get_dict(doc, "choices")
	for slot: String in choices.keys():
		var c: Dictionary = choices[slot]
		if not str(c.get("status", "")) in SyntyWrapperBuilder.BUILD_STATUS or str(c.get("source", "")).is_empty():
			continue
		var r := builder.build_one(slot, c, prefab_dir)
		report.append(r)
		if r["ok"]:
			mapped[slot] = r["scene"]
		else:
			failed += 1
		print("%-28s %s %s" % [slot, "OK  " if r["ok"] else "FAIL", r.get("summary", r.get("error", ""))])
	SyntyWrapperBuilder.save_mappings(mapped, scenes_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var ev := FileAccess.open("res://evidence/synty_build.json", FileAccess.WRITE)
	ev.store_string(JSON.stringify({"built": report.size() - failed, "failed": failed, "slots": report}, "  "))
	ev.close()
	print("wrappers: %d built, %d failed -> %s" % [report.size() - failed, failed, scenes_path])
	if report.any(func(r: Dictionary) -> bool: return r.get("reimport", false)):
		print("import settings updated (atlas material): run  godot --headless --path . --import  once more")
	quit(1 if failed > 0 else 0)
