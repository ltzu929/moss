extends "res://tests/support/moss_test_case.gd"

const APP_SCENE: PackedScene = preload("res://scenes/app_root.tscn")
const SETTINGS_SERVICE_SCRIPT := preload("res://scripts/systems/settings_service.gd")
const TEST_SAVE_DIR: String = "user://app_menu_ui_test_saves"
const TEST_SETTINGS_PATH: String = "user://app_menu_ui_test_settings.cfg"


func _ready() -> void:
	_cleanup_test_files()
	await _assert_main_menu_flow()
	await _assert_compact_layout()
	_cleanup_test_files()
	print("[MOSS-APP-MENU-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


func _assert_main_menu_flow() -> void:
	var project_config := FileAccess.get_file_as_string("res://project.godot")
	_assert_true(
		'run/main_scene="res://scenes/app_root.tscn"' in project_config,
		"项目启动场景应指向应用根"
	)
	var app := _create_app()
	add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	for action in ["new_game", "continue", "load", "settings", "quit"]:
		_assert_true(app.get_menu_button(action) != null, "主页面应提供%s按钮" % action)
	_assert_true(app.get_menu_button("continue").disabled, "无存档时继续游戏应禁用")

	app.open_slot_browser("load")
	await get_tree().process_frame
	_assert_eq(app.get_slot_row_count(), 4, "读取界面应显示四个固定槽位")
	_assert_eq(app.get_active_overlay_name(), "slots", "读取按钮应打开存档界面")
	(app.find_child("SlotBackButton", true, false) as Button).pressed.emit()

	app.open_settings()
	_assert_eq(app.get_display_mode_option().item_count, 2, "设置应提供窗口与全屏")
	_assert_eq(app.get_resolution_option().item_count, 3, "设置应提供三档分辨率")
	app.get_display_mode_option().select(0)
	app.get_display_mode_option().item_selected.emit(0)
	app.get_resolution_option().select(2)
	(app.find_child("ApplySettingsButton", true, false) as Button).pressed.emit()
	var settings: SettingsService = SETTINGS_SERVICE_SCRIPT.new(TEST_SETTINGS_PATH)
	var loaded_settings := settings.load_settings()
	_assert_eq(int(loaded_settings["width"]), 1280, "显示设置应持久化窗口宽度")
	_assert_eq(int(loaded_settings["height"]), 720, "显示设置应持久化窗口高度")
	(app.find_child("SettingsBackButton", true, false) as Button).pressed.emit()

	app.get_menu_button("new_game").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var first_game := app.get_game_instance()
	_assert_true(first_game != null, "新游戏应创建真实 MainOS 实例")
	_assert_true(
		FileAccess.file_exists(TEST_SAVE_DIR + "/autosave.json"),
		"新游戏初始化后应立即产生自动档"
	)
	var save_service := SaveService.new(TEST_SAVE_DIR)
	var initial_auto := save_service.read_slot("autosave")
	(first_game.get_node("Timer") as Timer).stop()
	first_game.current_year = 2045
	first_game.current_month = 2
	await first_game.process_month_tick()
	var monthly_auto := save_service.read_slot("autosave")
	_assert_true(
		float(monthly_auto.get("saved_at_unix", 0.0))
		> float(initial_auto.get("saved_at_unix", 0.0)),
		"完整月度结算后应更新自动档"
	)
	_assert_eq(
		int(monthly_auto.get("metadata", {}).get("month", 0)),
		3,
		"自动档摘要应记录结算后的月份"
	)

	app.open_system_menu()
	_assert_eq(app.get_active_overlay_name(), "system", "系统按钮入口应打开暂停菜单")
	_assert_true((first_game.get_node("Timer") as Timer).is_stopped(), "系统菜单应暂停时间")
	app.open_slot_browser("save")
	await get_tree().process_frame
	var slot_one_save := app.find_child("Slot1ActionButton", true, false) as Button
	_assert_true(slot_one_save != null, "手动存档一应提供保存按钮")
	if slot_one_save != null:
		slot_one_save.pressed.emit()
	_assert_true(
		FileAccess.file_exists(TEST_SAVE_DIR + "/slot_1.json"),
		"系统菜单应能写入手动存档"
	)

	app.open_slot_browser("load")
	await get_tree().process_frame
	var slot_one_load := app.find_child("Slot1ActionButton", true, false) as Button
	if slot_one_load != null:
		slot_one_load.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var restored_game := app.get_game_instance()
	_assert_true(restored_game != null and restored_game != first_game, "读取应创建干净游戏实例")
	_assert_true(
		(restored_game.get_node("Timer") as Timer).is_stopped(),
		"读取存档后应保持暂停"
	)

	app.queue_free()
	await get_tree().process_frame
	var reopened := _create_app()
	add_child(reopened)
	await get_tree().process_frame
	_assert_true(not reopened.get_menu_button("continue").disabled, "存在自动档时继续游戏应可用")
	reopened.get_menu_button("new_game").pressed.emit()
	await get_tree().process_frame
	var confirmation := reopened.find_child("Confirmation", true, false) as ConfirmationDialog
	_assert_true(confirmation != null and confirmation.visible, "覆盖自动档前应要求确认")
	reopened.queue_free()
	await get_tree().process_frame


func _assert_compact_layout() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var app := _create_app()
	viewport.add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := app.find_child("MainMenuPanel", true, false) as Control
	_assert_true(panel != null, "紧凑视口应创建主菜单面板")
	if panel != null:
		var rect := panel.get_global_rect()
		_assert_true(
			rect.position.x >= 0.0
			and rect.position.y >= 0.0
			and rect.end.x <= 1280.0
			and rect.end.y <= 720.0,
			"1280×720 下主菜单应完整位于视口内"
		)
	viewport.queue_free()
	await get_tree().process_frame


func _create_app() -> AppRoot:
	var app := APP_SCENE.instantiate() as AppRoot
	app.save_directory = TEST_SAVE_DIR
	app.settings_path = TEST_SETTINGS_PATH
	app.apply_display_settings = false
	return app


func _cleanup_test_files() -> void:
	for slot_id in SaveService.SLOT_IDS:
		var path := "%s/%s.json" % [TEST_SAVE_DIR, slot_id]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	var absolute_dir := ProjectSettings.globalize_path(TEST_SAVE_DIR)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)
