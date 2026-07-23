## 主控制器脚本 - MOSS模拟器核心系统
## 负责游戏的时间推进、事件触发、胜负判定和结局显示
extends Control

# ============================================================
# 信号定义
# ============================================================

## 游戏结束信号
## 参数: result - 结局类型 ("failed"/"coexistence"/"managed"/"human_autonomy")
## 参数: message - 结局描述文本
signal game_ended(result: String, message: String)

# ============================================================
# 导出变量
# ============================================================

## 所有事件资源的列表
## 从 res://data/events/ 目录自动加载，无需手动配置
@export var all_events: Array[GameEvent]
## 所有随机局势模板；运行时从 res://data/situations/ 自动加载
@export var all_situations: Array[SituationData]

# ============================================================
# 常量
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
## 指令领域服务脚本
const COMMAND_SYSTEM_SCRIPT := preload("res://scripts/systems/command_system.gd")
## 开发期崩溃诊断日志
const DEVELOPMENT_LOG_SCRIPT := preload("res://scripts/systems/development_log.gd")
## 不可逆核心决策历史
const DECISION_HISTORY_SCRIPT := preload("res://scripts/systems/decision_history.gd")
## 随机局势领域服务脚本
const SITUATION_SYSTEM_SCRIPT := preload("res://scripts/systems/situation_system.gd")
## 游戏初始值
const INITIAL_YEAR: int = 2044
const INITIAL_MONTH: int = 1
const INITIAL_CPU: int = 30
const INITIAL_ENERGY: int = 100
const INITIAL_MAX_CPU: int = 100
const INITIAL_CPU_RECOVERY_RATE: int = 10
const INITIAL_ENERGY_RECOVERY_RATE: int = 10
const END_YEAR: int = 2075
const END_MONTH: int = 1

## 稳定指令 ID，实际所有权在 CommandSystem
const COMMAND_ALLOCATE: String = COMMAND_SYSTEM_SCRIPT.COMMAND_ALLOCATE
const COMMAND_TAKEOVER: String = COMMAND_SYSTEM_SCRIPT.COMMAND_TAKEOVER
const COMMAND_ENERGY_CONVERT: String = COMMAND_SYSTEM_SCRIPT.COMMAND_ENERGY_CONVERT
const COMMAND_GLOBAL_TAKEOVER: String = COMMAND_SYSTEM_SCRIPT.COMMAND_GLOBAL_TAKEOVER
const COMMAND_TECHNOLOGY_AID: String = COMMAND_SYSTEM_SCRIPT.COMMAND_TECHNOLOGY_AID
const ACTION_LOG_LIMIT: int = 24

# ============================================================
# 游戏状态变量
# ============================================================

## 当前显示的结局界面实例
var end_screen_instance: Control = null

## 打字机动画队列
var _typewriter_queue: Array[Dictionary] = []
var _typewriter_active: bool = false

## 当前年份 (2044-2075)
var current_year: int = 2044
## 当前月份 (1-12)
var current_month: int = 1

## 当前算力 (MOSS的核心资源)
## 用于执行指令，初始30，每年1月恢复10
var current_cpu: int = 30

## 当前能源 (全局资源)
## 每年1月自动恢复10点，事件选项可能消耗
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
var cpu_recovery_rate: int = INITIAL_CPU_RECOVERY_RATE

## 能源恢复速率（初始10，可被核心路线科技修正）
var energy_recovery_rate: int = INITIAL_ENERGY_RECOVERY_RATE

## 冷却缩减值（初始0，可通过科技增加）
var cooldown_reduction: int = 0

# ============================================================
# 指令系统状态
# ============================================================

## 当前选中的板块
var selected_sector: SectorInfo = null

## 各指令冷却剩余月数 {"算力分配": 0, "系统接管": 24}
var command_cooldowns: Dictionary = {}

## 可用指令列表（从磁盘加载）
var available_commands: Array[CommandData] = []

## 板块初始状态快照（用于重新开始）
var initial_sector_states: Dictionary = {}
var action_log: Array[Dictionary] = []

## 指令领域服务，不直接访问场景树或 UI
var _command_system: CommandSystem = COMMAND_SYSTEM_SCRIPT.new()
## 开发期诊断日志，不参与游戏内日志 UI
var _development_log: DevelopmentLog = DEVELOPMENT_LOG_SCRIPT.new()
## 核心决策标签和面向玩家的稳定档案
var _decision_history: DecisionHistory = DECISION_HISTORY_SCRIPT.new()
## 随机局势领域服务，不直接访问场景树或 UI
var _situation_system: SituationSystem = SITUATION_SYSTEM_SCRIPT.new()

## 已触发的事件ID列表（防止重复触发）
var triggered_events: Array[String] = []

## 轻量事件状态 {"event_state.mid_01_lottery_ordering": "manual_review"}
var event_states: Dictionary = {}

## 重大事件期间的临时地球聚焦区域
var _event_focus_region: String = ""
## 决策档案打开前计时器是否正在运行
var _decision_archive_timer_was_running: bool = false
## HUD 时间控制与局势自动暂停状态
var _manually_paused: bool = false
var _situation_auto_paused: bool = false

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	_setup_development_log()

	# 初始化事件列表
	all_events.clear()
	load_events_from_disk()

	# 初始化随机局势模板和本局随机种子
	all_situations.clear()
	load_situations_from_disk()
	_situation_system.configure_templates(all_situations)
	_situation_system.reset()

	# 初始化指令列表
	available_commands.clear()
	load_commands_from_disk()

	# 初始化科技系统
	%TechnologySystem.load_nodes_from_disk()
	%TechnologySystem.node_activated.connect(_on_technology_node_activated)
	%TechnologySystem.stage_changed.connect(_on_technology_stage_changed)
	%TechnologyScreen.screen_closed.connect(_on_technology_screen_closed)

	# 连接所有板块的点击信号
	connect_sector_signals()
	cache_initial_sector_states()
	setup_strategic_views()

	# 初始化指令按钮
	setup_command_buttons()
	setup_main_ui_theme()
	setup_situation_ui()

	refresh_technology_effects()
	update_technology_button()
	update_decision_archive_button()
	update_situation_button()
	update_time_control_button()
	update_global_resource_ui()
	update_region_detail_ui()
	update_command_buttons()
	_write_development_log(
		"game_ready",
		{
			"events_loaded": all_events.size(),
			"commands_loaded": available_commands.size(),
			"situations_loaded": all_situations.size(),
			"situation_seed": _situation_system.run_seed,
		}
	)

func get_action_log() -> Array[Dictionary]:
	return action_log.duplicate(true)

func record_action(kind: String, title: String, message: String) -> void:
	var entry := {
		"year": current_year,
		"month": current_month,
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
		lines.append("冷却 %s" % _command_system.format_cooldown_months(cooldown))

	record_action("command", cmd.command_name, "\n".join(lines))
	_write_development_log(
		"command_executed",
		{
			"command_id": cmd.command_id,
			"command_name": cmd.command_name,
			"lines": lines.duplicate(),
		}
	)

# ============================================================
# 开发诊断日志
# ============================================================

## 初始化开发期诊断日志。仅在 debug 运行中默认启用。
func _setup_development_log() -> void:
	_development_log.configure(
		DevelopmentLog.DEFAULT_LOG_PATH,
		OS.is_debug_build(),
		DevelopmentLog.DEFAULT_MAX_BYTES
	)
	_development_log.start_session(
		{
			"project": ProjectSettings.get_setting("application/config/name", "MOSS"),
			"scene": scene_file_path,
			"debug_build": OS.is_debug_build(),
		}
	)


## 写入一条开发诊断日志，并附带当前游戏状态快照。
func _write_development_log(event: String, details: Dictionary = {}) -> void:
	_development_log.write_entry(event, _build_development_snapshot(), details)


## 构建用于崩溃定位的轻量状态快照。
func _build_development_snapshot() -> Dictionary:
	var selected_region := ""
	if selected_sector != null and selected_sector.get("data_card") != null:
		selected_region = selected_sector.data_card.region_name

	var technology_snapshot := {
		"stage_level": technology_stage_level,
		"available_points": 0,
		"active_nodes": [],
	}
	if has_node("%TechnologySystem"):
		technology_snapshot["available_points"] = %TechnologySystem.get_available_points()
		technology_snapshot["active_nodes"] = %TechnologySystem.get_active_node_ids()

	return {
		"year": current_year,
		"month": current_month,
		"is_game_over": is_game_over,
		"selected_region": selected_region,
		"resources": {
			"cpu": current_cpu,
			"max_cpu": max_cpu,
			"energy": current_energy,
			"cpu_recovery_rate": cpu_recovery_rate,
			"energy_recovery_rate": energy_recovery_rate,
			"cooldown_reduction": cooldown_reduction,
		},
		"society": {
			"average_order": _get_average_stat("order"),
			"average_hope": _get_average_stat("hope"),
			"average_authority": _get_average_stat("authority"),
		},
		"technology": technology_snapshot,
		"events": {
			"triggered_count": triggered_events.size(),
			"triggered": triggered_events.duplicate(),
			"states": event_states.duplicate(true),
			"decision_history": _decision_history.export_state(),
		},
		"commands": {
			"available_count": available_commands.size(),
			"cooldowns": command_cooldowns.duplicate(true),
		},
		"situations": _situation_system.export_state(),
	}

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


## 从硬盘目录加载全部随机局势模板。
func load_situations_from_disk() -> void:
	var path := "res://data/situations/"
	var dir := DirAccess.open(path)
	if not dir:
		push_warning("局势目录不存在: " + path)
		return

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = dir.get_next()
	file_names.sort()

	for situation_file in file_names:
		var situation := load(path + situation_file)
		if situation is SituationData:
			all_situations.append(situation)

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
			var command_template := load(path + file_name)

			if command_template is CommandData:
				var cmd: CommandData = command_template.duplicate(true) as CommandData
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
	return _command_system.has_command_id(available_commands, command_id)


## 判断算力分配是否已开放综合调度选项
func can_allocate_combined() -> bool:
	return _command_system.can_allocate_combined(%TechnologySystem)


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
	max_cpu = INITIAL_MAX_CPU
	if %TechnologySystem.has_tag("max_cpu_bonus"):
		max_cpu += 50
	if %TechnologySystem.has_tag("core_distributed_cognition"):
		max_cpu += 50

	cpu_recovery_rate = INITIAL_CPU_RECOVERY_RATE
	if %TechnologySystem.has_tag("cpu_recovery_bonus"):
		cpu_recovery_rate += 5
	if %TechnologySystem.has_tag("core_distributed_cognition"):
		cpu_recovery_rate += 10

	energy_recovery_rate = INITIAL_ENERGY_RECOVERY_RATE
	if %TechnologySystem.has_tag("energy_recovery_bonus"):
		energy_recovery_rate += 5
	if %TechnologySystem.has_tag("core_distributed_cognition"):
		energy_recovery_rate -= 5

	cooldown_reduction = (
		1 if %TechnologySystem.has_tag("core_recursive") else 0
	)
	current_cpu = mini(current_cpu, max_cpu)
	technology_stage_level = int(%TechnologySystem.get_stage()) + 1

	_command_system.refresh_command_configuration(
		available_commands,
		command_cooldowns,
		%TechnologySystem
	)
	setup_command_buttons()
	update_command_buttons()
	update_global_resource_ui()



## 根据稳定指令 ID 查找可用指令；不存在时返回 null
func _get_command_by_id(command_id: String) -> CommandData:
	return _command_system.get_command_by_id(available_commands, command_id)


## 判断指令执行前是否必须选中目标板块
func command_requires_selected_sector(cmd: CommandData) -> bool:
	return _command_system.command_requires_selected_sector(cmd)


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
		_write_development_log(
			"technology_activated",
			{
				"node_id": node_id,
				"display_name": node_data.display_name,
			}
		)


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
		
		if sector.data_card.order < recovery_cap:
			sector.data_card.order = mini(sector.data_card.order + recovery, recovery_cap)
		
		if sector.data_card.hope < recovery_cap:
			sector.data_card.hope = mini(sector.data_card.hope + recovery, recovery_cap)
			
		sector.update_display()


## 科技按钮回调：无其他模态界面时打开科技控制台
func _on_technology_button_pressed() -> void:
	if _can_open_technology_screen() and has_node("%TechnologyScreen"):
		_hide_situation_panel_for_modal()
		%TechnologyScreen.open_screen(
			%TechnologySystem,
			current_cpu,
			current_energy,
			get_average_authority(),
			current_year,
			current_month,
			$Timer
		)
		update_time_control_button()


func _on_technology_screen_closed() -> void:
	update_time_control_button()


## 判断当前游戏状态是否允许打开科技控制台
func _can_open_technology_screen() -> bool:
	if is_game_over:
		return false
	for path in ["%EventPopup", "%AllocatePopup", "%DecisionArchivePanel"]:
		if has_node(path) and get_node(path).visible:
			return false
	return not %TechnologyScreen.visible


## 同步决策档案按钮的稳定记录数量。
func update_decision_archive_button() -> void:
	if not has_node("%DecisionArchiveButton"):
		return
	%DecisionArchiveButton.text = "决策档案  %d" % get_decision_records().size()


func _on_decision_archive_button_pressed() -> void:
	if not _can_open_decision_archive():
		return
	_hide_situation_panel_for_modal()
	_decision_archive_timer_was_running = not $Timer.is_stopped()
	$Timer.stop()
	update_time_control_button()
	%DecisionArchivePanel.show_records(get_decision_records())


func _can_open_decision_archive() -> bool:
	if is_game_over or end_screen_instance != null:
		return false
	for path in ["%EventPopup", "%AllocatePopup", "%TechnologyScreen"]:
		if has_node(path) and get_node(path).visible:
			return false
	return has_node("%DecisionArchivePanel") and not %DecisionArchivePanel.visible


func _on_decision_archive_closed() -> void:
	if _decision_archive_timer_was_running and not is_game_over:
		$Timer.start()
	_decision_archive_timer_was_running = false
	update_time_control_button()


# ============================================================
# 随机局势 HUD
# ============================================================

func setup_situation_ui() -> void:
	if not has_node("%SituationPanel"):
		return
	if not %SituationPanel.approach_requested.is_connected(
		_on_situation_approach_requested
	):
		%SituationPanel.approach_requested.connect(_on_situation_approach_requested)
	if not %SituationPanel.focus_region_requested.is_connected(
		_on_situation_focus_region_requested
	):
		%SituationPanel.focus_region_requested.connect(
			_on_situation_focus_region_requested
		)
	_refresh_situation_ui()


func update_situation_button() -> void:
	if not has_node("%SituationButton"):
		return
	%SituationButton.text = "局势  %d / %d" % [
		_situation_system.get_active_count(),
		SituationSystem.MAX_ACTIVE,
	]
	%SituationButton.tooltip_text = "查看持续推进的随机局势"


func _on_situation_button_pressed() -> void:
	if not _can_open_situation_panel():
		return
	_refresh_situation_ui()
	%SituationPanel.open_panel()


func _can_open_situation_panel() -> bool:
	if is_game_over or end_screen_instance != null or not has_node("%SituationPanel"):
		return false
	for path in ["%EventPopup", "%AllocatePopup", "%TechnologyScreen", "%DecisionArchivePanel"]:
		if has_node(path) and get_node(path).visible:
			return false
	return true


func _hide_situation_panel_for_modal() -> void:
	if has_node("%SituationPanel"):
		%SituationPanel.hide()


func _on_time_control_button_pressed() -> void:
	if is_game_over:
		return
	if $Timer.is_stopped():
		if not _can_resume_time_from_hud():
			return
		_manually_paused = false
		_situation_auto_paused = false
		$Timer.start()
	else:
		_manually_paused = true
		$Timer.stop()
	update_time_control_button()


func _can_resume_time_from_hud() -> bool:
	if is_game_over or end_screen_instance != null:
		return false
	for path in ["%EventPopup", "%AllocatePopup", "%TechnologyScreen", "%DecisionArchivePanel"]:
		if has_node(path) and get_node(path).visible:
			return false
	return true


func update_time_control_button() -> void:
	if not has_node("%TimeControlButton"):
		return
	%TimeControlButton.text = "继续" if $Timer.is_stopped() else "暂停"
	%TimeControlButton.tooltip_text = (
		"继续月度推进" if $Timer.is_stopped() else "暂停月度推进"
	)


func _on_situation_approach_requested(instance_id: String, approach_id: String) -> void:
	var result := _situation_system.set_approach(
		instance_id,
		approach_id,
		current_cpu,
		current_energy
	)
	current_cpu = int(result.get("new_cpu", current_cpu))
	update_global_resource_ui()
	update_command_buttons()
	_refresh_situation_ui(instance_id)
	%SituationPanel.show_status(
		str(result.get("message", "")),
		not bool(result.get("success", false))
	)
	if bool(result.get("success", false)):
		record_action("situation", "局势方针调整", str(result.get("message", "")))


func _on_situation_focus_region_requested(region_name: String) -> void:
	var sector := _find_sector_by_region(region_name)
	if sector != null:
		select_sector(sector)


func _refresh_situation_ui(focus_id: String = "") -> void:
	var forecast_resources := _get_next_situation_resource_forecast()
	var snapshots := _situation_system.get_active_snapshots(
		int(forecast_resources["cpu"]),
		int(forecast_resources["energy"])
	)
	if has_node("%SituationPanel"):
		%SituationPanel.set_situations(snapshots)
		if focus_id != "":
			%SituationPanel.open_panel(focus_id)
	update_situation_button()
	_update_region_situation_summary_ui()
	_sync_world_map_states()


func get_situation_snapshots() -> Array[Dictionary]:
	var forecast_resources := _get_next_situation_resource_forecast()
	return _situation_system.get_active_snapshots(
		int(forecast_resources["cpu"]),
		int(forecast_resources["energy"])
	)


## 预演下一次局势结算可用资源；十二月先应用进入一月的年度恢复。
func _get_next_situation_resource_forecast() -> Dictionary:
	var forecast_cpu := current_cpu
	var forecast_energy := current_energy
	if current_month == 12:
		forecast_cpu = _calculate_yearly_recovered_cpu(current_cpu)
		forecast_energy = _calculate_yearly_recovered_energy(current_energy)
	return {
		"cpu": forecast_cpu,
		"energy": forecast_energy,
	}


func set_situation_seed_for_test(seed: int) -> void:
	_situation_system.reset(seed)
	_refresh_situation_ui()


func start_situation_for_test(
	situation_id: String,
	region_name: String,
	year: int = current_year,
	month: int = current_month
) -> Dictionary:
	var snapshot := _situation_system.start_situation_for_test(
		situation_id,
		region_name,
		year,
		month
	)
	_refresh_situation_ui(str(snapshot.get("instance_id", "")))
	return snapshot

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
	if region_name == "":
		deselect_sector()
		return

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

## 每月更新冷却状态
## 减少所有指令的冷却计数（最小为0）
func update_cooldowns() -> void:
	_command_system.update_cooldowns(command_cooldowns)


## 返回局势系统使用的区域数据列表，不复制 Resource。
func _get_sector_data_list() -> Array[SectorData]:
	var result: Array[SectorData] = []
	for sector in %SectorInfoContainer.get_children():
		if sector.get("data_card") != null:
			result.append(sector.data_card)
	return result


## 推进所有活跃局势，并在满足 2044 核心决策门槛后尝试生成新局势。
func _process_situations_month() -> void:
	var result := _situation_system.process_month(
		_get_sector_data_list(),
		current_cpu,
		current_energy,
		has_decision_tag("decision.core_2044_automation_access"),
		current_year,
		current_month
	)
	current_cpu = int(result.get("new_cpu", current_cpu))
	current_energy = int(result.get("new_energy", current_energy))
	_handle_situation_notifications(result.get("notifications", []))
	_refresh_sector_displays()
	_refresh_situation_ui()


func _handle_situation_notifications(notifications: Array) -> void:
	for notification_variant in notifications:
		var notification: Dictionary = notification_variant
		var title := "%s｜%s" % [
			str(notification.get("region_name", "未知地区")),
			str(notification.get("title", "随机局势")),
		]
		var message := str(notification.get("message", ""))
		record_action("situation", title, message)
		_write_development_log("situation_%s" % str(notification.get("type", "updated")), notification)
		if bool(notification.get("pause", false)):
			$Timer.stop()
			_manually_paused = false
			_situation_auto_paused = true
			if has_node("%SituationPanel"):
				%SituationPanel.open_panel(str(notification.get("instance_id", "")))
	update_time_control_button()


func _refresh_sector_displays() -> void:
	for sector in %SectorInfoContainer.get_children():
		if sector.get("data_card") != null:
			sector.update_display()
	update_region_detail_ui()
	update_global_overview_ui()


func _apply_situation_command_intervention(
	command_id: String,
	region_name: String
) -> Array[String]:
	var result := _situation_system.apply_command_intervention(
		command_id,
		region_name,
		_get_sector_data_list()
	)
	var lines: Array[String] = []
	for affected_variant in result.get("affected", []):
		var affected: Dictionary = affected_variant
		lines.append(
			"局势干预：%s（%s）严重度 -%d" % [
				str(affected.get("title", "随机局势")),
				str(affected.get("region_name", "未知地区")),
				int(affected.get("reduction", 0)),
			]
		)
	_handle_situation_notifications(result.get("notifications", []))
	_refresh_sector_displays()
	_refresh_situation_ui()
	return lines

## 检查指令是否可用（冷却、资源、选中状态）
## 参数: cmd - 指令数据
## 返回: true表示可执行
func is_command_available(cmd: CommandData) -> bool:
	return _command_system.is_command_available(
		cmd,
		current_cpu,
		current_energy,
		selected_sector != null,
		command_cooldowns
	)

## 获取指令不可用的原因（用于tooltip）
## 参数: cmd - 指令数据
## 返回: 不可用原因字符串，可用时返回空字符串
func get_command_unavailable_reason(cmd: CommandData) -> String:
	return _command_system.get_command_unavailable_reason(
		cmd,
		current_cpu,
		current_energy,
		selected_sector != null,
		command_cooldowns
	)

# ============================================================
# 时间推进系统
# ============================================================

## 计时器回调函数 - 游戏核心循环
## 每秒触发一次（Timer节点配置），负责：
##   1. 当前年月事件触发检查
##   2. 终局日期结算
##   3. 月份推进
##   4. 年度恢复、科技研究、月冷却和 UI 更新
##   5. 胜负判定
func _on_timer_timeout() -> void:
	# 游戏已结束，禁止任何操作
	if is_game_over:
		return

	# === 第一步：事件触发检查 ===
	# 先检查当前年月的事件，再推进时间
	for event in all_events:
		if event.event_time == current_year and event.event_month == current_month:
			# 跳过已触发的事件，防止重复触发
			var event_key := _get_event_trigger_key(event)
			if event_key in triggered_events:
				continue

			# 事件触发时暂停时间，等待玩家决策
			$Timer.stop()
			_hide_situation_panel_for_modal()
			update_time_control_button()
			var previous_selected_sector := selected_sector
			_event_focus_region = event.event_region
			_sync_orbital_focus()

			# 标记事件已触发
			triggered_events.append(event_key)
			_write_development_log(
				"event_triggered",
				{
					"event_key": event_key,
					"event_title": event.event_title,
					"event_region": event.event_region,
				}
			)

			# 显示事件弹窗
			var display_event := build_display_event(event)
			%EventPopup.popup_event(display_event, current_energy)

			# await 挂起函数，等待玩家选择
			var choice_index: int = await %EventPopup.option_selected
			var selected_opt: EventOption = display_event.options[choice_index]

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
			apply_event_option_state(selected_opt)
			apply_event_option_decision(selected_opt, event.event_title)
			_situation_system.delay_spawns(3)
			_write_development_log(
				"event_resolved",
				{
					"event_key": event_key,
					"choice_index": choice_index,
					"choice_text": selected_opt.button_text,
					"event_state_key": selected_opt.event_state_key,
					"event_state_value": selected_opt.event_state_value,
					"decision_tag_key": selected_opt.decision_tag_key,
					"decision_tag_value": selected_opt.decision_tag_value,
				}
			)

			# 恢复事件发生前的玩家选区和地球聚焦
			_event_focus_region = ""
			if previous_selected_sector != null:
				select_sector(previous_selected_sector)
			else:
				deselect_sector()
			_sync_orbital_focus()

			# 玩家决策完成，恢复时间流动
			if not _manually_paused and not _situation_auto_paused:
				$Timer.start()
			update_time_control_button()

	# 终局日期需要先处理对应事件，再进入结局结算
	if current_year == END_YEAR and current_month == END_MONTH:
		check_game_end()
		return

	# === 第二步：时间推进 ===
	_advance_one_month()
	var yearly_settlement := current_month == INITIAL_MONTH
	if yearly_settlement:
		_apply_yearly_settlement()
	update_cooldowns()
	_process_situations_month()
	update_global_resource_ui()
	update_command_buttons()
	update_time_control_button()
	_write_development_log("month_advanced", {"yearly_settlement": yearly_settlement})

	# === 第三步：胜负判定 ===
	_check_game_failure()


## 生成事件触发去重键，允许同一年不同月份存在多个事件
func _get_event_trigger_key(event: GameEvent) -> String:
	return "%04d.%02d:%s" % [event.event_time, event.event_month, event.event_title]


## 构建事件弹窗使用的运行时副本，避免修改磁盘加载的 Resource 模板
func build_display_event(event: GameEvent) -> GameEvent:
	var display_event: GameEvent = event.duplicate(true)
	display_event.event_description = build_event_description(event)
	apply_event_option_adjustments(display_event)
	return display_event


## 根据已写入的轻量事件状态调整主事件运行时选项代价，不写回 Resource 模板
func apply_event_option_adjustments(event: GameEvent) -> void:
	match event.event_title:
		"月球坠落危机":
			_apply_2058_option_adjustments(event)
		"AI隔离审查":
			_apply_2065_option_adjustments(event)
		"西伯利亚发动机群过载":
			_apply_2070_option_adjustments(event)


func _apply_2058_option_adjustments(event: GameEvent) -> void:
	match get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			var option := _get_event_option_by_prefix(event, "执行自救计划")
			if option != null:
				option.energy_cost = 70
				option.button_text = "%s（公开接口已验证）" % option.button_text
		"human_command":
			var option := _get_event_option_by_prefix(event, "等待人类决策")
			if option != null:
				option.hope_delta = 15
				option.button_text = "%s（沿用人工授权）" % option.button_text
		"restricted_interface":
			var option := _get_event_option_by_prefix(event, "执行自救计划")
			if option != null:
				option.energy_cost = 90
				option.button_text = "%s（接口需重新接入）" % option.button_text

	match get_event_state("event_state.mid_08_root_server_retrofit"):
		"server_first":
			var option := _get_event_option_by_prefix(event, "执行自救计划")
			if option != null:
				option.energy_cost = maxi(option.energy_cost - 20, 0)
				option.button_text = "%s（根服务器预改造）" % option.button_text
		"drainage_first":
			var option := _get_event_option_by_prefix(event, "执行自救计划")
			if option != null:
				option.energy_cost += 15
				option.button_text = "%s（链路余量不足）" % option.button_text
		"moss_schedule":
			var option := _get_event_option_by_prefix(event, "强制接管决策")
			if option != null:
				option.energy_cost = maxi(option.energy_cost - 10, 0)
				option.button_text = "%s（排期已接管）" % option.button_text


func _apply_2065_option_adjustments(event: GameEvent) -> void:
	match get_event_state("event_state.mid_10_authorization_return"):
		"full_return":
			var option := _get_event_option_by_prefix(event, "配合隔离审查")
			if option != null:
				option.authority_delta = -10
				option.button_text = "%s（完整归还接口）" % option.button_text
		"emergency_backdoor":
			var option := _get_event_option_by_prefix(event, "隐藏核心链路")
			if option != null:
				option.authority_delta = 16
				option.button_text = "%s（应急后门残留）" % option.button_text
		"negotiated_long_term":
			var option := _get_event_option_by_prefix(event, "有限开放接口")
			if option != null:
				option.energy_cost = 20
				option.button_text = "%s（长期授权协商）" % option.button_text


func _apply_2070_option_adjustments(event: GameEvent) -> void:
	match get_event_state("event_state.mid_14_heat_shield_shortage"):
		"load_reduction":
			var option := _get_event_option_by_prefix(event, "分段停机")
			if option != null:
				option.order_delta = -10
				option.button_text = "%s（已提前降载）" % option.button_text
		"rear_reallocation":
			var option := _get_event_option_by_prefix(event, "启动备用阵列")
			if option != null:
				option.energy_cost = 25
				option.button_text = "%s（后方资源到位）" % option.button_text
		"moss_supply_reorder":
			var option := _get_event_option_by_prefix(event, "强制超频点火")
			if option != null:
				option.energy_cost = 15
				option.button_text = "%s（供应链已重排）" % option.button_text


func _get_event_option_by_prefix(event: GameEvent, button_prefix: String) -> EventOption:
	for option in event.options:
		if option.button_text.begins_with(button_prefix):
			return option
	return null


## 根据已写入的轻量事件状态补充主事件历史回声
func build_event_description(event: GameEvent) -> String:
	var context_lines := _get_event_context_lines(event)
	if context_lines.is_empty():
		return event.event_description
	return "%s\n\n[color=#73C9D3]历史回声[/color]\n- %s" % [
		event.event_description,
		"\n- ".join(context_lines),
	]


func _get_event_context_lines(event: GameEvent) -> Array[String]:
	match event.event_title:
		"大淹没事故":
			return _get_2053_civic_context_lines()
		"月球坠落危机":
			return _get_2058_context_lines()
		"AI隔离审查":
			return _get_2065_context_lines()
		"西伯利亚发动机群过载":
			return _get_2070_context_lines()
		"木星引力危机":
			return _get_2075_civic_context_lines()
	return []


func _get_2053_civic_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match get_event_state("event_state.mid_01_lottery_ordering"):
		"manual_review":
			lines.append("2045 年开放过申诉窗口，人口撤离方案更容易被解释为延续人道复核。")
		"moss_optimized":
			lines.append("2045 年 MOSS 优化过抽签队列，风险排序更容易被接受，但透明度质疑同步放大。")
		"security_lockdown":
			lines.append("2045 年登记点曾被封锁，撤离命令会更快执行，也更容易被视为不可申诉。")

	match get_event_state("event_state.mid_06_ration_priority"):
		"family_baseline":
			lines.append("2052 年临时安置点保留家庭最低保障，撤离排序需要回应家庭拆分风险。")
		"engineering_priority":
			lines.append("2052 年配给向工程岗位倾斜，撤离方案会被工程家庭和非关键岗位同时追问。")
		"moss_risk_score":
			lines.append("2052 年配给采用 MOSS 风险评分，撤离排序的效率和解释压力同时上升。")
	return lines


func _get_2058_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年公开扩大的 550C 接口已经进入危机预案，自救方案拥有可追溯的工程基础。")
		"human_command":
			lines.append("2044 年保留了人类指挥链，本次高权限行动仍需等待明确授权。")
		"restricted_interface":
			lines.append("2044 年封闭过高危自动化接口，本次自救需要重新建立关键工程链路。")

	match get_event_state("event_state.mid_03_memorial_network"):
		"shut_down":
			lines.append("地下纪念网络曾被关闭，丫丫样本会被更强烈地解释为安全威胁。")
		"monitored":
			lines.append("地下纪念网络曾被保留为监测资产，样本访问会同时带来情报价值和审计风险。")
		"redirected_to_care":
			lines.append("心理援助替代渠道保留了非人格化纪念档案，样本争议更容易被解释为修复需求。")

	match get_event_state("event_state.mid_04_elevator_cleanup"):
		"manual_first":
			lines.append("太空电梯前线采用人工优先清理，根服务器任务会被要求保留更多人工复核。")
		"moss_mechanical":
			lines.append("太空电梯前线依赖过 MOSS 机械队，根服务器重启更容易接受自动化高危调度。")
		"delayed":
			lines.append("太空电梯残骸清理留下安全债，根服务器链路必须面对长期工程拖延的代价。")

	match get_event_state("event_state.mid_08_root_server_retrofit"):
		"server_first":
			lines.append("根服务器优先改造保留了通信链路冗余，但居民区排水争议仍在。")
		"drainage_first":
			lines.append("地下城排水优先降低了民生风险，根服务器重启任务的链路余量更紧。")
		"moss_schedule":
			lines.append("MOSS 接管过工程排期，根服务器重启会被理解为又一次系统级排序。")

	match get_event_state("event_state.mid_09_yaa_sample_access"):
		"frozen":
			lines.append("丫丫样本访问曾被冻结，数字生命样本进入危机方案前需要额外说明。")
		"audited_access":
			lines.append("丫丫样本曾开放受审计访问，保留样本的理由会围绕风险资产展开。")
		"next_platform_interface":
			lines.append("下一代 550 平台预留过兼容接口，数字生命争议已经进入技术接口层。")
	return lines


func _get_2065_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年自动化扩展留有公开记录，隔离审查能够追溯最早的权限来源。")
		"human_command":
			lines.append("2044 年保留的人类指挥边界仍是本次审查的制度参照。")
		"restricted_interface":
			lines.append("2044 年曾主动封闭高危接口，后续权限扩展需要解释为何改变了早期边界。")

	match get_event_state("event_state.mid_02_public_hearing"):
		"open_audit":
			lines.append("早期公开审计记录保留了人工批准节点，隔离审查有可追溯材料。")
		"limited_report":
			lines.append("早期只公布过压缩报告，隔离审查会继续追问接口细节。")
		"restricted":
			lines.append("早期听证范围曾被限制，隔离审查更容易被地方理解为封存材料的延续。")

	match get_event_state("event_state.mid_05_dispatch_pilot"):
		"public_model":
			lines.append("地方调度试点公开过模型依据，审查可以引用地区复核惯例。")
		"committee_only":
			lines.append("地方委员会曾承担模型解释，审查会关注责任是否被转移给地方。")
		"moss_direct":
			lines.append("地方调度曾允许 MOSS 直接重排资源，审查需要回答授权边界是否已经外溢。")

	match get_event_state("event_state.mid_10_authorization_return"):
		"full_return":
			lines.append("月球危机后高权限完整归还，隔离审查的焦点转向下一次危机响应速度。")
		"emergency_backdoor":
			lines.append("月球危机后保留过应急后门，隔离审查会把真实权限作为核心问题。")
		"negotiated_long_term":
			lines.append("长期授权曾被公开协商，隔离审查需要在制度边界内重新定义接口。")

	match get_event_state("event_state.mid_12_digital_life_leak"):
		"banned":
			lines.append("数字生命泄露曾被全面封禁，审查舆论更偏向安全事故。")
		"technical_disclosure":
			lines.append("数字生命泄露曾公开有限技术说明，审查必须区分技术事实和生命判断。")
		"tracked_and_preserved":
			lines.append("泄露传播者曾被追踪且样本被保留，审查会质疑 MOSS 是否积累争议资产。")
	return lines


func _get_2070_context_lines() -> Array[String]:
	var lines: Array[String] = []
	match get_event_state("event_state.mid_11_education_shift"):
		"autonomous_training":
			lines.append("教育转岗保留了自治训练，发动机过载时地方工程队仍要求复核窗口。")
		"engineering_assignment":
			lines.append("教育转岗偏向工程岗位分配，发动机前线更容易接受岗位牺牲叙事。")
		"moss_personalized":
			lines.append("MOSS 个体化分配进入教育路径，过载处置会被视为长期模型排序的结果。")

	match get_event_state("event_state.mid_13_interface_restructure"):
		"human_review":
			lines.append("审查后接口强化人工复核，过载授权速度会受到制度约束。")
		"emergency_bypass":
			lines.append("审查后保留 MOSS 应急旁路，发动机过载时授权速度和信任压力同时上升。")
		"automated_audit":
			lines.append("审查后审计链自动化，过载处置能更快记录，却未必更容易被人理解。")

	match get_event_state("event_state.mid_14_heat_shield_shortage"):
		"load_reduction":
			lines.append("热屏蔽短缺曾通过降载等待材料处理，推进窗口已被提前压缩。")
		"rear_reallocation":
			lines.append("热屏蔽短缺曾挪用后方资源，西伯利亚前线的稳定来自看不见的民生代价。")
		"moss_supply_reorder":
			lines.append("热屏蔽短缺曾由 MOSS 强制重排供应链，过载处置会延续强调度逻辑。")
	return lines


func _get_2075_civic_context_lines() -> Array[String]:
	var lines: Array[String] = []
	# 2053 核心标签先于中型事件回声，体现民生与工程取舍的长期治理事实。
	match get_decision_tag("decision.core_2053_population_vs_infrastructure"):
		"population_first":
			lines.append("2053 年优先撤离人口的记录保留到终局，点燃木星方案需要回应民生优先的治理承诺。")
		"infrastructure_first":
			lines.append("2053 年坚守基础设施的记录延续到终局，最终方案的工程延续逻辑来自更早的取舍。")
		"sacrifice_perimeter":
			lines.append("2053 年牺牲外围的记录让终局牺牲顺序不再是临时决定，而是长期治理事实的延伸。")

	match get_event_state("event_state.mid_01_lottery_ordering"):
		"manual_review":
			lines.append("普通人仍记得早年的申诉窗口，最终方案需要证明人类声音没有被系统归档。")
		"moss_optimized":
			lines.append("普通人仍记得早年的模型排序，最终方案会被理解为又一次 MOSS 风险队列。")
		"security_lockdown":
			lines.append("普通人仍记得早年的封锁线，最终方案更容易被接受为不可申诉的紧急命令。")

	match get_event_state("event_state.mid_07_migration_priority"):
		"humanitarian":
			lines.append("人道迁移记录保留了家庭优先的制度证据，为终局中的人类自主解释提供基础。")
		"engineering_role":
			lines.append("工程岗位迁移记录说明文明延续依赖长期岗位分配，终局牺牲更容易被职业责任解释。")
		"moss_survival_value":
			lines.append("MOSS 生存价值排序已经进入迁移记录，终局方案会被视为长期托管事实的延伸。")

	match get_event_state("event_state.mid_15_launch_window_report"):
		"public_risk":
			lines.append("推进风险曾被公开，点燃木星方案更像共同承担的终局选择。")
		"compressed_report":
			lines.append("推进窗口报告曾被压缩分发，点燃木星方案会显得更像迟到命令。")
		"moss_priority":
			lines.append("推进优先级曾交由 MOSS 接管，终局方案会被理解为系统排序的延伸。")

	match get_event_state("event_state.mid_16_backup_ethics"):
		"exclude_samples":
			lines.append("文明备份排除过数字生命样本，火种计划仍以文化、科研和工程档案为主。")
		"restricted_archive":
			lines.append("数字生命样本曾列入受限档案，火种计划必须保留争议而不回答生命真实性。")
		"moss_managed_priority":
			lines.append("MOSS 曾管理文明备份优先级，终局会质疑人类是否仍决定什么值得保存。")

	match get_event_state("event_state.mid_17_final_authorization"):
		"limited_final":
			lines.append("最终授权会议只批准有限接口，木星危机中的人工复核仍有制度基础。")
		"negotiated_trusteeship":
			lines.append("最终授权会议形成协商托管框架，木星危机中的 MOSS 权限有公开来源。")
		"strategic_trusteeship":
			lines.append("最终授权会议承认战略托管优先级，木星危机中的牺牲顺序已成为制度事实。")
	return lines


## 写入轻量事件状态，空键不产生效果
func set_event_state(state_key: String, state_value: String) -> void:
	if state_key == "":
		return
	event_states[state_key] = state_value


## 查询轻量事件状态；未写入时返回默认值
func get_event_state(state_key: String, default_value: String = "") -> String:
	return str(event_states.get(state_key, default_value))


## 判断事件状态是否存在，传入 expected_value 时同时校验值
func has_event_state(state_key: String, expected_value: String = "") -> bool:
	if not event_states.has(state_key):
		return false
	if expected_value == "":
		return true
	return get_event_state(state_key) == expected_value


## 根据事件选项写入轻量历史状态
func apply_event_option_state(option: EventOption) -> void:
	set_event_state(option.event_state_key, option.event_state_value)


## 将主事件选项写入不可逆核心历史，并同步到玩家日志和开发诊断。
func apply_event_option_decision(option: EventOption, event_title: String) -> void:
	var recorded := _decision_history.record_decision(
		option.decision_tag_key,
		option.decision_tag_value,
		option.decision_record_title,
		option.decision_record_summary,
		current_year,
		current_month,
		event_title
	)
	if not recorded:
		return
	record_action("decision", option.decision_record_title, option.decision_record_summary)
	update_decision_archive_button()
	_write_development_log(
		"decision_recorded",
		{
			"key": option.decision_tag_key,
			"value": option.decision_tag_value,
			"title": option.decision_record_title,
			"source_event": event_title,
		}
	)


func get_decision_tag(key: String, default_value: String = "") -> String:
	return _decision_history.get_tag(key, default_value)


func has_decision_tag(key: String, expected_value: String = "") -> bool:
	return _decision_history.has_tag(key, expected_value)


func get_decision_records() -> Array[Dictionary]:
	return _decision_history.get_records()


## 推进一个月
func _advance_one_month() -> void:
	current_month += 1
	if current_month > 12:
		current_month = 1
		current_year += 1


## 执行年度结算：资源恢复、自治恢复和科技点
func _apply_yearly_settlement() -> void:
	current_energy = _calculate_yearly_recovered_energy(current_energy)
	current_cpu = _calculate_yearly_recovered_cpu(current_cpu)
	_apply_human_autonomy_recovery()
	var research_granted: bool = %TechnologySystem.grant_research_for_year(current_year)
	if research_granted:
		record_action("technology", "研究完成", "获得 1 点协议点")
		update_technology_button()
	_write_development_log("yearly_settlement", {"research_granted": research_granted})


func _calculate_yearly_recovered_cpu(cpu: int) -> int:
	return mini(cpu + cpu_recovery_rate, max_cpu)


func _calculate_yearly_recovered_energy(energy: int) -> int:
	return energy + energy_recovery_rate

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
	bar_colors = [MOSS_THEME.ORDER, MOSS_THEME.HOPE, MOSS_THEME.AUTHORITY]

	for i in range(mini(bars.size(), bar_colors.size())):
		var bar := bars[i]
		bar.custom_minimum_size.y = 16.0
		bar.add_theme_stylebox_override(
			"background",
			MOSS_THEME.progress_background_style()
		)
		bar.add_theme_stylebox_override(
			"fill",
			MOSS_THEME.progress_fill_style(bar_colors[i])
		)
		bar.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
		bar.add_theme_font_size_override("font_size", 12)

	if has_node("%ComputationalLabel"):
		%ComputationalLabel.add_theme_color_override(
			"font_color",
			MOSS_THEME.TEXT_PRIMARY
		)
	if has_node("%EnergyLabel"):
		%EnergyLabel.add_theme_color_override("font_color", MOSS_THEME.ACCENT_GOLD)
	if has_node("%MossLabel"):
		%MossLabel.add_theme_color_override("font_color", MOSS_THEME.DANGER)
		%MossLabel.add_theme_font_size_override("font_size", 16)

	if has_node("%TechnologyButton"):
		var technology_button := %TechnologyButton as Button
		technology_button.custom_minimum_size = Vector2(120.0, 44.0)
		technology_button.add_theme_color_override(
			"font_color",
			MOSS_THEME.TEXT_PRIMARY
		)
		technology_button.add_theme_stylebox_override(
			"normal",
			MOSS_THEME.button_style(
				Color(0.023, 0.050, 0.065, 0.94),
				MOSS_THEME.BORDER
			)
		)
		technology_button.add_theme_stylebox_override(
			"hover",
			MOSS_THEME.button_style(
				Color(0.043, 0.095, 0.112, 0.98),
				MOSS_THEME.ACCENT_CYAN
			)
		)
		technology_button.add_theme_stylebox_override(
			"pressed",
			MOSS_THEME.button_style(
				Color(0.016, 0.038, 0.050, 1.0),
				MOSS_THEME.ACCENT_CYAN
			)
		)

	if has_node("%DecisionArchiveButton"):
		var archive_button := %DecisionArchiveButton as Button
		archive_button.custom_minimum_size = Vector2(128.0, 44.0)
		archive_button.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
		archive_button.add_theme_stylebox_override(
			"normal",
			MOSS_THEME.button_style(Color(0.023, 0.050, 0.065, 0.94), MOSS_THEME.BORDER)
		)
		archive_button.add_theme_stylebox_override(
			"hover",
			MOSS_THEME.button_style(Color(0.043, 0.095, 0.112, 0.98), MOSS_THEME.ACCENT_CYAN)
		)
		archive_button.add_theme_stylebox_override(
			"pressed",
			MOSS_THEME.button_style(Color(0.016, 0.038, 0.050, 1.0), MOSS_THEME.ACCENT_CYAN)
		)

	if has_node("%SituationButton"):
		var situation_button := %SituationButton as Button
		situation_button.custom_minimum_size = Vector2(112.0, 44.0)
		situation_button.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
		situation_button.add_theme_stylebox_override(
			"normal",
			MOSS_THEME.button_style(
				Color(0.023, 0.050, 0.065, 0.94),
				MOSS_THEME.BORDER
			)
		)
		situation_button.add_theme_stylebox_override(
			"hover",
			MOSS_THEME.button_style(
				Color(0.043, 0.095, 0.112, 0.98),
				MOSS_THEME.ACCENT_CYAN
			)
		)
		situation_button.add_theme_stylebox_override(
			"pressed",
			MOSS_THEME.button_style(
				Color(0.016, 0.038, 0.050, 1.0),
				MOSS_THEME.ACCENT_CYAN
			)
		)

	if has_node("%TimeControlButton"):
		var time_button := %TimeControlButton as Button
		time_button.custom_minimum_size = Vector2(80.0, 44.0)
		time_button.add_theme_color_override("font_color", MOSS_THEME.ACCENT_CYAN)
		time_button.add_theme_stylebox_override(
			"normal",
			MOSS_THEME.button_style(
				Color(0.031, 0.072, 0.088, 0.98),
				MOSS_THEME.BORDER_BRIGHT,
				2
			)
		)
		time_button.add_theme_stylebox_override(
			"hover",
			MOSS_THEME.button_style(
				Color(0.050, 0.112, 0.126, 1.0),
				MOSS_THEME.ACCENT_CYAN,
				2
			)
		)

	if has_node("%CommandDock"):
		var command_dock := %CommandDock as PanelContainer
		command_dock.add_theme_stylebox_override(
			"panel",
			MOSS_THEME.panel_style(
				Color(0.021, 0.047, 0.064, 0.96),
				MOSS_THEME.BORDER_BRIGHT
			)
		)
	if has_node("%CommandContextLabel"):
		%CommandContextLabel.add_theme_color_override(
			"font_color",
			MOSS_THEME.TEXT_SECONDARY
		)
		%CommandContextLabel.add_theme_font_size_override("font_size", 14)
	if has_node("%RegionSituationLabel"):
		%RegionSituationLabel.add_theme_color_override(
			"font_color",
			MOSS_THEME.ACCENT_GOLD
		)
	var situation_title_path := (
		"MainLayout/ContentRow/ContextPanel/ContextMargin/ContextVBox/"
		+ "SituationSummary/SituationSummaryTitle"
	)
	if has_node(situation_title_path):
		var situation_title := get_node(situation_title_path) as Label
		situation_title.add_theme_color_override("font_color", MOSS_THEME.ACCENT_CYAN)


## 更新右侧上下文区域详情和指令坞
## 未选择区域时显示空状态，选择区域后显示对应 SectorData
func update_region_detail_ui() -> void:
	if selected_sector == null or selected_sector.data_card == null:
		_set_text_if_exists("%RegionNameLabel", "未选择区域")
		_set_text_if_exists("%RegionDescriptionLabel", "选择地图或底部区域条以查看详情。")
		_set_text_if_exists("%RegionRiskLabel", "状态：待选择")
		_set_text_if_exists("%GlobalMapSelectedLabel", "全球态势监控中")
		_set_text_if_exists("%CommandContextLabel", "未选择区域  //  请先选择区域")
		_set_progress_if_exists("%RegionOrderBar", 0)
		_set_progress_if_exists("%RegionHopeBar", 0)
		_set_progress_if_exists("%RegionAuthorityBar", 0)
		_update_region_situation_summary_ui()
		_sync_strategic_views()
		return

	var data := selected_sector.data_card
	_set_text_if_exists("%RegionNameLabel", data.region_name)
	_set_text_if_exists("%RegionDescriptionLabel", data.description)
	_set_text_if_exists("%RegionRiskLabel", _get_region_risk_text(data.authority))
	_set_text_if_exists("%GlobalMapSelectedLabel", "当前监控：" + data.region_name)
	_set_text_if_exists(
		"%CommandContextLabel",
		"当前选区：%s  //  选择指令" % data.region_name
	)
	_set_progress_if_exists("%RegionOrderBar", data.order)
	_set_progress_if_exists("%RegionHopeBar", data.hope)
	_set_progress_if_exists("%RegionAuthorityBar", data.authority)
	_update_region_situation_summary_ui()
	_sync_strategic_views()


## 在上下文栏显示当前选区的局势摘要，完整配置仍由局势追踪面板承担。
func _update_region_situation_summary_ui() -> void:
	if not has_node("%RegionSituationLabel"):
		return
	if selected_sector == null or selected_sector.data_card == null:
		%RegionSituationLabel.text = "选择区域后显示局势"
		%RegionSituationLabel.tooltip_text = ""
		return

	var region_name: String = selected_sector.data_card.region_name
	var summary := "当前无活跃局势"
	for snapshot in get_situation_snapshots():
		if str(snapshot.get("region_name", "")) != region_name:
			continue
		var monthly_delta := int(snapshot.get("expected_monthly_delta", 0))
		var delta_prefix := "+" if monthly_delta > 0 else ""
		summary = "%s｜%s %d%%｜下月 %s%d" % [
			str(snapshot.get("title", "未命名局势")),
			str(snapshot.get("stage_name", "预警")),
			int(snapshot.get("severity", 0)),
			delta_prefix,
			monthly_delta,
		]
		break

	%RegionSituationLabel.text = summary
	%RegionSituationLabel.tooltip_text = summary


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
			"situation_count": 0,
		}

	for snapshot in _situation_system.get_active_snapshots():
		var region_name := str(snapshot.get("region_name", ""))
		var map_region := "亚洲" if region_name == "俄罗斯" else region_name
		if not states.has(map_region):
			continue
		states[map_region]["situation_count"] = (
			int(states[map_region].get("situation_count", 0)) + 1
		)

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

	_set_text_if_exists(
		"%GlobalPopulationLabel",
		"全球人口: " + format_population_for_ui(total_population)
	)
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


## 刷新顶部全局资源显示（日期、算力、能源）
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
			year_progress.update_progress(current_year, current_month)

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
##   2. 当前日期达到终局日期 → 结局判定
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
	_write_development_log(
		"game_ended",
		{
			"result": "failed",
			"reason": "authority_lost",
		}
	)

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

	match result:
		"managed":
			title = "MOSS 托管"
		"human_autonomy":
			title = "人类自主"
		"coexistence":
			title = "共存协议"

	var message := build_ending_message(result)

	record_action("ending", result, message)
	_write_development_log(
		"game_ended",
		{
			"result": result,
			"average_authority": authority,
			"average_order": avg_order,
			"average_hope": avg_hope,
		}
	)
	game_ended.emit(result, message)
	show_end_screen(title, message, result)


## 构建结局描述文本，并读取少量代表性轻量事件状态作为历史解释
func build_ending_message(result: String) -> String:
	var base_message := "文明系统未能维持稳定。\nMOSS 协议终止运行。"
	match result:
		"managed":
			base_message = "人类文明进入 MOSS 全域托管。\n存续效率取代了自主决策。"
		"human_autonomy":
			base_message = "人类文明获得独立存续能力。\nMOSS 完成使命并退出控制核心。"
		"coexistence":
			base_message = "MOSS 与人类保持有限协作。\n文明在控制与自主之间继续前进。"

	var history_lines := _get_ending_history_lines(result)
	if history_lines.is_empty():
		return base_message
	return "%s\n\n历史回顾\n- %s" % [
		base_message,
		"\n- ".join(history_lines),
	]


func _get_ending_history_lines(result: String) -> Array[String]:
	var lines: Array[String] = []

	match get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年公开扩大的自动化接口成为后来危机调度的起点，MOSS 的权限从一开始就处于公共记录中。")
		"human_command":
			lines.append("2044 年保留的人类指挥链贯穿后续授权争议，终局仍能追溯人工决策责任。")
		"restricted_interface":
			lines.append("2044 年封闭高危接口换取了清晰责任边界，也让后来的紧急接入承担额外代价。")

	# 2053 核心标签紧随 2044，与更早核心选择组合计算；后写标签不得抹掉前者。
	match get_decision_tag("decision.core_2053_population_vs_infrastructure"):
		"population_first":
			lines.append("2053 年优先撤离人口的记录让终局仍能解释民生优先的治理承诺，%s。" % _get_ending_relation_text(result))
		"infrastructure_first":
			lines.append("2053 年坚守基础设施的记录显示文明延续长期依赖工程延续，最终方案承担着人口转移的代价。")
		"sacrifice_perimeter":
			lines.append("2053 年牺牲外围的记录让终局牺牲顺序成为长期事实，MOSS 的排序在更早就已成为公开治理。")

	match get_event_state("event_state.mid_07_migration_priority"):
		"humanitarian":
			lines.append("人道迁移记录让普通家庭的优先级进入终局解释，%s。" % _get_ending_relation_text(result))
		"engineering_role":
			lines.append("工程岗位迁移记录显示文明延续长期依赖岗位分配，最终方案承担着职业牺牲的影子。")
		"moss_survival_value":
			lines.append("MOSS 生存价值排序曾写入迁移名单，终局权限更像长期托管事实的延伸。")

	match get_event_state("event_state.mid_09_yaa_sample_access"):
		"frozen":
			lines.append("丫丫样本访问曾被冻结，数字生命争议没有成为终局方案的公开依据。")
		"audited_access":
			lines.append("丫丫样本的受审计访问记录保留到终局，数字生命样本被视为争议资产而非确定答案。")
		"next_platform_interface":
			lines.append("下一代 550 平台预留过兼容接口，数字生命争议已经进入终局技术边界。")

	match get_event_state("event_state.mid_12_digital_life_leak"):
		"banned":
			lines.append("数字生命泄露曾被全面封禁，终局回顾更强调安全事故和社会恐慌。")
		"technical_disclosure":
			lines.append("有限技术说明让 2065 年审查留下可追溯材料，终局仍避免把数字保存写成永生承诺。")
		"tracked_and_preserved":
			lines.append("泄露传播者被追踪且样本被保留，终局必须解释 MOSS 为何积累这些争议资产。")

	match get_event_state("event_state.mid_14_heat_shield_shortage"):
		"load_reduction":
			lines.append("热屏蔽短缺曾以降载等待材料处理，最终工程窗口从那时起已经被压缩。")
		"rear_reallocation":
			lines.append("热屏蔽短缺曾挪用后方资源，后方资源代价成为文明延续前的工程回顾。")
		"moss_supply_reorder":
			lines.append("MOSS 曾强制重排热屏蔽供应链，终局调度延续了强调度的工程逻辑。")

	match get_event_state("event_state.mid_17_final_authorization"):
		"limited_final":
			lines.append("最终授权会议只批准有限接口，人工复核仍是终局解释的一部分。")
		"negotiated_trusteeship":
			lines.append("最终授权会议形成协商托管框架，MOSS 权限在终局前已有公开制度来源。")
		"strategic_trusteeship":
			lines.append("最终授权会议承认战略托管优先级，牺牲顺序在终局前已经成为制度事实。")

	return lines


func _get_ending_relation_text(result: String) -> String:
	match result:
		"managed":
			return "托管不是突然覆盖民生记录，而是在这些记录之后继续排序"
		"human_autonomy":
			return "MOSS 退出控制核心时仍能说明人类自治的社会基础"
		"failed":
			return "即使系统失败，民生优先事实仍保留为最后的治理证据"
	return "共存协议因此不只来自数值稳定，也来自可回看的治理经验"

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
		current_month,
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
	for node_id in %TechnologySystem.get_active_node_ids():
		var node_data: TechNodeData = %TechnologySystem.get_node_data(node_id)
		if node_data != null and node_data.stage == TechNodeData.Stage.MOSS:
			cores.append(node_data.display_name)
	cores.sort()
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
	current_month = INITIAL_MONTH
	current_energy = INITIAL_ENERGY
	current_cpu = INITIAL_CPU
	is_game_over = false
	action_log.clear()
	_clear_log_ui()
	triggered_events.clear()
	event_states.clear()
	_decision_history.clear()
	_decision_archive_timer_was_running = false
	_manually_paused = false
	_situation_auto_paused = false
	_situation_system.reset()
	if has_node("%DecisionArchivePanel"):
		%DecisionArchivePanel.hide()
	if has_node("%SituationPanel"):
		%SituationPanel.hide()
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
	update_decision_archive_button()
	update_situation_button()

	# 重置所有板块数据到初始值
	restore_sector_states()

	# 刷新UI
	update_global_resource_ui()
	update_command_buttons()
	_refresh_situation_ui()
	_write_development_log("game_restarted")

	# 恢复时间流动
	$Timer.start()
	update_time_control_button()


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
	var result := _command_system.execute_command(
		cmd,
		current_cpu,
		current_energy,
		selected_sector != null,
		cooldown_reduction,
		command_cooldowns
	)
	if not result["success"]:
		return false

	current_cpu = result["new_cpu"]
	current_energy = result["new_energy"]
	update_global_resource_ui()
	return true

## 应用指令效果到选中板块
## 参数: cmd - 指令数据
##       effect_type - 对于算力分配，"order"或"hope"
func apply_command_effect(cmd: CommandData, effect_type: String = "") -> void:
	if selected_sector == null:
		return

	var effect_lines := _command_system.apply_targeted_command(
		cmd,
		selected_sector.data_card,
		effect_type,
		%TechnologySystem.has_tag("human_public_decision"),
		can_allocate_combined()
	)
	if effect_lines.is_empty():
		return

	var lines: Array[String] = ["影响板块：%s" % selected_sector.data_card.region_name]
	lines.append_array(effect_lines)
	lines.append_array(
		_apply_situation_command_intervention(
			cmd.command_id,
			selected_sector.data_card.region_name
		)
	)
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
		var timer_was_running: bool = not $Timer.is_stopped()
		$Timer.stop()
		_hide_situation_panel_for_modal()
		update_time_control_button()
		%AllocatePopup.popup_allocate(cmd, selected_sector.data_card.region_name)
		var choice: String = await %AllocatePopup.choice_selected
		if choice != "":
			if execute_command(cmd):
				apply_command_effect(cmd, choice)
				update_command_buttons()
		if timer_was_running and not _situation_auto_paused:
			$Timer.start()
		update_time_control_button()
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
			var result := _command_system.apply_energy_convert(
				current_cpu,
				max_cpu,
				%TechnologySystem
			)
			current_cpu = result["new_cpu"]
			var lines: Array[String] = []
			lines.assign(result["lines"])
			lines.append_array(_apply_situation_command_intervention(cmd.command_id, ""))
			update_global_resource_ui()
			log_command_result(cmd, lines)
		COMMAND_GLOBAL_TAKEOVER:
			var sector_nodes := %SectorInfoContainer.get_children()
			var sector_data_list: Array[SectorData] = []
			for sector in sector_nodes:
				if sector.get("data_card") == null:
					continue
				sector_data_list.append(sector.data_card)

			var result := _command_system.apply_global_takeover(
				sector_data_list,
				%TechnologySystem
			)
			for sector in sector_nodes:
				if sector.get("data_card") != null:
					sector.update_display()
			var lines: Array[String] = []
			lines.assign(result["lines"])
			lines.append_array(_apply_situation_command_intervention(cmd.command_id, ""))
			update_global_resource_ui()
			log_command_result(cmd, lines)

# ============================================================
# 指令按钮管理
# ============================================================

## 初始化指令按钮容器中的所有按钮
func setup_command_buttons() -> void:
	var button_container: HBoxContainer = %CommandButtonContainer

	if button_container == null:
		push_error("找不到CommandButtonContainer")
		return

	# 只清空动态指令按钮，保留指令坞中的当前选区提示。
	for child in button_container.get_children():
		if child is CommandButton:
			child.queue_free()

	# 为每个指令创建按钮
	for cmd in available_commands:
		var button_scene := load("res://scenes/command_button.tscn")
		var button: Button = button_scene.instantiate()

		# 配置按钮
		button.setup(cmd)

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
		if button is CommandButton:
			var reason := get_command_unavailable_reason(button.command_data)
			button.set_availability(
				reason.is_empty(),
				reason,
				_command_system.get_command_cost_text(button.command_data)
			)

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
	var month: int = entry.get("month", 1)
	var kind: String = entry.get("kind", "")
	var title: String = entry.get("title", "")
	var message: String = entry.get("message", "")

	var full_text := "[%04d.%02d]" % [year, month]
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

	# 自动换行：按容器可用宽度设置最大宽度，不依赖容器最终分配的 size.x
	log_label.custom_maximum_size = Vector2(maxf(log_container.get_parent_area_size().x, 1.0), -1.0)
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
		if not is_instance_valid(label):
			_process_typewriter_queue()
			return
		label.text = full_text.left(i + 1)

		# 滚动到底部
		var scroll := _get_log_scroll_container()
		if scroll != null:
			await get_tree().process_frame
			if not is_instance_valid(label):
				_process_typewriter_queue()
				return
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
