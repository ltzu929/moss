extends Control

# --- 核心数据 ---
# 存储所有加载进来的事件资源 (GameEvent)
@export var all_events:Array[GameEvent]

# 当前游戏年份，游戏的主要时间推进变量
var current_year = 2044
var current_cpu = 100
var current_energy = 100

func _ready() :
	# 初始化：先清空列表，防止残留
	all_events.clear()
	# 从硬盘目录动态加载所有事件文件
	load_events_from_disk()

# --- 功能函数 ---
# 遍历 res://data/events/ 文件夹，自动读取所有 .tres 事件文件
func load_events_from_disk():
	var path = "res://data/events/"
	var dir = DirAccess.open(path)
	
	# 如果目录打开成功
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		# 遍历目录下的所有文件
		while file_name != "":
			# 只加载非文件夹且后缀为 .tres 的资源文件
			if !dir.current_is_dir() and file_name.ends_with(".tres"):
				var event = load(path + file_name)
				# 安全检查：确保加载的确实是 GameEvent 类型
				if event is GameEvent:
					all_events.append(event)
					# print("加载事件: " + file_name) # 调试用

			file_name = dir.get_next()

# --- 计时器回调 ---
# 负责时间的推进和事件的触发检查
func _on_timer_timeout():
	# 1. 年份增加
	current_year += 1
	current_energy += 10
	update_global_resoursce_ui()
	
	
	# 2. 检查是否有事件在今年触发
	for i in all_events:
		if i.event_time == current_year:
			# 如果触发事件，先暂停计时器，避免时间继续流逝
			$Timer.stop()
			
			# 3. 呼叫弹窗显示事件内容
			%EventPopup.popup_event(i,current_energy)
			
			# 4. 等待玩家做出选择 (await 会挂起当前函数，直到信号触发)
			var choice_index = await %EventPopup.option_selected
			var selected_opt = i.options[choice_index]
			
			apply_consequences(
				i.event_region,
				selected_opt.hope_delta,
				selected_opt.order_delta,
				selected_opt.energy_cost
			)
			
			# 玩家选择完毕，恢复时间流动
			$Timer.start()

# 修改函数
# 参数：目标名字，秩序变化量，希望变化量
func apply_consequences(event_name: String, order_delta: int, hope_delta: int, energy_cost: int):
	var sectors = %SectorInfoContainer.get_children()
	var found = false
	
	# 2. 挨个检查
	for sector in sectors:
		# 确保它真的是一个 SectorInfo 面板 (防止有别的东西混进来)
		if sector.get("data_card") != null:
			# 3. 比对名字
			if sector.data_card.region_name == event_name:
				print("找到目标区域：", event_name, " 执行修改！")
				
				# 4. 修改数据
				sector.data_card.order += order_delta
				sector.data_card.hope += hope_delta
				current_energy -= energy_cost
				
				# 5. 关键一步：数据改了，界面不会自动变！要通知面板刷新
				sector.update_display()
				update_global_resoursce_ui()
				
				found = true
				break # 找到了
	
	if not found:
		print("错误：找不到名为 ", event_name, " 的区域！")

func update_global_resoursce_ui():
	# 刷新年份
	%YearLabel.text = "年份: " + str(current_year)
	
	# 刷新能源 (顺便防止它显示负数，虽然逻辑上可能是负的)
	%EnergyLabel.text = "能源: " + str(current_energy)
