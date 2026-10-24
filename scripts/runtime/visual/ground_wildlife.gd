class_name GroundWildlife
extends Node3D
## Ambient ground wildlife (data/art/ground_cover.json -> <planet>.wildlife, D-053):
## herds of grazers, solitary beasts and rare giants walking the expedition
## site and the land around a colony. Animated purchased creatures (Poly Perfect
## FBX with embedded clips, Synty aliens with a baked humanoid library) recoloured
## per world by art/shaders/creature_skin.gdshader so they read as alien fauna.
## Purely ambient: no collision, no gameplay, never inside `avoid` circles (camp,
## sample sites, routes, colony districts), land or shore only, never on steep
## ground. They graze, idle, wander with their herd and bolt for a few seconds
## when the captain comes close. Cheap: clips play only when near the camera
## (every frame up close, every few frames further out, frozen beyond), meshes
## cull with a visibility range. Reduced motion: they stand still. Species whose
## local model is missing are skipped (a fresh clone has no wildlife).

const SHADER := preload("res://art/shaders/creature_skin.gdshader")
const NEAR := 45.0   # clips every frame within half of this, every 2nd frame out to it
const MID := 100.0   # clips every 4th frame; beyond: every 8th until culled
const TURN := 2.0    # rad/s walking (running turns twice as fast)
const MAX_SLOPE := 0.55  # rise per metre an animal will walk up
const CELL := 1.5        # placement grid (m)
const CALL_RANGE := 110.0  # herds farther than this from the camera stay quiet
const CALL_GAP := 7.0      # seconds between any two calls on the whole map (sparse, never a chorus)

static var _models: Dictionary = {}  # model path -> measured template (see _model)

var terrain: Node3D
## The captain: animals flee from it. Null (colony overview) -> nobody to flee from.
var watcher: Node3D
var _beasts: Array = []  # [Beast]
var _herds: Array = []   # [Herd]
var _blocked := PackedByteArray()  # avoid circles rasterised (CELL grid)
var _ground: Dictionary = {}  # cell*2 + shore -> walkable
var _n := 1
var _half := 80.0
var _water := -100.0
var _wet := false
var _rng := RandomNumberGenerator.new()
var _frame := 0
var _still := false
var _call_cool := 0.0


class Herd:
	var centre := Vector2.ZERO
	var radius := 8.0
	var timer := 0.0
	var alarm := 0.0
	var threat := Vector2.ZERO
	var ring := Vector2(0.0, 999.0)
	var habitat := "land"
	var flee := 10.0
	var members: Array = []
	var call_slot := ""       # sound family (sfx_wild_<group>): grazer / beast / giant / flyer
	var pitch := 1.0       # per world and species, so the same family sounds different on each planet
	var call_t := 0.0


class Beast:
	var holder: Node3D
	var player: AnimationPlayer
	var mesh: GeometryInstance3D
	var clips: Dictionary = {}  # idle / graze / walk / run -> clip name
	var herd: Herd
	var state := "idle"
	var pos := Vector2.ZERO
	var target := Vector2.ZERO
	var yaw := 0.0
	var timer := 0.0
	var speed := 0.0
	var walk := 1.2
	var run := 5.0
	var walk_ref := 1.0  # ground speed of the walk clip at this size and playback 1
	var run_ref := 4.0
	var radius := 1.0
	var length := 2.0
	var anim_dt := 0.0
	var vis_end := 170.0
	var slot := 0
	var dirty := true


## specs: <planet>.wildlife entries. density scales the herd counts (colony: lighter).
## ring_min pushes everything out past a radius (colony: beyond the districts).
static func build(p_terrain: Node3D, specs: Array, seed_value: int, avoid: Array, size_m: float,
		p_watcher: Node3D = null, density: float = 1.0, ring_min: float = 0.0) -> GroundWildlife:
	var root := GroundWildlife.new()
	root.name = "GroundWildlife"
	root.terrain = p_terrain
	root.watcher = p_watcher
	root._half = size_m * 0.46
	root._raster(avoid)
	root._water = float(p_terrain.get("water_level"))
	root._wet = root._water > -50.0
	root._rng.seed = seed_value
	root._still = FxEffect.reduced_motion()
	var q := Quality.value("wildlife_scale", 1.0)
	var map_scale := size_m / 180.0  # rings are authored for the 180 m expedition map
	for sv: Variant in specs:
		var spec: Dictionary = sv
		var key := "colony" if density < 1.0 else "herds"
		var herds := int(round(DictUtil.get_float(spec, key, DictUtil.get_float(spec, "herds", 1.0) * density) * q))
		if herds <= 0:
			continue
		var tmpl := _model(spec)
		if tmpl.is_empty():
			continue
		var ring: Array = DictUtil.get_arr(spec, "ring")
		var hr: Array = DictUtil.get_arr(spec, "herd")
		var mat := _skin(spec, tmpl)
		for h: int in herds:
			var herd := Herd.new()
			herd.habitat = str(spec.get("habitat", "land"))
			herd.ring = Vector2(maxf(float(ring[0]) * map_scale if ring.size() == 2 else 0.0, ring_min), float(ring[1]) * map_scale if ring.size() == 2 else 999.0)
			herd.radius = DictUtil.get_float(spec, "spread", 7.0)
			herd.flee = DictUtil.get_float(spec, "flee", 10.0)
			herd.timer = root._rng.randf_range(10.0, 30.0)
			herd.call_slot = "sfx_wild_" + call_group(spec)
			herd.pitch = 0.82 + float(absi(hash(str(seed_value) + str(spec.get("model", "")))) % 37) / 100.0
			herd.call_t = root._rng.randf_range(6.0, 30.0) * (2.0 if herd.call_slot.ends_with("giant") else 1.0)
			var found := false
			for attempt: int in 60:
				var c := Vector2.from_angle(root._rng.randf() * TAU) * root._rng.randf_range(herd.ring.x, minf(herd.ring.y, root._half))
				if root._ok(c, herd, 3.0) and not root._near_herd(c, 18.0):
					herd.centre = c
					found = true
					break
			if not found:
				continue
			root._herds.append(herd)
			var n := root._rng.randi_range(int(hr[0]), int(hr[1])) if hr.size() == 2 else 1
			for i: int in n:
				var p := herd.centre
				for attempt: int in 20:
					var cand := herd.centre + Vector2.from_angle(root._rng.randf() * TAU) * root._rng.randf_range(0.0, herd.radius)
					if root._ok(cand, herd, 1.0) and root._room(cand, herd, 2.0):
						p = cand
						break
				var b := root._spawn(spec, tmpl, mat, herd, p)
				if b:
					herd.members.append(b)
					root._beasts.append(b)
	return root


func _spawn(spec: Dictionary, tmpl: Dictionary, mat: Material, herd: Herd, p: Vector2) -> Beast:
	var inst: Node3D = (tmpl["scene"] as PackedScene).instantiate()
	var b := Beast.new()
	var size := DictUtil.get_float(spec, "size", 1.8) * _rng.randf_range(1.0 - DictUtil.get_float(spec, "var", 0.1), 1.0 + DictUtil.get_float(spec, "var", 0.1))
	var s := size / maxf(float(tmpl["height"]), 0.01)
	if tmpl.has("only_mesh"):  # one Synty body out of a multi-body prefab; no physics
		for mi: Node in inst.find_children("SM_Chr_*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = String(mi.name) == str(tmpl["only_mesh"])
		for cs: Node in inst.find_children("*", "CollisionShape3D", true, false):
			cs.get_parent().remove_child(cs)
			cs.free()
		if inst is CollisionObject3D:
			(inst as CollisionObject3D).collision_layer = 0
			(inst as CollisionObject3D).collision_mask = 0
	# Face the model's own forward (measured from its walk) down the holder's -Z.
	var fwd: Vector3 = tmpl["forward"]
	inst.transform = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z) + PI).scaled(Vector3.ONE * s), Vector3(0.0, -float(tmpl["foot"]) * s, 0.0))
	b.holder = Node3D.new()
	b.holder.add_child(inst)
	add_child(b.holder)
	b.mesh = _main_mesh(inst, tmpl)
	if b.mesh:
		if mat:
			b.mesh.material_override = mat
		b.vis_end = DictUtil.get_float(spec, "vis", 170.0)
		b.mesh.visibility_range_end = b.vis_end
		b.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	b.player = _player(inst, tmpl)
	b.clips = tmpl["clips"]
	b.herd = herd
	b.pos = p
	b.target = p
	b.yaw = _rng.randf() * TAU
	b.walk = DictUtil.get_float(spec, "walk", 1.3) * sqrt(s * float(tmpl["height"]) / maxf(DictUtil.get_float(spec, "size", 1.8), 0.1))
	b.run = DictUtil.get_float(spec, "run", 5.5)
	b.walk_ref = float(tmpl["walk_ref"]) * s
	b.run_ref = float(tmpl["run_ref"]) * s
	b.length = float(tmpl["length"]) * s
	b.radius = maxf(b.length * 0.5, 0.6)
	b.slot = _beasts.size()
	b.state = "graze" if b.clips.has("graze") and _rng.randf() < 0.6 else "idle"
	b.timer = _rng.randf_range(2.0, 12.0)
	if b.player:
		b.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var clip := str(b.clips.get(b.state, b.clips.get("idle", "")))
		if not clip.is_empty():
			b.player.play(clip)
			b.player.seek(_rng.randf() * b.player.current_animation_length, true)
			b.player.speed_scale = _rng.randf_range(0.85, 1.1)
	_place(b)
	return b


func _process(delta: float) -> void:
	if _still or not is_visible_in_tree():
		return
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var threat := Vector2.INF
	if is_instance_valid(watcher) and watcher.is_visible_in_tree():
		threat = Vector2(watcher.global_position.x, watcher.global_position.z)
	_call_cool -= delta
	for hv: Variant in _herds:
		var herd: Herd = hv
		_calls(herd, delta, eye)
		herd.alarm -= delta
		herd.timer -= delta
		if herd.timer <= 0.0:  # the herd drifts on to fresh grazing
			herd.timer = _rng.randf_range(25.0, 50.0)
			for attempt: int in 10:
				var c := herd.centre + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, 12.0)
				if _ok(c, herd, 3.0):
					herd.centre = c
					break
	for bv: Variant in _beasts:
		var b: Beast = bv
		_think(b, delta, threat)
		_move(b, delta)
		_animate(b, delta, eye)


## Which call family a species uses (D-064): data may name it ("call"), else the
## model and size decide. Alien-flavoured takes in assets/audio/final/sfx_wild_*.
static func call_group(spec: Dictionary) -> String:
	if spec.has("call"):
		return str(spec["call"])
	var m := str(spec.get("model", "")).to_lower()
	if DictUtil.get_float(spec, "size", 1.8) >= 5.0:
		return "giant"
	if m.contains("gryph"):
		return "flyer"
	if m.contains("bull") or m.contains("bear"):
		return "beast"
	return "grazer"


## Now and then one animal of a herd near the camera calls (positional, quiet,
## sparse: per-herd timers plus a map-wide gap). Startled herds call once.
func _calls(herd: Herd, delta: float, eye: Vector3) -> void:
	herd.call_t -= delta
	if herd.call_t > 0.0 or herd.members.is_empty():
		return
	herd.call_t = _rng.randf_range(25.0, 60.0) * (2.0 if herd.call_slot.ends_with("giant") else 1.0)
	_voice(herd, eye, 1.0)


func _voice(herd: Herd, eye: Vector3, pitch_k: float) -> void:
	if _call_cool > 0.0 or herd.members.is_empty():
		return
	var b: Beast = herd.members[_rng.randi() % herd.members.size()]
	if not is_instance_valid(b.holder) or b.holder.global_position.distance_to(eye) > CALL_RANGE:
		return
	_call_cool = CALL_GAP
	var giant := herd.call_slot.ends_with("giant")
	AudioService.play_3d(herd.call_slot, b.holder, 2.0 if giant else -2.0, 260.0 if giant else 130.0,
		herd.pitch * pitch_k * _rng.randf_range(0.95, 1.05), "Ambience", 22.0 if giant else 10.0)


func _think(b: Beast, delta: float, threat: Vector2) -> void:
	var herd := b.herd
	if threat != Vector2.INF and b.pos.distance_to(threat) < herd.flee:
		if herd.alarm <= 0.0 and is_instance_valid(watcher):
			_voice(herd, watcher.global_position, 1.15)  # the startled one cries out as the herd bolts
		herd.alarm = 3.5  # one startled animal sets off the whole herd
		herd.threat = threat
	if herd.alarm > 0.0 and b.state != "run" and b.pos.distance_to(herd.threat) < herd.flee * 1.8:
		var away := (b.pos - herd.threat).normalized()
		if away == Vector2.ZERO:
			away = Vector2.from_angle(b.yaw)
		for k: int in 7:
			var a := away.rotated(((k + 1) >> 1) * 0.45 * (1.0 if k % 2 == 1 else -1.0))
			var cand := b.pos + a * _rng.randf_range(12.0, 20.0)
			if _ok(cand, herd, b.radius):
				b.target = cand
				b.state = "run"
				b.timer = 5.0
				return
	b.timer -= delta
	match b.state:
		"walk", "run":
			if b.pos.distance_to(b.target) < 0.7 or b.timer <= -8.0:
				_rest(b)
		_:
			if b.timer <= 0.0:
				var roll := _rng.randf()
				if roll < 0.3:
					for attempt: int in 8:
						var cand := herd.centre + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, herd.radius)
						if cand.distance_to(b.pos) > 2.0 and _ok(cand, herd, b.radius) and _room(cand, herd, b.radius * 2.0, b):
							b.target = cand
							b.state = "walk"
							b.timer = 0.0
							return
				_rest(b)


func _rest(b: Beast) -> void:
	b.state = "graze" if b.clips.has("graze") and _rng.randf() < 0.6 else "idle"
	b.timer = _rng.randf_range(5.0, 14.0)


func _move(b: Beast, delta: float) -> void:
	var want := 0.0
	if b.state == "walk":
		want = b.walk
	elif b.state == "run":
		want = b.run
	b.speed = move_toward(b.speed, want, delta * (6.0 if b.state == "run" else 2.0))
	if b.speed < 0.01 and want == 0.0:
		if b.dirty:
			_place(b)
		return
	var to := b.target - b.pos
	var ease := 1.0
	if to.length() > 0.05:
		var ty := atan2(-to.x, -to.y)
		b.yaw = rotate_toward(b.yaw, ty, delta * TURN * (3.0 if b.state == "run" else 1.0))
		ease = clampf(cos(angle_difference(b.yaw, ty)), 0.15, 1.0)  # wheel round before striding off
	var facing := Vector2(-sin(b.yaw), -cos(b.yaw))
	var nxt := b.pos + facing * b.speed * ease * delta
	if not _ok(nxt, b.herd, b.radius * 0.5):
		b.speed = 0.0
		_rest(b)
		return
	b.pos = nxt
	b.dirty = true
	_place(b)


func _place(b: Beast) -> void:
	var y := float(terrain.call("height_at", b.pos.x, b.pos.y))
	var facing := Vector2(-sin(b.yaw), -cos(b.yaw))
	var half := b.length * 0.4
	var hf := float(terrain.call("height_at", b.pos.x + facing.x * half, b.pos.y + facing.y * half))
	var hb := float(terrain.call("height_at", b.pos.x - facing.x * half, b.pos.y - facing.y * half))
	var pitch := clampf(atan2(hf - hb, half * 2.0), -0.35, 0.35)
	b.holder.transform = Transform3D(Basis(Vector3.UP, b.yaw) * Basis(Vector3.RIGHT, pitch), Vector3(b.pos.x, minf(y, (hf + hb) * 0.5) - 0.03, b.pos.y))
	b.dirty = false


func _animate(b: Beast, delta: float, eye: Vector3) -> void:
	if b.player == null:
		return
	var clip := ""
	var rate := 1.0
	if b.state in ["walk", "run"] and b.speed > 0.15:
		var running := b.speed > (b.walk + b.run) * 0.5 and b.clips.has("run")
		clip = str(b.clips.get("run" if running else "walk", ""))
		rate = clampf(b.speed / maxf(b.run_ref if running else b.walk_ref, 0.05), 0.4, 2.2)
	else:
		clip = str(b.clips.get(b.state, b.clips.get("idle", "")))
	if clip.is_empty():
		return
	if b.player.current_animation != clip:
		b.player.play(clip, 0.3)
		if b.state in ["idle", "graze"]:
			rate = _rng.randf_range(0.85, 1.1)
		b.player.speed_scale = rate
	elif b.state in ["walk", "run"]:
		b.player.speed_scale = rate
	b.anim_dt += delta
	var d := b.holder.global_position.distance_to(eye)
	var every := 1 if d < NEAR * 0.5 else (2 if d < NEAR else (4 if d < MID else 8))
	if d > b.vis_end:
		return
	if every == 1 or (_frame + b.slot) % every == 0:
		b.player.advance(b.anim_dt)
		b.anim_dt = 0.0


# ---------------------------------------------------------------- placement

func _ok(p: Vector2, herd: Herd, clearance: float) -> bool:
	if absf(p.x) > _half or absf(p.y) > _half:
		return false
	var r := p.length()
	if r < herd.ring.x or r > herd.ring.y:
		return false
	var idx := _cell_of(p)
	if _blocked[idx] != 0:
		return false
	if clearance > CELL:  # big bodies (giants, herd centres) keep a wider berth
		for k: int in 4:
			if _blocked[_cell_of(p + Vector2.from_angle(TAU * k / 4.0) * clearance)] != 0:
				return false
	var key := idx * 2 + (1 if herd.habitat == "shore" else 0)
	if not _ground.has(key):
		var cx := idx % _n
		_ground[key] = _ground_ok(Vector2(cx * CELL - _half, float(idx - cx) / _n * CELL - _half) + Vector2.ONE * CELL * 0.5, herd.habitat)
	return _ground[key]


## Land (or shore) and walkable slope at a cell centre; cached per cell.
func _ground_ok(p: Vector2, habitat: String) -> bool:
	var y := float(terrain.call("height_at", p.x, p.y))
	if _wet:
		if habitat == "shore":
			if y < _water + 0.1 or y > _water + 2.5:
				return false
		elif y < _water + 0.5:
			return false
	var gx := float(terrain.call("height_at", p.x + 1.5, p.y)) - y
	var gz := float(terrain.call("height_at", p.x, p.y + 1.5)) - y
	return Vector2(gx, gz).length() / 1.5 < MAX_SLOPE


func _cell_of(p: Vector2) -> int:
	var cx := clampi(int((p.x + _half) / CELL), 0, _n - 1)
	var cz := clampi(int((p.y + _half) / CELL), 0, _n - 1)
	return cz * _n + cx


## The avoid circles rasterised once (colonies have hundreds: roads, tubes, plots).
func _raster(avoid: Array) -> void:
	_n = int(ceil(_half * 2.0 / CELL)) + 1
	_blocked.resize(_n * _n)
	_blocked.fill(0)
	for a: Variant in avoid:
		var arr: Array = a
		var c: Vector2 = arr[0]
		var rr := float(arr[1]) + 1.0
		var x0 := clampi(int((c.x - rr + _half) / CELL), 0, _n - 1)
		var x1 := clampi(int((c.x + rr + _half) / CELL), 0, _n - 1)
		var z0 := clampi(int((c.y - rr + _half) / CELL), 0, _n - 1)
		var z1 := clampi(int((c.y + rr + _half) / CELL), 0, _n - 1)
		for cz: int in range(z0, z1 + 1):
			for cx: int in range(x0, x1 + 1):
				var q := Vector2(cx * CELL - _half, cz * CELL - _half) + Vector2.ONE * CELL * 0.5
				if q.distance_to(c) < rr:
					_blocked[cz * _n + cx] = 1


func _room(p: Vector2, herd: Herd, gap: float, me: Beast = null) -> bool:
	for m: Variant in herd.members:
		var o: Beast = m
		if o != me and (o.pos.distance_to(p) < gap or o.target.distance_to(p) < gap):
			return false
	return true


func _near_herd(p: Vector2, gap: float) -> bool:
	for hv: Variant in _herds:
		if (hv as Herd).centre.distance_to(p) < gap:
			return true
	return false


# ---------------------------------------------------------------- models

## Loads and measures a creature once: its height, foot level, body length,
## forward direction and the ground speed of its walk/run clips (from the
## planted feet), so instances face where they go and the feet do not slide.
static func _model(spec: Dictionary) -> Dictionary:
	var path := str(spec.get("model", ""))
	var key := path + "|" + str(spec.get("only_mesh", ""))
	if _models.has(key):
		return _models[key]
	var out: Dictionary = {}
	_models[key] = out
	if path.is_empty() or not ResourceLoader.exists(path):
		return out
	var ps := load(path) as PackedScene
	if ps == null:
		return out
	var lib_path := str(spec.get("library", ""))
	var lib: AnimationLibrary = null
	if not lib_path.is_empty():
		if not ResourceLoader.exists(lib_path):
			return out  # a humanoid giant without its baked clips would T-pose: skip it
		lib = load(lib_path) as AnimationLibrary
	var inst: Node = ps.instantiate()
	var only := str(spec.get("only_mesh", ""))
	var mi: MeshInstance3D = null
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh and (only.is_empty() or String(m.name) == only):
			mi = m
			break
	var skel: Skeleton3D = null
	if mi:
		skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D if not mi.skeleton.is_empty() else null
	if skel == null and not inst.find_children("*", "Skeleton3D", true, false).is_empty():
		skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	if mi == null or skel == null:
		inst.free()
		return out
	var clips: Dictionary = {}
	var anims: Dictionary = {}  # clip name -> Animation
	if lib:
		for an: StringName in lib.get_animation_list():
			anims[LIB + "/" + String(an)] = lib.get_animation(an)
	else:
		for apn: Node in inst.find_children("*", "AnimationPlayer", true, false):
			var ap := apn as AnimationPlayer
			for an: StringName in ap.get_animation_list():
				anims[String(an)] = ap.get_animation(an)
	for cn: String in anims.keys():
		var low := cn.to_lower().get_file()
		if low.contains("init") or low.contains("death") or low.contains("hit") or low.contains("attack"):
			continue
		var st := ""
		if low.contains("idle"):
			st = "idle"
		elif low.contains("eat") or low.contains("graze"):
			st = "graze"
		elif low.contains("walk"):
			st = "walk"
		elif low.contains("run"):
			st = "run"
		if st.is_empty() or clips.has(st):
			continue
		clips[st] = cn
		(anims[cn] as Animation).loop_mode = Animation.LOOP_LINEAR
	if not clips.has("idle"):
		inst.free()
		return out
	var mesh_xf := _xf_to(inst, mi)
	var box: AABB = mesh_xf * mi.mesh.get_aabb()
	var skel_xf := _xf_to(inst, skel)
	var deform: Dictionary = {}  # Blender-rigged packs: only DEF_ bones are the legs (not IK/MCH helpers)
	for bi: int in skel.get_bone_count():
		if skel.get_bone_name(bi).to_lower().begins_with("def_"):
			deform[bi] = true
	if not deform.is_empty():
		_strip_rig_tracks(skel, deform, clips, anims)
	var walk: Array = _ground_speed(skel, anims.get(clips.get("walk", ""), null), skel_xf, box.size.y, deform)
	var run: Array = _ground_speed(skel, anims.get(clips.get("run", ""), null), skel_xf, box.size.y, deform)
	if lib:  # baked humanoid clips: Synty bodies face +Z; long alien arms swing low and fool
		# the planted-foot measure, the source clip's measured speed holds (same hip height)
		walk = [DictUtil.get_float(spec, "walk_ref", 1.49), Vector3(0, 0, 1)]
		run = [0.0, Vector3.ZERO]
	var fwd: Vector3 = walk[1] if walk[0] > 0.0 else Vector3(0, 0, 1)
	out["scene"] = ps
	out["clips"] = clips
	out["height"] = box.size.y
	out["foot"] = box.position.y
	out["length"] = absf(box.size.dot(Vector3(absf(fwd.x), 0.0, absf(fwd.z))))
	out["forward"] = fwd
	out["walk_ref"] = walk[0] if walk[0] > 0.0 else box.size.y * 0.6
	out["run_ref"] = run[0] if run[0] > 0.0 else float(out["walk_ref"]) * 3.0
	out["up_mesh"] = (mesh_xf.basis.inverse() * Vector3.UP).normalized()
	out["long_mesh"] = (mesh_xf.basis.inverse() * fwd).normalized()
	out["mesh_height"] = (mi.mesh.get_aabb().size * (mesh_xf.basis.inverse() * Vector3.UP).abs()).length()
	out["mesh_path"] = inst.get_path_to(mi)
	out["skel_path"] = inst.get_path_to(skel)
	out["tex"] = _albedo_of(mi)
	if lib:
		out["library"] = lib
	if not only.is_empty():
		out["only_mesh"] = only
	inst.free()
	return out


const LIB := "wild"


## The packs export every control bone of their Blender rigs (IK targets, poles,
## widgets): ~180 tracks a clip. Only the deforming bones and their ancestors move
## the mesh, so the rest is dropped from the clips we play (half the playback cost).
static func _strip_rig_tracks(skel: Skeleton3D, deform: Dictionary, clips: Dictionary, anims: Dictionary) -> void:
	var keep: Dictionary = {}
	for bi: int in deform.keys():
		var cur: int = bi
		while cur >= 0 and not keep.has(cur):
			keep[cur] = true
			cur = skel.get_bone_parent(cur)
	for cn: Variant in clips.values():
		var anim := anims.get(cn) as Animation
		if anim == null or anim.has_meta("ga_stripped"):
			continue
		for t: int in range(anim.get_track_count() - 1, -1, -1):
			var bone := skel.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
			if bone >= 0 and not keep.has(bone):
				anim.remove_track(t)
		anim.set_meta("ga_stripped", true)


static func _xf_to(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _albedo_of(mi: MeshInstance3D) -> Texture2D:
	var m := mi.get_active_material(0)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null


## [ground speed m/s at scale 1, forward direction] of a locomotion clip: the
## lowest bones are the feet; while one is planted it travels backwards at the
## body's speed. [0, -] when the clip is missing or not measurable.
static func _ground_speed(skel: Skeleton3D, anim: Animation, skel_xf: Transform3D, height: float, deform: Dictionary) -> Array:
	if anim == null or anim.length <= 0.0:
		return [0.0, Vector3.ZERO]
	var n := skel.get_bone_count()
	var track_bone: Dictionary = {}
	for t: int in anim.get_track_count():
		var bone := skel.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
		if bone >= 0:
			track_bone[t] = bone
	var steps := 48
	var dt := anim.length / steps
	var series: Array = []  # per bone: PackedVector3Array of root-space positions
	for i: int in n:
		series.append(PackedVector3Array())
	for k: int in steps + 1:
		var tt := minf(k * dt, anim.length)
		var local: Array = []
		for i: int in n:
			local.append(skel.get_bone_rest(i))
		for t: int in track_bone.keys():
			var bi: int = track_bone[t]
			var xf: Transform3D = local[bi]
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					xf.origin = anim.position_track_interpolate(t, tt)
				Animation.TYPE_ROTATION_3D:
					xf.basis = Basis(anim.rotation_track_interpolate(t, tt)).scaled(xf.basis.get_scale())
				Animation.TYPE_SCALE_3D:
					xf.basis = xf.basis.orthonormalized().scaled(anim.scale_track_interpolate(t, tt))
			local[bi] = xf
		var glob: Array = []
		glob.resize(n)
		for i: int in n:
			glob[i] = _global(skel, local, glob, i)
		for i: int in n:
			var arr: PackedVector3Array = series[i]  # packed arrays copy on write: store back
			arr.append(skel_xf * (glob[i] as Transform3D).origin)
			series[i] = arr
	var ground := INF  # lowest point of any skinned bone that lifts (rig roots and IK targets don't count)
	var lifts: Dictionary = {}
	for i: int in n:
		if not deform.is_empty() and not deform.has(i):
			continue
		var s: Variant = series[i]
		var lo := INF
		var hi := -INF
		for p: Vector3 in s as PackedVector3Array:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		if hi - lo >= height * 0.01:
			ground = minf(ground, lo)
			lifts[i] = true
	# Whatever touches the ground is planted: the lowest bone of each sample (when it
	# is down) slides backwards at the body's speed.
	var vel := Vector3.ZERO
	var speed := 0.0
	var cnt := 0
	for k: int in steps:
		var lowest := -1
		var ly := INF
		for i: int in lifts.keys():
			var y := (series[i] as PackedVector3Array)[k].y
			if y < ly:
				ly = y
				lowest = i
		if lowest < 0 or ly > ground + height * 0.03:
			continue
		var ps: PackedVector3Array = series[lowest]
		var v := (ps[k + 1] - ps[k]) / dt
		v.y = 0.0
		vel += v
		speed += v.length()
		cnt += 1
	if cnt < 3 or vel.length() < 0.001:
		return [0.0, Vector3.ZERO]
	return [speed / cnt, -vel.normalized()]


static func _global(skel: Skeleton3D, local: Array, glob: Array, i: int) -> Transform3D:
	if glob[i] != null:
		return glob[i]
	var p := skel.get_bone_parent(i)
	var g: Transform3D = local[i] if p < 0 else _global(skel, local, glob, p) * (local[i] as Transform3D)
	glob[i] = g
	return g


static func _main_mesh(inst: Node, tmpl: Dictionary) -> GeometryInstance3D:
	return inst.get_node_or_null(tmpl["mesh_path"]) as GeometryInstance3D


static func _player(inst: Node, tmpl: Dictionary) -> AnimationPlayer:
	if tmpl.has("library"):
		var skel := inst.get_node_or_null(tmpl["skel_path"]) as Node
		if skel == null:
			return null
		var ap := AnimationPlayer.new()
		ap.name = "WildAnimations"
		skel.get_parent().add_child(ap)
		ap.root_node = NodePath("..")
		ap.add_animation_library(LIB, tmpl["library"])
		return ap
	for n: Node in inst.find_children("*", "AnimationPlayer", true, false):
		return n as AnimationPlayer
	return null


## The world's colouring for a species (one material shared by the species).
static func _skin(spec: Dictionary, tmpl: Dictionary) -> Material:
	var sk: Dictionary = DictUtil.get_dict(spec, "skin")
	var tex: Texture2D = null
	var tp := str(spec.get("tex", ""))
	if not tp.is_empty() and ResourceLoader.exists(tp):
		tex = load(tp)
	elif tmpl.get("tex") is Texture2D:
		tex = tmpl["tex"]
	if tex == null:
		return null  # keep the model's own material (Synty atlas)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	var ep := str(spec.get("emit_tex", ""))
	if not ep.is_empty() and ResourceLoader.exists(ep):
		mat.set_shader_parameter("emit_tex", load(ep))
		mat.set_shader_parameter("emit_energy", DictUtil.get_float(sk, "emit", 1.5))
		mat.set_shader_parameter("emit_color", Color(str(sk.get("emit_color", "#ffffff"))))
	mat.set_shader_parameter("hue_shift", DictUtil.get_float(sk, "hue", 0.0))
	mat.set_shader_parameter("sat", DictUtil.get_float(sk, "sat", 1.0))
	mat.set_shader_parameter("val", DictUtil.get_float(sk, "val", 1.0))
	var grad: Array = DictUtil.get_arr(sk, "grad")
	if grad.size() == 2:
		mat.set_shader_parameter("grad_dark", Color(str(grad[0])))
		mat.set_shader_parameter("grad_light", Color(str(grad[1])))
		mat.set_shader_parameter("grad_amount", DictUtil.get_float(sk, "grad_amount", 0.6))
	mat.set_shader_parameter("glow_color", Color(str(sk.get("glow_color", "#5affe0"))))
	mat.set_shader_parameter("glow_energy", DictUtil.get_float(sk, "glow", 0.0))
	mat.set_shader_parameter("glow_min", DictUtil.get_float(sk, "glow_min", 0.72))
	mat.set_shader_parameter("band_energy", DictUtil.get_float(sk, "bands", 0.0))
	mat.set_shader_parameter("band_freq", DictUtil.get_float(sk, "band_freq", 1.2))
	mat.set_shader_parameter("up_axis", tmpl["up_mesh"])
	mat.set_shader_parameter("long_axis", tmpl["long_mesh"])
	mat.set_shader_parameter("body_height", float(tmpl["mesh_height"]))
	mat.set_shader_parameter("pulse_speed", 0.0 if FxEffect.reduced_motion() else 1.3)
	mat.set_shader_parameter("roughness", DictUtil.get_float(sk, "roughness", 0.85))
	return mat


## Keep-out circles [centre, radius] from a GroundCover node: tree trunks and the
## footprints of landmark silhouettes, so nothing grazes inside a rock or a tree.
static func obstacles(cover: Node) -> Array:
	var out: Array = []
	if cover == null:
		return out
	var trunks := cover.get_node_or_null("TreeTrunks")
	if trunks:
		for c: Node in trunks.get_children():
			var cs := c as CollisionShape3D
			if cs and cs.shape is CylinderShape3D:
				out.append([Vector2(cs.position.x, cs.position.z), (cs.shape as CylinderShape3D).radius + 0.8])
	for c: Node in cover.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.transform * mi.get_aabb()
		out.append([Vector2(box.get_center().x, box.get_center().z), maxf(box.size.x, box.size.z) * 0.45 + 1.0])
	return out


## Number of animals (perf probes, tests).
func count() -> int:
	return _beasts.size()


## Where animal `i` (wrapped) stands (evidence camera).
func animal_position(i: int) -> Vector3:
	if _beasts.is_empty():
		return Vector3.ZERO
	return (_beasts[posmod(i, _beasts.size())] as Beast).holder.global_position
