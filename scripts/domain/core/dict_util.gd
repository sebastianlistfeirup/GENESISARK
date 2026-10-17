class_name DictUtil
extends RefCounted
## Helpers for deterministic serialisation and typed reads from JSON data.


## Canonical JSON: sorted keys, so equal states give equal strings and checksums.
static func canonical_json(value: Variant) -> String:
	return JSON.stringify(_sorted(value), "", false, true)


static func _sorted(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for k: Variant in keys:
			out[str(k)] = _sorted(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for v: Variant in value:
			arr.append(_sorted(v))
		return arr
	if value is float:
		# Normalise integral floats so 3 and 3.0 serialise identically after a JSON roundtrip.
		var f: float = value
		if is_equal_approx(f, roundf(f)) and absf(f) < 9.0e15:
			return int(roundf(f))
		return snappedf(f, 0.000001)
	return value


static func sha256(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func get_float(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	var v: Variant = d.get(key, fallback)
	if v is float or v is int:
		return float(v)
	return fallback


static func get_int(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v: Variant = d.get(key, fallback)
	if v is float or v is int:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return int(v)
	return fallback


static func get_str(d: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = d.get(key, fallback)
	return str(v) if v != null else fallback


static func get_dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	return v if v is Dictionary else {}


static func get_arr(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key, [])
	return v if v is Array else []


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
