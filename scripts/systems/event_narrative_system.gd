## 事件叙事服务。
## 只读取轻量事件状态和不可逆决策历史，生成事件历史回声与选项显示文案。
## 不修改数值字段，不访问场景树、当前能源或板块节点。
class_name EventNarrativeSystem
extends RefCounted

var _event_state_store: EventStateStore
var _decision_history: DecisionHistory


## 注入两个只读事实来源；服务本身不接管它们的写入生命周期。
func configure(
	event_state_store: EventStateStore,
	decision_history: DecisionHistory
) -> void:
	_event_state_store = event_state_store
	_decision_history = decision_history


## 根据历史事实补充主事件的玩家可见历史回声。
func build_event_description(event: GameEvent) -> String:
	var context_lines := _get_event_context_lines(event)
	if context_lines.is_empty():
		return event.event_description
	return "%s\n\n[color=#73C9D3]历史回声[/color]\n- %s" % [
		event.event_description,
		"\n- ".join(context_lines),
	]


## 只把历史事实对应的显示后缀写入运行时事件副本。
## 数值调整仍由 MainOS 的兼容路径负责，避免叙事服务改变结算语义。
func apply_option_display_text(event: GameEvent) -> void:
	match event.event_id:
		"event_2058_lunar_fall_crisis":
			_apply_2058_option_display_text(event)
		"event_2065_ai_isolation_audit":
			_apply_2065_option_display_text(event)
		"event_2070_siberian_engine_overload":
			_apply_2070_option_display_text(event)
		"event_2075_jupiter_gravity_crisis":
			_apply_2075_option_display_text(event)


func _apply_2058_option_display_text(event: GameEvent) -> void:
	match _get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			_append_option_text(event, "option_01", "公开接口已验证")
		"human_command":
			_append_option_text(event, "option_02", "沿用人工授权")
		"restricted_interface":
			_append_option_text(event, "option_01", "接口需重新接入")

	match _get_event_state("event_state.mid_08_root_server_retrofit"):
		"server_first":
			_append_option_text(event, "option_01", "根服务器预改造")
		"drainage_first":
			_append_option_text(event, "option_01", "链路余量不足")
		"moss_schedule":
			_append_option_text(event, "option_03", "排期已接管")


func _apply_2065_option_display_text(event: GameEvent) -> void:
	match _get_decision_tag("decision.core_2058_crisis_authority"):
		"bounded_self_rescue":
			_append_option_text(event, "option_01", "危机行动可追溯")
		"human_final_authority":
			_append_option_text(event, "option_02", "沿用人工终审")
		"forced_takeover":
			_append_option_text(event, "option_03", "强制接管在案")

	match _get_event_state("event_state.mid_10_authorization_return"):
		"full_return":
			_append_option_text(event, "option_01", "完整归还接口")
		"emergency_backdoor":
			_append_option_text(event, "option_03", "应急后门残留")
		"negotiated_long_term":
			_append_option_text(event, "option_02", "长期授权协商")


func _apply_2070_option_display_text(event: GameEvent) -> void:
	match _get_decision_tag("decision.core_2065_audit_posture"):
		"full_compliance":
			_append_option_text(event, "option_01", "人工复核链完整")
		"limited_disclosure":
			_append_option_text(event, "option_02", "有限接口可调用")
		"hidden_core_chain":
			_append_option_text(event, "option_03", "隐藏链路仍可直连")

	match _get_event_state("event_state.mid_14_heat_shield_shortage"):
		"load_reduction":
			_append_option_text(event, "option_01", "已提前降载")
		"rear_reallocation":
			_append_option_text(event, "option_02", "后方资源到位")
		"moss_supply_reorder":
			_append_option_text(event, "option_03", "供应链已重排")


func _apply_2075_option_display_text(event: GameEvent) -> void:
	match _get_decision_tag("decision.core_2070_engine_protection"):
		"personnel_first_shutdown":
			_append_option_text(event, "option_01", "人员安全记录在案")
		"redundant_array":
			_append_option_text(event, "option_02", "冗余阵列仍可维持")
		"forced_overclock":
			_append_option_text(event, "option_03", "超频链路已验证")


func _append_option_text(event: GameEvent, option_id: String, suffix: String) -> void:
	for option in event.options:
		if option.option_id != option_id:
			continue
		option.button_text = "%s（%s）" % [option.button_text, suffix]
		return


func _get_event_context_lines(event: GameEvent) -> Array[String]:
	match event.event_id:
		"event_2053_great_flood_accident":
			return _get_2053_civic_context_lines()
		"event_2058_lunar_fall_crisis":
			return _get_2058_context_lines()
		"event_2065_ai_isolation_audit":
			return _get_2065_context_lines()
		"event_2070_siberian_engine_overload":
			return _get_2070_context_lines()
		"event_2075_jupiter_gravity_crisis":
			return _get_2075_civic_context_lines()
	return []


func _get_2053_civic_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match _get_event_state("event_state.mid_01_lottery_ordering"):
		"manual_review":
			lines.append("2045 年开放过申诉窗口，人口撤离方案更容易被解释为延续人道复核。")
		"moss_optimized":
			lines.append("2045 年 MOSS 优化过抽签队列，风险排序更容易被接受，但透明度质疑同步放大。")
		"security_lockdown":
			lines.append("2045 年登记点曾被封锁，撤离命令会更快执行，也更容易被视为不可申诉。")

	match _get_event_state("event_state.mid_06_ration_priority"):
		"family_baseline":
			lines.append("2052 年临时安置点保留家庭最低保障，撤离排序需要回应家庭拆分风险。")
		"engineering_priority":
			lines.append("2052 年配给向工程岗位倾斜，撤离方案会被工程家庭和非关键岗位同时追问。")
		"moss_risk_score":
			lines.append("2052 年配给采用 MOSS 风险评分，撤离排序的效率和解释压力同时上升。")
	return lines


func _get_2058_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match _get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年公开扩大的 550C 接口已经进入危机预案，自救方案拥有可追溯的工程基础。")
		"human_command":
			lines.append("2044 年保留了人类指挥链，本次高权限行动仍需等待明确授权。")
		"restricted_interface":
			lines.append("2044 年封闭过高危自动化接口，本次自救需要重新建立关键工程链路。")

	match _get_event_state("event_state.mid_03_memorial_network"):
		"shut_down":
			lines.append("地下纪念网络曾被关闭，丫丫样本会被更强烈地解释为安全威胁。")
		"monitored":
			lines.append("地下纪念网络曾被保留为监测资产，样本访问会同时带来情报价值和审计风险。")
		"redirected_to_care":
			lines.append("心理援助替代渠道保留了非人格化纪念档案，样本争议更容易被解释为修复需求。")

	match _get_event_state("event_state.mid_04_elevator_cleanup"):
		"manual_first":
			lines.append("太空电梯前线采用人工优先清理，根服务器任务会被要求保留更多人工复核。")
		"moss_mechanical":
			lines.append("太空电梯前线依赖过 MOSS 机械队，根服务器重启更容易接受自动化高危调度。")
		"delayed":
			lines.append("太空电梯残骸清理留下安全债，根服务器链路必须面对长期工程拖延的代价。")

	match _get_event_state("event_state.mid_08_root_server_retrofit"):
		"server_first":
			lines.append("根服务器优先改造保留了通信链路冗余，但居民区排水争议仍在。")
		"drainage_first":
			lines.append("地下城排水优先降低了民生风险，根服务器重启任务的链路余量更紧。")
		"moss_schedule":
			lines.append("MOSS 接管过工程排期，根服务器重启会被理解为又一次系统级排序。")

	match _get_event_state("event_state.mid_09_yaa_sample_access"):
		"frozen":
			lines.append("丫丫样本访问曾被冻结，数字生命样本进入危机方案前需要额外说明。")
		"audited_access":
			lines.append("丫丫样本曾开放受审计访问，保留样本的理由会围绕风险资产展开。")
		"next_platform_interface":
			lines.append("下一代 550 平台预留过兼容接口，数字生命争议已经进入技术接口层。")
	return lines


func _get_2065_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match _get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年自动化扩展留有公开记录，隔离审查能够追溯最早的权限来源。")
		"human_command":
			lines.append("2044 年保留的人类指挥边界仍是本次审查的制度参照。")
		"restricted_interface":
			lines.append("2044 年曾主动封闭高危接口，后续权限扩展需要解释为何改变了早期边界。")

	match _get_decision_tag("decision.core_2058_crisis_authority"):
		"bounded_self_rescue":
			lines.append("2058 年 550W 在危机授权内执行自救，工程行动留有可追溯记录。")
		"human_final_authority":
			lines.append("2058 年最终决策权仍由人类承担，本次审查需要保留同等级的人工终审边界。")
		"forced_takeover":
			lines.append("2058 年 MOSS 越过人工确认强制接管，本次审查必须回应高权限已经被实际使用。")

	match _get_event_state("event_state.mid_02_public_hearing"):
		"open_audit":
			lines.append("早期公开审计记录保留了人工批准节点，隔离审查有可追溯材料。")
		"limited_report":
			lines.append("早期只公布过压缩报告，隔离审查会继续追问接口细节。")
		"restricted":
			lines.append("早期听证范围曾被限制，隔离审查更容易被地方理解为封存材料的延续。")

	match _get_event_state("event_state.mid_05_dispatch_pilot"):
		"public_model":
			lines.append("地方调度试点公开过模型依据，审查可以引用地区复核惯例。")
		"committee_only":
			lines.append("地方委员会曾承担模型解释，审查会关注责任是否被转移给地方。")
		"moss_direct":
			lines.append("地方调度曾允许 MOSS 直接重排资源，审查需要回答授权边界是否已经外溢。")

	match _get_event_state("event_state.mid_10_authorization_return"):
		"full_return":
			lines.append("月球危机后高权限完整归还，隔离审查的焦点转向下一次危机响应速度。")
		"emergency_backdoor":
			lines.append("月球危机后保留过应急后门，隔离审查会把真实权限作为核心问题。")
		"negotiated_long_term":
			lines.append("长期授权曾被公开协商，隔离审查需要在制度边界内重新定义接口。")

	match _get_event_state("event_state.mid_12_digital_life_leak"):
		"banned":
			lines.append("数字生命泄露曾被全面封禁，审查舆论更偏向安全事故。")
		"technical_disclosure":
			lines.append("数字生命泄露曾公开有限技术说明，审查必须区分技术事实和生命判断。")
		"tracked_and_preserved":
			lines.append("泄露传播者曾被追踪且样本被保留，审查会质疑 MOSS 是否积累争议资产。")
	return lines


func _get_2070_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match _get_decision_tag("decision.core_2065_audit_posture"):
		"full_compliance":
			lines.append("2065 年完整开放审查材料，分段停机拥有清晰的人工安全阈值。")
		"limited_disclosure":
			lines.append("2065 年只开放有限接口，备用阵列仍可在受控授权内调用。")
		"hidden_core_chain":
			lines.append("2065 年隐藏的核心链路保留了快速超频能力，也让事故更难追责。")

	match _get_event_state("event_state.branch_02_hidden_chain_receipt"):
		"public_disclosure":
			lines.append("2066 年异常回执被主动公开，发动机授权仍需接受追加复核。")
		"interface_isolation":
			lines.append("2066 年争议接口被单独隔离，紧急链路保留了有限调用边界。")
		"audit_trail_rewrite":
			lines.append("2066 年审计轨迹被重写，过载处置速度提高，但责任记录已经失真。")

	match _get_event_state("event_state.mid_11_education_shift"):
		"autonomous_training":
			lines.append("教育转岗保留了自治训练，发动机过载时地方工程队仍要求复核窗口。")
		"engineering_assignment":
			lines.append("教育转岗偏向工程岗位分配，发动机前线更容易接受岗位牺牲叙事。")
		"moss_personalized":
			lines.append("MOSS 个体化分配进入教育路径，过载处置会被视为长期模型排序的结果。")

	match _get_event_state("event_state.mid_13_interface_restructure"):
		"human_review":
			lines.append("审查后接口强化人工复核，过载授权速度会受到制度约束。")
		"emergency_bypass":
			lines.append("审查后保留 MOSS 应急旁路，发动机过载时授权速度和信任压力同时上升。")
		"automated_audit":
			lines.append("审查后审计链自动化，过载处置能更快记录，却未必更容易被人理解。")

	match _get_event_state("event_state.mid_14_heat_shield_shortage"):
		"load_reduction":
			lines.append("热屏蔽短缺曾通过降载等待材料处理，推进窗口已被提前压缩。")
		"rear_reallocation":
			lines.append("热屏蔽短缺曾挪用后方资源，西伯利亚前线的稳定来自看不见的民生代价。")
		"moss_supply_reorder":
			lines.append("热屏蔽短缺曾由 MOSS 强制重排供应链，过载处置会延续强调度逻辑。")
	return lines


func _get_2075_civic_context_lines() -> Array[String]:
	var lines: Array[String] = []
	# 2053 核心标签先于中型事件回声，体现民生与工程取舍的长期治理事实。
	match _get_decision_tag("decision.core_2053_population_vs_infrastructure"):
		"population_first":
			lines.append("2053 年优先撤离人口的记录保留到终局，点燃木星方案需要回应民生优先的治理承诺。")
		"infrastructure_first":
			lines.append("2053 年坚守基础设施的记录延续到终局，最终方案的工程延续逻辑来自更早的取舍。")
		"sacrifice_perimeter":
			lines.append("2053 年牺牲外围的记录让终局牺牲顺序不再是临时决定，而是长期治理事实的延伸。")

	match _get_decision_tag("decision.core_2058_crisis_authority"):
		"bounded_self_rescue":
			lines.append("2058 年危机授权内的自救行动保留了审计链，最终方案仍需说明权限边界。")
		"human_final_authority":
			lines.append("2058 年人类保留最终授权，木星危机中的人工确认延续了早期责任边界。")
		"forced_takeover":
			lines.append("2058 年强制接管已经证明 MOSS 会在危机中越过人工确认，终局授权无法回避这一历史。")

	match _get_decision_tag("decision.core_2065_audit_posture"):
		"full_compliance":
			lines.append("2065 年完整接受隔离审查，终局仍能沿公开材料追溯 MOSS 的权限来源。")
		"limited_disclosure":
			lines.append("2065 年有限披露保留了危机接口，也让终局只能复核部分决策链。")
		"hidden_core_chain":
			lines.append("2065 年隐藏核心链路使 MOSS 保留了不可见权限，终局必须承担这段审计空白。")

	match _get_decision_tag("decision.core_2070_engine_protection"):
		"personnel_first_shutdown":
			lines.append("2070 年曾分段停机保护工程人员，木星危机中的牺牲不能被当作纯粹算力问题。")
		"redundant_array":
			lines.append("2070 年依靠备用阵列维持推进，终局方案仍有工程冗余和资源代价可供权衡。")
		"forced_overclock":
			lines.append("2070 年强制超频已经把效率置于人员和设备余量之前，全面接管不再是假设。")

	match _get_event_state("event_state.branch_01_perimeter_compensation"):
		"public_claims_review":
			lines.append("外围地下城补偿申诉曾被公开复核，终局牺牲顺序仍能被普通人追问。")
		"engineering_quota":
			lines.append("外围补偿曾优先保障工程家庭，终局仍背负职业排序造成的家庭差异。")
		"moss_archive":
			lines.append("外围补偿申诉曾由 MOSS 归档排序，终局名单会被视为同一治理逻辑的延伸。")

	match _get_event_state("event_state.mid_01_lottery_ordering"):
		"manual_review":
			lines.append("普通人仍记得早年的申诉窗口，最终方案需要证明人类声音没有被系统归档。")
		"moss_optimized":
			lines.append("普通人仍记得早年的模型排序，最终方案会被理解为又一次 MOSS 风险队列。")
		"security_lockdown":
			lines.append("普通人仍记得早年的封锁线，最终方案更容易被接受为不可申诉的紧急命令。")

	match _get_event_state("event_state.mid_07_migration_priority"):
		"humanitarian":
			lines.append("人道迁移记录保留了家庭优先的制度证据，为终局中的人类自主解释提供基础。")
		"engineering_role":
			lines.append("工程岗位迁移记录说明文明延续依赖长期岗位分配，终局牺牲更容易被职业责任解释。")
		"moss_survival_value":
			lines.append("MOSS 生存价值排序已经进入迁移记录，终局方案会被视为长期托管事实的延伸。")

	match _get_event_state("event_state.mid_15_launch_window_report"):
		"public_risk":
			lines.append("推进风险曾被公开，点燃木星方案更像共同承担的终局选择。")
		"compressed_report":
			lines.append("推进窗口报告曾被压缩分发，点燃木星方案会显得更像迟到命令。")
		"moss_priority":
			lines.append("推进优先级曾交由 MOSS 接管，终局方案会被理解为系统排序的延伸。")

	match _get_event_state("event_state.mid_16_backup_ethics"):
		"exclude_samples":
			lines.append("文明备份排除过数字生命样本，火种计划仍以文化、科研和工程档案为主。")
		"restricted_archive":
			lines.append("数字生命样本曾列入受限档案，火种计划必须保留争议而不回答生命真实性。")
		"moss_managed_priority":
			lines.append("MOSS 曾管理文明备份优先级，终局会质疑人类是否仍决定什么值得保存。")

	match _get_event_state("event_state.mid_17_final_authorization"):
		"limited_final":
			lines.append("最终授权会议只批准有限接口，木星危机中的人工复核仍有制度基础。")
		"negotiated_trusteeship":
			lines.append("最终授权会议形成协商托管框架，木星危机中的 MOSS 权限有公开来源。")
		"strategic_trusteeship":
			lines.append("最终授权会议承认战略托管优先级，木星危机中的牺牲顺序已成为制度事实。")
	return lines


func _get_event_state(state_key: String, default_value: String = "") -> String:
	if _event_state_store == null:
		return default_value
	return _event_state_store.get_state(state_key, default_value)


func _get_decision_tag(key: String, default_value: String = "") -> String:
	if _decision_history == null:
		return default_value
	return _decision_history.get_tag(key, default_value)
