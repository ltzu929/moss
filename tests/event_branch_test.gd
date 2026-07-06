## 分支事件测试
## 验证事件可以根据核心历史标签和轻量事件状态进行条件触发。
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

	_assert_game_event_exposes_branch_condition_fields()
	_assert_branch_event_resources_define_conditions()
	_assert_main_os_exposes_condition_check()
	await _assert_branch_event_waits_for_decision_tag()
	await _assert_branch_event_can_require_event_state_too()

	print("[MOSS-EVENT-BRANCH] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_game_event_exposes_branch_condition_fields() -> void:
	var event := GameEvent.new()
	var property_names := _get_property_names(event)
	for property_name in [
		"required_decision_tag_key",
		"required_decision_tag_value",
		"required_event_state_key",
		"required_event_state_value",
		"causal_thread",
		"branch_reason",
	]:
		_assert_true(
			property_name in property_names,
			"GameEvent 应支持分支条件字段 %s" % property_name
		)


func _assert_main_os_exposes_condition_check() -> void:
	_assert_true(
		_main_os.has_method("can_trigger_event"),
		"MainOS 应提供 can_trigger_event 条件判断接口"
	)


func _assert_branch_event_resources_define_conditions() -> void:
	for resource_path in [
		"res://data/events/event_branch_2056_population_appeal_record.tres",
		"res://data/events/event_branch_2066_hidden_core_leak.tres",
		"res://data/events/event_branch_2071_engine_crew_petition.tres",
		"res://data/events/event_branch_2074_trusteeship_public_record.tres",
	]:
		var event := load(resource_path) as GameEvent
		_assert_true(event != null, "应能加载真实分支事件资源：%s" % resource_path)
		if event == null:
			continue
		_assert_true(event.causal_thread != "", "分支事件应标注因果链：%s" % event.event_title)
		_assert_true(event.branch_reason != "", "分支事件应说明触发原因：%s" % event.event_title)
		_assert_true(
			event.required_decision_tag_key != "" or event.required_event_state_key != "",
			"分支事件应至少声明一个触发条件：%s" % event.event_title
		)
		_assert_true(not event.options.is_empty(), "分支事件应提供可选择方案：%s" % event.event_title)


func _assert_branch_event_waits_for_decision_tag() -> void:
	if not _main_os.has_method("can_trigger_event"):
		return

	var branch_event := _create_branch_event()
	branch_event.set("required_decision_tag_key", "decision.test_branch")
	branch_event.set("required_decision_tag_value", "enabled")

	_assert_true(
		not _main_os.can_trigger_event(branch_event),
		"缺少核心历史标签时分支事件不应满足触发条件"
	)

	_main_os.all_events = [branch_event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2056
	_main_os.current_month = 6
	_main_os._on_timer_timeout()
	await get_tree().process_frame
	_assert_true(
		not _event_popup.visible,
		"缺少核心历史标签时计时器不应弹出分支事件"
	)
	_assert_eq(
		_main_os.triggered_events.size(),
		0,
		"未满足条件的分支事件不应写入 triggered_events"
	)

	_main_os.current_year = 2056
	_main_os.current_month = 6
	_main_os.set_decision_tag(
		"decision.test_branch",
		"enabled",
		"测试分支标签",
		"测试分支标签摘要。",
		"测试事件"
	)
	_assert_true(
		_main_os.can_trigger_event(branch_event),
		"核心历史标签匹配时分支事件应满足触发条件"
	)

	_main_os._on_timer_timeout()
	await get_tree().process_frame
	_assert_true(
		_event_popup.visible,
		"核心历史标签匹配时计时器应弹出分支事件"
	)
	_event_popup.option_selected.emit(0)
	await get_tree().process_frame
	_event_popup.hide()


func _assert_branch_event_can_require_event_state_too() -> void:
	if not _main_os.has_method("can_trigger_event"):
		return

	var branch_event := _create_branch_event()
	branch_event.set("required_decision_tag_key", "decision.test_branch")
	branch_event.set("required_decision_tag_value", "enabled")
	branch_event.set("required_event_state_key", "event_state.test_branch")
	branch_event.set("required_event_state_value", "public")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_main_os.set_decision_tag(
		"decision.test_branch",
		"enabled",
		"测试分支标签",
		"测试分支标签摘要。",
		"测试事件"
	)
	_assert_true(
		not _main_os.can_trigger_event(branch_event),
		"缺少轻量事件状态时复合条件分支不应触发"
	)
	_main_os.set_event_state("event_state.test_branch", "public")
	_assert_true(
		_main_os.can_trigger_event(branch_event),
		"核心历史标签和轻量状态都匹配时复合条件分支应触发"
	)


func _create_branch_event() -> GameEvent:
	var event := GameEvent.new()
	event.event_title = "测试分支事件"
	event.event_time = 2056
	event.event_month = 6
	event.event_region = "联合政府"
	event.event_description = "分支事件条件测试。"
	event.options = [_create_option()]
	event.set("causal_thread", "测试链")
	event.set("branch_reason", "测试分支原因。")
	return event


func _create_option() -> EventOption:
	var option := EventOption.new()
	option.button_text = "记录分支"
	option.order_delta = 1
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
