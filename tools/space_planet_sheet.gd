extends SceneTree
## Evidence/tuning only (D-044): renders the six destination planets and the
## three approach gas giants in their space look (PlanetLook, Synty planet masks,
## faceted planet models, halos, rings and moons since D-046)
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
		# The real space path (D-046): the planet slot, PlanetLook.apply with the
		# faceted pack model, halo, ring and moons, scaled to the sheet.
		var pd: Variant = DictUtil.load_json("res://data/planets/%s.json" % id)  # no autoloads under --script
		var biome := str((pd as Dictionary).get("biome_id", "green")) if pd is Dictionary else "green"
		var slot := VisualSlot.make("space.planet_" + biome)
		slot.position = Vector3(-21.0 + (i % 3) * 21.0, 9.0 - (i / 3) * 16.0, 0.0)
		slot.scale = Vector3.ONE * (6.5 / 60.0)
		slot.rotation_degrees = Vector3(12, 30, 8)
		root.add_child(slot)
		PlanetLook.apply(slot, biome, "", hash(id), id)
		i += 1
	var j := 0
	for biome: String in gg.keys():
		var m2 := PlanetLook.sheet_material(gg[biome], 31)
		var pos := Vector3(-21.0 + j * 21.0, -23.0, 0.0)
		var mi := _sphere(root, m2 if m2 else StandardMaterial3D.new(), pos, 5.0)
		var model := PlanetLook.model_of(str((gg[biome] as Dictionary).get("mesh", "")))
		if not model.is_empty():
			PlanetLook.fit_model(mi, model, 5.0, pos, [12, 30, 8])
		if m2:
			var h := PlanetLook.halo_node(5.0, Color(str((gg[biome] as Dictionary).get("atmo", "#8fd0ff"))), 0.9)
			h.position = pos
			root.add_child(h)
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


func _sphere(root: Node3D, m: Material, pos: Vector3, r: float) -> MeshInstance3D:
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
	return mi
