extends CanvasLayer
## On-screen controls for phones and tablets (web build). Active only on a
## touchscreen (or with the `--touch` user arg for testing). Left: virtual
## joystick -> move_* actions with analog strength. Right half: drag to look.
## Buttons are TouchScreenButtons bound to the normal input actions, so the
## game code needs no touch-specific branches.

const JOY_RADIUS := 110.0

var enabled := false
var look_delta := Vector2.ZERO
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _root: Control
var _base: Control
var _knob: Control
var _buttons: Dictionary = {}  # action -> TouchScreenButton
var _portrait: Label


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	if not enabled:
		return
	# Bigger UI on small screens: lay the 2D UI out for a smaller canvas.
	get_tree().root.content_scale_size = Vector2i(1400, 800)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_base = _circle(JOY_RADIUS, Color(1, 1, 1, 0.12))
	_knob = _circle(46.0, Color(0.9, 0.64, 0.24, 0.55))
	_root.add_child(_base)
	_root.add_child(_knob)
	_base.visible = false
	_knob.visible = false
	var defs := [
		["interact", "E", Vector2(-120, -150), 64.0], ["sprint", Loc.t("Løb"), Vector2(-260, -110), 48.0],
		["build_confirm", Loc.t("Byg"), Vector2(-120, -210), 64.0], ["cancel", Loc.t("Fortryd"), Vector2(-270, -180), 48.0],
		["rotate_building", Loc.t("Drej"), Vector2(-390, -160), 42.0], ["zoom_in", "+", Vector2(-120, -330), 40.0],
		["zoom_out", "−", Vector2(-220, -330), 40.0], ["rotate_cam_left", "⟲", Vector2(-320, -330), 40.0],
		["rotate_cam_right", "⟳", Vector2(-420, -330), 40.0], ["colony_mode", "B", Vector2(-120, -460), 40.0],
		["autopilot", Loc.t("Auto"), Vector2(-120, -150), 64.0], ["drone_refill", Loc.t("Drone"), Vector2(-260, -250), 44.0],
		["ascend", "▲", Vector2(-380, -150), 42.0], ["descend", "▼", Vector2(-380, -60), 42.0],
		["journal", Loc.t("Log"), Vector2(170, 180), 40.0], ["pause", "II", Vector2(70, 180), 40.0],
		["speed_pause", Loc.t("Tid"), Vector2(-220, -460), 40.0],
	]
	for d: Array in defs:
		_add_button(str(d[0]), str(d[1]), d[2], float(d[3]))
	_portrait = UiKit.label(Loc.t("Drej telefonen til liggende format"), 34, UiKit.AMBER)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_portrait)
	AppFlow.scene_changed.connect(func(_k: String) -> void: _update_visibility())
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_visibility()


func _circle(r: float, c: Color) -> Control:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(r))
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(r * 2, r * 2)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _add_button(action: String, text: String, offset: Vector2, r: float) -> void:
	var b := TouchScreenButton.new()
	b.action = action
	var shape := CircleShape2D.new()
	shape.radius = r
	b.shape = shape
	b.shape_centered = true
	b.passby_press = false
	var img := Image.create(int(r * 2), int(r * 2), false, Image.FORMAT_RGBA8)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var d := Vector2(x - r, y - r).length()
			if d <= r:
				img.set_pixel(x, y, Color(0.06, 0.11, 0.14, 0.62) if d < r - 3 else Color(0.12, 0.54, 0.54, 0.9))
	var tex := ImageTexture.create_from_image(img)
	b.texture_normal = tex
	var pressed := img.duplicate() as Image
	pressed.adjust_bcs(1.6, 1.0, 1.0)
	b.texture_pressed = ImageTexture.create_from_image(pressed)
	var l := UiKit.label(text, int(r * 0.55), UiKit.TEXT)
	l.size = Vector2(r * 2, r * 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.set_meta("offset", offset)
	b.set_meta("r", r)
	add_child(b)
	_buttons[action] = b


func _layout() -> void:
	if not enabled:
		return
	var vs := get_viewport().get_visible_rect().size
	for action: String in _buttons.keys():
		var b: TouchScreenButton = _buttons[action]
		var off: Vector2 = b.get_meta("offset")
		var r: float = b.get_meta("r")
		var anchor := Vector2(vs.x if off.x < 0 else 0.0, vs.y if off.y < 0 else 0.0)
		b.position = anchor + off - Vector2(r, r)
	_portrait.visible = vs.y > vs.x


func _update_visibility() -> void:
	if not enabled:
		return
	var key := AppFlow.current_key
	var sets := {
		"ship": ["interact", "sprint", "journal", "pause"],
		"surface": ["interact", "sprint", "journal", "pause", "drone_refill"],
		"flight": ["autopilot", "ascend", "descend", "pause"],
		"colony": ["build_confirm", "cancel", "rotate_building", "zoom_in", "zoom_out", "rotate_cam_left", "rotate_cam_right", "colony_mode", "journal", "pause", "speed_pause"],
	}
	var show: Array = sets.get(key, [])
	for action: String in _buttons.keys():
		(_buttons[action] as TouchScreenButton).visible = action in show
	_joy_allowed = key in ["ship", "surface", "flight", "colony"]
	if not _joy_allowed:
		_release_joy()


var _joy_allowed := false


func _input(event: InputEvent) -> void:
	if not enabled or get_tree().paused:
		return
	var vs := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _joy_allowed and _joy_index < 0 and t.position.x < vs.x * 0.4 and t.position.y > vs.y * 0.35:
				_joy_index = t.index
				_joy_center = t.position
				_base.position = _joy_center - Vector2(JOY_RADIUS, JOY_RADIUS)
				_knob.position = _joy_center - Vector2(46, 46)
				_base.visible = true
				_knob.visible = true
			elif _look_index < 0 and t.position.x >= vs.x * 0.4:
				_look_index = t.index
		else:
			if t.index == _joy_index:
				_release_joy()
			if t.index == _look_index:
				_look_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var v := (d.position - _joy_center).limit_length(JOY_RADIUS)
			_knob.position = _joy_center + v - Vector2(46, 46)
			_joy_vec = v / JOY_RADIUS
			_apply_joy()
		elif d.index == _look_index:
			look_delta += d.relative


func _apply_joy() -> void:
	var v := _joy_vec
	for pair: Array in [["move_right", maxf(v.x, 0.0)], ["move_left", maxf(-v.x, 0.0)], ["move_back", maxf(v.y, 0.0)], ["move_forward", maxf(-v.y, 0.0)]]:
		if float(pair[1]) > 0.15:
			Input.action_press(str(pair[0]), float(pair[1]))
		else:
			Input.action_release(str(pair[0]))


func _release_joy() -> void:
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	if _base:
		_base.visible = false
		_knob.visible = false
	for a: String in ["move_right", "move_left", "move_back", "move_forward"]:
		Input.action_release(a)


## Camera code reads and clears the accumulated look drag.
func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
