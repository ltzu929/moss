## 随机事件导演领域服务
## 根据战略导演快照、事件窗口和冷却记录筛选并抽取随机事件。
class_name RandomEventDirector
extends RefCounted


## 返回满足年份、压力、主导轴和冷却条件的随机事件候选。
func collect_candidates(
	events: Array,
	snapshot: Dictionary,
	triggered_years: Dictionary
) -> Array:
	var candidates: Array = []
	var year: int = int(snapshot.get("year", 0))
	var pressure_score: int = int(snapshot.get("pressure_score", 0))
	var dominant_axis := str(snapshot.get("dominant_axis", "none"))

	for event in events:
		if not event is RandomEvent:
			continue
		var random_event: RandomEvent = event as RandomEvent
		if random_event.event_id == "":
			continue
		if year < random_event.earliest_year or year > random_event.latest_year:
			continue
		if pressure_score < random_event.min_pressure_score:
			continue
		if random_event.min_pressure_score > 0 and not _axis_matches(
			random_event.pressure_axes,
			dominant_axis
		):
			continue
		if _is_on_cooldown(random_event, year, triggered_years):
			continue
		candidates.append(random_event)
	return candidates


## 使用整数种子从候选池按权重抽取一个事件。
func select_event(candidates: Array, rng_seed: int) -> Resource:
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0] as Resource

	var total_weight := 0
	for candidate in candidates:
		if candidate is RandomEvent:
			total_weight += maxi(1, (candidate as RandomEvent).weight)
	if total_weight <= 0:
		return candidates[0] as Resource

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var roll := rng.randi_range(1, total_weight)
	var cursor := 0
	for candidate in candidates:
		if not candidate is RandomEvent:
			continue
		cursor += maxi(1, (candidate as RandomEvent).weight)
		if roll <= cursor:
			return candidate as Resource
	return candidates.back() as Resource


func _axis_matches(pressure_axes: Array[String], dominant_axis: String) -> bool:
	if pressure_axes.is_empty():
		return true
	if "any" in pressure_axes:
		return true
	if dominant_axis in pressure_axes:
		return true
	return dominant_axis == "none" and "stable" in pressure_axes


func _is_on_cooldown(
	event: RandomEvent,
	year: int,
	triggered_years: Dictionary
) -> bool:
	if event.cooldown_years <= 0:
		return false
	if not triggered_years.has(event.event_id):
		return false
	var last_year: int = int(triggered_years.get(event.event_id, -9999))
	return year - last_year < event.cooldown_years
