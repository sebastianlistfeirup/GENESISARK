extends Node
## Entry scene: settings and content are loaded by autoloads; report content
## errors loudly instead of starting a broken game, then go to the menu.

func _ready() -> void:
	if not GameSession.content.errors.is_empty():
		var l := Label.new()
		l.text = Loc.t("Content error — see log:\n") + "\n".join(GameSession.content.errors)
		add_child(l)
		return
	await get_tree().process_frame
	if PerfProbe.requested():
		get_tree().root.add_child(PerfProbe.new())
		return
	if _playtest_requested():  # dev tool: scripted player (tools/playtest, D-066)
		var drv := load("res://tools/playtest/play_driver.gd") as GDScript
		if drv and drv.can_instantiate():
			get_tree().root.add_child(drv.new() as Node)
			return
		push_error("playtest driver failed to load")
		get_tree().quit(3)
		return
	if DebugCapture.requested():
		get_tree().root.add_child(DebugCapture.new())
		return
	AppFlow.goto("menu")


static func _playtest_requested() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--playtest"):
			return true
	return false
