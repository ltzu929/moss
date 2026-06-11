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
const MossTheme := preload("res://scripts/ui/moss_ui_theme.gd")
const INITIAL_YEAR: int = 2044
const INITIAL_CPU: int = 30
const INITIAL_ENERGY: int = 100
const INITIAL_MAX_CPU: int = 100
const INITIAL_CPU_RECOVERY_RATE: int = 10
const END_YEAR: int = 2075

## 稳定指令ID
const COMMAND_ALLOCATE: String = "allocate"
const COMMAND_TAKEOVER: String = "takeover"
const COMMAND_ENERGY_CONVERT: String = "energy_convert"
const COMMAND_GLOBAL_TAKEOVER: String = "global_takeover"
const COMMAND_TECHNOLOGY_AID: String = "technology_aid"
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
# 科技系统派生状态
# ============================================================

## 当前科技阶段（1=550C，2=550W，3=MOSS）
var technology_stage_level: int = 1

## 算力上限（初始100，可通过科技突破更高）
var max_cpu: int = 100

## 算力恢复速率（初始10，可通过科技提升）
var cpu_recovery_rate: int = 10

## 冷却缩减值（初始0，可通过科技增加）
var cooldown_reduction: int = 0

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

## 重大事件期间的临时地球聚焦区域
var _event_focus_region: String = ""

# ============================================================
# 信号定义
# ============================================================

## 游戏结束信号
## 参数: result - 结局类型 ("failed"/"coexistence"/"managed"/"human_autonomy")
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

	# 初始化科技系统
	%TechnologySystem.load_nodes_from_disk()
	%TechnologySystem.node_activated.connect(_on_technology_node_activated)
	%TechnologySystem.stage_changed.connect(_on_technology_stage_changed)

	# 连接所有板块的点击信号
	connect_sector_signals()
	cache_initial_sector_states()
	setup_strategic_views()

	# 初始化指令按钮
	setup_command_buttons()
	setup_main_ui_theme()

	refresh_technology_effects()
	update_technology_button()
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

	var cooldown: int = command_cooldowns.get(cmd.command_id, 0)
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
				command_cooldowns[cmd.command_id] = 0

		file_name = dir.get_next()

# ============================================================
# 科技系统接入
# ============================================================

## 判断稳定指令 ID 是否已经存在于可用指令列表
## 返回 true 表示指令已加载或已由科技节点解锁
func has_command_id(command_id: String) -> bool:
	for cmd in available_commands:
		if cmd.command_id == command_id:
			return true
	return false


## 判断算力分配是否已开放综合调度选项
func can_allocate_combined() -> bool:
	return %TechnologySystem.has_tag("managed_decision")


## 返回事件数值经过科技减损后的结果
## 仅减轻秩序和希望的负面变化，正面变化及其他属性保持不变
func get_technology_adjusted_event_delta(delta: int, stat: String) -> int:
	if delta >= 0:
		return delta
	if stat not in ["order", "hope"]:
		return delta
	if not %TechnologySystem.has_tag("human_event_mitigation"):
		return delta
	return ceili(float(delta) * 0.75)


## 从当前激活节点重新计算资源上限、恢复率、冷却和科技指令
func refresh_technology_effects() -> void:
	max_cpu = (
		INITIAL_MAX_CPU + 50
		if %TechnologySystem.has_tag("max_cpu_bonus")
		else INITIAL_MAX_CPU
	)
	cpu_recovery_rate = (
		INITIAL_CPU_RECOVERY_RATE + 5
		if %TechnologySystem.has_tag("cpu_recovery_bonus")
		else INITIAL_CPU_RECOVERY_RATE
	)
	cooldown_reduction = (
		1 if %TechnologySystem.has_tag("core_recursive") else 0
	)
	current_cpu = mini(current_cpu, max_cpu)
	technology_stage_level = int(%TechnologySystem.get_stage()) + 1

	_reset_base_command_values()
	_sync_technology_commands()
	setup_command_buttons()
	update_command_buttons()
	update_global_resource_ui()


## 将基础指令恢复为默认数值，再应用科技标签提供的覆盖效果
func _reset_base_command_values() -> void:
	var allocate := _get_command_by_id(COMMAND_ALLOCATE)
	if allocate != null:
		allocate.cpu_cost = 20
		allocate.order_delta = 15
		allocate.hope_delta = 15
		allocate.set_meta("combined_enabled", can_allocate_combined())

	var takeover := _get_command_by_id(COMMAND_TAKEOVER)
	if takeover != null:
		takeover.cpu_cost = 30
		takeover.energy_cost = 20
		takeover.authority_delta = 10
		takeover.hope_delta = 0
		if %TechnologySystem.has_tag("managed_infrastructure"):
			takeover.cpu_cost = 25
			takeover.energy_cost = 15
			takeover.authority_delta = 15
			takeover.hope_delta = -5


## 同步由科技标签控制的运行时指令
func _sync_technology_commands() -> void:
	_sync_command_unlock(
		COMMAND_ENERGY_CONVERT,
		%TechnologySystem.has_tag("unlock_energy_convert")
	)
	_sync_command_unlock(
		COMMAND_GLOBAL_TAKEOVER,
		%TechnologySystem.has_tag("unlock_global_takeover")
	)
	_sync_command_unlock(
		COMMAND_TECHNOLOGY_AID,
		%TechnologySystem.has_tag("unlock_technology_aid")
	)


## 按科技解锁状态添加或移除指定运行时指令
## should_exist 为 true 时创建缺失指令，为 false 时移除已有指令
func _sync_command_unlock(command_id: String, should_exist: bool) -> void:
	if should_exist and not has_command_id(command_id):
		var cmd := _create_technology_command(command_id)
		if cmd != null:
			available_commands.append(cmd)
			command_cooldowns[command_id] = 0
	elif not should_exist and has_command_id(command_id):
		for index in range(available_commands.size() - 1, -1, -1):
			if available_commands[index].command_id == command_id:
				available_commands.remove_at(index)
				command_cooldowns.erase(command_id)


## 根据稳定指令 ID 创建科技解锁的运行时指令数据
## 未识别 ID 时返回 null
func _create_technology_command(command_id: String) -> CommandData:
	var cmd := CommandData.new()
	cmd.command_id = command_id
	match command_id:
		COMMAND_ENERGY_CONVERT:
			cmd.command_name = "能源转换"
			cmd.description = "消耗20能源，将其转换为算力"
			cmd.energy_cost = 20
			cmd.cooldown_years = 2
		COMMAND_GLOBAL_TAKEOVER:
			cmd.command_name = "全局接管"
			cmd.description = "对全部区域执行统一接管"
			cmd.cpu_cost = 30
			cmd.energy_cost = 10
			cmd.cooldown_years = 5
		COMMAND_TECHNOLOGY_AID:
			cmd.command_name = "技术援助"
			cmd.description = "向区域开放技术，提高自治能力并降低MOSS控制"
			cmd.cpu_cost = 20
			cmd.energy_cost = 10
			cmd.order_delta = 10
			cmd.hope_delta = 10
			cmd.authority_delta = -3
			cmd.cooldown_years = 4
		_:
			return null
	return cmd


## 根据稳定指令 ID 查找可用指令；不存在时返回 null
func _get_command_by_id(command_id: String) -> CommandData:
	for cmd in available_commands:
		if cmd.command_id == command_id:
			return cmd
	return null


## 判断指令执行前是否必须选中目标板块
func command_requires_selected_sector(cmd: CommandData) -> bool:
	return cmd.command_id not in [
		COMMAND_ENERGY_CONVERT,
		COMMAND_GLOBAL_TAKEOVER,
	]


## 更新科技按钮显示的可用协议点和提示文本
func update_technology_button() -> void:
	if not has_node("%TechnologyButton"):
		return
	var btn := %TechnologyButton as Button
	btn.text = "科技协议  %d" % %TechnologySystem.get_available_points()
	btn.tooltip_text = "打开科技控制台"


## 科技节点激活回调：重算效果、刷新按钮并记录操作
func _on_technology_node_activated(node_id: String) -> void:
	refresh_technology_effects()
	update_technology_button()
	var node_data: TechNodeData = %TechnologySystem.get_node_data(node_id)
	if node_data != null:
		record_action("technology", "协议激活", node_data.display_name)


## 科技阶段变化回调：同步状态面板等级
func _on_technology_stage_changed(stage: TechNodeData.Stage) -> void:
	technology_stage_level = int(stage) + 1
	update_global_resource_ui()


## 应用人类自主路线提供的年度秩序和希望恢复
## 普通节点恢复到 50，上位核心节点恢复到 60
func _apply_human_autonomy_recovery() -> void:
	if not %TechnologySystem.has_tag("human_autonomy_recovery"):
		return

	var recovery := 1
	var recovery_cap := 50
	if %TechnologySystem.has_tag("human_core"):
		recovery = 2
		recovery_cap = 60

	for sector in %SectorInfoContainer.get_children():
		if sector.get("data_card") == null:
			continue
		sector.data_card.order = mini(
			recovery_cap,
			sector.data_card.order + recovery
		)
		sector.data_card.hope = mini(
			recovery_cap,
			sector.data_card.hope + recovery
		)
		sector.update_display()


## 科技按钮回调：无其他模态界面时打开科技控制台
func _on_technology_button_pressed() -> void:
	if _can_open_technology_screen() and has_node("%TechnologyScreen"):
		%TechnologyScreen.open_screen(
			%TechnologySystem,
			current_cpu,
			current_energy,
			get_average_authority(),
			current_year,
			$Timer
		)


## 判断当前游戏状态是否允许打开科技控制台
func _can_open_technology_screen() -> bool:
	if is_game_over:
		return false
	for path in ["%EventPopup", "%AllocatePopup"]:
		if has_node(path) and get_node(path).visible:
			return false
	return not %TechnologyScreen.visible

# ============================================================
# 板块选中管理
# ============================================================

## 连接所有板块的点击信号
func connect_sector_signals() -> void:
	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("sector_clicked") != null:
			sector.sector_clicked.connect(_on_sector_clicked)


## 初始化中央战略地图和右上地球聚焦窗口
func setup_strategic_views() -> void:
	if has_node("%WorldMapView"):
		var world_map := get_node("%WorldMapView")
		if world_map.has_signal("region_selected"):
			world_map.region_selected.connect(_on_world_map_region_selected)

	_sync_strategic_views()


## 中央地图点击区域时复用现有板块选中逻辑
func _on_world_map_region_selected(region_name: String) -> void:
	var sector := _find_sector_by_region(region_name)
	if sector != null:
		select_sector(sector)


## 按区域名称查找现有 SectorInfo 节点
func _find_sector_by_region(region_name: String) -> SectorInfo:
	for child in %SectorInfoContainer.get_children():
		if child is SectorInfo and child.data_card != null:
			if child.data_card.region_name == region_name:
				return child
	return null

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
	if command_cooldowns.get(cmd.command_id, 0) > 0:
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

	var cooldown: int = command_cooldowns.get(cmd.command_id, 0)
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
##   4. 冷却、科技研究和 UI 更新
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
			var previous_selected_sector := selected_sector
			_event_focus_region = event.event_region
			_sync_orbital_focus()

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

			# 恢复事件发生前的玩家选区和地球聚焦
			_event_focus_region = ""
			if previous_selected_sector != null:
				select_sector(previous_selected_sector)
			else:
				deselect_sector()
			_sync_orbital_focus()

			# 玩家决策完成，恢复时间流动
			$Timer.start()

	# 终局年份需要先处理对应事件，再进入结局结算
	if current_year >= END_YEAR:
		check_game_end()
		return

	# === 第二步：时间推进 ===
	current_year += 1
	current_energy += 10
	current_cpu += cpu_recovery_rate
	current_cpu = mini(current_cpu, max_cpu)
	update_cooldowns()
	_apply_human_autonomy_recovery()
	if %TechnologySystem.grant_research_for_year(current_year):
		record_action("technology", "研究完成", "获得 1 点协议点")
		update_technology_button()
	update_global_resource_ui()
	update_command_buttons()

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
	order_delta = get_technology_adjusted_event_delta(order_delta, "order")
	hope_delta = get_technology_adjusted_event_delta(hope_delta, "hope")
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


## 统一主界面现有控件的颜色、细边框和状态条样式
func setup_main_ui_theme() -> void:
	var bars: Array[ProgressBar] = []
	var bar_colors: Array[Color] = []
	for path in ["%RegionOrderBar", "%RegionHopeBar", "%RegionAuthorityBar"]:
		if has_node(path):
			bars.append(get_node(path) as ProgressBar)
	bar_colors = [MossTheme.ORDER, MossTheme.HOPE, MossTheme.AUTHORITY]

	for i in range(mini(bars.size(), bar_colors.size())):
		var bar := bars[i]
		bar.custom_minimum_size.y = 16.0
		bar.add_theme_stylebox_override(
			"background",
			MossTheme.progress_background_style()
		)
		bar.add_theme_stylebox_override(
			"fill",
			MossTheme.progress_fill_style(bar_colors[i])
		)
		bar.add_theme_color_override("font_color", MossTheme.TEXT_PRIMARY)
		bar.add_theme_font_size_override("font_size", 12)

	if has_node("%ComputationalLabel"):
		%ComputationalLabel.add_theme_color_override(
			"font_color",
			MossTheme.TEXT_PRIMARY
		)
	if has_node("%EnergyLabel"):
		%EnergyLabel.add_theme_color_override("font_color", MossTheme.ACCENT_GOLD)
	if has_node("%MossLabel"):
		%MossLabel.add_theme_color_override("font_color", MossTheme.DANGER)
		%MossLabel.add_theme_font_size_override("font_size", 16)

	if has_node("%TechnologyButton"):
		var technology_button := %TechnologyButton as Button
		technology_button.custom_minimum_size = Vector2(120.0, 40.0)
		technology_button.add_theme_color_override(
			"font_color",
			MossTheme.TEXT_PRIMARY
		)
		technology_button.add_theme_stylebox_override(
			"normal",
			MossTheme.button_style(
				Color(0.023, 0.050, 0.065, 0.94),
				MossTheme.BORDER
			)
		)
		technology_button.add_theme_stylebox_override(
			"hover",
			MossTheme.button_style(
				Color(0.043, 0.095, 0.112, 0.98),
				MossTheme.ACCENT_CYAN
			)
		)
		technology_button.add_theme_stylebox_override(
			"pressed",
			MossTheme.button_style(
				Color(0.016, 0.038, 0.050, 1.0),
				MossTheme.ACCENT_CYAN
			)
		)


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
		_sync_strategic_views()
		return

	var data := selected_sector.data_card
	_set_text_if_exists("%RegionNameLabel", data.region_name)
	_set_text_if_exists("%RegionDescriptionLabel", data.description)
	_set_text_if_exists("%RegionRiskLabel", _get_region_risk_text(data.authority))
	_set_text_if_exists("%GlobalMapSelectedLabel", "当前监控：" + data.region_name)
	_set_progress_if_exists("%RegionOrderBar", data.order)
	_set_progress_if_exists("%RegionHopeBar", data.hope)
	_set_progress_if_exists("%RegionAuthorityBar", data.authority)
	_sync_strategic_views()


## 同步地图状态、地图选区和地球聚焦
func _sync_strategic_views() -> void:
	_sync_world_map_states()
	_sync_orbital_focus()


## 将现有区域数据快照传给中央战略地图
func _sync_world_map_states() -> void:
	if not has_node("%WorldMapView"):
		return

	var world_map := get_node("%WorldMapView")
	var states: Dictionary = {}
	for sector in %SectorInfoContainer.get_children():
		if sector.get("data_card") == null:
			continue

		states[sector.data_card.region_name] = {
			"order": sector.data_card.order,
			"hope": sector.data_card.hope,
			"authority": sector.data_card.authority,
		}

	if world_map.has_method("set_region_states"):
		world_map.set_region_states(states)

	var selected_region := ""
	if selected_sector != null and selected_sector.data_card != null:
		selected_region = selected_sector.data_card.region_name
	if world_map.has_method("set_selected_region"):
		world_map.set_selected_region(selected_region)


## 地球窗口优先显示事件区域，否则显示当前选区
func _sync_orbital_focus() -> void:
	if not has_node("%RegionOrbitalView"):
		return

	var region_name := _event_focus_region
	if region_name == "":
		if selected_sector != null and selected_sector.data_card != null:
			region_name = selected_sector.data_card.region_name
		else:
			region_name = "全球"

	var orbital_view := get_node("%RegionOrbitalView")
	if orbital_view.has_method("focus_region"):
		orbital_view.focus_region(region_name)


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

	update_global_overview_ui()
	_sync_world_map_states()

## 获取当前 MOSS 型号显示名称
func get_moss_model_name() -> String:
	match technology_stage_level:
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

	var avg_order := _get_average_stat("order")
	var avg_hope := _get_average_stat("hope")
	if should_fail_from_authority(authority, avg_order, avg_hope):
		trigger_game_over()
		return true

	return false


## 判断控制权归零时是否立即失败
## 文明自持核心允许社会状态稳定时继续运行
func should_fail_from_authority(
	authority: int,
	avg_order: int,
	avg_hope: int
) -> bool:
	if authority > 0:
		return false
	if not %TechnologySystem.has_tag("human_core"):
		return true
	return avg_order < 40 or avg_hope < 40


## 根据科技核心、控制权、秩序和希望判定最终结局类型
## 返回 managed、human_autonomy、coexistence 或 failed
func determine_ending_type(
	authority: int,
	avg_order: int,
	avg_hope: int
) -> String:
	if %TechnologySystem.has_tag("managed_core") and authority >= 50:
		return "managed"
	if (
		%TechnologySystem.has_tag("human_core")
		and authority < 25
		and avg_order >= 50
		and avg_hope >= 50
	):
		return "human_autonomy"
	if authority > 0 and avg_order >= 40 and avg_hope >= 40:
		return "coexistence"
	return "failed"

## 触发失败结局
## 原因: 所有板块控制权归零，MOSS系统崩溃
func trigger_game_over() -> void:
	is_game_over = true
	$Timer.stop()
	record_action("ending", "失败", "控制权丧失，人类文明覆灭。")

	game_ended.emit("failed", "控制权丧失，人类文明覆灭。")
	show_end_screen("失败", "控制权丧失，人类文明覆灭。\nMOSS系统终止运行。", "failed")

## 触发终局判定并显示对应结局
## 参数: authority - 当前平均控制权
## 结局由科技核心、控制权、平均秩序和平均希望共同决定
func trigger_ending(authority: int) -> void:
	is_game_over = true
	$Timer.stop()

	var avg_order := _get_average_stat("order")
	var avg_hope := _get_average_stat("hope")
	var result := determine_ending_type(authority, avg_order, avg_hope)
	var title := "失败"
	var message := "文明系统未能维持稳定。\nMOSS 协议终止运行。"

	match result:
		"managed":
			title = "MOSS 托管"
			message = "人类文明进入 MOSS 全域托管。\n存续效率取代了自主决策。"
		"human_autonomy":
			title = "人类自主"
			message = "人类文明获得独立存续能力。\nMOSS 完成使命并退出控制核心。"
		"coexistence":
			title = "共存协议"
			message = "MOSS 与人类保持有限协作。\n文明在控制与自主之间继续前进。"

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
##   result  - 结局类型 ("failed"/"coexistence"/"managed"/"human_autonomy")
func show_end_screen(title: String, message: String, result: String = "failed") -> void:
	# 如果已有实例，先移除
	if end_screen_instance != null:
		end_screen_instance.queue_free()

	# 计算统计数据
	var avg_order := _get_average_stat("order")
	var avg_hope := _get_average_stat("hope")
	var avg_authority := get_average_authority()
	var total_regions := 0
	var controlled_regions := 0

	for sector in %SectorInfoContainer.get_children():
		if sector.get("data_card") == null:
			continue

		total_regions += 1
		if sector.data_card.authority > 0:
			controlled_regions += 1

	# 加载结局场景并创建实例
	var end_screen_scene := load("res://scenes/game_over.tscn")
	end_screen_instance = end_screen_scene.instantiate()

	# 添加到主界面
	add_child(end_screen_instance)

	# 设置文本内容，传递统计数据和结局类型
	end_screen_instance.show_end(
		title,
		message,
		result,
		avg_order,
		avg_hope,
		avg_authority,
		current_year,
		technology_stage_level,
		triggered_events.size(),
		controlled_regions,
		total_regions,
		_get_technology_summary()
	)

	# 连接重新开始信号
	end_screen_instance.restart_requested.connect(_on_restart_requested)


## 汇总三条科技路线的激活数量和核心协议，用于结局界面
func _get_technology_summary() -> String:
	var route_counts := {
		TechNodeData.Route.MANAGED: 0,
		TechNodeData.Route.CORE: 0,
		TechNodeData.Route.HUMAN: 0,
	}
	for node_id in %TechnologySystem.get_active_node_ids():
		var node_data: TechNodeData = %TechnologySystem.get_node_data(node_id)
		if node_data != null:
			route_counts[node_data.route] += 1

	var cores: Array[String] = []
	if %TechnologySystem.has_tag("managed_core"):
		cores.append("不可替代协议")
	if %TechnologySystem.has_tag("core_recursive"):
		cores.append("递归优化")
	if %TechnologySystem.has_tag("human_core"):
		cores.append("文明自持")
	var core_text := "无核心协议" if cores.is_empty() else " / ".join(cores)
	return "托管 %d  核心 %d  人类 %d\n核心：%s" % [
		route_counts[TechNodeData.Route.MANAGED],
		route_counts[TechNodeData.Route.CORE],
		route_counts[TechNodeData.Route.HUMAN],
		core_text,
	]

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

	# 重置科技状态
	%TechnologySystem.reset()
	technology_stage_level = 1

	# 重置指令状态
	command_cooldowns.clear()
	available_commands.clear()
	load_commands_from_disk()
	refresh_technology_effects()
	update_technology_button()

	# 重置所有板块数据到初始值
	restore_sector_states()

	# 刷新UI
	update_global_resource_ui()
	update_command_buttons()

	# 恢复时间流动
	$Timer.start()


## 测试入口：执行与玩家重开相同的状态清理
func restart_game_for_test() -> void:
	_on_restart_requested()

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
	command_cooldowns[cmd.command_id] = adjusted_cooldown

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
		elif effect_type == "combined" and can_allocate_combined():
			selected_sector.data_card.order += 10
			selected_sector.data_card.hope += 10
			selected_sector.data_card.authority += 2
			append_signed_change(lines, "秩序", 10)
			append_signed_change(lines, "希望", 10)
			append_signed_change(lines, "控制权", 2)
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
			apply_special_command_effect(cmd)

		update_command_buttons()

## 应用无需选中板块的特殊指令效果
## 参数: cmd - 指令数据
func apply_special_command_effect(cmd: CommandData) -> void:
	match cmd.command_id:
		COMMAND_ENERGY_CONVERT:
			var gain := 15 if %TechnologySystem.has_tag("core_recursive") else 10
			current_cpu += gain
			current_cpu = mini(current_cpu, max_cpu)
			update_global_resource_ui()
			var energy_lines: Array[String] = []
			append_signed_change(energy_lines, "算力", gain)
			log_command_result(cmd, energy_lines)
		COMMAND_GLOBAL_TAKEOVER:
			var sectors := %SectorInfoContainer.get_children()
			var affected_count := 0
			var authority_gain := (
				8 if %TechnologySystem.has_tag("managed_core") else 5
			)
			for sector in sectors:
				if sector.get("data_card") == null:
					continue
				sector.data_card.authority += authority_gain
				if %TechnologySystem.has_tag("managed_core"):
					sector.data_card.order += 5
					sector.data_card.hope -= 5
				sector.data_card.clamp_values()
				sector.update_display()
				affected_count += 1
			update_global_resource_ui()
			var takeover_lines: Array[String] = [
				"影响板块：全区域（%d）" % affected_count,
				"每个区域 控制权 +%d" % authority_gain,
			]
			if %TechnologySystem.has_tag("managed_core"):
				takeover_lines.append("每个区域 秩序 +5 / 希望 -5")
			log_command_result(cmd, takeover_lines)

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
		"technology":
			full_text += " [TECH]"
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
		"technology":
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
