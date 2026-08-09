## 单个随机局势的可变运行态。
## 不保存 Resource 模板以外的场景或 UI 引用，快照只导出稳定 ID 与基础类型。
class_name SituationInstanceState
extends RefCounted

var instance_id: String = ""
var data: SituationData = null
var region_id: String = ""
var severity: int = 0
var stage: int = 0
var approach_id: String = ""
var switch_lock_months: int = 0
var started_year: int = 0
var started_month: int = 0
var last_unfunded: bool = false
var node_pending: bool = false
var node_resolved: bool = false
var node_choice_id: String = ""
var node_choice_name: String = ""
var node_result_text: String = ""


## 导出可恢复的基础类型快照，不把 Resource 模板或内部对象暴露给调用方。
func to_runtime_snapshot() -> Dictionary:
	return {
		"instance_id": instance_id,
		"situation_id": data.situation_id if data != null else "",
		"region_id": region_id,
		"severity": severity,
		"stage": stage,
		"approach_id": approach_id,
		"switch_lock_months": switch_lock_months,
		"started_year": started_year,
		"started_month": started_month,
		"last_unfunded": last_unfunded,
		"node_pending": node_pending,
		"node_resolved": node_resolved,
		"node_choice_id": node_choice_id,
		"node_choice_name": node_choice_name,
		"node_result_text": node_result_text,
	}
