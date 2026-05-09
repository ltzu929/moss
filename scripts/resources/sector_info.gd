class_name SectorInfo
extends Panel

# ============================================================
# 导出变量
# ============================================================

## 数据卡插槽，可在编辑器中配置具体板块数据
@export var data_card: SectorData

# ============================================================
# 信号定义
# ============================================================

## 板块被点击时发出，用于选中状态
signal sector_clicked(sector: SectorInfo)

# ============================================================
# 常量定义
# ============================================================

## 选中时的边框颜色（橙色，醒目且不与进度条冲突）
const SELECTED_BORDER_COLOR: Color = Color(1.0, 0.6, 0.0, 1.0)  # #FF9900 橙色

## 默认边框颜色
const DEFAULT_BORDER_COLOR: Color = Color(0.3, 0.3, 0.3, 1.0)

## 边框宽度
const BORDER_WIDTH: int = 4

# ============================================================
# 状态变量
# ============================================================

## 是否被选中
var is_selected: bool = false

## 默认样式（缓存）
var default_style: StyleBoxFlat

## 选中样式（缓存）
var selected_style: StyleBoxFlat

# ============================================================
# 节点引用
# ============================================================

@onready var title_label: Label = $TitleLabel
@onready var order_bar: ProgressBar = %OrderBar
@onready var hope_bar: ProgressBar = %HopeBar
@onready var authority_bar: ProgressBar = %AuthorityBar

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	# 创建样式
	_create_styles()

	# 如果插槽里有卡，就读取数据
	if data_card != null:
		update_display()

	# 设置默认边框
	add_theme_stylebox_override("panel", default_style)

# ============================================================
# 样式创建
# ============================================================

## 创建默认和选中两种边框样式
func _create_styles() -> void:
	# 默认样式
	default_style = StyleBoxFlat.new()
	default_style.border_color = DEFAULT_BORDER_COLOR
	default_style.set_border_width_all(BORDER_WIDTH)
	default_style.bg_color = Color(0.15, 0.15, 0.2, 0.9)  # 半透明深色背景

	# 选中样式
	selected_style = StyleBoxFlat.new()
	selected_style.border_color = SELECTED_BORDER_COLOR
	selected_style.set_border_width_all(BORDER_WIDTH)
	selected_style.bg_color = Color(0.2, 0.18, 0.15, 0.95)  # 略亮的背景

# ============================================================
# 显示更新
# ============================================================

## 刷新显示内容，从 data_card 读取数据并更新UI
func update_display() -> void:
	# 设置标题文字
	title_label.text = data_card.region_name

	# 更新三个核心数值的进度条显示
	order_bar.value = data_card.order
	hope_bar.value = data_card.hope
	authority_bar.value = data_card.authority

# ============================================================
# 选中状态管理
# ============================================================

## 设置选中状态
## 参数: value - true为选中，false为取消选中
func set_selected(value: bool) -> void:
	is_selected = value
	if is_selected:
		add_theme_stylebox_override("panel", selected_style)
	else:
		add_theme_stylebox_override("panel", default_style)

# ============================================================
# 点击响应
# ============================================================

## 面板被点击时发出信号
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			sector_clicked.emit(self)
			# 阻止事件继续传播
			accept_event()