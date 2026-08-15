extends PanelContainer

# ============================================================
# 信号定义
# ============================================================

signal option_selected(index: int)

# ============================================================
# 常量
# ============================================================

const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const REGION_IDENTITY := preload("res://scripts/resources/region_identity.gd")
const FALLBACK_EVENT_IMAGE: Texture2D = preload(
	"res://assets/ui/event_fallback_flood.png"
)
const IMPACT_PREVIEW_DELAY: float = 1.0
const TOOLTIP_OFFSET: Vector2 = Vector2(16.0, 16.0)
const TOOLTIP_EDGE_MARGIN: float = 8.0

var _hover_generation: int = 0
var _hovered_button: Button


func _ready() -> void:
	$CenterContainer/MainPanel.add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style()
	)
	hide()


func _process(_delta: float) -> void:
	if visible and %ImpactTooltip.visible:
		_update_tooltip_position()


func popup_event(event: GameEvent, current_energy: int) -> void:
	_ensure_affordable_option(event, current_energy)
	var region_name := REGION_IDENTITY.display_name(event.event_region)
	%EventTitle.text = event.event_title
	%EventLevelLabel.text = event.event_level
	%EventMetaLabel.text = "影响区域：%s  /  记录时间：%04d.%02d  /  MOSS 自动归档" % [
		region_name,
		event.event_time,
		event.event_month,
	]
	%EventImage.texture = (
		event.event_image
		if event.event_image != null
		else FALLBACK_EVENT_IMAGE
	)
	%RichTextLabel.text = "[color=#73C9D3]影响板块：%s[/color]\n%s" % [
		region_name,
		event.event_description,
	]

	_hide_impact_tooltip()
	for child in %OptionList.get_children():
		child.free()

	for i in range(event.options.size()):
		var option: EventOption = event.options[i]
		add_custom_button(
			option,
			region_name,
			i if option.energy_cost <= current_energy else -1,
			i + 1
		)

	show()
	move_to_front()


## 强制事件必须始终可继续；内容资源仍应至少提供一个零能源方案。
## 如果资源或运行时调整破坏了该约束，只开放最低成本方案并耗尽剩余能源，
## 同时留下警告，避免玩家永久卡在模态弹窗中。
func _ensure_affordable_option(event: GameEvent, current_energy: int) -> void:
	if event.options.is_empty():
		return
	for option in event.options:
		if option.energy_cost <= current_energy:
			return

	var fallback: EventOption = event.options[0]
	for option in event.options:
		if option.energy_cost < fallback.energy_cost:
			fallback = option
	fallback.energy_cost = maxi(0, current_energy)
	fallback.button_text = "%s（紧急降级）" % fallback.button_text
	push_warning("事件没有可负担方案，已启用紧急降级：%s" % event.event_title)


func get_impact_preview_delay() -> float:
	return IMPACT_PREVIEW_DELAY


func format_option_impact(option: EventOption, region: String = "") -> String:
	var lines: Array[String] = []
	if region != "":
		lines.append("影响区域  %s" % region)
	lines.append("秩序      %s" % _format_signed_value(option.order_delta))
	lines.append("希望      %s" % _format_signed_value(option.hope_delta))
	lines.append("控制权    %s" % _format_signed_value(option.authority_delta))
	if option.energy_cost > 0:
		lines.append("能源      -%d" % option.energy_cost)
	return "\n".join(lines)


func add_custom_button(
	option: EventOption,
	region: String,
	index: int,
	display_number: int
) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = "%02d   %s" % [display_number, option.button_text]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color("#d7e5ec"))
	button.add_theme_color_override("font_pressed_color", MOSS_THEME.ACCENT_CYAN)
	button.add_theme_color_override("font_disabled_color", Color(0.31, 0.37, 0.41, 1.0))
	button.add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(
			Color(0.025, 0.060, 0.078, 0.92),
			MOSS_THEME.BORDER_BRIGHT,
			2
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(
			Color(0.045, 0.105, 0.128, 0.98),
			MOSS_THEME.ACCENT_CYAN,
			3
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		MOSS_THEME.button_style(
			Color(0.018, 0.045, 0.060, 1.0),
			MOSS_THEME.ACCENT_CYAN,
			3
		)
	)
	button.add_theme_stylebox_override(
		"disabled",
		MOSS_THEME.button_style(
			Color(0.025, 0.035, 0.043, 0.82),
			Color(0.14, 0.18, 0.20, 1.0),
			2
		)
	)

	%OptionList.add_child(button)
	button.mouse_entered.connect(
		_on_option_mouse_entered.bind(button, option, region, index != -1)
	)
	button.mouse_exited.connect(_on_option_mouse_exited.bind(button))

	if index == -1:
		button.disabled = true
	else:
		button.pressed.connect(_on_new_button_pressed.bind(index))


func _on_option_mouse_entered(
	button: Button,
	option: EventOption,
	region: String,
	is_available: bool
) -> void:
	_hover_generation += 1
	var generation := _hover_generation
	_hovered_button = button

	await get_tree().create_timer(IMPACT_PREVIEW_DELAY).timeout
	if generation != _hover_generation or _hovered_button != button:
		return

	var impact_text := format_option_impact(option, region)
	if not is_available:
		impact_text += "\n\n能源不足，方案不可执行"
	%ImpactTooltipContent.text = impact_text
	%ImpactTooltip.show()
	_update_tooltip_position()


func _on_option_mouse_exited(button: Button) -> void:
	if _hovered_button != button:
		return
	_hover_generation += 1
	_hovered_button = null
	_hide_impact_tooltip()


func _hide_impact_tooltip() -> void:
	if has_node("%ImpactTooltip"):
		%ImpactTooltip.hide()


func _update_tooltip_position() -> void:
	var tooltip_size: Vector2 = %ImpactTooltip.size
	if tooltip_size.x <= 0.0 or tooltip_size.y <= 0.0:
		tooltip_size = %ImpactTooltip.custom_minimum_size

	var mouse_position := get_global_mouse_position() - global_position
	var desired_position := mouse_position + TOOLTIP_OFFSET

	if desired_position.x + tooltip_size.x > size.x - TOOLTIP_EDGE_MARGIN:
		desired_position.x = mouse_position.x - tooltip_size.x - TOOLTIP_OFFSET.x
	if desired_position.y + tooltip_size.y > size.y - TOOLTIP_EDGE_MARGIN:
		desired_position.y = mouse_position.y - tooltip_size.y - TOOLTIP_OFFSET.y

	desired_position.x = clampf(
		desired_position.x,
		TOOLTIP_EDGE_MARGIN,
		maxf(TOOLTIP_EDGE_MARGIN, size.x - tooltip_size.x - TOOLTIP_EDGE_MARGIN)
	)
	desired_position.y = clampf(
		desired_position.y,
		TOOLTIP_EDGE_MARGIN,
		maxf(TOOLTIP_EDGE_MARGIN, size.y - tooltip_size.y - TOOLTIP_EDGE_MARGIN)
	)
	%ImpactTooltip.position = desired_position


func _format_signed_value(value: int) -> String:
	return "%+d" % value


func _on_new_button_pressed(index: int) -> void:
	_hover_generation += 1
	_hovered_button = null
	_hide_impact_tooltip()
	option_selected.emit(index)
	hide()
