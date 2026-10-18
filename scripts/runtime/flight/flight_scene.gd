extends Node3D
## Short, bounded orbital approach (bible p.6): throttle, turn, autopilot.
## The journey is already committed in the domain; this is pilot feel, not a
## second chance to spend fuel. Autopilot can fly it entirely (assisted).

const RING_COUNT := 8

var ship: Node3D
var cam: Camera3D
var rings: Array[Node3D] = []
var next_ring := 0
var speed := 0.0
var autopilot := false
var hud: GameHud
var _info: Label
var _done := false
var _shake := 0.0
var _dest := ""
var _asteroids: Array[Node3D] = []
var _thruster: AudioStreamPlayer


func _ready() -> void:
	_dest = str(AppFlow.params.get("destination", GameSession.state.campaign.location_id if GameSession.has_game() else "viridia"))
	add_child(SpaceBackdrop.new())
	var pid := str(GameSession.content.locations.get(_dest, {}).get("planet_id", "viridia"))
	var p := GameSession.content.planet(pid)
	var planet := VisualSlot.make("space.planet_" + str(p.get("biome_id", "green")), str(p.get("palette", {}).get("nature", "")))
	planet.scale = Vector3.ONE * 3.0
	planet.position = Vector3(0, -120, -900)
	add_child(planet)
	ship = Node3D.new()
	ship.add_child(VisualSlot.make("space.ark_exterior"))
	add_child(ship)
	var thr := VisualSlot.make("fx.thruster")
	thr.position = Vector3(0, -1.5, 15)
	ship.add_child(thr)
	cam = Camera3D.new()
	cam.far = 5000
	cam.fov = 70
	add_child(cam)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_dest)
	for i: int in RING_COUNT:
		var ring := VisualSlot.make("space.approach_ring")
		ring.scale = Vector3.ONE * 2.2
		ring.position = Vector3(sin(i * 0.9) * 40.0, cos(i * 0.6) * 18.0 - i * 6.0, -80.0 - i * 90.0)
		add_child(ring)
		rings.append(ring)
	for i: int in 26:
		var a := VisualSlot.make("space.asteroid")
		a.position = Vector3(rng.randf_range(-120, 120), rng.randf_range(-60, 40), rng.randf_range(-100, -760))
		a.scale = Vector3.ONE * rng.randf_range(1.0, 4.0)
		add_child(a)
		_asteroids.append(a)
	hud = GameHud.new()
	add_child(hud)
	_info = UiKit.label("", 18)
	var panel := UiKit.panel()
	panel.add_child(_info)
	hud.top_right.add_child(panel)
	hud.set_prompt(Loc.t("W/S gas · A/D drej · Mellemrum/Ctrl op/ned · [F] autopilot"))
	AudioService.set_ambience("amb_space")
	_thruster = AudioStreamPlayer.new()
	_thruster.stream = AudioService.stream("sfx_thruster")
	_thruster.bus = "SFX"
	_thruster.volume_db = -14
	add_child(_thruster)
	_thruster.play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if _done or hud.any_modal_open():
		return
	if Input.is_action_just_pressed("autopilot"):
		autopilot = not autopilot
		AudioService.ui("ui_confirm")
	var throttle := Input.get_axis("move_back", "move_forward")
	var turn := Input.get_axis("move_right", "move_left")
	var lift := (1.0 if Input.is_action_pressed("ascend") else 0.0) - (1.0 if Input.is_action_pressed("descend") else 0.0)
	if next_ring < rings.size():
		var target := rings[next_ring].global_position
		var to := (target - ship.global_position)
		if autopilot:
			var local := ship.global_transform.basis.inverse() * to.normalized()
			turn = clampf(-local.x * 3.0, -1, 1)
			lift = clampf(local.y * 3.0, -1, 1)
			throttle = 1.0
		if to.length() < 14.0:
			next_ring += 1
			AudioService.ui("ui_confirm")
	else:
		throttle = 1.0
		if not _done:
			_arrive()
	speed = clampf(speed + throttle * 30.0 * delta - 6.0 * delta, 8.0, 70.0)
	ship.rotation.y += turn * 0.9 * delta
	ship.rotation.z = lerpf(ship.rotation.z, turn * 0.35, delta * 3.0)
	ship.position += -ship.global_transform.basis.z * speed * delta + Vector3(0, lift * 18.0 * delta, 0)
	for a: Node3D in _asteroids:
		if a.global_position.distance_to(ship.global_position) < 8.0 * a.scale.x:
			var away := (ship.global_position - a.global_position).normalized()
			ship.position += away * 3.0
			speed *= 0.6
			if SettingsService.get_value("camera_shake", true) and not SettingsService.get_value("reduced_motion", false):
				_shake = 0.4
	var behind := ship.global_transform.basis.z * 34.0 + Vector3(0, 9, 0)
	cam.global_position = cam.global_position.lerp(ship.global_position + behind, clampf(delta * 4.0, 0, 1))
	if _shake > 0.0:
		_shake -= delta
		cam.global_position += Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0)
	cam.look_at(ship.global_position + -ship.global_transform.basis.z * 20.0)
	_thruster.pitch_scale = 0.7 + speed / 100.0
	_info.text = Loc.t("Indflyvning: %s\nKorridor %d / %d\nFart %d · %s") % [GameSession.content.locations.get(_dest, {}).get("name", _dest),
		mini(next_ring + 1, RING_COUNT), RING_COUNT, int(speed), Loc.t("AUTOPILOT") if autopilot else Loc.t("manuel")]


func _arrive() -> void:
	_done = true
	hud.set_prompt(Loc.t("Kredsløb etableret."))
	await get_tree().create_timer(1.2).timeout
	AppFlow.goto("ship", {"spawn": "orbit_terminal"})


func debug_action(action: String) -> void:
	if action == "autopilot":
		autopilot = true
		for i: int in 200:
			_physics_process(1.0 / 60.0)
