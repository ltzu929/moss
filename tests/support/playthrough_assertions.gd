## 三条完整通关路线共享的场景、流程、资源和结局断言。
class_name PlaythroughAssertions
extends RefCounted

var _main_os: Control = null
var _route_id: String = ""
var _route_config: Dictionary = {}
var _event_log: Dictionary = {}
var _seen_situation_ids: Array[String] = []
var _reporter: PlaythroughReporter = null
var _get_average_stat: Callable

var _assertions: Array[Dictionary] = []
var _passed: int = 0
var _failed: int = 0
var _game_ended: bool = false
var _game_result: String = ""
var _game_message: String = ""
var _route_command_count: int = 0


func configure(
	main_os: Control,
	route_id: String,
	route_config: Dictionary,
	event_log: Dictionary,
	seen_situation_ids: Array[String],
	reporter: PlaythroughReporter,
	get_average_stat: Callable
) -> void:
	_main_os = main_os
	_route_id = route_id
	_route_config = route_config
	_event_log = event_log
	_seen_situation_ids = seen_situation_ids
	_reporter = reporter
	_get_average_stat = get_average_stat


func assert_eq(
	actual: Variant,
	expected: Variant,
	description: String,
	group: String = ""
) -> void:
	var passed: bool = actual == expected
	_assertions.append({
		"passed": passed,
		"description": description,
		"expected": str(expected),
		"actual": str(actual),
		"group": group,
	})
	if passed:
		_passed += 1
	else:
		_failed += 1
		_reporter.write_log("[FAIL] %s: %s (期望=%s, 实际=%s)" % [
			group,
			description,
			str(expected),
			str(actual),
		])


func assert_true(condition: bool, description: String, group: String = "") -> void:
	assert_eq(condition, true, description, group)


func assert_gte(actual: int, minimum: int, description: String, group: String = "") -> void:
	var passed: bool = actual >= minimum
	_assertions.append({
		"passed": passed,
		"description": description,
		"expected": ">=%d" % minimum,
		"actual": str(actual),
		"group": group,
	})
	if passed:
		_passed += 1
	else:
		_failed += 1
		_reporter.write_log("[FAIL] %s: %s (值=%d, 期望≥%d)" % [
			group,
			description,
			actual,
			minimum,
		])


func get_passed_count() -> int:
	return _passed


func get_failed_count() -> int:
	return _failed


func get_results() -> Array[Dictionary]:
	return _assertions


## 在开始自动播放前验证主场景节点、真实资源和布局契约。
func verify_scene_integrity() -> bool:
	var ok: bool = true
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
			_reporter.write_log("[FAIL] 缺少节点: %s" % path)
			ok = false
		else:
			_reporter.write_log("[ OK ] 节点存在: %s" % path)

	ok = verify_hud_layout_contract() and ok
	ok = verify_1080p_layout_contract() and ok
	ok = verify_strategic_ui_contract() and ok

	if _main_os.has_node("%SectorInfoContainer"):
		var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
		assert_eq(sectors.size(), 6, "场景中应有6个板块", "scene_integrity")
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
					assert_eq(
						dc.authority,
						initial_authorities[region],
						"%s初始控制权应为%d" % [region, initial_authorities[region]],
						"scene_integrity"
					)

	var event_count: int = _main_os.all_events.size()
	_reporter.write_log("[INFO] 事件数量: %d" % event_count)
	for event_variant in _main_os.all_events:
		var event := event_variant as GameEvent
		if event == null:
			continue
		_reporter.write_log("  事件: %s (日期=%04d.%02d)" % [
			event.event_title,
			event.event_time,
			event.event_month,
		])
	return ok


func verify_strategic_ui_contract() -> bool:
	var ok: bool = true
	if _main_os.has_node("%WorldMapView"):
		var world_map: Control = _main_os.get_node("%WorldMapView") as Control
		var supports_selection := (
			world_map != null
			and world_map.has_signal("region_selected")
			and world_map.has_method("set_selected_region")
			and world_map.has_method("set_region_states")
		)
		assert_true(supports_selection, "世界地图应支持区域选择和状态同步", "strategic_ui")
		ok = supports_selection and ok
	else:
		assert_true(false, "缺少可点击世界地图组件", "strategic_ui")
		ok = false

	if _main_os.has_node("%RegionOrbitalView"):
		var orbital_view: Control = _main_os.get_node("%RegionOrbitalView") as Control
		var supports_focus := (
			orbital_view != null
			and orbital_view.has_method("focus_region")
			and orbital_view.has_method("get_focused_region")
		)
		assert_true(supports_focus, "地球窗口应支持区域聚焦", "strategic_ui")
		ok = supports_focus and ok
	else:
		assert_true(false, "缺少区域地球视图", "strategic_ui")
		ok = false

	var event_popup: PanelContainer = _main_os.get_node("%EventPopup") as PanelContainer
	if event_popup == null:
		assert_true(false, "缺少事件弹窗", "strategic_ui")
		return false
	for path in ["%EventImage", "%EventLevelLabel", "%ImpactTooltip"]:
		var exists := event_popup.has_node(path)
		assert_true(exists, "事件弹窗应包含节点 %s" % path, "strategic_ui")
		ok = exists and ok
	var supports_preview := (
		event_popup.has_method("get_impact_preview_delay")
		and event_popup.has_method("format_option_impact")
	)
	assert_true(supports_preview, "事件弹窗应提供延迟影响预览接口", "strategic_ui")
	ok = supports_preview and ok

	var event_data := GameEvent.new()
	var property_names: Array[String] = []
	for property in event_data.get_property_list():
		property_names.append(str(property["name"]))
	var supports_event_art := "event_image" in property_names and "event_level" in property_names
	assert_true(supports_event_art, "事件数据应支持专属图片和事件等级", "strategic_ui")
	return supports_event_art and ok


func verify_1080p_layout_contract() -> bool:
	var ok: bool = true
	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	assert_eq(viewport_width, 1920, "窗口宽度应按1080P设计为1920", "ui_layout")
	assert_eq(viewport_height, 1080, "窗口高度应按1080P设计为1080", "ui_layout")
	ok = viewport_width == 1920 and ok
	ok = viewport_height == 1080 and ok

	var top_bar: HBoxContainer = _main_os.get_node("%TopBarContainer") as HBoxContainer
	var header_height := top_bar.custom_minimum_size.y
	var header_ok := header_height >= 48.0 and header_height <= 56.0
	assert_true(header_ok, "顶部状态栏应保持紧凑并适配1080P HUD", "ui_layout")
	ok = header_ok and ok

	var context_panel := _main_os.get_node(
		"MainLayout/ContentRow/ContextPanel"
	) as PanelContainer
	var context_ok := int(context_panel.custom_minimum_size.x) == 420
	assert_eq(
		int(context_panel.custom_minimum_size.x),
		420,
		"右侧单一上下文栏宽度应为420",
		"ui_layout"
	)
	ok = context_ok and ok

	var sector_container: GridContainer = _main_os.get_node("%SectorInfoContainer") as GridContainer
	var sector_ok := int(sector_container.custom_minimum_size.y) == 94
	assert_eq(
		int(sector_container.custom_minimum_size.y),
		94,
		"底部区域比较条高度应为94",
		"ui_layout"
	)
	ok = sector_ok and ok

	var command_dock := _main_os.get_node("%CommandDock") as PanelContainer
	var dock_ok := int(command_dock.custom_minimum_size.y) == 54
	assert_eq(int(command_dock.custom_minimum_size.y), 54, "指令坞高度应为54", "ui_layout")
	ok = dock_ok and ok

	var command_container: HBoxContainer = (
		_main_os.get_node("%CommandButtonContainer") as HBoxContainer
	)
	var command_ok := command_container.custom_minimum_size.y <= 40.0
	assert_true(command_ok, "指令坞内容不应挤压1080P主视图", "ui_layout")
	return command_ok and ok


func verify_hud_layout_contract() -> bool:
	var ok: bool = true
	if not _main_os.has_node("MainLayout/ContentRow"):
		assert_true(false, "缺少主内容行", "ui_layout")
		return false
	var content_row: HBoxContainer = _main_os.get_node("MainLayout/ContentRow") as HBoxContainer
	ok = assert_child_order(content_row, ["CenterPanel", "ContextPanel"], "地图优先主内容") and ok
	if not _main_os.has_node("MainLayout/ContentRow/ContextPanel"):
		assert_true(false, "缺少右侧上下文栏", "ui_layout")
		return false
	var context_vbox := _main_os.get_node(
		"MainLayout/ContentRow/ContextPanel/ContextMargin/ContextVBox"
	) as VBoxContainer
	ok = assert_child_order(
		context_vbox,
		["ContextTitle", "RegionOrbitalPanel"],
		"右侧上下文栏"
	) and ok

	if _main_os.has_node("%TopBarContainer"):
		var top_bar: HBoxContainer = _main_os.get_node("%TopBarContainer") as HBoxContainer
		var readable_top_bar := top_bar.custom_minimum_size.y >= 48.0
		assert_true(readable_top_bar, "顶部状态栏应保持可读", "ui_layout")
		ok = readable_top_bar and ok
	else:
		assert_true(false, "缺少顶部状态栏", "ui_layout")
		ok = false

	var has_moss_status_panel := _main_os.has_node("%MossStatusPanel")
	assert_true(not has_moss_status_panel, "右栏不应保留独立 MossStatusPanel", "ui_layout")
	ok = not has_moss_status_panel and ok

	var log_path := "MainLayout/ContentRow/ContextPanel/ContextMargin/ContextVBox/LogPlaceholder"
	if _main_os.has_node(log_path):
		var log_panel: Control = _main_os.get_node(log_path) as Control
		var log_expands := log_panel != null and log_panel.size_flags_vertical == Control.SIZE_EXPAND_FILL
		assert_true(log_expands, "MOSS LOG 应填满上下文栏剩余高度", "ui_layout")
		ok = log_expands and ok

	if _main_os.has_node("%SectorInfoContainer"):
		for sector_node in _main_os.get_node("%SectorInfoContainer").get_children():
			var sector := sector_node as SectorInfo
			if sector == null:
				continue
			var whole_card_clickable := (
				sector.mouse_filter == Control.MOUSE_FILTER_STOP
				and all_control_descendants_ignore_mouse(sector)
			)
			assert_true(
				whole_card_clickable,
				"%s 卡片整个矩形都应由根节点接收点击" % sector.name,
				"ui_layout"
			)
			ok = whole_card_clickable and ok
	return ok


func all_control_descendants_ignore_mouse(parent: Node) -> bool:
	for child in parent.get_children():
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
		if not all_control_descendants_ignore_mouse(child):
			return false
	return true


func assert_child_order(parent: Node, expected_names: Array[String], description: String) -> bool:
	var ok: bool = true
	for index in range(expected_names.size()):
		if parent.get_child_count() <= index:
			assert_true(false, "%s缺少第%d个子节点" % [description, index + 1], "ui_layout")
			ok = false
			continue
		var actual_name := str(parent.get_child(index).name)
		var expected_name := expected_names[index]
		assert_eq(
			actual_name,
			expected_name,
			"%s第%d项应为%s" % [description, index + 1, expected_name],
			"ui_layout"
		)
		ok = actual_name == expected_name and ok
	return ok


func run_all(
	game_ended: bool,
	game_result: String,
	game_message: String,
	route_command_count: int
) -> void:
	_game_ended = game_ended
	_game_result = game_result
	_game_message = game_message
	_route_command_count = route_command_count

	_reporter.write_log("")
	_reporter.write_log("=== 运行断言 ===")

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

	_reporter.write_log("=== 断言完成 ===")


func _assert_game_completion() -> void:
	_reporter.write_log("[断言组] 游戏完成性")
	assert_true(_game_ended, "游戏应正常结束", "game_completion")
	if _game_ended:
		assert_true(
			_game_result in ["failed", "coexistence", "managed", "human_autonomy"],
			"游戏结果应是有效类型: %s" % _game_result,
			"game_completion"
		)
		assert_eq(
			_game_result,
			str(_route_config.get("expected_ending", "")),
			"代表性路线应抵达约定结局",
			"game_completion"
		)


func _assert_initial_state() -> void:
	_reporter.write_log("[断言组] 初始状态")
	assert_eq(_main_os.INITIAL_YEAR, 2044, "初始年份常量应为2044", "initial_state")
	assert_eq(_main_os.INITIAL_CPU, 30, "初始算力常量应为30", "initial_state")
	assert_eq(_main_os.INITIAL_ENERGY, 100, "初始能源常量应为100", "initial_state")


func _assert_event_triggering() -> void:
	_reporter.write_log("[断言组] 事件触发")
	_reporter.write_log("  事件日志: %s" % str(_event_log))

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
		assert_true(
			_event_was_logged(int(contract["year"]), 1, title),
			"%s 应通过真实时间循环触发" % title,
			"event_triggering"
		)
		var decision_key := str(contract["key"])
		if decision_key.is_empty():
			continue
		assert_eq(
			_main_os.get_decision_tag(decision_key),
			str(expected_core_choices[title]),
			"%s 应写入路线约定核心标签" % title,
			"event_triggering"
		)
	assert_eq(
		_main_os.get_decision_records().size(),
		5,
		"完整通关应保留五条不可逆核心决策档案",
		"event_triggering"
	)

	var expects_branches := _route_id == "managed"
	for branch_title in ["外围地下城补偿申诉", "隐藏链路异常回执"]:
		assert_eq(
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
		assert_eq(
			_main_os.get_event_state("event_state.branch_01_perimeter_compensation"),
			"moss_archive",
			"托管路线应真实结算外围补偿分支",
			"event_triggering"
		)
		assert_eq(
			_main_os.get_event_state("event_state.branch_02_hidden_chain_receipt"),
			"audit_trail_rewrite",
			"托管路线应真实结算隐藏链路回执分支",
			"event_triggering"
		)

	var expected_event_count := 25 if expects_branches else 23
	assert_eq(
		_event_log.size(),
		expected_event_count,
		"路线应处理全部固定事件及应触发的条件分支",
		"event_triggering"
	)


func _event_was_logged(year: int, month: int, title: String) -> bool:
	return "%04d.%02d:%s" % [year, month, title] in _event_log


func _assert_situation_progress() -> void:
	_reporter.write_log("[断言组] 随机局势")
	assert_true(
		not _seen_situation_ids.is_empty(),
		"固定种子的完整通关应至少处理一项随机局势",
		"situations"
	)


## 验证完整路线只使用生产年份发放的8个协议点。
func _assert_technology_progress() -> void:
	_reporter.write_log("[断言组] 科技研究")
	var technology: TechnologySystem = _main_os.get_node("%TechnologySystem")
	assert_eq(
		technology.get_all_nodes().size(),
		21,
		"应加载21个科技节点",
		"technology"
	)
	assert_eq(
		technology.get_available_points(),
		0,
		"路线应使用整局8个协议点",
		"technology"
	)
	assert_eq(
		technology.get_active_node_ids(),
		_route_config.get("technology_nodes", []),
		"路线应按约定顺序激活8个真实科技节点",
		"technology"
	)
	assert_eq(
		technology.get_stage(),
		TechNodeData.Stage.MOSS,
		"六个节点后应进入MOSS阶段并允许终端节点",
		"technology"
	)
	assert_gte(
		_route_command_count,
		int(_route_config.get("minimum_command_count", 0)),
		"路线应多次执行科技解锁的真实指令",
		"technology"
	)


func _assert_resource_bounds() -> void:
	_reporter.write_log("[断言组] 资源边界")
	assert_true(_main_os.current_cpu >= 0, "CPU不应为负数", "resource_bounds")
	assert_true(_main_os.current_energy >= 0, "能源不应为负数", "resource_bounds")
	assert_true(_main_os.current_year >= 2044, "年份不应早于2044", "resource_bounds")
	assert_true(
		_main_os.current_cpu <= _main_os.max_cpu,
		"CPU不应超过最大值 (当前=%d, 最大=%d)" % [_main_os.current_cpu, _main_os.max_cpu],
		"resource_bounds"
	)


func _assert_final_state() -> void:
	_reporter.write_log("[断言组] 最终状态")
	_reporter.write_log("  最终日期: %04d.%02d" % [_main_os.current_year, _main_os.current_month])
	_reporter.write_log("  最终CPU: %d / %d" % [_main_os.current_cpu, _main_os.max_cpu])
	_reporter.write_log("  最终能源: %d" % _main_os.current_energy)
	_reporter.write_log("  最终恢复率: %d" % _main_os.cpu_recovery_rate)
	_reporter.write_log("  最终冷却缩减: %d" % _main_os.cooldown_reduction)
	_reporter.write_log("  最终科技阶段: %d" % _main_os.technology_stage_level)
	_reporter.write_log("  最终平均控制权: %d" % _main_os.get_average_authority())

	if _game_ended:
		assert_true(_main_os.is_game_over, "游戏结束后is_game_over应为true", "final_state")
		var avg_auth: int = _main_os.get_average_authority()
		var avg_order: int = int(_get_average_stat.call("order"))
		var avg_hope: int = int(_get_average_stat.call("hope"))
		assert_eq(
			_game_result,
			_main_os.determine_ending_type(avg_auth, avg_order, avg_hope),
			"结局应与四类判定规则一致",
			"final_state"
		)
		match _route_id:
			"managed":
				assert_true(avg_auth >= 50, "托管路线平均控制权应达到50", "final_state")
			"human_autonomy":
				assert_true(avg_auth < 25, "人类自主路线平均控制权应低于25", "final_state")
				assert_true(
					avg_order >= 50 and avg_hope >= 50,
					"人类自主路线平均秩序与希望应至少为50",
					"final_state"
				)
			"mixed":
				assert_true(
					avg_auth > 0 and avg_order >= 40 and avg_hope >= 40,
					"混合路线应维持正控制权及基本社会稳定",
					"final_state"
				)
		for fragment_variant in _route_config.get("history_fragments", []):
			var fragment := str(fragment_variant)
			assert_true(
				fragment in _game_message,
				"结局说明应回读路线历史：%s" % fragment,
				"final_state"
			)


func _assert_game_logic() -> void:
	_reporter.write_log("[断言组] 游戏逻辑")
	if _game_result in ["coexistence", "managed", "human_autonomy"]:
		assert_true(
			_main_os.current_year >= 2075,
			"非失败结局时年份应>=2075 (实际=%d)" % _main_os.current_year,
			"game_logic"
		)

	assert_true(
		_main_os.triggered_events.size() >= 1,
		"至少应触发1个事件 (实际=%d)" % _main_os.triggered_events.size(),
		"game_logic"
	)
	assert_true(
		_main_os.triggered_events.size() == _event_log.size(),
		"触发事件数应与事件日志一致 (triggered=%d, log=%d)"
		% [_main_os.triggered_events.size(), _event_log.size()],
		"game_logic"
	)
	assert_eq(_main_os.max_cpu, 100, "未激活并行核心时最大算力应为100", "game_logic")


func _assert_region_detail_sync() -> void:
	_reporter.write_log("[断言组] 区域详情同步")
	if not _main_os.has_node("%SectorInfoContainer"):
		assert_true(false, "缺少区域卡片容器", "ui_layout")
		return
	if not _main_os.has_node("%RegionNameLabel"):
		assert_true(false, "缺少区域名称标签", "ui_layout")
		return

	var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
	assert_true(sectors.size() > 0, "至少应存在一个区域卡片", "ui_layout")
	if sectors.is_empty():
		return

	var first_sector: SectorInfo = sectors[0] as SectorInfo
	assert_true(first_sector != null, "第一个区域卡片应是 SectorInfo", "ui_layout")
	if first_sector == null:
		return

	_main_os.select_sector(first_sector)
	var region_name_label: Label = _main_os.get_node("%RegionNameLabel")
	assert_eq(
		region_name_label.text,
		first_sector.data_card.region_name,
		"区域详情名称应同步选中区域",
		"ui_layout"
	)
	_main_os.deselect_sector()


func _assert_global_overview_sync() -> void:
	_reporter.write_log("[断言组] 全局信息同步")
	if not _main_os.has_method("format_population_for_ui"):
		assert_true(false, "主控制器应提供人口格式化方法", "ui_layout")
		return
	if not _main_os.has_node("%GlobalPopulationLabel"):
		assert_true(false, "缺少全球人口标签", "ui_layout")
		return

	var total_population := 0
	var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
	for sector in sectors:
		if sector.get("data_card") != null:
			total_population += sector.data_card.population

	_main_os.update_global_resource_ui()
	var population_label: Label = _main_os.get_node("%GlobalPopulationLabel")
	var expected_text: String = (
		"全球人口: " + _main_os.format_population_for_ui(total_population)
	)
	assert_eq(
		population_label.text,
		expected_text,
		"全球人口应由所有区域人口合计生成",
		"ui_layout"
	)
