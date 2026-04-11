extends Panel

# --- 插槽：这里专门用来插 .tres 数据卡 ---
# 这里的 @export var data_card 就像一个插槽
# 你可以在编辑器里把具体的 SectorData 资源文件（比如 sector_asia.tres）拖进去
@export var data_card: SectorData

# --- 获取界面节点 ---
# @onready 确保节点在 _ready() 调用前已经准备好
@onready var title_label = $TitleLabel      # 显示区域名称的标签
@onready var order_bar = %OrderBar          # 显示秩序值的进度条
@onready var hope_bar = %HopeBar            # 显示希望值的进度条
@onready var authority_bar = %AuthorityBar  # 显示控制权的进度条

func _ready():
	# 如果插槽里有卡，就读取数据
	if data_card != null:
		update_display()

# 刷新显示内容的函数
# 从 data_card 读取数据并关联到 UI 控件上
func update_display():
	# 1. 设置标题文字
	title_label.text = data_card.region_name
	
	# 2. 更新三个核心数值的进度条显示
	order_bar.value = data_card.order
	hope_bar.value = data_card.hope
	authority_bar.value = data_card.authority
