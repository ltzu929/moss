## 开发期诊断日志写入器
## 用于崩溃后从 user:// 下的 JSONL 和心跳文件还原最后运行状态。
class_name DevelopmentDiagnosticsLog
extends RefCounted

# ============================================================
# 常量
# ============================================================

const DEFAULT_LOG_PATH: String = "user://moss_development_diagnostics.jsonl"
const DEFAULT_HEARTBEAT_PATH: String = "user://moss_runtime_heartbeat.json"
const DEFAULT_MAX_BYTES: int = 512 * 1024
const DEFAULT_HEARTBEAT_INTERVAL_SEC: float = 2.0
const FORMAT_VERSION: int = 2
const HEARTBEAT_TEMP_SUFFIX: String = ".tmp"

# ============================================================
# 成员变量
# ============================================================

var _log_path: String = DEFAULT_LOG_PATH
var _heartbeat_path: String = DEFAULT_HEARTBEAT_PATH
var _enabled: bool = true
var _max_bytes: int = DEFAULT_MAX_BYTES
var _session_id: String = ""
var _entry_index: int = 0
var _current_log_bytes: int = -1

var _runtime_phase: String = "not_started"
var _runtime_snapshot: Dictionary = {}
var _runtime_details: Dictionary = {}

# ============================================================
# 公共接口
# ============================================================

## 配置日志路径、开关、单文件大小上限和心跳路径。
func configure(
	log_path: String = DEFAULT_LOG_PATH,
	enabled: bool = true,
	max_bytes: int = DEFAULT_MAX_BYTES,
	heartbeat_path: String = DEFAULT_HEARTBEAT_PATH
) -> void:
	shutdown()
	_log_path = log_path
	_enabled = enabled
	_max_bytes = max_bytes
	_heartbeat_path = heartbeat_path
	_current_log_bytes = -1


## 开始一次运行会话，并写入会话头和首个心跳。
func start_session(details: Dictionary = {}) -> void:
	if not _enabled:
		return

	shutdown()
	_session_id = _build_session_id()
	_entry_index = 0
	set_runtime_phase("session_started", {}, details)
	write_entry("session_started", {}, details)
	flush_heartbeat()


## 写入一条带完整检查点的诊断日志。
func write_entry(
	event: String,
	snapshot: Dictionary = {},
	details: Dictionary = {}
) -> void:
	_write_jsonl_entry("checkpoint", event, snapshot, details)


## 写入一条轻量路径记录，避免高频事件反复序列化完整游戏状态。
func write_breadcrumb(
	event: String,
	snapshot: Dictionary = {},
	details: Dictionary = {}
) -> void:
	_write_jsonl_entry("breadcrumb", event, snapshot, details)


## 更新当前运行阶段；默认同时替换心跳使用的最小快照。
func set_runtime_phase(
	phase: String,
	snapshot: Dictionary = {},
	details: Dictionary = {},
	replace_snapshot: bool = true
) -> void:
	_runtime_phase = phase
	if replace_snapshot:
		_runtime_snapshot = snapshot.duplicate(true)
	_runtime_details = details.duplicate(true)


## 刷新心跳快照，同时保留当前阶段。
func update_runtime_snapshot(snapshot: Dictionary) -> void:
	_runtime_snapshot = snapshot.duplicate(true)


## 立即把当前阶段写入临时文件，再原子替换正式心跳，供卡死后读取。
func flush_heartbeat() -> bool:
	if not _enabled or _heartbeat_path.is_empty() or _session_id.is_empty():
		return false

	var heartbeat := {
		"version": FORMAT_VERSION,
		"kind": "heartbeat",
		"session_id": _session_id,
		"phase": _runtime_phase,
		"ticks_msec": Time.get_ticks_msec(),
		"unix_time": Time.get_unix_time_from_system(),
		"snapshot": _runtime_snapshot.duplicate(true),
		"details": _runtime_details.duplicate(true),
	}
	var temporary_path := _heartbeat_path + HEARTBEAT_TEMP_SUFFIX
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_line(JSON.stringify(heartbeat))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if not stored or write_error != OK:
		_remove_heartbeat_temporary_file(temporary_path)
		return false

	var temporary_absolute_path := ProjectSettings.globalize_path(temporary_path)
	var heartbeat_absolute_path := ProjectSettings.globalize_path(_heartbeat_path)
	var replace_error := _replace_heartbeat_file(
		temporary_absolute_path,
		heartbeat_absolute_path
	)
	if replace_error != OK:
		_remove_heartbeat_temporary_file(temporary_path)
		_report_heartbeat_replace_failure()
		return false
	return true


## 留下可区分正常退出与异常中断的最终心跳。
func shutdown() -> void:
	if not _enabled or _session_id.is_empty():
		return
	set_runtime_phase("session_stopped", _runtime_snapshot, {})
	flush_heartbeat()


## 返回当前日志路径，便于开发工具定位。
func get_log_path() -> String:
	return _log_path


## 返回当前心跳路径，便于开发工具直接读取最新运行阶段。
func get_heartbeat_path() -> String:
	return _heartbeat_path

# ============================================================
# JSONL 文件写入
# ============================================================

## 通过同目录重命名替换正式心跳；失败时旧文件保持不变。
func _replace_heartbeat_file(
	temporary_absolute_path: String,
	heartbeat_absolute_path: String
) -> Error:
	return DirAccess.rename_absolute(
		temporary_absolute_path,
		heartbeat_absolute_path
	)


func _remove_heartbeat_temporary_file(temporary_path: String) -> void:
	if not FileAccess.file_exists(temporary_path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))


func _report_heartbeat_replace_failure() -> void:
	push_warning("开发诊断心跳无法替换: %s" % _heartbeat_path)


func _write_jsonl_entry(
	kind: String,
	event: String,
	snapshot: Dictionary,
	details: Dictionary
) -> void:
	if not _enabled:
		return

	if _session_id.is_empty():
		_session_id = _build_session_id()

	_entry_index += 1
	var entry := {
		"version": FORMAT_VERSION,
		"kind": kind,
		"session_id": _session_id,
		"entry_index": _entry_index,
		"event": event,
		"phase": _runtime_phase,
		"ticks_msec": Time.get_ticks_msec(),
		"unix_time": Time.get_unix_time_from_system(),
		"snapshot": snapshot.duplicate(true),
		"details": details.duplicate(true),
	}
	_append_line(JSON.stringify(entry))


## 追加一行日志。每次写入后关闭文件，让崩溃前状态尽量落盘。
func _append_line(line: String) -> void:
	var incoming_bytes := line.to_utf8_buffer().size() + 1
	_rotate_if_needed(incoming_bytes)

	var file: FileAccess = null
	if FileAccess.file_exists(_log_path):
		file = FileAccess.open(_log_path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(_log_path, FileAccess.WRITE)

	if file == null:
		push_warning("开发诊断日志无法写入: %s" % _log_path)
		return

	file.store_line(line)
	file.close()
	_current_log_bytes += incoming_bytes


## 如果当前文件加上下一行会超过上限，则把旧日志轮转到 .1 文件。
func _rotate_if_needed(incoming_bytes: int = 0) -> void:
	if _max_bytes <= 0:
		return
	_initialize_current_log_bytes()
	if _current_log_bytes + incoming_bytes <= _max_bytes:
		return

	var absolute_path := ProjectSettings.globalize_path(_log_path)
	var rotated_path := absolute_path + ".1"
	if FileAccess.file_exists(rotated_path):
		DirAccess.remove_absolute(rotated_path)
	DirAccess.rename_absolute(absolute_path, rotated_path)
	_current_log_bytes = 0


func _initialize_current_log_bytes() -> void:
	if _current_log_bytes >= 0:
		return
	_current_log_bytes = 0
	if not FileAccess.file_exists(_log_path):
		return
	var file := FileAccess.open(_log_path, FileAccess.READ)
	if file == null:
		return
	_current_log_bytes = file.get_length()
	file.close()


## 构造当前运行会话 ID。
func _build_session_id() -> String:
	return "%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
