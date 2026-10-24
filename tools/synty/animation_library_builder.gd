class_name AnimationLibraryBuilder
extends RefCounted
## Collects retargeted clips into one AnimationLibrary per character slot, named
## after the game's animation states (idle, walk, run, interact, sample, build,
## plus polish clips: walk_slow, stop_<gait>_l/r, turn_l/r, idle_alt_*), so
## CharacterAnimator can play them on any humanoid wrapper.
## Locomotion is made in-place (bible p.24-25): the Hips' forward/sideways travel
## is removed; the controller moves the character, the clip only animates it.
##
## A state spec is a path, or {source, clip?, loop?, upper?, lower_bones?, blend_with?, weight?, phase_offset?}:
##   blend_with  - second locomotion cycle blended in at weight (0..1), phase-matched
##                 (AnimationLibraryBuilder.blend): a gait between two Synty gaits.
##   upper       - second clip whose upper body (every bone not in lower_bones)
##                 replaces the source's; the result takes the upper clip's length.
##                 Used for "kneel + work with the hands" from two Synty clips.
##   lower_bones - bones kept from `source` (default LOWER_BODY).

const LIB_DIR := "res://art/animations/"
const LIBRARIES := CharacterAnimator.LIBRARIES
const OVERRIDES := "res://data/art/animation_overrides.json"
const LOOPING := ["idle", "walk", "walk_slow", "walk_mid", "run", "sample", "build"]
const LOWER_BODY := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]


## states: {state: "res://.../A_Walk_01.fbx" or {source, clip, ...}}. Returns a report.
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
		var other := str(spec.get("blend_with", "")) if spec is Dictionary else ""
		if not other.is_empty():
			var ob := _take_clip(other, "")
			if ob == null:
				report["errors"].append("%s: no blend clip in %s" % [state, other])
				continue
			anim = blend(anim, ob, float(spec.get("weight", 0.5)), float(spec.get("phase_offset", 0.0)))
		var upper := str(spec.get("upper", "")) if spec is Dictionary else ""
		if not upper.is_empty():
			var up := _take_clip(upper, "")
			if up == null:
				report["errors"].append("%s: no upper clip in %s" % [state, upper])
				continue
			var lower: Array = spec.get("lower_bones", LOWER_BODY) if spec is Dictionary else LOWER_BODY
			anim = layer(anim, up, lower)
		var loop := state in LOOPING
		if spec is Dictionary and spec.has("loop"):
			loop = bool(spec["loop"])
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		var travel := make_in_place(anim)
		lib.add_animation(state, anim)
		var entry := {"source": src, "length_s": snappedf(anim.length, 0.01), "removed_travel_m": snappedf(travel, 0.01),
			"loop": loop, "retargeted": _is_retargeted(anim)}
		if not upper.is_empty():
			entry["upper"] = upper
		report["clips"][state] = entry
	if lib.get_animation_list().is_empty():
		report["ok"] = false
		return report
	report["ground_fix_m"] = ground_fix(slot, lib)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var path := out_dir.path_join(slot + ".res")
	ResourceSaver.save(lib, path)
	report["library"] = path
	return report


## Feet on the floor: Synty's run/sprint/run-stop clips keep the ball of the foot
## 5-9 cm above the floor on the retargeted rigs (walk and idle touch it), so the
## character hovered while running. Plays each locomotion clip (gaits, stops,
## turns) on the slot's prefab, finds the lowest ball-of-foot height and lowers
## the Hips track so it matches idle's. Returns {clip: metres lowered}.
static func ground_fix(slot: String, lib: AnimationLibrary) -> Dictionary:
	var out := {}
	var prefab := "res://art/prefabs/%s.tscn" % slot
	if not ResourceLoader.exists(prefab) or not lib.has_animation("idle"):
		return out
	var model: Node3D = (load(prefab) as PackedScene).instantiate()
	var found := model.find_children("GeneralSkeleton", "Skeleton3D", true, false)
	if found.is_empty():
		model.free()
		return out
	var sk: Skeleton3D = found[0]
	# Model-space scale of the skeleton (wrapper fit, e.g. x0.66 for children), no tree needed.
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var ref := _toe_min(sk, xf, lib.get_animation("idle"))
	for name: StringName in lib.get_animation_list():
		var s := String(name)
		if not (s in CharacterAnimator.GAITS or s.begins_with("stop_") or s.begins_with("turn_")):
			continue
		var anim := lib.get_animation(name)
		var lift := _toe_min(sk, xf, anim) - ref
		if lift < 0.015:
			continue
		var scale_y := xf.basis.get_scale().y
		for t: int in anim.get_track_count():
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and _bone(anim.track_get_path(t)) == "Hips":
				for k: int in anim.track_get_key_count(t):
					var v: Vector3 = anim.track_get_key_value(t, k)
					anim.track_set_key_value(t, k, v - Vector3(0, lift / scale_y, 0))
		out[s] = snappedf(lift, 0.001)
	model.free()
	return out


## Lowest ball-of-foot height (model space) over the clip, posing the skeleton
## straight from the tracks (own forward kinematics along the toe chains: works
## without a scene tree, where Skeleton3D does not refresh its global poses).
static func _toe_min(sk: Skeleton3D, xf: Transform3D, anim: Animation) -> float:
	var lo := INF
	var tracks := {}  # bone -> [pos track, rot track, scale track]
	for t: int in anim.get_track_count():
		var b := sk.find_bone(_bone(anim.track_get_path(t)))
		if b < 0:
			continue
		var slots: Array = tracks.get(b, [-1, -1, -1])
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D: slots[0] = t
			Animation.TYPE_ROTATION_3D: slots[1] = t
			Animation.TYPE_SCALE_3D: slots[2] = t
		tracks[b] = slots
	var chain := {}
	for toe: String in ["LeftToes", "RightToes"]:
		var b := sk.find_bone(toe)
		while b >= 0:
			chain[b] = true
			b = sk.get_bone_parent(b)
	var order: Array = chain.keys()
	order.sort()  # Skeleton3D keeps parents before children
	for i: int in 61:
		var time := anim.length * i / 60.0
		var glob := {}
		for b: int in order:
			var rest := sk.get_bone_rest(b)
			var pos := rest.origin
			var rot := rest.basis.get_rotation_quaternion()
			var scl := rest.basis.get_scale()
			var tr: Array = tracks.get(b, [-1, -1, -1])
			if tr[0] >= 0: pos = anim.position_track_interpolate(tr[0], time)
			if tr[1] >= 0: rot = anim.rotation_track_interpolate(tr[1], time)
			if tr[2] >= 0: scl = anim.scale_track_interpolate(tr[2], time)
			var local := Transform3D(Basis(rot).scaled(scl), pos)
			var par := sk.get_bone_parent(b)
			glob[b] = (glob[par] as Transform3D) * local if glob.has(par) else local
		for toe: String in ["LeftToes", "RightToes"]:
			var tb := sk.find_bone(toe)
			if glob.has(tb):
				lo = minf(lo, (xf * (glob[tb] as Transform3D)).origin.y)
	return lo


## Every source file a spec needs (for retargeting before the build).
static func spec_sources(spec: Variant) -> Array:
	if spec is Dictionary:
		var out := [str(spec.get("source", ""))]
		for k: String in ["upper", "blend_with"]:
			if not str(spec.get(k, "")).is_empty():
				out.append(str(spec[k]))
		return out
	return [str(spec)]


## The "animations" section of synty_choices.json with data/art/animation_overrides.json
## merged over it: per slot, override states replace or add states; "status" too.
## A state set to null in the overrides removes it.
static func merged_animations(choices_anims: Dictionary, overrides_path: String = OVERRIDES) -> Dictionary:
	var out := choices_anims.duplicate(true)
	var ov: Variant = DictUtil.load_json(overrides_path) if FileAccess.file_exists(overrides_path) else null
	if not ov is Dictionary:
		return out
	var slots: Dictionary = DictUtil.get_dict(ov, "animations")
	for slot: String in slots.keys():
		var o: Dictionary = slots[slot]
		var base: Dictionary = out.get(slot, {"status": "approved", "states": {}})
		var states: Dictionary = DictUtil.get_dict(base, "states").duplicate(true)
		var ostates: Dictionary = DictUtil.get_dict(o, "states")
		for st: String in ostates.keys():
			if ostates[st] == null:
				states.erase(st)
			else:
				states[st] = ostates[st]
		base["states"] = states
		if o.has("status"):
			base["status"] = o["status"]
		out[slot] = base
	return out


## Phase-matched pose blend of two locomotion cycles (a gait between them): both
## clips are sampled at the same normalised phase u (b shifted by phase_offset),
## the result lasts lerp(a.length, b.length, w). With matching foot contacts the
## blended ground speed lands between the two (measured by tools/anim_probe.gd).
static func blend(a: Animation, b: Animation, w: float, phase_offset: float = 0.0, fps: float = 30.0) -> Animation:
	var out := Animation.new()
	out.length = lerpf(a.length, b.length, w)
	var frames := maxi(int(round(out.length * fps)), 2)
	for t: int in a.get_track_count():
		var ty := a.track_get_type(t)
		if not ty in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var p := a.track_get_path(t)
		var tb := b.find_track(p, ty)
		var nt := out.add_track(ty)
		out.track_set_path(nt, p)
		for i: int in frames + 1:
			var u := float(i) / float(frames)
			var ta := u * a.length
			var tbt := fposmod(u + phase_offset, 1.0) * b.length
			var v: Variant
			match ty:
				Animation.TYPE_POSITION_3D:
					var va := a.position_track_interpolate(t, ta)
					v = va.lerp(b.position_track_interpolate(tb, tbt), w) if tb >= 0 else va
				Animation.TYPE_ROTATION_3D:
					var qa := a.rotation_track_interpolate(t, ta)
					v = qa.slerp(b.rotation_track_interpolate(tb, tbt), w) if tb >= 0 else qa
				_:
					var sa := a.scale_track_interpolate(t, ta)
					v = sa.lerp(b.scale_track_interpolate(tb, tbt), w) if tb >= 0 else sa
			out.track_insert_key(nt, u * out.length, v)
	return out


## Upper body from `up`, lower body (bone names in `lower`) from `base`, time-scaled
## to the upper clip's length (the lower clip is a held pose such as a kneel).
static func layer(base: Animation, up: Animation, lower: Array) -> Animation:
	var out := up.duplicate(true) as Animation
	var k := up.length / maxf(base.length, 0.001)
	for t: int in range(out.get_track_count() - 1, -1, -1):
		if _bone(out.track_get_path(t)) in lower:
			out.remove_track(t)
	for t: int in base.get_track_count():
		var p := base.track_get_path(t)
		if not _bone(p) in lower:
			continue
		var nt := out.add_track(base.track_get_type(t))
		out.track_set_path(nt, p)
		out.track_set_interpolation_type(nt, base.track_get_interpolation_type(t))
		for i: int in base.track_get_key_count(t):
			out.track_insert_key(nt, base.track_get_key_time(t, i) * k, base.track_get_key_value(t, i))
	return out


static func _bone(p: NodePath) -> String:
	return String(p.get_concatenated_subnames())


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
