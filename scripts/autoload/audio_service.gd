extends Node
## Audio groups and placeholder sounds (bible p.13: lonely ark -> inhabited
## colony; critical alarms are unambiguous and never spam). Every sound is a
## named slot; replace files via data/art/audio_slots.json without code changes.

const BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]
const DEFAULT_DIR := "res://assets/audio/placeholder/"
const FINAL_DIR := "res://assets/audio/final/"
const ALARM_COOLDOWN_MS := 6000
## Mix trims (D-064) on top of the player's sliders, set from the in-game loudness
## check: the score and the beds sit under the voice, effects in between.
const MIX_TRIM_DB := {"Music": 6.0, "SFX": 0.0, "Ambience": 3.0, "UI": 0.0, "Voice": 0.0}
## Ducking (D-064): while a voice line plays, music and ambience dip so every line
## is intelligible; fast attack, slow release.
const DUCK_DB := {"Music": -8.0, "Ambience": -6.0, "SFX": -2.0}
const DUCK_ATTACK := 0.25
const DUCK_RELEASE := 0.9

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
var _duck := 0.0          # 0 = open, 1 = fully ducked under a voice line
var _music_slot := ""
var _ambience_slot := ""
var _last_ui: Dictionary = {}  # slot -> ticks of its last play (ui_soft cooldown)
var _log_plays := false   # evidence captures only: which cues fired (DebugCapture prints it)
var played: Dictionary = {}  # slot -> count, while _log_plays


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# ARK's voice: its own bus into Voice (so the voice volume still governs it) with a
	# light ship-AI colour — a thin band cut, a whisper of chorus and a small metal
	# room. Recordings stay clean (VO_SCRIPT direction).
	if AudioServer.get_bus_index("VoiceArk") == -1:
		AudioServer.add_bus()
		var ai := AudioServer.bus_count - 1
		AudioServer.set_bus_name(ai, "VoiceArk")
		AudioServer.set_bus_send(ai, "Voice")
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 140.0
		AudioServer.add_bus_effect(ai, hp)
		var ch := AudioEffectChorus.new()
		ch.voice_count = 2
		ch.wet = 0.18
		ch.dry = 1.0
		AudioServer.add_bus_effect(ai, ch)
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.32
		rv.damping = 0.6
		rv.wet = 0.12
		rv.dry = 1.0
		AudioServer.add_bus_effect(ai, rv)
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
	_log_plays = DebugCapture.requested()
	SettingsService.changed.connect(apply_volumes)
	apply_volumes()


func apply_volumes() -> void:
	_set_bus("Master", float(SettingsService.get_value("master_volume", 1.0)))
	_set_bus("Music", float(SettingsService.get_value("music_volume", 1.0)))
	_set_bus("SFX", float(SettingsService.get_value("sfx_volume", 1.0)))
	_set_bus("Ambience", float(SettingsService.get_value("ambience_volume", 1.0)))
	_set_bus("UI", float(SettingsService.get_value("ui_volume", 1.0)))
	_set_bus("Voice", float(SettingsService.get_value("voice_volume", 1.0)))


func _set_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)) + float(MIX_TRIM_DB.get(bus, 0.0)) + duck_offset_db(bus, _duck))


## How far `bus` sits under a voice line at duck amount k (0..1).
static func duck_offset_db(bus: String, k: float) -> float:
	return float(DUCK_DB.get(bus, 0.0)) * clampf(k, 0.0, 1.0)


func voice_playing() -> bool:
	return _voice != null and _voice.playing


func _process(delta: float) -> void:
	var want := 1.0 if voice_playing() else 0.0
	if is_equal_approx(want, _duck):
		return
	_duck = move_toward(_duck, want, delta / (DUCK_ATTACK if want > _duck else DUCK_RELEASE))
	for b: String in DUCK_DB.keys():
		_set_bus(b, float(SettingsService.get_value(b.to_lower() + "_volume", 1.0)))


func duck_amount() -> float:
	return _duck


func music_slot() -> String:
	return _music_slot if _music.playing else ""


func ambience_slot() -> String:
	return _ambience_slot if _ambience.playing else ""


func stream(slot: String) -> AudioStream:
	if _cache.has(slot):
		return _cache[slot]
	# Lookup order: explicit override -> finished sound in assets/audio/final/
	# (ogg/mp3/wav) -> synthesized placeholder. Dropping a file in "final" is enough.
	var path := str(_overrides.get(slot, ""))
	if path.is_empty():
		for cand: String in [FINAL_DIR + slot + ".ogg", FINAL_DIR + slot + ".mp3", FINAL_DIR + slot + ".wav", DEFAULT_DIR + slot + ".wav"]:
			if ResourceLoader.exists(cand):
				path = cand
				break
	var s: AudioStream = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis and loops(slot):
		var o := (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		o.loop = true
		s = o
	if s is AudioStreamMP3 and loops(slot):
		var m := (s as AudioStreamMP3).duplicate() as AudioStreamMP3
		m.loop = true
		s = m
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
	if _log_plays:
		played[slot] = int(played.get(slot, 0)) + 1
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


## Fire-and-forget positional one-shot (D-064): a 3D player under `where` that
## frees itself when done. `slot` may name a variant family (slot_01..06) without
## a base file; a random take is picked. Missing sound -> nothing (fresh clone).
func play_3d(slot: String, where: Node3D, volume_db: float = 0.0, max_distance: float = 60.0, pitch: float = 1.0,
		bus: String = "SFX", unit_size: float = 8.0) -> AudioStreamPlayer3D:
	var pick := slot
	if stream(slot) == null:
		var takes: Array = variants(slot)
		if takes.is_empty():
			return null
		pick = str(takes[_rng.randi() % takes.size()])
	if where == null or not where.is_inside_tree():
		return null
	if _log_plays:
		played[pick] = int(played.get(pick, 0)) + 1
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(pick)
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.finished.connect(p.queue_free)
	where.add_child(p)
	p.play()
	return p


## First slot of `slots` that exists plays (new finals with an old fallback).
func play_any(slots: Array, bus: String = "SFX", volume_db: float = 0.0, pitch: float = 1.0) -> void:
	for sl: Variant in slots:
		if has_sound(str(sl)):
			play(str(sl), bus, volume_db, pitch)
			return


func ui(slot: String) -> void:
	play(slot, "UI", -4.0)


## Quiet UI accent with its own cooldown, so panels booting together make one
## sound, not a burst (holo boot-in, location card).
func ui_soft(slot: String, volume_db: float = -10.0, cooldown_ms: int = 350) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_ui.get(slot, -cooldown_ms)) < cooldown_ms:
		return
	_last_ui[slot] = now
	play(slot, "UI", volume_db)


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
				_voice.process_mode = Node.PROCESS_MODE_PAUSABLE  # holds with its subtitle while the pause menu is open
				add_child(_voice)
			_voice.stream = st
			_voice.bus = "VoiceArk" if _speaker_of(line_id) == "ARK" else "Voice"
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
	_ambience_slot = slot
	_ambience.stream = s
	if s:
		_ambience.play()
	else:
		_ambience.stop()


func set_music(slot: String) -> void:
	var s := stream(slot) if not slot.is_empty() else null
	if _music.stream == s and _music.playing:
		return
	_music_slot = slot
	_music.stream = s
	# The epilogue's theme plays alone (no voice, no bed): it may come up (D-064).
	_music.volume_db = -3.0 if slot.begins_with("music_ending_") else -8.0
	if s:
		_music.play()
	else:
		_music.stop()


var _speakers: Dictionary = {}  # line_id -> speaker (from data/story/scenes.json)


func _speaker_of(line_id: String) -> String:
	if _speakers.is_empty():
		var d: Variant = DictUtil.load_json("res://data/story/scenes.json")
		var scenes: Array = DictUtil.get_arr(d, "scenes") if d is Dictionary else (d if d is Array else [])
		for sc: Variant in scenes:
			var lines: Array = DictUtil.get_arr(sc, "lines")
			for i: int in lines.size():
				_speakers["%s_%02d" % [str((sc as Dictionary).get("id", "")), i + 1]] = str((lines[i] as Dictionary).get("speaker", ""))
	return str(_speakers.get(line_id, ""))
