## 科技系统
## 负责加载科技图、发放协议点、校验激活条件并维护当前系统形态
class_name TechnologySystem
extends Node

# ============================================================
# 信号定义
# ============================================================

## 可用协议点发生变化时发出
signal points_changed(available_points: int)
## 科技节点成功激活后发出
signal node_activated(node_id: String)
## 系统形态阶段发生变化时发出
signal stage_changed(stage: TechNodeData.Stage)

# ============================================================
# 常量
# ============================================================

## 科技节点资源目录
const TECHNOLOGY_PATH: String = "res://data/technology/"
## 新游戏初始协议点
const INITIAL_POINTS: int = 1
## 每局固定发放协议点的研究年份
const RESEARCH_YEARS: Array[int] = [
	2048,
	2052,
	2056,
	2060,
	2064,
	2068,
	2072,
]

# ============================================================
# 状态变量
# ============================================================

## 按节点 ID 索引的全部科技节点
var _nodes_by_id: Dictionary = {}
## 已激活节点 ID 列表
var _active_node_ids: Array[String] = []
## 已发放协议点的年份，防止重复结算
var _granted_years: Array[int] = []
## 当前可用协议点
var _available_points: int = INITIAL_POINTS
## 当前系统形态阶段
var _stage: TechNodeData.Stage = TechNodeData.Stage.C550

# ============================================================
# 公共方法
# ============================================================

## 从科技资源目录加载所有节点，并按节点 ID 建立索引
func load_nodes_from_disk() -> void:
	_nodes_by_id.clear()
	var dir := DirAccess.open(TECHNOLOGY_PATH)
	if dir == null:
		push_warning("科技节点目录不存在: " + TECHNOLOGY_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var node_data := load(TECHNOLOGY_PATH + file_name)
			if node_data is TechNodeData:
				_nodes_by_id[node_data.node_id] = node_data
		file_name = dir.get_next()
	dir.list_dir_end()


## 返回按路线、阶段和节点 ID 排序的全部科技节点
func get_all_nodes() -> Array[TechNodeData]:
	var nodes: Array[TechNodeData] = []
	for value in _nodes_by_id.values():
		nodes.append(value as TechNodeData)
	nodes.sort_custom(
		func(a: TechNodeData, b: TechNodeData) -> bool:
			if a.route != b.route:
				return a.route < b.route
			if a.stage != b.stage:
				return a.stage < b.stage
			return a.node_id < b.node_id
	)
	return nodes


## 根据稳定 ID 返回科技节点；节点不存在时返回 null
func get_node_data(node_id: String) -> TechNodeData:
	return _nodes_by_id.get(node_id) as TechNodeData


## 返回当前可用协议点
func get_available_points() -> int:
	return _available_points


## 返回已激活节点 ID 的副本，防止外部直接修改内部状态
func get_active_node_ids() -> Array[String]:
	return _active_node_ids.duplicate()


## 返回当前系统形态阶段
func get_stage() -> TechNodeData.Stage:
	return _stage


## 判断指定节点是否已经激活
func is_active(node_id: String) -> bool:
	return node_id in _active_node_ids


## 判断任一已激活节点是否提供指定能力标签
func has_tag(tag: String) -> bool:
	for node_id in _active_node_ids:
		var node_data := get_node_data(node_id)
		if node_data != null and tag in node_data.tags:
			return true
	return false


## 返回与指定节点发生互斥的已激活节点；没有冲突时返回空字符串
func get_exclusive_conflict(node_id: String) -> String:
	var node_data := get_node_data(node_id)
	if node_data == null or node_data.exclusive_group == "":
		return ""
	for active_node_id in _active_node_ids:
		var active_node := get_node_data(active_node_id)
		if (
			active_node != null
			and active_node.exclusive_group == node_data.exclusive_group
			and active_node.node_id != node_id
		):
			return active_node.node_id
	return ""


## 判断节点是否满足存在性、点数、阶段、前置和互斥条件
func can_activate(node_id: String) -> bool:
	var node_data := get_node_data(node_id)
	if node_data == null or is_active(node_id):
		return false
	if get_exclusive_conflict(node_id) != "":
		return false
	if _available_points < node_data.point_cost:
		return false
	if node_data.stage > _stage:
		return false
	for prerequisite_id in node_data.prerequisite_ids:
		if not is_active(prerequisite_id):
			return false
	return true


## 返回节点当前状态，供科技界面选择对应提示和样式
## 返回值可能为 missing、active、stage_locked、prerequisite_locked、
## points_locked 或 available
func get_activation_state(node_id: String) -> String:
	var node_data := get_node_data(node_id)
	if node_data == null:
		return "missing"
	if is_active(node_id):
		return "active"
	if get_exclusive_conflict(node_id) != "":
		return "exclusive_locked"
	if node_data.stage > _stage:
		return "stage_locked"
	for prerequisite_id in node_data.prerequisite_ids:
		if not is_active(prerequisite_id):
			return "prerequisite_locked"
	if _available_points < node_data.point_cost:
		return "points_locked"
	return "available"


## 激活指定节点并发出状态变化信号
## 返回 true 表示激活成功，false 表示激活条件不满足
func activate(node_id: String) -> bool:
	if not can_activate(node_id):
		return false

	var node_data := get_node_data(node_id)
	_available_points -= node_data.point_cost
	_active_node_ids.append(node_id)
	var previous_stage := _stage
	_update_stage()

	points_changed.emit(_available_points)
	node_activated.emit(node_id)
	if previous_stage != _stage:
		stage_changed.emit(_stage)
	return true


## 在预定研究年份发放一个协议点
## 返回 true 表示本次成功发放，false 表示年份无效或已经发放
func grant_research_for_year(year: int) -> bool:
	if year not in RESEARCH_YEARS or year in _granted_years:
		return false
	_granted_years.append(year)
	_available_points += 1
	points_changed.emit(_available_points)
	return true


## 重置已激活节点、研究年份、协议点和系统形态
func reset() -> void:
	_active_node_ids.clear()
	_granted_years.clear()
	_available_points = INITIAL_POINTS
	var previous_stage := _stage
	_stage = TechNodeData.Stage.C550
	points_changed.emit(_available_points)
	if previous_stage != _stage:
		stage_changed.emit(_stage)


## 导出当前科技状态快照，供界面显示和测试校验
func export_state() -> Dictionary:
	return {
		"available_points": _available_points,
		"active_node_ids": _active_node_ids.duplicate(),
		"granted_years": _granted_years.duplicate(),
		"stage": _stage,
	}


## 校验科技图节点数量、路线结构、前置引用和环依赖
## 返回所有发现的错误；空数组表示图结构有效
func validate_graph() -> Array[String]:
	var errors: Array[String] = []
	if _nodes_by_id.size() != 21:
		errors.append("科技节点数量必须为21")

	var route_stage_counts: Dictionary = {}
	for node_data in get_all_nodes():
		if node_data.node_id == "":
			errors.append("存在空节点ID")
		var route_key := str(node_data.route)
		if route_key not in route_stage_counts:
			route_stage_counts[route_key] = {
				TechNodeData.Stage.C550: 0,
				TechNodeData.Stage.W550: 0,
				TechNodeData.Stage.MOSS: 0,
			}
		route_stage_counts[route_key][node_data.stage] += 1
		for prerequisite_id in node_data.prerequisite_ids:
			if prerequisite_id not in _nodes_by_id:
				errors.append(
					"%s 的前置节点不存在: %s" % [
						node_data.node_id,
						prerequisite_id,
					]
				)

	for route in TechNodeData.Route.values():
		var counts: Dictionary = route_stage_counts.get(str(route), {})
		if (
			counts.get(TechNodeData.Stage.C550, 0) != 2
			or counts.get(TechNodeData.Stage.W550, 0) != 3
			or counts.get(TechNodeData.Stage.MOSS, 0) != 2
		):
			errors.append("路线 %d 必须包含2个550C、3个550W和2个MOSS节点" % route)

	var exclusive_groups: Dictionary = {}
	for node_data in get_all_nodes():
		if node_data.stage == TechNodeData.Stage.MOSS and node_data.exclusive_group == "":
			errors.append("MOSS终端必须设置互斥组: %s" % node_data.node_id)
		if node_data.exclusive_group == "":
			continue
		if node_data.stage != TechNodeData.Stage.MOSS:
			errors.append("只有MOSS终端可以设置互斥组: %s" % node_data.node_id)
		if node_data.exclusive_group not in exclusive_groups:
			exclusive_groups[node_data.exclusive_group] = []
		exclusive_groups[node_data.exclusive_group].append(node_data)

	if exclusive_groups.size() != 3:
		errors.append("科技图必须包含3个路线终端互斥组")
	for group_name in exclusive_groups:
		var group_nodes: Array = exclusive_groups[group_name]
		if group_nodes.size() != 2:
			errors.append("互斥组 %s 必须包含2个MOSS终端" % group_name)
		continue
		if group_nodes[0].route != group_nodes[1].route:
			errors.append("互斥组 %s 的终端必须属于同一路线" % group_name)

	# 使用深度优先搜索的访问中集合检测前置关系中的环。
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for node_id in _nodes_by_id:
		if _has_cycle(node_id, visiting, visited):
			errors.append("科技节点图存在环")
			break
	return errors

# ============================================================
# 私有方法
# ============================================================

## 根据已激活节点数量更新当前系统形态
func _update_stage() -> void:
	if _active_node_ids.size() >= 6:
		_stage = TechNodeData.Stage.MOSS
	elif _active_node_ids.size() >= 2:
		_stage = TechNodeData.Stage.W550
	else:
		_stage = TechNodeData.Stage.C550


## 递归检查指定节点的前置关系是否形成环
## visiting 记录当前递归链，visited 记录已经确认无环的节点
func _has_cycle(
	node_id: String,
	visiting: Dictionary,
	visited: Dictionary
) -> bool:
	if visited.get(node_id, false):
		return false
	if visiting.get(node_id, false):
		return true

	visiting[node_id] = true
	var node_data := get_node_data(node_id)
	if node_data != null:
		for prerequisite_id in node_data.prerequisite_ids:
			if _has_cycle(prerequisite_id, visiting, visited):
				return true
	visiting.erase(node_id)
	visited[node_id] = true
	return false
