class_name Hologram
extends Node3D
## A floating holographic display (Sci-Fi Space key art): glowing HUD frames and
## reticles that hover, bob and turn slowly above consoles. Frozen with reduced
## motion. Presentation only; built from the pack's SM_Hud_* meshes, skipped
## when they are missing.

const PARTS := ["SM_Hud_Box_01", "SM_Hud_Reticle_03", "SM_Hud_Reticle_08", "SM_Hud_Barrier_01"]

var _t := 0.0
var _spin: Array[Node3D] = []
var _base_y := 0.0


static func make(color: Color, size: float = 1.0, seed_value: int = 0) -> Hologram:
	var h := Hologram.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	var i := 0
	for p: String in PARTS:
		var path := "res://assets/Synty/SciFiSpace/FBX/%s.fbx" % p
		if not ResourceLoader.exists(path):
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(inst)
		var s: float = size * [2.2, 2.6, 2.0, 1.4][i]
		inst.scale = Vector3.ONE * s
		holder.position.y = i * 0.12 * size
		holder.rotation.y = (seed_value % 7) * 0.4 + i * 0.9
		h.add_child(holder)
		if i % 2 == 1:
			h._spin.append(holder)
		i += 1
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 0.6
	glow.omni_range = 3.0 * size
	h.add_child(glow)
	h._t = float(seed_value % 10)
	return h


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	if FxEffect.reduced_motion():
		return
	_t += delta
	position.y = _base_y + sin(_t * 1.3) * 0.05
	for n: Node3D in _spin:
		n.rotation.y += delta * 0.6
