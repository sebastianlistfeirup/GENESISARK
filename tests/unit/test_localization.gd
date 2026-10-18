extends TestCase
## GA-33 (D-017, D-025): English source text is the key, Danish via
## localization/translations.csv, content text localized on load, saves stay
## language-neutral. Every test restores the source language.

const CSV := "res://localization/translations.csv"
const SPEC := "%[-+0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXc%]"


func test_source_language_is_identity() -> void:
	Loc.set_language(Loc.SOURCE)
	eq(Loc.lang(), "en", "source language")
	eq(Loc.t("Continue"), "Continue", "English key returned unchanged")
	eq(Loc.t(""), "", "empty text")


func test_unknown_language_falls_back_to_source() -> void:
	Loc.set_language("xx")
	eq(Loc.lang(), "en", "unknown language -> English")
	Loc.set_language(Loc.SOURCE)


func test_danish_translation_loaded() -> void:
	Loc.set_language("da")
	eq(Loc.t("Continue"), "Fortsæt", "Continue -> Fortsæt")
	eq(Loc.t(str(ColonySimulation.RES_LABELS["water"])), "vand", "resource label")
	eq(Loc.group(50000), "50.000", "Danish thousands separator")
	Loc.set_language(Loc.SOURCE)
	eq(Loc.group(-1234567), "-1,234,567", "English thousands separator")


func test_every_key_translated_with_same_placeholders() -> void:
	var f := FileAccess.open(CSV, FileAccess.READ)
	check(f != null, "translations.csv exists")
	if f == null:
		return
	var re := RegEx.create_from_string(SPEC)
	var brace := RegEx.create_from_string("\\{[a-z_]+\\}")
	var header := f.get_csv_line()
	eq(header[0], "keys", "first column is keys")
	eq(header[1], "da", "second column is Danish")
	var rows := 0
	var bad: Array = []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0].is_empty():
			continue
		rows += 1
		if row[1].strip_edges().is_empty():
			bad.append("missing: " + row[0].left(50))
			continue
		for rx: RegEx in [re, brace]:
			if _tokens(rx, row[0]) != _tokens(rx, row[1]):
				bad.append("placeholders: " + row[0].left(50))
	check(rows > 900, "at least 900 keys (got %d)" % rows)
	check(bad.is_empty(), "every key translated with the same placeholders: %s" % str(bad.slice(0, 5)))


func test_content_localized_and_save_language_neutral() -> void:
	Loc.set_language("da")
	var da := ContentDB.load_default()
	Loc.set_language(Loc.SOURCE)
	check(da.errors.is_empty(), "Danish content validates: %s" % str(da.errors))
	eq(da.planets.keys(), content.planets.keys(), "same planet ids")
	eq(da.buildings.keys(), content.buildings.keys(), "same building ids")
	eq(str(content.buildings["water_plant"].get("name")), "Water plant", "English source name")
	eq(str(da.buildings["water_plant"].get("name")), "Vandanlæg", "Danish name")
	eq(da.buildings["water_plant"].get("power_kw"), content.buildings["water_plant"].get("power_kw"), "numbers unchanged")
	var en_state := GameState.create_new(content, 7, "loc_test")
	var da_state := GameState.create_new(da, 7, "loc_test")
	eq(SaveCodec.checksum(en_state.to_dict()), SaveCodec.checksum(da_state.to_dict()), "save is language-neutral")


func _tokens(rx: RegEx, s: String) -> Array:
	var out: Array = []
	for m: RegExMatch in rx.search_all(s):
		out.append(m.get_string())
	return out
