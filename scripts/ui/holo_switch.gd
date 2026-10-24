class_name HoloSwitch
extends CheckButton
## A holo toggle switch (D-059): a 72x30 pill drawn in code, the knob slides
## across (instantly with reduced motion), ON glows petrol with the word "ON"
## beside the knob, OFF is a dark outlined track with "OFF". Shape, position
## and word all change, so the state never rests on colour alone. Keyboard /
## pad toggle it like any CheckButton; focus draws the amber outline.
##   var s := HoloSwitch.make(true, func(on: bool) -> void: ...)

const W := 72.0
const H := 30.0
var _k := 0.0  # knob position 0 (off) .. 1 (on)
static var _blank: ImageTexture


static func make(on: bool, cb: Callable = Callable()) -> HoloSwitch:
	var s := HoloSwitch.new()
	s.button_pressed = on
	s._k = 1.0 if on else 0.0
	s.focus_mode = Control.FOCUS_ALL
	s.custom_minimum_size = Vector2(W + 8.0, H + 6.0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _blank == null:
		var img := Image.create(int(W), int(H), false, Image.FORMAT_RGBA8)
		_blank = ImageTexture.create_from_image(img)
	for st: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		s.add_theme_icon_override(st, _blank)
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = UiKit.AMBER
	foc.set_border_width_all(2)
	foc.set_corner_radius_all(18)
	foc.set_expand_margin_all(2)
	s.add_theme_stylebox_override("focus", foc)
	if cb.is_valid():
		s.toggled.connect(cb)
	s.toggled.connect(func(_on: bool) -> void:
		AudioService.ui("ui_click")
		s.set_process(true))
	return s


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	var target := 1.0 if button_pressed else 0.0
	if UiKit.calm():
		_k = target
	else:
		_k = move_toward(_k, target, delta * 7.0)
	queue_redraw()
	if is_equal_approx(_k, target):
		set_process(false)


func _draw() -> void:
	var r := Rect2(size.x - W - 4.0, (size.y - H) * 0.5, W, H)
	var on := button_pressed
	var e := ease(_k, -2.0)
	var c := UiKit.PETROL.lightened(0.2)
	var dim := disabled
	var track := Color(0.02, 0.05, 0.07, 0.95).lerp(Color(c.darkened(0.35), 0.95), e)
	var edge := Color(UiKit.MUTED, 0.55).lerp(Color(c.lightened(0.35), 0.95), e)
	if dim:
		track = track.darkened(0.4)
		edge = Color(edge, 0.3)
	var rad := H * 0.5
	if e > 0.05 and not dim:  # soft glow behind a lit switch
		_pill(r.grow(3.0), Color(c, 0.18 * e))
	_pill(r, track)
	_pill_outline(r, edge)
	var kx := lerpf(r.position.x + rad, r.end.x - rad, e)
	var kc := Color.WHITE.lerp(UiKit.MUTED, 1.0 - e) if not dim else Color(UiKit.MUTED, 0.5)
	draw_circle(Vector2(kx, r.get_center().y), rad - 4.0, kc, true, -1.0, true)
	if e > 0.5 and not dim:
		draw_circle(Vector2(kx, r.get_center().y), rad - 1.0, Color(c.lightened(0.5), 0.25), false, 1.5, true)
	var word := Loc.t("ON") if on else Loc.t("OFF")
	var font := UiKit.display_variant(1)
	var fs := 12
	var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := (r.position.x + 10.0) if on else (r.end.x - 10.0 - tw)
	draw_string(font, Vector2(tx, r.get_center().y + fs * 0.36), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if on else UiKit.MUTED)


func _pill(r: Rect2, col: Color) -> void:
	# One capsule polygon, so translucent fills do not double up where parts overlap.
	var rad := r.size.y * 0.5
	var pts := PackedVector2Array()
	var cl := Vector2(r.position.x + rad, r.get_center().y)
	var cr := Vector2(r.end.x - rad, r.get_center().y)
	for i: int in 17:
		pts.append(cr + Vector2.from_angle(-PI * 0.5 + PI * i / 16.0) * rad)
	for i: int in 17:
		pts.append(cl + Vector2.from_angle(PI * 0.5 + PI * i / 16.0) * rad)
	draw_colored_polygon(pts, col)


func _pill_outline(r: Rect2, col: Color) -> void:
	var rad := r.size.y * 0.5
	draw_line(Vector2(r.position.x + rad, r.position.y), Vector2(r.end.x - rad, r.position.y), col, 1.5, true)
	draw_line(Vector2(r.position.x + rad, r.end.y), Vector2(r.end.x - rad, r.end.y), col, 1.5, true)
	draw_arc(Vector2(r.position.x + rad, r.get_center().y), rad, PI * 0.5, PI * 1.5, 16, col, 1.5, true)
	draw_arc(Vector2(r.end.x - rad, r.get_center().y), rad, -PI * 0.5, PI * 0.5, 16, col, 1.5, true)
