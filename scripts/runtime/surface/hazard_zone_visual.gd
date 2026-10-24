class_name HazardZoneVisual
extends Node3D
## How an expedition hazard zone looks (D-043), replacing the flat translucent
## cylinder: a glowing ground ring with a hazard-tape band draped on the
## terrain at the zone edge (shape + colour, a11y), a low animated haze curtain
## standing on the edge, soft volumetric haze and motes inside per hazard type
## (spores, dust, cold mist, storm with lightning, heat shimmer, darkness), and
## small warning beacons with triangle plates around the edge that keep off
## routes and interactables. Purely visual: the Area3D, radius and drain stay
## in surface_scene. Look data: data/art/hazard_zones.json.

const PATH := "res://data/art/hazard_zones.json"
const GROUND_SHADER := preload("res://art/shaders/hazard_ground.gdshader")
const CURTAIN_SHADER := preload("res://art/shaders/hazard_curtain.gdshader")
const SHIMMER_SHADER := preload("res://art/shaders/hazard_shimmer.gdshader")
const BEACON_SHADER := preload("res://art/shaders/hazard_beacon.gdshader")

static var _noise: NoiseTexture2D
static var _puff: ImageTexture
static var _doc: Dictionary = {}

var radius := 10.0
var spec: Dictionary = {}
var ring_color := Color.YELLOW
var beacon_count := 0
var _terrain: TerrainBuilder
var _motion := 1.0
var _lights: Array = []  # [OmniLight3D, base energy]
var _flash: OmniLight3D
var _flash_t := 0.0
var _flash_wait := 3.0
var _flash_rng := RandomNumberGenerator.new()


## `node` sits at the zone centre on the ground. `routes`: Array of polylines
## (Array[Vector2]); `keep`: Array of [Vector2, clear radius] (interactables, lander).
static func build(terrain: TerrainBuilder, center: Vector2, p_radius: float, hazard_id: String, fallback_hex: String,
		routes: Array = [], keep: Array = []) -> HazardZoneVisual:
	var v := HazardZoneVisual.new()
	v.name = "HazardZoneVisual"
	v._terrain = terrain
	v.radius = p_radius
	v.spec = spec_for(hazard_id)
	v.ring_color = Color(str(v.spec.get("ring", fallback_hex)))
	v._motion = 0.0 if FxEffect.reduced_motion() else 1.0
	v._flash_rng.seed = hash(hazard_id) + int(center.x * 31.0 + center.y * 17.0)
	var base_y := v._mesh_h(center.x, center.y)
	v._build_ground(center, base_y)
	v._build_curtain(center, base_y)
	v._build_haze()
	v._build_motes()
	v._build_shimmer(center, base_y)
	v._build_beacons(center, base_y, routes, keep)
	if v.spec.has("flash") and v._motion > 0.0:
		var f: Dictionary = v.spec["flash"]
		v._flash = OmniLight3D.new()
		v._flash.light_color = Color(str(f.get("color", "#c9d6ff")))
		v._flash.omni_range = p_radius * 2.2
		v._flash.light_energy = 0.0
		v._flash.shadow_enabled = false
		v._flash.position = Vector3(0, 9.0, 0)
		v.add_child(v._flash)
	return v


static func spec_for(hazard_id: String) -> Dictionary:
	if _doc.is_empty():
		var d: Variant = DictUtil.load_json(PATH)
		_doc = d if d is Dictionary else {"default": {}}
	return DictUtil.get_dict(_doc, hazard_id) if _doc.has(hazard_id) else DictUtil.get_dict(_doc, "default")


## Height of the rendered terrain mesh (its two-triangle quads), not the smooth
## height function, so the decal hugs every facet.
func _mesh_h(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	var st := _terrain.step
	var half := _terrain.size_m * 0.5
	var gx := (x + half) / st
	var gz := (z + half) / st
	var ix := floorf(gx)
	var iz := floorf(gz)
	var fx := gx - ix
	var fz := gz - iz
	var x0 := -half + ix * st
	var z0 := -half + iz * st
	var h10 := _terrain.height_at(x0 + st, z0)
	var h01 := _terrain.height_at(x0, z0 + st)
	var h := 0.0
	if fx + fz <= 1.0:
		var h00 := _terrain.height_at(x0, z0)
		h = h00 + (h10 - h00) * fx + (h01 - h00) * fz
	else:
		var h11 := _terrain.height_at(x0 + st, z0 + st)
		h = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
	if _terrain.water_level > -50.0:
		h = maxf(h, _terrain.water_level + 0.04)
	return h


static func _noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = fn
	return _noise


## A soft wispy puff (radial falloff broken by fbm), generated once.
static func _puff_tex() -> ImageTexture:
	if _puff == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.045
		fn.fractal_octaves = 4
		fn.seed = 11
		var n := 96
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in n:
			for x: int in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var w := (y + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + w * w)
				var fall := pow(clampf(1.0 - r, 0.0, 1.0), 1.6)
				var nz := fn.get_noise_2d(x, y) * 0.5 + 0.5
				var a := clampf(fall * (0.35 + 1.1 * nz), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_puff = ImageTexture.create_from_image(img)
	return _puff


## Polar mesh draped on the terrain: rings at `radii`, UV.x = arc length at the
## zone edge, UV.y = distance from the centre.
func _build_ground(center: Vector2, base_y: float) -> void:
	var radii: Array[float] = [0.0]
	var r := 1.2
	while r < radius - 2.2:
		radii.append(r)
		r += 1.2
	r = maxf(radius - 2.2, 0.6)
	while r <= radius + 1.25:
		radii.append(r)
		r += 0.22
	var seg := maxi(72, int(TAU * radius / 0.45))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for rr: float in radii:
		var row: Array = []
		for i: int in seg + 1:
			var a := TAU * i / seg
			var p := center + Vector2.from_angle(a) * rr
			row.append([Vector3(p.x - center.x, _mesh_h(p.x, p.y) - base_y + 0.06, p.y - center.y), Vector2(a * radius, rr)])
		rows.append(row)
	for ri: int in rows.size() - 1:
		var ra: Array = rows[ri]
		var rb: Array = rows[ri + 1]
		for i: int in seg:
			for v: Array in [ra[i], rb[i], rb[i + 1], ra[i], rb[i + 1], ra[i + 1]]:
				st.set_uv(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "GroundRing"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("zone_color", ring_color)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("motion", _motion)
	m.set_shader_parameter("noise_tex", _noise_tex())
	var inner: Dictionary = DictUtil.get_dict(spec, "interior")
	m.set_shader_parameter("interior_color", Color(str(inner.get("color", ring_color.to_html()))))
	m.set_shader_parameter("interior_alpha", float(inner.get("alpha", 0.10)))
	m.render_priority = 1
	mi.material_override = m
	add_child(mi)


## A vertical ribbon around a circle, bottom edge on the terrain.
func _ribbon(center: Vector2, base_y: float, rr: float, height: float, mat: Material, nm: String) -> MeshInstance3D:
	var seg := maxi(64, int(TAU * rr / 0.6))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom: Array = []
	for i: int in seg + 1:
		var a := TAU * i / seg
		var p := center + Vector2.from_angle(a) * rr
		bottom.append(Vector3(p.x - center.x, _mesh_h(p.x, p.y) - base_y - 0.1, p.y - center.y))
	for i: int in seg:
		var a0 := TAU * i / seg * rr
		var a1 := TAU * (i + 1) / seg * rr
		var b0: Vector3 = bottom[i]
		var b1: Vector3 = bottom[i + 1]
		var t0 := b0 + Vector3(0, height, 0)
		var t1 := b1 + Vector3(0, height, 0)
		for q: Array in [[b0, Vector2(a0, 0)], [t0, Vector2(a0, 1)], [t1, Vector2(a1, 1)], [b0, Vector2(a0, 0)], [t1, Vector2(a1, 1)], [b1, Vector2(a1, 0)]]:
			st.set_uv(q[1])
			st.add_vertex(q[0])
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	add_child(mi)
	return mi


func _build_curtain(center: Vector2, base_y: float) -> void:
	var c: Dictionary = DictUtil.get_dict(spec, "curtain")
	if c.is_empty():
		return
	var m := ShaderMaterial.new()
	m.shader = CURTAIN_SHADER
	m.set_shader_parameter("zone_color", Color(str(c.get("color", DictUtil.get_dict(spec, "haze").get("color", ring_color.to_html())))))
	m.set_shader_parameter("strength", float(c.get("alpha", 0.3)))
	m.set_shader_parameter("motion", _motion)
	m.set_shader_parameter("noise_tex", _noise_tex())
	_ribbon(center, base_y, radius + 0.05, float(c.get("height", 2.4)), m, "EdgeCurtain")


func _build_shimmer(center: Vector2, base_y: float) -> void:
	var s: Dictionary = DictUtil.get_dict(spec, "shimmer")
	if s.is_empty():
		return
	var m := ShaderMaterial.new()
	m.shader = SHIMMER_SHADER
	m.set_shader_parameter("strength", float(s.get("strength", 0.012)))
	m.set_shader_parameter("motion", _motion)
	m.set_shader_parameter("noise_tex", _noise_tex())
	m.set_shader_parameter("tint", Color(str(s.get("color", DictUtil.get_dict(spec, "haze").get("color", "#ffb070")))))
	for f: float in [0.96, 0.6]:
		_ribbon(center, base_y, radius * f, 3.0 * (0.7 + 0.3 * f), m, "Shimmer")


func _particle_mat(color: Color, additive: bool, soft: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.disable_fog = true  # fog on an additive quad adds the fog colour: white blobs in hazy air
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	m.albedo_texture = _puff_tex()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if soft > 0.0:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = soft
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.0
	m.distance_fade_max_distance = 4.5
	return m


func _alpha_ramp(alpha: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, alpha), Color(1, 1, 1, alpha), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 64
	return gt


func _build_haze() -> void:
	var h: Dictionary = DictUtil.get_dict(spec, "haze")
	if h.is_empty():
		return
	var size: Array = DictUtil.get_arr(h, "size")
	var hgt: Array = DictUtil.get_arr(h, "height")
	var smin := float(size[0]) if size.size() == 2 else 3.0
	var smax := float(size[1]) if size.size() == 2 else 6.0
	var hmin := float(hgt[0]) if hgt.size() == 2 else 0.5
	var hmax := float(hgt[1]) if hgt.size() == 2 else 2.5
	var area := PI * radius * radius
	var amount := clampi(int(area / 10.0 * float(h.get("density", 1.4))), 16, 72)
	var p := GPUParticles3D.new()
	p.name = "Haze"
	p.amount = amount
	p.lifetime = 9.0 / maxf(0.25, _motion)
	p.preprocess = 9.0
	p.speed_scale = lerpf(0.4, 1.0, _motion)
	p.randomness = 0.6
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-radius - 4, -4, -radius - 4), Vector3(radius * 2 + 8, hmax + 12, radius * 2 + 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.86
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = maxf(0.1, hmax - hmin)
	pm.emission_shape_offset = Vector3(0, (hmin + hmax) * 0.5, 0)
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.flatness = 1.0
	var spd := float(h.get("speed", 0.3))
	pm.initial_velocity_min = spd * 0.4
	pm.initial_velocity_max = spd
	pm.gravity = Vector3.ZERO
	pm.tangential_accel_min = float(h.get("swirl", 0.1)) * 0.5
	pm.tangential_accel_max = float(h.get("swirl", 0.1))
	pm.damping_min = spd * 0.3
	pm.damping_max = spd * 0.6
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -8.0
	pm.angular_velocity_max = 8.0
	pm.scale_min = 1.0
	pm.scale_max = smax / smin
	pm.color_ramp = _alpha_ramp(float(h.get("alpha", 0.2)))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(smin, smin)
	q.material = _particle_mat(Color(str(h.get("color", "#cccccc"))), str(h.get("blend", "mix")) == "add", 1.4)
	p.draw_pass_1 = q
	add_child(p)


func _build_motes() -> void:
	var mo: Dictionary = DictUtil.get_dict(spec, "motes")
	if mo.is_empty():
		return
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = clampi(int(mo.get("count", 100)) / (2 if _motion < 0.5 else 1), 8, 220)
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.speed_scale = lerpf(0.4, 1.0, _motion)
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-radius - 2, -2, -radius - 2), Vector3(radius * 2 + 4, 10, radius * 2 + 4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.92
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 2.6
	pm.emission_shape_offset = Vector3(0, 1.4, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	var rise := float(mo.get("rise", 0.2))
	pm.initial_velocity_min = rise * 0.5
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0.05, 0, 0.03)
	pm.turbulence_enabled = false
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = _alpha_ramp(0.95)
	p.process_material = pm
	var q := QuadMesh.new()
	var sz := float(mo.get("size", 0.06))
	q.size = Vector2(sz, sz)
	var m := _particle_mat(Color(str(mo.get("color", "#ffffff"))), true, 0.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	m.albedo_texture = gt
	m.albedo_color = Color(str(mo.get("color", "#ffffff"))) * 1.8
	m.distance_fade_min_distance = 0.3
	m.distance_fade_max_distance = 1.2
	q.material = m
	p.draw_pass_1 = q
	add_child(p)


static func _dist_to_lines(p: Vector2, lines: Array) -> float:
	var best := INF
	for line: Array in lines:
		for i: int in line.size() - 1:
			var a: Vector2 = line[i]
			var ab: Vector2 = line[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


## Warning poles just outside the edge: dark pole, hazard-colour collar, a
## warning triangle facing outward and a lamp that chases around the zone.
func _build_beacons(center: Vector2, base_y: float, routes: Array, keep: Array) -> void:
	var b: Dictionary = DictUtil.get_dict(spec, "beacons")
	if b.is_empty():
		return
	var br := radius + 0.45
	var n := clampi(int(round(TAU * br / float(b.get("spacing", 7.5)))), 6, 16)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#2b2f33")
	metal.metallic = 0.6
	metal.roughness = 0.45
	var collar := StandardMaterial3D.new()
	collar.albedo_color = ring_color
	collar.emission_enabled = true
	collar.emission = ring_color
	collar.emission_energy_multiplier = 0.8
	var plate_bg := StandardMaterial3D.new()
	plate_bg.albedo_color = Color("#15171a")
	plate_bg.roughness = 0.6
	var plate := StandardMaterial3D.new()
	plate.albedo_color = ring_color
	plate.emission_enabled = true
	plate.emission = ring_color
	plate.emission_energy_multiplier = 0.55
	var lamp := ShaderMaterial.new()
	lamp.shader = BEACON_SHADER
	lamp.set_shader_parameter("lamp_color", ring_color)
	lamp.set_shader_parameter("motion", _motion)
	var pole_m := CylinderMesh.new()
	pole_m.top_radius = 0.035
	pole_m.bottom_radius = 0.05
	pole_m.height = 1.55
	pole_m.radial_segments = 8
	var base_m := CylinderMesh.new()
	base_m.top_radius = 0.16
	base_m.bottom_radius = 0.24
	base_m.height = 0.12
	base_m.radial_segments = 10
	var collar_m := CylinderMesh.new()
	collar_m.top_radius = 0.055
	collar_m.bottom_radius = 0.055
	collar_m.height = 0.22
	collar_m.radial_segments = 8
	var tri_bg := PrismMesh.new()
	tri_bg.size = Vector3(0.46, 0.4, 0.025)
	var tri := PrismMesh.new()
	tri.size = Vector3(0.34, 0.29, 0.03)
	var bulb := SphereMesh.new()
	bulb.radius = 0.075
	bulb.height = 0.15
	bulb.radial_segments = 10
	bulb.rings = 6
	var phase := float(hash(center)) * 0.0001
	var placed := 0
	for i: int in n:
		var a := phase + TAU * i / n
		var p := center + Vector2.from_angle(a) * br
		if _dist_to_lines(p, routes) < 2.6:
			continue
		var blocked := false
		for k: Array in keep:
			if p.distance_to(k[0]) < float(k[1]):
				blocked = true
		if blocked:
			continue
		var pole := Node3D.new()
		pole.name = "Beacon%d" % i
		pole.position = Vector3(p.x - center.x, _mesh_h(p.x, p.y) - base_y - 0.04, p.y - center.y)
		pole.rotation.y = -a + PI * 0.5  # local +Z faces outward
		add_child(pole)
		for part: Array in [[base_m, metal, Vector3(0, 0.06, 0)], [pole_m, metal, Vector3(0, 0.8, 0)], [collar_m, collar, Vector3(0, 0.95, 0)],
				[tri_bg, plate_bg, Vector3(0, 1.27, 0.06)], [tri, plate, Vector3(0, 1.255, 0.075)], [bulb, lamp, Vector3(0, 1.62, 0)]]:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.material_override = part[1]
			mi.position = part[2]
			if part[1] == lamp or part[1] == plate:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pole.add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.12
		cyl.height = 1.6
		cs.shape = cyl
		cs.position.y = 0.8
		body.add_child(cs)
		pole.add_child(body)
		if placed % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = ring_color
			l.omni_range = 3.2
			l.light_energy = 0.7
			l.shadow_enabled = false
			l.position = Vector3(0, 1.62, 0.1)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 45.0
			l.distance_fade_length = 15.0
			pole.add_child(l)
			_lights.append([l, a])
		placed += 1
	beacon_count = placed
	lamp.set_shader_parameter("center", Vector3.ZERO)  # set for real once in the tree
	set_meta("lamp_mat", lamp)


func _ready() -> void:
	var lamp: ShaderMaterial = get_meta("lamp_mat", null)
	if lamp:
		lamp.set_shader_parameter("center", global_position)
	_flash_wait = _flash_rng.randf_range(1.0, 3.0)
	set_process(_motion > 0.0)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for la: Array in _lights:  # follow the lamp shader's chase
		var ph := fposmod((la[1] as float) / TAU + t * 0.32, 1.0)
		(la[0] as OmniLight3D).light_energy = 0.35 + 1.4 * pow(ph, 10.0)
	if _flash:
		_flash_wait -= delta
		if _flash_wait <= 0.0:
			var f: Dictionary = spec["flash"]
			var iv: Array = DictUtil.get_arr(f, "interval")
			_flash_wait = _flash_rng.randf_range(float(iv[0]) if iv.size() == 2 else 3.0, float(iv[1]) if iv.size() == 2 else 6.0)
			_flash_t = 0.32
			var off := Vector2.from_angle(_flash_rng.randf() * TAU) * _flash_rng.randf() * radius * 0.6
			_flash.position = Vector3(off.x, 7.0 + _flash_rng.randf() * 4.0, off.y)
		if _flash_t > 0.0:
			_flash_t -= delta
			# a double flicker: two quick peaks, then decay
			var k := clampf(_flash_t / 0.32, 0.0, 1.0)
			var flick := 1.0 if (k > 0.75 or (k > 0.35 and k < 0.55)) else 0.25
			_flash.light_energy = float(spec["flash"].get("energy", 6.0)) * k * flick
		else:
			_flash.light_energy = 0.0
