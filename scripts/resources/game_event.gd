extends Resource

# 自定义资源类：游戏事件
# 使用 class_name 注册后，可以在编辑器中右键新建此资源 (Create New -> Resource -> GameEvent)
class_name GameEvent

# --- 事件基本属性 ---
# @export 这里的变量会显示在编辑器的检查器(Inspector)面板中

# 事件标题：显示在弹窗顶部
@export var event_title: String = "事件标题"

# 触发年份：当游戏内年份达到此数值时触发事件 (例如 2044)
@export var event_time:  int    = 0
@export var event_region: String = "事件地区"
@export var event_description: String = "事件描述"

## 事件专属图片；未配置时弹窗使用项目占位图
@export var event_image: Texture2D

## 事件等级文本，仅影响报告显示，不改变玩法结算
@export_enum("一般事件", "重大事件", "高危事件") var event_level: String = "重大事件"

@export var options:Array[EventOption]
