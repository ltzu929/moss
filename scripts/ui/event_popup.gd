extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

## 选项选中信号，携带选项索引
signal option_selected(index: int)

# ============================================================
# 区域二：生命周期函数
# ============================================================

func _ready() -> void:
	# 游戏开始时默认隐藏弹窗
	hide()

# ============================================================
# 区域三：公共函数
# ============================================================

## 显示事件弹窗
## 参数: event - 事件数据
##       current_energy - 当前能源值
func popup_event(event: GameEvent, current_energy: int) -> void:
	# 设置界面文本
	%EventTitle.text = event.event_title
	%RichTextLabel.text = event.event_description

	# 清理上一轮事件的按钮
	for child in %OptionList.get_children():
		child.queue_free()

	# 根据当前事件的数据，动态添加新按钮
	for i in range(event.options.size()):
		var opt := event.options[i]
		var region := event.event_region
		if opt.energy_cost <= current_energy:
			add_custom_button(opt, region, i)
		else:
			add_custom_button(opt, region, -1)

	# 显示窗口
	show()

# ============================================================
# 区域四：内部辅助函数
# ============================================================

## 动态生成选项按钮
## 参数: opt - 事件选项数据
##       region - 受影响的板块名称
##       index - 选项索引，-1表示不可用
func add_custom_button(opt: EventOption, region: String, index: int) -> void:
	var new_button := Button.new()
	new_button.text = opt.button_text
	new_button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# 构建tooltip文本，显示消耗和收益
	var tooltip_parts: Array[String] = []

	# 显示受影响的板块
	tooltip_parts.append("【影响板块：%s】" % region)

	if opt.order_delta != 0:
		var prefix := "+" if opt.order_delta > 0 else ""
		tooltip_parts.append("秩序 %s%d" % [prefix, opt.order_delta])

	if opt.hope_delta != 0:
		var prefix := "+" if opt.hope_delta > 0 else ""
		tooltip_parts.append("希望 %s%d" % [prefix, opt.hope_delta])

	if opt.energy_cost > 0:
		tooltip_parts.append("消耗能源 %d" % opt.energy_cost)

	new_button.tooltip_text = "\n".join(tooltip_parts)

	# 能源不足时禁用按钮并修改tooltip
	if index == -1:
		new_button.disabled = true
		new_button.tooltip_text = "能源不足（需要%d）" % opt.energy_cost

	# 将按钮添加到布局容器中
	%OptionList.add_child(new_button)

	# 连接点击信号，使用 bind(index) 将按钮编号传递给回调函数
	new_button.pressed.connect(_on_new_button_pressed.bind(index))

# ============================================================
# 区域五：回调函数
# ============================================================

## 按钮点击回调
## 参数: index - 选项索引
func _on_new_button_pressed(index: int) -> void:
	# 发出信号通知 MainOS 玩家选了哪个
	option_selected.emit(index)
	# 关闭弹窗
	hide()