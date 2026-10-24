class_name ResourcePrefetch
extends RefCounted
## Parallel warm-up of the pack resources a scene is about to build from (D-054).
## A grown colony instantiates ~150 prefabs, kits and plant scenes; loading them
## one by one on the main thread was most of its load time. `request()` hands
## them to the engine's threaded loader at the start of the scene, so they load
## on worker threads while the terrain and sky are built; the scene's own
## load() calls then find them ready (or wait for that one file). `release()`
## drops the loader's handles once the scene is built. Missing files (fresh
## clone without the purchased packs) are skipped.

const EXTS := ["tscn", "scn", "fbx", "glb", "res", "tres"]

static var _pending: Array = []


static func request(paths: Array) -> int:
	var n := 0
	var seen := {}
	for p: Variant in paths:
		var path := str(p)
		if path.is_empty() or seen.has(path) or not path.begins_with("res://") or not EXTS.has(path.get_extension().to_lower()):
			continue
		seen[path] = true
		if ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)
			n += 1
	return n


## Collect the finished loads (blocks only for a file still loading).
static func release() -> void:
	for path: String in _pending:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()


## Every resource path string inside a data value (dictionaries, arrays), with
## `resolve` turning short names ("W:Props/SM_Prop_Crate_03") into paths.
static func paths_in(v: Variant, resolve: Callable = Callable(), out: Array = []) -> Array:
	if v is Dictionary:
		for x: Variant in (v as Dictionary).values():
			paths_in(x, resolve, out)
	elif v is Array:
		for x: Variant in v:
			paths_in(x, resolve, out)
	elif v is String:
		var s: String = v
		if s.begins_with("res://"):
			out.append(s)
		elif resolve.is_valid() and s.length() < 200 and (s.find(":") == 1 or s.find(":") == 2):
			var r := str(resolve.call(s))
			if r.begins_with("res://"):
				out.append(r)
	return out
