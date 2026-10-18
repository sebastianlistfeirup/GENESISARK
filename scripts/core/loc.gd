class_name Loc
extends RefCounted
## Localization helper (GA-33, D-017, D-025). The game is written in English:
## English source text is the translation key; localization/translations.csv
## holds the other languages (Danish) and tools/loc_extract.py keeps it in sync
## with code and data. Static so domain
## code can use it: TranslationServer is an engine singleton, not an autoload.

const SOURCE := "en"
const LANGUAGES := {"en": "English", "da": "Dansk"}


static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


static func lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func is_source() -> bool:
	return lang() == SOURCE


## Grouped integer in the active language's style: 50,000 (en), 50.000 (da).
static func group(n: int) -> String:
	var sep := "." if lang() == "da" else ","
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Switches the active language. Unknown codes fall back to the source language.
static func set_language(code: String) -> void:
	TranslationServer.set_locale(code if LANGUAGES.has(code) else SOURCE)
