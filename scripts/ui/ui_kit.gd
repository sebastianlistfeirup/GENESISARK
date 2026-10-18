class_name UiKit
extends RefCounted
## Shared look for all screens: cool petrol + warm amber + clear service
## colours (bible p.13). Colour is never the only signal: every status also has
## text and a symbol (bible p.26). The theme can later take Synty INTERFACE
## textures via data/art/asset_slots.json ("ui.panel", "ui.button").

const BG := Color("0b1219")
const PANEL := Color("0f1c24")
const PANEL_2 := Color("142832")
const PETROL := Color("1f8a8a")
const PETROL_D := Color("173b45")
const AMBER := Color("e8a33d")
const TEXT := Color("e6f2f2")
const MUTED := Color("8fa3ad")
const OK := Color("5fae6e")
const WARN := Color("e8a33d")
const DANGER := Color("d25b4c")
const WATER := Color("4fa3d9")
const FOOD := Color("7cc46a")

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var panel := _box(PANEL, PETROL_D, 1, 6)
	panel.bg_color.a = 0.94
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := _box(PETROL_D, PETROL, 1, 4)
	btn.content_margin_left = 14
	btn.content_margin_right = 14
	btn.content_margin_top = 7
	btn.content_margin_bottom = 7
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = PETROL
	var pr := btn.duplicate() as StyleBoxFlat
	pr.bg_color = AMBER.darkened(0.3)
	pr.border_color = AMBER
	var dis := btn.duplicate() as StyleBoxFlat
	dis.bg_color = Color("1a2328")
	dis.border_color = Color("2a3840")
	var foc := btn.duplicate() as StyleBoxFlat
	foc.border_color = AMBER
	foc.set_border_width_all(2)
	for n: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(n, "Button", {"normal": btn, "hover": hov, "pressed": pr, "disabled": dis, "focus": foc}[n])
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	var pb_bg := _box(Color("0a1418"), PETROL_D, 1, 3)
	var pb_fg := _box(PETROL, PETROL, 0, 3)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_color("font_color", "ProgressBar", TEXT)
	var tab_sel := _box(PETROL, PETROL, 1, 4)
	var tab_un := _box(PETROL_D, PETROL_D, 1, 4)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", panel)
	var tip := _box(Color("0b1219"), AMBER, 1, 4)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	var line := _box(Color("0a1418"), PETROL_D, 1, 3)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("panel", "PopupMenu", panel)
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func label(text: String, size: int = 18, color: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String) -> Label:
	var l := label(text.to_upper(), 15, PETROL.lightened(0.35))
	return l


static func heading(text: String) -> Label:
	return label(text, 26, TEXT)


static func button(text: String, cb: Callable = Callable(), tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_ALL
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func() -> void: AudioService.ui("ui_click"))
	b.mouse_entered.connect(func() -> void: AudioService.ui("ui_hover"))
	return b


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.theme = theme()
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func rich(bbcode: String, fit: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = bbcode
	r.fit_content = fit
	r.scroll_active = not fit
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_color_override("default_color", TEXT)
	return r


static func bar(value: float, max_v: float, fill: Color = PETROL, h: int = 14) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max_v
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(80, h)
	var fg := _box(fill, fill, 0, 3)
	p.add_theme_stylebox_override("fill", fg)
	return p


static func status_icon(kind: String) -> String:
	return {"ok": "●", "warning": "▲", "critical": "■", "info": "◆", "locked": "✕"}.get(kind, "•")


static func status_color(kind: String) -> Color:
	return {"ok": OK, "warning": WARN, "critical": DANGER, "info": PETROL.lightened(0.3), "locked": MUTED}.get(kind, TEXT)


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func clear(n: Node) -> void:
	for c: Node in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func fmt(v: float, decimals: int = 0) -> String:
	if decimals == 0:
		return str(int(roundf(v)))
	return ("%." + str(decimals) + "f") % v


static func thousands(n: int) -> String:
	return Loc.group(n)
