## 事件可玩性与防软锁测试
extends "res://tests/support/moss_test_case.gd"

const EVENT_DIRECTORY := "res://data/events/"
const EVENT_POPUP_SCENE: PackedScene = preload("res://scenes/event_popup.tscn")
const VALID_EVENT_REGIONS: Array[String] = [
	"north_america",
	"south_america",
	"europe",
	"africa",
	"asia",
	"oceania",
]
const EVENT_DESCRIPTION_CONTRACTS: Dictionary = {
	"event_2065_ai_isolation_audit.tres": {
		"required": "联合政府",
		"forbidden": "欧洲势力",
	},
	"event_mid_02_automation_interface_hearing.tres": {
		"required": "UEG",
		"forbidden": "欧洲势力",
	},
	"event_mid_13_post_audit_interface_restructure.tres": {
		"required": "UEG",
		"forbidden": "欧洲势力",
	},
	"event_mid_15_propulsion_window_compression_report.tres": {
		"required": "UEG",
		"forbidden": "欧洲势力",
	},
	"event_mid_16_civilization_backup_ethics_hearing.tres": {
		"required": "UEG",
		"forbidden": "欧洲势力",
	},
	"event_mid_17_final_authorization_meeting.tres": {
		"required": "UEG",
		"forbidden": "欧洲势力",
	},
	"event_2070_siberian_engine_overload.tres": {
		"required": "西伯利亚发动机群",
		"forbidden": "欧洲负责",
	},
}



func _ready() -> void:
	_assert_all_events_have_safe_choices()
	await _assert_runtime_emergency_fallback()
	print("[MOSS-EVENT-PLAYABILITY] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_all_events_have_safe_choices() -> void:
	var trigger_keys: Dictionary = {}
	var event_count := 0
	var branch_event_count := 0
	for file_name in DirAccess.get_files_at(EVENT_DIRECTORY):
		if not file_name.ends_with(".tres"):
			continue
		var event := load(EVENT_DIRECTORY + file_name) as GameEvent
		_assert_true(event != null, "事件资源应能加载：%s" % file_name)
		if event == null:
			continue
		event_count += 1
		_assert_true(not event.event_title.is_empty(), "事件标题不得为空：%s" % file_name)
		_assert_true(not event.event_region.is_empty(), "事件地区不得为空：%s" % file_name)
		_assert_true(
			event.event_region in VALID_EVENT_REGIONS,
			"事件地区必须对应现有板块：%s -> %s" % [file_name, event.event_region]
		)
		if EVENT_DESCRIPTION_CONTRACTS.has(file_name):
			var contract: Dictionary = EVENT_DESCRIPTION_CONTRACTS[file_name]
			var required_text := str(contract.get("required", ""))
			var forbidden_text := str(contract.get("forbidden", ""))
			_assert_true(
				required_text in event.event_description,
				"事件正文应保留世界观主体：%s -> %s" % [file_name, required_text]
			)
			_assert_true(
				forbidden_text not in event.event_description,
				"事件正文不应把数值归属写成组织身份：%s -> %s" % [
					file_name,
					forbidden_text,
				]
			)
		_assert_true(not event.options.is_empty(), "事件至少需要一个方案：%s" % event.event_title)
		if event.required_decision_tag_key.is_empty():
			_assert_true(
				event.required_decision_tag_value.is_empty(),
				"固定事件不得孤立声明分支触发值：%s" % event.event_title
			)
		else:
			branch_event_count += 1
			_assert_true(
				not event.required_decision_tag_value.is_empty(),
				"条件分支必须声明精确核心触发值：%s" % event.event_title
			)
		var has_zero_energy_option := false
		for option in event.options:
			_assert_true(not option.button_text.is_empty(), "事件方案文本不得为空：%s" % event.event_title)
			_assert_true(option.energy_cost >= 0, "事件能源消耗不得为负：%s" % event.event_title)
			has_zero_energy_option = has_zero_energy_option or option.energy_cost == 0
		_assert_true(
			has_zero_energy_option,
			"强制事件必须提供零能源保底方案：%s" % event.event_title
		)

		var trigger_key := event.event_id
		_assert_true(not trigger_key.is_empty(), "事件触发键不得为空：%s" % file_name)
		_assert_true(not trigger_keys.has(trigger_key), "事件触发键不得重复：%s" % trigger_key)
		trigger_keys[trigger_key] = true
	_assert_true(event_count >= 25, "应覆盖全部现有事件资源")
	_assert_eq(branch_event_count, 2, "首个可玩版应注册两个受核心选择控制的短分支")


func _assert_runtime_emergency_fallback() -> void:
	var popup := EVENT_POPUP_SCENE.instantiate()
	add_child(popup)
	await get_tree().process_frame
	var event := GameEvent.new()
	event.event_id = "event_test_playability_fallback"
	event.event_title = "防软锁测试"
	event.event_time = 2050
	event.event_region = "europe"
	event.event_description = "所有配置方案都超过当前能源。"
	event.options = [
		_create_option("高成本方案", 20),
		_create_option("最低成本方案", 10),
	]
	popup.popup_event(event, 0)

	_assert_eq(event.options[1].energy_cost, 0, "紧急降级应把最低成本压到剩余能源")
	_assert_true("紧急降级" in event.options[1].button_text, "紧急降级应向玩家说明原因")
	var enabled_count := 0
	for child in popup.get_node("%OptionList").get_children():
		if child is Button and not child.disabled:
			enabled_count += 1
	_assert_eq(enabled_count, 1, "异常资源仍应保留一个真实可点击方案")
	popup.queue_free()


func _create_option(text: String, energy_cost: int) -> EventOption:
	var option := EventOption.new()
	option.button_text = text
	option.energy_cost = energy_cost
	return option
