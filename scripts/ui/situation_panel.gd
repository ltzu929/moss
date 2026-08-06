## 非模态局势追踪与应对面板。
class_name SituationPanel
extends Control

signal approach_requested(instance_id: String, approach_id: String)
signal node_option_requested(instance_id: String, option_id: String)
signal focus_region_requested(region_id: String)

const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")

var _snapshots: Array[Dictionary] = []
var _selected_id: String = ""
var _current_cpu: int = 0
var _current_energy: int = 0


func _ready() -> void:
	%CloseButton.pressed.connect(hide)
	%FocusRegionButton.pressed.connect(_on_focus_region_pressed)
	%SituationWindow.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.018, 0.045, 0.062, 0.99),
			MOSS_THEME.BORDER_BRIGHT,
			2
		)
	)
	%SituationTitle.add_theme_color_override("font_color", MOSS_THEME.ACCENT_CYAN)
	%DetailTitle.add_theme_color_override("font_color", MOSS_THEME.ACCENT_GOLD)
	%SituationProgress.add_theme_stylebox_override(
		"background",
		MOSS_THEME.progress_background_style()
	)
	%SituationProgress.add_theme_stylebox_override(
		"fill",
		MOSS_THEME.progress_fill_style(MOSS_THEME.DANGER)
	)
	%SituationProgress.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	get_viewport().size_changed.connect(_update_window_bounds)
	_update_window_bounds()
	hide()


func calculate_window_rect(viewport_size: Vector2) -> Rect2:
	var margin := 20.0
	var width := minf(480.0, maxf(360.0, viewport_size.x - margin * 2.0))
	var top := 92.0 if viewport_size.y <= 720.0 else 112.0
	var height := minf(720.0, maxf(420.0, viewport_size.y - top - margin))
	return Rect2(viewport_size.x - width - margin, top, width, height)


func _update_window_bounds() -> void:
	var viewport_size := get_viewport_rect().size
	var window_rect := calculate_window_rect(viewport_size)
	%ApproachScroll.custom_minimum_size.y = 150.0 if viewport_size.y <= 720.0 else 210.0
	%SituationWindow.offset_left = window_rect.position.x - viewport_size.x
	%SituationWindow.offset_top = window_rect.position.y
	%SituationWindow.offset_right = -20.0
	%SituationWindow.offset_bottom = window_rect.end.y


func set_situations(
	snapshots: Array[Dictionary],
	current_cpu: int = 0,
	current_energy: int = 0
) -> void:
	_snapshots = snapshots.duplicate(true)
	_current_cpu = current_cpu
	_current_energy = current_energy
	%SituationCount.text = "%d / %d" % [_snapshots.size(), SituationSystem.MAX_ACTIVE]
	_rebuild_entries()
	if _snapshots.is_empty():
		_selected_id = ""
		%EmptyLabel.show()
		%DetailVBox.hide()
		return

	if not _has_snapshot(_selected_id):
		_selected_id = str(_snapshots[0].get("instance_id", ""))
	%EmptyLabel.hide()
	%DetailVBox.show()
	_render_selected()


func open_panel(focus_id: String = "") -> void:
	if focus_id != "" and _has_snapshot(focus_id):
		_selected_id = focus_id
	_render_selected()
	show()
	move_to_front()


func show_status(message: String, is_error: bool = false) -> void:
	%StatusLabel.text = message
	%StatusLabel.add_theme_color_override(
		"font_color",
		MOSS_THEME.DANGER if is_error else MOSS_THEME.ACCENT_CYAN
	)


func _rebuild_entries() -> void:
	for child in %EntryList.get_children():
		child.queue_free()

	for snapshot in _snapshots:
		var button := Button.new()
		var severity := int(snapshot.get("severity", 0))
		button.text = "%s｜%s  %s %d%%" % [
			str(snapshot.get("region_name", "未知地区")),
			str(snapshot.get("title", "未命名局势")),
			str(snapshot.get("stage_name", "预警")),
			severity,
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "查看局势详情"
		button.add_theme_stylebox_override(
			"normal",
			MOSS_THEME.button_style(MOSS_THEME.PANEL_BACKGROUND, MOSS_THEME.BORDER)
		)
		button.add_theme_stylebox_override(
			"hover",
			MOSS_THEME.button_style(
				MOSS_THEME.PANEL_BACKGROUND_HOVER,
				MOSS_THEME.ACCENT_CYAN,
				2
			)
		)
		button.pressed.connect(
			_on_entry_pressed.bind(str(snapshot.get("instance_id", "")))
		)
		%EntryList.add_child(button)


func _render_selected() -> void:
	var snapshot := _get_snapshot(_selected_id)
	if snapshot.is_empty():
		return

	%DetailTitle.text = str(snapshot.get("title", "未命名局势"))
	%DetailMeta.text = "%s  //  %s阶段  //  始于 %04d.%02d" % [
		str(snapshot.get("region_name", "未知地区")),
		str(snapshot.get("stage_name", "预警")),
		int(snapshot.get("started_year", 0)),
		int(snapshot.get("started_month", 1)),
	]
	%SituationProgress.value = int(snapshot.get("severity", 0))
	%SituationProgress.tooltip_text = "%s：%d / 100" % [
		str(snapshot.get("progress_label", "严重度")),
		int(snapshot.get("severity", 0)),
	]
	var monthly_delta := int(snapshot.get("expected_monthly_delta", 0))
	var trend_prefix := "+" if monthly_delta > 0 else ""
	var funding_required := bool(snapshot.get("funding_required", false))
	var funding_known := bool(snapshot.get("funding_known", false))
	var is_funded := bool(snapshot.get("is_funded", true))
	if funding_required and funding_known and not is_funded:
		%TrendLabel.text = "预计月度变化：%s%d（持续成本不足，方针不会生效）" % [
			trend_prefix,
			monthly_delta,
		]
	else:
		%TrendLabel.text = "预计月度变化：%s%d  （正数表示恶化）" % [
			trend_prefix,
			monthly_delta,
		]
	%DescriptionLabel.text = str(snapshot.get("description", ""))
	var history_echo := str(snapshot.get("history_echo", ""))
	%HistoryLabel.text = history_echo
	%HistoryLabel.visible = history_echo != ""
	var funding_text := ""
	if funding_required and funding_known:
		funding_text = "｜供给：充足" if is_funded else "｜供给：不足"
	elif funding_required and bool(snapshot.get("last_unfunded", false)):
		funding_text = "｜供给：上月断供"
	%CurrentApproachLabel.text = "当前方针：%s%s" % [
		str(snapshot.get("approach_name", "尚未选择")),
		funding_text,
	]
	var lock_months := int(snapshot.get("switch_lock_months", 0))
	%SwitchLockLabel.text = (
		"重配置锁定：%d 个月" % lock_months
		if lock_months > 0
		else "方针可调整；切换消耗 5 算力"
	)
	%StatusLabel.text = ""
	var node: Dictionary = snapshot.get("node", {})
	if bool(node.get("pending", false)):
		%ApproachScroll.hide()
		%NodePanel.show()
		_rebuild_node(snapshot, node)
	else:
		%NodePanel.hide()
		%ApproachScroll.show()
		_rebuild_approaches(snapshot)


func _rebuild_approaches(snapshot: Dictionary) -> void:
	for child in %ApproachList.get_children():
		child.queue_free()

	var current_id := str(snapshot.get("approach_id", ""))
	var lock_months := int(snapshot.get("switch_lock_months", 0))
	var approaches: Array = snapshot.get("approaches", [])
	for approach_variant in approaches:
		var approach: Dictionary = approach_variant
		var button := Button.new()
		var cpu_cost := int(approach.get("monthly_cpu_cost", 0))
		var energy_cost := int(approach.get("monthly_energy_cost", 0))
		var cost_parts: Array[String] = []
		if cpu_cost > 0:
			cost_parts.append("算力 %d/月" % cpu_cost)
		if energy_cost > 0:
			cost_parts.append("能源 %d/月" % energy_cost)
		if cost_parts.is_empty():
			cost_parts.append("无持续资源消耗")
		button.text = "%s｜%s｜严重度 %+d/月\n%s" % [
			str(approach.get("display_name", "未命名方针")),
			"，".join(cost_parts),
			int(approach.get("monthly_severity_delta", 0)),
			str(approach.get("description", "")),
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var approach_id := str(approach.get("approach_id", ""))
		button.disabled = approach_id == current_id or (current_id != "" and lock_months > 0)
		if approach_id == current_id:
			button.tooltip_text = "当前应对方针"
		elif lock_months > 0:
			button.tooltip_text = "重配置锁定剩余 %d 个月" % lock_months
		else:
			button.tooltip_text = "选择该应对方针"
		button.pressed.connect(
			_on_approach_pressed.bind(
				str(snapshot.get("instance_id", "")),
				approach_id
			)
		)
		%ApproachList.add_child(button)


func _rebuild_node(snapshot: Dictionary, node: Dictionary) -> void:
	%NodeTitle.text = str(node.get("title", "待处理节点"))
	%NodeDescription.text = str(node.get("description", ""))
	for child in %NodeOptionList.get_children():
		child.queue_free()

	var options: Array = node.get("options", [])
	for option_variant in options:
		var option: Dictionary = option_variant
		var button := Button.new()
		var cpu_cost := int(option.get("cpu_cost", 0))
		var energy_cost := int(option.get("energy_cost", 0))
		var costs: Array[String] = []
		if cpu_cost > 0:
			costs.append("算力 %d" % cpu_cost)
		if energy_cost > 0:
			costs.append("能源 %d" % energy_cost)
		if costs.is_empty():
			costs.append("无立即资源消耗")
		button.text = "%s｜%s｜局势 %+d\n%s" % [
			str(option.get("display_name", "未命名方案")),
			"，".join(costs),
			int(option.get("severity_delta", 0)),
			str(option.get("description", "")),
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = _current_cpu < cpu_cost or _current_energy < energy_cost
		button.tooltip_text = (
			"资源不足，无法执行该方案"
			if button.disabled
			else str(option.get("result_text", "执行该处置方案"))
		)
		button.pressed.connect(
			_on_node_option_pressed.bind(
				str(snapshot.get("instance_id", "")),
				str(option.get("option_id", ""))
			)
		)
		%NodeOptionList.add_child(button)


func _on_entry_pressed(instance_id: String) -> void:
	_selected_id = instance_id
	_render_selected()


func _on_approach_pressed(instance_id: String, approach_id: String) -> void:
	approach_requested.emit(instance_id, approach_id)


func _on_node_option_pressed(instance_id: String, option_id: String) -> void:
	node_option_requested.emit(instance_id, option_id)


func _on_focus_region_pressed() -> void:
	var snapshot := _get_snapshot(_selected_id)
	if not snapshot.is_empty():
		focus_region_requested.emit(str(snapshot.get("region_id", "")))


func _has_snapshot(instance_id: String) -> bool:
	return not _get_snapshot(instance_id).is_empty()


func _get_snapshot(instance_id: String) -> Dictionary:
	for snapshot in _snapshots:
		if snapshot.get("instance_id", "") == instance_id:
			return snapshot
	return {}
