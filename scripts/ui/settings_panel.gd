class_name SettingsPanel
extends CanvasLayer
## Settings: audio groups, UI scale (tested at 1280x720 and 1920x1080),
## subtitles, reduced motion, mouse, full key remapping (bible p.26).

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _waiting_action := ""


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = UiKit.panel(Vector2(720, 640))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = UiKit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_panel.add_child(scroll)
	add_child(_panel)
	visible = false


func open() -> void:
	visible = true
	_build()


func close() -> void:
	visible = false
	_waiting_action = ""
	closed.emit()


func _build() -> void:
	UiKit.clear(_body)
	_body.add_child(UiKit.heading(Loc.t("Indstillinger")))
	var lang_row := UiKit.hbox(8)
	var ll := UiKit.label(Loc.t("Sprog"), 16)
	ll.custom_minimum_size = Vector2(300, 0)
	lang_row.add_child(ll)
	for code: String in Loc.LANGUAGES.keys():
		var lb := UiKit.button(str(Loc.LANGUAGES[code]), func() -> void:
			close()
			SettingsService.set_language(code))
		lb.disabled = code == Loc.lang()
		lang_row.add_child(lb)
	_body.add_child(lang_row)
	_body.add_child(UiKit.title(Loc.t("Lyd")))
	for k: String in ["master_volume", "music_volume", "sfx_volume", "ambience_volume", "ui_volume"]:
		_slider(k, {"master_volume": Loc.t("Samlet"), "music_volume": Loc.t("Musik"), "sfx_volume": Loc.t("Effekter"), "ambience_volume": Loc.t("Stemning"), "ui_volume": Loc.t("Brugerflade")}[k], 0.0, 1.0, 0.05)
	_body.add_child(UiKit.title(Loc.t("Visning og tilgængelighed")))
	_slider("ui_scale", Loc.t("UI-skalering"), 0.75, 1.5, 0.05)
	_slider("subtitle_size", Loc.t("Undertekststørrelse"), 16, 34, 1)
	_toggle("subtitles", Loc.t("Undertekster"))
	_toggle("reduced_motion", Loc.t("Reduceret bevægelse (ingen fades/rystelser)"))
	_toggle("camera_shake", Loc.t("Kamerarystelser"))
	_toggle("fullscreen", Loc.t("Fuld skærm"))
	_body.add_child(UiKit.title(Loc.t("Mus")))
	_slider("mouse_sensitivity", Loc.t("Følsomhed"), 0.05, 1.0, 0.05)
	_toggle("invert_y", Loc.t("Invertér lodret akse"))
	_body.add_child(UiKit.title(Loc.t("Taster")))
	for action: String in SettingsService.ACTIONS.keys():
		var h := UiKit.hbox(8)
		var l := UiKit.label(Loc.t(str(SettingsService.ACTION_LABELS.get(action, action))), 16)
		l.custom_minimum_size = Vector2(300, 0)
		h.add_child(l)
		var b := UiKit.button(Loc.t("Tryk en tast...") if _waiting_action == action else SettingsService.binding_text(action))
		b.custom_minimum_size = Vector2(240, 0)
		b.pressed.connect(func() -> void:
			_waiting_action = action
			_build())
		h.add_child(b)
		_body.add_child(h)
	_body.add_child(UiKit.button(Loc.t("Nulstil taster"), func() -> void:
		SettingsService.reset_bindings()
		_build()))
	_body.add_child(UiKit.button(Loc.t("Luk"), close))


func _slider(key: String, label_text: String, lo: float, hi: float, step: float) -> void:
	var h := UiKit.hbox(8)
	var l := UiKit.label(label_text, 16)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(SettingsService.get_value(key, lo))
	s.custom_minimum_size = Vector2(260, 24)
	var val := UiKit.label(str(s.value), 16, UiKit.MUTED)
	s.value_changed.connect(func(v: float) -> void:
		val.text = str(snappedf(v, step))
		SettingsService.set_value(key, int(v) if step >= 1.0 else v))
	h.add_child(s)
	h.add_child(val)
	_body.add_child(h)


func _toggle(key: String, label_text: String) -> void:
	var c := CheckButton.new()
	c.text = label_text
	c.button_pressed = bool(SettingsService.get_value(key, false))
	c.toggled.connect(func(on: bool) -> void: SettingsService.set_value(key, on))
	_body.add_child(c)


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
	_waiting_action = ""
	get_viewport().set_input_as_handled()
	_build()
