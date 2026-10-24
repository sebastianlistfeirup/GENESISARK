class_name OverlayPanel
extends CanvasLayer
## Modal overlay base: dims the scene, frees the mouse, emits closed. Esc closes.
## Holo-console look (D-055): every overlay wears a HoloFrame (brackets,
## scanlines, edge glow), boots in (unfolds, flickers on, content prints
## top-down and fades in one block after another) and powers off like an old
## screen when it closes. Reduced motion: shown and hidden at once.

signal closed

var panel: PanelContainer
var body: VBoxContainer
var frame: HoloFrame
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
	frame = HoloFrame.attach(panel)
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
	HoloAnim.boot_in(panel)
	frame.boot()
	HoloAnim.stagger(body, 0.05, 0.12)
	# With a controller, focus lands on the panel's main control (bible p.26).
	var f := focus_target()
	if f and SettingsService.using_pad:
		f.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	HoloAnim.power_off(self, Rect2(offset + panel.position * scale, panel.size * scale), layer + 1)
	visible = false
	closed.emit()


func refresh() -> void:
	pass


## The control that takes focus when the panel opens with a controller:
## the Close button unless a panel names a better one.
func focus_target() -> Control:
	return _close_btn


var _close_btn: Button


## After a panel rebuilt itself (a repair, a probe), a controller keeps a
## focused control. Call deferred from refresh().
func regrab_focus() -> void:
	var f := focus_target()
	if visible and f and f.is_inside_tree() and SettingsService.using_pad:
		f.grab_focus()


## Panel header: badge, title, sub line, optional status chips
## ([icon_slot, text, Color] each) and the Close button.
func header(text: String, sub: String = "", icon_slot: String = "", chips: Array = []) -> void:
	var blk := UiKit.header_block(text, sub, icon_slot)
	var h := blk.get_child(0) as HBoxContainer
	if not chips.is_empty():
		var row := UiKit.hbox(6)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for c: Array in chips:
			row.add_child(Holo.chip(str(c[1]), c[2] if c.size() > 2 else UiKit.PETROL.lightened(0.35), str(c[0]), 13))
		h.add_child(row)
	var cb := UiKit.button(Loc.t("Close  [%s]") % SettingsService.primary_key("pause"), close)
	UiKit.with_icon(cb, "ui.icon_close", 16)
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_btn = cb
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
