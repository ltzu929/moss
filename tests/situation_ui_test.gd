## 随机局势 HUD 测试：主界面入口、非模态详情、方针回写和双分辨率边界。
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _failed: int = 0
var _main_os: Control
var _panel: SituationPanel


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()
	_panel = _main_os.get_node("%SituationPanel") as SituationPanel

	_assert_hud_entry()
	await _assert_situation_details_and_approach()
	_assert_modal_boundary()
	_assert_responsive_bounds()
	_assert_time_control()

	print("[MOSS-SITUATION-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


func _assert_hud_entry() -> void:
	_assert_true(_main_os.has_node("%SituationButton"), "顶部栏应存在局势入口")
	_assert_true(_main_os.has_node("%TimeControlButton"), "顶部栏应存在暂停/继续按钮")
	_assert_true(_panel != null, "主场景应挂载非模态局势面板")
	_assert_eq((_main_os.get_node("%SituationButton") as Button).text, "局势  0 / 2", "局势入口应显示全局并发上限")


func _assert_situation_details_and_approach() -> void:
	var snapshot: Dictionary = _main_os.start_situation_for_test(
		"regional_power_instability", "亚洲", 2044, 7
	)
	await get_tree().process_frame
	_assert_true(not snapshot.is_empty(), "测试局势应能从主场景启动")
	_assert_true(_panel.visible, "新局势详情应可作为非模态面板打开")
	_assert_eq((_main_os.get_node("%SituationButton") as Button).text, "局势  1 / 2", "顶部入口应同步活跃局势数量")
	_assert_eq((_panel.get_node("%DetailTitle") as Label).text, "区域电网负荷失衡", "详情页应显示局势标题")
	_assert_eq((_panel.get_node("%SituationProgress") as ProgressBar).value, 38.0, "严重度进度条应显示当前风险")
	var approach_list := _panel.get_node("%ApproachList")
	_assert_eq(approach_list.get_child_count(), 3, "详情页应显示三种专属方针")
	var first_button := approach_list.get_child(0) as Button
	first_button.pressed.emit()
	await get_tree().process_frame
	var active: Array[Dictionary] = _main_os.get_situation_snapshots()
	_assert_eq(str(active[0].get("approach_id", "")), "local_repair", "方针选择应回写局势运行时")


func _assert_responsive_bounds() -> void:
	for viewport_size in [Vector2(1920, 1080), Vector2(1280, 720)]:
		var rect := _panel.calculate_window_rect(viewport_size)
		_assert_true(rect.position.x >= 0.0 and rect.position.y >= 0.0, "%s 下局势面板不应越过左上边界" % viewport_size)
		_assert_true(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "%s 下局势面板不应越过右下边界" % viewport_size)
		_assert_true(rect.size.x >= 360.0 and rect.size.y >= 420.0, "%s 下局势详情应保留可用阅读区域" % viewport_size)


func _assert_modal_boundary() -> void:
	_panel.hide()
	var event_popup := _main_os.get_node("%EventPopup") as Control
	event_popup.show()
	_main_os._on_situation_button_pressed()
	_assert_true(not _panel.visible, "事件模态显示时不得从下层 HUD 打开局势面板")
	event_popup.hide()


func _assert_time_control() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	_assert_true(timer.is_stopped(), "测试开始时计时器应暂停")
	_main_os._on_time_control_button_pressed()
	_assert_true(not timer.is_stopped(), "继续按钮应恢复月度推进")
	_main_os._on_time_control_button_pressed()
	_assert_true(timer.is_stopped(), "暂停按钮应停止月度推进")
	_assert_eq((_main_os.get_node("%TimeControlButton") as Button).text, "继续", "暂停后按钮应提示继续")


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(actual == expected, "%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)])
