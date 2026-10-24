class_name FlightCockpit
extends Node3D
## Cockpit view for the approach flight (D-044, the key art's bridge shot): the
## POLYGON Sci-Fi Space POV cockpit and window frame (local pack) around the
## camera, faint glass, glowing dashboard screens, a turning NAV hologram over
## the console and a targeting ring floating ahead in the window. Lives under
## the flight's ship node, so it follows the Ark; presentation only (gameplay,
## hazards and hit bookkeeping never read it). Data: space_scenery.json -> cockpit.
## Missing pack files: build() returns false and the flight stays in chase view.

const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 color : source_color = vec3(0.35, 0.9, 1.0);
uniform float energy = 1.6;
uniform float scan = 1.0;
void fragment() {
	float lines = 0.75 + 0.25 * sin(FRAGCOORD.y * 1.6 + TIME * 6.0 * scan);
	float fres = 0.55 + 0.45 * pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color * energy * lines * fres;
}
"""
const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(0.45, 0.75, 1.0);
void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	float sheen = smoothstep(0.62, 0.7, fract(UV.x * 0.7 + UV.y * 0.9)) * (1.0 - smoothstep(0.7, 0.8, fract(UV.x * 0.7 + UV.y * 0.9)));
	ALBEDO = tint * (0.02 + fres * 0.18 + sheen * 0.05);
}
"""

## Render layer of the cockpit meshes: the flight's sun and fill skip it, so
## only the cockpit's own warm/cyan lamps (and ambient) light the interior.
const LAYER := 1 << 9

var eye: Node3D        # camera mount (local -Z looks out of the window)
var _holo: Node3D
var _ring: Node3D
var _reduced := false
var _t := 0.0


## Builds the cockpit; false if the pack's cockpit model is missing.
func build(spec: Dictionary, atlas: Material) -> bool:
	name = "Cockpit"
	_reduced = FxEffect.reduced_motion()
	# A graded copy of the atlas: mauve plating, screens keep their glow.
	if atlas is ShaderMaterial and spec.has("albedo_mul"):
		atlas = (atlas as ShaderMaterial).duplicate()
		(atlas as ShaderMaterial).set_shader_parameter("albedo_mul", Color(str(spec["albedo_mul"])))
		(atlas as ShaderMaterial).set_shader_parameter("glow_energy", float(spec.get("glow_energy", 2.8)))
	var body := _model(str(spec.get("body", "")), atlas)
	if body == null:
		return false
	# The pack's cockpit looks along +Z; the flight flies along -Z.
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.rotation_degrees.y = 180.0
	rig.scale = Vector3.ONE * float(spec.get("scale", 1.0))
	add_child(rig)
	rig.add_child(body)
	var frame := _model(str(spec.get("frame", "")), atlas)
	if frame != null:
		rig.add_child(frame)
	var glass_mat := ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = GLASS_SHADER
	glass_mat.shader = gs
	for n: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER
		if "Glass" in str(mi.name):
			mi.material_override = glass_mat
	var e: Array = DictUtil.get_arr(spec, "eye")
	eye = Node3D.new()
	eye.name = "Eye"
	rig.add_child(eye)
	eye.position = Vector3(float(e[0]), float(e[1]), float(e[2])) if e.size() == 3 else Vector3(0, 0.78, -0.75)
	# Mount looks out of the window (+Z in rig space), slightly down at the dash.
	eye.rotation_degrees = Vector3(-float(spec.get("eye_pitch", 6.0)), 180.0, 0.0)
	_interior_light(rig, spec)
	_holo = _hologram(rig, spec)
	_ring = _target_ring(spec)
	return true


func _process(delta: float) -> void:
	if not visible or _reduced:
		return
	_t += delta
	if _holo:
		_holo.rotation.y += delta * 0.6
		if _holo.get_child_count() > 1:
			(_holo.get_child(1) as Node3D).rotation.x += delta * 0.9
	if _ring:
		_ring.rotation.z += delta * 0.25


## Gentle head sway on top of the mount (0 with reduced motion); shake = 0..1.
func sway(shake: float) -> Transform3D:
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	if not _reduced:
		off = Vector3(sin(_t * 0.7) * 0.008, sin(_t * 1.13) * 0.006, 0.0)
		rot = Vector3(sin(_t * 0.53) * 0.004, sin(_t * 0.41) * 0.005, 0.0)
	if shake > 0.0:
		off += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.035 * shake
		rot += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02 * shake
	return Transform3D(Basis.from_euler(rot), off)


func _model(path: String, atlas: Material) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	for c: Node in ([n] if n is MeshInstance3D else []) + n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = atlas
	return n


## Warm salmon key from above + a cyan bounce off the screens (image3's grade).
func _interior_light(rig: Node3D, spec: Dictionary) -> void:
	var warm := OmniLight3D.new()
	warm.light_color = Color(str(spec.get("light_warm", "#ff9c86")))
	warm.light_energy = float(spec.get("warm_energy", 1.6))
	warm.omni_range = 3.2
	warm.position = Vector3(0, 1.3, -0.2)
	warm.shadow_enabled = false
	warm.light_cull_mask = LAYER
	rig.add_child(warm)
	var cool := OmniLight3D.new()
	cool.light_color = Color(str(spec.get("light_cool", "#4fe0ff")))
	cool.light_energy = float(spec.get("cool_energy", 1.2))
	cool.omni_range = 1.6
	cool.position = Vector3(0, 0.45, 0.45)
	cool.shadow_enabled = false
	cool.light_cull_mask = LAYER
	# Sun through the glass: a soft gold rim on the left window posts.
	var sunlit := OmniLight3D.new()
	sunlit.light_color = Color("ffb870")
	sunlit.light_energy = 0.9
	sunlit.omni_range = 2.0
	sunlit.position = Vector3(0.9, 1.1, 0.7)
	sunlit.shadow_enabled = false
	sunlit.light_cull_mask = LAYER
	rig.add_child(sunlit)
	rig.add_child(cool)


func _holo_mat(color: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = HOLO_SHADER
	m.shader = s
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("scan", 0.0 if _reduced else 1.0)
	return m


## NAV hologram over the centre console: the pack's HUD rings (local), turning.
func _hologram(rig: Node3D, spec: Dictionary) -> Node3D:
	var h: Dictionary = DictUtil.get_dict(spec, "hologram")
	var root := Node3D.new()
	root.name = "NavHologram"
	var p: Array = DictUtil.get_arr(h, "pos")
	root.position = Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3(0, 0.62, 0.42)
	rig.add_child(root)
	var mat := _holo_mat(Color(str(h.get("color", "#59e6ff"))), float(h.get("energy", 0.7)))
	var size := float(h.get("size", 0.16))
	for path: Variant in DictUtil.get_arr(h, "meshes"):
		var m := _model(str(path), mat)
		if m == null:
			continue
		var box := AssetSlots.aabb_of(m, Transform3D.IDENTITY)
		var s := size / maxf(0.001, box.get_longest_axis_size())
		var holder := Node3D.new()
		holder.add_child(m)
		m.position = -box.get_center()
		holder.scale = Vector3.ONE * s
		root.add_child(holder)
	# A small globe in the middle: the destination, drawn as light.
	var globe := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size * 0.22
	sm.height = size * 0.44
	sm.radial_segments = 16
	sm.rings = 8
	globe.mesh = sm
	globe.material_override = _holo_mat(Color(str(h.get("globe", "#ffb070"))), float(h.get("energy", 0.7)) * 0.45)
	root.add_child(globe)
	return root


## A thin targeting ring far ahead in the window (image3's HUD circles).
func _target_ring(spec: Dictionary) -> Node3D:
	var r: Dictionary = DictUtil.get_dict(spec, "target_ring")
	if r.is_empty():
		return null
	var m := _model(str(r.get("mesh", "")), _holo_mat(Color(str(r.get("color", "#59e6ff"))), 0.9))
	if m == null:
		return null
	var holder := Node3D.new()
	holder.name = "TargetRing"
	var box := AssetSlots.aabb_of(m, Transform3D.IDENTITY)
	m.position = -box.get_center()
	holder.add_child(m)
	var size := float(r.get("size", 9.0))
	holder.scale = Vector3.ONE * size / maxf(0.001, box.get_longest_axis_size())
	var p: Array = DictUtil.get_arr(r, "pos")
	holder.position = Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3(0, 0.5, -60)
	# Face the pilot: the ring mesh lies in its XY plane.
	add_child(holder)
	return holder
