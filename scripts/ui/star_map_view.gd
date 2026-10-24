class_name StarMapView
extends Control
## 2D star map: candidate worlds, routes from the ark's position with their
## fuel cost, the ark marker and the selection. Click a world to select it;
## with the map focused, left/right (keys or pad) step through the worlds.
## Look (D-046, D-055, after the POLYGON Sci-Fi Space key art and the owner's
## Mass Effect / No Man's Sky bar): a painted nebula with a navigation grid and
## pointer parallax (art/shaders/starmap_nebula), a pulsing home star with a
## lens streak, the route network faintly, routes from the Ark as dashes that
## flow outwards with a fuel pill each, a radar sweep with pings around the
## Ark, every world as a slowly turning faceted planet (PlanetDiorama icons,
## re-rendered round-robin a few times a second), HUD rings, a reticle that
## locks onto the selection and icon badges (biome, route risk, visited) under
## each name. Route risk stays a symbol as well as a colour (▲ / ✕).
## Reduced motion: no drift, flow, sweep, spin or lock animation.

signal planet_selected(location_id: String)

const ICON := 64.0  # planet render diameter on the map (px)
const SPIN := 0.35  # planet turn speed on the map (rad/s)

var selected := ""
var _hover := ""
var _icons: Dictionary = {}  # location -> PlanetDiorama (icon render)
var _bg: ColorRect
var _glow_tex: GradientTexture2D
var _atmo: Dictionary = {}  # planet id -> Color (space_planets.json "atmo")
var _t := 0.0
var _lock := 1.0  # 0 -> 1: the reticle closing in on a new selection
var _calm := false
var _parallax := Vector2.ZERO
var _parallax_goal := Vector2.ZERO
var _spin_i := 0
var _spin_acc := 0.0
var _tex: Dictionary = {}  # name -> Texture2D (null without the packs)
var _quotes: Dictionary = {}  # location -> travel quote (refreshed on open)
var _sun: Control  # additive layer for the home star (the flare sprite has a black ground)


func _ready() -> void:
	custom_minimum_size = Vector2(680, 680)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	_calm = HoloAnim.calm()
	_bg = ColorRect.new()
	_bg.show_behind_parent = true
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/starmap_nebula.gdshader")
	m.set_shader_parameter("drift", 0.0 if _calm else 0.004)
	m.set_shader_parameter("sun_uv", Vector2(0.08, 0.1))
	_bg.material = m
	add_child(_bg)
	_sun = Control.new()
	_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.set_anchors_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sun.material = add
	_sun.draw.connect(_draw_sun)
	add_child(_sun)
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
	# HUD sprites (null without the packs: the code-drawn shapes stay).
	_tex = {
		"radar": Holo.tex(Holo.GEN + "Ring_Medium_10.png", 256),
		"radar2": Holo.tex(Holo.GEN + "Ring_Small_04.png", 128),
		"lock": Holo.tex(Holo.GEN + "Ring_Small_06.png", 192),
		"hover": Holo.tex(Holo.GEN + "Ring_Small_03.png", 160),
		"sun_ring": Holo.tex(Holo.GEN + "Ring_Large_03.png", 256),
		"flare": Holo.tex(Holo.FXP + "LensFlare_01.png", 512),
		"glow": Holo.tex(Holo.FXP + "Glow_01.png", 128),
		"ship": SyntySkin.icon("ui.icon_ship", 48),
		"fuel": SyntySkin.icon("ui.icon_fuel_pump", 32),
		"ok": SyntySkin.icon("ui.icon_ok", 32),
		"warning": SyntySkin.icon("ui.icon_warning", 32),
		"locked": SyntySkin.icon("ui.icon_locked", 32),
		"flag": SyntySkin.icon("ui.icon_flag", 32),
	}
	for b: String in ["green", "desert", "ice"]:
		_tex["biome." + b] = SyntySkin.icon("biome." + b, 32)
	refresh_quotes()
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Route quotes are domain reads; cache them per open instead of every frame.
func refresh_quotes() -> void:
	_quotes.clear()
	var gs: GameState = GameSession.state
	for loc: String in GameSession.content.locations.keys():
		if loc != gs.campaign.location_id:
			_quotes[loc] = GameSession.sim.travel.quote(gs, loc)
	queue_redraw()


func _on_resized() -> void:
	var m := minf(size.x, size.y)
	if m > 0.0:
		(_bg.material as ShaderMaterial).set_shader_parameter("aspect", size / m)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _calm:
		return
	_t += delta
	# Pointer parallax, eased.
	_parallax = _parallax.lerp(_parallax_goal, minf(1.0, delta * 3.0))
	(_bg.material as ShaderMaterial).set_shader_parameter("parallax", _parallax)
	# Turn one planet icon per tick, round-robin (~6 renders a second each).
	_spin_acc += delta
	if _spin_acc >= 1.0 / 36.0 and not _icons.is_empty():
		var keys := _icons.keys()
		_spin_i = (_spin_i + 1) % keys.size()
		var icon: PlanetDiorama = _icons[keys[_spin_i]]
		icon.spin_icon(SPIN * _spin_acc * keys.size())
		_spin_acc = 0.0
	queue_redraw()


## Selects a world (click, keys, the panel): the reticle locks on anew.
func select(loc: String, emit: bool = true) -> void:
	if loc == selected and not emit:
		return
	selected = loc
	_lock = 1.0
	if not _calm:
		_lock = 0.0
		var tw := create_tween()
		tw.tween_property(self, "_lock", 1.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if emit:
		planet_selected.emit(loc)
	queue_redraw()


func _pos(loc: String) -> Vector2:
	var sp: Array = DictUtil.get_arr(GameSession.content.locations.get(loc, {}), "star_position")
	var c := size * 0.5
	if sp.size() < 2:
		return c
	return c + Vector2(float(sp[0]), float(sp[1])) * minf(size.x, size.y) * 0.4


func _quote(loc: String) -> Dictionary:
	if not _quotes.has(loc):
		_quotes[loc] = GameSession.sim.travel.quote(GameSession.state, loc)
	return _quotes[loc]


func _risk_kind(q: Dictionary) -> String:
	return "ok" if q.get("ok", false) and not q.get("risky", false) else ("warning" if q.get("ok", false) else "locked")


func _draw() -> void:
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var here := gs.campaign.location_id
	var font := get_theme_default_font()
	_sun.queue_redraw()
	# The whole network, faint: the region reads as charted space.
	for r: Dictionary in content.routes:
		var a := str(r.get("a", ""))
		var b := str(r.get("b", ""))
		if a == here or b == here:
			continue
		draw_dashed_line(_pos(a), _pos(b), Color(0.6, 0.9, 1.0, 0.12), 1.0, 5.0, true, true)
	var ark := _pos(here)
	_draw_radar(ark)
	# Routes from the Ark: a soft glow under dashes flowing outwards; fuel in a pill.
	var pills: Array = []  # [Rect2, text, colour, selected, kind]
	var taken: Array[Rect2] = [Rect2(ark + Vector2(-14, -22), Vector2(54, 40))]  # the Ark marker and its tag
	for loc: String in content.locations.keys():
		if loc == here:
			continue
		var r: Dictionary = content.route_between(here, loc)
		if r.is_empty():
			continue
		var q := _quote(loc)
		var kind := _risk_kind(q)
		var col: Color = {"ok": Color("4fe0d8"), "warning": UiKit.WARN}.get(kind, UiKit.DANGER)
		var b := _pos(loc)
		var sel := loc == selected
		var hov := loc == _hover
		draw_line(ark, b, Color(col, 0.18 if sel else (0.11 if hov else 0.06)), 10.0 if sel else 6.0, true)
		if sel:
			draw_line(ark, b, Color(col, 0.85), 2.4, true)
			_flow(ark, b, col)
		else:
			_flow_dash(ark, b, Color(col, 0.75 if hov else 0.55), 1.6, 8.0, 6.0)
		# Route risk is also a symbol, not only a colour: ▲ risky, ✕ not possible.
		var mark := "" if kind == "ok" else (" " + UiKit.status_icon(kind))
		var txt := Loc.t("%d fuel") % int(r.get("fuel", 0)) + mark
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + (18.0 if _tex["fuel"] else 0.0)
		# A little towards the Ark (clear of the world's name); slid along its own
		# route when it would sit on a neighbour's pill (routes fan out from the Ark).
		var pill := Rect2()
		for f: float in [0.42, 0.56, 0.3, 0.66, 0.22]:
			pill = Rect2(ark.lerp(b, f) + Vector2(-tw * 0.5 - 8.0, -11.0), Vector2(tw + 16.0, 22.0))
			var free := true
			for t: Rect2 in taken:
				if t.grow(3.0).intersects(pill):
					free = false
					break
			if free:
				break
		taken.append(pill)
		if sel:
			pills.append([pill, txt, col, sel])  # drawn last: on top of its neighbours
		else:
			pills.push_front([pill, txt, col, sel])
	for pl: Array in pills:
		var sb := StyleBoxFlat.new()
		var pc: Color = pl[2]
		sb.bg_color = Color(0.02, 0.04, 0.08, 0.9) if not pl[3] else Color(pc.darkened(0.6), 0.95)
		sb.border_color = Color(pc, 0.95 if pl[3] else 0.5)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(11)
		var rect: Rect2 = pl[0]
		draw_style_box(sb, rect)
		var x := rect.position.x + 8.0
		if _tex["fuel"]:
			draw_texture_rect(_tex["fuel"], Rect2(x, rect.position.y + 4.0, 14, 14), false, pc.lightened(0.3))
			x += 18.0
		draw_string(font, Vector2(x, rect.position.y + 16.0), str(pl[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(pc.lightened(0.35), 1.0))
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
		var breathe := 0.0 if _calm else sin(_t * 1.3 + p.x * 0.01) * 0.08
		draw_texture_rect(_glow_tex, Rect2(p - Vector2.ONE * rad * 2.3, Vector2.ONE * rad * 4.6), false, Color(atmo, 0.8 + breathe))
		_place_icon(loc, pid, p)
		var ring := rad + 9.0
		var hov := loc == _hover
		var sel := loc == selected
		_draw_rings(p, ring, hov, sel)
		var name_col := UiKit.AMBER if sel else (Color.WHITE if hov else UiKit.TEXT)
		_label(font, p + Vector2(0, ring + 22.0), str(content.locations[loc].get("name", loc)).to_upper(), 16, name_col)
		_badges(loc, pid, p + Vector2(0, ring + 34.0), gs)
	# The Ark: the ship glyph (amber) with a soft pulse ring.
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	draw_texture_rect(_glow_tex, Rect2(ark - Vector2.ONE * 28.0, Vector2.ONE * 56.0), false, Color(UiKit.AMBER, 0.75))
	draw_arc(ark, 14.0 + pulse * 6.0, 0.0, TAU, 32, Color(UiKit.AMBER, 0.55 * (1.0 - pulse)), 1.5, true)
	if _tex["ship"]:
		draw_texture_rect(_tex["ship"], Rect2(ark - Vector2(13, 13), Vector2(26, 26)), false, UiKit.AMBER.lightened(0.2))
	else:
		draw_colored_polygon(PackedVector2Array([ark + Vector2(0, -12), ark + Vector2(8, 8), ark + Vector2(0, 4), ark + Vector2(-8, 8)]), UiKit.AMBER)
	draw_string_outline(font, ark + Vector2(15, -9), "ARK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 5, Color(0.01, 0.01, 0.04, 0.85))
	draw_string(font, ark + Vector2(15, -9), "ARK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.AMBER)
	if has_focus():
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(UiKit.AMBER, 0.8), false, 2.0)


## The home star: a pulsing corona, a slow ring and a horizontal lens streak.
func _draw_sun() -> void:
	var sp := Vector2(0.08, 0.1) * size
	var pulse := 0.0 if _calm else 0.5 + 0.5 * sin(_t * 1.1)
	var g: Texture2D = _tex["glow"] if _tex["glow"] else _glow_tex
	var r := 50.0 + pulse * 10.0
	_sun.draw_texture_rect(g, Rect2(sp - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(1.0, 0.6, 0.3, 0.35 + pulse * 0.15))
	_sun.draw_texture_rect(g, Rect2(sp - Vector2.ONE * r * 0.4, Vector2.ONE * r * 0.8), false, Color(1.0, 0.9, 0.75, 0.7))
	if _tex["flare"]:
		var fw := 340.0 + pulse * 50.0
		_sun.draw_texture_rect(_tex["flare"], Rect2(sp - Vector2(fw * 0.5, fw * 0.25), Vector2(fw, fw * 0.5)), false, Color(1.0, 0.8, 0.6, 0.8))
	if _tex["sun_ring"]:
		_sun.draw_set_transform(sp, _t * 0.05, Vector2.ONE)
		_sun.draw_texture_rect(_tex["sun_ring"], Rect2(-Vector2.ONE * 74.0, Vector2.ONE * 148.0), false, Color(1.0, 0.7, 0.4, 0.3))
		_sun.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Radar around the Ark: a turning dashed ring, a sweep wedge and pings.
func _draw_radar(ark: Vector2) -> void:
	var rr := 62.0
	var a := _t * 0.9
	# Sweep: a fan that fades behind the leading edge.
	var steps := 14
	for i: int in steps:
		var a0 := a - 0.08 * (i + 1)
		var a1 := a - 0.08 * i
		var alpha := 0.16 * (1.0 - float(i) / steps)
		draw_colored_polygon(PackedVector2Array([ark, ark + Vector2.from_angle(a0) * rr, ark + Vector2.from_angle(a1) * rr]), Color(UiKit.AMBER, alpha))
	draw_line(ark, ark + Vector2.from_angle(a) * rr, Color(UiKit.AMBER, 0.6), 1.5, true)
	if _tex["radar"]:
		draw_set_transform(ark, -_t * 0.25, Vector2.ONE)
		draw_texture_rect(_tex["radar"], Rect2(-Vector2.ONE * rr, Vector2.ONE * rr * 2.0), false, Color(UiKit.AMBER, 0.45))
		draw_set_transform(ark, _t * 0.6, Vector2.ONE)
		draw_texture_rect(_tex["radar2"], Rect2(-Vector2.ONE * rr * 0.45, Vector2.ONE * rr * 0.9), false, Color(UiKit.AMBER, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_arc(ark, rr, 0.0, TAU, 48, Color(UiKit.AMBER, 0.3), 1.0, true)
	if not _calm:
		for k: int in 2:
			var f := fmod(_t * 0.4 + k * 0.5, 1.0)
			draw_arc(ark, rr * (0.3 + f * 1.1), 0.0, TAU, 48, Color(UiKit.AMBER, 0.35 * (1.0 - f)), 1.2, true)


## HUD ring with ticks; brighter on hover with a turning sprite ring; the
## selection gets a lock-on reticle (brackets closing in, then turning slowly).
func _draw_rings(p: Vector2, ring: float, hov: bool, sel: bool) -> void:
	var rc := Color("7fe8e0", 0.8 if hov or sel else 0.32)
	draw_arc(p, ring, 0.0, TAU, 48, rc, 1.0, true)
	for i: int in 4:
		var ang := TAU * i / 4.0 + PI * 0.25
		draw_line(p + Vector2.from_angle(ang) * (ring - 3.0), p + Vector2.from_angle(ang) * (ring + 4.0), rc, 1.5)
	if hov and not sel and _tex["hover"]:
		draw_set_transform(p, _t * 0.8, Vector2.ONE)
		var d := (ring + 10.0) * 2.0
		draw_texture_rect(_tex["hover"], Rect2(-Vector2.ONE * d * 0.5, Vector2.ONE * d), false, Color("7fe8e0", 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not sel:
		return
	var k := clampf(_lock, 0.0, 1.2)
	var far := ring + 8.0 + (1.0 - k) * 46.0
	var spin := (1.0 - k) * PI * 0.5 + _t * 0.5
	var a := clampf(k * 1.4, 0.0, 1.0)
	# Four amber brackets.
	for i: int in 4:
		var a0 := spin + TAU * i / 4.0
		draw_arc(p, far, a0, a0 + 0.62, 10, Color(UiKit.AMBER, a), 2.6, true)
	# Cross ticks outside the brackets.
	for i: int in 4:
		var ang := TAU * i / 4.0
		draw_line(p + Vector2.from_angle(ang) * (far + 5.0), p + Vector2.from_angle(ang) * (far + 14.0), Color(UiKit.AMBER, a * 0.9), 2.0)
	if _tex["lock"]:
		draw_set_transform(p, -_t * 0.35, Vector2.ONE)
		var d := (ring + 22.0) * 2.0
		draw_texture_rect(_tex["lock"], Rect2(-Vector2.ONE * d * 0.5, Vector2.ONE * d), false, Color(UiKit.AMBER, 0.45 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if k < 1.0:
		draw_arc(p, far + 20.0 * (1.0 - k), 0.0, TAU, 48, Color(UiKit.AMBER, 0.5 * (1.0 - k)), 1.0, true)


## Small icon badges under a world's name: biome, route risk, visited.
func _badges(loc: String, pid: String, at: Vector2, gs: GameState) -> void:
	var items: Array = []  # [Texture2D or null, Color, fallback text]
	var p := GameSession.content.planet(pid)
	var pal := Color(str(DictUtil.get_dict(p, "palette").get("nature", "#8fa3ad")))
	items.append([_tex.get("biome." + str(p.get("biome_id", "green"))), pal.lightened(0.35), "◆"])
	var kind := _risk_kind(_quote(loc))
	items.append([_tex.get(kind), UiKit.status_color(kind) if kind != "ok" else UiKit.OK.lightened(0.2), UiKit.status_icon(kind)])
	if loc in gs.campaign.visited:
		items.append([_tex["flag"], UiKit.TEXT, "⚑"])
	var w := 20.0
	var x := at.x - items.size() * w * 0.5 + w * 0.5
	var font := get_theme_default_font()
	for it: Array in items:
		var c := Vector2(x, at.y)
		draw_circle(c, 9.0, Color(0.01, 0.03, 0.06, 0.85))
		draw_arc(c, 9.0, 0.0, TAU, 20, Color(it[1] as Color, 0.6), 1.0, true)
		if it[0]:
			draw_texture_rect(it[0], Rect2(c - Vector2(6, 6), Vector2(12, 12)), false, it[1])
		else:
			draw_string(font, c + Vector2(-4, 4), str(it[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, it[1])
		x += w


## Text centred on x with a dark outline so it reads over the bright nebula.
func _label(font: Font, at: Vector2, text: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var o := at - Vector2(w * 0.5, 0)
	draw_string_outline(font, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.01, 0.01, 0.04, 0.9))
	draw_string(font, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Dashes flowing from a to b (still with reduced motion).
func _flow_dash(a: Vector2, b: Vector2, col: Color, w: float, dash: float, gap: float) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var dir := (b - a) / len
	var period := dash + gap
	var off := fmod(_t * 22.0, period)
	var s := -period + off
	while s < len:
		var s0 := maxf(0.0, s)
		var s1 := minf(len, s + dash)
		if s1 > s0:
			draw_line(a + dir * s0, a + dir * s1, col, w, true)
		s += period


## Light pulses running from the Ark to the selected world (static with reduced motion).
func _flow(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var n := int(len / 34.0)
	for i: int in n:
		var f := fmod(float(i) / float(n) + _t * 0.2, 1.0)
		var pt := a.lerp(b, f)
		draw_circle(pt, 4.5, Color(col, 0.18 * sin(f * PI)))
		draw_circle(pt, 2.4, Color(col.lightened(0.55), 0.95 * sin(f * PI)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mp := (event as InputEventMouseMotion).position
		_parallax_goal = (mp / size - Vector2(0.5, 0.5)) * 0.05
		var h := _hit(mp)
		if h != _hover:
			_hover = h
			if not h.is_empty() and h != selected:
				AudioService.ui("ui_hover")
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var h := _hit((event as InputEventMouseButton).position)
		if not h.is_empty() and h != GameSession.state.campaign.location_id:
			AudioService.ui("ui_click")
			select(h)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var worlds := _worlds_by_angle()
		if worlds.is_empty():
			return
		var i := worlds.find(selected)
		i = (i + (1 if event.is_action_pressed("ui_right") else -1) + worlds.size()) % worlds.size() if i >= 0 else 0
		AudioService.ui("ui_click")
		select(str(worlds[i]))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_parallax_goal = Vector2.ZERO
		if not _hover.is_empty():
			_hover = ""
			queue_redraw()


## Selectable worlds clockwise around the Ark (keys and pad step through them).
func _worlds_by_angle() -> Array:
	var here := GameSession.state.campaign.location_id
	var ark := _pos(here)
	var out: Array = []
	for loc: String in GameSession.content.locations.keys():
		if loc != here and not str(GameSession.content.locations[loc].get("planet_id", "")).is_empty():
			out.append(loc)
	out.sort_custom(func(a: String, b: String) -> bool: return (_pos(a) - ark).angle() < (_pos(b) - ark).angle())
	return out


func _hit(p: Vector2) -> String:
	for loc: String in GameSession.content.locations.keys():
		if str(GameSession.content.locations[loc].get("planet_id", "")).is_empty():
			continue
		if _pos(loc).distance_to(p) < ICON * 0.5 + 8.0:
			return loc
	return ""


## Each world as a render of its space planet (same model and look as in
## orbit and on the approach), turned a step at a time by _process.
func _place_icon(loc: String, pid: String, p: Vector2) -> void:
	var icon: PlanetDiorama = _icons.get(loc)
	if icon == null:
		icon = PlanetDiorama.make(pid, "icon", Vector2i(int(ICON), int(ICON)))
		add_child(icon)
		_icons[loc] = icon
	icon.size = Vector2.ONE * ICON
	icon.position = p - icon.size * 0.5
