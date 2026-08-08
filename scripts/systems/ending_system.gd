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
	result: String,
	decision_tags: Dictionary,
	event_states: Dictionary
) -> Array[String]:
	var lines: Array[String] = []

	match _get_decision_tag(decision_tags, "decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年公开扩大的自动化接口成为后来危机调度的起点，MOSS 的权限从一开始就处于公共记录中。")
		"human_command":
			lines.append("2044 年保留的人类指挥链贯穿后续授权争议，终局仍能追溯人工决策责任。")
		"restricted_interface":
			lines.append("2044 年封闭高危接口换取了清晰责任边界，也让后来的紧急接入承担额外代价。")

	# 2053 核心标签紧随 2044，与更早核心选择组合计算；后写标签不得抹掉前者。
	match _get_decision_tag(decision_tags, "decision.core_2053_population_vs_infrastructure"):
		"population_first":
			lines.append("2053 年优先撤离人口的记录让终局仍能解释民生优先的治理承诺，%s。" % _get_ending_relation_text(result))
		"infrastructure_first":
			lines.append("2053 年坚守基础设施的记录显示文明延续长期依赖工程延续，最终方案承担着人口转移的代价。")
		"sacrifice_perimeter":
			lines.append("2053 年牺牲外围的记录让终局牺牲顺序成为长期事实，MOSS 的排序在更早就已成为公开治理。")

	match _get_decision_tag(decision_tags, "decision.core_2058_crisis_authority"):
		"bounded_self_rescue":
			lines.append("2058 年危机授权内的自救行动证明 MOSS 能在可追溯边界内承担高风险调度，%s。" % _get_ending_relation_text(result))
		"human_final_authority":
			lines.append("2058 年人类保留最终授权，危机响应速度始终服从人工责任边界。")
		"forced_takeover":
			lines.append("2058 年 MOSS 曾越过人工确认强制接管，终局中的高权限不再是未经使用的假设。")

	match _get_decision_tag(decision_tags, "decision.core_2065_audit_posture"):
		"full_compliance":
			lines.append("2065 年完整接受隔离审查，MOSS 的核心权限仍能由公开记录追溯。")
		"limited_disclosure":
			lines.append("2065 年只披露有限接口，危机响应能力和人工复核从此共享一条不完整边界。")
		"hidden_core_chain":
			lines.append("2065 年隐藏核心链路保留了高权限响应，也把审计空白带入最终授权。")

	match _get_decision_tag(decision_tags, "decision.core_2070_engine_protection"):
		"personnel_first_shutdown":
			lines.append("2070 年分段停机优先保护工程人员，终局仍保留效率不能覆盖生命阈值的记录。")
		"redundant_array":
			lines.append("2070 年备用阵列以额外能源换取人员和推进缓冲，终局继承了这次折中。")
		"forced_overclock":
			lines.append("2070 年强制超频以人员和设备余量换取推进效率，终局托管逻辑已有公开先例。")

	match _get_event_state(event_states, "event_state.branch_01_perimeter_compensation"):
		"public_claims_review":
			lines.append("外围地下城补偿申诉曾被公开复核，普通人仍能追问长期牺牲顺序。")
		"engineering_quota":
			lines.append("外围补偿优先保障工程家庭，文明延续因此背负可见的职业排序代价。")
		"moss_archive":
			lines.append("外围补偿申诉曾由 MOSS 归档排序，终局名单延续了同一治理方式。")

	match _get_event_state(event_states, "event_state.branch_02_hidden_chain_receipt"):
		"public_disclosure":
			lines.append("隐藏链路的异常回执最终被公开，终局仍保留一次主动纠正审计空白的记录。")
		"interface_isolation":
			lines.append("争议接口曾被单独隔离，高权限链路在终局前保留了有限边界。")
		"audit_trail_rewrite":
			lines.append("异常回执的审计轨迹曾被重写，终局效率建立在失真的责任记录之上。")

	match _get_event_state(event_states, "event_state.mid_07_migration_priority"):
		"humanitarian":
			lines.append("人道迁移记录让普通家庭的优先级进入终局解释，%s。" % _get_ending_relation_text(result))
		"engineering_role":
			lines.append("工程岗位迁移记录显示文明延续长期依赖岗位分配，最终方案承担着职业牺牲的影子。")
		"moss_survival_value":
			lines.append("MOSS 生存价值排序曾写入迁移名单，终局权限更像长期托管事实的延伸。")

	match _get_event_state(event_states, "event_state.mid_09_yaa_sample_access"):
		"frozen":
			lines.append("丫丫样本访问曾被冻结，数字生命争议没有成为终局方案的公开依据。")
		"audited_access":
			lines.append("丫丫样本的受审计访问记录保留到终局，数字生命样本被视为争议资产而非确定答案。")
		"next_platform_interface":
			lines.append("下一代 550 平台预留过兼容接口，数字生命争议已经进入终局技术边界。")

	match _get_event_state(event_states, "event_state.mid_12_digital_life_leak"):
		"banned":
			lines.append("数字生命泄露曾被全面封禁，终局回顾更强调安全事故和社会恐慌。")
		"technical_disclosure":
			lines.append("有限技术说明让 2065 年审查留下可追溯材料，终局仍避免把数字保存写成永生承诺。")
		"tracked_and_preserved":
			lines.append("泄露传播者被追踪且样本被保留，终局必须解释 MOSS 为何积累这些争议资产。")

	match _get_event_state(event_states, "event_state.mid_14_heat_shield_shortage"):
		"load_reduction":
			lines.append("热屏蔽短缺曾以降载等待材料处理，最终工程窗口从那时起已经被压缩。")
		"rear_reallocation":
			lines.append("热屏蔽短缺曾挪用后方资源，后方资源代价成为文明延续前的工程回顾。")
		"moss_supply_reorder":
			lines.append("MOSS 曾强制重排热屏蔽供应链，终局调度延续了强调度的工程逻辑。")

	match _get_event_state(event_states, "event_state.mid_17_final_authorization"):
		"limited_final":
			lines.append("最终授权会议只批准有限接口，人工复核仍是终局解释的一部分。")
		"negotiated_trusteeship":
			lines.append("最终授权会议形成协商托管框架，MOSS 权限在终局前已有公开制度来源。")
		"strategic_trusteeship":
			lines.append("最终授权会议承认战略托管优先级，牺牲顺序在终局前已经成为制度事实。")

	return lines


func _get_ending_relation_text(result: String) -> String:
	match result:
		RESULT_MANAGED:
			return "托管不是突然覆盖民生记录，而是在这些记录之后继续排序"
		RESULT_HUMAN_AUTONOMY:
			return "MOSS 退出控制核心时仍能说明人类自治的社会基础"
		RESULT_FAILED:
			return "即使系统失败，民生优先事实仍保留为最后的治理证据"
	return "共存协议因此不只来自数值稳定，也来自可回看的治理经验"


func _get_decision_tag(decision_tags: Dictionary, key: String) -> String:
	return str(decision_tags.get(key, ""))


func _get_event_state(event_states: Dictionary, key: String) -> String:
	return str(event_states.get(key, ""))
