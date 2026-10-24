extends SceneTree
## Builds the particle library art/fx/*.tscn for the fx.* VisualSlots.
##   godot --headless --path . --script res://tools/fx/build_fx_scenes.gd [-- --force] [--only=spores]
## The saved scenes are the source of truth afterwards (tweak them in the editor,
## drop Synty Particle FX textures in, see docs/SYNTY_INTEGRATION.md). Existing
## scenes are only overwritten with --force.
## Textures are procedural (GradientTexture2D), so the repo holds no image files.
## Everything stays Compatibility-safe: no collision, no trails, no turbulence.

const FX_SCRIPT := preload("res://scripts/runtime/visual/fx/fx_effect.gd")
const RING_SCRIPT := preload("res://scripts/runtime/visual/fx/fx_scan_ring.gd")
const OUT := "res://art/fx/"

var _force := false
var _only := ""


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--force":
			_force = true
		elif a.begins_with("--only="):
			_only = a.trim_prefix("--only=")
	var builders := {
		"spores": _spores, "dust": _dust, "snow": _snow, "storm": _storm, "steam_vent": _steam_vent,
		"smoke_plume": _smoke_plume, "smoke_toxic": _smoke_toxic,
		"thruster": _thruster, "construction_sparks": _construction_sparks, "power_surge": _power_surge,
		"scan_pulse": _scan_pulse, "landing_dust": _landing_dust,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var failed := 0
	for key: String in builders.keys():
		if not _only.is_empty() and key != _only:
			continue
		var path := OUT + key + ".tscn"
		if FileAccess.file_exists(path) and not _force:
			print("FX skip %s (exists; use --force)" % path)
			continue
		var root: Node3D = (builders[key] as Callable).call()
		_own(root, root)
		var ps := PackedScene.new()
		var err := ps.pack(root)
		if err == OK:
			err = ResourceSaver.save(ps, path)
		print("FX %s %s" % ["wrote" if err == OK else "FAILED", path])
		failed += 1 if err != OK else 0
		root.free()
	quit(1 if failed > 0 else 0)


func _own(n: Node, root: Node) -> void:
	for c: Node in n.get_children():
		c.owner = root
		_own(c, root)


# ------------------------------------------------------------------ building blocks

func _root(slot: String, mode: int = 0) -> Node3D:
	var r := Node3D.new()
	r.name = "fx_" + slot
	r.set_script(FX_SCRIPT)
	r.set("mode", mode)
	return r


## Soft round sprite. `stops` = [offset, alpha] pairs from centre (0) to edge (1).
func _dot(stops: Array, size: int = 64) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(Color(1, 1, 1, float(s[1])))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


func _soft() -> GradientTexture2D:
	return _dot([[0.0, 1.0], [0.35, 0.75], [0.75, 0.2], [1.0, 0.0]])


func _glow() -> GradientTexture2D:
	return _dot([[0.0, 1.0], [0.18, 0.9], [0.45, 0.3], [1.0, 0.0]])


func _puff() -> GradientTexture2D:
	return _dot([[0.0, 0.85], [0.4, 0.6], [0.8, 0.12], [1.0, 0.0]], 128)


## Colour over lifetime (alpha fade). `stops` = [offset, Color].
func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1] as Color)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t


## Size over lifetime. `pts` = [x, y] with y in 0..max.
func _curve(pts: Array, max_value: float = 1.0) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_value
	for p: Array in pts:
		c.add_point(Vector2(float(p[0]), float(p[1])))
	var t := CurveTexture.new()
	t.curve = c
	t.width = 64
	return t


## Particle sprite material: unshaded, vertex colour (the ramp) as albedo.
func _mat(tex: Texture2D, additive: bool, billboard: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	return m


func _quad(size: Vector2, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	return q


func _emitter(name: String, amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh, aabb: AABB) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.name = name
	gp.amount = amount
	gp.lifetime = lifetime
	gp.process_material = pm
	gp.draw_pass_1 = mesh
	gp.local_coords = true
	gp.visibility_aabb = aabb
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return gp


## Continuous emitter that is already "full" when the scene appears.
func _loop(gp: GPUParticles3D) -> GPUParticles3D:
	gp.preprocess = gp.lifetime
	gp.emitting = true
	return gp


func _shot(gp: GPUParticles3D, explosiveness: float) -> GPUParticles3D:
	gp.one_shot = true
	gp.explosiveness = explosiveness
	gp.emitting = false
	return gp


func _pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	return pm


func _box(pm: ParticleProcessMaterial, extents: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.emission_shape_offset = offset


func _sphere(pm: ParticleProcessMaterial, r: float, offset: Vector3 = Vector3.ZERO) -> void:
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r
	pm.emission_shape_offset = offset


func _flash(color: Color, energy: float, rng: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "Flash"
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	l.shadow_enabled = false
	return l


const ZONE_AABB := AABB(Vector3(-9, -1, -9), Vector3(18, 11, 18))


# ------------------------------------------------------------------ hazard zones

## Green hazard: slow glowing motes, some rising, over a faint haze. ~12 m wide.
func _spores() -> Node3D:
	var r := _root("spores")
	var pm := _pm()
	_box(pm, Vector3(6, 1.6, 6), Vector3(0, 1.8, 0))
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0.04, 0.09, 0)
	pm.damping_min = 0.02
	pm.damping_max = 0.06
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.scale_curve = _curve([[0.0, 0.3], [0.2, 1.0], [0.8, 0.9], [1.0, 0.2]])
	pm.color_ramp = _ramp([[0.0, Color(1, 0.96, 0.55, 0)], [0.15, Color(1, 0.95, 0.5, 1)], [0.5, Color(0.97, 0.9, 0.38, 0.7)],
		[0.7, Color(1, 0.96, 0.55, 0.95)], [1.0, Color(0.9, 0.88, 0.35, 0)]])
	pm.hue_variation_min = -0.03
	pm.hue_variation_max = 0.04
	r.add_child(_loop(_emitter("Motes", 170, 7.0, pm, _quad(Vector2(0.24, 0.24), _mat(_glow(), false)), ZONE_AABB)))
	var hz := _pm()
	_box(hz, Vector3(5, 0.8, 5), Vector3(0, 1.4, 0))
	hz.direction = Vector3(1, 0.2, 0)
	hz.spread = 180.0
	hz.flatness = 0.8
	hz.initial_velocity_min = 0.1
	hz.initial_velocity_max = 0.3
	hz.scale_min = 0.7
	hz.scale_max = 1.3
	hz.scale_curve = _curve([[0.0, 0.6], [1.0, 1.0]])
	hz.color_ramp = _ramp([[0.0, Color(0.9, 0.86, 0.35, 0)], [0.4, Color(0.88, 0.84, 0.35, 0.16)], [1.0, Color(0.8, 0.8, 0.35, 0)]])
	r.add_child(_loop(_emitter("Haze", 16, 9.0, hz, _quad(Vector2(4, 4), _mat(_puff(), false)), ZONE_AABB)))
	return r


## Desert heat/dust: soft sheets and grit blown sideways (+X), low over the ground.
func _dust() -> Node3D:
	var r := _root("dust")
	var pm := _pm()
	_box(pm, Vector3(3, 0.3, 6), Vector3(-3, 1.6, 0))
	pm.direction = Vector3(1, 0.05, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.0
	pm.angle_min = -6.0
	pm.angle_max = 6.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.scale_curve = _curve([[0.0, 0.5], [1.0, 1.0]])
	pm.color_ramp = _ramp([[0.0, Color(0.74, 0.55, 0.37, 0)], [0.3, Color(0.7, 0.5, 0.33, 0.55)], [0.7, Color(0.68, 0.49, 0.32, 0.42)],
		[1.0, Color(0.7, 0.52, 0.35, 0)]])
	r.add_child(_loop(_emitter("Sheets", 56, 6.0, pm, _quad(Vector2(4.2, 2.0), _mat(_puff(), false)), ZONE_AABB)))
	var gr := _pm()
	_box(gr, Vector3(6, 0.9, 6), Vector3(-1, 0.8, 0))
	gr.direction = Vector3(1, 0.08, 0)
	gr.spread = 6.0
	gr.initial_velocity_min = 4.0
	gr.initial_velocity_max = 6.5
	gr.gravity = Vector3(0, -0.4, 0)
	gr.scale_min = 0.6
	gr.scale_max = 1.2
	gr.color_ramp = _ramp([[0.0, Color(0.45, 0.33, 0.22, 0)], [0.15, Color(0.48, 0.36, 0.24, 0.9)], [0.8, Color(0.48, 0.36, 0.24, 0.75)],
		[1.0, Color(0.45, 0.33, 0.22, 0)]])
	r.add_child(_loop(_emitter("Grit", 110, 2.0, gr, _quad(Vector2(0.09, 0.09), _mat(_soft(), false)), ZONE_AABB)))
	return r


## Cold zone / long night: snow falling with a light wind.
func _snow() -> Node3D:
	var r := _root("snow")
	var pm := _pm()
	_box(pm, Vector3(6, 0.4, 6), Vector3(-1, 7.5, 0))
	pm.direction = Vector3(0.25, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.12, -0.18, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = _ramp([[0.0, Color(0.8, 0.87, 0.96, 0)], [0.08, Color(0.72, 0.8, 0.92, 1)], [0.85, Color(0.76, 0.84, 0.95, 0.9)],
		[1.0, Color(0.84, 0.9, 0.98, 0)]])
	r.add_child(_loop(_emitter("Flakes", 280, 6.5, pm, _quad(Vector2(0.18, 0.18), _mat(_soft(), false)), ZONE_AABB)))
	var dr := _pm()
	_box(dr, Vector3(5, 0.4, 5), Vector3(-2, 0.5, 0))
	dr.direction = Vector3(1, 0.1, 0)
	dr.spread = 15.0
	dr.initial_velocity_min = 1.0
	dr.initial_velocity_max = 1.8
	dr.scale_min = 0.8
	dr.scale_max = 1.2
	dr.scale_curve = _curve([[0.0, 0.5], [1.0, 1.0]])
	dr.color_ramp = _ramp([[0.0, Color(0.78, 0.86, 0.95, 0)], [0.4, Color(0.8, 0.88, 0.97, 0.22)], [1.0, Color(0.8, 0.88, 0.97, 0)]])
	r.add_child(_loop(_emitter("Drift", 14, 5.0, dr, _quad(Vector2(3.0, 1.2), _mat(_puff(), false)), ZONE_AABB)))
	return r


## Pelagos storm belt: slanted rain streaks plus grey gusts.
func _storm() -> Node3D:
	var r := _root("storm")
	var pm := _pm()
	_box(pm, Vector3(7, 0.5, 7), Vector3(-2.5, 9.0, 0))
	pm.direction = Vector3(0.3, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 14.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([[0.0, Color(0.6, 0.68, 0.82, 0)], [0.1, Color(0.6, 0.68, 0.82, 0.75)], [0.9, Color(0.58, 0.66, 0.8, 0.7)],
		[1.0, Color(0.6, 0.68, 0.82, 0)]])
	var rain := _loop(_emitter("Rain", 300, 0.8, pm, _quad(Vector2(0.07, 1.3), _mat(_dot([[0.0, 1.0], [0.6, 0.5], [1.0, 0.0]], 32), false, false)), ZONE_AABB))
	rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	r.add_child(rain)
	var gu := _pm()
	_box(gu, Vector3(2, 1.5, 6), Vector3(-5, 2.5, 0))
	gu.direction = Vector3(1, 0.05, 0)
	gu.spread = 8.0
	gu.initial_velocity_min = 4.5
	gu.initial_velocity_max = 6.5
	gu.scale_min = 0.8
	gu.scale_max = 1.3
	gu.scale_curve = _curve([[0.0, 0.6], [1.0, 1.0]])
	gu.color_ramp = _ramp([[0.0, Color(0.55, 0.6, 0.72, 0)], [0.35, Color(0.56, 0.62, 0.74, 0.3)], [1.0, Color(0.55, 0.6, 0.72, 0)]])
	r.add_child(_loop(_emitter("Gusts", 14, 2.4, gu, _quad(Vector2(5.0, 2.2), _mat(_puff(), false)), ZONE_AABB)))
	return r


## Geothermal vent: rising, expanding, fading steam column with a slight drift.
func _steam_vent() -> Node3D:
	var r := _root("steam_vent")
	var pm := _pm()
	_sphere(pm, 0.35, Vector3(0, 0.2, 0))
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 2.8
	pm.damping_min = 0.25
	pm.damping_max = 0.4
	pm.gravity = Vector3(0.25, 0.15, 0)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	pm.scale_min = 0.7
	pm.scale_max = 1.0
	pm.scale_curve = _curve([[0.0, 0.25], [0.4, 0.65], [1.0, 1.0]])
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.08, Color(0.95, 0.97, 0.98, 0.5)], [0.5, Color(0.9, 0.93, 0.95, 0.28)],
		[1.0, Color(0.88, 0.9, 0.92, 0)]])
	r.add_child(_loop(_emitter("Steam", 60, 4.0, pm, _quad(Vector2(3.2, 3.2), _mat(_puff(), false)), AABB(Vector3(-4, -1, -4), Vector3(10, 14, 8)))))
	return r


## Industry chimney: a tall, slowly leaning column of dark smoke (scavenger
## worlds, key art #7). Lit material so it darkens at dusk instead of glowing.
func _smoke_plume() -> Node3D:
	var r := _root("smoke_plume")
	var m := _mat(_puff(), false)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 1.0
	r.add_child(_loop(_emitter("Smoke", 48, 7.0, _chimney_pm([[0.0, Color(0.22, 0.2, 0.19, 0)], [0.07, Color(0.24, 0.22, 0.2, 0.5)],
		[0.45, Color(0.36, 0.34, 0.32, 0.3)], [1.0, Color(0.5, 0.48, 0.46, 0)]]), _quad(Vector2(5.5, 5.5), m), AABB(Vector3(-8, -1, -8), Vector3(26, 30, 18)))))
	return r


## Refinery stack: the same column in a sickly yellow-green (unshaded, so it
## reads at night like the toxic plumes in the scavenger key art).
func _smoke_toxic() -> Node3D:
	var r := _root("smoke_toxic")
	r.add_child(_loop(_emitter("Toxic", 48, 7.0, _chimney_pm([[0.0, Color(0.66, 0.76, 0.3, 0)], [0.1, Color(0.62, 0.72, 0.28, 0.3)],
		[0.45, Color(0.6, 0.66, 0.38, 0.17)], [1.0, Color(0.58, 0.62, 0.45, 0)]]), _quad(Vector2(5.5, 5.5), _mat(_puff(), false)), AABB(Vector3(-8, -1, -8), Vector3(26, 30, 18)))))
	return r


func _chimney_pm(ramp: Array) -> ParticleProcessMaterial:
	var pm := _pm()
	_sphere(pm, 0.5, Vector3(0, 0.3, 0))
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 2.8
	pm.damping_min = 0.15
	pm.damping_max = 0.35
	pm.gravity = Vector3(0.7, 0.05, 0.3)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -10.0
	pm.angular_velocity_max = 10.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _curve([[0.0, 0.2], [0.3, 0.6], [1.0, 1.0]])
	pm.color_ramp = _ramp(ramp)
	return pm


# ------------------------------------------------------------------ ship & colony

## Ark engine: hot white core and a blue-white plume, emitted backwards (+Z).
func _thruster() -> Node3D:
	var r := _root("thruster")
	var box := AABB(Vector3(-4, -4, -2), Vector3(8, 8, 18))
	var core := _pm()
	_sphere(core, 0.25)
	core.direction = Vector3(0, 0, 1)
	core.spread = 3.0
	core.initial_velocity_min = 16.0
	core.initial_velocity_max = 20.0
	core.scale_min = 0.9
	core.scale_max = 1.1
	core.scale_curve = _curve([[0.0, 1.0], [1.0, 0.25]])
	core.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.4, Color(0.75, 0.9, 1, 0.8)], [1.0, Color(0.4, 0.65, 1, 0)]])
	r.add_child(_loop(_emitter("Core", 48, 0.3, core, _quad(Vector2(1.6, 1.6), _mat(_glow(), true)), box)))
	var pl := _pm()
	_sphere(pl, 0.6)
	pl.direction = Vector3(0, 0, 1)
	pl.spread = 5.0
	pl.initial_velocity_min = 13.0
	pl.initial_velocity_max = 17.0
	pl.damping_min = 2.0
	pl.damping_max = 4.0
	pl.scale_min = 0.8
	pl.scale_max = 1.2
	pl.scale_curve = _curve([[0.0, 0.45], [1.0, 1.0]])
	pl.color_ramp = _ramp([[0.0, Color(0.62, 0.86, 1, 0.55)], [0.5, Color(0.35, 0.6, 1, 0.3)], [1.0, Color(0.2, 0.35, 0.9, 0)]])
	r.add_child(_loop(_emitter("Plume", 120, 0.75, pl, _quad(Vector2(2.4, 2.4), _mat(_glow(), true)), box)))
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var gm := _mat(_glow(), true)
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.vertex_color_use_as_albedo = false
	gm.albedo_color = Color(0.7, 0.88, 1, 0.9)
	glow.mesh = _quad(Vector2(4.5, 4.5), gm)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(glow)
	var l := OmniLight3D.new()
	l.name = "EngineLight"
	l.light_color = Color(0.55, 0.78, 1)
	l.light_energy = 2.0
	l.omni_range = 9.0
	l.position = Vector3(0, 0, 1.5)
	r.add_child(l)
	return r


## Construction site: intermittent welding bursts with gravity, a flash and a wisp.
func _construction_sparks() -> Node3D:
	var r := _root("construction_sparks", 1)  # BURSTS
	r.set("burst_interval", Vector2(0.35, 1.4))
	r.set("burst_jitter", Vector3(1.4, 0.7, 1.4))
	var box := AABB(Vector3(-5, -1, -5), Vector3(10, 7, 10))
	var pm := _pm()
	_sphere(pm, 0.08)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([[0.0, Color(1, 0.97, 0.8, 1)], [0.2, Color(1, 0.78, 0.35, 1)], [0.7, Color(0.91, 0.55, 0.16, 0.9)],
		[1.0, Color(0.7, 0.28, 0.08, 0)]])
	var sp := _shot(_emitter("Sparks", 40, 1.0, pm, _quad(Vector2(0.045, 0.3), _mat(_dot([[0.0, 1.0], [0.5, 0.85], [1.0, 0.0]], 32), false, false)), box), 0.92)
	sp.randomness = 0.5
	sp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	sp.position = Vector3(0, 2.6, 0)
	r.add_child(sp)
	var fl := _pm()
	_sphere(fl, 0.05)
	fl.scale_min = 0.8
	fl.scale_max = 1.2
	fl.scale_curve = _curve([[0.0, 1.0], [1.0, 0.1]])
	fl.color_ramp = _ramp([[0.0, Color(1, 0.95, 0.8, 1)], [1.0, Color(1, 0.7, 0.3, 0)]])
	var flare := _shot(_emitter("Flare", 2, 0.25, fl, _quad(Vector2(0.9, 0.9), _mat(_glow(), true)), box), 1.0)
	flare.position = Vector3(0, 2.6, 0)
	r.add_child(flare)
	var sm := _pm()
	_sphere(sm, 0.15)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 20.0
	sm.initial_velocity_min = 0.3
	sm.initial_velocity_max = 0.6
	sm.scale_curve = _curve([[0.0, 0.4], [1.0, 1.0]])
	sm.color_ramp = _ramp([[0.0, Color(0.75, 0.75, 0.72, 0)], [0.2, Color(0.75, 0.75, 0.72, 0.22)], [1.0, Color(0.7, 0.7, 0.7, 0)]])
	var wisp := _shot(_emitter("Wisp", 4, 2.2, sm, _quad(Vector2(0.8, 0.8), _mat(_puff(), false)), box), 0.6)
	wisp.position = Vector3(0, 2.6, 0)
	r.add_child(wisp)
	r.add_child(_flash(Color(1, 0.78, 0.45), 2.2, 5.0, Vector3(0, 2.8, 0)))
	return r


## Power surge: short teal arcs (velocity-stretched streaks), crackle and a flicker.
func _power_surge() -> Node3D:
	var r := _root("power_surge", 1)
	r.set("burst_interval", Vector2(0.15, 1.1))
	r.set("burst_jitter", Vector3(0.5, 0.4, 0.5))
	var box := AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	var pm := _pm()
	_sphere(pm, 0.35)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 12.0
	pm.damping_min = 8.0
	pm.damping_max = 14.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.35, Color(0.6, 0.95, 0.92, 0.95)], [1.0, Color(0.5, 0.84, 0.82, 0)]])
	var arcs := _shot(_emitter("Arcs", 26, 0.24, pm, _quad(Vector2(0.04, 0.6), _mat(_dot([[0.0, 1.0], [0.4, 0.9], [1.0, 0.0]], 32), true, false)), box), 1.0)
	arcs.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	arcs.position = Vector3(0, 1.2, 0)
	r.add_child(arcs)
	var cr := _pm()
	_sphere(cr, 0.4)
	cr.scale_min = 0.4
	cr.scale_max = 1.0
	cr.scale_curve = _curve([[0.0, 1.0], [1.0, 0.2]])
	cr.color_ramp = _ramp([[0.0, Color(0.85, 1, 1, 0.9)], [1.0, Color(0.5, 0.84, 0.82, 0)]])
	var crack := _shot(_emitter("Crackle", 8, 0.18, cr, _quad(Vector2(0.7, 0.7), _mat(_glow(), true)), box), 0.9)
	crack.position = Vector3(0, 1.2, 0)
	r.add_child(crack)
	r.add_child(_flash(Color(0.5, 0.84, 0.82), 3.0, 6.0, Vector3(0, 1.4, 0)))
	return r


## Scanner: expanding ground rings (FxScanRing) and a few rising motes at the centre.
func _scan_pulse() -> Node3D:
	var r := _root("scan_pulse")
	var tex := _dot([[0.0, 0.0], [0.72, 0.0], [0.88, 0.55], [0.95, 1.0], [1.0, 0.0]], 256)
	for i: int in 2:
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % (i + 1)
		var pmesh := PlaneMesh.new()
		pmesh.size = Vector2(2, 2)
		ring.mesh = pmesh
		var m := _mat(tex, true, false)
		m.vertex_color_use_as_albedo = false
		m.albedo_color = Color(0.5, 0.84, 0.82, 0.9)
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.15
		ring.set_script(RING_SCRIPT)
		ring.set("phase", 0.5 * i)
		r.add_child(ring)
	var pm := _pm()
	_sphere(pm, 0.4, Vector3(0, 0.2, 0))
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([[0.0, Color(0.5, 0.84, 0.82, 0)], [0.2, Color(0.6, 0.92, 0.9, 0.9)], [1.0, Color(0.12, 0.44, 0.47, 0)]])
	r.add_child(_loop(_emitter("Motes", 24, 2.5, pm, _quad(Vector2(0.12, 0.12), _mat(_glow(), true)), AABB(Vector3(-2, -1, -2), Vector3(4, 6, 4)))))
	return r


## Lander touchdown: radial ground dust burst (repeats while shown; set mode ONCE
## for a single touchdown).
func _landing_dust() -> Node3D:
	var r := _root("landing_dust", 1)
	r.set("burst_interval", Vector2(3.2, 4.2))
	var box := AABB(Vector3(-12, -1, -12), Vector3(24, 6, 24))
	var pm := _pm()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 1.6
	pm.emission_ring_inner_radius = 0.6
	pm.emission_ring_height = 0.2
	pm.emission_shape_offset = Vector3(0, 0.4, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.radial_velocity_min = 5.0
	pm.radial_velocity_max = 8.0
	pm.radial_velocity_curve = _curve([[0.0, 1.0], [0.3, 0.3], [1.0, 0.0]])
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.scale_curve = _curve([[0.0, 0.3], [0.4, 0.9], [1.0, 1.5]], 1.5)
	pm.color_ramp = _ramp([[0.0, Color(0.75, 0.6, 0.42, 0)], [0.08, Color(0.75, 0.6, 0.42, 0.4)], [0.6, Color(0.72, 0.58, 0.4, 0.2)],
		[1.0, Color(0.7, 0.56, 0.4, 0)]])
	r.add_child(_shot(_emitter("Cloud", 64, 3.0, pm, _quad(Vector2(3.0, 3.0), _mat(_puff(), false)), box), 0.85))
	var gr := _pm()
	_sphere(gr, 0.8, Vector3(0, 0.2, 0))
	gr.direction = Vector3(0, 1, 0)
	gr.spread = 25.0
	gr.initial_velocity_min = 1.5
	gr.initial_velocity_max = 3.5
	gr.radial_velocity_min = 6.0
	gr.radial_velocity_max = 10.0
	gr.radial_velocity_curve = _curve([[0.0, 1.0], [0.5, 0.3], [1.0, 0.0]])
	gr.gravity = Vector3(0, -6.0, 0)
	gr.damping_min = 1.0
	gr.damping_max = 2.0
	gr.scale_min = 0.6
	gr.scale_max = 1.3
	gr.color_ramp = _ramp([[0.0, Color(0.5, 0.4, 0.28, 0.9)], [0.7, Color(0.5, 0.4, 0.28, 0.7)], [1.0, Color(0.5, 0.4, 0.28, 0)]])
	r.add_child(_shot(_emitter("Grit", 50, 1.4, gr, _quad(Vector2(0.08, 0.08), _mat(_soft(), false)), box), 0.95))
	return r
