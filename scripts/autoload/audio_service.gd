extends Node
## Audio groups and placeholder sounds (bible p.13: lonely ark -> inhabited
## colony; critical alarms are unambiguous and never spam). Every sound is a
## named slot; replace files via data/art/audio_slots.json without code changes.

const BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]
const DEFAULT_DIR := "res://assets/audio/placeholder/"
const FINAL_DIR := "res://assets/audio/final/"
const ALARM_COOLDOWN_MS := 6000

## Every alarm sound has a visual twin (bible p.26); GameHud shows it.
signal alarm_raised(critical: bool)

var _players: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _cache: Dictionary = {}
var _overrides: Dictionary = {}
var _last_alarm: Dictionary = {}
var _voice: AudioStreamPlayer
var _layer: AudioStreamPlayer   # second ambience bed (embryo bank, hazard zone, colony people)
var _layer_slot := ""
var _stinger: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


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
	_layer = AudioStreamPlayer.new()
	_layer.bus = "Ambience"
	add_child(_layer)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = "Music"
	add_child(_stinger)
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
	if s is AudioStreamOggVorbis and loops(slot):
		var o := (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		o.loop = true
		s = o
	if s is AudioStreamWAV and loops(slot):
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
		s = w
	_cache[slot] = s
	return s


## Beds and music loop; endings, stingers and one-shots play once.
static func loops(slot: String) -> bool:
	if slot.begins_with("music_ending_"):
		return false
	return slot.begins_with("amb_") or slot.begins_with("music_") or slot.ends_with("_loop") or slot == "sfx_thruster"


func play(slot: String, bus: String = "SFX", volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := stream(slot)
	if s == null:
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = s
			p.bus = bus
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Random take among <slot>, <slot>_01 ... <slot>_06 that exist, with a small
## pitch spread, so repeated sounds (footsteps) never machine-gun.
func play_variant(slot: String, bus: String = "SFX", volume_db: float = 0.0) -> void:
	var takes: Array = variants(slot)
	if takes.is_empty():
		return
	play(str(takes[_rng.randi() % takes.size()]), bus, volume_db, _rng.randf_range(0.94, 1.06))


func variants(slot: String) -> Array:
	var key := "#variants:" + slot
	if not _cache.has(key):
		var out: Array = []
		for sl: String in [slot] + range(1, 7).map(func(i: int) -> String: return "%s_%02d" % [slot, i]):
			if stream(sl) != null:
				out.append(sl)
		_cache[key] = out
	return _cache[key]


## Second ambience bed on top of the main one, crossfaded. "" fades it out.
func set_layer(slot: String, volume_db: float = -6.0) -> void:
	if slot == _layer_slot:
		return
	_layer_slot = slot
	var s := stream(slot) if not slot.is_empty() else null
	var fast := bool(SettingsService.get_value("reduced_motion", false))
	var t := create_tween()
	if _layer.playing:
		t.tween_property(_layer, "volume_db", -40.0, 0.1 if fast else 0.8)
	t.tween_callback(func() -> void:
		_layer.stream = s
		if s:
			_layer.volume_db = -40.0
			_layer.play()
		else:
			_layer.stop())
	if s:
		t.tween_property(_layer, "volume_db", volume_db, 0.1 if fast else 1.2)


func layer_slot() -> String:
	return _layer_slot


## Short musical sting over the music bed (critical events). Never stacks.
func stinger(slot: String) -> void:
	var s := stream(slot)
	if s == null or _stinger.playing:
		return
	_stinger.stream = s
	_stinger.volume_db = -4.0
	_stinger.play()


## Positional loop/one-shot attached to a 3D node (construction sites). The
## caller owns the returned player; it frees with its parent.
func play_at(slot: String, parent: Node3D, volume_db: float = 0.0, max_distance: float = 60.0) -> AudioStreamPlayer3D:
	var s := stream(slot)
	if s == null or parent == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 8.0
	parent.add_child(p)
	p.play()
	return p


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
	alarm_raised.emit(critical)


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


## Voice-over for one story line (assets/audio/vo/<line_id>.ogg|.wav; other
## languages in assets/audio/vo/<lang>/, falling back to the Danish recording).
## Returns its length in seconds, or 0 if no recording exists (subtitles only).
func play_voice(line_id: String) -> float:
	var dirs: Array = ["res://assets/audio/vo/"]
	if not Loc.is_source():
		dirs.push_front("res://assets/audio/vo/%s/" % Loc.lang())
	for path: String in voice_candidates(line_id, dirs):
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


static func voice_candidates(line_id: String, dirs: Array) -> Array:
	var out: Array = []
	for d: String in dirs:
		for ext: String in [".ogg", ".wav", ".mp3"]:
			out.append(d + line_id + ext)
	return out


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
