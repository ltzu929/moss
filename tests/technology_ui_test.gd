## 科技界面集成测试
## 验证静态场景结构、模态冲突、节点状态、详情同步、两步确认和计时器恢复
extends Node

# ============================================================
# 测试状态
# ============================================================

## 失败断言数量，同时作为进程退出码
var _failed: int = 0
## 被测主场景实例
var _main_os: Control
## 被测科技系统
var _technology: TechnologySystem
## 被测科技控制台
var _screen
## 主场景年份计时器
var _timer: Timer

# ============================================================
# 测试入口
# ============================================================

## 创建主场景并执行科技控制台交互断言
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	_main_os = scene.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_technology = _main_os.get_node("%TechnologySystem")
	_screen = _main_os.get_node("%TechnologyScreen")
	_timer = _main_os.get_node("Timer")
	_timer.start()

	var cards := _get_node_cards()
	_assert_eq(cards.size(), 12, "科技场景应预置12张节点卡")
	if cards.size() != 12:
		print("[MOSS-TECH-UI] 完成，失败断言：%d" % _failed)
		await get_tree().create_timer(0.2).timeout
		get_tree().quit(_failed)
		return
	_assert_static_card_resources(cards)

	var technology_button: Button = _main_os.get_node("%TechnologyButton")
	technology_button.pressed.emit()
	_assert_true(_screen.visible, "无模态弹窗时科技按钮应打开科技树")
	_screen.close_screen()
	_main_os.get_node("%EventPopup").show()
	technology_button.pressed.emit()
	_assert_true(not _screen.visible, "事件弹窗应阻止科技按钮打开科技树")
	_main_os.get_node("%EventPopup").hide()
	_main_os.get_node("%AllocatePopup").show()
	technology_button.pressed.emit()
	_assert_true(not _screen.visible, "算力分配弹窗应阻止科技按钮打开科技树")
	_main_os.get_node("%AllocatePopup").hide()

	technology_button.pressed.emit()
	_assert_true(_screen.visible, "科技树应全屏显示")
	_assert_true(_timer.is_stopped(), "打开科技树应暂停年份")
	var first_instance_ids := _get_card_instance_ids(cards)
	_screen.close_screen()
	technology_button.pressed.emit()
	var reopened_cards := _get_node_cards()
	_assert_eq(
		_get_card_instance_ids(reopened_cards),
		first_instance_ids,
		"重复打开科技树不得创建或替换节点卡"
	)
	_assert_eq(
		_technology.get_activation_state("managed_decision"),
		"available",
		"550C根节点应可激活"
	)
	_assert_eq(
		_technology.get_activation_state("managed_infrastructure"),
		"stage_locked",
		"开局550W节点应阶段锁定"
	)
	_assert_eq(
		_technology.get_activation_state("managed_irreplaceable_protocol"),
		"stage_locked",
		"开局MOSS核心应阶段锁定"
	)

	var managed_card := _find_card(cards, "managed_decision")
	var core_card := _find_card(cards, "core_energy_mapping")
	_assert_true(managed_card != null, "应找到辅助决策接口卡片")
	_assert_true(core_card != null, "应找到能量映射卡片")
	if managed_card == null or core_card == null:
		get_tree().quit(_failed)
		return

	managed_card.pressed.emit()
	_assert_eq(
		_screen.get_node("%DetailName").text,
		"辅助决策接口",
		"右侧详情应同步节点名称"
	)
	_assert_eq(
		_screen.get_node("%ActivateButton").text,
		"激活协议",
		"首次应显示激活操作"
	)
	_screen.get_node("%ManagedRouteButton").pressed.emit()
	_assert_eq(managed_card.modulate, Color.WHITE, "路线筛选应保留同路线卡片亮度")
	_assert_eq(
		core_card.modulate,
		Color(0.48, 0.56, 0.60, 1.0),
		"路线筛选应降低其他路线卡片亮度"
	)
	_screen.close_screen()
	technology_button.pressed.emit()
	_assert_eq(core_card.modulate, Color.WHITE, "重新打开应清除路线筛选")
	managed_card.pressed.emit()

	_screen.get_node("%ActivateButton").pressed.emit()
	_assert_eq(_technology.get_active_node_ids().size(), 0, "第一次点击不得直接激活")
	_assert_eq(
		_screen.get_node("%ActivateButton").text,
		"确认不可逆激活",
		"第一次点击应进入确认"
	)
	_screen.get_node("%ActivateButton").pressed.emit()
	_assert_true(_technology.is_active("managed_decision"), "第二次点击应激活节点")
	_assert_eq(
		_technology.get_activation_state("core_energy_mapping"),
		"points_locked",
		"协议点耗尽后其他根节点应显示点数不足"
	)

	_technology.grant_research_for_year(2048)
	_assert_true(_technology.activate("core_energy_mapping"), "第二个根节点应推动阶段升级")
	_assert_eq(
		_technology.get_activation_state("managed_infrastructure"),
		"points_locked",
		"已满足前置但无点数的节点应显示点数不足"
	)
	_assert_eq(
		_technology.get_activation_state("human_autonomy_network"),
		"prerequisite_locked",
		"未激活路线根节点时应显示前置锁定"
	)

	_screen.close_screen()
	_assert_true(not _screen.visible, "关闭科技树应隐藏覆盖层")
	_assert_true(not _timer.is_stopped(), "关闭后应恢复原本运行的年份计时")

	print("[MOSS-TECH-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)

# ============================================================
# 断言辅助方法
# ============================================================

## 返回科技场景中预置的节点卡
func _get_node_cards() -> Array[Node]:
	var cards: Array[Node] = []
	for card in _screen.find_children("*", "Button", true, false):
		if card.is_in_group("technology_node_cards"):
			cards.append(card)
	return cards


## 校验12张卡片引用唯一资源，并符合每条路线的阶段布局
func _assert_static_card_resources(cards: Array[Node]) -> void:
	var node_ids: Dictionary = {}
	var route_stage_counts: Dictionary = {}
	var route_containers := {
		TechNodeData.Route.MANAGED: "ManagedRow",
		TechNodeData.Route.CORE: "CoreRow",
		TechNodeData.Route.HUMAN: "HumanRow",
	}
	var stage_containers := {
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
		var stage_container := card.get_parent()
		_assert_true(
			str(stage_container.name).ends_with(stage_containers[node_data.stage]),
			"%s 应位于对应阶段容器" % node_data.display_name
		)
		var route_container := stage_container.get_parent()
		_assert_eq(
			str(route_container.name),
			route_containers[node_data.route],
			"%s 应位于对应路线" % node_data.display_name
		)

	_assert_eq(node_ids.size(), 12, "12张卡片必须分别引用唯一科技资源")
	for route in TechNodeData.Route.values():
		_assert_eq(
			route_stage_counts.get("%d:%d" % [route, TechNodeData.Stage.C550], 0),
			1,
			"每条路线应预置1张550C卡片"
		)
		_assert_eq(
			route_stage_counts.get("%d:%d" % [route, TechNodeData.Stage.W550], 0),
			2,
			"每条路线应预置2张550W卡片"
		)
		_assert_eq(
			route_stage_counts.get("%d:%d" % [route, TechNodeData.Stage.MOSS], 0),
			1,
			"每条路线应预置1张MOSS卡片"
		)


## 返回当前卡片实例ID，用于确认重复打开不会重建节点
func _get_card_instance_ids(cards: Array[Node]) -> Array[int]:
	var instance_ids: Array[int] = []
	for card in cards:
		instance_ids.append(card.get_instance_id())
	instance_ids.sort()
	return instance_ids


## 按稳定节点ID查找场景中的卡片
func _find_card(cards: Array[Node], node_id: String) -> Node:
	for card in cards:
		var node_data: TechNodeData = card.get("node_data")
		if node_data != null and node_data.node_id == node_id:
			return card
	return null


## 断言条件为 true，失败时累计退出码并输出错误
func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


## 断言实际值与期望值相等
func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
