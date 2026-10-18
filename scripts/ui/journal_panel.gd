class_name JournalPanel
extends CanvasLayer
## Tab: objectives, log and the embryo ledger at a glance.

var _panel: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = UiKit.panel(Vector2(760, 620))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = UiKit.vbox(6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_panel.add_child(scroll)
	add_child(_panel)
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioService.ui("ui_click")


func refresh() -> void:
	UiKit.clear(_body)
	if not GameSession.has_game():
		return
	var gs: GameState = GameSession.state
	_body.add_child(UiKit.heading(Loc.t("Journal")))
	var l := gs.ark.ledger()
	_body.add_child(UiKit.rich(Loc.t("[color=#8fa3ad]Embryoregnskab:[/color] %s levedygtige · %s i inkubation · %s født · %s tabt   [color=#8fa3ad](i alt %s)[/color]") % [
		UiKit.thousands(l["viable"]), UiKit.thousands(l["incubating"]), UiKit.thousands(l["born"]), UiKit.thousands(l["lost"]), UiKit.thousands(gs.ark.embryo_sum())]))
	_body.add_child(UiKit.title(Loc.t("Mål")))
	var ids: Array = GameSession.content.objectives.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(GameSession.content.objectives[a].get("order", 0)) < int(GameSession.content.objectives[b].get("order", 0)))
	var shown := 0
	for id: String in ids:
		var o: Dictionary = GameSession.content.objectives[id]
		var done := id in gs.campaign.completed_objectives
		var cur := not done and shown == 0
		if not done:
			shown += 1
		if shown > 3:
			continue
		_body.add_child(UiKit.rich("%s %s" % ["[color=#5fae6e]✔[/color]" if done else ("[color=#e8a33d]▶[/color]" if cur else "[color=#8fa3ad]○[/color]"), o.get("title", id)]))
	_body.add_child(UiKit.title(Loc.t("Logbog")))
	var entries: Array = gs.campaign.journal.duplicate()
	entries.reverse()
	for e: Dictionary in entries.slice(0, 40):
		_body.add_child(UiKit.rich(Loc.t("[color=#8fa3ad]Dag %d[/color]  %s") % [int(e.get("day", 0)), e.get("text", "")]))

