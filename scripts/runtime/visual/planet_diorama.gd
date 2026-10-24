class_name PlanetDiorama
extends SubViewportContainer
## A small live 3D view of one world for the 2D panels (D-046), after the
## POLYGON Sci-Fi Space key art and the owner's galaxy-map bar: the faceted
## planet with its halo, moons and ring (PlanetLook) in its own little world.
##   "orbit"   - the orbital terminal: the painted nebula, the sun, the Ark on
##               a tilted orbit, satellites, a station and passing traffic.
##   "preview" - the star map's selected world: nebula, planet and moons.
##   "icon"    - a still, transparent render for map markers (drawn a few
##               frames, then frozen).
## Presentation only; everything reads data/art/space_planets.json
## ("orbit_view") and the local pack models, and degrades to the proxy sphere
## without them. Reduced motion: nothing moves, the frame stays put.

const R := 60.0  # the space.planet_* slot sphere radius

var planet_id := ""
var mode := "preview"
var _vp: SubViewport
var _world: Node3D
var _planet: VisualSlot
var _cam: Camera3D
var _movers: Array = []  # [{pivot: Node3D, speed: float (rad/s)}]
var _frames := 0
var _still := false


static func make(pid: String, view_mode: String, px: Vector2i) -> PlanetDiorama:
	var d := PlanetDiorama.new()
	d.planet_id = pid
	d.mode = view_mode
	d.custom_minimum_size = Vector2(px)
	d.stretch = true
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## The view in a HUD frame: thin petrol border, corner brackets and a caption
## (the world's name, as data text) in the top-left corner.
static func framed(view: Control, caption: String) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.02, 0.05, 1.0)
	sb.border_color = Color(UiKit.PETROL, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(1)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(view)
	var over := Control.new()
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.draw.connect(func() -> void:
		var s := over.size
		var c := Color("7fe8e0")
		var k := 18.0
		for corner: Vector2 in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), Vector2(s.x, s.y)]:
			var dx := k if corner.x == 0.0 else -k
			var dy := k if corner.y == 0.0 else -k
			over.draw_line(corner, corner + Vector2(dx, 0), c, 2.0)
			over.draw_line(corner, corner + Vector2(0, dy), c, 2.0))
	box.add_child(over)
	if not caption.is_empty():
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_theme_constant_override("margin_left", 14)
		m.add_theme_constant_override("margin_top", 10)
		var l := UiKit.label(caption.to_upper(), 15, Color("bff6f0"))
		l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		l.add_theme_font_override("font", UiKit.font_variant(0.2, 3))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_outline_size", 4)
		m.add_child(l)
		box.add_child(m)
	return box


func _ready() -> void:
	_still = FxEffect.reduced_motion()
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = mode == "icon"
	_vp.size = Vector2i(custom_minimum_size)
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_build()


## Shows another world in the same view (star map selection).
func set_planet(pid: String) -> void:
	if pid == planet_id and _planet != null:
		return
	planet_id = pid
	if _world != null:
		for c: Node in _world.get_children():
			c.queue_free()
		_movers.clear()
		_build()


func _process(delta: float) -> void:
	if mode == "icon":
		_frames += 1
		if _frames == 8 and _vp:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # keep the last frame
		return
	if _still or not is_visible_in_tree():
		return
	if _planet:
		_planet.rotate_y(delta * 0.03)
	for m: Dictionary in _movers:
		(m["pivot"] as Node3D).rotate_object_local(Vector3.UP, float(m["speed"]) * delta)


func _build() -> void:
	var p := GameSession.content.planet(planet_id)
	var biome := str(p.get("biome_id", "green"))
	var tint := str(DictUtil.get_dict(p, "palette").get("nature", ""))
	var view: Dictionary = DictUtil.get_dict(DictUtil.load_json(PlanetLook.DATA), "orbit_view")
	var sun_rot := Vector3(-14.0, -62.0, 0.0)
	if mode == "icon":
		_icon_lights(sun_rot)
	else:
		var back := SpaceBackdrop.new()
		back.seed_value = 7 + posmod(hash(planet_id), 50)
		back.star_count = 900
		back.glow_star_count = 40
		_world.add_child(back)
		back.set_sun(sun_rot, 1.35)
		back.fill.light_energy = 0.8
		back.environment.ambient_light_energy = 0.4
		# A big bright disc fills this small frame: no wide bloom wash over it.
		back.environment.glow_bloom = 0.0
		back.environment.glow_intensity = 0.6
		back.environment.adjustment_enabled = true
		back.environment.adjustment_saturation = 1.1
	_planet = VisualSlot.make("space.planet_" + biome, tint)
	_world.add_child(_planet)
	PlanetLook.apply(_planet, biome, tint, hash(planet_id), planet_id)
	_cam = Camera3D.new()
	_cam.far = 4000.0
	_world.add_child(_cam)
	match mode:
		"orbit":
			_cam.fov = 38.0
			_cam.position = Vector3(-60.0, 30.0, 215.0)
			_cam.look_at(Vector3(-44.0, 2.0, 0.0))
			_traffic(view)
		"icon":
			_cam.fov = 30.0
			_cam.position = Vector3(0, 0, R * 4.2)
			_cam.look_at(Vector3.ZERO)
			_planet.rebuilt.connect(_icon_only, CONNECT_ONE_SHOT)
		_:
			_cam.fov = 34.0
			# Wide strip: the world on the right third, its moons beside it.
			_cam.position = Vector3(-120.0, 18.0, 300.0)
			_cam.look_at(Vector3(-125.0, 0.0, 0.0))
	_cam.current = true


## Icons show the planet and its halo only: moons would shrink the globe.
func _icon_only() -> void:
	for n: Node in _planet.find_children("Moon*", "", true, false):
		(n as Node3D).visible = false


func _icon_lights(sun_rot: Vector3) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("5a4a7a")
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_rot
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.1
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, 140, 0)
	fill.light_color = Color("8a6cff")
	fill.light_energy = 0.8
	_world.add_child(fill)


## The Ark on a tilted orbit, satellites, a station and two transports with
## trails: the planet reads as a place the Ark is parked at.
func _traffic(view: Dictionary) -> void:
	var sc: Variant = DictUtil.load_json(SpaceScenery.PATH)
	var scd: Dictionary = sc if sc is Dictionary else {}
	var atlas_path := str(scd.get("material", ""))
	var atlas: Material = load(atlas_path) if not atlas_path.is_empty() and ResourceLoader.exists(atlas_path) else null
	# The Ark: the same dressed carrier as in the flight, small against the world.
	var ark_orbit := _orbit_pivot(float(view.get("ark_tilt", 14.0)), float(view.get("ark_phase", 200.0)), float(view.get("ark_speed", 0.05)))
	var ark := VisualSlot.make("space.ark_exterior")
	ark_orbit.add_child(ark)
	ark.position = Vector3(R * float(view.get("ark_radius", 1.42)), 0, 0)
	ark.scale = Vector3.ONE * float(view.get("ark_scale", 0.42))
	ark.rotation_degrees.y = 180.0  # bow (+Z) along the orbit's direction of travel
	if ark.using_asset:
		var spec := DictUtil.get_dict(scd, "ark_fx")
		SpaceFx.dress_ark(ark, spec)
	# The Ark crosses the day side backlit: a soft key from the camera's side lights
	# only the ship (render layer 2), so it reads as a hull, not a black sliver.
	for gi: Node in ark.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers |= 2
	var key := DirectionalLight3D.new()
	key.light_cull_mask = 2
	key.light_color = Color("ffd8b4")
	key.light_energy = float(view.get("ark_key", 0.9))
	key.shadow_enabled = false
	_world.add_child(key)
	key.look_at_from_position(_cam.position if _cam else Vector3(0, 30, 215), Vector3.ZERO)
	for s: Variant in DictUtil.get_arr(view, "satellites"):
		var d: Dictionary = s
		var src := SpaceScenery._source(str(d.get("mesh", "")))
		if src.is_empty():
			continue
		var piv := _orbit_pivot(float(d.get("tilt", 0.0)), float(d.get("phase", 0.0)), float(d.get("speed", 0.08)))
		var n := _model_node(src, atlas, float(d.get("size", 4.0)))
		n.position = Vector3(R * float(d.get("radius", 1.3)), 0, 0)
		n.rotation_degrees = Vector3(20, float(d.get("yaw", 0.0)), 10)
		piv.add_child(n)
		if d.has("light"):
			var g := SpaceFx.glow(float(d.get("size", 4.0)) * 0.5, Color(str(d["light"])), 1.6)
			n.add_child(g)
	for t: Variant in DictUtil.get_arr(view, "traffic"):
		var d: Dictionary = t
		var src := SpaceScenery._source(str(d.get("mesh", "")))
		if src.is_empty():
			continue
		var piv := _orbit_pivot(float(d.get("tilt", 0.0)), float(d.get("phase", 0.0)), float(d.get("speed", 0.1)))
		var size := float(d.get("size", 6.0))
		# Moving along -Z on the orbit: the model's +Z bow turns forward, the
		# engine glow and trail sit behind it (+Z).
		var ship := Node3D.new()
		ship.position = Vector3(R * float(d.get("radius", 1.8)), 0, 0)
		piv.add_child(ship)
		var n := _model_node(src, atlas, size)
		n.rotation_degrees.y = 180.0
		ship.add_child(n)
		var col := Color(str(d.get("trail", "#5fe8ff")))
		var tr := SpaceFx.trail(size * 3.0, size * 0.06, col, 2.0)
		tr.position = Vector3(0, 0, size * 0.45)
		ship.add_child(tr)
		var g := SpaceFx.glow(size * 0.35, col, 1.2)
		g.position = Vector3(0, 0, size * 0.45)
		ship.add_child(g)


## A pivot at the planet's centre, tilted, turned to its start phase; children
## placed on +X circle the planet as it turns.
func _orbit_pivot(tilt_deg: float, phase_deg: float, speed: float) -> Node3D:
	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(tilt_deg, 0, tilt_deg * 0.4)
	_world.add_child(tilt)
	var piv := Node3D.new()
	piv.rotation_degrees.y = phase_deg
	tilt.add_child(piv)
	_movers.append({"pivot": piv, "speed": speed})
	return piv


## A pack model centred and scaled so its largest extent is `size` metres,
## nose along -Z after the model's own orientation (+Z bow models turn 180).
func _model_node(src: Dictionary, mat: Material, size: float) -> Node3D:
	var root := Node3D.new()
	var box: AABB = src["aabb"]
	var holder := Node3D.new()
	var s := size / maxf(0.01, box.get_longest_axis_size())
	holder.transform = Transform3D(Basis().scaled(Vector3.ONE * s), -box.get_center() * s)
	root.add_child(holder)
	for part: Array in src["parts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		if mat:
			mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	return root
