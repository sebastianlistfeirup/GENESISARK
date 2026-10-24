class_name HoloForm
extends RefCounted
## Settings-style rows for the holo menus (D-059). Every row is one glass
## strip: a glyph badge, the caption with an optional muted hint under it,
## and the control on the right. The row lights (petrol plate, amber accent
## bar) while its control is hovered or focused, so keyboard / pad users see
## where they are at a glance; clicking anywhere on a switch row toggles it.
##   HoloForm.slider_row(icon, caption, hint, value, lo, hi, step, fmt, on_change)
##   HoloForm.switch_row(icon, caption, hint, on, on_toggle)
##   HoloForm.choice_row(icon, caption, hint, [[id, label], ...], current, on_pick)
##   HoloForm.key_row(caption, binding_text, waiting, on_press)
## The focusable control of a row is row.get_meta("focus").


## Glass strip with a left accent bar; lit while its control has hover/focus.
class Row extends PanelContainer:
	var lit := false
	var _base: StyleBoxFlat
	var _hot: StyleBoxFlat

	func _init() -> void:
		_base = StyleBoxFlat.new()
		_base.bg_color = Color(0.02, 0.05, 0.07, 0.55)
		_base.border_color = Color(UiKit.PETROL.lerp(UiKit.MUTED, 0.5), 0.14)
		_base.set_border_width_all(1)
		_base.corner_radius_top_right = 10
		_base.corner_radius_bottom_left = 10
		_base.content_margin_left = 14
		_base.content_margin_right = 12
		_base.content_margin_top = 7
		_base.content_margin_bottom = 7
		_hot = _base.duplicate() as StyleBoxFlat
		_hot.bg_color = Color(UiKit.PETROL.darkened(0.6), 0.85)
		_hot.border_color = Color(UiKit.PETROL.lightened(0.2), 0.45)
		add_theme_stylebox_override("panel", _base)
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func watch(c: Control) -> void:
		c.focus_entered.connect(func() -> void: set_lit(true))
		c.focus_exited.connect(func() -> void: set_lit(false))
		c.mouse_entered.connect(func() -> void: set_lit(true))
		c.mouse_exited.connect(func() -> void: set_lit(c.has_focus()))
		mouse_entered.connect(func() -> void: set_lit(true))
		mouse_exited.connect(func() -> void: set_lit(c.has_focus()))

	func set_lit(on: bool) -> void:
		lit = on
		add_theme_stylebox_override("panel", _hot if on else _base)
		queue_redraw()

	func _draw() -> void:
		var col := UiKit.AMBER if lit else Color(UiKit.PETROL.lightened(0.2), 0.45)
		draw_rect(Rect2(0, 8, 3, size.y - 16), col, true)


## The left half of a row: badge + caption (+ hint under it).
static func _label_block(icon_slot: String, caption: String, hint: String, fallback: String = "◆") -> HBoxContainer:
	var h := UiKit.hbox(12)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not icon_slot.is_empty():
		h.add_child(IconBadge.make(icon_slot, 32, UiKit.PETROL.lightened(0.35), false, fallback))
	var v := UiKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(caption, 17, UiKit.TEXT, true)
	l.add_theme_font_override("font", UiKit.bold_font())
	v.add_child(l)
	if not hint.is_empty():
		v.add_child(UiKit.label(hint, 13, UiKit.MUTED, true))
	h.add_child(v)
	return h


static func row(icon_slot: String, caption: String, hint: String, control: Control, focus: Control = null) -> Row:
	var r := Row.new()
	var h := UiKit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_label_block(icon_slot, caption, hint))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	r.add_child(h)
	var f := focus if focus else control
	r.set_meta("focus", f)
	r.watch(f)
	return r


## A live value chip (display face) that the slider row updates.
static func value_chip(text: String, w: float = 78.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiKit.PETROL.darkened(0.7), 0.9)
	sb.border_color = Color(UiKit.PETROL.lightened(0.25), 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, 32)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 18, Color.WHITE)
	l.add_theme_font_override("font", UiKit.display_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Slider + live value chip. `fmt` turns the value into the chip text.
static func slider_row(icon_slot: String, caption: String, hint: String, value: float, lo: float, hi: float, step: float, fmt: Callable, on_change: Callable, w: float = 300.0) -> Row:
	var s := HoloSlider.make(lo, hi, step, value, w)
	var chip := value_chip(str(fmt.call(value)))
	var lbl := chip.get_child(0) as Label
	s.value_changed.connect(func(v: float) -> void:
		lbl.text = str(fmt.call(v))
		on_change.call(v))
	var h := UiKit.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(s)
	h.add_child(chip)
	return row(icon_slot, caption, hint, h, s)


static func switch_row(icon_slot: String, caption: String, hint: String, on: bool, on_toggle: Callable) -> Row:
	var sw := HoloSwitch.make(on, on_toggle)
	sw.tooltip_text = caption
	var r := row(icon_slot, caption, hint, sw)
	# Clicking anywhere on the strip toggles the switch.
	r.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not sw.disabled:
			sw.button_pressed = not sw.button_pressed
			sw.grab_focus())
	return r


## Segmented choice: one button per option, the current one marked (amber, bright text).
static func choice_row(icon_slot: String, caption: String, hint: String, options: Array, current: String, on_pick: Callable) -> Row:
	var h := UiKit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var first: Button
	var sel: Button
	for o: Array in options:
		var id := str(o[0])
		var b := UiKit.button(str(o[1]), func() -> void: on_pick.call(id))
		b.custom_minimum_size = Vector2(86, 38)
		if id == current:
			UiKit.mark_selected(b)
			sel = b
		h.add_child(b)
		if first == null:
			first = b
	var f := first
	if sel == first and h.get_child_count() > 1:
		f = h.get_child(1) as Button  # focus a pickable option, not the marked one
	var r := row(icon_slot, caption, hint, h, f)
	for b: Node in h.get_children():
		if b != f:
			r.watch(b as Control)
	return r


## A key binding as key caps ("W", "Up") in a button; "Press a key…" while waiting.
static func key_row(caption: String, binding: String, waiting: bool, on_press: Callable) -> Row:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(250, 40)
	b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: AudioService.ui("ui_click"))
	HoloAnim.hover_lift(b, 0.015, 0.1)
	var caps := UiKit.hbox(6)
	caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caps.alignment = BoxContainer.ALIGNMENT_CENTER
	caps.set_anchors_preset(Control.PRESET_FULL_RECT)
	if waiting:
		var w := UiKit.label(Loc.t("Press a key..."), 16, UiKit.AMBER)
		w.add_theme_font_override("font", UiKit.display_variant(1))
		caps.add_child(w)
		HoloAnim.pulse.call_deferred(w, 0.5, 0.9)
	else:
		var parts := binding.split(" / ", false)
		for i: int in parts.size():
			if i > 0:
				caps.add_child(UiKit.label("/", 14, UiKit.MUTED))
			caps.add_child(UiKit.keycap(parts[i], 15))
	b.add_child(caps)
	b.tooltip_text = binding
	return row("", caption, "", b)
