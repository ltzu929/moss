## 随机局势单项月结算服务。
## 接收状态副本和显式资源计划，返回新状态与通知数据，不删除集合或写入板块/UI。
class_name SituationMonthResolver
extends RefCounted

const WARNING_THRESHOLD: int = 40
const CRITICAL_THRESHOLD: int = 70


## 结算单个活跃局势，输入状态不会被修改。
func resolve_month(
	state: SituationInstanceState,
	funding_plan: Dictionary
) -> Dictionary:
	if state == null or state.data == null:
		return {"state": state, "status": "active", "notifications": []}
	var next_state := state.duplicate_state()
	var data: SituationData = next_state.data
	if next_state.switch_lock_months > 0:
		next_state.switch_lock_months -= 1

	var severity_delta: int = data.monthly_growth
	var approach: SituationApproachData = data.get_approach(next_state.approach_id)
	var plan: Dictionary = funding_plan.get(next_state.instance_id, {})
	var notifications: Array[Dictionary] = []
	if approach != null:
		var funded := bool(plan.get("funded", false))
		if funded:
			severity_delta += approach.monthly_severity_delta
			next_state.last_unfunded = false
		else:
			severity_delta += data.unfunded_growth_penalty
			if not next_state.last_unfunded:
				notifications.append(
					_raw_notification(
						"unfunded",
						"持续成本不足，%s 正在失效。" % approach.display_name,
						false
					)
				)
			next_state.last_unfunded = true

	var previous_stage := next_state.stage
	next_state.severity = clampi(next_state.severity + severity_delta, 0, 100)
	next_state.stage = stage_for_severity(next_state.severity)
	if next_state.stage > previous_stage:
		if activate_node_if_ready(next_state):
			notifications.append(
				_raw_notification(
					"node_available",
					"局势进入%s阶段，并出现待处理节点。" % data.get_stage_name(
						next_state.stage
					),
					true
				)
			)
		else:
			notifications.append(
				_raw_notification(
					"stage_worsened",
					"局势进入%s阶段。" % data.get_stage_name(next_state.stage),
					true
				)
			)

	var status := "active"
	if next_state.severity == 0:
		status = "success"
	elif next_state.severity >= 100:
		status = "failure"
	return {
		"state": next_state,
		"status": status,
		"notifications": notifications,
	}


func stage_for_severity(severity: int) -> int:
	if severity >= CRITICAL_THRESHOLD:
		return 2
	if severity >= WARNING_THRESHOLD:
		return 1
	return 0


func activate_node_if_ready(state: SituationInstanceState) -> bool:
	if state.node_resolved or state.node_pending:
		return false
	var data: SituationData = state.data
	if data.situation_node == null or data.situation_node.options.is_empty():
		return false
	if state.stage < data.situation_node.trigger_stage:
		return false
	state.node_pending = true
	return true


func _raw_notification(type: String, message: String, pause: bool) -> Dictionary:
	return {
		"type": type,
		"message": message,
		"pause": pause,
	}
