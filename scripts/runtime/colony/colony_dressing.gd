class_name ColonyDressing
extends Node3D
## Draws every building's planned dressing (BuildingDressing) as one MultiMesh
## per mesh for the whole colony, plus small lamps that glow on dark worlds.
## A prop is dropped when it would touch another building's footprint, a
## corridor tube or a road, so placement and collision stay owned by the domain
## and the building views. A dropped prop first gets a second chance on another
## side of its own building, and the lanes between buildings get street
## furniture (ColonyInfill). Platform tiles take their district's tint.
## Rebuilt only when the building set changes. Presentation only: no collision,
## no picking.

const MAX_LIGHTS := 48

var _bulb_mesh: SphereMesh
## Props that survived the clearance test: [Vector2 position, radius] (walkers keep off them).
var kept: Array = []
## Evidence/debug: how many props were planned, kept on the first try, moved, and added as infill.
var stats := {}
## Where idle colonists stand and browse at the market corners: [Vector2, yaw] (ColonyLife).
var crowd: Array = []
## Ground the street life took (ColonyStreets items and crowd spots): plants growing there are pruned.
var street_area := ColonyClearance.new()
var _prop_fx: Array = []  # [Vector3 world position, slot, scale] from set entries with "fx" (smoking silos)

static var _tint_cache: Dictionary = {}  # "mesh id|tint" -> Mesh
var _on_platform: ColonyClearance  # footprints of the buildings that stand on platform tiles
var _margin := 0.0
## World id for the weathering look (set by the scene before rebuild).
var weather_world := ""


## views: building id -> BuildingView. clear: ColonyClearance with footprints,
## corridors and roads. light_scale: lamp brightness for this world.
## districts: [[key, Vector2 centre, radius]] for the street furniture.
## night: this world's night look (data "night"): emissive boost, light pools, roof beacons.
## roads: the road polylines (ColonyPaths.roads) for the roadside signs and parked vehicles.
## avoid: [[Vector2, radius]] ground the street life keeps off (the site's rock formations).
func rebuild(views: Dictionary, terrain: TerrainBuilder, clear: ColonyClearance, light_scale: float, districts: Array = [], night: Dictionary = {},
		roads: Array = [], avoid: Array = []) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var batches: Dictionary = {}  # Mesh -> Array[Transform3D]
	var ranges: Dictionary = {}   # Mesh -> visibility range
	var lights: Array = []        # [Vector3 pos, Color]
	var retry: Array = []         # [BuildingView, item]
	kept.clear()
	stats = {"planned": 0, "first": 0, "moved": 0, "infill": 0, "street": 0, "crowd": 0, "pools": 0}
	_prop_fx = []
	street_area = ColonyClearance.new()
	crowd = []
	_margin = BuildingDressing.platform_margin()
	_on_platform = ColonyClearance.new()
	for bid: int in views.keys():
		var bv: BuildingView = views[bid]
		if is_instance_valid(bv) and BuildingDressing.pad_style(bv.def_id) == "skirt":
			var fs: Vector2 = bv.footprint()
			if posmod(roundi(bv.rotation.y / (PI * 0.5)), 2) == 1:
				fs = Vector2(fs.y, fs.x)
			_on_platform.add_rect(Rect2(Vector2(bv.position.x, bv.position.z) - fs * 0.5, fs), bid)
	for bid: int in views.keys():
		var v: BuildingView = views[bid]
		if not is_instance_valid(v) or v.dressing.is_empty():
			continue
		var vxf := v.global_transform if v.is_inside_tree() else v.transform
		for it: Dictionary in v.dressing:
			var kind := str(it["kind"])
			if v.constructing() and not bool(it["build"]):
				continue
			var xf: Transform3D = vxf * (it["xf"] as Transform3D)
			if kind != "platform":
				stats["planned"] += 1
				var p := Vector2(xf.origin.x, xf.origin.z)
				if clear.blocked(p, float(it["r"]), bid):
					retry.append([v, it])
					continue
				stats["first"] += 1
				kept.append([p, float(it["r"])])
			_emit(batches, ranges, lights, it, xf, vxf.origin.y, terrain)
	# Rooftop greebles on the flat parts of finished roofs.
	for bid: int in views.keys():
		var v: BuildingView = views[bid]
		if not is_instance_valid(v) or v.constructing():
			continue
		var vxf := v.global_transform if v.is_inside_tree() else v.transform
		for it: Dictionary in ColonyRoofs.plan(v):
			stats["roof"] = int(stats.get("roof", 0)) + 1
			_emit(batches, ranges, lights, it, vxf * (it["xf"] as Transform3D), vxf.origin.y, terrain)
	# Second chance: the same prop on the opposite side (or, for a square
	# footprint, a quarter turn) of its own building, if that side is free.
	var taken := ColonyClearance.new()
	for k: Array in kept:
		taken.add_segment(k[0], k[0], float(k[1]) * 0.8)
	for rt: Array in retry:
		var v: BuildingView = rt[0]
		var it: Dictionary = rt[1]
		var vxf := v.global_transform if v.is_inside_tree() else v.transform
		var size: Vector2 = v.footprint()
		var turns: Array = [PI, PI * 0.5, -PI * 0.5] if absf(size.x - size.y) < 0.6 else [PI]
		var r := float(it["r"])
		for ang: float in turns:
			var xf: Transform3D = vxf * Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO) * (it["xf"] as Transform3D)
			var p := Vector2(xf.origin.x, xf.origin.z)
			if clear.blocked(p, r, v.building_id) or taken.blocked(p, r * 0.8):
				continue
			stats["moved"] += 1
			kept.append([p, r])
			taken.add_segment(p, p, r * 0.8)
			_emit(batches, ranges, lights, it, xf, vxf.origin.y, terrain)
			break
	var pools: Array = []
	if not districts.is_empty():
		# Street life first (markets need the open courtyards), then the furniture fills the lanes.
		var room := ColonyClearance.new()
		for k: Array in kept:
			room.add_segment(k[0], k[0], float(k[1]) * 0.85)
		for a: Array in avoid:
			room.add_segment(a[0], a[0], float(a[1]))
		var street: Dictionary = ColonyStreets.plan(clear, room, districts, roads)
		for it: Dictionary in street["items"]:
			var xf: Transform3D = it["xf"]
			kept.append([Vector2(xf.origin.x, xf.origin.z), float(it["r"])])
			if float(it["r"]) > 0.0:
				var half := Vector2.ONE * float(it["r"])
				street_area.add_rect(Rect2(Vector2(xf.origin.x, xf.origin.z) - half, half * 2.0), -1)
			stats["street"] += 1
			_emit(batches, ranges, lights, it, xf, 0.0, terrain)
		crowd = street["crowd"]
		for c: Array in crowd:
			kept.append([c[0], 0.35])
			street_area.add_rect(Rect2((c[0] as Vector2) - Vector2.ONE * 0.4, Vector2.ONE * 0.8), -1)
		pools = street["pools"]
		for pl: Array in pools:
			kept.append([pl[0], (pl[1] as Vector2).x])
		stats["crowd"] = crowd.size()
		stats["street_counts"] = street["counts"]
		stats["pools"] = pools.size()
		for it: Dictionary in ColonyInfill.plan(clear, kept, districts):
			var xf: Transform3D = it["xf"]
			kept.append([Vector2(xf.origin.x, xf.origin.z), float(it["r"])])
			stats["infill"] += 1
			_emit(batches, ranges, lights, it, xf, 0.0, terrain)
	for m: Mesh in batches.keys():
		var xfs: Array = batches[m]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = float(ranges[m])
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	_add_lights(lights, light_scale)
	_add_night(views, night)
	_add_weathering(views, terrain, clear)
	_add_fx(views)
	_add_pools(pools, terrain)
	# D-054: per-chunk LOD and culling for the colony-wide batches (ranges kept for the overhead camera).
	MeshLod.split_multimeshes(self, 40.0, 300.0)


## Biome weathering at the foundations (data "weathering" per world): soft,
## flattened mounds of dust, snow or mud half over each platform edge, so the
## buildings sit in the ground instead of on it. One MultiMesh, no collision.
func _add_weathering(views: Dictionary, terrain: TerrainBuilder, clear: ColonyClearance) -> void:
	var cfg: Dictionary = DictUtil.get_dict(DictUtil.get_dict(BuildingDressing.doc(), "weathering"), weather_world)
	if cfg.is_empty():
		return
	var xfs: Array = []
	var per := DictUtil.get_float(cfg, "per_m", 0.35)
	var sz: Array = DictUtil.get_arr(cfg, "size")
	for bid: int in views.keys():
		var v: BuildingView = views[bid]
		if not is_instance_valid(v) or v.constructing():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("weather#%d" % bid)
		var fs: Vector2 = v.footprint()
		if BuildingDressing.pad_style(v.def_id) != "skirt":
			continue  # drifts lean on platform edges; free-standing machines stay clean
		var m := _margin
		var hx := fs.x * 0.5 + m
		var hz := fs.y * 0.5 + m
		var vxf := v.global_transform if v.is_inside_tree() else v.transform
		for side: int in 4:
			var along := hx * 2.0 if side < 2 else hz * 2.0
			var n := int(along * per * rng.randf_range(0.6, 1.2))
			for k: int in n:
				var t := rng.randf_range(-0.5, 0.5) * along
				var local := Vector3(t, 0, (hz + 0.1) * (1.0 if side == 0 else -1.0)) if side < 2 else Vector3((hx + 0.1) * (1.0 if side == 2 else -1.0), 0, t)
				var w: Vector3 = vxf * local
				var p := Vector2(w.x, w.z)
				if clear.blocked(p, 0.2, bid):
					continue
				var s := rng.randf_range(float(sz[0]) if sz.size() == 2 else 0.6, float(sz[1]) if sz.size() == 2 else 1.4)
				# Long and low along the edge, the way wind piles dust or snow against a wall.
				var edge_yaw := (0.0 if side < 2 else PI * 0.5) + rng.randf_range(-0.15, 0.15)
				var basis := (vxf.basis.orthonormalized() * Basis(Vector3.UP, edge_yaw)).scaled(Vector3(s * rng.randf_range(1.6, 2.6), s * DictUtil.get_float(cfg, "height", 0.18), s * rng.randf_range(0.55, 0.85)))
				xfs.append(Transform3D(basis, Vector3(p.x, terrain.height_at(p.x, p.y) - 0.02, p.y)))
	if xfs.is_empty():
		return
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 7
	sm.rings = 2
	sm.is_hemisphere = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(cfg.get("color", "#c8a878")))
	mat.roughness = DictUtil.get_float(cfg, "roughness", 1.0)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 160.0
	add_child(mmi)


## Life on the machines (data "fx" per building type): steam over geothermal
## generators and water plants, sparks at workshops. Capped per type and only
## on finished buildings; missing effect scenes fall back to the slot proxy.
func _add_fx(views: Dictionary) -> void:
	# The shared effects, then the style's own (scavenger chimneys smoke).
	for li: int in 2:
		var cfg: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "fx") if li == 0 else BuildingDressing.style_cfg("fx")
		if not cfg.is_empty():
			_add_fx_list(views, cfg)
	# Effects carried by street props (set field "fx"), capped by data "street_fx_max".
	var cap := DictUtil.get_int(BuildingDressing.doc(), "street_fx_max", 8)
	for i: int in mini(cap, _prop_fx.size()):
		var e: Array = _prop_fx[i]
		var n := VisualSlot.make(str(e[1]))
		n.scale = Vector3.ONE * float(e[2])
		n.position = e[0]
		add_child(n)
		stats["fx_" + str(e[1]).trim_prefix("fx.")] = int(stats.get("fx_" + str(e[1]).trim_prefix("fx."), 0)) + 1


func _add_fx_list(views: Dictionary, cfg: Dictionary) -> void:
	var count := {}
	var ids := views.keys()
	ids.sort()
	for bid: int in ids:
		var v: BuildingView = views[bid]
		if not is_instance_valid(v) or v.constructing() or not cfg.has(v.def_id):
			continue
		var f: Dictionary = cfg[v.def_id]
		if int(count.get(v.def_id, 0)) >= DictUtil.get_int(f, "max", 4):
			continue
		count[v.def_id] = int(count.get(v.def_id, 0)) + 1
		stats["fx_" + str(f.get("slot", "fx.steam_vent")).trim_prefix("fx.")] = int(stats.get("fx_" + str(f.get("slot", "fx.steam_vent")).trim_prefix("fx."), 0)) + 1
		var n := VisualSlot.make(str(f.get("slot", "fx.steam_vent")))
		var at: Array = DictUtil.get_arr(f, "at")  # [x, z] in footprint halves, y = roof or given
		var fs: Vector2 = v.footprint()
		var y := v.visual_top() * DictUtil.get_float(f, "top", 1.0) if f.has("top") else DictUtil.get_float(f, "y", 0.2)
		var local := Vector3((float(at[0]) if at.size() == 2 else 0.0) * fs.x * 0.5, y, (float(at[1]) if at.size() == 2 else 0.0) * fs.y * 0.5)
		n.scale = Vector3.ONE * DictUtil.get_float(f, "scale", 0.5)
		add_child(n)
		n.global_transform = Transform3D(Basis.from_scale(n.scale), (v.global_transform if v.is_inside_tree() else v.transform) * local)


## Night worlds: every active building's emissive windows burn brighter, a soft
## warm pool of light spills around it (a capped, spread subset of real lights)
## and the tall ones carry a slow red roof beacon (one MultiMesh, shader blink).
func _add_night(views: Dictionary, night: Dictionary) -> void:
	var glow := DictUtil.get_float(night, "windows", 1.0)
	var pools: Array = []
	var beacons: Array = []
	var min_h := DictUtil.get_float(night, "beacon_min_h", 5.0)
	for bid: int in views.keys():
		var v: BuildingView = views[bid]
		if not is_instance_valid(v):
			continue
		v.set_glow(glow if not v.constructing() else 1.0)
		if night.is_empty() or v.constructing():
			continue
		var fs: Vector2 = v.footprint()
		var cool := v.def_id in DictUtil.get_arr(night, "cool_defs")
		pools.append([v.position + Vector3(0, 1.2, 0), maxf(fs.x, fs.y) * 0.75 + 3.0, cool])
		var top := v.visual_top()
		if top >= min_h:
			beacons.append(v.global_transform * Vector3(0, top + 0.15, 0) if v.is_inside_tree() else v.position + Vector3(0, top + 0.15, 0))
	if night.is_empty():
		return
	var cap := DictUtil.get_int(night, "pool_max", 36)
	var step := maxi(1, int(ceil(pools.size() / float(cap))))
	var pc := Color(str(night.get("pool", "#ffc98a")))
	var pcool := Color(str(night.get("pool_cool", "#8fd6ff")))
	for i: int in range(0, pools.size(), step):
		var ol := OmniLight3D.new()
		ol.position = pools[i][0]
		ol.light_color = pcool if bool(pools[i][2]) else pc
		ol.light_energy = DictUtil.get_float(night, "pool_energy", 1.0)
		ol.omni_range = float(pools[i][1])
		ol.omni_attenuation = 1.6
		ol.shadow_enabled = false
		ol.light_specular = 0.1
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 140.0
		ol.distance_fade_length = 40.0
		add_child(ol)
	if beacons.is_empty() or not night.has("beacon"):
		return
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 8
	sm.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = sm
	mm.instance_count = beacons.size()
	for i: int in beacons.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, beacons[i]))
		mm.set_instance_custom_data(i, Color(fmod(i * 0.37, 1.0), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _beacon_shader()
	mat.set_shader_parameter("col", Color(str(night["beacon"])))
	mmi.material_override = mat
	mmi.visibility_range_end = 400.0
	add_child(mmi)


## Signs and holograms spill their colour (data "street_glow": capped, spread
## subset of real lights, no shadows, stronger on night worlds).
func _add_glows(glows: Array, light_scale: float) -> void:
	var cfg: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "street_glow")
	if glows.is_empty() or light_scale <= 0.05 or cfg.is_empty():
		return
	var step := maxi(1, int(ceil(glows.size() / float(DictUtil.get_int(cfg, "max", 20)))))
	for i: int in range(0, glows.size(), step):
		var ol := OmniLight3D.new()
		ol.position = glows[i][0]
		ol.light_color = glows[i][1]
		ol.light_energy = DictUtil.get_float(cfg, "energy", 1.2) * light_scale
		ol.omni_range = DictUtil.get_float(cfg, "range", 5.0)
		ol.omni_attenuation = 1.4
		ol.shadow_enabled = false
		ol.light_specular = 0.3
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 110.0
		ol.distance_fade_length = 30.0
		add_child(ol)


## Toxic spill pools (style "pools", scavenger industry): a dark crusted rim and
## a glowing, slowly rippling surface, two MultiMeshes for the whole colony.
func _add_pools(pools: Array, terrain: TerrainBuilder) -> void:
	var cfg: Dictionary = BuildingDressing.style_cfg("pools")
	if pools.is_empty() or cfg.is_empty():
		return
	# An organic puddle outline from the pack (data "mesh"), normalised to radius 1; else a disc.
	var shape: Mesh = null
	var norm := Transform3D.IDENTITY
	var pr: Dictionary = BuildingDressing.parts(str(cfg.get("mesh", "")))
	if not pr.is_empty():
		shape = (pr["parts"] as Array)[0][0]
		var box: AABB = shape.get_aabb()
		var k := 2.0 / maxf(maxf(box.size.x, box.size.z), 0.01)
		norm = Transform3D(Basis.from_scale(Vector3(k, 1.0, k)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z))
	else:
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.06
		disc.radial_segments = 14
		disc.rings = 1
		shape = disc
	for layer: int in 2:  # 0 = rim, 1 = liquid
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shape
		mm.instance_count = pools.size()
		for i: int in pools.size():
			var pl: Array = pools[i]
			var c: Vector2 = pl[0]
			var rad: Vector2 = (pl[1] as Vector2) * (1.25 if layer == 0 else 1.0)
			var b := Basis(Vector3.UP, float(pl[2]) + (0.35 if layer == 0 else 0.0)) * Basis.from_scale(Vector3(rad.x, 1.0 if layer == 0 else 1.5, rad.y))
			mm.set_instance_transform(i, Transform3D(b, Vector3(c.x, terrain.height_at(c.x, c.y) + (0.02 if layer == 0 else 0.05), c.y)) * norm)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if layer == 0:
			var rim := StandardMaterial3D.new()
			rim.albedo_color = Color(str(cfg.get("rim", "#3a3a24")))
			rim.roughness = 0.9
			mmi.material_override = rim
		else:
			var mat := ShaderMaterial.new()
			mat.shader = _pool_shader()
			mat.set_shader_parameter("col", Color(str(cfg.get("color", "#c8f03c"))))
			mat.set_shader_parameter("energy", DictUtil.get_float(cfg, "energy", 1.6))
			mmi.material_override = mat
		mmi.visibility_range_end = 260.0
		add_child(mmi)


static var _pool_sh: Shader


static func _pool_shader() -> Shader:
	if _pool_sh == null:
		_pool_sh = Shader.new()
		_pool_sh.code = """shader_type spatial;
render_mode shadows_disabled;
uniform vec4 col : source_color = vec4(0.78, 0.94, 0.24, 1.0);
uniform float energy = 1.6;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = sin(wp.x * 2.3 + TIME * 1.1) * sin(wp.z * 2.9 - TIME * 0.8);
	float k = 0.75 + 0.25 * r;
	ALBEDO = col.rgb * 0.35;
	ROUGHNESS = 0.15;
	EMISSION = col.rgb * energy * k;
}
"""
	return _pool_sh


static var _beacon_sh: Shader


static func _beacon_shader() -> Shader:
	if _beacon_sh == null:
		_beacon_sh = Shader.new()
		_beacon_sh.code = """shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.3, 0.2, 1.0);
varying float phase;
void vertex() { phase = INSTANCE_CUSTOM.r; }
void fragment() {
	float t = fract(TIME * 0.55 + phase);
	float on = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.12, 0.3, t));
	ALBEDO = col.rgb * (0.35 + on);
	EMISSION = col.rgb * (0.2 + on * 5.0);
}
"""
	return _beacon_sh


## Queue one placed item (world transform xf; base_y = its building's ground).
func _emit(batches: Dictionary, ranges: Dictionary, lights: Array, it: Dictionary, xf: Transform3D, base_y: float, terrain: TerrainBuilder) -> void:
	var kind := str(it["kind"])
	if kind != "platform" and kind != "roof":
		# Stand on the real ground (the ring can leave the flattened district),
		# or on the platform tiles where the prop's base reaches over them.
		var p := Vector2(xf.origin.x, xf.origin.z)
		var on_tiles := _on_platform != null and _on_platform.blocked(p, float(it["r"]) * 0.6 + _margin - 0.25, -1, true)
		xf.origin.y = terrain.height_at(p.x, p.y) + (xf.origin.y - base_y) + (0.05 if on_tiles else -0.03)
	var pr: Dictionary = BuildingDressing.parts(str(it["mesh"]))
	var big := kind in ["platform", "park"] or float(it["top"]) > 2.5
	var tint := str(it.get("tint", ""))
	for part: Array in pr["parts"]:
		var m: Mesh = part[0]
		if not tint.is_empty():
			m = _tinted(m, tint)
		if not m.has_meta("short"):
			m.set_meta("short", str(it["mesh"]))  # debug/evidence name (tri_audit)
		if not batches.has(m):
			batches[m] = []
			ranges[m] = 0.0
		(batches[m] as Array).append(xf * (part[1] as Transform3D))
		var reach := 110.0 if kind in ["infill", "roof"] else 190.0
		if big:
			reach = 300.0 if kind == "street" else 420.0
		ranges[m] = maxf(float(ranges[m]), reach)
	var col := str(it["light"])
	if not col.is_empty():
		lights.append([xf * (it["light_at"] as Vector3), Color(col)])
	var fx := str(it.get("fx", ""))
	if not fx.is_empty():
		_prop_fx.append([xf * (it["fx_at"] as Vector3), fx, float(it.get("fx_scale", 0.5))])
	var glow := str(it.get("glow", ""))
	if not glow.is_empty():  # neon signs and holograms: a coloured light spill, no bulb
		lights.append([xf * (it["glow_at"] as Vector3), Color(glow), true])


## A copy of the mesh whose standard materials are multiplied by a tint (the
## district's paving colour). Shader materials are left as they are.
static func _tinted(m: Mesh, tint: String) -> Mesh:
	var key := "%d|%s" % [m.get_instance_id(), tint]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var out: Mesh = m
	if m is ArrayMesh:
		out = (m as ArrayMesh).duplicate()
		var f := tint.split_floats(",")
		var col := Color(f[0], f[1], f[2]) if f.size() >= 3 else Color(tint)
		for s: int in out.get_surface_count():
			var mat := out.surface_get_material(s)
			if mat is StandardMaterial3D:
				var t := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				t.albedo_color = t.albedo_color * col
				(out as ArrayMesh).surface_set_material(s, t)
			elif mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("BaseColor") is Color:
				# Synty's Generic_Basic shader multiplies its atlas by BaseColor.
				var sm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
				sm.set_shader_parameter("BaseColor", (sm.get_shader_parameter("BaseColor") as Color) * col)
				(out as ArrayMesh).surface_set_material(s, sm)
	_tint_cache[key] = out
	return out


## Each lamp gets a small glowing bulb; a capped, evenly spread subset also casts
## real light (no shadows, fades out with distance) so the colony glows at night.
func _add_lights(all: Array, light_scale: float) -> void:
	var lights: Array = []
	var glows: Array = []
	for l: Array in all:
		(glows if l.size() > 2 else lights).append(l)
	_add_glows(glows, light_scale)
	if lights.is_empty():
		return
	if _bulb_mesh == null:
		_bulb_mesh = SphereMesh.new()
		_bulb_mesh.radius = 0.14
		_bulb_mesh.height = 0.28
		_bulb_mesh.radial_segments = 8
		_bulb_mesh.rings = 4
	var by_col: Dictionary = {}
	for l: Array in lights:
		var key := (l[1] as Color).to_html(false)
		if not by_col.has(key):
			by_col[key] = []
		(by_col[key] as Array).append(l[0])
	for key: String in by_col.keys():
		var pts: Array = by_col[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _bulb_mesh
		mm.instance_count = pts.size()
		for i: int in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(key)
		mat.emission_enabled = true
		mat.emission = Color(key)
		mat.emission_energy_multiplier = 2.0 + 2.0 * light_scale
		mmi.material_override = mat
		mmi.visibility_range_end = 260.0
		add_child(mmi)
	if light_scale <= 0.05:
		return
	var step := maxi(1, int(ceil(lights.size() / float(MAX_LIGHTS))))
	for i: int in range(0, lights.size(), step):
		var l: Array = lights[i]
		var ol := OmniLight3D.new()
		ol.position = (l[0] as Vector3) + Vector3(0, 0.25, 0)
		ol.light_color = l[1]
		ol.light_energy = 1.4 * light_scale
		ol.omni_range = 7.0
		ol.omni_attenuation = 1.2
		ol.shadow_enabled = false
		ol.light_specular = 0.2
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 120.0
		ol.distance_fade_length = 40.0
		add_child(ol)
