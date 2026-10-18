class_name AnimationLibraryBuilder
extends RefCounted
## Collects retargeted clips into one AnimationLibrary per character slot, named
## after the game's animation states (idle, walk, run, interact, sample, build),
## so CharacterAnimator can play them on any humanoid wrapper.
## Locomotion is made in-place (bible p.24-25): the Hips' forward/sideways travel
## is removed; the controller moves the character, the clip only animates it.

const LIB_DIR := "res://art/animations/"
const LIBRARIES := CharacterAnimator.LIBRARIES
const LOOPING := ["idle", "walk", "run", "sample", "build"]


## states: {state: "res://.../A_Walk_01.gltf" or {source, clip}}. Returns a report.
static func build(slot: String, states: Dictionary, out_dir: String = LIB_DIR) -> Dictionary:
	var lib := AnimationLibrary.new()
	var report := {"slot": slot, "ok": true, "clips": {}, "errors": []}
	for state: String in states.keys():
		var spec: Variant = states[state]
		var src := str(spec.get("source", "")) if spec is Dictionary else str(spec)
		var clip := str(spec.get("clip", "")) if spec is Dictionary else ""
		var anim := _take_clip(src, clip)
		if anim == null:
			report["errors"].append("%s: no clip in %s" % [state, src])
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if state in LOOPING else Animation.LOOP_NONE
		var travel := make_in_place(anim)
		lib.add_animation(state, anim)
		report["clips"][state] = {"source": src, "length_s": snappedf(anim.length, 0.01), "removed_travel_m": snappedf(travel, 0.01),
			"retargeted": _is_retargeted(anim)}
	if lib.get_animation_list().is_empty():
		report["ok"] = false
		return report
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var path := out_dir.path_join(slot + ".res")
	ResourceSaver.save(lib, path)
	report["library"] = path
	return report


static func _take_clip(src: String, clip: String) -> Animation:
	if not ResourceLoader.exists(src):
		return null
	var root := (load(src) as PackedScene).instantiate()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	var out: Animation = null
	if not players.is_empty():
		var ap: AnimationPlayer = players[0]
		for n: StringName in ap.get_animation_list():
			if n == &"RESET":
				continue
			if clip.is_empty() or String(n) == clip or String(n).ends_with("/" + clip):
				out = (ap.get_animation(n).duplicate(true)) as Animation
				break
	root.free()
	return out


## Removes horizontal root travel from the Hips position track. Returns metres removed.
static func make_in_place(anim: Animation) -> float:
	var removed := 0.0
	for t: int in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var p := String(anim.track_get_path(t))
		if not (p.ends_with(":Hips") or p.ends_with(":hips")):
			continue
		var n := anim.track_get_key_count(t)
		if n == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		var last: Vector3 = anim.track_get_key_value(t, n - 1)
		removed = Vector2(last.x - first.x, last.z - first.z).length()
		for k: int in n:
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
	return removed


static func _is_retargeted(anim: Animation) -> bool:
	for t: int in anim.get_track_count():
		if String(anim.track_get_path(t)).begins_with("%GeneralSkeleton:"):
			return true
	return false


static func load_mappings(path: String = LIBRARIES) -> Dictionary:
	var v: Variant = DictUtil.load_json(path) if FileAccess.file_exists(path) else null
	return DictUtil.get_dict(v, "libraries") if v is Dictionary else {}


static func save_mappings(m: Dictionary, path: String = LIBRARIES) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_note": "Written by the Synty builder: character slot -> AnimationLibrary (states as clip names).", "libraries": m}, " ", true) + "\n")
	f.close()
