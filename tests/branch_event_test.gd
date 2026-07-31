## 条件分支事件契约与运行时触发测试
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const BRANCH_01_PATH := "res://data/events/event_branch_01_perimeter_compensation_appeal.tres"
const BRANCH_02_PATH := "res://data/events/event_branch_02_hidden_chain_anomaly_receipt.tres"

var _main_os: Control
var _event_popup: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_event_popup = _main_os.get_node("%EventPopup")
	_main_os.get_node("Timer").stop()

	_assert_real_branch_resources()
	_assert_branch_availability()
	await _assert_real_timer_triggers_and_writes_state()
	_assert_branch_state_readback_and_core_coexistence()
	_assert_restart_clears_branch_history()

	print("[MOSS-BRANCH-EVENTS] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_real_branch_resources() -> void:
	var branch_01 := load(BRANCH_01_PATH) as GameEvent
	var branch_02 := load(BRANCH_02_PATH) as GameEvent
	_assert_branch_contract(
		branch_01,
		"外围地下城补偿申诉",
		2054,
		"decision.core_2053_population_vs_infrastructure",
		"sacrifice_perimeter",
		"event_state.branch_01_perimeter_compensation",
		["public_claims_review", "engineering_quota", "moss_archive"],
		["2053", "牺牲"]
	)
	_assert_branch_contract(
		branch_02,
		"隐藏链路异常回执",
		2066,
		"decision.core_2065_audit_posture",
		"hidden_core_chain",
		"event_state.branch_02_hidden_chain_receipt",
		["public_disclosure", "interface_isolation", "audit_trail_rewrite"],
		["2065", "隐藏"]
	)


func _assert_branch_contract(
	event: GameEvent,
	expected_title: String,
	expected_year: int,
	expected_required_key: String,
	expected_required_value: String,
	expected_state_key: String,
	expected_state_values: Array[String],
	required_description_fragments: Array[String]
) -> void:
	_assert_true(event != null, "应能加载真实条件分支：%s" % expected_title)
	if event == null:
		return
	_assert_eq(event.event_title, expected_title, "条件分支标题应稳定")
	_assert_eq(event.event_time, expected_year, "%s 应位于约定年份" % expected_title)
	_assert_eq(event.event_month, 6, "%s 应在非一月触发" % expected_title)
	_assert_eq(event.event_level, "一般事件", "%s 应保持短分支层级" % expected_title)
	_assert_true(event.event_image != null, "%s 应使用专属事件插画" % expected_title)
	_assert_eq(
		event.required_decision_tag_key,
		expected_required_key,
		"%s 应声明唯一核心触发维度" % expected_title
	)
	_assert_eq(
		event.required_decision_tag_value,
		expected_required_value,
		"%s 应声明唯一核心触发值" % expected_title
	)
	for fragment in required_description_fragments:
		_assert_true(
			fragment in event.event_description,
			"%s 正文应直接说明触发前因：%s" % [expected_title, fragment]
		)

	_assert_eq(event.options.size(), 3, "%s 应提供三种治理方案" % expected_title)
	var state_values: Dictionary = {}
	var has_zero_energy := false
	for option in event.options:
		_assert_eq(
			option.event_state_key,
			expected_state_key,
			"%s 的三个方案应写入同一个分支状态" % expected_title
		)
		_assert_true(
			not option.event_state_value.is_empty(),
			"%s 分支状态值不得为空" % expected_title
		)
		_assert_true(
			option.decision_tag_key.is_empty(),
			"%s 不得覆盖不可逆核心决策" % expected_title
		)
		state_values[option.event_state_value] = true
		has_zero_energy = has_zero_energy or option.energy_cost == 0
	_assert_eq(
		state_values.size(),
		expected_state_values.size(),
		"%s 三个方案应写入三个唯一状态值" % expected_title
	)
	for value in expected_state_values:
		_assert_true(
			state_values.has(value),
			"%s 应保留稳定状态值：%s" % [expected_title, value]
		)
	_assert_true(has_zero_energy, "%s 应保留零能源保底方案" % expected_title)


func _assert_branch_availability() -> void:
	var branch_01 := load(BRANCH_01_PATH) as GameEvent
	var branch_02 := load(BRANCH_02_PATH) as GameEvent
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_true(not _main_os.is_event_available(branch_01), "未发生牺牲外围时不得出现补偿申诉")
	_assert_true(not _main_os.is_event_available(branch_02), "未隐藏核心链路时不得出现异常回执")

	_main_os.apply_event_option_decision(event_2053.options[0], event_2053.event_title)
	_assert_true(not _main_os.is_event_available(branch_01), "2053 错误标签值不得触发补偿申诉")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_main_os.apply_event_option_decision(event_2053.options[2], event_2053.event_title)
	_assert_true(_main_os.is_event_available(branch_01), "牺牲外围应解锁补偿申诉")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_main_os.apply_event_option_decision(event_2065.options[0], event_2065.event_title)
	_assert_true(not _main_os.is_event_available(branch_02), "2065 错误标签值不得触发异常回执")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_main_os.apply_event_option_decision(event_2065.options[2], event_2065.event_title)
	_assert_true(_main_os.is_event_available(branch_02), "隐藏核心链路应解锁异常回执")


func _assert_real_timer_triggers_and_writes_state() -> void:
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	await _assert_timer_branch_resolution(
		load(BRANCH_01_PATH) as GameEvent,
		event_2053.options[2],
		event_2053.event_title,
		0,
		"event_state.branch_01_perimeter_compensation",
		"public_claims_review",
		"decision.core_2053_population_vs_infrastructure",
		"sacrifice_perimeter"
	)
	await _assert_timer_branch_resolution(
		load(BRANCH_02_PATH) as GameEvent,
		event_2065.options[2],
		event_2065.event_title,
		2,
		"event_state.branch_02_hidden_chain_receipt",
		"audit_trail_rewrite",
		"decision.core_2065_audit_posture",
		"hidden_core_chain"
	)


func _assert_timer_branch_resolution(
	branch_event: GameEvent,
	core_option: EventOption,
	core_event_title: String,
	choice_index: int,
	expected_state_key: String,
	expected_state_value: String,
	expected_core_key: String,
	expected_core_value: String
) -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_main_os.apply_event_option_decision(core_option, core_event_title)
	_main_os.all_events = [branch_event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = branch_event.event_time
	_main_os.current_month = branch_event.event_month
	_main_os.current_energy = 100

	_main_os._on_timer_timeout()
	await get_tree().process_frame
	var trigger_key := "%04d.%02d:%s" % [
		branch_event.event_time,
		branch_event.event_month,
		branch_event.event_title,
	]
	_assert_true(_event_popup.visible, "%s 应通过真实时间循环打开弹窗" % branch_event.event_title)
	_assert_true(
		trigger_key in _main_os.triggered_events,
		"%s 应写入唯一真实触发键" % branch_event.event_title
	)
	_event_popup.option_selected.emit(choice_index)
	await get_tree().process_frame
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	_assert_eq(
		_main_os.get_event_state(expected_state_key),
		expected_state_value,
		"%s 真实结算应写入分支状态" % branch_event.event_title
	)
	_assert_true(
		_main_os.has_decision_tag(expected_core_key, expected_core_value),
		"%s 结算后应保留原核心事实" % branch_event.event_title
	)


func _assert_branch_state_readback_and_core_coexistence() -> void:
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	var event_2070 := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	var event_2075 := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var compensation_cases: Dictionary = {
		"public_claims_review": "公开复核",
		"engineering_quota": "工程家庭",
		"moss_archive": "MOSS 归档",
	}
	for state_value in compensation_cases:
		var compensation_state := str(state_value)
		_main_os.restart_game_for_test()
		_main_os.get_node("Timer").stop()
		_main_os.apply_event_option_decision(event_2053.options[2], event_2053.event_title)
		_main_os.set_event_state(
			"event_state.branch_01_perimeter_compensation",
			compensation_state
		)
		var display_2075: GameEvent = _main_os.build_display_event(event_2075)
		var ending_text: String = _main_os.build_ending_message("coexistence")
		_assert_true(
			str(compensation_cases[compensation_state]) in display_2075.event_description,
			"2075 正文应回读外围补偿状态：%s" % compensation_state
		)
		_assert_true(
			str(compensation_cases[compensation_state]) in ending_text,
			"结局应回读外围补偿状态：%s" % compensation_state
		)
		_assert_true(
			"牺牲外围" in display_2075.event_description,
			"外围补偿回声不得覆盖 2053 核心事实"
		)

	var receipt_cases: Dictionary = {
		"public_disclosure": {
			"context": "主动公开",
			"ending": "最终被公开",
		},
		"interface_isolation": {
			"context": "单独隔离",
			"ending": "单独隔离",
		},
		"audit_trail_rewrite": {
			"context": "审计轨迹",
			"ending": "审计轨迹",
		},
	}
	for state_value in receipt_cases:
		var receipt_state := str(state_value)
		_main_os.restart_game_for_test()
		_main_os.get_node("Timer").stop()
		_main_os.apply_event_option_decision(event_2065.options[2], event_2065.event_title)
		_main_os.set_event_state(
			"event_state.branch_02_hidden_chain_receipt",
			receipt_state
		)
		var display_2070: GameEvent = _main_os.build_display_event(event_2070)
		var ending_text: String = _main_os.build_ending_message("coexistence")
		var expected_fragments: Dictionary = receipt_cases[receipt_state]
		_assert_true(
			str(expected_fragments["context"]) in display_2070.event_description,
			"2070 正文应回读异常回执状态：%s" % receipt_state
		)
		_assert_true(
			str(expected_fragments["ending"]) in ending_text,
			"结局应回读异常回执状态：%s" % receipt_state
		)
		_assert_true(
			"隐藏的核心链路" in display_2070.event_description,
			"异常回执回声不得覆盖 2065 核心事实"
		)


func _assert_restart_clears_branch_history() -> void:
	_main_os.set_event_state(
		"event_state.branch_01_perimeter_compensation",
		"moss_archive"
	)
	_main_os.set_event_state(
		"event_state.branch_02_hidden_chain_receipt",
		"audit_trail_rewrite"
	)
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_eq(
		_main_os.get_event_state("event_state.branch_01_perimeter_compensation"),
		"",
		"重开应清空外围补偿分支状态"
	)
	_assert_eq(
		_main_os.get_event_state("event_state.branch_02_hidden_chain_receipt"),
		"",
		"重开应清空异常回执分支状态"
	)
