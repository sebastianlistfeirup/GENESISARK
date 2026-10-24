class_name Captain
extends CharacterBody3D
## Third-person captain (bible p.6): WASD + mouse camera, E interacts, Shift
## runs. Input stays separate from the domain. The VisualPivot holds the
## VisualSlot "char.captain" so a Synty/Sidekick rig can replace the capsule.

signal interact_target_changed(target: Interactable)
signal hold_progress(fraction: float)

@export var walk_speed: float = 4.2
@export var run_speed: float = 7.0
## Calm, weighty feel (no twitch): ~0.3 s to full walk, slightly faster stop,
## body turns over ~0.25 s instead of snapping to the stick. Braking 16 m/s2
## (D-040): long enough for the distance-matched stop clip to read (0.55 m from
## 4.2 m/s, 1.5 m from a 7 m/s run), still under 0.45 s.
@export var acceleration: float = 14.0
@export var deceleration: float = 16.0
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
## EVA helmet outdoors; the surface scene sets this before adding the captain.
var wear_helmet := false
var _interact_left := 0.0

## Below this speed a start towards a direction far off the facing turns first.
const START_TURN_SPEED := 1.5
## Lean into curves: radians of roll per (rad/s yaw x m/s), capped at ~9 degrees.
const LEAN_PER_RAD_MPS := 0.0125
const LEAN_MAX := 0.157
## Seconds the console-press clip shows after an instant interaction.
const INTERACT_S := 1.1

const HELMET_PREFAB := "res://assets/Synty/PolygonSciFiWorlds/Prefabs/Characters/SM_Chr_ScifiWorlds_SpaceSuit_Male_01.tscn"
const HELMET_NODE := "SM_Chr_Attach_Helmet_Space_01"


func _ready() -> void:
	add_to_group("player")  # WaypointLayer measures distances from here
	collision_layer = 2
	collision_mask = 1 | 16  # buildings: ShapeCollider bodies on "world"; layer 8 is click-picking only
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
	if wear_helmet:
		_attach_helmet()
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
	# Starting off in a direction behind the body: pivot first (turn clip), then go,
	# instead of skating backwards while the body spins round (D-040).
	var facing := Vector3(-sin(visual_pivot.rotation.y), 0, -cos(visual_pivot.rotation.y))
	var off := facing.signed_angle_to(dir, Vector3.UP) if dir.length() > 0.1 else 0.0
	if target.length() > cur.length() and cur.length() < START_TURN_SPEED:
		rate *= lerpf(0.3, 1.0, clampf(cos(off), 0.0, 1.0))
	var hv := cur.move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	var yaw_before := visual_pivot.rotation.y
	if hv.length() > 0.2 or (dir.length() > 0.1 and absf(off) > deg_to_rad(40.0)):
		var head := hv if hv.length() > 0.2 else dir
		var want := atan2(-head.x, -head.z)
		visual_pivot.rotation.y = lerp_angle(visual_pivot.rotation.y, want, 1.0 - exp(-turn_speed * delta))
		_probe.rotation.y = visual_pivot.rotation.y
		_step_accum += hv.length() * delta
		if _step_accum > 1.6 and is_on_floor():
			_step_accum = 0.0
			AudioService.play_variant(footstep_slot, "SFX", -14.0)
	elif current_target and (_interact_left > 0.0 or _hold > 0.0):
		# Face the console / sample being worked on (the turn clip covers the pivot).
		var to := current_target.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.2:
			visual_pivot.rotation.y = lerp_angle(visual_pivot.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-turn_speed * 0.6 * delta))
			_probe.rotation.y = visual_pivot.rotation.y
	var yaw_rate := angle_difference(yaw_before, visual_pivot.rotation.y) / maxf(delta, 0.0001)
	_lean(yaw_rate, hv.length(), delta)
	_update_target()
	_update_hold(delta)
	_interact_left = maxf(_interact_left - delta, 0.0)
	if _anim.active():
		var spd := Vector2(velocity.x, velocity.z).length()
		var st := "idle"
		var stop_d := -1.0
		if _hold > 0.0:
			st = "sample"
		elif spd < 1.2 and dir.length() > 0.1 and absf(yaw_rate) > 2.0:
			st = "turn_l" if yaw_rate > 0.0 else "turn_r"
		elif dir.length() < 0.1 and spd > 0.05:
			stop_d = spd * spd / (2.0 * deceleration)  # braking at a constant rate: distance left
		elif spd > walk_speed + 0.3:
			st = "run"
		elif spd > 0.2:
			st = "walk"
		elif _interact_left > 0.0:
			st = "interact"
		_anim.update(st, absf(yaw_rate) if st.begins_with("turn") else spd, target.length(), stop_d)


## Leans the body into curves around the feet, like a runner (roll ~ yaw rate x speed).
func _lean(yaw_rate: float, spd: float, delta: float) -> void:
	if _slot == null:
		return
	var want := clampf(yaw_rate * spd * LEAN_PER_RAD_MPS, -LEAN_MAX, LEAN_MAX)
	_slot.rotation.z = lerpf(_slot.rotation.z, want, 1.0 - exp(-10.0 * delta))


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
		_interact_left = INTERACT_S
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


## Puts Synty's space helmet on the retargeted captain. The helmet is authored in
## the head-bone space of Synty's own rig, so its offset is carried over from that
## rig's rest pose to ours (the retarget re-orients bone axes). Presentation only;
## silently skipped on a clone without the purchased packs.
func _attach_helmet() -> void:
	var skels := _slot.find_children("GeneralSkeleton", "Skeleton3D", true, false)
	if skels.is_empty() or not ResourceLoader.exists(HELMET_PREFAB):
		return
	var sk: Skeleton3D = skels[0]
	var head := sk.find_bone("Head")
	var ref: Node = (load(HELMET_PREFAB) as PackedScene).instantiate()
	var ref_skels := ref.find_children("*", "Skeleton3D", true, false)
	var helm_src := ref.find_child(HELMET_NODE, true, false) as Node3D
	if head < 0 or ref_skels.is_empty() or helm_src == null:
		ref.free()
		return
	var rs: Skeleton3D = ref_skels[0]
	var ho := rs.get_bone_global_rest(rs.find_bone("Head"))
	var local := helm_src.transform
	var helm: Node3D = helm_src.duplicate()
	ref.free()
	var att := BoneAttachment3D.new()
	att.name = "Helmet"
	att.bone_name = "Head"
	sk.add_child(att)
	att.add_child(helm)
	helm.transform = sk.get_bone_global_rest(head).affine_inverse() * ho * local
