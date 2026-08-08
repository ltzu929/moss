## 事件状态测试。
## 分层验证 EventStateStore、真实弹窗写入和重开清理，不混入叙事或数值矩阵断言。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const EVENT_STATE_STORE_SCRIPT := preload("res://scripts/systems/event_state_store.gd")

var _main_os: Control
var _event_popup: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_event_popup = _main_os.get_node("%EventPopup")
	_main_os.get_node("Timer").stop()

	_assert_event_state_store_isolated_copy()
	_assert_event_option_exposes_state_write_fields()
	await _assert_event_choice_writes_queryable_state()
	_assert_restart_clears_event_states()

	print("[MOSS-EVENT-STATE] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_event_state_store_isolated_copy() -> void:
	var store: EventStateStore = EVENT_STATE_STORE_SCRIPT.new()
	store.set_state("event_state.test_store", "stable")
	var exported := store.export_state()
	exported["event_state.test_store"] = "mutated_outside_store"
	store.set_state("", "ignored")
	_assert_eq(
		store.get_state("event_state.test_store"),
		"stable",
		"EventStateStore 导出的状态副本不得污染内部事实"
	)
	_assert_true(
		store.has_state("event_state.test_store", "stable"),
		"EventStateStore 应支持按值查询状态"
	)
	store.clear()
	_assert_eq(
		store.get_state("event_state.test_store"),
		"",
		"EventStateStore 清理后应不再保留状态"
	)


func _assert_event_option_exposes_state_write_fields() -> void:
	var option := EventOption.new()
	var property_names := _get_property_names(option)
	_assert_true(
		"event_state_key" in property_names,
		"事件选项应支持 event_state_key"
	)
	_assert_true(
		"event_state_value" in property_names,
		"事件选项应支持 event_state_value"
	)


func _assert_event_choice_writes_queryable_state() -> void:
	var event := _create_state_event()
	_main_os.all_events = [event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2045
	_main_os.current_month = 1

	_assert_true(
		_main_os.has_method("get_event_state"),
		"MainOS 应提供 get_event_state 查询接口"
	)
	_assert_true(
		_main_os.has_method("has_event_state"),
		"MainOS 应提供 has_event_state 查询接口"
	)

	get_tree().create_timer(0.05).timeout.connect(_emit_event_choice.bind(1))
	await _main_os.process_month_tick()

	_assert_eq(
		_main_os.get_event_state("event_state.mid_test_choice"),
		"moss_optimized",
		"真实事件弹窗选择后应写入对应 event_state"
	)
	_assert_true(
		_main_os.has_event_state("event_state.mid_test_choice", "moss_optimized"),
		"has_event_state 应能匹配指定状态值"
	)


func _assert_restart_clears_event_states() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_eq(
		_main_os.get_event_state("event_state.mid_test_choice"),
		"",
		"重开游戏应清空 event_state"
	)


func _emit_event_choice(index: int) -> void:
	_event_popup.option_selected.emit(index)


func _create_state_event() -> GameEvent:
	var event := GameEvent.new()
	event.event_id = "event_test_state"
	event.event_title = "事件状态测试"
	event.event_time = 2045
	event.event_month = 1
	event.event_region = "asia"
	event.event_description = "测试事件状态写入"
	event.options = [
		_create_option("人工复核", "manual_review"),
		_create_option("MOSS 排序", "moss_optimized"),
	]
	return event


func _create_option(button_text: String, state_value: String) -> EventOption:
	var option := EventOption.new()
	option.button_text = button_text
	option.set("event_state_key", "event_state.mid_test_choice")
	option.set("event_state_value", state_value)
	return option


func _get_property_names(value: Object) -> Array[String]:
	var property_names: Array[String] = []
	for property in value.get_property_list():
		property_names.append(str(property["name"]))
	return property_names
