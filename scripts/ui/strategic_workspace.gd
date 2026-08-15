## 战略工作区组件。
## 管理地图、区域卡、区域详情、全局概览、局势摘要和行动日志显示，不推进时间或结算资源。
class_name StrategicWorkspace
extends Control

signal region_selected(region_id: String)
signal region_selection_cleared
signal situation_approach_requested(instance_id: String, approach_id: String)
signal situation_node_option_requested(instance_id: String, option_id: String)
signal situation_details_requested(instance_id: String)

const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const REGION_RISK_HIGH: int = 20
const REGION_RISK_UNSTABLE: int = 40
const REGION_RISK_CONTROLLED: int = 70

const SIDE_MARGIN: float = 16.0
const TOP_MARGIN: float = 16.0
const TOP_BAR_HEIGHT: float = 52.0
const YEAR_PROGRESS_HEIGHT: float = 28.0
const COMMAND_DOCK_HEIGHT: float = 54.0
const SECTOR_INFO_HEIGHT: float = 94.0
const SEPARATION: float = 10.0

@onready var _content_row: HBoxContainer = $ContentRow
@onready var _center_panel: PanelContainer = $ContentRow/CenterPanel
@onready var _context_panel: ScrollContainer = $ContentRow/ContextPanel
@onready var _world_map: WorldMapView = $ContentRow/CenterPanel/CenterMargin/CenterVBox/WorldMapView
@onready var _orbital_view: RegionOrbitalView = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionOrbitalPanel/OrbitalMargin/OrbitalVBox/RegionOrbitalView
@onready var _global_map_selected_label: Label = $ContentRow/CenterPanel/CenterMargin/CenterVBox/GlobalViewHeader/GlobalMapSelectedLabel
@onready var _region_name_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionNameLabel
@onready var _region_description_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionDescriptionLabel
@onready var _region_order_bar: ProgressBar = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionOrderBar
@onready var _region_hope_bar: ProgressBar = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionHopeBar
@onready var _region_authority_bar: ProgressBar = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionAuthorityBar
@onready var _region_risk_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionRiskLabel
@onready var _region_situation_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationSummary/RegionSituationLabel
@onready var _situation_alert_panel: PanelContainer = $ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationAlertPanel
@onready var _alert_title_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationAlertPanel/AlertMargin/AlertVBox/AlertHeader/AlertTitleLabel
@onready var _alert_severity_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationAlertPanel/AlertMargin/AlertVBox/AlertHeader/AlertSeverityLabel
@onready var _alert_description_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationAlertPanel/AlertMargin/AlertVBox/AlertDescriptionLabel
@onready var _annual_status_panel: PanelContainer = $ContentRow/ContextPanel/ContextMargin/ContextVBox/AnnualStatusPanel
@onready var _annual_status_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/AnnualStatusPanel/AnnualStatusMargin/AnnualStatusVBox/AnnualStatusLabel
@onready var _approach_panel: PanelContainer = $ContentRow/ContextPanel/ContextMargin/ContextVBox/ApproachPanel
@onready var _current_approach_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/ApproachPanel/ApproachMargin/ApproachVBox/CurrentApproachLabel
@onready var _approach_list: VBoxContainer = $ContentRow/ContextPanel/ContextMargin/ContextVBox/ApproachPanel/ApproachMargin/ApproachVBox/ApproachList
@onready var _more_approaches_button: Button = $ContentRow/ContextPanel/ContextMargin/ContextVBox/ApproachPanel/ApproachMargin/ApproachVBox/MoreApproachesButton
@onready var _details_toggle: Button = $ContentRow/ContextPanel/ContextMargin/ContextVBox/DetailsToggle
@onready var _region_orbital_panel: PanelContainer = $ContentRow/ContextPanel/ContextMargin/ContextVBox/RegionOrbitalPanel
@onready var _global_overview_panel: PanelContainer = $ContentRow/ContextPanel/ContextMargin/ContextVBox/GlobalOverviewPanel
@onready var _global_population_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/GlobalOverviewPanel/GlobalOverviewMargin/GlobalOverviewVBox/GlobalPopulationLabel
@onready var _global_authority_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/GlobalOverviewPanel/GlobalOverviewMargin/GlobalOverviewVBox/GlobalAuthorityLabel
@onready var _global_stability_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/GlobalOverviewPanel/GlobalOverviewMargin/GlobalOverviewVBox/GlobalStabilityLabel
@onready var _global_threat_label: Label = $ContentRow/ContextPanel/ContextMargin/ContextVBox/GlobalOverviewPanel/GlobalOverviewMargin/GlobalOverviewVBox/GlobalThreatLabel
@onready var _sector_container: GridContainer = $SectorInfoContainer
@onready var _action_log_view: ActionLogView = $ContentRow/ContextPanel/ContextMargin/ContextVBox/LogPlaceholder

var _selected_sector: SectorInfo = null
var _situation_snapshots: Array[Dictionary] = []
var _event_focus_region: String = ""
var _current_cpu: int = 0
var _current_energy: int = 0
var _current_year: int = 2044
var _details_expanded: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_map.region_selected.connect(_on_world_map_region_selected)
	_more_approaches_button.pressed.connect(_on_more_approaches_pressed)
	_details_toggle.pressed.connect(_on_details_toggle_pressed)
	for child in _sector_container.get_children():
		if child is SectorInfo:
			(child as SectorInfo).sector_clicked.connect(_on_sector_clicked)
	_apply_theme()
	_set_details_visibility(false)
	_layout_children()
	_refresh_views()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_children()


## 返回当前工作区中装配的区域卡片节点。
func get_sector_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for child in _sector_container.get_children():
		result.append(child)
	return result


## 返回指定稳定区域 ID 对应的区域卡片。
func get_sector_by_region_id(region_id: String) -> SectorInfo:
	for child in _sector_container.get_children():
		if child is SectorInfo:
			var sector := child as SectorInfo
			if sector.data_card != null and sector.data_card.region_id == region_id:
				return sector
	return null


## 返回供领域服务消费的区域运行态数据列表。
func get_sector_data_list() -> Array[SectorData]:
	var result: Array[SectorData] = []
	for child in _sector_container.get_children():
		if child is SectorInfo and (child as SectorInfo).data_card != null:
			result.append((child as SectorInfo).data_card)
	return result


func get_selected_sector() -> SectorInfo:
	return _selected_sector


func get_selected_region_id() -> String:
	if _selected_sector == null or _selected_sector.data_card == null:
		return ""
	return _selected_sector.data_card.region_id


## 由主控制器传入局势快照并刷新所有战略显示。
func refresh_views(
	situation_snapshots: Array[Dictionary] = [],
	event_focus_region: String = ""
) -> void:
	_situation_snapshots = situation_snapshots.duplicate(true)
	_event_focus_region = event_focus_region
	_refresh_views()


## 刷新区域卡片和工作区内的地图/详情/全局摘要。
func refresh_sector_displays() -> void:
	for child in _sector_container.get_children():
		if child is SectorInfo and (child as SectorInfo).data_card != null:
			(child as SectorInfo).update_display()
	_refresh_views()


## 只更新区域详情和局势摘要；快照字段保持由主控制器显式传入。
func update_region_detail(
	situation_snapshots: Array[Dictionary],
	current_cpu: int = 0,
	current_energy: int = 0,
	current_year: int = 2044
) -> void:
	_situation_snapshots = situation_snapshots.duplicate(true)
	_current_cpu = current_cpu
	_current_energy = current_energy
	_current_year = current_year
	_update_region_detail_ui()
	_sync_world_map_states()
	_sync_orbital_focus()


## 刷新全局概览和地图状态。
func update_global_overview() -> void:
	_update_global_overview_ui()
	_sync_world_map_states()


func set_event_focus_region(region_id: String) -> void:
	_event_focus_region = region_id
	_sync_orbital_focus()


func select_sector(sector: SectorInfo) -> void:
	if sector == null:
		deselect_sector()
		return
	if _selected_sector != null and _selected_sector != sector:
		_selected_sector.set_selected(false)
	_selected_sector = sector
	_selected_sector.set_selected(true)
	_refresh_views()
	_emit_selection()


func deselect_sector() -> void:
	if _selected_sector != null:
		_selected_sector.set_selected(false)
	_selected_sector = null
	_refresh_views()
	_emit_selection()


func get_world_map() -> WorldMapView:
	return _world_map


func get_orbital_view() -> RegionOrbitalView:
	return _orbital_view


func get_content_rect() -> Rect2:
	return _content_row.get_global_rect()


func get_world_map_rect() -> Rect2:
	return _world_map.get_global_rect()


func get_region_name_text() -> String:
	return _region_name_label.text


func get_region_situation_text() -> String:
	return _region_situation_label.text


func get_global_population_text() -> String:
	return _global_population_label.text


func append_action_log_entry(entry: Dictionary) -> void:
	_action_log_view.append_entry(entry)


func clear_action_log() -> void:
	_action_log_view.clear()


func get_action_log_view() -> ActionLogView:
	return _action_log_view


func _layout_children() -> void:
	if _content_row == null:
		return
	var content_width := maxf(0.0, size.x - SIDE_MARGIN * 2.0)
	var content_top := TOP_MARGIN + TOP_BAR_HEIGHT + SEPARATION + YEAR_PROGRESS_HEIGHT + SEPARATION
	var content_bottom := size.y - SIDE_MARGIN - SECTOR_INFO_HEIGHT - SEPARATION - COMMAND_DOCK_HEIGHT - SEPARATION
	_content_row.position = Vector2(SIDE_MARGIN, content_top)
	_content_row.size = Vector2(content_width, maxf(0.0, content_bottom - content_top))
	_sector_container.position = Vector2(SIDE_MARGIN, size.y - SIDE_MARGIN - SECTOR_INFO_HEIGHT)
	_sector_container.size = Vector2(content_width, SECTOR_INFO_HEIGHT)


func _refresh_views() -> void:
	_update_region_detail_ui()
	_update_global_overview_ui()
	_sync_world_map_states()
	_sync_orbital_focus()


func _emit_selection() -> void:
	var region_id := get_selected_region_id()
	region_selected.emit(region_id)
	if region_id == "":
		region_selection_cleared.emit()


func _on_world_map_region_selected(region_id: String) -> void:
	if region_id == "":
		deselect_sector()
		return
	var sector := get_sector_by_region_id(region_id)
	if sector == null:
		deselect_sector()
		return
	select_sector(sector)


func _on_sector_clicked(sector: SectorInfo) -> void:
	if _selected_sector == sector:
		deselect_sector()
	else:
		select_sector(sector)


func _update_region_detail_ui() -> void:
	if _selected_sector == null or _selected_sector.data_card == null:
		_global_map_selected_label.text = "全球态势监控中"
		_region_name_label.text = "未选择区域"
		_region_description_label.text = "选择地图或底部区域条以查看详情。"
		_region_risk_label.text = "状态：待选择"
		_region_order_bar.value = 0
		_region_hope_bar.value = 0
		_region_authority_bar.value = 0
		_region_situation_label.text = "选择区域后显示局势"
		_region_situation_label.tooltip_text = ""
		_annual_status_label.text = "选择区域后显示年度状态。"
		_clear_situation_context()
		return

	var data := _selected_sector.data_card
	_global_map_selected_label.text = "当前监控：" + data.region_name
	_region_name_label.text = data.region_name
	_region_description_label.text = data.description
	_region_risk_label.text = _get_region_risk_text(data.authority)
	_region_order_bar.value = data.order
	_region_hope_bar.value = data.hope
	_region_authority_bar.value = data.authority
	_annual_status_label.text = _build_annual_status_text(data)
	_update_region_situation_summary_ui(data.region_id)
	_render_situation_context(data.region_id)


func _build_annual_status_text(data: SectorData) -> String:
	return "当前年度：%d  ·  秩序 %d%%  ·  希望 %d%%  ·  控制权 %d%%" % [
		_current_year,
		data.order,
		data.hope,
		data.authority,
	]


func _clear_situation_context() -> void:
	_situation_alert_panel.hide()
	_approach_panel.hide()
	_more_approaches_button.hide()
	_alert_title_label.text = "活跃局势"
	_alert_severity_label.text = "--"
	_alert_description_label.text = "选择区域后显示当前局势。"
	_current_approach_label.text = "当前方针：--"
	_clear_dynamic_buttons()


func _clear_dynamic_buttons() -> void:
	for child in _approach_list.get_children():
		_approach_list.remove_child(child)
		child.queue_free()


func _get_selected_situation(region_id: String) -> Dictionary:
	for snapshot in _situation_snapshots:
		if str(snapshot.get("region_id", "")) == region_id:
			return snapshot
	return {}


func _render_situation_context(region_id: String) -> void:
	var snapshot := _get_selected_situation(region_id)
	if snapshot.is_empty():
		_situation_alert_panel.show()
		_situation_alert_panel.add_theme_stylebox_override(
			"panel",
			MOSS_THEME.panel_style(MOSS_THEME.PANEL_BACKGROUND, MOSS_THEME.BORDER)
		)
		_alert_title_label.text = "当前局势"
		_alert_severity_label.text = "无活跃局势"
		_alert_description_label.text = "当前区域没有持续中的局势。"
		_alert_description_label.add_theme_color_override(
			"font_color",
			MOSS_THEME.TEXT_SECONDARY
		)
		_approach_panel.hide()
		_more_approaches_button.hide()
		_clear_dynamic_buttons()
		return

	_situation_alert_panel.show()
	var severity := int(snapshot.get("severity", 0))
	var is_opportunity := bool(snapshot.get("is_opportunity", false))
	var status_color := MOSS_THEME.ACCENT_GOLD if is_opportunity else MOSS_THEME.DANGER
	_situation_alert_panel.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.10, 0.035, 0.045, 0.96) if not is_opportunity else Color(0.09, 0.07, 0.035, 0.96),
			status_color,
			1
		)
	)
	_alert_title_label.text = str(snapshot.get("title", "未命名局势"))
	_alert_title_label.add_theme_color_override("font_color", status_color)
	_alert_severity_label.text = "%s  %d%%" % [
		str(snapshot.get("stage_name", "预警")),
		severity,
	]
	_alert_severity_label.add_theme_color_override("font_color", status_color)
	_alert_description_label.text = _build_situation_alert_text(snapshot)
	_alert_description_label.add_theme_color_override(
		"font_color",
		MOSS_THEME.TEXT_PRIMARY
	)
	_render_situation_actions(snapshot)


func _build_situation_alert_text(snapshot: Dictionary) -> String:
	var monthly_delta := int(snapshot.get("expected_monthly_delta", 0))
	var delta_prefix := "+" if monthly_delta > 0 else ""
	return "%s  ·  预计下月 %s%d  ·  %s" % [
		str(snapshot.get("description", "")),
		delta_prefix,
		monthly_delta,
		str(snapshot.get("approach_name", "尚未选择")),
	]


func _render_situation_actions(snapshot: Dictionary) -> void:
	_approach_panel.show()
	_clear_dynamic_buttons()
	var instance_id := str(snapshot.get("instance_id", ""))
	var node: Dictionary = snapshot.get("node", {})
	if bool(node.get("pending", false)):
		_current_approach_label.text = "待处理节点：%s" % str(node.get("title", "待处理节点"))
		var options: Array = node.get("options", [])
		for option_variant in options:
			if _approach_list.get_child_count() >= 2:
				break
			var option: Dictionary = option_variant
			var option_button := _build_action_button(
				str(option.get("display_name", "未命名方案")),
				"%s  ·  严重度 %+d" % [
					_build_cost_text(int(option.get("cpu_cost", 0)), int(option.get("energy_cost", 0))),
					int(option.get("severity_delta", 0)),
				]
			)
			var cpu_cost := int(option.get("cpu_cost", 0))
			var energy_cost := int(option.get("energy_cost", 0))
			option_button.disabled = _current_cpu < cpu_cost or _current_energy < energy_cost
			option_button.tooltip_text = (
				"资源不足，无法执行该方案：%s" % _build_cost_text(cpu_cost, energy_cost)
				if option_button.disabled
				else str(option.get("description", option.get("result_text", "执行该处置方案")))
			)
			option_button.pressed.connect(
				_on_inline_node_option_pressed.bind(instance_id, str(option.get("option_id", "")))
			)
			_approach_list.add_child(option_button)
		_more_approaches_button.text = "节点详情 / 完整说明"
		_more_approaches_button.show()
		return

	var current_id := str(snapshot.get("approach_id", ""))
	var lock_months := int(snapshot.get("switch_lock_months", 0))
	_current_approach_label.text = "当前方针：%s" % str(snapshot.get("approach_name", "尚未选择"))
	var approaches: Array = snapshot.get("approaches", [])
	var displayed := 0
	for approach_variant in approaches:
		if displayed >= 2:
			break
		var approach: Dictionary = approach_variant
		var approach_id := str(approach.get("approach_id", ""))
		if approach_id == current_id:
			continue
		var approach_button := _build_action_button(
			str(approach.get("display_name", "未命名方针")),
			_build_cost_text(
				int(approach.get("monthly_cpu_cost", 0)),
				int(approach.get("monthly_energy_cost", 0))
			)
		)
		var unavailable_reason := ""
		if lock_months > 0 and current_id != "":
			unavailable_reason = "重配置锁定剩余 %d 个月" % lock_months
		elif current_id != "" and _current_cpu < SituationSystem.APPROACH_SWITCH_CPU_COST:
			unavailable_reason = "算力不足（切换需要 %d）" % SituationSystem.APPROACH_SWITCH_CPU_COST
		if unavailable_reason != "":
			approach_button.disabled = true
			approach_button.tooltip_text = unavailable_reason
		else:
			approach_button.tooltip_text = str(approach.get("description", "选择该应对方针"))
		approach_button.pressed.connect(
			_on_inline_approach_pressed.bind(instance_id, approach_id)
		)
		_approach_list.add_child(approach_button)
		displayed += 1
	_more_approaches_button.text = "更多方针 / 完整说明"
	_more_approaches_button.visible = approaches.size() > displayed


func _build_cost_text(cpu_cost: int, energy_cost: int) -> String:
	var costs: Array[String] = []
	if cpu_cost > 0:
		costs.append("算力 %d/月" % cpu_cost)
	if energy_cost > 0:
		costs.append("能源 %d/月" % energy_cost)
	if costs.is_empty():
		return "无持续资源消耗"
	return "、".join(costs)


func _build_action_button(title: String, detail: String) -> Button:
	var button := Button.new()
	button.text = "%s  ·  %s" % [title, detail]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 38)
	button.custom_maximum_size = Vector2(372, 0)
	button.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	button.add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(MOSS_THEME.PANEL_BACKGROUND, MOSS_THEME.BORDER)
	)
	button.add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(MOSS_THEME.PANEL_BACKGROUND_HOVER, MOSS_THEME.ACCENT_CYAN, 2)
	)
	button.add_theme_stylebox_override(
		"disabled",
		MOSS_THEME.button_style(Color(0.025, 0.04, 0.05, 0.88), MOSS_THEME.BORDER)
	)
	return button


func _update_region_situation_summary_ui(region_id: String = "") -> void:
	var selected_region_id := region_id if region_id != "" else get_selected_region_id()
	if selected_region_id == "":
		_region_situation_label.text = "选择区域后显示局势"
		_region_situation_label.tooltip_text = ""
		return

	var summary := "当前无活跃局势"
	for snapshot in _situation_snapshots:
		if str(snapshot.get("region_id", "")) != selected_region_id:
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
	_region_situation_label.text = summary
	_region_situation_label.tooltip_text = summary


func _sync_world_map_states() -> void:
	var states: Dictionary = {}
	for child in _sector_container.get_children():
		if child is not SectorInfo or (child as SectorInfo).data_card == null:
			continue
		var data := (child as SectorInfo).data_card
		states[data.region_id] = {
			"order": data.order,
			"hope": data.hope,
			"authority": data.authority,
			"situation_count": 0,
		}

	for snapshot in _situation_snapshots:
		var region_id := str(snapshot.get("region_id", ""))
		if not states.has(region_id):
			continue
		states[region_id]["situation_count"] = int(states[region_id].get("situation_count", 0)) + 1

	_world_map.set_region_states(states)
	_world_map.set_selected_region(get_selected_region_id())


func _sync_orbital_focus() -> void:
	var region_id := _event_focus_region
	if region_id == "":
		region_id = get_selected_region_id()
	_orbital_view.focus_region(region_id)


func _update_global_overview_ui() -> void:
	var total_population := 0
	var total_order := 0
	var total_hope := 0
	var total_authority := 0
	var count := 0
	for child in _sector_container.get_children():
		if child is not SectorInfo or (child as SectorInfo).data_card == null:
			continue
		var data := (child as SectorInfo).data_card
		total_population += data.population
		total_order += data.order
		total_hope += data.hope
		total_authority += data.authority
		count += 1

	if count == 0:
		_global_population_label.text = "全球人口: --"
		_global_authority_label.text = "平均控制权: --"
		_global_stability_label.text = "系统稳定性: --"
		_global_threat_label.text = "威胁等级: --"
		return

	var avg_order := floori(float(total_order) / float(count))
	var avg_hope := floori(float(total_hope) / float(count))
	var avg_authority := floori(float(total_authority) / float(count))
	var stability := floori(float(avg_order + avg_hope + avg_authority) / 3.0)
	_global_population_label.text = "全球人口: " + format_population_for_ui(total_population)
	_global_authority_label.text = "平均控制权: %d%%" % avg_authority
	_global_stability_label.text = "系统稳定性: %d%%" % stability
	_global_threat_label.text = "威胁等级: " + _get_global_threat_text(avg_authority)


func format_population_for_ui(value: int) -> String:
	if value >= 100000000:
		return "%.1f亿" % (float(value) / 100000000.0)
	if value >= 10000:
		return "%.1f万" % (float(value) / 10000.0)
	return str(value)


func _get_region_risk_text(authority: int) -> String:
	if authority < REGION_RISK_HIGH:
		return "状态：高风险"
	if authority < REGION_RISK_UNSTABLE:
		return "状态：不稳定"
	if authority < REGION_RISK_CONTROLLED:
		return "状态：可控"
	return "状态：稳定"


func _get_global_threat_text(avg_authority: int) -> String:
	if avg_authority < REGION_RISK_HIGH:
		return "高风险"
	if avg_authority < REGION_RISK_UNSTABLE:
		return "中等"
	return "稳定"


func _on_more_approaches_pressed() -> void:
	var snapshot := _get_selected_situation(get_selected_region_id())
	if not snapshot.is_empty():
		situation_details_requested.emit(str(snapshot.get("instance_id", "")))


func _on_inline_approach_pressed(instance_id: String, approach_id: String) -> void:
	situation_approach_requested.emit(instance_id, approach_id)


func _on_inline_node_option_pressed(instance_id: String, option_id: String) -> void:
	situation_node_option_requested.emit(instance_id, option_id)


func _on_details_toggle_pressed() -> void:
	_set_details_visibility(not _details_expanded)


func _set_details_visibility(expanded: bool) -> void:
	_details_expanded = expanded
	_region_orbital_panel.visible = expanded
	_global_overview_panel.visible = expanded
	_action_log_view.visible = expanded
	_details_toggle.text = "收起全局信息与日志" if expanded else "展开全局信息与日志"


func _apply_theme() -> void:
	for panel in [
		_center_panel,
		_context_panel,
		_region_orbital_panel,
		_situation_alert_panel,
		_annual_status_panel,
		_approach_panel,
		_global_overview_panel,
		_action_log_view,
	]:
		panel.add_theme_stylebox_override("panel", MOSS_THEME.panel_style())

	for bar_data in [
		[_region_order_bar, MOSS_THEME.ORDER],
		[_region_hope_bar, MOSS_THEME.HOPE],
		[_region_authority_bar, MOSS_THEME.AUTHORITY],
	]:
		var bar: ProgressBar = bar_data[0]
		var color: Color = bar_data[1]
		bar.custom_minimum_size.y = 16.0
		bar.add_theme_stylebox_override("background", MOSS_THEME.progress_background_style())
		bar.add_theme_stylebox_override("fill", MOSS_THEME.progress_fill_style(color))
		bar.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
		bar.add_theme_font_size_override("font_size", 12)
	_region_situation_label.add_theme_color_override("font_color", MOSS_THEME.ACCENT_GOLD)
	var situation_title := $ContentRow/ContextPanel/ContextMargin/ContextVBox/SituationSummary/SituationSummaryTitle as Label
	situation_title.add_theme_color_override("font_color", MOSS_THEME.ACCENT_CYAN)
	_details_toggle.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	_more_approaches_button.add_theme_color_override("font_color", MOSS_THEME.ACCENT_GOLD)
