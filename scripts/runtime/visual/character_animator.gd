class_name CharacterAnimator
extends RefCounted
## Drives an imported character's AnimationPlayer from gameplay state
## (data/art/animation_map.json). The controller owns position (in-place
## locomotion); this only picks clips and scales playback to the real speed so
## feet do not slide. Proxies without an AnimationPlayer are ignored silently.

static var _map: Dictionary = {}

var player: AnimationPlayer
var cfg: Dictionary = {}
var current := ""


static func for_slot(slot: VisualSlot) -> CharacterAnimator:
	if _map.is_empty():
		var v: Variant = DictUtil.load_json("res://data/art/animation_map.json")
		_map = v if v is Dictionary else {"_": {}}
	var a := CharacterAnimator.new()
	a.cfg = DictUtil.get_dict(_map, slot.slot_id)
	a.player = _find_player(slot)
	return a


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
	if clip.is_empty() or not player.has_animation(clip):
		return
	if clip != current:
		player.play(clip, DictUtil.get_float(cfg, "blend_s", 0.2))
		current = clip
	var ref := DictUtil.get_float(st, "speed_ref", 0.0)
	player.speed_scale = clampf(speed / ref, 0.5, 1.8) if ref > 0.0 and speed > 0.05 else 1.0
