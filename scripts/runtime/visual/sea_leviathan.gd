class_name SeaLeviathan
extends Node3D
## A giant sea serpent far out on a water world (Meshy model, D-058): it rises out
## of the sea in a slow arch, glides forward, rolls back under, and surfaces again
## somewhere else after a pause. Disney beats at ~50%: a swell of foam before it
## breaks the surface (anticipation), an ease-out rise, a long glide with a gentle
## roll (follow-through), an ease-in dive with a last spray as the tail goes under.
## Ambient only: far beyond the playable map, no collision. Frozen mid-glide with
## reduced motion. Skipped when the local model is missing.

var water_y := 0.0
var _body: Node3D
var _spray: GPUParticles3D
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _cycle := 0.0
var _pos := Vector2.ZERO
var _dir := Vector2.RIGHT
var _height := 30.0
var _length := 60.0

const RISE := 7.0
const GLIDE := 9.0
const DIVE := 7.0
const REST := 10.0


static func build(spec: Dictionary, water_level: float, seed_value: int) -> SeaLeviathan:
	var path := str(spec.get("model", ""))
	if not ResourceLoader.exists(path):
		return null
	var l := SeaLeviathan.new()
	l.name = "SeaLeviathan"
	l.water_y = water_level
	l._rng.seed = seed_value
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var box := AssetSlots.aabb_of(inst, Transform3D.IDENTITY)
	var size := DictUtil.get_float(spec, "size", 70.0)
	var s := size / maxf(maxf(box.size.x, box.size.z), 0.01)
	inst.scale = Vector3.ONE * s
	inst.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	for gi: Node in inst.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := DictUtil.get_arr(spec, "glow")
	if not glow.is_empty():
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m:
				(mi as MeshInstance3D).material_override = GroundCover.glow_material(m, glow)
	l._body = Node3D.new()
	l._body.add_child(inst)
	l.add_child(l._body)
	l._height = box.size.y * s
	l._length = maxf(box.size.x, box.size.z) * s
	l._spray = _make_spray(l._length)
	l.add_child(l._spray)
	l._new_spot(spec)
	l._cycle = l._rng.randf_range(0.0, RISE + GLIDE)  # start somewhere in the show
	if FxEffect.reduced_motion():
		l._cycle = RISE + GLIDE * 0.5
	l._place()
	l.set_meta("spec", spec)
	return l


static func _make_spray(length: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 2.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(length * 0.45, 0.5, 4.0)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 1.2
	pm.scale_max = 3.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.75))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.9, 0.97, 1.0)
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p


func _new_spot(spec: Dictionary) -> void:
	var rr: Array = DictUtil.get_arr(spec, "radius")
	var r := _rng.randf_range(float(rr[0]), float(rr[1])) if rr.size() == 2 else 260.0
	var a := _rng.randf() * TAU
	_pos = Vector2.from_angle(a) * r
	_dir = Vector2.from_angle(a + PI * 0.5 + _rng.randf_range(-0.6, 0.6))  # swims across the view, not at it


func _process(delta: float) -> void:
	if FxEffect.reduced_motion():
		return
	_t += delta
	_cycle += delta
	if _cycle > RISE + GLIDE + DIVE + REST:
		_cycle = 0.0
		_new_spot(get_meta("spec", {}))
	_place()


func _place() -> void:
	var c := _cycle
	var k := 0.0  # 0 = fully under, 1 = full arch above the sea
	var travel := 0.0
	if c < RISE:
		var u := c / RISE
		k = 1.0 - pow(1.0 - u, 3.0)  # ease-out rise
		travel = u * 0.25
	elif c < RISE + GLIDE:
		var u := (c - RISE) / GLIDE
		k = 1.0 - 0.06 * sin(u * PI)  # breathes a little at the top
		travel = 0.25 + u * 0.5
	elif c < RISE + GLIDE + DIVE:
		var u := (c - RISE - GLIDE) / DIVE
		k = 1.0 - u * u * u  # ease-in dive
		travel = 0.75 + u * 0.25
	else:
		k = 0.0
		travel = 1.0
	var p := _pos + _dir * (travel - 0.5) * _length * 1.6
	var sink := (1.0 - k) * _height * 1.05 + _height * 0.12  # the head and tail always stay under
	position = Vector3(p.x, water_y - sink, p.y)
	var roll := sin(_t * 0.4) * 0.05 + (1.0 - k) * 0.12
	_body.basis = Basis(Vector3.UP, -_dir.angle()) * Basis(Vector3.RIGHT, roll)
	visible = k > 0.001
	# Foam swells just before it breaks the surface and as the tail goes under.
	var surf := (c > RISE * 0.05 and c < RISE * 0.5) or (c > RISE + GLIDE + DIVE * 0.55 and c < RISE + GLIDE + DIVE)
	_spray.emitting = surf
	# Local to the serpent (itself unrotated, placed in its parent's space like
	# `position` above): build() runs before the node is in the tree.
	_spray.position = Vector3(p.x, water_y, p.y) - position
	_spray.basis = Basis(Vector3.UP, -_dir.angle())
