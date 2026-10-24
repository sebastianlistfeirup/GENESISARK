class_name ColonyPaths
extends RefCounted
## Walkable grid of the colony map for presentation: dirt roads between the
## districts and believable walking routes for colonists and vehicles. Building
## footprints and the site's blocked zones are solid, corridor tubes are costly
## to cross, roads are cheap. Rebuilt when the building set changes. Never
## consulted by the domain.

## Walkers keep this far from footprints, tubes and props (body radius + a hand).
const WALKER_R := 0.45
## Grid cells whose centre is this close to a footprint are solid, so every grid
## vertex already stands clear of the walls (string pulling never hugs a corner).
const FOOT_GROW := 1.15

var cell := 2.0
var half := 108.0
var grid := AStarGrid2D.new()
var roads: Array[PackedVector2Array] = []
## Exact obstacles for walkers (footprints, tubes outside road crossings, blocked
## zones, kept props): every straight leg of a route is tested against it.
var walk_clear := ColonyClearance.new()
var _n := 0
var _reach := PackedByteArray()  # 1 = connected to the open map (no walled-in courtyards)
var _tubes: Array = []  # [Vector2 a, Vector2 b] corridor tubes (solid once the roads are laid)


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
	walk_clear = ColonyClearance.new()
	for b: Dictionary in gs.colony.buildings:
		var def := GameSession.content.building(str(b["def_id"]))
		var rect := ColonySimulation.rect_for(def, float(b["x"]), float(b["z"]), int(b.get("rot", 0)))
		_weight_rect(rect.grow(FOOT_GROW + 1.6), 2.6)  # roads keep a little off the platforms
		_mark_rect(rect.grow(FOOT_GROW))
		walk_clear.add_rect(rect, int(b["id"]))
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var c: Array = DictUtil.get_arr(bz, "center")
		var r := DictUtil.get_float(bz, "radius") + 1.0
		_mark_rect(Rect2(Vector2(float(c[0]), float(c[1])) - Vector2(r, r), Vector2(r, r) * 2.0))
		walk_clear.add_segment(Vector2(float(c[0]), float(c[1])), Vector2(float(c[0]), float(c[1])), r - 0.5)
	_tubes = corridor_segments
	for sg: Array in corridor_segments:
		_weight_segment(sg[0], sg[1], 2.0, 4.0)
	_flood()
	_build_roads(site)
	_solidify_tubes()
	_flood()


## Once the roads are laid, corridor tubes become walls for walkers except where
## a road crosses them (the tube is opened there, see crossings()).
func _solidify_tubes() -> void:
	var tube_half := ColonyCorridors.WIDTH * 0.5
	for sg: Array in _tubes:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var steps := maxi(1, int(a.distance_to(b) / 0.8))
		for i: int in steps:
			var p := a.lerp(b, (i + 0.5) / steps)
			var q := a.lerp(b, float(i + 1) / steps)
			var o := a.lerp(b, float(i) / steps)
			if _near_road(p, 2.4):
				continue
			walk_clear.add_segment(o, q, tube_half)
		var rr := int(ceil((tube_half + 1.0) / cell)) + 1
		var n := maxi(1, int(a.distance_to(b) / (cell * 0.5)))
		for i: int in n + 1:
			var c := to_cell(a.lerp(b, float(i) / n))
			for dx: int in range(-rr, rr + 1):
				for dy: int in range(-rr, rr + 1):
					var q := c + Vector2i(dx, dy)
					if not grid.region.has_point(q) or grid.is_point_solid(q):
						continue
					var w := to_world(q)
					if Geometry2D.get_closest_point_to_segment(w, a, b).distance_to(w) < tube_half + 0.75 and not _near_road(w, 2.0):
						grid.set_point_solid(q, true)


func _near_road(p: Vector2, d: float) -> bool:
	for rd: PackedVector2Array in roads:
		for i: int in range(1, rd.size()):
			if Geometry2D.get_closest_point_to_segment(p, rd[i - 1], rd[i]).distance_to(p) < d:
				return true
	return false


## Where a road passes through a corridor tube: [Vector2 point] (the scene opens the tube there).
func crossings() -> Array:
	var out: Array = []
	for sg: Array in _tubes:
		for rd: PackedVector2Array in roads:
			for i: int in range(1, rd.size()):
				var hit: Variant = Geometry2D.segment_intersects_segment(sg[0], sg[1], rd[i - 1], rd[i])
				if hit != null:
					out.append(hit)
	return out


## Props become obstacles for walkers (roads stay open), then reachability is redone.
func block_discs(discs: Array) -> void:
	for d: Array in discs:
		var p: Vector2 = d[0]
		var r := float(d[1]) + 0.3
		var a := to_cell(p - Vector2(r, r))
		var b := to_cell(p + Vector2(r, r))
		for x: int in range(a.x, b.x + 1):
			for y: int in range(a.y, b.y + 1):
				var c := Vector2i(x, y)
				if to_world(c).distance_to(p) <= r and grid.get_point_weight_scale(c) > 1.0:
					grid.set_point_solid(c, true)
		walk_clear.add_segment(p, p, float(d[1]))
	_flood()


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
	pts[0] = fa
	pts[pts.size() - 1] = fb
	pts = _pull(pts)
	return _round_corners(_round_corners(pts))


## Corner rounding that never cuts into an obstacle: each corner is replaced by
## a short chord only when that chord is clear for a walker (Chaikin used to
## pull the path into the inside of every turn, i.e. into the building corner).
func _round_corners(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i: int in range(1, pts.size() - 1):
		var p := pts[i]
		var a := pts[i - 1]
		var b := pts[i + 1]
		var done := false
		for f: float in [0.25, 0.12]:
			var ca := p.move_toward(a, minf(p.distance_to(a) * f, 2.0))
			var cb := p.move_toward(b, minf(p.distance_to(b) * f, 2.0))
			if _walk_clear(ca, cb):
				out.append(ca)
				out.append(cb)
				done = true
				break
		if not done:
			out.append(p)
	out.append(pts[pts.size() - 1])
	return out


## A straight walk from a to b keeps WALKER_R off every footprint, tube and prop.
func _walk_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(a.distance_to(b) / 0.35))
	for i: int in steps + 1:
		if walk_clear.blocked(a.lerp(b, float(i) / steps), WALKER_R):
			return false
	return true


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


func _weight_rect(r: Rect2, w: float) -> void:
	var a := to_cell(r.position)
	var b := to_cell(r.end)
	for x: int in range(a.x, b.x + 1):
		for y: int in range(a.y, b.y + 1):
			var c := Vector2i(x, y)
			if r.has_point(to_world(c)) and not grid.is_point_solid(c):
				grid.set_point_weight_scale(c, maxf(grid.get_point_weight_scale(c), w))


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
		# Prefer a road that goes around the corridor tubes; only when that
		# detour is much longer does it cross one (the tube opens a gate there).
		var target := Vector2(float(c[0]), float(c[1]))
		var pts := _route_around_tubes(land, target)
		var direct := route(land, target)
		if pts.size() < 2 or (direct.size() >= 2 and _length(pts) > _length(direct) * 1.5 + 12.0):
			pts = direct
		if pts.size() >= 2:
			roads.append(pts)
			for i: int in range(1, pts.size()):
				_weight_segment(pts[i - 1], pts[i], 1.5, 0.6)


## A route with every corridor tube made solid for the moment.
func _route_around_tubes(a: Vector2, b: Vector2) -> PackedVector2Array:
	var set_cells: Array[Vector2i] = []
	var reach := int(ceil((ColonyCorridors.WIDTH * 0.5 + 1.0) / cell)) + 1
	for sg: Array in _tubes:
		var sa: Vector2 = sg[0]
		var sb: Vector2 = sg[1]
		var n := maxi(1, int(sa.distance_to(sb) / (cell * 0.5)))
		for i: int in n + 1:
			var c := to_cell(sa.lerp(sb, float(i) / n))
			for dx: int in range(-reach, reach + 1):
				for dy: int in range(-reach, reach + 1):
					var q := c + Vector2i(dx, dy)
					if not grid.region.has_point(q) or grid.is_point_solid(q):
						continue
					var w := to_world(q)
					if Geometry2D.get_closest_point_to_segment(w, sa, sb).distance_to(w) < ColonyCorridors.WIDTH * 0.5 + 0.75:
						grid.set_point_solid(q, true)
						set_cells.append(q)
	if set_cells.is_empty():
		return route(a, b)
	_flood()
	var r := route(a, b)
	for q: Vector2i in set_cells:
		grid.set_point_solid(q, false)
	_flood()
	return r


static func _length(pts: PackedVector2Array) -> float:
	var t := 0.0
	for i: int in range(1, pts.size()):
		t += pts[i - 1].distance_to(pts[i])
	return t


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
	return _walk_clear(a, b)


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
## `under`: footprints (rects only); the ribbon fades out within `under_grow` of
## them, so a road meets a building platform instead of being painted over it.
## `glow`: emission strength (night worlds, the track stays readable in the dark).
static func road_mesh(pts: PackedVector2Array, terrain: TerrainBuilder, col: Color, width: float, shoulder: float,
		under: ColonyClearance = null, under_grow: float = 0.0, glow: float = 0.0) -> MeshInstance3D:
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
	var hidden: Array = []  # [row][col] -> true where the ribbon passes under a platform
	for i: int in rows.size():
		var hr: Array = []
		for k: int in cols:
			var v3: Vector3 = rows[i][k]
			hr.append(under != null and under.blocked(Vector2(v3.x, v3.z), under_grow, -1, true))
		hidden.append(hr)
	for i: int in range(1, rows.size()):
		for k: int in cols - 1:
			var a: Vector3 = rows[i - 1][k]
			var b: Vector3 = rows[i - 1][k + 1]
			var c: Vector3 = rows[i][k]
			var d: Vector3 = rows[i][k + 1]
			for v: Array in [[a, k, i - 1], [c, k, i], [b, k + 1, i - 1], [b, k + 1, i - 1], [c, k, i], [d, k + 1, i]]:
				var taper := clampf(minf(dist[v[2]], total - dist[v[2]]) / 6.0, 0.0, 1.0)  # fade in/out at the ends
				if hidden[v[2]][v[1]]:
					taper = 0.0
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
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Edge markers along a road: small studs on both shoulders every `every` metres
## (one MultiMesh). Night worlds make them glow so the road reads in the dark.
static func road_markers(pts: PackedVector2Array, terrain: TerrainBuilder, width: float, every: float, col: Color, energy: float,
		under: ColonyClearance = null, keep_off: float = 0.0) -> MultiMeshInstance3D:
	var xfs: Array = []
	var total := 0.0
	for i: int in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var s := 3.0
	while s < total - 3.0:
		var at := ColonyLife._along(pts, s)
		var p: Vector2 = at[0]
		var n: Vector2 = (at[1] as Vector2).orthogonal()
		for side: float in [-1.0, 1.0]:
			var q := p + n * side * (width * 0.5 + 0.25)
			if under != null and under.blocked(q, keep_off, -1, true):
				continue
			xfs.append(Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(q.x, surface_y(terrain, q.x, q.y) + 0.06, q.y)))
		s += every
	var mmi := MultiMeshInstance3D.new()
	if xfs.is_empty():
		return mmi
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.12, 0.12)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = energy > 0.0
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 240.0
	return mmi
