class_name SettingsPanel
extends CanvasLayer
## Settings: audio groups, UI scale (tested at 1280x720 and 1920x1080),
## subtitles, reduced motion, mouse, full key remapping (bible p.26).
## Holo console (D-059): four tabs with glyphs (Audio / Display /
## Accessibility / Controls), every setting one glass row with a badge, a
## caption and a hint; sliders are big with a live value chip, toggles are
## holo switches (ON/OFF word + knob position), key bindings are key caps.
## Live previews: the audio mixer's levels and a subtitle line at the chosen
## size. LB/RB (or clicking a tab) switch tabs; Esc / B closes.

signal closed

const TABS := ["audio", "display", "access", "controls"]
const W := 1060.0

var _panel: PanelContainer
var _body: VBoxContainer
var _frame: HoloFrame
var _waiting_action := ""
var _tab := 0
var _tabs: TabContainer
var _focus_key := ""
var _reset_btn: Button


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.04, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_left = -4096
	dim.offset_top = -4096
	dim.offset_right = 4096
	dim.offset_bottom = 4096
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = UiKit.panel(Vector2(W, 0))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_body = UiKit.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_body)
	_frame = HoloFrame.attach(_panel)
	add_child(_panel)
	visible = false
	SettingsService.changed.connect(func() -> void:
		if visible:
			UiKit.fit_layer(self, _panel))


func open() -> void:
	visible = true
	_focus_key = ""
	_build()
	UiKit.fit_layer(self, _panel)
	UiKit.fit_layer.call_deferred(self, _panel)
	HoloAnim.boot_in(_panel)
	_frame.boot()


## Opens a tab by index (0 audio, 1 display, 2 accessibility, 3 controls).
func show_tab(t: int) -> void:
	_tab = clampi(t, 0, 3)
	if is_instance_valid(_tabs):
		_tabs.current_tab = _tab
		_restore_focus.call_deferred()


func close() -> void:
	if visible:
		HoloAnim.power_off(self, Rect2(offset + _panel.position * scale, _panel.size * scale), layer + 1)
	visible = false
	_waiting_action = ""
	closed.emit()


## Rebuilds everything (language, quality, a rebinding) and puts focus back
## on the control that had it, on the same tab.
func _build() -> void:
	if is_instance_valid(_tabs):
		_tab = _tabs.current_tab
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo and fo.has_meta("fkey") and _focus_key.is_empty():
		_focus_key = str(fo.get_meta("fkey"))
	UiKit.clear(_body)
	_body.add_child(UiKit.header_block(Loc.t("Settings"), Loc.t("Audio, display, accessibility and controls. Changes apply at once."), "ui.icon_settings"))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(W - 40.0, 500)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_tabs)
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_display_tab())
	_tabs.add_child(_access_tab())
	_tabs.add_child(_controls_tab())
	var titles := [Loc.t("Audio"), Loc.t("Display"), Loc.t("Accessibility"), Loc.t("Controls")]
	var icons := ["ui.icon_audio", "ui.icon_display", "ui.icon_access", "ui.icon_controls"]
	for i: int in 4:
		_tabs.set_tab_title(i, "  " + str(titles[i]).to_upper())
		var tex := SyntySkin.icon(str(icons[i]), 40)
		if tex:
			_tabs.set_tab_icon(i, tex)
			_tabs.set_tab_icon_max_width(i, 20)
	_tabs.current_tab = clampi(_tab, 0, 3)
	_tabs.tab_changed.connect(func(t: int) -> void:
		_tab = t
		_reset_btn.visible = t == 3
		AudioService.ui("ui_click")
		HoloAnim.stagger(_tab_rows(t), 0.03, 0.0, 0.16))
	var foot := UiKit.hbox(10)
	foot.add_child(_hint("LB", "Q", Loc.t("Previous tab")))
	foot.add_child(_hint("RB", "E", Loc.t("Next tab")))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_reset_btn = UiKit.with_icon(UiKit.button(Loc.t("Reset keys"), func() -> void:
		SettingsService.reset_bindings()
		_build()), "ui.icon_time", 18)
	_reset_btn.set_meta("fkey", "reset")
	_reset_btn.visible = _tabs.current_tab == 3
	foot.add_child(_reset_btn)
	var cb := UiKit.with_icon(UiKit.button(Loc.t("Close"), close), "ui.icon_close", 16)
	cb.set_meta("fkey", "close")
	foot.add_child(cb)
	_body.add_child(UiKit.trim())
	_body.add_child(foot)
	_restore_focus.call_deferred()


func _restore_focus() -> void:
	if not visible:
		return
	var target: Control = null
	if not _focus_key.is_empty():
		for c: Node in _panel.find_children("*", "Control", true, false):
			if c.has_meta("fkey") and str(c.get_meta("fkey")) == _focus_key and (c as Control).is_visible_in_tree():
				target = c
				break
	_focus_key = ""
	if target == null:
		var rows := _tab_rows(_tabs.current_tab)
		for r: Node in rows.get_children() if rows else []:
			if r.has_meta("focus") and (r.get_meta("focus") as Control).is_visible_in_tree():
				target = r.get_meta("focus")
				break
	if target:
		target.grab_focus()


## The rows container of a tab (for stagger and first focus).
func _tab_rows(t: int) -> Node:
	if not is_instance_valid(_tabs) or t >= _tabs.get_child_count():
		return null
	return _tabs.get_child(t).find_child("Rows", true, false)


## A tab page: a scrolling column of rows, with an optional preview column on the right.
func _page(page_name: String, preview: Control = null) -> Array:
	var h := UiKit.hbox(16)
	h.name = page_name
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(8)
	v.name = "Rows"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	s.add_child(m)
	h.add_child(s)
	if preview:
		h.add_child(preview)
	return [h, v]


func _tag(r: Control, key: String) -> Control:
	(r.get_meta("focus") as Control).set_meta("fkey", key)
	return r


func _audio_tab() -> Control:
	var pg := _page("Audio", _mixer_preview())
	var v: VBoxContainer = pg[1]
	v.add_child(UiKit.section(Loc.t("Volume"), "ui.icon_audio"))
	var rows := [["master_volume", Loc.t("Master"), Loc.t("Everything at once."), "ui.icon_audio"],
		["music_volume", Loc.t("Music"), Loc.t("The score."), "ui.icon_music"],
		["sfx_volume", Loc.t("Effects"), Loc.t("Machines, steps, the Ark."), "ui.icon_power"],
		["ambience_volume", Loc.t("Ambience"), Loc.t("Wind, rooms, the colony."), "ui.icon_wind"],
		["voice_volume", Loc.t("Voices"), Loc.t("ARK, the captain and the colonists. The score and the beds dip under every line."), "ui.icon_population"],
		["ui_volume", Loc.t("Interface"), Loc.t("Clicks and notices."), "ui.icon_display"]]
	for r: Array in rows:
		v.add_child(_tag(_slider(str(r[0]), str(r[1]), str(r[2]), str(r[3]), 0.0, 1.0, 0.05, _pct), str(r[0])))
	return pg[0]


func _display_tab() -> Control:
	var pg := _page("Display")
	var v: VBoxContainer = pg[1]
	v.add_child(UiKit.section(Loc.t("Language"), "ui.icon_language"))
	var langs: Array = []
	for code: String in Loc.LANGUAGES.keys():
		langs.append([code, str(Loc.LANGUAGES[code])])
	v.add_child(_tag(HoloForm.choice_row("ui.icon_language", Loc.t("Language"), Loc.t("Text and subtitles."), langs, Loc.lang(), func(code: String) -> void:
		close()
		SettingsService.set_language(code)), "language"))
	v.add_child(UiKit.section(Loc.t("Picture"), "ui.icon_display"))
	var qn := Loc.t("(now: %s, from the next area)") % (Loc.t("Low") if Quality.low() else Loc.t("High"))
	v.add_child(_tag(HoloForm.choice_row("ui.icon_camera", Loc.t("Graphics quality"), qn,
		[["auto", Loc.t("Auto")], ["high", Loc.t("High")], ["low", Loc.t("Low")]], str(SettingsService.get_value("graphics_quality", "auto")), func(q: String) -> void:
			_focus_key = "quality"
			SettingsService.set_value("graphics_quality", q)
			_build()), "quality"))
	v.add_child(_tag(_slider("ui_scale", Loc.t("UI scale"), Loc.t("Tested from 1280x720 to 1920x1080."), "ui.icon_display", 0.75, 1.5, 0.05, _pct), "ui_scale"))
	v.add_child(_tag(_toggle("fullscreen", Loc.t("Fullscreen"), Loc.t("Use the whole screen."), "ui.icon_display"), "fullscreen"))
	return pg[0]


func _access_tab() -> Control:
	var preview := _subtitle_preview()
	var pg := _page("Accessibility")
	var v: VBoxContainer = pg[1]
	v.add_child(UiKit.section(Loc.t("Subtitles"), "ui.icon_journal"))
	v.add_child(_tag(_toggle("subtitles", Loc.t("Subtitles"), Loc.t("Spoken lines as text at the bottom."), "ui.icon_journal", func(on: bool) -> void: preview.modulate.a = 1.0 if on else 0.4), "subtitles"))
	v.add_child(_tag(_slider("subtitle_size", Loc.t("Subtitle size"), Loc.t("See the preview below."), "ui.icon_journal", 16, 34, 1, func(x: float) -> String: return "%d px" % int(x),
		func(x: float) -> void: (preview.get_meta("line") as Label).add_theme_font_size_override("font_size", int(x))), "subtitle_size"))
	v.add_child(preview)
	v.add_child(UiKit.section(Loc.t("Comfort"), "ui.icon_access"))
	v.add_child(_tag(_toggle("reduced_motion", Loc.t("Reduced motion (no fades/shaking)"), Loc.t("Panels, cameras and effects stay still."), "ui.icon_access"), "reduced_motion"))
	v.add_child(_tag(_toggle("camera_shake", Loc.t("Camera shake"), Loc.t("Impacts and landings shake the view."), "ui.icon_camera"), "camera_shake"))
	v.add_child(_tag(_toggle("realtime_descent", Loc.t("Real-time descent from orbit"), Loc.t("Watch the Ark come down, or cut to the ground."), "ui.icon_lander"), "realtime_descent"))
	return pg[0]


func _controls_tab() -> Control:
	var pg := _page("Controls")
	var v: VBoxContainer = pg[1]
	v.add_child(UiKit.section(Loc.t("Mouse"), "ui.icon_mouse"))
	v.add_child(_tag(_slider("mouse_sensitivity", Loc.t("Sensitivity"), Loc.t("How fast the view turns."), "ui.icon_mouse", 0.05, 1.0, 0.05, _pct), "mouse_sensitivity"))
	v.add_child(_tag(_toggle("invert_y", Loc.t("Invert vertical axis"), Loc.t("Mouse up looks down."), "ui.icon_mouse"), "invert_y"))
	if TouchControls.enabled:
		v.add_child(_tag(_slider("touch_look_sensitivity", Loc.t("Camera drag (touch)"), "", "ui.icon_mouse", 0.4, 2.0, 0.05, _pct), "touch_look"))
	v.add_child(UiKit.section(Loc.t("Keys"), "ui.icon_controls"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for action: String in SettingsService.ACTIONS.keys():
		var r := HoloForm.key_row(Loc.t(str(SettingsService.ACTION_LABELS.get(action, action))), SettingsService.binding_text(action), _waiting_action == action, func() -> void:
			_waiting_action = action
			_focus_key = "key:" + action
			_build())
		_tag(r, "key:" + action)
		grid.add_child(r)
	v.add_child(grid)
	# Rows in the grid still count for first focus and stagger.
	return pg[0]


func _pct(x: float) -> String:
	return "%d%%" % int(roundf(x * 100.0))


func _slider(key: String, caption: String, hint: String, icon_slot: String, lo: float, hi: float, step: float, fmt: Callable, extra: Callable = Callable()) -> Control:
	return HoloForm.slider_row(icon_slot, caption, hint, float(SettingsService.get_value(key, lo)), lo, hi, step, fmt, func(v: float) -> void:
		SettingsService.set_value(key, int(v) if step >= 1.0 else v)
		if extra.is_valid():
			extra.call(v))


func _toggle(key: String, caption: String, hint: String, icon_slot: String, extra: Callable = Callable()) -> Control:
	return HoloForm.switch_row(icon_slot, caption, hint, bool(SettingsService.get_value(key, false)), func(on: bool) -> void:
		SettingsService.set_value(key, on)
		if extra.is_valid():
			extra.call(on))


## Key hint: the pad glyph with a controller, else a key cap; then the word.
func _hint(pad_name: String, key: String, text: String) -> Control:
	var h := UiKit.hbox(6)
	h.add_child(UiKit.keycap(pad_name if SettingsService.using_pad else key, 13))
	h.add_child(UiKit.label(text, 14, UiKit.MUTED))
	return h


## Audio preview: one live level bar per channel (master x channel), bouncing
## gently like a mixer (still with reduced motion).
func _mixer_preview() -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.7)
	sb.border_color = Color(UiKit.PETROL.lerp(UiKit.MUTED, 0.5), 0.2)
	sb.set_border_width_all(1)
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(270, 0)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := UiKit.vbox(8)
	v.add_child(UiKit.section(Loc.t("Mixer"), "ui.icon_music"))
	var m := _Mixer.new()
	m.custom_minimum_size = Vector2(240, 250)
	m.names = [Loc.t("Master"), Loc.t("Music"), Loc.t("Effects"), Loc.t("Ambience"), Loc.t("Voices"), Loc.t("Interface")]
	v.add_child(m)
	v.add_child(UiKit.label(Loc.t("Levels follow the sliders: each channel is mixed under the master."), 13, UiKit.MUTED, true))
	p.add_child(v)
	return p


class _Mixer extends Control:
	const KEYS := ["master_volume", "music_volume", "sfx_volume", "ambience_volume", "voice_volume", "ui_volume"]
	var names: Array = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			if not UiKit.calm():
				_t += delta
			queue_redraw()

	func _draw() -> void:
		var n := KEYS.size()
		var gap := 10.0
		var bw := (size.x - gap * (n - 1)) / n
		var h := size.y - 22.0
		var master := float(SettingsService.get_value("master_volume", 1.0))
		var font := UiKit.display_variant(1)
		for i: int in n:
			var lvl := float(SettingsService.get_value(KEYS[i], 1.0)) * (1.0 if i == 0 else master)
			var bounce := 0.82 + 0.18 * (0.5 + 0.5 * sin(_t * (3.1 + i * 0.7) + i * 1.9)) * (0.6 + 0.4 * sin(_t * 1.3 + i))
			var shown := lvl * bounce
			var x := i * (bw + gap)
			var segs := 16
			var sh := h / segs
			for s: int in segs:
				var y := h - (s + 1) * sh
				var on := float(s) / segs < shown
				var c := UiKit.PETROL.lightened(0.25) if s < 11 else (UiKit.AMBER if s < 14 else UiKit.DANGER)
				draw_rect(Rect2(x, y + 1.0, bw, sh - 2.0), Color(c, 0.9) if on else Color(c, 0.08), true)
			# Set level marker (the slider value, not the bounce).
			var ly := h - lvl * h
			draw_line(Vector2(x - 2, ly), Vector2(x + bw + 2, ly), Color.WHITE, 2.0)
			var nm := str(names[i]).substr(0, 3).to_upper() if i < names.size() else ""
			var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(x + (bw - tw) * 0.5, size.y - 4.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.MUTED)


## Accessibility preview: a subtitle line as the HUD shows it, at the chosen size.
func _subtitle_preview() -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.01, 0.02, 0.8)
	sb.border_color = Color(UiKit.PETROL.lerp(UiKit.MUTED, 0.4), 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox(4)
	var cap := UiKit.label(Loc.t("PREVIEW"), 11, UiKit.AMBER)
	cap.add_theme_font_override("font", UiKit.display_variant(2))
	v.add_child(cap)
	var who := UiKit.label("CAPTAIN", 13, UiKit.PETROL.lightened(0.45))
	who.add_theme_font_override("font", UiKit.display_variant(1))
	v.add_child(who)
	var line := UiKit.label(Loc.t("You are the last human who can give humanity a future."), int(SettingsService.get_value("subtitle_size", 22)), UiKit.TEXT, true)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)
	p.add_child(v)
	p.set_meta("line", line)
	p.modulate.a = 1.0 if bool(SettingsService.get_value("subtitles", true)) else 0.4
	return p


func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty() or not visible:
		return
	var name := ""
	if event is InputEventKey and (event as InputEventKey).pressed:
		name = OS.get_keycode_string((event as InputEventKey).physical_keycode)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		name = "mouse:%d" % int((event as InputEventMouseButton).button_index)
	if name.is_empty():
		return
	SettingsService.rebind(_waiting_action, name)
	_focus_key = "key:" + _waiting_action
	_waiting_action = ""
	get_viewport().set_input_as_handled()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _waiting_action.is_empty():
		return
	var step := 0
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed:
		step = -1 if jb.button_index == JOY_BUTTON_LEFT_SHOULDER else (1 if jb.button_index == JOY_BUTTON_RIGHT_SHOULDER else 0)
	var kb := event as InputEventKey
	if kb and kb.pressed and not kb.echo and not (get_viewport().gui_get_focus_owner() is LineEdit):
		step = -1 if kb.physical_keycode == KEY_Q else (1 if kb.physical_keycode == KEY_E else 0)
	if step != 0 and is_instance_valid(_tabs):
		_tabs.current_tab = wrapi(_tabs.current_tab + step, 0, 4)
		_restore_focus.call_deferred()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
