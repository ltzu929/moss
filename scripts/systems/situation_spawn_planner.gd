## 随机局势生成算法服务。
## 只消费显式模板、地区、冷却、事实和资源快照，不持有场景树或活跃集合。
class_name SituationSpawnPlanner
extends RefCounted

const BASE_TRIGGER_PER_THOUSAND: int = 120


## 根据一次已经完成的随机抽样判断本月是否进入候选生成阶段。
func should_start(trigger_roll: int) -> bool:
	return trigger_roll >= 1 and trigger_roll <= BASE_TRIGGER_PER_THOUSAND


## 构建确定顺序的局势候选；模板和地区的输入顺序就是候选顺序。
func build_candidates(
	templates: Array[SituationData],
	sectors: Array[SectorData],
	active_regions: Dictionary,
	repeat_cooldowns: Dictionary,
	year: int,
	month: int,
	facts: Dictionary,
	current_cpu: int,
	current_energy: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if month < 1 or month > 12:
		return candidates
	for data in templates:
		if data == null or not is_template_eligible(templates, data.situation_id, year, facts):
			continue
		for sector in sectors:
			if sector == null or not is_region_eligible(data, sector.region_id):
				continue
			if sector.order < data.minimum_region_order or sector.hope < data.minimum_region_hope:
				continue
			if active_regions.has(sector.region_id):
				continue
			var repeat_key := cooldown_key(data.situation_id, sector.region_id)
			if int(repeat_cooldowns.get(repeat_key, 0)) > 0:
				continue
			var weight := data.base_weight + calculate_risk_weight(
				data,
				sector,
				current_cpu,
				current_energy
			)
			candidates.append(
				{
					"data": data,
					"region_id": sector.region_id,
					"weight": maxi(1, weight),
				}
			)
	return candidates


## 按候选权重和外部提供的随机值选择一个候选，避免服务接管 RNG 所有权。
func pick_candidate(candidates: Array[Dictionary], roll: int) -> Dictionary:
	var total_weight := get_total_weight(candidates)
	if candidates.is_empty() or roll < 1 or roll > total_weight:
		return {}
	var cursor := 0
	for candidate in candidates:
		cursor += int(candidate.get("weight", 0))
		if roll <= cursor:
			return candidate
	return {}


func get_total_weight(candidates: Array[Dictionary]) -> int:
	var total_weight := 0
	for candidate in candidates:
		total_weight += int(candidate.get("weight", 0))
	return total_weight


## 按稳定 ID 查询模板是否满足年份与历史事实门槛。
func is_template_eligible(
	templates: Array[SituationData],
	situation_id: String,
	year: int,
	facts: Dictionary = {}
) -> bool:
	var data := _get_template(templates, situation_id)
	if data == null or year < data.min_year or year > data.max_year:
		return false
	if data.required_any_facts.is_empty():
		return true
	for fact_key_variant in data.required_any_facts:
		var fact_key := str(fact_key_variant)
		if not facts.has(fact_key):
			continue
		var allowed_values: Array = data.required_any_facts[fact_key_variant]
		if allowed_values.is_empty() or facts[fact_key] in allowed_values:
			return true
	return false


func is_region_eligible(data: SituationData, region_id: String) -> bool:
	return data.eligible_regions.is_empty() or region_id in data.eligible_regions


## 根据地区状态和当前资源计算候选风险权重。
func calculate_risk_weight(
	data: SituationData,
	sector: SectorData,
	current_cpu: int,
	current_energy: int
) -> int:
	if data == null or sector == null:
		return 0
	var low_order := maxi(0, 50 - sector.order)
	var low_hope := maxi(0, 50 - sector.hope)
	var low_cpu := maxi(0, 60 - current_cpu)
	var low_energy := maxi(0, 80 - current_energy)
	var high_order := maxi(0, sector.order - 50)
	var high_hope := maxi(0, sector.hope - 50)
	var high_authority := maxi(0, sector.authority - 50)
	var weighted_total := (
		low_order * data.low_order_weight
		+ low_hope * data.low_hope_weight
		+ low_cpu * data.low_cpu_weight
		+ low_energy * data.low_energy_weight
		+ high_order * data.high_order_weight
		+ high_hope * data.high_hope_weight
		+ high_authority * data.high_authority_weight
	)
	return int(float(weighted_total) / 10.0)


func cooldown_key(situation_id: String, region_id: String) -> String:
	return "%s|%s" % [situation_id, region_id]


func _get_template(
	templates: Array[SituationData],
	situation_id: String
) -> SituationData:
	for data in templates:
		if data != null and data.situation_id == situation_id:
			return data
	return null
