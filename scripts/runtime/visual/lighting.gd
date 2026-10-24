class_name Lighting
extends RefCounted
## Light and atmosphere per world from data/art/lighting.json (defaults <- biome
## <- planet): gradient sky, sun, ambient, fog with sun scatter, tonemap, glow,
## SSAO (Forward+ only; ignored in Compatibility). Balance-style data, so the
## Synty look can be tuned without code (bible p.23: one light grammar).

const PATH := "res://data/art/lighting.json"

static var _data: Dictionary = {}


## Merged preset for a planet dictionary (needs "id" and "biome_id").
static func preset(planet: Dictionary) -> Dictionary:
	if _data.is_empty():
		var v: Variant = DictUtil.load_json(PATH)
		_data = v if v is Dictionary else {"defaults": {}}
	var out: Dictionary = DictUtil.get_dict(_data, "defaults").duplicate()
	out.merge(DictUtil.get_dict(DictUtil.get_dict(_data, "biomes"), str(planet.get("biome_id", ""))), true)
	out.merge(DictUtil.get_dict(DictUtil.get_dict(_data, "planets"), str(planet.get("id", ""))), true)
	return out


## [WorldEnvironment, DirectionalLight3D] ready to add to a scene.
static func build(planet: Dictionary) -> Array:
	var p := preset(planet)
	var c := func(k: String) -> Color: return Color(str(p.get(k, "#ffffff")))
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = c.call("sky_top")
	sky_mat.sky_horizon_color = c.call("sky_horizon")
	sky_mat.ground_horizon_color = c.call("ground_horizon")
	sky_mat.ground_bottom_color = c.call("ground_bottom")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = c.call("ambient_color")
	e.ambient_light_energy = float(p["ambient_energy"])
	e.ambient_light_sky_contribution = float(p["sky_contribution"])
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR if str(p.get("tonemap", "filmic")) == "linear" else Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = float(p["exposure"])
	e.tonemap_white = float(p["white"])
	e.fog_enabled = true
	e.fog_light_color = c.call("fog_color")
	e.fog_density = float(p["fog_density"])
	e.fog_sun_scatter = float(p["fog_sun_scatter"])
	e.fog_aerial_perspective = float(p["fog_aerial"])
	e.fog_sky_affect = 0.6
	# Height fog: ground-level haze for the captain, clear air for the overhead colony camera.
	e.fog_height = float(p.get("fog_height", 2.0))
	e.fog_height_density = float(p.get("fog_height_density", 0.06))
	if str(p.get("fog_mode", "exponential")) == "depth":
		# Synty demo recipe: clear air near the player, coloured depth haze far away.
		e.fog_mode = Environment.FOG_MODE_DEPTH
		e.fog_depth_begin = float(p.get("fog_depth_begin", 23.0))
		e.fog_depth_end = float(p.get("fog_depth_end", 430.0))
		e.fog_depth_curve = float(p.get("fog_depth_curve", 1.0))
		e.fog_light_energy = float(p.get("fog_energy", 1.0))
		e.fog_height_density = 0.0
	e.glow_enabled = float(p["glow"]) > 0.0
	e.glow_intensity = float(p["glow"])
	e.glow_bloom = float(p["glow_bloom"])
	e.ssao_enabled = bool(p["ssao"])
	e.ssao_radius = float(p.get("ssao_radius", 1.0))
	e.ssao_intensity = float(p.get("ssao_intensity", 2.0))
	e.ssao_power = float(p.get("ssao_power", 1.5))
	e.adjustment_enabled = not is_equal_approx(float(p["adjust_saturation"]), 1.0)
	e.adjustment_saturation = float(p["adjust_saturation"])
	var env := WorldEnvironment.new()
	env.environment = e
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(p["sun_pitch"]), float(p["sun_yaw"]), 0)
	sun.light_color = c.call("sun_color")
	sun.light_energy = float(p["sun_energy"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = float(p["shadow_distance"]) * Quality.value("shadow_distance_scale", 1.0)
	if Quality.value("shadow_single_cascade", 0.0) > 0.5:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # one shadow pass instead of four
	return [env, sun]
