## 真实决策组合应同时改变正文、按钮和数值，且不污染模板。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")


func _ready() -> void:
	var main_os := MAIN_SCENE.instantiate()
	add_child(main_os)
	await get_tree().process_frame
	main_os.get_node("Timer").stop()
	var access := load("res://data/events/event_2044_space_elevator_crisis.tres") as GameEvent
	var network := load("res://data/events/event_2058_beijing_network_rescue.tres") as GameEvent
	var final_event := load("res://data/events/event_2058_lunar_fall_crisis.tres") as GameEvent
	var access_fragments := ["公开扩大的工程接口", "保留人工指挥", "收紧工程接口"]
	var network_fragments := ["集中投入供电支援", "现场人员确认需求", "集中调度支援接口"]
	var access_suffixes := ["沿用公开接口", "沿用人工指挥", "重新准备接入"]
	var network_suffixes := ["供电支援已投入", "现场协作延续", "支援接口已集中"]
	for i in range(3):
		for j in range(3):
			main_os.restart_game_for_test()
			main_os.get_node("Timer").stop()
			main_os.apply_event_option_decision(access.options[i], access.event_title)
			main_os.apply_event_option_decision(network.options[j], network.event_title)
			var display: GameEvent = main_os.build_display_event(final_event)
			_assert_true(access_fragments[i] in display.event_description, "早期接口回声应存在")
			_assert_true(network_fragments[j] in display.event_description, "同月供电回声应叠加")
			_assert_true(access_suffixes[i] in display.options[[0, 1, 0][i]].button_text, "接口后缀对应真实选择")
			_assert_true(network_suffixes[j] in display.options[j].button_text, "供电后缀对应真实选择")
			_assert_eq(display.options[0].energy_cost, 60 + [-10, 0, 10][i] + [-15, 0, 0][j], "显示副本包含叠加成本")
			main_os.apply_event_option_decision(final_event.options[0], final_event.event_title)
			_assert_eq(main_os.get_decision_records().size(), 3, "后写事实不得覆盖早期记录")
			var ending: String = main_os.build_ending_message("coexistence")
			_assert_true(access_fragments[i] in ending, "早期选择保留至结局")
			_assert_true(network_fragments[j] in ending, "同月供电选择保留至结局")
	_assert_eq(final_event.options[0].energy_cost, 60, "显示副本不得污染真实资源")
	_assert_true("本局历史回声" not in final_event.event_description, "模板不保留本局历史")
	print("[MOSS-EVENT-NARRATIVE-MATRIX] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)
