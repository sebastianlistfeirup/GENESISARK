class_name DetRng
extends RefCounted
## Named, serialisable RNG streams (bible p.22: campaign choices and content
## extraction use separate streams with saved seed/state).
## 64-bit state is stored as a string so JSON never loses precision.

var _streams: Dictionary = {}  # name -> RandomNumberGenerator
var base_seed: int = 0


func _init(seed_value: int = 0) -> void:
	base_seed = seed_value


func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(base_seed) + ":" + stream_name)
		_streams[stream_name] = rng
	return _streams[stream_name]


func randf_in(stream_name: String, lo: float, hi: float) -> float:
	return stream(stream_name).randf_range(lo, hi)


func randi_in(stream_name: String, lo: int, hi: int) -> int:
	return stream(stream_name).randi_range(lo, hi)


func to_dict() -> Dictionary:
	var states := {}
	for k: String in _streams.keys():
		var rng: RandomNumberGenerator = _streams[k]
		states[k] = {"seed": str(rng.seed), "state": str(rng.state)}
	return {"base_seed": str(base_seed), "streams": states}


static func from_dict(d: Dictionary) -> DetRng:
	var r := DetRng.new(int(str(d.get("base_seed", "0"))))
	var states: Dictionary = d.get("streams", {})
	for k: String in states.keys():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(str(states[k].get("seed", "0")))
		rng.state = int(str(states[k].get("state", "0")))
		r._streams[k] = rng
	return r
