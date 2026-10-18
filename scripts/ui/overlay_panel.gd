class_name OverlayPanel
extends CanvasLayer
## Modal overlay base: dims the scene, frees the mouse, emits closed. Esc closes.

signal closed

var panel: PanelContainer
var body: VBoxContainer
var _dim: ColorRect


func _init(size: Vector2 = Vector2(1100, 720)) -> void:
	layer = 25
	_dim = ColorRect.new()
	_dim.color = Color(0, 0.02, 0.04, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	panel = UiKit.panel(size)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	body = UiKit.vbox(10)
	panel.add_child(body)
	add_child(panel)
	visible = false


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func refresh() -> void:
	pass


func header(text: String, sub: String = "") -> void:
	var h := UiKit.hbox(10)
	var v := UiKit.vbox(0)
	v.add_child(UiKit.heading(text))
	if not sub.is_empty():
		v.add_child(UiKit.label(sub, 15, UiKit.MUTED, true))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	h.add_child(UiKit.button(Loc.t("Close  [Esc]"), close))
	body.add_child(h)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
