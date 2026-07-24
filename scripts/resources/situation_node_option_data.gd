## 局势节点中的确定性处置方案。
class_name SituationNodeOptionData
extends Resource

@export_group("基础信息")
@export var option_id: String = ""
@export var display_name: String = "未命名方案"
@export_multiline var description: String = ""
@export_multiline var result_text: String = ""

@export_group("立即成本")
@export var cpu_cost: int = 0
@export var energy_cost: int = 0

@export_group("立即影响")
## 负数表示缓解局势，正数表示推动局势接近失控边界。
@export var severity_delta: int = 0
@export var order_delta: int = 0
@export var hope_delta: int = 0
@export var authority_delta: int = 0
