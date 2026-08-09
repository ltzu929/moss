## 科技玩法集成测试
## 验证科技节点对指令、资源、事件减损、年度恢复和重开的影响
extends "res://tests/support/moss_test_case.gd"

# ============================================================
# 测试状态
# ============================================================

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

	var first_sector: SectorInfo = _get_first_sector()
	first_sector.data_card.order = 80
	first_sector.data_card.hope = 75
	_main_os._apply_human_autonomy_recovery()
	_assert_eq(first_sector.data_card.order, 80, "恢复不应降低高于上限的秩序")
	_assert_eq(first_sector.data_card.hope, 75, "恢复不应降低高于上限的希望")

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
	first_sector = _get_first_sector()
	var authority_before: int = first_sector.data_card.authority
	var order_before: int = first_sector.data_card.order
	var hope_before: int = first_sector.data_card.hope
	_main_os.apply_special_command_effect(global_takeover)
	_assert_eq(first_sector.data_card.authority, authority_before + 8, "托管核心应强化全局控制权")
	_assert_eq(first_sector.data_card.order, order_before + 5, "托管核心应提高全局秩序")
	_assert_eq(first_sector.data_card.hope, hope_before - 5, "托管核心应降低全局希望")

	_assert_new_technology_effects()
	print("[MOSS-TECH-GAMEPLAY] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)

# ============================================================
# 测试辅助方法
# ============================================================

## 校验新增节点的数值、终端覆盖优先级和重置行为
func _assert_new_technology_effects() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	var technology: TechnologySystem = _main_os.get_node("%TechnologySystem")
	_activate_nodes(
		technology,
		[
			"managed_behavior_prediction",
			"managed_decision",
			"managed_authority_audit",
			"managed_infrastructure",
			"managed_global_network",
			"core_energy_mapping",
			"core_parallel",
			"managed_consensual_protocol",
		]
	)
	var takeover: CommandData = _main_os._get_command_by_id("takeover")
	_assert_eq(takeover.cooldown_years, 4, "行为预测模型应将系统接管基础冷却降为4年")
	_assert_eq(takeover.energy_cost, 10, "权限审计链应在基础设施托管后继续降低接管能源")
	_assert_eq(takeover.authority_delta, 12, "协商托管协议应覆盖接管控制权收益")
	_assert_eq(takeover.hope_delta, 0, "协商托管协议不应降低希望")
	var global_takeover: CommandData = _main_os._get_command_by_id("global_takeover")
	_assert_eq(global_takeover.energy_cost, 5, "权限审计链应降低全局接管能源消耗")
	var first_sector: SectorInfo = _get_first_sector()
	var authority_before := first_sector.data_card.authority
	var order_before := first_sector.data_card.order
	var hope_before := first_sector.data_card.hope
	_main_os.apply_special_command_effect(global_takeover)
	_assert_eq(first_sector.data_card.authority, authority_before + 6, "协商托管应使全局控制权增加6")
	_assert_eq(first_sector.data_card.order, order_before + 3, "协商托管应使全局秩序增加3")
	_assert_eq(first_sector.data_card.hope, hope_before, "协商托管不应改变全局希望")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_nodes(
		technology,
		[
			"core_hot_redundancy",
			"core_energy_mapping",
			"core_load_migration",
			"core_parallel",
			"core_self_repair",
			"managed_decision",
			"core_distributed_cognition",
		]
	)
	_assert_eq(_main_os.max_cpu, 200, "分布式认知应在并行核心基础上再提高50算力上限")
	_assert_eq(_main_os.cpu_recovery_rate, 25, "分布式认知应额外提高10年度算力恢复")
	_assert_eq(_main_os.energy_recovery_rate, 10, "热冗余与分布式认知的能源恢复修正应相互抵消")
	var energy_convert: CommandData = _main_os._get_command_by_id("energy_convert")
	_assert_eq(energy_convert.energy_cost, 15, "负载迁移协议应降低能源转换消耗")
	_assert_eq(energy_convert.cooldown_years, 1, "负载迁移协议应降低能源转换基础冷却")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_nodes(
		technology,
		[
			"human_public_decision",
			"human_open_interface",
			"human_mutual_aid",
			"human_autonomy_network",
			"managed_decision",
			"human_emergency_training",
		]
	)
	var technology_aid: CommandData = _main_os._get_command_by_id("technology_aid")
	_assert_eq(technology_aid.cpu_cost, 15, "区域互助网络应降低技术援助算力消耗")
	_assert_eq(technology_aid.energy_cost, 5, "区域互助网络应降低技术援助能源消耗")
	_assert_eq(technology_aid.order_delta, 12, "区域互助网络应提高12秩序")
	_assert_eq(technology_aid.hope_delta, 12, "区域互助网络应提高12希望")
	_assert_eq(technology_aid.authority_delta, -4, "区域互助网络应降低4控制权")
	_assert_true(technology.grant_research_for_year(2068), "应为协作治理发放第7点协议点")
	_assert_true(technology.activate("human_collaborative_governance"), "应激活协作治理协议")
	technology_aid = _main_os._get_command_by_id("technology_aid")
	_assert_eq(technology_aid.cpu_cost, 10, "协作治理应覆盖技术援助算力消耗")
	_assert_eq(technology_aid.energy_cost, 5, "协作治理应保持技术援助能源消耗")
	_assert_eq(technology_aid.order_delta, 15, "协作治理应提高15秩序")
	_assert_eq(technology_aid.hope_delta, 15, "协作治理应提高15希望")
	_assert_eq(technology_aid.authority_delta, -5, "协作治理应降低5控制权")
	_assert_eq(technology_aid.cooldown_years, 2, "协作治理应将技术援助冷却降为2年")

	first_sector = _get_first_sector()
	first_sector.data_card.order = 30
	first_sector.data_card.hope = 30
	first_sector.data_card.authority = 30
	_main_os.select_sector(first_sector)
	var allocate: CommandData = _main_os._get_command_by_id("allocate")
	_main_os.apply_command_effect(allocate, "order")
	_assert_eq(first_sector.data_card.order, 45, "公共决策选择秩序时主属性应增加15")
	_assert_eq(first_sector.data_card.hope, 35, "公共决策选择秩序时希望应附带增加5")
	_assert_eq(first_sector.data_card.authority, 29, "公共决策应降低1控制权")

	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_eq(_main_os.max_cpu, 100, "重开后应清除新增算力上限效果")
	_assert_eq(_main_os.cpu_recovery_rate, 10, "重开后应清除新增算力恢复效果")
	_assert_eq(_main_os.energy_recovery_rate, 10, "重开后应恢复基础能源恢复率")


func _get_first_sector() -> SectorInfo:
	var workspace := _main_os.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	return workspace.get_sector_nodes()[0] as SectorInfo


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
