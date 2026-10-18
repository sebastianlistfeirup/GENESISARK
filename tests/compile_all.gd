extends Node
## Run as a scene so autoloads exist: godot --headless --path . res://scenes/tests/compile_all.tscn
## Loads every GDScript under res://scripts, tests, tools and addons to surface parse
## errors in one pass. Exit code 1 if any script fails to load.

func _ready() -> void:
	var bad: Array = []
	var files: Array = []
	_collect("res://scripts", files)
	_collect("res://tests", files)
	_collect("res://tools", files)
	_collect("res://addons", files)
	for f: String in files:
		var s: Variant = load(f)
		if s == null or not (s as GDScript).can_instantiate():
			bad.append(f)
	print("COMPILE %d scripts, %d failed %s" % [files.size(), bad.size(), str(bad)])
	get_tree().quit(1 if not bad.is_empty() else 0)


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub: String in d.get_directories():
		_collect(dir + "/" + sub, out)
