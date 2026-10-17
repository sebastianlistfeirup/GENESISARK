class_name ColonyState
extends RefCounted
## The settled colony. Buildings are plain dictionaries with stable ids:
## {id, def_id, x, z, rot, state, progress, modules[], wear, powered, accessible, efficiency, blocked_reason}
## Owner: ColonySimulation.

const B_PLANNED := "planned"
const B_CONSTRUCTING := "constructing"
const B_ACTIVE := "active"

var planet_id: String = ""
var biome_id: String = ""
var site_id: String = ""
var buildings: Array = []
var next_building_id: int = 1
var inventory: Dictionary = {"alloy": 0.0, "components": 0.0, "water": 0.0, "food": 0.0}
var battery_kwh: float = 0.0
var ark_fuel: float = 0.0
var salvage_left: float = 0.0
var speed: int = 0                    # 0 pause, 1, 3
var last_report: Dictionary = {}      # Derived per tick, also saved for UI continuity
var stats: Dictionary = {"days_stable": 0, "deficit_days": 0, "crises_resolved": 0}
## Derived cache flag (not saved): the network is recomputed only after changes.
var network_dirty := true
## Derived per-tick census (not saved): counts and capacities of active buildings.
var census: Dictionary = {}


func building_by_id(bid: int) -> Dictionary:
	for b: Dictionary in buildings:
		if int(b.get("id")) == bid:
			return b
	return {}


func count_active(def_id: String) -> int:
	if not census.is_empty():
		return int(census["active"].get(def_id, 0))
	var n := 0
	for b: Dictionary in buildings:
		if b.get("def_id") == def_id and b.get("state") == B_ACTIVE:
			n += 1
	return n


func invalidate() -> void:
	census = {}


func to_dict() -> Dictionary:
	return {
		"planet_id": planet_id, "biome_id": biome_id, "site_id": site_id,
		"buildings": buildings.duplicate(true), "next_building_id": next_building_id,
		"inventory": inventory.duplicate(), "battery_kwh": battery_kwh, "ark_fuel": ark_fuel,
		"salvage_left": salvage_left, "speed": speed, "last_report": last_report.duplicate(true),
		"stats": stats.duplicate(),
	}


static func from_dict(d: Dictionary) -> ColonyState:
	var s := ColonyState.new()
	s.planet_id = DictUtil.get_str(d, "planet_id")
	s.biome_id = DictUtil.get_str(d, "biome_id")
	s.site_id = DictUtil.get_str(d, "site_id")
	s.buildings = DictUtil.get_arr(d, "buildings").duplicate(true)
	for b: Dictionary in s.buildings:
		b["id"] = int(b.get("id", 0))
	s.next_building_id = DictUtil.get_int(d, "next_building_id", 1)
	var inv: Dictionary = DictUtil.get_dict(d, "inventory")
	for k: String in s.inventory.keys():
		s.inventory[k] = DictUtil.get_float(inv, k)
	s.battery_kwh = DictUtil.get_float(d, "battery_kwh")
	s.ark_fuel = DictUtil.get_float(d, "ark_fuel")
	s.salvage_left = DictUtil.get_float(d, "salvage_left")
	s.speed = DictUtil.get_int(d, "speed")
	s.last_report = DictUtil.get_dict(d, "last_report").duplicate(true)
	var st: Dictionary = DictUtil.get_dict(d, "stats")
	for k: String in st.keys():
		s.stats[k] = int(st[k])
	return s


func invariant_errors() -> PackedStringArray:
	var out: PackedStringArray = []
	for k: String in inventory.keys():
		if float(inventory[k]) < -0.0001:
			out.append("inventory.%s < 0" % k)
	if battery_kwh < -0.0001: out.append("battery < 0")
	var ids := {}
	for b: Dictionary in buildings:
		if ids.has(b.get("id")):
			out.append("dubleret bygnings-id %s" % b.get("id"))
		ids[b.get("id")] = true
	return out
