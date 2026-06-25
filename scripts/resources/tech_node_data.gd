## 科技节点资源数据
## 描述节点所属路线、阶段、前置关系和激活后提供的标签
class_name TechNodeData
extends Resource

# ============================================================
# 枚举
# ============================================================

## 科技节点所属的演化路线
enum Route {
	MANAGED,
	CORE,
	HUMAN,
}

## 科技节点所属的系统形态阶段
enum Stage {
	C550,
	W550,
	MOSS,
}

# ============================================================
# 导出变量
# ============================================================

@export_group("基础信息")
## 节点稳定标识，用于前置关系、状态保存和逻辑查询
@export var node_id: String = ""
## 节点在科技界面中的显示名称
@export var display_name: String = "节点名称"
## 节点背景与设计意图说明
@export_multiline var description: String = "节点描述"
## 节点激活后产生的正向效果
@export_multiline var effect_text: String = "节点效果"
## 节点激活后需要提示的代价或风险
@export_multiline var risk_text: String = " "

@export_group("结构")
## 节点所属路线
@export var route: Route = Route.MANAGED
## 节点所属阶段
@export var stage: Stage = Stage.C550
## 激活当前节点前必须激活的节点 ID
@export var prerequisite_ids: Array[String] = []
## 非空时表示同组节点只能激活一个，用于路线终端互斥
@export var exclusive_group: String = ""
## 节点向运行时系统提供的能力标签
@export var tags: Array[String] = []
## 激活节点消耗的协议点
@export_range(1, 1) var point_cost: int = 1
