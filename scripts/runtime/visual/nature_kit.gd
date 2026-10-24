class_name NatureKit
extends RefCounted
## Loads POLYGON Nature Biomes source FBX (assets/Synty/Nature/<Pack>/FBX) and
## gives them Godot materials rebuilt from the pack's MaterialList_*.txt:
## foliage (leaf + trunk in one mesh, art/shaders/synty_foliage.gdshader),
## triplanar rock (art/shaders/synty_triplanar_rock.gdshader) or the plain atlas.
## A "look" dictionary tints them per planet: hue_shift, sat, leaf_tint,
## trunk_tint, rock_tint, rock_top_tint, glow, glow_color, wind.
## Only LOD0 parts are kept and merged into one ArrayMesh (one draw per surface).
## Purchased files live only locally; missing files return an empty result.

const FOLIAGE := preload("res://art/shaders/synty_foliage.gdshader")
const ROCK := preload("res://art/shaders/synty_triplanar_rock.gdshader")

static var _lists: Dictionary = {}   # pack dir -> {mesh_name: [ {slot, tex: {key: file}} ]}
static var _tex_index: Dictionary = {}  # pack dir -> {file name: res path}
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


## [ArrayMesh, Transform3D local, AABB] like GroundCover._mesh_of, or [] if missing.
static func mesh(path: String, look: Dictionary = {}) -> Array:
	var key := path + "|" + str(look.hash())
	if _meshes.has(key):
		return _meshes[key]
	var out: Array = []
	if ResourceLoader.exists(path):
		var pack := pack_root(path)
		var list := _list(pack)
		var inst: Node = (load(path) as PackedScene).instantiate()
		var merged := ArrayMesh.new()
		var box := AABB()
		var first := true
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var nm := String(mi.name)
			if mi.mesh == null or (nm.contains("_LOD") and not nm.ends_with("_LOD0")):
				continue
			var xf := _local(mi, inst)
			var slots: Array = _slots_for(pack, nm)
			for s: int in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				_transform_arrays(arrays, xf)
				var mat: Material = _material(pack, slots[s] if s < slots.size() else {}, look)
				merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				merged.surface_set_material(merged.get_surface_count() - 1, mat)
			var b: AABB = xf * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		inst.free()
		if merged.get_surface_count() > 0:
			out = [_with_lods(merged), Transform3D.IDENTITY, box]
	_meshes[key] = out
	return out


## "res://assets/Synty/Nature/Alpine/FBX/Environment/x.fbx" -> "res://assets/Synty/Nature/Alpine".
static func pack_root(path: String) -> String:
	var i := path.find("/FBX/")
	return path.substr(0, i) if i > 0 else path.get_base_dir().get_base_dir()


## Automatic LODs (what the importer does for imported meshes; a merged
## runtime mesh would otherwise draw its full detail at every distance).
static func _with_lods(m: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s: int in m.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s), [], {}, m.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	return out if out != null and out.get_surface_count() > 0 else m


static func _local(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _transform_arrays(a: Array, xf: Transform3D) -> void:
	if xf == Transform3D.IDENTITY:
		return
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i: int in v.size():
		v[i] = xf * v[i]
	a[Mesh.ARRAY_VERTEX] = v
	if a[Mesh.ARRAY_NORMAL] != null:
		var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		for i: int in nn.size():
			nn[i] = (xf.basis * nn[i]).normalized()
		a[Mesh.ARRAY_NORMAL] = nn
	a[Mesh.ARRAY_TANGENT] = null


static func _material(pack: String, slot: Dictionary, look: Dictionary) -> Material:
	var tex: Dictionary = slot.get("tex", {})
	var key := pack + "|" + str(slot.get("slot", "")) + "|" + str(look.hash())
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if tex.has("_Leaf_Texture"):
		var sm := ShaderMaterial.new()
		sm.shader = FOLIAGE
		sm.set_shader_parameter("leaf_tex", _tex(pack, str(tex["_Leaf_Texture"])))
		var trunk := str(tex.get("_Trunk_Texture", ""))
		sm.set_shader_parameter("has_trunk", not trunk.is_empty())
		sm.set_shader_parameter("trunk_tex", _tex(pack, trunk if not trunk.is_empty() else str(tex["_Leaf_Texture"])))
		sm.set_shader_parameter("hue_shift", float(look.get("hue_shift", 0.0)))
		sm.set_shader_parameter("sat_mul", float(look.get("sat", 1.0)))
		sm.set_shader_parameter("leaf_tint", Color(str(look.get("leaf_tint", "#ffffff"))))
		sm.set_shader_parameter("trunk_tint", Color(str(look.get("trunk_tint", "#ffffff"))))
		sm.set_shader_parameter("glow", float(look.get("glow", 0.0)))
		sm.set_shader_parameter("glow_color", Color(str(look.get("glow_color", "#4dffcc"))))
		sm.set_shader_parameter("wind", 0.0 if FxEffect.reduced_motion() else float(look.get("wind", 0.06)))
		m = sm
	elif tex.has("_Triplanar_Texture_Side"):
		var rm := ShaderMaterial.new()
		rm.shader = ROCK
		rm.set_shader_parameter("side_tex", _tex(pack, str(tex["_Triplanar_Texture_Side"])))
		var top_override := str(look.get("rock_top_tex", ""))
		rm.set_shader_parameter("top_tex", load(top_override) if not top_override.is_empty() and ResourceLoader.exists(top_override) else _tex(pack, str(tex.get("_Triplanar_Texture_Top", tex["_Triplanar_Texture_Side"]))))
		rm.set_shader_parameter("side_tint", Color(str(look.get("rock_tint", "#ffffff"))))
		rm.set_shader_parameter("top_tint", Color(str(look.get("rock_top_tint", look.get("rock_tint", "#ffffff")))))
		rm.set_shader_parameter("top_amount", float(look.get("rock_top_amount", 0.55)))
		m = rm
	else:
		var bm := StandardMaterial3D.new()
		var alb := str(tex.get("Albedo", ""))
		if alb.is_empty():
			alb = _atlas_name(pack)
		bm.albedo_texture = _tex(pack, alb)
		bm.albedo_color = Color(str(look.get("prop_tint", "#ffffff")))
		bm.roughness = 0.85
		m = bm
	_mats[key] = m
	return m


static func _atlas_name(pack: String) -> String:
	for f: String in _index(pack).keys():
		if f.contains("_Texture_01") and not f.contains("Emissive"):
			return f
	return ""


## Slots for a mesh: this pack's list first, then any other Nature pack (the
## packs share core meshes such as grass clumps but list them only once).
static func _slots_for(pack: String, mesh_name: String) -> Array:
	for pk: String in [pack] + _all_packs():
		var l := _list(pk)
		for k: String in [mesh_name, mesh_name.trim_suffix("_LOD0")]:
			if l.has(k):
				return l[k]
	return []


static func _all_packs() -> Array:
	var out: Array = []
	for d: String in DirAccess.get_directories_at("res://assets/Synty/Nature"):
		out.append("res://assets/Synty/Nature".path_join(d))
	return out


static func _tex(pack: String, file: String) -> Texture2D:
	var p := str(_index(pack).get(file, ""))
	if p.is_empty():
		for pk: String in _all_packs():
			p = str(_index(pk).get(file, ""))
			if not p.is_empty():
				break
	return load(p) if not p.is_empty() and ResourceLoader.exists(p) else null


static func _index(pack: String) -> Dictionary:
	if _tex_index.has(pack):
		return _tex_index[pack]
	var idx := {}
	_scan(pack.path_join("Textures"), idx)
	_tex_index[pack] = idx
	return idx


static func _scan(dir: String, idx: Dictionary) -> void:
	for f: String in DirAccess.get_files_at(dir):
		# An exported game lists "x.png.import"/"x.png.remap" instead of the source file.
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if not idx.has(name):
			idx[name] = dir.path_join(name)
	for d: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), idx)


## Parses MaterialList_*.txt: Mesh Name -> slots (in surface order) -> texture keys.
static func _list(pack: String) -> Dictionary:
	if _lists.has(pack):
		return _lists[pack]
	var out := {}
	for f: String in DirAccess.get_files_at(pack):
		if not (f.begins_with("MaterialList") and f.ends_with(".txt")):
			continue
		var mesh_name := ""
		var cur: Dictionary = {}
		for raw: String in FileAccess.get_file_as_string(pack.path_join(f)).split("\n"):
			var line := raw.strip_edges()
			if line.begins_with("Mesh Name:"):
				mesh_name = line.trim_prefix("Mesh Name:").strip_edges()
				if not out.has(mesh_name):
					out[mesh_name] = []
			elif line.begins_with("Slot:") and not mesh_name.is_empty():
				cur = {"slot": line.trim_prefix("Slot:").strip_edges(), "tex": {}}
				(out[mesh_name] as Array).append(cur)
			elif line.contains(": ") and line.contains("(") and not cur.is_empty():
				var k := line.get_slice(":", 0).strip_edges()
				var v := line.get_slice(":", 1).strip_edges().get_slice(" (", 0).strip_edges()
				(cur["tex"] as Dictionary)[k] = v
	_lists[pack] = out
	return out
