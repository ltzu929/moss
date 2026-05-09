## 年份进度条组件
## 显示 2044→2075 的游戏进程
class_name YearProgress
extends Control

# ============================================================
# 常量
# ============================================================

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
## 填充颜色: #4488ff (蓝色)
## 背景颜色: #333333 (深灰色)
func _setup_progress_bar_style() -> void:
	# 创建背景样式
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("#333333")
	bg_style.set_corner_radius_all(4)

	# 创建填充样式
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color("#4488ff")
	fill_style.set_corner_radius_all(4)

	# 应用样式到进度条
	progress_bar.add_theme_stylebox_override("background", bg_style)
	progress_bar.add_theme_stylebox_override("fill", fill_style)