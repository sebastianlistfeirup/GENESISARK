extends SceneTree
## Headless probe for the supply drop pod (D-056): scrubs DropPodTimeline through
## a real DropPod and prints the key values over time (body height, tilt, squash,
## feet in contact, lid angle, cell height, glow) plus the event beats, for the
## full and the reduced-motion version. Exit 1 if an invariant breaks:
## the pod ends on the ground, level, lid open, cell delivered, lights dimmed,
## no NaN, the hatch never opens before the landing.
##   godot --headless --path . --script res://tools/rebuild/droppod_probe.gd [-- --step=100]

var step := 100.0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
	_run.call_deferred()


func _run() -> void:
	var pod := DropPod.new()
	root.add_child(pod)
	await process_frame
	var bad: Array = []
	for short: bool in [false, true]:
		var ev := DropPodTimeline.events(short)
		print("DROPPOD %s  duration %d ms  events %s" % ["SHORT" if short else "FULL", int(DropPodTimeline.duration(short)), str(ev)])
		print("   t_ms    alt   roll°  pitch° squash feet  lid°   cell_y  zip   glow  thrust")
		var t := 0.0
		var landed_at := -1.0
		while t <= DropPodTimeline.duration(short) + 0.5:
			var p := DropPodTimeline.pose(t, short)
			pod.set_time(t, short)
			var feet := 0
			for i: int in 4:
				if absf(pod.foot_world(i).y - pod.global_position.y - DropPod.FOOT_Y) < 0.002:
					feet += 1
			if feet >= 3 and landed_at < 0.0:
				landed_at = t
			var lid := float(p["lid"]) * rad_to_deg(DropPod.LID_MAX)
			if lid > 5.0 and (landed_at < 0.0 or t < landed_at):
				bad.append("lid opens before landing at %d" % int(t))
			for k: String in ["alt", "roll", "pitch", "squash", "lid", "cell_y", "glow"]:
				if is_nan(float(p[k])):
					bad.append("NaN %s at %d" % [k, int(t)])
			print("%7d %6.3f %6.2f %6.2f %6.3f %4d %6.1f %7.3f %5.2f %5.2f %5.2f" % [int(t), float(p["alt"]), rad_to_deg(float(p["roll"])), rad_to_deg(float(p["pitch"])),
				float(p["squash"]), feet, lid, float(p["cell_y"]), float(p["cell_zip"]), float(p["glow"]), float(p["thrust"])])
			t += step
		var e := DropPodTimeline.pose(DropPodTimeline.duration(short), short)
		if absf(float(e["alt"])) > 0.002 or absf(float(e["roll"])) > 0.002 or float(e["lid"]) < 0.98 or float(e["cell_vis"]) > 0.5 or float(e["glow"]) > 0.2:
			bad.append("end pose wrong (%s): %s" % ["short" if short else "full", str(e)])
		print("landed (3+ feet) at %d ms" % int(landed_at))
	print("DROPPOD_PROBE %s %s" % ["PASS" if bad.is_empty() else "FAIL", str(bad)])
	quit(0 if bad.is_empty() else 1)
