class_name EventDialog
extends OverlayPanel
## Crisis / citizen event: situation, options with price, requirements and the
## consequence shown before choosing. Always at least one free option.

var event_def: Dictionary = {}


func _init() -> void:
	super(Vector2(900, 620))


func show_event(def: Dictionary) -> void:
	event_def = def
	open()


func refresh() -> void:
	UiKit.clear(body)
	if event_def.is_empty():
		return
	var crit := bool(event_def.get("critical", false))
	var h := UiKit.label(("■ " if crit else "◆ ") + str(event_def.get("title", "")), 28, UiKit.DANGER if crit else UiKit.AMBER, true)
	body.add_child(h)
	body.add_child(UiKit.label(str(event_def.get("text", "")), 18, UiKit.TEXT, true))
	if crit:
		body.add_child(UiKit.label(Loc.t("Time stands still until you have chosen. Time leaps stop at unresolved crises."), 14, UiKit.MUTED, true))
	var gs: GameState = GameSession.state
	for o: Dictionary in DictUtil.get_arr(event_def, "options"):
		var blockers := GameSession.sim.events.option_blockers(gs, event_def, o)
		var cost: Dictionary = GameSession.sim.events.option_cost(gs, event_def, o)
		var parts: Array = []
		for k: String in cost.keys():
			if float(cost[k]) > 0.0:
				parts.append("%d %s" % [int(cost[k]), ColonySimulation._res_label(k)])
		var p := UiKit.panel()
		var v := UiKit.vbox(4)
		var b := UiKit.button(str(o.get("label", "")) + ("  (" + ", ".join(parts) + ")" if not parts.is_empty() else Loc.t("  (free)")), func() -> void:
			var r := GameSession.cmd_resolve_event(str(event_def.get("id")), str(o.get("id")))
			if r.ok:
				event_def = {}
				close())
		b.disabled = not blockers.is_empty()
		v.add_child(b)
		v.add_child(UiKit.label(str(o.get("description", "")), 15, UiKit.MUTED, true))
		for bl: Variant in blockers:
			v.add_child(UiKit.label("✕ " + str(bl), 14, UiKit.WARN, true))
		p.add_child(v)
		body.add_child(p)


func _unhandled_input(event: InputEvent) -> void:
	pass  # An event must be answered; Esc does not dismiss it.
