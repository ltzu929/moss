## 科技界面集成测试
## 验证三页静态场景、居中窗口、节点状态、终端互斥和计时器恢复
extends "res://tests/support/moss_test_case.gd"

var _main_os: Control
var _technology: TechnologySystem
var _screen: TechnologyScreen
var _timer: Timer


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	_main_os = scene.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_technology = _main_os.get_node("%TechnologySystem")
	_screen = _main_os.get_node("%TechnologyScreen") as TechnologyScreen
	_timer = _main_os.get_node("Timer")
	_timer.start()

	var cards := _get_node_cards()
	_assert_eq(cards.size(), 21, "科技场景应预置21张节点卡")
	if cards.size() != 21:
		get_tree().quit(_failed)
		return
	_assert_static_card_resources(cards)
	_assert_window_sizing()

	var hud := _main_os.get_node("MainLayout/MainHud") as MainHud
	var technology_button: Button = hud.get_technology_button()
	technology_button.pressed.emit()
	await get_tree().process_frame
	_assert_true(_screen.visible, "无模态弹窗时科技按钮应打开科技树")
	_assert_true(_timer.is_stopped(), "打开科技树应暂停年份")
	_assert_eq(_screen.get_node("%YearLabel").text, "系统时间  2044.01", "科技界面应显示年月")
	_assert_route_page(TechNodeData.Route.MANAGED, true)
	_assert_route_page(TechNodeData.Route.CORE, false)
	_assert_route_page(TechNodeData.Route.HUMAN, false)
	_assert_centered_window()
	_assert_true(
		_screen.z_index > hud.get_year_progress().z_index,
		"科技窗口层级应高于时间线"
	)

	var first_instance_ids := _get_card_instance_ids(cards)
	var managed_card := _find_card(cards, "managed_decision")
	var core_card := _find_card(cards, "core_energy_mapping")
	_assert_true(managed_card != null, "应找到辅助决策接口卡片")
	_assert_true(core_card != null, "应找到能量映射卡片")
	if managed_card == null or core_card == null:
		get_tree().quit(_failed)
		return

	managed_card.pressed.emit()
	_assert_eq(_screen.get_node("%DetailName").text, "辅助决策接口", "详情应同步节点名称")
	_screen.get_node("%ActivateButton").pressed.emit()
	_assert_true(_technology.is_active("managed_decision"), "首次点击应直接激活节点")
	_assert_eq(_screen.get_node("%ActivateButton").text, "协议已激活", "激活后按钮应立即更新")

	_screen.get_node("%CoreRouteButton").pressed.emit()
	_assert_route_page(TechNodeData.Route.MANAGED, false)
	_assert_route_page(TechNodeData.Route.CORE, true)
	_assert_eq(_screen.get_node("%DetailName").text, "未选择", "切换路线应清除节点选择")
	_assert_true(_screen.get_node("%ActivateButton").disabled, "切换路线后未选择节点时按钮应禁用")

	_screen.close_screen()
	technology_button.pressed.emit()
	await get_tree().process_frame
	_assert_route_page(TechNodeData.Route.CORE, true)
	_assert_eq(
		_get_card_instance_ids(_get_node_cards()),
		first_instance_ids,
		"重复打开不得重建节点卡"
	)

	_technology.grant_research_for_year(2048)
	core_card.pressed.emit()
	_screen.get_node("%ActivateButton").pressed.emit()
	_assert_true(_technology.is_active("core_energy_mapping"), "单次点击激活应推动阶段升级")
	_assert_eq(
		_technology.get_activation_state("managed_infrastructure"),
		"points_locked",
		"满足前置但无点数时应显示协议点不足"
	)

	_assert_terminal_conflict_ui(cards)

	_screen.close_screen()
	_main_os.get_node("%EventPopup").show()
	technology_button.pressed.emit()
	_assert_true(not _screen.visible, "事件弹窗应阻止科技树打开")
	_main_os.get_node("%EventPopup").hide()
	_main_os.get_node("%AllocatePopup").show()
	technology_button.pressed.emit()
	_assert_true(not _screen.visible, "算力分配弹窗应阻止科技树打开")
	_main_os.get_node("%AllocatePopup").hide()
	_assert_true(not _timer.is_stopped(), "关闭后应恢复原本运行的年份计时")

	print("[MOSS-TECH-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_window_sizing() -> void:
	_assert_eq(
		_screen.calculate_window_size(Vector2(1920, 1080)),
		Vector2(1680, 900),
		"1920x1080时窗口应限制为1680x900"
	)
	_assert_eq(
		_screen.calculate_window_size(Vector2(1280, 720)),
		Vector2(1216, 656),
		"1280x720时窗口应保留32像素边距"
	)


func _assert_centered_window() -> void:
	var panel := _screen.get_node("%WindowPanel") as Control
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_center := panel.global_position + panel.size * 0.5
	_assert_true(panel_center.distance_to(viewport_size * 0.5) <= 2.0, "科技窗口应位于视口中央")
	_assert_true(panel.size.x <= viewport_size.x - 64.0, "科技窗口应保留水平边距")
	_assert_true(panel.size.y <= viewport_size.y - 64.0, "科技窗口应保留垂直边距")


func _assert_route_page(route: TechNodeData.Route, expected: bool) -> void:
	var page_names := {
		TechNodeData.Route.MANAGED: "%ManagedRoutePage",
		TechNodeData.Route.CORE: "%CoreRoutePage",
		TechNodeData.Route.HUMAN: "%HumanRoutePage",
	}
	_assert_eq(_screen.get_node(page_names[route]).visible, expected, "路线页面可见性应正确")


func _assert_terminal_conflict_ui(cards: Array[Node]) -> void:
	_technology.reset()
	var activation_order: Array[String] = [
		"managed_decision",
		"managed_behavior_prediction",
		"core_energy_mapping",
		"managed_infrastructure",
		"managed_global_network",
		"managed_authority_audit",
		"managed_consensual_protocol",
	]
	var year_index := 0
	for node_id in activation_order:
		if _technology.get_available_points() == 0:
			_technology.grant_research_for_year(TechnologySystem.RESEARCH_YEARS[year_index])
			year_index += 1
		_assert_true(_technology.activate(node_id), "应激活互斥测试节点 %s" % node_id)
	_screen.get_node("%ManagedRouteButton").pressed.emit()
	var conflict_card := _find_card(cards, "managed_irreplaceable_protocol")
	conflict_card.pressed.emit()
	_assert_eq(_screen.get_node("%ActivateButton").text, "终端互斥", "互斥终端应显示专用锁定状态")
	_assert_true(
		"协商托管协议" in _screen.get_node("%DetailRequirements").text,
		"互斥提示应指出已激活终端"
	)


func _get_node_cards() -> Array[Node]:
	var cards: Array[Node] = []
	for card in _screen.find_children("*", "Button", true, false):
		if card.is_in_group("technology_node_cards"):
			cards.append(card)
	return cards


func _assert_static_card_resources(cards: Array[Node]) -> void:
	var node_ids: Dictionary = {}
	var route_stage_counts: Dictionary = {}
	var page_names := {
		TechNodeData.Route.MANAGED: "ManagedRoutePage",
		TechNodeData.Route.CORE: "CoreRoutePage",
		TechNodeData.Route.HUMAN: "HumanRoutePage",
	}
	var stage_names := {
		TechNodeData.Stage.C550: "C550Nodes",
		TechNodeData.Stage.W550: "W550Nodes",
		TechNodeData.Stage.MOSS: "MossNodes",
	}
	for card in cards:
		var node_data: TechNodeData = card.get("node_data")
		_assert_true(node_data != null, "每张科技卡片都必须引用节点资源")
		if node_data == null:
			continue
		node_ids[node_data.node_id] = true
		var key := "%d:%d" % [node_data.route, node_data.stage]
		route_stage_counts[key] = route_stage_counts.get(key, 0) + 1
		_assert_eq(str(card.get_parent().name), stage_names[node_data.stage], "卡片应位于对应阶段容器")
		_assert_true(_has_ancestor_named(card, page_names[node_data.route]), "卡片应位于对应路线页面")

	_assert_eq(node_ids.size(), 21, "21张卡片必须引用唯一科技资源")
	for route in TechNodeData.Route.values():
		_assert_eq(route_stage_counts.get("%d:%d" % [route, TechNodeData.Stage.C550], 0), 2, "每页应有2张550C卡片")
		_assert_eq(route_stage_counts.get("%d:%d" % [route, TechNodeData.Stage.W550], 0), 3, "每页应有3张550W卡片")
		_assert_eq(route_stage_counts.get("%d:%d" % [route, TechNodeData.Stage.MOSS], 0), 2, "每页应有2张MOSS卡片")


func _has_ancestor_named(node: Node, ancestor_name: String) -> bool:
	var current := node.get_parent()
	while current != null:
		if str(current.name) == ancestor_name:
			return true
		current = current.get_parent()
	return false


func _get_card_instance_ids(cards: Array[Node]) -> Array[int]:
	var instance_ids: Array[int] = []
	for card in cards:
		instance_ids.append(card.get_instance_id())
	instance_ids.sort()
	return instance_ids


func _find_card(cards: Array[Node], node_id: String) -> Node:
	for card in cards:
		var node_data: TechNodeData = card.get("node_data")
		if node_data != null and node_data.node_id == node_id:
			return card
	return null
