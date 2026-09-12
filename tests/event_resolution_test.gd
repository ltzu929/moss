## 真实危机阶段的历史组合、投影和科技边界测试。
extends "res://tests/support/moss_test_case.gd"

var _resolution_system := EventResolutionSystem.new()


func _ready() -> void:
	var source := load("res://data/events/event_2058_lunar_fall_crisis.tres") as GameEvent
	var access := ["public_counterstrike", "human_command", "restricted_interface"]
	var network := ["power_support", "crew_confirmation", "central_dispatch"]
	for i in range(3):
		for j in range(3):
			var event := source.duplicate(true) as GameEvent
			_resolution_system.apply_event_option_adjustments(event, {
				"decision.core_2044_automation_access": access[i],
				"decision.core_2058_network_support": network[j],
			}, {})
			_assert_eq(event.options[0].energy_cost, 60 + [-10, 0, 10][i] + [-15, 0, 0][j], "两段支援成本应叠加")
			_assert_eq(event.options[1].hope_delta, 15 + [0, 5, 0][i] + [0, 5, 0][j], "人工协作希望应叠加")
			_assert_eq(event.options[2].energy_cost, 20 + [0, 0, -10][j], "集中支援成本应调整")
	_assert_eq(source.options[0].energy_cost, 60, "运行时调整不得污染模板")
	var rescue := load("res://data/events/event_2075_engine_rescue.tres") as GameEvent
	var final_event := load("res://data/events/event_2075_jupiter_gravity_crisis.tres") as GameEvent
	for i in range(3):
		var event := rescue.duplicate(true) as GameEvent
		_resolution_system.apply_event_option_adjustments(event, {
			"decision.core_2058_crisis_authority": ["bounded_self_rescue", "human_final_authority", "forced_takeover"][i],
		}, {})
		_assert_eq(event.options[1].energy_cost, [25, 35, 35][i], "授权内支援应降低救援投入成本")
		_assert_eq(event.options[0].hope_delta, [12, 17, 12][i], "人类授权应延续到现场协作")
		_assert_eq(event.options[2].hope_delta, [-16, -16, -21][i], "扩权应继承信任代价")
		event = final_event.duplicate(true) as GameEvent
		_resolution_system.apply_event_option_adjustments(event, {
			"decision.core_2075_rescue_support": rescue.options[i].decision_tag_value,
		}, {})
		_assert_eq(event.options[0].energy_cost, [70, 55, 70][i], "救援投入应影响最终能源代价")
		_assert_eq(event.options[0].hope_delta, [25, 20, 20][i], "现场协作应影响最终希望")
		_assert_eq(event.options[2].energy_cost, [20, 20, 10][i], "集中调度应影响最终能源代价")
		for option in event.options:
			var projection := _resolution_system.calculate_option_projections(option, {}, {"order": 50, "hope": 50, "authority": 50}, 100)
			_assert_eq(projection.preview.energy_cost, projection.resolution.energy_cost, "充足能源时预览与结算成本一致")
			_assert_eq(projection.preview.hope_delta, projection.resolution.hope_delta, "未触及边界时希望预览与结算一致")
	_assert_technology_mitigation_and_clamp()
	print("[MOSS-EVENT-RESOLUTION] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


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
