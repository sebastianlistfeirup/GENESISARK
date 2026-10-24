class_name ColonyPaths
extends RefCounted
## Walkable grid of the colony map for presentation: dirt roads between the
## districts and believable walking routes for colonists and vehicles. Building
## footprints and the site's blocked zones are solid, corridor tubes are costly
## to cross, roads are cheap. Rebuilt when the building set changes. Never
## consulted by the domain.

var cell := 2.0
var half := 108.0
var grid := AStarGrid2D.new()
var roads: Array[PackedVector2Array] = []
var _n := 0
var _reach := PackedByteArray()  # 1 = connected to the open map (no walled-in courtyards)


func build(gs: GameState, site: Dictionary, corridor_segments: Array, map_size: float) -> void:
	var cfg: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "roads")
	cell = DictUtil.get_float(cfg, "cell", 2.0)
	half = map_size * 0.47
	_n = int(ceil(half * 2.0 / cell))
	grid.region = Rect2i(0, 0, _n, _n)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	grid.fill_weight_scale_region(grid.region, 1.6)
	for b: Dictionary in gs.colony.buildings:
		var def := GameSession.content.building(str(b["def_id"]))
		_mark_rect(ColonySimulation.rect_for(def, float(b["x"]), float(b["z"]), int(b.get("rot", 0))).grow(0.7))
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var c: Array = DictUtil.get_arr(bz, "center")
		var r := DictUtil.get_float(bz, "radius") + 1.0
		_mark_rect(Rect2(Vector2(float(c[0]), float(c[1])) - Vector2(r, r), Vector2(r, r) * 2.0))
	for sg: Array in corridor_segments:
		_weight_segment(sg[0], sg[1], 2.0, 12.0)
	_flood()
	_build_roads(site)


## Marks every free cell reachable from the map corner, so routes never start
## or end in a pocket walled in by buildings.
func _flood() -> void:
	_reach = PackedByteArray()
	_reach.resize(_n * _n)
	var q: Array[Vector2i] = [Vector2i(0, 0)]
	_reach[0] = 1
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d: Vector2i in dirs:
			var nb := c + d
			if nb.x < 0 or nb.y < 0 or nb.x >= _n or nb.y >= _n:
				continue
			var k := nb.y * _n + nb.x
			if _reach[k] == 0 and not grid.is_point_solid(nb):
				_reach[k] = 1
				q.append(nb)


func _ok(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _n and c.y < _n and _reach.size() == _n * _n and _reach[c.y * _n + c.x] == 1


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x + half) / cell), 0, _n - 1), clampi(int((p.y + half) / cell), 0, _n - 1))


func to_world(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * cell - half, (c.y + 0.5) * cell - half)


func walkable(p: Vector2) -> bool:
	return _ok(to_cell(p))


## Nearest walkable cell centre to p (spiral search), or p itself if none.
func free_near(p: Vector2, max_r: int = 24) -> Vector2:
	var c := to_cell(p)
	if _ok(c):
		return p
	for r: int in range(1, max_r):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dx: int in range(-r, r + 1):
			for dy: int in [-r, r]:
				for q: Vector2i in [Vector2i(c.x + dx, c.y + dy), Vector2i(c.x + dy, c.y + dx)]:
					if _ok(q):
						var d := to_world(q).distance_squared_to(p)
						if d < bd:
							bd = d
							best = q
		if best.x >= 0:
			return to_world(best)
	return p


## A smoothed walking route from a to b (both nudged onto free cells); empty if none.
func route(a: Vector2, b: Vector2) -> PackedVector2Array:
	var fa := free_near(a)
	var fb := free_near(b)
	var ids := grid.get_id_path(to_cell(fa), to_cell(fb))
	if ids.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for id: Vector2i in ids:
		pts.append(to_world(id))
	pts = _pull(pts)
	pts[0] = fa
	pts[pts.size() - 1] = fb
	return _chaikin(pts, 2)


## Where people step out of a building: the middle of the footprint side that
## faces `toward`, just outside the walkable clearance.
func door(b: Dictionary, toward: Vector2) -> Vector2:
	var def := GameSession.content.building(str(b["def_id"]))
	var r := ColonySimulation.rect_for(def, float(b["x"]), float(b["z"]), int(b.get("rot", 0)))
	var c := r.get_center()
	var d := toward - c
	var sx := signf(d.x) if d.x != 0.0 else 1.0
	var sy := signf(d.y) if d.y != 0.0 else 1.0
	var sides: Array = [Vector2(sx, 0), Vector2(0, sy), Vector2(0, -sy), Vector2(-sx, 0)]
	if absf(d.x) / maxf(r.size.x, 0.1) < absf(d.y) / maxf(r.size.y, 0.1):
		sides = [Vector2(0, sy), Vector2(sx, 0), Vector2(-sx, 0), Vector2(0, -sy)]
	for s: Vector2 in sides:
		var p := c + Vector2(s.x * (r.size.x * 0.5 + 1.6), s.y * (r.size.y * 0.5 + 1.6))
		if walkable(p):
			return p
	return c + Vector2(sx * (r.size.x * 0.5 + 1.6), 0)


func _mark_rect(r: Rect2) -> void:
	var a := to_cell(r.position)
	var b := to_cell(r.end)
	for x: int in range(a.x, b.x + 1):
		for y: int in range(a.y, b.y + 1):
			# Only cells whose centre is covered, so narrow lanes stay open.
			if r.has_point(to_world(Vector2i(x, y))):
				grid.set_point_solid(Vector2i(x, y), true)


func _weight_segment(a: Vector2, b: Vector2, half_w: float, w: float) -> void:
	var steps := maxi(1, int(a.distance_to(b) / (cell * 0.5)))
	for i: int in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var c := to_cell(p)
		var rr := int(ceil(half_w / cell))
		for dx: int in range(-rr, rr + 1):
			for dy: int in range(-rr, rr + 1):
				var q := c + Vector2i(dx, dy)
				if grid.region.has_point(q) and not grid.is_point_solid(q):
					grid.set_point_weight_scale(q, w)


## Dirt roads: landing <-> resource and landing <-> living, routed around the
## buildings; once laid, they are the cheap way for walkers and vehicles.
func _build_roads(site: Dictionary) -> void:
	roads.clear()
	var ds: Dictionary = DictUtil.get_dict(site, "districts")
	var lc: Array = DictUtil.get_arr(ds.get("landing", {}), "center")
	if lc.size() != 2:
		return
	var land := Vector2(float(lc[0]), float(lc[1]))
	for k: String in ["resource", "living"]:
		var c: Array = DictUtil.get_arr(ds.get(k, {}), "center")
		if c.size() != 2:
			continue
		var pts := route(land, Vector2(float(c[0]), float(c[1])))
		if pts.size() >= 2:
			roads.append(pts)
			for i: int in range(1, pts.size()):
				_weight_segment(pts[i - 1], pts[i], 1.5, 0.6)


## String pulling: drop grid points while the straight line stays walkable.
func _pull(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	var anchor := 0
	var i := 2
	while i < pts.size():
		if not _clear_line(pts[anchor], pts[i]):
			out.append(pts[i - 1])
			anchor = i - 1
		i += 1
	out.append(pts[pts.size() - 1])
	return out


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(a.distance_to(b) / (cell * 0.4)))
	for i: int in steps + 1:
		var c := to_cell(a.lerp(b, float(i) / steps))
		if grid.is_point_solid(c) or grid.get_point_weight_scale(c) > 3.0:
			return false
	return true


static func _chaikin(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := pts
	for it: int in iterations:
		if cur.size() < 3:
			return cur
		var nxt := PackedVector2Array([cur[0]])
		for i: int in cur.size() - 1:
			nxt.append(cur[i].lerp(cur[i + 1], 0.25))
			nxt.append(cur[i].lerp(cur[i + 1], 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


## Height of the drawn (faceted) terrain mesh at x/z: the same two triangles per
## grid quad as TerrainBuilder.build(), so ribbons sit on the facets, not under them.
static func surface_y(terrain: TerrainBuilder, x: float, z: float) -> float:
	var st := terrain.step
	var h := terrain.size_m * 0.5
	var gx := (x + h) / st
	var gz := (z + h) / st
	var ix := floori(gx)
	var iz := floori(gz)
	var fx := gx - ix
	var fz := gz - iz
	var x0 := -h + ix * st
	var z0 := -h + iz * st
	var h00 := terrain.height_at(x0, z0)
	var h10 := terrain.height_at(x0 + st, z0)
	var h01 := terrain.height_at(x0, z0 + st)
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	var h11 := terrain.height_at(x0 + st, z0 + st)
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


## A soft-edged dirt ribbon draped on the terrain along a polyline.
static func road_mesh(pts: PackedVector2Array, terrain: TerrainBuilder, col: Color, width: float, shoulder: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dense := PackedVector2Array()
	for i: int in range(1, pts.size()):
		var n := maxi(1, int(pts[i - 1].distance_to(pts[i]) / minf(1.0, terrain.step)))
		for k: int in n:
			dense.append(pts[i - 1].lerp(pts[i], float(k) / n))
	dense.append(pts[pts.size() - 1])
	# Across the road: soft shoulder, two darker wheel tracks, soft shoulder.
	var offs := [-(width * 0.5 + shoulder), -width * 0.5, -width * 0.27, 0.0, width * 0.27, width * 0.5, width * 0.5 + shoulder]
	var alphas := [0.0, 0.8, 0.95, 0.8, 0.95, 0.8, 0.0]
	var shade := [1.0, 1.0, 0.8, 1.0, 0.8, 1.0, 1.0]
	var cols := offs.size()
	var total := 0.0
	var dist := PackedFloat32Array([0.0])
	for i: int in range(1, dense.size()):
		total += dense[i - 1].distance_to(dense[i])
		dist.append(total)
	var rows: Array = []
	for i: int in dense.size():
		var dir := (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]).normalized()
		var nrm := dir.orthogonal()
		var row: Array = []
		for k: int in cols:
			var p: Vector2 = dense[i] + nrm * float(offs[k])
			row.append(Vector3(p.x, surface_y(terrain, p.x, p.y) + 0.1, p.y))
		rows.append(row)
	for i: int in range(1, rows.size()):
		for k: int in cols - 1:
			var a: Vector3 = rows[i - 1][k]
			var b: Vector3 = rows[i - 1][k + 1]
			var c: Vector3 = rows[i][k]
			var d: Vector3 = rows[i][k + 1]
			for v: Array in [[a, k, i - 1], [c, k, i], [b, k + 1, i - 1], [b, k + 1, i - 1], [c, k, i], [d, k + 1, i]]:
				var taper := clampf(minf(dist[v[2]], total - dist[v[2]]) / 6.0, 0.0, 1.0)  # fade in/out at the ends
				var sh := float(shade[v[1]])
				st.set_color(Color(col.r * sh, col.g * sh, col.b * sh, float(alphas[v[1]]) * taper))
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
