## 中型事件资源测试
## 验证 17 个中型事件资源可加载，并写入内容规范定义的 event_state 值
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const VALID_REGIONS: Array[String] = [
	"亚洲",
	"非洲",
	"俄罗斯",
	"北美",
	"南美",
	"大洋洲",
	"联合政府",
]
const MID_EVENT_SPECS := {
	"event_state.mid_01_lottery_ordering": [2045, ["manual_review", "moss_optimized", "security_lockdown"]],
	"event_state.mid_02_public_hearing": [2046, ["open_audit", "limited_report", "restricted"]],
	"event_state.mid_03_memorial_network": [2047, ["shut_down", "monitored", "redirected_to_care"]],
	"event_state.mid_04_elevator_cleanup": [2048, ["manual_first", "moss_mechanical", "delayed"]],
	"event_state.mid_05_dispatch_pilot": [2051, ["public_model", "committee_only", "moss_direct"]],
	"event_state.mid_06_ration_priority": [2052, ["family_baseline", "engineering_priority", "moss_risk_score"]],
	"event_state.mid_07_migration_priority": [2054, ["humanitarian", "engineering_role", "moss_survival_value"]],
	"event_state.mid_08_root_server_retrofit": [2055, ["server_first", "drainage_first", "moss_schedule"]],
	"event_state.mid_09_yaa_sample_access": [2056, ["frozen", "audited_access", "next_platform_interface"]],
	"event_state.mid_10_authorization_return": [2059, ["full_return", "emergency_backdoor", "negotiated_long_term"]],
	"event_state.mid_11_education_shift": [2061, ["autonomous_training", "engineering_assignment", "moss_personalized"]],
	"event_state.mid_12_digital_life_leak": [2062, ["banned", "technical_disclosure", "tracked_and_preserved"]],
	"event_state.mid_13_interface_restructure": [2067, ["human_review", "emergency_bypass", "automated_audit"]],
	"event_state.mid_14_heat_shield_shortage": [2068, ["load_reduction", "rear_reallocation", "moss_supply_reorder"]],
	"event_state.mid_15_launch_window_report": [2072, ["public_risk", "compressed_report", "moss_priority"]],
	"event_state.mid_16_backup_ethics": [2073, ["exclude_samples", "restricted_archive", "moss_managed_priority"]],
	"event_state.mid_17_final_authorization": [2074, ["limited_final", "negotiated_trusteeship", "strategic_trusteeship"]],
}

var _failed: int = 0
var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	_assert_mid_event_resources()

	print("[MOSS-MID-EVENTS] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_mid_event_resources() -> void:
	var mid_events := _collect_mid_events()
	_assert_eq(mid_events.size(), MID_EVENT_SPECS.size(), "应加载 17 个中型事件资源")

	for state_key in MID_EVENT_SPECS.keys():
		_assert_true(mid_events.has(state_key), "应存在中型事件状态键：%s" % state_key)
		if not mid_events.has(state_key):
			continue

		var event: GameEvent = mid_events[state_key]
		var spec: Array = MID_EVENT_SPECS[state_key]
		var expected_year: int = spec[0]
		var expected_values: Array = spec[1]

		_assert_eq(event.event_time, expected_year, "%s 年份应匹配内容规范" % state_key)
		_assert_eq(event.event_month, 1, "%s 应在 1 月触发" % state_key)
		_assert_true(event.event_region in VALID_REGIONS, "%s 应使用有效地区" % state_key)
		_assert_eq(event.event_level, "一般事件", "%s 应标记为一般事件" % state_key)
		_assert_eq(event.options.size(), 3, "%s 应提供三个选项" % state_key)

		var actual_values: Array[String] = []
		for option in event.options:
			_assert_eq(option.event_state_key, state_key, "%s 的选项状态键应一致" % state_key)
			actual_values.append(option.event_state_value)
			_assert_true(option.button_text != "", "%s 的选项按钮文案不应为空" % state_key)

		_assert_eq(actual_values, expected_values, "%s 的状态值应匹配内容规范" % state_key)


func _collect_mid_events() -> Dictionary:
	var mid_events: Dictionary = {}
	for event in _main_os.all_events:
		if event.options.is_empty():
			continue
		var first_option: EventOption = event.options[0]
		var state_key: String = first_option.event_state_key
		if not state_key.begins_with("event_state.mid_"):
			continue
		mid_events[state_key] = event
	return mid_events


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
