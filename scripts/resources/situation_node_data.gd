## 单个局势实例最多触发一次的轻量处置节点。
class_name SituationNodeData
extends Resource

@export_group("基础信息")
@export var node_id: String = ""
@export var title: String = "待处理节点"
@export_multiline var description: String = ""
## 0 表示局势出现时触发，1 表示首次进入恶化阶段，2 表示首次进入紧急阶段。
@export_range(0, 2, 1) var trigger_stage: int = 1
@export var options: Array[SituationNodeOptionData] = []


func get_option(option_id: String) -> SituationNodeOptionData:
	for option in options:
		if option != null and option.option_id == option_id:
			return option
	return null
