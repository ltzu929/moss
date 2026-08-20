class_name AppRoot
extends Control

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const SAVE_SERVICE_SCRIPT := preload("res://scripts/systems/save_service.gd")
const SETTINGS_SERVICE_SCRIPT := preload("res://scripts/systems/settings_service.gd")
const BACKGROUND_MUSIC: AudioStream = preload("res://assets/audio/background_music.ogg")

@export var save_directory: String = "user://saves"
@export var settings_path: String = "user://settings.cfg"
@export var apply_display_settings: bool = true

var _save_service: SaveService
var _settings_service: SettingsService
var _game: MainOS = null
var _main_menu: Control
var _system_overlay: Control
var _slot_overlay: Control
var _settings_overlay: Control
var _slot_list: VBoxContainer
var _slot_status: Label
var _system_status: Label
var _settings_status: Label
var _display_mode_option: OptionButton
var _resolution_option: OptionButton
var _confirmation: ConfirmationDialog
var _background_music: AudioStreamPlayer
var _pending_confirmation: Callable
var _slot_mode: String = "load"
var _system_timer_was_running: bool = false
var _menu_buttons: Dictionary = {}


func _ready() -> void:
	set_process_unhandled_input(true)
	_save_service = SAVE_SERVICE_SCRIPT.new(save_directory)
	_settings_service = SETTINGS_SERVICE_SCRIPT.new(settings_path)
	_build_interface()
	_setup_background_music()
	var settings := _settings_service.load_settings()
	if apply_display_settings:
		_settings_service.apply_settings(settings)
	_show_main_menu()


func _setup_background_music() -> void:
	_background_music = AudioStreamPlayer.new()
	_background_music.name = "BackgroundMusic"
	_background_music.stream = BACKGROUND_MUSIC
	_background_music.volume_db = -18.0
	add_child(_background_music)
	_background_music.play()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_overlay.visible:
		_settings_overlay.hide()
	elif _slot_overlay.visible:
		_slot_overlay.hide()
	elif _system_overlay.visible:
		close_system_menu()
	elif _game != null and is_instance_valid(_game):
		open_system_menu()
	else:
		return
	get_viewport().set_input_as_handled()


func get_menu_button(action: String) -> Button:
	return _menu_buttons.get(action) as Button


func get_game_instance() -> MainOS:
	return _game


func get_slot_row_count() -> int:
	return 0 if _slot_list == null else _slot_list.get_child_count()


func get_display_mode_option() -> OptionButton:
	return _display_mode_option


func get_resolution_option() -> OptionButton:
	return _resolution_option


func get_active_overlay_name() -> String:
	if _settings_overlay.visible:
		return "settings"
	if _slot_overlay.visible:
		return "slots"
	if _system_overlay.visible:
		return "system"
	return "main_menu" if _main_menu.visible else "game"


func open_system_menu() -> void:
	if _game == null or not is_instance_valid(_game):
		return
	if not _game.can_open_system_menu():
		return
	_system_timer_was_running = bool(_game.pause_for_system_menu())
	_system_status.text = ""
	_system_overlay.show()
	_system_overlay.move_to_front()


func close_system_menu() -> void:
	_system_overlay.hide()
	if _game != null and is_instance_valid(_game):
		_game.resume_after_system_menu(_system_timer_was_running)
	_system_timer_was_running = false


func open_slot_browser(mode: String = "load") -> void:
	_slot_mode = "save" if mode == "save" else "load"
	_rebuild_slot_rows()
	_slot_status.text = ""
	_slot_overlay.show()
	_slot_overlay.move_to_front()


func open_settings() -> void:
	var settings := _settings_service.load_settings()
	_display_mode_option.select(
		1 if str(settings["mode"]) == SettingsService.FULLSCREEN else 0
	)
	_resolution_option.select(_settings_service.resolution_index(settings))
	_resolution_option.disabled = _display_mode_option.selected == 1
	_settings_status.text = ""
	_settings_overlay.show()
	_settings_overlay.move_to_front()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.name = "ApplicationBackground"
	background.color = MOSS_THEME.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_main_menu()
	_build_system_menu()
	_build_slot_browser()
	_build_settings_panel()
	_confirmation = ConfirmationDialog.new()
	_confirmation.name = "Confirmation"
	_confirmation.title = "确认操作"
	_confirmation.confirmed.connect(_on_confirmation_confirmed)
	add_child(_confirmation)


func _build_main_menu() -> void:
	_main_menu = Control.new()
	_main_menu.name = "MainMenu"
	_main_menu.z_index = 10
	add_child(_main_menu)
	_main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_main_menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "MainMenuPanel"
	panel.custom_minimum_size = Vector2(520.0, 650.0)
	panel.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.018, 0.045, 0.062, 0.98),
			MOSS_THEME.BORDER_BRIGHT,
			2
		)
	)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 42)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	var title := _make_label("MOSS", 64, MOSS_THEME.ACCENT_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle := _make_label("文明守护协议  //  2044—2075", 16, MOSS_THEME.TEXT_SECONDARY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	var separator := HSeparator.new()
	separator.custom_minimum_size.y = 28
	content.add_child(separator)
	_add_main_menu_button(content, "new_game", "新游戏", _on_new_game_pressed)
	_add_main_menu_button(content, "continue", "继续游戏", _on_continue_pressed)
	_add_main_menu_button(content, "load", "读取游戏", _on_load_pressed)
	_add_main_menu_button(content, "settings", "设置", open_settings)
	_add_main_menu_button(content, "quit", "退出游戏", _on_quit_pressed)
	var status := _make_label("", 14, MOSS_THEME.ACCENT_GOLD)
	status.name = "MainMenuStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(status)


func _add_main_menu_button(
	parent: VBoxContainer,
	action: String,
	text: String,
	callback: Callable
) -> void:
	var button := _make_button(text, "%sButton" % action.to_pascal_case())
	button.pressed.connect(callback)
	parent.add_child(button)
	_menu_buttons[action] = button


func _build_system_menu() -> void:
	var modal := _create_modal("SystemMenu", "系统菜单", Vector2(460.0, 610.0), 100)
	_system_overlay = modal["root"]
	var body: VBoxContainer = modal["body"]
	var continue_button := _make_button("继续游戏", "ContinueGameButton")
	continue_button.pressed.connect(close_system_menu)
	body.add_child(continue_button)
	var save_button := _make_button("保存游戏", "SaveGameButton")
	save_button.pressed.connect(open_slot_browser.bind("save"))
	body.add_child(save_button)
	var load_button := _make_button("读取游戏", "LoadGameButton")
	load_button.pressed.connect(open_slot_browser.bind("load"))
	body.add_child(load_button)
	var settings_button := _make_button("设置", "SystemSettingsButton")
	settings_button.pressed.connect(open_settings)
	body.add_child(settings_button)
	var return_button := _make_button("返回主页面", "ReturnToTitleButton")
	return_button.pressed.connect(_on_return_to_title_pressed)
	body.add_child(return_button)
	_system_status = _make_label("", 14, MOSS_THEME.ACCENT_GOLD)
	_system_status.name = "SystemMenuStatus"
	_system_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_system_status)
	_system_overlay.hide()


func _build_slot_browser() -> void:
	var modal := _create_modal("SlotBrowser", "存档管理", Vector2(760.0, 680.0), 120)
	_slot_overlay = modal["root"]
	var body: VBoxContainer = modal["body"]
	_slot_list = VBoxContainer.new()
	_slot_list.name = "SlotList"
	_slot_list.add_theme_constant_override("separation", 10)
	body.add_child(_slot_list)
	_slot_status = _make_label("", 14, MOSS_THEME.ACCENT_GOLD)
	_slot_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_slot_status)
	var back_button := _make_button("返回", "SlotBackButton")
	back_button.pressed.connect(_slot_overlay.hide)
	body.add_child(back_button)
	_slot_overlay.hide()


func _build_settings_panel() -> void:
	var modal := _create_modal("SettingsPanel", "显示设置", Vector2(560.0, 520.0), 130)
	_settings_overlay = modal["root"]
	var body: VBoxContainer = modal["body"]
	body.add_child(_make_label("窗口模式", 15, MOSS_THEME.TEXT_PRIMARY))
	_display_mode_option = OptionButton.new()
	_display_mode_option.name = "DisplayModeOption"
	_display_mode_option.add_item("窗口")
	_display_mode_option.add_item("全屏")
	_style_button(_display_mode_option)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	body.add_child(_display_mode_option)
	body.add_child(_make_label("窗口分辨率", 15, MOSS_THEME.TEXT_PRIMARY))
	_resolution_option = OptionButton.new()
	_resolution_option.name = "ResolutionOption"
	for size in SettingsService.RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [size.x, size.y])
	_style_button(_resolution_option)
	body.add_child(_resolution_option)
	_settings_status = _make_label("", 14, MOSS_THEME.ACCENT_GOLD)
	_settings_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_settings_status)
	var apply_button := _make_button("应用", "ApplySettingsButton")
	apply_button.pressed.connect(_on_apply_settings_pressed)
	body.add_child(apply_button)
	var back_button := _make_button("返回", "SettingsBackButton")
	back_button.pressed.connect(_settings_overlay.hide)
	body.add_child(back_button)
	_settings_overlay.hide()


func _create_modal(
	name: String,
	title_text: String,
	minimum_size: Vector2,
	z_index: int
) -> Dictionary:
	var root := Control.new()
	root.name = name
	root.z_index = z_index
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "%sWindow" % name
	panel.custom_minimum_size = minimum_size
	panel.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.018, 0.045, 0.062, 0.99),
			MOSS_THEME.BORDER_BRIGHT,
			2
		)
	)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 30)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)
	var title := _make_label(title_text, 28, MOSS_THEME.ACCENT_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var separator := HSeparator.new()
	separator.custom_minimum_size.y = 16
	body.add_child(separator)
	return {"root": root, "body": body}


func _make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 52.0)
	_style_button(button)
	return button


func _style_button(button: BaseButton) -> void:
	button.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	button.add_theme_color_override(
		"font_disabled_color",
		Color(0.45, 0.52, 0.58, 1.0)
	)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(MOSS_THEME.PANEL_BACKGROUND, MOSS_THEME.BORDER)
	)
	button.add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(
			MOSS_THEME.PANEL_BACKGROUND_HOVER,
			MOSS_THEME.ACCENT_CYAN,
			2
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		MOSS_THEME.button_style(
			Color(0.016, 0.038, 0.050, 1.0),
			MOSS_THEME.ACCENT_CYAN,
			2
		)
	)
	button.add_theme_stylebox_override(
		"disabled",
		MOSS_THEME.button_style(
			Color(0.018, 0.028, 0.035, 0.82),
			MOSS_THEME.BORDER
		)
	)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _show_main_menu(message: String = "") -> void:
	_main_menu.show()
	_system_overlay.hide()
	_slot_overlay.hide()
	_settings_overlay.hide()
	var latest := _save_service.get_latest_valid_slot()
	get_menu_button("continue").disabled = latest.is_empty()
	var status := _main_menu.find_child("MainMenuStatus", true, false) as Label
	if status != null:
		status.text = message
	get_menu_button("new_game").grab_focus()


func _on_new_game_pressed() -> void:
	if _save_service.slot_exists("autosave"):
		_ask_confirmation(
			"开始新游戏将覆盖自动存档，三个手动存档会保留。",
			_start_new_game
		)
	else:
		_start_new_game()


func _start_new_game() -> void:
	_save_service.delete_slot("autosave")
	_start_game()


func _on_continue_pressed() -> void:
	var latest := _save_service.get_latest_valid_slot()
	if latest.is_empty():
		_show_main_menu("没有可继续的有效存档")
		return
	_load_slot(str(latest["slot_id"]))


func _on_load_pressed() -> void:
	open_slot_browser("load")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _start_game(state: Dictionary = {}) -> void:
	_destroy_game()
	_game = MAIN_SCENE.instantiate() as MainOS
	add_child(_game)
	_game.system_menu_requested.connect(open_system_menu)
	_game.autosave_requested.connect(_on_autosave_requested)
	_main_menu.hide()
	_system_overlay.hide()
	_slot_overlay.hide()
	_settings_overlay.hide()
	if not state.is_empty() and not _game.restore_save_state(state):
		_destroy_game()
		_show_main_menu("存档内容无法恢复")
		return
	if state.is_empty():
		_save_auto()


func _destroy_game() -> void:
	if _game == null or not is_instance_valid(_game):
		_game = null
		return
	remove_child(_game)
	_game.queue_free()
	_game = null


func _on_autosave_requested(state: Dictionary) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	_save_service.write_slot("autosave", state, _game.build_save_metadata())


func _save_auto() -> bool:
	if _game == null or not is_instance_valid(_game):
		return false
	return _save_service.write_slot(
		"autosave",
		_game.export_save_state(),
		_game.build_save_metadata()
	)


func _rebuild_slot_rows() -> void:
	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()
	for slot in _save_service.list_slots():
		_slot_list.add_child(_build_slot_row(slot))


func _build_slot_row(slot: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 94.0)
	panel.add_theme_stylebox_override("panel", MOSS_THEME.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var label := _make_label(_format_slot_text(slot), 14, MOSS_THEME.TEXT_PRIMARY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slot_id := str(slot["slot_id"])
	var action := _make_button(
		"保存" if _slot_mode == "save" else "读取",
		"%sActionButton" % slot_id.to_pascal_case()
	)
	action.custom_minimum_size = Vector2(88.0, 44.0)
	if _slot_mode == "save":
		action.disabled = slot_id == "autosave"
		action.text = "自动" if slot_id == "autosave" else (
			"覆盖" if bool(slot["exists"]) else "保存"
		)
		action.pressed.connect(_on_save_slot_pressed.bind(slot_id))
	else:
		action.disabled = not bool(slot["valid"])
		action.pressed.connect(_load_slot.bind(slot_id))
	row.add_child(action)
	var delete_button := _make_button("删除", "%sDeleteButton" % slot_id.to_pascal_case())
	delete_button.custom_minimum_size = Vector2(78.0, 44.0)
	delete_button.disabled = not bool(slot["exists"])
	delete_button.pressed.connect(_on_delete_slot_pressed.bind(slot_id))
	row.add_child(delete_button)
	return panel


func _format_slot_text(slot: Dictionary) -> String:
	var slot_name := "自动存档" if str(slot["slot_id"]) == "autosave" else (
		"手动存档 %s" % str(slot["slot_id"]).trim_prefix("slot_")
	)
	if not bool(slot["exists"]):
		return "%s\n空槽位" % slot_name
	if not bool(slot["valid"]):
		return "%s\n%s" % [slot_name, str(slot["error"])]
	var metadata: Dictionary = slot["metadata"]
	var date_text := "%04d.%02d" % [
		int(metadata.get("year", 2044)),
		int(metadata.get("month", 1)),
	]
	var saved := Time.get_datetime_dict_from_unix_time(int(slot["saved_at_unix"]))
	var saved_text := "%04d-%02d-%02d %02d:%02d" % [
		int(saved.get("year", 0)),
		int(saved.get("month", 0)),
		int(saved.get("day", 0)),
		int(saved.get("hour", 0)),
		int(saved.get("minute", 0)),
	]
	return "%s\n%s  //  %s  //  %s" % [
		slot_name,
		date_text,
		str(metadata.get("model_name", "MOSS-550C")),
		saved_text,
	]


func _on_save_slot_pressed(slot_id: String) -> void:
	if slot_id == "autosave" or _game == null:
		return
	if _save_service.slot_exists(slot_id):
		_ask_confirmation(
			"覆盖该手动存档？",
			_write_manual_slot.bind(slot_id)
		)
	else:
		_write_manual_slot(slot_id)


func _write_manual_slot(slot_id: String) -> void:
	var success := _save_service.write_slot(
		slot_id,
		_game.export_save_state(),
		_game.build_save_metadata()
	)
	_slot_status.text = "保存完成" if success else "保存失败"
	_rebuild_slot_rows()


func _load_slot(slot_id: String) -> void:
	var result := _save_service.read_slot(slot_id)
	if not bool(result.get("success", false)):
		_slot_status.text = str(result.get("error", "读取失败"))
		return
	var state: Dictionary = result["state"]
	if _game != null and is_instance_valid(_game) and not _game.validate_save_state(state):
		_slot_status.text = "存档内容无法恢复"
		return
	_start_game(state)


func _on_delete_slot_pressed(slot_id: String) -> void:
	_ask_confirmation(
		"删除该存档？此操作不可撤销。",
		_delete_slot.bind(slot_id)
	)


func _delete_slot(slot_id: String) -> void:
	var success := _save_service.delete_slot(slot_id)
	_slot_status.text = "存档已删除" if success else "删除失败"
	_rebuild_slot_rows()
	if _main_menu.visible:
		_show_main_menu(_slot_status.text)


func _on_return_to_title_pressed() -> void:
	_ask_confirmation(
		"保存当前进度并返回主页面？",
		_return_to_title
	)


func _return_to_title() -> void:
	if not _save_auto():
		_system_status.text = "保存失败，未返回主页面"
		return
	_destroy_game()
	_show_main_menu("当前进度已保存")


func _on_display_mode_selected(index: int) -> void:
	_resolution_option.disabled = index == 1


func _on_apply_settings_pressed() -> void:
	var size := SettingsService.RESOLUTIONS[_resolution_option.selected]
	var settings := {
		"mode": (
			SettingsService.FULLSCREEN
			if _display_mode_option.selected == 1
			else SettingsService.WINDOWED
		),
		"width": size.x,
		"height": size.y,
	}
	var applied := true
	if apply_display_settings:
		applied = _settings_service.apply_settings(settings)
	var saved := _settings_service.save_settings(settings)
	_settings_status.text = "设置已应用" if applied and saved else "设置保存失败"


func _ask_confirmation(text: String, callback: Callable) -> void:
	_pending_confirmation = callback
	_confirmation.dialog_text = text
	_confirmation.popup_centered(Vector2i(520, 220))


func _on_confirmation_confirmed() -> void:
	var callback := _pending_confirmation
	_pending_confirmation = Callable()
	if callback.is_valid():
		callback.call()
