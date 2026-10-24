class_name StarMapView
extends Control
## 2D star map: candidate worlds, routes from the ark's position with their
## fuel cost, the ark marker and the selection. Click a world to select it.
## Look (D-046, after the POLYGON Sci-Fi Space key art and the owner's galaxy-map
## bar): a painted nebula with a navigation grid (art/shaders/starmap_nebula),
## the whole route network faintly, glowing routes from the Ark with a flow of
## light along the selected one, each world as a still render of its faceted
## space planet (PlanetDiorama "icon") in its atmosphere glow, HUD rings and
## brackets. Route risk stays a symbol as well as a colour (▲ / ✕).

signal planet_selected(location_id: String)

const ICON := 58.0  # planet render diameter on the map (px)

var selected := ""
var _hover := ""
var _icons: Dictionary = {}  # location -> PlanetDiorama (still icon render)
var _bg: ColorRect
var _glow_tex: GradientTexture2D
var _atmo: Dictionary = {}  # planet id -> Color (space_planets.json "atmo")
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(600, 600)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_bg = ColorRect.new()
	_bg.show_behind_parent = true
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/starmap_nebula.gdshader")
	m.set_shader_parameter("drift", 0.0 if FxEffect.reduced_motion() else 0.004)
	m.set_shader_parameter("sun_uv", Vector2(0.08, 0.1))
	_bg.material = m
	add_child(_bg)
	resized.connect(_on_resized)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0)])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(0.5, 0.0)
	_glow_tex.width = 64
	_glow_tex.height = 64
	var planets := DictUtil.get_dict(DictUtil.load_json(PlanetLook.DATA), "planets")
	for pid: String in planets.keys():
		_atmo[pid] = Color(str((planets[pid] as Dictionary).get("atmo", "#8fd0ff")))


func _on_resized() -> void:
	var m := minf(size.x, size.y)
	if m > 0.0:
		(_bg.material as ShaderMaterial).set_shader_parameter("aspect", size / m)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or FxEffect.reduced_motion():
		return
	_t += delta
	queue_redraw()  # light flowing along the selected route, turning brackets


func _pos(loc: String) -> Vector2:
	var sp: Array = DictUtil.get_arr(GameSession.content.locations.get(loc, {}), "star_position")
	var c := size * 0.5
	if sp.size() < 2:
		return c
	return c + Vector2(float(sp[0]), float(sp[1])) * minf(size.x, size.y) * 0.4


func _draw() -> void:
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var here := gs.campaign.location_id
	var font := get_theme_default_font()
	# The whole network, faint: the region reads as charted space.
	for r: Dictionary in content.routes:
		var a := str(r.get("a", ""))
		var b := str(r.get("b", ""))
		if a == here or b == here:
			continue
		_dotted(_pos(a), _pos(b), Color(0.6, 0.9, 1.0, 0.12), 1.0, 5.0)
	# Routes from the Ark: a soft glow under a bright core; fuel cost in a pill.
	var pills: Array = []  # [Rect2, text, colour, selected]
	for loc: String in content.locations.keys():
		if loc == here:
			continue
		var r: Dictionary = content.route_between(here, loc)
		if r.is_empty():
			continue
		var q := GameSession.sim.travel.quote(gs, loc)
		var col := Color("4fe0d8") if q["ok"] and not q["risky"] else (UiKit.WARN if q["ok"] else UiKit.DANGER)
		var a := _pos(here)
		var b := _pos(loc)
		var sel := loc == selected
		draw_line(a, b, Color(col, 0.16 if sel else 0.07), 9.0 if sel else 6.0, true)
		if sel:
			draw_line(a, b, Color(col, 0.9), 2.4, true)
			_flow(a, b, col)
		else:
			_dotted(a, b, Color(col, 0.6), 1.5, 7.0)
		var mid := a.lerp(b, 0.42)  # a little towards the Ark: clear of the world's name
		# Route risk is also a symbol, not only a colour: ▲ risky, ✕ not possible.
		var mark := "" if q["ok"] and not q["risky"] else (" " + UiKit.status_icon("warning") if q["ok"] else " " + UiKit.status_icon("locked"))
		var txt := Loc.t("%d fuel") % int(r.get("fuel", 0)) + mark
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var pill := Rect2(mid + Vector2(-tw * 0.5 - 7.0, -10.0), Vector2(tw + 14.0, 20.0))
		if sel:
			pills.append([pill, txt, col, sel])  # drawn last: on top of its neighbours
		else:
			pills.push_front([pill, txt, col, sel])
	for pl: Array in pills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.04, 0.08, 0.86)
		sb.border_color = Color(pl[2] as Color, 0.95 if pl[3] else 0.45)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		draw_style_box(sb, pl[0])
		draw_string(font, (pl[0] as Rect2).position + Vector2(7.0, 15.0), str(pl[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color((pl[2] as Color).lightened(0.25), 1.0))
	# Locations: worlds as planet renders in their glow; the drift point as a beacon.
	for loc: String in content.locations.keys():
		var p := _pos(loc)
		var pid := str(content.locations[loc].get("planet_id", ""))
		if pid.is_empty():
			var bc := Color("7fe8e0")
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), Color(bc, 0.85))
			draw_arc(p, 13.0, 0.0, TAU, 32, Color(bc, 0.4), 1.0, true)
			_label(font, p + Vector2(0, 40), str(content.locations[loc].get("name", loc)), 13, Color(UiKit.MUTED.lightened(0.2), 0.95))
			continue
		var atmo: Color = _atmo.get(pid, Color(str(content.planet(pid).get("palette", {}).get("nature", "#8fa3ad"))))
		var rad := ICON * 0.5
		draw_texture_rect(_glow_tex, Rect2(p - Vector2.ONE * rad * 2.2, Vector2.ONE * rad * 4.4), false, Color(atmo, 0.85))
		_place_icon(loc, pid, p)
		# HUD ring with ticks; brighter on hover; amber turning brackets on the selection.
		var ring := rad + 9.0
		var rc := Color("7fe8e0", 0.75 if loc == _hover else 0.35)
		draw_arc(p, ring, 0.0, TAU, 48, rc, 1.0, true)
		for i: int in 4:
			var ang := TAU * i / 4.0 + PI * 0.25
			draw_line(p + Vector2.from_angle(ang) * (ring - 3.0), p + Vector2.from_angle(ang) * (ring + 4.0), rc, 1.5)
		if loc == selected:
			var spin := _t * 0.6
			for i: int in 4:
				var a0 := spin + TAU * i / 4.0
				draw_arc(p, ring + 6.0, a0, a0 + 0.7, 10, UiKit.AMBER, 2.5, true)
		if loc in gs.campaign.visited:
			draw_arc(p, rad + 2.0, 0.0, TAU, 32, Color(UiKit.TEXT, 0.7), 1.0, true)
		_label(font, p + Vector2(0, ring + 20.0), str(content.locations[loc].get("name", loc)).to_upper(), 15, UiKit.AMBER if loc == selected else UiKit.TEXT)
	# The Ark: an amber chevron with a soft pulse ring.
	var ark := _pos(here)
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	draw_texture_rect(_glow_tex, Rect2(ark - Vector2.ONE * 26.0, Vector2.ONE * 52.0), false, Color(UiKit.AMBER, 0.7))
	draw_arc(ark, 14.0 + pulse * 6.0, 0.0, TAU, 32, Color(UiKit.AMBER, 0.55 * (1.0 - pulse)), 1.5, true)
	draw_colored_polygon(PackedVector2Array([ark + Vector2(0, -12), ark + Vector2(8, 8), ark + Vector2(0, 4), ark + Vector2(-8, 8)]), UiKit.AMBER)
	draw_string(font, ark + Vector2(13, -8), "ARK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.AMBER)


## Text centred on x with a dark outline so it reads over the bright nebula.
func _label(font: Font, at: Vector2, text: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var o := at - Vector2(w * 0.5, 0)
	draw_string_outline(font, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.01, 0.01, 0.04, 0.85))
	draw_string(font, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _dotted(a: Vector2, b: Vector2, col: Color, w: float, step: float) -> void:
	draw_dashed_line(a, b, col, w, step, true, true)


## Light pulses running from the Ark to the selected world (static with reduced motion).
func _flow(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var n := int(len / 38.0)
	for i: int in n:
		var f := fmod(float(i) / float(n) + _t * 0.18, 1.0)
		var pt := a.lerp(b, f)
		draw_circle(pt, 2.6, Color(col.lightened(0.5), 0.9 * sin(f * PI)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var h := _hit((event as InputEventMouseButton).position)
		if not h.is_empty() and h != GameSession.state.campaign.location_id:
			selected = h
			AudioService.ui("ui_click")
			planet_selected.emit(h)
			queue_redraw()


func _hit(p: Vector2) -> String:
	for loc: String in GameSession.content.locations.keys():
		if str(GameSession.content.locations[loc].get("planet_id", "")).is_empty():
			continue
		if _pos(loc).distance_to(p) < ICON * 0.5 + 8.0:
			return loc
	return ""


## Each world as a still render of its space planet (same model and look as
## in orbit and on the approach).
func _place_icon(loc: String, pid: String, p: Vector2) -> void:
	var icon: PlanetDiorama = _icons.get(loc)
	if icon == null:
		icon = PlanetDiorama.make(pid, "icon", Vector2i(int(ICON), int(ICON)))
		add_child(icon)
		_icons[loc] = icon
	icon.size = Vector2.ONE * ICON
	icon.position = p - icon.size * 0.5
