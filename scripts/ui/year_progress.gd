## 日期进度条组件
## 显示 2044.01→2075.01 的游戏进程
class_name YearProgress
extends Control

# ============================================================
# 常量
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const START_YEAR: int = 2044
const START_MONTH: int = 1
const END_YEAR: int = 2075
const END_MONTH: int = 1

# ============================================================
# 节点引用
# ============================================================

@onready var start_label: Label = $HBoxContainer/StartLabel
@onready var current_label: Label = $HBoxContainer/CurrentLabel
@onready var end_label: Label = $HBoxContainer/EndLabel
@onready var progress_bar: ProgressBar = $HBoxContainer/ProgressBar
@onready var stage_label: Label = $HBoxContainer/StageLabel

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	stage_label.text = "年度阶段"
	start_label.text = str(START_YEAR)
	end_label.text = str(END_YEAR)
	progress_bar.min_value = 0
	progress_bar.max_value = _month_index(END_YEAR, END_MONTH)
	progress_bar.value = 0
	current_label.text = str(START_YEAR)
	tooltip_text = "%04d.%02d" % [START_YEAR, START_MONTH]

	# 设置进度条样式
	_setup_progress_bar_style()

# ============================================================
# 公共方法
# ============================================================

## 更新进度条显示
## 参数: current_year/current_month - 当前日期（2044.01-2075.01）
func update_progress(current_year: int, current_month: int) -> void:
	progress_bar.value = clampi(
		_month_index(current_year, current_month),
		int(progress_bar.min_value),
		int(progress_bar.max_value)
	)
	current_label.text = str(current_year)
	tooltip_text = "%04d.%02d" % [current_year, current_month]
	progress_bar.tooltip_text = "当前日期：%04d.%02d" % [current_year, current_month]

# ============================================================
# 私有方法
# ============================================================

## 设置进度条的自定义样式
## 使用低饱和青蓝细条，与全局终端主题一致
func _setup_progress_bar_style() -> void:
	progress_bar.add_theme_stylebox_override(
		"background",
		MOSS_THEME.progress_background_style()
	)
	progress_bar.add_theme_stylebox_override(
		"fill",
		MOSS_THEME.progress_fill_style(Color(0.22, 0.48, 0.58, 1.0))
	)
	start_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	current_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	end_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	stage_label.add_theme_color_override("font_color", MOSS_THEME.ACCENT_GOLD)


## 计算从起始年月开始的月份偏移
func _month_index(year: int, month: int) -> int:
	return (year - START_YEAR) * 12 + (month - START_MONTH)
