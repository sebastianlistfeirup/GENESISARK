extends Node
## Trailer director: plays a scripted tour of the game (menu, derelict ark, terminals,
## approach, real-time descent, the six worlds, colony, epilogue) with slow camera
## drift, title cards and the game's own audio, for Godot Movie Maker:
##   godot --path . --resolution 1920x1080 --write-movie C:/abs/trailer.avi --fixed-fps 30 res://tools/trailer/trailer.tscn
## Dev tool only. Uses the evidence fixtures/actions; nothing is saved.

const SHOTS := [
	# [setup, scene, action, seconds, caption, hide_hud, drift_deg_per_s]
	["fresh", "menu", "", 7.0, "", false, 0.0],
	["fresh", "ship", "", 9.0, "50,000 embryos. One last human.", false, 0.0],
	["power", "ship", "roomcam_E", 5.0, "", true, 1.5],
	["power", "ship", "roomcam_B", 5.0, "", true, 1.5],
	["power", "ship", "starmap", 7.0, "Six possible worlds", false, 0.0],
	["orbit:sere", "ship", "orbit", 5.0, "", false, 0.0],
	["orbit:viridia", "flight", "", 8.0, "", true, 0.0],
	["expedition:viridia", "surface", "descent:2600", 31.0, "Land anywhere. In real time.", false, 0.0],
	["expedition:viridia", "surface", "vista:200", 7.0, "VIRIDIA", true, 3.0],
	["expedition:pelagos", "surface", "leviathan", 9.0, "PELAGOS", true, 1.0],
	["expedition:umbra", "surface", "vista:45", 7.0, "UMBRA", true, 3.0],
	["expedition:sere", "surface", "vista:135", 7.0, "SERE", true, 3.0],
	["expedition:nivalis", "surface", "vista:45", 6.0, "NIVALIS", true, 3.0],
	["expedition:ferrum", "surface", "vista:225", 6.0, "FERRUM", true, 3.0],
	["expedition:viridia", "surface", "ascent", 11.0, "", false, 0.0],
	["era:ferrum:20", "colony", "zoomout", 8.0, "Build a civilisation", true, 4.0],
	["era:ferrum:20", "colony", "rover", 7.0, "", true, 0.0],
	["grown:viridia", "colony", "living", 6.0, "", true, 2.0],
	["era:viridia:40", "ending", "", 8.0, "", false, 0.0],
]

var _layer: CanvasLayer
var _caption: Label
var _card: Label
var _black: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Survive scene changes: hang the director off the root.
	call_deferred("_reparent_and_run")


func _reparent_and_run() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_build_overlay()
	await _run()
	get_tree().quit(0)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.position = Vector2(-700, -170)
	_caption.custom_minimum_size = Vector2(1400, 0)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", UiKit.bold_font())
	_caption.add_theme_font_size_override("font_size", 44)
	_caption.add_theme_constant_override("outline_size", 14)
	_caption.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.85))
	_caption.modulate.a = 0.0
	_layer.add_child(_caption)
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0.01, 0.02, 0.04, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_black)
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_override("font", UiKit.bold_font())
	_card.add_theme_font_size_override("font_size", 120)
	_card.add_theme_constant_override("outline_size", 24)
	_card.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.9))
	_card.text = "GENESIS ARK"
	_card.modulate.a = 0.0
	_layer.add_child(_card)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _run() -> void:
	for shot: Array in SHOTS:
		DebugFixtures.prepare(str(shot[0]))
		if str(shot[0]) != "fresh" and GameSession.has_game():
			GameSession.state.mark_applied("story:intro_wakeup")  # the wake-up plays only in the opening shot
		var act := str(shot[2])
		var params := {"action": act} if act.begins_with("descent") else {"no_intro": true}
		AppFlow.goto(str(shot[1]), params)
		var want := str(AppFlow.SCENES.get(str(shot[1]), ""))
		for i: int in 600:
			await get_tree().process_frame
			var sc0 := get_tree().current_scene
			if sc0 and sc0.scene_file_path == want:
				break
		for i: int in 45:  # fade-in and lights settle
			await get_tree().process_frame
		var sc := get_tree().current_scene
		if not act.is_empty() and not act.begins_with("descent") and sc and sc.has_method("debug_action"):
			sc.call("debug_action", act)
		if bool(shot[5]) and sc:
			# Every UI layer of the scene (HUD, dialogs, waypoints), not just the HUD.
			for n: Node in sc.find_children("*", "CanvasLayer", true, false):
				(n as CanvasLayer).visible = false
			GameSession.colony_clock_active = false  # no event popping up mid-shot
		_show_caption(str(shot[4]))
		var t := 0.0
		var dur := float(shot[3])
		var drift := deg_to_rad(float(shot[6]))
		while t < dur:
			var dt := get_process_delta_time()
			t += dt
			if drift != 0.0:
				_drift(dt * drift)
			await get_tree().process_frame
	_card.text = "GENESIS ARK"
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_black, "color:a", 0.85, 1.0)
	tw.tween_property(_card, "modulate:a", 1.0, 1.2)
	await _wait(4.0)


func _show_caption(text: String) -> void:
	_caption.text = text
	_caption.modulate.a = 0.0
	if text.is_empty():
		return
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_caption, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.6)
	tw.tween_property(_caption, "modulate:a", 0.0, 0.8)


## Slow orbit of the active camera around the point it looks at (~60 m ahead, on its own height).
func _drift(angle: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_basis.z
	var pivot := cam.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 60.0
	pivot.y = cam.global_position.y + fwd.y * 60.0
	var off := cam.global_position - pivot
	off = off.rotated(Vector3.UP, angle)
	var gt := cam.global_transform
	gt.origin = pivot + off
	gt.basis = Basis(Vector3.UP, angle) * gt.basis
	cam.global_transform = gt
