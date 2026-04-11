extends PanelContainer

# 信号：当玩家点击某个选项按钮时发出，携带选项的索引 (0 或 1)
signal option_selected(index)

func _ready():
	# 游戏开始时默认隐藏弹窗
	hide()

# --- 公共函数：显示事件 ---
# 外部调用此函数来弹出一个具体的事件
func popup_event(event:GameEvent,current_energy:int):
	# 设置界面文本
	%EventTitle.text = event.event_title
	%RichTextLabel.text = event.event_description
	
	# 1. 清理上一轮事件的按钮
	for child in %OptionList.get_children():
		child.queue_free()
		
	# 2.根据当前事件的数据，动态添加新按钮
	for i in range(event.options.size()):
		var opt = event.options[i]
		if opt.energy_cost <= current_energy:
			add_custom_button(opt.button_text,i)
		else:add_custom_button(opt.button_text,-1)
		
	# 显示窗口
	show()

# --- 内部辅助：动态生成按钮 ---
func add_custom_button(text_content:String,index:int):
	var new_button = Button.new()
	new_button.text = text_content
	new_button.alignment = HORIZONTAL_ALIGNMENT_LEFT # 文字左对齐
	
	if index == -1:
			new_button.disabled = true
	# 将按钮添加到布局容器中
	%OptionList.add_child(new_button)
	
	# 连接点击信号，使用 bind(index) 将按钮编号传递给回调函数
	new_button.pressed.connect(_on_new_button_pressed.bind(index))
	

# 按钮点击回调
func _on_new_button_pressed(index):
	# 发出信号通知 MainOS 玩家选了哪个
	option_selected.emit(index)
	# 关闭弹窗
	hide()
