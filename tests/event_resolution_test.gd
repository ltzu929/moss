## 验证事件数值调整、preview/resolve 投影、科技减免和板块限幅。
extends "res://tests/support/moss_test_case.gd"

const EVENT_RESOLUTION_SCRIPT := preload("res://scripts/systems/event_resolution_system.gd")

var _resolution_system: EventResolutionSystem = EVENT_RESOLUTION_SCRIPT.new()


func _ready() -> void:
	_assert_2058_adjustment_matrix()
	_assert_2065_adjustment_matrix()
	_assert_2070_adjustment_matrix()
	_assert_2070_to_2075_projection_matrix()
	_assert_technology_mitigation_and_clamp()
	print("[MOSS-EVENT-RESOLUTION] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_2058_adjustment_matrix() -> void:
	var source_event := load(
		"res://data/events/event_2058_lunar_fall_crisis.tres"
	) as GameEvent
	_assert_true(source_event != null, "应能加载真实 2058 事件资源")
	if source_event == null:
		return
	var core_cases: Array[Dictionary] = [
		{
			"value": "public_counterstrike",
			"option_id": "option_01",
			"energy_delta": -10,
			"hope_option": "",
		},
		{
			"value": "human_command",
			"option_id": "option_02",
			"energy_delta": 0,
			"hope_option": "option_02",
		},
		{
			"value": "restricted_interface",
			"option_id": "option_01",
			"energy_delta": 10,
			"hope_option": "",
		},
	]
	var state_cases: Array[Dictionary] = [
		{"value": "server_first", "option_id": "option_01", "energy_delta": -20},
		{"value": "drainage_first", "option_id": "option_01", "energy_delta": 15},
		{"value": "moss_schedule", "option_id": "option_03", "energy_delta": -10},
	]

	for core_case in core_cases:
		for state_case in state_cases:
			var runtime_event := source_event.duplicate(true) as GameEvent
			_resolution_system.apply_event_option_adjustments(
				runtime_event,
				{
					"decision.core_2044_automation_access": str(core_case["value"]),
				},
				{
					"event_state.mid_08_root_server_retrofit": str(state_case["value"]),
				}
			)
			var option_01 := _get_option(runtime_event, "option_01")
			var option_02 := _get_option(runtime_event, "option_02")
			var option_03 := _get_option(runtime_event, "option_03")
			var expected_option_01_energy := 80 + int(core_case["energy_delta"])
			if str(state_case["option_id"]) == "option_01":
				expected_option_01_energy += int(state_case["energy_delta"])
			_assert_eq(
				option_01.energy_cost,
				expected_option_01_energy,
				"2044×2055→2058 九种组合应叠加自救能源调整"
			)
			_assert_eq(
				option_02.hope_delta,
				15 if str(core_case["hope_option"]) == "option_02" else 10,
				"2044 人工指挥选择应只调整 2058 等待方案希望"
			)
			_assert_eq(
				option_03.energy_cost,
				20 if str(state_case["option_id"]) == "option_03" else 30,
				"2055 MOSS 排期应只调整 2058 强制接管成本"
			)

	_assert_eq(
		_get_option(source_event, "option_01").energy_cost,
		80,
		"2058 九种调整不得污染原始资源模板"
	)


func _assert_2065_adjustment_matrix() -> void:
	var source_event := load(
		"res://data/events/event_2065_ai_isolation_audit.tres"
	) as GameEvent
	_assert_true(source_event != null, "应能加载真实 2065 事件资源")
	if source_event == null:
		return
	var core_cases: Array[Dictionary] = [
		{"value": "bounded_self_rescue", "hope_option": "option_01"},
		{"value": "human_final_authority", "hope_option": ""},
		{"value": "forced_takeover", "hope_option": "option_03"},
	]
	var state_cases: Array[Dictionary] = [
		{"value": "full_return", "authority_option": "option_01", "energy_option": ""},
		{"value": "emergency_backdoor", "authority_option": "option_03", "energy_option": ""},
		{
			"value": "negotiated_long_term",
			"authority_option": "",
			"energy_option": "option_02",
		},
	]

	for core_case in core_cases:
		for state_case in state_cases:
			var runtime_event := source_event.duplicate(true) as GameEvent
			_resolution_system.apply_event_option_adjustments(
				runtime_event,
				{
					"decision.core_2058_crisis_authority": str(core_case["value"]),
				},
				{
					"event_state.mid_10_authorization_return": str(state_case["value"]),
				}
			)
			var option_01 := _get_option(runtime_event, "option_01")
			var option_02 := _get_option(runtime_event, "option_02")
			var option_03 := _get_option(runtime_event, "option_03")
			_assert_eq(
				option_01.hope_delta,
				12 if str(core_case["hope_option"]) == "option_01" else 8,
				"2058×2059→2065 应保留自救方案希望调整"
			)
			_assert_eq(
				option_01.authority_delta,
				-10 if str(state_case["authority_option"]) == "option_01" else -8,
				"2065 完整归还应只调整配合审查的控制权"
			)
			_assert_eq(
				option_02.energy_cost,
				30
				- (10 if str(core_case["value"]) == "human_final_authority" else 0)
				- (10 if str(state_case["energy_option"]) == "option_02" else 0),
				"2058 人工终审与 2059 长期授权应叠加接口成本"
			)
			_assert_eq(
				option_03.hope_delta,
				-23 if str(core_case["hope_option"]) == "option_03" else -18,
				"2058 强制接管应增加 2065 隐藏链路信任代价"
			)
			_assert_eq(
				option_03.authority_delta,
				16 if str(state_case["authority_option"]) == "option_03" else 14,
				"2059 应急后门应提高隐藏链路权限收益"
			)

	_assert_eq(
		_get_option(source_event, "option_02").energy_cost,
		30,
		"2065 九种调整不得污染原始资源模板"
	)


func _assert_2070_adjustment_matrix() -> void:
	var source_event := load(
		"res://data/events/event_2070_siberian_engine_overload.tres"
	) as GameEvent
	_assert_true(source_event != null, "应能加载真实 2070 事件资源")
	if source_event == null:
		return
	var core_cases: Array[Dictionary] = [
		{"value": "full_compliance", "hope_option": "option_01"},
		{"value": "limited_disclosure", "hope_option": ""},
		{"value": "hidden_core_chain", "hope_option": "option_03"},
	]
	var state_cases: Array[Dictionary] = [
		{"value": "load_reduction", "order_option": "option_01", "energy_option": ""},
		{"value": "rear_reallocation", "order_option": "", "energy_option": "option_02"},
		{
			"value": "moss_supply_reorder",
			"order_option": "",
			"energy_option": "option_03",
		},
	]

	for core_case in core_cases:
		for state_case in state_cases:
			var runtime_event := source_event.duplicate(true) as GameEvent
			_resolution_system.apply_event_option_adjustments(
				runtime_event,
				{
					"decision.core_2065_audit_posture": str(core_case["value"]),
				},
				{
					"event_state.mid_14_heat_shield_shortage": str(state_case["value"]),
				}
			)
			var option_01 := _get_option(runtime_event, "option_01")
			var option_02 := _get_option(runtime_event, "option_02")
			var option_03 := _get_option(runtime_event, "option_03")
			_assert_eq(
				option_01.hope_delta,
				12 if str(core_case["hope_option"]) == "option_01" else 8,
				"2065×2068→2070 应保留人员优先希望调整"
			)
			_assert_eq(
				option_01.order_delta,
				-10 if str(state_case["order_option"]) == "option_01" else -15,
				"2068 提前降载应调整分段停机秩序损失"
			)
			_assert_eq(
				option_02.energy_cost,
				35
				- (10 if str(core_case["value"]) == "limited_disclosure" else 0)
				- (10 if str(state_case["energy_option"]) == "option_02" else 0),
				"2065 有限接口与 2068 后方资源应叠加备用阵列成本"
			)
			_assert_eq(
				option_03.hope_delta,
				-27 if str(core_case["hope_option"]) == "option_03" else -22,
				"2065 隐藏链路应增加 2070 超频信任代价"
			)
			_assert_eq(
				option_03.authority_delta,
				18 if str(core_case["hope_option"]) == "option_03" else 16,
				"2065 隐藏链路应提高 2070 超频权限收益"
			)
			_assert_eq(
				option_03.energy_cost,
				15 if str(state_case["energy_option"]) == "option_03" else 20,
				"2068 供应链重排应降低 2070 超频成本"
			)

	_assert_eq(
		_get_option(source_event, "option_03").hope_delta,
		-22,
		"2070 九种调整不得污染原始资源模板"
	)


func _assert_2070_to_2075_projection_matrix() -> void:
	var source_event := load(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres"
	) as GameEvent
	_assert_true(source_event != null, "应能加载真实 2075 事件资源")
	if source_event == null:
		return
	var cases: Array[Dictionary] = [
		{
			"decision": "personnel_first_shutdown",
			"option_id": "option_01",
			"hope": 25,
			"energy": 100,
		},
		{
			"decision": "redundant_array",
			"option_id": "option_02",
			"hope": -10,
			"energy": 0,
		},
		{
			"decision": "forced_overclock",
			"option_id": "option_03",
			"hope": -45,
			"energy": 20,
		},
	]
	for choice_case in cases:
		var runtime_event := source_event.duplicate(true) as GameEvent
		_resolution_system.apply_event_option_adjustments(
			runtime_event,
			{
				"decision.core_2070_engine_protection": str(choice_case["decision"]),
			},
			{}
		)
		var option := _get_option(runtime_event, str(choice_case["option_id"]))
		var projections := _resolution_system.calculate_option_projections(
			option,
			{},
			{"order": 50, "hope": 50, "authority": 50},
			150
		)
		var preview: Dictionary = projections.get("preview", {})
		var resolution: Dictionary = projections.get("resolution", {})
		_assert_eq(
			int(preview.get("hope_delta", 0)),
			int(choice_case["hope"]),
			"2070 决策到 2075 的预览希望投影应来自运行时快照"
		)
		_assert_eq(
			int(preview.get("energy_cost", 0)),
			int(choice_case["energy"]),
			"2070 决策到 2075 的预览能源投影应来自运行时快照"
		)
		_assert_eq(
			int(resolution.get("hope_delta", 0)),
			int(choice_case["hope"]),
			"2070 决策到 2075 的结算希望应消费同一快照"
		)
		_assert_eq(
			int(resolution.get("energy_cost", 0)),
			int(choice_case["energy"]),
			"2070 决策到 2075 的结算能源应消费同一快照"
		)
		_assert_eq(
			str(preview.get("option_id", "")),
			str(resolution.get("option_id", "")),
			"预览和结算必须引用同一个稳定 option_id"
		)


func _assert_technology_mitigation_and_clamp() -> void:
	var option := EventOption.new()
	option.option_id = "option_test_resolution"
	option.order_delta = -20
	option.hope_delta = -45
	option.authority_delta = 25
	option.energy_cost = 20
	var projections := _resolution_system.calculate_option_projections(
		option,
		{"human_event_mitigation": true},
		{"order": 5, "hope": 10, "authority": 90},
		7
	)
	var preview: Dictionary = projections.get("preview", {})
	var resolution: Dictionary = projections.get("resolution", {})
	_assert_eq(
		int(preview.get("hope_delta", 0)),
		-45,
		"科技减免不得改变弹窗预览的原始希望值"
	)
	_assert_eq(
		int(resolution.get("hope_delta", 0)),
		-10,
		"科技减免后仍应按板块下限计算实际希望变化"
	)
	_assert_eq(
		int(resolution.get("order_delta", 0)),
		-5,
		"板块秩序下限应返回实际限幅后的变化"
	)
	_assert_eq(
		int(resolution.get("authority_delta", 0)),
		10,
		"板块控制权上限应返回实际限幅后的变化"
	)
	_assert_eq(
		int(resolution.get("energy_cost", 0)),
		7,
		"能源结算不得扣除当前可用能源之外的数值"
	)
	_assert_eq(
		_resolution_system.get_technology_adjusted_event_delta(
			-45,
			"hope",
			{"human_event_mitigation": true}
		),
		-33,
		"human_event_mitigation 应按 ceili(delta * 0.75) 计算"
	)
	_assert_eq(
		_resolution_system.get_technology_adjusted_event_delta(
			-45,
			"authority",
			{"human_event_mitigation": true}
		),
		-45,
		"科技减免不得改变控制权变化"
	)


func _get_option(event: GameEvent, option_id: String) -> EventOption:
	for option in event.options:
		if option.option_id == option_id:
			return option
	return null
