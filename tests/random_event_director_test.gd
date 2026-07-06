## 随机事件导演测试
## 验证随机事件来自现有文档、可按局势筛选，并能复用主事件弹窗结算。
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const RANDOM_EVENT_PATH := "res://scripts/resources/random_event.gd"
const RANDOM_DIRECTOR_PATH := "res://scripts/systems/random_event_director.gd"
const RANDOM_EVENT_DIR := "res://data/random_events"

var _failed: int = 0
var _main_os: Control


func _ready() -> void:
	_assert_random_event_resource_contract()
	_assert_real_random_events_have_document_sources()
	_assert_random_event_director_filters_candidates()
	await _assert_main_scene_can_trigger_random_event()

	print("[MOSS-RANDOM-EVENT-DIRECTOR] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_random_event_resource_contract() -> void:
	var event := _create_random_event("contract")
	if event == null:
		return

	_assert_true(event is GameEvent, "RandomEvent 应继承 GameEvent 以复用事件弹窗和结算")
	var property_names := _get_property_names(event)
	for property_name in [
		"event_id",
		"earliest_year",
		"latest_year",
		"min_pressure_score",
		"pressure_axes",
		"cooldown_years",
		"weight",
		"source_reference",
		"design_role",
	]:
		_assert_true(
			property_name in property_names,
			"RandomEvent 应支持字段 %s" % property_name
		)


func _assert_real_random_events_have_document_sources() -> void:
	var dir := DirAccess.open(RANDOM_EVENT_DIR)
	_assert_true(dir != null, "应存在随机事件资源目录：%s" % RANDOM_EVENT_DIR)
	if dir == null:
		return

	var resources: Array[Resource] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource := load(RANDOM_EVENT_DIR.path_join(file_name)) as Resource
			if resource != null:
				resources.append(resource)
		file_name = dir.get_next()
	dir.list_dir_end()

	_assert_true(resources.size() >= 4, "随机事件池至少应覆盖四条现有压力来源")
	for resource in resources:
		_assert_true(resource is GameEvent, "随机事件资源应继承 GameEvent")
		_assert_true(str(resource.get("event_id")) != "", "随机事件应声明稳定 event_id")
		_assert_true(str(resource.get("source_reference")) != "", "随机事件应声明文档来源")
		_assert_true(str(resource.get("design_role")) != "", "随机事件应声明设计作用")
		_assert_source_reference_exists(str(resource.get("source_reference")))
		_assert_true(
			not Array(resource.get("options")).is_empty(),
			"随机事件应提供可选择方案：%s" % resource.get("event_title")
		)
		for option in Array(resource.get("options")):
			_assert_true(option is EventOption, "随机事件选项应使用 EventOption")
			if option is EventOption:
				_assert_true(
					option.event_state_key.begins_with("event_state.random_"),
					"随机事件选项应写入 event_state.random_*：%s" % resource.get("event_title")
				)


func _assert_random_event_director_filters_candidates() -> void:
	var director := _create_director()
	if director == null:
		return

	_assert_true(director.has_method("collect_candidates"), "RandomEventDirector 应提供候选筛选接口")
	_assert_true(director.has_method("select_event"), "RandomEventDirector 应提供可复现抽取接口")
	if not director.has_method("collect_candidates") or not director.has_method("select_event"):
		return

	var civic_event := _create_random_event("civic")
	var engineering_event := _create_random_event("engineering")
	if civic_event == null or engineering_event == null:
		return

	civic_event.set("event_id", "random_civic_pressure")
	civic_event.set("event_title", "地下城资格复核")
	civic_event.set("earliest_year", 2050)
	civic_event.set("latest_year", 2060)
	civic_event.set("min_pressure_score", 40)
	civic_event.set("pressure_axes", ["civil"])
	civic_event.set("weight", 10)
	civic_event.set("cooldown_years", 3)

	engineering_event.set("event_id", "random_engineering_pressure")
	engineering_event.set("event_title", "发动机维护疲劳")
	engineering_event.set("earliest_year", 2060)
	engineering_event.set("latest_year", 2072)
	engineering_event.set("min_pressure_score", 65)
	engineering_event.set("pressure_axes", ["engineering"])
	engineering_event.set("weight", 10)
	engineering_event.set("cooldown_years", 3)

	var snapshot := {
		"year": 2055,
		"pressure_score": 58,
		"dominant_axis": "civil",
		"pressure_band": "strained",
	}
	var candidates: Array = director.collect_candidates(
		[civic_event, engineering_event],
		snapshot,
		{}
	)
	_assert_eq(candidates.size(), 1, "候选筛选应匹配年份、压力和主导轴")
	if not candidates.is_empty():
		_assert_eq(candidates[0].get("event_id"), "random_civic_pressure", "应保留民生压力事件")

	var selected: Resource = director.select_event(candidates, 11)
	_assert_true(selected == civic_event, "单候选抽取应稳定返回该事件")

	candidates = director.collect_candidates(
		[civic_event],
		snapshot,
		{"random_civic_pressure": 2054}
	)
	_assert_true(candidates.is_empty(), "冷却期内不应再次抽取同一随机事件")


func _assert_main_scene_can_trigger_random_event() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	for method_name in [
		"get_random_event_candidates",
		"set_random_seed",
		"try_trigger_random_event",
	]:
		_assert_true(_main_os.has_method(method_name), "MainOS 应提供随机事件接口：%s" % method_name)
	if (
		not _main_os.has_method("get_random_event_candidates")
		or not _main_os.has_method("set_random_seed")
		or not _main_os.has_method("try_trigger_random_event")
	):
		return

	var random_event := _create_random_event("runtime")
	if random_event == null:
		return
	random_event.set("event_id", "random_runtime_test")
	random_event.set("event_title", "测试随机事件")
	random_event.set("event_region", "联合政府")
	random_event.set("event_description", "测试随机事件运行时触发。")
	random_event.set("event_level", "一般事件")
	random_event.set("earliest_year", 2044)
	random_event.set("latest_year", 2044)
	random_event.set("min_pressure_score", 0)
	random_event.set("pressure_axes", ["authority"])
	random_event.set("weight", 1)
	random_event.set("cooldown_years", 2)
	random_event.set("source_reference", "docs/design/游戏内容规范.md#轻量事件状态与中型事件")
	random_event.set("design_role", "测试随机事件弹窗和状态写入。")
	var runtime_options: Array[EventOption] = [_create_runtime_option()]
	random_event.set("options", runtime_options)

	_main_os.set("all_random_events", [random_event])
	_main_os.set("all_events", [] as Array[GameEvent])
	_main_os.set("random_event_monthly_chance", 1.0)
	_main_os.set_random_seed(5)
	_main_os.current_year = 2044
	_main_os.current_month = 6
	var triggered: bool = await _main_os.try_trigger_random_event()
	await get_tree().process_frame
	_assert_true(triggered, "满足条件且概率为 1 时应触发随机事件")
	_assert_true((_main_os.get_node("%EventPopup") as Control).visible, "随机事件应复用事件弹窗")
	(_main_os.get_node("%EventPopup") as Control).option_selected.emit(0)
	await get_tree().process_frame
	_assert_eq(
		_main_os.get_event_state("event_state.random_runtime_test"),
		"acknowledged",
		"随机事件选项应写入轻量事件状态"
	)


func _create_random_event(event_id: String) -> Resource:
	var script := ResourceLoader.load(
		RANDOM_EVENT_PATH,
		"GDScript",
		ResourceLoader.CACHE_MODE_IGNORE
	) as GDScript
	_assert_true(script != null, "应存在 RandomEvent 脚本：%s" % RANDOM_EVENT_PATH)
	if script == null:
		return null
	var event := script.new() as Resource
	_assert_true(event != null, "RandomEvent 脚本应可实例化")
	if event != null:
		event.set("event_id", event_id)
	return event


func _create_director() -> RefCounted:
	var script := ResourceLoader.load(
		RANDOM_DIRECTOR_PATH,
		"GDScript",
		ResourceLoader.CACHE_MODE_IGNORE
	) as GDScript
	_assert_true(script != null, "应存在 RandomEventDirector 脚本：%s" % RANDOM_DIRECTOR_PATH)
	if script == null:
		return null
	var director := script.new() as RefCounted
	_assert_true(director != null, "RandomEventDirector 应为无场景依赖服务")
	return director


func _create_runtime_option() -> EventOption:
	var option := EventOption.new()
	option.button_text = "记录随机扰动"
	option.order_delta = -1
	option.hope_delta = -1
	option.authority_delta = 1
	option.event_state_key = "event_state.random_runtime_test"
	option.event_state_value = "acknowledged"
	return option


func _assert_source_reference_exists(source_reference: String) -> void:
	var source_path: String = source_reference.get_slice("#", 0)
	_assert_true(
		source_path.begins_with("docs/"),
		"随机事件来源应指向 docs 目录：%s" % source_reference
	)
	_assert_true(
		FileAccess.file_exists("res://" + source_path),
		"随机事件来源文档应存在：%s" % source_reference
	)


func _get_property_names(value: Object) -> Array[String]:
	var property_names: Array[String] = []
	for property in value.get_property_list():
		property_names.append(str(property["name"]))
	return property_names


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
