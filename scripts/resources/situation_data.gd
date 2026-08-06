## 随机局势模板配置。
class_name SituationData
extends Resource

@export_group("基础信息")
@export var situation_id: String = ""
@export var title: String = "未命名局势"
@export_multiline var description: String = ""
## 稳定区域 ID 白名单；空数组表示所有区域
@export var eligible_regions: Array[String] = []
@export var region_descriptions: Dictionary = {}
@export_range(2044, 2075, 1) var min_year: int = 2044
@export_range(2044, 2075, 1) var max_year: int = 2074
@export_range(1, 1000, 1) var base_weight: int = 100
@export_enum("威胁", "机会") var situation_kind: int = 0

@export_group("生成条件")
## 键为历史事实，值为允许值数组；任意一项匹配即可生成。空字典表示无条件。
@export var required_any_facts: Dictionary = {}
@export var minimum_region_order: int = 0
@export var minimum_region_hope: int = 0

@export_group("风险权重")
## 权重以每 10 点缺口或余量为单位，由领域服务统一计算。
@export var low_order_weight: int = 0
@export var low_hope_weight: int = 0
@export var low_cpu_weight: int = 0
@export var low_energy_weight: int = 0
@export var high_order_weight: int = 0
@export var high_hope_weight: int = 0
@export var high_authority_weight: int = 0

@export_group("严重度")
@export_range(1, 99, 1) var initial_severity: int = 35
@export var monthly_growth: int = 3
@export var unfunded_growth_penalty: int = 3
@export var stage_names: Array[String] = ["预警", "恶化", "紧急"]
@export var progress_label: String = "严重度"

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
@export var situation_node: SituationNodeData
## 稳定指令 ID 到一次性严重度降低值。
@export var command_interventions: Dictionary = {}


func get_approach(approach_id: String) -> SituationApproachData:
	for approach in approaches:
		if approach != null and approach.approach_id == approach_id:
			return approach
	return null


func get_region_description(region_id: String) -> String:
	return str(region_descriptions.get(region_id, description))


func get_stage_name(stage: int) -> String:
	if stage >= 0 and stage < stage_names.size():
		return stage_names[stage]
	return "未知阶段"
