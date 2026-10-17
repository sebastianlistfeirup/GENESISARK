class_name DebugCapture
extends Node
## DEBUG / EVIDENCE ONLY. Active only with command-line user args, never in the
## player flow. Prepares a named fixture state through real domain commands,
## opens a scene, waits, saves a screenshot and quits.
## Example (needs a display; use xvfb-run on Linux):
##   godot --path . -- --capture=evidence/shots/ship.png --setup=power --scene=ship --wait=90

var out_path := ""
var setup := "fresh"
var scene_key := "menu"
var wait_frames := 90
var extra: Dictionary = {}


static func requested() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"capture": out_path = kv[1]
				"setup": setup = kv[1]
				"scene": scene_key = kv[1]
				"wait": wait_frames = int(kv[1])
				_: extra[kv[0]] = kv[1]
	_run.call_deferred()


func _run() -> void:
	DebugFixtures.prepare(setup)
	if scene_key != "menu" and not extra.has("no_scene"):
		AppFlow.params = extra
	AppFlow.goto(scene_key, extra)
	for i: int in wait_frames:
		await get_tree().process_frame
	if extra.has("action"):
		var sc := get_tree().current_scene
		if sc and sc.has_method("debug_action"):
			sc.call("debug_action", str(extra["action"]))
		for i: int in 40:
			await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path("res://" + out_path) if not out_path.begins_with("/") else out_path
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	img.save_png(abs_path)
	print("CAPTURED ", abs_path)
	get_tree().quit(0)
