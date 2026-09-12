## 负责事件选项的历史数值调整、科技减免和纯数值结算。
## 不访问场景树、Resource 模板、能源状态、板块节点、UI 或日志。
class_name EventResolutionSystem
extends RefCounted

const MIN_SECTOR_VALUE: int = 0
const MAX_SECTOR_VALUE: int = 100


## 根据前序核心决策和轻量事件状态调整运行时事件副本。
## 传入的 event 必须是可写的运行时副本，服务不会加载或修改原始模板。
func apply_event_option_adjustments(
	event: GameEvent,
	decision_tags: Dictionary,
	_event_states: Dictionary
) -> void:
	match event.event_id:
		"event_2058_lunar_fall_crisis":
			match _get_decision_tag(decision_tags, "decision.core_2044_automation_access"):
				"public_counterstrike":
					_add_option_energy_cost(event, "option_01", -10)
				"human_command":
					_add_option_delta(event, "option_02", "hope_delta", 5)
				"restricted_interface":
					_add_option_energy_cost(event, "option_01", 10)
			match _get_decision_tag(decision_tags, "decision.core_2058_network_support"):
				"power_support":
					_add_option_energy_cost(event, "option_01", -15)
				"crew_confirmation":
					_add_option_delta(event, "option_02", "hope_delta", 5)
				"central_dispatch":
					_add_option_energy_cost(event, "option_03", -10)
		"event_2075_engine_rescue":
			match _get_decision_tag(decision_tags, "decision.core_2058_crisis_authority"):
				"bounded_self_rescue":
					_add_option_energy_cost(event, "option_02", -10)
				"human_final_authority":
					_add_option_delta(event, "option_01", "hope_delta", 5)
				"forced_takeover":
					_add_option_delta(event, "option_03", "hope_delta", -5)
		"event_2075_jupiter_gravity_crisis":
			match _get_decision_tag(decision_tags, "decision.core_2075_rescue_support"):
				"crew_priority":
					_add_option_delta(event, "option_01", "hope_delta", 5)
				"resource_support":
					_add_option_energy_cost(event, "option_01", -15)
				"central_dispatch":
					_add_option_energy_cost(event, "option_03", -10)
					_add_option_delta(event, "option_03", "hope_delta", -5)


## 用同一份运行时选项快照同时生成预览和结算投影。
## preview 保留弹窗显示的历史调整值；resolution 才应用科技减免、能源可用量
## 和板块 0-100 限幅后的实际变化。
func calculate_option_projections(
	option: EventOption,
	technology_snapshot: Dictionary,
	sector_values: Dictionary,
	current_energy: int
) -> Dictionary:
	var preview := {
		"option_id": option.option_id,
		"order_delta": option.order_delta,
		"hope_delta": option.hope_delta,
		"authority_delta": option.authority_delta,
		"energy_cost": option.energy_cost,
	}
	var technology_order_delta := get_technology_adjusted_event_delta(
		option.order_delta,
		"order",
		technology_snapshot
	)
	var technology_hope_delta := get_technology_adjusted_event_delta(
		option.hope_delta,
		"hope",
		technology_snapshot
	)
	var current_order := clampi(
		int(sector_values.get("order", MIN_SECTOR_VALUE)),
		MIN_SECTOR_VALUE,
		MAX_SECTOR_VALUE
	)
	var current_hope := clampi(
		int(sector_values.get("hope", MIN_SECTOR_VALUE)),
		MIN_SECTOR_VALUE,
		MAX_SECTOR_VALUE
	)
	var current_authority := clampi(
		int(sector_values.get("authority", MIN_SECTOR_VALUE)),
		MIN_SECTOR_VALUE,
		MAX_SECTOR_VALUE
	)
	var resolved_order := clampi(
		current_order + technology_order_delta,
		MIN_SECTOR_VALUE,
		MAX_SECTOR_VALUE
	)
	var resolved_hope := clampi(
		current_hope + technology_hope_delta,
		MIN_SECTOR_VALUE,
		MAX_SECTOR_VALUE
	)
	var resolved_authority := clampi(
		current_authority + option.authority_delta,
		MIN_SECTOR_VALUE,
		MAX_SECTOR_VALUE
	)
	var resolved_energy_cost := clampi(
		option.energy_cost,
		0,
		maxi(0, current_energy)
	)
	var resolution := {
		"option_id": option.option_id,
		"order_delta": resolved_order - current_order,
		"hope_delta": resolved_hope - current_hope,
		"authority_delta": resolved_authority - current_authority,
		"energy_cost": resolved_energy_cost,
		"new_order": resolved_order,
		"new_hope": resolved_hope,
		"new_authority": resolved_authority,
	}
	return {
		"preview": preview,
		"resolution": resolution,
	}


## 只减轻秩序和希望的负面变化，正面变化及其他属性保持不变。
func get_technology_adjusted_event_delta(
	delta: int,
	stat: String,
	technology_snapshot: Dictionary
) -> int:
	if delta >= 0:
		return delta
	if stat not in ["order", "hope"]:
		return delta
	if not bool(technology_snapshot.get("human_event_mitigation", false)):
		return delta
	return ceili(float(delta) * 0.75)


func _get_decision_tag(decision_tags: Dictionary, key: String) -> String:
	return str(decision_tags.get(key, ""))


func _get_event_option(event: GameEvent, option_id: String) -> EventOption:
	for option in event.options:
		if option.option_id == option_id:
			return option
	return null


func _add_option_energy_cost(event: GameEvent, option_id: String, delta: int) -> void:
	var option := _get_event_option(event, option_id)
	if option != null:
		option.energy_cost = maxi(option.energy_cost + delta, 0)


func _add_option_delta(
	event: GameEvent,
	option_id: String,
	property_name: String,
	delta: int
) -> void:
	var option := _get_event_option(event, option_id)
	if option != null:
		option.set(property_name, int(option.get(property_name)) + delta)
