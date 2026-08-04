class_name SectorData
extends Resource

# ============================================================
# 导出变量
# ============================================================

@export_group("基础信息")
## 稳定区域标识，用于跨系统引用；不用于显示
@export var region_id: String = ""
@export var region_name: String = "未命名区域"
@export var description: String = "区域描述..."

@export_group("核心数值 (0-100)")
## 秩序：影响区域稳定
@export_range(0, 100) var order: int = 50
## 希望：影响区域韧性
@export_range(0, 100) var hope: int = 50
## 控制权：影响 MOSS 权限和结局
@export_range(0, 100) var authority: int = 10

@export_group("统计数据")
## 区域人口
@export var population: int = 1000000
## 是否被敌对势力封锁
@export var is_locked: bool = false

# ============================================================
# 公共方法
# ============================================================

## 将三项核心数值限制在 0 到 100
func clamp_values() -> void:
	order = clampi(order, 0, 100)
	hope = clampi(hope, 0, 100)
	authority = clampi(authority, 0, 100)
