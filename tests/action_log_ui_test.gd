## 行动日志 UI 回归测试：容量上限、延迟删除安全和打字机队列有界。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const ACTION_LOG_LIMIT: int = 24

var _main_os: Control


func _ready() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	_assert_full_container_evicts_without_hanging()
	await get_tree().process_frame
	await _assert_burst_queue_stays_bounded()

	print("[MOSS-ACTION-LOG-UI] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


## 预先填满真实日志容器，再走 record_action() 验证同步缩容能立即返回。
func _assert_full_container_evicts_without_hanging() -> void:
	_main_os._clear_log_ui()
	var log_container := _main_os.get_node("%LogEntryContainer") as VBoxContainer
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


## 模拟高频交互暂时快于打字机动画，队列只保留最近的有界记录。
func _assert_burst_queue_stays_bounded() -> void:
	_main_os._clear_log_ui()
	_main_os._typewriter_active = true
	for index in range(100):
		_main_os.record_action("situation", "突发操作 %d" % index, "队列容量测试")

	var action_log: Array[Dictionary] = _main_os.get_action_log()
	_assert_eq(action_log.size(), ACTION_LOG_LIMIT, "领域行动日志应保持固定容量")
	_assert_eq(
		_main_os._typewriter_queue.size(),
		ACTION_LOG_LIMIT,
		"打字机待处理队列应保持固定容量"
	)
	_assert_eq(
		str(action_log[0].get("title", "")),
		"突发操作 76",
		"容量淘汰后应保留最近 24 条行动"
	)
	_assert_eq(
		str(_main_os._typewriter_queue[0].get("text", "")),
		"[2044.01] [SITUATION] 突发操作 76\n　队列容量测试",
		"打字机队列应丢弃最旧积压并保留最近内容"
	)
	_main_os._clear_log_ui()
	await get_tree().process_frame
	_assert_eq(
		(_main_os.get_node("%LogEntryContainer") as VBoxContainer).get_child_count(),
		0,
		"清空日志后旧打字机协程不应恢复并重新创建标签"
	)
	_assert_true(not _main_os._typewriter_active, "清空日志后打字机应保持停止")
