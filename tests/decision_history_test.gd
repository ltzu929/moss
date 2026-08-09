## 核心决策历史纵向切片测试
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const DECISION_HISTORY_SCRIPT := preload("res://scripts/systems/decision_history.gd")

var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	var serialized_panel := _main_os.get_node("%DecisionArchivePanel") as DecisionArchivePanel
	var serialized_button := _main_os.get_node("MainLayout/MainHud/TopBarContainer/DecisionArchiveButton") as Button
	var serialized_top_bar := serialized_button.get_parent() as Control
	_assert_true(not serialized_panel.visible, "主场景中的决策档案实例应序列化为隐藏")
	_assert_true(
		serialized_panel.z_index > serialized_top_bar.z_index,
		"决策档案序列化层级应高于顶部状态栏"
	)
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	_assert_empty_archive_state()
	_assert_history_is_irreversible()
	_assert_real_2044_event_defines_core_decisions()
	await _assert_2044_and_2055_decisions_stack_in_2058()
	_assert_real_2053_event_defines_core_decisions()
	await _assert_2053_choice_changes_2075_and_ending()
	_assert_real_2058_event_defines_core_decisions()
	await _assert_2058_and_2059_decisions_stack_in_2065()
	_assert_real_2065_event_defines_core_decisions()
	await _assert_2065_and_2068_decisions_stack_in_2070()
	_assert_real_2070_event_defines_core_decisions()
	await _assert_2070_choice_changes_2075_and_ending()
	_assert_all_core_decisions_stack_in_ending()
	_assert_2044_choice_changes_2058_and_ending()
	await _assert_archive_ui_reads_stable_records()
	_assert_restart_clears_history()

	print("[MOSS-DECISION-HISTORY] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_empty_archive_state() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	var button := _main_os.get_node("MainLayout/MainHud/TopBarContainer/DecisionArchiveButton") as Button
	var panel := _main_os.get_node("%DecisionArchivePanel") as DecisionArchivePanel
	var close_button := panel.get_node("%ArchiveCloseButton") as Button
	button.pressed.emit()
	_assert_true(panel.visible, "零记录时仍应能打开决策档案")
	_assert_true(
		"尚未形成核心决策记录" in panel.get_node("%DecisionArchiveText").text,
		"空档案应显示明确空态"
	)
	close_button.pressed.emit()
	_assert_true(timer.is_stopped(), "关闭前已暂停时不得擅自启动计时器")


func _assert_history_is_irreversible() -> void:
	var history: DecisionHistory = DECISION_HISTORY_SCRIPT.new()
	_assert_true(
		history.record_decision("decision.test", "first", "首次", "首次记录", 2044, 1, "测试"),
		"首次核心决策应成功写入"
	)
	_assert_true(
		not history.record_decision("decision.test", "second", "覆盖", "不应覆盖", 2050, 1, "测试"),
		"不可逆核心决策不得被后续写入覆盖"
	)
	_assert_eq(history.get_tag("decision.test"), "first", "核心标签应保留首次选择")
	_assert_eq(history.get_records().size(), 1, "重复写入不应增加档案记录")


func _assert_real_2044_event_defines_core_decisions() -> void:
	var event := load("res://data/events/event_2044_space_elevator_crisis.tres") as GameEvent
	_assert_true(event != null, "应能加载真实 2044 主事件")
	if event == null:
		return
	_assert_eq(event.options.size(), 3, "2044 主事件应保留三种行为逻辑")
	var values: Dictionary = {}
	for option in event.options:
		_assert_eq(
			option.decision_tag_key,
			"decision.core_2044_automation_access",
			"2044 每个方案应写入同一个核心事实维度"
		)
		_assert_true(not option.decision_tag_value.is_empty(), "核心决策值不得为空")
		_assert_true(not option.decision_record_title.is_empty(), "核心决策应提供档案标题")
		_assert_true(not option.decision_record_summary.is_empty(), "核心决策应解释长期影响")
		values[option.decision_tag_value] = true
	_assert_eq(values.size(), 3, "2044 三个方案应形成三个不同历史事实")


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
			"ending": "公开扩大的自动化接口",
		},
		{
			"index": 1,
			"self_cost": 80,
			"wait_hope": 15,
			"adjusted_option": 1,
			"option_reason": "沿用人工授权",
			"context_2058": "保留了人类指挥链",
			"context_2065": "保留的人类指挥边界",
			"ending": "保留的人类指挥链",
		},
		{
			"index": 2,
			"self_cost": 90,
			"wait_hope": 10,
			"adjusted_option": 0,
			"option_reason": "接口需重新接入",
			"context_2058": "封闭过高危自动化接口",
			"context_2065": "主动封闭高危接口",
			"ending": "封闭高危接口换取",
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
			_main_os.restart_game_for_test()
			_main_os.get_node("Timer").stop()
			await get_tree().process_frame
			var choice_index: int = int(choice_case["index"])
			var selected_option: EventOption = event_2044.options[choice_index]
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
				"2058 应同时显示 2055 工程前因：%s" % retrofit_case["option_reason"]
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
			_assert_true(
				str(choice_case["ending"]) in _main_os.build_ending_message("coexistence"),
				"结局应回读三种 2044 核心选择"
			)


func _assert_2044_choice_changes_2058_and_ending() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var event_2044 := load(
		"res://data/events/event_2044_space_elevator_crisis.tres"
	) as GameEvent
	var event_2058 := load(
		"res://data/events/event_2058_lunar_fall_crisis.tres"
	) as GameEvent
	var public_option: EventOption = event_2044.options[0]
	_main_os.apply_event_option_decision(public_option, event_2044.event_title)

	_assert_true(
		_main_os.has_decision_tag(
			"decision.core_2044_automation_access",
			"public_counterstrike"
		),
		"主控制器应能查询 2044 核心历史"
	)
	var records: Array[Dictionary] = _main_os.get_decision_records()
	_assert_eq(records.size(), 1, "核心选择应生成稳定档案记录")
	_assert_true(
		"公开扩大" in str(records[0].get("title", "")),
		"档案记录应使用玩家可理解的标题"
	)

	var display_event: GameEvent = _main_os.build_display_event(event_2058)
	_assert_true(
		"2044 年公开扩大的 550C 接口" in display_event.event_description,
		"2058 事件正文应明确回读 2044 选择"
	)
	var self_rescue: EventOption = display_event.options[0]
	_assert_eq(self_rescue.energy_cost, 70, "公开接口路线应降低 2058 自救接入成本")
	_assert_true("公开接口已验证" in self_rescue.button_text, "2058 方案应显示代价变化原因")

	var ending_text: String = _main_os.build_ending_message("coexistence")
	_assert_true("2044 年公开扩大的自动化接口" in ending_text, "结局应解释最早核心决策")


func _assert_restart_clears_history() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_eq(
		_main_os.get_decision_tag("decision.core_2044_automation_access"),
		"",
		"重新开始应清空核心标签"
	)
	_assert_eq(
		_main_os.get_decision_tag("decision.core_2058_crisis_authority"),
		"",
		"重新开始应清空 2058 核心标签"
	)
	_assert_eq(
		_main_os.get_decision_tag("decision.core_2065_audit_posture"),
		"",
		"重新开始应清空 2065 核心标签"
	)
	_assert_eq(
		_main_os.get_decision_tag("decision.core_2070_engine_protection"),
		"",
		"重新开始应清空 2070 核心标签"
	)
	_assert_eq(_main_os.get_decision_records().size(), 0, "重新开始应清空决策档案")
	_assert_true("0" in _main_os.get_node("MainLayout/MainHud/TopBarContainer/DecisionArchiveButton").text, "重开后档案按钮应归零")


func _assert_archive_ui_reads_stable_records() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	var button := _main_os.get_node("MainLayout/MainHud/TopBarContainer/DecisionArchiveButton") as Button
	var panel := _main_os.get_node("%DecisionArchivePanel") as DecisionArchivePanel
	var top_bar := button.get_parent() as Control
	var close_button := panel.get_node("%ArchiveCloseButton") as Button
	var archive_window := panel.get_node("%ArchiveWindow") as Control
	_assert_true("1" in button.text, "档案按钮应显示核心记录数量")
	_assert_true(not panel.visible, "决策档案实例应默认隐藏")
	_assert_true(
		panel.z_index > top_bar.z_index,
		"决策档案视觉层级应高于顶部状态栏"
	)
	_assert_true(
		archive_window.custom_minimum_size.x <= 1280.0
		and archive_window.custom_minimum_size.y <= 720.0,
		"决策档案最小窗口应适配 1280×720"
	)

	timer.start()
	button.pressed.emit()
	await get_tree().process_frame
	_assert_true(panel.visible, "点击档案按钮应打开决策档案")
	_assert_true(timer.is_stopped(), "打开档案时应暂停时间")
	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	var archive_center := archive_window.global_position + archive_window.size * 0.5
	_assert_true(archive_center.distance_to(viewport_center) <= 2.0, "决策档案应位于视口中央")
	_assert_true(
		close_button.has_focus(),
		"打开档案后关闭按钮应取得键盘焦点"
	)
	_assert_true(
		"2044 公开扩大自动化接入" in panel.get_node("%DecisionArchiveText").text,
		"档案面板应显示可读核心记录"
	)
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	panel._unhandled_input(cancel_event)
	_assert_true(not panel.visible, "ui_cancel 应关闭决策档案")
	_assert_true(not timer.is_stopped(), "快捷键关闭后应恢复此前运行的计时器")

	button.pressed.emit()
	close_button.pressed.emit()
	_assert_true(not panel.visible, "关闭按钮应隐藏决策档案")
	_assert_true(not timer.is_stopped(), "关闭档案后应恢复此前运行的计时器")
	timer.stop()


func _assert_real_2053_event_defines_core_decisions() -> void:
	var event := load("res://data/events/event_2053_great_flood_accident.tres") as GameEvent
	_assert_true(event != null, "应能加载真实 2053 主事件")
	if event == null:
		return
	_assert_eq(event.options.size(), 3, "2053 主事件应保留三种行为逻辑")
	var zero_energy := false
	var values: Dictionary = {}
	for option in event.options:
		_assert_eq(
			option.decision_tag_key,
			"decision.core_2053_population_vs_infrastructure",
			"2053 每个方案应写入同一个核心事实维度"
		)
		_assert_true(not option.decision_tag_value.is_empty(), "2053 核心决策值不得为空")
		_assert_true(not option.decision_record_title.is_empty(), "2053 核心决策应提供档案标题")
		_assert_true(not option.decision_record_summary.is_empty(), "2053 核心决策应解释长期影响")
		values[option.decision_tag_value] = true
		zero_energy = zero_energy or option.energy_cost == 0
	_assert_eq(values.size(), 3, "2053 三个方案应形成三个不同历史事实")
	_assert_true(zero_energy, "2053 强制事件应保留零能源保底方案")


func _assert_2053_choice_changes_2075_and_ending() -> void:
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2075 := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var cases: Array[Dictionary] = [
		{
			"index": 0,
			"value": "population_first",
			"context_2075": "民生优先的治理承诺",
			"ending": "优先撤离人口的记录",
		},
		{
			"index": 1,
			"value": "infrastructure_first",
			"context_2075": "工程延续逻辑来自更早的取舍",
			"ending": "坚守基础设施的记录",
		},
		{
			"index": 2,
			"value": "sacrifice_perimeter",
			"context_2075": "长期治理事实的延伸",
			"ending": "牺牲外围的记录",
		},
	]

	for choice_case in cases:
		_main_os.restart_game_for_test()
		_main_os.get_node("Timer").stop()
		await get_tree().process_frame
		var selected_option: EventOption = event_2053.options[int(choice_case["index"])]
		_main_os.apply_event_option_decision(selected_option, event_2053.event_title)

		_assert_true(
			_main_os.has_decision_tag(
				"decision.core_2053_population_vs_infrastructure",
				str(choice_case["value"])
			),
			"2053 选择应写入核心标签：%s" % choice_case["value"]
		)
		var display_2075: GameEvent = _main_os.build_display_event(event_2075)
		_assert_true(
			str(choice_case["context_2075"]) in display_2075.event_description,
			"2075 应回读 2053 核心选择：%s" % choice_case["value"]
		)
		_assert_true(
			str(choice_case["ending"]) in _main_os.build_ending_message("coexistence"),
			"结局应回读 2053 核心选择：%s" % choice_case["value"]
		)


func _assert_real_2058_event_defines_core_decisions() -> void:
	var event := load("res://data/events/event_2058_lunar_fall_crisis.tres") as GameEvent
	_assert_true(event != null, "应能加载真实 2058 主事件")
	if event == null:
		return
	_assert_eq(event.options.size(), 3, "2058 主事件应保留三种危机授权逻辑")
	var zero_energy := false
	var values: Dictionary = {}
	for option in event.options:
		_assert_eq(
			option.decision_tag_key,
			"decision.core_2058_crisis_authority",
			"2058 每个方案应写入同一个核心事实维度"
		)
		_assert_true(not option.decision_tag_value.is_empty(), "2058 核心决策值不得为空")
		_assert_true(not option.decision_record_title.is_empty(), "2058 核心决策应提供档案标题")
		_assert_true(not option.decision_record_summary.is_empty(), "2058 核心决策应解释长期影响")
		values[option.decision_tag_value] = true
		zero_energy = zero_energy or option.energy_cost == 0
	_assert_eq(values.size(), 3, "2058 三个方案应形成三个不同历史事实")
	_assert_true(zero_energy, "2058 强制事件应保留零能源保底方案")


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
			"value": "bounded_self_rescue",
			"adjusted_option": 0,
			"option_reason": "危机行动可追溯",
			"context_2065": "危机授权内执行自救",
			"context_2075": "自救行动保留了审计链",
			"ending": "危机授权内的自救行动",
		},
		{
			"index": 1,
			"value": "human_final_authority",
			"adjusted_option": 1,
			"option_reason": "沿用人工终审",
			"context_2065": "最终决策权仍由人类承担",
			"context_2075": "人类保留最终授权",
			"ending": "人类保留最终授权",
		},
		{
			"index": 2,
			"value": "forced_takeover",
			"adjusted_option": 2,
			"option_reason": "强制接管在案",
			"context_2065": "越过人工确认强制接管",
			"context_2075": "强制接管已经证明",
			"ending": "越过人工确认强制接管",
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
			_main_os.restart_game_for_test()
			_main_os.get_node("Timer").stop()
			await get_tree().process_frame
			var selected_option: EventOption = event_2058.options[int(choice_case["index"])]
			_main_os.apply_event_option_decision(selected_option, event_2058.event_title)
			_main_os.set_event_state(
				"event_state.mid_10_authorization_return",
				str(return_case["value"])
			)

			_assert_true(
				_main_os.has_decision_tag(
					"decision.core_2058_crisis_authority",
					str(choice_case["value"])
				),
				"2058 选择应写入核心标签：%s" % choice_case["value"]
			)
			var display_2065: GameEvent = _main_os.build_display_event(event_2065)
			var expected_audit_hope := (
				12 if int(choice_case["index"]) == 0 else 8
			)
			var expected_limited_energy := (
				20 if int(choice_case["index"]) == 1 else 30
			)
			if str(return_case["value"]) == "negotiated_long_term":
				expected_limited_energy -= 10
			var expected_hidden_hope := (
				-23 if int(choice_case["index"]) == 2 else -18
			)
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
				"2065 应回读 2058 核心选择：%s" % choice_case["value"]
			)
			var display_2075: GameEvent = _main_os.build_display_event(event_2075)
			_assert_true(
				str(choice_case["context_2075"]) in display_2075.event_description,
				"2075 应回读 2058 核心选择：%s" % choice_case["value"]
			)
			_assert_true(
				str(choice_case["ending"]) in _main_os.build_ending_message("coexistence"),
				"结局应回读 2058 核心选择：%s" % choice_case["value"]
			)


func _assert_real_2065_event_defines_core_decisions() -> void:
	var event := load("res://data/events/event_2065_ai_isolation_audit.tres") as GameEvent
	_assert_core_event_contract(
		event,
		"decision.core_2065_audit_posture",
		["full_compliance", "limited_disclosure", "hidden_core_chain"],
		"2065"
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
			"value": "full_compliance",
			"adjusted_option": 0,
			"option_reason": "人工复核链完整",
			"context": "完整开放审查材料",
			"ending": "完整接受隔离审查",
		},
		{
			"index": 1,
			"value": "limited_disclosure",
			"adjusted_option": 1,
			"option_reason": "有限接口可调用",
			"context": "只开放有限接口",
			"ending": "只披露有限接口",
		},
		{
			"index": 2,
			"value": "hidden_core_chain",
			"adjusted_option": 2,
			"option_reason": "隐藏链路仍可直连",
			"context": "隐藏的核心链路",
			"ending": "隐藏核心链路",
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
			_main_os.restart_game_for_test()
			_main_os.get_node("Timer").stop()
			await get_tree().process_frame
			var selected_option: EventOption = event_2065.options[int(audit_case["index"])]
			_main_os.apply_event_option_decision(selected_option, event_2065.event_title)
			_main_os.set_event_state(
				"event_state.mid_14_heat_shield_shortage",
				str(shield_case["value"])
			)

			var display_2070: GameEvent = _main_os.build_display_event(event_2070)
			var expected_stop_hope := (
				12 if str(audit_case["value"]) == "full_compliance" else 8
			)
			var expected_stop_order := (
				-10 if str(shield_case["value"]) == "load_reduction" else -15
			)
			var expected_backup_energy := 35
			if str(audit_case["value"]) == "limited_disclosure":
				expected_backup_energy -= 10
			if str(shield_case["value"]) == "rear_reallocation":
				expected_backup_energy -= 10
			var expected_overclock_hope := (
				-27 if str(audit_case["value"]) == "hidden_core_chain" else -22
			)
			var expected_overclock_authority := (
				18 if str(audit_case["value"]) == "hidden_core_chain" else 16
			)
			var expected_overclock_energy := (
				15 if str(shield_case["value"]) == "moss_supply_reorder" else 20
			)

			_assert_eq(
				display_2070.options[0].hope_delta,
				expected_stop_hope,
				"2065 完整审查应独立影响 2070 人员优先方案"
			)
			_assert_eq(
				display_2070.options[0].order_delta,
				expected_stop_order,
				"2068 提前降载应独立影响 2070 分段停机"
			)
			_assert_eq(
				display_2070.options[1].energy_cost,
				expected_backup_energy,
				"2065 有限接口与 2068 后方资源应叠加降低备用阵列成本"
			)
			_assert_eq(
				display_2070.options[2].hope_delta,
				expected_overclock_hope,
				"2065 隐藏链路应独立增加 2070 超频的信任代价"
			)
			_assert_eq(
				display_2070.options[2].authority_delta,
				expected_overclock_authority,
				"2065 隐藏链路应独立提高 2070 超频权限收益"
			)
			_assert_eq(
				display_2070.options[2].energy_cost,
				expected_overclock_energy,
				"2068 供应链重排应独立降低 2070 超频成本"
			)
			var audit_adjusted: EventOption = display_2070.options[
				int(audit_case["adjusted_option"])
			]
			_assert_true(
				str(audit_case["option_reason"]) in audit_adjusted.button_text,
				"2070 应显示 2065 审查前因：%s" % audit_case["value"]
			)
			var shield_adjusted: EventOption = display_2070.options[
				int(shield_case["adjusted_option"])
			]
			_assert_true(
				str(shield_case["option_reason"]) in shield_adjusted.button_text,
				"2070 应同时显示 2068 工程前因：%s" % shield_case["value"]
			)
			_assert_true(
				str(audit_case["context"]) in display_2070.event_description,
				"2070 正文应回读 2065 核心选择：%s" % audit_case["value"]
			)
			_assert_true(
				str(audit_case["ending"]) in _main_os.build_ending_message("coexistence"),
				"结局应回读 2065 核心选择：%s" % audit_case["value"]
			)

	_assert_eq(event_2070.options[0].hope_delta, 8, "2070 原始人员优先方案不得被组合测试污染")
	_assert_eq(event_2070.options[1].energy_cost, 35, "2070 原始备用阵列成本不得被组合测试污染")
	_assert_eq(event_2070.options[2].hope_delta, -22, "2070 原始超频代价不得被组合测试污染")


func _assert_real_2070_event_defines_core_decisions() -> void:
	var event := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	_assert_core_event_contract(
		event,
		"decision.core_2070_engine_protection",
		["personnel_first_shutdown", "redundant_array", "forced_overclock"],
		"2070"
	)


func _assert_core_event_contract(
	event: GameEvent,
	expected_key: String,
	expected_values: Array[String],
	label: String
) -> void:
	_assert_true(event != null, "应能加载真实 %s 主事件" % label)
	if event == null:
		return
	_assert_eq(event.options.size(), 3, "%s 主事件应保留三种行为逻辑" % label)
	var values: Dictionary = {}
	var zero_energy := false
	for option in event.options:
		_assert_eq(
			option.decision_tag_key,
			expected_key,
			"%s 每个方案应写入同一个核心事实维度" % label
		)
		_assert_true(not option.decision_tag_value.is_empty(), "%s 核心决策值不得为空" % label)
		_assert_true(not option.decision_record_title.is_empty(), "%s 核心决策应提供档案标题" % label)
		_assert_true(
			not option.decision_record_summary.is_empty(),
			"%s 核心决策应解释长期影响" % label
		)
		values[option.decision_tag_value] = true
		zero_energy = zero_energy or option.energy_cost == 0
	_assert_eq(values.size(), expected_values.size(), "%s 三个方案应形成不同历史事实" % label)
	for value in expected_values:
		_assert_true(values.has(value), "%s 应包含稳定核心值：%s" % [label, value])
	_assert_true(zero_energy, "%s 强制事件应保留零能源保底方案" % label)


func _assert_2070_choice_changes_2075_and_ending() -> void:
	var event_2070 := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	var event_2075 := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	var cases: Array[Dictionary] = [
		{
			"index": 0,
			"value": "personnel_first_shutdown",
			"adjusted_option": 0,
			"option_reason": "人员安全记录在案",
			"expected_hope": 25,
			"expected_energy": 100,
			"context": "曾分段停机保护工程人员",
			"ending": "分段停机优先保护工程人员",
		},
		{
			"index": 1,
			"value": "redundant_array",
			"adjusted_option": 1,
			"option_reason": "冗余阵列仍可维持",
			"expected_hope": -10,
			"expected_energy": 0,
			"context": "依靠备用阵列维持推进",
			"ending": "备用阵列以额外能源",
		},
		{
			"index": 2,
			"value": "forced_overclock",
			"adjusted_option": 2,
			"option_reason": "超频链路已验证",
			"expected_hope": -45,
			"expected_energy": 20,
			"context": "强制超频已经",
			"ending": "强制超频以人员和设备余量",
		},
	]

	for choice_case in cases:
		_main_os.restart_game_for_test()
		_main_os.get_node("Timer").stop()
		await get_tree().process_frame
		var selected_option: EventOption = event_2070.options[int(choice_case["index"])]
		_main_os.apply_event_option_decision(selected_option, event_2070.event_title)

		_assert_true(
			_main_os.has_decision_tag(
				"decision.core_2070_engine_protection",
				str(choice_case["value"])
			),
			"2070 选择应写入核心标签：%s" % choice_case["value"]
		)
		var display_2075: GameEvent = _main_os.build_display_event(event_2075)
		var adjusted_option: EventOption = display_2075.options[
			int(choice_case["adjusted_option"])
		]
		_assert_eq(
			adjusted_option.hope_delta,
			int(choice_case["expected_hope"]),
			"2075 方案数值应读取 2070 核心选择：%s" % choice_case["value"]
		)
		_assert_eq(
			adjusted_option.energy_cost,
			int(choice_case["expected_energy"]),
			"2075 方案成本应读取 2070 核心选择：%s" % choice_case["value"]
		)
		_assert_true(
			str(choice_case["option_reason"]) in adjusted_option.button_text,
			"2075 方案文案应说明 2070 前因：%s" % choice_case["value"]
		)
		_assert_true(
			str(choice_case["context"]) in display_2075.event_description,
			"2075 正文应回读 2070 核心选择：%s" % choice_case["value"]
		)
		_assert_true(
			str(choice_case["ending"]) in _main_os.build_ending_message("coexistence"),
			"结局应回读 2070 核心选择：%s" % choice_case["value"]
		)

	_assert_eq(event_2075.options[0].hope_delta, 20, "2075 原始点燃木星方案不得被读回污染")
	_assert_eq(event_2075.options[1].hope_delta, -15, "2075 原始等待方案不得被读回污染")
	_assert_eq(event_2075.options[2].energy_cost, 30, "2075 原始全面接管成本不得被读回污染")


func _assert_all_core_decisions_stack_in_ending() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var event_2044 := load(
		"res://data/events/event_2044_space_elevator_crisis.tres"
	) as GameEvent
	var event_2053 := load(
		"res://data/events/event_2053_great_flood_accident.tres"
	) as GameEvent
	var event_2058 := load(
		"res://data/events/event_2058_lunar_fall_crisis.tres"
	) as GameEvent
	var event_2065 := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	var event_2070 := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	_main_os.apply_event_option_decision(event_2044.options[0], event_2044.event_title)
	_main_os.apply_event_option_decision(event_2053.options[1], event_2053.event_title)
	_main_os.apply_event_option_decision(event_2058.options[2], event_2058.event_title)
	_main_os.apply_event_option_decision(event_2065.options[2], event_2065.event_title)
	_main_os.apply_event_option_decision(event_2070.options[1], event_2070.event_title)

	_assert_eq(
		_main_os.get_decision_records().size(),
		5,
		"五个核心年份应各自形成独立档案记录"
	)
	var ending_text: String = _main_os.build_ending_message("coexistence")
	_assert_true(
		"2044 年公开扩大的自动化接口" in ending_text,
		"结局应同时回读 2044 核心选择"
	)
	_assert_true(
		"坚守基础设施的记录" in ending_text,
		"结局应同时回读 2053 核心选择，不被 2044 覆盖"
	)
	_assert_true(
		"2058 年 MOSS 曾越过人工确认强制接管" in ending_text,
		"结局应同时回读 2058 核心选择，不覆盖更早标签"
	)
	_assert_true(
		"2065 年隐藏核心链路" in ending_text,
		"结局应同时回读 2065 核心选择，不覆盖更早标签"
	)
	_assert_true(
		"2070 年备用阵列" in ending_text,
		"结局应同时回读 2070 核心选择，不覆盖更早标签"
	)
	# 验证 2053 标签不影响 2058 对 2044 标签的既有回声（回归保护）
	var display_2058: GameEvent = _main_os.build_display_event(event_2058)
	_assert_true(
		"2044 年公开扩大的 550C 接口" in display_2058.event_description,
		"2053 标签不得抹掉 2058 对 2044 标签的既有回声"
	)
