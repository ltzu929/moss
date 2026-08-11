## 核心决策历史存储测试。
## 验证真实主事件资源、不可逆写入、档案记录和重开清理，不包含 UI 展示断言。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const DECISION_HISTORY_SCRIPT := preload("res://scripts/systems/decision_history.gd")

const CORE_EVENT_CASES := [
	{
		"path": "res://data/events/event_2044_space_elevator_crisis.tres",
		"key": "decision.core_2044_automation_access",
		"values": ["public_counterstrike", "human_command", "restricted_interface"],
	},
	{
		"path": "res://data/events/event_2053_great_flood_accident.tres",
		"key": "decision.core_2053_population_vs_infrastructure",
		"values": ["population_first", "infrastructure_first", "sacrifice_perimeter"],
	},
	{
		"path": "res://data/events/event_2058_lunar_fall_crisis.tres",
		"key": "decision.core_2058_crisis_authority",
		"values": ["bounded_self_rescue", "human_final_authority", "forced_takeover"],
	},
	{
		"path": "res://data/events/event_2065_ai_isolation_audit.tres",
		"key": "decision.core_2065_audit_posture",
		"values": ["full_compliance", "limited_disclosure", "hidden_core_chain"],
	},
	{
		"path": "res://data/events/event_2070_siberian_engine_overload.tres",
		"key": "decision.core_2070_engine_protection",
		"values": ["personnel_first_shutdown", "redundant_array", "forced_overclock"],
	},
]

var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	_assert_core_event_contracts()
	_assert_history_is_irreversible()
	_assert_main_os_records_first_write()
	_assert_restart_clears_history()

	print("[MOSS-DECISION-HISTORY-STORE] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _assert_core_event_contracts() -> void:
	for event_case_value in CORE_EVENT_CASES:
		var event_case: Dictionary = event_case_value
		var event := load(str(event_case["path"])) as GameEvent
		_assert_true(event != null, "核心决策事件应能加载：%s" % event_case["path"])
		if event == null:
			continue
		_assert_eq(event.options.size(), 3, "核心决策事件应保留三个方案：%s" % event.event_id)
		var values: Dictionary = {}
		var has_zero_energy := false
		for option in event.options:
			_assert_eq(
				option.decision_tag_key,
				str(event_case["key"]),
				"核心事件的三个方案应写入同一历史维度：%s" % event.event_id
			)
			_assert_true(not option.decision_tag_value.is_empty(), "核心决策值不得为空：%s" % event.event_id)
			_assert_true(not option.decision_record_title.is_empty(), "核心决策应提供档案标题：%s" % event.event_id)
			_assert_true(not option.decision_record_summary.is_empty(), "核心决策应提供档案摘要：%s" % event.event_id)
			values[option.decision_tag_value] = true
			has_zero_energy = has_zero_energy or option.energy_cost == 0
		_assert_eq(values.size(), 3, "核心事件应形成三个不同历史事实：%s" % event.event_id)
		for expected_value in event_case["values"]:
			_assert_true(values.has(expected_value), "核心事件应包含稳定历史值：%s" % expected_value)
		_assert_true(has_zero_energy, "强制核心事件应保留零能源保底方案：%s" % event.event_id)


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


func _assert_main_os_records_first_write() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var event := load("res://data/events/event_2044_space_elevator_crisis.tres") as GameEvent
	_main_os.apply_event_option_decision(event.options[0], event.event_title)
	_assert_true(
		_main_os.has_decision_tag("decision.core_2044_automation_access", "public_counterstrike"),
		"主场景应通过公开入口写入核心历史标签"
	)
	_assert_eq(_main_os.get_decision_records().size(), 1, "首次核心选择应生成一条档案记录")
	_assert_true(
		"公开扩大" in str(_main_os.get_decision_records()[0].get("title", "")),
		"档案记录应保留玩家可理解的标题"
	)
	_main_os.apply_event_option_decision(event.options[1], event.event_title)
	_assert_eq(
		_main_os.get_decision_tag("decision.core_2044_automation_access"),
		"public_counterstrike",
		"同一核心维度的后续选择不得覆盖首次标签"
	)
	_assert_eq(_main_os.get_decision_records().size(), 1, "重复核心选择不得增加档案记录")


func _assert_restart_clears_history() -> void:
	var event := load("res://data/events/event_2044_space_elevator_crisis.tres") as GameEvent
	_main_os.apply_event_option_decision(event.options[0], event.event_title)
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	for key in [
		"decision.core_2044_automation_access",
		"decision.core_2053_population_vs_infrastructure",
		"decision.core_2058_crisis_authority",
		"decision.core_2065_audit_posture",
		"decision.core_2070_engine_protection",
	]:
		_assert_eq(_main_os.get_decision_tag(key), "", "重开应清空核心标签：%s" % key)
	_assert_eq(_main_os.get_decision_records().size(), 0, "重开应清空不可逆档案记录")
