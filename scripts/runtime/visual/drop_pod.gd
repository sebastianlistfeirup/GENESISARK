@tool
class_name DropPod
extends Node3D
## Energy-cell supply drop pod (D-056): the drone reserve as a moment. A compact
## Synty-style cargo pod descends on retro thrusters, hovers (anticipation), drops,
## lands with weight (struts compress, it rocks across its feet, dust ring), then
## the hatch unlocks with a hiss, strains, snaps open with a small energy burst and
## an energy cell rises out, hovers and zips into the captain's suit. The lights
## dim and the pod stays as a prop. Presentation only: the domain has already
## granted the refill (GameSession.cmd_drone_refill); no collision, never blocks.
##
## Rebuilt with ProcBuilder from a Meshy image-to-3D scan (local only) measured
## with tools/rebuild/measure_scan.py; the scan's paint can be baked onto UV2
## (tools/rebuild/bake_scan.py). Without the bake (fresh clone) the procedural
## shader carries the look. The hero beats are pure functions of time in
## DropPodTimeline, mirrored by the web viewer.

signal impact(strength: float)
signal hatch_snapped
signal cell_delivered
signal finished
## Every timeline beat as it plays (incoming, impact, unlock, strain, snap, burst,
## zip, arrive, done): the owner hangs sounds on them (D-064). Not fired by skip().
signal beat(beat_name: String)

# --- Measurements (metres) from measure_scan.py, scan scaled to 1.20 m tall ---
const WALL_APO := 0.505     # octagon apothem of the wall core (panels sit proud to ~0.515)
const WALL_Y0 := 0.45       # bottom of the vertical walls
const WALL_Y1 := 0.93       # top of the walls (cyan band just below)
const SHOULDER_APO := 0.335
const SHOULDER_Y := 1.095
const TOP_Y := 1.13         # lid seat
const LID_APO := 0.30
const HATCH_APO := 0.2
const BELLY_Y := 0.13
const BELLY_APO := 0.36
const HIP_R := 0.535          # strut hinge on the hull (cardinal faces, like the scan)
const HIP_Y := 0.52
const FOOT_R := 0.665       # pad centre radius at rest (pads reach 0.78, scan 0.78)
const FOOT_Y := 0.05        # pad top / ball joint height
const STROKE := 0.07        # strut travel: unloaded legs hang this much lower
const FOLD := 1.05          # stowed leg swing (rad) before deployment
const SLEEVE_L := 0.3
const ROD_L := 0.27
const WELL_APO := 0.2
const WELL_FLOOR := 0.47
const LID_MAX := 1.95       # fully open hatch angle (rad)
const CELL_R := 0.1
const CELL_HH := 0.18
const TARGET_OFFSET := Vector3(0, 1.2, 0)  # captain's chest above his feet
const BAKE_DIR := "res://assets/imported/meshy/drop_pod_baked/"
const BAKE_FILES := ["baked.glb", "baked_albedo.png", "baked_orm.png"]

const COL_HULL := Color(0.86, 0.86, 0.84)
const COL_ACCENT := Color(0.92, 0.37, 0.05)
const COL_FRAME := Color(0.2, 0.21, 0.23)
const COL_METAL := Color(0.55, 0.57, 0.6)
const COL_GLOW := Color(0.2, 0.85, 1.0)

## Scrub the sequence in the editor (ms); -1 = rest pose.
@export var preview_ms := -1.0:
	set(v):
		preview_ms = v
		if is_inside_tree() and _built:
			_apply(DropPodTimeline.pose(maxf(v, 0.0), preview_short) if v >= 0.0 else _rest_pose(), maxf(v, 0.0))
@export var preview_short := false
## Mix of the baked scan paint (0 = procedural only).
@export_range(0.0, 1.0) var paint := 1.0:
	set(v):
		paint = v
		for m: ShaderMaterial in _mats.values():
			m.set_shader_parameter("paint", v)

## Where the cell flies (the captain); TARGET_OFFSET is added. Null = straight up.
var target: Node3D
var dust_color := Color(0.62, 0.56, 0.46)
var light_level := 1.0
var short := false
## Stream the local bake on a loader thread (the game sets this before adding the pod).
var async_bake := false
var playing := false
var t_ms := -1.0
var baked := false

var _built := false
var _mats: Dictionary = {}
var _body: Node3D
var _lid_pivot: Node3D
var _sleeves: Array[Node3D] = []
var _rods: Array[Node3D] = []
var _pads: Array[Node3D] = []
var _foot_ground: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _flames: Array[MeshInstance3D] = []
var _flame_mat: ShaderMaterial
var _thrust_light: OmniLight3D
var _flash: OmniLight3D
var _cell: Node3D
var _cell_mat: ShaderMaterial
var _cell_light: OmniLight3D
var _marker: MeshInstance3D
var _burst_ring: MeshInstance3D
var _absorb: Node3D
var _absorb_ring: MeshInstance3D
var _wash: MultiMeshInstance3D
var _dust: MultiMeshInstance3D
var _steam: MultiMeshInstance3D
var _sparks: MultiMeshInstance3D
var _absorb_sparks: MultiMeshInstance3D
var _trail: MultiMeshInstance3D
var _trail_pts: Array = []  # [Vector3, age_s]
var _fired: Dictionary = {}
var _zip_from := Vector3.ZERO
var _clock := 0.0
var _warming := false
var _bake_pending := false


func _ready() -> void:
	_build()
	_apply(_rest_pose(), 0.0)
	set_process(_bake_pending)


# ------------------------------------------------------------------ API
## Start the sequence. `reduced` = the short reduced-motion version.
func play(reduced: bool = false) -> void:
	if not _built:
		_build()
	short = reduced
	playing = true
	t_ms = 0.0
	_fired.clear()
	_trail_pts.clear()
	visible = true
	_apply(DropPodTimeline.pose(0.0, short), 0.0)
	set_process(true)


func is_busy() -> bool:
	return playing


## Jump to the end: landed, open, lights dimmed, cell delivered (silently except
## for the delivery signal, so the suit still gets its feedback).
func skip() -> void:
	if not playing:
		return
	var ev := DropPodTimeline.events(short)
	for k: String in ev.keys():
		if not _fired.has(k):
			_fired[k] = true
			if k == "arrive":
				cell_delivered.emit()
	t_ms = DropPodTimeline.duration(short)
	_apply(DropPodTimeline.pose(t_ms, short), t_ms)
	_finish()


## Deterministic scrub for captures and probes (no events fired).
func set_time(ms: float, reduced: bool = false) -> void:
	short = reduced
	t_ms = ms
	visible = true
	_apply(DropPodTimeline.pose(ms, reduced), ms)


## Sample the terrain under each foot so the pads stand on uneven ground.
## height_at(x, z) -> world height. Call after the pod is placed and turned.
func fit_ground(height_at: Callable) -> void:
	for i: int in 4:
		var w := global_transform * (_dir(i) * FOOT_R)
		_foot_ground[i] = float(height_at.call(w.x, w.z)) - global_position.y


func foot_world(i: int) -> Vector3:
	return _pads[i].global_position


## Draw every material and effect once, microscopic, just in front of `cam`, so
## all pipelines are compiled before the real drop (no hitch at the hero moment).
func warm_up(cam: Camera3D) -> void:
	_warming = true
	set_time(DropPodTimeline.SNAP + 100.0)
	global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.002), cam.global_position - cam.global_basis.z * 1.5)
	for n: Node3D in [_wash, _dust, _steam, _sparks, _absorb_sparks, _trail, _marker, _burst_ring, _absorb, _cell, _thrust_light, _flash]:
		n.visible = true
	for f: MeshInstance3D in _flames:
		f.visible = true


func end_warm_up() -> void:
	if not _warming:
		return
	_warming = false
	scale = Vector3.ONE
	visible = false
	_finish_fx()


func _process(delta: float) -> void:
	if _bake_pending:
		_poll_bake()
	if not playing:
		set_process(_bake_pending)
		return
	_clock += delta
	t_ms += delta * 1000.0
	var p := DropPodTimeline.pose(t_ms, short)
	_apply(p, t_ms)
	var ev := DropPodTimeline.events(short)
	for k: String in ev.keys():
		if not _fired.has(k) and t_ms >= float(ev[k]):
			_fired[k] = true
			beat.emit(k)
			match k:
				"impact": impact.emit(0.4 if short else 1.0)
				"snap": hatch_snapped.emit()
				"arrive": cell_delivered.emit()
	if t_ms >= DropPodTimeline.duration(short):
		_finish()


func _finish() -> void:
	playing = false
	set_process(_bake_pending)
	_finish_fx()
	finished.emit()


func _finish_fx() -> void:
	for n: Node3D in [_wash, _dust, _steam, _sparks, _absorb_sparks, _trail, _marker, _burst_ring, _absorb]:
		n.visible = false
	for f: MeshInstance3D in _flames:
		f.visible = false
	_thrust_light.visible = false
	_flash.visible = false


# ------------------------------------------------------------------ pose
func _rest_pose() -> Dictionary:
	var p := DropPodTimeline.pose(0.0)
	p["alt"] = 0.0
	p["drift"] = Vector2.ZERO
	p["yaw"] = 0.0
	p["roll"] = 0.0
	p["pitch"] = 0.0
	p["thrust"] = 0.0
	p["ring"] = 0.0
	p["deploy"] = 1.0
	p["scorch"] = 0.0
	return p


static func _dir(i: int) -> Vector3:
	var a := PI * 0.5 * i
	return Vector3(sin(a), 0, cos(a))


func _foot_local(i: int, deploy: float) -> Vector3:
	var d := _dir(i)
	var hip := d * HIP_R + Vector3(0, HIP_Y, 0)
	var ext := d * FOOT_R + Vector3(0, FOOT_Y - STROKE, 0)
	var folded := hip + (ext - hip).rotated(d.cross(Vector3.UP).normalized(), -FOLD)
	return folded.lerp(ext, deploy)


func _body_xf(p: Dictionary) -> Transform3D:
	var dr: Vector2 = p["drift"]
	var sy := float(p["squash"])
	var tremble := float(p["tremble"]) * 0.0045 * sin(t_ms * 0.088)
	var b := Basis.from_euler(Vector3(float(p["pitch"]), float(p["yaw"]), float(p["roll"]) + tremble))
	b = b * Basis.from_scale(Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy)))
	return Transform3D(b, Vector3(dr.x, float(p["alt"]), dr.y))


func _apply(p: Dictionary, t: float) -> void:
	if not _built:
		return
	var bx := _body_xf(p)
	_body.transform = bx
	var inv := bx.affine_inverse()
	var deploy := float(p["deploy"])
	for i: int in 4:
		var d := _dir(i)
		var hip := d * HIP_R + Vector3(0, HIP_Y, 0)
		var fw := bx * _foot_local(i, deploy)
		var floor_y := _foot_ground[i] + FOOT_Y
		var grounded := fw.y <= floor_y
		if grounded:
			fw.y = floor_y
		var fb := inv * fw
		var axis := (hip - fb).normalized()
		var side := Vector3.UP.cross(d).normalized()
		var fwd := side.cross(axis).normalized()
		var lb := Basis(axis.cross(fwd).normalized(), axis, fwd)
		_sleeves[i].transform = Transform3D(lb, hip)
		_rods[i].transform = Transform3D(lb, fb)
		var pb := Basis(Vector3.UP, PI * 0.5 * i + float(p["yaw"])) if grounded else bx.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5 * i)
		_pads[i].transform = Transform3D(pb, fw)
	_lid_pivot.rotation.z = float(p["lid"]) * LID_MAX  # side hinge: the lid flips to the pod's left, edge-on to the captain
	var glow := float(p["glow"])
	(_mats["glow"] as ShaderMaterial).set_shader_parameter("glow", glow)
	var scorch := float(p["scorch"])
	for key: String in ["hull", "accent", "frame", "metal"]:
		(_mats[key] as ShaderMaterial).set_shader_parameter("scorch", scorch)
	# Thrusters, their light and the ground wash.
	var thrust := float(p["thrust"])
	for f: MeshInstance3D in _flames:
		f.visible = thrust > 0.02
		(f.get_parent() as Node3D).scale = Vector3(1.0, 0.25 + 0.75 * thrust, 1.0)  # grows from the nozzle
	_flame_mat.set_shader_parameter("thrust", clampf(thrust, 0.0, 1.3))
	_flame_mat.set_shader_parameter("clock", t * 0.001)
	_thrust_light.visible = thrust > 0.02
	_thrust_light.light_energy = 0.8 * thrust
	var alt := float(p["alt"])
	var wash := thrust * clampf(1.0 - alt / 4.0, 0.0, 1.0)
	_wash.visible = wash > 0.02
	_set_fx(_wash, {"t": t * 0.001, "strength": wash})
	# Landing marker.
	var ring := float(p["ring"])
	_marker.visible = ring > 0.01
	_set_fx(_marker, {"alpha": ring * (0.75 + 0.25 * sin(t * 0.008)), "spin": t * 0.00004})
	# Impact dust.
	var dt := float(p["dust_t"])
	_dust.visible = dt >= 0.0 and dt < 2.4
	_set_fx(_dust, {"t": maxf(dt, 0.0), "strength": 0.5 if short else 1.0})
	# Hiss from the hatch seam.
	var hiss := float(p["hiss"])
	_steam.visible = hiss > 0.01
	_set_fx(_steam, {"t": t * 0.001, "strength": hiss})
	# Hatch burst: short, non-blinding flash, sparks and a ring.
	var btv := float(p["burst_t"])
	var burst := btv >= 0.0 and btv < 1.4
	_sparks.visible = burst and not short
	_set_fx(_sparks, {"t": maxf(btv, 0.0)})
	_flash.visible = burst
	_flash.light_energy = (0.6 if short else 1.6) * exp(-maxf(btv, 0.0) * 1000.0 / 70.0) if burst else 0.0
	_burst_ring.visible = burst and btv < 0.45
	var br := DropPodTimeline.ease_out3(clampf(btv / 0.4, 0.0, 1.0))
	_set_fx(_burst_ring, {"radius": 0.12 + 0.33 * br, "alpha": (1.0 - br) * (0.5 if short else 0.85)})
	# The cell: rides in the well, rises, hovers, zips to the target.
	var zip := float(p["cell_zip"])
	var vis := float(p["cell_vis"]) > 0.5
	_cell.visible = vis
	var spin := Basis(Vector3.UP, float(p["cell_spin"])).scaled(Vector3.ONE * float(p["cell_scale"]))
	var cell_pos: Vector3
	if zip < 0.0:
		cell_pos = bx * Vector3(0, float(p["cell_y"]), 0)
		_zip_from = cell_pos
	else:
		var from := _zip_start()
		var to := _target_local()
		var ctrl := (from + to) * 0.5 + Vector3(0, 0.55 + 0.08 * from.distance_to(to), 0)
		cell_pos = from.lerp(ctrl, zip).lerp(ctrl.lerp(to, zip), zip)
	_cell.transform = Transform3D(spin, cell_pos)
	_cell_mat.set_shader_parameter("glow", 1.0 + 0.35 * sin(t * 0.006))
	_cell_light.light_energy = 0.9 * clampf(float(p["lid"]) * 1.5, 0.0, 1.0) if vis else 0.0  # sealed in the hull until the hatch opens
	# Trail behind the cell while it is out of the pod.
	_update_trail(global_transform * cell_pos, vis and t >= (DropPodTimeline.S_CELL_A if short else DropPodTimeline.CELL_A + 200.0), t)
	# Delivery: a soft ring and a few motes at the suit.
	var at := float(p["arrive_t"])
	_absorb.visible = at >= 0.0 and at < 0.8
	if _absorb.visible:
		_absorb.global_position = (target.global_position + TARGET_OFFSET) if is_instance_valid(target) else global_transform * _target_local()
		var ka := DropPodTimeline.ease_out3(clampf(at / 0.5, 0.0, 1.0))
		_set_fx(_absorb_ring, {"radius": 0.12 + 0.3 * ka, "alpha": (1.0 - ka) * 0.8})
		_set_fx(_absorb_sparks, {"t": at})
		_absorb_sparks.visible = not short


func _zip_start() -> Vector3:
	var a := DropPodTimeline.S_ZIP_A if short else DropPodTimeline.ZIP_A
	var p := DropPodTimeline.pose(a, short)
	return _body_xf(p) * Vector3(0, float(p["cell_y"]), 0)


func _target_local() -> Vector3:
	if is_instance_valid(target) and target.is_inside_tree() and is_inside_tree():
		return to_local(target.global_position + TARGET_OFFSET)
	return Vector3(0, 3.5, 2.5)


func _update_trail(world_pos: Vector3, emit: bool, t: float) -> void:
	var mm := _trail.multimesh
	var dt := 1.0 / 60.0
	for e: Array in _trail_pts:
		e[1] = float(e[1]) + dt
	if emit:
		if _trail_pts.is_empty() or (_trail_pts[0][0] as Vector3).distance_to(world_pos) > 0.025:
			_trail_pts.push_front([world_pos, 0.0])
	while _trail_pts.size() > mm.instance_count or (not _trail_pts.is_empty() and float(_trail_pts[-1][1]) > 0.45):
		_trail_pts.pop_back()
	_trail.visible = not _trail_pts.is_empty()
	for i: int in mm.instance_count:
		if i < _trail_pts.size():
			var e: Array = _trail_pts[i]
			var age := float(e[1])
			var wob := Vector3(sin(t * 0.01 + i), cos(t * 0.013 + i * 1.7), sin(t * 0.008 + i * 2.3)) * 0.02 * age / 0.45
			mm.set_instance_transform(i, Transform3D(Basis(), (e[0] as Vector3) + wob))
			mm.set_instance_custom_data(i, Color(clampf(1.0 - age / 0.45, 0.0, 1.0) * 0.9, 1.0 - 0.6 * age / 0.45, 0, 0))
		else:
			mm.set_instance_custom_data(i, Color(0, 0, 0, 0))


func _set_fx(n: GeometryInstance3D, params: Dictionary) -> void:
	var m := n.material_override as ShaderMaterial
	for k: String in params.keys():
		m.set_shader_parameter(k, params[k])


# ------------------------------------------------------------------ build
func _mat(key: String, col: Color, rough: float, metal: float = 0.0, emit: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/drop_pod.gdshader")
	m.resource_name = key
	m.set_shader_parameter("albedo", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("roughness_v", rough)
	m.set_shader_parameter("metallic_v", metal)
	m.set_shader_parameter("paint", paint)
	if emit > 0.0:
		m.set_shader_parameter("albedo", Vector3(col.r, col.g, col.b) * 0.3)  # unlit strips read dark teal, the glow is emission
		m.set_shader_parameter("emission_color", Vector3(col.r, col.g, col.b))
		m.set_shader_parameter("emission_energy", emit)
		m.set_shader_parameter("edge_wear", 0.0)
	return m


static func _r(apo: float) -> float:
	return apo / cos(PI / 8.0)


## Slanted octagon face panel (belly/shoulder): face i between (apo0, y0) and (apo1, y1).
static func _slant_panel(b: ProcBuilder, i: int, apo0: float, y0: float, apo1: float, y1: float, inset: float, lift: float) -> void:
	var a := PI * 0.25 * i
	var d := Vector3(sin(a), 0, cos(a))
	var side := Vector3.UP.cross(d).normalized()
	var p0 := d * apo0 + Vector3(0, y0, 0)
	var p1 := d * apo1 + Vector3(0, y1, 0)
	var up := (p1 - p0).normalized()
	var n := side.cross(up).normalized()
	if n.dot(d) < 0.0:
		n = -n
	var h0 := apo0 * tan(PI / 8.0) - inset
	var h1 := apo1 * tan(PI / 8.0) - inset
	var q0 := p0.lerp(p1, inset / (p1 - p0).length() * 1.2) + n * lift
	var q1 := p1.lerp(p0, inset / (p1 - p0).length() * 1.2) + n * lift
	var inside := (q0 + q1) * 0.5 - n * 0.2
	b.quad(q0 - side * h0, q0 + side * h0, q1 + side * h1, q1 - side * h1, inside)
	# Thin sides so the panel reads as a plate, not a decal.
	var back := -n * lift
	b.quad(q0 - side * h0 + back, q0 - side * h0, q1 - side * h1, q1 - side * h1 + back, inside)
	b.quad(q0 + side * h0, q0 + side * h0 + back, q1 + side * h1 + back, q1 + side * h1, inside)
	b.quad(q1 - side * h1, q1 + side * h1, q1 + side * h1 + back, q1 - side * h1 + back, inside)
	b.quad(q0 - side * h0 + back, q0 + side * h0 + back, q0 + side * h0, q0 - side * h0, inside)


func _build() -> void:
	if _built:
		return
	_built = true
	_mats = {
		"hull": _mat("hull", COL_HULL, 0.55),
		"accent": _mat("accent", COL_ACCENT, 0.5),
		"frame": _mat("frame", COL_FRAME, 0.45, 0.25),
		"metal": _mat("metal", COL_METAL, 0.35, 0.6),
		"glow": _mat("glow", COL_GLOW, 0.3, 0.0, 1.5)}
	(_mats["frame"] as ShaderMaterial).set_shader_parameter("stripe_color", Vector3(0.9, 0.62, 0.12))
	(_mats["accent"] as ShaderMaterial).set_shader_parameter("stripe_color", Vector3(0.1, 0.1, 0.11))
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_body.add_child(_build_hull().commit("Hull", _mats))
	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidPivot"
	_lid_pivot.position = Vector3(-LID_APO, TOP_Y, 0)
	_body.add_child(_lid_pivot)
	var lid := _build_lid().commit("Lid", _mats)
	lid.position = Vector3(LID_APO, 0, 0)
	_lid_pivot.add_child(lid)
	for i: int in 4:
		var s := Node3D.new()
		s.name = "Leg%d" % i
		_body.add_child(s)
		s.add_child(_build_sleeve().commit("Sleeve%d" % i, _mats))
		_sleeves.append(s)
		var r := Node3D.new()
		r.name = "Rod%d" % i
		_body.add_child(r)
		r.add_child(_build_rod().commit("RodMesh%d" % i, _mats))
		_rods.append(r)
		var pad := Node3D.new()
		pad.name = "Foot%d" % i
		add_child(pad)
		pad.add_child(_build_pad().commit("Pad%d" % i, _mats))
		_pads.append(pad)
	_build_cell()
	_build_fx()
	_load_bake()


func _build_hull() -> ProcBuilder:
	var b := ProcBuilder.new()
	var I := Transform3D()
	# Belly: charcoal core, white slanted panels, nozzles and side ports.
	b.use("frame", 0.45)
	b.frustum(I, BELLY_Y, _r(BELLY_APO), WALL_Y0, _r(WALL_APO + 0.01), 8, 0.0, true)
	for i: int in 8:
		b.use("hull", 0.4 + 0.2 * float(i % 3) / 2.0)
		_slant_panel(b, i, BELLY_APO, BELLY_Y, WALL_APO + 0.01, WALL_Y0, 0.035, 0.012)
	for k: int in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var d := Vector3(sin(a), 0, cos(a))
		b.use("metal", 0.5)
		b.cylinder(Transform3D(Basis(), d * 0.19 + Vector3(0, BELLY_Y - 0.03, 0)), 0.062, 0.035, 10, false)
		b.use("frame", 0.2)
		b.cylinder(Transform3D(Basis(), d * 0.19 + Vector3(0, BELLY_Y - 0.066, 0)), 0.045, 0.002, 10)
		# Round side ports on the diagonal belly faces (the scan's "eyes").
		var pn := (d * 0.32 + Vector3(0, -0.145, 0)).normalized()
		var pc := d * ((BELLY_APO + WALL_APO) * 0.5 + 0.02) + Vector3(0, (BELLY_Y + WALL_Y0) * 0.5, 0)
		var pb := Basis(pn.cross(Vector3.UP).normalized(), pn, pn.cross(Vector3.UP).normalized().cross(pn)).orthonormalized()
		b.use("frame", 0.6)
		b.cylinder(Transform3D(pb, pc), 0.05, 0.02, 10)
		b.use("metal", 0.6)
		b.dome(pc + pn * 0.02, pn, 0.034, 8, 2)
	# Trim rings.
	b.use("frame", 0.5)
	b.frustum(I, WALL_Y0 - 0.02, _r(WALL_APO + 0.018), WALL_Y0 + 0.035, _r(WALL_APO + 0.018), 8)
	b.frustum(I, WALL_Y0 - 0.02, _r(WALL_APO + 0.01), WALL_Y0 - 0.02, _r(WALL_APO + 0.018), 8)
	b.frustum(I, WALL_Y1 - 0.025, _r(WALL_APO + 0.018), WALL_Y1 + 0.02, _r(WALL_APO + 0.018), 8)
	# Walls: charcoal core with orange / white panels, cyan seams and a cyan band.
	b.frustum(I, WALL_Y0, _r(WALL_APO), WALL_Y1, _r(WALL_APO), 8)
	var half := WALL_APO * tan(PI / 8.0)
	for i: int in 8:
		var a := PI * 0.25 * i
		var d := Vector3(sin(a), 0, cos(a))
		var bs := Basis(Vector3.UP, a)
		var orange := i % 2 == 0 or i == 3 or i == 7
		var py0 := WALL_Y0 + 0.05
		var py1 := WALL_Y1 - 0.085
		if i % 2 == 0:
			py0 = WALL_Y0 + 0.17  # room for the strut bracket under the panel
		b.use("accent" if orange else "hull", 0.35 + 0.3 * float((i * 5) % 7) / 6.0)
		b.box(Transform3D(bs, d * (WALL_APO + 0.006) + Vector3(0, (py0 + py1) * 0.5, 0)), Vector3(half - 0.04, (py1 - py0) * 0.5, 0.009), 0.006)
		b.use("glow", 0.5)
		b.box(Transform3D(bs, d * (WALL_APO + 0.008) + Vector3(0, WALL_Y1 - 0.055, 0)), Vector3(half - 0.045, 0.014, 0.006), 0.003)
		var ca := a + PI / 8.0
		var cd := Vector3(sin(ca), 0, cos(ca))
		b.box(Transform3D(Basis(Vector3.UP, ca), cd * (_r(WALL_APO) - 0.004) + Vector3(0, (WALL_Y0 + 0.06 + WALL_Y1 - 0.09) * 0.5, 0)), Vector3(0.012, (WALL_Y1 - WALL_Y0 - 0.15) * 0.5, 0.012), 0.004)
		if i % 2 == 0:
			# Strut bracket: a charcoal "boot" frame on the cardinal faces.
			b.use("frame", 0.35)
			b.box(Transform3D(bs, d * (WALL_APO + 0.015) + Vector3(0, WALL_Y0 + 0.07, 0)), Vector3(0.125, 0.1, 0.024), 0.012)
			b.use("frame", 0.15)
			b.box(Transform3D(bs, d * (WALL_APO + 0.03) + Vector3(0, WALL_Y0 + 0.055, 0)), Vector3(0.09, 0.075, 0.014), 0.006)
	# Shoulder: slanted white panels in a charcoal frame.
	b.use("frame", 0.5)
	b.frustum(I, WALL_Y1 + 0.02, _r(WALL_APO + 0.018), SHOULDER_Y, _r(SHOULDER_APO + 0.01), 8)
	for i: int in 8:
		b.use("hull", 0.45 + 0.1 * float(i % 2))
		_slant_panel(b, i, WALL_APO + 0.018, WALL_Y1 + 0.02, SHOULDER_APO + 0.01, SHOULDER_Y, 0.032, 0.01)
	# Top deck: charcoal ring with orange segments around the hatch seat.
	b.use("frame", 0.5)
	b.frustum(I, SHOULDER_Y, _r(SHOULDER_APO + 0.01), TOP_Y, _r(SHOULDER_APO), 8)
	b.frustum(I, TOP_Y, _r(SHOULDER_APO), TOP_Y, _r(LID_APO + 0.008), 8)
	for i: int in 8:
		var a := PI * 0.25 * i
		var d := Vector3(sin(a), 0, cos(a))
		var side := Vector3.UP.cross(d)
		var o0 := SHOULDER_APO - 0.012
		var o1 := LID_APO + 0.02
		var y := TOP_Y + 0.006
		b.use("accent", 0.45 + 0.1 * float(i % 2))
		var w0 := o0 * tan(PI / 8.0) - 0.022
		var w1 := o1 * tan(PI / 8.0) - 0.022
		var down := Vector3(0, y - 0.2, 0)
		b.quad(d * o0 + side * w0 + Vector3(0, y, 0), d * o0 - side * w0 + Vector3(0, y, 0), d * o1 - side * w1 + Vector3(0, y, 0), d * o1 + side * w1 + Vector3(0, y, 0), down)
		b.quad(d * o0 + side * w0 + Vector3(0, y, 0), d * o0 + side * w0 + Vector3(0, TOP_Y, 0), d * o0 - side * w0 + Vector3(0, TOP_Y, 0), d * o0 - side * w0 + Vector3(0, y, 0), Vector3(0, y, 0))
	# Hatch seat and the cell's well (lit cradle at the bottom).
	b.use("frame", 0.2)
	b.frustum(I, TOP_Y - 0.012, _r(LID_APO + 0.008), TOP_Y - 0.012, _r(WELL_APO), 8)
	b.frustum(I, TOP_Y - 0.012, _r(LID_APO + 0.008), TOP_Y, _r(LID_APO + 0.008), 8, 0.0, false, false, true)
	b.frustum(I, WELL_FLOOR, _r(WELL_APO), TOP_Y - 0.012, _r(WELL_APO), 8, 0.0, false, false, true)
	b.use("frame", 0.1)
	b.frustum(I, WELL_FLOOR, _r(WELL_APO), WELL_FLOOR, 0.0, 8)
	b.use("glow", 0.5)
	b.frustum(I, WELL_FLOOR + 0.004, _r(0.13), WELL_FLOOR + 0.004, _r(0.105), 8)
	for k: int in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var d := Vector3(sin(a), 0, cos(a))
		b.box(Transform3D(Basis(Vector3.UP, a), d * (WELL_APO - 0.006) + Vector3(0, (WELL_FLOOR + TOP_Y) * 0.5 - 0.04, 0)), Vector3(0.03, 0.17, 0.004), 0.002)
	return b


func _build_lid() -> ProcBuilder:
	# Local to the hinge-centred lid node: y = 0 on the seat, centre at the origin.
	var b := ProcBuilder.new()
	var I := Transform3D()
	b.use("frame", 0.55)
	b.frustum(I, 0.0, _r(LID_APO), 0.02, _r(LID_APO - 0.012), 8, 0.0, true)
	b.use("frame", 0.35)
	b.frustum(I, 0.02, _r(LID_APO - 0.012), 0.02, _r(HATCH_APO + 0.02), 8)
	for i: int in 8:
		var a := PI * 0.25 * i
		var d := Vector3(sin(a), 0, cos(a))
		var side := Vector3.UP.cross(d)
		var o0 := LID_APO - 0.03
		var o1 := HATCH_APO + 0.03
		b.use("accent", 0.45 + 0.1 * float(i % 2), 1.0 if i == 0 else 0.0)
		var w0 := o0 * tan(PI / 8.0) - 0.018
		var w1 := o1 * tan(PI / 8.0) - 0.018
		var y := 0.027
		b.quad(d * o0 + side * w0 + Vector3(0, y, 0), d * o0 - side * w0 + Vector3(0, y, 0), d * o1 - side * w1 + Vector3(0, y, 0), d * o1 + side * w1 + Vector3(0, y, 0), Vector3(0, -0.2, 0))
		b.quad(d * o0 + side * w0 + Vector3(0, y, 0), d * o0 + side * w0 + Vector3(0, 0.02, 0), d * o0 - side * w0 + Vector3(0, 0.02, 0), d * o0 - side * w0 + Vector3(0, y, 0), Vector3(0, y, 0))
	b.use("frame", 0.45)
	b.frustum(I, 0.02, _r(HATCH_APO + 0.02), 0.032, _r(HATCH_APO), 8)
	b.use("hull", 0.55)
	b.frustum(I, 0.032, _r(HATCH_APO), 0.038, _r(HATCH_APO - 0.03), 8, 0.0, false, true)
	# Handle (scan: an arch across the hatch, top at 1.20 m).
	b.use("frame", 0.6)
	var hb := Basis(Vector3.UP, PI * 0.25)  # the scan's handle runs corner to corner
	for s: float in [-1.0, 1.0]:
		b.box(Transform3D(hb * Basis(Vector3.FORWARD, s * 0.4), hb * Vector3(s * 0.12, 0.048, 0)), Vector3(0.015, 0.026, 0.018), 0.005)
	b.box(Transform3D(hb, hb * Vector3(0, 0.064, 0)), Vector3(0.115, 0.009, 0.018), 0.005)
	# Underside: glowing seal ring and a dark plate, seen when it is open.
	b.use("glow", 0.5)
	b.frustum(I, -0.004, _r(LID_APO - 0.03), -0.004, _r(LID_APO - 0.05), 8)
	b.use("hull", 0.5)
	b.frustum(I, -0.006, 0.0, -0.006, _r(LID_APO - 0.065), 8)
	b.use("metal", 0.5)
	for k: int in 4:
		var a := PI * 0.5 * k + PI * 0.25
		b.dome(Vector3(sin(a), 0, cos(a)) * (LID_APO - 0.075) + Vector3(0, -0.007, 0), Vector3.DOWN, 0.018, 6, 2)
	# Hinge knuckles on the left edge (the lid flips sideways, edge-on to the captain).
	for s: float in [-1.0, 1.0]:
		b.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-LID_APO + 0.004, 0.012, s * 0.09)), 0.017, 0.035, 8)
	return b


func _build_sleeve() -> ProcBuilder:
	# Upper strut, from the hinge (origin) down its -Y axis; X = across the leg.
	var b := ProcBuilder.new()
	b.use("metal", 0.5)
	b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), 0.03, 0.075, 10)
	b.use("frame", 0.5)
	b.box(Transform3D(Basis(), Vector3(0, -SLEEVE_L * 0.5, -0.005)), Vector3(0.1, SLEEVE_L * 0.5 + 0.01, 0.03), 0.01)
	b.use("hull", 0.55)
	b.box(Transform3D(Basis(), Vector3(0, -SLEEVE_L * 0.34, 0.024)), Vector3(0.08, SLEEVE_L * 0.31, 0.007), 0.005)
	b.use("accent", 0.5)
	b.box(Transform3D(Basis(), Vector3(0, -SLEEVE_L * 0.83, 0.024)), Vector3(0.08, SLEEVE_L * 0.13, 0.007), 0.005)
	return b


func _build_rod() -> ProcBuilder:
	# Lower strut, from the foot ball joint (origin) up its +Y axis into the sleeve.
	var b := ProcBuilder.new()
	b.use("metal", 0.55)
	b.cylinder(Transform3D(Basis(), Vector3(0, ROD_L * 0.5, -0.004)), 0.026, ROD_L * 0.5, 10)
	b.use("frame", 0.4)
	b.box(Transform3D(Basis(), Vector3(0, 0.04, 0)), Vector3(0.05, 0.04, 0.03), 0.008)
	return b


func _build_pad() -> ProcBuilder:
	# Foot pad, local Z = outward. Origin at the ball joint (pad top).
	var b := ProcBuilder.new()
	b.use("frame", 0.5)
	b.box(Transform3D(Basis(), Vector3(0, -FOOT_Y + 0.02, 0.0)), Vector3(0.12, 0.02, 0.125), 0.008)
	b.use("accent", 0.5, 1.0)
	b.box(Transform3D(Basis(), Vector3(0, -FOOT_Y + 0.046, 0.0)), Vector3(0.108, 0.008, 0.113), 0.004)
	b.use("hull", 0.6)
	b.box(Transform3D(Basis(), Vector3(0, -FOOT_Y + 0.056, 0.0)), Vector3(0.078, 0.004, 0.083), 0.002)
	b.use("metal", 0.5)
	b.dome(Vector3(0, -0.004, 0), Vector3.UP, 0.036, 8, 3)
	return b


func _build_cell() -> void:
	_cell = Node3D.new()
	_cell.name = "Cell"
	_cell.add_to_group("no_export")
	add_child(_cell)
	_cell_mat = _mat("cell_glow", Color(0.42, 0.95, 1.0), 0.2, 0.0, 4.5)
	var b := ProcBuilder.new()
	var I := Transform3D()
	b.use("cell_glow", 0.5)
	b.frustum(I, -CELL_HH * 0.72, _r(CELL_R * 0.72), CELL_HH * 0.72, _r(CELL_R * 0.72), 8, PI / 8.0)
	b.use("frame", 0.4)
	for s: float in [-1.0, 1.0]:
		b.frustum(I, s * CELL_HH * 0.72, _r(CELL_R), s * CELL_HH, _r(CELL_R * 0.8), 8, 0.0, false, true)
		b.frustum(I, s * CELL_HH * 0.72, _r(CELL_R * 0.72), s * CELL_HH * 0.72, _r(CELL_R), 8)
		b.use("metal", 0.6)
		b.cylinder(Transform3D(Basis(), Vector3(0, s * (CELL_HH + 0.012), 0)), 0.026, 0.014, 8)
		b.use("frame", 0.4)
	b.use("accent", 0.5)
	for k: int in 4:
		var a := PI * 0.5 * k + PI * 0.25
		b.box(Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * CELL_R * 0.9), Vector3(0.011, CELL_HH * 0.74, 0.008), 0.003)
	var mi := b.commit("CellMesh", {"cell_glow": _cell_mat, "frame": _mats["frame"], "metal": _mats["metal"], "accent": _mats["accent"]})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cell.add_child(mi)
	# Soft halo so the cell reads as energy from the gameplay camera.
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 0.75)
	halo.mesh = q
	var hm := StandardMaterial3D.new()
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.no_depth_test = false
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.95, 1.0, 0.38))
	g.set_color(1, Color(0.2, 0.7, 1.0, 0.0))
	gt.gradient = g
	hm.albedo_texture = gt
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cell.add_child(halo)
	_cell_light = OmniLight3D.new()
	_cell_light.light_color = COL_GLOW
	_cell_light.omni_range = 2.6
	_cell_light.light_energy = 0.9
	_cell_light.shadow_enabled = false
	_cell.add_child(_cell_light)


func _multimesh(count: int, shader: Shader, rng_seed: int, aabb: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i: int in count:
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = aabb
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = shader
	mi.material_override = m
	mi.add_to_group("no_export")
	mi.visible = false
	return mi


func _ring_plane(size: float, params: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/pod_ring.gdshader")
	for k: String in params.keys():
		m.set_shader_parameter(k, params[k])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("no_export")
	mi.visible = false
	return mi


func _build_fx() -> void:
	var dust_sh := preload("res://art/shaders/pod_dust.gdshader")
	var spark_sh := preload("res://art/shaders/pod_spark.gdshader")
	# Thruster plumes + their light (under the belly, ride with the body).
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = preload("res://art/shaders/pod_flame.gdshader")
	for k: int in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var f := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.012
		cm.height = 0.7
		cm.radial_segments = 10
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		f.mesh = cm
		f.material_override = _flame_mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_to_group("no_export")
		var pivot := Node3D.new()
		pivot.position = Vector3(sin(a), 0, cos(a)) * 0.19 + Vector3(0, BELLY_Y - 0.068, 0)
		pivot.add_to_group("no_export")
		_body.add_child(pivot)
		f.position = Vector3(0, -0.35, 0)
		var holder := Node3D.new()
		holder.add_child(f)
		pivot.add_child(holder)
		_flames.append(f)
		f.visible = false
	_thrust_light = OmniLight3D.new()
	_thrust_light.light_color = Color(0.55, 0.85, 1.0)
	_thrust_light.omni_range = 3.5
	_thrust_light.position = Vector3(0, -0.15, 0)
	_thrust_light.shadow_enabled = false
	_thrust_light.visible = false
	_body.add_child(_thrust_light)
	# Ground wash under the thrusters (loops), impact dust ring (one shot), hiss.
	_wash = _multimesh(28, dust_sh, 11, AABB(Vector3(-5, -1, -5), Vector3(10, 4, 10)))
	add_child(_wash)
	_set_fx(_wash, {"loop_rate": 1.3, "life": 0.75, "r0": 0.35, "radial_speed": 3.6, "drag": 2.0, "rise": 0.35, "height0": 0.08, "size0": 0.2, "size1": 0.75, "opacity": 0.3})
	_dust = _multimesh(56, dust_sh, 23, AABB(Vector3(-6, -1, -6), Vector3(12, 4, 12)))
	add_child(_dust)
	_set_fx(_dust, {"loop_rate": 0.0, "life": 1.9, "delay": 0.04, "r0": 0.55, "radial_speed": 3.4, "drag": 2.6, "rise": 0.22, "height0": 0.06, "size0": 0.22, "size1": 1.0, "opacity": 0.42})
	_steam = _multimesh(18, dust_sh, 37, AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4)))
	_steam.position = Vector3(0, TOP_Y + 0.01, 0)
	_body.add_child(_steam)
	_set_fx(_steam, {"loop_rate": 1.8, "life": 0.55, "r0": _r(LID_APO), "radial_speed": 0.35, "drag": 1.0, "rise": 0.55, "height0": 0.0, "size0": 0.05, "size1": 0.28, "opacity": 0.45, "color": Color(0.92, 0.95, 0.97), "light": 1.0})
	# Hatch burst: sparks, ring, a brief light.
	_sparks = _multimesh(26, spark_sh, 41, AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6)))
	_sparks.position = Vector3(0, TOP_Y + 0.05, 0)
	_body.add_child(_sparks)
	_set_fx(_sparks, {"mode": 0, "size": 0.045, "life": 0.32, "speed_min": 1.2, "speed_max": 3.2, "el_min": 0.5, "el_max": 1.45, "drag": 3.2, "gravity": 3.5, "energy": 2.2})
	_burst_ring = _ring_plane(1.4, {"width": 0.03, "energy": 1.6})
	_burst_ring.position = Vector3(0, TOP_Y + 0.07, 0)
	_body.add_child(_burst_ring)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.6, 0.93, 1.0)
	_flash.omni_range = 4.0
	_flash.position = Vector3(0, TOP_Y + 0.35, 0)
	_flash.shadow_enabled = false
	_flash.visible = false
	_body.add_child(_flash)
	# Landing marker on the ground (staging: shows where it will land).
	_marker = _ring_plane(2.6, {"radius": 0.4, "width": 0.012, "dashes": 16.0, "energy": 1.4, "inner_fill": 0.6})
	_marker.position = Vector3(0, 0.05, 0)
	add_child(_marker)
	# Cell trail (CPU-placed, world space) and the delivery ring at the suit.
	_trail = _multimesh(36, spark_sh, 53, AABB(Vector3(-60, -20, -60), Vector3(120, 60, 120)))
	_trail.top_level = true
	add_child(_trail)
	_trail.global_transform = Transform3D()
	_set_fx(_trail, {"mode": 1, "size": 0.07, "energy": 1.8})
	_absorb = Node3D.new()
	_absorb.top_level = true
	_absorb.visible = false
	_absorb.add_to_group("no_export")
	add_child(_absorb)
	_absorb_ring = _ring_plane(2.0, {"width": 0.025, "energy": 1.4})
	_absorb_ring.visible = true
	_absorb.add_child(_absorb_ring)
	_absorb_sparks = _multimesh(14, spark_sh, 67, AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6)))
	_absorb.add_child(_absorb_sparks)
	_set_fx(_absorb_sparks, {"mode": 0, "size": 0.035, "life": 0.25, "speed_min": 0.5, "speed_max": 1.4, "el_min": -0.6, "el_max": 1.2, "drag": 4.0, "gravity": 0.5, "energy": 1.8})


## Scene-dependent tint for the dust (ground colour, light level). Call after adding.
func set_environment(ground: Color, light: float) -> void:
	# Dust is lighter and greyer than the ground it rises from (green moss makes grey-green dust).
	ground = Color.from_hsv(ground.h, ground.s * 0.45, clampf(ground.v * 1.15 + 0.08, 0.0, 0.9)).lerp(Color(0.62, 0.6, 0.56), 0.35)
	dust_color = ground
	light_level = light
	for mm: MultiMeshInstance3D in [_wash, _dust]:
		_set_fx(mm, {"color": ground, "light": light})
	_set_fx(_steam, {"light": clampf(light * 1.1, 0.5, 1.2)})


## Baked paint from the scan (local only, D-056): swap in the meshes that carry
## UV2 and feed the textures. Missing files = procedural look (fresh clone).
## In a running game the files stream in on a loader thread (~0.1-0.2 s of GLB and
## 2K textures) while the pod is still hidden, so neither the scene load nor the
## key press pays for them (async_bake, set by the game); tools and the editor
## load synchronously.
func _load_bake() -> void:
	if "--no-bake" in OS.get_cmdline_user_args():  # export of the pure procedural rebuild (the bake's input)
		return
	for f: String in BAKE_FILES:
		if not ResourceLoader.exists(BAKE_DIR + f):
			return
	var threaded := async_bake and not Engine.is_editor_hint()
	if not threaded:
		_apply_bake(load(BAKE_DIR + BAKE_FILES[0]) as PackedScene, load(BAKE_DIR + BAKE_FILES[1]) as Texture2D, load(BAKE_DIR + BAKE_FILES[2]) as Texture2D)
		return
	for f: String in BAKE_FILES:
		ResourceLoader.load_threaded_request(BAKE_DIR + f)
	_bake_pending = true
	set_process(true)


## Never leave a loader thread behind (scene change or quit mid-load).
func _exit_tree() -> void:
	if _bake_pending:
		_bake_pending = false
		for f: String in BAKE_FILES:
			if ResourceLoader.load_threaded_get_status(BAKE_DIR + f) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_get(BAKE_DIR + f)


func _poll_bake() -> void:
	var done := 0
	for f: String in BAKE_FILES:
		var st := ResourceLoader.load_threaded_get_status(BAKE_DIR + f)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			done += 1
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_bake_pending = false  # failed: stay procedural
			return
	if done < BAKE_FILES.size():
		return
	_bake_pending = false
	var res: Array = []
	for f: String in BAKE_FILES:
		res.append(ResourceLoader.load_threaded_get(BAKE_DIR + f))
	_apply_bake(res[0] as PackedScene, res[1] as Texture2D, res[2] as Texture2D)


func _apply_bake(ps: PackedScene, alb: Texture2D, orm: Texture2D) -> void:
	if ps == null or alb == null or orm == null:
		return
	var src := ps.instantiate()
	var meshes: Dictionary = {}
	for n: Node in src.find_children("*", "MeshInstance3D", true, false):
		meshes[str(n.name)] = (n as MeshInstance3D).mesh
	src.free()
	var swapped := 0
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not meshes.has(str(m.name)):
			continue
		var mesh := meshes[str(m.name)] as Mesh
		if _tri_count(mesh) != _tri_count(m.mesh):
			continue  # stale bake (the rebuild changed since): keep the procedural mesh there
		for s: int in mesh.get_surface_count():
			var key := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
			key = key.rstrip("0123456789").trim_suffix("_")
			if _mats.has(key):
				mesh.surface_set_material(s, _mats[key])
		m.mesh = mesh
		swapped += 1
	for key: String in ["hull", "accent", "frame"]:
		(_mats[key] as ShaderMaterial).set_shader_parameter("baked_albedo", alb)
		(_mats[key] as ShaderMaterial).set_shader_parameter("baked_orm", orm)
	baked = swapped > 0


static func _tri_count(mesh: Mesh) -> int:
	var n := 0
	for s: int in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
