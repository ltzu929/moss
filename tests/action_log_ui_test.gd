## 行动日志 UI 回归测试：容量上限、延迟删除安全和打字机队列有界。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const ACTION_LOG_LIMIT: int = 24
const LOG_VIEW_PATH: NodePath = NodePath(
	"MainLayout/StrategicWorkspace/ContentRow/ContextPanel/ContextMargin/ContextVBox/LogPlaceholder"
)

var _main_os: Control
var _action_log_view: ActionLogView


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()
	_action_log_view = _main_os.get_node_or_null(LOG_VIEW_PATH) as ActionLogView
	_assert_true(_action_log_view != null, "主场景应装配 ActionLogView 显示组件")
	if _action_log_view == null:
		get_tree().quit(_failed)
		return

	_assert_full_container_evicts_without_hanging()
	await get_tree().process_frame
	await _assert_burst_queue_stays_bounded()
	await _assert_active_typewriter_is_cancelled_by_clear()

	print("[MOSS-ACTION-LOG-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


## 预先填满真实日志容器，再走 record_action() 验证同步缩容能立即返回。
func _assert_full_container_evicts_without_hanging() -> void:
	_action_log_view.clear()
	var log_container := _get_log_container()
	for index in range(ACTION_LOG_LIMIT):
		var label := Label.new()
		label.name = "ExistingLog%d" % index
		label.text = "existing-%d" % index
		log_container.add_child(label)

	_main_os.record_action("situation", "容量边界", "写入第 25 条日志")

	_assert_eq(
		log_container.get_child_count(),
		ACTION_LOG_LIMIT,
		"满容量日志写入后应立即移除一个旧标签并保持固定上限"
	)
	_assert_true(
		not log_container.has_node("ExistingLog0"),
		"容量淘汰应从场景树同步移除最旧标签"
	)


## 真实启动打字机后模拟高频交互，并等待最新 24 条完整显示。
func _assert_burst_queue_stays_bounded() -> void:
	_action_log_view.clear()
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 10.0
	for index in range(100):
		_main_os.record_action("situation", str(index), "")

	var action_log: Array[Dictionary] = _main_os.get_action_log()
	var snapshot := _action_log_view.get_debug_snapshot()
	_assert_true(bool(snapshot.get("is_active", false)), "突发写入期间应有真实打字机协程运行")
	_assert_eq(action_log.size(), ACTION_LOG_LIMIT, "领域行动日志应保持固定容量")
	_assert_eq(
		_action_log_view.get_pending_count(),
		ACTION_LOG_LIMIT,
		"打字机待处理队列应保持固定容量"
	)
	_assert_eq(
		str(action_log[0].get("title", "")),
		"76",
		"容量淘汰后应保留最近 24 条行动"
	)
	var pending_entries: Array = snapshot.get("pending_entries", [])
	_assert_eq(pending_entries.size(), ACTION_LOG_LIMIT, "调试快照应返回完整待处理队列")
	_assert_eq(
		str(pending_entries[0].get("text", "")),
		"[2044.01] [SITUATION] 76",
		"打字机队列应丢弃最旧积压并保留最近内容"
	)

	await _wait_for_typewriter_idle(1200)
	Engine.time_scale = previous_time_scale

	var log_container := _get_log_container()
	var first_label := log_container.get_child(0) as Label
	var last_label := log_container.get_child(ACTION_LOG_LIMIT - 1) as Label
	_assert_eq(
		log_container.get_child_count(),
		ACTION_LOG_LIMIT,
		"突发日志最终应收敛为 24 个标签"
	)
	_assert_eq(
		first_label.text,
		"[2044.01] [SITUATION] 76",
		"显示结果应从最新 24 条的首条开始"
	)
	_assert_eq(
		last_label.text,
		"[2044.01] [SITUATION] 99",
		"显示结果应保留最新一条"
	)
	_assert_eq(_action_log_view.get_pending_count(), 0, "打字机完成后待显示队列应清空")
	_assert_true(_action_log_view.is_idle(), "打字机完成后应回到空闲状态")
	snapshot = _action_log_view.get_debug_snapshot()
	_assert_true(bool(snapshot.get("cursor_visible", false)), "打字机完成后光标应恢复可见")


## 在真实协程等待帧或字符 Timer 时清空，旧协程醒来后不得恢复状态。
func _assert_active_typewriter_is_cancelled_by_clear() -> void:
	_action_log_view.clear()
	_main_os.record_action("situation", "协程取消", "等待中的旧日志不得恢复")
	var log_container := _get_log_container()
	var cursor := _get_log_cursor()
	var snapshot := _action_log_view.get_debug_snapshot()
	_assert_true(bool(snapshot.get("is_active", false)), "取消前应有真实打字机协程运行")
	_assert_eq(log_container.get_child_count(), 1, "取消前应已创建正在打字的标签")
	_assert_true(not cursor.visible, "打字期间光标应隐藏")

	await get_tree().process_frame
	_action_log_view.clear()
	_assert_eq(log_container.get_child_count(), 0, "清空应立即把旧标签移出场景树")
	_assert_eq(_action_log_view.get_pending_count(), 0, "清空应立即移除待显示记录")
	_assert_true(_action_log_view.is_idle(), "清空应立即停止打字机")
	_assert_true(cursor.visible, "清空应立即恢复光标")

	await get_tree().create_timer(0.12).timeout
	await get_tree().process_frame
	_assert_eq(
		log_container.get_child_count(),
		0,
		"旧协程等待结束后不应恢复并重新创建标签"
	)
	_assert_eq(_action_log_view.get_pending_count(), 0, "旧协程等待结束后不应修改新队列")
	_assert_true(_action_log_view.is_idle(), "旧协程等待结束后打字机应保持停止")
	_assert_true(cursor.visible, "旧协程等待结束后不应再次修改光标")


func _wait_for_typewriter_idle(maximum_frames: int) -> void:
	for _frame_index in range(maximum_frames):
		if _action_log_view.is_idle():
			return
		await get_tree().process_frame
	_assert_true(false, "真实打字机协程应在限定帧数内收敛")


func _get_log_container() -> VBoxContainer:
	return _action_log_view.get_node("LogVBox/LogScrollContainer/LogEntryContainer") as VBoxContainer


func _get_log_cursor() -> Label:
	return _action_log_view.get_node("LogVBox/LogCursor") as Label
