class_name ColonyCamera
extends Node3D
## Oblique overhead camera (bible p.6): WASD pan, wheel zoom, Q/E step rotation.

var cam: Camera3D
var zoom := 70.0
var target_yaw := 0.0
var active := true
var bounds := 95.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 50
	cam.far = 1200
	add_child(cam)
	rotation.y = target_yaw
	_apply()


func _apply() -> void:
	cam.position = Vector3(0, zoom * 0.82, zoom * 0.62)
	cam.look_at(global_position, Vector3.UP)


func make_current() -> void:
	cam.current = true


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 5.0, 18.0, 150.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 5.0, 18.0, 150.0)
	if event.is_action_pressed("zoom_in"):
		zoom = clampf(zoom - 10.0, 18.0, 150.0)
	elif event.is_action_pressed("zoom_out"):
		zoom = clampf(zoom + 10.0, 18.0, 150.0)
	if event.is_action_pressed("rotate_cam_left"):
		target_yaw += PI * 0.5
	elif event.is_action_pressed("rotate_cam_right"):
		target_yaw -= PI * 0.5


func _process(delta: float) -> void:
	if not active:
		return
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move := Basis(Vector3.UP, rotation.y) * Vector3(iv.x, 0, iv.y) * zoom * 0.9 * delta
	position += move
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	var fast := bool(SettingsService.get_value("reduced_motion", false))
	rotation.y = target_yaw if fast else lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0, 1))
	_apply()
