## 随机局势领域测试：资源、并发、方针、持续成本、指令干预与固定种子。
extends Node

const SITUATION_PATHS: Array[String] = [
	"res://data/situations/emergency_communication_congestion.tres",
	"res://data/situations/regional_power_instability.tres",
	"res://data/situations/underground_life_support_fault.tres",
]

var _failed: int = 0
var _templates: Array[SituationData] = []


func _ready() -> void:
	_load_templates()
	_assert_content_contract()
	_assert_concurrency_and_approach_switching()
	_assert_unfunded_growth_and_stage_pause()
	_assert_command_intervention_and_outcome()
	_assert_fixed_seed_export()

	print("[MOSS-SITUATION-SYSTEM] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


func _load_templates() -> void:
	for path in SITUATION_PATHS:
		var data := load(path) as SituationData
		_assert_true(data != null, "局势资源应能加载：%s" % path)
		if data != null:
			_templates.append(data)


func _assert_content_contract() -> void:
	_assert_eq(_templates.size(), 3, "首版应包含三类随机局势")
	var ids: Array[String] = []
	for data in _templates:
		ids.append(data.situation_id)
		_assert_eq(data.approaches.size(), 3, "%s 应提供三种局势专属方针" % data.title)
		_assert_true(not data.command_interventions.is_empty(), "%s 应响应现有指令" % data.title)
		_assert_true(
			"联合政府" not in data.eligible_regions,
			"%s 不应生成在地图外目标" % data.title
		)
	_assert_true("regional_power_instability" in ids, "应包含区域电网负荷失衡")
	_assert_true("emergency_communication_congestion" in ids, "应包含应急通信拥塞")
	_assert_true("underground_life_support_fault" in ids, "应包含地下城维生异常")


func _assert_concurrency_and_approach_switching() -> void:
	var system := _new_system(20260714)
	var first := system.start_situation_for_test(
		"regional_power_instability", "亚洲", 2044, 7
	)
	var duplicate_region := system.start_situation_for_test(
		"emergency_communication_congestion", "亚洲", 2044, 7
	)
	var second := system.start_situation_for_test(
		"emergency_communication_congestion", "北美", 2044, 7
	)
	var third := system.start_situation_for_test(
		"underground_life_support_fault", "非洲", 2044, 7
	)
	_assert_true(not first.is_empty(), "第一项局势应能启动")
	_assert_true(duplicate_region.is_empty(), "同一地区同时最多一项局势")
	_assert_true(not second.is_empty(), "不同地区应允许第二项局势")
	_assert_true(third.is_empty(), "全局同时最多两项局势")

	var first_id := str(first.get("instance_id", ""))
	var initial := system.set_approach(first_id, "local_repair", 20)
	_assert_true(bool(initial.get("success", false)), "首次选择方针应成功")
	_assert_eq(int(initial.get("new_cpu", -1)), 20, "首次选择方针不收重配置成本")
	var switched := system.set_approach(first_id, "grid_takeover", 20)
	_assert_true(bool(switched.get("success", false)), "未锁定时应允许切换方针")
	_assert_eq(int(switched.get("new_cpu", -1)), 15, "切换方针应消耗 5 算力")
	var locked := system.set_approach(first_id, "rolling_ration", 15)
	_assert_true(not bool(locked.get("success", true)), "重配置锁定期间不得再次切换")

	var second_id := str(second.get("instance_id", ""))
	system.set_approach(second_id, "priority_routing", 15, 1)
	var forecasts := system.get_active_snapshots(1, 1)
	_assert_true(
		not bool(forecasts[0].get("is_funded", true)),
		"共享资源不足时，后结算的局势不应继续显示供给充足"
	)
	_assert_true(
		bool(forecasts[1].get("is_funded", false)),
		"共享资源应按真实月结算顺序分配给先结算的局势"
	)


func _assert_unfunded_growth_and_stage_pause() -> void:
	var system := _new_system(17)
	var started := system.start_situation_for_test(
		"underground_life_support_fault", "非洲", 2045, 3
	)
	var instance_id := str(started.get("instance_id", ""))
	system.set_approach(instance_id, "automated_trusteeship", 20)
	var sector := _create_sector("非洲")
	var sectors: Array[SectorData] = [sector]
	var result := system.process_month(sectors, 0, 0, false, 2045, 4)
	var snapshots: Array = result.get("situations", [])
	_assert_eq(int(snapshots[0].get("severity", -1)), 40, "持续成本不足时严重度应额外恶化")
	_assert_eq(
		int(snapshots[0].get("expected_monthly_delta", -1)),
		6,
		"断供后的预计趋势应按真实规则显示恶化"
	)
	_assert_true(bool(snapshots[0].get("funding_known", false)), "月结算快照应包含供给状态")
	_assert_true(not bool(snapshots[0].get("is_funded", true)), "断供快照应明确标记供给不足")
	_assert_eq(int(result.get("new_cpu", -1)), 0, "资源不足不应产生负算力")
	var types := _notification_types(result.get("notifications", []))
	_assert_true("unfunded" in types, "首次断供应生成持续成本不足记录")
	_assert_true("stage_worsened" in types, "跨入恶化阶段应生成自动暂停通知")


func _assert_command_intervention_and_outcome() -> void:
	var system := _new_system(31)
	var sector := _create_sector("亚洲")
	var sectors: Array[SectorData] = [sector]
	var started := system.start_situation_for_test(
		"regional_power_instability", "亚洲", 2046, 1
	)
	var instance_id := str(started.get("instance_id", ""))
	system.set_approach(instance_id, "local_repair", 20)
	var first := system.apply_command_intervention("energy_convert", "亚洲", sectors)
	_assert_eq(int(first["situations"][0].get("severity", -1)), 18, "现有指令应一次性降低局势严重度")
	var second := system.apply_command_intervention("energy_convert", "亚洲", sectors)
	_assert_eq(system.get_active_count(), 0, "严重度降至 0 后局势应结算并移除")
	_assert_true("resolved" in _notification_types(second.get("notifications", [])), "安全结算应生成记录")
	_assert_eq(sector.order, 53, "成功结算应叠加局势与所选方针的秩序恢复")
	_assert_eq(sector.hope, 54, "成功结算应叠加局势与所选方针的希望恢复")
	_assert_eq(sector.authority, 49, "地方抢修结算应轻微降低控制权")


func _assert_fixed_seed_export() -> void:
	var system := _new_system(424242)
	_assert_eq(int(system.export_state().get("seed", 0)), 424242, "固定种子应进入可保存运行时快照")


func _new_system(seed: int) -> SituationSystem:
	var system := SituationSystem.new()
	system.configure_templates(_templates)
	system.reset(seed)
	return system


func _create_sector(region_name: String) -> SectorData:
	var sector := SectorData.new()
	sector.region_name = region_name
	sector.order = 50
	sector.hope = 50
	sector.authority = 50
	return sector


func _notification_types(notifications: Array) -> Array[String]:
	var result: Array[String] = []
	for notification in notifications:
		result.append(str(notification.get("type", "")))
	return result


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(actual == expected, "%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)])
