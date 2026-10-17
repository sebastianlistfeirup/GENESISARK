extends SceneTree
## Headless domain test runner (test layer 1, bible p.26).
## Usage: godot --headless --path . --script res://tests/run_tests.gd [-- --filter=name]
## Writes evidence/test_report.json and exits non-zero on failure.

func _init() -> void:
	var filter := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var content := ContentDB.load_default()
	var total := 0
	var failed: Array = []
	var files: Array = []
	var dir := DirAccess.open("res://tests/unit")
	for f: String in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var t0 := Time.get_ticks_msec()
	var per_file := {}
	for f: String in files:
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null:
			failed.append("%s: kunne ikke indlæses" % f)
			continue
		var count := 0
		for m: Dictionary in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if not filter.is_empty() and not filter in name and not filter in f:
				continue
			var inst: TestCase = script.new()
			inst.content = content
			inst.set_current("%s::%s" % [f.get_basename(), name])
			inst.call(name)
			total += 1
			count += 1
			failed.append_array(inst.failures)
			if inst.failures.is_empty():
				print("  PASS ", f.get_basename(), "::", name)
			else:
				for fl: String in inst.failures:
					print("  FAIL ", fl)
		per_file[f] = count
	var elapsed := Time.get_ticks_msec() - t0
	print("\n%d tests, %d fejl, %d ms" % [total, failed.size(), elapsed])
	if not content.errors.is_empty():
		print("Indholdsfejl:")
		for e: String in content.errors:
			print("  ", e)
	var report := {
		"engine_version": Engine.get_version_info().get("string"), "tests": total, "failures": failed,
		"content_errors": Array(content.errors), "elapsed_ms": elapsed, "files": per_file,
		"status": "PASS" if failed.is_empty() and content.errors.is_empty() else "FAIL",
		"timestamp": Time.get_datetime_string_from_system(true),
	}
	DirAccess.make_dir_recursive_absolute("res://evidence")
	var fa := FileAccess.open("res://evidence/test_report.json", FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(report, "  "))
		fa.close()
	quit(0 if report["status"] == "PASS" else 1)
