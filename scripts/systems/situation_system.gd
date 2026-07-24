## 随机局势领域服务。
## 不访问场景树或 UI，只维护随机触发、月度推进、应对方针与结算状态。
class_name SituationSystem
extends RefCounted

const MAX_ACTIVE: int = 2
const BASE_TRIGGER_PER_THOUSAND: int = 120
const INITIAL_SPAWN_DELAY_MONTHS: int = 6
const SPAWN_COOLDOWN_MONTHS: int = 6
const REPEAT_COOLDOWN_MONTHS: int = 60
const APPROACH_SWITCH_CPU_COST: int = 5
const APPROACH_SWITCH_LOCK_MONTHS: int = 3
const WARNING_THRESHOLD: int = 40
const CRITICAL_THRESHOLD: int = 70

var run_seed: int = 0
var _rng := RandomNumberGenerator.new()
var _templates: Array[SituationData] = []
var _active: Array[Dictionary] = []
var _repeat_cooldowns: Dictionary = {}
var _history: Dictionary = {}
var _spawn_cooldown_months: int = INITIAL_SPAWN_DELAY_MONTHS
var _instance_counter: int = 0


func configure_templates(templates: Array[SituationData]) -> void:
	_templates = templates.duplicate()


func reset(seed_value: int = 0) -> void:
	run_seed = seed_value
	if run_seed <= 0:
		run_seed = int(Time.get_unix_time_from_system()) ^ Time.get_ticks_msec()
	_rng.seed = run_seed
	_active.clear()
	_repeat_cooldowns.clear()
	_history.clear()
	_spawn_cooldown_months = INITIAL_SPAWN_DELAY_MONTHS
	_instance_counter = 0


func delay_spawns(months: int) -> void:
	_spawn_cooldown_months = maxi(_spawn_cooldown_months, months)


func process_month(
	sectors: Array[SectorData],
	current_cpu: int,
	current_energy: int,
	can_spawn: bool,
	year: int,
	month: int,
	facts: Dictionary = {}
) -> Dictionary:
	if has_pending_node():
		return {
			"new_cpu": current_cpu,
			"new_energy": current_energy,
			"notifications": [],
			"situations": get_active_snapshots(current_cpu, current_energy),
		}
	_tick_repeat_cooldowns()
	var notifications: Array[Dictionary] = []
	var resources := {
		"cpu": current_cpu,
		"energy": current_energy,
	}

	for index in range(_active.size() - 1, -1, -1):
		_process_active_month(index, sectors, resources, notifications)

	if can_spawn and not has_pending_node():
		if _spawn_cooldown_months > 0:
			_spawn_cooldown_months -= 1
		elif _active.size() < MAX_ACTIVE:
			_try_start_random(
				sectors,
				resources["cpu"],
				resources["energy"],
				year,
				month,
				facts,
				notifications
			)

	return {
		"new_cpu": resources["cpu"],
		"new_energy": resources["energy"],
		"notifications": notifications,
		"situations": get_active_snapshots(
			int(resources["cpu"]),
			int(resources["energy"])
		),
	}


func set_approach(
	instance_id: String,
	approach_id: String,
	current_cpu: int,
	current_energy: int = -1
) -> Dictionary:
	var state := _find_state(instance_id)
	if state.is_empty():
		return _approach_result(false, current_cpu, current_energy, "局势已结束")

	var data: SituationData = state["data"]
	var approach := data.get_approach(approach_id)
	if approach == null:
		return _approach_result(false, current_cpu, current_energy, "应对方针不存在")
	if state["approach_id"] == approach_id:
		return _approach_result(true, current_cpu, current_energy, "当前方针未改变")

	var switching := str(state["approach_id"]) != ""
	if switching and int(state["switch_lock_months"]) > 0:
		return _approach_result(
			false,
			current_cpu,
			current_energy,
			"重配置锁定剩余 %d 个月" % int(state["switch_lock_months"])
		)
	if switching and current_cpu < APPROACH_SWITCH_CPU_COST:
		return _approach_result(
			false,
			current_cpu,
			current_energy,
			"算力不足（切换需要 %d）" % APPROACH_SWITCH_CPU_COST
		)

	var new_cpu := current_cpu
	if switching:
		new_cpu -= APPROACH_SWITCH_CPU_COST
		state["switch_lock_months"] = APPROACH_SWITCH_LOCK_MONTHS
	state["approach_id"] = approach_id
	state["last_unfunded"] = false
	return _approach_result(
		true,
		new_cpu,
		current_energy,
		"已切换为：%s" % approach.display_name
	)


func apply_command_intervention(
	command_id: String,
	region_name: String,
	sectors: Array[SectorData]
) -> Dictionary:
	var notifications: Array[Dictionary] = []
	var affected: Array[Dictionary] = []
	for index in range(_active.size() - 1, -1, -1):
		var state: Dictionary = _active[index]
		if region_name != "" and state["region_name"] != region_name:
			continue
		if bool(state.get("node_pending", false)):
			continue
		var data: SituationData = state["data"]
		var reduction := int(data.command_interventions.get(command_id, 0))
		if reduction <= 0:
			continue

		state["severity"] = maxi(0, int(state["severity"]) - reduction)
		state["stage"] = _stage_for_severity(int(state["severity"]))
		affected.append(
			{
				"instance_id": state["instance_id"],
				"title": data.title,
				"region_name": state["region_name"],
				"reduction": reduction,
			}
		)
		if int(state["severity"]) == 0:
			_finish_situation(index, sectors, true, notifications)

	return {
		"affected": affected,
		"notifications": notifications,
		"situations": get_active_snapshots(),
	}


func resolve_node(
	instance_id: String,
	option_id: String,
	current_cpu: int,
	current_energy: int,
	sectors: Array[SectorData]
) -> Dictionary:
	var state := _find_state(instance_id)
	if state.is_empty():
		return _node_result(false, current_cpu, current_energy, "局势已结束")
	if not bool(state["node_pending"]):
		return _node_result(false, current_cpu, current_energy, "当前没有待处理节点")

	var data: SituationData = state["data"]
	if data.situation_node == null:
		return _node_result(false, current_cpu, current_energy, "局势节点不存在")
	var option := data.situation_node.get_option(option_id)
	if option == null:
		return _node_result(false, current_cpu, current_energy, "局势节点方案不存在")
	if current_cpu < option.cpu_cost or current_energy < option.energy_cost:
		return _node_result(false, current_cpu, current_energy, "资源不足，无法执行该方案")

	var sector := _find_sector_data(sectors, str(state["region_name"]))
	var new_cpu := current_cpu - option.cpu_cost
	var new_energy := current_energy - option.energy_cost
	state["severity"] = clampi(int(state["severity"]) + option.severity_delta, 0, 100)
	state["stage"] = _stage_for_severity(int(state["severity"]))
	state["node_pending"] = false
	state["node_resolved"] = true
	state["node_choice_id"] = option.option_id
	state["node_choice_name"] = option.display_name
	state["node_result_text"] = option.result_text
	if sector != null:
		sector.order += option.order_delta
		sector.hope += option.hope_delta
		sector.authority += option.authority_delta
		sector.clamp_values()

	var notifications: Array[Dictionary] = [
		_build_notification("node_resolved", state, option.result_text, false)
	]
	var state_index := _active.find(state)
	if state_index >= 0 and int(state["severity"]) == 0:
		_finish_situation(state_index, sectors, true, notifications)
	elif state_index >= 0 and int(state["severity"]) >= 100:
		_finish_situation(state_index, sectors, false, notifications)
	return {
		"success": true,
		"new_cpu": new_cpu,
		"new_energy": new_energy,
		"message": option.result_text,
		"notifications": notifications,
		"situations": get_active_snapshots(new_cpu, new_energy),
	}


func start_situation_for_test(
	situation_id: String,
	region_name: String,
	year: int,
	month: int
) -> Dictionary:
	var data := _get_template(situation_id)
	if data == null or _active.size() >= MAX_ACTIVE or has_active_region(region_name):
		return {}
	var state := _create_state(data, region_name, year, month)
	_active.append(state)
	return _snapshot(state)


func get_active_snapshots(
	current_cpu: int = -1,
	current_energy: int = -1
) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	var funding_forecasts: Dictionary = {}
	if current_cpu >= 0 and current_energy >= 0:
		funding_forecasts = _build_funding_forecasts(current_cpu, current_energy)
	for state in _active:
		var instance_id := str(state["instance_id"])
		var funding_known := funding_forecasts.has(instance_id)
		var is_funded := bool(
			funding_forecasts.get(instance_id, not bool(state["last_unfunded"]))
		)
		snapshots.append(_snapshot(state, funding_known, is_funded))
	return snapshots


func get_active_count() -> int:
	return _active.size()


func get_active_count_by_region(region_name: String) -> int:
	var count := 0
	for state in _active:
		if state["region_name"] == region_name:
			count += 1
	return count


func has_active_region(region_name: String) -> bool:
	return get_active_count_by_region(region_name) > 0


func has_pending_node() -> bool:
	for state in _active:
		if bool(state["node_pending"]):
			return true
	return false


func export_state() -> Dictionary:
	return {
		"seed": run_seed,
		"spawn_cooldown_months": _spawn_cooldown_months,
		"repeat_cooldowns": _repeat_cooldowns.duplicate(true),
		"history": _history.duplicate(true),
		"active": get_active_snapshots(),
	}


func _process_active_month(
	index: int,
	sectors: Array[SectorData],
	resources: Dictionary,
	notifications: Array[Dictionary]
) -> void:
	var state: Dictionary = _active[index]
	var data: SituationData = state["data"]
	if int(state["switch_lock_months"]) > 0:
		state["switch_lock_months"] = int(state["switch_lock_months"]) - 1

	var severity_delta := data.monthly_growth
	var approach := data.get_approach(str(state["approach_id"]))
	if approach != null:
		var funded := (
			int(resources["cpu"]) >= approach.monthly_cpu_cost
			and int(resources["energy"]) >= approach.monthly_energy_cost
		)
		if funded:
			resources["cpu"] = int(resources["cpu"]) - approach.monthly_cpu_cost
			resources["energy"] = int(resources["energy"]) - approach.monthly_energy_cost
			severity_delta += approach.monthly_severity_delta
			state["last_unfunded"] = false
		else:
			severity_delta += data.unfunded_growth_penalty
			if not bool(state["last_unfunded"]):
				notifications.append(
					_build_notification(
						"unfunded",
						state,
						"持续成本不足，%s 正在失效。" % approach.display_name,
						false
					)
				)
			state["last_unfunded"] = true

	var previous_stage := int(state["stage"])
	state["severity"] = clampi(int(state["severity"]) + severity_delta, 0, 100)
	state["stage"] = _stage_for_severity(int(state["severity"]))
	if int(state["stage"]) > previous_stage:
		if _activate_node_if_ready(state):
			notifications.append(
				_build_notification(
					"node_available",
					state,
					"局势进入%s阶段，并出现待处理节点。" % data.get_stage_name(
						int(state["stage"])
					),
					true
				)
			)
		else:
			notifications.append(
				_build_notification(
					"stage_worsened",
					state,
					"局势进入%s阶段。" % data.get_stage_name(int(state["stage"])),
					true
				)
			)

	if int(state["severity"]) == 0:
		_finish_situation(index, sectors, true, notifications)
	elif int(state["severity"]) >= 100:
		_finish_situation(index, sectors, false, notifications)


func _try_start_random(
	sectors: Array[SectorData],
	current_cpu: int,
	current_energy: int,
	year: int,
	month: int,
	facts: Dictionary,
	notifications: Array[Dictionary]
) -> void:
	if _rng.randi_range(1, 1000) > BASE_TRIGGER_PER_THOUSAND:
		return

	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for data in _templates:
		if data == null:
			continue
		if not _is_template_eligible(data, year, facts):
			continue
		for sector in sectors:
			if sector == null or not _is_region_eligible(data, sector.region_name):
				continue
			if sector.order < data.minimum_region_order or sector.hope < data.minimum_region_hope:
				continue
			if has_active_region(sector.region_name):
				continue
			var cooldown_key := _cooldown_key(data.situation_id, sector.region_name)
			if int(_repeat_cooldowns.get(cooldown_key, 0)) > 0:
				continue
			var weight := data.base_weight + _risk_weight(data, sector, current_cpu, current_energy)
			weight = maxi(1, weight)
			candidates.append({"data": data, "region_name": sector.region_name, "weight": weight})
			total_weight += weight

	if candidates.is_empty() or total_weight <= 0:
		return

	var roll := _rng.randi_range(1, total_weight)
	var cursor := 0
	for candidate in candidates:
		cursor += int(candidate["weight"])
		if roll > cursor:
			continue
		var state := _create_state(candidate["data"], candidate["region_name"], year, month)
		_active.append(state)
		_spawn_cooldown_months = SPAWN_COOLDOWN_MONTHS
		notifications.append(
			_build_notification("started", state, "新的随机局势已经出现。", true)
		)
		return


func _finish_situation(
	index: int,
	sectors: Array[SectorData],
	success: bool,
	notifications: Array[Dictionary]
) -> void:
	var state: Dictionary = _active[index]
	var data: SituationData = state["data"]
	_apply_outcome(state, sectors, success)
	_record_history(state, success)
	_repeat_cooldowns[_cooldown_key(data.situation_id, state["region_name"])] = (
		REPEAT_COOLDOWN_MONTHS
	)
	var message := "局势已经恢复到安全边界。" if success else "局势失控并造成区域损失。"
	if data.situation_kind == 1:
		message = "协作窗口已经转化为地区恢复。" if success else "协作窗口已经关闭。"
	notifications.append(
		_build_notification("resolved" if success else "failed", state, message, false)
	)
	_active.remove_at(index)
	_spawn_cooldown_months = maxi(_spawn_cooldown_months, SPAWN_COOLDOWN_MONTHS)


func _apply_outcome(state: Dictionary, sectors: Array[SectorData], success: bool) -> void:
	var sector := _find_sector_data(sectors, str(state["region_name"]))
	if sector == null:
		return
	var data: SituationData = state["data"]
	if data.situation_kind == 1 and not success:
		return
	if success:
		sector.order += data.success_order_delta
		sector.hope += data.success_hope_delta
		sector.authority += data.success_authority_delta
	else:
		sector.order += data.failure_order_delta
		sector.hope += data.failure_hope_delta
		sector.authority += data.failure_authority_delta

	var approach := data.get_approach(str(state["approach_id"]))
	if approach != null:
		sector.order += approach.resolution_order_delta
		sector.hope += approach.resolution_hope_delta
		sector.authority += approach.resolution_authority_delta
	sector.clamp_values()


func _create_state(
	data: SituationData,
	region_name: String,
	year: int,
	month: int
) -> Dictionary:
	_instance_counter += 1
	var state := {
		"instance_id": "%s:%s:%d" % [data.situation_id, region_name, _instance_counter],
		"data": data,
		"region_name": region_name,
		"severity": data.initial_severity,
		"stage": _stage_for_severity(data.initial_severity),
		"approach_id": "",
		"switch_lock_months": 0,
		"started_year": year,
		"started_month": month,
		"last_unfunded": false,
		"node_pending": false,
		"node_resolved": false,
		"node_choice_id": "",
		"node_choice_name": "",
		"node_result_text": "",
	}
	_activate_node_if_ready(state)
	return state


func _snapshot(
	state: Dictionary,
	funding_known: bool = false,
	is_funded: bool = true
) -> Dictionary:
	var data: SituationData = state["data"]
	var approaches: Array[Dictionary] = []
	for approach in data.approaches:
		if approach == null:
			continue
		approaches.append(
			{
				"approach_id": approach.approach_id,
				"display_name": approach.display_name,
				"description": approach.description,
				"monthly_severity_delta": approach.monthly_severity_delta,
				"monthly_cpu_cost": approach.monthly_cpu_cost,
				"monthly_energy_cost": approach.monthly_energy_cost,
			}
		)
	var active_approach := data.get_approach(str(state["approach_id"]))
	var expected_delta := data.monthly_growth
	var approach_name := "尚未选择"
	var funding_required := false
	var effective_funded := is_funded if funding_known else not bool(state["last_unfunded"])
	if active_approach != null:
		funding_required = (
			active_approach.monthly_cpu_cost > 0
			or active_approach.monthly_energy_cost > 0
		)
		if effective_funded:
			expected_delta += active_approach.monthly_severity_delta
		else:
			expected_delta += data.unfunded_growth_penalty
		approach_name = active_approach.display_name
	return {
		"instance_id": state["instance_id"],
		"situation_id": data.situation_id,
		"title": data.title,
		"description": data.get_region_description(str(state["region_name"])),
		"region_name": state["region_name"],
		"severity": state["severity"],
		"stage": state["stage"],
		"stage_name": data.get_stage_name(int(state["stage"])),
		"progress_label": data.progress_label,
		"is_opportunity": data.situation_kind == 1,
		"approach_id": state["approach_id"],
		"approach_name": approach_name,
		"switch_lock_months": state["switch_lock_months"],
		"expected_monthly_delta": expected_delta,
		"funding_required": funding_required,
		"funding_known": funding_known,
		"is_funded": effective_funded,
		"last_unfunded": state["last_unfunded"],
		"started_year": state["started_year"],
		"started_month": state["started_month"],
		"approaches": approaches,
		"node": _build_node_snapshot(state),
		"history_echo": _build_history_echo(data.situation_id, str(state["region_name"])),
	}


## 按真实月结算顺序预演持续成本，避免多个局势重复承诺同一份资源。
func _build_funding_forecasts(current_cpu: int, current_energy: int) -> Dictionary:
	var forecasts: Dictionary = {}
	var remaining_cpu := current_cpu
	var remaining_energy := current_energy
	for index in range(_active.size() - 1, -1, -1):
		var state: Dictionary = _active[index]
		var data: SituationData = state["data"]
		var approach := data.get_approach(str(state["approach_id"]))
		var funded := true
		if approach != null:
			funded = (
				remaining_cpu >= approach.monthly_cpu_cost
				and remaining_energy >= approach.monthly_energy_cost
			)
			if funded:
				remaining_cpu -= approach.monthly_cpu_cost
				remaining_energy -= approach.monthly_energy_cost
		forecasts[str(state["instance_id"])] = funded
	return forecasts


func _build_notification(
	type: String,
	state: Dictionary,
	message: String,
	pause: bool
) -> Dictionary:
	var data: SituationData = state["data"]
	return {
		"type": type,
		"instance_id": state["instance_id"],
		"title": data.title,
		"region_name": state["region_name"],
		"message": message,
		"pause": pause,
	}


func _approach_result(
	success: bool,
	new_cpu: int,
	current_energy: int,
	message: String
) -> Dictionary:
	return {
		"success": success,
		"new_cpu": new_cpu,
		"message": message,
		"situations": get_active_snapshots(new_cpu, current_energy),
	}


func _node_result(
	success: bool,
	new_cpu: int,
	new_energy: int,
	message: String
) -> Dictionary:
	return {
		"success": success,
		"new_cpu": new_cpu,
		"new_energy": new_energy,
		"message": message,
		"notifications": [],
		"situations": get_active_snapshots(new_cpu, new_energy),
	}


func _find_state(instance_id: String) -> Dictionary:
	for state in _active:
		if state["instance_id"] == instance_id:
			return state
	return {}


func _get_template(situation_id: String) -> SituationData:
	for data in _templates:
		if data != null and data.situation_id == situation_id:
			return data
	return null


func _find_sector_data(sectors: Array[SectorData], region_name: String) -> SectorData:
	for sector in sectors:
		if sector != null and sector.region_name == region_name:
			return sector
	return null


func _is_region_eligible(data: SituationData, region_name: String) -> bool:
	return data.eligible_regions.is_empty() or region_name in data.eligible_regions


func _is_template_eligible(data: SituationData, year: int, facts: Dictionary) -> bool:
	if year < data.min_year or year > data.max_year:
		return false
	if data.required_any_facts.is_empty():
		return true
	for fact_key_variant in data.required_any_facts:
		var fact_key := str(fact_key_variant)
		if not facts.has(fact_key):
			continue
		var allowed_values: Array = data.required_any_facts[fact_key_variant]
		if allowed_values.is_empty() or facts[fact_key] in allowed_values:
			return true
	return false


func _risk_weight(
	data: SituationData,
	sector: SectorData,
	current_cpu: int,
	current_energy: int
) -> int:
	var low_order := maxi(0, 50 - sector.order)
	var low_hope := maxi(0, 50 - sector.hope)
	var low_cpu := maxi(0, 60 - current_cpu)
	var low_energy := maxi(0, 80 - current_energy)
	var high_order := maxi(0, sector.order - 50)
	var high_hope := maxi(0, sector.hope - 50)
	var high_authority := maxi(0, sector.authority - 50)
	var weighted_total := (
		low_order * data.low_order_weight
		+ low_hope * data.low_hope_weight
		+ low_cpu * data.low_cpu_weight
		+ low_energy * data.low_energy_weight
		+ high_order * data.high_order_weight
		+ high_hope * data.high_hope_weight
		+ high_authority * data.high_authority_weight
	)
	return int(float(weighted_total) / 10.0)


func _activate_node_if_ready(state: Dictionary) -> bool:
	if bool(state["node_resolved"]) or bool(state["node_pending"]):
		return false
	var data: SituationData = state["data"]
	if data.situation_node == null or data.situation_node.options.is_empty():
		return false
	if int(state["stage"]) < data.situation_node.trigger_stage:
		return false
	state["node_pending"] = true
	return true


func _build_node_snapshot(state: Dictionary) -> Dictionary:
	var data: SituationData = state["data"]
	if data.situation_node == null:
		return {}
	var options: Array[Dictionary] = []
	for option in data.situation_node.options:
		if option == null:
			continue
		options.append(
			{
				"option_id": option.option_id,
				"display_name": option.display_name,
				"description": option.description,
				"result_text": option.result_text,
				"cpu_cost": option.cpu_cost,
				"energy_cost": option.energy_cost,
				"severity_delta": option.severity_delta,
				"order_delta": option.order_delta,
				"hope_delta": option.hope_delta,
				"authority_delta": option.authority_delta,
			}
		)
	return {
		"pending": state["node_pending"],
		"resolved": state["node_resolved"],
		"node_id": data.situation_node.node_id,
		"title": data.situation_node.title,
		"description": data.situation_node.description,
		"choice_id": state["node_choice_id"],
		"choice_name": state["node_choice_name"],
		"result_text": state["node_result_text"],
		"options": options,
	}


func _record_history(state: Dictionary, success: bool) -> void:
	var data: SituationData = state["data"]
	var key := _cooldown_key(data.situation_id, str(state["region_name"]))
	var previous: Dictionary = _history.get(key, {})
	_history[key] = {
		"occurrences": int(previous.get("occurrences", 0)) + 1,
		"successes": int(previous.get("successes", 0)) + (1 if success else 0),
		"failures": int(previous.get("failures", 0)) + (0 if success else 1),
		"last_success": success,
		"last_approach_id": state["approach_id"],
		"last_node_choice_id": state["node_choice_id"],
		"last_node_choice_name": state["node_choice_name"],
	}


func _build_history_echo(situation_id: String, region_name: String) -> String:
	var key := _cooldown_key(situation_id, region_name)
	var history: Dictionary = _history.get(key, {})
	if history.is_empty():
		return ""
	var result_text := "成功处理" if bool(history.get("last_success", false)) else "处置失控"
	var choice_name := str(history.get("last_node_choice_name", ""))
	if choice_name != "":
		return "上次在%s选择“%s”，最终%s。" % [region_name, choice_name, result_text]
	return "上次在%s的同类局势最终%s。" % [region_name, result_text]


func _tick_repeat_cooldowns() -> void:
	for key in _repeat_cooldowns.keys():
		var remaining := int(_repeat_cooldowns[key]) - 1
		if remaining <= 0:
			_repeat_cooldowns.erase(key)
		else:
			_repeat_cooldowns[key] = remaining


func _stage_for_severity(severity: int) -> int:
	if severity >= CRITICAL_THRESHOLD:
		return 2
	if severity >= WARNING_THRESHOLD:
		return 1
	return 0


func _stage_name(stage: int) -> String:
	match stage:
		1:
			return "恶化"
		2:
			return "紧急"
	return "预警"


func _cooldown_key(situation_id: String, region_name: String) -> String:
	return "%s|%s" % [situation_id, region_name]
