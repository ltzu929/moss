@tool
class_name TechnologyScreen
extends Control

signal screen_closed()

const TECHNOLOGY_NODE_CARD_SCRIPT := preload("res://scripts/ui/technology_node_card.gd")
const MAX_WINDOW_SIZE := Vector2(1680.0, 900.0)
const MIN_WINDOW_SIZE := Vector2(960.0, 560.0)
const VIEWPORT_MARGIN := 32.0

const ROUTE_NAMES: Dictionary = {
	TechNodeData.Route.MANAGED: "托管网络",
	TechNodeData.Route.CORE: "核心演化",
	TechNodeData.Route.HUMAN: "人类赋能",
}
const ROUTE_DESCRIPTIONS: Dictionary = {
	TechNodeData.Route.MANAGED: "基础设施托管、权限链与文明级协调",
	TechNodeData.Route.CORE: "算力、恢复效率与 MOSS 核心形态",
	TechNodeData.Route.HUMAN: "区域自治、组织韧性与协作治理",
}
const STAGE_NAMES: Dictionary = {
	TechNodeData.Stage.C550: "550C",
	TechNodeData.Stage.W550: "550W",
	TechNodeData.Stage.MOSS: "MOSS",
}
const STATE_NAMES: Dictionary = {
	"active": "已激活",
	"available": "可激活",
	"points_locked": "协议点不足",
	"prerequisite_locked": "前置未满足",
	"stage_locked": "阶段未解锁",
	"exclusive_locked": "终端互斥",
}

@export var editor_preview_route: TechNodeData.Route = TechNodeData.Route.MANAGED:
	set(value):
		editor_preview_route = value
		if Engine.is_editor_hint() and is_inside_tree():
			_switch_route(value, false)

var _technology: TechnologySystem
var _timer: Timer
var _timer_was_stopped: bool = true
var _selected_node_id: String = ""
var _confirming_node_id: String = ""
var _node_cards: Dictionary = {}
var _route_buttons: Dictionary = {}
var _route_pages: Dictionary = {}
var _current_route: TechNodeData.Route = TechNodeData.Route.MANAGED
var _layout_viewport: Viewport

@onready var _window_panel: PanelContainer = %WindowPanel
@onready var _model_label: Label = %ModelLabel
@onready var _points_label: Label = %PointsLabel
@onready var _resource_label: Label = %ResourceLabel
@onready var _year_label: Label = %YearLabel
@onready var _detail_route: Label = %DetailRoute
@onready var _detail_name: Label = %DetailName
@onready var _detail_description: Label = %DetailDescription
@onready var _detail_effect: Label = %DetailEffect
@onready var _detail_risk: Label = %DetailRisk
@onready var _detail_requirements: Label = %DetailRequirements
@onready var _activate_button: Button = %ActivateButton


func _ready() -> void:
	set_process_unhandled_input(true)
	_index_scene_nodes()
	_layout_viewport = get_viewport()
	if not _layout_viewport.size_changed.is_connected(_update_window_size):
		_layout_viewport.size_changed.connect(_update_window_size)
	_update_window_size()
	_reset_details()
	if Engine.is_editor_hint():
		_current_route = editor_preview_route
		_switch_route(_current_route, false)
		_refresh_route_tabs()
	else:
		hide()
		_switch_route(_current_route, false)


func _exit_tree() -> void:
	if is_instance_valid(_layout_viewport) and _layout_viewport.size_changed.is_connected(_update_window_size):
		_layout_viewport.size_changed.disconnect(_update_window_size)
	_layout_viewport = null


func open_screen(
	technology: TechnologySystem,
	cpu: int,
	energy: int,
	authority: int,
	year: int,
	timer: Timer
) -> void:
	_technology = technology
	_timer = timer
	_timer_was_stopped = timer.is_stopped()
	timer.stop()
	_resource_label.text = "算力 %d  /  能源 %d  /  平均控制权 %d%%" % [cpu, energy, authority]
	_year_label.text = "系统时间  %d" % year
	_connect_system_signals()
	_update_window_size()
	_switch_route(_current_route, false)
	_refresh_status()
	show()
	move_to_front()


func close_screen() -> void:
	hide()
	_clear_selection()
	if _timer != null and not _timer_was_stopped:
		_timer.start()
	screen_closed.emit()


func _calculate_window_size(viewport_size: Vector2) -> Vector2:
	var available := Vector2(
		maxf(320.0, viewport_size.x - VIEWPORT_MARGIN * 2.0),
		maxf(320.0, viewport_size.y - VIEWPORT_MARGIN * 2.0)
	)
	return Vector2(
		minf(MAX_WINDOW_SIZE.x, maxf(MIN_WINDOW_SIZE.x, available.x)),
		minf(MAX_WINDOW_SIZE.y, maxf(MIN_WINDOW_SIZE.y, available.y))
	)


func _update_window_size() -> void:
	if not is_instance_valid(_layout_viewport) or not is_instance_valid(_window_panel):
		return
	_window_panel.custom_minimum_size = _calculate_window_size(_layout_viewport.get_visible_rect().size)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()


func _index_scene_nodes() -> void:
	_route_buttons = {
		TechNodeData.Route.MANAGED: %ManagedRouteButton,
		TechNodeData.Route.CORE: %CoreRouteButton,
		TechNodeData.Route.HUMAN: %HumanRouteButton,
	}
	_route_pages = {
		TechNodeData.Route.MANAGED: %ManagedRoutePage,
		TechNodeData.Route.CORE: %CoreRoutePage,
		TechNodeData.Route.HUMAN: %HumanRoutePage,
	}
	_node_cards.clear()
	for child in find_children("*", "Button", true, false):
		if child.get_script() != TECHNOLOGY_NODE_CARD_SCRIPT:
			continue
		var node_data: TechNodeData = child.get("node_data")
		if node_data == null or node_data.node_id == "":
			push_error("科技节点卡片未绑定有效资源: " + child.name)
			continue
		if node_data.node_id in _node_cards:
			push_error("科技节点卡片 ID 重复: " + node_data.node_id)
			continue
		_node_cards[node_data.node_id] = child
		if not child.node_selected.is_connected(_on_node_selected):
			child.node_selected.connect(_on_node_selected)
	if _node_cards.size() != 21:
		push_error("科技场景必须预置21张唯一节点卡，当前为%d张" % _node_cards.size())


func _refresh_status() -> void:
	if _technology == null:
		_refresh_route_tabs()
		return
	_model_label.text = STAGE_NAMES[_technology.get_stage()]
	_points_label.text = str(_technology.get_available_points())
	_refresh_route_tabs()
	_refresh_nodes()
	_refresh_details()


func _refresh_route_tabs() -> void:
	for route in ROUTE_NAMES:
		var count := 0
		if _technology != null:
			for node_data in _technology.get_all_nodes():
				if node_data.route == route and _technology.is_active(node_data.node_id):
					count += 1
		var button: Button = _route_buttons[route]
		button.text = "%s  %d / 7\n%s" % [ROUTE_NAMES[route], count, ROUTE_DESCRIPTIONS[route]]
		button.button_pressed = route == _current_route


func _refresh_nodes() -> void:
	if _technology == null:
		return
	for node_id in _node_cards:
		var card: Node = _node_cards[node_id]
		card.call("refresh_state", _technology.get_activation_state(node_id), node_id == _selected_node_id)
	for page in _route_pages.values():
		var graph := (page as Node).get_node_or_null("RouteGraph") as Control
		if graph != null:
			graph.queue_redraw()


func _reset_details() -> void:
	if not is_instance_valid(_detail_name):
		return
	_detail_route.text = "请选择科技节点"
	_detail_name.text = "未选择"
	_detail_description.text = ""
	_detail_effect.text = ""
	_detail_risk.text = ""
	_detail_risk.visible = false
	_detail_requirements.text = ""
	_activate_button.text = "选择节点以查看协议"
	_activate_button.disabled = true


func _refresh_details() -> void:
	if _technology == null or _selected_node_id == "":
		_reset_details()
		return
	var node_data := _technology.get_node_data(_selected_node_id)
	var state := _technology.get_activation_state(_selected_node_id)
	_detail_route.text = "%s  /  %s" % [ROUTE_NAMES[node_data.route], STAGE_NAMES[node_data.stage]]
	_detail_name.text = node_data.display_name
	_detail_description.text = node_data.description
	_detail_effect.text = node_data.effect_text
	_detail_risk.text = node_data.risk_text
	_detail_risk.visible = node_data.risk_text != ""

	var requirements: Array[String] = []
	if node_data.prerequisite_ids.is_empty():
		requirements.append("无节点前置")
	else:
		for prerequisite_id in node_data.prerequisite_ids:
			var prerequisite := _technology.get_node_data(prerequisite_id)
			var marker := "✓" if _technology.is_active(prerequisite_id) else "□"
			requirements.append("%s %s" % [marker, prerequisite.display_name])
	var conflict_id := _technology.get_exclusive_conflict(_selected_node_id)
	if conflict_id != "":
		var conflict := _technology.get_node_data(conflict_id)
		requirements.append("互斥：%s 已激活" % conflict.display_name)
	requirements.append("阶段：%s" % STAGE_NAMES[node_data.stage])
	requirements.append("消耗：1 协议点")
	_detail_requirements.text = "\n".join(requirements)

	if state == "active":
		_activate_button.text = "协议已激活"
		_activate_button.disabled = true
	elif state == "available":
		_activate_button.disabled = false
		_activate_button.text = "确认不可逆激活" if _confirming_node_id == _selected_node_id else "激活协议"
	else:
		_activate_button.text = STATE_NAMES.get(state, "不可激活")
		_activate_button.disabled = true


func _clear_selection() -> void:
	_selected_node_id = ""
	_confirming_node_id = ""
	_reset_details()
	if _technology != null:
		_refresh_nodes()


func _switch_route(route: TechNodeData.Route, clear_selection: bool = true) -> void:
	_current_route = route
	for page_route in _route_pages:
		(_route_pages[page_route] as Control).visible = page_route == route
	if clear_selection:
		_clear_selection()
	_refresh_route_tabs()


func _on_node_selected(node_id: String) -> void:
	_selected_node_id = node_id
	_confirming_node_id = ""
	_refresh_nodes()
	_refresh_details()


func _on_activate_pressed() -> void:
	if _selected_node_id == "" or _technology == null:
		return
	if _confirming_node_id != _selected_node_id:
		_confirming_node_id = _selected_node_id
		_refresh_details()
		return
	if _technology.activate(_selected_node_id):
		_confirming_node_id = ""
		_refresh_status()


func _on_managed_route_pressed() -> void:
	_switch_route(TechNodeData.Route.MANAGED)


func _on_core_route_pressed() -> void:
	_switch_route(TechNodeData.Route.CORE)


func _on_human_route_pressed() -> void:
	_switch_route(TechNodeData.Route.HUMAN)


func _connect_system_signals() -> void:
	if not _technology.points_changed.is_connected(_on_system_changed):
		_technology.points_changed.connect(_on_system_changed)
	if not _technology.node_activated.is_connected(_on_node_activated):
		_technology.node_activated.connect(_on_node_activated)
	if not _technology.stage_changed.is_connected(_on_system_changed):
		_technology.stage_changed.connect(_on_system_changed)


func _on_system_changed(_value: int) -> void:
	_refresh_status()


func _on_node_activated(_node_id: String) -> void:
	_refresh_status()
