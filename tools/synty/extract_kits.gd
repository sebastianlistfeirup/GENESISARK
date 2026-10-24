extends SceneTree
## Lifts Synty's own building assemblies out of the pack demo scenes: for every
## main building instance (pods, corp/scav structures) it gathers the prefab
## instances Synty placed on and around it (supports, ramps, airlocks, greebles,
## lights, small props) and saves them as one kit scene with transforms relative
## to the building's base centre. Kits reference the vendor prefabs (no vendor
## data is copied); they are chosen by eye and used as slot sources.
##   godot --headless --path . --script res://tools/synty/extract_kits.gd -- [--out=res://art/kits]

const DEMOS := ["res://assets/Synty/PolygonSciFiWorlds/Scenes/Demo_Explorer_01.tscn",
	"res://assets/Synty/PolygonSciFiWorlds/Scenes/Demo_Corporation_01.tscn",
	"res://assets/Synty/PolygonSciFiWorlds/Scenes/Demo_Scavenger_01.tscn",
	"res://assets/Synty/PolygonSciFiWorlds/Scenes/Demo_BlackMarket_01.tscn"]
const MAIN := ["Vendor_0", "Crate_Building_0", "Scav_Dish_0", "Pod_Hab", "Pod_Research", "Pod_Hub", "Pod_Silo", "Corp_Generator", "Corp_Barracks", "Corp_Comms", "Corp_Containment",
	"Corp_LandingPad", "Corp_Radar", "Corp_Control_Tower", "Scav_Refinery_0", "Scav_Garage", "Corp_MobileSite", "Corp_Loading_Bay", "WindMill", "Watertank"]
const SKIP := ["Env_", "Corridor", "Bridge", "Platform_Large", "Platform_Small", "Wall", "Chr_", "Veh_", "FX_", "Decal"]

var out_dir := "res://art/kits"


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var index: Array = []
	for demo: String in DEMOS:
		if not ResourceLoader.exists(demo):
			continue
		var root: Node = (load(demo) as PackedScene).instantiate()
		var inst: Array = []
		_collect(root, root, inst)
		var mains: Array = inst.filter(func(e: Dictionary) -> bool: return _is_main(e["path"]))
		var n := 0
		for m: Dictionary in mains:
			var box: AABB = m["aabb"]
			var grow := box.grow(1.2)
			var kit := Node3D.new()
			kit.name = "Kit"
			var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
			var inv := Transform3D(Basis(Vector3.UP, (m["xf"] as Transform3D).basis.get_euler().y), base).affine_inverse()
			var parts := 0
			for e: Dictionary in inst:
				if e == m:
					continue
				var p: String = e["path"]
				if _is_main(p) or SKIP.any(func(s: String) -> bool: return p.contains(s)):
					continue
				var c: Vector3 = (e["aabb"] as AABB).get_center()
				if not grow.has_point(c) and not (grow.grow(0.5).intersects(e["aabb"]) and (e["aabb"] as AABB).size.length() < box.size.length() * 0.6):
					continue
				var ps: PackedScene = load(p)
				var node: Node3D = ps.instantiate()
				node.transform = inv * (e["xf"] as Transform3D)
				kit.add_child(node)
				node.owner = kit
				parts += 1
			var main_node: Node3D = (load(m["path"]) as PackedScene).instantiate()
			main_node.transform = inv * (m["xf"] as Transform3D)
			kit.add_child(main_node)
			main_node.owner = kit
			kit.move_child(main_node, 0)
			var name := "%s_%02d_%s" % [demo.get_file().get_basename().trim_prefix("Demo_"), n, (m["path"] as String).get_file().get_basename().trim_prefix("SM_Bld_")]
			var packed := PackedScene.new()
			packed.pack(kit)
			ResourceSaver.save(packed, out_dir.path_join(name + ".tscn"))
			index.append({"kit": out_dir.path_join(name + ".tscn"), "main": m["path"], "parts": parts, "size": [snappedf(box.size.x, 0.1), snappedf(box.size.y, 0.1), snappedf(box.size.z, 0.1)]})
			kit.free()
			n += 1
		root.free()
	var f := FileAccess.open(out_dir.path_join("kits_index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(index, " "))
	print("KITS ", index.size())
	quit()


func _is_main(p: String) -> bool:
	return MAIN.any(func(s: String) -> bool: return p.contains(s))


## Every instanced prefab (direct instances only, not their insides) with world transform and AABB.
func _collect(n: Node, root: Node, out: Array) -> void:
	for ch: Node in n.get_children():
		if not ch.scene_file_path.is_empty() and ch is Node3D and ch.scene_file_path.contains("/Prefabs/"):
			var xf := _world(ch as Node3D, root)
			var box := _aabb(ch, Transform3D.IDENTITY)
			if box.size != Vector3.ZERO:
				out.append({"path": ch.scene_file_path, "xf": xf, "aabb": xf * box})
			continue
		_collect(ch, root, out)


func _world(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh:
		out = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for c: Node in n.get_children():
		if c is CollisionObject3D:
			continue
		var b := _aabb(c, xf * (c as Node3D).transform if c is Node3D else xf)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out
