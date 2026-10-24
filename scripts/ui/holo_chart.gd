class_name HoloChart
extends Control
## A small holo line chart drawn in code (D-059): dark plot with a faint grid,
## y labels at 0 / half / max, x labels, vertical milestone markers with a tag,
## series as glowing lines (solid, or dashed for "planned / needed"), optional
## area fill, point markers with a value tag, and a legend in the corner.
## Lines draw in from the left when shown (final at once with reduced motion).
## Every value shown is also given as text elsewhere in the panel.
##   var c := HoloChart.new(); c.x_range = Vector2(0, 40); c.y_max = 500
##   c.add_series([Vector2(0, 0), Vector2(20, 120)], UiKit.FOOD, Loc.t("Forecast"))
##   c.add_marker(20.0, Loc.t("Handover"), UiKit.AMBER)

var x_range := Vector2(0, 1)
var y_max := 1.0
var x_labels: Array = []  # [[x, text], ...]
var y_suffix := ""
var series: Array = []  # [{pts, col, label, dashed, fill}]
var markers: Array = []  # [[x, text, Color], ...]
var points: Array = []  # [[Vector2, text, Color], ...]
var bands: Array = []  # [[y0, y1, Color, text], ...] horizontal zones (e.g. the goal)
var _k := 0.0
const PAD := Vector4(46, 14, 14, 26)  # left, top, right, bottom


func add_series(pts: Array, col: Color, label: String, dashed: bool = false, fill: bool = false) -> void:
	series.append({"pts": pts, "col": col, "label": label, "dashed": dashed, "fill": fill})


func add_marker(x: float, text: String, col: Color) -> void:
	markers.append([x, text, col])


func add_point(p: Vector2, text: String, col: Color) -> void:
	points.append([p, text, col])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_k = 1.0 if UiKit.calm() else 0.0


func _process(delta: float) -> void:
	if _k < 1.0 and is_visible_in_tree():
		_k = minf(1.0, _k + delta * 1.4)
		queue_redraw()


func _plot() -> Rect2:
	return Rect2(PAD.x, PAD.y, size.x - PAD.x - PAD.z, size.y - PAD.y - PAD.w)


func _to(p: Vector2) -> Vector2:
	var r := _plot()
	var tx := (p.x - x_range.x) / maxf(x_range.y - x_range.x, 0.0001)
	var ty := p.y / maxf(y_max, 0.0001)
	return Vector2(r.position.x + tx * r.size.x, r.end.y - clampf(ty, 0.0, 1.05) * r.size.y)


func _draw() -> void:
	var r := _plot()
	var font := UiKit.display_variant(1)
	draw_rect(r, Color(0.01, 0.03, 0.05, 0.85), true)
	for b: Array in bands:
		var y0 := _to(Vector2(0, float(b[0]))).y
		var y1 := _to(Vector2(0, float(b[1]))).y
		draw_rect(Rect2(r.position.x, y1, r.size.x, y0 - y1), Color(b[2] as Color, 0.12), true)
		draw_line(Vector2(r.position.x, y1), Vector2(r.end.x, y1), Color(b[2] as Color, 0.55), 1.0)
		draw_string(font, Vector2(r.end.x - 4 - font.get_string_size(str(b[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, y1 - 4), str(b[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, (b[2] as Color).lightened(0.3))
	# Grid + y labels.
	for i: int in 5:
		var y := r.end.y - r.size.y * i / 4.0
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(UiKit.PETROL, 0.12 if i > 0 else 0.4), 1.0)
		if i % 2 == 0:
			var t := "%d%s" % [int(roundf(y_max * i / 4.0)), y_suffix]
			draw_string(font, Vector2(r.position.x - 6 - font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.MUTED)
	for xl: Array in x_labels:
		var p := _to(Vector2(float(xl[0]), 0))
		draw_line(Vector2(p.x, r.end.y), Vector2(p.x, r.end.y + 4), Color(UiKit.MUTED, 0.6), 1.0)
		var t := str(xl[1])
		draw_string(font, Vector2(p.x - font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5, r.end.y + 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.MUTED)
	for m: Array in markers:
		var p := _to(Vector2(float(m[0]), 0))
		var c: Color = m[2]
		var y := r.position.y
		while y < r.end.y:
			draw_line(Vector2(p.x, y), Vector2(p.x, minf(y + 5, r.end.y)), Color(c, 0.55), 1.0)
			y += 9
		draw_string(font, Vector2(p.x + 4, r.position.y + 12), str(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c.lightened(0.2))
	# Series: clipped to the reveal (left to right).
	var cut := r.position.x + r.size.x * ease(_k, 0.4)
	for s: Dictionary in series:
		var pts := PackedVector2Array()
		for v: Variant in s["pts"]:
			pts.append(_to(v as Vector2))
		if pts.size() < 2:
			continue
		var vis := PackedVector2Array()
		for i: int in pts.size():
			if pts[i].x <= cut:
				vis.append(pts[i])
			elif i > 0:
				var a := pts[i - 1]
				var t := (cut - a.x) / maxf(pts[i].x - a.x, 0.001)
				vis.append(a.lerp(pts[i], clampf(t, 0.0, 1.0)))
				break
		if vis.size() < 2:
			continue
		var c: Color = s["col"]
		if s["fill"]:
			var poly := vis.duplicate()
			poly.append(Vector2(vis[vis.size() - 1].x, r.end.y))
			poly.append(Vector2(vis[0].x, r.end.y))
			draw_colored_polygon(poly, Color(c, 0.14))
		if s["dashed"]:
			for i: int in vis.size() - 1:
				var a := vis[i]
				var b := vis[i + 1]
				var n := int(a.distance_to(b) / 10.0) + 1
				for j: int in n:
					draw_line(a.lerp(b, float(j) / n), a.lerp(b, minf(1.0, (j + 0.55) / n)), Color(c, 0.85), 2.0, true)
		else:
			draw_polyline(vis, Color(c, 0.25), 6.0, true)
			draw_polyline(vis, c, 2.5, true)
	for pt: Array in points:
		var p := _to(pt[0] as Vector2)
		if p.x > cut + 1.0:
			continue
		var c: Color = pt[2]
		draw_circle(p, 7.0, Color(c, 0.25), true)
		draw_circle(p, 4.0, c.lightened(0.3), true)
		var t := str(pt[1])
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tx := clampf(p.x - tw * 0.5, r.position.x + 2, r.end.x - tw - 2)
		draw_string(font, Vector2(tx, p.y - 11), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c.lightened(0.4))
	draw_rect(r, Color(UiKit.PETROL.lightened(0.2), 0.3), false, 1.0)
	# Legend (top left inside the plot).
	var lx := r.position.x + 10
	for s: Dictionary in series:
		var c: Color = s["col"]
		var ly := r.position.y + 14
		if s["dashed"]:
			draw_line(Vector2(lx, ly - 4), Vector2(lx + 6, ly - 4), c, 2.0)
			draw_line(Vector2(lx + 10, ly - 4), Vector2(lx + 16, ly - 4), c, 2.0)
		else:
			draw_line(Vector2(lx, ly - 4), Vector2(lx + 16, ly - 4), c, 3.0)
		draw_string(font, Vector2(lx + 22, ly), str(s["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.TEXT)
		lx += 30 + font.get_string_size(str(s["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
