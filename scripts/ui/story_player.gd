class_name StoryPlayer
extends CanvasLayer
## Plays short hand-written scenes as subtitles with speaker names (bible p.13:
## subtitles work without voice; size is adjustable). Non-blocking by default.

var blocking := false
var _queue: Array = []
var _box: PanelContainer
var _speaker: Label
var _text: Label
var _timer := 0.0
var _lines: Array = []
var _index := 0
var _scene_id := ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = UiKit.panel()
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.position.y -= 110
	_box.custom_minimum_size = Vector2(900, 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UiKit.vbox(2)
	_speaker = UiKit.label("", 16, UiKit.AMBER)
	_text = UiKit.label("", 22, UiKit.TEXT, true)
	_text.custom_minimum_size = Vector2(860, 0)
	v.add_child(_speaker)
	v.add_child(_text)
	_box.add_child(v)
	_box.visible = false
	add_child(_box)


func play_scene(scene: Dictionary) -> void:
	_queue.append(scene)
	if _lines.is_empty():
		_next_scene()


func _next_scene() -> void:
	if _queue.is_empty():
		_lines = []
		_box.visible = false
		return
	var sc: Dictionary = _queue.pop_front()
	_scene_id = str(sc.get("id", ""))
	_lines = DictUtil.get_arr(sc, "lines")
	_index = 0
	_show_line()


func _show_line() -> void:
	if _index >= _lines.size():
		_next_scene()
		return
	var line: Dictionary = _lines[_index]
	var sp := str(line.get("speaker", ""))
	var name := sp
	if sp == "CAPTAIN":
		name = Loc.t("Kaptajnen")
	elif sp == "NARRATOR":
		name = ""
	elif GameSession.content and GameSession.content.characters.has(sp):
		name = str(GameSession.content.characters[sp].get("name", sp))
	_speaker.text = name
	_speaker.visible = not name.is_empty()
	_text.text = str(line.get("text", ""))
	_text.add_theme_font_size_override("font_size", int(SettingsService.get_value("subtitle_size", 22)))
	_box.visible = bool(SettingsService.get_value("subtitles", true)) or sp != "NARRATOR"
	_timer = clampf(2.0 + _text.text.length() * 0.055, 3.0, 9.0)
	# Line id = "<scene id>_<two-digit index>", matching docs/VO_SCRIPT.csv.
	var vo := AudioService.play_voice("%s_%02d" % [_scene_id, _index + 1])
	if vo > 0.0:
		_timer = maxf(_timer, vo + 0.4)


func _process(delta: float) -> void:
	if _lines.is_empty():
		return
	_timer -= delta
	if _timer <= 0.0:
		_index += 1
		_show_line()


func skip_line() -> void:
	if not _lines.is_empty():
		AudioService.stop_voice()
		_index += 1
		_show_line()


func is_playing() -> bool:
	return not _lines.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if is_playing() and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ENTER:
		skip_line()
		get_viewport().set_input_as_handled()
