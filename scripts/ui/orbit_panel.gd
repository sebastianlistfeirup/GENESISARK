class_name OrbitPanel
extends OverlayPanel
## In orbit: orbital scan, site probes, expeditions and the landing decision
## with known risks, start stock, energy plan and the option to travel on.
## Holo-console look (D-055): the live orbit diorama large with the planet's
## stat tiles under it and the scan as a glowing action; landing sites as
## cards with a living site map (all sites, this one locked on), its known
## facts as icon meters and locked glyphs for what is still unknown, and the
## actions as icon buttons. The landing page shows risks and unknowns as icon
## bullets, the starting stock as counters and the final confirmation as the
## red primary button.

signal expedition_requested(site_id: String)
signal landing_committed(site_id: String)

var _landing_site := ""
var _landing_txn := ""
var _drone := false
var _focus: Control  # pad focus on open: the scan, else a site's landing button, else Back


func _init() -> void:
	# Fixed width, height from the content: the landing preview is much shorter
	# than the site list and used to leave ~40 % of the panel blank.
	super(Vector2(1240, 0))


func refresh() -> void:
	UiKit.clear(body)
	_focus = null
	regrab_focus.call_deferred()
	_shrink_to_content()
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var pid := GameSession.sim.travel.current_planet_id(gs)
	if pid.is_empty():
		header(Loc.t("Orbit"), Loc.t("The Ark is not in orbit around a planet. Use the star map to travel."), "ui.icon_planet")
		return
	var p := content.planet(pid)
	header(Loc.t("Orbiting %s") % p.get("name"), str(p.get("tagline", "")), "ui.icon_planet", [
		["ui.icon_components", Loc.t("Components %d") % gs.ark.components, UiKit.PETROL.lightened(0.4)],
		["ui.icon_fuel", Loc.t("Fuel %d") % int(gs.ark.fuel), UiKit.AMBER.lightened(0.1)],
		["ui.icon_hull", Loc.t("Hull %d%%") % int(gs.ark.integrity), UiKit.WARN if gs.ark.integrity < 50.0 else UiKit.PETROL.lightened(0.4)]])
	if not _landing_site.is_empty():
		_landing_preview(pid, _landing_site)
		return
	var top := UiKit.hbox(16)
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(600, 0)
	# The world below, live (D-046): the faceted planet with its moons, the Ark
	# parked on its orbit, satellites and traffic against the painted nebula.
	left.add_child(PlanetDiorama.framed(PlanetDiorama.make(pid, "orbit", Vector2i(600, 290)), str(p.get("name", ""))))
	var kh := UiKit.hbox(8)
	var ks := UiKit.section(Loc.t("The planet"), "ui.icon_probe")
	ks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kh.add_child(ks)
	var cmp := GameSession.sim.survey.comparison(gs, pid)
	kh.add_child(Holo.chip(Loc.t("%d of %d known") % [int(cmp["known_count"]), int(cmp["total"])], Color("5fe0c8"), "ui.icon_ok", 11))
	left.add_child(kh)
	left.add_child(StarMapPanel.knowledge_grid(pid, 2, true))
	var k := gs.knowledge_of(pid)
	var done: bool = k.level_reached.get("orbital_scan_done", false)
	var scan := GlowButton.make(Loc.t("Orbital scan (1 day)") if not done else Loc.t("Orbital scan complete"), "ui.icon_target" if not done else "ui.icon_ok", "go", func() -> void:
		GameSession.cmd_orbital_scan(pid)
		refresh())
	scan.disabled = done
	if not done:
		_focus = scan
	if not done:
		scan.set_cost("1", "ui.icon_time", Loc.t("day"))
	left.add_child(scan)
	top.add_child(left)
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(560, 0)
	right.add_child(UiKit.section(Loc.t("Landing sites"), "ui.icon_lander"))
	var chk := CheckButton.new()  # the theme's drawn switch: on/off by shape and position
	chk.text = Loc.t("Plan drone reserve for the expedition (2 components, one refill)")
	chk.button_pressed = _drone
	chk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chk.toggled.connect(func(on: bool) -> void:
		_drone = on
		AudioService.ui("ui_click"))
	var ch := UiKit.hbox(8)
	var dic := UiKit.icon_rect("prop.drone", 30, Color.WHITE)
	if dic:
		ch.add_child(dic)
	chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(chk)
	right.add_child(ch)
	var sites := DictUtil.get_arr(p, "site_templates")
	for sid: Variant in sites:
		right.add_child(_site_card(pid, str(sid), sites))
	top.add_child(right)
	body.add_child(top)


func _site_card(pid: String, sid: String, all_sites: Array) -> PanelContainer:
	var gs: GameState = GameSession.state
	var site := GameSession.content.site(sid)
	var k := gs.knowledge_of(pid)
	var explored := sid in k.expedition_sites
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.85)
	sb.border_color = Color(UiKit.AMBER if explored else UiKit.PETROL.lightened(0.2), 0.5)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	HoloAnim.hover_lift(card, 0.01, 0.08)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UiKit.hbox(12)
	h.add_child(SiteMap.make(pid, sid, all_sites, 116))
	var v := UiKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nh := UiKit.hbox(8)
	var name_l := UiKit.label(str(site.get("name", sid)).to_upper(), 17, UiKit.AMBER.lightened(0.1))
	name_l.add_theme_font_override("font", UiKit.display_variant(1))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(name_l)
	if explored:
		nh.add_child(Holo.chip(Loc.t("Explored"), UiKit.OK.lightened(0.15), "ui.icon_flag", 10))
	elif sid in k.probed_sites:
		nh.add_child(Holo.chip(Loc.t("Probed"), Color("5fe0c8"), "ui.icon_probe", 10))
	v.add_child(nh)
	v.add_child(UiKit.label(str(site.get("description", "")), 13, UiKit.MUTED.lightened(0.1), true))
	v.add_child(_fact_row(k.site_facts.get(sid, {})))
	var row := UiKit.hbox(8)
	var probe := UiKit.button(Loc.t("Site probe (3)"), func() -> void:
		GameSession.cmd_probe(pid, sid)
		refresh(), Loc.t("Reveals water distance, heat source and exposure at this site."))
	UiKit.with_icon(probe, "ui.icon_probe", 18)
	probe.disabled = sid in k.probed_sites or gs.ark.components < 3
	row.add_child(probe)
	var ex := UiKit.button(Loc.t("Expedition"), func() -> void:
		var r := GameSession.cmd_start_expedition(sid, _drone)
		if r.ok:
			close()
			expedition_requested.emit(sid), Loc.t("The captain goes down in person: samples, relay and assessment of the landing site."))
	UiKit.with_icon(ex, "ui.icon_expedition", 18)
	ex.disabled = explored
	row.add_child(ex)
	var land := UiKit.button(Loc.t("Prepare landing…"), func() -> void:
		_landing_site = sid
		_landing_txn = GameSession.txn("landing")
		refresh())
	UiKit.with_icon(land, "ui.icon_lander", 18)
	land.add_theme_color_override("font_color", UiKit.AMBER.lightened(0.3))
	if _focus == null:
		_focus = land
	row.add_child(land)
	v.add_child(row)
	h.add_child(v)
	card.add_child(h)
	return card


const FACT_ICONS := {"water_distance_m": "stat.water", "flatness": "ui.icon_flat", "shelter": "ui.icon_shelter", "vent": "stat.geothermal",
	"exposure": "ui.icon_wind", "landing_quality": "ui.icon_target"}


## Known facts as glyph + value/meter, unknown ones as dim locked glyphs (their
## names in the tooltip), so the card shows at a glance what is still open.
func _fact_row(facts: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 4)
	for f: String in FACT_LABELS.keys():
		var item := UiKit.hbox(4)
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		var name_t := Loc.t(str(FACT_LABELS[f]))
		if facts.has(f):
			var val: Variant = facts[f].get("value")
			var good := _fact_good(f, val)
			var col := UiKit.OK.lightened(0.2) if good > 0.6 else (UiKit.WARN if good > 0.3 else UiKit.DANGER.lightened(0.15))
			item.add_child(IconBadge.make(str(FACT_ICONS.get(f, "ui.icon_info")), 26, col, false, "◆"))
			if val is float and f != "water_distance_m":
				item.add_child(Holo.meter(float(val), 5, col, 34))
			var l := UiKit.label(_fact_text(f, val), 13, col.lightened(0.2))
			item.add_child(l)
			item.tooltip_text = "%s: %s" % [name_t, _fact_text(f, val)]
		else:
			var b := IconBadge.make(str(FACT_ICONS.get(f, "ui.icon_info")), 24, UiKit.MUTED, false, "?")
			b.locked = true
			item.add_child(b)
			item.tooltip_text = "%s: %s" % [name_t, Loc.t("unknown")]
			item.modulate.a = 0.7
		flow.add_child(item)
	return flow


## 0..1: how good the fact is for a colony (colour of its meter; text says the value).
static func _fact_good(f: String, v: Variant) -> float:
	match f:
		"water_distance_m":
			return clampf(1.0 - float(v) / 150.0, 0.0, 1.0)
		"vent":
			return 1.0 if v else 0.35
		"exposure":
			return 1.0 - float(v)
	return float(v) if v is float or v is int else 0.5


func _landing_preview(pid: String, sid: String) -> void:
	var gs: GameState = GameSession.state
	var pv := GameSession.sim.landing.preview(gs, sid)
	var site := GameSession.content.site(sid)
	var top := UiKit.hbox(16)
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(440, 0)
	left.add_child(PlanetDiorama.framed(PlanetDiorama.make(pid, "orbit", Vector2i(440, 250)), str(site.get("name", ""))))
	var sh := UiKit.hbox(10)
	sh.add_child(SiteMap.make(pid, sid, DictUtil.get_arr(GameSession.content.planet(pid), "site_templates"), 120))
	var facts := UiKit.vbox(4)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_child(UiKit.section(Loc.t("Site"), "ui.icon_target"))
	facts.add_child(_fact_row(pv.get("site_facts", {})))
	sh.add_child(facts)
	left.add_child(sh)
	top.add_child(left)
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(620, 0)
	var hd := UiKit.label(Loc.t("Landing: %s, %s") % [GameSession.content.planet(pid).get("name"), site.get("name")], 24, Color.WHITE)
	hd.add_theme_font_override("font", Holo.name_font())
	v.add_child(hd)
	v.add_child(Holo.bullet("ui.icon_critical", Loc.t("Once the Ark lands, it becomes the colony's base. It cannot lift off again."), UiKit.WARN, "▲", 16, UiKit.WARN.lightened(0.25)))
	v.add_child(Holo.bullet("ui.icon_plus", str(pv.get("advantage", "")), UiKit.OK, "+"))
	v.add_child(Holo.bullet("ui.icon_warning", str(pv.get("price", "")), UiKit.WARN, "−"))
	v.add_child(UiKit.section(Loc.t("Known risks"), "ui.icon_warning"))
	for r: Variant in pv.get("known_risks", []):
		v.add_child(Holo.bullet("ui.icon_warning", str(r), UiKit.WARN, "▲", 14))
	if (pv.get("known_risks", []) as Array).is_empty():
		v.add_child(Holo.bullet("ui.icon_info", Loc.t("No mapped risks — that doesn't mean there are none."), UiKit.MUTED, "◆", 14, UiKit.MUTED))
	if not (pv.get("unknowns", []) as Array).is_empty():
		v.add_child(UiKit.section(Loc.t("Unknown"), "ui.icon_unknown"))
		for u: Variant in pv.get("unknowns", []):
			v.add_child(Holo.bullet("ui.icon_locked", str(u), UiKit.MUTED, "✕", 14, UiKit.MUTED.lightened(0.1)))
	var inv: Dictionary = pv.get("start_inventory", {})
	v.add_child(UiKit.section(Loc.t("Starting stock and energy"), "ui.icon_building"))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 16)
	for it: Array in [["ui.icon_alloy", Loc.t("Building material"), inv.get("alloy", 0), UiKit.PETROL.lightened(0.4)],
			["ui.icon_components", Loc.t("Components"), inv.get("components", 0), UiKit.PETROL.lightened(0.4)],
			["ui.icon_water", Loc.t("Water (person-days)"), inv.get("water", 0), UiKit.WATER],
			["ui.icon_food", Loc.t("Food (person-days)"), inv.get("food", 0), UiKit.FOOD]]:
		g.add_child(Holo.readout(str(it[0]), str(it[1]), CountUpLabel.make(float(it[2]), 22, Color.WHITE), it[3]))
	v.add_child(g)
	v.add_child(Holo.bullet("ui.icon_power", str(pv.get("energy_plan", "")), UiKit.AMBER, "◆", 14))
	for reason: Variant in pv.get("reasons", []):
		v.add_child(Holo.bullet("ui.icon_critical", str(reason), UiKit.DANGER, "■", 15, UiKit.DANGER.lightened(0.3)))
	var row := UiKit.hbox(10)
	var back := UiKit.button(Loc.t("Back — continue the voyage"), func() -> void:
		_landing_site = ""
		refresh())
	UiKit.with_icon(back, "ui.icon_back", 20)
	back.custom_minimum_size = Vector2(0, 54)
	_focus = back  # never the irreversible button
	row.add_child(back)
	var commit := GlowButton.make(Loc.t("Confirm landing (final)"), "ui.icon_lander", "danger", func() -> void:
		var r := GameSession.cmd_commit_landing(sid, _landing_txn)
		if r.ok:
			close()
			landing_committed.emit(sid))
	commit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commit.disabled = not pv["ok"]
	row.add_child(commit)
	v.add_child(row)
	top.add_child(v)
	body.add_child(top)


func close() -> void:
	_landing_site = ""
	super()


func focus_target() -> Control:
	return _focus if is_instance_valid(_focus) else super()


## A Control never shrinks on its own once it has grown: once the new page is
## laid out (wrapped labels know their width, so their height is right), drop
## to the content's height and re-centre.
func _shrink_to_content() -> void:
	if not is_inside_tree():
		return
	for i: int in 2:
		await get_tree().process_frame
	if not is_instance_valid(panel) or not visible:
		return
	panel.size = Vector2(panel.size.x, 0.0)  # clamped up to the combined minimum
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	fit()


const FACT_LABELS := {"water_distance_m": "water", "flatness": "flatness", "shelter": "shelter", "vent": "heat source",
	"exposure": "exposure", "landing_quality": "landing quality"}


static func _fact_text(f: String, v: Variant) -> String:
	if f == "water_distance_m":
		return "%d m" % int(v)
	if f == "vent":
		return Loc.t("yes") if v else Loc.t("no")
	if v is float or v is int:
		var x := float(v)
		return Loc.t("high") if x >= 0.7 else (Loc.t("medium") if x >= 0.4 else Loc.t("low"))
	return str(v)


## Living thumbnail of a landing site (D-055): the biome map's ground colour
## in a round scope, every site of the planet as a dot, this one with its
## districts and a turning lock-on reticle, a radar sweep over it. Code-drawn.
class SiteMap extends Control:
	var site_id := ""
	var sites: Array = []  # [{id, center: Vector2 (-1..1)}]
	var ground := Color("4a5a50")
	var rock := Color("2a302c")
	var districts: Array = []  # [Vector2 centre (-1..1), radius (0..1)]
	var _t := 0.0

	static func make(pid: String, sid: String, all_sites: Array, px: int) -> SiteMap:
		var m := SiteMap.new()
		m.site_id = sid
		m.custom_minimum_size = Vector2(px, px)
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p := GameSession.content.planet(pid)
		var bm: Dictionary = GameSession.content.biome_maps.get(str(p.get("biome_id", "")), {})
		var mp: Dictionary = DictUtil.get_dict(bm, "map")
		var half := maxf(1.0, float(mp.get("size_m", 260.0)) * 0.5)
		m.ground = Color(str(mp.get("base_color", "#4a5a50")))
		m.rock = Color(str(mp.get("rock_color", "#2a302c")))
		for s: Variant in all_sites:
			var sd := GameSession.content.site(str(s))
			var c: Array = DictUtil.get_arr(sd, "center")
			if c.size() >= 2:
				m.sites.append({"id": str(s), "center": Vector2(float(c[0]), float(c[1])) / half})
			if str(s) == sid:
				for key: String in ["landing", "resource", "living"]:
					var dd := DictUtil.get_dict(DictUtil.get_dict(sd, "districts"), key)
					var dc: Array = DictUtil.get_arr(dd, "center")
					if dc.size() >= 2 and c.size() >= 2:
						m.districts.append([(Vector2(float(c[0]), float(c[1])) + Vector2(float(dc[0]), float(dc[1]))) / half, float(dd.get("radius", 20.0)) / half])
		return m

	func _ready() -> void:
		set_process(not HoloAnim.calm())

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r, Color(ground.darkened(0.55), 1.0))
		# A little terrain: rings of rock tone.
		for i: int in 5:
			draw_arc(c + Vector2(sin(i * 2.1), cos(i * 1.7)) * r * 0.25, r * (0.25 + i * 0.13), 0.0, TAU, 32, Color(rock.lightened(0.15), 0.35), 2.0, true)
		draw_circle(c, r, Color(ground, 0.18))
		# Grid.
		for k: int in 3:
			draw_arc(c, r * (k + 1) / 3.0, 0.0, TAU, 40, Color(0.5, 0.95, 1.0, 0.18), 1.0, true)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.5, 0.95, 1.0, 0.15), 1.0)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.5, 0.95, 1.0, 0.15), 1.0)
		# Sweep.
		var a := _t * 1.2
		for i: int in 10:
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - 0.07 * (i + 1)) * r, c + Vector2.from_angle(a - 0.07 * i) * r]), Color(0.4, 1.0, 0.9, 0.12 * (1.0 - i / 10.0)))
		var me := Vector2.ZERO
		for s: Dictionary in sites:
			var p: Vector2 = c + (s["center"] as Vector2) * r * 0.9
			if str(s["id"]) == site_id:
				me = p
			else:
				draw_circle(p, 3.0, Color(0.7, 0.9, 1.0, 0.6))
		for d: Array in districts:
			var dp: Vector2 = c + (d[0] as Vector2) * r * 0.9
			draw_arc(dp, maxf(3.0, float(d[1]) * r * 0.9), 0.0, TAU, 20, Color(UiKit.AMBER, 0.45), 1.0, true)
		if me != Vector2.ZERO:
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(me, 4.0, UiKit.AMBER.lightened(0.3))
			draw_arc(me, 9.0 + pulse * 3.0, 0.0, TAU, 24, Color(UiKit.AMBER, 0.7 - pulse * 0.4), 1.5, true)
			for i: int in 4:
				var a0 := _t * 0.8 + TAU * i / 4.0
				draw_arc(me, 15.0, a0, a0 + 0.8, 8, Color(UiKit.AMBER, 0.9), 2.0, true)
		draw_arc(c, r, 0.0, TAU, 64, Color(0.5, 0.95, 1.0, 0.7), 1.5, true)
		for i: int in 24:
			var ang := TAU * i / 24.0
			draw_line(c + Vector2.from_angle(ang) * r, c + Vector2.from_angle(ang) * (r - (5.0 if i % 6 == 0 else 2.5)), Color(0.5, 0.95, 1.0, 0.6), 1.0)
