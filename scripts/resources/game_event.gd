class_name GameEvent
extends Resource

# ============================================================
# 导出变量
# ============================================================

@export_group("基础信息")
## 稳定事件标识，用于运行时身份、条件和跨资源引用；不用于显示
@export var event_id: String = ""
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
## 玩家可选择的事件方案
@export var options: Array[EventOption] = []
@export_group("分支触发")
## 仅当对应核心决策已写入时触发；空键表示固定事件
@export var required_decision_tag_key: String = ""
## 分支要求的核心决策值；空值表示只要求标签存在
@export var required_decision_tag_value: String = ""
