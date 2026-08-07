## 自动化播放测试入口。
## 具体路线配置、自动驾驶、断言和报告分别位于 tests/support/。
extends Control

@export_enum("mixed", "managed", "human_autonomy")
var route_id: String = "mixed"

const TEST_TIMER_INTERVAL: float = 0.05
const MAX_TEST_DURATION_MSEC: int = 80000
const ROUTE_CATALOG_SCRIPT := preload("res://tests/support/playthrough_route_catalog.gd")
const DRIVER_SCRIPT := preload("res://tests/support/playthrough_driver.gd")
const ASSERTIONS_SCRIPT := preload("res://tests/support/playthrough_assertions.gd")
const REPORTER_SCRIPT := preload("res://tests/support/playthrough_reporter.gd")

var _main_os: Control = null
var _route_config: Dictionary = {}
var _test_started_msec: int = 0
var _game_ended: bool = false
var _game_result: String = ""
var _game_message: String = ""
var _assertions_done: bool = false
var _finished: bool = false

var _route_catalog: PlaythroughRouteCatalog
var _driver: PlaythroughDriver
var _assertions: PlaythroughAssertions
var _reporter: PlaythroughReporter


func _ready() -> void:
	_test_started_msec = Time.get_ticks_msec()
	_route_catalog = ROUTE_CATALOG_SCRIPT.new()
	_reporter = REPORTER_SCRIPT.new()
	_reporter.configure(self, route_id)
	_assertions = ASSERTIONS_SCRIPT.new()
	_driver = DRIVER_SCRIPT.new()
	_route_config = _route_catalog.get_route_config(route_id)
	if _route_config.is_empty():
		_reporter.write_log("[FATAL] 未知代表性路线: %s" % route_id)
		_assertions.configure(null, route_id, {}, {}, [], _reporter, Callable())
		_assertions.assert_true(false, "代表性路线配置必须存在", "route_config")
		_finish_test()
		return

	_reporter.write_log("=== MOSS模拟器 代表性路线测试启动：%s ===" % route_id)
	_reporter.write_log("")
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	if scene == null:
		_reporter.write_log("[FATAL] 无法加载主场景")
		_assertions.configure(null, route_id, _route_config, {}, [], _reporter, Callable())
		_assertions.assert_true(false, "主场景必须可加载", "scene_integrity")
		_finish_test()
		return

	_main_os = scene.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	var timer: Timer = _main_os.get_node("Timer")
	timer.stop()
	timer.wait_time = TEST_TIMER_INTERVAL
	_main_os.set_situation_seed_for_test(424242)
	_reporter.set_main_os(_main_os)
	_driver.configure(
		_main_os,
		route_id,
		_route_config,
		_route_catalog,
		_assertions,
		_reporter,
		Callable(self, "get_route_command"),
		Callable(self, "request_situation_node"),
		Callable(self, "request_situation_approach"),
		Callable(self, "toggle_time_control"),
	)
	_assertions.configure(
		_main_os,
		route_id,
		_route_config,
		_driver.get_event_log(),
		_driver.get_seen_situation_ids(),
		_reporter,
		Callable(self, "get_average_stat_for_test"),
	)

	if not _assertions.verify_scene_integrity():
		_reporter.write_log("[FATAL] 场景完整性检查失败")
		_finish_test()
		return
	_driver.record_initial_state()
	_driver.drive_route_technology()
	_driver.setup_auto_responders()
	_main_os.game_ended.connect(_on_game_ended)
	timer.start()

	_reporter.write_log("测试环境就绪，路线=%s，Timer间隔: %.3fs" % [route_id, TEST_TIMER_INTERVAL])
	_reporter.write_log("---")
	set_process(true)


func _process(_delta: float) -> void:
	if (
		Time.get_ticks_msec() - _test_started_msec > MAX_TEST_DURATION_MSEC
		and not _game_ended
	):
		_reporter.write_log("[ERROR] 测试超时！路线未在 80 秒内结束")
		_game_ended = true
		_driver.set_game_ended(true)
		_run_all_assertions()
		_finish_test()
		set_process(false)
		return

	if _main_os == null:
		return
	_driver.poll_popups()
	_driver.poll_situations()
	_driver.drive_route_technology()
	_driver.drive_route_command()
	_driver.track_date()
	if _game_ended:
		set_process(false)


## 这些桥接接口只保留测试对 MainOS 私有实现的既有边界，供 support 脚本使用。
func get_route_command(command_id: String) -> CommandData:
	if _main_os == null:
		return null
	return _main_os._get_command_by_id(command_id)


func request_situation_node(instance_id: String, option_id: String) -> void:
	_main_os._on_situation_node_option_requested(instance_id, option_id)


func request_situation_approach(instance_id: String, approach_id: String) -> void:
	_main_os._on_situation_approach_requested(instance_id, approach_id)


func toggle_time_control() -> void:
	_main_os._on_time_control_button_pressed()


func get_average_stat_for_test(stat_name: String) -> int:
	if stat_name == "order":
		return _main_os._get_average_stat("order")
	return _main_os._get_average_stat("hope")


func _on_game_ended(result: String, message: String) -> void:
	_game_result = result
	_game_message = message
	_game_ended = true
	_driver.set_game_ended(true)

	_reporter.write_log("---")
	_reporter.write_log("游戏结束! 结果: %s" % result)
	_reporter.write_log("消息: %s" % message)

	while _driver.has_pending_popup_response():
		await get_tree().process_frame
	await get_tree().process_frame
	_run_all_assertions()
	_finish_test()


func _run_all_assertions() -> void:
	if _assertions_done:
		return
	_assertions_done = true
	_assertions.run_all(
		_game_ended,
		_game_result,
		_game_message,
		_driver.get_route_command_count(),
	)


func _finish_test() -> void:
	if _finished:
		return
	_finished = true
	_reporter.finish(
		_game_ended,
		_game_result,
		_game_message,
		_driver.get_event_log(),
		_assertions.get_passed_count(),
		_assertions.get_failed_count(),
		_assertions.get_results(),
	)
