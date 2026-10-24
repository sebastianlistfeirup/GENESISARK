class_name PauseMenu
extends CanvasLayer
## Esc menu, reachable from all gameplay (bible p.26): resume, save/load slots
## (with backup recovery), settings, main menu, quit. Pauses the tree.

var _panel: PanelContainer
var _body: VBoxContainer
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var settings: SettingsPanel
var dim: ColorRect


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = UiKit.panel(Vector2(560, 0))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_body = UiKit.vbox(10)
	_panel.add_child(_body)
	add_child(_panel)
	settings = SettingsPanel.new()
	settings.closed.connect(_main)
	add_child(settings)
	visible = false


func open() -> void:
	_prev_mouse = Input.mouse_mode
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main()
	UiKit.fade_in(dim, 0.22)
	UiKit.fade_in(_panel)


func close() -> void:
	visible = false
	settings.visible = false
	get_tree().paused = false
	Input.mouse_mode = _prev_mouse


## Menu entry in the main-menu style (lit plate, amber tab, glyph).
func _entry(text: String, icon_slot: String, cb: Callable) -> Button:
	var b := UiKit.button(text, cb)
	UiKit.with_icon(b, icon_slot, 20)
	UiKit.style_menu_button(b, true, 19, 44)
	return b


func _head(text: String) -> void:
	var sub := ""
	if GameSession.has_game():
		var o := GameSession.sim.objectives.current(GameSession.state)
		sub = "%s: %s" % [Loc.t("Objectives"), str(o.get("title", ""))] if not o.is_empty() else ""
	_body.add_child(UiKit.header_block(text, sub, "ui.icon_pause"))


func _main() -> void:
	_panel.visible = true
	UiKit.clear(_body)
	_head(Loc.t("Pause"))
	var first := _entry(Loc.t("Continue"), "ui.icon_play", close)
	_body.add_child(first)
	_body.add_child(_entry(Loc.t("Save game"), "ui.icon_save", _save_menu))
	_body.add_child(_entry(Loc.t("Load game"), "ui.icon_load", _load_menu))
	_body.add_child(_entry(Loc.t("Settings"), "ui.icon_settings", open_settings))
	_body.add_child(_entry(Loc.t("Main menu"), "ui.icon_menu", func() -> void:
		GameSession.autosave()
		close()
		AppFlow.goto("menu")))
	_body.add_child(_entry(Loc.t("Quit game"), "ui.icon_quit", func() -> void:
		GameSession.autosave()
		get_tree().quit()))
	first.grab_focus.call_deferred()


## Settings replace the pause panel (never drawn through it).
func open_settings() -> void:
	_panel.visible = false
	settings.open()


func _save_menu() -> void:
	UiKit.clear(_body)
	_body.add_child(UiKit.header_block(Loc.t("Save game"), "", "ui.icon_save"))
	var first: Button
	for slot: String in ["manual_1", "manual_2", "manual_3"]:
		var sm := SaveService.summary(slot)
		var txt := "%s — %s" % [Loc.t(str(SaveService.SLOT_LABELS[slot])), _describe(sm)]
		var b := _entry(txt, "ui.icon_save", func() -> void:
			var r := GameSession.save_to(slot)
			_status(Loc.t("Saved to %s.") % Loc.t(str(SaveService.SLOT_LABELS[slot])) if r["ok"] else Loc.t("Save failed: ") + str(r["error"]), bool(r["ok"])))
		_body.add_child(b)
		if first == null:
			first = b
	_body.add_child(_entry(Loc.t("Back"), "ui.icon_back", _main))
	first.grab_focus.call_deferred()


func _load_menu() -> void:
	UiKit.clear(_body)
	_body.add_child(UiKit.header_block(Loc.t("Load game"), "", "ui.icon_load"))
	for slot: String in SaveService.SLOTS:
		if not SaveService.store.exists(slot):
			continue
		var sm := SaveService.summary(slot)
		_body.add_child(_entry("%s — %s" % [Loc.t(str(SaveService.SLOT_LABELS[slot])), _describe(sm)], "ui.icon_load", func() -> void: _load(slot, false)))
	var back := _entry(Loc.t("Back"), "ui.icon_back", _main)
	_body.add_child(back)
	(_body.get_child(1) as Control).grab_focus.call_deferred()


func _load(slot: String, backup: bool) -> void:
	var r := GameSession.load_from(slot, backup)
	if r["ok"]:
		close()
		AppFlow.continue_game()
		return
	UiKit.clear(_body)
	_body.add_child(UiKit.header_block(Loc.t("Could not load"), "", "ui.icon_warning"))
	_body.add_child(UiKit.label(str(r["error"]), 17, UiKit.WARN, true))
	if r["backup_available"] and not backup:
		_body.add_child(_entry(Loc.t("Load latest valid backup"), "ui.icon_load", func() -> void: _load(slot, true)))
	var back := _entry(Loc.t("Back"), "ui.icon_back", _main)
	_body.add_child(back)
	back.grab_focus.call_deferred()


func _status(text: String, ok: bool = true) -> void:
	_main()
	var row := UiKit.hbox(8)
	row.add_child(UiKit.status_glyph("ok" if ok else "warning", 18))
	row.add_child(UiKit.label(text, 16, UiKit.MUTED.lightened(0.2), true))
	_body.add_child(row)


static func _describe(sm: Dictionary) -> String:
	if sm.is_empty():
		return Loc.t("empty")
	var phase := str(sm.get("phase", ""))
	var where := Loc.t("Voyage") if phase in ["ARK", "VOYAGE"] else Loc.t("Colony day %d") % int(sm.get("colony_day", 0))
	return "%s · %s" % [where, str(sm.get("saved_at", "")).replace("T", " ").substr(0, 16)]


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		if settings.visible:
			settings.close()
		else:
			close()
		get_viewport().set_input_as_handled()
