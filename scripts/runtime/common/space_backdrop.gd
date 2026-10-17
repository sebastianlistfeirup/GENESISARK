class_name SpaceBackdrop
extends Node3D
## Deterministic starfield + nebula sky + key light. Shared by menu, ship
## windows and flight. Stars are one MultiMesh (cheap).

@export var star_count: int = 1600
@export var radius: float = 900.0
@export var seed_value: int = 7


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("03060b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("2a3a4a")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.1
	env.environment = e
	add_child(env)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := SphereMesh.new()
	q.radius = 1.0
	q.height = 2.0
	q.radial_segments = 4
	q.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	q.material = mat
	mm.mesh = q
	mm.instance_count = star_count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in star_count:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * radius
		var s := rng.randf_range(0.6, 2.2)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), v))
		var warm := rng.randf()
		var c := Color(1, 0.85, 0.7) if warm > 0.8 else (Color(0.7, 0.85, 1) if warm < 0.3 else Color(1, 1, 1))
		mm.set_instance_color(i, c * rng.randf_range(0.6, 1.4))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -40, 0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.4
	add_child(sun)
