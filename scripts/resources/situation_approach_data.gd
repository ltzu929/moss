## 局势应对方针配置。
class_name SituationApproachData
extends Resource

@export_group("基础信息")
@export var approach_id: String = ""
@export var display_name: String = "未命名方针"
@export_multiline var description: String = ""

@export_group("月度影响")
## 与局势自身月度增长叠加；负数表示缓解严重度。
@export var monthly_severity_delta: int = 0
@export var monthly_cpu_cost: int = 0
@export var monthly_energy_cost: int = 0

@export_group("结算影响")
@export var resolution_order_delta: int = 0
@export var resolution_hope_delta: int = 0
@export var resolution_authority_delta: int = 0
