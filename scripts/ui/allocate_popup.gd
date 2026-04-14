## 算力分配选择弹窗 - 让玩家选择提升秩序或希望
class_name AllocatePopup
extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

## 玩家选择后发出，"order"表示秩序，"hope"表示希望，空字符串表示取消
signal choice_selected(choice: String)

# ============================================================
# 区域二：状态变量
# ============================================================

## 当前指令数据（用于实时更新）
var current_cmd: CommandData = null

# ============================================================
# 区域三：生命周期函数
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 区域四：弹窗显示
# ============================================================

## 显示算力分配选择弹窗
## 参数: cmd - 指令数据
##       region_name - 目标板块名称
func popup_allocate(cmd: CommandData, region_name: String) -> void:
	current_cmd = cmd
	update_display(region_name)
	show()

## 更新弹窗显示内容（实时更新板块名称）
## 参数: region_name - 当前选中的板块名称，"未选择板块"时禁用按钮
func update_display(region_name: String) -> void:
	if current_cmd == null:
		return

	%AllocateTitle.text = "算力分配 - " + region_name
	%AllocateDesc.text = current_cmd.description + "\n请选择要提升的属性："

	%OrderButton.text = "提升秩序 (+%d)" % current_cmd.order_delta
	%HopeButton.text = "提升希望 (+%d)" % current_cmd.hope_delta
	%CancelButton.text = "取消"

	# 如果没有选中板块，禁用选择按钮（取消按钮始终可用）
	var has_selection: bool = (region_name != "未选择板块")
	%OrderButton.disabled = not has_selection
	%HopeButton.disabled = not has_selection
	%CancelButton.disabled = false  # 取消按钮始终可用

# ============================================================
# 区域五：按钮回调
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