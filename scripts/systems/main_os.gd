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
# 区域三：进化系统状态
# ============================================================

## 当前进化等级 (1=初始, 2=进化, 3=终极)
var evolution_level: int = 1

## 已解锁的被动能力ID列表
var unlocked_passives: Array[String] = []

## 已购买解锁的指令ID列表
var unlocked_evolution_commands: Array[String] = []

## 算力上限（初始100，可通过进化突破到150）
var max_cpu: int = 100

## 算力恢复速率（初始5，可通过进化提升）
var cpu_recovery_rate: int = 5

## 冷却缩减值（初始0，可通过进化增加）
var cooldown_reduction: int = 0

## 所有进化能力数据（从磁盘加载）
var all_evolutions: Array[EvolutionData] = []

# ============================================================
# 区域四：指令系统状态
# ============================================================

## 当前选中的板块
var selected_sector: SectorInfo = null

## 各指令冷却剩余年数 {"算力分配": 0, "系统接管": 2}
var command_cooldowns: Dictionary = {}

## 可用指令列表（从磁盘加载）
var available_commands: Array[CommandData] = []

# ============================================================
# 区域五：信号定义
# ============================================================

## 游戏结束信号
## 参数: result - 结局类型 ("failed"/"coexistence"/"domination")
## 参数: message - 结局描述文本
signal game_ended(result: String, message: String)

# ============================================================
# 区域六：生命周期函数
# ============================================================

func _ready() -> void:
	# 初始化事件列表
	all_events.clear()
	load_events_from_disk()

	# 初始化指令列表
	available_commands.clear()
	load_commands_from_disk()

	# 初始化进化能力列表
	all_evolutions.clear()
	load_evolutions_from_disk()

	# 连接所有板块的点击信号
	connect_sector_signals()

	# 初始化指令按钮
	setup_command_buttons()

	# 连接进化弹窗信号
	if has_node("%EvolutionPopup"):
		var popup := get_node("%EvolutionPopup")
		if popup.get("purchase_requested") != null:
			popup.purchase_requested.connect(_on_purchase_requested)

# ============================================================
# 区域七：事件加载系统
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
# 区域八：指令加载系统
# ============================================================

## 从硬盘目录加载所有指令资源文件
## 自动扫描 res://data/commands/ 下的 .tres 文件
func load_commands_from_disk() -> void:
	var path := "res://data/commands/"
	var dir := DirAccess.open(path)

	if not dir:
		push_warning("指令目录不存在: " + path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var cmd := load(path + file_name)

			if cmd is CommandData:
				available_commands.append(cmd)
				# 初始化冷却状态为0
				command_cooldowns[cmd.command_name] = 0

		file_name = dir.get_next()

# ============================================================
# 区域九：进化能力加载系统
# ============================================================

## 从硬盘目录加载所有进化能力资源文件
## 自动扫描 res://data/evolution/ 下的 .tres 文件
func load_evolutions_from_disk() -> void:
	var path := "res://data/evolution/"
	var dir := DirAccess.open(path)

	if not dir:
		push_warning("进化能力目录不存在: " + path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var evolution := load(path + file_name)

			if evolution is EvolutionData:
				all_evolutions.append(evolution)

		file_name = dir.get_next()

## 每年检查进化能力自动解锁
## 遍历所有被动能力，检查是否满足解锁条件
func check_evolution_unlocks() -> void:
	var unlocked_any: bool = false
	var unlocked_names: Array[String] = []

	for evolution in all_evolutions:
		if not evolution.is_passive:
			continue

		if evolution.ability_id in unlocked_passives:
			continue

		if evolution.cpu_threshold > 0 and current_cpu < evolution.cpu_threshold:
			continue

		if evolution.authority_threshold > 0:
			var avg_auth := get_average_authority()
			if avg_auth < evolution.authority_threshold:
				continue

		unlocked_passives.append(evolution.ability_id)
		apply_evolution_effect(evolution)
		unlocked_any = true
		unlocked_names.append(evolution.ability_name)

	if unlocked_any:
		update_evolution_level()
		# TODO: 显示进化通知弹窗

## 应用进化能力效果
## 参数: evolution - 进化能力数据
func apply_evolution_effect(evolution: EvolutionData) -> void:
	if evolution.cooldown_reduction > 0:
		cooldown_reduction += evolution.cooldown_reduction

	if evolution.max_cpu_bonus > 0:
		max_cpu += evolution.max_cpu_bonus

	if evolution.recovery_bonus > 0:
		cpu_recovery_rate += evolution.recovery_bonus

## 更新进化等级
## 根据已解锁被动能力数量确定等级
func update_evolution_level() -> void:
	var passive_count := unlocked_passives.size()

	if passive_count >= 3:
		evolution_level = 3
	elif passive_count >= 1:
		evolution_level = 2
	else:
		evolution_level = 1

## 购买解锁进化指令
## 参数: evolution - 进化能力数据
## 返回: true表示购买成功
func purchase_evolution_command(evolution: EvolutionData) -> bool:
	if evolution.is_passive:
		return false

	if evolution.ability_id in unlocked_evolution_commands:
		return false

	if current_cpu < evolution.purchase_cpu_cost:
		return false

	if current_energy < evolution.purchase_energy_cost:
		return false

	current_cpu -= evolution.purchase_cpu_cost
	current_energy -= evolution.purchase_energy_cost

	unlocked_evolution_commands.append(evolution.ability_id)

	update_global_resource_ui()

	return true

## 获取进化进度（用于UI）
## 返回: 包含进度百分比和下一个解锁能力的字典
func get_evolution_progress() -> Dictionary:
	var result := {
		"cpu_progress": 0.0,
		"authority_progress": 0.0,
		"next_passive": null
	}

	for evolution in all_evolutions:
		if not evolution.is_passive:
			continue
		if evolution.ability_id in unlocked_passives:
			continue

		result["next_passive"] = evolution

		if evolution.cpu_threshold > 0:
			result["cpu_progress"] = float(current_cpu) / float(evolution.cpu_threshold)

		if evolution.authority_threshold > 0:
			var avg_auth := get_average_authority()
			result["authority_progress"] = float(avg_auth) / float(evolution.authority_threshold)

		break

	return result

# ============================================================
# 区域九点五：进化弹窗管理
# ============================================================

## 显示进化弹窗
func show_evolution_popup() -> void:
	$Timer.stop()
	%EvolutionPopup.all_evolutions_ref = all_evolutions
	%EvolutionPopup.unlocked_passives_ref = unlocked_passives
	%EvolutionPopup.unlocked_commands_ref = unlocked_evolution_commands
	%EvolutionPopup.show_popup(evolution_level, current_cpu, current_energy)
	await %EvolutionPopup.popup_closed
	$Timer.start()

## 更新进化按钮显示
func update_evolution_button() -> void:
	if has_node("%EvolutionButton"):
		var btn := get_node("%EvolutionButton")
		if btn is Button:
			btn.text = "Lv." + str(evolution_level)

## 进化按钮点击回调
func _on_evolution_button_pressed() -> void:
	show_evolution_popup()

## 购买请求回调
## 参数: evolution - 进化能力数据
func _on_purchase_requested(evolution: EvolutionData) -> void:
	if purchase_evolution_command(evolution):
		%EvolutionPopup.show_popup(evolution_level, current_cpu, current_energy)

# ============================================================
# 区域十：板块选中管理
# ============================================================

## 连接所有板块的点击信号
func connect_sector_signals() -> void:
	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("sector_clicked") != null:
			sector.sector_clicked.connect(_on_sector_clicked)

## 设置选中板块
## 参数: sector - 被点击的板块节点
func select_sector(sector: SectorInfo) -> void:
	# 取消之前的选中
	if selected_sector != null:
		selected_sector.set_selected(false)

	# 设置新选中
	selected_sector = sector
	selected_sector.set_selected(true)

## 取消选中状态
func deselect_sector() -> void:
	if selected_sector != null:
		selected_sector.set_selected(false)
		selected_sector = null

## 板块点击回调 - 连接到SectorInfo的sector_clicked信号
## 实现toggle行为：点击已选中的板块取消选中，点击其他板块切换选中
func _on_sector_clicked(sector: SectorInfo) -> void:
	# 如果点击的是已选中的板块，取消选中
	if selected_sector == sector:
		deselect_sector()
		# 如果弹窗打开，更新显示为未选择状态
		if %AllocatePopup.visible:
			%AllocatePopup.update_display("未选择板块")
	else:
		# 选中新板块
		select_sector(sector)
		# 如果弹窗打开，实时更新板块名称
		if %AllocatePopup.visible:
			%AllocatePopup.update_display(sector.data_card.region_name)

# ============================================================
# 区域十：冷却系统
# ============================================================

## 每年更新冷却状态
## 减少所有指令的冷却计数（最小为0）
func update_cooldowns() -> void:
	for cmd_name in command_cooldowns.keys():
		if command_cooldowns[cmd_name] > 0:
			command_cooldowns[cmd_name] -= 1

## 检查指令是否可用（冷却、资源、选中状态）
## 参数: cmd - 指令数据
## 返回: true表示可执行
func is_command_available(cmd: CommandData) -> bool:
	# 检查选中状态
	if selected_sector == null:
		return false

	# 检查冷却
	if command_cooldowns.get(cmd.command_name, 0) > 0:
		return false

	# 检查算力
	if current_cpu < cmd.cpu_cost:
		return false

	# 检查能源
	if current_energy < cmd.energy_cost:
		return false

	return true

## 获取指令不可用的原因（用于tooltip）
## 参数: cmd - 指令数据
## 返回: 不可用原因字符串，可用时返回空字符串
func get_command_unavailable_reason(cmd: CommandData) -> String:
	if selected_sector == null:
		return "请先选择板块"

	var cooldown: int = command_cooldowns.get(cmd.command_name, 0)
	if cooldown > 0:
		return "冷却中（剩余%d年）" % cooldown

	if current_cpu < cmd.cpu_cost:
		return "算力不足（需要%d）" % cmd.cpu_cost

	if current_energy < cmd.energy_cost:
		return "能源不足（需要%d）" % cmd.energy_cost

	return ""

# ============================================================
# 区域十一：时间推进系统
# ============================================================

## 计时器回调函数 - 游戏核心循环
## 每秒触发一次（Timer节点配置），负责：
##   1. 年份递增
##   2. 能源恢复
##   3. 事件触发检查
##   4. 时间推进
##   5. 胜负判定
func _on_timer_timeout() -> void:
	# 游戏已结束，禁止任何操作
	if is_game_over:
		return

	# === 第一步：事件触发检查 ===
	# 先检查当前年份的事件，再推进时间
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

	# === 第二步：时间推进 ===
	current_year += 1
	current_energy += 10  # 每年能源自然恢复
	current_cpu += cpu_recovery_rate      # 每年算力恢复
	current_cpu = mini(current_cpu, max_cpu)  # 算力上限（可通过进化提升）
	update_cooldowns()    # 更新指令冷却
	check_evolution_unlocks()  # 检查进化解锁
	update_global_resource_ui()
	update_command_buttons()  # 更新指令按钮状态

	# === 第三步：胜负判定 ===
	check_game_end()

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

## 刷新顶部全局资源显示（年份、算力、能源）
func update_global_resource_ui() -> void:
	%YearLabel.text = "年份: " + str(current_year)
	%ComputationalLabel.text = "算力: " + str(current_cpu)
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

	# 返回整数平均值，向下取整
	return int(total_authority / count)

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

	# 加载结局场景并创建实例
	var end_screen_scene := load("res://scenes/game_over.tscn")
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
	current_cpu = 100
	is_game_over = false

	# 重置进化状态
	evolution_level = 1
	unlocked_passives.clear()
	unlocked_evolution_commands.clear()
	max_cpu = 100
	cpu_recovery_rate = 5
	cooldown_reduction = 0
	update_evolution_button()

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

# ============================================================
# 区域十一：指令执行系统
# ============================================================

## 执行指令
## 参数: cmd - 指令数据
## 返回: true表示执行成功
func execute_command(cmd: CommandData) -> bool:
	if not is_command_available(cmd):
		return false

	# 消耗资源
	current_cpu -= cmd.cpu_cost
	current_energy -= cmd.energy_cost

	# 启动冷却
	command_cooldowns[cmd.command_name] = cmd.cooldown_years

	# 刷新资源UI
	update_global_resource_ui()

	return true

## 应用指令效果到选中板块
## 参数: cmd - 指令数据
##       effect_type - 对于算力分配，"order"或"hope"
func apply_command_effect(cmd: CommandData, effect_type: String = "") -> void:
	if selected_sector == null:
		return

	# 应用效果
	if cmd.is_allocate_type:
		# 算力分配根据选择决定效果
		if effect_type == "order":
			selected_sector.data_card.order += cmd.order_delta
		elif effect_type == "hope":
			selected_sector.data_card.hope += cmd.hope_delta
	else:
		# 其他指令直接应用所有效果
		selected_sector.data_card.order += cmd.order_delta
		selected_sector.data_card.hope += cmd.hope_delta
		selected_sector.data_card.authority += cmd.authority_delta

	# 限制数值范围
	selected_sector.data_card.clamp_values()

	# 刷新板块显示
	selected_sector.update_display()

## 指令按钮点击回调
## 参数: cmd - 指令数据
func _on_command_button_pressed(cmd: CommandData) -> void:
	if not is_command_available(cmd):
		return

	if cmd.is_allocate_type:
		# 算力分配需要弹出选择窗口
		$Timer.stop()
		%AllocatePopup.popup_allocate(cmd, selected_sector.data_card.region_name)
		var choice: String = await %AllocatePopup.choice_selected
		if choice != "":
			execute_command(cmd)
			apply_command_effect(cmd, choice)
		$Timer.start()
	else:
		# 其他指令直接执行
		execute_command(cmd)
		apply_command_effect(cmd)

# ============================================================
# 区域十二：指令按钮管理
# ============================================================

## 初始化指令按钮容器中的所有按钮
func setup_command_buttons() -> void:
	var button_container: HBoxContainer = %CommandButtonContainer

	if button_container == null:
		push_error("找不到CommandButtonContainer")
		return

	# 清空现有按钮
	for child in button_container.get_children():
		child.queue_free()

	# 为每个指令创建按钮
	for cmd in available_commands:
		var button_scene := load("res://scenes/command_button.tscn")
		var button: Button = button_scene.instantiate()

		# 配置按钮
		button.setup(cmd)
		button.cooldowns_ref = command_cooldowns

		# 连接点击信号
		button.command_pressed.connect(_on_command_button_pressed)

		# 添加到容器
		button_container.add_child(button)

## 更新所有指令按钮状态
func update_command_buttons() -> void:
	var button_container: HBoxContainer = %CommandButtonContainer

	if button_container == null:
		return

	for button in button_container.get_children():
		if button.get("update_state") != null:
			# 更新按钮的状态变量
			button.current_cpu = current_cpu
			button.current_energy = current_energy
			button.has_selected_sector = (selected_sector != null)
			button.update_state()