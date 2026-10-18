class_name FxLab
extends Node3D
## DEVELOPER TOOL: shows the fx.* particle library (art/fx/) on a neutral ground
## so effects can be judged one by one, in Forward+ and Compatibility:
##   godot --path . --rendering-method gl_compatibility -- --capture=evidence/shots/fx_lab.png --scene=fxlab --fx=spores --wait=120
## --fx=<name> frames one effect; without it all ten stand in a row.
## Dev-only text, not localized (like RigLab / DebugCapture).

const SLOTS := ["fx.spores", "fx.dust", "fx.snow", "fx.storm", "fx.steam_vent", "fx.thruster", "fx.construction_sparks",
	"fx.power_surge", "fx.scan_pulse", "fx.landing_dust"]
## Camera per effect: [distance, height, look-at height].
const VIEW := {"fx.spores": [17.0, 6.0, 1.5], "fx.dust": [17.0, 5.0, 1.0], "fx.snow": [18.0, 6.0, 3.0], "fx.storm": [18.0, 6.0, 3.0],
	"fx.steam_vent": [13.0, 4.0, 4.0], "fx.thruster": [16.0, 5.0, 0.0], "fx.construction_sparks": [8.0, 3.5, 1.8],
	"fx.power_surge": [7.0, 3.0, 1.2], "fx.scan_pulse": [14.0, 9.0, 0.0], "fx.landing_dust": [16.0, 7.0, 0.0]}


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#16252b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8fa6ad")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	ground.material_override = AssetSlots.material("#3b4a48")
	add_child(ground)
	var only := str(AppFlow.params.get("fx", ""))
	var id := "fx." + only if not only.is_empty() else ""
	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	if id in SLOTS:
		var fx := VisualSlot.make(id)
		if id == "fx.thruster":
			fx.position.y = 3.0
			fx.rotation_degrees.y = 90.0  # plume (+Z) runs across the screen
		add_child(fx)
		var v: Array = VIEW[id]
		cam.position = Vector3(0, float(v[1]) + fx.position.y, float(v[0]))
		cam.look_at(Vector3(0, float(v[2]) + fx.position.y, 0))
	else:
		for i: int in SLOTS.size():
			var fx := VisualSlot.make(SLOTS[i])
			fx.position = Vector3((i - 4.5) * 16.0, 0, 0)
			add_child(fx)
		cam.position = Vector3(0, 40, 110)
		cam.look_at(Vector3(0, 2, 0))
