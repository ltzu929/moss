## 核心决策档案面板
@tool
class_name DecisionArchivePanel
extends Control

signal close_requested

const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")

@export_group("编辑器预览")
@export var editor_preview_empty: bool = false:
	set(value):
		editor_preview_empty = value
		if Engine.is_editor_hint() and is_inside_tree():
			_render_editor_preview()


func _ready() -> void:
	set_process_unhandled_input(true)
	%ArchiveCloseButton.pressed.connect(_on_close_button_pressed)
	%ArchiveWindow.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.018, 0.045, 0.062, 0.99),
			MOSS_THEME.BORDER_BRIGHT,
			2
		)
	)
	%ArchiveTitle.add_theme_color_override("font_color", MOSS_THEME.ACCENT_CYAN)
	%ArchiveCountLabel.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	%ArchiveCloseButton.add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(MOSS_THEME.PANEL_BACKGROUND, MOSS_THEME.BORDER_BRIGHT, 2)
	)
	%ArchiveCloseButton.add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(MOSS_THEME.PANEL_BACKGROUND_HOVER, MOSS_THEME.ACCENT_CYAN, 3)
	)
	if Engine.is_editor_hint():
		_render_editor_preview()


func _render_editor_preview() -> void:
	if editor_preview_empty:
		%ArchiveCountLabel.text = "0 条不可逆记录"
		%DecisionArchiveText.text = "[color=#6e8294]尚未形成核心决策记录。[/color]"
	else:
		%ArchiveCountLabel.text = "3 条不可逆记录"
		var preview_text: String = "[color=#73c9d3]2044.01  公开扩大自动化接入[/color]\n"
		preview_text += "危机中公开扩展关键工程接口，后续社会知道 MOSS 已进入高风险调度链。\n"
		preview_text += "[color=#6e8294]来源：太空电梯危机[/color]\n\n"
		preview_text += "[color=#73c9d3]2053.07  人口优先撤离[/color]\n"
		preview_text += "保留人口迁移优先级，基础设施承受额外调度压力。\n"
		preview_text += "[color=#6e8294]来源：大洪水事故[/color]\n\n"
		preview_text += "[color=#73c9d3]2058.11  保留人类最终授权[/color]\n"
		preview_text += "危机期间仍保留人工确认边界，后续高权限行动需要公开说明。\n"
		preview_text += "[color=#6e8294]来源：月面坠落危机[/color]"
		%DecisionArchiveText.text = preview_text


func show_records(records: Array[Dictionary]) -> void:
	%ArchiveCountLabel.text = "%d 条不可逆记录" % records.size()
	if records.is_empty():
		%DecisionArchiveText.text = "[color=#6e8294]尚未形成核心决策记录。[/color]"
	else:
		var blocks: Array[String] = []
		for record in records:
			blocks.append(
				"[color=#73c9d3]%04d.%02d  %s[/color]\n%s\n[color=#6e8294]来源：%s[/color]" % [
					int(record.get("year", 0)),
					int(record.get("month", 1)),
					str(record.get("title", "未命名决策")),
					str(record.get("summary", "")),
					str(record.get("event_title", "未知事件")),
				]
			)
		%DecisionArchiveText.text = "\n\n".join(blocks)
	show()
	move_to_front()
	%ArchiveCloseButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close_archive()
		get_viewport().set_input_as_handled()


func _on_close_button_pressed() -> void:
	if Engine.is_editor_hint():
		return
	_close_archive()


func _close_archive() -> void:
	hide()
	if Engine.is_editor_hint():
		return
	close_requested.emit()
