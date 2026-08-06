## 稳定内容身份契约测试。
## 加载真实事件与区域资源，验证字段迁移、映射基线和显示文字解耦边界。
extends "res://tests/support/moss_test_case.gd"

const BASELINE_PATH: String = "res://tests/fixtures/content_identity_baseline.json"
const REGION_ID_BY_NAME: Dictionary = {
	"亚洲": "asia",
	"北美": "north_america",
	"欧洲": "europe",
	"非洲": "africa",
	"南美": "south_america",
	"大洋洲": "oceania",
}


func _ready() -> void:
	var baseline := _load_baseline()
	if baseline.is_empty():
		print("[MOSS-CONTENT-IDENTITY] 完成，失败断言：%d" % _failed)
		await get_tree().create_timer(0.2).timeout
		get_tree().quit(_failed)
		return

	var sectors := _load_sector_resources(baseline)
	_assert_event_resources(baseline, sectors)
	_assert_sector_resources(baseline)
	_assert_display_text_is_not_identity()

	print("[MOSS-CONTENT-IDENTITY] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _load_baseline() -> Dictionary:
	_assert_true(FileAccess.file_exists(BASELINE_PATH), "身份映射基线应存在")
	if not FileAccess.file_exists(BASELINE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	_assert_true(parsed is Dictionary, "身份映射基线必须是 JSON 对象")
	if not parsed is Dictionary:
		return {}
	var baseline: Dictionary = parsed
	_assert_eq(baseline.get("schema_version", 0), 1, "身份映射基线版本应为 1")
	return baseline


func _load_sector_resources(baseline: Dictionary) -> Dictionary:
	var sectors_by_id: Dictionary = {}
	var expected_sectors: Array = baseline.get("sectors", [])
	for entry_variant in expected_sectors:
		var entry: Dictionary = entry_variant
		var resource_path := str(entry.get("path", ""))
		var sector := load(resource_path) as SectorData
		_assert_true(sector != null, "区域资源应能加载：%s" % resource_path)
		if sector == null:
			continue
		_assert_eq(
			sector.region_id,
			str(entry.get("region_id", "")),
			"区域 ID 应匹配映射基线：%s" % resource_path
		)
		_assert_eq(
			sector.region_name,
			str(entry.get("region_name", "")),
			"区域显示名应匹配映射基线：%s" % resource_path
		)
		_assert_true(not sector.region_id.is_empty(), "区域 ID 不得为空：%s" % resource_path)
		_assert_true(not sectors_by_id.has(sector.region_id), "区域 ID 不得重复")
		sectors_by_id[sector.region_id] = sector

	_assert_eq(sectors_by_id.size(), 6, "应加载六个唯一区域")
	return sectors_by_id


func _assert_event_resources(baseline: Dictionary, sectors_by_id: Dictionary) -> void:
	var expected_events: Array = baseline.get("events", [])
	var event_ids: Dictionary = {}
	var decision_tag_writes: Dictionary = {}
	var expected_decision_tag_writes: Array = baseline.get("decision_tag_writes", [])
	var event_count := 0
	var branch_count := 0
	var required_branch_refs: Array[Dictionary] = []

	for entry_variant in expected_events:
		var entry: Dictionary = entry_variant
		var resource_path := str(entry.get("path", ""))
		var event := load(resource_path) as GameEvent
		_assert_true(event != null, "事件资源应能加载：%s" % resource_path)
		if event == null:
			continue
		event_count += 1

		var expected_event_id := str(entry.get("event_id", ""))
		_assert_true(not event.event_id.is_empty(), "事件 ID 不得为空：%s" % resource_path)
		_assert_true(not event_ids.has(event.event_id), "事件 ID 不得重复：%s" % event.event_id)
		_assert_eq(event.event_id, expected_event_id, "事件 ID 应匹配映射基线：%s" % resource_path)
		event_ids[event.event_id] = true
		_assert_eq(event.event_title, str(entry.get("event_title", "")), "事件标题不得漂移")
		_assert_eq(event.event_region, str(entry.get("event_region", "")), "事件区域不得漂移")
		_assert_eq(
			event.required_decision_tag_key,
			str(entry.get("required_decision_tag_key", "")),
			"条件分支键不得漂移"
		)
		_assert_eq(
			event.required_decision_tag_value,
			str(entry.get("required_decision_tag_value", "")),
			"条件分支值不得漂移"
		)
		_assert_true(
			event.required_decision_tag_key.is_empty() == event.required_decision_tag_value.is_empty(),
			"条件分支必须同时声明键和值：%s" % event.event_id
		)
		_assert_true(sectors_by_id.has(event.event_region), "事件区域必须引用真实区域 ID：%s" % event.event_id)
		if not event.required_decision_tag_key.is_empty():
			branch_count += 1
			_assert_true(
				not event.required_decision_tag_value.is_empty(),
				"条件分支必须有触发值：%s" % event.event_id
			)
			required_branch_refs.append(
				{
					"event_id": event.event_id,
					"key": event.required_decision_tag_key,
					"value": event.required_decision_tag_value,
				}
			)

		var expected_options: Array = entry.get("options", [])
		_assert_eq(event.options.size(), expected_options.size(), "选项数量不得漂移：%s" % event.event_id)
		var option_ids: Dictionary = {}
		for index in range(event.options.size()):
			var option: EventOption = event.options[index]
			var expected_option: Dictionary = expected_options[index] if index < expected_options.size() else {}
			_assert_true(not option.option_id.is_empty(), "选项 ID 不得为空：%s" % event.event_id)
			_assert_true(
				not option_ids.has(option.option_id),
				"同一事件内选项 ID 不得重复：%s" % event.event_id
			)
			_assert_eq(option.option_id, "option_%02d" % (index + 1), "选项 ID 应按固定顺序编号")
			_assert_eq(option.option_id, str(expected_option.get("option_id", "")), "选项 ID 不得漂移")
			_assert_eq(option.button_text, str(expected_option.get("button_text", "")), "选项文字不得漂移")
			_assert_eq(
				option.decision_tag_key,
				str(expected_option.get("decision_tag_key", "")),
				"选项决策标签键不得漂移"
			)
			_assert_eq(
				option.decision_tag_value,
				str(expected_option.get("decision_tag_value", "")),
				"选项决策标签值不得漂移"
			)
			_assert_true(
				option.decision_tag_key.is_empty() == option.decision_tag_value.is_empty(),
				"选项决策标签必须同时声明键和值：%s/%s" % [event.event_id, option.option_id]
			)
			if not option.decision_tag_key.is_empty():
				decision_tag_writes[
					"%s|%s" % [option.decision_tag_key, option.decision_tag_value]
				] = true
			option_ids[option.option_id] = true

	_assert_eq(event_count, 25, "应覆盖全部 25 个事件资源")
	_assert_eq(branch_count, 2, "应保留两个条件分支事件")
	_assert_eq(
		decision_tag_writes.size(),
		expected_decision_tag_writes.size(),
		"决策标签写入数量不得漂移"
	)
	for write_variant in expected_decision_tag_writes:
		var write: Dictionary = write_variant
		var write_key := str(write.get("decision_tag_key", ""))
		var write_value := str(write.get("decision_tag_value", ""))
		var write_pair := "%s|%s" % [write_key, write_value]
		_assert_true(
			decision_tag_writes.has(write_pair),
			"身份基线中的决策标签写入必须来自真实选项：%s" % write_pair
		)

	for required_variant in required_branch_refs:
		var required: Dictionary = required_variant
		var required_pair := "%s|%s" % [required.get("key", ""), required.get("value", "")]
		_assert_true(
			decision_tag_writes.has(required_pair),
			"条件分支引用必须命中真实选项写入：%s -> %s" % [required.get("event_id", ""), required_pair]
		)


func _assert_sector_resources(baseline: Dictionary) -> void:
	var region_ids: Dictionary = {}
	for entry_variant in baseline.get("sectors", []):
		var entry: Dictionary = entry_variant
		var region_name := str(entry.get("region_name", ""))
		var region_id := str(entry.get("region_id", ""))
		_assert_eq(
			region_id,
			str(REGION_ID_BY_NAME.get(region_name, "")),
			"区域 ID 应使用固定 ASCII 映射：%s" % region_name
		)
		_assert_true(not region_id.is_empty(), "区域 ID 不得为空：%s" % region_name)
		_assert_true(not region_ids.has(region_id), "区域 ID 不得重复：%s" % region_id)
		region_ids[region_id] = true
	_assert_eq(region_ids.size(), 6, "应存在六个唯一区域 ID")


func _assert_display_text_is_not_identity() -> void:
	var event := load("res://data/events/event_2044_space_elevator_crisis.tres") as GameEvent
	var sector := load("res://data/sector_asia.tres") as SectorData
	_assert_true(event != null and sector != null, "文字解耦测试资源应能加载")
	if event == null or sector == null:
		return

	var event_copy := event.duplicate(true) as GameEvent
	var original_event_id := event_copy.event_id
	var original_option_id := event_copy.options[0].option_id
	event_copy.event_title = "仅修改显示标题"
	event_copy.options[0].button_text = "仅修改显示方案文字"
	_assert_eq(event_copy.event_id, original_event_id, "修改事件标题不得改变事件 ID")
	_assert_eq(event_copy.options[0].option_id, original_option_id, "修改方案文字不得改变选项 ID")

	var sector_copy := sector.duplicate(true) as SectorData
	var original_region_id := sector_copy.region_id
	sector_copy.region_name = "仅修改显示区域名"
	_assert_eq(sector_copy.region_id, original_region_id, "修改区域显示名不得改变区域 ID")
