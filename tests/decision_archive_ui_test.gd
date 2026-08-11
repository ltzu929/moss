## 决策档案真实 UI 测试。
## 通过主场景按钮、真实节点和 Viewport 输入验证模态暂停、关闭与 ui_cancel。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	await _assert_empty_archive_state()
	_seed_one_decision()
	await _assert_archive_modal_and_input()

	print("[MOSS-DECISION-ARCHIVE-UI] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _assert_empty_archive_state() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	var button := _main_os.get_node("MainLayout/MainHud/TopBarContainer/DecisionArchiveButton") as Button
	var panel := _main_os.get_node("%DecisionArchivePanel") as DecisionArchivePanel
	var close_button := panel.get_node("%ArchiveCloseButton") as Button
	button.pressed.emit()
	await get_tree().process_frame
	_assert_true(panel.visible, "零记录时仍应能打开决策档案")
	_assert_true(
		"尚未形成核心决策记录" in panel.get_node("%DecisionArchiveText").text,
		"空档案应显示明确空态"
	)
	close_button.pressed.emit()
	await get_tree().process_frame
	_assert_true(not panel.visible, "关闭按钮应隐藏空档案")
	_assert_true(timer.is_stopped(), "关闭前已暂停时不得擅自启动计时器")


func _seed_one_decision() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var event := load("res://data/events/event_2044_space_elevator_crisis.tres") as GameEvent
	_main_os.apply_event_option_decision(event.options[0], event.event_title)


func _assert_archive_modal_and_input() -> void:
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
	_assert_true(close_button.has_focus(), "打开档案后关闭按钮应取得键盘焦点")
	_assert_true(
		"2044 公开扩大自动化接入" in panel.get_node("%DecisionArchiveText").text,
		"档案面板应显示可读核心记录"
	)

	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	get_viewport().push_input(cancel_event)
	await get_tree().process_frame
	_assert_true(not panel.visible, "Viewport 的 ui_cancel 输入应关闭决策档案")
	_assert_true(not timer.is_stopped(), "ui_cancel 关闭后应恢复此前运行的计时器")

	button.pressed.emit()
	await get_tree().process_frame
	close_button.pressed.emit()
	await get_tree().process_frame
	_assert_true(not panel.visible, "关闭按钮应隐藏决策档案")
	_assert_true(not timer.is_stopped(), "关闭档案后应恢复此前运行的计时器")
	timer.stop()
