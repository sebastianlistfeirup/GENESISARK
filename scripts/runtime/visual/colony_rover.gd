@tool
class_name ColonyRover
extends Node3D
## Six-wheeled colony utility rover (D-065), Synty POLYGON Sci-Fi style: faceted
## white/orange/charcoal body, cab with windows, flatbed with crates behind a
## railing, cyan running strips, roof light bar and antenna, rocker-bogie
## suspension. Rebuilt with ProcBuilder from a Meshy image-to-3D scan (local only)
## measured with tools/rebuild/measure_scan.py; the scan's paint can be baked onto
## UV2 (tools/rebuild/bake_scan.py --yaw 90). Without the bake (fresh clone) the
## procedural shader carries the look.
##
## A puppet: whoever drives it (ColonyRovers in the colony, the viewer's stage)
## places the root on the ground under the MIDDLE axle facing +Z, and calls
## `drive(dt, v, accel, curvature)` each frame plus `set_ground()` with the six
## wheel ground heights. The rover then solves the rocker-bogie (each wheel on its
## own ground), spins and steers the wheels, and runs the sprung body, antenna and
## crates as damped springs on the accelerations (weight, follow-through). The hero
## beats (unload, point turn) are RoverTimeline poses applied with `pose_unload` /
## `pose_turn`. No collision anywhere: presentation only.

# --- Measurements (metres), scan scaled to 4.5 m long, front = +Z. Design space is
# centred on the scan's bounding box; the root sits under the middle axle (Z0).
const LENGTH := 4.5
const WHEEL_R := 0.445
const WHEEL_HW := 0.235       # half tyre width
const TRACK := 1.045          # wheel centre |x|
const WZ := [1.456, -0.37, -1.54]   # front, middle, rear axle (design z)
const Z0 := -0.37             # design z of the middle axle = the root
const PIVOT_X := 0.7          # rocker / bogie arms |x|
const ROCKER := Vector3(0.0, 0.74, 0.30)
const BOGIE := Vector3(0.0, 0.60, -0.955)
const BODY_PIVOT := Vector3(0.0, 0.95, -0.2)
const BED_HINGE := Vector3(0.0, 1.18, -2.12)
const DECK_Y := 1.25
const ANT_BASE := Vector3(0.48, 2.12, 0.0)
const ANT_LEN := 0.62
# Corner wheels' pivot-turn steer: tangent to a circle about the middle axle.
const STEER_PIVOT_F := 1.0757  # atan((1.456 + 0.37) / 1.045)
const STEER_PIVOT_R := 0.8418  # atan((1.54 - 0.37) / 1.045)

const C_HULL := 0
const C_ACCENT := 1
const C_FRAME := 2
const C_METAL := 3
const C_TYRE := 4
const C_GLASS := 5
const C_STRIP := 6
const C_LAMP := 7
const C_TAIL := 8
const C_BEACON := 9
const C_CRATE := 10
const C_CRATE_O := 11
const C_HAZARD := 12

const BAKE_DIR := "res://assets/imported/meshy/rover_baked/"
const BAKE_FILES := ["baked.glb", "baked_albedo.png", "baked_orm.png"]
const SHADER := preload("res://art/shaders/rover.gdshader")

## Editor preview: drive speed (m/s) with a bumpy road, and scrubbing the beats.
@export var preview_speed := 0.0
@export var preview_unload_ms := -1.0:
	set(v):
		preview_unload_ms = v
		if _built:
			pose_unload(maxf(v, 0.0))
@export var preview_turn_ms := -1.0:
	set(v):
		preview_turn_ms = v
		if _built:
			pose_turn(maxf(v, 0.0), 1.0)
## Mix of the baked scan paint (0 = procedural only).
@export_range(0.0, 1.0) var paint := 1.0:
	set(v):
		paint = v
		if _mat:
			_mat.set_shader_parameter("paint", v)

## Reduced motion: still drives, but no bounce exaggeration, dips or overshoots.
var reduced := false
## Desert worlds: dust from the wheels and dust on the lower body.
var dusty := false
## Night worlds: head lamps and their light.
var night := false
var baked := false

# Dynamics state (springs on the sprung body, antenna, crates).
var pitch := 0.0      # body pitch (rad, + = nose down), relative to the chassis
var pitch_v := 0.0
var roll := 0.0       # body roll (rad, + = left side up)
var roll_v := 0.0
var heave := 0.0
var heave_v := 0.0
var yaw_lag := 0.0    # body yaw lag in a turn (follow-through)
var yaw_lag_v := 0.0
var ant := Vector2.ZERO   # antenna bend (x: fore/aft, y: sideways)
var ant_v := Vector2.ZERO
var cargo := 0.0      # crates' shared shuffle on the springs (m, + = back)
var cargo_v := 0.0
var speed := 0.0
var spin := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]  # wheel spin angles FL, ML, RL, FR, MR, RR
var steer_f := 0.0
var steer_r := 0.0
var brake_glow := 0.0
var head_glow := 0.0
var depart_ms := -1.0  # >= 0 while pulling away (anticipation dip); set by the driver each frame

var _built := false
var _mat: ShaderMaterial       # this rover's body material (lamps are per rover)
var _chassis: Node3D
var _body: Node3D
var _bed: Node3D
var _gate: Node3D
var _crates: Array[Node3D] = []
var _crate_rest: Array[Vector3] = []
var _rockers: Array[Node3D] = []   # L, R
var _bogies: Array[Node3D] = []
var _steers: Array[Node3D] = []    # FL, RL, FR, RR
var _wheels: Array[Node3D] = []    # FL, ML, RL, FR, MR, RR (spin nodes)
var _ant_lo: Node3D
var _ant_hi: Node3D
var _head_light: SpotLight3D
var _dust: GPUParticles3D
var _ground := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _acc := 0.0
var _unload := {}
var _turn_steer := 0.0
var _turn_rate := 0.0
var _beacon := 0.0
var _beacon_beat := -1.0
var _step_left := 0.0
var _last_v := 0.0
var _last_lat := 0.0
var _last_yaw_rate := 0.0
var _yaw_acc := 0.0
var _tmp_g := PackedFloat32Array([0, 0, 0, 0, 0, 0])

static var _meshes: Dictionary = {}          # node name -> ArrayMesh (shared by every rover)
static var _template: ShaderMaterial          # body material template (bake textures live here)
static var _wheel_mat: ShaderMaterial         # wheels, arms, antenna (no lamps): shared
static var _bake_state := 0                   # 0 not tried, 1 loading, 2 done/absent
static var _live: Array = []                  # weakrefs of built rovers (bake arrives later)
## The game streams the local bake on a loader thread (set before adding rovers).
static var async_bake := false


func _ready() -> void:
	_build()
	set_process(Engine.is_editor_hint() or _bake_state == 1)


## Never leave a loader thread behind (scene change or quit mid-load): finish it here.
func _exit_tree() -> void:
	if _bake_state == 1:
		var res: Array = []
		for f: String in BAKE_FILES:
			res.append(ResourceLoader.load_threaded_get(BAKE_DIR + f))
		_apply_bake(res[0] as PackedScene, res[1] as Texture2D, res[2] as Texture2D)


# ------------------------------------------------------------------ API
## Ground under each wheel, relative to the root (FL, ML, RL, FR, MR, RR), already
## including road ruts. Call before drive().
func set_ground(h: PackedFloat32Array) -> void:
	for i: int in 6:
		_ground[i] = h[i]


## One frame of driving: v (m/s, signed), accel (m/s^2 along the heading), curvature
## of the path (1/m, + = turning left) and the yaw rate (rad/s) for the body's lag.
func drive(dt: float, v: float, accel: float, curvature: float, yaw_rate: float = INF) -> void:
	if not _built:
		return
	speed = v
	_acc = accel
	var yr := v * curvature if yaw_rate == INF else yaw_rate
	_yaw_acc = (yr - _last_yaw_rate) / maxf(dt, 0.001)
	_last_yaw_rate = yr
	_last_lat = v * yr
	# Corner wheels steer about the middle axle (it never steers).
	if _turn_steer <= 0.0:
		steer_f = atan(curvature * (float(WZ[0]) - Z0))
		steer_r = atan(curvature * (float(WZ[2]) - Z0))
	else:
		steer_f = lerpf(atan(curvature * (float(WZ[0]) - Z0)), -STEER_PIVOT_F, _turn_steer)
		steer_r = lerpf(atan(curvature * (float(WZ[2]) - Z0)), STEER_PIVOT_R, _turn_steer)
	# Wheel spin matched to ground speed, each wheel at its own radius in a curve
	# and opposite per side in a point turn.
	for i: int in 6:
		var side := 1.0 if i < 3 else -1.0
		var wz := float(WZ[i % 3]) - Z0
		var wx := side * TRACK
		var vw := v
		if absf(curvature) > 0.0005:
			var rho := 1.0 / curvature
			vw = v * Vector2(rho - wx, wz).length() / absf(rho)
		vw += -_turn_rate * Vector2(wx, wz).length() * side
		spin[i] = fmod(float(spin[i]) + vw * dt / WHEEL_R, TAU)
	_step_dynamics(dt)
	_apply()


## Unload beat at t (ms); call every frame while it runs.
func pose_unload(t: float) -> void:
	_unload = RoverTimeline.unload(t, reduced)
	_beacon_beat = float(_unload["beacon"])
	if t >= RoverTimeline.U_END:
		_unload = {}
	if Engine.is_editor_hint():
		_apply()


## Point-turn beat at t (ms): wheels swivel, spin opposite per side. The caller
## turns the root by RoverTimeline.turn(t)["yaw"] * dir.
func pose_turn(t: float, dir: float, moving: bool = true) -> void:
	var p := RoverTimeline.turn(t, reduced)
	_turn_steer = float(p["steer"]) if t < RoverTimeline.T_END else 0.0
	_turn_rate = float(p["rate"]) * dir if t < RoverTimeline.T_END and moving else 0.0
	_beacon_beat = float(p["beacon"]) if t < RoverTimeline.T_END else -1.0
	if Engine.is_editor_hint():
		drive(1.0 / 60.0, 0.0, 0.0, 0.0, _turn_rate)


func end_beats() -> void:
	_unload = {}
	_turn_steer = 0.0
	_turn_rate = 0.0


## Lamps follow the world: night = head lamps on with their light.
func set_world(is_night: bool, is_dusty: bool, dust_color: Color, light: float = 1.0) -> void:
	night = is_night
	dusty = is_dusty
	if _head_light:
		_head_light.visible = night
	if _dust:
		var pm := _dust.process_material as ParticleProcessMaterial
		pm.color = Color(dust_color.r * light, dust_color.g * light, dust_color.b * light, 0.8)
		_dust.emitting = false
	if _mat:
		_mat.set_shader_parameter("dirt", 0.55 if dusty else 0.0)
		_mat.set_shader_parameter("dirt_color", dust_color)
	if _wheel_mat:
		_wheel_mat.set_shader_parameter("dirt", 0.6 if dusty else 0.0)
		_wheel_mat.set_shader_parameter("dirt_color", dust_color)


## Brief flash of the head lamps (the rover "asks" the captain to step aside).
var _flash_t := -1.0


func flash_lamps() -> void:
	_flash_t = 0.0


func body_node() -> Node3D:
	return _body


func wheel_world(i: int) -> Vector3:
	return _wheels[i].global_position


## The wheel hubs' design-space rest offsets relative to the root (x, z).
static func wheel_offset(i: int) -> Vector2:
	var side := 1.0 if i < 3 else -1.0
	return Vector2(side * TRACK, float(WZ[i % 3]) - Z0)


func _process(delta: float) -> void:
	if _bake_state == 1:
		_poll_bake()
	if Engine.is_editor_hint():
		if not _built:
			return
		if preview_speed != 0.0:
			var t := Time.get_ticks_msec() * 0.001
			for i: int in 6:
				var z := float(WZ[i % 3]) + t * preview_speed
				_tmp_g[i] = 0.05 * sin(z * 2.1 + (0.0 if i < 3 else 1.3)) + 0.03 * sin(z * 5.3)
			set_ground(_tmp_g)
			drive(delta, preview_speed, 0.0, 0.0)
	elif _bake_state != 1:
		set_process(false)


# ------------------------------------------------------------------ dynamics
func _step_dynamics(dt: float) -> void:
	_step_left += dt
	var h := 1.0 / 120.0
	var amp := 0.45 if reduced else 1.0  # reduced motion: gentle, and critically damped
	var z_body := 1.0 if reduced else 0.42
	var dip := 0.0
	if depart_ms >= 0.0:
		dip = RoverTimeline.depart_dip(depart_ms, reduced)
	var jolt := float(_unload.get("jolt", 0.0))
	while _step_left >= h:
		_step_left -= h
		# Weight: nose dives on braking and squats when pulling away (pitch + = nose
		# down), leans out of curves, lags behind a point turn, bobs on the ruts.
		var r := RoverTimeline.spring_step(pitch, pitch_v, clampf(-_acc * 0.016, -0.045, 0.045) * amp + dip, 1.25, z_body, h)
		pitch = r.x
		pitch_v = r.y
		r = RoverTimeline.spring_step(roll, roll_v, clampf(_last_lat * 0.012, -0.03, 0.03) * amp, 1.1, z_body, h)
		roll = r.x
		roll_v = r.y
		r = RoverTimeline.spring_step(heave, heave_v, -jolt, 2.2, 1.0 if reduced else 0.35, h)
		heave = r.x
		heave_v = r.y
		r = RoverTimeline.spring_step(yaw_lag, yaw_lag_v, clampf(-_yaw_acc * 0.012, -0.03, 0.03) * amp, 0.9, z_body, h)
		yaw_lag = r.x
		yaw_lag_v = r.y
		# Antenna whips (secondary action): lighter, faster, barely damped.
		var ant_t := Vector2(clampf(-_acc * 0.06, -0.2, 0.2), clampf(_last_lat * 0.05, -0.2, 0.2)) * amp
		ant_t.x += pitch * 2.0
		var ax := RoverTimeline.spring_step(ant.x, ant_v.x, ant_t.x, 2.4, 1.0 if reduced else 0.16, h)
		var ay := RoverTimeline.spring_step(ant.y, ant_v.y, ant_t.y, 2.4, 1.0 if reduced else 0.16, h)
		ant = Vector2(ax.x, ay.x)
		ant_v = Vector2(ax.y, ay.y)
		# Crates shuffle on the bed a beat after the body (overlapping action).
		var c := RoverTimeline.spring_step(cargo, cargo_v, clampf(_acc * 0.006, -0.012, 0.012) * amp, 1.6, 1.0 if reduced else 0.3, h)
		cargo = c.x
		cargo_v = c.y
	# Lamps: brake lamps flare when slowing; head lamps at night (flash on request).
	var braking := _acc < -0.25 and absf(speed) > 0.05 or absf(speed) < 0.05
	brake_glow = lerpf(brake_glow, 1.6 if braking else 0.35, clampf(dt * 10.0, 0.0, 1.0))
	var head := 1.2 if night else 0.25
	if _flash_t >= 0.0:
		_flash_t += dt
		head += 1.3 * maxf(0.0, sin(_flash_t * TAU * 2.5)) if _flash_t < 0.8 else 0.0
		if _flash_t >= 0.8:
			_flash_t = -1.0
	head_glow = head
	if _beacon_beat >= 0.0:
		_beacon = _beacon_beat
		_beacon_beat = -1.0
	else:
		_beacon = maxf(_beacon - dt * 1.5, 0.0)


# ------------------------------------------------------------------ pose
func _apply() -> void:
	# Rocker-bogie: every wheel on its own ground (side view per side, then the
	# chassis heaves, pitches with the average of the rockers (the differential)
	# and rolls with the difference between the sides).
	var a_r := [0.0, 0.0]
	var a_b := [0.0, 0.0]
	var py := [0.0, 0.0]
	for s: int in 2:
		var yf := _ground[s * 3] + WHEEL_R
		var ym := _ground[s * 3 + 1] + WHEEL_R
		var yr := _ground[s * 3 + 2] + WHEEL_R
		var zf := float(WZ[0])
		var zm := float(WZ[1])
		var zr := float(WZ[2])
		var ab := asin(clampf((yr - ym) / (zm - zr), -0.6, 0.6))
		var bm := _rot_x(Vector2(BOGIE.y - WHEEL_R, BOGIE.z - zm), ab)  # mid hub -> bogie pivot
		var by := ym + bm.x
		var bz := zm + bm.y
		var rest := Vector2(BOGIE.y - WHEEL_R, BOGIE.z - zf)
		var want := Vector2(by - yf, bz - zf)
		var ar := atan2(rest.x, rest.y) - atan2(want.x, want.y)
		var fp := _rot_x(Vector2(ROCKER.y - WHEEL_R, ROCKER.z - zf), ar)
		a_r[s] = ar
		a_b[s] = ab
		py[s] = yf + fp.x
	var c_pitch := (float(a_r[0]) + float(a_r[1])) * 0.5
	var c_roll := asin(clampf((float(py[0]) - float(py[1])) / (2.0 * PIVOT_X), -0.5, 0.5))
	var c_heave := (float(py[0]) + float(py[1])) * 0.5 - ROCKER.y
	var piv := Vector3(0, ROCKER.y, ROCKER.z - Z0)
	var cb := Basis.from_euler(Vector3(c_pitch, 0.0, c_roll))
	_chassis.transform = Transform3D(cb, piv + Vector3(0, c_heave, 0) - cb * piv) * Transform3D(Basis(), Vector3(0, 0, -Z0))
	for s: int in 2:
		_rockers[s].rotation = Vector3(float(a_r[s]) - c_pitch, 0, 0)
		_bogies[s].rotation = Vector3(float(a_b[s]) - float(a_r[s]), 0, 0)
	# Wheels: corner steer, spin.
	_steers[0].rotation.y = steer_f
	_steers[2].rotation.y = -steer_f if _turn_steer > 0.0 else steer_f
	_steers[1].rotation.y = steer_r
	_steers[3].rotation.y = -steer_r if _turn_steer > 0.0 else steer_r
	for i: int in 6:
		_wheels[i].rotation.x = float(spin[i])
	# Sprung body on top of the chassis.
	var bed := float(_unload.get("bed", 0.0))
	var bb := Basis.from_euler(Vector3(pitch, yaw_lag, roll))
	_body.transform = Transform3D(bb, BODY_PIVOT + Vector3(0, heave, 0) - bb * BODY_PIVOT)
	_bed.rotation.x = -bed
	_gate.rotation.x = -float(_unload.get("gate", 0.0))
	var crates: Array = _unload.get("crates", [])
	var hop := float(_unload.get("hop", 0.0))
	for i: int in _crates.size():
		var off := cargo * (0.6 + 0.25 * i) + (float(crates[i]) if i < crates.size() else 0.0)
		_crates[i].position = _crate_rest[i] + Vector3(0, hop * (1.0 + 0.4 * i), -off)
	_ant_lo.rotation = Vector3(ant.x, 0, ant.y)
	_ant_hi.rotation = Vector3(ant.x * 1.6, 0, ant.y * 1.6)
	# Lamps and dust.
	if _mat:
		_mat.set_shader_parameter("head", head_glow)
		_mat.set_shader_parameter("brake", brake_glow)
		_mat.set_shader_parameter("beacon", _beacon)
	if _head_light and night:
		_head_light.light_energy = 5.0 * clampf(head_glow / 1.2, 0.5, 2.0)
	if _dust:
		var moving := absf(speed) + absf(_turn_rate) * 1.5
		var want := dusty and moving > 0.4
		if want != _dust.emitting:
			_dust.emitting = want
		_dust.amount_ratio = clampf(moving / 4.0, 0.15, 1.0)


## Rotate a side-view vector (y, z) by a rotation of `a` about +X.
static func _rot_x(yz: Vector2, a: float) -> Vector2:
	return Vector2(yz.x * cos(a) - yz.y * sin(a), yz.x * sin(a) + yz.y * cos(a))


# ------------------------------------------------------------------ build
func _build() -> void:
	if _built:
		return
	_built = true
	if _template == null:
		_template = ShaderMaterial.new()
		_template.shader = SHADER
		_template.resource_name = "rover"
		_wheel_mat = ShaderMaterial.new()
		_wheel_mat.shader = SHADER
		_wheel_mat.resource_name = "rover_wheel"
	if _meshes.is_empty():
		_build_meshes()
	_mat = _template.duplicate() as ShaderMaterial
	_mat.set_shader_parameter("paint", paint)
	_chassis = _node("Chassis", self)
	_chassis.add_child(_mi("FrameMesh"))
	var piv_node := func(nm: String, parent: Node3D, at: Vector3) -> Node3D:
		var n := _node(nm, parent)
		n.position = at
		return n
	for s: int in 2:
		var sx := 1.0 if s == 0 else -1.0
		var side := "L" if s == 0 else "R"
		var rk: Node3D = piv_node.call("Rocker" + side, _chassis, Vector3(sx * PIVOT_X, ROCKER.y, ROCKER.z))
		rk.add_child(_mi("RockerMesh", "Rocker" + side + "Mesh", Vector3(sx, 1, 1)))
		_rockers.append(rk)
		var front: Node3D = piv_node.call("SteerF" + side, rk, Vector3(sx * TRACK, WHEEL_R, float(WZ[0])) - rk.position)
		var bg: Node3D = piv_node.call("Bogie" + side, rk, Vector3(sx * PIVOT_X, BOGIE.y, BOGIE.z) - rk.position)
		bg.add_child(_mi("BogieMesh", "Bogie" + side + "Mesh", Vector3(sx, 1, 1)))
		_bogies.append(bg)
		var mid: Node3D = piv_node.call("HubM" + side, bg, Vector3(sx * TRACK, WHEEL_R, float(WZ[1])) - bg.position - rk.position)
		var rear: Node3D = piv_node.call("SteerR" + side, bg, Vector3(sx * TRACK, WHEEL_R, float(WZ[2])) - bg.position - rk.position)
		_steers.append(front)
		_steers.append(rear)
		for hub: Node3D in [front, mid, rear]:
			var w := _node("Spin", hub)
			w.add_child(_mi("WheelMesh", "Wheel" + side + str(_wheels.size() % 3)))
			_wheels.append(w)
	# _wheels order: FL, ML, RL, FR, MR, RR; _steers: FL, RL, FR, RR.
	_body = _node("Body", _chassis)
	_body.add_child(_mi("BodyMesh"))
	_bed = piv_node.call("Bed", _body, BED_HINGE)
	var bed_mesh := _mi("BedMesh")
	bed_mesh.position = -BED_HINGE
	_bed.add_child(bed_mesh)
	for i: int in 4:
		var c := _node("Crate%d" % i, _bed)
		var cm := _mi("Crate%dMesh" % i)
		c.add_child(cm)
		c.position = -BED_HINGE
		_crates.append(c)
		_crate_rest.append(c.position)
	_gate = piv_node.call("Gate", _bed, Vector3(0, DECK_Y, -2.12) - BED_HINGE)
	var gm := _mi("GateMesh")
	gm.position = -Vector3(0, DECK_Y, -2.12)
	_gate.add_child(gm)
	_ant_lo = piv_node.call("Antenna", _body, ANT_BASE)
	_ant_lo.add_child(_mi("AntennaLo"))
	_ant_hi = piv_node.call("AntennaTip", _ant_lo, Vector3(0, ANT_LEN * 0.5, 0))
	_ant_hi.add_child(_mi("AntennaHi"))
	_head_light = SpotLight3D.new()
	_head_light.name = "HeadLight"
	_head_light.position = Vector3(0, 1.0, 2.35)
	_head_light.rotation = Vector3(-0.3, PI, 0)
	_head_light.spot_range = 20.0
	_head_light.spot_angle = 38.0
	_head_light.spot_attenuation = 0.8
	_head_light.light_color = Color(0.85, 0.94, 1.0)
	_head_light.light_energy = 5.0
	_head_light.shadow_enabled = false
	_head_light.visible = false
	_head_light.add_to_group("no_export")
	_body.add_child(_head_light)
	_build_dust()
	_live = _live.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_live.append(weakref(self))
	_load_bake()
	_apply()


func _node(nm: String, parent: Node) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	parent.add_child(n)
	return n


func _mi(key: String, nm: String = "", flip: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm if nm != "" else key
	mi.mesh = _meshes[key]
	mi.scale = flip  # the right-hand arms are the left ones mirrored
	var wheelish := key in ["WheelMesh", "RockerMesh", "BogieMesh", "AntennaLo", "AntennaHi"]
	mi.material_override = _wheel_mat if wheelish else _mat
	mi.visibility_range_end = 170.0
	mi.visibility_range_end_margin = 10.0
	if key in ["AntennaLo", "AntennaHi", "RockerMesh", "BogieMesh"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 48
	_dust.lifetime = 1.7
	_dust.local_coords = false
	_dust.emitting = false
	_dust.visibility_aabb = AABB(Vector3(-8, -2, -12), Vector3(16, 8, 20))
	_dust.position = Vector3(0, 0.15, -0.6)
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.add_to_group("no_export")
	_dust.add_to_group("no_aabb")
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.1, 0.08, 1.1)
	pm.direction = Vector3(0, 1, -0.6)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, -0.15, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.color = Color(0.7, 0.6, 0.45, 0.55)
	_dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 0.8))
	tg.set_color(1, Color(1, 1, 1, 0.0))
	tex.gradient = tg
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	q.material = m
	_dust.draw_pass_1 = q
	_chassis.add_child(_dust)


# ---------------------------------------------------------------- meshes
static func _bx(b: ProcBuilder, c: Vector3, h: Vector3, ch: float = 0.02, basis: Basis = Basis()) -> void:
	b.box(Transform3D(basis, c), h, ch)


## Box between two points (beams, rails), square section half-size `hs`.
static func _beam(b: ProcBuilder, p0: Vector3, p1: Vector3, hs: Vector2, ch: float = 0.012) -> void:
	var d := p1 - p0
	var l := d.length()
	if l < 1e-4:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	b.box(Transform3D(Basis(x, y, z), (p0 + p1) * 0.5), Vector3(hs.x, hs.y, l * 0.5), ch)


## Lofted block through rings of four corners (-x back, +x back, +x front, -x front),
## bottom to top: the tapered cab with a bevel ring. Flat faces, the Synty look.
static func _loft(b: ProcBuilder, rings: Array) -> void:
	var c := Vector3.ZERO
	var n := 0
	for r: Array in rings:
		for q: Vector3 in r:
			c += q
			n += 1
	c /= float(n)
	var first: Array = rings[0]
	var last: Array = rings[rings.size() - 1]
	b.quad(first[0], first[1], first[2], first[3], c)
	b.quad(last[0], last[1], last[2], last[3], c)
	for k: int in rings.size() - 1:
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for i: int in 4:
			var j := (i + 1) % 4
			b.quad(r0[i], r0[j], r1[j], r1[i], c)


## Sub-rectangle (u0..u1, v0..v1) of a quad face a-b-c-d (a->b = u, a->d = v),
## lifted along the face normal: windows, panels and trims that sit proud.
static func _plate(b: ProcBuilder, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, u0: float, u1: float, v0: float, v1: float, lift: float, inside: Vector3) -> void:
	var f := func(u: float, v: float) -> Vector3:
		return a.lerp(bb, u).lerp(d.lerp(c, u), v)
	var n := (bb - a).cross(d - a).normalized()
	if n.dot((a + c) * 0.5 - inside) < 0.0:
		n = -n
	var q: Array[Vector3] = [f.call(u0, v0), f.call(u1, v0), f.call(u1, v1), f.call(u0, v1)]
	var top: Array[Vector3] = []
	for p: Vector3 in q:
		top.append(p + n * lift)
	b.quad(top[0], top[1], top[2], top[3], inside)
	for i: int in 4:
		var j := (i + 1) % 4
		b.quad(q[i], q[j], top[j], top[i], (q[0] + q[2]) * 0.5 - n * 0.2)


static func _crate(b: ProcBuilder, c: Vector3, h: Vector3, cls: int, tint: float) -> void:
	b.use("rover", tint, (cls + 0.5) / 16.0)
	_bx(b, c, h * Vector3(0.96, 0.96, 0.96), 0.015)
	b.use("rover", 0.45, (C_FRAME + 0.5) / 16.0)
	var e := 0.035
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_bx(b, c + Vector3(sx * (h.x - e), 0, sz * (h.z - e)), Vector3(e, h.y, e), 0.0)
		for sy: float in [-1.0, 1.0]:
			_bx(b, c + Vector3(sx * (h.x - e), sy * (h.y - e), 0), Vector3(e, e, h.z - e * 2.0), 0.0)
			_bx(b, c + Vector3(0, sy * (h.y - e), sx * (h.z - e)), Vector3(h.x - e * 2.0, e, e), 0.0)
	# X braces on the long sides (the scan's crates have them).
	for sx: float in [-1.0, 1.0]:
		var x := c.x + sx * (h.x + 0.004)
		_beam(b, Vector3(x, c.y - h.y + e * 2.0, c.z - h.z + e * 2.0), Vector3(x, c.y + h.y - e * 2.0, c.z + h.z - e * 2.0), Vector2(0.006, 0.022), 0.0)
		_beam(b, Vector3(x, c.y - h.y + e * 2.0, c.z + h.z - e * 2.0), Vector3(x, c.y + h.y - e * 2.0, c.z - h.z + e * 2.0), Vector2(0.006, 0.022), 0.0)


static func _cls(cls: int) -> float:
	return (cls + 0.5) / 16.0


static func _build_meshes() -> void:
	_meshes["BodyMesh"] = _build_body().commit_mesh({"rover": _template})
	_meshes["FrameMesh"] = _build_frame().commit_mesh({"rover": _template})
	_meshes["BedMesh"] = _build_bed().commit_mesh({"rover": _template})
	_meshes["GateMesh"] = _build_gate().commit_mesh({"rover": _template})
	var crates := [
		[Vector3(0.42, DECK_Y + 0.31, -0.62), Vector3(0.36, 0.31, 0.36), C_CRATE, 0.5],
		[Vector3(-0.42, DECK_Y + 0.33, -0.66), Vector3(0.34, 0.33, 0.34), C_CRATE_O, 0.55],
		[Vector3(0.12, DECK_Y + 0.66 + 0.26, -0.68), Vector3(0.3, 0.26, 0.3), C_CRATE, 0.62],
		[Vector3(0.0, DECK_Y + 0.21, -1.55), Vector3(0.42, 0.21, 0.3), C_CRATE_O, 0.42]]
	for i: int in crates.size():
		var cb := ProcBuilder.new()
		var cr: Array = crates[i]
		_crate(cb, cr[0], cr[1], int(cr[2]), float(cr[3]))
		_meshes["Crate%dMesh" % i] = cb.commit_mesh({"rover": _template})
	_meshes["WheelMesh"] = _build_wheel().commit_mesh({"rover_wheel": _wheel_mat})
	_meshes["RockerMesh"] = _build_rocker().commit_mesh({"rover_wheel": _wheel_mat})
	_meshes["BogieMesh"] = _build_bogie().commit_mesh({"rover_wheel": _wheel_mat})
	var a0 := ProcBuilder.new()
	a0.use("rover_wheel", 0.5, _cls(C_FRAME))
	a0.cylinder(Transform3D(Basis(), Vector3(0, -0.02, 0)), 0.035, 0.03, 8)
	a0.use("rover_wheel", 0.5, _cls(C_METAL))
	a0.cylinder(Transform3D(Basis(), Vector3(0, ANT_LEN * 0.25, 0)), 0.011, ANT_LEN * 0.25, 6)
	_meshes["AntennaLo"] = a0.commit_mesh({"rover_wheel": _wheel_mat})
	var a1 := ProcBuilder.new()
	a1.use("rover_wheel", 0.5, _cls(C_METAL))
	a1.cylinder(Transform3D(Basis(), Vector3(0, ANT_LEN * 0.25, 0)), 0.007, ANT_LEN * 0.25, 6)
	a1.use("rover_wheel", 0.5, _cls(C_TAIL))
	a1.dome(Vector3(0, ANT_LEN * 0.5, 0), Vector3.UP, 0.018, 6, 2)
	_meshes["AntennaHi"] = a1.commit_mesh({"rover_wheel": _wheel_mat})


## Cab, skirts, fenders, bumpers, lamps, roof gear (design space).
static func _build_body() -> ProcBuilder:
	var b := ProcBuilder.new()
	var C := func(cls: int, tint: float = 0.5) -> void:
		b.use("rover", tint, _cls(cls))
	# Lower body: charcoal core between the wheels, orange skirt above the wheel tops.
	C.call(C_FRAME, 0.4)
	_bx(b, Vector3(0, 0.86, 0.0), Vector3(0.72, 0.16, 2.14), 0.03)
	C.call(C_ACCENT, 0.5)
	b.prism_x(Transform3D(), -0.93, 0.93, PackedVector2Array([Vector2(-0.06, 0.99), Vector2(2.02, 0.99), Vector2(2.15, 1.12), Vector2(2.12, 1.38), Vector2(-0.06, 1.38)]))
	C.call(C_ACCENT, 0.42)
	_bx(b, Vector3(0, 1.08, -1.11), Vector3(0.93, 0.1, 1.05), 0.025)  # bed skirt
	# Upper cab: tapered white block, windscreen slope from the scan's side view.
	C.call(C_HULL, 0.5)
	var cab: Array[Vector3] = [Vector3(-0.9, 1.38, -0.06), Vector3(0.9, 1.38, -0.06), Vector3(0.9, 1.38, 2.12), Vector3(-0.9, 1.38, 2.12),
		Vector3(-0.77, 1.96, -0.05), Vector3(0.77, 1.96, -0.05), Vector3(0.77, 1.96, 1.52), Vector3(-0.77, 1.96, 1.52)]
	var cap: Array[Vector3] = [Vector3(-0.64, 2.07, 0.02), Vector3(0.64, 2.07, 0.02), Vector3(0.64, 2.07, 1.36), Vector3(-0.64, 2.07, 1.36)]
	_loft(b, [cab.slice(0, 4), cab.slice(4, 8), cap])
	var inside := Vector3(0, 1.7, 1.0)
	# Windscreen (charcoal frame band + dark glass), side windows, rear window.
	C.call(C_FRAME, 0.35)
	_plate(b, cab[3], cab[2], cab[6], cab[7], 0.04, 0.96, 0.08, 0.95, 0.012, inside)
	C.call(C_GLASS, 0.5)
	_plate(b, cab[3], cab[2], cab[6], cab[7], 0.09, 0.91, 0.16, 0.89, 0.022, inside)
	for s: int in 2:
		var sx := 1.0 if s == 0 else -1.0
		# Side face corners: back-bottom, front-bottom, front-top, back-top.
		var a := cab[1] if s == 0 else cab[0]
		var bq := cab[2] if s == 0 else cab[3]
		var cq := cab[6] if s == 0 else cab[7]
		var dq := cab[5] if s == 0 else cab[4]
		C.call(C_FRAME, 0.35)
		_plate(b, a, bq, cq, dq, 0.5, 0.86, 0.14, 0.86, 0.01, inside)  # big side window frame
		C.call(C_GLASS, 0.55)
		_plate(b, a, bq, cq, dq, 0.53, 0.84, 0.2, 0.8, 0.02, inside)
		C.call(C_FRAME, 0.35)
		_plate(b, a, bq, cq, dq, 0.08, 0.3, 0.52, 0.84, 0.01, inside)  # small rear window
		C.call(C_GLASS, 0.5)
		_plate(b, a, bq, cq, dq, 0.1, 0.28, 0.57, 0.8, 0.02, inside)
		# Door seam and handle, vent, mirror, step.
		C.call(C_FRAME, 0.5)
		_bx(b, Vector3(sx * 0.932, 1.19, 0.62), Vector3(0.006, 0.17, 0.008), 0.0)
		_bx(b, Vector3(sx * 0.932, 1.19, 1.36), Vector3(0.006, 0.17, 0.008), 0.0)
		C.call(C_METAL, 0.6)
		_bx(b, Vector3(sx * 0.94, 1.3, 1.18), Vector3(0.012, 0.018, 0.07), 0.005)
		C.call(C_FRAME, 0.45)
		_bx(b, Vector3(sx * 0.935, 1.17, 0.3), Vector3(0.01, 0.1, 0.16), 0.005)
		for k: int in 4:
			_bx(b, Vector3(sx * 0.948, 1.11 + k * 0.04, 0.3), Vector3(0.006, 0.008, 0.14), 0.0)
		_beam(b, Vector3(sx * 0.86, 1.62, 1.82), Vector3(sx * 1.04, 1.68, 1.86), Vector2(0.014, 0.014))
		_bx(b, Vector3(sx * 1.07, 1.6, 1.86), Vector3(0.03, 0.11, 0.06), 0.012)
		_bx(b, Vector3(sx * 0.86, 0.8, 0.5), Vector3(0.1, 0.025, 0.28), 0.01)
		# Cyan running strips: along the cab's shoulder line and the bed skirt.
		C.call(C_STRIP, 0.5)
		_bx(b, Vector3(sx * 0.932, 1.395, 0.96), Vector3(0.006, 0.014, 1.0), 0.0)
		_bx(b, Vector3(sx * 0.937, 1.165, -1.1), Vector3(0.006, 0.014, 1.0), 0.0)
		# Charcoal "C" trim on the orange cab skirt (the scan's raised outline).
		C.call(C_FRAME, 0.4)
		_bx(b, Vector3(sx * 0.936, 1.03, 0.97), Vector3(0.008, 0.012, 0.42), 0.0)
		_bx(b, Vector3(sx * 0.936, 1.12, 0.56), Vector3(0.008, 0.1, 0.012), 0.0)
		# Fenders: faceted arcs over the front wheel and one long one over the tandem.
		C.call(C_FRAME, 0.45)
		_fender(b, sx, float(WZ[0]), 0.4, 2.75)
		_fender(b, sx, float(WZ[1]), PI * 0.5, 2.75)
		_fender(b, sx, float(WZ[2]), 0.4, PI * 0.5)
		_bx(b, Vector3(sx * 1.05, 0.445 + 0.58 + 0.02, (float(WZ[1]) + float(WZ[2])) * 0.5), Vector3(0.25, 0.022, (float(WZ[1]) - float(WZ[2])) * 0.5), 0.008)
		# Tail lamps, cab marker lamps and the bumper head lamps (with bezels).
		C.call(C_FRAME, 0.3)
		_bx(b, Vector3(sx * 0.78, 1.05, -2.2), Vector3(0.13, 0.065, 0.03), 0.01)
		C.call(C_TAIL, 0.5)
		_bx(b, Vector3(sx * 0.78, 1.05, -2.225), Vector3(0.1, 0.045, 0.015), 0.006)
		C.call(C_LAMP, 0.5)
		_bx(b, Vector3(sx * 0.7, 1.33, 2.135), Vector3(0.06, 0.025, 0.012), 0.005)
		C.call(C_FRAME, 0.3)
		_bx(b, Vector3(sx * 0.79, 0.76, 2.31), Vector3(0.16, 0.07, 0.03), 0.012)
		C.call(C_LAMP, 0.5)
		_bx(b, Vector3(sx * 0.79, 0.76, 2.335), Vector3(0.13, 0.05, 0.012), 0.006)
		C.call(C_LAMP, 0.5)
		_bx(b, Vector3(sx * 0.6, 2.09, 1.43), Vector3(0.07, 0.025, 0.04), 0.008)  # roof corner lamps
	# Grille and front bumper with bull bar.
	C.call(C_FRAME, 0.35)
	_bx(b, Vector3(0, 1.17, 2.15), Vector3(0.55, 0.14, 0.03), 0.01)
	C.call(C_FRAME, 0.2)
	for k: int in 4:
		_bx(b, Vector3(0, 1.08 + k * 0.06, 2.18), Vector3(0.5, 0.012, 0.012), 0.0)
	C.call(C_FRAME, 0.45)
	_bx(b, Vector3(0, 0.74, 2.2), Vector3(1.0, 0.12, 0.11), 0.03)
	for sx: float in [-1.0, 1.0]:
		_bx(b, Vector3(sx * 0.42, 1.02, 2.28), Vector3(0.05, 0.2, 0.05), 0.012)
	_bx(b, Vector3(0, 1.2, 2.28), Vector3(0.47, 0.04, 0.05), 0.012)
	C.call(C_METAL, 0.5)
	for sx: float in [-1.0, 1.0]:
		b.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.25, 0.6, 2.33)), 0.03, 0.04, 8)
	# Rear bumper with hazard stripes, step plate.
	C.call(C_HAZARD, 0.5)
	_bx(b, Vector3(0, 0.82, -2.2), Vector3(0.95, 0.09, 0.07), 0.02)
	# Roof: hatch box, light bar on posts, beacon.
	C.call(C_FRAME, 0.4)
	_bx(b, Vector3(0, 2.1, 0.5), Vector3(0.48, 0.045, 0.4), 0.02)
	_bx(b, Vector3(0, 2.16, 1.28), Vector3(0.56, 0.03, 0.07), 0.01)
	for sx: float in [-1.0, 1.0]:
		_bx(b, Vector3(sx * 0.4, 2.1, 1.28), Vector3(0.025, 0.04, 0.025), 0.005)
	C.call(C_LAMP, 0.5)
	for k: int in 4:
		_bx(b, Vector3(-0.39 + 0.26 * k, 2.225, 1.3), Vector3(0.1, 0.04, 0.035), 0.01)
	C.call(C_FRAME, 0.3)
	b.frustum(Transform3D(Basis(), Vector3(-0.42, 2.14, 0.25)), 0.0, 0.07, 0.04, 0.07, 6, 0.0, false, true)
	C.call(C_BEACON, 0.5)
	b.frustum(Transform3D(Basis(), Vector3(-0.42, 2.18, 0.25)), 0.0, 0.055, 0.08, 0.045, 6, 0.0, false, true)
	return b


## Faceted fender arc over a wheel at design z `wz`, angles a0..a1 (0 = toward +z).
static func _fender(b: ProcBuilder, sx: float, wz: float, a0: float, a1: float) -> void:
	var r := 0.6
	var n := 3
	for i: int in n:
		var t0 := lerpf(a0, a1, float(i) / n)
		var t1 := lerpf(a0, a1, float(i + 1) / n)
		var p0 := Vector3(sx * 1.05, 0.445 + sin(t0) * r, wz + cos(t0) * r)
		var p1 := Vector3(sx * 1.05, 0.445 + sin(t1) * r, wz + cos(t1) * r)
		var d := (p1 - p0).normalized()
		var ext := d * 0.02
		_beam(b, p0 - ext, p1 + ext, Vector2(0.25, 0.022), 0.008)


## Chassis frame under the body: rails, cross members, pivot housings.
static func _build_frame() -> ProcBuilder:
	var b := ProcBuilder.new()
	b.use("rover", 0.3, _cls(C_FRAME))
	_bx(b, Vector3(0, 0.62, -0.05), Vector3(0.5, 0.1, 2.0), 0.02)
	for z: float in [1.6, 0.3, -0.955, -1.9]:
		_bx(b, Vector3(0, 0.66, z), Vector3(0.66, 0.06, 0.08), 0.01)
	b.use("rover", 0.55, _cls(C_METAL))
	for sx: float in [-1.0, 1.0]:
		b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 0.62, ROCKER.y, ROCKER.z)), 0.075, 0.07, 10)
	return b


static func _build_rocker() -> ProcBuilder:
	var b := ProcBuilder.new()
	var piv := Vector3(PIVOT_X, ROCKER.y, ROCKER.z)
	var f := Vector3(PIVOT_X, WHEEL_R + 0.08, float(WZ[0])) - piv
	var bg := Vector3(PIVOT_X, BOGIE.y, BOGIE.z) - piv
	b.use("rover_wheel", 0.45, _cls(C_FRAME))
	_beam(b, Vector3.ZERO, f, Vector2(0.045, 0.06))
	_beam(b, Vector3.ZERO, bg, Vector2(0.045, 0.06))
	b.use("rover_wheel", 0.55, _cls(C_METAL))
	b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), 0.08, 0.06, 10)
	b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), bg), 0.065, 0.06, 10)
	# Knuckle over the front wheel: post down to the hub, stub out to it.
	var hub := Vector3(TRACK, WHEEL_R, float(WZ[0])) - piv
	b.use("rover_wheel", 0.45, _cls(C_FRAME))
	_beam(b, f, Vector3(f.x + 0.1, f.y, f.z), Vector2(0.05, 0.05))
	b.use("rover_wheel", 0.55, _cls(C_METAL))
	b.cylinder(Transform3D(Basis(), Vector3(f.x + 0.12, f.y - 0.04, f.z)), 0.05, 0.07, 8)
	b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), hub - Vector3(0.17, 0, 0)), 0.045, 0.06, 8)
	return b


static func _build_bogie() -> ProcBuilder:
	var b := ProcBuilder.new()
	var piv := Vector3(PIVOT_X, BOGIE.y, BOGIE.z)
	var m := Vector3(PIVOT_X, WHEEL_R + 0.06, float(WZ[1])) - piv
	var r := Vector3(PIVOT_X, WHEEL_R + 0.06, float(WZ[2])) - piv
	b.use("rover_wheel", 0.4, _cls(C_FRAME))
	_beam(b, m, Vector3.ZERO, Vector2(0.04, 0.055))
	_beam(b, Vector3.ZERO, r, Vector2(0.04, 0.055))
	b.use("rover_wheel", 0.55, _cls(C_METAL))
	for p: Vector3 in [m, r]:
		b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), p + Vector3(0.1, -0.06, 0)), 0.045, 0.1, 8)
	return b


## Chunky off-road wheel (axis X), symmetric so one mesh serves all six: tyre with
## chevron tread blocks, white rim, charcoal hub cap, bolts on both faces.
static func _build_wheel() -> ProcBuilder:
	var b := ProcBuilder.new()
	var ax := Basis(Vector3.BACK, -PI * 0.5)  # lathe axis Y -> X
	b.use("rover_wheel", 0.5, _cls(C_TYRE))
	var R := WHEEL_R - 0.02
	b.lathe([Vector2(0.27, -0.215), Vector2(0.34, -WHEEL_HW), Vector2(R - 0.04, -WHEEL_HW), Vector2(R, -WHEEL_HW + 0.05),
		Vector2(R, WHEEL_HW - 0.05), Vector2(R - 0.04, WHEEL_HW), Vector2(0.34, WHEEL_HW), Vector2(0.27, 0.215)], 16, Transform3D(ax, Vector3.ZERO))
	var n := 16
	for i: int in n:
		var a := TAU * (float(i) + 0.5) / n
		var rad := Vector3(0, cos(a), sin(a))
		var tan := Vector3(0, -sin(a), cos(a))
		var bs := Basis(Vector3.RIGHT, tan, rad).orthonormalized()
		var half := Vector3(0.1, 0.07, 0.03)
		for row: float in [-1.0, 1.0]:
			var shift := 0.035 * row * (1.0 if i % 2 == 0 else -1.0)
			b.use("rover_wheel", 0.3 + 0.08 * float(i % 2), _cls(C_TYRE))
			b.box(Transform3D(bs, rad * (R + 0.005) + Vector3(row * 0.115, 0, 0) + tan * shift), half, 0.0)
	b.use("rover_wheel", 0.62, _cls(C_HULL))
	b.cylinder(Transform3D(ax, Vector3.ZERO), 0.275, 0.205, 12, false)
	b.use("rover_wheel", 0.4, _cls(C_FRAME))
	b.cylinder(Transform3D(ax, Vector3.ZERO), 0.1, 0.225, 8, false)
	b.use("rover_wheel", 0.55, _cls(C_METAL))
	for s: float in [-1.0, 1.0]:
		for k: int in 6:
			var a := TAU * k / 6.0
			b.dome(Vector3(s * 0.207, cos(a) * 0.17, sin(a) * 0.17), Vector3(s, 0, 0), 0.02, 6, 2)
	return b


## Bed: deck, rails, headboard (tips about the rear hinge with the crates).
static func _build_bed() -> ProcBuilder:
	var b := ProcBuilder.new()
	b.use("rover", 0.35, _cls(C_FRAME))
	_bx(b, Vector3(0, 1.215, -1.11), Vector3(0.95, 0.035, 1.02), 0.012)
	b.use("rover", 0.5, _cls(C_METAL))
	for k: int in 5:
		_bx(b, Vector3(-0.72 + 0.36 * k, 1.253, -1.11), Vector3(0.02, 0.006, 0.98), 0.0)
	b.use("rover", 0.42, _cls(C_FRAME))
	var zs := [-0.16, -0.72, -1.28, -1.84]
	for sx: float in [-1.0, 1.0]:
		for z: float in zs:
			_bx(b, Vector3(sx * 0.91, 1.49, z), Vector3(0.028, 0.24, 0.028), 0.006)
		_bx(b, Vector3(sx * 0.91, 1.72, -1.03), Vector3(0.03, 0.025, 0.9), 0.008)
		_bx(b, Vector3(sx * 0.91, 1.47, -1.03), Vector3(0.022, 0.018, 0.88), 0.006)
	# Headboard behind the cab with an X brace.
	_bx(b, Vector3(0, 1.72, -0.16), Vector3(0.9, 0.025, 0.03), 0.008)
	_bx(b, Vector3(0, 1.47, -0.16), Vector3(0.9, 0.018, 0.022), 0.006)
	for sx: float in [-1.0, 1.0]:
		_beam(b, Vector3(sx * 0.85, 1.28, -0.16), Vector3(0, 1.69, -0.16), Vector2(0.015, 0.02), 0.004)
	# Stop bar the crates knock against when the bed tips.
	b.use("rover", 0.55, _cls(C_METAL))
	_bx(b, Vector3(0, 1.29, -2.0), Vector3(0.88, 0.035, 0.03), 0.008)
	return b


## Tailgate rail (hinged at the deck's rear edge, swings down).
static func _build_gate() -> ProcBuilder:
	var b := ProcBuilder.new()
	b.use("rover", 0.42, _cls(C_FRAME))
	for sx: float in [-1.0, -0.33, 0.33, 1.0]:
		_bx(b, Vector3(sx * 0.88, 1.49, -2.12), Vector3(0.025, 0.23, 0.025), 0.006)
	_bx(b, Vector3(0, 1.72, -2.12), Vector3(0.92, 0.025, 0.03), 0.008)
	_bx(b, Vector3(0, 1.47, -2.12), Vector3(0.9, 0.018, 0.022), 0.006)
	b.use("rover", 0.5, _cls(C_HAZARD))
	_bx(b, Vector3(0, 1.3, -2.125), Vector3(0.9, 0.045, 0.018), 0.006)
	return b


# ---------------------------------------------------------------- bake (local)
## Baked paint from the scan (local only, never committed): swap in the meshes that
## carry UV2 and feed the textures. Missing files = procedural look (fresh clone).
## Streams on a loader thread in the game; tools and the editor load synchronously.
func _load_bake() -> void:
	if _bake_state != 0:
		return
	_bake_state = 2
	if "--no-bake" in OS.get_cmdline_user_args() or (DisplayServer.get_name() == "headless" and not Engine.is_editor_hint() and not "--bake" in OS.get_cmdline_user_args()):
		return  # nothing is drawn headless (tests): skip the paint
	for f: String in BAKE_FILES:
		if not ResourceLoader.exists(BAKE_DIR + f):
			return
	var threaded := async_bake and not Engine.is_editor_hint()
	if not threaded:
		_apply_bake(load(BAKE_DIR + BAKE_FILES[0]) as PackedScene, load(BAKE_DIR + BAKE_FILES[1]) as Texture2D, load(BAKE_DIR + BAKE_FILES[2]) as Texture2D)
		return
	for f: String in BAKE_FILES:
		ResourceLoader.load_threaded_request(BAKE_DIR + f)
	_bake_state = 1
	set_process(true)


func _poll_bake() -> void:
	for f: String in BAKE_FILES:
		var st := ResourceLoader.load_threaded_get_status(BAKE_DIR + f)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if st != ResourceLoader.THREAD_LOAD_LOADED:
			_bake_state = 2
			return
	_bake_state = 2
	var res: Array = []
	for f: String in BAKE_FILES:
		res.append(ResourceLoader.load_threaded_get(BAKE_DIR + f))
	_apply_bake(res[0] as PackedScene, res[1] as Texture2D, res[2] as Texture2D)


static func _apply_bake(ps: PackedScene, alb: Texture2D, orm: Texture2D) -> void:
	_bake_state = 2
	if ps == null or alb == null or orm == null:
		return
	var src := ps.instantiate()
	var found: Dictionary = {}
	for n: Node in src.find_children("*", "MeshInstance3D", true, false):
		found[str(n.name)] = (n as MeshInstance3D).mesh
	src.free()
	var swapped := 0
	for key: String in _meshes.keys():
		if not found.has(key):
			continue
		var mesh := found[key] as Mesh
		if _tri_count(mesh) != _tri_count(_meshes[key]):
			continue  # stale bake (the rebuild changed since): keep the procedural mesh
		for s: int in mesh.get_surface_count():
			mesh.surface_set_material(s, _template)
		_meshes[key] = mesh
		swapped += 1
	if swapped == 0:
		return
	_template.set_shader_parameter("baked_albedo", alb)
	_template.set_shader_parameter("baked_orm", orm)
	for w: WeakRef in _live:
		var r := w.get_ref() as ColonyRover
		if r != null:
			r._take_bake(alb, orm)


func _take_bake(alb: Texture2D, orm: Texture2D) -> void:
	baked = true
	_mat.set_shader_parameter("baked_albedo", alb)
	_mat.set_shader_parameter("baked_orm", orm)
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if _meshes.has(str(m.name)):
			m.mesh = _meshes[str(m.name)]


static func _tri_count(mesh: Mesh) -> int:
	var n := 0
	for s: int in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
