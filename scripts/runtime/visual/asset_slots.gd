class_name AssetSlots
extends RefCounted
## Registry for VisualSlot ids (data/art/asset_slots.json). A slot renders its
## greybox proxy until the owner maps it to an imported Synty wrapper scene.

const PATH := "res://data/art/asset_slots.json"
## Mappings written by tools/synty/build_wrappers.gd. A hand-set "scene" in
## asset_slots.json always wins over this file.
const BUILT_PATH := "res://data/art/slot_scenes.json"

static var _slots: Dictionary = {}
static var _loaded := false
static var _materials: Dictionary = {}
static var _scenes: Dictionary = {}
static var _built: Dictionary = {}
## Architecture style of the current world ("corp", "scav", "" = default). A slot
## "building.habitat@corp" in the built map wins over "building.habitat" while set.
static var style := ""


static func slots() -> Dictionary:
	if not _loaded:
		_loaded = true
		var v: Variant = DictUtil.load_json(PATH)
		if v is Dictionary:
			_slots = DictUtil.get_dict(v, "slots")
		var b: Variant = DictUtil.load_json(BUILT_PATH) if FileAccess.file_exists(BUILT_PATH) else null
		_built = DictUtil.get_dict(b, "scenes") if b is Dictionary else {}
	return _slots


## All wrapper scenes for a slot: the hand-set "scene" in asset_slots.json, else
## the builder's entry in slot_scenes.json (a path or a list of variants).
static func scene_paths(id: String) -> Array:
	if not style.is_empty() and not id.contains("@") and _built.has(id + "@" + style):
		return scene_paths(id + "@" + style)
	var p := str(slot(id).get("scene", ""))
	if not p.is_empty():
		return [p]
	var b: Variant = _built.get(id, "")
	if b is Array:
		return (b as Array).filter(func(x: Variant) -> bool: return not str(x).is_empty())
	return [str(b)] if not str(b).is_empty() else []


## The (first) wrapper scene path for a slot, "" = proxy.
static func scene_path(id: String) -> String:
	slots()
	var all := scene_paths(id)
	return str(all[0]) if not all.is_empty() else ""


static func variant_count(id: String) -> int:
	slots()
	return scene_paths(id).size()


## Forget cached registry data (after the Synty builder wrote new mappings).
static func reload() -> void:
	_loaded = false
	_scenes.clear()


static func slot(id: String) -> Dictionary:
	return slots().get(id, {})


static func has_scene(id: String) -> bool:
	var p := scene_path(id)
	return not p.is_empty() and ResourceLoader.exists(p)


static func scene_for(id: String, variant: int = 0) -> PackedScene:
	slots()
	var all := scene_paths(id)
	var p := str(all[posmod(variant, all.size())]) if not all.is_empty() else ""
	if p.is_empty():
		return null
	if not _scenes.has(p):
		_scenes[p] = load(p) if ResourceLoader.exists(p) and _sources_present(p) else null
	return _scenes[p]


## A wrapper points at purchased files that live only on the owner's machine
## (assets/Synty, assets/imported; never in the public repository). On a fresh
## clone they are missing: fall back to the proxy instead of loading a broken scene.
static func _sources_present(wrapper: String) -> bool:
	for dep: String in ResourceLoader.get_dependencies(wrapper):
		var path := dep.get_slice("::", 2) if dep.contains("::") else dep
		if path.is_empty():
			path = dep.get_slice("::", 0)
		if (path.begins_with("res://assets/Synty/") or path.begins_with("res://assets/imported/")) and not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			return false
	return true


static func material(hex: String, emissive: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [hex, emissive, alpha]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	var c := Color.from_string(hex, Color.MAGENTA)
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = 0.75
	m.metallic = 0.15
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	_materials[key] = m
	return m


## Builds the proxy node tree for a slot (also used by the editor via @tool).
## Bounding box of all visible geometry under `n`, in the space `xf` maps to.
## Works on nodes that are not in the scene tree (tools, audits).
static func aabb_of(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is Node3D and not (n as Node3D).visible:
		return out  # hidden geometry (e.g. the unused bodies of a multi-character model) has no size
	if n is VisualInstance3D:
		out = xf * (n as VisualInstance3D).get_aabb()
		first = false
	for c: Node in n.get_children():
		var cxf := xf * (c as Node3D).transform if c is Node3D else xf
		var cb := aabb_of(c, cxf)
		if cb.size == Vector3.ZERO:
			continue
		out = cb if first else out.merge(cb)
		first = false
	return out


static func build_proxy(id: String, tint: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = "Proxy"
	for part: Dictionary in DictUtil.get_arr(slot(id.get_slice("@", 0)), "proxy"):
		var n := _part(part, tint)
		if n:
			root.add_child(n)
	if root.get_child_count() == 0:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		mi.mesh = bm
		mi.material_override = material("#ff00ff")
		mi.position.y = 0.5
		root.add_child(mi)
	return root


static func _part(p: Dictionary, tint: String) -> Node3D:
	var color := str(p.get("color", "#888888")) if tint.is_empty() else tint
	var emissive := DictUtil.get_float(p, "emissive")
	var pos: Array = DictUtil.get_arr(p, "pos")
	var mi := MeshInstance3D.new()
	match str(p.get("shape")):
		"box":
			var m := BoxMesh.new()
			var s: Array = DictUtil.get_arr(p, "size")
			m.size = Vector3(float(s[0]), float(s[1]), float(s[2]))
			mi.mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			m.bottom_radius = DictUtil.get_float(p, "radius", 0.5)
			m.top_radius = DictUtil.get_float(p, "top_radius", m.bottom_radius)
			m.height = DictUtil.get_float(p, "height", 1.0)
			m.radial_segments = 16
			mi.mesh = m
		"sphere":
			var m := SphereMesh.new()
			var r := DictUtil.get_float(p, "radius", 0.5)
			m.radius = r
			m.height = r * 2.0
			m.radial_segments = 24 if r > 5.0 else 12
			m.rings = 16 if r > 5.0 else 8
			mi.mesh = m
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = DictUtil.get_float(p, "radius", 0.3)
			m.height = DictUtil.get_float(p, "height", 1.8)
			mi.mesh = m
		"torus":
			var m := TorusMesh.new()
			m.inner_radius = DictUtil.get_float(p, "inner", 1.0)
			m.outer_radius = DictUtil.get_float(p, "outer", 1.2)
			mi.mesh = m
			mi.rotation_degrees.x = DictUtil.get_float(p, "rot_x")
		"particles":
			return _particles(p)
		_:
			return null
	mi.material_override = material(color, emissive)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if emissive <= 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if pos.size() == 3:
		mi.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	mi.rotation.y = DictUtil.get_float(p, "rot_y")
	return mi


static func _particles(p: Dictionary) -> Node3D:
	var gp := GPUParticles3D.new()
	gp.amount = DictUtil.get_int(p, "amount", 48)
	gp.lifetime = 3.0
	var pm := ParticleProcessMaterial.new()
	var ext: Array = DictUtil.get_arr(p, "extent")
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(ext[0]), float(ext[1]), float(ext[2])) if ext.size() == 3 else Vector3(3, 2, 3)
	pm.gravity = Vector3(0, -0.2, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.direction = Vector3(1, 0.3, 0)
	pm.spread = 60.0
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color.from_string(str(p.get("color", "#ffffff")), Color.WHITE)
	mat.albedo_color.a = 0.7
	q.material = mat
	gp.draw_pass_1 = q
	gp.position.y = 1.5
	return gp
