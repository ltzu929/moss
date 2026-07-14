## 核心决策档案面板
class_name DecisionArchivePanel
extends Control

signal close_requested

const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")


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
	hide()


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
	_close_archive()


func _close_archive() -> void:
	hide()
	close_requested.emit()
