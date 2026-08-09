## 随机局势四类算法服务的表驱动测试。
extends "res://tests/support/moss_test_case.gd"

const TEMPLATE_PATHS: Array[String] = [
	"res://data/situations/regional_power_instability.tres",
	"res://data/situations/emergency_communication_congestion.tres",
	"res://data/situations/underground_life_support_fault.tres",
	"res://data/situations/underground_geological_stress.tres",
	"res://data/situations/regional_mutual_aid_window.tres",
]
const REGION_IDENTITY: GDScript = preload("res://scripts/resources/region_identity.gd")

var _templates: Array[SituationData] = []


func _ready() -> void:
	_load_templates()
	_assert_spawn_planner_contract()
	_assert_funding_planner_contract()
	_assert_month_resolver_contract()
	_assert_snapshot_builder_contract()

	await get_tree().create_timer(0.2).timeout
	print("[MOSS-SITUATION-ALGORITHMS] 完成，失败断言：%d" % _failed)
	await get_tree().process_frame
	get_tree().quit(_failed)


func _load_templates() -> void:
	for path in TEMPLATE_PATHS:
		var data := load(path) as SituationData
		_assert_true(data != null, "算法测试模板应能加载：%s" % path)
		if data != null:
			_templates.append(data)


func _assert_spawn_planner_contract() -> void:
	var planner := SituationSpawnPlanner.new()
	var eligibility_cases: Array[Dictionary] = [
		{
			"facts": {},
			"expected": false,
			"message": "条件型机会缺少事实时不得进入生成池",
		},
		{
			"facts": {"technology.human_mutual_aid": true},
			"expected": true,
			"message": "条件型机会命中科技事实时应进入生成池",
		},
		{
			"facts": {"technology.human_mutual_aid": false},
			"expected": false,
			"message": "条件型机会事实值不匹配时不得进入生成池",
		},
	]
	for eligibility_case in eligibility_cases:
		_assert_eq(
			planner.is_template_eligible(
				_templates,
				"regional_mutual_aid_window",
				2056,
				eligibility_case["facts"]
			),
			eligibility_case["expected"],
			str(eligibility_case["message"])
		)

	var power := _get_template("regional_power_instability")
	var asia := _create_sector("asia", 50, 50, 50)
	var north_america := _create_sector("north_america", 50, 50, 50)
	var sectors: Array[SectorData] = [asia, north_america]
	var power_templates: Array[SituationData] = [power]
	var candidates := planner.build_candidates(
		power_templates,
		sectors,
		{"asia": true},
		{},
		2050,
		1,
		{},
		30,
		100
	)
	_assert_true(not candidates.is_empty(), "未占用地区应保留局势候选")
	for candidate in candidates:
		_assert_true(
			str(candidate["region_id"]) != "asia",
			"已活跃地区不得进入候选"
		)
	_assert_eq(planner.get_total_weight(candidates), int(candidates[0]["weight"]), "单候选总权重应稳定")

	var low_risk := _create_sector("asia", 20, 20, 50)
	var normal_risk := _create_sector("asia", 50, 50, 50)
	_assert_true(
		planner.calculate_risk_weight(power, low_risk, 20, 20)
		> planner.calculate_risk_weight(power, normal_risk, 100, 100),
		"地区和资源缺口应提高候选风险权重"
	)
	var weighted_candidates: Array[Dictionary] = [
		{"region_id": "first", "weight": 2},
		{"region_id": "second", "weight": 3},
	]
	_assert_eq(
		str(planner.pick_candidate(weighted_candidates, 1)["region_id"]),
		"first",
		"权重抽样的首段应命中第一个候选"
	)
	_assert_eq(
		str(planner.pick_candidate(weighted_candidates, 5)["region_id"]),
		"second",
		"权重抽样的末段应命中最后一个候选"
	)
	_assert_true(
		planner.pick_candidate(weighted_candidates, 6).is_empty(),
		"越界权重抽样应返回空候选"
	)


func _assert_funding_planner_contract() -> void:
	var planner := SituationFundingPlanner.new()
	var first := _make_state(
		"underground_life_support_fault",
		"africa",
		"automated_trusteeship",
		"first"
	)
	var second := _make_state(
		"underground_geological_stress",
		"asia",
		"predictive_closure",
		"second"
	)
	var states: Array[SituationInstanceState] = [first, second]
	var plan := planner.build_plan(states, 1, 1)
	var first_plan: Dictionary = plan[first.instance_id]
	var second_plan: Dictionary = plan[second.instance_id]
	_assert_true(not bool(first_plan["funded"]), "逆序资源计划应让后结算局势优先获得资源")
	_assert_true(bool(second_plan["funded"]), "逆序资源计划应保持真实结算顺序")
	_assert_eq(int(first_plan["cpu_cost"]), 1, "资源计划应暴露算力成本")
	_assert_eq(int(first_plan["energy_cost"]), 1, "资源计划应暴露能源成本")
	_assert_eq(first.last_unfunded, false, "资源预演不得修改局势状态")


func _assert_month_resolver_contract() -> void:
	var resolver := SituationMonthResolver.new()
	var state := _make_state(
		"underground_life_support_fault",
		"africa",
		"automated_trusteeship",
		"resolver"
	)
	state.severity = 39
	state.stage = resolver.stage_for_severity(state.severity)
	state.switch_lock_months = 2
	var result := resolver.resolve_month(
		state,
		{
			state.instance_id: {
				"funded": false,
				"cpu_cost": 1,
				"energy_cost": 1,
			}
		}
	)
	var next_state: SituationInstanceState = result["state"]
	_assert_eq(state.severity, 39, "月结算服务不得修改输入状态副本")
	_assert_eq(state.switch_lock_months, 2, "月结算服务不得修改输入锁定")
	_assert_eq(next_state.severity, 45, "断供应叠加基础增长和断供惩罚")
	_assert_eq(next_state.stage, 1, "严重度跨过预警阈值应进入恶化阶段")
	_assert_true(next_state.last_unfunded, "断供后状态应记录断供")
	_assert_true(next_state.node_pending, "跨入恶化阶段应激活一次性节点")
	_assert_eq(str(result["status"]), "active", "仍在边界内的局势应保持活跃")
	var notification_types: Array[String] = []
	for notification in result["notifications"]:
		notification_types.append(str(notification["type"]))
	_assert_true("unfunded" in notification_types, "首次断供应返回断供通知数据")
	_assert_true("node_available" in notification_types, "节点激活应返回暂停通知数据")

	var terminal := _make_state(
		"underground_life_support_fault",
		"africa",
		"automated_trusteeship",
		"terminal"
	)
	terminal.severity = 3
	terminal.stage = resolver.stage_for_severity(terminal.severity)
	var terminal_result := resolver.resolve_month(
		terminal,
		{
			terminal.instance_id: {
				"funded": true,
				"cpu_cost": 1,
				"energy_cost": 1,
			}
		}
	)
	_assert_eq(str(terminal_result["status"]), "success", "严重度归零应返回成功结算状态")
	_assert_eq(int(terminal_result["state"].severity), 0, "成功结算状态应将严重度限幅到零")


func _assert_snapshot_builder_contract() -> void:
	var builder := SituationSnapshotBuilder.new()
	var state := _make_state(
		"regional_power_instability",
		"asia",
		"local_repair",
		"snapshot"
	)
	var history: Dictionary = {
		"regional_power_instability|asia": {
			"last_success": true,
			"situation_kind": 0,
			"last_node_choice_name": "本地抢修",
		},
	}
	var snapshot := builder.build_active_snapshot(state, true, false, history)
	_assert_eq(str(snapshot["region_id"]), "asia", "快照应保留稳定地区 ID")
	_assert_eq(str(snapshot["region_name"]), REGION_IDENTITY.display_name("asia"), "快照应生成地区显示名")
	_assert_eq(bool(snapshot["funding_known"]), true, "快照应标记供给预测已知")
	_assert_eq(bool(snapshot["is_funded"]), false, "快照应消费外部资源计划结果")
	_assert_true("本地抢修" in str(snapshot["history_echo"]), "快照应生成同类历史回声")
	_assert_eq(snapshot["node"].get("options", []).size(), 2, "快照应完整投影节点方案")
	var notification := builder.build_notification(
		"resolved",
		state,
		"局势已经恢复到安全边界。",
		false,
		history
	)
	_assert_true("历史回声" in str(notification["message"]), "结算通知应追加历史回声")
	_assert_eq(str(notification["title"]), state.data.title, "通知应消费模板标题")


func _make_state(
	situation_id: String,
	region_id: String,
	approach_id: String,
	instance_suffix: String
) -> SituationInstanceState:
	var state := SituationInstanceState.new()
	state.instance_id = "algorithm:%s:%s" % [situation_id, instance_suffix]
	state.data = _get_template(situation_id)
	state.region_id = region_id
	state.approach_id = approach_id
	state.severity = state.data.initial_severity
	state.stage = SituationMonthResolver.new().stage_for_severity(state.severity)
	state.started_year = 2050
	state.started_month = 1
	return state


func _get_template(situation_id: String) -> SituationData:
	for data in _templates:
		if data.situation_id == situation_id:
			return data
	return null


func _create_sector(
	region_id: String,
	order: int,
	hope: int,
	authority: int
) -> SectorData:
	var sector := SectorData.new()
	sector.region_id = region_id
	sector.region_name = REGION_IDENTITY.display_name(region_id)
	sector.order = order
	sector.hope = hope
	sector.authority = authority
	return sector
