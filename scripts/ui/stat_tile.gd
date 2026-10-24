class_name StatTile
extends PanelContainer
## One fact about a world as a tile (D-055), replacing the old text table:
##   [badge] CAPTION                         [ESTIMATE · ARCHIVE]
##           0.90 – 1.30 g
##   [=========|######|======================]   (RangeBar on the stat's scale)
## known = teal accent and a marker, estimate = amber band, unknown = striped,
## locked tile ("probe or scan to learn"). The text value and the status word
## are always there, so nothing depends on colour or on the art.
## Scales and the "good" direction below are presentation only (no balance).
##   StatTile.for_property(pid, "gravity_multiplier")            - full tile
##   StatTile.for_property(pid, "gravity_multiplier", true)      - compact (no chip, smaller)

## prop -> icon slot, scale, comfortable zone, which way is better ("high" / "low" / "mid").
const STATS := {
	"gravity_multiplier": {"icon": "stat.gravity", "lo": 0.5, "hi": 1.5, "ideal": [0.85, 1.15], "better": "mid", "target": 1.0},
	"mean_temperature_c": {"icon": "stat.temperature_hot", "lo": -70.0, "hi": 60.0, "ideal": [5.0, 28.0], "better": "mid", "target": 18.0},
	"atmosphere_class": {"icon": "stat.atmosphere", "category": true},
	"water_access": {"icon": "stat.water", "lo": 0.0, "hi": 1.0, "ideal": [0.6, 1.0], "better": "high"},
	"mineral_yield": {"icon": "stat.minerals", "lo": 0.0, "hi": 2.0, "ideal": [1.0, 2.0], "better": "high"},
	"solar_factor": {"icon": "stat.solar", "lo": 0.0, "hi": 1.6, "ideal": [0.9, 1.6], "better": "high"},
	"geothermal_factor": {"icon": "stat.geothermal", "lo": 0.0, "hi": 1.2, "ideal": [0.6, 1.2], "better": "high"},
	"biological_risk": {"icon": "stat.biohazard", "lo": 0.0, "hi": 1.0, "ideal": [0.0, 0.2], "better": "low"},
}
## Atmosphere classes ranked for "best" in the comparison (breathable first).
const ATMO_RANK := {"breathable": 3.0, "breathable_humid": 2.8, "breathable_spores": 2.4, "thin_dry": 1.0, "thin_dusty": 0.9, "thin_cold": 0.9, "inert_thin": 0.2}

var prop := ""
var status := "unknown"
var bar: RangeBar
var _accent: Control


## Builds the tile for one property of one world from the survey state (read only).
static func for_property(pid: String, property: String, compact: bool = false) -> StatTile:
	var gs: GameState = GameSession.state
	var cmp := GameSession.sim.survey.comparison(gs, pid)
	var row: Dictionary = (cmp["rows"] as Dictionary).get(property, {"status": "unknown", "text": Loc.t("unknown"), "source": ""})
	var obs: Dictionary = gs.knowledge_of(pid).observations.get(property, {"status": "unknown"})
	var t := StatTile.new()
	t._build(property, row, obs, compact)
	return t


static func icon_for(property: String, obs: Dictionary) -> String:
	if property == "mean_temperature_c":
		var v := mid_value(obs)
		return "stat.temperature_cold" if not is_nan(v) and v < 5.0 else "stat.temperature_hot"
	return str(DictUtil.get_dict(STATS, property).get("icon", "ui.icon_info"))


## Known value, or the middle of an estimate, or NAN.
static func mid_value(obs: Dictionary) -> float:
	match str(obs.get("status", "")):
		"known":
			var v: Variant = obs.get("value")
			return float(v) if v is float or v is int else NAN
		"estimated":
			if obs.has("min"):
				return (float(obs.get("min")) + float(obs.get("max"))) * 0.5
	return NAN


## Higher = better for the comparison's "best" mark; NAN when unknown.
static func score(property: String, obs: Dictionary) -> float:
	var st := str(obs.get("status", "unknown"))
	if st == "unknown":
		return NAN
	if property == "atmosphere_class":
		if st == "known":
			return float(ATMO_RANK.get(str(obs.get("value")), 0.0))
		var s := 0.0
		var cands: Array = obs.get("candidates", [])
		for c: Variant in cands:
			s += float(ATMO_RANK.get(str(c), 0.0))
		return s / maxf(1.0, cands.size()) - 0.01  # an estimate never ties a known value
	var v := mid_value(obs)
	if is_nan(v):
		return NAN
	var d: Dictionary = STATS.get(property, {})
	match str(d.get("better", "high")):
		"low":
			return -v
		"mid":
			return -absf(v - float(d.get("target", 0.0))) / maxf(0.001, float(d.get("hi", 1.0)) - float(d.get("lo", 0.0)))
	return v


static func status_color(st: String) -> Color:
	return {"known": Color("5fe0c8"), "estimated": UiKit.AMBER}.get(st, UiKit.MUTED)


func _build(property: String, row: Dictionary, obs: Dictionary, compact: bool) -> void:
	prop = property
	status = str(row.get("status", "unknown"))
	var col := StatTile.status_color(status)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.82) if status != "unknown" else Color(0.03, 0.04, 0.05, 0.7)
	sb.border_color = Color(col, 0.35 if status != "unknown" else 0.2)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.border_color = Color(col, 0.55)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.content_margin_left = 10 if not compact else 8
	sb.content_margin_right = 10 if not compact else 8
	sb.content_margin_top = 7 if not compact else 5
	sb.content_margin_bottom = 8 if not compact else 6
	add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox(4 if not compact else 3)
	var top := UiKit.hbox(9)
	var badge := IconBadge.make(StatTile.icon_for(property, obs), 34 if not compact else 26, col if status != "unknown" else UiKit.MUTED, false, UiKit.status_icon(str({"known": "ok", "estimated": "warning"}.get(status, "locked"))))
	badge.locked = status == "unknown"
	top.add_child(badge)
	var tv := UiKit.vbox(-1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := UiKit.label(Loc.t(str(SurveyService.PROPERTY_LABELS.get(property, property))).to_upper(), 11 if not compact else 10, UiKit.MUTED.lightened(0.15))
	cap.add_theme_font_override("font", UiKit.display_variant(1))
	tv.add_child(cap)
	var val_text := str(row.get("text", ""))
	if property == "atmosphere_class" and status == "estimated":
		val_text = Loc.t("%d candidates") % (obs.get("candidates", []) as Array).size()
	var val := UiKit.label(val_text if status != "unknown" else Loc.t("Unknown"), 18 if not compact else 15, col.lightened(0.25) if status != "unknown" else UiKit.MUTED)
	val.add_theme_font_override("font", UiKit.display_font())
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	val.tooltip_text = val_text
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	tv.add_child(val)
	top.add_child(tv)
	if not compact:
		var word := str({"known": Loc.t("known"), "estimated": Loc.t("estimate"), "unknown": Loc.t("unknown")}.get(status, status))
		var src := str(row.get("source", ""))
		var ch := Holo.chip(word, col, str({"known": "ui.icon_ok", "estimated": "ui.icon_warning"}.get(status, "ui.icon_locked")), 10)
		ch.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		ch.tooltip_text = src
		top.add_child(ch)
	v.add_child(top)
	var d: Dictionary = STATS.get(property, {})
	if bool(d.get("category", false)):
		v.add_child(_category_row(obs, col, compact))
	else:
		bar = RangeBar.new()
		var a := 0.0
		var b := 0.0
		if status == "known":
			a = StatTile.mid_value(obs)
			b = a
		elif status == "estimated":
			a = float(obs.get("min", 0.0))
			b = float(obs.get("max", 0.0))
		bar.setup(float(d.get("lo", 0.0)), float(d.get("hi", 1.0)), status, a, b)
		var iz: Array = d.get("ideal", [])
		if iz.size() == 2:
			bar.ideal = Vector2(float(iz[0]), float(iz[1]))
		bar.custom_minimum_size = Vector2(0, 16 if not compact else 12)
		bar.live = not compact
		v.add_child(bar)
	if not compact:
		var src := str(row.get("source", ""))
		var foot := UiKit.label(src if status != "unknown" else Loc.t("Not yet measured. A probe or a scan can reveal it."), 11, Color(UiKit.MUTED, 0.85), true)
		v.add_child(foot)
	add_child(v)
	HoloAnim.hover_lift(self, 0.015, 0.1)


## Atmosphere: the candidate classes as chips (estimate) or the one known class.
func _category_row(obs: Dictionary, col: Color, compact: bool) -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 5)
	h.add_theme_constant_override("v_separation", 3)
	var vals: Array = []
	match status:
		"known": vals = [obs.get("value")]
		"estimated": vals = obs.get("candidates", [])
	if vals.is_empty():
		var rb := RangeBar.new().setup(0, 1, "unknown")
		rb.custom_minimum_size = Vector2(0, 16 if not compact else 12)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return rb
	for c: Variant in vals:
		var key := str(c)
		var good := float(ATMO_RANK.get(key, 0.0)) >= 2.0
		var cc := (UiKit.OK.lightened(0.2) if good else UiKit.WARN) if status == "known" else UiKit.AMBER
		var word := Loc.t(str(SurveyService.ATMOSPHERE_LABELS.get(key, key)))
		h.add_child(Holo.chip(word + ("" if status == "known" else " ?"), cc, "ui.icon_ok" if good and status == "known" else "", 10 if compact else 11))
	return h
