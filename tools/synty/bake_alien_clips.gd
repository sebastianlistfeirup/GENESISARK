extends SceneTree
## Bakes walk/idle clips for the Synty Sci-Fi Worlds alien giants (ground
## wildlife, D-053). The aliens ship as Godot prefabs with their own Synty-named
## skeleton (no FBX to re-import with a bone map), so the citizen's retargeted
## clips (art/animations/char.citizen_adult.res, humanoid profile names) are
## transferred pose by pose: each mapped bone gets the same rotation relative to
## its rest in skeleton space (both rigs rest in a T-pose), the hips move scaled
## by hip height. Output: art/animations/beast.<body>.res (local only, gitignored
## like every library built from purchased clips).
##
## Usage: godot --headless --path . --script res://tools/synty/bake_alien_clips.gd

const SRC_SCENE := "res://assets/Synty/CharactersSrc/Characters.fbx"
const SRC_LIB := "res://art/animations/char.citizen_adult.res"
const PREFABS := "res://assets/Synty/PolygonSciFiWorlds/Prefabs/Characters/SM_Chr_ScifiWorlds_%s.tscn"
const BODIES := ["AlienRock_01", "AlienSpikes_01"]
const CLIPS := ["idle", "walk"]
const FPS := 30.0


func _init() -> void:
	var code := 0
	if not ResourceLoader.exists(SRC_SCENE) or not ResourceLoader.exists(SRC_LIB):
		print("bake_alien_clips: source character or library missing (build the Synty packs first)")
		quit(1)
		return
	var src_root: Node = (load(SRC_SCENE) as PackedScene).instantiate()
	var found := src_root.find_children("GeneralSkeleton", "Skeleton3D", true, false)
	if found.is_empty():
		print("bake_alien_clips: no retargeted GeneralSkeleton in ", SRC_SCENE)
		src_root.free()
		quit(1)
		return
	var src: Skeleton3D = found[0]
	var lib: AnimationLibrary = load(SRC_LIB)
	for body: String in BODIES:
		var path := PREFABS % body
		if not ResourceLoader.exists(path):
			print("skip ", body, ": prefab missing")
			continue
		var al: Node = (load(path) as PackedScene).instantiate()
		var sk := al.find_children("*", "Skeleton3D", true, false)
		if sk.is_empty():
			al.free()
			continue
		var tgt: Skeleton3D = sk[0]
		var bm: BoneMap = HumanoidBoneMapper.build(tgt)["map"]
		var pairs: Dictionary = {}  # target bone -> source bone
		for i: int in bm.profile.bone_size:
			var pn := bm.profile.get_bone_name(i)
			var tn := String(bm.get_skeleton_bone_name(pn))
			if tn.is_empty() or src.find_bone(pn) < 0 or tgt.find_bone(tn) < 0:
				continue
			pairs[tgt.find_bone(tn)] = src.find_bone(pn)
		var out := AnimationLibrary.new()
		for c: String in CLIPS:
			if lib.has_animation(c):
				out.add_animation(c, _bake(lib.get_animation(c), src, tgt, pairs))
		var dest := "res://art/animations/beast.%s.res" % body.to_lower()
		var err := ResourceSaver.save(out, dest)
		print("baked ", dest, " bones=", pairs.size(), " clips=", out.get_animation_list(), " err=", err)
		code = maxi(code, err)
		al.free()
	src_root.free()
	quit(code)


func _bake(anim: Animation, src: Skeleton3D, tgt: Skeleton3D, pairs: Dictionary) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = Animation.LOOP_LINEAR
	var src_rest := _globals(src, _rests(src))
	var tgt_rest := _globals(tgt, _rests(tgt))
	var hips_t := tgt.find_bone("Hips")
	var hips_s := src.find_bone("Hips")
	var ratio: float = (tgt_rest[hips_t] as Transform3D).origin.y / maxf((src_rest[hips_s] as Transform3D).origin.y, 0.01) if hips_t >= 0 and hips_s >= 0 else 1.0
	var tracks: Dictionary = {}
	for ti: int in pairs.keys():
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(String(tgt.name) + ":" + tgt.get_bone_name(ti)))
		tracks[ti] = tr
	var hips_track := -1
	if hips_t >= 0:
		hips_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath(String(tgt.name) + ":Hips"))
	var track_bone: Dictionary = {}
	for t: int in anim.get_track_count():
		var b := src.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
		if b >= 0:
			track_bone[t] = b
	var frames := int(ceil(anim.length * FPS))
	for f: int in frames + 1:
		var tt := minf(f / FPS, anim.length)
		var local := _rests(src)
		for t: int in track_bone.keys():
			var bi: int = track_bone[t]
			var xf: Transform3D = local[bi]
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					xf.origin = anim.position_track_interpolate(t, tt)
				Animation.TYPE_ROTATION_3D:
					xf.basis = Basis(anim.rotation_track_interpolate(t, tt))
			local[bi] = xf
		var sg := _globals(src, local)
		var tg: Array = []
		tg.resize(tgt.get_bone_count())
		for ti: int in tgt.get_bone_count():
			_target_global(tgt, ti, pairs, sg, src_rest, tgt_rest, tg, hips_t, hips_s, ratio)
		for ti: int in pairs.keys():
			var p := tgt.get_bone_parent(ti)
			var pb: Basis = (tg[p] as Transform3D).basis if p >= 0 else Basis.IDENTITY
			out.rotation_track_insert_key(tracks[ti], tt, (pb.inverse() * (tg[ti] as Transform3D).basis).get_rotation_quaternion())
		if hips_track >= 0:
			var hp := tgt.get_bone_parent(hips_t)
			var pxf: Transform3D = tg[hp] if hp >= 0 else Transform3D.IDENTITY
			out.position_track_insert_key(hips_track, tt, pxf.affine_inverse() * (tg[hips_t] as Transform3D).origin)
	return out


func _target_global(tgt: Skeleton3D, ti: int, pairs: Dictionary, sg: Array, src_rest: Array, tgt_rest: Array, tg: Array,
		hips_t: int, hips_s: int, ratio: float) -> Transform3D:
	if tg[ti] != null:
		return tg[ti]
	var p := tgt.get_bone_parent(ti)
	var parent: Transform3D = _target_global(tgt, p, pairs, sg, src_rest, tgt_rest, tg, hips_t, hips_s, ratio) if p >= 0 else Transform3D.IDENTITY
	var g := parent * tgt.get_bone_rest(ti)
	if pairs.has(ti):
		var si: int = pairs[ti]
		var delta := (sg[si] as Transform3D).basis.orthonormalized() * (src_rest[si] as Transform3D).basis.orthonormalized().inverse()
		g.basis = delta * (tgt_rest[ti] as Transform3D).basis.orthonormalized()
	if ti == hips_t and hips_s >= 0:
		g.origin = (tgt_rest[ti] as Transform3D).origin + ((sg[hips_s] as Transform3D).origin - (src_rest[hips_s] as Transform3D).origin) * ratio
	tg[ti] = g
	return g


func _rests(s: Skeleton3D) -> Array:
	var a: Array = []
	for i: int in s.get_bone_count():
		a.append(s.get_bone_rest(i))
	return a


func _globals(s: Skeleton3D, local: Array) -> Array:
	var g: Array = []
	g.resize(s.get_bone_count())
	for i: int in s.get_bone_count():
		g[i] = _g(s, local, g, i)
	return g


func _g(s: Skeleton3D, local: Array, g: Array, i: int) -> Transform3D:
	if g[i] != null:
		return g[i]
	var p := s.get_bone_parent(i)
	var v: Transform3D = local[i] if p < 0 else _g(s, local, g, p) * (local[i] as Transform3D)
	g[i] = v
	return v
