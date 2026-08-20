extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const SAVE_SERVICE_SCRIPT := preload("res://scripts/systems/save_service.gd")
const TEST_SAVE_DIR: String = "user://save_system_test"


func _ready() -> void:
	_cleanup_test_files()
	_assert_slot_file_contract()
	await _assert_main_os_round_trip()
	_cleanup_test_files()
	print("[MOSS-SAVE-SYSTEM] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


func _assert_slot_file_contract() -> void:
	var service: SaveService = SAVE_SERVICE_SCRIPT.new(TEST_SAVE_DIR)
	var slots := service.list_slots()
	_assert_eq(slots.size(), 4, "存档服务应固定提供一个自动档和三个手动档")
	_assert_true(service.get_latest_valid_slot().is_empty(), "空目录不应提供继续游戏存档")
	_assert_true(
		service.write_slot("autosave", {"value": 1}, {"year": 2044, "month": 1}),
		"应能写入自动存档"
	)
	_assert_true(
		service.write_slot("slot_1", {"value": 2}, {"year": 2050, "month": 6}),
		"应能写入手动存档"
	)
	var latest := service.get_latest_valid_slot()
	_assert_eq(str(latest.get("slot_id", "")), "slot_1", "继续游戏应选择最近有效存档")
	var loaded := service.read_slot("slot_1")
	_assert_true(bool(loaded.get("success", false)), "手动存档应能读取")
	_assert_eq(int(loaded.get("state", {}).get("value", 0)), 2, "读取应保留整数状态")
	_assert_true(service.delete_slot("slot_1"), "应能删除手动存档")
	_assert_true(not service.slot_exists("slot_1"), "删除后槽位文件应消失")

	var corrupt := FileAccess.open(TEST_SAVE_DIR + "/slot_2.json", FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.flush()
	_assert_true(
		not bool(service.read_slot("slot_2").get("success", true)),
		"损坏 JSON 应拒绝读取"
	)
	var unsupported := FileAccess.open(TEST_SAVE_DIR + "/slot_3.json", FileAccess.WRITE)
	unsupported.store_string(
		JSON.stringify(
			{
				"format_version": 99,
				"saved_at_unix": Time.get_unix_time_from_system(),
				"metadata": {},
				"state": {},
			}
		)
	)
	unsupported.flush()
	_assert_true(
		"版本" in str(service.read_slot("slot_3").get("error", "")),
		"不支持的格式版本应给出明确错误"
	)


func _assert_main_os_round_trip() -> void:
	var source := MAIN_SCENE.instantiate() as MainOS
	add_child(source)
	await get_tree().process_frame
	await get_tree().process_frame
	source.toggle_time_control()
	source.current_year = 2056
	source.current_month = 6
	var technology := source.get_node("%TechnologySystem") as TechnologySystem
	_assert_true(technology.activate("managed_decision"), "测试存档应激活一个科技节点")
	source.current_cpu = 47
	source.current_energy = 123
	source.command_cooldowns["allocate"] = 7
	source.set_event_state("event_state.test_save", "kept")
	var option := EventOption.new()
	option.decision_tag_key = "decision.test_save"
	option.decision_tag_value = "kept"
	option.decision_record_title = "存档测试决策"
	option.decision_record_summary = "验证核心决策往返"
	source.apply_event_option_decision(option, "存档测试事件")
	source.set_situation_seed_for_test(24680)
	var situation := source.start_situation_for_test(
		"regional_power_instability",
		"asia",
		2056,
		6
	)
	_assert_true(not situation.is_empty(), "测试存档应包含活跃局势")
	var workspace := source.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	var selected := workspace.get_sector_nodes()[2] as SectorInfo
	selected.data_card.order = 73
	selected.data_card.hope = 61
	source.select_sector(selected)
	source.record_action("test", "存档测试", "保留行动日志")
	source.set_time_speed(2.0)
	var expected := source.export_save_state()
	_assert_true(source.validate_save_state(expected), "主场景导出的状态应可恢复")

	var service: SaveService = SAVE_SERVICE_SCRIPT.new(TEST_SAVE_DIR)
	_assert_true(
		service.write_slot("slot_1", expected, source.build_save_metadata()),
		"完整游戏状态应能写入手动档"
	)
	var loaded := service.read_slot("slot_1")
	_assert_true(bool(loaded.get("success", false)), "完整游戏状态应能从 JSON 读取")

	var restored := MAIN_SCENE.instantiate() as MainOS
	add_child(restored)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(restored.restore_save_state(loaded["state"]), "合法存档应恢复成功")
	_assert_eq(restored.export_save_state(), loaded["state"], "恢复后再次导出的状态应完全一致")
	_assert_true((restored.get_node("Timer") as Timer).is_stopped(), "载入后时间应保持暂停")

	source.queue_free()
	restored.queue_free()
	await get_tree().process_frame


func _cleanup_test_files() -> void:
	for slot_id in SaveService.SLOT_IDS:
		var path := "%s/%s.json" % [TEST_SAVE_DIR, slot_id]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_dir := ProjectSettings.globalize_path(TEST_SAVE_DIR)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)
