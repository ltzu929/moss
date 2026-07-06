## 决策档案测试
## 验证主事件选项可以写入核心历史标签，并形成可回看的档案条目。
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _failed: int = 0
var _main_os: Control
var _event_popup: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_event_popup = _main_os.get_node("%EventPopup")
	_main_os.get_node("Timer").stop()

	_assert_event_option_exposes_decision_fields()
	_assert_real_main_events_define_core_tags()
	await _assert_event_choice_writes_decision_archive()
	_assert_decision_archive_panel_reflects_records()
	_assert_restart_clears_decision_archive()

	print("[MOSS-DECISION-ARCHIVE] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_event_option_exposes_decision_fields() -> void:
	var option := EventOption.new()
	var property_names := _get_property_names(option)
	for property_name in [
		"decision_tag_key",
		"decision_tag_value",
		"decision_record_title",
		"decision_record_summary",
	]:
		_assert_true(
			property_name in property_names,
			"事件选项应支持 %s" % property_name
		)


func _assert_real_main_events_define_core_tags() -> void:
	_assert_event_options_have_single_core_tag(
		"res://data/events/event_2044_space_elevator_crisis.tres",
		"decision.core_2044_automation_access"
	)
	_assert_event_options_have_single_core_tag(
		"res://data/events/event_2053_great_flood_accident.tres",
		"decision.core_2053_civic_priority"
	)
	_assert_event_options_have_single_core_tag(
		"res://data/events/event_2058_lunar_fall_crisis.tres",
		"decision.core_2058_crisis_authorization"
	)
	_assert_event_options_have_single_core_tag(
		"res://data/events/event_2065_ai_isolation_audit.tres",
		"decision.core_2065_audit_boundary"
	)
	_assert_event_options_have_single_core_tag(
		"res://data/events/event_2070_siberian_engine_overload.tres",
		"decision.core_2070_engine_overload_doctrine"
	)


func _assert_event_options_have_single_core_tag(
	resource_path: String,
	expected_key: String
) -> void:
	var event := load(resource_path) as GameEvent
	_assert_true(event != null, "应能加载真实主事件资源：%s" % resource_path)
	if event == null:
		return
	_assert_true(not event.options.is_empty(), "主事件应包含选项：%s" % event.event_title)
	for option in event.options:
		_assert_eq(
			option.decision_tag_key,
			expected_key,
			"%s 的每个选项应写入核心历史标签键" % event.event_title
		)
		_assert_true(
			option.decision_tag_value != "",
			"%s 的每个选项应写入核心历史标签值" % event.event_title
		)
		_assert_true(
			option.decision_record_title != "",
			"%s 的每个选项应写入可读档案标题" % event.event_title
		)
		_assert_true(
			option.decision_record_summary != "",
			"%s 的每个选项应写入长期影响摘要" % event.event_title
		)


func _assert_event_choice_writes_decision_archive() -> void:
	var event := _create_decision_event()
	_main_os.all_events = [event] as Array[GameEvent]
	_main_os.triggered_events.clear()
	_main_os.current_year = 2044
	_main_os.current_month = 1

	_assert_true(
		_main_os.has_method("get_decision_tag"),
		"MainOS 应提供 get_decision_tag 查询接口"
	)
	_assert_true(
		_main_os.has_method("has_decision_tag"),
		"MainOS 应提供 has_decision_tag 查询接口"
	)
	_assert_true(
		_main_os.has_method("get_decision_archive"),
		"MainOS 应提供 get_decision_archive 查询接口"
	)
	if (
		not _main_os.has_method("get_decision_tag")
		or not _main_os.has_method("has_decision_tag")
		or not _main_os.has_method("get_decision_archive")
	):
		return

	_main_os._on_timer_timeout()
	await get_tree().process_frame
	_event_popup.option_selected.emit(0)
	await get_tree().process_frame

	_assert_eq(
		_main_os.get_decision_tag("decision.core_2044_automation_access"),
		"public_counterstrike",
		"选择主事件方案后应写入核心历史标签"
	)
	_assert_true(
		_main_os.has_decision_tag(
			"decision.core_2044_automation_access",
			"public_counterstrike"
		),
		"has_decision_tag 应能匹配指定核心历史标签值"
	)

	var archive: Array = _main_os.get_decision_archive()
	_assert_eq(archive.size(), 1, "核心历史标签应生成一条档案记录")
	if archive.is_empty():
		return

	var record: Dictionary = archive[0]
	_assert_eq(record.get("year"), 2044, "档案记录应保存发生年份")
	_assert_eq(record.get("month"), 1, "档案记录应保存发生月份")
	_assert_eq(record.get("key"), "decision.core_2044_automation_access", "档案记录应保存标签键")
	_assert_eq(record.get("value"), "public_counterstrike", "档案记录应保存标签值")
	_assert_eq(record.get("title"), "2044 公开反击数字生命派", "档案记录应保存可读标题")
	_assert_true(
		"自动化接入" in str(record.get("summary")),
		"档案记录应保存玩家可理解的长期影响摘要"
	)


func _assert_decision_archive_panel_reflects_records() -> void:
	_event_popup.hide()
	_assert_true(
		_main_os.has_node("%DecisionArchiveButton"),
		"主界面应提供决策档案按钮"
	)
	_assert_true(
		_main_os.has_node("%DecisionArchivePanel"),
		"主界面应提供决策档案面板"
	)
	_assert_true(
		_main_os.has_node("%DecisionArchiveText"),
		"决策档案面板应提供文本内容节点"
	)
	if (
		not _main_os.has_node("%DecisionArchiveButton")
		or not _main_os.has_node("%DecisionArchivePanel")
		or not _main_os.has_node("%DecisionArchiveText")
	):
		return

	var button := _main_os.get_node("%DecisionArchiveButton") as Button
	var panel := _main_os.get_node("%DecisionArchivePanel") as Control
	var text := _main_os.get_node("%DecisionArchiveText") as RichTextLabel
	_assert_true("1" in button.text, "决策档案按钮应显示已有记录数量")

	button.pressed.emit()
	_assert_true(panel.visible, "点击决策档案按钮应打开档案面板")
	_assert_true(
		"2044 公开反击数字生命派" in text.text,
		"档案面板应显示核心历史标题"
	)
	_assert_true(
		"自动化接入" in text.text,
		"档案面板应显示长期影响摘要"
	)


func _assert_restart_clears_decision_archive() -> void:
	_main_os.restart_game_for_test()
	_main_os.get_node("Timer").stop()
	if not _main_os.has_method("get_decision_tag") or not _main_os.has_method("get_decision_archive"):
		return

	_assert_eq(
		_main_os.get_decision_tag("decision.core_2044_automation_access"),
		"",
		"重开游戏应清空核心历史标签"
	)
	_assert_eq(
		_main_os.get_decision_archive().size(),
		0,
		"重开游戏应清空决策档案"
	)


func _create_decision_event() -> GameEvent:
	var event := GameEvent.new()
	event.event_title = "太空电梯危机"
	event.event_time = 2044
	event.event_month = 1
	event.event_region = "亚洲"
	event.event_description = "测试核心历史标签写入。"
	event.options = [
		_create_decision_option(),
	]
	return event


func _create_decision_option() -> EventOption:
	var option := EventOption.new()
	option.button_text = "公开反击"
	option.order_delta = 1
	option.hope_delta = 1
	option.authority_delta = 1
	option.set("decision_tag_key", "decision.core_2044_automation_access")
	option.set("decision_tag_value", "public_counterstrike")
	option.set("decision_record_title", "2044 公开反击数字生命派")
	option.set("decision_record_summary", "自动化接入被公开扩大，人类社会从第一场危机开始知道 MOSS 正在进入关键工程系统。")
	return option


func _get_property_names(value: Object) -> Array[String]:
	var property_names: Array[String] = []
	for property in value.get_property_list():
		property_names.append(str(property["name"]))
	return property_names


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
