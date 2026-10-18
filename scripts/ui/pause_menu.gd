class_name PauseMenu
extends CanvasLayer
## Esc menu, reachable from all gameplay (bible p.26): resume, save/load slots
## (with backup recovery), settings, main menu, quit. Pauses the tree.

var _panel: PanelContainer
var _body: VBoxContainer
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var settings: SettingsPanel


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = UiKit.panel(Vector2(520, 0))
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


func close() -> void:
	visible = false
	settings.visible = false
	get_tree().paused = false
	Input.mouse_mode = _prev_mouse


func _main() -> void:
	_panel.visible = true
	UiKit.clear(_body)
	_body.add_child(UiKit.heading(Loc.t("Pause")))
	_body.add_child(UiKit.button(Loc.t("Continue"), close))
	_body.add_child(UiKit.button(Loc.t("Save game"), _save_menu))
	_body.add_child(UiKit.button(Loc.t("Load game"), _load_menu))
	_body.add_child(UiKit.button(Loc.t("Settings"), func() -> void:
		_panel.visible = false
		settings.open()))
	_body.add_child(UiKit.button(Loc.t("Main menu"), func() -> void:
		GameSession.autosave()
		close()
		AppFlow.goto("menu")))
	_body.add_child(UiKit.button(Loc.t("Quit game"), func() -> void:
		GameSession.autosave()
		get_tree().quit()))
	(_body.get_child(1) as Button).grab_focus.call_deferred()


func _save_menu() -> void:
	UiKit.clear(_body)
	_body.add_child(UiKit.heading(Loc.t("Save game")))
	for slot: String in ["manual_1", "manual_2", "manual_3"]:
		var sm := SaveService.summary(slot)
		var txt := "%s — %s" % [Loc.t(str(SaveService.SLOT_LABELS[slot])), _describe(sm)]
		_body.add_child(UiKit.button(txt, func() -> void:
			var r := GameSession.save_to(slot)
			_status(Loc.t("Saved to %s.") % Loc.t(str(SaveService.SLOT_LABELS[slot])) if r["ok"] else Loc.t("Save failed: ") + str(r["error"]))))
	_body.add_child(UiKit.button(Loc.t("Back"), _main))


func _load_menu() -> void:
	UiKit.clear(_body)
	_body.add_child(UiKit.heading(Loc.t("Load game")))
	for slot: String in SaveService.SLOTS:
		if not SaveService.store.exists(slot):
			continue
		var sm := SaveService.summary(slot)
		_body.add_child(UiKit.button("%s — %s" % [Loc.t(str(SaveService.SLOT_LABELS[slot])), _describe(sm)], func() -> void: _load(slot, false)))
	_body.add_child(UiKit.button(Loc.t("Back"), _main))


func _load(slot: String, backup: bool) -> void:
	var r := GameSession.load_from(slot, backup)
	if r["ok"]:
		close()
		AppFlow.continue_game()
		return
	UiKit.clear(_body)
	_body.add_child(UiKit.heading(Loc.t("Could not load")))
	_body.add_child(UiKit.label(str(r["error"]), 17, UiKit.WARN, true))
	if r["backup_available"] and not backup:
		_body.add_child(UiKit.button(Loc.t("Load latest valid backup"), func() -> void: _load(slot, true)))
	_body.add_child(UiKit.button(Loc.t("Back"), _main))


func _status(text: String) -> void:
	_main()
	_body.add_child(UiKit.label(text, 16, UiKit.MUTED, true))


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
