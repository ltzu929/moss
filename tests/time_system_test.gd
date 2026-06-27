## 月制时间系统测试
## 验证月份推进、非一月事件、年度结算和终局顺序
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

	_assert_initial_date_and_no_opening_recovery()
	await _assert_non_january_event_triggers_once()
	await _assert_year_boundary_settlement_before_end_event()
	_assert_restart_resets_month()

	print("[MOSS-TIME-SYSTEM] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_initial_date_and_no_opening_recovery() -> void:
	_assert_eq(_main_os.current_year, 2044, "初始年份应为 2044")
	_assert_eq(_main_os.current_month, 1, "初始月份应为 1 月")
	_assert_eq(_main_os.current_cpu, 30, "开局不应额外恢复算力")
	_assert_eq(_main_os.current_energy, 100, "开局不应额外恢复能源")


func _assert_non_january_event_triggers_once() -> void:
	var events: Array[GameEvent] = [_create_event("二月测试事件", 2044, 2)]
	_main_os.all_events = events
	_main_os.triggered_events.clear()

	await _tick_without_event_choice()
	_assert_eq(_main_os.current_year, 2044, "第一次推进后仍应处于 2044 年")
	_assert_eq(_main_os.current_month, 2, "第一次推进后应进入 2 月")
	_assert_eq(_main_os.triggered_events.size(), 0, "2044.01 不应触发 2044.02 事件")

	await _tick_and_choose_event()
	_assert_eq(_main_os.triggered_events.size(), 1, "2044.02 事件应触发一次")
	_assert_eq(
		_main_os.triggered_events[0],
		"2044.02:二月测试事件",
		"触发事件键应包含年月和标题"
	)

	await _tick_without_event_choice()
	_assert_eq(_main_os.triggered_events.size(), 1, "二月事件不应重复触发")


func _assert_year_boundary_settlement_before_end_event() -> void:
	var events: Array[GameEvent] = [_create_event("木星测试事件", 2075, 1)]
	_main_os.all_events = events
	_main_os.triggered_events.clear()
	_main_os.current_year = 2074
	_main_os.current_month = 12
	_main_os.current_cpu = 30
	_main_os.current_energy = 100
	_main_os.command_cooldowns[CommandSystem.COMMAND_TAKEOVER] = 2

	await _tick_without_event_choice()
	_assert_eq(_main_os.current_year, 2075, "2074.12 推进后应进入 2075 年")
	_assert_eq(_main_os.current_month, 1, "2074.12 推进后应进入 1 月")
	_assert_eq(_main_os.current_cpu, 40, "进入 1 月时应先执行年度算力恢复")
	_assert_eq(_main_os.current_energy, 110, "进入 1 月时应先执行年度能源恢复")
	_assert_eq(
		_main_os.command_cooldowns[CommandSystem.COMMAND_TAKEOVER],
		1,
		"月冷却应在每次月份推进后递减"
	)
	_assert_true(not _main_os.is_game_over, "进入 2075.01 的推进 tick 不应立即结局")

	await _tick_and_choose_event()
	_assert_true(_main_os.is_game_over, "处理 2075.01 事件后应结算结局")
	_assert_eq(_main_os.current_year, 2075, "终局结算不应再推进年份")
	_assert_eq(_main_os.current_month, 1, "终局结算不应再推进月份")
	_assert_eq(_main_os.triggered_events.size(), 1, "终局事件应触发一次")


func _assert_restart_resets_month() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_eq(_main_os.current_year, 2044, "重开应重置年份")
	_assert_eq(_main_os.current_month, 1, "重开应重置月份")


func _tick_without_event_choice() -> void:
	_main_os._on_timer_timeout()
	await get_tree().process_frame


func _tick_and_choose_event() -> void:
	_main_os._on_timer_timeout()
	await get_tree().process_frame
	_event_popup.option_selected.emit(0)
	await get_tree().process_frame


func _create_event(title: String, year: int, month: int) -> GameEvent:
	var event := GameEvent.new()
	event.event_title = title
	event.event_time = year
	event.event_month = month
	event.event_region = "亚洲"
	event.event_description = "测试事件"
	event.options = [_create_option()]
	return event


func _create_option() -> EventOption:
	var option := EventOption.new()
	option.button_text = "确认"
	return option


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
