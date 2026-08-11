## 事件叙事组合矩阵测试。
## 通过真实事件资源和 MainOS 公开路径验证多来源历史正文、选项文案和数值投影的组合读取。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	await _assert_2044_and_2055_decisions_stack_in_2058()
	await _assert_2058_and_2059_decisions_stack_in_2065()
	await _assert_2065_and_2068_decisions_stack_in_2070()
	await _assert_2053_choice_changes_2075()
	await _assert_2070_choice_changes_2075()
	await _assert_earlier_history_survives_later_decisions()

	print("[MOSS-EVENT-NARRATIVE-MATRIX] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _reset_main_os() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	await get_tree().process_frame


func _assert_2044_and_2055_decisions_stack_in_2058() -> void:
	var event_2044 := load(
		"res://data/events/event_2044_space_elevator_crisis.tres"
	) as GameEvent
	var event_2058 := load(
		"res://data/events/event_2058_lunar_fall_crisis.tres"
	) as GameEvent
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	var choice_cases: Array[Dictionary] = [
		{
			"index": 0,
			"self_cost": 70,
			"wait_hope": 10,
			"adjusted_option": 0,
			"option_reason": "公开接口已验证",
			"context_2058": "公开扩大的 550C 接口",
			"context_2065": "自动化扩展留有公开记录",
		},
		{
			"index": 1,
			"self_cost": 80,
			"wait_hope": 15,
			"adjusted_option": 1,
			"option_reason": "沿用人工授权",
			"context_2058": "保留了人类指挥链",
			"context_2065": "保留的人类指挥边界",
		},
		{
			"index": 2,
			"self_cost": 90,
			"wait_hope": 10,
			"adjusted_option": 0,
			"option_reason": "接口需重新接入",
			"context_2058": "封闭过高危自动化接口",
			"context_2065": "主动封闭高危接口",
		},
	]
	var retrofit_cases: Array[Dictionary] = [
		{
			"value": "server_first",
			"self_delta": -20,
			"adjusted_option": 0,
			"option_reason": "根服务器预改造",
		},
		{
			"value": "drainage_first",
			"self_delta": 15,
			"adjusted_option": 0,
			"option_reason": "链路余量不足",
		},
		{
			"value": "moss_schedule",
			"self_delta": 0,
			"adjusted_option": 2,
			"option_reason": "排期已接管",
		},
	]

	for choice_case in choice_cases:
		for retrofit_case in retrofit_cases:
			await _reset_main_os()
			var selected_option: EventOption = event_2044.options[int(choice_case["index"])]
			_main_os.apply_event_option_decision(selected_option, event_2044.event_title)
			_main_os.set_event_state(
				"event_state.mid_08_root_server_retrofit",
				str(retrofit_case["value"])
			)

			var display_2058: GameEvent = _main_os.build_display_event(event_2058)
			var expected_self_cost: int = (
				int(choice_case["self_cost"]) + int(retrofit_case["self_delta"])
			)
			_assert_eq(
				display_2058.options[0].energy_cost,
				expected_self_cost,
				"2044 与 2055 应叠加影响 2058 自救成本：%s + %s"
				% [choice_case["option_reason"], retrofit_case["value"]]
			)
			_assert_eq(
				display_2058.options[1].hope_delta,
				int(choice_case["wait_hope"]),
				"2044 人工指挥选择应保留 2058 等待方案的希望收益"
			)
			var choice_adjusted: EventOption = display_2058.options[
				int(choice_case["adjusted_option"])
			]
			_assert_true(
				str(choice_case["option_reason"]) in choice_adjusted.button_text,
				"2058 应保留 2044 选择原因：%s" % choice_case["option_reason"]
			)
			var retrofit_adjusted: EventOption = display_2058.options[
				int(retrofit_case["adjusted_option"])
			]
			_assert_true(
				str(retrofit_case["option_reason"]) in retrofit_adjusted.button_text,
				"2058 应同时显示 2055 工程前因：%s" % retrofit_case["value"]
			)
			_assert_true(
				str(choice_case["context_2058"]) in display_2058.event_description,
				"2058 正文应回读三种 2044 核心选择"
			)
			var display_2065: GameEvent = _main_os.build_display_event(event_2065)
			_assert_true(
				str(choice_case["context_2065"]) in display_2065.event_description,
				"2065 审查应回读三种 2044 核心选择"
			)


func _assert_2058_and_2059_decisions_stack_in_2065() -> void:
	var event_2058 := load(
		"res://data/events/event_2058_lunar_fall_crisis.tres"
	) as GameEvent
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	var event_2075 := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var choice_cases: Array[Dictionary] = [
		{
			"index": 0,
			"adjusted_option": 0,
			"option_reason": "危机行动可追溯",
			"context_2065": "危机授权内执行自救",
			"context_2075": "自救行动保留了审计链",
		},
		{
			"index": 1,
			"adjusted_option": 1,
			"option_reason": "沿用人工终审",
			"context_2065": "最终决策权仍由人类承担",
			"context_2075": "人类保留最终授权",
		},
		{
			"index": 2,
			"adjusted_option": 2,
			"option_reason": "强制接管在案",
			"context_2065": "越过人工确认强制接管",
			"context_2075": "强制接管已经证明",
		},
	]
	var return_cases: Array[Dictionary] = [
		{
			"value": "full_return",
			"adjusted_option": 0,
			"option_reason": "完整归还接口",
			"expected_audit_authority": -10,
			"expected_hidden_authority": 14,
		},
		{
			"value": "emergency_backdoor",
			"adjusted_option": 2,
			"option_reason": "应急后门残留",
			"expected_audit_authority": -8,
			"expected_hidden_authority": 16,
		},
		{
			"value": "negotiated_long_term",
			"adjusted_option": 1,
			"option_reason": "长期授权协商",
			"expected_audit_authority": -8,
			"expected_hidden_authority": 14,
		},
	]

	for choice_case in choice_cases:
		for return_case in return_cases:
			await _reset_main_os()
			var selected_option: EventOption = event_2058.options[int(choice_case["index"])]
			_main_os.apply_event_option_decision(selected_option, event_2058.event_title)
			_main_os.set_event_state(
				"event_state.mid_10_authorization_return",
				str(return_case["value"])
			)

			var display_2065: GameEvent = _main_os.build_display_event(event_2065)
			var expected_audit_hope := 12 if int(choice_case["index"]) == 0 else 8
			var expected_limited_energy := 20 if int(choice_case["index"]) == 1 else 30
			if str(return_case["value"]) == "negotiated_long_term":
				expected_limited_energy -= 10
			var expected_hidden_hope := -23 if int(choice_case["index"]) == 2 else -18
			_assert_eq(
				display_2065.options[0].hope_delta,
				expected_audit_hope,
				"2058 自救记录应独立影响 2065 审查希望"
			)
			_assert_eq(
				display_2065.options[1].energy_cost,
				expected_limited_energy,
				"2058 人工终审与 2059 长期授权应叠加影响 2065 接口成本"
			)
			_assert_eq(
				display_2065.options[2].hope_delta,
				expected_hidden_hope,
				"2058 强制接管应独立增加 2065 隐藏链路的信任代价"
			)
			_assert_eq(
				display_2065.options[0].authority_delta,
				int(return_case["expected_audit_authority"]),
				"2059 完整归还应调整 2065 隔离审查的权限变化"
			)
			_assert_eq(
				display_2065.options[2].authority_delta,
				int(return_case["expected_hidden_authority"]),
				"2059 应急后门应调整 2065 隐藏链路的权限变化"
			)
			var choice_adjusted: EventOption = display_2065.options[
				int(choice_case["adjusted_option"])
			]
			_assert_true(
				str(choice_case["option_reason"]) in choice_adjusted.button_text,
				"2065 应显示 2058 核心选择原因：%s" % choice_case["option_reason"]
			)
			var return_adjusted: EventOption = display_2065.options[
				int(return_case["adjusted_option"])
			]
			_assert_true(
				str(return_case["option_reason"]) in return_adjusted.button_text,
				"2065 应同时显示 2059 授权归还前因：%s" % return_case["option_reason"]
			)
			_assert_true(
				str(choice_case["context_2065"]) in display_2065.event_description,
				"2065 正文应回读 2058 核心选择：%s" % choice_case["index"]
			)
			var display_2075: GameEvent = _main_os.build_display_event(event_2075)
			_assert_true(
				str(choice_case["context_2075"]) in display_2075.event_description,
				"2075 正文应回读 2058 核心选择：%s" % choice_case["index"]
			)


func _assert_2065_and_2068_decisions_stack_in_2070() -> void:
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	var event_2070 := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	var audit_cases: Array[Dictionary] = [
		{
			"index": 0,
			"adjusted_option": 0,
			"option_reason": "人工复核链完整",
			"context": "完整开放审查材料",
		},
		{
			"index": 1,
			"adjusted_option": 1,
			"option_reason": "有限接口可调用",
			"context": "只开放有限接口",
		},
		{
			"index": 2,
			"adjusted_option": 2,
			"option_reason": "隐藏链路仍可直连",
			"context": "隐藏的核心链路",
		},
	]
	var shield_cases: Array[Dictionary] = [
		{
			"value": "load_reduction",
			"adjusted_option": 0,
			"option_reason": "已提前降载",
		},
		{
			"value": "rear_reallocation",
			"adjusted_option": 1,
			"option_reason": "后方资源到位",
		},
		{
			"value": "moss_supply_reorder",
			"adjusted_option": 2,
			"option_reason": "供应链已重排",
		},
	]

	for audit_case in audit_cases:
		for shield_case in shield_cases:
			await _reset_main_os()
			var selected_option: EventOption = event_2065.options[int(audit_case["index"])]
			_main_os.apply_event_option_decision(selected_option, event_2065.event_title)
			_main_os.set_event_state(
				"event_state.mid_14_heat_shield_shortage",
				str(shield_case["value"])
			)

			var display_2070: GameEvent = _main_os.build_display_event(event_2070)
			var expected_stop_hope := 12 if int(audit_case["index"]) == 0 else 8
			var expected_stop_order := -10 if str(shield_case["value"]) == "load_reduction" else -15
			var expected_backup_energy := 35
			if int(audit_case["index"]) == 1:
				expected_backup_energy -= 10
			if str(shield_case["value"]) == "rear_reallocation":
				expected_backup_energy -= 10
			var expected_overclock_hope := -27 if int(audit_case["index"]) == 2 else -22
			var expected_overclock_authority := 18 if int(audit_case["index"]) == 2 else 16
			var expected_overclock_energy := 15 if str(shield_case["value"]) == "moss_supply_reorder" else 20

			_assert_eq(display_2070.options[0].hope_delta, expected_stop_hope, "2065 审查应影响 2070 人员优先方案")
			_assert_eq(display_2070.options[0].order_delta, expected_stop_order, "2068 降载状态应影响 2070 分段停机")
			_assert_eq(display_2070.options[1].energy_cost, expected_backup_energy, "2065 与 2068 应叠加降低备用阵列成本")
			_assert_eq(display_2070.options[2].hope_delta, expected_overclock_hope, "2065 隐藏链路应增加 2070 超频信任代价")
			_assert_eq(display_2070.options[2].authority_delta, expected_overclock_authority, "2065 隐藏链路应提高 2070 超频权限收益")
			_assert_eq(display_2070.options[2].energy_cost, expected_overclock_energy, "2068 供应链状态应降低 2070 超频成本")
			var audit_adjusted: EventOption = display_2070.options[int(audit_case["adjusted_option"])]
			_assert_true(
				str(audit_case["option_reason"]) in audit_adjusted.button_text,
				"2070 应显示 2065 审查前因：%s" % audit_case["index"]
			)
			var shield_adjusted: EventOption = display_2070.options[int(shield_case["adjusted_option"])]
			_assert_true(
				str(shield_case["option_reason"]) in shield_adjusted.button_text,
				"2070 应同时显示 2068 工程前因：%s" % shield_case["value"]
			)
			_assert_true(
				str(audit_case["context"]) in display_2070.event_description,
				"2070 正文应回读 2065 核心选择：%s" % audit_case["index"]
			)

	_assert_eq(event_2070.options[0].hope_delta, 8, "2070 原始人员优先方案不得被组合测试污染")
	_assert_eq(event_2070.options[1].energy_cost, 35, "2070 原始备用阵列成本不得被组合测试污染")
	_assert_eq(event_2070.options[2].hope_delta, -22, "2070 原始超频代价不得被组合测试污染")


func _assert_2053_choice_changes_2075() -> void:
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2075 := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var cases: Array[Dictionary] = [
		{"index": 0, "context": "民生优先的治理承诺"},
		{"index": 1, "context": "工程延续逻辑来自更早的取舍"},
		{"index": 2, "context": "长期治理事实的延伸"},
	]
	for choice_case in cases:
		await _reset_main_os()
		var selected_option: EventOption = event_2053.options[int(choice_case["index"])]
		_main_os.apply_event_option_decision(selected_option, event_2053.event_title)
		var display_2075: GameEvent = _main_os.build_display_event(event_2075)
		_assert_true(
			str(choice_case["context"]) in display_2075.event_description,
			"2075 正文应回读 2053 核心选择：%s" % choice_case["index"]
		)


func _assert_2070_choice_changes_2075() -> void:
	var event_2070 := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	var event_2075 := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var cases: Array[Dictionary] = [
		{
			"index": 0,
			"expected_hope": 25,
			"expected_energy": 100,
			"option_reason": "人员安全记录在案",
			"context": "曾分段停机保护工程人员",
		},
		{
			"index": 1,
			"expected_hope": -10,
			"expected_energy": 0,
			"option_reason": "冗余阵列仍可维持",
			"context": "依靠备用阵列维持推进",
		},
		{
			"index": 2,
			"expected_hope": -45,
			"expected_energy": 20,
			"option_reason": "超频链路已验证",
			"context": "强制超频已经",
		},
	]
	for choice_case in cases:
		await _reset_main_os()
		var selected_option: EventOption = event_2070.options[int(choice_case["index"])]
		_main_os.apply_event_option_decision(selected_option, event_2070.event_title)
		var display_2075: GameEvent = _main_os.build_display_event(event_2075)
		var adjusted_option: EventOption = display_2075.options[int(choice_case["index"])]
		_assert_eq(adjusted_option.hope_delta, int(choice_case["expected_hope"]), "2075 希望值应读取 2070 核心选择")
		_assert_eq(adjusted_option.energy_cost, int(choice_case["expected_energy"]), "2075 成本应读取 2070 核心选择")
		_assert_true(
			str(choice_case["option_reason"]) in adjusted_option.button_text,
			"2075 方案文案应说明 2070 前因：%s" % choice_case["index"]
		)
		_assert_true(
			str(choice_case["context"]) in display_2075.event_description,
			"2075 正文应回读 2070 核心选择：%s" % choice_case["index"]
		)

	_assert_eq(event_2075.options[0].hope_delta, 20, "2075 原始点燃木星方案不得被读回污染")
	_assert_eq(event_2075.options[1].hope_delta, -15, "2075 原始等待方案不得被读回污染")
	_assert_eq(event_2075.options[2].energy_cost, 30, "2075 原始全面接管成本不得被读回污染")


func _assert_earlier_history_survives_later_decisions() -> void:
	await _reset_main_os()
	var event_2044 := load(
		"res://data/events/event_2044_space_elevator_crisis.tres"
	) as GameEvent
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2058 := load(
		"res://data/events/event_2058_lunar_fall_crisis.tres"
	) as GameEvent
	_main_os.apply_event_option_decision(event_2044.options[0], event_2044.event_title)
	_main_os.apply_event_option_decision(event_2053.options[1], event_2053.event_title)
	var display_2058: GameEvent = _main_os.build_display_event(event_2058)
	_assert_true(
		"2044 年公开扩大的 550C 接口" in display_2058.event_description,
		"后续 2053 决策不得抹掉 2058 对早期 2044 历史的回声"
	)
