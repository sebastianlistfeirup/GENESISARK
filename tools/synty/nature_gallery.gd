extends SceneTree
## Contact sheet for Nature Biomes FBX through NatureKit (rebuilt materials).
##   godot --path . --resolution 1920x1080 --script res://tools/synty/nature_gallery.gd -- --dir=res://assets/Synty/Nature/Jungle/FBX --filter=Tree --out=C:/tmp/x.png [--hue=0.3]
func _init() -> void: _go.call_deferred()
func _go() -> void:
	var dir := ""; var filt := ""; var out := "user://nature.png"; var look := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"dir": dir = kv[1]
			"filter": filt = kv[1]
			"out": out = kv[1]
			"hue": look["hue_shift"] = float(kv[1])
	var files: Array = []
	_collect(dir, filt, files)
	files = files.slice(0, 32)
	var w := Node3D.new(); root.add_child(w)
	var we := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.5, 0.6, 0.7); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.6; we.environment = e; w.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; w.add_child(sun)
	var cols := 8; var cell := 10.0
	for i: int in files.size():
		var m := NatureKit.mesh(files[i], look)
		if m.is_empty(): continue
		var b: AABB = m[2]
		var s := cell * 0.8 / maxf(b.size.x, maxf(b.size.y, b.size.z))
		var mi := MeshInstance3D.new(); mi.mesh = m[0]
		mi.scale = Vector3.ONE * s
		mi.position = Vector3((i % cols - 3.5) * cell, -b.position.y * s, (i / cols - 1.5) * cell * 1.2) - Vector3(b.get_center().x, 0, b.get_center().z) * s
		w.add_child(mi)
		var l := Label3D.new(); l.text = "%d %s %.0fm" % [i, files[i].get_file().get_basename().trim_prefix("SM_Env_").trim_prefix("SM_Prop_"), b.size.y]; l.font_size = 56; l.pixel_size = 0.01; l.outline_size = 8; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3((i % cols - 3.5) * cell, -0.6, (i / cols - 1.5) * cell * 1.2 + cell * 0.42); w.add_child(l)
	var cam := Camera3D.new(); w.add_child(cam); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 34; cam.position = Vector3(0, 50, 50); cam.look_at(Vector3(0, 3, 0)); cam.current = true
	for f: int in 15: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("NATURE ", files.size(), " -> ", out)
	quit()


func _collect(dir: String, filt: String, files: Array) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".fbx") and (filt.is_empty() or f.contains(filt)) and not f.contains("LOD") and not f.contains("Collision"):
			files.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if d != "Collision":
			_collect(dir.path_join(d), filt, files)
