## 核心决策历史纵向切片测试
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const DECISION_HISTORY_SCRIPT := preload("res://scripts/systems/decision_history.gd")

var _failed: int = 0
var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	var serialized_panel := _main_os.get_node("%DecisionArchivePanel") as DecisionArchivePanel
	var serialized_button := _main_os.get_node("%DecisionArchiveButton") as Button
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
	_assert_2044_and_2055_decisions_stack_in_2058()
	_assert_2044_choice_changes_2058_and_ending()
	await _assert_archive_ui_reads_stable_records()
	_assert_restart_clears_history()

	print("[MOSS-DECISION-HISTORY] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_empty_archive_state() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	var button := _main_os.get_node("%DecisionArchiveButton") as Button
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
	_assert_eq(_main_os.get_decision_records().size(), 0, "重新开始应清空决策档案")
	_assert_true("0" in _main_os.get_node("%DecisionArchiveButton").text, "重开后档案按钮应归零")


func _assert_archive_ui_reads_stable_records() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	var button := _main_os.get_node("%DecisionArchiveButton") as Button
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
