## 游戏内容加载器
## 负责从磁盘扫描并返回事件、局势和指令资源，不依赖场景树或主控制器。
class_name GameContentLoader
extends RefCounted

const EVENTS_PATH: String = "res://data/events/"
const SITUATIONS_PATH: String = "res://data/situations/"
const COMMANDS_PATH: String = "res://data/commands/"


## 按文件名顺序加载事件资源；事件 Resource 保持只读模板语义。
func load_events() -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	for file_name in _list_resource_files(EVENTS_PATH, "事件"):
		var event := load(EVENTS_PATH + file_name)
		if event is GameEvent:
			events.append(event)
	return events


## 按文件名顺序加载随机局势模板。
func load_situations() -> Array[SituationData]:
	var situations: Array[SituationData] = []
	for file_name in _list_resource_files(SITUATIONS_PATH, "局势"):
		var situation := load(SITUATIONS_PATH + file_name)
		if situation is SituationData:
			situations.append(situation)
	return situations


## 按文件名顺序加载指令，并为每个主场景创建独立运行态副本。
func load_commands() -> Array[CommandData]:
	var commands: Array[CommandData] = []
	for file_name in _list_resource_files(COMMANDS_PATH, "指令"):
		var command_template := load(COMMANDS_PATH + file_name)
		if not command_template is CommandData:
			continue
		var command := command_template.duplicate(true) as CommandData
		if command != null:
			commands.append(command)
	return commands


## 返回目录下按文件名排序的 .tres 文件；目录缺失时保留原有提示。
func _list_resource_files(path: String, resource_label: String) -> Array[String]:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("%s目录不存在: %s" % [resource_label, path])
		return []

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()
	return file_names
