class_name DebugCapture
extends Node
## DEBUG / EVIDENCE ONLY. Active only with command-line user args, never in the
## player flow. Prepares a named fixture state through real domain commands,
## opens a scene, waits, saves a screenshot and quits.
## Example (needs a display; use xvfb-run on Linux):
##   godot --path . -- --capture=evidence/shots/ship.png --setup=power --scene=ship --wait=90 [--lang=en]

var out_path := ""
var setup := "fresh"
var scene_key := "menu"
var wait_frames := 90
var extra: Dictionary = {}
var lang := ""  # --lang=en: capture in another language without touching saved settings
var ui_scale := 0.0  # --ui_scale=1.5: capture at another UI scale without touching saved settings


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
				"lang": lang = kv[1]
				"ui_scale": ui_scale = float(kv[1])
				_: extra[kv[0]] = kv[1]
	_run.call_deferred()


func _run() -> void:
	if not lang.is_empty():
		Loc.set_language(lang)
		GameSession.reload_content()
	if ui_scale > 0.0:
		get_tree().root.content_scale_factor = ui_scale  # never written to settings.cfg
	DebugFixtures.prepare(setup)
	if scene_key != "menu" and not extra.has("no_scene"):
		AppFlow.params = extra
	AppFlow.goto(scene_key, extra)
	for i: int in wait_frames:
		await get_tree().process_frame
	# Park the cursor where no button sits, so no stray hover/tooltip lands in the shot.
	get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 170))
	if extra.has("action"):
		var sc := get_tree().current_scene
		var act := str(extra["action"])
		var hud: Variant = sc.get("hud") if sc else null
		if act == "alarm" and hud is GameHud:
			AudioService.alarm_raised.emit(true)  # the HUD's visual twin of an alarm sound
		elif act in ["pause", "pause_settings", "pause_save", "pause_load"] and hud is GameHud:
			(hud as GameHud).pause_menu.open()
			if act == "pause_settings":
				(hud as GameHud).pause_menu.open_settings()
			elif act == "pause_save":
				(hud as GameHud).pause_menu._save_menu()
			elif act == "pause_load":
				(hud as GameHud).pause_menu._load_menu()
		elif act == "journal" and hud is GameHud:
			(hud as GameHud).journal.toggle()
		elif act == "hud_demo" and hud is GameHud:
			# Every HUD message surface at once: notices of each kind, a subtitle and a prompt.
			var gh := hud as GameHud
			gh.toast(Loc.t("Objective complete: %s") % Loc.t("Restore emergency power"), "ok")
			gh.toast(Loc.t("Not enough components (have %d, need %d).") % [1, 3], "warning")
			gh.toast(Loc.t("ALARM: critical"), "critical")
			gh.story.play_scene({"id": "dbg", "lines": [{"speaker": "CAPTAIN", "text": Loc.t("You are the last human who can give humanity a future.")}]})
			gh.set_prompt("[%s] %s %s" % [SettingsService.binding_text("interact"), Loc.t("Connect"), Loc.t("the emergency power coupling")])
		elif sc and sc.has_method("debug_action"):
			sc.call("debug_action", act)
		# The alarm banner hides after a few real seconds; software rendering is slow.
		# --hold=N waits N frames instead (Movie Maker sequences); --frametimes=<json>
		# records every frame's time over that window (hero-moment perf, D-056).
		var hold := int(extra.get("hold", 4 if act == "alarm" else 40))
		var times: Array = []
		var last := Time.get_ticks_usec()
		for i: int in hold:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append(snappedf((now - last) / 1000.0, 0.001))
			last = now
		if extra.has("frametimes"):
			var fp := str(extra["frametimes"])
			var fabs := fp if fp.is_absolute_path() else ProjectSettings.globalize_path("res://" + fp)
			DirAccess.make_dir_recursive_absolute(fabs.get_base_dir())
			var f := FileAccess.open(fabs, FileAccess.WRITE)
			f.store_string(JSON.stringify({"action": act, "frame_ms": times, "device": RenderingServer.get_video_adapter_name()}))
			f.close()
	var img := get_viewport().get_texture().get_image()
	var abs_path := out_path if out_path.is_absolute_path() else ProjectSettings.globalize_path("res://" + out_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	img.save_png(abs_path)
	print("CAPTURED ", abs_path)
	get_tree().quit(0)
