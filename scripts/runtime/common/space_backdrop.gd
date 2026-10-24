class_name SpaceBackdrop
extends Node3D
## Deterministic starfield + nebula sky + key light. Shared by menu, ship
## windows and flight. Stars are one MultiMesh (cheap) plus a few big coloured
## glow stars (billboards, D-044); both stay centred on the active camera so a
## long flight never leaves the star sphere.

@export var star_count: int = 1600
@export var radius: float = 900.0
@export var seed_value: int = 7
@export var glow_star_count: int = 70
var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_material: ShaderMaterial
var _star_nodes: Array[Node3D] = []


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# Painted nebula sky (art/shaders/nebula_sky.gdshader), varied per seed.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://art/shaders/nebula_sky.gdshader")
	sky_mat.set_shader_parameter("seed", float(seed_value % 97))
	sky_material = sky_mat
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("5a4a7a")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.1
	env.environment = e
	environment = e
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
		# HDR: brighter than white so the glow pass gives the bigger stars a soft halo.
		mm.set_instance_color(i, c * rng.randf_range(0.9, 2.6))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_star_nodes.append(mmi)
	_glow_stars(rng)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -40, 0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.6
	add_child(sun)
	# Cool violet fill from the other side: the two-tone rim of the key art.
	fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, 140, 0)
	fill.light_color = Color("8a6cff")
	fill.light_energy = 0.7
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	for n: Node3D in _star_nodes:
		n.global_position = cam.global_position


## Big coloured stars of the key art: blue-white, gold and pink glow sprites.
func _glow_stars(rng: RandomNumberGenerator) -> void:
	if glow_star_count <= 0:
		return
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	m.no_depth_test = false
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	q.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = glow_star_count
	var tints := [Color(0.65, 0.8, 1.0), Color(1.0, 0.78, 0.45), Color(1.0, 0.55, 0.85), Color(1, 1, 1)]
	for i: int in glow_star_count:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * radius * 0.98
		var s := rng.randf_range(4.0, 11.0) * (2.2 if rng.randf() < 0.12 else 1.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), v))
		mm.set_instance_color(i, (tints[rng.randi() % tints.size()] as Color) * rng.randf_range(1.2, 2.4))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_star_nodes.append(mmi)


## Points the system's sun (key light + the sky's sun disc and fiery region).
func set_sun(rotation_deg: Vector3, energy: float = -1.0) -> void:
	if sun == null:
		return
	sun.rotation_degrees = rotation_deg
	if energy >= 0.0:
		sun.light_energy = energy


## Violet depth haze for scenes with far geometry (approach flight): distant
## asteroids fade into the nebula like the key art. The sky stays untouched.
func set_depth_haze(color: Color, density: float) -> void:
	if environment == null:
		return
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = color
	environment.fog_density = density
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.35
