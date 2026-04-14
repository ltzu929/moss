## 算力分配选择弹窗 - 让玩家选择提升秩序或希望
class_name AllocatePopup
extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

## 玩家选择后发出，"order"表示秩序，"hope"表示希望，空字符串表示取消
signal choice_selected(choice: String)

# ============================================================
# 区域二：生命周期函数
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 区域三：弹窗显示
# ============================================================

## 显示算力分配选择弹窗
## 参数: cmd - 指令数据
##       region_name - 目标板块名称
func popup_allocate(cmd: CommandData, region_name: String) -> void:
	%AllocateTitle.text = "算力分配 - " + region_name
	%AllocateDesc.text = cmd.description + "\n请选择要提升的属性："

	%OrderButton.text = "提升秩序 (+%d)" % cmd.order_delta
	%HopeButton.text = "提升希望 (+%d)" % cmd.hope_delta

	show()

# ============================================================
# 区域四：按钮回调
# ============================================================

func _on_order_button_pressed() -> void:
	choice_selected.emit("order")
	hide()

func _on_hope_button_pressed() -> void:
	choice_selected.emit("hope")
	hide()

func _on_cancel_button_pressed() -> void:
	choice_selected.emit("")
	hide()