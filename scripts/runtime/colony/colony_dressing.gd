class_name ColonyDressing
extends Node3D
## Draws every building's planned dressing (BuildingDressing) as one MultiMesh
## per mesh for the whole colony, plus small lamps that glow on dark worlds.
## A prop is dropped when it would touch another building's footprint, a
## corridor tube or a road, so placement and collision stay owned by the domain
## and the building views. Rebuilt only when the building set changes.
## Presentation only: no collision, no picking.

const MAX_LIGHTS := 48

var _bulb_mesh: SphereMesh
## Props that survived the clearance test: [Vector2 position, radius] (walkers keep off them).
var kept: Array = []


## views: building id -> BuildingView. clear: ColonyClearance with footprints,
## corridors and roads. light_scale: lamp brightness for this world.
func rebuild(views: Dictionary, terrain: TerrainBuilder, clear: ColonyClearance, light_scale: float) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var batches: Dictionary = {}  # Mesh -> Array[Transform3D]
	var ranges: Dictionary = {}   # Mesh -> visibility range
	var lights: Array = []        # [Vector3 pos, Color]
	kept.clear()
	for bid: int in views.keys():
		var v: BuildingView = views[bid]
		if not is_instance_valid(v) or v.dressing.is_empty():
			continue
		var vxf := v.global_transform if v.is_inside_tree() else v.transform
		for it: Dictionary in v.dressing:
			var kind := str(it["kind"])
			if v.constructing() and not bool(it["build"]):
				continue
			var xf: Transform3D = vxf * (it["xf"] as Transform3D)
			if kind != "platform":
				var p := Vector2(xf.origin.x, xf.origin.z)
				if clear.blocked(p, float(it["r"]), bid):
					continue
				kept.append([p, float(it["r"])])
				# Stand on the real ground (the ring can leave the flattened district).
				xf.origin.y = terrain.height_at(p.x, p.y) + (xf.origin.y - vxf.origin.y) - 0.03
			var pr: Dictionary = BuildingDressing.parts(str(it["mesh"]))
			var big := kind in ["platform", "park"] or float(it["top"]) > 2.5
			for part: Array in pr["parts"]:
				var m: Mesh = part[0]
				if not batches.has(m):
					batches[m] = []
					ranges[m] = 0.0
				(batches[m] as Array).append(xf * (part[1] as Transform3D))
				ranges[m] = maxf(float(ranges[m]), 420.0 if big else 190.0)
			var col := str(it["light"])
			if not col.is_empty():
				lights.append([xf * (it["light_at"] as Vector3), Color(col)])
	for m: Mesh in batches.keys():
		var xfs: Array = batches[m]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = float(ranges[m])
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	_add_lights(lights, light_scale)


## Each lamp gets a small glowing bulb; a capped, evenly spread subset also casts
## real light (no shadows, fades out with distance) so the colony glows at night.
func _add_lights(lights: Array, light_scale: float) -> void:
	if lights.is_empty():
		return
	if _bulb_mesh == null:
		_bulb_mesh = SphereMesh.new()
		_bulb_mesh.radius = 0.14
		_bulb_mesh.height = 0.28
		_bulb_mesh.radial_segments = 8
		_bulb_mesh.rings = 4
	var by_col: Dictionary = {}
	for l: Array in lights:
		var key := (l[1] as Color).to_html(false)
		if not by_col.has(key):
			by_col[key] = []
		(by_col[key] as Array).append(l[0])
	for key: String in by_col.keys():
		var pts: Array = by_col[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _bulb_mesh
		mm.instance_count = pts.size()
		for i: int in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(key)
		mat.emission_enabled = true
		mat.emission = Color(key)
		mat.emission_energy_multiplier = 2.0 + 2.0 * light_scale
		mmi.material_override = mat
		mmi.visibility_range_end = 260.0
		add_child(mmi)
	if light_scale <= 0.05:
		return
	var step := maxi(1, int(ceil(lights.size() / float(MAX_LIGHTS))))
	for i: int in range(0, lights.size(), step):
		var l: Array = lights[i]
		var ol := OmniLight3D.new()
		ol.position = (l[0] as Vector3) + Vector3(0, 0.25, 0)
		ol.light_color = l[1]
		ol.light_energy = 1.4 * light_scale
		ol.omni_range = 7.0
		ol.omni_attenuation = 1.2
		ol.shadow_enabled = false
		ol.light_specular = 0.2
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 120.0
		ol.distance_fade_length = 40.0
		add_child(ol)
