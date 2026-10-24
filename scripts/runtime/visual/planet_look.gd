class_name PlanetLook
extends RefCounted
## Gives a planet slot a procedural surface (art/shaders/planet.gdshader) when no
## imported planet model is mapped: continents, dunes or ice by biome, tinted with
## the planet's own nature colour, clouds and an atmosphere rim. Presentation only.

const SHADER := preload("res://art/shaders/planet.gdshader")
const BIOMES := {
	"green": {"ocean": "#123a5c", "high": "#d8d4c4", "atmo": "#7fb8ff", "sea": 0.5, "clouds": 0.5, "banding": 0.0},
	"desert": {"ocean": "#6b3d22", "high": "#f0d6a8", "atmo": "#ffb070", "sea": 0.36, "clouds": 0.12, "banding": 0.65},
	"ice": {"ocean": "#4e6f86", "high": "#ffffff", "atmo": "#bfe4ff", "sea": 0.42, "clouds": 0.35, "banding": 0.2},
}


static func apply(slot: VisualSlot, biome: String, tint: String, seed: int) -> void:
	if slot.using_asset:
		return
	var b: Dictionary = BIOMES.get(biome, BIOMES["green"])
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var base := Color.from_string(tint, Color("#4f8a5a")) if not tint.is_empty() else Color("#4f8a5a")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("ocean_color", Color(str(b["ocean"])))
	m.set_shader_parameter("high_color", Color(str(b["high"])))
	m.set_shader_parameter("atmo_color", Color(str(b["atmo"])))
	m.set_shader_parameter("sea_level", float(b["sea"]))
	m.set_shader_parameter("cloud_amount", float(b["clouds"]))
	m.set_shader_parameter("banding", float(b["banding"]))
	m.set_shader_parameter("seed", float(posmod(seed, 997)))
	m.set_shader_parameter("cloud_speed", 0.0 if FxEffect.reduced_motion() else 0.004)
	for mi: Node in slot.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh is SphereMesh:
			var smooth := SphereMesh.new()
			smooth.radius = (mesh as SphereMesh).radius
			smooth.height = (mesh as SphereMesh).height
			smooth.radial_segments = 128
			smooth.rings = 64
			(mi as MeshInstance3D).mesh = smooth
			(mi as MeshInstance3D).material_override = m
