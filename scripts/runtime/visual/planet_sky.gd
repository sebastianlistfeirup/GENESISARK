class_name PlanetSky
extends RefCounted
## The sky of a world (data/art/ground_cover.json -> <planet>.sky, D-039):
## moons and giant planets hanging over the horizon (procedural planet shader,
## not fogged), an aurora ring on cold worlds and ambient motes (pollen, snow,
## dust) that travel with the captain. Presentation only.

const DISTANCE := 1500.0


static func build(planet_id: String, fallback: String, terrain: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "PlanetSky"
	var sky: Dictionary = DictUtil.get_dict(GroundCover.spec_for(planet_id, fallback), "sky")
	var i := 0
	for b: Variant in DictUtil.get_arr(sky, "bodies"):
		var body: Dictionary = b
		var az := deg_to_rad(DictUtil.get_float(body, "azimuth"))
		var el := deg_to_rad(DictUtil.get_float(body, "elevation", 20.0))
		var radius := DISTANCE * tan(deg_to_rad(DictUtil.get_float(body, "size", 12.0)) * 0.5)
		var slot := VisualSlot.make("space.planet_" + str(body.get("biome", "ice")))
		var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		slot.position = dir * DISTANCE
		slot.scale = Vector3.ONE * radius / 60.0  # planet slots are 60 m spheres
		slot.rotation = Vector3(DictUtil.get_float(body, "tilt") * 0.0174, az, 0.3)
		slot.set_meta("sky_far", true)  # hangs at sky distance: the descent keeps it around the camera
		root.add_child(slot)
		PlanetLook.apply(slot, str(body.get("biome", "ice")), str(body.get("tint", "#9aa8b8")), hash(planet_id) + i)
		if body.has("ring"):
			var rg := _ring(slot.position, radius, Color(str(body["ring"])), az)
			rg.set_meta("sky_far", true)
			root.add_child(rg)
		i += 1
	for key: String in ["fauna", "fauna_low"]:
		if sky.has(key):
			var flock := FaunaFlock.build(DictUtil.get_dict(sky, key), hash(planet_id + key), terrain)
			if flock:
				root.add_child(flock)
	if sky.has("creatures"):
		var cr := SkyCreatures.build(DictUtil.get_arr(sky, "creatures"), hash(planet_id + "creatures"), terrain)
		if cr:
			root.add_child(cr)
	if sky.has("leviathan") and terrain and float(terrain.get("water_level")) > -50.0:
		var lv := SeaLeviathan.build(DictUtil.get_dict(sky, "leviathan"), float(terrain.get("water_level")), hash(planet_id + "leviathan"))
		if lv:
			root.add_child(lv)
	if sky.has("clouds"):
		var cl := _clouds(DictUtil.get_dict(sky, "clouds"), hash(planet_id + "clouds"), terrain)
		cl.set_meta("sky_far", true)
		root.add_child(cl)
	if sky.has("sun_size"):
		var sun := _sun(planet_id, fallback, DictUtil.get_float(sky, "sun_size"), Color(str(sky.get("sun_color", "#fff2c8"))))
		sun.set_meta("sky_far", true)
		root.add_child(sun)
	if sky.has("debris"):
		root.add_child(_debris(DictUtil.get_dict(sky, "debris"), hash(planet_id + "debris")))
	if sky.has("aurora"):
		var au := _aurora(Color(str(sky["aurora"])), Color(str(sky.get("aurora_high", "#9a5cff"))))
		au.set_meta("sky_far", true)
		root.add_child(au)
	return root


static func _ring(pos: Vector3, radius: float, color: Color, az: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 1.35
	tm.outer_radius = radius * 2.1
	tm.rings = 96
	tm.ring_segments = 3
	mi.mesh = tm
	mi.scale = Vector3(1, 0.02, 1)
	mi.position = pos
	mi.rotation = Vector3(0.35, az, 0.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_fog = true
	m.albedo_color = Color(color.r, color.g, color.b, 0.45)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _aurora(low: Color, high: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 900.0
	cm.bottom_radius = 1000.0
	cm.height = 260.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 96
	mi.mesh = cm
	mi.position = Vector3(0, 330, 0)
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/aurora.gdshader")
	m.set_shader_parameter("low_color", low)
	m.set_shader_parameter("high_color", high)
	m.set_shader_parameter("speed", 0.0 if FxEffect.reduced_motion() else 0.02)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Ambient motes that follow a node (the captain): an existing FX scene.
static func motes(planet_id: String, fallback: String) -> Node3D:
	var sky: Dictionary = DictUtil.get_dict(GroundCover.spec_for(planet_id, fallback), "sky")
	var fx := str(sky.get("motes", ""))
	if fx.is_empty():
		return null
	var v := VisualSlot.make(fx)
	v.position = Vector3(0, 1.5, 0)
	v.scale = Vector3.ONE * DictUtil.get_float(sky, "motes_scale", 2.5)
	return v


## The system's star as a big glowing disc with a soft halo, placed where the
## world's key light comes from (Lighting preset), unfogged, so it blooms.
static func _sun(planet_id: String, biome: String, size_deg: float, color: Color) -> Node3D:
	var p := Lighting.preset({"id": planet_id, "biome_id": biome})
	var basis := Basis.from_euler(Vector3(deg_to_rad(float(p.get("sun_pitch", -45))), deg_to_rad(float(p.get("sun_yaw", 30))), 0))
	var dir := basis.z.normalized()  # a DirectionalLight shines along -Z; the sun sits toward +Z
	var holder := Node3D.new()
	holder.name = "Sun"
	var r := DISTANCE * tan(deg_to_rad(size_deg) * 0.5)
	for layer: Array in [[1.0, 6.0, 1.0], [2.6, 1.6, 0.35], [6.0, 0.6, 0.12]]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * r * 2.0 * float(layer[0])
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.disable_fog = true
		m.albedo_color = Color(color.r, color.g, color.b, float(layer[2]))
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = float(layer[1])
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var gr := Gradient.new()
		gr.set_color(0, Color.WHITE)
		gr.set_color(1, Color(1, 1, 1, 0))
		if float(layer[0]) == 1.0:
			gr.add_point(0.85, Color.WHITE)
		g.gradient = gr
		m.albedo_texture = g
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = dir * DISTANCE * 1.1
		holder.add_child(mi)
	return holder


## Rock fragments and scrap hanging and drifting in the sky (ref: Sci-Fi Worlds key art).
static func _debris(spec: Dictionary, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "SkyDebris"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var meshes: Array = []
	for m: Variant in DictUtil.get_arr(spec, "meshes"):
		var src := GroundCover.mesh_of(str(m))
		if not src.is_empty():
			meshes.append(src)
	if meshes.is_empty():
		return root
	var by: Dictionary = {}
	for i: int in int(spec.get("count", 60)):
		var k := rng.randi() % meshes.size()
		var a := rng.randf() * TAU
		var dist := rng.randf_range(60.0, 260.0)
		var pos := Vector3(cos(a) * dist, rng.randf_range(35.0, 120.0), sin(a) * dist)
		var s := rng.randf_range(float(DictUtil.get_arr(spec, "scale")[0]), float(DictUtil.get_arr(spec, "scale")[1])) if DictUtil.get_arr(spec, "scale").size() == 2 else 0.1
		var xf := Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * s), pos) * (meshes[k][1] as Transform3D)
		if not by.has(k):
			by[k] = []
		(by[k] as Array).append(xf)
	for k: int in by.keys():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k][0]
		mm.instance_count = (by[k] as Array).size()
		for i: int in mm.instance_count:
			mm.set_instance_transform(i, by[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	return root


## A loose deck of stylized cloud puffs high over the map (same puffs as the
## descent's cloud deck, so the sky you flew through is the one you stand under).
static func _clouds(spec: Dictionary, seed_value: int, terrain: Node3D) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = int(spec.get("count", 90))
	var base := float(terrain.call("height_at", 0.0, 0.0)) if terrain else 0.0
	var h: Array = DictUtil.get_arr(spec, "height")
	for i: int in mm.instance_count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * DictUtil.get_float(spec, "radius", 700.0)
		var y := base + (rng.randf_range(float(h[0]), float(h[1])) if h.size() == 2 else 260.0)
		var sc := rng.randf_range(60.0, 150.0) * DictUtil.get_float(spec, "scale", 1.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(cos(a) * r, y, sin(a) * r)))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/cloud_sky.gdshader")
	var col := Color(str(spec.get("color", "#f4f2ec")))
	mat.set_shader_parameter("lit", col)
	mat.set_shader_parameter("shade", col.darkened(0.3).lerp(Color(str(spec.get("shade", "#9aa6bc"))), 0.5))
	mat.set_shader_parameter("opacity", DictUtil.get_float(spec, "opacity", 0.75))
	mat.set_shader_parameter("near_fade", 60.0)
	mat.set_shader_parameter("far_fade", 2600.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Clouds"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1200, -100, -1200), Vector3(2400, 900, 2400))
	return mmi
