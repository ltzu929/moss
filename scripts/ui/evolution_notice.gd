class_name EvolutionNotice
extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

## 通知确认信号
signal notice_confirmed()

# ============================================================
# 区域二：生命周期函数
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 区域三：公共函数
# ============================================================

## 显示进化通知
## 参数: unlocked_names - 已解锁的能力名称列表
func show_notice(unlocked_names: Array[String]) -> void:
	$VBoxContainer/NoticeTitle.text = "进化解锁！"
	var desc := "以下能力已激活：\n"
	for n in unlocked_names:
		desc += "• " + n + "\n"
	$VBoxContainer/NoticeDesc.text = desc
	show()

# ============================================================
# 区域四：回调函数
# ============================================================

## 确认按钮点击回调
func _on_confirm_pressed() -> void:
	notice_confirmed.emit()
	hide()