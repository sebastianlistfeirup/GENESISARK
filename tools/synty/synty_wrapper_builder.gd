class_name SyntyWrapperBuilder
extends RefCounted
## Turns one imported Synty model into a slot wrapper scene (shared by the
## command-line builder tools/synty/build_wrappers.gd and the editor dock
## addons/genesis_slots). See build_wrappers.gd for the rules.

const SLOT_SCENES := "res://data/art/slot_scenes.json"
const PREFABS := "res://art/prefabs/"
const MATERIALS := "res://art/materials/"
const BUILD_STATUS := ["auto", "approved", "manual"]
const MODULES := ["ship.floor", "ship.wall", "ship.wall_window", "ship.door", "ship.pillar", "ship.pipe", "ship.window_space", "ship.ceiling_light"]
const NATURAL_BUILDINGS := ["building.module_filter", "building.module_heater", "building.construction_frame"]


## Reads the slot -> scene map written by the builder.
static func load_mappings(path: String = SLOT_SCENES) -> Dictionary:
	var prev: Variant = DictUtil.load_json(path) if FileAccess.file_exists(path) else null
	return DictUtil.get_dict(prev, "scenes") if prev is Dictionary else {}


static func save_mappings(mapped: Dictionary, path: String = SLOT_SCENES) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify({"_note": "Written by the Synty wrapper builder: slot -> wrapper scene. A non-empty \"scene\" in asset_slots.json wins over this file.", "scenes": mapped}, " ", true) + "\n")
	out.close()


static func fit_mode(slot: String) -> String:
	if slot in MODULES:
		return "module"
	if slot.begins_with("building.") and not slot in NATURAL_BUILDINGS:
		return "footprint"
	if slot.begins_with("space."):
		return "size"
	return "natural"


func build_one(slot: String, c: Dictionary, prefab_dir: String) -> Dictionary:
	var src := str(c["source"])
	var pack := src.trim_prefix("res://assets/imported/").get_slice("/", 0)
	var model_path := src if src.begins_with("res://") else "res://assets/imported/" + src
	if not ResourceLoader.exists(model_path):
		return {"slot": slot, "ok": false, "error": "not staged/imported: %s (run tools/synty/stage.py, then godot --import)" % model_path}
	var ps: PackedScene = load(model_path)
	if ps == null:
		return {"slot": slot, "ok": false, "error": "could not load " + model_path}
	var root := Node3D.new()
	root.name = slot.replace(".", "_")
	var model: Node3D = ps.instantiate()
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	model.rotation_degrees.y = float(c.get("rotation_y", 0.0))
	var raw := AssetSlots.aabb_of(model, model.transform)
	var proxy_node := AssetSlots.build_proxy(slot)
	var proxy := AssetSlots.aabb_of(proxy_node, Transform3D.IDENTITY)
	proxy_node.free()
	if raw.size == Vector3.ZERO:
		root.free()
		return {"slot": slot, "ok": false, "error": "model has no visible geometry"}
	var mode := str(c.get("fit", fit_mode(slot)))
	var s := 1.0
	var notes: Array = []
	match mode:
		"module":
			s = maxf(proxy.size.x, proxy.size.z) / maxf(maxf(raw.size.x, raw.size.z), 0.001)
		"footprint":
			s = minf(proxy.size.x / maxf(raw.size.x, 0.001), proxy.size.z / maxf(raw.size.z, 0.001))
		"size":
			s = maxf(proxy.size.x, maxf(proxy.size.y, proxy.size.z)) / maxf(maxf(raw.size.x, maxf(raw.size.y, raw.size.z)), 0.001)
		_:
			var ratio := proxy.size.y / maxf(raw.size.y, 0.001)
			if ratio < 0.05:
				s = 0.01
				notes.append("centimetres -> metres (x0.01)")
			elif ratio > 20.0:
				s = 100.0
				notes.append("metres*100 -> x100")
	s *= float(c.get("extra_scale", 1.0))
	model.scale = Vector3.ONE * s
	var scaled := AssetSlots.aabb_of(model, model.transform)
	# Align: centre on the proxy in x/z, base on the proxy's base (module: same box).
	var target_center := proxy.get_center()
	var shift := Vector3(target_center.x - scaled.get_center().x, proxy.position.y - scaled.position.y, target_center.z - scaled.get_center().z)
	model.position += shift
	var final := AssetSlots.aabb_of(model, model.transform)
	var need: Dictionary = {}
	_untextured_materials(model, need)
	var uses_atlas := _uses_material_dir(model, MATERIALS)
	var mat_count := need.size()
	var reimport := false
	if not need.is_empty():
		var atlas := _atlas_material(pack)
		if atlas:
			reimport = _use_external(model_path, need.keys(), atlas.resource_path)
		else:
			notes.append("no atlas texture staged for " + pack)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefab_dir))
	var scene_path := prefab_dir.path_join(slot + ".tscn")
	root.set_meta("synty_source", src)
	root.set_meta("synty_fit", mode)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, scene_path)
	root.free()
	if err != OK:
		return {"slot": slot, "ok": false, "error": "save failed (%d)" % err}
	var dev := Vector3(final.size.x / maxf(proxy.size.x, 0.001), final.size.y / maxf(proxy.size.y, 0.001), final.size.z / maxf(proxy.size.z, 0.001))
	var warn: Array = []
	if mode == "natural" and (dev.y < 0.5 or dev.y > 2.0):
		warn.append("height %.0f%% of the proxy: check the scale or choose another model" % (dev.y * 100.0))
	if mode == "footprint" and dev.y > 2.5:
		warn.append("much taller than the proxy (%.1fx): check the silhouette in the colony" % dev.y)
	return {"slot": slot, "ok": true, "scene": scene_path, "source": src, "fit": mode, "scale": snappedf(s, 0.0001),
		"size_m": [snappedf(final.size.x, 0.01), snappedf(final.size.y, 0.01), snappedf(final.size.z, 0.01)],
		"proxy_m": [snappedf(proxy.size.x, 0.01), snappedf(proxy.size.y, 0.01), snappedf(proxy.size.z, 0.01)],
		"atlas_materials": mat_count, "uses_atlas": uses_atlas, "reimport": reimport, "notes": notes, "warnings": warn,
		"summary": "%s x%.3f -> %.1fx%.1fx%.1f m (proxy %.1fx%.1fx%.1f)%s" % [mode, s, final.size.x, final.size.y, final.size.z,
			proxy.size.x, proxy.size.y, proxy.size.z, ("  ▲ " + "; ".join(warn)) if not warn.is_empty() else ""]}


## Shared atlas material for the pack, created once from its staged atlas texture.
func _atlas_material(pack: String) -> Material:
	var path := MATERIALS.path_join(pack.to_snake_case() + "_atlas.tres")
	if ResourceLoader.exists(path):
		return load(path)
	var staged: Variant = DictUtil.load_json("res://assets/imported/%s/staged.json" % pack)
	var tex_path := ""
	if staged is Dictionary:
		for t: Variant in DictUtil.get_arr(staged, "atlas"):
			tex_path = "res://" + str(t)
			break
	if tex_path.is_empty() or not ResourceLoader.exists(tex_path):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex_path)
	m.roughness = 0.85
	m.metallic = 0.0
	m.resource_name = pack + " atlas"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATERIALS))
	ResourceSaver.save(m, path)
	return load(path)


## True when any surface already renders with a material from art/materials (after import).
func _uses_material_dir(n: Node, dir: String) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for i: int in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat and mat.resource_path.begins_with(dir):
				return true
	for ch: Node in n.get_children():
		if _uses_material_dir(ch, dir):
			return true
	return false


## Names of imported materials without a colour texture (Synty FBX often lose the atlas link).
func _untextured_materials(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for i: int in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture == null and not mat.resource_name.is_empty():
				out[mat.resource_name] = true
	for ch: Node in n.get_children():
		_untextured_materials(ch, out)


## Points the named materials of a model at an external material in its .import
## file. Returns true when the file changed (a re-import is needed).
func _use_external(model_path: String, names: Array, material_path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(model_path + ".import") != OK:
		return false
	var sub: Dictionary = cfg.get_value("params", "_subresources", {})
	var mats: Dictionary = sub.get("materials", {})
	var changed := false
	for n: String in names:
		var cur: Dictionary = mats.get(n, {})
		if cur.get("use_external/path", "") != material_path or not cur.get("use_external/enabled", false):
			cur["use_external/enabled"] = true
			cur["use_external/path"] = material_path
			mats[n] = cur
			changed = true
	if changed:
		sub["materials"] = mats
		cfg.set_value("params", "_subresources", sub)
		cfg.save(model_path + ".import")
	return changed
