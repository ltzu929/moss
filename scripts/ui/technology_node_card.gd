## 科技节点卡片
## 在编辑器中引用固定科技资源，运行时只刷新状态和选中样式
@tool
class_name TechnologyNodeCard
extends Button

# ============================================================
# 信号定义
# ============================================================

## 玩家点击卡片时发出稳定节点 ID
signal node_selected(node_id: String)

# ============================================================
# 导出变量
# ============================================================

## 当前卡片在静态科技场景中绑定的节点资源
@export var node_data: TechNodeData:
	set(value):
		node_data = value
		_refresh_text()

# ============================================================
# 常量
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")

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

## 当前激活状态
var _state: String = "stage_locked"
## 当前卡片是否被选中
var _selected: bool = false

# ============================================================
# 生命周期函数
# ============================================================

## 初始化编辑器预览和运行时样式
func _ready() -> void:
	_refresh_text()
	_apply_style()

# ============================================================
# 公共方法
# ============================================================

## 刷新节点状态、文本和选中样式
func refresh_state(state: String, selected: bool) -> void:
	_state = state
	_selected = selected
	_refresh_text()
	_apply_style()

# ============================================================
# 交互回调
# ============================================================

## 将按钮点击转换为带稳定节点 ID 的业务信号
func _on_pressed() -> void:
	if node_data != null and node_data.node_id != "":
		node_selected.emit(node_data.node_id)

# ============================================================
# 显示辅助方法
# ============================================================

## 根据绑定资源和当前状态刷新卡片文本
func _refresh_text() -> void:
	if not is_inside_tree():
		return
	if node_data == null:
		text = "未绑定科技节点"
		return
	var state_text: String = STATE_NAMES.get(_state, "不可用")
	text = "%s\n%s  /  %s" % [
		node_data.display_name,
		STAGE_NAMES[node_data.stage],
		state_text,
	]


## 根据节点状态和选中状态更新卡片样式
func _apply_style() -> void:
	var border := MOSS_THEME.BORDER
	var background := Color(0.018, 0.045, 0.060, 0.96)
	var font_color := MOSS_THEME.TEXT_SECONDARY
	if _state == "active":
		border = MOSS_THEME.ACCENT_CYAN
		font_color = MOSS_THEME.TEXT_PRIMARY
	elif _state == "available":
		border = MOSS_THEME.BORDER_BRIGHT
		font_color = MOSS_THEME.TEXT_PRIMARY
	if _selected:
		border = MOSS_THEME.ACCENT_GOLD
	add_theme_color_override("font_color", font_color)
	add_theme_font_size_override("font_size", 15)
	add_theme_stylebox_override(
		"normal",
		MOSS_THEME.button_style(background, border, 2 if _selected else 1)
	)
	add_theme_stylebox_override(
		"hover",
		MOSS_THEME.button_style(
			MOSS_THEME.PANEL_BACKGROUND_HOVER,
			MOSS_THEME.ACCENT_GOLD
		)
	)
	add_theme_stylebox_override(
		"pressed",
		MOSS_THEME.button_style(background, MOSS_THEME.ACCENT_GOLD, 2)
	)
