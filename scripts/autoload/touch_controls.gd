extends CanvasLayer
## On-screen controls for phones and tablets (web build). Active only on a
## touchscreen (or with the `--touch` user arg for testing). Right side: drag
## to look. Buttons are TouchScreenButtons bound to the normal input actions.
##
## Left: a calm, floating joystick in the style of Honkai: Star Rail / Genshin.
## It appears under the thumb, has a radial dead zone and a soft response
## curve, and the output is low-pass filtered so thumb jitter never reaches
## the captain. Small deflection = slow walk, full deflection = run.
## Captain reads move_vector() directly (analog, no action dead zone on top);
## other scenes still get the move_* actions.

const JOY_RADIUS := 150.0       # canvas px for full deflection (canvas is 1400x800)
const KNOB_RADIUS := 52.0
const DEAD_ZONE := 0.16         # radial, as a fraction of JOY_RADIUS
const RUN_FROM := 0.92          # deflection that turns walking into running
const SMOOTH_RATE := 10.0       # 1/s; ~100 ms to settle, removes jitter
const FOLLOW_RADIUS := 1.25     # dragging past this drags the base along (no "stuck" edge)
const REST := Vector2(230, -210)  # resting base position (from bottom-left)

var enabled := false
var look_delta := Vector2.ZERO
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_raw := Vector2.ZERO   # unfiltered, -1..1
var _joy_vec := Vector2.ZERO   # shaped + smoothed, what the game sees
var _look_idle := 0.0          # seconds since the last look drag
var _pressed: Dictionary = {}  # move_* actions currently pressed by the stick
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
	_base = _circle(JOY_RADIUS, Color(1, 1, 1, 0.08))
	_knob = _circle(KNOB_RADIUS, Color(0.9, 0.64, 0.24, 0.45))
	_root.add_child(_base)
	_root.add_child(_knob)
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
		"ship": ["interact", "journal", "pause"],  # run = push the stick all the way
		"surface": ["interact", "journal", "pause", "drone_refill"],
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


func _rest_center() -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	return Vector2(REST.x, vs.y + REST.y)


## Joystick shown faintly at rest so the thumb knows where to go; it follows
## the thumb while held and glides back afterwards.
func _draw_joy(delta: float) -> void:
	if _base == null:
		return
	_base.visible = _joy_allowed
	_knob.visible = _joy_allowed
	var held := _joy_index >= 0
	var center := _joy_center if held else _rest_center()
	var k := 1.0 - exp(-18.0 * delta)
	var base_pos := center - Vector2(JOY_RADIUS, JOY_RADIUS)
	_base.position = base_pos if held else _base.position.lerp(base_pos, k)
	var knob_target := center + _joy_raw * JOY_RADIUS - Vector2(KNOB_RADIUS, KNOB_RADIUS)
	_knob.position = knob_target if held else _knob.position.lerp(knob_target, k)
	_base.modulate.a = lerpf(_base.modulate.a, 1.0 if held else 0.45, k)
	_knob.modulate.a = _base.modulate.a


func _input(event: InputEvent) -> void:
	if not enabled or get_tree().paused:
		return
	var vs := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _joy_allowed and _joy_index < 0 and t.position.x < vs.x * 0.45 and t.position.y > vs.y * 0.3 and not _on_button(t.position):
				_joy_index = t.index
				# Floating: the stick starts under the thumb (never with a jump in direction).
				_joy_center = t.position
				_joy_raw = Vector2.ZERO
			elif _look_index < 0 and t.position.x >= vs.x * 0.45 and not _on_button(t.position):
				_look_index = t.index
		else:
			if t.index == _joy_index:
				_release_joy()
			if t.index == _look_index:
				_look_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var v := (d.position - _joy_center) / JOY_RADIUS
			if v.length() > FOLLOW_RADIUS:
				# Thumb wandered off: drag the base along instead of pinning it at the rim.
				_joy_center += (v - v.limit_length(FOLLOW_RADIUS)) * JOY_RADIUS
				v = v.limit_length(FOLLOW_RADIUS)
			_joy_raw = v.limit_length(1.0)
		elif d.index == _look_index:
			look_delta += d.relative
			_look_idle = 0.0


func _on_button(pos: Vector2) -> bool:
	for b: TouchScreenButton in _buttons.values():
		if b.visible:
			var r: float = b.get_meta("r")
			if pos.distance_to(b.position + Vector2(r, r)) <= r + 12.0:
				return true
	return false


## Radial dead zone + smoothstep curve: the first part of the throw is fine
## control, the outer part is speed. Pure function (tested).
static func shape(raw: Vector2) -> Vector2:
	var m := raw.length()
	if m <= DEAD_ZONE:
		return Vector2.ZERO
	var t := clampf((m - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return raw / m * t


func _process(delta: float) -> void:
	if not enabled:
		return
	_look_idle += delta
	var target := shape(_joy_raw) if _joy_index >= 0 else Vector2.ZERO
	_joy_vec = _joy_vec.lerp(target, 1.0 - exp(-SMOOTH_RATE * delta))
	if target == Vector2.ZERO and _joy_vec.length() < 0.02:
		_joy_vec = Vector2.ZERO
	_apply_joy()
	_draw_joy(delta)


## Analog move input for the captain: x = right, y = back (like Input.get_vector).
func move_vector() -> Vector2:
	return _joy_vec


func joy_active() -> bool:
	return enabled and (_joy_index >= 0 or _joy_vec != Vector2.ZERO)


## Full deflection held = run (no separate run button needed on the phone).
func wants_run() -> bool:
	return enabled and _joy_index >= 0 and _joy_raw.length() >= RUN_FROM


## Seconds since the player last dragged the camera (camera auto-follow waits for it).
func look_idle() -> float:
	return _look_idle


func _apply_joy() -> void:
	var v := _joy_vec
	for pair: Array in [["move_right", maxf(v.x, 0.0)], ["move_left", maxf(-v.x, 0.0)], ["move_back", maxf(v.y, 0.0)], ["move_forward", maxf(-v.y, 0.0)]]:
		if float(pair[1]) > 0.05:
			Input.action_press(str(pair[0]), float(pair[1]))
			_pressed[pair[0]] = true
		elif _pressed.has(pair[0]):  # only release what the stick pressed (a keyboard may be attached)
			Input.action_release(str(pair[0]))
			_pressed.erase(pair[0])


func _release_joy() -> void:
	_joy_index = -1
	_joy_raw = Vector2.ZERO  # _joy_vec eases out in _process: no hard stop


## Camera code reads and clears the accumulated look drag.
func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
