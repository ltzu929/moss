## MOSS状态面板组件
## 右侧固定面板，显示MOSS核心状态
class_name MossStatusPanel
extends Panel

# ============================================================
# 区域一：信号
# ============================================================

## 点击"查看详情"按钮时发出
signal details_requested

# ============================================================
# 区域二：常量
# ============================================================

# ============================================================
# 区域三：节点引用
# ============================================================

@onready var level_label: Label = $VBoxContainer/LevelLabel
@onready var authority_label: Label = $VBoxContainer/AuthorityLabel
@onready var details_button: Button = $VBoxContainer/DetailsButton

# ============================================================
# 区域四：生命周期
# ============================================================

func _ready() -> void:
	details_button.pressed.connect(_on_details_pressed)

# ============================================================
# 区域五：公共方法
# ============================================================

## 更新显示内容
## 参数: level - 进化等级（1-3）
## 参数: authority_percent - 平均控制权百分比
func update_display(level: int, authority_percent: int) -> void:
	level_label.text = "Lv." + str(level)
	authority_label.text = "控制权: " + str(authority_percent) + "%"

# ============================================================
# 区域六：私有方法/回调
# ============================================================

func _on_details_pressed() -> void:
	details_requested.emit()