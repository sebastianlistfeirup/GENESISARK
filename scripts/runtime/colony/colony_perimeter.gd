class_name ColonyPerimeter
extends RefCounted
## A fortified ring around corporation-style colonies (owner's reference: the
## Sci-Fi Worlds snow base inside its wall): Synty corp wall segments on a circle
## that encloses every district, towers at intervals, gates where the circle
## meets the roads out. Segments are skipped where a building, water or steep
## ground is in the way, so the wall never blocks play. Visual only, no collision.

const BLD := "res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings/"
const SCALE := 0.36


static func build(gs: GameState, site: Dictionary, terrain: TerrainBuilder) -> Node3D:
	var root := Node3D.new()
	root.name = "Perimeter"
	var wall := GroundCover.mesh_of(BLD + "SM_Bld_Corp_Wall_01.tscn")
	var tower := GroundCover.mesh_of(BLD + "SM_Bld_Corp_Wall_Tower_01.tscn")
	if wall.is_empty():
		return root
	var districts: Dictionary = DictUtil.get_dict(site, "districts")
	var centre := Vector2.ZERO
	for dk: String in districts.keys():
		var c: Array = DictUtil.get_arr(districts[dk], "center")
		centre += Vector2(float(c[0]), float(c[1])) / districts.size()
	var radius := 0.0
	for dk: String in districts.keys():
		var c: Array = DictUtil.get_arr(districts[dk], "center")
		radius = maxf(radius, centre.distance_to(Vector2(float(c[0]), float(c[1]))) + DictUtil.get_float(districts[dk], "radius") * 1.25 + 6.0)
	var box: AABB = wall[2]
	var seg := box.size.x * SCALE
	var n := int(ceil(TAU * radius / seg))
	var step_a := TAU / n
	var blocked: Array = []
	for b: Dictionary in gs.colony.buildings:
		blocked.append(Vector2(float(b["x"]), float(b["z"])))
	var walls: Array = []
	var towers: Array = []
	for i: int in n:
		var a := i * step_a
		var p := centre + Vector2.from_angle(a + step_a * 0.5) * radius
		var near := false
		for q: Vector2 in blocked:
			if q.distance_to(p) < seg * 0.5 + 7.0:
				near = true
				break
		if near or i % 9 == 4:  # a gap for gates/roads every ninth segment
			continue
		var y0 := terrain.height_at(p.x, p.y)
		var pa := centre + Vector2.from_angle(a) * radius
		var pb := centre + Vector2.from_angle(a + step_a) * radius
		if absf(terrain.height_at(pa.x, pa.y) - terrain.height_at(pb.x, pb.y)) > 2.5 or (terrain.water_level > -50.0 and y0 < terrain.water_level + 0.3):
			continue
		var dir := (pb - pa).normalized()
		var basis := Basis(Vector3.UP, -atan2(dir.y, dir.x)).scaled(Vector3.ONE * SCALE)
		var local_centre := Vector3(box.get_center().x, box.position.y, box.get_center().z)
		walls.append(Transform3D(basis, Vector3(p.x, y0 - 0.3, p.y)) * Transform3D(Basis.IDENTITY, -local_centre) * (wall[1] as Transform3D))
		if i % 4 == 0 and not tower.is_empty():
			var tb: AABB = tower[2]
			towers.append(Transform3D(basis, Vector3(pa.x, terrain.height_at(pa.x, pa.y) - 0.3, pa.y)) * Transform3D(Basis.IDENTITY, -Vector3(tb.get_center().x, tb.position.y, tb.get_center().z)) * (tower[1] as Transform3D))
	for pair: Array in [[wall, walls], [tower, towers]]:
		if (pair[1] as Array).is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0][0]
		mm.instance_count = (pair[1] as Array).size()
		for i: int in mm.instance_count:
			mm.set_instance_transform(i, pair[1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
	return root
