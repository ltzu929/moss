## 随机局势领域服务。
## 不访问场景树或 UI，只维护随机触发、月度推进、应对方针与结算状态。
class_name SituationSystem
extends RefCounted

const MAX_ACTIVE: int = 2
const INITIAL_SPAWN_DELAY_MONTHS: int = 6
const SPAWN_COOLDOWN_MONTHS: int = 6
const REPEAT_COOLDOWN_MONTHS: int = 60
const APPROACH_SWITCH_CPU_COST: int = 5
const APPROACH_SWITCH_LOCK_MONTHS: int = 3
const RUNTIME_SNAPSHOT_VERSION: int = 1

var run_seed: int = 0
var _rng := RandomNumberGenerator.new()
var _templates: Array[SituationData] = []
var _active: Array[SituationInstanceState] = []
var _repeat_cooldowns: Dictionary = {}
var _history: Dictionary = {}
var _spawn_cooldown_months: int = INITIAL_SPAWN_DELAY_MONTHS
var _instance_counter: int = 0
var _spawn_planner: SituationSpawnPlanner = SituationSpawnPlanner.new()
var _funding_planner: SituationFundingPlanner = SituationFundingPlanner.new()
var _month_resolver: SituationMonthResolver = SituationMonthResolver.new()
var _snapshot_builder: SituationSnapshotBuilder = SituationSnapshotBuilder.new()


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
	var funding_plan := _funding_planner.build_plan(
		_active,
		current_cpu,
		current_energy
	)

	for index in range(_active.size() - 1, -1, -1):
		var state: SituationInstanceState = _active[index]
		var state_plan: Dictionary = funding_plan.get(state.instance_id, {})
		if bool(state_plan.get("funded", false)):
			resources["cpu"] = int(resources["cpu"]) - int(
				state_plan.get("cpu_cost", 0)
			)
			resources["energy"] = int(resources["energy"]) - int(
				state_plan.get("energy_cost", 0)
			)
		var resolution: Dictionary = _month_resolver.resolve_month(state, funding_plan)
		var resolved_state: SituationInstanceState = resolution["state"]
		_active[index] = resolved_state
		var raw_notifications: Array = resolution["notifications"]
		for raw_notification_variant in raw_notifications:
			var raw_notification: Dictionary = raw_notification_variant
			notifications.append(
				_snapshot_builder.build_notification(
					str(raw_notification.get("type", "")),
					resolved_state,
					str(raw_notification.get("message", "")),
					bool(raw_notification.get("pause", false)),
					_history
				)
			)
		match str(resolution.get("status", "active")):
			"success":
				_finish_situation(index, sectors, true, notifications)
			"failure":
				_finish_situation(index, sectors, false, notifications)

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
	if state == null:
		return _approach_result(false, current_cpu, current_energy, "局势已结束")

	var data: SituationData = state.data
	var approach := data.get_approach(approach_id)
	if approach == null:
		return _approach_result(false, current_cpu, current_energy, "应对方针不存在")
	if state.approach_id == approach_id:
		return _approach_result(true, current_cpu, current_energy, "当前方针未改变")

	var switching := state.approach_id != ""
	if switching and state.switch_lock_months > 0:
		return _approach_result(
			false,
			current_cpu,
			current_energy,
			"重配置锁定剩余 %d 个月" % state.switch_lock_months
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
		state.switch_lock_months = APPROACH_SWITCH_LOCK_MONTHS
	state.approach_id = approach_id
	state.last_unfunded = false
	return _approach_result(
		true,
		new_cpu,
		current_energy,
		"已切换为：%s" % approach.display_name
	)


func apply_command_intervention(
	command_id: String,
	region_id: String,
	sectors: Array[SectorData]
) -> Dictionary:
	var notifications: Array[Dictionary] = []
	var affected: Array[Dictionary] = []
	for index in range(_active.size() - 1, -1, -1):
		var state: SituationInstanceState = _active[index]
		if region_id != "" and state.region_id != region_id:
			continue
		if state.node_pending:
			continue
		var data: SituationData = state.data
		var reduction := int(data.command_interventions.get(command_id, 0))
		if reduction <= 0:
			continue

		state.severity = maxi(0, state.severity - reduction)
		state.stage = _stage_for_severity(state.severity)
		affected.append(
			{
				"instance_id": state.instance_id,
				"title": data.title,
				"region_id": state.region_id,
				"region_name": RegionIdentity.display_name(state.region_id),
				"reduction": reduction,
			}
		)
		if state.severity == 0:
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
	if state == null:
		return _node_result(false, current_cpu, current_energy, "局势已结束")
	if not state.node_pending:
		return _node_result(false, current_cpu, current_energy, "当前没有待处理节点")

	var data: SituationData = state.data
	if data.situation_node == null:
		return _node_result(false, current_cpu, current_energy, "局势节点不存在")
	var option := data.situation_node.get_option(option_id)
	if option == null:
		return _node_result(false, current_cpu, current_energy, "局势节点方案不存在")
	if current_cpu < option.cpu_cost or current_energy < option.energy_cost:
		return _node_result(false, current_cpu, current_energy, "资源不足，无法执行该方案")

	var sector := _find_sector_data(sectors, state.region_id)
	var new_cpu := current_cpu - option.cpu_cost
	var new_energy := current_energy - option.energy_cost
	state.severity = clampi(state.severity + option.severity_delta, 0, 100)
	state.stage = _stage_for_severity(state.severity)
	state.node_pending = false
	state.node_resolved = true
	state.node_choice_id = option.option_id
	state.node_choice_name = option.display_name
	state.node_result_text = option.result_text
	if sector != null:
		sector.order += option.order_delta
		sector.hope += option.hope_delta
		sector.authority += option.authority_delta
		sector.clamp_values()

	var notifications: Array[Dictionary] = [
		_snapshot_builder.build_notification(
			"node_resolved",
			state,
			option.result_text,
			false,
			_history
		)
	]
	var state_index := _active.find(state)
	if state_index >= 0 and state.severity == 0:
		_finish_situation(state_index, sectors, true, notifications)
	elif state_index >= 0 and state.severity >= 100:
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
	region_id: String,
	year: int,
	month: int
) -> Dictionary:
	var data := _get_template(situation_id)
	if data == null or _active.size() >= MAX_ACTIVE or has_active_region(region_id):
		return {}
	var state := _create_state(data, region_id, year, month)
	_active.append(state)
	return _snapshot_builder.build_active_snapshot(state, false, true, _history)


func get_active_snapshots(
	current_cpu: int = -1,
	current_energy: int = -1
) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	var funding_plan: Dictionary = {}
	if current_cpu >= 0 and current_energy >= 0:
		funding_plan = _funding_planner.build_plan(
			_active,
			current_cpu,
			current_energy
		)
	for state in _active:
		var instance_id := state.instance_id
		var funding_known := funding_plan.has(instance_id)
		var funding_entry: Dictionary = funding_plan.get(instance_id, {})
		var is_funded := bool(funding_entry.get("funded", not state.last_unfunded))
		snapshots.append(
			_snapshot_builder.build_active_snapshot(
				state,
				funding_known,
				is_funded,
				_history
			)
		)
	return snapshots


func get_active_count() -> int:
	return _active.size()


func get_active_count_by_region(region_id: String) -> int:
	var count := 0
	for state in _active:
		if state.region_id == region_id:
			count += 1
	return count


func has_active_region(region_id: String) -> bool:
	return get_active_count_by_region(region_id) > 0


func has_pending_node() -> bool:
	for state in _active:
		if state.node_pending:
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


## 导出供未来存档使用的局势运行态，只包含可序列化基础类型。
func export_runtime_snapshot() -> Dictionary:
	var active: Array[Dictionary] = []
	for state in _active:
		active.append(state.to_runtime_snapshot())
	return {
		"version": RUNTIME_SNAPSHOT_VERSION,
		"seed": run_seed,
		"rng_state": _rng.state,
		"instance_counter": _instance_counter,
		"spawn_cooldown_months": _spawn_cooldown_months,
		"repeat_cooldowns": _repeat_cooldowns.duplicate(true),
		"history": _history.duplicate(true),
		"active": active,
	}


## 校验并原子恢复局势运行态；任何失败都不会改变当前状态。
func restore_runtime_snapshot(snapshot: Dictionary) -> bool:
	var parsed: Dictionary = _parse_runtime_snapshot(snapshot)
	if not bool(parsed.get("success", false)):
		return false
	var restored_active: Array[SituationInstanceState] = parsed["active"]
	run_seed = int(parsed["seed"])
	_rng.seed = run_seed
	_rng.state = int(parsed["rng_state"])
	_instance_counter = int(parsed["instance_counter"])
	_spawn_cooldown_months = int(parsed["spawn_cooldown_months"])
	_repeat_cooldowns = parsed["repeat_cooldowns"]
	_history = parsed["history"]
	_active = restored_active
	return true


func _parse_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var version: Variant = snapshot.get("version", null)
	if not _is_int(version) or int(version) != RUNTIME_SNAPSHOT_VERSION:
		return {"success": false}
	var snapshot_seed: Variant = snapshot.get("seed", null)
	var rng_state: Variant = snapshot.get("rng_state", null)
	var instance_counter: Variant = snapshot.get("instance_counter", null)
	var spawn_cooldown_months: Variant = snapshot.get("spawn_cooldown_months", null)
	if not _is_int(snapshot_seed) or int(snapshot_seed) <= 0:
		return {"success": false}
	if not _is_int(rng_state) or int(rng_state) < 0:
		return {"success": false}
	if not _is_int(instance_counter) or int(instance_counter) < 0:
		return {"success": false}
	if not _is_int(spawn_cooldown_months) or int(spawn_cooldown_months) < 0:
		return {"success": false}

	var raw_repeat_cooldowns: Variant = snapshot.get("repeat_cooldowns", null)
	if not _validate_repeat_cooldowns(raw_repeat_cooldowns):
		return {"success": false}
	var raw_history: Variant = snapshot.get("history", null)
	if not _validate_history(raw_history):
		return {"success": false}
	var raw_active: Variant = snapshot.get("active", null)
	if typeof(raw_active) != TYPE_ARRAY:
		return {"success": false}
	var active_entries: Array = raw_active
	if active_entries.size() > MAX_ACTIVE:
		return {"success": false}
	var active: Array[SituationInstanceState] = []
	var seen_instance_ids: Dictionary = {}
	for entry_variant in active_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			return {"success": false}
		var entry: Dictionary = entry_variant
		var state := _parse_state_snapshot(entry, seen_instance_ids)
		if state == null:
			return {"success": false}
		active.append(state)

	var repeat_cooldowns: Dictionary = raw_repeat_cooldowns
	var history: Dictionary = raw_history
	return {
		"success": true,
		"seed": int(snapshot_seed),
		"rng_state": int(rng_state),
		"instance_counter": int(instance_counter),
		"spawn_cooldown_months": int(spawn_cooldown_months),
		"repeat_cooldowns": repeat_cooldowns.duplicate(true),
		"history": history.duplicate(true),
		"active": active,
	}


func _parse_state_snapshot(
	entry: Dictionary,
	seen_instance_ids: Dictionary
) -> SituationInstanceState:
	var instance_id: Variant = entry.get("instance_id", null)
	var situation_id: Variant = entry.get("situation_id", null)
	var region_id: Variant = entry.get("region_id", null)
	var severity: Variant = entry.get("severity", null)
	var stage: Variant = entry.get("stage", null)
	var approach_id: Variant = entry.get("approach_id", null)
	var switch_lock_months: Variant = entry.get("switch_lock_months", null)
	var started_year: Variant = entry.get("started_year", null)
	var started_month: Variant = entry.get("started_month", null)
	var last_unfunded: Variant = entry.get("last_unfunded", null)
	var node_pending: Variant = entry.get("node_pending", null)
	var node_resolved: Variant = entry.get("node_resolved", null)
	var node_choice_id: Variant = entry.get("node_choice_id", null)
	var node_choice_name: Variant = entry.get("node_choice_name", null)
	var node_result_text: Variant = entry.get("node_result_text", null)
	if not _is_string(instance_id) or str(instance_id).is_empty():
		return null
	if seen_instance_ids.has(str(instance_id)):
		return null
	if not _is_string(situation_id) or str(situation_id).is_empty():
		return null
	if not _is_string(region_id) or not RegionIdentity.is_valid_id(str(region_id)):
		return null
	if not _is_int(severity) or int(severity) < 0 or int(severity) > 100:
		return null
	if not _is_int(stage) or int(stage) != _stage_for_severity(int(severity)):
		return null
	if not _is_string(approach_id):
		return null
	if not _is_int(switch_lock_months):
		return null
	if int(switch_lock_months) < 0 or int(switch_lock_months) > APPROACH_SWITCH_LOCK_MONTHS:
		return null
	if not _is_int(started_year) or int(started_year) < 2044 or int(started_year) > 2075:
		return null
	if not _is_int(started_month) or int(started_month) < 1 or int(started_month) > 12:
		return null
	if not _is_bool(last_unfunded) or not _is_bool(node_pending) or not _is_bool(node_resolved):
		return null
	if not _is_string(node_choice_id) or not _is_string(node_choice_name):
		return null
	if not _is_string(node_result_text):
		return null

	var data := _get_template(str(situation_id))
	if data == null:
		return null
	if str(approach_id) != "" and data.get_approach(str(approach_id)) == null:
		return null
	if str(approach_id).is_empty() and bool(last_unfunded):
		return null
	if bool(node_pending) and bool(node_resolved):
		return null
	if data.situation_node == null:
		if bool(node_pending) or bool(node_resolved):
			return null
		if not str(node_choice_id).is_empty() or not str(node_choice_name).is_empty():
			return null
		if not str(node_result_text).is_empty():
			return null
	else:
		var node := data.situation_node
		if bool(node_pending):
			if int(stage) < node.trigger_stage:
				return null
			if not str(node_choice_id).is_empty():
				return null
			if not str(node_choice_name).is_empty() or not str(node_result_text).is_empty():
				return null
		elif bool(node_resolved):
			if str(node_choice_id).is_empty():
				return null
			var option := node.get_option(str(node_choice_id))
			if option == null or str(node_choice_name) != option.display_name:
				return null
			if str(node_result_text) != option.result_text:
				return null
		else:
			if int(stage) >= node.trigger_stage:
				return null
			if not str(node_choice_id).is_empty():
				return null
			if not str(node_choice_name).is_empty() or not str(node_result_text).is_empty():
				return null

	seen_instance_ids[str(instance_id)] = true
	var state := SituationInstanceState.new()
	state.instance_id = str(instance_id)
	state.data = data
	state.region_id = str(region_id)
	state.severity = int(severity)
	state.stage = int(stage)
	state.approach_id = str(approach_id)
	state.switch_lock_months = int(switch_lock_months)
	state.started_year = int(started_year)
	state.started_month = int(started_month)
	state.last_unfunded = bool(last_unfunded)
	state.node_pending = bool(node_pending)
	state.node_resolved = bool(node_resolved)
	state.node_choice_id = str(node_choice_id)
	state.node_choice_name = str(node_choice_name)
	state.node_result_text = str(node_result_text)
	return state


func _validate_repeat_cooldowns(raw_cooldowns: Variant) -> bool:
	if typeof(raw_cooldowns) != TYPE_DICTIONARY:
		return false
	var cooldowns: Dictionary = raw_cooldowns
	for key_variant in cooldowns.keys():
		if not _is_string(key_variant):
			return false
		if not _is_int(cooldowns[key_variant]):
			return false
		if int(cooldowns[key_variant]) <= 0 or int(cooldowns[key_variant]) > REPEAT_COOLDOWN_MONTHS:
			return false
		if not _is_valid_cooldown_key(str(key_variant)):
			return false
	return true


func _validate_history(raw_history: Variant) -> bool:
	if typeof(raw_history) != TYPE_DICTIONARY:
		return false
	var history: Dictionary = raw_history
	for key_variant in history.keys():
		if not _is_string(key_variant):
			return false
		var key := str(key_variant)
		var data := _get_cooldown_template(key)
		if data == null:
			return false
		var entry_variant: Variant = history[key_variant]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			return false
		var entry: Dictionary = entry_variant
		var occurrences: Variant = entry.get("occurrences", null)
		var successes: Variant = entry.get("successes", null)
		var failures: Variant = entry.get("failures", null)
		if not _is_int(occurrences) or not _is_int(successes) or not _is_int(failures):
			return false
		if int(occurrences) <= 0 or int(successes) < 0 or int(failures) < 0:
			return false
		if int(successes) + int(failures) != int(occurrences):
			return false
		if not _is_bool(entry.get("last_success", null)):
			return false
		var situation_kind: Variant = entry.get("situation_kind", null)
		if not _is_int(situation_kind) or int(situation_kind) != data.situation_kind:
			return false
		var last_approach_id: Variant = entry.get("last_approach_id", null)
		var last_node_choice_id: Variant = entry.get("last_node_choice_id", null)
		var last_node_choice_name: Variant = entry.get("last_node_choice_name", null)
		if not _is_string(last_approach_id) or not _is_string(last_node_choice_id):
			return false
		if not _is_string(last_node_choice_name):
			return false
		if str(last_approach_id) != "" and data.get_approach(str(last_approach_id)) == null:
			return false
		if str(last_node_choice_id).is_empty():
			if not str(last_node_choice_name).is_empty():
				return false
		elif data.situation_node == null:
			return false
		else:
			var option := data.situation_node.get_option(str(last_node_choice_id))
			if option == null or str(last_node_choice_name) != option.display_name:
				return false
	return true


func _is_valid_cooldown_key(key: String) -> bool:
	return _get_cooldown_template(key) != null


func _get_cooldown_template(key: String) -> SituationData:
	var parts := key.split("|")
	if parts.size() != 2 or not RegionIdentity.is_valid_id(parts[1]):
		return null
	return _get_template(parts[0])


func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


func _is_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING


func _is_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL


func _try_start_random(
	sectors: Array[SectorData],
	current_cpu: int,
	current_energy: int,
	year: int,
	month: int,
	facts: Dictionary,
	notifications: Array[Dictionary]
) -> void:
	if not _spawn_planner.should_start(_rng.randi_range(1, 1000)):
		return

	var active_regions: Dictionary = {}
	for state in _active:
		active_regions[state.region_id] = true
	var candidates := _spawn_planner.build_candidates(
		_templates,
		sectors,
		active_regions,
		_repeat_cooldowns,
		year,
		month,
		facts,
		current_cpu,
		current_energy
	)
	var total_weight := _spawn_planner.get_total_weight(candidates)

	if candidates.is_empty() or total_weight <= 0:
		return

	var candidate := _spawn_planner.pick_candidate(
		candidates,
		_rng.randi_range(1, total_weight)
	)
	if candidate.is_empty():
		return
	var state := _create_state(
		candidate["data"],
		str(candidate["region_id"]),
		year,
		month
	)
	_active.append(state)
	_spawn_cooldown_months = SPAWN_COOLDOWN_MONTHS
	notifications.append(
		_snapshot_builder.build_notification(
			"started",
			state,
			"新的随机局势已经出现。",
			true,
			_history
		)
	)


func _finish_situation(
	index: int,
	sectors: Array[SectorData],
	success: bool,
	notifications: Array[Dictionary]
) -> void:
	var state: SituationInstanceState = _active[index]
	var data: SituationData = state.data
	_apply_outcome(state, sectors, success)
	_repeat_cooldowns[_cooldown_key(data.situation_id, state.region_id)] = (
		REPEAT_COOLDOWN_MONTHS
	)
	var message := "局势已经恢复到安全边界。" if success else "局势失控并造成区域损失。"
	if data.situation_kind == 1:
		message = "协作窗口已经转化为地区恢复。" if success else "协作窗口已经关闭。"
	notifications.append(
		_snapshot_builder.build_notification(
			"resolved" if success else "failed",
			state,
			message,
			false,
			_history
		)
	)
	_record_history(state, success)
	_active.remove_at(index)
	_spawn_cooldown_months = maxi(_spawn_cooldown_months, SPAWN_COOLDOWN_MONTHS)


func _apply_outcome(
	state: SituationInstanceState,
	sectors: Array[SectorData],
	success: bool
) -> void:
	var sector := _find_sector_data(sectors, state.region_id)
	if sector == null:
		return
	var data: SituationData = state.data
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

	var approach := data.get_approach(state.approach_id)
	if approach != null:
		sector.order += approach.resolution_order_delta
		sector.hope += approach.resolution_hope_delta
		sector.authority += approach.resolution_authority_delta
	sector.clamp_values()


func _create_state(
	data: SituationData,
	region_id: String,
	year: int,
	month: int
) -> SituationInstanceState:
	_instance_counter += 1
	var state := SituationInstanceState.new()
	state.instance_id = "%s:%s:%d" % [data.situation_id, region_id, _instance_counter]
	state.data = data
	state.region_id = region_id
	state.severity = data.initial_severity
	state.stage = _month_resolver.stage_for_severity(data.initial_severity)
	state.started_year = year
	state.started_month = month
	_month_resolver.activate_node_if_ready(state)
	return state


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


func _find_state(instance_id: String) -> SituationInstanceState:
	for state in _active:
		if state.instance_id == instance_id:
			return state
	return null


func _get_template(situation_id: String) -> SituationData:
	for data in _templates:
		if data != null and data.situation_id == situation_id:
			return data
	return null


func _find_sector_data(sectors: Array[SectorData], region_id: String) -> SectorData:
	for sector in sectors:
		if sector != null and sector.region_id == region_id:
			return sector
	return null


## 按稳定 ID 查询模板是否满足当前年份与历史事实门槛。
func is_template_eligible(
	situation_id: String,
	year: int,
	facts: Dictionary = {}
) -> bool:
	return _spawn_planner.is_template_eligible(_templates, situation_id, year, facts)


func _record_history(state: SituationInstanceState, success: bool) -> void:
	var data: SituationData = state.data
	var key := _cooldown_key(data.situation_id, state.region_id)
	var previous: Dictionary = _history.get(key, {})
	_history[key] = {
		"occurrences": int(previous.get("occurrences", 0)) + 1,
		"successes": int(previous.get("successes", 0)) + (1 if success else 0),
		"failures": int(previous.get("failures", 0)) + (0 if success else 1),
		"last_success": success,
		"situation_kind": data.situation_kind,
		"last_approach_id": state.approach_id,
		"last_node_choice_id": state.node_choice_id,
		"last_node_choice_name": state.node_choice_name,
	}


func _tick_repeat_cooldowns() -> void:
	for key in _repeat_cooldowns.keys():
		var remaining := int(_repeat_cooldowns[key]) - 1
		if remaining <= 0:
			_repeat_cooldowns.erase(key)
		else:
			_repeat_cooldowns[key] = remaining


func _stage_for_severity(severity: int) -> int:
	return _month_resolver.stage_for_severity(severity)


func _cooldown_key(situation_id: String, region_id: String) -> String:
	return _spawn_planner.cooldown_key(situation_id, region_id)
