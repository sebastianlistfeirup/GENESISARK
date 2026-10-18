class_name CreditsPanel
extends CanvasLayer
## Credits and licence notices (main menu). People, packs and tools come from
## data/credits/credits.json; Godot's MIT licence and third-party notices are read
## from the engine itself, so they always match the shipped binary.

signal closed

var _panel: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = UiKit.panel(Vector2(760, 640))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = UiKit.vbox(6)
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
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	UiKit.clear(_body)
	var close_btn := UiKit.button(Loc.t("Luk"), close)
	_body.add_child(UiKit.heading(Loc.t("Krediteringer")))
	for section: Dictionary in GameSession.content.credits:
		_body.add_child(UiKit.title(str(section.get("title", ""))))
		for e: Dictionary in DictUtil.get_arr(section, "entries"):
			var planned := str(e.get("status", "in_use")) == "planned"
			var row := UiKit.hbox(12)
			var role := UiKit.label(str(e.get("role", "")), 15, UiKit.MUTED, true)
			role.custom_minimum_size = Vector2(380, 0)
			role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(role)
			var who := UiKit.label(str(e.get("name", "")) + (Loc.t("  (planlagt)") if planned else ""), 15,
				UiKit.MUTED.darkened(0.2) if planned else UiKit.TEXT, true)
			who.custom_minimum_size = Vector2(300, 0)
			row.add_child(who)
			_body.add_child(row)
			if e.has("text"):
				_body.add_child(UiKit.label(str(e["text"]), 13, UiKit.MUTED, true))
	_body.add_child(UiKit.title(Loc.t("Licenser")))
	_body.add_child(UiKit.label(Loc.t("Spillet bruger Godot Engine, udgivet under MIT-licensen:"), 14, UiKit.MUTED, true))
	_body.add_child(_mono(Engine.get_license_text()))
	_body.add_child(UiKit.label(Loc.t("Tredjepartskomponenter i Godot Engine:"), 14, UiKit.MUTED, true))
	_body.add_child(_mono(_third_party_text()))
	_body.add_child(close_btn)
	close_btn.grab_focus.call_deferred()


static func _third_party_text() -> String:
	var lines: PackedStringArray = []
	for info: Dictionary in Engine.get_copyright_info():
		var holders: PackedStringArray = []
		for part: Dictionary in info.get("parts", []):
			for c: String in part.get("copyright", []):
				holders.append(c)
			lines.append("%s — %s (%s)" % [info.get("name", ""), "; ".join(holders.slice(0, 2)), part.get("license", "")])
			holders.clear()
	return "\n".join(lines)


static func _mono(text: String) -> Label:
	var l := UiKit.label(text, 11, UiKit.MUTED, true)
	l.custom_minimum_size = Vector2(700, 0)
	return l
