class_name SpaceFx
extends RefCounted
## Glow pieces for ships in space after the POLYGON Sci-Fi Space key art (D-044):
## soft engine glows, long laser-like engine trails, and the Ark's lit window
## strips + engine nozzles. Presentation only: nothing here collides or is read
## by gameplay. Unshaded additive materials, no textures from disk.

static var _glow_tex: GradientTexture2D
static var _trail_tex: ImageTexture


## A soft round glow (billboard, additive) of the given diameter.
static func glow(size: float, color: Color, energy: float = 1.0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.albedo_texture = _glow_texture()
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A laser-like engine trail: two crossed ribbons from the origin along local
## +Z for `length` metres, a white-hot core fading into the colour and out.
static func trail(length: float, width: float, color: Color, energy: float = 3.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:
		var hw := axis * width * 0.5
		var a := -hw
		var b := hw
		var c := hw + Vector3(0, 0, length)
		var d := -hw + Vector3(0, 0, length)
		for v: Array in [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [c, Vector2(1, 1)], [a, Vector2(0, 0)], [c, Vector2(1, 1)], [d, Vector2(0, 1)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.albedo_texture = _trail_texture()
	var mi := MeshInstance3D.new()
	mi.name = "Trail"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = length
	return mi


## Across x: a thin white-hot core inside a soft coloured sheath; along y: fades out.
static func _trail_texture() -> ImageTexture:
	if _trail_tex == null:
		var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
		for y: int in 64:
			var along := pow(1.0 - y / 63.0, 1.6)
			for x: int in 32:
				var across := 1.0 - absf((x + 0.5) / 16.0 - 1.0)
				var core := pow(across, 8.0)
				var sheath := pow(across, 2.0) * 0.55
				var v := clampf((core + sheath) * along, 0.0, 1.0)
				var w := clampf(core * along, 0.0, 1.0)
				var lum := clampf(v * 0.75 + w * 0.6, 0.0, 1.0)
				img.set_pixel(x, y, Color(lum, lum, lum, 1.0))
		_trail_tex = ImageTexture.create_from_image(img)
	return _trail_tex


## Dresses the Ark exterior slot (Galactic Carrier) like the key art's capital
## ships: lit window strips on the hull sides (atlas shader window_* params on a
## copy of the slot's material) and glowing engine nozzles with trails. `spec`
## is space_scenery.json -> ark_fx; engine positions are in slot-local metres.
static func dress_ark(slot: Node3D, spec: Dictionary) -> void:
	if spec.is_empty():
		return
	var win: Dictionary = DictUtil.get_dict(spec, "windows")
	if not win.is_empty():
		var copies: Dictionary = {}
		for n: Node in slot.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var src := mi.material_override as ShaderMaterial
			if src == null or src.shader == null or not str(src.shader.resource_path).ends_with("synty_glow_atlas.gdshader"):
				continue
			if not copies.has(src):
				var m := src.duplicate() as ShaderMaterial
				m.set_shader_parameter("window_amount", float(win.get("amount", 1.0)))
				m.set_shader_parameter("window_energy", float(win.get("energy", 3.0)))
				var cell: Array = DictUtil.get_arr(win, "cell")
				if cell.size() == 2:
					m.set_shader_parameter("window_cell", Vector2(float(cell[0]), float(cell[1])))
				var size: Array = DictUtil.get_arr(win, "size")
				if size.size() == 2:
					m.set_shader_parameter("window_size", Vector2(float(size[0]), float(size[1])))
				m.set_shader_parameter("glow_energy", float(win.get("strip_energy", 3.2)))
				copies[src] = m
			mi.material_override = copies[src]
	var engine_col := Color(str(spec.get("engine_color", "#5fe8ff")))
	for e: Variant in DictUtil.get_arr(spec, "engines"):
		var a: Array = e
		if a.size() < 4:
			continue
		var pos := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var r := float(a[3])
		var holder := Node3D.new()
		holder.name = "Engine"
		holder.position = pos
		slot.add_child(holder)
		holder.add_child(glow(r * 2.6, engine_col, 1.2))
		var core := glow(r * 0.9, Color(1, 1, 1), 1.4)
		holder.add_child(core)
		# Trails run out of the nozzles, away from the bow (slot-local -Z).
		var t := trail(float(spec.get("trail_length", 60.0)) * r, r * 0.8, engine_col, 1.6)
		t.rotation_degrees.y = 180.0
		holder.add_child(t)


static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(0.5, 0.0)
		_glow_tex.width = 64
		_glow_tex.height = 64
	return _glow_tex
