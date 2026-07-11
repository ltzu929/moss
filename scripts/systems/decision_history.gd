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


func clear() -> void:
	_tags.clear()
	_records.clear()
