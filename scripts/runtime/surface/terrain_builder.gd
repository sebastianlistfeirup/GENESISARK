class_name TerrainBuilder
extends Node3D
## Deterministic biome terrain around one landing site (bible p.9: three
## hand-tuned districts per site; no free procedural planet). Flattened
## zones keep landing pads, sample points and building districts walkable.
## Height noise is seeded from the biome map so every visit looks the same.

var biome_id := "green"
var map_def: Dictionary = {}
var site: Dictionary = {}
var size_m := 200.0
var step := 1.0
var flat_zones: Array = []   # [{center: Vector2, radius: float, height: float}]
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var palette: Dictionary = {}
var height_scale := 9.0
var water_level := -100.0
## Planet terrain style from data/art/ground_cover.json (D-039): amp, dunes, ridges,
## terraces, water, ground/patch/cliff colours. Empty = the biome map as before.
var style: Dictionary = {}
var _far_args: Array = []  # far-ring material and colours, reused by build_horizon


func setup(p_biome: String, p_site: Dictionary, p_palette: Dictionary, p_size: float = 200.0) -> void:
	biome_id = p_biome
	map_def = DictUtil.get_dict(GameSession.content.biome_maps.get(p_biome, {}), "map")
	site = p_site
	palette = p_palette
	size_m = p_size
	step = Quality.value("terrain_step", step)
	height_scale = DictUtil.get_float(map_def, "height_scale", 9.0)
	water_level = DictUtil.get_float(map_def, "water_level", -100.0)
	noise.seed = DictUtil.get_int(map_def, "terrain_seed", 1)
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	detail.seed = noise.seed + 7
	detail.frequency = 0.08


## Give the map its planet's own shape and colours (call before build()).
func apply_planet_style(planet_id: String) -> void:
	style = DictUtil.get_dict(GroundCover.spec_for(planet_id, biome_id), "terrain")


## Wet worlds: the sea covers the lowest part of the map (style "sea", default
## 40 % of it); every point the player must reach is raised onto land with a soft
## shoulder, so routes become spits and causeways between lagoons.
var _lift: PackedFloat32Array = PackedFloat32Array()
var _lift_n := 0
const LIFT_CELL := 2.0
const LIFT_RADIUS := 7.0


func set_water_below(points: Array, lift: bool = true) -> void:
	if not bool(style.get("water", false)) or points.is_empty():
		return
	if not lift:
		# Colony: wide flat districts must stay clearly dry; the sea only fills the low ground.
		var lo := INF
		for p: Variant in points:
			var v: Vector2 = p
			lo = minf(lo, height_at(v.x, v.y))
		var hs2: Array = []
		for iz: int in 30:
			for ix: int in 30:
				hs2.append(height_at(-size_m * 0.45 + ix * size_m * 0.9 / 29.0, -size_m * 0.45 + iz * size_m * 0.9 / 29.0))
		hs2.sort()
		water_level = minf(float(hs2[int(hs2.size() * float(style.get("sea", 0.4)))]), lo - 0.8)
		return
	var hs: Array = []
	var half := size_m * 0.45
	for iz: int in 30:
		for ix: int in 30:
			hs.append(height_at(-half + ix * size_m * 0.9 / 29.0, -half + iz * size_m * 0.9 / 29.0))
	hs.sort()
	water_level = float(hs[int(hs.size() * float(style.get("sea", 0.4)))])
	_lift_n = int(size_m / LIFT_CELL) + 1
	_lift.resize(_lift_n * _lift_n)
	_lift.fill(0.0)
	var r_cells := int(ceil(LIFT_RADIUS / LIFT_CELL))
	for p: Variant in points:
		var v: Vector2 = p
		var cx := int(round((v.x + size_m * 0.5) / LIFT_CELL))
		var cz := int(round((v.y + size_m * 0.5) / LIFT_CELL))
		for dz: int in range(-r_cells, r_cells + 1):
			for dx: int in range(-r_cells, r_cells + 1):
				var x := cx + dx
				var z := cz + dz
				if x < 0 or z < 0 or x >= _lift_n or z >= _lift_n:
					continue
				var d := Vector2(dx, dz).length() * LIFT_CELL
				var w := 1.0 - smoothstep(LIFT_RADIUS * 0.45, LIFT_RADIUS, d)
				_lift[z * _lift_n + x] = maxf(_lift[z * _lift_n + x], w)


func _lift_at(x: float, z: float) -> float:
	if _lift_n == 0:
		return 0.0
	var fx := clampf((x + size_m * 0.5) / LIFT_CELL, 0.0, _lift_n - 1.001)
	var fz := clampf((z + size_m * 0.5) / LIFT_CELL, 0.0, _lift_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_lift[iz * _lift_n + ix], _lift[iz * _lift_n + ix + 1], tx)
	var b := lerpf(_lift[(iz + 1) * _lift_n + ix], _lift[(iz + 1) * _lift_n + ix + 1], tx)
	return lerpf(a, b, tz)


func add_flat(center: Vector2, radius: float) -> void:
	flat_zones.append({"center": center, "radius": radius})


## Local coords (site-relative). Sampled in world-map coords so sites differ.
func height_at(x: float, z: float) -> float:
	var sc: Array = DictUtil.get_arr(site, "center")
	var wx := x + (float(sc[0]) if sc.size() == 2 else 0.0)
	var wz := z + (float(sc[1]) if sc.size() == 2 else 0.0)
	var amp := float(style.get("amp", 1.0))
	var h := noise.get_noise_2d(wx, wz) * height_scale * amp + detail.get_noise_2d(wx, wz) * 0.6
	if biome_id == "desert":
		h += pow(absf(noise.get_noise_2d(wx * 0.5, wz * 0.5)), 2.0) * height_scale * 1.2
	if style.has("ridges"):  # sharp crests (ice, night world)
		var rn := 1.0 - absf(noise.get_noise_2d(wx * 1.9 + 300.0, wz * 1.9))
		h += pow(rn, 3.0) * height_scale * 0.7 * float(style["ridges"])
	if style.has("dunes"):  # wind-driven dune crests plus small ripples
		var warp := noise.get_noise_2d(wx * 0.6, wz * 0.6) * 4.0
		h += pow(absf(sin(wx * 0.06 + wz * 0.025 + warp)), 1.6) * 2.4 * float(style["dunes"])
		h += sin(wx * 0.9 + wz * 0.35 + warp * 2.0) * 0.08 * float(style["dunes"])
	if style.has("terraces"):  # mesas: soft steps
		var ts := float(style["terraces"])
		var tq: float = floor(h / ts)
		h = (tq + smoothstep(0.25, 0.75, h / ts - tq)) * ts
	var f := 1.0
	for fz: Dictionary in flat_zones:
		var d := Vector2(x, z).distance_to(fz["center"])
		var r: float = fz["radius"]
		f = minf(f, smoothstep(r, r + 14.0, d))
	var base := noise.get_noise_2d(float(sc[0]) if sc.size() == 2 else 0.0, float(sc[1]) if sc.size() == 2 else 0.0) * height_scale * 0.3
	# Rim rises toward the region edge so the playable area reads as a valley.
	var edge := smoothstep(size_m * 0.32, size_m * 0.5, maxf(absf(x), absf(z))) * height_scale * 1.6
	var out := lerpf(base, h, f) + edge
	if _lift_n > 0:
		var lw := _lift_at(x, z)
		if lw > 0.0:
			out = maxf(out, lerpf(out, water_level + 0.7, lw))
	return out


func build() -> void:
	var n := int(size_m / step)
	var half := size_m * 0.5
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz: int in n + 1:
		for ix: int in n + 1:
			heights[iz * (n + 1) + ix] = height_at(-half + ix * step, -half + iz * step)
	var base := Color(str(palette.get("nature", DictUtil.get_str(map_def, "base_color", "#556b4a"))))
	var rock := Color(DictUtil.get_str(map_def, "rock_color", "#6f6a60"))
	var ground := base.darkened(0.25) if biome_id == "green" else (base.darkened(0.12) if biome_id == "ice" else base)
	# Synty-style ground: richer base, a second tone in broad patches, dark rocky slopes.
	ground = Color.from_hsv(ground.h, clampf(ground.s * 1.25, 0.0, 1.0), ground.v)
	var patch := Color.from_hsv(fposmod(ground.h + 0.03, 1.0), clampf(ground.s * 1.1, 0.0, 1.0), ground.v * 0.82)
	var cliff := rock.darkened(0.35).lerp(ground.darkened(0.55), 0.35)
	if style.has("ground"):
		ground = Color(str(style["ground"]))
		patch = Color(str(style.get("patch", style["ground"])))
		cliff = Color(str(style.get("cliff", "#4a4a4a")))
	var sand := Color(str(style.get("patch", "#c9b98a")))
	var cols := PackedColorArray()
	cols.resize((n + 1) * (n + 1))
	for iz: int in n + 1:
		for ix: int in n + 1:
			var h := heights[iz * (n + 1) + ix]
			var hx := heights[iz * (n + 1) + mini(ix + 1, n)] - heights[iz * (n + 1) + maxi(ix - 1, 0)]
			var hz := heights[mini(iz + 1, n) * (n + 1) + ix] - heights[maxi(iz - 1, 0) * (n + 1) + ix]
			var slope := 1.0 - Vector3(-hx, 2.0 * step, -hz).normalized().y
			var c := ground.lerp(patch, smoothstep(0.1, 0.35, detail.get_noise_2d(ix * 0.7, iz * 0.7)))
			c = c.lerp(cliff, smoothstep(0.08, 0.3, slope))
			if style.has("terraces") and slope > 0.15:
				# Mesa walls show geological strata: alternating bands by height.
				var band := fposmod(h / (float(style["terraces"]) * 0.5), 1.0)
				c = c.lerp(c.lightened(0.18) if band < 0.5 else c.darkened(0.18), 0.8)
			c = c.lerp(c.lightened(0.12), clampf(detail.get_noise_2d(ix * 3.0, iz * 3.0) * 0.5 + 0.5, 0, 1) * 0.35)
			if biome_id == "ice" and h > height_scale * 0.4:
				c = c.lerp(Color.WHITE, 0.5)
			if water_level > -50.0 and h < water_level + 0.8:
				c = sand.lerp(sand.darkened(0.45), clampf((water_level - h) / 2.0, 0.0, 1.0))  # beaches and wet sea floor
			cols[iz * (n + 1) + ix] = c
	# Faceted (flat-shaded) triangles: one normal and one colour per face, the low-poly look of the packs.
	# Written straight into packed arrays (same vertices, order and format as the
	# SurfaceTool version, D-054: ~3x faster, the colony loads sooner).
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var vcols := PackedColorArray()
	verts.resize(n * n * 6)
	norms.resize(n * n * 6)
	vcols.resize(n * n * 6)
	var wi := 0
	for iz: int in n:
		var z0 := -half + iz * step
		var z1 := -half + (iz + 1) * step
		for ix: int in n:
			var i := iz * (n + 1) + ix
			var x0 := -half + ix * step
			var x1 := -half + (ix + 1) * step
			var a := Vector3(x0, heights[i], z0)
			var b := Vector3(x1, heights[i + 1], z0)
			var c := Vector3(x0, heights[i + n + 1], z1)
			var d := Vector3(x1, heights[i + n + 2], z1)
			# Triangle 1: i, i + 1, i + n + 1 -> a, b, c
			var fc := cols[i] / 3.0 + cols[i + 1] / 3.0 + cols[i + n + 1] / 3.0
			var fn := (c - a).cross(b - a).normalized()
			var col := Color(fc.r, fc.g, fc.b, 1.0)
			verts[wi] = a
			verts[wi + 1] = b
			verts[wi + 2] = c
			norms[wi] = fn
			norms[wi + 1] = fn
			norms[wi + 2] = fn
			vcols[wi] = col
			vcols[wi + 1] = col
			vcols[wi + 2] = col
			# Triangle 2: i + 1, i + n + 2, i + n + 1 -> b, d, c
			fc = cols[i + 1] / 3.0 + cols[i + n + 2] / 3.0 + cols[i + n + 1] / 3.0
			fn = (c - b).cross(d - b).normalized()
			col = Color(fc.r, fc.g, fc.b, 1.0)
			verts[wi + 3] = b
			verts[wi + 4] = d
			verts[wi + 5] = c
			norms[wi + 3] = fn
			norms[wi + 4] = fn
			norms[wi + 5] = fn
			vcols[wi + 3] = col
			vcols[wi + 4] = col
			vcols[wi + 5] = col
			wi += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = vcols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	var gt := str(style.get("ground_tex", ""))
	if not gt.is_empty() and ResourceLoader.exists(gt):
		# Planet ground detail (luminance only, the planet keeps its colour).
		var dm := ShaderMaterial.new()
		dm.shader = preload("res://art/shaders/terrain_detail.gdshader")
		dm.set_shader_parameter("ground_tex", load(gt))
		var ct := str(style.get("cliff_tex", gt))
		dm.set_shader_parameter("cliff_tex", load(ct if ResourceLoader.exists(ct) else gt))
		mi.material_override = dm
	add_child(mi)
	_build_far_ring(mi.material_override, ground, patch, cliff)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 16 | 1
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n + 1
	hm.map_depth = n + 1
	hm.map_data = heights
	cs.shape = hm
	cs.scale = Vector3(step, 1, step)
	body.add_child(cs)
	add_child(body)
	if water_level > -50.0:
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size_m, size_m)
		w.mesh = pm
		w.position.y = water_level
		var wm := ShaderMaterial.new()
		wm.shader = preload("res://art/shaders/water.gdshader")
		w.material_override = wm
		var span := 960.0 if bool(style.get("ocean", false)) else size_m * 3.0  # a water world's sea reaches the horizon
		pm.size = Vector2(span, span)
		pm.subdivide_width = 128 if span > size_m * 3.0 else 96
		pm.subdivide_depth = pm.subdivide_width
		add_child(w)


func scatter(rng_seed: int, count: int, avoid: Array) -> void:
	count = int(count * Quality.value("scatter_scale", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var slots: Array = {"green": ["surface.tree_green", "surface.tree_green", "surface.plant_green", "surface.rock_small", "surface.rock_large"],
		"desert": ["surface.desert_rock", "surface.rock_large", "surface.rock_small", "surface.rock_small"],
		"ice": ["surface.ice_spire", "surface.crystal_ice", "surface.rock_large", "surface.rock_small"]}.get(biome_id, ["surface.rock_small"])
	var props := Node3D.new()
	props.name = "Scatter"
	add_child(props)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 10:
		tries += 1
		var p := Vector2(rng.randf_range(-size_m * 0.45, size_m * 0.45), rng.randf_range(-size_m * 0.45, size_m * 0.45))
		var ok := true
		for a: Array in avoid:
			if p.distance_to(a[0]) < float(a[1]):
				ok = false
				break
		if not ok:
			continue
		var slot: String = slots[rng.randi() % slots.size()]
		var v := VisualSlot.make(slot)
		v.position = Vector3(p.x, height_at(p.x, p.y) - 0.1, p.y)
		v.rotation.y = rng.randf() * TAU
		var s := rng.randf_range(0.7, 1.5)
		v.scale = Vector3.ONE * s
		props.add_child(v)
		if slot.contains("rock_large") or slot.contains("spire") or slot.contains("desert_rock") or slot.contains("tree"):
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.2 * s
			cyl.height = 4.0 * s
			cs.shape = cyl
			cs.position.y = cyl.height * 0.5
			sb.add_child(cs)
			sb.position = v.position
			props.add_child(sb)
		placed += 1


## Environment + sun for a world: data-driven, see Lighting / data/art/lighting.json.
static func environment_for(p: Dictionary, biome: String) -> Array:
	var planet := p.duplicate()
	if not planet.has("biome_id"):
		planet["biome_id"] = biome
	return Lighting.build(planet)


## Distant land out to the horizon (no collision, coarse facets): the playable map
## no longer ends in a cut edge against the sky. Same height function and colours,
## so the rim hills continue into the haze.
func _build_far_ring(mat: Material, ground: Color, patch: Color, cliff: Color, far: float = 460.0, fs: float = 10.0, skip_r: float = -1.0, curve_r: float = 0.0, ring_name: String = "FarTerrain") -> MeshInstance3D:
	_far_args = [mat, ground, patch, cliff]
	var inner := size_m * 0.5 - step * 2.0
	if skip_r < 0.0:
		skip_r = inner - fs
	var n := int(far * 2.0 / fs)
	var ocean := water_level > -50.0 and bool(style.get("ocean", false))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz: int in n:
		for ix: int in n:
			var x0 := -far + ix * fs
			var z0 := -far + iz * fs
			if maxf(absf(x0 + fs * 0.5), absf(z0 + fs * 0.5)) < skip_r:
				continue
			var q := [Vector2(x0, z0), Vector2(x0 + fs, z0), Vector2(x0, z0 + fs), Vector2(x0 + fs, z0), Vector2(x0 + fs, z0 + fs), Vector2(x0, z0 + fs)]
			for t: int in 2:
				var vs: Array[Vector3] = []
				for k: int in 3:
					var v: Vector2 = q[t * 3 + k]
					var h := height_at(v.x, v.y)
					var dist := maxf(absf(v.x), absf(v.y))
					h += smoothstep(size_m * 0.5, 460.0, dist) * height_scale * 2.5 * (0.6 + 0.4 * detail.get_noise_2d(v.x * 0.05, v.y * 0.05))
					if dist > 460.0:  # descent horizon: broad hills far out, and the globe's curve
						h += noise.get_noise_2d(v.x * 0.004, v.y * 0.004) * height_scale * 6.0 * smoothstep(460.0, 1400.0, dist)
					if curve_r > 0.0:  # zero at the far ring's edge, so the seam stays closed
						h -= maxf(0.0, v.x * v.x + v.y * v.y - 211600.0) / (2.0 * curve_r)
					if ocean:
						# Water world: open sea to the horizon, broken by scattered islands.
						var isle := maxf(0.0, detail.get_noise_2d(v.x * 0.012 + 40.0, v.y * 0.012) - 0.18) * height_scale * 9.0
						h = lerpf(h, water_level - 5.0 + isle, ocean_shore(v, dist))
					if dist < inner:
						h -= 3.0  # tucked under the playable mesh where they overlap
					vs.append(Vector3(v.x, h, v.y))
				var fn := (vs[2] - vs[0]).cross(vs[1] - vs[0]).normalized()
				var slope := 1.0 - fn.y
				var c := ground.lerp(patch, clampf(detail.get_noise_2d(vs[0].x * 0.08, vs[0].z * 0.08) * 0.5 + 0.5, 0, 1)).lerp(cliff, smoothstep(0.1, 0.35, slope))
				var far_k := smoothstep(size_m * 0.5, size_m * 0.5 + 160.0, maxf(absf(vs[0].x), absf(vs[0].z)))
				# Same light speckle as the playable ground at the seam, so the two meet;
				# it fades with distance (one random shade per 10-90 m cell read as a
				# checkerboard from the air).
				c = c.lerp(c.lightened(0.12), clampf(detail.get_noise_2d(vs[0].x, vs[0].z) * 0.5 + 0.5, 0, 1) * 0.35 * (1.0 - 0.8 * far_k))
				if far_k > 0.0:  # far land: broad regions of darker and lighter ground, faded in past the map edge
					var reg := noise.get_noise_2d(vs[0].x * 0.0022 + 90.0, vs[0].z * 0.0022)
					var rc := c.lerp(c.darkened(0.38), smoothstep(-0.05, 0.4, reg)).lerp(patch.lightened(0.12), smoothstep(-0.2, -0.5, reg))
					c = c.lerp(rc, far_k)
				if biome_id == "ice" and vs[0].y > height_scale * 0.6:
					c = c.lerp(Color.WHITE, 0.6)
				st.set_color(c)
				st.set_normal(fn)
				for v: Vector3 in vs:
					st.add_vertex(v)
	var ring := MeshInstance3D.new()
	ring.name = ring_name
	ring.mesh = st.commit()
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	return ring


## Water world: how far past the map edge the land has sunk into the sea (0..1).
## The shore wanders 40-320 m out with the noise, so from the air the site is a
## ragged island, not a square plateau (0 at the map edge: the seam stays closed).
func ocean_shore(v: Vector2, dist: float) -> float:
	var reach := lerpf(40.0, 320.0, clampf(detail.get_noise_2d(v.x * 0.05 + 17.0, v.y * 0.05 - 9.0) * 0.9 + 0.5, 0.0, 1.0))
	return smoothstep(0.0, reach, dist - size_m * 0.5)


## Land from the far ring out to the horizon for the descent from orbit (coarse
## facets, same colours and height field, dropping away with the globe's curve).
## Removed again after touchdown.
func build_horizon(outer: float, cell: float, curve_r: float) -> MeshInstance3D:
	if _far_args.is_empty():
		return null
	return _build_far_ring(_far_args[0], _far_args[1], _far_args[2], _far_args[3], outer, cell, 460.0 - cell, curve_r, "HorizonTerrain")
