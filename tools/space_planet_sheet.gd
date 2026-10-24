extends SceneTree
## Evidence/tuning only (D-044): renders the six destination planets and the
## three approach gas giants in their space look (PlanetLook, Synty planet masks)
## against the nebula backdrop, like the pack's planet sheet. Needs a GPU window:
##   godot --path . --resolution 1600x900 --script res://tools/space_planet_sheet.gd -- --out=C:/abs/sheet.png

var _out := "user://space_planet_sheet.png"


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var root := Node3D.new()
	get_root().add_child(root)
	var back := SpaceBackdrop.new()
	root.add_child(back)
	var ids := ["viridia", "pelagos", "ferrum", "sere", "nivalis", "umbra"]
	var gg: Dictionary = DictUtil.get_dict(DictUtil.load_json(PlanetLook.DATA), "gas_giants")
	var i := 0
	for id: String in ids:
		var m := PlanetLook.synty_material(id, hash(id))
		var pos := Vector3(-21.0 + (i % 3) * 21.0, 9.0 - (i / 3) * 16.0, 0.0)
		_sphere(root, m if m else StandardMaterial3D.new(), pos, 6.5)
		var ring: Dictionary = DictUtil.get_dict(DictUtil.get_dict(DictUtil.get_dict(DictUtil.load_json(PlanetLook.DATA), "planets"), id), "ring")
		if not ring.is_empty():
			var r := PlanetLook.ring_node(6.5, ring)
			r.position = pos
			root.add_child(r)
		i += 1
	var j := 0
	for biome: String in gg.keys():
		var m2 := PlanetLook.sheet_material(gg[biome], 31)
		_sphere(root, m2 if m2 else StandardMaterial3D.new(), Vector3(-21.0 + j * 21.0, -23.0, 0.0), 5.0)
		j += 1
	var cam := Camera3D.new()
	cam.position = Vector3(0, -3, 62)
	cam.fov = 50
	root.add_child(cam)
	cam.make_current()
	for f: int in 30:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(_out)
	print("SHEET ", _out)
	quit(0)


func _sphere(root: Node3D, m: Material, pos: Vector3, r: float) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 96
	s.rings = 48
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = Vector3(12, 30, 8)
	root.add_child(mi)
