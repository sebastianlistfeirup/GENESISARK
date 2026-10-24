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


## Zoom-dependent tilt, like modern city builders: close in, the camera pitches
## down to ~33 degrees so buildings are seen from the side; from TILT_FAR_ZOOM
## out it keeps the classic ~53 degree overview. It follows the zoom directly
## (no extra easing), so reduced motion behaves exactly as before.
const PITCH_NEAR := 33.0
const PITCH_FAR := 52.9  # atan(0.82 / 0.62), the original overview
const TILT_NEAR_ZOOM := 18.0
const TILT_FAR_ZOOM := 80.0


static func pitch_for(z: float) -> float:
	var t := smoothstep(TILT_NEAR_ZOOM, TILT_FAR_ZOOM, z)
	return deg_to_rad(lerpf(PITCH_NEAR, PITCH_FAR, t))


func _apply() -> void:
	var p := pitch_for(zoom)
	var dist := zoom * 1.0283  # same distance as the old (0.82, 0.62) offset
	cam.position = Vector3(0, dist * sin(p), dist * cos(p))
	# Close in, aim a little above the ground so the street and facades fill the frame.
	var lift := lerpf(1.6, 0.0, smoothstep(TILT_NEAR_ZOOM, TILT_FAR_ZOOM, zoom))
	cam.look_at(global_position + Vector3(0, lift, 0), Vector3.UP)


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
	var look := Input.get_axis("look_left", "look_right")
	if absf(look) > 0.0:
		target_yaw -= look * delta * 1.8
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	var fast := bool(SettingsService.get_value("reduced_motion", false))
	rotation.y = target_yaw if fast else lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0, 1))
	_apply()
