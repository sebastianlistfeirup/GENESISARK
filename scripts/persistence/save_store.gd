class_name SaveStore
extends RefCounted
## File IO for saves with safe writes (bible p.22): write a temp file, close,
## re-read and validate it, keep the last valid file as backup, then replace the
## main file on the same filesystem. Interrupted writes and corrupt files offer
## the backup; there is never a silent reset to a new campaign.

var dir_path: String


func _init(base_dir: String = "user://saves") -> void:
	dir_path = base_dir
	DirAccess.make_dir_recursive_absolute(dir_path)


func main_path(slot: String) -> String:
	return "%s/%s.json" % [dir_path, slot]


func write(slot: String, envelope: Dictionary, content: ContentDB) -> Dictionary:
	var path := main_path(slot)
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Kan ikke skrive midlertidig fil (%s)." % error_string(FileAccess.get_open_error())}
	f.store_string(JSON.stringify(envelope, "\t"))
	f.close()
	# Re-read and validate what actually landed on disk before trusting it.
	var check := SaveCodec.decode(DictUtil.load_json(tmp), content)
	if not check["ok"]:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "error": "Verificering af ny save fejlede: " + str(check["error"])}
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var err := DirAccess.rename_absolute(path, bak)
		if err != OK:
			return {"ok": false, "error": "Kunne ikke lave backup (%s)." % error_string(err)}
	var err2 := DirAccess.rename_absolute(tmp, path)
	if err2 != OK:
		return {"ok": false, "error": "Kunne ikke erstatte save (%s)." % error_string(err2)}
	return {"ok": true, "path": path}


## Returns {ok, state, source, error, backup_available, migrated_from}.
func read(slot: String, content: ContentDB, prefer_backup: bool = false) -> Dictionary:
	var path := main_path(slot)
	var bak := path + ".bak"
	var res := {"ok": false, "state": null, "source": "", "error": "", "backup_available": false, "migrated_from": 0}
	var bak_ok := false
	if FileAccess.file_exists(bak):
		bak_ok = SaveCodec.decode(DictUtil.load_json(bak), content)["ok"]
	res["backup_available"] = bak_ok
	var target := bak if prefer_backup else path
	if not FileAccess.file_exists(target):
		if FileAccess.file_exists(path + ".tmp") and not prefer_backup:
			res["error"] = "Den seneste gemning blev afbrudt." + (" En backup er tilgængelig." if bak_ok else "")
		else:
			res["error"] = "Ingen save i dette slot."
		return res
	var dec := SaveCodec.decode(DictUtil.load_json(target), content)
	if not dec["ok"]:
		res["error"] = str(dec["error"]) + (" En backup er tilgængelig." if bak_ok and not prefer_backup else "")
		return res
	res["ok"] = true
	res["state"] = dec["state"]
	res["source"] = "backup" if prefer_backup else "main"
	res["migrated_from"] = dec["migrated_from"]
	return res


func exists(slot: String) -> bool:
	return FileAccess.file_exists(main_path(slot)) or FileAccess.file_exists(main_path(slot) + ".bak")


func summary(slot: String) -> Dictionary:
	var v: Variant = DictUtil.load_json(main_path(slot))
	if not v is Dictionary:
		return {}
	var p: Dictionary = DictUtil.get_dict(v, "payload")
	var camp: Dictionary = DictUtil.get_dict(p, "campaign")
	return {"saved_at": v.get("saved_at", ""), "phase": camp.get("phase", ""), "location": camp.get("location_id", ""),
		"colony_day": camp.get("colony_day", 0), "planet": camp.get("selected_planet_id", "")}


func delete_slot(slot: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(main_path(slot) + suffix):
			DirAccess.remove_absolute(main_path(slot) + suffix)
