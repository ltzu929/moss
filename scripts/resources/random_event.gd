## 随机事件资源
## 继承 GameEvent 以复用现有弹窗、选项结算和轻量状态写入。
class_name RandomEvent
extends GameEvent

## 稳定 ID，用于冷却、测试和未来存档。
@export var event_id: String = ""
## 可出现的最早年份。
@export var earliest_year: int = 2044
## 可出现的最晚年份。
@export var latest_year: int = 2074
## 最低战役压力要求。
@export_range(0, 100, 1) var min_pressure_score: int = 0
## 允许触发的压力轴：civil、authority、engineering、energy、any。
@export var pressure_axes: Array[String] = ["any"]
## 同一随机事件再次出现的最少年数。
@export_range(0, 20, 1) var cooldown_years: int = 4
## 候选池中的相对权重。
@export_range(1, 100, 1) var weight: int = 10
## 必须指向现有 docs 文档，说明内容依据。
@export var source_reference: String = ""
## 说明该随机事件服务哪条事件链或玩法压力。
@export_multiline var design_role: String = ""
