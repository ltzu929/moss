## 指令按钮组件 - 显示单个MOSS指令按钮
## 负责按钮状态更新和点击响应
@tool
class_name CommandButton
extends Button

# ============================================================
# 信号定义
# ============================================================

## 按钮被点击时发出，携带指令数据
signal command_pressed(cmd: CommandData)

# ============================================================
# 常量
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const EDITOR_PREVIEW_COMMAND: CommandData = preload("res://data/commands/command_allocate.tres")

@export_group("编辑器预览")
@export var editor_preview_command: CommandData = EDITOR_PREVIEW_COMMAND:
	set(value):
		editor_preview_command = value
		if Engine.is_editor_hint() and is_inside_tree():
			_render_editor_preview()

# ============================================================
# 状态变量
# ============================================================

## 关联的指令数据
var command_data: CommandData = null

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	_apply_terminal_style()
	if Engine.is_editor_hint():
		_render_editor_preview()
	elif command_data != null:
		text = command_data.command_name


func _render_editor_preview() -> void:
	if editor_preview_command == null:
		text = "未绑定指令"
		return
	text = editor_preview_command.command_name
	disabled = true
	tooltip_text = "编辑器预览：未选择区域，指令不可用"

# ============================================================
# 状态更新
# ============================================================

## 按外部指令系统计算结果更新按钮可用状态和提示
func set_availability(is_available: bool, reason: String, cost_text: String) -> void:
	if command_data == null:
		return

	if not is_available:
		disabled = true
		tooltip_text = reason
		return

	disabled = false
	tooltip_text = cost_text

# ============================================================
# 点击响应
# ============================================================

func _pressed() -> void:
	if Engine.is_editor_hint():
		return
	if command_data != null and not disabled:
		command_pressed.emit(command_data)

# ============================================================
# 配置函数
# ============================================================

## 设置指令数据（创建时调用）
func setup(cmd: CommandData) -> void:
	command_data = cmd
	text = cmd.command_name
	_apply_terminal_style()


## 统一指令按钮为细边框系统操作样式
func _apply_terminal_style() -> void:
	custom_minimum_size = Vector2(118, 32)
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	add_theme_color_override("font_hover_color", Color("#d7e5ec"))
	add_theme_color_override("font_disabled_color", Color(0.32, 0.38, 0.42, 1.0))
	add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(
			Color(0.022, 0.050, 0.066, 0.94),
			MOSS_THEME.BORDER
		)
	)
	add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(
			Color(0.040, 0.090, 0.108, 0.98),
			MOSS_THEME.ACCENT_CYAN
		)
	)
	add_theme_stylebox_override(
		"pressed",
		MOSS_THEME.button_style(
			Color(0.015, 0.038, 0.050, 1.0),
			MOSS_THEME.ACCENT_CYAN
		)
	)
	add_theme_stylebox_override(
		"disabled",
		MOSS_THEME.button_style(
			Color(0.018, 0.028, 0.035, 0.82),
			Color(0.12, 0.16, 0.18, 1.0)
		)
	)
