class_name PerfProbe
extends Node
## DEBUG / EVIDENCE ONLY (GA-29): measures every case in data/perf/budget.json
## the way the bible asks (p.26): warm up, then three rounds, frame-time
## p50/p95/p99 plus draw calls, primitives, objects, nodes, memory and load time.
## Hardware-independent counts are checked against the budget everywhere; frame
## times only count on real hardware (not under software rendering).
##   godot --path . -- --perf [--profile=desktop|web] [--case=colony_grown] [--frames=N] [--out=evidence/perf/perf_report.json]
## Exit code 1 if a counted budget is exceeded. Dev-only text, not localized.

var budget: Dictionary = {}
var profile := "desktop"
var only_case := ""
var out_path := "evidence/perf/perf_report.json"
var frames_override := 0


static func requested() -> bool:
	return "--perf" in OS.get_cmdline_user_args()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			profile = a.substr(10)
		elif a.begins_with("--case="):
			only_case = a.substr(7)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--frames="):
			frames_override = int(a.substr(9))
	budget = DictUtil.load_json("res://data/perf/budget.json")
	if frames_override > 0:  # quick count-only runs (software rendering is ~100x slower)
		budget["frames_per_round"] = frames_override
		budget["warmup_frames"] = mini(int(budget.get("warmup_frames", 90)), frames_override)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


static func percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return float(s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)])


func _run() -> void:
	var renderer := RenderingServer.get_current_rendering_method()
	var device := RenderingServer.get_video_adapter_name()
	var software := device.to_lower().contains("llvmpipe") or device.to_lower().contains("software") or DisplayServer.get_name() == "headless"
	var limits: Dictionary = DictUtil.get_dict(DictUtil.get_dict(budget, "profiles"), profile)
	var results: Array = []
	var over: Array = []
	for c: Dictionary in DictUtil.get_arr(budget, "cases"):
		if not only_case.is_empty() and str(c["id"]) != only_case:
			continue
		var r := await _measure(c)
		var fails: Array = []
		for k: String in ["draw_calls", "primitives", "nodes"]:
			if limits.has(k) and float(r[k + "_max"]) > float(limits[k]):
				fails.append("%s %d > %d" % [k, int(r[k + "_max"]), int(limits[k])])
		if not software:
			if limits.has("load_ms") and float(r["load_ms"]) > float(limits["load_ms"]):
				fails.append("load %d ms > %d" % [int(r["load_ms"]), int(limits["load_ms"])])
			var fm: Dictionary = DictUtil.get_dict(budget, "frame_ms")
			if float(r["frame_p95"]) > float(fm.get("p95", 16.7)):
				fails.append("p95 %.1f ms > %.1f" % [r["frame_p95"], fm.get("p95", 16.7)])
			if float(r["frame_p99"]) > float(fm.get("p99", 33.3)):
				fails.append("p99 %.1f ms > %.1f" % [r["frame_p99"], fm.get("p99", 33.3)])
		r["over_budget"] = fails
		if not fails.is_empty():
			over.append("%s: %s" % [c["id"], ", ".join(fails)])
		results.append(r)
		print("PERF %-16s p50 %5.1f  p95 %5.1f  p99 %5.1f ms | draws %5d  prims %8d  objs %5d  nodes %5d | load %5d ms  %s" % [c["id"],
			r["frame_p50"], r["frame_p95"], r["frame_p99"], r["draw_calls_max"], r["primitives_max"], r["objects_max"], r["nodes_max"],
			r["load_ms"], "OK" if fails.is_empty() else "OVER: " + ", ".join(fails)])
		print("PERF   census %s" % JSON.stringify(r["census"]))
	var report := {"engine_version": Engine.get_version_info().get("string"), "renderer": renderer, "device": device,
		"cpu": OS.get_processor_name(), "os": OS.get_name(), "resolution": get_viewport().get_visible_rect().size,
		"profile": profile, "limits": limits, "frame_times_judged": not software,
		"timestamp": Time.get_datetime_string_from_system(true), "cases": results, "over_budget": over}
	var abs_path := ProjectSettings.globalize_path("res://" + out_path) if not out_path.begins_with("/") else out_path
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("PERF device=%s renderer=%s frame times %s" % [device, renderer, "judged" if not software else "NOT judged (software rendering)"])
	print("PERF TOTAL %d cases, %d over budget -> %s" % [results.size(), over.size(), out_path])
	get_tree().quit(0 if over.is_empty() else 1)


func _measure(c: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	DebugFixtures.prepare(str(c.get("setup", "fresh")))
	AppFlow.goto(str(c["scene"]), {})
	var want := str(AppFlow.SCENES.get(str(c["scene"]), ""))
	for i: int in 600:
		await get_tree().process_frame
		var sc := get_tree().current_scene
		if sc and sc.scene_file_path == want:
			break
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if c.has("action"):
		await _frames(20)
		var sc := get_tree().current_scene
		if sc and sc.has_method("debug_action"):
			sc.call("debug_action", str(c["action"]))
	await _frames(int(budget.get("warmup_frames", 90)))
	var frames: Array = []
	var maxes := {"draw_calls": 0.0, "primitives": 0.0, "objects": 0.0, "nodes": 0.0}
	var mem_peak := 0.0
	for round: int in int(budget.get("rounds", 3)):
		for i: int in int(budget.get("frames_per_round", 120)):
			var t := Time.get_ticks_usec()
			await get_tree().process_frame
			frames.append((Time.get_ticks_usec() - t) / 1000.0)
			maxes["draw_calls"] = maxf(maxes["draw_calls"], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			maxes["primitives"] = maxf(maxes["primitives"], Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			maxes["objects"] = maxf(maxes["objects"], Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			maxes["nodes"] = maxf(maxes["nodes"], Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			mem_peak = maxf(mem_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
		await _frames(10)
	# What is on screen: the usual suspects behind draw calls.
	var census := {}
	for t: String in ["MeshInstance3D", "MultiMeshInstance3D", "Label3D", "GPUParticles3D", "OmniLight3D", "SpotLight3D", "CollisionShape3D"]:
		census[t] = get_tree().current_scene.find_children("*", t, true, false).size() if get_tree().current_scene else 0
	return {"id": c["id"], "scene": c["scene"], "setup": c.get("setup", ""), "load_ms": int(load_ms), "census": census, "quality": Quality.name(),
		"frame_p50": snappedf(percentile(frames, 0.5), 0.01), "frame_p95": snappedf(percentile(frames, 0.95), 0.01),
		"frame_p99": snappedf(percentile(frames, 0.99), 0.01), "frames": frames.size(),
		"draw_calls_max": int(maxes["draw_calls"]), "primitives_max": int(maxes["primitives"]),
		"objects_max": int(maxes["objects"]), "nodes_max": int(maxes["nodes"]),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_peak_mb": snappedf(mem_peak / 1048576.0, 0.1)}
