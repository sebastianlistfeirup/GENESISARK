class_name CommandResult
extends RefCounted
## Outcome of a domain command. UI and 3D adapters never mutate state directly;
## they issue commands and react to these results (bible p.14).

var ok: bool = false
var code: String = ""
var reason: String = ""
var data: Dictionary = {}


static func success(payload: Dictionary = {}, message: String = "") -> CommandResult:
	var r := CommandResult.new()
	r.ok = true
	r.code = "ok"
	r.reason = message
	r.data = payload
	return r


static func fail(error_code: String, message: String, payload: Dictionary = {}) -> CommandResult:
	var r := CommandResult.new()
	r.ok = false
	r.code = error_code
	r.reason = message
	r.data = payload
	return r


func _to_string() -> String:
	return "CommandResult(%s, %s, %s)" % [ok, code, reason]
