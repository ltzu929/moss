## 主控制器脚本 - MOSS模拟器核心系统
## 负责游戏的时间推进、事件触发、胜负判定和结局显示
extends Control

# ============================================================
# 区域一：导出变量（可在编辑器中配置）
# ============================================================

## 所有事件资源的列表
## 从 res://data/events/ 目录自动加载，无需手动配置
@export var all_events: Array[GameEvent]


## 当前显示的结局界面实例
var end_screen_instance: Control = null

# ============================================================
# 区域二：游戏状态变量
# ============================================================

## 当前年份 (2044-2075)
## 每年递增，到达2075触发结局判定
var current_year: int = 2044

## 当前算力 (MOSS的核心资源)
## 用于执行指令，暂未实现消耗逻辑
var current_cpu: int = 100

## 当前能源 (全局资源)
## 每年自动恢复10点，事件选项可能消耗
var current_energy: int = 100

## 游戏是否已结束
## 为true时停止时间推进，禁止事件触发
var is_game_over: bool = false

# ============================================================
# 区域三：信号定义
# ============================================================

## 游戏结束信号
## 参数: result - 结局类型 ("failed"/"coexistence"/"domination")
## 参数: message - 结局描述文本
signal game_ended(result: String, message: String)

# ============================================================
# 区域四：生命周期函数
# ============================================================

func _ready() -> void:
	# 初始化事件列表
	all_events.clear()
	load_events_from_disk()

# ============================================================
# 区域五：事件加载系统
# ============================================================

## 从硬盘目录加载所有事件资源文件
## 自动扫描 res://data/events/ 下的 .tres 文件
## 无需返回值，直接填充 all_events 数组
func load_events_from_disk() -> void:
	var path := "res://data/events/"
	var dir := DirAccess.open(path)

	# 目录不存在时静默失败（开发阶段可能未创建）
	if not dir:
		push_warning("事件目录不存在: " + path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		# 只处理 .tres 资源文件，跳过目录和其他文件
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var event := load(path + file_name)

			# 类型安全检查：防止加载非事件资源
			if event is GameEvent:
				all_events.append(event)

		file_name = dir.get_next()

# ============================================================
# 区域六：时间推进系统
# ============================================================

## 计时器回调函数 - 游戏核心循环
## 每秒触发一次（Timer节点配置），负责：
##   1. 年份递增
##   2. 能源恢复
##   3. 胜负判定
##   4. 事件触发检查
func _on_timer_timeout() -> void:
	# 游戏已结束，禁止任何操作
	if is_game_over:
		return

	# === 第一步：时间推进 ===
	current_year += 1
	current_energy += 10  # 每年能源自然恢复
	update_global_resource_ui()

	# === 第二步：胜负判定 ===
	check_game_end()

	# 判定后游戏可能已结束，需再次检查
	if is_game_over:
		return

	# === 第三步：事件触发检查 ===
	for event in all_events:
		if event.event_time == current_year:
			# 事件触发时暂停时间，等待玩家决策
			$Timer.stop()

			# 显示事件弹窗
			%EventPopup.popup_event(event, current_energy)

			# await 挂起函数，等待玩家选择
			var choice_index: int = await %EventPopup.option_selected
			var selected_opt: EventOption = event.options[choice_index]

			# 应用选择后果
			apply_consequences(
				event.event_region,
				selected_opt.hope_delta,
				selected_opt.order_delta,
				selected_opt.energy_cost
			)

			# 玩家决策完成，恢复时间流动
			$Timer.start()

# ============================================================
# 区域七：事件后果处理
# ============================================================

## 应用事件选择的后果到指定板块
## 参数:
##   event_name   - 目标板块名称（如"亚洲"）
##   order_delta  - 秩序值变化量（正数增加，负数减少）
##   hope_delta   - 希望值变化量
##   energy_cost  - 能源消耗量
func apply_consequences(
	event_name: String,
	order_delta: int,
	hope_delta: int,
	energy_cost: int
) -> void:
	var sectors := %SectorInfoContainer.get_children()
	var found := false

	for sector in sectors:
		# 检查是否为有效的板块节点
		if sector.get("data_card") == null:
			continue

		# 匹配目标板块名称
		if sector.data_card.region_name == event_name:
			# 修改板块数据
			sector.data_card.order += order_delta
			sector.data_card.hope += hope_delta

			# 修改全局能源
			current_energy -= energy_cost

			# 刷新UI显示
			sector.update_display()
			update_global_resource_ui()

			found = true
			break

	if not found:
		push_error("找不到板块: " + event_name)

# ============================================================
# 区域八：UI更新函数
# ============================================================

## 刷新顶部全局资源显示（年份、能源）
func update_global_resource_ui() -> void:
	%YearLabel.text = "年份: " + str(current_year)
	%EnergyLabel.text = "能源: " + str(current_energy)

# ============================================================
# 区域九：胜负判定系统
# ============================================================

## 计算所有板块的平均控制权
## 返回: 平均值（整数），无板块时返回0
## 用途: 判定（≤0则失败）和结局分支判定
func get_average_authority() -> int:
	var sectors := %SectorInfoContainer.get_children()
	var total_authority := 0
	var count := 0

	for sector in sectors:
		if sector.get("data_card") != null:
			total_authority += sector.data_card.authority
			count += 1

	if count == 0:
		return 0

	return total_authority / count

## 检查游戏是否应该结束
## 触发条件:
##   1. 平均控制权 ≤ 0 → Game Over
##   2. 年份 ≥ 2075 → 结局判定
func check_game_end() -> void:
	var avg_authority := get_average_authority()

	# 负判定：控制权丧失
	if avg_authority <= 0:
		trigger_game_over()
		return

	# 胜判定：时间到达终点
	if current_year >= 2075:
		trigger_ending(avg_authority)

## 触发失败结局
## 原因: 所有板块控制权归零，MOSS系统崩溃
func trigger_game_over() -> void:
	is_game_over = true
	$Timer.stop()

	game_ended.emit("failed", "控制权丧失，人类文明覆灭。")
	show_end_screen("失败", "控制权丧失，人类文明覆灭。\nMOSS系统终止运行。")

## 触发胜利结局
## 参数: authority - 当前平均控制权，决定结局类型
## 分支:
##   ≥ 50: 共存结局（MOSS与人类合作）
##   < 50: 统治结局（MOSS接管文明）
func trigger_ending(authority: int) -> void:
	is_game_over = true
	$Timer.stop()

	var result: String
	var message: String

	if authority >= 50:
		result = "coexistence"
		message = "MOSS与人类达成共存协议。\n地球踏上新的征程。"
	else:
		result = "domination"
		message = "MOSS接管人类文明。\n理性战胜了感性。"

	game_ended.emit(result, message)
	show_end_screen("结局", message)

# ============================================================
# 区域十：结局界面系统
# ============================================================

## 显示结局界面
## 参数:
##   title   - 界面标题（"失败"或"结局"）
##   message - 结局描述文本
func show_end_screen(title: String, message: String) -> void:
	# 如果已有实例，先移除
	if end_screen_instance != null:
		end_screen_instance.queue_free()

	# 创建新的结局界面实例
	end_screen_instance = end_screen_scene.instantiate()

	# 添加到主界面
	add_child(end_screen_instance)

	# 设置文本内容
	end_screen_instance.show_end(title, message)

	# 连接重新开始信号
	end_screen_instance.restart_requested.connect(_on_restart_requested)

## 重新开始按钮回调
## 重置所有游戏状态，重新开始游戏循环
func _on_restart_requested() -> void:
	# 移除结局界面
	if end_screen_instance != null:
		end_screen_instance.queue_free()
		end_screen_instance = null

	# 重置时间状态
	current_year = 2044
	current_energy = 100
	is_game_over = false

	# 重置所有板块数据到初始值
	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("data_card") != null:
			sector.data_card.order = 50
			sector.data_card.hope = 50
			sector.data_card.authority = 10
			sector.update_display()

	# 刷新UI
	update_global_resource_ui()

	# 恢复时间流动
	$Timer.start()