class_name GlowButton
extends Button
## The primary call to action of a terminal (D-055): tall, display-font caps,
## a glyph, a breathing outer glow, a light sweep crossing it every few
## seconds and a cost chip on its right ("−16 FUEL"). Hover/focus lift it and
## brighten the glow; ui_hover / ui_click sounds as every UiKit button.
## Disabled: dim plate, no glow, no sweep. Styles: "primary" (amber),
## "go" (teal), "danger" (red, irreversible actions).
##   var b := GlowButton.make(Loc.t("Travel here"), "ui.icon_ship", "go", on_travel); b.set_cost("−16", "ui.icon_fuel")

var style := "primary"
var _glow: Control
var _sweep: Control
var _cost_box: HBoxContainer
var _t := 0.0
var _boxes: Array[StyleBoxFlat] = []


static func make(text_value: String, icon_slot: String = "", kind: String = "primary", cb: Callable = Callable(), tip: String = "") -> GlowButton:
	var b := GlowButton.new()
	b.style = kind
	b.text = text_value.to_upper()
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_override("font", UiKit.display_variant(2))
	b.add_theme_font_size_override("font_size", 19)
	if not icon_slot.is_empty():
		UiKit.with_icon(b, icon_slot, 24)
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func() -> void: AudioService.ui("ui_click"))
	b.mouse_entered.connect(func() -> void: AudioService.ui("ui_hover"))
	b._styles()
	HoloAnim.hover_lift(b, 0.02, 0.12)
	return b


func _col() -> Color:
	return {"go": Color("3fd8c8"), "danger": UiKit.DANGER.lightened(0.1)}.get(style, UiKit.AMBER)


func _styles() -> void:
	var c := _col()
	var base := StyleBoxFlat.new()
	base.bg_color = Color(c.darkened(0.62), 0.95)
	base.border_color = c
	base.set_border_width_all(2)
	base.border_width_bottom = 3
	base.corner_radius_top_left = 4
	base.corner_radius_bottom_right = 4
	base.corner_radius_top_right = 14
	base.corner_radius_bottom_left = 14
	base.content_margin_left = 18
	base.content_margin_right = 18
	base.content_margin_top = 8
	base.content_margin_bottom = 8
	base.shadow_color = Color(c, 0.25)
	base.shadow_size = 6
	var hov := base.duplicate() as StyleBoxFlat
	hov.bg_color = Color(c.darkened(0.45), 0.98)
	hov.border_color = c.lightened(0.35)
	hov.shadow_size = 12
	hov.shadow_color = Color(c, 0.4)
	var pr := base.duplicate() as StyleBoxFlat
	pr.bg_color = Color(c.darkened(0.2), 1.0)
	pr.border_color = Color.WHITE
	var dis := base.duplicate() as StyleBoxFlat
	dis.bg_color = Color("10181d")
	dis.border_color = Color("2b3940")
	dis.shadow_size = 0
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = Color.WHITE
	foc.set_border_width_all(2)
	foc.corner_radius_top_right = 16
	foc.corner_radius_bottom_left = 16
	foc.set_expand_margin_all(4)
	add_theme_stylebox_override("normal", base)
	add_theme_stylebox_override("hover", hov)
	add_theme_stylebox_override("pressed", pr)
	add_theme_stylebox_override("hover_pressed", pr)
	add_theme_stylebox_override("disabled", dis)
	add_theme_stylebox_override("focus", foc)
	add_theme_color_override("font_color", c.lightened(0.6))
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_focus_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)
	add_theme_color_override("font_disabled_color", Color(UiKit.MUTED, 0.6))
	add_theme_color_override("icon_normal_color", c.lightened(0.4))
	add_theme_color_override("icon_hover_color", Color.WHITE)
	add_theme_color_override("icon_focus_color", Color.WHITE)
	add_theme_color_override("icon_disabled_color", Color(UiKit.MUTED, 0.4))
	add_theme_constant_override("h_separation", 12)


## A cost chip on the right: glyph + amount (e.g. "−16" fuel, "3" components).
func set_cost(amount: String, icon_slot: String = "", caption: String = "") -> void:
	if _cost_box:
		_cost_box.queue_free()
	_cost_box = UiKit.hbox(5)
	_cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_cost_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cost_box.offset_right = -16
	var c := _col()
	if not icon_slot.is_empty():
		var ic := UiKit.icon_rect(icon_slot, 18, c.lightened(0.3))
		if ic:
			_cost_box.add_child(ic)
	var l := UiKit.label(amount, 18, Color.WHITE)
	l.add_theme_font_override("font", UiKit.display_font())
	_cost_box.add_child(l)
	if not caption.is_empty():
		var cl := UiKit.label(caption.to_upper(), 11, c.lightened(0.3))
		cl.add_theme_font_override("font", UiKit.display_variant(1))
		_cost_box.add_child(cl)
	add_child(_cost_box)
	# Room for the chip, so the label never runs under it.
	var w := 30.0 + l.get_minimum_size().x + (24.0 if not icon_slot.is_empty() else 0.0) + (60.0 if not caption.is_empty() else 0.0)
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := get_theme_stylebox(st) as StyleBoxFlat
		if sb:
			sb.content_margin_right = 18.0 + w
	_cost_box.modulate.a = 0.45 if disabled else 1.0


func _ready() -> void:
	# Glow behind the plate and the sweep over it, both drawn in code.
	_glow = Control.new()
	_glow.show_behind_parent = true
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	move_child(_glow, 0)
	_sweep = Control.new()
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sweep.clip_contents = true
	_sweep.draw.connect(_draw_sweep)
	add_child(_sweep)
	_t = randf() * 2.0
	set_process(not HoloAnim.calm())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_glow.queue_redraw()
	_sweep.queue_redraw()
	if _cost_box:
		_cost_box.modulate.a = 0.45 if disabled else 1.0


func _draw_glow() -> void:
	if disabled:
		return
	var c := _col()
	var p := 0.5 + 0.5 * sin(_t * 2.4) if not HoloAnim.calm() else 0.6
	var hot := 1.6 if is_hovered() or has_focus() else 1.0
	var r := Rect2(Vector2.ZERO, size)
	while _boxes.size() < 4:
		_boxes.append(StyleBoxFlat.new())
	for i: int in 4:
		var g := 3.0 + i * 4.0 * (0.7 + p * 0.5)
		var sb: StyleBoxFlat = _boxes[i]
		sb.bg_color = Color(c, (0.09 - i * 0.018) * hot * (0.6 + p * 0.6))
		sb.corner_radius_top_right = int(14 + g)
		sb.corner_radius_bottom_left = int(14 + g)
		sb.corner_radius_top_left = int(4 + g)
		sb.corner_radius_bottom_right = int(4 + g)
		_glow.draw_style_box(sb, r.grow(g))


func _draw_sweep() -> void:
	if disabled or HoloAnim.calm():
		return
	var k := fmod(_t, 3.2) / 1.1  # a sweep of 1.1 s, then a pause
	if k > 1.0:
		return
	var x := lerpf(-60.0, size.x + 60.0, k)
	var h := size.y
	var pts := PackedVector2Array([Vector2(x - 18.0, h), Vector2(x + 6.0, 0), Vector2(x + 30.0, 0), Vector2(x + 6.0, h)])
	_sweep.draw_colored_polygon(pts, Color(1, 1, 1, 0.13))
	var pts2 := PackedVector2Array([Vector2(x + 34.0, h), Vector2(x + 50.0, 0), Vector2(x + 56.0, 0), Vector2(x + 40.0, h)])
	_sweep.draw_colored_polygon(pts2, Color(1, 1, 1, 0.08))
