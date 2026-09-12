## 条件事件基础接口与旧分支退出测试。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")


func _ready() -> void:
	var main_os := MAIN_SCENE.instantiate()
	add_child(main_os)
	await get_tree().process_frame
	main_os.get_node("Timer").stop()
	for event in main_os.all_events:
		_assert_true(not event.event_id.begins_with("event_branch_"), "不得加载旧虚构灾难的衍生分支")
	var conditional := GameEvent.new()
	conditional.event_id = "event_test_support_condition"
	conditional.required_decision_tag_key = "decision.core_2058_network_support"
	conditional.required_decision_tag_value = "power_support"
	_assert_true(not main_os.is_event_available(conditional), "未写入的决策不能解锁条件")
	var source := load("res://data/events/event_2058_beijing_network_rescue.tres") as GameEvent
	main_os.apply_event_option_decision(source.options[1], source.event_title)
	_assert_true(not main_os.is_event_available(conditional), "错误决策值不能解锁条件")
	main_os.restart_game_for_test()
	main_os.get_node("Timer").stop()
	main_os.apply_event_option_decision(source.options[0], source.event_title)
	_assert_true(main_os.is_event_available(conditional), "匹配真实决策应解锁条件")
	conditional.required_decision_tag_value = ""
	_assert_true(main_os.is_event_available(conditional), "空条件值只要求事实存在")
	main_os.restart_game_for_test()
	main_os.get_node("Timer").stop()
	_assert_true(not main_os.is_event_available(conditional), "重开清理条件事实")
	print("[MOSS-BRANCH-EVENTS] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)
