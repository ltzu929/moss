## 轻量事件状态存取服务。
## 只保存中型事件和条件分支写入的 event_state.* 事实，不依赖场景树或 UI。
class_name EventStateStore
extends RefCounted

var _states: Dictionary = {}


## 写入一个轻量事件状态；空键不产生效果。
func set_state(state_key: String, state_value: String) -> void:
	if state_key.is_empty():
		return
	_states[state_key] = state_value


## 查询轻量事件状态；未写入时返回默认值。
func get_state(state_key: String, default_value: String = "") -> String:
	return str(_states.get(state_key, default_value))


## 判断状态是否存在；提供 expected_value 时同时校验值。
func has_state(state_key: String, expected_value: String = "") -> bool:
	if not _states.has(state_key):
		return false
	return expected_value.is_empty() or get_state(state_key) == expected_value


## 导出状态副本，调用方修改结果不会污染服务内部状态。
func export_state() -> Dictionary:
	return _states.duplicate(true)


func can_restore_state(state: Dictionary) -> bool:
	for key in state:
		if typeof(key) != TYPE_STRING or str(key).is_empty():
			return false
		if typeof(state[key]) != TYPE_STRING:
			return false
	return true


func restore_state(state: Dictionary) -> bool:
	if not can_restore_state(state):
		return false
	_states = state.duplicate(true)
	return true


## 清空本局所有轻量事件状态。
func clear() -> void:
	_states.clear()
