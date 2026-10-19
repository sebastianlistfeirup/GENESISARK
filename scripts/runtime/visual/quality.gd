class_name Quality
extends RefCounted
## Graphics profile (bible p.26: a lower profile may reduce shadows and VFX, never
## readability). Setting "graphics_quality": "auto" | "high" | "low". Auto picks
## low on web, mobile and the Compatibility renderer. The numbers live in
## data/perf/budget.json "quality_low"; high uses each system's own defaults.

static var _low_values: Dictionary = {}


static func setting() -> String:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var s := (ml as SceneTree).root.get_node_or_null(^"SettingsService")
		if is_instance_valid(s) and s.has_method("get_value"):
			return str(s.call("get_value", "graphics_quality", "auto"))
	return "auto"


static func low() -> bool:
	match setting():
		"low":
			return true
		"high":
			return false
	return OS.has_feature("web") or OS.has_feature("mobile") or RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func name() -> String:
	return "low" if low() else "high"


## A low-profile value, or `fallback` on the high profile.
static func value(key: String, fallback: float) -> float:
	if not low():
		return fallback
	if _low_values.is_empty():
		var b: Variant = DictUtil.load_json("res://data/perf/budget.json")
		_low_values = DictUtil.get_dict(b, "quality_low") if b is Dictionary else {}
	return DictUtil.get_float(_low_values, key, fallback)
