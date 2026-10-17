class_name ColonySimulation
extends RefCounted
## Colony rules: placement, network, power allocation, production, maintenance.
## All quantities are explicit and data-driven (bible p.10). One call to
## DaySimulator.tick_day runs one strategic colony day; never per render frame.

const REASONS := {
	"no_access": "Ingen adgang: bygningen er ikke forbundet til robotdepotet.",
	"no_power": "Ingen strøm: afbrudt efter prioritet.",
	"no_workforce": "Mangler robotarbejdskraft.",
	"maintenance": "Mangler vedligeholdelse: ingen komponenter til service.",
	"input_missing": "Mangler råvarer til produktionen.",
	"module_missing": "Mangler modul, som planeten kræver.",
	"constructing": "Under opførelse.",
}
const PRIORITY_LABELS := {"life_support": "Livsstøtte", "care": "Omsorg", "water": "Vand/mad", "production": "Produktion"}

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


# ----------------------------------------------------------------- geometry

static func footprint_size(def: Dictionary, rot: int) -> Vector2:
	var fp: Array = DictUtil.get_arr(def, "footprint")
	var w := float(fp[0]) if fp.size() > 0 else 4.0
	var d := float(fp[1]) if fp.size() > 1 else 4.0
	return Vector2(d, w) if posmod(rot, 2) == 1 else Vector2(w, d)


static func rect_for(def: Dictionary, x: float, z: float, rot: int) -> Rect2:
	var s := footprint_size(def, rot)
	return Rect2(Vector2(x, z) - s * 0.5, s)


static func _rect_circle_overlap(r: Rect2, c: Vector2, radius: float) -> bool:
	var closest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return closest.distance_to(c) < radius


func district_scale(gs: GameState) -> float:
	return clampf(1.0 + gs.campaign.colony_year() / 25.0, 1.0, 2.2)


func modifiers(gs: GameState) -> Dictionary:
	return DictUtil.get_dict(content.planet(gs.colony.planet_id), "colony_modifiers")


func build_cost(gs: GameState, def_id: String) -> Dictionary:
	var def := content.building(def_id)
	var mult := DictUtil.get_float(modifiers(gs), "build_cost", 1.0)
	var out := {}
	var cost: Dictionary = DictUtil.get_dict(def, "cost")
	for k: String in cost.keys():
		out[k] = int(ceil(float(cost[k]) * (mult if k == "alloy" else 1.0)))
	return out


func link_range(def_id: String) -> float:
	var base := float(content.bal("network.link_range_m", 24.0))
	return base * 1.5 if def_id == "drone_hub" or def_id == "ark_core" else base


# ----------------------------------------------------------------- placement

## Validates a placement without changing anything. Returns {ok, reasons[], cost}.
func check_placement(gs: GameState, def_id: String, x: float, z: float, rot: int, ignore_cost: bool = false) -> Dictionary:
	var out := {"ok": false, "reasons": [], "cost": {}}
	var reasons: Array = out["reasons"]
	if gs.colony == null or gs.campaign.phase != CampaignState.PHASE_SETTLED:
		reasons.append("Der er ingen koloni endnu.")
		return out
	var def := content.building(def_id)
	if def.is_empty() or not def.get("buildable", true):
		reasons.append("Ukendt eller ikke-byggelig bygning.")
		return out
	var rect := rect_for(def, x, z, rot)
	var site := content.site(gs.colony.site_id)
	var districts: Dictionary = DictUtil.get_dict(site, "districts")
	var scale := district_scale(gs)
	var wanted := str(def.get("district", "any"))
	var inside := false
	for dk: String in districts.keys():
		if wanted != "any" and dk != wanted:
			continue
		var dc: Array = DictUtil.get_arr(districts[dk], "center")
		var rad := DictUtil.get_float(districts[dk], "radius") * scale
		if Vector2(x, z).distance_to(Vector2(float(dc[0]), float(dc[1]))) <= rad:
			inside = true
	if not inside:
		reasons.append("Skal placeres i %s." % ("boligzonen" if wanted == "living" else "ressourceområdet" if wanted == "resource" else "et af koloniens distrikter"))
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var bc: Array = DictUtil.get_arr(bz, "center")
		if _rect_circle_overlap(rect, Vector2(float(bc[0]), float(bc[1])), DictUtil.get_float(bz, "radius")):
			reasons.append("Terrænet her er ufremkommeligt.")
			break
	for b: Dictionary in gs.colony.buildings:
		var other := rect_for(content.building(str(b.get("def_id"))), float(b.get("x")), float(b.get("z")), int(b.get("rot", 0)))
		if rect.grow(0.5).intersects(other):
			reasons.append("Overlapper %s." % content.building(str(b.get("def_id"))).get("name"))
			break
	# Network: must be within link range of a connected node.
	var linked := false
	for b: Dictionary in gs.colony.buildings:
		if not bool(b.get("accessible", false)):
			continue
		var r := maxf(link_range(str(b.get("def_id"))), link_range(def_id))
		if Vector2(x, z).distance_to(Vector2(float(b.get("x")), float(b.get("z")))) <= r:
			linked = true
			break
	if not linked:
		reasons.append("Ingen forbindelse: placér inden for %.0f m af forsyningsnettet." % float(content.bal("network.link_range_m", 24.0)))
	var cost := build_cost(gs, def_id)
	out["cost"] = cost
	if not ignore_cost:
		for k: String in cost.keys():
			if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
				reasons.append("Mangler %s (%d / %d)." % [_res_label(k), int(gs.colony.inventory.get(k, 0.0)), int(cost[k])])
	out["ok"] = reasons.is_empty()
	return out


func place_building(gs: GameState, def_id: String, x: float, z: float, rot: int, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Byggeordren er allerede afgivet.")
	var chk := check_placement(gs, def_id, x, z, rot)
	if not chk["ok"]:
		return CommandResult.fail("placement_invalid", " ".join(chk["reasons"]), chk)
	var cost: Dictionary = chk["cost"]
	for k: String in cost.keys():  # Reserve resources at the order: never spent twice.
		gs.colony.inventory[k] = float(gs.colony.inventory[k]) - float(cost[k])
	var b := {
		"id": gs.colony.next_building_id, "def_id": def_id, "x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "rot": posmod(rot, 4),
		"state": ColonyState.B_CONSTRUCTING, "progress": 0.0, "modules": [], "wear": 0.0,
		"powered": false, "accessible": true, "efficiency": 1.0, "blocked_reason": "constructing",
		"invested": cost.duplicate(), "txn": txn,
	}
	gs.colony.next_building_id += 1
	gs.colony.buildings.append(b)
	gs.mark_applied(txn)
	recompute_network(gs)
	gs.colony.invalidate()
	return CommandResult.success({"building_id": b["id"], "cost": cost})


## Demolish/cancel. Refund never exceeds what was invested (bible p.10).
func demolish(gs: GameState, building_id: int) -> CommandResult:
	var b := gs.colony.building_by_id(building_id) if gs.colony else {}
	if b.is_empty():
		return CommandResult.fail("unknown_building", "Bygningen findes ikke.")
	if b.get("def_id") == "ark_core":
		return CommandResult.fail("protected", "Arkens kerne kan ikke rives ned.")
	var invested: Dictionary = DictUtil.get_dict(b, "invested")
	var frac := float(content.bal("demolish_refund", 0.5))
	if b.get("state") == ColonyState.B_CONSTRUCTING and float(b.get("progress", 0.0)) <= 0.0:
		frac = 1.0  # Cancelled before any work: full refund of the reservation
	var refund := {}
	for k: String in invested.keys():
		var amount := floorf(float(invested[k]) * frac)
		refund[k] = amount
		gs.colony.inventory[k] = float(gs.colony.inventory.get(k, 0.0)) + amount
	gs.colony.buildings.erase(b)
	recompute_network(gs)
	gs.colony.invalidate()
	return CommandResult.success({"refund": refund})


func add_module(gs: GameState, building_id: int, module_id: String) -> CommandResult:
	var b := gs.colony.building_by_id(building_id) if gs.colony else {}
	if b.is_empty():
		return CommandResult.fail("unknown_building", "Bygningen findes ikke.")
	var mods: Dictionary = DictUtil.get_dict(content.building(str(b.get("def_id"))), "modules")
	if not mods.has(module_id):
		return CommandResult.fail("unknown_module", "Bygningen kan ikke have dette modul.")
	if module_id in b.get("modules", []):
		return CommandResult.fail("already_installed", "Modulet er allerede installeret.")
	var cost: Dictionary = DictUtil.get_dict(mods[module_id], "cost")
	for k: String in cost.keys():
		if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
			return CommandResult.fail("insufficient", "Mangler %s til modulet." % _res_label(k))
	for k: String in cost.keys():
		gs.colony.inventory[k] = float(gs.colony.inventory[k]) - float(cost[k])
		var inv: Dictionary = b.get("invested", {})
		inv[k] = float(inv.get(k, 0.0)) + float(cost[k])
		b["invested"] = inv
	(b["modules"] as Array).append(module_id)
	gs.colony.invalidate()
	return CommandResult.success({"module": module_id})


static func _res_label(k: String) -> String:
	return {"alloy": "byggemateriale", "components": "komponenter", "water": "vand", "food": "mad"}.get(k, k)


# ----------------------------------------------------------------- network

func recompute_network(gs: GameState) -> void:
	gs.colony.network_dirty = false
	gs.colony.invalidate()
	var bs: Array = gs.colony.buildings
	for b: Dictionary in bs:
		b["accessible"] = b.get("def_id") == "ark_core"
	var frontier: Array = []
	for b: Dictionary in bs:
		if b["accessible"]:
			frontier.append(b)
	while not frontier.is_empty():
		var cur: Dictionary = frontier.pop_back()
		# Only active buildings relay the network; construction sites can still be reached.
		if cur.get("state") != ColonyState.B_ACTIVE:
			continue
		for o: Dictionary in bs:
			if o["accessible"]:
				continue
			var r := maxf(link_range(str(cur.get("def_id"))), link_range(str(o.get("def_id"))))
			if Vector2(float(cur.x), float(cur.z)).distance_to(Vector2(float(o.x), float(o.z))) <= r:
				o["accessible"] = true
				frontier.append(o)


# ----------------------------------------------------------------- daily rules

func ark_power_kw(gs: GameState) -> float:
	if gs.colony.ark_fuel <= 0.0:
		return 0.0
	var base := float(content.building("ark_core").get("power_kw", 8))
	return base * (1.0 if gs.ark.integrity >= 50.0 else 0.6)


## Seasonal hazard factors as deterministic functions of the colony day.
func hazard_factors(gs: GameState, day: int) -> Dictionary:
	var f := {"solar": 1.0, "wear": 1.0, "storm": false, "night": false}
	var p := content.planet(gs.colony.planet_id)
	var site_facts: Dictionary = DictUtil.get_dict(content.site(gs.colony.site_id), "facts")
	for hid: Variant in DictUtil.get_arr(p, "hazard_ids"):
		var col: Dictionary = DictUtil.get_dict(content.hazards.get(str(hid), {}), "colony")
		match str(hid):
			"storms":
				if posmod(day, 30) >= 27:
					var shelter := DictUtil.get_float(site_facts, "shelter", 0.5)
					f["solar"] *= 1.0 - DictUtil.get_float(col, "solar_penalty", 0.6) * (1.0 - shelter * 0.5)
					f["wear"] *= DictUtil.get_float(col, "wear_multiplier", 1.5)
					f["storm"] = true
			"dust":
				f["wear"] *= DictUtil.get_float(col, "wear_multiplier", 2.0) * (0.6 + DictUtil.get_float(site_facts, "exposure", 0.5) * 0.6)
			"long_night":
				var cycle := DictUtil.get_int(col, "cycle_days", 120)
				if posmod(day, cycle) >= cycle - DictUtil.get_int(col, "night_days", 40):
					f["solar"] = 0.0
					f["night"] = true
	f["wear"] *= DictUtil.get_float(DictUtil.get_dict(p, "colony_modifiers"), "wear_multiplier", 1.0)
	return f


func building_power_kw(gs: GameState, b: Dictionary, hz: Dictionary) -> float:
	return _power_kw(gs, b, hz, _power_ctx(gs))


## Per-tick constants for power maths (hot path: called for every building).
func _power_ctx(gs: GameState) -> Dictionary:
	var mods := modifiers(gs)
	return {
		"solar": DictUtil.get_float(mods, "solar", 1.0), "geo": DictUtil.get_float(mods, "geothermal", 0.2),
		"heat": DictUtil.get_float(mods, "heating_kw_per_habitat"), "water_extra": DictUtil.get_float(mods, "water_power_extra_kw"),
		"vent": bool(DictUtil.get_dict(content.site(gs.colony.site_id), "facts").get("vent", false)), "ark": ark_power_kw(gs),
	}


func _power_kw(_gs: GameState, b: Dictionary, hz: Dictionary, ctx: Dictionary) -> float:
	var def_id: String = b["def_id"]
	if def_id == "ark_core":
		return ctx["ark"]
	var def: Dictionary = content.buildings[def_id]
	var kw := float(def.get("power_kw", 0))
	var src: String = def.get("power_source", "")
	if src == "solar":
		return kw * float(ctx["solar"]) * float(hz["solar"]) * float(b.get("efficiency", 1.0))
	if src == "geothermal":
		return kw * float(ctx["geo"]) * (1.0 + (float(def.get("vent_bonus", 0.0)) if ctx["vent"] else 0.0)) * float(b.get("efficiency", 1.0))
	if kw >= 0.0:
		return kw
	var demand := kw
	if def_id == "habitat":
		demand -= float(ctx["heat"])
	elif def_id == "water_plant":
		demand -= float(ctx["water_extra"])
	var mods: Array = b.get("modules", [])
	if not mods.is_empty():
		var module_defs: Dictionary = def.get("modules", {})
		for m: Variant in mods:
			demand += float(module_defs.get(str(m), {}).get("power_kw", 0.0))
	return demand


## One pass over all buildings per state change: counts and capacities.
## "powered_*" capacities only count accessible, powered, safe buildings.
func census(gs: GameState) -> Dictionary:
	var c := gs.colony
	if not c.census.is_empty():
		return c.census
	var active := {}
	var battery := 0.0
	var drone_n := 0.0
	var pcap := {"residents": 0.0, "incubation_slots": 0.0, "care_capacity": 0.0, "education_capacity": 0.0, "health_per_day": 0.0}
	var req := requires_module(gs)
	for b: Dictionary in c.buildings:
		if b["state"] != ColonyState.B_ACTIVE:
			continue
		var def_id: String = b["def_id"]
		active[def_id] = int(active.get(def_id, 0)) + 1
		if not b["accessible"]:
			continue
		var prov := _provides(def_id)
		battery += prov["battery_kwh"]
		drone_n += prov["drones"]
		if not b["powered"]:
			continue
		if def_id == "habitat" and not req.is_empty() and not req in b["modules"]:
			continue
		for k: String in pcap.keys():
			pcap[k] += prov[k]
	var cap := {"battery_kwh": battery, "drones": drone_n}
	c.census = {"active": active, "cap": cap, "powered_cap": pcap}
	return c.census


var _prov_cache: Dictionary = {}


func _provides(def_id: String) -> Dictionary:
	if not _prov_cache.has(def_id):
		var prov: Dictionary = DictUtil.get_dict(content.building(def_id), "provides")
		var out := {}
		for k: String in ["battery_kwh", "drones", "residents", "incubation_slots", "care_capacity", "education_capacity", "health_per_day"]:
			out[k] = DictUtil.get_float(prov, k)
		_prov_cache[def_id] = out
	return _prov_cache[def_id]


func battery_capacity(gs: GameState) -> float:
	return float(census(gs)["cap"]["battery_kwh"])


func drones(gs: GameState) -> float:
	return float(census(gs)["cap"]["drones"]) * DictUtil.get_float(modifiers(gs), "drone_efficiency", 1.0)


## Power allocation by priority. Writes powered/blocked flags; returns the power report.
func allocate_power(gs: GameState, hz: Dictionary) -> Dictionary:
	var ctx := _power_ctx(gs)
	var prio_index := {}
	for i: int in content.building_priorities.size():
		prio_index[content.building_priorities[i]] = i
	var produced := 0.0
	var buckets: Array = [[], [], [], [], []]  # by priority; buildings are already in id order
	for b: Dictionary in gs.colony.buildings:
		if b["state"] != ColonyState.B_ACTIVE:
			continue
		if not b["accessible"]:
			b["powered"] = false
			continue
		var kw := _power_kw(gs, b, hz, ctx)
		if kw >= 0.0:
			produced += kw
			b["powered"] = true
		else:
			buckets[mini(int(prio_index.get(content.buildings[b["def_id"]].get("priority"), 4)), 4)].append([0, -kw, b])
	var consumers: Array = []
	for bucket: Array in buckets:
		consumers.append_array(bucket)
	var demand := 0.0
	for c: Array in consumers:
		demand += float(c[1])
	var cap := battery_capacity(gs)
	gs.colony.battery_kwh = minf(gs.colony.battery_kwh, cap)
	var available := produced + gs.colony.battery_kwh / 24.0
	var used := 0.0
	var shed: Array = []
	for c: Array in consumers:
		var b: Dictionary = c[2]
		if used + float(c[1]) <= available + 0.0001:
			used += float(c[1])
			b["powered"] = true
		else:
			b["powered"] = false
			shed.append(int(b["id"]))
	var net := produced - used
	gs.colony.battery_kwh = clampf(gs.colony.battery_kwh + net * 24.0, 0.0, cap)
	gs.colony.invalidate()  # Powered flags changed
	return {"produced_kw": snappedf(produced, 0.01), "demand_kw": snappedf(demand, 0.01), "used_kw": snappedf(used, 0.01),
		"surplus_kw": snappedf(produced - demand, 0.01), "battery_kwh": snappedf(gs.colony.battery_kwh, 0.01),
		"battery_capacity": cap, "shed": shed, "ark_kw": float(ctx["ark"]), "night": hz["night"], "storm": hz["storm"]}


func building_priorities_index(p: String) -> int:
	var idx := content.building_priorities.find(p)
	return idx if idx >= 0 else 99


func requires_module(gs: GameState) -> String:
	return DictUtil.get_str(modifiers(gs), "requires_module")


func habitat_ok(gs: GameState, b: Dictionary) -> bool:
	var req := requires_module(gs)
	return req.is_empty() or req in b.get("modules", [])
