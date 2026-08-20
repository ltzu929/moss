## 算力分配选择弹窗
## 让玩家选择提升秩序、希望，或在科技解锁后执行综合调度
class_name AllocatePopup
extends PanelContainer

# ============================================================
# 信号定义
# ============================================================

## 玩家选择后发出
## order 表示秩序，hope 表示希望，combined 表示综合调度，空字符串表示取消
signal choice_selected(choice: String)

# ============================================================
# 常量定义
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")

# ============================================================
# 状态变量
# ============================================================

## 当前指令数据（用于实时更新）
var current_cmd: CommandData = null

# ============================================================
# 生命周期函数
# ============================================================

## 初始化时应用主题并隐藏弹窗
func _ready() -> void:
	_apply_theme()
	hide()

# ============================================================
# 弹窗显示
# ============================================================

## 显示算力分配选择弹窗
## 参数: cmd - 指令数据
##       region_name - 目标板块名称
func popup_allocate(cmd: CommandData, region_name: String) -> void:
	current_cmd = cmd
	update_display(region_name)
	show()

## 更新弹窗显示内容（实时更新板块名称）
## 参数: region_name - 当前选中的板块名称，"未选择板块"时禁用按钮
func update_display(region_name: String) -> void:
	if current_cmd == null:
		return

	%AllocateTitle.text = "算力分配 - " + region_name
	%AllocateDesc.text = current_cmd.description + "\n请选择要提升的属性："

	%OrderButton.text = "提升秩序 (+%d)" % current_cmd.order_delta
	%HopeButton.text = "提升希望 (+%d)" % current_cmd.hope_delta
	%CombinedButton.visible = current_cmd.get_meta("combined_enabled", false)
	%CombinedButton.text = "综合调度（秩序 +10 / 希望 +10 / 控制权 +2）"
	%CancelButton.text = "取消"

	# 如果没有选中板块，禁用选择按钮（取消按钮始终可用）
	var has_selection: bool = (region_name != "未选择板块")
	%OrderButton.disabled = not has_selection
	%HopeButton.disabled = not has_selection
	%CombinedButton.disabled = not has_selection
	%CancelButton.disabled = false  # 取消按钮始终可用

# ============================================================
# 按钮回调
# ============================================================

## 为弹窗面板与四个按钮应用 MOSS 终端主题，避免落入 Godot 默认皮肤。
func _apply_theme() -> void:
	add_theme_stylebox_override(
		"panel",
		MOSS_THEME.panel_style(
			Color(0.018, 0.045, 0.062, 0.99),
			MOSS_THEME.BORDER_BRIGHT,
			2
		)
	)
	%AllocateTitle.add_theme_color_override("font_color", MOSS_THEME.ACCENT_CYAN)
	%AllocateTitle.add_theme_font_size_override("font_size", 18)
	%AllocateDesc.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	%AllocateDesc.add_theme_font_size_override("font_size", 14)
	_style_action_button(%OrderButton)
	_style_action_button(%HopeButton)
	_style_action_button(%CombinedButton)
	_style_action_button(%CancelButton)


## 统一分配弹窗按钮的 normal/hover/pressed/disabled 样式。
func _style_action_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(240.0, 36.0)
	button.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	button.add_theme_color_override(
		"font_disabled_color",
		Color(0.45, 0.52, 0.58, 1.0)
	)
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
	button.add_theme_stylebox_override(
		"pressed",
		MOSS_THEME.button_style(
			Color(0.016, 0.038, 0.050, 1.0),
			MOSS_THEME.ACCENT_CYAN,
			2
		)
	)
	button.add_theme_stylebox_override(
		"disabled",
		MOSS_THEME.button_style(
			Color(0.018, 0.028, 0.035, 0.82),
			MOSS_THEME.BORDER
		)
	)

## 选择提升秩序并关闭弹窗
func _on_order_button_pressed() -> void:
	choice_selected.emit("order")
	hide()

## 选择提升希望并关闭弹窗
func _on_hope_button_pressed() -> void:
	choice_selected.emit("hope")
	hide()


## 选择综合调度并关闭弹窗
func _on_combined_button_pressed() -> void:
	choice_selected.emit("combined")
	hide()


## 取消本次算力分配并关闭弹窗
func _on_cancel_button_pressed() -> void:
	choice_selected.emit("")
	hide()
