## 随机局势只读快照与通知构建服务。
## 只读取显式运行态、模板和历史，不持有活跃集合或场景节点。
class_name SituationSnapshotBuilder
extends RefCounted


func build_active_snapshot(
	state: SituationInstanceState,
	funding_known: bool = false,
	is_funded: bool = true,
	history: Dictionary = {}
) -> Dictionary:
	var data: SituationData = state.data
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
	var active_approach: SituationApproachData = data.get_approach(state.approach_id)
	var expected_delta: int = data.monthly_growth
	var approach_name := "尚未选择"
	var funding_required := false
	var effective_funded := is_funded if funding_known else not state.last_unfunded
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
	var region_id := state.region_id
	return {
		"instance_id": state.instance_id,
		"situation_id": data.situation_id,
		"title": data.title,
		"description": data.get_region_description(region_id),
		"region_id": region_id,
		"region_name": RegionIdentity.display_name(region_id),
		"severity": state.severity,
		"stage": state.stage,
		"stage_name": data.get_stage_name(state.stage),
		"progress_label": data.progress_label,
		"is_opportunity": data.situation_kind == 1,
		"approach_id": state.approach_id,
		"approach_name": approach_name,
		"switch_lock_months": state.switch_lock_months,
		"expected_monthly_delta": expected_delta,
		"funding_required": funding_required,
		"funding_known": funding_known,
		"is_funded": effective_funded,
		"last_unfunded": state.last_unfunded,
		"started_year": state.started_year,
		"started_month": state.started_month,
		"approaches": approaches,
		"node": build_node_snapshot(state),
		"history_echo": build_history_echo(data.situation_id, region_id, history),
	}


func build_notification(
	type: String,
	state: SituationInstanceState,
	message: String,
	pause: bool,
	history: Dictionary = {}
) -> Dictionary:
	var data: SituationData = state.data
	if type in ["started", "resolved", "failed"]:
		var history_echo := build_history_echo(data.situation_id, state.region_id, history)
		if history_echo != "":
			message += "\n历史回声：" + history_echo
	return {
		"type": type,
		"instance_id": state.instance_id,
		"title": data.title,
		"region_id": state.region_id,
		"region_name": RegionIdentity.display_name(state.region_id),
		"message": message,
		"pause": pause,
	}


func build_node_snapshot(state: SituationInstanceState) -> Dictionary:
	var data: SituationData = state.data
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
		"pending": state.node_pending,
		"resolved": state.node_resolved,
		"node_id": data.situation_node.node_id,
		"title": data.situation_node.title,
		"description": data.situation_node.description,
		"choice_id": state.node_choice_id,
		"choice_name": state.node_choice_name,
		"result_text": state.node_result_text,
		"options": options,
	}


func build_history_echo(
	situation_id: String,
	region_id: String,
	history: Dictionary
) -> String:
	var key := "%s|%s" % [situation_id, region_id]
	var raw_history: Variant = history.get(key, {})
	if typeof(raw_history) != TYPE_DICTIONARY:
		return ""
	var history_entry: Dictionary = raw_history
	if history_entry.is_empty():
		return ""
	var is_opportunity := int(history_entry.get("situation_kind", 0)) == 1
	var result_text := ""
	if bool(history_entry.get("last_success", false)):
		result_text = "成功利用协作窗口" if is_opportunity else "成功处理"
	else:
		result_text = "协作窗口关闭" if is_opportunity else "处置失控"
	var choice_name := str(history_entry.get("last_node_choice_name", ""))
	var region_name := RegionIdentity.display_name(region_id)
	if choice_name != "":
		return "上次在%s选择“%s”，最终%s。" % [region_name, choice_name, result_text]
	return "上次在%s的同类局势最终%s。" % [region_name, result_text]
