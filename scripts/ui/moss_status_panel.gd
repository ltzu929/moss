## MOSS状态面板组件
## 右侧固定面板，显示MOSS核心状态
class_name MossStatusPanel
extends Panel

# ============================================================
# 信号
# ============================================================

## 点击"查看详情"按钮时发出
signal details_requested

# ============================================================
# 常量
# ============================================================

# ============================================================
# 节点引用
# ============================================================

@onready var level_label: Label = $VBoxContainer/LevelLabel
@onready var authority_label: Label = $VBoxContainer/AuthorityLabel
@onready var details_button: Button = $VBoxContainer/DetailsButton

# ============================================================
# 生命周期
# ============================================================

## 连接详情按钮点击信号
func _ready() -> void:
	details_button.pressed.connect(_on_details_pressed)

# ============================================================
# 公共方法
# ============================================================

## 更新显示内容
## 参数: level - 科技阶段（1-3）
## 参数: authority_percent - 平均控制权百分比
func update_display(level: int, authority_percent: int) -> void:
	level_label.text = "Lv." + str(level)
	authority_label.text = "控制权: " + str(authority_percent) + "%"

# ============================================================
# 私有方法/回调
# ============================================================

## 转发详情按钮点击事件
func _on_details_pressed() -> void:
	details_requested.emit()
