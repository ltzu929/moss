## 危机阶段资源与同月顺序测试；覆盖退出旧中型事件后的真实月度编排。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
var _main_os: Control
var _seen: Array[String] = []
var _checking_final: bool = false


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()
	var events: Array[GameEvent] = _main_os.all_events
	_assert_eq(events.size(), 5, "只加载五个原作危机阶段")
	for event in events:
		_assert_true(event.event_image != null, "每个阶段应绑定可加载的专属示意图")
		_assert_true(event.required_decision_tag_key.is_empty(), "主线阶段不能被旧决策门禁跳过")
		for option in event.options:
			_assert_true(option.event_state_key.is_empty(), "旧中型事件状态不得残留写入")
	_assert_eq(events[1].event_order, 0, "北京支援是2058首阶段")
	_assert_eq(events[2].event_order, 1, "月球最终支援是2058后阶段")
	_assert_eq(events[3].event_order, 0, "发动机支援是2075首阶段")
	_assert_eq(events[4].event_order, 1, "木星最终抉择是2075后阶段")
	_main_os.get_node("%EventPopup").visibility_changed.connect(_on_popup_visibility)
	for year in [2058, 2075]:
		_main_os.restart_game_for_test()
		_main_os.get_node("Timer").stop()
		_main_os.current_year = year
		_main_os.current_month = 1
		_main_os.current_energy = 0
		_seen.clear()
		_checking_final = year == 2075
		await _main_os.process_month_tick()
		_assert_eq(_seen.size(), 2, "零能源时同月两个阶段都应完成")
		_assert_eq(_main_os.triggered_events.size(), 2, "两个阶段各触发一次")
		_assert_eq(_main_os.current_energy, 0, "零能源路线不应产生负能源")
		if year == 2058:
			_assert_eq(_seen, ["北京联网救援", "月球危机最终支援"], "月球危机内部顺序正确")
		else:
			_assert_eq(_seen, ["行星发动机救援", "木星引力危机"], "发动机救援先于终局")
			_assert_true(_main_os.is_game_over, "两个阶段之后才能结束游戏")
	print("[MOSS-MID-EVENTS] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _on_popup_visibility() -> void:
	var popup := _main_os.get_node("%EventPopup") as Control
	if not popup.visible:
		return
	await get_tree().process_frame
	_seen.append(popup.get_node("%EventTitle").text)
	if _checking_final:
		_assert_true(not _main_os.is_game_over, "危机抉择完成前不得提前判定结局")
	for child in popup.get_node("%OptionList").get_children():
		if child is Button and not child.disabled:
			child.pressed.emit()
			return
	_assert_true(false, "零能源仍应有真实可执行按钮")
