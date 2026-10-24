class_name PlanetSky
extends RefCounted
## The sky of a world (data/art/ground_cover.json -> <planet>.sky, D-039):
## moons and giant planets hanging over the horizon (procedural planet shader,
## not fogged), an aurora ring on cold worlds and ambient motes (pollen, snow,
## dust) that travel with the captain. Presentation only.

const DISTANCE := 1500.0


static func build(planet_id: String, fallback: String) -> Node3D:
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
		root.add_child(slot)
		PlanetLook.apply(slot, str(body.get("biome", "ice")), str(body.get("tint", "#9aa8b8")), hash(planet_id) + i)
		if body.has("ring"):
			root.add_child(_ring(slot.position, radius, Color(str(body["ring"])), az))
		i += 1
	if sky.has("fauna"):
		var flock := FaunaFlock.build(DictUtil.get_dict(sky, "fauna"), hash(planet_id))
		if flock:
			root.add_child(flock)
	if sky.has("aurora"):
		root.add_child(_aurora(Color(str(sky["aurora"])), Color(str(sky.get("aurora_high", "#9a5cff")))))
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
