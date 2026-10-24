class_name ProcBuilder
extends RefCounted
## Procedural mesh kit for clean rebuilds of AI scans (image-to-3d-rebuild skill,
## typed port). One SurfaceTool per material key, so each material class ends up
## as one surface (one draw call).
##
##   var b := ProcBuilder.new()
##   b.use("hull", 0.4)                       # material key + per-part tint (vertex color R)
##   b.box(Transform3D(Basis(), Vector3(0, 0.25, 0)), Vector3(0.5, 0.25, 0.3), 0.012)
##   b.use("metal")
##   b.cylinder(Transform3D(Basis(), Vector3(0, 0.5, 0)), 0.04, 0.01, 16)
##   var mi := b.commit("Body", {"hull": hull_mat, "metal": metal_mat})
##
## Vertex color: R = per-part tint, G = 1 on chamfer edges (edge wear in the
## shader), B = free per-part mask (the drop pod uses it for panel colour ids).
## UV0 is a planar box projection in metres (constant texel density); UV2 is left
## for the bake. Godot treats CLOCKWISE triangles as front faces; tri() orients
## every triangle from its normals, so callers never worry about winding.

var tools: Dictionary = {}
var cur := "default"
var tint := 0.5
var edge := 0.0
var mask := 0.0


func use(mat: String, t: float = 0.5, m: float = 0.0) -> void:
	cur = mat
	tint = t
	mask = m
	if not tools.has(mat):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[mat] = s


## Build an ArrayMesh (one surface per material key) wrapped in a MeshInstance3D.
## Each material's resource_name is its key, so the GLB export and the bake keep the class.
func commit(node_name: String, mats: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = commit_mesh(mats)
	return mi


func commit_mesh(mats: Dictionary = {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys: Array = tools.keys()
	keys.sort()
	for key: String in keys:
		var s: SurfaceTool = tools[key]
		s.index()
		s.commit(mesh)
		var m: Material = mats.get(key, null)
		if m == null:
			m = StandardMaterial3D.new()
		if m.resource_name == "":
			m.resource_name = key
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		mesh.surface_set_name(mesh.get_surface_count() - 1, key)
	return mesh


# ---------------------------------------------------------------- core
func _v(s: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	s.set_normal(n)
	s.set_uv(uv)
	s.set_color(Color(tint, edge, mask))
	s.add_vertex(p)


func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	if not tools.has(cur):
		use(cur, tint, mask)
	var s: SurfaceTool = tools[cur]
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		_v(s, a, na, ua)
		_v(s, c, nc, uc)
		_v(s, b, nb, ub)
	else:
		_v(s, a, na, ua)
		_v(s, b, nb, ub)
		_v(s, c, nc, uc)


func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	tri(a, b, c, na, nb, nc, ua, ub, uc)
	tri(a, c, d, na, nc, nd, ua, uc, ud)


## Flat quad (one normal from its corners), planar UVs in metres. `away`: a
## point behind the face; the normal is flipped to point away from it.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, away: Vector3 = Vector3.INF) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n == Vector3.ZERO:
		n = (c - a).cross(d - a).normalized()
	if away != Vector3.INF and n.dot((a + b + c + d) * 0.25 - away) < 0.0:
		n = -n
	quad_n(a, b, c, d, n, n, n, n, _uv(a, n), _uv(b, n), _uv(c, n), _uv(d, n))


static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var an := n.abs()
	if an.x >= an.y and an.x >= an.z:
		return Vector2(p.z, p.y)
	elif an.y >= an.z:
		return Vector2(p.x, p.z)
	return Vector2(p.x, p.y)


func _face(xf: Transform3D, pts: Array, n: Vector3, uvn: Vector3) -> void:
	var wn := (xf.basis * n).normalized()
	var w: Array[Vector3] = []
	var u: Array[Vector2] = []
	for p: Vector3 in pts:
		w.append(xf * p)
		u.append(_uv(xf * p, xf.basis * uvn))
	if pts.size() == 4:
		quad_n(w[0], w[1], w[2], w[3], wn, wn, wn, wn, u[0], u[1], u[2], u[3])
	else:
		tri(w[0], w[1], w[2], wn, wn, wn, u[0], u[1], u[2])


static func _fp(h: Vector3, b: float, axis: int, s: Vector3) -> Vector3:
	var p := Vector3(s.x * (h.x - b), s.y * (h.y - b), s.z * (h.z - b))
	p[axis] = s[axis] * h[axis]
	return p


# ---------------------------------------------------------------- primitives
## Chamfered box: half extents h, chamfer b. Chamfers catch light; never ship razor edges.
func box(xf: Transform3D, h: Vector3, b: float) -> void:
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.9)
	for axis: int in 3:
		for sg: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sg
			var ua := (axis + 1) % 3
			var va := (axis + 2) % 3
			var pts: Array = []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var s := Vector3.ZERO
				s[axis] = sg
				s[ua] = c.x
				s[va] = c.y
				pts.append(_fp(h, b, axis, s))
			_face(xf, pts, n, n)
	if b <= 0.0:
		return
	edge = 1.0
	for a1: int in 3:
		for a2: int in range(a1 + 1, 3):
			var a3 := 3 - a1 - a2
			for s1: float in [-1.0, 1.0]:
				for s2: float in [-1.0, 1.0]:
					var n := Vector3.ZERO
					n[a1] = s1
					n[a2] = s2
					var sa := Vector3.ZERO
					sa[a1] = s1
					sa[a2] = s2
					sa[a3] = -1.0
					var sb := sa
					sb[a3] = 1.0
					var uvn := Vector3.ZERO
					uvn[a1] = 1.0
					_face(xf, [_fp(h, b, a1, sa), _fp(h, b, a1, sb), _fp(h, b, a2, sb), _fp(h, b, a2, sa)], n.normalized(), uvn)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				_face(xf, [_fp(h, b, 0, s), _fp(h, b, 1, s), _fp(h, b, 2, s)], s.normalized(), Vector3(0, 0, 1))
	edge = 0.0


## Faceted frustum ring around local Y (low-poly hulls): `sides` flat faces from
## (y0, r0) to (y1, r1), first face centred on angle `rot` (0 = facing +Z).
## Caps optional; `inward` flips the walls to face the axis (wells, sockets).
## Flat shading per face, the Synty look.
func frustum(xf: Transform3D, y0: float, r0: float, y1: float, r1: float, sides: int, rot: float = 0.0, cap0: bool = false, cap1: bool = false, inward: bool = false) -> void:
	var half := PI / sides
	for i: int in sides:
		var a0 := rot + TAU * i / sides - half
		var a1 := a0 + TAU / sides
		var p00 := Vector3(sin(a0) * r0, y0, cos(a0) * r0)
		var p01 := Vector3(sin(a1) * r0, y0, cos(a1) * r0)
		var p10 := Vector3(sin(a0) * r1, y1, cos(a0) * r1)
		var p11 := Vector3(sin(a1) * r1, y1, cos(a1) * r1)
		if inward:
			quad(xf * p10, xf * p11, xf * p01, xf * p00)
		else:
			quad(xf * p00, xf * p01, xf * p11, xf * p10)
		if cap0 and r0 > 0.0:
			var c := xf * Vector3(0, y0, 0)
			var n := (xf.basis * Vector3.DOWN).normalized()
			tri(c, xf * p00, xf * p01, n, n, n, _uv(c, n), _uv(xf * p00, n), _uv(xf * p01, n))
		if cap1 and r1 > 0.0:
			var c := xf * Vector3(0, y1, 0)
			var n := (xf.basis * Vector3.UP).normalized()
			tri(c, xf * p10, xf * p11, n, n, n, _uv(c, n), _uv(xf * p10, n), _uv(xf * p11, n))


## Capped cylinder; axis = local Y of xf, half height hh (pegs, pistons, hinges).
func cylinder(xf: Transform3D, r: float, hh: float, sides: int = 12, smooth: bool = true) -> void:
	var up := (xf.basis * Vector3.UP).normalized()
	for i: int in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var top := Vector3(0, hh, 0)
		tri(xf * top, xf * (p0 + top), xf * (p1 + top), up, up, up, Vector2.ZERO, Vector2(r, 0), Vector2(0, r))
		tri(xf * -top, xf * (p1 - top), xf * (p0 - top), -up, -up, -up, Vector2.ZERO, Vector2(r, 0), Vector2(0, r))
		var n0 := (xf.basis * p0).normalized()
		var n1 := (xf.basis * p1).normalized()
		if not smooth:
			n0 = (xf.basis * (p0 + p1)).normalized()
			n1 = n0
		quad_n(xf * (p0 - top), xf * (p1 - top), xf * (p1 + top), xf * (p0 + top), n0, n1, n1, n0,
			Vector2(r * a0, -hh), Vector2(r * a1, -hh), Vector2(r * a1, hh), Vector2(r * a0, hh))


## Flattened dome facing n (rivets, studs, lamps).
func dome(c: Vector3, n: Vector3, r: float, sides: int = 8, rings: int = 3) -> void:
	n = n.normalized()
	var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := n.cross(t1)
	var prev: Array[Vector3] = []
	var prevn: Array[Vector3] = []
	for j: int in rings + 1:
		var phi := PI * 0.5 * float(j) / rings
		var ring: Array[Vector3] = []
		var ringn: Array[Vector3] = []
		for i: int in sides:
			var a := TAU * float(i) / sides
			var radial := t1 * cos(a) + t2 * sin(a)
			ring.append(c + radial * r * cos(phi) + n * r * 0.65 * sin(phi))
			ringn.append((radial * cos(phi) + n * sin(phi) * 1.4).normalized())
		if j > 0:
			for i: int in sides:
				var k := (i + 1) % sides
				quad_n(prev[i], prev[k], ring[k], ring[i], prevn[i], prevn[k], ringn[k], ringn[i], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		prev = ring
		prevn = ringn


## Surface of revolution around local Y from a (radius, height) profile, smooth normals.
func lathe(profile: Array, segments: int = 24, xf: Transform3D = Transform3D()) -> void:
	for k: int in profile.size() - 1:
		var p0: Vector2 = profile[k]
		var p1: Vector2 = profile[k + 1]
		var d := p1 - p0
		if d.length() < 1e-6:
			continue
		var n2 := Vector2(d.y, -d.x).normalized()  # outward for a profile drawn bottom -> top
		for i: int in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var v00 := xf * Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := xf * Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := xf * Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := xf * Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var na := (xf.basis * Vector3(cos(a0) * n2.x, n2.y, sin(a0) * n2.x)).normalized()
			var nb := (xf.basis * Vector3(cos(a1) * n2.x, n2.y, sin(a1) * n2.x)).normalized()
			if (v01 - v00).length() > 1e-7 or (v11 - v10).length() > 1e-7:
				quad_n(v00, v01, v11, v10, na, nb, nb, na, Vector2(a0 * p0.x, p0.y), Vector2(a1 * p0.x, p0.y), Vector2(a1 * p1.x, p1.y), Vector2(a0 * p1.x, p1.y))


## Convex polygon given as (z, y) points, extruded along X (brackets, fins, trims).
func prism_x(xf: Transform3D, x0: float, x1: float, poly: PackedVector2Array) -> void:
	if x0 > x1:
		var tmp := x0
		x0 = x1
		x1 = tmp
	var c := Vector2.ZERO
	for p: Vector2 in poly:
		c += p
	c /= poly.size()
	for xs: float in [x0, x1]:
		var n := (xf.basis * (Vector3(-1, 0, 0) if xs == x0 else Vector3(1, 0, 0))).normalized()
		for i: int in range(1, poly.size() - 1):
			var a := xf * Vector3(xs, poly[0].y, poly[0].x)
			var b := xf * Vector3(xs, poly[i].y, poly[i].x)
			var d := xf * Vector3(xs, poly[i + 1].y, poly[i + 1].x)
			tri(a, b, d, n, n, n, _uv(a, n), _uv(b, n), _uv(d, n))
	for i: int in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var e := q - p
		if e.length() < 1e-5:
			continue
		quad(xf * Vector3(x0, p.y, p.x), xf * Vector3(x1, p.y, p.x), xf * Vector3(x1, q.y, q.x), xf * Vector3(x0, q.y, q.x))
