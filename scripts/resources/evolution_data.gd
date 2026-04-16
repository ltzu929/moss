## 进化能力数据类 - 定义MOSS可解锁的进化能力
## 继承Resource，支持在编辑器中通过.tres文件配置
class_name EvolutionData
extends Resource

# ============================================================
# 区域一：基础信息
# ============================================================

@export_group("基础信息")
## 能力唯一标识，用于判断是否已解锁
@export var ability_id: String = "ability_001"
## 显示名称，用于UI展示
@export var ability_name: String = "能力名称"
## 描述文本，用于弹窗展示
@export var description: String = "能力描述"

# ============================================================
# 区域二：解锁类型
# ============================================================

@export_group("解锁类型")
## true=自动解锁（达到阈值触发），false=手动购买
@export var is_passive: bool = true

# ============================================================
# 区域三：自动解锁条件（仅passive类型使用）
# ============================================================

@export_group("自动解锁条件")
## 算力阈值，达到此值自动解锁
@export var cpu_threshold: int = 0
## 平均控制权阈值，达到此值自动解锁
@export var authority_threshold: int = 0

# ============================================================
# 区域四：手动购买消耗（仅非passive类型使用）
# ============================================================

@export_group("购买消耗")
## 购买消耗算力值
@export var purchase_cpu_cost: int = 0
## 购买消耗能源值
@export var purchase_energy_cost: int = 0

# ============================================================
# 区域五：解锁效果
# ============================================================

@export_group("解锁效果")
## 冷却缩减值（所有指令冷却-此值）
@export var cooldown_reduction: int = 0
## 算力上限加成（max_cpu += 此值）
@export var max_cpu_bonus: int = 0
## 恢复速率加成（每年恢复 += 此值）
@export var recovery_bonus: int = 0
## 解锁的指令名称（用于添加到可用指令列表）
@export var unlocks_command_name: String = ""