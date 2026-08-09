## 完整通关测试的日志、汇总和退出码报告。
class_name PlaythroughReporter
extends RefCounted

var _test_root: Node = null
var _route_id: String = ""
var _main_os: Control = null
var _log_entries: Array[String] = []


func configure(test_root: Node, route_id: String, main_os: Control = null) -> void:
	_test_root = test_root
	_route_id = route_id
	_main_os = main_os


func set_main_os(main_os: Control) -> void:
	_main_os = main_os


func write_log(message: String) -> void:
	_log_entries.append(message)
	print("[MOSS-TEST] ", message)


## 输出与旧测试入口兼容的最终标记，并以失败断言数退出。
func finish(
	_game_ended: bool,
	game_result: String,
	game_message: String,
	event_log: Dictionary,
	passed: int,
	failed: int,
	assertions: Array[Dictionary]
) -> void:
	write_log("")
	write_log("==========================================")
	write_log("  MOSS模拟器 代表性路线测试报告：%s" % _route_id)
	write_log("==========================================")

	var total: int = passed + failed
	write_log("")
	write_log("总断言数: %d" % total)
	write_log("通过: %d" % passed)
	write_log("失败: %d" % failed)

	if total > 0:
		var rate: float = float(passed) / float(total) * 100.0
		write_log("通过率: %.1f%%" % rate)

	if failed > 0:
		write_log("")
		write_log("失败断言详情:")
		for assertion in assertions:
			if not bool(assertion.get("passed", false)):
				write_log("  X [%s] %s (期望=%s, 实际=%s)" % [
					str(assertion.get("group", "")),
					str(assertion.get("description", "")),
					str(assertion.get("expected", "")),
					str(assertion.get("actual", "")),
				])

	write_log("")
	write_log("--- 游戏状态摘要 ---")
	if _main_os != null:
		write_log("游戏结果: %s" % game_result)
		if game_message != "":
			write_log("消息: %s" % game_message)
		write_log("最终日期: %04d.%02d" % [_main_os.current_year, _main_os.current_month])
		write_log("最终CPU: %d" % _main_os.current_cpu)
		write_log("最终能源: %d" % _main_os.current_energy)
		write_log("最终平均控制权: %d" % _main_os.get_average_authority())
		write_log("最终科技阶段: %d" % _main_os.technology_stage_level)
		write_log(
			"科技节点: %s" % str(
				_main_os.get_node("%TechnologySystem").get_active_node_ids()
			)
		)
		write_log("事件日志: %s" % str(event_log))
	else:
		write_log("MainOS实例不可用")

	write_log("")
	write_log("=== 测试结束 ===")
	print("[MOSS-ROUTE:%s] 完成，失败断言：%d" % [_route_id, failed])
	if _test_root != null:
		_test_root.get_tree().quit(failed)
