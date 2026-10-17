extends Node
## Audio groups and placeholder sounds (bible p.13: lonely ark -> inhabited
## colony; critical alarms are unambiguous and never spam). Every sound is a
## named slot; replace files via data/art/audio_slots.json without code changes.

const BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]
const DEFAULT_DIR := "res://assets/audio/placeholder/"
const FINAL_DIR := "res://assets/audio/final/"
const ALARM_COOLDOWN_MS := 6000

var _players: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _cache: Dictionary = {}
var _overrides: Dictionary = {}
var _last_alarm: Dictionary = {}
var _voice: AudioStreamPlayer


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
	# Lookup order: explicit override -> finished sound in assets/audio/final/
	# (ogg/wav) -> synthesized placeholder. Dropping a file in "final" is enough.
	var path := str(_overrides.get(slot, ""))
	if path.is_empty():
		for cand: String in [FINAL_DIR + slot + ".ogg", FINAL_DIR + slot + ".wav", DEFAULT_DIR + slot + ".wav"]:
			if ResourceLoader.exists(cand):
				path = cand
				break
	var s: AudioStream = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis and (slot.begins_with("amb_") or slot.begins_with("music_") or slot.ends_with("_loop") or slot == "sfx_thruster"):
		var o := (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		o.loop = true
		s = o
	if s is AudioStreamWAV and (slot.begins_with("amb_") or slot.begins_with("music_") or slot.ends_with("_loop") or slot == "sfx_thruster"):
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


func has_sound(slot: String) -> bool:
	return stream(slot) != null


## First slot that exists wins, e.g. ["amb_desert", "amb_colony_wind"]: lets
## finished sounds replace placeholders without code changes.
func set_ambience_any(slots: Array) -> void:
	for sl: Variant in slots:
		if has_sound(str(sl)):
			set_ambience(str(sl))
			return


func set_music_any(slots: Array) -> void:
	for sl: Variant in slots:
		if has_sound(str(sl)):
			set_music(str(sl))
			return


## Voice-over for one story line (assets/audio/vo/<line_id>.ogg|.wav).
## Returns its length in seconds, or 0 if no recording exists (subtitles only).
func play_voice(line_id: String) -> float:
	for ext: String in [".ogg", ".wav", ".mp3"]:
		var path := "res://assets/audio/vo/" + line_id + ext
		if ResourceLoader.exists(path):
			var st: AudioStream = load(path)
			if _voice == null:
				_voice = AudioStreamPlayer.new()
				_voice.bus = "Voice"
				add_child(_voice)
			_voice.stream = st
			_voice.play()
			return st.get_length()
	return 0.0


func stop_voice() -> void:
	if _voice:
		_voice.stop()


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
