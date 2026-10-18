class_name HumanoidBoneMapper
extends RefCounted
## Maps a skeleton's bone names onto Godot's SkeletonProfileHumanoid, so every
## humanoid (Synty POLYGON/Sidekick, Mixamo, Unreal/Blender "_l/.L" rigs) ends up
## with the same bone names after import ("retargeting"). Animations made for one
## rig then play on any other. This is what the BoneMap editor's auto-mapping
## does by hand in the import dialog.
## Synty/Sidekick names are typical conventions, not verified against the
## purchased files: audit() reports exactly which profile bones were found.

## Core bones a walking/interacting humanoid needs (fingers/eyes/jaw are optional).
const CORE := ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot"]

## part (side-less, normalised) -> profile bone suffix. Order matters only for ties.
const PARTS := {
	"hips": "Hips", "hip": "Hips", "pelvis": "Hips", "root_hips": "Hips",
	"neck": "Neck", "neck01": "Neck", "neck1": "Neck", "head": "Head", "jaw": "Jaw", "eye": "Eye",
	"clavicle": "Shoulder", "collar": "Shoulder", "collarbone": "Shoulder",
	"upperarm": "UpperArm", "arm": "UpperArm", "armupper": "UpperArm",
	"forearm": "LowerArm", "lowerarm": "LowerArm", "elbow": "LowerArm", "armlower": "LowerArm",
	"hand": "Hand", "wrist": "Hand",
	"upleg": "UpperLeg", "upperleg": "UpperLeg", "thigh": "UpperLeg", "legupper": "UpperLeg",
	"leg": "LowerLeg", "lowerleg": "LowerLeg", "knee": "LowerLeg", "calf": "LowerLeg", "shin": "LowerLeg", "leglower": "LowerLeg",
	"foot": "Foot", "ankle": "Foot",
	"toebase": "Toes", "toes": "Toes", "toe": "Toes", "ball": "Toes",
}
const FINGERS := {"thumb": "Thumb", "index": "Index", "middle": "Middle", "ring": "Ring", "pinky": "Little", "little": "Little"}
const FINGER_JOINTS := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "_": ["Proximal", "Intermediate", "Distal"]}


## Builds a BoneMap for `skel`. Returns {map: BoneMap, found: [...], missing_core: [...]}.
static func build(skel: Skeleton3D) -> Dictionary:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	var taken := {}
	var spine_chain: Array = []
	var has_clavicle := {"Left": false, "Right": false}
	var parsed: Array = []
	for i: int in skel.get_bone_count():
		var info := parse(skel.get_bone_name(i))
		info["bone"] = skel.get_bone_name(i)
		info["index"] = i
		parsed.append(info)
		if info["part"] in ["clavicle", "collar", "collarbone"] and not str(info["side"]).is_empty():
			has_clavicle[info["side"]] = true
	for info: Dictionary in parsed:
		var part: String = info["part"]
		var side: String = info["side"]
		var profile := ""
		if part.begins_with("spine") or part in ["chest", "upperchest"]:
			spine_chain.append(info)
			continue
		if part == "shoulder":
			# Synty: Clavicle_L + Shoulder_L(= upper arm). Mixamo: LeftShoulder(= clavicle) + LeftArm.
			profile = side + ("UpperArm" if has_clavicle.get(side, false) else "Shoulder")
		elif FINGERS.has(info["finger"]):
			var f: String = FINGERS[info["finger"]]
			var joints: Array = FINGER_JOINTS.get(f, FINGER_JOINTS["_"])
			var n := clampi(int(info["num"]) - 1, 0, 2)
			profile = side + f + str(joints[n])
		elif PARTS.has(part):
			var suffix: String = PARTS[part]
			if suffix in ["Hips", "Neck", "Head", "Jaw"]:
				profile = suffix
			elif suffix == "Eye":
				profile = side + "Eye"
			elif not side.is_empty():
				profile = side + suffix
		if profile.is_empty() or taken.has(profile) or bm.profile.find_bone(profile) < 0:
			continue
		bm.set_skeleton_bone_name(profile, info["bone"])
		taken[profile] = info["bone"]
	# Spine chain in hierarchy order: Spine, Chest, UpperChest (2 bones -> Spine, Chest).
	spine_chain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _depth(skel, a["index"]) < _depth(skel, b["index"]))
	var spine_names := ["Spine", "Chest", "UpperChest"]
	for k: int in mini(spine_chain.size(), 3):
		bm.set_skeleton_bone_name(spine_names[k], spine_chain[k]["bone"])
		taken[spine_names[k]] = spine_chain[k]["bone"]
	var missing: Array = CORE.filter(func(b: String) -> bool: return not taken.has(b))
	return {"map": bm, "found": taken, "missing_core": missing}


## "mixamorig_LeftForeArm" -> {side: Left, part: forearm}; "Elbow_L" -> {Left, elbow};
## "Index_02_R" -> {Right, finger: index, num: 2}; "spine.003" -> {part: spine3}.
static func parse(raw: String) -> Dictionary:
	var s := raw
	for pre: String in ["mixamorig:", "mixamorig_", "mixamorig", "Bip001 ", "Bip01 ", "DEF-", "DEF_", "ORG-", "B_", "b_", "Bone_", "SK_"]:
		if s.begins_with(pre):
			s = s.substr(pre.length())
	var side := ""
	var low := s.to_lower()
	for pat: Array in [["left", "Left"], ["right", "Right"]]:
		if low.begins_with(pat[0]) or low.ends_with(pat[0]):
			side = pat[1]
			low = low.trim_prefix(pat[0]).trim_suffix(pat[0])
	if side.is_empty():
		var re := RegEx.create_from_string("(^|[_.\\s-])([lr])($|[_.\\s-])")
		var m := re.search(low)
		if m:
			side = "Left" if m.get_string(2) == "l" else "Right"
			low = low.substr(0, m.get_start(2)) + low.substr(m.get_end(2))
	var num := 0
	var dm := RegEx.create_from_string("(\\d+)").search(low)
	if dm:
		num = int(dm.get_string(1))
	var letters := RegEx.create_from_string("[^a-z]").sub(low, "", true)
	var finger := ""
	for f: String in FINGERS.keys():
		if letters.begins_with(f):
			finger = f
	var part := letters
	if letters == "spine":
		part = "spine%d" % num if num > 0 else "spine"
	return {"side": side, "part": part, "finger": finger, "num": maxi(num, 1)}


static func _depth(skel: Skeleton3D, i: int) -> int:
	var d := 0
	var p := skel.get_bone_parent(i)
	while p >= 0:
		d += 1
		p = skel.get_bone_parent(p)
	return d


## Makes a model import as a retargeted humanoid: finds its Skeleton3D, builds
## the BoneMap, saves it to art/rigs/ and points the model's import settings at
## it (what "Retarget > Bone Map" in Advanced Import Settings does).
## Returns {ok, changed, skeleton, missing_core, bone_map}. changed = re-import needed.
static func apply_retarget(model_path: String, rig_dir: String = "res://art/rigs/") -> Dictionary:
	var ps: PackedScene = load(model_path)
	if ps == null:
		return {"ok": false, "error": "cannot load " + model_path}
	var root := ps.instantiate()
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		root.free()
		return {"ok": false, "error": "no Skeleton3D in " + model_path}
	var skel: Skeleton3D = found[0]
	var path := str(root.get_path_to(skel))
	if skel.name == "GeneralSkeleton" and skel.find_bone("Hips") >= 0:
		root.free()  # already imported with a humanoid bone map
		return {"ok": true, "changed": false, "skeleton": path, "missing_core": [], "bone_map": ""}
	var r := build(skel)
	root.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rig_dir))
	var pack := model_path.trim_prefix("res://assets/imported/").get_slice("/", 0) if model_path.begins_with("res://assets/imported/") else "local"
	var bm_path := rig_dir.path_join("%s__%s.bonemap.tres" % [pack, model_path.get_file().get_basename()])
	ResourceSaver.save(r["map"], bm_path)
	var cfg := ConfigFile.new()
	if cfg.load(model_path + ".import") != OK:
		return {"ok": false, "error": "no .import file for " + model_path}
	var sub: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = sub.get("nodes", {})
	var key := "PATH:" + path
	var cur: Dictionary = nodes.get(key, {})
	cur["retarget/bone_map"] = load(bm_path)
	nodes[key] = cur
	sub["nodes"] = nodes
	cfg.set_value("params", "_subresources", sub)
	cfg.save(model_path + ".import")
	return {"ok": true, "changed": true, "skeleton": path, "missing_core": r["missing_core"], "bone_map": bm_path}
