## 开发诊断日志测试
## 验证开发期崩溃诊断日志独立于游戏内旧日志 UI，并能落盘为 JSONL。
extends Node

# ============================================================
# 常量
# ============================================================

const LOGGER_SCRIPT_PATH: String = "res://scripts/systems/development_log.gd"
const MAIN_SCENE_PATH: String = "res://scenes/main_os.tscn"
const UNIT_LOG_PATH: String = "user://moss_development_log_unit_test.jsonl"
const DEFAULT_LOG_PATH: String = "user://moss_development_diagnostics.jsonl"

# ============================================================
# 测试状态
# ============================================================

var _failed: int = 0

# ============================================================
# 测试入口
# ============================================================

## 执行开发诊断日志断言
func _ready() -> void:
	_delete_user_file(UNIT_LOG_PATH)
	_delete_user_file(DEFAULT_LOG_PATH)

	_assert_development_log_writes_jsonl()
	await _assert_main_scene_writes_startup_snapshot()

	print("[MOSS-DEVELOPMENT-LOG] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)

# ============================================================
# 断言
# ============================================================

## 独立日志器应写入可解析 JSONL，并保留事件、快照和详情字段
func _assert_development_log_writes_jsonl() -> void:
	var logger_script := load(LOGGER_SCRIPT_PATH)
	_assert_true(logger_script != null, "开发诊断日志脚本应存在")
	if logger_script == null:
		return

	var logger: RefCounted = logger_script.new()
	logger.configure(UNIT_LOG_PATH, true, 1024 * 1024)
	logger.start_session({"project": "MOSS", "mode": "unit_test"})
	logger.write_entry(
		"unit_event",
		{"year": 2044, "month": 1, "cpu": 30},
		{"reason": "test"}
	)

	var entries := _read_json_entries(UNIT_LOG_PATH)
	_assert_eq(entries.size(), 2, "独立日志器应写入 session 和事件两行")
	if entries.size() < 2:
		return

	_assert_eq(entries[0].get("event", ""), "session_started", "首行应记录会话开始")
	_assert_eq(entries[1].get("event", ""), "unit_event", "第二行应记录业务事件")
	_assert_eq(entries[1].get("snapshot", {}).get("year", 0), 2044, "事件快照应包含年份")
	_assert_eq(entries[1].get("details", {}).get("reason", ""), "test", "事件详情应保留原因")


## 主场景启动时应写入开发诊断快照，不依赖旧的游戏内日志 UI
func _assert_main_scene_writes_startup_snapshot() -> void:
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	_assert_true(scene != null, "主场景应可加载")
	if scene == null:
		return

	var main_os := scene.instantiate()
	add_child(main_os)
	await get_tree().process_frame

	var entries := _read_json_entries(DEFAULT_LOG_PATH)
	var ready_entry := _find_entry(entries, "game_ready")
	_assert_true(not ready_entry.is_empty(), "主场景启动应写入 game_ready 开发诊断日志")
	if not ready_entry.is_empty():
		var snapshot: Dictionary = ready_entry.get("snapshot", {})
		_assert_eq(snapshot.get("year", 0), 2044, "启动快照应包含当前年份")
		_assert_eq(snapshot.get("month", 0), 1, "启动快照应包含当前月份")
		_assert_true(snapshot.has("technology"), "启动快照应包含科技摘要")
		_assert_true(snapshot.has("resources"), "启动快照应包含资源摘要")

	main_os.queue_free()

# ============================================================
# 文件辅助方法
# ============================================================

## 删除 user:// 下的测试日志文件
func _delete_user_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 读取 JSONL 文件中的所有有效字典
func _read_json_entries(path: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return entries

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_assert_true(false, "日志文件应可读取：%s" % path)
		return entries

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		_assert_true(parsed is Dictionary, "日志行应是 JSON 字典：%s" % line)
		if parsed is Dictionary:
			entries.append(parsed)

	return entries


## 查找指定事件日志
func _find_entry(entries: Array[Dictionary], event_name: String) -> Dictionary:
	for entry in entries:
		if entry.get("event", "") == event_name:
			return entry
	return {}

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


## 断言两个值相等
func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] %s (期望=%s, 实际=%s)" % [message, str(expected), str(actual)])
