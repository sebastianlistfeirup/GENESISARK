class_name CharacterAnimator
extends RefCounted
## Drives an imported character's AnimationPlayer from gameplay state
## (data/art/animation_map.json). The controller owns position (in-place
## locomotion, bible p.24-25); this only picks clips and scales playback to the
## real speed so feet do not slide. Proxies without an AnimationPlayer are ignored.
##
## D-040 animation pass:
##  - gaits: "walk"/"run" requests pick the library clip (walk_slow, walk_mid, walk,
##    run) whose measured speed_ref is nearest the gait speed, keep the phase when
##    switching, and play at speed / speed_ref (tools/anim_probe.gd measures refs);
##  - stops: going idle from a gait plays stop_<gait>_<foot> with distance matching:
##    the clip is held at the point whose remaining travel equals the controller's
##    remaining stopping distance, so the planted foot stays put while braking;
##  - turns: turn_l / turn_r play at the real yaw rate (speed = rad/s);
##  - idle: seeded start phase and tempo, occasional idle_alt_* one-shots on a
##    seeded timer, so a crowd never moves in lockstep;
##  - blend times come from the slot's "blend" table ("from>to" by state family).

const LIBRARIES := "res://data/art/animation_libraries.json"
const LIB_NAME := "ga"
## Playback range for speed matching; outside it a different gait clip is due.
const PLAYBACK_MIN := 0.6
const PLAYBACK_MAX := 1.5
## Library clips that are gaits (cycles with a measured speed_ref).
const GAITS := ["walk_slow", "walk_mid", "walk", "run"]
const DEFAULT_IDLE_ALT_EVERY := [7.0, 16.0]

static var _map: Dictionary = {}
static var _libraries: Variant = null  # slot -> AnimationLibrary path (tools/synty build)

var player: AnimationPlayer
var cfg: Dictionary = {}
var current := ""
## "ga/" when the slot uses a built AnimationLibrary: clips are then named after states.
var prefix := ""
## Deterministic per character (slot id + variant + spawn position by default).
var anim_seed := 0

var _rng := RandomNumberGenerator.new()
var _seeded := false
var _last_ms := -1
var _idle_wait := -1.0
var _stop_t := 0.0  # distance-matched time in the active stop clip
var _stop_braking := false


static func for_slot(slot: VisualSlot, seed_override: int = -1) -> CharacterAnimator:
	if _map.is_empty():
		var v: Variant = DictUtil.load_json("res://data/art/animation_map.json")
		_map = v if v is Dictionary else {"_": {}}
	var a := CharacterAnimator.new()
	a.cfg = DictUtil.get_dict(_map, slot.slot_id)
	a.anim_seed = seed_override if seed_override >= 0 else hash("%s|%s|%s" % [slot.slot_id, slot.variant, slot.position.snapped(Vector3.ONE * 0.1)])
	if _libraries == null:
		var lv: Variant = DictUtil.load_json(LIBRARIES) if FileAccess.file_exists(LIBRARIES) else null
		_libraries = DictUtil.get_dict(lv, "libraries") if lv is Dictionary else {}
	var lib_path := str((_libraries as Dictionary).get(slot.slot_id, ""))
	if not lib_path.is_empty() and ResourceLoader.exists(lib_path):
		a.player = attach(slot, load(lib_path))
		if a.player:
			a.prefix = LIB_NAME + "/"
			if a.cfg.is_empty():
				a.cfg = {"idle": {}, "walk": {"speed_ref": 1.5}, "run": {"speed_ref": 4.5}, "blend_s": 0.2}
	if a.player == null:
		a.player = _find_player(slot)
	return a


## Gives a retargeted humanoid (skeleton "GeneralSkeleton", see tools/synty/humanoid_bone_mapper.gd)
## an AnimationPlayer with the slot's library. Null if the model has no such rig.
static func attach(model_root: Node, library: AnimationLibrary) -> AnimationPlayer:
	var skels := model_root.find_children("GeneralSkeleton", "Skeleton3D", true, false)
	if skels.is_empty() or library == null:
		return null
	var owner_node: Node = skels[0].owner if skels[0].owner else model_root
	var ap := AnimationPlayer.new()
	ap.name = "GAAnimations"
	owner_node.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library(LIB_NAME, library)
	return ap


static func _find_player(n: Node) -> AnimationPlayer:
	for c: Node in n.get_children():
		if c is AnimationPlayer:
			return c
		var deep := _find_player(c)
		if deep:
			return deep
	return null


func active() -> bool:
	return player != null and not cfg.is_empty()


## state: "idle" | "walk" | "run" | "interact" | "sample" | "build" | "turn_l" | "turn_r".
## speed: ground speed in m/s (turns: yaw rate in rad/s).
## gait_speed: the speed the character is heading for (input intent); picks the gait
##   clip without flicker while accelerating. Default: speed.
## stop_distance: metres left until standstill (controller knows its braking); enables
##   distance-matched stop clips. -1 = unknown (plain blend to idle).
func update(state: String, speed: float, gait_speed: float = -1.0, stop_distance: float = -1.0) -> void:
	if not active():
		return
	if not _seeded:
		_rng.seed = anim_seed
		_seeded = true
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last_ms) / 1000.0, 0.0, 0.1) if _last_ms >= 0 else 0.0
	_last_ms = now
	if prefix.is_empty():
		_update_named_clip(state, speed)
		return
	if state in ["walk", "run"] and speed > 0.05:
		_locomote(state, speed, gait_speed if gait_speed > 0.0 else speed)
		return
	if state == "idle":
		if _stopping(speed, stop_distance):
			return
		_idle(dt)
		return
	if state.begins_with("turn_"):
		_turn(state, speed)
		return
	var key := state if _has(state) else "idle"
	_play(key)
	player.speed_scale = 1.0


# ---------------------------------------------------------------- states

func _locomote(state: String, speed: float, gait_speed: float) -> void:
	var gait := _pick_gait(state, gait_speed)
	var ref := _ref(gait)
	if gait != _state_of(current):
		var phase := -1.0
		if _state_of(current) in GAITS and player.current_animation != "":
			phase = player.current_animation_position / maxf(player.current_animation_length, 0.001)
		_play(gait, phase)
	player.speed_scale = clampf(speed / ref, PLAYBACK_MIN, PLAYBACK_MAX) if ref > 0.0 else 1.0


## Nearest measured speed_ref in log space, with hysteresis so gaits do not flicker.
func _pick_gait(state: String, v: float) -> String:
	var best := state if _has(state) else ""
	var best_err := INF
	var cur := _state_of(current)
	for g: String in GAITS:
		if not _has(g) or _ref(g) <= 0.0:
			continue
		if state == "walk" and g == "run":
			continue  # a walk request never sprints
		var err := absf(log(maxf(v, 0.05) / _ref(g)))
		if g == cur:
			err -= 0.15
		if err < best_err:
			best_err = err
			best = g
	return best if not best.is_empty() else "idle"


func _stopping(speed: float, stop_distance: float) -> bool:
	var cur := _state_of(current)
	if cur.begins_with("stop_"):
		var clip_len := player.current_animation_length
		if _stop_braking and speed > 0.05 and stop_distance >= 0.0:
			_stop_t = maxf(_stop_t, _time_at_remaining(cur, stop_distance))
			player.speed_scale = 0.0
			player.seek(minf(_stop_t, clip_len), true)
			return true
		_stop_braking = false
		player.speed_scale = 1.0
		if player.current_animation_position < clip_len - _blend(cur, "idle"):
			return true
		return false  # play out, then idle blends in
	if cur in GAITS and stop_distance > 0.05 and speed > 0.3:
		var clip := "stop_%s_%s" % [cur, _stop_foot(cur)]
		if _has(clip) and not DictUtil.get_dict(cfg, clip).get("travel_curve", []).is_empty():
			_stop_t = _time_at_remaining(clip, stop_distance)
			_stop_braking = true
			_play(clip)
			player.speed_scale = 0.0
			player.seek(_stop_t, true)
			return true
	return false


## Which foot is planted now in the gait cycle (measured left-contact phase).
func _stop_foot(gait: String) -> String:
	var lcs := DictUtil.get_float(DictUtil.get_dict(cfg, gait), "left_contact_phase", 0.0)
	var p := player.current_animation_position / maxf(player.current_animation_length, 0.001)
	return "l" if fposmod(p - lcs, 1.0) < 0.5 else "r"


## travel_curve: metres travelled since the clip start, every curve_step_s (root-motion twin).
func _time_at_remaining(clip: String, remaining: float) -> float:
	var c: Dictionary = DictUtil.get_dict(cfg, clip)
	var curve: Array = c.get("travel_curve", [])
	var step := DictUtil.get_float(c, "curve_step_s", 0.1)
	if curve.is_empty():
		return 0.0
	var total := float(curve[curve.size() - 1])
	var want := clampf(total - remaining, 0.0, total)
	for i: int in range(1, curve.size()):
		var a := float(curve[i - 1])
		var b := float(curve[i])
		if want <= b:
			return (i - 1 + (want - a) / maxf(b - a, 0.0001)) * step
	return (curve.size() - 1) * step


func _idle(dt: float) -> void:
	var cur := _state_of(current)
	if cur.begins_with("idle_alt"):
		player.speed_scale = 1.0
		if player.current_animation_position < player.current_animation_length - _blend(cur, "idle"):
			return
		cur = ""
	if cur != "idle":
		_play("idle", _rng.randf())  # seeded phase: a crowd that stops together still breathes apart
		_idle_wait = -1.0
	player.speed_scale = DictUtil.get_float(cfg, "idle_tempo", 1.0) * (0.92 + 0.16 * fposmod(float(anim_seed % 997) / 997.0, 1.0))
	var alts := _alts()
	if alts.is_empty():
		return
	if _idle_wait < 0.0:
		var every: Array = cfg.get("idle_alt_every_s", DEFAULT_IDLE_ALT_EVERY)
		_idle_wait = _rng.randf_range(float(every[0]), float(every[1]))
	_idle_wait -= dt
	if _idle_wait <= 0.0:
		_idle_wait = -1.0
		_play(alts[_rng.randi() % alts.size()])
		player.speed_scale = 1.0


func _turn(state: String, yaw_rate: float) -> void:
	if not _has(state):
		_idle(0.0)
		return
	var clip_rate := DictUtil.get_float(DictUtil.get_dict(cfg, state), "yaw_rate", PI / 2.0 / 0.97)
	if _state_of(current) != state or player.current_animation_position >= player.current_animation_length - 0.05:
		_play(state)
	player.speed_scale = clampf(absf(yaw_rate) / clip_rate, 1.0, DictUtil.get_float(cfg, "turn_playback_max", 2.2))


## Old path: a model with its own AnimationPlayer and clip names from the map.
func _update_named_clip(state: String, speed: float) -> void:
	var st: Dictionary = DictUtil.get_dict(cfg, state)
	if st.is_empty():
		st = DictUtil.get_dict(cfg, "idle")
	var clip := str(st.get("clip", ""))
	if clip.is_empty() or not player.has_animation(clip):
		return
	if clip != current:
		player.play(clip, DictUtil.get_float(cfg, "blend_s", 0.2))
		current = clip
	var ref := DictUtil.get_float(st, "speed_ref", 0.0)
	player.speed_scale = clampf(speed / ref, PLAYBACK_MIN, PLAYBACK_MAX) if ref > 0.0 and speed > 0.05 else 1.0


# ---------------------------------------------------------------- helpers

func _play(state: String, phase: float = -1.0) -> void:
	var from := _state_of(current)
	var clip := prefix + state
	player.play(clip, _blend(from, state))
	if phase >= 0.0:
		player.seek(fposmod(phase, 1.0) * player.current_animation_length, true)
	current = clip


func _has(state: String) -> bool:
	return player.has_animation(prefix + state)


func _ref(state: String) -> float:
	return DictUtil.get_float(DictUtil.get_dict(cfg, state), "speed_ref", 0.0)


func _state_of(clip: String) -> String:
	return clip.trim_prefix(prefix)


func _alts() -> Array:
	var out: Array = []
	for n: StringName in player.get_animation_library(LIB_NAME).get_animation_list():
		if String(n).begins_with("idle_alt"):
			out.append(String(n))
	return out


static func family(state: String) -> String:
	if state in GAITS:
		return "move"
	for f: String in ["stop", "turn", "idle_alt"]:
		if state.begins_with(f):
			return f
	return state


## Blend time (s) from the slot's "blend" table: "from>to" by family, then "*>to",
## "from>*", "default"; falls back to the legacy "blend_s".
func _blend(from: String, to: String) -> float:
	if from.is_empty():
		return 0.0  # first clip: no pose to blend from
	var table: Dictionary = DictUtil.get_dict(cfg, "blend")
	var fa := family(from)
	var fb := family(to)
	for k: String in ["%s>%s" % [fa, fb], "*>%s" % fb, "%s>*" % fa, "default"]:
		if table.has(k):
			return float(table[k])
	return DictUtil.get_float(cfg, "blend_s", 0.2)
