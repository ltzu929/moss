## 月制时间系统测试
## 验证月份推进、非一月事件、年度结算和终局顺序
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

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
	await _assert_time_speed_and_single_step()

	print("[MOSS-TIME-SYSTEM] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_initial_date_and_no_opening_recovery() -> void:
	_assert_eq(_main_os.current_year, 2044, "初始年份应为 2044")
	_assert_eq(_main_os.current_month, 1, "初始月份应为 1 月")
	_assert_eq(_main_os.current_cpu, 30, "开局不应额外恢复算力")
	_assert_eq(_main_os.current_energy, 100, "开局不应额外恢复能源")


func _assert_non_january_event_triggers_once() -> void:
	var events: Array[GameEvent] = [_create_event("event_test_february", "二月测试事件", 2044, 2)]
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
		"event_test_february",
		"触发事件键应使用稳定事件 ID"
	)

	_main_os.current_year = 2044
	_main_os.current_month = 2
	await _tick_without_event_choice()
	_assert_eq(_main_os.triggered_events.size(), 1, "同日期事件不应重复触发")


func _assert_year_boundary_settlement_before_end_event() -> void:
	var events: Array[GameEvent] = [_create_event("event_test_jupiter", "木星测试事件", 2075, 1)]
	_main_os.all_events = events
	_main_os.triggered_events.clear()
	_main_os.current_year = 2074
	_main_os.current_month = 12
	_main_os.current_cpu = 30
	_main_os.current_energy = 100
	_main_os.command_cooldowns[CommandSystem.COMMAND_TAKEOVER] = 2

	await _tick_without_event_choice()
	_assert_eq(_main_os.current_year, 2075, "2074.12 推进后应进入 2075 年")
	_assert_eq(_main_os.current_month, _main_os.END_MONTH, "2074.12 推进后应进入终局月份")
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


func _assert_time_speed_and_single_step() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	_main_os.set_time_speed(0.5)
	_assert_true(is_equal_approx(_main_os.get_time_speed(), 0.5), "0.5x 应成为当前推进速度")
	_assert_true(is_equal_approx(timer.wait_time, 2.0), "0.5x 应设置为 2 秒/月")
	_main_os.set_time_speed(2.0)
	_assert_true(is_equal_approx(_main_os.get_time_speed(), 2.0), "2x 应成为当前推进速度")
	_assert_true(is_equal_approx(timer.wait_time, 0.5), "2x 应设置为 0.5 秒/月")
	_main_os.set_time_speed(3.0)
	_assert_true(is_equal_approx(_main_os.get_time_speed(), 2.0), "不支持的速度不应覆盖当前速度")

	_main_os.set_time_speed(1.0)
	_main_os.triggered_events.clear()
	timer.stop()
	await _main_os.step_month_once()
	_assert_eq(_main_os.current_year, 2044, "单步推进首月后年份应保持 2044")
	_assert_eq(_main_os.current_month, 2, "单步推进应完整推进一个月")
	_assert_true(timer.is_stopped(), "单步推进完成后应保持暂停")
	_assert_eq(
		(_main_os.get_node("MainLayout/MainHud") as MainHud).get_time_control_button().text,
		"继续",
		"单步推进完成后按钮应提示继续"
	)


func _tick_without_event_choice() -> void:
	await _main_os.process_month_tick()


func _tick_and_choose_event() -> void:
	get_tree().create_timer(0.05).timeout.connect(_emit_event_choice.bind(0))
	await _main_os.process_month_tick()


func _emit_event_choice(index: int) -> void:
	_event_popup.option_selected.emit(index)
	_event_popup.hide()


func _create_event(event_id: String, title: String, year: int, month: int) -> GameEvent:
	var event := GameEvent.new()
	event.event_id = event_id
	event.event_title = title
	event.event_time = year
	event.event_month = month
	event.event_region = "asia"
	event.event_description = "测试事件"
	event.options = [_create_option()]
	return event


func _create_option() -> EventOption:
	var option := EventOption.new()
	option.button_text = "确认"
	return option
