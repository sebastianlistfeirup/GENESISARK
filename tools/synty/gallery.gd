extends SceneTree
## Contact sheets for choosing Synty models by eye, not by file name.
## Lays out every scene/model in a folder (or a list file) on a grid, each scaled
## to fit its cell, with its file name underneath, and saves one PNG per page.
##   godot --path . --resolution 1920x1080 --script res://tools/synty/gallery.gd -- \
##     --dir=res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings --out=C:/tmp/gal --cols=6 --rows=4 [--filter=Dome] [--true_scale]
## --true_scale keeps real size (one shared scale per page) so heights can be compared.

var files: Array[String] = []
var out_dir := "user://gallery"
var cols := 6
var rows := 4
var filter := ""
var true_scale := false
var page := 0


func _init() -> void:
	var dir := ""
	var list := ""
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"dir": dir = kv[1]
			"list": list = kv[1]
			"out": out_dir = kv[1]
			"cols": cols = int(kv[1])
			"rows": rows = int(kv[1])
			"filter": filter = kv[1]
			"true_scale": true_scale = true
	if not list.is_empty():
		for line: String in FileAccess.get_file_as_string(list).split("\n"):
			if not line.strip_edges().is_empty():
				files.append(line.strip_edges())
	else:
		for f: String in DirAccess.get_files_at(dir):
			if (f.ends_with(".tscn") or f.ends_with(".fbx") or f.ends_with(".glb")) and (filter.is_empty() or f.containsn(filter)):
				files.append(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D and n is GeometryInstance3D:
		var b: AABB = t * (n as VisualInstance3D).get_aabb()
		acc[0] = b if acc[0] == null else (acc[0] as AABB).merge(b)
	for c: Node in n.get_children():
		_aabb(c, t, acc)


func _strip_bodies(n: Node) -> void:
	for c: Node in n.get_children():
		if c is CollisionObject3D:
			c.queue_free()
		else:
			_strip_bodies(c)


func _run() -> void:
	var per := cols * rows
	var pages := int(ceil(files.size() / float(per)))
	print("GALLERY %d files, %d pages" % [files.size(), pages])
	for p: int in pages:
		await _page(files.slice(p * per, (p + 1) * per), p)
	quit(0)


func _page(batch: Array[String], p: int) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var cell := 10.0
	var nodes: Array = []
	var max_dim := 0.001
	for i: int in batch.size():
		var res: Resource = load(batch[i])
		var inst: Node3D = null
		if res is PackedScene:
			inst = (res as PackedScene).instantiate() as Node3D
		if inst == null:
			nodes.append(null)
			continue
		_strip_bodies(inst)
		var holder := Node3D.new()
		holder.add_child(inst)
		world.add_child(holder)
		var acc: Array = [null]
		_aabb(inst, Transform3D.IDENTITY, acc)
		var b: AABB = acc[0] if acc[0] != null else AABB(Vector3.ZERO, Vector3.ONE)
		max_dim = maxf(max_dim, maxf(b.size.x, maxf(b.size.y, b.size.z)))
		nodes.append([holder, inst, b])
	for i: int in nodes.size():
		if nodes[i] == null:
			continue
		var holder: Node3D = nodes[i][0]
		var inst: Node3D = nodes[i][1]
		var b: AABB = nodes[i][2]
		var dim := maxf(b.size.x, maxf(b.size.y, b.size.z))
		var s := (cell * 0.8) / (max_dim if true_scale else maxf(dim, 0.001))
		inst.scale = Vector3.ONE * s
		inst.position = -b.get_center() * s + Vector3(0, b.size.y * s * 0.5, 0)
		var c := i % cols
		var r := i / cols
		holder.position = Vector3((c - (cols - 1) * 0.5) * cell, 0, (r - (rows - 1) * 0.5) * cell * 1.15)
		var lbl := Label3D.new()
		lbl.text = "%d %s\n%.1fx%.1fx%.1f m" % [i, batch[i].get_file().get_basename(), b.size.x, b.size.y, b.size.z]
		lbl.font_size = 56
		lbl.pixel_size = 0.01
		lbl.outline_size = 8
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = holder.position + Vector3(0, -0.6, cell * 0.42)
		world.add_child(lbl)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(rows * cell * 1.15 * 0.75 + 6.0, cols * cell * 0.5625 * 1.02)
	cam.position = Vector3(0, 60, 60)
	cam.look_at(Vector3(0, 0, 0))
	cam.current = true
	for f: int in 12:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("page_%02d.png" % p)
	img.save_png(path)
	var names := FileAccess.open(out_dir.path_join("page_%02d.txt" % p), FileAccess.WRITE)
	for i: int in batch.size():
		names.store_line("%d %s" % [i, batch[i]])
	print("PAGE ", path)
	world.queue_free()
	await process_frame
