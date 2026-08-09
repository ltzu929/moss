## 行动日志显示组件。
## 只负责日志条目的显示生命周期，不读取年月、资源或 MainOS 状态。
class_name ActionLogView
extends Panel

# ============================================================
# 常量
# ============================================================

const ACTION_LOG_LIMIT: int = 24
const TYPEWRITER_CHAR_DELAY_SEC: float = 0.02
const TYPEWRITER_NEWLINE_DELAY_SEC: float = 0.08

# ============================================================
# 显示状态
# ============================================================

var _typewriter_queue: Array[Dictionary] = []
var _typewriter_active: bool = false
var _typewriter_generation: int = 0

# ============================================================
# 公开接口
# ============================================================

## 追加一个领域日志条目并启动显示队列。
func append_entry(entry: Dictionary) -> void:
	_typewriter_queue.append(_build_display_entry(entry))
	while _typewriter_queue.size() > ACTION_LOG_LIMIT:
		_typewriter_queue.pop_front()

	if not _typewriter_active:
		_process_typewriter_queue()


## 清空当前显示、待显示队列和仍在等待的旧打字机协程。
func clear() -> void:
	_typewriter_generation += 1
	var log_container := _get_log_container()
	if log_container != null:
		for child in log_container.get_children():
			log_container.remove_child(child)
			child.queue_free()

	_typewriter_queue.clear()
	_typewriter_active = false
	var cursor := _get_log_cursor()
	if cursor != null:
		cursor.visible = true


## 返回显示组件是否没有正在处理的条目。
func is_idle() -> bool:
	return not _typewriter_active and _typewriter_queue.is_empty()


## 返回尚未开始显示的待处理条目数量，不包含当前正在打字的条目。
func get_pending_count() -> int:
	return _typewriter_queue.size()


## 返回只读调试快照；嵌套数据均为深拷贝。
func get_debug_snapshot() -> Dictionary:
	var display_count := 0
	var log_container := _get_log_container()
	if log_container != null:
		display_count = log_container.get_child_count()

	var cursor_visible := true
	var cursor := _get_log_cursor()
	if cursor != null:
		cursor_visible = cursor.visible

	return {
		"pending_entries": _typewriter_queue.duplicate(true),
		"pending_count": _typewriter_queue.size(),
		"is_active": _typewriter_active,
		"generation": _typewriter_generation,
		"display_count": display_count,
		"cursor_visible": cursor_visible,
	}

# ============================================================
# 显示实现
# ============================================================

## 把领域条目转换为显示文本；不改变传入字典。
func _build_display_entry(entry: Dictionary) -> Dictionary:
	var year: int = entry.get("year", 2044)
	var month: int = entry.get("month", 1)
	var kind: String = entry.get("kind", "")
	var title: String = entry.get("title", "")
	var message: String = entry.get("message", "")

	var full_text := "[%04d.%02d]" % [year, month]
	match kind:
		"event":
			full_text += " [EVENT]"
		"command":
			full_text += " [CMD]"
		"technology":
			full_text += " [TECH]"
		"ending":
			full_text += " [END]"
		_:
			full_text += " [%s]" % kind.to_upper()

	full_text += " %s" % title
	if message != "":
		full_text += "\n　%s" % message

	return {"text": full_text, "kind": kind, "message": message}


## 获取日志条目容器。
func _get_log_container() -> VBoxContainer:
	if has_node("%LogEntryContainer"):
		return get_node("%LogEntryContainer") as VBoxContainer
	return null


## 获取日志滚动容器。
func _get_log_scroll_container() -> ScrollContainer:
	if has_node("%LogScrollContainer"):
		return get_node("%LogScrollContainer") as ScrollContainer
	return null


## 获取光标标签。
func _get_log_cursor() -> Label:
	if has_node("%LogCursor"):
		return get_node("%LogCursor") as Label
	return null


## 处理打字机队列。
func _process_typewriter_queue() -> void:
	if _typewriter_queue.is_empty():
		_typewriter_active = false
		return

	_typewriter_active = true
	var entry_info: Dictionary = _typewriter_queue.pop_front()
	var full_text: String = entry_info["text"]
	var kind: String = entry_info["kind"]

	var log_container := _get_log_container()
	if log_container == null:
		_typewriter_active = false
		return
	_trim_log_entries(log_container, ACTION_LOG_LIMIT - 1)

	var log_label := Label.new()
	log_label.name = "LogEntry"

	var text_color := Color(0.8, 0.8, 0.8)
	match kind:
		"event":
			text_color = Color(0.545, 0.867, 0.835)
		"command":
			text_color = Color(0.4, 0.7, 1.0)
		"technology":
			text_color = Color(0.42, 0.8, 0.27)
		"ending":
			text_color = Color(1.0, 0.42, 0.42)

	log_label.add_theme_color_override("font_color", text_color)
	log_label.custom_maximum_size = Vector2(maxf(log_container.get_parent_area_size().x, 1.0), -1.0)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_container.add_child(log_label)

	_start_typewriter(log_label, full_text, _typewriter_generation)


## 在创建新标签前同步移除溢出的旧标签，避免延迟删除造成计数不变的紧循环。
func _trim_log_entries(log_container: VBoxContainer, maximum_entries: int) -> void:
	var overflow := maxi(0, log_container.get_child_count() - maximum_entries)
	for _index in range(overflow):
		var oldest_entry := log_container.get_child(0)
		log_container.remove_child(oldest_entry)
		oldest_entry.queue_free()


## 逐字显示日志文本。
func _start_typewriter(label: Label, full_text: String, generation: int) -> void:
	var cursor := _get_log_cursor()
	if cursor != null:
		cursor.visible = false

	var chars := full_text.length()
	for i in range(chars):
		if generation != _typewriter_generation or not is_instance_valid(label):
			if generation == _typewriter_generation:
				_process_typewriter_queue()
			return
		label.text = full_text.left(i + 1)

		var scroll := _get_log_scroll_container()
		if scroll != null:
			await get_tree().process_frame
			if generation != _typewriter_generation or not is_instance_valid(label):
				if generation == _typewriter_generation:
					_process_typewriter_queue()
				return
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

		if full_text[i] == '\n':
			await get_tree().create_timer(TYPEWRITER_NEWLINE_DELAY_SEC).timeout
		else:
			await get_tree().create_timer(TYPEWRITER_CHAR_DELAY_SEC).timeout

	if generation != _typewriter_generation:
		return

	if cursor != null:
		cursor.visible = true
	_process_typewriter_queue()
