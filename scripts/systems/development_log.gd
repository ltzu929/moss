## 开发期诊断日志写入器
## 用于崩溃后从 user:// 下的 JSONL 文件还原最后运行状态。
class_name DevelopmentLog
extends RefCounted

# ============================================================
# 常量
# ============================================================

const DEFAULT_LOG_PATH: String = "user://moss_development_diagnostics.jsonl"
const DEFAULT_MAX_BYTES: int = 512 * 1024
const FORMAT_VERSION: int = 1

# ============================================================
# 成员变量
# ============================================================

var _log_path: String = DEFAULT_LOG_PATH
var _enabled: bool = true
var _max_bytes: int = DEFAULT_MAX_BYTES
var _session_id: String = ""

# ============================================================
# 公共接口
# ============================================================

## 配置日志路径、开关和单文件大小上限。
func configure(
	log_path: String = DEFAULT_LOG_PATH,
	enabled: bool = true,
	max_bytes: int = DEFAULT_MAX_BYTES
) -> void:
	_log_path = log_path
	_enabled = enabled
	_max_bytes = max_bytes


## 开始一次运行会话，并写入会话头。
func start_session(details: Dictionary = {}) -> void:
	if not _enabled:
		return

	_session_id = _build_session_id()
	_rotate_if_needed()
	write_entry("session_started", {}, details)


## 写入一条诊断日志。每条为独立 JSON 行，方便崩溃后读取最后一行。
func write_entry(
	event: String,
	snapshot: Dictionary = {},
	details: Dictionary = {}
) -> void:
	if not _enabled:
		return

	if _session_id.is_empty():
		_session_id = _build_session_id()

	var entry := {
		"version": FORMAT_VERSION,
		"session_id": _session_id,
		"event": event,
		"ticks_msec": Time.get_ticks_msec(),
		"unix_time": Time.get_unix_time_from_system(),
		"snapshot": snapshot.duplicate(true),
		"details": details.duplicate(true),
	}
	_append_line(JSON.stringify(entry))


## 返回当前日志路径，便于开发工具定位。
func get_log_path() -> String:
	return _log_path

# ============================================================
# 文件写入
# ============================================================

## 追加一行日志。每次写入后关闭文件，让崩溃前状态尽量落盘。
func _append_line(line: String) -> void:
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


## 会话开始时如果日志过大，则把旧日志挪到 .1 文件。
func _rotate_if_needed() -> void:
	if _max_bytes <= 0:
		return
	if not FileAccess.file_exists(_log_path):
		return

	var file := FileAccess.open(_log_path, FileAccess.READ)
	if file == null:
		return
	var length := file.get_length()
	file.close()
	if length <= _max_bytes:
		return

	var absolute_path := ProjectSettings.globalize_path(_log_path)
	var rotated_path := absolute_path + ".1"
	if FileAccess.file_exists(rotated_path):
		DirAccess.remove_absolute(rotated_path)
	DirAccess.rename_absolute(absolute_path, rotated_path)


## 构造当前运行会话 ID。
func _build_session_id() -> String:
	return "%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
