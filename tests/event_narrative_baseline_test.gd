## 事件叙事基线测试。
## 逐字段、逐字比对真实事件资源的拆分前玩家可见文本。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const BASELINE_PATH := "res://tests/fixtures/event_narrative_baseline.json"

var _main_os: Control
var _baseline: Dictionary


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()
	_baseline = _load_baseline()

	_assert_eq(
		_baseline.get("schema_version", 0),
		1,
		"事件叙事基线 schema 版本应匹配"
	)
	_assert_eq(
		(_baseline.get("events", []) as Array).size(),
		25,
		"事件叙事基线应覆盖 25 个真实事件"
	)
	_assert_base_event_texts()
	_assert_history_case_texts()

	print("[MOSS-EVENT-NARRATIVE-BASELINE] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _assert_base_event_texts() -> void:
	for expected_value in _baseline.get("events", []):
		var expected: Dictionary = expected_value
		var event := _find_event(str(expected["event_id"]))
		_assert_true(event != null, "基线事件应能加载：%s" % expected["event_id"])
		if event == null:
			continue
		var original := _capture_original_event_text(event)
		var display_event: GameEvent = _main_os.build_display_event(event)
		_assert_eq(
			_event_snapshot(display_event),
			expected,
			"无历史事件文本应逐字段匹配：%s" % expected["event_id"]
		)
		_assert_eq(
			_capture_original_event_text(event),
			original,
			"无历史事件运行时副本不得污染资源：%s" % expected["event_id"]
		)


func _assert_history_case_texts() -> void:
	var history_cases: Array = _baseline.get("history_cases", [])
	_assert_eq(history_cases.size(), 2, "事件叙事基线应保留两个历史场景")
	for case_value in history_cases:
		var history_case: Dictionary = case_value
		_main_os.restart_game_for_test()
		_main_os.get_node("Timer").stop()
		_apply_event_states(history_case.get("event_states", {}))
		_apply_decision_tags(history_case.get("decision_tags", {}))
		for expected_value in history_case.get("events", []):
			var expected: Dictionary = expected_value
			var event := _find_event(str(expected["event_id"]))
			_assert_true(
				event != null,
				"历史基线事件应能加载：%s / %s" % [history_case["name"], expected["event_id"]]
			)
			if event == null:
				continue
			var original := _capture_original_event_text(event)
			var display_event: GameEvent = _main_os.build_display_event(event)
			_assert_eq(
				_event_snapshot(display_event),
				expected,
				"历史事件文本应逐字段匹配：%s / %s" % [history_case["name"], expected["event_id"]]
			)
			_assert_eq(
				_capture_original_event_text(event),
				original,
				"历史运行时副本不得污染资源：%s" % expected["event_id"]
			)


func _apply_event_states(states: Dictionary) -> void:
	for key in states:
		_main_os.set_event_state(str(key), str(states[key]))


func _apply_decision_tags(decision_tags: Dictionary) -> void:
	for key in decision_tags:
		var decision_key := str(key)
		var expected_value := str(decision_tags[key])
		var matched := false
		for event in _main_os.all_events:
			for option in event.options:
				if option.decision_tag_key != decision_key:
					continue
				if option.decision_tag_value != expected_value:
					continue
				_main_os.apply_event_option_decision(option, event.event_title)
				matched = true
				break
			if matched:
				break
		_assert_true(matched, "历史基线决策应能由真实事件选项写入：%s" % decision_key)


func _find_event(event_id: String) -> GameEvent:
	for event in _main_os.all_events:
		if event.event_id == event_id:
			return event
	return null


func _event_snapshot(event: GameEvent) -> Dictionary:
	var options: Array[Dictionary] = []
	for option in event.options:
		options.append(
			{
				"option_id": option.option_id,
				"button_text": option.button_text,
			}
		)
	return {
		"event_id": event.event_id,
		"event_title": event.event_title,
		"event_level": event.event_level,
		"event_description": event.event_description,
		"options": options,
	}


func _capture_original_event_text(event: GameEvent) -> Dictionary:
	return _event_snapshot(event)


func _load_baseline() -> Dictionary:
	var file := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	_assert_true(file != null, "事件叙事基线文件应存在")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_assert_true(parsed is Dictionary, "事件叙事基线应是 JSON 对象")
	return parsed if parsed is Dictionary else {}
