extends Node3D
## Main menu over a slow cinematic shot: the ark drifting past a candidate world
## against the star field and a faint nebula. With "reduced motion" the camera,
## ark and UI stay still and nothing fades (D-035).

const ATMO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform vec4 rim_color : source_color = vec4(0.45, 0.85, 0.9, 1.0);
uniform float rim_power = 3.0;
uniform float rim_strength = 1.6;
uniform vec3 sun_dir = vec3(-0.8, 0.3, 0.5);
void fragment() {
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = 0.08 + 0.92 * smoothstep(-0.35, 0.6, dot(n_world, normalize(sun_dir)));
	// Front faces of a shell slightly larger than the planet: glow builds
	// towards the limb and fades out again at the shell's own edge.
	float d = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - d, rim_power) * smoothstep(0.0, 0.25, d);
	ALBEDO = rim_color.rgb * rim * rim_strength * lit;
}
"""

const NEBULA_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
uniform vec4 tint_a : source_color = vec4(0.06, 0.22, 0.26, 1.0);
uniform vec4 tint_b : source_color = vec4(0.30, 0.16, 0.06, 1.0);
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
void fragment() {
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
	float n = fbm(d * 2.6 + vec3(3.1, 0.0, 1.7));
	float m = fbm(d * 5.0 - vec3(1.0, 2.0, 0.5));
	float band = smoothstep(0.55, 0.0, abs(d.y + 0.25 * d.x - 0.08));
	vec3 col = tint_a.rgb * smoothstep(0.45, 0.9, n) * (0.15 + band) + tint_b.rgb * smoothstep(0.6, 0.95, m) * band * 0.6;
	ALBEDO = col * 0.4;
}
"""

const ARK_BASE := Vector3(19.0, 5.0, -40.0)
const CAM_BASE := Vector3(-10.0, 4.0, 50.0)
const CAM_TARGET := Vector3(2.0, -2.0, -20.0)

var _ark: Node3D
var _planet: Node3D
var _cam: Camera3D
var _settings: SettingsPanel
var _credits: CreditsPanel
var _col: VBoxContainer
var _body: VBoxContainer
var _ui: Control
var _t := 0.0
var _sun_dir := Vector3(-0.8, 0.3, 0.5)
var _focus_sound_armed := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioService.set_ambience("amb_space")
	AudioService.set_music("music_hope")
	_build_world()
	_build_ui()
	_settings = SettingsPanel.new()
	_settings.closed.connect(_on_panel_closed)
	add_child(_settings)
	_credits = CreditsPanel.new()
	_credits.closed.connect(_on_panel_closed)
	add_child(_credits)
	_build()
	_apply_pose(0.0)
	if not UiKit.calm():
		UiKit.fade_in(_ui, 1.2)


func _build_world() -> void:
	var backdrop := SpaceBackdrop.new()
	add_child(backdrop)
	# Grade the shared backdrop for a cinematic key: low ambient, strong rim sun.
	for c: Node in backdrop.get_children():
		if c is WorldEnvironment:
			var e := (c as WorldEnvironment).environment
			e.ambient_light_energy = 0.35
			e.glow_intensity = 1.0
			e.glow_bloom = 0.18
			e.adjustment_enabled = true
			e.adjustment_contrast = 1.08
			e.adjustment_saturation = 1.05
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.rotation_degrees = Vector3(-18, -118, 0)
			sun.light_energy = 1.9
			_sun_dir = sun.global_transform.basis.z if sun.is_inside_tree() else Basis.from_euler(sun.rotation).z
	var neb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1500.0
	sphere.height = 3000.0
	sphere.radial_segments = 32
	sphere.rings = 16
	neb.mesh = sphere
	var nm := ShaderMaterial.new()
	var ns := Shader.new()
	ns.code = NEBULA_SHADER
	nm.shader = ns
	neb.material_override = nm
	neb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(neb)
	_planet = Node3D.new()
	_planet.position = Vector3(112, -96, -215)
	_planet.add_child(VisualSlot.make("space.planet_green"))
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 66.0
	am.height = 132.0
	atmo.mesh = am
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ATMO_SHADER
	mat.shader = sh
	mat.set_shader_parameter("sun_dir", _sun_dir)
	atmo.material_override = mat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet.add_child(atmo)
	add_child(_planet)
	_ark = Node3D.new()
	_ark.add_child(VisualSlot.make("space.ark_exterior"))
	add_child(_ark)
	_cam = Camera3D.new()
	_cam.fov = 46
	add_child(_cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiKit.theme()
	layer.add_child(_ui)
	# Readability: a navy wash from the left edge and a soft floor, so the
	# column stays legible over any art the ark slot brings.
	_ui.add_child(_wash(Vector2(0, 0.5), Vector2(1, 0.5), 0.86, Control.PRESET_LEFT_WIDE, Vector2(820, 0)))
	_ui.add_child(_wash(Vector2(0.5, 1), Vector2(0.5, 0), 0.7, Control.PRESET_BOTTOM_WIDE, Vector2(0, 220)))
	_ui.add_child(_wash(Vector2(0.5, 0), Vector2(0.5, 1), 0.5, Control.PRESET_TOP_WIDE, Vector2(0, 120)))
	# One column, centred vertically: title, menu and tagline never overlap at any UI scale.
	_col = UiKit.vbox(0)
	_col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_col.offset_left = 110
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui.add_child(_col)
	var title := UiKit.label("GENESIS ARK", 84, UiKit.TEXT)
	title.add_theme_font_override("font", UiKit.font_variant(0.35, 8))
	title.add_theme_color_override("font_shadow_color", Color(0, 0.02, 0.05, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 10)
	_col.add_child(title)
	var rule := UiKit.hbox(8)
	rule.add_child(_rule(UiKit.AMBER, 72))
	rule.add_child(_rule(UiKit.PETROL, 180))
	_col.add_child(rule)
	_col.add_child(_gap(16))
	_col.add_child(UiKit.label(Loc.t("You are the last human who can give humanity a future."), 22, UiKit.MUTED.lightened(0.15)))
	_col.add_child(_gap(36))
	_body = UiKit.vbox(8)
	_body.custom_minimum_size = Vector2(380, 0)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_col.add_child(_body)
	_col.add_child(_gap(30))
	_col.add_child(UiKit.label(Loc.t("50,000 embryos. Six possible worlds. One choice you must live with."), 16, UiKit.AMBER))
	var ver := UiKit.label(Loc.t("v%s · Godot %s · greybox-proxies") % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().get("string")], 13, UiKit.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -28
	ver.offset_bottom = -20
	_ui.add_child(ver)


func _wash(from: Vector2, to: Vector2, alpha: float, preset: Control.LayoutPreset, size: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.BG, alpha))
	g.set_color(1, Color(UiKit.BG, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 64
	gt.height = 64
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(preset)
	if size.x > 0.0:
		r.offset_right = r.offset_left + size.x
	if size.y > 0.0:
		if preset == Control.PRESET_BOTTOM_WIDE:
			r.offset_top = -size.y
		else:
			r.offset_bottom = size.y
	return r


func _rule(c: Color, w: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(w, 3)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gap(h: float) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp


func _menu_button(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, cb)
	UiKit.style_menu_button(b, not UiKit.calm())
	b.focus_entered.connect(func() -> void:
		if _focus_sound_armed and SettingsService.using_pad:
			AudioService.ui("ui_hover"))
	return b


func _build() -> void:
	_focus_sound_armed = false
	UiKit.clear(_body)
	var first: Button
	if SaveService.has_any():
		first = _menu_button(Loc.t("Continue"), _continue)
		_body.add_child(first)
	var nb := _menu_button(Loc.t("New campaign"), _new)
	_body.add_child(nb)
	if first == null:
		first = nb
	if SaveService.has_any():
		_body.add_child(_menu_button(Loc.t("Load"), _load_list))
	_body.add_child(_menu_button(Loc.t("Settings"), func() -> void: _open_panel(_settings)))
	_body.add_child(_menu_button(Loc.t("Credits"), func() -> void: _open_panel(_credits)))
	if OS.get_name() != "Web":
		_body.add_child(_menu_button(Loc.t("Quit"), func() -> void: get_tree().quit()))
	first.grab_focus.call_deferred()
	set_deferred("_focus_sound_armed", true)


func _open_panel(p: CanvasLayer) -> void:
	_col.visible = false
	p.call("open")


func _on_panel_closed() -> void:
	_col.visible = true
	if not UiKit.calm():
		UiKit.fade_in(_col, 0.25)
	_build()


func _new() -> void:
	GameSession.new_campaign()
	AppFlow.goto("ship")


func _continue() -> void:
	var slot := SaveService.latest_slot()
	_try_load(slot, false)


func _load_list() -> void:
	UiKit.clear(_body)
	for slot: String in SaveService.SLOTS:
		if SaveService.store.exists(slot):
			_body.add_child(_menu_button("%s — %s" % [Loc.t(str(SaveService.SLOT_LABELS[slot])), PauseMenu._describe(SaveService.summary(slot))], func() -> void: _try_load(slot, false)))
	_body.add_child(_menu_button(Loc.t("Back"), _build))
	(_body.get_child(0) as Control).grab_focus.call_deferred()


func _try_load(slot: String, backup: bool) -> void:
	var r := GameSession.load_from(slot, backup)
	if r["ok"]:
		AppFlow.continue_game()
		return
	UiKit.clear(_body)
	_body.add_child(UiKit.label(Loc.t("Could not load: ") + str(r["error"]), 17, UiKit.WARN, true))
	if r["backup_available"] and not backup:
		_body.add_child(_menu_button(Loc.t("Load latest valid backup"), func() -> void: _try_load(slot, true)))
	var back := _menu_button(Loc.t("Back"), _build)
	_body.add_child(back)
	back.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if UiKit.calm():
		return
	_t += delta
	_apply_pose(_t)


## One pose per time value: slow camera drift (a lazy figure-eight around the
## base framing) and the ark gliding past the planet. t = 0 is the still frame
## used when reduced motion is on.
func _apply_pose(t: float) -> void:
	_ark.position = ARK_BASE + Vector3(sin(t * 0.021) * 7.0, sin(t * 0.37) * 0.35, cos(t * 0.017) * 3.0)
	_ark.rotation_degrees = Vector3(7.0 + sin(t * 0.23) * 0.6, 32.0 + sin(t * 0.021) * 6.0, -5.0 + sin(t * 0.19) * 0.8)
	_planet.rotation.y = t * 0.004
	_cam.position = CAM_BASE + Vector3(sin(t * 0.05) * 2.4, sin(t * 0.083) * 0.9, cos(t * 0.041) * 1.6)
	_cam.look_at(CAM_TARGET + Vector3(sin(t * 0.03) * 0.8, 0.0, 0.0))


## Evidence captures only (DebugCapture --action=credits|settings|still).
func debug_action(action: String) -> void:
	match action:
		"credits": _open_panel(_credits)
		"settings": _open_panel(_settings)
		"focus2":
			if _body.get_child_count() > 1:
				(_body.get_child(1) as Control).grab_focus()
		"drift":
			_t = 60.0
			_apply_pose(_t)
