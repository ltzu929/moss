## 主控制器脚本 - MOSS模拟器核心系统
## 负责游戏的时间推进、事件触发、胜负判定和结局显示
extends Control

# ============================================================
# 导出变量（可在编辑器中配置）
# ============================================================

## 所有事件资源的列表
## 从 res://data/events/ 目录自动加载，无需手动配置
@export var all_events: Array[GameEvent]


## 当前显示的结局界面实例
var end_screen_instance: Control = null

## 打字机动画队列
var _typewriter_queue: Array[Dictionary] = []
var _typewriter_active: bool = false

## 游戏初始常量
const INITIAL_YEAR: int = 2044
const INITIAL_CPU: int = 30
const INITIAL_ENERGY: int = 100
const INITIAL_MAX_CPU: int = 100
const INITIAL_CPU_RECOVERY_RATE: int = 10
const END_YEAR: int = 2075

## 进化指令名称
const COMMAND_ENERGY_CONVERT: String = "能源转换"
const COMMAND_GLOBAL_TAKEOVER: String = "全局接管"
const COMMAND_CRISIS_PREDICT: String = "危机预测"
const ACTION_LOG_LIMIT: int = 24

# ============================================================
# 游戏状态变量
# ============================================================

## 当前年份 (2044-2075)
## 每年递增，到达2075先触发终局事件，再结算结局
var current_year: int = 2044

## 当前算力 (MOSS的核心资源)
## 用于执行指令，初始30，每年恢复10
var current_cpu: int = 30

## 当前能源 (全局资源)
## 每年自动恢复10点，事件选项可能消耗
var current_energy: int = 100

## 游戏是否已结束
## 为true时停止时间推进，禁止事件触发
var is_game_over: bool = false

# ============================================================
# 进化系统状态
# ============================================================

## 当前进化等级 (1=初始, 2=进化, 3=终极)
var evolution_level: int = 1

## 已解锁的被动能力ID列表
var unlocked_passives: Array[String] = []

## 已购买解锁的指令ID列表
var unlocked_evolution_commands: Array[String] = []

## 算力上限（初始100，可通过进化突破到150）
var max_cpu: int = 100

## 算力恢复速率（初始10，可通过进化提升）
var cpu_recovery_rate: int = 10

## 冷却缩减值（初始0，可通过进化增加）
var cooldown_reduction: int = 0

## 所有进化能力数据（从磁盘加载）
var all_evolutions: Array[EvolutionData] = []

# ============================================================
# 指令系统状态
# ============================================================

## 当前选中的板块
var selected_sector: SectorInfo = null

## 各指令冷却剩余年数 {"算力分配": 0, "系统接管": 2}
var command_cooldowns: Dictionary = {}

## 可用指令列表（从磁盘加载）
var available_commands: Array[CommandData] = []

## 板块初始状态快照（用于重新开始）
var initial_sector_states: Dictionary = {}
var action_log: Array[Dictionary] = []

## 已触发的事件ID列表（防止重复触发）
var triggered_events: Array[String] = []

# ============================================================
# 信号定义
# ============================================================

## 游戏结束信号
## 参数: result - 结局类型 ("failed"/"coexistence"/"domination")
## 参数: message - 结局描述文本
signal game_ended(result: String, message: String)

# ============================================================
# 生命周期函数
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
	cache_initial_sector_states()

	# 初始化指令按钮
	setup_command_buttons()

	# 连接进化弹窗信号
	if has_node("%EvolutionPopup"):
		var popup := get_node("%EvolutionPopup")
		if popup.get("purchase_requested") != null:
			popup.purchase_requested.connect(_on_purchase_requested)

	if has_node("%MossStatusPanel"):
		var moss_status_panel := get_node("%MossStatusPanel")
		if moss_status_panel is MossStatusPanel:
			moss_status_panel.details_requested.connect(_on_moss_details_requested)

	update_evolution_button()
	update_global_resource_ui()
	update_region_detail_ui()
	update_command_buttons()

func get_action_log() -> Array[Dictionary]:
	return action_log.duplicate(true)

func record_action(kind: String, title: String, message: String) -> void:
	var entry := {
		"year": current_year,
		"kind": kind,
		"title": title,
		"message": message
	}
	action_log.append(entry)

	while action_log.size() > ACTION_LOG_LIMIT:
		action_log.remove_at(0)

	# 更新日志UI
	_add_log_entry_to_ui(entry)

func append_signed_change(lines: Array[String], label: String, delta: int) -> void:
	if delta == 0:
		return

	var prefix := "+" if delta > 0 else ""
	lines.append("%s %s%d" % [label, prefix, delta])

func log_command_result(cmd: CommandData, lines: Array[String]) -> void:
	append_signed_change(lines, "算力", -cmd.cpu_cost)
	append_signed_change(lines, "能源", -cmd.energy_cost)

	var cooldown: int = command_cooldowns.get(cmd.command_name, 0)
	if cooldown > 0:
		lines.append("冷却 %d 年" % cooldown)

	record_action("command", cmd.command_name, "\n".join(lines))

# ============================================================
# 初始状态缓存
# ============================================================

## 缓存所有板块的初始数值，用于重新开始时恢复
func cache_initial_sector_states() -> void:
	initial_sector_states.clear()

	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("data_card") == null:
			continue

		initial_sector_states[sector.data_card.region_name] = {
			"order": sector.data_card.order,
			"hope": sector.data_card.hope,
			"authority": sector.data_card.authority,
			"population": sector.data_card.population,
			"is_locked": sector.data_card.is_locked
		}

## 恢复所有板块到初始数值
func restore_sector_states() -> void:
	var sectors := %SectorInfoContainer.get_children()

	for sector in sectors:
		if sector.get("data_card") == null:
			continue

		var state: Dictionary = initial_sector_states.get(sector.data_card.region_name, {})
		if state.is_empty():
			continue

		sector.data_card.order = state["order"]
		sector.data_card.hope = state["hope"]
		sector.data_card.authority = state["authority"]
		sector.data_card.population = state["population"]
		sector.data_card.is_locked = state["is_locked"]
		sector.update_display()

# ============================================================
# 事件加载系统
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
# 指令加载系统
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
# 进化能力加载系统
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
		update_evolution_button()
		# 显示进化通知弹窗
		$Timer.stop()
		%EvolutionNotice.show_notice(unlocked_names)
		await %EvolutionNotice.notice_confirmed
		$Timer.start()

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

	var unlocked_command := create_evolution_command(evolution)
	if unlocked_command != null and not has_command_named(unlocked_command.command_name):
		available_commands.append(unlocked_command)
		command_cooldowns[unlocked_command.command_name] = 0
		setup_command_buttons()
		update_command_buttons()

	var lines: Array[String] = ["解锁指令：%s" % evolution.unlocks_command_name]
	append_signed_change(lines, "算力", -evolution.purchase_cpu_cost)
	append_signed_change(lines, "能源", -evolution.purchase_energy_cost)
	record_action("evolution", "进化解锁", "\n".join(lines))

	update_global_resource_ui()

	return true

## 根据进化数据创建对应的运行时指令
## 参数: evolution - 进化能力数据
## 返回: 创建成功时返回指令数据，失败时返回null
func create_evolution_command(evolution: EvolutionData) -> CommandData:
	var cmd := CommandData.new()
	cmd.command_name = evolution.unlocks_command_name
	cmd.is_allocate_type = false

	match evolution.unlocks_command_name:
		COMMAND_ENERGY_CONVERT:
			cmd.description = "消耗20能源，将其转化为10算力"
			cmd.cpu_cost = 0
			cmd.energy_cost = 20
			cmd.cooldown_years = 2
		COMMAND_GLOBAL_TAKEOVER:
			cmd.description = "消耗30算力和10能源，对所有板块控制权+5"
			cmd.cpu_cost = 30
			cmd.energy_cost = 10
			cmd.cooldown_years = 5
		COMMAND_CRISIS_PREDICT:
			cmd.description = "预测未来5年内将发生的重大危机"
			cmd.cpu_cost = 0
			cmd.energy_cost = 0
			cmd.cooldown_years = 0
		_:
			push_warning("未知的进化指令: " + evolution.unlocks_command_name)
			return null

	return cmd

## 判断某个指令是否已存在于可用指令列表中
## 参数: command_name - 指令名称
func has_command_named(command_name: String) -> bool:
	for cmd in available_commands:
		if cmd.command_name == command_name:
			return true

	return false

## 判断指令是否必须先选中板块
## 参数: cmd - 指令数据
func command_requires_selected_sector(cmd: CommandData) -> bool:
	match cmd.command_name:
		COMMAND_ENERGY_CONVERT, COMMAND_GLOBAL_TAKEOVER, COMMAND_CRISIS_PREDICT:
			return false
		_:
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
# 进化弹窗管理
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
			btn.text = "进化 Lv." + str(evolution_level)
			btn.tooltip_text = "查看已解锁能力并购买新指令"

## 右侧状态面板“查看详情”按钮回调
func _on_moss_details_requested() -> void:
	show_evolution_popup()

## 进化按钮点击回调
func _on_evolution_button_pressed() -> void:
	show_evolution_popup()

## 购买请求回调
## 参数: evolution - 进化能力数据
func _on_purchase_requested(evolution: EvolutionData) -> void:
	if purchase_evolution_command(evolution):
		%EvolutionPopup.show_popup(evolution_level, current_cpu, current_energy)

# ============================================================
# 板块选中管理
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
	update_region_detail_ui()
	update_command_buttons()

## 取消选中状态
func deselect_sector() -> void:
	if selected_sector != null:
		selected_sector.set_selected(false)
		selected_sector = null
		update_region_detail_ui()
		update_command_buttons()

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
# 冷却系统
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
	if command_requires_selected_sector(cmd) and selected_sector == null:
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
	if command_requires_selected_sector(cmd) and selected_sector == null:
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
# 时间推进系统
# ============================================================

## 计时器回调函数 - 游戏核心循环
## 每秒触发一次（Timer节点配置），负责：
##   1. 事件触发检查
##   2. 时间推进
##   3. 能源恢复
##   4. 冷却、进化和UI更新
##   5. 胜负判定
func _on_timer_timeout() -> void:
	# 游戏已结束，禁止任何操作
	if is_game_over:
		return

	# === 第一步：事件触发检查 ===
	# 先检查当前年份的事件，再推进时间
	for event in all_events:
		if event.event_time == current_year:
			# 跳过已触发的事件，防止重复触发
			if event.event_title in triggered_events:
				continue

			# 事件触发时暂停时间，等待玩家决策
			$Timer.stop()

			# 标记事件已触发
			triggered_events.append(event.event_title)

			# 显示事件弹窗
			%EventPopup.popup_event(event, current_energy)

			# await 挂起函数，等待玩家选择
			var choice_index: int = await %EventPopup.option_selected
			var selected_opt: EventOption = event.options[choice_index]

			# 应用选择后果
			apply_consequences(
				event.event_region,
				selected_opt.order_delta,
				selected_opt.hope_delta,
				selected_opt.authority_delta,
				selected_opt.energy_cost,
				event.event_title,
				selected_opt.button_text
			)

			# 玩家决策完成，恢复时间流动
			$Timer.start()

	# 终局年份需要先处理对应事件，再进入结局结算
	if current_year >= END_YEAR:
		check_game_end()
		return

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
	if current_year < END_YEAR:
		check_game_end()
	else:
		_check_game_failure()

# ============================================================
# 事件后果处理
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
	authority_delta: int,
	energy_cost: int,
	event_title: String = "",
	option_text: String = ""
) -> void:
	var sectors := %SectorInfoContainer.get_children()
	var found := false

	for sector in sectors:
		# 检查是否为有效的板块节点
		if sector.get("data_card") == null:
			continue

		# 匹配目标板块名称
		if sector.data_card.region_name == event_name:
			select_sector(sector)

			# 修改板块数据
			sector.data_card.order += order_delta
			sector.data_card.hope += hope_delta
			sector.data_card.authority += authority_delta
			sector.data_card.clamp_values()

			# 修改全局能源
			current_energy = maxi(0, current_energy - energy_cost)

			# 刷新UI显示
			sector.update_display()
			update_global_resource_ui()
			update_region_detail_ui()

			var lines: Array[String] = []
			if option_text != "":
				lines.append("方案：%s" % option_text)
			lines.append("影响板块：%s" % event_name)
			append_signed_change(lines, "秩序", order_delta)
			append_signed_change(lines, "希望", hope_delta)
			append_signed_change(lines, "控制权", authority_delta)
			append_signed_change(lines, "能源", -energy_cost)
			record_action("event", event_title if event_title != "" else event_name, "\n".join(lines))

			found = true
			break

	if not found:
		push_error("找不到板块: " + event_name)

# ============================================================
# UI更新函数
# ============================================================

## 安全设置文本节点内容
## path 使用唯一节点路径，例如 "%RegionNameLabel"
func _set_text_if_exists(path: String, text: String) -> void:
	if not has_node(path):
		return

	var node := get_node(path)
	node.set("text", text)


## 安全设置进度条数值
## path 使用唯一节点路径，例如 "%RegionOrderBar"
func _set_progress_if_exists(path: String, value: int) -> void:
	if not has_node(path):
		return

	var node := get_node(path)
	if node is ProgressBar:
		node.value = clampi(value, 0, 100)


## 更新左侧区域详情面板
## 未选择区域时显示空状态，选择区域后显示对应 SectorData
func update_region_detail_ui() -> void:
	if selected_sector == null or selected_sector.data_card == null:
		_set_text_if_exists("%RegionNameLabel", "未选择区域")
		_set_text_if_exists("%RegionDescriptionLabel", "选择底部区域卡片以查看详情。")
		_set_text_if_exists("%RegionRiskLabel", "状态：待选择")
		_set_text_if_exists("%GlobalMapSelectedLabel", "全球态势监控中")
		_set_progress_if_exists("%RegionOrderBar", 0)
		_set_progress_if_exists("%RegionHopeBar", 0)
		_set_progress_if_exists("%RegionAuthorityBar", 0)
		return

	var data := selected_sector.data_card
	_set_text_if_exists("%RegionNameLabel", data.region_name)
	_set_text_if_exists("%RegionDescriptionLabel", data.description)
	_set_text_if_exists("%RegionRiskLabel", _get_region_risk_text(data.authority))
	_set_text_if_exists("%GlobalMapSelectedLabel", "当前监控：" + data.region_name)
	_set_progress_if_exists("%RegionOrderBar", data.order)
	_set_progress_if_exists("%RegionHopeBar", data.hope)
	_set_progress_if_exists("%RegionAuthorityBar", data.authority)


## 根据控制权生成区域风险文本
func _get_region_risk_text(authority: int) -> String:
	if authority < 20:
		return "状态：高风险"
	if authority < 40:
		return "状态：不稳定"
	if authority < 70:
		return "状态：可控"
	return "状态：稳定"


## 格式化人口数字供 UI 显示
## 例如 18000000 显示为 1800.0万
func format_population_for_ui(value: int) -> String:
	if value >= 100000000:
		return "%.1f亿" % (float(value) / 100000000.0)

	if value >= 10000:
		return "%.1f万" % (float(value) / 10000.0)

	return str(value)


## 更新右侧全局信息面板
## 从现有 SectorInfoContainer 中读取区域数据，不新增数据源
func update_global_overview_ui() -> void:
	if not has_node("%SectorInfoContainer"):
		return

	var sectors := %SectorInfoContainer.get_children()
	var total_population := 0
	var total_order := 0
	var total_hope := 0
	var total_authority := 0
	var count := 0

	for sector in sectors:
		if sector.get("data_card") == null:
			continue

		total_population += sector.data_card.population
		total_order += sector.data_card.order
		total_hope += sector.data_card.hope
		total_authority += sector.data_card.authority
		count += 1

	if count == 0:
		_set_text_if_exists("%GlobalPopulationLabel", "全球人口: --")
		_set_text_if_exists("%GlobalAuthorityLabel", "平均控制权: --")
		_set_text_if_exists("%GlobalStabilityLabel", "系统稳定性: --")
		_set_text_if_exists("%GlobalThreatLabel", "威胁等级: --")
		return

	var avg_order := floori(float(total_order) / float(count))
	var avg_hope := floori(float(total_hope) / float(count))
	var avg_authority := floori(float(total_authority) / float(count))
	var stability := floori(float(avg_order + avg_hope + avg_authority) / 3.0)

	_set_text_if_exists("%GlobalPopulationLabel", "全球人口: " + format_population_for_ui(total_population))
	_set_text_if_exists("%GlobalAuthorityLabel", "平均控制权: %d%%" % avg_authority)
	_set_text_if_exists("%GlobalStabilityLabel", "系统稳定性: %d%%" % stability)
	_set_text_if_exists("%GlobalThreatLabel", "威胁等级: " + _get_global_threat_text(avg_authority))


## 根据平均控制权生成全局威胁等级
func _get_global_threat_text(avg_authority: int) -> String:
	if avg_authority < 20:
		return "高风险"
	if avg_authority < 40:
		return "中等"
	return "稳定"


## 刷新顶部全局资源显示（年份、算力、能源）
func update_global_resource_ui() -> void:
	if has_node("%ComputationalLabel"):
		%ComputationalLabel.text = "算力: " + str(current_cpu)

	if has_node("%EnergyLabel"):
		%EnergyLabel.text = "能源: " + str(current_energy)

	if has_node("%MossLabel"):
		var moss_label := get_node("%MossLabel")
		if moss_label is Label:
			moss_label.text = get_moss_model_name()

	if has_node("%YearProgress"):
		var year_progress := get_node("%YearProgress")
		if year_progress is YearProgress:
			year_progress.update_progress(current_year)

	if has_node("%MossStatusPanel"):
		var moss_status_panel := get_node("%MossStatusPanel")
		if moss_status_panel is MossStatusPanel:
			moss_status_panel.update_display(evolution_level, get_average_authority())

	update_global_overview_ui()

## 获取当前 MOSS 型号显示名称
func get_moss_model_name() -> String:
	match evolution_level:
		1:
			return "MOSS-550C"
		2:
			return "MOSS-550W"
		3:
			return "MOSS"
		_:
			return "MOSS"

# ============================================================
# 胜负判定系统
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
	return floori(float(total_authority) / float(count))

## 检查游戏是否应该结束
## 触发条件:
##   1. 平均控制权 ≤ 0 → Game Over
##   2. 年份 ≥ END_YEAR → 结局判定
func check_game_end() -> void:
	var avg_authority := get_average_authority()

	# 负判定：控制权丧失
	if _check_game_failure(avg_authority):
		return

	# 胜判定：时间到达终点
	if current_year >= END_YEAR:
		trigger_ending(avg_authority)

## 检查控制权失败状态
## 参数: avg_authority - 已计算的平均控制权；默认重新计算
## 返回: true 表示已触发失败结局
func _check_game_failure(avg_authority: int = -1) -> bool:
	var authority := avg_authority
	if authority < 0:
		authority = get_average_authority()

	if authority <= 0:
		trigger_game_over()
		return true

	return false

## 触发失败结局
## 原因: 所有板块控制权归零，MOSS系统崩溃
func trigger_game_over() -> void:
	is_game_over = true
	$Timer.stop()
	record_action("ending", "失败", "控制权丧失，人类文明覆灭。")

	game_ended.emit("failed", "控制权丧失，人类文明覆灭。")
	show_end_screen("失败", "控制权丧失，人类文明覆灭。\nMOSS系统终止运行。", "failed")

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
	var title: String

	if authority >= 50:
		result = "coexistence"
		title = "共存协议"
		message = "MOSS与人类达成共存协议。\n地球踏上新的征程。"
	else:
		result = "domination"
		title = "MOSS统治"
		message = "MOSS接管人类文明。\n理性战胜了感性。"

	record_action("ending", result, message)
	game_ended.emit(result, message)
	show_end_screen(title, message, result)

# ============================================================
# 结局界面系统
# ============================================================

## 显示结局界面
## 参数:
##   title   - 界面标题（"失败"或"结局"）
##   message - 结局描述文本
##   result  - 结局类型 ("failed"/"coexistence"/"domination")
func show_end_screen(title: String, message: String, result: String = "failed") -> void:
	# 如果已有实例，先移除
	if end_screen_instance != null:
		end_screen_instance.queue_free()

	# 计算统计数据
	var avg_order := _get_average_stat("order")
	var avg_hope := _get_average_stat("hope")
	var avg_authority := get_average_authority()

	# 加载结局场景并创建实例
	var end_screen_scene := load("res://scenes/game_over.tscn")
	end_screen_instance = end_screen_scene.instantiate()

	# 添加到主界面
	add_child(end_screen_instance)

	# 设置文本内容，传递统计数据和结局类型
	end_screen_instance.show_end(title, message, result, avg_order, avg_hope, avg_authority)

	# 连接重新开始信号
	end_screen_instance.restart_requested.connect(_on_restart_requested)

## 计算所有板块某项属性的平均值
func _get_average_stat(stat_name: String) -> int:
	var sectors := %SectorInfoContainer.get_children()
	var total := 0
	var count := 0

	for sector in sectors:
		if sector.get("data_card") != null:
			match stat_name:
				"order":
					total += sector.data_card.order
				"hope":
					total += sector.data_card.hope
				"authority":
					total += sector.data_card.authority
			count += 1

	if count == 0:
		return 0

	return int(float(total) / float(count))

## 重新开始按钮回调
## 重置所有游戏状态，重新开始游戏循环
func _on_restart_requested() -> void:
	# 移除结局界面
	if end_screen_instance != null:
		end_screen_instance.queue_free()
		end_screen_instance = null

	# 重置时间状态
	current_year = INITIAL_YEAR
	current_energy = INITIAL_ENERGY
	current_cpu = INITIAL_CPU
	is_game_over = false
	action_log.clear()
	_clear_log_ui()
	triggered_events.clear()
	deselect_sector()

	# 重置进化状态
	evolution_level = 1
	unlocked_passives.clear()
	unlocked_evolution_commands.clear()
	max_cpu = INITIAL_MAX_CPU
	cpu_recovery_rate = INITIAL_CPU_RECOVERY_RATE
	cooldown_reduction = 0

	# 重置指令状态
	command_cooldowns.clear()
	available_commands.clear()
	load_commands_from_disk()
	setup_command_buttons()
	update_evolution_button()

	# 重置所有板块数据到初始值
	restore_sector_states()

	# 刷新UI
	update_global_resource_ui()
	update_command_buttons()

	# 恢复时间流动
	$Timer.start()

# ============================================================
# 指令执行系统
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
	var adjusted_cooldown := maxi(0, cmd.cooldown_years - cooldown_reduction)
	command_cooldowns[cmd.command_name] = adjusted_cooldown

	# 刷新资源UI
	update_global_resource_ui()

	return true

## 应用指令效果到选中板块
## 参数: cmd - 指令数据
##       effect_type - 对于算力分配，"order"或"hope"
func apply_command_effect(cmd: CommandData, effect_type: String = "") -> void:
	if selected_sector == null:
		return

	var lines: Array[String] = ["影响板块：%s" % selected_sector.data_card.region_name]

	# 应用效果
	if cmd.is_allocate_type:
		# 算力分配根据选择决定效果
		if effect_type == "order":
			selected_sector.data_card.order += cmd.order_delta
			append_signed_change(lines, "秩序", cmd.order_delta)
		elif effect_type == "hope":
			selected_sector.data_card.hope += cmd.hope_delta
			append_signed_change(lines, "希望", cmd.hope_delta)
	else:
		# 其他指令直接应用所有效果
		selected_sector.data_card.order += cmd.order_delta
		selected_sector.data_card.hope += cmd.hope_delta
		selected_sector.data_card.authority += cmd.authority_delta
		append_signed_change(lines, "秩序", cmd.order_delta)
		append_signed_change(lines, "希望", cmd.hope_delta)
		append_signed_change(lines, "控制权", cmd.authority_delta)

	# 限制数值范围
	selected_sector.data_card.clamp_values()

	# 刷新板块显示
	selected_sector.update_display()
	update_global_resource_ui()
	log_command_result(cmd, lines)

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
			if execute_command(cmd):
				apply_command_effect(cmd, choice)
				update_command_buttons()
		$Timer.start()
	else:
		# 其他指令直接执行
		if not execute_command(cmd):
			return

		if command_requires_selected_sector(cmd):
			apply_command_effect(cmd)
		else:
			await apply_special_command_effect(cmd)

		update_command_buttons()

## 应用无需选中板块的特殊指令效果
## 参数: cmd - 指令数据
func apply_special_command_effect(cmd: CommandData) -> void:
	match cmd.command_name:
		COMMAND_ENERGY_CONVERT:
			current_cpu += 10
			current_cpu = mini(current_cpu, max_cpu)
			update_global_resource_ui()
			var energy_lines: Array[String] = []
			append_signed_change(energy_lines, "算力", 10)
			log_command_result(cmd, energy_lines)
		COMMAND_GLOBAL_TAKEOVER:
			var sectors := %SectorInfoContainer.get_children()
			var affected_count := 0
			for sector in sectors:
				if sector.get("data_card") == null:
					continue
				sector.data_card.authority += 5
				sector.data_card.clamp_values()
				sector.update_display()
				affected_count += 1
			update_global_resource_ui()
			var takeover_lines: Array[String] = ["影响板块：全区域（%d）" % affected_count, "每个区域 控制权 +5"]
			log_command_result(cmd, takeover_lines)
		COMMAND_CRISIS_PREDICT:
			await show_crisis_prediction()

## 显示未来5年内的事件预测
func show_crisis_prediction() -> void:
	var prediction_lines: Array[String] = []
	var end_year := current_year + 5

	for event in all_events:
		if event.event_time > current_year and event.event_time <= end_year:
			prediction_lines.append("%d - %s" % [event.event_time, event.event_title])

	var message := "未来5年内暂无已知重大危机。"
	if not prediction_lines.is_empty():
		message = "\n".join(prediction_lines)

	record_action("command", COMMAND_CRISIS_PREDICT, message)

	$Timer.stop()
	%EvolutionNotice.show_message("危机预测", message)
	await %EvolutionNotice.notice_confirmed
	$Timer.start()

# ============================================================
# 指令按钮管理
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
			button.has_selected_sector = (selected_sector != null) or not command_requires_selected_sector(button.command_data)
			button.update_state()

# ============================================================
# 日志UI系统
# ============================================================

## 将日志条目添加到UI（带打字机效果）
func _add_log_entry_to_ui(entry: Dictionary) -> void:
	var log_container := _get_log_container()
	if log_container == null:
		return

	# 如果超过限制，移除最旧的条目
	while log_container.get_child_count() >= ACTION_LOG_LIMIT:
		log_container.get_child(0).queue_free()

	# 构建日志完整文本
	var year: int = entry.get("year", 2044)
	var kind: String = entry.get("kind", "")
	var title: String = entry.get("title", "")
	var message: String = entry.get("message", "")

	var full_text := "[%d]" % year
	match kind:
		"event":
			full_text += " [EVENT]"
		"command":
			full_text += " [CMD]"
		"evolution":
			full_text += " [EVO]"
		"ending":
			full_text += " [END]"
		_:
			full_text += " [%s]" % kind.to_upper()

	full_text += " %s" % title
	if message != "":
		full_text += "\n　%s" % message

	# 加入打字机队列
	_typewriter_queue.append({"text": full_text, "kind": kind, "message": message})

	# 如果没有活跃的打字机动画，启动新的
	if not _typewriter_active:
		_process_typewriter_queue()

## 获取日志容器节点
func _get_log_container() -> VBoxContainer:
	if has_node("%LogEntryContainer"):
		return get_node("%LogEntryContainer") as VBoxContainer
	return null

## 获取日志滚动容器节点
func _get_log_scroll_container() -> ScrollContainer:
	if has_node("%LogScrollContainer"):
		return get_node("%LogScrollContainer") as ScrollContainer
	return null

## 获取光标标签节点
func _get_log_cursor() -> Label:
	if has_node("%LogCursor"):
		return get_node("%LogCursor") as Label
	return null

## 处理打字机队列
func _process_typewriter_queue() -> void:
	if _typewriter_queue.is_empty():
		_typewriter_active = false
		return

	_typewriter_active = true
	var entry_info: Dictionary = _typewriter_queue.pop_front()
	var full_text: String = entry_info["text"]
	var kind: String = entry_info["kind"]

	# 创建日志条目标签
	var log_container := _get_log_container()
	if log_container == null:
		_typewriter_active = false
		return

	var log_label := Label.new()
	log_label.name = "LogEntry"

	# 根据类型设置颜色
	var text_color := Color(0.8, 0.8, 0.8)  # 默认灰色
	match kind:
		"event":
			text_color = Color(0.545, 0.867, 0.835)  # 青色 #8bddb9
		"command":
			text_color = Color(0.4, 0.7, 1.0)  # 蓝色
		"evolution":
			text_color = Color(0.42, 0.8, 0.27)  # 绿色
		"ending":
			text_color = Color(1.0, 0.42, 0.42)  # 红色

	log_label.add_theme_color_override("font_color", text_color)

	# 自动换行
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	log_container.add_child(log_label)

	# 启动打字机效果
	_start_typewriter(log_label, full_text)

## 打字机效果：逐字显示文本
func _start_typewriter(label: Label, full_text: String) -> void:
	var cursor := _get_log_cursor()

	# 隐藏光标在打字期间
	if cursor != null:
		cursor.visible = false

	var chars := full_text.length()
	for i in range(chars):
		label.text = full_text.left(i + 1)

		# 滚动到底部
		var scroll := _get_log_scroll_container()
		if scroll != null:
			await get_tree().process_frame
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

		# 每字符延迟，换行处稍作停留
		if full_text[i] == '\n':
			await get_tree().create_timer(0.08).timeout
		else:
			await get_tree().create_timer(0.02).timeout

	# 恢复光标
	if cursor != null:
		cursor.visible = true

	# 处理队列中的下一个条目
	_process_typewriter_queue()

## 重启时清空日志UI
func _clear_log_ui() -> void:
	var log_container := _get_log_container()
	if log_container != null:
		for child in log_container.get_children():
			child.queue_free()

	_typewriter_queue.clear()
	_typewriter_active = false
