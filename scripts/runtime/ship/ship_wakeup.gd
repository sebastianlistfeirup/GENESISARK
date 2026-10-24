class_name ShipWakeup
extends Node3D
## The first seconds of a new campaign (D-060): the captain wakes in a cryo pod
## on the derelict ark. Darkness, then frosted glass and red emergency light seen
## lying down; the glass cracks, the hatch snaps up with a burst of cryo vapour,
## and the view sits up with a woozy, weighted sway before handing over to the
## normal third-person camera. Disney beats at ~50%: anticipation (breath, shake,
## cracks), fast action (hatch), follow-through (sit-up overshoot, lagging roll).
## Skippable (any of interact / skip / pause), short with reduced motion.
## Presentation only.

signal opened
signal finished

var captain: Captain
var hud: GameHud
var _cam: Camera3D
var _layer: CanvasLayer
var _black: ColorRect
var _frost: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _rest := Transform3D.IDENTITY   # where the camera ends: standing eye height at the spawn
var _lie := Transform3D.IDENTITY    # lying in the pod, looking up and out
var _opened := false
var _done := false
var _dur := 9.0


func start(p_captain: Captain, p_hud: GameHud, spawn: Vector3, yaw: float) -> void:
	captain = p_captain
	hud = p_hud
	captain.visible = false
	captain.input_enabled = false
	hud.visible = false
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye := spawn + Vector3(0, 1.62, 0)
	_rest = Transform3D(Basis.looking_at(fwd, Vector3.UP), eye)
	var lie_pos := spawn - fwd * 0.35 + Vector3(0, 0.95, 0)
	var up_look := (fwd * 0.55 + Vector3.UP).normalized()
	_lie = Transform3D(Basis.looking_at(up_look, -fwd) * Basis(Vector3.FORWARD, deg_to_rad(6.0)), lie_pos)
	_cam = Camera3D.new()
	_cam.fov = 64.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.global_transform = _lie
	_cam.current = true
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_frost = ColorRect.new()
	_frost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/cryo_frost.gdshader")
	_frost.material = _mat
	_layer.add_child(_frost)
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 1)
	_layer.add_child(_black)
	if FxEffect.reduced_motion():
		_dur = 2.5
		_t = 6.5


func _process(delta: float) -> void:
	if _done:
		return
	if Input.is_action_just_pressed("skip_line"):
		_open_now()
		_finish()
		return
	_t += delta
	var t := _t
	if not _cam.current:
		_cam.current = true  # the captain's rig claims the view on its first frames
	# 0.0-1.6 darkness, slowly lifting.
	_black.color.a = 1.0 - smoothstep(0.6, 2.0, t)
	# Breathing behind frosted glass, 1.2-3.6.
	var breath := 0.5 + 0.5 * sin(t * 2.2)
	_mat.set_shader_parameter("breath", breath * (1.0 - smoothstep(3.0, 3.6, t)))
	# Anticipation 3.4-4.2: cracks spread, the pod shudders.
	_mat.set_shader_parameter("crack", smoothstep(3.4, 4.1, t))
	var shake := 0.0
	if t > 3.5 and t < 4.25:
		shake = 0.012 * (1.0 - absf(t - 3.9) / 0.4)
	# Action 4.2-4.55: the hatch snaps up and overshoots a touch.
	var s := smoothstep(4.2, 4.55, t)
	var over := sin(clampf((t - 4.55) / 0.35, 0.0, 1.0) * PI) * 0.04 * float(t > 4.55)
	_mat.set_shader_parameter("slide", s - over)
	if t >= 4.2 and not _opened:
		_open_now()
	# Sit up 4.8-7.4: ease-out with overshoot, roll lags behind (overlapping action).
	var k := clampf((t - 4.8) / 2.6, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	e += sin(k * PI) * 0.06  # overshoot past upright, settles
	var xf := _lie.interpolate_with(_rest, clampf(e, 0.0, 1.06))
	var lag := sin(clampf((t - 5.2) / 3.0, 0.0, 1.0) * PI * 1.5) * deg_to_rad(5.0) * (1.0 - k * 0.6)
	var sway := sin(t * 1.7) * deg_to_rad(1.2) * (1.0 - smoothstep(7.0, 8.6, t))
	xf.basis = xf.basis * Basis(Vector3.FORWARD, lag + sway)
	xf.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake
	_cam.global_transform = xf
	if t >= _dur:
		_finish()


func _open_now() -> void:
	if _opened:
		return
	_opened = true
	AudioService.play("sfx_door", "SFX", -2.0, 0.8)
	var vapour := _vapour()
	add_child(vapour)
	var fwd := -_rest.basis.z
	vapour.global_position = _lie.origin + fwd * 0.5 + Vector3(0, 0.1, 0)
	vapour.emitting = true
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(vapour):
			vapour.queue_free())
	opened.emit()


func _exit_tree() -> void:
	_restore()  # scene changed mid-sequence: never leave the player hidden or frozen


func _restore() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(captain):
		captain.visible = true
		captain.input_enabled = true
		if captain.camera_rig:
			captain.camera_rig.camera.current = true
			captain.camera_rig.snap()
	if is_instance_valid(hud):
		hud.visible = true


func _finish() -> void:
	if _done:
		return
	_restore()
	var tw := create_tween()
	tw.tween_property(_frost, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
	finished.emit()


## Thin cryo vapour rolling out of the opened pod and sinking to the floor.
func _vapour() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 3.2
	p.one_shot = true
	p.explosiveness = 0.55
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.15, 0.9)
	pm.direction = Vector3(0, 0.2, -1)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -0.35, 0)  # cold vapour sinks
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.8))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.93, 1.0, 0.0))
	g.add_point(0.15, Color(0.85, 0.93, 1.0, 0.16))
	g.set_color(1, Color(0.85, 0.93, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.6
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in 64:
		for x: int in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2.0))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	q.material = mat
	p.draw_pass_1 = q
	return p
