extends RefCounted
## DEV TOOL (D-054): where do the triangles of a perf case come from?
## Called by PerfProbe after a case when run with `--tris`:
##   godot --path . -- --perf --tris [--case=colony_era20] --out=builds/tris.json
## Two views, printed and returned for the JSON report:
##  * static: every visible GeometryInstance3D, LOD0 triangles x instances,
##    grouped by source mesh (resource path / mesh name) and by the scene-tree
##    branch that owns it; flags meshes without LODs and the camera distance vs
##    visibility_range_end (culled pieces are not counted).
##  * ablation: hide one branch at a time and read the renderer's real primitive
##    count (LOD, shadows and culling included) -> exact share of each branch.
## Dev-only text, not localized.

const TOP := 30


func run(scene: Node) -> Dictionary:
	var vp := scene.get_viewport()
	var cam := vp.get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var lod_mult := cam.get_camera_projection().get_lod_multiplier() if cam else 1.0
	var lod_thr := scene.get_viewport().mesh_lod_threshold / maxf(1.0, scene.get_viewport().get_visible_rect().size.x)
	var drawn_total := 0
	var by_size := {}  # world size bucket -> drawn tris of shadow casters
	var by_mesh := {}
	var by_branch := {}
	var lodless := {}
	var total := 0
	for n: Node in scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree() or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var mesh: Mesh = null
		var count := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			count = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		if mesh == null or count == 0:
			continue
		var box: AABB = gi.global_transform * gi.get_aabb()
		var dist := _dist_to_aabb(cam_pos, box)
		if gi.visibility_range_end > 0.0 and dist > gi.visibility_range_end + gi.visibility_range_end_margin:
			continue
		var tris := tris_of(mesh)
		var t := tris * count
		total += t
		var sc := gi.global_transform.basis.get_scale().abs()
		var drawn := lod_tris(mesh, maxf(sc.x, maxf(sc.y, sc.z)), maxf(dist, 0.01) * lod_mult, lod_thr) * count
		drawn_total += drawn
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var side := box.size.x if gi is MeshInstance3D else mesh.get_aabb().size.x * sc.x
			if gi is MeshInstance3D:
				side = maxf(box.size.x, maxf(box.size.y, box.size.z))
			else:
				var mb := mesh.get_aabb()
				side = maxf(mb.size.x, maxf(mb.size.y, mb.size.z)) * maxf(sc.x, 1.0)
			var bucket := "<0.5" if side < 0.5 else ("<1" if side < 1.0 else ("<2" if side < 2.0 else ("<4" if side < 4.0 else ">=4")))
			by_size[bucket] = int(by_size.get(bucket, 0)) + drawn
		var key := mesh_key(mesh)
		var e: Dictionary = by_mesh.get(key, {"tris": 0, "drawn": 0, "instances": 0, "nodes": 0, "lod0_tris": tris, "lods": lod_count(mesh), "near": INF, "far": 0.0, "shadow": 0})
		e["tris"] = int(e["tris"]) + t
		e["drawn"] = int(e["drawn"]) + drawn
		e["instances"] = int(e["instances"]) + count
		e["nodes"] = int(e["nodes"]) + 1
		e["near"] = minf(float(e["near"]), dist)
		e["far"] = maxf(float(e["far"]), dist)
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			e["shadow"] = int(e["shadow"]) + count
		by_mesh[key] = e
		if int(e["lods"]) == 0 and tris > 64:
			lodless[key] = int(lodless.get(key, 0)) + t
		var br := branch(scene, gi)
		by_branch[br] = int(by_branch.get(br, 0)) + t
	var mesh_rows: Array = []
	for k: String in by_mesh.keys():
		var e: Dictionary = by_mesh[k]
		mesh_rows.append({"mesh": k, "tris": e["tris"], "drawn": e["drawn"], "instances": e["instances"], "nodes": e["nodes"], "lod0": e["lod0_tris"],
			"lods": e["lods"], "near_m": snappedf(float(e["near"]), 0.1), "far_m": snappedf(float(e["far"]), 0.1), "shadow_inst": e["shadow"]})
	mesh_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["drawn"]) > int(b["drawn"]))
	var branch_rows: Array = []
	for k: String in by_branch.keys():
		branch_rows.append({"branch": k, "tris": by_branch[k]})
	branch_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tris"]) > int(b["tris"]))
	print("TRIS camera ", cam_pos, " scene ", scene.name, " year ", GameSession.state.campaign.colony_year() if GameSession.has_game() and GameSession.state.campaign else -1.0)
	print("TRIS shadow casters by world size (drawn tris): ", by_size)
	print("TRIS static LOD0 total %d, estimated after LOD %d (visible, in range, one pass)" % [total, drawn_total])
	for r: Dictionary in branch_rows.slice(0, TOP):
		print("TRIS branch %9d  %s" % [r["tris"], r["branch"]])
	for r: Dictionary in mesh_rows.slice(0, TOP):
		print("TRIS mesh %9d drawn %8d x%-5d lod0 %6d lods %d near %6.1f far %6.1f shadow %d  %s" % [r["tris"], r["drawn"], r["instances"], r["lod0"], r["lods"], r["near_m"], r["far_m"], r["shadow_inst"], r["mesh"]])
	var ablation := await _ablate(scene)
	return {"static_total": total, "lod_estimate_total": drawn_total, "branches": branch_rows.slice(0, TOP), "meshes": mesh_rows.slice(0, TOP * 2),
		"lodless": lodless, "ablation": ablation}


## Real primitive share per branch: hide it, read the renderer's count, show it.
func _ablate(scene: Node) -> Array:
	var tree := scene.get_tree()
	var cands: Array = []
	for c: Node in scene.get_children():
		if c is Node3D and (c as Node3D).visible:
			cands.append(c)
			for cc: Node in c.get_children():
				if cc is Node3D and (cc as Node3D).visible and cc.get_child_count() > 0:
					cands.append(cc)
	var base := await _prims(tree)
	var rows: Array = []
	for c: Node3D in cands:
		c.visible = false
		var without := await _prims(tree)
		c.visible = true
		await _prims(tree)
		var share := base - without
		if share > 20000:
			rows.append({"branch": str(scene.get_path_to(c)), "class": c.get_class(), "script": _script_of(c), "prims": share})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prims"]) > int(b["prims"]))
	print("TRIS ablation base %d primitives" % base)
	for r: Dictionary in rows.slice(0, TOP):
		print("TRIS ablate %9d  %s (%s %s)" % [r["prims"], r["branch"], r["class"], r["script"]])
	return [{"base": base}] + rows.slice(0, TOP)


func _prims(tree: SceneTree) -> int:
	var v := 0.0
	for i: int in 4:
		await tree.process_frame
	for i: int in 3:
		await tree.process_frame
		v = maxf(v, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	return int(v)


static func _script_of(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file() if s else ""


static func _dist_to_aabb(p: Vector3, b: AABB) -> float:
	var q := p.clamp(b.position, b.end)
	return p.distance_to(q)


static func tris_of(mesh: Mesh) -> int:
	var t := 0
	for s: int in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		t += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


## Triangles the engine draws for `mesh` (RendererSceneCull/mesh_storage LOD rule:
## first LOD whose edge_length * scale / (distance * lod multiplier) exceeds the
## threshold stops the walk).
static func lod_tris(mesh: Mesh, model_scale: float, dist_mult: float, threshold: float) -> int:
	var t := 0
	for s: int in mesh.get_surface_count():
		var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var n := tris_of_surface(mesh, s)
		for lod: Dictionary in d.get("lods", []):
			if float(lod.get("edge_length", 0.0)) * model_scale / dist_mult > threshold:
				break
			var ib: PackedByteArray = lod.get("index_data", PackedByteArray())
			n = ib.size() / (2 if int(d.get("vertex_count", 0)) <= 65536 else 4) / 3
		t += n
	return t


static func tris_of_surface(mesh: Mesh, s: int) -> int:
	var arr := mesh.surface_get_arrays(s)
	if arr.is_empty():
		return 0
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	return (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


static func lod_count(mesh: Mesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	return (d.get("lods", []) as Array).size()


static func mesh_key(mesh: Mesh) -> String:
	if not mesh.resource_path.is_empty():
		return mesh.resource_path.replace("res://assets/Synty/", "Synty/")
	if mesh.has_meta("short"):
		return "meta:" + str(mesh.get_meta("short"))
	if not mesh.resource_name.is_empty():
		return "name:" + mesh.resource_name
	return "%s(%d surf, %d tris)" % [mesh.get_class(), mesh.get_surface_count(), tris_of(mesh)]


## The owning branch: first two levels under the scene plus the wrapper scene file.
static func branch(scene: Node, n: Node) -> String:
	var parts: Array = []
	var cur := n
	var wrapper := ""
	while cur != null and cur != scene:
		if not cur.scene_file_path.is_empty() and wrapper.is_empty():
			wrapper = cur.scene_file_path.get_file()
		parts.push_front(String(cur.name).get_slice("@", 0).rstrip("0123456789"))
		cur = cur.get_parent()
	var head := "/".join(parts.slice(0, 2))
	return head + (" [" + wrapper + "]" if not wrapper.is_empty() else "")
