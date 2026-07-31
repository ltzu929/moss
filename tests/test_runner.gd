## 自动化播放测试脚本 - MOSS模拟器核心循环验证
## 通过加速Timer和自动响应弹窗信号，驱动游戏完整播放
## 验证：事件触发、状态变化、科技进度、结局判定
extends Control

# ============================================================
# 常量定义
# ============================================================

@export_enum("mixed", "managed", "human_autonomy")
var route_id: String = "mixed"

## 测试用Timer间隔（秒）- 加速游戏时间
const TEST_TIMER_INTERVAL: float = 0.05

## 单路线必须早于外层测试运行器的 90 秒超时结束
const MAX_TEST_DURATION_MSEC: int = 80000

const ROUTE_CONFIGS: Dictionary = {
	"mixed": {
		"expected_ending": "coexistence",
		"mid_choice": 1,
		"final_choice": 1,
		"branch_choice": 1,
		"situation_approach": 1,
		"situation_node_choice": 0,
		"command_id": "technology_aid",
		"command_start_year": 2064,
		"minimum_command_count": 3,
		"technology_nodes": [
			"managed_decision",
			"core_hot_redundancy",
			"managed_infrastructure",
			"managed_global_network",
			"human_open_interface",
			"human_public_decision",
			"core_load_migration",
			"human_mutual_aid",
		],
		"core_choices": {
			"太空电梯危机": "human_command",
			"大淹没事故": "infrastructure_first",
			"月球坠落危机": "human_final_authority",
			"AI隔离审查": "limited_disclosure",
			"西伯利亚发动机群过载": "redundant_array",
		},
		"history_fragments": ["只披露有限接口", "备用阵列"],
	},
	"managed": {
		"expected_ending": "managed",
		"mid_choice": 2,
		"final_choice": 2,
		"branch_choice": 2,
		"situation_approach": 2,
		"situation_node_choice": 1,
		"command_id": "global_takeover",
		"command_start_year": 2056,
		"minimum_command_count": 4,
		"technology_nodes": [
			"managed_decision",
			"managed_behavior_prediction",
			"managed_infrastructure",
			"managed_global_network",
			"managed_authority_audit",
			"core_hot_redundancy",
			"managed_irreplaceable_protocol",
			"core_energy_mapping",
		],
		"core_choices": {
			"太空电梯危机": "public_counterstrike",
			"大淹没事故": "sacrifice_perimeter",
			"月球坠落危机": "forced_takeover",
			"AI隔离审查": "hidden_core_chain",
			"西伯利亚发动机群过载": "forced_overclock",
		},
		"history_fragments": [
			"隐藏核心链路",
			"强制超频",
			"外围补偿申诉",
			"审计轨迹",
		],
	},
	"human_autonomy": {
		"expected_ending": "human_autonomy",
		"mid_choice": 0,
		"final_choice": 0,
		"branch_choice": 0,
		"situation_approach": 0,
		"situation_node_choice": 0,
		"command_id": "technology_aid",
		"command_start_year": 2060,
		"minimum_command_count": 4,
		"technology_nodes": [
			"human_open_interface",
			"human_public_decision",
			"human_autonomy_network",
			"human_emergency_training",
			"human_mutual_aid",
			"core_hot_redundancy",
			"human_civilization_self_sustain",
			"core_energy_mapping",
		],
		"core_choices": {
			"太空电梯危机": "human_command",
			"大淹没事故": "population_first",
			"月球坠落危机": "human_final_authority",
			"AI隔离审查": "full_compliance",
			"西伯利亚发动机群过载": "personnel_first_shutdown",
		},
		"history_fragments": ["完整接受隔离审查", "分段停机优先保护工程人员"],
	},
}

# ============================================================
# 测试状态
# ============================================================

## MainOS实例引用
var _main_os: Control = null

## 测试日志
var _log_entries: Array[String] = []

## 断言结果列表
var _assertions: Array[Dictionary] = []

## 已通过断言数
var _passed: int = 0

## 已失败断言数
var _failed: int = 0

## 游戏结束标记
var _game_ended: bool = false

## 游戏结束结果
var _game_result: String = ""

## 游戏结束消息
var _game_message: String = ""

## 上一次跟踪的年月
var _last_tracked_year: int = 2044
var _last_tracked_month: int = 1

## 事件触发日志 {"YYYY.MM:title": {year, month, event_title, selected_index}}
var _event_log: Dictionary = {}

## 测试启动时间戳
var _test_started_msec: int = 0

## 是否已完成断言
var _assertions_done: bool = false

## 弹窗自动响应标记（防止重复响应）
var _event_popup_responding: bool = false
var _alloc_popup_responding: bool = false
var _seen_situation_ids: Array[String] = []
var _route_config: Dictionary = {}
var _technology_plan_index: int = 0
var _technology_blocked_node: String = ""
var _route_command_count: int = 0

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	_test_started_msec = Time.get_ticks_msec()
	_route_config = ROUTE_CONFIGS.get(route_id, {})
	if _route_config.is_empty():
		_log("[FATAL] 未知代表性路线: %s" % route_id)
		_failed += 1
		_finish_test()
		return
	_log("=== MOSS模拟器 代表性路线测试启动：%s ===" % route_id)
	_log("")

	# 加载并实例化主场景
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	if scene == null:
		_log("[FATAL] 无法加载主场景")
		_finish_test()
		return

	_main_os = scene.instantiate()
	add_child(_main_os)

	# 等待一帧让MainOS子节点初始化完成
	await get_tree().process_frame

	# 停止Timer，防止在测试设置期间触发游戏循环
	var timer: Timer = _main_os.get_node("Timer")
	timer.stop()
	timer.wait_time = TEST_TIMER_INTERVAL
	_main_os.set_situation_seed_for_test(424242)

	# 验证场景完整性
	if not _verify_scene_integrity():
		_log("[FATAL] 场景完整性检查失败")
		_finish_test()
		return

	# 记录初始状态
	_record_initial_state()
	_drive_route_technology()

	# 设置自动响应器
	_setup_auto_responders()

	# 连接游戏结束信号
	_main_os.game_ended.connect(_on_game_ended)

	# 启动加速Timer
	timer.start()

	_log("测试环境就绪，路线=%s，Timer间隔: %.3fs" % [route_id, TEST_TIMER_INTERVAL])
	_log("---")

	set_process(true)


func _process(_delta: float) -> void:
	# 超时保护
	if (
		Time.get_ticks_msec() - _test_started_msec > MAX_TEST_DURATION_MSEC
		and not _game_ended
	):
		_log("[ERROR] 测试超时！路线未在 80 秒内结束")
		_game_ended = true
		_run_all_assertions()
		_finish_test()
		set_process(false)
		return

	if _main_os == null:
		return

	# 轮询弹窗自动响应
	_poll_popups()
	_poll_situations()
	_drive_route_technology()
	_drive_route_command()

	# 跟踪日期变化
	var current_year: int = _main_os.current_year
	var current_month: int = _main_os.current_month
	if current_year != _last_tracked_year or current_month != _last_tracked_month:
		_on_date_changed(_last_tracked_year, _last_tracked_month, current_year, current_month)
		_last_tracked_year = current_year
		_last_tracked_month = current_month

	# 游戏已结束，停止处理
	if _game_ended:
		set_process(false)


## 按路线逐点激活真实科技节点；协议点仍只来自生产时间循环。
func _drive_route_technology() -> void:
	if _main_os == null or _game_ended or _is_route_modal_active():
		return
	var technology := _main_os.get_node("%TechnologySystem") as TechnologySystem
	var technology_nodes: Array = _route_config.get("technology_nodes", [])
	if _technology_plan_index >= technology_nodes.size():
		return
	if technology.get_available_points() <= 0:
		return

	var node_id := str(technology_nodes[_technology_plan_index])
	if not technology.can_activate(node_id):
		if _technology_blocked_node != node_id:
			_technology_blocked_node = node_id
			_assert_true(
				false,
				"路线科技节点应在协议点到账时可激活：%s" % node_id,
				"route_technology"
			)
		return

	var activated := technology.activate(node_id)
	_assert_true(activated, "路线应通过真实接口激活科技：%s" % node_id, "route_technology")
	if activated:
		_technology_plan_index += 1
		_technology_blocked_node = ""
		_log("  [TECH] 路线 %s 激活 %s" % [route_id, node_id])


## 在无模态窗口时执行路线解锁的真实指令，依靠生产冷却控制频率。
func _drive_route_command() -> void:
	if _main_os == null or _game_ended or _is_route_modal_active():
		return
	if _main_os.current_year < int(_route_config.get("command_start_year", 9999)):
		return

	var command_id := str(_route_config.get("command_id", ""))
	if command_id.is_empty():
		return
	var command := _main_os._get_command_by_id(command_id) as CommandData
	if command == null:
		return

	if _main_os.command_requires_selected_sector(command):
		var target := _find_route_command_target(command)
		if target == null:
			return
		_main_os.select_sector(target)

	if not _main_os.is_command_available(command):
		return
	if not _main_os.execute_command(command):
		_assert_true(false, "已判定可用的路线指令应成功结算：%s" % command_id, "route_command")
		return

	if _main_os.command_requires_selected_sector(command):
		_main_os.apply_command_effect(command)
	else:
		_main_os.apply_special_command_effect(command)
	_main_os.update_command_buttons()
	_route_command_count += 1
	_log(
		"  [COMMAND] 路线 %s 第%d次执行 %s"
		% [route_id, _route_command_count, command_id]
	)


func _find_route_command_target(command: CommandData) -> SectorInfo:
	var technology := _main_os.get_node("%TechnologySystem") as TechnologySystem
	var allow_zero_authority := technology.has_tag("human_core")
	var best_target: SectorInfo = null
	var best_social_score := 1000000
	for sector_node in _main_os.get_node("%SectorInfoContainer").get_children():
		var sector := sector_node as SectorInfo
		if sector == null or sector.data_card == null:
			continue
		var projected_authority := sector.data_card.authority + command.authority_delta
		if not allow_zero_authority and projected_authority < 5:
			continue
		var social_score := sector.data_card.order + sector.data_card.hope
		if social_score < best_social_score:
			best_target = sector
			best_social_score = social_score
	return best_target


func _is_route_modal_active() -> bool:
	if _event_popup_responding or _alloc_popup_responding:
		return true
	if bool(_main_os.get("_situation_auto_paused")):
		return true
	for node_path in ["%EventPopup", "%AllocatePopup"]:
		var modal := _main_os.get_node(node_path) as Control
		if modal != null and modal.visible:
			return true
	return false


## 为完整通关选择每项局势的地方方案、首个节点，并处理自动暂停。
func _poll_situations() -> void:
	var snapshots: Array[Dictionary] = _main_os.get_situation_snapshots()
	for snapshot in snapshots:
		var instance_id := str(snapshot.get("instance_id", ""))
		if instance_id not in _seen_situation_ids:
			_seen_situation_ids.append(instance_id)
			_log("发现随机局势: %s" % str(snapshot.get("title", "")))
		var node: Dictionary = snapshot.get("node", {})
		if bool(node.get("pending", false)):
			var node_options: Array = node.get("options", [])
			var preferred_node_index := mini(
				int(_route_config.get("situation_node_choice", 0)),
				node_options.size() - 1
			)
			var ordered_node_indices: Array[int] = []
			if preferred_node_index >= 0:
				ordered_node_indices.append(preferred_node_index)
			for index in range(node_options.size()):
				if index != preferred_node_index:
					ordered_node_indices.append(index)
			for index in ordered_node_indices:
				var option_variant: Variant = node_options[index]
				var option: Dictionary = option_variant
				if (
					_main_os.current_cpu >= int(option.get("cpu_cost", 0))
					and _main_os.current_energy >= int(option.get("energy_cost", 0))
				):
					_main_os._on_situation_node_option_requested(
						instance_id,
						str(option.get("option_id", ""))
					)
					break
			continue
		if str(snapshot.get("approach_id", "")) != "":
			continue
		var approaches: Array = snapshot.get("approaches", [])
		if approaches.is_empty():
			continue
		var approach_index := mini(
			int(_route_config.get("situation_approach", 0)),
			approaches.size() - 1
		)
		_main_os._on_situation_approach_requested(
			instance_id,
			str(approaches[approach_index].get("approach_id", ""))
		)

	if bool(_main_os.get("_situation_auto_paused")):
		_main_os._on_time_control_button_pressed()

# ============================================================
# 场景完整性验证
# ============================================================

func _verify_scene_integrity() -> bool:
	var ok: bool = true

	# 检查核心节点
	var node_paths: Array[String] = [
		"Timer",
		"%TopBarContainer",
		"MainLayout/ContentRow",
		"MainLayout/ContentRow/ContextPanel",
		"%SectorInfoContainer",
		"%CommandDock",
		"%CommandButtonContainer",
		"%CommandContextLabel",
		"%EventPopup",
		"%TechnologySystem",
		"%TechnologyScreen",
		"%RegionNameLabel",
		"%RegionDescriptionLabel",
		"%RegionOrderBar",
		"%RegionHopeBar",
		"%RegionAuthorityBar",
		"%GlobalMapSelectedLabel",
		"%GlobalPopulationLabel",
		"%GlobalAuthorityLabel",
		"%WorldMapView",
		"%RegionOrbitalView",
		"%RegionSituationLabel",
	]

	for path in node_paths:
		if not _main_os.has_node(path):
			_log("[FAIL] 缺少节点: %s" % path)
			ok = false
		else:
			_log("[ OK ] 节点存在: %s" % path)

	ok = _verify_hud_layout_contract() and ok
	ok = _verify_1080p_layout_contract() and ok
	ok = _verify_strategic_ui_contract() and ok

	# 检查板块初始控制权
	if _main_os.has_node("%SectorInfoContainer"):
		var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
		_assert_eq(sectors.size(), 6, "场景中应有6个板块", "scene_integrity")

		var initial_authorities: Dictionary = {
			"亚洲": 24,
			"北美": 26,
			"欧洲": 27,
			"非洲": 18,
			"南美": 17,
			"大洋洲": 20,
		}

		for sector in sectors:
			if sector.get("data_card") != null:
				var dc: Resource = sector.data_card
				var region: String = dc.region_name
				if region in initial_authorities:
					_assert_eq(
						dc.authority, initial_authorities[region],
						"%s初始控制权应为%d" % [region, initial_authorities[region]],
						"scene_integrity"
					)

	# 检查事件数据
	var event_count: int = _main_os.all_events.size()
	_log("[INFO] 事件数量: %d" % event_count)
	for event in _main_os.all_events:
		_log("  事件: %s (日期=%04d.%02d)" % [
			event.event_title,
			event.event_time,
			event.event_month,
		])

	return ok


func _verify_strategic_ui_contract() -> bool:
	var ok: bool = true

	if _main_os.has_node("%WorldMapView"):
		var world_map: Control = _main_os.get_node("%WorldMapView") as Control
		var supports_selection := (
			world_map != null
			and world_map.has_signal("region_selected")
			and world_map.has_method("set_selected_region")
			and world_map.has_method("set_region_states")
		)
		_assert_true(supports_selection, "世界地图应支持区域选择和状态同步", "strategic_ui")
		ok = supports_selection and ok
	else:
		_assert_true(false, "缺少可点击世界地图组件", "strategic_ui")
		ok = false

	if _main_os.has_node("%RegionOrbitalView"):
		var orbital_view: Control = _main_os.get_node("%RegionOrbitalView") as Control
		var supports_focus := (
			orbital_view != null
			and orbital_view.has_method("focus_region")
			and orbital_view.has_method("get_focused_region")
		)
		_assert_true(supports_focus, "地球窗口应支持区域聚焦", "strategic_ui")
		ok = supports_focus and ok
	else:
		_assert_true(false, "缺少区域地球视图", "strategic_ui")
		ok = false

	var event_popup: PanelContainer = _main_os.get_node("%EventPopup") as PanelContainer
	if event_popup == null:
		_assert_true(false, "缺少事件弹窗", "strategic_ui")
		return false

	var popup_nodes: Array[String] = [
		"%EventImage",
		"%EventLevelLabel",
		"%ImpactTooltip",
	]
	for path in popup_nodes:
		var exists := event_popup.has_node(path)
		_assert_true(exists, "事件弹窗应包含节点 %s" % path, "strategic_ui")
		ok = exists and ok

	var supports_preview := (
		event_popup.has_method("get_impact_preview_delay")
		and event_popup.has_method("format_option_impact")
	)
	_assert_true(supports_preview, "事件弹窗应提供延迟影响预览接口", "strategic_ui")
	ok = supports_preview and ok

	var event_data := GameEvent.new()
	var property_names: Array[String] = []
	for property in event_data.get_property_list():
		property_names.append(str(property["name"]))
	var supports_event_art := "event_image" in property_names and "event_level" in property_names
	_assert_true(supports_event_art, "事件数据应支持专属图片和事件等级", "strategic_ui")
	ok = supports_event_art and ok

	return ok


func _verify_1080p_layout_contract() -> bool:
	var ok: bool = true

	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	_assert_eq(viewport_width, 1920, "窗口宽度应按1080P设计为1920", "ui_layout")
	_assert_eq(viewport_height, 1080, "窗口高度应按1080P设计为1080", "ui_layout")
	ok = (viewport_width == 1920) and ok
	ok = (viewport_height == 1080) and ok

	var top_bar: HBoxContainer = _main_os.get_node("%TopBarContainer") as HBoxContainer
	var header_height := top_bar.custom_minimum_size.y
	_assert_true(
		header_height >= 48.0 and header_height <= 56.0,
		"顶部状态栏应保持紧凑并适配1080P HUD",
		"ui_layout"
	)
	ok = (header_height >= 48.0 and header_height <= 56.0) and ok

	var context_panel := (
		_main_os.get_node("MainLayout/ContentRow/ContextPanel") as PanelContainer
	)
	_assert_eq(
		int(context_panel.custom_minimum_size.x),
		420,
		"右侧单一上下文栏宽度应为420",
		"ui_layout"
	)
	ok = (int(context_panel.custom_minimum_size.x) == 420) and ok

	var sector_container: GridContainer = _main_os.get_node("%SectorInfoContainer") as GridContainer
	_assert_eq(
		int(sector_container.custom_minimum_size.y),
		94,
		"底部区域比较条高度应为94",
		"ui_layout"
	)
	ok = (int(sector_container.custom_minimum_size.y) == 94) and ok

	var command_dock := _main_os.get_node("%CommandDock") as PanelContainer
	_assert_eq(int(command_dock.custom_minimum_size.y), 54, "指令坞高度应为54", "ui_layout")
	ok = (int(command_dock.custom_minimum_size.y) == 54) and ok

	var command_container: HBoxContainer = (
		_main_os.get_node("%CommandButtonContainer") as HBoxContainer
	)
	_assert_true(
		command_container.custom_minimum_size.y <= 40.0,
		"指令坞内容不应挤压1080P主视图",
		"ui_layout"
	)
	ok = (command_container.custom_minimum_size.y <= 40.0) and ok

	return ok


func _verify_hud_layout_contract() -> bool:
	var ok: bool = true

	if not _main_os.has_node("MainLayout/ContentRow"):
		_assert_true(false, "缺少主内容行", "ui_layout")
		return false

	var content_row: HBoxContainer = _main_os.get_node("MainLayout/ContentRow") as HBoxContainer
	var content_order: Array[String] = ["CenterPanel", "ContextPanel"]
	ok = _assert_child_order(
		content_row,
		content_order,
		"地图优先主内容"
	) and ok

	if not _main_os.has_node("MainLayout/ContentRow/ContextPanel"):
		_assert_true(false, "缺少右侧上下文栏", "ui_layout")
		return false

	var context_vbox: VBoxContainer = (
		_main_os.get_node(
			"MainLayout/ContentRow/ContextPanel/ContextMargin/ContextVBox"
		) as VBoxContainer
	)
	var context_panel_order: Array[String] = [
		"ContextTitle",
		"RegionOrbitalPanel",
	]
	ok = _assert_child_order(
		context_vbox,
		context_panel_order,
		"右侧上下文栏"
	) and ok

	if _main_os.has_node("%TopBarContainer"):
		var top_bar: HBoxContainer = _main_os.get_node("%TopBarContainer") as HBoxContainer
		var readable_top_bar := top_bar.custom_minimum_size.y >= 48.0
		_assert_true(readable_top_bar, "顶部状态栏应保持可读", "ui_layout")
		ok = readable_top_bar and ok
	else:
		_assert_true(false, "缺少顶部状态栏", "ui_layout")
		ok = false

	var has_moss_status_panel := _main_os.has_node("%MossStatusPanel")
	_assert_true(
		not has_moss_status_panel,
		"右栏不应保留独立 MossStatusPanel",
		"ui_layout"
	)
	ok = not has_moss_status_panel and ok

	var log_path := (
		"MainLayout/ContentRow/ContextPanel/ContextMargin/ContextVBox/LogPlaceholder"
	)
	if _main_os.has_node(log_path):
		var log_panel: Control = _main_os.get_node(
			log_path
		) as Control
		var log_expands := (
			log_panel != null
			and log_panel.size_flags_vertical == Control.SIZE_EXPAND_FILL
		)
		_assert_true(log_expands, "MOSS LOG 应填满上下文栏剩余高度", "ui_layout")
		ok = log_expands and ok

	if _main_os.has_node("%SectorInfoContainer"):
		for sector_node in _main_os.get_node("%SectorInfoContainer").get_children():
			var sector := sector_node as SectorInfo
			if sector == null:
				continue

			var whole_card_clickable := (
				sector.mouse_filter == Control.MOUSE_FILTER_STOP
				and _all_control_descendants_ignore_mouse(sector)
			)
			_assert_true(
				whole_card_clickable,
				"%s 卡片整个矩形都应由根节点接收点击" % sector.name,
				"ui_layout"
			)
			ok = whole_card_clickable and ok

	return ok


func _all_control_descendants_ignore_mouse(parent: Node) -> bool:
	for child in parent.get_children():
		if child is Control:
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				return false
		if not _all_control_descendants_ignore_mouse(child):
			return false
	return true


func _assert_child_order(parent: Node, expected_names: Array[String], description: String) -> bool:
	var ok: bool = true

	for index in range(expected_names.size()):
		if parent.get_child_count() <= index:
			_assert_true(false, "%s缺少第%d个子节点" % [description, index + 1], "ui_layout")
			ok = false
			continue

		var actual_name := str(parent.get_child(index).name)
		var expected_name := expected_names[index]
		_assert_eq(
			actual_name,
			expected_name,
			"%s第%d项应为%s" % [description, index + 1, expected_name],
			"ui_layout"
		)
		ok = (actual_name == expected_name) and ok

	return ok

# ============================================================
# 初始状态记录
# ============================================================

func _record_initial_state() -> void:
	_log("初始状态:")
	_log("  日期: %04d.%02d" % [_main_os.current_year, _main_os.current_month])
	_log("  算力: %d" % _main_os.current_cpu)
	_log("  能源: %d" % _main_os.current_energy)
	_log("  最大算力: %d" % _main_os.max_cpu)
	_log("  恢复率: %d" % _main_os.cpu_recovery_rate)
	_log("  科技阶段: %d" % _main_os.technology_stage_level)
	_log("  平均控制权: %d" % _main_os.get_average_authority())

# ============================================================
# 自动响应器
# ============================================================

func _setup_auto_responders() -> void:
	# 不再使用visibility_changed，改用_process中的轮询方式
	# 这样可以可靠地检测弹窗显示并自动响应
	_log("[ OK ] 自动响应器就绪（ polling 模式）")


func _poll_popups() -> void:
	"""每帧检测弹窗状态，自动响应可见的弹窗"""
	if _main_os == null or _game_ended:
		return

	# 检测事件弹窗
	if not _event_popup_responding:
		var event_popup: PanelContainer = _main_os.get_node("%EventPopup")
		if event_popup != null and event_popup.visible:
			_event_popup_responding = true
			_respond_to_event_popup(event_popup)

	# 检测算力分配弹窗
	if not _alloc_popup_responding:
		var alloc_popup: AllocatePopup = _main_os.get_node("%AllocatePopup")
		if alloc_popup != null and alloc_popup.visible:
			_alloc_popup_responding = true
			_respond_to_alloc_popup(alloc_popup)


func _respond_to_event_popup(event_popup: PanelContainer) -> void:
	# 等待两帧确保_on_timer_timeout中的await已注册
	await get_tree().process_frame
	await get_tree().process_frame

	# 记录事件触发
	var year: int = _main_os.current_year
	var month: int = _main_os.current_month
	var title: String = ""
	if event_popup.has_node("%EventTitle"):
		title = event_popup.get_node("%EventTitle").text
	var date_key := "%04d.%02d" % [year, month]
	var event_key := "%s:%s" % [date_key, title]
	var desired_index := _get_route_event_choice_index(title, year, month)
	_event_log[event_key] = {
		"year": year,
		"month": month,
		"event_title": title,
		"desired_index": desired_index,
	}
	var option_list := event_popup.get_node("%OptionList") as VBoxContainer
	var option_buttons: Array[Node] = option_list.get_children()
	var selected_index := -1
	if desired_index >= 0 and desired_index < option_buttons.size():
		var preferred_button := option_buttons[desired_index] as Button
		if preferred_button != null and not preferred_button.disabled:
			selected_index = desired_index
		else:
			_assert_true(
				false,
				"路线目标方案必须真实可点击：%s / 选项%d" % [title, desired_index],
				"route_event_choice"
			)
	else:
		_assert_true(
			false,
			"应能从稳定事件契约定位路线方案：%s" % title,
			"route_event_choice"
		)
	if selected_index == -1:
		for index in range(option_buttons.size()):
			var candidate := option_buttons[index] as Button
			if candidate != null and not candidate.disabled:
				selected_index = index
				break

	_assert_true(
		selected_index != -1,
		"事件弹窗必须至少提供一个真实可点击方案：%s" % title,
		"event_playability"
	)
	if selected_index == -1:
		# 只用于让失败测试退出，不能把不可点击方案记为通过。
		event_popup.option_selected.emit(0)
		event_popup.hide()
	else:
		_log("  [EVENT] 日期=%s 自动点击选项 %d (%s)" % [date_key, selected_index, title])
		_event_log[event_key]["selected_index"] = selected_index
		(option_buttons[selected_index] as Button).pressed.emit()
	_event_popup_responding = false


func _get_route_event_choice_index(title: String, year: int, month: int) -> int:
	var core_choices: Dictionary = _route_config.get("core_choices", {})
	if core_choices.has(title):
		var expected_value := str(core_choices[title])
		var source_event := _find_source_event(title, year, month)
		if source_event == null:
			return -1
		for index in range(source_event.options.size()):
			if source_event.options[index].decision_tag_value == expected_value:
				return index
		return -1
	if title == "木星引力危机":
		return int(_route_config.get("final_choice", 0))
	if title in ["外围地下城补偿申诉", "隐藏链路异常回执"]:
		return int(_route_config.get("branch_choice", 0))
	return int(_route_config.get("mid_choice", 0))


func _find_source_event(title: String, year: int, month: int) -> GameEvent:
	for event in _main_os.all_events:
		if (
			event.event_title == title
			and event.event_time == year
			and event.event_month == month
		):
			return event
	return null


func _respond_to_alloc_popup(alloc_popup: AllocatePopup) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_log("  [ALLOCATE] 自动选择：秩序")
	# 发出选择信号并隐藏弹窗
	alloc_popup.choice_selected.emit("order")
	alloc_popup.hide()
	_alloc_popup_responding = false

# ============================================================
# 状态跟踪
# ============================================================

func _on_date_changed(old_year: int, old_month: int, new_year: int, new_month: int) -> void:
	var avg_auth: int = _main_os.get_average_authority()
	_log("日期 %04d.%02d->%04d.%02d | CPU=%d 能源=%d 控制权=%d" % [
		old_year, old_month,
		new_year, new_month,
		_main_os.current_cpu,
		_main_os.current_energy,
		avg_auth
	])

# ============================================================
# 游戏结束回调
# ============================================================

func _on_game_ended(result: String, message: String) -> void:
	_game_result = result
	_game_message = message
	_game_ended = true

	_log("---")
	_log("游戏结束! 结果: %s" % result)
	_log("消息: %s" % message)

	# 2075 选项会在同一协程中触发结局；等待弹窗响应器完整收尾。
	while _event_popup_responding or _alloc_popup_responding:
		await get_tree().process_frame
	await get_tree().process_frame
	_run_all_assertions()
	_finish_test()

# ============================================================
# 断言系统
# ============================================================

func _assert_eq(
	actual: Variant,
	expected: Variant,
	description: String,
	group: String = ""
) -> void:
	var passed: bool = (actual == expected)
	_assertions.append({
		"passed": passed,
		"description": description,
		"expected": str(expected),
		"actual": str(actual),
		"group": group
	})
	if passed:
		_passed += 1
	else:
		_failed += 1
		_log("[FAIL] %s: %s (期望=%s, 实际=%s)" % [group, description, str(expected), str(actual)])


func _assert_true(condition: bool, description: String, group: String = "") -> void:
	_assert_eq(condition, true, description, group)


func _assert_gte(actual: int, minimum: int, description: String, group: String = "") -> void:
	var passed: bool = (actual >= minimum)
	_assertions.append({
		"passed": passed,
		"description": description,
		"expected": ">=%d" % minimum,
		"actual": str(actual),
		"group": group
	})
	if passed:
		_passed += 1
	else:
		_failed += 1
		_log("[FAIL] %s: %s (值=%d, 期望≥%d)" % [group, description, actual, minimum])

# ============================================================
# 断言组
# ============================================================

func _run_all_assertions() -> void:
	if _assertions_done:
		return
	_assertions_done = true

	_log("")
	_log("=== 运行断言 ===")

	_assert_game_completion()
	_assert_initial_state()
	_assert_region_detail_sync()
	_assert_global_overview_sync()
	_assert_event_triggering()
	_assert_situation_progress()
	_assert_technology_progress()
	_assert_resource_bounds()
	_assert_final_state()
	_assert_game_logic()

	_log("=== 断言完成 ===")


func _assert_game_completion() -> void:
	_log("[断言组] 游戏完成性")
	_assert_true(_game_ended, "游戏应正常结束", "game_completion")
	if _game_ended:
		_assert_true(
			_game_result in ["failed", "coexistence", "managed", "human_autonomy"],
			"游戏结果应是有效类型: %s" % _game_result,
			"game_completion"
		)
		_assert_eq(
			_game_result,
			str(_route_config.get("expected_ending", "")),
			"代表性路线应抵达约定结局",
			"game_completion"
		)


func _assert_initial_state() -> void:
	_log("[断言组] 初始状态")
	_assert_eq(_main_os.INITIAL_YEAR, 2044, "初始年份常量应为2044", "initial_state")
	_assert_eq(_main_os.INITIAL_CPU, 30, "初始算力常量应为30", "initial_state")
	_assert_eq(_main_os.INITIAL_ENERGY, 100, "初始能源常量应为100", "initial_state")


func _assert_event_triggering() -> void:
	_log("[断言组] 事件触发")
	_log("  事件日志: %s" % str(_event_log))

	var core_event_contracts: Dictionary = {
		"太空电梯危机": {
			"year": 2044,
			"key": "decision.core_2044_automation_access",
		},
		"大淹没事故": {
			"year": 2053,
			"key": "decision.core_2053_population_vs_infrastructure",
		},
		"月球坠落危机": {
			"year": 2058,
			"key": "decision.core_2058_crisis_authority",
		},
		"AI隔离审查": {
			"year": 2065,
			"key": "decision.core_2065_audit_posture",
		},
		"西伯利亚发动机群过载": {
			"year": 2070,
			"key": "decision.core_2070_engine_protection",
		},
		"木星引力危机": {
			"year": 2075,
			"key": "",
		},
	}
	var expected_core_choices: Dictionary = _route_config.get("core_choices", {})
	for title_variant in core_event_contracts:
		var title := str(title_variant)
		var contract: Dictionary = core_event_contracts[title]
		_assert_true(
			_event_was_logged(int(contract["year"]), 1, title),
			"%s 应通过真实时间循环触发" % title,
			"event_triggering"
		)
		var decision_key := str(contract["key"])
		if decision_key.is_empty():
			continue
		_assert_eq(
			_main_os.get_decision_tag(decision_key),
			str(expected_core_choices[title]),
			"%s 应写入路线约定核心标签" % title,
			"event_triggering"
		)
	_assert_eq(
		_main_os.get_decision_records().size(),
		5,
		"完整通关应保留五条不可逆核心决策档案",
		"event_triggering"
	)

	var expects_branches := route_id == "managed"
	for branch_title in ["外围地下城补偿申诉", "隐藏链路异常回执"]:
		_assert_eq(
			_event_was_logged(
				2054 if branch_title == "外围地下城补偿申诉" else 2066,
				6,
				branch_title
			),
			expects_branches,
			"条件分支触发应与核心路线一致：%s" % branch_title,
			"event_triggering"
		)
	if expects_branches:
		_assert_eq(
			_main_os.get_event_state("event_state.branch_01_perimeter_compensation"),
			"moss_archive",
			"托管路线应真实结算外围补偿分支",
			"event_triggering"
		)
		_assert_eq(
			_main_os.get_event_state("event_state.branch_02_hidden_chain_receipt"),
			"audit_trail_rewrite",
			"托管路线应真实结算隐藏链路回执分支",
			"event_triggering"
		)

	var expected_event_count := 25 if expects_branches else 23
	_assert_eq(
		_event_log.size(),
		expected_event_count,
		"路线应处理全部固定事件及应触发的条件分支",
		"event_triggering"
	)


func _event_was_logged(year: int, month: int, title: String) -> bool:
	return "%04d.%02d:%s" % [year, month, title] in _event_log


func _assert_situation_progress() -> void:
	_log("[断言组] 随机局势")
	_assert_true(
		not _seen_situation_ids.is_empty(),
		"固定种子的完整通关应至少处理一项随机局势",
		"situations"
	)


## 验证完整路线只使用生产年份发放的8个协议点。
func _assert_technology_progress() -> void:
	_log("[断言组] 科技研究")
	var technology: TechnologySystem = _main_os.get_node("%TechnologySystem")
	_assert_eq(
		technology.get_all_nodes().size(),
		21,
		"应加载21个科技节点",
		"technology"
	)
	_assert_eq(
		technology.get_available_points(),
		0,
		"路线应使用整局8个协议点",
		"technology"
	)
	_assert_eq(
		technology.get_active_node_ids(),
		_route_config.get("technology_nodes", []),
		"路线应按约定顺序激活8个真实科技节点",
		"technology"
	)
	_assert_eq(
		technology.get_stage(),
		TechNodeData.Stage.MOSS,
		"六个节点后应进入MOSS阶段并允许终端节点",
		"technology"
	)
	_assert_gte(
		_route_command_count,
		int(_route_config.get("minimum_command_count", 0)),
		"路线应多次执行科技解锁的真实指令",
		"technology"
	)


func _assert_resource_bounds() -> void:
	_log("[断言组] 资源边界")
	_assert_true(_main_os.current_cpu >= 0, "CPU不应为负数", "resource_bounds")
	_assert_true(_main_os.current_energy >= 0, "能源不应为负数", "resource_bounds")
	_assert_true(_main_os.current_year >= 2044, "年份不应早于2044", "resource_bounds")
	_assert_true(
		_main_os.current_cpu <= _main_os.max_cpu,
		"CPU不应超过最大值 (当前=%d, 最大=%d)" % [_main_os.current_cpu, _main_os.max_cpu],
		"resource_bounds"
	)


func _assert_final_state() -> void:
	_log("[断言组] 最终状态")
	_log("  最终日期: %04d.%02d" % [_main_os.current_year, _main_os.current_month])
	_log("  最终CPU: %d / %d" % [_main_os.current_cpu, _main_os.max_cpu])
	_log("  最终能源: %d" % _main_os.current_energy)
	_log("  最终恢复率: %d" % _main_os.cpu_recovery_rate)
	_log("  最终冷却缩减: %d" % _main_os.cooldown_reduction)
	_log("  最终科技阶段: %d" % _main_os.technology_stage_level)
	_log("  最终平均控制权: %d" % _main_os.get_average_authority())

	if _game_ended:
		_assert_true(_main_os.is_game_over, "游戏结束后is_game_over应为true", "final_state")

		var avg_auth: int = _main_os.get_average_authority()

		var avg_order: int = _main_os._get_average_stat("order")
		var avg_hope: int = _main_os._get_average_stat("hope")
		_assert_eq(
			_game_result,
			_main_os.determine_ending_type(avg_auth, avg_order, avg_hope),
			"结局应与四类判定规则一致",
			"final_state"
		)
		match route_id:
			"managed":
				_assert_true(avg_auth >= 50, "托管路线平均控制权应达到50", "final_state")
			"human_autonomy":
				_assert_true(avg_auth < 25, "人类自主路线平均控制权应低于25", "final_state")
				_assert_true(
					avg_order >= 50 and avg_hope >= 50,
					"人类自主路线平均秩序与希望应至少为50",
					"final_state"
				)
			"mixed":
				_assert_true(
					avg_auth > 0 and avg_order >= 40 and avg_hope >= 40,
					"混合路线应维持正控制权及基本社会稳定",
					"final_state"
				)
		for fragment_variant in _route_config.get("history_fragments", []):
			var fragment := str(fragment_variant)
			_assert_true(
				fragment in _game_message,
				"结局说明应回读路线历史：%s" % fragment,
				"final_state"
			)


func _assert_game_logic() -> void:
	_log("[断言组] 游戏逻辑")

	if _game_result in ["coexistence", "managed", "human_autonomy"]:
		_assert_true(
			_main_os.current_year >= 2075,
			"非失败结局时年份应>=2075 (实际=%d)" % _main_os.current_year,
			"game_logic"
		)

	# 已触发的事件不应重复触发
	var event_count: int = _main_os.triggered_events.size()
	_assert_true(event_count >= 1, "至少应触发1个事件 (实际=%d)" % event_count, "game_logic")

	# 每个事件只触发一次
	_assert_true(
		_main_os.triggered_events.size() == _event_log.size(),
		"触发事件数应与事件日志一致 (triggered=%d, log=%d)" % [_main_os.triggered_events.size(), _event_log.size()],
		"game_logic"
	)

	_assert_eq(_main_os.max_cpu, 100, "未激活并行核心时最大算力应为100", "game_logic")


func _assert_region_detail_sync() -> void:
	_log("[断言组] 区域详情同步")

	if not _main_os.has_node("%SectorInfoContainer"):
		_assert_true(false, "缺少区域卡片容器", "ui_layout")
		return

	if not _main_os.has_node("%RegionNameLabel"):
		_assert_true(false, "缺少区域名称标签", "ui_layout")
		return

	var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
	_assert_true(sectors.size() > 0, "至少应存在一个区域卡片", "ui_layout")
	if sectors.is_empty():
		return

	var first_sector: SectorInfo = sectors[0] as SectorInfo
	_assert_true(first_sector != null, "第一个区域卡片应是 SectorInfo", "ui_layout")
	if first_sector == null:
		return

	_main_os.select_sector(first_sector)

	var region_name_label: Label = _main_os.get_node("%RegionNameLabel")
	_assert_eq(
		region_name_label.text,
		first_sector.data_card.region_name,
		"区域详情名称应同步选中区域",
		"ui_layout"
	)

	_main_os.deselect_sector()


func _assert_global_overview_sync() -> void:
	_log("[断言组] 全局信息同步")

	if not _main_os.has_method("format_population_for_ui"):
		_assert_true(false, "主控制器应提供人口格式化方法", "ui_layout")
		return

	if not _main_os.has_node("%GlobalPopulationLabel"):
		_assert_true(false, "缺少全球人口标签", "ui_layout")
		return

	var total_population := 0
	var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
	for sector in sectors:
		if sector.get("data_card") != null:
			total_population += sector.data_card.population

	_main_os.update_global_resource_ui()

	var population_label: Label = _main_os.get_node("%GlobalPopulationLabel")
	var expected_text: String = "全球人口: " + _main_os.format_population_for_ui(total_population)
	_assert_eq(
		population_label.text,
		expected_text,
		"全球人口应由所有区域人口合计生成",
		"ui_layout"
	)

# ============================================================
# 日志与测试结束
# ============================================================

func _log(msg: String) -> void:
	_log_entries.append(msg)
	print("[MOSS-TEST] ", msg)


func _finish_test() -> void:
	_log("")
	_log("==========================================")
	_log("  MOSS模拟器 代表性路线测试报告：%s" % route_id)
	_log("==========================================")

	var total: int = _passed + _failed
	_log("")
	_log("总断言数: %d" % total)
	_log("通过: %d" % _passed)
	_log("失败: %d" % _failed)

	if total > 0:
		var rate: float = float(_passed) / float(total) * 100.0
		_log("通过率: %.1f%%" % rate)

	if _failed > 0:
		_log("")
		_log("失败断言详情:")
		for assertion in _assertions:
			if not assertion["passed"]:
				_log("  X [%s] %s (期望=%s, 实际=%s)" % [
					assertion["group"],
					assertion["description"],
					assertion["expected"],
					assertion["actual"]
				])

	_log("")
	_log("--- 游戏状态摘要 ---")
	if _main_os != null:
		_log("游戏结果: %s" % _game_result)
		if _game_message != "":
			_log("消息: %s" % _game_message)
		_log("最终日期: %04d.%02d" % [_main_os.current_year, _main_os.current_month])
		_log("最终CPU: %d" % _main_os.current_cpu)
		_log("最终能源: %d" % _main_os.current_energy)
		_log("最终平均控制权: %d" % _main_os.get_average_authority())
		_log("最终科技阶段: %d" % _main_os.technology_stage_level)
		_log(
			"科技节点: %s" % str(
				_main_os.get_node("%TechnologySystem").get_active_node_ids()
			)
		)
		_log("事件日志: %s" % str(_event_log))
	else:
		_log("MainOS实例不可用")

	_log("")
	_log("=== 测试结束 ===")
	print("[MOSS-ROUTE:%s] 完成，失败断言：%d" % [route_id, _failed])

	# 退出游戏
	get_tree().quit(_failed)
