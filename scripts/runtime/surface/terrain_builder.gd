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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
			c = c.lerp(c.lightened(0.12), clampf(detail.get_noise_2d(ix * 3.0, iz * 3.0) * 0.5 + 0.5, 0, 1) * 0.35)
			if biome_id == "ice" and h > height_scale * 0.4:
				c = c.lerp(Color.WHITE, 0.5)
			if water_level > -50.0 and h < water_level + 0.8:
				c = sand.lerp(sand.darkened(0.45), clampf((water_level - h) / 2.0, 0.0, 1.0))  # beaches and wet sea floor
			cols[iz * (n + 1) + ix] = c
	# Faceted (flat-shaded) triangles: one normal and one colour per face, the low-poly look of the packs.
	for iz: int in n:
		for ix: int in n:
			var i := iz * (n + 1) + ix
			var quad := [i, i + 1, i + n + 1, i + 1, i + n + 2, i + n + 1]
			for t: int in 2:
				var ids := [quad[t * 3], quad[t * 3 + 1], quad[t * 3 + 2]]
				var vs: Array[Vector3] = []
				var fc := Color(0, 0, 0, 0)
				for k: int in ids:
					vs.append(Vector3(-half + (k % (n + 1)) * step, heights[k], -half + (k / (n + 1)) * step))
					fc += cols[k] / 3.0
				var fn := (vs[2] - vs[0]).cross(vs[1] - vs[0]).normalized()
				st.set_color(Color(fc.r, fc.g, fc.b, 1.0))
				st.set_normal(fn)
				for v: Vector3 in vs:
					st.add_vertex(v)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)
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
		pm.size = Vector2(size_m * 3.0, size_m * 3.0)
		pm.subdivide_width = 96
		pm.subdivide_depth = 96
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
