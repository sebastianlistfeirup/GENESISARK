class_name ArkPanels
extends RefCounted
## Small ship-room panels: embryo bank status and the workshop.
## Holo-console look (D-055): the embryo bank is a living readout (a ring of
## glowing vials turning around a DNA helix, the 50,000 counting up, the
## ledger as progress rings, four cooling loops pulsing); the workshop shows
## hull and scrubbers as gauges, components and fuel as counters with their
## part renders, and the repairs as icon buttons.


## A stat card: glyph + muted caption over a big display-font value (+ optional bar).
static func stat_card(icon_slot: String, caption: String, value: String, color: Color = UiKit.TEXT, frac: float = -1.0, bar_color: Color = UiKit.PETROL) -> PanelContainer:
	var p := UiKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(2)
	var top := UiKit.hbox(6)
	var ic := UiKit.icon_rect(icon_slot, 16, UiKit.PETROL.lightened(0.45))
	if ic:
		top.add_child(ic)
	top.add_child(UiKit.label(caption.to_upper(), 13, UiKit.MUTED))
	v.add_child(top)
	var val := UiKit.label(value, 30, color)
	val.add_theme_font_override("font", UiKit.display_font())
	v.add_child(val)
	if frac >= 0.0:
		v.add_child(UiKit.bar(frac, 1.0, bar_color, 8))
	p.add_child(v)
	return p


## A counter card: a part render (Synty prop icon, untinted) or glyph, the
## number counting up in the display face, its caption.
static func counter(prop_slot: String, glyph: String, caption: String, value: float, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.85)
	sb.border_color = Color(col, 0.5)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HoloAnim.hover_lift(p, 0.015, 0.1)
	var h := UiKit.hbox(10)
	var art := UiKit.icon_rect(prop_slot, 64, Color.WHITE)
	if art:
		h.add_child(art)
	else:
		h.add_child(IconBadge.make(glyph, 52, col, true, "◆"))
	var v := UiKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := UiKit.label(caption.to_upper(), 12, UiKit.MUTED.lightened(0.1))
	c.add_theme_font_override("font", UiKit.display_variant(2))
	v.add_child(c)
	var n := CountUpLabel.make(value, 40, Color.WHITE)
	n.add_theme_font_override("font", UiKit.display_variant(2))
	v.add_child(n)
	h.add_child(v)
	p.add_child(h)
	return p


class EmbryoBankPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(980, 640))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header(Loc.t("The embryo bank"), Loc.t("Storage status, redundancy and the later care plan."), "ui.icon_embryo")
		var hero := UiKit.hbox(18)
		hero.add_child(VialRing.make(280))
		var right := UiKit.vbox(6)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		var cap := UiKit.label(Loc.t("Embryos in the bank").to_upper(), 14, Color(UiKit.AMBER, 0.95))
		cap.add_theme_font_override("font", UiKit.display_variant(3))
		right.add_child(cap)
		var big := CountUpLabel.make(gs.ark.embryo_sum(), 92, Color.WHITE)
		big.seconds = 1.6
		big.add_theme_font_override("font", UiKit.display_variant(4))
		big.add_theme_color_override("font_shadow_color", Color(UiKit.PETROL.lightened(0.2), 0.55))
		big.add_theme_constant_override("shadow_outline_size", 22)
		right.add_child(big)
		right.add_child(UiKit.label(Loc.t("The number is not a score. It is everyone who may yet become someone."), 18, UiKit.MUTED.lightened(0.15), true))
		right.add_child(Holo.chip(Loc.t("Stasis stable · emergency power"), UiKit.OK.lightened(0.15), "ui.icon_ok", 12))
		hero.add_child(right)
		body.add_child(hero)
		# The ledger as rings: viable + incubating + born + lost = 50,000.
		var l := gs.ark.ledger()
		var total := float(maxi(1, gs.ark.embryo_sum()))
		var row := UiKit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for r: Array in [[Loc.t("Viable in cryo"), l["viable"], Color("5fe0c8")], [Loc.t("In incubation"), l["incubating"], UiKit.AMBER],
				[Loc.t("Born"), l["born"], UiKit.OK.lightened(0.15)], [Loc.t("Lost"), l["lost"], UiKit.DANGER if int(l["lost"]) > 0 else UiKit.MUTED]]:
			var g := ProgressRing.make(float(r[1]) / total, "", str(r[0]), r[2], 132, float(r[1]))
			g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(g)
		body.add_child(row)
		body.add_child(UiKit.section(Loc.t("Redundancy"), "ui.icon_cooling"))
		var loops := UiKit.hbox(8)
		for i: int in 4:
			loops.add_child(CoolingLoop.make(i))
		body.add_child(loops)
		body.add_child(UiKit.label(Loc.t("Redundancy: four independent cooling loops, all stable on emergency power. Incubation requires a care center, stable supply and +5 kW on a new world."), 15, UiKit.MUTED, true))


class WorkshopPanel extends OverlayPanel:
	var _focus: Control

	func _init() -> void:
		super(Vector2(940, 560))

	func focus_target() -> Control:
		return _focus if is_instance_valid(_focus) else super()

	func refresh() -> void:
		UiKit.clear(body)
		_focus = null
		regrab_focus.call_deferred()
		var gs: GameState = GameSession.state
		header(Loc.t("The workshop"), Loc.t("Robots, components and repairs."), "ui.icon_repair")
		var top := UiKit.hbox(14)
		var hc := UiKit.WARN if gs.ark.integrity < 50.0 else UiKit.OK.lightened(0.1)
		top.add_child(ProgressRing.make(gs.ark.integrity / 100.0, "", Loc.t("Hull"), hc, 150, gs.ark.integrity, "%"))
		top.add_child(ProgressRing.make(gs.ark.oxygen / 100.0, "", Loc.t("Oxygen"), UiKit.WATER.lightened(0.15), 150, gs.ark.oxygen, "%"))
		var counters := UiKit.vbox(10)
		counters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		counters.alignment = BoxContainer.ALIGNMENT_CENTER
		counters.add_child(ArkPanels.counter("prop.battery", "ui.icon_components", Loc.t("Components"), gs.ark.components, UiKit.PETROL.lightened(0.3)))
		counters.add_child(ArkPanels.counter("prop.fuel_cell", "ui.icon_fuel", Loc.t("Fuel"), int(gs.ark.fuel), UiKit.AMBER))
		top.add_child(counters)
		body.add_child(top)
		body.add_child(Holo.bullet("ui.icon_info", Loc.t("Every component you use here will be missing later in the colony. Probes cost 3, a drone reserve 2. Whatever remains at landing becomes the colony's starting stock."), UiKit.PETROL.lightened(0.4), "◆", 15, UiKit.MUTED.lightened(0.1)))
		body.add_child(UiKit.section(Loc.t("Repair the hull"), "ui.icon_hull"))
		var row := UiKit.hbox(10)
		for n: int in [1, 3, 5]:
			var b := UiKit.button(Loc.t("Repair the hull: %d comp. → +%d%%") % [n, n * 4], func() -> void:
				GameSession.cmd_repair(n)
				refresh())
			b.disabled = gs.ark.components < n or gs.ark.integrity >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			b.custom_minimum_size = Vector2(0, 46)
			UiKit.with_icon(b, "ui.icon_repair", 20)
			row.add_child(b)
			if _focus == null and not b.disabled:
				_focus = b
		body.add_child(row)
		body.add_child(UiKit.section(Loc.t("Repair scrubbers"), "ui.icon_suit"))
		var orow := UiKit.hbox(10)
		var per := float(GameSession.content.bal("oxygen", {}).get("repair_per_component", 4.0))
		for n: int in [1, 3, 5]:
			var ob := UiKit.button(Loc.t("Repair scrubbers: %d comp. → +%d%%") % [n, int(n * per)], func() -> void:
				GameSession.cmd_repair_oxygen(n)
				refresh())
			ob.disabled = gs.ark.components < n or gs.ark.oxygen >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			ob.custom_minimum_size = Vector2(0, 46)
			UiKit.with_icon(ob, "ui.icon_suit", 20)
			orow.add_child(ob)
		body.add_child(orow)
		if gs.ark.integrity < 50.0:
			body.add_child(Holo.bullet("ui.icon_warning", Loc.t("Below 50% hull, the Ark gives only 60% emergency power after landing."), UiKit.WARN, "▲", 16, UiKit.WARN.lightened(0.2)))


## The embryo bank's living emblem: holo rings turning, a ring of glowing
## vials (fill levels breathing) around a slowly twisting DNA helix and the
## test-tube render. Code-drawn apart from the optional Synty sprites.
class VialRing extends Control:
	var _t := 0.0
	var _tube: Texture2D
	var _rings: HoloRing

	static func make(px: int) -> VialRing:
		var v := VialRing.new()
		v.custom_minimum_size = Vector2(px, px)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return v

	func _ready() -> void:
		_tube = SyntySkin.icon("prop.embryo_tube", 160)
		_rings = HoloRing.new()
		_rings.custom_minimum_size = custom_minimum_size
		_rings.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rings.add_layer("Ring_Large_06", 1.0, 0.06, Color(0.5, 1.0, 0.95, 0.35))
		_rings.add_layer("Ring_Medium_11", 0.62, -0.18, Color(0.5, 1.0, 0.95, 0.3))
		_rings.add_layer("Ring_Small_04", 0.4, 0.35, Color(1.0, 0.75, 0.35, 0.3))
		add_child(_rings)
		move_child(_rings, 0)
		set_process(not HoloAnim.calm())

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		# Soft core glow.
		for i: int in 5:
			draw_circle(c, r * (0.42 - i * 0.06), Color(0.3, 0.95, 0.9, 0.035))
		# Vials around the ring.
		var n := 20
		var rot := _t * 0.12
		for i: int in n:
			var a := rot + TAU * i / n
			var p := c + Vector2.from_angle(a) * r * 0.8
			var lvl := 0.55 + 0.35 * sin(_t * 1.4 + i * 0.9)
			draw_set_transform(p, a + PI * 0.5, Vector2.ONE)
			var vw := 8.0
			var vh := 20.0
			draw_rect(Rect2(-vw * 0.5, -vh * 0.5, vw, vh), Color(0.03, 0.08, 0.1, 0.9), true)
			draw_rect(Rect2(-vw * 0.5 + 1.0, vh * 0.5 - 1.0 - (vh - 2.0) * lvl, vw - 2.0, (vh - 2.0) * lvl), Color(0.35, 1.0, 0.9, 0.85), true)
			draw_rect(Rect2(-vw * 0.5, -vh * 0.5, vw, vh), Color(0.6, 1.0, 1.0, 0.7), false, 1.0)
			draw_rect(Rect2(-vw * 0.5 - 1.0, -vh * 0.5 - 3.0, vw + 2.0, 3.0), Color(0.8, 0.9, 0.95, 0.9), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# DNA helix: two strands twisting, rungs between them.
		var hh := r * 0.85
		var steps := 28
		for i: int in steps:
			var f := float(i) / (steps - 1)
			var y := c.y - hh * 0.5 + f * hh
			var ph := f * TAU * 1.6 + _t * 1.3
			var x1 := c.x + sin(ph) * r * 0.18
			var x2 := c.x + sin(ph + PI) * r * 0.18
			var front := cos(ph) > 0.0
			if i % 2 == 0:
				draw_line(Vector2(x1, y), Vector2(x2, y), Color(0.6, 1.0, 0.95, 0.25), 1.5)
			draw_circle(Vector2(x1, y), 3.2 if front else 2.2, Color(0.4, 1.0, 0.9, 0.95 if front else 0.45))
			draw_circle(Vector2(x2, y), 2.2 if front else 3.2, Color(1.0, 0.75, 0.4, 0.45 if front else 0.95))
		if _tube:
			var ts := r * 0.5
			draw_texture_rect(_tube, Rect2(c + Vector2(r * 0.42, r * 0.28) - Vector2.ONE * ts * 0.5, Vector2.ONE * ts), false, Color(1, 1, 1, 0.95))


## One cooling loop: snowflake glyph, its name, STABLE, and coolant flowing
## through a little pipe (still with reduced motion).
class CoolingLoop extends PanelContainer:
	var index := 0
	var _pipe: Control
	var _t := 0.0

	static func make(i: int) -> CoolingLoop:
		var l := CoolingLoop.new()
		l.index = i
		return l

	func _ready() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.05, 0.07, 0.85)
		sb.border_color = Color(UiKit.OK, 0.45)
		sb.set_border_width_all(1)
		sb.border_width_left = 3
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_left = 10
		sb.set_content_margin_all(8)
		add_theme_stylebox_override("panel", sb)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UiKit.vbox(4)
		var h := UiKit.hbox(6)
		h.add_child(IconBadge.make("ui.icon_cooling", 26, Color("7fe8e0"), false, "❄"))
		var n := UiKit.label(Loc.t("Loop %d") % (index + 1), 14, UiKit.TEXT)
		n.add_theme_font_override("font", UiKit.display_variant(1))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(Holo.chip(Loc.t("Stable"), UiKit.OK.lightened(0.15), "", 10))
		v.add_child(h)
		_pipe = Control.new()
		_pipe.custom_minimum_size = Vector2(0, 8)
		_pipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pipe.draw.connect(_draw_pipe)
		v.add_child(_pipe)
		add_child(v)
		_t = index * 0.37
		set_process(not HoloAnim.calm())

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			_pipe.queue_redraw()

	func _draw_pipe() -> void:
		var w := _pipe.size.x
		var h := _pipe.size.y
		_pipe.draw_rect(Rect2(0, 1, w, h - 2), Color(0.02, 0.08, 0.1, 1.0), true)
		var x := fmod(_t * 40.0, 16.0) - 16.0
		while x < w:
			_pipe.draw_rect(Rect2(maxf(0.0, x), 2, minf(8.0, w - maxf(0.0, x)), h - 4), Color(0.4, 1.0, 0.9, 0.7), true)
			x += 16.0
		_pipe.draw_rect(Rect2(0, 1, w, h - 2), Color(UiKit.OK, 0.5), false, 1.0)
