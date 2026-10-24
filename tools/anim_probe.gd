extends SceneTree
## Headless animation measurements (D-040, bible p.24-25 "no foot slide").
##   godot --headless --path . --script res://tools/anim_probe.gd [-- --out=res://evidence/animation_pass/measurements.json]
## For every built character library (data/art/animation_libraries.json) the clips
## are played on the slot's real retargeted model and sampled at 120 Hz:
##   - locomotion loops: the planted foot's backward speed = the ground speed the
##     clip was authored for (speed_ref). Foot slide at the game's speed is
##     |v_game - speed_ref * playback|, playback clamped like CharacterAnimator.
##   - stops/turns: distance the planted feet push the body (how far the stop "travels").
##   - actions: hand heights/reach (interact should meet a 1.05 m console) and hips height.
## Prints a table and writes JSON. Purely a measurement; it changes nothing.

const HZ := 120.0
const CONTACT_EPS := 0.035  # m above the clip's lowest foot height counts as planted
const GAME_SPEEDS := {"char.captain": {"walk_slow": [1.0, 2.0], "walk": [4.2], "run": [7.0]},
	"char.citizen_adult": {"walk": [1.35 * 0.9, 1.35, 1.35 * 1.1]}, "char.citizen_child": {"walk": [1.05 * 0.9, 1.05, 1.05 * 1.1]}}
const ROOT_MOTION := {"A_Walk_F_RootMotion_Masc": 1, "A_Run_F_RootMotion_Masc": 1, "A_Sprint_F_RootMotion_Masc": 1,
	"A_Walk_ToIdleF_LFootRootMotion_Masc": 1, "A_Run_ToIdleF_LFootRootMotion_Masc": 1,
	"A_Walk_F_Masc": 1, "A_Run_F_Masc": 1, "A_Sprint_F_Masc": 1}

var _out := "res://evidence/animation_pass/measurements.json"


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)


func _process(_d: float) -> bool:
	var libs := AnimationLibraryBuilder.load_mappings()
	var scenes: Variant = DictUtil.load_json("res://data/art/slot_scenes.json")
	var map: Variant = DictUtil.load_json("res://data/art/animation_map.json")
	var report := {"engine": Engine.get_version_info()["string"], "sample_hz": HZ, "contact_eps_m": CONTACT_EPS, "slots": {}, "root_motion_sources": {}}
	for slot: String in libs.keys():
		var sp: Variant = DictUtil.get_dict(scenes, "scenes").get(slot, DictUtil.get_dict(scenes, "slots").get(slot, ""))
		var prefab := "res://art/prefabs/%s.tscn" % slot
		if not ResourceLoader.exists(prefab):
			continue
		var model: Node3D = (load(prefab) as PackedScene).instantiate()
		root.add_child(model)
		var lib: AnimationLibrary = load(str(libs[slot]))
		var ap := CharacterAnimator.attach(model, lib)
		var sk: Skeleton3D = model.find_children("GeneralSkeleton", "Skeleton3D", true, false)[0]
		var cfg: Dictionary = DictUtil.get_dict(map if map is Dictionary else {}, slot)
		var clips := {}
		for n: StringName in lib.get_animation_list():
			clips[String(n)] = _measure(ap, sk, String(n), lib.get_animation(n))
		# Foot slide at the speeds the game actually uses, with today's map and clamp.
		var slide := {}
		var speeds: Dictionary = GAME_SPEEDS.get(slot, {})
		for st: String in speeds.keys():
			if not clips.has(st):
				continue
			var ref := float(clips[st].get("speed_ref_mps", 0.0))
			var mapped := DictUtil.get_float(DictUtil.get_dict(cfg, st), "speed_ref", 0.0)
			for v: float in speeds[st]:
				var row := {"game_mps": snappedf(v, 0.01), "measured_ref": ref}
				if mapped > 0.0:
					var pb := clampf(v / mapped, CharacterAnimator.PLAYBACK_MIN, CharacterAnimator.PLAYBACK_MAX)
					row["map_ref"] = mapped
					row["playback"] = snappedf(pb, 0.001)
					row["foot_slide_mps"] = snappedf(absf(v - ref * pb), 0.001)
					row["foot_slide_pct"] = snappedf(100.0 * absf(v - ref * pb) / v, 0.1)
				slide["%s@%.2f" % [st, v]] = row
		# Body variants (slot__N prefabs) share the library: their walk speed must agree with the map.
		var variants := {}
		for k: int in range(2, 21):
			var vp := "res://art/prefabs/%s__%d.tscn" % [slot, k]
			if not ResourceLoader.exists(vp) or not lib.has_animation("walk"):
				continue
			var vm: Node3D = (load(vp) as PackedScene).instantiate()
			root.add_child(vm)
			var vsk := vm.find_children("GeneralSkeleton", "Skeleton3D", true, false)
			if not vsk.is_empty():
				var vap := CharacterAnimator.attach(vm, lib)
				var m := _measure(vap, vsk[0], "walk", lib.get_animation("walk"))
				variants[vp.get_file()] = {"walk_speed_ref_mps": m.get("speed_ref_mps", 0.0), "hips_y_m": m["hips_y_max_m"]}
			vm.queue_free()
		report["slots"][slot] = {"prefab": prefab, "clips": clips, "slide_at_game_speed": slide, "variants": variants}
		if not variants.is_empty():
			print("  variants ", variants)
		model.queue_free()
	report["stop_simulation"] = {}
	for v0: float in [4.2, 7.0]:
		for matched: bool in [false, true]:
			report["stop_simulation"]["captain_%.1f_%s" % [v0, "distance_matched" if matched else "plain_blend"]] = _stop_sim("char.captain", v0, 16.0, matched, map)
	for base: String in ROOT_MOTION.keys():
		var p := "res://assets/imported/anim_pass/%s.fbx" % base
		if not ResourceLoader.exists(p):
			p = "res://assets/Synty/Animations/%s.fbx" % base
		if ResourceLoader.exists(p):
			report["root_motion_sources"][base] = _root_motion(p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " ", false) + "\n")
	f.close()
	_print(report)
	quit(0)
	return true


## Real-time braking through CharacterAnimator at 60 Hz: the model moves forward
## (-Z) at the controller's speed, braking at `decel` like Captain. Planted-foot
## slide = world travel of a ball-of-foot while it is on the floor. Plain blend =
## no stop distance passed (old behaviour); matched = distance-matched stop clip.
func _stop_sim(slot: String, v0: float, decel: float, matched: bool, map: Variant) -> Dictionary:
	var libs := AnimationLibraryBuilder.load_mappings()
	var model: Node3D = (load("res://art/prefabs/%s.tscn" % slot) as PackedScene).instantiate()
	root.add_child(model)
	var ca := CharacterAnimator.new()
	ca.player = CharacterAnimator.attach(model, load(str(libs[slot])))
	ca.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ca.prefix = CharacterAnimator.LIB_NAME + "/"
	ca.cfg = DictUtil.get_dict(map, slot)
	ca.anim_seed = 1
	var sk: Skeleton3D = model.find_children("GeneralSkeleton", "Skeleton3D", true, false)[0]
	var dt := 1.0 / 60.0
	var v := v0
	var walk_slide := 0.0
	var stop_slide := 0.0
	var frames: Array = []
	var t := 0.0
	var stop_t := -1.0
	var clips_seen := {}
	for i: int in 300:
		var braking := i >= 90  # 1.5 s steady gait, then let go of the stick
		if braking:
			v = maxf(v - decel * dt, 0.0)
			if stop_t < 0.0 and v <= 0.0:
				stop_t = t
			ca.update("idle", v, -1.0, v * v / (2.0 * decel) if matched else -1.0)
		else:
			ca.update("run" if v0 > 5.0 else "walk", v, v0)
		clips_seen[ca.current.trim_prefix(ca.prefix)] = true
		ca.player.advance(dt)
		model.position.z -= v * dt
		t += dt
		frames.append([braking, i > 30, _pos(sk, "LeftToes"), _pos(sk, "RightToes")])
	model.queue_free()
	var floor_y := INF
	for f: Array in frames:
		floor_y = minf(floor_y, minf((f[2] as Vector3).y, (f[3] as Vector3).y))
	var wmin := INF
	for f: Array in frames:
		if not f[0] and f[1]:
			wmin = minf(wmin, minf((f[2] as Vector3).y, (f[3] as Vector3).y))
	for i: int in range(1, frames.size()):
		for s: int in [2, 3]:
			var a: Vector3 = frames[i - 1][s]
			var b: Vector3 = frames[i][s]
			if a.y < floor_y + CONTACT_EPS and b.y < floor_y + CONTACT_EPS:
				var d := Vector2(b.x - a.x, b.z - a.z).length()
				if frames[i][0]:
					stop_slide += d
				elif frames[i][1]:
					walk_slide += d
	return {"v0_mps": v0, "decel_mps2": decel, "steady_planted_slide_m_per_s": snappedf(walk_slide / (60.0 * dt), 0.003),
		"braking_planted_slide_m": snappedf(stop_slide, 0.003), "brake_time_s": snappedf(stop_t - 1.5, 0.01),
		"braking_distance_m": snappedf(v0 * v0 / (2.0 * decel), 0.01), "clips": clips_seen.keys()}


func _pos(sk: Skeleton3D, bone: String) -> Vector3:
	var b := sk.find_bone(bone)
	return (sk.global_transform * sk.get_bone_global_pose(b)).origin if b >= 0 else Vector3.ZERO


func _measure(ap: AnimationPlayer, sk: Skeleton3D, name: String, anim: Animation) -> Dictionary:
	var length := anim.length
	var n := maxi(int(length * HZ), 2)
	ap.play(CharacterAnimator.LIB_NAME + "/" + name, 0.0)
	var bones := ["LeftFoot", "RightFoot", "LeftToes", "RightToes", "Hips", "LeftHand", "RightHand", "Head"]
	var tr := {}
	for b: String in bones:
		tr[b] = []
	for i: int in n + 1:
		ap.seek(length * float(i) / float(n), true)
		for b: String in bones:
			(tr[b] as Array).append(_pos(sk, b))
	var out := {"length_s": snappedf(length, 0.001), "loop": anim.loop_mode != Animation.LOOP_NONE}
	var dt := length / float(n)
	# Planted-foot speed: horizontal speed of a foot while it is within CONTACT_EPS of the floor.
	var speeds: Array = []
	var push := 0.0  # integrated planted-foot travel (lowest foot each frame)
	var lmin := INF
	var rmin := INF
	for i: int in n + 1:
		lmin = minf(lmin, (tr["LeftToes"][i] as Vector3).y)
		rmin = minf(rmin, (tr["RightToes"][i] as Vector3).y)
	var floor_y := minf(lmin, rmin)
	var left_contact_start := -1.0
	for i: int in n:
		for side: String in ["Left", "Right"]:
			var a: Vector3 = tr[side + "Toes"][i]
			var b: Vector3 = tr[side + "Toes"][i + 1]
			var ta: Vector3 = tr[side + "Toes"][i]
			if minf(a.y, ta.y) - floor_y < CONTACT_EPS:
				speeds.append(Vector2(b.x - a.x, b.z - a.z).length() / dt)
				if side == "Left" and left_contact_start < 0.0 and i > 0:
					var pa: Vector3 = tr["LeftFoot"][i - 1]
					var pt: Vector3 = tr["LeftToes"][i - 1]
					if minf(pa.y, pt.y) - floor_y >= CONTACT_EPS:
						left_contact_start = float(i) / float(n)
		var lo := "Left" if minf((tr["LeftFoot"][i] as Vector3).y, (tr["LeftToes"][i] as Vector3).y) < minf((tr["RightFoot"][i] as Vector3).y, (tr["RightToes"][i] as Vector3).y) else "Right"
		var fa: Vector3 = tr[lo + "Foot"][i]
		var fb: Vector3 = tr[lo + "Foot"][i + 1]
		push += Vector2(fb.x - fa.x, fb.z - fa.z).length()
	speeds.sort()
	var med: float = speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
	out["planted_foot_speed_median_mps"] = snappedf(med, 0.001)
	out["planted_push_m"] = snappedf(push, 0.001)
	out["toe_min_y_m"] = snappedf(floor_y, 0.001)
	out["left_contact_start_phase"] = snappedf(left_contact_start, 0.001)
	if out["loop"] and med > 0.3:
		out["speed_ref_mps"] = snappedf(med, 0.01)
		out["stride_m"] = snappedf(med * length, 0.01)  # one full cycle = two steps
	var hips_y: Array = (tr["Hips"] as Array).map(func(v: Vector3) -> float: return v.y)
	out["hips_y_min_m"] = snappedf(hips_y.min(), 0.001)
	out["hips_y_max_m"] = snappedf(hips_y.max(), 0.001)
	for side: String in ["Left", "Right"]:
		var best := 0.0
		var best_i := 0
		for i: int in n + 1:
			var h: Vector3 = tr[side + "Hand"][i]
			var hip: Vector3 = tr["Hips"][0]
			var reach := Vector2(h.x - hip.x, h.z - hip.z).length()
			if reach > best:
				best = reach
				best_i = i
		var hb: Vector3 = tr[side + "Hand"][best_i]
		out[side.to_lower() + "_hand_max_reach"] = {"reach_m": snappedf(best, 0.001), "height_m": snappedf(hb.y, 0.001), "t_s": snappedf(best_i * dt, 0.01)}
		var ys: Array = (tr[side + "Hand"] as Array).map(func(v: Vector3) -> float: return v.y)
		out[side.to_lower() + "_hand_y_range_m"] = [snappedf(ys.min(), 0.001), snappedf(ys.max(), 0.001)]
	return out


## Root-motion source clip on its own (un-retargeted) rig: hips travel per second.
func _root_motion(path: String) -> Dictionary:
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	var out := {}
	if aps.is_empty() or sks.is_empty():
		inst.queue_free()
		return {"error": "no player/skeleton"}
	var ap: AnimationPlayer = aps[0]
	var sk: Skeleton3D = sks[0]
	var clip := ""
	for c: StringName in ap.get_animation_list():
		if c != &"RESET":
			clip = String(c)
	var a := ap.get_animation(clip)
	ap.play(clip)
	var hb := sk.find_bone("Hips")
	if hb < 0:
		hb = 0
	ap.seek(0.0, true)
	var p0 := (sk.global_transform * sk.get_bone_global_pose(hb)).origin
	ap.seek(a.length, true)
	var p1 := (sk.global_transform * sk.get_bone_global_pose(hb)).origin
	var d := Vector2(p1.x - p0.x, p1.z - p0.z).length()
	out = {"length_s": snappedf(a.length, 0.001), "hips_travel_m": snappedf(d, 0.001), "mean_speed_mps": snappedf(d / a.length, 0.01)}
	# Same planted-foot method on the source rig (root motion: planted feet should read ~0 m/s).
	var names := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"] if sk.find_bone("LeftFoot") >= 0 else ["Ankle_L", "Ankle_R", "Ball_L", "Ball_R"]
	var n := int(a.length * HZ)
	var ps: Array = []
	var curve: Array = []  # hips travel so far, every 0.1 s (where a stop spends its distance)
	for i: int in n + 1:
		ap.seek(a.length * i / n, true)
		if i % int(HZ / 10.0) == 0:
			var hp := (sk.global_transform * sk.get_bone_global_pose(hb)).origin
			curve.append(snappedf(Vector2(hp.x - p0.x, hp.z - p0.z).length(), 0.01))
		var row: Array = []
		for b: String in names:
			row.append((sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin)
		ps.append(row)
	var fl := INF
	for row: Array in ps:
		fl = minf(fl, minf((row[2] as Vector3).y, (row[3] as Vector3).y))
	var sp: Array = []
	for i: int in n:
		for s: int in 2:
			var fa: Vector3 = ps[i][s + 2]
			var fb: Vector3 = ps[i + 1][s + 2]
			if minf(fa.y, (ps[i][s + 2] as Vector3).y) - fl < CONTACT_EPS:
				sp.append(Vector2(fb.x - fa.x, fb.z - fa.z).length() / (a.length / n))
	sp.sort()
	out["planted_foot_speed_median_mps"] = snappedf(sp[sp.size() / 2], 0.01) if not sp.is_empty() else 0.0
	out["hips_travel_every_0_1s"] = curve
	inst.queue_free()
	return out


func _print(r: Dictionary) -> void:
	for slot: String in r["slots"].keys():
		print("== ", slot)
		var clips: Dictionary = r["slots"][slot]["clips"]
		for c: String in clips.keys():
			var m: Dictionary = clips[c]
			print("  %-18s len %.2f  ref %5s  stride %5s  push %.2f  lcs %.2f  hips %.2f-%.2f  Lhand %.2f@%.2f  Rhand %.2f@%.2f" % [c, m["length_s"],
				str(m.get("speed_ref_mps", "-")), str(m.get("stride_m", "-")), m["planted_push_m"], m["left_contact_start_phase"], m["hips_y_min_m"], m["hips_y_max_m"],
				m["left_hand_max_reach"]["reach_m"], m["left_hand_max_reach"]["height_m"], m["right_hand_max_reach"]["reach_m"], m["right_hand_max_reach"]["height_m"]])
		for k: String in r["slots"][slot]["slide_at_game_speed"].keys():
			print("  slide ", k, " ", r["slots"][slot]["slide_at_game_speed"][k])
	for k: String in r["root_motion_sources"].keys():
		print("  root motion ", k, " ", r["root_motion_sources"][k])
	for k: String in r.get("stop_simulation", {}).keys():
		print("  stop sim ", k, " ", r["stop_simulation"][k])
