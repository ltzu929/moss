class_name SaveService
extends RefCounted

const FORMAT_VERSION: int = 1
const SLOT_IDS: Array[String] = ["autosave", "slot_1", "slot_2", "slot_3"]
const SAVE_STATE_VALIDATOR := preload("res://scripts/systems/save_state_validator.gd")

var _save_directory: String


func _init(save_directory: String = "user://saves") -> void:
	_save_directory = save_directory.trim_suffix("/")


func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot_id in SLOT_IDS:
		var path := _slot_path(slot_id)
		if not FileAccess.file_exists(path):
			slots.append(_empty_slot(slot_id))
			continue
		var result := read_slot(slot_id)
		if bool(result.get("success", false)):
			slots.append(
				{
					"slot_id": slot_id,
					"kind": _slot_kind(slot_id),
					"exists": true,
					"valid": true,
					"saved_at_unix": float(result.get("saved_at_unix", 0.0)),
					"metadata": result.get("metadata", {}).duplicate(true),
					"error": "",
				}
			)
		else:
			slots.append(
				{
					"slot_id": slot_id,
					"kind": _slot_kind(slot_id),
					"exists": true,
					"valid": false,
					"saved_at_unix": 0.0,
					"metadata": {},
					"error": str(result.get("error", "存档损坏")),
				}
			)
	return slots


func write_slot(
	slot_id: String,
	state: Dictionary,
	metadata: Dictionary = {}
) -> bool:
	if not _is_valid_slot_id(slot_id):
		return false
	if not _ensure_save_directory():
		return false
	var envelope := {
		"format_version": FORMAT_VERSION,
		"slot_kind": _slot_kind(slot_id),
		"saved_at_unix": _next_timestamp(),
		"metadata": metadata.duplicate(true),
		"state": state.duplicate(true),
	}
	var final_path := _slot_path(slot_id)
	var temp_path := "%s.tmp" % final_path
	var backup_path := "%s.bak" % final_path
	if FileAccess.file_exists(temp_path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path)) != OK:
			return false
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var serialized := JSON.stringify(envelope, "\t")
	file.store_string(serialized)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not FileAccess.file_exists(temp_path):
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	if FileAccess.get_file_as_string(temp_path) != serialized:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false

	var had_final := FileAccess.file_exists(final_path)
	if had_final:
		if FileAccess.file_exists(backup_path):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path)) != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
				return false
		if DirAccess.rename_absolute(
			ProjectSettings.globalize_path(final_path),
			ProjectSettings.globalize_path(backup_path)
		) != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return false
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(final_path)
	) != OK:
		if had_final:
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path),
				ProjectSettings.globalize_path(final_path)
			)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	if had_final and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return true


func read_slot(slot_id: String) -> Dictionary:
	if not _is_valid_slot_id(slot_id):
		return {"success": false, "error": "未知存档槽位"}
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return {"success": false, "error": "存档不存在"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"success": false, "error": "存档无法读取"}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"success": false, "error": "存档损坏"}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"success": false, "error": "存档损坏"}
	var envelope: Dictionary = _normalize_json_value(parsed)
	if int(envelope.get("format_version", 0)) != FORMAT_VERSION:
		return {"success": false, "error": "存档版本不受支持"}
	if typeof(envelope.get("state")) != TYPE_DICTIONARY:
		return {"success": false, "error": "存档状态缺失"}
	if not SAVE_STATE_VALIDATOR.validate_state(envelope["state"]):
		return {"success": false, "error": "存档状态损坏"}
	if typeof(envelope.get("metadata", {})) != TYPE_DICTIONARY:
		return {"success": false, "error": "存档摘要损坏"}
	return {
		"success": true,
		"saved_at_unix": float(envelope.get("saved_at_unix", 0.0)),
		"metadata": (envelope.get("metadata", {}) as Dictionary).duplicate(true),
		"state": (envelope["state"] as Dictionary).duplicate(true),
	}


func delete_slot(slot_id: String) -> bool:
	if not _is_valid_slot_id(slot_id):
		return false
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func get_latest_valid_slot() -> Dictionary:
	var latest: Dictionary = {}
	for slot in list_slots():
		if not bool(slot.get("valid", false)):
			continue
		if (
			latest.is_empty()
			or float(slot["saved_at_unix"]) > float(latest["saved_at_unix"])
		):
			latest = slot
	return latest.duplicate(true)


func slot_exists(slot_id: String) -> bool:
	return _is_valid_slot_id(slot_id) and FileAccess.file_exists(_slot_path(slot_id))


func _empty_slot(slot_id: String) -> Dictionary:
	return {
		"slot_id": slot_id,
		"kind": _slot_kind(slot_id),
		"exists": false,
		"valid": false,
		"saved_at_unix": 0.0,
		"metadata": {},
		"error": "",
	}


func _ensure_save_directory() -> bool:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_save_directory)):
		return true
	return (
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_save_directory)
		)
		== OK
	)


func _slot_path(slot_id: String) -> String:
	return "%s/%s.json" % [_save_directory, slot_id]


func _slot_kind(slot_id: String) -> String:
	return "auto" if slot_id == "autosave" else "manual"


func _is_valid_slot_id(slot_id: String) -> bool:
	return slot_id in SLOT_IDS


func _next_timestamp() -> float:
	var timestamp := Time.get_unix_time_from_system()
	for slot_id in SLOT_IDS:
		if not FileAccess.file_exists(_slot_path(slot_id)):
			continue
		var existing := read_slot(slot_id)
		if not bool(existing.get("success", false)):
			continue
		timestamp = maxf(
			timestamp,
			float(existing.get("saved_at_unix", 0.0)) + 0.001
		)
	return timestamp


func _normalize_json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var number: float = value
			return int(number) if number == floorf(number) else number
		TYPE_ARRAY:
			var normalized_array: Array = []
			for entry in value:
				normalized_array.append(_normalize_json_value(entry))
			return normalized_array
		TYPE_DICTIONARY:
			var normalized_dictionary: Dictionary = {}
			for key in value:
				normalized_dictionary[key] = _normalize_json_value(value[key])
			return normalized_dictionary
		_:
			return value
