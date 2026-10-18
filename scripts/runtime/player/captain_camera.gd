class_name CaptainCamera
extends Node3D
## Third-person orbit camera. SpringArm3D keeps it out of walls (bible p.6:
## the camera must never pass through the ship's hull).

var target: Node3D
var yaw := 0.0
var pitch := -0.35
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
	var td: Vector2 = TouchControls.consume_look() if TouchControls.enabled else Vector2.ZERO
	if active and td != Vector2.ZERO:
		var sens := float(SettingsService.get_value("mouse_sensitivity", 0.25)) * 0.012
		yaw -= td.x * sens
		pitch = clampf(pitch - td.y * sens, -1.2, 0.5)
	var want := target.global_position + Vector3(0, 1.55, 0)
	global_position = global_position.lerp(want, clampf(delta * 14.0, 0, 1)) if global_position.distance_to(want) < 3.0 else want
	rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = distance
