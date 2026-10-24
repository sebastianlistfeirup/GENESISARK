class_name PlanetLook
extends RefCounted
## Gives a planet slot its look in space when no imported planet model is mapped.
## With a planet id and the POLYGON Sci-Fi Space planet masks present (D-044):
## the pack-sheet look (art/shaders/planet_synty.gdshader, data
## data/art/space_planets.json): banded, ringed, terran with clouds, glowing veins.
## Otherwise the procedural fallback (art/shaders/planet.gdshader): continents,
## dunes or ice by biome, tinted with the planet's nature colour. Presentation only.
## D-046: a planet entry may name a faceted POLYGON Sci-Fi Space planet model
## ("mesh", normalised to the slot's sphere radius), an atmosphere halo
## ("halo", art/shaders/planet_atmo.gdshader) and moons ("moons", looks from
## "moon_looks"). Without the pack the smooth sphere, halo and moons stay.

const SHADER := preload("res://art/shaders/planet.gdshader")
const SYNTY_SHADER := preload("res://art/shaders/planet_synty.gdshader")
const RING_SHADER := preload("res://art/shaders/planet_ring.gdshader")
const ATMO_SHADER := preload("res://art/shaders/planet_atmo.gdshader")
const DATA := "res://data/art/space_planets.json"
const BIOMES := {
	"green": {"ocean": "#123a5c", "high": "#d8d4c4", "atmo": "#7fb8ff", "sea": 0.5, "clouds": 0.5, "banding": 0.0},
	"desert": {"ocean": "#6b3d22", "high": "#f0d6a8", "atmo": "#ffb070", "sea": 0.36, "clouds": 0.12, "banding": 0.65},
	"ice": {"ocean": "#4e6f86", "high": "#ffffff", "atmo": "#bfe4ff", "sea": 0.42, "clouds": 0.35, "banding": 0.2},
}

static var _doc: Dictionary = {}
static var _tex: Dictionary = {}
static var _meshes: Dictionary = {}  # path -> [Mesh, centre: Vector3, mean radius: float] (or [] when missing)


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
	var d: Dictionary = {}
	if m != null:
		d = DictUtil.get_dict(DictUtil.get_dict(_data(), "planets"), planet_id)
	else:
		m = _procedural(biome, tint, seed)
	for n: Node in slot.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not (mi.mesh is SphereMesh) or mi.has_meta("planet_body"):
			continue
		var r := (mi.mesh as SphereMesh).radius
		var centre := mi.position
		var model: Array = model_of(str(d.get("mesh", "")))
		if model.is_empty():
			var smooth := SphereMesh.new()
			smooth.radius = r
			smooth.height = (mi.mesh as SphereMesh).height
			smooth.radial_segments = 128
			smooth.rings = 64
			mi.mesh = smooth
		else:
			fit_model(mi, model, r, centre, DictUtil.get_arr(d, "tilt"))
		mi.material_override = m
		mi.set_meta("planet_body", true)
		if d.is_empty():
			continue
		# Halo, ring and moons hang off a sibling at the planet's centre, so the
		# model's own scale (normalised to r) never scales them.
		var extras := Node3D.new()
		extras.name = "PlanetExtras"
		extras.position = centre
		mi.get_parent().add_child(extras)
		if float(d.get("halo", 1.0)) > 0.0:
			extras.add_child(halo_node(r, Color(str(d.get("halo_color", d.get("atmo", "#8fd0ff")))), float(d.get("halo", 1.0))))
		var ring: Dictionary = DictUtil.get_dict(d, "ring")
		if not ring.is_empty():
			extras.add_child(ring_node(r, ring))
		var mi_idx := 0
		for moon: Variant in DictUtil.get_arr(d, "moons"):
			var mn := moon_node(r, moon as Dictionary, seed + 101 * (mi_idx + 1))
			if mn:
				extras.add_child(mn)
			mi_idx += 1


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
	# The halo shell (D-046) carries most of the glow now: a softer own rim.
	m.set_shader_parameter("rim_energy", float(d.get("rim", 1.2)) * 0.55)
	m.set_shader_parameter("soft_light", float(d.get("soft", 0.55)))
	m.set_shader_parameter("seed", float(posmod(seed, 997)))
	m.set_shader_parameter("spin_speed", 0.0 if FxEffect.reduced_motion() else 0.003)
	return m


## The atmosphere halo: a lit additive shell a little larger than the planet.
static func halo_node(r: float, color: Color, strength: float, scale_r: float = 1.1) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r * scale_r
	sm.height = r * scale_r * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	var hm := ShaderMaterial.new()
	hm.shader = ATMO_SHADER
	hm.set_shader_parameter("halo_color", color)
	hm.set_shader_parameter("strength", 0.8 * strength)
	hm.set_shader_parameter("shell", scale_r)
	var mi := MeshInstance3D.new()
	mi.name = "Halo"
	mi.mesh = sm
	mi.material_override = hm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A moon beside a planet of radius r: a faceted pack model (or a low sphere)
## in a look from "moon_looks"; pos is in planet radii from its centre.
static func moon_node(r: float, spec: Dictionary, seed: int) -> Node3D:
	var look: Dictionary = DictUtil.get_dict(DictUtil.get_dict(_data(), "moon_looks"), str(spec.get("look", "")))
	var m := sheet_material(look, seed) if not look.is_empty() else null
	if m == null:
		return null
	var size := r * float(spec.get("size", 0.2))
	var mi := MeshInstance3D.new()
	mi.name = "Moon"
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	var p: Array = DictUtil.get_arr(spec, "pos")
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2])) * r if p.size() == 3 else Vector3(r * 1.8, r * 0.3, 0)
	var model := model_of(str(spec.get("mesh", look.get("mesh", ""))))
	if model.is_empty():
		mi.position = pos
	else:
		fit_model(mi, model, size, pos, DictUtil.get_arr(spec, "tilt"))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if float(look.get("halo", 0.0)) > 0.0:
		var holder := Node3D.new()
		holder.name = "MoonHolder"
		holder.add_child(mi)
		var h := halo_node(size, Color(str(look.get("atmo", "#ffffff"))), float(look.get("halo", 0.0)), 1.1)
		h.position = pos
		holder.add_child(h)
		return holder
	return mi


## Swaps a sphere's mesh for a pack planet model: centred on `at`, its mean
## radius scaled to r, optionally tilted (degrees) so the bands lean.
static func fit_model(mi: MeshInstance3D, model: Array, r: float, at: Vector3, tilt: Array) -> void:
	mi.mesh = model[0]
	var s := r / maxf(0.001, float(model[2]))
	var b := Basis().scaled(Vector3.ONE * s)
	if tilt.size() == 3:
		b = Basis.from_euler(Vector3(deg_to_rad(float(tilt[0])), deg_to_rad(float(tilt[1])), deg_to_rad(float(tilt[2])))) * b
	mi.transform = Transform3D(b, at - b * (model[1] as Vector3))


## [mesh, centre, mean radius] of a pack planet model, cached; [] when missing.
static func model_of(path: String) -> Array:
	if path.is_empty():
		return []
	if _meshes.has(path):
		return _meshes[path]
	var out: Array = []
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps:
			var inst := ps.instantiate()
			var mis: Array = [inst] if inst is MeshInstance3D else []
			mis.append_array(inst.find_children("*", "MeshInstance3D", true, false))
			for n: Variant in mis:
				var mi := n as MeshInstance3D
				if mi and mi.mesh:
					var box := mi.mesh.get_aabb()
					out = [mi.mesh, box.get_center(), (box.size.x + box.size.y + box.size.z) / 6.0]
					break
			inst.free()
	_meshes[path] = out
	return out


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
