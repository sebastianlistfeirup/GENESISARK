class_name HoloCard
extends Button
## A large pickable card for the holo menus (D-059): save slots, event
## choices, generation decisions, objectives. It is a Button (mouse, keys and
## pad pick it; Enter/A presses it) whose look is a dark glass plate with a
## calm hairline, a coloured accent bar on the left and small corner ticks.
## Hover/focus light the plate in the accent colour and lift it a touch; focus
## also draws an outline (never colour alone). Content goes into `content`
## (a VBox, mouse ignored); the card sizes itself to it, so wrapped text fits.
## `dashed` draws a dashed outline instead (an empty "new save" slot);
## `arm(true)` turns it red for a press-again confirmation (overwrite).
##   var c := HoloCard.make(UiKit.AMBER, on_pick); c.content.add_child(...)

var accent := UiKit.PETROL
var content: VBoxContainer
var dashed := false
var armed := false
var pad := Vector4(18, 12, 16, 12)
var _base_w := -1.0  # the width the caller asked for (content may need more)
var _base: StyleBoxFlat
var _lit: StyleBoxFlat
var _off: StyleBoxFlat


static func make(col: Color, cb: Callable = Callable(), tip: String = "", margins: Vector4 = Vector4(18, 12, 16, 12)) -> HoloCard:
	var c := HoloCard.new()
	c.accent = col
	c.pad = margins
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_ALL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.content = UiKit.vbox(6)
	c.content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.content.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.content.offset_left = margins.x
	c.content.offset_top = margins.y
	c.content.offset_right = -margins.z
	c.content.offset_bottom = -margins.w
	c.add_child(c.content)
	c.content.minimum_size_changed.connect(c._sync_min)
	c.content.resized.connect(c._sync_min)
	if cb.is_valid():
		c.pressed.connect(cb)
	c.pressed.connect(func() -> void: AudioService.ui("ui_click"))
	c.mouse_entered.connect(func() -> void: AudioService.ui("ui_hover"))
	c._styles()
	HoloAnim.hover_lift(c, 0.012, 0.08)
	return c


## Button computes its own minimum size (text + icon), so the card keeps its
## height in custom_minimum_size, following the content (wrapped text included).
func _sync_min() -> void:
	if content == null:
		return
	if _base_w < 0.0:
		_base_w = custom_minimum_size.x
	var m := content.get_combined_minimum_size()
	var want := Vector2(maxf(_base_w, m.x + pad.x + pad.z), m.y + pad.y + pad.w)
	if not custom_minimum_size.is_equal_approx(want):
		custom_minimum_size = want


## The accent changes (status, armed): restyle and redraw.
func set_accent(col: Color) -> void:
	accent = col
	_styles()
	queue_redraw()


## Press-again state: the card turns red until it is pressed again or left.
func arm(on: bool) -> void:
	armed = on
	_styles()
	queue_redraw()


func _col() -> Color:
	return UiKit.DANGER.lightened(0.1) if armed else accent


func _styles() -> void:
	var c := _col()
	_base = StyleBoxFlat.new()
	_base.bg_color = Color(0.02, 0.05, 0.07, 0.82)
	# Calm hairline: desaturated and faint, so bright colour stays for the lit state.
	_base.border_color = Color(c.lerp(UiKit.MUTED, 0.55), 0.0 if dashed else 0.22)
	_base.set_border_width_all(1)
	_base.corner_radius_top_right = 12
	_base.corner_radius_bottom_left = 12
	_base.corner_radius_top_left = 2
	_base.corner_radius_bottom_right = 2
	_base.set_content_margin_all(0)
	if dashed:
		_base.bg_color = Color(0.02, 0.05, 0.07, 0.45)
	_lit = _base.duplicate() as StyleBoxFlat
	_lit.bg_color = Color(UiKit.PANEL.darkened(0.3).lerp(c, 0.16), 0.95)
	_lit.border_color = Color(c.lightened(0.15), 0.75)
	_lit.shadow_color = Color(c, 0.22)
	_lit.shadow_size = 8
	if armed:
		_base.bg_color = Color(c.darkened(0.75), 0.92)
		_base.border_color = Color(c, 0.8)
	_off = _base.duplicate() as StyleBoxFlat
	_off.bg_color = Color(0.03, 0.04, 0.05, 0.7)
	_off.border_color = Color(UiKit.MUTED, 0.15)
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = UiKit.AMBER.lightened(0.15)
	foc.set_border_width_all(2)
	foc.corner_radius_top_right = 14
	foc.corner_radius_bottom_left = 14
	foc.set_expand_margin_all(3)
	add_theme_stylebox_override("normal", _base)
	add_theme_stylebox_override("hover", _lit)
	add_theme_stylebox_override("pressed", _lit)
	add_theme_stylebox_override("hover_pressed", _lit)
	add_theme_stylebox_override("disabled", _off)
	add_theme_stylebox_override("focus", foc)


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		# Focused reads as lit too (keyboard / pad get the same cue as the mouse).
		add_theme_stylebox_override("normal", _lit if what == NOTIFICATION_FOCUS_ENTER else _base)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_MOUSE_ENTER:
		queue_redraw()


func _draw() -> void:
	var s := size
	var c := _col()
	var lit := (has_focus() or is_hovered()) and not disabled
	var a := 0.35 if disabled else (1.0 if lit or armed else 0.75)
	if dashed:
		var dc := Color(c.lerp(UiKit.MUTED, 0.3), 0.75 if lit else 0.45)
		_dash(Vector2(1, 1), Vector2(s.x - 1, 1), dc)
		_dash(Vector2(s.x - 1, 1), Vector2(s.x - 1, s.y - 1), dc)
		_dash(Vector2(s.x - 1, s.y - 1), Vector2(1, s.y - 1), dc)
		_dash(Vector2(1, s.y - 1), Vector2(1, 1), dc)
		return
	# Accent bar on the left, brighter when lit.
	draw_rect(Rect2(0, 10, 3, s.y - 20), Color(c.lightened(0.2 if lit else 0.0), a), true)
	# Corner ticks (top right, bottom left): the holo bracket language.
	var k := 12.0
	var tc := Color(c.lightened(0.3), 0.85 if lit else 0.4)
	draw_line(Vector2(s.x - k - 10, 2), Vector2(s.x - 10, 2), tc, 2.0)
	draw_line(Vector2(s.x - 2, 10), Vector2(s.x - 2, 10 + k), tc, 2.0)
	draw_line(Vector2(10, s.y - 2), Vector2(10 + k, s.y - 2), tc, 2.0)


func _dash(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var n := int(d.length() / 12.0)
	for i: int in n:
		var t0 := float(i) / n
		var t1 := t0 + 0.55 / n
		draw_line(a + d * t0, a + d * t1, col, 1.5)
