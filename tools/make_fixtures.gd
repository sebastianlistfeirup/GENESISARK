extends SceneTree
## Regenerates committed save fixtures. Usage:
## godot --headless --path . --script res://tools/make_fixtures.gd

func _init() -> void:
	Loc.set_language(Loc.SOURCE)
	var content := ContentDB.load_default()
	DirAccess.make_dir_recursive_absolute("res://fixtures/saves")
	# v1 fixture: mid-voyage, after one probe and one journey.
	var sim := Simulation.new_campaign(content, 4242)
	sim.ark.restore_power(sim.state)
	sim.survey.launch_probe(sim.state, "ferrum", "", "fx-probe")
	sim.travel.request_travel(sim.state, "viridia", "fx-trip")
	_write("res://fixtures/saves/v1_voyage.json", SaveCodec.to_v1_fixture(sim.state))
	# Current-schema fixture: a fresh robot colony on Sere.
	var s2 := Simulation.new_campaign(content, 777)
	s2.ark.restore_power(s2.state)
	s2.travel.request_travel(s2.state, "sere", "fx-t")
	s2.landing.commit_landing(s2.state, "desert_b", "fx-land")
	_write("res://fixtures/saves/v2_colony_start.json", SaveCodec.encode(s2.state, content.content_version, "fixture_v2", "2026-10-17T00:00:00"))
	print("fixtures written")
	quit(0)


func _write(path: String, env: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(env, "\t"))
	f.close()
