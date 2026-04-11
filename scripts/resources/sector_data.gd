extends Resource
class_name SectorData

# --- 核心属性 ---
# @export 的意思是：让这些变量显示在编辑器面板里，方便你填数字

@export_group("基础信息")
@export var region_name: String = "未命名区域"
@export var description: String = "区域描述..."

@export_group("核心数值 (0-100)")
@export_range(0, 100) var order: int = 50      # 秩序：影响产能
@export_range(0, 100) var hope: int = 50       # 希望：影响抗性
@export_range(0, 100) var authority: int = 10  # 控制权：获胜关键

@export_group("统计数据")
@export var population: int = 1000000          # 人口
@export var is_locked: bool = false            # 是否被敌对势力封锁

# --- 辅助函数 ---
# 用来限制数值不要超过 0 到 100
func clamp_values():
	order = clampi(order, 0, 100)
	hope = clampi(hope, 0, 100)
	authority = clampi(authority, 0, 100)
