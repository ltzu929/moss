## 科技玩法集成测试
## 验证科技节点对指令、资源、事件减损、年度恢复和重开的影响
extends Node

# ============================================================
# 测试状态
# ============================================================

## 失败断言数量，同时作为进程退出码
var _failed: int = 0
## 被测主场景实例
var _main_os: Control

# ============================================================
# 测试入口
# ============================================================

## 创建主场景并执行科技玩法集成断言
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	_main_os = scene.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	var technology: TechnologySystem = _main_os.get_node("%TechnologySystem")
	_assert_eq(technology.get_available_points(), 1, "主场景科技系统应从1点开始")
	_assert_true(technology.activate("core_energy_mapping"), "应激活能量映射")
	_assert_true(_main_os.has_command_id("energy_convert"), "应解锁能源转换")

	technology.grant_research_for_year(2048)
	_assert_true(technology.activate("managed_decision"), "应激活辅助决策接口")
	_assert_true(_main_os.can_allocate_combined(), "算力分配应开放综合调度")

	technology.grant_research_for_year(2052)
	_assert_true(technology.activate("core_parallel"), "应激活并行核心")
	_assert_eq(_main_os.max_cpu, 150, "并行核心应提高算力上限")

	technology.grant_research_for_year(2056)
	_assert_true(technology.activate("core_self_repair"), "应激活自修复进程")
	_assert_eq(_main_os.cpu_recovery_rate, 15, "自修复应提高恢复率")

	technology.grant_research_for_year(2060)
	_assert_true(technology.activate("managed_infrastructure"), "应激活基础设施托管")
	var takeover: CommandData = _main_os._get_command_by_id("takeover")
	_assert_eq(takeover.cpu_cost, 25, "基础设施托管应降低接管算力成本")
	_assert_eq(takeover.energy_cost, 15, "基础设施托管应降低接管能源成本")
	_assert_eq(takeover.authority_delta, 15, "基础设施托管应提高控制权收益")
	_assert_eq(takeover.hope_delta, -5, "基础设施托管应损失希望")

	technology.grant_research_for_year(2064)
	_assert_true(technology.activate("managed_global_network"), "应激活全域协调网络")
	_assert_true(_main_os.has_command_id("global_takeover"), "应解锁全局接管")

	technology.grant_research_for_year(2068)
	_assert_true(technology.activate("core_recursive"), "应激活递归优化")
	_assert_eq(_main_os.cooldown_reduction, 1, "递归优化应减少1年冷却")
	_main_os.current_cpu = 0
	_main_os.apply_special_command_effect(_main_os._get_command_by_id("energy_convert"))
	_assert_eq(_main_os.current_cpu, 15, "递归优化应使能源转换获得15算力")

	var mitigated: int = _main_os.get_technology_adjusted_event_delta(-20, "order")
	_assert_eq(mitigated, -20, "未激活应急训练时不减损")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	technology = _main_os.get_node("%TechnologySystem")
	_assert_eq(technology.get_active_node_ids().size(), 0, "重开应清空科技节点")
	_assert_true(not _main_os.has_command_id("energy_convert"), "重开应移除科技指令")
	_assert_eq(_main_os.max_cpu, 100, "重开应恢复算力上限")

	_activate_nodes(
		technology,
		[
			"human_open_interface",
			"core_energy_mapping",
			"human_autonomy_network",
			"human_emergency_training",
			"core_parallel",
			"core_self_repair",
			"human_civilization_self_sustain",
		]
	)
	_assert_true(_main_os.has_command_id("technology_aid"), "开放技术接口应解锁技术援助")
	mitigated = _main_os.get_technology_adjusted_event_delta(-20, "hope")
	_assert_eq(mitigated, -15, "应急训练应将负面秩序希望影响减轻25%")

	var first_sector: SectorInfo = (
		_main_os.get_node("%SectorInfoContainer").get_child(0) as SectorInfo
	)
	first_sector.data_card.order = 30
	first_sector.data_card.hope = 30
	_main_os._apply_human_autonomy_recovery()
	_assert_eq(first_sector.data_card.order, 32, "文明自持应使低秩序年度恢复2")
	_assert_eq(first_sector.data_card.hope, 32, "文明自持应使低希望年度恢复2")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_nodes(
		technology,
		[
			"managed_decision",
			"core_energy_mapping",
			"managed_infrastructure",
			"managed_global_network",
			"core_parallel",
			"core_self_repair",
			"managed_irreplaceable_protocol",
		]
	)
	var global_takeover: CommandData = _main_os._get_command_by_id("global_takeover")
	first_sector = _main_os.get_node("%SectorInfoContainer").get_child(0)
	var authority_before: int = first_sector.data_card.authority
	var order_before: int = first_sector.data_card.order
	var hope_before: int = first_sector.data_card.hope
	_main_os.apply_special_command_effect(global_takeover)
	_assert_eq(first_sector.data_card.authority, authority_before + 8, "托管核心应强化全局控制权")
	_assert_eq(first_sector.data_card.order, order_before + 5, "托管核心应提高全局秩序")
	_assert_eq(first_sector.data_card.hope, hope_before - 5, "托管核心应降低全局希望")

	get_tree().quit(_failed)

# ============================================================
# 测试辅助方法
# ============================================================

## 按顺序激活测试节点，并在协议点耗尽时发放下一年度研究点
func _activate_nodes(technology: TechnologySystem, node_ids: Array[String]) -> void:
	var research_year_index := 0
	for node_id in node_ids:
		if technology.get_available_points() == 0:
			technology.grant_research_for_year(
				TechnologySystem.RESEARCH_YEARS[research_year_index]
			)
			research_year_index += 1
		_assert_true(technology.activate(node_id), "应激活测试节点 %s" % node_id)


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
