class_name StarMapPanel
extends OverlayPanel
## Bridge star map (bible p.6-8): compare candidates, send probes, choose a
## route with all costs and the minimum reserve shown BEFORE committing.
## Emits travel_committed so the scene can play the approach.
## Holo-console look (D-055): the living map on the left; on the right the
## selected world large and turning under HUD rings with its name, type tags,
## pros/cons as icon bullets, KNOWLEDGE as stat tiles with range bars, the
## route as icon readouts and NAV's brief, and the actions pinned at the
## bottom (Travel = the glowing primary button with its fuel cost).
## The Comparison tab shows the worlds as side-by-side cards with the same
## bars; the best known/estimated value of each row is marked.

signal travel_committed(destination: String)

var tabs: TabContainer
var map_view: StarMapView
var detail: VBoxContainer
var compare_box: VBoxContainer
var preview: PlanetDiorama  # the selected world, live
var _preview_frame: Control
var _hero_name: Label
var _hero_tag: Label
var _hero_line: Label
var _hero_tags: HBoxContainer
var _actions: VBoxContainer
var _pending_txn := ""
var _confirming := false


func _init() -> void:
	super(Vector2(1340, 860))


func refresh() -> void:
	UiKit.clear(body)
	var gs: GameState = GameSession.state
	var here := str(GameSession.content.locations.get(gs.campaign.location_id, {}).get("name", ""))
	header(Loc.t("Star map"), Loc.t("Position: %s") % here, "ui.icon_planet", [
		["ui.icon_fuel", Loc.t("Fuel %d") % int(gs.ark.fuel), UiKit.AMBER.lightened(0.1)],
		["ui.icon_hull", Loc.t("Hull %d%%") % int(gs.ark.integrity), UiKit.WARN if gs.ark.integrity < 50.0 else UiKit.PETROL.lightened(0.4)],
		["ui.icon_components", Loc.t("Components %d") % gs.ark.components, UiKit.PETROL.lightened(0.4)]])
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1300, 740)
	body.add_child(tabs)
	var map_tab := UiKit.hbox(14)
	map_tab.name = Loc.t("Voyage")
	map_view = StarMapView.new()
	map_view.planet_selected.connect(func(loc: String) -> void:
		_confirming = false
		_show_detail(loc))
	map_tab.add_child(map_view)
	# Right column: the selected world live (D-046) under its name, the facts
	# scrolling below, the actions pinned at the bottom.
	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_build_hero())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail = UiKit.vbox(10)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)
	right.add_child(scroll)
	_actions = UiKit.vbox(4)
	right.add_child(_actions)
	map_tab.add_child(right)
	tabs.add_child(map_tab)
	var cmp_scroll := ScrollContainer.new()
	cmp_scroll.name = Loc.t("Comparison")
	compare_box = UiKit.vbox(8)
	compare_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmp_scroll.add_child(compare_box)
	tabs.add_child(cmp_scroll)
	_build_compare()
	if map_view.selected.is_empty():
		_preview_frame.visible = false
		detail.add_child(Holo.bullet("ui.icon_target", Loc.t("Choose a world on the map."), UiKit.AMBER, "◆", 18))
		detail.add_child(UiKit.label(Loc.t("Known values and uncertainties are shown separately. A probe costs 3 components and narrows the archive's estimate. Traveling costs fuel and wears on the hull."), 16, UiKit.MUTED, true))
	else:
		_show_detail(map_view.selected)


## The hero view: the world large and turning, HUD rings over it, its name,
## tagline and type tags on the left.
func _build_hero() -> Control:
	preview = PlanetDiorama.make(map_view.selected if not map_view.selected.is_empty() else "viridia", "hero", Vector2i(600, 250))
	_preview_frame = PlanetDiorama.framed(preview, "")
	var over := Control.new()
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A dark veil from the left keeps the name and text readable over the nebula.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.0, 0.01, 0.03, 0.82), Color(0.0, 0.01, 0.03, 0.45), Color(0.0, 0.01, 0.03, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 4
	var veil := TextureRect.new()
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.anchor_bottom = 1.0
	veil.anchor_right = 0.62
	over.add_child(veil)
	var rings := HoloRing.new()
	rings.custom_minimum_size = Vector2(250, 250)
	rings.anchor_left = 0.72
	rings.anchor_right = 0.72
	rings.anchor_top = 0.5
	rings.anchor_bottom = 0.5
	rings.offset_left = -125
	rings.offset_right = 125
	rings.offset_top = -125
	rings.offset_bottom = 125
	rings.add_layer("Ring_Large_05", 1.04, 0.05, Color(0.55, 1.0, 1.0, 0.42))
	rings.add_layer("Ring_Medium_04", 0.92, -0.12, Color(0.55, 1.0, 1.0, 0.32))
	rings.add_layer("Ring_Small_06", 1.12, 0.22, Color(1.0, 0.75, 0.35, 0.35))
	over.add_child(rings)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16 if side == "left" else 14)
	var v := UiKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_tag = UiKit.label("", 12, Color(UiKit.AMBER, 0.95))
	_hero_tag.add_theme_font_override("font", UiKit.display_variant(3))
	_hero_tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hero_tag.add_theme_constant_override("shadow_outline_size", 5)
	v.add_child(_hero_tag)
	_hero_name = UiKit.label("", 34, Color.WHITE)
	_hero_name.add_theme_font_override("font", Holo.name_font())
	_hero_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hero_name.add_theme_constant_override("shadow_outline_size", 8)
	v.add_child(_hero_name)
	_hero_line = UiKit.label("", 14, Color("cfeff0"))
	_hero_line.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hero_line.add_theme_constant_override("shadow_outline_size", 6)
	_hero_line.custom_minimum_size = Vector2(290, 0)
	_hero_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hero_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hero_line)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	_hero_tags = UiKit.hbox(6)
	v.add_child(_hero_tags)
	m.add_child(v)
	over.add_child(m)
	_preview_frame.add_child(over)
	return _preview_frame


func _show_detail(loc: String) -> void:
	UiKit.clear(detail)
	UiKit.clear(_actions)
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var pid := str(content.locations.get(loc, {}).get("planet_id", ""))
	var p := content.planet(pid)
	if map_view and map_view.selected != loc:
		map_view.select(loc, false)
	if preview != null and not pid.is_empty():
		preview.set_planet(pid)
		_preview_frame.visible = true
	_fill_hero(loc, pid, p)
	detail.add_child(Holo.bullet("ui.icon_plus", str(p.get("advantage", "")), UiKit.OK, "+"))
	detail.add_child(Holo.bullet("ui.icon_warning", str(p.get("price", "")), UiKit.WARN, "−"))
	var cmp := GameSession.sim.survey.comparison(gs, pid)
	var kh := UiKit.hbox(8)
	var ks := UiKit.section(Loc.t("Knowledge"), "ui.icon_probe")
	ks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kh.add_child(ks)
	kh.add_child(Holo.chip(Loc.t("%d of %d known") % [int(cmp["known_count"]), int(cmp["total"])], Color("5fe0c8"), "ui.icon_ok", 11))
	detail.add_child(kh)
	detail.add_child(knowledge_grid(pid))
	detail.add_child(UiKit.section(Loc.t("Route"), "ui.icon_nav"))
	var q := GameSession.sim.travel.quote(gs, loc)
	if q.has("fuel"):
		detail.add_child(_route_readouts(q))
	var brief := GameSession.sim.nav.route_brief(gs, q)
	if not brief.is_empty():
		detail.add_child(nav_block(brief))
	for reason: Variant in q.get("reasons", []):
		detail.add_child(Holo.bullet("ui.icon_critical", str(reason), UiKit.DANGER, "■", 16, UiKit.DANGER.lightened(0.3)))
	for reason: Variant in q.get("risk_reasons", []):
		detail.add_child(Holo.bullet("ui.icon_warning", str(reason), UiKit.WARN, "▲", 16, UiKit.WARN.lightened(0.2)))
	HoloAnim.stagger(detail, 0.035, 0.0, 0.18)
	# Actions, pinned under the scroll: the probe and the big Travel button.
	var row := UiKit.hbox(10)
	var k := gs.knowledge_of(pid)
	var probe := UiKit.button(Loc.t("Send remote probe (3 components)"), func() -> void:
		if GameSession.cmd_probe(pid, "").ok:
			_show_detail(loc)
			_build_compare(),
		Loc.t("Narrows the archive's estimate of %s without traveling.") % p.get("name"))
	UiKit.with_icon(probe, "ui.icon_probe", 22)
	probe.custom_minimum_size = Vector2(0, 54)
	probe.disabled = k.level_reached.has("orbital") or gs.ark.components < 3 or gs.campaign.phase != CampaignState.PHASE_VOYAGE
	row.add_child(probe)
	var risky := bool(q.get("risky", false))
	var travel := GlowButton.make(Loc.t("Confirm risky voyage") if _confirming else Loc.t("Travel here"), "ui.icon_ship",
		"danger" if _confirming else ("primary" if risky else "go"), func() -> void: _travel(loc, q))
	travel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	travel.disabled = not q["ok"]
	if q.has("fuel"):
		travel.set_cost("−%d" % int(q["fuel"]), "ui.icon_fuel")
	row.add_child(travel)
	_actions.add_child(row)
	if _confirming:
		_actions.add_child(Holo.bullet("ui.icon_warning", Loc.t("Press again to confirm. The voyage cannot be undone."), UiKit.WARN, "▲", 15, UiKit.WARN.lightened(0.2)))


func _fill_hero(loc: String, pid: String, p: Dictionary) -> void:
	var gs: GameState = GameSession.state
	_hero_name.text = str(p.get("name", loc)).to_upper()
	_hero_tag.text = str(p.get("tagline", "")).to_upper()
	_hero_line.text = str(p.get("description", ""))
	UiKit.clear(_hero_tags)
	var pal := Color(str(DictUtil.get_dict(p, "palette").get("nature", "#8fa3ad")))
	var biome := str(p.get("biome_id", "green"))
	var bname := str({"green": Loc.t("Green world"), "desert": Loc.t("Desert world"), "ice": Loc.t("Ice world")}.get(biome, biome))
	_hero_tags.add_child(Holo.tag(bname, "biome." + biome, pal.lightened(0.15)))
	for hz: Variant in DictUtil.get_arr(p, "hazard_ids"):
		var h: Dictionary = GameSession.content.hazards.get(str(hz), {})
		_hero_tags.add_child(Holo.tag(str(h.get("name", hz)), "hazard." + str(hz), UiKit.WARN))
	if loc in gs.campaign.visited:
		_hero_tags.add_child(Holo.tag(Loc.t("Visited"), "ui.icon_flag", UiKit.PETROL.lightened(0.3)))


## Route costs as icon readouts: fuel (with what is left), hull wear, days in
## stasis, and the reserve check as a chip with its symbol.
func _route_readouts(q: Dictionary) -> Control:
	var v := UiKit.vbox(8)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	var fuel := CountUpLabel.make(float(q["fuel"]), 22, UiKit.AMBER.lightened(0.2))
	var fv := UiKit.hbox(6)
	fv.add_child(fuel)
	fv.add_child(UiKit.label(Loc.t("→ %d left") % int(q["fuel_after"]), 13, UiKit.MUTED))
	g.add_child(Holo.readout("ui.icon_fuel", Loc.t("Fuel"), fv, UiKit.AMBER))
	var hull := CountUpLabel.make(float(q["integrity"]), 22, Color.WHITE)
	hull.prefix = "−"
	hull.suffix = "%"
	g.add_child(Holo.readout("ui.icon_hull", Loc.t("Hull"), hull))
	var days := CountUpLabel.make(float(q["days"]), 22, Color.WHITE)
	days.suffix = " " + Loc.t("days")
	g.add_child(Holo.readout("ui.icon_time", Loc.t("In stasis"), days))
	v.add_child(g)
	var ok := bool(q["reserve_ok"])
	var txt := (Loc.t("Reserve to nearest alternative: ok (%d required)") if ok else Loc.t("Reserve to nearest alternative: too low (%d required)")) % int(q["reserve_needed"])
	v.add_child(Holo.chip(txt, UiKit.OK.lightened(0.15) if ok else UiKit.WARN, "ui.icon_ok" if ok else "ui.icon_warning", 12))
	return v


## NAV's assessment of the route: a terminal block with the comms glyph, one
## line per item with its status symbol.
static func nav_block(items: Array) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.04, 0.05, 0.92)
	sb.border_color = Color(UiKit.PETROL.lightened(0.2), 0.8)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var h := UiKit.hbox(10)
	var badge := IconBadge.make("ui.icon_nav", 30, Color("7fd6d0"), true, "◆")
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(badge)
	var lines: Array = []
	for it: Dictionary in items:
		var col: String = {"critical": "#d25b4c", "warning": "#e8a33d"}.get(str(it.get("severity", "")), "#9fb4bd")
		var sev := str(it.get("severity", ""))
		lines.append("[color=%s]%s%s[/color]" % [col, (UiKit.status_icon(sev) + " ") if sev in ["critical", "warning"] else "› ", str(it["text"])])
	var r := UiKit.rich("[color=#7fd6d0][b]NAV[/b][/color]\n" + "\n".join(lines))
	r.custom_minimum_size = Vector2(0, 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(r)
	p.add_child(h)
	return p


## Known / estimated / unknown, each with its source (bible p.7, p.13), as
## stat tiles with range bars in two columns.
static func knowledge_grid(pid: String, columns: int = 2, compact: bool = false) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cmp := GameSession.sim.survey.comparison(GameSession.state, pid)
	var rows: Dictionary = cmp["rows"]
	for prop: String in SurveyService.PROPERTY_LABELS.keys():
		if not rows.has(prop):
			continue
		var t := StatTile.for_property(pid, prop, compact)
		t.custom_minimum_size = Vector2(260 if not compact else 240, 0)
		g.add_child(t)
	return g


func _build_compare() -> void:
	if compare_box == null:
		return
	UiKit.clear(compare_box)
	var content := GameSession.content
	var gs: GameState = GameSession.state
	compare_box.add_child(Holo.bullet("ui.icon_info", Loc.t("Known values, estimates and gaps side by side. The best known or estimated value in each row is marked. No world is best at everything."), UiKit.PETROL.lightened(0.4), "◆", 15, UiKit.MUTED.lightened(0.1)))
	var props: Array = []
	for prop: String in SurveyService.PROPERTY_LABELS.keys():
		props.append(prop)
	var pids: Array = content.planet_ids_sorted()
	# Best score per row (known or estimated only).
	var best: Dictionary = {}
	for prop: String in props:
		var top := -INF
		var who := ""
		for pid: String in pids:
			var s := StatTile.score(prop, gs.knowledge_of(pid).observations.get(prop, {"status": "unknown"}))
			if not is_nan(s) and s > top:
				top = s
				who = pid
		best[prop] = who
	var loc_of: Dictionary = {}
	for loc: String in content.locations.keys():
		loc_of[str(content.locations[loc].get("planet_id", ""))] = loc
	var row := UiKit.hbox(8)
	# Legend column: the stat glyphs and names, aligned with the card rows.
	var legend := UiKit.vbox(0)
	legend.custom_minimum_size = Vector2(150, 0)
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, CARD_HEAD)
	legend.add_child(head)
	for prop: String in props:
		var lh := UiKit.hbox(8)
		lh.custom_minimum_size = Vector2(0, CELL_H)
		lh.add_child(IconBadge.make(StatTile.icon_for(prop, {}), 28, UiKit.PETROL.lightened(0.4), false, "◆"))
		var l := UiKit.label(Loc.t(str(SurveyService.PROPERTY_LABELS[prop])), 14, UiKit.TEXT, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(100, 0)
		lh.add_child(l)
		legend.add_child(lh)
	row.add_child(legend)
	for pid: String in pids:
		row.add_child(_compare_card(pid, props, best, str(loc_of.get(pid, ""))))
	compare_box.add_child(row)


const CARD_HEAD := 124.0
const CELL_H := 56.0


## One world as a card: a still render, its name in its colour, the tagline,
## then one compact cell per property (value + mini bar, best marked) and its
## knowledge count. Click (or Enter on it): show it on the Voyage tab.
func _compare_card(pid: String, props: Array, best: Dictionary, loc: String) -> Control:
	var gs: GameState = GameSession.state
	var p := GameSession.content.planet(pid)
	var pal := Color(str(DictUtil.get_dict(p, "palette").get("nature", "#ffffff")))
	var card := Button.new()  # a button, so mouse, keys and pad can pick it
	card.focus_mode = Control.FOCUS_ALL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(160, 0)
	card.tooltip_text = Loc.t("Show %s on the map") % str(p.get("name", pid))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.85)
	sb.border_color = Color(pal.lightened(0.2), 0.45)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.set_content_margin_all(0)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.border_color = pal.lightened(0.45)
	hov.bg_color = Color(pal.darkened(0.75), 0.92)
	for st: String in ["normal", "disabled"]:
		card.add_theme_stylebox_override(st, sb)
	for st: String in ["hover", "pressed", "hover_pressed"]:
		card.add_theme_stylebox_override(st, hov)
	card.pressed.connect(func() -> void:
		AudioService.ui("ui_click")
		if loc.is_empty() or loc == gs.campaign.location_id:
			return
		tabs.current_tab = 0
		_confirming = false
		map_view.select(loc))
	card.mouse_entered.connect(func() -> void: AudioService.ui("ui_hover"))
	HoloAnim.hover_lift(card, 0.015, 0.12)
	var v := UiKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	var head := UiKit.vbox(2)
	head.custom_minimum_size = Vector2(0, CARD_HEAD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := PlanetDiorama.make(pid, "icon", Vector2i(70, 70))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var n := UiKit.label(str(p.get("name", pid)).to_upper(), 15, pal.lightened(0.35))
	n.add_theme_font_override("font", Holo.name_font())
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(n)
	var tl := UiKit.label(str(p.get("tagline", "")), 11, UiKit.MUTED, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.custom_minimum_size = Vector2(140, 0)
	head.add_child(tl)
	v.add_child(head)
	var cmp := GameSession.sim.survey.comparison(gs, pid)
	for prop: String in props:
		v.add_child(_compare_cell(pid, prop, (cmp["rows"] as Dictionary).get(prop, {}), best.get(prop, "") == pid))
	card.add_child(v)
	card.custom_minimum_size.y = CARD_HEAD + CELL_H * props.size() + 34.0
	var foot := UiKit.hbox(6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.custom_minimum_size = Vector2(0, 30)
	foot.add_child(Holo.chip(Loc.t("%d of %d known") % [int(cmp["known_count"]), int(cmp["total"])], Color("5fe0c8"), "", 10))
	v.add_child(foot)
	return card


func _compare_cell(pid: String, prop: String, row: Dictionary, is_best: bool) -> Control:
	var st := str(row.get("status", "unknown"))
	var col := StatTile.status_color(st)
	var obs: Dictionary = GameSession.state.knowledge_of(pid).observations.get(prop, {"status": "unknown"})
	var cell := PanelContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.custom_minimum_size = Vector2(0, CELL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiKit.AMBER, 0.1) if is_best else Color(0, 0, 0, 0)
	sb.border_color = Color(UiKit.AMBER, 0.55) if is_best else Color(UiKit.PETROL, 0.15)
	sb.border_width_top = 1
	if is_best:
		sb.set_border_width_all(1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var h := UiKit.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_best:
		var star := UiKit.icon_rect("ui.icon_star", 13, UiKit.AMBER)
		h.add_child(star if star else UiKit.label("★", 12, UiKit.AMBER))
	var txt := str(row.get("text", "")) if st != "unknown" else Loc.t("unknown")
	var l := UiKit.label(txt, 12, col.lightened(0.25) if st != "unknown" else UiKit.MUTED)
	l.add_theme_font_override("font", UiKit.display_font() if st == "known" else UiKit.body_font())
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(60, 0)
	l.tooltip_text = txt
	h.add_child(l)
	v.add_child(h)
	var d: Dictionary = StatTile.STATS.get(prop, {})
	if not bool(d.get("category", false)):
		var a := 0.0
		var b := 0.0
		if st == "known":
			a = StatTile.mid_value(obs)
			b = a
		elif st == "estimated":
			a = float(obs.get("min", 0.0))
			b = float(obs.get("max", 0.0))
		var bar := RangeBar.new().setup(float(d.get("lo", 0.0)), float(d.get("hi", 1.0)), st, a, b)
		bar.live = false
		bar.custom_minimum_size = Vector2(0, 11)
		var iz: Array = d.get("ideal", [])
		if iz.size() == 2:
			bar.ideal = Vector2(float(iz[0]), float(iz[1]))
		v.add_child(bar)
	elif st == "unknown":
		var lock := RangeBar.new().setup(0.0, 1.0, "unknown")
		lock.live = false
		lock.custom_minimum_size = Vector2(0, 11)
		v.add_child(lock)
	else:
		var word := UiKit.label(str({"known": Loc.t("known"), "estimated": Loc.t("estimate")}.get(st, "")), 10, Color(col, 0.8))
		word.add_theme_font_override("font", UiKit.display_variant(1))
		v.add_child(word)
	cell.add_child(v)
	return cell


func _travel(loc: String, q: Dictionary) -> void:
	if _pending_txn.is_empty():
		_pending_txn = GameSession.txn("travel")
	if q["risky"] and not _confirming:
		_confirming = true
		_show_detail(loc)
		return
	var r := GameSession.cmd_travel(loc, q["risky"], _pending_txn)
	if r.ok:
		_pending_txn = ""
		_confirming = false
		close()
		travel_committed.emit(loc)
	elif r.code != "duplicate_txn":
		_pending_txn = ""
