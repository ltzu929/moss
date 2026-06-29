## 事件状态测试
## 验证事件选项可以写入可查询的轻量历史状态
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _failed: int = 0
var _main_os: Control
var _event_popup: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_event_popup = _main_os.get_node("%EventPopup")
	_main_os.get_node("Timer").stop()

	_assert_event_option_exposes_state_write_fields()
	await _assert_event_choice_writes_queryable_state()
	_assert_civic_event_states_change_main_event_context()
	_assert_restart_clears_event_states()

	print("[MOSS-EVENT-STATE] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


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

	_main_os._on_timer_timeout()
	await get_tree().process_frame
	_event_popup.option_selected.emit(1)
	await get_tree().process_frame

	_assert_eq(
		_main_os.get_event_state("event_state.mid_test_choice"),
		"moss_optimized",
		"选择事件方案后应写入对应 event_state"
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


func _assert_civic_event_states_change_main_event_context() -> void:
	_assert_true(
		_main_os.has_method("build_event_description"),
		"MainOS 应提供 build_event_description 生成可读取历史状态的事件正文"
	)
	if not _main_os.has_method("build_event_description"):
		return

	_main_os.set_event_state("event_state.mid_01_lottery_ordering", "manual_review")
	_main_os.set_event_state("event_state.mid_06_ration_priority", "family_baseline")
	_main_os.set_event_state("event_state.mid_07_migration_priority", "humanitarian")

	var flood_event := _create_named_event("大淹没事故", 2053, "根服务器和地下城同时承压。")
	var flood_description: String = _main_os.build_event_description(flood_event)
	_assert_true(
		"历史回声" in flood_description,
		"2053 主事件正文应追加历史回声段落"
	)
	_assert_true(
		"申诉窗口" in flood_description,
		"2053 主事件应读取 MID-01 人工复核抽签背景"
	)
	_assert_true(
		"家庭最低保障" in flood_description,
		"2053 主事件应读取 MID-06 家庭配给背景"
	)

	var real_flood_event := load("res://data/events/event_2053.tres") as GameEvent
	_assert_true(real_flood_event != null, "应能加载真实 2053 主事件资源")
	if real_flood_event != null:
		var original_description: String = real_flood_event.event_description
		var display_flood_event: GameEvent = _main_os.build_display_event(real_flood_event)
		_assert_true(
			display_flood_event != real_flood_event,
			"build_display_event 应返回独立运行时副本"
		)
		_assert_true(
			"历史回声" in display_flood_event.event_description,
			"真实 2053 主事件运行时副本应包含历史回声"
		)
		_assert_eq(
			real_flood_event.event_description,
			original_description,
			"真实 2053 主事件原始描述不应被运行时副本污染"
		)

	var jupiter_event := _create_named_event("木星引力危机", 2075, "终局方案等待授权。")
	var jupiter_description: String = _main_os.build_event_description(jupiter_event)
	_assert_true(
		"普通人仍记得早年的申诉窗口" in jupiter_description,
		"2075 终局事件应读取 MID-01 作为普通人回声"
	)
	_assert_true(
		"人道迁移记录" in jupiter_description,
		"2075 终局事件应读取 MID-07 迁移优先级"
	)

	var real_jupiter_event := load("res://data/events/event_2075.tres") as GameEvent
	_assert_true(real_jupiter_event != null, "应能加载真实 2075 主事件资源")
	if real_jupiter_event != null:
		var original_description: String = real_jupiter_event.event_description
		var display_jupiter_event: GameEvent = _main_os.build_display_event(real_jupiter_event)
		_assert_true(
			display_jupiter_event != real_jupiter_event,
			"build_display_event 应为 2075 返回独立运行时副本"
		)
		_assert_true(
			"人道迁移记录" in display_jupiter_event.event_description,
			"真实 2075 主事件运行时副本应读取 MID-07 迁移优先级"
		)
		_assert_eq(
			real_jupiter_event.event_description,
			original_description,
			"真实 2075 主事件原始描述不应被运行时副本污染"
		)


func _create_state_event() -> GameEvent:
	var event := GameEvent.new()
	event.event_title = "事件状态测试"
	event.event_time = 2045
	event.event_month = 1
	event.event_region = "亚洲"
	event.event_description = "测试事件状态写入"
	event.options = [
		_create_option("人工复核", "manual_review"),
		_create_option("MOSS 排序", "moss_optimized"),
	]
	return event


func _create_named_event(title: String, year: int, description: String) -> GameEvent:
	var event := GameEvent.new()
	event.event_title = title
	event.event_time = year
	event.event_month = 1
	event.event_region = "联合政府"
	event.event_description = description
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


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
