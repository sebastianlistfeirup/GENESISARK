extends Node
## Settings and input map (bible p.26: every action can be rebound; UI scale;
## subtitles; reduced motion). Persists to user://settings.cfg.

signal changed
signal input_device_changed(pad: bool)

const PATH := "user://settings.cfg"
## 2 = English became the game's language (D-025): older files had Danish as the
## default, so their saved "da" is reset to English once.
const SETTINGS_VERSION := 2

## action -> [default keys]. Mouse buttons are prefixed "mouse:".
const ACTIONS := {
	"move_forward": ["W", "Up"], "move_back": ["S", "Down"], "move_left": ["A", "Left"], "move_right": ["D", "Right"],
	"sprint": ["Shift"], "interact": ["E"], "journal": ["Tab"], "pause": ["Escape"],
	"colony_mode": ["B"], "rotate_cam_left": ["Q"], "rotate_cam_right": ["E"], "rotate_building": ["R"],
	"confirm": ["mouse:1"], "cancel": ["mouse:2"], "autopilot": ["F"], "speed_pause": ["Space"],
	"speed_1": ["1"], "speed_3": ["3"], "drone_refill": ["G"], "ascend": ["Space"], "descend": ["Ctrl"],
	"zoom_in": ["Equal"], "zoom_out": ["Minus"], "build_confirm": ["Enter"],
	"build_repeat": ["Shift"], "skip_line": ["Enter"], "camera_view": ["V"],
}
const ACTION_LABELS := {
	"move_forward": "Forward", "move_back": "Back", "move_left": "Left", "move_right": "Right",
	"sprint": "Run", "interact": "Interact", "journal": "Journal", "pause": "Pause / back",
	"colony_mode": "Colony mode", "rotate_cam_left": "Rotate camera left", "rotate_cam_right": "Rotate camera right",
	"rotate_building": "Rotate building", "confirm": "Confirm", "cancel": "Cancel", "autopilot": "Autopilot",
	"speed_pause": "Pause time", "speed_1": "Speed 1x", "speed_3": "Speed 3x", "drone_refill": "Drone reserve",
	"ascend": "Ascend (flight)", "descend": "Descend (flight)",
	"zoom_in": "Zoom in", "zoom_out": "Zoom out", "build_confirm": "Build here",
	"build_repeat": "Hold: keep building", "skip_line": "Skip subtitle line", "camera_view": "Cockpit / chase view (flight)",
}

## Controller layout (Xbox naming; Godot JoyButton/JoyAxis indices). Tokens:
## "btn:<JoyButton>" or "axis:<JoyAxis>:<+|->". Added next to the keyboard
## bindings, so remapping keys never removes the pad. Not remappable in v1 (D-018).
const PAD := {
	"move_forward": ["axis:1:-", "btn:11"], "move_back": ["axis:1:+", "btn:12"],
	"move_left": ["axis:0:-", "btn:13"], "move_right": ["axis:0:+", "btn:14"],
	"look_left": ["axis:2:-"], "look_right": ["axis:2:+"], "look_up": ["axis:3:-"], "look_down": ["axis:3:+"],
	"sprint": ["btn:7"], "interact": ["btn:0"], "journal": ["btn:4"], "pause": ["btn:6"],
	"colony_mode": ["btn:3"], "rotate_cam_left": ["btn:9"], "rotate_cam_right": ["btn:10"], "rotate_building": ["btn:2"],
	"confirm": ["btn:0"], "build_confirm": ["btn:0"], "cancel": ["btn:1"], "autopilot": ["btn:3"],
	"speed_pause": ["btn:8"], "drone_refill": ["btn:2"], "ascend": ["axis:5:+"], "descend": ["axis:4:+"],
	"zoom_in": ["axis:5:+"], "zoom_out": ["axis:4:+"], "camera_view": ["btn:2"],
}
const PAD_NAMES := {"btn:0": "A", "btn:1": "B", "btn:2": "X", "btn:3": "Y", "btn:4": "Back", "btn:6": "Start",
	"btn:7": "L3", "btn:8": "R3", "btn:9": "LB", "btn:10": "RB", "btn:11": "D-pad", "btn:12": "D-pad",
	"btn:13": "D-pad", "btn:14": "D-pad", "axis:4:+": "LT", "axis:5:+": "RT", "axis:0:-": "L-stick",
	"axis:0:+": "L-stick", "axis:1:-": "L-stick", "axis:1:+": "L-stick", "axis:2:-": "R-stick",
	"axis:2:+": "R-stick", "axis:3:-": "R-stick", "axis:3:+": "R-stick"}

## True after the last meaningful input came from a controller (prompts and
## the colony build cursor follow it).
var using_pad := false

var values := {
	"master_volume": 0.9, "music_volume": 0.6, "sfx_volume": 0.9, "ambience_volume": 0.7, "ui_volume": 0.8,
	"ui_scale": 1.0, "subtitle_size": 22, "subtitles": true, "reduced_motion": false, "mouse_sensitivity": 0.25,
	"invert_y": false, "fullscreen": false, "camera_shake": true, "realtime_descent": true, "language": "en", "pad_look_speed": 2.4, "touch_look_sensitivity": 1.0,
	"graphics_quality": "auto",
}
var remaps: Dictionary = {}  # action -> [key names]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_input_map()
	apply()


func get_value(key: String, fallback: Variant = null) -> Variant:
	return values.get(key, fallback)


func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply()
	save_settings()
	changed.emit()


func apply() -> void:
	Loc.set_language(str(values["language"]))
	get_tree().root.content_scale_factor = float(values["ui_scale"])
	get_tree().root.mesh_lod_threshold = Quality.mesh_lod_threshold()  # D-054
	if not DisplayServer.get_name() == "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and (values["fullscreen"] or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(mode)


func keys_for(action: String) -> Array:
	return remaps.get(action, ACTIONS.get(action, []))


func apply_input_map() -> void:
	var all: Array = ACTIONS.keys()
	for a: String in PAD.keys():
		if not a in all:
			all.append(a)
	for action: String in all:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for k: String in keys_for(action):
			var ev := _event_for(k)
			if ev:
				InputMap.action_add_event(action, ev)
		for token: String in PAD.get(action, []):
			InputMap.action_add_event(action, pad_event(token))


static func pad_event(token: String) -> InputEvent:
	var p := token.split(":")
	if p[0] == "btn":
		var b := InputEventJoypadButton.new()
		b.button_index = int(p[1]) as JoyButton
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = int(p[1]) as JoyAxis
	m.axis_value = -1.0 if p[2] == "-" else 1.0
	return m


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	var kbm := event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0)
	if (pad and not using_pad) or (kbm and using_pad):
		using_pad = pad
		input_device_changed.emit(using_pad)
	# Menus: a controller needs a focused control to navigate. Give it the first button on screen.
	if pad and event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		if get_viewport().gui_get_focus_owner() == null:
			var first := _first_focusable(get_tree().root)
			if first:
				first.grab_focus()


func _first_focusable(n: Node) -> Control:
	# Topmost layer first: modal panels sit on higher CanvasLayers than the HUD.
	var kids := n.get_children()
	kids.sort_custom(func(a: Node, b: Node) -> bool: return (a as CanvasLayer).layer > (b as CanvasLayer).layer if a is CanvasLayer and b is CanvasLayer else false)
	for c: Node in kids:
		if c is CanvasLayer and not (c as CanvasLayer).visible:
			continue
		if c is Control and not (c as Control).is_visible_in_tree():
			continue
		if c is BaseButton and not (c as BaseButton).disabled and (c as Control).focus_mode != Control.FOCUS_NONE:
			return c
		var f := _first_focusable(c)
		if f:
			return f
	return null


## Language change: persist, reload translated content, rebuild the scene.
func set_language(code: String) -> void:
	if code == str(values["language"]) or not Loc.LANGUAGES.has(code):
		return
	set_value("language", code)
	GameSession.reload_content()
	AppFlow.reload_current()


func rebind(action: String, key_name: String) -> void:
	remaps[action] = [key_name]
	apply_input_map()
	save_settings()
	changed.emit()


func reset_bindings() -> void:
	remaps.clear()
	apply_input_map()
	save_settings()
	changed.emit()


func _event_for(k: String) -> InputEvent:
	if k.begins_with("mouse:"):
		var mb := InputEventMouseButton.new()
		mb.button_index = int(k.substr(6)) as MouseButton
		return mb
	var code := OS.find_keycode_from_string(k)
	if code == KEY_NONE:
		return null
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	if ev is InputEventMouseButton:
		return {1: Loc.t("Left click"), 2: Loc.t("Right click"), 3: Loc.t("Middle click")}.get((ev as InputEventMouseButton).button_index, Loc.t("Mouse"))
	return "?"


func binding_text(action: String) -> String:
	if using_pad and PAD.has(action):
		return str(PAD_NAMES.get(PAD[action][0], "?"))
	var parts: Array = []
	for k: String in keys_for(action):
		if k.begins_with("mouse:"):
			parts.append({"1": Loc.t("Left click"), "2": Loc.t("Right click")}.get(k.substr(6), Loc.t("Mouse")))
		else:
			parts.append(k)
	return " / ".join(parts)


## Just the first binding (short prompts like "W/S speed"); follows remaps and the pad.
func primary_key(action: String) -> String:
	return binding_text(action).split(" / ")[0]


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in values.keys():
		values[k] = cfg.get_value("settings", k, values[k])
	if int(cfg.get_value("meta", "version", 1)) < 2:
		values["language"] = Loc.SOURCE
	for a: String in ACTIONS.keys():
		if cfg.has_section_key("input", a):
			remaps[a] = cfg.get_value("input", a)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	for k: String in values.keys():
		cfg.set_value("settings", k, values[k])
	for a: String in remaps.keys():
		cfg.set_value("input", a, remaps[a])
	cfg.save(PATH)
