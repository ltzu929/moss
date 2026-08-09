## 主界面 HUD 组件。
## 只接收主控制器传入的资源、时间和指令快照，不读取 MainOS 或战略工作区内部节点。
class_name MainHud
extends Control

signal decision_archive_requested
signal technology_requested
signal situation_requested
signal time_control_requested
signal command_requested(command: CommandData)

const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const COMMAND_BUTTON_SCENE := preload("res://scenes/command_button.tscn")

const SIDE_MARGIN: float = 16.0
const TOP_MARGIN: float = 16.0
const TOP_BAR_HEIGHT: float = 52.0
const YEAR_PROGRESS_HEIGHT: float = 28.0
const COMMAND_DOCK_HEIGHT: float = 54.0
const SECTOR_INFO_HEIGHT: float = 94.0
const SEPARATION: float = 10.0

@onready var _top_bar: HBoxContainer = $TopBarContainer
@onready var _moss_label: Label = $TopBarContainer/MossLabel
@onready var _computational_label: Label = $TopBarContainer/ComputationalLabel
@onready var _energy_label: Label = $TopBarContainer/EnergyLabel
@onready var _decision_archive_button: Button = $TopBarContainer/DecisionArchiveButton
@onready var _technology_button: Button = $TopBarContainer/TechnologyButton
@onready var _situation_button: Button = $TopBarContainer/SituationButton
@onready var _time_control_button: Button = $TopBarContainer/TimeControlButton
@onready var _year_progress: YearProgress = $YearProgress
@onready var _command_dock: PanelContainer = $CommandDock
@onready var _command_button_container: HBoxContainer = $CommandDock/CommandDockMargin/CommandButtonContainer
@onready var _command_context_label: Label = $CommandDock/CommandDockMargin/CommandButtonContainer/CommandContextLabel

var _command_buttons: Array[CommandButton] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decision_archive_button.pressed.connect(_on_decision_archive_pressed)
	_technology_button.pressed.connect(_on_technology_pressed)
	_situation_button.pressed.connect(_on_situation_pressed)
	_time_control_button.pressed.connect(_on_time_control_pressed)
	_apply_theme()
	_layout_children()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_children()


## 更新顶栏资源、型号和入口计数。
func update_resources(
	model_name: String,
	cpu: int,
	energy: int,
	technology_points: int,
	decision_count: int,
	situation_count: int,
	max_situations: int
) -> void:
	_moss_label.text = model_name
	_computational_label.text = "算力: " + str(cpu)
	_energy_label.text = "能源: " + str(energy)
	_technology_button.text = "科技协议  %d" % technology_points
	_decision_archive_button.text = "决策档案  %d" % decision_count
	_situation_button.text = "局势  %d / %d" % [situation_count, max_situations]


func set_technology_points(value: int) -> void:
	_technology_button.text = "科技协议  %d" % value


func set_decision_count(value: int) -> void:
	_decision_archive_button.text = "决策档案  %d" % value


func set_situation_count(value: int, maximum: int) -> void:
	_situation_button.text = "局势  %d / %d" % [value, maximum]


## 更新日期进度和暂停/继续按钮状态。
func set_time_state(
	year: int,
	month: int,
	is_running: bool,
	manually_paused: bool,
	situation_auto_paused: bool
) -> void:
	_year_progress.update_progress(year, month)
	_time_control_button.text = "继续" if not is_running else "暂停"
	if situation_auto_paused:
		_time_control_button.tooltip_text = "请先处理当前局势节点"
	elif manually_paused:
		_time_control_button.tooltip_text = "继续月度推进"
	else:
		_time_control_button.tooltip_text = (
			"暂停月度推进" if is_running else "继续月度推进"
		)


## 更新当前选区的指令上下文提示。
func set_command_context(text: String) -> void:
	_command_context_label.text = text


## 装配动态指令按钮；按钮点击只发出语义信号，不执行领域规则。
func set_commands(commands: Array[CommandData]) -> void:
	for child in _command_button_container.get_children():
		if child is not CommandButton:
			continue
		_command_button_container.remove_child(child)
		child.queue_free()
	_command_buttons.clear()

	for command in commands:
		var button := COMMAND_BUTTON_SCENE.instantiate() as CommandButton
		if button == null:
			continue
		button.setup(command)
		button.command_pressed.connect(_on_command_pressed)
		_command_button_container.add_child(button)
		_command_buttons.append(button)


## 应用主控制器预先计算的指令可用性快照。
func set_command_availability(availability: Dictionary) -> void:
	for button in _command_buttons:
		var state: Dictionary = availability.get(button.command_data.command_id, {})
		button.set_availability(
			bool(state.get("available", false)),
			str(state.get("reason", "")),
			str(state.get("cost_text", ""))
		)


## 设置或读取指令上下文，供测试和其他显示协调器使用。
func get_command_context_text() -> String:
	return _command_context_label.text


func get_situation_button() -> Button:
	return _situation_button


func get_time_control_button() -> Button:
	return _time_control_button


func get_technology_button() -> Button:
	return _technology_button


func get_year_progress() -> YearProgress:
	return _year_progress


func get_command_dock() -> PanelContainer:
	return _command_dock


func _layout_children() -> void:
	if _top_bar == null:
		return
	var content_width := maxf(0.0, size.x - SIDE_MARGIN * 2.0)
	_top_bar.position = Vector2(SIDE_MARGIN, TOP_MARGIN)
	_top_bar.size = Vector2(content_width, TOP_BAR_HEIGHT)
	_year_progress.position = Vector2(
		SIDE_MARGIN,
		TOP_MARGIN + TOP_BAR_HEIGHT + SEPARATION
	)
	_year_progress.size = Vector2(content_width, YEAR_PROGRESS_HEIGHT)
	_command_dock.position = Vector2(
		SIDE_MARGIN,
		size.y - SIDE_MARGIN - SECTOR_INFO_HEIGHT - SEPARATION - COMMAND_DOCK_HEIGHT
	)
	_command_dock.size = Vector2(content_width, COMMAND_DOCK_HEIGHT)


func _apply_theme() -> void:
	_moss_label.add_theme_color_override("font_color", MOSS_THEME.DANGER)
	_moss_label.add_theme_font_size_override("font_size", 16)
	_computational_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	_energy_label.add_theme_color_override("font_color", MOSS_THEME.ACCENT_GOLD)
	_style_action_button(_technology_button, Vector2(120.0, 44.0), MOSS_THEME.TEXT_PRIMARY)
	_style_action_button(_decision_archive_button, Vector2(128.0, 44.0), MOSS_THEME.TEXT_PRIMARY)
	_style_action_button(_situation_button, Vector2(112.0, 44.0), MOSS_THEME.TEXT_PRIMARY)
	_style_action_button(_time_control_button, Vector2(80.0, 44.0), MOSS_THEME.ACCENT_CYAN, true)
	_command_dock.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.021, 0.047, 0.064, 0.96),
			MOSS_THEME.BORDER_BRIGHT
		)
	)
	_command_context_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	_command_context_label.add_theme_font_size_override("font_size", 14)


func _style_action_button(
	button: Button,
	minimum_size: Vector2,
	font_color: Color,
	emphasized: bool = false
) -> void:
	button.custom_minimum_size = minimum_size
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(
			Color(0.031, 0.072, 0.088, 0.98) if emphasized else Color(0.023, 0.050, 0.065, 0.94),
			MOSS_THEME.BORDER_BRIGHT if emphasized else MOSS_THEME.BORDER,
			2 if emphasized else 1
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(
			Color(0.050, 0.112, 0.126, 1.0) if emphasized else Color(0.043, 0.095, 0.112, 0.98),
			MOSS_THEME.ACCENT_CYAN,
			2 if emphasized else 1
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		MOSS_THEME.button_style(
			Color(0.016, 0.038, 0.050, 1.0),
			MOSS_THEME.ACCENT_CYAN,
			2 if emphasized else 1
		)
	)


func _on_decision_archive_pressed() -> void:
	decision_archive_requested.emit()


func _on_technology_pressed() -> void:
	technology_requested.emit()


func _on_situation_pressed() -> void:
	situation_requested.emit()


func _on_time_control_pressed() -> void:
	time_control_requested.emit()


func _on_command_pressed(command: CommandData) -> void:
	command_requested.emit(command)
