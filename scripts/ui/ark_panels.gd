class_name ArkPanels
extends RefCounted
## Small ship-room panels: embryo bank status and the workshop.


class EmbryoBankPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(880, 600))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header(Loc.t("The embryo bank"), Loc.t("Storage status, redundancy and the later care plan."))
		var big := UiKit.label(UiKit.thousands(gs.ark.embryo_sum()), 96, UiKit.TEXT)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(big)
		var sub := UiKit.label(Loc.t("The number is not a score. It is everyone who may yet become someone."), 18, UiKit.MUTED, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(sub)
		var l := gs.ark.ledger()
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 30)
		for row: Array in [[Loc.t("Viable in cryo"), l["viable"]], [Loc.t("In incubation"), l["incubating"]], [Loc.t("Born"), l["born"]], [Loc.t("Lost"), l["lost"]]]:
			g.add_child(UiKit.label(str(row[0]), 18, UiKit.MUTED))
			g.add_child(UiKit.label(UiKit.thousands(int(row[1])), 22))
		body.add_child(g)
		body.add_child(UiKit.label(Loc.t("Redundancy: four independent cooling loops, all stable on emergency power. Incubation requires a care center, stable supply and +5 kW on a new world."), 15, UiKit.MUTED, true))


class WorkshopPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(820, 520))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header(Loc.t("The workshop"), Loc.t("Robots, components and repairs."))
		body.add_child(UiKit.label(Loc.t("Hull %d%% · Oxygen %d%% · Components %d · Fuel %d") % [int(gs.ark.integrity), int(gs.ark.oxygen), gs.ark.components, int(gs.ark.fuel)], 20))
		body.add_child(UiKit.label(Loc.t("Every component you use here will be missing later in the colony. Probes cost 3, a drone reserve 2. Whatever remains at landing becomes the colony's starting stock."), 16, UiKit.MUTED, true))
		var row := UiKit.hbox(10)
		for n: int in [1, 3, 5]:
			var b := UiKit.button(Loc.t("Repair the hull: %d comp. → +%d%%") % [n, n * 4], func() -> void:
				GameSession.cmd_repair(n)
				refresh())
			b.disabled = gs.ark.components < n or gs.ark.integrity >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			row.add_child(b)
		body.add_child(row)
		var orow := UiKit.hbox(10)
		var per := float(GameSession.content.bal("oxygen", {}).get("repair_per_component", 4.0))
		for n: int in [1, 3, 5]:
			var ob := UiKit.button(Loc.t("Repair scrubbers: %d comp. → +%d%%") % [n, int(n * per)], func() -> void:
				GameSession.cmd_repair_oxygen(n)
				refresh())
			ob.disabled = gs.ark.components < n or gs.ark.oxygen >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			orow.add_child(ob)
		body.add_child(orow)
		if gs.ark.integrity < 50.0:
			body.add_child(UiKit.label(Loc.t("▲ Below 50% hull, the Ark gives only 60% emergency power after landing."), 16, UiKit.WARN, true))
