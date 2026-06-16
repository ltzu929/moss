## 年份进度条组件
## 显示 2044→2075 的游戏进程
class_name YearProgress
extends Control

# ============================================================
# 常量
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const START_YEAR: int = 2044
const END_YEAR: int = 2075

# ============================================================
# 节点引用
# ============================================================

@onready var start_label: Label = $HBoxContainer/StartLabel
@onready var end_label: Label = $HBoxContainer/EndLabel
@onready var progress_bar: ProgressBar = $HBoxContainer/ProgressBar

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	start_label.text = str(START_YEAR)
	end_label.text = str(END_YEAR)
	progress_bar.min_value = 0
	progress_bar.max_value = END_YEAR - START_YEAR
	progress_bar.value = 0

	# 设置进度条样式
	_setup_progress_bar_style()

# ============================================================
# 公共方法
# ============================================================

## 更新进度条显示
## 参数: current_year - 当前年份（2044-2075）
func update_progress(current_year: int) -> void:
	progress_bar.value = current_year - START_YEAR

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
	end_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
