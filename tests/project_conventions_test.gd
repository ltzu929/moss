## 项目约定测试
## 验证低误伤的代码和 Godot 工程约定。
extends Node

# ============================================================
# 常量
# ============================================================

const NAME_CHECK_ROOTS: Array[String] = [
	"res://scripts",
	"res://scenes",
	"res://data",
	"res://tests",
]

const CODE_CHECK_ROOTS: Array[String] = [
	"res://scripts",
	"res://tests",
]

const PRODUCTION_SCRIPT_ROOTS: Array[String] = [
	"res://scripts",
]

const FILE_NAME_EXTENSIONS: Array[String] = [
	"gd",
	"tscn",
	"tres",
]

const FORBIDDEN_PROCESS_PATTERNS: Array[String] = [
	"load(",
	"ResourceLoader.load(",
	"DirAccess",
	"FileAccess",
]

const FORBIDDEN_EMIT_SIGNAL := "emit_" + "signal("
const FORBIDDEN_CHAINED_GET_PARENT := "get_parent()" + ".get_parent()"

# ============================================================
# 测试状态
# ============================================================

var _failed: int = 0
var _function_regex := RegEx.new()

# ============================================================
# 测试入口
# ============================================================

## 执行项目约定扫描
func _ready() -> void:
	_function_regex.compile("^\\s*func\\s+[^\\(]+\\([^\\)]*\\)\\s*(?:->|$)")

	_assert_file_names()
	_assert_no_legacy_signal_emit()
	_assert_function_return_types()
	_assert_no_chained_get_parent()
	_assert_process_has_no_blocking_work()

	print("[MOSS-CONVENTIONS] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)

# ============================================================
# 约定检查
# ============================================================

## 检查 Godot 资源文件名使用 snake_case
func _assert_file_names() -> void:
	for root in NAME_CHECK_ROOTS:
		for path in _collect_files(root):
			if not path.get_extension() in FILE_NAME_EXTENSIONS:
				continue
			var base_name := path.get_file().get_basename()
			_assert_true(
				_is_snake_case(base_name),
				"文件名应使用 snake_case：%s" % path
			)


## 禁止旧式字符串发信号，统一使用 signal_name.emit()
func _assert_no_legacy_signal_emit() -> void:
	for root in CODE_CHECK_ROOTS:
		for path in _collect_files(root, "gd"):
			_assert_true(
				not _source_has_pattern(path, FORBIDDEN_EMIT_SIGNAL),
				"信号发射应使用 .emit()：%s" % path
			)


## 所有函数必须声明返回类型
func _assert_function_return_types() -> void:
	for root in CODE_CHECK_ROOTS:
		for path in _collect_files(root, "gd"):
			var lines := _read_text(path).split("\n")
			for index in lines.size():
				var line := String(lines[index])
				if not line.strip_edges().begins_with("func "):
					continue
				var declaration := _collect_function_declaration(lines, index)
				_assert_true(
					_function_regex.search(declaration) != null and "->" in declaration,
					"函数必须标注返回类型：%s:%d" % [path, index + 1]
				)


## 禁止链式跨层父节点访问
func _assert_no_chained_get_parent() -> void:
	for root in CODE_CHECK_ROOTS:
		for path in _collect_files(root, "gd"):
			_assert_true(
				not _source_has_pattern(path, FORBIDDEN_CHAINED_GET_PARENT),
				"不得链式跨层 get_parent()：%s" % path
			)


## _process() 内不得执行加载、目录扫描或文件访问
func _assert_process_has_no_blocking_work() -> void:
	for root in PRODUCTION_SCRIPT_ROOTS:
		for path in _collect_files(root, "gd"):
			var blocks := _collect_function_blocks(path)
			for block in blocks:
				if not String(block["name"]) in ["_process", "_physics_process"]:
					continue
				for pattern in FORBIDDEN_PROCESS_PATTERNS:
					_assert_true(
						not pattern in String(block["body"]),
						"%s() 不应执行加载或磁盘访问：%s" % [block["name"], path]
					)

# ============================================================
# 文件辅助方法
# ============================================================

## 递归收集指定目录下的文件
func _collect_files(root: String, extension: String = "") -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		_assert_true(false, "目录应存在：%s" % root)
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var path := root.path_join(file_name)
		if dir.current_is_dir():
			result.append_array(_collect_files(path, extension))
		elif extension.is_empty() or path.get_extension() == extension:
			result.append(path)

		file_name = dir.get_next()
	dir.list_dir_end()
	return result


## 读取文本文件
func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_assert_true(false, "文件应可读取：%s" % path)
		return ""
	return file.get_as_text()


## 判断源码代码行中是否包含指定模式
func _source_has_pattern(path: String, pattern: String) -> bool:
	var lines := _read_text(path).split("\n")
	for line in lines:
		var source_line := String(line)
		if source_line.strip_edges().begins_with("#"):
			continue
		if pattern in source_line:
			return true
	return false


## 收集可能跨多行的函数声明
func _collect_function_declaration(lines: PackedStringArray, start_index: int) -> String:
	var declaration := ""
	for index in range(start_index, lines.size()):
		var line := String(lines[index])
		declaration += line.strip_edges() + " "
		if line.strip_edges().ends_with(":"):
			break
	return declaration


## 收集函数块，用于检查生命周期函数内部内容
func _collect_function_blocks(path: String) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var lines := _read_text(path).split("\n")
	var current_name := ""
	var current_indent := 0
	var current_body := ""

	for line_index in lines.size():
		var line := String(lines[line_index])
		if line.strip_edges().begins_with("func "):
			if not current_name.is_empty():
				blocks.append({"name": current_name, "body": current_body})

			current_name = _extract_function_name(line)
			current_indent = _leading_whitespace_size(line)
			current_body = line + "\n"
			continue

		if current_name.is_empty():
			continue

		var stripped := line.strip_edges()
		var indent := _leading_whitespace_size(line)
		if not stripped.is_empty() and indent <= current_indent:
			blocks.append({"name": current_name, "body": current_body})
			current_name = ""
			current_body = ""
			continue

		current_body += line + "\n"

	if not current_name.is_empty():
		blocks.append({"name": current_name, "body": current_body})

	return blocks


## 提取函数名
func _extract_function_name(line: String) -> String:
	var declaration := line.strip_edges()
	var open_paren := declaration.find("(")
	if open_paren == -1:
		return ""
	return declaration.substr(5, open_paren - 5).strip_edges()


## 计算前导空白长度
func _leading_whitespace_size(line: String) -> int:
	var count := 0
	while count < line.length():
		var character := line.substr(count, 1)
		if character != "\t" and character != " ":
			break
		count += 1
	return count


## 判断名称是否为 snake_case
func _is_snake_case(value: String) -> bool:
	if value.is_empty():
		return false
	for character_index in value.length():
		var character := value.substr(character_index, 1)
		var is_lower := character >= "a" and character <= "z"
		var is_digit := character >= "0" and character <= "9"
		var is_underscore := character == "_"
		if not (is_lower or is_digit or is_underscore):
			return false
	return not value.begins_with("_") and not value.ends_with("_") and not "__" in value

# ============================================================
# 断言辅助方法
# ============================================================

## 断言条件为 true，失败时累计退出码并输出错误
func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)
