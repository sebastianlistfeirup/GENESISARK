class_name FaunaFlock
extends Node3D
## Ambient wildlife over a world (data/art/ground_cover.json -> <planet>.sky.fauna):
## flocks of birds wheeling in slow circles high above the map, each bird with
## its own phase, bank and wing-beat bob. One MultiMesh per flock, no collision,
## no gameplay. Frozen in place with reduced motion. Skipped when the purchased
## mesh is missing.

var _mm: MultiMesh
var _birds: Array = []  # [centre: Vector3, radius, speed, phase, height]
var _t := 0.0
var _mesh_scale := 1.0


static func build(spec: Dictionary, seed_value: int) -> FaunaFlock:
	var src := GroundCover.mesh_of(str(spec.get("mesh", "")), DictUtil.get_dict(spec, "look"))
	if src.is_empty():
		return null
	var f := FaunaFlock.new()
	f.name = "Fauna"
	f._mesh_scale = DictUtil.get_float(spec, "scale", 1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var flocks := int(spec.get("flocks", 3))
	var per := int(spec.get("count", 9))
	for k: int in flocks:
		var centre := Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
		var h := rng.randf_range(22, 38)
		var r := rng.randf_range(14, 30)
		var sp := rng.randf_range(0.12, 0.22) * (1.0 if rng.randf() > 0.5 else -1.0)
		for i: int in per:
			f._birds.append([centre + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), r + rng.randf_range(-3, 3), sp, rng.randf() * 0.6 + k * 2.0, h + rng.randf_range(-2, 2)])
	f._mm = MultiMesh.new()
	f._mm.transform_format = MultiMesh.TRANSFORM_3D
	f._mm.mesh = src[0]
	f._mm.instance_count = f._birds.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = f._mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(mmi)
	f._place(0.0)
	return f


func _process(delta: float) -> void:
	if FxEffect.reduced_motion():
		return
	_t += delta
	_place(_t)


func _place(t: float) -> void:
	for i: int in _birds.size():
		var b: Array = _birds[i]
		var a: float = float(b[3]) + t * float(b[2])
		var c: Vector3 = b[0]
		var r: float = b[1]
		var pos := c + Vector3(cos(a) * r, float(b[4]) + sin(t * 2.3 + i) * 0.6, sin(a) * r)
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(float(b[2]))
		var basis := Basis.looking_at(tangent, Vector3.UP)
		basis = basis * Basis(Vector3.FORWARD, 0.35 * signf(float(b[2])))  # bank into the turn
		var flap := 1.0 + 0.25 * sin(t * 9.0 + i * 1.7)
		_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(_mesh_scale * flap, _mesh_scale, _mesh_scale)), pos))
