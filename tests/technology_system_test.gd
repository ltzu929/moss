## 科技系统单元测试
## 验证节点图、协议点、阶段推进、激活约束、标签、快照和重置
extends Node

# ============================================================
# 常量
# ============================================================

## 被测科技系统脚本
const TECHNOLOGY_SYSTEM_SCRIPT := preload(
	"res://scripts/systems/technology_system.gd"
)

# ============================================================
# 测试状态
# ============================================================

## 失败断言数量，同时作为进程退出码
var _failed: int = 0

# ============================================================
# 测试入口
# ============================================================

## 创建科技系统并依次执行全部断言
func _ready() -> void:
	var system: TechnologySystem = TECHNOLOGY_SYSTEM_SCRIPT.new()
	add_child(system)
	system.load_nodes_from_disk()

	_assert_eq(system.get_all_nodes().size(), 12, "应加载12个科技节点")
	_assert_eq(system.get_available_points(), 1, "开局应有1个协议点")
	_assert_eq(system.get_stage(), TechNodeData.Stage.C550, "开局形态应为550C")
	_assert_true(system.validate_graph().is_empty(), "科技节点图应完整且无环")

	for year in [2048, 2052, 2056, 2060, 2064, 2068, 2072]:
		_assert_true(system.grant_research_for_year(year), "%d年应发放协议点" % year)
		_assert_true(
			not system.grant_research_for_year(year),
			"%d年不得重复发放协议点" % year
		)
	_assert_eq(system.get_available_points(), 8, "整局最多应获得8个协议点")

	system.reset()
	_assert_true(system.activate("managed_decision"), "应能激活首个550C节点")
	_assert_eq(system.get_stage(), TechNodeData.Stage.C550, "1个节点仍为550C")
	system.grant_research_for_year(2048)
	_assert_true(system.activate("core_energy_mapping"), "应能跨路线激活节点")
	_assert_eq(system.get_stage(), TechNodeData.Stage.W550, "2个节点应进入550W")

	system.grant_research_for_year(2052)
	_assert_true(
		not system.activate("managed_irreplaceable_protocol"),
		"未满足前置时不得激活核心节点"
	)
	_assert_true(system.activate("managed_infrastructure"), "应激活托管分支节点")
	system.grant_research_for_year(2056)
	_assert_true(system.activate("managed_global_network"), "应激活托管另一分支")
	system.grant_research_for_year(2060)
	_assert_true(system.activate("core_parallel"), "应激活第五个节点")
	_assert_true(
		not system.activate("managed_irreplaceable_protocol"),
		"未进入MOSS阶段时不得激活核心节点"
	)
	system.grant_research_for_year(2064)
	_assert_true(system.activate("core_self_repair"), "应激活第六个节点")
	_assert_eq(system.get_stage(), TechNodeData.Stage.MOSS, "6个节点应进入MOSS")
	system.grant_research_for_year(2068)
	_assert_true(system.activate("managed_irreplaceable_protocol"), "第7点应能激活托管核心")
	_assert_true(system.has_tag("managed_core"), "核心节点应输出科技标签")
	_assert_true(not system.activate("core_self_repair"), "节点不得重复激活")

	var snapshot := system.export_state()
	_assert_eq(snapshot["stage"], TechNodeData.Stage.MOSS, "快照应包含形态")
	_assert_eq(snapshot["active_node_ids"].size(), 7, "快照应包含激活节点")

	system.reset()
	_assert_eq(system.get_available_points(), 1, "重置后恢复1个协议点")
	_assert_eq(system.get_active_node_ids().size(), 0, "重置后清空节点")
	_assert_eq(system.get_stage(), TechNodeData.Stage.C550, "重置后恢复550C")

	get_tree().quit(_failed)

# ============================================================
# 断言辅助方法
# ============================================================

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
