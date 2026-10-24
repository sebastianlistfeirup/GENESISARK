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
	# Oversized so the dim still covers the screen when fit() scales the layer down.
	_dim.offset_left = -4096
	_dim.offset_top = -4096
	_dim.offset_right = 4096
	_dim.offset_bottom = 4096
	add_child(_dim)
	panel = UiKit.panel(size)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	body = UiKit.vbox(10)
	panel.add_child(body)
	add_child(panel)
	panel.minimum_size_changed.connect(fit)
	visible = false


func _ready() -> void:
	get_viewport().size_changed.connect(fit)
	SettingsService.changed.connect(fit)


## Keep the whole panel on screen at any window size and UI scale (bible p.26).
func fit() -> void:
	if visible:
		UiKit.fit_layer(self, panel)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	fit()
	fit.call_deferred()
	UiKit.fade_in(_dim, 0.22)
	UiKit.fade_in(panel)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func refresh() -> void:
	pass


func header(text: String, sub: String = "", icon_slot: String = "") -> void:
	var blk := UiKit.header_block(text, sub, icon_slot)
	var h := blk.get_child(0) as HBoxContainer
	var cb := UiKit.button(Loc.t("Close  [%s]") % SettingsService.primary_key("pause"), close)
	UiKit.with_icon(cb, "ui.icon_close", 16)
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# On a controller, show the real button glyph instead of its name.
	var glyph := SyntySkin.pad_glyph(str(SettingsService.PAD["pause"][0])) if SettingsService.using_pad else null
	if glyph:
		cb.text = Loc.t("Close")
		cb.icon = glyph
		cb.expand_icon = false
		cb.add_theme_constant_override("icon_max_width", 26)
		cb.add_theme_color_override("icon_normal_color", Color.WHITE)
	h.add_child(cb)
	body.add_child(blk)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
