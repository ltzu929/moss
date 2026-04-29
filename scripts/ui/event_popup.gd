extends PanelContainer

signal option_selected(index: int)

func _ready() -> void:
	hide()

func popup_event(event: GameEvent, current_energy: int) -> void:
	%EventTitle.text = event.event_title + " · " + event.event_region
	%RichTextLabel.text = "[color=#8BDDD9]影响板块：%s[/color]\n\n%s" % [
		event.event_region,
		event.event_description
	]

	for child in %OptionList.get_children():
		child.queue_free()

	for i in range(event.options.size()):
		var opt: EventOption = event.options[i]
		if opt.energy_cost <= current_energy:
			add_custom_button(opt, event.event_region, i)
		else:
			add_custom_button(opt, event.event_region, -1)

	show()

func add_custom_button(opt: EventOption, region: String, index: int) -> void:
	var new_button := Button.new()
	new_button.text = opt.button_text
	new_button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var tooltip_parts: Array[String] = []
	tooltip_parts.append("【影响板块：%s】" % region)

	if opt.order_delta != 0:
		var order_prefix := "+" if opt.order_delta > 0 else ""
		tooltip_parts.append("秩序 %s%d" % [order_prefix, opt.order_delta])

	if opt.hope_delta != 0:
		var hope_prefix := "+" if opt.hope_delta > 0 else ""
		tooltip_parts.append("希望 %s%d" % [hope_prefix, opt.hope_delta])

	if opt.authority_delta != 0:
		var authority_prefix := "+" if opt.authority_delta > 0 else ""
		tooltip_parts.append("控制权 %s%d" % [authority_prefix, opt.authority_delta])

	if opt.energy_cost > 0:
		tooltip_parts.append("消耗能源 %d" % opt.energy_cost)

	new_button.tooltip_text = "\n".join(tooltip_parts)

	if index == -1:
		new_button.disabled = true
		new_button.tooltip_text = "能源不足（需要 %d）" % opt.energy_cost

	%OptionList.add_child(new_button)
	new_button.pressed.connect(_on_new_button_pressed.bind(index))

func _on_new_button_pressed(index: int) -> void:
	option_selected.emit(index)
	hide()
