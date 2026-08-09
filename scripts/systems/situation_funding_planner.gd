## 随机局势资源计划服务。
## 按真实逆序结算顺序预演每个活跃局势的持续成本，不修改状态或资源。
class_name SituationFundingPlanner
extends RefCounted


## 返回 {instance_id: {funded, cpu_cost, energy_cost}} 计划。
func build_plan(
	states: Array[SituationInstanceState],
	current_cpu: int,
	current_energy: int
) -> Dictionary:
	var plan: Dictionary = {}
	var remaining_cpu := current_cpu
	var remaining_energy := current_energy
	for index in range(states.size() - 1, -1, -1):
		var state: SituationInstanceState = states[index]
		if state == null:
			continue
		var cpu_cost := 0
		var energy_cost := 0
		var funded := true
		if state.data != null:
			var approach: SituationApproachData = state.data.get_approach(state.approach_id)
			if approach != null:
				cpu_cost = approach.monthly_cpu_cost
				energy_cost = approach.monthly_energy_cost
				funded = remaining_cpu >= cpu_cost and remaining_energy >= energy_cost
				if funded:
					remaining_cpu -= cpu_cost
					remaining_energy -= energy_cost
		plan[state.instance_id] = {
			"funded": funded,
			"cpu_cost": cpu_cost,
			"energy_cost": energy_cost,
		}
	return plan
