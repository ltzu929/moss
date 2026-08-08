## 事件领域真实写回测试。
## 通过真实 EventPopup 和 MainOS 月度编排验证 preview、resolve 与场景写回边界。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _main_os: Control
var _event_popup: Control
var _preview_button_text: String = ""
var _preview_button_disabled: bool = false


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_event_popup = _main_os.get_node("%EventPopup")

	await _assert_real_2070_to_2075_writeback_matrix()
	await _assert_lower_bounds_through_real_event()
	await _assert_energy_cap_and_upper_bounds_through_real_event()

	print("[MOSS-EVENT-WRITEBACK] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_real_2070_to_2075_writeback_matrix() -> void:
	var cases: Array[Dictionary] = [
		{
			"decision": "personnel_first_shutdown",
			"option_id": "option_01",
			"index": 0,
			"hope_delta": 25,
			"order_delta": 15,
			"authority_delta": 8,
			"energy_cost": 100,
			"suffix": "人员安全记录在案",
		},
		{
			"decision": "redundant_array",
			"option_id": "option_02",
			"index": 1,
			"hope_delta": -10,
			"order_delta": 25,
			"authority_delta": 5,
			"energy_cost": 0,
			"suffix": "冗余阵列仍可维持",
		},
		{
			"decision": "forced_overclock",
			"option_id": "option_03",
			"index": 2,
			"hope_delta": -45,
			"order_delta": 40,
			"authority_delta": 20,
			"energy_cost": 20,
			"suffix": "超频链路已验证",
		},
	]

	for case in cases:
		await _run_2075_writeback_case(case)


func _run_2075_writeback_case(case: Dictionary) -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	await get_tree().process_frame

	var source_event := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var source_decision_event := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	_assert_true(source_event != null, "2075 写回矩阵应加载真实终局事件")
	_assert_true(source_decision_event != null, "2075 写回矩阵应加载真实 2070 决策事件")
	if source_event == null or source_decision_event == null:
		return

	var decision_option := _get_option_by_decision(
		source_decision_event,
		str(case["decision"])
	)
	_assert_true(
		decision_option != null,
		"2070 决策应能为 2075 写回矩阵提供真实历史标签"
	)
	if decision_option == null:
		return
	_main_os.apply_event_option_decision(
		decision_option,
		source_decision_event.event_title
	)

	var sector := _get_sector("europe")
	_assert_true(sector != null, "2075 真实事件应能找到欧洲写回板块")
	if sector == null:
		return
	_set_sector_values(sector, 50, 50, 50)

	var runtime_event := source_event.duplicate(true) as GameEvent
	runtime_event.event_time = 2074
	runtime_event.event_month = 1
	runtime_event.event_title = "改名后的 2075 终局事件"
	var selected_option := _get_option(runtime_event, str(case["option_id"]))
	_assert_true(selected_option != null, "2075 运行时副本应保留稳定 option_id")
	if selected_option == null:
		return
	selected_option.button_text = "改名后的终局方案"
	_main_os.all_events = [runtime_event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2074
	_main_os.current_month = 1
	_main_os.current_energy = 100

	var preview_event: GameEvent = _main_os.build_display_event(runtime_event)
	var preview_option := _get_option(preview_event, str(case["option_id"]))
	_assert_true(preview_option != null, "2075 预览应来自运行时事件副本")
	if preview_option == null:
		return
	_assert_eq(
		preview_option.hope_delta,
		int(case["hope_delta"]),
		"2070 决策到 2075 的预览希望应使用同一运行时选项快照"
	)
	_assert_eq(
		preview_option.energy_cost,
		int(case["energy_cost"]),
		"2070 决策到 2075 的预览能源应使用同一运行时选项快照"
	)
	_assert_true(
		str(case["suffix"]) in preview_option.button_text,
		"2075 预览按钮应包含对应核心决策历史后缀"
	)

	_preview_button_text = ""
	_preview_button_disabled = false
	get_tree().create_timer(0.05).timeout.connect(
		_capture_popup_and_emit.bind(int(case["index"]), false)
	)
	await _main_os.process_month_tick()

	_assert_true(
		str(case["suffix"]) in _preview_button_text,
		"真实 EventPopup 应显示同一历史后缀"
	)
	_assert_true(
		"改名后的终局方案" in _preview_button_text,
		"真实 EventPopup 应消费运行时副本而不是原始标题/按钮文字"
	)
	_assert_true(
		not _preview_button_disabled,
		"100 能源下 2075 矩阵中的实际方案应保持可执行"
	)

	_assert_eq(
		sector.data_card.order,
		50 + int(case["order_delta"]),
		"真实 MainOS 写回应使用结算秩序投影"
	)
	_assert_eq(
		sector.data_card.hope,
		50 + int(case["hope_delta"]),
		"真实 MainOS 写回应使用结算希望投影"
	)
	_assert_eq(
		sector.data_card.authority,
		50 + int(case["authority_delta"]),
		"真实 MainOS 写回应使用结算控制权投影"
	)
	_assert_eq(
		_main_os.current_energy,
		100 - int(case["energy_cost"]),
		"真实 MainOS 写回应扣除结算能源投影"
	)
	_assert_eq(
		_main_os.triggered_events[0],
		"event_2075_jupiter_gravity_crisis",
		"修改标题后真实触发记录仍应使用稳定 event_id"
	)
	_assert_eq(
		source_event.event_title,
		"木星引力危机",
		"真实 2075 资源标题不应被运行时副本污染"
	)
	_assert_eq(
		_get_option(source_event, str(case["option_id"])).energy_cost,
		100 if str(case["option_id"]) == "option_01" else (
			30 if str(case["option_id"]) == "option_03" else 0
		),
		"真实 2075 资源能源代价不应被历史调整污染"
	)


func _assert_lower_bounds_through_real_event() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	await get_tree().process_frame

	var source_event := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	_assert_true(source_event != null, "边界写回应加载真实 2070 事件")
	if source_event == null:
		return
	var sector := _get_sector("europe")
	_assert_true(sector != null, "边界写回应找到欧洲板块")
	if sector == null:
		return
	_set_sector_values(sector, 0, 100, 0)

	var runtime_event := source_event.duplicate(true) as GameEvent
	runtime_event.event_time = 2074
	runtime_event.event_month = 1
	_main_os.all_events = [runtime_event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2074
	_main_os.current_month = 1
	_main_os.current_energy = 100

	_preview_button_text = ""
	_preview_button_disabled = true
	get_tree().create_timer(0.05).timeout.connect(
		_capture_popup_and_emit.bind(0, false)
	)
	await _main_os.process_month_tick()

	_assert_true(not _preview_button_disabled, "2070 零能源方案应在真实弹窗中可执行")
	_assert_eq(sector.data_card.order, 0, "秩序下限写回不得低于 0")
	_assert_eq(sector.data_card.hope, 100, "希望上限写回不得超过 100")
	_assert_eq(sector.data_card.authority, 0, "控制权下限写回不得低于 0")
	_assert_eq(_main_os.current_energy, 100, "零能源方案写回不得错误扣除能源")
	_assert_eq(
		_get_option(source_event, "option_01").order_delta,
		-15,
		"真实 2070 资源秩序代价不应被边界写回污染"
	)


func _assert_energy_cap_and_upper_bounds_through_real_event() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	await get_tree().process_frame

	var source_event := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	_assert_true(source_event != null, "能源上限写回应加载真实 2075 事件")
	if source_event == null:
		return
	var sector := _get_sector("europe")
	_assert_true(sector != null, "能源上限写回应找到欧洲板块")
	if sector == null:
		return
	_set_sector_values(sector, 100, 90, 100)

	var runtime_event := source_event.duplicate(true) as GameEvent
	runtime_event.event_time = 2074
	runtime_event.event_month = 1
	_main_os.all_events = [runtime_event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2074
	_main_os.current_month = 1
	_main_os.current_energy = 7

	_preview_button_text = ""
	_preview_button_disabled = false
	get_tree().create_timer(0.05).timeout.connect(
		_capture_popup_and_emit.bind(0, true)
	)
	await _main_os.process_month_tick()

	_assert_true(
		_preview_button_disabled,
		"能源不足时真实 EventPopup 应禁用 100 能源方案"
	)
	_assert_eq(sector.data_card.order, 100, "秩序上限写回不得超过 100")
	_assert_eq(sector.data_card.hope, 100, "希望上限写回不得超过 100")
	_assert_eq(sector.data_card.authority, 100, "控制权上限写回不得超过 100")
	_assert_eq(
		_main_os.current_energy,
		0,
		"结算投影应将能源扣除限制在当前可用能源以内"
	)


func _capture_popup_and_emit(index: int, bypass_disabled: bool) -> void:
	var option_list := _event_popup.get_node("%OptionList")
	var button: Button = null
	if index < option_list.get_child_count():
		button = option_list.get_child(index) as Button
		_preview_button_text = button.text
		_preview_button_disabled = button.disabled
	if button != null and not bypass_disabled:
		button.pressed.emit()
	else:
		_event_popup.option_selected.emit(index)


func _get_sector(region_id: String) -> SectorInfo:
	var container := _main_os.get_node("%SectorInfoContainer")
	for child in container.get_children():
		if child is SectorInfo and child.data_card != null:
			if child.data_card.region_id == region_id:
				return child
	return null


func _set_sector_values(sector: SectorInfo, order: int, hope: int, authority: int) -> void:
	sector.data_card.order = order
	sector.data_card.hope = hope
	sector.data_card.authority = authority
	sector.update_display()


func _get_option(event: GameEvent, option_id: String) -> EventOption:
	for option in event.options:
		if option.option_id == option_id:
			return option
	return null


func _get_option_by_decision(event: GameEvent, decision_value: String) -> EventOption:
	for option in event.options:
		if option.decision_tag_value == decision_value:
			return option
	return null
