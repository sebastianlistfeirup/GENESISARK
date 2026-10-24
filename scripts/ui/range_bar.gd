class_name RangeBar
extends Control
## A value on its scale (D-055): a dark track with ticks, an optional "good"
## zone, and then by status:
##   known     - a bright diamond marker at the value with a filled lead-in
##   estimated - an amber band from min to max with soft (uncertain) edges,
##               end caps and a light sweeping across it
##   unknown   - diagonal stripes over the whole track and a lock in the middle
## The band/marker grows in when shown; with reduced motion it is drawn final.
## Meaning never rests on colour alone: the tile beside it always has text.
##   var b := RangeBar.new(); b.setup(0.5, 1.5, "estimated", 0.9, 1.3); b.ideal = Vector2(0.85, 1.15)

var lo := 0.0
var hi := 1.0
var status := "unknown"  # known / estimated / unknown
var vmin := 0.0
var vmax := 0.0
var ideal := Vector2(NAN, NAN)  # optional comfortable zone on the scale
var col := UiKit.AMBER
var live := true  # false: no endless sweep (many bars, e.g. the comparison)
var best := false  # highlighted as the best of its row (comparison)
var _reveal := 1.0
var _t := 0.0
var _lock: Texture2D


func setup(scale_lo: float, scale_hi: float, st: String, a: float = 0.0, b: float = 0.0) -> RangeBar:
	lo = scale_lo
	hi = scale_hi
	status = st
	vmin = minf(a, b)
	vmax = maxf(a, b)
	col = {"known": Color("5fe0c8"), "estimated": UiKit.AMBER}.get(st, UiKit.MUTED)
	custom_minimum_size.y = maxf(custom_minimum_size.y, 14.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _ready() -> void:
	_lock = SyntySkin.icon("ui.icon_locked", 24)
	_t = randf() * 3.0
	if HoloAnim.calm():
		_reveal = 1.0
	else:
		_reveal = 0.0
		var tw := create_tween()
		tw.tween_interval(0.12 + randf() * 0.12)
		tw.tween_property(self, "_reveal", 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	set_process(not HoloAnim.calm())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if live or _reveal < 1.0:
		queue_redraw()


func _x(v: float) -> float:
	return clampf((v - lo) / maxf(0.0001, hi - lo), 0.0, 1.0) * size.x


func _draw() -> void:
	var w := size.x
	var h := size.y
	var mid := h * 0.5
	var th := minf(8.0, h * 0.55)
	var track := Rect2(0, mid - th * 0.5, w, th)
	draw_rect(track, Color(0.01, 0.03, 0.05, 0.85), true)
	if not is_nan(ideal.x):
		var zr := Rect2(_x(ideal.x), track.position.y, _x(ideal.y) - _x(ideal.x), th)
		draw_rect(zr, Color(UiKit.OK, 0.16), true)
		draw_line(Vector2(zr.position.x, track.position.y + th), Vector2(zr.end.x, track.position.y + th), Color(UiKit.OK, 0.5), 1.0)
	# Ticks every tenth of the scale, taller at the middle.
	for i: int in 11:
		var x := w * i / 10.0
		var tl := 3.0 if i % 5 != 0 else 5.0
		draw_line(Vector2(x, track.position.y - tl), Vector2(x, track.position.y), Color(UiKit.PETROL.lightened(0.3), 0.35), 1.0)
	draw_rect(track, Color(UiKit.PETROL, 0.45), false, 1.0)
	match status:
		"known":
			var x := _x(vmin) * _reveal
			var fill := Rect2(0, track.position.y + 1, x, th - 2)
			draw_rect(fill, Color(col, 0.28), true)
			draw_line(Vector2(0, mid), Vector2(x, mid), Color(col, 0.75), 2.0)
			var r := th * 0.95
			var pulse := 0.5 + 0.5 * sin(_t * 2.6) if live and not HoloAnim.calm() else 1.0
			draw_circle(Vector2(x, mid), r * (1.8 + pulse * 0.6), Color(col, 0.12 + 0.1 * pulse))
			draw_colored_polygon(PackedVector2Array([Vector2(x, mid - r), Vector2(x + r, mid), Vector2(x, mid + r), Vector2(x - r, mid)]), col.lightened(0.35))
		"estimated":
			var c := (_x(vmin) + _x(vmax)) * 0.5
			var half := (_x(vmax) - _x(vmin)) * 0.5 * _reveal
			var a := c - half
			var b := c + half
			# Soft edges: the band fades out past its ends (the value may lie a little outside).
			var soft := minf(14.0, w * 0.05)
			for i: int in 4:
				var k := float(i + 1) / 4.0
				draw_rect(Rect2(a - soft * k, track.position.y + 1, (b - a) + soft * k * 2.0, th - 2), Color(col, 0.07), true)
			draw_rect(Rect2(a, track.position.y + 1, b - a, th - 2), Color(col, 0.45), true)
			# End caps and a dotted mid line ("about here").
			for x: float in [a, b]:
				draw_line(Vector2(x, mid - th), Vector2(x, mid + th), col.lightened(0.2), 2.0)
			var y := mid
			var dx := a + 2.0
			while dx < b - 2.0:
				draw_line(Vector2(dx, y), Vector2(minf(dx + 3.0, b - 2.0), y), Color(1, 0.95, 0.8, 0.55), 1.0)
				dx += 6.0
			if live and not HoloAnim.calm() and b - a > 6.0:
				var sx := a + fmod(_t * 0.45, 1.0) * (b - a)
				draw_line(Vector2(sx, track.position.y + 1), Vector2(sx, track.end.y - 1), Color(1, 1, 1, 0.65), 2.0)
		_:
			var step := 9.0
			var x0 := -th
			while x0 < w:
				var p1 := Vector2(clampf(x0, 0.0, w), track.end.y - 1)
				var p2 := Vector2(clampf(x0 + th, 0.0, w), track.position.y + 1)
				draw_line(p1, p2, Color(UiKit.MUTED, 0.3), 2.0)
				x0 += step
			var lr := 10.0
			if _lock:
				draw_rect(Rect2(w * 0.5 - lr - 3.0, mid - lr, lr * 2.0 + 6.0, lr * 2.0), Color(0.02, 0.04, 0.06, 0.95), true)
				draw_texture_rect(_lock, Rect2(w * 0.5 - lr * 0.8, mid - lr * 0.8, lr * 1.6, lr * 1.6), false, Color(UiKit.MUTED, 0.95))
	if best:
		draw_rect(Rect2(-2, track.position.y - 3, w + 4, th + 6), Color(UiKit.AMBER, 0.7), false, 1.0)
