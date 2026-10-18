extends Node
## Entry scene: settings and content are loaded by autoloads; report content
## errors loudly instead of starting a broken game, then go to the menu.

func _ready() -> void:
	if not GameSession.content.errors.is_empty():
		var l := Label.new()
		l.text = Loc.t("Indholdsfejl — se log:\n") + "\n".join(GameSession.content.errors)
		add_child(l)
		return
	await get_tree().process_frame
	if DebugCapture.requested():
		get_tree().root.add_child(DebugCapture.new())
		return
	AppFlow.goto("menu")
