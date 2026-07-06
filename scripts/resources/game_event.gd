class_name GameEvent
extends Resource

# ============================================================
# 导出变量
# ============================================================

## 事件标题，显示在报告顶部
@export var event_title: String = "事件标题"
## 触发年份
@export var event_time: int = 0
## 触发月份
@export_range(1, 12, 1) var event_month: int = 1
## 事件影响区域
@export var event_region: String = "事件地区"
## 事件正文
@export var event_description: String = "事件描述"
## 事件专属图片；未配置时弹窗使用项目占位图
@export var event_image: Texture2D
## 事件等级文本，仅影响报告显示，不改变玩法结算
@export_enum("一般事件", "重大事件", "高危事件") var event_level: String = "重大事件"
## 需要匹配的核心历史标签键；留空表示不限制
@export var required_decision_tag_key: String = ""
## 需要匹配的核心历史标签值；留空时只要求标签存在
@export var required_decision_tag_value: String = ""
## 需要匹配的轻量事件状态键；留空表示不限制
@export var required_event_state_key: String = ""
## 需要匹配的轻量事件状态值；留空时只要求状态存在
@export var required_event_state_value: String = ""
## 事件所属因果链，仅用于档案、文档和测试解释
@export var causal_thread: String = ""
## 分支触发原因，仅用于档案、文档和测试解释
@export_multiline var branch_reason: String = ""
## 玩家可选择的事件方案
@export var options: Array[EventOption] = []
