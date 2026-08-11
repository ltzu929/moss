## 主控制器脚本 - MOSS模拟器核心系统
## 负责游戏的时间推进、事件协调、胜负判定和结局显示
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

## 指令领域服务脚本
const COMMAND_SYSTEM_SCRIPT := preload("res://scripts/systems/command_system.gd")
## 游戏内容扫描与运行态资源装配
const CONTENT_LOADER_SCRIPT := preload("res://scripts/systems/game_content_loader.gd")
## 开发期崩溃诊断日志
const DEVELOPMENT_LOG_SCRIPT := preload("res://scripts/systems/development_log.gd")
## 不可逆核心决策历史
const DECISION_HISTORY_SCRIPT := preload("res://scripts/systems/decision_history.gd")
## 轻量事件状态存取服务
const EVENT_STATE_STORE_SCRIPT := preload("res://scripts/systems/event_state_store.gd")
## 事件历史回声与选项显示文案服务
const EVENT_NARRATIVE_SCRIPT := preload("res://scripts/systems/event_narrative_system.gd")
## 事件选项数值调整与结算服务
const EVENT_RESOLUTION_SCRIPT := preload("res://scripts/systems/event_resolution_system.gd")
## 结局判定、历史回顾和科技摘要服务
const ENDING_SYSTEM_SCRIPT := preload("res://scripts/systems/ending_system.gd")
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

## HUD 和战略工作区只通过公开快照接口接收主控制器状态。
@onready var _main_hud: MainHud = $MainLayout/MainHud
@onready var _strategic_workspace: StrategicWorkspace = $MainLayout/StrategicWorkspace

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
## 内容加载服务，不依赖场景树或主控制器
var _content_loader: GameContentLoader = CONTENT_LOADER_SCRIPT.new()
## 开发期诊断日志，不参与游戏内日志 UI
var _development_log: DevelopmentDiagnosticsLog = DEVELOPMENT_LOG_SCRIPT.new()
## 开发期低频心跳计时器，不参与游戏时间推进
var _development_heartbeat_timer: Timer = null
## 核心决策标签和面向玩家的稳定档案
var _decision_history: DecisionHistory = DECISION_HISTORY_SCRIPT.new()
## 轻量事件状态，不依赖场景树或 UI
var _event_state_store: EventStateStore = EVENT_STATE_STORE_SCRIPT.new()
## 事件叙事服务，不访问场景树、资源模板或运行时数值
var _event_narrative_system: EventNarrativeSystem = EVENT_NARRATIVE_SCRIPT.new()
## 事件数值服务，不访问场景树、资源模板或写回对象
var _event_resolution_system: EventResolutionSystem = EVENT_RESOLUTION_SCRIPT.new()
## 结局领域服务，不访问场景树、Resource 或 UI
var _ending_system: EndingSystem = ENDING_SYSTEM_SCRIPT.new()
## 随机局势领域服务，不直接访问场景树或 UI
var _situation_system: SituationSystem = SITUATION_SYSTEM_SCRIPT.new()

## 已触发的事件ID列表（防止重复触发）
var triggered_events: Array[String] = []

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
	_event_narrative_system.configure(_event_state_store, _decision_history)
	_setup_development_log()
	_persist_development_phase("startup:events")

	# 初始化事件列表
	all_events.clear()
	all_events.assign(_content_loader.load_events())

	# 初始化随机局势模板和本局随机种子
	_persist_development_phase("startup:situations")
	all_situations.clear()
	all_situations.assign(_content_loader.load_situations())
	_situation_system.configure_templates(all_situations)
	_situation_system.reset()

	# 初始化指令列表
	_persist_development_phase("startup:commands")
	available_commands.clear()
	available_commands.assign(_content_loader.load_commands())
	for command in available_commands:
		command_cooldowns[command.command_id] = 0

	# 初始化科技系统
	_persist_development_phase("startup:technology")
	%TechnologySystem.load_nodes_from_disk()
	%TechnologySystem.node_activated.connect(_on_technology_node_activated)
	%TechnologySystem.stage_changed.connect(_on_technology_stage_changed)
	%TechnologyScreen.screen_closed.connect(_on_technology_screen_closed)

	cache_initial_sector_states()
	setup_strategic_views()

	# 初始化指令按钮
	setup_command_buttons()
	setup_situation_ui()

	_persist_development_phase("startup:ui")
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
	_set_development_phase("idle", {}, true)
	_development_log.flush_heartbeat()


func _exit_tree() -> void:
	if _development_heartbeat_timer != null:
		_development_heartbeat_timer.stop()
	_development_log.shutdown()

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

	# 显示生命周期由独立组件负责，MainOS 只传递完整领域条目。
	_strategic_workspace.append_action_log_entry(entry)

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
		DevelopmentDiagnosticsLog.DEFAULT_LOG_PATH,
		OS.is_debug_build(),
		DevelopmentDiagnosticsLog.DEFAULT_MAX_BYTES
	)
	_development_log.start_session(
		{
			"project": ProjectSettings.get_setting("application/config/name", "MOSS"),
			"scene": scene_file_path,
			"debug_build": OS.is_debug_build(),
		}
	)
	if OS.is_debug_build():
		_development_heartbeat_timer = Timer.new()
		_development_heartbeat_timer.name = "DevelopmentHeartbeatTimer"
		_development_heartbeat_timer.wait_time = (
			DevelopmentDiagnosticsLog.DEFAULT_HEARTBEAT_INTERVAL_SEC
		)
		_development_heartbeat_timer.ignore_time_scale = true
		_development_heartbeat_timer.timeout.connect(
			_on_development_heartbeat_timeout
		)
		add_child(_development_heartbeat_timer)
		_development_heartbeat_timer.start()


## 低频覆盖最新心跳；主线程卡死时该时间戳会停止前进，作为失活证据。
func _on_development_heartbeat_timeout() -> void:
	_development_log.update_runtime_snapshot(
		_build_development_runtime_snapshot()
	)
	_development_log.flush_heartbeat()


## 写入一条开发诊断日志，并附带当前游戏状态快照。
func _write_development_log(event: String, details: Dictionary = {}) -> void:
	_development_log.write_entry(event, _build_development_snapshot(), details)


## 同步写入关键阶段；即使主线程在下一次心跳前停止，JSONL 仍保留精确位置。
func _persist_development_phase(
	phase: String,
	details: Dictionary = {}
) -> void:
	var snapshot := _build_development_runtime_snapshot()
	_development_log.set_runtime_phase(phase, snapshot, details)
	_development_log.write_breadcrumb(
		"phase_entered",
		snapshot,
		details
	)


## 更新供低频心跳读取的当前执行阶段；只更新内存，不在此处写磁盘。
func _set_development_phase(
	phase: String,
	details: Dictionary = {},
	refresh_snapshot: bool = false
) -> void:
	var snapshot: Dictionary = {}
	if refresh_snapshot:
		snapshot = _build_development_runtime_snapshot()
	_development_log.set_runtime_phase(
		phase,
		snapshot,
		details,
		refresh_snapshot
	)


## 构建心跳和高频路径记录使用的最小快照。
func _build_development_runtime_snapshot() -> Dictionary:
	var selected_region := ""
	if selected_sector != null and selected_sector.get("data_card") != null:
		selected_region = selected_sector.data_card.region_id

	var technology_points := 0
	var active_technology_count := 0
	if has_node("%TechnologySystem"):
		technology_points = %TechnologySystem.get_available_points()
		active_technology_count = %TechnologySystem.get_active_node_ids().size()

	return {
		"year": current_year,
		"month": current_month,
		"is_game_over": is_game_over,
		"timer_stopped": true if not has_node("Timer") else $Timer.is_stopped(),
		"modal": _get_development_modal_state(),
		"situation_panel_visible": (
			has_node("%SituationPanel") and %SituationPanel.visible
		),
		"selected_region": selected_region,
		"cpu": current_cpu,
		"energy": current_energy,
		"technology_points": technology_points,
		"active_technology_count": active_technology_count,
		"active_situation_count": _situation_system.get_active_count(),
		"situation_node_pending": _situation_system.has_pending_node(),
	}


func _get_development_modal_state() -> String:
	if end_screen_instance != null and is_instance_valid(end_screen_instance):
		return "ending"
	var modal_paths := {
		"event": "%EventPopup",
		"allocate": "%AllocatePopup",
		"technology": "%TechnologyScreen",
		"decision_archive": "%DecisionArchivePanel",
	}
	for modal_name: String in modal_paths:
		var path: String = modal_paths[modal_name]
		if has_node(path) and get_node(path).visible:
			return modal_name
	return "none"


## 构建用于崩溃定位的轻量状态快照。
func _build_development_snapshot() -> Dictionary:
	var selected_region := ""
	if selected_sector != null and selected_sector.get("data_card") != null:
		selected_region = selected_sector.data_card.region_id

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
			"states": _event_state_store.export_state(),
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

	var sectors := _strategic_workspace.get_sector_nodes()
	for sector in sectors:
		if sector.get("data_card") == null:
			continue

		initial_sector_states[sector.data_card.region_id] = {
			"order": sector.data_card.order,
			"hope": sector.data_card.hope,
			"authority": sector.data_card.authority,
			"population": sector.data_card.population,
			"is_locked": sector.data_card.is_locked
		}

## 恢复所有板块到初始数值
func restore_sector_states() -> void:
	var sectors := _strategic_workspace.get_sector_nodes()

	for sector in sectors:
		if sector.get("data_card") == null:
			continue

		var state: Dictionary = initial_sector_states.get(sector.data_card.region_id, {})
		if state.is_empty():
			continue

		sector.data_card.order = state["order"]
		sector.data_card.hope = state["hope"]
		sector.data_card.authority = state["authority"]
		sector.data_card.population = state["population"]
		sector.data_card.is_locked = state["is_locked"]
		sector.update_display()

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
	return _event_resolution_system.get_technology_adjusted_event_delta(
		delta,
		stat,
		_get_event_technology_snapshot()
	)


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



## 根据稳定指令 ID 查找可用指令；不存在时返回 null。
## 这是 MainOS 对指令查询的稳定公开入口，具体查找仍由 CommandSystem 负责。
func get_command_by_id(command_id: String) -> CommandData:
	return _command_system.get_command_by_id(available_commands, command_id)


## 判断指令执行前是否必须选中目标板块
func command_requires_selected_sector(cmd: CommandData) -> bool:
	return _command_system.command_requires_selected_sector(cmd)


## 更新科技按钮显示的可用协议点和提示文本
func update_technology_button() -> void:
	_main_hud.set_technology_points(%TechnologySystem.get_available_points())


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

	for sector in _strategic_workspace.get_sector_nodes():
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
		_persist_development_phase(
			"ui:technology_opening",
			{"screen": "technology"}
		)
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
		_set_development_phase("ui:technology_open", {}, true)


func _on_technology_screen_closed() -> void:
	update_time_control_button()
	_set_development_phase("idle", {}, true)


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
	_main_hud.set_decision_count(get_decision_records().size())


func _on_decision_archive_button_pressed() -> void:
	if not _can_open_decision_archive():
		return
	_persist_development_phase(
		"ui:decision_archive_opening",
		{"screen": "decision_archive"}
	)
	_hide_situation_panel_for_modal()
	_decision_archive_timer_was_running = not $Timer.is_stopped()
	$Timer.stop()
	update_time_control_button()
	%DecisionArchivePanel.show_records(get_decision_records())
	_set_development_phase("ui:decision_archive_open", {}, true)


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
	_set_development_phase("idle", {}, true)


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
	if not %SituationPanel.node_option_requested.is_connected(
		_on_situation_node_option_requested
	):
		%SituationPanel.node_option_requested.connect(
			_on_situation_node_option_requested
		)
	_refresh_situation_ui()


func update_situation_button() -> void:
	_main_hud.set_situation_count(
		_situation_system.get_active_count(),
		SituationSystem.MAX_ACTIVE
	)


func _on_situation_button_pressed() -> void:
	if not _can_open_situation_panel():
		return
	_refresh_situation_ui()
	%SituationPanel.open_panel()
	_set_development_phase("idle", {}, true)


## 公共局势面板入口；测试和场景编排不再调用私有按钮回调。
func open_situation_panel() -> void:
	_on_situation_button_pressed()


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
	_set_development_phase("idle", {}, true)


## 公共时间控制入口；保持按钮回调只负责转发语义事件。
func toggle_time_control() -> void:
	_on_time_control_button_pressed()


func _can_resume_time_from_hud() -> bool:
	if is_game_over or end_screen_instance != null:
		return false
	if _situation_system.has_pending_node():
		if has_node("%SituationPanel"):
			%SituationPanel.show_status("请先处理当前局势节点。", true)
		return false
	for path in ["%EventPopup", "%AllocatePopup", "%TechnologyScreen", "%DecisionArchivePanel"]:
		if has_node(path) and get_node(path).visible:
			return false
	return true


func update_time_control_button() -> void:
	_main_hud.set_time_state(
		current_year,
		current_month,
		not $Timer.is_stopped(),
		_manually_paused,
		_situation_auto_paused or _situation_system.has_pending_node()
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


func request_situation_approach(instance_id: String, approach_id: String) -> void:
	_on_situation_approach_requested(instance_id, approach_id)


func _on_situation_node_option_requested(instance_id: String, option_id: String) -> void:
	var result := _situation_system.resolve_node(
		instance_id,
		option_id,
		current_cpu,
		current_energy,
		_get_sector_data_list()
	)
	current_cpu = int(result.get("new_cpu", current_cpu))
	current_energy = int(result.get("new_energy", current_energy))
	_handle_situation_notifications(result.get("notifications", []))
	_refresh_sector_displays()
	update_global_resource_ui()
	update_command_buttons()
	var focus_id := instance_id
	if bool(result.get("success", false)):
		for snapshot in get_situation_snapshots():
			var node: Dictionary = snapshot.get("node", {})
			if bool(node.get("pending", false)):
				focus_id = str(snapshot.get("instance_id", instance_id))
				break
	_refresh_situation_ui(focus_id)
	%SituationPanel.show_status(
		(
			"当前处置已完成；仍有另一个局势节点等待处理"
			if focus_id != instance_id
			else str(result.get("message", ""))
		),
		not bool(result.get("success", false))
	)


func request_situation_node_option(instance_id: String, option_id: String) -> void:
	_on_situation_node_option_requested(instance_id, option_id)


func _on_situation_focus_region_requested(region_id: String) -> void:
	var sector := _find_sector_by_id(region_id)
	if sector != null:
		select_sector(sector)


func _refresh_situation_ui(focus_id: String = "") -> void:
	var forecast_resources := _get_next_situation_resource_forecast()
	var snapshots := _situation_system.get_active_snapshots(
		int(forecast_resources["cpu"]),
		int(forecast_resources["energy"])
	)
	if has_node("%SituationPanel"):
		%SituationPanel.set_situations(snapshots, current_cpu, current_energy)
		if focus_id != "":
			%SituationPanel.open_panel(focus_id)
	update_situation_button()
	_update_region_situation_summary_ui()
	_sync_world_map_states()


func refresh_situation_ui(focus_id: String = "") -> void:
	_refresh_situation_ui(focus_id)


func get_situation_snapshots() -> Array[Dictionary]:
	var forecast_resources := _get_next_situation_resource_forecast()
	return _situation_system.get_active_snapshots(
		int(forecast_resources["cpu"]),
		int(forecast_resources["energy"])
	)


## 返回局势自动暂停状态，只读暴露给 HUD 与测试编排。
func is_situation_auto_paused() -> bool:
	return _situation_auto_paused


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


func set_situation_seed_for_test(seed_value: int) -> void:
	_situation_system.reset(seed_value)
	_refresh_situation_ui()


func start_situation_for_test(
	situation_id: String,
	region_id: String,
	year: int = current_year,
	month: int = current_month
) -> Dictionary:
	var snapshot := _situation_system.start_situation_for_test(
		situation_id,
		region_id,
		year,
		month
	)
	_refresh_situation_ui(str(snapshot.get("instance_id", "")))
	return snapshot

# ============================================================
# 板块选中管理
# ============================================================

## 初始化战略工作区；地图和区域卡片的输入由工作区内部管理。
func setup_strategic_views() -> void:
	if not _strategic_workspace.region_selected.is_connected(
		_on_workspace_region_selected
	):
		_strategic_workspace.region_selected.connect(_on_workspace_region_selected)

	_sync_strategic_views()


## 工作区将稳定区域 ID 选择事件交回主控制器。
func _on_workspace_region_selected(_region_id: String) -> void:
	selected_sector = _strategic_workspace.get_selected_sector()
	if %AllocatePopup.visible:
		if selected_sector == null or selected_sector.data_card == null:
			%AllocatePopup.update_display("未选择板块")
		else:
			%AllocatePopup.update_display(selected_sector.data_card.region_name)
	update_region_detail_ui()
	update_command_buttons()


## 按稳定区域 ID 查找现有 SectorInfo 节点
func _find_sector_by_id(region_id: String) -> SectorInfo:
	return _strategic_workspace.get_sector_by_region_id(region_id)

## 设置选中板块
## 参数: sector - 被点击的板块节点
func select_sector(sector: SectorInfo) -> void:
	_strategic_workspace.select_sector(sector)
	selected_sector = _strategic_workspace.get_selected_sector()
	update_region_detail_ui()
	update_command_buttons()

## 取消选中状态
func deselect_sector() -> void:
	_strategic_workspace.deselect_sector()
	selected_sector = null
	update_region_detail_ui()
	update_command_buttons()

# ============================================================
# 冷却系统
# ============================================================

## 每月更新冷却状态
## 减少所有指令的冷却计数（最小为0）
func update_cooldowns() -> void:
	_command_system.update_cooldowns(command_cooldowns)


## 返回局势系统使用的区域数据列表，不复制 Resource。
func _get_sector_data_list() -> Array[SectorData]:
	return _strategic_workspace.get_sector_data_list()


## 推进所有活跃局势，并在满足 2044 核心决策门槛后尝试生成新局势。
func _process_situations_month() -> void:
	var result := _situation_system.process_month(
		_get_sector_data_list(),
		current_cpu,
		current_energy,
		has_decision_tag("decision.core_2044_automation_access"),
		current_year,
		current_month,
		_get_situation_facts()
	)
	current_cpu = int(result.get("new_cpu", current_cpu))
	current_energy = int(result.get("new_energy", current_energy))
	_handle_situation_notifications(result.get("notifications", []))
	_refresh_sector_displays()
	_refresh_situation_ui()


func _get_situation_facts() -> Dictionary:
	var facts: Dictionary = _event_state_store.export_state()
	facts["decision.core_2044_automation_access"] = get_decision_tag(
		"decision.core_2044_automation_access"
	)
	for technology_tag in ["human_autonomy_recovery", "human_mutual_aid"]:
		if %TechnologySystem.has_tag(technology_tag):
			facts["technology.%s" % technology_tag] = true
	return facts


func _handle_situation_notifications(notifications: Array) -> void:
	for notification_variant in notifications:
		var situation_notice: Dictionary = notification_variant
		var title := "%s｜%s" % [
			str(situation_notice.get("region_name", "未知地区")),
			str(situation_notice.get("title", "随机局势")),
		]
		var message := str(situation_notice.get("message", ""))
		record_action("situation", title, message)
		_write_development_log(
			"situation_%s" % str(situation_notice.get("type", "updated")),
			situation_notice
		)
		if bool(situation_notice.get("pause", false)):
			$Timer.stop()
			_manually_paused = false
			_situation_auto_paused = true
			if has_node("%SituationPanel"):
				%SituationPanel.open_panel(str(situation_notice.get("instance_id", "")))
	update_time_control_button()


func _refresh_sector_displays() -> void:
	_strategic_workspace.refresh_sector_displays()
	selected_sector = _strategic_workspace.get_selected_sector()
	update_region_detail_ui()
	update_global_overview_ui()


func _apply_situation_command_intervention(
	command_id: String,
	region_id: String
) -> Array[String]:
	var result := _situation_system.apply_command_intervention(
		command_id,
		region_id,
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

## 公开的完整月度编排接口。
##
## 该协程按固定顺序执行事件检查、终局检查、月份推进、年度结算、
## 冷却、局势、UI 刷新和失败检查。测试或其他编排方可等待此接口，
## 不应调用 Timer 信号回调。
func process_month_tick() -> void:
	# 游戏已结束，禁止任何操作
	if is_game_over:
		return
	_persist_development_phase("month_tick:event_scan")

	# === 第一步：事件触发检查 ===
	# 先检查当前年月的事件，再推进时间
	for event in all_events:
		if event.event_time == current_year and event.event_month == current_month:
			if not is_event_available(event):
				continue

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
			_set_development_phase(
				"event:awaiting_choice",
				{
					"event_key": event_key,
					"event_title": event.event_title,
				},
				true
			)
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
			_persist_development_phase(
				"event:applying_choice",
				{
					"event_key": event_key,
					"choice_index": choice_index,
				}
			)

			# 应用选择后果
			_apply_event_option_consequences(
				event.event_region,
				selected_opt,
				event.event_title
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
			_set_development_phase("month_tick:event_scan")

	# 终局日期需要先处理对应事件，再进入结局结算
	if current_year == END_YEAR and current_month == END_MONTH:
		_persist_development_phase("month_tick:ending_check")
		check_game_end()
		return

	# === 第二步：时间推进 ===
	_persist_development_phase("month_tick:advance")
	_advance_one_month()
	var yearly_settlement := current_month == INITIAL_MONTH
	if yearly_settlement:
		_persist_development_phase("month_tick:yearly_settlement")
		_apply_yearly_settlement()
	_persist_development_phase("month_tick:cooldowns")
	update_cooldowns()
	_persist_development_phase("month_tick:situations")
	_process_situations_month()
	_persist_development_phase("month_tick:ui_refresh")
	update_global_resource_ui()
	update_command_buttons()
	update_time_control_button()

	# === 第三步：胜负判定 ===
	_persist_development_phase("month_tick:failure_check")
	_check_game_failure()
	if not is_game_over:
		_set_development_phase("idle", {}, true)


## Timer 信号转发到公开的完整月度编排接口。
func _on_timer_timeout() -> void:
	await process_month_tick()


## 生成事件触发去重键，允许同一年不同月份存在多个事件
func _get_event_trigger_key(event: GameEvent) -> String:
	return event.event_id


## 判断固定事件或核心历史分支是否满足触发条件
func is_event_available(event: GameEvent) -> bool:
	if event.required_decision_tag_key.is_empty():
		return true
	return has_decision_tag(
		event.required_decision_tag_key,
		event.required_decision_tag_value
	)


## 构建事件弹窗使用的运行时副本，避免修改磁盘加载的 Resource 模板
func build_display_event(event: GameEvent) -> GameEvent:
	var display_event: GameEvent = event.duplicate(true)
	display_event.event_description = build_event_description(event)
	_event_narrative_system.apply_option_display_text(display_event)
	var decision_state := _decision_history.export_state()
	_event_resolution_system.apply_event_option_adjustments(
		display_event,
		decision_state.get("tags", {}),
		_event_state_store.export_state()
	)
	return display_event


func _get_event_technology_snapshot() -> Dictionary:
	return {
		"human_event_mitigation": %TechnologySystem.has_tag("human_event_mitigation"),
	}


## 根据已写入的轻量事件状态补充主事件历史回声。
func build_event_description(event: GameEvent) -> String:
	return _event_narrative_system.build_event_description(event)


## 写入轻量事件状态，空键不产生效果
func set_event_state(state_key: String, state_value: String) -> void:
	_event_state_store.set_state(state_key, state_value)


## 查询轻量事件状态；未写入时返回默认值
func get_event_state(state_key: String, default_value: String = "") -> String:
	return _event_state_store.get_state(state_key, default_value)


## 判断事件状态是否存在，传入 expected_value 时同时校验值
func has_event_state(state_key: String, expected_value: String = "") -> bool:
	return _event_state_store.has_state(state_key, expected_value)


## 根据事件选项写入轻量历史状态
func apply_event_option_state(option: EventOption) -> void:
	_event_state_store.set_state(option.event_state_key, option.event_state_value)


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

## 兼容旧调用面的事件后果入口；数值计算由 EventResolutionSystem 完成。
func apply_consequences(
	region_id: String,
	order_delta: int,
	hope_delta: int,
	authority_delta: int,
	energy_cost: int,
	event_title: String = "",
	option_text: String = ""
) -> void:
	var option := EventOption.new()
	option.button_text = option_text
	option.order_delta = order_delta
	option.hope_delta = hope_delta
	option.authority_delta = authority_delta
	option.energy_cost = energy_cost
	_apply_event_option_consequences(region_id, option, event_title, option_text)


## 将玩家在弹窗中实际选择的运行时选项交给同一结算快照。
func _apply_event_option_consequences(
	region_id: String,
	option: EventOption,
	event_title: String = "",
	option_text: String = ""
) -> void:
	var sectors := _strategic_workspace.get_sector_nodes()
	var found := false

	for sector in sectors:
		# 检查是否为有效的板块节点
		if sector.get("data_card") == null:
			continue

		# 通过稳定区域 ID 匹配目标板块
		if sector.data_card.region_id == region_id:
			select_sector(sector)
			var projections := _event_resolution_system.calculate_option_projections(
				option,
				_get_event_technology_snapshot(),
				{
					"order": sector.data_card.order,
					"hope": sector.data_card.hope,
					"authority": sector.data_card.authority,
				},
				current_energy
			)
			var resolution: Dictionary = projections.get("resolution", {})
			var resolved_order_delta := int(resolution.get("order_delta", 0))
			var resolved_hope_delta := int(resolution.get("hope_delta", 0))
			var resolved_authority_delta := int(resolution.get("authority_delta", 0))
			var resolved_energy_cost := int(resolution.get("energy_cost", 0))

			# 修改板块数据
			sector.data_card.order += resolved_order_delta
			sector.data_card.hope += resolved_hope_delta
			sector.data_card.authority += resolved_authority_delta
			sector.data_card.clamp_values()

			# 修改全局能源
			current_energy = maxi(0, current_energy - resolved_energy_cost)

			# 刷新UI显示
			sector.update_display()
			update_global_resource_ui()
			update_region_detail_ui()

			var lines: Array[String] = []
			var display_option_text := option_text
			if display_option_text.is_empty():
				display_option_text = option.button_text
			if display_option_text != "":
				lines.append("方案：%s" % display_option_text)
			lines.append("影响板块：%s" % sector.data_card.region_name)
			append_signed_change(lines, "秩序", resolved_order_delta)
			append_signed_change(lines, "希望", resolved_hope_delta)
			append_signed_change(lines, "控制权", resolved_authority_delta)
			append_signed_change(lines, "能源", -resolved_energy_cost)
			record_action(
				"event",
				event_title if event_title != "" else sector.data_card.region_name,
				"\n".join(lines)
			)

			found = true
			break

	if not found:
		push_error("找不到板块 ID: " + region_id)

# ============================================================
# UI更新函数
# ============================================================

## 更新右侧上下文区域详情和指令坞
## 未选择区域时显示空状态，选择区域后显示对应 SectorData
func update_region_detail_ui() -> void:
	_strategic_workspace.update_region_detail(get_situation_snapshots())
	if selected_sector == null or selected_sector.data_card == null:
		_main_hud.set_command_context("未选择区域  //  请先选择区域")
		return
	_main_hud.set_command_context(
		"当前选区：%s  //  选择指令" % selected_sector.data_card.region_name
	)


## 在上下文栏显示当前选区的局势摘要，完整配置仍由局势追踪面板承担。
func _update_region_situation_summary_ui() -> void:
	_strategic_workspace.update_region_detail(get_situation_snapshots())


## 同步地图状态、地图选区和地球聚焦
func _sync_strategic_views() -> void:
	_strategic_workspace.refresh_views(get_situation_snapshots(), _event_focus_region)


## 将现有区域数据快照传给中央战略地图
func _sync_world_map_states() -> void:
	_strategic_workspace.refresh_views(get_situation_snapshots(), _event_focus_region)


## 地球窗口优先显示事件区域，否则显示当前选区
func _sync_orbital_focus() -> void:
	_strategic_workspace.set_event_focus_region(_event_focus_region)


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
	_strategic_workspace.update_global_overview()


## 根据平均控制权生成全局威胁等级
func _get_global_threat_text(avg_authority: int) -> String:
	if avg_authority < 20:
		return "高风险"
	if avg_authority < 40:
		return "中等"
	return "稳定"


## 刷新顶部全局资源显示（日期、算力、能源）
func update_global_resource_ui() -> void:
	_main_hud.update_resources(
		get_moss_model_name(),
		current_cpu,
		current_energy,
		%TechnologySystem.get_available_points(),
		get_decision_records().size(),
		_situation_system.get_active_count(),
		SituationSystem.MAX_ACTIVE
	)
	_main_hud.set_time_state(
		current_year,
		current_month,
		not $Timer.is_stopped(),
		_manually_paused,
		_situation_auto_paused or _situation_system.has_pending_node()
	)
	_strategic_workspace.refresh_views(get_situation_snapshots(), _event_focus_region)

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
	return int(get_average_stats_snapshot().get("authority", 0))


## 返回当前区域的平均秩序、希望和控制权快照。
## 返回值只包含整数平均值，空区域集合时三个维度均为0。
## 完整路线测试和外部编排通过该公开快照读取统计，不跨脚本访问私有实现。
func get_average_stats_snapshot() -> Dictionary:
	var sectors := _strategic_workspace.get_sector_nodes()
	var total_order := 0
	var total_hope := 0
	var total_authority := 0
	var count := 0

	for sector in sectors:
		if sector.get("data_card") == null:
			continue
		total_order += sector.data_card.order
		total_hope += sector.data_card.hope
		total_authority += sector.data_card.authority
		count += 1

	if count == 0:
		return {
			"order": 0,
			"hope": 0,
			"authority": 0,
		}

	# 返回整数平均值，向下取整，保持原有结局和失败判定语义。
	return {
		"order": floori(float(total_order) / float(count)),
		"hope": floori(float(total_hope) / float(count)),
		"authority": floori(float(total_authority) / float(count)),
	}

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
	return _ending_system.should_fail_from_authority(
		authority,
		avg_order,
		avg_hope,
		_get_ending_technology_snapshot()
	)


## 根据科技核心、控制权、秩序和希望判定最终结局类型
## 返回 managed、human_autonomy、coexistence 或 failed
func determine_ending_type(
	authority: int,
	avg_order: int,
	avg_hope: int
) -> String:
	return _ending_system.determine_ending_type(
		authority,
		avg_order,
		avg_hope,
		_get_ending_technology_snapshot()
	)


## 组装结局服务所需的科技能力快照，不把 TechnologySystem 注入领域服务。
func _get_ending_technology_snapshot() -> Dictionary:
	return {
		"managed_core": %TechnologySystem.has_tag("managed_core"),
		"human_core": %TechnologySystem.has_tag("human_core"),
	}

## 触发失败结局
## 原因: 所有板块控制权归零，MOSS系统崩溃
func trigger_game_over() -> void:
	is_game_over = true
	$Timer.stop()
	_persist_development_phase("ending:failure")
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
	_persist_development_phase("ending:building_result")

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


## 构建结局描述文本，并读取显式历史快照作为历史解释。
func build_ending_message(result: String) -> String:
	var decision_state := _decision_history.export_state()
	return _ending_system.build_ending_message(
		result,
		decision_state.get("tags", {}),
		_event_state_store.export_state()
	)

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

	for sector in _strategic_workspace.get_sector_nodes():
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
		get_technology_summary()
	)

	# 连接重新开始信号
	end_screen_instance.restart_requested.connect(_on_restart_requested)


## 返回结局界面使用的科技摘要兼容投影。
## MainOS 只组装 TechnologySystem 的显式数据，文本格式由 EndingSystem 负责。
func get_technology_summary() -> String:
	var route_counts: Dictionary = {
		"managed": 0,
		"core": 0,
		"human": 0,
	}
	var core_names: Array[String] = []
	for node_id in %TechnologySystem.get_active_node_ids():
		var node_data: TechNodeData = %TechnologySystem.get_node_data(node_id)
		if node_data == null:
			continue
		match node_data.route:
			TechNodeData.Route.MANAGED:
				route_counts["managed"] += 1
			TechNodeData.Route.CORE:
				route_counts["core"] += 1
			TechNodeData.Route.HUMAN:
				route_counts["human"] += 1
		if node_data.stage == TechNodeData.Stage.MOSS:
			core_names.append(node_data.display_name)
	return _ending_system.build_technology_summary(route_counts, core_names)

## 计算所有板块某项属性的平均值
func _get_average_stat(stat_name: String) -> int:
	return int(get_average_stats_snapshot().get(stat_name, 0))

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
	_strategic_workspace.clear_action_log()
	triggered_events.clear()
	_event_state_store.clear()
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
	available_commands.assign(_content_loader.load_commands())
	for command in available_commands:
		command_cooldowns[command.command_id] = 0
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
	_set_development_phase("idle", {}, true)


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
			selected_sector.data_card.region_id
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
		_persist_development_phase(
			"ui:allocate_waiting",
			{"screen": "allocate", "command_id": cmd.command_id}
		)
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
		_set_development_phase("idle", {}, true)
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
			var sector_nodes := _strategic_workspace.get_sector_nodes()
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
	_main_hud.set_commands(available_commands)

## 更新所有指令按钮状态
func update_command_buttons() -> void:
	var availability: Dictionary = {}
	for cmd in available_commands:
		var reason := get_command_unavailable_reason(cmd)
		availability[cmd.command_id] = {
			"available": reason.is_empty(),
			"reason": reason,
			"cost_text": _command_system.get_command_cost_text(cmd),
		}
	_main_hud.set_command_availability(availability)
