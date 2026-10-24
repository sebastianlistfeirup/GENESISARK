class_name PlanetDescent
extends Node3D
## Real-time descent from low orbit to the expedition site in one continuous
## shot (owner: "like No Man's Sky"). The lander starts kilometres above a
## planet-sized globe in open space, flies down through a burning atmospheric
## entry and the cloud deck, the sky turns from nebula to the planet's own sky,
## the haze clears over the real site terrain, and it sets down on the camp pad.
## Autopilot flies a glide path by default; the player can take the stick at any
## time ([F]), throttle, steer and dive. Landing assist takes over near the pad,
## so every descent ends on the site. Presentation only: the domain already
## holds the landed expedition, and the suit clock waits until touchdown.
## Skippable ([Enter]); reduced motion uses the short drop-in instead.

signal finished

const R_PLANET := 9000.0      # radius of the stand-in globe under the site
const START_ALT := 5200.0
const START_RANGE := 6800.0
const SWITCH_ALT := 1250.0    # space sky -> planet sky, hidden in the cloud whiteout
const CLOUD_ALT := Vector2(1080.0, 1480.0)
const ASSIST_RANGE := 170.0   # horizontal metres from the pad where landing assist engages
const ASSIST_ALT := 320.0
const HOVER_ALT := 26.0

var terrain: TerrainBuilder
var planet: Dictionary = {}
var target := Vector3.ZERO        # pad (lander rest position)
var lander_body: Node3D           # the lander's VisualSlot, flown top-level during the descent
var surface_root: Node3D

var autopilot := true
var _ascent := false
var _climb_dir := Vector3.FORWARD
var _asc_t := 0.0
var scale_k := 1.0
var _body_rest := Transform3D.IDENTITY   # the body's own local transform, restored at touchdown
var _rest_basis := Basis.IDENTITY
var nose_yaw := PI  # Synty ships face +Z; callers flying a long-in-X model (the landed Ark) set -PI/2                # camera and landing distances scale with the ship (the Ark is huge)
var _layers: Array[CanvasLayer] = []
var _vel := Vector3.ZERO
var _alt := START_ALT
var _phase := "space"
var _landing := false
var _done := false
var _bank := 0.0
var _shake := 0.0
var _t := 0.0
var _manual_hold := 0.0

var _cam: Camera3D
var _cam_pos := Vector3.ZERO
var _cam_off := Vector3(0, 6, 20)
var _world_env: WorldEnvironment
var _planet_env: Environment
var _space_env: Environment
var _fog: Dictionary = {}
var _hidden: Array[Node3D] = []
var _globe_space: Node3D
var _globe_ground: MeshInstance3D
var _horizon: MeshInstance3D
var _sea: MeshInstance3D
var _site_water: MeshInstance3D  # the playable map's own sea plane, hidden under _sea while in the air
var _horizon_bits: Array[Node3D] = []
var _mothership: Node3D
var _ark_pending := false
var _clouds: MultiMeshInstance3D
var _plasma: MeshInstance3D
var _plasma_mat: ShaderMaterial
var _glow_light: OmniLight3D
var _streaks: MultiMeshInstance3D
var _streak_mat: ShaderMaterial
var _streak_pts: Array = []
var _roar := false  # [local offset (ship frame), length]
var _vignette: ColorRect
var _thruster: Node3D
var _marker: Label3D
var _hud: CanvasLayer
var _white: ColorRect
var _lbl_phase: Label
var _lbl_data: Label
var _lbl_hint: Label
var _gauge: DescentHud
var _sky_tint := Color(0.85, 0.9, 1.0)
var _sky_far: Array = []  # [node, rest position]: moons, sun, rings, aurora of the planet's sky
var _haze := Color(0.8, 0.86, 0.9)


static func wanted() -> bool:
	return not FxEffect.reduced_motion() and bool(SettingsService.get_value("realtime_descent", true))


func start(p_root: Node3D, p_terrain: TerrainBuilder, p_planet: Dictionary, p_target: Vector3, p_body: Node3D, start_alt: float = START_ALT) -> void:
	_setup(p_root, p_terrain, p_planet, p_target, p_body)
	# Come in from the sunward side, kilometres out and high: the globe's curve
	# and the terminator fill the view, the site is a marker far below.
	var dir := Vector2.from_angle(deg_to_rad(float(hash(str(planet.get("id", ""))) % 360)))
	var alt := clampf(start_alt, 60.0, START_ALT)
	var k := alt / START_ALT
	var p := Vector3(dir.x * START_RANGE * k, target.y + alt, dir.y * START_RANGE * k)
	lander_body.top_level = true
	lander_body.global_position = p
	_vel = (Vector3(target.x, target.y + alt * 0.55, target.z) - p).normalized() * lerpf(80.0, 360.0, k)
	_alt = alt
	_cam_pos = p - _vel.normalized() * 30.0 + Vector3.UP * 8.0
	_cam_off = _cam_pos - p
	_ark_pending = _mothership != null
	_phase = _phase_for(alt)
	_set_sky(alt > SWITCH_ALT)
	AudioService.set_ambience_any(["amb_space"])
	AudioService.play("sfx_thruster", "SFX", -10.0)


## The way home: lift-off from the pad, a climbing turn out over the land, up
## through the cloud deck into space; `finished` fires high in orbit (the caller
## then changes scene). Cinematic (no stick), skippable.
func start_ascent(p_root: Node3D, p_terrain: TerrainBuilder, p_planet: Dictionary, p_body: Node3D) -> void:
	_setup(p_root, p_terrain, p_planet, p_body.global_position, p_body)
	_ascent = true
	autopilot = true
	lander_body.top_level = true
	_alt = 0.0
	var dir := Vector2.from_angle(deg_to_rad(float(hash(str(planet.get("id", ""))) % 360) + 140.0))
	_climb_dir = Vector3(dir.x, 0.0, dir.y)
	var p := lander_body.global_position
	_cam_off = (-_climb_dir * 16.0 + Vector3.UP * 4.0 + _climb_dir.cross(Vector3.UP) * 9.0) * scale_k
	_cam_pos = p + _cam_off
	_phase = "atmos"
	_set_sky(false)
	_marker.visible = false
	var dust := VisualSlot.make("fx.landing_dust")
	var lander := lander_body.get_parent() as Node3D
	if lander:
		lander.add_child(dust)
		get_tree().create_timer(4.0).timeout.connect(dust.queue_free)
	AudioService.play("sfx_thruster", "SFX", -6.0)


## Evidence captures: run the flight forward by `seconds` of simulated time.
func debug_advance(seconds: float) -> void:
	var steps := int(seconds * 60.0)
	for i: int in steps:
		if _done:
			return
		_process(1.0 / 60.0)


func _setup(p_root: Node3D, p_terrain: TerrainBuilder, p_planet: Dictionary, p_target: Vector3, p_body: Node3D) -> void:
	surface_root = p_root
	terrain = p_terrain
	planet = p_planet
	target = p_target
	lander_body = p_body
	_body_rest = p_body.transform
	_rest_basis = p_body.global_basis
	var box := AssetSlots.aabb_of(p_body, Transform3D.IDENTITY)
	scale_k = clampf(box.size.length() / 14.0, 1.0, 8.0)
	for c: Node in p_root.get_children():
		if c is CanvasLayer and (c as CanvasLayer).visible:
			(c as CanvasLayer).visible = false
			_layers.append(c)
	# Sky bodies hang 1.5 km from the site: from the air they must stay at sky
	# distance around the camera, not turn into nearby spheres and a fence of aurora.
	var ps := p_root.get_node_or_null("PlanetSky")
	if ps:
		for c: Node in ps.get_children():
			if c is Node3D and c.has_meta("sky_far"):
				_sky_far.append([c, (c as Node3D).position])
	_world_env = _find_env(p_root)
	_planet_env = _world_env.environment if _world_env else null
	_remember_fog()
	_sky_tint = _planet_env.fog_light_color if _planet_env else _sky_tint
	var pre := Lighting.preset(planet)
	_haze = Color(str(pre.get("sky_horizon", "#d0dce6")))
	_sky_tint = _haze
	_build_space_env()
	_build_globes()
	_horizon = terrain.build_horizon(7200.0, 90.0, R_PLANET)
	_stretch_cover(true)
	_build_horizon_scatter()
	_build_mothership()
	_build_clouds()
	_build_ship_fx()
	_build_hud()
	_cam = Camera3D.new()
	_cam.near = 0.5
	_cam.far = 60000.0
	_cam.fov = 66.0
	add_child(_cam)
	_cam.current = true


func _find_env(n: Node) -> WorldEnvironment:
	for c: Node in n.get_children():
		if c is WorldEnvironment:
			return c
	return null


func _remember_fog() -> void:
	if _planet_env == null:
		return
	_fog = {"color": _planet_env.fog_light_color, "sky_affect": _planet_env.fog_sky_affect, "begin": _planet_env.fog_depth_begin, "end": _planet_env.fog_depth_end, "density": _planet_env.fog_density, "enabled": _planet_env.fog_enabled,
		"height_density": _planet_env.fog_height_density, "aerial": _planet_env.fog_aerial_perspective}


func _restore_fog() -> void:
	if _planet_env == null or _fog.is_empty():
		return
	_planet_env.fog_depth_begin = _fog["begin"]
	_planet_env.fog_depth_end = _fog["end"]
	_planet_env.fog_density = _fog["density"]
	_planet_env.fog_height_density = _fog["height_density"]
	_planet_env.fog_aerial_perspective = _fog["aerial"]
	_planet_env.fog_light_color = _fog["color"]
	_planet_env.fog_sky_affect = _fog["sky_affect"]


## Thin the planet's haze with altitude so the ground shows through from high up
## (the playable terrain's own fog is tuned for walking height).
func _fog_for_alt(alt: float) -> void:
	if _planet_env == null or _fog.is_empty():
		return
	var k := clampf(alt / 40.0, 1.0, 60.0)
	_planet_env.fog_depth_begin = float(_fog["begin"]) + alt * 0.9
	_planet_env.fog_depth_end = float(_fog["end"]) + alt * 4.5 + smoothstep(0.0, 900.0, alt) * 2500.0
	_planet_env.fog_density = float(_fog["density"]) / k
	_planet_env.fog_height_density = float(_fog["height_density"]) / k
	# From the air the haze is the sky's own horizon colour (aerial perspective),
	# not the ground-level fog tint; it eases back to the walking fog on the way down.
	var air := smoothstep(60.0, 500.0, alt)
	_planet_env.fog_light_color = (_fog["color"] as Color).lerp(_haze, air)
	_planet_env.fog_sky_affect = lerpf(float(_fog["sky_affect"]), 0.15, air)


func _build_space_env() -> void:
	var e := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://art/shaders/nebula_sky.gdshader")
	sky_mat.set_shader_parameter("seed", float(posmod(hash(str(planet.get("id", ""))), 97)))
	sky_mat.set_shader_parameter("star_boost", 1.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("5a4a7a")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.12
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	_space_env = e


func _hide_surface() -> void:
	if not _hidden.is_empty():
		return
	for c: Node in surface_root.get_children():
		if c == self or c is WorldEnvironment or c is DirectionalLight3D or not (c is Node3D):
			continue
		var n := c as Node3D
		if n.visible and n != lander_body and not lander_body.is_ancestor_of(n) and n != lander_body.get_parent():
			n.visible = false
			_hidden.append(n)
	# The lander node itself stays (its body flies top-level); its interactable gizmos hide.
	var lp := lander_body.get_parent()
	if lp is Node3D and lp != surface_root:
		for c: Node in lp.get_children():
			if c != lander_body and c is Node3D and (c as Node3D).visible:
				(c as Node3D).visible = false
				_hidden.append(c)


func _show_surface() -> void:
	for n: Node3D in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()


func _build_globes() -> void:
	var centre := Vector3(target.x, target.y - R_PLANET - 14.0, target.z)
	# From orbit: the planet's own space look (faceted Synty globe, halo, moons).
	var biome := str(planet.get("biome_id", "green"))
	var tint := str(DictUtil.get_dict(planet, "palette").get("nature", ""))
	var slot := VisualSlot.make("space.planet_" + biome, tint)
	_globe_space = Node3D.new()
	_globe_space.add_child(slot)
	add_child(_globe_space)
	_globe_space.global_position = centre
	_globe_space.scale = Vector3.ONE * (R_PLANET / PlanetDiorama.R)
	PlanetLook.apply(slot, biome, tint, hash(str(planet.get("id", ""))), str(planet.get("id", "")))
	# Below the cloud deck: plain ground to the horizon past the playable terrain
	# and its far ring, in the terrain's colours, so the curve continues under the haze.
	var sm := SphereMesh.new()
	sm.radius = R_PLANET
	sm.height = R_PLANET * 2.0
	sm.radial_segments = 192
	sm.rings = 96
	var mat := StandardMaterial3D.new()
	var ocean := bool(terrain.style.get("ocean", false))
	mat.albedo_color = Color("2c6a80") if ocean else Color(str(terrain.style.get("ground", "#6f7a60"))).darkened(0.12)
	mat.roughness = 0.35 if ocean else 1.0
	mat.metallic_specular = 0.6 if ocean else 0.2
	if ocean and terrain.water_level > -50.0:
		var pm := PlaneMesh.new()
		pm.size = Vector2(16000, 16000)
		_sea = MeshInstance3D.new()
		_sea.mesh = pm
		var wm := ShaderMaterial.new()
		wm.shader = preload("res://art/shaders/water.gdshader")
		wm.set_shader_parameter("foam_strength", 0.0)  # depth-buffer noise at kilometre range reads as white speckle
		_sea.material_override = wm
		add_child(_sea)
		_sea.global_position = Vector3(target.x, terrain.water_level - 0.05, target.z)
		# Two translucent seas 5 cm apart: the site's own plane showed as a dark
		# square in the ocean from the air. One sea until touchdown.
		for c: Node in terrain.get_children():
			var mi := c as MeshInstance3D
			if mi and mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == wm.shader:
				_site_water = mi
				mi.visible = false
				break
	_globe_ground = MeshInstance3D.new()
	_globe_ground.mesh = sm
	_globe_ground.material_override = mat
	_globe_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_globe_ground)
	_globe_ground.global_position = centre


## Forests (or rocks, on bare worlds) over the horizon land, from the planet's
## own ground-cover set: from the air the world reads as wooded, rocky, alive.
func _build_horizon_scatter() -> void:
	var spec := GroundCover.spec_for(str(planet.get("id", "")), str(planet.get("biome_id", "")))
	var d: Dictionary = DictUtil.get_dict(spec, "descent")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(planet.get("id", ""))) + 404
	var ocean := bool(terrain.style.get("ocean", false))
	var kind := str(d.get("canopy", "blob"))
	if kind != "none":
		_build_canopy(rng, d, kind, ocean)
	if bool(d.get("rocks", false)):
		_build_rock_fields(rng, spec, ocean)


## The planet's big landmark rocks scattered in fields over the horizon land.
func _build_rock_fields(rng: RandomNumberGenerator, spec: Dictionary, ocean: bool) -> void:
	var look: Dictionary = DictUtil.get_dict(spec, "look")
	var srcs: Array = []
	for l: Variant in DictUtil.get_arr(spec, "landmarks"):
		if int((l as Dictionary).get("count", 0)) < 8:
			continue
		for pth: Variant in DictUtil.get_arr(l, "meshes"):
			var src := GroundCover.mesh_of(str(pth), look)
			if not src.is_empty():
				srcs.append([src, DictUtil.get_arr(l, "scale")])
	if srcs.is_empty():
		return
	var per := 420 / srcs.size()
	for entry: Array in srcs:
		var src: Array = entry[0]
		var sc: Array = entry[1]
		var xfs: Array = []
		while xfs.size() < per:
			var c := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(560.0, 5000.0)
			for j: int in 5:
				var p := c + Vector2(rng.randf_range(-160, 160), rng.randf_range(-160, 160))
				var hz := _horizon_height(p)
				if ocean and hz < terrain.water_level + 0.5:
					continue
				var s := (rng.randf_range(float(sc[0]), float(sc[1])) if sc.size() == 2 else 1.0) * rng.randf_range(1.0, 2.2) * (1.0 + p.length() / 1800.0)
				var box: AABB = src[2]
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, hz - box.position.y * s - box.size.y * s * 0.15, p.y)) * (src[1] as Transform3D))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src[0]
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_horizon_bits.append(mmi)
		terrain.add_child(mmi)


## Trees and big plants of the site stay drawn from the air (they normally cull
## at walking distance); restored at touchdown.
func _stretch_cover(on: bool) -> void:
	var gc := surface_root.get_node_or_null("GroundCover")
	if gc == null:
		return
	for n: Node in gc.get_children():
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		if mmi.multimesh.mesh.get_aabb().size.length() < 3.0:
			continue  # pebbles and tufts stay culled: from the air they only speckle the playable square
		if on:
			mmi.set_meta("vis_end", mmi.visibility_range_end)
			mmi.visibility_range_end = 2500.0 if mmi.visibility_range_end > 0.0 else 0.0
		elif mmi.has_meta("vis_end"):
			mmi.visibility_range_end = float(mmi.get_meta("vis_end"))


## Distant forest as low-poly canopy blobs (a few dozen triangles each, one
## draw call): dense woods to the horizon at a fraction of the cost of trees.
func _build_canopy(rng: RandomNumberGenerator, d: Dictionary, kind: String, ocean: bool) -> void:
	var leaf := Color(str(d.get("color", "#2f5a22")))
	var blob: PrimitiveMesh
	if kind == "cone":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.55
		cone.height = 2.6
		cone.radial_segments = 6
		cone.rings = 1
		blob = cone
	else:
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 1.5
		sph.radial_segments = 7
		sph.rings = 4
		blob = sph
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	blob.material = mat
	var xfs: Array = []
	var cols: Array = []
	var clumps := int(900 * DictUtil.get_float(d, "density", 1.0))
	for k: int in clumps:
		var c := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(480.0, 5200.0)
		var spread := rng.randf_range(60.0, 220.0)
		var shade := rng.randf_range(-0.18, 0.12)
		for j: int in 22:
			var p := c + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
			if absf(p.x) < terrain.size_m * 0.5 + 20.0 and absf(p.y) < terrain.size_m * 0.5 + 20.0:
				continue
			var hz := _horizon_height(p)
			if ocean and hz < terrain.water_level + 0.5:
				continue
			var r := rng.randf_range(5.0, 11.0) * (1.0 + p.length() / 6000.0)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * rng.randf_range(0.8, 1.3), r)), Vector3(p.x, hz + r * 0.55, p.y)))
			cols.append(leaf.lightened(shade + rng.randf_range(-0.06, 0.06)) if shade > 0.0 else leaf.darkened(-shade + rng.randf_range(0.0, 0.06)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blob
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_horizon_bits.append(mmi)
	terrain.add_child(mmi)


## Height of the horizon land at p (same field as TerrainBuilder.build_horizon).
func _horizon_height(p: Vector2) -> float:
	var h := terrain.height_at(p.x, p.y)
	var dist := maxf(absf(p.x), absf(p.y))
	h += smoothstep(terrain.size_m * 0.5, 460.0, dist) * terrain.height_scale * 2.5 * (0.6 + 0.4 * terrain.detail.get_noise_2d(p.x * 0.05, p.y * 0.05))
	if dist > 460.0:
		h += terrain.noise.get_noise_2d(p.x * 0.004, p.y * 0.004) * terrain.height_scale * 6.0 * smoothstep(460.0, 1400.0, dist)
	if bool(terrain.style.get("ocean", false)):
		var isle := maxf(0.0, terrain.detail.get_noise_2d(p.x * 0.012 + 40.0, p.y * 0.012) - 0.18) * terrain.height_scale * 9.0
		h = lerpf(h, terrain.water_level - 5.0 + isle, terrain.ocean_shore(p, dist))
	return h - maxf(0.0, p.length_squared() - 211600.0) / (2.0 * R_PLANET)


## The Ark hangs in orbit where the lander has just undocked: seen in the first
## seconds of the descent, falling away behind.
func _build_mothership() -> void:
	var ark := VisualSlot.make("space.ark_exterior")
	_mothership = ark
	add_child(ark)
	ark.visible = true


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(planet.get("id", ""))) + 91
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	var cover := DictUtil.get_float(DictUtil.get_dict(planet, "descent"), "clouds", 1.0)
	mm.instance_count = int(340 * cover)
	for i: int in mm.instance_count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 7500.0
		var y := target.y + rng.randf_range(CLOUD_ALT.x, CLOUD_ALT.y) - r * r / (2.0 * (R_PLANET + CLOUD_ALT.x))  # the deck follows the globe's curve
		var s := rng.randf_range(260.0, 620.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(target.x + cos(a) * r, y, target.z + sin(a) * r)))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/cloud_puff.gdshader")
	mat.set_shader_parameter("lit", _sky_tint.lightened(0.55))
	mat.set_shader_parameter("shade", _sky_tint.darkened(0.25))
	_clouds = MultiMeshInstance3D.new()
	_clouds.multimesh = mm
	_clouds.material_override = mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.custom_aabb = AABB(Vector3(-8000, -200, -8000), Vector3(16000, 2400, 16000))
	add_child(_clouds)


func _build_ship_fx() -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	_plasma_mat = ShaderMaterial.new()
	_plasma_mat.shader = preload("res://art/shaders/reentry_plasma.gdshader")
	_plasma = MeshInstance3D.new()
	_plasma.mesh = sm
	_plasma.material_override = _plasma_mat
	_plasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plasma)
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color("ff7a2e")
	_glow_light.omni_range = 18.0
	_glow_light.light_energy = 0.0
	add_child(_glow_light)
	# Streaks of burning air: a cylinder of thin quads around the flight path.
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 1.0)
	q.orientation = PlaneMesh.FACE_Y
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = preload("res://art/shaders/entry_streak.gdshader")
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = q
	smm.instance_count = 140
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in smm.instance_count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.5, 14.0)
		_streak_pts.append([Vector3(cos(a) * r, sin(a) * r * 0.8, rng.randf_range(-60.0, 30.0)), rng.randf_range(4.0, 14.0)])
	_streaks = MultiMeshInstance3D.new()
	_streaks.multimesh = smm
	_streaks.material_override = _streak_mat
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streaks.custom_aabb = AABB(Vector3(-40, -40, -90), Vector3(80, 80, 140))
	add_child(_streaks)
	_thruster = VisualSlot.make("fx.thruster")
	add_child(_thruster)
	_marker = Label3D.new()
	_marker.text = "◆"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = false  # the chase-cam lander sits right in front of the pad: its hull hides the marker, not the other way round
	_marker.fixed_size = true
	_marker.pixel_size = 0.0016
	_marker.font_size = 48
	_marker.modulate = UiKit.AMBER
	_marker.outline_size = 10
	_marker.outline_modulate = Color(0.02, 0.05, 0.06, 0.85)
	add_child(_marker)
	_marker.global_position = target + Vector3.UP * 6.0


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 20
	add_child(_hud)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = preload("res://art/shaders/heat_vignette.gdshader")
	_vignette.material = vm
	_hud.add_child(_vignette)
	_white = ColorRect.new()
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.color = Color(_sky_tint.lightened(0.6), 0.0)
	_hud.add_child(_white)
	_gauge = DescentHud.new()
	_gauge.switch_alt = SWITCH_ALT
	_hud.add_child(_gauge)
	# Readout in a framed strip at the top centre (the game's panel style).
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	frame.position = Vector2(-300, 18)
	frame.custom_minimum_size = Vector2(600, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiKit.PANEL, 0.62)
	sb.border_color = Color(UiKit.PETROL, 0.8)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(frame)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(box)
	_lbl_phase = UiKit.label("", 26, UiKit.AMBER)
	_lbl_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_phase.add_theme_constant_override("outline_size", 8)
	_lbl_phase.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	box.add_child(_lbl_phase)
	_lbl_data = UiKit.label("", 17)
	_lbl_data.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_data.add_theme_constant_override("outline_size", 6)
	_lbl_data.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	box.add_child(_lbl_data)
	_lbl_hint = UiKit.label("", 15, Color(0.85, 0.92, 0.95))
	_lbl_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lbl_hint.position = Vector2(-420, -64)
	_lbl_hint.custom_minimum_size = Vector2(840, 0)
	_lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_hint.add_theme_constant_override("outline_size", 6)
	_lbl_hint.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_hud.add_child(_lbl_hint)


func _phase_for(alt: float) -> String:
	if alt > 1900.0:
		return "space"
	if alt > 900.0:
		return "entry"
	return "atmos"


var _in_space := true


## Space sky + orbital globe above the switch altitude; the planet's own sky,
## the real site and the ground globe below it (the swap happens in the whiteout).
func _set_sky(in_space: bool) -> void:
	_in_space = in_space
	if _world_env:
		_world_env.environment = _space_env if in_space else _planet_env
	_globe_space.visible = in_space
	if _mothership:
		_mothership.visible = in_space
	_globe_ground.visible = not in_space
	if _sea:
		_sea.visible = not in_space
	if in_space:
		_hide_surface()
	else:
		_show_surface()
		AudioService.set_ambience_any(["amb_surface_" + str(planet.get("biome_id")), "amb_colony_wind"])


func _process(delta: float) -> void:
	if _done or lander_body == null:
		return
	_t += delta
	if Input.is_action_just_pressed("skip_line"):
		_skip()
		return
	if Input.is_action_just_pressed("autopilot") and not _landing:
		autopilot = not autopilot
		AudioService.play("ui_click", "UI", -6.0)
	var pos := lander_body.global_position
	var ground := _ground_y(pos)
	_alt = pos.y - ground
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var hdist := to.length()
	if _ascent:
		_ascend(delta, pos)
	elif not _landing:
		if hdist < ASSIST_RANGE * sqrt(scale_k) and _alt < ASSIST_ALT * sqrt(scale_k):
			_begin_landing()
		else:
			_fly(delta, pos, to, hdist)
	pos = lander_body.global_position
	_alt = pos.y - _ground_y(pos)
	_phase = _phase_for(_alt)
	if (_alt > SWITCH_ALT) != _in_space:
		_set_sky(_alt > SWITCH_ALT)
	if not _in_space:
		_fog_for_alt(_alt)
	_update_fx(delta, pos)
	_update_camera(delta, pos)
	if _ark_pending:
		# Just undocked: the Ark hangs in orbit high in the frame, the lander dives away from it.
		_ark_pending = false
		var cb := _cam.global_basis
		_mothership.scale = Vector3.ONE * 7.0
		_mothership.global_position = _cam.global_position - cb.z * 1150.0 + cb.x * 360.0 + cb.y * 300.0
		_mothership.look_at(_mothership.global_position + cb.x, Vector3.UP)
	_follow_sky()
	_update_hud(hdist)


func _follow_sky() -> void:
	var off := Vector3(_cam_pos.x, maxf(0.0, _cam_pos.y - target.y), _cam_pos.z)
	for e: Array in _sky_far:
		if is_instance_valid(e[0]):
			(e[0] as Node3D).position = (e[1] as Vector3) + off


func _ground_y(p: Vector3) -> float:
	var half := terrain.size_m * 0.49
	if absf(p.x) < half and absf(p.z) < half:
		return terrain.height_at(p.x, p.z)
	var d := Vector2(p.x - target.x, p.z - target.z).length()
	return target.y - 14.0 - d * d / (2.0 * R_PLANET)  # the globe's curve beyond the map


func _fly(delta: float, pos: Vector3, to: Vector3, hdist: float) -> void:
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_left", "move_right")
	var climb := Input.get_axis("descend", "ascend")
	if throttle != 0.0 or steer != 0.0 or climb != 0.0:
		_manual_hold = 2.5
	_manual_hold = maxf(0.0, _manual_hold - delta)
	var hv := Vector3(_vel.x, 0.0, _vel.z)
	var heading := hv.normalized() if hv.length() > 1.0 else to.normalized()
	# Cruise speed falls with altitude: orbital pace up high, a slow hover near the ground.
	var cruise := lerpf(50.0, 330.0, smoothstep(120.0, 4200.0, _alt)) * (1.6 if Input.is_action_pressed("sprint") else 1.0)
	var want_h: Vector3
	var want_vy: float
	if autopilot and _manual_hold <= 0.0:
		# Glide path: arrive over the pad at hover height; turn gently toward it.
		var tdir := to.normalized()
		heading = heading.slerp(tdir, clampf(delta * 0.9, 0.0, 1.0)) if heading.dot(tdir) > -0.95 else tdir
		var hs := minf(cruise, maxf(hdist * 0.35, 40.0))
		want_h = heading * hs
		var tgo := maxf(hdist / maxf(hs, 1.0), 3.0)
		want_vy = clampf(-(_alt - HOVER_ALT * 3.0) / tgo, -260.0, 30.0)
	else:
		# Manual: yaw with steer, throttle scales speed, climb/dive directly.
		heading = heading.rotated(Vector3.UP, -steer * 0.9 * delta)
		want_h = heading * cruise * (1.0 + throttle * 0.6)
		var glide := -clampf(_alt * 0.06, 8.0, 200.0)  # still sinking slowly: the lander is coming down
		want_vy = glide + climb * clampf(_alt * 0.12, 25.0, 260.0)
	var want := want_h + Vector3.UP * want_vy
	var prev := _vel
	_vel = _vel.lerp(want, clampf(delta * 1.2, 0.0, 1.0))
	var np := pos + _vel * delta
	var floor_y := _ground_y(np) + 18.0 * scale_k
	if np.y < floor_y:  # never into the ground before the pad
		np.y = lerpf(np.y, floor_y, 0.5)
		_vel.y = maxf(_vel.y, 0.0)
	lander_body.global_position = np
	# Face the flight path, nose dipping on the way down, bank into turns.
	var lat := (_vel - prev).dot(heading.cross(Vector3.UP)) / maxf(delta, 0.001)
	_bank = lerpf(_bank, clampf(lat * 0.004, -0.6, 0.6), clampf(delta * 2.0, 0.0, 1.0))
	var fwd := _vel.normalized() if _vel.length() > 1.0 else heading
	fwd.y = clampf(fwd.y, -0.55, 0.3)
	var b := Basis.looking_at(fwd.normalized(), Vector3.UP)
	lander_body.global_basis = b * Basis(Vector3.FORWARD, _bank) * Basis(Vector3.UP, nose_yaw)


func _ascend(delta: float, pos: Vector3) -> void:
	_asc_t += delta
	var np := pos
	if _asc_t < 2.6:
		# Lift-off: straight up on the thrusters, nose levelling out.
		var k := smoothstep(0.0, 2.6, _asc_t)
		np = Vector3(target.x, target.y + k * k * 22.0 * scale_k, target.z)
		_vel = Vector3.UP * 12.0 * scale_k + _climb_dir * 2.0
		lander_body.global_position = np
		lander_body.global_basis = _rest_basis.slerp(Basis.looking_at(_climb_dir, Vector3.UP) * Basis(Vector3.UP, nose_yaw), k * 0.6)
		return
	var speed := lerpf(40.0, 640.0, smoothstep(2.6, 15.0, _asc_t))
	var pitch := lerpf(0.18, 0.62, smoothstep(2.6, 9.0, _asc_t))  # climb steepens
	var want := (_climb_dir * cos(pitch) + Vector3.UP * sin(pitch)).normalized() * speed
	_vel = _vel.lerp(want, clampf(delta * 1.5, 0.0, 1.0))
	np = pos + _vel * delta
	lander_body.global_position = np
	var fwd := _vel.normalized()
	lander_body.global_basis = Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.UP, nose_yaw)
	if np.y - target.y > 3800.0 or _asc_t > 22.0:
		_done = true
		finished.emit()


func _begin_landing() -> void:
	_landing = true
	autopilot = true
	var pos := lander_body.global_position
	var hover := target + Vector3.UP * HOVER_ALT * scale_k
	var dur1 := clampf(pos.distance_to(hover) / 45.0, 2.0, 6.0)
	var rest := _rest_basis
	var t := create_tween().set_parallel(false)
	t.tween_property(lander_body, "global_position", hover, dur1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_method(func(k: float) -> void: lander_body.global_basis = lander_body.global_basis.slerp(rest, k * 0.25), 0.0, 1.0, dur1)
	t.tween_property(lander_body, "global_position", target, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lander_body, "global_basis", rest, 2.0)
	t.tween_callback(_touchdown)


func _touchdown() -> void:
	var lander := lander_body.get_parent() as Node3D
	var dust := VisualSlot.make("fx.landing_dust")
	if lander:
		lander.add_child(dust)
	get_tree().create_timer(4.0).timeout.connect(dust.queue_free)
	AudioService.play("sfx_landing", "SFX", -6.0)
	_shake = 0.3 if _shake_ok() else 0.0
	get_tree().create_timer(0.7).timeout.connect(_finish)


func _skip() -> void:
	if _ascent:
		_done = true
		finished.emit()
		return
	_landing = true
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_alt = 0.0
	_show_surface()
	if _world_env:
		_world_env.environment = _planet_env
	_restore_fog()
	AudioService.set_layer("", -2.0)
	_stretch_cover(false)
	if is_instance_valid(_site_water):
		_site_water.visible = true
	for e: Array in _sky_far:
		if is_instance_valid(e[0]):
			(e[0] as Node3D).position = e[1]
	if is_instance_valid(_horizon):
		_horizon.queue_free()
	for b: Node3D in _horizon_bits:
		if is_instance_valid(b):
			b.queue_free()
	lander_body.top_level = false
	lander_body.transform = _body_rest
	_cam.current = false
	for l: CanvasLayer in _layers:
		if is_instance_valid(l):
			l.visible = true
	finished.emit()
	queue_free()


func _shake_ok() -> bool:
	return bool(SettingsService.get_value("camera_shake", true)) and not FxEffect.reduced_motion()


func _update_fx(delta: float, pos: Vector3) -> void:
	var speed := _vel.length()
	# Entry heat: strongest through the upper atmosphere at speed.
	var heat := smoothstep(2600.0, 1700.0, _alt) * smoothstep(650.0, 1150.0, _alt) * clampf(speed / 380.0, 0.0, 1.2)
	if _landing:
		heat = 0.0
	if _ascent:
		heat *= 0.45  # climbing out: a glow, not a burn
		_plasma.visible = false
	_plasma_mat.set_shader_parameter("heat", heat)
	var fwd := _vel.normalized() if speed > 1.0 else -lander_body.global_basis.z
	_plasma.global_position = pos + fwd * 2.5 * scale_k
	_plasma.global_basis = Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.98 else Vector3.FORWARD).scaled(Vector3(4.2, 3.4, 8.5) * scale_k)
	_plasma.visible = heat > 0.01 and not _ascent
	_streak_mat.set_shader_parameter("heat", heat)
	(_vignette.material as ShaderMaterial).set_shader_parameter("heat", heat)
	_streaks.visible = heat > 0.02
	if _streaks.visible:
		var sb := Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.98 else Vector3.FORWARD)
		_streaks.global_transform = Transform3D(sb.scaled(Vector3.ONE * scale_k), pos)
		var flow := speed * 0.35 * delta
		for i: int in _streak_pts.size():
			var sp: Array = _streak_pts[i]
			var o: Vector3 = sp[0]
			o.z += flow  # local +Z is backwards (looking_at faces -Z)
			if o.z > 30.0:
				o.z -= 90.0
			sp[0] = o
			var ln: float = sp[1]
			# Quad lies in local XZ (FACE_Y), stretched along Z; roll it to face the axis.
			var roll := Basis(Vector3.BACK, atan2(o.y, o.x) + PI * 0.5)
			_streaks.multimesh.set_instance_transform(i, Transform3D(roll * Basis().scaled(Vector3(1.0, 1.0, ln)), o))
	_glow_light.global_position = pos + fwd * 4.0
	_glow_light.light_energy = heat * 6.0
	_thruster.global_position = pos + Vector3.DOWN * 1.2
	_thruster.global_basis = Basis(Vector3.RIGHT, PI * 0.5)  # plume down at the ground
	_thruster.visible = _alt < 600.0 or _landing or _ascent
	# Entry roar: the storm bed swells with the heat and dies away below the deck.
	var roaring := heat > 0.15 or (_alt < SWITCH_ALT + 150.0 and _alt > SWITCH_ALT - 250.0)
	if roaring != _roar:
		_roar = roaring
		AudioService.set_layer("amb_hazard_storm" if roaring else "", -2.0)
	if heat > 0.25 and _shake_ok():
		_shake = maxf(_shake, heat * 0.22)
	_shake = maxf(0.0, _shake - delta * 0.8)
	# Cloud whiteout hides the sky change; peaks right at the switch altitude.
	var w := 1.0 - smoothstep(0.0, 220.0, absf(_alt - SWITCH_ALT))
	_white.color.a = w * 0.88 if not _landing else 0.0
	_marker.visible = _alt > 60.0 and not _ascent
	(_clouds.material_override as ShaderMaterial).set_shader_parameter("presence", 1.0 - smoothstep(1900.0, 2700.0, _alt))


func _update_camera(delta: float, pos: Vector3) -> void:
	var speed := _vel.length()
	var back := (_vel.normalized() if speed > 2.0 else -lander_body.global_basis.z)
	back.y = clampf(back.y, -0.5, 0.2)
	back = back.normalized()
	var dist := lerpf(10.0, 17.0, clampf(speed / 350.0, 0.0, 1.0)) * scale_k
	var want := pos - back * dist + Vector3.UP * lerpf(3.2, 5.0, clampf(speed / 350.0, 0.0, 1.0)) * scale_k
	if _ascent and _alt > 700.0:
		# Out of the clouds: the camera swings ahead and looks back down past the
		# ship at the world falling away.
		var k := smoothstep(700.0, 1600.0, _alt)
		want = want.lerp(pos + back * 22.0 * scale_k + Vector3.UP * 9.0 * scale_k + back.cross(Vector3.UP) * 10.0 * scale_k, k)
	if _landing:
		want = pos + (Vector3(_cam_pos.x - pos.x, 0, _cam_pos.z - pos.z).normalized() * 22.0 * scale_k) + Vector3.UP * 9.0 * scale_k
	# Smooth the camera's offset from the ship, not its world position: at
	# orbital speed a world-space lag would leave the ship a dot far ahead.
	_cam_off = _cam_off.lerp(want - pos, clampf(delta * 3.0, 0.0, 1.0))
	_cam_pos = pos + _cam_off
	var floor_y := _ground_y(_cam_pos) + 3.0
	_cam_pos.y = maxf(_cam_pos.y, floor_y)
	var look := pos + back * 40.0 + Vector3.DOWN * 6.0
	if _ascent and _alt > 700.0:
		look = look.lerp(pos - back * 60.0 + Vector3.DOWN * 40.0, smoothstep(700.0, 1600.0, _alt))
	if _landing:
		look = pos
	_cam.global_position = _cam_pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if _cam.global_position.distance_to(look) > 0.1:
		_cam.look_at(look, Vector3.UP)
	_cam.fov = lerpf(_cam.fov, lerpf(62.0, 78.0, clampf(speed / 520.0, 0.0, 1.0)), clampf(delta * 2.0, 0.0, 1.0))


func _update_hud(hdist: float) -> void:
	_gauge.alt = _alt
	var site := target + Vector3.UP * 6.0
	var behind := _cam.is_position_behind(site)
	var px := _cam.unproject_position(site)
	var vr := get_viewport().get_visible_rect().size
	# Climbing out there is no site to point at.
	_gauge.site_on_screen = _ascent or (not behind and px.x > 30.0 and px.y > 30.0 and px.x < vr.x - 30.0 and px.y < vr.y - 30.0)
	_gauge.site_px = (vr - px) if behind else px  # behind the camera: point the other way
	_gauge.site_text = Loc.t("SITE %s") % _fmt_m(hdist)
	_gauge.visible = not _landing
	_gauge.queue_redraw()
	var names := {"space": Loc.t("LOW ORBIT"), "entry": Loc.t("ATMOSPHERIC ENTRY"), "atmos": Loc.t("DESCENT")}
	_lbl_phase.text = Loc.t("TOUCHDOWN") if _landing else (Loc.t("LIFT-OFF") if _ascent and _alt < 120.0 else (Loc.t("CLIMB TO ORBIT") if _ascent else str(names.get(_phase, ""))))
	_lbl_data.text = Loc.t("ALT %s · SPEED %d m/s · SITE %s · %s") % [_fmt_m(_alt), int(_vel.length()), _fmt_m(hdist),
		Loc.t("LANDING ASSIST") if _landing else (Loc.t("AUTOPILOT") if autopilot and _manual_hold <= 0.0 else Loc.t("MANUAL"))]
	_lbl_hint.text = Loc.t("[%s] autopilot / manual · [%s][%s] speed · [%s][%s] steer · [%s][%s] climb/dive · [%s] skip descent") % [
		SettingsService.binding_text("autopilot"), SettingsService.binding_text("move_forward"), SettingsService.binding_text("move_back"),
		SettingsService.binding_text("move_left"), SettingsService.binding_text("move_right"), SettingsService.binding_text("ascend"),
		SettingsService.binding_text("descend"), SettingsService.binding_text("skip_line")]
	_lbl_hint.visible = not _landing and not _ascent


func _fmt_m(m: float) -> String:
	return ("%.1f km" % (m / 1000.0)) if m >= 1000.0 else ("%d m" % int(maxf(m, 0.0)))
