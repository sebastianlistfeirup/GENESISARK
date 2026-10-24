class_name HoloFrame
extends Control
## Holo-console dressing for any PanelContainer (D-055). `HoloFrame.attach(panel)`
## adds two layers that cover the WHOLE panel (they reach out past the content
## margins), so the content layout is untouched:
##   back  - a faint hexagon grid and a cool top light behind the content
##   front - the holo shader (scanlines, scan band, edge glow, grain, boot
##           reveal) plus code-drawn corner brackets that breathe, a segmented
##           data strip with a running light along the top edge and tick
##           marks down both sides.
## `boot()` plays the reveal (brackets fly in, a bright line prints the panel
## top-down). Reduced motion: no flicker, no breathing, no scroll; the static
## frame stays. Mouse is always ignored. OverlayPanel attaches one to every overlay.

const SHADER := preload("res://art/shaders/holo_panel.gdshader")

var tint := Color("6fe6dc")
var _fx: ColorRect
var _mat: ShaderMaterial
var _panel: Control
var _t := 0.0
var _fly := 0.0  # 1 = brackets far out (boot), 0 = home
var _calm := false


## Dresses `panel` and returns the front frame (call boot() on it when shown).
static func attach(panel: PanelContainer, colour: Color = Color("6fe6dc")) -> HoloFrame:
	var back := _Back.new()
	panel.add_child(back)
	panel.move_child(back, 0)
	var f := HoloFrame.new()
	f.tint = colour
	f._panel = panel
	panel.add_child(f)
	back.frame = f
	return f


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx = ColorRect.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_fx.material = _mat
	_fx.color = Color.WHITE
	add_child(_fx)


func _ready() -> void:
	_calm = HoloAnim.calm()
	_mat.set_shader_parameter("glow_color", Color(tint, 0.9))
	_mat.set_shader_parameter("fill_color", Color(0.012, 0.03, 0.045))
	_mat.set_shader_parameter("motion", 0.0 if _calm else 1.0)
	resized.connect(_fit)
	_fit()


## The panel's content margins: this control sits inside them, the art reaches out to the edge.
func margins() -> Vector4:
	var sb: StyleBox = _panel.get_theme_stylebox("panel") if _panel else null
	if sb == null:
		return Vector4.ZERO
	return Vector4(sb.content_margin_left, sb.content_margin_top, sb.content_margin_right, sb.content_margin_bottom)


func outer_rect() -> Rect2:
	var m := margins()
	return Rect2(-m.x, -m.y, size.x + m.x + m.z, size.y + m.y + m.w)


func _fit() -> void:
	var r := outer_rect()
	_fx.position = r.position
	_fx.size = r.size
	_mat.set_shader_parameter("px_size", r.size)
	queue_redraw()


## Boot reveal: a bright line prints the panel top-down, the brackets fly home.
func boot() -> void:
	_calm = HoloAnim.calm()
	_mat.set_shader_parameter("motion", 0.0 if _calm else 1.0)
	if _calm:
		_mat.set_shader_parameter("boot", 1.0)
		_mat.set_shader_parameter("flash", 0.0)
		_fly = 0.0
		queue_redraw()
		return
	_mat.set_shader_parameter("boot", 0.0)
	_mat.set_shader_parameter("flash", 0.6)
	_fly = 1.0
	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("boot", v), 0.0, 1.0, 0.36).set_delay(0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("flash", v), 0.6, 0.0, 0.3)
	tw.tween_property(self, "_fly", 0.0, 0.38).set_delay(0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _calm or not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var r := outer_rect().grow(-6.0)
	var breathe := 0.0 if _calm else (0.5 + 0.5 * sin(_t * 1.8)) * 2.5
	var out := breathe + _fly * 46.0
	var a := 1.0 - _fly * 0.8
	var k := 30.0
	var bright := Color(tint.lightened(0.35), 0.95 * a)
	var soft := Color(tint, 0.22 * a)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x <= r.position.x + 0.5 else -1.0
		var sy := 1.0 if corner.y <= r.position.y + 0.5 else -1.0
		var p := corner - Vector2(sx, sy) * out
		var pts := PackedVector2Array([p + Vector2(0, sy * k), p, p + Vector2(sx * k, 0)])
		draw_polyline(pts, soft, 7.0, true)
		draw_polyline(pts, bright, 2.0, true)
		draw_rect(Rect2(p + Vector2(sx * 4.0, sy * 4.0) - Vector2(2, 2), Vector2(4, 4)), Color(tint.lightened(0.5), a), true)
	# Data strip on the top edge: segments with a running light.
	var segs := 14
	var sw := 9.0
	var gap := 4.0
	var total := segs * (sw + gap)
	var x0 := r.get_center().x - total * 0.5
	var y := r.position.y - 1.0
	var run := int(_t * 9.0) % (segs + 6)
	for i: int in segs:
		var lit := absi(i - run) <= 1 and not _calm
		var c := Color(tint.lightened(0.5), 0.95 * a) if lit else Color(tint, (0.35 if i % 4 != 0 else 0.6) * a)
		draw_rect(Rect2(x0 + i * (sw + gap), y, sw, 3.0), c, true)
	# Tick marks down the sides, around the middle.
	var cy := r.get_center().y
	for i: int in 7:
		var ty := cy + (i - 3) * 9.0
		var l := 8.0 if i == 3 else 4.0
		draw_line(Vector2(r.position.x - 2.0, ty), Vector2(r.position.x - 2.0 + l, ty), Color(tint, 0.5 * a), 1.0)
		draw_line(Vector2(r.end.x + 2.0, ty), Vector2(r.end.x + 2.0 - l, ty), Color(tint, 0.5 * a), 1.0)


## Behind the content: a faint hexagon grid (Synty, one tiled draw) and a
## cool light from the top.
class _Back extends Control:
	var frame: HoloFrame
	var _grid: TextureRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var hex := Holo.tex(Holo.HUDP + "Background_Hexagons.png", 128)
		if hex:
			_grid = TextureRect.new()
			_grid.texture = hex
			_grid.stretch_mode = TextureRect.STRETCH_TILE
			_grid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_grid.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid.modulate = Color(frame.tint if frame else Color.WHITE, 0.035)
			add_child(_grid)
		resized.connect(_fit)
		_fit.call_deferred()

	func _fit() -> void:
		if frame == null:
			return
		var r := frame.outer_rect().grow(-4.0)
		if _grid:
			_grid.position = r.position
			_grid.size = r.size
		queue_redraw()

	func _draw() -> void:
		if frame == null:
			return
		var r := frame.outer_rect().grow(-4.0)
		# Top light: a few stacked translucent bands.
		for i: int in 6:
			var h := r.size.y * (0.06 + i * 0.05)
			draw_rect(Rect2(r.position, Vector2(r.size.x, h)), Color(frame.tint, 0.012), true)
