## 科技控制台界面
## 运行时构建三路线科技矩阵、节点详情和不可逆激活交互
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

## MOSS 界面主题工具
const MossTheme := preload("res://scripts/ui/moss_ui_theme.gd")

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
## 节点 ID 到节点按钮的索引
var _node_buttons: Dictionary = {}
## 路线枚举到路线按钮的索引
var _route_buttons: Dictionary = {}
## 路线和阶段组合键到节点容器的索引
var _route_panels: Dictionary = {}

## 顶部状态和右侧详情区域的控件引用
var _model_label: Label
var _points_label: Label
var _resource_label: Label
var _year_label: Label
var _detail_route: Label
var _detail_name: Label
var _detail_description: Label
var _detail_effect: Label
var _detail_risk: Label
var _detail_requirements: Label
var _activate_button: Button
var _research_label: Label

# ============================================================
# 生命周期函数
# ============================================================

## 初始化并隐藏科技控制台
func _ready() -> void:
	hide()
	set_process_unhandled_input(true)
	_build_interface()

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
	_rebuild_nodes()
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
# 界面构建
# ============================================================

## 构建科技控制台的头部、路线、矩阵、详情和底部区域
func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	add_theme_stylebox_override(
		"panel",
		MossTheme.panel_style(MossTheme.BACKGROUND, MossTheme.BORDER_BRIGHT)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	body.add_child(_build_routes_panel())
	body.add_child(_build_matrix_panel())
	body.add_child(_build_details_panel())
	root.add_child(_build_footer())


## 构建顶部形态、协议点、资源、年份和关闭按钮区域
func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 82
	panel.add_theme_stylebox_override(
		"panel",
		MossTheme.panel_style(Color(0.018, 0.045, 0.062, 0.96), MossTheme.BORDER)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)

	var title_box := VBoxContainer.new()
	title_box.custom_minimum_size.x = 520
	row.add_child(title_box)
	var archive := _label("MOSS EVOLUTION ARCHIVE", 12, MossTheme.ACCENT_CYAN)
	title_box.add_child(archive)
	title_box.add_child(_label("核心协议架构", 30, MossTheme.TEXT_PRIMARY))

	_model_label = _metric(row, "当前形态")
	_points_label = _metric(row, "协议点")
	_resource_label = _metric(row, "运行资源", 330)
	_year_label = _metric(row, "系统时间", 210)

	var close := Button.new()
	close.text = "关闭  ×"
	close.custom_minimum_size = Vector2(112, 44)
	close.pressed.connect(close_screen)
	_style_button(close)
	row.add_child(close)
	return panel


## 构建左侧三条科技路线的筛选按钮区域
func _build_routes_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 278
	panel.add_theme_stylebox_override(
		"panel",
		MossTheme.panel_style(MossTheme.PANEL_BACKGROUND, MossTheme.BORDER)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("演化路线", 13, MossTheme.ACCENT_CYAN))
	for route in ROUTE_NAMES:
		var route_button := Button.new()
		route_button.custom_minimum_size = Vector2(0, 148)
		route_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		route_button.text = "%s\n%s\n0 / 4" % [
			ROUTE_NAMES[route],
			ROUTE_DESCRIPTIONS[route],
		]
		route_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_button.pressed.connect(_on_route_selected.bind(route))
		_style_button(route_button)
		box.add_child(route_button)
		_route_buttons[route] = route_button
	return panel


## 构建按路线和阶段排列的科技节点矩阵
func _build_matrix_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		MossTheme.panel_style(Color(0.012, 0.035, 0.050, 0.92), MossTheme.BORDER)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	var route_spacer := Control.new()
	route_spacer.custom_minimum_size.x = 96
	heading.add_child(route_spacer)
	for stage in STAGE_NAMES:
		var stage_label := _label(
			STAGE_NAMES[stage],
			18,
			MossTheme.ACCENT_CYAN
		)
		stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(stage_label)
	box.add_child(heading)

	for route in ROUTE_NAMES:
		var row := HBoxContainer.new()
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		var route_label := _label(ROUTE_NAMES[route], 15, MossTheme.TEXT_SECONDARY)
		route_label.custom_minimum_size.x = 96
		route_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(route_label)
		for stage in STAGE_NAMES:
			var stage_box := VBoxContainer.new()
			stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			stage_box.add_theme_constant_override("separation", 8)
			row.add_child(stage_box)
			_route_panels[_panel_key(route, stage)] = stage_box
		box.add_child(row)
	return panel


## 构建右侧节点说明、前置条件和激活按钮区域
func _build_details_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 356
	panel.add_theme_stylebox_override(
		"panel",
		MossTheme.panel_style(MossTheme.PANEL_BACKGROUND, MossTheme.BORDER_BRIGHT)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("协议详情", 13, MossTheme.ACCENT_CYAN))
	_detail_route = _label("请选择科技节点", 13, MossTheme.ACCENT_GOLD)
	_detail_name = _label("未选择", 24, MossTheme.TEXT_PRIMARY)
	_detail_description = _wrapped_label("", 16, MossTheme.TEXT_SECONDARY)
	_detail_effect = _wrapped_label("", 16, MossTheme.ACCENT_CYAN)
	_detail_risk = _wrapped_label("", 15, MossTheme.DANGER)
	_detail_requirements = _wrapped_label("", 14, MossTheme.TEXT_SECONDARY)
	box.add_child(_detail_route)
	box.add_child(_detail_name)
	box.add_child(_separator())
	box.add_child(_detail_description)
	box.add_child(_separator())
	box.add_child(_label("解锁效果", 13, MossTheme.ACCENT_CYAN))
	box.add_child(_detail_effect)
	box.add_child(_detail_risk)
	box.add_child(_separator())
	box.add_child(_label("前置条件", 13, MossTheme.ACCENT_CYAN))
	box.add_child(_detail_requirements)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_activate_button = Button.new()
	_activate_button.custom_minimum_size.y = 58
	_activate_button.pressed.connect(_on_activate_pressed)
	_style_button(_activate_button, true)
	box.add_child(_activate_button)
	return panel


## 构建底部状态图例和下一研究年份提示
func _build_footer() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 54
	panel.add_theme_stylebox_override(
		"panel",
		MossTheme.panel_style(Color(0.016, 0.038, 0.052, 0.94), MossTheme.BORDER)
	)
	var row := HBoxContainer.new()
	panel.add_child(row)
	row.add_child(
		_label(
			"■ 已激活    □ 可激活    ◇ 当前选择    × 风险协议",
			13,
			MossTheme.TEXT_SECONDARY
		)
	)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_research_label = _label("", 13, MossTheme.ACCENT_CYAN)
	row.add_child(_research_label)
	return panel

# ============================================================
# 状态刷新
# ============================================================

## 根据科技系统中的节点数据重新创建全部节点按钮
func _rebuild_nodes() -> void:
	for container in _route_panels.values():
		for child in container.get_children():
			child.queue_free()
	_node_buttons.clear()

	for node_data in _technology.get_all_nodes():
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 92)
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_node_selected.bind(node_data.node_id))
		_route_panels[_panel_key(node_data.route, node_data.stage)].add_child(button)
		_node_buttons[node_data.node_id] = button
	_refresh_nodes()


## 刷新形态、协议点、研究年份和各路线激活数量
func _refresh_status() -> void:
	if _technology == null:
		return
	_model_label.text = STAGE_NAMES[_technology.get_stage()]
	_points_label.text = str(_technology.get_available_points())
	var next_year := "研究计划已完成"
	for year in TechnologySystem.RESEARCH_YEARS:
		if year not in _technology.export_state()["granted_years"]:
			next_year = "下一协议点：%d" % year
			break
	_research_label.text = next_year
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


## 刷新所有节点按钮的文本、状态样式和选中状态
func _refresh_nodes() -> void:
	if _technology == null:
		return
	for node_id in _node_buttons:
		var button: Button = _node_buttons[node_id]
		var node_data := _technology.get_node_data(node_id)
		var state := _technology.get_activation_state(node_id)
		var state_text: String = STATE_NAMES.get(state, "不可用")
		button.text = "%s\n%s  /  %s" % [
			node_data.display_name,
			STAGE_NAMES[node_data.stage],
			state_text,
		]
		_style_node_button(button, state, node_id == _selected_node_id)


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
			# 前置状态用符号直接呈现，避免玩家在矩阵和详情间反复查找。
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
	for node_id in _node_buttons:
		var node_data := _technology.get_node_data(node_id)
		_node_buttons[node_id].modulate = (
			Color.WHITE if node_data.route == route else Color(0.48, 0.56, 0.60, 1.0)
		)


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

# ============================================================
# 控件辅助方法
# ============================================================

## 创建带标题的顶部指标，并返回数值标签
func _metric(parent: Container, title: String, width: int = 150) -> Label:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = width
	parent.add_child(box)
	box.add_child(_label(title, 11, MossTheme.TEXT_SECONDARY))
	var value := _label("--", 18, MossTheme.TEXT_PRIMARY)
	box.add_child(value)
	return value


## 创建统一字号和颜色的文本标签
func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## 创建支持自动换行的文本标签
func _wrapped_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## 创建使用主题边框色的水平分隔线
func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", MossTheme.BORDER)
	return separator


## 为普通操作按钮应用统一主题样式
## strong 为 true 时使用更醒目的悬停边框
func _style_button(button: Button, strong: bool = false) -> void:
	button.add_theme_color_override("font_color", MossTheme.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", MossTheme.TEXT_SECONDARY)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override(
		"normal",
		MossTheme.button_style(MossTheme.PANEL_BACKGROUND, MossTheme.BORDER)
	)
	button.add_theme_stylebox_override(
		"hover",
		MossTheme.button_style(
			MossTheme.PANEL_BACKGROUND_HOVER,
			MossTheme.ACCENT_CYAN,
			2 if strong else 1
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		MossTheme.button_style(Color(0.02, 0.04, 0.05, 1.0), MossTheme.ACCENT_GOLD)
	)
	button.add_theme_stylebox_override(
		"disabled",
		MossTheme.button_style(Color(0.018, 0.028, 0.035, 0.9), MossTheme.BORDER)
	)


## 根据节点状态和选中状态更新科技节点按钮样式
func _style_node_button(button: Button, state: String, selected: bool) -> void:
	var border := MossTheme.BORDER
	var background := Color(0.018, 0.045, 0.060, 0.96)
	var font_color := MossTheme.TEXT_SECONDARY
	if state == "active":
		border = MossTheme.ACCENT_CYAN
		font_color = MossTheme.TEXT_PRIMARY
	elif state == "available":
		border = MossTheme.BORDER_BRIGHT
		font_color = MossTheme.TEXT_PRIMARY
	if selected:
		border = MossTheme.ACCENT_GOLD
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override(
		"normal",
		MossTheme.button_style(background, border, 2 if selected else 1)
	)
	button.add_theme_stylebox_override(
		"hover",
		MossTheme.button_style(MossTheme.PANEL_BACKGROUND_HOVER, MossTheme.ACCENT_GOLD)
	)
	button.add_theme_stylebox_override(
		"pressed",
		MossTheme.button_style(background, MossTheme.ACCENT_GOLD, 2)
	)


## 生成路线和阶段对应的节点容器索引键
func _panel_key(route: TechNodeData.Route, stage: TechNodeData.Stage) -> String:
	return "%d:%d" % [route, stage]
