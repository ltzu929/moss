## 自动化播放测试脚本 - MOSS模拟器核心循环验证
## 通过加速Timer和自动响应弹窗信号，驱动游戏完整播放
## 验证：事件触发、状态变化、科技进度、结局判定
extends Control

# ============================================================
# 常量定义
# ============================================================

## 测试用Timer间隔（秒）- 加速游戏时间
const TEST_TIMER_INTERVAL: float = 0.05

## 测试超时帧数（约60秒@60fps）
const MAX_TEST_FRAMES: int = 3600

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

## 上一次跟踪的年份
var _last_tracked_year: int = 2044

## 事件触发日志 {年份: 事件标题}
var _event_log: Dictionary = {}

## 自动选择的事件选项索引
var _auto_choice: int = 0

## 帧计数器
var _frame_count: int = 0

## 是否已完成断言
var _assertions_done: bool = false

## 弹窗自动响应标记（防止重复响应）
var _event_popup_responding: bool = false
var _alloc_popup_responding: bool = false

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	_log("=== MOSS模拟器 自动化播放测试启动 ===")
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

	# 验证场景完整性
	if not _verify_scene_integrity():
		_log("[FATAL] 场景完整性检查失败")
		_finish_test()
		return

	# 记录初始状态
	_record_initial_state()

	# 设置自动响应器
	_setup_auto_responders()

	# 连接游戏结束信号
	_main_os.game_ended.connect(_on_game_ended)

	# 启动加速Timer
	timer.start()

	_log("测试环境就绪，Timer间隔: %.3fs" % TEST_TIMER_INTERVAL)
	_log("---")

	set_process(true)


func _process(_delta: float) -> void:
	_frame_count += 1

	# 超时保护
	if _frame_count > MAX_TEST_FRAMES and not _game_ended:
		_log("[ERROR] 测试超时！游戏未在 %d 帧内结束" % MAX_TEST_FRAMES)
		_game_ended = true
		_run_all_assertions()
		_finish_test()
		set_process(false)
		return

	if _main_os == null:
		return

	# 轮询弹窗自动响应
	_poll_popups()

	# 跟踪年份变化
	var current_year: int = _main_os.current_year
	if current_year != _last_tracked_year:
		_on_year_changed(_last_tracked_year, current_year)
		_last_tracked_year = current_year

	# 游戏已结束，停止处理
	if _game_ended:
		set_process(false)

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
		"%SectorInfoContainer",
		"%CommandButtonContainer",
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
		_assert_eq(sectors.size(), 7, "场景中应有7个板块", "scene_integrity")

		var initial_authorities: Dictionary = {
			"亚洲": 24,
			"北美": 26,
			"俄罗斯": 25,
			"非洲": 18,
			"南美": 17,
			"大洋洲": 20,
			"联合政府": 30,
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
		_log("  事件: %s (年份=%d)" % [event.event_title, event.event_time])

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
	_assert_true(header_height >= 56.0 and header_height <= 72.0, "顶部状态栏高度应适配1080P HUD", "ui_layout")
	ok = (header_height >= 56.0 and header_height <= 72.0) and ok

	var left_panel: PanelContainer = (
		_main_os.get_node("MainLayout/ContentRow/LeftPanel") as PanelContainer
	)
	var right_panel: VBoxContainer = (
		_main_os.get_node("MainLayout/ContentRow/RightPanel") as VBoxContainer
	)
	_assert_eq(int(left_panel.custom_minimum_size.x), 360, "左侧区域详情宽度应为360", "ui_layout")
	_assert_eq(int(right_panel.custom_minimum_size.x), 420, "右侧信息栏宽度应为420", "ui_layout")
	ok = (int(left_panel.custom_minimum_size.x) == 360) and ok
	ok = (int(right_panel.custom_minimum_size.x) == 420) and ok

	var sector_container: GridContainer = _main_os.get_node("%SectorInfoContainer") as GridContainer
	_assert_eq(int(sector_container.custom_minimum_size.y), 160, "底部区域卡片栏高度应为160", "ui_layout")
	ok = (int(sector_container.custom_minimum_size.y) == 160) and ok

	var command_container: HBoxContainer = (
		_main_os.get_node("%CommandButtonContainer") as HBoxContainer
	)
	_assert_true(command_container.custom_minimum_size.y <= 36.0, "底部命令栏不应挤压1080P主视图", "ui_layout")
	ok = (command_container.custom_minimum_size.y <= 36.0) and ok

	return ok


func _verify_hud_layout_contract() -> bool:
	var ok: bool = true

	if not _main_os.has_node("MainLayout/ContentRow"):
		_assert_true(false, "缺少主内容行", "ui_layout")
		return false

	var content_row: HBoxContainer = _main_os.get_node("MainLayout/ContentRow") as HBoxContainer
	var content_order: Array[String] = ["LeftPanel", "CenterPanel", "RightPanel"]
	ok = _assert_child_order(
		content_row,
		content_order,
		"主内容三栏"
	) and ok

	if not _main_os.has_node("MainLayout/ContentRow/RightPanel"):
		_assert_true(false, "缺少右侧信息栏", "ui_layout")
		return false

	var right_panel: VBoxContainer = (
		_main_os.get_node("MainLayout/ContentRow/RightPanel") as VBoxContainer
	)
	var right_panel_order: Array[String] = [
		"RegionOrbitalPanel",
		"GlobalOverviewPanel",
		"LogPlaceholder",
	]
	ok = _assert_child_order(
		right_panel,
		right_panel_order,
		"右侧信息栏"
	) and ok

	if _main_os.has_node("%TopBarContainer"):
		var top_bar: HBoxContainer = _main_os.get_node("%TopBarContainer") as HBoxContainer
		var readable_top_bar := top_bar.custom_minimum_size.y >= 56.0
		_assert_true(readable_top_bar, "顶部状态栏高度应保持宽松", "ui_layout")
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

	if _main_os.has_node("MainLayout/ContentRow/RightPanel/LogPlaceholder"):
		var log_panel: Control = _main_os.get_node(
			"MainLayout/ContentRow/RightPanel/LogPlaceholder"
		) as Control
		var log_expands := (
			log_panel != null
			and log_panel.size_flags_vertical == Control.SIZE_EXPAND_FILL
		)
		_assert_true(log_expands, "MOSS LOG 应填满右栏剩余高度", "ui_layout")
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
	_log("  年份: %d" % _main_os.current_year)
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
	var title: String = ""
	if event_popup.has_node("%EventTitle"):
		title = event_popup.get_node("%EventTitle").text
	_event_log[year] = title
	_log("  [EVENT] 年份=%d 自动选择选项 %d (%s)" % [year, _auto_choice, title])

	# 发出选择信号并隐藏弹窗
	# 注意：直接emit信号不会触发popup的hide()，必须手动隐藏
	event_popup.option_selected.emit(_auto_choice)
	event_popup.hide()
	_event_popup_responding = false


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

func _on_year_changed(old_year: int, new_year: int) -> void:
	var avg_auth: int = _main_os.get_average_authority()
	_log("年份 %d->%d | CPU=%d 能源=%d 控制权=%d" % [
		old_year, new_year,
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

	# 延迟运行断言，确保所有处理完成
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


func _assert_initial_state() -> void:
	_log("[断言组] 初始状态")
	_assert_eq(_main_os.INITIAL_YEAR, 2044, "初始年份常量应为2044", "initial_state")
	_assert_eq(_main_os.INITIAL_CPU, 30, "初始算力常量应为30", "initial_state")
	_assert_eq(_main_os.INITIAL_ENERGY, 100, "初始能源常量应为100", "initial_state")


func _assert_event_triggering() -> void:
	_log("[断言组] 事件触发")
	_log("  事件日志: %s" % str(_event_log))

	var expected_years: Array[int] = [2044, 2053, 2058, 2065, 2070, 2075]
	for year in expected_years:
		var triggered: bool = (year in _event_log)
		_assert_true(triggered, "年份%d应有事件触发" % year, "event_triggering")


## 验证科技节点加载、年度协议点累计和无操作时的激活状态
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
		8,
		"2075年前应累计8个协议点",
		"technology"
	)
	_assert_eq(
		technology.get_active_node_ids().size(),
		0,
		"自动通关未操作科技树时不应自动激活节点",
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
	_log("  最终年份: %d" % _main_os.current_year)
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
	_log("  MOSS模拟器 自动化播放测试报告")
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
		_log("最终年份: %d" % _main_os.current_year)
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

	# 退出游戏
	get_tree().quit(_failed)
