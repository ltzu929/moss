## 事件状态测试
## 验证事件选项可以写入可查询的轻量历史状态
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _main_os: Control
var _event_popup: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_event_popup = _main_os.get_node("%EventPopup")
	_main_os.get_node("Timer").stop()

	_assert_event_option_exposes_state_write_fields()
	await _assert_event_choice_writes_queryable_state()
	_assert_civic_event_states_change_main_event_context()
	_assert_remaining_event_states_change_main_event_context()
	_assert_representative_event_states_change_main_event_options()
	await _assert_adjusted_main_event_options_are_used_for_resolution()
	_assert_restart_clears_event_states()

	print("[MOSS-EVENT-STATE] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_event_option_exposes_state_write_fields() -> void:
	var option := EventOption.new()
	var property_names := _get_property_names(option)
	_assert_true(
		"event_state_key" in property_names,
		"事件选项应支持 event_state_key"
	)
	_assert_true(
		"event_state_value" in property_names,
		"事件选项应支持 event_state_value"
	)


func _assert_event_choice_writes_queryable_state() -> void:
	var event := _create_state_event()
	_main_os.all_events = [event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2045
	_main_os.current_month = 1

	_assert_true(
		_main_os.has_method("get_event_state"),
		"MainOS 应提供 get_event_state 查询接口"
	)
	_assert_true(
		_main_os.has_method("has_event_state"),
		"MainOS 应提供 has_event_state 查询接口"
	)

	get_tree().create_timer(0.05).timeout.connect(_emit_event_choice.bind(1))
	await _main_os.process_month_tick()

	_assert_eq(
		_main_os.get_event_state("event_state.mid_test_choice"),
		"moss_optimized",
		"选择事件方案后应写入对应 event_state"
	)
	_assert_true(
		_main_os.has_event_state("event_state.mid_test_choice", "moss_optimized"),
		"has_event_state 应能匹配指定状态值"
	)


func _assert_restart_clears_event_states() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_assert_eq(
		_main_os.get_event_state("event_state.mid_test_choice"),
		"",
		"重开游戏应清空 event_state"
	)


func _assert_civic_event_states_change_main_event_context() -> void:
	_assert_true(
		_main_os.has_method("build_event_description"),
		"MainOS 应提供 build_event_description 生成可读取历史状态的事件正文"
	)
	if not _main_os.has_method("build_event_description"):
		return

	_main_os.set_event_state("event_state.mid_01_lottery_ordering", "manual_review")
	_main_os.set_event_state("event_state.mid_06_ration_priority", "family_baseline")
	_main_os.set_event_state("event_state.mid_07_migration_priority", "humanitarian")

	var flood_event := _create_named_event("大淹没事故", 2053, "根服务器和地下城同时承压。")
	var flood_description: String = _main_os.build_event_description(flood_event)
	_assert_true(
		"历史回声" in flood_description,
		"2053 主事件正文应追加历史回声段落"
	)
	_assert_true(
		"申诉窗口" in flood_description,
		"2053 主事件应读取 MID-01 人工复核抽签背景"
	)
	_assert_true(
		"家庭最低保障" in flood_description,
		"2053 主事件应读取 MID-06 家庭配给背景"
	)

	var real_flood_event := load("res://data/events/event_2053_great_flood_accident.tres") as GameEvent
	_assert_true(real_flood_event != null, "应能加载真实 2053 主事件资源")
	if real_flood_event != null:
		var original_description: String = real_flood_event.event_description
		var display_flood_event: GameEvent = _main_os.build_display_event(real_flood_event)
		_assert_true(
			display_flood_event != real_flood_event,
			"build_display_event 应返回独立运行时副本"
		)
		_assert_true(
			"历史回声" in display_flood_event.event_description,
			"真实 2053 主事件运行时副本应包含历史回声"
		)
		_assert_eq(
			real_flood_event.event_description,
			original_description,
			"真实 2053 主事件原始描述不应被运行时副本污染"
		)

	var jupiter_event := _create_named_event("木星引力危机", 2075, "终局方案等待授权。")
	var jupiter_description: String = _main_os.build_event_description(jupiter_event)
	_assert_true(
		"普通人仍记得早年的申诉窗口" in jupiter_description,
		"2075 终局事件应读取 MID-01 作为普通人回声"
	)
	_assert_true(
		"人道迁移记录" in jupiter_description,
		"2075 终局事件应读取 MID-07 迁移优先级"
	)

	var real_jupiter_event := load("res://data/events/event_2075_jupiter_gravity_crisis.tres") as GameEvent
	_assert_true(real_jupiter_event != null, "应能加载真实 2075 主事件资源")
	if real_jupiter_event != null:
		var original_description: String = real_jupiter_event.event_description
		var display_jupiter_event: GameEvent = _main_os.build_display_event(real_jupiter_event)
		_assert_true(
			display_jupiter_event != real_jupiter_event,
			"build_display_event 应为 2075 返回独立运行时副本"
		)
		_assert_true(
			"人道迁移记录" in display_jupiter_event.event_description,
			"真实 2075 主事件运行时副本应读取 MID-07 迁移优先级"
		)
		_assert_eq(
			real_jupiter_event.event_description,
			original_description,
			"真实 2075 主事件原始描述不应被运行时副本污染"
		)


func _assert_remaining_event_states_change_main_event_context() -> void:
	_main_os.set_event_state("event_state.mid_02_public_hearing", "open_audit")
	_main_os.set_event_state("event_state.mid_03_memorial_network", "monitored")
	_main_os.set_event_state("event_state.mid_04_elevator_cleanup", "delayed")
	_main_os.set_event_state("event_state.mid_05_dispatch_pilot", "moss_direct")
	_main_os.set_event_state("event_state.mid_08_root_server_retrofit", "server_first")
	_main_os.set_event_state("event_state.mid_09_yaa_sample_access", "audited_access")
	_main_os.set_event_state("event_state.mid_10_authorization_return", "emergency_backdoor")
	_main_os.set_event_state("event_state.mid_11_education_shift", "autonomous_training")
	_main_os.set_event_state("event_state.mid_12_digital_life_leak", "technical_disclosure")
	_main_os.set_event_state("event_state.mid_13_interface_restructure", "emergency_bypass")
	_main_os.set_event_state("event_state.mid_14_heat_shield_shortage", "rear_reallocation")
	_main_os.set_event_state("event_state.mid_15_launch_window_report", "public_risk")
	_main_os.set_event_state("event_state.mid_16_backup_ethics", "restricted_archive")
	_main_os.set_event_state("event_state.mid_17_final_authorization", "negotiated_trusteeship")

	_assert_real_event_context(
		"res://data/events/event_2058_lunar_fall_crisis.tres",
		["监测资产", "安全债", "根服务器优先", "受审计访问"],
		"2058 主事件应读取数字生命和根服务器前因"
	)
	_assert_real_event_context(
		"res://data/events/event_2065_ai_isolation_audit.tres",
		["公开审计记录", "MOSS 直接重排", "应急后门", "技术说明"],
		"2065 主事件应读取权限演化和数字生命审查前因"
	)
	_assert_real_event_context(
		"res://data/events/event_2070_siberian_engine_overload.tres",
		["自治训练", "应急旁路", "后方资源"],
		"2070 主事件应读取工程疲劳前因"
	)
	_assert_real_event_context(
		"res://data/events/event_2075_jupiter_gravity_crisis.tres",
		["推进风险", "受限档案", "协商托管框架"],
		"2075 主事件应读取终局前授权、工程和备份前因"
	)


func _assert_real_event_context(
	resource_path: String,
	expected_fragments: Array[String],
	message_prefix: String
) -> void:
	var real_event := load(resource_path) as GameEvent
	_assert_true(real_event != null, "%s：应能加载真实事件资源" % message_prefix)
	if real_event == null:
		return

	var original_description: String = real_event.event_description
	var display_event: GameEvent = _main_os.build_display_event(real_event)
	_assert_true(
		display_event != real_event,
		"%s：build_display_event 应返回独立运行时副本" % message_prefix
	)
	_assert_true(
		"历史回声" in display_event.event_description,
		"%s：运行时副本应包含历史回声" % message_prefix
	)
	for fragment in expected_fragments:
		_assert_true(
			fragment in display_event.event_description,
			"%s：历史回声应包含“%s”" % [message_prefix, fragment]
		)
	_assert_eq(
		real_event.event_description,
		original_description,
		"%s：原始描述不应被运行时副本污染" % message_prefix
	)


func _assert_representative_event_states_change_main_event_options() -> void:
	_main_os.set_event_state("event_state.mid_08_root_server_retrofit", "server_first")
	var moon_event := load("res://data/events/event_2058_lunar_fall_crisis.tres") as GameEvent
	_assert_true(moon_event != null, "应能加载真实 2058 主事件资源")
	if moon_event != null:
		var original_energy := _get_option_by_id(moon_event, "option_01").energy_cost
		var display_moon_event: GameEvent = _main_os.build_display_event(moon_event)
		var adjusted_option := _get_option_by_id(display_moon_event, "option_01")
		_assert_eq(
			adjusted_option.energy_cost,
			60,
			"根服务器优先改造应降低 2058 执行自救计划能源代价"
		)
		_assert_true(
			"根服务器预改造" in adjusted_option.button_text,
			"2058 调整后的选项文案应说明前序状态来源"
		)
		_assert_eq(
			_get_option_by_id(moon_event, "option_01").energy_cost,
			original_energy,
			"2058 原始事件资源选项代价不应被运行时副本污染"
		)
		_main_os.set_event_state("event_state.mid_08_root_server_retrofit", "drainage_first")
		display_moon_event = _main_os.build_display_event(moon_event)
		adjusted_option = _get_option_by_id(display_moon_event, "option_01")
		_assert_eq(
			adjusted_option.energy_cost,
			95,
			"地下城排水优先应提高 2058 执行自救计划能源代价"
		)
		_assert_true(
			"链路余量不足" in adjusted_option.button_text,
			"2058 排水优先调整文案应说明链路余量不足"
		)
		_main_os.set_event_state("event_state.mid_08_root_server_retrofit", "moss_schedule")
		display_moon_event = _main_os.build_display_event(moon_event)
		adjusted_option = _get_option_by_id(display_moon_event, "option_03")
		_assert_eq(
			adjusted_option.energy_cost,
			20,
			"MOSS 工程排期应降低 2058 强制接管决策能源代价"
		)
		_assert_true(
			"排期已接管" in adjusted_option.button_text,
			"2058 MOSS 排期调整文案应说明排期来源"
		)

	_main_os.set_event_state("event_state.mid_10_authorization_return", "negotiated_long_term")
	var audit_event := load("res://data/events/event_2065_ai_isolation_audit.tres") as GameEvent
	_assert_true(audit_event != null, "应能加载真实 2065 主事件资源")
	if audit_event != null:
		var original_energy := _get_option_by_id(audit_event, "option_02").energy_cost
		var display_audit_event: GameEvent = _main_os.build_display_event(audit_event)
		var adjusted_option := _get_option_by_id(display_audit_event, "option_02")
		_assert_eq(
			adjusted_option.energy_cost,
			20,
			"长期授权协商应降低 2065 有限开放接口能源代价"
		)
		_assert_true(
			"长期授权协商" in adjusted_option.button_text,
			"2065 调整后的选项文案应说明前序授权状态"
		)
		_assert_eq(
			_get_option_by_id(audit_event, "option_02").energy_cost,
			original_energy,
			"2065 原始事件资源选项代价不应被运行时副本污染"
		)
		_main_os.set_event_state("event_state.mid_10_authorization_return", "full_return")
		display_audit_event = _main_os.build_display_event(audit_event)
		adjusted_option = _get_option_by_id(display_audit_event, "option_01")
		_assert_eq(
			adjusted_option.authority_delta,
			-10,
			"完整归还接口应提高 2065 配合隔离审查的控制权让渡"
		)
		_assert_true(
			"完整归还接口" in adjusted_option.button_text,
			"2065 完整归还调整文案应说明授权状态"
		)
		_main_os.set_event_state("event_state.mid_10_authorization_return", "emergency_backdoor")
		display_audit_event = _main_os.build_display_event(audit_event)
		adjusted_option = _get_option_by_id(display_audit_event, "option_03")
		_assert_eq(
			adjusted_option.authority_delta,
			16,
			"应急后门残留应提高 2065 隐藏核心链路控制权收益"
		)
		_assert_true(
			"应急后门残留" in adjusted_option.button_text,
			"2065 应急后门调整文案应说明授权状态"
		)

	_main_os.set_event_state("event_state.mid_14_heat_shield_shortage", "rear_reallocation")
	var overload_event := load("res://data/events/event_2070_siberian_engine_overload.tres") as GameEvent
	_assert_true(overload_event != null, "应能加载真实 2070 主事件资源")
	if overload_event != null:
		var original_energy := _get_option_by_id(overload_event, "option_02").energy_cost
		var display_overload_event: GameEvent = _main_os.build_display_event(overload_event)
		var adjusted_option := _get_option_by_id(display_overload_event, "option_02")
		_assert_eq(
			adjusted_option.energy_cost,
			25,
			"后方资源挪用应降低 2070 启动备用阵列能源代价"
		)
		_assert_true(
			"后方资源到位" in adjusted_option.button_text,
			"2070 调整后的选项文案应说明热屏蔽短缺处置来源"
		)
		_assert_eq(
			_get_option_by_id(overload_event, "option_02").energy_cost,
			original_energy,
			"2070 原始事件资源选项代价不应被运行时副本污染"
		)
		_main_os.set_event_state("event_state.mid_14_heat_shield_shortage", "load_reduction")
		display_overload_event = _main_os.build_display_event(overload_event)
		adjusted_option = _get_option_by_id(display_overload_event, "option_01")
		_assert_eq(
			adjusted_option.order_delta,
			-10,
			"提前降载应降低 2070 分段停机秩序损失"
		)
		_assert_true(
			"已提前降载" in adjusted_option.button_text,
			"2070 提前降载调整文案应说明热屏蔽处置来源"
		)
		_main_os.set_event_state("event_state.mid_14_heat_shield_shortage", "moss_supply_reorder")
		display_overload_event = _main_os.build_display_event(overload_event)
		adjusted_option = _get_option_by_id(display_overload_event, "option_03")
		_assert_eq(
			adjusted_option.energy_cost,
			15,
			"MOSS 供应链重排应降低 2070 强制超频点火能源代价"
		)
		_assert_true(
			"供应链已重排" in adjusted_option.button_text,
			"2070 供应链重排调整文案应说明热屏蔽处置来源"
		)


func _get_option_by_id(event: GameEvent, option_id: String) -> EventOption:
	for option in event.options:
		if option.option_id == option_id:
			return option
	return null


func _assert_adjusted_main_event_options_are_used_for_resolution() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	_event_popup = _main_os.get_node("%EventPopup")

	var moon_event := load("res://data/events/event_2058_lunar_fall_crisis.tres") as GameEvent
	_assert_true(moon_event != null, "应能加载真实 2058 主事件用于结算测试")
	if moon_event == null:
		return

	var renamed_event := moon_event.duplicate(true) as GameEvent
	renamed_event.event_title = "改名后的 2058 事件"
	renamed_event.options[0].button_text = "改名后的执行方案"
	_main_os.all_events = [renamed_event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2058
	_main_os.current_month = 1
	_main_os.current_energy = 100
	_main_os.set_event_state("event_state.mid_08_root_server_retrofit", "server_first")

	get_tree().create_timer(0.05).timeout.connect(_emit_event_choice.bind(0))
	await _main_os.process_month_tick()

	_assert_eq(
		_main_os.current_energy,
		40,
		"修改标题和按钮文字后仍应使用稳定 ID 对应的 60 能源代价"
	)
	_assert_eq(
		_main_os.triggered_events[0],
		"event_2058_lunar_fall_crisis",
		"修改标题后触发记录仍应使用事件 ID"
	)
	_assert_eq(
		_get_option_by_id(moon_event, "option_01").energy_cost,
		80,
		"真实事件结算后原始 2058 资源能源代价仍不应被污染"
	)


func _emit_event_choice(index: int) -> void:
	_event_popup.option_selected.emit(index)


func _create_state_event() -> GameEvent:
	var event := GameEvent.new()
	event.event_id = "event_test_state"
	event.event_title = "事件状态测试"
	event.event_time = 2045
	event.event_month = 1
	event.event_region = "asia"
	event.event_description = "测试事件状态写入"
	event.options = [
		_create_option("人工复核", "manual_review"),
		_create_option("MOSS 排序", "moss_optimized"),
	]
	return event


func _create_named_event(title: String, year: int, description: String) -> GameEvent:
	var event := GameEvent.new()
	event.event_id = {
		"大淹没事故": "event_2053_great_flood_accident",
		"木星引力危机": "event_2075_jupiter_gravity_crisis",
	}.get(title, "event_test_%s" % year)
	event.event_title = title
	event.event_time = year
	event.event_month = 1
	event.event_region = "europe"
	event.event_description = description
	return event


func _create_option(button_text: String, state_value: String) -> EventOption:
	var option := EventOption.new()
	option.button_text = button_text
	option.set("event_state_key", "event_state.mid_test_choice")
	option.set("event_state_value", state_value)
	return option


func _get_property_names(value: Object) -> Array[String]:
	var property_names: Array[String] = []
	for property in value.get_property_list():
		property_names.append(str(property["name"]))
	return property_names
