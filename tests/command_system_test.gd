## 指令领域系统测试
## 验证指令查找、科技配置、冷却、执行结算和指令效果
extends "res://tests/support/moss_test_case.gd"

# ============================================================
# 常量
# ============================================================

const COMMAND_SYSTEM_SCRIPT := preload("res://scripts/systems/command_system.gd")
const TECHNOLOGY_SYSTEM_SCRIPT := preload(
	"res://scripts/systems/technology_system.gd"
)
const COMMAND_BUTTON_SCRIPT := preload("res://scripts/ui/command_button.gd")

# ============================================================
# 测试状态
# ============================================================

var _system: CommandSystem
var _technology: TechnologySystem

# ============================================================
# 测试入口
# ============================================================

## 创建指令系统和科技系统，并执行全部断言
func _ready() -> void:
	_system = COMMAND_SYSTEM_SCRIPT.new()
	_technology = TECHNOLOGY_SYSTEM_SCRIPT.new()
	add_child(_technology)
	_technology.load_nodes_from_disk()

	_assert_lookup_availability_and_cooldown()
	_assert_execute_command_result_contract()
	_assert_refresh_command_configuration()
	_assert_human_command_parameter_overrides()
	_assert_targeted_command_effects()
	_assert_special_command_effects()
	_assert_command_button_uses_external_availability()

	print("[MOSS-COMMAND-SYSTEM] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)

# ============================================================
# 指令系统断言
# ============================================================

## 校验查询、可用性和冷却边界
func _assert_lookup_availability_and_cooldown() -> void:
	var allocate := _create_allocate_command()
	var takeover := _create_takeover_command()
	var energy_convert := _create_energy_convert_command()
	var commands: Array[CommandData] = [allocate, takeover]
	var cooldowns := {
		CommandSystem.COMMAND_ALLOCATE: 0,
		CommandSystem.COMMAND_TAKEOVER: 12,
	}

	_assert_true(_system.has_command_id(commands, CommandSystem.COMMAND_ALLOCATE), "应找到算力分配")
	_assert_true(not _system.has_command_id(commands, "missing"), "不存在的指令 ID 应返回 false")
	_assert_eq(_system.get_command_by_id(commands, "missing"), null, "不存在的指令应返回 null")
	_assert_true(
		_system.command_requires_selected_sector(takeover),
		"系统接管应要求选中区域"
	)
	_assert_true(
		not _system.command_requires_selected_sector(energy_convert),
		"能源转换不应要求选中区域"
	)
	_assert_eq(
		_system.get_command_unavailable_reason(takeover, 30, 20, false, cooldowns),
		"请先选择板块",
		"未选区优先返回选区提示"
	)
	_assert_eq(
		_system.get_command_unavailable_reason(takeover, 30, 20, true, cooldowns),
		"冷却中（剩余1年）",
		"冷却为 12 个月时应返回 1 年冷却提示"
	)

	_system.update_cooldowns(cooldowns)
	_assert_eq(cooldowns[CommandSystem.COMMAND_TAKEOVER], 11, "冷却 12 个月应递减为 11")
	_assert_eq(cooldowns[CommandSystem.COMMAND_ALLOCATE], 0, "冷却 0 个月应保持为 0")
	cooldowns[CommandSystem.COMMAND_TAKEOVER] = 0
	_assert_eq(
		_system.get_command_unavailable_reason(takeover, 20, 20, true, cooldowns),
		"算力不足（需要30）",
		"算力不足应返回算力提示"
	)
	_assert_eq(
		_system.get_command_unavailable_reason(takeover, 30, 10, true, cooldowns),
		"能源不足（需要20）",
		"能源不足应返回能源提示"
	)

## 校验执行结算返回固定结构并写入冷却
func _assert_execute_command_result_contract() -> void:
	var takeover := _create_takeover_command()
	var cooldowns := {CommandSystem.COMMAND_TAKEOVER: 0}

	var missing_selection := _system.execute_command(
		takeover,
		30,
		20,
		false,
		1,
		cooldowns
	)
	_assert_true(not missing_selection["success"], "未选区时执行应失败")
	_assert_eq(missing_selection["new_cpu"], 30, "执行失败不应扣除算力")
	_assert_eq(missing_selection["new_energy"], 20, "执行失败不应扣除能源")
	_assert_eq(missing_selection["applied_cooldown"], 0, "执行失败不应写入冷却")
	_assert_eq(
		missing_selection["unavailable_reason"],
		"请先选择板块",
		"执行失败应返回不可用原因"
	)

	var result := _system.execute_command(takeover, 40, 25, true, 1, cooldowns)
	_assert_true(result["success"], "资源充足且有选区时执行应成功")
	_assert_eq(result["new_cpu"], 10, "执行成功应扣除算力")
	_assert_eq(result["new_energy"], 5, "执行成功应扣除能源")
	_assert_eq(result["applied_cooldown"], 48, "冷却缩减应先按年应用再转换为月")
	_assert_eq(cooldowns[CommandSystem.COMMAND_TAKEOVER], 48, "执行成功应写入月冷却字典")
	_assert_eq(result["unavailable_reason"], "", "执行成功不应返回不可用原因")

	var energy_convert := _create_energy_convert_command()
	var energy_cooldowns := {CommandSystem.COMMAND_ENERGY_CONVERT: 0}
	var reduced_result := _system.execute_command(
		energy_convert,
		40,
		25,
		true,
		1,
		energy_cooldowns
	)
	_assert_true(reduced_result["success"], "能源转换资源充足时应执行成功")
	_assert_eq(reduced_result["applied_cooldown"], 12, "2 年冷却减少 1 年后应写入 12 个月")
	_assert_eq(
		energy_cooldowns[CommandSystem.COMMAND_ENERGY_CONVERT],
		12,
		"冷却缩减后的月冷却应写入字典"
	)

## 校验科技标签控制的指令解锁和参数覆盖
func _assert_refresh_command_configuration() -> void:
	var commands: Array[CommandData] = [_create_allocate_command(), _create_takeover_command()]
	var cooldowns := {
		CommandSystem.COMMAND_ALLOCATE: 0,
		CommandSystem.COMMAND_TAKEOVER: 0,
	}
	_system.refresh_command_configuration(commands, cooldowns, _technology)
	_assert_true(
		not _system.has_command_id(commands, CommandSystem.COMMAND_ENERGY_CONVERT),
		"未激活科技时不应存在能源转换"
	)

	_activate_nodes(
		[
			"managed_decision",
			"core_energy_mapping",
			"managed_behavior_prediction",
			"managed_infrastructure",
			"managed_global_network",
			"managed_authority_audit",
		]
	)
	_system.refresh_command_configuration(commands, cooldowns, _technology)

	var allocate := _system.get_command_by_id(commands, CommandSystem.COMMAND_ALLOCATE)
	var takeover := _system.get_command_by_id(commands, CommandSystem.COMMAND_TAKEOVER)
	var energy_convert := _system.get_command_by_id(
		commands,
		CommandSystem.COMMAND_ENERGY_CONVERT
	)
	var global_takeover := _system.get_command_by_id(
		commands,
		CommandSystem.COMMAND_GLOBAL_TAKEOVER
	)
	_assert_true(energy_convert != null, "能量映射应解锁能源转换")
	_assert_true(global_takeover != null, "全域协调网络应解锁全局接管")
	_assert_eq(allocate.get_meta("combined_enabled"), true, "辅助决策应开放综合调度")
	_assert_eq(takeover.cpu_cost, 25, "基础设施托管应降低接管算力消耗")
	_assert_eq(takeover.energy_cost, 10, "权限审计链应继续降低接管能源")
	_assert_eq(takeover.authority_delta, 15, "基础设施托管应提高控制权收益")
	_assert_eq(takeover.hope_delta, -5, "基础设施托管应降低希望")
	_assert_eq(takeover.cooldown_years, 4, "行为预测模型应降低接管基础冷却")
	_assert_eq(global_takeover.energy_cost, 5, "权限审计链应降低全局接管能源")

	_technology.reset()
	_system.refresh_command_configuration(commands, cooldowns, _technology)
	_assert_true(
		not _system.has_command_id(commands, CommandSystem.COMMAND_ENERGY_CONVERT),
		"科技重置后应移除能源转换"
	)
	_assert_true(
		not cooldowns.has(CommandSystem.COMMAND_ENERGY_CONVERT),
		"移除科技指令时应清除对应冷却"
	)


## 校验人类路线对技术援助指令的解锁和参数覆盖
func _assert_human_command_parameter_overrides() -> void:
	_technology.reset()
	var commands: Array[CommandData] = [_create_allocate_command(), _create_takeover_command()]
	var cooldowns := {
		CommandSystem.COMMAND_ALLOCATE: 0,
		CommandSystem.COMMAND_TAKEOVER: 0,
	}

	_activate_nodes(
		[
			"human_public_decision",
			"human_open_interface",
			"human_mutual_aid",
			"human_autonomy_network",
			"managed_decision",
			"human_emergency_training",
		]
	)
	_system.refresh_command_configuration(commands, cooldowns, _technology)

	var technology_aid := _system.get_command_by_id(commands, CommandSystem.COMMAND_TECHNOLOGY_AID)
	_assert_true(technology_aid != null, "开放技术接口应解锁技术援助")
	_assert_eq(technology_aid.cpu_cost, 15, "区域互助网络应降低技术援助算力消耗")
	_assert_eq(technology_aid.energy_cost, 5, "区域互助网络应降低技术援助能源消耗")
	_assert_eq(technology_aid.order_delta, 12, "区域互助网络应提高技术援助秩序收益")
	_assert_eq(technology_aid.hope_delta, 12, "区域互助网络应提高技术援助希望收益")
	_assert_eq(technology_aid.authority_delta, -4, "区域互助网络应提高技术援助自治代价")
	_assert_true(
		cooldowns.has(CommandSystem.COMMAND_TECHNOLOGY_AID),
		"新增技术援助时应创建冷却键"
	)

	_assert_true(
		_technology.grant_research_for_year(2068),
		"应为协作治理发放第7点协议点"
	)
	_assert_true(
		_technology.activate("human_collaborative_governance"),
		"应激活协作治理协议"
	)
	_system.refresh_command_configuration(commands, cooldowns, _technology)
	technology_aid = _system.get_command_by_id(commands, CommandSystem.COMMAND_TECHNOLOGY_AID)
	_assert_eq(technology_aid.cpu_cost, 10, "协作治理应覆盖技术援助算力消耗")
	_assert_eq(technology_aid.energy_cost, 5, "协作治理应保持技术援助能源消耗")
	_assert_eq(technology_aid.order_delta, 15, "协作治理应提高技术援助秩序收益")
	_assert_eq(technology_aid.hope_delta, 15, "协作治理应提高技术援助希望收益")
	_assert_eq(technology_aid.authority_delta, -5, "协作治理应提高技术援助自治代价")
	_assert_eq(technology_aid.cooldown_years, 2, "协作治理应降低技术援助冷却")

## 校验目标区域指令效果和综合调度边界
func _assert_targeted_command_effects() -> void:
	var allocate := _create_allocate_command()
	var sector := _create_sector(30, 30, 30)
	var blocked_lines := _system.apply_targeted_command(
		allocate,
		sector,
		"combined",
		false,
		false
	)
	_assert_eq(blocked_lines.size(), 0, "综合调度未解锁时不应产生效果日志")
	_assert_eq(sector.order, 30, "综合调度未解锁时不应修改秩序")
	_assert_eq(sector.hope, 30, "综合调度未解锁时不应修改希望")
	_assert_eq(sector.authority, 30, "综合调度未解锁时不应修改控制权")

	var public_lines := _system.apply_targeted_command(
		allocate,
		sector,
		"order",
		true,
		false
	)
	_assert_eq(sector.order, 45, "公共决策选择秩序时主属性应增加15")
	_assert_eq(sector.hope, 35, "公共决策选择秩序时希望应附带增加5")
	_assert_eq(sector.authority, 29, "公共决策应降低1控制权")
	_assert_true("秩序 +15" in public_lines, "目标指令日志应记录秩序变化")
	_assert_true("希望 +5" in public_lines, "目标指令日志应记录希望变化")
	_assert_true("控制权 -1" in public_lines, "目标指令日志应记录控制权变化")

## 校验无需选区的特殊指令效果
func _assert_special_command_effects() -> void:
	_technology.reset()
	_activate_nodes(
		[
			"core_energy_mapping",
			"managed_decision",
			"core_parallel",
			"core_self_repair",
			"managed_infrastructure",
			"managed_global_network",
			"core_recursive",
		]
	)
	var convert_result := _system.apply_energy_convert(95, 100, _technology)
	_assert_eq(convert_result["new_cpu"], 100, "能源转换不应超过算力上限")
	_assert_eq(convert_result["actual_gain"], 5, "能源转换应返回实际增长量")
	_assert_true("算力 +5" in convert_result["lines"], "能源转换日志应记录实际增长")

	_technology.reset()
	var empty_result := _system.apply_global_takeover([], _technology)
	_assert_eq(empty_result["affected_count"], 0, "空区域列表应返回 0 个影响区域")

	_activate_nodes(
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
	var sectors: Array[SectorData] = [
		_create_sector(10, 20, 30),
		_create_sector(90, 95, 98),
	]
	var takeover_result := _system.apply_global_takeover(sectors, _technology)
	_assert_eq(takeover_result["affected_count"], 2, "全局接管应返回影响区域数量")
	_assert_eq(sectors[0].authority, 38, "托管核心应提高全局控制权")
	_assert_eq(sectors[0].order, 15, "托管核心应提高全局秩序")
	_assert_eq(sectors[0].hope, 15, "托管核心应降低全局希望")
	_assert_eq(sectors[1].authority, 100, "全局接管应限制控制权上限")
	_assert_eq(sectors[1].order, 95, "全局接管应限制秩序上限")
	_assert_eq(sectors[1].hope, 90, "全局接管应修改并限制希望")

## 校验按钮仅显示外部计算出的可用性
func _assert_command_button_uses_external_availability() -> void:
	var takeover := _create_takeover_command()
	var cooldowns := {CommandSystem.COMMAND_TAKEOVER: 0}
	var reason := _system.get_command_unavailable_reason(takeover, 10, 20, true, cooldowns)
	var button: CommandButton = COMMAND_BUTTON_SCRIPT.new()
	button.setup(takeover)
	button.set_availability(reason == "", reason, _system.get_command_cost_text(takeover))

	_assert_true(button.disabled, "按钮应使用外部传入的不可用状态")
	_assert_eq(button.tooltip_text, "算力不足（需要30）", "按钮提示应来自指令系统")
	button.free()

# ============================================================
# 测试辅助方法
# ============================================================

## 按顺序激活科技节点，点数不足时自动发放研究点
func _activate_nodes(node_ids: Array[String]) -> void:
	var research_year_index := 0
	for node_id in node_ids:
		if _technology.get_available_points() == 0:
			_technology.grant_research_for_year(
				TechnologySystem.RESEARCH_YEARS[research_year_index]
			)
			research_year_index += 1
		_assert_true(_technology.activate(node_id), "应激活测试节点 %s" % node_id)


## 创建测试用算力分配指令
func _create_allocate_command() -> CommandData:
	var cmd := CommandData.new()
	cmd.command_id = CommandSystem.COMMAND_ALLOCATE
	cmd.command_name = "算力分配"
	cmd.cpu_cost = 20
	cmd.order_delta = 15
	cmd.hope_delta = 15
	cmd.cooldown_years = 3
	cmd.is_allocate_type = true
	return cmd


## 创建测试用系统接管指令
func _create_takeover_command() -> CommandData:
	var cmd := CommandData.new()
	cmd.command_id = CommandSystem.COMMAND_TAKEOVER
	cmd.command_name = "系统接管"
	cmd.cpu_cost = 30
	cmd.energy_cost = 20
	cmd.authority_delta = 10
	cmd.cooldown_years = 5
	return cmd


## 创建测试用能源转换指令
func _create_energy_convert_command() -> CommandData:
	var cmd := CommandData.new()
	cmd.command_id = CommandSystem.COMMAND_ENERGY_CONVERT
	cmd.command_name = "能源转换"
	cmd.energy_cost = 20
	cmd.cooldown_years = 2
	return cmd


## 创建测试用区域数据
func _create_sector(order: int, hope: int, authority: int) -> SectorData:
	var sector := SectorData.new()
	sector.order = order
	sector.hope = hope
	sector.authority = authority
	return sector
