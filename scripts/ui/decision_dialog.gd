class_name DecisionDialog
extends OverlayPanel
## Generational chapter decision (bible p.12: at year 20 the first generation
## challenges your priorities — expansion, safety or self-determination).

var decision_id := ""


func _init() -> void:
	super(Vector2(980, 640))


func ask(id: String) -> void:
	decision_id = id
	open()


func refresh() -> void:
	UiKit.clear(body)
	var gs: GameState = GameSession.state
	body.add_child(UiKit.label(Loc.t("År %d: den første generation taler") % int(gs.campaign.colony_year()), 28, UiKit.AMBER))
	body.add_child(UiKit.label(Loc.t("De, der blev født her, har deres egne svar på, hvad kolonien skal være. Dit valg ændrer tillid, selvbestemmelse og hvad institutionerne prioriterer. Ingen svar er det rigtige."), 16, UiKit.TEXT, true))
	var lines := {"expansion": Loc.t("Vi skal videre. Dalene mod nord kan brødføde tusinder."), "safety": Loc.t("Vi har ikke råd til at miste noget. Reserver før alt andet."),
		"self_determination": Loc.t("Vi vil selv bestemme. Giv rådet nøglerne.")}
	for ch: Dictionary in GameSession.content.characters.values():
		var persp := str(ch.get("perspective", ""))
		if persp.is_empty():
			continue
		var p := UiKit.panel()
		var v := UiKit.vbox(4)
		v.add_child(UiKit.label(str(ch.get("name")), 20, UiKit.TEXT))
		v.add_child(UiKit.label(str(ch.get("bio", "")), 14, UiKit.MUTED, true))
		v.add_child(UiKit.label("“%s”" % lines.get(persp, ""), 16, UiKit.TEXT, true))
		v.add_child(UiKit.button(Loc.t("Støt %s (%s)") % [str(ch.get("name")).split(" ")[0], {"expansion": "ekspansion", "safety": "sikkerhed", "self_determination": "selvbestemmelse"}[persp]], func() -> void:
			if GameSession.cmd_choose_priority(decision_id, persp).ok:
				close()))
		p.add_child(v)
		body.add_child(p)


func _unhandled_input(event: InputEvent) -> void:
	pass
