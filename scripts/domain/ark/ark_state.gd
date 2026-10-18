class_name ArkState
extends RefCounted
## The ark's resources and the embryo ledger. Owner: ArkService.
## Invariant: viable + incubating + born + lost == 50000 (bible p.14).

const EMBRYO_TOTAL := 50000

var fuel: float = 100.0
var integrity: float = 100.0
var components: int = 40
## Ship systems: power ("offline" | "emergency" | "restored"), plus discovered terminals.
var systems: Dictionary = {"power": "offline", "starmap": false, "embryo_bank_checked": false, "workshop_checked": false}
var embryo_viable: int = EMBRYO_TOTAL
var embryo_incubating: int = 0
var embryo_born: int = 0
var embryo_lost: int = 0


func embryo_sum() -> int:
	return embryo_viable + embryo_incubating + embryo_born + embryo_lost


func ledger() -> Dictionary:
	return {"viable": embryo_viable, "incubating": embryo_incubating, "born": embryo_born, "lost": embryo_lost}


func to_dict() -> Dictionary:
	return {
		"fuel": fuel, "integrity": integrity, "components": components, "systems": systems.duplicate(true),
		"embryo_ledger": ledger(),
	}


static func from_dict(d: Dictionary) -> ArkState:
	var s := ArkState.new()
	s.fuel = DictUtil.get_float(d, "fuel", 100.0)
	s.integrity = DictUtil.get_float(d, "integrity", 100.0)
	s.components = DictUtil.get_int(d, "components", 40)
	var sys: Dictionary = DictUtil.get_dict(d, "systems")
	for k: String in sys.keys():
		s.systems[k] = sys[k]
	var l: Dictionary = DictUtil.get_dict(d, "embryo_ledger")
	s.embryo_viable = DictUtil.get_int(l, "viable", EMBRYO_TOTAL)
	s.embryo_incubating = DictUtil.get_int(l, "incubating")
	s.embryo_born = DictUtil.get_int(l, "born")
	s.embryo_lost = DictUtil.get_int(l, "lost")
	return s


## Returns reasons the state breaks domain invariants (empty = valid).
func invariant_errors() -> PackedStringArray:
	var out: PackedStringArray = []
	if fuel < 0.0: out.append(Loc.t("fuel < 0"))
	if integrity < 0.0 or integrity > 100.0: out.append(Loc.t("integrity uden for [0,100]"))
	if components < 0: out.append(Loc.t("components < 0"))
	for k: String in ["viable", "incubating", "born", "lost"]:
		if int(ledger()[k]) < 0:
			out.append(Loc.t("embryo %s < 0") % k)
	if embryo_sum() != EMBRYO_TOTAL:
		out.append(Loc.t("embryosum %d != %d") % [embryo_sum(), EMBRYO_TOTAL])
	return out
