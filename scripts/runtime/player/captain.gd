class_name Captain
extends CharacterBody3D
## Third-person captain (bible p.6): WASD + mouse camera, E interacts, Shift
## runs. Input stays separate from the domain. The VisualPivot holds the
## VisualSlot "char.captain" so a Synty/Sidekick rig can replace the capsule.

signal interact_target_changed(target: Interactable)
signal hold_progress(fraction: float)

@export var walk_speed: float = 3.0
@export var run_speed: float = 5.0
## Calm, weighty feel (no twitch): ~0.3 s to full walk, slightly faster stop,
## body turns over ~0.25 s instead of snapping to the stick.
@export var acceleration: float = 10.0
@export var deceleration: float = 14.0
@export var turn_speed: float = 8.0
@export var gravity_scale: float = 1.0

var input_enabled := true
var current_target: Interactable = null
var camera_rig: CaptainCamera
var visual_pivot: Node3D
var _hold := 0.0
var _hold_audio: AudioStreamPlayer3D
## Footstep cue family; outdoor scenes switch to "sfx_footstep_soil".
var footstep_slot := "sfx_footstep"
var _probe: Area3D
var _step_accum := 0.0
var _anim: CharacterAnimator
var _slot: VisualSlot


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16 | 8
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	visual_pivot = Node3D.new()
	visual_pivot.name = "VisualPivot"
	add_child(visual_pivot)
	_slot = VisualSlot.make("char.captain")
	visual_pivot.add_child(_slot)
	_anim = CharacterAnimator.for_slot(_slot)
	_probe = Area3D.new()
	_probe.collision_layer = 0
	_probe.collision_mask = 4
	var ps := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.6
	ps.shape = sp
	ps.position = Vector3(0, 1.0, -0.9)
	_probe.add_child(ps)
	add_child(_probe)
	camera_rig = CaptainCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.target = self
	var bal: Dictionary = GameSession.content.bal("player", {}) if GameSession.content else {}
	walk_speed = DictUtil.get_float(bal, "walk_speed", walk_speed)
	run_speed = DictUtil.get_float(bal, "run_speed", run_speed)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta
	var dir := Vector3.ZERO
	if input_enabled:
		var touch := is_instance_valid(TouchControls) and TouchControls.joy_active()
		var iv := TouchControls.move_vector() if touch else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var basis_y := Basis(Vector3.UP, camera_rig.yaw)
		dir = (basis_y * Vector3(iv.x, 0, iv.y))
		if dir.length() > 1.0:
			dir = dir.normalized()
	var running := Input.is_action_pressed("sprint") or (is_instance_valid(TouchControls) and TouchControls.wants_run())
	var speed := run_speed if running else walk_speed
	var target := dir * speed
	var cur := Vector3(velocity.x, 0, velocity.z)
	var rate := acceleration if target.length() > cur.length() else deceleration
	var hv := cur.move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	if hv.length() > 0.2:
		var want := atan2(-hv.x, -hv.z)
		visual_pivot.rotation.y = lerp_angle(visual_pivot.rotation.y, want, 1.0 - exp(-turn_speed * delta))
		_probe.rotation.y = visual_pivot.rotation.y
		_step_accum += hv.length() * delta
		if _step_accum > 1.6 and is_on_floor():
			_step_accum = 0.0
			AudioService.play_variant(footstep_slot, "SFX", -14.0)
	_update_target()
	_update_hold(delta)
	if _anim.active():
		var spd := Vector2(velocity.x, velocity.z).length()
		var st := "idle"
		if _hold > 0.0:
			st = "sample"
		elif spd > walk_speed + 0.3:
			st = "run"
		elif spd > 0.2:
			st = "walk"
		_anim.update(st, spd)


func _update_target() -> void:
	var best: Interactable = null
	var best_d := INF
	for a: Area3D in _probe.get_overlapping_areas():
		if a is Interactable and a.visible:
			var d := a.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = a
	if best != current_target:
		current_target = best
		_hold = 0.0
		hold_progress.emit(0.0)
		interact_target_changed.emit(best)


func _update_hold(delta: float) -> void:
	if current_target == null or not input_enabled:
		return
	if current_target.hold_time <= 0.0:
		return
	if Input.is_action_pressed("interact") and not current_target.locked:
		if _hold == 0.0 and _hold_audio == null:
			_hold_audio = AudioService.play_at("sfx_sample_loop", self, -6.0)
		_hold += delta
		hold_progress.emit(clampf(_hold / current_target.hold_time, 0, 1))
		if _hold >= current_target.hold_time:
			_hold = 0.0
			_stop_hold_audio()
			hold_progress.emit(0.0)
			current_target.use()
	elif _hold > 0.0:
		_hold = 0.0
		_stop_hold_audio()
		hold_progress.emit(0.0)


func _stop_hold_audio() -> void:
	if _hold_audio:
		_hold_audio.queue_free()
		_hold_audio = null


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("interact") and current_target and current_target.hold_time <= 0.0:
		current_target.use()
		get_viewport().set_input_as_handled()


func set_active(on: bool) -> void:
	input_enabled = on
	camera_rig.set_active(on)
	if not on:
		velocity = Vector3.ZERO


func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	camera_rig.yaw = yaw
	camera_rig.snap()
	visual_pivot.rotation.y = yaw
