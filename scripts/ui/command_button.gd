## 指令按钮组件 - 显示单个MOSS指令按钮
## 负责按钮状态更新和点击响应
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

# ============================================================
# 状态变量
# ============================================================

## 关联的指令数据
var command_data: CommandData = null

## 引用main_os的冷却字典（由main_os设置）
var cooldowns_ref: Dictionary = {}

## 当前算力值（由main_os设置）
var current_cpu: int = 0

## 当前能源值（由main_os设置）
var current_energy: int = 0

## 是否有选中板块（由main_os设置）
var has_selected_sector: bool = false

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	_apply_terminal_style()
	if command_data != null:
		text = command_data.command_name
		update_state()

# ============================================================
# 状态更新
# ============================================================

## 更新按钮可用状态和tooltip
func update_state() -> void:
	if command_data == null:
		return

	# 检查选中状态
	if not has_selected_sector:
		disabled = true
		tooltip_text = "请先选择板块"
		return

	# 检查冷却
	var cooldown: int = cooldowns_ref.get(command_data.command_id, 0)
	if cooldown > 0:
		disabled = true
		tooltip_text = "冷却中（剩余%d年）" % cooldown
		return

	# 检查算力
	if current_cpu < command_data.cpu_cost:
		disabled = true
		tooltip_text = "算力不足（需要%d）" % command_data.cpu_cost
		return

	# 检查能源
	if current_energy < command_data.energy_cost:
		disabled = true
		tooltip_text = "能源不足（需要%d）" % command_data.energy_cost
		return

	# 可用状态
	disabled = false
	if command_data.energy_cost > 0:
		tooltip_text = "消耗: %d算力 %d能源" % [command_data.cpu_cost, command_data.energy_cost]
	else:
		tooltip_text = "消耗: %d算力" % command_data.cpu_cost

# ============================================================
# 点击响应
# ============================================================

func _pressed() -> void:
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
