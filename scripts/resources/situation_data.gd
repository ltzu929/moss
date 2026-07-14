## 随机局势模板配置。
class_name SituationData
extends Resource

@export_group("基础信息")
@export var situation_id: String = ""
@export var title: String = "未命名局势"
@export_multiline var description: String = ""
@export var eligible_regions: Array[String] = []
@export_range(1, 1000, 1) var base_weight: int = 100

@export_group("严重度")
@export_range(1, 99, 1) var initial_severity: int = 35
@export var monthly_growth: int = 3
@export var unfunded_growth_penalty: int = 3

@export_group("安全结算")
@export var success_order_delta: int = 2
@export var success_hope_delta: int = 2
@export var success_authority_delta: int = 0

@export_group("失控结算")
@export var failure_order_delta: int = -8
@export var failure_hope_delta: int = -8
@export var failure_authority_delta: int = 0

@export_group("干预")
@export var approaches: Array[SituationApproachData] = []
## 稳定指令 ID 到一次性严重度降低值。
@export var command_interventions: Dictionary = {}


func get_approach(approach_id: String) -> SituationApproachData:
	for approach in approaches:
		if approach != null and approach.approach_id == approach_id:
			return approach
	return null
