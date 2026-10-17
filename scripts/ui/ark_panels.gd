class_name ArkPanels
extends RefCounted
## Small ship-room panels: embryo bank status and the workshop.


class EmbryoBankPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(880, 600))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header("Embryobanken", "Lagerstatus, redundans og den senere omsorgsplan.")
		var big := UiKit.label(UiKit.thousands(gs.ark.embryo_sum()), 96, UiKit.TEXT)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(big)
		var sub := UiKit.label("Tallet er ikke en score. Det er alle, der endnu kan blive til nogen.", 18, UiKit.MUTED, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(sub)
		var l := gs.ark.ledger()
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 30)
		for row: Array in [["Levedygtige i kryo", l["viable"]], ["I inkubation", l["incubating"]], ["Født", l["born"]], ["Tabt", l["lost"]]]:
			g.add_child(UiKit.label(str(row[0]), 18, UiKit.MUTED))
			g.add_child(UiKit.label(UiKit.thousands(int(row[1])), 22))
		body.add_child(g)
		body.add_child(UiKit.label("Redundans: fire uafhængige kølesløjfer, alle stabile på nødstrøm. Inkubation kræver et omsorgscenter, stabil forsyning og +5 kW på en ny verden.", 15, UiKit.MUTED, true))


class WorkshopPanel extends OverlayPanel:
	func _init() -> void:
		super(Vector2(820, 520))

	func refresh() -> void:
		UiKit.clear(body)
		var gs: GameState = GameSession.state
		header("Værkstedet", "Robotter, komponenter og reparationer.")
		body.add_child(UiKit.label("Skrog %d%% · Komponenter %d · Brændstof %d" % [int(gs.ark.integrity), gs.ark.components, int(gs.ark.fuel)], 20))
		body.add_child(UiKit.label("Hver komponent, du bruger her, mangler senere i kolonien. Sonder koster 3, en dronereserve 2. Det, der er tilbage ved landing, bliver koloniens startlager.", 16, UiKit.MUTED, true))
		var row := UiKit.hbox(10)
		for n: int in [1, 3, 5]:
			var b := UiKit.button("Reparér skroget: %d komp. → +%d%%" % [n, n * 4], func() -> void:
				GameSession.cmd_repair(n)
				refresh())
			b.disabled = gs.ark.components < n or gs.ark.integrity >= 100.0 or gs.campaign.phase == CampaignState.PHASE_SETTLED
			row.add_child(b)
		body.add_child(row)
		if gs.ark.integrity < 50.0:
			body.add_child(UiKit.label("▲ Under 50% skrog giver arken kun 60% nødstrøm efter landing.", 16, UiKit.WARN, true))
