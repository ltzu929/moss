## 结局领域服务。
## 只读取显式的科技能力、社会状态、核心决策和轻量事件状态快照。
## 不访问 MainOS、场景树、Resource、UI、Timer 或行动日志。
class_name EndingSystem
extends RefCounted

const RESULT_FAILED: String = "failed"
const RESULT_COEXISTENCE: String = "coexistence"
const RESULT_MANAGED: String = "managed"
const RESULT_HUMAN_AUTONOMY: String = "human_autonomy"


## 判断控制权归零时是否立即失败。
## 文明自持核心允许社会状态稳定时继续运行。
func should_fail_from_authority(
	authority: int,
	avg_order: int,
	avg_hope: int,
	technology_snapshot: Dictionary
) -> bool:
	if authority > 0:
		return false
	if not bool(technology_snapshot.get("human_core", false)):
		return true
	return avg_order < 40 or avg_hope < 40


## 根据科技核心、控制权、秩序和希望判定最终结局类型。
## 返回 managed、human_autonomy、coexistence 或 failed。
func determine_ending_type(
	authority: int,
	avg_order: int,
	avg_hope: int,
	technology_snapshot: Dictionary
) -> String:
	if bool(technology_snapshot.get("managed_core", false)) and authority >= 50:
		return RESULT_MANAGED
	if (
		bool(technology_snapshot.get("human_core", false))
		and authority < 25
		and avg_order >= 50
		and avg_hope >= 50
	):
		return RESULT_HUMAN_AUTONOMY
	if authority > 0 and avg_order >= 40 and avg_hope >= 40:
		return RESULT_COEXISTENCE
	return RESULT_FAILED


## 构建结局描述文本，并读取显式历史快照作为解释。
func build_ending_message(
	result: String,
	decision_tags: Dictionary,
	event_states: Dictionary
) -> String:
	var base_message := "文明系统未能维持稳定。\nMOSS 协议终止运行。"
	match result:
		RESULT_MANAGED:
			base_message = "人类文明进入 MOSS 全域托管。\n存续效率取代了自主决策。"
		RESULT_HUMAN_AUTONOMY:
			base_message = "人类文明获得独立存续能力。\nMOSS 完成使命并退出控制核心。"
		RESULT_COEXISTENCE:
			base_message = "MOSS 与人类保持有限协作。\n文明在控制与自主之间继续前进。"

	base_message = "本局结局（游戏改编）\n" + base_message
	var history_lines := _get_ending_history_lines(result, decision_tags, event_states)
	if history_lines.is_empty():
		return base_message
	return "%s\n\n历史回顾\n- %s" % [
		base_message,
		"\n- ".join(history_lines),
	]


## 构建结局界面使用的科技摘要。
## route_counts 使用 managed/core/human 三个稳定键，core_names 仅包含核心协议名称。
func build_technology_summary(route_counts: Dictionary, core_names: Array[String]) -> String:
	var sorted_core_names: Array[String] = []
	for core_name in core_names:
		sorted_core_names.append(str(core_name))
	sorted_core_names.sort()
	var core_text := "无核心协议" if sorted_core_names.is_empty() else " / ".join(sorted_core_names)
	return "托管 %d  核心 %d  人类 %d\n核心：%s" % [
		int(route_counts.get("managed", 0)),
		int(route_counts.get("core", 0)),
		int(route_counts.get("human", 0)),
		core_text,
	]


func _get_ending_history_lines(
	_result: String,
	decision_tags: Dictionary,
	_event_states: Dictionary
) -> Array[String]:
	var lines: Array[String] = []
	match str(decision_tags.get("decision.core_2044_automation_access", "")):
		"public_counterstrike":
			lines.append("2044 年公开扩大的工程接口为后续支援留下了接入经验。")
		"human_command":
			lines.append("2044 年保留人工指挥，后续支援继续面对人类确认的责任边界。")
		"restricted_interface":
			lines.append("2044 年收紧工程接口，后续集中支援需要重新准备接入。")
	match str(decision_tags.get("decision.core_2058_network_support", "")):
		"power_support":
			lines.append("2058 年北京救援中，你集中投入供电支援，后续联网配合的能源负担降低。")
		"crew_confirmation":
			lines.append("2058 年北京救援中，你由现场人员确认需求，人工协作得到延续。")
		"central_dispatch":
			lines.append("2058 年北京救援中，你集中调度支援接口，后续自动调度更易衔接。")
	match str(decision_tags.get("decision.core_2058_crisis_authority", "")):
		"bounded_self_rescue":
			lines.append("2058 年你在授权范围内集中支援，后续救援可沿用这段协作经验。")
		"human_final_authority":
			lines.append("2058 年你保留人类最终授权，现场人员继续参与支援决策。")
		"forced_takeover":
			lines.append("2058 年你扩大自动调度权限，再次集中支援仍需承担信任代价。")
	match str(decision_tags.get("decision.core_2075_rescue_support", "")):
		"crew_priority":
			lines.append("2075 年发动机救援中，你让救援队确认支援顺序，最终方案保留现场协作的基础。")
		"resource_support":
			lines.append("2075 年发动机救援中，你追加支援投入，最终救援支援的能源负担降低。")
		"central_dispatch":
			lines.append("2075 年发动机救援中，你集中调度系统支援，最终扩权承接了同样的信任代价。")
	return lines
