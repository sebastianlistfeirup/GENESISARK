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
	body.add_child(UiKit.label(Loc.t("Year %d: the first generation speaks") % int(gs.campaign.colony_year()), 28, UiKit.AMBER))
	body.add_child(UiKit.label(Loc.t("Those born here have their own answers to what the colony should be. Your choice changes trust, autonomy and what the institutions prioritize. No answer is the right one."), 16, UiKit.TEXT, true))
	var lines := {"expansion": Loc.t("We have to move on. The valleys to the north could feed thousands."), "safety": Loc.t("We can't afford to lose anything. Reserves before everything else."),
		"self_determination": Loc.t("We want to decide for ourselves. Give the council the keys.")}
	for ch: Dictionary in GameSession.content.characters.values():
		var persp := str(ch.get("perspective", ""))
		if persp.is_empty():
			continue
		var p := UiKit.panel()
		var v := UiKit.vbox(4)
		v.add_child(UiKit.label(str(ch.get("name")), 20, UiKit.TEXT))
		v.add_child(UiKit.label(str(ch.get("bio", "")), 14, UiKit.MUTED, true))
		v.add_child(UiKit.label("“%s”" % lines.get(persp, ""), 16, UiKit.TEXT, true))
		v.add_child(UiKit.button(Loc.t("Support %s (%s)") % [str(ch.get("name")).split(" ")[0], {"expansion": "ekspansion", "safety": "sikkerhed", "self_determination": "selvbestemmelse"}[persp]], func() -> void:
			if GameSession.cmd_choose_priority(decision_id, persp).ok:
				close()))
		p.add_child(v)
		body.add_child(p)


func _unhandled_input(event: InputEvent) -> void:
	pass
