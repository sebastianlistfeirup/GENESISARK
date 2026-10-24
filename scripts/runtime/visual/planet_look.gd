class_name PlanetLook
extends RefCounted
## Gives a planet slot its look in space when no imported planet model is mapped.
## With a planet id and the POLYGON Sci-Fi Space planet masks present (D-044):
## the pack-sheet look (art/shaders/planet_synty.gdshader, data
## data/art/space_planets.json): banded, ringed, terran with clouds, glowing veins.
## Otherwise the procedural fallback (art/shaders/planet.gdshader): continents,
## dunes or ice by biome, tinted with the planet's nature colour. Presentation only.

const SHADER := preload("res://art/shaders/planet.gdshader")
const SYNTY_SHADER := preload("res://art/shaders/planet_synty.gdshader")
const RING_SHADER := preload("res://art/shaders/planet_ring.gdshader")
const DATA := "res://data/art/space_planets.json"
const BIOMES := {
	"green": {"ocean": "#123a5c", "high": "#d8d4c4", "atmo": "#7fb8ff", "sea": 0.5, "clouds": 0.5, "banding": 0.0},
	"desert": {"ocean": "#6b3d22", "high": "#f0d6a8", "atmo": "#ffb070", "sea": 0.36, "clouds": 0.12, "banding": 0.65},
	"ice": {"ocean": "#4e6f86", "high": "#ffffff", "atmo": "#bfe4ff", "sea": 0.42, "clouds": 0.35, "banding": 0.2},
}

static var _doc: Dictionary = {}
static var _tex: Dictionary = {}


static func apply(slot: VisualSlot, biome: String, tint: String, seed: int, planet_id: String = "") -> void:
	if not slot.is_inside_tree() or slot.get_child_count() == 0:
		# Not built yet (VisualSlot builds in _ready): apply right after it is.
		slot.rebuilt.connect(apply.bind(slot, biome, tint, seed, planet_id), CONNECT_ONE_SHOT)
		return
	if slot.using_asset:
		return
	# Only callers that name a planet get the sheet look (space views); the
	# surface skies' moons keep the procedural look.
	var m := synty_material(planet_id, seed) if not planet_id.is_empty() else null
	var ring: Dictionary = {}
	if m != null:
		ring = DictUtil.get_dict(DictUtil.get_dict(DictUtil.get_dict(_data(), "planets"), planet_id), "ring")
	else:
		m = _procedural(biome, tint, seed)
	for mi: Node in slot.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh is SphereMesh:
			var r := (mesh as SphereMesh).radius
			var smooth := SphereMesh.new()
			smooth.radius = r
			smooth.height = (mesh as SphereMesh).height
			smooth.radial_segments = 128
			smooth.rings = 64
			(mi as MeshInstance3D).mesh = smooth
			(mi as MeshInstance3D).material_override = m
			if not ring.is_empty():
				(mi as Node3D).add_child(ring_node(r, ring))


## The sheet-look material for a planet id, or null when the id has no entry or
## the pack's masks are missing (callers then keep the procedural look).
static func synty_material(planet_id: String, seed: int) -> ShaderMaterial:
	var d: Dictionary = DictUtil.get_dict(DictUtil.get_dict(_data(), "planets"), planet_id)
	if d.is_empty() or _texture("lines") == null or _texture("land") == null:
		return null
	return sheet_material(d, seed)


## Builds the sheet-look material from one look entry (also used for the
## approach's gas giants, whose entries live under "gas_giants").
static func sheet_material(d: Dictionary, seed: int) -> ShaderMaterial:
	if _texture("lines") == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = SYNTY_SHADER
	m.set_shader_parameter("land_tex", _texture("land"))
	m.set_shader_parameter("cloud_tex", _texture("cloud"))
	m.set_shader_parameter("lines_tex", _texture("lines"))
	for key: String in ["ocean", "land", "land2", "band_a", "band_b", "atmo", "vein"]:
		if d.has(key):
			var param: String = {"ocean": "ocean_color", "land": "land_color", "land2": "land_color2", "atmo": "atmo_color", "vein": "vein_color"}.get(key, key)
			m.set_shader_parameter(param, Color(str(d[key])))
	m.set_shader_parameter("land_amount", float(d.get("land_amount", 0.0)))
	m.set_shader_parameter("land_scale", float(d.get("land_scale", 1.0)))
	m.set_shader_parameter("sea_shift", float(d.get("sea_shift", 0.0)))
	m.set_shader_parameter("bands", float(d.get("bands", 0.0)))
	m.set_shader_parameter("band_scale", float(d.get("band_scale", 1.0)))
	m.set_shader_parameter("band_wobble", float(d.get("band_wobble", 0.04)))
	m.set_shader_parameter("cloud_amount", float(d.get("clouds", 0.0)))
	m.set_shader_parameter("vein_amount", float(d.get("vein_amount", 0.0)))
	m.set_shader_parameter("craters", float(d.get("craters", 0.0)))
	m.set_shader_parameter("crater_scale", float(d.get("crater_scale", 5.0)))
	m.set_shader_parameter("rim_energy", float(d.get("rim", 1.2)))
	m.set_shader_parameter("soft_light", float(d.get("soft", 0.55)))
	m.set_shader_parameter("seed", float(posmod(seed, 997)))
	m.set_shader_parameter("spin_speed", 0.0 if FxEffect.reduced_motion() else 0.003)
	return m


## A flat ring around a planet of radius r: the pack's ring texture when present.
static func ring_node(r: float, ring: Dictionary) -> MeshInstance3D:
	var rq := PlaneMesh.new()
	rq.size = Vector2.ONE * r * float(ring.get("scale", 4.4))
	var rm := ShaderMaterial.new()
	rm.shader = RING_SHADER
	rm.set_shader_parameter("ring_color", Color(str(ring.get("color", "#e8d2b4"))))
	rm.set_shader_parameter("band_color", Color(str(ring.get("band", "#8a7262"))))
	rm.set_shader_parameter("inner", float(ring.get("inner", 0.5)))
	var rt := _texture("ring")
	if rt != null:
		rm.set_shader_parameter("ring_tex", rt)
		rm.set_shader_parameter("use_tex", 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Ring"
	mi.mesh = rq
	mi.material_override = rm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t: Array = DictUtil.get_arr(ring, "tilt")
	if t.size() == 3:
		mi.rotation_degrees = Vector3(float(t[0]), float(t[1]), float(t[2]))
	return mi


static func _procedural(biome: String, tint: String, seed: int) -> ShaderMaterial:
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
	return m


static func _data() -> Dictionary:
	if _doc.is_empty():
		var d: Variant = DictUtil.load_json(DATA)
		_doc = d if d is Dictionary else {"planets": {}}
	return _doc


static func _texture(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var path := str(DictUtil.get_dict(_data(), "textures").get(key, ""))
	var t: Texture2D = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null
	# The pack imports these without mipmaps (and its import settings are not
	# ours to change): build a mipmapped copy once, so the soft coasts, inland
	# shading and glowing veins can read blurred levels of the masks.
	if t != null:
		var img := t.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_tex[key] = t
	return t
