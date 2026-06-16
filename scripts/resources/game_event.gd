class_name GameEvent
extends Resource

# ============================================================
# 导出变量
# ============================================================

## 事件标题，显示在报告顶部
@export var event_title: String = "事件标题"
## 触发年份
@export var event_time: int = 0
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
