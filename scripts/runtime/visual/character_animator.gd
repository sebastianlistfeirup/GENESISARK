class_name CharacterAnimator
extends RefCounted
## Drives an imported character's AnimationPlayer from gameplay state
## (data/art/animation_map.json). The controller owns position (in-place
## locomotion); this only picks clips and scales playback to the real speed so
## feet do not slide. Proxies without an AnimationPlayer are ignored silently.

const LIBRARIES := "res://data/art/animation_libraries.json"
const LIB_NAME := "ga"

static var _map: Dictionary = {}
static var _libraries: Variant = null  # slot -> AnimationLibrary path (tools/synty build)

var player: AnimationPlayer
var cfg: Dictionary = {}
var current := ""
## "ga/" when the slot uses a built AnimationLibrary: clips are then named after states.
var prefix := ""


static func for_slot(slot: VisualSlot) -> CharacterAnimator:
	if _map.is_empty():
		var v: Variant = DictUtil.load_json("res://data/art/animation_map.json")
		_map = v if v is Dictionary else {"_": {}}
	var a := CharacterAnimator.new()
	a.cfg = DictUtil.get_dict(_map, slot.slot_id)
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


## state: "idle" | "walk" | "run" | "interact" | "sample" | "build"; speed in m/s.
func update(state: String, speed: float) -> void:
	if not active():
		return
	var st: Dictionary = DictUtil.get_dict(cfg, state)
	if st.is_empty():
		st = DictUtil.get_dict(cfg, "idle")
	var clip := str(st.get("clip", ""))
	if not prefix.is_empty():
		clip = prefix + state if player.has_animation(prefix + state) else prefix + "idle"
	if clip.is_empty() or not player.has_animation(clip):
		return
	if clip != current:
		player.play(clip, DictUtil.get_float(cfg, "blend_s", 0.2))
		current = clip
	var ref := DictUtil.get_float(st, "speed_ref", 0.0)
	player.speed_scale = clampf(speed / ref, 0.5, 1.8) if ref > 0.0 and speed > 0.05 else 1.0
