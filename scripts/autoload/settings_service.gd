extends Node
## Settings and input map (bible p.26: every action can be rebound; UI scale;
## subtitles; reduced motion). Persists to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

## action -> [default keys]. Mouse buttons are prefixed "mouse:".
const ACTIONS := {
	"move_forward": ["W", "Up"], "move_back": ["S", "Down"], "move_left": ["A", "Left"], "move_right": ["D", "Right"],
	"sprint": ["Shift"], "interact": ["E"], "journal": ["Tab"], "pause": ["Escape"],
	"colony_mode": ["B"], "rotate_cam_left": ["Q"], "rotate_cam_right": ["E"], "rotate_building": ["R"],
	"confirm": ["mouse:1"], "cancel": ["mouse:2"], "autopilot": ["F"], "speed_pause": ["Space"],
	"speed_1": ["1"], "speed_3": ["3"], "drone_refill": ["G"], "ascend": ["Space"], "descend": ["Ctrl"],
}
const ACTION_LABELS := {
	"move_forward": "Frem", "move_back": "Tilbage", "move_left": "Venstre", "move_right": "Højre",
	"sprint": "Løb", "interact": "Interagér", "journal": "Journal", "pause": "Pause / tilbage",
	"colony_mode": "Kolonitilstand", "rotate_cam_left": "Drej kamera venstre", "rotate_cam_right": "Drej kamera højre",
	"rotate_building": "Drej bygning", "confirm": "Bekræft", "cancel": "Fortryd", "autopilot": "Autopilot",
	"speed_pause": "Pause tid", "speed_1": "Hastighed 1x", "speed_3": "Hastighed 3x", "drone_refill": "Dronereserve",
	"ascend": "Stig (flyvning)", "descend": "Dyk (flyvning)",
}

var values := {
	"master_volume": 0.9, "music_volume": 0.6, "sfx_volume": 0.9, "ambience_volume": 0.7, "ui_volume": 0.8,
	"ui_scale": 1.0, "subtitle_size": 22, "subtitles": true, "reduced_motion": false, "mouse_sensitivity": 0.25,
	"invert_y": false, "fullscreen": false, "camera_shake": true,
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
	get_tree().root.content_scale_factor = float(values["ui_scale"])
	if not DisplayServer.get_name() == "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and (values["fullscreen"] or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(mode)


func keys_for(action: String) -> Array:
	return remaps.get(action, ACTIONS.get(action, []))


func apply_input_map() -> void:
	for action: String in ACTIONS.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for k: String in keys_for(action):
			var ev := _event_for(k)
			if ev:
				InputMap.action_add_event(action, ev)


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
		return {1: "Venstre klik", 2: "Højre klik", 3: "Midterklik"}.get((ev as InputEventMouseButton).button_index, "Mus")
	return "?"


func binding_text(action: String) -> String:
	var parts: Array = []
	for k: String in keys_for(action):
		if k.begins_with("mouse:"):
			parts.append({"1": "Venstre klik", "2": "Højre klik"}.get(k.substr(6), "Mus"))
		else:
			parts.append(k)
	return " / ".join(parts)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in values.keys():
		values[k] = cfg.get_value("settings", k, values[k])
	for a: String in ACTIONS.keys():
		if cfg.has_section_key("input", a):
			remaps[a] = cfg.get_value("input", a)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k: String in values.keys():
		cfg.set_value("settings", k, values[k])
	for a: String in remaps.keys():
		cfg.set_value("input", a, remaps[a])
	cfg.save(PATH)
