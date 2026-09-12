## 四类治理结局读取全部新决策变体；不复活旧灾难历史。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const CASES: Dictionary = {
	"event_2044_space_elevator_crisis": ["公开扩大的工程接口", "保留人工指挥", "收紧工程接口"],
	"event_2058_beijing_network_rescue": ["集中投入供电支援", "现场人员确认需求", "集中调度支援接口"],
	"event_2058_lunar_fall_crisis": ["授权范围内集中支援", "保留人类最终授权", "扩大自动调度权限"],
	"event_2075_engine_rescue": ["救援队确认支援顺序", "追加支援投入", "集中调度系统支援"],
}


func _ready() -> void:
	var main_os := MAIN_SCENE.instantiate()
	add_child(main_os)
	await get_tree().process_frame
	main_os.get_node("Timer").stop()
	for event_id in CASES:
		var event := load("res://data/events/%s.tres" % event_id) as GameEvent
		for index in range(3):
			main_os.restart_game_for_test()
			main_os.get_node("Timer").stop()
			main_os.apply_event_option_decision(event.options[index], event.event_title)
			for result in ["failed", "coexistence", "managed", "human_autonomy"]:
				var message: String = main_os.build_ending_message(result)
				_assert_true(CASES[event_id][index] in message, "所有结局都应读取实际选择")
				_assert_true("游戏改编" in message, "治理结局明确为游戏改编")
				for other in range(3):
					if other != index:
						_assert_true(CASES[event_id][other] not in message, "不得补写未选分支")
	var system := EndingSystem.new()
	var ghost_tags := {
		"decision.core_2053_population_vs_infrastructure": "sacrifice_perimeter",
		"decision.core_2065_audit_posture": "hidden_core_chain",
		"decision.core_2070_engine_protection": "forced_overclock",
	}
	_assert_eq(system.build_ending_message("coexistence", ghost_tags, {}), system.build_ending_message("coexistence", {}, {}), "已退出事实没有结局消费者")
	main_os.restart_game_for_test()
	main_os.get_node("Timer").stop()
	_assert_true("历史回顾" not in main_os.build_ending_message("coexistence"), "重开清理结局历史")
	print("[MOSS-ENDING-HISTORY] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)
