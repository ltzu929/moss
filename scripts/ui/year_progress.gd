## 年份进度条组件
## 显示 2044→2075 的游戏进程
class_name YearProgress
extends Control

# ============================================================
# 区域一：节点引用
# ============================================================

@onready var start_label: Label = $HBoxContainer/StartLabel
@onready var end_label: Label = $HBoxContainer/EndLabel
@onready var progress_bar: ProgressBar = $HBoxContainer/ProgressBar

# ============================================================
# 区域二：常量
# ============================================================

const START_YEAR: int = 2044
const END_YEAR: int = 2075

# ============================================================
# 区域三：生命周期
# ============================================================

func _ready() -> void:
	start_label.text = str(START_YEAR)
	end_label.text = str(END_YEAR)
	progress_bar.min_value = 0
	progress_bar.max_value = END_YEAR - START_YEAR
	progress_bar.value = 0

# ============================================================
# 区域四：公共方法
# ============================================================

## 更新进度条显示
## 参数: current_year - 当前年份（2044-2075）
func update_progress(current_year: int) -> void:
	progress_bar.value = current_year - START_YEAR