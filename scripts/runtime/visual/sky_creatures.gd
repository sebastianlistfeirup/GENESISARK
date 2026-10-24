class_name SkyCreatures
extends Node3D
## Alien wildlife drifting through a world's sky (data/art/ground_cover.json ->
## <planet>.sky.creatures): Meshy-made rigid meshes brought to life by
## art/shaders/creature_flex.gdshader (wing beats or bell pulses) and slow
## wandering paths (circles with height drift, or straight glides across the sky
## for distant giants). Purely ambient: no collision, no gameplay. Frozen with
## reduced motion. Skipped when the local model is missing.

const SHADER := preload("res://art/shaders/creature_flex.gdshader")

var _beings: Array = []  # [Node3D, centre, radius, speed, phase, height, mode]
var _t := 0.0


static func build(specs: Array, seed_value: int, terrain: Node3D = null) -> SkyCreatures:
	var root := SkyCreatures.new()
	root.name = "SkyCreatures"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for sv: Variant in specs:
		var spec: Dictionary = sv
		var path := str(spec.get("model", ""))
		if not ResourceLoader.exists(path):
			continue
		var tmpl: Node = (load(path) as PackedScene).instantiate()
		var src: MeshInstance3D = tmpl if tmpl is MeshInstance3D else tmpl.find_children("*", "MeshInstance3D", true, false).front() if not tmpl.find_children("*", "MeshInstance3D", true, false).is_empty() else null
		if src == null or src.mesh == null:
			tmpl.free()
			continue
		var mesh: Mesh = src.mesh
		var tex: Texture2D = null
		var m0 := mesh.surface_get_material(0)
		if m0 is BaseMaterial3D:
			tex = (m0 as BaseMaterial3D).albedo_texture
		tmpl.free()
		var box := mesh.get_aabb()
		var mode := 1 if str(spec.get("motion", "wing")) == "pulse" else 0
		var size := DictUtil.get_float(spec, "size", 6.0)
		var s := size / maxf(box.size.x if mode == 0 else box.size.y, 0.01)
		var count := int(spec.get("count", 4))
		var hr: Array = DictUtil.get_arr(spec, "height")
		var rr: Array = DictUtil.get_arr(spec, "radius")
		for i: int in count:
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			mat.set_shader_parameter("albedo_tex", tex)
			mat.set_shader_parameter("mode", mode)
			mat.set_shader_parameter("amount", DictUtil.get_float(spec, "amount", 0.25))
			mat.set_shader_parameter("speed", 0.0 if FxEffect.reduced_motion() else DictUtil.get_float(spec, "beat", 1.2) * rng.randf_range(0.85, 1.15))
			mat.set_shader_parameter("half_span", (box.size.x if mode == 0 else box.size.y) * 0.5)
			mat.set_shader_parameter("phase", rng.randf() * TAU)
			mat.set_shader_parameter("glow", DictUtil.get_float(spec, "glow", 0.0))
			mat.set_shader_parameter("glow_color", Color(str(spec.get("glow_color", "#4dffe0"))))
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.scale = Vector3.ONE * s * rng.randf_range(0.8, 1.2)
			mi.position = -box.get_center() * mi.scale.x
			var holder := Node3D.new()
			holder.add_child(mi)
			root.add_child(holder)
			var centre := Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-70, 70))
			var h := rng.randf_range(float(hr[0]), float(hr[1])) if hr.size() == 2 else 25.0
			if terrain:
				h += float(terrain.call("height_at", clampf(centre.x, -85, 85), clampf(centre.z, -85, 85)))
			var r := rng.randf_range(float(rr[0]), float(rr[1])) if rr.size() == 2 else 30.0
			var sp := DictUtil.get_float(spec, "speed", 0.05) * rng.randf_range(0.7, 1.3) * (1.0 if rng.randf() > 0.5 else -1.0)
			root._beings.append([holder, centre, r, sp, rng.randf() * TAU, h, mode])
	root._place(0.0)
	return root


func _process(delta: float) -> void:
	if FxEffect.reduced_motion():
		return
	_t += delta
	_place(_t)


func _place(t: float) -> void:
	for b: Array in _beings:
		var holder: Node3D = b[0]
		var a: float = float(b[4]) + t * float(b[3])
		var c: Vector3 = b[1]
		var r: float = b[2]
		var mode: int = b[6]
		var pos := c + Vector3(cos(a) * r, float(b[5]) + sin(t * 0.3 + float(b[4])) * (1.5 if mode == 0 else 3.0), sin(a) * r)
		holder.position = pos
		if mode == 0:
			var tangent := Vector3(-sin(a), 0, cos(a)) * signf(float(b[3]))
			holder.basis = Basis.looking_at(tangent, Vector3.UP) * Basis(Vector3.FORWARD, 0.25 * signf(float(b[3])))
		else:
			holder.rotation.y = a * 0.3
