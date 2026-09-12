## 三条完整通关路线的稳定配置与事件方案查找。
class_name PlaythroughRouteCatalog
extends RefCounted

const ROUTE_CONFIGS: Dictionary = {
	"mixed": {
		"expected_ending": "coexistence",

		"final_choice": 1,

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
			"北京联网救援": "power_support",
			"月球危机最终支援": "human_final_authority",
			"行星发动机救援": "resource_support",
		},
		"history_fragments": ["供电支援", "追加支援投入"],
	},
	"managed": {
		"expected_ending": "managed",

		"final_choice": 2,

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
			"北京联网救援": "central_dispatch",
			"月球危机最终支援": "forced_takeover",
			"行星发动机救援": "central_dispatch",
		},
		"history_fragments": ["扩大自动调度权限", "集中调度系统支援"],
	},
	"human_autonomy": {
		"expected_ending": "human_autonomy",

		"final_choice": 0,

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
			"北京联网救援": "crew_confirmation",
			"月球危机最终支援": "human_final_authority",
			"行星发动机救援": "crew_priority",
		},
		"history_fragments": ["保留人类最终授权", "救援队确认支援顺序"],
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
	return -1


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
