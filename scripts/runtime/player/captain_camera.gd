class_name CaptainCamera
extends Node3D
## Third-person orbit camera. SpringArm3D keeps it out of walls (bible p.6:
## the camera must never pass through the ship's hull).

var target: Node3D
## yaw/pitch are where the player wants the camera; _view_* is where it is.
## The view eases towards the target, so drags and auto-follow feel smooth.
var yaw := 0.0
var pitch := -0.35
var _view_yaw := 0.0
var _view_pitch := -0.35
var _view_init := false
const REST_PITCH := -0.32
const TOUCH_LOOK := 0.0022     # rad per canvas px at sensitivity 1 (full-width swipe ≈ 180°)
const AUTO_FOLLOW := 0.7       # rad/s at full sideways stick, like HSR/Genshin

var distance := 4.2
var camera: Camera3D
var arm: SpringArm3D
var active := true


func _ready() -> void:
	top_level = true
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.collision_mask = 1 | 16 | 8
	arm.margin = 0.25
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	arm.shape = sh
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.near = 0.1
	camera.far = 2000.0
	arm.add_child(camera)
	set_active(true)


func set_active(on: bool) -> void:
	active = on
	if camera:
		camera.current = on or camera.current
	if on and DisplayServer.get_name() != "headless" and not TouchControls.enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Jump the view to the target angles (teleports, scene starts): no easing.
func snap() -> void:
	_view_yaw = yaw
	_view_pitch = pitch
	_view_init = true


func make_current() -> void:
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := float(SettingsService.get_value("mouse_sensitivity", 0.25)) * 0.01
		var inv := -1.0 if SettingsService.get_value("invert_y", false) else 1.0
		yaw -= (event as InputEventMouseMotion).relative.x * sens
		pitch = clampf(pitch - (event as InputEventMouseMotion).relative.y * sens * inv, -1.2, 0.5)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if DisplayServer.get_name() != "headless" and not TouchControls.enabled and not get_viewport().gui_get_hovered_control():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if target == null:
		return
	# Autoloads are freed before top-level nodes at quit; never touch a freed TouchControls.
	var touch := is_instance_valid(TouchControls) and TouchControls.enabled
	var td: Vector2 = TouchControls.consume_look() if touch else Vector2.ZERO
	if active and td != Vector2.ZERO:
		var sens := TOUCH_LOOK * float(SettingsService.get_value("touch_look_sensitivity", 1.0))
		yaw -= td.x * sens
		pitch = clampf(pitch - td.y * sens * 0.6, -0.95, 0.3)
	if active and touch and TouchControls.joy_active() and TouchControls.look_idle() > 0.8:
		# Camera drifts in behind the captain while walking sideways; pitch settles back.
		var mv: Vector2 = TouchControls.move_vector()
		yaw -= mv.x * AUTO_FOLLOW * delta
		pitch = lerpf(pitch, REST_PITCH, 1.0 - exp(-0.8 * delta))
	if active:
		var pv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if pv != Vector2.ZERO:
			var ps := float(SettingsService.get_value("pad_look_speed", 2.4)) * delta
			var pinv := -1.0 if SettingsService.get_value("invert_y", false) else 1.0
			yaw -= pv.x * ps
			pitch = clampf(pitch - pv.y * ps * 0.7 * pinv, -1.2, 0.5)
	if not _view_init:
		_view_yaw = yaw
		_view_pitch = pitch
		_view_init = true
	var damp := 9.0 if touch else 24.0  # touch: soft; mouse: near-instant
	var k := 1.0 - exp(-damp * delta)
	_view_yaw = lerp_angle(_view_yaw, yaw, k)
	_view_pitch = lerpf(_view_pitch, pitch, k)
	var want := target.global_position + Vector3(0, 1.55, 0)
	var follow := 1.0 - exp(-(8.0 if touch else 14.0) * delta)
	global_position = global_position.lerp(want, follow) if global_position.distance_to(want) < 3.0 else want
	rotation = Vector3(_view_pitch, _view_yaw, 0)
	arm.spring_length = distance
