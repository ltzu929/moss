## 读取本局实际决策，生成危机支援的历史回声；不补写原作因果。
class_name EventNarrativeSystem
extends RefCounted

var _decision_history: DecisionHistory


func configure(_event_state_store: EventStateStore, decision_history: DecisionHistory) -> void:
	_decision_history = decision_history


func build_event_description(event: GameEvent) -> String:
	var lines := _get_event_context_lines(event)
	if lines.is_empty():
		return event.event_description
	return "%s\n\n[color=#73C9D3]本局历史回声[/color]\n- %s" % [
		event.event_description, "\n- ".join(lines),
	]


## 只更新显示后缀，数值仍由 EventResolutionSystem 调整。
func apply_option_display_text(event: GameEvent) -> void:
	match event.event_id:
		"event_2058_lunar_fall_crisis":
			match _get_decision_tag("decision.core_2044_automation_access"):
				"public_counterstrike":
					_append_option_text(event, "option_01", "沿用公开接口")
				"human_command":
					_append_option_text(event, "option_02", "沿用人工指挥")
				"restricted_interface":
					_append_option_text(event, "option_01", "重新准备接入")
			match _get_decision_tag("decision.core_2058_network_support"):
				"power_support":
					_append_option_text(event, "option_01", "供电支援已投入")
				"crew_confirmation":
					_append_option_text(event, "option_02", "现场协作延续")
				"central_dispatch":
					_append_option_text(event, "option_03", "支援接口已集中")
		"event_2075_engine_rescue":
			match _get_decision_tag("decision.core_2058_crisis_authority"):
				"bounded_self_rescue":
					_append_option_text(event, "option_02", "沿用授权内支援")
				"human_final_authority":
					_append_option_text(event, "option_01", "人工授权延续")
				"forced_takeover":
					_append_option_text(event, "option_03", "扩权记录仍在")
		"event_2075_jupiter_gravity_crisis":
			match _get_decision_tag("decision.core_2075_rescue_support"):
				"crew_priority":
					_append_option_text(event, "option_01", "现场协作支援")
				"resource_support":
					_append_option_text(event, "option_01", "救援投入延续")
				"central_dispatch":
					_append_option_text(event, "option_03", "集中调度延续")


func _append_option_text(event: GameEvent, option_id: String, suffix: String) -> void:
	for option in event.options:
		if option.option_id == option_id:
			option.button_text += "（%s）" % suffix
			return


func _get_event_context_lines(event: GameEvent) -> Array[String]:
	var lines: Array[String] = []
	match event.event_id:
		"event_2058_lunar_fall_crisis":
			match _get_decision_tag("decision.core_2044_automation_access"):
				"public_counterstrike":
					lines.append("2044 年公开扩大的工程接口为后续支援留下了接入经验。")
				"human_command":
					lines.append("2044 年保留人工指挥，后续支援继续面对人类确认的责任边界。")
				"restricted_interface":
					lines.append("2044 年收紧工程接口，后续集中支援需要重新准备接入。")
			match _get_decision_tag("decision.core_2058_network_support"):
				"power_support":
					lines.append("本次北京救援中，你集中投入供电支援，后续联网配合的能源负担降低。")
				"crew_confirmation":
					lines.append("本次北京救援中，你由现场人员确认需求，人工协作得到延续。")
				"central_dispatch":
					lines.append("本次北京救援中，你集中调度支援接口，后续自动调度更易衔接。")
		"event_2075_engine_rescue":
			match _get_decision_tag("decision.core_2058_crisis_authority"):
				"bounded_self_rescue":
					lines.append("2058 年你在授权范围内集中支援，后续救援可沿用这段协作经验。")
				"human_final_authority":
					lines.append("2058 年你保留人类最终授权，现场人员继续参与支援决策。")
				"forced_takeover":
					lines.append("2058 年你扩大自动调度权限，再次集中支援仍需承担信任代价。")
		"event_2075_jupiter_gravity_crisis":
			match _get_decision_tag("decision.core_2075_rescue_support"):
				"crew_priority":
					lines.append("本次发动机救援中，你让救援队确认支援顺序，最终方案保留现场协作的基础。")
				"resource_support":
					lines.append("本次发动机救援中，你追加支援投入，最终救援支援的能源负担降低。")
				"central_dispatch":
					lines.append("本次发动机救援中，你集中调度系统支援，最终扩权承接了同样的信任代价。")
	return lines


func _get_decision_tag(key: String) -> String:
	return "" if _decision_history == null else _decision_history.get_tag(key)
