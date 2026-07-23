class_name SectorInfo
extends Panel

# ============================================================
# 信号定义
# ============================================================

## 板块被点击时发出，用于选中状态
signal sector_clicked(sector: SectorInfo)

# ============================================================
# 导出变量
# ============================================================

## 数据卡插槽，可在编辑器中配置具体板块数据
@export var data_card: SectorData

# ============================================================
# 常量定义
# ============================================================

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")

## 选中时使用低饱和金色，避免高亮面积过大
const SELECTED_BORDER_COLOR: Color = Color("#bda66a")

## 默认边框颜色
const DEFAULT_BORDER_COLOR: Color = Color("#263b4a")

## 边框宽度
const BORDER_WIDTH: int = 1

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
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_descendants_mouse_filter_ignore(self)

	# 创建样式
	_create_styles()
	_setup_text_and_bars()

	# 如果插槽里有卡，就读取数据
	if data_card != null:
		# 外部 .tres 是只读模板；每个场景实例持有独立运行态副本。
		data_card = data_card.duplicate(true) as SectorData
		update_display()

	# 设置默认边框
	add_theme_stylebox_override("panel", default_style)


## 子控件只负责显示，鼠标事件统一交给整张卡片处理
func _set_descendants_mouse_filter_ignore(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_descendants_mouse_filter_ignore(child)


# ============================================================
# 样式创建
# ============================================================

## 创建默认和选中两种边框样式
func _create_styles() -> void:
	# 默认样式
	default_style = StyleBoxFlat.new()
	default_style.border_color = DEFAULT_BORDER_COLOR
	default_style.set_border_width_all(BORDER_WIDTH)
	default_style.bg_color = Color(0.026, 0.052, 0.072, 0.94)

	# 选中样式
	selected_style = StyleBoxFlat.new()
	selected_style.border_color = SELECTED_BORDER_COLOR
	selected_style.set_border_width_all(2)
	selected_style.bg_color = Color(0.105, 0.091, 0.052, 0.96)


## 统一卡片文字与三项状态条的低饱和终端样式
func _setup_text_and_bars() -> void:
	title_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
	title_label.add_theme_font_size_override("font_size", 14)

	var bars: Array[ProgressBar] = [order_bar, hope_bar, authority_bar]
	var colors: Array[Color] = [
		MOSS_THEME.ORDER,
		MOSS_THEME.HOPE,
		MOSS_THEME.AUTHORITY,
	]
	for i in range(bars.size()):
		var bar := bars[i]
		bar.add_theme_stylebox_override(
			"background",
			MOSS_THEME.progress_background_style()
		)
		bar.add_theme_stylebox_override(
			"fill",
			MOSS_THEME.progress_fill_style(colors[i])
		)
		bar.add_theme_color_override("font_color", MOSS_THEME.TEXT_PRIMARY)
		bar.add_theme_font_size_override("font_size", 10)

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
