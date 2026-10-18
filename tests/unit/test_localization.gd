extends TestCase
## GA-33 groundwork (D-017): Danish source text as key, English via
## localization/translations.csv, content text localized on load, saves stay
## language-neutral. Every test restores the source language.

const CSV := "res://localization/translations.csv"
const SPEC := "%[-+0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXc%]"


func test_source_language_is_identity() -> void:
	Loc.set_language(Loc.SOURCE)
	eq(Loc.lang(), "da", "kildesprog")
	eq(Loc.t("Fortsæt"), "Fortsæt", "dansk nøgle returneres uændret")
	eq(Loc.t(""), "", "tom tekst")


func test_unknown_language_falls_back_to_source() -> void:
	Loc.set_language("xx")
	eq(Loc.lang(), "da", "ukendt sprog -> dansk")
	Loc.set_language(Loc.SOURCE)


func test_english_translation_loaded() -> void:
	Loc.set_language("en")
	eq(Loc.t("Fortsæt"), "Continue", "Fortsæt -> Continue")
	eq(Loc.t(str(ColonySimulation.RES_LABELS["water"])), "water", "ressourcelabel")
	Loc.set_language(Loc.SOURCE)


func test_every_key_translated_with_same_placeholders() -> void:
	var f := FileAccess.open(CSV, FileAccess.READ)
	check(f != null, "translations.csv findes")
	if f == null:
		return
	var re := RegEx.create_from_string(SPEC)
	var brace := RegEx.create_from_string("\\{[a-z_]+\\}")
	var header := f.get_csv_line()
	eq(header[0], "keys", "første kolonne er keys")
	var rows := 0
	var bad: Array = []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0].is_empty():
			continue
		rows += 1
		if row[1].strip_edges().is_empty():
			bad.append("mangler: " + row[0].left(50))
			continue
		for rx: RegEx in [re, brace]:
			if _tokens(rx, row[0]) != _tokens(rx, row[1]):
				bad.append("pladsholdere: " + row[0].left(50))
	check(rows > 900, "mindst 900 nøgler (fik %d)" % rows)
	check(bad.is_empty(), "alle nøgler oversat med samme pladsholdere: %s" % str(bad.slice(0, 5)))


func test_content_localized_and_save_language_neutral() -> void:
	Loc.set_language("en")
	var en := ContentDB.load_default()
	Loc.set_language(Loc.SOURCE)
	check(en.errors.is_empty(), "engelsk indhold validerer: %s" % str(en.errors))
	eq(en.planets.keys(), content.planets.keys(), "samme planet-id'er")
	eq(en.buildings.keys(), content.buildings.keys(), "samme bygnings-id'er")
	check(str(en.buildings["water_plant"].get("name")) != str(content.buildings["water_plant"].get("name")), "bygningsnavn oversat")
	eq(en.buildings["water_plant"].get("power_kw"), content.buildings["water_plant"].get("power_kw"), "tal uændret")
	var da_state := GameState.create_new(content, 7, "loc_test")
	var en_state := GameState.create_new(en, 7, "loc_test")
	eq(SaveCodec.checksum(da_state.to_dict()), SaveCodec.checksum(en_state.to_dict()), "save er sproguafhængig")


func _tokens(rx: RegEx, s: String) -> Array:
	var out: Array = []
	for m: RegExMatch in rx.search_all(s):
		out.append(m.get_string())
	return out
