## 不依赖场景树的存档状态协议校验。
## SaveService 在主页面阶段使用它筛掉明显不可恢复的存档，
## MainOS 创建后仍会执行带资源模板的完整校验。
class_name SaveStateValidator
extends RefCounted

const SAVE_STATE_VERSION: int = 1
const INITIAL_YEAR: int = 2044
const END_YEAR: int = 2075
const ACTION_LOG_LIMIT: int = 24
const REGION_IDS: Array[String] = [
	"north_america",
	"south_america",
	"europe",
	"africa",
	"asia",
	"oceania",
]
const REGION_IDENTITY := preload("res://scripts/resources/region_identity.gd")
const TECHNOLOGY_SYSTEM_SCRIPT := preload("res://scripts/systems/technology_system.gd")
const SITUATION_SYSTEM_SCRIPT := preload("res://scripts/systems/situation_system.gd")
const CONTENT_LOADER_SCRIPT := preload("res://scripts/systems/game_content_loader.gd")


static func validate_state(state: Dictionary) -> bool:
	if not _is_int(state.get("version")) or int(state["version"]) != SAVE_STATE_VERSION:
		return false
	for key in [
		"time", "resources", "sectors", "events", "technology",
		"commands", "situations"
	]:
		if typeof(state.get(key)) != TYPE_DICTIONARY:
			return false
	if typeof(state.get("action_log")) != TYPE_ARRAY:
		return false
	return (
		_validate_time(state["time"])
		and _validate_resources(state["resources"])
		and _validate_sectors(state["sectors"])
		and _validate_events(state["events"])
		and _validate_technology(state["technology"])
		and _validate_commands(state["commands"])
		and _validate_situations(state["situations"])
		and _validate_action_log(state["action_log"])
		and _validate_selected_region(state.get("selected_region", ""))
	)


static func _validate_time(time: Dictionary) -> bool:
	return (
		_is_int(time.get("year"))
		and int(time["year"]) >= INITIAL_YEAR
		and int(time["year"]) <= END_YEAR
		and _is_int(time.get("month"))
		and int(time["month"]) >= 1
		and int(time["month"]) <= 12
		and _is_int(time.get("speed_index"))
		and int(time["speed_index"]) >= 0
		and int(time["speed_index"]) <= 2
		and _is_bool(time.get("manually_paused"))
		and _is_bool(time.get("situation_auto_paused"))
	)


static func _validate_resources(resources: Dictionary) -> bool:
	return (
		_is_int(resources.get("cpu"))
		and int(resources["cpu"]) >= 0
		and _is_int(resources.get("energy"))
		and int(resources["energy"]) >= 0
	)


static func _validate_sectors(sectors: Dictionary) -> bool:
	if sectors.size() != REGION_IDS.size():
		return false
	for region_id in REGION_IDS:
		if typeof(sectors.get(region_id)) != TYPE_DICTIONARY:
			return false
		var sector: Dictionary = sectors[region_id]
		for field in ["order", "hope", "authority"]:
			if not _is_int(sector.get(field)) or int(sector[field]) < 0 or int(sector[field]) > 100:
				return false
		if not _is_int(sector.get("population")) or int(sector["population"]) < 0:
			return false
		if not _is_bool(sector.get("is_locked")):
			return false
	return true


static func _validate_events(events: Dictionary) -> bool:
	if typeof(events.get("triggered")) != TYPE_ARRAY:
		return false
	for event_id in events["triggered"]:
		if not _is_string(event_id) or str(event_id).is_empty():
			return false
	var states: Variant = events.get("states")
	if typeof(states) != TYPE_DICTIONARY:
		return false
	for key in states:
		if not _is_string(key) or str(key).is_empty() or not _is_string(states[key]):
			return false
	var history: Variant = events.get("decision_history")
	return typeof(history) == TYPE_DICTIONARY and _validate_decision_history(history)


static func _validate_decision_history(history: Dictionary) -> bool:
	var tags: Variant = history.get("tags")
	var records: Variant = history.get("records")
	if typeof(tags) != TYPE_DICTIONARY or typeof(records) != TYPE_ARRAY:
		return false
	for key in tags:
		if not _is_string(key) or str(key).is_empty() or not _is_string(tags[key]) or str(tags[key]).is_empty():
			return false
	var seen: Dictionary = {}
	for raw_record in records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = raw_record
		for field in ["key", "value", "title", "summary", "event_title"]:
			if not _is_string(record.get(field)):
				return false
		var key := str(record["key"])
		if key.is_empty() or seen.has(key) or not tags.has(key) or str(tags[key]) != str(record["value"]):
			return false
		if not _is_int(record.get("year")) or not _is_int(record.get("month")):
			return false
		if int(record["month"]) < 1 or int(record["month"]) > 12:
			return false
		seen[key] = true
	return seen.size() == tags.size()


static func _validate_technology(technology: Dictionary) -> bool:
	var system: TechnologySystem = TECHNOLOGY_SYSTEM_SCRIPT.new()
	system.load_nodes_from_disk()
	var valid := system.can_restore_state(technology)
	system.free()
	return valid


static func _validate_commands(commands: Dictionary) -> bool:
	var cooldowns: Variant = commands.get("cooldowns")
	if typeof(cooldowns) != TYPE_DICTIONARY:
		return false
	for command_id in cooldowns:
		if not _is_string(command_id) or not _is_int(cooldowns[command_id]) or int(cooldowns[command_id]) < 0:
			return false
	return true


static func _validate_situations(situations: Dictionary) -> bool:
	if not _is_string(situations.get("rng_state")) or not str(situations["rng_state"]).is_valid_int():
		return false
	var snapshot := situations.duplicate(true)
	snapshot["rng_state"] = str(situations["rng_state"]).to_int()
	var system: SituationSystem = SITUATION_SYSTEM_SCRIPT.new()
	var loader: GameContentLoader = CONTENT_LOADER_SCRIPT.new()
	system.configure_templates(loader.load_situations())
	return system.can_restore_runtime_snapshot(snapshot)


static func _validate_action_log(action_log: Array) -> bool:
	if action_log.size() > ACTION_LOG_LIMIT:
		return false
	for raw_entry in action_log:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return false
		var entry: Dictionary = raw_entry
		for field in ["kind", "title", "message"]:
			if not _is_string(entry.get(field)):
				return false
		if not _is_int(entry.get("year")) or not _is_int(entry.get("month")):
			return false
		if int(entry["year"]) < INITIAL_YEAR or int(entry["year"]) > END_YEAR:
			return false
		if int(entry["month"]) < 1 or int(entry["month"]) > 12:
			return false
	return true


static func _validate_selected_region(region_id: Variant) -> bool:
	return _is_string(region_id) and (str(region_id).is_empty() or REGION_IDENTITY.is_valid_id(str(region_id)))


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _is_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING


static func _is_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL
