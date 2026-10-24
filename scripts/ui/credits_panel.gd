class_name CreditsPanel
extends CanvasLayer
## Credits and licence notices (main menu). People, packs and tools come from
## data/credits/credits.json; Godot's MIT licence and third-party notices are read
## from the engine itself, so they always match the shipped binary.
## Holo console (D-059): HoloFrame + boot, each credits section a card (role
## muted, name bright, planned entries dimmed with a PLANNED chip), the licences
## in their own card at the end; the Close button stays in the header.

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _head: VBoxContainer
var _frame: HoloFrame


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = UiKit.panel(Vector2(900, 0))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var outer := UiKit.vbox(10)
	_head = UiKit.vbox(0)
	outer.add_child(_head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = UiKit.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	outer.add_child(scroll)
	_panel.add_child(outer)
	_frame = HoloFrame.attach(_panel)
	add_child(_panel)
	visible = false


func open() -> void:
	visible = true
	_build()
	UiKit.fit_layer(self, _panel)
	UiKit.fit_layer.call_deferred(self, _panel)
	HoloAnim.boot_in(_panel)
	_frame.boot()


func close() -> void:
	if visible:
		HoloAnim.power_off(self, Rect2(offset + _panel.position * scale, _panel.size * scale), layer + 1)
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	UiKit.clear(_head)
	UiKit.clear(_body)
	var close_btn := UiKit.with_icon(UiKit.button(Loc.t("Close"), close), "ui.icon_close", 16)
	var hb := UiKit.header_block(Loc.t("Credits"), Loc.t("The people, packs and tools behind the Ark."), "ui.icon_credits")
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(hb.get_child(0) as HBoxContainer).add_child(close_btn)
	_head.add_child(hb)
	for section: Dictionary in GameSession.content.credits:
		var card := Holo.card(UiKit.PETROL.lightened(0.2), 12)
		var v := UiKit.vbox(6)
		v.add_child(UiKit.title(str(section.get("title", ""))))
		for e: Dictionary in DictUtil.get_arr(section, "entries"):
			var planned := str(e.get("status", "in_use")) == "planned"
			var row := UiKit.hbox(12)
			var role := UiKit.label(str(e.get("role", "")), 15, UiKit.MUTED, true)
			role.custom_minimum_size = Vector2(360, 0)
			role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(role)
			var who := UiKit.label(str(e.get("name", "")) + (Loc.t("  (planned)") if planned else ""), 16,
				UiKit.MUTED.darkened(0.2) if planned else Color.WHITE, true)
			who.add_theme_font_override("font", UiKit.bold_font())
			who.custom_minimum_size = Vector2(330, 0)
			row.add_child(who)
			if planned:
				row.add_child(Holo.chip(Loc.t("Planned"), UiKit.MUTED, "", 10))
			v.add_child(row)
			if e.has("text"):
				v.add_child(UiKit.label(str(e["text"]), 13, UiKit.MUTED, true))
		card.add_child(v)
		_body.add_child(card)
	var lic := Holo.card(UiKit.MUTED, 12)
	var lv := UiKit.vbox(6)
	lv.add_child(UiKit.title(Loc.t("Licenses")))
	lv.add_child(UiKit.label(Loc.t("The game uses Godot Engine, released under the MIT license:"), 14, UiKit.MUTED, true))
	lv.add_child(_mono(Engine.get_license_text()))
	lv.add_child(UiKit.label(Loc.t("Third-party components in Godot Engine:"), 14, UiKit.MUTED, true))
	lv.add_child(_mono(_third_party_text()))
	lic.add_child(lv)
	_body.add_child(lic)
	HoloAnim.stagger(_body, 0.05, 0.1)
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
	l.custom_minimum_size = Vector2(780, 0)
	return l
