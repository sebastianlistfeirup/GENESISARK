extends TestCase
## GA-10: save envelope, safe write, backup, corruption, migration.

const DIR := "user://test_saves"


func _store() -> SaveStore:
	var s := SaveStore.new(DIR)
	s.delete_slot("t")
	return s


func _sample_state() -> GameState:
	var sim := new_sim(777)
	land_on(sim, "ferrum")
	place_near(sim, "solar_array")
	place_near(sim, "water_plant")
	run_days(sim, 12)
	sim.state.rng.stream("events").randf()
	return sim.state


func test_roundtrip_preserves_everything() -> void:
	var store := _store()
	var gs := _sample_state()
	var env := SaveCodec.encode(gs, content.content_version, "s1")
	ok_dict(store.write("t", env, content), "skriv")
	var res := store.read("t", content)
	check(res["ok"], "læs: %s" % res["error"])
	eq(DictUtil.canonical_json(res["state"].to_dict()), DictUtil.canonical_json(gs.to_dict()), "identisk")
	eq(res["state"].rng.stream("events").randf(), gs.rng.stream("events").randf(), "RNG-tilstand bevaret")


func ok_dict(d: Dictionary, msg: String) -> void:
	check(bool(d.get("ok", false)), "%s: %s" % [msg, d.get("error", "")])


func test_corrupt_main_offers_backup() -> void:
	var store := _store()
	var gs := _sample_state()
	store.write("t", SaveCodec.encode(gs, "x", "a"), content)
	store.write("t", SaveCodec.encode(gs, "x", "b"), content)
	var f := FileAccess.open(store.main_path("t"), FileAccess.WRITE)
	f.store_string("{\"game_id\": \"genesis_ark\", \"payload\": {\"campaign\": {}}, \"checksum\": \"bad\"}")
	f.close()
	var res := store.read("t", content)
	check(not res["ok"], "korrupt afvises")
	check(res["backup_available"], "backup tilbydes")
	var bak := store.read("t", content, true)
	check(bak["ok"], "backup kan indlæses")


func test_interrupted_write_offers_backup() -> void:
	var store := _store()
	var gs := _sample_state()
	store.write("t", SaveCodec.encode(gs, "x", "a"), content)
	store.write("t", SaveCodec.encode(gs, "x", "b"), content)
	# Simulate a crash between "backup made" and "tmp renamed": main gone, tmp half-written.
	DirAccess.remove_absolute(store.main_path("t"))
	var f := FileAccess.open(store.main_path("t") + ".tmp", FileAccess.WRITE)
	f.store_string("{\"game_id\": \"gen")
	f.close()
	var res := store.read("t", content)
	check(not res["ok"] and str(res["error"]).contains("interrupted"), "interrupted write recognized: " + str(res["error"]))
	check(res["backup_available"], "backup tilbydes")


func test_unknown_content_id_rejected() -> void:
	var gs := _sample_state()
	var env := SaveCodec.encode(gs, "x", "a")
	env["payload"]["campaign"]["selected_planet_id"] = "atlantis"
	env["checksum"] = SaveCodec.checksum(env["payload"])
	var dec := SaveCodec.decode(env, content)
	check(not dec["ok"] and str(dec["error"]).contains("atlantis"), "ukendt content-id: " + str(dec["error"]))


func test_tampered_payload_rejected() -> void:
	var gs := _sample_state()
	var env := SaveCodec.encode(gs, "x", "a")
	env["payload"]["ark"]["fuel"] = 999
	check(not SaveCodec.decode(env, content)["ok"], "checksum fanger ændring")


func test_v1_fixture_migrates_on_copy() -> void:
	var v: Variant = DictUtil.load_json("res://fixtures/saves/v1_voyage.json")
	if not check(v is Dictionary, "fixture findes"):
		return
	var original := JSON.stringify(v)
	var dec := SaveCodec.decode(v, content)
	check(dec["ok"], "migrering: %s" % dec["error"])
	eq(dec["migrated_from"], 1, "fra v1")
	eq(JSON.stringify(v), original, "originalen er urørt")
	if dec["ok"]:
		eq((dec["state"] as GameState).ark.embryo_sum(), 50000, "ledger bevaret")


func test_restore_does_not_refire_events() -> void:
	var sim := new_sim(5)
	land_on(sim, "viridia")
	var env := SaveCodec.encode(sim.state, "x", "a")
	var gs: GameState = SaveCodec.decode(env, content)["state"]
	var sim2 := Simulation.new(content, gs)
	fails(sim2.landing.commit_landing(gs, "green_b", "land:viridia"), "already_landed", "landing affyres ikke igen")
