class_name SectorInfo
extends Panel

# ============================================================
# 区域一：导出变量
# ============================================================

## 数据卡插槽，可在编辑器中配置具体板块数据
@export var data_card: SectorData

# ============================================================
# 区域二：信号定义
# ============================================================

## 板块被点击时发出，用于选中状态
signal sector_clicked(sector: SectorInfo)

# ============================================================
# 区域三：常量定义
# ============================================================

## 选中时的边框颜色
const SELECTED_COLOR: Color = Color(0.0, 1.0, 0.533, 1.0)  # #00FF88

## 默认边框颜色
const DEFAULT_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)

# ============================================================
# 区域四：状态变量
# ============================================================

## 是否被选中
var is_selected: bool = false

# ============================================================
# 区域五：节点引用
# ============================================================

@onready var title_label: Label = $TitleLabel
@onready var order_bar: ProgressBar = %OrderBar
@onready var hope_bar: ProgressBar = %HopeBar
@onready var authority_bar: ProgressBar = %AuthorityBar

# ============================================================
# 区域六：生命周期函数
# ============================================================

func _ready() -> void:
	# 如果插槽里有卡，就读取数据
	if data_card != null:
		update_display()
	# 设置默认边框颜色
	self.modulate = DEFAULT_COLOR

# ============================================================
# 区域七：显示更新
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
# 区域八：选中状态管理
# ============================================================

## 设置选中状态
## 参数: value - true为选中，false为取消选中
func set_selected(value: bool) -> void:
	is_selected = value
	if is_selected:
		self.modulate = SELECTED_COLOR
	else:
		self.modulate = DEFAULT_COLOR

# ============================================================
# 区域九：点击响应
# ============================================================

## 面板被点击时发出信号
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			sector_clicked.emit(self)
			# 阻止事件继续传播
			accept_event()