class_name ColonyCorridors
extends RefCounted
## Walkway tubes between linked buildings, the way the Sci-Fi Worlds demo colony
## reads as one connected base. Visual only: the domain network (power/access)
## is unchanged; this draws a minimum spanning tree over the same links so the
## base gets a few clean corridors instead of a web of crossing lines. Tubes are
## tiled from 10 m Synty corridor modules, trimmed to the building footprints.
## Skipped when the purchased module is missing.

const MODULES := ["res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings/SM_Bld_Pod_Corridor_Square_01.tscn",
	"res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings/SM_Bld_Pod_Corridor_Square_03.tscn",
	"res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings/SM_Bld_Pod_Corridor_Round_02.tscn"]
const JOINT := "res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings/SM_Bld_Pod_Corridor_Round_Connector_01.tscn"
const WIDTH := 2.4  # metres across, to sit with the scaled-down pods
const NO_TUBE := ["solar_array", "battery", "geothermal_generator", "drone_hub"]  # power/pad pieces stand free


static func build(gs: GameState, terrain: TerrainBuilder) -> Node3D:
	var root := Node3D.new()
	root.name = "Corridors"
	root.set_meta("segments", [])  # [Vector2 a, Vector2 b] per tube, for ColonyClearance
	var mods: Array = []
	for p: String in MODULES:
		var m := GroundCover._mesh_of(p)
		if not m.is_empty():
			mods.append(m)
	if mods.is_empty():
		return root
	var nodes: Array = []
	for b: Dictionary in gs.colony.buildings:
		if b.get("accessible") and b.get("state") == ColonyState.B_ACTIVE and not str(b["def_id"]) in NO_TUBE:
			nodes.append(b)
	# Prim's MST over pairs within link range.
	if nodes.size() < 2:
		return root
	var in_tree := {0: true}
	while in_tree.size() < nodes.size():
		var best := INF
		var pair := Vector2i(-1, -1)
		for i: int in in_tree.keys():
			for j: int in nodes.size():
				if in_tree.has(j):
					continue
				var d := _pos(nodes[i]).distance_to(_pos(nodes[j]))
				var reach := maxf(GameSession.sim.colony.link_range(str(nodes[i]["def_id"])), GameSession.sim.colony.link_range(str(nodes[j]["def_id"])))
				if d < best and d <= maxf(reach, 1.0) * 1.05:
					best = d
					pair = Vector2i(i, j)
		if pair.x < 0:
			break
		in_tree[pair.y] = true
		_tube(root, nodes[pair.x], nodes[pair.y], terrain, mods[absi(hash(pair)) % mods.size()])
	return root


static func _pos(b: Dictionary) -> Vector2:
	return Vector2(float(b["x"]), float(b["z"]))


## How far from the building's centre its walls are in direction dir: the
## drawn model's extent (data "tube_extent", e.g. the landed Ark is narrower
## than its footprint) or the footprint, so a tube always meets the hull.
static func _reach(b: Dictionary, dir: Vector2) -> float:
	var def := GameSession.content.building(str(b["def_id"]))
	var ext: Array = DictUtil.get_arr(DictUtil.get_dict(BuildingDressing.doc(), "tube_extent"), str(b["def_id"]))
	var size := ColonySimulation.footprint_size(def, int(b.get("rot", 0)))
	if ext.size() == 2:
		size = Vector2(float(ext[0]), float(ext[1]))
		if posmod(int(b.get("rot", 0)), 2) == 1:
			size = Vector2(size.y, size.x)
	var tx := size.x * 0.5 / maxf(absf(dir.x), 0.001)
	var tz := size.y * 0.5 / maxf(absf(dir.y), 0.001)
	return minf(tx, tz)


static func _half(b: Dictionary) -> float:
	var fp: Array = DictUtil.get_arr(GameSession.content.building(str(b["def_id"])), "footprint")
	return (minf(float(fp[0]), float(fp[1])) * 0.5) if fp.size() == 2 else 3.0


static func _tube(root: Node3D, a: Dictionary, b: Dictionary, terrain: TerrainBuilder, mod: Array) -> void:
	var pa := _pos(a)
	var pb := _pos(b)
	var dir := (pb - pa).normalized()
	var start := pa + dir * (_reach(a, dir) - 0.4)
	var end := pb - dir * (_reach(b, -dir) - 0.4)
	var length := start.distance_to(end)
	if length < 1.0 or (pb - pa).dot(end - start) <= 0.0:
		return
	(root.get_meta("segments") as Array).append([start, end])
	var box: AABB = mod[2]
	var s := WIDTH / maxf(box.size.x, 0.1)
	var seg := box.size.z * s
	var n := maxi(1, int(ceil(length / seg)))
	var stretch := length / (n * seg)
	var yaw := atan2(dir.x, dir.y)
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s * stretch))
	# A connector collar at every joint so a tube reads as built modules, not a pipe.
	var joint: Array = GroundCover._mesh_of(JOINT) if ResourceLoader.exists(JOINT) else []
	if not joint.is_empty():
		var jb: AABB = joint[2]
		var js := WIDTH * 1.08 / maxf(jb.size.x, 0.1)
		var jbasis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(js, js, js))
		for i: int in range(1, n):
			var c := start + dir * (seg * stretch * i)
			var y := terrain.height_at(c.x, c.y) - jb.position.y * js - 0.02
			var mi := MeshInstance3D.new()
			mi.mesh = joint[0]
			mi.transform = Transform3D(jbasis, Vector3(c.x, y, c.y)) * Transform3D(Basis.IDENTITY, -Vector3(jb.get_center().x, 0, jb.get_center().z)) * (joint[1] as Transform3D)
			mi.set_meta("joint", true)
			root.add_child(mi)
	for i: int in n:
		var c := start + dir * (seg * stretch * (i + 0.5))
		var y := terrain.height_at(c.x, c.y) - box.position.y * s
		var mi := MeshInstance3D.new()
		mi.mesh = mod[0]
		mi.transform = Transform3D(basis, Vector3(c.x, y, c.y)) * Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, 0, box.get_center().z)) * (mod[1] as Transform3D)
		root.add_child(mi)
