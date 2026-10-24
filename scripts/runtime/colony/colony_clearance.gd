class_name ColonyClearance
extends RefCounted
## What decorative things must keep clear of: building footprints, corridor
## tubes and roads, in a coarse bucket grid so a few thousand props can be
## tested quickly. Presentation helper only (the domain owns real placement).

const CELL := 12.0

var _rects: Array = []     # [Rect2, building id]
var _segs: Array = []      # [Vector2 a, Vector2 b, half width]
var _grid: Dictionary = {}  # Vector2i -> Array of ["r"|"s", index]


func add_rect(r: Rect2, building_id: int) -> void:
	_rects.append([r, building_id])
	_insert(r, ["r", _rects.size() - 1])


func add_segment(a: Vector2, b: Vector2, half_width: float) -> void:
	_segs.append([a, b, half_width])
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(half_width)
	_insert(r, ["s", _segs.size() - 1])


func add_polyline(pts: PackedVector2Array, half_width: float) -> void:
	for i: int in range(1, pts.size()):
		add_segment(pts[i - 1], pts[i], half_width)


func _insert(r: Rect2, entry: Array) -> void:
	var a := Vector2i(floori(r.position.x / CELL), floori(r.position.y / CELL))
	var b := Vector2i(floori(r.end.x / CELL), floori(r.end.y / CELL))
	for x: int in range(a.x, b.x + 1):
		for y: int in range(a.y, b.y + 1):
			var k := Vector2i(x, y)
			if not _grid.has(k):
				_grid[k] = []
			(_grid[k] as Array).append(entry)


## True when a disc at p with radius r touches anything except building `own`.
func blocked(p: Vector2, r: float, own: int = -1, rects_only: bool = false) -> bool:
	var a := Vector2i(floori((p.x - r) / CELL), floori((p.y - r) / CELL))
	var b := Vector2i(floori((p.x + r) / CELL), floori((p.y + r) / CELL))
	for x: int in range(a.x, b.x + 1):
		for y: int in range(a.y, b.y + 1):
			for e: Array in _grid.get(Vector2i(x, y), []):
				if e[0] == "r":
					var rr: Array = _rects[e[1]]
					if int(rr[1]) != own and (rr[0] as Rect2).grow(r + 0.25).has_point(p):
						return true
				elif not rects_only:
					var s: Array = _segs[e[1]]
					if Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) < float(s[2]) + r:
						return true
	return false


func rects() -> Array:
	return _rects


## Footprints closer than d to p (each once), nearest first not guaranteed.
func rects_near(p: Vector2, d: float) -> Array:
	var out: Array = []
	var seen := {}
	var a := Vector2i(floori((p.x - d) / CELL), floori((p.y - d) / CELL))
	var b := Vector2i(floori((p.x + d) / CELL), floori((p.y + d) / CELL))
	for x: int in range(a.x, b.x + 1):
		for y: int in range(a.y, b.y + 1):
			for e: Array in _grid.get(Vector2i(x, y), []):
				if e[0] != "r" or seen.has(e[1]):
					continue
				seen[e[1]] = true
				var r: Rect2 = _rects[e[1]][0]
				var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
				if c.distance_to(p) < d:
					out.append(r)
	return out
