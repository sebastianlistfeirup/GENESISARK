extends Node
## Audio groups and placeholder sounds (bible p.13: lonely ark -> inhabited
## colony; critical alarms are unambiguous and never spam). Every sound is a
## named slot; replace files via data/art/audio_slots.json without code changes.

const BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]
const DEFAULT_DIR := "res://assets/audio/placeholder/"
const ALARM_COOLDOWN_MS := 6000

var _players: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _cache: Dictionary = {}
var _overrides: Dictionary = {}
var _last_alarm: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var ov: Variant = DictUtil.load_json("res://data/art/audio_slots.json")
	if ov is Dictionary:
		_overrides = DictUtil.get_dict(ov, "slots")
	for i: int in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	SettingsService.changed.connect(apply_volumes)
	apply_volumes()


func apply_volumes() -> void:
	_set_bus("Master", float(SettingsService.get_value("master_volume", 1.0)))
	_set_bus("Music", float(SettingsService.get_value("music_volume", 1.0)))
	_set_bus("SFX", float(SettingsService.get_value("sfx_volume", 1.0)))
	_set_bus("Ambience", float(SettingsService.get_value("ambience_volume", 1.0)))
	_set_bus("UI", float(SettingsService.get_value("ui_volume", 1.0)))


func _set_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func stream(slot: String) -> AudioStream:
	if _cache.has(slot):
		return _cache[slot]
	var path := str(_overrides.get(slot, DEFAULT_DIR + slot + ".wav"))
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamWAV and (slot.begins_with("amb_") or slot.begins_with("music_") or slot == "sfx_thruster"):
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
		s = w
	_cache[slot] = s
	return s


func play(slot: String, bus: String = "SFX", volume_db: float = 0.0) -> void:
	var s := stream(slot)
	if s == null:
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = s
			p.bus = bus
			p.volume_db = volume_db
			p.play()
			return


func ui(slot: String) -> void:
	play(slot, "UI", -4.0)


## Alarms have a cooldown per type so they never spam (bible p.13).
func alarm(critical: bool) -> void:
	var key := "alarm_critical" if critical else "alarm_warning"
	var now := Time.get_ticks_msec()
	if now - int(_last_alarm.get(key, -ALARM_COOLDOWN_MS)) < ALARM_COOLDOWN_MS:
		return
	_last_alarm[key] = now
	play(key, "SFX", -2.0)


func set_ambience(slot: String) -> void:
	var s := stream(slot) if not slot.is_empty() else null
	if _ambience.stream == s and _ambience.playing:
		return
	_ambience.stream = s
	if s:
		_ambience.play()
	else:
		_ambience.stop()


func set_music(slot: String) -> void:
	var s := stream(slot) if not slot.is_empty() else null
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.volume_db = -8.0
	if s:
		_music.play()
	else:
		_music.stop()
