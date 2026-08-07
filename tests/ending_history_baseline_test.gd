## 结局叙事基线测试。
## 锁定四类结局、历史回顾和科技摘要的玩家可见文本。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const BASELINE_PATH := "res://tests/fixtures/ending_history_baseline.json"

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
		"结局叙事基线 schema 版本应匹配"
	)
	_assert_empty_messages()
	_assert_history_messages()
	_assert_technology_summary()

	print("[MOSS-ENDING-HISTORY-BASELINE] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _assert_empty_messages() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var expected_messages: Dictionary = _baseline.get("empty_messages", {})
	for result in ["failed", "coexistence", "managed", "human_autonomy"]:
		_assert_eq(
			_main_os.build_ending_message(result),
			str(expected_messages.get(result, "")),
			"无历史状态的%s结局文本应逐字匹配" % result
		)


func _assert_history_messages() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var history_case: Dictionary = _baseline.get("history_case", {})
	_apply_event_states(history_case.get("event_states", {}))
	_apply_decision_tags(history_case.get("decision_tags", {}))
	var expected_messages: Dictionary = history_case.get("messages", {})
	for result in ["failed", "coexistence", "managed", "human_autonomy"]:
		_assert_eq(
			_main_os.build_ending_message(result),
			str(expected_messages.get(result, "")),
			"含历史回顾的%s结局文本应逐字匹配" % result
		)


func _assert_technology_summary() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var summaries: Dictionary = _baseline.get("technology_summaries", {})
	_assert_eq(
		_main_os.get_technology_summary(),
		str(summaries.get("empty", "")),
		"无科技激活时摘要应逐字匹配结局基线"
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
		_assert_true(matched, "结局基线决策应能由真实事件选项写入：%s" % decision_key)


func _load_baseline() -> Dictionary:
	var file := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	_assert_true(file != null, "结局叙事基线文件应存在")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_assert_true(parsed is Dictionary, "结局叙事基线应是 JSON 对象")
	return parsed if parsed is Dictionary else {}
