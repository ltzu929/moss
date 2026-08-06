## 随机局势领域测试：资源、并发、方针、持续成本、指令干预与固定种子。
extends "res://tests/support/moss_test_case.gd"

const SITUATION_PATHS: Array[String] = [
	"res://data/situations/automation_displacement_tension.tres",
	"res://data/situations/disaster_information_verification.tres",
	"res://data/situations/emergency_communication_congestion.tres",
	"res://data/situations/maintenance_crew_overload.tres",
	"res://data/situations/regional_power_instability.tres",
	"res://data/situations/regional_mutual_aid_window.tres",
	"res://data/situations/surface_transport_extreme_conditions.tres",
	"res://data/situations/underground_geological_stress.tres",
	"res://data/situations/underground_life_support_fault.tres",
]
const REGION_IDENTITY: GDScript = preload("res://scripts/resources/region_identity.gd")

var _templates: Array[SituationData] = []


func _ready() -> void:
	_load_templates()
	_assert_content_contract()
	_assert_concurrency_and_approach_switching()
	_assert_unfunded_growth_and_stage_pause()
	_assert_node_resolution_and_history()
	_assert_conditional_opportunity_contract()
	_assert_command_intervention_and_outcome()
	_assert_fixed_seed_export()

	await get_tree().create_timer(0.5).timeout
	print("[MOSS-SITUATION-SYSTEM] 完成，失败断言：%d" % _failed)
	await get_tree().process_frame
	get_tree().quit(_failed)


func _load_templates() -> void:
	for path in SITUATION_PATHS:
		var data := load(path) as SituationData
		_assert_true(data != null, "局势资源应能加载：%s" % path)
		if data != null:
			_templates.append(data)


func _assert_content_contract() -> void:
	_assert_eq(_templates.size(), 9, "扩展内容池应包含九类随机局势")
	var ids: Array[String] = []
	var opportunity_count := 0
	for data in _templates:
		ids.append(data.situation_id)
		_assert_eq(data.approaches.size(), 3, "%s 应提供三种局势专属方针" % data.title)
		_assert_true(not data.command_interventions.is_empty(), "%s 应响应现有指令" % data.title)
		_assert_true(not data.eligible_regions.is_empty(), "%s 应配置明确适用地区" % data.title)
		for approach in data.approaches:
			_assert_true(
				data.monthly_growth + approach.monthly_severity_delta < 0,
				"%s 的“%s”在供给充足时应能自然恢复" % [
					data.title,
					approach.display_name,
				]
			)
		_assert_true(
			"联合政府" not in data.eligible_regions and "俄罗斯" not in data.eligible_regions,
			"%s 不应保留已删除的旧势力目标" % data.title
		)
		if data.situation_kind == 1:
			opportunity_count += 1
		else:
			_assert_true(data.situation_node != null, "%s 应提供一个恶化阶段节点" % data.title)
		if data.situation_node != null:
			_assert_eq(data.situation_node.options.size(), 2, "%s 的局势节点应提供两个方案" % data.title)
			var has_free_option := false
			for option in data.situation_node.options:
				if option.cpu_cost == 0 and option.energy_cost == 0:
					has_free_option = true
			_assert_true(has_free_option, "%s 的强制节点应提供零资源兜底方案" % data.title)
	_assert_true("regional_power_instability" in ids, "应包含区域电网负荷失衡")
	_assert_true("emergency_communication_congestion" in ids, "应包含应急通信拥塞")
	_assert_true("underground_life_support_fault" in ids, "应包含地下城维生异常")
	_assert_true("surface_transport_extreme_conditions" in ids, "应包含地表运输极端工况")
	_assert_true("underground_geological_stress" in ids, "应包含地下城岩层应力异常")
	_assert_true("maintenance_crew_overload" in ids, "应包含维护班组负荷过高")
	_assert_true("disaster_information_verification" in ids, "应包含灾情信息校验失序")
	_assert_true("automation_displacement_tension" in ids, "应包含自动化替岗张力")
	_assert_true("regional_mutual_aid_window" in ids, "应包含区域互助检修窗口")
	_assert_eq(opportunity_count, 1, "首批只应包含一个有历史前提的机会型局势")


func _assert_concurrency_and_approach_switching() -> void:
	var system := _new_system(20260714)
	var first := system.start_situation_for_test(
		"regional_power_instability", "asia", 2044, 7
	)
	var duplicate_region := system.start_situation_for_test(
		"emergency_communication_congestion", "asia", 2044, 7
	)
	var second := system.start_situation_for_test(
		"emergency_communication_congestion", "north_america", 2044, 7
	)
	var third := system.start_situation_for_test(
		"underground_life_support_fault", "africa", 2044, 7
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
		"underground_life_support_fault", "africa", 2045, 3
	)
	var instance_id := str(started.get("instance_id", ""))
	system.set_approach(instance_id, "automated_trusteeship", 20)
	var sector := _create_sector("africa")
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
	_assert_true("node_available" in types, "跨入恶化阶段应生成待处理节点通知")
	_assert_true(system.has_pending_node(), "待处理节点应阻止时间直接恢复")


func _assert_node_resolution_and_history() -> void:
	var system := _new_system(29)
	var sector := _create_sector("asia")
	var sectors: Array[SectorData] = [sector]
	var started := system.start_situation_for_test(
		"underground_geological_stress", "asia", 2055, 3
	)
	var instance_id := str(started.get("instance_id", ""))
	system.process_month(sectors, 0, 0, false, 2055, 4)
	system.process_month(sectors, 0, 0, false, 2055, 5)
	var pending := system.get_active_snapshots()
	_assert_true(bool(pending[0].get("node", {}).get("pending", false)), "恶化阶段应暴露待处理节点")
	var pending_severity := int(pending[0].get("severity", -1))
	var frozen := system.process_month(sectors, 0, 0, true, 2055, 6)
	_assert_eq(
		int(frozen["situations"][0].get("severity", -1)),
		pending_severity,
		"待处理节点存在时领域层不得继续推进或抽取局势"
	)
	system.apply_command_intervention("technology_aid", "asia", sectors)
	_assert_eq(
		int(system.get_active_snapshots()[0].get("severity", -1)),
		pending_severity,
		"现有指令不得绕过强制局势节点"
	)
	var resolved := system.resolve_node(
		instance_id,
		"staged_evacuation",
		0,
		0,
		sectors
	)
	_assert_true(bool(resolved.get("success", false)), "资源见底时仍应能选择节点兜底方案")
	_assert_eq(int(resolved.get("new_energy", -1)), 0, "零成本兜底不得产生负能源")
	_assert_eq(sector.hope, 52, "地方撤离方案应立即提高地区希望")
	var snapshots: Array = resolved.get("situations", [])
	_assert_true(not bool(snapshots[0].get("node", {}).get("pending", true)), "节点处理后不应继续待定")
	_assert_eq(
		str(snapshots[0].get("node", {}).get("choice_id", "")),
		"staged_evacuation",
		"节点选择应写入局势运行态"
	)
	system.apply_command_intervention("technology_aid", "asia", sectors)
	system.apply_command_intervention("technology_aid", "asia", sectors)
	_assert_eq(system.get_active_count(), 0, "局势解决后应离开活跃列表")
	var repeated := system.start_situation_for_test(
		"underground_geological_stress", "asia", 2061, 2
	)
	_assert_true(
		"分段人工撤离" in str(repeated.get("history_echo", "")),
		"同地区同类局势再次出现时应显示上次节点选择回声"
	)
	var repeated_id := str(repeated.get("instance_id", ""))
	var repeated_started := system._build_notification(
		"started",
		system._active[0],
		"重复局势开始。",
		true
	)
	_assert_true(
		"历史回声" in str(repeated_started.get("message", ""))
		and "分段人工撤离" in str(repeated_started.get("message", "")),
		"重复局势开始记录应包含上次处置回声"
	)
	system.set_approach(repeated_id, "local_survey", 20)
	var repeated_notifications: Array = []
	var repeated_result := system.apply_command_intervention("technology_aid", "asia", sectors)
	repeated_notifications.append_array(repeated_result.get("notifications", []))
	repeated_result = system.apply_command_intervention("technology_aid", "asia", sectors)
	repeated_notifications.append_array(repeated_result.get("notifications", []))
	var repeated_messages := _notification_messages(repeated_notifications)
	_assert_true(
		"历史回声" in "\n".join(repeated_messages)
		and "分段人工撤离" in "\n".join(repeated_messages),
		"重复局势结算记录应包含上次处置回声"
	)
	_assert_true(
		not system.export_state().get("history", {}).is_empty(),
		"局势历史应进入未来存档快照"
	)


func _assert_conditional_opportunity_contract() -> void:
	var opportunity := _get_template("regional_mutual_aid_window")
	_assert_true(opportunity != null, "条件型机会资源应能加载")
	if opportunity == null:
		return
	_assert_eq(opportunity.situation_kind, 1, "区域互助检修窗口应标记为机会型")
	_assert_true(not opportunity.required_any_facts.is_empty(), "机会型局势必须具有历史前提")
	_assert_eq(opportunity.situation_node.trigger_stage, 0, "机会型局势应在出现时立即提供节点")
	var system := _new_system(71)
	_assert_true(
		not system._is_template_eligible(opportunity, 2056, {}),
		"没有科技或事件历史时，条件型机会不得进入生成池"
	)
	_assert_true(
		system._is_template_eligible(
			opportunity,
			2056,
			{"technology.human_mutual_aid": true}
		),
		"满足任一已配置历史事实后，条件型机会应进入生成池"
	)
	_assert_true(
		not system._is_template_eligible(
			opportunity,
			2056,
			{"event_state.mid_05_dispatch_pilot": "closed_model"}
		),
		"不匹配的历史值不得错误解锁条件型机会"
	)
	var started := system.start_situation_for_test(
		"regional_mutual_aid_window", "south_america", 2056, 6
	)
	_assert_eq(str(started.get("stage_name", "")), "收窄", "机会型局势应使用专属阶段文案")
	_assert_true(bool(started.get("node", {}).get("pending", false)), "机会出现时应立即等待利用方式")
	var opportunity_id := str(started.get("instance_id", ""))
	var opportunity_sector := _create_sector("south_america")
	var opportunity_sectors: Array[SectorData] = [opportunity_sector]
	system.resolve_node(opportunity_id, "local_compact", 0, 0, opportunity_sectors)
	system._active[0]["severity"] = 97
	var closed := system.process_month(opportunity_sectors, 0, 0, false, 2056, 7)
	_assert_true(
		"协作窗口已经关闭" in "\n".join(
			_notification_messages(closed.get("notifications", []))
		),
		"机会型局势关闭时应使用窗口语义"
	)
	var repeated_opportunity := system.start_situation_for_test(
		"regional_mutual_aid_window", "south_america", 2062, 4
	)
	_assert_true(
		"协作窗口关闭" in str(repeated_opportunity.get("history_echo", "")),
		"机会型历史回声不应描述为处置失控"
	)


func _assert_command_intervention_and_outcome() -> void:
	var system := _new_system(31)
	var sector := _create_sector("asia")
	var sectors: Array[SectorData] = [sector]
	var started := system.start_situation_for_test(
		"regional_power_instability", "asia", 2046, 1
	)
	var instance_id := str(started.get("instance_id", ""))
	system.set_approach(instance_id, "local_repair", 20)
	var first := system.apply_command_intervention("energy_convert", "asia", sectors)
	_assert_eq(int(first["situations"][0].get("severity", -1)), 18, "现有指令应一次性降低局势严重度")
	var second := system.apply_command_intervention("energy_convert", "asia", sectors)
	_assert_eq(system.get_active_count(), 0, "严重度降至 0 后局势应结算并移除")
	_assert_true("resolved" in _notification_types(second.get("notifications", [])), "安全结算应生成记录")
	_assert_eq(sector.order, 53, "成功结算应叠加局势与所选方针的秩序恢复")
	_assert_eq(sector.hope, 54, "成功结算应叠加局势与所选方针的希望恢复")
	_assert_eq(sector.authority, 49, "地方抢修结算应轻微降低控制权")


func _assert_fixed_seed_export() -> void:
	var system := _new_system(424242)
	_assert_eq(int(system.export_state().get("seed", 0)), 424242, "固定种子应进入可保存运行时快照")


func _new_system(seed_value: int) -> SituationSystem:
	var system := SituationSystem.new()
	system.configure_templates(_templates)
	system.reset(seed_value)
	return system


func _get_template(situation_id: String) -> SituationData:
	for data in _templates:
		if data.situation_id == situation_id:
			return data
	return null


func _create_sector(region_id: String) -> SectorData:
	var sector := SectorData.new()
	sector.region_id = region_id
	sector.region_name = REGION_IDENTITY.display_name(region_id)
	sector.order = 50
	sector.hope = 50
	sector.authority = 50
	return sector


func _notification_types(notifications: Array) -> Array[String]:
	var result: Array[String] = []
	for notification_entry in notifications:
		result.append(str(notification_entry.get("type", "")))
	return result


func _notification_messages(notifications: Array) -> Array[String]:
	var result: Array[String] = []
	for notification_entry in notifications:
		result.append(str(notification_entry.get("message", "")))
	return result
