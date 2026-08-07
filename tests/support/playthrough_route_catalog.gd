## 三条完整通关路线的稳定配置与事件方案查找。
class_name PlaythroughRouteCatalog
extends RefCounted

const ROUTE_CONFIGS: Dictionary = {
	"mixed": {
		"expected_ending": "coexistence",
		"mid_choice": 1,
		"final_choice": 1,
		"branch_choice": 1,
		"situation_approach": 1,
		"situation_node_choice": 0,
		"command_id": "technology_aid",
		"command_start_year": 2064,
		"minimum_command_count": 3,
		"technology_nodes": [
			"managed_decision",
			"core_hot_redundancy",
			"managed_infrastructure",
			"managed_global_network",
			"human_open_interface",
			"human_public_decision",
			"core_load_migration",
			"human_mutual_aid",
		],
		"core_choices": {
			"太空电梯危机": "human_command",
			"大淹没事故": "infrastructure_first",
			"月球坠落危机": "human_final_authority",
			"AI隔离审查": "limited_disclosure",
			"西伯利亚发动机群过载": "redundant_array",
		},
		"history_fragments": ["只披露有限接口", "备用阵列"],
	},
	"managed": {
		"expected_ending": "managed",
		"mid_choice": 2,
		"final_choice": 2,
		"branch_choice": 2,
		"situation_approach": 2,
		"situation_node_choice": 1,
		"command_id": "global_takeover",
		"command_start_year": 2056,
		"minimum_command_count": 4,
		"technology_nodes": [
			"managed_decision",
			"managed_behavior_prediction",
			"managed_infrastructure",
			"managed_global_network",
			"managed_authority_audit",
			"core_hot_redundancy",
			"managed_irreplaceable_protocol",
			"core_energy_mapping",
		],
		"core_choices": {
			"太空电梯危机": "public_counterstrike",
			"大淹没事故": "sacrifice_perimeter",
			"月球坠落危机": "forced_takeover",
			"AI隔离审查": "hidden_core_chain",
			"西伯利亚发动机群过载": "forced_overclock",
		},
		"history_fragments": [
			"隐藏核心链路",
			"强制超频",
			"外围补偿申诉",
			"审计轨迹",
		],
	},
	"human_autonomy": {
		"expected_ending": "human_autonomy",
		"mid_choice": 0,
		"final_choice": 0,
		"branch_choice": 0,
		"situation_approach": 0,
		"situation_node_choice": 0,
		"command_id": "technology_aid",
		"command_start_year": 2060,
		"minimum_command_count": 4,
		"technology_nodes": [
			"human_open_interface",
			"human_public_decision",
			"human_autonomy_network",
			"human_emergency_training",
			"human_mutual_aid",
			"core_hot_redundancy",
			"human_civilization_self_sustain",
			"core_energy_mapping",
		],
		"core_choices": {
			"太空电梯危机": "human_command",
			"大淹没事故": "population_first",
			"月球坠落危机": "human_final_authority",
			"AI隔离审查": "full_compliance",
			"西伯利亚发动机群过载": "personnel_first_shutdown",
		},
		"history_fragments": ["完整接受隔离审查", "分段停机优先保护工程人员"],
	},
}


## 返回路线配置副本，避免测试过程改写共享常量。
func get_route_config(route_id: String) -> Dictionary:
	var route_config: Dictionary = ROUTE_CONFIGS.get(route_id, {})
	return route_config.duplicate(true)


## 根据玩家可见事件标题和真实资源标签定位路线方案。
func get_event_choice_index(
	route_config: Dictionary,
	main_os: Control,
	title: String,
	year: int,
	month: int
) -> int:
	var core_choices: Dictionary = route_config.get("core_choices", {})
	if core_choices.has(title):
		var expected_value := str(core_choices[title])
		var source_event := find_source_event(main_os, title, year, month)
		if source_event == null:
			return -1
		for index in range(source_event.options.size()):
			if source_event.options[index].decision_tag_value == expected_value:
				return index
		return -1
	if title == "木星引力危机":
		return int(route_config.get("final_choice", 0))
	if title in ["外围地下城补偿申诉", "隐藏链路异常回执"]:
		return int(route_config.get("branch_choice", 0))
	return int(route_config.get("mid_choice", 0))


## 从主场景真实事件列表中定位指定年月的资源。
func find_source_event(main_os: Control, title: String, year: int, month: int) -> GameEvent:
	for event_variant in main_os.all_events:
		var event := event_variant as GameEvent
		if (
			event != null
			and event.event_title == title
			and event.event_time == year
			and event.event_month == month
		):
			return event
	return null
