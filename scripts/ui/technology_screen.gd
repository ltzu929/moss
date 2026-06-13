## 科技控制台界面
## 绑定静态场景中的三路线科技矩阵、节点详情和不可逆激活交互
class_name TechnologyScreen
extends PanelContainer

# ============================================================
# 信号定义
# ============================================================

## 科技控制台关闭后发出
signal screen_closed()

# ============================================================
# 常量
# ============================================================

## 科技节点卡片脚本
const TECHNOLOGY_NODE_CARD_SCRIPT := preload(
	"res://scripts/ui/technology_node_card.gd"
)

## 科技路线显示名称
const ROUTE_NAMES: Dictionary = {
	TechNodeData.Route.MANAGED: "托管网络",
	TechNodeData.Route.CORE: "核心演化",
	TechNodeData.Route.HUMAN: "人类赋能",
}
## 科技路线用途说明
const ROUTE_DESCRIPTIONS: Dictionary = {
	TechNodeData.Route.MANAGED: "让文明基础设施逐步依赖 MOSS 的统一调度。",
	TechNodeData.Route.CORE: "提升 MOSS 的算力、恢复与执行效率。",
	TechNodeData.Route.HUMAN: "让人类组织获得独立维持文明的能力。",
}
## 系统形态阶段显示名称
const STAGE_NAMES: Dictionary = {
	TechNodeData.Stage.C550: "550C",
	TechNodeData.Stage.W550: "550W",
	TechNodeData.Stage.MOSS: "MOSS",
}
## 节点状态显示名称
const STATE_NAMES: Dictionary = {
	"active": "已激活",
	"available": "可激活",
	"points_locked": "协议点不足",
	"prerequisite_locked": "前置未满足",
	"stage_locked": "阶段未解锁",
}

# ============================================================
# 状态变量
# ============================================================

## 当前绑定的科技系统
var _technology: TechnologySystem
## 打开界面时暂停和关闭界面时恢复的年份计时器
var _timer: Timer
## 打开界面前计时器是否已经停止
var _timer_was_stopped: bool = true
## 当前选中的节点 ID
var _selected_node_id: String = ""
## 已进入二次确认状态的节点 ID
var _confirming_node_id: String = ""
## 节点 ID 到静态卡片的索引
var _node_cards: Dictionary = {}
## 路线枚举到静态路线按钮的索引
var _route_buttons: Dictionary = {}

## 顶部状态和右侧详情区域的静态控件引用
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

# ============================================================
# 生命周期函数
# ============================================================

## 索引静态场景节点并隐藏科技控制台
func _ready() -> void:
	hide()
	set_process_unhandled_input(true)
	_index_scene_nodes()

# ============================================================
# 公共方法
# ============================================================

## 打开科技控制台并暂停年份计时
## 同步当前资源、控制权、年份和科技节点状态
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
	_resource_label.text = "算力 %d  /  能源 %d  /  平均控制权 %d%%" % [
		cpu,
		energy,
		authority,
	]
	_year_label.text = "系统时间  %d" % year
	_connect_system_signals()
	_reset_route_filter()
	_refresh_status()
	show()
	move_to_front()


## 关闭科技控制台，并按打开前状态恢复年份计时
func close_screen() -> void:
	hide()
	_selected_node_id = ""
	_confirming_node_id = ""
	if _timer != null and not _timer_was_stopped:
		_timer.start()
	screen_closed.emit()

# ============================================================
# 输入回调
# ============================================================

## 响应取消输入并关闭当前可见的科技控制台
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()

# ============================================================
# 场景索引
# ============================================================

## 索引场景中预置的路线按钮和12张科技节点卡
func _index_scene_nodes() -> void:
	_route_buttons = {
		TechNodeData.Route.MANAGED: %ManagedRouteButton,
		TechNodeData.Route.CORE: %CoreRouteButton,
		TechNodeData.Route.HUMAN: %HumanRouteButton,
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
	if _node_cards.size() != 12:
		push_error("科技场景必须预置12张唯一节点卡，当前为%d张" % _node_cards.size())

# ============================================================
# 状态刷新
# ============================================================

## 刷新形态、协议点和各路线激活数量
func _refresh_status() -> void:
	if _technology == null:
		return
	_model_label.text = STAGE_NAMES[_technology.get_stage()]
	_points_label.text = str(_technology.get_available_points())
	for route in ROUTE_NAMES:
		var count := 0
		for node_data in _technology.get_all_nodes():
			if node_data.route == route and _technology.is_active(node_data.node_id):
				count += 1
		_route_buttons[route].text = "%s\n%s\n%d / 4" % [
			ROUTE_NAMES[route],
			ROUTE_DESCRIPTIONS[route],
			count,
		]
	_refresh_nodes()
	_refresh_details()


## 刷新所有静态节点卡的文本、状态样式和选中状态
func _refresh_nodes() -> void:
	if _technology == null:
		return
	for node_id in _node_cards:
		var card: Node = _node_cards[node_id]
		card.call(
			"refresh_state",
			_technology.get_activation_state(node_id),
			node_id == _selected_node_id
		)


## 刷新当前选中节点的说明、前置条件和激活按钮状态
func _refresh_details() -> void:
	if _technology == null or _selected_node_id == "":
		_activate_button.text = "选择节点以查看协议"
		_activate_button.disabled = true
		return
	var node_data := _technology.get_node_data(_selected_node_id)
	var state := _technology.get_activation_state(_selected_node_id)
	_detail_route.text = "%s  /  %s" % [
		ROUTE_NAMES[node_data.route],
		STAGE_NAMES[node_data.stage],
	]
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
	requirements.append("阶段：%s" % STAGE_NAMES[node_data.stage])
	requirements.append("消耗：1 协议点")
	_detail_requirements.text = "\n".join(requirements)

	if state == "active":
		_activate_button.text = "协议已激活"
		_activate_button.disabled = true
	elif state == "available":
		_activate_button.disabled = false
		_activate_button.text = (
			"确认不可逆激活"
			if _confirming_node_id == _selected_node_id
			else "激活协议"
		)
	else:
		_activate_button.text = STATE_NAMES.get(state, "不可激活")
		_activate_button.disabled = true

# ============================================================
# 交互回调
# ============================================================

## 选中科技节点，并清除其他节点的二次确认状态
func _on_node_selected(node_id: String) -> void:
	_selected_node_id = node_id
	_confirming_node_id = ""
	_refresh_nodes()
	_refresh_details()


## 处理节点的两步不可逆激活
## 第一次点击进入确认状态，第二次点击才提交到科技系统
func _on_activate_pressed() -> void:
	if _selected_node_id == "":
		return
	if _confirming_node_id != _selected_node_id:
		_confirming_node_id = _selected_node_id
		_refresh_details()
		return
	if _technology.activate(_selected_node_id):
		_confirming_node_id = ""
		_refresh_status()


## 高亮指定路线，并降低其他路线节点的显示强度
func _on_route_selected(route: TechNodeData.Route) -> void:
	for node_id in _node_cards:
		var card := _node_cards[node_id] as Control
		var node_data: TechNodeData = card.get("node_data")
		card.modulate = (
			Color.WHITE
			if node_data.route == route
			else Color(0.48, 0.56, 0.60, 1.0)
		)


## 恢复全部路线节点亮度，保持每次打开科技控制台时的初始显示
func _reset_route_filter() -> void:
	for card in _node_cards.values():
		(card as Control).modulate = Color.WHITE


## 选择托管网络路线
func _on_managed_route_pressed() -> void:
	_on_route_selected(TechNodeData.Route.MANAGED)


## 选择核心演化路线
func _on_core_route_pressed() -> void:
	_on_route_selected(TechNodeData.Route.CORE)


## 选择人类赋能路线
func _on_human_route_pressed() -> void:
	_on_route_selected(TechNodeData.Route.HUMAN)


## 连接科技系统状态信号，避免重复连接
func _connect_system_signals() -> void:
	if not _technology.points_changed.is_connected(_on_system_changed):
		_technology.points_changed.connect(_on_system_changed)
	if not _technology.node_activated.is_connected(_on_node_activated):
		_technology.node_activated.connect(_on_node_activated)
	if not _technology.stage_changed.is_connected(_on_system_changed):
		_technology.stage_changed.connect(_on_system_changed)


## 协议点或系统形态变化后刷新界面状态
func _on_system_changed(_value: int) -> void:
	_refresh_status()


## 节点激活后刷新界面状态
func _on_node_activated(_node_id: String) -> void:
	_refresh_status()
