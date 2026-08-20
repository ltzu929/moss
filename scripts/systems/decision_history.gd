## 核心决策历史
## 保存不可逆历史标签及其面向玩家的档案记录，不依赖场景树或 UI。
class_name DecisionHistory
extends RefCounted

var _tags: Dictionary = {}
var _records: Array[Dictionary] = []


## 记录一次不可逆核心决策；同一标签已经存在时拒绝覆盖。
func record_decision(
	key: String,
	value: String,
	title: String,
	summary: String,
	year: int,
	month: int,
	event_title: String
) -> bool:
	if key.is_empty() or value.is_empty() or _tags.has(key):
		return false

	_tags[key] = value
	_records.append(
		{
			"key": key,
			"value": value,
			"title": title,
			"summary": summary,
			"year": year,
			"month": month,
			"event_title": event_title,
		}
	)
	return true


func get_tag(key: String, default_value: String = "") -> String:
	return str(_tags.get(key, default_value))


func has_tag(key: String, expected_value: String = "") -> bool:
	if not _tags.has(key):
		return false
	return expected_value.is_empty() or get_tag(key) == expected_value


func get_records() -> Array[Dictionary]:
	return _records.duplicate(true)


func export_state() -> Dictionary:
	return {
		"tags": _tags.duplicate(true),
		"records": get_records(),
	}


func can_restore_state(state: Dictionary) -> bool:
	var raw_tags: Variant = state.get("tags")
	var raw_records: Variant = state.get("records")
	if typeof(raw_tags) != TYPE_DICTIONARY or typeof(raw_records) != TYPE_ARRAY:
		return false
	var tags: Dictionary = raw_tags
	for key in tags:
		if typeof(key) != TYPE_STRING or str(key).is_empty():
			return false
		if typeof(tags[key]) != TYPE_STRING or str(tags[key]).is_empty():
			return false
	var seen_keys: Dictionary = {}
	for record_variant in raw_records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = record_variant
		for field in ["key", "value", "title", "summary", "event_title"]:
			if typeof(record.get(field)) != TYPE_STRING:
				return false
		var key := str(record["key"])
		if key.is_empty() or seen_keys.has(key):
			return false
		if not tags.has(key) or str(tags[key]) != str(record["value"]):
			return false
		if typeof(record.get("year")) != TYPE_INT:
			return false
		if typeof(record.get("month")) != TYPE_INT:
			return false
		if int(record["month"]) < 1 or int(record["month"]) > 12:
			return false
		seen_keys[key] = true
	return seen_keys.size() == tags.size()


func restore_state(state: Dictionary) -> bool:
	if not can_restore_state(state):
		return false
	_tags = (state["tags"] as Dictionary).duplicate(true)
	_records.clear()
	for record_variant in state["records"]:
		_records.append((record_variant as Dictionary).duplicate(true))
	return true


func clear() -> void:
	_tags.clear()
	_records.clear()
