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


## Builds the slot's wrapper, or one per entry in c["variants"] (slot.tscn,
## slot__2.tscn, ...). Returns the first result with "scenes" listing all.
func build_slot(slot: String, c: Dictionary, prefab_dir: String) -> Dictionary:
	var sources: Array = Array(c.get("variants", []))
	if sources.size() < 2:
		return build_one(slot, c, prefab_dir)
	var first: Dictionary = {}
	var scenes: Array = []
	var reimport := false
	for i: int in sources.size():
		var vc := c.duplicate()
		vc["source"] = str(sources[i])
		var r := build_one(slot, vc, prefab_dir, "" if i == 0 else "__%d" % (i + 1))
		if not r["ok"]:
			return r
		reimport = reimport or bool(r.get("reimport", false))
		scenes.append(r["scene"])
		if first.is_empty():
			first = r
	first["scenes"] = scenes
	first["reimport"] = reimport
	first["summary"] = "%s  (+%d varianter)" % [first["summary"], scenes.size() - 1]
	return first


func build_one(slot: String, c: Dictionary, prefab_dir: String, suffix: String = "") -> Dictionary:
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
	var model: Node3D
	if model_path.ends_with(".tscn") or model_path.ends_with(".scn"):
		# A ready-made Godot prefab (Synty's Godot packs): copy only what is drawn,
		# never its physics bodies; collision belongs to the game's own nodes (bible p.23).
		model = flatten_prefab(ps)
	else:
		model = ps.instantiate()
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	_own_all(model, root)
	var only := str(c.get("only_mesh", ""))
	if not only.is_empty():
		# Multi-character FBX: VisualSlot shows this body and hides the others when it
		# instances the wrapper. (Overriding visibility here would make the wrapper
		# embed a stale copy of the imported Skin and break skinning after re-import.)
		root.set_meta("only_mesh", only)
		apply_only_mesh(model, only)
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
	var rig := {}
	if slot.begins_with("char.") and not model.find_children("*", "Skeleton3D", true, false).is_empty():
		# Humanoid: import with the shared bone map so any retargeted animation plays on it.
		rig = HumanoidBoneMapper.apply_retarget(model_path)
		if rig.get("changed", false):
			notes.append("retarget bone map set (re-import)")
		if not Array(rig.get("missing_core", [])).is_empty():
			notes.append("bone map missing: " + ", ".join(rig["missing_core"]))
	var need: Dictionary = {}
	_untextured_materials(model, need)
	var uses_atlas := _uses_material_dir(model, MATERIALS)
	var mat_count := need.size()
	var reimport := false
	if not need.is_empty():
		var atlas: Material = load(str(c["material"])) if c.has("material") else _atlas_material(pack)
		if atlas:
			reimport = _use_external(model_path, need.keys(), atlas.resource_path)
		else:
			notes.append("no atlas texture staged for " + pack)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefab_dir))
	var scene_path := prefab_dir.path_join(slot + suffix + ".tscn")
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
		"atlas_materials": mat_count, "uses_atlas": uses_atlas, "reimport": reimport or bool(rig.get("changed", false)),
		"rig": rig.get("skeleton", ""), "notes": notes, "warnings": warn,
		"summary": "%s x%.3f -> %.1fx%.1fx%.1f m (proxy %.1fx%.1fx%.1f)%s" % [mode, s, final.size.x, final.size.y, final.size.z,
			proxy.size.x, proxy.size.y, proxy.size.z, ("  ▲ " + "; ".join(warn)) if not warn.is_empty() else ""]}


## Shows one body of a multi-character model; attachments stay as they are.
static func apply_only_mesh(n: Node, only: String) -> void:
	for mi: Node in n.find_children("SM_Chr_*", "MeshInstance3D", true, false):
		if not mi.name.begins_with("SM_Chr_Attach"):
			(mi as MeshInstance3D).visible = String(mi.name) == only


## Copies a prefab's visible geometry into a fresh tree: meshes (with their
## material overrides), skeletons and bone attachments keep their transforms;
## physics bodies, collision shapes, players and hidden meshes are dropped.
static func flatten_prefab(ps: PackedScene) -> Node3D:
	var src: Node = ps.instantiate()
	var out := Node3D.new()
	if src is MeshInstance3D:
		# Many Synty prefabs are a MeshInstance3D at the root.
		var self_copy: MeshInstance3D = src.duplicate(0)
		for gc: Node in self_copy.get_children():
			self_copy.remove_child(gc)
			gc.free()
		self_copy.transform = Transform3D.IDENTITY
		self_copy.name = src.name
		out.add_child(self_copy)
		_copy_visual(src, self_copy)
	else:
		_copy_visual(src, out)
	src.free()
	return out


static func _copy_visual(src: Node, dst: Node) -> void:
	for ch: Node in src.get_children():
		if ch is CollisionObject3D or ch is CollisionShape3D or ch is AnimationPlayer or ch is AnimationTree:
			continue
		if ch is MeshInstance3D and not (ch as MeshInstance3D).visible:
			continue
		var copy: Node
		if ch is MeshInstance3D or ch is Skeleton3D or ch is BoneAttachment3D or ch is Decal or ch is GPUParticles3D or ch is Light3D:
			copy = ch.duplicate(0)
			for gc: Node in copy.get_children():
				copy.remove_child(gc)
				gc.free()
		elif ch is Node3D:
			copy = Node3D.new()
			(copy as Node3D).transform = (ch as Node3D).transform
		else:
			continue
		copy.name = ch.name
		dst.add_child(copy)
		_copy_visual(ch, copy)
	# Drop empty helper nodes left after stripping bodies.
	for ch: Node in dst.get_children():
		if ch.get_class() == "Node3D" and ch.get_child_count() == 0:
			dst.remove_child(ch)
			ch.free()


static func _own_all(n: Node, owner_node: Node) -> void:
	for ch: Node in n.get_children():
		if ch.owner == null or ch.owner == n and n.scene_file_path.is_empty():
			ch.owner = owner_node
		if ch.scene_file_path.is_empty():
			_own_all(ch, owner_node)


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
