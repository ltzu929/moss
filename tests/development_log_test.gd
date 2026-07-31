## 开发诊断日志测试
## 验证开发期崩溃诊断日志独立于游戏内旧日志 UI，并能落盘为 JSONL。
extends "res://tests/support/moss_test_case.gd"

# ============================================================
# 常量
# ============================================================

const LOGGER_SCRIPT_PATH: String = "res://scripts/systems/development_log.gd"
const MAIN_SCENE_PATH: String = "res://scenes/main_os.tscn"
const UNIT_LOG_PATH: String = "user://moss_development_log_unit_test.jsonl"
const UNIT_HEARTBEAT_PATH: String = "user://moss_development_log_unit_heartbeat.json"
const ROTATION_LOG_PATH: String = "user://moss_development_log_rotation_test.jsonl"
const DEFAULT_LOG_PATH: String = "user://moss_development_diagnostics.jsonl"
const DEFAULT_HEARTBEAT_PATH: String = "user://moss_runtime_heartbeat.json"

# ============================================================
# 测试状态
# ============================================================


# ============================================================
# 测试入口
# ============================================================

## 执行开发诊断日志断言
func _ready() -> void:
	_delete_user_file(UNIT_LOG_PATH)
	_delete_user_file(UNIT_HEARTBEAT_PATH)
	_delete_user_file(ROTATION_LOG_PATH)
	_delete_user_file(ROTATION_LOG_PATH + ".1")
	_delete_user_file(DEFAULT_LOG_PATH)
	_delete_user_file(DEFAULT_HEARTBEAT_PATH)

	_assert_development_log_writes_jsonl_and_heartbeat()
	_assert_log_rotates_while_running()
	await _assert_main_scene_writes_startup_snapshot()

	print("[MOSS-DEVELOPMENT-LOG] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)

# ============================================================
# 断言
# ============================================================

## 独立日志器应写入可解析 JSONL，并由低频心跳保留当前运行阶段
func _assert_development_log_writes_jsonl_and_heartbeat() -> void:
	var logger_script := load(LOGGER_SCRIPT_PATH)
	_assert_true(logger_script != null, "开发诊断日志脚本应存在")
	if logger_script == null:
		return

	var logger: RefCounted = logger_script.new()
	logger.configure(
		UNIT_LOG_PATH,
		true,
		1024 * 1024,
		UNIT_HEARTBEAT_PATH
	)
	logger.start_session({"project": "MOSS", "mode": "unit_test"})
	logger.set_runtime_phase(
		"unit:waiting",
		{"year": 2044, "month": 1, "timer_stopped": true},
		{"reason": "heartbeat_test"}
	)
	logger.flush_heartbeat()
	logger.write_entry(
		"unit_event",
		{"year": 2044, "month": 1, "cpu": 30},
		{"reason": "test"}
	)
	logger.write_breadcrumb(
		"unit_breadcrumb",
		{"year": 2044, "month": 2},
		{"reason": "lightweight"}
	)

	var entries := _read_json_entries(UNIT_LOG_PATH)
	_assert_eq(entries.size(), 3, "独立日志器应写入会话、检查点和路径记录")
	if entries.size() < 3:
		logger.shutdown()
		return

	_assert_eq(entries[0].get("event", ""), "session_started", "首行应记录会话开始")
	_assert_eq(entries[1].get("event", ""), "unit_event", "第二行应记录业务事件")
	_assert_eq(entries[1].get("kind", ""), "checkpoint", "业务事件应标记为完整检查点")
	_assert_eq(entries[1].get("snapshot", {}).get("year", 0), 2044, "事件快照应包含年份")
	_assert_eq(entries[1].get("details", {}).get("reason", ""), "test", "事件详情应保留原因")
	_assert_eq(entries[2].get("kind", ""), "breadcrumb", "高频事件应标记为轻量路径记录")

	var heartbeat := _read_json_object(UNIT_HEARTBEAT_PATH)
	_assert_eq(heartbeat.get("kind", ""), "heartbeat", "心跳文件应标记独立记录类型")
	_assert_eq(heartbeat.get("phase", ""), "unit:waiting", "心跳应保留当前运行阶段")
	_assert_eq(
		heartbeat.get("snapshot", {}).get("timer_stopped", false),
		true,
		"心跳应保留最小运行状态"
	)
	logger.shutdown()
	var stopped_heartbeat := _read_json_object(UNIT_HEARTBEAT_PATH)
	_assert_eq(
		stopped_heartbeat.get("phase", ""),
		"session_stopped",
		"正常关闭时应留下可区分崩溃的最终心跳"
	)


## 日志达到上限时应在同一会话内轮转，而不是等到下次启动
func _assert_log_rotates_while_running() -> void:
	var logger_script := load(LOGGER_SCRIPT_PATH)
	if logger_script == null:
		return

	var logger: RefCounted = logger_script.new()
	logger.configure(ROTATION_LOG_PATH, true, 700, "")
	logger.start_session({"mode": "rotation_test"})
	for index in range(12):
		logger.write_breadcrumb(
			"rotation_entry",
			{"index": index},
			{"payload": "0123456789abcdef"}
		)
	logger.shutdown()

	_assert_true(
		FileAccess.file_exists(ROTATION_LOG_PATH + ".1"),
		"日志运行期间超过上限后应生成 .1 轮转文件"
	)
	_assert_true(
		_get_file_length(ROTATION_LOG_PATH) <= 700,
		"当前日志文件应保持在配置上限内"
	)


## 主场景启动时应写入开发诊断快照，并保持独立于旧的游戏内日志 UI
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

	var heartbeat := _read_json_object(DEFAULT_HEARTBEAT_PATH)
	_assert_eq(heartbeat.get("phase", ""), "idle", "主场景就绪后心跳阶段应为空闲")
	_assert_eq(
		heartbeat.get("snapshot", {}).get("year", 0),
		2044,
		"主场景心跳应包含当前年份"
	)
	_assert_true(
		main_os.has_node("DevelopmentHeartbeatTimer"),
		"主场景应创建独立于游戏时间的低频心跳 Timer"
	)
	main_os.current_month = 2
	main_os._on_development_heartbeat_timeout()
	var refreshed_heartbeat := _read_json_object(DEFAULT_HEARTBEAT_PATH)
	_assert_eq(
		refreshed_heartbeat.get("snapshot", {}).get("month", 0),
		2,
		"低频 Timer 回调应覆盖写入最新月份快照"
	)

	main_os.queue_free()
	await get_tree().process_frame

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


## 读取单个 JSON 字典文件
func _read_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_assert_true(false, "JSON 文件应存在：%s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_assert_true(false, "JSON 文件应可读取：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_assert_true(parsed is Dictionary, "JSON 文件应包含字典：%s" % path)
	return parsed if parsed is Dictionary else {}


## 返回文件字节数
func _get_file_length(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


## 查找指定事件日志
func _find_entry(entries: Array[Dictionary], event_name: String) -> Dictionary:
	for entry in entries:
		if entry.get("event", "") == event_name:
			return entry
	return {}
