## 结局历史回顾测试。
## 覆盖五个核心决策的组合解释和全部选项变体，独立于事件正文与档案模态 UI。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

const CORE_ENDING_CASES := [
	{
		"path": "res://data/events/event_2044_space_elevator_crisis.tres",
		"index": 0,
		"expected": "公开扩大的自动化接口",
	},
	{
		"path": "res://data/events/event_2044_space_elevator_crisis.tres",
		"index": 1,
		"expected": "保留的人类指挥链",
	},
	{
		"path": "res://data/events/event_2044_space_elevator_crisis.tres",
		"index": 2,
		"expected": "封闭高危接口换取",
	},
	{
		"path": "res://data/events/event_2053_great_flood_accident.tres",
		"index": 0,
		"expected": "优先撤离人口的记录",
	},
	{
		"path": "res://data/events/event_2053_great_flood_accident.tres",
		"index": 1,
		"expected": "坚守基础设施的记录",
	},
	{
		"path": "res://data/events/event_2053_great_flood_accident.tres",
		"index": 2,
		"expected": "牺牲外围的记录",
	},
	{
		"path": "res://data/events/event_2058_lunar_fall_crisis.tres",
		"index": 0,
		"expected": "危机授权内的自救行动",
	},
	{
		"path": "res://data/events/event_2058_lunar_fall_crisis.tres",
		"index": 1,
		"expected": "人类保留最终授权",
	},
	{
		"path": "res://data/events/event_2058_lunar_fall_crisis.tres",
		"index": 2,
		"expected": "越过人工确认强制接管",
	},
	{
		"path": "res://data/events/event_2065_ai_isolation_audit.tres",
		"index": 0,
		"expected": "完整接受隔离审查",
	},
	{
		"path": "res://data/events/event_2065_ai_isolation_audit.tres",
		"index": 1,
		"expected": "只披露有限接口",
	},
	{
		"path": "res://data/events/event_2065_ai_isolation_audit.tres",
		"index": 2,
		"expected": "隐藏核心链路",
	},
	{
		"path": "res://data/events/event_2070_siberian_engine_overload.tres",
		"index": 0,
		"expected": "分段停机优先保护工程人员",
	},
	{
		"path": "res://data/events/event_2070_siberian_engine_overload.tres",
		"index": 1,
		"expected": "备用阵列以额外能源",
	},
	{
		"path": "res://data/events/event_2070_siberian_engine_overload.tres",
		"index": 2,
		"expected": "强制超频以人员和设备余量",
	},
]

var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	await _assert_all_core_decisions_stack_in_ending()
	await _assert_core_decision_variants()

	print("[MOSS-ENDING-HISTORY] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _reset_main_os() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	await get_tree().process_frame


func _assert_all_core_decisions_stack_in_ending() -> void:
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

	_assert_eq(_main_os.get_decision_records().size(), 5, "五个核心年份应各自形成独立档案记录")
	var ending_text: String = _main_os.build_ending_message("coexistence")
	_assert_true("2044 年公开扩大的自动化接口" in ending_text, "结局应同时回读 2044 核心选择")
	_assert_true("坚守基础设施的记录" in ending_text, "结局应同时回读 2053 核心选择，不被 2044 覆盖")
	_assert_true("2058 年 MOSS 曾越过人工确认强制接管" in ending_text, "结局应同时回读 2058 核心选择，不覆盖更早标签")
	_assert_true("2065 年隐藏核心链路" in ending_text, "结局应同时回读 2065 核心选择，不覆盖更早标签")
	_assert_true("2070 年备用阵列" in ending_text, "结局应同时回读 2070 核心选择，不覆盖更早标签")


func _assert_core_decision_variants() -> void:
	for case_value in CORE_ENDING_CASES:
		var ending_case: Dictionary = case_value
		await _reset_main_os()
		var event := load(str(ending_case["path"])) as GameEvent
		_assert_true(event != null, "结局变体事件应能加载：%s" % ending_case["path"])
		if event == null:
			continue
		_main_os.apply_event_option_decision(
			event.options[int(ending_case["index"])],
			event.event_title
		)
		var ending_text: String = _main_os.build_ending_message("coexistence")
		_assert_true(
			str(ending_case["expected"]) in ending_text,
			"结局应回读核心决策变体：%s / %s" % [event.event_id, ending_case["index"]]
		)
