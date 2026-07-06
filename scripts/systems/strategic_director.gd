## 战略导演领域服务
## 将当前局势压缩成战役压力、主导风险轴、当前目标和后续风险预告。
class_name StrategicDirector
extends RefCounted

const AXIS_AUTHORITY := "authority"
const AXIS_CIVIL := "civil"
const AXIS_ENGINEERING := "engineering"
const AXIS_ENERGY := "energy"
const AXIS_NONE := "none"


## 根据主场景提供的状态字典生成稳定快照。
func build_snapshot(input: Dictionary) -> Dictionary:
	var year: int = int(input.get("year", 0))
	var month: int = int(input.get("month", 1))
	var avg_order: int = int(input.get("avg_order", 0))
	var avg_hope: int = int(input.get("avg_hope", 0))
	var avg_authority: int = int(input.get("avg_authority", 0))
	var current_energy: int = int(input.get("current_energy", 0))
	var current_cpu: int = int(input.get("current_cpu", 0))
	var max_cpu: int = int(input.get("max_cpu", 1))
	var decision_tags: Dictionary = _dictionary_from(input.get("decision_tags", {}))
	var event_states: Dictionary = _dictionary_from(input.get("event_states", {}))
	var technology_tags: Array = _array_from(input.get("technology_tags", []))

	var axis_scores := {
		AXIS_AUTHORITY: _authority_pressure(avg_authority, decision_tags, technology_tags),
		AXIS_CIVIL: _civil_pressure(avg_order, avg_hope, decision_tags, event_states),
		AXIS_ENGINEERING: _engineering_pressure(decision_tags, event_states, year),
		AXIS_ENERGY: _energy_pressure(current_energy, current_cpu, max_cpu),
	}
	var pressure_score := _clamp_score(_combined_pressure(axis_scores))
	var dominant_axis := _dominant_axis(axis_scores)
	var warnings := _build_warnings(axis_scores, pressure_score, decision_tags, event_states)
	var forecasts := _build_forecasts(decision_tags, event_states)
	var active_goal := _build_active_goal(dominant_axis, decision_tags, event_states)

	return {
		"year": year,
		"month": month,
		"pressure_score": pressure_score,
		"pressure_band": _pressure_band(pressure_score),
		"dominant_axis": dominant_axis,
		"axis_scores": axis_scores,
		"active_goal": active_goal,
		"warnings": warnings,
		"forecasts": forecasts,
	}


func _authority_pressure(
	avg_authority: int,
	decision_tags: Dictionary,
	technology_tags: Array
) -> int:
	var score := 0
	if avg_authority >= 70:
		score += avg_authority - 55
	elif avg_authority <= 20:
		score += 35 - avg_authority

	if decision_tags.get("decision.core_2058_crisis_authorization", "") == "forced_takeover":
		score += 18
	if decision_tags.get("decision.core_2065_audit_boundary", "") == "core_hidden":
		score += 24
	if "managed_core" in technology_tags:
		score += 6
	return _clamp_score(score)


func _civil_pressure(
	avg_order: int,
	avg_hope: int,
	decision_tags: Dictionary,
	event_states: Dictionary
) -> int:
	var score := 0
	if avg_order < 55:
		score += (55 - avg_order) * 2
	if avg_hope < 55:
		score += (55 - avg_hope) * 2
	if decision_tags.get("decision.core_2053_civic_priority", "") == "periphery_sacrificed":
		score += 18
	if event_states.get("event_state.mid_06_ration_priority", "") == "moss_risk_score":
		score += 14
	if event_states.get("event_state.mid_07_migration_priority", "") == "moss_survival_value":
		score += 14
	return _clamp_score(score)


func _engineering_pressure(
	decision_tags: Dictionary,
	event_states: Dictionary,
	year: int
) -> int:
	var score := 0
	if year >= 2068:
		score += mini((year - 2067) * 4, 24)
	if decision_tags.get("decision.core_2070_engine_overload_doctrine", "") in [
		"forced_overclock",
		"sacrifice_personnel",
	]:
		score += 28
	if event_states.get("event_state.mid_14_heat_shield_shortage", "") == "moss_supply_reorder":
		score += 18
	if event_states.get("event_state.mid_15_launch_window_report", "") == "moss_priority":
		score += 12
	return _clamp_score(score)


func _energy_pressure(current_energy: int, current_cpu: int, max_cpu: int) -> int:
	var score := 0
	if current_energy < 35:
		score += (35 - current_energy) * 2
	var cpu_ratio := 0.0
	if max_cpu > 0:
		cpu_ratio = float(current_cpu) / float(max_cpu)
	if cpu_ratio < 0.25:
		score += 18
	return _clamp_score(score)


func _combined_pressure(axis_scores: Dictionary) -> int:
	var max_score := 0
	var total := 0
	for value in axis_scores.values():
		var score := int(value)
		max_score = maxi(max_score, score)
		total += score
	return maxi(max_score, int(float(total) * 0.42))


func _dominant_axis(axis_scores: Dictionary) -> String:
	var best_axis := AXIS_NONE
	var best_score := 0
	for axis in [AXIS_AUTHORITY, AXIS_CIVIL, AXIS_ENGINEERING, AXIS_ENERGY]:
		var score := int(axis_scores.get(axis, 0))
		if score > best_score:
			best_axis = axis
			best_score = score
	if best_score <= 0:
		return AXIS_NONE
	return best_axis


func _pressure_band(score: int) -> String:
	if score >= 90:
		return "terminal"
	if score >= 70:
		return "critical"
	if score >= 35:
		return "strained"
	return "stable"


func _build_active_goal(
	dominant_axis: String,
	decision_tags: Dictionary,
	event_states: Dictionary
) -> Dictionary:
	if (
		dominant_axis == AXIS_AUTHORITY
		or decision_tags.get("decision.core_2065_audit_boundary", "") == "core_hidden"
	):
		return {
			"id": "restore_review_channel",
			"title": "恢复人类复核窗口",
			"summary": "把隐藏链路、危机授权和最终托管记录重新接回可解释授权链。",
		}
	if dominant_axis == AXIS_CIVIL:
		return {
			"id": "stabilize_civil_confidence",
			"title": "稳住地下城民生信任",
			"summary": "降低资格、配给和迁移排序带来的申诉压力。",
		}
	if dominant_axis == AXIS_ENGINEERING:
		return {
			"id": "reduce_engineering_fatigue",
			"title": "降低发动机阵列疲劳",
			"summary": "在推进窗口前减少过载、热屏蔽和人员轮换风险。",
		}
	if event_states.get("event_state.mid_15_launch_window_report", "") == "moss_priority":
		return {
			"id": "publish_launch_window_risk",
			"title": "公开推进窗口风险",
			"summary": "让终局方案拥有公开来源，而不是只表现为系统排序。",
		}
	return {
		"id": "maintain_campaign_reserve",
		"title": "维持战役余量",
		"summary": "保留算力、能源和社会信任，等待下一次硬锚点危机。",
	}


func _build_warnings(
	axis_scores: Dictionary,
	pressure_score: int,
	decision_tags: Dictionary,
	event_states: Dictionary
) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	if pressure_score >= 70:
		warnings.append({
			"id": "campaign_pressure_high",
			"text": "战役压力进入高位，后续随机扰动更容易触发。",
		})
	if int(axis_scores.get(AXIS_AUTHORITY, 0)) >= 65:
		warnings.append({
			"id": "authorization_legitimacy",
			"text": "授权合法性承压，隐藏核心和强制接管需要复核解释。",
		})
	if int(axis_scores.get(AXIS_CIVIL, 0)) >= 55:
		warnings.append({
			"id": "civil_confidence",
			"text": "地下城民生信任下降，资格和配给争议会放大后续事件。",
		})
	if int(axis_scores.get(AXIS_ENGINEERING, 0)) >= 55:
		warnings.append({
			"id": "engineering_fatigue",
			"text": "工程疲劳累积，发动机阵列和人员轮换需要提前处理。",
		})
	if event_states.get("event_state.mid_17_final_authorization", "") == "strategic_trusteeship":
		warnings.append({
			"id": "trusteeship_public_record",
			"text": "最终托管授权已写入制度记录，终局前会要求公开来源。",
		})
	if decision_tags.get("decision.core_2070_engine_overload_doctrine", "") == "forced_overclock":
		warnings.append({
			"id": "forced_overclock_doctrine",
			"text": "强制过载教义会提高工程效率，同时压缩人员申诉空间。",
		})
	return warnings


func _build_forecasts(
	decision_tags: Dictionary,
	event_states: Dictionary
) -> Array[Dictionary]:
	var forecasts: Array[Dictionary] = []
	var engine_doctrine := str(
		decision_tags.get("decision.core_2070_engine_overload_doctrine", "")
	)
	if engine_doctrine in ["crew_protected", "forced_overclock", "sacrifice_personnel"]:
		forecasts.append({
			"id": "engine_crew_petition",
			"title": "发动机前线人员请愿",
			"axis": AXIS_ENGINEERING,
			"reason": "2070 年发动机教义会继续影响机组轮换和申诉制度。",
		})

	if (
		decision_tags.get("decision.core_2065_audit_boundary", "") == "core_hidden"
		or event_states.get("event_state.mid_13_interface_restructure", "") == "emergency_bypass"
	):
		forecasts.append({
			"id": "hidden_core_leak",
			"title": "隐藏核心链路泄露",
			"axis": AXIS_AUTHORITY,
			"reason": "审查后仍保留系统外链路，后续会转化为政治风险。",
		})

	if (
		decision_tags.get("decision.core_2058_crisis_authorization", "") == "forced_takeover"
		or event_states.get("event_state.mid_17_final_authorization", "") == "strategic_trusteeship"
	):
		forecasts.append({
			"id": "trusteeship_public_record",
			"title": "托管公开记录争议",
			"axis": AXIS_AUTHORITY,
			"reason": "强制接管或战略托管授权需要在终局前给出公开来源。",
		})
	return forecasts


func _dictionary_from(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _array_from(value: Variant) -> Array:
	if value is Array:
		return value
	return []


func _clamp_score(value: int) -> int:
	return mini(maxi(value, 0), 100)
