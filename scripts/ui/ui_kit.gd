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
	t.default_font = body_font()
	# Panels: deep navy glass, a hairline petrol border, soft drop shadow. The
	# content margins are part of the 1280x720 @1.5 fit budget (GA-29): keep them.
	var panel := _box(PANEL, Color(PETROL, 0.42), 1, 8)
	panel.bg_color.a = 0.93
	panel.border_width_top = 2  # a brighter lip on top reads as "glass edge"
	panel.shadow_color = Color(0, 0.01, 0.03, 0.45)
	panel.shadow_size = 10
	panel.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# Large overlays (dialogs, settings, pause, journal) take the Synty frame
	# when the packs are installed; small HUD chips stay flat for legibility.
	t.add_type("PanelLarge")
	t.set_type_variation("PanelLarge", "PanelContainer")
	var large: StyleBox = SyntySkin.box("SPR_SciFiMenus_Frame_Box_Large_01", Color(PANEL.darkened(0.2), 0.95), Color(0.95, 1.0, 1.0), 0.2,
		Vector4(340, 340, 340, 340), Vector4(26, 24, 26, 22), Vector4(40, 40, 40, 40))
	t.set_stylebox("panel", "PanelLarge", large if large else panel)
	# Buttons: one shape, five states. Focus is drawn ON TOP of the current
	# state (Godot 4), so it is an outline only: amber, 2 px, outside the
	# button, never hidden by hover or pressed (bible p.26).
	var btn: StyleBox = _box(PETROL_D.darkened(0.15), PETROL.darkened(0.2), 1, 6)
	btn.content_margin_left = 14
	btn.content_margin_right = 14
	btn.content_margin_top = 7
	btn.content_margin_bottom = 7
	(btn as StyleBoxFlat).border_width_bottom = 2
	var hov_f := btn.duplicate() as StyleBoxFlat
	hov_f.bg_color = PETROL.darkened(0.12)
	hov_f.border_color = PETROL.lightened(0.35)
	var pr_f := btn.duplicate() as StyleBoxFlat
	pr_f.bg_color = AMBER.darkened(0.45)
	pr_f.border_color = AMBER
	pr_f.border_width_bottom = 1
	pr_f.border_width_top = 2
	var dis_f := btn.duplicate() as StyleBoxFlat
	dis_f.bg_color = Color("141d22")
	dis_f.border_color = Color("26343b")
	var hov: StyleBox = hov_f
	var pr: StyleBox = pr_f
	var dis: StyleBox = dis_f
	# Synty skin: one rounded-octagon frame for every state, the background
	# tinted per state, the steel frame tinted cool/amber/dim. Content margins
	# equal the flat ones, so no layout changes with or without the packs.
	var steel := Color(0.78, 0.9, 0.95)
	var sk_slice := Vector4(90, 112, 90, 112)
	var sk_content := Vector4(14, 7, 14, 7)
	var sk_btn: StyleBox = SyntySkin.box("SPR_SciFiMenus_Button_Frame_03", PETROL_D.darkened(0.25), steel, 0.13, sk_slice, sk_content)
	if sk_btn:
		btn = sk_btn
		hov = SyntySkin.box("SPR_SciFiMenus_Button_Frame_03", PETROL.darkened(0.1), Color(0.95, 1.0, 1.0), 0.13, sk_slice, sk_content)
		pr = SyntySkin.box("SPR_SciFiMenus_Button_Frame_03", AMBER.darkened(0.4), AMBER.lightened(0.25), 0.13, sk_slice, sk_content)
		dis = SyntySkin.box("SPR_SciFiMenus_Button_Frame_03", Color("141d22"), Color(0.4, 0.45, 0.48), 0.13, sk_slice, sk_content)
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = AMBER
	foc.set_border_width_all(2)
	foc.set_corner_radius_all(8)
	foc.set_expand_margin_all(3)
	for cls: String in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hov)
		t.set_stylebox("pressed", cls, pr)
		t.set_stylebox("hover_pressed", cls, pr)
		t.set_stylebox("disabled", cls, dis)
		t.set_stylebox("focus", cls, foc)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color("fff4e0"))
		t.set_color("font_hover_pressed_color", cls, Color("fff4e0"))
		t.set_color("font_disabled_color", cls, MUTED.darkened(0.25))
	# Toggles (settings): flat row, amber outline when focused.
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 6
	flat.content_margin_right = 6
	flat.content_margin_top = 4
	flat.content_margin_bottom = 4
	var flat_hov := _box(Color(PETROL, 0.14), Color(0, 0, 0, 0), 0, 6)
	flat_hov.content_margin_left = 6
	flat_hov.content_margin_right = 6
	flat_hov.content_margin_top = 4
	flat_hov.content_margin_bottom = 4
	for cls: String in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cls, flat)
		t.set_stylebox("pressed", cls, flat)
		t.set_stylebox("hover", cls, flat_hov)
		t.set_stylebox("hover_pressed", cls, flat_hov)
		t.set_stylebox("disabled", cls, flat)
		t.set_stylebox("focus", cls, foc)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
	for state: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		t.set_icon(state, "CheckButton", _toggle_icon(state.begins_with("checked"), state.ends_with("disabled")))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	# Bars, sliders, scrollbars share the petrol track.
	var pb_bg := _box(Color("0a1418"), PETROL_D, 1, 4)
	var pb_fg := _box(PETROL, PETROL, 0, 4)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_color("font_color", "ProgressBar", TEXT)
	var track := _box(Color("0a1418"), PETROL_D, 1, 4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var track_fill := _box(PETROL, PETROL, 0, 4)
	track_fill.content_margin_top = 3
	track_fill.content_margin_bottom = 3
	var track_hi := track_fill.duplicate() as StyleBoxFlat
	track_hi.bg_color = PETROL.lightened(0.25)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_hi)
	t.set_stylebox("focus", "HSlider", foc)
	var sb_bg := _box(Color(0.02, 0.05, 0.07, 0.6), Color(0, 0, 0, 0), 0, 4)
	sb_bg.set_content_margin_all(3)
	var sb_grab := _box(PETROL_D.lightened(0.15), Color(0, 0, 0, 0), 0, 4)
	var sb_grab_h := _box(PETROL, Color(0, 0, 0, 0), 0, 4)
	for cls: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, sb_bg)
		t.set_stylebox("grabber", cls, sb_grab)
		t.set_stylebox("grabber_highlight", cls, sb_grab_h)
		t.set_stylebox("grabber_pressed", cls, sb_grab_h)
	var tab_sel := _box(PETROL.darkened(0.1), PETROL.lightened(0.3), 1, 6)
	var tab_un := _box(PETROL_D.darkened(0.15), PETROL_D, 1, 6)
	var tab_hov := _box(PETROL_D, PETROL, 1, 6)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_stylebox("tab_focus", "TabContainer", foc)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	var tip := _box(Color("0b1219"), AMBER, 1, 6)
	tip.shadow_color = Color(0, 0, 0, 0.4)
	tip.shadow_size = 6
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	var line := _box(Color("0a1418"), PETROL_D, 1, 4)
	var line_f := line.duplicate() as StyleBoxFlat
	line_f.border_color = AMBER
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", line_f)
	t.set_stylebox("panel", "PopupMenu", panel)
	var sep := StyleBoxLine.new()
	sep.color = Color(PETROL, 0.35)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	_theme = t
	return t


## Switch icon drawn in code (no texture files): petrol track + white knob when
## on, outlined dark track + grey knob when off. Shape AND position differ, so
## the state never depends on colour alone (bible p.26).
static func _toggle_icon(on: bool, disabled: bool) -> ImageTexture:
	var w := 46
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := PETROL if on else Color("0a1418")
	var edge := PETROL.lightened(0.3) if on else MUTED.darkened(0.2)
	var knob := Color.WHITE if on else MUTED
	if disabled:
		track = track.darkened(0.4)
		edge = edge.darkened(0.5)
		knob = knob.darkened(0.5)
	var r := h * 0.5 - 1.0
	var kx := (w - h * 0.5) if on else h * 0.5
	for y: int in h:
		for x: int in w:
			var px := Vector2(x + 0.5, y + 0.5)
			# Signed distance to the pill (capsule between the two end centres).
			var cx := clampf(px.x, h * 0.5, w - h * 0.5)
			var d_pill := px.distance_to(Vector2(cx, h * 0.5)) - r
			var d_knob := px.distance_to(Vector2(kx, h * 0.5)) - (r - 3.5)
			var c := Color(0, 0, 0, 0)
			var a_pill := clampf(0.5 - d_pill, 0.0, 1.0)
			if a_pill > 0.0:
				var a_edge := clampf(0.5 - absf(d_pill + 0.75), 0.0, 1.0)
				c = track.lerp(edge, a_edge)
				c.a = a_pill
			var a_knob := clampf(0.5 - d_knob, 0.0, 1.0)
			if a_knob > 0.0:
				c = c.lerp(knob, a_knob)
				c.a = maxf(c.a, a_knob)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


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
	l.add_theme_font_override("font", font_variant(0.0, 1))
	return l


static func heading(text: String) -> Label:
	var l := label(text, 26, TEXT)
	l.add_theme_font_override("font", font_variant(0.0, 0))
	return l


static var _fonts: Dictionary = {}
static var _body: Font
static var _bold: Font

const FONT_REGULAR := "res://art/fonts/exo2/Exo2.0-Regular.otf"
const FONT_SEMIBOLD := "res://art/fonts/exo2/Exo2.0-SemiBold.otf"


## Exo 2 (SIL OFL, shipped in art/fonts) with the engine font as glyph
## fallback for symbols it lacks (status shapes, arrows, ∞).
static func body_font() -> Font:
	if _body == null:
		# A touch of weight: Exo 2 Regular is thin over bright 3D scenes.
		var fv := FontVariation.new()
		fv.base_font = _load_font(FONT_REGULAR)
		fv.variation_embolden = 0.2
		_body = fv
	return _body


static func bold_font() -> Font:
	if _bold == null:
		_bold = _load_font(FONT_SEMIBOLD)
	return _bold


static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var f := load(path) as FontFile
	if f == null:
		return ThemeDB.fallback_font
	var fb: Array[Font] = [ThemeDB.fallback_font]
	f.fallbacks = fb
	return f


## The default font with a little weight/tracking: headings and section titles
## get hierarchy without shipping a font file (D-035).
static func font_variant(embolden: float, spacing: int) -> FontVariation:
	var key := "%s/%d" % [embolden, spacing]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = bold_font()
		fv.variation_embolden = embolden
		fv.spacing_glyph = spacing
		_fonts[key] = fv
	return _fonts[key]


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


## True when the player asked for reduced motion: no fades, slides or drift.
static func calm() -> bool:
	return bool(SettingsService.get_value("reduced_motion", false))


## Fades a control (or any CanvasItem) in from transparent. Instant with
## reduced motion. Only modulate changes, so layout and fit checks are unaffected.
static func fade_in(item: CanvasItem, seconds: float = 0.18) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return
	if calm():
		item.modulate.a = 1.0
		return
	item.modulate.a = 0.0
	var tw := item.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(item, "modulate:a", 1.0, seconds)


## Large left-aligned menu entry (main menu): translucent plate with an accent
## bar on the left that lights amber and slides the label in on hover/focus.
## The shared amber focus outline still draws on top (bible p.26).
static func style_menu_button(b: Button, animate: bool = true) -> void:
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 21)
	var set := _menu_styles()
	var base: StyleBox = (set["base"] as StyleBox).duplicate()
	var lit: StyleBox = (set["lit"] as StyleBox).duplicate()
	var pr: StyleBox = (set["pr"] as StyleBox).duplicate()
	var dis: StyleBox = (set["dis"] as StyleBox).duplicate()
	var rest := base.content_margin_left
	var slid := rest + 12.0
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", dis)
	# Lit when hovered OR focused (pad/keyboard), so both inputs get the same cue.
	var light := func(on: bool) -> void:
		var target := slid if on else rest
		b.add_theme_stylebox_override("normal", lit if on else base)
		if animate and not calm() and b.is_inside_tree():
			var tw := b.create_tween().set_parallel(true)
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			for sb: StyleBox in [lit, pr]:
				tw.tween_property(sb, "content_margin_left", target, 0.14)
		else:
			lit.content_margin_left = target
			pr.content_margin_left = target
	b.focus_entered.connect(func() -> void: light.call(true))
	b.focus_exited.connect(func() -> void: light.call(b.is_hovered()))
	b.mouse_entered.connect(func() -> void: light.call(true))
	b.mouse_exited.connect(func() -> void: light.call(b.has_focus()))


static var _menu_set: Dictionary = {}


## Main-menu entry styles, built once: the Synty amber-capped bar when the
## packs are installed, otherwise a translucent plate with a left accent bar.
static func _menu_styles() -> Dictionary:
	if not _menu_set.is_empty():
		return _menu_set
	var frame := "SPR_SciFiMenus_Button_Frame_01"
	var slice := Vector4(185, 64, 185, 64)
	var content := Vector4(44, 8, 44, 8)
	var sk: StyleBox = SyntySkin.box(frame, Color(PANEL, 0.82), Color(0.8, 0.9, 0.95), 0.2, slice, content)
	if sk:
		_menu_set = {
			"base": sk,
			"lit": SyntySkin.box(frame, Color(PETROL.darkened(0.15), 0.95), Color.WHITE, 0.2, slice, content),
			"pr": SyntySkin.box(frame, Color(AMBER.darkened(0.45), 0.95), Color(1.0, 0.9, 0.75), 0.2, slice, content),
			"dis": SyntySkin.box(frame, Color(PANEL, 0.5), Color(0.45, 0.5, 0.52), 0.2, slice, content),
		}
		return _menu_set
	var base := StyleBoxFlat.new()
	base.bg_color = Color(PANEL, 0.55)
	base.border_color = Color(PETROL, 0.75)
	base.border_width_left = 3
	base.set_corner_radius_all(4)
	base.content_margin_left = 22
	base.content_margin_right = 22
	base.content_margin_top = 8
	base.content_margin_bottom = 8
	var lit := base.duplicate() as StyleBoxFlat
	lit.bg_color = Color(PETROL.darkened(0.25), 0.85)
	lit.border_color = AMBER
	lit.border_width_left = 5
	var pr := lit.duplicate() as StyleBoxFlat
	pr.bg_color = Color(AMBER.darkened(0.5), 0.9)
	var dis := base.duplicate() as StyleBoxFlat
	dis.bg_color = Color(PANEL, 0.35)
	dis.border_color = Color(MUTED, 0.3)
	_menu_set = {"base": base, "lit": lit, "pr": pr, "dis": dis}
	return _menu_set


## Drops cached styles so the next theme() call rebuilds (tests, pack toggles).
static func reset_theme() -> void:
	_theme = null
	_menu_set = {}


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.theme = theme()
	if min_size.x >= 500.0:
		p.theme_type_variation = &"PanelLarge"
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


## Shrinks a modal CanvasLayer (about the screen centre) until `panel` fits the
## visible area with a margin. Large UI scales on small windows (e.g. 1.5 at
## 1280x720) then still show the whole panel instead of clipping its header
## and buttons; at normal sizes the scale stays 1.
static func fit_layer(layer: CanvasLayer, panel: Control, margin: float = 12.0) -> void:
	var vp := layer.get_viewport()
	if vp == null or not is_instance_valid(panel):
		return
	var vis := vp.get_visible_rect().size
	var need := panel.get_combined_minimum_size() + Vector2(margin, margin) * 2.0
	var s := minf(1.0, minf(vis.x / maxf(need.x, 1.0), vis.y / maxf(need.y, 1.0)))
	layer.scale = Vector2(s, s)
	layer.offset = vis * (1.0 - s) * 0.5


## Status text with its symbol in front: colour is never the only signal.
static func status_text(kind: String, text: String) -> String:
	return "%s %s" % [status_icon(kind), text]


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
