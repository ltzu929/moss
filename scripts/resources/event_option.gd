class_name EventOption
extends Resource

@export_group("基础信息")
## 事件内稳定方案标识；不用于显示
@export var option_id: String = ""
@export var button_text: String = "选项描述"
@export var order_delta: int = 0
@export var hope_delta: int = 0
@export var authority_delta: int = 0
@export var energy_cost: int = 0
@export var event_state_key: String = ""
@export var event_state_value: String = ""
@export_group("核心决策历史")
@export var decision_tag_key: String = ""
@export var decision_tag_value: String = ""
@export var decision_record_title: String = ""
@export_multiline var decision_record_summary: String = ""
