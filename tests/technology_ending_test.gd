## 科技结局集成测试
## 验证共存、托管、人类自主、失败和控制权归零判定
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

## 创建主场景并执行四类结局与失败条件断言
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	_main_os = scene.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	var technology: TechnologySystem = _main_os.get_node("%TechnologySystem")
	_activate_route(
		technology,
		[
			"managed_decision",
			"core_energy_mapping",
			"managed_infrastructure",
			"core_parallel",
			"managed_global_network",
			"core_self_repair",
		]
	)
	_assert_eq(
		_main_os.determine_ending_type(35, 45, 45),
		"coexistence",
		"混合路线无结局核心且社会稳定应进入共存"
	)

	_main_os.restart_game_for_test()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_route(
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
	_assert_eq(
		_main_os.determine_ending_type(20, 55, 55),
		"human_autonomy",
		"文明自持且低控制高社会状态应进入人类自主"
	)
	_assert_true(
		not _main_os.should_fail_from_authority(0, 45, 45),
		"文明自持且秩序希望达40时控制权归零不应立即失败"
	)

	_main_os.restart_game_for_test()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_route(
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
	_assert_eq(
		_main_os.determine_ending_type(55, 45, 45),
		"managed",
		"托管核心且高控制权应进入MOSS托管"
	)

	_main_os.restart_game_for_test()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_route(
		technology,
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
	_assert_eq(
		_main_os.determine_ending_type(30, 35, 50),
		"failed",
		"核心演化路线但社会状态未达40时应失败"
	)
	_assert_true(
		_main_os.should_fail_from_authority(0, 60, 60),
		"未激活文明自持时控制权归零应立即失败"
	)

	_assert_alternative_terminal_endings()
	_assert_ending_message_reads_event_history()
	print("[MOSS-TECH-ENDING] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)

# ============================================================
# 测试辅助方法
# ============================================================

## 校验三个新增MOSS终端会进入摘要，但不会解锁旧路线专属结局
func _assert_alternative_terminal_endings() -> void:
	var technology: TechnologySystem

	_main_os.restart_game_for_test()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_route(
		technology,
		[
			"managed_decision",
			"managed_behavior_prediction",
			"managed_infrastructure",
			"managed_global_network",
			"managed_authority_audit",
			"core_energy_mapping",
			"managed_consensual_protocol",
		]
	)
	_assert_eq(
		_main_os.determine_ending_type(55, 50, 50),
		"coexistence",
		"协商托管协议不应解锁MOSS托管结局"
	)
	_assert_true("协商托管协议" in _main_os._get_technology_summary(), "结局摘要应显示协商托管协议")

	_main_os.restart_game_for_test()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_route(
		technology,
		[
			"core_energy_mapping",
			"core_hot_redundancy",
			"core_parallel",
			"core_self_repair",
			"core_load_migration",
			"managed_decision",
			"core_distributed_cognition",
		]
	)
	_assert_eq(
		_main_os.determine_ending_type(30, 50, 50),
		"coexistence",
		"分布式认知不应新增独立结局"
	)
	_assert_true("分布式认知" in _main_os._get_technology_summary(), "结局摘要应显示分布式认知")

	_main_os.restart_game_for_test()
	technology = _main_os.get_node("%TechnologySystem")
	_activate_route(
		technology,
		[
			"human_open_interface",
			"human_public_decision",
			"human_autonomy_network",
			"human_emergency_training",
			"human_mutual_aid",
			"core_energy_mapping",
			"human_collaborative_governance",
		]
	)
	_assert_eq(
		_main_os.determine_ending_type(20, 55, 55),
		"coexistence",
		"协作治理协议不应解锁人类自主结局"
	)
	_assert_true("协作治理协议" in _main_os._get_technology_summary(), "结局摘要应显示协作治理协议")


## 校验结局解释会读取代表性 event_state，但不改变结局判定
func _assert_ending_message_reads_event_history() -> void:
	_main_os.restart_game_for_test()
	_assert_true(
		_main_os.has_method("build_ending_message"),
		"MainOS 应提供 build_ending_message 供结局解释和测试复用"
	)
	if not _main_os.has_method("build_ending_message"):
		return

	var base_message: String = _main_os.call("build_ending_message", "coexistence")
	_assert_eq(
		base_message,
		"MOSS 与人类保持有限协作。\n文明在控制与自主之间继续前进。",
		"没有轻量事件状态时共存结局应保持原有短文本"
	)

	_main_os.set_event_state("event_state.mid_07_migration_priority", "humanitarian")
	_main_os.set_event_state("event_state.mid_09_yaa_sample_access", "audited_access")
	_main_os.set_event_state("event_state.mid_12_digital_life_leak", "technical_disclosure")
	_main_os.set_event_state("event_state.mid_14_heat_shield_shortage", "rear_reallocation")
	_main_os.set_event_state("event_state.mid_17_final_authorization", "negotiated_trusteeship")

	var history_message: String = _main_os.call("build_ending_message", "coexistence")
	_assert_true(
		"历史回顾" in history_message,
		"存在代表性 event_state 时结局解释应追加历史回顾段落"
	)
	_assert_true(
		not "[color" in history_message and not "[/color]" in history_message,
		"结局解释会写入普通 Label，不应包含 BBCode 颜色标签"
	)
	_assert_true(
		"人道迁移记录" in history_message,
		"结局解释应读取 2053 民生迁移事实"
	)
	_assert_true(
		"受审计访问" in history_message,
		"结局解释应读取 2058 数字生命样本事实"
	)
	_assert_true(
		"技术说明" in history_message,
		"结局解释应读取 2065 数字生命审查事实"
	)
	_assert_true(
		"后方资源" in history_message,
		"结局解释应读取 2070 工程资源事实"
	)
	_assert_true(
		"协商托管框架" in history_message,
		"结局解释应读取 2075 最终授权事实"
	)
	_assert_eq(
		_main_os.determine_ending_type(35, 45, 45),
		"coexistence",
		"结局解释读取 event_state 不应改变结局判定"
	)


## 按顺序激活结局路线节点，并在需要时发放研究点
func _activate_route(technology: TechnologySystem, node_ids: Array[String]) -> void:
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
