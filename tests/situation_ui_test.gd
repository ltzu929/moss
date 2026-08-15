## 随机局势 HUD 测试：主界面入口、非模态详情、方针回写和双分辨率边界。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

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
	await _assert_inline_node()
	_assert_modal_boundary()
	_assert_responsive_bounds()
	_assert_time_control()

	print("[MOSS-SITUATION-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


func _assert_hud_entry() -> void:
	var hud := _main_os.get_node("MainLayout/MainHud") as MainHud
	var workspace := _main_os.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	_assert_true(hud.get_situation_button() != null, "顶部栏应存在局势入口")
	_assert_true(hud.get_time_control_button() != null, "顶部栏应存在暂停/继续按钮")
	_assert_true(hud.get_time_speed_option() != null, "顶部栏应存在调速入口")
	_assert_true(hud.get_single_step_button() != null, "顶部栏应存在单步推进入口")
	_assert_true(workspace.get_region_situation_text() != "", "上下文栏应存在当前选区局势摘要")
	_assert_true(hud.get_command_context_text() != "", "指令坞应显示当前选区提示")
	_assert_true(_panel != null, "主场景应挂载非模态局势面板")
	_assert_eq(hud.get_situation_button().text, "局势  0 / 2", "局势入口应显示全局并发上限")
	_assert_true(
		"请先选择区域" in hud.get_command_context_text(),
		"未选择区域时指令坞应说明前置操作"
	)


func _assert_situation_details_and_approach() -> void:
	var snapshot: Dictionary = _main_os.start_situation_for_test(
		"regional_power_instability", "asia", 2044, 7
	)
	await get_tree().process_frame
	_assert_true(not snapshot.is_empty(), "测试局势应能从主场景启动")
	_assert_true(_panel.visible, "新局势详情应可作为非模态面板打开")
	var workspace := _main_os.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	var hud := _main_os.get_node("MainLayout/MainHud") as MainHud
	_main_os.select_sector(workspace.get_sector_by_region_id("asia"))
	await get_tree().process_frame
	_assert_true(
		"区域电网负荷失衡" in workspace.get_region_situation_text(),
		"选中区域后上下文栏应显示该区域的活跃局势"
	)
	_assert_true(
		"当前选区：亚洲" in hud.get_command_context_text(),
		"选中区域后指令坞应同步当前选区"
	)
	_assert_eq(hud.get_situation_button().text, "局势  1 / 2", "顶部入口应同步活跃局势数量")
	_assert_eq((_panel.get_node("%DetailTitle") as Label).text, "区域电网负荷失衡", "详情页应显示局势标题")
	_assert_eq((_panel.get_node("%SituationProgress") as ProgressBar).value, 38.0, "严重度进度条应显示当前风险")
	var inline_alert := workspace.get_node(
		"ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationAlertPanel"
	) as Control
	_assert_true(inline_alert.visible, "选中区域后右栏应显示活跃局势告警")
	var inline_approaches := workspace.get_node(
		"ContentRow/ContextPanel/ContextMargin/ContextVBox/ApproachPanel/ApproachMargin/ApproachVBox/ApproachList"
	) as VBoxContainer
	_assert_true(inline_approaches.get_child_count() <= 2, "右栏轻操作最多展示两项方针")
	var approach_list := _panel.get_node("%ApproachList")
	_assert_eq(approach_list.get_child_count(), 3, "详情页应显示三种专属方针")
	_main_os.current_cpu = 0
	_main_os.current_energy = 0
	var paid_button := approach_list.get_child(2) as Button
	paid_button.pressed.emit()
	await get_tree().process_frame
	var active: Array[Dictionary] = _main_os.get_situation_snapshots()
	_assert_eq(
		str(active[0].get("approach_id", "")),
		"grid_takeover",
		"付费方针选择应回写局势运行时"
	)
	_assert_eq(
		int(active[0].get("expected_monthly_delta", -1)),
		6,
		"付费方针断供后预计趋势应转为恶化"
	)
	_assert_true(not bool(active[0].get("is_funded", true)), "局势快照应暴露持续成本不足")
	_assert_true(
		"+6" in (_panel.get_node("%TrendLabel") as Label).text,
		"局势面板应显示断供后的真实恶化值"
	)
	_assert_true(
		"持续成本不足" in (_panel.get_node("%TrendLabel") as Label).text,
		"局势面板应说明方针因断供不会生效"
	)
	_assert_true(
		"供给：不足" in (_panel.get_node("%CurrentApproachLabel") as Label).text,
		"局势面板应明确显示当前供给状态"
	)

	_main_os.current_year = 2044
	_main_os.current_month = 12
	_main_os.refresh_situation_ui()
	active = _main_os.get_situation_snapshots()
	_assert_eq(
		int(active[0].get("expected_monthly_delta", 0)),
		-5,
		"十二月趋势应先计入进入一月的年度恢复"
	)
	_assert_true(
		bool(active[0].get("is_funded", false)),
		"十二月低资源预测应标记一月恢复后的持续成本供给充足"
	)
	_assert_true(
		"-5" in (_panel.get_node("%TrendLabel") as Label).text,
		"跨年面板应显示年度恢复后的真实缓解值"
	)
	_assert_true(
		"供给：充足" in (_panel.get_node("%CurrentApproachLabel") as Label).text,
		"跨年面板应显示年度恢复后的供给状态"
	)

	await _main_os.process_month_tick()
	active = _main_os.get_situation_snapshots()
	_assert_eq(_main_os.current_year, 2045, "十二月推进后应进入下一年")
	_assert_eq(_main_os.current_month, 1, "十二月推进后应进入一月")
	_assert_eq(
		int(active[0].get("severity", -1)),
		33,
		"一月实际局势变化应与十二月预测一致"
	)
	_assert_eq(_main_os.current_cpu, 9, "一月恢复后应支付 1 算力持续成本")
	_assert_eq(_main_os.current_energy, 9, "一月恢复后应支付 1 能源持续成本")


func _assert_inline_node() -> void:
	_main_os.current_year = 2049
	_main_os.current_month = 2
	_main_os.current_cpu = 0
	_main_os.current_energy = 0
	await _main_os.process_month_tick()
	await _main_os.process_month_tick()
	var active: Array[Dictionary] = _main_os.get_situation_snapshots()
	var node: Dictionary = active[0].get("node", {})
	_assert_true(bool(node.get("pending", false)), "局势首次进入恶化时应生成待处理节点")
	_assert_true((_panel.get_node("%NodePanel") as Control).visible, "待处理节点应显示在非模态面板内")
	_assert_true(
		not (_panel.get_node("%ApproachScroll") as Control).visible,
		"处理节点时应暂时收起方针列表"
	)
	var node_options := _panel.get_node("%NodeOptionList")
	_assert_eq(node_options.get_child_count(), 2, "局势节点应显示两个确定性方案")
	var has_available_fallback := false
	for child in node_options.get_children():
		if child is Button and not (child as Button).disabled:
			has_available_fallback = true
	_assert_true(has_available_fallback, "资源见底时节点仍应保留可选兜底方案")
	var timer := _main_os.get_node("Timer") as Timer
	_assert_true(timer.is_stopped(), "待处理局势节点应保持自动暂停")
	_main_os.toggle_time_control()
	_assert_true(timer.is_stopped(), "节点处理前不应允许恢复时间")
	_assert_true(
		"请先处理" in (_main_os.get_node("MainLayout/MainHud") as MainHud).get_time_control_button().tooltip_text,
		"继续按钮应说明节点前置条件"
	)

	_main_os.current_energy = 5
	_main_os.refresh_situation_ui()
	await get_tree().process_frame
	node_options = _panel.get_node("%NodeOptionList")
	if node_options.get_child_count() == 0:
		_assert_true(false, "刷新资源后节点方案仍应存在")
		return
	var first_option := node_options.get_child(0) as Button
	_assert_true(not first_option.disabled, "资源充足时节点方案应可用")
	first_option.pressed.emit()
	await get_tree().process_frame
	active = _main_os.get_situation_snapshots()
	_assert_true(
		not bool(active[0].get("node", {}).get("pending", true)),
		"选择节点方案后应清除待处理状态"
	)
	_assert_true(
		(_panel.get_node("%ApproachScroll") as Control).visible,
		"节点处理后应恢复方针列表"
	)


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
	_main_os.open_situation_panel()
	_assert_true(not _panel.visible, "事件模态显示时不得从下层 HUD 打开局势面板")
	event_popup.hide()


func _assert_time_control() -> void:
	var timer := _main_os.get_node("Timer") as Timer
	_assert_true(timer.is_stopped(), "测试开始时计时器应暂停")
	_main_os.set_time_speed(0.5)
	_assert_true(is_equal_approx(timer.wait_time, 2.0), "局势 HUD 调速应设置 0.5x 的 2 秒/月")
	_main_os.set_time_speed(1.0)
	_main_os.toggle_time_control()
	_assert_true(not timer.is_stopped(), "继续按钮应恢复月度推进")
	_main_os.toggle_time_control()
	_assert_true(timer.is_stopped(), "暂停按钮应停止月度推进")
	_assert_eq((_main_os.get_node("MainLayout/MainHud") as MainHud).get_time_control_button().text, "继续", "暂停后按钮应提示继续")
