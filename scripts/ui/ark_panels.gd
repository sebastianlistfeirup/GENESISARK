class_name ArkPanels
extends RefCounted
## Small ship-room panels: embryo bank status and the workshop.


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


class EmbryoBankPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(880, 600))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header(Loc.t("The embryo bank"), Loc.t("Storage status, redundancy and the later care plan."), "ui.icon_embryo")
		var big := UiKit.label(UiKit.thousands(gs.ark.embryo_sum()), 96, UiKit.TEXT)
		big.add_theme_font_override("font", UiKit.display_variant(4))
		big.add_theme_color_override("font_shadow_color", Color(UiKit.PETROL, 0.45))
		big.add_theme_constant_override("shadow_outline_size", 18)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(big)
		var sub := UiKit.label(Loc.t("The number is not a score. It is everyone who may yet become someone."), 18, UiKit.MUTED, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(sub)
		var l := gs.ark.ledger()
		var total := float(maxi(1, gs.ark.embryo_sum()))
		var row := UiKit.hbox(10)
		for r: Array in [["ui.icon_embryo", Loc.t("Viable in cryo"), l["viable"], UiKit.TEXT], ["ui.icon_time", Loc.t("In incubation"), l["incubating"], UiKit.AMBER],
				["ui.icon_population", Loc.t("Born"), l["born"], UiKit.OK], ["ui.icon_critical", Loc.t("Lost"), l["lost"], UiKit.DANGER if int(l["lost"]) > 0 else UiKit.MUTED]]:
			row.add_child(ArkPanels.stat_card(str(r[0]), str(r[1]), UiKit.thousands(int(r[2])), r[3], float(r[2]) / total, (r[3] as Color) if r[3] != UiKit.TEXT else UiKit.PETROL))
		body.add_child(row)
		body.add_child(UiKit.section(Loc.t("Redundancy"), "ui.icon_ok"))
		body.add_child(UiKit.label(Loc.t("Redundancy: four independent cooling loops, all stable on emergency power. Incubation requires a care center, stable supply and +5 kW on a new world."), 15, UiKit.MUTED, true))


class WorkshopPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(820, 520))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header(Loc.t("The workshop"), Loc.t("Robots, components and repairs."), "ui.icon_repair")
		var cards := UiKit.hbox(10)
		cards.add_child(ArkPanels.stat_card("ui.icon_ship", Loc.t("Hull"), "%d%%" % int(gs.ark.integrity), UiKit.WARN if gs.ark.integrity < 50.0 else UiKit.TEXT, gs.ark.integrity / 100.0, UiKit.WARN if gs.ark.integrity < 50.0 else UiKit.PETROL))
		cards.add_child(ArkPanels.stat_card("ui.icon_suit", Loc.t("Oxygen"), "%d%%" % int(gs.ark.oxygen), UiKit.TEXT, gs.ark.oxygen / 100.0, UiKit.WATER))
		cards.add_child(ArkPanels.stat_card("ui.icon_components", Loc.t("Components"), str(gs.ark.components)))
		cards.add_child(ArkPanels.stat_card("ui.icon_fuel", Loc.t("Fuel"), str(int(gs.ark.fuel))))
		body.add_child(cards)
		body.add_child(UiKit.label(Loc.t("Every component you use here will be missing later in the colony. Probes cost 3, a drone reserve 2. Whatever remains at landing becomes the colony's starting stock."), 16, UiKit.MUTED, true))
		body.add_child(UiKit.section(Loc.t("Repair the hull"), "ui.icon_ship"))
		var row := UiKit.hbox(10)
		for n: int in [1, 3, 5]:
			var b := UiKit.button(Loc.t("Repair the hull: %d comp. → +%d%%") % [n, n * 4], func() -> void:
				GameSession.cmd_repair(n)
				refresh())
			b.disabled = gs.ark.components < n or gs.ark.integrity >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			UiKit.with_icon(b, "ui.icon_repair", 18)
			row.add_child(b)
		body.add_child(row)
		body.add_child(UiKit.section(Loc.t("Repair scrubbers"), "ui.icon_suit"))
		var orow := UiKit.hbox(10)
		var per := float(GameSession.content.bal("oxygen", {}).get("repair_per_component", 4.0))
		for n: int in [1, 3, 5]:
			var ob := UiKit.button(Loc.t("Repair scrubbers: %d comp. → +%d%%") % [n, int(n * per)], func() -> void:
				GameSession.cmd_repair_oxygen(n)
				refresh())
			ob.disabled = gs.ark.components < n or gs.ark.oxygen >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			UiKit.with_icon(ob, "ui.icon_repair", 18)
			orow.add_child(ob)
		body.add_child(orow)
		if gs.ark.integrity < 50.0:
			body.add_child(UiKit.label(Loc.t("▲ Below 50% hull, the Ark gives only 60% emergency power after landing."), 16, UiKit.WARN, true))
